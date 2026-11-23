#!/usr/bin/env bash
# Brique 07b, pièce 8, préparation : vex-gabarit.sh sur le VRAI Zot après la reprise du rejeu un-trait-1 (2026-11-23), en
# LECTURE SEULE (cosign verify-attestation et lectures anonymes ; rien n'est signé, rien n'est écrit dans Zot ni dans le cluster).
#   1. tableaux des entrées des scans signés de sample-app et du deb (clé du scanner archivée, resultats/scanner-cle-publique.pem) ;
#   2. recoupement : un gabarit pour une entrée de sample-app, rempli en TÉMOIN (« témoin, aucune analyse »), jugé par
#      signer-vex.sh verifier (même lecture du scan, scan-outil vex, VEX publiés lus par la clé VEX archivée). Le témoin n'est
#      jamais signé ni gardé : il vit dans un dossier jetable effacé à la fin.
# Juge : scan-outil reconstruit depuis une copie de HEAD (git archive), comme vex-gabarit-banc.sh ; empreinte exigée
# 7dde1a8ed457f254 (binaire de l'image outils-scan b799feda). Le nom sc-stockage.poc.test ne se résout pas sur l'hôte : le
# registre est lu par son adresse (192.168.161.13:5000), comme dans le banc.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1; R=poc/bricks/07a-sbom-grype; S=$R/vex-gabarit.sh
B=$HOME/.cache/supply-chain-poc/07a/vex-gabarit-zot
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
export CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt CLE_SCANNER=$R/resultats/scanner-cle-publique.pem \
  CLE_PUBLIQUE=$R/resultats/vex-cle-publique.pem
APP=192.168.161.13:5000/builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
DEB=192.168.161.13:5000/builds/sample-app-deb@sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e
ID=GHSA-3fxj-6jh8-hvhx
GO=$(mise which go)
mkdir -p "$B/src" "$B/bin" "$B/cache"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
spki() { openssl pkey -pubin -in "$1" -outform DER | sha256sum | cut -c1-16; }
{
echo "# vex-gabarit.sh sur le vrai Zot, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), script $(sha256sum < "$S" | cut -c1-16)"
echo "clés archivées : scanner SPKI $(spki "$CLE_SCANNER") ; VEX SPKI $(spki "$CLE_PUBLIQUE")"
echo "## juge : scan-outil depuis une copie de HEAD ($("$GO" version | cut -d' ' -f3))"
git archive HEAD "$R/outil" | tar -x -C "$B/src"
(cd "$B/src/$R/outil" && CGO_ENABLED=0 GOPROXY=off GOCACHE=$B/cache GOFLAGS=-mod=mod \
  "$GO" build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o "$B/bin/scan-outil" .) > "$B/build.err" 2>&1 \
  || echo "construction en échec : $(tail -3 "$B/build.err")"
attendu "empreinte de scan-outil (celle de l'image b799feda)" "$(sha256sum < "$B/bin/scan-outil" 2>/dev/null | cut -c1-16)" 7dde1a8ed457f254
echo "## 1. tableaux (scans signés, vérifiés par la clé du scanner)"
for i in "$APP" "$DEB"; do
  echo "### ${i%@*}"
  o=$(timeout 120 bash "$S" "$i" - 2>&1); c=$?
  echo "$o"
  attendu "code" "$c" 0
  attendu "scan vérifié, jamais « NON VÉRIFIÉ »" "$(grep -c 'NON VÉRIFIÉ' <<< "$o")" 0
done
echo "## 2. témoin jamais signé, jugé par signer-vex.sh verifier"
G=$B/gabarit.json T=$B/temoin.json
timeout 120 bash "$S" "$APP" "$G" "$ID" > "$B/g.out" 2>&1; attendu "gabarit $ID : code" "$?" 0
jq -c '{produit: .statements[0].products[0]."@id", sous: [.statements[0].products[0].subcomponents[]."@id"], vuln: .statements[0].vulnerability}' "$G"
o=$(env SCAN_OUTIL="$B/bin/scan-outil" timeout 120 bash "$R/signer-vex.sh" verifier "$G" "$APP" 2>&1); c=$?
attendu "gabarit brut (champs vides) : refusé par verifier" "$c" 1
grep '^REFUS|' <<< "$o" | head -2 | cut -c1-200
h=$(date -u +%FT%TZ)
jq --arg h "$h" '.author = "témoin, aucune analyse" | .timestamp = $h | ."@id" = "https://supply-chain.example/vex/temoin-zot"
  | .statements[0].justification = "vulnerable_code_not_in_execute_path" | .statements[0].impact_statement = "témoin, aucune analyse"
  | .statements[0].timestamp = $h' "$G" > "$T"
o=$(env SCAN_OUTIL="$B/bin/scan-outil" timeout 120 bash "$R/signer-vex.sh" verifier "$T" "$APP" 2>&1); c=$?
echo "$o" | cut -c1-220
attendu "témoin rempli : accepté par verifier (rien signé)" "$c" 0
attendu "VEX publiés sur sample-app (ligne PUBLIES)" "$(grep -c '^PUBLIES|' <<< "$o")" 1
echo "## dépôt et registre"
attendu "outil/ du dépôt inchangé (git status)" "$(git status --porcelain -- "$R/outil" | wc -l)" 0
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$B" -delete
cat "$J"
