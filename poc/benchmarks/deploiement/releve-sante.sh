#!/usr/bin/env bash
# Évaluation du déploiement (hors ADR 0000) : relevé de santé selon les critères de docs/04, par l'API publique de GitHub seulement
# (aucun clone, aucun binaire téléchargé). Seuls les domaines des adresses e-mail sont imprimés, comptés.
# Usage (racine du dépôt) : bash poc/benchmarks/deploiement/releve-sante.sh > poc/benchmarks/deploiement/resultats/<journal neuf> 2>&1
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C
gha() { env -u GITHUB_TOKEN gh api "$@"; }
SINCE=$(date -u -d '90 days ago' +%FT%TZ)
echo "# releve-sante.sh (déploiement), début $(date -u +%FT%TZ) ; activité depuis $SINCE"
echo "## Scorecard (API publique, via tools/health/scorecard.sh, lignes de projects.tsv)"
L=$(mktemp -d "$HOME/.cache/supply-chain-poc/dep-tsv-XXXXXX")
grep -P '^(Argo CD|Flux CD|helmfile)\t' tools/health/projects.tsv > "$L/p.tsv"
for r in source-controller kustomize-controller helm-controller notification-controller; do printf 'Flux %s\tfluxcd/%s\tdéploiement\tnon\n' "$r" "$r" >> "$L/p.tsv"; done
bash tools/health/scorecard.sh "$L/p.tsv"
for e in "argoproj/argo-cd v3.6.2" "fluxcd/flux2 v2.10.0" "helmfile/helmfile v1.8.4"; do
  set -- $e; R=$1 TAG=$2
  echo; echo "## $R, tag $TAG"
  gha "repos/$R" --jq '"archivé \(.archived) ; licence \(.license.spdx_id) ; branche \(.default_branch) ; dernier push \(.pushed_at)"'
  echo "releases publiées depuis 6 mois : $(gha "repos/$R/releases?per_page=100" --jq "[.[] | select(.published_at > \"$(date -u -d '183 days ago' +%FT%TZ)\")] | length")"
  gha "repos/$R/releases/tags/$TAG" --jq '"release \(.tag_name) du \(.published_at), pré-release \(.prerelease) ; fichiers : \([.assets[].name] | join(" "))"'
  o=$(gha "repos/$R/git/ref/tags/$TAG" --jq .object.sha); t=$(gha "repos/$R/git/ref/tags/$TAG" --jq .object.type)
  if [ "$t" = tag ]; then gha "repos/$R/git/tags/$o" --jq '"tag annoté ; vérification GitHub du tag : \(.verification.verified) (\(.verification.reason))"'; c=$(gha "repos/$R/git/tags/$o" --jq .object.sha); else echo "tag léger"; c=$o; fi
  gha "repos/$R/commits/$c" --jq '"commit \(.sha) ; vérification GitHub : \(.commit.verification.verified) (\(.commit.verification.reason))"'
  gha --paginate "repos/$R/commits?since=$SINCE&per_page=100" --jq '.[] | [.commit.author.email, (.author.login // "-")] | @tsv' > "$L/c-${R//\//_}"
  n=$(wc -l < "$L/c-${R//\//_}"); echo "commits sur 90 jours (branche par défaut) : $n ; auteurs distincts : $(cut -f1 "$L/c-${R//\//_}" | sort -u | wc -l) ; commits de robots : $(cut -f2 "$L/c-${R//\//_}" | grep -c '\[bot\]' || true)"
  echo "domaines d'adresse (auteurs distincts, commits) :"
  cut -f1 "$L/c-${R//\//_}" | sed 's/.*@//' | sort | uniq -c | sort -rn | head -8 | while read -r k d; do
    echo "  $d : $(cut -f1 "$L/c-${R//\//_}" | grep -F "@$d" | sort -u | wc -l) auteurs, $k commits"; done
  for f in SECURITY.md .github/SECURITY.md; do gha "repos/$R/contents/$f?ref=$TAG" --jq '"présent : \(.path)"' 2>/dev/null || echo "absent : $f"; done
  echo "avis publiés (GHSA), 2026 seulement :"
  gha "repos/$R/security-advisories?per_page=100" --jq '.[] | select(.published_at > "2026-01-01") | "  \(.ghsa_id)\t\(.severity)\t\(.published_at[0:10])\t\(.summary[0:90])"' 2>&1 || true
  echo "avis publiés (GHSA), total : $(gha "repos/$R/security-advisories?per_page=100" --jq length 2>/dev/null || echo '?')"
done
echo; echo "fichiers de travail laissés dans $L"
echo "# fin $(date -u +%FT%TZ)"
