#!/usr/bin/env bash
# Brique 05, M4b : relevé de / sur sc-stockage (porte /var/lib/zot), sans sudo, pour attribuer sa croissance hors écritures de la
# brique (18/11/2026). Compte poc : du ne lit que les arbres lisibles ; les arbres illisibles (750 ou 700 à un autre propriétaire)
# sont seulement nommés. Prometheus : tailles lues dans ses propres métriques (127.0.0.1:9090), des nombres seulement.
# Usage (racine du dépôt) : poc/bricks/05-rpm-mock/resultats/m4b-disque-sc-stockage.sh >> <journal>
export LC_ALL=C DISTRO=rke2
. poc/bricks/08-trust-plane/commun.sh > /dev/null 2>&1   # chargé avant set -eu (sortie silencieuse sinon)
set -euo pipefail
echo "## relevé, début $(date -u +%FT%TZ)"
sur sc-stockage '
df -B1 --output=used,avail / | tail -n 1 | awk "{print \"df / : utilisés \" \$1 \" ; libres \" \$2}"
for d in /var/log/journal /var/lib/rancher /var/lib/apt /var/lib/dpkg /var/cache /opt /home; do
  printf "du %s %s\n" "$d" "$(du -sxb "$d" 2> /dev/null | cut -f1)"
done
for m in prometheus_tsdb_storage_blocks_bytes prometheus_tsdb_wal_storage_size_bytes prometheus_tsdb_head_chunks_storage_size_bytes; do
  curl -s --max-time 5 http://127.0.0.1:9090/metrics | awk -v m="$m" "\$1 == m {printf \"prometheus %s %.0f\n\", m, \$2}"
done
printf "illisibles pour %s :" "$(id -un)"
for d in /var/lib/* /var/log/*; do [ -d "$d" ] && ! [ -r "$d" -a -x "$d" ] && printf " %s" "$d"; done; echo
' < /dev/null
echo "## relevé, fin $(date -u +%FT%TZ)"
