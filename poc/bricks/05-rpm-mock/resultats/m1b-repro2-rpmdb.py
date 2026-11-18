# Brique 05, M1b, point 1 A, second banc : compare les bases rpm de deux arbres. (1) Sorties de rpm -qa --xml : en-tête de chaque
# paquet, étiquette par étiquette. (2) Fichiers rpmdb.sqlite (copies) : tables, nombre de lignes, lignes égales ou non, et pour
# Packages, les blobs par hnum. Lecture seule (SQLite ouvert en immutable=1) ; code 0 : c'est une mesure.
import sqlite3, sys
import xml.etree.ElementTree as E
from collections import Counter


def entetes(p):
    t = open(p, encoding='utf-8').read()
    r = {}
    for h in E.fromstring('<r>' + t + '</r>').findall('rpmHeader'):
        g = {x.get('name'): tuple(E.tostring(v, encoding='unicode') for v in x) for x in h.findall('rpmTag')}
        k = '-'.join(''.join(g.get(n, ('?',))) for n in ('Name', 'Version', 'Release', 'Arch'))
        assert k not in r, k
        r[k] = g
    return r


x1, x2 = entetes(sys.argv[1]), entetes(sys.argv[2])
print(f'en-têtes : {len(x1)} et {len(x2)} ; mêmes paquets : {set(x1) == set(x2)}')
diff = Counter(); paq = 0
for k in sorted(set(x1) & set(x2)):
    d = [n for n in sorted(set(x1[k]) | set(x2[k])) if x1[k].get(n) != x2[k].get(n)]
    paq += bool(d); diff.update(d)
print(f'paquets dont l\'en-tête diffère : {paq} ; étiquettes en cause : ' + (', '.join(f'{n} {c}' for n, c in sorted(diff.items())) or 'aucune'))


def ouvre(p):
    return sqlite3.connect(f'file:{p}?immutable=1', uri=True)


b1, b2 = ouvre(sys.argv[3]), ouvre(sys.argv[4])
tables = lambda b: sorted(r[0] for r in b.execute("select name from sqlite_master where type = 'table'"))
print(f'tables : {tables(b1)} ; mêmes tables : {tables(b1) == tables(b2)}')
for t in tables(b1):
    l1 = b1.execute(f'select * from "{t}"').fetchall(); l2 = b2.execute(f'select * from "{t}"').fetchall()
    print(f'     {t} : {len(l1)} et {len(l2)} lignes ; mêmes lignes dans le même ordre : {l1 == l2} ; mêmes ensembles : {sorted(map(repr, l1)) == sorted(map(repr, l2))}')
p1 = dict(b1.execute('select hnum, blob from Packages')); p2 = dict(b2.execute('select hnum, blob from Packages'))
print(f'Packages : mêmes hnum : {set(p1) == set(p2)} ; blobs égaux : {sum(p1[h] == p2.get(h) for h in p1)} sur {len(p1)} ; '
      f'mêmes tailles de blob : {sum(len(p1[h]) == len(p2.get(h, b"")) for h in p1)}')
for n, b in (('1', b1), ('2', b2)):
    print(f'pragmas de la base {n} : page_size {b.execute("pragma page_size").fetchone()[0]}, journal_mode {b.execute("pragma journal_mode").fetchone()[0]}, '
          f'page_count {b.execute("pragma page_count").fetchone()[0]}, freelist_count {b.execute("pragma freelist_count").fetchone()[0]}')
