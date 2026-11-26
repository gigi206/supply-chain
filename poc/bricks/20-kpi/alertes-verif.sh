#!/usr/bin/env bash
# Brique 20, règles d'alerte KpiPassageEnRetard et KpiSignatureRefusee : ce que Grafana montre, lu par l'auditeur (/api/ds/query, source
# « prometheus »). Nombre de règles chargées (prometheus_rule_group_rules), alertes kpi en attente ou déclenchées (ALERTS), âge du dernier
# passage de l'exportateur, signatures refusées. Lecture seule. Usage (racine du dépôt) :
#   [SUFFIXE=-2] [REGLES=17] mise exec -- bash poc/bricks/20-kpi/alertes-verif.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e14-alertes-verif${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
O8=$HOME/.cache/supply-chain-poc/08
T=$HOME/.cache/supply-chain-poc/20/alertes-verif   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/alertes-verif ] || find ~/.cache/supply-chain-poc/20/alertes-verif -delete
trap 'find ~/.cache/supply-chain-poc/20/alertes-verif -delete 2> /dev/null' EXIT
mkdir -p "$T"
ko=0
lire() { # expression PromQL : une ligne « étiquettes valeur » par série, ou « (aucun résultat) » ; code HTTP dans $T/c
  jq -nc --arg t "$(date -u +%s)000" --arg e "$1" '{from: $t, to: $t, queries: [{refId: "A", datasource: {uid: "prometheus"}, expr: $e, instant: true, range: false}]}' > "$T/q.json"
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -o "$T/r.json" -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d @"$T/q.json" https://192.168.161.13:3001/api/ds/query > "$T/c"
  jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | "\(.schema.fields[1].labels // {} | del(.__name__) | tostring) \(.data.values[1][0])"]
    | if length == 0 then "(aucun résultat)" else .[] end' "$T/r.json"
}
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
{
  echo "# alertes-verif.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16)"
  r=$(lire 'sum(prometheus_rule_group_rules)'); attendu "HTTP (règles)" "$(cat "$T/c")" 200
  attendu "règles chargées, vues par Grafana" "${r##* }" "${REGLES:-17}"
  r=$(lire 'ALERTS{alerte="kpi"}'); attendu "HTTP (ALERTS)" "$(cat "$T/c")" 200
  attendu "alertes kpi en attente ou déclenchées" "$r" "(aucun résultat)"
  r=$(lire 'time() - kpi_exportateur_passage_timestamp_seconds'); attendu "HTTP (âge)" "$(cat "$T/c")" 200
  a=${r##* }; a=${a%.*}
  if [ -n "$a" ] && [ "$a" -ge 0 ] 2> /dev/null && [ "$a" -lt 2700 ]; then echo "OK   âge du dernier passage : $a s (< 2700)"; else echo "KO   âge du dernier passage : « $r »"; ko=$((ko + 1)); fi
  r=$(lire 'sum(kpi_signatures_refusees)'); attendu "HTTP (refus)" "$(cat "$T/c")" 200
  attendu "signatures refusées (somme)" "${r##* }" 0
  echo "## bilan : $ko KO"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
