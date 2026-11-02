#!/usr/bin/env bash
# Cherche chaque secret de la brique 08 dans les fichiers modifiés ou nouveaux du dépôt (motifs en fichier, jamais en argument).
# À lancer avant chaque commit. Les motifs vivent dans un dossier privé (0700), supprimé même en cas d'échec.
set -euo pipefail
cd "$(dirname "$0")/.."
M=$(mktemp -d)
trap 'rm -rf -- "${M:?}"' EXIT
for f in "$HOME"/.cache/supply-chain-poc/08/secrets/*; do
  [ -f "$f" ] || continue
  grep -v -e '^-----' -e '^$' "$f" > "$M/motif-${f##*/}" || true
done
mapfile -t fichiers < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
echo "fichiers : ${#fichiers[@]} ; motifs : $(find "$M" -name 'motif-*' | wc -l)"
openssl rand -hex 16 > "$M/temoin"
cp "$M/temoin" "$M/temoin.txt"
n=$(grep -c -F -f "$M/temoin" "$M/temoin.txt" || true)
echo "témoin retrouvé : $n"
ko=0
for m in "$M"/motif-*; do
  [ -s "$m" ] || continue
  n=$(grep -l -F -f "$m" -- "${fichiers[@]}" 2>/dev/null | wc -l || true)
  [ "$n" = 0 ] || { echo "KO   ${m##*/motif-} : $n fichier(s)"; ko=1; }
done
[ "$ko" = 0 ] && echo "OK   aucun secret dans les fichiers modifiés ou nouveaux"
