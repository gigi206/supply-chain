#!/usr/bin/env bash
# Relève le score OpenSSF Scorecard (API publique) des projets listés dans
# projects.tsv et imprime un tableau Markdown daté sur la sortie standard.
#
# Usage : tools/health/scorecard.sh [projects.tsv] > scorecard.md
#
# Les dépôts absents de l'analyse automatique de Scorecard ressortent « n/d » :
# il faut alors lancer le CLI `scorecard --repo=...` avec un GITHUB_AUTH_TOKEN.
# Les scores de `scorecard --local` (contrôles partiels) ne doivent pas être
# mélangés à ceux de l'API.
set -euo pipefail

list="${1:-$(dirname "$0")/projects.tsv}"
api="${SCORECARD_API:-https://api.securityscorecards.dev}"

check() { # $1 = JSON, $2 = nom du contrôle
  jq -r --arg n "$2" '([.checks[]? | select(.name == $n) | .score][0] // "?") | tostring' <<<"$1"
}

echo "Relevé du $(date -u +%Y-%m-%d) via ${api}"
echo
echo "| Projet | Dépôt | Domaine | Chemin critique | Score | Date du relevé | Maintained | Signed-Releases | Code-Review | Vulnerabilities |"
echo "|---|---|---|---|---|---|---|---|---|---|"

grep -v '^#' "$list" | while IFS=$'\t' read -r name repo domain critical; do
  [ -z "${name}" ] && continue
  if [ "${repo}" = "-" ]; then
    echo "| ${name} | hors GitHub | ${domain} | ${critical} | n/a | — | — | — | — | — |"
    continue
  fi
  json="$(curl -fsS --max-time 20 "${api}/projects/github.com/${repo}" 2>/dev/null || true)"
  score="$(jq -r '.score // empty' <<<"${json}" 2>/dev/null || true)"
  if [ -z "${score}" ]; then
    echo "| ${name} | ${repo} | ${domain} | ${critical} | n/d | — | — | — | — | — |"
    continue
  fi
  date="$(jq -r '.date // "" | .[0:10]' <<<"${json}")"
  echo "| ${name} | ${repo} | ${domain} | ${critical} | ${score} | ${date} | $(check "${json}" Maintained) | $(check "${json}" Signed-Releases) | $(check "${json}" Code-Review) | $(check "${json}" Vulnerabilities) |"
done
