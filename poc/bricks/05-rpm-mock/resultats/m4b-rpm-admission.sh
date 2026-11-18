#!/usr/bin/env bash
# Brique 05, M4b, préparation de l'étape rpm (18/11/2026, accord permanent du 18/11) : PipelineRun m4b-rpm-1 rendu par la fonction
# pr_rpm de m4b.sh (reprise telle quelle), admis en dry-run serveur dans builds (kubectl create --dry-run=server : rien n'est
# créé ; ni résolveur, ni vérification des signatures, ni pods). Puis : aucun PipelineRun m4b-rpm-* dans builds, dépôt de la
# fermeture absent de Zot (lecture anonyme), pipeline relue au tag m4b.
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/resultats/m4b-rpm-admission.sh
export LC_ALL=C DISTRO=${DISTRO:-rke2}
. poc/bricks/08-trust-plane/commun.sh > /dev/null 2>&1   # chargé avant set -eu (sortie silencieuse sinon)
set -euo pipefail
M=$repo/poc/bricks/05-rpm-mock/m4b.sh
T=$W/m4b-05/admission-rpm
rm -rf -- "${T:?}"; mkdir -p "$T"
eval "$(grep -E '^PIPELINE_REF=' "$M")"
eval "$(sed -n '/^pr_rpm() {/,/^}/p' "$M")"
echo "# m4b-rpm-admission.sh, début $(date -u +%FT%TZ) ; m4b.sh $(sha256sum < "$M" | cut -c1-64)"
pr_rpm m4b-rpm-1
echo "PipelineRun rendu : $(jq -c '{name: .metadata.name, bundle: .spec.pipelineRef.params[0].value, podTemplate: .spec.taskRunTemplate.podTemplate, ws: .spec.workspaces[0].volumeClaimTemplate.spec.resources}' "$T/pr-m4b-rpm-1.json")"
rc=0; kubectl create --dry-run=server -n builds -f "$T/pr-m4b-rpm-1.json" < /dev/null > "$T/admission.out" 2>&1 || rc=$?
echo "dry-run serveur : code $rc ; $(head -c 300 "$T/admission.out" | tr '\n' ' ')"
rc=0; kubectl get pipelinerun -n builds -o name < /dev/null > "$T/pr.txt" 2>&1 || rc=$?
echo "PipelineRuns de builds : code $rc ; $(grep -c . "$T/pr.txt" || true) au total, dont m4b-rpm-* : $(grep -c 'm4b-rpm-' "$T/pr.txt" || true)"
r=$(oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/builds/fermetures/sample-app-rpm" < /dev/null 2>&1 || true)
echo "dépôt builds/fermetures/sample-app-rpm : $(grep -c 'name unknown' <<< "$r") ligne « name unknown »"
echo "pipeline au tag m4b : $(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/tekton/pipelines/prefetch-rpm-sample-app:m4b" < /dev/null | jq -r .digest) (attendu ${PIPELINE_REF##*@})"
echo "# fin $(date -u +%FT%TZ)"
