#!/usr/bin/env bash
# Banc A2 : pool, réseau et VM libvirt de l'appliance OBS (qemu:///system, sans sudo).
#   creer    : pool supply-chain-poc (/var/lib/libvirt/supply-chain-poc, créé par libvirtd),
#              réseau NAT supply-chain-poc (libvirt/reseau.xml), disque qcow2 de 40 Go tiré de
#              l'image oem vérifiée (obs:preparer), VM sc-obs (libvirt/sc-obs.xml), démarrage ;
#   demarrer : réseau puis VM ;  arreter : VM puis réseau ;
#   detruire : VM, disque, pool (et son répertoire), réseau ; fichiers de travail et known_hosts
#              dédiés. L'image téléchargée et les secrets restent dans ~/.cache/supply-chain-poc/obs.
# Aucun démarrage automatique ; les VM et réseaux personnels ne sont pas touchés.
#
# Usage (racine du dépôt) : mise run obs:vm -- creer|demarrer|arreter|detruire
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}
IMG=$O/appliance/obs-server.x86_64-2.10.51-oem-Build53.24.raw.xz
SHA=bbc26ff87cac640481300a70d3680cd2f84d0b58c086e48976aa0f542cd85699
POOL=supply-chain-poc
POOL_DIR=/var/lib/libvirt/supply-chain-poc
NET=supply-chain-poc
VM=sc-obs
VOL=sc-obs.qcow2
TAILLE=40G
v() { virsh -c qemu:///system "$@"; }
liste() { case $1 in net) v net-list --name "${@:2}" ;; pool) v pool-list --name "${@:2}" ;; dom) v list --name "${@:2}" ;; esac; }
existe() { liste "$1" --all | grep -qxF "$2"; }
actif() { liste "$1" | grep -qxF "$2"; }

creer() {
  (cd "$(dirname "$IMG")" && echo "$SHA  $(basename "$IMG")" | sha256sum -c --quiet)
  if ! existe pool "$POOL"; then
    v pool-define-as "$POOL" dir --target "$POOL_DIR"
    v pool-build "$POOL"
  fi
  actif pool "$POOL" || v pool-start "$POOL"
  existe net "$NET" || v net-define "$here/libvirt/reseau.xml"
  actif net "$NET" || v net-start "$NET"
  if ! v vol-info --pool "$POOL" "$VOL" >/dev/null 2>&1; then
    W=$O/travail
    mkdir -p "$W"
    echo "décompression de l'image oem (fichier creux)"
    xz -dc "$IMG" | dd of="$W/oem.raw" bs=1M iflag=fullblock conv=sparse status=none
    qemu-img info "$W/oem.raw" | grep -E 'virtual size|disk size'
    qemu-img convert -f raw -O qcow2 "$W/oem.raw" "$W/$VOL"
    qemu-img resize "$W/$VOL" "$TAILLE"
    rm -f "$W/oem.raw"
    v vol-create-as "$POOL" "$VOL" "$TAILLE" --format qcow2
    v vol-upload --pool "$POOL" --sparse "$VOL" "$W/$VOL"
    rm -f "$W/$VOL"
    v pool-refresh "$POOL"
    v vol-info --pool "$POOL" "$VOL"
  fi
  existe dom "$VM" || v define "$here/libvirt/sc-obs.xml"
  v autostart --disable "$VM" >/dev/null
  actif dom "$VM" || v start "$VM"
  mkdir -p "$R"
  printf '2. VM %s démarrée (pool, réseau, disque de %s)\t%s\t\n' "$VM" "$TAILLE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$R/chrono.tsv"
}

demarrer() { actif net "$NET" || v net-start "$NET"; actif dom "$VM" || v start "$VM"; }

arreter() {
  if actif dom "$VM"; then
    v shutdown "$VM"
    for _ in $(seq 60); do actif dom "$VM" || break; sleep 2; done
    actif dom "$VM" && v destroy "$VM"
  fi
  if actif net "$NET"; then v net-destroy "$NET"; fi
}

detruire() {
  if existe dom "$VM"; then
    actif dom "$VM" && v destroy "$VM"
    v undefine "$VM"
  fi
  if existe pool "$POOL"; then
    actif pool "$POOL" || v pool-start "$POOL"
    v vol-delete --pool "$POOL" "$VOL" 2>/dev/null || true
    v pool-destroy "$POOL"
    v pool-delete "$POOL"
    v pool-undefine "$POOL"
  fi
  if existe net "$NET"; then
    actif net "$NET" && v net-destroy "$NET"
    v net-undefine "$NET"
  fi
  rm -rf -- "$O/travail" "$O/ssh/known_hosts"
  echo "reste dans $O : $(find "$O" -mindepth 1 -maxdepth 1 -printf '%f ')"
}

case ${1:-} in
  creer|demarrer|arreter|detruire) "$1" ;;
  *) echo "usage : $0 creer|demarrer|arreter|detruire" >&2; exit 2 ;;
esac
