#!/usr/bin/env bash
# Banc A1 : embarque sample-app dans Konflux depuis Forgejo, par le chemin natif (doc
# Konflux « Onboard Application with Kubernetes Manifests », build-service en mode Forgejo).
#
# 1. Images de base UBI du Containerfile : signature GPG « simple signing » de Red Hat
#    (lookaside access.redhat.com), clé de release 2 dont l'empreinte est publiée sur
#    access.redhat.com/security/team/key ; la signature doit citer le digest épinglé.
# 2. Dépôt Forgejo banc/sample-app : sources de poc/sample-app et Containerfile du banc,
#    commit à auteur et date fixes.
# 3. Konflux : identifiants SCM (secret basic-auth, label scm.host = hôte du dépôt),
#    URL de webhook vue depuis Forgejo (CR Konflux, buildService.spec.webhookURLs :
#    PaC publié sur 127.0.0.1:8180), Application et Component annoté configure-pac.
#    Le build-service crée alors le Repository PaC, le webhook signé dans Forgejo et une
#    PR qui ajoute les PipelineRuns .tekton/.
#
# Usage (racine du dépôt, Konflux et Forgejo démarrés) : mise run konflux:onboarder
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
R=$here/resultats
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
export KUBECONFIG=$HOME/.kube/supply-chain-poc-konflux.yaml
F=${FORGEJO_DIR:-$HOME/.cache/supply-chain-poc/forgejo}
W=${WORKDIR:-$HOME/.cache/supply-chain-poc/konflux/onboarding}
HOST=forgejo.banc-a1.svc.cluster.local
TENANT=default-tenant
IMAGE=registry-service.kind-registry/$TENANT/sample-app   # nom couvert par le certificat du registre interne
RH_FPR=567E347AD0044ADE55BA8A5F199E2F91FD431D51
gw=$(docker network inspect kind --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 -E '^[0-9.]+$')
base=https://$gw:3000

rm -rf "$W"
mkdir -p "$W/gnupg" "$R"
chmod 700 "$W" "$W/gnupg"
exec > >(sed -u "s#$HOME#~#g" | tee "$R/onboarding.log") 2>&1
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; exit 1; }
echo "# onboarder.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 1. Images de base.
export GNUPGHOME=$W/gnupg
curl -fsSL -o "$W/rh-key2.txt" https://access.redhat.com/security/data/fd431d51.txt
curl -fsSL -o "$W/rh-keys.html" https://access.redhat.com/security/team/key
sed 's/<[^>]*>/ /g' "$W/rh-keys.html" | grep -qF "$(sed 's/\(....\)/\1 /g; s/ $//' <<<"$RH_FPR")" \
  && ok "clé de release Red Hat 2 : empreinte $RH_FPR publiée sur access.redhat.com/security/team/key" || ko "empreinte Red Hat absente de la page"
gpg -q --import "$W/rh-key2.txt" 2>/dev/null
grep -oE 'registry\.access\.redhat\.com/[^ @]+@sha256:[0-9a-f]{64}' "$here/sample-app/Containerfile" | while read -r img; do
  n=${img#registry.access.redhat.com/}; n=${n%@*}; d=${img#*@}
  curl -fsS -o "$W/sig" "https://access.redhat.com/webassets/docker/content/sigstore/$n@${d/:/=}/signature-1"
  j=$(gpg --status-fd 3 --decrypt "$W/sig" 2>/dev/null 3>"$W/sig.status")
  [ "$(awk '/VALIDSIG/ {print $NF}' "$W/sig.status")" = "$RH_FPR" ] && [ "$(jq -r '.critical.image."docker-manifest-digest"' <<<"$j")" = "$d" ] \
    && ok "$n@$d : signature Red Hat ($(jq -r '.critical.identity."docker-reference"' <<<"$j"))" || ko "$n@$d : signature refusée"
done

# 2. Dépôt Forgejo.
umask 077
printf 'Authorization: token %s\n' "$(tr -d '\n' < "$F/admin.token")" > "$W/entete"
api() { curl -fsS --cacert "$F/tls/ca.crt" -H @"$W/entete" -H 'Content-Type: application/json' "$@"; }
api -X DELETE "$base/api/v1/repos/banc/sample-app" >/dev/null 2>&1 || true
api -X POST "$base/api/v1/user/repos" -d '{"name": "sample-app", "default_branch": "main", "private": false}' >/dev/null
git -C "$repo" archive HEAD poc/sample-app | tar -x -C "$W" --strip-components=1
cp "$here/sample-app/Containerfile" "$W/sample-app/Containerfile"
GIT_CONFIG_VALUE_0=$(cat "$W/entete")
# Dépôt de test isolé de la configuration git de l'utilisateur (signature de commits, identité).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0 \
  GIT_CONFIG_KEY_1=http.sslCAInfo GIT_CONFIG_VALUE_1="$F/tls/ca.crt"
export GIT_AUTHOR_NAME="banc A1" GIT_AUTHOR_EMAIL=banc@localhost GIT_AUTHOR_DATE=2026-10-29T00:00:00Z
export GIT_COMMITTER_NAME="banc A1" GIT_COMMITTER_EMAIL=banc@localhost GIT_COMMITTER_DATE=2026-10-29T00:00:00Z
git -C "$W/sample-app" init -q -b main
git -C "$W/sample-app" add -A
git -C "$W/sample-app" commit -qm "sample-app (banc A1)"
git -C "$W/sample-app" push -q "$base/banc/sample-app.git" main
ok "dépôt https://$HOST/banc/sample-app : commit $(git -C "$W/sample-app" rev-parse HEAD)"

# 3. Konflux.
tr -d '\n' < "$F/admin.token" > "$W/token"
kubectl delete secret -n "$TENANT" forgejo-banc --ignore-not-found >/dev/null
kubectl create secret generic -n "$TENANT" forgejo-banc --type=kubernetes.io/basic-auth \
  --from-literal=username=banc --from-file=password="$W/token" >/dev/null
kubectl label secret -n "$TENANT" forgejo-banc appstudio.redhat.com/credentials=scm "appstudio.redhat.com/scm.host=$HOST" >/dev/null
rm -f "$W/token"
ok "secret SCM forgejo-banc ($TENANT, scm.host=$HOST)"

# Écarts d'intégration de Konflux v0.2.2 constatés le 29/10/2026, corrigés par configuration :
# a. le Service NodePort de PaC livré par Konflux vise le port 8080 (sondes), alors que
#    PaC v0.50.0 écoute les événements sur 8082, seul port admis par sa NetworkPolicy ;
kubectl patch svc -n tekton-pipelines pipelines-as-code-controller-nodeport --type json \
  -p '[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8082}]' >/dev/null
ok "écart a : NodePort de PaC (30012 → 127.0.0.1:8180) dirigé vers le port 8082"
# b. le contrôleur et le watcher PaC ne montent pas le bundle trusted-ca (Konflux le fait
#    pour Chains et les résolveurs) : l'API Forgejo en HTTPS échoue, et le watcher ne crée
#    pas le secret git du PipelineRun. L'opérateur Tekton ne propage pas les options du
#    TektonConfig vers son objet PaC sur Kubernetes : on pose les deux.
kubectl patch tektonconfig config --type merge --patch-file "$here/k8s/tektonconfig-pac-trusted-ca.yaml" >/dev/null
kubectl patch openshiftpipelinesascode pipelines-as-code --type merge --patch-file "$here/k8s/pac-trusted-ca.json" >/dev/null
for d in controller watcher; do
  for _ in $(seq 1 30); do
    kubectl get deploy -n tekton-pipelines "pipelines-as-code-$d" -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].name}' | grep -qw trusted-ca && break
    sleep 5
  done
  kubectl rollout status -n tekton-pipelines "deploy/pipelines-as-code-$d" --timeout=180s >/dev/null
done
ok "écart b : bundle trusted-ca monté dans le contrôleur et le watcher PaC"
# c. l'URL de webhook vue depuis Forgejo doit être en place avant le Component, sinon le
#    build-service crée un premier webhook vers l'URL interne du cluster, injoignable.
kubectl patch konflux konflux --type merge -p "{\"spec\": {\"buildService\": {\"spec\": {\"webhookURLs\": {\"https://$HOST\": \"http://127.0.0.1:8180\"}}}}}" >/dev/null
for _ in $(seq 1 30); do
  kubectl get cm -n build-service -o json | jq -e --arg h "https://$HOST" '.items[] | select(.metadata.name | startswith("webhook-config")) | .data["webhook-config.json"] | fromjson | has($h)' >/dev/null 2>&1 && break
  sleep 5
done
kubectl rollout status -n build-service deploy/build-service-controller-manager --timeout=180s >/dev/null
ok "écart c : CR Konflux, webhookURLs https://$HOST → http://127.0.0.1:8180, build-service redéployé"
kubectl apply -f - <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: $TENANT
spec:
  displayName: sample-app
---
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  name: sample-app
  namespace: $TENANT
  annotations:
    build.appstudio.openshift.io/request: configure-pac
    git-provider: forgejo
spec:
  application: sample-app
  componentName: sample-app
  containerImage: $IMAGE
  source:
    git:
      revision: main
      url: https://$HOST/banc/sample-app.git
      dockerfileUrl: Containerfile
      context: ./
EOF
# Secret de push du registre interne (Zot authentifié) relié au compte de build : étape de la
# doc Konflux « Build pipeline push secret » ; l'image-controller (Quay) n'est pas déployé.
for _ in $(seq 1 30); do kubectl get sa -n "$TENANT" build-pipeline-sample-app >/dev/null 2>&1 && break; sleep 2; done
kubectl patch -n "$TENANT" serviceaccount build-pipeline-sample-app -p '{"secrets": [{"name": "regcred-internal-registry"}]}' >/dev/null
ok "secret de push regcred-internal-registry relié à build-pipeline-sample-app"
