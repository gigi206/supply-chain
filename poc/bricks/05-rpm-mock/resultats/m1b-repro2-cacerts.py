# Brique 05, M1b, point 1 A, second banc : lit deux magasins Java (format JKS : magic 0xFEEDFEED) et les compare champ par champ :
# entrées (alias, horodatage, type et sha256 du certificat) et empreinte finale. Si le format n'est pas JKS, imprime le magic et
# s'arrête. Lecture seule ; code 0 : c'est une mesure.
import datetime, hashlib, struct, sys
from collections import Counter


def lit(p):
    d = open(p, 'rb').read(); o = 0
    def u(n, f):
        nonlocal o
        v = struct.unpack('>' + f, d[o:o + n])[0]; o += n; return v
    def utf():
        nonlocal o
        n = u(2, 'H'); s = d[o:o + n].decode('utf-8'); o += n; return s
    m = u(4, 'I')
    if m != 0xFEEDFEED:
        return {'magic': hex(m), 'taille': len(d)}
    v, n = u(4, 'I'), u(4, 'I'); e = []
    for _ in range(n):
        t = u(4, 'I')
        assert t == 2, f'entrée de type {t} : non lue par ce script'
        a = utf(); ts = u(8, 'Q'); ty = utf(); ln = u(4, 'I'); c = d[o:o + ln]; o += ln
        e.append((a, ts, ty, hashlib.sha256(c).hexdigest()))
    return {'magic': hex(m), 'version': v, 'entrées': e, 'empreinte': d[o:].hex(), 'taille': len(d), 'reste': len(d) - o - 20}


j1, j2 = lit(sys.argv[1]), lit(sys.argv[2])
print(f'cacerts : magic {j1["magic"]} et {j2["magic"]} ; tailles {j1["taille"]} et {j2["taille"]}')
if 'entrées' in j1 and 'entrées' in j2:
    e1, e2 = j1['entrées'], j2['entrées']
    print(f'version {j1["version"]} et {j2["version"]} ; entrées {len(e1)} et {len(e2)} ; octets après l\'empreinte : {j1["reste"]} et {j2["reste"]}')
    c = Counter()
    for x, y in zip(e1, e2):
        for i, k in enumerate(('alias', 'horodatage', 'type', 'certificat')):
            c[k] += x[i] != y[i]
    print('entrées différentes, par champ : ' + ', '.join(f'{k} {n}' for k, n in c.items()))
    for j, e in (('1', e1), ('2', e2)):
        ts = sorted({x[1] for x in e})
        print(f'horodatages de {j} : {len(ts)} valeur(s) distincte(s), de {datetime.datetime.fromtimestamp(ts[0] / 1000, datetime.timezone.utc):%FT%T.%f}Z '
              f'à {datetime.datetime.fromtimestamp(ts[-1] / 1000, datetime.timezone.utc):%FT%T.%f}Z')
    print(f'empreinte finale égale : {j1["empreinte"] == j2["empreinte"]}')
