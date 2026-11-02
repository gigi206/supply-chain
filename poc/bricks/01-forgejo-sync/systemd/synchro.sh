#!/usr/bin/env bash
# Brique 01, S3 : lancé par synchro@<projet>.service. Variables de /etc/synchro/<projet>.env : AMONT (https), MIROIR et
# FORK (URL Forgejo ; FORK vide : pas de mise à jour du fork, premier run d'un projet dont le fork n'existe pas encore). Le jeton (credential « jeton ») n'est envoyé qu'à MIROIR et FORK (http.<url>.extraHeader), jamais à
# l'amont ; il passe par l'environnement de git, jamais en argument.
set -euo pipefail
p=$1
d=$STATE_DIRECTORY
d=${d##*:}   # StateDirectory=synchro synchro/<projet> : le dernier répertoire est celui du projet
entete="Authorization: token $(cat "$CREDENTIALS_DIRECTORY/jeton")"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0=/etc/synchro/ca-poc.crt
export GIT_CONFIG_KEY_1="http.$MIROIR.extraHeader" GIT_CONFIG_VALUE_1="$entete"
export GIT_CONFIG_KEY_2="http.${FORK:-$MIROIR}.extraHeader" GIT_CONFIG_VALUE_2="$entete"
unset entete
fork=()
[ -z "${FORK:-}" ] || fork=(--fork "$FORK")
exec python3 -I /usr/local/lib/synchro/sync.py --mirror "$d/miroir.git" --upstream "$AMONT" \
  --report-dir "$d/rapports" --bundle-dir "$d/bundles" --metriques "$d/$p.prom" \
  --refs-propres /etc/synchro/refs-propres.json --projet "$p" --push "$MIROIR" "${fork[@]}"
