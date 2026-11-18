#!/usr/bin/env bash
# Brique 05, M4b, préparation de l'étape rpm (18/11/2026, accord permanent du 18/11) : fonctions de relevé de etape_rpm (releve_pod,
# statut_pr, et les jq des TaskRuns et du PipelineRun), reprises telles quelles de m4b.sh, jouées sur de vrais objets de Tekton déjà
# présents dans builds (PipelineRun s4b-deb-1 de la 06, ses deux TaskRuns et leurs pods), en lecture seule. But : vérifier la forme
# réelle (conteneurs d'initialisation, place-scripts, ressources, résultats) avant une étape dont les écritures sont définitives.
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/resultats/m4b-rpm-releve-reel.sh
export LC_ALL=C DISTRO=${DISTRO:-rke2}
. poc/bricks/08-trust-plane/commun.sh > /dev/null 2>&1   # chargé avant set -eu (sortie silencieuse sinon)
set -euo pipefail
M=$repo/poc/bricks/05-rpm-mock/m4b.sh
T=$W/m4b-05/releve-reel
rm -rf -- "${T:?}"; mkdir -p "$T"
eval "$(grep -E '^ARGS_RECONSTRUIT=' "$M")"
eval "$(sed -n '/^statut_pr() {/,/^}/p; /^releve_pod() {/,/^}/p' "$M")"
echo "# m4b-rpm-releve-reel.sh, début $(date -u +%FT%TZ) ; m4b.sh $(sha256sum < "$M" | cut -c1-64)"
pr=s4b-deb-1
echo "PipelineRun $pr : « $(statut_pr "$pr") »"
kubectl get pipelinerun -n builds "$pr" -o json < /dev/null \
  | jq -r '"début \(.status.startTime // "-") ; fin \(.status.completionTime // "-")"' | sed 's/^/     /'
for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
  kubectl get taskrun -n builds "$t" -o json < /dev/null > "$T/tr-$t.json"
  p=$(jq -r '.status.podName // ""' "$T/tr-$t.json")
  echo "### TaskRun $t : $(jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "-")|\(.reason // "-")"' "$T/tr-$t.json") ; début $(jq -r '.status.startTime // "-"' "$T/tr-$t.json") ; fin $(jq -r '.status.completionTime // "-"' "$T/tr-$t.json")"
  jq -r '.status.results[]? | "     résultat \(.name) : \(.value | if type == "string" then . else tojson end)"' "$T/tr-$t.json"
  [ -n "$p" ] || { echo "     aucun pod"; continue; }
  releve_pod "$p"
  echo "     conteneurs de pas : $(jq -r '[.spec.containers[].name] | join(" ")' "$T/pod-$p.json")"
done
jq -r '.status.results[]? | "résultat de \(.name) : \(.value)"' <(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null)
echo "# fin $(date -u +%FT%TZ)"
