#!/usr/bin/env bash
# Brique 07b, VEX du deb : contrôles qui doivent précéder le brouillon (réserves de la note de 12:58Z de la carte), sur le binaire
# du paquet de builds/sample-app-deb@sha256:60f25f5c…. LECTURE SEULE (lecture anonyme de Zot ; binaire jamais exécuté).
#   1. étalon : forme des chemins de fichiers sources de la bibliothèque standard dans ce binaire (-trimpath), sur des témoins
#      liés (net/http/server.go, crypto/tls) ;
#   2. classe A (17 entrées stdlib) : aucun chemin de fichier source des paquets visés ; un fichier inliné y laisserait le sien ;
#   3. chi : les 5 entrées (3 GHSA sans imports, 2 GO), comme piece8-binaire.sh passage 4 : aucun chemin chi/v5/middleware,
#      aucune chaîne RealIP, ClientIPFromXFF, GetClientIP, RedirectSlashes, realip, /strip.go ;
#   4. GO-2026-6604 (Critical, goos windows d'après sa fiche) : binaire GOOS=linux ; aucun chemin internal/syscall/windows.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
B=$HOME/.cache/supply-chain-poc/07a/deb-preuves
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
DEB=192.168.161.13:5000/builds/sample-app-deb@sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e
GO=$(mise which go)
mkdir -p "$B/oci" "$B/racine"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
fichiers() { grep -cE "(^|/)$1/[^/]+\.go$" "$B/chaines" || true; }   # chemins de fichiers sources du paquet (pas des sous-paquets)
{
echo "# preuves du deb avant brouillon, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
attendu "digest du manifeste relu" "$(SSL_CERT_FILE=$CA crane digest "$DEB" 2>&1)" "sha256:${DEB##*@sha256:}"
SSL_CERT_FILE=$CA crane export "$DEB" - | tar -x -C "$B/oci"; dpkg-deb -x "$B/oci"/*.deb "$B/racine"; X=$B/racine/usr/bin/sample-app
attendu "binaire (celui du tri)" "$(sha256sum < "$X" | cut -c1-16)" 10d475d00dc2a14c
strings -n 4 "$X" > "$B/chaines"
echo "## 1. étalon"
grep -E 'net/http/server\.go$|crypto/tls/conn\.go$' "$B/chaines" | sort -u | head -4 | sed 's/^/  chemin témoin : /'
attendu "témoin net/http/server.go présent" "$([ "$(fichiers net/http)" -gt 0 ] && echo oui || echo non)" oui
attendu "témoin crypto/tls présent" "$([ "$(fichiers crypto/tls)" -gt 0 ] && echo oui || echo non)" oui
echo "## 2. classe A : chemins de fichiers sources des paquets visés"
for p in database/sql os/exec net/mail archive/tar archive/zip html/template net/http/httputil encoding/xml; do
  attendu "aucun fichier source de $p" "$(fichiers "$p")" 0
done
echo "## 3. chi"
attendu "chemins sous chi/v5…/middleware/" "$(grep -c 'chi/v5[^ ]*/middleware/' "$B/chaines" || true)" 0
attendu "chemin de paquet chi/v5/middleware" "$(grep -c 'chi/v5/middleware' "$B/chaines" || true)" 0
for m in RealIP ClientIPFromXFF GetClientIP RedirectSlashes; do attendu "$m" "$(grep -c "$m" "$B/chaines" || true)" 0; done
attendu "realip ou /strip.go" "$(grep -ciE 'realip|/strip\.go' "$B/chaines" || true)" 0
echo "## 4. GO-2026-6604 (Windows)"
attendu "GOOS du binaire" "$("$GO" version -m "$X" | awk '$1 == "build" && $2 ~ /^GOOS=/ {sub("GOOS=", "", $2); print $2}')" linux
attendu "aucun fichier source de internal/syscall/windows" "$(fichiers internal/syscall/windows)" 0
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$B" -delete
cat "$J"
