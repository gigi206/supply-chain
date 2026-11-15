#!/usr/bin/env bash
# Brique 08 : mesure locale du correctif v2 (kyverno/kyverno#18525) contre la PR kyverno/kyverno#18533 (tête 04385c77, base 2be1bc3),
# sur « Oui, mesure-le » du propriétaire (15/11/2026). Local seulement : rien publié, rien lu ni écrit dans le cluster, Zot ou les
# VM. Modules hors ligne (GOPROXY=off) : go.mod et go.sum de la PR sont ceux de 2be1bc3. Prédictions M0 à M7 :
# poc/bricks/08-trust-plane/resultats/kyverno-correctif-18533-predictions.md
# Usage (racine du dépôt) : bash poc/bricks/08-trust-plane/kyverno-correctif/mesure-18533.sh <répertoire des journaux>
set -uo pipefail
export LC_ALL=C
N=04385c77395d3aea22bc1fd11e5e31cf049b00ca
here=$(cd "$(dirname "$0")" && pwd)
PATCH=$here/correctif-v2-final.patch
REPRO=$here/repro_tsa_test.go.txt
J=${1:?répertoire des journaux}
mkdir -p "$J" && J=$(cd "$J" && pwd) || exit 1
K=$HOME/.cache/supply-chain-poc/08/kyverno-correctif
WT=$K/pr-18533
PKG=./pkg/image/verifiers/ivpol/cosign/
g=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.27.3.linux-amd64
export GOROOT=$g PATH=$g/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPROXY=off GOSUMDB=sum.golang.org \
  GOMODCACHE=$K/gomodcache GOCACHE=$K/gocache GOPATH=$K/gopath GOENV=off GOTELEMETRY=off CGO_ENABLED=1
unset GOPRIVATE GONOSUMDB GONOSUMCHECK GOINSECURE GITHUB_TOKEN
h() { echo "== $1, $(date -u +%T) UTC"; }
repro() { # libellé journal
  { h "$1"
    cp "$REPRO" "$PKG/repro_tsa_test.go"
    go test -count=1 -v -run '^TestRepro_KeyAttestor_TSACertChain_TimestampedBundle$' "$PKG"; rc=$?
    echo "code $rc"
    rm -f "$PKG/repro_tsa_test.go"; h fin; } > "$J/$2" 2>&1
  echo "nil pointer : $(grep -c 'nil pointer' "$J/$2")" >> "$J/$2"
}
{
h "préparation : arbre de travail détaché à ${N:0:12} (tête de la PR 18533), $(go version)"
echo "correctif $(sha256sum < "$PATCH" | cut -c1-16), reproducteur $(sha256sum < "$REPRO" | cut -c1-16)"
if [ -e "$WT" ]; then
  [ "$(git -C "$WT" rev-parse HEAD)" = "$N" ] && [ -z "$(git -C "$WT" status --porcelain)" ] && echo "arbre de travail existant repris : propre" \
    || { echo "KO   $WT existe et n'est pas à $N ou pas propre"; exit 1; }
else
  git -C "$K/main" worktree add -q --detach "$WT" "$N" </dev/null; rc=$?
  echo "worktree add : code $rc"; [ "$rc" = 0 ] || exit 1
fi
cd "$WT" || exit 1
[ "$(git rev-parse HEAD)" = "$N" ] && echo "OK   tête $N" || { echo "KO   tête $(git rev-parse HEAD)"; exit 1; }
echo "base commune avec 2be1bc3 : $(git merge-base HEAD 2be1bc3fe3b4150501caac2c95ee58039824cdce)"
echo "arbre propre : $(git status --porcelain | wc -l) ligne(s) de status"
} > "$J/m0-preparation.log" 2>&1
[ -d "$WT" ] && cd "$WT" || { cat "$J/m0-preparation.log"; exit 1; }

repro "M1 reproducteur, PR 18533 seule (seul ajout : repro_tsa_test.go)" m1-repro-18533.log

{ h "M2 paquet ivpol/cosign, PR 18533 seule (référence)"
go test -count=1 "$PKG"; rc=$?; echo "code $rc"; h fin; } > "$J/m2-paquet-18533.log" 2>&1

{ h "M3 application du correctif v2 final sur la PR 18533"
git apply --check "$PATCH"; rc=$?; echo "git apply --check : code $rc"
git apply --3way "$PATCH"; rc=$?; echo "git apply --3way : code $rc"
echo "fichiers en conflit : $(git diff --name-only --diff-filter=U | wc -l)"
echo "marqueurs de conflit : $(grep -l -E '^(<<<<<<<|>>>>>>>)' pkg/image/verifiers/ivpol/cosign/*.go | wc -l)"
git status --porcelain
git diff HEAD > "$J/correctif-v2-sur-18533.patch"; echo "diff contre la tête de la PR : $(sha256sum < "$J/correctif-v2-sur-18533.patch" | cut -c1-16)"
} > "$J/m3-application.log" 2>&1

repro "M4 reproducteur, PR 18533 + correctif v2" m4-repro-18533-corrige.log

{ h "M5 paquet ivpol/cosign, PR 18533 + correctif v2 (tests des deux)"
go test -count=1 -v "$PKG" > "$J/m5-paquet-detail.log" 2>&1; rc=$?
grep -E '^(ok|FAIL|---)' "$J/m5-paquet-detail.log" | grep -v -- '--- PASS' ; echo "code $rc"
echo "tests de la PR passés : $(grep -c -E '^--- PASS: TestCheckOptions_(InlineTrustedRootWithTlogIgnored|NoInlineTrustedRootWithTlogIgnored|MalformedInlineTrustedRootWithTlogIgnored|EmptyKeyAttestorRejected|CertChainOnlyAttestorStillAllowed|InlineTrustedRootWrappedByTSAOnFastPath) ' "$J/m5-paquet-detail.log")/6"
echo "tests du correctif passés : $(grep -c -E '^--- PASS: Test(CertificateAttestor_TSACertChain_SigstoreBundle|KeyAttestor_TSACertChain_V2Signature|KeyAttestor_TSACertChain_SeparateRepository|CertificateWithChainAttestor_TSACertChain_SigstoreBundle|KeyAttestor_TSACertChain_TwoTimestampedAttestations|KeyAttestor_TSACertChain_SigstoreBundle|BuildCheckOpts_KeyBased_TSACertChain_TrustedMaterial|KeyAttestor_TSACertChainWithoutRoot_SigstoreBundle|CheckOptions_CertificateBased_TSACertChain_Unchanged) ' "$J/m5-paquet-detail.log")/9"
echo "--- FAIL : $(grep -c -- '--- FAIL' "$J/m5-paquet-detail.log")"
h fin; } > "$J/m5-paquet-18533-corrige.log" 2>&1

{ h "M6 régression ./pkg/image/... et ./pkg/cel/policies/ivpol/..., PR 18533 + correctif v2"
go test -count=1 ./pkg/image/... ./pkg/cel/policies/ivpol/...; rc=$?; echo "code $rc"; h fin; } > "$J/m6-regression.log" 2>&1

{ h "M7 modules et arbre"
echo "GOPROXY=$GOPROXY ; go.mod et go.sum modifiés : $(git status --porcelain -- go.mod go.sum | wc -l)"
git status --porcelain
echo "worktree laissé en place : $WT"; } > "$J/m7-etat.log" 2>&1
grep -h -E '^(==|OK|KO|code|git apply|nil pointer|fichiers en conflit|marqueurs|tests |--- FAIL|ok |FAIL)' "$J"/m*.log
