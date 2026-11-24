#!/usr/bin/env bash
# Brique 20, étape 1, vérification demandée par le conseiller : y a-t-il dans Loki des lignes d'avant le rejeu de zéro du 23/11
# (rejeu-un-trait-1, début 2026-11-23T20:35:05Z) ? Lecture seule, par l'auditeur dans Grafana ; comptes seulement, aucune ligne brute.
# entrees-scan tourne depuis le 21/11 (07b, tranche 1) : si Loki avait survécu au rejeu, les fenêtres d'avant le 23/11 auraient des lignes.
# Usage (racine du dépôt) : bash poc/bricks/20-kpi/loki-anciennete.sh > <journal>
O8=$HOME/.cache/supply-chain-poc/08
q() { # expr instant(epoch s)
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query \
      -d "$(jq -nc --arg q "$1" --arg t "${2}000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant"}]}')" \
    | jq -r '[.results.A.frames[]? | "\(.schema.fields[1].labels // {} | tojson) \(.data.values[1][0])"] | if length == 0 then "aucune série" else .[] end'
}
echo "# loki-anciennete.sh, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
for t in 2026-11-22T12:00:00Z 2026-11-23T20:00:00Z 2026-11-24T12:00:00Z; do
  e=$(date -u -d "$t" +%s)
  echo "## fenêtre de 24 h finissant à $t"
  echo "tout le journal : $(q 'sum(count_over_time({source="journal"}[24h]))' "$e" | tr '\n' ' ')"
  echo "entrees-scan : $(q 'sum(count_over_time({source="journal", unite="entrees-scan.service"}[24h]))' "$e" | tr '\n' ' ')"
done
