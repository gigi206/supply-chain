#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b, pod_d (19/11/2026) : deux lectures, sans rien extraire sur disque.
# 1. Mode de ./proc dans la couche amont 812c4412 de l'image rockylinux 9.7 (manifeste ee90dc0e), lue dans le cache OCI local,
#    pour savoir d'où vient le ./proc en 755 de boot-racine.tar de S1.
# 2. Comptes de etc/passwd de la référence a8 dont l'uid est 50 ou plus (lastlog de pod_d : 17 520 octets = 60 × 292, soit
#    un enregistrement jusqu'à l'uid 59), et compte de uid 59. Seuls nom, uid, gid et shell sont écrits (pas de champ mot de passe).
# Lecture seule, hors cluster.
set -euo pipefail
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256
C=812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09
BANC=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z
echo "# m1b-pod_d-origines.sh, début $(date -u +%FT%TZ)"
echo "couche $C : sha256 recalculé $(sha256sum < "$O/$C" | cut -c1-64)"
python3 -I - "$O/$C" "$BANC/archives/a8.tar" <<'EOF'
import sys, tarfile
with tarfile.open(sys.argv[1], 'r:gz') as t:
    for m in t:
        if m.name.lstrip('./').rstrip('/') == 'proc':
            print(f'couche amont : {m.name} type {m.type.decode()} mode {oct(m.mode)}')
            break
    else:
        print('couche amont : proc absent')
with tarfile.open(sys.argv[2], 'r:') as t:
    f = t.extractfile('./etc/passwd').read().decode()
for l in f.splitlines():
    c = l.split(':')
    if len(c) >= 7 and int(c[2]) >= 50 and int(c[2]) < 65534:
        print(f'a8 etc/passwd : {c[0]} uid {c[2]} gid {c[3]} shell {c[6]}')
print('a8 etc/passwd, uid 59 : ' + (', '.join(l.split(':')[0] for l in f.splitlines() if l.split(':')[2:3] == ['59']) or 'aucun'))
print(f'60 × 292 = {60 * 292}')
EOF
echo "# fin $(date -u +%FT%TZ)"
