#!/usr/bin/env bash
# Brique 08 : SSH vers un nœud, avec la clé et le known_hosts dédiés (clés d'hôte générées par vm.sh).
# Usage : poc/bricks/08-trust-plane/ssh.sh sc-confiance|sc-build|sc-stockage [commande…]
set -euo pipefail
O=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}
case ${1:-} in
  sc-confiance) ip=192.168.161.11 ;;
  sc-build) ip=192.168.161.12 ;;
  sc-stockage) ip=192.168.161.13 ;;
  *) echo "usage : $0 sc-confiance|sc-build|sc-stockage [commande…]" >&2; exit 2 ;;
esac
shift
exec ssh -i "$O/ssh/id_ed25519" -o UserKnownHostsFile="$O/ssh/known_hosts" -o StrictHostKeyChecking=yes \
  -o BatchMode=yes "poc@$ip" "$@"
