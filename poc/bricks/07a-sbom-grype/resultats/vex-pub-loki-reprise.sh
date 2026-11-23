#!/bin/bash
# Ajout du 23/11/2026 après le redémarrage de sc-stockage : comptes Loki seuls, par l auditeur à travers Grafana ; audit-k8s par tranches (perte ou requête fausse ?) puis écriture de scan-config de la pose avec son heure de réception par l API (requestReceivedTimestamp, en étiquette de compte)
set -uo pipefail
O8=$HOME/.cache/supply-chain-poc/08
q() { # expr, heure de fin (epoch s)
  local body
  body=$(jq -nc --arg q "$1" --arg t "${2}000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$body" \
    | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end'
}
S='{noeud="sc-confiance", source="audit-k8s"}'
now=$(date -u +%s)
echo "heure : $(date -u +%FT%TZ)"
for h in 06:00 06:30 06:45 07:00 07:30 08:00 08:15 08:30; do
  e=$(date -ud "2026-11-23T${h}:00Z" +%s)
  echo "audit-k8s, 15 min jusqu'à $h : $(q "sum(count_over_time($S [15m]))" "$e")"
done
echo "audit-k8s, 2 dernières min : $(q "sum(count_over_time($S [2m]))" "$now")"
echo "audit-k8s configmaps scan, 2 dernières min : $(q "sum(count_over_time($S | json | objectRef_resource=\"configmaps\" | objectRef_namespace=\"scan\" [2m]))" "$now")"
echo "audit-k8s avec objectRef_resource, 2 dernières min : $(q "sum(count_over_time($S | json | objectRef_resource!=\"\" [2m]))" "$now")"
echo "audit-k8s verbe patch, 24 h : $(q "sum(count_over_time($S | json | verb=\"patch\" [24h]))" "$now")"
A="$S | json | objectRef_resource=\"configmaps\" | objectRef_namespace=\"scan\" | objectRef_name=\"scan-config\" | verb=~\"create|update|patch|delete\""
echo "écritures de scan-config, 3 h : $(q "sum(count_over_time($A [3h]))" "$now")"
for h in 08:16 08:20 08:25 08:30 08:34; do e=$(date -ud "2026-11-23T${h}:00Z" +%s); echo "écritures de scan-config, 5 min jusqu'à $h : $(q "sum(count_over_time($A [5m]))" "$e")"; done
echo "écritures de scan-config, 2 dernières min : $(q "sum(count_over_time($A [2m]))" "$(date -u +%s)")"
for h in 08:18 08:21 08:24 08:27 08:30 08:33; do e=$(date -ud "2026-11-23T${h}:00Z" +%s); echo "audit-k8s, 3 min jusqu'à $h : $(q "sum(count_over_time($S [3m]))" "$e")"; done
echo "écriture de scan-config sur 3 h, par heure de réception/verbe/utilisateur/code : $(
  Q="sum by (requestReceivedTimestamp, verb, user_username, responseStatus_code) (count_over_time($A [3h]))"
  body=$(jq -nc --arg q "$Q" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$body" \
    | jq -r '[.results.A.frames[]? | "\(.schema.fields[1].labels | [.requestReceivedTimestamp, .verb, .user_username, .responseStatus_code] | join("/")) \(.data.values[1][0])"] | if length == 0 then "aucune série" else join(",") end')"
