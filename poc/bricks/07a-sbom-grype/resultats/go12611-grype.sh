#!/usr/bin/env bash
# Brique 07b, reconstruction en Go 1.26.11 (choix du propriétaire du 2026-11-24), contrôle préalable SANS télécharger Go :
# entrées de la base Grype du jour (vulndb/grype:2026-11-24 du vrai Zot, lecture anonyme, blob vérifié par sha256) pour la
# bibliothèque standard de Go aux versions 1.24.4 (deb), 1.26.10 (image actuelle), 1.26.11 (cible) et 1.27.4.
# Grype interrogé par PURL (pkg:golang/stdlib@<v>), hors ligne (unshare -rn). Rien n'est écrit dans Zot ni dans le cluster.
# Dossier jetable ~/.cache/supply-chain-poc/07a/go12611-grype, effacé à la fin.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
B=$HOME/.cache/supply-chain-poc/07a/go12611-grype
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
DB=192.168.161.13:5000/vulndb/grype:2026-11-24
mkdir -p "$B/cache"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
hors() { unshare -rn env GRYPE_DB_CACHE_DIR="$B/cache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
  GRYPE_CHECK_FOR_APP_UPDATE=false mise exec -- grype "$@"; }
{
echo "# stdlib de Go dans la base Grype du jour, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), $(mise exec -- grype version 2>/dev/null | awk '/^Version/ {print "grype " $2}')"
d=$(SSL_CERT_FILE=$CA crane manifest "$DB" | jq -r '.layers[] | select(.mediaType == "application/vnd.anchore.grype.db.v6+zstd") | .digest')
echo "base : $DB ; couche $d"
SSL_CERT_FILE=$CA crane blob "${DB%:*}@$d" > "$B/db.tar.zst"
attendu "sha256 de la couche" "sha256:$(sha256sum < "$B/db.tar.zst" | cut -c1-64)" "$d"
hors db import "$B/db.tar.zst" > "$B/import.out" 2>&1; echo "import : code $?"
hors db status 2>&1 | grep -E '^(Schema|Built|Status)' | sed 's/^/  /'
for v in 1.24.4 1.26.10 1.26.11 1.27.4; do
  hors -q -o json "pkg:golang/stdlib@$v" 2>/dev/null > "$B/$v.json"
  echo "stdlib $v : $(jq -r '[.matches[].vulnerability.id] | unique | "\(length) entrée(s) : \(join(" "))"' "$B/$v.json" | cut -c1-900)"
done
attendu "témoin 1.24.4 : 62 entrées (comme le scan du deb)" "$(jq '[.matches[].vulnerability.id] | unique | length' "$B/1.24.4.json")" 62
attendu "1.26.10 : GO-2026-6859 présente" "$(jq '[.matches[].vulnerability.id] | index("GO-2026-6859") != null' "$B/1.26.10.json")" true
attendu "1.26.11 : aucune entrée" "$(jq '.matches | length' "$B/1.26.11.json")" 0
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$B" -delete
cat "$J"
