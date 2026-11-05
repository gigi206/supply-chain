#!/bin/bash
# Lecture seule : attend le passage planifié de scan-sample-app du jour donné (AAAA-MM-JJ) et relève la place libre la plus basse sur sc-confiance.
# Depuis la racine du dépôt, à lancer avant 09:29 UTC pour mesurer le creux. Journal : g7-passage-<jour>.log
J=${1:?jour}
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
O8=$HOME/.cache/supply-chain-poc/08
L=$PWD/poc/bricks/07a-sbom-grype/resultats/g7-passage-$J.log
mini=999999; j=""; etat=""
echo "# relevé du passage planifié du $J, $(date -u +%FT%TZ)" > "$L"
while [ "$(date -u +%s)" -lt "$(date -ud "$J 09:50:00" +%s)" ]; do
  if [ "$(date -u +%H%M)" -ge 0929 ]; then
    l=$(timeout 15 ssh -i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10 poc@192.168.161.11 'df -m --output=avail / | tail -1' | tr -d ' ')
    [ -n "$l" ] && [ "$l" -lt "$mini" ] && mini=$l
  fi
  j=$(kubectl get jobs -n scan -o json | jq -r --arg j "$J" '[.items[] | select((.metadata.name | startswith("scan-sample-app-")) and .metadata.creationTimestamp >= $j)] | sort_by(.metadata.creationTimestamp) | last | .metadata.name // ""')
  if [ -n "$j" ]; then
    etat=$(kubectl get job -n scan "$j" -o jsonpath='{.status.succeeded}/{.status.failed}')
    case $etat in 1/*|*/1) break ;; esac
  fi
  sleep 15
done
{
  echo "job : ${j:-aucun}, état $etat"
  kubectl get job -n scan -o custom-columns=NOM:.metadata.name,CREE:.metadata.creationTimestamp,FIN:.status.completionTime,OK:.status.succeeded,ECHEC:.status.failed --no-headers
  kubectl get cronjob -n scan scan-sample-app -o jsonpath='dernier passage : {.status.lastScheduleTime}, dernière réussite : {.status.lastSuccessfulTime}{"\n"}'
  echo "place libre la plus basse sur sc-confiance depuis 09:29 UTC : $mini Mo"
  [ -n "$j" ] && for c in source analyser attester publier revocation; do kubectl logs -n scan "job/$j" -c "$c" 2>&1 | grep -E '^(SOURCE|BASE|SBOM|SCAN|PREDICAT|ATTESTATION|PUBLIE)\||révoqué' | sed "s/^/$c: /"; done
  d=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
  echo "referrers : $(curl -fsS --cacert "$O8/pki/ca-poc.crt" "https://192.168.161.13:5000/v2/builds/scan/sample-app/referrers/$d" | jq '.manifests | length')"
  echo "# fin $(date -u +%FT%TZ)"
} >> "$L" 2>&1
