#!/usr/bin/env bash
# Brique 08 : pool, réseau et trois VM libvirt (qemu:///system, sans sudo).
#   creer    : pool supply-chain-poc (/var/lib/libvirt/supply-chain-poc, créé par libvirtd), réseau NAT
#              supply-chain-poc (libvirt/reseau.xml), pour chaque VM un disque qcow2 tiré de l'image
#              Debian vérifiée (confiance:preparer) et une graine cloud-init (clés générées sur l'hôte),
#              puis démarrage et attente de SSH ;
#   demarrer : réseau puis VM ;  arreter : VM puis réseau ;
#   detruire : VM, volumes, pool (et son répertoire), réseau, fichiers de travail. Les téléchargements
#              et les secrets restent dans ~/.cache/supply-chain-poc/08.
# Aucun démarrage automatique ; les VM et réseaux personnels ne sont pas touchés.
#
# Usage (racine du dépôt) : mise run confiance:vm -- creer|demarrer|arreter|detruire
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}
IMG=$O/telechargements/debian/debian-13-generic-amd64-20261026-2643.qcow2
SHA512=5bd891c6e62d01639f52a5587b72a4607421e445732214be787dba6043cf9797a6ff90bed982aada6a6c7e619f1f956d961c4fad76757171abd607920aac098a
POOL=supply-chain-poc
POOL_DIR=/var/lib/libvirt/supply-chain-poc
NET=supply-chain-poc
VMS=(sc-confiance sc-build sc-stockage)
declare -A TAILLE=([sc-confiance]=15G [sc-build]=30G [sc-stockage]=20G)
declare -A IP=([sc-confiance]=192.168.161.11 [sc-build]=192.168.161.12 [sc-stockage]=192.168.161.13)
S=$O/ssh
W=$O/travail
v() { virsh -c qemu:///system "$@"; }
liste() { case $1 in net) v net-list --name "${@:2}" ;; pool) v pool-list --name "${@:2}" ;; dom) v list --name "${@:2}" ;; esac; }
existe() { liste "$1" --all | grep -qxF "$2"; }
actif() { liste "$1" | grep -qxF "$2"; }
chrono() { mkdir -p "$R"; printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }
televerser() { # fichier volume format
  local taille
  taille=$(stat -c %s "$1")
  v vol-create-as "$POOL" "$2" "$taille" --format "$3" >/dev/null
  v vol-upload --pool "$POOL" --sparse "$2" "$1"
}

cles() {
  mkdir -p "$S" && chmod 0700 "$S"
  [ -f "$S/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C supply-chain-poc-08 -f "$S/id_ed25519"
  : > "$S/known_hosts.tmp"
  for vm in "${VMS[@]}"; do
    [ -f "$S/hote-$vm" ] || ssh-keygen -q -t ed25519 -N '' -C "$vm" -f "$S/hote-$vm"
    printf '%s,%s.poc.test,%s %s\n' "$vm" "$vm" "${IP[$vm]}" "$(cut -d' ' -f1-2 "$S/hote-$vm.pub")" >> "$S/known_hosts.tmp"
  done
  mv "$S/known_hosts.tmp" "$S/known_hosts"
}

graine() { # vm
  local vm=$1 d=$W/graine-$1
  rm -rf "$d" && mkdir -p "$d" && chmod 0700 "$d"
  printf 'instance-id: %s-1\nlocal-hostname: %s\n' "$vm" "$vm" > "$d/meta-data"
  awk -v hote="$vm" -v pub="$(cut -d' ' -f1-2 "$S/hote-$vm.pub")" -v poc="$(cat "$S/id_ed25519.pub")" -v priv="$S/hote-$vm" '
    /@CLE_HOTE_PRIVEE@/ { while ((getline l < priv) > 0) print "    " l; next }
    { gsub(/@HOTE@/, hote); gsub(/@CLE_HOTE_PUBLIQUE@/, pub); gsub(/@CLE_POC@/, poc); print }
  ' "$here/cloud-init/user-data.in" > "$d/user-data"
  if grep -q '@[A-Z_]*@' "$d/user-data"; then echo "graine de $vm incomplète" >&2; exit 1; fi
  genisoimage -quiet -output "$W/$vm-graine.iso" -volid cidata -joliet -rock "$d/user-data" "$d/meta-data"
  rm -rf "$d"
}

attendre_ssh() { # vm
  for _ in $(seq 90); do
    if ssh -i "$S/id_ed25519" -o UserKnownHostsFile="$S/known_hosts" -o StrictHostKeyChecking=yes \
         -o ConnectTimeout=3 -o BatchMode=yes "poc@${IP[$1]}" true 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "SSH injoignable sur $1" >&2; return 1
}

creer() {
  (cd "$(dirname "$IMG")" && echo "$SHA512  $(basename "$IMG")" | sha512sum -c --quiet)
  cles
  if ! existe pool "$POOL"; then
    v pool-define-as "$POOL" dir --target "$POOL_DIR"
    v pool-build "$POOL"
  fi
  actif pool "$POOL" || v pool-start "$POOL"
  existe net "$NET" || v net-define "$here/libvirt/reseau.xml"
  v net-autostart --disable "$NET" >/dev/null
  actif net "$NET" || v net-start "$NET"
  mkdir -p "$W"
  for vm in "${VMS[@]}"; do
    if ! v vol-info --pool "$POOL" "$vm.qcow2" >/dev/null 2>&1; then
      qemu-img convert -f qcow2 -O qcow2 "$IMG" "$W/$vm.qcow2"
      qemu-img resize -q "$W/$vm.qcow2" "${TAILLE[$vm]}"
      televerser "$W/$vm.qcow2" "$vm.qcow2" qcow2
      rm -f "$W/$vm.qcow2"
    fi
    if ! v vol-info --pool "$POOL" "$vm-graine.iso" >/dev/null 2>&1; then
      graine "$vm"
      televerser "$W/$vm-graine.iso" "$vm-graine.iso" raw
      rm -f "$W/$vm-graine.iso"
    fi
    existe dom "$vm" || v define "$here/libvirt/$vm.xml"
    v autostart --disable "$vm" >/dev/null
  done
  v pool-refresh "$POOL" >/dev/null
  v vol-list --pool "$POOL" --details
  chrono "J1 VM définies" "pool, réseau, 3 volumes et 3 graines"
  for vm in "${VMS[@]}"; do actif dom "$vm" || v start "$vm"; done
  for vm in "${VMS[@]}"; do attendre_ssh "$vm"; echo "$vm : SSH ok (clé d'hôte attendue)"; done
  chrono "J1 VM joignables en SSH"
}

demarrer() {
  actif net "$NET" || v net-start "$NET"
  for vm in "${VMS[@]}"; do actif dom "$vm" || v start "$vm"; done
  for vm in "${VMS[@]}"; do attendre_ssh "$vm"; done
}

arreter() {
  for vm in "${VMS[@]}"; do if actif dom "$vm"; then v shutdown "$vm"; fi; done
  for vm in "${VMS[@]}"; do
    for _ in $(seq 60); do actif dom "$vm" || break; sleep 2; done
    if actif dom "$vm"; then v destroy "$vm"; fi
  done
  if actif net "$NET"; then v net-destroy "$NET"; fi
}

detruire() {
  for vm in "${VMS[@]}"; do
    if existe dom "$vm"; then
      if actif dom "$vm"; then v destroy "$vm"; fi
      v undefine "$vm"
    fi
  done
  if existe pool "$POOL"; then
    actif pool "$POOL" || v pool-start "$POOL"
    for vm in "${VMS[@]}"; do
      v vol-delete --pool "$POOL" "$vm.qcow2" 2>/dev/null || true
      v vol-delete --pool "$POOL" "$vm-graine.iso" 2>/dev/null || true
    done
    v pool-destroy "$POOL"
    v pool-delete "$POOL"
    v pool-undefine "$POOL"
  fi
  if existe net "$NET"; then
    if actif net "$NET"; then v net-destroy "$NET"; fi
    v net-undefine "$NET"
  fi
  rm -rf -- "$W"
  rm -f -- "$HOME/.kube/supply-chain-poc.yaml"
  chrono "VM, pool et réseau détruits"
  echo "reste dans $O : $(find "$O" -mindepth 1 -maxdepth 1 -printf '%f ')"
}

case ${1:-} in
  creer|demarrer|arreter|detruire) "$1" ;;
  *) echo "usage : $0 creer|demarrer|arreter|detruire" >&2; exit 2 ;;
esac
