#!/usr/bin/env bash
# Banc A2 : télécharge l'appliance OBS épinglée (OBS:Server:Unstable, Build53.24) et la vérifie.
# - clé du projet OBS comparée sur trois canaux : download.opensuse.org (repomd.xml.key),
#   build.opensuse.org (signing_keys) et la clé embarquée dans config.sh de l'appliance ;
# - signature détachée du .sha256 vérifiée dans un GNUPGHOME isolé, puis sha256 du fichier
#   comparé à la valeur relevée le 29/10/2026 (le fichier amont est écrasé à chaque build) ;
# - versions des composants relevées dans le SBOM CycloneDX de l'image.
# Le téléchargement reste dans ~/.cache/supply-chain-poc/obs (archive locale de l'entrée).
#
# Usage (racine du dépôt) : mise run obs:preparer
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
D=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}/appliance
PRJ=OBS:Server:Unstable
U=https://download.opensuse.org/repositories/OBS:/Server:/Unstable/images
IMG=obs-server.x86_64-2.10.51-oem-Build53.24.raw.xz
SBOM=obs-server.x86_64-2.10.51-qcow2-Build53.24   # SBOM publiés pour la qcow2 seulement, même build ; comparé à rpm -qa dans la VM
SHA=bbc26ff87cac640481300a70d3680cd2f84d0b58c086e48976aa0f542cd85699   # relevé le 29/10/2026
FPR=660FD3F9F16602A3722ABF6DE8420AB8C5C219E7                           # « OBS OBS Project »
mkdir -p "$D" "$R"
G=$(mktemp -d)
trap 'rm -rf -- "$G"' EXIT
exec > >(sed -u "s#$HOME#~#g" | tee "$R/preparation.log") 2>&1
echo "# preparer.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "## Clé du projet OBS, trois canaux"
curl -fsSL "https://download.opensuse.org/repositories/OBS:/Server:/Unstable/16.0/repodata/repomd.xml.key" -o "$G/k1.asc"
curl -fsSL "https://build.opensuse.org/projects/$PRJ/signing_keys/download?kind=gpg" -o "$G/k2.asc"
curl -fsSL "https://api.opensuse.org/public/source/$PRJ/OBS-Appliance/config.sh" \
  | sed -n '/^-----BEGIN PGP PUBLIC KEY BLOCK-----/,/^-----END PGP PUBLIC KEY BLOCK-----/p' > "$G/k3.asc"
for k in k1 k2 k3; do
  f=$(gpg --show-keys --with-colons "$G/$k.asc" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  echo "$k : $f"
  [[ $f == "$FPR" ]] || { echo "ÉCHEC : empreinte inattendue ($k)"; exit 1; }
done
GNUPGHOME=$G gpg --batch --quiet --import "$G/k1.asc"

echo "## Image $IMG"
for f in "$IMG.sha256" "$IMG.sha256.asc" "$SBOM.cdx.json" "$SBOM.spdx.json"; do
  curl -fsSL "$U/$f" -o "$D/$f"
done
GNUPGHOME=$G gpg --batch --status-fd 1 --verify "$D/$IMG.sha256.asc" "$D/$IMG.sha256" 2>/dev/null \
  | grep -E '^\[GNUPG:\] (VALIDSIG|GOODSIG)' | cut -d' ' -f2-4
GNUPGHOME=$G gpg --batch --status-fd 1 --verify "$D/$IMG.sha256.asc" "$D/$IMG.sha256" 2>/dev/null \
  | grep -q "^\[GNUPG:\] VALIDSIG $FPR " || { echo "ÉCHEC : signature du .sha256"; exit 1; }
[[ $(awk '{print $1}' "$D/$IMG.sha256") == "$SHA" ]] || { echo "ÉCHEC : .sha256 signé différent de la valeur relevée"; exit 1; }
if [[ ! -s $D/$IMG ]] || ! (cd "$D" && echo "$SHA  $IMG" | sha256sum -c --quiet); then
  curl -fsSL --retry 3 "$U/$IMG" -o "$D/$IMG.part"
  mv "$D/$IMG.part" "$D/$IMG"
fi
(cd "$D" && echo "$SHA  $IMG" | sha256sum -c)
echo "taille : $(stat -c %s "$D/$IMG") octets"

echo "## Composants (SBOM CycloneDX)"
jq -r '.components[] | select(.name | test("^(obs-server|obs-worker|obs-api|obs-signd|build|perl-BSSolv|kernel-default|qemu|qemu-x86|mariadb|ruby3\\.[0-9]+|osc|createrepo_c|dpkg|rpm)$")) | "\(.name) \(.version)"' \
  "$D/$SBOM.cdx.json" | sort -u
echo "composants : $(jq '.components | length' "$D/$SBOM.cdx.json")"
