#!/usr/bin/env bash
# Brique 19b (journalisation d'audit dans Grafana, décisions D8 à D12 du propriétaire du 02/11/2026).
# Jalon L1, relevé en lecture seule :
#   telecharger  archives amont épinglées dans ~/.cache/supply-chain-poc/19b/amont : sha256 figés ici ; Alloy et Loki :
#                attestation de release GitHub (gh release verify-asset), mesurée ; Grafana : sha256 publié par Grafana Labs
#                (dl.grafana.com et API grafana.com, concordants au relevé), aucune signature ni attestation de l'archive
#   releve       ressources de sc-stockage ; volume de journald et des journaux de pods sur la dernière heure, par VM et
#                par espace ; événements Kubernetes ; audits existants (k3s, OpenBao, Zot) ; CLA de Grafana Labs
# Aucun secret en argument de commande.
#
# Usage (racine du dépôt) : mise run journalisation -- <étape>…   (journal : resultats/l1-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"   # sur, racine, IP, P, S, W, lancer, chrono (R = resultats de la 19b)
A=$HOME/.cache/supply-chain-poc/19b/amont
LOKI_VERSION=3.7.9
LOKI_ARCHIVE=loki-linux-amd64.zip
LOKI_SHA=17a5fae28ce733b3560c27c76620920b169bd2aea9473947b733b511f92e81dd     # SHA256SUMS de v3.7.9, relevé le 02/11/2026
ALLOY_VERSION=1.21.3
ALLOY_ARCHIVE=alloy-linux-amd64.zip
ALLOY_SHA=50d23af2d0f98c00beac6ce9a365693e60f87fb76b6cad6fe1d161e80588af6d    # SHA256SUMS de v1.21.3, relevé le 02/11/2026
GRAFANA_VERSION=13.3.0
GRAFANA_ARCHIVE=grafana_13.3.0_40412481033_linux_amd64.tar.gz
GRAFANA_URL=https://dl.grafana.com/grafana/release/$GRAFANA_VERSION/$GRAFANA_ARCHIVE   # URL donnée par l'API grafana.com
GRAFANA_SHA=cec8f98cc59bc1a1945833b652371a073be678c5c159a9b1695ad63c04fae5a7  # .sha256 de dl.grafana.com et API grafana.com, 02/11/2026
mkdir -p "$A" "$R"

etape_telecharger() {
  [ -s "$A/$LOKI_ARCHIVE" ] || gh release download "v$LOKI_VERSION" -R grafana/loki -p "$LOKI_ARCHIVE" -D "$A"
  [ -s "$A/$ALLOY_ARCHIVE" ] || gh release download "v$ALLOY_VERSION" -R grafana/alloy -p "$ALLOY_ARCHIVE" -D "$A"
  [ -s "$A/$GRAFANA_ARCHIVE" ] || curl -fsSL -o "$A/$GRAFANA_ARCHIVE" "$GRAFANA_URL"
  ls -l "$A" | awk 'NR > 1 {print "  " $5, $9}'
  (cd "$A" && printf '%s  %s\n%s  %s\n%s  %s\n' "$LOKI_SHA" "$LOKI_ARCHIVE" "$ALLOY_SHA" "$ALLOY_ARCHIVE" "$GRAFANA_SHA" "$GRAFANA_ARCHIVE" | sha256sum -c)
  echo "## Grafana : empreinte relue dans l'API grafana.com au moment du téléchargement"
  curl -fsS "https://grafana.com/api/downloads/grafana/versions/$GRAFANA_VERSION" \
    | jq -r --arg u "$GRAFANA_URL" '.packages[] | select(.url == $u) | .sha256' | sed 's/^/  /'
  echo "## attestations de release GitHub (gh release verify-asset)"
  gh release verify-asset "v$ALLOY_VERSION" "$A/$ALLOY_ARCHIVE" -R grafana/alloy 2>&1 | sed 's/^/  alloy : /' || echo "  alloy : ÉCHEC"
  gh release verify-asset "v$LOKI_VERSION" "$A/$LOKI_ARCHIVE" -R grafana/loki 2>&1 | sed 's/^/  loki : /' || echo "  loki : ÉCHEC"
}

etape_releve() {
  local vm t
  t=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%S)
  echo "## sc-stockage : ressources"
  sur sc-stockage "nproc; free -m | sed -n 1,2p; df -h / /var/lib 2>/dev/null | sort -u; sudo du -sh /var/lib/prometheus 2>/dev/null || true"
  echo "## journald, dernière heure (octets de la sortie JSON, lignes ; dix unités les plus bavardes)"
  for vm in sc-confiance sc-build sc-stockage; do
    echo "### $vm"
    sur "$vm" "sudo journalctl --since '1 hour ago' -o json --no-pager | wc -lc; sudo journalctl --disk-usage; \
      sudo journalctl --since '1 hour ago' -o json --no-pager | python3 -c 'import sys, json, collections; c = collections.Counter(); [c.update([(lambda d: d.get(\"_SYSTEMD_UNIT\") or d.get(\"SYSLOG_IDENTIFIER\") or \"?\")(json.loads(l))]) for l in sys.stdin]; [print(f\"{n:8d}  {u}\") for u, n in c.most_common(10)]'"   # jq absent des VM (deuxième passage)
  done
  echo "## journaux de pods depuis $t UTC (lignes CRI horodatées ; octets et lignes par espace, sur chaque nœud)"
  for vm in sc-confiance sc-build; do
    echo "### $vm"
    sur "$vm" "sudo find /var/log/pods -name '*.log' -type f -exec awk -v t='$t' '\$1 >= t { split(FILENAME, p, \"/\"); split(p[5], q, \"_\"); n[q[1]]++; b[q[1]] += length(\$0) + 1 } END { for (k in n) printf \"%10d o %7d lignes  %s\n\", b[k], n[k], k }' {} + | sort -rn; sudo du -sh /var/log/pods"
  done
  echo "## événements Kubernetes"
  kubectl get events -A --no-headers 2>/dev/null | wc -l
  kubectl get events -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -8
  echo "## audits existants"
  echo "### serveur k3s (ligne de commande et configuration)"
  sur sc-confiance "sudo grep -rn audit /etc/rancher/k3s/ 2>/dev/null || echo '  aucune mention d audit dans /etc/rancher/k3s'; \
    sudo grep -v '^ *#' /etc/rancher/k3s/audit-policy.yaml; sudo ls -l /var/lib/rancher/k3s/server/logs/; \
    sudo awk -v t='$t' '\$0 ~ \"requestReceivedTimestamp\" { if (match(\$0, /\"requestReceivedTimestamp\":\"[^\"]*/) && substr(\$0, RSTART + 28, 19) >= t) { n++; b += length(\$0) + 1 } } END { printf \"  dernière heure : %d événements, %d o\\n\", n, b }' /var/lib/rancher/k3s/server/logs/audit.log"
  echo "### OpenBao (devices d'audit)"
  racine <<<'bao audit list -format=json 2>&1 || true'
  kubectl exec -n openbao openbao-0 -- sh -c 'ls -l /openbao/data/audit.log; wc -l < /openbao/data/audit.log; df -h /openbao/data | tail -1'
  echo "### Zot (section log de la configuration)"
  sur sc-stockage "sudo python3 -c 'import json; print(json.dumps(json.load(open(\"/etc/zot/config.json\")).get(\"log\")))'"   # jq absent de la VM (premier passage)
  echo "## CLA de Grafana Labs (fichiers du dépôt, branche par défaut)"
  for r in grafana/grafana grafana/loki grafana/alloy; do
    printf '  %s : ' "$r"
    { curl -fsS "https://api.github.com/repos/$r/contents/CONTRIBUTING.md" | jq -r .content | base64 -d 2>/dev/null; } \
      | grep -o -m1 -E '.{0,60}(\bCLA\b|[Cc]ontributor [Ll]icense [Aa]greement).{0,60}' || echo "aucune mention dans CONTRIBUTING.md (racine)"
  done
  echo "  contrôles de la dernière PR fermée (statut license/cla attendu) :"
  for r in grafana/grafana grafana/loki grafana/alloy; do
    n=$(curl -fsS "https://api.github.com/repos/$r/pulls?state=closed&per_page=1" | jq -r '.[0].number')
    printf '    %s PR %s : %s\n' "$r" "$n" "$(curl -fsS "https://api.github.com/repos/$r/commits/$(curl -fsS "https://api.github.com/repos/$r/pulls/$n" | jq -r .head.sha)/status" | jq -r '[.statuses[].context] | join(", ")')"
  done
  echo "  workflows dont le nom évoque un CLA :"
  for r in grafana/grafana grafana/loki grafana/alloy; do
    printf '    %s : %s\n' "$r" "$(curl -fsS "https://api.github.com/repos/$r/contents/.github/workflows" | jq -r '[.[].name | select(test("cla"; "i"))] | join(", ")')"
  done
}

lancer l1 L1 "$@"
