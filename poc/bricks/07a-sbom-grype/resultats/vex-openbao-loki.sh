#!/bin/bash
# comptes Loki de l'audit d'OpenBao par l'auditeur, lecture seule, aucune ligne brute ; « étiquette nombre » par série
set -uo pipefail
O8=$HOME/.cache/supply-chain-poc/08
CA=$O8/pki/ca-poc.crt
GRAF=https://192.168.161.13:3001
q() {
  local t body
  t=$(date -u +%s)000
  body=$(jq -nc --arg q "$1" --arg t "$t" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$CA" -H 'Content-Type: application/json' -X POST "$GRAF/api/ds/query" -d "$body" \
    | jq -r --arg l "$2" '[.results.A.frames[]? | select((.data.values | length) > 1) | "\(.schema.fields[1].labels[$l] // "-") \(.data.values[1][0])"] | if length == 0 then "aucune série" else sort | join(",") end'
}
O='{source="pods", espace="openbao"} | json | type="response"'
echo "heure : $(date -u +%Y-%m-%dT%H:%M:%SZ) ; fenêtre : 15 min"
echo "signatures réussies sur transit/sign/vex, par identité : $(q "sum by (auth_display_name) (count_over_time($O | request_path=~\"transit/sign/vex.*\" | error=\"\" [15m]))" auth_display_name)"
echo "signatures refusées sur transit/sign/vex, par identité : $(q "sum by (auth_display_name) (count_over_time($O | request_path=~\"transit/sign/vex.*\" | error!=\"\" [15m]))" auth_display_name)"
echo "écritures de l'utilisateur proprietaire (création ou mise à jour), par identité : $(q "sum by (auth_display_name) (count_over_time($O | request_path=\"auth/userpass/users/proprietaire\" | request_operation=~\"create|update\" [15m]))" auth_display_name)"
echo "connexions userpass de proprietaire, par résultat (vide = réussie) : $(q "sum by (error) (count_over_time($O | request_path=\"auth/userpass/login/proprietaire\" [15m]))" error)"
echo "création de la clé vex, par identité : $(q "sum by (auth_display_name) (count_over_time($O | request_path=\"transit/keys/vex\" | request_operation=~\"create|update\" [15m]))" auth_display_name)"
