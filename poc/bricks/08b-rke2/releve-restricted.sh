#!/usr/bin/env bash
# Brique 08b : ce que le défaut restricted du profil cis et Kyverno refuseraient sous RKE2, mesuré à sec sur le cluster k3s en service.
# Tout passe par --dry-run=server : rien n'est créé ni modifié. Sous k3s, le défaut de Pod Security est privileged : les pods sont donc
# présentés à des espaces déjà en enforce=restricted, et bancc, sans label, sert à lire Kyverno seul.
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08b-rke2/releve-restricted.sh   (journal : resultats/releve-restricted.log)
set -euo pipefail
export LC_ALL=C
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/supply-chain-poc.yaml}

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
LP_TAG=v0.0.37
APP=sc-stockage.poc.test:5000/workspace/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
BUSYBOX=docker.io/rancher/mirrored-library-busybox:1.37.0
T=$(umask 077 && mktemp -d "$HOME/.cache/supply-chain-poc/08b/restricted.XXXXXX")
nettoyer() { rm -rf -- "${T:?}"; }
trap nettoyer EXIT

essai() { # libellé fichier : décision de l'API, à sec
  local o
  if o=$(kubectl apply --dry-run=server -f "$2" 2>&1 </dev/null); then echo "ADMIS    $1"
  else echo "REFUSÉ   $1"; echo "$o" | sed 's/^/         /' | cut -c1-320; fi
}

pod() { # nom espace : pod JSON sur l'entrée standard, spec seule
  jq --arg n "$1" --arg e "$2" '{apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: $e}, spec: .}'
}

releve() {
  date -u '+relevé du %d/%m/%Y à %H:%M UTC, à sec, cluster k3s en service'
  echo "serveur : $(kubectl version -o json </dev/null | jq -r .serverVersion.gitVersion)"

  echo; echo "## 1. Espaces sans label enforce : pods existants face à enforce=restricted"
  while read -r e; do
    case $e in kube-system|kube-public|kube-node-lease) continue ;; esac
    o=$(kubectl label --dry-run=server --overwrite ns "$e" pod-security.kubernetes.io/enforce=restricted 2>&1 </dev/null | grep '^Warning' || true)
    echo "$e : $(kubectl get pods -n "$e" --no-headers </dev/null 2>/dev/null | wc -l) pod(s), ${o:-conformes}" | cut -c1-260
  done < <(kubectl get ns -o json </dev/null | jq -r '.items[] | select(.metadata.labels["pod-security.kubernetes.io/enforce"] == null) | .metadata.name')

  echo; echo "## 2. Ordre d'admission : le gabarit du banc C, sans securityContext ni nodeSelector, dans porte (restricted, zone-confiance)"
  echo "Kyverno le refuserait aussi (nodeSelector absent) : le message dit qui parle le premier."
  sed -e "s|__CASE__|essai-ordre|; s|__REF__|$APP|; s|namespace: default|namespace: porte|" \
    "$here/../../benchmarks/kyverno-seul/kyverno/pod.tmpl.yaml" > "$T/ordre.yaml"
  essai "gabarit du banc C dans porte" "$T/ordre.yaml"

  echo; echo "## 3. Pods de j2-essais (stockage.sh), présentés à builds (restricted)"
  jq -n --arg i "$APP" '{nodeSelector: {zone: "build"}, automountServiceAccountToken: false,
    tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
    containers: [{name: "app", image: $i, securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}' \
    | pod essai-j2 builds > "$T/j2.json"
  essai "sample-app de j2-essais, securityContext actuel" "$T/j2.json"
  jq '.spec.securityContext = {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}}' "$T/j2.json" > "$T/j2-conforme.json"
  essai "sample-app de j2-essais, runAsNonRoot et seccomp ajoutés" "$T/j2-conforme.json"

  echo; echo "## 4. Pod auxiliaire de local-path hors de kube-system : bancc, sans label, donc Kyverno seul"
  echo "Sous k3s ce pod tourne dans kube-system, exclu des webhooks ; D2 (a) le place dans local-path-storage, qui ne l'est pas."
  echo "Webhooks de Kyverno, espaces exclus : $(kubectl get cm -n kyverno kyverno -o json </dev/null | jq -c '[.data.webhooks | fromjson | .namespaceSelector.matchExpressions[].values[]]')"
  echo "provisioner.go au tag $LP_TAG :"
  curl -fsSL --max-time 30 "https://raw.githubusercontent.com/rancher/local-path-provisioner/$LP_TAG/provisioner.go" > "$T/provisioner.go"
  grep -n -E 'HostPath: *&|VolumeSource\{$|Privileged|func \(p \*LocalPathProvisioner\) createHelperPod' "$T/provisioner.go" | cut -c1-110 | sed 's/^/  /'
  jq -n --arg i "$BUSYBOX" '{restartPolicy: "Never", containers: [{name: "helper-pod", image: $i, command: ["sh", "-c", "true"],
    volumeMounts: [{name: "data", mountPath: "/data"}]}],
    volumes: [{name: "data", hostPath: {path: "/var/lib/rancher/rke2/storage", type: "DirectoryOrCreate"}}]}' | pod essai-lp bancc > "$T/lp.json"
  essai "pod à hostPath dans bancc" "$T/lp.json"
  jq '.spec.volumes = [{name: "data", emptyDir: {}}]' "$T/lp.json" > "$T/lp-temoin.json"
  essai "témoin : même pod, emptyDir à la place du hostPath" "$T/lp-temoin.json"

  echo; echo "## 5. Contrôleur de Chains présenté à scan (restricted, zone-confiance), compte default"
  kubectl get deploy -n tekton-chains tekton-chains-controller -o json </dev/null \
    | jq '.spec.template.spec | del(.serviceAccountName, .serviceAccount) | {apiVersion: "v1", kind: "Pod", metadata: {name: "essai-chains", namespace: "scan"}, spec: .}' > "$T/chains.json"
  essai "Chains, securityContext actuel" "$T/chains.json"
  jq '.spec.securityContext = {runAsNonRoot: true, seccompProfile: {type: "RuntimeDefault"}}
    | .spec.containers |= map(.securityContext.capabilities = {drop: ["ALL"]})
    | .spec.initContainers |= (if . == null then null else map(.securityContext.capabilities = {drop: ["ALL"]}) end)
    | if .spec.initContainers == null then del(.spec.initContainers) else . end' "$T/chains.json" > "$T/chains-conforme.json"
  essai "Chains, runAsNonRoot, seccomp et capabilities drop ALL ajoutés" "$T/chains-conforme.json"
  echo "conteneurs d'initialisation actuels : $(jq -c '[.spec.initContainers[]? | {name, securityContext}]' "$T/chains.json")" | cut -c1-300

  echo; echo "## 6. Qui peut créer des pods dans local-path-storage (espace absent sous k3s : liaisons de tout le cluster seulement)"
  while read -r e c; do
    [ "$(kubectl auth can-i create pods -n local-path-storage --as "system:serviceaccount:$e:$c" 2>/dev/null </dev/null || true)" != yes ] \
      || echo "oui : $e/$c"
  done < <(kubectl get sa -A -o json </dev/null | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"') | tee "$T/createurs"
  echo "comptes de service en lecture : $(kubectl get sa -A --no-headers </dev/null | wc -l) ; autorisés : $(wc -l < "$T/createurs")"
  echo "Role de l'espace dans le manifeste $LP_TAG, épinglé par sha256 :"
  yq -o json '.' "$HOME/.cache/supply-chain-poc/08b/telechargements/local-path-storage.yaml" \
    | jq -c -s '.[] | select(.kind == "Role" or .kind == "RoleBinding") | {kind, name: .metadata.name, ns: .metadata.namespace, rules, subjects}' | sed 's/^/  /'

  echo; echo "## 7. Cas d'admission de la 08 : base de ZONE et de POD (cas-admission.py), présentés à scan (restricted)"
  python3 -I "$here/../08-trust-plane/politique/cas-admission.py" "$T/adm" x "$BUSYBOX" >/dev/null
  jq '.metadata.namespace = "scan"' "$T/adm/zone-confiance.json" > "$T/zone.json"
  essai "cas zone-confiance, destiné à tekton-chains" "$T/zone.json"
  jq '.metadata.namespace = "scan" | .spec.nodeSelector = {zone: "confiance"}' "$T/adm/pod-cap-net-bind.json" > "$T/net-bind.json"
  essai "cas pod-cap-net-bind, destiné à bancc" "$T/net-bind.json"
  echo "utilisateur déclaré par busybox : $(crane config "docker.io/rancher/mirrored-library-busybox@sha256:ad9fa4d07136a83e69a54ef00102f579d04eba431932de3b0f098cc5d5948f9f" | jq -c '.config.User // "aucun"')"
}

releve 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/releve-restricted.log"
