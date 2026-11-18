#!/usr/bin/env bash
# Évaluation PaC (hors ADR 0000) : relevé de santé selon les critères de docs/04, en lecture publique seulement.
# Clone le dépôt (sans les blobs hors du tag) dans un dossier neuf de ~/.cache/supply-chain-poc/pac/, jamais effacé ni réutilisé.
# Aucune adresse e-mail n'est imprimée : seuls leurs domaines, comptés.
# Usage (racine du dépôt) : bash poc/benchmarks/pac/releve-sante.sh <tag> > poc/benchmarks/pac/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
[ $# = 1 ] || { echo "KO   usage : $0 <tag>" >&2; exit 1; }
TAG=$1 R=tektoncd/pipelines-as-code
gha() { env -u GITHUB_TOKEN gh api "$@"; }
echo "# releve-sante.sh, début $(date -u +%FT%TZ), dépôt $R, tag $TAG"

echo "## Scorecard (API publique, via tools/health/scorecard.sh)"
L=$(mktemp -d "$HOME/.cache/supply-chain-poc/pac-tsv-XXXXXX")
grep -P '^Tekton Pipelines-as-Code\t' tools/health/projects.tsv > "$L/p.tsv"
printf 'PaC (ancien chemin)\topenshift-pipelines/pipelines-as-code\torchestration\toui\n' >> "$L/p.tsv"
bash tools/health/scorecard.sh "$L/p.tsv"

echo "## Dépôt"
gha "repos/$R" --jq '"nom \(.full_name) ; archivé \(.archived) ; licence \(.license.spdx_id) ; branche \(.default_branch) ; dernier push \(.pushed_at)"'

echo "## Releases (12 dernières)"
gha "repos/$R/releases?per_page=12" --jq '.[] | "\(.tag_name)\t\(.published_at)\tpré-release=\(.prerelease)"'
echo "fichiers attachés à $TAG :"
gha "repos/$R/releases/tags/$TAG" --jq '.assets[] | "  \(.name)\t\(.size)"'

echo "## Tag $TAG et signature"
gha "repos/$R/git/ref/tags/$TAG" --jq '"ref : objet \(.object.type) \(.object.sha)"'
o=$(gha "repos/$R/git/ref/tags/$TAG" --jq .object.sha); t=$(gha "repos/$R/git/ref/tags/$TAG" --jq .object.type)
if [ "$t" = tag ]; then
  gha "repos/$R/git/tags/$o" --jq '"tag annoté : vise \(.object.type) \(.object.sha) ; vérification GitHub du tag : \(.verification.verified) (\(.verification.reason))"'
  c=$(gha "repos/$R/git/tags/$o" --jq .object.sha)
else c=$o; fi
gha "repos/$R/commits/$c" --jq '"commit \(.sha) ; vérification GitHub du commit : \(.commit.verification.verified) (\(.commit.verification.reason)) ; date \(.commit.committer.date)"'

echo "## Clone"
D=$HOME/.cache/supply-chain-poc/pac/depot-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }
mkdir -p "$(dirname "$D")"
git clone -q --filter=blob:none --no-checkout "https://github.com/$R.git" "$D"
git -C "$D" -c advice.detachedHead=false checkout -q "refs/tags/$TAG"
echo "dossier $D ; HEAD $(git -C "$D" rev-parse HEAD) ; égal au commit du tag : $([ "$(git -C "$D" rev-parse HEAD)" = "$c" ] && echo oui || echo NON)"

echo "## Activité sur 90 jours (branche $(git -C "$D" symbolic-ref --short refs/remotes/origin/HEAD), jusqu'au $(date -u +%F))"
B=$(git -C "$D" symbolic-ref --short refs/remotes/origin/HEAD)
echo "commits : $(git -C "$D" log --since=90.days --format=%H "$B" | wc -l) ; sans les fusions : $(git -C "$D" log --no-merges --since=90.days --format=%H "$B" | wc -l)"
echo "auteurs distincts (adresse) : $(git -C "$D" log --no-merges --since=90.days --format=%ae "$B" | sort -u | wc -l)"
echo "auteurs distincts par domaine d'adresse (nombre d'auteurs, nombre de commits) :"
git -C "$D" log --no-merges --since=90.days --format=%ae "$B" | sed 's/.*@//' | sort | uniq -c | sort -rn | while read -r n d; do
  a=$(git -C "$D" log --no-merges --since=90.days --format=%ae "$B" | grep -c -F "@$d" || true)
  u=$(git -C "$D" log --no-merges --since=90.days --format=%ae "$B" | grep -F "@$d" | sort -u | wc -l)
  echo "  $d : $u auteurs, $a commits"
done
echo "commits de robots (auteur contenant [bot]) : $(git -C "$D" log --no-merges --since=90.days --format=%an "$B" | grep -c '\[bot\]' || true)"

echo "## Processus de sécurité"
for f in SECURITY.md .github/SECURITY.md docs/SECURITY.md; do [ -e "$D/$f" ] && echo "présent : $f" || echo "absent : $f"; done
gha "repos/tektoncd/.github/contents" --jq '.[].name' 2>/dev/null | grep -i security | sed 's/^/dépôt tektoncd\/.github : /' || echo "dépôt tektoncd/.github : aucun fichier de sécurité à la racine"
echo "avis publiés (GHSA) :"
gha "repos/$R/security-advisories?per_page=50" --jq '.[] | "  \(.ghsa_id)\t\(.severity)\tpublié \(.published_at)\t\(.cve_id // "sans CVE")"' 2>&1 || true

echo "## CLA"
grep -ril -E 'contributor license agreement|\bCLA\b' "$D"/CONTRIBUTING* "$D"/.github 2>/dev/null | sed "s|$D/||" || echo "aucune mention de CLA dans CONTRIBUTING* ni .github"

echo "## Images de $TAG (release.yaml)"
gha "repos/$R/releases/tags/$TAG" --jq '.assets[] | select(.name == "release.yaml") | .browser_download_url' > "$L/url"
if [ -s "$L/url" ]; then
  curl -fsSL --max-time 60 -o "$L/release.yaml" "$(cat "$L/url")"
  echo "release.yaml : $(stat -c %s "$L/release.yaml") octets, sha256 $(sha256sum < "$L/release.yaml" | cut -c1-64)"
  grep -oE '(ghcr\.io|quay\.io|gcr\.io)/[^" ]+' "$L/release.yaml" | sort -u | tee "$L/images" | sed 's/^/  image : /'
  i=$(grep -m1 controller "$L/images" || head -1 "$L/images")
  echo "cosign tree de $i :"
  cosign tree "$i" 2>&1 | sed 's/^/  /' || echo "  cosign tree code $?"
else echo "pas de release.yaml attaché à $TAG"; fi
echo "fichiers de travail laissés dans $L"
echo "# fin $(date -u +%FT%TZ)"
