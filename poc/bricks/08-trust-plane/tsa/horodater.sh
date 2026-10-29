#!/bin/sh
# Brique 08, jalon J5 : job d'horodatage (tsa.sh horodater), sur le nœud de confiance. Pour chaque enveloppe DSSE que
# Chains a écrite dans le tag .att de $IMAGE (mode dsse) :
#   - jeton RFC 3161 du TSA ($TSA) sur les octets bruts de la signature, ce que vérifient sigstore-go et cosign pour un
#     bundle (le chemin historique horodate l'enveloppe entière et accepte une attestation sans jeton : écarté) ;
#   - bundle Sigstore v0.3 (enveloppe + jeton, cosign bundle create), publié en referrer de l'image dans le dépôt
#     $DEPOT, pas dans celui de l'image : Kyverno n'y lirait plus que les bundles et ignorerait .sig et .att.
# Rejouable : le manifeste est étiqueté par le digest de l'image et l'empreinte de la signature ; une enveloppe déjà
# horodatée est sautée. Le compte Zot poc-horodatage ne peut écrire que dans horodatage/**.
set -eu
umask 077
cd "$(mktemp -d)"
CA=/etc/horodatage/ca-poc.crt
VIDE=sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a   # {} : application/vnd.oci.empty.v1+json
TYPE=application/vnd.dev.sigstore.bundle.v0.3+json
oras_ecriture() { oras "$@" --ca-file "$CA" --registry-config /var/run/zot/config.json; }
champ() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p"; }   # champ texte unique d'un JSON tenant sur une ligne

# kube-router rejette le trafic d'un pod neuf pendant quelques secondes (J3), ici comme à l'entrée du TSA : on attend
# Zot et le TSA.
n=1
until oras manifest fetch --ca-file "$CA" --descriptor "$IMAGE" > sujet.json 2> erreur \
    && wget -q -O /dev/null "$TSA/api/v1/timestamp/certchain" 2>> erreur; do
  [ $n -lt 30 ] || { cat erreur >&2; exit 1; }
  n=$((n + 1)); sleep 1
done
echo "JOINT|Zot et TSA, essai $n"
cosign download attestation --registry-cacert "$CA" "$IMAGE" > enveloppes.jsonl
[ -s enveloppes.jsonl ] || { echo "AUCUNE_ATTESTATION|$IMAGE"; exit 1; }
printf '{}' > vide.json
oras_ecriture blob push "$DEPOT" vide.json > /dev/null
image=$(echo "$IMAGE" | sed 's/.*@sha256://')
i=0
while IFS= read -r enveloppe; do
  i=$((i + 1))
  printf '%s' "$enveloppe" > enveloppe.json
  [ "$(grep -o '"sig":' enveloppe.json | wc -l)" -eq 1 ] || { echo "SIGNATURES_MULTIPLES|$i"; exit 1; }
  champ sig < enveloppe.json > sig.b64
  base64 -d sig.b64 > sig.bin
  champ payload < enveloppe.json | base64 -d > payload.json
  type=$(champ predicateType < payload.json)
  empreinte=$(sha256sum < sig.bin | cut -c1-64)
  etiquette=$image-$(echo "$empreinte" | cut -c1-16)
  if oras manifest fetch --ca-file "$CA" --descriptor "$DEPOT:$etiquette" > /dev/null 2>&1; then
    echo "DEJA_HORODATEE|$i|signature $(echo "$empreinte" | cut -c1-16)|$type"
    continue
  fi
  timestamp-cli --timestamp_server "$TSA" timestamp --artifact sig.bin --hash sha256 --out jeton.tsr > tsa.out
  printf '{"SignedRFC3161Timestamp":"%s"}' "$(base64 jeton.tsr | tr -d '\n')" > jeton.json
  cosign bundle create --artifact payload.json --signature sig.b64 --attestation enveloppe.json \
    --rfc3161-timestamp jeton.json --key /etc/horodatage/chains.pub --ignore-tlog --out bundle.json 2> erreur \
    || { cat erreur >&2; exit 1; }
  oras_ecriture blob push "$DEPOT" bundle.json > /dev/null
  printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s",%s,%s,%s,%s}' \
    "$TYPE" \
    "\"config\":{\"mediaType\":\"application/vnd.oci.empty.v1+json\",\"digest\":\"$VIDE\",\"size\":2}" \
    "\"layers\":[{\"mediaType\":\"$TYPE\",\"digest\":\"sha256:$(sha256sum < bundle.json | cut -c1-64)\",\"size\":$(wc -c < bundle.json)}]" \
    "\"subject\":$(cat sujet.json)" \
    "\"annotations\":{\"dev.sigstore.bundle.content\":\"dsse-envelope\",\"dev.sigstore.bundle.predicateType\":\"$type\",\"org.opencontainers.image.created\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    > manifeste.json
  d=$(oras_ecriture manifest push "$DEPOT:$etiquette" manifeste.json | sed -n 's/^Digest: //p')
  echo "HORODATEE|$i|signature $(echo "$empreinte" | cut -c1-16)|$type|$(sed -n 's/^Artifact timestamped at //p' tsa.out)|referrer $d"
done < enveloppes.jsonl
echo "FIN|$i enveloppe(s)|$IMAGE → $DEPOT"
