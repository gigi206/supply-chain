# Brique 05, M1b, point 1 A, compléments du troisième banc, partie 3 corrigée : la comparaison de m1b-complements3.sh confondait deux
# écritures du même paquet (rpm : « E:NOM-V-R.A » ; journal de dnf : « NOM-E:V-R.A ») et ne tenait pas compte des noms que dnf tronque
# dans sa colonne. Ici : l'écriture de rpm est convertie en celle de dnf, et un nom du journal est accepté s'il est un préfixe du nom
# converti (troncature), compté à part. Lecture seule ; code 0 : c'est une mesure.
# Usage : python3 -I m1b-complements3-ordre.py <complements3-installtime> <dnf-3.log>
import re, sys

it = []
for l in open(sys.argv[1], encoding='utf-8'):
    t, n = l.split()
    m = re.match(r'^(\d+):(.*)-([^-]+)-([^-]+)$', n)
    it.append((int(t), f'{m.group(2)}-{m.group(1)}:{m.group(3)}-{m.group(4)}' if m else n))
it.sort()
tx = []
for l in open(sys.argv[2], encoding='utf-8', errors='replace'):
    m = re.match(r'^\s+Installing\s+:\s+(\S+)\s+(\d+)/(\d+)\s*$', l)
    if m:
        tx.append((int(m.group(2)), m.group(1)))
tx.sort()
assert [r for r, _ in tx] == list(range(1, len(tx) + 1)) and len(tx) == len(it) == 222, (len(tx), len(it))
egal = tronque = 0
autre = []
for i, ((_, a), (_, b)) in enumerate(zip(it, tx)):
    if a == b:
        egal += 1
    elif a.startswith(b):
        tronque += 1
    else:
        autre.append((i + 1, a, b))
print(f'rangs comparés : {len(it)} ; même nom : {egal} ; nom du journal tronqué, préfixe du nom de rpm : {tronque} ; autres : {len(autre)}')
for r, a, b in autre[:20]:
    print(f'     rang {r} : INSTALLTIME {a} ; journal {b}')
print(f'ordre par INSTALLTIME égal à l\'ordre du journal : {not autre}')
