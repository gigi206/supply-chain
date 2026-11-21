#!/usr/bin/env bash
# Brique 07b, tranche 3, mesure 0 : effet d'un metadata.component de type container dans le SBOM fusionné, sans --vex.
# Rien de partagé : l'image et le deb ont été copiés depuis Zot en lecture anonyme dans $X/mesure0 avant ce script ; Grype tourne
# hors réseau (unshare -rn) sur la base archivée de G0, lue sans modification ; scan-outil est construit depuis outil/ du dépôt.
# Le deb est extrait comme dans scanner.sh (une couche tar, le .deb seul, data.tar), avec ar et tar de l'hôte au lieu de busybox.
# Usage (racine du dépôt, outils de mise.toml) : poc/bricks/07a-sbom-grype/resultats/07b-t3-mesure0.sh > <journal>
set -euo pipefail
export LC_ALL=C
B=$PWD/poc/bricks/07a-sbom-grype
G0=$HOME/.cache/supply-chain-poc/07a/g0
X=$HOME/.cache/supply-chain-poc/07a/t3/mesure0
KO=0
ok() { echo "OK   $1"; }
ko() { echo "KO   $1"; KO=$((KO + 1)); }
offline() {
  unshare -rn env GRYPE_DB_CACHE_DIR="$G0/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
    GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false TMPDIR="$X/tmp" "$@"
}
empreinte_base() { (cd "$G0" && find dbcache -type f -exec sha256sum {} + | sort | sha256sum | cut -c1-16); }

echo "# mesure 0 : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "grype $(grype version 2>/dev/null | sed -n 's/^Version: *//p'), syft $(syft version 2>/dev/null | sed -n 's/^Version: *//p'), $(go version | cut -d' ' -f3)"
e0=$(empreinte_base)
mkdir -p "$X/tmp" "$X/bin"
(cd "$B/outil" && CGO_ENABLED=0 go build -trimpath -o "$X/bin/scan-outil" .)
echo "scan-outil construit depuis outil/main.go sha256 $(sha256sum < "$B/outil/main.go" | cut -c1-16)"

# deb : même extraction que extraire_deb de scanner.sh
d=$(jq -r '.manifests[0].digest' "$X/deb/index.json")
couches=$(jq -c '.layers' "$X/deb/blobs/sha256/${d#sha256:}")
[ "$(jq length <<< "$couches")" = 1 ] && [ "$(jq -r '.[0].mediaType' <<< "$couches")" = application/vnd.oci.image.layer.v1.tar ] || { echo "deb : forme inattendue"; exit 1; }
l=$(jq -r '.[0].digest' <<< "$couches")
mkdir -p "$X/deb-couche" "$X/deb-artefact"
tar -xf "$X/deb/blobs/sha256/${l#sha256:}" -C "$X/deb-couche"
set -- "$X"/deb-couche/*.deb
[ $# = 1 ] || { echo "deb : un .deb attendu"; exit 1; }
echo "DEB|${1##*/}, sha256 $(sha256sum < "$1" | cut -c1-16)"
(cd "$X/deb-couche" && ar -x "${1##*/}")
set -- "$X"/deb-couche/data.tar*
[ $# = 1 ] || { echo "deb : un data.tar attendu"; exit 1; }
tar -xf "$1" -C "$X/deb-artefact"
echo "EXTRAIT|$(find "$X/deb-artefact" -type f | wc -l) fichiers dans data.tar"

for a in image deb; do
  echo "## $a"
  d=$(jq -r '.manifests[0].digest' "$X/$a/index.json")
  nom=sample-app; [ "$a" = image ] || nom=sample-app-deb
  if [ "$a" = image ]; then offline syft scan "oci-dir:$X/image" -o cyclonedx-json="$X/$a-artefact.json" -q
  else offline syft scan "dir:$X/deb-artefact" -o cyclonedx-json="$X/$a-artefact.json" -q; fi
  echo "artefact seul : $(grep -oE '"purl": *"pkg:[^"@]+@[^"]*"' "$X/$a-artefact.json" | wc -l) PURL versionnées"
  "$X/bin/scan-outil" fusion "$G0/sbom-source.json" "$X/$a-artefact.json" source image > "$X/$a-avant.cdx"
  jq -c --arg n "$nom" --arg d "$d" '.metadata.component = {type: "container", name: $n, version: $d, "bom-ref": "pkg:oci/\($n)@\($d)", purl: "pkg:oci/\($n)@\($d)"}' \
    "$X/$a-avant.cdx" > "$X/$a-apres.cdx"
  [ "$(jq -S 'del(.metadata.component)' "$X/$a-apres.cdx" | sha256sum)" = "$(jq -S . "$X/$a-avant.cdx" | sha256sum)" ] \
    && ok "$a : SBOM après = SBOM avant + metadata.component seul" || ko "$a : SBOM après diffère au-delà du composant"
  for v in avant apres; do
    offline grype "sbom:$X/$a-$v.cdx" -o json --file "$X/$a-$v.grype.json" -q 2> "$X/$a-$v.err" || { ko "$a $v : grype en erreur ($(head -c 300 "$X/$a-$v.err"))"; continue; }
    "$X/bin/scan-outil" predicat "$X/$a-$v.grype.json" base-g0 > "$X/$a-$v.scan.json"
    echo "$a $v : $(jq '.matches | length' "$X/$a-$v.grype.json") matches, $(jq '.ignoredMatches // [] | length' "$X/$a-$v.grype.json") ignorées, source $(jq -c .source.type "$X/$a-$v.grype.json"), $(jq '.vulnerabilities | length' "$X/$a-$v.scan.json") entrées au prédicat, $(jq '[.vulnerabilities[] | select(.kev)] | length' "$X/$a-$v.scan.json") KEV"
  done
  p() { jq -S 'del(.scannedAt)' "$X/$a-$1.scan.json"; }
  m() { jq -r '.matches[] | "\(.vulnerability.id) \(.artifact.purl)"' "$X/$a-$1.grype.json" | sort; }
  [ "$(p avant | sha256sum)" = "$(p apres | sha256sum)" ] && ok "$a : prédicats identiques hors scannedAt" || { ko "$a : prédicats différents"; diff <(p avant) <(p apres) | head -20; }
  [ "$(m avant | sha256sum)" = "$(m apres | sha256sum)" ] && ok "$a : couples (id, PURL) identiques ($(m avant | wc -l))" || { ko "$a : couples différents"; diff <(m avant) <(m apres) | head -20; }
done
[ "$(jq '.matches | length' "$X/deb-avant.grype.json")" -gt 0 ] && ok "deb : au moins une correspondance" || ko "deb : aucune correspondance"
[ "$(empreinte_base)" = "$e0" ] && ok "base de G0 inchangée ($e0)" || ko "base de G0 modifiée"
echo "# fin : $(date -u +%Y-%m-%dT%H:%M:%SZ) ; $KO KO"
