#!/usr/bin/env bash
# Essai ponctuel : rejeu_entree refuse-t-il un TAG dont seuls les journaux de s1.sh (amorce, m3_reseau) sont présents ?
# Bac à sable dans <dossier-neuf> (CONFIANCE_DIR et R du bac) ; rien d'écrit dans le dépôt ni sous ~/.cache ; un TAG par cas.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m5b-rejeu-essai-amorce.sh <dossier-neuf>
# shellcheck disable=SC1090,SC2034  # script sourcé (chemin variable) ; R lu par rejeu_entree
set -uo pipefail
export LC_ALL=C
B=${1:?dossier}
[ ! -e "$B" ] || { echo "dossier présent" >&2; exit 2; }
mkdir -p "$B/O/secrets" "$B/O/pki" "$B/O/travail" "$B/resultats"; chmod 700 "$B/O/secrets"
F=poc/bricks/05-rpm-mock/m5b-rejeu.sh
echo "# essai-amorce.sh, $(date -u +%FT%TZ), dépôt $(git rev-parse --short=8 HEAD), script $(sha256sum < "$F" | cut -c1-16)"
un() { # nom tag fichier-à-créer|- : rejeu_entree sous TAG, R du bac ; code et ligne de la garde des journaux
  local r
  [ "$3" = - ] || : > "$B/resultats/$3"
  ( export TAG=$2 CONFIANCE_DIR=$B/O E05=$B/entrees; . "$F"; R=$B/resultats; rejeu_entree ) > "$B/$1.out" 2>&1; r=$?
  echo "$1 (TAG $2, présent : $3) : code $r ; garde : $(grep -F 'journaux de ce TAG présents' "$B/$1.out" | head -n 1)"
}
un X1 essai-x1 -
un X2 essai-x2 essai-x2-amorce.log
un X3 essai-x3 essai-x3-m3_reseau.log
