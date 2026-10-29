#!/usr/bin/env bash
# Rejoue sur le laptop les bancs locaux de l'étape 4b avec les outils de mise.toml,
# dans l'ordre B, C, 02, 03, 04 (BuildKit du nixpkgs puis release amont), 07a, 13a.
# Registre Zot et démons BuildKit rootless éphémères ; journaux */resultats/*-laptop.*
# (chemins personnels masqués).
#
# Usage (racine du dépôt) : mise run bancs   — W : répertoire de travail, sur disque
# (défaut ~/.cache/supply-chain-poc/w ; jamais /tmp, monté en RAM).
set -euo pipefail
export LC_ALL=C

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$repo"
: "${POC_OUTILS:?lancer avec : mise run bancs}" "${GOROOT_DIR:?}" "${HERMETO:?}" "${BUSYBOX:?}" "${SPDX:?}"
W=${W:-$HOME/.cache/supply-chain-poc/w}
# Hermeto sonde chaque `go` du PATH : les shims de mise échouent hors du dépôt.
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
# Le Go de mise (1.24.7) exporte GOROOT : Go 1.26.10 prendrait sinon sa bibliothèque standard.
unset GOROOT GOBIN
export PATH
GO126=$GOROOT_DIR/bin/go
pids=()
arreter() { local p; for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap arreter EXIT

masque() { sed "s#$HOME#~#g"; }
banc() { # $1 = journal, $2 = en-tête, $3… = commande
  local log=$1 entete=$2 t0
  shift 2
  t0=$(date +%s)
  { echo "# $entete"; r=0; "$@" 2>&1 || r=$?; echo "exit=$r durée=$(( $(date +%s) - t0 )) s"; } | masque > "$log"
  echo "$(grep -c '^OK' "$log" || true) OK, $(grep -c '^KO' "$log" || true) KO, $(grep -o '^exit=[0-9]*' "$log" | tail -1) : $log"
}
attendre() { # $1 = commande de test
  for _ in $(seq 1 30); do eval "$1" >/dev/null 2>&1 && return 0; sleep 1; done
  echo "service non prêt : $1" >&2
  return 1
}
buildkit() { # $1 = nom, $2 = buildkitd, $3 = runc ; démon rootless, réseau de l'hôte
  local d=$W/bk-$1
  # Un démon rootless laisse des fichiers en lecture seule ou à des uid subordonnés :
  # on nettoie dans un user namespace qui les mappe tous.
  [ ! -e "$d" ] || unshare -Ur --map-auto rm -rf -- "$d"
  mkdir -p "$d"
  rootlesskit --state-dir="$d/rk" --net=host "$2" --rootless --root "$d/root" --addr "unix://$d/buildkitd.sock" \
    --oci-worker=true --containerd-worker=false --oci-worker-snapshotter=native --oci-worker-binary="$3" \
    > "$d/buildkitd.log" 2>&1 &
  pids+=($!)
  attendre "buildctl --addr unix://$d/buildkitd.sock debug workers"
}
date_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
mkdir -p "$W"

# Registre Zot éphémère (stockage sur disque, vidé à chaque passage).
rm -rf "$W/zot"
mkdir -p "$W/zot/data"
jq --arg d "$W/zot/data" '.storage.rootDirectory = $d' poc/bricks/03-deps-closure/zot-config.json > "$W/zot/config.json"
zot serve "$W/zot/config.json" > "$W/zot/zot.log" 2>&1 &
pids+=($!)
attendre "curl -fsS http://127.0.0.1:5000/v2/"

# B : référence Hermeto (Go 1.24.7 du PATH).
banc poc/benchmarks/nix/resultats/reference-hermeto-laptop.log \
  "hermeto.sh (laptop), $(date_utc), $("$HERMETO" --version), $(go version), node $(node --version), npm $(npm --version)" \
  env WORKDIR="$W/b-hermeto" poc/benchmarks/nix/reference/hermeto.sh

# C : run.sh écrit resultats/resultats.md (mesures du cloud) : on le met de côté.
c=poc/benchmarks/kyverno-seul/resultats
cp "$c/resultats.md" "$W/resultats-c-cloud.md"
env REG=localhost:5000 WORKDIR="$W/bench-c" poc/benchmarks/kyverno-seul/setup.sh 2>&1 | masque > "$W/bench-c-setup.log"
env WORKDIR="$W/bench-c" poc/benchmarks/kyverno-seul/run.sh > "$W/bench-c-run.log" 2>&1
mv "$c/resultats.md" "$c/resultats-laptop.md"
cp "$W/resultats-c-cloud.md" "$c/resultats.md"
echo "banc C : $(awk -F'|' 'NR > 2 && $3 == $4 && $3 == $5' "$c/resultats-laptop.md" | wc -l) cas sur 17 conformes : $c/resultats-laptop.md"

# 02 : 10 000 artefacts synthétiques + les images du banc C.
banc poc/bricks/02-artefact-index/resultats/bench-laptop.log \
  "bench.sh (laptop), $(date_utc), zot v2.1.22 local, $(python3 --version), COUNT=10000 + banc C (17 images cosign)" \
  env REG=http://localhost:5000 WORKDIR="$W/b02" COUNT=10000 poc/bricks/02-artefact-index/bench.sh

# 03 : fermetures (Go 1.26.10).
banc poc/bricks/03-deps-closure/resultats/bench-laptop.log \
  "bench.sh (laptop), $(date_utc), $("$HERMETO" --version), oras $(oras version | awk 'NR == 1 {print $2}'), zot v2.1.22 (dedupe), $("$GO126" version), GOROOT $("$GO126" env GOROOT | sed 's#.*/##'), node $(node --version)" \
  env GO="$GO126" ORAS=oras REG=localhost:5000 WORKDIR="$W/b03" ZOT_DATA="$W/zot/data" poc/bricks/03-deps-closure/bench.sh

# 04 : BuildKit rootless, référence (nixpkgs) puis release amont (mise).
bkn=$POC_OUTILS/buildkit-nix/bin
l=poc/bricks/04-hermetic-repro/resultats/bench-laptop.log
buildkit nix "$bkn/buildkitd" "$POC_OUTILS/runc-nix/bin/runc"
banc "$l" "bench.sh (laptop), $(date_utc), buildkit $("$bkn/buildkitd" --version | awk '{print $3}') + runc $("$POC_OUTILS/runc-nix/bin/runc" --version | awk 'NR == 1 {print $3}') (nixpkgs b6018f87da91, démon éphémère ROOTLESS via rootlesskit $(rootlesskit --version | awk '{print $3}') --net=host, oci worker, snapshotter native, sans Docker), go 1.26.10 (module golang.org/toolchain), busybox $("$BUSYBOX" | awk 'NR == 1 {print $2}') statique (nixpkgs)" \
  env BUILDKIT_HOST="unix://$W/bk-nix/buildkitd.sock" BUILDCTL="$bkn/buildctl" B03="$W/b03" WORKDIR="$W/b04" poc/bricks/04-hermetic-repro/bench.sh
buildkit amont "$(command -v buildkitd)" "$(command -v runc)"
banc "$W/b04-amont.log" "passage supplémentaire, $(date_utc) : release AMONT buildkit $(buildkitd --version | awk '{print $3}') + runc $(runc --version | awk 'NR == 1 {print $3}') (mise / aqua, sha256 vérifiés), rootless, mêmes entrées" \
  env BUILDKIT_HOST="unix://$W/bk-amont/buildkitd.sock" BUILDCTL="$(command -v buildctl)" B03="$W/b03" WORKDIR="$W/b04-amont" poc/bricks/04-hermetic-repro/bench.sh
{ echo; cat "$W/b04-amont.log"; } >> "$l"

# 07a : base Grype du jour archivée dans Zot, puis scan hors réseau et porte.
db=$(env ORAS=oras ORAS_OPTS=--plain-http REG=localhost:5000 WORKDIR="$W/db" poc/bricks/07a-sbom-grype/fetch-db.sh | tail -1)
cl=localhost:5000/deps/sample-app@$(crane digest --insecure localhost:5000/deps/sample-app:v1.0.0)
banc poc/bricks/07a-sbom-grype/resultats/bench-laptop.log \
  "bench.sh (laptop), $(date_utc), syft $(syft version | awk '/^Version/ {print $2}'), grype $(grype version | awk '/^Version/ {print $2}') (mise/aqua), base $db, conforma ec $(ec version 2>/dev/null | awk '/Version/ {print $2; exit}'), kyverno $(kyverno version 2>/dev/null | awk '/Version/ {print $2; exit}'), cosign $(cosign version 2>/dev/null | awk '/GitVersion/ {print $2}')" \
  env DB_REF="$db" CLOSURE_REF="$cl" APP_BIN="$W/b03/build-apres/sample-app" REG=localhost:5000 WORKDIR="$W/b07" poc/bricks/07a-sbom-grype/bench.sh

# 13a : licences (Go 1.26.10, liste SPDX et reuse du nixpkgs).
banc poc/bricks/13a-licences/resultats/bench-laptop.log \
  "bench.sh (laptop), $(date_utc), syft $(syft version | awk '/^Version/ {print $2}') (mise/aqua, PATH réduit à syft), $(reuse --version | head -1) et liste SPDX 3.27.0 (nixpkgs b6018f87da91), $("$GO126" version | cut -d' ' -f3)" \
  env GO="$GO126" B03="$W/b03" REG=localhost:5000 WORKDIR="$W/b13" poc/bricks/13a-licences/bench.sh
