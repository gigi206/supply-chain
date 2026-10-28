#!/usr/bin/env bash
# Brique 07a : archive la base officielle de Grype du jour dans le registre (job quotidien).
# Télécharge latest.json et l'archive, vérifie l'empreinte annoncée, puis pousse
# l'archive avec ORAS sous vulndb/grype:<date de construction>. Imprime la
# référence par digest, que les scans citent dans leur prédicat.
#
# Usage : ORAS=oras ORAS_OPTS=--plain-http REG=localhost:5000 WORKDIR=/tmp/db ./fetch-db.sh
# Seul script de la brique à utiliser le réseau (grype.anchore.io).
set -euo pipefail
W=${WORKDIR:?}
REG=${REG:?}
ORAS=${ORAS:-oras}
read -r -a opts <<<"${ORAS_OPTS:-}"
BASE=https://grype.anchore.io/databases/v6
mkdir -p "$W"
cd "$W"

curl -fsS -o latest.json "$BASE/latest.json"
read -r path checksum built schema < <(python3 -I -c 'import json
d = json.load(open("latest.json"))
print(d["path"], d["checksum"], d["built"], d["schemaVersion"])')
[ -f "$path" ] || curl -fsS -o "$path" "$BASE/$path"
[ "sha256:$(sha256sum < "$path" | cut -c1-64)" = "$checksum" ] || { echo "empreinte invalide : $path" >&2; exit 1; }

digest=$("$ORAS" push "${opts[@]}" --no-tty --format go-template='{{.digest}}' \
  --artifact-type application/vnd.supply-chain.grype-db.v6 \
  --annotation "org.opencontainers.image.created=$built" \
  --annotation "org.opencontainers.image.source=$BASE/$path" \
  --annotation "dev.anchore.grype.db.schema=$schema" \
  --annotation "dev.anchore.grype.db.checksum=$checksum" \
  "$REG/vulndb/grype:${built%%T*}" "$path:application/vnd.anchore.grype.db.v6+zstd" latest.json:application/json)
echo "$REG/vulndb/grype@$digest"
