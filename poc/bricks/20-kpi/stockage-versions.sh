#!/usr/bin/env bash
# Brique 20, étape 4 (préparation, accord du 24/11 : « Oui, lecture seule (Recommandé) ») : présence et version d'openssl et de python3
# sur sc-stockage, par ssh, sans sudo. Deux commandes de version, rien n'est écrit sur la VM.
# Usage (racine du dépôt) : bash poc/bricks/20-kpi/stockage-versions.sh   (journal : resultats/e4-stockage-versions<SUFFIXE>.log)
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e4-stockage-versions${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
O8=$HOME/.cache/supply-chain-poc/08
N=0; KO=0
attendu() { N=$((N + 1)); if [[ $2 =~ $3 ]]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
sur() { env -u SSH_AUTH_SOCK ssh -n -i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes poc@192.168.161.13 "$@" 2>&1; }
{
  echo "# stockage-versions.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16)"
  attendu "openssl de sc-stockage" "$(sur '/usr/bin/openssl version'; echo "code $?")" '^OpenSSL 3\.5\.[0-9]+ .*code 0$'
  attendu "python3 de sc-stockage" "$(sur '/usr/bin/python3 --version'; echo "code $?")" '^Python 3\.13\.5.*code 0$'
  echo "## bilan : $N cas, $KO écart(s)"
  [ "$KO" = 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
