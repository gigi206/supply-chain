#!/usr/bin/env bash
# Brique 08c : relevé à sec de l'étape controleurs de preuves.sh sous H1 à H5, sans la rejouer. Rien n'est créé : lectures, can-i et
# dry-run serveur seulement, y compris pour les essais que preuves.sh lance pour de bon. L'espace d'essai et ses liaisons temporaires
# ne sont pas créés : la seconde barrière est mesurée dans bancc avec --as-group system:masters (droits contournés, la règle juge le
# nom du compte). Continue après un écart, pour tous les lister. Refuse si le journal existe déjà.
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/08c-durcissement/essais-h5-controleurs.sh   (journal : resultats/durcissement-h5_controleurs_sec.log)
set -uo pipefail
export LC_ALL=C
d8c=$(cd "$(dirname "$0")" && pwd)
JOURNAL=${JOURNAL:-$d8c/resultats/durcissement-h5_controleurs_sec.log}
[ ! -e "$JOURNAL" ] || { echo "$JOURNAL existe déjà, rien relevé"; exit 2; }
here=$d8c/../08-trust-plane
. "$here/commun.sh"
T=$HOME/.cache/supply-chain-poc/08c-sec-controleurs
mkdir -p "$T"
trap 'rm -rf "${T:?}"' EXIT
exec > >(sed -u "s#$HOME#~#g" | tee "$JOURNAL") 2>&1

CONTROLEUR=system:serviceaccount:tekton-pipelines:tekton-pipelines-controller
CHAINS=system:serviceaccount:tekton-chains:tekton-chains-controller
REGLE_CTRL=tekton-controleurs-builds
RBAC_REFUS='is forbidden: User "system:serviceaccount:[^"]*" cannot '
REGLE_REFUS="ValidatingAdmissionPolicy '$REGLE_CTRL'"
BUSYBOX=sc-stockage.poc.test:5000/amont/rancher/mirrored-library-busybox@sha256:ad9fa4d07136a83e69a54ef00102f579d04eba431932de3b0f098cc5d5948f9f
ecarts=0
ko() { echo "KO   $*"; ecarts=$((ecarts + 1)); }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || ko "$1 : $2 (attendu : $3)"; }
refuse() { # motif libellé commande… : mêmes essais que preuves.sh, en dry-run serveur
  local m=$1 l=$2
  shift 2
  if "$@" > "$T/sortie" 2>&1; then ko "$l : admis"
  elif grep -qE "$m" "$T/sortie"; then echo "OK   $l : refusé ($(tr '\n' ' ' < "$T/sortie" | sed 's/^Error from server ([A-Za-z]*): //; s/^error when creating "[^"]*": //' | cut -c1-190))"
  else ko "$l : refusé pour un autre motif ($(tr '\n' ' ' < "$T/sortie" | cut -c1-200))"
  fi
}
hc_pod() { # compte-du-pod fichier : même pod que preuves.sh
  jq -n --arg sa "$1" --arg img "$(kubectl get ds -n kube-system cilium -o jsonpath='{.spec.template.spec.containers[0].image}')" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: "preuve-helm-cilium", namespace: "kube-system"},
    spec: {serviceAccountName: $sa, restartPolicy: "Never",
      securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "c", image: $img, command: ["true"],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}}' > "$2"
}
refus_journal() { # espace/déploiement : lignes de refus des droits dans le journal du contrôleur, sans écarter les watch de démarrage de kube-apiserver
  kubectl logs -n "${1%/*}" "deploy/${1#*/}" | { grep -c 'is forbidden: User' || true; }
}

echo "# essais-h5-controleurs.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), DISTRO=$DISTRO"
echo "Prédiction (écrite le 06/11/2026 à 22:31 UTC, avant ce relevé) :"
echo "- règle et liaison présentes ; droits de locataire bornés à builds ; can-i et essais au nom des contrôleurs refusés par les droits"
echo "- seconde barrière : pod de bancc refusé par la règle au nom des deux contrôleurs, droits contournés ; même pod admis pour l'administrateur"
echo "- témoins : pod et StatefulSet de kube-system admis pour l'administrateur ; 6 créateurs de pods de kube-system, chacun admis"
echo "- audit : 0 refus de la règle dans builds, au moins un pod créé dans builds, lectures de Secrets dans builds seulement"
echo "- écarts redoutés, non vérifiés avant ce relevé : arguments de Chains changés par S1 ; redémarrages non nuls après les retouches"
echo "  de H4 et S1 ; lecture de Secret hors de builds par Chains ; compte des créateurs changé par h5_roles"

echo "## règle"
attendu "ValidatingAdmissionPolicy $REGLE_CTRL (failurePolicy, à jour, avertissements de typage)" \
  "$(kubectl get validatingadmissionpolicy "$REGLE_CTRL" -o json | jq -r '"\(.spec.failurePolicy) \(.status.observedGeneration == .metadata.generation) \((.status.typeChecking.expressionWarnings // []) | length)"')" "Fail true 0"
attendu "liaison $REGLE_CTRL" "$(kubectl get validatingadmissionpolicybinding "$REGLE_CTRL" -o json | jq -r '"\(.spec.policyName) \(.spec.validationActions | join(","))"')" "$REGLE_CTRL Deny"
t0=$(kubectl get validatingadmissionpolicy "$REGLE_CTRL" -o jsonpath='{.metadata.creationTimestamp}')
echo "posée le $t0"
for u in "$CONTROLEUR" "$CHAINS"; do
  attendu "${u##*:} : create, update, patch, delete sur la règle et sa liaison" "$(for v in create update patch delete; do
    for r in validatingadmissionpolicies validatingadmissionpolicybindings; do kubectl auth can-i "$v" "$r.admissionregistration.k8s.io" --as "$u" 2>/dev/null || true; done
  done | sort -u | paste -sd,)" no
done

echo "## droits"
for c in tekton-pipelines-controller-tenant-access tekton-chains-controller-tenant-access; do
  attendu "ClusterRoleBinding $c introuvable (NotFound)" "$(kubectl get clusterrolebinding "$c" 2>&1 | grep -c NotFound || true)" 1
  attendu "RoleBinding builds/$c → ClusterRole" "$(kubectl get rolebinding -n builds "$c" -o jsonpath='{.roleRef.kind}/{.roleRef.name}')" "ClusterRole/$c"
done
attendu "Role tekton-chains/tekton-chains-controller-config (ConfigMaps)" \
  "$(kubectl get role -n tekton-chains tekton-chains-controller-config -o json | jq -c '[.rules[] | "\(.resources | join(",")):\(.verbs | join(","))"]')" '["configmaps:get,list,watch"]'
attendu "argument de namespace du contrôleur de Pipelines" \
  "$(kubectl get deploy -n tekton-pipelines tekton-pipelines-controller -o json | jq -r '.spec.template.spec.containers[0].args | map(select(startswith("-namespace"))) | join(",")')" "-namespace=builds"
attendu "arguments de Chains" "$(kubectl get deploy -n tekton-chains tekton-chains-controller -o json | jq -r '.spec.template.spec.containers[0].args | join(",")')" "--namespace=builds"
for u in "$CONTROLEUR" "$CHAINS"; do
  attendu "${u##*:} : can-i list secrets (tout le cluster, builds, kube-system), create pods (kube-system, builds)" "$( {
    kubectl auth can-i list secrets -A --as "$u" 2>/dev/null || true; kubectl auth can-i list secrets -n builds --as "$u" 2>/dev/null || true
    kubectl auth can-i list secrets -n kube-system --as "$u" 2>/dev/null || true; kubectl auth can-i create pods -n kube-system --as "$u" 2>/dev/null || true
    kubectl auth can-i create pods -n builds --as "$u" 2>/dev/null || true; } | paste -sd,)" "no,yes,no,no,yes"
done

echo "## essais au nom des contrôleurs, en dry-run serveur (preuves.sh les lance pour de bon)"
hc_pod clusterrole-aggregation-controller "$T/ct-pod.json"
jq '.metadata.name = "preuve-controleurs"' "$T/ct-pod.json" > "$T/ct-pod-ks.json"
jq '.metadata = {name: "preuve-controleurs", namespace: "tekton-chains"} | .spec.serviceAccountName = "tekton-chains-controller"' "$T/ct-pod.json" > "$T/ct-pod-chains.json"
jq '{apiVersion: "apps/v1", kind: "StatefulSet", metadata: {name: "preuve-controleurs", namespace: "kube-system"},
  spec: {replicas: 0, serviceName: "preuve-controleurs", selector: {matchLabels: {app: "preuve-controleurs"}},
    template: {metadata: {labels: {app: "preuve-controleurs"}}, spec: (.spec | del(.restartPolicy))}}}' "$T/ct-pod.json" > "$T/ct-sts.json"
jq -n '{apiVersion: "v1", kind: "PersistentVolumeClaim", metadata: {name: "preuve-controleurs", namespace: "kube-system"},
  spec: {accessModes: ["ReadWriteOnce"], storageClassName: "local-path", resources: {requests: {storage: "1Mi"}}}}' > "$T/ct-pvc.json"
lp=$(kubectl get pods -n "$D_LP_NS" -l app=local-path-provisioner -o jsonpath='{.items[0].metadata.name}')
img=$(jq -r '.spec.containers[0].image' "$T/ct-pod.json")
for u in "$CONTROLEUR" "$CHAINS"; do
  n=${u##*:}
  refuse "$RBAC_REFUS" "$n : pod de kube-system portant clusterrole-aggregation-controller" kubectl create --dry-run=server --as "$u" -f "$T/ct-pod-ks.json"
  refuse "$RBAC_REFUS" "$n : StatefulSet de kube-system" kubectl create --dry-run=server --as "$u" -f "$T/ct-sts.json"
  refuse "$RBAC_REFUS" "$n : PVC de kube-system" kubectl create --dry-run=server --as "$u" -f "$T/ct-pvc.json"
  refuse "$RBAC_REFUS" "$n : annotation du pod $lp" kubectl annotate --dry-run=server --as "$u" pod -n "$D_LP_NS" "$lp" preuve-controleurs=1
  refuse "$RBAC_REFUS" "$n : image du pod $lp remplacée" kubectl patch --as "$u" pod -n "$D_LP_NS" "$lp" --dry-run=server \
    --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/containers/0/image\",\"value\":\"$img\"}]"
  refuse "$RBAC_REFUS" "$n : annotation du StatefulSet openbao" kubectl annotate --dry-run=server --as "$u" statefulset -n openbao openbao preuve-controleurs=1
  refuse "$RBAC_REFUS" "$n : pod de tekton-chains portant tekton-chains-controller" kubectl create --dry-run=server --as "$u" -f "$T/ct-pod-chains.json"
  refuse "$RBAC_REFUS" "$n : lecture du Secret kube-system/$D_SERVING" kubectl get secret -n kube-system "$D_SERVING" --as "$u" -o name
  refuse "$RBAC_REFUS" "$n : liste des Secrets d'openbao" kubectl get secrets -n openbao --as "$u" -o name
  refuse "$RBAC_REFUS" "$n : lecture du Secret tekton-chains/zot-chains" kubectl get secret -n tekton-chains zot-chains --as "$u" -o name
done

echo "## règle en seconde barrière : dry-run dans bancc, droits contournés par --as-group system:masters, espace d'essai non créé"
hc_pod default "$T/ct-pod-default.json"
jq --arg i "$BUSYBOX" '.metadata = {name: "preuve-controleurs", namespace: "bancc"} | .spec.automountServiceAccountToken = false
  | .spec.containers[0] += {image: $i, resources: {requests: {cpu: "10m", memory: "16Mi"}, limits: {cpu: "100m", memory: "64Mi"}}}' \
  "$T/ct-pod-default.json" > "$T/ct-pod-essai.json"
for u in "$CONTROLEUR" "$CHAINS"; do
  refuse "$REGLE_REFUS" "${u##*:} : pod de bancc" kubectl create --dry-run=server --as "$u" --as-group system:masters -f "$T/ct-pod-essai.json"
done
kubectl create --dry-run=server -f "$T/ct-pod-essai.json" >/dev/null 2>"$T/sortie" && echo "OK   témoin : même pod admis au nom de l'administrateur" \
  || ko "témoin administrateur refusé dans bancc ($(tr '\n' ' ' < "$T/sortie" | cut -c1-200))"
kubectl create namespace preuve-controleurs --dry-run=server >/dev/null 2>"$T/sortie" && echo "OK   espace preuve-controleurs admis" \
  || ko "espace preuve-controleurs refusé ($(tr '\n' ' ' < "$T/sortie" | cut -c1-200))"
attendu "espace preuve-controleurs introuvable (NotFound)" "$(kubectl get namespace preuve-controleurs 2>&1 | grep -c NotFound || true)" 1

echo "## témoins"
kubectl create --dry-run=server -f "$T/ct-pod-ks.json" >/dev/null 2>"$T/sortie" && echo "OK   administrateur : pod de kube-system admis" \
  || ko "administrateur : pod refusé ($(tr '\n' ' ' < "$T/sortie" | cut -c1-200))"
kubectl create --dry-run=server -f "$T/ct-sts.json" >/dev/null 2>"$T/sortie" && echo "OK   administrateur : StatefulSet admis" \
  || ko "administrateur : StatefulSet refusé ($(tr '\n' ' ' < "$T/sortie" | cut -c1-200))"
n=0
kubectl get sa -A -o jsonpath='{range .items[*]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}' > "$T/ct-comptes"
while IFS=: read -r ns sa; do
  u=system:serviceaccount:$ns:$sa
  [ "$(kubectl auth can-i create pods -n kube-system --as "$u" 2>/dev/null </dev/null || true)" = yes ] || continue
  n=$((n + 1))
  kubectl create --as "$u" --dry-run=server -f "$T/ct-pod-default.json" >/dev/null 2>"$T/sortie" </dev/null && echo "OK   $sa : pod default de kube-system admis" \
    || ko "$sa : pod default refusé ($(tr '\n' ' ' < "$T/sortie" | cut -c1-200))"
done < "$T/ct-comptes"
attendu "comptes de service qui peuvent créer des pods dans kube-system" "$n" "$D_KS_CREATEURS"

echo "## audit de l'API (fichiers gardés sur sc-confiance)"
audit_api "$REGLE_CTRL" > "$T/ct-refus-audit.json"
jq -r 'select(.stage == "ResponseComplete" and .responseStatus.code >= 400) | "  \(.objectRef.namespace) \((.impersonatedUser.username // .user.username) | split(":") | last) \(.verb) \(.objectRef.resource)"' "$T/ct-refus-audit.json" | sort | uniq -c
attendu "refus de la règle dans builds" "$(jq -s '[.[] | select(.stage == "ResponseComplete" and .responseStatus.code >= 400 and .objectRef.namespace == "builds")] | length' "$T/ct-refus-audit.json")" 0
n=$(audit_api "$CONTROLEUR" | jq -s --arg t "$t0" --arg u "$CONTROLEUR" '[.[] | select(.stage == "ResponseComplete" and .user.username == $u
  and .verb == "create" and .objectRef.resource == "pods" and .objectRef.namespace == "builds" and .responseStatus.code == 201
  and .stageTimestamp[0:19] >= ($t[0:19]))] | length')
[ "$n" -ge 1 ] && echo "OK   pods créés dans builds par le contrôleur de Pipelines depuis la pose de la règle : $n" || ko "aucun pod créé dans builds depuis la pose de la règle"
{ audit_api tekton-pipelines-controller; audit_api tekton-chains-controller; } | jq -c 'select(.objectRef.resource == "secrets"
  and .impersonatedUser == null and (.user.username | test("^system:serviceaccount:tekton-(pipelines:tekton-pipelines|chains:tekton-chains)-controller$")))' \
  | sort -u > "$T/ct-secrets.json"
jq -r '"  \(.user.username | split(":") | last) \(.verb) \(.objectRef.namespace // "(tout le cluster)") \(.responseStatus.code) \(.stage)"' "$T/ct-secrets.json" | sort | uniq -c
attendu "lectures de Secrets du contrôleur de Pipelines dans builds (au moins une)" \
  "$(jq -s --arg u "$CONTROLEUR" '[.[] | select(.user.username == $u and .objectRef.namespace == "builds")] | length > 0' "$T/ct-secrets.json")" true
attendu "lectures de Secrets hors de builds ou refusées (403), par l'un ou l'autre" \
  "$(jq -s '[.[] | select(.objectRef.namespace != "builds" or .responseStatus.code == 403)] | length' "$T/ct-secrets.json")" 0

echo "## journaux des contrôleurs (depuis leur démarrage)"
for c in tekton-pipelines/tekton-pipelines-controller tekton-chains/tekton-chains-controller; do
  attendu "${c#*/} : pods sélectionnés par app=${c#*/}" "$(kubectl get pods -n "${c%/*}" -l "app=${c#*/}" -o name | wc -l)" 1
  attendu "${c#*/} : redémarrages" "$(kubectl get pods -n "${c%/*}" -l "app=${c#*/}" -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | sort -u | paste -sd,)" 0
  attendu "${c#*/} : refus des droits dans le journal, watch de démarrage compris" "$(refus_journal "$c")" 0
done

echo "## lecteurs des Secrets de kube-system"
while IFS=: read -r ns sa; do
  u=system:serviceaccount:$ns:$sa
  b=$(kubectl auth can-i list secrets -n kube-system --as "$u" 2>/dev/null </dev/null || true)
  if [ "$b" = yes ]; then echo "  $ns:$sa"; fi
done < "$T/ct-comptes" | tee "$T/ct-lecteurs"
echo "$(wc -l < "$T/ct-comptes") comptes de service examinés, $(wc -l < "$T/ct-lecteurs") lecteurs"
attendu "contrôleurs de Pipelines et de Chains parmi eux" "$(grep -cE 'tekton-(pipelines|chains)-controller$' "$T/ct-lecteurs" || true)" 0

echo "## bilan, $(date -u +%Y-%m-%dT%H:%M:%SZ) : $ecarts écart(s)"
[ "$ecarts" = 0 ]
