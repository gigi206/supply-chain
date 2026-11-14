#!/bin/sh
# Brique 07a, jalon G4 : le job de scan, un mode par conteneur (politique/scan-job.yaml), sur le nœud de confiance.
#   source      (buildkit, seule image avec git) commit lu dans Forgejo, vérifié par git, arbre exporté (D1 a)
#   analyser    (outils-scan) base la plus récente de vulndb/grype, résolue en digest et vérifiée par son empreinte, importée
#               hors de tout service Anchore ; image lue par digest ; SBOM de l'image et de la source fusionnés ; scan ; prédicat.
#               Ni identifiant ni jeton dans ce conteneur : Zot et Forgejo sont lus en anonyme.
#   artefact    (outils-scan) la partie « artefact » d'analyser seule, sans base ni scan : mode du pod d'essai de S6a (brique 06).
#               NATURE=image (défaut) : syft oci-dir: sur l'image. NATURE=deb (S6a de la 06, décision du 12/11/2026, 08:50:32 UTC) :
#               layout du deb (une couche tar qui contient le .deb seul), data.tar extrait par busybox (ar, unxz ou gunzip, tar),
#               syft dir: sur le contenu extrait. Dans les deux cas, plancher : au moins une PURL versionnée dans le SBOM de
#               l'artefact seul, sans quoi refus (relevé 1 de S6a : un artefact vide passe sans erreur, et la fusion le masque).
#   jetons      (openbao) rôle scan-zot : identifiants de poc-scan lus, jeton révoqué ; puis rôle scanner : jeton de 5 min, pris
#               juste avant la signature (D9 a), après le scan
#   attester    (outils-scan) cosign attest-blob --key hashivault://scanner, sans service Sigstore, sujet = digest de l'image ;
#               bundle vérifié avec la clé publique avant toute publication
#   publier     (outils-scan) bundle publié en referrer de l'image dans $DEPOT, pas dans le dépôt de l'image : Kyverno y lirait
#               les bundles et ignorerait .sig et .att (constat de J5). poc-scan écrit par digest seulement (D2)
#   revocation  (openbao) jeton révoqué, identifiants et jeton effacés du volume en mémoire
set -eu
umask 077
MODE=${1:?mode}
TRAVAIL=${TRAVAIL:-/travail}
CA=${CA:-/etc/scan/ca-poc.crt}
CLE_PUBLIQUE=${CLE_PUBLIQUE:-/etc/scan/scanner.pub}
CLE=${CLE:-hashivault://scanner}
SECRETS=${SECRETS:-/var/run/bao}
PREDICAT=https://supply-chain.example/scan/v1
VIDE=sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a   # {} : application/vnd.oci.empty.v1+json
TYPE=application/vnd.dev.sigstore.bundle.v0.3+json
champ() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p"; }   # champ texte unique d'un JSON tenant sur une ligne
oras_ecriture() { oras "$@" --ca-file "$CA" --registry-config "$SECRETS/config.json"; }
cd "$TRAVAIL"

source_commit() {
  export HOME=$TRAVAIL GIT_CONFIG_NOSYSTEM=1 GIT_SSL_CAINFO=$CA GIT_TERMINAL_PROMPT=0
  # kube-router rejette le trafic d'un pod neuf pendant quelques secondes (J3).
  n=1
  until git clone --quiet --no-checkout "$SOURCE" depot 2> erreur; do
    [ $n -lt 30 ] || { cat erreur >&2; exit 1; }
    rm -rf depot; n=$((n + 1)); sleep 1
  done
  rm -f erreur
  git -C depot checkout --quiet --detach "$COMMIT"
  [ "$(git -C depot rev-parse HEAD)" = "$COMMIT" ] || { echo "HEAD différent du commit demandé" >&2; exit 1; }
  git -C depot fsck --no-progress > /dev/null 2>&1
  mkdir source
  git -C depot archive --format=tar HEAD | tar -xf - -C source
  echo "SOURCE|commit $COMMIT, arbre $(git -C depot rev-parse 'HEAD^{tree}'), essai $n, $(find source -type f | wc -l) fichiers"
  rm -rf depot .gitconfig
}

extraire_deb() { # layout du deb (deb/construire-deb.yaml de la 06) : data.tar extrait dans artefact/ ; busybox n'a pas zstd
  couches=$(sed -n 's/.*"layers":\[\([^]]*\)\].*/\1/p' "image/blobs/sha256/${IMAGE##*@sha256:}")
  [ "$(printf '%s' "$couches" | grep -o '"digest"' | wc -l)" = 1 ] || { echo "deb : une couche attendue dans le manifeste" >&2; exit 1; }
  case $couches in *'"mediaType":"application/vnd.oci.image.layer.v1.tar"'*) ;; *) echo "deb : couche tar non compressée attendue" >&2; exit 1 ;; esac
  l=$(printf '%s' "$couches" | sed -n 's/.*"digest":"sha256:\([0-9a-f]\{64\}\)".*/\1/p')
  mkdir couche artefact
  tar -xf "image/blobs/sha256/$l" -C couche
  set -- couche/*
  [ "$(ls -A couche | wc -l)" = 1 ] && [ -f "$1" ] && [ "${1%.deb}" != "$1" ] || { echo "deb : la couche doit contenir un .deb seul" >&2; exit 1; }
  echo "DEB|${1##*/}, sha256 $(sha256sum < "$1" | cut -c1-64), $(wc -c < "$1") octets"
  (cd couche && ar -x "${1##*/}")
  set -- couche/data.tar*
  [ $# = 1 ] && [ -f "$1" ] || { echo "deb : un data.tar attendu" >&2; exit 1; }
  case $1 in
    *.tar.xz) unxz -c "$1" > couche/data.tar ;;
    *.tar.gz) gunzip -c "$1" > couche/data.tar ;;
    *.tar) ;;
    *) echo "deb : compression de data.tar non prise en charge : ${1##*/}" >&2; exit 1 ;;
  esac
  tar -xf couche/data.tar -C artefact
  rm -rf couche
  echo "EXTRAIT|$(find artefact -type f | wc -l) fichiers dans data.tar"
}

artefact() { # image lue par digest ; SBOM de l'artefact seul dans sbom-image.json ; plancher
  oras cp --no-tty --from-ca-file "$CA" "$IMAGE" --to-oci-layout image:scan > /dev/null
  grep -q "\"digest\":\"${IMAGE##*@}\"" image/index.json || { echo "digest de l'image lue différent de $IMAGE" >&2; exit 1; }
  case ${NATURE:-image} in
    image) syft scan oci-dir:image -o cyclonedx-json=sbom-image.json -q ;;
    deb) extraire_deb; syft scan dir:artefact -o cyclonedx-json=sbom-image.json -q ;;
    *) echo "nature inconnue : $NATURE" >&2; exit 2 ;;
  esac
  # syft écrit le JSON sur une ligne : compter les occurrences, pas les lignes
  n=$(grep -oE '"purl": *"pkg:[^"@]+@[^"]*"' sbom-image.json | wc -l)
  [ "$n" -gt 0 ] || { echo "aucune PURL versionnée dans le SBOM de l'artefact seul (${NATURE:-image}) : extraction vide ou ratée" >&2; exit 1; }
  echo "ARTEFACT|${NATURE:-image}, $n PURL versionnées dans l'artefact seul"
}

analyser() {
  debut=$(date +%s)
  export GRYPE_DB_CACHE_DIR=$TRAVAIL/dbcache GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false GRYPE_CHECK_FOR_APP_UPDATE=false \
    SYFT_CHECK_FOR_APP_UPDATE=false
  # Base la plus récente archivée par le timer de sc-stockage : le tag daté est résolu en digest une fois pour toutes.
  tag=$(oras repo tags --ca-file "$CA" "$BASES" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | tail -1)
  [ -n "$tag" ] || { echo "aucune base dans $BASES" >&2; exit 1; }
  digest=$(oras manifest fetch --ca-file "$CA" --descriptor "$BASES:$tag" | champ digest)
  ref=$BASES@$digest
  empreinte=$(oras manifest fetch --ca-file "$CA" "$ref" | sed -n 's/.*"dev.anchore.grype.db.checksum": *"\([^"]*\)".*/\1/p')
  oras pull --no-tty --ca-file "$CA" -o base "$ref" > /dev/null
  set -- base/vulnerability-db_*.tar.zst
  [ $# = 1 ] && [ -f "$1" ] || { echo "archive de la base introuvable ou multiple" >&2; exit 1; }
  [ "sha256:$(sha256sum < "$1" | cut -c1-64)" = "$empreinte" ] || { echo "empreinte de la base invalide : $ref" >&2; exit 1; }
  echo "BASE|$tag, $ref, empreinte $empreinte, $(( $(date +%s) - debut )) s"
  t=$(date +%s)
  grype db import "$1" > import.out 2>&1 || { cat import.out >&2; exit 1; }
  echo "IMPORT|$(du -sm dbcache | cut -f1) Mo, $(( $(date +%s) - t )) s ; $(du -sm "$TRAVAIL" | cut -f1) Mo dans le volume, au plus haut"
  rm -rf base import.out

  t=$(date +%s)
  artefact
  syft scan dir:source -o cyclonedx-json=sbom-source.json -q
  scan-outil fusion sbom-source.json sbom-image.json source image > sbom.json
  echo "SBOM|$(grep -c '"purl"' sbom.json) composants avec PURL (D1 a), $(( $(date +%s) - t )) s"
  t=$(date +%s)
  grype sbom:sbom.json -o json --file grype.json -q
  scan-outil predicat grype.json "$ref" > scan.json
  echo "SCAN|$IMAGE, $(grep -c '"kev":' scan.json) vulnérabilités, $(grep -c '"kev": true' scan.json) KEV, $(( $(date +%s) - t )) s"
  rm -rf dbcache image artefact source sbom-image.json sbom-source.json sbom.json grype.json .cache
  echo "PREDICAT|sha256 $(sha256sum < scan.json | cut -c1-64), $(( $(date +%s) - debut )) s en tout"
}

connexion() { # rôle : jeton sur la sortie standard ; quelques essais, le réseau d'un pod neuf (J3)
  n=1
  until j=$(bao write -field=token auth/jwt/login role="$1" jwt=@/var/run/secrets/openbao/token 2> "$SECRETS/erreur"); do
    [ $n -lt 30 ] || { cat "$SECRETS/erreur" >&2; exit 1; }
    n=$((n + 1)); sleep 1
  done
  rm -f "$SECRETS/erreur"
  echo "$j"
}

jetons() {
  BAO_TOKEN=$(connexion scan-zot); export BAO_TOKEN
  bao read -field=config.json kv/scan/zot > "$SECRETS/config.json"
  bao token revoke -self > /dev/null
  unset BAO_TOKEN
  echo "identifiants Zot lus dans OpenBao (rôle scan-zot) ; jeton révoqué"
  connexion scanner > "$SECRETS/token"
  echo "jeton du rôle scanner obtenu"
}

attester() {
  cosign signing-config create --out vide.json > cosign.log 2>&1
  if [ "$CLE" = hashivault://scanner ]; then VAULT_TOKEN=$(cat "$SECRETS/token"); export VAULT_TOKEN; fi
  cosign attest-blob --key "$CLE" --signing-config vide.json --predicate scan.json --type "$PREDICAT" --bundle bundle.json \
    --hash "${IMAGE##*@sha256:}" --yes "$NOM" >> cosign.log 2>&1 || { cat cosign.log >&2; exit 1; }
  unset VAULT_TOKEN
  cosign verify-blob-attestation --bundle bundle.json --new-bundle-format --key "$CLE_PUBLIQUE" --insecure-ignore-tlog --type "$PREDICAT" \
    --digest "${IMAGE##*@sha256:}" --digestAlg sha256 >> cosign.log 2>&1 || { cat cosign.log >&2; exit 1; }
  rm -f vide.json cosign.log
  echo "ATTESTATION|sujet ${IMAGE##*@}, prédicat $PREDICAT, bundle sha256 $(sha256sum < bundle.json | cut -c1-64), vérifié avec la clé publique"
}

publier() {
  oras manifest fetch --ca-file "$CA" --descriptor "$IMAGE" > sujet.json
  printf '{}' > config-vide.json
  oras_ecriture blob push "$DEPOT" config-vide.json > /dev/null
  oras_ecriture blob push "$DEPOT" bundle.json > /dev/null
  printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s",%s,%s,%s,%s}' \
    "$TYPE" \
    "\"config\":{\"mediaType\":\"application/vnd.oci.empty.v1+json\",\"digest\":\"$VIDE\",\"size\":2}" \
    "\"layers\":[{\"mediaType\":\"$TYPE\",\"digest\":\"sha256:$(sha256sum < bundle.json | cut -c1-64)\",\"size\":$(wc -c < bundle.json)}]" \
    "\"subject\":$(cat sujet.json)" \
    "\"annotations\":{\"dev.sigstore.bundle.content\":\"dsse-envelope\",\"dev.sigstore.bundle.predicateType\":\"$PREDICAT\",\"org.opencontainers.image.created\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    > manifeste.json
  d=sha256:$(sha256sum < manifeste.json | cut -c1-64)
  oras_ecriture manifest push "$DEPOT@$d" manifeste.json > /dev/null
  echo "PUBLIE|$DEPOT@$d, referrer de ${IMAGE##*@}"
}

revocation() {
  BAO_TOKEN=$(cat "$SECRETS/token") bao token revoke -self > /dev/null
  rm -f "$SECRETS/token" "$SECRETS/config.json"
  echo "jeton du rôle scanner révoqué ; identifiants et jeton effacés"
}

case $MODE in
  source) source_commit ;;
  analyser) analyser ;;
  artefact) artefact ;;
  jetons) jetons ;;
  attester) attester ;;
  publier) publier ;;
  revocation) revocation ;;
  *) echo "mode inconnu : $MODE" >&2; exit 2 ;;
esac
