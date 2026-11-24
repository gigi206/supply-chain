#!/usr/bin/env bash
# Brique 20, étape 3 (complément) : exportateur lancé depuis l'hôte sur le vrai Zot, en lecture anonyme, puis recalcul signé et
# comparaison (comparer_zot.py). Rien n'est posé ; la sortie reste sous ~/.cache/supply-chain-poc/20/exportateur-zot, effacé à la fin.
# Usage (racine du dépôt) : [SUFFIXE=-1] mise exec -- bash poc/bricks/20-kpi/exportateur-zot.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e3-exportateur-zot${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
T=$HOME/.cache/supply-chain-poc/20/exportateur-zot   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/exportateur-zot ] || find ~/.cache/supply-chain-poc/20/exportateur-zot -delete
trap 'find ~/.cache/supply-chain-poc/20/exportateur-zot ~/.cache/supply-chain-poc/20/recalcul -delete 2> /dev/null' EXIT
mkdir -p "$T"; : > "$T/kpi.prom"
X=$here/../../../tools/metrics-exporter/metrics_exporter.py
{
  echo "# exportateur-zot.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), exportateur $(sha256sum < "$X" | cut -c1-16), $(/usr/bin/python3 --version)"
  REG=192.168.161.13:5000 CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt PRODUITS="sample-app sample-app-deb sample-app-rpm" \
    SORTIE=$T/kpi.prom /usr/bin/python3 -I "$X"; a=$?
  sed 's/^/PROM|/' "$T/kpi.prom"
  python3 -I "$here/recalcul.py" > "$T/recalcul.log" 2>&1; b=$?
  grep -E '^(KPI\||KO|ARRÊT|##)' "$T/recalcul.log"
  echo "## comparaison (code de l'exportateur $a, du recalcul $b)"
  python3 -I "$here/comparer_zot.py" "$T/recalcul.log" "$T/kpi.prom"; c=$?
  [ "$a$b$c" = 000 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
