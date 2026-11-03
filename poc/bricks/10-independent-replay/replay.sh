#!/usr/bin/env bash
# Brique 10 : replay indépendant (décisions D1 à D7 du propriétaire du 03/11/2026). Domaine de replay : ses fichiers vivent dans
# ~/.cache/supply-chain-poc/10, sans rien de commun avec 08 (clés, secrets) ; seules des lectures anonymes de Zot et de Forgejo.
# Jalon R1, sur l'hôte, sans VM ni installation :
#   cosign_stockage  Zot 2.1.22 jetable et cosign 3.1.4 dans un espace de noms réseau vide (unshare -rn : boucle locale seule) ;
#                    image et clés jetables ; cosign attest --key d'un prédicat VSA d'essai : besoin de réseau ? stockage en tag
#                    .att ou en referrer OCI 1.1 ?
#   version_go       version de Go de l'entrée plateforme/builder-go-voie-d de la provenance, lue dans ses couches (rien d'exécuté)
#   outils           toolchain Go officielle de go.dev (sha256 de go.dev/dl/?mode=json) ; archives des outils de mise.lock
#                    (BuildKit, runc, rootlesskit, cosign, oras, crane) téléchargées et vérifiées pour la VM
#
# Usage (racine du dépôt) : mise run replay -- <étape>…   (journal : resultats/<jalon>-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
racine_depot=$(cd "$here/../../.." && pwd)
R=$here/resultats
O=$HOME/.cache/supply-chain-poc/10
T=$O/telechargements
E=$O/essais
mkdir -p "$R" "$T" "$E"
ZOT_POC=192.168.161.13:5000                      # Zot du PoC, lecture anonyme seulement
CA_POC=$O/ca-poc.crt                             # certificat public de la CA du PoC (TLS de Zot et de Forgejo), copié une fois
[ -s "$CA_POC" ] || cp "$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt" "$CA_POC"   # public ; aucune clé de 08 n'est lue
IMAGE=builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # sujet de la provenance
INVOCATION=d9006af7-5d9a-4a5e-878e-1c9a5bd96d56   # PipelineRun du 02/11/2026, 13:58:36 à 13:59:30 UTC

lancer() { # jalon étape… : journal resultats/<jalon>-<étape>.log
  local j=$1 e; shift
  [ $# -gt 0 ] || { echo "usage : $0 $(declare -F | awk '$3 ~ /^etape_/ {sub("etape_", "", $3); printf "%s|", $3}' | sed 's/|$//')…" >&2; exit 2; }
  for e in "$@"; do declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }; done
  for e in "$@"; do
    { echo "# ${0##*/} $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/$j-$e.log"
  done
}

etape_cosign_stockage() {
  local d=$E/cosign
  rm -rf -- "${d:?}" && mkdir -p "$d/zot" && cd "$d"
  printf '{"distSpecVersion":"1.1.1","storage":{"rootDirectory":"%s/zot"},"http":{"address":"127.0.0.1","port":"15000"},"log":{"level":"error"}}\n' "$d" > zot.json
  printf '{"verifier":{"id":"https://supply-chain.example/verifiers/essai"},"resourceUri":"essai","policy":{"uri":"essai"},"verificationResult":"PASSED","verifiedLevels":["POC_ESSAI"]}\n' > vsa.json
  printf 'essai\n' > f && tar -cf couche.tar f
  # tout ce qui suit tourne dans un espace de noms réseau vide : aucune route, seule la boucle locale
  unshare -rn bash -s "$d" "$(command -v zot)" "$(command -v crane)" "$(command -v cosign)" <<'EOS'
set -uo pipefail
d=$1 zot=$2 crane=$3 cosign=$4; cd "$d"
ip link set lo up
echo "## interfaces de l'espace de noms : $(ip -o link | awk -F': ' '{print $2}' | paste -sd' ') ; routes : $(ip route | wc -l)"
"$zot" serve zot.json > zot.log 2>&1 & z=$!
for _ in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:15000/v2/ && break; sleep 0.5; done
"$crane" append --insecure --oci-empty-base -f couche.tar -t 127.0.0.1:15000/essai/image:v1 > /dev/null
img=127.0.0.1:15000/essai/image@$("$crane" digest --insecure 127.0.0.1:15000/essai/image:v1)
echo "## image jetable : $img"
export COSIGN_PASSWORD=essai-jetable
"$cosign" generate-key-pair > /dev/null 2>&1 && echo "clés jetables : $(ls cosign.key cosign.pub | paste -sd' ')"
echo "## cosign attest --key, sans option de stockage ni de journal"
timeout 60 "$cosign" attest --key cosign.key --type https://slsa.dev/verification_summary/v1 --predicate vsa.json --allow-http-registry --yes "$img" 2>&1 | tail -6
echo "code de sortie : ${PIPESTATUS[0]}"
echo "## configuration de signature sans aucun service (ni Fulcio, ni Rekor, ni TSA)"
"$cosign" signing-config create --out signature-vide.json 2>&1 | tail -2; jq -c . signature-vide.json
echo "## cosign attest --key --signing-config signature-vide.json"
timeout 60 "$cosign" attest --key cosign.key --signing-config signature-vide.json --type https://slsa.dev/verification_summary/v1 \
  --predicate vsa.json --allow-http-registry --yes "$img" 2>&1 | tail -6
echo "code de sortie : ${PIPESTATUS[0]}"
echo "## cosign verify-attestation --key cosign.pub, sans journal (hors réseau)"
timeout 60 "$cosign" verify-attestation --key cosign.pub --insecure-ignore-tlog --type https://slsa.dev/verification_summary/v1 \
  --allow-http-registry "$img" 2>&1 | grep -vE '^\{' | tail -4
echo "code de sortie : ${PIPESTATUS[0]}"
echo "## tags du dépôt essai/image"
"$crane" ls --insecure 127.0.0.1:15000/essai/image
echo "## referrers de l'image (API OCI 1.1)"
curl -s "http://127.0.0.1:15000/v2/essai/image/referrers/${img#*@}" | jq -c '[.manifests[]? | {artifactType, mediaType, digest: .digest[0:19]}]'
for t in $("$crane" ls --insecure 127.0.0.1:15000/essai/image | grep -E '\.(att|sig)$'); do
  echo "manifeste du tag $t : $("$crane" manifest --insecure "127.0.0.1:15000/essai/image:$t" | jq -c '{mediaType, artifactType, couches: [.layers[].mediaType]}')"
done
kill $z
EOS
  cd / && rm -rf -- "${d:?}"
}

provenance() { # $O/provenance.json : énoncé de la provenance du PipelineRun INVOCATION, tiré du tag .att (lecture anonyme ;
  # sa signature n'est vérifiée qu'en R3, dans le domaine)
  local t l
  [ -s "$O/provenance.json" ] && return
  t=$(echo "${IMAGE#*@}" | tr : -).att
  for l in $(SSL_CERT_FILE=$CA_POC crane manifest "$ZOT_POC/${IMAGE%@*}:$t" | jq -r '.layers[].digest'); do
    SSL_CERT_FILE=$CA_POC crane blob "$ZOT_POC/${IMAGE%@*}@$l" | jq -r '.payload' | base64 -d > "$E/enonce.json"
    if [ "$(jq -r '.predicate.runDetails.metadata.invocationId' "$E/enonce.json")" = "$INVOCATION" ] \
       && [ "$(jq '.predicate.buildDefinition.resolvedDependencies | length' "$E/enonce.json")" -gt 6 ]; then
      mv "$E/enonce.json" "$O/provenance.json"; echo "provenance $INVOCATION : couche $l"; return
    fi
  done
  rm -f "$E/enonce.json"; echo "KO   provenance $INVOCATION introuvable" >&2; exit 1
}

etape_version_go() {
  local d=$E/builder ref l
  rm -rf -- "${d:?}" && mkdir -p "$d"
  provenance
  ref=$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.uri | test("builder-go-voie-d")) | "\(.uri | sub("^oci://"; ""))@sha256:\(.digest.sha256)"' "$O/provenance.json")
  echo "entrée de la provenance : $ref"
  ref=${ref/sc-stockage.poc.test:5000/$ZOT_POC}   # l'hôte ne résout pas poc.test ; le certificat de Zot couvre aussi l'IP
  SSL_CERT_FILE=$CA_POC crane manifest "$ref" | jq -r '.mediaType, (.layers | length | "couches : \(.)")'
  for l in $(SSL_CERT_FILE=$CA_POC crane manifest "$ref" | jq -r '.layers[].digest'); do
    if SSL_CERT_FILE=$CA_POC crane blob "${ref%@*}@$l" | tar -xzf - -C "$d" --wildcards '*go/VERSION' 2>/dev/null; then :; fi
  done
  find "$d" -name VERSION -path '*go/VERSION' -exec sh -c 'echo "${1#$2/} :"; head -2 "$1"' _ {} "$d" \;
  find "$d" -name VERSION -path '*go/VERSION' -exec head -1 {} \; | head -1 > "$O/version-go"
  echo "version retenue pour le domaine : $(cat "$O/version-go")"
  rm -rf -- "${d:?}"
}

etape_outils() {
  local v f s u
  v=$(cat "$O/version-go")
  echo "## toolchain Go officielle $v (go.dev)"
  curl -fsS 'https://go.dev/dl/?mode=json&include=all' -o "$E/go-dl.json"
  s=$(jq -r --arg f "$v.linux-amd64.tar.gz" '.[].files[] | select(.filename == $f) | .sha256' "$E/go-dl.json")
  echo "sha256 publié par go.dev : ${s:-absent}"
  [ -n "$s" ] || { echo "KO   $v.linux-amd64.tar.gz absent de go.dev"; exit 1; }
  [ -s "$T/$v.linux-amd64.tar.gz" ] || curl -fsSL -o "$T/$v.linux-amd64.tar.gz" "https://go.dev/dl/$v.linux-amd64.tar.gz"
  echo "$s  $T/$v.linux-amd64.tar.gz" | sha256sum -c
  rm -f "$E/go-dl.json"
  echo "## archives des outils (url et sha256 de mise.lock)"
  python3 -I - "$racine_depot/mise.lock" <<'PY' > "$E/outils.tsv"
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
for k in ["aqua:moby/buildkit", "aqua:opencontainers/runc", "aqua:rootless-containers/rootlesskit",
          "aqua:sigstore/cosign", "aqua:oras-project/oras", "aqua:google/go-containerregistry"]:
    e = d["tools"][k][0]; p = e["platforms.linux-x64"]
    print(k, e["version"], p["url"], p["checksum"].removeprefix("sha256:"), sep="\t")
PY
  while IFS=$'\t' read -r n v u s; do
    f=$T/${u##*/}
    [ -s "$f" ] || curl -fsSL -o "$f" "$u"
    printf '%-40s %-8s ' "$n" "$v"; echo "$s  $f" | sha256sum -c 2>&1 | sed "s#$T/##"
  done < "$E/outils.tsv"
  rm -f "$E/outils.tsv"
}

lancer r1 "$@"
