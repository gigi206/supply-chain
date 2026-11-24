#!/usr/bin/env bash
# Brique 20 : kpi-pose.sh sec dans un clone jetable, clés conformes à HEAD puis clé de Chains changée sans commit. Hôte seulement, sans ssh ;
# releve-dates.py lit Zot en anonyme. Usage (racine du dépôt) : mise exec -- bash poc/bricks/20-kpi/essai-cles.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
for j in conformes changees; do [ ! -e "$here/resultats/e7-cles-$j.log" ] || { echo "journal présent : e7-cles-$j.log" >&2; exit 2; }; done
[ ! -e ~/.cache/supply-chain-poc/20/essai-cles ] || find ~/.cache/supply-chain-poc/20/essai-cles -delete
trap 'find ~/.cache/supply-chain-poc/20/essai-cles -delete' EXIT
C=$HOME/.cache/supply-chain-poc/20/essai-cles
git clone -q --local "$here/../../.." "$C" || exit 1
for j in conformes changees; do
  [ "$j" = conformes ] || echo >> "$C/poc/bricks/08-trust-plane/resultats/chains-cle-publique.pem"
  (cd "$C" && bash poc/bricks/20-kpi/kpi-pose.sh sec < /dev/null; echo "code : $?") 2>&1 | sed "s#$HOME#~#g" | tee "$here/resultats/e7-cles-$j.log"
done
