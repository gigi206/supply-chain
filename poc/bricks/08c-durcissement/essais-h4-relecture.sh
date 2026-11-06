#!/usr/bin/env bash
# Brique 08c : relecture après H4, sans rien changer. Baux DHCP renouvelés sous blocage, journaux des nœuds dans Loki, sondes de cilium-health.
# Usage (racine du dépôt) : poc/bricks/08c-durcissement/essais-h4-relecture.sh   (journal : resultats/durcissement-h4-relecture.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
O=$HOME/.cache/supply-chain-poc/08
K=$O/ssh
SSH=(ssh -n -i "$K/id_ed25519" -o UserKnownHostsFile="$K/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)

loki() { # LogQL, instantané
  curl -sS --max-time 20 --cacert "$O/pki/ca-poc.crt" --cert "$O/pki/controle.crt" --key "$O/secrets/controle.key" -G "https://192.168.161.13:3100/loki/api/v1/query" \
    --data-urlencode "query=$1" | jq -r '.data.result[]? | "  \(.metric | to_entries | map("\(.key)=\(.value)") | join(",")) \(.value[1])"'
}

{
  date -u '+relecture du %d/%m/%Y à %H:%M:%S UTC, H4 à 17:48 UTC'
  echo "## baux DHCP"
  for ip in 11 12 13; do
    "${SSH[@]}" "poc@192.168.161.$ip" "sudo sh -c 'stat -c \"%y\" /run/systemd/netif/leases/* | cut -c1-19; ip -4 -o addr show enp1s0 | sed -E \"s/.*(valid_lft [^ ]+).*/\1/\"'" </dev/null 2>&1 | paste -sd' ' | sed "s/^/  .$ip /"
  done
  echo "## journaux dans Loki, 5 dernières minutes, par nœud puis par source"
  loki 'sum by (noeud) (count_over_time({source=~".+"}[5m]))'
  loki 'sum by (source) (count_over_time({source=~".+"}[5m]))'
  echo "## cilium-health"
  while read -r p n; do
    echo "$n : $(kubectl exec -n kube-system "$p" -c cilium-agent -- cilium-health status --probe </dev/null 2>/dev/null | grep -E 'Cluster health|sc-(confiance|build|stockage)' | tr -s ' ' | paste -sd';' | cut -c1-240)"
  done < <(kubectl get pods -n kube-system -l k8s-app=cilium -o json </dev/null | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"')
  echo "## verdicts refusés de l'hôte depuis H4, deux minutes de relevé"
  while read -r p n; do
    echo "$n : $(kubectl exec -n kube-system "$p" -c cilium-agent -- timeout 120 cilium-dbg monitor -t drop </dev/null 2>/dev/null | grep -c 'Policy denied' || true) refus de politique" &
  done < <(kubectl get pods -n kube-system -l k8s-app=cilium -o json </dev/null | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"')
  wait
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$here/resultats/durcissement-h4-relecture.log"
