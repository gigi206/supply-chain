#!/usr/bin/env bash
# Brique 08c : relevés à sec pour la décision S1 (plan des secrets). Lecture seule : API, VM, code amont aux tags épinglés, pages publiques.
# Rien n'est installé ni modifié, aucune valeur de Secret n'est affichée (noms et clés seulement). Ne note aucune grille de l'ADR 0000.
#   usages    qui utilise zot-images, zot-fermetures, zot-chains et forgejo-webhook, et comment ; règle de la zone build ; accès réseau à OpenBao
#   noeuds    comment les nœuds tirent les images depuis Zot : registries.yaml, containerd, lecture anonyme
#   zot       version épinglée, bearer.oidc dans le code, émetteur des jetons vu depuis sc-stockage
#   chains    authentification de Tekton Chains pour pousser, code au tag épinglé
#   buildkit  identifiants de BuildKit : tâche construire-image, code de buildctl
#   webhook   forgejo-webhook : code de l'intercepteur GitHub de Triggers, droits
#   stabilite page de stabilité d'External Secrets, source au tag et page du fournisseur OpenBao
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08c-durcissement/releve-secrets.sh <étape>…   (journal : resultats/releve-secrets-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
racine=$(cd "$here/../../.." && pwd)
b08=$racine/poc/bricks/08-trust-plane
R=$here/resultats
S=$HOME/.cache/supply-chain-poc/08c/sources
E=$HOME/.cache/supply-chain-poc/08c/eso
CIBLES='^(zot-images|zot-fermetures|zot-chains|zot-build|forgejo-webhook)$'
ZOT_TAG=v2.1.22
ZOT_COMMIT=6bbc7e56db2b7a64eee589324efe5813245e3a28
CHAINS_TAG=v0.29.9
CHAINS_COMMIT=89219ea5443fe3164715b9a93f7e6fd16d56b38a
BK_TAG=v0.34.1
BK_COMMIT=f5b59a1f2fb25a0cb7072c398cab9aed7835da4e
TRIGGERS_TAG=v0.37.2
TRIGGERS_COMMIT=799a5fbb9c5856ca758594efef572c1675af83c8
ESO_TAG=v2.14.0
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/supply-chain-poc.yaml}
SSHO=(-n -i "$HOME/.cache/supply-chain-poc/08/ssh/id_ed25519" -o "UserKnownHostsFile=$HOME/.cache/supply-chain-poc/08/ssh/known_hosts"
      -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)
mkdir -p "$R" "$S" "$E"

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)"; exit 1; }; }
vm() { ssh "${SSHO[@]}" "poc@192.168.161.$1" "$2"; }
source_au_tag() { # dépôt tag commit répertoire
  [ -d "$S/$4/.git" ] || git -c advice.detachedHead=false clone -q --depth 1 --branch "$2" "https://github.com/$1.git" "$S/$4" </dev/null
  attendu "$1 au tag $2" "$(git -C "$S/$4" rev-parse HEAD </dev/null)" "$3"
}
lit() { # répertoire expression fichier… : numéros de ligne, chemins relatifs à la source
  local d=$1 x=$2; shift 2
  (cd "$d" && grep -nE -- "$x" "$@") || echo "aucune correspondance : $x"
}

etape_usages() {
  echo "## Secrets : espace/nom, type, clés (noms seulement)"
  kubectl get secrets -A -o json | jq -r --arg c "$CIBLES|^signing-secrets$" '.items[] | select(.metadata.name | test($c))
    | "\(.metadata.namespace)/\(.metadata.name) \(.type) clés=[\((.data // {}) | keys | join(","))]"'
  echo "## comptes de service qui les référencent (secrets, imagePullSecrets)"
  kubectl get sa -A -o json | jq -r --arg c "$CIBLES" '.items[] | (.metadata.namespace + "/" + .metadata.name) as $n
    | (((.secrets // []) + (.imagePullSecrets // [])) | map(.name) | map(select(test($c)))) as $l | select($l | length > 0) | "\($n) : \($l | join(","))"'
  echo "(fin de liste)"
  echo "## compte build de builds"
  kubectl get sa -n builds build -o json | jq -c '{automountServiceAccountToken, secrets: (.secrets // []), imagePullSecrets: (.imagePullSecrets // [])}'
  echo "## pods : imagePullSecrets, volume, projected, env, envFrom"
  kubectl get pods -A -o json | jq -r --arg c "$CIBLES" '
    .items[] | (.metadata.namespace + "/" + .metadata.name) as $p | .spec as $s | "\($p) phase=\(.status.phase) sa=\($s.serviceAccountName)" as $t |
    (($s.imagePullSecrets // [])[] | select(.name | test($c)) | "\($t) imagePullSecrets \(.name)"),
    (($s.volumes // [])[] | select((.secret.secretName // "") | test($c)) | "\($t) volume \(.name) <- \(.secret.secretName)"),
    (($s.volumes // [])[] | select(.projected) | .name as $v | .projected.sources[]? | select((.secret.name // "") | test($c)) | "\($t) projected \($v) <- \(.secret.name)"),
    ((($s.containers // []) + ($s.initContainers // []))[] | .name as $k |
      ((.env // [])[] | select((.valueFrom.secretKeyRef.name // "") | test($c)) | "\($t) env \($k) \(.name) <- \(.valueFrom.secretKeyRef.name)/\(.valueFrom.secretKeyRef.key)"),
      ((.envFrom // [])[] | select((.secretRef.name // "") | test($c)) | "\($t) envFrom \($k) \(.secretRef.name)"))'
  echo "## objets de contrôle qui les citent"
  kubectl get deploy,ds,sts,job,cronjob -A -o json | jq -r '.items[] | (.spec.jobTemplate.spec.template.spec // .spec.template.spec) as $s
    | select($s | tostring | test("zot-images|zot-fermetures|zot-chains|forgejo-webhook")) | "\(.kind) \(.metadata.namespace)/\(.metadata.name) sa=\($s.serviceAccountName)"'
  echo "## objets Tekton du cluster qui les citent"
  kubectl get eventlisteners.triggers.tekton.dev -A -o json | jq -r '.items[] | select(tostring | test("forgejo-webhook")) | "EventListener \(.metadata.namespace)/\(.metadata.name) sa=\(.spec.serviceAccountName)"'
  echo "## tâches signées du dépôt qui les montent"
  lit "$b08" 'secretName: *(zot-|forgejo-webhook)' politique/taches/publier-image.yaml politique/taches/publier-fermeture.yaml politique/chains-zot.yaml politique/declencheurs.yaml
  lit "$b08" 'registry-config' politique/taches/publier-image.yaml politique/taches/publier-fermeture.yaml
  echo "## précédent : identifiants Zot lus dans OpenBao par un conteneur d'initialisation"
  lit "$b08" 'auth/jwt/login|bao read -field=config.json|token revoke' tsa/horodatage-job.yaml
  lit "$b08" 'secrets enable -path=kv|kv/horodatage/zot' tsa.sh
  echo "## jetons et accès à OpenBao de chaque zone"
  kubectl get validatingpolicies.policies.kyverno.io zone-build -o json | jq -r '"zone-build : \(.spec.validationActions | join(",")) ; \(.spec.validations[] | select(.message | test("jeton")) | .message)"'
  kubectl get deploy -n tekton-chains tekton-chains-controller -o json | jq -c '{env: [.spec.template.spec.containers[0].env[] | select(.name == "DOCKER_CONFIG")],
    projected: [.spec.template.spec.volumes[] | select(.projected) | {name, sources: [.projected.sources[].serviceAccountToken | {audience, expirationSeconds}]}]}'
  kubectl get networkpolicy -n openbao -o json | jq -r '.items[] | "NetworkPolicy openbao/\(.metadata.name), espaces admis : \([.spec.ingress[]?.from[]?.namespaceSelector.matchLabels["kubernetes.io/metadata.name"]] | map(select(.)) | unique | join(","))"'
}

etape_noeuds() {
  local h
  echo "## registries.yaml du dépôt"
  grep -v '^#' "$b08/stockage/registries.yaml"
  for h in 11 12 13; do
    echo "## 192.168.161.$h : registries.yaml, champs d'identifiants masqués s'il y en avait"
    vm "$h" 'hostname; sudo sed -E "/^#/d; s/(username|password|auth|identitytoken|token): .*/\1: <masqué>/" /etc/rancher/k3s/registries.yaml;
      echo "lignes d'\''authentification dans le containerd rendu : $(sudo grep -cE "\.auth\]|username|password|identitytoken" /var/lib/rancher/k3s/agent/etc/containerd/config.toml || true)";
      echo "lignes d'\''authentification dans hosts.toml : $(sudo sh -c "grep -cE \"username|password|auth\" /var/lib/rancher/k3s/agent/etc/containerd/certs.d/*/hosts.toml" || true)"'
  done
  echo "## Zot en service : compteurs sur /etc/zot/config.json"
  vm 13 'echo "anonymousPolicy=$(sudo grep -c anonymousPolicy /etc/zot/config.json) htpasswd=$(sudo grep -c "\"htpasswd\"" /etc/zot/config.json) bearer=$(sudo grep -c "\"bearer\"" /etc/zot/config.json || true)"'
  echo "## lecture anonyme depuis chaque nœud, sans identifiant ; adresse forcée, car /etc/hosts de sc-stockage donne 127.0.1.1 et Zot écoute sur .13"
  for h in 11 12 13; do
    vm "$h" 'echo "$(hostname) tags de builds/sample-app : HTTP $(sudo curl -s --cacert /etc/rancher/k3s/ca-poc.crt --resolve sc-stockage.poc.test:5000:192.168.161.13 -o /dev/null -w "%{http_code}" https://sc-stockage.poc.test:5000/v2/builds/sample-app/tags/list)"'
  done
  vm 13 'echo "résolution sur sc-stockage : $(getent hosts sc-stockage.poc.test)"'
  echo "pods de sc-stockage dont une image vient de Zot : $(kubectl get pods -A --field-selector spec.nodeName=sc-stockage -o json | jq '[.items[] | select([.spec.containers[].image] | any(startswith("sc-stockage.poc.test:5000/")))] | length')"
}

etape_zot() {
  local z=$S/zot
  source_au_tag project-zot/zot "$ZOT_TAG" "$ZOT_COMMIT" zot
  echo "## version épinglée"
  lit "$racine" 'project-zot/zot' mise.toml
  lit "$b08" 'ZOT_SHA=' stockage.sh
  vm 13 '/usr/local/bin/zot --version 2>&1 | sed -E "s/.*\"commit\":\"([^\"]*)\".*/commit du binaire : \1/"; sudo sha256sum /usr/local/bin/zot'
  echo "## bearer.oidc au tag $ZOT_TAG"
  lit "$z" 'OIDC BearerOIDCConfigs|workload identity|Issuer string|Audiences \[\]string|ClaimMapping \*|CertificateAuthority(File)? string|SkipIssuerVerification bool' pkg/api/config/config.go
  echo "## découverte : Zot appelle l'émetteur, sans en-tête d'authentification et sans clé statique"
  lit "$z" 'oidc\.NewProvider|oidc\.ClientContext|Issuer|StaticKeySet|NewRemoteKeySet' pkg/api/bearer_oidc.go
  echo "## échange de jeton : seuls l'OIDC et les clés d'API sont reconnus"
  lit "$z" 'func \(b \*BearerAuth\) TokenExchangeHandler|hasWrappedCredentialSecret\(\)|hasAPIKeySecret\(\)|localOIDCTokenOwnerForCredential|IsUpstreamTokenEndpointConfigured|oidcTokenExchangeUnauthorized\(response' pkg/api/bearer_auth.go
  lit "$z" 'func \(a \*AuthConfig\) (HasBearerChallengeConfig|ShouldAdvertiseBearerChallenge)|Bearer\.Realm != "" && a\.Bearer\.Service' pkg/api/config/config.go
  echo "## cohabitation avec htpasswd : en-tête Basic traité directement, défi Bearer dès que realm et service sont posés, mot de passe ordinaire inconnu de l'échange"
  lit "$z" 'case hasBearerAuthorizationHeader|case hasBasicAuthorizationHeader|shouldChallengeWithBearer\(authConfig\)' pkg/api/authn.go
  lit "$z" 'func isLocalCredentialSecret|strings\.HasPrefix\(secret, constants\.APIKeysPrefix\)' pkg/api/token_exchange.go
  echo "## exemples de la documentation au tag $ZOT_TAG"
  (cd "$z/examples" && find . -maxdepth 1 -name 'README-*' | grep -E 'OIDC|COMBINED' || echo "ni README-OIDC-WORKLOAD-IDENTITY ni README-COMBINED-AUTHENTICATION à ce tag")
  echo "## émetteur des jetons du cluster"
  kubectl get --raw /.well-known/openid-configuration | jq -c '{issuer, jwks_uri}'
  kubectl get clusterrolebinding -o json | jq -c '.items[] | select(.roleRef.name == "system:service-account-issuer-discovery") | {name: .metadata.name, subjects}'
  echo "## vu de sc-stockage, où tourne Zot, sans identifiant"
  vm 13 'echo "résolution de kubernetes.default.svc.cluster.local : $(getent hosts kubernetes.default.svc.cluster.local || echo aucune)";
    for u in /.well-known/openid-configuration /openid/v1/jwks; do echo "$u : HTTP $(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 https://192.168.161.11:6443$u)"; done'
  echo "## comptes htpasswd du modèle de configuration"
  jq -r '[.http.accessControl.repositories[] | .policies[]? | .users[]] + .http.accessControl.metrics.users | unique | "\(length) comptes : \(join(" "))"' "$b08/stockage/zot.json"
}

etape_chains() {
  local c=$S/chains v
  source_au_tag tektoncd/chains "$CHAINS_TAG" "$CHAINS_COMMIT" chains
  v=vendor/github.com/google/go-containerregistry/pkg/authn
  echo "## pin"
  lit "$b08" '^chains v|chains v[0-9]' tekton.sh
  echo "## stockage OCI : trousseau"
  lit "$c" 'k8schain\.New|Namespace: +obj|ServiceAccountName: obj|UseMountSecrets|WithAuthFromKeychain' pkg/chains/storage/oci/legacy.go
  echo "## k8schain.New : chaîne des trousseaux"
  lit "$c" 'func New\(|NewMultiKeychain|authn\.DefaultKeychain' "$v/k8schain/k8schain.go"
  echo "## trousseau Kubernetes : ne lit que ce que le compte de service référence"
  lit "$c" 'range opt\.ImagePullSecrets|range sa\.ImagePullSecrets|range sa\.Secrets|Secrets\(opt\.Namespace\)\.Get' "$v/kubernetes/keychain.go"
  echo "## trousseau par défaut : fichier relu à chaque résolution"
  lit "$c" 'func \(dk \*defaultKeychain\) ResolveContext|os\.Getenv\("DOCKER_CONFIG"\)|config\.Load\(|cfg\.Username|cfg\.Password|IdentityToken: |RegistryToken: ' "$v/keychain.go"
  echo "## PoC"
  lit "$b08" 'DOCKER_CONFIG|mountPath: /etc/zot-chains|secretName: zot-chains' politique/chains-zot.yaml
  echo "## signing-secrets, secret du fournisseur x509 de Chains"
  kubectl get secret -n tekton-chains signing-secrets -o json | jq -r '"clés : \((.data // {}) | length)"'
}

etape_buildkit() {
  local b=$S/buildkit t=politique/taches/construire-image.yaml
  source_au_tag moby/buildkit "$BK_TAG" "$BK_COMMIT" buildkit
  echo "## tâche construire-image : sorties et entrées"
  lit "$b08" 'buildctl .* build|--output|--oci-layout|--local ' "$t"
  echo "## mentions d'identifiants dans la tâche"
  lit "$b08" 'DOCKER_CONFIG|secretName|config\.json|registry-config' "$t"
  echo "## réseau"
  kubectl get networkpolicy -n builds construction-sans-sortie -o json | jq -c '{podSelector: .spec.podSelector.matchLabels, policyTypes: .spec.policyTypes, egress: (.spec.egress // [])}'
  echo "## buildctl : identifiants fournis par le client, depuis son fichier Docker"
  lit "$b" 'LoadDefaultConfigFile|NewDockerAuthProvider|LoadAuthConfig' cmd/buildctl/build.go
}

etape_webhook() {
  local t=$S/triggers
  source_au_tag tektoncd/triggers "$TRIGGERS_TAG" "$TRIGGERS_COMMIT" triggers
  echo "## EventListener du PoC"
  lit "$b08" 'secretName: forgejo-webhook|secretKey: secret|name: github' politique/declencheurs.yaml
  echo "## intercepteur GitHub : secret obligatoire, lu par SecretGetter"
  lit "$t" 'SecretRef == nil|SecretGetter\.Get\(ctx, ns, p\.SecretRef\)|ValidateSignature' pkg/interceptors/github/github.go
  echo "## SecretGetter : Secret Kubernetes de l'espace du trigger"
  lit "$t" 'func \(g \*kubeclientSecretGetter\) Get|g\.getter\.Secrets\(triggerNS\)\.Get' pkg/interceptors/secret_getter.go
  echo "## qui le lit dans le cluster"
  echo "core-interceptors, get sur forgejo-webhook : $(kubectl auth can-i get secret/forgejo-webhook -n declencheurs --as=system:serviceaccount:tekton-pipelines:tekton-triggers-core-interceptors)"
  echo "el-forgejo, get sur forgejo-webhook : $(kubectl auth can-i get secret/forgejo-webhook -n declencheurs --as=system:serviceaccount:declencheurs:el-forgejo || true)"
}

etape_stabilite() {
  local p=https://external-secrets.io/latest
  curl -fsSL --proto '=https' --max-time 30 "$p/introduction/stability-support/" -o "$E/stability.html"
  curl -fsSL --proto '=https' --max-time 30 "$p/provider/openbao/" -o "$E/openbao.html"
  env -u GITHUB_TOKEN gh api "repos/external-secrets/external-secrets/contents/docs/introduction/stability-support.md?ref=$ESO_TAG" --jq .content </dev/null | base64 -d > "$E/stability-$ESO_TAG.md"
  (cd "$E" && sha256sum stability.html openbao.html "stability-$ESO_TAG.md")
  echo "## dernière version publiée, hors chart : $(env -u GITHUB_TOKEN gh api 'repos/external-secrets/external-secrets/releases?per_page=8' --jq '[.[] | select(.tag_name | startswith("v"))][0] | .tag_name + " " + .published_at' </dev/null)"
  echo "## source de la page au tag $ESO_TAG : lignes OpenBao et HashiCorp Vault"
  grep -nE '^\| *(\[)?(OpenBao|Hashicorp Vault)' "$E/stability-$ESO_TAG.md" | tr -s ' ' | cut -c1-150
  echo "## page publiée, tableau de stabilité et page du fournisseur"
  python3 -I - "$E/stability.html" "$E/openbao.html" <<'PY'
import html, re, sys
def texte(f):
    t = open(f, encoding="utf8").read()
    t = re.sub(r"<(script|style).*?</\1>", "", t, flags=re.S)
    t = re.sub(r"</t[dh]>|</tr>|</p>|</h\d>|</li>", "\n", t)
    t = html.unescape(re.sub(r"<[^>]+>", "", t))
    return [l.strip() for l in t.splitlines() if l.strip()]
l = texte(sys.argv[1])
d = next(i for i, x in enumerate(l) if x == "Stability")
for n in ("Hashicorp Vault", "OpenBao"):
    i = next(i for i in range(d, len(l)) if l[i] == n)
    print(n, ":", l[i + 1], ",", l[i + 2])
for x in texte(sys.argv[2]):
    if "tested with" in x or "by using the" in x: print(x)
PY
}

for e in "$@"; do
  { echo "# releve-secrets.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/releve-secrets-$e.log"
  [ "${PIPESTATUS[0]}" = 0 ] || exit 1
done
