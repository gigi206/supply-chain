#!/usr/bin/env bash
# Agrandissement à chaud du disque de sc-stockage, de 20G à 30G (décision « Agrandir maintenant » du 20/11/2026).
# Hôte : virsh blockresize sur qemu:///system (sans sudo de l'hôte). VM : growpart de vda1 puis resize2fs en ligne,
# par le sudo du compte poc. Rien n'est arrêté ni redémarré. vm.sh n'est pas modifié : un rejeu de zéro reprend 20G.
#
# Usage (racine du dépôt) : env -u SSH_AUTH_SOCK DISTRO=rke2 bash poc/bricks/05-rpm-mock/resultats/sc-stockage-agrandir.sh avant|agrandir|apres
set -euo pipefail
export LC_ALL=C
here=$PWD/poc/bricks/08-trust-plane
. "$here/commun.sh" > /dev/null
VM=sc-stockage
CIBLE=30G
v() { virsh -c qemu:///system "$@"; }
releve() {
  date -u +%FT%TZ
  v domstate "$VM"
  v domblkinfo "$VM" vda | grep -E '^(Capacity|Capacité)'
  sur "$VM" "lsblk -b -n -o NAME,SIZE /dev/vda /dev/vda1; df -B1M --output=used,avail,size /; findmnt -no FSTYPE /" </dev/null
  sur "$VM" "for s in zot loki prometheus forgejo grafana alloy rke2-agent; do printf '%s %s\n' \$s \$(systemctl is-active \$s); done" </dev/null
  echo "dépôts du catalogue de Zot (lecture anonyme) : $(SSL_CERT_FILE=$P/ca-poc.crt DOCKER_CONFIG=/nonexistent mise exec -- crane catalog "$REG_HOTE" | wc -l)"
}
case ${1:-} in
  avant|apres) echo "## $1"; releve ;;
  agrandir)
    echo "## agrandir"
    date -u +%FT%TZ
    v blockresize "$VM" vda "$CIBLE"
    echo "blockresize : rc $?"
    sur "$VM" "sudo growpart /dev/vda 1; echo growpart : rc \$?; sudo resize2fs /dev/vda1 2>&1; echo resize2fs : rc \$?" </dev/null
    date -u +%FT%TZ ;;
  *) echo "usage : $0 avant|agrandir|apres" >&2; exit 2 ;;
esac
