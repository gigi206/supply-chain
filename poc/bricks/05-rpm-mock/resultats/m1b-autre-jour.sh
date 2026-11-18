#!/usr/bin/env bash
# Brique 05, M1b, point 1 A : comparaison des relances d'un autre jour aux références du 18/11/2026. Préparé le 18/11/2026, à sec.
# Les quatre bancs sont relancés sans modification, chacun dans son dossier neuf et son nouveau journal :
#   m1b-outil.sh (outils de 99790c13), m1b-outil-amorce.sh (outils de l'amorce), m1b-repro3.sh (222 rpm), m1b-boot.sh (bootstrap).
# Ce script ne réinstalle rien. Il lit les archives des dossiers neufs et compare leurs sha256 aux références du 18/11 :
#   outillage, outils de 99790c13 : 05d35d64 (b5 de m1b-sans-machine-id.sh). m1b-sans-machine-id.sh fixe en dur les arbres du 18/11
#     (l. 12) et ne se relance donc pas tel quel : ici, i5 et i6 du dossier neuf sont archivés avec sa fonction archive, sa liste
#     EXCL et --exclude=./etc/machine-id, recopiées à l'identique (l. 20 à 28 et 34), dans un dossier neuf de ce script ;
#   outillage, outils de l'amorce : 06c289ad (a8 et a9) ; troisième banc : 0c00666a (a3 et a4) ; bootstrap : 28634a12 (x1 et x2).
# Sur un écart, l'archive neuve est comparée membre à membre à celle du 18/11, restée sur disque (m1b-repro2-comparer.py).
# Relève aussi le mode des dossiers b1 et b2 du bootstrap (racine de x1, venue du mkdir de l'hôte) et le umask du shell de lancement.
# Hors ligne (unshare -n). Usage (racine du dépôt), « - » pour un banc non relancé :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-autre-jour.sh <dossier outil> <dossier amorce> <dossier repro3> <dossier boot> > <journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
[ $# = 4 ] || { echo "KO   usage : $0 <outil> <amorce> <repro3> <boot> (« - » pour sauter)" >&2; exit 1; }
OUTIL=$1 AMORCE=$2 REPRO3=$3 BOOT=$4
C=$HOME/.cache/supply-chain-poc/05
S=1793914619                                                                          # m1b-outil.log, l. 54 ; m1b-sans-machine-id.sh, l. 14
ns() { unshare --map-auto --map-root-user -n "$@"; }
echo "# m1b-autre-jour.sh, début $(date -u +%FT%TZ)"
echo "umask du shell de lancement : $(umask)"
ecart() { # nom dossier_ref_horodaté dossier_neuf : intervalle entre les deux horodatages des noms de dossier
  local a b
  a=$(basename "$2" | sed -E 's/.*-([0-9]{8})T([0-9]{2})([0-9]{2})([0-9]{2})Z$/\1 \2:\3:\4/'); b=$(basename "$3" | sed -E 's/.*-([0-9]{8})T([0-9]{2})([0-9]{2})([0-9]{2})Z$/\1 \2:\3:\4/')
  echo "$1 : dossier de référence $(basename "$2"), dossier neuf $(basename "$3") ; intervalle $(( ($(date -u -d "$b" +%s) - $(date -u -d "$a" +%s)) / 60 )) min"
}
compare() { # nom archive_neuve sha256_attendu archive_du_18/11
  local s; s=$(sha256sum < "$2" | cut -c1-64)
  if [ "$s" = "$3" ]; then echo "OK   $1 : sha256 égal à la référence du 18/11 ($s)"
  else echo "ÉCART $1 : sha256 $s (référence $3)"; python3 -I "$r/m1b-repro2-comparer.py" "$4" "$2"; fi
}
if [ "$OUTIL" != - ]; then
  echo "## outillage, outils de 99790c13 (référence 05d35d64)"
  ecart outil "$C/m1b-outil-20261118T205714Z" "$OUTIL"
  [ -d "$OUTIL/outils/m/i5" ] && [ -d "$OUTIL/outils/m/i6" ] || { echo "KO   i5 ou i6 absent de $OUTIL" >&2; exit 1; }
  A=$C/m1b-autre-jour-$(date -u +%Y%m%dT%H%M%SZ)                                      # dossier neuf, jamais effacé ni réutilisé
  [ ! -e "$A" ] || { echo "KO   dossier déjà présent : $A" >&2; exit 1; }
  mkdir -p "$A"
  # recopié de m1b-sans-machine-id.sh, l. 20 à 28
  EXCL=(--exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log
    --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal
    --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m)
  archive() { # arbre fichier [exclusions en plus]
    local a=$1 f=$2; shift 2
    ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
      --xattrs --xattrs-include='*' --numeric-owner "${EXCL[@]}" "$@" -C "$a" -cf "$f" . 2> "$f.err" || echo "tar code $? ($(wc -l < "$f.err") lignes d'erreur)"
    echo "$(basename "$f") : $(stat -c %s "$f") octets, $(tar -tf "$f" | wc -l) membres, sha256 $(sha256sum < "$f" | cut -c1-64)"
  }
  for i in 5 6; do archive "$OUTIL/outils/m/i$i" "$A/b$i.tar" --exclude=./etc/machine-id; done
  for i in 5 6; do compare "outil b$i" "$A/b$i.tar" 05d35d64f09692b13bd08af86b405607bca75c72d359550864fcf89a0321a59a "$C/m1b-sans-machine-id-20261118T210852Z/b5.tar"; done
  echo "archives laissées dans $A"
fi
if [ "$AMORCE" != - ]; then
  echo "## outillage, outils de l'amorce (référence 06c289ad)"
  ecart amorce "$C/m1b-outil-amorce-20261118T212517Z" "$AMORCE"
  for a in a8 a9; do compare "amorce $a" "$AMORCE/archives/$a.tar" 06c289ad8da33198dd845be6cc899f688ecfb8986e77e4b333629e838876dfa5 "$C/m1b-outil-amorce-20261118T212517Z/archives/a8.tar"; done
fi
if [ "$REPRO3" != - ]; then
  echo "## troisième banc (référence 0c00666a)"
  ecart repro3 "$C/m1b-repro3-20261118T201556Z" "$REPRO3"
  for a in a3 a4; do compare "repro3 $a" "$REPRO3/archives/$a.tar" 0c00666acc4836fd956043fcb3d0f85101b8726c9a7b1747746cc2ecf1d95d89 "$C/m1b-repro3-20261118T201556Z/archives/a3.tar"; done
fi
if [ "$BOOT" != - ]; then
  echo "## bootstrap (référence 28634a12)"
  ecart boot "$C/m1b-boot-20261118T214226Z" "$BOOT"
  for i in 1 2; do echo "stat de b$i : $(stat -c '%a %U:%G' "$BOOT/outils/m/b$i") ; au 18/11 : $(stat -c '%a %U:%G' "$C/m1b-boot-20261118T214226Z/outils/m/b$i")"; done
  for a in x1 x2; do compare "boot $a" "$BOOT/archives/$a.tar" 28634a12c5e99aae558a0cd6719d8f87fad6bac329724f0afafee252e6b78ab3 "$C/m1b-boot-20261118T214226Z/archives/x1.tar"; done
fi
echo "# fin $(date -u +%FT%TZ)"
