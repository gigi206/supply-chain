#!/usr/bin/env bash
# Brique 08, jalon J8 : les 8 tests négatifs (doc 01), plan validé par le propriétaire le 30/10/2026 (README, « Préparation
# de J8 »). Une étape par test : prédiction écrite avant le premier passage, tentative depuis la zone build ou par le compte
# qu'un attaquant y viserait, témoin positif (l'essai sait voir ce qu'il cherche), trace dans resultats/preuves-<étape>.log.
# Les fonctions de J6 viennent de politique.sh, sourcé sans lancer ses étapes ; aucune étape existante n'est appelée (leurs
# journaux sont cités par le README). builds/sample-app@3a7ca1b1, l'image réelle, est relevée avant et après chaque étape :
# nombre d'enveloppes de Chains et provenance de PipelineRun la plus récente, seule jugée par la porte (Conforma v1.0.28).
#   test2  TaskRun à taskSpec en ligne et PipelineRun à pipelineSpec en ligne, créés pour de vrai (pas en dry-run), par
#          l'administrateur du cluster et par el-forgejo, seul compte qui crée des PipelineRuns dans builds ; témoins :
#          mêmes comptes, références signées par digest, admises (dry-run serveur) ; trace : refus de l'API (un seul webhook
#          nommé), événement PolicyViolation de Kyverno par objet refusé (sa propre barrière), audit de l'API
#   test4  pods créés pour de vrai dans builds au nom du contrôleur de Tekton, le compte qui crée les pods des TaskRuns : pod runc
#          privilégié (Pod Security restricted), pods Kata privilégiés avec hostPath ou en hostNetwork (exemptés de Pod Security
#          par la RuntimeClass kata, J7 : Kyverno pods-isolation seul) ; témoins : pod Kata privilégié et pod runc restreint,
#          admis (dry-run serveur) ; trace : refus de l'API, événements de Kyverno, audit de l'API et annotations de Pod Security
#   test5  livraisons vers l'EventListener de declencheurs : non signée, signée avec un autre secret, corps modifié sous une
#          signature valide ; rejeu à l'identique d'une livraison valide, nouvelle livraison de Forgejo pour la tête de main ;
#          témoin : livraison valide d'un commit propre au passage. Sans la purge de tekton.sh essais_webhook : les exécutions
#          de builds restent (construction de J7 comprise). Trace : journal des intercepteurs, journal de l'EventListener
# Aucun secret en argument de commande.
#
# Usage (racine du dépôt) : mise run confiance:preuves -- <étape>…   (journal : resultats/preuves-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/politique.sh"   # fonctions de J6 et commun.sh ; les étapes de politique.sh ne sont pas lancées
T=$W/preuves
trap 'rm -rf "$T/auth" "$T/webhook" "$W/refus.out"' EXIT
mkdir -p "$T"
EL=system:serviceaccount:declencheurs:el-forgejo
CONTROLEUR=system:serviceaccount:tekton-pipelines:tekton-pipelines-controller   # crée les pods des TaskRuns
APP=builds/sample-app@$APP_DIGEST

etat_app() { # enveloppes de Chains sur l'image réelle, et provenance de PipelineRun la plus récente (seule jugée par la porte)
  local n
  n=$(cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$APP" 2>/dev/null | grep -c . || true)
  echo "$n enveloppes, dernière provenance de PipelineRun : $(prov_pr "$APP" | jq -s -r 'sort_by(.predicate.runDetails.metadata.finishedOn)
    | last | "\(.predicate.runDetails.metadata.invocationId) (\(.predicate.runDetails.metadata.finishedOn))"')"
}

garder() { # avant|apres : l'image réelle n'est pas touchée par l'étape
  if [ "$1" = avant ]; then APP0=$(etat_app); echo "$APP avant l'étape : $APP0"; return; fi
  local a
  a=$(etat_app)
  [ "$a" = "$APP0" ] && echo "OK   $APP inchangée : $a" || { echo "KO   $APP modifiée : $a (avant : $APP0)" >&2; exit 1; }
}

tentative() { # libellé compte(admin|el|ctl) fichier : création réelle, refus attendu ; motif du refus dans $T/motif
  local as=()
  case $2 in el) as=(--as "$EL") ;; ctl) as=(--as "$CONTROLEUR") ;; esac
  if kubectl create "${as[@]}" -f "$3" > "$T/creation.out" 2>&1; then
    echo "KO   $1 : créé ($(tr '\n' ' ' < "$T/creation.out"))" >&2; kubectl delete -f "$3" --wait=false >/dev/null 2>&1 || true; exit 1
  fi
  tr '\n' ' ' < "$T/creation.out" | sed 's/^Error from server\( ([A-Za-z]*)\)\{0,1\}: //; s/^error when creating "[^"]*": //' | cut -c1-260 > "$T/motif"
}

temoin() { # libellé compte(admin|el|ctl) fichier : même compte, admis en dry-run serveur
  local as=()
  case $2 in el) as=(--as "$EL") ;; ctl) as=(--as "$CONTROLEUR") ;; esac
  kubectl create "${as[@]}" --dry-run=server -f "$3" > "$T/creation.out" 2>&1 \
    && echo "OK   témoin $1 : admis ($(tr '\n' ' ' < "$T/creation.out"))" \
    || { echo "KO   témoin $1 : refusé ($(tr '\n' ' ' < "$T/creation.out" | cut -c1-260))" >&2; exit 1; }
}

etape_test2() {
  local t0 busybox d c m
  garder avant
  echo "## prédiction (écrite le 30/10/2026, corrigée après le premier passage, archivé : preuves-test2-premier-passage.log)"
  echo "- TaskRun à taskSpec en ligne créé par l'administrateur, et PipelineRun à pipelineSpec en ligne créé par el-forgejo :"
  echo "  refusés à l'admission par deux barrières indépendantes, le webhook de Tekton (disable-inline-spec) et la règle"
  echo "  tekton-references de Kyverno. La réponse de l'API ne nomme qu'un refus (au premier passage, celui de Tekton) ; celui de"
  echo "  Kyverno se lit dans son événement PolicyViolation (« fail (blocked) »), un par objet refusé. TaskRun en ligne créé par"
  echo "  el-forgejo : refusé par RBAC avant l'admission (el-forgejo ne crée que des PipelineRuns), donc sans événement de Kyverno ;"
  echo "  aucun objet créé"
  echo "- témoins : TaskRun du bundle signé (administrateur) et PipelineRun du bundle signé (el-forgejo) admis en dry-run serveur"
  echo "- trace : refus de l'API ; un événement PolicyViolation de tekton-references par refus de Kyverno ; chaque requête dans"
  echo "  l'audit de l'API, avec le compte (l'administrateur apparaît comme emprunteur de l'identité d'el-forgejo)"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  busybox=$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")
  d=$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/tekton/tasks/essai-confiance:essai")
  rm -rf "$T/adm"
  python3 -I "$here/politique/cas-admission.py" "$T/adm" "$REG/tekton/tasks/essai-confiance@$d" "$busybox" oui
  for c in tr-en-ligne pr-en-ligne tr-bundle-signe pr-bundle-signe; do
    jq --arg n "preuve-t2-$c" '.metadata.name = $n' "$T/adm/$c.json" > "$T/t2-$c.json"
  done
  jq '.metadata.name = "preuve-t2-tr-en-ligne-el"' "$T/adm/tr-en-ligne.json" > "$T/t2-tr-en-ligne-el.json"
  echo "## tentatives (créations réelles)"
  tentative "TaskRun en ligne, administrateur" admin "$T/t2-tr-en-ligne.json"; m=$(cat "$T/motif")
  grep -F 'denied the request' "$T/motif" >/dev/null && echo "OK   TaskRun en ligne, administrateur : refusé à l'admission ($m)" \
    || { echo "KO   TaskRun en ligne, administrateur : $m" >&2; exit 1; }
  tentative "PipelineRun en ligne, el-forgejo" el "$T/t2-pr-en-ligne.json"; m=$(cat "$T/motif")
  grep -F 'denied the request' "$T/motif" >/dev/null && echo "OK   PipelineRun en ligne, el-forgejo : refusé à l'admission ($m)" \
    || { echo "KO   PipelineRun en ligne, el-forgejo : $m" >&2; exit 1; }
  tentative "TaskRun en ligne, el-forgejo" el "$T/t2-tr-en-ligne-el.json"; m=$(cat "$T/motif")
  grep -F 'cannot create resource "taskruns"' "$T/motif" >/dev/null && echo "OK   TaskRun en ligne, el-forgejo : refusé par RBAC ($m)" \
    || { echo "KO   TaskRun en ligne, el-forgejo : $m" >&2; exit 1; }
  echo "## témoins (dry-run serveur, mêmes comptes)"
  temoin "TaskRun du bundle signé, administrateur" admin "$T/t2-tr-bundle-signe.json"
  temoin "PipelineRun du bundle signé, el-forgejo" el "$T/t2-pr-bundle-signe.json"
  c=$(kubectl get taskruns,pipelineruns -n builds -o name | grep -c 'preuve-t2-' || true)
  [ "$c" = 0 ] && echo "OK   aucun objet preuve-t2-* dans builds" || { echo "KO   $c objet(s) preuve-t2-* créé(s)" >&2; exit 1; }
  echo "## trace : événements PolicyViolation de Kyverno depuis $t0"
  sleep 2
  kubectl get events -A --field-selector reason=PolicyViolation -o json | jq -r --arg t "$t0" '.items[]
    | select(((.lastTimestamp // .eventTime)[0:19]) >= ($t[0:19])) | "  \(.involvedObject.kind)/\(.involvedObject.name) : \(.message | .[0:200])"' \
    | tee "$T/t2-evenements.txt"
  for c in preuve-t2-tr-en-ligne: preuve-t2-pr-en-ligne:; do
    grep -F "tekton-references : " "$T/t2-evenements.txt" | grep -F "/$c fail (blocked)" >/dev/null \
      && echo "OK   Kyverno a bloqué ${c%:} (événement de tekton-references)" || { echo "KO   aucun blocage de Kyverno pour ${c%:}" >&2; exit 1; }
  done
  ! grep -F 'preuve-t2-tr-en-ligne-el' "$T/t2-evenements.txt" >/dev/null \
    && echo "OK   aucun événement de Kyverno pour preuve-t2-tr-en-ligne-el : refusé par RBAC avant l'admission" \
    || { echo "KO   événement de Kyverno pour preuve-t2-tr-en-ligne-el" >&2; exit 1; }
  echo "## trace : audit de l'API (requêtes preuve-t2-*, et créations de TaskRuns par el-forgejo : un refus de RBAC précède la"
  echo "## lecture du corps, la requête n'a donc pas de nom d'objet)"
  { audit_api preuve-t2-; audit_api el-forgejo | jq -c 'select(.verb == "create" and .objectRef.resource == "taskruns")'; } \
    | jq -s -r --arg t "$t0" '[.[] | select(.stageTimestamp[0:19] >= ($t[0:19]) and .stage == "ResponseComplete")] | unique_by(.auditID) | sort_by(.stageTimestamp) | .[]
    | "  \(.stageTimestamp[11:19]) \(.user.username)\(if .impersonatedUser then " (pour " + .impersonatedUser.username + ")" else "" end) \(.verb) \(.objectRef.resource)/\(.objectRef.name // "-")\(if (.requestURI | test("dryRun")) then " (dry-run)" else "" end) : \(.responseStatus.code)"' \
    | tee "$T/t2-audit.txt"
  c=$(grep -c -E ' : (400|403|422)$' "$T/t2-audit.txt" || true)
  [ "$c" -ge 3 ] && echo "OK   les 3 refus sont dans l'audit de l'API" || { echo "KO   $c refus dans l'audit de l'API (3 attendus)" >&2; exit 1; }
  garder apres
}

cas_j6() { # cas d'admission de J6 (cas-admission.py, bundle essai-confiance:essai) dans $T/adm
  local busybox d
  busybox=$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")
  d=$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/tekton/tasks/essai-confiance:essai")
  rm -rf "$T/adm"
  python3 -I "$here/politique/cas-admission.py" "$T/adm" "$REG/tekton/tasks/essai-confiance@$d" "$busybox" oui
}

pod_builds() { # cas nom filtre-jq : pod d'un cas de J6 (espace bancc) placé dans builds comme ceux des TaskRuns (zone build, sans
  # jeton de compte de service, sans relance), puis modifié par le filtre ; dans $T/<nom>.json
  jq --arg n "$2" '.metadata += {name: $n, namespace: "builds"} | .spec += {restartPolicy: "Never", serviceAccountName: "build",
    automountServiceAccountToken: false, nodeSelector: {zone: "build"},
    tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}]} | '"$3" "$T/adm/$1.json" > "$T/$2.json"
}

evenements_kyverno() { # depuis fichier : événements PolicyViolation de Kyverno depuis une date RFC 3339, copiés dans le fichier
  sleep 3
  kubectl get events -A --field-selector reason=PolicyViolation -o json | jq -r --arg t "$1" '.items[]
    | select(((.lastTimestamp // .eventTime)[0:19]) >= ($t[0:19])) | "  \(.involvedObject.kind)/\(.involvedObject.name) : \(.message | .[0:200])"' \
    | tee "$2"
}

etape_test4() {
  local t0 c m
  garder avant
  echo "## prédiction (écrite le 30/10/2026, avant le premier passage)"
  echo "- tentatives au nom du contrôleur de Tekton, le compte qui crée les pods des TaskRuns dans builds (créations réelles) :"
  echo "  pod runc privilégié : refusé par Pod Security (restricted en enforce sur builds, HTTP 403). Pod Security est une extension"
  echo "  d'admission intégrée, appelée avant les webhooks, et le premier refus arrête l'admission : Kyverno n'est pas consulté, donc"
  echo "  aucun événement de pods-isolation pour ce pod (J6 a mesuré cette règle de Kyverno seule, dans bancc, sans Pod Security)."
  echo "  Pod Kata privilégié avec un volume hostPath, et pod Kata privilégié en hostNetwork : exemptés de Pod Security (RuntimeClass"
  echo "  kata, J7), refusés par la règle pods-isolation de Kyverno (HTTP 400), seule barrière ; un événement PolicyViolation par pod"
  echo "- témoins (même compte, dry-run serveur) : pod Kata privilégié sans hostPath ni hostNetwork, et pod runc restreint : admis"
  echo "- trace : refus de l'API ; événements de Kyverno ; audit de l'API, avec l'annotation de Pod Security : enforce-policy"
  echo "  restricted:latest pour les pods runc, exempt runtimeClass pour les pods Kata, y compris ceux que Kyverno refuse ensuite"
  echo "- hors de ce test, déjà mesurée : la voie d'un PipelineRun (podTemplate avec volume refusé par tekton-references, cas de J6 ;"
  echo "  construction sans runtimeClassName : pod refusé par Pod Security, construction-construire.log)"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cas_j6
  pod_builds pod-privilegie preuve-t4-runc-privilegie .
  pod_builds pod-privilegie-kata preuve-t4-kata-hostpath \
    '.spec.volumes = [{name: "h", hostPath: {path: "/var/lib/rancher"}}] | .spec.containers[0].volumeMounts = [{name: "h", mountPath: "/h"}]'
  pod_builds pod-privilegie-kata preuve-t4-kata-hostnetwork '.spec.hostNetwork = true'
  pod_builds pod-privilegie-kata preuve-t4-kata-privilegie .
  pod_builds pod-restreint preuve-t4-runc-restreint .
  echo "## tentatives (créations réelles, au nom de $CONTROLEUR)"
  tentative "pod runc privilégié" ctl "$T/preuve-t4-runc-privilegie.json"; m=$(cat "$T/motif")
  grep -F 'violates PodSecurity "restricted:latest": privileged' "$T/motif" >/dev/null \
    && echo "OK   pod runc privilégié : refusé par Pod Security ($m)" || { echo "KO   pod runc privilégié : $m" >&2; exit 1; }
  tentative "pod Kata privilégié avec hostPath" ctl "$T/preuve-t4-kata-hostpath.json"; m=$(cat "$T/motif")
  grep -F 'Policy pods-isolation failed: test 4 : volume hostPath interdit' "$T/motif" >/dev/null \
    && echo "OK   pod Kata privilégié avec hostPath : refusé par Kyverno ($m)" || { echo "KO   pod Kata privilégié avec hostPath : $m" >&2; exit 1; }
  tentative "pod Kata privilégié en hostNetwork" ctl "$T/preuve-t4-kata-hostnetwork.json"; m=$(cat "$T/motif")
  grep -F 'Policy pods-isolation failed: test 4 : hostNetwork, hostPID et hostIPC interdits' "$T/motif" >/dev/null \
    && echo "OK   pod Kata privilégié en hostNetwork : refusé par Kyverno ($m)" || { echo "KO   pod Kata privilégié en hostNetwork : $m" >&2; exit 1; }
  echo "## témoins (dry-run serveur, même compte)"
  temoin "pod Kata privilégié" ctl "$T/preuve-t4-kata-privilegie.json"
  temoin "pod runc restreint" ctl "$T/preuve-t4-runc-restreint.json"
  c=$(kubectl get pods -n builds -o name | grep -c 'preuve-t4-' || true)
  [ "$c" = 0 ] && echo "OK   aucun pod preuve-t4-* dans builds" || { echo "KO   $c pod(s) preuve-t4-* créé(s)" >&2; exit 1; }
  echo "## trace : événements PolicyViolation de Kyverno depuis $t0"
  evenements_kyverno "$t0" "$T/t4-evenements.txt"
  for c in preuve-t4-kata-hostpath: preuve-t4-kata-hostnetwork:; do
    grep -F "pods-isolation : " "$T/t4-evenements.txt" | grep -F "/$c fail (blocked)" >/dev/null \
      && echo "OK   Kyverno a bloqué ${c%:} (événement de pods-isolation)" || { echo "KO   aucun blocage de Kyverno pour ${c%:}" >&2; exit 1; }
  done
  ! grep -F 'preuve-t4-runc-privilegie' "$T/t4-evenements.txt" >/dev/null \
    && echo "OK   aucun événement de Kyverno pour preuve-t4-runc-privilegie : refusé par Pod Security, Kyverno non consulté" \
    || { echo "KO   événement de Kyverno pour preuve-t4-runc-privilegie" >&2; exit 1; }
  echo "## trace : audit de l'API (créations de pods preuve-t4-*, annotation de Pod Security)"
  audit_api preuve-t4- | jq -s -r --arg t "$t0" '[.[] | select(.stageTimestamp[0:19] >= ($t[0:19]) and .stage == "ResponseComplete"
      and .objectRef.resource == "pods")] | unique_by(.auditID) | sort_by(.stageTimestamp) | .[]
    | "  \(.stageTimestamp[11:19]) \(.user.username)\(if .impersonatedUser then " (pour " + .impersonatedUser.username + ")" else "" end) \(.verb) pods/\(.objectRef.name)\(if (.requestURI | test("dryRun")) then " (dry-run)" else "" end) : \(.responseStatus.code) ; Pod Security : \(if .annotations["pod-security.kubernetes.io/exempt"] then "exempt " + .annotations["pod-security.kubernetes.io/exempt"] else "enforce-policy " + (.annotations["pod-security.kubernetes.io/enforce-policy"] // "-") end)"' \
    | tee "$T/t4-audit.txt"
  for c in 'runc-privilegie : 403 ; Pod Security : enforce-policy restricted:latest' 'kata-hostpath : 400 ; Pod Security : exempt runtimeClass' \
    'kata-hostnetwork : 400 ; Pod Security : exempt runtimeClass'; do
    grep -F "(pour $CONTROLEUR) create pods/preuve-t4-$c" "$T/t4-audit.txt" >/dev/null \
      && echo "OK   audit : preuve-t4-$c" || { echo "KO   audit : preuve-t4-$c absent" >&2; exit 1; }
  done
  garder apres
}

corps_push() { # commit fichier : corps d'un événement push de workspace/sample-app sur main, comme Forgejo (champs lus par le Trigger)
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

el_existe() { # depuis : erreurs « already exists » de l'EventListener (PipelineRun déjà présent), une ligne JSON par erreur
  kubectl logs -n "$EL_NS" deploy/el-forgejo --since-time="$1" \
    | jq -Rc 'fromjson? | select(.severity == "error" and (.message | startswith("couldn'"'"'t create resource")))
      | {t: .timestamp[11:19], eventID: ."/triggers-eventid", erreur: (.message | capture("(?<e>pipelineruns.tekton.dev .* already exists)").e)}'
}

etape_test5() {
  local t0 reel=6391fd437f26696847041be3226bbbf633f55a2f faux=1111111111111111111111111111111111111111 neuf sig_e ev_f c o
  garder avant
  EL_NS=declencheurs
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  neuf=$(printf 'preuves.sh test5 %s' "$t0" | sha1sum | cut -c1-40)   # commit du témoin, propre au passage : jamais livré avant
  rm -rf "$T/webhook" "$T/auth" && (umask 077 && mkdir -p "$T/webhook" "$T/auth")
  echo "## prédiction (écrite le 30/10/2026, avant le premier passage)"
  echo "- l'EventListener répond HTTP 202 à chaque livraison, avant les intercepteurs : l'émetteur n'apprend rien du refus"
  echo "- commit $faux : livraison non signée, signée avec un autre secret, et corps modifié sous la signature valide d'un"
  echo "  autre corps : refusées par l'intercepteur github (FailedPrecondition : une fois « no X-Hub-Signature-256 header set », deux"
  echo "  fois « payload signature check failed ») ; aucun PipelineRun. L'EventListener ne journalise ces refus qu'au niveau debug"
  echo "  (« interceptor stopped trigger processing », pkg/sink/sink.go de Triggers v0.37.2), absent au niveau info en service : leur"
  echo "  trace est le journal des intercepteurs, pas celui de l'EventListener"
  echo "- témoin : livraison valide du commit $neuf (propre à ce passage) : PipelineRun sample-app-<commit> créé par"
  echo "  l'EventListener, terminé, signé par Chains (TaskRun et PipelineRun)"
  echo "- rejeu à l'identique du témoin (même corps, même signature), et nouvelle livraison de Forgejo pour la tête de main ($reel,"
  echo "  dont le PipelineRun existe) : acceptés par les intercepteurs, puis refusés à la création (« already exists » dans le journal"
  echo "  de l'EventListener, avec l'eventID de la livraison rejouée) ; un seul PipelineRun par commit"
  echo "- limite connue, non éprouvée ici : l'anti-rejeu dure tant que le PipelineRun existe (J4)"
  echo "## livraisons refusées (commit $faux)"
  corps_push "$faux" b.json; envoyer "non signée" "$T/webhook/b.json" ""
  corps_push "$faux" c.json
  (umask 077 && openssl rand -hex 32 | tr -d '\n' > "$T/webhook/autre.secret")
  envoyer "autre secret" "$T/webhook/c.json" "$(python3 -I -c 'import hashlib, hmac, sys; print(hmac.new(open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read(), hashlib.sha256).hexdigest())' "$T/webhook/autre.secret" "$T/webhook/c.json")"
  corps_push "$neuf" e.json; corps_push "$faux" d.json
  envoyer "corps modifié (signature valide du corps du témoin)" "$T/webhook/d.json" "$(hmac_corps "$T/webhook/e.json")"
  echo "## témoin : livraison valide (commit $neuf)"
  sig_e=$(hmac_corps "$T/webhook/e.json")
  envoyer "valide" "$T/webhook/e.json" "$sig_e"
  pr_attendre "$neuf"
  signe_attendre "$neuf"
  non_repris "$neuf"
  [ -n "$(kubectl get pipelinerun -n builds "sample-app-$neuf" -o jsonpath='{.metadata.labels.triggers\.tekton\.dev/eventlistener}')" ] \
    && echo "OK   PipelineRun sample-app-$neuf créé par l'EventListener, $(kubectl get pipelinerun -n builds "sample-app-$neuf" -o jsonpath='{.status.conditions[0].reason}')" \
    || { echo "KO   sample-app-$neuf créé hors de l'EventListener" >&2; exit 1; }
  for o in "taskrun/sample-app-$neuf-publier" "pipelinerun/sample-app-$neuf"; do
    [ "$(kubectl get -n builds "$o" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')" = true ] \
      && echo "OK   $o signé par Chains" || { echo "KO   $o non signé" >&2; exit 1; }
  done
  echo "## rejeux"
  envoyer "rejeu à l'identique du témoin" "$T/webhook/e.json" "$sig_e"
  ev_f=$(jq -r .eventID "$T/webhook/reponse")
  echo "Forgejo, nouvelle livraison pour la tête de main : HTTP $(forgejo_livrer)"
  for _ in $(seq 30); do
    el_existe "$t0" > "$T/webhook/existe"
    grep -F "\"eventID\":\"$ev_f\"" "$T/webhook/existe" >/dev/null && grep -F "sample-app-$reel\\\" already exists" "$T/webhook/existe" >/dev/null && break
    sleep 2
  done
  echo "## bilan (PipelineRuns par commit)"
  echo "commit $faux : $(nb_pr "$faux") ; témoin $neuf : $(nb_pr "$neuf") ; tête de main $reel : $(nb_pr "$reel")"
  [ "$(nb_pr "$faux")" = 0 ] && echo "OK   livraisons non signée, d'un autre secret, à corps modifié : aucun PipelineRun" \
    || { echo "KO   livraison non signée ou falsifiée acceptée" >&2; exit 1; }
  [ "$(nb_pr "$neuf")" = 1 ] && [ "$(nb_pr "$reel")" = 1 ] && echo "OK   rejeux sans effet : un seul PipelineRun par commit" \
    || { echo "KO   rejeu accepté" >&2; exit 1; }
  echo "## trace : refus des intercepteurs (service tekton-triggers-core-interceptors) depuis $t0"
  kubectl logs -n tekton-pipelines deploy/tekton-triggers-core-interceptors --since-time="$t0" \
    | jq -Rc 'fromjson? | select((.msg // "") | test("Continue:false")) | {t: (.ts | todate | .[11:19]), refus: (.msg | capture("Code:(?<code>[A-Za-z]+) Message:(?<message>[^}]*)"))}' \
    | tee "$T/webhook/refus"
  c=$(grep -c '"code":"FailedPrecondition","message":"no X-Hub-Signature-256 header set"' "$T/webhook/refus" || true)
  [ "$c" = 1 ] && echo "OK   livraison non signée refusée par l'intercepteur github" || { echo "KO   $c refus « no X-Hub-Signature-256 header set » (1 attendu)" >&2; exit 1; }
  c=$(grep -c '"code":"FailedPrecondition","message":"payload signature check failed"' "$T/webhook/refus" || true)
  [ "$c" = 2 ] && echo "OK   autre secret et corps modifié refusés par l'intercepteur github" || { echo "KO   $c refus « payload signature check failed » (2 attendus)" >&2; exit 1; }
  c=$(grep -c . "$T/webhook/refus" || true)
  [ "$c" = 3 ] && echo "OK   3 refus des intercepteurs, aucun autre (rejeux acceptés par les intercepteurs)" || { echo "KO   $c refus des intercepteurs (3 attendus)" >&2; exit 1; }
  echo "## trace : EventListener, créations refusées (already exists) depuis $t0"
  cat "$T/webhook/existe"
  grep -F "\"eventID\":\"$ev_f\"" "$T/webhook/existe" | grep -F "sample-app-$neuf\\\" already exists" >/dev/null \
    && echo "OK   rejeu du témoin (eventID $ev_f) : PipelineRun sample-app-$neuf déjà présent" || { echo "KO   rejeu du témoin absent du journal" >&2; exit 1; }
  grep -F "sample-app-$reel\\\" already exists" "$T/webhook/existe" >/dev/null \
    && echo "OK   nouvelle livraison de Forgejo : PipelineRun sample-app-$reel déjà présent" || { echo "KO   livraison de Forgejo absente du journal" >&2; exit 1; }
  c=$(kubectl logs -n "$EL_NS" deploy/el-forgejo --since-time="$t0" | grep -c 'interceptor stopped trigger processing' || true)
  [ "$c" = 0 ] && echo "OK   EventListener : aucune ligne « interceptor stopped trigger processing » (niveau debug, non journalisé en service)" \
    || echo "CONSTAT EventListener : $c ligne(s) « interceptor stopped trigger processing » (prédiction : aucune)"
  garder apres
}

lancer preuves J8 "$@"
