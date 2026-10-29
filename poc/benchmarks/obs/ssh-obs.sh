#!/usr/bin/env bash
# Banc A2 : SSH vers l'appliance (clé et known_hosts dédiés, jamais ~/.ssh).
# Usage : poc/benchmarks/obs/ssh-obs.sh [commande…] ; scp : SSH_OBS_SCP=1 ssh-obs.sh <src> <dst>
set -euo pipefail
O=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}
opts=(-o UserKnownHostsFile="$O/ssh/known_hosts" -o StrictHostKeyChecking=yes
      -o IdentitiesOnly=yes -o BatchMode=yes -i "$O/ssh/id_ed25519")
if [[ -n ${SSH_OBS_SCP:-} ]]; then exec scp -q "${opts[@]}" "$@"; fi
exec ssh "${opts[@]}" root@192.168.161.10 "$@"
