#!/usr/bin/env bash
# Brique 08 : correctif v3 de kyverno/kyverno#18525 = correctif v2 dont les deux fichiers de tests sont regroupés en un seul
# (tsa_cert_chain_test.go, regrouper-tests.py), sans changer la logique des tests ni le code ; mesuré sur main (b2e65e2) et sur la
# PR 18533 (04385c77). Décision du propriétaire « PR directe » (15/11/2026) ; lancement sur accord nommé. Local seulement,
# GOPROXY=off : rien publié, rien lu ni écrit dans le cluster, Zot ou les VM. Prédictions G0 à G7 :
# poc/bricks/08-trust-plane/resultats/kyverno-correctif-v3-predictions.md
# Usage (racine du dépôt) : bash poc/bricks/08-trust-plane/kyverno-correctif/regrouper-tests.sh <répertoire des journaux>
set -uo pipefail
export LC_ALL=C
M=b2e65e2fa88f8ff8bfb0a6351712433d6b14796d
R=04385c77395d3aea22bc1fd11e5e31cf049b00ca
here=$(cd "$(dirname "$0")" && pwd)
V2=$here/correctif-v2-final.patch
GEN=$here/regrouper-tests.py
REF=$here/mesure-18533/m5-paquet-detail.log
J=${1:?répertoire des journaux}
mkdir -p "$J" && J=$(cd "$J" && pwd) || exit 1
K=$HOME/.cache/supply-chain-poc/08/kyverno-correctif
WM=$K/main-b2e65e2
WR=$K/pr-18533-v3
PKG=./pkg/image/verifiers/ivpol/cosign/
g=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.27.3.linux-amd64
export GOROOT=$g PATH=$g/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPROXY=off GOSUMDB=sum.golang.org \
  GOMODCACHE=$K/gomodcache GOCACHE=$K/gocache GOPATH=$K/gopath GOENV=off GOTELEMETRY=off CGO_ENABLED=1
unset GOPRIVATE GONOSUMDB GONOSUMCHECK GOINSECURE GITHUB_TOKEN
h() { echo "== $1, $(date -u +%T) UTC"; }
NOS='Test(CertificateAttestor_TSACertChain_SigstoreBundle|KeyAttestor_TSACertChain_V2Signature|KeyAttestor_TSACertChain_SeparateRepository|CertificateWithChainAttestor_TSACertChain_SigstoreBundle|KeyAttestor_TSACertChain_TwoTimestampedAttestations|KeyAttestor_TSACertChain_SigstoreBundle|BuildCheckOpts_KeyBased_TSACertChain_TrustedMaterial|KeyAttestor_TSACertChainWithoutRoot_SigstoreBundle|CheckOptions_CertificateBased_TSACertChain_Unchanged)'
passes() { grep -E -o -- "--- PASS: ${NOS}(/[^ ]*)? " "$1" | sed 's/ $//' | sort; }   # nos tests et sous-tests passés
grep -q -- '--- PASS' "$REF" || { echo "KO   référence absente : $REF"; exit 1; }
passes "$REF" > "$J/reference-passes.txt"

{ h "G0 départ : arbre main-b2e65e2 à ${M:0:12} avec le correctif v2"
cd "$WM" || exit 1
[ "$(git rev-parse HEAD)" = "$M" ] && echo "OK   tête $M" || { echo "KO   tête $(git rev-parse HEAD)"; exit 1; }
git apply -R --check "$V2"; rc=$?; echo "correctif v2 présent (applicable à l'envers) : code $rc"; [ "$rc" = 0 ] || exit 1
git status --porcelain
git diff HEAD -- "$PKG/opts.go" "$PKG/verifier.go" > "$J/v2-code.diff"
echo "référence : $(wc -l < "$J/reference-passes.txt") PASS de nos tests dans $(basename "$REF")"
} > "$J/g0-depart.log" 2>&1 || { cat "$J/g0-depart.log"; exit 1; }
cd "$WM" || exit 1

{ h "G1 regroupement"
python3 -I "$GEN" "$WM/$PKG"; rc=$?; echo "regrouper-tests.py : code $rc"
ls "$PKG"/tsa_*_test.go
} > "$J/g1-regroupement.log" 2>&1

{ h "G2 gofmt et go vet"
echo "gofmt -l : [$(gofmt -l "$PKG/tsa_cert_chain_test.go")]"
go vet "$PKG"; rc=$?; echo "go vet : code $rc"
} > "$J/g2-gofmt-vet.log" 2>&1

{ h "G3 correctif v3 (diff contre ${M:0:12})"
git add -A -- "$PKG"
git diff --cached HEAD > "$J/correctif-v3.patch"; echo "correctif v3 : $(sha256sum < "$J/correctif-v3.patch" | cut -c1-16), $(grep -c '^diff --git' "$J/correctif-v3.patch") fichiers"
grep '^diff --git' "$J/correctif-v3.patch"
git diff --cached HEAD -- "$PKG/opts.go" "$PKG/verifier.go" > "$J/v3-code.diff"
cmp -s "$J/v2-code.diff" "$J/v3-code.diff" && echo "OK   opts.go et verifier.go identiques à v2" || echo "ÉCART opts.go ou verifier.go différent de v2"
} > "$J/g3-correctif-v3.log" 2>&1

{ h "G4 paquet ivpol/cosign sur main + v3 (verbeux)"
go test -count=1 -v "$PKG" > "$J/g4-paquet-detail.log" 2>&1; rc=$?
grep -E '^(ok|FAIL)' "$J/g4-paquet-detail.log"; echo "code $rc"
echo "--- FAIL : $(grep -c -- '--- FAIL' "$J/g4-paquet-detail.log")"
passes "$J/g4-paquet-detail.log" > "$J/g4-passes.txt"
cmp -s "$J/reference-passes.txt" "$J/g4-passes.txt" && echo "OK   PASS de nos tests identiques à la référence ($(wc -l < "$J/g4-passes.txt"))" \
  || { echo "ÉCART PASS de nos tests différents de la référence"; diff "$J/reference-passes.txt" "$J/g4-passes.txt"; }
h fin; } > "$J/g4-main.log" 2>&1

{ h "G5 PR 18533 + v3 (arbre pr-18533-v3, fusion à trois voies)"
if [ -e "$WR" ]; then echo "KO   $WR existe déjà"; exit 1; fi
git -C "$K/main" worktree add -q --detach "$WR" "$R" </dev/null; rc=$?; echo "worktree add : code $rc"; [ "$rc" = 0 ] || exit 1
cd "$WR" || exit 1
git apply --3way "$J/correctif-v3.patch"; rc=$?; echo "git apply --3way : code $rc"
echo "fichiers en conflit : $(git diff --name-only --diff-filter=U | wc -l)"
go test -count=1 -v "$PKG" > "$J/g5-paquet-detail.log" 2>&1; rc=$?
grep -E '^(ok|FAIL)' "$J/g5-paquet-detail.log"; echo "code $rc"
echo "--- FAIL : $(grep -c -- '--- FAIL' "$J/g5-paquet-detail.log")"
echo "tests de la PR passés : $(grep -c -E '^--- PASS: TestCheckOptions_(InlineTrustedRootWithTlogIgnored|NoInlineTrustedRootWithTlogIgnored|MalformedInlineTrustedRootWithTlogIgnored|EmptyKeyAttestorRejected|CertChainOnlyAttestorStillAllowed|InlineTrustedRootWrappedByTSAOnFastPath) ' "$J/g5-paquet-detail.log")/6"
passes "$J/g5-paquet-detail.log" > "$J/g5-passes.txt"
cmp -s "$J/reference-passes.txt" "$J/g5-passes.txt" && echo "OK   PASS de nos tests identiques à la référence ($(wc -l < "$J/g5-passes.txt"))" \
  || { echo "ÉCART PASS de nos tests différents de la référence"; diff "$J/reference-passes.txt" "$J/g5-passes.txt"; }
h fin; } > "$J/g5-pr-18533.log" 2>&1

{ h "G6 modules et arbres"
for w in "$WM" "$WR"; do echo "$w : GOPROXY=$GOPROXY ; go.mod et go.sum modifiés : $(git -C "$w" status --porcelain -- go.mod go.sum | wc -l)"; git -C "$w" status --porcelain; done
} > "$J/g6-etat.log" 2>&1
grep -h -E '^(== G|OK|KO|ÉCART|code|regrouper|gofmt|go vet|correctif v3|git apply|fichiers en conflit|tests de la PR|--- FAIL|ok |FAIL)' "$J"/g[0-6]-*.log
