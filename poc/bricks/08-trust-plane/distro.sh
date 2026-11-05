# Brique 08b : ce qui diffère entre k3s et RKE2 (décision du propriétaire du 05/11/2026). Chargé par commun.sh, controles.sh, fuites.sh
# et vm.sh. DISTRO=k3s reste le défaut tant que le rejeu sous RKE2 n'a pas passé : le cluster en service et le relevé du 06/11/2026
# gardent exactement leurs chemins. DISTRO=rke2 : rke2.sh (brique 08b) à la place de k3s.sh. Les valeurs D_CRICTL, D_CTR et D_KUBECTL
# sont des commandes à passer à sudo sur le nœud.
DISTRO=${DISTRO:-k3s}
case $DISTRO in
  k3s)
    D_CONF=/etc/rancher/k3s                # configuration, ca-poc.crt, registries.yaml, audit-policy.yaml, pod-security.yaml
    D_ETAT=/var/lib/rancher/k3s            # server/logs (audit), server/tls, agent/etc/containerd, storage (local-path)
    D_SERVEUR=k3s                          # unités systemd
    D_AGENT=k3s-agent
    D_VERSION="k3s --version"
    D_KUBECTL="k3s kubectl"
    D_CRICTL="k3s crictl"
    D_CTR="k3s ctr"
    D_SERVING=k3s-serving                  # Secret de kube-system, cible des refus de lecture de preuves.sh
    D_LP_NS=kube-system                    # espace de local-path-provisioner
    ;;
  rke2)
    D_CONF=/etc/rancher/rke2
    D_ETAT=/var/lib/rancher/rke2
    D_SERVEUR=rke2-server
    D_AGENT=rke2-agent
    D_VERSION="/usr/local/bin/rke2 --version"
    D_KUBECTL="/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"
    D_CRICTL="env CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml /var/lib/rancher/rke2/bin/crictl"
    D_CTR="/var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock"
    D_SERVING=rke2-serving
    D_LP_NS=local-path-storage
    ;;
  *) echo "DISTRO inconnue : $DISTRO" >&2; exit 1 ;;
esac

args_apiserver() { # arguments de kube-apiserver sur sc-confiance, un par ligne : journal de k3s (dernier lancement), ou manifeste du
  # pod statique sous RKE2, où kube-apiserver n'est pas un processus de l'unité
  if [ "$DISTRO" = k3s ]; then
    sur sc-confiance "sudo journalctl -u $D_SERVEUR --no-pager -o cat | grep 'Running kube-apiserver' | tail -n 1" | tr ' ' '\n'
  else
    sur sc-confiance "sudo sed -n 's/^ *- \"\\{0,1\\}\\(--[^\"]*\\)\"\\{0,1\\}$/\\1/p' $D_ETAT/agent/pod-manifests/kube-apiserver.yaml"
  fi
}
