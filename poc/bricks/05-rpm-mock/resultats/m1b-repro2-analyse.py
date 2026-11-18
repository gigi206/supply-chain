# Brique 05, M1b, point 1 A, second banc : lecture complémentaire des deux arbres (lecture seule ; sous unshare --map-auto
# --map-root-user). (1) Entrées dont la mtime dépasse E, classées selon que leur mtime est égale ou non entre les deux arbres ;
# pour celles à mtime égale : préfixes, plus petite et plus grande mtime. (2) Taille des fichiers de la base rpm (-shm, -wal), que
# la lecture SQLite en immutable=1 ignore. Arguments : arbre 1, arbre 2, E. Code 0 : c'est une mesure.
import datetime, os, stat, sys
from collections import Counter

a1, a2, e = sys.argv[1], sys.argv[2], int(sys.argv[3])


def releve(r):
    x = {}
    for d, ds, fs in os.walk(r):
        for n in ds + fs:
            p = os.path.join(d, n); x[os.path.relpath(p, r)] = os.lstat(p)
    return x


r1, r2 = releve(a1), releve(a2)
eg, di = [], []
for p, s in r1.items():
    if s.st_mtime > e or r2[p].st_mtime > e:
        (eg if s.st_mtime_ns == r2[p].st_mtime_ns else di).append(p)
print(f'au-dessus de E : {len(eg) + len(di)} ; mtime égale entre les arbres : {len(eg)} ; mtime différente : {len(di)}')
g = {stat.S_IFDIR: 'répertoire', stat.S_IFREG: 'fichier', stat.S_IFLNK: 'lien'}
print('mtime égale, par type : ' + ', '.join(f'{k} {n}' for k, n in sorted(Counter(g.get(stat.S_IFMT(r1[p].st_mode), 'autre') for p in eg).items())))
print('mtime égale, par préfixe (trois composants) : ' + ', '.join(f'{k} {n}' for k, n in sorted(Counter('/'.join(p.split('/')[:3]) for p in eg).items())))
if eg:
    m = sorted(r1[p].st_mtime for p in eg)
    f = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime('%FT%TZ')
    print(f'mtime égale : de {f(m[0])} à {f(m[-1])} ; valeurs distinctes : {len(set(m))}')
for r, n in ((a1, '1'), (a2, '2')):
    print(f'base rpm de l\'arbre {n} : ' + ', '.join(f'{x} {os.lstat(os.path.join(r, "var/lib/rpm", x)).st_size} o' for x in sorted(os.listdir(os.path.join(r, 'var/lib/rpm')))))
