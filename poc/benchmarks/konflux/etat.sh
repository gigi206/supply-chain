#!/usr/bin/env bash
# Banc A1 : archive l'état du cluster Konflux dans resultats/etat-<libellé>/.
# - pods.txt : kubectl get pods -A -o wide ;
# - images.tsv : image du spec et imageID réellement exécuté, pour chaque conteneur ;
#   images-sans-digest.tsv : images du spec citées par tag seulement ;
# - composants.txt (règle A-5) : Deployments, StatefulSets et DaemonSets hors
#   kube-system et local-path-storage ;
# - memoire.txt : docker stats du nœud (RAM au repos : libellé « repos-30min ») ;
# - tekton.txt : versions des composants Tekton ; chains-config.yaml : format et stockage.
#
# Usage (racine du dépôt) : mise run konflux:etat -- <libellé>
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
E=$here/resultats/etat-${1:?libellé}
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
export KUBECONFIG=$HOME/.kube/supply-chain-poc-konflux.yaml
noeud=konflux-control-plane
rm -rf "$E"
mkdir -p "$E"

date -u +%Y-%m-%dT%H:%M:%SZ > "$E/date.txt"
kubectl get pods -A -o wide > "$E/pods.txt"
kubectl get pods -A -o json > "$E/pods.json.tmp"
jq -r '.items[] | .metadata.namespace as $n | .metadata.name as $p
  | ((.status.initContainerStatuses // []) + (.status.containerStatuses // []))[]
  | [$n, $p, .name, .image, .imageID] | @tsv' "$E/pods.json.tmp" | sort > "$E/images.tsv"
jq -r '.items[] | .metadata.namespace as $n | ((.spec.initContainers // []) + .spec.containers)[]
  | [$n, .image] | @tsv' "$E/pods.json.tmp" | sort -u > "$E/images-spec.tsv"
rm "$E/pods.json.tmp"
awk -F'\t' '$2 !~ /@sha256:[0-9a-f]{64}$/' "$E/images-spec.tsv" > "$E/images-sans-digest.tsv"
kubectl get deploy,sts,ds -A --no-headers | awk '$1 != "kube-system" && $1 != "local-path-storage"' > "$E/composants.txt"
docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}\t{{.PIDs}}' "$noeud" > "$E/memoire.txt"
kubectl get deploy -A -o json | jq -r '.items[] | select(.metadata.namespace | test("tekton|pipelines"))
  | [.metadata.namespace, .metadata.name, (.metadata.labels["app.kubernetes.io/version"] // "-")] | @tsv' | sort > "$E/tekton.txt"
kubectl get cm chains-config -n tekton-pipelines -o yaml > "$E/chains-config.yaml" 2>&1 || true

nc=$(wc -l < "$E/composants.txt")
ns=$(cut -f1 "$E/images-spec.tsv" | grep -vcx kube-system || true)
nt=$(awk -F'\t' '$1 != "kube-system" && $1 != "local-path-storage"' "$E/images-sans-digest.tsv" | wc -l)
pods=$(awk 'NR > 1' "$E/pods.txt" | wc -l)
pas_prets=$(awk 'NR > 1 && $4 != "Running" && $4 != "Completed"' "$E/pods.txt" | wc -l)
echo "état « $1 » : $pods pods ($pas_prets ni Running ni Completed), $nc composants (A-5), $ns images hors kube-system dont $nt sans digest, mémoire du nœud $(cut -f2 "$E/memoire.txt")" | tee "$E/resume.txt"
