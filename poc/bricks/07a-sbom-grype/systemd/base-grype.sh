#!/usr/bin/env bash
# Brique 07a, G1 (D3 a, décision du propriétaire du 04/11/2026) : lancé par base-grype.service sur sc-stockage. Archive la
# base Grype du jour dans Zot (vulndb/grype:<date>) avec fetch-db.sh : empreinte annoncée par latest.json vérifiée (la base
# n'a pas de signature, relevé de G0), création seulement. Le mot de passe de poc-vulndb (credential « zot ») ne passe que
# par un fichier de configuration d'oras dans le répertoire d'exécution, jamais en argument.
set -euo pipefail
cfg=$RUNTIME_DIRECTORY/auth.json
w=$CACHE_DIRECTORY/travail
(umask 077 && printf '{"auths":{"%s":{"auth":"%s"}}}' "$REG" "$(printf 'poc-vulndb:%s' "$(cat "$CREDENTIALS_DIRECTORY/zot")" | base64 -w0)" > "$cfg")
rm -rf -- "${w:?}" && mkdir -p "$w"
ORAS=/usr/local/bin/oras ORAS_OPTS="--ca-file /etc/base-grype/ca-poc.crt --registry-config $cfg" REG=$REG WORKDIR=$w \
  /usr/local/lib/base-grype/fetch-db.sh
rm -rf -- "${w:?}" "$cfg"
