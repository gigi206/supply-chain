#!/usr/bin/env bash
# Brique 06, jalon S6a (contrôle 7 du deb ; décision du propriétaire du 12/11/2026, 08:50:32 UTC : « 1 ok / 2 ok / 3 ok / 4 ok »).
# Prédictions : resultats/s6a-predictions.md, commitées avant tout lancement.
#   releve  hôte seul, hors réseau (syft et grype sous unshare -rn), rien dans le cluster ni dans Zot, rien installé ; écritures
#           sous ~/.cache/supply-chain-poc/06/s6a et dans resultats/ seulement :
#           entrées vérifiées (sha256 du deb de S3 = celui de builds/sample-app-deb@039949f9 ; layout local de l'image de base
#           d'outils-scan, blobs revérifiés) ; P1 format du deb (ar t) ; P2 applets de busybox dans les couches de cette base
#           (noms listés, rien exécuté) ; P3 étiquettes des catalogueurs de syft ; P4 SBOM de l'artefact seul (syft dir: sur
#           data.tar extrait) ; P5 le deb comme fichier (syft dir: sur un dossier qui ne contient que lui) ; P6 grype sur le
#           SBOM de P4, base de G0 ; P7 syft dir: sur un dossier vide avec -q, puis fusion (scan-outil de la 07a) avec le SBOM
#           de la source (arbre HEAD:poc/sample-app, celui du commit 6391fd43).
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/06-deb-sbuild/s6a.sh releve   (journal : resultats/s6a-releve.log)
set -euo pipefail
export LC_ALL=C
h06=$(cd "$(dirname "$0")" && pwd)
racine=$(cd "$h06/../../.." && pwd)
R=$h06/resultats
T=$HOME/.cache/supply-chain-poc/06/s6a
DEB=$HOME/.cache/supply-chain-poc/08/travail/s3-06/build-1/sample-app_1.0.0-1_amd64.deb
DEB_SHA=0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5      # deb de builds/sample-app-deb@039949f9 (S4d1)
G0=$HOME/.cache/supply-chain-poc/07a/g0                                          # base grype du 04/11/2026 (G0 de la 07a)
SCAN_OUTIL=$HOME/.cache/supply-chain-poc/07a/outil/scan-outil                    # construit depuis 07a-sbom-grype/outil
BASE=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/sigstore/cosign/cosign
BASE_DIGEST=c142f6bc0c6d8e5e4a3d31b941200a12502ad90bb5ce93b78c875c868905619d     # COSIGN_BASE de 07a-sbom-grype/plateforme.sh
ARBRE=30e808ffa327288c656ddda7b6fafe4005234b77                                   # arbre de poc/sample-app au commit 6391fd43

chrono() { printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
hors() { /usr/bin/unshare -rn env GRYPE_DB_CACHE_DIR="$G0/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
  GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false "$@"; }
purls() { python3 -I -c 'import json, sys
c = [x for x in json.load(open(sys.argv[1])).get("components", []) if x.get("purl")]
print(f"{len(c)} composant(s) avec PURL")
for x in sorted(x["purl"] for x in c): print("  ", x)' "$1"; }

etape_releve() {
  rm -rf -- "${T:?}"; mkdir -p "$T"/{deb,data,fichier,vide,source}

  echo "## entrées"
  echo "syft $(syft version 2>/dev/null | sed -n 's/^Version: *//p'), grype $(grype version 2>/dev/null | sed -n 's/^Version: *//p')"
  attendu "sha256 du deb de S3" "$(sha256sum < "$DEB" | cut -c1-64)" "$DEB_SHA"
  attendu "manifeste du layout de la base" "$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["manifests"][0]["digest"])' "$BASE/index.json")" "sha256:$BASE_DIGEST"
  local b k=0
  for b in "$BASE"/blobs/sha256/*; do
    [ "$(sha256sum < "$b" | cut -c1-64)" = "${b##*/}" ] || { echo "KO   blob altéré : ${b##*/}" >&2; exit 1; }
    k=$((k + 1))
  done
  echo "OK   $k blobs de la base revérifiés par leur sha256"
  echo "scan-outil (07a, hôte) : sha256 $(sha256sum < "$SCAN_OUTIL" | cut -c1-64)"

  echo "## P1 : format du deb (ar t)"
  ar t "$DEB"

  echo "## P2 : applets de busybox dans les couches de l'image de base (noms seulement)"
  local m c
  m=$BASE/blobs/sha256/$BASE_DIGEST
  python3 -I -c 'import json, sys; [print(l["digest"][7:], l["mediaType"]) for l in json.load(open(sys.argv[1]))["layers"]]' "$m" > "$T/couches"
  : > "$T/noms"
  while read -r c _; do tar -tf "$BASE/blobs/sha256/$c" >> "$T/noms" 2>/dev/null || echo "couche $c illisible par tar" ; done < "$T/couches"
  echo "$(wc -l < "$T/couches") couches, $(wc -l < "$T/noms") entrées"
  for a in ar tar xz unxz zstd unzstd gunzip dpkg-deb; do
    printf '%-9s %s\n' "$a" "$(grep -E "(^|/)$a\$" "$T/noms" | sort -u | tr '\n' ' ')"
  done

  echo "## P3 : catalogueurs de syft (nom, étiquettes)"
  hors syft cataloger list -o json > "$T/catalogueurs.json"
  python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
print("sélection par défaut :", json.dumps(d.get("default")), json.dumps(d.get("selection")))
for x in d["catalogers"]:   # structure lue le 12/11/2026 : {"default", "selection", "catalogers": [{"name", "tags"}]}
    if x.get("name") in ("go-module-binary-cataloger", "deb-archive-cataloger", "dpkg-db-cataloger"):
        print(x["name"], ":", ",".join(sorted(x.get("tags") or [])))' "$T/catalogueurs.json"

  echo "## P4 : SBOM de l'artefact seul (syft dir: sur data.tar extrait)"
  (cd "$T/deb" && ar x "$DEB")
  ls "$T/deb"
  tar -xf "$T"/deb/data.tar* -C "$T/data"
  (cd "$T/data" && find . -type f | sort)
  set +e; hors syft scan "dir:$T/data" -o cyclonedx-json="$T/sbom-artefact.json" -q 2> "$T/p4.err"; c=$?; set -e
  echo "code $c, sortie d'erreur : $(wc -c < "$T/p4.err") octets"
  purls "$T/sbom-artefact.json"

  echo "## P5 : le deb comme fichier (syft dir: sur un dossier qui ne contient que lui)"
  cp "$DEB" "$T/fichier/"
  set +e; hors syft scan "dir:$T/fichier" -o cyclonedx-json="$T/sbom-fichier.json" -q 2> "$T/p5.err"; c=$?; set -e
  echo "code $c, sortie d'erreur : $(wc -c < "$T/p5.err") octets"
  purls "$T/sbom-fichier.json"

  echo "## P6 : grype sur le SBOM de P4 (base de G0, sans -q : avertissements gardés)"
  set +e; hors grype "sbom:$T/sbom-artefact.json" -o json --file "$T/grype-artefact.json" 2> "$T/p6.err"; c=$?; set -e
  echo "code $c ; avertissements : $(grep -c -i warn "$T/p6.err" || true)"
  grep -i warn "$T/p6.err" | cut -c1-200 | head -5 || true
  python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
m = d.get("matches", [])
print("correspondances :", len(m), "; distro vue par grype :", json.dumps(d.get("distro")))
for x in sorted(m, key=lambda x: (x["artifact"]["name"], x["vulnerability"]["id"])):
    v, a = x["vulnerability"], x["artifact"]
    kev = "KEV" if v.get("knownExploited") else "-"
    print("  ", a["name"], a["version"], v["id"], v.get("severity"), v.get("namespace"), kev, ",".join(v.get("fix", {}).get("versions", [])))' "$T/grype-artefact.json"

  echo "## P7 : dossier vide avec -q, puis fusion avec le SBOM de la source"
  set +e; hors syft scan "dir:$T/vide" -o cyclonedx-json="$T/sbom-vide.json" -q 2> "$T/p7.err"; c=$?; set -e
  echo "code $c, sortie d'erreur : $(wc -c < "$T/p7.err") octets"
  purls "$T/sbom-vide.json"
  attendu "arbre de poc/sample-app à HEAD" "$(git -C "$racine" rev-parse HEAD:poc/sample-app)" "$ARBRE"
  git -C "$racine" archive --format=tar "$ARBRE" | tar -xf - -C "$T/source"
  hors syft scan "dir:$T/source" -o cyclonedx-json="$T/sbom-source.json" -q
  echo "source seule : $(purls "$T/sbom-source.json" | head -1)"
  (cd "$T" && "$SCAN_OUTIL" fusion sbom-source.json sbom-vide.json source image > sbom-fusion-vide.json)
  echo "fusion source + vide : $(purls "$T/sbom-fusion-vide.json" | head -1)"
  (cd "$T" && "$SCAN_OUTIL" fusion sbom-source.json sbom-artefact.json source image > sbom-fusion-artefact.json)
  echo "fusion source + artefact : $(purls "$T/sbom-fusion-artefact.json" | head -1)"
}

[ "${1:-}" = releve ] && [ $# = 1 ] || { echo "usage : $0 releve" >&2; exit 2; }
chrono "S6a releve"
{ echo "# ${0##*/} releve, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; etape_releve; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/s6a-releve.log"
chrono "S6a releve fait"
