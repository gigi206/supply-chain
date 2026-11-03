#!/bin/bash
# Brique 10, R5, mesure préalable SUR L'HÔTE (prédictions : resultats/r5-tuf-predictions.md ; accord du propriétaire du
# 03/11/2026 : « Oui, mesurer ») : cosign tente-t-il de joindre le TUF public de Sigstore quand il vérifie avec une clé ?
# Espace de noms réseau vide (unshare -rn, boucle locale seule) : aucune connexion extérieure possible ; les TENTATIVES sont
# relevées par strace, pour des vérifications réussies (bonne clé) et refusées (autre clé). Zot, image et clés jetables ; HOME vide, puis HOME muni d'une COPIE du cache ~/.sigstore (le vrai cache
# n'est pas touché). Hors de replay.sh, comme les autres essais de R5, tant que R4 exécute replay.sh.
# Journal : resultats/r5-tuf.log
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")/.." && pwd)   # dossier de la brique
d=$HOME/.cache/supply-chain-poc/10/essais/tuf
rm -rf -- "${d:?}" && mkdir -p "$d/zot" "$d/home-vide" "$d/home-cache"
[ -d "$HOME/.sigstore" ] && cp -a "$HOME/.sigstore" "$d/home-cache/"
cd "$d"
printf '{"distSpecVersion":"1.1.1","storage":{"rootDirectory":"%s/zot"},"http":{"address":"127.0.0.1","port":"15002"},"log":{"level":"error"}}\n' "$d" > zot.json
printf 'essai\n' > f && tar -cf couche.tar f
{
echo "# essais/tuf-verification-cle.sh, $(date -u +%FT%TZ) ; cosign $(cosign version 2>/dev/null | awk '/GitVersion/ {print $2}') ; strace $(strace -V | awk 'NR == 1 {print $NF}')"
echo "cache copié : $(find "$d/home-cache" -type f | sed "s#$d/home-cache/##" | sort | paste -sd' ')"
unshare -rn bash -s "$d" "$(command -v zot)" "$(command -v crane)" "$(command -v cosign)" "$(command -v oras)" <<'EOS'
set -uo pipefail
d=$1 zot=$2 crane=$3 cosign=$4 oras=$5; cd "$d"
ip link set lo up
echo "## espace de noms : $(ip -o link | awk -F': ' '{print $2}' | paste -sd' ') ; routes : $(ip route | wc -l)"
"$zot" serve zot.json > zot.log 2>&1 & z=$!
for _ in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:15002/v2/ && break; sleep 0.5; done
export HOME=$d/home-vide COSIGN_PASSWORD=essai-jetable
"$crane" append --insecure --oci-empty-base -f couche.tar -t 127.0.0.1:15002/essai/image:v1 > /dev/null 2>&1
dig=$("$crane" digest --insecure 127.0.0.1:15002/essai/image:v1); img=127.0.0.1:15002/essai/image@$dig
echo "image jetable : $img"
mkdir cle autre && (cd cle && "$cosign" generate-key-pair > /dev/null 2>&1) && (cd autre && "$cosign" generate-key-pair > /dev/null 2>&1)
"$cosign" signing-config create --out vide.json > /dev/null 2>&1
echo "## préparation (hors sonde) : signature et attestation au format ancien (.sig, .att), comme l'image réelle"
o=(--key cle/cosign.key --new-bundle-format=false --use-signing-config=false --tlog-upload=false --allow-http-registry --yes)
printf '{"buildDefinition":{"buildType":"essai"},"runDetails":{"builder":{"id":"essai"}}}' > predicat.json
"$cosign" sign "${o[@]}" "$img" > prep.out 2>&1; echo "cosign sign : code $? ; $(grep -m1 -i error prep.out | cut -c1-160)"
"$cosign" attest "${o[@]}" --type slsaprovenance1 --predicate predicat.json "$img" > prep.out 2>&1
echo "cosign attest : code $? ; $(grep -m1 -i error prep.out | cut -c1-160)"
echo "tags : $("$crane" ls --insecure 127.0.0.1:15002/essai/image | paste -sd' ')"
echo "## préparation (hors sonde) : VSA signée par attest-blob --statement, referrer fait main dans le dépôt séparé vsa/essai"
python3 -I - "$dig" <<'PY'
import json, sys
json.dump({"_type": "https://in-toto.io/Statement/v1",
           "subject": [{"name": "127.0.0.1:15002/essai/image", "digest": {"sha256": sys.argv[1].split(":")[1]}}],
           "predicateType": "https://slsa.dev/verification_summary/v1",
           "predicate": {"verifier": {"id": "https://supply-chain.example/verifiers/essai"}, "resourceUri": "essai",
                         "policy": {"uri": "essai"}, "verificationResult": "PASSED", "verifiedLevels": ["POC_ESSAI"]}},
          open("enonce.json", "w"))
PY
"$cosign" attest-blob --statement enonce.json --key cle/cosign.key --signing-config vide.json --bundle vsa.bundle.json --yes > prep.out 2>&1
echo "attest-blob : code $?"
T=application/vnd.dev.sigstore.bundle.v0.3+json V=https://slsa.dev/verification_summary/v1
printf '{}' > config.json
s=$(curl -sI -H 'Accept: application/vnd.oci.image.manifest.v1+json' "http://127.0.0.1:15002/v2/essai/image/manifests/$dig" | tr -d '\r' \
  | python3 -I -c 'import sys,json; h={l.split(": ",1)[0].lower(): l.split(": ",1)[1] for l in sys.stdin.read().splitlines() if ": " in l}; print(json.dumps({"mediaType": h["content-type"], "digest": h["docker-content-digest"], "size": int(h["content-length"])}))')
printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s","config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:%s","size":2},"layers":[{"mediaType":"%s","digest":"sha256:%s","size":%s}],"subject":%s,"annotations":{"dev.sigstore.bundle.content":"dsse-envelope","dev.sigstore.bundle.predicateType":"%s"}}' \
  "$T" "$(sha256sum < config.json | cut -c1-64)" "$T" "$(sha256sum < vsa.bundle.json | cut -c1-64)" "$(wc -c < vsa.bundle.json)" "$s" "$V" > manifeste.json
m=sha256:$(sha256sum < manifeste.json | cut -c1-64)
"$oras" blob push --plain-http 127.0.0.1:15002/vsa/essai vsa.bundle.json > /dev/null && "$oras" blob push --plain-http 127.0.0.1:15002/vsa/essai config.json > /dev/null \
  && "$oras" manifest push --plain-http "127.0.0.1:15002/vsa/essai@$m" manifeste.json > /dev/null && echo "referrer poussé : vsa/essai@$m"
echo "referrers de l'image dans vsa/essai : $(curl -s "http://127.0.0.1:15002/v2/vsa/essai/referrers/$dig" | jq -c '[.manifests[].artifactType]')"

sonde() { # libellé home commande… : code de sortie, connexions hors de Zot (127.0.0.1:15002), lignes de socket citant le TUF
  local l=$1 h=$2 f="st-$1-$2" rc hors tuf; shift 2
  HOME=$d/home-$h strace -f -qq -e trace=connect,sendto,sendmsg,write -s 300 -o "$f.txt" "$@" > "$f.out" 2> "$f.err"; rc=$?
  hors=$(grep -E '^[0-9]+ +connect\(' "$f.txt" | grep -v 'sin_port=htons(15002), sin_addr=inet_addr("127.0.0.1")' \
    | grep -oE 'sa_family=AF_[A-Z0-9]+(, sun_path="[^"]*"|, sin_port=htons\([0-9]+\), sin_addr=inet_addr\("[^"]*"\)|, sin6_port=htons\([0-9]+\)[^}]*inet_pton\(AF_INET6, "[^"]*")?' \
    | sort | uniq -c | sed 's/^ *//' | paste -sd';' -)
  tuf=$(grep -E '^[0-9]+ +(connect|sendto|sendmsg|write)\(' "$f.txt" | grep -v -E 'write\([12],' | grep -c 'tuf-repo-cdn' || true)
  echo "$l, HOME $h : code $rc ; connexions hors Zot : ${hors:-aucune} ; écritures de socket citant tuf-repo-cdn : $tuf"
  [ "$rc" = 0 ] || echo "    motif : $(grep -m1 -E '^Error' "$f.err" | cut -c1-220)"
}
echo "## sondes (strace -f, connect/sendto/sendmsg/write)"
for h in vide cache; do
  sonde temoin-attest-sans-config "$h" "$cosign" attest --key cle/cosign.key --type slsaprovenance1 --predicate predicat.json --allow-http-registry --yes "$img"
  sonde V1-verify-blob-attestation "$h" "$cosign" verify-blob-attestation --bundle vsa.bundle.json --new-bundle-format --key cle/cosign.pub \
    --insecure-ignore-tlog --type "$V" --digest "${dig#sha256:}" --digestAlg sha256
  sonde V2-verify-attestation-COSIGN_REPOSITORY "$h" env COSIGN_REPOSITORY=127.0.0.1:15002/vsa/essai "$cosign" verify-attestation \
    --key cle/cosign.pub --insecure-ignore-tlog --type "$V" --allow-http-registry "$img"
  sonde V3-verify "$h" "$cosign" verify --key cle/cosign.pub --insecure-ignore-tlog --allow-http-registry "$img"
  sonde V4-verify-attestation-att "$h" "$cosign" verify-attestation --key cle/cosign.pub --insecure-ignore-tlog --type slsaprovenance1 \
    --allow-http-registry "$img"
  # refus (cas N3 de lire_vsa) : mêmes commandes, autre clé
  sonde V1-autre-cle "$h" "$cosign" verify-blob-attestation --bundle vsa.bundle.json --new-bundle-format --key autre/cosign.pub \
    --insecure-ignore-tlog --type "$V" --digest "${dig#sha256:}" --digestAlg sha256
  sonde V2-autre-cle "$h" env COSIGN_REPOSITORY=127.0.0.1:15002/vsa/essai "$cosign" verify-attestation \
    --key autre/cosign.pub --insecure-ignore-tlog --type "$V" --allow-http-registry "$img"
  sonde V3-autre-cle "$h" "$cosign" verify --key autre/cosign.pub --insecure-ignore-tlog --allow-http-registry "$img"
  sonde V4-autre-cle "$h" "$cosign" verify-attestation --key autre/cosign.pub --insecure-ignore-tlog --type slsaprovenance1 \
    --allow-http-registry "$img"
done
echo "## cache copié après les sondes : $(find "$d/home-cache" -type f -newer zot.json | sed "s#$d/home-cache/##" | paste -sd' ' -) (fichiers modifiés)"
echo "## HOME vide après les sondes : $(find "$d/home-vide" -type f | sed "s#$d/home-vide/##" | paste -sd' ' -)"
kill $z
EOS
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$here/resultats/r5-tuf.log"
# extrait archivé : connexions et lignes citant Sigstore (les traces complètes restent hors du dépôt)
for f in "$d"/st-*.txt; do echo "### ${f##*/}"; { grep -E 'connect\(|tuf-repo-cdn|sigstore\.dev' "$f" || true; } | cut -c1-400; done > "$here/resultats/r5-tuf-strace.txt"
cd / && rm -rf -- "${d:?}"
