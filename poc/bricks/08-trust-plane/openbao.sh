#!/usr/bin/env bash
# Brique 08, jalon J3 : OpenBao 2.7.2 sur sc-confiance, clé de provenance Transit non exportable, authentification JWT
# réservée au compte de service de Chains (accord du propriétaire du 29/10/2026).
#   image          signature sans clé de l'index vérifiée par identité exacte (workflow, tag, commit, déclencheur),
#                  copie dans Zot avec ses referrers (oras cp -r), signature revérifiée depuis Zot ; identité voisine refusée
#   deployer       certificat de la CA du PoC (openbao.openbao.svc.cluster.local), StatefulSet sur le nœud de confiance
#                  (openbao/openbao.yaml), configuration (openbao/config.hcl : raft, TLS 1.3, audit déclaré)
#   initialiser    initialisation (1 part) lue dans OpenBao (sys/init), descellement, audit actif vérifié avant toute
#                  configuration ; jeton root et clé de descellement en 0600 sur l'hôte, un secret par fichier
#   configurer     Transit (clé chains : ecdsa-p256, exportable=false, allow_plaintext_backup=false), politique
#                  chains-signature, méthode JWT (clé publique de l'émetteur des comptes de service, kid recoupé)
#   essais         signature par le compte de service de Chains (vérifiée sur l'hôte par openssl) ; refus : autre compte,
#                  autre audience, export, clé rendue exportable, sauvegarde, réseau depuis sc-build ; trace de l'audit
#   deverrouiller  descellement après un redémarrage (OpenBao redémarre scellé : Chains ne peut plus signer)
#   temoin         avant un redémarrage : message signé par la clé chains, empreinte de la clé publique complète
#   controle       après : même empreinte, même version, toujours non exportable, signature témoin vérifiée par openssl
#   redemarrage    pod supprimé : il revient scellé, non prêt et sans endpoint ; descellement ; controle
#   cle            clé publique de la clé chains dans resultats/chains-cle-publique.pem (vérification cosign sur l'hôte)
# Aucun secret en argument de commande : le jeton root et la clé de descellement passent par l'entrée standard de
# kubectl exec (la ligne de commande d'exec figure dans l'URL, donc dans l'audit de l'API).
#
# Usage (racine du dépôt) : mise run confiance:openbao -- <étape>…   (journal : resultats/openbao-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
AMONT=ghcr.io/openbao/openbao
BAO_INDEX=sha256:5046911075e137e154ce49ab051502f4ec7cf367d484ae4a4dce665d9b90561f   # 2.7.2, index multi-plateforme signé
BAO_AMD64=sha256:a78eb12a9fc7a3ebb4bec1724e2bdd6a28e33394820641d061166919a3f1866b
BAO_COMMIT=9e0a0d3c3504a0a00b45e61355afac5e35c78379   # tag v2.7.2
BAO_ID=https://github.com/openbao/openbao/.github/workflows/release-images.yml@refs/tags/v2.7.2
MIROIR=amont/openbao/openbao
IMAGE=$REG/$MIROIR@$BAO_INDEX
SUJET=system:serviceaccount:tekton-chains:tekton-chains-controller
MESSAGE="Brique 08, J3 : signature Transit par le compte de service de Chains"
trap 'rm -rf "$W/openbao" "$W/refus.out"' EXIT   # copies de secrets et jetons d'essai, même en cas d'échec
B=$W/openbao
(umask 077 && mkdir -p "$B")

bao_status() { kubectl exec -n openbao openbao-0 -- bao status -format=json 2>/dev/null || true; }   # code 2 si scellé
racine() { # script sh sur l'entrée standard, exécuté dans openbao-0 avec le jeton root lu sur l'entrée standard
  { tr -d '\n' < "$S/openbao-root.token"; echo; cat; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c 'read -r BAO_TOKEN && export BAO_TOKEN && exec sh -s'
}
verifier_signature() { # référence [options cosign…]
  cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity "$BAO_ID" \
    --certificate-github-workflow-sha "$BAO_COMMIT" --certificate-github-workflow-trigger release "$@" > "$B/cosign.json" 2> "$B/cosign.err"
}
attendre_pret() {
  for _ in $(seq 60); do
    [ "$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ] && return 0
    sleep 2
  done
  echo "KO   openbao-0 pas prêt" >&2; return 1
}
desceller() {
  local st
  st=$(bao_status)
  if [ "$(jq -r .sealed <<<"$st")" = true ]; then
    tr -d '\n' < "$S/openbao-descellement.b64" | kubectl exec -i -n openbao openbao-0 -- bao write -format=json sys/unseal key=- \
      | jq -c '(.data // .) | {sealed, t, n, progress}'
  fi
  attendre_pret
  bao_status | jq -c '{initialized, sealed, version, storage_type, ha_enabled}'
}

etape_image() {
  local tag
  tag=$(crane digest "$AMONT:2.7.2")
  echo "$AMONT:2.7.2 → $tag $([ "$tag" = "$BAO_INDEX" ] && echo '(= digest épinglé)' || echo "(≠ digest épinglé $BAO_INDEX)")"
  crane manifest "$AMONT@$BAO_INDEX" | jq -e --arg d "$BAO_AMD64" '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest == $d' >/dev/null \
    && echo "OK   l'index signé référence le manifeste linux/amd64 $BAO_AMD64" || { echo "KO   manifeste amd64" >&2; exit 1; }
  verifier_signature "$AMONT@$BAO_INDEX" && echo "OK   signature de $AMONT@$BAO_INDEX : $BAO_ID, commit $BAO_COMMIT, déclencheur release" \
    || { cat "$B/cosign.err" >&2; exit 1; }
  grep -E '^  - ' "$B/cosign.err" || true
  refus "signature avec une identité voisine (tag v2.7.1)" "no matching CertificateIdentity|none of the expected identities" \
    cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      --certificate-identity "${BAO_ID%v2.7.2}v2.7.1" "$AMONT@$BAO_INDEX"
  auth_zot "$B/zot.json"
  oras cp -r "$AMONT@$BAO_INDEX" "$REG_HOTE/$MIROIR@$BAO_INDEX" --to-ca-file "$P/ca-poc.crt" --to-registry-config "$B/zot.json" | tail -2
  verifier_signature --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$MIROIR@$BAO_INDEX" \
    && echo "OK   signature revérifiée sur la copie de Zot : $REG/$MIROIR@$BAO_INDEX" || { cat "$B/cosign.err" >&2; exit 1; }
  echo "referrers dans Zot : $(oras discover --ca-file "$P/ca-poc.crt" --format json "$REG_HOTE/$MIROIR@$BAO_INDEX" | jq -r '[.referrers[]?.artifactType] | group_by(.) | map("\(.[0]) ×\(length)") | join(", ")')"
}

etape_deployer() {
  certificat openbao DNS:openbao.openbao.svc.cluster.local
  local empreinte
  empreinte=$(cat "$here/openbao/config.hcl" "$P/openbao.crt" | sha256sum | cut -c1-16)
  sed -e "s#@IMAGE@#$IMAGE#" "$here/openbao/openbao.yaml" \
    | awk -v e="$empreinte" '{print} /^  template:$/ {t=1} t && /^    metadata:$/ {print "      annotations:\n        poc/configuration: \"" e "\""; t=0}' \
    | kubectl apply --server-side -f -
  kubectl create configmap openbao-config -n openbao --from-file=config.hcl="$here/openbao/config.hcl" --dry-run=client -o yaml | kubectl apply --server-side -f -
  kubectl create secret generic openbao-tls -n openbao --from-file=tls.crt="$P/openbao.crt" --from-file=tls.key="$S/openbao.key" \
    --from-file=ca.crt="$P/ca-poc.crt" --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  echo "secret openbao-tls appliqué (clé lue sur l'entrée standard de kubectl, sans annotation last-applied)"
  for _ in $(seq 90); do
    [ "$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && break
    sleep 2
  done
  kubectl get pod -n openbao openbao-0 -o wide
  kubectl get pod -n openbao openbao-0 -o jsonpath='{.status.containerStatuses[0].imageID}{"\n"}'
  kubectl get pvc -n openbao
  kubectl exec -n openbao openbao-0 -- sh -c 'id; ls -ld /openbao/data; bao version'
}

etape_initialiser() {
  local st
  st=$(bao_status)
  echo "état : $(jq -c '{initialized, sealed}' <<<"$st")"
  if [ "$(jq -r .initialized <<<"$st")" = false ]; then
    (umask 077 && kubectl exec -n openbao openbao-0 -- bao operator init -key-shares=1 -key-threshold=1 -format=json > "$B/init.json")
    (umask 077
     jq -j .root_token "$B/init.json" > "$S/openbao-root.token"
     jq -j '.unseal_keys_b64[0]' "$B/init.json" > "$S/openbao-descellement.b64"
     jq -j '.unseal_keys_hex[0]' "$B/init.json" > "$S/openbao-descellement.hex")
    echo "initialisé : 1 part, seuil 1 ; $(jq -r '.unseal_keys_b64 | length' "$B/init.json") clé de descellement et jeton root en 0600 sur l'hôte"
    rm -f "$B/init.json"
  elif [ ! -s "$S/openbao-root.token" ]; then
    echo "KO   OpenBao initialisé mais jeton root absent de l'hôte" >&2; exit 1
  fi
  desceller
  # L'audit déclaré doit être actif avant toute configuration : sinon, rechargement (SIGHUP) puis nouvelle vérification.
  if ! racine <<<'bao audit list -format=json' | jq -e 'has("fichier/")' >/dev/null; then
    echo "audit absent après le descellement : SIGHUP"
    kubectl exec -n openbao openbao-0 -- kill -HUP 1
    sleep 2
  fi
  racine <<<'bao audit list -format=json' | jq -c 'to_entries[] | {chemin: .key, type: .value.type, fichier: .value.options.file_path}'
  racine <<<'bao audit list -format=json' | jq -e 'has("fichier/")' >/dev/null && echo "OK   audit actif avant la configuration" || { echo "KO   audit inactif" >&2; exit 1; }
  kubectl exec -n openbao openbao-0 -- ls -l /openbao/data
}

etape_configurer() {
  local iss pub kid kid_calc
  iss=$(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)
  kubectl get --raw /openid/v1/jwks > "$B/jwks.json"
  [ "$(jq '.keys | length' "$B/jwks.json")" = 1 ] || { echo "KO   le JWKS ne contient pas une seule clé" >&2; exit 1; }
  sur sc-confiance "sudo openssl pkey -in /var/lib/rancher/k3s/server/tls/service.key -pubout" > "$B/sa.pub"
  kid=$(jq -r '.keys[0].kid' "$B/jwks.json")
  kid_calc=$(openssl pkey -pubin -in "$B/sa.pub" -outform DER | openssl dgst -sha256 -binary | basenc --base64url | tr -d '=')
  [ "$kid" = "$kid_calc" ] && echo "OK   clé publique de service.key : kid $kid = celui du JWKS (émetteur $iss)" || { echo "KO   kid $kid_calc ≠ $kid" >&2; exit 1; }
  racine <<EOF | jq -c 'if .data then .data else . end | if has("keys") then {name, type, exportable, allow_plaintext_backup, deletion_allowed, latest_version} elif has("bound_subject") then {bound_audiences, bound_subject, user_claim, token_policies, token_no_default_policy, token_type, token_ttl, token_max_ttl} else {bound_issuer, cles: (.jwt_validation_pubkeys | length)} end'
set -eu
bao secrets list -format=json | grep -q '"transit/"' || bao secrets enable transit >&2
bao read transit/keys/chains >/dev/null 2>&1 || bao write -f transit/keys/chains type=ecdsa-p256 exportable=false allow_plaintext_backup=false >&2
bao read -format=json transit/keys/chains
bao policy write chains-signature - >&2 <<'POL'
$(cat "$here/openbao/chains-signature.hcl")
POL
bao auth list -format=json | grep -q '"jwt/"' || bao auth enable jwt >&2
bao write auth/jwt/config bound_issuer="$iss" jwt_validation_pubkeys="$(cat "$B/sa.pub")" >&2
bao write auth/jwt/role/tekton-chains role_type=jwt user_claim=sub bound_audiences=openbao bound_subject=$SUJET \
  token_policies=chains-signature token_no_default_policy=true token_type=batch token_ttl=5m token_max_ttl=5m >&2
bao read -format=json auth/jwt/role/tekton-chains
bao read -format=json auth/jwt/config
EOF
  racine <<<'bao policy read chains-signature' | grep -v '^#'
}

pod_essai() { # nom espace compte zone jeton(projete|defaut|aucun)
  local tol="" jeton="" vol="" auto=false
  [ "$4" = build ] && tol='  tolerations: [{key: zone, operator: Equal, value: build, effect: NoSchedule}]'
  case $5 in
    projete) vol='  - {name: jeton, projected: {sources: [{serviceAccountToken: {audience: openbao, expirationSeconds: 600, path: token}}]}}'
             jeton='    - {name: jeton, mountPath: /var/run/secrets/openbao}' ;;
    defaut) auto=true ;;
  esac
  cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $1, namespace: $2}
spec:
  serviceAccountName: $3
  automountServiceAccountToken: $auto
  nodeSelector: {zone: $4}
$tol
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 100, runAsGroup: 1000, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: client
    image: $IMAGE
    command: [/bin/sh, /essai/essai.sh]
    env:
    - {name: BAO_ADDR, value: "https://openbao.openbao.svc.cluster.local:8200"}
    - {name: BAO_CACERT, value: /essai/ca/ca.crt}
    - {name: BAO_CLIENT_TIMEOUT, value: 8s}
    - {name: HOME, value: /tmp}
    - {name: H_B64, value: "$(cat "$B/h.b64")"}
$([ "$5" = defaut ] && echo '    - {name: JETON, value: /var/run/secrets/kubernetes.io/serviceaccount/token}')
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    volumeMounts:
    - {name: essai, mountPath: /essai}
    - {name: ca, mountPath: /essai/ca}
    - {name: tmp, mountPath: /tmp}
$jeton
  volumes:
  - {name: essai, configMap: {name: j3-script}}
  - {name: ca, configMap: {name: ca-poc}}
  - {name: tmp, emptyDir: {}}
$vol
---
EOF
}

etape_essais() {
  local debut sig p
  debut=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s' "$MESSAGE" > "$B/message"
  openssl dgst -sha256 -binary "$B/message" | base64 -w0 > "$B/h.b64"
  kubectl delete ns j3-essais --ignore-not-found --wait=true >/dev/null
  kubectl delete pod -n tekton-chains chains autre-compte autre-audience --ignore-not-found --wait=true >/dev/null
  kubectl apply --server-side -f "$here/openbao/essais.yaml" >/dev/null
  for n in tekton-chains j3-essais; do
    kubectl create configmap ca-poc -n "$n" --from-file=ca.crt="$P/ca-poc.crt" --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  done
  { pod_essai chains tekton-chains tekton-chains-controller confiance projete
    pod_essai autre-compte tekton-chains autre confiance projete
    pod_essai autre-audience tekton-chains tekton-chains-controller confiance defaut; } | grep -v '^$' | kubectl apply -f - >/dev/null
  for p in chains autre-compte autre-audience; do
    kubectl wait -n tekton-chains --for=jsonpath='{.status.phase}'=Succeeded "pod/$p" --timeout=120s >/dev/null
    kubectl logs -n tekton-chains "$p" > "$B/$p.log"
  done
  # Trace réseau : paquets du pod de sc-build refusés par la NetworkPolicy d'OpenBao, journalisés par kube-router
  # (NFLOG, groupe 100) sur sc-confiance. tcpdump ne filtre pas sur NFLOG : on garde ensuite les sources de sc-build.
  local cidr tcpdump
  cidr=$(kubectl get node sc-build -o jsonpath='{.spec.podCIDR}')
  sur sc-confiance "sudo timeout 40 tcpdump -i nflog:100 -nn -l 2>&1" > "$B/nflog.txt" &
  tcpdump=$!
  sleep 2
  attendre_sa j3-essais
  pod_essai reseau j3-essais default build aucun | grep -v '^$' | kubectl apply -f - >/dev/null
  kubectl wait -n j3-essais --for=jsonpath='{.status.phase}'=Succeeded pod/reseau --timeout=120s >/dev/null
  kubectl logs -n j3-essais reseau > "$B/reseau.log"
  wait "$tcpdump" || true

  echo "## compte de service de Chains (audience openbao), sur sc-confiance"
  echo "OpenBao joint au bout de $(sed -n 's/^JOINT_AU_ESSAI|//p' "$B/chains.log") essai(s) (synchronisation de kube-router)"
  sed -n '/^CONNEXION/,/^SIGNATURE/p' "$B/chains.log" | grep -v -E '^(SIGNATURE|--$)' | tr -s ' ' | paste -sd' '
  grep -q '^CONNEXION_ACCEPTEE' "$B/chains.log" || { cat "$B/chains.log" >&2; exit 1; }
  sig=$(sed -n 's/^SIGNATURE|vault:v1://p' "$B/chains.log")
  [ -n "$sig" ] || { echo "KO   pas de signature" >&2; cat "$B/chains.log" >&2; exit 1; }
  base64 -d <<<"$sig" > "$B/sig.der"
  sed -n '/^CLE_DEBUT$/,/^CLE_FIN$/p' "$B/chains.log" | sed '1d;$d' | jq -r '.data.keys["1"].public_key' > "$B/chains.pub"
  echo "clé publique : $(openssl pkey -pubin -in "$B/chains.pub" -noout -text | sed -n 's/^\(Public-Key\|ASN1 OID\|NIST CURVE\): */\1 /p' | paste -sd' ')"
  openssl dgst -sha256 -verify "$B/chains.pub" -signature "$B/sig.der" "$B/message" \
    && echo "OK   signature Transit (prehashed sha2-256, comme le client hashivault de Chains) vérifiée par openssl sur l'hôte"
  printf '%s.' "$MESSAGE" > "$B/message-modifie"
  refus "même signature sur un message modifié" "Verification failure" openssl dgst -sha256 -verify "$B/chains.pub" -signature "$B/sig.der" "$B/message-modifie"
  local l
  while IFS='|' read -r etat lib motif; do
    if [ "$etat" = REFUSE ] && grep -E 'Code: 403|permission denied' >/dev/null <<<"$motif"; then
      echo "OK   jeton de Chains, $lib : refusé ($(grep -oE 'Code: 403' <<<"$motif") ; $(grep -oE 'permission denied' <<<"$motif" | head -1))"
    else echo "KO   jeton de Chains, $lib : $etat $motif" >&2; exit 1; fi
  done < <(grep -E '^(REFUSE|ACCEPTE)\|' "$B/chains.log")
  for p in autre-compte:"sub|subject" autre-audience:"aud|audience"; do
    l=$(grep '^CONNEXION' "$B/${p%%:*}.log")
    if [[ $l == CONNEXION_REFUSEE* ]] && grep -iE "${p#*:}" >/dev/null <<<"$l"; then echo "OK   ${p%%:*} : connexion refusée (${l#CONNEXION_REFUSEE|})"
    else echo "KO   ${p%%:*} : $l" >&2; exit 1; fi
  done
  l=$(cat "$B/reseau.log")
  [[ $l == INJOIGNABLE* ]] && echo "OK   pod de j3-essais sur sc-build : OpenBao injoignable (${l#INJOIGNABLE|})" || { echo "KO   réseau : $l" >&2; exit 1; }
  echo "## NFLOG (groupe 100) sur sc-confiance pendant l'essai réseau : source $cidr (pods de sc-build)"
  grep -E "IP ${cidr%.0/24}\.[0-9]+\.[0-9]+ > [0-9.]+\.8200: Flags \[S\]" "$B/nflog.txt" | head -3
  grep -E 'packets (captured|received)' "$B/nflog.txt"
  grep -E "IP ${cidr%.0/24}\.[0-9]+\.[0-9]+ > [0-9.]+\.8200: Flags \[S\]" "$B/nflog.txt" >/dev/null \
    && echo "OK   SYN du pod de sc-build vers OpenBao journalisés comme refusés" || { echo "KO   aucune trace NFLOG" >&2; exit 1; }

  echo "## jeton root : la clé reste non exportable"
  racine <<'EOF' > "$B/racine.txt" 2>&1 || true
bao read transit/export/signing-key/chains
bao read transit/backup/chains
EOF
  grep -E 'Code:|\* ' "$B/racine.txt" | tr -s '\t ' ' '
  grep -E 'not exportable|exportable' "$B/racine.txt" >/dev/null && grep -iE 'plaintext backup|backup' "$B/racine.txt" >/dev/null \
    && echo "OK   export et sauvegarde en clair refusés même au jeton root" || { echo "KO   racine" >&2; exit 1; }

  echo "## audit d'OpenBao depuis $debut (connexions, signatures, refus)"
  kubectl exec -n openbao openbao-0 -- cat /openbao/data/audit.log > "$B/audit.log"
  jq -c --arg d "$debut" 'select(.type == "response" and .time >= $d and (.request.path | test("^(auth/jwt/login|transit/|sys/mounts|auth/token/lookup)")))
    | {time: .time[11:19], chemin: .request.path, op: .request.operation, compte: (.auth.display_name // .auth.metadata.role // null),
       politiques: (.auth.policies // null), erreur: (.error // .response.data.error // null)}' "$B/audit.log"
  echo "valeurs sensibles en HMAC dans l'audit : $(jq -r --arg d "$debut" 'select(.type == "request" and .time >= $d and .request.path == "auth/jwt/login") | .request.data.jwt' "$B/audit.log" | head -1 | cut -c1-12)…"
  kubectl delete ns j3-essais --wait=false >/dev/null
  kubectl delete pod -n tekton-chains chains autre-compte autre-audience --wait=false >/dev/null
  kubectl delete -n tekton-chains configmap/j3-script configmap/ca-poc serviceaccount/autre --ignore-not-found >/dev/null
}

etape_deverrouiller() {
  desceller
}

T=$W/openbao-temoin   # message, signature et clé publique (rien de secret) conservés entre temoin et controle
cle_chains() { racine <<<'bao read -format=json transit/keys/chains' | jq '.data | {latest_version, exportable, allow_plaintext_backup, public_key: .keys["1"].public_key}'; }

etape_cle() { # clé publique de la clé chains (rien de secret), pour cosign sur l'hôte : resultats/chains-cle-publique.pem
  cle_chains > "$B/cle.json"
  jq -r .public_key "$B/cle.json" > "$R/chains-cle-publique.pem"
  echo "clé publique chains : $(jq -c 'del(.public_key)' "$B/cle.json"), empreinte $(sha256sum < "$R/chains-cle-publique.pem" | cut -c1-16)…"
}

etape_temoin() {
  rm -rf "$T" && mkdir -p "$T"
  printf 'Brique 08, J3 : témoin de redémarrage, %s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$T/message"
  cle_chains > "$T/cle.json"
  jq -r .public_key "$T/cle.json" > "$T/chains.pub"
  racine <<EOF | sed 's/^vault:v1://' | base64 -d > "$T/sig.der"
bao write -field=signature transit/sign/chains/sha2-256 input=$(openssl dgst -sha256 -binary "$T/message" | base64 -w0) prehashed=true
EOF
  openssl dgst -sha256 -verify "$T/chains.pub" -signature "$T/sig.der" "$T/message" >/dev/null
  echo "témoin : message signé par la clé chains ; empreinte de la clé publique $(sha256sum < "$T/chains.pub" | cut -c1-16)… ; $(jq -c '{latest_version, exportable}' "$T/cle.json")"
}

etape_controle() {
  [ -s "$T/sig.der" ] || { echo "KO   pas de témoin (étape temoin)" >&2; exit 1; }
  cle_chains > "$B/cle.json"
  jq -r .public_key "$B/cle.json" > "$B/chains.pub"
  cmp -s "$T/chains.pub" "$B/chains.pub" && echo "OK   clé publique identique (empreinte $(sha256sum < "$B/chains.pub" | cut -c1-16)…)" || { echo "KO   clé publique différente" >&2; exit 1; }
  jq -e '.latest_version == 1 and .exportable == false and .allow_plaintext_backup == false' "$B/cle.json" >/dev/null \
    && echo "OK   $(jq -c 'del(.public_key)' "$B/cle.json")" || { echo "KO   $(jq -c 'del(.public_key)' "$B/cle.json")" >&2; exit 1; }
  openssl dgst -sha256 -verify "$B/chains.pub" -signature "$T/sig.der" "$T/message" >/dev/null \
    && echo "OK   signature témoin d'avant le redémarrage vérifiée avec la clé relue après : même clé privée" || { echo "KO   signature témoin" >&2; exit 1; }
}

etape_redemarrage() {
  etape_temoin
  kubectl delete pod -n openbao openbao-0 --wait=true >/dev/null
  for _ in $(seq 90); do
    [ "$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && break
    sleep 2
  done
  sleep 6   # au moins une sonde de disponibilité
  local st pret ep
  st=$(bao_status | jq -c '{initialized, sealed}')
  pret=$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  ep=$(kubectl get endpointslice -n openbao -l kubernetes.io/service-name=openbao -o json | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length')
  echo "après suppression du pod : $st, Ready=$pret, endpoints prêts du Service : $ep"
  [ "$(jq -r .sealed <<<"$st")" = true ] && [ "$pret" = False ] && [ "$ep" = 0 ] \
    && echo "OK   OpenBao redémarre scellé, non prêt, retiré du Service" || { echo "KO   état après redémarrage" >&2; exit 1; }
  desceller
  echo "endpoints prêts du Service : $(kubectl get endpointslice -n openbao -l kubernetes.io/service-name=openbao -o json | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length')"
  etape_controle
}

lancer openbao J3 "$@"
