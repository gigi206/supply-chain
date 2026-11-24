#!/usr/bin/env bash
# Brique 20, étape 5 : le seuil (« 0 écart avec le recalcul depuis les attestations »). Les séries kpi_* telles que Prometheus les a, lues par
# l'auditeur à travers Grafana, contre le recalcul signé par cosign lancé juste après (comparer_zot.py, sans le passage à clé étrangère).
# Lecture seule : Grafana par l'auditeur, Zot en anonyme, git. Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/20-kpi/seuil.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e5-seuil${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
O8=$HOME/.cache/supply-chain-poc/08
T=$HOME/.cache/supply-chain-poc/20/seuil   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/seuil ] || find ~/.cache/supply-chain-poc/20/seuil -delete
trap 'find ~/.cache/supply-chain-poc/20/seuil ~/.cache/supply-chain-poc/20/recalcul -delete 2> /dev/null' EXIT
mkdir -p "$T"
{
  echo "# seuil.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), comparer $(sha256sum < "$here/comparer_zot.py" | cut -c1-16)"
  jq -nc --arg t "$(date -u +%s)000" '{from: $t, to: $t, queries: [{refId: "A", datasource: {uid: "prometheus"}, expr: "{__name__=~\"kpi_.+\"}", instant: true, range: false}]}' > "$T/q.json"
  c=$(printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -o "$T/r.json" -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d @"$T/q.json" https://192.168.161.13:3001/api/ds/query)
  # étiquettes de collecte (job, instance) retirées, les autres triées : le format du fichier .prom de l'exportateur
  jq -r '.results.A.frames[]? | select((.data.values | length) > 1) | .schema.fields[1].labels as $l | .data.values[1][0] as $v
    | ($l | del(.__name__, .job, .instance) | to_entries | sort_by(.key) | map("\(.key)=\"\(.value)\"") | join(",")) as $e
    | $l.__name__ + (if $e == "" then "" else "{\($e)}" end) + " \($v)"' "$T/r.json" | sort > "$T/kpi.prom"
  echo "Prometheus par l'auditeur : HTTP $c, $(wc -l < "$T/kpi.prom") séries, âge du passage $(awk -v n="$(date -u +%s)" '/^kpi_exportateur_passage/{print n - $2}' "$T/kpi.prom") s"
  sed 's/^/PROM|/' "$T/kpi.prom"
  python3 -I "$here/recalcul.py" > "$T/recalcul.log" 2>&1; b=$?
  grep -E '^(KPI\||DETAIL\|builds|KO|ARRÊT|##)' "$T/recalcul.log"
  echo "## comparaison (code du recalcul $b)"
  python3 -I "$here/comparer_zot.py" "$T/recalcul.log" "$T/kpi.prom" -; d=$?
  echo "## codes : HTTP $c, recalcul $b, comparaison $d"
  [ "$c$b$d" = 20000 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
