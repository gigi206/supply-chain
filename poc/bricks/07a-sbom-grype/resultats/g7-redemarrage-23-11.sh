#!/usr/bin/env bash
# Ajout du 23/11/2026 (G7, après le redémarrage de sc-stockage à 08:33 UTC) : début et fin des balayages de Zot autour du
# redémarrage, lus dans Loki à travers Grafana (compte auditeur), par tranches de 10 s ; comptes seuls, aucune ligne archivée.
# Rien sur la VM, rien dans Zot. Fenêtres : balayage n°3 attendu le 22/11 vers 22:30 UTC, et le démarrage de Zot le 23/11.
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/resultats/g7-redemarrage-23-11.sh  (journal : g7-redemarrage-23-11.log)
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
O8=$HOME/.cache/supply-chain-poc/08
L=$here/g7-redemarrage-23-11.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
rq() { # expr Loki (compte par tranche de 10 s), début, fin (ISO) : première et dernière tranche non nulles, total
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query \
      -d "$(jq -nc --arg q "$1" --arg f "$(date -ud "$2" +%s)000" --arg t "$(date -ud "$3" +%s)000" '{from:$f,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"range",step:"10s",intervalMs:10000,maxLines:1}]}')" \
    | jq -r 'if .results.A.error then "erreur : \(.results.A.error)" else
        [.results.A.frames[]? | select((.data.values | length) > 1) | [.data.values[0], .data.values[1]] | transpose[] | select(.[1] > 0)]
        | if length == 0 then "aucune" else "de \(.[0][0] / 1000 | todate) à \(.[-1][0] / 1000 | todate), \(map(.[1]) | add) lignes, \(length) tranches de 10 s" end end'
}
Z='{noeud="sc-stockage", source="journal", unite="zot.service"}'
{
echo "# g7-redemarrage-23-11.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; Loki à travers Grafana, tranches de 10 s (heure de la tranche)"
for w in "2026-11-22T21:30:00Z 2026-11-23T00:30:00Z" "2026-11-23T06:00:00Z 2026-11-23T08:30:00Z" "2026-11-23T08:30:00Z 2026-11-23T10:30:00Z" "2026-11-23T10:30:00Z $(date -u +%Y-%m-%dT%H:%M:00Z)"; do
  set -- $w
  echo "== fenêtre $1 -> $2"
  echo "  gc (executing gc of orphaned blobs) : $(rq "sum(count_over_time($Z |= \"executing gc of orphaned blobs\" [10s]))" "$1" "$2")"
  echo "  rétention (retention, sans casse)   : $(rq "sum(count_over_time($Z |~ \"(?i)retention\" [10s]))" "$1" "$2")"
  echo "  démarrage (starting|listening|config) : $(rq "sum(count_over_time($Z |~ \"(?i)starting|listening|config\" [10s]))" "$1" "$2")"
  echo "  toutes les lignes de zot.service    : $(rq "sum(count_over_time($Z [10s]))" "$1" "$2")"
done
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "bilan : relevé fait"
} 2>&1 | tee "$L"
