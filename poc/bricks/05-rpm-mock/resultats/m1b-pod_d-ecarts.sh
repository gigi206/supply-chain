#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b, pod_d (19/11/2026, décision « Mesurer aussi /proc ») : nomme les écarts entre l'archive de pod_d
# ($T/p-d.tar) et la référence a8 du banc de l'amorce. Lecture seule, hors cluster. Pour chaque membre présent d'un seul
# côté, il donne le côté, le type, le mode et la taille ; pour chaque membre présent des deux côtés et différent, il donne
# les champs en cause, puis l'ancienne et la nouvelle valeur de ces champs (sauf le contenu : seulement le sha256).
set -euo pipefail
h05=$(cd "$(dirname "$0")/.." && pwd)
T=$HOME/.cache/supply-chain-poc/08/travail/m1b-05
BANC=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z
echo "# m1b-pod_d-ecarts.sh, début $(date -u +%FT%TZ)"
for f in "$BANC/archives/a8.tar" "$T/p-d.tar"; do
  echo "$(basename "$f") : $(stat -c %s "$f") octets, sha256 $(sha256sum < "$f" | cut -c1-64)"
done
echo "## comparateur du second banc (m1b-repro2-comparer.py)"
python3 -I "$h05/resultats/m1b-repro2-comparer.py" "$BANC/archives/a8.tar" "$T/p-d.tar" 2>&1 | sed 's/^/   /'
echo "## détail par côté"
python3 -I - "$BANC/archives/a8.tar" "$T/p-d.tar" <<'EOF'
import hashlib, sys, tarfile
def membres(p):
    r = {}
    with tarfile.open(p, 'r:') as t:
        for m in t:
            e = {'type': m.type.decode(), 'mode': oct(m.mode), 'uid': m.uid, 'gid': m.gid, 'mtime': m.mtime,
                 'taille': m.size, 'cible': m.linkname, 'pax': tuple(sorted(m.pax_headers.items()))}
            if m.isfile():
                h = hashlib.sha256(); f = t.extractfile(m)
                for b in iter(lambda: f.read(1 << 20), b''):
                    h.update(b)
                e['sha256'] = h.hexdigest()[:16]
            r[m.name] = e
    return r
a, d = membres(sys.argv[1]), membres(sys.argv[2])
for p in sorted(set(d) - set(a)):
    e = d[p]; print(f'   seulement dans p-d : {p} (type {e["type"]}, mode {e["mode"]}, taille {e["taille"]})')
for p in sorted(set(a) - set(d)):
    e = a[p]; print(f'   seulement dans a8 : {p} (type {e["type"]}, mode {e["mode"]}, taille {e["taille"]})')
for p in sorted(set(a) & set(d)):
    c = [k for k in a[p] if a[p][k] != d[p].get(k)]
    if c:
        print(f'   écart : {p} : ' + ' ; '.join(f'{k} {a[p][k]!r} -> {d[p].get(k)!r}' for k in c))
EOF
echo "# fin $(date -u +%FT%TZ)"
