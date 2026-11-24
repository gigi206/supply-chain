#!/usr/bin/env bash
# Brique 07c, étape 2 : banc de la brique 04 (bench.sh, inchangé) sur l'hôte, BuildKit du nixpkgs rootless (référence de
# bancs-laptop.sh), entrées de la brique 03 (~/.cache/supply-chain-poc/w/b03) :
#   témoin  Go 1.26.10 : doit redonner l'image 3a7ca1b1 (l'hôte reproduit toujours la référence) ;
#   cible   Go 1.26.11 : deux constructions, même digest = digest PRÉDIT de la future image ; l'étape 3 de bench.sh (binaire =
#           celui de la brique 03, compilé en 1.26.10) échoue par construction : remplacée ici par une compilation hors BuildKit
#           en 1.26.11, sans réseau (unshare -rn), mêmes options que le Dockerfile de la 04 ;
#   scan    Grype hors ligne (base vulndb/grype:2026-11-24 du vrai Zot, lecture anonyme, couche vérifiée) sur les deux images.
# Rien n'est écrit dans Zot ni dans le cluster. Dossier gardé : ~/.cache/supply-chain-poc/07c/banc (images OCI, relues aux
# étapes suivantes), sauf la base Grype, effacée à la fin.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
W=$HOME/.cache/supply-chain-poc/07c/banc
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
O=$HOME/.cache/supply-chain-poc/outils
B03=$HOME/.cache/supply-chain-poc/w/b03
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
DB=192.168.161.13:5000/vulndb/grype:2026-11-24
REF=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
bkn=$O/buildkit-nix/bin
B04=$PWD/poc/bricks/04-hermetic-repro/bench.sh
mkdir -p "$W/bk"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
pid=
fin() { [ -z "$pid" ] || kill "$pid" 2>/dev/null; }
trap fin EXIT
hors() { unshare -rn env GRYPE_DB_CACHE_DIR="$W/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
  GRYPE_CHECK_FOR_APP_UPDATE=false mise exec -- grype "$@"; }
{
echo "# banc de la 04 en Go 1.26.10 et 1.26.11, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), buildkit $("$bkn/buildkitd" --version | awk '{print $3}')"
attendu "entrées de la 03 : binaire de référence (1.26.10)" "$(sha256sum < "$B03/build-apres/sample-app" | cut -c1-16)" e3749c68b6babe6d
"$(mise which rootlesskit)" --state-dir="$W/bk/rk" --net=host "$bkn/buildkitd" --rootless --root "$W/bk/root" \
  --addr "unix://$W/bk/buildkitd.sock" --oci-worker=true --containerd-worker=false --oci-worker-snapshotter=native \
  --oci-worker-binary="$O/runc-nix/bin/runc" > "$W/bk/buildkitd.log" 2>&1 &
pid=$!
for _ in $(seq 1 30); do "$bkn/buildctl" --addr "unix://$W/bk/buildkitd.sock" debug workers >/dev/null 2>&1 && break; sleep 1; done
for v in 1.26.10 1.26.11; do
  echo "## bench.sh de la 04, Go $v"
  t=$(date +%s)
  env BUILDKIT_HOST="unix://$W/bk/buildkitd.sock" BUILDCTL="$bkn/buildctl" BUSYBOX="$O/busybox/bin/busybox" \
    GOROOT_DIR="$O/gomodcache/golang.org/toolchain@v0.0.1-go$v.linux-amd64" B03="$B03" WORKDIR="$W/b04-$v" \
    bash "$B04" > "$W/b04-$v.log" 2>&1; echo "code $? en $(( $(date +%s) - t )) s"
  grep -E '^(OK|KO)' "$W/b04-$v.log" | cut -c1-200 | sed 's/^/  /'
done
d10=$(grep -o 'image sample-app identique sur 2 builds sans cache, 2 chemins (sha256:[0-9a-f]*' "$W/b04-1.26.10.log" | grep -o 'sha256:.*')
d11=$(grep -o 'image sample-app identique sur 2 builds sans cache, 2 chemins (sha256:[0-9a-f]*' "$W/b04-1.26.11.log" | grep -o 'sha256:.*')
attendu "témoin 1.26.10 : image de référence" "$d10" "$REF"
attendu "témoin 1.26.10 : bench.sh sans KO" "$(grep -c '^KO' "$W/b04-1.26.10.log")" 0
attendu "1.26.11 : image identique sur deux constructions" "$([ -n "$d11" ] && echo oui || echo non)" oui
attendu "1.26.11 : digest différent de la référence" "$([ "$d11" != "$REF" ] && echo oui || echo non)" oui
attendu "1.26.11 : seul KO de bench.sh, l'étape 3 (binaire de la 03 en 1.26.10)" "$(grep '^KO' "$W/b04-1.26.11.log" | cut -c1-14 | paste -sd,)" "KO   binaire :"
echo "DIGEST PRÉDIT|$d11"
X=$W/b04-1.26.11/extrait/sample-app
echo "binaire 1.26.11 : $(stat -c %s "$X") octets, sha256 $(sha256sum < "$X" | cut -c1-64)"
env -u GOROOT -u GOBIN mise exec -- go version -m "$X" | sed 's/^/  /'
echo "## compilation hors BuildKit, Go 1.26.11, sans réseau"
mkdir -p "$W/hors/src" "$W/hors/mod" "$W/hors/cache"
cp -a "$B03/canon/source/." "$W/hors/src/"; cp -a "$B03/build-apres/web/dist" "$W/hors/src/web/"
G=$O/gomodcache/golang.org/toolchain@v0.0.1-go1.26.11.linux-amd64/bin/go
(cd "$W/hors/src" && unshare -rn env -u GOROOT -u GOBIN -u GOFLAGS CGO_ENABLED=0 GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOSUMDB=off \
  GOPROXY=file://$B03/canon/deps/deps/gomod/pkg/mod/cache/download GOMODCACHE="$W/hors/mod" GOCACHE="$W/hors/cache" \
  "$G" build -trimpath -buildvcs=false -ldflags "-s -w -buildid= -X main.Version=1.0.0" -o "$W/hors/sample-app" .) > "$W/hors/build.log" 2>&1
echo "compilation : code $? ; $(tail -2 "$W/hors/build.log")"
attendu "binaire hors BuildKit = binaire de l'image (1.26.11)" "$(sha256sum < "$W/hors/sample-app" | cut -c1-64)" "$(sha256sum < "$X" | cut -c1-64)"
chmod -R u+w "$W/hors/mod" 2>/dev/null
echo "## scan Grype hors ligne, base du jour"
d=$(SSL_CERT_FILE=$CA crane manifest "$DB" | jq -r '.layers[] | select(.mediaType == "application/vnd.anchore.grype.db.v6+zstd") | .digest')
SSL_CERT_FILE=$CA crane blob "${DB%:*}@$d" > "$W/db.tar.zst"
attendu "sha256 de la couche de la base" "sha256:$(sha256sum < "$W/db.tar.zst" | cut -c1-64)" "$d"
hors db import "$W/db.tar.zst" > /dev/null 2>&1; hors db status 2>&1 | grep -E '^(Built|Status)' | sed 's/^/  /'
for v in 1.26.10 1.26.11; do
  hors -q -o json "oci-dir:$W/b04-$v/app-layout" 2>/dev/null > "$W/grype-$v.json"
  echo "Go $v : $(jq -r '[.matches[] | "\(.vulnerability.id) (\(.artifact.name)@\(.artifact.version))"] | unique | "\(length) : \(join(", "))"' "$W/grype-$v.json")"
done
attendu "témoin 1.26.10 : 6 entrées, dont GO-2026-6859" "$(jq '[.matches[].vulnerability.id] | unique | "\(length) \(index("GO-2026-6859") != null)"' -r "$W/grype-1.26.10.json")" "6 true"
attendu "1.26.11 : 5 entrées, toutes sur chi" "$(jq -r '"\([.matches[].vulnerability.id] | unique | length) \([.matches[].artifact.name] | unique | join(","))"' "$W/grype-1.26.11.json")" "5 github.com/go-chi/chi/v5"
attendu "1.26.11 : 0 entrée stdlib" "$(jq '[.matches[] | select(.artifact.name == "stdlib")] | length' "$W/grype-1.26.11.json")" 0
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
find "$W/dbcache" "$W/db.tar.zst" -delete 2>/dev/null
sed -i "s#$HOME#~#g" "$J"
cat "$J"
