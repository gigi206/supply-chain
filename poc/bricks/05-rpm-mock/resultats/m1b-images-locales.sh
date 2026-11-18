#!/usr/bin/env bash
# Brique 05, M1b : images de l'amorce (rockylinux:9.8, ed654c69) et du bootstrap (rockylinux:9.7, ee90dc0e) dans le cache OCI
# local de s1.sh amorce : présence et sha256 du manifeste, de la configuration et des couches. (18/11/2026)
# Lecture seule ; aucun réseau ; rien n'est installé.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-images-locales.sh > poc/bricks/05-rpm-mock/resultats/m1b-images-locales.log 2>&1
set -euo pipefail
export LC_ALL=C
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux   # cache de s1.sh amorce : lecture seule
echo "# m1b-images-locales.sh, début $(date -u +%FT%TZ)"
echo "index.json du cache : $(python3 -I -c 'import json, sys; print(" ".join(m["digest"][7:19] for m in json.load(open(sys.argv[1]))["manifests"]))' "$O/index.json")"
ko=0
for x in "amorce ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d" "bootstrap ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2"; do
  set -- $x
  echo "## $1 (${2:0:12})"
  while read -r k d s; do
    f=$O/blobs/sha256/$d
    if [ -s "$f" ] && [ "$(stat -c %s "$f")" = "$s" ] && [ "$(sha256sum < "$f" | cut -c1-64)" = "$d" ]; then echo "OK   $k ${d:0:12} : $s octets, sha256 égal"
    else echo "KO   $k ${d:0:12} : absent, taille ou sha256 différents"; ko=1; fi
  done < <(python3 -I -c 'import json, os, sys
p = sys.argv[1]; j = json.load(open(p))
print("manifeste", os.path.basename(p), os.path.getsize(p))
print("configuration", j["config"]["digest"][7:], j["config"]["size"])
for l in j["layers"]: print("couche", l["digest"][7:], l["size"])' "$O/blobs/sha256/$2")
done
echo "# fin $(date -u +%FT%TZ), code $ko"
exit $ko
