#!/usr/bin/env bash
# Brique 08c : relevé avant H5, sans rien changer. Durées de la porte, limites manquantes par charge, consommation à l'instant, droits effectifs, noms seulement.
# Usage (racine du dépôt) : poc/bricks/08c-durcissement/essais-h5-releve.sh   (journal : resultats/durcissement-h5-releve.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
FLUX=$HOME/.cache/supply-chain-poc/08/travail/durcissement/flux/sc-confiance-refus.txt

{
  date -u '+relevé du %d/%m/%Y à %H:%M:%S UTC, rien de modifié'

  echo "## conteneurs des deux Jobs de la porte de la preuve de S1 (début, fin, secondes)"
  for j in porte-ba-webhook porte-reelle-apres; do
    echo "$j"
    kubectl get pods -n porte -l "job-name=$j" -o json </dev/null \
      | jq -r '.items[0] | (.status.initContainerStatuses + .status.containerStatuses)[] | .state.terminated as $t | "  \(.name) \($t.startedAt) \($t.finishedAt) \(($t.finishedAt|fromdate) - ($t.startedAt|fromdate)) s"'
  done

  echo "## refus vers 34.117.62.14:443 pendant la preuve de S1 (SYN, identité, port source)"
  grep '34.117.62.14' "$FLUX" | sed -E 's/.*identity ([0-9]+)->world: [0-9.]+:([0-9]+) ->.*/\1 \2/' | sort | uniq -c

  echo "## échecs de limites-obligatoires dans les rapports, par espace"
  kubectl get policyreports -A -o json </dev/null \
    | jq -r '.items[] | .metadata.namespace as $n | (.results // [])[] | select(.result == "fail") | "\(.policy) \($n)"' | sort | uniq -c
  echo "(la règle ne lit que spec.containers : les conteneurs d'initialisation sont listés ci-dessous sans compter pour elle)"

  echo "## charges hors TaskRun, conteneurs sans limite de mémoire ou de CPU"
  kubectl get pods -A -o json </dev/null | jq -r '.items[]
    | select(.metadata.namespace | test("^(kube-|kyverno|local-path)") | not)
    | select(.metadata.ownerReferences[0].kind != "TaskRun")
    | .metadata.namespace as $n
    | ((.metadata.ownerReferences[0].kind // "-") + "/" + (.metadata.ownerReferences[0].name // .metadata.name)) as $o
    | (.spec.containers[] | [., "conteneur"]), ((.spec.initContainers // [])[] | [., "init"])
    | .[0] as $c | .[1] as $g
    | select(($c.resources.limits.memory == null) or ($c.resources.limits.cpu == null))
    | "  \($n) \($o | sub("-[0-9a-f]{8,10}(-[a-z0-9]{5})?$"; "") | sub("-[0-9]{8}$"; "")) \($c.name) \($g) mem=\($c.resources.limits.memory // "-") cpu=\($c.resources.limits.cpu // "-")"' | sort -u

  echo "## conteneurs de la dernière exécution par le webhook"
  kubectl get pods -n builds -l tekton.dev/pipelineRun -o json </dev/null | jq -r '[.items[] | select(.metadata.labels["tekton.dev/pipelineRun"] | startswith("sample-app-6391"))][]
    | .metadata.labels["tekton.dev/pipelineTask"] as $t | (.spec.containers + (.spec.initContainers // []))[] | "  \($t) \(.name) \(.resources | tojson)"'

  echo "## consommation à l'instant, hors espaces système (metrics-server, pas un pic)"
  kubectl top pods -A --no-headers </dev/null 2>&1 | grep -v -E '^(kube-system|kyverno|local-path-storage) ' | awk '{printf "  %s %s %s %s\n", $1, $2, $3, $4}' || true

  echo "## config-defaults de Tekton, clés actives (valeur _example retirée)"
  kubectl get cm -n tekton-pipelines config-defaults -o json </dev/null | jq -r '.data | del(._example) | keys | length | "  \(.) clé(s)"'

  echo "## droits effectifs de tous les comptes de service (auth can-i, à l'échelle du cluster)"
  kubectl get sa -A -o json </dev/null | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | while read -r n s; do
    u=system:serviceaccount:$n:$s
    g=$(kubectl auth can-i get secrets -A --as="$u" </dev/null 2>/dev/null)
    l=$(kubectl auth can-i list secrets -A --as="$u" </dev/null 2>/dev/null)
    h=$(kubectl auth can-i create helmcharts.helm.cattle.io -A --as="$u" </dev/null 2>/dev/null)
    [ "$g$l$h" = "nonono" ] || echo "  $n/$s get=$g list=$l helmchart=$h"
  done
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$here/resultats/durcissement-h5-releve.log"
