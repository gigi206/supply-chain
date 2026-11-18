#!/usr/bin/env bash
# Brique 05, M1b : question du propriétaire (18/11/2026) « et dnf5 ? il faut utiliser le bon outil avec la bonne distribution ».
# Lecture seule, sans rien installer.
#   1. Hors ligne : gestionnaire de paquets que mock-core-configs (image d'outillage 99790c13, racine extraite par le troisième banc)
#      choisit pour chaque famille (rhel, rocky, centos-stream, fedora, et toute mention de dnf5).
#   2. Lecture publique : fichiers dnf5 et dnf listés dans Rocky 9.8 (vault, BaseOS et AppStream), EPEL 9.8 (archive), Rocky 10 (pub,
#      BaseOS et AppStream) ; listes de répertoire non signées : un indice, pas un épinglage.
#   3. Lecture publique : santé de dnf5 (même relevé que l'étape dnf de sante.sh, sans Scorecard).
# Prédictions : m1b-predictions.md (section dnf5), commitées avant le lancement.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-dnf5.sh > poc/bricks/05-rpm-mock/resultats/m1b-dnf5.log 2>&1
set -euo pipefail
export LC_ALL=C
R=$HOME/.cache/supply-chain-poc/05/m1b-repro3-20261118T201556Z/racine
GH=$(command -v gh)
gh() { env -u GITHUB_TOKEN "$GH" "$@"; }
L=$(mktemp -d "$HOME/.cache/supply-chain-poc/05/m1b-dnf5-XXXXXX")   # listes HTML téléchargées : un dossier neuf, laissé en place
echo "# m1b-dnf5.sh, début $(date -u +%FT%TZ) ; listes dans $L"
echo "## 1. mock-core-configs : package_manager par gabarit"
echo "mock-core-configs : $(unshare --map-auto --map-root-user -n chroot "$R" /usr/bin/rpm -q mock-core-configs mock | tr '\n' ' ')"
for f in rhel-9 rocky-9 centos-stream-9 rhel-10 rocky-10 centos-stream-10 fedora-branched fedora-rawhide; do
  if [ -f "$R/etc/mock/templates/$f.tpl" ]; then
    echo "  $f.tpl : $(grep -h "package_manager'\]" "$R/etc/mock/templates/$f.tpl" | tr -s ' ' || echo 'aucune ligne package_manager')"
  else
    echo "  $f.tpl : absent"
  fi
done
echo "gabarits qui citent dnf5 : $(grep -l dnf5 "$R"/etc/mock/templates/*.tpl | sed 's|.*/||' | tr '\n' ' ')"
echo "## 2. fichiers dnf5 et dnf dans les dépôts"
liste() { # étiquette URL
  local h
  h=$(curl -sSL --max-time 60 -o "$L/$1.html" -w '%{http_code}' "$2") || h="$h, curl en échec"
  if [ "$h" != 200 ]; then echo "  $1 : HTTP $h, liste non lue ($2)"; return; fi
  echo "  $1 : dnf5 $(grep -oE '"(lib)?dnf5[-a-z]*-[0-9][^"]*\.rpm"' "$L/$1.html" | tr -d '"' | sort -uV | tr '\n' ' ')"
  echo "  $1 : dnf $(grep -oE '"(python3-)?dnf-[0-9][^"]*\.rpm"' "$L/$1.html" | tr -d '"' | sort -uV | tail -n 2 | tr '\n' ' ')"
}
liste rocky98-baseos https://dl.rockylinux.org/vault/rocky/9.8/BaseOS/x86_64/os/Packages/d/
liste rocky98-appstream https://dl.rockylinux.org/vault/rocky/9.8/AppStream/x86_64/os/Packages/d/
liste epel98 https://dl.fedoraproject.org/pub/archive/epel/9.8/Everything/x86_64/Packages/d/
liste rocky10-baseos https://dl.rockylinux.org/pub/rocky/10/BaseOS/x86_64/os/Packages/d/
liste rocky10-appstream https://dl.rockylinux.org/pub/rocky/10/AppStream/x86_64/os/Packages/d/
echo "## 3. santé de dnf5"
r=rpm-software-management/dnf5
gh api "repos/$r" --jq '"nom final \(.full_name), archivé \(.archived), licence \(.license.spdx_id), dernier push \(.pushed_at[0:10])"'
echo "dernière release : $(gh api "repos/$r/releases/latest" --jq '"\(.tag_name) du \(.published_at[0:10])"' 2>/dev/null || echo aucune)"
echo "commits depuis $(date -u -d '90 days ago' +%F) : $(gh api "repos/$r/commits?since=$(date -u -d '90 days ago' +%Y-%m-%dT00:00:00Z)&per_page=100" --paginate --jq '.[].sha' | wc -l)"
echo "fusionneurs des 100 dernières PR : $(gh pr list --repo "$r" --state merged --limit 100 --json mergedBy --jq '[.[] | .mergedBy.login] | group_by(.) | map("\(.[0]) \(length)") | join(", ")')"
echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null | grep -x SECURITY.md || echo absent)"
echo "# fin $(date -u +%FT%TZ)"
