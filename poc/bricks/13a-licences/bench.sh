#!/usr/bin/env bash
# Brique 13a : licences déclarées, REUSE et bundle de sources en referrer.
#
# 1. oras v1.3.6 et sample-app : fermeture Hermeto extraite sans réseau
#    (`go mod download` depuis la fermeture), SBOM Syft avec les licences du cache
#    de modules et des lockfiles npm, puis verdict (licences.py).
#    Attendu : 0 NOASSERTION, 0 ERROR, 100 % d'expressions valides.
#    Négatif : le même SBOM sans recherche de licences → NOASSERTION → ERROR.
# 2. Cas synthétiques : GPL refusée, expression invalide, NOASSERTION levée par une
#    curation, LGPL avec source présente dans la fermeture → bundle de sources
#    attaché en referrer à l'image (rétention 10 ans) ; LGPL sans source → ERROR.
# 3. REUSE : sample-app conforme ; un fichier sous une autre licence sans son texte
#    → non conforme.
#
# Usage : B03=<WORKDIR du banc de la brique 03> SPDX=<…/json> REG=localhost:5000 \
#         WORKDIR=/tmp/b13 [SYFT=… REUSE=… GO=… ORAS=… CRANE=…] ./bench.sh
# Aucun accès réseau (registre local seulement).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
W=${WORKDIR:?}
REG=${REG:?}
B03=${B03:?}
SPDX=${SPDX:?}
SYFT=${SYFT:-syft} REUSE=${REUSE:-reuse} GO=${GO:-go} ORAS=${ORAS:-oras} CRANE=${CRANE:-crane}
read -r -a oras_opts <<<"${ORAS_OPTS:---plain-http}"
ko=0

chmod -R u+w -- "$W" 2>/dev/null || true
rm -rf -- "${W:?}"
mkdir -p "$W"
cd "$W"
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; ko=1; }
verdict() { # $1 = SBOM, $2 = fermeture, $3… = options ; imprime le résumé, renvoie le code de licences.py
  local rc=0
  python3 -I "$here/licences.py" --sbom "$1" --policy "$here/policy.json" --spdx "$SPDX/licenses.json" \
    --exceptions "$SPDX/exceptions.json" --closure "$2" "${@:3}" > "$1.lic.json" || rc=$?
  python3 -I -c 'import json, sys
p = json.load(open(sys.argv[1])); v = p["violations"]
print("%d composants, erreurs %d, avertissements %d, NOASSERTION %d, invalides %d"
      % (len(p["components"]), v["error"], v["warning"], p["noassertion"], p["invalid"]))' "$1.lic.json"
  return $rc
}
# Extrait toute la fermeture Go sans réseau ($1 = sources, $2 = fermeture, $3 = cache).
extract() {
  (cd "$1" && unshare -rn env -i PATH="$PATH" HOME="$W" GOMODCACHE="$3" GOTOOLCHAIN=local GOSUMDB=off \
    GOFLAGS=-mod=readonly GOPROXY="file://$2/deps/gomod/pkg/mod/cache/download" "$GO" mod download)
}
syft_dir() { # $1 = sources, $2 = cache de modules, $3 = sortie, $4 = recherche de licences (true|false)
  unshare -rn env SYFT_CHECK_FOR_APP_UPDATE=false SYFT_GOLANG_SEARCH_LOCAL_MOD_CACHE_LICENSES="$4" \
    SYFT_GOLANG_LOCAL_MOD_CACHE_DIR="$2" "$SYFT" scan "dir:$1" -o "cyclonedx-json=$3" -q
}

# 1. Dépendances réelles.
cp -a "$B03/oras-v1.3.6" oras
chmod -R u+w oras
extract "$W/oras" "$B03/deps-v1.3.6" "$W/mod-oras"
syft_dir oras "$W/mod-oras" oras.json true
r=$(verdict oras.json "$B03/deps-v1.3.6") && ok "oras v1.3.6 : $r" || ko "oras v1.3.6 : $r"
syft_dir oras "$W/mod-oras" oras-sans.json false
r=$(verdict oras-sans.json "$B03/deps-v1.3.6") && ko "licences non recherchées acceptées : $r" \
  || ok "négatif, licences non recherchées : refusé ($r)"

cp -a "$B03/canon/source" app
chmod -R u+w app
extract "$W/app" "$B03/canon/deps" "$W/mod-app"
syft_dir app "$W/mod-app" app.json true
r=$(verdict app.json "$B03/canon/deps") && ok "sample-app : $r" || ko "sample-app : $r"

# 2. Cas synthétiques.
mkdir -p fx/deps/gomod/pkg/mod/cache/download/example.com/lgpl-demo/@v
python3 -I - fx/deps/gomod/pkg/mod/cache/download/example.com/lgpl-demo/@v/v1.0.0.zip <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("example.com/lgpl-demo@v1.0.0/LICENSE", "GNU LESSER GENERAL PUBLIC LICENSE Version 2.1\n")
    z.writestr("example.com/lgpl-demo@v1.0.0/demo.go", "package demo\n")
PY
cat > fx.json <<'EOF'
{"components": [
  {"type": "library", "purl": "pkg:golang/example.com/gpl-demo@v1.0.0", "licenses": [{"license": {"id": "GPL-3.0-or-later"}}]},
  {"type": "library", "purl": "pkg:npm/invalide@1.0.0", "licenses": [{"expression": "MIT AND (Apache-2.0"}]},
  {"type": "library", "purl": "pkg:npm/sans-licence@1.0.0"},
  {"type": "library", "purl": "pkg:golang/example.com/lgpl-demo@v1.0.0", "licenses": [{"license": {"id": "LGPL-2.1-only"}}]},
  {"type": "library", "purl": "pkg:golang/example.com/lgpl-absent@v1.0.0", "licenses": [{"license": {"id": "LGPL-2.1-only"}}]}
]}
EOF
cat > curations.json <<'EOF'
[{"purl": "pkg:npm/sans-licence@1.0.0", "expression": "MIT", "reason": "fixture du banc", "reviewer": "banc"}]
EOF
verdict fx.json "$W/fx" --curations curations.json > /dev/null || true
python3 -I - fx.json.lic.json <<'PY' && ok "cas synthétiques : verdicts attendus" || ko "cas synthétiques"
import json, sys
c = {x["purl"]: x for x in json.load(open(sys.argv[1]))["components"]}
want = {"pkg:golang/example.com/gpl-demo@v1.0.0": "error", "pkg:npm/invalide@1.0.0": "error",
        "pkg:npm/sans-licence@1.0.0": "ok", "pkg:golang/example.com/lgpl-demo@v1.0.0": "warning",
        "pkg:golang/example.com/lgpl-absent@v1.0.0": "error"}
bad = {p: c[p]["verdict"] for p in want if c[p]["verdict"] != want[p]}
for p in want:
    print(f"     {c[p]['verdict']:8} {p} : {'; '.join(c[p]['reasons']) or c[p]['expression']}")
sys.exit(1 if bad else 0)
PY

# Bundle de sources : fichiers des obligations satisfaites, attachés en referrer à l'image.
mkdir -p layer sources
echo "binaire de démonstration" > layer/app
tar -C layer -cf layer.tar app
img=$("$CRANE" append --oci-empty-base -f layer.tar -t "$REG/porte13a/app:1" --insecure 2>/dev/null | tail -1)
python3 -I -c 'import json, sys
for o in json.load(open(sys.argv[1]))["sourceObligations"]:
    if o["file"]: print(o["file"])' fx.json.lic.json | while read -r f; do cp "fx/$f" sources/; done
(cd sources && "$ORAS" attach "${oras_opts[@]}" --no-tty \
  --artifact-type application/vnd.supply-chain.source-bundle.v1 \
  --annotation supply-chain.example/retention=P10Y \
  --annotation "supply-chain.example/licences-policy=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["policy"]["sha256"])' ../fx.json.lic.json)" \
  "$img" ./* >/dev/null)
n=$("$ORAS" discover "${oras_opts[@]}" --format json --artifact-type application/vnd.supply-chain.source-bundle.v1 "$img" |
  python3 -I -c 'import json, sys; d = json.load(sys.stdin); print(len(d.get("referrers") or d.get("manifests") or []))')
[ "$n" = 1 ] && ok "bundle de sources attaché en referrer à $img (rétention P10Y)" || ko "bundle de sources absent"

# 3. REUSE.
git -C "$repo" archive HEAD poc/sample-app | tar -x --strip-components=2 --one-top-level=reuse-ok
"$REUSE" --root reuse-ok lint > reuse-ok.log 2>&1 && ok "REUSE : sample-app conforme" || ko "REUSE : sample-app non conforme"
cp -a reuse-ok reuse-ko
printf '// SPDX-License-Identifier: GPL-3.0-only\npackage main\n' > reuse-ko/vendored.go
"$REUSE" --root reuse-ko lint > reuse-ko.log 2>&1 && ko "REUSE : fichier GPL sans texte accepté" \
  || ok "négatif REUSE : fichier sous GPL-3.0-only sans texte de licence refusé ($(grep -m1 -o 'Missing licenses: .*' reuse-ko.log))"

exit $ko
