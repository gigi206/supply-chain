# Brique 05, M1b, point 1 A (carte de M1b, décision « Oui » du 18/11/2026) : compare deux arbres installés par dnf --installroot.
# Pour chaque chemin relatif : type, mode, uid, gid, taille, mtime (ns), sha256 (fichier ordinaire) ou cible (lien). Imprime les
# chemins présents d'un seul côté et ceux dont un champ diffère, avec les champs en cause, puis un résumé par préfixe. Lecture
# seule ; à lancer dans le même espace de noms utilisateur que l'installation (propriétaires lisibles). Code 0 : c'est une mesure.
import hashlib, os, stat, sys
from collections import Counter


def releve(racine):
    r = {}
    for d, dirs, fichiers in os.walk(racine):
        for x in dirs + fichiers:
            p = os.path.join(d, x)
            s = os.lstat(p)
            e = {'type': stat.S_IFMT(s.st_mode), 'mode': stat.S_IMODE(s.st_mode), 'uid': s.st_uid, 'gid': s.st_gid,
                 'mtime': s.st_mtime_ns}
            if stat.S_ISREG(s.st_mode):
                e['taille'] = s.st_size
                h = hashlib.sha256()
                with open(p, 'rb') as f:
                    for b in iter(lambda: f.read(1 << 20), b''):
                        h.update(b)
                e['sha256'] = h.hexdigest()
            elif stat.S_ISLNK(s.st_mode):
                e['cible'] = os.readlink(p)
            r[os.path.relpath(p, racine)] = e
    return r


def prefixe(p, n=3):
    return '/'.join(p.split('/')[:n])


a, b = releve(sys.argv[1]), releve(sys.argv[2])
print(f'arbre 1 : {len(a)} entrées ; arbre 2 : {len(b)} entrées')
seul1, seul2 = sorted(set(a) - set(b)), sorted(set(b) - set(a))
diff = {}
for p in sorted(set(a) & set(b)):
    c = [k for k in sorted(set(a[p]) | set(b[p])) if a[p].get(k) != b[p].get(k)]
    if c:
        diff[p] = c
print(f'seulement dans 1 : {len(seul1)} ; seulement dans 2 : {len(seul2)} ; présents des deux côtés et différents : {len(diff)}')
for p in seul1[:100]:
    print(f'     seul 1 : {p}')
for p in seul2[:100]:
    print(f'     seul 2 : {p}')
for p, c in list(diff.items())[:300]:
    print(f'     écart : {p} ({", ".join(c)})')
if len(diff) > 300:
    print(f'     … {len(diff) - 300} écarts de plus, non imprimés')
champs = Counter(k for c in diff.values() for k in c)
print('champs en cause : ' + (', '.join(f'{k} {n}' for k, n in sorted(champs.items())) or 'aucun'))
pre = Counter(prefixe(p) for p in list(diff) + seul1 + seul2)
print('écarts par préfixe : ' + (', '.join(f'{k} {n}' for k, n in sorted(pre.items())) or 'aucun'))
hors_mtime = {p: c for p, c in diff.items() if c != ['mtime']}
print(f'écarts autres que la seule mtime : {len(hors_mtime)} ; '
      + ('identiques' if not (diff or seul1 or seul2) else 'arbres différents'))
