#!/usr/bin/env bash
# Brique 08, jalon J5 : horodatage RFC 3161 (accord du propriétaire du 29/10/2026).
#   image      timestamp-server v2.2.0 (index signé : attestation GitHub du workflow build_container.yml au tag, commit
#              du tag) copié dans Zot et revérifié depuis Zot ; image d'outils du job assemblée sans Docker (crane
#              append) : base cosign v3.1.4-dev (signée, identité documentée par Sigstore), timestamp-cli v2.2.0
#              (attestation GitHub de release) et oras 1.3.6 (GPG, empreinte de la clé recoupée sur oras.land)
#   pki        racine TSA dédiée (pas la CA TLS du PoC : clés séparées par usage), clé en 0600 sur l'hôte
#   openbao    clé Transit tsa (ecdsa-p256, non exportable), politique tsa-signature, rôle JWT tsa réservé au compte
#              de service tsa:timestamp-authority (jeton périodique) ; certificat feuille de la clé Transit (EKU
#              timeStamping seul, critique), clé publique recoupée ; chaîne et racine de confiance de cosign
#   deployer   TSA sur le nœud de confiance (tsa/tsa.yaml), OpenBao ouvert à l'espace tsa
#   temoin     jeton témoin demandé depuis l'espace horodatage, vérifié sur l'hôte par openssl (racine TSA) et par
#              timestamp-cli ; refus : autre contenu, CA TLS du PoC (aussi rejoué après un redémarrage des VM)
#   essais     temoin ; refus : TSA depuis un autre espace, rôle tsa pour un autre compte, clé chains avec le rôle tsa
#              et clé tsa avec le rôle tekton-chains, export ; Zot : poc-horodatage hors de horodatage/** ; audit
#   horodater  job d'horodatage (tsa/horodater.sh) sur les images signées de J4 : bundles v0.3 en referrers dans
#              horodatage/bundles ; rejouable (enveloppes déjà horodatées sautées)
#   chemins    mesure des chemins de vérification (jeton valide, absent, falsifié) par cosign et Kyverno
# Aucun secret en argument de commande : jetons et mots de passe par fichier 0600 ou entrée standard.
#
# Usage (racine du dépôt) : mise run confiance:tsa -- <étape>…   (journal : resultats/tsa-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
TSA_AMONT=ghcr.io/sigstore/timestamp-server
TSA_INDEX=sha256:77c615f0bef6ddd907b531099cd1a8cf8f698ca9a08b1abf7397b222c9352306   # v2.2.0
TSA_AMD64=sha256:0cddebb024e8bb135d250da6ffc603d847d4bdd8a0470622701efdf6db1ac037
TSA_DEPOT=sigstore/timestamp-authority
TSA_TAG_OBJET=11108902eaf0307666abeef7e16cd8eab8050e81   # tag annoté v2.2.0
TSA_COMMIT=526e9de76cded7d2fd7b3d9b21061305ea7c85b2
CLI_SHA=18ee91ff6980ce279f49a0643808bf943785e88101aac5c8593170d642235f3d   # timestamp-cli-linux-amd64 v2.2.0
COSIGN_AMONT=ghcr.io/sigstore/cosign/cosign
COSIGN_INDEX=sha256:8af1a2cf9fba903fdfc6bdafdc25f7b13ef34ad722095543ea787fb96f7240c1   # v3.1.4-dev (busybox)
COSIGN_AMD64=sha256:c142f6bc0c6d8e5e4a3d31b941200a12502ad90bb5ce93b78c875c868905619d
COSIGN_ID=keyless@projectsigstore.iam.gserviceaccount.com   # sigstore/docs : cosign/system_config/installation.md
ORAS_TGZ_SHA=66fb0ad7206f3f6fa77ed5b552049d364ccf4b50b1684554f731f76302b52ca0   # mise.lock, oras 1.3.6
ORAS_FPR=C6FC42F0DE84A345FAADB742F44418110791EF37   # « ORAS Project Release Signing » (KEYS du dépôt, oras.land)
MIROIR_TSA=amont/sigstore/timestamp-server
MIROIR_COSIGN=amont/sigstore/cosign/cosign
OUTILS=plateforme/outils-horodatage
OUTILS_DIGEST=sha256:c7bebae2bd33e57792988b8ba215536dd9360a9871ec0bdf807ee94d4c1f4ca0   # assemblage reproductible (tsa.sh image)
BAO_INDEX=sha256:5046911075e137e154ce49ab051502f4ec7cf367d484ae4a4dce665d9b90561f   # openbao.sh
SUJET=system:serviceaccount:tsa:timestamp-authority
URL_TSA=http://timestamp-authority.tsa.svc.cluster.local:3000/api/v1/timestamp
DEPOT_BUNDLES=horodatage/bundles   # bundles réémis, hors des dépôts des images (voir tsa/horodater.sh)
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # images d'essai signées en J4
DL=$O/telechargements/tsa
T=$W/tsa
trap 'rm -rf "$T" "$W/refus.out"' EXIT   # copies de secrets et jetons d'essai, même en cas d'échec
(umask 077 && mkdir -p "$T" "$DL")

telecharger() { # url fichier
  [ -s "$DL/$2" ] || curl -fsSL -o "$DL/$2" "$1"
}

etape_image() {
  local d s
  echo "## timestamp-server v2.2.0"
  [ "$(gh api "repos/$TSA_DEPOT/git/refs/tags/v2.2.0" --jq .object.sha)" = "$TSA_TAG_OBJET" ] \
    && [ "$(gh api "repos/$TSA_DEPOT/git/tags/$TSA_TAG_OBJET" --jq '.object.sha + " " + (.verification.verified | tostring)')" = "$TSA_COMMIT true" ] \
    && echo "OK   tag v2.2.0 (objet $TSA_TAG_OBJET, signé et vérifié par GitHub) → commit $TSA_COMMIT" \
    || { echo "KO   tag v2.2.0" >&2; exit 1; }
  d=$(crane digest "$TSA_AMONT:v2.2.0")
  echo "$TSA_AMONT:v2.2.0 → $d $([ "$d" = "$TSA_INDEX" ] && echo '(= digest épinglé)' || echo "(≠ digest épinglé $TSA_INDEX)")"
  crane manifest "$TSA_AMONT@$TSA_INDEX" | jq -e --arg d "$TSA_AMD64" '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest == $d' >/dev/null \
    && echo "OK   l'index référence le manifeste linux/amd64 $TSA_AMD64" || { echo "KO   manifeste amd64" >&2; exit 1; }
  verifier_tsa "oci://$TSA_AMONT@$TSA_INDEX"
  auth_zot "$T/zot.json"
  miroir "$TSA_AMONT@$TSA_INDEX" "$MIROIR_TSA" "$T/zot.json" -r
  cat /etc/ssl/certs/ca-certificates.crt "$P/ca-poc.crt" > "$T/ca-tous.pem"   # gh joint aussi GitHub
  SSL_CERT_FILE=$T/ca-tous.pem verifier_tsa "oci://$REG_HOTE/$MIROIR_TSA@$TSA_INDEX" --bundle-from-oci
  echo "## cosign v3.1.4-dev (base de l'image d'outils)"
  d=$(crane digest "$COSIGN_AMONT:v3.1.4-dev")
  echo "$COSIGN_AMONT:v3.1.4-dev → $d $([ "$d" = "$COSIGN_INDEX" ] && echo '(= digest épinglé)' || echo "(≠ digest épinglé $COSIGN_INDEX)")"
  crane manifest "$COSIGN_AMONT@$COSIGN_INDEX" | jq -e --arg d "$COSIGN_AMD64" '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest == $d' >/dev/null \
    && echo "OK   l'index référence le manifeste linux/amd64 $COSIGN_AMD64" || { echo "KO   manifeste amd64" >&2; exit 1; }
  cosign verify --certificate-oidc-issuer https://accounts.google.com --certificate-identity "$COSIGN_ID" \
    "$COSIGN_AMONT@$COSIGN_INDEX" > "$T/cosign.json" 2> "$T/cosign.err" || { cat "$T/cosign.err" >&2; exit 1; }
  echo "OK   signature de $COSIGN_AMONT@$COSIGN_INDEX : $COSIGN_ID (https://accounts.google.com), type $(jq -r '[.[].critical.type] | unique | join(",")' "$T/cosign.json")"
  grep -E '^  - ' "$T/cosign.err" || true
  refus "identité voisine" "no matching CertificateIdentity|none of the expected identities" \
    cosign verify --certificate-oidc-issuer https://accounts.google.com --certificate-identity "github-actions-cosign@projectsigstore.iam.gserviceaccount.com" "$COSIGN_AMONT@$COSIGN_INDEX"
  miroir "$COSIGN_AMONT@$COSIGN_AMD64" "$MIROIR_COSIGN" "$T/zot.json"
  echo "## timestamp-cli v2.2.0"
  telecharger "https://github.com/$TSA_DEPOT/releases/download/v2.2.0/timestamp-cli-linux-amd64" timestamp-cli-linux-amd64
  telecharger "https://github.com/$TSA_DEPOT/releases/download/v2.2.0/timestamp-authority_checksums.txt" timestamp-authority_checksums.txt
  (cd "$DL" && grep ' timestamp-cli-linux-amd64$' timestamp-authority_checksums.txt | sha256sum -c && echo "$CLI_SHA  timestamp-cli-linux-amd64" | sha256sum -c)
  gh attestation verify "$DL/timestamp-cli-linux-amd64" --repo "$TSA_DEPOT" --signer-workflow "$TSA_DEPOT/.github/workflows/release.yaml" \
    --source-ref refs/tags/v2.2.0 --source-digest "$TSA_COMMIT" --deny-self-hosted-runners --format json \
    | jq -r '.[0].verificationResult.signature.certificate | "OK   attestation GitHub de timestamp-cli : \(.buildSignerURI), commit \(.sourceRepositoryDigest), déclencheur \(.buildTrigger)"'
  echo "## oras 1.3.6"
  for f in oras_1.3.6_linux_amd64.tar.gz oras_1.3.6_checksums.txt oras_1.3.6_checksums.txt.asc; do
    telecharger "https://github.com/oras-project/oras/releases/download/v1.3.6/$f" "$f"
  done
  telecharger https://raw.githubusercontent.com/oras-project/oras/v1.3.6/KEYS oras-KEYS
  telecharger https://raw.githubusercontent.com/oras-project/oras-www/main/versioned_docs/version-1.3/how_to_guides/verifying_binaries.mdx oras-verifying_binaries.mdx
  s=$(tr -d ' ' < "$DL/oras-verifying_binaries.mdx" | grep -c "$ORAS_FPR" || true)
  [ "$s" -gt 0 ] && echo "OK   empreinte $ORAS_FPR publiée sur oras.land (dépôt oras-www, version 1.3)" || { echo "KO   empreinte absente d'oras.land" >&2; exit 1; }
  (umask 077 && mkdir -p "$T/gnupg")
  GNUPGHOME=$T/gnupg gpg --batch --quiet --import "$DL/oras-KEYS" 2>/dev/null
  s=$(GNUPGHOME=$T/gnupg gpg --batch --status-fd 1 --verify "$DL/oras_1.3.6_checksums.txt.asc" "$DL/oras_1.3.6_checksums.txt" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}')
  [ "$s" = "$ORAS_FPR" ] && echo "OK   signature GPG de oras_1.3.6_checksums.txt : clé primaire $s" || { echo "KO   signature GPG ($s)" >&2; exit 1; }
  (cd "$DL" && grep ' oras_1.3.6_linux_amd64.tar.gz$' oras_1.3.6_checksums.txt | sha256sum -c && echo "$ORAS_TGZ_SHA  oras_1.3.6_linux_amd64.tar.gz" | sha256sum -c)
  echo "## image d'outils du job (crane append, couche reproductible)"
  rm -rf "$T/racine" && mkdir -p "$T/racine/usr/local/bin" && chmod 0755 "$T/racine" "$T/racine/usr" "$T/racine/usr/local" "$T/racine/usr/local/bin"
  tar -xzf "$DL/oras_1.3.6_linux_amd64.tar.gz" -C "$T/racine/usr/local/bin" oras
  install -m 0755 "$DL/timestamp-cli-linux-amd64" "$T/racine/usr/local/bin/timestamp-cli"
  chmod 0755 "$T/racine/usr/local/bin/oras"
  (cd "$T/racine/usr/local/bin" && sha256sum oras timestamp-cli)
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$T/couche.tar" -C "$T/racine" usr
  mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"
  d=$(DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt crane append -b "$REG_HOTE/$MIROIR_COSIGN@$COSIGN_AMD64" \
    -f "$T/couche.tar" -t "$REG_HOTE/$OUTILS:v2.2.0-1.3.6" 2>/dev/null)
  echo "image d'outils : $d"
  [ "${d##*@}" = "$OUTILS_DIGEST" ] && echo "OK   même digest que l'image épinglée (assemblage reproductible)" \
    || { echo "KO   digest différent de l'image épinglée $OUTILS_DIGEST" >&2; exit 1; }
}

verifier_tsa() { # oci://référence [options gh…] : attestation GitHub de l'image, workflow et commit du tag v2.2.0
  local ref=$1; shift
  gh attestation verify "$ref" "$@" --repo "$TSA_DEPOT" --signer-workflow "$TSA_DEPOT/.github/workflows/build_container.yml" \
    --source-ref refs/tags/v2.2.0 --source-digest "$TSA_COMMIT" --deny-self-hosted-runners --format json > "$T/gh.json" 2> "$T/gh.err" \
    || { cat "$T/gh.err" >&2; exit 1; }
  jq -r --arg r "$ref" '.[0].verificationResult | "OK   attestation GitHub de \($r) : \(.statement.predicateType), \(.signature.certificate.buildSignerURI), commit \(.signature.certificate.sourceRepositoryDigest), déclencheur \(.signature.certificate.buildTrigger)"' "$T/gh.json"
}

etape_pki() {
  if [ -s "$S/tsa-racine.key" ] && [ -s "$P/tsa-racine.crt" ]; then echo "racine TSA existante"; else
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/tsa-racine.key")
    openssl req -x509 -new -key "$S/tsa-racine.key" -subj "/O=supply-chain PoC/CN=Racine TSA du PoC" -days 3650 -sha256 \
      -config "$here/tsa/pki.cnf" -extensions racine_tsa -out "$P/tsa-racine.crt"
  fi
  openssl x509 -in "$P/tsa-racine.crt" -noout -subject -enddate -ext basicConstraints,keyUsage | paste -sd' ' | sed 's/  */ /g'
  openssl x509 -in "$P/tsa-racine.crt" -noout -fingerprint -sha256
}

etape_openbao() {
  local pub
  racine <<EOF | jq -c 'if .data then .data else . end | if has("keys") then {name, type, exportable, allow_plaintext_backup, deletion_allowed, latest_version} else {bound_audiences, bound_subject, user_claim, token_policies, token_no_default_policy, token_type, token_period, token_ttl, token_max_ttl} end'
set -eu
bao read transit/keys/tsa >/dev/null 2>&1 || bao write -f transit/keys/tsa type=ecdsa-p256 exportable=false allow_plaintext_backup=false >&2
bao read -format=json transit/keys/tsa
bao policy write tsa-signature - >&2 <<'POL'
$(cat "$here/tsa/tsa-signature.hcl")
POL
bao write auth/jwt/role/tsa role_type=jwt user_claim=sub bound_audiences=openbao bound_subject=$SUJET \
  token_policies=tsa-signature token_no_default_policy=true token_type=service token_period=1h >&2
bao read -format=json auth/jwt/role/tsa
EOF
  racine <<<'bao policy read tsa-signature' | grep -v '^#'
  racine <<<'bao read -format=json transit/keys/tsa' | jq -r '.data.keys | to_entries | max_by(.key | tonumber) | .value.public_key' > "$T/transit.pub"
  pub=$(openssl pkey -pubin -in "$T/transit.pub" -outform DER | sha256sum | cut -c1-64)
  if [ -s "$P/tsa-feuille.crt" ] && [ "$(openssl x509 -in "$P/tsa-feuille.crt" -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum | cut -c1-64)" = "$pub" ]; then
    echo "certificat feuille existant (clé Transit inchangée)"
  else
    openssl x509 -new -force_pubkey "$T/transit.pub" -subj "/O=supply-chain PoC/CN=TSA du PoC" -CA "$P/tsa-racine.crt" -CAkey "$S/tsa-racine.key" \
      -set_serial "0x$(openssl rand -hex 16)" -days 365 -sha256 -extfile "$here/tsa/pki.cnf" -extensions feuille_tsa -out "$P/tsa-feuille.crt"
    echo "certificat feuille émis pour la clé Transit tsa"
  fi
  openssl verify -CAfile "$P/tsa-racine.crt" -purpose timestampsign "$P/tsa-feuille.crt"
  openssl x509 -in "$P/tsa-feuille.crt" -noout -subject -issuer -enddate -ext basicConstraints,keyUsage,extendedKeyUsage | paste -sd' ' | sed 's/  */ /g'
  [ "$(openssl x509 -in "$P/tsa-feuille.crt" -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum | cut -c1-64)" = "$pub" ] \
    && echo "OK   clé publique du certificat = clé publique Transit tsa (SPKI sha256 ${pub:0:16}…)" || { echo "KO   SPKI" >&2; exit 1; }
  cat "$P/tsa-feuille.crt" "$P/tsa-racine.crt" > "$P/tsa-chaine.pem"
  cp "$P/tsa-chaine.pem" "$R/tsa-chaine.pem"
  cosign trusted-root create --tsa="url=$URL_TSA,certificate-chain=$P/tsa-chaine.pem" --out "$P/tsa-racine-confiance.json" 2>/dev/null
  jq -c '{mediaType, tsa: [.timestampAuthorities[] | {uri, certificats: (.certChain.certificates | length), validFor}], tlogs: (.tlogs | length), ca: (.certificateAuthorities | length), ctlogs: (.ctlogs | length)}' "$P/tsa-racine-confiance.json"
}

etape_deployer() {
  local empreinte pod
  # NetworkPolicy d'OpenBao seule (openbao.yaml) : ouverte à l'espace tsa, sans toucher au StatefulSet (descellement).
  awk 'BEGIN {RS = "\n---\n"} /\nkind: NetworkPolicy\n/' "$here/openbao/openbao.yaml" | kubectl apply --server-side -f - >/dev/null
  kubectl get networkpolicy -n openbao openbao -o jsonpath='{range .spec.ingress[0].from[*]}{.namespaceSelector.matchLabels}{" "}{.podSelector.matchLabels}{"\n"}{end}'
  empreinte=$(cat "$P/tsa-chaine.pem" "$P/ca-poc.crt" "$here/tsa/tsa.yaml" | sha256sum | cut -c1-16)
  sed -e "s#@TSA@#$REG/$MIROIR_TSA@$TSA_INDEX#" -e "s#@BAO@#$REG/amont/openbao/openbao@$BAO_INDEX#" "$here/tsa/tsa.yaml" \
    | awk -v e="$empreinte" '{print} /^  template:$/ {t=1} t && /^    metadata:$/ {print "      annotations:\n        poc/configuration: \"" e "\""; t=0}' \
    | kubectl apply --server-side -f -
  kubectl create configmap tsa-config -n tsa --from-file=chaine.pem="$P/tsa-chaine.pem" --from-file=ca-poc.crt="$P/ca-poc.crt" \
    --dry-run=client -o yaml | kubectl apply --server-side -f -
  kubectl rollout status -n tsa deployment/timestamp-authority --timeout=180s
  kubectl get pods -n tsa -o wide
  kubectl get pods -n tsa -l app=timestamp-authority -o jsonpath='{range .items[0].status.containerStatuses[*]}{.name} {.imageID}{"\n"}{end}'
  # Pod le plus récent : après un redéploiement, l'ancien peut être encore en cours d'arrêt.
  pod=$(kubectl get pods -n tsa -l app=timestamp-authority --sort-by=.metadata.creationTimestamp -o name | tail -1)
  kubectl logs -n tsa "$pod" -c connexion
  for _ in $(seq 30); do
    kubectl logs -n tsa "$pod" -c renouvellement 2>/dev/null | grep -q 'jeton renouvelé : 3600 s' && break
    sleep 1
  done
  kubectl logs -n tsa "$pod" -c renouvellement | grep -q 'jeton renouvelé : 3600 s' \
    && echo "OK   jeton OpenBao du TSA renouvelé au démarrage ($(kubectl logs -n tsa "$pod" -c renouvellement | tail -1))" \
    || { echo "KO   renouvellement du jeton" >&2; kubectl logs -n tsa "$pod" -c renouvellement >&2; exit 1; }
  kubectl logs -n tsa deployment/timestamp-authority -c timestamp-server | jq -R -r 'fromjson? // {message: .} | .message' | grep -v -E '^\{|^  ' | head -5
}

pod_outils() { # nom espace script : pod d'essai avec l'image d'outils sur le nœud de confiance ; affiche sa sortie
  local nom=$1 ns=$2 phase=""
  kubectl delete pod -n "$ns" "$nom" --ignore-not-found --wait=true >/dev/null
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $nom, namespace: $ns}
spec:
  automountServiceAccountToken: false
  enableServiceLinks: false
  restartPolicy: Never
  nodeSelector: {zone: confiance}
  securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: essai
    image: $REG/$OUTILS@$OUTILS_DIGEST
    command: [sh, -c, $(jq -Rs . <<<"$3")]
    env: [{name: HOME, value: /travail}]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    volumeMounts: [{name: travail, mountPath: /travail}]
  volumes: [{name: travail, emptyDir: {}}]
EOF
  for _ in $(seq 90); do
    phase=$(kubectl get pod -n "$ns" "$nom" -o jsonpath='{.status.phase}')
    case $phase in Succeeded|Failed) break ;; esac
    sleep 2
  done
  kubectl logs -n "$ns" "$nom"
  [ "$phase" = Succeeded ] || { echo "KO   pod $ns/$nom : $phase" >&2; return 1; }
}

en_tant_que() { # compte espace rôle : script sh (entrée standard) exécuté dans openbao-0 après connexion JWT avec ce rôle
  # Le jeton du compte de service (audience openbao, 10 min) passe par l'entrée standard, jamais en argument.
  { kubectl create token "$1" -n "$2" --audience openbao --duration 10m; echo; echo "$3"; cat; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c '
read -r JWT; read -r ROLE
if ! r=$(printf "%s" "$JWT" | bao write -format=json auth/jwt/login role="$ROLE" jwt=- 2>&1); then
  echo "CONNEXION_REFUSEE|$(echo "$r" | grep -E "Code:|\* " | tr "\n\t" "  " | sed "s/  */ /g")"; exit 0
fi
BAO_TOKEN=$(echo "$r" | sed -n "s/.*\"client_token\": \"\([^\"]*\)\".*/\1/p"); export BAO_TOKEN
echo "CONNEXION_ACCEPTEE|$(echo "$r" | tr -d "\n " | grep -o "\"token_policies\":\[[^]]*\]")"
refus() { l=$1; shift; if o=$("$@" 2>&1); then echo "ACCEPTE|$l"; else echo "REFUSE|$l|$(echo "$o" | grep -E "Code:|\* " | tr "\n\t" "  " | sed "s/  */ /g")"; fi; }
eval "$(cat)"'
}

etape_temoin() { # jeton témoin demandé depuis l'espace horodatage, vérifié sur l'hôte (aussi après un redémarrage)
  local sortie
  echo "## jeton témoin, depuis l'espace horodatage"
  kubectl apply -f "$here/tsa/horodatage.yaml" >/dev/null
  attendre_sa horodatage
  sortie=$(pod_outils j5-temoin horodatage '
set -eu
cd /travail
n=1; until wget -q -O chaine.pem http://timestamp-authority.tsa.svc.cluster.local:3000/api/v1/timestamp/certchain 2>/dev/null; do
  [ $n -lt 30 ] || { echo "INJOIGNABLE"; exit 1; }; n=$((n + 1)); sleep 1; done
echo "JOINT|essai $n"
printf "Brique 08, J5 : jeton témoin\n" > temoin.txt
timestamp-cli --timestamp_server http://timestamp-authority.tsa.svc.cluster.local:3000 timestamp --artifact temoin.txt --hash sha256 --out temoin.tsr
echo "VERIFICATION_TIMESTAMP_CLI|$(timestamp-cli verify --timestamp temoin.tsr --artifact temoin.txt --certificate-chain chaine.pem --common-name "TSA du PoC" 2>&1 | tail -1)"
echo "CHAINE|$(base64 chaine.pem | tr -d "\n")"
echo "JETON|$(base64 temoin.tsr | tr -d "\n")"')
  grep -v -E '^(CHAINE|JETON)\|' <<<"$sortie"
  sed -n 's/^CHAINE|//p' <<<"$sortie" | base64 -d > "$T/chaine-servie.pem"
  sed -n 's/^JETON|//p' <<<"$sortie" | base64 -d > "$T/temoin.tsr"
  cmp -s "$T/chaine-servie.pem" "$P/tsa-chaine.pem" && echo "OK   chaîne servie par le TSA = chaîne émise (feuille de la clé Transit, racine TSA)" \
    || { echo "KO   chaîne servie différente" >&2; exit 1; }
  printf 'Brique 08, J5 : jeton témoin\n' > "$T/temoin.txt"
  openssl ts -reply -in "$T/temoin.tsr" -text 2>/dev/null | grep -E '^(Status:|Policy OID|Hash Algorithm|Time stamp|Accuracy|Ordering|Nonce|TSA:)' | paste -sd' ' | sed 's/  */ /g'
  openssl ts -verify -data "$T/temoin.txt" -in "$T/temoin.tsr" -CAfile "$P/tsa-racine.crt" -untrusted "$P/tsa-feuille.crt" 2>&1 | grep -q '^Verification: OK' \
    && echo "OK   jeton vérifié sur l'hôte par openssl ts -verify (racine TSA, feuille de la clé Transit)" || { echo "KO   openssl ts -verify" >&2; exit 1; }
  printf 'autre contenu\n' > "$T/autre.txt"
  refus "jeton confronté à un autre contenu (openssl)" "message imprint mismatch" \
    openssl ts -verify -data "$T/autre.txt" -in "$T/temoin.tsr" -CAfile "$P/tsa-racine.crt" -untrusted "$P/tsa-feuille.crt"
  refus "jeton confronté à la CA TLS du PoC (openssl)" "certificate verify error|unable to get local issuer" \
    openssl ts -verify -data "$T/temoin.txt" -in "$T/temoin.tsr" -CAfile "$P/ca-poc.crt" -untrusted "$P/tsa-feuille.crt"

}

etape_essais() {
  local debut h
  debut=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  etape_temoin

  echo "## TSA injoignable hors de l'espace horodatage"
  kubectl create namespace j5-essais --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  attendre_sa j5-essais
  pod_outils j5-reseau j5-essais '
n=0; until wget -q -T 2 -O /dev/null http://timestamp-authority.tsa.svc.cluster.local:3000/api/v1/timestamp/certchain 2>/dev/null || [ $n -ge 15 ]; do n=$((n + 1)); sleep 1; done
if [ $n -lt 15 ]; then echo "JOINT|essai $n"; else echo "INJOIGNABLE|15 essais sur environ 45 s"; fi' | tee "$T/reseau.txt"
  grep -q '^INJOIGNABLE' "$T/reseau.txt" && echo "OK   TSA injoignable depuis j5-essais (NetworkPolicy)" || { echo "KO   TSA joignable" >&2; exit 1; }

  echo "## OpenBao : rôle tsa et clés séparées"
  h=$(printf 'Brique 08, J5' | openssl dgst -sha256 -binary | base64)
  en_tant_que timestamp-authority tsa tsa <<EOF | tee "$T/bao.txt"
echo "SIGNATURE_TSA|\$(bao write -field=signature transit/sign/tsa/sha2-256 input=$h prehashed=true | cut -c1-12)…"
echo "RENOUVELLEMENT|durée \$(bao token renew -format=json | tr -d '\n ' | sed -n 's/.*"auth":{.*"lease_duration":\([0-9]*\).*/\1/p') s"
refus "signature avec la clé chains" bao write transit/sign/chains/sha2-256 input=$h prehashed=true
refus "lecture de la clé chains" bao read transit/keys/chains
refus "export de la clé tsa" bao read transit/export/signing-key/tsa
refus "clé tsa rendue exportable" bao write transit/keys/tsa/config exportable=true
refus "sauvegarde en clair de la clé tsa" bao read transit/backup/tsa
refus "lecture de son propre jeton" bao token lookup
EOF
  en_tant_que tekton-chains-controller tekton-chains tsa </dev/null | tee -a "$T/bao.txt"
  en_tant_que tekton-chains-controller tekton-chains tekton-chains <<EOF | tee -a "$T/bao.txt"
refus "signature avec la clé tsa (rôle tekton-chains)" bao write transit/sign/tsa/sha2-256 input=$h prehashed=true
EOF
  en_tant_que timestamp-authority tsa tekton-chains </dev/null | tee -a "$T/bao.txt"
  [ "$(grep -c '^ACCEPTE' "$T/bao.txt")" = 0 ] && [ "$(grep -c '^REFUSE' "$T/bao.txt")" = 7 ] && [ "$(grep -c '^CONNEXION_REFUSEE' "$T/bao.txt")" = 2 ] \
    && grep -q '^SIGNATURE_TSA|vault:v1:' "$T/bao.txt" \
    && echo "OK   rôle tsa : signe avec la seule clé tsa ; 7 refus, 2 connexions croisées refusées" || { echo "KO   OpenBao" >&2; exit 1; }

  echo "## Zot : poc-horodatage limité à horodatage/**"
  auth_zot "$T/zot-horodatage.json" "" poc-horodatage
  blob() { openssl rand -hex 16 > "$T/blob.txt"; }   # contenu neuf : oras saute un blob déjà présent sans rien écrire
  blob; oras blob push --ca-file "$P/ca-poc.crt" --registry-config "$T/zot-horodatage.json" "$REG_HOTE/horodatage/essais" "$T/blob.txt" | tail -1
  echo "OK   poc-horodatage écrit dans horodatage/"
  blob; refus "poc-horodatage dans builds/" "denied|403|forbidden|unauthorized" \
    oras blob push --ca-file "$P/ca-poc.crt" --registry-config "$T/zot-horodatage.json" "$REG_HOTE/builds/essai-j5" "$T/blob.txt"
  blob; refus "poc-horodatage dans amont/" "denied|403|forbidden|unauthorized" \
    oras blob push --ca-file "$P/ca-poc.crt" --registry-config "$T/zot-horodatage.json" "$REG_HOTE/amont/essai-j5" "$T/blob.txt"
  printf '{}\n' > "$T/anonyme.json"
  blob; refus "écriture anonyme dans horodatage/" "basic credential not found|unauthorized|401" \
    oras blob push --ca-file "$P/ca-poc.crt" --registry-config "$T/anonyme.json" "$REG_HOTE/horodatage/essais" "$T/blob.txt"
  h=$(curl -s -o /dev/null -w '%{http_code}' -X POST --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/horodatage/essais/blobs/uploads/")
  [ "$h" = 401 ] && echo "OK   ouverture d'un envoi anonyme dans horodatage/ : HTTP $h" || { echo "KO   envoi anonyme : HTTP $h" >&2; exit 1; }

  echo "## audit d'OpenBao depuis $debut"
  kubectl exec -n openbao openbao-0 -- cat /openbao/data/audit.log > "$T/audit.log"
  jq -c --arg d "$debut" 'select(.type == "response" and .time >= $d and (.request.path | test("^(auth/jwt/login|transit/|auth/token/)")))
    | {time: .time[11:19], chemin: .request.path, op: .request.operation, compte: (.auth.display_name // .auth.metadata.role // null),
       politiques: (.auth.policies // null), erreur: (.error // .response.data.error // null)}' "$T/audit.log" \
    | awk '{c[$0]++; if (c[$0] == 1) o[++n] = $0} END {for (i = 1; i <= n; i++) print o[i] (c[o[i]] > 1 ? " ×" c[o[i]] : "")}'
  kubectl delete ns j5-essais --wait=false >/dev/null
  kubectl delete pod -n horodatage j5-temoin --wait=false >/dev/null
}

job_horodatage() { # dépôt-de-l'image : job d'horodatage de l'image d'essai de J4 dans ce dépôt ; affiche sa sortie
  local nom=h-${1##*/} etat=""
  kubectl delete job -n horodatage "$nom" --ignore-not-found --wait=true >/dev/null
  sed -e "s#@NOM@#$nom#" -e "s#@OUTILS@#$REG/$OUTILS@$OUTILS_DIGEST#" -e "s#@IMAGE@#$REG/$1@$APP_DIGEST#" -e "s#@DEPOT@#$REG/$DEPOT_BUNDLES#" \
    "$here/tsa/horodatage-job.yaml" | kubectl apply -f - >/dev/null
  for _ in $(seq 90); do
    etat=$(kubectl get job -n horodatage "$nom" -o jsonpath='{.status.succeeded}/{.status.failed}')
    case $etat in 1/*|*/1) break ;; esac
    sleep 2
  done
  kubectl logs -n horodatage "job/$nom"
  [ "${etat%%/*}" = 1 ] || { echo "KO   job $nom : $etat" >&2; return 1; }
}

referrers() { # dépôt : referrers de l'image d'essai dans ce dépôt (API OCI 1.1 de Zot, lecture anonyme)
  curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$1/referrers/$APP_DIGEST"
}

etape_horodater() {
  kubectl apply -f "$here/tsa/horodatage.yaml" >/dev/null
  attendre_sa horodatage
  auth_zot "$T/zot-horodatage.json" "" poc-horodatage "$REG"
  kubectl create secret generic zot-horodatage -n horodatage --from-file=config.json="$T/zot-horodatage.json" \
    --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  echo "secret zot-horodatage appliqué (poc-horodatage, $REG ; lu sur l'entrée standard de kubectl, sans annotation last-applied)"
  kubectl create configmap horodatage -n horodatage --from-file=horodater.sh="$here/tsa/horodater.sh" \
    --from-file=ca-poc.crt="$P/ca-poc.crt" --from-file=chains.pub="$R/chains-cle-publique.pem" \
    --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  echo "## builds/essai-signature (une exécution signée en J4)"
  job_horodatage builds/essai-signature
  echo "## builds/essai-webhook (une enveloppe par exécution signée de l'essai du webhook)"
  job_horodatage builds/essai-webhook
  echo "## reprise : builds/essai-signature une seconde fois"
  job_horodatage builds/essai-signature | tee "$T/reprise.txt"
  grep -q '^HORODATEE' "$T/reprise.txt" && { echo "KO   enveloppe horodatée deux fois" >&2; exit 1; }
  echo "OK   reprise sans nouvel horodatage ni nouveau bundle"
  echo "## referrers de $APP_DIGEST dans $DEPOT_BUNDLES (aucun dans les dépôts des images)"
  referrers "$DEPOT_BUNDLES" | jq -c '.manifests[] | {digest: .digest[7:19], artifactType, predicateType: .annotations["dev.sigstore.bundle.predicateType"]}'
  for d in builds/essai-signature builds/essai-webhook; do
    echo "$d : $(referrers "$d" | jq '.manifests | length') referrer(s)"
  done
  [ "$(referrers "$DEPOT_BUNDLES" | jq '[.manifests[] | select(.artifactType == "application/vnd.dev.sigstore.bundle.v0.3+json")] | length')" \
    = "$(($(cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-signature@$APP_DIGEST" 2>/dev/null | wc -l) \
         + $(cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-webhook@$APP_DIGEST" 2>/dev/null | wc -l)))" ] \
    && echo "OK   un bundle par enveloppe de Chains" || { echo "KO   nombre de bundles" >&2; exit 1; }
}

publier_bundle() { # dépôt fichier : bundle publié en referrer de l'image d'essai (manifeste fait main : sujet hors du dépôt)
  local f=$2 pt
  pt=$(jq -r '.dsseEnvelope.payload | @base64d | fromjson | .predicateType' "$f")
  printf '{}' > "$T/vide.json"
  oras blob push --ca-file "$P/ca-poc.crt" --registry-config "$T/zot.json" "$REG_HOTE/$1" "$T/vide.json" >/dev/null
  oras blob push --ca-file "$P/ca-poc.crt" --registry-config "$T/zot.json" "$REG_HOTE/$1" "$f" >/dev/null
  jq -n --arg ld "sha256:$(sha256sum < "$f" | cut -c1-64)" --argjson ls "$(stat -c%s "$f")" --arg pt "$pt" --slurpfile s "$T/sujet.json" '{
    schemaVersion: 2, mediaType: "application/vnd.oci.image.manifest.v1+json", artifactType: "application/vnd.dev.sigstore.bundle.v0.3+json",
    config: {mediaType: "application/vnd.oci.empty.v1+json", digest: "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", size: 2},
    layers: [{mediaType: "application/vnd.dev.sigstore.bundle.v0.3+json", digest: $ld, size: $ls}],
    subject: $s[0], annotations: {"dev.sigstore.bundle.content": "dsse-envelope", "dev.sigstore.bundle.predicateType": $pt}}' > "$T/manifeste.json"
  oras manifest push --ca-file "$P/ca-poc.crt" --registry-config "$T/zot.json" "$REG_HOTE/$1:${1##*/}" "$T/manifeste.json" >/dev/null
}


verif_cosign() { # dépôt-des-bundles : vérification par cosign v3.1.4 (bundle, clé de Chains, racine de confiance du TSA)
  COSIGN_REPOSITORY=$REG_HOTE/$1 cosign verify-attestation --key "$R/chains-cle-publique.pem" --insecure-ignore-tlog \
    --use-signed-timestamps --trusted-root "$P/tsa-racine-confiance.json" --type slsaprovenance1 \
    --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-signature@$APP_DIGEST" > "$T/cosign.out" 2>&1
}

verif_kyverno() { # dépôt-des-bundles [chaîne-TSA] : kyverno apply (CLI 1.19.2) ; affiche pass, fail ou error et le motif
  ivpol "$@" > "$T/ivpol.yaml"
  SSL_CERT_FILE=$P/ca-poc.crt kyverno apply "$T/ivpol.yaml" --resource "$T/pod.yaml" --policy-report --output-format json \
    > "$T/kyverno.json" 2> "$T/kyverno.err" || true
  jq -r '[.. | objects | select(has("result") and has("policy"))][0] | "\(.result) (\(.message // "" | .[0:110]))"' "$T/kyverno.json"
}

motif_kyverno() { # motif : relance kyverno apply (politique $T/ivpol.yaml) en mode verbeux et affiche le motif cherché
  SSL_CERT_FILE=$P/ca-poc.crt kyverno apply "$T/ivpol.yaml" --resource "$T/pod.yaml" -v 6 > "$T/kyverno-v6.out" 2>&1 || true
  sed 's/\x1b\[[0-9;]*m//g' "$T/kyverno-v6.out" | grep -o "$1" | sort -u | sed 's/^/  motif : /' | grep . \
    || { echo "KO   motif introuvable : $1" >&2; sed 's/\x1b\[[0-9;]*m//g' "$T/kyverno-v6.out" >&2; exit 1; }
}

etape_chemins() {
  local b c r k e
  auth_zot "$T/zot.json"
  oras manifest fetch --ca-file "$P/ca-poc.crt" --descriptor "$REG_HOTE/builds/essai-signature@$APP_DIGEST" > "$T/sujet.json"
  cat > "$T/pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata: {name: essai-j5, namespace: default}
spec:
  containers:
    - name: app
      image: $REG_HOTE/builds/essai-signature@$APP_DIGEST
EOF
  echo "## cas falsifiés, construits à partir des bundles du job (publiés par poc-ecriture dans essais-j5/*)"
  referrers "$DEPOT_BUNDLES" | jq -r '.manifests[].digest' | head -2 > "$T/bundles.txt"
  b=1; while read -r d; do
    oras manifest fetch --ca-file "$P/ca-poc.crt" "$REG_HOTE/$DEPOT_BUNDLES@$d" | jq -r '.layers[0].digest' \
      | xargs -I{} oras blob fetch --ca-file "$P/ca-poc.crt" --output "$T/b$b.json" "$REG_HOTE/$DEPOT_BUNDLES@{}"
    b=$((b + 1))
  done < "$T/bundles.txt"
  jq 'del(.verificationMaterial.timestampVerificationData)' "$T/b1.json" > "$T/sans-jeton.json"
  jq -r '.verificationMaterial.timestampVerificationData.rfc3161Timestamps[0].signedTimestamp' "$T/b1.json" | base64 -d > "$T/jeton.der"
  python3 -I -c 'import sys; b = bytearray(open(sys.argv[1], "rb").read()); b[-1] ^= 1; open(sys.argv[2], "wb").write(b)' "$T/jeton.der" "$T/jeton-altere.der"
  jq --arg t "$(base64 -w0 "$T/jeton-altere.der")" '.verificationMaterial.timestampVerificationData.rfc3161Timestamps[0].signedTimestamp = $t' "$T/b1.json" > "$T/jeton-altere.json"
  echo "jeton altéré : dernier octet (signature ECDSA du TSA) inversé, $(cmp -l "$T/jeton.der" "$T/jeton-altere.der" | wc -l) octet modifié sur $(stat -c%s "$T/jeton.der")"
  jq --slurpfile b2 "$T/b2.json" '.verificationMaterial.timestampVerificationData = $b2[0].verificationMaterial.timestampVerificationData' "$T/b1.json" > "$T/autre-signature.json"
  echo "jeton d'une autre signature : jeton valide du TSA, porté par l'enveloppe $(jq -r '.dsseEnvelope.signatures[0].sig[0:12]' "$T/b2.json")… et non $(jq -r '.dsseEnvelope.signatures[0].sig[0:12]' "$T/b1.json")…"
  # TSA étrangère : même forme (racine, feuille à EKU timeStamping critique), jeton sur les bons octets, autre racine.
  mkdir -p "$T/etrangere" && cd "$T/etrangere"
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out racine.key 2>/dev/null
  openssl req -x509 -new -key racine.key -subj "/O=Ailleurs/CN=Racine TSA etrangere" -days 30 -sha256 -config "$here/tsa/pki.cnf" -extensions racine_tsa -out racine.crt
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out feuille.key 2>/dev/null
  openssl pkey -in feuille.key -pubout -out feuille.pub
  openssl x509 -new -force_pubkey feuille.pub -subj "/O=Ailleurs/CN=TSA du PoC" -CA racine.crt -CAkey racine.key -set_serial 2 -days 30 -sha256 \
    -extfile "$here/tsa/pki.cnf" -extensions feuille_tsa -out feuille.crt
  printf '[ tsa ]\ndefault_tsa = e\n[ e ]\nserial = ./serial\nsigner_cert = ./feuille.crt\nsigner_key = ./feuille.key\nsigner_digest = sha256\ndefault_policy = 1.3.6.1.4.1.57264.2\ndigests = sha256\ness_cert_id_alg = sha256\ness_cert_id_chain = no\n' > ts.cnf
  echo 01 > serial
  jq -r '.dsseEnvelope.signatures[0].sig' "$T/b1.json" | base64 -d > sig.bin
  openssl ts -query -data sig.bin -sha256 -cert -out req.tsq 2>/dev/null
  openssl ts -reply -queryfile req.tsq -config ts.cnf -out rep.tsr 2>/dev/null
  openssl ts -verify -data sig.bin -in rep.tsr -CAfile racine.crt -untrusted feuille.crt 2>&1 | grep -q '^Verification: OK' \
    && echo "TSA étrangère : jeton valide pour sa propre racine (même CN « TSA du PoC », autre clé)" || { echo "KO   TSA étrangère" >&2; exit 1; }
  jq --arg t "$(base64 -w0 rep.tsr)" '.verificationMaterial.timestampVerificationData.rfc3161Timestamps[0].signedTimestamp = $t' "$T/b1.json" > "$T/tsa-etrangere.json"
  cd - >/dev/null
  for c in sans-jeton jeton-altere autre-signature tsa-etrangere; do publier_bundle "essais-j5/$c" "$T/$c.json"; done

  echo "## cosign v3.1.4 : bundle dans un dépôt séparé, --use-signed-timestamps et racine de confiance du TSA"
  printf '%s\n' "valide|$DEPOT_BUNDLES|0" "aucun bundle|essais-j5/aucun|1" "bundle sans jeton|essais-j5/sans-jeton|1" \
    "jeton altéré|essais-j5/jeton-altere|1" "jeton d'une autre signature|essais-j5/autre-signature|1" "jeton d'une TSA étrangère|essais-j5/tsa-etrangere|1" \
    > "$T/cas.txt"
  while IFS='|' read -r c r e; do
    if verif_cosign "$r"; then k=0; else k=1; fi
    m=$({ grep -m1 '^Error: ' "$T/cosign.out" || true; } | sed -e 's/^Error: //' -e 's/^no matching attestations: $/no matching attestations (aucun bundle)/' \
      -e 's/.*threshold not met for verified signed timestamps: \(0 < 1\); error: %!w(<nil>)/aucun jeton vérifié (\1)/' \
      -e 's/.*threshold not met for verified signed timestamps: \(0 < 1\); error: /aucun jeton vérifié (\1) : /' | cut -c1-200)
    if [ "$k" = "$e" ]; then echo "OK   $c : $([ "$k" = 0 ] && echo accepté || echo "refusé ($m)")"
    else echo "KO   $c : $([ "$k" = 0 ] && echo accepté || echo refusé) ($m)" >&2; cat "$T/cosign.out" >&2; exit 1; fi
  done < "$T/cas.txt"

  echo "## cosign v3.1.4 : chemin historique (tag .att de Chains, sans jeton), --use-signed-timestamps et chaîne du TSA"
  if cosign verify-attestation --key "$R/chains-cle-publique.pem" --insecure-ignore-tlog --use-signed-timestamps --new-bundle-format=false \
      --timestamp-certificate-chain "$P/tsa-chaine.pem" --type slsaprovenance1 --registry-cacert "$P/ca-poc.crt" \
      "$REG_HOTE/builds/essai-signature@$APP_DIGEST" > "$T/cosign.out" 2>&1; then
    echo "CONSTAT attestation sans jeton ACCEPTÉE : ce chemin ne peut pas exiger le jeton (VerifyRFC3161Timestamp renvoie nil sans jeton)"
  else echo "KO   chemin historique refusé, contrairement au code lu" >&2; cat "$T/cosign.out" >&2; exit 1; fi

  echo "## Kyverno 1.19.2 (CLI ; même code de vérification qu'à l'admission, parité mesurée en J6) : attestor à clé, insecureIgnoreTlog"
  echo "bundle valide, sans tsaCertChain (témoin)     : $(verif_kyverno "$DEPOT_BUNDLES")"
  echo "bundle valide, tsaCertChain du TSA            : $(verif_kyverno "$DEPOT_BUNDLES" "$P/tsa-chaine.pem")"
  echo "bundle sans jeton, tsaCertChain du TSA        : $(verif_kyverno essais-j5/sans-jeton "$P/tsa-chaine.pem")"
  echo "aucun bundle, tsaCertChain du TSA             : $(verif_kyverno essais-j5/aucun "$P/tsa-chaine.pem")"
  echo "chemin historique (.att), sans tsaCertChain   : $(verif_kyverno "")"
  motif_kyverno 'image verification failed error="[^"]*"'
  ivpol "$DEPOT_BUNDLES" "$P/tsa-chaine.pem" > "$T/ivpol.yaml"
  motif_kyverno 'evaluation returned an internal error[^"]*error="[^"]*"'
}

lancer tsa J5 "$@"
