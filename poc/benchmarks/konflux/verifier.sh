#!/usr/bin/env bash
# Banc A1 : vérifie depuis l'hôte une image construite par Konflux, et exerce T7.
# - Registre interne (Zot authentifié) atteint par 127.0.0.1:5001 ; CA et identifiants du
#   tenant copiés dans un répertoire 0600, effacé à la fin.
# - cosign (nixpkgs épinglé) : signature et attestation avec la clé publique de Chains
#   (openshift-pipelines/public-key, celle de la politique Conforma « default ») ;
#   provenance archivée (resultats/provenance-<digest court>.json).
# - Conforma : politique EnterpriseContractPolicy « default » de Konflux, telle quelle.
# - T7 : la même image recopiée (a) sans signature ni attestation, (b) avec l'attestation
#   seule, sous d'autres noms ; cosign et Conforma doivent refuser les deux.
#
# Usage (racine du dépôt) : mise run konflux:verifier -- <digest> [libellé]
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
export KUBECONFIG=$HOME/.kube/supply-chain-poc-konflux.yaml
COSIGN=$POC_OUTILS/cosign-nix/bin/cosign
D=${1:?digest sha256:…}
L=${2:-verification}
REPO=localhost:5001/default-tenant/sample-app
W=$(mktemp -d "$HOME/.cache/supply-chain-poc/konflux/verif.XXXXXX")
trap 'rm -rf -- "$W"' EXIT
chmod 700 "$W"
exec > >(sed -u "s#$HOME#~#g" | tee "$R/$L.log") 2>&1
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; }
echo "# verifier.sh $D, $(date -u +%Y-%m-%dT%H:%M:%SZ), cosign $("$COSIGN" version 2>/dev/null | awk '/GitVersion/ {print $2}') (nixpkgs), ec $(ec version 2>/dev/null | awk '/Version/ {print $2; exit}')"

# Accès au registre et à la clé publique.
kubectl get secret -n kind-registry local-registry-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "$W/ca.crt"
mkdir -p "$W/docker"
kubectl get secret -n default-tenant regcred-internal-registry -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d \
  | jq '{auths: {"localhost:5001": .auths["registry-service.kind-registry"]}}' > "$W/docker/config.json"
kubectl get secret -n openshift-pipelines public-key -o jsonpath='{.data.cosign\.pub}' | base64 -d > "$W/cosign.pub"
kubectl get enterprisecontractpolicy -n enterprise-contract-service default -o json | jq '.spec' > "$W/policy.json"
export DOCKER_CONFIG=$W/docker SSL_CERT_FILE=$W/ca.crt
img=$REPO@$D

# Signature, attestation, provenance.
"$COSIGN" verify --key "$W/cosign.pub" --insecure-ignore-tlog "$img" > "$W/sig.json" 2>"$W/sig.err" \
  && ok "signature cosign (clé de Chains) : $(jq -r '.[0].critical.type' "$W/sig.json"), $(jq length "$W/sig.json") signature(s)" \
  || ko "signature : $(tail -1 "$W/sig.err")"
"$COSIGN" verify-attestation --key "$W/cosign.pub" --insecure-ignore-tlog --type slsaprovenance02 "$img" > "$W/att.json" 2>"$W/att.err" \
  && ok "attestation cosign (clé de Chains) vérifiée" || ko "attestation : $(tail -1 "$W/att.err")"
if [ -s "$W/att.json" ]; then
  head -1 "$W/att.json" | jq -r '.payload' | base64 -d | jq . > "$R/provenance-${D:7:12}.json"
  jq -r '"provenance : \(.predicateType), builder \(.predicate.builder.id), buildType \(.predicate.buildType)",
    "  sujets : \([.subject[] | "\(.name)@\(.digest.sha256[0:12])"] | join(", "))",
    "  matériaux : \(.predicate.materials | length) (\([.predicate.materials[] | .uri | split("@")[0] | split("/")[-1]] | unique | join(", ") | .[0:200]))",
    "  paramètres : hermetic=\(.predicate.invocation.parameters.hermetic // "-"), source-date-epoch=\(.predicate.invocation.parameters["source-date-epoch"] // "-")"' "$R/provenance-${D:7:12}.json"
fi
echo "transparence : $(kubectl get cm -n tekton-pipelines chains-config -o jsonpath='{.data.transparency\.enabled}') ; référents OCI : $(crane ls "$REPO" 2>/dev/null | grep -c "^sha256-${D:7}\." || true) tag(s) .sig/.att"

# Conforma, politique « default » de Konflux.
conforma() { # $1 = image, $2 = libellé ; renvoie le code de ec
  local rc=0
  ec validate image --image "$1" --policy "$W/policy.json" --public-key "$W/cosign.pub" --ignore-rekor \
    --output json="$W/ec-$2.json" --timeout 10m >/dev/null 2>"$W/ec-$2.err" || rc=$?
  echo "Conforma ($2) : code $rc, succès=$(jq -r '.success' "$W/ec-$2.json" 2>/dev/null), violations $(jq '[.components[].violations // [] | length] | add' "$W/ec-$2.json" 2>/dev/null), avertissements $(jq '[.components[].warnings // [] | length] | add' "$W/ec-$2.json" 2>/dev/null)"
  jq -r '.components[].violations // [] | .[] | "     violation : \(.metadata.code) : \(.msg | .[0:160])"' "$W/ec-$2.json" 2>/dev/null | sort | uniq -c | head -15
  [ -s "$W/ec-$2.json" ] || tail -3 "$W/ec-$2.err"
  return $rc
}
conforma "$img" image || true

# T7 : copies sans signature, puis avec l'attestation seule.
crane copy "$img" "$REPO-t7a:non-signee" >/dev/null 2>&1
crane copy "$img" "$REPO-t7b:attestation-seule" >/dev/null 2>&1
crane copy "$REPO:sha256-${D:7}.att" "$REPO-t7b:sha256-${D:7}.att" >/dev/null 2>&1
for c in t7a t7b; do
  i=$REPO-$c@$D
  "$COSIGN" verify --key "$W/cosign.pub" --insecure-ignore-tlog "$i" >/dev/null 2>"$W/$c.err" \
    && ko "T7 $c : cosign verify accepte l'image" || ok "T7 $c : cosign verify refuse ($(tail -1 "$W/$c.err" | cut -c1-120))"
  conforma "$i" "$c" && ko "T7 $c : Conforma accepte l'image" || ok "T7 $c : Conforma refuse l'image"
done
