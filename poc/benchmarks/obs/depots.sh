#!/usr/bin/env bash
# Banc A2 : dépôts figés téléchargés à la demande (DoD) et projet poc dans l'appliance.
# 1. Clés des distributions, chacune comparée sur deux canaux :
#    Debian 13 (archive, stable) et archive Debian 12 (elle signe aussi Release.gpg de trixie) :
#    ftp-master.debian.org et le dépôt debian-archive-keyring (salsa) ;
#    Rocky 9 : dl.rockylinux.org et le projet RockyLinux:9 de build.opensuse.org.
# 2. Métadonnées figées vérifiées sur l'hôte : InRelease de l'instantané Debian (signatures, et même
#    sha256 sur deb.debian.org, source réelle du DoD), repomd.xml.asc du vault.
# 3. prjconf de référence (Debian:13, RockyLinux:9 de build.opensuse.org) archivés une fois et
#    épinglés par sha256 ; seule modification : retrait de « VMInstall: kernel-obs-build » (Debian),
#    que fournit OBS:DefaultKernel, absent de l'instance ; la VM de build démarre alors sur le noyau
#    de l'appliance (build-vm-kvm, /boot/vmlinuz et /boot/initrd).
# 4. Projets Debian:13, Rocky:9.7 et poc poussés avec l'osc de l'appliance ; attente du premier DoD.
#
# Usage (racine du dépôt) : mise run obs:depots
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
P=$here/projets
O=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}
A=$O/entrees
SNAP=https://snapshot.debian.org/archive/debian/20261029T000000Z
DEB=https://deb.debian.org/debian   # source du DoD, épinglée sur l'InRelease de SNAP (voir projets/Debian-13.meta.xml)
SHA_INRELEASE=0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675   # trixie, 12/09/2026
VAULT=https://dl.rockylinux.org/vault/rocky/9.7
FPR_DEB_ARCHIVE=04B54C3CDCA79751B16BC6B5225629DF75B188BD   # Debian Archive Automatic Signing Key (13/trixie)
FPR_DEB_STABLE=41587F7DB8C774BCCF131416762F67A0B2C39DE4    # Debian Stable Release Key (13/trixie)
FPR_DEB_ARCHIVE_12=B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8 # Debian Archive Automatic Signing Key (12/bookworm) :
# Release.gpg de trixie porte aussi sa signature, et bs_dodup (gpgv) exige que toutes les signatures se vérifient.
FPR_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D         # Rocky Enterprise Software Foundation, 2022
SHA_PRJCONF_DEBIAN=4137b14eb99c8dc6209a932330b2b990cce454e09e0c6ad52ece574d2a1fc620   # relevés le 29/10/2026
SHA_PRJCONF_ROCKY=bc69dbb894aea471f8927a64af9a07661ef84e2dd62705881dc07664cec8a2c1
s() { "$here/ssh-obs.sh" "$@"; }
mkdir -p "$A/cles" "$A/prjconf"
G=$(mktemp -d)
trap 'rm -rf -- "$G"' EXIT
exec > >(sed -u "s#$HOME#~#g" | tee "$R/depots.log") 2>&1
echo "# depots.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

fpr() { gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}'; }
attendu() {   # attendu <fichier> <empreinte> <libellé>
  local f; f=$(fpr "$1")
  echo "$3 : $f"
  [[ $f == "$2" ]] || { echo "ÉCHEC : empreinte inattendue ($3)"; exit 1; }
}
blocs() { sed -n '/-----BEGIN PGP PUBLIC KEY BLOCK-----/,/-----END PGP PUBLIC KEY BLOCK-----/p' | sed 's/^.*<pubkey>//; s/^  //'; }

echo "## 1. Clés, deux canaux"
curl -fsSL https://ftp-master.debian.org/keys/archive-key-13.asc -o "$A/cles/debian-archive-13.asc"
curl -fsSL https://ftp-master.debian.org/keys/release-13.asc -o "$A/cles/debian-release-13.asc"
curl -fsSL https://ftp-master.debian.org/keys/archive-key-12.asc -o "$A/cles/debian-archive-12.asc"
curl -fsSL https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 -o "$A/cles/rocky-9.asc"
for f in add-trixie-automatic add-trixie-stable add-bookworm-automatic; do
  curl -fsSL "https://salsa.debian.org/release-team/debian-archive-keyring/-/raw/master/active-keys/$f" | blocs > "$G/$f.asc"
done
curl -fsSL https://api.opensuse.org/public/source/RockyLinux:9/_meta -o "$G/rocky-bo.meta"
awk '/-----BEGIN PGP PUBLIC KEY BLOCK-----/{f=1} f{print} /-----END PGP PUBLIC KEY BLOCK-----/{exit}' "$G/rocky-bo.meta" | blocs > "$G/rocky-bo.asc"
attendu "$A/cles/debian-archive-13.asc" "$FPR_DEB_ARCHIVE" "Debian archive 13, ftp-master"
attendu "$G/add-trixie-automatic.asc" "$FPR_DEB_ARCHIVE" "Debian archive 13, salsa"
attendu "$A/cles/debian-release-13.asc" "$FPR_DEB_STABLE" "Debian stable 13, ftp-master"
attendu "$G/add-trixie-stable.asc" "$FPR_DEB_STABLE" "Debian stable 13, salsa"
attendu "$A/cles/debian-archive-12.asc" "$FPR_DEB_ARCHIVE_12" "Debian archive 12, ftp-master"
attendu "$G/add-bookworm-automatic.asc" "$FPR_DEB_ARCHIVE_12" "Debian archive 12, salsa"
attendu "$A/cles/rocky-9.asc" "$FPR_ROCKY" "Rocky 9, dl.rockylinux.org"
attendu "$G/rocky-bo.asc" "$FPR_ROCKY" "Rocky 9, build.opensuse.org"

echo "## 2. Métadonnées figées, vérifiées sur l'hôte"
GNUPGHOME=$G gpg --batch -q --import "$A/cles/debian-archive-13.asc" "$A/cles/debian-release-13.asc" \
  "$A/cles/debian-archive-12.asc" "$A/cles/rocky-9.asc" 2>/dev/null
curl -fsSL "$SNAP/dists/trixie/InRelease" -o "$G/InRelease"
echo "InRelease ($(grep -m1 '^Date:' "$G/InRelease"), sha256 $(sha256sum < "$G/InRelease" | cut -c1-16)…) :"
GNUPGHOME=$G gpg --batch --status-fd 1 --verify "$G/InRelease" 2>/dev/null > "$G/statut" || true
awk '$2 == "VALIDSIG" {print "  VALIDSIG", $3, $4, "clé principale", $NF} $2 == "NO_PUBKEY" {print "  NO_PUBKEY", $3, "(non importée)"}' "$G/statut"
for f in "$FPR_DEB_ARCHIVE" "$FPR_DEB_STABLE" "$FPR_DEB_ARCHIVE_12"; do
  grep -q "^\[GNUPG:\] VALIDSIG .* $f$" "$G/statut" || { echo "ÉCHEC : InRelease non signé par $f"; exit 1; }
done
for u in "$SNAP" "$DEB"; do
  h=$(curl -fsSL "$u/dists/trixie/InRelease" | sha256sum | cut -d' ' -f1)
  echo "InRelease de $u : $h"
  [[ $h == "$SHA_INRELEASE" ]] || { echo "ÉCHEC : InRelease différent de l'instantané épinglé"; exit 1; }
done
for r in BaseOS AppStream; do
  curl -fsSL "$VAULT/$r/x86_64/os/repodata/repomd.xml" -o "$G/repomd.xml"
  curl -fsSL "$VAULT/$r/x86_64/os/repodata/repomd.xml.asc" -o "$G/repomd.xml.asc"
  echo "$r repomd.xml (révision $(grep -o '<revision>[0-9]*</revision>' "$G/repomd.xml" | tr -dc 0-9), sha256 $(sha256sum < "$G/repomd.xml" | cut -c1-16)…) :"
  GNUPGHOME=$G gpg --batch --status-fd 1 --verify "$G/repomd.xml.asc" "$G/repomd.xml" 2>/dev/null > "$G/statut" || true
  awk '$2 == "VALIDSIG" {print "  VALIDSIG", $3, $4}' "$G/statut"
  grep -q "^\[GNUPG:\] VALIDSIG $FPR_ROCKY " "$G/statut" || { echo "ÉCHEC : repomd.xml de $r"; exit 1; }
done

echo "## 3. prjconf de référence (build.opensuse.org), épinglés"
for p in Debian:13 RockyLinux:9; do
  [[ -s $A/prjconf/$p ]] || curl -fsSL "https://api.opensuse.org/public/source/$p/_config" -o "$A/prjconf/$p"
done
echo "$SHA_PRJCONF_DEBIAN  $A/prjconf/Debian:13" | sha256sum -c
echo "$SHA_PRJCONF_ROCKY  $A/prjconf/RockyLinux:9" | sha256sum -c
grep -v '^VMInstall: kernel-obs-build$' "$A/prjconf/Debian:13" > "$G/Debian-13.prjconf"
cp "$A/prjconf/RockyLinux:9" "$G/Rocky-9.7.prjconf"
diff "$A/prjconf/Debian:13" "$G/Debian-13.prjconf" | sed 's/^/  Debian:13 /' || true

echo "## 4. Projets dans l'appliance"
cles_debian=$(cat "$A/cles/debian-archive-13.asc" "$A/cles/debian-release-13.asc" "$A/cles/debian-archive-12.asc")
cles_rocky=$(cat "$A/cles/rocky-9.asc")
python3 -I - "$P/Debian-13.meta.xml" "$G/Debian-13.meta.xml" "$cles_debian" <<'PY'
import sys
src, dst, cles = sys.argv[1:4]
open(dst, "w").write(open(src).read().replace("@CLES@", cles))
PY
python3 -I - "$P/Rocky-9.7.meta.xml" "$G/Rocky-9.7.meta.xml" "$cles_rocky" <<'PY'
import sys
src, dst, cles = sys.argv[1:4]
open(dst, "w").write(open(src).read().replace("@CLES@", cles))
PY
cp "$P/poc.meta.xml" "$P/poc.prjconf" "$G/"
s 'rm -rf /root/banc-a2/projets && mkdir -p /root/banc-a2/projets'
SSH_OBS_SCP=1 "$here/ssh-obs.sh" "$G/Debian-13.meta.xml" "$G/Debian-13.prjconf" "$G/Rocky-9.7.meta.xml" \
  "$G/Rocky-9.7.prjconf" "$G/poc.meta.xml" "$G/poc.prjconf" root@192.168.161.10:/root/banc-a2/projets/
s 'set -e; cd /root/banc-a2/projets
   osc -q meta prj -F Debian-13.meta.xml Debian:13 && osc -q meta prjconf -F Debian-13.prjconf Debian:13
   osc -q meta prj -F Rocky-9.7.meta.xml Rocky:9.7 && osc -q meta prjconf -F Rocky-9.7.prjconf Rocky:9.7
   osc -q meta prj -F poc.meta.xml poc && osc -q meta prjconf -F poc.prjconf poc
   for p in Debian:13 Rocky:9.7 poc; do echo "$p : $(osc meta prj "$p" | grep -c "<repository ") dépôts"; done'

echo "## Premier téléchargement à la demande (bs_dodup)"
for i in $(seq 120); do
  n=$(s 'for r in Debian:13/standard Rocky:9.7/baseos Rocky:9.7/appstream; do
           osc api "/build/$r/x86_64/_repository" 2>/dev/null | grep -c "<binary " || true
         done' | paste -sd' ')
  [[ $n =~ ^[1-9][0-9]*\ [1-9][0-9]*\ [1-9][0-9]*$ ]] && break
  sleep 10
done
echo "binaires connus (Debian:13/standard, Rocky:9.7/baseos, Rocky:9.7/appstream) : $n, après $(( (i - 1) * 10 )) s"
s 'grep -h -E "dodup|signature|error|Error" /srv/obs/log/dodup.log 2>/dev/null | tail -15'
