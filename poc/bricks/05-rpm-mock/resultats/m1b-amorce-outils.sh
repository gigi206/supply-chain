#!/usr/bin/env bash
# Brique 05, M1b, préparation des tâches neuves : outils et clés de l'amorce rockylinux:9.8 (ed654c69), lus dans le cache OCI
# local de s1.sh amorce, sans extraction de la racine. (19/11/2026)
#   1. Manifeste et couche : sha256 (blobs adressés par contenu) ; nombre de membres.
#   2. Présence des outils que le prefetch et le constructeur utiliseraient (curl, gpgv, gpg, sha256sum, python3 et ssl, tar, gzip,
#      timeout, getent, rpm, dnf-3) et absence de ceux qu'ils n'auraient pas (skopeo, createrepo_c, cmp, jq, xz).
#   3. Clés : fichiers de etc/pki/rpm-gpg de la couche ; clé de Rocky de l'amorce comparée octet pour octet à celle des bancs de
#      l'outillage et du bootstrap (/m/cles, importée dans la base rpm de la racine installée) ; clé d'EPEL : présence dans la couche,
#      sha256, taille et empreinte de la copie des bancs.
# Hors ligne ; le cache et les bancs ne sont que lus ; un dossier neuf pour les fichiers extraits.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-amorce-outils.sh > poc/bricks/05-rpm-mock/resultats/m1b-amorce-outils.log 2>&1
set -euo pipefail
export LC_ALL=C
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256   # cache de s1.sh amorce : lecture seule
M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d                                # s1.sh, l. 169
B1=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/outils/m/cles   # banc de l'outillage : lecture seule
B2=$HOME/.cache/supply-chain-poc/05/m1b-boot-20261118T214226Z/outils/m/cles           # banc du bootstrap : lecture seule
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D                                     # s1.sh, l. 164
FP_EPEL=FF8AD1344597106ECE813B918A3872BF3228467C                                      # m1b-sources.log, l. 10
U=$(date -u +%Y%m%dT%H%M%SZ)
D=$HOME/.cache/supply-chain-poc/05/m1b-amorce-outils-$U
echo "# m1b-amorce-outils.sh, début $(date -u +%FT%TZ) ; dossier $D"
mkdir "$D"
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
fp() { gpg --batch --with-colons --show-keys "$1" 2> /dev/null | awk -F: '$1 == "fpr" {print $10; exit}'; }
echo "## 1. manifeste et couche"
attendu "manifeste de l'amorce" "$(sha256sum < "$O/$M" | cut -c1-64)" "$M"
read -r L n < <(python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); l = d["layers"]; print(l[0]["digest"][7:], len(l))' "$O/$M")
attendu "nombre de couches" "$n" 1
attendu "couche" "$(sha256sum < "$O/$L" | cut -c1-64)" "$L"
tar -tzf "$O/$L" > "$D/membres.txt"
echo "membres de la couche : $(wc -l < "$D/membres.txt")"
echo "## 2. outils"
for o in usr/bin/curl usr/bin/gpgv usr/bin/gpg usr/bin/sha256sum usr/bin/python3 usr/lib64/python3.9/ssl.py \
  usr/lib64/python3.9/lib-dynload/_ssl.cpython-39-x86_64-linux-gnu.so usr/lib64/python3.9/urllib/request.py usr/bin/tar \
  usr/bin/gzip usr/bin/timeout usr/bin/getent usr/bin/rpm usr/bin/dnf-3 usr/bin/bash usr/bin/find usr/bin/stat \
  usr/bin/skopeo usr/bin/createrepo_c usr/bin/cmp usr/bin/jq usr/bin/xz usr/bin/wget; do
  if grep -qx "$o" "$D/membres.txt"; then echo "présent : $o"; else echo "absent  : $o"; fi
done
echo "## 3. clés"
grep '^etc/pki/rpm-gpg/' "$D/membres.txt" | sed 's/^/membre : /'
mkdir "$D/x"
tar -xzf "$O/$L" -C "$D/x" etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
k=$D/x/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
echo "clé de Rocky de l'amorce : $(stat -c %s "$k") octets, sha256 $(sha256sum < "$k" | cut -c1-64)"
attendu "empreinte de la clé de Rocky de l'amorce" "$(fp "$k")" "$FP_ROCKY"
for b in "$B1" "$B2"; do
  echo "clé de Rocky de $b : $(stat -c %s "$b/RPM-GPG-KEY-Rocky-9") octets, sha256 $(sha256sum < "$b/RPM-GPG-KEY-Rocky-9" | cut -c1-64)"
  if [ "$(sha256sum < "$k")" = "$(sha256sum < "$b/RPM-GPG-KEY-Rocky-9")" ]; then echo "OK   clé de Rocky de l'amorce = celle du banc, octet pour octet"
  else echo "ÉCART clé de Rocky de l'amorce différente de celle du banc"; fi
done
if grep -q 'EPEL' "$D/membres.txt"; then echo "membres qui citent EPEL :"; grep 'EPEL' "$D/membres.txt"; else echo "aucun membre ne cite EPEL"; fi
e=$B1/RPM-GPG-KEY-EPEL-9
echo "clé d'EPEL du banc de l'outillage : $(stat -c %s "$e") octets, $(wc -l < "$e") lignes, sha256 $(sha256sum < "$e" | cut -c1-64)"
attendu "empreinte de la clé d'EPEL du banc" "$(fp "$e")" "$FP_EPEL"
echo "# fin $(date -u +%FT%TZ)"
