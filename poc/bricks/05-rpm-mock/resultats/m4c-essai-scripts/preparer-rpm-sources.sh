#!/bin/sh
set -eu
case $COMMIT in *[!0-9a-f]*) echo "commit invalide : $COMMIT" >&2; exit 1 ;; esac
[ ${#COMMIT} = 40 ] || { echo "commit invalide : $COMMIT" >&2; exit 1; }
case $DEPOT in https://sc-stockage.poc.test:3000/*.git) ;; *) echo "dépôt hors de Forgejo : $DEPOT" >&2; exit 1 ;; esac
e=/workspace/sortie/entrees
[ ! -e "$e" ] || { echo "workspace déjà rempli : $e" >&2; exit 1; }
export HOME=/tmp GIT_CONFIG_NOSYSTEM=1 GIT_SSL_CAINFO=/etc/ca-poc/ca.crt GIT_TERMINAL_PROMPT=0
git clone --quiet --no-checkout "$DEPOT" /tmp/depot
git -C /tmp/depot checkout --quiet --detach "$COMMIT"
[ "$(git -C /tmp/depot rev-parse HEAD)" = "$COMMIT" ] || { echo "HEAD différent du commit demandé" >&2; exit 1; }
echo "$(git --version) ; commit $COMMIT, arbre $(git -C /tmp/depot rev-parse 'HEAD^{tree}')"
mkdir -p "$e/src"
git -C /tmp/depot archive --format=tar HEAD | tar -xf - -C "$e/src"
printf '%s' "$DEPOT" > /resultats/CHAINS-GIT_URL
printf '%s' "$COMMIT" > /resultats/CHAINS-GIT_COMMIT

