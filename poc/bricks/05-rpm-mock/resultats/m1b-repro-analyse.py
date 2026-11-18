# Brique 05, M1b, point 1 A : analyse en lecture seule des deux arbres laissés par m1b-repro.sh (passage du 18/11/2026,
# 19:44:49 UTC). Classe chaque écart par type d'entrée (répertoire, fichier, lien) et par préfixe de deux composants ; liste
# tous les écarts de contenu ; pour les écarts de seule mtime sur des fichiers ordinaires, compare la mtime à l'heure de chaque
# installation (fichier posé ou réécrit pendant la transaction, ou mtime venue de l'en-tête du rpm). À lancer sous
# unshare --map-auto --map-root-user, comme le comparateur. Arguments : arbre 1, arbre 2, début de l'installation 1 et 2 (epoch).
import os, stat, sys
from collections import Counter

a1, a2, t1, t2 = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])


def releve(racine):
    r = {}
    for d, dirs, fichiers in os.walk(racine):
        for x in dirs + fichiers:
            p = os.path.join(d, x)
            st = os.lstat(p)
            r[os.path.relpath(p, racine)] = st
    return r


def contenu(p):
    import hashlib
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


r1, r2 = releve(a1), releve(a2)
assert set(r1) == set(r2), 'listes de chemins différentes'
genre = {stat.S_IFDIR: 'répertoire', stat.S_IFREG: 'fichier', stat.S_IFLNK: 'lien'}
types, pre, contenus = Counter(), Counter(), []
fichiers_mtime = Counter()
for p in sorted(r1):
    x, y = r1[p], r2[p]
    g = genre.get(stat.S_IFMT(x.st_mode), 'autre')
    c = stat.S_ISREG(x.st_mode) and (x.st_size != y.st_size or contenu(os.path.join(a1, p)) != contenu(os.path.join(a2, p)))
    m = x.st_mtime_ns != y.st_mtime_ns
    autres = (x.st_mode, x.st_uid, x.st_gid) != (y.st_mode, y.st_uid, y.st_gid)
    if not (c or m or autres):
        continue
    types[(g, 'contenu' if c else ('mtime' if m and not autres else 'autre'))] += 1
    pre['/'.join(p.split('/')[:2])] += 1
    if c:
        contenus.append(p)
    elif g == 'fichier' and m:
        k = 'pendant la transaction' if x.st_mtime >= t1 - 1 and y.st_mtime >= t2 - 1 else 'avant la transaction'
        fichiers_mtime[k] += 1
print('écarts par type et par nature : ' + ', '.join(f'{g} {n} {k}' for (g, n), k in sorted(types.items())))
print('écarts par préfixe (deux composants) : ' + ', '.join(f'{k} {n}' for k, n in sorted(pre.items())))
print('fichiers ordinaires à seule mtime différente : ' + ', '.join(f'{k} {n}' for k, n in sorted(fichiers_mtime.items())))
print(f'écarts de contenu : {len(contenus)}')
for p in contenus:
    print(f'     contenu : {p}')
