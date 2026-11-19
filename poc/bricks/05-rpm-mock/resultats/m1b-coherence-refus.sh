#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# M1b : le contrôle de cohérence de la base (m1b-builders.sh, prealables) joué sur la pipeline rendue du bootstrap de m1bt4,
# telle quelle puis altérée (annotation base.digest, base.name, couche de construire). Copies dans un dossier neuf (mktemp).
set -euo pipefail
G=$(git rev-parse --show-toplevel)
M=$G/poc/bricks/05-rpm-mock/m1b-builders.sh
P=$HOME/.cache/supply-chain-poc/08/travail/m1bt4-05/pipeline-b.yaml
REG=sc-stockage.poc.test:5000
D=$(mktemp -d "$HOME/.cache/supply-chain-poc/05/m1b-coherence-refus.XXXXXX")
echo "# m1b-coherence-refus.sh, début $(date -u +%Y-%m-%dT%H:%M:%SZ) ; m1b-builders.sh $(sha256sum < "$M" | cut -c1-16)… ; dossier $D"
awk '/annotations et couche de construire = base contrôlée/ {f = 1} f && /<<.PY.$/ {g = 1; next} g && /^PY$/ {exit} g' "$M" > "$D/controle.py"
echo "contrôle extrait : $(wc -l < "$D/controle.py") lignes, sha256 $(sha256sum < "$D/controle.py" | cut -c1-16)…"
cas() { # nom expression-yq
  cp "$P" "$D/$1.yaml"
  [ "$2" = - ] || yq -i "$2" "$D/$1.yaml"
  echo "$1 : $(python3 -I "$D/controle.py" "$D/$1.yaml" "$REG" | cut -c1-120)"
}
cas tel-quel -
cas digest-autre '(.spec.tasks[1].params[] | select(.name == "annotations") | .value) |= sub("ee90dc0e", "ed654c69")'
cas nom-autre '(.spec.tasks[1].params[] | select(.name == "annotations") | .value) |= sub("rockylinux/rockylinux", "rockylinux/autre")'
cas couche-autre '(.spec.tasks[1].params[] | select(.name == "couche") | .value) |= sub("^812c", "99c7")'
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
