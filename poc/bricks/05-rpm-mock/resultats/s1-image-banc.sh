#!/usr/bin/env bash
# Banc local de l'étape image de s1.sh (brique 05) : mêmes commandes crane append et mutate qu'etape_image, contre un registre
# crane temporaire en loopback (disque sous ~/.cache), sans Zot ni cluster ni authentification ; rien n'est écrit sous $T.
# Usage : banc-image.sh <racine-du-dépôt> <dossier-du-banc-config>
set -euo pipefail
export LC_ALL=C
D=$1; BC=$2
O=$HOME/.cache/supply-chain-poc
T=$O/08/travail/s1-05
B=$O/05/banc-image
ADR=127.0.0.1:5905
DEPOT=essais-05/mock-rocky9
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)"; exit 1; }; }
CRANE=$(cd "$D" && mise which crane)
crane() { "$CRANE" "$@"; }

echo "# banc-image.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), crane $(crane version), $(tar --version | head -1)"
attendu "sha256 de s1.sh" "$(sha256sum < "$D/poc/bricks/05-rpm-mock/s1.sh" | cut -c1-64)" \
  ad16fc9909308b2e8f2703114ed0e37e67b73095b9f3b32128890bd4d81a3e63
echo "## A : couche de configuration rejouée à sec (banc-config.sh, extrait de etape_image par banc-config.py)"
bash "$BC/banc-config.sh" </dev/null | grep -v '^[-d]r'
attendu "couche-config.tar rejouée une seconde fois" "$(bash "$BC/banc-config.sh" </dev/null >/dev/null && sha256sum < "$BC/couche-config.tar" | cut -c1-64)" \
  f5710d475bc0e83b67701a96b5aa3dbd01fe971d2d68f097358019c72ba52560
echo "## B : entrée et modèle de mock"
attendu "sha256 de racine.tar (étape racine)" "$(sha256sum < "$T/racine.tar" | cut -c1-64)" \
  d7433a050469836de7317de87f2421d3bc7eaa52052cf422518809e276a94a9d
a=$(tar -xOf "$T/racine.tar" ./etc/mock/templates/rocky-9.tpl | sha256sum | cut -c1-64)
attendu "sha256 de l'archive amont de mock (m2)" "$(sha256sum < "$O/05/m2/mock.tar.gz" | cut -c1-64)" \
  3c034916a721bb06b923399c856d5111fbf3d791804934dd6d909e3d292e4d88
m=$(tar -xzOf "$O/05/m2/mock.tar.gz" mock-mock-6.9-1/mock-core-configs/etc/mock/templates/rocky-9.tpl | sha256sum | cut -c1-64)
attendu "rocky-9.tpl de la racine égal à celui de mock-6.9-1 (archive m2)" "$a" "$m"
echo "## C : append puis mutate contre un registre crane local ($ADR, disque $B)"
[ ! -e "$B" ] || { echo "KO   $B existe déjà"; exit 1; }
mkdir -p "$B/disque"
"$CRANE" registry serve --address "$ADR" --disk "$B/disque" > "$B/serve.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null; wait $srv 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://$ADR/v2/" >/dev/null && echo "registre local : prêt (http)"
t=$(date +%s)
crane append --oci-empty-base -f "$T/racine.tar" -f "$BC/couche-config.tar" -t "$ADR/$DEPOT:s1" >/dev/null 2>"$B/crane.err" \
  || { cat "$B/crane.err"; exit 1; }
echo "crane append : rc 0 en $(($(date +%s) - t)) s"
crane mutate "$ADR/$DEPOT:s1" --set-platform linux/amd64 -t "$ADR/$DEPOT:s1" \
  -e PATH=/usr/sbin:/usr/bin:/sbin:/bin -e HOME=/root >/dev/null 2>"$B/crane.err" || { cat "$B/crane.err"; exit 1; }
echo "crane mutate : rc 0"
d=$(crane digest "$ADR/$DEPOT:s1")
crane manifest "$ADR/$DEPOT@$d" | jq -r '.layers[] | "couche \(.digest) \(.size) octets"'
crane manifest "$ADR/$DEPOT@$d" | jq -r '"manifeste : \(.mediaType) ; config \(.config.mediaType) \(.config.digest) ; couches \([.layers[].mediaType] | unique | join(","))"'
crane config "$ADR/$DEPOT@$d" | jq -r '"config : os \(.os) ; architecture \(.architecture) ; Env \(.config.Env | join(" ")) ; created \(.created // "absent") ; history \(.history | length // 0)"'
echo "image d'essai (banc) : $DEPOT@$d"
echo "place du registre local : $(du -sm "$B/disque" | cut -f1) Mo"
