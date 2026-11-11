#!/usr/bin/env bash
# Brique 06, jalon S4d3 (décision du propriétaire du 11/11/2026, 20:35:01 UTC : « Oui, les deux ») : le deb de sample-app sur les
# deux chemins de déclenchement de la 08, la livraison du webhook de Forgejo (EventListener forgejo, Trigger sample-app-deb-push
# sélectionné par label) et le rattrapage (CronJob rattrapage-deb, même image). Sur le modèle de preuves.sh bascule (J8).
# Prédictions : resultats/s4d3-predictions.md, commitées avant tout lancement. Relevé de l'état déployé : s4d3-releve-*.log.
#   prealables  lecture (API, Zot) : declencheur.yaml rendu (bundle de S4d1, image du rattrapage), aucune variable restante ;
#               gabarit conforme aux exigences de main.go ; Trigger égal au trigger en ligne en service (intercepteurs, liaisons) ;
#               CronJob égal à rattrapage hors nom, compte, gabarit et suspension ; EventListener du dépôt égal à celui en service
#               plus le labelSelector ; bundle de la pipeline dans Zot et ses tâches dans la liste revue
#   deployer    cluster (réversible : étape retirer) : EventListener avec labelSelector (document seul de declencheurs.yaml de la
#               08), declencheur.yaml ; droits mesurés (can-i) ; PipelineRun du gabarit admis à blanc au nom de el-forgejo et de
#               rattrapage-deb, spec égale à celle de s4d-deb-1 ; livraisons sans signature, d'un autre secret, à corps modifié
#               (commit fictif) : refusées par les intercepteurs des deux triggers, aucun PipelineRun
#   chemins     cluster et Zot (écritures de Chains dans builds/sample-app-deb) : chemin 1, livraison de Forgejo pour la tête de
#               main ; chemin 2, PipelineRun purgé, CronJob rattrapage-deb repris ; rejeu de la livraison ; enveloppes comptées
#   porte       cluster : Job de la porte sur le deb (provenance jugée : celle du chemin 2), puis sur l'image sample-app
#   retirer     cluster, au choix du propriétaire seulement : objets de declencheur.yaml retirés (le labelSelector reste, sans
#               effet sans objet Trigger labellisé) ; rien n'est retiré de Zot
# Aucun secret en argument de commande : le jeton de Forgejo et le secret du webhook sont lus dans des fichiers.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4d3.sh <étape>…   (journal : resultats/s4d3-<étape>.log)
set -euo pipefail
export LC_ALL=C

h06=$(cd "$(dirname "$0")" && pwd)
. "$h06/../08-trust-plane/politique.sh"   # here (08), commun.sh, juger, origine, creations, passage, prov_pr, purger_pr, signe…
for f in $(declare -F | awk '$3 ~ /^etape_/ {print $3}'); do unset -f "$f"; done   # seules les étapes de S4d3 sont appelables
R=$h06/resultats
T=$W/s4d3-06
mkdir -p "$T"
trap 'rm -rf "$T/auth" "$T/webhook"' EXIT
EL_NS=declencheurs
EL=system:serviceaccount:declencheurs:el-forgejo
RD=system:serviceaccount:declencheurs:rattrapage-deb
RI=system:serviceaccount:declencheurs:rattrapage

PIPE_DEB=$REG/tekton/pipelines/sample-app-deb@sha256:82c8373d725941bf65d6530e0c88904bb291e5f8b5c18c2209919a6d355f54a5   # S4d1
DEB_DIGEST=sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e                                     # S4d1
DEB=builds/sample-app-deb@$DEB_DIGEST
APP=builds/sample-app@$APP_DIGEST
PR_DEB=sample-app-deb-$TETE_J2   # 55 caractères
PR_APP=sample-app-$TETE_J2
URL=https://sc-stockage.poc.test:3000/$SAMPLE_APP.git
SRC=$(jq -nc --arg u "$URL" --arg r "$TETE_J2" '{git: {url: $u, revision: $r}}')
FAUX=1111111111111111111111111111111111111111

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
ECARTS=0
mesure() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS=$((ECARTS + 1)); }; }
champ() { cut -d'|' -f"$2" <<< "$1"; }
ecarts() { [ "$ECARTS" = 0 ] || { echo "KO   $ECARTS écart(s)" >&2; exit 1; }; }

rendre() { # declencheur.yaml rendu dans $T/declencheur.yaml ; objets (JSON, un tableau) dans $T/declencheur.json
  sed -e "s#@PIPELINE@#$PIPE_DEB#" -e "s#@RATTRAPAGE@#$REG/$RATTRAPAGE@$RATTRAPAGE_DIGEST#" "$h06/deb/declencheur.yaml" > "$T/declencheur.yaml"
  ! grep -n '@[A-Z_]*@' "$T/declencheur.yaml" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue" >&2; exit 1; }
  kubectl create --dry-run=client -o json -f "$T/declencheur.yaml" | jq -s '[.[] | if .kind == "List" then .items[] else . end]' > "$T/declencheur.json"
}
el_depot() { # EventListener de declencheurs.yaml (08), seul document, en JSON
  sed 's#@PIPELINE@#BUNDLE#' "$here/politique/declencheurs.yaml" | kubectl create --dry-run=client -o json -f - \
    | jq -s '[.[] | if .kind == "List" then .items[] else . end] | .[] | select(.kind == "EventListener")'
}
el_service() { # spec de l'EventListener en service, défauts du serveur retirés (relevé du 11/11/2026, s4d3-releve-2.log)
  kubectl get eventlistener -n declencheurs forgejo -o json | jq -S '.spec | del(.namespaceSelector)
    | del(.resources.kubernetesResource.spec.template.metadata) | del(.resources.kubernetesResource.spec.template.spec.containers)
    | .triggers |= map(.bindings |= map(del(.kind)))'
}
pr_rendu() { # nom : PipelineRun du gabarit sample-app-deb rendu pour la tête de main, sous ce nom, dans $T/pr-<nom>.json
  jq --arg c "$TETE_J2" --arg u "$URL" --arg n "$1" '.[] | select(.kind == "TriggerTemplate") | .spec.resourcetemplates[0]
    | walk(if type == "string" then gsub("\\$\\(tt.params.commit\\)"; $c) | gsub("\\$\\(tt.params.depot\\)"; $u) else . end)
    | .metadata.name = $n' "$T/declencheur.json" > "$T/pr-$1.json"
  ! grep -q '\$(tt\.' "$T/pr-$1.json" || { echo "KO   variable du gabarit non remplacée" >&2; exit 1; }
}
spec_pr() { jq -S '.spec' "$1"; }   # fichier JSON d'un PipelineRun
peut() { kubectl auth can-i --as "$1" "${@:2}" 2>/dev/null || true; }   # compte verbe ressource [nom] -n espace : yes|no
envel() { cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$1" 2>/dev/null | grep -c . || true; }   # dépôt@digest

# Repris de preuves.sh (08), qui ne peut pas être chargé (il lance ses étapes) : mêmes corps, mêmes commandes.
corps_push() { # commit fichier : corps d'un événement push de workspace/sample-app sur main, comme Forgejo
  jq -nc --arg c "$1" '{ref: "refs/heads/main", after: $c, repository: {full_name: "workspace/sample-app",
    clone_url: "https://sc-stockage.poc.test:3000/workspace/sample-app.git"}}' > "$T/webhook/$2"
}
forgejo_livrer() { # nouvelle livraison du webhook de sample-app par Forgejo (POST hooks/<id>/tests : dernier commit de main) ; code HTTP
  local id
  printf 'Authorization: token %s\n' "$(cat "$S/forgejo-admin.token")" > "$T/auth/entete"
  id=$(curl -fsS --cacert "$P/ca-poc.crt" -H @"$T/auth/entete" https://192.168.161.13:3000/api/v1/repos/workspace/sample-app/hooks | jq -r '.[0].id')
  curl -fsS -o /dev/null -w '%{http_code}' --cacert "$P/ca-poc.crt" -H @"$T/auth/entete" -X POST \
    "https://192.168.161.13:3000/api/v1/repos/workspace/sample-app/hooks/$id/tests"
  rm -f "$T/auth/entete"
}
el_existe() { # depuis : erreurs « already exists » de l'EventListener, une ligne JSON par erreur
  kubectl logs -n "$EL_NS" deploy/el-forgejo --since-time="$1" \
    | jq -Rc 'fromjson? | select(.severity == "error" and (.message | startswith("couldn'"'"'t create resource")))
      | {t: .timestamp[11:19], eventID: ."/triggers-eventid", erreur: (.message | capture("(?<e>pipelineruns.tekton.dev .* already exists)").e)}'
}
refus_intercepteurs() { # depuis : refus des intercepteurs de Triggers, une ligne JSON par refus
  kubectl logs -n tekton-pipelines deploy/tekton-triggers-core-interceptors --since-time="$1" \
    | jq -Rc 'fromjson? | select((.msg // "") | test("Continue:false")) | {t: (.ts | todate | .[11:19]), refus: (.msg | capture("Code:(?<code>[A-Za-z]+) Message:(?<message>[^}]*)"))}'
}
temoin() { # libellé compte fichier : création admise en dry-run serveur, sous l'identité du compte ; objet rendu dans $T/temoin.json
  kubectl create --as "$2" --dry-run=server -o json -f "$3" > "$T/temoin.json" 2> "$T/temoin.err" \
    && echo "OK   $1 : admis à blanc" || { echo "KO   $1 : refusé ($(tr '\n' ' ' < "$T/temoin.err" | cut -c1-260))" >&2; exit 1; }
}

fin_pr() { # nom : attend la fin (3600 s au plus) ; « statut|raison »
  local st=""
  for _ in $(seq 1800); do
    st=$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || true)
    [ -n "$st" ] && [ "$st" != Unknown ] && break; sleep 2
  done
  kubectl get pipelinerun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}|{.status.conditions[?(@.type=="Succeeded")].reason}'
}
CHEMIN_UID=""
chemin() { # libellé origine compte t0 : PipelineRun PR_DEB créé par ce chemin depuis t0, mesuré ; UID dans CHEMIN_UID
  local l=$1 st tr p n
  for _ in $(seq 120); do kubectl get pipelinerun -n builds "$PR_DEB" >/dev/null 2>&1 && break; sleep 2; done
  kubectl get pipelinerun -n builds "$PR_DEB" >/dev/null 2>&1 || { echo "KO   $l : aucun PipelineRun $PR_DEB" >&2; exit 1; }
  CHEMIN_UID=$(kubectl get pipelinerun -n builds "$PR_DEB" -o jsonpath='{.metadata.uid}')
  echo "$PR_DEB créé à $(kubectl get pipelinerun -n builds "$PR_DEB" -o jsonpath='{.metadata.creationTimestamp}'), UID $CHEMIN_UID"
  mesure "$l : origine (labels)" "$(origine "$PR_DEB")" "$2"
  st=$(fin_pr "$PR_DEB")
  creations "$4" "$PR_DEB" | tee "$T/$l.creations"
  mesure "$l : créations dans l'audit de l'API" "$(sed 's/^ *//' "$T/$l.creations" | paste -sd, -)" "1 $3 201"
  mesure "$l : PipelineRun" "$st" "True|Succeeded"
  kubectl get pipelinerun -n builds "$PR_DEB" -o json > "$T/$l.pr.json"
  mesure "$l : pipeline" "$(jq -r '.spec.pipelineRef.params | (.[] | select(.name == "name") | .value) + "@" + (.[] | select(.name == "bundle") | .value)' "$T/$l.pr.json")" "sample-app-deb@$PIPE_DEB"
  spec_pr "$T/$l.pr.json" > "$T/$l.spec"
  if diff "$T/s4d-deb-1.spec" "$T/$l.spec" > "$T/$l.diff"; then echo "OK   $l : spec identique à celle de s4d-deb-1 (S4d1)"
  else sed 's/^/     /' "$T/$l.diff"; echo "ÉCART $l : spec différente de celle de s4d-deb-1"; ECARTS=$((ECARTS + 1)); fi
  kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$PR_DEB" -o json \
    | jq -r '.items[] | "\(.metadata.labels["tekton.dev/pipelineTask"])|\(.metadata.name)|\(.metadata.name | length)|\(.status.conditions[0].reason)"' | sort > "$T/$l.taskruns"
  sed 's/^/     TaskRun /' "$T/$l.taskruns"
  mesure "$l : TaskRuns réussis" "$(awk -F'|' '$4 == "Succeeded"' "$T/$l.taskruns" | wc -l)/$(wc -l < "$T/$l.taskruns")" 3/3
  mesure "$l : noms des TaskRuns de 63 caractères au plus" "$(awk -F'|' '$3 > 63' "$T/$l.taskruns" | wc -l)" 0
  mesure "$l : TaskRun publier au nom non raccourci" "$(awk -F'|' '$1 == "publier" {print $2}' "$T/$l.taskruns")" "$PR_DEB-publier"
  n=$(awk -F'|' '$1 != "publier" && $2 !~ /^'"$PR_DEB"'-(preparer|construire)$/' "$T/$l.taskruns" | wc -l)
  mesure "$l : TaskRuns preparer et construire aux noms raccourcis par Tekton" "$n" 2
  kubectl get pods -n builds -l "tekton.dev/pipelineRun=$PR_DEB" -o json \
    | jq -r '.items[] | "\(.metadata.labels["tekton.dev/pipelineTask"])|\(.spec.nodeName)|\(.spec.runtimeClassName // "-")"' | sort > "$T/$l.pods"
  sed 's/^/     pod /' "$T/$l.pods"
  mesure "$l : pods (tâche|nœud|runtime)" "$(paste -sd' ' "$T/$l.pods")" "construire|sc-build|kata preparer|sc-build|- publier|sc-build|-"
  mesure "$l : résultats" "$(jq -r '.status.results | map(.name + "=" + .value) | sort | join(" ")' "$T/$l.pr.json")" "IMAGE_DIGEST=$DEB_DIGEST IMAGE_URL=$REG/builds/sample-app-deb"
  for tr in $(cut -d'|' -f2 "$T/$l.taskruns"); do echo "     TaskRun $tr signé=$(signe taskrun "$tr")"; done
  mesure "$l : PipelineRun signé par Chains" "$(signe pipelinerun "$PR_DEB")" true
}

etape_prealables() {
  local a b
  echo "## gabarit rendu"
  rendre
  mesure "objets de declencheur.yaml" "$(jq -r 'map(.kind + "/" + .metadata.name) | sort | join(" ")' "$T/declencheur.json")" \
    "CronJob/rattrapage-deb Role/rattrapage-deb Role/rattrapage-deb-pipelineruns RoleBinding/rattrapage-deb RoleBinding/rattrapage-deb-pipelineruns ServiceAccount/rattrapage-deb Trigger/sample-app-deb-push TriggerTemplate/sample-app-deb"
  echo "## exigences de main.go sur le gabarit (paramètres commit et depot, une ressource, PipelineRun v1 de builds nommé <gabarit>-<commit>)"
  mesure "paramètres" "$(jq -r '.[] | select(.kind == "TriggerTemplate") | [.spec.params[].name] | sort | join(",")' "$T/declencheur.json")" commit,depot
  mesure "ressources" "$(jq -r '.[] | select(.kind == "TriggerTemplate") | .spec.resourcetemplates | length' "$T/declencheur.json")" 1
  pr_rendu "$PR_DEB"
  mesure "PipelineRun rendu (apiVersion kind espace/nom)" "$(jq -r '"\(.apiVersion) \(.kind) \(.metadata.namespace)/\(.metadata.name)"' "$T/pr-$PR_DEB.json")" "tekton.dev/v1 PipelineRun builds/$PR_DEB"
  echo "## Trigger sample-app-deb-push contre le trigger en ligne en service (intercepteurs et liaisons)"
  kubectl get eventlistener -n declencheurs forgejo -o json | jq -S '.spec.triggers[] | select(.name == "sample-app-push") | {interceptors, bindings: (.bindings | map({name, value}))}' > "$T/trigger-service.json"
  jq -S '.[] | select(.kind == "Trigger") | .spec | {interceptors, bindings}' "$T/declencheur.json" > "$T/trigger-deb.json"
  if diff "$T/trigger-service.json" "$T/trigger-deb.json" > "$T/trigger.diff"; then echo "OK   intercepteurs et liaisons identiques"
  else sed 's/^/     /' "$T/trigger.diff"; echo "ÉCART intercepteurs ou liaisons différents"; ECARTS=$((ECARTS + 1)); fi
  mesure "label du Trigger" "$(jq -c '.[] | select(.kind == "Trigger") | .metadata.labels' "$T/declencheur.json")" '{"poc.test/ecouteur":"forgejo"}'
  echo "## CronJob rattrapage-deb contre rattrapage en service (hors nom, compte, GABARIT et suspension)"
  # Corrigé le 11/11/2026 après le premier passage (20:42:37 UTC, arrêt avant toute écriture) : le serveur pose aussi le champ
  # déprécié serviceAccount (copie de serviceAccountName) et un jobTemplate.metadata vide ({}), absent du rendu (null).
  a='.spec | .jobTemplate.spec.template.spec |= (del(.serviceAccountName, .serviceAccount) | .containers[0].env |= map(select(.name != "GABARIT")))
    | del(.suspend) | walk(if type == "object" then del(.defaultMode, .terminationMessagePath, .terminationMessagePolicy, .imagePullPolicy,
      .dnsPolicy, .schedulerName, .terminationGracePeriodSeconds, .resources) else . end)
    | .jobTemplate.spec.template.metadata = ((.jobTemplate.spec.template.metadata // {}) | del(.creationTimestamp))
    | .jobTemplate.metadata = ((.jobTemplate.metadata // {}) | del(.creationTimestamp))'
  kubectl get cronjob -n declencheurs rattrapage -o json | jq -S "$a" > "$T/cj-service.json"
  jq -S ".[] | select(.kind == \"CronJob\") | $a" "$T/declencheur.json" > "$T/cj-deb.json"
  if diff "$T/cj-service.json" "$T/cj-deb.json" > "$T/cj.diff"; then echo "OK   CronJob identique hors nom, compte, GABARIT et suspension (image comprise)"
  else sed 's/^/     /' "$T/cj.diff"; echo "ÉCART CronJob différent"; ECARTS=$((ECARTS + 1)); fi
  mesure "compte, GABARIT, suspension" "$(jq -r '.[] | select(.kind == "CronJob") | .spec | "\(.jobTemplate.spec.template.spec.serviceAccountName) \(.jobTemplate.spec.template.spec.containers[0].env[] | select(.name == "GABARIT") | .value) \(.suspend)"' "$T/declencheur.json")" \
    "rattrapage-deb declencheurs/sample-app-deb true"
  echo "## EventListener du dépôt contre celui en service"
  el_depot | jq -S '.spec' > "$T/el-depot.json"
  el_service > "$T/el-service.json"
  if diff "$T/el-service.json" <(jq -S 'del(.labelSelector)' "$T/el-depot.json") > "$T/el.diff"; then echo "OK   identiques hors labelSelector"
  else sed 's/^/     /' "$T/el.diff"; echo "ÉCART EventListener en service différent du dépôt hors labelSelector"; ECARTS=$((ECARTS + 1)); fi
  mesure "labelSelector du dépôt" "$(jq -c '.labelSelector' "$T/el-depot.json")" '{"matchLabels":{"poc.test/ecouteur":"forgejo"}}'
  echo "## dépendances de la 08 en service"
  mesure "ConfigMap declencheurs/rattrapage" "$(kubectl get configmap -n declencheurs rattrapage -o name 2>&1)" configmap/rattrapage
  mesure "secret declencheurs/forgejo-webhook (nom seul)" "$(kubectl get secret -n declencheurs forgejo-webhook -o name 2>&1)" secret/forgejo-webhook
  mesure "NetworkPolicy builds/construction-deb-sans-sortie" "$(kubectl get networkpolicy -n builds construction-deb-sans-sortie -o name 2>&1)" networkpolicy.networking.k8s.io/construction-deb-sans-sortie
  mesure "objets Trigger de declencheurs" "$(kubectl get triggers.triggers.tekton.dev -n declencheurs -o name | wc -l)" 0
  mesure "TriggerTemplate sample-app-deb" "$(kubectl get triggertemplate -n declencheurs sample-app-deb -o name 2>/dev/null || echo absente)" absente
  echo "## bundle de la pipeline deb"
  b=$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/${PIPE_DEB#*/}")
  mesure "bundle dans Zot" "$b" "${PIPE_DEB#*@}"
  SSL_CERT_FILE=$P/ca-poc.crt crane export "$REG_HOTE/${PIPE_DEB#*/}" - | tar -xO > "$T/pipeline.json"
  while read -r a b; do
    listee "$b" && echo "OK   tâche $a dans la liste revue : ${b#"$REG/"}" || { echo "ÉCART tâche $a hors de la liste revue : $b"; ECARTS=$((ECARTS + 1)); }
  done < <(jq -r '.spec.tasks[] | "\(.name) \(.taskRef.params[] | select(.name == "bundle") | .value)"' "$T/pipeline.json")
  ecarts
}

etape_deployer() {
  local p0 p1 t0 c
  rendre
  echo "## départ"
  el_service > "$T/el-service.json"
  el_depot | jq -S '.spec' > "$T/el-depot.json"
  diff "$T/el-service.json" <(jq -S 'del(.labelSelector)' "$T/el-depot.json") > /dev/null || { echo "KO   EventListener en service différent du dépôt hors labelSelector (étape prealables)" >&2; exit 1; }
  attendu "objets Trigger de declencheurs" "$(kubectl get triggers.triggers.tekton.dev -n declencheurs -o name | wc -l)" 0
  p0=$(kubectl get pods -n declencheurs -l eventlistener=forgejo -o jsonpath='{.items[*].metadata.name}')
  echo "pod de l'EventListener : $p0"
  echo "## EventListener : labelSelector (document EventListener de declencheurs.yaml de la 08, seul)"
  el_depot > "$T/el.json"
  kubectl apply --server-side -f "$T/el.json" > /dev/null
  mesure "labelSelector en service" "$(kubectl get eventlistener -n declencheurs forgejo -o jsonpath='{.spec.labelSelector}')" '{"matchLabels":{"poc.test/ecouteur":"forgejo"}}'
  echo "## declencheur.yaml"
  kubectl apply --server-side -f "$T/declencheur.yaml"
  sleep 10   # informateurs de l'EventListener
  kubectl wait -n declencheurs --for=condition=Ready eventlistener/forgejo --timeout=120s > /dev/null
  p1=$(kubectl get pods -n declencheurs -l eventlistener=forgejo -o jsonpath='{.items[*].metadata.name}')
  mesure "pod de l'EventListener inchangé (aucun redémarrage)" "$p1" "$p0"
  mesure "CronJob rattrapage-deb suspendu" "$(kubectl get cronjob -n declencheurs rattrapage-deb -o jsonpath='{.spec.suspend}')" true
  mesure "CronJob rattrapage repris (inchangé)" "$(kubectl get cronjob -n declencheurs rattrapage -o jsonpath='{.spec.suspend}')" false
  echo "## droits (kubectl auth can-i)"
  mesure "rattrapage-deb : get triggertemplate sample-app-deb" "$(peut "$RD" get triggertemplates.triggers.tekton.dev/sample-app-deb -n declencheurs)" yes
  mesure "rattrapage-deb : get triggertemplate sample-app" "$(peut "$RD" get triggertemplates.triggers.tekton.dev/sample-app -n declencheurs)" no
  mesure "rattrapage-deb : create pipelineruns dans builds" "$(peut "$RD" create pipelineruns.tekton.dev -n builds)" yes
  mesure "rattrapage-deb : delete pipelineruns dans builds" "$(peut "$RD" delete pipelineruns.tekton.dev -n builds)" no
  mesure "rattrapage-deb : get secrets dans declencheurs" "$(peut "$RD" get secrets -n declencheurs)" no
  mesure "rattrapage : get triggertemplate sample-app-deb" "$(peut "$RI" get triggertemplates.triggers.tekton.dev/sample-app-deb -n declencheurs)" no
  mesure "el-forgejo : list triggers dans declencheurs" "$(peut "$EL" list triggers.triggers.tekton.dev -n declencheurs)" yes
  echo "## PipelineRun du gabarit, à blanc"
  pr_rendu a-blanc-s4d3
  kubectl get pipelinerun -n builds s4d-deb-1 -o json | jq -S '.spec' > "$T/s4d-deb-1.spec"
  for c in "el-forgejo|$EL" "rattrapage-deb|$RD"; do
    temoin "au nom de ${c%%|*}" "${c#*|}" "$T/pr-a-blanc-s4d3.json"
    if diff "$T/s4d-deb-1.spec" <(jq -S '.spec' "$T/temoin.json") > "$T/a-blanc.diff"; then echo "OK   spec admise identique à celle de s4d-deb-1"
    else sed 's/^/     /' "$T/a-blanc.diff"; echo "ÉCART spec admise différente de celle de s4d-deb-1"; ECARTS=$((ECARTS + 1)); fi
  done
  echo "## livraisons refusées (commit fictif $FAUX), adressées directement à l'EventListener"
  rm -rf "$T/webhook" && (umask 077 && mkdir -p "$T/webhook")
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  corps_push "$FAUX" b.json; envoyer "non signée" "$T/webhook/b.json" ""
  corps_push "$FAUX" c.json
  (umask 077 && openssl rand -hex 32 | tr -d '\n' > "$T/webhook/autre.secret")
  envoyer "autre secret" "$T/webhook/c.json" "$(python3 -I -c 'import hashlib, hmac, sys; print(hmac.new(open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read(), hashlib.sha256).hexdigest())' "$T/webhook/autre.secret" "$T/webhook/c.json")"
  corps_push "$TETE_J2" e.json; corps_push "$FAUX" d.json
  envoyer "corps modifié (signature valide d'un autre corps)" "$T/webhook/d.json" "$(hmac_corps "$T/webhook/e.json")"
  sleep 20
  refus_intercepteurs "$t0" | tee "$T/refus"
  mesure "refus « no X-Hub-Signature-256 header set » (un par trigger)" "$(grep -c 'no X-Hub-Signature-256 header set' "$T/refus" || true)" 2
  mesure "refus « payload signature check failed » (deux livraisons, deux triggers)" "$(grep -c 'payload signature check failed' "$T/refus" || true)" 4
  mesure "refus des intercepteurs, en tout" "$(grep -c . "$T/refus" || true)" 6
  mesure "PipelineRuns du commit fictif" "$(kubectl get pipelinerun -n builds -o name | grep -c "$FAUX" || true)" 0
  ecarts
}

etape_chemins() {
  local t0 j n u1 e0 a0 e1 a1
  rendre
  echo "## départ"
  attendu "$PR_DEB absent" "$(kubectl get pipelinerun -n builds "$PR_DEB" -o name 2>/dev/null || echo absent)" absent
  attendu "$PR_APP présent" "$(kubectl get pipelinerun -n builds "$PR_APP" -o name 2>/dev/null || echo absent)" "pipelinerun.tekton.dev/$PR_APP"
  attendu "tête de main dans Forgejo" "$(tete)" "$TETE_J2"
  attendu "CronJob rattrapage-deb suspendu" "$(kubectl get cronjob -n declencheurs rattrapage-deb -o jsonpath='{.spec.suspend}')" true
  attendu "PipelineRuns en cours dans builds" "$(kubectl get pipelineruns -n builds -o json | jq '[.items[] | select((.status.conditions[0].status // "Unknown") == "Unknown")] | length')" 0
  kubectl get pipelinerun -n builds s4d-deb-1 -o json | jq -S '.spec' > "$T/s4d-deb-1.spec"
  e0=$(envel "$DEB"); a0=$(envel "$APP")
  echo "enveloppes de Chains : $DEB $e0, $APP $a0"
  (umask 077 && mkdir -p "$T/auth")

  echo "## chemin 1 : livraison de Forgejo (tête de main)"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  attendu "Forgejo, POST hooks/…/tests" "HTTP $(forgejo_livrer)" "HTTP 204"
  chemin webhook "EventListener forgejo" declencheurs:el-forgejo "$t0"
  u1=$CHEMIN_UID
  el_existe "$t0" | tee "$T/existe-1"
  mesure "trigger de l'image : $PR_APP déjà présent" "$(grep -cF "\"$PR_APP\\\" already exists" "$T/existe-1" || true)" 1
  mesure "trigger du deb : aucun refus" "$(grep -cF "$PR_DEB" "$T/existe-1" || true)" 0

  echo "## chemin 2 : rattrapage ($PR_DEB purgé, CronJob rattrapage-deb repris, aucune livraison)"
  purger_pr "$PR_DEB"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  kubectl patch cronjob -n declencheurs rattrapage-deb --type merge -p '{"spec":{"suspend":false}}' > /dev/null
  for _ in $(seq 180); do kubectl get pipelinerun -n builds "$PR_DEB" > /dev/null 2>&1 && break; sleep 1; done
  : > "$T/passages.log"
  for j in $(kubectl get jobs -n declencheurs -o json | jq -r --arg t "$t0" '[.items[] | select(any(.metadata.ownerReferences[]?; .kind == "CronJob"
      and .name == "rattrapage-deb") and .metadata.creationTimestamp >= $t)] | sort_by(.metadata.creationTimestamp) | .[].metadata.name'); do
    kubectl wait -n declencheurs "job/$j" --for=condition=complete --timeout=120s > /dev/null || true
    journal_rattrapage "$j" | sed "s/^/$j/"
    sed "s/^/$j /" "$T/rattrapage.log" >> "$T/passages.log"
  done
  chemin rattrapage rattrapage declencheurs:rattrapage-deb "$t0"
  mesure "créations de $PR_DEB dans les passages de rattrapage-deb depuis la reprise" "$(grep -c " CREE|builds/$PR_DEB|commit $TETE_J2|depot $URL$" "$T/passages.log" || true)" 1
  [ "$CHEMIN_UID" != "$u1" ] && echo "OK   UID différent de celui du chemin 1" || { echo "ÉCART même UID qu'au chemin 1"; ECARTS=$((ECARTS + 1)); }
  if diff "$T/webhook.spec" "$T/rattrapage.spec" > /dev/null; then echo "OK   spec identique par les deux chemins"; else echo "ÉCART specs différentes selon le chemin"; ECARTS=$((ECARTS + 1)); fi
  j=$(passage "$t0" declencheurs rattrapage)
  journal_rattrapage "$j"
  mesure "rattrapage de l'image ($j)" "$(grep -c "^PRESENT|builds/$PR_APP$" "$T/rattrapage.log" || true)" 1

  echo "## rejeu de la livraison"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  attendu "Forgejo, POST hooks/…/tests" "HTTP $(forgejo_livrer)" "HTTP 204"
  for _ in $(seq 30); do el_existe "$t0" > "$T/existe-2"; [ "$(grep -c . "$T/existe-2" || true)" -ge 2 ] && break; sleep 2; done
  cat "$T/existe-2"
  mesure "rejeu : $PR_APP et $PR_DEB déjà présents" "$(grep -cF -e "\"$PR_APP\\\" already exists" -e "\"$PR_DEB\\\" already exists" "$T/existe-2" || true)" 2
  mesure "UID de $PR_DEB après le rejeu" "$(kubectl get pipelinerun -n builds "$PR_DEB" -o jsonpath='{.metadata.uid}')" "$CHEMIN_UID"
  echo "$CHEMIN_UID" > "$T/uid-chemin-2"

  echo "## fin"
  e1=$(envel "$DEB"); a1=$(envel "$APP")
  mesure "enveloppes de Chains sur $DEB" "$e0 → $e1" "$e0 → $((e0 + 4))"
  mesure "enveloppes de Chains sur $APP" "$a0 → $a1" "$a0 → $a0"
  mesure "CronJob rattrapage-deb repris" "$(kubectl get cronjob -n declencheurs rattrapage-deb -o jsonpath='{.spec.suspend}')" false
  ecarts
}

etape_porte() {
  local t j v
  [ -s "$T/uid-chemin-2" ] || { echo "KO   UID du chemin 2 absent (étape chemins)" >&2; exit 1; }
  attendu "PipelineRuns en cours dans builds" "$(kubectl get pipelineruns -n builds -o json | jq '[.items[] | select((.status.conditions[0].status // "Unknown") == "Unknown")] | length')" 0
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  j=$(passage "$t")
  echo "passage d'horodatage $j"
  mesure "provenance de PipelineRun la plus récente de $DEB (seule jugée)" \
    "$(prov_pr "$DEB" | jq -sr 'max_by(.predicate.runDetails.metadata.finishedOn).predicate.runDetails.metadata.invocationId')" "$(cat "$T/uid-chemin-2")"
  echo "## deb (prédictions : ec en succès sans violation ; horodatage 8/8 ; VSA et scan refusés, Job en échec, comme décidé)"
  v=$(juger s4d3-deb "$REG/$DEB" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$v"
  mesure "deb : succès de ec" "$(champ "$v" 3)" true
  mesure "deb : violations" "$(champ "$v" 4)" ""
  mesure "deb : avertissements" "$(champ "$v" 5)" trusted_task.tagged
  mesure "deb : horodatage" "$(champ "$v" 7)|$(champ "$v" 8 | cut -d' ' -f1)" "ok|8/8"
  mesure "deb : VSA" "$(champ "$v" 9)" refus
  mesure "deb : scan" "$(champ "$v" 11)" refus
  mesure "deb : règles du PoC parmi les succès" "$(jq -r '[.components[] | .successes[]? | .metadata.code | select(startswith("porte."))] | unique | join(",")' "$T/porte-s4d3-deb.json")" \
    porte.construction_kata,porte.fermeture_plateforme,porte.image_signature,porte.preparation_appariee,porte.taches_vues
  echo "## image sample-app (non-régression ; prédiction : verdict de s4d2-reelle)"
  v=$(juger s4d3-reelle "$REG/$APP" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$v"
  mesure "sample-app : succès, violations, avertissements" "$(champ "$v" 3)|$(champ "$v" 4)|$(champ "$v" 5)" "true||trusted_task.tagged"
  mesure "sample-app : horodatage" "$(champ "$v" 7)|$(champ "$v" 8 | cut -d' ' -f1)" "ok|28/28"
  mesure "sample-app : VSA, scan" "$(champ "$v" 9)|$(champ "$v" 11)" "ok|ok"
  ecarts
}

etape_retirer() {
  rendre
  kubectl delete -f "$T/declencheur.yaml" --ignore-not-found --wait=true
  echo "labelSelector laissé : $(kubectl get eventlistener -n declencheurs forgejo -o jsonpath='{.spec.labelSelector}') (aucun objet Trigger : $(kubectl get triggers.triggers.tekton.dev -n declencheurs -o name | wc -l))"
}

lancer s4d3 S4d3 "$@"
