#!/bin/bash
# Ajout du 23/11/2026 après le scan de 09:30 : base Grype non renouvelée le 23/11. Lecture seule, par l auditeur à travers Grafana :
# comptes Loki seuls des messages de systemd (init.scope) sur base-grype de sc-stockage, par mot-clé et par tranche ; date de
# construction de la base la plus récente (métrique base_grype_construite_timestamp_seconds de fraicheur-scan, brique 19) ;
# échéances qui en découlent : alerte BaseGrypeVieillie (plus de 2 jours, pendant 5 min) et refus D4 de la porte (scan à plus de
# 3 jours de la construction de la base, scan.rego). Rien sur la VM.
set -uo pipefail
O8=$HOME/.cache/supply-chain-poc/08
R=$(git rev-parse --show-toplevel)
g() { # corps JSON de /api/ds/query
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$1"
}
q() { # expr Loki, heure de fin (epoch s)
  g "$(jq -nc --arg q "$1" --arg t "${2}000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')" \
    | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end'
}
now=$(date -u +%s)
echo "heure : $(date -u +%FT%TZ)"
S='{noeud="sc-stockage", source="journal", unite="init.scope"} |= "base-grype"'
for f in base-grype.timer base-grype.service Starting Started Finished Stopped Deactivated; do
  for r in 2h 26h; do echo "init.scope base-grype |= $f, $r : $(q "sum(count_over_time($S |= \"$f\" [$r]))" "$now")"; done
done
for h in 08:30 08:35 08:40 09:00 09:30; do
  e=$(date -ud "2026-11-23T${h}:00Z" +%s)
  echo "init.scope base-grype.timer, 5 min jusqu'à $h : $(q "sum(count_over_time($S |= \"base-grype.timer\" [5m]))" "$e")"
done
e=$(date -ud 2026-11-22T08:30:00Z +%s)
echo "init.scope base-grype, 30 min jusqu'au 22/11 08:30 : $(q "sum(count_over_time($S [30m]))" "$e")"
echo "unite base-grype.service, 26 h : $(q 'sum(count_over_time({noeud="sc-stockage", source="journal", unite="base-grype.service"} [26h]))' "$now")"
b=$(g "$(jq -nc --arg t "${now}000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:"base_grype_construite_timestamp_seconds",instant:true}]}')" \
  | jq -r '[.results.A.frames[]? | .data.values[1][0]] | if length == 1 then .[0] | tostring else "lecture impossible" end')
echo "base_grype_construite_timestamp_seconds : $b"
case $b in ''|*[!0-9]*) echo "bilan : KO (métrique illisible)"; exit 1 ;; esac
echo "base la plus récente construite le : $(date -ud "@$b" +%FT%TZ)"
s=$(sed -n 's/^ *base_age_max_jours: *\([0-9]*\)$/\1/p' "$R/poc/bricks/07a-sbom-grype/politique/porte/policy-scan.yaml")
echo "base_age_max_jours (policy-scan.yaml) : $s"
echo "refus D4 pour tout scan après : $(date -ud "@$((b + s * 86400))" +%FT%TZ)"
echo "alerte BaseGrypeVieillie (plus de 2 jours, for 5m) à partir de : $(date -ud "@$((b + 2 * 86400 + 300))" +%FT%TZ)"
echo "bilan : relevé fait"
