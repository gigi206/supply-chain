#!/usr/bin/env bash
# Brique 08, jalon J1 : téléchargements vérifiés, rangés dans ~/.cache/supply-chain-poc/08/telechargements.
#   Debian 13 generic (20261026-2643) : aucune signature publiée. Le SHA512 est vérifié contre
#     SHA512SUMS et contre le manifeste JSON de l'image (deux documents de cloud.debian.org), puis
#     contre l'empreinte épinglée ici (choix du propriétaire, 29/10/2026).
#   k3s v1.35.9+k3s1 : ni signature ni attestation. Le sha256 est vérifié contre sha256sum-amd64.txt,
#     contre l'empreinte calculée par GitHub (API des releases), puis contre l'empreinte épinglée ici.
# Rien n'est installé sur l'hôte.
#
# Usage (racine du dépôt) : mise run confiance:preparer
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}
T=$O/telechargements
mkdir -p "$R" "$T/debian" "$T/k3s"
exec > >(tee "$R/preparer.log") 2>&1
echo "# preparer.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

DEB_URL=https://cloud.debian.org/images/cloud/trixie/20261026-2643
DEB_IMG=debian-13-generic-amd64-20261026-2643.qcow2
DEB_SHA512=5bd891c6e62d01639f52a5587b72a4607421e445732214be787dba6043cf9797a6ff90bed982aada6a6c7e619f1f956d961c4fad76757171abd607920aac098a
K3S_TAG=v1.35.9+k3s1
K3S_URL=https://github.com/k3s-io/k3s/releases/download/v1.35.9%2Bk3s1
K3S_SHA=897acb21cca57d477a211102251a6591450ce767344a9faaa121a1007ca9fa9a
K3S_IMG=k3s-airgap-images-amd64.tar.zst
K3S_IMG_SHA=7f1cbfea56d38f5e69aec13500a89290119096cc2f5a6d4f542e5f26599977d0

telecharger() { # url fichier
  [ -s "$2" ] && return 0
  curl -fsSL --proto '=https' --tlsv1.2 -o "$2.part" "$1"
  mv "$2.part" "$2"
}
echec() { echo "ÉCHEC : $*" >&2; exit 1; }

echo "## Debian 13 generic"
cd "$T/debian"
telecharger "$DEB_URL/SHA512SUMS" SHA512SUMS
telecharger "$DEB_URL/${DEB_IMG%.qcow2}.json" "${DEB_IMG%.qcow2}.json"
telecharger "$DEB_URL/$DEB_IMG" "$DEB_IMG"
somme=$(awk -v f="$DEB_IMG" '$2 == f { print $1 }' SHA512SUMS)
[ "$somme" = "$DEB_SHA512" ] || echec "SHA512SUMS ($somme) diffère de l'empreinte épinglée"
manifeste=$(jq -r --arg f "trixie/20261026-2643/$DEB_IMG" \
  '.items[] | select(.kind == "Upload" and (.data.ref == $f)) | .metadata.annotations["cloud.debian.org/digest"]' \
  "${DEB_IMG%.qcow2}.json" | sed 's/^sha512://' | base64 -d 2>/dev/null | od -An -v -tx1 | tr -d ' \n')
[ "$manifeste" = "$DEB_SHA512" ] || echec "manifeste JSON ($manifeste) diffère de l'empreinte épinglée"
echo "$DEB_SHA512  $DEB_IMG" | sha512sum -c
jq -r '.items[] | select(.kind == "Build") | .data.packages[] | "\(.name) \(.version)"' "${DEB_IMG%.qcow2}.json" \
  | grep -E '^(linux-image-amd64|cloud-init|openssh-server|systemd|iptables|tcpdump|apparmor) '
ls -l "$DEB_IMG"

echo "## k3s $K3S_TAG"
cd "$T/k3s"
telecharger "$K3S_URL/sha256sum-amd64.txt" sha256sum-amd64.txt
telecharger "$K3S_URL/k3s" k3s
telecharger "$K3S_URL/$K3S_IMG" "$K3S_IMG"
for f in "k3s $K3S_SHA" "$K3S_IMG $K3S_IMG_SHA"; do
  set -- $f
  somme=$(awk -v f="$1" '$2 == f { print $1 }' sha256sum-amd64.txt)
  [ "$somme" = "$2" ] || echec "sha256sum-amd64.txt ($somme) diffère de l'empreinte épinglée pour $1"
  github=$(gh api "repos/k3s-io/k3s/releases/tags/$K3S_TAG" --jq ".assets[] | select(.name == \"$1\") | .digest")
  [ "$github" = "sha256:$2" ] || echec "empreinte GitHub ($github) diffère de l'empreinte épinglée pour $1"
  echo "$2  $1" | sha256sum -c
done
ls -l k3s "$K3S_IMG"  # binaire exécuté seulement dans les VM (version contrôlée par controles.sh)
echo "## Signatures : aucune publiée pour ces deux téléchargements (constaté le 29/10/2026)"
