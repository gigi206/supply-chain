#!/usr/bin/env bash
# Brique 08b : builds entre J4 et J6 sous RKE2, mesuré à sec sur le cluster k3s en service. Sous k3s, builds n'a aucun label jusqu'à
# politique.sh restreint (J6), donc privileged ; sous le profil cis, le défaut y est restricted dès sa création, avec
# set-security-context encore à faux. Les pods réels de J4, restés Completed dans builds, sont présentés à builds, aujourd'hui en
# enforce=restricted. Tout passe par --dry-run=server : rien n'est créé ni modifié.
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08b-rke2/releve-builds-j4.sh   (journal : resultats/releve-builds-j4.log)
set -euo pipefail
export LC_ALL=C
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/supply-chain-poc.yaml}

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
P08=$here/../08-trust-plane
T=$(umask 077 && mktemp -d "$HOME/.cache/supply-chain-poc/08b/builds-j4.XXXXXX")
nettoyer() { rm -rf -- "${T:?}"; }
trap nettoyer EXIT

essai() { # libellé fichier : décision de l'API, à sec
  local o
  if o=$(kubectl create --dry-run=server -f "$2" 2>&1 </dev/null); then echo "ADMIS    $1"
  else echo "REFUSÉ   $1"; echo "$o" | sed 's/^/         /' | cut -c1-420; fi
}

presenter() { # pod nom-d'essai : spec du pod réel, sans son placement ni son propriétaire
  kubectl get pod -n builds "$1" -o json </dev/null \
    | jq --arg n "$2" '{apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: .metadata.labels}, spec: (.spec | del(.nodeName))}'
}

contextes() { # fichier : securityContext du pod et de chaque conteneur
  jq -r '"  pod : \(.spec.securityContext | tostring)",
    ((.spec.initContainers // []) + .spec.containers | .[] | "  \(.name) : \(.securityContext // {} | tostring)")' "$1"
}

releve() {
  date -u '+relevé du %d/%m/%Y à %H:%M UTC, à sec, cluster k3s en service'
  echo "serveur : $(kubectl version -o json </dev/null | jq -r .serverVersion.gitVersion)"

  echo; echo "## 1. Qui pose le label enforce de builds"
  echo "labels déclarés par tekton/builds.yaml : $(grep -c 'pod-security' "$P08/tekton/builds.yaml" || true)"
  grep -n 'label.*builds.*pod-security.kubernetes.io/enforce' "$P08"/*.sh | sed "s#$P08/##" | cut -c1-150
  echo "enforce de builds aujourd'hui : $(kubectl get ns builds -o json </dev/null | jq -r '.metadata.labels["pod-security.kubernetes.io/enforce"]')"
  echo "set-security-context aujourd'hui : $(kubectl get configmap feature-flags -n tekton-pipelines -o jsonpath='{.data.set-security-context}' </dev/null)"
  echo "défaut prévu sous RKE2 : $(grep -E '^ +enforce:' "$here/config/pod-security.yaml" | tr -d ' ')"

  echo; echo "## 2. Pod réel de J4, TaskRun essai-signature, créé avant le drapeau"
  kubectl get pod -n builds essai-signature-pod -o json </dev/null | jq -r '"créé le \(.metadata.creationTimestamp), phase \(.status.phase)"'
  presenter essai-signature-pod essai-j4 > "$T/j4.json"
  contextes "$T/j4.json"
  essai "pod de J4 tel qu'il a tourné" "$T/j4.json"

  echo; echo "## 3. Même pod, securityContext posé par set-security-context sur les conteneurs de Tekton seuls"
  jq '.spec.initContainers |= map(.securityContext = {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}, runAsNonRoot: true, seccompProfile: {type: "RuntimeDefault"}})' \
    "$T/j4.json" > "$T/j4-drapeau.json"
  essai "pod de J4, conteneurs d'initialisation réglés" "$T/j4-drapeau.json"
  jq '.spec.containers |= map(.securityContext = {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}})' "$T/j4-drapeau.json" > "$T/j4-conforme.json"
  essai "pod de J4, étape réglée aussi" "$T/j4-conforme.json"

  echo; echo "## 4. Tâches de J4 et J5 : securityContext déclaré"
  grep -n -A4 'securityContext' "$P08/tekton/essai-signature.yaml" "$P08/tekton/webhook.yaml" | sed "s#$P08/##" | cut -c1-120

  echo; echo "## 5. Autres pods de builds encore présents, sans réglage sur leurs conteneurs d'initialisation"
  kubectl get pods -n builds -o json </dev/null \
    | jq -r '.items[] | select(any((.spec.initContainers // [])[]; .securityContext.allowPrivilegeEscalation != false)) | "\(.metadata.creationTimestamp) \(.metadata.name)"' \
    | sort | tee "$T/sans" | head -n 12
  echo "total : $(wc -l < "$T/sans")"

  echo; echo "## 6. Retrait du label sous RKE2 : politique.sh, cas sous warn et audit"
  grep -n -E 'enforce levé|enforce- ' "$P08/politique.sh" | sed 's/^/  /' | cut -c1-170
  echo "autres retraits du label dans les scripts de la 08 : $(grep -l 'enforce- ' "$P08"/*.sh | grep -vc 'politique.sh' || true)"

  echo; echo "## 7. CronJob et Job du cluster, hors des espaces restricted : gabarits non vus par un relevé de pods"
  while read -r e; do
    kubectl get cronjob,job -n "$e" -o name </dev/null 2>/dev/null | sed "s#^#$e : #"
  done < <(kubectl get ns -o json </dev/null | jq -r '.items[] | select(.metadata.labels["pod-security.kubernetes.io/enforce"] == null) | .metadata.name') | tee "$T/jobs"
  echo "total : $(wc -l < "$T/jobs")"

  echo; echo "## 8. Label posé sans --overwrite sur un espace déjà en restricted, à sec : ce que verrait un tekton.sh rejoué après J6"
  rc=0; o=$(kubectl label --dry-run=server ns builds pod-security.kubernetes.io/enforce=privileged </dev/null 2>&1) || rc=$?
  echo "$o" | cut -c1-160; echo "code $rc"
  echo "enforce de builds après l'essai : $(kubectl get ns builds -o json </dev/null | jq -r '.metadata.labels["pod-security.kubernetes.io/enforce"]')"
}

releve 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/releve-builds-j4.log"
