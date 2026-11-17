#!/usr/bin/env bash
# Banc hors réseau de l'étape verrou_derivee (s1-verrou-derivee.patch), écrit le 17/11/2026 avant tout passage. Ni cluster, ni Zot,
# ni réseau.
# A : insertions seules ; la copie, blocs insérés retirés, redonne le s1.sh du dépôt octet pour octet.
# B : bash -n ; shellcheck : remarques de la copie comparées à celles du dépôt.
# C : partie hôte de la configuration, extraite de la copie et jouée sous set -euo pipefail : configuration de base comparée au
#     sha256 affiché par l'étape image (s1-image.log), six lignes d'écart exactes, texte dérivé comparé à un calcul indépendant.
# D : SONDE_CFG_DERIVEE rendue, /etc/mock et /w remplacés par des dossiers du banc, mock et podman remplacés par des doublures :
#     pull accepté puis refusé ; contrôles de l'hôte (champ et attendu de la copie) rejoués sur les deux sorties.
# E : SONDE_VERROU rendue pour verrou_derivee, comparée au rendu de verrou ; SONDE_REPLI ; SONDE_BOOT rendue pour l'image dérivée
#     (libellés, doublures rpm et podman : listes égales, puis pull refusé).
# F : résumé et comparaison du verrou, sur s1-verrou_brut.json et sur une variante ; JSON cassé ; ordre des blocs de l'étape.
# G : étape connue de lancer, nom du pod.
# H : commandes des sondes neuves présentes dans /usr/bin de racine.tar (image d'essai), diff absent ; dnf-3 et builddep.py dans
#     boot-racine.tar (image dérivée) ; archives lues par leur nom dans T, sha256 de leurs étapes.
# Non couvert : vrai pod, vrai mock, vrai podman, vrai rpm, kubectl, Zot.
# Usage : banc-verrou-derivee.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier de travail, vidé> [dossier T]
set -uo pipefail
export LC_ALL=C
D=$1; S1N=$2; B=$3; TT=${4:-$HOME/.cache/supply-chain-poc/08/travail/s1-05}
S1A=$D/poc/bricks/05-rpm-mock/s1.sh
RES=$D/poc/bricks/05-rpm-mock/resultats
rm -rf -- "${B:?}"; mkdir -p "$B"
echo "# banc-verrou-derivee.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), python3 $(python3 -I -c 'import sys; print(sys.version.split()[0])')"
echo "# s1.sh du dépôt $(sha256sum < "$S1A" | cut -c1-64) ; copie modifiée $(sha256sum < "$S1N" | cut -c1-64)"
ko=0
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
egal() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else nok "$1 : $2 (attendu : $3)"; fi; }
BD=sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6   # digest de boot_image (s1-boot_image.log)

echo "## A : insertions seules"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
python3 -I - "$S1A" "$S1N" <<'PY' || ko=1
import sys
a, n = (open(f, encoding='utf-8').read() for f in sys.argv[1:3])
d = n.index('#   verrou_derivee '); f = n.index('# Les replis (stockage vfs')
e = n.index('# Étape verrou_derivee '); g = n.index('lancer "$PREFIXE" "05 S1" "$@"\n')
r = n[:d] + n[f:e] + n[g:]
print('OK   copie sans les blocs insérés égale au dépôt' if r == a else 'KO   copie sans les blocs insérés différente du dépôt')
print('     en-tête inséré :', n[d:f].count('\n'), 'lignes ; bloc inséré :', n[e:g].count('\n'), 'lignes')
sys.exit(0 if r == a else 1)
PY

echo "## B : syntaxe et shellcheck"
bash -n "$S1N" && ok "bash -n de la copie" || nok "bash -n de la copie"
shellcheck -f gcc "$S1A" 2>/dev/null | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort | uniq -c > "$B/sc-avant.txt"
shellcheck -f gcc "$S1N" 2>/dev/null | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort | uniq -c > "$B/sc-apres.txt"
echo "     remarques shellcheck : dépôt $(awk '{s+=$1} END {print s+0}' "$B/sc-avant.txt"), copie $(awk '{s+=$1} END {print s+0}' "$B/sc-apres.txt")"
diff "$B/sc-avant.txt" "$B/sc-apres.txt" | sed 's/^/     diff shellcheck : /'
egal "remarques shellcheck SC1112 (guillemet typographique) dans la copie" "$(grep -c SC1112 "$B/sc-apres.txt")" 0
egal "remarques shellcheck de niveau error dans la copie" "$(shellcheck -S error -f gcc "$S1N" 2>/dev/null | wc -l)" 0

# Extraits de la copie : variables, MOCK_CFG, fonctions, sondes, fragments de l'étape.
python3 -I - "$S1N" "$B" <<'PY' || ko=1
import re, sys
n = open(sys.argv[1], encoding='utf-8').read(); B = sys.argv[2]
def ecrire(nom, t): open(f'{B}/{nom}', 'w', encoding='utf-8').write(t)
v = [l for l in n.split('\n') if re.match(r'^(VAULT97|BOOT_DIGEST|DEPOT_AMONT|BOOT|CFG|CFG_PRET|DEPOT_DERIVE|CFG_DERIVE|ISOLATION)=', l)]
ecrire('vars.sh', 'REG=sc-stockage.poc.test:5000\n' + '\n'.join(v) + '\n')
i = n.index('MOCK_CFG="'); j = n.index('\n"\n', i) + 3; ecrire('mock-cfg.sh', n[i:j])
for f in ('attendu', 'champ', 'dans'):
    i = n.index(f'\n{f}() '); j = n.index('\n}\n', i) + 3 if n[i:].split('\n')[1].endswith('{') or f == 'dans' else n.index('\n', i + 1) + 1
    ecrire(f'f-{f}.sh', n[i + 1:j])
for s in ('SONDE_CFG_DERIVEE', 'SONDE_REPLI', 'SONDE_VERROU', 'SONDE_BOOT'):
    i = n.index(f"{s}='"); j = n.index("\ntrue'\n", i) + len("\ntrue'\n"); ecrire(f'{s}.txt', n[i + len(s) + 2:j - 2])
k = n.index('etape_verrou_derivee() {')
i = n.index('  printf \'%s\' "$MOCK_CFG" > "$T/$CFG.cfg"', k); j = n.index('  echo "image : $img', i); ecrire('hote-cfg.sh', n[i:j])
i = n.index('  ( attendu "configuration de base du pod', k); j = n.index('    || { pod_retirer "$n"; exit 1; }\n', i)
ecrire('hote-controle.sh', n[i:j] + '    || { echo "pod retiré (doublure)"; exit 1; }\n')
i = n.index('  sed -e "s|@CFG@|$CFG|g" -e "s|@CFG_DERIVE@', k); j = n.index('    | dans "$n" verrou-derivee-cfg\n', i); ecrire('rendu-cfg.sh', n[i:j] + '\n')
i = n.index('  sed -e "s|@CFG_PRET@|$CFG_DERIVE|g"', k); j = n.index('<<<"$SONDE_VERROU" | dans "$n" verrou-derivee\n', i); ecrire('rendu-verrou.sh', n[i:j] + '<<<"$SONDE_VERROU"\n')
i = n.index('  sed -e "s|@CFG@|$CFG_DERIVE|g" -e "s|@BOOT@', k); j = n.index('<<<"$SONDE_BOOT" | dans "$n" verrou-derivee-boot\n', i); ecrire('rendu-boot.sh', n[i:j] + '<<<"$SONDE_BOOT"\n')
p = [m.start() for m in re.finditer(r"<<'PY'", n[k:])]
assert len(p) == 2, p
for nom, x in zip(('resume.py', 'comparaison.py'), p):
    i = n.index('\n', k + x) + 1; j = n.index('\nPY\n', i) + 1; ecrire(nom, n[i:j])
print('     extraits écrits :', len(v), 'variables')
PY
for f in f-attendu.sh f-champ.sh f-dans.sh; do head -c 300 "$B/$f" | head -n 2 | sed "s/^/     $f : /"; done

echo "## C : configuration dérivée, partie hôte"
mkdir -p "$B/t"
cat > "$B/c.sh" <<EOF
set -euo pipefail
. "$B/vars.sh"; . "$B/mock-cfg.sh"; . "$B/f-attendu.sh"
T=$B/t; bd=$BD
c=\$T/\$CFG_DERIVE.cfg
. "$B/hote-cfg.sh"
echo "fin atteinte"
EOF
bash "$B/c.sh" > "$B/c.out" 2>&1; egal "C code (set -euo pipefail)" "$?" 0
sed 's/^/     /' "$B/c.out"
egal "C fin atteinte (diff sans arrêt)" "$(tail -n 1 "$B/c.out")" "fin atteinte"
egal "C configuration de base = sha256 de l'étape image (s1-image.log)" "$(sha256sum < "$B/t/poc-rocky-9.7-x86_64.cfg" | cut -c1-64)" \
  "$(sed -n 's/^configuration de mock : sha256 //p' "$RES/s1-image.log")"
egal "C six lignes d'écart affichées" "$(grep -c '^écart prévu : [<>] ' "$B/c.out")" 6
python3 -I - "$B/t/poc-rocky-9.7-x86_64.cfg" "$B/t/poc-rocky-9.7-derivee-x86_64.cfg" "$BD" <<'PY' || ko=1
import sys
a, d = (open(f, encoding='utf-8').read() for f in sys.argv[1:3]); bd = sys.argv[3]
boot = 'sc-stockage.poc.test:5000/amont/rockylinux/rockylinux@sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2'
r = [("config_opts['root'] = 'poc-rocky-9.7-x86_64'", "config_opts['root'] = 'poc-rocky-9.7-derivee-x86_64'"),
     (f"config_opts['bootstrap_image'] = '{boot}'", f"config_opts['bootstrap_image'] = 'sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@{bd}'"),
     ("config_opts['bootstrap_image_ready'] = False", "config_opts['bootstrap_image_ready'] = True")]
e = a
for x, y in r:
    assert e.count(x + '\n') == 1, x
    e = e.replace(x + '\n', y + '\n')
print('OK   configuration dérivée égale au calcul indépendant' if e == d else 'KO   configuration dérivée différente du calcul indépendant')
sys.exit(0 if e == d else 1)
PY

echo "## D : SONDE_CFG_DERIVEE avec doublures, et contrôles de l'hôte"
( . "$B/vars.sh"; SONDE_CFG_DERIVEE=$(cat "$B/SONDE_CFG_DERIVEE.txt"); bd=$BD; . "$B/rendu-cfg.sh" ) > "$B/cfg-rendue.txt"
egal "marqueurs @ restants" "$(grep -c '@[A-Z_]*@' "$B/cfg-rendue.txt")" 0
egal "image dérivée nommée par digest (pull et inspect)" "$(grep -c "sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@$BD" "$B/cfg-rendue.txt")" 2
sh -n "$B/cfg-rendue.txt" && ok "sh -n de SONDE_CFG_DERIVEE rendue" || nok "sh -n de SONDE_CFG_DERIVEE rendue"
mkdir -p "$B/etc/mock" "$B/w" "$B/bin"
cp "$B/t/poc-rocky-9.7-x86_64.cfg" "$B/t/poc-rocky-9.7-derivee-x86_64.cfg" "$B/etc/mock/"
cat > "$B/bin/mock" <<'R'
#!/bin/sh
# doublure : mock -r <cfg> --debug-config ; lignes écrites comme mock.py:605 à :619 (clés différentes du défaut seulement)
[ "$1 $3" = "-r --debug-config" ] || { echo "doublure mock : appel inattendu $*" >&2; exit 9; }
c="$BANC/etc/mock/$2.cfg"
grep -E "^config_opts\['(root|bootstrap_image|bootstrap_image_ready)'\]" "$c"
echo "config_opts['autre'] = 1"
R
cat > "$B/bin/podman" <<'R'
#!/bin/sh
case "$1 $2" in
  "pull "*) [ -e "$BANC/pull-ko" ] && { echo "doublure : pull refusé"; exit 125; }; echo "doublure : pull"; exit 0 ;;
  "image inspect") [ -e "$BANC/pull-ko" ] && { echo "Error: doublure : image absente"; exit 125; }; echo "image dérivée, inspect : sha256:0 linux/amd64" ;;
  "image mount") echo "$BANC/w/image" ;;
esac
exit 0
R
chmod +x "$B/bin/mock" "$B/bin/podman"
sed -e "s|/etc/mock/|$B/etc/mock/|g" -e "s|/w/|$B/w/|g" "$B/cfg-rendue.txt" > "$B/cfg-banc.txt"
egal "/etc/mock et /w restants hors banc" "$(sed -e "s|$B/etc/mock/|X|g" -e "s|$B/w/|X|g" "$B/cfg-banc.txt" | grep -c -E '/etc/mock/|/w/')" 0
controle() { # libellé : sortie $B/t/verrou-derivee-cfg.log lue par champ et attendu de la copie
  ( set -euo pipefail; . "$B/vars.sh"; . "$B/f-attendu.sh"; . "$B/f-champ.sh"; T=$B/t; c=$T/$CFG_DERIVE.cfg; . "$B/hote-controle.sh"; echo "suite atteinte" ) \
    > "$B/$1.ctl" 2>&1
}
rm -f "$B/pull-ko"; BANC=$B PATH=$B/bin:$PATH sh "$B/cfg-banc.txt" > "$B/t/verrou-derivee-cfg.log" 2>&1; egal "D1 code" "$?" 0
sed 's/^/     /' "$B/t/verrou-derivee-cfg.log"
egal "D1 aucune commande diff dans la sonde (absente de l'image d'essai)" "$(grep -c -w diff "$B/cfg-rendue.txt")" 0
egal "D1 lignes de --debug-config relevées" "$(grep -c '^configuration lue par mock : ' "$B/t/verrou-derivee-cfg.log")" 3
egal "D1 pull" "$(grep -c '^podman pull, image dérivée : rc 0 en [0-9]* s$' "$B/t/verrou-derivee-cfg.log")" 1
controle d1; sed 's/^/     /' "$B/d1.ctl"
egal "D1 contrôles de l'hôte : trois OK" "$(grep -c '^OK   ' "$B/d1.ctl")" 3
egal "D1 contrôles de l'hôte : suite atteinte" "$(tail -n 1 "$B/d1.ctl")" "suite atteinte"
: > "$B/pull-ko"; BANC=$B PATH=$B/bin:$PATH sh "$B/cfg-banc.txt" > "$B/t/verrou-derivee-cfg.log" 2>&1; egal "D2 code" "$?" 0; rm -f "$B/pull-ko"
sed 's/^/     /' "$B/t/verrou-derivee-cfg.log"
egal "D2 pull refusé affiché" "$(grep -c '^podman pull, image dérivée : rc 125 en ' "$B/t/verrou-derivee-cfg.log")" 1
controle d2; sed 's/^/     /' "$B/d2.ctl"
egal "D2 arrêt : KO du pull, pod retiré, suite non atteinte" "$(grep -c "^KO   podman pull de l'image dérivée par le pod : rc 125" "$B/d2.ctl") $(grep -c '^pod retiré (doublure)$' "$B/d2.ctl") $(grep -c 'suite atteinte' "$B/d2.ctl")" "1 1 0"
sed -i 's/^configuration dérivée livrée : sha256 .*/configuration dérivée livrée : sha256 0/' "$B/t/verrou-derivee-cfg.log"
controle d3
egal "D3 configuration livrée altérée : arrêt" "$(grep -c '^KO   configuration dérivée livrée dans le pod' "$B/d3.ctl") $(grep -c 'suite atteinte' "$B/d3.ctl")" "1 0"
egal "doublure mock jamais appelée autrement (D1, D2)" "$(grep -c 'appel inattendu' "$B/t/verrou-derivee-cfg.log")" 0

echo "## E : SONDE_VERROU, SONDE_REPLI et SONDE_BOOT rendues"
( . "$B/vars.sh"; SONDE_VERROU=$(cat "$B/SONDE_VERROU.txt"); . "$B/rendu-verrou.sh" ) > "$B/verrou-rendue.txt"
( . "$B/vars.sh"; sed -e "s|@CFG_PRET@|$CFG_PRET|g" -e "s|@ISO@|$ISOLATION|g" <<<"$(cat "$B/SONDE_VERROU.txt")" ) > "$B/verrou-pret.txt"
egal "marqueurs @ restants (SONDE_VERROU)" "$(grep -c '@[A-Z_]*@' "$B/verrou-rendue.txt")" 0
egal "configuration prête absente" "$(grep -c 'pret' "$B/verrou-rendue.txt")" 0
egal "--no-cleanup-after" "$(grep -c -- '^mock -r poc-rocky-9.7-derivee-x86_64 --isolation=simple --resultdir=/w/res-verrou --calculate-build-dependencies --no-cleanup-after "\$s" > /w/verrou-calc.log 2>&1$' "$B/verrou-rendue.txt")" 1
egal "libellé image dérivée" "$(grep -c '(image dérivée)' "$B/verrou-rendue.txt")" 1
diff "$B/verrou-pret.txt" "$B/verrou-rendue.txt" > "$B/diff-verrou.txt"
egal "lignes changées contre verrou" "$(grep -c '^[<>]' "$B/diff-verrou.txt")" 10
sed 's/^/     /' "$B/diff-verrou.txt"
sh -n "$B/verrou-rendue.txt" && ok "sh -n de SONDE_VERROU rendue" || nok "sh -n de SONDE_VERROU rendue"
sed "s|/w/|$B/w/|g" "$B/SONDE_REPLI.txt" > "$B/repli.txt"
rm -rf "$B/w"; mkdir -p "$B/w/res-verrou"; printf 'x\n' > "$B/w/verrou-srpm.log"; printf 'WARNING buildroot.py:307:  falling back to chroot installation\nfalling back to chroot installation\n' > "$B/w/res-verrou/root.log"; printf 'WARNING: Can'"'"'t work with Podman, falling back to chroot installation: x\n' > "$B/w/verrou-calc.log"
sh "$B/repli.txt" > "$B/repli1.out" 2>&1; egal "SONDE_REPLI code" "$?" 0; sed "s|$B||g; s/^/     /" "$B/repli1.out"
egal "SONDE_REPLI 2, 0 puis 1" "$(sed "s|$B||g" "$B/repli1.out" | tr '\n' '|')" "res-verrou/root.log : 2 ligne(s) de repli sans image|verrou-srpm.log : 0 ligne(s) de repli sans image|verrou-calc.log : 1 ligne(s) de repli sans image|"
rm -f "$B/w/verrou-calc.log"; sh "$B/repli.txt" > "$B/repli2.out" 2>&1
egal "SONDE_REPLI fichier absent" "$(grep -c 'verrou-calc.log : fichier absent ligne(s) de repli sans image$' "$B/repli2.out")" 1
egal "SONDE_REPLI : chemins du pod (/w/)" "$(grep -c '^for f in /w/res-verrou/root.log /w/verrou-srpm.log /w/verrou-calc.log; do$' "$B/SONDE_REPLI.txt")" 1
( . "$B/vars.sh"; SONDE_BOOT=$(cat "$B/SONDE_BOOT.txt"); bd=$BD; . "$B/rendu-boot.sh" ) > "$B/boot-rendue.txt"
egal "SONDE_BOOT : ni brut ni rockylinux:9.7, hors fichiers internes /w/\$2.brut" "$(grep -v -F '/w/$2.brut' "$B/boot-rendue.txt" | grep -c -E 'brut|rockylinux:9\.7')" 0
egal "SONDE_BOOT : fichiers internes /w/\$2.brut (jamais affichés)" "$(grep -c -F '/w/$2.brut' "$B/boot-rendue.txt")" 2
egal "SONDE_BOOT : marqueurs @" "$(grep -c '@[A-Z_]*@' "$B/boot-rendue.txt")" 0
egal "SONDE_BOOT : bootstrap de la configuration dérivée" "$(grep -c '/w/mock/poc-rocky-9.7-derivee-x86_64-bootstrap\*/root' "$B/boot-rendue.txt")" 2
egal "SONDE_BOOT : image dérivée par digest (pull, mount, umount)" "$(grep -c "essais-05/rocky9-bootstrap@$BD" "$B/boot-rendue.txt")" 3
diff <(sed -e "s|@CFG@|poc-rocky-9.7-x86_64|g" "$B/SONDE_BOOT.txt") "$B/boot-rendue.txt" | grep '^>' | sed 's/^/     rendu : /'
sh -n "$B/boot-rendue.txt" && ok "sh -n de SONDE_BOOT rendue" || nok "sh -n de SONDE_BOOT rendue"
BOOTR=$B/w/mock/poc-rocky-9.7-derivee-x86_64-bootstrap/root
cat > "$B/bin/rpm" <<'R'
#!/bin/sh
[ "$1" = --dbpath ] && [ -e "$2/Packages.marque" ] || { echo "doublure rpm : appel inattendu $*" >&2; exit 9; }
printf 'python3-dnf.noarch 0:4.14.0-31.el9.rocky.0.1 s=k1\nrpm.x86_64 0:4.16.1.3-39.el9 s=k1\npython3-dnf-plugins-core.noarch 0:4.3.0-24.el9_7 s=k1\n'
R
chmod +x "$B/bin/rpm"
racines() { rm -rf "$B/w"; mkdir -p "$BOOTR/var/lib/rpm" "$B/w/image/var/lib/rpm"; : > "$BOOTR/var/lib/rpm/Packages.marque"; : > "$B/w/image/var/lib/rpm/Packages.marque"; }
sed -e "s|/w/|$B/w/|g" -e "s|df -k /w |df -k $B/w |" "$B/boot-rendue.txt" > "$B/boot-banc.txt"
racines; rm -f "$B/pull-ko"; BANC=$B PATH=$B/bin:$PATH sh "$B/boot-banc.txt" > "$B/e1.out" 2>&1; egal "E1 code" "$?" 0
sed "s|$B||g; s/^/     /" "$B/e1.out"
egal "E1 aucune ligne « seulement »" "$(grep -c '^seulement' "$B/e1.out")" 0
egal "E1 lignes communes" "$(sed -n 's/^lignes communes : //p' "$B/e1.out")" 3
egal "E1 libellés" "$(grep -c "^podman pull de l'image dérivée : rc 0 en " "$B/e1.out") $(grep -c '^image dérivée : rpm -qa rc 0, 3 ligne(s), stderr 0 ligne(s)$' "$B/e1.out")" "1 1"
racines; : > "$B/pull-ko"; BANC=$B PATH=$B/bin:$PATH sh "$B/boot-banc.txt" > "$B/e2.out" 2>&1; egal "E2 code" "$?" 0; rm -f "$B/pull-ko"
egal "E2 pull refusé, comparaison non faite" "$(grep -c "^podman pull de l'image dérivée : rc 125 " "$B/e2.out") $(grep -c '^comparaison non faite (bootstrap de mock lu : 1 ; image dérivée lue : 0)$' "$B/e2.out")" "1 1"
egal "E2 liste du bootstrap seule" "$(grep -c '^bootstrap de mock, liste : ' "$B/e2.out")" 3

echo "## F : résumé et comparaison du verrou"
python3 -I "$B/resume.py" "$RES/s1-verrou_brut.json" > "$B/f1.out" 2>&1; egal "F1 résumé sur s1-verrou_brut.json" "$?" 0
egal "F1 rpm du buildroot" "$(grep -c '^rpm du buildroot : 222 ;' "$B/f1.out")" 1
python3 -I "$B/comparaison.py" "$RES/s1-verrou_brut.json" "$RES/s1-verrou_brut.json" "$BD" > "$B/f2.out" 2>&1; egal "F2 comparaison à soi-même" "$?" 0
sed 's/^/     /' "$B/f2.out"
egal "F2 pull_digest d'un autre bootstrap signalé" "$(grep -c '^bootstrap, pull_digest égal au digest de boot_image : non (sha256:ee90dc0e' "$B/f2.out")" 1
egal "F2 222 communs, aucun écart" "$(grep -c '^rpm du buildroot (nom, epoch, version, release, arch, sigmd5, url) : ici 222, verrou_brut 222 ; communs 222 ; seulement ici 0 ; seulement dans verrou_brut 0$' "$B/f2.out")" 1
egal "F2 options identiques" "$(grep -c '^options de configuration différentes de verrou_brut : aucune$' "$B/f2.out")" 1
python3 -I - "$RES/s1-verrou_brut.json" "$B/variante.json" "$BD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['bootstrap']['pull_digest'] = sys.argv[3]
d['config']['bootstrap_image'] = 'x'; d['config']['bootstrap_image_ready'] = True
d['buildroot']['rpms'][0]['release'] += '.banc'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
python3 -I "$B/comparaison.py" "$B/variante.json" "$RES/s1-verrou_brut.json" "$BD" > "$B/f3.out" 2>&1; egal "F3 comparaison de la variante" "$?" 0
sed 's/^/     /' "$B/f3.out"
egal "F3 pull_digest égal" "$(grep -c '^bootstrap, pull_digest égal au digest de boot_image : oui$' "$B/f3.out")" 1
egal "F3 options différentes" "$(grep -c '^options de configuration différentes de verrou_brut : bootstrap_image, bootstrap_image_ready$' "$B/f3.out")" 1
egal "F3 un écart de chaque côté" "$(grep -c 'communs 221 ; seulement ici 1 ; seulement dans verrou_brut 1$' "$B/f3.out") $(grep -c '^seulement ici : ' "$B/f3.out") $(grep -c '^seulement dans verrou_brut : ' "$B/f3.out")" "1 1 1"
echo '{"version": ' > "$B/casse.json"
( set -e; python3 -I "$B/comparaison.py" "$B/casse.json" "$RES/s1-verrou_brut.json" "$BD" >/dev/null 2>&1 || echo "comparaison avec verrou_brut en échec : rc $?" ) > "$B/casse.out"
egal "JSON cassé : échec signalé, étape poursuivie" "$(cat "$B/casse.out")" "comparaison avec verrou_brut en échec : rc 1"
egal "résumé et comparaison non fatals dans la copie" "$(grep -c -E "<<'PY' \|\| echo \"(résumé du verrou|comparaison avec verrou_brut) en échec : rc \\\$\?\"$" <(sed -n '/^etape_verrou_derivee() {$/,/^}$/p' "$S1N"))" 2
python3 -I - "$S1N" <<'PY2' || ko=1
import sys
n = open(sys.argv[1], encoding='utf-8').read(); k = n.index('etape_verrou_derivee() {'); z = n.index('\n}\n', k)
o = [n.index(x, k) for x in ('attendu "configuration dérivée : racine', 'pod_demarrer "$n"', 'livrer "$n" "/etc/mock/$CFG_DERIVE.cfg"',
     '| dans "$n" verrou-derivee-cfg\n', '( attendu "configuration de base du pod', '| dans "$n" verrou-derivee\n',
     'dans "$n" verrou-derivee-repli', '| dans "$n" verrou-derivee-boot', '-verrou_derivee-mock.log" || true',
     "<<'PY' || echo \"résumé", "<<'PY' || echo \"comparaison", 'pod_retirer "$n"\n}')]
b = o == sorted(o) and o[-1] < z
print('OK   ordre : configuration, pod, livraison, contrôle, sonde, repli, SONDE_BOOT, journaux, résumé, comparaison, retrait'
      if b else 'KO   ordre des blocs de etape_verrou_derivee : %s' % o)
sys.exit(0 if b else 1)
PY2

echo "## G : étape connue de lancer"
egal "fonction etape_verrou_derivee" "$(grep -c '^etape_verrou_derivee() {$' "$S1N")" 1
egal "nom du pod conforme (minuscules, chiffres, tirets)" "$(grep -o 'n=s1-05-verrou-derivee ' "$S1N" | grep -c -E '^n=[a-z0-9-]+ $')" 1
egal "fonctions etape_ : celles du dépôt plus une" "$(grep -c '^etape_[a-z0-9_]*() {$' "$S1N")" "$(($(grep -c '^etape_[a-z0-9_]*() {$' "$S1A") + 1))"
echo "## H : commandes dans l'image d'essai, dnf-3 et builddep dans l'image dérivée"
egal "racine.tar (image d'essai), sha256 de l'étape racine" "$(sha256sum < "$TT/racine.tar" | cut -c1-64)" d7433a050469836de7317de87f2421d3bc7eaa52052cf422518809e276a94a9d
tar -tf "$TT/racine.tar" > "$B/racine.liste"
egal "commandes de SONDE_CFG_DERIVEE et SONDE_REPLI absentes de /usr/bin" "$(for c in sha256sum cut grep sed mock date podman tail; do grep -q -x "./usr/bin/$c" "$B/racine.liste" || echo "$c"; done | tr '\n' ' ')" ""
egal "diff absent de l'image d'essai (raison du contrôle par sha256)" "$(grep -c -x './usr/bin/diff' "$B/racine.liste")" 0
egal "boot-racine.tar (image dérivée), sha256 de boot_racine" "$(sha256sum < "$TT/boot-racine.tar" | cut -c1-64)" 8ae17f92b27377fff20009d0a88740b1bf9045d533f0506949d6e209c970f1f2
tar -tf "$TT/boot-racine.tar" > "$B/boot-racine.liste"
egal "image dérivée : /usr/bin/dnf-3 (dnf4_command de mock)" "$(grep -c -x './usr/bin/dnf-3' "$B/boot-racine.liste")" 1
egal "image dérivée : greffon builddep" "$(grep -c -x './usr/lib/python3.9/site-packages/dnf-plugins/builddep.py' "$B/boot-racine.liste")" 1
if [ $ko = 0 ]; then echo "# bilan : tenu, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; else echo "# bilan : NON TENU, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
exit $ko
