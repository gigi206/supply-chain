#!/usr/bin/env bash
# Vérification à sec du correctif D8 à D12 : blocs extraits des scripts du clone, rien de créé ni de modifié sur le cluster.
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
W=$HOME/.cache/supply-chain-poc/08b/correctif-d8-d12
A=$W/poc/bricks/08-trust-plane                                # avec correctif
O=/home/gigi/Documents/git/github/gigi206/supply-chain/poc/bricks/08-trust-plane  # sans correctif, dépôt en l'état
DL=$HOME/.cache/supply-chain-poc/08/telechargements
T=$(umask 077 && mktemp -d "$HOME/.cache/supply-chain-poc/08b/verif-d8.XXXXXX")
trap 'rm -rf -- "${T:?}"' EXIT
ko=0
ok() { echo "OK   $1"; }
non() { echo "KO   $1"; ko=1; }
fonction() { sed -n "/^$2() {/,/^}/p" "$1"; }

date -u '+vérification du %d/%m/%Y à %H:%M UTC'

echo; echo "## 1. Syntaxe"
for f in tekton.sh politique.sh stockage.sh; do bash -n "$A/$f" && ok "bash -n $f" || non "bash -n $f"; done
if command -v shellcheck >/dev/null; then
  for f in tekton.sh politique.sh stockage.sh; do
    a=$(cd "$A" && shellcheck -f gcc -x "$f" 2>/dev/null | wc -l); b=$(cd "$O" && shellcheck -f gcc -x "$f" 2>/dev/null | wc -l)
    echo "shellcheck $f : $b avis avant, $a après"
  done
else echo "shellcheck absent : non passé"; fi

echo; echo "## 2. D12 et D10, branches RKE2 avec un faux kubectl"
cat > "$T/faux.sh" <<'F'
kubectl() { echo "kubectl $*" >> "$APPELS"; case "$*" in *jsonpath*) printf %s "$ENFORCE" ;; esac; }
attendre_sa() { :; }
F
{ cat "$T/faux.sh"; fonction "$A/tekton.sh" builds_privilegie; echo 'builds_privilegie'; } > "$T/d12.sh"
cas() { # distro enforce attendu libellé
  : > "$T/appels"
  DISTRO=$1 ENFORCE=$2 APPELS=$T/appels bash -c 'set -euo pipefail; . "$0"' "$T/d12.sh"
  n=$(grep -c ' label ' "$T/appels"); [ "$n" = "$3" ] && ok "$4 : $n label" || non "$4 : $n label, attendu $3"
}
cas k3s "" 0 "k3s, sans label"
cas rke2 "" 1 "rke2, sans label (J4)"
cas rke2 restricted 0 "rke2, déjà restricted (tekton.sh signature rejoué après J6)"
cas rke2 privileged 0 "rke2, déjà privileged"
grep -n 'overwrite' "$T/appels" && non "D12 : --overwrite inattendu" || ok "D12 : pas de --overwrite, restricted ne peut pas être écrasé"
{ cat "$T/faux.sh"; echo 'NS_ESSAI=bancc'; fonction "$A/politique.sh" espace_essai; echo 'espace_essai'; } > "$T/d10.sh"
for d in k3s rke2; do
  : > "$T/appels"; DISTRO=$d ENFORCE="" APPELS=$T/appels bash -c 'set -euo pipefail; . "$0"' "$T/d10.sh"
  echo "$d : $(grep -c ' label ' "$T/appels") label, $(grep -c 'create namespace' "$T/appels") création"
done
echo "espaces d'essai encore créés hors du helper : $(grep -c 'kubectl create namespace "$NS_ESSAI"' "$A/politique.sh") (1 attendu, dans le helper)"

echo; echo "## 3. D9 : ligne réelle du correctif sur install.yaml"
k=$T/ky; mkdir -p "$k"
cp "$DL/kyverno/install.yaml" "$k/install.yaml"; cp "$A/politique/kustomization-kyverno.yaml" "$k/kustomization.yaml"; echo x > "$k/ca.crt"
ligne=$(grep -n 'D_LP_NS" = kube-system' "$A/politique.sh" | cut -d: -f2-)
controle=$(sed -n '/yq -o json "$k\/rendu.yaml" | jq -e -s --arg n "$D_LP_NS"/,/non exclu des webhooks/p' "$A/politique.sh")
essai_d9() { # D_LP_NS [sans sed]
  ( set -e; cp "$DL/kyverno/install.yaml" "$k/install.yaml"; D_LP_NS=$1
    [ -n "${2:-}" ] || eval "$ligne"
    kubectl kustomize "$k" > "$k/rendu.yaml"
    eval "$controle" ) 2>&1
  echo "code $?"
}
essai_d9 kube-system; cmp -s "$k/install.yaml" "$DL/kyverno/install.yaml" && ok "k3s : install.yaml inchangé" || non "k3s : install.yaml modifié"
essai_d9 local-path-storage
echo "lignes changées : $(diff "$DL/kyverno/install.yaml" "$k/install.yaml" | grep -c '^>')"
yq -o json "$k/rendu.yaml" | jq -c -s '.[] | select(.kind == "ConfigMap" and .metadata.name == "kyverno") | .data.webhooks | fromjson | .namespaceSelector.matchExpressions[].values'
yq -o json "$k/rendu.yaml" | jq -c -s '.[] | select(.kind == "ConfigMap" and .metadata.name == "kyverno") | .data.resourceFilters' | grep -c 'local-path' | sed 's/^/resourceFilters mentionnant local-path : /'
echo "témoin négatif : sed retiré, le contrôle doit dire KO"
essai_d9 local-path-storage sans

echo; echo "## 4. D8 : rendu réel de Chains, avec et sans correctif"
echo x > "$T/ca-poc.crt"
printf 'source\tdigest_release\tdigest_amd64\tmiroir\n' > "$T/tsv"
RELEASE=$DL/tekton/chains-v0.29.9/github/release.yaml
B=$T
rendu() { # racine-08 distro sortie
  ( set -e; here=$1; DISTRO=$2; T=$B/r; P=$B; BUSYBOX_AMONT=docker.io/rancher/mirrored-library-busybox:1.37.0; TSV=$B/tsv
    mkdir -p "$T"
    eval "$(fonction "$here/tekton.sh" rendre)"
    rendre chains "$RELEASE"
    cp "$T/chains/rendu.yaml" "$3" )
}
rendu "$O" k3s "$T/avant-k3s.yaml" && rendu "$A" k3s "$T/apres-k3s.yaml" && rendu "$A" rke2 "$T/apres-rke2.yaml"
for x in avant-k3s apres-k3s apres-rke2; do [ -s "$T/$x.yaml" ] && echo "$x : $(grep -c '^kind:' "$T/$x.yaml") objets" || non "$x vide ou absent"; done
[ -s "$T/apres-k3s.yaml" ] && cmp -s "$T/avant-k3s.yaml" "$T/apres-k3s.yaml" && ok "rendu de Chains identique sous k3s, $(sha256sum < "$T/apres-k3s.yaml" | cut -c1-16)…" || non "rendu de Chains différent sous k3s"
echo "différences k3s → rke2 :"; diff "$T/apres-k3s.yaml" "$T/apres-rke2.yaml" | sed 's/^/  /' | cut -c1-100
yq -o json "$T/apres-rke2.yaml" | jq -c -s '.[] | select(.kind == "Deployment") | {n: .metadata.name, pod: .spec.template.spec.securityContext, c: [.spec.template.spec.containers[] | {name, securityContext}]}'
echo "Deployments du rendu : $(yq -o json "$T/apres-rke2.yaml" | jq -s '[.[] | select(.kind == "Deployment")] | length')"
yq -o json "$T/apres-rke2.yaml" | jq -s '.[] | select(.kind == "Deployment") | {apiVersion: "v1", kind: "Pod", metadata: {name: "essai-d8", namespace: "scan"}, spec: (.spec.template.spec | del(.serviceAccountName, .serviceAccount))}' > "$T/d8.json"

echo; echo "## 5. D11 : pods réels de stockage.sh"
sed -n "/^  kubectl apply -f - <<EOF$/,/^EOF$/p" "$A/stockage.sh" | sed -e '1d;$d' > "$T/j2.brut"
grep -c 'runAsNonRoot' "$T/j2.brut" | sed 's/^/pods réglés : /'
APP=sc-stockage.poc.test:5000/workspace/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
sed -e "s#\$REG/\$DEPOT@\$APP_DIGEST#$APP#" -e 's#\$BUSYBOX#docker.io/rancher/mirrored-library-busybox:1.37.0#' -e 's/namespace: j2-essais/namespace: builds/' \
  -e 's/name: sample-app,/name: essai-d11-app,/' -e 's/name: dns,/name: essai-d11-dns,/' "$T/j2.brut" > "$T/j2.yaml"
grep -c '\$' "$T/j2.yaml" | sed 's/^/variables non remplacées : /'
yq -o json "$T/j2.yaml" > "$T/j2.json" && jq -c -s '.[] | {n: .metadata.name, c: .spec.securityContext}' "$T/j2.json"

echo; echo "## 6. Présentés à l'API, à sec"
if [ "$(date -u +%H%M)" -ge 0912 ]; then echo "09:12 UTC dépassé : section sautée, fenêtre du relevé"; else
  essai() { o=$(kubectl create --dry-run=server -f "$2" 2>&1 </dev/null) && echo "ADMIS    $1" || { echo "REFUSÉ   $1"; echo "$o" | sed 's/^/         /' | cut -c1-300; }; }
  echo "enforce : scan=$(kubectl get ns scan -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' </dev/null) builds=$(kubectl get ns builds -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' </dev/null)"
  [ -s "$T/d8.json" ] || non "D8 : aucun pod à présenter"
  essai "D8 : Chains rendu sous rke2, dans scan" "$T/d8.json"
  jq 'del(.spec.securityContext)' "$T/d8.json" > "$T/d8-temoin.json"
  essai "D8 témoin : même pod sans securityContext de pod" "$T/d8-temoin.json"
  essai "D11 : les deux pods de j2-essais, dans builds" "$T/j2.yaml"
  sed '/runAsNonRoot/d' "$T/j2.yaml" > "$T/j2-temoin.yaml"
  essai "D11 témoin : mêmes pods sans le correctif" "$T/j2-temoin.yaml"
  avant=$(kubectl get ns builds -o json </dev/null | jq -c '.metadata.labels | with_entries(select(.key | startswith("pod-security")))')
  o=$(kubectl label --dry-run=server --overwrite namespace builds pod-security.kubernetes.io/enforce=privileged pod-security.kubernetes.io/enforce-version- </dev/null 2>&1); c=$?
  echo "D12 ligne 612, à sec : code $c, $o" | cut -c1-200
  apres=$(kubectl get ns builds -o json </dev/null | jq -c '.metadata.labels | with_entries(select(.key | startswith("pod-security")))')
  [ "$avant" = "$apres" ] && ok "labels de builds inchangés" || non "labels de builds modifiés"
fi

echo; date -u '+fin à %H:%M:%S UTC'
[ "$ko" = 0 ] && echo "aucun KO" || echo "au moins un KO"
