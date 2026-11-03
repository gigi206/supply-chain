#!/usr/bin/env bash
# Brique 03, jalon F1 (protocole du 03/11/2026, validé par le propriétaire ; accord « Oui, tout ») : fermetures de Traefik
# (gomod et yarn 4.18.0) sur l'hôte, sans cluster. Prédictions : resultats/f1-predictions.md.
#   outils     Go 1.27.3 (module golang.org/toolchain, h1 comparé à sum.golang.org) et yarn 4.18.0 par corepack (sha512 du
#              packageManager), par les tâches mise outils:go-1.27 et outils:yarn ; contre-épreuve : sha512 faux refusé par
#              corepack (COREPACK_HOME jetable)
#   sources    Traefik v3.7.16 et v3.7.17 clonés par tag : commit, signature du tag selon GitHub, directive go, packageManager,
#              résolutions de yarn.lock qui ne viennent pas du registre npm
#   prefetch   hermeto fetch-deps gomod + yarn (webui) pour chaque tag, sous strace (connect) ; go et yarn passent par des
#              enrobages qui posent un proxy CONNECT journalisé (journal-connect.py) : noms contactés (D2) et connexions hors
#              du proxy ; tailles, fichiers, chemins absolus de la sortie dans la fermeture ; sources intactes après coup
#   registre   Zot éphémère (dedupe) : fermetures poussées par closure.sh, v3.7.16 puis v3.7.17, puis v3.7.17 une seconde fois
#              (même digest) ; croissance du stockage ; couches partagées (nombre, octets, par gestionnaire)
#   restaurer  v3.7.17 restaurée par digest à un autre chemin : arbre comparé ; go build hors réseau (unshare -rn) depuis la
#              fermeture d'origine et depuis la restaurée : binaires comparés ; yarn install --immutable hors réseau avec
#              l'environnement de hermeto generate-env, aux deux chemins : node_modules comparés ; sans fermeture : refus
#   alterer    hors réseau : zip yarn altéré, checksum de yarn.lock altéré, zip Go altéré ; blob altéré dans le stockage de Zot
#              (oras pull par digest)
# Réseau : seulement outils, sources et prefetch. Rien n'est installé dans le système ; tout vit sous ~/.cache/supply-chain-poc.
#
# Usage (racine du dépôt) : mise run fermetures -- <étape>…   (journal : resultats/f1-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
D=$HOME/.cache/supply-chain-poc/03/f1
O=${POC_OUTILS:?POC_OUTILS absent : lancer par mise run fermetures}
TAGS=(v3.7.16 v3.7.17)
GO_VERSION=1.27.3
GO_DIR=$O/gomodcache/golang.org/toolchain@v0.0.1-go$GO_VERSION.linux-amd64
YARN_PM=yarn@4.18.0+sha512.fcb8716fe7cd0eece141ffc18b92193a9df9204c1ba83189c288835223fc0bbe64af473bab0d5e9927a7daeb5caf2bb07eb2787cc9338ca040ea125f2a1f2f7e
export COREPACK_HOME=$O/corepack
YARN_SHIMS=$O/corepack/bin
PORT_PROXY=18080
REG=localhost:5000
DEPOT=fermetures/traefik
export ORAS=${ORAS:-oras} ORAS_OPTS=--plain-http
NODE_DIR=$(dirname "$(command -v node)")
mkdir -p "$D" "$D/home"

ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; }
arbre() { (cd "$1" && find . -type f ! -name bom.json -exec sha256sum {} + | sort -k2); }

zot_demarrer() {
  mkdir -p "$D/zot/data"
  jq --arg d "$D/zot/data" '.storage.rootDirectory = $d' "$here/zot-config.json" > "$D/zot/config.json"
  zot serve "$D/zot/config.json" >> "$D/zot/zot.log" 2>&1 &
  echo $! > "$D/zot/pid"
  for _ in $(seq 50); do curl -fs "http://$REG/v2/" >/dev/null && return 0; sleep 0.2; done
  echo "Zot ne répond pas" >&2; return 1
}
zot_arreter() { [ -f "$D/zot/pid" ] && kill "$(cat "$D/zot/pid")" 2>/dev/null; rm -f "$D/zot/pid"; }

# Build Go hors réseau ($1 sources, $2 sortie de hermeto, $3 binaire produit), caches vierges.
go_hors_reseau() {
  local c; c=$(mktemp -d -p "$D")
  unshare -rn env -i PATH="$GO_DIR/bin:/usr/bin:/bin" HOME="$D/home" GOCACHE="$c/cache" GOMODCACHE="$c/mod" \
    GOTOOLCHAIN=local GOPROXY="file://$2/deps/gomod/pkg/mod/cache/download" GOSUMDB=off GOFLAGS=-mod=readonly CGO_ENABLED=0 \
    bash --norc -euc "cd '$1' && go build -trimpath -buildvcs=false -ldflags '-s -w -buildid=' -o '$3' ./cmd/traefik"
  local rc=$?
  chmod -R u+w "$c"; rm -rf -- "${c:?}"
  return $rc
}
# yarn install --immutable hors réseau ($1 copie de webui, $2 sortie de hermeto, $3 chemin déclaré à generate-env).
yarn_hors_reseau() {
  rm -f "$D/yarn.env"
  "$HERMETO" generate-env "$2" --for-output-dir "$3" --format env --output "$D/yarn.env" >/dev/null || return 1
  unshare -rn env -i PATH="$YARN_SHIMS:$NODE_DIR:/usr/bin:/bin" HOME="$D/home" COREPACK_HOME="$COREPACK_HOME" \
    COREPACK_ENABLE_NETWORK=0 YARN_ENABLE_TELEMETRY=0 \
    bash --norc -euc "set -a; . '$D/yarn.env'; set +a; cd '$1' && yarn install --immutable --mode=skip-build"
}

etape_outils() {
  mise run outils:go-1.27 && mise run outils:yarn
  echo "## Go $GO_VERSION"
  "$GO_DIR/bin/go" version
  local m=golang.org/toolchain@v0.0.1-go$GO_VERSION.linux-amd64 h s
  h=$(cat "$O/gomodcache/cache/download/golang.org/toolchain/@v/v0.0.1-go$GO_VERSION.linux-amd64.ziphash")
  s=$(curl -fsS "https://sum.golang.org/lookup/$m" | awk -v m="${m%@*}" '$1 == m && $3 ~ /^h1:/ {print $3; exit}')
  echo "ziphash du cache : $h ; sum.golang.org : $s"
  [ -n "$s" ] && [ "$h" = "$s" ] && ok "toolchain conforme à sum.golang.org" || ko "toolchain : empreintes différentes"
  echo "## yarn 4.18.0 (corepack $(corepack --version), node $(node --version))"
  ls "$YARN_SHIMS"
  echo "version hors réseau, sans téléchargement : $(unshare -rn env -i PATH="$YARN_SHIMS:$NODE_DIR:/usr/bin:/bin" HOME="$D/home" COREPACK_HOME="$COREPACK_HOME" COREPACK_ENABLE_NETWORK=0 sh -c "cd '$D' && printf '{\"packageManager\":\"%s\"}' '$YARN_PM' > package.json && yarn --version" 2>&1 | tail -1)"
  rm -f "$D/package.json"
  find "$COREPACK_HOME/v1/yarn" -maxdepth 2 -name .corepack -exec sh -c 'echo "$1 : $(cat "$1")"' _ {} \;
  echo "## contre-épreuve : sha512 faux (dernier chiffre changé), COREPACK_HOME jetable"
  local t; t=$(mktemp -d -p "$D")
  printf '{"packageManager":"%s"}' "${YARN_PM%?}0" > "$t/package.json"
  [ "${YARN_PM: -1}" != 0 ] || printf '{"packageManager":"%s"}' "${YARN_PM%?}1" > "$t/package.json"
  if (cd "$t" && env -i PATH="$NODE_DIR:/usr/bin:/bin" HOME="$t" COREPACK_HOME="$t/corepack" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack install) > "$t/sortie" 2>&1; then
    ko "sha512 faux accepté"
  else
    ok "sha512 faux refusé : $(grep -m1 -iE 'hash|mismatch|error' "$t/sortie" | cut -c1-200)"
  fi
  rm -rf -- "${t:?}"
}

etape_sources() {
  local t c o
  for t in "${TAGS[@]}"; do
    rm -rf -- "${D:?}/src-$t"
    git clone -q -c advice.detachedHead=false --depth 1 --branch "$t" https://github.com/traefik/traefik.git "$D/src-$t"
    c=$(git -C "$D/src-$t" rev-parse HEAD)
    o=$(env -u GITHUB_TOKEN gh api "repos/traefik/traefik/git/ref/tags/$t" -q '.object.type + " " + .object.sha')
    echo "## $t : commit $c ; référence du tag : $o"
    case $o in
      tag\ *) echo "tag annoté, vérification GitHub : $(env -u GITHUB_TOKEN gh api "repos/traefik/traefik/git/tags/${o#tag }" -q '(.verification.verified|tostring) + " " + .verification.reason')" ;;
      *) echo "tag léger ; commit, vérification GitHub : $(env -u GITHUB_TOKEN gh api "repos/traefik/traefik/commits/$c" -q '(.commit.verification.verified|tostring) + " " + .commit.verification.reason')" ;;
    esac
    echo "go.mod : $(sed -n 's/^go //p' "$D/src-$t/go.mod" | head -1) ; toolchain : $(sed -n 's/^toolchain //p' "$D/src-$t/go.mod" | head -1)"
    echo "go.sum : $(wc -l < "$D/src-$t/go.sum") lignes ; packageManager : $(jq -r .packageManager "$D/src-$t/webui/package.json" | cut -c1-40)…"
    echo "yarn.lock : $(grep -c '^  resolution:' "$D/src-$t/webui/yarn.lock") résolutions, $(grep -c '^  checksum:' "$D/src-$t/webui/yarn.lock") checksums ; hors @npm: : $(grep '^  resolution:' "$D/src-$t/webui/yarn.lock" | grep -vc '@npm:' || true)"
    grep '^  resolution:' "$D/src-$t/webui/yarn.lock" | grep -v '@npm:' | sed 's/^/  /' | head -20
  done
}

etape_prefetch() {
  local t debut fin
  mkdir -p "$D/bin"
  printf '#!/bin/sh\nexport HTTPS_PROXY=http://127.0.0.1:%s HTTP_PROXY=http://127.0.0.1:%s NO_PROXY=\nexec %s "$@"\n' \
    "$PORT_PROXY" "$PORT_PROXY" "$GO_DIR/bin/go" > "$D/bin/go"
  printf '#!/bin/sh\nexport COREPACK_HOME=%s COREPACK_ENABLE_NETWORK=0 HOME=%s YARN_HTTPS_PROXY=http://127.0.0.1:%s YARN_HTTP_PROXY=http://127.0.0.1:%s\nexec %s "$@"\n' \
    "$COREPACK_HOME" "$D/home" "$PORT_PROXY" "$PORT_PROXY" "$YARN_SHIMS/yarn" > "$D/bin/yarn"
  chmod +x "$D/bin/go" "$D/bin/yarn"
  for t in "${TAGS[@]}"; do
    rm -rf -- "${D:?}/out-$t"; rm -f "$D/proxy-$t.log"
    python3 -I "$here/journal-connect.py" "$PORT_PROXY" "$D/proxy-$t.log" & local px=$!
    sleep 1
    echo "## $t"
    debut=$(date +%s)
    if env -i PATH="$D/bin:$NODE_DIR:/usr/bin:/bin" HOME="$D/home" \
      strace -f -qq -e trace=connect -o "$D/trace-$t" "$HERMETO" fetch-deps --source "$D/src-$t" --output "$D/out-$t" \
      '[{"type": "gomod"}, {"type": "yarn", "path": "webui"}]' > "$D/hermeto-$t.log" 2>&1; then
      fin=$(date +%s); ok "fetch-deps en $((fin - debut)) s"
    else
      fin=$(date +%s); ko "fetch-deps en échec après $((fin - debut)) s"; tail -30 "$D/hermeto-$t.log"
    fi
    kill "$px" 2>/dev/null; wait "$px" 2>/dev/null || true
    { grep -iE 'toolchain|go version|yarn version|WARNING' "$D/hermeto-$t.log" || true; } | cut -c1-200 | head -8
    echo "noms contactés par le proxy (CONNECT, nombre) :"
    awk '$2 == "CONNECT" {print $3}' "$D/proxy-$t.log" | sort | uniq -c | sed 's/^ */  /'
    echo "refus et échecs du proxy : $(grep -cE ' (REFUS|ECHEC|ERREUR) ' "$D/proxy-$t.log" || true)"
    echo "connect() inet hors du proxy : $(grep -E 'connect\(' "$D/trace-$t" | grep -E 'AF_INET6?' | grep -vF "htons($PORT_PROXY), sin_addr=inet_addr(\"127.0.0.1\")" \
      | grep -oE 'sin6?_port=htons\([0-9]+\), (sin_addr=inet_addr|inet_pton\(AF_INET6)\("[^"]*"' | sort | uniq -c | sed 's/^ *//' | paste -sd';' - || true)"
    echo "connect() unix : $(grep -E 'connect\(' "$D/trace-$t" | grep -oE 'sun_path="[^"]*"' | sort | uniq -c | sed 's/^ *//' | paste -sd';' - || true)"
    if [ -d "$D/out-$t/deps" ]; then
      echo "gomod : $(find "$D/out-$t/deps/gomod" -type f | wc -l) fichiers, $(du -sb "$D/out-$t/deps/gomod" | cut -f1) o ; zip : $(find "$D/out-$t/deps/gomod" -name '*.zip' | wc -l)"
      echo "yarn : $(find "$D/out-$t/deps/yarn" -type f | wc -l) fichiers, $(du -sb "$D/out-$t/deps/yarn" | cut -f1) o ; zip : $(find "$D/out-$t/deps/yarn" -name '*.zip' | wc -l)"
      echo "SBOM : $(jq '.components | length' "$D/out-$t/bom.json") composants"
      echo "paquets natifs linux-x64 (sans checksum dans yarn.lock) : $(find "$D/out-$t/deps/yarn" -name '*linux-x64*.zip' -printf '%f\n' | sort | paste -sd' ' -)"
      echo "chemin absolu de la sortie dans la fermeture : $(grep -rlF "$D/out-$t" "$D/out-$t" | sed "s#$D/out-$t/##" | paste -sd' ' - || true)"
      echo "chemin absolu des sources dans la fermeture : $(grep -rlF "$D/src-$t" "$D/out-$t" | sed "s#$D/out-$t/##" | paste -sd' ' - || true)"
    fi
    echo "sources après le prefetch (git status --porcelain) : $(git -C "$D/src-$t" status --porcelain --ignored | wc -l) entrée(s)"
    git -C "$D/src-$t" status --porcelain --ignored | head -5
  done
}

etape_registre() {
  local t r a b n
  zot_arreter; rm -rf -- "${D:?}/zot"; zot_demarrer
  trap zot_arreter RETURN
  a=$(du -sb "$D/zot/data" | cut -f1)
  for t in "${TAGS[@]}"; do
    r=$("$here/closure.sh" push "$D/out-$t" "$REG/$DEPOT:$t")
    b=$(du -sb "$D/zot/data" | cut -f1)
    echo "$t : $r ; couches : $(oras manifest fetch --plain-http "$r" | jq '.layers | length') ; stockage +$((b - a)) o"
    echo "$t $r" >> "$D/digests.txt"; a=$b
  done
  r=$("$here/closure.sh" push "$D/out-${TAGS[1]}" "$REG/$DEPOT:${TAGS[1]}-bis")
  [ "$r" = "$(awk -v t="${TAGS[1]}" '$1 == t {r = $2} END {print r}' "$D/digests.txt")" ] && ok "même digest au second push : $r" || ko "digest différent au second push : $r"
  for t in "${TAGS[@]}"; do
    oras manifest fetch --plain-http "$(awk -v t="$t" '$1 == t {r = $2} END {print r}' "$D/digests.txt")" \
      | jq -r '.layers[] | "\(.digest) \(.size) \(.annotations["org.opencontainers.image.title"])"' | sort > "$D/couches-$t"
    sort -u -k1,1 "$D/couches-$t" > "$D/digests-$t"   # un fichier par couche, mais des fichiers identiques partagent un digest
  done
  echo "## blobs (digests distincts) de ${TAGS[1]} partagés avec ${TAGS[0]}"
  for g in gomod yarn ""; do
    n=$(join <(grep " deps/$g" "$D/digests-${TAGS[1]}" | cut -d' ' -f1,2) <(cut -d' ' -f1 "$D/digests-${TAGS[0]}") | awk '{n++; o += $2} END {printf "%d %d", n, o}')
    grep " deps/$g" "$D/digests-${TAGS[1]}" | awk -v g="${g:-total}" -v n="${n% *}" -v o="${n#* }" '{t++; s += $2} END {printf "%s : %d blobs sur %d, %d o sur %d o, %.1f %% des octets\n", g, n, t, o, s, 100 * o / s}'
  done
}

etape_restaurer() {
  local t=${TAGS[1]} r
  r=$(awk -v t="$t" '$1 == t {r = $2} END {print r}' "$D/digests.txt")
  zot_arreter; zot_demarrer
  trap zot_arreter RETURN
  rm -rf -- "${D:?}/ailleurs"; mkdir -p "$D/ailleurs"
  "$here/closure.sh" pull "$r" "$D/ailleurs/out"
  cp "$D/out-$t/bom.json" "$D/ailleurs/out/"   # le SBOM est un referrer, pas une couche ; generate-env ne lit que deps/
  diff <(arbre "$D/out-$t") <(arbre "$D/ailleurs/out") > /dev/null && ok "arbre restauré identique ($(arbre "$D/ailleurs/out" | wc -l) fichiers)" || ko "arbre restauré différent"
  echo "## go build hors réseau"
  for x in origine:"$D/out-$t" ailleurs:"$D/ailleurs/out"; do
    local debut; debut=$(date +%s)
    go_hors_reseau "$D/src-$t" "${x#*:}" "$D/traefik-${x%%:*}" && ok "${x%%:*} : $(sha256sum < "$D/traefik-${x%%:*}" | cut -c1-16) en $(($(date +%s) - debut)) s" || ko "${x%%:*} : échec"
  done
  cmp -s "$D/traefik-origine" "$D/traefik-ailleurs" && ok "binaires identiques" || ko "binaires différents"
  echo "## yarn install --immutable hors réseau"
  for x in origine:"$D/out-$t" ailleurs:"$D/ailleurs/out"; do
    rm -rf -- "${D:?}/webui-${x%%:*}"; cp -a "$D/src-$t/webui" "$D/webui-${x%%:*}"
    if yarn_hors_reseau "$D/webui-${x%%:*}" "${x#*:}" "${x#*:}" > "$D/yarn-${x%%:*}.log" 2>&1; then
      ok "${x%%:*} : $(find "$D/webui-${x%%:*}/node_modules" -name package.json -path '*/node_modules/*/package.json' | wc -l) package.json dans node_modules"
    else
      ko "${x%%:*} : échec"; tail -5 "$D/yarn-${x%%:*}.log"
    fi
  done
  grep -E '^YARN|^export' "$D/yarn.env" | sed 's/^/  /'
  diff -q <(cd "$D/webui-origine/node_modules" && find . -type f ! -name '.yarn-state.yml' -exec sha256sum {} + | sort -k2) \
    <(cd "$D/webui-ailleurs/node_modules" && find . -type f ! -name '.yarn-state.yml' -exec sha256sum {} + | sort -k2) >/dev/null \
    && ok "node_modules identiques aux deux chemins" || ko "node_modules différents"
  echo "## sans fermeture (dossier deps/yarn vide)"
  rm -rf -- "${D:?}/vide" "${D:?}/webui-vide"; mkdir -p "$D/vide/deps/yarn"; cp "$D/out-$t/bom.json" "$D/out-$t/.build-config.json" "$D/vide/"
  cp -a "$D/src-$t/webui" "$D/webui-vide"
  if yarn_hors_reseau "$D/webui-vide" "$D/vide" "$D/vide" > "$D/yarn-vide.log" 2>&1; then ko "accepté sans fermeture"; else ok "refusé : $(grep -m1 -E 'YN0*[1-9][0-9]*:' "$D/yarn-vide.log" | cut -c1-200)"; fi
}

etape_alterer() {
  local t=${TAGS[1]} z f b r
  echo "## zip yarn altéré"
  rm -rf -- "${D:?}/alt"; mkdir -p "$D/alt"; cp -a "$D/ailleurs/out" "$D/alt/out"
  z=$(find "$D/alt/out/deps/yarn" -name '*.zip' | sort | awk 'NR == 1')
  printf 'X' | dd of="$z" bs=1 seek=$(( $(stat -c %s "$z") / 2 )) conv=notrunc status=none
  echo "altéré : ${z#"$D"/alt/out/}"
  rm -rf -- "${D:?}/webui-alt"; cp -a "$D/src-$t/webui" "$D/webui-alt"
  if yarn_hors_reseau "$D/webui-alt" "$D/alt/out" "$D/alt/out" > "$D/yarn-alt.log" 2>&1; then ko "zip altéré accepté"; else ok "refusé : $(grep -m1 -E 'YN0*[1-9][0-9]*:' "$D/yarn-alt.log" | cut -c1-220)"; fi
  echo "## zip yarn altéré d'un paquet sans checksum dans yarn.lock (natif linux-x64)"
  rm -rf -- "${D:?}/altnc"; mkdir -p "$D/altnc"; cp -a "$D/ailleurs/out" "$D/altnc/out"
  z=$(find "$D/altnc/out/deps/yarn" -name '*binding-linux-x64-gnu*.zip' | sort | awk 'NR == 1')
  if [ -z "$z" ]; then
    echo "aucun zip natif linux-x64 dans la fermeture"
  else
    printf 'X' | dd of="$z" bs=1 seek=$(( $(stat -c %s "$z") / 2 )) conv=notrunc status=none
    echo "altéré : ${z#"$D"/altnc/out/}"
    rm -rf -- "${D:?}/webui-altnc"; cp -a "$D/src-$t/webui" "$D/webui-altnc"
    if yarn_hors_reseau "$D/webui-altnc" "$D/altnc/out" "$D/altnc/out" > "$D/yarn-altnc.log" 2>&1; then
      echo "CONSTAT accepté hors réseau : $(grep -m1 -E 'YN0000.*(Done|Completed)' "$D/yarn-altnc.log" | cut -c1-160)"
    else
      echo "refusé : $(grep -m1 -E 'YN0*[1-9][0-9]*:' "$D/yarn-altnc.log" | cut -c1-220)"
    fi
  fi
  echo "## checksum de yarn.lock altéré"
  rm -rf -- "${D:?}/webui-lock"; cp -a "$D/src-$t/webui" "$D/webui-lock"
  sed -i '0,/^  checksum: 10c0\//s//  checksum: 10c0\/0/' "$D/webui-lock/yarn.lock"
  { diff "$D/src-$t/webui/yarn.lock" "$D/webui-lock/yarn.lock" || true; } | grep '^>' | cut -c1-80
  if yarn_hors_reseau "$D/webui-lock" "$D/ailleurs/out" "$D/ailleurs/out" > "$D/yarn-lock.log" 2>&1; then ko "yarn.lock altéré accepté"; else ok "refusé : $(grep -m1 -E 'YN0*[1-9][0-9]*:' "$D/yarn-lock.log" | cut -c1-220)"; fi
  echo "## zip Go altéré"
  rm -rf -- "${D:?}/altgo"; mkdir -p "$D/altgo"; cp -a "$D/ailleurs/out" "$D/altgo/out"
  z=$(find "$D/altgo/out/deps/gomod" -name '*.zip' -size +100k | sort | awk 'NR == 1')
  # zip valide, un fichier .go modifié (une ligne de commentaire ajoutée) : seul go.sum peut le refuser
  python3 -I - "$z" <<'PY'
import sys, zipfile
z = sys.argv[1]
with zipfile.ZipFile(z) as a:
    infos = [(i, a.read(i.filename)) for i in a.infolist()]
cible = next(i.filename for i, _ in infos if i.filename.endswith('.go'))
with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as b:
    for i, d in infos:
        b.writestr(i, d + b'\n// altere\n' if i.filename == cible else d)
print('fichier modifié :', cible)
PY
  echo "altéré : ${z#"$D"/altgo/out/}"
  if go_hors_reseau "$D/src-$t" "$D/altgo/out" "$D/traefik-altgo" > "$D/go-alt.log" 2>&1; then ko "zip Go altéré accepté"; else ok "refusé : $(grep -m1 -E 'checksum mismatch|SECURITY ERROR|flate' "$D/go-alt.log" | cut -c1-220)"; fi
  echo "## blob altéré dans le stockage de Zot"
  r=$(awk -v t="$t" '$1 == t {r = $2} END {print r}' "$D/digests.txt")
  b=$(grep ' deps/yarn/' "$D/couches-$t" | awk 'NR == 1 {print $1}')
  f=$(find "$D/zot/data" -path "*/blobs/sha256/${b#sha256:}" -type f | awk 'NR == 1')
  echo "blob ${b:0:19}… : ${f#"$D"/}"
  printf 'X' | dd of="$f" bs=1 seek=$(( $(stat -c %s "$f") / 2 )) conv=notrunc status=none
  zot_arreter; zot_demarrer
  trap zot_arreter RETURN
  rm -rf -- "${D:?}/alt-zot"
  if "$here/closure.sh" pull "$r" "$D/alt-zot" > "$D/pull-alt.log" 2>&1; then ko "blob altéré accepté"; else ok "refusé : $(grep -m1 -iE 'digest|mismatch|error' "$D/pull-alt.log" | cut -c1-220)"; fi
}

lancer() {
  [ $# -gt 0 ] || { echo "usage : $0 $(declare -F | awk '$3 ~ /^etape_/ {sub("etape_", "", $3); printf "%s|", $3}' | sed 's/|$//')…" >&2; exit 2; }
  for e in "$@"; do declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }; done
  for e in "$@"; do
    { echo "# ${0##*/} $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/f1-$e.log"
  done
}
lancer "$@"
