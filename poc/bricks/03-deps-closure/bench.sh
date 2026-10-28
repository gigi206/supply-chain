#!/usr/bin/env bash
# Brique 03 : fermetures Hermeto dans un registre OCI, un fichier par couche.
#
# 1. oras v1.3.5 puis v1.3.6 (une dépendance change) : couches partagées et
#    croissance du stockage du registre.
# 2. Restauration de v1.3.6 par digest : arbre identique, puis build hors réseau
#    identique à celui fait depuis la fermeture d'origine.
# 3. sample-app (gomod + npm) : fermeture poussée, supprimée, restaurée aux mêmes
#    chemins canoniques, puis binaire et interface identiques.
# 4. Tests négatifs : restauration par tag refusée ; blob altéré dans le stockage
#    du registre refusé (si ZOT_DATA est fourni).
#
# Usage : HERMETO=… ORAS=… GO=… REG=localhost:5000 WORKDIR=… [ZOT_DATA=…] ./bench.sh
# Prérequis : Go ≥ 1.26.7 (exigé par oras 1.3.6), Node/npm, git, unzip, unshare.
# Seuls le téléchargement des sources d'oras et les prefetch Hermeto utilisent le réseau.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
W=${WORKDIR:?WORKDIR obligatoire}
REG=${REG:?REG obligatoire}
HERMETO=${HERMETO:-hermeto}
GO=${GO:-go}
GOBIN_DIR=$(dirname "$(command -v "$GO")")
export ORAS=${ORAS:-oras} ORAS_OPTS=${ORAS_OPTS:---plain-http}
CLOSURE=$HERE/closure.sh
ko=0

chmod -R u+w -- "$W" 2>/dev/null || true
rm -rf -- "${W:?}"
mkdir -p "$W"
cd "$W"

ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; ko=1; }
size() { [ -n "${ZOT_DATA:-}" ] && du -sb "$ZOT_DATA" | cut -f1 || echo 0; }

# Dépôt git avec un remote origin joignable, comme l'exige Hermeto ($1 = sources, $2 = tag).
git_repo() {
  git -C "$1" init -q
  git -C "$1" add -A
  git -C "$1" -c user.name=bench -c user.email=bench@example.invalid commit -qm "$2"
  git clone -q --bare "$1" "$1.origin.git"
  git -C "$1" remote add origin "file://$1.origin.git"
  git -C "$1" tag "$2"
  git -C "$1" push -q origin "$2"
}

# Build Go hors réseau : fermeture servie en GOPROXY, caches vierges.
# $1 = sources, $2 = fermeture, $3 = commande de build.
offline() {
  unshare -rn env -i PATH="$GOBIN_DIR:$PATH" HOME="$1" \
    GOCACHE="$(mktemp -d -p "$W")" GOMODCACHE="$(mktemp -d -p "$W")" GOTOOLCHAIN=local \
    GOPROXY="file://$2/deps/gomod/pkg/mod/cache/download" GOSUMDB=off \
    GOFLAGS=-mod=readonly CGO_ENABLED=0 npm_config_cache="$(mktemp -d -p "$W")" \
    bash --norc -euc "cd '$1' && $3"
}

tree_sum() { (cd "$1" && find . -type f ! -name bom.json -exec sha256sum {} + | LC_ALL=C sort -k2); }

# 1. oras v1.3.5 et v1.3.6.
for v in v1.3.5 v1.3.6; do
  zip=$(GOMODCACHE="$W/gomodcache" GOFLAGS=-mod=mod "$GO" mod download -json "oras.land/oras@$v" |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)["Zip"])')
  mkdir -p "tmp-$v" "oras-$v"
  unzip -q "$zip" -d "tmp-$v"
  cp -a "tmp-$v/oras.land/oras@$v/." "oras-$v/"
  chmod -R u+w "oras-$v"
  git_repo "$W/oras-$v" "$v"
  "$HERMETO" --log-level warning fetch-deps --source "oras-$v" --output "deps-$v" '{"type": "gomod", "path": "."}'
done

s0=$(size)
ref1=$("$CLOSURE" push "deps-v1.3.5" "$REG/deps/oras:v1.3.5")
s1=$(size)
ref2=$("$CLOSURE" push "deps-v1.3.6" "$REG/deps/oras:v1.3.6")
s2=$(size)
"$ORAS" manifest fetch $ORAS_OPTS "$ref1" > m1.json
"$ORAS" manifest fetch $ORAS_OPTS "$ref2" > m2.json
python3 -I - m1.json m2.json <<'PY'
import json, sys
m1, m2 = (json.load(open(p)) for p in sys.argv[1:3])
known = {l["digest"] for l in m1["layers"]}
total = sum(l["size"] for l in m2["layers"])
shared = [l for l in m2["layers"] if l["digest"] in known]
octets = sum(l["size"] for l in shared)
print(f"v1.3.6 : {len(m2['layers'])} couches, {total} octets ; partagées avec v1.3.5 : "
      f"{len(shared)} couches, {octets} octets ({100 * octets / total:.1f} %)")
for l in m2["layers"]:
    if l["digest"] not in known:
        print("  nouvelle :", l["annotations"]["org.opencontainers.image.title"])
PY
[ -n "${ZOT_DATA:-}" ] && echo "Registre : +$((s1 - s0)) octets pour v1.3.5, +$((s2 - s1)) octets pour v1.3.6"
[ "$("$CLOSURE" push "deps-v1.3.5" "$REG/deps/oras:v1.3.5-bis")" = "$ref1" ] \
  && ok "même fermeture repoussée : même digest ($ref1)" || ko "digest non déterministe"

# 2. Restauration par digest et build hors réseau.
"$CLOSURE" pull "$ref2" restore-v1.3.6
diff <(tree_sum deps-v1.3.6) <(tree_sum restore-v1.3.6) >/dev/null \
  && ok "arbre restauré identique ($(tree_sum restore-v1.3.6 | wc -l) fichiers)" || ko "arbre restauré différent"
for c in deps-v1.3.6 restore-v1.3.6; do
  cp -a oras-v1.3.6 "build-$c"
  offline "$W/build-$c" "$W/$c" "go build -trimpath -buildvcs=false -ldflags '-s -w -buildid=' -o oras ./cmd/oras" 2>/dev/null
done
a=$(sha256sum < build-deps-v1.3.6/oras | cut -c1-64)
b=$(sha256sum < build-restore-v1.3.6/oras | cut -c1-64)
[ "$a" = "$b" ] && ok "oras construit depuis la fermeture restaurée : identique ($a)" || ko "oras : $a ≠ $b"

# 3. sample-app (gomod + npm), chemins canoniques fixes : Hermeto inscrit des chemins
#    absolus (.build-config.json, lockfile npm réécrit), la restauration doit donc
#    reprendre les mêmes chemins, comme le feront les pods de build.
mkdir -p canon/source
git -C "$REPO" archive HEAD poc/sample-app | tar -x --strip-components=2 -C canon/source
git_repo "$W/canon/source" v1.0.0
"$HERMETO" --log-level warning fetch-deps --source canon/source --output canon/deps \
  '[{"type": "gomod", "path": "."}, {"type": "npm", "path": "web"}]'
"$HERMETO" --log-level warning inject-files canon/deps --for-output-dir "$W/canon/deps"
web='cd web && npm ci --no-audit --no-fund --ignore-scripts >/dev/null && npm run -s build && cd ..'
app="go build -trimpath -buildvcs=false -ldflags '-s -w -buildid= -X main.Version=1.0.0' -o sample-app ."
cp -a canon/source build-avant
offline "$W/build-avant" "$W/canon/deps" "$web && $app" 2>/dev/null
ref3=$("$CLOSURE" push canon/deps "$REG/deps/sample-app:v1.0.0")
rm -rf canon/deps
"$CLOSURE" pull "$ref3" canon/deps
cp -a canon/source build-apres
offline "$W/build-apres" "$W/canon/deps" "$web && $app" 2>/dev/null
for f in sample-app web/dist/index.html web/dist/marked.umd.js; do
  a=$(sha256sum < "build-avant/$f" | cut -c1-64)
  b=$(sha256sum < "build-apres/$f" | cut -c1-64)
  [ "$a" = "$b" ] && ok "sample-app $f identique après restauration ($a)" || ko "sample-app $f : $a ≠ $b"
done

# 4. Tests négatifs.
"$CLOSURE" pull "$REG/deps/oras:v1.3.6" refus-tag 2>/dev/null && ko "pull par tag accepté" || ok "pull par tag refusé"
if [ -n "${ZOT_DATA:-}" ]; then
  d=$(python3 -I -c 'import json, sys
m = json.load(open(sys.argv[1]))
print(next(l["digest"] for l in m["layers"] if l["annotations"]["org.opencontainers.image.title"].endswith("v2.7.0.zip")))' m2.json)
  blob=$ZOT_DATA/deps/oras/blobs/sha256/${d#sha256:}
  cp "$blob" blob.bak
  python3 -I -c 'import sys
p = sys.argv[1]; d = bytearray(open(p, "rb").read()); d[1000] ^= 0xff; open(p, "wb").write(d)' "$blob"
  if out=$("$CLOSURE" pull "$ref2" refus-blob 2>&1); then
    ko "blob altéré accepté"
  elif grep -q "mismatched digest" <<<"$out"; then
    ok "blob altéré dans le registre refusé (mismatched digest)"
  else
    ko "pull refusé pour une autre raison : $out"
  fi
  cp blob.bak "$blob"
fi

exit $ko
