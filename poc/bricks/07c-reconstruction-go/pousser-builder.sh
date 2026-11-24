#!/usr/bin/env bash
# Brique 07c, étape 3 : image de build de la voie D en Go 1.26.11 poussée dans le VRAI Zot (accord nommé du propriétaire du
# 2026-11-24, « J'autorise »), dépôt plateforme/builder-go-voie-d, tag NEUF go1.26.11 (les tags a et b de 1.26.10 restent).
# Copie de predire-builder.sh : assemblage sur le registre jetable local (deux fois, témoin 1.26.10 compris), puis crane copy
# PAR DIGEST du seul manifeste final vers le vrai Zot, compte poc-ecriture (auth au format docker, 0600, effacée à la fin).
# Assemblage recopié de voie-d.sh (racine_builder, tar_det, crane append --oci-empty-base puis mutate, mêmes variables) ;
# témoin : Go 1.26.10 doit redonner d50ae57551c3… (image épinglée par construction.sh), sinon la recopie est fausse.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
W=$HOME/.cache/supply-chain-poc/07c/pousser-builder
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
O=$HOME/.cache/supply-chain-poc/outils
BUSYBOX=$O/busybox/bin/busybox
REF=sha256:d50ae57551c381b591540643fdfee12dd251ae16675c3c69fde221f8e9c28b67
R=127.0.0.1:5077
Z=192.168.161.13:5000/plateforme/builder-go-voie-d
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
ATTENDU=sha256:8c11e856b10fcc3dce8d22815b803d95e2f643cda265cfd3ebdaed8615b2edf7   # predire-builder.log
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
attendu "1.26.11 : digest prédit à sec" "$(crane digest --insecure "$R/builder:1.26.11-a")" "$ATTENDU"
echo "## vrai Zot"
attendu "tag go1.26.11 absent avant" "$(SSL_CERT_FILE=$CA crane ls "$Z" | grep -c '^go1.26.11$')" 0
avant=$(for t in a b; do SSL_CERT_FILE=$CA crane digest "$Z:$t"; done | paste -sd' ')
mkdir -p -m 0700 "$W/docker"
(umask 077 && printf '{"auths":{"192.168.161.13:5000":{"auth":"%s"}}}\n' \
  "$(printf '%s:%s' poc-ecriture "$(cat "$HOME/.cache/supply-chain-poc/08/secrets/zot-poc-ecriture.password")" | base64 -w0)" > "$W/docker/config.json")
if [ "$KO" = 0 ]; then
  # pas de crane copy --insecure, qui couperait aussi la vérification TLS du vrai Zot : layout OCI local, puis push vérifié
  crane pull --insecure --format=oci "$R/builder@$ATTENDU" "$W/layout" > "$W/copie.out" 2>&1; echo "layout : code $?"
  DOCKER_CONFIG=$W/docker SSL_CERT_FILE=$CA crane push "$W/layout" "$Z:go1.26.11" >> "$W/copie.out" 2>&1; echo "poussée : code $?"
else echo "copie NON faite : écart avant la poussée"; fi
find "$W/docker" -delete
attendu "lecture anonyme du tag go1.26.11" "$(SSL_CERT_FILE=$CA crane digest "$Z:go1.26.11" 2>&1)" "$ATTENDU"
attendu "lecture anonyme par digest" "$(SSL_CERT_FILE=$CA crane digest "$Z@$ATTENDU" 2>&1)" "$ATTENDU"
attendu "couche relue = couche du registre jetable" "$(SSL_CERT_FILE=$CA crane manifest "$Z@$ATTENDU" | jq -r '.layers[0].digest')" "$(crane manifest --insecure "$R/builder@$ATTENDU" | jq -r '.layers[0].digest')"
SSL_CERT_FILE=$CA crane config "$Z@$ATTENDU" | jq -c '{architecture, os, Env: .config.Env}'
attendu "tags a et b inchangés (1.26.10)" "$(for t in a b; do SSL_CERT_FILE=$CA crane digest "$Z:$t"; done | paste -sd' ')" "$avant"
echo "IMAGE DE BUILD|192.168.161.13:5000/plateforme/builder-go-voie-d@$ATTENDU"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
fin; pid=
find "$W" -delete
sed -i "s#$HOME#~#g" "$J"
cat "$J"
