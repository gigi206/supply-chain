#!/usr/bin/env bash
# Banc A2 : compare deux builds collectés (comparer.py) ; sortie dans resultats/comparaison-<A>-<B>.txt.
# Usage (racine du dépôt) : mise run obs:comparer -- build-1 build-2
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
O=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}/builds
a=${1:?libellé A}; b=${2:?libellé B}
{
  echo "# comparer.sh $a $b, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 -I "$here/comparer.py" "$O/$a" "$O/$b" && echo "RÉSULTAT : tous les paquets identiques (rpm hors signature, deb entiers)" \
    || echo "RÉSULTAT : au moins un paquet différent"
} | tee "$here/resultats/comparaison-$a-$b.txt"
