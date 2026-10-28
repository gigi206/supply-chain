#!/usr/bin/env bash
# Brique 04 : build hermétique et image OCI bit à bit avec BuildKit.
#
# 1. Image de build : toolchain Go + busybox statique, construite par BuildKit
#    (SOURCE_DATE_EPOCH, rewrite-timestamp), deux fois → même digest.
# 2. sample-app : compilée dans BuildKit sans réseau (`RUN --network=none`), image
#    de build épinglée par digest, fermeture Hermeto en contexte nommé.
#    Deux builds sans cache, depuis deux chemins → même digest d'image.
# 3. Le binaire extrait de l'image est comparé à celui de la brique 03, compilé
#    hors BuildKit avec la même toolchain.
# 4. Négatif : sans la fermeture, la compilation échoue (aucun module disponible) :
#    la fermeture est bien la seule source des dépendances.
# 5. Négatif : une étape `--network=none` ne peut pas sortir sur le réseau.
#
# Usage : BUILDKIT_HOST=unix://…/buildkitd.sock GOROOT_DIR=<toolchain Go ≥ 1.26.7>
#         BUSYBOX=<busybox statique> B03=<WORKDIR du banc 03> WORKDIR=/tmp/b04 ./bench.sh
# Démon : buildkitd (oci worker, runc), éphémère, sans Docker.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
W=${WORKDIR:?}
: "${BUILDKIT_HOST:?}" "${GOROOT_DIR:?}" "${BUSYBOX:?}" "${B03:?}"
export BUILDKIT_HOST
BUILDCTL=${BUILDCTL:-buildctl}
ko=0

chmod -R u+w -- "$W" 2>/dev/null || true
rm -rf -- "${W:?}"
mkdir -p "$W"
cd "$W"
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; ko=1; }
digest() { tar -xOf "$1" index.json | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["manifests"][0]["digest"])'; }
build() { # $1 = sortie (tar OCI), $2… = options buildctl
  local out=$1
  shift
  "$BUILDCTL" build --frontend dockerfile.v0 --no-cache \
    --opt build-arg:SOURCE_DATE_EPOCH=0 \
    --output "type=oci,dest=$out,rewrite-timestamp=true" "$@" > /dev/null 2> "$out.log"
}

# 1. Image de build.
mkdir -p builder-ctx
cp -a "$GOROOT_DIR" builder-ctx/go
cp "$BUSYBOX" builder-ctx/busybox
chmod -R u+w builder-ctx
for i in 1 2; do
  build "builder-$i.tar" --local context=builder-ctx --local dockerfile="$here" --opt filename=Dockerfile.builder
done
b1=$(digest builder-1.tar)
b2=$(digest builder-2.tar)
[ "$b1" = "$b2" ] && ok "image de build identique sur 2 builds ($b1)" || ko "image de build : $b1 ≠ $b2"
mkdir -p builder-layout
tar -xf builder-1.tar -C builder-layout

# 2. sample-app, deux builds sans cache depuis deux chemins.
for src in src-1 autre/src-2; do
  mkdir -p "$src"
  cp -a "$B03/canon/source/." "$src/"
  cp -a "$B03/build-apres/web/dist" "$src/web/"  # interface construite hors ligne (brique 03)
  printf 'web/node_modules\n.git\n' > "$src/.dockerignore"
done
for i in 1 2; do
  src=src-1
  [ "$i" = 2 ] && src=autre/src-2
  build "app-$i.tar" --local context="$src" --local dockerfile="$here" --opt filename=Dockerfile \
    --oci-layout builder="$W/builder-layout" --opt "context:builder=oci-layout://builder@$b1" \
    --local deps="$B03/canon/deps" --opt context:deps=local:deps
done
a1=$(digest app-1.tar)
a2=$(digest app-2.tar)
[ "$a1" = "$a2" ] && ok "image sample-app identique sur 2 builds sans cache, 2 chemins ($a1)" || ko "image : $a1 ≠ $a2"

# 3. Binaire extrait de l'image, comparé au build de la brique 03.
mkdir -p app-layout
tar -xf app-1.tar -C app-layout
python3 -I - app-layout <<'PY' > layer.digest
import json, sys
root = sys.argv[1]
idx = json.load(open(f"{root}/index.json"))
m = json.load(open(f"{root}/blobs/sha256/{idx['manifests'][0]['digest'][7:]}"))
print(m["layers"][-1]["digest"][7:])
PY
mkdir -p extrait
tar -xzf "app-layout/blobs/sha256/$(cat layer.digest)" -C extrait
x=$(sha256sum < extrait/sample-app | cut -c1-64)
y=$(sha256sum < "$B03/build-apres/sample-app" | cut -c1-64)
[ "$x" = "$y" ] && ok "binaire dans l'image = binaire de la brique 03, compilé hors BuildKit ($x)" \
  || ko "binaire : BuildKit $x ≠ brique 03 $y"

# 4. Négatif : sans la fermeture, le build sans réseau ne trouve aucun module.
mkdir -p vide/deps/gomod/pkg/mod/cache/download
if build app-ko.tar --local context=src-1 --local dockerfile="$here" --opt filename=Dockerfile \
    --oci-layout builder="$W/builder-layout" --opt "context:builder=oci-layout://builder@$b1" \
    --local deps="$W/vide" --opt context:deps=local:deps; then
  ko "build sans fermeture réussi"
else
  ok "négatif : build sans fermeture refusé ($(grep -m1 -o 'github.com/go-chi/chi/v5@v5.2.3: [^"]*' app-ko.tar.log | head -c 120))"
fi

# 5. Négatif : une étape `--network=none` ne peut pas sortir sur le réseau.
mkdir -p net-ctx
printf 'FROM builder\nRUN --network=none wget -T 5 -q -O /dev/null http://proxy.golang.org/\n' > net-ctx/Dockerfile
if build net-ko.tar --local context=net-ctx --local dockerfile=net-ctx --opt filename=Dockerfile \
    --oci-layout builder="$W/builder-layout" --opt "context:builder=oci-layout://builder@$b1"; then
  ko "sortie réseau possible depuis une étape --network=none"
else
  ok "négatif : sortie réseau refusée dans l'étape --network=none ($(grep -m1 -o 'wget: [^"]*' net-ko.tar.log | head -c 80))"
fi

exit $ko
