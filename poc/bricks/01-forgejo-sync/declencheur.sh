#!/usr/bin/env bash
# Brique 01, jalon S5 : branche custom du fork workspace/sample-app-sync construite par la plateforme (D2 (b) et option (ii),
# décisions du propriétaire du 02/11/2026). Aucun fichier de la brique 08 n'est modifié ; tout dérive de ce qui est en service.
#   pipeline    pipeline signée sample-app-sync : la pipeline sample-app en service (bundle du gabarit, lu par tkn bundle list),
#               renommée et publiant vers builds/sample-app-sync au lieu de builds/sample-app ; écart vérifié (ces deux champs
#               seuls), re-signée par la clé des tâches, publiée dans tekton/pipelines/sample-app-sync
#   installer   secret HMAC propre (0600 sur l'hôte, Secret forgejo-webhook-sync de declencheurs), TriggerTemplate
#               sample-app-sync et EventListener forgejo-sync dérivés de ceux en service (filtre : workspace/sample-app-sync,
#               refs/heads/custom/*), webhook du fork (branches custom/*) ; EventListener et gabarit de la 08 inchangés
#   construire  push d'un commit sur custom/s5 du fork par poc-dev : PipelineRun sample-app-sync-<commit>, image, signature de Chains
#   porte       jugement de l'image par la porte de la 08 (source attendue : le fork au commit de custom/s5), puis non-interférence :
#               l'image réelle de la 08, jugée avec sa source, reste admise
# Prérequis : forgejo.sh comptes … protections (S2). Aucun secret en argument de commande.
#
# Usage (racine du dépôt) : poc/bricks/01-forgejo-sync/declencheur.sh <étape>…   (journal : resultats/declencheur-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
h08=$here/../08-trust-plane
. "$h08/commun.sh"
# Porte de la 08 réutilisée telle quelle : variables et fonction juger lues dans politique.sh (chemins de la 08).
eval "$(grep -E '^(PORTE|PORTE_DIGEST)=' "$h08/politique.sh" | sed 's/ *#.*//')"
eval "$(sed -n '/^juger() {/,/^}/p' "$h08/politique.sh" | sed 's#\$here/#$h08/#g')"
FORGEJO_HOTE=https://192.168.161.13:3000
PROJET=sample-app-sync
FORK=workspace/$PROJET
BRANCHE=custom/s5
PIPE_DEPOT=tekton/pipelines/$PROJET
IMAGE_08=$REG/builds/sample-app
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # image réelle de la 08 (brique 04)
IMAGE_S5=$REG/builds/$PROJET
EL_NS=declencheurs
T=$W/synchro-s5
mkdir -p "$T/auth/docker" && chmod 0700 "$T"
trap 'rm -rf "$T" "$W/refus.out"' EXIT

api() { # méthode chemin [corps-json] : API de Forgejo avec le jeton de l'administrateur
  (umask 077 && printf 'Authorization: token %s\n' "$(cat "$S/forgejo-admin.token")" > "$T/auth/entete")
  if [ $# -gt 2 ]; then curl -fsS --cacert "$P/ca-poc.crt" -H @"$T/auth/entete" -H 'Content-Type: application/json' -X "$1" "$FORGEJO_HOTE/api/v1$2" -d @"$3"
  else curl -fsS --cacert "$P/ca-poc.crt" -H @"$T/auth/entete" -X "$1" "$FORGEJO_HOTE/api/v1$2"; fi
  rm -f "$T/auth/entete"
}
pipeline_en_service() { kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value'; }
el_sync_url() { echo "http://${IP[sc-confiance]}:$(kubectl get svc -n "$EL_NS" el-forgejo-sync -o jsonpath='{.spec.ports[?(@.name=="http-listener")].nodePort}')"; }

etape_pipeline() {
  local src n
  src=$(pipeline_en_service)
  echo "pipeline en service : $src"
  [ "$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "name") | .value')" = sample-app ] \
    || { echo "KO   gabarit en service sans la pipeline sample-app (bascule de J8 attendue)" >&2; exit 1; }
  SSL_CERT_FILE=$P/ca-poc.crt tkn bundle list "$src" pipeline sample-app -o json > "$T/source.json"
  # Dérivée : nom et dépôt d'image changés ; signature retirée avant la nouvelle.
  jq --arg a "$IMAGE_08" --arg b "$IMAGE_S5" --arg n "$PROJET" '.metadata.name = $n | del(.metadata.annotations["tekton.dev/signature"])
    | .spec.tasks |= map(if .params then .params |= map(if .name == "image" and .value == $a then .value = $b else . end) else . end)' "$T/source.json" > "$T/derivee.json"
  n=$(jq --arg a "$IMAGE_08" '[.spec.tasks[].params[]? | select(.name == "image" and .value == $a)] | length' "$T/source.json")
  [ "$n" = 1 ] && echo "OK   un seul paramètre image = $IMAGE_08 dans la pipeline source" || { echo "KO   $n paramètre(s) image = $IMAGE_08" >&2; exit 1; }
  # Écart vérifié : en remettant nom et dépôt, la dérivée redevient la source (signature exceptée).
  if cmp -s <(jq -S --arg a "$IMAGE_08" --arg b "$IMAGE_S5" '.metadata.name = "sample-app"
        | .spec.tasks |= map(if .params then .params |= map(if .name == "image" and .value == $b then .value = $a else . end) else . end)' "$T/derivee.json") \
      <(jq -S 'del(.metadata.annotations["tekton.dev/signature"])' "$T/source.json"); then
    echo "OK   écart avec la pipeline en service : nom et dépôt d'image seulement"
  else echo "KO   écart inattendu avec la pipeline en service" >&2; exit 1; fi
  yq -P '.' "$T/derivee.json" > "$T/derivee.yaml"
  tkn pipeline sign "$T/derivee.yaml" -K "$S/taches.key" -f "$T/derivee-signee.yaml" > /dev/null
  auth_zot "$T/auth/docker/config.json"
  echo "$REG/$PIPE_DEPOT@$(bundle "$T/derivee-signee.yaml" "$PIPE_DEPOT" s5)" | tee "$R/s5-pipeline.ref"
  jq -c '[.spec.tasks[] | {name, bundle: ((.taskRef.params // [])[] | select(.name == "bundle") | .value)}]' "$T/derivee.json"
}

etape_installer() {
  local ref url
  ref=$(cat "$R/s5-pipeline.ref")
  [ -s "$S/forgejo-webhook-sync.secret" ] || (umask 077 && openssl rand -hex 32 > "$S/forgejo-webhook-sync.secret")
  kubectl create secret generic forgejo-webhook-sync -n "$EL_NS" --from-file=secret="$S/forgejo-webhook-sync.secret" \
    --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  kubectl get triggertemplate -n "$EL_NS" sample-app -o json | jq --arg n "$PROJET" --arg r "$ref" '{apiVersion, kind,
      metadata: {name: $n, namespace: .metadata.namespace}, spec: (.spec | .resourcetemplates[0].metadata.name = "\($n)-$(tt.params.commit)"
      | .resourcetemplates[0].spec.pipelineRef.params |= map(if .name == "bundle" then .value = $r elif .name == "name" then .value = $n else . end))}' \
    | kubectl apply --server-side -f - >/dev/null
  kubectl get eventlistener -n "$EL_NS" forgejo -o json | jq --arg p "$PROJET" --arg f "body.ref.startsWith('refs/heads/custom/') && body.repository.full_name == 'workspace/$PROJET' && body.after.matches('^[0-9a-f]{40}$')" \
    '{apiVersion, kind, metadata: {name: "forgejo-sync", namespace: .metadata.namespace}, spec: (.spec | .triggers |= [.[0] | .name = "\($p)-push"
      | .interceptors |= map(if .ref.name == "github" then .params |= map(if .name == "secretRef" then .value.secretName = "forgejo-webhook-sync" else . end)
          elif .ref.name == "cel" then .params |= map(if .name == "filter" then .value = $f else . end) else . end)
      | .template.ref = $p])}' > "$T/el.json"
  jq -c '.spec.triggers[0] | {name, filtre: (.interceptors[] | select(.ref.name == "cel") | .params[0].value), secret: (.interceptors[] | select(.ref.name == "github") | .params[] | select(.name == "secretRef") | .value), template}' "$T/el.json"
  kubectl apply --server-side -f "$T/el.json" >/dev/null
  for _ in $(seq 60); do kubectl get deploy -n "$EL_NS" el-forgejo-sync >/dev/null 2>&1 && break; sleep 2; done
  kubectl wait -n "$EL_NS" --for=condition=Available deploy/el-forgejo-sync --timeout=180s >/dev/null
  url=$(el_sync_url)
  for _ in $(seq 60); do [ "$(sur sc-stockage "curl -s -o /dev/null -w '%{http_code}' $url/live" || true)" = 200 ] && break; sleep 1; done
  echo "EventListener forgejo-sync joignable par Forgejo : $url"
  for id in $(api GET "/repos/$FORK/hooks" | jq -r '.[].id'); do api DELETE "/repos/$FORK/hooks/$id" >/dev/null; done
  jq -n --arg u "$url" --rawfile s "$S/forgejo-webhook-sync.secret" '{type: "forgejo", active: true, events: ["push"], branch_filter: "custom/*",
    config: {url: $u, content_type: "json", secret: ($s | rtrimstr("\n"))}}' > "$T/auth/hook.json"
  api POST "/repos/$FORK/hooks" "$T/auth/hook.json" | jq -c '{id, type, active, events, branch_filter, url: .config.url}'
  rm -f "$T/auth/hook.json"
  echo "## EventListener et gabarit de la 08, inchangés"
  kubectl get eventlistener -n "$EL_NS" forgejo -o json | jq -c '{triggers: [.spec.triggers[] | {name, template: .template.ref}]}'
  [ "$(pipeline_en_service)" != "$ref" ] && echo "OK   gabarit sample-app de la 08 toujours sur sa pipeline" || { echo "KO   gabarit de la 08 modifié" >&2; exit 1; }
}

etape_construire() {
  local c pr d u v
  (umask 077 && printf 'Authorization: token %s\n' "$(cat "$S/forgejo-poc-dev.token")" > "$T/auth/entete-dev")
  rm -rf "$T/w"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    git clone -q "$FORGEJO_HOTE/$FORK.git" "$T/w"
  git -C "$T/w" -c user.name="PoC brique 01" -c user.email=poc-dev@poc.test -c commit.gpgsign=false commit -q --allow-empty -m "branche custom (S5)"
  c=$(git -C "$T/w" rev-parse HEAD)
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    GIT_CONFIG_KEY_1="http.$FORGEJO_HOTE/$FORK.git.extraHeader" GIT_CONFIG_VALUE_1="$(cat "$T/auth/entete-dev")" \
    git -C "$T/w" push -q "$FORGEJO_HOTE/$FORK.git" "HEAD:refs/heads/$BRANCHE"
  rm -f "$T/auth/entete-dev"
  echo "commit $c poussé sur $BRANCHE par poc-dev (arbre identique à main du fork)"
  pr=$PROJET-$c
  for _ in $(seq 60); do kubectl get pipelinerun -n builds "$pr" >/dev/null 2>&1 && break; sleep 2; done
  kubectl get pipelinerun -n builds "$pr" >/dev/null 2>&1 && echo "OK   PipelineRun $pr créé par le webhook" || { echo "KO   aucun PipelineRun $pr" >&2; exit 1; }
  kubectl wait -n builds --for=condition=Succeeded "pipelinerun/$pr" --timeout=900s >/dev/null \
    || { kubectl get pipelinerun -n builds "$pr" -o json | jq -c '.status.conditions' >&2; exit 1; }
  u=$(kubectl get pipelinerun -n builds "$pr" -o json | jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value')
  d=$(kubectl get pipelinerun -n builds "$pr" -o json | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
  echo "image : $u@$d"
  [ "$u" = "$IMAGE_S5" ] && echo "OK   image publiée dans builds/$PROJET, pas dans builds/sample-app" || { echo "KO   dépôt $u" >&2; exit 1; }
  v=$(signe pipelinerun "$pr")
  [ "$v" = true ] && echo "OK   PipelineRun signé par Chains" || { echo "KO   signature de Chains : $v" >&2; exit 1; }
  [ "$d" = "$APP_DIGEST" ] && echo "MESURE digest $d : celui de l'image réelle de la 08 (arbre identique, construction reproductible)" \
    || echo "MESURE digest $d : différent de celui de l'image réelle de la 08 ($APP_DIGEST)"
  printf '%s %s %s\n' "$c" "$u" "$d" > "$R/s5-construction.txt"
}

etape_porte() {
  local c u d r i tete src
  read -r c u d < "$R/s5-construction.txt"
  src=$(jq -nc --arg u "https://sc-stockage.poc.test:3000/$FORK.git" --arg r "$c" '{git: {url: $u, revision: $r}}')
  for i in $(seq 6); do   # le job d'horodatage (CronJob, chaque minute) doit d'abord avoir publié le bundle de l'enveloppe
    r=$(juger s5-fork "$u@$d" policy.yaml porte "$src")
    [ "$(cut -d'|' -f7 <<< "$r")" = ok ] && break
    sleep 60
  done
  echo "  $r (essai $i)"
  [ "$(cut -d'|' -f1,3,4,7 <<< "$r")" = "VERDICT|true||ok" ] && echo "OK   image de la branche custom admise, source attendue : $FORK@$c" || { echo "KO   verdict de la branche custom" >&2; exit 1; }
  r=$(juger s5-autre-source "$u@$d" policy.yaml porte "$(jq -nc --arg r "$c" '{git: {url: "https://sc-stockage.poc.test:3000/workspace/sample-app.git", revision: $r}}')")
  echo "  $r"
  [ "$(cut -d'|' -f1,3 <<< "$r")" = "VERDICT|false" ] && echo "OK   même image, source attendue workspace/sample-app : refusée" || { echo "KO   source non vérifiée" >&2; exit 1; }
  echo "## non-interférence : image réelle de la 08, jugée avec sa source"
  tete=$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    git ls-remote --refs "$FORGEJO_HOTE/workspace/sample-app.git" refs/heads/main | cut -f1)
  r=$(juger s5-reelle "$IMAGE_08@$APP_DIGEST" policy.yaml porte "$(jq -nc --arg r "$tete" '{git: {url: "https://sc-stockage.poc.test:3000/workspace/sample-app.git", revision: $r}}')")
  echo "  $r"
  [ "$(cut -d'|' -f1,3,4 <<< "$r")" = "VERDICT|true|" ] && echo "OK   image réelle de la 08 toujours admise (provenance de la branche custom dans un autre dépôt)" \
    || { echo "KO   image réelle de la 08 refusée après S5" >&2; exit 1; }
}

lancer declencheur S5 "$@"
