#!/usr/bin/env bash
# Banc B, référence (ADR 0000 §3) : fermeture Hermeto de sample-app, deux builds
# hors réseau dans deux chemins, puis trois tests d'altération de la fermeture.
#
# Usage : HERMETO=/chemin/vers/hermeto WORKDIR=/tmp/bench-b-hermeto ./hermeto.sh
# Prérequis : git, go, node/npm, python3, unshare (user namespaces).
# Seul le prefetch (étape 2) utilise le réseau.
set -euo pipefail

HERMETO=${HERMETO:-hermeto}
W=${WORKDIR:?WORKDIR obligatoire}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
VERSION=1.0.0
LDFLAGS="-s -w -buildid= -X main.Version=$VERSION"
ko=0

mkdir -p "$W"
cd "$W"
chmod -R u+w -- "$W" 2>/dev/null || true
rm -rf -- "${W:?}"/{src,origin.git,deps,run-1,autre-chemin,alt-*}

# 1. Sources. Hermeto exige un dépôt git avec un remote « origin » joignable
#    (il y lit les tags pour versionner le module principal). Sur la plateforme,
#    c'est le miroir Forgejo ; ici, un dépôt nu local.
mkdir src
git -C "$REPO" archive HEAD poc/sample-app | tar -x --strip-components=2 -C src
git -C src init -q
git -C src add -A
git -C src -c user.name=bench -c user.email=bench@example.invalid commit -qm "sample-app $VERSION"
git clone -q --bare src origin.git
git -C src remote add origin "file://$W/origin.git"
git -C src tag "v$VERSION"
git -C src push -q origin "v$VERSION"

# 2. Prefetch (réseau) et réécriture des lockfiles vers la fermeture.
"$HERMETO" --log-level warning fetch-deps --source src --output deps \
  '[{"type": "gomod", "path": "."}, {"type": "npm", "path": "web"}]'
"$HERMETO" --log-level warning inject-files deps --for-output-dir "$W/deps"
echo "Fermeture : $(du -sb deps/deps | cut -f1) octets"

# 3. Build sans réseau. On n'utilise PAS l'environnement de `hermeto generate-env` :
#    il fait de la fermeture le GOMODCACHE, que Go croit sans revérifier (voir T1),
#    et le build y écrit (GOCACHE, modules extraits).
#    La fermeture sert de GOPROXY en lecture seule ; caches vierges à chaque build.
#    $1 = sources, $2 = fermeture.
build() {
  unshare -rn env -i PATH="$PATH" HOME="$1" \
    GOCACHE="$(mktemp -d)" GOMODCACHE="$(mktemp -d)" GOTOOLCHAIN=local \
    GOPROXY="file://$2/deps/gomod/pkg/mod/cache/download" GOSUMDB=off \
    GOFLAGS=-mod=readonly CGO_ENABLED=0 npm_config_cache="$(mktemp -d)" \
    bash --norc -euc 'cd "$1/web"
      npm ci --no-audit --no-fund --ignore-scripts >/dev/null
      npm run -s build
      cd "$1"
      go build -trimpath -buildvcs=false -ldflags "$2" -o sample-app .' _ "$1" "$LDFLAGS"
}

cp -a src run-1
mkdir autre-chemin
cp -a src autre-chemin/run-2
build "$W/run-1" "$W/deps"
build "$W/autre-chemin/run-2" "$W/deps"
for f in sample-app web/dist/index.html web/dist/marked.umd.js; do
  a=$(sha256sum < "run-1/$f" | cut -c1-64)
  b=$(sha256sum < "autre-chemin/run-2/$f" | cut -c1-64)
  [ "$a" = "$b" ] && r=identique || { r=DIFFÉRENT; ko=1; }
  echo "B-1 $f : $a ($r)"
done

# Copie de la fermeture et des sources pour un test d'altération ($1 = nom).
alt() {
  cp -a deps "alt-$1"
  cp -a src "alt-$1-src"
  sed -i "s|$W/deps/|$W/alt-$1/|g" "alt-$1-src/web/package-lock.json"
}
check() { # $1 = test, $2 = attendu (rejeté|accepté), $3 = code de sortie, $4 = motif de rejet attendu
  local obtenu=accepté
  [ "$3" -ne 0 ] && obtenu=rejeté
  # Un rejet pour une autre raison que celle attendue ne prouve rien.
  [ -n "${4:-}" ] && [ "$obtenu" = rejeté ] && ! grep -Eq "$4" "$W/test.log" && obtenu="rejeté pour une autre raison"
  [ "$obtenu" = "$2" ] && echo "$1 : $obtenu (attendu)" || { echo "$1 : $obtenu (ATTENDU : $2)"; ko=1; }
}
ZIP=deps/gomod/pkg/mod/cache/download/github.com/go-chi/chi/v5/@v/v5.2.3.zip
alter_zip() { # ajoute un fichier Go valide dans le zip de chi ($1 = copie de la fermeture)
  python3 -I -c 'import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "a") as z:
    z.writestr("github.com/go-chi/chi/v5@v5.2.3/altere.go", "package chi\nfunc init() { println(\"ALTERE\") }\n")' "$1/$ZIP"
}

# T1. Zip de chi altéré, avec la configuration de `hermeto generate-env`
#     (GOMODCACHE = fermeture). Go se fie au fichier .ziphash du cache au lieu de
#     recalculer l'empreinte : go build accepte le code injecté, seul `go mod verify` le voit.
alt t1
alter_zip alt-t1
t1() {
  unshare -rn env -i PATH="$PATH" HOME="$W/alt-t1-src" GOCACHE="$(mktemp -d)" \
    GOMODCACHE="$W/alt-t1/deps/gomod/pkg/mod" GOTOOLCHAIN=local GOFLAGS=-mod=readonly \
    GOPROXY="file://$W/alt-t1/deps/gomod/pkg/mod/cache/download" GOSUMDB=off CGO_ENABLED=0 \
    bash --norc -euc "cd '$W/alt-t1-src' && mkdir -p web/dist && touch web/dist/vide && $1"
}
rc=0; t1 'go build -o sample-app . && grep -q ALTERE sample-app' > "$W/test.log" 2>&1 || rc=$?
check "T1 zip Go altéré, env Hermeto, go build" accepté "$rc"
rc=0; t1 'go mod verify' > "$W/test.log" 2>&1 || rc=$?
check "T1 zip Go altéré, env Hermeto, go mod verify" rejeté "$rc" "zip has been modified"

# T2. Même altération, fermeture servie en GOPROXY et GOMODCACHE vierge :
#     Go recalcule l'empreinte du zip et go.sum le rejette.
alt t2
alter_zip alt-t2
rc=0; build "$W/alt-t2-src" "$W/alt-t2" > "$W/test.log" 2>&1 || rc=$?
check "T2 zip Go altéré, GOPROXY en lecture seule" rejeté "$rc" "checksum mismatch"

# T3. Archive npm valide mais contenu modifié : l'intégrité sha512 du lockfile la rejette.
alt t3
mkdir alt-t3-tgz
tar -xzf deps/deps/npm/marked-16.4.1.tgz -C alt-t3-tgz
echo '/* altéré */' >> alt-t3-tgz/package/lib/marked.umd.js
tar -czf alt-t3/deps/npm/marked-16.4.1.tgz -C alt-t3-tgz package
rc=0; build "$W/alt-t3-src" "$W/alt-t3" > "$W/test.log" 2>&1 || rc=$?
check "T3 archive npm altérée" rejeté "$rc" "EINTEGRITY|corrupted"

# 4. SBOM Hermeto : types de PURL et composants sans version.
python3 -I -c 'import collections, json, sys
c = json.load(open(sys.argv[1]))["components"]
types = collections.Counter(x["purl"].split("/")[0] for x in c)
sans_version = sum(1 for x in c if "@" not in x["purl"])
print(f"SBOM : {len(c)} composants, {dict(types)}, {sans_version} sans version (bibliothèque standard Go)")
for x in c:
    if "@" in x["purl"] and "type=package" not in x["purl"] and "vcs_url" not in x["purl"]:
        print("  ", x["purl"])' deps/bom.json

exit $ko
