#!/usr/bin/env bash
# Relecture sur l'hôte de l'image d'essai poussée par l'étape image (brique 05, S1), en lecture seule, annoncée dans les
# prédictions avant le passage. Usage : relecture.sh <racine-du-dépôt>  (sortie : journal brut)
set -uo pipefail
export LC_ALL=C
D=$1
O=$HOME/.cache/supply-chain-poc/08
T=$O/travail/s1-05
REF=192.168.161.13:5000/essais-05/mock-rocky9
CRANE=$(cd "$D" && mise which crane)
zot() { DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$O/pki/ca-poc.crt "$CRANE" "$@" </dev/null; }
egal() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || echo "ÉCART $1 : $2 (attendu : $3)"; }
echo "# relecture sur l'hôte de l'image d'essai (lecture seule), $(date -u +%Y-%m-%dT%H:%M:%SZ), crane $("$CRANE" version)"
d=$(zot digest "$REF:s1"); echo "crane digest du tag :s1 : rc $?"
egal "digest du tag :s1 (IM4)" "$d" sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771
egal "contenu de image.digest" "$(cat "$T/image.digest")" "$d"
zot manifest "$REF@$d" | jq -r '"manifeste : \(.mediaType) ; config \(.config.mediaType) \(.config.digest) ; couches \([.layers[].mediaType] | unique | join(","))", (.layers[] | "couche \(.digest) \(.size) octets")'
egal "digest de config" "$(zot manifest "$REF@$d" | jq -r .config.digest)" sha256:d3002ab075686a9355bca64963934f6b80bc657ae17d5ca49c1dcd674762b672
zot config "$REF@$d" | jq -r '"config : os \(.os) ; architecture \(.architecture) ; Env \(.config.Env | join(" ")) ; created \(.created // "absent") ; history \(.history | length // 0)"'
egal "config (banc)" "$(zot config "$REF@$d" | jq -r '"os \(.os) ; architecture \(.architecture) ; Env \(.config.Env | join(" ")) ; created \(.created // "absent") ; history \(.history | length // 0)"')" \
  "os linux ; architecture amd64 ; Env PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root ; created 0001-01-01T00:00:00Z ; history 2"
echo "tags du dépôt : $(zot ls "$REF" | paste -sd ' ')"
echo "# fin, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
