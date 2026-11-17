"""Copie modifiée de s1.sh : sleep 43200 au lieu de 10800 (décision « Oui, 12 h ») ; ligne df -k /w en tête de SONDE (décision
« Oui, ajoute df ») ; quatre lignes d'en-tête. Assertions.
Usage : python3 -I modifier.py <s1.sh du dépôt> <copie à écrire>"""
import hashlib, sys
src, dst = sys.argv[1:3]
s = open(src, encoding='utf-8').read()
assert hashlib.sha256(s.encode()).hexdigest() == 'ad16fc9909308b2e8f2703114ed0e37e67b73095b9f3b32128890bd4d81a3e63'
a = 'command: ["sleep", "10800"]'
assert s.count(a) == 1 and s.count('10800') == 1 and s.count('43200') == 0
s = s.replace(a, 'command: ["sleep", "43200"]')
ancre = "# Les replis (stockage vfs, mock non root, bootstrap sans image) ne sont pas lancés ici"
assert s.count(ancre) == 1
ajout = ("#   pods        Durée de vie et place (../s1-duree.patch, préparé à sec le 17/11/2026, NON APPLIQUÉ ; décisions du propriétaire\n"
         "#               « Oui, 12 h » et « Oui, ajoute df ») : le conteneur des pods de racine, essais et verrou attend sleep 43200\n"
         "#               au lieu de 10800 (racine a duré 5818 s ; un pod arrêté en plein travail perd /w, restartPolicy Never) ; SONDE\n"
         "#               lit la capacité de /w par df -k, car sous Kata les options de montage de /w ne portent pas de size=\n")
s = s.replace(ancre, ajout + ancre)
m = 'awk "\\$2 == \\"/\\" || \\$2 == \\"/w\\" {print \\"montage \\" \\$2 \\" : \\" \\$3 \\" \\" \\$4}" /proc/mounts\n'
assert s.count(m) == 1, m
s = s.replace(m, m + 'df -k /w | awk "NR == 2 {print \\"capacité de /w : \\" \\$2 \\" kB ; utilisés : \\" \\$3 \\" kB\\"}"\n')
open(dst, 'w', encoding='utf-8').write(s)
print('copie :', hashlib.sha256(s.encode()).hexdigest())
