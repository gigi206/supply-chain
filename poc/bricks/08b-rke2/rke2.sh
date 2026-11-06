#!/usr/bin/env bash
# Brique 08b : RKE2 v1.35.9+rke2r1 dans les trois VM à la place de k3s (décision du propriétaire du 05/11/2026), durci par profile: cis,
# sans exécuter install.sh. Pendant de k3s.sh, appelé par rejeu.sh avec DISTRO=rke2.
#   telecharger  sur l'hôte, sans toucher au cluster : archive et images de RKE2 (sha256 de sha256sum-amd64.txt), charts rke2-coredns et
#                rke2-metrics-server, manifeste de local-path-provisioner, épinglés par sha256 après revue ; archives OCI amd64 de
#                local-path-provisioner et de busybox (absentes des images de RKE2), épinglées par digest ; kube-bench
#   rendu        à sec : manifeste de local-path, charts et valeurs de Cilium rendus sans cluster, écart avec k3s
#   installer    archive et images copiées puis vérifiées dans chaque VM ; profil cis (compte etcd, sysctl) ; configuration versionnée ; server
#                d'abord, jetons distincts ; dès que l'API répond : Cilium, CoreDNS, metrics-server et local-path-provisioner depuis l'hôte
#                (D1 a et D2 a : aucun HelmChart, donc aucun compte helm-*) ; puis les deux agents, avec le jeton agent au format sécurisé
#   cis          après le rejeu, en lecture seule : kube-bench sur le server et sur un agent (D5 a). kube-bench v0.16.0 n'a pas de profil RKE2
#                pour Kubernetes 1.35 : rke2-cis-1.9, le plus récent par version de CIS, dans ses limites
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08b-rke2/rke2.sh <étape>…   (journal : resultats/rke2-<étape>.log)
set -euo pipefail
export LC_ALL=C
export DISTRO=rke2

here=$(cd "$(dirname "$0")" && pwd)
b08=$here/../08-trust-plane
. "$b08/commun.sh"
RKE2_TAG=v1.35.9+rke2r1
RKE2_URL=https://github.com/rancher/rke2/releases/download/v1.35.9%2Brke2r1
RKE2_TGZ=rke2.linux-amd64.tar.gz
RKE2_TGZ_SHA=e2ed0b37d06d16d823289c0117e43d98c7677d65b778ae4370827243776c295e
RKE2_IMG=rke2-images-core.linux-amd64.tar.zst
RKE2_IMG_SHA=f9e1c9f66545618b1ae736a40b01c0087b17e9ab98b0d747bc91ef4c6da56abd
COREDNS=rke2-coredns-1.47.102
COREDNS_SHA=2ce253185dab4580da015a0107b8ec7e2b1591e9019466afcc7c42ce88ead9ca
METRICS=rke2-metrics-server-3.14.001
METRICS_SHA=8dbc13c9d3d25ba7fc4de120b8a643b73be737f5a9a17b821c5bf5a44b795892
LP_TAG=v0.0.37
LP_MANIFESTE_SHA=9781b39c24f3f651bd6d6e41b561e04e4904bbdb6d4f8c7a6009df3a702dcd65
LP_IMAGE=docker.io/rancher/local-path-provisioner
LP_AMD64=sha256:c3f2c60ee2490eb83ac00101d7e239fd8c20a5b8b4038e2dfc36a7e66fe99c08
BB_IMAGE=docker.io/rancher/mirrored-library-busybox
BB_TAG=1.37.0
BB_AMD64=sha256:ad9fa4d07136a83e69a54ef00102f579d04eba431932de3b0f098cc5d5948f9f   # celui de kata.sh
KB=kube-bench_0.16.0_linux_amd64.tar.gz
KB_SHA=82dbc7e598740dc9344d41f8ad0b8210d57c4c00bdb2c5f1d8a69a2b98baddcf
CIS_PROFIL=rke2-cis-1.9
C=$here/config
A=$HOME/.cache/supply-chain-poc/08b/telechargements
T=$W/rke2
mkdir -p "$A" "$T"

somme() { echo "$2  $1" | (cd "$A" && sha256sum -c --quiet) && echo "OK   $1"; }
recuperer() { # fichier url sha256 : téléchargé une fois, revérifié à chaque passage
  [ -s "$A/$1" ] || curl -fsSL -o "$A/$1" "$2"
  somme "$1" "$3"
}

archive() { # image tag digest nom : archive OCI amd64, nommée par tag et par digest, comme cilium.sh archive
  local l=$T/$4-oci
  rm -rf -- "${T:?}/$4-oci"
  crane pull --format oci "$1@$3" "$l"
  jq --arg t "$1:$2" --arg d "$1@$3" --arg v "$2" \
    '.manifests = [(.manifests[0] + {annotations: {"io.containerd.image.name": $t, "org.opencontainers.image.ref.name": $v}}),
                   (.manifests[0] + {annotations: {"io.containerd.image.name": $d}})]' "$l/index.json" > "$l/index.tmp"
  mv "$l/index.tmp" "$l/index.json"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$l" -cf "$A/$4-amd64.tar" oci-layout index.json blobs
  echo "$4 : archive $(du -m "$A/$4-amd64.tar" | cut -f1) Mo"
}

etape_telecharger() {
  recuperer "$RKE2_TGZ" "$RKE2_URL/$RKE2_TGZ" "$RKE2_TGZ_SHA"
  recuperer "$RKE2_IMG" "$RKE2_URL/$RKE2_IMG" "$RKE2_IMG_SHA"
  recuperer "$COREDNS.tgz" "https://rke2-charts.rancher.io/assets/rke2-coredns/$COREDNS.tgz" "$COREDNS_SHA"
  recuperer "$METRICS.tgz" "https://rke2-charts.rancher.io/assets/rke2-metrics-server/$METRICS.tgz" "$METRICS_SHA"
  recuperer local-path-storage.yaml "https://raw.githubusercontent.com/rancher/local-path-provisioner/$LP_TAG/deploy/local-path-storage.yaml" "$LP_MANIFESTE_SHA"
  recuperer "$KB" "https://github.com/aquasecurity/kube-bench/releases/download/v0.16.0/$KB" "$KB_SHA"
  archive "$LP_IMAGE" "$LP_TAG" "$LP_AMD64" local-path
  archive "$BB_IMAGE" "$BB_TAG" "$BB_AMD64" busybox
  (cd "$A" && sha256sum local-path-amd64.tar busybox-amd64.tar > sums.txt)
  sed 's/^/  /' "$A/sums.txt"
  [ ! -s "$O/telechargements/cilium/sums.txt" ] || (cd "$O/telechargements/cilium" && sha256sum -c --quiet sums.txt) && echo "OK   archives de Cilium"
  du -sm "$A" | awk '{print "téléchargements : " $1 " Mo"}'
}

verifier_hote() {
  somme "$RKE2_TGZ" "$RKE2_TGZ_SHA"; somme "$RKE2_IMG" "$RKE2_IMG_SHA"
  somme "$COREDNS.tgz" "$COREDNS_SHA"; somme "$METRICS.tgz" "$METRICS_SHA"; somme local-path-storage.yaml "$LP_MANIFESTE_SHA"
  (cd "$A" && sha256sum -c --quiet sums.txt) && echo "OK   archives de local-path et de busybox"
  (cd "$O/telechargements/cilium" && sha256sum -c --quiet sums.txt) && echo "OK   archives de Cilium"
}

installer() { # vm server|agent
  local vm=$1 role=$2
  local unite=rke2-$role d=/tmp/rke2-installation j=$W/jetons-$vm cil=$O/telechargements/cilium   # second local : $vm n'existe qu'après le premier
  rm -rf -- "${j:?}" && (umask 077 && mkdir -p "$j")
  if [ "$role" = server ]; then
    cp "$S/rke2-jeton-serveur" "$j/jeton"; cp "$S/rke2-jeton-agent" "$j/jeton-agent"
  else
    cp "$S/rke2-jeton-agent-securise" "$j/jeton"
  fi
  local fichiers=("$A/$RKE2_TGZ" "$A/$RKE2_IMG" "$A/local-path-amd64.tar" "$A/busybox-amd64.tar" "$cil/cilium-amd64.tar" "$C/$vm.yaml" "$j"/*)
  local sommes="$RKE2_TGZ_SHA  $RKE2_TGZ
$RKE2_IMG_SHA  $RKE2_IMG
$(cat "$A/sums.txt")
$(grep ' cilium-amd64.tar$' "$cil/sums.txt")"
  if [ "$role" = server ]; then
    fichiers+=("$cil/operator-generic-amd64.tar" "$C/audit-policy.yaml")
    sommes="$sommes
$(grep ' operator-generic-amd64.tar$' "$cil/sums.txt")"
  fi
  sur "$vm" "rm -rf $d && mkdir -m 0700 $d"
  scp -q "${SSH_OPTS[@]}" "${fichiers[@]}" "poc@${IP[$vm]}:$d/"
  sur "$vm" sudo bash -s <<EOF
set -euo pipefail
cd $d
sha256sum -c --quiet <<'SOMMES'
$sommes
SOMMES
tar -xzf $RKE2_TGZ -C /usr/local --no-same-owner bin share lib/systemd/system
install -m 0644 /usr/local/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
systemctl restart systemd-sysctl
id etcd >/dev/null 2>&1 || useradd -r -c "etcd user" -s /usr/sbin/nologin -M -U etcd
install -d -m 0755 $D_ETAT/agent/images
install -m 0644 $RKE2_IMG local-path-amd64.tar busybox-amd64.tar cilium-amd64.tar $D_ETAT/agent/images/
if [ -f operator-generic-amd64.tar ]; then install -m 0644 operator-generic-amd64.tar $D_ETAT/agent/images/; fi
install -d -m 0700 $D_CONF
install -m 0600 $vm.yaml $D_CONF/config.yaml
install -m 0600 jeton $D_CONF/jeton
if [ -f jeton-agent ]; then install -m 0600 jeton-agent $D_CONF/jeton-agent; fi
if [ -f audit-policy.yaml ]; then
  install -m 0600 audit-policy.yaml $D_CONF/audit-policy.yaml
  install -d -m 0700 $D_ETAT/server/logs
fi
systemctl daemon-reload
systemctl enable --now $unite
cd / && rm -rf $d
/usr/local/bin/rke2 --version | sed -n 1p
EOF
  rm -rf -- "${j:?}"
  echo "$vm : RKE2 $role installé"
}

pret() { # nœuds attendus…
  for _ in $(seq 120); do
    local ok=0 n
    for n in "$@"; do
      if kubectl get node "$n" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -x True >/dev/null; then ok=$((ok + 1)); fi
    done
    [ "$ok" -eq $# ] && return 0
    sleep 4
  done
  echo "KO   nœuds non prêts : $*" >&2; return 1
}

kubeconfig() { # même kubeconfig dédié que k3s.sh
  mkdir -p "$(dirname "$KUBECONFIG")"
  (umask 077 && sur sc-confiance "sudo cat $D_CONF/rke2.yaml" \
    | sed -e 's#https://127.0.0.1:6443#https://192.168.161.11:6443#' -e 's/: default$/: supply-chain-poc/' > "$KUBECONFIG")
  echo "kubeconfig : $(stat -c %a "$KUBECONFIG")"
}

rendre_local_path() { # manifeste de la release, épinglé par sha256, image par digest ; volumes au chemin que lit fuites.sh ; busybox de l'archive
  sed -e "s#\"paths\":\[\"/opt/local-path-provisioner\"\]#\"paths\":[\"$D_ETAT/storage\"]#" \
      -e "s#image: docker.io/rancher/local-path-provisioner:$LP_TAG#image: $LP_IMAGE@$LP_AMD64#" \
      -e "s#image: docker.io/library/busybox#image: $BB_IMAGE@$BB_AMD64#" "$A/local-path-storage.yaml" > "$T/local-path.yaml"
  grep -q "$LP_AMD64" "$T/local-path.yaml" && grep -q "$BB_AMD64" "$T/local-path.yaml" && grep -q "$D_ETAT/storage" "$T/local-path.yaml" \
    || { echo "KO   manifeste de local-path non rendu" >&2; exit 1; }
}

composants() { # depuis l'hôte, comme Cilium (D1 a) : ni HelmChart, ni compte helm-*
  helm upgrade --install rke2-coredns "$A/$COREDNS.tgz" --namespace kube-system -f "$C/valeurs-coredns.yaml" \
    --server-side=true --wait=watcher --timeout 5m --hide-notes
  helm upgrade --install rke2-metrics-server "$A/$METRICS.tgz" --namespace kube-system \
    --server-side=true --wait=watcher --timeout 5m --hide-notes
  # local-path-provisioner (D2 a) : classe par défaut, comme celle de k3s, dont les workspaces des pipelines dépendent. Les pods auxiliaires
  # montent des hostPath : espace en privileged, hors du défaut restricted du profil cis.
  rendre_local_path
  kubectl create namespace local-path-storage --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label --overwrite namespace local-path-storage pod-security.kubernetes.io/enforce=privileged >/dev/null
  kubectl apply --server-side -f "$T/local-path.yaml" >/dev/null
  kubectl annotate --overwrite storageclass local-path storageclass.kubernetes.io/is-default-class=true >/dev/null
  kubectl rollout status -n local-path-storage deploy/local-path-provisioner --timeout=300s >/dev/null
  echo "OK   CoreDNS, metrics-server et local-path-provisioner depuis l'hôte ; classe par défaut : $(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name} {end}')"
}

etape_rendu() { # à sec, sans toucher au cluster : ce que recevrait RKE2, et ce qui ne doit pas changer pour k3s
  local h=$T/rendu c=$O/telechargements/cilium
  rm -rf -- "${T:?}/rendu"; mkdir -p "$h"
  verifier_hote
  rendre_local_path
  echo "OK   local-path : $(grep -c "$LP_AMD64\|$BB_AMD64" "$T/local-path.yaml") images par digest, chemin $(grep -o "\"paths\":\[[^]]*\]" "$T/local-path.yaml")"
  sed "s#/etc/rancher/k3s#$D_CONF#" "$b08/stockage/registries.yaml" | grep -n ca_file
  helm template rke2-coredns "$A/$COREDNS.tgz" --namespace kube-system -f "$C/valeurs-coredns.yaml" > "$h/coredns.yaml"
  helm template rke2-metrics-server "$A/$METRICS.tgz" --namespace kube-system > "$h/metrics.yaml"
  echo "CoreDNS : $(grep -c 'k8s-app: kube-dns$' "$h/coredns.yaml") label(s) kube-dns, clusterIP $(awk '/clusterIP:/ {print $2}' "$h/coredns.yaml") ; metrics-server : $(grep -c 'app: rke2-metrics-server$' "$h/metrics.yaml") label(s)"
  sed -e 's/^#.*//' -e 's#@CILIUM_AMD64@#sha256:fa56fecd779584642c7ec2da6872c03c45c1f1043da66665a73ed8c425584d54#' -e 's#@OPERATOR_AMD64@#sha256:77a9b4371faed41dc9c2fb3942b6c02a581158be1d4aa46a0e62956ce2f55ff1#' "$b08/cilium/valeurs.yaml" > "$h/valeurs.yaml"
  helm template cilium "$c/cilium-1.20.4.tgz" --namespace kube-system -f "$h/valeurs.yaml" -f "$C/valeurs-cilium.yaml" > "$h/cilium-rke2.yaml"
  helm template cilium "$c/cilium-1.20.4.tgz" --namespace kube-system -f "$h/valeurs.yaml" > "$h/cilium-k3s.yaml"
  echo "## ConfigMap cilium-config, RKE2 contre k3s (seules ces clés doivent différer)"
  diff <(grep -E '^  [a-z0-9-]+: ' "$h/cilium-k3s.yaml" | sort -u) <(grep -E '^  [a-z0-9-]+: ' "$h/cilium-rke2.yaml" | sort -u) | grep '^[<>]' | cut -c1-90 || true
  echo "l7 : $(grep -E '^  (enable-l7-proxy|enable-envoy-config|external-envoy-proxy):' "$h/cilium-rke2.yaml" | tr -s ' ' | paste -sd,)"
}

etape_installer() {
  local j ca
  verifier_hote
  for j in rke2-jeton-serveur rke2-jeton-agent; do
    [ -s "$S/$j" ] || (umask 077 && openssl rand -hex 32 > "$S/$j")
  done
  chrono "08b installation de RKE2"
  installer sc-confiance server
  for _ in $(seq 150); do
    sur sc-confiance "sudo $D_KUBECTL get --raw /readyz" 2>/dev/null | grep -x ok >/dev/null && break
    sleep 2
  done
  sur sc-confiance "sudo $D_KUBECTL get --raw /readyz" | grep -x ok >/dev/null && echo "API du server prête (/readyz)"
  kubeconfig
  "$b08/cilium.sh" installer
  pret sc-confiance
  chrono "08b server prêt"
  composants
  # Jeton agent au format sécurisé, contrôlé comme dans k3s.sh.
  (umask 077 && sur sc-confiance "sudo cat $D_ETAT/server/agent-token" > "$S/rke2-jeton-agent-securise")
  ca=$(sur sc-confiance "sudo sha256sum $D_ETAT/server/tls/server-ca.crt" | cut -d' ' -f1)
  j=$(cat "$S/rke2-jeton-agent-securise")
  case $j in
    "K10$ca::"*) echo "jeton agent sécurisé : empreinte de la CA du server ${ca:0:16}… vérifiée" ;;
    *) echo "KO   jeton agent sans l'empreinte attendue de la CA" >&2; exit 1 ;;
  esac
  if [ "${j#*::}" = "$(cat "$S/rke2-jeton-serveur")" ] || [ "${j#*::}" = "server:$(cat "$S/rke2-jeton-serveur")" ]; then
    echo "KO   le jeton agent contient le jeton du server" >&2; exit 1
  fi
  installer sc-build agent
  installer sc-stockage agent
  pret sc-confiance sc-build sc-stockage
  chrono "08b trois nœuds prêts"
  kubectl get nodes -o wide -L zone
  echo "HelmChart : $(kubectl get helmcharts -A --no-headers 2>/dev/null | wc -l) ; attendu 0 (D1 a)"
  echo "kube-proxy : $(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c '^kube-proxy' || true) pod ; attendu 0"
  echo "chiffrement des Secrets : $(sur sc-confiance "sudo /usr/local/bin/rke2 secrets-encrypt status" | sed -n 1p)"
}

etape_cis() {
  local vm
  somme "$KB" "$KB_SHA"
  for vm in sc-confiance sc-build; do
    copier "$vm" /tmp/kube-bench "$A/$KB"
    echo "## $vm, profil $CIS_PROFIL (Kubernetes 1.35 : profil le plus proche, pas le sien)"
    sur "$vm" "cd /tmp/kube-bench && tar -xzf $KB && sudo ./kube-bench run --benchmark $CIS_PROFIL --config-dir cfg --config cfg/config.yaml --noremediations 2>&1 | grep -E '^\[(FAIL|WARN)\]|== Summary|checks (PASS|FAIL|WARN|INFO)|^[0-9]+ checks' ; rm -rf /tmp/kube-bench" || echo "KO   kube-bench sur $vm"
  done
}

for e in "$@"; do
  { echo "# rke2.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/rke2-$e.log"
  [ "${PIPESTATUS[0]}" = 0 ] || exit 1
done
