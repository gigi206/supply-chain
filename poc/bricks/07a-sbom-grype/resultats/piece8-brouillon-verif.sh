#!/usr/bin/env bash
# Brique 07b, pièce 8 (2026-11-24) : verdict de signer-vex.sh verifier sur le BROUILLON vex/sample-app-3a7ca1b1.json (proposition
# de la session, non validée par le propriétaire), en LECTURE SEULE sur le vrai Zot (192.168.161.13:5000 ; rien n'est signé).
#   1. le brouillon tel qu'il est dans le dépôt (author et horodatages vides) : refus attendu ;
#   2. une copie jetable avec un auteur témoin (« témoin, aucune analyse ») et l'heure du moment : acceptation attendue, 5 énoncés
#      d'exemption. La copie n'est jamais signée ni gardée (dossier effacé à la fin).
# Juge : scan-outil reconstruit depuis une copie de HEAD (git archive), empreinte exigée 7dde1a8ed457f254, comme vex-gabarit-zot.sh.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1; R=poc/bricks/07a-sbom-grype; D=$R/vex/sample-app-3a7ca1b1.json
B=$HOME/.cache/supply-chain-poc/07a/piece8-brouillon-verif
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
export CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt CLE_SCANNER=$R/resultats/scanner-cle-publique.pem \
  CLE_PUBLIQUE=$R/resultats/vex-cle-publique.pem
APP=192.168.161.13:5000/builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
GO=$(mise which go)
mkdir -p "$B/src" "$B/bin" "$B/cache"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
{
echo "# verdict du brouillon de la pièce 8, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), brouillon sha256 $(sha256sum < "$D" | cut -c1-16)"
echo "## juge : scan-outil depuis une copie de HEAD ($("$GO" version | cut -d' ' -f3))"
git archive HEAD "$R/outil" | tar -x -C "$B/src"
(cd "$B/src/$R/outil" && CGO_ENABLED=0 GOPROXY=off GOCACHE=$B/cache GOFLAGS=-mod=mod \
  "$GO" build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o "$B/bin/scan-outil" .) > "$B/build.err" 2>&1 \
  || echo "construction en échec : $(tail -3 "$B/build.err")"
attendu "empreinte de scan-outil (celle de l'image b799feda)" "$(sha256sum < "$B/bin/scan-outil" 2>/dev/null | cut -c1-16)" 7dde1a8ed457f254
echo "## brouillon"
jq -c '{id: ."@id", author, timestamp, enonces: [.statements[] | {n: .vulnerability.name, j: .justification}]}' "$D"
echo "## 1. brouillon tel quel (author et horodatages vides)"
o=$(env SCAN_OUTIL="$B/bin/scan-outil" timeout 120 bash "$R/signer-vex.sh" verifier "$D" "$APP" 2>&1); c=$?
echo "$o" | cut -c1-220
attendu "brouillon tel quel : refusé" "$c" 1
echo "## 2. copie témoin (auteur témoin, heure du moment), jamais signée"
h=$(date -u +%FT%TZ)
jq --arg h "$h" '.author = "témoin, aucune analyse" | .timestamp = $h | .statements |= map(.timestamp = $h)' "$D" > "$B/temoin.json"
o=$(env SCAN_OUTIL="$B/bin/scan-outil" timeout 120 bash "$R/signer-vex.sh" verifier "$B/temoin.json" "$APP" 2>&1); c=$?
echo "$o" | cut -c1-220
attendu "copie témoin : acceptée" "$c" 0
attendu "copie témoin : exemption de 5 énoncés" "$(grep -c '^JUGE|exemption, 5 énoncé(s)' <<< "$o")" 1
attendu "copie témoin : 5 échéances" "$(grep -c '^ECHEANCE|' <<< "$o")" 5
echo "## dépôt"
attendu "outil/ du dépôt inchangé (git status)" "$(git status --porcelain -- "$R/outil" | wc -l)" 0
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$B" -delete
cat "$J"
