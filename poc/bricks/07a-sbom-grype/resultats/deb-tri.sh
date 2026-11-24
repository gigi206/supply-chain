#!/usr/bin/env bash
# Brique 07b, VEX du deb (choix du propriétaire du 2026-11-24 : « Paquet deb : lui faire un VEX » → « oui ») : TRI des entrées
# du dernier scan signé de builds/sample-app-deb@sha256:60f25f5c…, mesuré sur le binaire du paquet. LECTURE SEULE : lecture
# anonyme de Zot (crane vérifie le digest demandé), fiches OSV lues par api.osv.dev ; rien n'est écrit dans Zot ni dans le
# cluster ; rien n'est signé. Le binaire n'est jamais exécuté.
#   1. entrées : vex-gabarit.sh (scan signé le plus récent, vérifié par la clé du scanner) ;
#   2. binaire : /usr/bin/sample-app extrait du .deb (dpkg-deb -x) ; go version -m ; noms de fonctions (pclntab, par strings) ;
#   3. fiches OSV (api.osv.dev/v1/vulns/<id>) gardées sous ~/.cache/supply-chain-poc/07a/deb-osv (empreintes au journal) ;
#      pour chaque entrée, paquets et symboles de affected[].ecosystem_specific.imports ;
#   4. classe de chaque entrée :
#        A  aucun paquet visé n'est lié (aucun nom de fonction « paquet. ») : candidat solide (vulnerable_code_not_present)
#        B  paquet lié, aucun des symboles listés présent : fragile (inlining possible), à étayer ou à laisser
#        C  au moins un symbole listé présent : non couvert
#        P  paquet lié et fiche sans liste de symboles : non couvert
#        X  fiche illisible ou sans imports : non classé
# Un nom présent dit que le code est LIÉ, pas qu'il est appelé ; un nom absent dit qu'il n'est pas lié, ou qu'il a été inliné.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1; R=poc/bricks/07a-sbom-grype
B=$HOME/.cache/supply-chain-poc/07a/deb-tri
F=$HOME/.cache/supply-chain-poc/07a/deb-osv
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$F" || { echo "existe déjà : $F"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
export CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt CLE_SCANNER=$R/resultats/scanner-cle-publique.pem
export SSL_CERT_FILE=$CA
DEB=192.168.161.13:5000/builds/sample-app-deb@sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e
GO=$(mise which go)
mkdir -p "$B/oci" "$B/racine" "$F"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
{
echo "# tri des entrées du deb, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), crane $(crane version)"
echo "## 1. entrées du dernier scan signé (vex-gabarit.sh)"
o=$(timeout 180 bash "$R/vex-gabarit.sh" "$DEB" - 2>&1); echo "$o" | grep -v '^| [0-9]' | cut -c1-220
grep '^| [0-9]' <<< "$o" | awk -F'|' '{for (i = 2; i <= NF; i++) gsub(/^ +| +$/, "", $i); print $3 "\t" $5 "\t" $8}' > "$B/entrees.tsv"
echo "entrées : $(wc -l < "$B/entrees.tsv") ; stdlib : $(grep -c 'stdlib' "$B/entrees.tsv") ; chi : $(grep -c 'go-chi' "$B/entrees.tsv")"
echo "## 2. binaire du paquet"
attendu "digest du manifeste relu" "$(crane digest "$DEB" 2>&1)" "sha256:${DEB##*@sha256:}"
crane export "$DEB" - | tar -x -C "$B/oci"; deb=$(ls "$B/oci"/*.deb)
echo "paquet : ${deb##*/} ; sha256 $(sha256sum < "$deb" | cut -c1-16)"
dpkg-deb -x "$deb" "$B/racine"; X=$B/racine/usr/bin/sample-app
echo "binaire : $(stat -c %s "$X") octets ; sha256 $(sha256sum < "$X" | cut -c1-16)"; file -b "$X" | cut -c1-160
"$GO" version -m "$X" | sed 's/^/  /'
strings -n 4 "$X" > "$B/chaines"
grep -E '^[a-z0-9_./-]+(\.|\.\(\*)[A-Za-z_]' "$B/chaines" | sort -u > "$B/noms"
echo "noms de fonctions retenus : $(wc -l < "$B/noms")"
attendu "pclntab exploitable : net/http.(*Server).Serve" "$(grep -c '^net/http\.(\*Server)\.Serve$' "$B/noms")" 1
attendu "pclntab exploitable : chi (*Mux).ServeHTTP" "$(grep -c '^github.com/go-chi/chi/v5\.(\*Mux)\.ServeHTTP$' "$B/noms")" 1
echo "## 3. fiches OSV (api.osv.dev)"
cut -f1 "$B/entrees.tsv" | sort -u | while read -r id; do
  curl -fsS --max-time 30 "https://api.osv.dev/v1/vulns/$id" -o "$F/$id.json" || echo "fiche illisible : $id"
done
echo "fiches : $(ls "$F" | wc -l) ; empreinte de l'ensemble (sha256 des sha256 triés) : $(cd "$F" && sha256sum -- *.json | sort | sha256sum | cut -c1-16)"
(cd "$F" && sha256sum -- *.json | sed 's/^/  /')
echo "## 4. classes"
echo "  identifiant | gravité | classe | paquets visés (lié ?) | symboles présents / listés"
while IFS=$'\t' read -r id grav paq; do
  f=$F/$id.json
  if ! jq -e '[.affected[]?.ecosystem_specific.imports[]?] | length > 0' "$f" >/dev/null 2>&1; then
    echo "  $id | $grav | X | ($paq) | -"; continue
  fi
  lies=""; nlies=0; pres=0; tot=0; sanssym=0
  while IFS=$'\t' read -r p syms; do
    pe=$(sed 's/[.[\*^$]/\\&/g' <<< "$p")
    if grep -qE "^$pe\.(\(\*)?[A-Za-z_]" "$B/noms"; then lies="$lies $p(oui)"; nlies=$((nlies + 1)); else lies="$lies $p(non)"; fi
    if [ -z "$syms" ]; then sanssym=1; continue; fi
    for s in $syms; do
      tot=$((tot + 1))
      if [[ $s == *.* ]]; then t=${s%%.*}; m=${s#*.}; re="^$pe\.(\(\*$t\)|$t)\.$m(\[.*\])?$"; else re="^$pe\.$s(\[.*\])?$"; fi
      grep -qE "$re" "$B/noms" && pres=$((pres + 1))
    done
  done < <(jq -r '[.affected[]?.ecosystem_specific.imports[]?] | unique_by(.path) | .[] | [.path, ((.symbols // []) | join(" "))] | @tsv' "$f")
  if [ "$nlies" = 0 ]; then c=A; elif [ "$pres" -gt 0 ]; then c=C; elif [ "$sanssym" = 1 ]; then c=P; else c=B; fi
  echo "  $id | $grav | $c |$lies | $pres / $tot"
done < "$B/entrees.tsv" | tee "$B/classes"
echo "## comptes"
for c in A B C P X; do echo "  classe $c : $(grep -c " | $c | " "$B/classes")"; done
for id in GO-2026-4337 GO-2026-6604 GO-2026-6612; do echo "  Critical $id : $(grep " $id | " "$B/classes" | cut -d'|' -f3 | tr -d ' ')"; done
attendu "toutes les entrées classées" "$(wc -l < "$B/classes")" "$(wc -l < "$B/entrees.tsv")"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$B" -delete
cat "$J"
