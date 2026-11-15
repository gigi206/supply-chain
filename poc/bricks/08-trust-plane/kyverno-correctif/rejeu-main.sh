#!/usr/bin/env bash
# Brique 08 : rejeu local du correctif v2 (kyverno/kyverno#18525) sur le main de Kyverno du 14/11/2026, sur « Oui, rejoue-le »
# du propriétaire (15/11/2026). Local seulement : rien publié, rien lu ni écrit dans le cluster, Zot ou les VM. Modules hors
# ligne (GOPROXY=off) : go.mod et go.sum sont inchangés depuis 2be1bc3. Prédictions R1 à R6 :
# poc/bricks/08-trust-plane/resultats/kyverno-correctif-rejeu-1511-predictions.md
# Usage (racine du dépôt) : bash poc/bricks/08-trust-plane/kyverno-correctif/rejeu-main.sh <répertoire des journaux>
set -uo pipefail
export LC_ALL=C
N=b2e65e2fa88f8ff8bfb0a6351712433d6b14796d
here=$(cd "$(dirname "$0")" && pwd)
PATCH=$here/correctif-v2-final.patch
REPRO=$here/repro_tsa_test.go.txt
J=${1:?répertoire des journaux}
mkdir -p "$J" && J=$(cd "$J" && pwd) || exit 1   # absolu : le script se place ensuite dans l'arbre de travail (v1 : chemin relatif, 15/11 20:17:46 UTC)
K=$HOME/.cache/supply-chain-poc/08/kyverno-correctif
WT=$K/main-b2e65e2
PKG=./pkg/image/verifiers/ivpol/cosign/
g=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.27.3.linux-amd64
export GOROOT=$g PATH=$g/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPROXY=off GOSUMDB=sum.golang.org \
  GOMODCACHE=$K/gomodcache GOCACHE=$K/gocache GOPATH=$K/gopath GOENV=off GOTELEMETRY=off CGO_ENABLED=1
unset GOPRIVATE GONOSUMDB GONOSUMCHECK GOINSECURE GITHUB_TOKEN
h() { echo "== $1, $(date -u +%T) UTC"; }
{
h "préparation : arbre de travail détaché à ${N:0:12}, $(go version)"
echo "correctif $(sha256sum < "$PATCH" | cut -c1-16), reproducteur $(sha256sum < "$REPRO" | cut -c1-16)"
if [ -e "$WT" ]; then   # laissé par la v1 : repris seulement s'il est à $N et propre
  [ "$(git -C "$WT" rev-parse HEAD)" = "$N" ] && [ -z "$(git -C "$WT" status --porcelain)" ] && echo "arbre de travail existant repris : à ${N:0:12}, propre" \
    || { echo "KO   $WT existe et n'est pas à $N ou pas propre"; exit 1; }
else
  git -C "$K/main" worktree add -q --detach "$WT" "$N" </dev/null; rc=$?
  echo "worktree add : code $rc"; [ "$rc" = 0 ] || exit 1
fi
cd "$WT" || exit 1
[ "$(git rev-parse HEAD)" = "$N" ] && echo "OK   tête $N" || { echo "KO   tête $(git rev-parse HEAD)"; exit 1; }
echo "arbre propre : $(git status --porcelain | wc -l) ligne(s) de status"
} > "$J/l0-preparation.log" 2>&1
[ -d "$WT" ] && cd "$WT" || { cat "$J/l0-preparation.log"; exit 1; }

{ h "R2 reproducteur, main ${N:0:12} intact (seul ajout : repro_tsa_test.go)"
cp "$REPRO" "$PKG/repro_tsa_test.go"
go test -count=1 -run '^TestRepro_KeyAttestor_TSACertChain_TimestampedBundle$' "$PKG"; rc=$?
echo "code $rc"
rm -f "$PKG/repro_tsa_test.go"; h fin; } > "$J/l1-repro-intact.log" 2>&1
echo "nil pointer : $(grep -c 'nil pointer' "$J/l1-repro-intact.log")" >> "$J/l1-repro-intact.log"

{ h "R1 application du correctif v2 final"
git apply --check "$PATCH"; rc=$?; echo "git apply --check : code $rc"
git apply "$PATCH"; rc=$?; echo "git apply : code $rc"
git apply -R --check "$PATCH"; rc=$?; echo "git apply -R --check : code $rc"
git status --porcelain; } > "$J/l2-application.log" 2>&1

{ h "R3 reproducteur, main ${N:0:12} + correctif v2"
cp "$REPRO" "$PKG/repro_tsa_test.go"
go test -count=1 -v -run '^TestRepro_KeyAttestor_TSACertChain_TimestampedBundle$' "$PKG"; rc=$?
echo "code $rc"
rm -f "$PKG/repro_tsa_test.go"; h fin; } > "$J/l3-repro-corrige.log" 2>&1

{ h "R4 paquet ivpol/cosign complet, correctif v2 et ses tests"
go test -count=1 "$PKG"; rc=$?; echo "code $rc"; h fin; } > "$J/l4-paquet-cosign.log" 2>&1

{ h "R5 régression ./pkg/image/... et ./pkg/cel/policies/ivpol/..., correctif v2"
go test -count=1 ./pkg/image/... ./pkg/cel/policies/ivpol/...; rc=$?; echo "code $rc"; h fin; } > "$J/l5-regression.log" 2>&1

{ h "R6 modules et arbre"
echo "GOPROXY=$GOPROXY ; go.mod et go.sum modifiés : $(git status --porcelain -- go.mod go.sum | wc -l)"
git status --porcelain
echo "worktree laissé en place : $WT (pour la PR)"; } > "$J/l6-etat.log" 2>&1
grep -h -E '^(==|OK|KO|code|git apply|nil pointer|ok |FAIL|--- )' "$J"/l*.log
