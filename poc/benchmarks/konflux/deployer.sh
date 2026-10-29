#!/usr/bin/env bash
# Banc A1 : déploie Konflux v0.2.2 sur kind depuis la copie préparée par preparer.sh,
# chronomètre chaque étape et archive l'état obtenu.
#
# 1. setup-kind-local-cluster.sh de Konflux, avec un KUBECONFIG dédié (jamais ~/.kube/config)
#    et system-reserved réglé pour que l'allocatable du kubelet reste sous le plafond :
#    sous Linux, le kubelet du nœud kind voit toute la mémoire de l'hôte.
# 2. Nœud plafonné à 20 Gi (docker update), avant tout téléchargement d'image.
# 3. Ports publiés : 127.0.0.1 seulement, sinon arrêt.
# 4. deploy-local.sh (DEPLOY_LOCAL_SKIP_KIND=1) : release v0.2.2 appliquée depuis le
#    disque (INSTALL_YAML), CR a1/konflux.yaml, ni secrets GitHub ni smee.
# 5. État : pods, images et imageID, composants (règle A-5), mémoire, config de Chains.
#
# Le chronomètre du banc (resultats/chrono.tsv) démarre à l'étape 1 du premier passage.
# Usage (racine du dépôt) : mise run konflux:deployer
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
K=${KONFLUX_DIR:-$HOME/.cache/supply-chain-poc/konflux}
R=$here/resultats
PLAFOND_GI=20
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
export KUBECONFIG=$HOME/.kube/supply-chain-poc-konflux.yaml KIND_CLUSTER=konflux
noeud=$KIND_CLUSTER-control-plane

mkdir -p "$R"
masque() { sed -u "s#$HOME#~#g"; }
ko() { echo "KO   $*"; exit 1; }
[ -f "$R/chrono.tsv" ] || printf 'étape\tdate (UTC)\tdepuis le début\n' > "$R/chrono.tsv"
t0=$(awk -F'\t' 'NR == 2 {print $2}' "$R/chrono.tsv")
etape() { # $1 = nom ; ajoute une ligne au chronomètre
  local now e
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  [ -n "$t0" ] || t0=$now
  e=$(( $(date -d "$now" +%s) - $(date -d "$t0" +%s) ))
  printf '%s\t%s\t%dh%02dm%02ds\n' "$1" "$now" $((e / 3600)) $((e % 3600 / 60)) $((e % 60)) | tee -a "$R/chrono.tsv"
}

# Copie préparée : commit d'adaptations, arbre propre, install.yaml épinglé identique au journal de préparation.
cd "$K/konflux-ci"
[ -z "$(git status --porcelain)" ] || ko "copie de travail modifiée depuis preparer.sh"
s=$(sha256sum "$K/assets/install-epingle.yaml" | cut -c1-64)
grep -q "install-epingle.yaml : sha256 $s" "$R/preparation.log" || ko "install-epingle.yaml ($s) ≠ journal de préparation"
! kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER" || ko "le cluster $KIND_CLUSTER existe déjà : mise run konflux:demonter"
config=$(sha256sum ~/.kube/config 2>/dev/null | cut -c1-64 || true)

{
  echo "# deployer.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), konflux-ci $(git describe --tags --always) (adaptations $(git rev-parse --short HEAD)), install-epingle.yaml $s"
  echo "# kind $(kind version | cut -d' ' -f2), kubectl $(kubectl version --client | awk 'NR == 1 {print $3}'), docker $(docker version --format '{{.Server.Version}}')"

  # 1. Cluster.
  mem=$(awk '/MemTotal/ {print int($2 / 1048576)}' /proc/meminfo)
  export KIND_MEMORY_GB=$(( mem - PLAFOND_GI + 1 ))
  echo "# hôte : $mem Gi ; system-reserved=${KIND_MEMORY_GB}Gi pour un allocatable sous ${PLAFOND_GI} Gi"
  etape "1. création du cluster kind (début du banc A1)"
  scripts/setup-kind-local-cluster.sh

  # 2. Plafond mémoire.
  docker update --memory="${PLAFOND_GI}g" --memory-swap="${PLAFOND_GI}g" "$noeud" >/dev/null
  m=$(docker inspect -f '{{.HostConfig.Memory}}' "$noeud")
  [ "$m" = $((PLAFOND_GI * 1024 * 1024 * 1024)) ] && echo "OK   $noeud plafonné à $PLAFOND_GI Gi" || ko "plafond mémoire : $m"
  echo "allocatable : $(kubectl get node "$noeud" -o jsonpath='{.status.allocatable.memory}'), capacité : $(kubectl get node "$noeud" -o jsonpath='{.status.capacity.memory}')"

  # 3. Ports publiés.
  docker port "$noeud"
  ! docker port "$noeud" | grep -qv -- '-> 127\.0\.0\.1:' && echo "OK   ports publiés sur 127.0.0.1 seulement" || ko "port publié hors de 127.0.0.1"
  [ "$(sha256sum ~/.kube/config 2>/dev/null | cut -c1-64 || true)" = "$config" ] && echo "OK   ~/.kube/config inchangé" || ko "config personnelle ~/.kube/config modifiée"
  etape "2. cluster prêt, plafond et ports contrôlés"

  # 4. Konflux.
  env OPERATOR_INSTALL_METHOD=release OPERATOR_RELEASE=v0.2.2 INSTALL_YAML="$K/assets/install-epingle.yaml" \
    KONFLUX_CR=a1/konflux.yaml SKIP_SECRETS=true SKIP_SMEE=true DEPLOY_LOCAL_SKIP_KIND=1 scripts/deploy-local.sh
  etape "3. deploy-local.sh terminé (Konflux Ready)"
} 2>&1 | masque > "$R/installation.log"

# 5. État.
"$here/etat.sh" "installation"
