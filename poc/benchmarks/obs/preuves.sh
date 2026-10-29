#!/usr/bin/env bash
# Banc A2 : preuves de santé et de pérennité (A-6), même méthode qu'au banc A1 (konflux/preuves.sh) :
# commits humains sur 90 jours, auteurs, domaines des adresses, employeurs déclarés (profils GitHub) ;
# licences ; rythme des releases (tags) et écart entre la release et master.
#
# Usage (racine du dépôt, lecture seule) : mise run obs:preuves
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
SINCE=$(date -u -d '90 days ago' +%Y-%m-%dT00:00:00Z)
W=$(mktemp -d)
trap 'rm -rf -- "$W"' EXIT
exec > >(tee "$R/preuves.log") 2>&1
echo "# preuves.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "## Licences"
for repo in openSUSE/open-build-service openSUSE/obs-build openSUSE/obs-sign; do
  echo "$repo : $(gh api "repos/$repo" --jq '.license.spdx_id // "?"') ; archivé : $(gh api "repos/$repo" --jq .archived)"
done

echo "## Releases (tags) et écart avec master"
gh api 'repos/openSUSE/open-build-service/tags?per_page=100' --jq '.[].name' | grep -E '^2\.10\.[0-9]+$' | sort -V | tail -5 | while read -r t; do
  c=$(gh api "repos/openSUSE/open-build-service/commits/$t" --jq '.commit.committer.date')
  echo "  $t : $c"
done
echo "commits de master non publiés depuis 2.10.34 : $(gh api 'repos/openSUSE/open-build-service/compare/2.10.34...master' --jq '.ahead_by')"

echo "## Santé : commits humains depuis $SINCE"
for repo in openSUSE/open-build-service openSUSE/obs-build openSUSE/obs-sign; do
  gh api --paginate "repos/$repo/commits?since=$SINCE&per_page=100" \
    --jq '.[] | select((.commit.author.name + " " + (.author.login // "")) | test("bot|renovate|dependabot|depfu"; "i") | not) | [.commit.author.email, (.author.login // "-")] | @tsv' > "$W/c.tsv"
  echo "$repo : $(wc -l < "$W/c.tsv") commits, $(cut -f2 "$W/c.tsv" | sort -u | wc -l) auteurs ; domaines : $(cut -f1 "$W/c.tsv" | sed 's/.*@//' | sort | uniq -c | sort -rn | head -4 | awk '{printf "%s %s ; ", $2, $1}')"
  cat "$W/c.tsv" >> "$W/tous.tsv"
done
echo "Employeur déclaré (profil GitHub) des auteurs sans adresse suse.com / suse.de :"
awk -F'\t' '$1 !~ /suse\.(com|de|cz)$/ && $2 != "-" {print $2}' "$W/tous.tsv" | sort | uniq -c | sort -rn | while read -r n u; do
  echo "  $u ($n) : $(gh api "users/$u" --jq '.company // "non renseigné"')"
done
echo "Auteurs distincts (tous dépôts) : $(cut -f2 "$W/tous.tsv" | sort -u | wc -l) ; part des commits du premier auteur : $(cut -f2 "$W/tous.tsv" | sort | uniq -c | sort -rn | awk 'NR==1{m=$1} {t+=$1} END{printf "%.0f %%", 100*m/t}')"
