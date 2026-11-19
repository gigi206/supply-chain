#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b, pod_d (19/11/2026, validation du conseiller) : les 20 chemins présents seulement dans l'archive de pod_d
# existent-ils dans la couche amont 812c4412 de l'image rockylinux 9.7 publiée (cache OCI local) ? La lecture n'est probante
# que si la couche contient usr/lib/tmpfiles.d/systemd.conf : c'est relevé d'abord. Relève aussi le securityContext du pas
# construire de la tâche signée, repris par le pod d'essai (ce qui a permis le montage de /proc). Lecture seule, rien
# n'est extrait sur disque.
set -euo pipefail
h05=$(cd "$(dirname "$0")/.." && pwd)
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256
C=812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09
T=$HOME/.cache/supply-chain-poc/08/travail/m1b-05
BANC=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z
echo "# m1b-pod_d-amont.sh, début $(date -u +%FT%TZ)"
echo "securityContext du pas construire (construire-rpm.signee.yaml) : $(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .securityContext' "$h05/construction/construire-rpm.signee.yaml")"
echo "couche $C : sha256 recalculé $(sha256sum < "$O/$C" | cut -c1-64)"
python3 -I - "$O/$C" "$BANC/archives/a8.tar" "$T/p-d.tar" <<'EOF'
import sys, tarfile
def lire(p, mode):
    with tarfile.open(p, mode) as t:
        return {(m.name[2:] if m.name.startswith('./') else m.name.lstrip('/')).rstrip('/'): m for m in t}
u = lire(sys.argv[1], 'r:gz'); a = lire(sys.argv[2], 'r:'); d = lire(sys.argv[3], 'r:')
print(f'couche amont : {len(u)} membres ; usr/lib/tmpfiles.d/systemd.conf : ' + ('présent' if 'usr/lib/tmpfiles.d/systemd.conf' in u else 'absent')
      + f' ; paquet systemd (usr/lib/systemd/systemd) : ' + ('présent' if 'usr/lib/systemd/systemd' in u else 'absent'))
plus = sorted(set(d) - set(a)); n = 0
for p in plus:
    m = u.get(p)
    if m:
        n += 1
    print(f'   {p} : ' + (f'présent (type {m.type.decode()}, mode {oct(m.mode)}, taille {m.size})' if m else 'absent'))
print(f'bilan couche amont : {n} des {len(plus)} chemins en plus de pod_d présents')
EOF
echo "# fin $(date -u +%FT%TZ)"
