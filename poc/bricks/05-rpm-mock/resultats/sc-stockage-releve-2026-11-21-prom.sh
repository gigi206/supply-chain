#!/usr/bin/env bash
# Brique 05, M5b : attribution de la croissance de / sur sc-stockage entre les relevés df du 20/11 16:04:23Z
# (sc-stockage-agrandir-apres.log) et du 21/11 16:10:10Z (sc-stockage-releve-2026-11-21.log).
# Lecture seule de Prometheus à travers Grafana (compte auditeur) : des nombres seulement, aucune ligne de journal.
# Usage (racine du dépôt) : poc/bricks/05-rpm-mock/resultats/sc-stockage-releve-2026-11-21-prom.sh > <journal>
set -euo pipefail
export LC_ALL=C
P=$HOME/.cache/supply-chain-poc/08/pki
S=$HOME/.cache/supply-chain-poc/08/secrets
T0=2026-11-20T16:04:23Z
T1=2026-11-21T16:10:10Z
t0=$(date -u -d "$T0" +%s)
t1=$(date -u -d "$T1" +%s)
ECART=$((t1 - t0))

# Requête instantanée à l'instant $2 ; affiche les étiquettes (sans __name__) et la valeur de chaque série.
prom() {
  local q
  q=$(jq -nc --arg e "$1" --arg t "${2}000" \
    '{queries: [{refId: "A", datasource: {uid: "prometheus"}, expr: $e, instant: true, range: false}], from: $t, to: $t}')
  printf 'user = "auditeur:%s"\n' "$(cat "$S/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$P/ca-poc.crt" -X POST -H 'Content-Type: application/json' \
        "https://192.168.161.13:3001/api/ds/query" -d "$q" \
    | jq -r '.results.A.frames[]? | "  \(.schema.fields[1].labels // {} | del(.__name__) | tojson) \(.data.values[1][0])"'
}

echo "## lancé à $(date -u +%FT%TZ) ; intervalle $T0 -> $T1 ($ECART s)"
for t in "$t0" "$t1"; do
  echo "## à $(date -u -d "@$t" +%FT%TZ)"
  echo "somme de zot_repo_storage_bytes :"; prom 'sum(zot_repo_storage_bytes)' "$t"
  echo "dépôts de Zot mesurés :"; prom 'count(zot_repo_storage_bytes)' "$t"
  echo "prometheus_tsdb_storage_blocks_bytes :"; prom 'prometheus_tsdb_storage_blocks_bytes' "$t"
done
echo "## hausse par dépôt de Zot sur l'intervalle (6 premiers)"
prom "topk(6, zot_repo_storage_bytes - zot_repo_storage_bytes offset ${ECART}s)" "$t1"
echo "## dépôts de Zot en baisse sur l'intervalle (rien = aucun)"
prom "count((zot_repo_storage_bytes - zot_repo_storage_bytes offset ${ECART}s) < 0)" "$t1"
echo "## octets envoyés par Alloy à Loki (loki_write_sent_bytes_total), par tranche de 24 h"
prom "increase(loki_write_sent_bytes_total[${ECART}s])" "$t1"
for k in 0 1 2; do
  t=$((t0 - k * 86400))
  echo "24 h jusqu'à $(date -u -d "@$t" +%FT%TZ) :"; prom 'increase(loki_write_sent_bytes_total[86400s])' "$t"
done
echo "## node_filesystem_avail_bytes (rien = pas d'exportateur de nœud)"
prom 'node_filesystem_avail_bytes{mountpoint="/"}' "$t1"
