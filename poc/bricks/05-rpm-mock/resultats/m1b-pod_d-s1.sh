#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b, pod_d (19/11/2026) : les chemins présents seulement dans l'archive de pod_d (/proc monté dans la racine)
# existent-ils dans les racines de S1 (racine.tar, boot-racine.tar) ? Ne lit que ces deux archives, nommées explicitement,
# sans lister leur dossier ; rien n'est extrait sur disque. Donne aussi le mode de ./proc et la présence de membres sous
# ./proc/. Lecture seule, hors cluster.
set -euo pipefail
T=$HOME/.cache/supply-chain-poc/08/travail/m1b-05
S1=$HOME/.cache/supply-chain-poc/08/travail/s1-05
BANC=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z
echo "# m1b-pod_d-s1.sh, début $(date -u +%FT%TZ)"
for f in "$S1/racine.tar" "$S1/boot-racine.tar"; do
  test -s "$f" && echo "$(basename "$f") : $(stat -c %s "$f") octets" || echo "$(basename "$f") : absent"
done
python3 -I - "$BANC/archives/a8.tar" "$T/p-d.tar" "$S1/racine.tar" "$S1/boot-racine.tar" <<'EOF'
import sys, tarfile
def lire(p):
    r = {}
    with tarfile.open(p, 'r:*') as t:
        for m in t:
            n = m.name[2:] if m.name.startswith('./') else m.name.lstrip('/')
            r[n.rstrip('/')] = m
    return r
a, d = lire(sys.argv[1]), lire(sys.argv[2])
plus = sorted(set(d) - set(a))
for f in sys.argv[3:]:
    s = lire(f); nom = f.rsplit('/', 1)[1]
    pr = s.get('proc')
    print(f'## {nom} : {len(s)} membres ; proc : ' + (f'mode {oct(pr.mode)}' if pr else 'absent')
          + f' ; membres sous proc/ : {sum(1 for x in s if x.startswith("proc/"))}')
    n = 0
    for p in plus:
        m = s.get(p)
        if m:
            n += 1
        print(f'   {p} : ' + (f'présent (type {m.type.decode()}, mode {oct(m.mode)}, taille {m.size})' if m else 'absent'))
    print(f'   bilan {nom} : {n} des {len(plus)} chemins en plus de pod_d présents')
EOF
echo "# fin $(date -u +%FT%TZ)"
