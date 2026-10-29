#!/usr/bin/env bash
# Sources de sample-app pour les constructeurs rpm et deb (banc A2, briques 05 et 06).
# Produit, de façon reproductible, dans ~/.cache/supply-chain-poc/packaging/ :
#   sample-app-1.0.0.tar.gz          archive complète : sources (git archive de poc/sample-app),
#                                    modules Go (vendor/, vérifiés par go.sum) et « marked »
#                                    (web/node_modules/marked, vérifié par l'intégrité sha512 du lockfile) ;
#   sample-app_1.0.0.orig.tar.gz     la même archive, nommée pour Debian ;
#   sample-app_1.0.0-1.dsc, sample-app_1.0.0-1.debian.tar.xz   paquet source Debian (dpkg-source) ;
#   sample-app.spec                  copie du spec ;  SHA256SUMS.
# Le build lui-même se fait ensuite sans réseau (GOPROXY=off, aucun npm).
#
# Usage (racine du dépôt) : mise run packaging:sources
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
racine=$(git -C "$here" rev-parse --show-toplevel)
NOM=sample-app
VERSION=1.0.0
OUT=${PACKAGING_DIR:-$HOME/.cache/supply-chain-poc/packaging}
W=$(mktemp -d -p "${XDG_CACHE_HOME:-$HOME/.cache}")
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf -- "$W"' EXIT
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)   # go de mise.toml, pas de shim

commit=$(git -C "$racine" log -1 --format=%H -- poc/sample-app)
SDE=$(git -C "$racine" log -1 --format=%ct -- poc/sample-app)   # = date de debian/changelog et du %changelog
echo "sample-app au commit $commit, SOURCE_DATE_EPOCH=$SDE ($(date -u -d "@$SDE" +%Y-%m-%dT%H:%M:%SZ))"
[[ -z $(git -C "$racine" status --porcelain -- poc/sample-app poc/packaging) ]] || echo "ATTENTION : modifications non commitées dans poc/sample-app ou poc/packaging"

S=$W/$NOM-$VERSION
mkdir -p "$S"
git -C "$racine" archive "$commit:poc/sample-app" | tar -x -C "$S"

echo "## Modules Go (vendor/)"
(cd "$S" && GOTOOLCHAIN=local GOFLAGS=-mod=mod GOMODCACHE=$W/gomodcache go mod vendor && GOMODCACHE=$W/gomodcache go mod verify)
echo "go : $(go version)"
cut -d' ' -f2,3 "$S/vendor/modules.txt" | grep -v '^explicit' | sed 's/^/  /'

echo "## marked (web/node_modules/marked)"
lock=$S/web/package-lock.json
url=$(jq -r '.packages["node_modules/marked"].resolved' "$lock")
integ=$(jq -r '.packages["node_modules/marked"].integrity' "$lock")
curl -fsSL "$url" -o "$W/marked.tgz"
calc="sha512-$(openssl dgst -sha512 -binary "$W/marked.tgz" | base64 -w0)"
[[ $calc == "$integ" ]] || { echo "ÉCHEC : intégrité de $url"; exit 1; }
echo "  $url : intégrité conforme au lockfile"
mkdir -p "$S/web/node_modules/marked"
tar -xzf "$W/marked.tgz" -C "$S/web/node_modules/marked" --strip-components=1

echo "## Archives"
mkdir -p "$OUT"
rm -f "$OUT"/"$NOM"[-_]*
tar -C "$W" --sort=name --mtime="@$SDE" --owner=0 --group=0 --numeric-owner --mode=go-w,a+rX \
    --format=gnu -cf - "$NOM-$VERSION" | gzip -n -9 > "$OUT/$NOM-$VERSION.tar.gz"
cp "$OUT/$NOM-$VERSION.tar.gz" "$OUT/${NOM}_$VERSION.orig.tar.gz"
cp "$here/$NOM.spec" "$OUT/"
cp -r "$here/debian" "$S/"
cp "$OUT/${NOM}_$VERSION.orig.tar.gz" "$W/"   # dpkg-source cherche l'archive amont à côté du répertoire source
(cd "$W" && SOURCE_DATE_EPOCH=$SDE dpkg-source -q -b "$NOM-$VERSION" >/dev/null)
mv "$W/${NOM}_$VERSION-1.dsc" "$W/${NOM}_$VERSION-1.debian.tar.xz" "$OUT/"
(cd "$OUT" && sha256sum "$NOM-$VERSION.tar.gz" "${NOM}_$VERSION.orig.tar.gz" "${NOM}_$VERSION-1.dsc" \
   "${NOM}_$VERSION-1.debian.tar.xz" "$NOM.spec" | tee SHA256SUMS)
