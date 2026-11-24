#!/usr/bin/env bash
# Brique 20, étape 2 : lance recalcul.py (recalcul de référence, signatures vérifiées) et archive son journal, jamais réécrit.
# Usage (racine du dépôt) : [SUFFIXE=-1] mise exec -- bash poc/bricks/20-kpi/recalcul.sh   (journal : resultats/e2-recalcul<SUFFIXE>.log)
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e2-recalcul${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
[ ! -e ~/.cache/supply-chain-poc/20/recalcul ] || find ~/.cache/supply-chain-poc/20/recalcul -delete
trap 'find ~/.cache/supply-chain-poc/20/recalcul -delete 2> /dev/null' EXIT
{
  echo "# recalcul.py, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), scripts $(cat "$here/kpi.py" "$here/recalcul.py" | sha256sum | cut -c1-16)"
  echo "# cosign $(cosign version 2> /dev/null | awk '/GitVersion/{print $2}') ; essais de kpi.py : $(python3 "$here/essais_kpi.py" | tail -1)"
  python3 -I "$here/recalcul.py"
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
