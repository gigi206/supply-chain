#!/usr/bin/env bash
# Banc A1 : copie de travail de Konflux v0.2.2 dont chaque entrée est téléchargée une
# fois, vérifiée puis épinglée ; les adaptations au laptop sont figées dans un commit
# local de la copie (le script de création du cluster fait `git checkout kind-config.yaml`).
#
# 1. Tag v0.2.2 cloné, commit vérifié (tag annoté, non signé).
# 2. install.yaml de la release Konflux, release.yaml de l'opérateur Tekton v0.81.1 et
#    clé publique de cert-manager : sha256 comparés aux valeurs relevées le 29/10/2026 ;
#    ils sont appliqués depuis le disque, jamais depuis leur URL.
# 3. Images citées par tag : digest comparé à celui relevé le 29/10/2026, signature
#    vérifiée quand le projet en publie une, puis épinglage `tag@digest`.
#    Les images déjà citées par digest (Tekton, task-runner) sont contrôlées et gardées.
# 4. Adaptations commitées : nœud kind par digest, ports sur 127.0.0.1, port de Quay
#    retiré, release.yaml de Tekton local, install.yaml local (INSTALL_YAML), CR avec
#    télémétrie explicitement désactivée. Diff archivé dans resultats/.
#
# Usage (racine du dépôt) : mise run konflux:preparer
# Sortie : $KONFLUX_DIR (défaut ~/.cache/supply-chain-poc/konflux), resultats/preparation.log.
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
: "${POC_OUTILS:?lancer avec : mise run konflux:preparer}"
K=${KONFLUX_DIR:-$HOME/.cache/supply-chain-poc/konflux}
R=$here/resultats
COSIGN=$POC_OUTILS/cosign-nix/bin/cosign
TAG=v0.2.2
COMMIT=be0e6cac273fe90ff6ef8e388a50c67be1308d52
NODE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
TEKTON=tekton-operator-v0.81.1.yaml
TM=https://github.com/cert-manager/trust-manager/.github/workflows
# Les shims de mise échouent hors du dépôt : on garde les répertoires des outils posés par `mise run`.
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)

# Fichiers : URL et sha256 relevé le 29/10/2026.
fichiers=(install.yaml "$TEKTON" cert-manager.pem)
declare -A URL=(
  [install.yaml]=https://github.com/konflux-ci/konflux-ci/releases/download/$TAG/install.yaml
  [$TEKTON]=https://infra.tekton.dev/tekton-releases/operator/previous/v0.81.1/release.yaml
  [cert-manager.pem]=https://cert-manager.io/public-keys/cert-manager-pubkey-2021-09-20.pem
)
declare -A SHA=(
  [install.yaml]=68fbb841e8c83a6c2b4181dd6c7fad5a0d570869d3556753f92eced3b6805ff3
  [$TEKTON]=3b7d798ed9f7e1fb6e4f271a0171ba3389d50226244223db30da0840624b03f6
  [cert-manager.pem]=62151ffda7bb5350367480750ff1cb75d53f0f83baca524044e5274aa83b63a6
)
# Images citées par tag : fichier qui les cite (relatif à la copie, ou assets/) et digest relevé le 29/10/2026.
images=(
  quay.io/konflux-ci/konflux-operator:release-sha-be0e6ca
  quay.io/jetstack/cert-manager-controller:v1.21.1
  quay.io/jetstack/cert-manager-webhook:v1.21.1
  quay.io/jetstack/cert-manager-cainjector:v1.21.1
  quay.io/jetstack/cert-manager-startupapicheck:v1.21.1
  quay.io/jetstack/cert-manager-acmesolver:v1.21.1
  quay.io/jetstack/trust-manager:v0.24.0
  quay.io/jetstack/trust-pkg-debian-trixie:20250419.1
  registry:2
)
declare -A FICHIER=(
  [quay.io/konflux-ci/konflux-operator:release-sha-be0e6ca]=assets/install-epingle.yaml
  [quay.io/jetstack/trust-manager:v0.24.0]=konflux-ci/dependencies/trust-manager/trust-manager.yaml
  [quay.io/jetstack/trust-pkg-debian-trixie:20250419.1]=konflux-ci/dependencies/trust-manager/trust-manager.yaml
  [registry:2]=konflux-ci/dependencies/pre-deployment-pvc-binding/pre-deployment-pvc-binding.yaml
)
declare -A DIGEST=(
  [quay.io/konflux-ci/konflux-operator:release-sha-be0e6ca]=sha256:36493a95f2b7b0c18b610df5ec519d5725b94845524ecfaa66f3142f9696f1d0
  [quay.io/jetstack/cert-manager-controller:v1.21.1]=sha256:416a2d76870d996460e62bd7f521bf14fa017be9e3e904aab92163a331fcb61a
  [quay.io/jetstack/cert-manager-webhook:v1.21.1]=sha256:d8b3961b51c8c7320633f8208dc46bf88aa13804d0f7cbe48a096b2c523cee42
  [quay.io/jetstack/cert-manager-cainjector:v1.21.1]=sha256:ccf6b919ec0500745a47a910118f834f9636d0aac1ff221245cd2557ed8c7c98
  [quay.io/jetstack/cert-manager-startupapicheck:v1.21.1]=sha256:d8ab6416e6e7303a86fa0a8daa82c94a8001f21c9d78eb2e7db20534e5d07ae8
  [quay.io/jetstack/cert-manager-acmesolver:v1.21.1]=sha256:dbc7cc1354f603918e7c5af7f55a0a620537394452c93a565bde75c6f48e8837
  [quay.io/jetstack/trust-manager:v0.24.0]=sha256:a7c1d71cad37b404738192213e3801dbf89fe797e72664b0ff0d498db35cea74
  [quay.io/jetstack/trust-pkg-debian-trixie:20250419.1]=sha256:17084a794d1e75065c9047438e2a6167907771fe78d7e4b5d4373a4b1d4e0494
  [registry:2]=sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373
)

mkdir -p "$R"
exec > >(sed -u "s#$HOME#~#g" | tee "$R/preparation.log") 2>&1
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; exit 1; }
na() { echo "--   $*"; }
echo "# preparer.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), konflux $TAG, kind $(kind version | cut -d' ' -f2), kubectl $(kubectl version --client | awk 'NR == 1 {print $3}'), cosign $("$COSIGN" version 2>/dev/null | awk '/GitVersion/ {print $2}') (nixpkgs)"

# 1. Sources.
rm -rf "$K/konflux-ci" "$K/assets"
mkdir -p "$K/assets"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" https://github.com/konflux-ci/konflux-ci.git "$K/konflux-ci"
c=$(git -C "$K/konflux-ci" rev-parse HEAD)
[ "$c" = "$COMMIT" ] && ok "konflux-ci $TAG = commit $c (tag annoté, non signé)" || ko "konflux-ci $TAG = $c ≠ $COMMIT"

# 2. Fichiers téléchargés une fois.
cd "$K/assets"
for f in "${fichiers[@]}"; do
  curl -fsSL --retry 2 -o "$f" "${URL[$f]}"
  s=$(sha256sum "$f" | cut -c1-64)
  [ "$s" = "${SHA[$f]}" ] && ok "$f : sha256 $s = relevé du 29/10/2026 (${URL[$f]})" || ko "$f : sha256 $s ≠ ${SHA[$f]}"
done
n=$(grep -oE '(ghcr|gcr|quay)\.io/[^ "]+' "$TEKTON" | sort -u | wc -l)
t=$(grep -oE '(ghcr|gcr|quay)\.io/[^ "]+' "$TEKTON" | grep -vc '@sha256:' || true)
[ "$t" = 0 ] && ok "$TEKTON : $n références d'images, toutes par digest (non signées : doc 04 §5)" || ko "$TEKTON : $t images citées sans digest"
cp install.yaml install-epingle.yaml

# 3. Images citées par tag.
cd "$K"
for ref in "${images[@]}"; do
  d=$(crane digest "$ref")
  [ "$d" = "${DIGEST[$ref]}" ] && ok "$ref : digest $d = relevé du 29/10/2026" || ko "$ref : digest $d ≠ ${DIGEST[$ref]}"
  img=${ref%:*}@$d
  case "$ref" in
    quay.io/jetstack/cert-manager-*)
      # Commande et clé documentées par cert-manager.io (« Signature Verification ») ; clé dans Cloud KMS, sans Rekor.
      "$COSIGN" verify --signature-digest-algorithm sha512 --insecure-ignore-tlog --key assets/cert-manager.pem "$img" >/dev/null 2>&1 \
        && ok "$ref : signature cosign, clé de cert-manager.io" || ko "$ref : signature refusée" ;;
    quay.io/jetstack/trust-manager:*|quay.io/jetstack/trust-pkg-debian-trixie:*)
      # Keyless : workflows de release de github.com/cert-manager/trust-manager.
      case "$ref" in
        *trust-manager:*) w=release.yaml@refs/tags/${ref##*:} ;;
        *) w=trust-package-release-debian-trixie.yaml@refs/heads/main ;;
      esac
      "$COSIGN" verify --certificate-oidc-issuer https://token.actions.githubusercontent.com \
        --certificate-identity "$TM/$w" "$img" >/dev/null 2>&1 \
        && ok "$ref : signature sigstore ($TM/$w)" || ko "$ref : signature refusée" ;;
    quay.io/konflux-ci/*) na "$ref : signature par clé sans clé publique publiée, non vérifiable (doc 04 §5)" ;;
    *) na "$ref : aucune signature publiée" ;;
  esac
  f=${FICHIER[$ref]:-konflux-ci/dependencies/cert-manager/cert-manager.yaml}
  e=${ref//./\\.}
  sed -i "s#\($e\)\(\"\|\$\)#\1@$d\2#" "$f"
  grep -q "$ref@$d" "$f" && ok "$ref : épinglé par digest dans $f" || ko "$ref : absent de $f"
done
d=$(awk '/digest: sha256:/ {print $2}' konflux-ci/dependencies/tekton-chains-rbac/base/kustomization.yaml)
[ -n "$d" ] && na "quay.io/konflux-ci/task-runner (job de clé de Chains) : digest $d fixé par la kustomization, non vérifiable (Konflux)" \
  || ko "task-runner sans digest"

# 4. Adaptations au laptop, commitées dans la copie.
cd "$K/konflux-ci"
sed -i '/# Quay/,+3d' kind-config.yaml
sed -i 's#^\( *\)hostPort: [0-9]*$#&\n\1listenAddress: "127.0.0.1"#' kind-config.yaml
sed -i "s#^- role: control-plane\$#&\n  image: $NODE#" kind-config.yaml
[ "$(grep -c 'listenAddress: "127.0.0.1"' kind-config.yaml)" = 4 ] && ! grep -q 8443 kind-config.yaml && grep -q "image: $NODE" kind-config.yaml \
  && ok "kind-config.yaml : nœud par digest, 4 ports sur 127.0.0.1, port 8443 (Quay) retiré" || ko "kind-config.yaml"
cp "$K/assets/$TEKTON" dependencies/tekton-operator/release-v0.81.1.yaml
sed -i 's#^  - https://infra.tekton.dev/tekton-releases/operator/previous/v0.81.1/release.yaml$#  - release-v0.81.1.yaml#' dependencies/tekton-operator/kustomization.yml
grep -q '^  - release-v0.81.1.yaml$' dependencies/tekton-operator/kustomization.yml && ok "tekton-operator : release.yaml local" || ko "tekton-operator"
sed -i -e 's#^\( *\)echo "Downloading: ${RELEASE_URL}"$#\1echo "Applying: ${INSTALL_YAML:-${RELEASE_URL}}"#' \
  -e 's#^\( *\)kubectl apply -f "${RELEASE_URL}"$#\1kubectl apply -f "${INSTALL_YAML:-${RELEASE_URL}}"#' scripts/deploy-local.sh
[ "$(grep -c 'INSTALL_YAML:-' scripts/deploy-local.sh)" = 2 ] && ok "deploy-local.sh : install.yaml appliqué depuis INSTALL_YAML" || ko "deploy-local.sh"
mkdir -p a1
{ cat operator/config/samples/konflux_v1alpha1_konflux.yaml
  printf '  # Banc A1 : télémétrie Segment désactivée explicitement (défaut : désactivée).\n  telemetry:\n    enabled: false\n'
} > a1/konflux.yaml
ok "a1/konflux.yaml : CR d'exemple de $TAG, télémétrie désactivée explicitement"
git add -A
git -c user.name="banc A1" -c user.email=banc-a1@localhost commit -qm "Banc A1 : adaptations au laptop"
git diff "$TAG" -- . ':!dependencies/tekton-operator/release-v0.81.1.yaml' > "$R/adaptations-$TAG.diff"
diff "$K/assets/install.yaml" "$K/assets/install-epingle.yaml" >> "$R/adaptations-$TAG.diff" || true
ok "adaptations commitées ($(git rev-parse --short HEAD)) ; diff archivé : resultats/adaptations-$TAG.diff"
echo "install-epingle.yaml : sha256 $(sha256sum "$K/assets/install-epingle.yaml" | cut -c1-64)"
