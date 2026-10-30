#!/usr/bin/env bash
# Brique 08, jalon J1 : k3s v1.35.9+k3s1 dans les trois VM, sans exécuter install.sh.
#   Binaire et images système (airgap) copiés puis vérifiés par sha256 dans chaque VM ; unité systemd
#   et configuration versionnées (k3s/) ; server d'abord, avec un jeton de server et un jeton agent distincts
#   (aléatoires, 0600, ~/.cache/supply-chain-poc/08/secrets) ; puis les deux agents, qui ne reçoivent que
#   le jeton agent au format sécurisé (K10<empreinte de la CA>::…), après contrôle de cette empreinte ;
#   kubeconfig dédié ~/.kube/supply-chain-poc.yaml (0600), jamais fusionné dans ~/.kube/config.
#   RESEAU=cilium (J7, option 1b accordée par le propriétaire le 30/10/2026 ; défaut flannel) : server sans flannel ni kube-router
#   (k3s/sc-confiance-cilium.yaml en fichier d'appoint), HelmChart cilium (chart vérifié en base64) dans les manifestes du server,
#   archives OCI amd64 de Cilium avec les images airgap ; tout est préparé par cilium.sh telecharger et revérifié par sha256
#   dans chaque VM. Les nœuds ne sont prêts qu'une fois l'agent Cilium démarré.
#
# Usage (racine du dépôt) : mise run confiance:k3s
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}
K=$O/telechargements/k3s
K3S_SHA=897acb21cca57d477a211102251a6591450ce767344a9faaa121a1007ca9fa9a
K3S_IMG=k3s-airgap-images-amd64.tar.zst
K3S_IMG_SHA=7f1cbfea56d38f5e69aec13500a89290119096cc2f5a6d4f542e5f26599977d0
KUBECONFIG_POC=$HOME/.kube/supply-chain-poc.yaml
RESEAU=${RESEAU:-flannel}
CIL=$O/telechargements/cilium   # cilium.sh telecharger
case $RESEAU in flannel|cilium) ;; *) echo "RESEAU inconnu : $RESEAU" >&2; exit 1 ;; esac
declare -A IP=([sc-confiance]=192.168.161.11 [sc-build]=192.168.161.12 [sc-stockage]=192.168.161.13)
SSH_OPTS=(-i "$O/ssh/id_ed25519" -o UserKnownHostsFile="$O/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
mkdir -p "$R" "$O/travail"
exec > >(tee "$R/k3s.log") 2>&1
echo "# k3s.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), réseau $RESEAU"
chrono() { printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }
sur() { local vm=$1; shift; ssh "${SSH_OPTS[@]}" "poc@${IP[$vm]}" "$@"; }

(cd "$K" && printf '%s  k3s\n%s  %s\n' "$K3S_SHA" "$K3S_IMG_SHA" "$K3S_IMG" | sha256sum -c --quiet)
if [ "$RESEAU" = cilium ]; then
  [ -s "$CIL/sums.txt" ] || { echo "archives de Cilium absentes : mise run confiance:cilium -- telecharger" >&2; exit 1; }
  (cd "$CIL" && sha256sum -c --quiet sums.txt) && echo "archives de Cilium conformes à $CIL/sums.txt"
fi
mkdir -p "$O/secrets" && chmod 0700 "$O/secrets"
for j in k3s-jeton-serveur k3s-jeton-agent; do
  [ -s "$O/secrets/$j" ] || (umask 077 && openssl rand -hex 32 > "$O/secrets/$j")
done

installer() { # vm server|agent
  local vm=$1 role=$2 unite d=/tmp/k3s-installation
  if [ "$role" = server ]; then unite=k3s; else unite=k3s-agent; fi
  sed "s/@ROLE@/$role/" "$here/k3s/k3s.service.in" > "$O/travail/$unite.service"
  local j=$O/travail/jetons-$vm
  rm -rf "$j" && (umask 077 && mkdir -p "$j")
  if [ "$role" = server ]; then
    cp "$O/secrets/k3s-jeton-serveur" "$j/jeton"
    cp "$O/secrets/k3s-jeton-agent" "$j/jeton-agent"
  else
    cp "$O/secrets/k3s-jeton-agent-securise" "$j/jeton"
  fi
  local fichiers=("$K/k3s" "$K/$K3S_IMG" "$here/k3s/$vm.yaml" "$O/travail/$unite.service" "$j"/*)
  if [ "$role" = server ]; then fichiers+=("$here/k3s/audit-policy.yaml"); fi
  local sommes="" reseau=":"
  if [ "$RESEAU" = cilium ]; then
    fichiers+=("$CIL/cilium-amd64.tar")
    sommes=$(grep ' cilium-amd64.tar$' "$CIL/sums.txt")
    reseau="install -m 0644 cilium-amd64.tar /var/lib/rancher/k3s/agent/images/cilium-amd64.tar"
    if [ "$role" = server ]; then
      fichiers+=("$CIL/operator-generic-amd64.tar" "$CIL/cilium-helmchart.yaml" "$here/k3s/sc-confiance-cilium.yaml")
      sommes=$(grep -E ' (cilium|operator-generic)-amd64.tar$| cilium-helmchart.yaml$' "$CIL/sums.txt")
      reseau="$reseau; install -m 0644 operator-generic-amd64.tar /var/lib/rancher/k3s/agent/images/operator-generic-amd64.tar"
      reseau="$reseau; install -d -m 0700 /etc/rancher/k3s/config.yaml.d /var/lib/rancher/k3s/server/manifests"
      reseau="$reseau; install -m 0600 sc-confiance-cilium.yaml /etc/rancher/k3s/config.yaml.d/reseau.yaml"
      reseau="$reseau; install -m 0600 cilium-helmchart.yaml /var/lib/rancher/k3s/server/manifests/cilium.yaml"
    fi
  fi
  sur "$vm" "rm -rf $d && mkdir -m 0700 $d"
  scp -q "${SSH_OPTS[@]}" "${fichiers[@]}" "poc@${IP[$vm]}:$d/"
  sur "$vm" sudo bash -s <<EOF
set -euo pipefail
cd $d
printf '%s  k3s\n%s  %s\n' "$K3S_SHA" "$K3S_IMG_SHA" "$K3S_IMG" | sha256sum -c
if [ -n "$sommes" ]; then printf '%s\n' "$sommes" | sha256sum -c; fi
install -m 0755 k3s /usr/local/bin/k3s
install -d -m 0755 /var/lib/rancher/k3s/agent/images
install -m 0644 $K3S_IMG /var/lib/rancher/k3s/agent/images/$K3S_IMG
$reseau
install -d -m 0700 /etc/rancher/k3s
install -m 0600 $vm.yaml /etc/rancher/k3s/config.yaml
install -m 0600 jeton /etc/rancher/k3s/jeton
if [ -f jeton-agent ]; then install -m 0600 jeton-agent /etc/rancher/k3s/jeton-agent; fi
if [ -f audit-policy.yaml ]; then
  install -m 0600 audit-policy.yaml /etc/rancher/k3s/audit-policy.yaml
  install -d -m 0700 /var/lib/rancher/k3s/server/logs
fi
install -m 0644 $unite.service /etc/systemd/system/$unite.service
systemctl daemon-reload
systemctl enable --now $unite
cd / && rm -rf $d
/usr/local/bin/k3s --version | sed -n 1p   # sed lit tout : pas de SIGPIPE sous pipefail
EOF
  rm -rf "$O/travail/$unite.service" "$j"
  echo "$vm : k3s $role installé"
}

pret() { # nœuds attendus…
  for _ in $(seq 90); do
    local ok=0
    for n in "$@"; do
      if sur sc-confiance "sudo k3s kubectl get node $n -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" 2>/dev/null | grep -x True >/dev/null; then
        ok=$((ok + 1))
      fi
    done
    [ "$ok" -eq $# ] && return 0
    sleep 4
  done
  echo "nœuds non prêts : $*" >&2; return 1
}

chrono "J1 installation de k3s"
installer sc-confiance server
pret sc-confiance
chrono "J1 server prêt"

# Jeton agent au format sécurisé : K10<sha256 du certificat PEM de la CA du server>::<identifiants>.
(umask 077 && sur sc-confiance "sudo cat /var/lib/rancher/k3s/server/agent-token" > "$O/secrets/k3s-jeton-agent-securise")
ca=$(sur sc-confiance "sudo sha256sum /var/lib/rancher/k3s/server/tls/server-ca.crt" | cut -d' ' -f1)
jeton=$(cat "$O/secrets/k3s-jeton-agent-securise")
case $jeton in
  "K10$ca::"*) echo "jeton agent sécurisé : empreinte de la CA du server ${ca:0:16}… vérifiée" ;;
  *) echo "jeton agent sans l'empreinte attendue de la CA" >&2; exit 1 ;;
esac
if [ "${jeton#*::}" = "$(cat "$O/secrets/k3s-jeton-serveur")" ] || [ "${jeton#*::}" = "server:$(cat "$O/secrets/k3s-jeton-serveur")" ]; then
  echo "le jeton agent contient le jeton du server" >&2; exit 1
fi
installer sc-build agent
installer sc-stockage agent
pret sc-confiance sc-build sc-stockage
chrono "J1 trois nœuds prêts"

mkdir -p "$(dirname "$KUBECONFIG_POC")"
(umask 077 && sur sc-confiance "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed -e 's#https://127.0.0.1:6443#https://192.168.161.11:6443#' -e 's/: default$/: supply-chain-poc/' > "$KUBECONFIG_POC")
echo "kubeconfig : $KUBECONFIG_POC ($(stat -c %a "$KUBECONFIG_POC"))"
sur sc-confiance "sudo k3s kubectl get nodes -o wide -L zone"
