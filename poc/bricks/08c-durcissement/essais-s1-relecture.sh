#!/usr/bin/env bash
# Brique 08c : relecture après S1, sans rien changer et sans lire de valeur. Contrôleur Chains, refus de Cilium, rapports de Kyverno, refus par --as.
# Usage (racine du dépôt) : poc/bricks/08c-durcissement/essais-s1-relecture.sh   (journal : resultats/secrets-s1-relecture.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
NS=tekton-chains
RESOLVEURS=system:serviceaccount:tekton-pipelines-resolvers:tekton-pipelines-resolvers

{
  date -u '+relecture du %d/%m/%Y à %H:%M:%S UTC, s1_chains à 18:39 UTC'
  echo "## contrôleur"
  kubectl get pods -n "$NS" -o json </dev/null | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName) prêt=\(.status.containerStatuses[0].ready) redémarrages=\(.status.containerStatuses[0].restartCount) init=\(.status.initContainerStatuses[0].state.terminated.reason // "?")/\(.status.initContainerStatuses[0].restartCount)"'
  echo "lignes de niveau error ou fatal au journal du contrôleur : $(kubectl logs -n "$NS" deploy/tekton-chains-controller -c tekton-chains-controller </dev/null 2>/dev/null | grep -cE '"(severity|level)":"(error|fatal)"' || true)"
  echo "Secrets de l'espace : $(kubectl get secret -n "$NS" -o json </dev/null | jq -c '[.items[].metadata.name]')"
  echo "## refus depuis ou vers tekton-chains, agent de sc-confiance, Hubble, 5 dernières minutes"
  a=$(kubectl get pods -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=sc-confiance -o jsonpath='{.items[0].metadata.name}' </dev/null)
  r=$(kubectl exec -n kube-system "$a" -c cilium-agent -- hubble observe --namespace "$NS" --verdict DROPPED --since 5m --last 1000 -o compact </dev/null 2>/dev/null || true)
  echo "refus : $(printf '%s' "$r" | grep -c . || true)"
  printf '%s\n' "$r" | head -n 8 | cut -c1-200
  echo "## Kyverno, rapport de l'espace (mode Audit)"
  kubectl get policyreports -n "$NS" -o json </dev/null | jq -r '[.items[].results[]? | select(.result == "fail") | .policy + "/" + .rule] | group_by(.) | map("\(.[0]) : \(length)") | .[]'
  echo "## lecture de zot-chains au nom des résolveurs : le Secret n'existe plus, le refus doit rester celui des droits"
  kubectl get secret -n "$NS" zot-chains --as "$RESOLVEURS" -o name </dev/null 2>&1 | cut -c1-200
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$here/resultats/secrets-s1-relecture.log"
