#!/usr/bin/env bash
# Brique 07c, étape 6 (2026-11-24) : faits pour le brouillon du VEX chi de l'image reconstruite en Go 1.26.11
# (builds/sample-app@sha256:f5e6bcb0…), mesurés sur l'ARTEFACT, pas sur les sources. Copie de
# poc/bricks/07a-sbom-grype/resultats/piece8-binaire.sh (passage 4, celui du VEX de 3a7ca1b1), avec trois ajouts :
#   - entrées du scan signé en vigueur (vex-gabarit.sh, scan vérifié par la clé du scanner) et gabarit des 5 identifiants :
#     noms, alias et sous-composants comparés à ceux du VEX de 3a7ca1b1 (produit mis à part) ;
#   - empreinte du binaire exigée (celle du banc de l'hôte, étape 2) et paquets de chi liés = exactement le paquet racine ;
#   - fiches OSV des 5 identifiants relues (api.osv.dev), empreintes et imports au journal.
# Le bloc MaxBytes (GO-2026-6859) de l'original est retiré : la stdlib 1.26.11 n'a plus d'entrée.
# LECTURE SEULE : lecture anonyme de Zot (crane vérifie le digest demandé), rien n'est écrit dans Zot ni dans le cluster, rien
# n'est signé. Le binaire n'est jamais exécuté : il est lu (go version -m, noms de la table pclntab et chaînes, par strings).
# La CA du PoC ne sert qu'à crane (SSL_CERT_FILE par commande) : curl vers api.osv.dev garde les CA du système (leçon du
# passage 1 de deb-tri.sh).
# Dossier jetable sous ~/.cache/supply-chain-poc/07c/vex-binaire, effacé à la fin.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1; R7=poc/bricks/07a-sbom-grype
B=$HOME/.cache/supply-chain-poc/07c/vex-binaire
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
export CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt CLE_SCANNER=$R7/resultats/scanner-cle-publique.pem
IMG=192.168.161.13:5000/builds/sample-app@sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7
ANCIEN=$R7/vex/sample-app-3a7ca1b1.json
GO=$(mise which go)
mkdir -p "$B/fs" "$B/osv"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
compte() { grep -c -- "$1" "$B/noms" || true; }
cr() { SSL_CERT_FILE=$CA crane "$@"; }
{
echo "# binaire de sample-app reconstruite (Go 1.26.11), $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), crane $(crane version)"
echo "## 1. entrées du scan signé en vigueur (vex-gabarit.sh)"
o=$(timeout 180 bash "$R7/vex-gabarit.sh" "$IMG" - 2>&1); echo "$o" | cut -c1-220
grep '^| [0-9]' <<< "$o" | awk -F'|' '{gsub(/ /, "", $3); print $3}' | sort -u > "$B/ids"
attendu "identifiants du scan = noms du VEX de 3a7ca1b1" "$(paste -sd, "$B/ids")" "$(jq -r '.statements[].vulnerability.name' "$ANCIEN" | sort -u | paste -sd,)"
attendu "entrées hors chi" "$(grep '^| [0-9]' <<< "$o" | grep -vc 'go-chi/chi' || true)" 0
# shellcheck disable=SC2046
timeout 180 bash "$R7/vex-gabarit.sh" "$IMG" "$B/gabarit.json" $(cat "$B/ids") > "$B/gabarit.out" 2>&1; echo "gabarit : code $?"
forme() { jq -cS '[.statements[] | {v: .vulnerability, s: [.products[].subcomponents[]."@id"]}] | sort_by(.v.name)' "$1"; }
attendu "gabarit : noms, alias et sous-composants = ceux du VEX de 3a7ca1b1" "$(forme "$B/gabarit.json" | sha256sum | cut -c1-16)" "$(forme "$ANCIEN" | sha256sum | cut -c1-16)"
attendu "gabarit : produit" "$(jq -r '[.statements[].products[]."@id"] | unique | join(",")' "$B/gabarit.json")" "pkg:oci/sample-app@sha256:${IMG##*@sha256:}"
echo "## 2. image (lecture anonyme)"
attendu "digest du manifeste relu" "$(cr digest "$IMG" 2>&1)" "sha256:${IMG##*@sha256:}"
cr config "$IMG" | jq -c '{Entrypoint: .config.Entrypoint, Cmd: .config.Cmd, User: .config.User}'
cr export "$IMG" - | tar -x -C "$B/fs" 2>"$B/tar.err"; echo "tar : code $? ; $(wc -l < "$B/tar.err") ligne(s) d'erreur"
E=$(cr config "$IMG" | jq -r '.config.Entrypoint[0] // .config.Cmd[0]')
X=$B/fs/${E#/}
echo "point d'entrée : $E ; $(stat -c %s "$X") octets"
attendu "binaire : sha256 (celui du banc de l'hôte, étape 2)" "$(sha256sum < "$X" | cut -c1-64)" 56f3cd7d256562bef660f596de462af4105462356858b11f71cd04761c13b5c2
file -b "$X" | cut -c1-160
echo "## 3. modules liés (go version -m)"
"$GO" version -m "$X" | sed 's/^/  /'
attendu "Go du binaire" "$("$GO" version "$X" | awk '{print $2}')" go1.26.11
attendu "module chi lié" "$("$GO" version -m "$X" | awk '$1 == "dep" {print $2 "@" $3}' | grep -c '^github.com/go-chi/chi/v5@v5.2.3$')" 1
echo "## 4. noms de fonctions (pclntab, par strings)"
strings -n 6 "$X" | grep -E '^(github\.com/go-chi/|net/http\.|main\.)' | sort -u > "$B/noms"
echo "noms retenus : $(wc -l < "$B/noms") ; dont chi : $(compte '^github.com/go-chi/')"
echo "### témoins (doivent être présents : le code de main.go)"
attendu "chi : (*Mux).ServeHTTP" "$(compte '^github.com/go-chi/chi/v5\.(\*Mux)\.ServeHTTP$')" 1
attendu "chi : (*Mux).routeHTTP" "$(compte '^github.com/go-chi/chi/v5\.(\*Mux)\.routeHTTP$')" 1
attendu "net/http : (*Server).Serve" "$(compte '^net/http\.(\*Server)\.Serve$')" 1
echo "### paquets de chi liés"
sed -n 's#^\(github.com/go-chi/chi/v5[^.(]*\)[.(].*#\1#p' "$B/noms" | sort | uniq -c | sed 's/^/  /'
attendu "paquets de chi liés = le seul paquet racine" "$(sed -n 's#^\(github.com/go-chi/[^.(]*\)[.(].*#\1#p' "$B/noms" | sort -u | paste -sd,)" github.com/go-chi/chi/v5
attendu "aucune fonction du paquet chi/v5/middleware liée" "$(compte '^github.com/go-chi/chi/v5/middleware')" 0
echo "### fichiers sources de chi cités par le binaire"
strings -n 6 "$X" | grep -o 'github.com/go-chi/chi/v5@v5[^ ]*\.go' | sort -u > "$B/fichiers"; sed 's/^/  /' "$B/fichiers"
attendu "fichiers sources de chi : les 7 du binaire de 3a7ca1b1" "$(sed 's#.*/##' "$B/fichiers" | paste -sd,)" chain.go,chi.go,context.go,mux.go,path_value.go,pattern.go,tree.go
attendu "chemins de fichiers sources sous middleware/" "$(strings -n 6 "$X" | grep -c 'chi/v5@v5[^ ]*/middleware/' || true)" 0
strings -n 4 "$X" > "$B/chaines"
attendu "chemin de paquet chi/v5/middleware (toutes les chaînes)" "$(grep -c 'chi/v5/middleware' "$B/chaines" || true)" 0
attendu "nom qualifié « middleware. » (toutes les chaînes)" "$(grep -c 'middleware\.' "$B/chaines" || true)" 0
attendu "« middleware » hors de « [Mm]iddlewares » (toutes les chaînes)" "$(sed 's/[Mm]iddlewares//g' "$B/chaines" | grep -ci 'middleware' || true)" 0
grep -i 'middleware' "$B/chaines" | cut -c1-200 | sed 's/^/  chaîne : /'
for m in RealIP ClientIPFromXFF GetClientIP RedirectSlashes; do
  attendu "$m (toutes les chaînes)" "$(grep -c "$m" "$B/chaines" || true)" 0
done
attendu "« realip » ou « strip.go » dans toutes les chaînes" "$(grep -ciE 'realip|/strip\.go' "$B/chaines" || true)" 0
echo "## 5. fiches OSV (api.osv.dev)"
while read -r id; do
  curl -fsS --max-time 30 "https://api.osv.dev/v1/vulns/$id" -o "$B/osv/$id.json" || echo "fiche illisible : $id"
done < "$B/ids"
attendu "fiches lues (une par identifiant)" "$(find "$B/osv" -name '*.json' -size +0 | wc -l)" "$(wc -l < "$B/ids")"
while read -r id; do
  f=$B/osv/$id.json; test -s "$f" || continue
  echo "  $id : sha256 $(sha256sum < "$f" | cut -c1-16) ; modifiée $(jq -r '.modified' "$f") ; alias $(jq -r '(.aliases // []) | join(",")' "$f")"
  jq -r '[.affected[]? | .package.name as $p | (.ranges[]?.events[]? | select(.fixed) | "corrigé \($p)@\(.fixed)"),
    (.ecosystem_specific.imports[]? | "imports \(.path) : \((.symbols // []) | join(" "))")] | unique | .[]' "$f" | sed 's/^/    /'
done < "$B/ids"
attendu "imports des fiches : aucun hors chi/v5/middleware" "$(cat "$B"/osv/*.json | jq -r '.affected[]?.ecosystem_specific.imports[]?.path' | sort -u | grep -vc '^github.com/go-chi/chi/v5/middleware$' || true)" 0
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$B" -delete
cat "$J"
