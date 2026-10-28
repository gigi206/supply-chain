#!/usr/bin/env bash
# Brique 03 : stocke une fermeture de dépendances (sortie de Hermeto) dans un
# registre OCI, un fichier par couche, et la restaure par digest.
#
#   closure.sh push <répertoire> <dépôt:tag>   imprime la référence <dépôt>@sha256:…
#   closure.sh pull <dépôt@sha256:…> <répertoire>
#
# Un fichier par couche : deux fermetures qui partagent un fichier (module Go,
# archive npm) partagent le blob, stocké une seule fois par le registre.
# Le SBOM Hermeto (bom.json) n'est pas une couche : il est attaché en referrer.
# Le manifest est déterministe (fichiers triés, date fixée par SOURCE_DATE_EPOCH,
# 0 par défaut) : la même fermeture donne le même digest.
# Variables : ORAS (binaire), ORAS_OPTS (ex. --plain-http pour un registre local).
set -euo pipefail

ORAS=${ORAS:-oras}
read -r -a opts <<<"${ORAS_OPTS:-}"
ARTIFACT_TYPE=application/vnd.supply-chain.deps-closure.v1
FILE_TYPE=application/vnd.supply-chain.deps-closure.file.v1
SBOM_TYPE=application/vnd.cyclonedx+json

push() {
  local dir=$1 ref=$2 created digest
  created=$(date -u -d "@${SOURCE_DATE_EPOCH:-0}" +%Y-%m-%dT%H:%M:%SZ)
  local files=()
  while IFS= read -r f; do
    files+=("$f:$FILE_TYPE")
  done < <(cd "$dir" && find . -type f ! -name bom.json -printf '%P\n' | LC_ALL=C sort)
  digest=$(cd "$dir" && "$ORAS" push "${opts[@]}" --no-tty --format go-template='{{.digest}}' \
    --artifact-type "$ARTIFACT_TYPE" \
    --annotation "org.opencontainers.image.created=$created" \
    "$ref" "${files[@]}")
  if [ -f "$dir/bom.json" ]; then
    (cd "$dir" && "$ORAS" attach "${opts[@]}" --no-tty --format go-template='{{.digest}}' \
      --artifact-type "$SBOM_TYPE" \
      --annotation "org.opencontainers.image.created=$created" \
      "${ref%:*}@$digest" "bom.json:$SBOM_TYPE" >/dev/null)
  fi
  echo "${ref%:*}@$digest"
}

pull() {
  local ref=$1 dir=$2
  case $ref in
    *@sha256:*) ;;
    *) echo "pull exige une référence par digest (…@sha256:…)" >&2; exit 2 ;;
  esac
  mkdir -p "$dir"
  # oras vérifie le digest du manifest puis celui de chaque couche.
  "$ORAS" pull "${opts[@]}" --no-tty -o "$dir" "$ref" >/dev/null
}

case ${1:-} in
  push) push "$2" "$3" ;;
  pull) pull "$2" "$3" ;;
  *) echo "usage : $0 push <répertoire> <dépôt:tag> | pull <dépôt@sha256:…> <répertoire>" >&2; exit 2 ;;
esac
