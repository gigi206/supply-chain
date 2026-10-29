#!/bin/sh
# Brique 08 : horodatage des enveloppes DSSE que Chains écrit dans le tag .att des images (mode dsse), sur le nœud de
# confiance, hors des pods de build. Deux modes :
#   - J5, une image : $IMAGE (dépôt@digest), job lancé par tsa.sh horodater ;
#   - J6, réconciliation périodique (CronJob, politique.sh horodatage) : sans $IMAGE, chaque dépôt de Zot sous $PREFIXES
#     est parcouru, et chaque tag sha256-<digest>.att y désigne une image attestée. Zot est la seule source, en lecture
#     anonyme : ni jeton de compte de service, ni accès à l'API ; une exécution purgée de l'API reste horodatée, et un
#     passage reprend ce qu'un passage interrompu a laissé.
# Pour chaque enveloppe :
#   - vérification avant toute demande au TSA (cosign verify-blob-attestation, sur un bundle sans jeton) : signature de la
#     clé de Chains, sujet égal au digest de l'image, prédicat $PREDICAT. cosign bundle create ne vérifie rien : la clé n'y
#     donne que son empreinte (lu dans le code de cosign v3.1.4). Une enveloppe refusée est écartée (REFUSEE : ni jeton,
#     ni bundle) sans arrêter le parcours, car Zot ne permet pas de la supprimer ; de même pour un tag .att illisible
#     (ATTESTATIONS_ILLISIBLES) ou un dépôt sans liste de tags (TAGS_ILLISIBLES), comptés en anomalies ;
#   - jeton RFC 3161 du TSA ($TSA) sur les octets bruts de la signature, ce que vérifient sigstore-go et cosign pour un
#     bundle (le chemin historique horodate l'enveloppe entière et accepte une attestation sans jeton : écarté) ;
#   - bundle Sigstore v0.3 (enveloppe + jeton, cosign bundle create), vérifié de bout en bout (jeton exigé, racine de
#     confiance du TSA), puis publié en referrer de l'image dans le dépôt $DEPOT, pas dans celui de l'image : Kyverno n'y
#     lirait plus que les bundles et ignorerait .sig et .att.
# Rejouable : le manifeste est étiqueté par le digest de l'image et l'empreinte de la signature ; une enveloppe déjà
# horodatée est sautée (l'existence de l'étiquette suffit : une étiquette occupée d'avance ferait sauter l'enveloppe ; le
# contrôle « un bundle par enveloppe » de politique.sh le verrait). Le compte Zot poc-horodatage ne peut écrire que dans
# horodatage/**. Zot ou TSA injoignable, ou bundle horodaté invalide : échec du job, et le passage suivant reprend.
set -eu
umask 077
cd "$(mktemp -d)"
CA=/etc/horodatage/ca-poc.crt
CLE=/etc/horodatage/chains.pub
RACINE=/etc/horodatage/tsa-racine-confiance.json
PREDICAT=${PREDICAT:-https://slsa.dev/provenance/v1}   # provenance SLSA v1 de Chains (slsa/v2alpha4) ; autre type refusé
I=${IMAGE:-}
REGISTRE=${REGISTRE:-${I%%/*}}
VIDE=sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a   # {} : application/vnd.oci.empty.v1+json
TYPE=application/vnd.dev.sigstore.bundle.v0.3+json
oras_ecriture() { oras "$@" --ca-file "$CA" --registry-config /var/run/zot/config.json; }
champ() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p"; }   # champ texte unique d'un JSON tenant sur une ligne
verifier() { # bundle [options de cosign…] : signature de Chains, sujet = digest de l'image, prédicat ; sortie dans verif.out
  f=$1; shift
  cosign verify-blob-attestation --bundle "$f" --new-bundle-format --key "$CLE" --insecure-ignore-tlog --type "$PREDICAT" \
    --digest "$image" --digestAlg sha256 "$@" > verif.out 2>&1
}
motif() { sed -n 's/^Error: //p' verif.out | head -1 | cut -c1-160; }
refusee() { # numéro empreinte motif
  echo "REFUSEE|$depot|$1|signature $2|$3"; n_r=$((n_r + 1))
}

horodater_image() { # dépôt@sha256:… : lignes HORODATEE, DEJA_HORODATEE, REFUSEE (une par enveloppe)
  IMAGE=$1
  depot=${IMAGE%@*}; depot=${depot#*/}
  image=${IMAGE##*@sha256:}
  n_images=$((n_images + 1))
  if ! oras manifest fetch --ca-file "$CA" --descriptor "$IMAGE" > sujet.json 2> erreur; then
    echo "IMAGE_ABSENTE|$depot|$(head -1 erreur | cut -c1-120)"; anomalies=$((anomalies + 1)); return 0
  fi
  # Un tag .att mal formé (index, couche qui n'est pas du JSON) fait échouer cosign : signalé, sans arrêter le parcours.
  if ! cosign download attestation --registry-cacert "$CA" "$IMAGE" > enveloppes.jsonl 2> erreur; then
    echo "ATTESTATIONS_ILLISIBLES|$depot|$(sed -n 's/^Error: //p' erreur | head -1 | cut -c1-120)"; anomalies=$((anomalies + 1)); return 0
  fi
  [ -s enveloppes.jsonl ] || { echo "AUCUNE_ATTESTATION|$depot"; anomalies=$((anomalies + 1)); return 0; }
  i=0
  while IFS= read -r enveloppe <&3; do
    i=$((i + 1)); n_env=$((n_env + 1))
    printf '%s' "$enveloppe" > enveloppe.json
    [ "$(grep -o '"sig":' enveloppe.json | wc -l)" -eq 1 ] || { refusee "$i" - "aucune ou plusieurs signatures"; continue; }
    champ sig < enveloppe.json > sig.b64
    champ payload < enveloppe.json > payload.b64
    if ! base64 -d sig.b64 > sig.bin 2>/dev/null || ! base64 -d payload.b64 > payload.json 2>/dev/null; then
      refusee "$i" - "signature ou contenu illisible"; continue
    fi
    type=$(champ predicateType < payload.json)
    empreinte=$(sha256sum < sig.bin | cut -c1-16)
    etiquette=$image-$empreinte
    if oras manifest fetch --ca-file "$CA" --descriptor "$DEPOT:$etiquette" > /dev/null 2>&1; then
      echo "DEJA_HORODATEE|$depot|$i|signature $empreinte|$type"; n_d=$((n_d + 1))
      continue
    fi
    if ! cosign bundle create --artifact payload.json --signature sig.b64 --attestation enveloppe.json --key "$CLE" \
           --ignore-tlog --out sans-jeton.json > verif.out 2>&1 || ! verifier sans-jeton.json; then
      refusee "$i" "$empreinte" "$(motif)"; continue
    fi
    timestamp-cli --timestamp_server "$TSA" timestamp --artifact sig.bin --hash sha256 --out jeton.tsr > tsa.out
    printf '{"SignedRFC3161Timestamp":"%s"}' "$(base64 jeton.tsr | tr -d '\n')" > jeton.json
    cosign bundle create --artifact payload.json --signature sig.b64 --attestation enveloppe.json \
      --rfc3161-timestamp jeton.json --key "$CLE" --ignore-tlog --out bundle.json 2> erreur \
      || { cat erreur >&2; exit 1; }
    verifier bundle.json --use-signed-timestamps --trusted-root "$RACINE" \
      || { echo "KO   bundle horodaté invalide ($depot, enveloppe $i) : $(motif)" >&2; exit 1; }
    oras_ecriture blob push "$DEPOT" bundle.json > /dev/null
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s",%s,%s,%s,%s}' \
      "$TYPE" \
      "\"config\":{\"mediaType\":\"application/vnd.oci.empty.v1+json\",\"digest\":\"$VIDE\",\"size\":2}" \
      "\"layers\":[{\"mediaType\":\"$TYPE\",\"digest\":\"sha256:$(sha256sum < bundle.json | cut -c1-64)\",\"size\":$(wc -c < bundle.json)}]" \
      "\"subject\":$(cat sujet.json)" \
      "\"annotations\":{\"dev.sigstore.bundle.content\":\"dsse-envelope\",\"dev.sigstore.bundle.predicateType\":\"$PREDICAT\",\"org.opencontainers.image.created\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
      > manifeste.json
    d=$(oras_ecriture manifest push "$DEPOT:$etiquette" manifeste.json | sed -n 's/^Digest: //p')
    echo "HORODATEE|$depot|$i|signature $empreinte|$PREDICAT|$(sed -n 's/^Artifact timestamped at //p' tsa.out)|referrer $d"
    n_h=$((n_h + 1))
  done 3< enveloppes.jsonl
}

# kube-router rejette le trafic d'un pod neuf pendant quelques secondes (J3), ici comme à l'entrée du TSA : on attend
# Zot et le TSA.
n=1
until oras repo ls --ca-file "$CA" "$REGISTRE" > /dev/null 2> erreur \
    && wget -q -O /dev/null "$TSA/api/v1/timestamp/certchain" 2>> erreur; do
  [ $n -lt 30 ] || { cat erreur >&2; exit 1; }
  n=$((n + 1)); sleep 1
done
echo "JOINT|Zot et TSA, essai $n"
printf '{}' > vide.json
oras_ecriture blob push "$DEPOT" vide.json > /dev/null
n_images=0 n_env=0 n_h=0 n_d=0 n_r=0 anomalies=0
if [ -n "$I" ]; then
  horodater_image "$I"
else
  for p in $PREFIXES; do
    oras repo ls --ca-file "$CA" "$REGISTRE/$p" > depots.txt
    while IFS= read -r r <&4; do
      if ! oras repo tags --ca-file "$CA" "$REGISTRE/$p/$r" > tags.txt 2> erreur; then
        echo "TAGS_ILLISIBLES|$p/$r|$(head -1 erreur | cut -c1-120)"; anomalies=$((anomalies + 1)); continue
      fi
      grep -E '^sha256-[0-9a-f]{64}\.att$' tags.txt > att.txt || true
      while IFS= read -r t <&5; do
        horodater_image "$REGISTRE/$p/$r@sha256:$(echo "$t" | cut -c8-71)"
      done 5< att.txt
    done 4< depots.txt
  done
fi
echo "FIN|$n_images image(s), $n_env enveloppe(s) : $n_h horodatée(s), $n_d déjà, $n_r refusée(s), $anomalies anomalie(s)|${I:-$REGISTRE ($PREFIXES)} → $DEPOT"
# Une seule image (J5) : toute enveloppe refusée ou anomalie est un échec ; en réconciliation, elles sont signalées.
[ -z "$I" ] || [ $((n_r + anomalies)) = 0 ]
