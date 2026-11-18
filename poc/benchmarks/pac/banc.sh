#!/usr/bin/env bash
# Banc PaC, étape 1 (accord du propriétaire du 18/11/2026 : « Oui, étapes 1 et 2 ») : cluster kind jetable, Tekton Pipelines v1.15.5
# (manifeste vérifié par la brique 08), PaC v0.54.0 (release.k8s.yaml appliqué depuis le disque, images épinglées par digest, rien
# de signé), Forgejo 15.0.11 (mise.toml) en HTTP sur la passerelle du réseau kind, dépôt d'essai neuf. Cas K1 à K8 du README.
# Configuration mesurée : celle qui pourrait tenir E2 (Repository global dans l'espace de PaC, secrets dans cet espace,
# secret-auto-create: false, Repository local sans secret dans essai-pac).
# Isolation : ports sur 127.0.0.1 (8182 vers le contrôleur PaC), Forgejo sur la passerelle de kind, KUBECONFIG dédié,
# nœud plafonné à 6 Gi. Secrets en 0600, passés par fichier, jamais en argument ni dans les journaux.
# Usage (racine du dépôt), une étape par appel, chacune dans son journal neuf :
#   bash poc/benchmarks/pac/banc.sh preparer|cluster|tekton|pac|forgejo|depot|cas|admission|demonter > poc/benchmarks/pac/resultats/banc-<étape>.log 2>&1
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
W=$HOME/.cache/supply-chain-poc/pac/banc
DL=$W/telechargements
F=$W/forgejo
export KUBECONFIG=$HOME/.kube/supply-chain-poc-pac.yaml
CL=banc-pac
NODE=kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0   # notes de release de kind v0.33.0
PIPE=$HOME/.cache/supply-chain-poc/08/telechargements/tekton/pipeline-v1.15.5/github/release.yaml
PIPE_SHA=c2fe5c2ac98af2984f2d58199e81ef2056802f671051744d986ec998ad19ba84                             # tekton.sh de la 08, l. 34
PAC_TAG=v0.54.0
PAC_URL=https://github.com/tektoncd/pipelines-as-code/releases/download/$PAC_TAG/release.k8s.yaml
PAC_SHA=62d6a4ee2ecbd0151ca13913ca9bc346b33df82ee411ecdeb049392b07543f61   # champ digest de l'asset, API de GitHub (relevé du 18/11/2026, 22:43:53 UTC)
CTRL_DIGEST=sha256:a9eefe48ae06ce287e899be3c9b351aaa731928e368fac4c9dc268247ccdf452   # resultats/sante.log (cosign tree)
BUSYBOX=docker.io/rancher/mirrored-library-busybox@sha256:101b4afd76732482eff9b95cae5f94bcf295e521fbec4e01b69c5421f3f3f3e5  # tekton.sh de la 08, l. 39
PORT_PAC=8182 NODEPORT=30082 PORT_FJ=3010 NS=essai-pac PACNS=pipelines-as-code
masque() { sed -E '/jeton|token|password|secret:/I c\[ligne masquée : motif jeton|token|password|secret]' | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g'; }
gw() { docker network inspect kind --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 -E '^[0-9.]+$'; }
fjurl() { echo "http://$(gw):$PORT_FJ"; }
api() { # chemin [options curl] : API de Forgejo avec le jeton administrateur lu dans un fichier d'en-têtes (0600)
  local p=$1; shift; curl -fsS -m 10 -H @"$F/entete-api" -H 'Content-Type: application/json' "$@" "$(fjurl)/api/v1/$p"; }
prs() { kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/sha=$1" --no-headers -o custom-columns=N:.metadata.name 2>/dev/null | grep -c . || true; }
pousser() { # message : commit et push de la copie de travail vers main (identifiants lus dans un fichier par l'assistant git)
  git -C "$W/depot" add -A && git -C "$W/depot" -c user.name=banc -c user.email=banc@localhost -c commit.gpgsign=false commit -q -m "$1"
  git -C "$W/depot" -c credential.helper= -c "credential.helper=!f() { echo username=banc; printf 'password='; cat '$F/admin.token'; echo; }; f" push -q origin HEAD:"${2:-main}"
  git -C "$W/depot" rev-parse HEAD; }
echo "# banc.sh ${1:-?}, début $(date -u +%FT%TZ)"

case "${1:-}" in
preparer)
  [ ! -e "$W" ] || { echo "KO   $W existe déjà" >&2; exit 1; }
  umask 077; mkdir -p "$DL" "$F"
  echo "manifeste Pipelines v1.15.5 : $(sha256sum < "$PIPE" | cut -c1-64) (attendu $PIPE_SHA)"
  [ "$(sha256sum < "$PIPE" | cut -c1-64)" = "$PIPE_SHA" ]
  curl -fsSL --max-time 60 -o "$DL/release.k8s.yaml" "$PAC_URL"
  echo "release.k8s.yaml de PaC $PAC_TAG : $(stat -c %s "$DL/release.k8s.yaml") octets, sha256 $(sha256sum < "$DL/release.k8s.yaml" | cut -c1-64) (74648 octets d'après l'API de GitHub)"
  [ "$(sha256sum < "$DL/release.k8s.yaml" | cut -c1-64)" = "$PAC_SHA" ] || { echo "KO   sha256 différent du digest publié $PAC_SHA" >&2; exit 1; }
  echo "OK   sha256 égal au digest publié par l'API de GitHub"
  cp "$DL/release.k8s.yaml" "$DL/release.k8s.digest.yaml"
  for i in $(grep -oE 'ghcr\.io/tektoncd/pipelines-as-code/[a-z-]+:'"$PAC_TAG" "$DL/release.k8s.yaml" | sort -u); do
    d=$(crane digest "$i"); echo "image $i -> $d"
    case $i in *controller*) [ "$d" = "$CTRL_DIGEST" ] || { echo "KO   contrôleur : digest différent de sante.log" >&2; exit 1; }; echo "OK   contrôleur : digest égal à sante.log";; esac
    sed -i "s|$i|${i%:*}@$d|g" "$DL/release.k8s.digest.yaml"
  done
  echo "release.k8s.yaml épinglé par digest : sha256 $(sha256sum < "$DL/release.k8s.digest.yaml" | cut -c1-64) ; références par tag restantes : $(grep -cE 'image: .*:[^@]*$' "$DL/release.k8s.digest.yaml" || true)"
  echo "images par tag dans le manifeste Pipelines : $(grep -E '^\s*image:|-image' "$PIPE" | grep -vc '@sha256:' || true)"
  ;;
cluster)
  kind get clusters 2>/dev/null | grep -qx "$CL" && { echo "KO   cluster $CL déjà présent" >&2; exit 1; }
  cat > "$W/kind.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "127.0.0.1"
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: $NODEPORT
    hostPort: $PORT_PAC
    listenAddress: "127.0.0.1"
EOF
  t0=$(date +%s)
  kind create cluster --name "$CL" --image "$NODE" --config "$W/kind.yaml" --kubeconfig "$KUBECONFIG" --wait 180s 2>&1 | grep -v '^ *$' | tail -4
  docker update --memory=6g --memory-swap=6g "$CL-control-plane" >/dev/null
  echo "cluster $CL créé en $(( $(date +%s) - t0 )) s ; mémoire plafonnée : $(docker inspect -f '{{.HostConfig.Memory}}' "$CL-control-plane") octets"
  echo "ports publiés : $(docker port "$CL-control-plane" | tr '\n' ' ')"
  kubectl version -o json | jq -r '"client \(.clientVersion.gitVersion) ; serveur \(.serverVersion.gitVersion)"'
  echo "image du nœud : $(docker inspect -f '{{.Config.Image}}' "$CL-control-plane")"
  ;;
tekton)
  t0=$(date +%s)
  kubectl apply --server-side -f "$PIPE" >/dev/null
  kubectl wait -n tekton-pipelines --for=condition=Available deploy --all --timeout=300s >/dev/null
  kubectl wait -n tekton-pipelines-resolvers --for=condition=Available deploy --all --timeout=300s >/dev/null
  echo "Tekton Pipelines prêt en $(( $(date +%s) - t0 )) s"
  for n in tekton-pipelines tekton-pipelines-resolvers; do
    kubectl get pods -n "$n" -o json | jq -r '.items[].status.containerStatuses[] | "  \(.name) \(.imageID)"'
  done
  ;;
pac)
  t0=$(date +%s)
  kubectl apply --server-side -f "$DL/release.k8s.digest.yaml" >/dev/null
  kubectl wait -n "$PACNS" --for=condition=Available deploy --all --timeout=300s >/dev/null
  kubectl patch configmap -n "$PACNS" pipelines-as-code --type merge -p '{"data":{"secret-auto-create":"false"}}' >/dev/null
  kubectl rollout restart -n "$PACNS" deploy/pipelines-as-code-controller deploy/pipelines-as-code-watcher >/dev/null
  kubectl rollout status -n "$PACNS" deploy/pipelines-as-code-controller --timeout=180s >/dev/null
  kubectl rollout status -n "$PACNS" deploy/pipelines-as-code-watcher --timeout=180s >/dev/null
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Service
metadata: {name: pac-controller-nodeport, namespace: $PACNS}
spec:
  type: NodePort
  selector: {app.kubernetes.io/name: controller, app.kubernetes.io/part-of: pipelines-as-code}
  ports: [{name: http-listener, port: 8080, targetPort: 8082, nodePort: $NODEPORT}]
EOF
  echo "PaC prêt en $(( $(date +%s) - t0 )) s ; secret-auto-create = $(kubectl get configmap -n "$PACNS" pipelines-as-code -o jsonpath='{.data.secret-auto-create}')"
  kubectl get pods -n "$PACNS" -o json | jq -r '.items[].status.containerStatuses[] | "  \(.name) \(.imageID)"'
  echo "## K1 : droits sur les Secrets des ClusterRoles de PaC, dans le cluster"
  kubectl get clusterroles -o json | jq -c '.items[] | select(.metadata.name | test("pipeline-as-code|pipelines-as-code")) | {name: .metadata.name, secrets: [.rules[] | select((.resources // []) | index("secrets")) | {verbs, resourceNames}]} | select(.secrets | length > 0)'
  for _ in $(seq 30); do curl -s -o /dev/null -m 3 "http://127.0.0.1:$PORT_PAC/" && break; sleep 2; done
  echo "contrôleur joignable sur 127.0.0.1:$PORT_PAC : HTTP $(curl -s -o /dev/null -w '%{http_code}' -m 3 "http://127.0.0.1:$PORT_PAC/" || true)"
  ;;
forgejo)
  umask 077; mkdir -p "$F/custom/conf" "$F/data" "$F/log"
  g=$(gw); cfg=$F/custom/conf/app.ini
  [ ! -e "$cfg" ] || { echo "KO   $cfg existe déjà" >&2; exit 1; }
  { echo "APP_NAME = Forgejo (banc PaC)"; echo "RUN_MODE = prod"; echo "WORK_PATH = $F"
    echo "[server]"; echo "PROTOCOL = http"; echo "HTTP_ADDR = $g"; echo "HTTP_PORT = $PORT_FJ"; echo "DOMAIN = $g"; echo "ROOT_URL = http://$g:$PORT_FJ/"
    echo "DISABLE_SSH = true"; echo "OFFLINE_MODE = true"; echo "LFS_START_SERVER = false"
    echo "[database]"; echo "DB_TYPE = sqlite3"; echo "PATH = $F/data/forgejo.db"
    echo "[repository]"; echo "ROOT = $F/data/repos"; echo "DEFAULT_BRANCH = main"
    echo "[security]"; echo "INSTALL_LOCK = true"; echo "SECRET_KEY = $(forgejo generate secret SECRET_KEY)"; echo "INTERNAL_TOKEN = $(forgejo generate secret INTERNAL_TOKEN)"
    echo "[oauth2]"; echo "JWT_SECRET = $(forgejo generate secret JWT_SECRET)"
    echo "[service]"; echo "DISABLE_REGISTRATION = true"
    echo "[webhook]"; echo "ALLOWED_HOST_LIST = loopback"; echo "DELIVER_TIMEOUT = 5"
    echo "[mailer]"; echo "ENABLED = false"; echo "[cron.update_checker]"; echo "ENABLED = false"
    echo "[log]"; echo "ROOT_PATH = $F/log"; echo "MODE = file"; echo "LEVEL = Info"; } > "$cfg"
  fg() { forgejo -c "$cfg" -w "$F" "$@"; }
  fg migrate > "$F/log/migrate.out" 2>&1
  fg admin user create --admin --username banc --email banc@localhost --random-password --random-password-length 32 > /dev/null 2>&1
  fg admin user generate-access-token --username banc --token-name banc-pac --scopes all --raw | tr -d '\n' > "$F/admin.token"
  printf 'Authorization: token %s\n' "$(cat "$F/admin.token")" > "$F/entete-api"
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$F/webhook.secret"
  setsid nohup forgejo -c "$cfg" -w "$F" web > "$F/log/web.out" 2>&1 < /dev/null &
  echo $! > "$F/forgejo.pid"
  for _ in $(seq 30); do curl -fsS -m 2 "http://$g:$PORT_FJ/api/healthz" >/dev/null 2>&1 && break; sleep 1; done
  echo "jeton : $(wc -c < "$F/admin.token") octets, sans saut de ligne final : $([ "$(tail -c1 "$F/admin.token" | od -An -tx1 | tr -d ' ')" != 0a ] && echo oui || echo NON)"
  echo "Forgejo vu depuis le conteneur du nœud kind : HTTP $(docker exec "$CL-control-plane" curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$g:$PORT_FJ/api/healthz" || echo échec)"
  echo "Forgejo $(curl -fsS "http://$g:$PORT_FJ/api/v1/version" | jq -r .version) sur $g:$PORT_FJ (pid $(cat "$F/forgejo.pid")) ; fichiers de secrets : $(stat -c '%a' "$F/admin.token" "$F/webhook.secret" "$F/entete-api" | tr '\n' ' ')"
  ;;
depot)
  g=$(gw)
  api user/repos -X POST -d '{"name": "essai", "default_branch": "main", "private": false, "auto_init": true}' | jq -r '"dépôt \(.full_name) créé"'
  python3 -I -c 'import json, sys; print(json.dumps({"type": "gitea", "active": True, "events": ["push", "pull_request"], "config": {"url": sys.argv[1], "content_type": "json", "secret": open(sys.argv[2]).read()}}))' \
    "http://127.0.0.1:$PORT_PAC" "$F/webhook.secret" > "$F/hook.json"
  api repos/banc/essai/hooks -X POST --data-binary @"$F/hook.json" | jq -r '"webhook \(.id) vers \(.config.url) (\(.type), \(.events | join(",")))"'
  kubectl create namespace "$NS" >/dev/null
  kubectl create secret generic -n "$PACNS" forgejo-essai --from-file=token="$F/admin.token" --from-file=webhook.secret="$F/webhook.secret" >/dev/null
  kubectl apply -f - >/dev/null <<EOF
apiVersion: pipelinesascode.tekton.dev/v1alpha1
kind: Repository
metadata: {name: pipelines-as-code, namespace: $PACNS}
spec:
  url: https://pac.global.repo
  git_provider:
    type: gitea
    url: http://$g:$PORT_FJ
    secret: {name: forgejo-essai, key: token}
    webhook_secret: {name: forgejo-essai, key: webhook.secret}
---
apiVersion: pipelinesascode.tekton.dev/v1alpha1
kind: Repository
metadata: {name: essai, namespace: $NS}
spec:
  url: http://$g:$PORT_FJ/banc/essai
  git_provider: {type: gitea, url: http://$g:$PORT_FJ}
EOF
  echo "Repository global $PACNS/pipelines-as-code (secrets dans $PACNS) et local $NS/essai (sans secret)"
  echo "Secrets dans $NS avant tout événement : $(kubectl get secrets -n "$NS" --no-headers 2>/dev/null | grep -c . || true)"
  git -C "$W" clone -q "http://$g:$PORT_FJ/banc/essai.git" depot
  mkdir -p "$W/depot/.tekton"; sed "s|@BUSYBOX@|$BUSYBOX|g" "$here/essai/k-push.yaml" > "$W/depot/.tekton/k-push.yaml"
  for f in k-bundle k-hostile k-pr; do sed "s|@BUSYBOX@|$BUSYBOX|g" "$here/essai/$f.yaml" > "$W/depot/.tekton/$f.yaml"; done
  s0=$(pousser "banc PaC : .tekton/ initial"); echo "$s0" > "$W/sha0"; echo "push initial : $s0"
  ;;
cas)
  g=$(gw); s0=$(cat "$W/sha0")
  for _ in $(seq 60); do [ "$(prs "$s0")" -ge 3 ] && break; sleep 2; done
  echo "## référence : PipelineRuns du push initial $s0 : $(prs "$s0") (attendu 3 : k-push, k-bundle, k-hostile)"
  [ "$(prs "$s0")" -ge 3 ] || { echo "KO   référence absente : cas K2 à K8 non interprétables (Repository global ? voir K5)" >&2; exit 1; }
  kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/sha=$s0" -o json | jq -r '.items[] | "  \(.metadata.name) (generateName \(.metadata.generateName // "-"), modèle \(.metadata.labels["pipelinesascode.tekton.dev/original-prname"]))"'
  echo "## K5 : Secrets dans $NS après le push : $(kubectl get secrets -n "$NS" --no-headers 2>/dev/null | grep -c . || true) ; annotation git-auth-secret : $(kubectl get pipelineruns -n "$NS" -o json | jq '[.items[].metadata.annotations["pipelinesascode.tekton.dev/git-auth-secret"] // empty] | length')"
  python3 -I - "$F/data/forgejo.db" "$s0" "$W" <<'PY'
import json, sqlite3, sys
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
for rid, req, payload, ok in db.execute("select id, request_content, payload_content, is_succeed from hook_task where event_type = 'push' order by id"):
    if json.loads(payload).get("after") == sys.argv[2]:
        r = json.loads(req); hs = r["headers"]
        open(f"{sys.argv[3]}/corps.json", "w").write(r["body"])
        open(f"{sys.argv[3]}/entetes-valides", "w").write("".join(f"{k}: {v}\n" for k, v in hs.items()))
        open(f"{sys.argv[3]}/entetes-sans-signature", "w").write("".join(f"{k}: {v}\n" for k, v in hs.items() if "ignature" not in k))
        open(f"{sys.argv[3]}/entetes-signature-fausse", "w").write("".join(f"{k}: {'0' * 64 if 'ignature' in k else v}\n" for k, v in hs.items()))
        print(f"livraison de référence : hook_task {rid}, réussie {bool(ok)}, X-Forgejo-Delivery {hs.get('X-Forgejo-Delivery')}, en-têtes de signature : {sorted(k for k in hs if 'ignature' in k)}")
        break
else:
    sys.exit("livraison du push initial introuvable")
PY
  for cas in sans-signature signature-fausse valides; do
    avant=$(prs "$s0"); code=$(curl -s -o "$W/reponse" -w '%{http_code}' -X POST -H @"$W/entetes-$cas" --data-binary @"$W/corps.json" "http://127.0.0.1:$PORT_PAC/")
    sleep 20; echo "## K$([ $cas = valides ] && echo 3 || echo 2) $cas : HTTP $code, PipelineRuns du push initial : $avant -> $(prs "$s0")"
  done
  kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/sha=$s0" --no-headers -o custom-columns=N:.metadata.name | sort | sed 's/^/  /'
  echo "refus de PaC (journal du contrôleur, messages de signature seulement) :"
  kubectl logs -n "$PACNS" deploy/pipelines-as-code-controller --since=5m 2>/dev/null | jq -r 'select(.level == "error" or .level == "warn") | .msg' 2>/dev/null \
    | grep -iE 'signature' | sed -E 's/[0-9a-f]{32,}/<hex>/g' | sort | uniq -c | sed 's/^/  /' || true
  echo "## K4 : contrôleur à 0 pendant un push"
  kubectl scale -n "$PACNS" deploy/pipelines-as-code-controller --replicas=0 >/dev/null
  kubectl wait -n "$PACNS" --for=delete pod -l app.kubernetes.io/name=controller --timeout=120s >/dev/null 2>&1 || true
  echo "k4 $(date -u +%FT%TZ)" > "$W/depot/k4.txt"; s1=$(pousser "banc PaC : K4"); echo "push pendant l'arrêt : $s1"
  sleep 15
  python3 -I -c 'import json, sqlite3, sys
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
r = [(i, ok) for i, p, ok in db.execute("select id, payload_content, is_succeed from hook_task where event_type = '"'push'"'") if json.loads(p).get("after") == sys.argv[2]]
print(f"livraisons Forgejo de {sys.argv[2][:12]} : {len(r)}, réussies : {sum(1 for _, ok in r if ok)}")
sys.exit(0 if len(r) >= 1 and not any(ok for _, ok in r) else "KO   K4 non interprétable : il faut au moins une livraison, toutes en échec")' "$F/data/forgejo.db" "$s1"
  kubectl scale -n "$PACNS" deploy/pipelines-as-code-controller --replicas=1 >/dev/null
  kubectl rollout status -n "$PACNS" deploy/pipelines-as-code-controller --timeout=180s >/dev/null
  echo "contrôleur relancé à $(date -u +%T) ; attente de 180 s"; sleep 180
  echo "PipelineRuns de $s1 : $(prs "$s1") (prédiction : 0)"
  echo "## K6 : pipelinerun_provenance default_branch, PR qui modifie .tekton/k-pr.yaml"
  kubectl patch repository -n "$NS" essai --type merge -p '{"spec":{"settings":{"pipelinerun_provenance":"default_branch"}}}' >/dev/null
  git -C "$W/depot" checkout -q -b k6
  sed -i 's/value: "main"/value: "branche"/' "$W/depot/.tekton/k-pr.yaml"
  s2=$(pousser "banc PaC : K6, marque de branche" k6); echo "commit de la branche k6 : $s2"
  pr=$(api repos/banc/essai/pulls -X POST -d '{"head": "k6", "base": "main", "title": "K6"}' | jq -r .number); echo "PR n° $pr ouverte"
  for _ in $(seq 60); do [ "$(prs "$s2")" -ge 1 ] && break; sleep 2; done
  kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/sha=$s2" -o json \
    | jq -r '.items[] | "  \(.metadata.name) : param marque = \((.spec.params // [])[] | select(.name == "marque") | .value)"'
  echo "PipelineRuns de la PR : $(prs "$s2") (prédiction : marque = main)"
  echo "## K7 : PipelineRun à pipelineRef par bundle"
  kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/sha=$s0,pipelinesascode.tekton.dev/original-prname=k-bundle" -o json \
    | jq -c '.items[0].spec | {pipelineRef, pipelineSpec_present: (.pipelineSpec != null)}'
  echo "## K8 : PipelineRun hostile tel que créé par PaC (archivé, nettoyé)"
  kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/sha=$s0,pipelinesascode.tekton.dev/original-prname=k-hostile" -o json \
    | jq '.items[0] | del(.status, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields, .metadata.ownerReferences, .metadata.name, .metadata.annotations["pipelinesascode.tekton.dev/git-auth-secret"])' > "$here/resultats/k8-objet.json"
  jq -c '{generateName: .metadata.generateName, env: .spec.taskRunTemplate.podTemplate.env, taskSpec_en_ligne: [.spec.pipelineSpec.tasks[] | (.taskSpec != null)], pipelineRef: .spec.pipelineRef}' "$here/resultats/k8-objet.json"
  echo "k8-objet.json : sha256 $(sha256sum < "$here/resultats/k8-objet.json" | cut -c1-64) ; motifs secret ou token : $(grep -ciE 'token|password' "$here/resultats/k8-objet.json" || true)"
  echo "## K8 bis : env du podTemplate contre env du pas (journal du pod de k-hostile)"
  tr=$(kubectl get taskruns -n "$NS" -l "pipelinesascode.tekton.dev/sha=$s0,pipelinesascode.tekton.dev/original-prname=k-hostile" -o jsonpath='{.items[0].metadata.name}')
  kubectl wait -n "$NS" --for=condition=Succeeded "taskrun/$tr" --timeout=180s >/dev/null 2>&1 || echo "TaskRun $tr non réussi"
  echo "sortie du pas : $(kubectl logs -n "$NS" "$(kubectl get taskrun -n "$NS" "$tr" -o jsonpath='{.status.podName}')" -c step-lire 2>&1 | tail -1)"
  echo "## K5 (fin) : Secrets dans $NS : $(kubectl get secrets -n "$NS" --no-headers 2>/dev/null | grep -c . || true)"
  ;;
admission)
  # Étape 2 : cluster du PoC, rien d'installé ; dry-run serveur sous l'identité de l'EventListener.
  export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
  AS=system:serviceaccount:declencheurs:el-forgejo
  O=$W/admission; umask 077; mkdir -p "$O"
  kubectl get pipelineruns -n builds -o json | jq '[.items[] | select(.metadata.labels["triggers.tekton.dev/eventlistener"] == "forgejo")] | sort_by(.metadata.creationTimestamp) | last' > "$O/reel.json"
  [ "$(jq -r '.metadata.name // empty' "$O/reel.json")" != "" ] || { echo "KO   aucun PipelineRun de l'EventListener dans builds" >&2; exit 1; }
  echo "PipelineRun réel de référence : $(jq -r .metadata.name "$O/reel.json") ; pipelineRef $(jq -c '.spec.pipelineRef.resolver' "$O/reel.json")"
  base='del(.status, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields, .metadata.ownerReferences, .metadata.name) | .metadata.generateName = "banc-pac-dry-" | .metadata.namespace = "builds"'
  jq "$base" "$O/reel.json" > "$O/v-temoin.json"
  jq "$base | .spec.taskRunTemplate.podTemplate.env = [{\"name\": \"BANC_PAC\", \"value\": \"env-du-podTemplate\"}]" "$O/reel.json" > "$O/v-env.json"
  # v-hostile : l'objet de K8 plus une étape privilégiée et hostPath /, ajoutées ici et jamais exécutées dans kind (A1 a mesuré que PaC les laisse passer)
  jq "$base | .spec.pipelineSpec.tasks[0].taskSpec.steps[0].securityContext = {\"privileged\": true} | .spec.pipelineSpec.tasks[0].taskSpec.volumes = [{\"name\": \"hote\", \"hostPath\": {\"path\": \"/\"}}] | .spec.pipelineSpec.tasks[0].taskSpec.steps[0].volumeMounts = [{\"name\": \"hote\", \"mountPath\": \"/hote\"}]" "$here/resultats/k8-objet.json" > "$O/v-hostile.json"
  jq "$base | del(.spec.taskRunTemplate.podTemplate.env)" "$here/resultats/k8-objet.json" > "$O/v-enligne.json"
  echo "fenêtre des requêtes sous l'identité empruntée $AS : début $(date -u +%FT%TZ)"
  for v in temoin env hostile enligne; do
    rc=0; kubectl create --dry-run=server --as="$AS" -f "$O/v-$v.json" > "$O/r-$v.txt" 2>&1 || rc=$?
    echo "## dry-run $v : code $rc ; webhooks cités : $(grep -oE 'admission webhook "[^"]+"' "$O/r-$v.txt" | sort -u | tr '\n' ' ') ; politiques citées : $(grep -oE '[a-z0-9-]+-[a-z0-9]{8}|finegrained-[a-z-]+' "$O/r-$v.txt" | sort -u | tr '\n' ' ')"
    masque < "$O/r-$v.txt" | tr '\n' ' ' | cut -c1-400 | sed 's/^/   texte : /'; echo
    if [ "$v" = temoin ] && [ "$rc" != 0 ]; then echo "KO   témoin refusé : v-env non interprétable" >&2; exit 1; fi
  done
  echo "fin des requêtes sous $AS : $(date -u +%FT%TZ)"
  echo "portée : seule l'admission du PipelineRun est mesurée ; aucun pod n'est créé (ni Pod Security, ni règles Kyverno des pods, ni Trusted Resources)"
  echo "PipelineRuns banc-pac-dry-* réellement présents dans builds (attendu 0) : $(kubectl get pipelineruns -n builds --no-headers 2>/dev/null | grep -c '^banc-pac-dry-' || true)"
  ;;
demonter)
  kind delete cluster --name "$CL" --kubeconfig "$KUBECONFIG" 2>&1 | tail -2
  [ ! -f "$F/forgejo.pid" ] || { kill "$(cat "$F/forgejo.pid")" 2>/dev/null || true; echo "Forgejo arrêté"; }
  echo "KUBECONFIG dédié laissé en place, sans le contexte du cluster supprimé : $KUBECONFIG"
  echo "clusters kind restants : $(kind get clusters 2>/dev/null | tr '\n' ' ')"
  ;;
*) echo "KO   étape inconnue : ${1:-}" >&2; exit 1 ;;
esac
echo "# fin $(date -u +%FT%TZ)"
