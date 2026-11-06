#!/usr/bin/env bash
# Brique 08c : relevé à sec de l'étape resolveurs de preuves.sh sous H1 à H5, sans la rejouer. Rien n'est créé : lectures, can-i et
# dry-run serveur seulement. L'espace d'essai et les résolutions réelles ne sont pas faits : leur admission est présentée à l'API, la
# résolution elle-même reste à mesurer. Continue après un écart, pour tous les lister. Refuse si le journal existe déjà.
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/08c-durcissement/essais-h5-resolveurs.sh   (journal : resultats/durcissement-h5_resolveurs_sec.log)
set -uo pipefail
export LC_ALL=C
d8c=$(cd "$(dirname "$0")" && pwd)
JOURNAL=${JOURNAL:-$d8c/resultats/durcissement-h5_resolveurs_sec.log}
[ ! -e "$JOURNAL" ] || { echo "$JOURNAL existe déjà, rien relevé"; exit 2; }
here=$d8c/../08-trust-plane
. "$here/commun.sh"
T=$HOME/.cache/supply-chain-poc/08c-sec-resolveurs
mkdir -p "$T"
trap 'rm -rf "${T:?}"' EXIT
exec > >(sed -u "s#$HOME#~#g" | tee "$JOURNAL") 2>&1

RESOLVEURS=system:serviceaccount:tekton-pipelines-resolvers:tekton-pipelines-resolvers
RBAC_REFUS='is forbidden: User "system:serviceaccount:[^"]*" cannot '
BUNDLE=sc-stockage.poc.test:5000/tekton/pipelines/sample-app@sha256:02c05736ea49fe3b2d7b8d105ddd75f5f0e9c55f00560b39710699d10bbe4d6e
H5_DENY=2026-11-06T19:26:00Z
ecarts=0
ko() { echo "KO   $*"; ecarts=$((ecarts + 1)); }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || ko "$1 : $2 (attendu : $3)"; }
refuse() { # libellé commande… : mêmes essais que preuves.sh, refus des droits attendu
  local l=$1
  shift
  if "$@" > "$T/sortie" 2>&1; then ko "$l : admis"
  elif grep -qE "$RBAC_REFUS" "$T/sortie"; then echo "OK   $l : refusé ($(tr '\n' ' ' < "$T/sortie" | sed 's/^Error from server ([A-Za-z]*): //' | cut -c1-170))"
  else ko "$l : refusé pour un autre motif ($(tr '\n' ' ' < "$T/sortie" | cut -c1-200))"
  fi
}
admis() { # libellé commande… : dry-run serveur attendu sans refus
  local l=$1
  shift
  if "$@" > "$T/sortie" 2>&1; then echo "OK   $l : admis ($(tr '\n' ' ' < "$T/sortie" | cut -c1-120))"
  else ko "$l : refusé ($(tr '\n' ' ' < "$T/sortie" | cut -c1-240))"
  fi
}
rr() { # nom paramètres-json : même objet que rr_essai de preuves.sh, dans builds
  jq -n --arg n "$1" --argjson p "$2" '{apiVersion: "resolution.tekton.dev/v1beta1", kind: "ResolutionRequest",
    metadata: {name: $n, namespace: "builds", labels: {"resolution.tekton.dev/type": "bundles"}}, spec: {params: $p}}' > "$T/$1.json"
}

echo "# essais-h5-resolveurs.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), DISTRO=$DISTRO"
echo "Prédiction (écrite le 06/11/2026 à 22:43 UTC, avant ce relevé, référence : resultats/preuves-resolveurs.log de 15:25 UTC, avant H1) :"
echo "- droits, can-i et lectures refusées : mêmes constats qu'à 15:25 ; lecture de tekton-chains/signing-secrets refusée aussi (ajoutée)"
echo "- rke2-serving et signing-secrets existent ; zot-chains absent depuis S1 : son refus reste mesuré, mais sur un objet absent"
echo "- bundle du gabarit inchangé ; Secret zot-images présent dans builds, compte default sans imagePullSecrets"
echo "- dry-run serveur : espace preuve-resolveurs admis ; deux ResolutionRequests admises dans builds, sans cache"
echo "- pod des résolveurs : prêt, 0 redémarrage, 0 refus des droits dans son journal ; aucune ResolutionRequest preuve-* restante"
echo "- audit : règle des résolveurs présente ; aucune lecture hors de builds sauf les deux refus (403) de 15:25 ; get secrets builds 200"
echo "  toujours 1, celle de 15:25, donc chemin du Secret sans passage sous H5 ; get serviceaccounts builds 200 depuis h5_deny : au moins 1,"
echo "  peu sûr (le résolveur peut servir un bundle par digest depuis son cache, non lu)"
echo "- lecteurs des Secrets de tout le cluster : 4, sans cilium-operator (h5_cilium) ; la valeur figée de preuves.sh en attend 5"
echo "- écart attendu, si l'étape était rejouée : KO sur sa dernière comparaison ; à corriger dans preuves.sh après ce relevé"

echo "## droits"
attendu "règles du ClusterRole des résolveurs sur secrets ou serviceaccounts" "$(kubectl get clusterrole tekton-pipelines-resolvers-resolution-request-updates -o json \
  | jq '[.rules[] | select(.resources | index("secrets") or index("serviceaccounts"))] | length')" 0
attendu "Role builds/tekton-pipelines-resolvers-lecture" "$(kubectl get role -n builds tekton-pipelines-resolvers-lecture -o json \
  | jq -c '[.rules[] | "\(.resources | join(",")):\(.verbs | join(","))"]')" '["secrets,serviceaccounts:get"]'
attendu "RoleBinding builds/tekton-pipelines-resolvers-lecture" "$(kubectl get rolebinding -n builds tekton-pipelines-resolvers-lecture -o json \
  | jq -r '"\(.roleRef.kind)/\(.roleRef.name) \(.subjects | map("\(.namespace):\(.name)") | join(","))"')" \
  "Role/tekton-pipelines-resolvers-lecture tekton-pipelines-resolvers:tekton-pipelines-resolvers"
attendu "can-i des résolveurs" "$( {
  kubectl auth can-i list secrets -A --as "$RESOLVEURS" 2>/dev/null || true; kubectl auth can-i get secrets -n builds --as "$RESOLVEURS" 2>/dev/null || true
  kubectl auth can-i get secrets -n kube-system --as "$RESOLVEURS" 2>/dev/null || true; kubectl auth can-i get serviceaccounts -n builds --as "$RESOLVEURS" 2>/dev/null || true
  kubectl auth can-i get serviceaccounts -n kube-system --as "$RESOLVEURS" 2>/dev/null || true
  kubectl auth can-i list resolutionrequests.resolution.tekton.dev -A --as "$RESOLVEURS" 2>/dev/null || true
  kubectl auth can-i get secrets -n tekton-pipelines-resolvers --as "$RESOLVEURS" 2>/dev/null || true; } | paste -sd,)" "no,yes,no,yes,no,yes,yes"

echo "## cibles (noms seulement)"
attendu "Secret kube-system/$D_SERVING" "$(kubectl get secret -n kube-system "$D_SERVING" -o name 2>&1)" "secret/$D_SERVING"
attendu "Secret tekton-chains/signing-secrets" "$(kubectl get secret -n tekton-chains signing-secrets -o name 2>&1)" secret/signing-secrets
attendu "Secret tekton-chains/zot-chains absent (NotFound)" "$(kubectl get secret -n tekton-chains zot-chains 2>&1 | grep -c NotFound || true)" 1
attendu "Secret builds/zot-images" "$(kubectl get secret -n builds zot-images -o name 2>&1)" secret/zot-images
attendu "compte builds/default : imagePullSecrets" "$(kubectl get sa -n builds default -o json | jq -c '.imagePullSecrets')" null

echo "## lectures réelles au nom des résolveurs"
refuse "lecture du Secret kube-system/$D_SERVING" kubectl get secret -n kube-system "$D_SERVING" --as "$RESOLVEURS" -o name
refuse "lecture du Secret tekton-chains/zot-chains (objet absent)" kubectl get secret -n tekton-chains zot-chains --as "$RESOLVEURS" -o name
refuse "lecture du Secret tekton-chains/signing-secrets" kubectl get secret -n tekton-chains signing-secrets --as "$RESOLVEURS" -o name
refuse "liste des Secrets d'openbao" kubectl get secrets -n openbao --as "$RESOLVEURS" -o name
refuse "lecture du compte de service kube-system/default" kubectl get serviceaccount -n kube-system default --as "$RESOLVEURS" -o name

echo "## admission (dry-run serveur, rien de créé, rien de résolu)"
p=$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -c '.spec.resourcetemplates[0].spec.pipelineRef.params + [{name: "cache", value: "never"}]')
attendu "bundle du gabarit" "$(jq -r '.[] | select(.name == "bundle") | .value' <<< "$p")" "$BUNDLE"
admis "espace preuve-resolveurs" kubectl create namespace preuve-resolveurs --dry-run=server -o name
rr preuve-resolveurs-compte "$p"
rr preuve-resolveurs-secret "$(jq -c '. + [{name: "serviceAccount", value: "no service account"}, {name: "secret", value: "zot-images"}]' <<< "$p")"
for n in preuve-resolveurs-compte preuve-resolveurs-secret; do
  admis "ResolutionRequest builds/$n" kubectl create --dry-run=server -f "$T/$n.json"
done

echo "## pod des résolveurs"
kubectl get pods -n tekton-pipelines-resolvers -o json | jq -r '.items[] | "\(.metadata.name) créé \(.metadata.creationTimestamp) prêt \(.status.conditions[] | select(.type == "Ready") | .status) redémarrages \([.status.containerStatuses[].restartCount] | add)"' > "$T/pods"
sed 's/^/  /' "$T/pods"
attendu "pods prêts sans redémarrage" "$(grep -c 'prêt True redémarrages 0$' "$T/pods" || true)/$(wc -l < "$T/pods")" 1/1
attendu "refus des droits dans le journal du pod" "$(kubectl logs -n tekton-pipelines-resolvers deploy/tekton-pipelines-remote-resolvers | { grep -c 'is forbidden: User' || true; })" 0
attendu "ResolutionRequests preuve-* dans builds" "$(kubectl get resolutionrequest -n builds -o name | { grep -c '/preuve-' || true; })" 0
attendu "espace preuve-resolveurs introuvable (NotFound)" "$(kubectl get namespace preuve-resolveurs 2>&1 | grep -c NotFound || true)" 1

echo "## audit de l'API (lectures de Secrets et de comptes de service des résolveurs ; sans --as)"
attendu "règle des résolveurs dans la politique d'audit du nœud" "$(sur sc-confiance "sudo grep -c 'serviceaccount:tekton-pipelines-resolvers:tekton-pipelines-resolvers' $D_CONF/audit-policy.yaml || true")" 1
audit_api tekton-pipelines-resolvers:tekton-pipelines-resolvers | jq -c --arg u "$RESOLVEURS" 'select(.user.username == $u and .impersonatedUser == null
  and (.objectRef.resource == "secrets" or .objectRef.resource == "serviceaccounts"))' | sort -u > "$T/audit.json"
jq -r '"  \(.verb) \(.objectRef.resource) \(.objectRef.namespace // "(tout le cluster)") \(.responseStatus.code) \(.stage)"' "$T/audit.json" | sort | uniq -c
echo "  première entrée gardée : $(jq -rs '[.[].requestReceivedTimestamp] | sort | .[0] // "aucune"' "$T/audit.json")"
echo "  dernière get secrets builds 200 : $(jq -rs '[.[] | select(.objectRef.resource == "secrets" and .objectRef.namespace == "builds" and .responseStatus.code < 400) | .requestReceivedTimestamp] | sort | .[-1] // "aucune"' "$T/audit.json")"
attendu "lectures hors de builds, sauf les refus (403) de preuve-resolveurs" "$(jq -s '[.[] | select(.objectRef.namespace != "builds"
  and (.objectRef.namespace != "preuve-resolveurs" or .responseStatus.code != 403))] | length' "$T/audit.json")" 0
attendu "get secrets builds 200" "$(jq -s '[.[] | select(.objectRef.resource == "secrets" and .objectRef.namespace == "builds" and .responseStatus.code < 400)] | length' "$T/audit.json")" 1
attendu "get serviceaccounts builds 200 depuis h5_deny, au moins une" "$(jq -s --arg t "$H5_DENY" '[.[] | select(.objectRef.resource == "serviceaccounts" and .objectRef.namespace == "builds"
  and .responseStatus.code < 400 and .requestReceivedTimestamp >= $t)] | length > 0' "$T/audit.json")" true

echo "## lecteurs des Secrets de tout le cluster"
while IFS=: read -r ns sa; do
  if [ "$(kubectl auth can-i list secrets -A --as "system:serviceaccount:$ns:$sa" 2>/dev/null || true)" = yes ]; then echo "$ns:$sa"; fi
done < <(kubectl get sa -A -o jsonpath='{range .items[*]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}') | sort > "$T/lecteurs"
sed 's/^/  /' "$T/lecteurs"
attendu "lecteurs" "$(paste -sd, "$T/lecteurs")" \
  "kube-system:generic-garbage-collector,kube-system:namespace-controller,kube-system:resourcequota-controller,tekton-pipelines:tekton-triggers-core-interceptors"
attendu "cilium-operator encore attendu par la valeur figée de preuves.sh" "$(grep -c '"kube-system:cilium-operator,kube-system:generic-garbage-collector' "$here/preuves.sh" || true)" 1

echo "## bilan : $ecarts écart(s)"
