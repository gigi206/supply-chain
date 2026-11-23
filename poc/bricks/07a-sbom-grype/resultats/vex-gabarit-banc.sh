#!/usr/bin/env bash
# Banc de vex-gabarit.sh (07b, pièce 8, préparation ; 2026-11-23, pendant le rejeu un-trait-1) : hôte seul, hors réseau, sans
# registre (PREDICAT=, prédicats archivés dans resultats/), rien dans le cluster ni dans Zot. Juge : scan-outil reconstruit depuis
# une copie de HEAD (git archive), avec les options de piece3-outils-scan.sh, GOPROXY=off, GOCACHE dans le dossier du banc ;
# l'empreinte doit être 7dde1a8ed457f254 (binaire de l'image outils-scan b799feda), sinon le juge n'est pas celui du service.
# Le dossier outil/ du dépôt n'est ni lu en place ni écrit (le rejeu reconstruit l'image depuis lui, « 07a (G2) »).
# Témoin rempli : « témoin, aucune analyse », jamais signé. Dossier jetable sous ~/.cache/supply-chain-poc/07a/banc-vex-gabarit,
# effacé à la fin. Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1; S=poc/bricks/07a-sbom-grype/vex-gabarit.sh; R=poc/bricks/07a-sbom-grype/resultats
B=$HOME/.cache/supply-chain-poc/07a/banc-vex-gabarit
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
APP=192.168.161.13:5000/builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
DEB=192.168.161.13:5000/builds/sample-app-deb@sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e
PA=$R/g4-scan-predicat.json                     # scan de sample-app du rejeu plateforme-1 (16:39:31Z), 6 entrées, bloc vex
PD=$R/07b-t1-predicat-sample-app-deb.json       # scan du deb du 21/11 (11:16:56Z), énoncé in-toto, 67 entrées, sans bloc vex
mkdir -p "$B/src" "$B/bin" "$B/vex" "$B/cache"
N=0; KO=0
attendu() { # libellé obtenu attendu
  N=$((N + 1))
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi
}
juge() { # gabarit hex : « retenus rejetés exemptant raison » de scan-outil vex sur l'énoncé in-toto qui serait signé
  jq -n --arg h "$2" --slurpfile d "$1" '{_type: "https://in-toto.io/Statement/v1", subject: [{name: "x", digest: {sha256: $h}}],
    predicateType: "https://openvex.dev/ns/v0.2.0", predicate: $d[0]}' > "$B/enonce.json"
  "$B/bin/scan-outil" vex "$2" "$B/vex" "$B/enonce.json" > "$B/verdict.json" 2> "$B/verdict.err" || { echo "erreur $(head -c 120 "$B/verdict.err")"; return; }
  jq -r '"\(.retenus | length) \(.rejetes | length) \([.enonces[]?.exemptant] | all) \(.rejetes[0].raison // "-")"' "$B/verdict.json"
}
{
echo "# banc de vex-gabarit.sh, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), script $(sha256sum < "$S" | cut -c1-16)"
echo "## juge : scan-outil depuis une copie de HEAD"
git archive HEAD poc/bricks/07a-sbom-grype/outil | tar -x -C "$B/src"
(cd "$B/src/poc/bricks/07a-sbom-grype/outil" && CGO_ENABLED=0 GOPROXY=off GOCACHE=$B/cache GOFLAGS=-mod=mod \
  go build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o "$B/bin/scan-outil" .) > "$B/build.err" 2>&1 \
  || { echo "construction en échec : $(tail -3 "$B/build.err")"; }
attendu "empreinte de scan-outil (celle de l'image b799feda)" "$(sha256sum < "$B/bin/scan-outil" 2>/dev/null | cut -c1-16)" 7dde1a8ed457f254
echo "## tableau seul"
o=$(PREDICAT=$PA bash "$S" "$APP" - 2>&1); c=$?
attendu "sample-app : code" "$c" 0
attendu "sample-app : lignes du tableau" "$(grep -c '^| [0-9]' <<< "$o")" 6
attendu "sample-app : comptes" "$(grep '^comptes' <<< "$o" | cut -d';' -f1)" "comptes : 6 entrée(s), 6 identifiant(s) "
attendu "sample-app : origine dite non vérifiée" "$(grep -c 'NON VÉRIFIÉ' <<< "$o")" 1
echo "$o" | sed 's/^/     /'
o=$(PREDICAT=$PD bash "$S" "$DEB" - 2>&1); c=$?
attendu "deb (énoncé in-toto) : code" "$c" 0
attendu "deb : lignes du tableau" "$(grep -c '^| [0-9]' <<< "$o")" 67
attendu "deb : alias CVE-2026-114437 dans le tableau" "$(grep -c '| GHSA-j6qf-3m9c-vwj3 | CVE-2026-114437 |' <<< "$o")" 1
grep '^comptes' <<< "$o" | sed 's/^/     /'
echo "## gabarit"
G=$B/g-app.json
o=$(PREDICAT=$PA bash "$S" "$APP" "$G" GHSA-3fxj-6jh8-hvhx 2>&1); c=$?
attendu "gabarit sample-app : code" "$c" 0
attendu "gabarit : un énoncé" "$(jq '.statements | length' "$G")" 1
attendu "gabarit : produit" "$(jq -r '.statements[0].products[0]."@id"' "$G")" "pkg:oci/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5"
attendu "gabarit : sous-composant = paquet du prédicat, octet près" "$(jq -r '.statements[0].products[0].subcomponents[0]."@id"' "$G")" \
  "$(jq -r '.vulnerabilities[] | select(.id == "GHSA-3fxj-6jh8-hvhx") | .package' "$PA")"
attendu "gabarit : champs laissés vides" "$(jq -c '[.author, .timestamp, .statements[0].justification, .statements[0].impact_statement, .statements[0].timestamp]' "$G")" '["","","","",""]'
attendu "gabarit : mode 0600" "$(stat -c %a "$G")" 600
attendu "gabarit brut jugé par scan-outil vex : rejeté" "$(juge "$G" "${APP##*:}" | cut -d' ' -f1,2)" "0 1"
T=$B/temoin.json
jq '.author = "témoin, aucune analyse" | .timestamp = "2026-11-23T00:00:00Z" | ."@id" = "https://supply-chain.example/vex/temoin-gabarit"
  | .statements[0].justification = "vulnerable_code_not_in_execute_path" | .statements[0].impact_statement = "témoin, aucune analyse"
  | .statements[0].timestamp = "2026-11-23T00:00:00Z"' "$G" > "$T"
attendu "témoin rempli jugé par scan-outil vex : retenu, exemptant" "$(juge "$T" "${APP##*:}" | cut -d' ' -f1-3)" "1 0 true"
attendu "témoin rempli, autre digest : rejeté" "$(juge "$T" "${DEB##*:}" | cut -d' ' -f1,2)" "0 1"
G2=$B/g-deb.json
o=$(PREDICAT=$PD bash "$S" "$DEB" "$G2" GHSA-j6qf-3m9c-vwj3 2>&1); c=$?
attendu "gabarit deb : code" "$c" 0
attendu "gabarit deb : alias repris" "$(jq -c '.statements[0].vulnerability' "$G2")" '{"name":"GHSA-j6qf-3m9c-vwj3","aliases":["CVE-2026-114437"]}'
echo "## refus"
o=$(PREDICAT=$PA bash "$S" "$APP" "$B/g-x.json" GHSA-0000-0000-0000 2>&1); c=$?
attendu "identifiant absent du scan : code" "$c" 1
attendu "identifiant absent : aucun fichier écrit" "$(test -e "$B/g-x.json" && echo écrit || echo absent)" absent
o=$(PREDICAT=$PA bash "$S" "$APP" "$G" GHSA-3fxj-6jh8-hvhx 2>&1); c=$?
attendu "gabarit existant : code (jamais réécrit)" "$c" 2
o=$(PREDICAT=$PA bash "$S" "$APP" - GHSA-3fxj-6jh8-hvhx 2>&1); c=$?
attendu "identifiant sans chemin de gabarit : code" "$c" 2
o=$(PREDICAT=$PA bash "$S" "$APP" "$B/g-y.json" 2>&1); c=$?
attendu "chemin sans identifiant : code" "$c" 2
o=$(PREDICAT=$PA bash "$S" "192.168.161.13:5000/builds/sample-app:t" - 2>&1); c=$?
attendu "image sans digest : code" "$c" 2
o=$(env -u CA PREDICAT= bash "$S" "$APP" - 2>&1); c=$?
attendu "sans PREDICAT ni CA : code (rien lu dans un registre)" "$c" 1
echo "## dépôt intact"
attendu "outil/ du dépôt inchangé (git status)" "$(git status --porcelain -- poc/bricks/07a-sbom-grype/outil | wc -l)" 0
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$HOME/.cache/supply-chain-poc/07a/banc-vex-gabarit" -delete
cat "$J"
