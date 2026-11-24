#!/usr/bin/env bash
# Brique 07c, étape 3 À SEC : digest de l'image de build de la voie D (voie-d.sh etape_image) avec Go 1.26.11, calculé sur un
# registre Zot JETABLE local (127.0.0.1:5077, mise zot), rien n'est écrit dans le vrai Zot ni dans le cluster.
# Assemblage recopié de voie-d.sh (racine_builder, tar_det, crane append --oci-empty-base puis mutate, mêmes variables) ;
# témoin : Go 1.26.10 doit redonner d50ae57551c3… (image épinglée par construction.sh), sinon la recopie est fausse.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
W=$HOME/.cache/supply-chain-poc/07c/predire-builder
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
O=$HOME/.cache/supply-chain-poc/outils
BUSYBOX=$O/busybox/bin/busybox
REF=sha256:d50ae57551c381b591540643fdfee12dd251ae16675c3c69fde221f8e9c28b67
R=127.0.0.1:5077
mkdir -p "$W/zot/data"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
pid=
fin() { [ -z "$pid" ] || kill "$pid" 2>/dev/null; }
trap fin EXIT
tar_det() { local d=$1 o=$2; shift 2
  tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$d" -cf "$o" "$@"; }
racine_builder() { # $1 racine, $2 GOROOT
  mkdir -p "$1/bin" "$1/usr/local" "$1/tmp"
  install -m 0755 "$BUSYBOX" "$1/bin/busybox"
  for a in $("$BUSYBOX" --list); do [ "$a" = busybox ] || ln -s busybox "$1/bin/$a"; done
  cp -a "$2" "$1/usr/local/go"; chmod -R u+w "$1/usr/local/go"; chmod 1777 "$1/tmp"; }
{
echo "# image de build de la voie D, Go 1.26.10 (témoin) et 1.26.11, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), crane $(crane version)"
umask 022
jq --arg d "$W/zot/data" '.storage.rootDirectory = $d | .http.port = "5077"' poc/bricks/03-deps-closure/zot-config.json > "$W/zot/config.json"
mise exec -- zot serve "$W/zot/config.json" > "$W/zot/zot.log" 2>&1 &
pid=$!
for _ in $(seq 1 30); do curl -fsS "http://$R/v2/" >/dev/null 2>&1 && break; sleep 1; done
for v in 1.26.10 1.26.11; do
  for i in a b; do
    racine_builder "$W/$v-$i/racine" "$O/gomodcache/golang.org/toolchain@v0.0.1-go$v.linux-amd64"
    tar_det "$W/$v-$i/racine" "$W/$v-$i/couche.tar" bin tmp usr
    crane append --insecure --oci-empty-base -f "$W/$v-$i/couche.tar" -t "$R/builder:$v-$i" >/dev/null 2>"$W/crane.err" || cat "$W/crane.err"
    crane mutate --insecure "$R/builder:$v-$i" --set-platform linux/amd64 -t "$R/builder:$v-$i" \
      -e PATH=/usr/local/go/bin:/bin -e HOME=/tmp -e CGO_ENABLED=0 -e GOTOOLCHAIN=local -e GOFLAGS=-mod=readonly -e GOSUMDB=off >/dev/null 2>"$W/crane.err" || cat "$W/crane.err"
    echo "$v $i : couche $(sha256sum < "$W/$v-$i/couche.tar" | cut -c1-16) ($(stat -c %s "$W/$v-$i/couche.tar") octets), image $(crane digest --insecure "$R/builder:$v-$i")"
    chmod -R u+w "$W/$v-$i"
  done
done
attendu "témoin 1.26.10 : image épinglée par construction.sh" "$(crane digest --insecure "$R/builder:1.26.10-a")" "$REF"
attendu "1.26.11 : identique sur deux assemblages" "$(crane digest --insecure "$R/builder:1.26.11-a")" "$(crane digest --insecure "$R/builder:1.26.11-b")"
attendu "1.26.11 : go de l'image" "$(env -u GOROOT -u GOBIN "$W/1.26.11-a/racine/usr/local/go/bin/go" version)" "go version go1.26.11 linux/amd64"
echo "BUILDER PRÉDIT|$(crane digest --insecure "$R/builder:1.26.11-a")"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
fin; pid=
find "$W" -delete
sed -i "s#$HOME#~#g" "$J"
cat "$J"
