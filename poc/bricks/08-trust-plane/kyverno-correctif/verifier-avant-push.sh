#!/usr/bin/env bash
# Brique 08 : contrôles d'avant push du commit de la PR (kyverno/kyverno#18525), demandés par le conseiller après la validation du
# message (« Oui, je valide », 15/11/2026) : tests du paquet avec le détecteur de courses (drapeaux de make test-unit), témoin positif
# du lint dans un arbre jetable, relecture de main en lecture publique. Local, GOPROXY=off ; rien publié, rien lu ni écrit dans le
# cluster, Zot ou les VM. Prédictions V0 à V3 : poc/bricks/08-trust-plane/resultats/kyverno-correctif-avant-push-predictions.md
# Usage (racine du dépôt) : bash poc/bricks/08-trust-plane/kyverno-correctif/verifier-avant-push.sh <répertoire des journaux>
set -uo pipefail
export LC_ALL=C
C=1851634f9aff22aa92cbab5a834103dbfba3a81d   # commit v2 de la PR, base b2e65e2
M=b2e65e2fa88f8ff8bfb0a6351712433d6b14796d
J=${1:?répertoire des journaux}
mkdir -p "$J" && J=$(cd "$J" && pwd) || exit 1
K=$HOME/.cache/supply-chain-poc/08/kyverno-correctif
WM=$K/main-b2e65e2
WT=$K/temoin-lint
L=$K/outils/bin/golangci-lint
PKG=./pkg/image/verifiers/ivpol/cosign
g=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.27.3.linux-amd64
export GOROOT=$g PATH=$g/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPROXY=off GOSUMDB=sum.golang.org \
  GOMODCACHE=$K/gomodcache GOCACHE=$K/gocache GOPATH=$K/gopath GOENV=off GOTELEMETRY=off CGO_ENABLED=1 GOLANGCI_LINT_CACHE=$K/golangci-cache
unset GOPRIVATE GONOSUMDB GONOSUMCHECK GOINSECURE GITHUB_TOKEN
O="--max-issues-per-linter=0 --max-same-issues=0 --output.text.colors=false"
h() { echo "== $1, $(date -u +%T) UTC"; }
{ h "V0 départ"
cd "$WM" || exit 1
[ "$(git rev-parse HEAD)" = "$C" ] && echo "OK   commit $C" || { echo "KO   tête $(git rev-parse HEAD)"; exit 1; }
echo "arbre propre : $(git status --porcelain | wc -l) ligne(s) ; $(gcc --version | head -1)"
} > "$J/v0-depart.log" 2>&1 || { cat "$J/v0-depart.log"; exit 1; }
cd "$WM" || exit 1
{ h "V1 paquet ivpol/cosign avec les drapeaux de make test-unit (-race -covermode atomic)"
go test -count=1 -race -covermode atomic -coverprofile "$J/v1-couverture.out" "$PKG/" > "$J/v1-detail.log" 2>&1; rc=$?
grep -E '^(ok|FAIL)' "$J/v1-detail.log"; echo "code $rc"
echo "WARNING: DATA RACE : $(grep -c 'WARNING: DATA RACE' "$J/v1-detail.log")"
h fin; } > "$J/v1-race.log" 2>&1
{ h "V2 témoin positif du lint (arbre jetable temoin-lint au commit $C, défauts volontaires dans opts.go)"
if [ -e "$WT" ]; then echo "KO   $WT existe déjà"; exit 1; fi
git -C "$K/main" worktree add -q --detach "$WT" "$C" </dev/null; rc=$?; echo "worktree add : code $rc"; [ "$rc" = 0 ] || exit 1
cd "$WT" || exit 1
printf '\n// occured once\nfunc temoinLint(x int) int { return int(x) }\n' >> "$PKG/opts.go"
"$L" run -c .golangci.yml $O "$PKG/..." > "$J/v2-lint.out" 2>&1; rc=$?; echo "lint : code $rc"
echo "misspell : $(grep -c 'misspell' "$J/v2-lint.out") ; unconvert : $(grep -c 'unconvert' "$J/v2-lint.out")"
"$L" fmt -c .golangci.yml --diff "$PKG/..." > "$J/v2-fmt.diff" 2>&1; rc=$?; echo "fmt : code $rc ; lignes de diff : $(wc -l < "$J/v2-fmt.diff")"
git checkout -q -- "$PKG/opts.go"; echo "défauts retirés : $(git status --porcelain | wc -l) ligne(s) de status"
h fin; } > "$J/v2-temoin-lint.log" 2>&1
{ h "V3 main de kyverno/kyverno (lecture publique)"
r=$(env -u GITHUB_TOKEN git -c credential.helper= ls-remote https://github.com/kyverno/kyverno.git refs/heads/main </dev/null | cut -f1)
echo "main distant : $r"
[ "$r" = "$M" ] && echo "OK   main inchangé depuis $M" || echo "ÉCART main a bougé : rebase et rejeu à faire avant le push"
h fin; } > "$J/v3-main.log" 2>&1
grep -h -E '^(== V|OK|KO|ÉCART|code|WARNING|worktree|lint|misspell|fmt|défauts|main distant|ok |FAIL)' "$J"/v[0-3]-*.log
