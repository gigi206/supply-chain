#!/usr/bin/env bash
# Brique 08, jalon J1 : contrôles des nœuds (poc/infra, « Contrôles au premier démarrage ») et du cluster.
#   Dans chaque VM : noyau, niveau x86-64 (ld.so), AVX-512 absent, mémoire, disque, sortie par le NAT ;
#   dans sc-build : /dev/kvm et kvm_intel ; cluster : version, nœuds, zones et taints, pods, images ;
#   sur l'hôte : RSS des processus QEMU (RAM réellement prise).
#
# Usage (racine du dépôt) : mise run confiance:controles [-- <libellé>]   (journal : resultats/controles-<libellé>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
lib=${1:-j1}
mkdir -p "$R"
exec > >(tee "$R/controles-$lib.log") 2>&1
echo "# controles.sh $lib, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
s() { "$here/ssh.sh" "$@" < /dev/null; }

for vm in sc-confiance sc-build sc-stockage; do
  echo "## $vm"
  s "$vm" 'set -u
    echo "noyau : $(uname -r) ; vCPU : $(nproc) ; modèle : $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2-)"
    /lib64/ld-linux-x86-64.so.2 --help | grep -E "x86-64-v[234]"
    echo "drapeaux avx512 : $(grep -o "avx512[a-z_]*" /proc/cpuinfo | sort -u | wc -l)"
    echo "vmx : $(grep "^flags" /proc/cpuinfo | grep -c -w vmx || true) vCPU sur $(nproc)"
    if [ -e /dev/kvm ]; then ls -l /dev/kvm; lsmod | grep -E "^kvm(_intel)? " || true; else echo "/dev/kvm absent"; fi
    free -m | sed -n 1,2p
    df -h / | tail -1
    echo "sortie NAT (deb.debian.org) : $(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 https://deb.debian.org/debian/ || echo échec)"
    systemctl is-active k3s k3s-agent 2>/dev/null | paste -sd" " || true'
done

echo "## cluster"
s sc-confiance 'sudo k3s --version | head -1
  sudo k3s kubectl get nodes -o wide -L zone
  sudo k3s kubectl get nodes -o custom-columns=NŒUD:.metadata.name,TAINTS:.spec.taints
  sudo k3s kubectl get pods -A -o wide
  if sudo k3s kubectl get ds -n kube-system cilium >/dev/null 2>&1; then
    echo "contrôleur réseau et de NetworkPolicy (Cilium) : DaemonSet $(sudo k3s kubectl get ds -n kube-system cilium -o jsonpath="{.status.numberReady}/{.status.desiredNumberScheduled}") prêt"
  else echo "contrôleur de NetworkPolicy (kube-router) : $(sudo iptables -S | grep -c KUBE-ROUTER || true) règles KUBE-ROUTER"; fi
  sudo k3s kubectl top nodes 2>/dev/null || echo "metrics-server pas encore prêt"'
for vm in sc-confiance sc-build sc-stockage; do
  echo "## images système sur $vm"
  s "$vm" 'sudo k3s crictl images 2>/dev/null | tail -n +2 | awk "{print \$1\":\"\$2\" \"\$3}"'
done

echo "## hôte : RSS des processus QEMU"
for vm in sc-confiance sc-build sc-stockage; do
  pid=$(pgrep -f "guest=$vm," | head -1 || true)
  if [ -n "$pid" ]; then echo "$vm : $(( $(ps -o rss= -p "$pid") / 1024 )) Mo"; else echo "$vm : pas de processus"; fi
done
free -m | sed -n 1,2p
