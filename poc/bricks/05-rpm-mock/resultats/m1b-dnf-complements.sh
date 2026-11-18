#!/usr/bin/env bash
# Brique 05, M1b : compléments du relevé de santé de dnf (sante-dnf.log, 18/11/2026, 20:24:37 UTC). L'API REST des étiquettes ne les
# trie pas par date : les cinq lues ne disent rien de la plus récente. Ici, lecture publique seulement :
#   1. les cinq étiquettes les plus récentes par date du commit (GraphQL, TAG_COMMIT_DATE), pour dnf, libdnf, librepo et libsolv ;
#   2. les dix dernières releases GitHub de dnf (nom, date, pré-version ou non) ;
#   3. les lignes du README de dnf qui citent dnf5 ou la maintenance (au plus dix, coupées à 200 caractères).
# Prédictions : m1b-predictions.md (section des compléments du relevé de dnf), commitées avant le lancement.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-dnf-complements.sh > poc/bricks/05-rpm-mock/resultats/m1b-dnf-complements.log 2>&1
set -euo pipefail
export LC_ALL=C
GH=$(command -v gh)
gh() { env -u GITHUB_TOKEN "$GH" "$@"; }
echo "# m1b-dnf-complements.sh, début $(date -u +%FT%TZ)"
echo "## 1. étiquettes les plus récentes, par date du commit"
for r in rpm-software-management/dnf rpm-software-management/libdnf rpm-software-management/librepo openSUSE/libsolv; do
  echo "$r :"
  gh api graphql -F o="${r%/*}" -F n="${r#*/}" -f query='query($o: String!, $n: String!) { repository(owner: $o, name: $n) {
      refs(refPrefix: "refs/tags/", first: 5, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
        nodes { name target { ... on Commit { committedDate } ... on Tag { target { ... on Commit { committedDate } } } } } } } }' \
    --jq '.data.repository.refs.nodes[] | "  \(.name) : commit du \((.target.committedDate // .target.target.committedDate // "?")[0:10])"'
done
echo "## 2. dix dernières releases GitHub de dnf"
gh api "repos/rpm-software-management/dnf/releases?per_page=10" --jq '.[] | "  \(.tag_name) du \(.published_at[0:10]) ; pré-version \(.prerelease) ; brouillon \(.draft)"'
echo "## 3. README de dnf : lignes citant dnf5 ou la maintenance"
gh api repos/rpm-software-management/dnf/readme --jq .content | base64 -d > "${TMPDIR:-/tmp}/m1b-dnf-readme.$$"
echo "lignes du README : $(wc -l < "${TMPDIR:-/tmp}/m1b-dnf-readme.$$") ; lignes citant dnf5 ou maintenance (casse ignorée) : $(grep -Eci 'dnf5|maintenance' "${TMPDIR:-/tmp}/m1b-dnf-readme.$$" || true)"
grep -Ei 'dnf5|maintenance' "${TMPDIR:-/tmp}/m1b-dnf-readme.$$" | head -n 10 | cut -c1-200 | sed 's/^/  /' || true
rm -f -- "${TMPDIR:-/tmp}/m1b-dnf-readme.$$"
echo "# fin $(date -u +%FT%TZ)"
