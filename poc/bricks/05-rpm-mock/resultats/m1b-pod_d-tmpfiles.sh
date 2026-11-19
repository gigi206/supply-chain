#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b, pod_d (19/11/2026) : les membres présents seulement dans l'archive de pod_d sont-ils déclarés dans les
# fichiers tmpfiles.d de l'outillage ? Lit les fichiers usr/lib/tmpfiles.d/*.conf de la référence a8 en mémoire (rien n'est
# extrait sur disque), puis, pour chaque chemin en plus dans p-d.tar, donne la ou les lignes qui le déclarent. Lit aussi les
# scriptlets %post du paquet systemd dans la base rpm de a8 n'est pas possible ici (rpm absent de l'hôte) : seule la
# déclaration est relevée, pas l'appel. Lecture seule, hors cluster.
set -euo pipefail
T=$HOME/.cache/supply-chain-poc/08/travail/m1b-05
BANC=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z
echo "# m1b-pod_d-tmpfiles.sh, début $(date -u +%FT%TZ)"
python3 -I - "$BANC/archives/a8.tar" "$T/p-d.tar" <<'EOF'
import sys, tarfile
def noms(p):
    with tarfile.open(p, 'r:') as t:
        return {m.name for m in t}
a = noms(sys.argv[1]); d = noms(sys.argv[2])
plus = sorted(x[1:] for x in d - a)            # « ./run/lock » -> « /run/lock »
decl = []
with tarfile.open(sys.argv[1], 'r:') as t:
    for m in t:
        if m.name.startswith('./usr/lib/tmpfiles.d/') and m.name.endswith('.conf') and m.isfile():
            for i, l in enumerate(t.extractfile(m).read().decode('utf-8', 'replace').splitlines(), 1):
                c = l.split()
                if len(c) >= 2 and not l.lstrip().startswith('#'):
                    decl.append((c[1], f'{m.name[2:]}:{i}: {l.strip()}'))
print(f'fichiers tmpfiles.d lus dans a8 : {len({x.split(":")[0] for _, x in decl})} ; lignes de déclaration : {len(decl)}')
sans = 0
for p in plus:
    q = [x for c, x in decl if c == p]
    if not q:
        sans += 1
    print(f'   {p} : ' + (' | '.join(q) if q else 'AUCUNE déclaration'))
print(f'chemins en plus : {len(plus)} ; déclarés : {len(plus) - sans} ; non déclarés : {sans}')
EOF
echo "# fin $(date -u +%FT%TZ)"
