#!/usr/bin/env bash
# Brique 07c, étape 7 : layout OCI de sample-app en Go 1.26.11 (f5e6bcb0, banc de l'hôte de l'étape 2) copié hors du banc, sous
# ~/.cache/supply-chain-poc/w/b04-1.26.11/app-layout, à côté de celui de la 04 (w/b04/app-layout, 3a7ca1b1) : w/ survit au
# démontage du rejeu (vm.sh detruire efface 08/travail, pas w/). Lu par construction.sh (APP_LAYOUT, étape compte).
# Hôte seul : rien n'est écrit dans Zot ni dans le cluster. La cible ne doit pas exister.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
SRC=$HOME/.cache/supply-chain-poc/07c/banc/b04-1.26.11/app-layout
DST=$HOME/.cache/supply-chain-poc/w/b04-1.26.11/app-layout
REF=sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
test ! -e "$DST" || { echo "existe déjà : $DST"; exit 1; }
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
blobs_ko() { # layout : blobs dont le sha256 diffère du nom
  find "$1/blobs/sha256" -type f | while read -r f; do [ "$(sha256sum < "$f" | cut -c1-64)" = "${f##*/}" ] || echo "$f"; done | wc -l; }
{
echo "# layout de référence Go 1.26.11 hors du banc, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
attendu "index du layout du banc" "$(jq -r '[.manifests[].digest] | join(",")' "$SRC/index.json")" "$REF"
attendu "blobs du banc conformes à leur sha256" "$(blobs_ko "$SRC")" 0
mkdir -p "${DST%/*}"
cp -a "$SRC" "$DST"
attendu "copie identique (diff -r)" "$(diff -r "$SRC" "$DST" >/dev/null && echo identique || echo différente)" identique
attendu "blobs de la copie conformes à leur sha256" "$(blobs_ko "$DST")" 0
echo "taille : $(du -sh "$DST" | cut -f1) ; $(find "$DST/blobs/sha256" -type f | wc -l) blobs"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
cat "$J"
