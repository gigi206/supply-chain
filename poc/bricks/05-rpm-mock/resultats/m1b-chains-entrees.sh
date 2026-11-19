#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# M1b, choix 2 : boucle de Chains v0.29.9 qui lit les résultats *ARTIFACT_INPUTS (copie locale), et code de prefetch-rpm
# signée qui contrôle le manifeste de l'image de bootstrap. Lecture seulement.
set -euo pipefail
C=$HOME/.cache/supply-chain-poc/08c/sources/chains
G=$(git rev-parse --show-toplevel)
echo "# m1b-chains-entrees.sh, début $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Chains : $(git -C "$C" describe --tags), signable.go sha256 $(sha256sum < "$C/pkg/artifacts/signable.go" | cut -c1-64)"
for fn in RetrieveMaterialsFromStructuredResults ExtractStructuredTargetFromResults; do
  n=$(grep -n "^func $fn" "$C/pkg/artifacts/signable.go" | cut -d: -f1)
  echo; echo "### $fn (ligne $n)"
  awk -v n="$n" 'NR>=n { print NR": "$0; if (NR>n && $0 ~ /^}/) exit }' "$C/pkg/artifacts/signable.go"
done
P=$G/poc/bricks/05-rpm-mock/fermeture/prefetch-rpm.signee.yaml
echo; echo "## prefetch-rpm signée ($(sha256sum < "$P" | cut -c1-16)…) : manifeste et résultat"
grep -n 'SOURCE\|manifeste\|ARTIFACT_INPUTS' "$P"
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
