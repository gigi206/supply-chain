#!/usr/bin/env bash
# Brique 05, M1b : portée de dnf 4 dans la brique, après le relevé de santé (dnf remplit le critère « Risqué » au sens littéral).
# Hôte seul, hors ligne, lecture seule.
#   1. Paquets dnf de la racine d'outils (image d'outillage 99790c13, extraite par le troisième banc) et de l'arbre i3 (222 rpm du
#      buildroot) : NEVRA, BUILDTIME, et première entrée du changelog de python3-dnf.
#   2. Journaux archivés de la brique (resultats/*.log) : pour chaque motif, les fichiers qui le contiennent et leur nombre de lignes.
#      Seuls des noms de fichiers et des comptes sont imprimés. Ce qui n'est pas dans un journal archivé (pods de M4b et M4c, Loki)
#      n'est pas vu.
# Prédictions : m1b-predictions.md (section de la portée de dnf), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-dnf-portee.sh > poc/bricks/05-rpm-mock/resultats/m1b-dnf-portee.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
D=$HOME/.cache/supply-chain-poc/05/m1b-repro3-20261118T201556Z
q() { unshare --map-auto --map-root-user -n chroot "$D/racine" "$@"; }
echo "# m1b-dnf-portee.sh, début $(date -u +%FT%TZ)"
echo "## 1. paquets dnf"
for o in "" "--root=/m/i3"; do
  if [ -n "$o" ]; then echo "$o :"; else echo "racine d'outils :"; fi
  # shellcheck disable=SC2086
  q /usr/bin/rpm $o -q --qf '  %{NEVRA} ; BUILDTIME %{BUILDTIME:date} (%{BUILDTIME})\n' dnf python3-dnf dnf-data libdnf python3-libdnf python3-hawkey librepo libsolv \
    | sed 's/^package \(.*\) is not installed$/  \1 : non installé/' || true
done
echo "racine d'outils, première entrée du changelog de python3-dnf :"
q /usr/bin/rpm -q --qf '[%{CHANGELOGTIME:date} ; %{CHANGELOGNAME}\n]' python3-dnf | head -n 1 | sed 's/<[^>]*>/<adresse retirée>/; s/^/  /'
q /usr/bin/rpm -q --qf '[%{CHANGELOGTEXT}\n----\n]' python3-dnf | sed '/^----$/q' | head -n 6 | cut -c1-160 | sed 's/^/  /'
journaux() { find "$r" -maxdepth 1 -name '*.log' ! -name m1b-dnf-portee.log -print0 | sort -z; }   # sans le journal de ce script
echo "## 2. journaux archivés de la brique : $(journaux | tr -cd '\0' | wc -c) fichiers"
for m in 'Package manager dnf4 detected' 'installing minimal buildroot with dnf' 'dnf-3' 'installroot'; do
  echo "motif « $m » :"
  journaux | xargs -0 grep -c -F -- "$m" | awk -F: '$2 > 0 {sub(".*/", "", $1); print "  " $1 " : " $2 " ligne(s)"}'
done
echo "# fin $(date -u +%FT%TZ)"
