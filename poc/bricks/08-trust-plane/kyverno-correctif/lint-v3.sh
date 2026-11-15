#!/usr/bin/env bash
# Brique 08 : lint du correctif v3 (kyverno/kyverno#18525) dans l'arbre main-b2e65e2, avec golangci-lint v2.14.0 (version du
# Makefile de Kyverno, installé le 15/11/2026 par go install vérifié par sum.golang.org, « Oui, installe-le ») et la
# configuration .golangci.yml de Kyverno. Local, GOPROXY=off : rien publié, rien lu ni écrit dans le cluster, Zot ou les VM.
# Prédictions L0 à L5 : poc/bricks/08-trust-plane/resultats/kyverno-correctif-lint-predictions.md
# Usage (racine du dépôt) : bash poc/bricks/08-trust-plane/kyverno-correctif/lint-v3.sh <répertoire des journaux>
set -uo pipefail
export LC_ALL=C
M=b2e65e2fa88f8ff8bfb0a6351712433d6b14796d
here=$(cd "$(dirname "$0")" && pwd)
V3=$here/v3/correctif-v3.patch
J=${1:?répertoire des journaux}
mkdir -p "$J" && J=$(cd "$J" && pwd) || exit 1
K=$HOME/.cache/supply-chain-poc/08/kyverno-correctif
WM=$K/main-b2e65e2
L=$K/outils/bin/golangci-lint
PKG=./pkg/image/verifiers/ivpol/cosign
g=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.27.3.linux-amd64
export GOROOT=$g PATH=$g/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPROXY=off GOSUMDB=sum.golang.org \
  GOMODCACHE=$K/gomodcache GOCACHE=$K/gocache GOPATH=$K/gopath GOENV=off GOTELEMETRY=off CGO_ENABLED=1 GOLANGCI_LINT_CACHE=$K/golangci-cache
unset GOPRIVATE GONOSUMDB GONOSUMCHECK GOINSECURE GITHUB_TOKEN
O="--max-issues-per-linter=0 --max-same-issues=0 --output.text.colors=false"
h() { echo "== $1, $(date -u +%T) UTC"; }
{ h "L0 départ"
echo "golangci-lint $(sha256sum < "$L" | cut -c1-16) : $("$L" version 2>&1 | head -1)"
cd "$WM" || exit 1
[ "$(git rev-parse HEAD)" = "$M" ] && echo "OK   tête $M" || { echo "KO   tête $(git rev-parse HEAD)"; exit 1; }
git diff --cached HEAD > "$J/v3-en-place.patch"
cmp -s "$J/v3-en-place.patch" "$V3" && echo "OK   v3 en place, identique à correctif-v3.patch" || { echo "KO   arbre différent du v3"; exit 1; }
echo ".golangci.yml $(sha256sum < .golangci.yml | cut -c1-16)"
} > "$J/l0-depart.log" 2>&1 || { cat "$J/l0-depart.log"; exit 1; }
cd "$WM" || exit 1
{ h "L1 lint, problèmes nouveaux seulement (--new-from-rev=HEAD), paquet ivpol/cosign"
"$L" run -c .golangci.yml $O --new-from-rev=HEAD "$PKG/..."; rc=$?; echo "code $rc"; h fin; } > "$J/l1-lint-nouveaux.log" 2>&1
{ h "L2 lint complet du paquet ivpol/cosign"
"$L" run -c .golangci.yml $O "$PKG/..."; rc=$?; echo "code $rc"; h fin; } > "$J/l2-lint-paquet.log" 2>&1
{ h "L3 formateurs de la configuration (gci, gofmt, gofumpt, goimports), --diff, paquet"
"$L" fmt -c .golangci.yml --diff "$PKG/..." > "$J/l3-fmt.diff"; rc=$?; echo "code $rc ; lignes de diff : $(wc -l < "$J/l3-fmt.diff")"; h fin; } > "$J/l3-fmt.log" 2>&1
{ h "L4 goimports sur le fichier de tests (sans configuration ; make imports-check passe goimports sur tous les fichiers)"
"$L" fmt --no-config -E goimports --diff "$PKG/tsa_cert_chain_test.go" > "$J/l4-goimports.diff"; rc=$?; echo "code $rc ; lignes de diff : $(wc -l < "$J/l4-goimports.diff")"; h fin; } > "$J/l4-goimports.log" 2>&1
{ h "L5 gofumpt sur le fichier de tests (affiché, exclu par .golangci.yml)"
"$L" fmt --no-config -E gofumpt --diff "$PKG/tsa_cert_chain_test.go" > "$J/l5-gofumpt.diff"; rc=$?; echo "code $rc ; lignes de diff : $(wc -l < "$J/l5-gofumpt.diff")"
echo "arbre inchangé par --diff : $(git status --porcelain | tr '\n' ' ')"; h fin; } > "$J/l5-gofumpt.log" 2>&1
grep -h -E '^(== L|OK|KO|code|golangci-lint|\.golangci|arbre)' "$J"/l[0-5]-*.log
