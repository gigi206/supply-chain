#!/usr/bin/env bash
# Brique 08d : relevés à sec pour la décision D6 de la 08b (cert-manager). Rien n'est installé ni modifié : lectures sur l'API et le chart, rendu local.
#   telecharger    chart v1.21.3 par digest épinglé, signature vérifiée avec la clé publiée par le projet, témoin d'une autre clé refusé
#   consommateurs  certificats du cluster en service : noms de clés et de Secrets, jamais de valeur privée ; ce qui peut prendre un certificat de cert-manager
#   droits         chart rendu : images, contextes de sécurité face à restricted, règles sur les Secrets
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08d-cert-manager/analyse.sh <étape>…   (journal : resultats/analyse-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
D=$HOME/.cache/supply-chain-poc/08d/telechargements
T=$HOME/.cache/supply-chain-poc/08d/analyse
CHART=quay.io/jetstack/charts/cert-manager
VERSION=v1.21.3
DIGEST=sha256:e482675aec32862d323a9218293ff7de81192337998615e4378c56498473f240
TGZ_SHA=9ec67938b2981d8b333af61b3fcf53e26b4f6f5deb7ccda3de4ea116bb373a17
CLE_URL=https://cert-manager.io/public-keys/cert-manager-pubkey-2021-09-20.pem
CLE_SHA=62151ffda7bb5350367480750ff1cb75d53f0f83baca524044e5274aa83b63a6
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/supply-chain-poc.yaml}
mkdir -p "$R" "$D" "$T"

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)"; exit 1; }; }

etape_telecharger() {
  local v rc=0
  attendu "digest du tag $VERSION" "$(crane digest "$CHART:$VERSION")" "$DIGEST"
  curl -fsSL --proto '=https' "$CLE_URL" -o "$D/cert-manager.pem"
  attendu "empreinte de la clé publiée" "$(sha256sum "$D/cert-manager.pem" | cut -d' ' -f1)" "$CLE_SHA"
  cosign verify --signature-digest-algorithm sha512 --insecure-ignore-tlog --key "$D/cert-manager.pem" "$CHART@$DIGEST" > "$T/verify.json" 2> "$T/verify.err"
  attendu "digest signé" "$(jq -r '.[0].critical.image."docker-manifest-digest"' "$T/verify.json")" "$DIGEST"
  openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl ec -pubout -out "$T/temoin.pem" 2>/dev/null
  cosign verify --signature-digest-algorithm sha512 --insecure-ignore-tlog --key "$T/temoin.pem" "$CHART@$DIGEST" > /dev/null 2> "$T/temoin.err" || rc=$?
  [ "$rc" != 0 ] && echo "OK   témoin : autre clé refusée (rc $rc)" || { echo "KO   témoin accepté"; exit 1; }
  v=$D/cert-manager-$VERSION.tgz
  [ -f "$v" ] || helm pull "oci://$CHART" --version "$VERSION" -d "$D" >/dev/null 2>&1
  attendu "empreinte du chart" "$(sha256sum "$v" | cut -d' ' -f1)" "$TGZ_SHA"
}

etape_consommateurs() {
  local s n o p
  echo "## Secrets portant un certificat : espace/nom, type, propriétaire (label), clés"
  kubectl get secrets -A -o json | jq -r '.items[] | select(.type != "kubernetes.io/service-account-token")
    | select((.data // {}) | keys | map(test("crt|cert|ca\\.key")) | any)
    | "\(.metadata.namespace)/\(.metadata.name) \(.type) \(.metadata.labels["cert.kyverno.io/managed-by"] // .metadata.labels["app.kubernetes.io/managed-by"] // "-") \(.data | keys | join(","))"'
  echo "## certificat Hubble : sujet, SAN et fin, partie publique"
  kubectl get secret -n kube-system hubble-server-certs -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate -ext subjectAltName | sed 's/^ *//'
  echo "## clients du port 4244"
  echo "pods Hubble Relay ou UI : $(kubectl get pods -A --no-headers 2>/dev/null | grep -c -i hubble || true)"
  p=$(kubectl -n kube-system get pod -l k8s-app=cilium -o name | head -1)
  kubectl -n kube-system exec "$p" -c cilium-agent -- hubble config view 2>/dev/null | grep -E '^(server|tls):'
  echo "## CA du PoC"
  openssl x509 -in "$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt" -noout -ext basicConstraints,nameConstraints | sed 's/^ *//'
  echo "## OpenBao en service : version, scellement au redémarrage mesuré dans redemarrer.sh"
  kubectl exec -n openbao openbao-0 -- bao version
  kubectl get pod -n openbao openbao-0 -o jsonpath='{.spec.containers[0].image}{"\n"}'
}

etape_droits() {
  local c=$D/cert-manager-$VERSION.tgz
  attendu "empreinte du chart" "$(sha256sum "$c" | cut -d' ' -f1)" "$TGZ_SHA"
  helm template cert-manager "$c" --namespace cert-manager --set crds.enabled=true > "$T/rendu.yaml"
  kubectl create --dry-run=client --validate=false -o json -f "$T/rendu.yaml" 2> "$T/rendu.err" | jq -s '[.[] | if .kind == "List" then .items[] else . end]' > "$T/rendu.json"
  echo "objets par type : $(jq -c '[group_by(.kind)[] | {(.[0].kind): length}] | add' "$T/rendu.json")"
  echo "## images"
  jq -r '.[] | select(.kind == "Deployment" or .kind == "Job") | "\(.kind)/\(.metadata.name) : \(.spec.template.spec.containers[].image)"' "$T/rendu.json"
  echo "## limites et contexte de sécurité par conteneur"
  jq -r '.[] | select(.kind == "Deployment" or .kind == "Job") | .metadata.name as $n | .spec.template.spec as $s | $s.containers[]
    | "\($n) : limites=\(.resources.limits // "aucune" | tostring) nonRoot=\($s.securityContext.runAsNonRoot) seccomp=\($s.securityContext.seccompProfile.type) escalade=\(.securityContext.allowPrivilegeEscalation) cap-drop=\(.securityContext.capabilities.drop | tostring)"' "$T/rendu.json"
  echo "## règles sur les Secrets (ClusterRole : portée du cluster ; Role : espace)"
  jq -r '.[] | select(.kind == "ClusterRole" or .kind == "Role") | .kind as $k | .metadata.name as $n | (.metadata.namespace // "cluster") as $e
    | .rules[] | select((.resources // []) | any(. == "secrets" or . == "*")) | "\($k) \($e) \($n) : \(.verbs | join(",")) \(.resourceNames // [] | join(","))"' "$T/rendu.json"
  echo "## liaisons de ces rôles"
  jq -r '.[] | select(.kind == "ClusterRoleBinding" or .kind == "RoleBinding") | "\(.kind) \(.roleRef.name) -> \(.subjects | map(.name) | join(","))"' "$T/rendu.json" | grep -E 'cainjector|certificates|issuers|challenges|orders|webhook' | sort -u
  echo "## droit de créer des jetons de compte de service dans le chart"
  jq -r '.[] | select(.kind == "ClusterRole" or .kind == "Role") | select(any(.rules[]; (.resources // []) | any(. == "serviceaccounts/token"))) | "\(.kind) \(.metadata.name) \(.rules | map(select((.resources // []) | any(. == "serviceaccounts/token"))) | tostring)"' "$T/rendu.json"
  echo "## webhooks de l'admission"
  jq -r '.[] | select(.kind | test("WebhookConfiguration")) | .kind as $k | .webhooks[] | "\($k) \(.name) failurePolicy=\(.failurePolicy)"' "$T/rendu.json"
}

for e in "$@"; do
  { echo "# analyse.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/analyse-$e.log"
  [ "${PIPESTATUS[0]}" = 0 ] || exit 1
done
