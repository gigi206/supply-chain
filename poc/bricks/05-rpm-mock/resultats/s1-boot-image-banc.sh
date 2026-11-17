#!/usr/bin/env bash
# Passage local de l'étape boot_image de s1.sh (brique 05) avec la vraie archive de boot_racine : la fonction etape_boot_image,
# extraite de s1.sh, contre un registre crane temporaire en loopback (disque sous ~/.cache), sans Zot ni cluster ni
# authentification ; rien n'est écrit sous $T. Deux passages sur la même archive : le digest d'image est-il le même ?
# L'archive est liée par un lien dur (même système de fichiers) : un lien symbolique fausserait le stat de la fonction.
# Usage : banc-boot-image.sh <racine-du-dépôt> [dossier T] [dossier du banc] [adresse]  (défauts : vrai passage)
set -euo pipefail
export LC_ALL=C
D=$1
O=$HOME/.cache/supply-chain-poc
T=${2:-$O/08/travail/s1-05}
B=${3:-$O/05/banc-boot-image}
ADR=${4:-127.0.0.1:5907}
S1=$D/poc/bricks/05-rpm-mock/s1.sh
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)"; exit 1; }; }
CRANE=$(cd "$D" && mise which crane)

echo "# banc-boot-image.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), crane $("$CRANE" version)"
attendu "sha256 de s1.sh" "$(sha256sum < "$S1" | cut -c1-64)" 2b0a3b7b9bdd0252a6700e084095006077d0f98f8fa9c2436af6908434d153e9
[ -s "$T/boot-racine.tar" ] && [ -s "$T/boot-racine.sha256" ] || { echo "KO   archive de boot_racine absente"; exit 1; }
echo "archive de boot_racine : $(stat -c %s "$T/boot-racine.tar") octets, sha256 attendu $(cat "$T/boot-racine.sha256")"
[ ! -e "$B" ] || { echo "KO   $B existe déjà"; exit 1; }
! curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 || { echo "KO   $ADR déjà pris"; exit 1; }
mkdir -p "$B/disque" "$B/t1/docker" "$B/t2/docker"
for t in t1 t2; do ln "$T/boot-racine.tar" "$B/$t/boot-racine.tar"; cp "$T/boot-racine.sha256" "$B/$t/"; echo '{}' > "$B/$t/docker/config.json"; done
python3 -I - "$S1" "$B/fonction.sh" <<'PY'
import sys
n = open(sys.argv[1], encoding='utf-8').read(); i = n.index('etape_boot_image() {'); j = n.index('\n}\n', i) + 3
open(sys.argv[2], 'w', encoding='utf-8').write(n[i:j])
PY
"$CRANE" registry serve --address "$ADR" --disk "$B/disque" > "$B/serve.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null; wait $srv 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://$ADR/v2/" >/dev/null && echo "registre local : prêt (http)"
passage() { # t préfixe
  ( set -euo pipefail
    . "$B/fonction.sh"
    # shellcheck disable=SC2034  # lues par etape_boot_image, chargée par la ligne précédente
    T=$B/$1 REG_HOTE=$ADR REG=sc-stockage.poc.test:5000 PREFIXE=$2
    eval "$(grep -m1 '^DEPOT_DERIVE=' "$S1" | cut -d' ' -f1)"; eval "$(grep -m1 '^DEPOT_AMONT=' "$S1")"
    eval "$(grep -m1 '^BOOT_DIGEST=' "$S1" | cut -d' ' -f1)"
    zot() { "$@"; }; crane() { "$CRANE" "$@"; }; auth_zot() { echo "auth_zot appelé (inattendu)"; exit 1; }
    t=$(date +%s); etape_boot_image; echo "durée : $(($(date +%s) - t)) s" )
}
echo "## passage 1 (tag banc1)"
passage t1 banc1
echo "## passage 2 (tag banc2, même archive)"
passage t2 banc2
echo "digest 1 : $(cat "$B/t1/boot-image.digest") ; digest 2 : $(cat "$B/t2/boot-image.digest") ; égaux : $([ "$(cat "$B/t1/boot-image.digest")" = "$(cat "$B/t2/boot-image.digest")" ] && echo oui || echo non)"
d=$(cat "$B/t1/boot-image.digest")
"$CRANE" manifest "$ADR/essais-05/rocky9-bootstrap@$d" | jq -r '"manifeste : \(.mediaType) ; config \(.config.mediaType) ; couches \([.layers[].mediaType] | unique | join(","))"'
"$CRANE" config "$ADR/essais-05/rocky9-bootstrap@$d" | jq -r '"config : os \(.os) ; architecture \(.architecture) ; created \(.created // "absent") ; history \(.history | length // 0) ; diff_ids \(.rootfs.diff_ids | length)"'
echo "place du registre local : $(du -sm "$B/disque" | cut -f1) Mo"
