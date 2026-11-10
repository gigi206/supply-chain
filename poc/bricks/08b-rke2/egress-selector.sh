#!/usr/bin/env bash
# Brique 08b : egress-selector-mode: disabled sur le server RKE2 (préparé à sec le 10/11/2026 à 20:40 UTC, NON LANCÉ). Décision du
# propriétaire : « on ne veut pas du proxy avec cilium ». Sans ce mode, kube-apiserver joint kubelet par un proxy HTTP CONNECT du
# superviseur (127.0.0.1:9345), puis la session remotedialer de l'agent ; la brique 06 y a situé le blocage de kubectl exec.
# Prérequis du mode disabled (docs.k3s.io, Basic Network Options) : kubelet, CNI et kube-proxy sur les servers, connectivité directe
# vers les agents : sc-confiance porte kubelet et Cilium (remplacement de kube-proxy) ; 10250 ouvert entre nœuds (hote-commun, 08c).
#   avant      lecture seule : sha256 de /etc/rancher/rke2/config.yaml sur sc-confiance comparé à celui de la version versionnée
#              d'avant ce changement (git show du commit indiqué) : la configuration en place est bien celle du dépôt (aucune valeur lue,
#              jetons dans des fichiers à part) ; sélecteur de sortie actuel de kube-apiserver
#   appliquer  config/sc-confiance.yaml copié et posé (0600) à la place de config.yaml, rke2-server redémarré ; attente de /readyz
#              et des trois nœuds Ready ; sélecteur de sortie relu (argument absent ou mode désactivé)
#   retour     même pose avec la version d'avant (git show), redémarrage, mêmes attentes (à lancer seulement en cas d'échec)
# Vérification ensuite par poc/bricks/06-deb-sbuild/diag-exec-kata.sh croise et connexions (accords à part).
#
# Usage (racine du dépôt, sous bash pour relever le code) :
#   mise exec -- poc/bricks/08b-rke2/egress-selector.sh <étape>…   (journal : resultats/egress-selector-<étape>.log)
set -euo pipefail
export LC_ALL=C
export DISTRO=rke2

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
AVANT=${AVANT:?commit de la configuration d\'avant (variable AVANT)}
T=$W/egress-selector
mkdir -p "$T"
umask 077

poser() { # fichier : pose comme config.yaml de sc-confiance, redémarrage de rke2-server, attentes
  local d=/tmp/rke2-config
  sur sc-confiance "rm -rf $d && mkdir -m 0700 $d" </dev/null
  scp -q "${SSH_OPTS[@]}" "$1" "poc@${IP[sc-confiance]}:$d/config.yaml"
  sur sc-confiance "sudo install -m 0600 $d/config.yaml $D_CONF/config.yaml && rm -rf $d && sudo systemctl restart $D_SERVEUR" </dev/null
  echo "rke2-server redémarré à $(date -u +%H:%M:%S) UTC"
  sleep 15   # laisser l'ancien apiserver s'arrêter avant de sonder /readyz
  for _ in $(seq 60); do kubectl get --raw /readyz </dev/null >/dev/null 2>&1 && break; sleep 5; done
  kubectl get --raw /readyz </dev/null >/dev/null && echo "OK   /readyz à $(date -u +%H:%M:%S) UTC" || { echo "KO   apiserver non prêt" >&2; exit 1; }
  kubectl wait node --all --for=condition=Ready --timeout=300s </dev/null >/dev/null && echo "OK   trois nœuds Ready" || { echo "KO   nœuds non prêts" >&2; exit 1; }
  selecteur
}

selecteur() {
  local e
  e=$(args_apiserver | sed -n 's/^--egress-selector-config-file=//p' | head -1)
  echo "sélecteur de sortie de kube-apiserver : ${e:-argument absent}"
  [ -z "$e" ] || sur sc-confiance "sudo cat '$e'" </dev/null 2>/dev/null | grep -a -i -v -E 'jeton|token' | sed 's/^/     /'
}

etape_avant() {
  local r v
  git -C "$here" show "$AVANT:poc/bricks/08b-rke2/config/sc-confiance.yaml" > "$T/avant.yaml"
  r=$(sha256sum < "$T/avant.yaml" | cut -c1-64)
  v=$(sur sc-confiance "sudo sha256sum $D_CONF/config.yaml" </dev/null | cut -c1-64)
  [ "$v" = "$r" ] && echo "OK   config.yaml en place = version versionnée de $AVANT ($r)" \
    || { echo "KO   config.yaml en place ($v) diffère de la version de $AVANT ($r) : rien à poser" >&2; exit 1; }
  selecteur
}

etape_appliquer() {
  etape_avant
  echo "## pose de la nouvelle configuration (egress-selector-mode: disabled)"
  grep -n 'egress-selector-mode' "$here/config/sc-confiance.yaml"
  poser "$here/config/sc-confiance.yaml"
}

etape_retour() {
  git -C "$here" show "$AVANT:poc/bricks/08b-rke2/config/sc-confiance.yaml" > "$T/avant.yaml"
  echo "## retour à la configuration de $AVANT"
  poser "$T/avant.yaml"
}

lancer egress-selector "08b egress selector" "$@"
