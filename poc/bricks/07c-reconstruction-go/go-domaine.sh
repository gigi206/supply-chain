#!/usr/bin/env bash
# Brique 07c, étape 7 (VSA de f5e6bcb0, brique 10) : archive officielle go1.26.11.linux-amd64.tar.gz pour le domaine de replay,
# comme R1 l'a fait pour go1.26.10 (r1-go-recoupement.log de la 10). SUR ACCORD DU PROPRIÉTAIRE (téléchargement), passé en ACCORD
# et recopié au journal. Sur l'hôte seulement : rien dans la VM, le cluster ou Zot.
#   1. sha256 et taille publiés par go.dev (?mode=json) = valeurs relevées le 24/11/2026 et passées à replay.sh (GO_SHA256) ;
#   2. archive téléchargée dans ~/.cache/supply-chain-poc/10/telechargements, sha256 et taille vérifiés avant d'être gardée ;
#   3. recoupement avec le module golang.org/toolchain@v0.0.1-go1.26.11.linux-amd64 (ziphash = h1 de sum.golang.org, étape 1 de
#      la 07c) : fichiers communs de contenu identique, binaires principaux comparés.
# Usage (racine du dépôt) : ACCORD='<réponse du propriétaire>' mise exec -- bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
: "${ACCORD:?accord du propriétaire requis (téléchargement)}"
V=go1.26.11
A=$V.linux-amd64.tar.gz
SHA=9849f4e04ee35303714e34fbc3ac8ab44ea3e448a95aa182f91e3b9b79c710ec   # go.dev, relevé le 24/11/2026 (lecture du JSON)
TAILLE=66999944
H1=h1:KyINmJ/FQdKRmDYGuTAAXkumyeR2DyUlSNHZj7XaLFg=                       # sum.golang.org (README de la 07c)
T=$HOME/.cache/supply-chain-poc/10/telechargements
MOD=${POC_OUTILS:?}/gomodcache/golang.org/toolchain@v0.0.1-$V.linux-amd64
ZH=$POC_OUTILS/gomodcache/cache/download/golang.org/toolchain/@v/v0.0.1-$V.linux-amd64.ziphash
W=$HOME/.cache/supply-chain-poc/07c/go-domaine
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
test ! -e "$T/$A" || { echo "existe déjà : $T/$A"; exit 1; }
mkdir -p "$W/archive"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
{
echo "# archive $A pour le domaine de replay, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
echo "accord du propriétaire (verbatim) : « $ACCORD »"
curl -fsS 'https://go.dev/dl/?mode=json&include=all' -o "$W/go-dl.json"
attendu "sha256 publié par go.dev" "$(jq -r --arg f "$A" '.[].files[] | select(.filename == $f) | .sha256' "$W/go-dl.json")" "$SHA"
attendu "taille publiée par go.dev" "$(jq -r --arg f "$A" '.[].files[] | select(.filename == $f) | .size' "$W/go-dl.json")" "$TAILLE"
curl -fsSL -o "$W/$A" "https://go.dev/dl/$A"
attendu "sha256 de l'archive téléchargée" "$(sha256sum < "$W/$A" | cut -c1-64)" "$SHA"
attendu "taille de l'archive téléchargée" "$(stat -c %s "$W/$A")" "$TAILLE"
attendu "ziphash du module (sum.golang.org)" "$(cat "$ZH")" "$H1"
tar -xzf "$W/$A" -C "$W/archive"
( cd "$MOD" && find . -type f | sort ) > "$W/module.txt"
( cd "$W/archive/go" && find . -type f | sort ) > "$W/archive.txt"
comm -12 "$W/module.txt" "$W/archive.txt" > "$W/communs.txt"
echo "fichiers : module $(wc -l < "$W/module.txt"), archive $(wc -l < "$W/archive.txt"), communs $(wc -l < "$W/communs.txt")"
echo "## dans l'archive seulement, par premier répertoire :"
comm -13 "$W/module.txt" "$W/archive.txt" | cut -d/ -f2 | sort | uniq -c | sort -rn | sed 's/^/  /'
echo "## dans le module seulement : $(comm -23 "$W/module.txt" "$W/archive.txt" | wc -l), dont hors _go.mod : $(comm -23 "$W/module.txt" "$W/archive.txt" | grep -vc '/_go\.mod$')"
d=0
while read -r f; do cmp -s "$MOD/$f" "$W/archive/go/$f" || d=$((d + 1)); done < "$W/communs.txt"
attendu "fichiers communs de contenu différent" "$d" 0
for f in bin/go bin/gofmt pkg/tool/linux_amd64/compile pkg/tool/linux_amd64/link VERSION; do
  attendu "$f identique (module, archive)" "$(sha256sum < "$MOD/$f" | cut -c1-16)" "$(sha256sum < "$W/archive/go/$f" | cut -c1-16)"
done
attendu "VERSION (première ligne)" "$(head -1 "$W/archive/go/VERSION")" "$V"
if [ "$KO" = 0 ]; then
  mv "$W/$A" "$T/$A"
  attendu "archive gardée dans le cache du domaine" "$(sha256sum < "$T/$A" | cut -c1-64)" "$SHA"
else
  echo "écart : archive NON gardée"
fi
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
chmod -R u+w "$W" 2>/dev/null
find "$W" -delete
sed -i "s#$HOME#~#g" "$J"
cat "$J"
