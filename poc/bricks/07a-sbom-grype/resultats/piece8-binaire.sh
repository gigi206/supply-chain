#!/usr/bin/env bash
# Brique 07b, pièce 8 (2026-11-24) : faits pour le brouillon du VEX de sample-app, mesurés sur l'ARTEFACT signé, pas sur les
# sources. LECTURE SEULE : crane export de builds/sample-app@sha256:3a7ca1b1… en lecture anonyme (crane vérifie le digest du
# manifeste demandé), rien n'est écrit dans Zot ni dans le cluster. Le binaire n'est jamais exécuté : il est lu (go version -m,
# et les noms de fonctions de sa table pclntab, présente même dans un binaire lié avec -s -w, par strings).
# Un nom de fonction présent dit que le code est LIÉ dans le binaire, pas qu'il est appelé ; un nom absent dit qu'il n'est pas
# lié (ou qu'il a été entièrement inliné : les témoins ci-dessous bornent ce risque pour chi).
# Dossier jetable sous ~/.cache/supply-chain-poc/07a/piece8-binaire, effacé à la fin.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
B=$HOME/.cache/supply-chain-poc/07a/piece8-binaire
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
IMG=192.168.161.13:5000/builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
export SSL_CERT_FILE=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
GO=$(mise which go)
mkdir -p "$B/fs"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
compte() { grep -c -- "$1" "$B/noms" || true; }
{
echo "# binaire de sample-app, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), crane $(crane version)"
echo "## image (lecture anonyme)"
attendu "digest du manifeste relu" "$(crane digest "$IMG" 2>&1)" "sha256:${IMG##*@sha256:}"
crane config "$IMG" | jq -c '{Entrypoint: .config.Entrypoint, Cmd: .config.Cmd, User: .config.User}'
crane export "$IMG" - | tar -x -C "$B/fs" 2>"$B/tar.err"; echo "tar : code $? ; $(wc -l < "$B/tar.err") ligne(s) d'erreur"
E=$(crane config "$IMG" | jq -r '.config.Entrypoint[0] // .config.Cmd[0]')
X=$B/fs/${E#/}
echo "point d'entrée : $E ; $(stat -c %s "$X") octets ; sha256 $(sha256sum < "$X" | cut -c1-16)"
file -b "$X" | cut -c1-160
echo "## modules liés (go version -m)"
"$GO" version -m "$X" | sed 's/^/  /'
attendu "module chi lié" "$("$GO" version -m "$X" | awk '$1 == "dep" {print $2 "@" $3}' | grep -c '^github.com/go-chi/chi/v5@v5.2.3$')" 1
echo "## noms de fonctions (pclntab, par strings)"
strings -n 6 "$X" | grep -E '^(github\.com/go-chi/|net/http\.|main\.)' | sort -u > "$B/noms"
echo "noms retenus : $(wc -l < "$B/noms") ; dont chi : $(compte '^github.com/go-chi/')"
echo "### témoins (doivent être présents : le code de main.go)"
attendu "chi : (*Mux).ServeHTTP" "$(compte '^github.com/go-chi/chi/v5\.(\*Mux)\.ServeHTTP$')" 1
attendu "chi : (*Mux).routeHTTP" "$(compte '^github.com/go-chi/chi/v5\.(\*Mux)\.routeHTTP$')" 1
attendu "net/http : (*Server).Serve" "$(compte '^net/http\.(\*Server)\.Serve$')" 1
echo "### paquets de chi liés"
sed -n 's#^\(github.com/go-chi/chi/v5[^.(]*\)[.(].*#\1#p' "$B/noms" | sort | uniq -c | sed 's/^/  /'
echo "### fonctions nommées par les fiches OSV"
for m in 'github.com/go-chi/chi/v5/middleware' 'RealIP' 'realIP' 'ClientIPFromXFF' 'GetClientIP' 'RedirectSlashes'; do
  echo "  $m : $(compte "$m")"
done
attendu "aucune fonction du paquet chi/v5/middleware liée" "$(compte '^github.com/go-chi/chi/v5/middleware')" 0
# passage 2 (conseiller, 2026-11-24) : chemins de fichiers sources de chi (…/chi/v5@v5.2.3/<fichier>.go) ; un fichier du
# middleware inliné y laisserait son chemin (…@v5.2.3/middleware/realip.go) ; et « middleware » sur TOUTES les chaînes
echo "### fichiers sources de chi cités par le binaire"
strings -n 6 "$X" | grep -o 'github.com/go-chi/chi/v5@v5[^ ]*\.go' | sort -u | sed 's/^/  /'
attendu "chemins de fichiers sources sous middleware/" "$(strings -n 6 "$X" | grep -c 'chi/v5@v5[^ ]*/middleware/' || true)" 0
# passage 4 : l'attente « middleware = 0 » du passage 2 était fausse (critère trop large) : les 5 chaînes du passage 3 sont le type
# Middlewares du paquet racine chi/v5 (chain.go). Attentes remplacées par trois comptes ciblés, sur TOUTES les chaînes.
strings -n 4 "$X" > "$B/chaines"
attendu "chemin de paquet chi/v5/middleware (toutes les chaînes)" "$(grep -c 'chi/v5/middleware' "$B/chaines" || true)" 0
attendu "nom qualifié « middleware. » (toutes les chaînes)" "$(grep -c 'middleware\.' "$B/chaines" || true)" 0
attendu "« middleware » hors de « [Mm]iddlewares » (toutes les chaînes)" "$(sed 's/[Mm]iddlewares//g' "$B/chaines" | grep -ci 'middleware' || true)" 0
grep -i 'middleware' "$B/chaines" | cut -c1-200 | sed 's/^/  chaîne : /'
for m in RealIP ClientIPFromXFF GetClientIP RedirectSlashes; do
  attendu "$m (toutes les chaînes)" "$(grep -c "$m" "$B/chaines" || true)" 0
done
attendu "« realip » ou « strip.go » dans toutes les chaînes" "$(strings -n 4 "$X" | grep -ciE 'realip|/strip\.go' || true)" 0
echo "### net/http : MaxBytesReader et MaxBytesHandler (GO-2026-6859)"
grep -E 'MaxBytes|maxBytes' "$B/noms" | sed 's/^/  /'
echo "  lignes : $(compte 'MaxBytes\|maxBytes')"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$B" -delete
cat "$J"
