#!/usr/bin/env bash
# Brique 05, M5b : attribution de la croissance de / sur sc-stockage entre les relevés df du 20/11 16:04:23Z
# (sc-stockage-agrandir-apres.log) et du 21/11 16:10:10Z (sc-stockage-releve-2026-11-21.log).
# Lecture seule de Prometheus à travers Grafana (compte auditeur) : des nombres seulement, aucune ligne de journal.
# Complément du 21/11 (relecture du conseiller) : WAL et tête de Prometheus, que prometheus_tsdb_storage_blocks_bytes ne compte pas.
# Usage (racine du dépôt) : poc/bricks/05-rpm-mock/resultats/sc-stockage-releve-2026-11-21-prom-2.sh > <journal>
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
  echo "prometheus_tsdb_wal_storage_size_bytes :"; prom 'prometheus_tsdb_wal_storage_size_bytes' "$t"
  echo "prometheus_tsdb_head_chunks_storage_size_bytes :"; prom 'prometheus_tsdb_head_chunks_storage_size_bytes' "$t"
done
