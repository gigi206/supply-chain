#!/usr/bin/env bash
# Brique 05, M1b : mode de ./var/lib/dnf dans a8.tar et a11.tar du banc de 21:25:17 UTC (outils de l'amorce), et dans racine.tar. (18/11/2026)
# Lecture seule, hors ligne : m1b-outil-amorce.log ne dit que « mode » pour l'écart de a11 contre a8.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-outil-amorce-modes.sh > poc/bricks/05-rpm-mock/resultats/m1b-outil-amorce-modes.log 2>&1
set -euo pipefail
export LC_ALL=C
D=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/archives
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05                    # jamais listé : racine.tar seule y est lue
echo "# m1b-outil-amorce-modes.sh, début $(date -u +%FT%TZ)"
for a in "$D/a8.tar" "$D/a11.tar" "$T/racine.tar"; do
  python3 -I -c 'import sys, tarfile; t = tarfile.open(sys.argv[1]); m = t.getmember("./var/lib/dnf"); print(f"{sys.argv[2]} : ./var/lib/dnf mode {m.mode:04o}")' "$a" "$(basename "$a")"
done
echo "# fin $(date -u +%FT%TZ)"
