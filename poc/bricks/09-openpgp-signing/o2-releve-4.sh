#!/usr/bin/env bash
# Brique 09, O2 : quatrième relevé, local et sans réseau. Options --skip et crochets de mmdebstrap 1.5.7-1+deb13u1, lus dans la
# page de manuel installée dans l'amorce Debian (o2/debian-amorce, mmdebstrap installé par debian_amorce), et dans le script
# lui-même : comment garder les .deb des paquets essentiels pour les contrôler. Journal : resultats/o2-releve-4.log.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
A=$HOME/.cache/supply-chain-poc/09/o2/debian-amorce
cd "$HOME/.cache/supply-chain-poc/09"
{
  echo "quatrième relevé O2 commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; mmdebstrap de l'amorce sha256 $(sha256sum < "$A/usr/bin/mmdebstrap" | cut -c1-16)…"
  echo "page de manuel : absente de l amorce slim (premier passage, FileNotFoundError) ; lecture du script seulement"
  echo "## script usr/bin/mmdebstrap : occurrences de essential/unlink et du retrait des .deb"
  grep -n -E "essential/unlink|essential-hook|unlink.*deb|skip.*unlink" "$A/usr/bin/mmdebstrap" | head -12 | cut -c1-200 | sed 's/^/  /'
  echo "quatrième relevé O2 fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | tee "$here/resultats/o2-releve-4.log"
