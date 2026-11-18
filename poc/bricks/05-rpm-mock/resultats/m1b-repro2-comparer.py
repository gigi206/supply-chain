# Brique 05, M1b, point 1 A, second banc : compare deux archives tar membre par membre (même ordre attendu, --sort=name). Pour
# chaque membre : nom, type, mode, uid, gid, mtime, taille, cible de lien, en-têtes pax, sha256 du contenu. Lecture seule ; code 0.
import hashlib, sys, tarfile
from collections import Counter


def membres(p):
    r = {}
    with tarfile.open(p, 'r:') as t:
        for m in t:
            e = {'type': m.type, 'mode': m.mode, 'uid': m.uid, 'gid': m.gid, 'mtime': m.mtime, 'taille': m.size,
                 'cible': m.linkname, 'pax': tuple(sorted(m.pax_headers.items()))}
            if m.isfile():
                h = hashlib.sha256(); f = t.extractfile(m)
                for b in iter(lambda: f.read(1 << 20), b''):
                    h.update(b)
                e['sha256'] = h.hexdigest()
            r[m.name] = e
    return r


a, b = membres(sys.argv[1]), membres(sys.argv[2])
print(f'membres : {len(a)} et {len(b)}')
seul = sorted(set(a) ^ set(b))
diff = {p: [k for k in a[p] if a[p][k] != b[p].get(k)] for p in sorted(set(a) & set(b))}
diff = {p: c for p, c in diff.items() if c}
print(f'seulement d\'un côté : {len(seul)} ; présents des deux côtés et différents : {len(diff)}')
for p in seul[:50]:
    print(f'     seul : {p}')
for p, c in list(diff.items())[:100]:
    print(f'     écart : {p} ({", ".join(c)})')
print('champs en cause : ' + (', '.join(f'{k} {n}' for k, n in sorted(Counter(k for c in diff.values() for k in c).items())) or 'aucun'))
