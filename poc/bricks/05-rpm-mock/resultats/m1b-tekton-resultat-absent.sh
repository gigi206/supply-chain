#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# M1b, choix 2 : sort d'un résultat objet déclaré mais non écrit, lu dans la source de Tekton Pipelines v1.15.5 et de
# Chains v0.29.9 (copie locale). Téléchargement de trois fichiers source au tag, sha256 relevés, lecture par grep et sed.
# Rien n'est exécuté depuis ces fichiers.
set -euo pipefail
S=$HOME/.cache/supply-chain-poc/05/tekton-v1.15.5-source
C=$HOME/.cache/supply-chain-poc/08c/sources/chains
echo "# m1b-tekton-resultat-absent.sh, début $(date -u +%Y-%m-%dT%H:%M:%SZ)"
for f in pkg/reconciler/taskrun/validate_taskrun.go pkg/entrypoint/entrypointer.go pkg/pod/status.go; do
  if [ ! -s "$S/$f" ]; then
    mkdir -p "$(dirname "$S/$f")"
    curl -fsS --proto =https -o "$S/$f.part" "https://raw.githubusercontent.com/tektoncd/pipeline/v1.15.5/$f"
    mv "$S/$f.part" "$S/$f"
    echo "téléchargé : $f"
  fi
  echo "$f : $(wc -c < "$S/$f") octets, sha256 $(sha256sum < "$S/$f" | cut -c1-64)"
done
echo "Chains : $(git -C "$C" describe --tags), signable.go sha256 $(sha256sum < "$C/pkg/artifacts/signable.go" | cut -c1-64)"

V=$S/pkg/reconciler/taskrun/validate_taskrun.go
echo; echo "## validate_taskrun.go : fonctions qui touchent aux résultats"
grep -n 'func validateTaskRunResults\|func mismatchedTypesResults\|func missingKeysofObjectResults\|range tr.Status.Results\|range specResults\|range results\b' "$V" || true
for fn in validateTaskRunResults mismatchedTypesResults missingKeysofObjectResults findMissingKeys; do
  n=$(grep -n "^func $fn" "$V" | cut -d: -f1) || true
  [ -n "$n" ] || { echo "fonction $fn absente"; continue; }
  echo; echo "### $fn (ligne $n)"
  awk -v n="$n" 'NR>=n { print NR": "$0; if (NR>n && $0 ~ /^}/) exit }' "$V"
done

E=$S/pkg/entrypoint/entrypointer.go
echo; echo "## entrypointer.go : lecture des fichiers de résultats"
grep -n 'func (e Entrypointer) readResultsFromDisk\|IsNotExist\|os.ReadFile\|ErrNotExist' "$E" || true
n=$(grep -n 'func (e Entrypointer) readResultsFromDisk' "$E" | cut -d: -f1) || true
[ -z "$n" ] || awk -v n="$n" 'NR>=n { print NR": "$0; if (NR>n && $0 ~ /^}/) exit }' "$E"

P=$S/pkg/pod/status.go
echo; echo "## status.go : résultats manquants"
grep -n -i 'missing\|not found\|absent' "$P" | grep -i result || echo "aucune ligne « missing / not found » liée aux résultats"

echo; echo "## Chains v0.29.9 : isStructuredResult"
n=$(grep -n '^func isStructuredResult' "$C/pkg/artifacts/signable.go" | cut -d: -f1)
awk -v n="$n" 'NR>=n { print NR": "$0; if (NR>n && $0 ~ /^}/) exit }' "$C/pkg/artifacts/signable.go"
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
