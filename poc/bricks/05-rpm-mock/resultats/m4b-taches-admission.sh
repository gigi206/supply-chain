#!/usr/bin/env bash
# Brique 05, M4b, préparation de l'étape taches (18/11/2026, accord permanent du 18/11) : admission des gabarits rendus, en dry-run
# serveur dans builds (kubectl create --dry-run=server : rien n'est créé). Trois cas : tâche prefetch-rpm rendue, pipeline
# prefetch-rpm-sample-app rendue (références des tâches factices), et un témoin : la tâche rendue avec computeResources (nom du
# champ en v1) au lieu de resources (nom en v1beta1) dans le pas. But : savoir si le dry-run contrôle le nom du champ des
# ressources, avant d'en faire une assertion de l'étape. Les fonctions remplacer et rendre_taches et les variables qu'elles lisent
# sont reprises telles quelles de m4b.sh.
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/resultats/m4b-taches-admission.sh
export LC_ALL=C DISTRO=${DISTRO:-rke2}
. poc/bricks/08-trust-plane/commun.sh > /dev/null 2>&1   # chargé avant set -eu (sortie silencieuse sinon)
set -euo pipefail
h05=$repo/poc/bricks/05-rpm-mock
M=$h05/m4b.sh
R=$h05/resultats
T=$W/m4b-05/admission
rm -rf -- "${T:?}"; mkdir -p "$T"
eval "$(grep -E '^(VERROU_SRC|FP_ROCKY|LISTE|IMAGE|REPOMD_V2|TACHES|DEPOT_FERMETURE|FACTICE)=' "$M")"
eval "$(sed -n '/^remplacer() {/,/^}/p; /^rendre_taches() {/,/^}/p' "$M")"
echo "# m4b-taches-admission.sh, début $(date -u +%FT%TZ) ; m4b.sh $(sha256sum < "$M" | cut -c1-64)"
echo "# kubectl client $(kubectl version --client -o json | jq -r .clientVersion.gitVersion) ; serveur $(kubectl version -o json < /dev/null | jq -r .serverVersion.gitVersion)"
src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$VERROU_SRC")
rendre_taches "$REG/tekton/tasks/prefetch-rpm@$FACTICE" "$REG/tekton/tasks/publier-fermeture@$FACTICE" "$src" "$dos"
yq '.spec.steps[0].computeResources = .spec.steps[0].resources | del(.spec.steps[0].resources)' "$T/prefetch-rpm.yaml" > "$T/temoin-v1beta1.yaml"
echo "témoin : clés du pas $(yq -o=json -I=0 '.spec.steps[0] | keys' "$T/temoin-v1beta1.yaml")"
for f in prefetch-rpm.yaml prefetch-rpm-sample-app.yaml temoin-v1beta1.yaml; do
  rc=0; kubectl create --dry-run=server -n builds -f "$T/$f" < /dev/null > "$T/$f.out" 2>&1 || rc=$?
  echo "$f : code $rc ; $(head -c 400 "$T/$f.out" | tr '\n' ' ')"
done
rc=0; kubectl get tasks.tekton.dev,pipelines.tekton.dev -n builds -o name < /dev/null > "$T/objets.txt" 2>&1 || rc=$?
echo "tâches et pipelines dans builds après les dry-runs : code $rc ; $(grep -c . "$T/objets.txt" || true) ligne(s) : $(head -c 200 "$T/objets.txt" | tr '\n' ' ')"
echo "# fin $(date -u +%FT%TZ)"
