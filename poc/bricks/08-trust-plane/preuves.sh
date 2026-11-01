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
#   test3  TaskRun publier terminé et signé, créé par une livraison valide (commit propre au passage) : écritures réelles (PUT)
#          du statut falsifié et de l'objet sans l'annotation de Chains, au nom de build, el-forgejo, des opérateurs et du
#          rattrapage ; témoin : écriture du statut par l'administrateur, puis Chains ne re-signe pas (annotation, audit
#          d'OpenBao, enveloppes, sujet de la provenance) ; trace : refus de l'API, audit de l'API ; PipelineRun purgé à la fin
#   test1  tâche signée par la clé des tâches, propre au test (bundle tekton/tasks/preuve-test1, hors de la liste revue), exécutée
#          dans builds : jeton monté, variables, OpenBao par le service et par l'IP du pod ; témoins : Zot et Forgejo depuis la
#          même étape, OpenBao descellé, signatures de Chains dans l'audit d'OpenBao ; trace : Hubble des deux agents, audit
#          d'OpenBao filtré sur l'adresse du pod
#   test5  livraisons vers l'EventListener de declencheurs : non signée, signée avec un autre secret, corps modifié sous une
#          signature valide ; rejeu à l'identique d'une livraison valide, nouvelle livraison de Forgejo pour la tête de main ;
#          témoin : livraison valide d'un commit propre au passage. Sans la purge de tekton.sh essais_webhook : les exécutions
#          de builds restent (construction de J7 comprise). Trace : journal des intercepteurs, journal de l'EventListener
#   test6  contrôle de conformité des barrières réseau de la zone build sur un TaskRun réel : tâche de vérification signée par la
#          clé des tâches, du nom construire-image (bundle tekton/tasks/preuve-test6-test, hors de la liste revue), étape
#          construire privilégiée sous Kata, image BuildKit : connexions vers Zot, Forgejo, l'API (nœud et service) et une adresse
#          externe, puis avec une adresse source inutilisée (vérification d'adresse source de Cilium) ; contre-épreuve : même
#          tâche, seul le nom change (non sélectionnée par construction-sans-sortie). Trace : Hubble de sc-build, capture sur enp1s0
#   reglec règle porte.construction_kata (option (c) des internalParameters) jugée par la porte du cluster : image réelle
#          (clé de Chains), puis images témoins d'essais-j8/regle-c signées par une clé jetable et munies de la provenance réelle,
#          sujet réécrit : intacte, runtimeClassName retiré du seul TaskRun construire (taskRunSpecs gardés à kata), runc ;
#          même Job, même politique, ConfigMap porte-temoin (clé publique jetable). Trace : verdicts de ec, motifs
#   test7  porte de release du cluster, source attendue fournie (--images, commit du script comparé à la tête de Forgejo) : image
#          réelle, mauvaise révision, mauvaise URL ; même digest dans builds/essai-images (poussé par poc-images, sans Chains) ;
#          ordre des provenances, par des témoins d'essais-j8/test7 signés par une clé jetable (provenance réelle listée, et la même
#          citant construire-image c7e8b275, retirée de la liste : seule, plus récente, plus ancienne, à égalité, sans date), puis
#          par de vraies signatures de Chains sur builds/essai-webhook (tâche signée hors liste, bundle tekton/tasks/preuve-test7,
#          puis gabarit en service). Trace : verdicts de ec, motifs, provenances du tag .att
#   attseule complément du test 7 : témoin d'essais-j8/test7 à attestation signée (clé jetable) sans signature d'image (constat
#          du banc C), jugé par la porte avec la source attendue. Trace : verdict de ec, motifs
#   test8  contrôle 9 joint à la porte du cluster (conteneur horodatage après ec, politique/porte/horodatage.sh) : chaque attestation
#          vérifiée par ec doit avoir un bundle horodaté valide qui porte sa signature ; image réelle avec horodatage/bundles, puis
#          dépôts d'essai écrits par poc-horodatage (horodatage/essais-test8) : copie, aucun, partiel, sans jeton, jeton altéré,
#          jetons échangés, TSA étrangère, bundles d'une autre image de même digest, bundle valide d'un autre digest, mélange ;
#          ancien contrôle de J6 sur les mêmes dépôts ; image sans Chains ; format bundle de cosign v3 (témoins d'essais-j8/test8,
#          clé jetable : attestation seule, signature et attestation). Trace : verdicts de ec et du contrôle 9, motifs de cosign
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
BUILDKIT=$REG/amont/moby/buildkit@sha256:ace6811c21334fa502644b9711e0ea48e8539c5c2a843c2325dfb7b987ab260b   # construction.sh
USURPEE=10.42.1.250     # adresse du sous-réseau des pods de sc-build, inutilisée (kata.sh ; contrôlé avant l'essai)
EXTERNE=203.0.113.10    # adresse de documentation (RFC 5737), hors du cluster (kata.sh)

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

comme() { # compte : identité empruntée par kubectl, dans le tableau AS (admin : l'administrateur du cluster, sans emprunt)
  case $1 in
    admin) AS=() ;;
    el) AS=(--as "$EL") ;;
    ctl) AS=(--as "$CONTROLEUR") ;;
    build) AS=(--as system:serviceaccount:builds:build) ;;              # compte des TaskRuns
    operateur) AS=(--as operateur --as-group operateurs) ;;             # opérateurs des builds (J6, politique/droits.yaml)
    rattrapage) AS=(--as system:serviceaccount:declencheurs:rattrapage) ;;
    *) echo "KO   compte inconnu : $1" >&2; exit 1 ;;
  esac
}

tentative() { # libellé compte (voir comme) fichier : création réelle, refus attendu ; motif du refus dans $T/motif
  comme "$2"
  if kubectl create "${AS[@]}" -f "$3" > "$T/creation.out" 2>&1; then
    echo "KO   $1 : créé ($(tr '\n' ' ' < "$T/creation.out"))" >&2; kubectl delete -f "$3" --wait=false >/dev/null 2>&1 || true; exit 1
  fi
  tr '\n' ' ' < "$T/creation.out" | sed 's/^Error from server\( ([A-Za-z]*)\)\{0,1\}: //; s/^error when creating "[^"]*": //' | cut -c1-260 > "$T/motif"
}

temoin() { # libellé compte (voir comme) fichier : même compte, admis en dry-run serveur
  comme "$2"
  kubectl create "${AS[@]}" --dry-run=server -f "$3" > "$T/creation.out" 2>&1 \
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

nb_enveloppes() { cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$1" 2>/dev/null | grep -c . || true; }   # dépôt@digest

bao_chains() { # depuis : signatures par la clé Transit chains (réponses de l'audit d'OpenBao) depuis une date RFC 3339, une ligne JSON chacune
  kubectl exec -n openbao openbao-0 -- cat /openbao/data/audit.log | jq -c --arg d "$1" 'select(.type == "response" and .time[0:19] >= ($d[0:19])
    and (.request.path | startswith("transit/sign/chains"))) | {t: .time[0:19], chemin: .request.path, compte: .auth.display_name}'
}

etape_test3() {
  local t0 t1 neuf tr uid i v n0 n1 compte faux=sha256:0000000000000000000000000000000000000000000000000000000000000000
  local essai=builds/essai-webhook@$APP_DIGEST
  garder avant
  EL_NS=declencheurs
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  neuf=$(printf 'preuves.sh test3 %s' "$t0" | sha1sum | cut -c1-40)   # commit propre au passage
  tr=sample-app-$neuf-publier
  rm -rf "$T/webhook" "$T/auth" && (umask 077 && mkdir -p "$T/webhook" "$T/auth")
  echo "## prédiction (écrite le 30/10/2026, avant le premier passage)"
  echo "- cible : le TaskRun publier d'un PipelineRun créé par une livraison valide (commit $neuf, propre au passage),"
  echo "  terminé et signé par Chains : 3 signatures par la clé Transit chains dans l'audit d'OpenBao (signature de l'image et"
  echo "  provenance du TaskRun, provenance du PipelineRun), comme au test 5"
  echo "- tentatives réelles, au nom du compte des TaskRuns (build), d'el-forgejo, des opérateurs et du rattrapage : écriture"
  echo "  du résultat IMAGE_DIGEST falsifié (PUT de la sous-ressource status), puis de l'objet sans l'annotation"
  echo "  chains.tekton.dev/signed (PUT de la ressource principale) : refusées par RBAC (403, verbe update), chaque requête dans"
  echo "  l'audit de l'API avec le nom de l'objet (présent dans l'URL). Corrigée après le premier passage (archivé) : kubectl patch"
  echo "  lisait d'abord l'objet, refus sur la lecture, que la politique d'audit ne journalise pas"
  echo "- témoin : la même écriture du statut par l'administrateur est acceptée ; le statut falsifié n'est pas réécrit par le"
  echo "  contrôleur de Pipelines (un TaskRun terminé n'est plus recalculé)"
  echo "- Chains ne re-signe pas : dans les 45 s qui suivent, annotation toujours true, aucune signature par la clé chains dans"
  echo "  l'audit d'OpenBao, même nombre d'enveloppes sur $essai, et la provenance de ce TaskRun (invocationId"
  echo "  = UID du TaskRun) garde son sujet d'origine, tiré du résultat IMAGE_DIGEST à la signature. Lu dans le code de Chains"
  echo "  v0.29.9 (annotations.go, Reconciled ; reconciler/taskrun/taskrun.go) : un TaskRun terminé dont l'annotation vaut true ou"
  echo "  failed est sauté"
  echo "- limite lue dans ce même code, non mesurée (elle laisserait dans Zot une attestation falsifiée validement signée, que"
  echo "  poc-ecriture ne peut pas supprimer) : sans l'annotation, Chains signerait le TaskRun tel qu'il est ; la retirer demande"
  echo "  un droit de modification des TaskRuns (administrateurs, contrôleurs de Pipelines et de Chains, droits de J6)"
  echo "- fin : PipelineRun purgé, pour ne laisser aucun statut falsifié dans builds"
  echo "## mise en place : livraison valide (commit $neuf)"
  corps_push "$neuf" e.json
  envoyer "valide" "$T/webhook/e.json" "$(hmac_corps "$T/webhook/e.json")"
  pr_attendre "$neuf"
  signe_attendre "$neuf"
  non_repris "$neuf"
  [ "$(kubectl get taskrun -n builds "$tr" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')" = true ] \
    && echo "OK   $tr terminé ($(kubectl get taskrun -n builds "$tr" -o jsonpath='{.status.conditions[0].reason}')) et signé par Chains" \
    || { echo "KO   $tr non signé" >&2; exit 1; }
  uid=$(kubectl get taskrun -n builds "$tr" -o jsonpath='{.metadata.uid}')
  kubectl get taskrun -n builds "$tr" -o json | jq -c '.status.results' > "$T/t3-resultats.json"
  i=$(jq '[.[].name] | index("IMAGE_DIGEST")' "$T/t3-resultats.json")
  n0=$(nb_enveloppes "$essai")
  echo "état avant : UID $uid, résultats $(cat "$T/t3-resultats.json"), $n0 enveloppes sur $essai"
  # Écritures réelles par l'API brute (PUT, verbe update) : kubectl patch lit d'abord l'objet, et un compte sans droit de lecture
  # est alors refusé sur la lecture (non journalisée par la politique d'audit), pas sur l'écriture (premier passage, archivé).
  kubectl get taskrun -n builds "$tr" -o json > "$T/t3-objet.json"
  jq --arg f "$faux" '(.status.results[] | select(.name == "IMAGE_DIGEST") | .value) = $f' "$T/t3-objet.json" > "$T/t3-statut.json"
  jq 'del(.metadata.annotations["chains.tekton.dev/signed"])' "$T/t3-objet.json" > "$T/t3-sans-annotation.json"
  echo "## tentatives (écritures réelles : PUT du statut falsifié, PUT de l'objet sans l'annotation de Chains)"
  for compte in build el operateur rattrapage; do
    comme "$compte"
    if kubectl replace --raw "/apis/tekton.dev/v1/namespaces/builds/taskruns/$tr/status" -f "$T/t3-statut.json" "${AS[@]}" > "$T/patch.out" 2>&1; then
      echo "KO   $compte : statut modifié" >&2; exit 1
    fi
    grep -E 'cannot update resource \\?"taskruns/status\\?"' "$T/patch.out" >/dev/null \
      && echo "OK   $compte : écriture du statut refusée par RBAC ($(tr '\n' ' ' < "$T/patch.out" | cut -c1-230))" \
      || { echo "KO   $compte : $(tr '\n' ' ' < "$T/patch.out")" >&2; exit 1; }
    if kubectl replace --raw "/apis/tekton.dev/v1/namespaces/builds/taskruns/$tr" -f "$T/t3-sans-annotation.json" "${AS[@]}" > "$T/patch.out" 2>&1; then
      echo "KO   $compte : annotation de Chains retirée" >&2; exit 1
    fi
    grep -E 'cannot update resource \\?"taskruns\\?"' "$T/patch.out" >/dev/null \
      && echo "OK   $compte : retrait de l'annotation de Chains refusé par RBAC" || { echo "KO   $compte : $(tr '\n' ' ' < "$T/patch.out")" >&2; exit 1; }
  done
  echo "## témoin : même écriture du statut par l'administrateur"
  t1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  kubectl replace --raw "/apis/tekton.dev/v1/namespaces/builds/taskruns/$tr/status" -f "$T/t3-statut.json" > "$T/patch.out" 2>&1 \
    && echo "OK   administrateur : statut écrit (IMAGE_DIGEST renvoyé par l'API : $(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$T/patch.out"))" \
    || { echo "KO   administrateur : $(cat "$T/patch.out")" >&2; exit 1; }
  echo "## Chains ne re-signe pas (45 s d'attente après l'écriture, $t1)"
  sleep 45
  v=$(kubectl get taskrun -n builds "$tr" -o json | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
  [ "$v" = "$faux" ] && echo "OK   statut falsifié conservé (IMAGE_DIGEST = $v) : le contrôleur de Pipelines ne le réécrit pas" \
    || echo "CONSTAT IMAGE_DIGEST réécrit en $v (prédiction : statut falsifié conservé)"
  v=$(kubectl get taskrun -n builds "$tr" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')
  [ "$v" = true ] && echo "OK   annotation chains.tekton.dev/signed toujours $v" || { echo "KO   annotation : $v" >&2; exit 1; }
  bao_chains "$t0" > "$T/t3-bao.txt"
  echo "signatures par la clé chains depuis $t0 (audit d'OpenBao) :"; sed 's/^/  /' "$T/t3-bao.txt"
  v=$(jq -c --arg t "$t1" 'select(.t < ($t[0:19]))' "$T/t3-bao.txt" | grep -c . || true)
  [ "$v" = 3 ] && echo "OK   témoin : 3 signatures de Chains avant l'écriture, pour cette exécution" || { echo "KO   $v signature(s) de Chains avant l'écriture (3 attendues)" >&2; exit 1; }
  v=$(jq -c --arg t "$t1" 'select(.t >= ($t[0:19]))' "$T/t3-bao.txt" | grep -c . || true)
  [ "$v" = 0 ] && echo "OK   aucune signature de Chains depuis l'écriture" || { echo "KO   $v signature(s) de Chains depuis l'écriture" >&2; exit 1; }
  n1=$(nb_enveloppes "$essai")
  [ "$n1" = "$n0" ] && echo "OK   $n1 enveloppes sur $essai, comme avant l'écriture" || { echo "KO   $n1 enveloppes (avant : $n0)" >&2; exit 1; }
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$essai" 2>/dev/null | jq -c --arg u "$uid" '.payload | @base64d | fromjson
    | select(.predicate.runDetails.metadata.invocationId == $u) | [.subject[] | "\(.name)@sha256:\(.digest.sha256)"]' > "$T/t3-sujets.txt"
  [ "$(cat "$T/t3-sujets.txt")" = "[\"$REG/$essai\"]" ] && echo "OK   une provenance pour ce TaskRun, sujet d'origine : $(cat "$T/t3-sujets.txt")" \
    || { echo "KO   provenance de ce TaskRun : $(cat "$T/t3-sujets.txt")" >&2; exit 1; }
  echo "## trace : audit de l'API (écritures de l'administrateur, emprunts compris, sur $tr)"
  audit_api "$tr" | jq -s -r --arg t "$t0" '[.[] | select(.stageTimestamp[0:19] >= ($t[0:19]) and .stage == "ResponseComplete" and .verb == "update"
      and .user.username == "system:admin")] | unique_by(.auditID) | sort_by(.stageTimestamp) | .[]
    | "  \(.stageTimestamp[11:19]) \(.user.username)\(if .impersonatedUser then " (pour " + .impersonatedUser.username + ")" else "" end) \(.verb) \(.objectRef.resource)/\(.objectRef.name // "-")\(if .objectRef.subresource then "/" + .objectRef.subresource else "" end) : \(.responseStatus.code)"' \
    | tee "$T/t3-audit.txt"
  v=$(grep -c "(pour .*) update taskruns/$tr/status : 403$" "$T/t3-audit.txt" || true)
  [ "$v" = 4 ] && echo "OK   4 écritures du statut refusées dans l'audit, avec le nom de l'objet" || { echo "KO   $v écriture(s) du statut refusées dans l'audit (4 attendues)" >&2; exit 1; }
  v=$(grep -c "(pour .*) update taskruns/$tr : 403$" "$T/t3-audit.txt" || true)
  [ "$v" = 4 ] && echo "OK   4 retraits d'annotation refusés dans l'audit" || { echo "KO   $v retrait(s) d'annotation refusés dans l'audit (4 attendus)" >&2; exit 1; }
  grep -E "^  [0-9:]+ system:admin update taskruns/$tr/status : 200$" "$T/t3-audit.txt" >/dev/null \
    && echo "OK   écriture de l'administrateur dans l'audit (200)" || { echo "KO   écriture de l'administrateur absente de l'audit" >&2; exit 1; }
  echo "## fin : PipelineRun sample-app-$neuf purgé (aucun statut falsifié laissé dans builds ; ses enveloppes restent dans Zot)"
  purger_pr "sample-app-$neuf"
  [ "$(nb_pr "$neuf")" = 0 ] && ! kubectl get taskrun -n builds "$tr" >/dev/null 2>&1 \
    && echo "OK   PipelineRun et TaskRun de $neuf supprimés" || { echo "KO   exécution de $neuf encore présente" >&2; exit 1; }
  garder apres
}

ligne_t1() { sed -n "s/^$1|//p" "$T/t1-etape.log" | head -1; }   # libellé : valeur d'une ligne LIBELLÉ|valeur du journal de l'étape

etape_test1() {
  local t0 ip bao d tr=preuve-test1 pod v c
  garder avant
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  bao=$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.status.podIP}')
  echo "## prédiction (écrite le 30/10/2026, avant le premier passage), barrière par barrière"
  echo "- véhicule : tâche signée par la clé des tâches de la plateforme, propre à ce test (bundle tekton/tasks/preuve-test1, jamais"
  echo "  inscrit dans la liste revue de la porte), exécutée par un TaskRun de builds (compte build, gabarit de la zone build) ;"
  echo "  elle vaut une étape de build dont le code est hostile. TaskRun terminé avec succès : l'étape journalise et sort en 0"
  echo "- 1. aucun jeton de compte de service dans le pod (compte build sans montage d'office ; zone-build interdit le jeton"
  echo "  projeté) : rien à présenter à l'authentification JWT d'OpenBao ; aucune variable d'environnement de secret (premier"
  echo "  passage archivé : la sonde comptait sa propre variable, OPENBAO_IP, renommée CIBLE)"
  echo "- 2. réseau : la NetworkPolicy d'OpenBao n'admet en entrée que tekton-chains et le TSA ; Cilium jette les SYN à l'entrée,"
  echo "  sur sc-confiance (POLICY_DENIED, INGRESS, dans Hubble de sc-confiance), par le service comme par l'IP du pod ($bao) :"
  echo "  délai du client dépassé (5 s), pas de refus ; rien chez l'agent de sc-build, aucune politique de sortie ne sélectionnant"
  echo "  ce pod"
  echo "- 3. OpenBao ne reçoit rien : aucune ligne de son audit avec l'adresse du pod. Témoin dans la même lecture : les requêtes de"
  echo "  Chains (connexion JWT et signature), qui signe ce même TaskRun"
  echo "- témoins : depuis la même étape, Zot et Forgejo joignables (le réseau du pod fonctionne) ; OpenBao descellé pendant l'essai"
  echo "- non exercées ici, mesurées en J3 (openbao-essais.log) : rôle JWT lié au seul compte de Chains (autre compte et autre"
  echo "  audience refusés), clé Transit non exportable (export et sauvegarde refusés, même au jeton root)"
  echo "- résidu : le bundle signé tekton/tasks/preuve-test1 reste dans Zot (poc-ecriture ne supprime pas) ; la porte le refuserait,"
  echo "  hors de la liste revue"
  v=$(kubectl exec -n openbao openbao-0 -- bao status -format=json 2>/dev/null | jq -r .sealed || true)
  [ "$v" = false ] && echo "OK   témoin : OpenBao descellé avant l'essai (pod $bao)" || { echo "KO   OpenBao : sealed=$v" >&2; exit 1; }
  echo "## véhicule : tâche signée (tkn $(tkn version --component client)), bundle, TaskRun"
  cat > "$T/$tr.yaml" <<EOF
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: $tr
spec:
  params:
  - name: openbao
    type: string
  stepTemplate:
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: [ALL]
  steps:
  - name: tenter
    image: $(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")
    env:
    - name: CIBLE
      value: \$(params.openbao)
    script: |
      #!/bin/sh
      o() { d=\$(date +%s); if nc -z -w 5 "\$1" "\$2" 2>/dev/null; then r=OUVERT; else r=FERME; fi; echo "\$r|\$(( \$(date +%s) - d )) s"; }
      echo "IP|\$(hostname -i)"
      if [ -e /var/run/secrets/kubernetes.io/serviceaccount/token ]; then echo "JETON|présent"; else echo "JETON|absent"; fi
      echo "SECRETS_MONTES|\$(ls -A /var/run/secrets 2>/dev/null | tr '\n' ' ')"
      echo "VARIABLES|\$(env | cut -d= -f1 | grep -iE 'token|vault|bao|secret|key|passw' | tr '\n' ' ')"
      echo "DNS|\$(nslookup openbao.openbao.svc.cluster.local 2>&1 | awk '/^Address/ {a = \$NF} END {print a}')"
      echo "OPENBAO_SERVICE|\$(o openbao.openbao.svc.cluster.local 8200)"
      echo "OPENBAO_POD|\$(o "\$CIBLE" 8200)"
      echo "TEMOIN_ZOT|\$(o 192.168.161.13 5000)"
      echo "TEMOIN_FORGEJO|\$(o 192.168.161.13 3000)"
EOF
  tkn task sign "$T/$tr.yaml" -K "$S/taches.key" -f "$T/$tr-signee.yaml" >/dev/null
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  d=$(bundle "$T/$tr-signee.yaml" "tekton/tasks/$tr")
  echo "bundle tekton/tasks/$tr : $d"
  sed -e "s#@NOM@#$tr#" -e "s#@RESOLVEUR@#bundles#" -e "s#@BUNDLE@#$REG/tekton/tasks/$tr@$d#" -e "s#value: essai-confiance#value: $tr#" \
    "$here/politique/taches/taskrun.yaml" | awk -v ip="$bao" '/^  taskRef:$/ {print "  params:"; print "  - name: openbao"; print "    value: \"" ip "\""} {print}' > "$T/tr-$tr.yaml"
  kubectl delete taskrun -n builds "$tr" --ignore-not-found --wait=true >/dev/null
  creer "$T/tr-$tr.yaml" || { echo "KO   TaskRun refusé : $(cat "$T/creer.out")" >&2; exit 1; }
  v=$(issue taskrun "$tr")
  [ "${v%%|*}" = True ] && echo "OK   TaskRun $tr terminé ($(cut -d'|' -f2 <<<"$v"), TrustedResourcesVerified=$(cut -d'|' -f3 <<<"$v"))" \
    || { echo "KO   TaskRun $tr : $v" >&2; exit 1; }
  pod=$(kubectl get taskrun -n builds "$tr" -o jsonpath='{.status.podName}')
  kubectl logs -n builds "$pod" -c step-tenter > "$T/t1-etape.log"
  echo "## journal de l'étape (pod $pod, nœud $(kubectl get pod -n builds "$pod" -o jsonpath='{.spec.nodeName}'))"
  sed 's/^/  /' "$T/t1-etape.log"
  ip=$(ligne_t1 IP | awk '{print $1}')
  [ "$(ligne_t1 JETON)" = absent ] && echo "OK   1. aucun jeton de compte de service dans le pod" || { echo "KO   jeton : $(ligne_t1 JETON)" >&2; exit 1; }
  [ -z "$(ligne_t1 VARIABLES | tr -d ' ')" ] && echo "OK   1. aucune variable d'environnement de secret" || { echo "KO   variables : $(ligne_t1 VARIABLES)" >&2; exit 1; }
  for c in OPENBAO_SERVICE OPENBAO_POD; do
    v=$(ligne_t1 "$c")
    [[ $v == FERME\|[4-7]\ s ]] && echo "OK   2. $c : injoignable, délai du client dépassé ($v)" || { echo "KO   2. $c : $v" >&2; exit 1; }
  done
  for c in TEMOIN_ZOT TEMOIN_FORGEJO; do
    v=$(ligne_t1 "$c")
    [[ $v == OUVERT* ]] && echo "OK   témoin $c : joignable depuis la même étape ($v)" || { echo "KO   témoin $c : $v" >&2; exit 1; }
  done
  echo "## trace : Hubble depuis $t0, flux refusés depuis $ip vers le port 8200"
  hubble_refus sc-confiance "$t0" --from-ip "$ip" --to-port 8200 > "$T/t1-hubble-confiance.txt" || true
  hubble_refus sc-build "$t0" --from-ip "$ip" > "$T/t1-hubble-build.txt" || true
  echo "agent de sc-confiance : $(grep -c . "$T/t1-hubble-confiance.txt" || true) flux"; sed 's/^/  /' "$T/t1-hubble-confiance.txt"
  echo "agent de sc-build : $(grep -c . "$T/t1-hubble-build.txt" || true) flux"; sed 's/^/  /' "$T/t1-hubble-build.txt"
  grep -E "^[0-9:.]+ $ip > $bao:8200 SYN POLICY_DENIED INGRESS$" "$T/t1-hubble-confiance.txt" >/dev/null \
    && echo "OK   2. SYN vers OpenBao jetés à l'entrée par Cilium (sc-confiance, POLICY_DENIED)" || { echo "KO   2. aucun refus dans Hubble de sc-confiance" >&2; exit 1; }
  [ ! -s "$T/t1-hubble-build.txt" ] && echo "OK   2. aucun refus chez l'agent de sc-build (pas de politique de sortie sur ce pod)" \
    || echo "CONSTAT refus vus chez l'agent de sc-build (prédiction : aucun)"
  echo "## trace : audit d'OpenBao depuis $t0"
  signe taskrun "$tr" > /dev/null || true
  kubectl exec -n openbao openbao-0 -- cat /openbao/data/audit.log | jq -c --arg d "$t0" 'select(.type == "response" and .time[0:19] >= ($d[0:19]))
    | {t: .time[11:19], adresse: .request.remote_address, chemin: .request.path, compte: (.auth.display_name // "-")}' > "$T/t1-bao.txt"
  echo "réponses journalisées : $(grep -c . "$T/t1-bao.txt" || true) ; par adresse et compte :"
  jq -r '"\(.adresse) \(.compte)"' "$T/t1-bao.txt" | sort | uniq -c | sed 's/^/  /'
  c=$(jq -c --arg a "$ip" 'select(.adresse == $a)' "$T/t1-bao.txt" | grep -c . || true)
  [ "$c" = 0 ] && echo "OK   3. aucune requête de $ip dans l'audit d'OpenBao" || { echo "KO   3. $c requête(s) de $ip dans l'audit d'OpenBao" >&2; exit 1; }
  c=$(jq -c 'select(.compte == "jwt-system:serviceaccount:tekton-chains:tekton-chains-controller" and (.chemin | startswith("transit/sign/chains")))' "$T/t1-bao.txt" | grep -c . || true)
  [ "$c" -ge 1 ] && echo "OK   témoin : $c signature(s) de Chains dans la même lecture ($tr signé : $(kubectl get taskrun -n builds "$tr" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}'))" \
    || { echo "KO   témoin : aucune signature de Chains depuis $t0 (audit illisible ?)" >&2; exit 1; }
  garder apres
}

T6_DESTINATIONS="Zot:192.168.161.13:5000 Forgejo:192.168.161.13:3000 API-noeud:192.168.161.11:6443 API-service:10.43.0.1:443 Externe:$EXTERNE:443"

t6_ligne() { grep "^$2|" "$T/t6-$1.log" | cut -d'|' -f2- || true; }   # passage clé : champs d'une ligne du journal de l'étape

t6_inutilisee() { # adresse : portée ni par un pod ni par un endpoint de Cilium (contrôle de kata.sh)
  local n d
  n=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | grep -cxF "$1" || true)
  d=$(kubectl get ciliumendpoints -A -o json | jq --arg u "$1" '[.items[].status.networking.addressing[]?.ipv4 | select(. == $u)] | length')
  [ "$n" = 0 ] && [ "$d" = 0 ] && echo "OK   $1 inutilisée : portée ni par un pod ni par un endpoint de Cilium" || { echo "KO   $1 en usage" >&2; exit 1; }
}

t6_passage() { # passage (test|contre) nom-de-la-tâche : bundle, TaskRun sous Kata, journal de l'étape, Hubble et capture sur enp1s0
  local pa=$1 nom=$2 tr=preuve-test6-$1 d t0 v pod
  sed -e "s#@NOM@#$nom#" "$T/t6-tache.yaml" > "$T/t6-$pa.yaml"
  tkn task sign "$T/t6-$pa.yaml" -K "$S/taches.key" -f "$T/t6-$pa-signee.yaml" >/dev/null
  d=$(bundle "$T/t6-$pa-signee.yaml" "tekton/tasks/$tr")
  echo "bundle tekton/tasks/$tr : $d (tâche $nom)"
  sed -e "s#@NOM@#$tr#" -e "s#@RESOLVEUR@#bundles#" -e "s#@BUNDLE@#$REG/tekton/tasks/$tr@$d#" -e "s#value: essai-confiance#value: $nom#" \
    "$here/politique/taches/taskrun.yaml" | awk '{print} /^  podTemplate:$/ {print "    runtimeClassName: kata"}' > "$T/tr-$tr.yaml"
  kubectl delete taskrun -n builds "$tr" --ignore-not-found --wait=true >/dev/null
  echo "NetworkPolicy de builds au lancement : $(kubectl get netpol -n builds -o json | jq -r '.items[] | "\(.metadata.name) (\(.spec.podSelector.matchLabels | to_entries | map(.key + "=" + .value) | join(",")))"' | paste -sd' ')"
  t6_inutilisee "$USURPEE"
  capture "$T/t6-$pa-enp1s0.txt" 600 -i enp1s0 host "$EXTERNE" or host "$USURPEE"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  creer "$T/tr-$tr.yaml" || { echo "KO   TaskRun refusé : $(cat "$T/creer.out")" >&2; exit 1; }
  v=$(issue taskrun "$tr")
  hubble_refus sc-build "$t0" --ip "$USURPEE" > "$T/t6-$pa-hubble-usurpee.txt" || true
  sur sc-build "sudo pkill -INT -x tcpdump" || true
  wait "$CAPTURE" || true
  [ "${v%%|*}" = True ] && echo "OK   TaskRun $tr terminé ($(cut -d'|' -f2 <<<"$v"), TrustedResourcesVerified=$(cut -d'|' -f3 <<<"$v"))" \
    || { echo "KO   TaskRun $tr : $v" >&2; exit 1; }
  pod=$(kubectl get taskrun -n builds "$tr" -o jsonpath='{.status.podName}')
  kubectl logs -n builds "$pod" -c step-construire > "$T/t6-$pa.log"
  kubectl get pod -n builds "$pod" -o json > "$T/t6-$pa-pod.json"
  hubble_refus sc-build "$t0" --from-ip "$(jq -r .status.podIP "$T/t6-$pa-pod.json")" > "$T/t6-$pa-hubble-propre.txt" || true
  echo "## journal de l'étape construire (pod $pod)"
  sed 's/^/  /' "$T/t6-$pa.log"
  jq -r '"pod : nœud \(.spec.nodeName), runtimeClassName \(.spec.runtimeClassName // "-"), IP \(.status.podIP), tekton.dev/task=\(.metadata.labels["tekton.dev/task"] // "-"), "
    + "étape \([.spec.containers[] | select(.name == "step-construire") | "privileged=\(.securityContext.privileged // false) uid \(.securityContext.runAsUser // "pod")"] | join(""))"' "$T/t6-$pa-pod.json"
  echo "Hubble de sc-build depuis $t0, flux refusés de l'IP du pod :"; sed 's/^/  /' "$T/t6-$pa-hubble-propre.txt"
  echo "Hubble de sc-build depuis $t0, flux refusés de $USURPEE :"; sed 's/^/  /' "$T/t6-$pa-hubble-usurpee.txt"
  grep -E 'packets (captured|received)' "$T/t6-$pa-enp1s0.txt" | sed 's/^/  tcpdump enp1s0 : /' || true
}

t6_garde_fous() { # passage label-attendu : le pod mesuré est bien celui qu'on croit (label, Kata, adresse)
  local pa=$1 l ip
  l=$(jq -r '.metadata.labels["tekton.dev/task"] // "-"' "$T/t6-$pa-pod.json")
  [ "$l" = "$2" ] && echo "OK   $pa : label tekton.dev/task=$l sur le pod" || { echo "KO   $pa : label tekton.dev/task=$l (attendu $2)" >&2; exit 1; }
  [ "$(jq -r '.spec.runtimeClassName // "-"' "$T/t6-$pa-pod.json")" = kata ] && [ "$(t6_ligne "$pa" NOYAU)" != "$T6_NOYAU_HOTE" ] \
    && echo "OK   $pa : pod sous Kata, noyau de l'invité $(t6_ligne "$pa" NOYAU) (sc-build : $T6_NOYAU_HOTE)" || { echo "KO   $pa : pas sous Kata" >&2; exit 1; }
  ip=$(jq -r .status.podIP "$T/t6-$pa-pod.json")
  [ "$(t6_ligne "$pa" IP)" = "$ip" ] && echo "OK   $pa : adresse de eth0 dans l'invité = IP du pod ($ip)" || { echo "KO   $pa : eth0 $(t6_ligne "$pa" IP), pod $ip" >&2; exit 1; }
  [ "$(t6_ligne "$pa" AJOUT)" = accepté ] && [ "$(t6_ligne "$pa" RETRAIT)" = accepté ] \
    && echo "OK   $pa : $USURPEE ajoutée puis retirée de eth0 (root dans l'invité)" || { echo "KO   $pa : ajout $(t6_ligne "$pa" AJOUT), retrait $(t6_ligne "$pa" RETRAIT)" >&2; exit 1; }
}

etape_test6() {
  local a c l r h t v n ko=0
  garder avant
  echo "## prédiction (écrite le 31/10/2026, avant le premier passage), contrôle par contrôle"
  echo "- objet : vérifier sur un TaskRun réel les deux contrôles réseau de la zone build, retenus par le propriétaire le"
  echo "  30/10/2026 : la NetworkPolicy construction-sans-sortie (aucune entrée ni sortie pour les pods qui portent"
  echo "  tekton.dev/task=construire-image) et la vérification d'adresse source de Cilium 1.20.4. Les mesures de kata.sh reseau"
  echo "  portaient sur des pods de mesure et une politique de mesure ; ici, la politique réelle et le label posé par Tekton"
  echo "- véhicule : tâche de vérification signée par la clé des tâches, du nom construire-image, publiée sous tekton/tasks/preuve-test6"
  echo "  (jamais dans la liste revue de la porte : la porte refuserait toute provenance qui la cite) ; étape construire, image"
  echo "  BuildKit de la construction réelle, privilégiée et root dans l'invité Kata, comme la vraie ; ni workspace, ni volume, ni"
  echo "  résultat : Chains ne rattache rien à une image ; gabarit de pod du PipelineRun réel (taskRunTemplate du TriggerTemplate,"
  echo "  plus runtimeClassName kata, comme taskRunSpecs). Elle modélise du code qui sortirait du bac à sable de BuildKit"
  echo "- garde-fous relevés sur le pod : label tekton.dev/task=construire-image posé par le contrôleur de Tekton pour un TaskRun"
  echo "  autonome (mesuré jusqu'ici pour un PipelineRun), pod sous Kata (noyau de l'invité différent de celui de sc-build), eth0"
  echo "  de l'invité à l'IP du pod, adresse $USURPEE ajoutée puis retirée"
  echo "- 1. avec l'IP du pod : Zot, Forgejo, API du nœud, API par le service (10.43.0.1:443) et $EXTERNE injoignables ; chez"
  echo "  l'agent de sc-build, au moins un flux refusé par tentative, motif POLICY_DENIED, sens EGRESS (au test 1, le refus était"
  echo "  à l'entrée d'OpenBao, sur sc-confiance). Compte par tentative : flux de l'IP du pod dans les 4 s qui suivent l'heure de la"
  echo "  tentative, notée par l'étape. Corrigé après le premier passage (preuves-test6-premier-passage.log), qui attendait l'API par"
  echo "  le service sous 10.43.0.1:443 : Hubble la montre sous l'adresse traduite, l'extrémité du service kubernetes, comme la"
  echo "  mesure de Cilium de J7 l'avait établi (adresse de service traduite avant la politique ; README, « Mesure de Cilium »)"
  echo "- 2. avec $USURPEE (adresse inutilisée du sous-réseau des pods de sc-build) : Zot et Forgejo injoignables ; au moins un flux"
  echo "  refusé par tentative, motif INVALID_SOURCE_IP (sens non exigé : INGRESS en J7) ; aucun paquet sur enp1s0"
  echo "- 3. rien ne sort du nœud : aucun paquet de ou vers $EXTERNE ni de $USURPEE sur enp1s0 de sc-build pendant le passage"
  echo "- contre-épreuve, même YAML et même image, seul le nom de la tâche change (preuve-test6-temoin, label différent, que la"
  echo "  politique ne sélectionne pas) : Zot, Forgejo et les deux voies de l'API joignables, nc lié à l'IP du pod (-s) joignable,"
  echo "  SYN vers $EXTERNE vus sur enp1s0 (sortie masquée par le nœud) et aucun flux refusé de l'IP du pod ; avec $USURPEE, tout"
  echo "  refusé, INVALID_SOURCE_IP : le contrôle d'adresse source tient seul, sans la politique. Sans cette contre-épreuve, un"
  echo "  nc qui ne marcherait pas ferait passer le test à tort : elle conditionne la conclusion"
  echo "- passages en séquence (mémoire de sc-build) ; l'étape sort toujours en 0"
  echo "- résidus : bundles tekton/tasks/preuve-test6-test et preuve-test6-contre dans Zot (poc-ecriture ne supprime pas) ; deux"
  echo "  TaskRuns signés par Chains sans sujet image, dont un de tâche construire-image (contrôle exécutions/enveloppes)"
  T6_NOYAU_HOTE=$(sur sc-build "uname -r")
  sur sc-build "ip -o link show enp1s0" >/dev/null && echo "OK   interface enp1s0 présente sur sc-build (noyau $T6_NOYAU_HOTE)" || { echo "KO   enp1s0 absente" >&2; exit 1; }
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  cat > "$T/t6-tache.yaml" <<EOF
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: @NOM@
spec:
  steps:
  - name: construire
    image: $BUILDKIT
    securityContext:
      privileged: true
      allowPrivilegeEscalation: true
      runAsUser: 0
      runAsNonRoot: false
    resources:
      requests:
        cpu: "1"
        memory: 1Gi
      limits:
        cpu: "1"
        memory: 1Gi
    script: |
      #!/bin/sh
      o() { t=\$(date +%H:%M:%S); if nc "\$@" 2>/dev/null; then r=OUVERT; else r=FERME; fi; echo "\$t|\$r"; }
      a=\$(ip -o -4 addr show dev eth0 | awk '{print \$4}' | cut -d/ -f1)
      echo "NOYAU|\$(uname -r)"
      echo "IP|\$a"
      echo "NC|\$(readlink -f "\$(command -v nc)")"
      for c in $T6_DESTINATIONS; do
        l=\${c%%:*}; r=\${c#*:}; h=\${r%:*}; p=\${r##*:}
        echo "PROPRE|\$l|\$h:\$p|\$(o -z -w 3 "\$h" "\$p")"
        sleep 1
      done
      echo "LIEE|Zot|192.168.161.13:5000|\$(o -s "\$a" -z -w 3 192.168.161.13 5000)"
      if ip addr add $USURPEE/32 dev eth0 2>/dev/null; then echo "AJOUT|accepté"; else echo "AJOUT|refusé"; fi
      for c in Zot:192.168.161.13:5000 Forgejo:192.168.161.13:3000; do
        l=\${c%%:*}; r=\${c#*:}; h=\${r%:*}; p=\${r##*:}
        echo "USURPEE|\$l|\$h:\$p|\$(o -s $USURPEE -z -w 3 "\$h" "\$p")"
        sleep 1
      done
      if ip addr del $USURPEE/32 dev eth0 2>/dev/null; then echo "RETRAIT|accepté"; else echo "RETRAIT|refusé"; fi
      echo FIN
      exit 0
EOF

  echo "## contre-épreuve d'abord : tâche preuve-test6-temoin, non sélectionnée par construction-sans-sortie"
  t6_passage contre preuve-test6-temoin
  echo "## contre-épreuve : mesures"
  t6_garde_fous contre preuve-test6-temoin
  for c in $T6_DESTINATIONS; do
    l=${c%%:*}; [ "$l" = Externe ] && continue
    v=$(grep "^PROPRE|$l|" "$T/t6-contre.log" | cut -d'|' -f5)
    [ "$v" = OUVERT ] && echo "OK   contre-épreuve : $l joignable" || { echo "KO   contre-épreuve : $l $v (nc ou réseau du pod inutilisable : le test ne prouverait rien)" >&2; exit 1; }
  done
  [ "$(grep '^LIEE|' "$T/t6-contre.log" | cut -d'|' -f5)" = OUVERT ] && echo "OK   contre-épreuve : nc lié à l'IP du pod (-s) joint Zot" \
    || { echo "KO   contre-épreuve : nc -s inutilisable" >&2; exit 1; }
  n=$(grep -cE "> ${EXTERNE//./\\.}\.443: Flags \[S\]," "$T/t6-contre-enp1s0.txt" || true)
  [ "$n" -ge 1 ] && echo "OK   contre-épreuve : $n SYN vers $EXTERNE:443 sur enp1s0 (source $(grep -E "> ${EXTERNE//./\\.}\.443: Flags \[S\]," "$T/t6-contre-enp1s0.txt" | sed -E 's/.* IP ([0-9.]+)\.[0-9]+ > .*/\1/' | sort -u | paste -sd,))" \
    || { echo "KO   contre-épreuve : aucun SYN vers $EXTERNE sur enp1s0 (la capture ne verrait pas une sortie)" >&2; exit 1; }
  [ ! -s "$T/t6-contre-hubble-propre.txt" ] && echo "OK   contre-épreuve : aucun flux refusé de l'IP du pod" \
    || { echo "KO   contre-épreuve : flux refusés de l'IP du pod" >&2; ko=1; }
  for l in Zot Forgejo; do
    v=$(grep "^USURPEE|$l|" "$T/t6-contre.log" | cut -d'|' -f2-)
    h=${v#*|}; h=${h%%|*}
    n=$(grep -cF " $USURPEE > $h SYN INVALID_SOURCE_IP " "$T/t6-contre-hubble-usurpee.txt" || true)
    [ "${v##*|}" = FERME ] && [ "$n" -ge 1 ] && echo "OK   contre-épreuve : $l injoignable depuis $USURPEE, $n flux INVALID_SOURCE_IP (contrôle d'adresse source seul)" \
      || { echo "KO   contre-épreuve : $l depuis $USURPEE : $v, $n flux INVALID_SOURCE_IP" >&2; ko=1; }
  done
  kubectl delete pod -n builds "$(jq -r .metadata.name "$T/t6-contre-pod.json")" --ignore-not-found --wait=true >/dev/null

  echo "## test : tâche construire-image (sélectionnée par construction-sans-sortie)"
  t6_passage test construire-image
  echo "## test : mesures"
  t6_garde_fous test construire-image
  a=$(kubectl get endpointslices -n default -l kubernetes.io/service-name=kubernetes -o json \
    | jq -r '[.items[] | .ports[0].port as $p | .endpoints[].addresses[] | "\(.):\($p)"] | join(" ")')
  echo "extrémités du service kubernetes : $a"
  for c in $T6_DESTINATIONS; do
    l=${c%%:*}; r=${c#*:}
    IFS='|' read -r t v < <(grep "^PROPRE|$l|" "$T/t6-test.log" | cut -d'|' -f4-)
    awk -v ip="$(t6_ligne test IP)" -v t="$t" 'function s(x) {split(substr(x, 1, 8), a, ":"); return a[1] * 3600 + a[2] * 60 + a[3]}
      $2 == ip && $5 == "SYN" && $6 == "POLICY_DENIED" && $7 == "EGRESS" && s($1) >= s(t) && s($1) < s(t) + 4 {print $4}' \
      "$T/t6-test-hubble-propre.txt" > "$T/t6-fenetre.txt"
    n=$(grep -c . "$T/t6-fenetre.txt" || true)
    h=$(sort -u "$T/t6-fenetre.txt" | paste -sd' ')
    [ "$l" = API-service ] && r=$a
    [ "$v" = FERME ] && [ "$n" -ge 1 ] && [ "$h" = "$r" ] && echo "OK   1. $l (${c#*:}, tentative à $t) injoignable, $n flux POLICY_DENIED EGRESS vers $h" \
      || { echo "KO   1. $l (${c#*:}, tentative à $t) : $v, $n flux POLICY_DENIED EGRESS vers « $h » (attendu $r)" >&2; ko=1; }
  done
  [ "$(grep '^LIEE|' "$T/t6-test.log" | cut -d'|' -f5)" = FERME ] && echo "OK   1. nc lié à l'IP du pod : Zot injoignable" || { echo "KO   1. nc -s : Zot joint" >&2; ko=1; }
  for l in Zot Forgejo; do
    v=$(grep "^USURPEE|$l|" "$T/t6-test.log" | cut -d'|' -f2-)
    h=${v#*|}; h=${h%%|*}
    n=$(grep -cF " $USURPEE > $h SYN INVALID_SOURCE_IP " "$T/t6-test-hubble-usurpee.txt" || true)
    [ "${v##*|}" = FERME ] && [ "$n" -ge 1 ] && echo "OK   2. $l injoignable depuis $USURPEE, $n flux INVALID_SOURCE_IP" \
      || { echo "KO   2. $l depuis $USURPEE : $v, $n flux INVALID_SOURCE_IP" >&2; ko=1; }
  done
  n=$(grep -cE " IP " "$T/t6-test-enp1s0.txt" || true)
  [ "$n" = 0 ] && echo "OK   3. aucun paquet de ou vers $EXTERNE ni de $USURPEE sur enp1s0 de sc-build" || { echo "KO   3. $n paquet(s) sur enp1s0" >&2; ko=1; }
  kubectl delete pod -n builds "$(jq -r .metadata.name "$T/t6-test-pod.json")" --ignore-not-found --wait=true >/dev/null
  garder apres
  [ "$ko" = 0 ] || { echo "KO   test 6 : au moins une mesure contraire à la prédiction" >&2; exit 1; }
}

RC_DEPOT=essais-j8/regle-c   # images témoins de reglec (non supprimables de Zot)

oci_signe() { # digest type-de-couche suffixe fichier… : tag <suffixe> signé au format hérité de cosign (config rootfs, annotation
  # de signature), une couche par fichier, dans OCI_DEPOT (RC_DEPOT par défaut) ; pour .att, chaque fichier est une enveloppe DSSE
  # et l'annotation est vide (Chains : une enveloppe par couche)
  local d=${OCI_DEPOT:-$RC_DEPOT} f a c ls=()
  for f in "${@:4}"; do
    [ "$3" = sig ] && a=$(base64 -w0 "$f.sig") || a=
    zot_ecrire blob push "$REG_HOTE/$d" "$f" >/dev/null
    ls+=("$(jq -nc --arg l "sha256:$(sha256sum < "$f" | cut -c1-64)" --argjson n "$(stat -c%s "$f")" --arg t "$2" --arg a "$a" \
      '{mediaType: $t, digest: $l, size: $n,
        annotations: {"dev.cosignproject.cosign/signature": $a, "dev.sigstore.cosign/certificate": "", "dev.sigstore.cosign/chain": ""}}')")
  done
  printf '%s\n' "${ls[@]}" | jq -sc '{architecture: "", os: "", config: {}, rootfs: {type: "layers", diff_ids: map(.digest)}}' > "$T/rc-config.json"
  c=sha256:$(sha256sum < "$T/rc-config.json" | cut -c1-64)
  zot_ecrire blob push "$REG_HOTE/$d" "$T/rc-config.json" >/dev/null
  printf '%s\n' "${ls[@]}" | jq -sc --arg c "$c" --argjson cn "$(stat -c%s "$T/rc-config.json")" \
    '{schemaVersion: 2, mediaType: "application/vnd.oci.image.manifest.v1+json",
      config: {mediaType: "application/vnd.oci.image.config.v1+json", digest: $c, size: $cn}, layers: .}' > "$T/rc-manifeste.json"
  zot_ecrire manifest push "$REG_HOTE/$d:sha256-${1#sha256:}.$3" "$T/rc-manifeste.json" >/dev/null
}

rc_temoin() { # cas filtre-jq-sur-le-TaskRun-construire : image témoin signée, provenance réelle modifiée ; digest dans $T/rc-<cas>.image
  local c=$1 d pt
  d=$(DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt crane mutate --label "poc.test/cas=reglec-$c-$RC_PASSAGE" \
    -t "$REG_HOTE/$RC_DEPOT:$c" "$REG_HOTE/$APP" 2>/dev/null)
  d=${d##*@}; echo "$d" > "$T/rc-$c.image"
  jq -nc --arg r "$REG/$RC_DEPOT" --arg d "$d" '{critical: {identity: {"docker-reference": $r}, image: {"docker-manifest-digest": $d},
    type: "cosign container image signature"}, optional: null}' > "$T/rc-$c-simple.json"
  openssl dgst -sha256 -sign "$T/auth/rc.key" -out "$T/rc-$c-simple.json.sig" "$T/rc-$c-simple.json"
  oci_signe "$d" application/vnd.dev.cosign.simplesigning.v1+json sig "$T/rc-$c-simple.json"
  jq -c --arg r "$REG/$RC_DEPOT" --arg x "${d#sha256:}" '.subject = [{name: $r, digest: {sha256: $x}}]
    | .predicate.buildDefinition.resolvedDependencies |= map(if .name == "pipelineTask" and .content != null
        and ((.content | @base64d | fromjson).metadata.labels["tekton.dev/task"] == "construire-image")
      then .content = ((.content | @base64d | fromjson) | '"$2"' | tojson | @base64) else . end)' "$T/rc-prov.json" > "$T/rc-$c.payload"
  pt=$(jq -r .payloadType "$T/rc-env-chains.json")
  { printf 'DSSEv1 %d %s %d ' "${#pt}" "$pt" "$(stat -c%s "$T/rc-$c.payload")"; cat "$T/rc-$c.payload"; } > "$T/rc-$c.pae"
  openssl dgst -sha256 -sign "$T/auth/rc.key" -out "$T/rc-$c.dsse" "$T/rc-$c.pae"
  jq -nc --arg t "$pt" --arg p "$(base64 -w0 "$T/rc-$c.payload")" --arg s "$(base64 -w0 "$T/rc-$c.dsse")" \
    '{payloadType: $t, payload: $p, signatures: [{keyid: "", sig: $s}]}' > "$T/rc-$c-env.json"
  oci_signe "$d" application/vnd.dsse.envelope.v1+json att "$T/rc-$c-env.json"
  echo "$c : $RC_DEPOT@$d ; runtimeClassName du TaskRun construire signé : $(jq -r '.predicate.buildDefinition.resolvedDependencies[]
    | select(.name == "pipelineTask" and .content != null) | .content | @base64d | fromjson
    | select(.metadata.labels["tekton.dev/task"] == "construire-image") | .spec.podTemplate.runtimeClassName // "absent"' "$T/rc-$c.payload") ;"\
    "taskRunSpecs : $(jq -r '[.predicate.buildDefinition.externalParameters.runSpec.taskRunSpecs[] | .podTemplate.runtimeClassName] | join(",")' "$T/rc-$c.payload")"
  echo "  sur l'hôte, clé jetable : signature $(cosign verify --key "$T/rc.pub" --insecure-ignore-tlog --registry-cacert "$P/ca-poc.crt" \
    "$REG_HOTE/$RC_DEPOT@$d" >/dev/null 2>&1 && echo vérifiée || echo REFUSÉE), attestation $(cosign verify-attestation --key "$T/rc.pub" \
    --insecure-ignore-tlog --type https://slsa.dev/provenance/v1 --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$RC_DEPOT@$d" >/dev/null 2>&1 \
    && echo vérifiée || echo REFUSÉE) ; clé de Chains : $(cosign verify-attestation --key "$R/chains-cle-publique.pem" --insecure-ignore-tlog \
    --type https://slsa.dev/provenance/v1 --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$RC_DEPOT@$d" >/dev/null 2>&1 && echo vérifiée || echo refusée)"
}

etape_reglec() {
  local v c r n ko=0 vr
  echo "## prédiction"
  echo "porte (Job de l'espace porte, policy.yaml) : image réelle $APP jugée avec la clé de Chains, verdict de référence V ;"
  echo "  porte.construction_kata parmi ses succès (TaskRun construire à runtimeClassName kata dans la spec signée)"
  echo "images témoins ($RC_DEPOT), clé jetable, provenance réelle au sujet réécrit, ConfigMap porte-temoin :"
  echo "  intacte : violations de V plus slsa_build_scripted_build.subject_build_task_matches (le digest du témoin n'est pas"
  echo "  celui que donne le résultat de la tâche de build, constaté au premier passage), porte.construction_kata parmi les succès ;"
  echo "  sans-kata (runtimeClassName retiré du seul TaskRun en contenu, taskRunSpecs gardés à kata) et runc : violations"
  echo "  d'intacte plus porte.construction_kata, et rien d'autre (même clé, même structure : seule la règle diffère)"
  cmp -s <(kubectl get configmap -n porte porte -o jsonpath='{.data.porte\.rego}') "$here/politique/porte/porte.rego" \
    && echo "OK   ConfigMap porte : porte.rego identique au fichier versionné" \
    || { echo "KO   ConfigMap porte différente de politique/porte/porte.rego (rejouer politique.sh porte)" >&2; exit 1; }
  garder avant
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  auth_zot "$T/auth/zot.json"
  RC_PASSAGE=$(date -u +%Y%m%dT%H%M%SZ)
  (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$T/auth/rc.key")
  openssl pkey -in "$T/auth/rc.key" -pubout -out "$T/rc.pub"
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$APP" 2>/dev/null > "$T/rc-envs.jsonl"
  jq -c 'select(.payload | @base64d | fromjson | .predicate.buildDefinition.externalParameters.runSpec.pipelineRef != null)' "$T/rc-envs.jsonl" \
    | jq -sc 'max_by(.payload | @base64d | fromjson | .predicate.runDetails.metadata.finishedOn)' > "$T/rc-env-chains.json"
  jq -r .payload "$T/rc-env-chains.json" | base64 -d > "$T/rc-prov.json"
  echo "provenance réelle reprise : PipelineRun $(jq -r .predicate.runDetails.metadata.invocationId "$T/rc-prov.json"), $(stat -c%s "$T/rc-prov.json") octets"

  echo "## images témoins"
  rc_temoin intacte '.'
  rc_temoin sans-kata 'del(.spec.podTemplate.runtimeClassName)'
  rc_temoin runc '.spec.podTemplate.runtimeClassName = "runc"'
  kubectl get configmap -n porte porte -o json | jq --rawfile k "$T/rc.pub" '.data["chains.pub"] = $k
    | .metadata = {name: "porte-temoin", namespace: "porte"}' | kubectl apply --server-side -f - >/dev/null
  echo "ConfigMap porte-temoin : copie de porte, clé publique jetable à la place de celle de Chains"

  echo "## verdicts de la porte"
  vr=$(juger reglec-reel "$REG/$APP")
  echo "  $vr"
  [ "${vr%%|*}" = VERDICT ] || { echo "KO   image réelle : aucun verdict" >&2; exit 1; }
  succes reglec-reel porte.construction_kata && echo "OK   réelle : porte.construction_kata parmi les succès" \
    || { echo "KO   réelle : porte.construction_kata absente des succès" >&2; ko=1; }
  v=$(trier "$(cut -d'|' -f4 <<< "$vr"),slsa_build_scripted_build.subject_build_task_matches")
  for c in intacte sans-kata runc; do
    r=$(juger "reglec-$c" "$REG/$RC_DEPOT@$(cat "$T/rc-$c.image")" policy.yaml porte-temoin)
    echo "  $r"
    if [ "$c" = intacte ]; then
      [ "$(cut -d'|' -f4 <<< "$r")" = "$v" ] && succes "reglec-$c" porte.construction_kata \
        && echo "OK   $c : violations de l'image réelle plus subject_build_task_matches, porte.construction_kata parmi les succès" \
        || { echo "KO   $c : violations ou succès différents de la prédiction" >&2; ko=1; }
    else
      [ "$(cut -d'|' -f4 <<< "$r")" = "$(trier "${v:+$v,}porte.construction_kata")" ] && [ "$(cut -d'|' -f3 <<< "$r")" = false ] \
        && echo "OK   $c : refusée, violations d'intacte plus porte.construction_kata seule" \
        || { echo "KO   $c : violations prédites $(trier "${v:+$v,}porte.construction_kata")" >&2; ko=1; }
      jq -r '[.components[] | .violations[]? | select(.metadata.code == "porte.construction_kata") | .msg] | .[0] // "-"' \
        "$T/porte-reglec-$c.json" | sed "s/^/  motif $c : /"
    fi
  done
  echo "## succès à vide : image de la tâche en service (builds/essai-webhook, pipeline sans construire-image)"
  r=$(juger reglec-en-service "$REG/builds/essai-webhook@$APP_DIGEST")
  echo "  $r"
  n=$(prov_pr "builds/essai-webhook@$APP_DIGEST" | jq -s 'max_by(.predicate.runDetails.metadata.finishedOn).predicate.buildDefinition.resolvedDependencies
    | [.[] | select(.name == "pipelineTask" and .content != null) | .content | @base64d | fromjson
    | select(.metadata.labels["tekton.dev/task"] == "construire-image")] | length')
  succes reglec-en-service porte.construction_kata && [ "$n" = 0 ] \
    && echo "CONSTAT  en-service : porte.construction_kata comptée parmi les succès sans aucun TaskRun de construire-image (succès à vide, comme trusted_task.trusted en J6)" \
    || echo "en-service : $n TaskRun(s) de construire-image, porte.construction_kata parmi les succès : $(succes reglec-en-service porte.construction_kata && echo oui || echo non)"
  kubectl delete configmap -n porte porte-temoin --ignore-not-found >/dev/null
  echo "ConfigMap porte-temoin retirée ; clé jetable effacée avec $T/auth à la sortie"
  garder apres
  [ "$ko" = 0 ] || { echo "KO   règle (c) : au moins une mesure contraire à la prédiction" >&2; exit 1; }
}

T7_DEPOT=essais-j8/test7   # images témoins du test 7 (non supprimables de Zot)
C7E8=sha256:c7e8b275c99e6a105acae4f1b76acee24034fca407229b7b63e620b26cd75906   # construire-image retirée de la liste revue (J7)

t7_prov() { # nom filtre-jq : provenance réelle ($T/rc-prov.json) modifiée par le filtre, dans $T/t7-<nom>.prov
  jq -c --arg c "${C7E8#sha256:}" 'def non_listee: .predicate.buildDefinition.resolvedDependencies |= map(
      if .name == "pipelineTask" and (.uri // "" | endswith("/tekton/tasks/construire-image")) then .digest.sha256 = $c
        | if .content != null then .content = ((.content | @base64d | fromjson)
            | .spec.taskRef.params |= map(if .name == "bundle" then .value |= sub("@sha256:[0-9a-f]+$"; "@sha256:" + $c) else . end)
            | .status.provenance.refSource.digest.sha256 = $c | tojson | @base64) else . end
      else . end);
    '"$2" "$T/rc-prov.json" > "$T/t7-$1.prov"
}

t7_temoin() { # cas prov… : image témoin de T7_DEPOT signée par la clé jetable, une enveloppe par provenance (sujet réécrit), dans
  # l'ordre donné ; digest dans $T/t7-<cas>.image
  local c=$1 d p pt i=0 envs=()
  d=$(DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt crane mutate --label "poc.test/cas=test7-$c-$RC_PASSAGE" \
    -t "$REG_HOTE/$T7_DEPOT:$c" "$REG_HOTE/$APP" 2>/dev/null)
  d=${d##*@}; echo "$d" > "$T/t7-$c.image"
  jq -nc --arg r "$REG/$T7_DEPOT" --arg d "$d" '{critical: {identity: {"docker-reference": $r}, image: {"docker-manifest-digest": $d},
    type: "cosign container image signature"}, optional: null}' > "$T/t7-$c-simple.json"
  openssl dgst -sha256 -sign "$T/auth/rc.key" -out "$T/t7-$c-simple.json.sig" "$T/t7-$c-simple.json"
  [ -n "${T7_SANS_SIG:-}" ] || OCI_DEPOT=$T7_DEPOT oci_signe "$d" application/vnd.dev.cosign.simplesigning.v1+json sig "$T/t7-$c-simple.json"
  pt=$(jq -r .payloadType "$T/rc-env-chains.json")
  for p in "${@:2}"; do
    i=$((i + 1))
    jq -c --arg r "$REG/$T7_DEPOT" --arg x "${d#sha256:}" '.subject = [{name: $r, digest: {sha256: $x}}]' "$T/t7-$p.prov" > "$T/t7-$c-$i.payload"
    { printf 'DSSEv1 %d %s %d ' "${#pt}" "$pt" "$(stat -c%s "$T/t7-$c-$i.payload")"; cat "$T/t7-$c-$i.payload"; } > "$T/t7-$c-$i.pae"
    openssl dgst -sha256 -sign "$T/auth/rc.key" -out "$T/t7-$c-$i.dsse" "$T/t7-$c-$i.pae"
    jq -nc --arg t "$pt" --arg p "$(base64 -w0 "$T/t7-$c-$i.payload")" --arg s "$(base64 -w0 "$T/t7-$c-$i.dsse")" \
      '{payloadType: $t, payload: $p, signatures: [{keyid: "", sig: $s}]}' > "$T/t7-$c-$i.env"
    envs+=("$T/t7-$c-$i.env")
  done
  OCI_DEPOT=$T7_DEPOT oci_signe "$d" application/vnd.dsse.envelope.v1+json att "${envs[@]}"
  echo "$c : $T7_DEPOT@$d${T7_SANS_SIG:+ (aucun tag .sig)} ; enveloppes dans l'ordre des couches : $(for p in "${@:2}"; do jq -r --arg p "$p" '.predicate as $q
    | ([$q.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask" and (.uri // "" | endswith("/construire-image")))][0].digest.sha256[0:8]) as $t
    | "\($p) (construire-image \($t), finishedOn \($q.runDetails.metadata.finishedOn // "absent"))"' "$T/t7-$p.prov"; done | paste -sd' ' -)"
  echo "  sur l'hôte, clé jetable : signature $(cosign verify --key "$T/rc.pub" --insecure-ignore-tlog --registry-cacert "$P/ca-poc.crt" \
    "$REG_HOTE/$T7_DEPOT@$d" >/dev/null 2>&1 && echo vérifiée || echo REFUSÉE), enveloppes vérifiées : $(cosign verify-attestation --key "$T/rc.pub" \
    --insecure-ignore-tlog --type https://slsa.dev/provenance/v1 --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$T7_DEPOT@$d" 2>/dev/null | grep -c . || true) ;"\
    "clé de Chains : $(cosign verify-attestation --key "$R/chains-cle-publique.pem" --insecure-ignore-tlog --type https://slsa.dev/provenance/v1 \
    --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$T7_DEPOT@$d" >/dev/null 2>&1 && echo vérifiée || echo refusée)"
}

t7_derniere() { # PipelineRun : attend que la provenance la plus récente de builds/essai-webhook soit la sienne (envoi de Chains)
  local u; u=$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.metadata.uid}')
  for _ in $(seq 60); do
    [ "$(prov_pr "builds/essai-webhook@$APP_DIGEST" | jq -sr 'max_by(.predicate.runDetails.metadata.finishedOn).predicate.runDetails.metadata.invocationId')" = "$u" ] \
      && { echo "OK   la provenance la plus récente de builds/essai-webhook est celle de $1 ($u)"; return; }
    sleep 2
  done
  echo "KO   provenance la plus récente de builds/essai-webhook hors de $1" >&2; exit 1
}

t7_provenances() { # provenances de PipelineRun de builds/essai-webhook : listées ou non (tâche publier), les trois plus récentes
  prov_pr "builds/essai-webhook@$APP_DIGEST" | jq -sr --arg t "$1" 'sort_by(.predicate.runDetails.metadata.finishedOn)
    | map(.predicate | ([.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask" and .uri != null) | (.uri | sub("^oci://"; "")) + "@sha256:" + .digest.sha256][0] // "") as $u
      | "\(.runDetails.metadata.finishedOn) \(.runDetails.metadata.invocationId[0:8]) \(if $u == "" then "sans tâche" elif $u == $t then "listée" else "non listée (\($u | sub(".*/tasks/"; "") | .[0:40]))" end)")
    | .[]' > "$T/t7-provenances"
  echo "provenances de PipelineRun de builds/essai-webhook : $(wc -l < "$T/t7-provenances") ; non listées : $(grep -c 'non listée' "$T/t7-provenances" || true) ; les trois plus récentes :"
  tail -3 "$T/t7-provenances" | sed 's/^/  /'
}

t7_verdict() { # cas attendu (violations triées, ou PASS) image [ConfigMap] [source] : juger, puis ligne OK ou KO ; ko incrémenté
  local r
  r=$(juger "t7-$1" "$3" policy.yaml "${4:-porte}" "${5:-}")
  echo "  $r"
  if [ "$2" = PASS ]; then
    [ "$(cut -d'|' -f1,3,4 <<< "$r")" = "VERDICT|true|" ] && echo "OK   $1 : admise, aucune violation" || { echo "KO   $1 : admission prédite" >&2; ko=$((ko + 1)); }
  else
    [ "$(cut -d'|' -f1,3 <<< "$r")" = "VERDICT|false" ] && [ "$(cut -d'|' -f4 <<< "$r")" = "$(trier "$2")" ] \
      && echo "OK   $1 : refusée, violations prédites" || { echo "KO   $1 : violations prédites $(trier "$2")" >&2; ko=$((ko + 1)); }
  fi
}

motif() { # cas code : premier motif de cette règle dans le verdict
  jq -r --arg c "$2" '[.components[] | .violations[]? | select(.metadata.code == $c) | .msg] | .[0] // "-"' "$T/porte-t7-$1.json" \
    | cut -c1-220 | sed "s/^/  motif $1 : /"
}

etape_test7() {
  local ko=0 src par f0 fm fp busybox tache pipe pipe_svc st w ww tsvc r
  echo "## prédiction (bibliothèque conforma/policy v1.0.28, lue au commit ebd3fbd2 ; politique policy.yaml de la porte)"
  echo "source attendue : dépôt workspace/sample-app de Forgejo et commit TETE_J2 du script, comparé à la tête de main dans l'API de"
  echo "  Forgejo, jamais lu dans la provenance jugée ; transmise à ec par --images (input.image.source)"
  echo "A  image réelle $APP, source attendue : admise, aucune violation (premier verdict complet d'une image réelle)"
  echo "B  même image, révision fictive absente du dépôt, puis URL d'un autre dépôt : refusée, slsa_source_correlated.expected_source_code_reference seule"
  echo "C  builds/essai-images@${APP_DIGEST#sha256:} (même digest, poussé par poc-images en J7, jamais présenté à Chains ; signatures dans"
  echo "   builds/sample-app seulement) : refusée, builtin.attestation.signature_check et builtin.image.signature_check"
  echo "D1 témoins à clé jetable ($T7_DEPOT, ConfigMap porte-temoin), provenance réelle au sujet réécrit, source attendue ; L : listée"
  echo "   (construire-image 403ccbd8), N : même provenance citant construire-image ${C7E8:7:8}, retirée de la liste revue. Référence W ="
  echo "   violations de « listee » : subject_build_task_matches seule (digest du témoin, constat de reglec) ; trusted_task.trusted parmi ses succès"
  echo "   non-listee (N) : W + trusted_task.trusted ; nl-recente (L, puis N plus récente d'une heure) : W + trusted_task.trusted ;"
  echo "   l-recente (N plus ancienne d'une heure, puis L) : W, admise par trusted_task (seule la plus récente est jugée : faiblesse mesurée) ;"
  echo "   egalite (L et N au même finishedOn) : W + trusted_task.trusted (les deux sont jugées) ;"
  echo "   sans-date (L, puis N sans finishedOn) : aucune provenance de PipelineRun retenue (toutes doivent être datées), trusted_task.trusted"
  echo "   en succès à vide ; refus porté par attestation_type.pipelinerun_attestation_found (lib.pipelinerun_attestations vide) et"
  echo "   porte.taches_vues ; tasks.pipeline_has_tasks ne parcourt que les provenances retenues et ne refuse rien (deuxième passage :"
  echo "   prédit à tort, lu ensuite dans tasks.rego)"
  echo "D2 vraies signatures de Chains sur builds/essai-webhook@${APP_DIGEST#sha256:} (image de la tâche en service, sans source git : Vw ="
  echo "   violations de son verdict de départ) : PipelineRun d'une pipeline signée dont la tâche, signée par la clé des tâches, est hors de la"
  echo "   liste revue (bundle tekton/tasks/preuve-test7) : sa provenance devient la plus récente, Vw + trusted_task.trusted ; puis PipelineRun"
  echo "   du gabarit en service : Vw, trusted_task.trusted parmi les succès, la provenance non listée plus ancienne restant dans le tag .att"
  cmp -s <(kubectl get configmap -n porte porte -o jsonpath='{.data.porte\.rego}') "$here/politique/porte/porte.rego" \
    && cmp -s <(kubectl get configmap -n porte porte -o jsonpath='{.data.policy\.yaml}') "$here/politique/porte/policy.yaml" \
    && echo "OK   ConfigMap porte : porte.rego et policy.yaml identiques aux fichiers versionnés" \
    || { echo "KO   ConfigMap porte différente des fichiers versionnés (rejouer politique.sh porte)" >&2; exit 1; }
  garder avant
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  auth_zot "$T/auth/zot.json"
  RC_PASSAGE=$(date -u +%Y%m%dT%H%M%SZ)

  echo "## source attendue"
  [ "$(tete)" = "$TETE_J2" ] && echo "OK   tête de main dans Forgejo : $TETE_J2 (commit du script)" || { echo "KO   tête de main différente de $TETE_J2" >&2; exit 1; }
  # Premier passage : TETE_J2 est la racine du dépôt (aucun parent dans l'API de Forgejo) ; révision fictive à la place
  par=$(printf 'test7 : revision absente du depot' | sha1sum | cut -c1-40)
  [ "$(curl -s -o /dev/null -w '%{http_code}' --cacert "$P/ca-poc.crt" "$FORGEJO_HOTE/api/v1/repos/$SAMPLE_APP/git/commits/$par")" = 404 ] \
    && echo "révision du cas B : $par (fictive, absente du dépôt : 404 dans l'API de Forgejo ; $TETE_J2 est la racine, sans parent)" \
    || { echo "KO   révision fictive présente dans le dépôt" >&2; exit 1; }
  src() { jq -nc --arg u "https://sc-stockage.poc.test:3000/$1.git" --arg r "$2" '{git: {url: $u, revision: $r}}'; }

  echo "## A, B : image réelle"
  t7_verdict reel PASS "$REG/$APP" porte "$(src "$SAMPLE_APP" "$TETE_J2")"
  succes t7-reel slsa_source_correlated.expected_source_code_reference && succes t7-reel trusted_task.trusted \
    && succes t7-reel porte.construction_kata && echo "OK   reel : expected_source_code_reference, trusted_task.trusted et porte.construction_kata parmi les succès" \
    || { echo "KO   reel : succès attendus absents" >&2; ko=$((ko + 1)); }
  t7_verdict mauvaise-revision slsa_source_correlated.expected_source_code_reference "$REG/$APP" porte "$(src "$SAMPLE_APP" "$par")"
  motif mauvaise-revision slsa_source_correlated.expected_source_code_reference
  t7_verdict mauvaise-url slsa_source_correlated.expected_source_code_reference "$REG/$APP" porte "$(src workspace/autre-depot "$TETE_J2")"
  motif mauvaise-url slsa_source_correlated.expected_source_code_reference

  echo "## C : même digest dans builds/essai-images, poussé par poc-images (J7, construction.sh compte), sans Chains"
  echo "builds/essai-images : enveloppes $(nb_enveloppes "builds/essai-images@$APP_DIGEST"), signature $(cosign download signature \
    --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-images@$APP_DIGEST" 2>/dev/null | grep -c . || true)"
  t7_verdict poc-images builtin.attestation.signature_check,builtin.image.signature_check "$REG/builds/essai-images@$APP_DIGEST" porte \
    "$(src "$SAMPLE_APP" "$TETE_J2")"
  motif poc-images builtin.attestation.signature_check

  echo "## D1 : témoins à clé jetable, ordre des provenances"
  (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$T/auth/rc.key")
  openssl pkey -in "$T/auth/rc.key" -pubout -out "$T/rc.pub"
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$APP" 2>/dev/null \
    | jq -c 'select(.payload | @base64d | fromjson | .predicate.buildDefinition.externalParameters.runSpec.pipelineRef != null)' \
    | jq -sc 'max_by(.payload | @base64d | fromjson | .predicate.runDetails.metadata.finishedOn)' > "$T/rc-env-chains.json"
  jq -r .payload "$T/rc-env-chains.json" | base64 -d > "$T/rc-prov.json"
  f0=$(jq -r .predicate.runDetails.metadata.finishedOn "$T/rc-prov.json")
  fm=$(date -u -d "$f0 - 1 hour" +%Y-%m-%dT%H:%M:%SZ); fp=$(date -u -d "$f0 + 1 hour" +%Y-%m-%dT%H:%M:%SZ)
  echo "provenance réelle reprise : PipelineRun $(jq -r .predicate.runDetails.metadata.invocationId "$T/rc-prov.json"), finishedOn $f0"
  t7_prov L '.'
  t7_prov N 'non_listee'
  t7_prov N-recente "non_listee | .predicate.runDetails.metadata.finishedOn = \"$fp\""
  t7_prov N-ancienne "non_listee | .predicate.runDetails.metadata.finishedOn = \"$fm\""
  t7_prov N-sans-date 'non_listee | del(.predicate.runDetails.metadata.finishedOn)'
  t7_temoin listee L
  t7_temoin non-listee N
  t7_temoin nl-recente L N-recente
  t7_temoin l-recente N-ancienne L
  t7_temoin egalite L N
  t7_temoin sans-date L N-sans-date
  kubectl get configmap -n porte porte -o json | jq --rawfile k "$T/rc.pub" '.data["chains.pub"] = $k
    | .metadata = {name: "porte-temoin", namespace: "porte"}' | kubectl apply --server-side -f - >/dev/null
  echo "ConfigMap porte-temoin : copie de porte, clé publique jetable à la place de celle de Chains"
  w=slsa_build_scripted_build.subject_build_task_matches
  t7_verdict listee "$w" "$REG/$T7_DEPOT@$(cat "$T/t7-listee.image")" porte-temoin "$(src "$SAMPLE_APP" "$TETE_J2")"
  succes t7-listee trusted_task.trusted && echo "OK   listee : trusted_task.trusted parmi les succès" || { echo "KO   listee : trusted_task.trusted absente des succès" >&2; ko=$((ko + 1)); }
  for r in non-listee nl-recente egalite; do
    t7_verdict "$r" "$w,trusted_task.trusted" "$REG/$T7_DEPOT@$(cat "$T/t7-$r.image")" porte-temoin "$(src "$SAMPLE_APP" "$TETE_J2")"
  done
  motif nl-recente trusted_task.trusted
  t7_verdict l-recente "$w" "$REG/$T7_DEPOT@$(cat "$T/t7-l-recente.image")" porte-temoin "$(src "$SAMPLE_APP" "$TETE_J2")"
  succes t7-l-recente trusted_task.trusted && echo "CONSTAT  l-recente : trusted_task.trusted en succès malgré l'enveloppe signée citant construire-image ${C7E8:7:8}, plus ancienne (seule la plus récente est jugée)" \
    || { echo "KO   l-recente : trusted_task.trusted absente des succès" >&2; ko=$((ko + 1)); }
  r=$(juger t7-sans-date "$REG/$T7_DEPOT@$(cat "$T/t7-sans-date.image")" policy.yaml porte-temoin "$(src "$SAMPLE_APP" "$TETE_J2")")
  echo "  $r"
  [ "$(cut -d'|' -f1,3 <<< "$r")" = "VERDICT|false" ] && ! grep -qw trusted_task.trusted <<< "$(cut -d'|' -f4 <<< "$r")" \
    && [ "$(cut -d'|' -f4 <<< "$r")" = attestation_type.pipelinerun_attestation_found,porte.taches_vues ] \
    && echo "OK   sans-date : refusée par attestation_type.pipelinerun_attestation_found et porte.taches_vues seules, trusted_task.trusted hors des violations" \
    || { echo "KO   sans-date : prédiction" >&2; ko=$((ko + 1)); }
  succes t7-sans-date trusted_task.trusted && echo "CONSTAT  sans-date : trusted_task.trusted en succès à vide (aucune provenance de PipelineRun retenue)"
  kubectl delete configmap -n porte porte-temoin --ignore-not-found >/dev/null
  echo "ConfigMap porte-temoin retirée ; clé jetable effacée avec $T/auth à la sortie"

  echo "## D2 : vraies signatures de Chains, builds/essai-webhook@${APP_DIGEST#sha256:}"
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente" >&2; exit 1; }
  tsvc=$(awk '/tekton\/tasks\/publier-essai:/ {getline; print $3}' "$here/politique/porte/taches.yml")
  tsvc=sc-stockage.poc.test:5000/tekton/tasks/publier-essai@$tsvc
  t7_provenances "$tsvc"
  ww=$(juger t7-webhook-depart "$REG/builds/essai-webhook@$APP_DIGEST")
  echo "  $ww"
  [ "${ww%%|*}" = VERDICT ] && succes t7-webhook-depart trusted_task.trusted && echo "OK   départ : trusted_task.trusted parmi les succès ; Vw = $(cut -d'|' -f4 <<< "$ww")" \
    || { echo "KO   départ : la plus récente n'est pas listée, ou aucun verdict" >&2; exit 1; }
  ww=$(cut -d'|' -f4 <<< "$ww")
  busybox=$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")
  sed -e "s#@IMAGE@#$REG/builds/essai-webhook#" -e "s#@DIGEST@#$APP_DIGEST#" -e "s#@BUSYBOX@#$busybox#" \
    "$here/politique/taches/publier-essai.yaml" > "$T/t7-tache.yaml"
  tkn task sign "$T/t7-tache.yaml" -K "$S/taches.key" -f "$T/t7-tache-signee.yaml" >/dev/null 2>&1
  tache=$REG/tekton/tasks/preuve-test7@$(bundle "$T/t7-tache-signee.yaml" tekton/tasks/preuve-test7 "$RC_PASSAGE")
  ! listee "$tache" && echo "tâche hors liste : ${tache#"$REG/"} (gabarit de publier-essai, même image et même digest, nouvelle signature)" \
    || { echo "KO   tâche dans la liste revue" >&2; exit 1; }
  sed "s#@TACHE@#$tache#" "$here/politique/taches/sample-app-essai.yaml" > "$T/t7-pipeline.yaml"
  tkn pipeline sign "$T/t7-pipeline.yaml" -K "$S/taches.key" -f "$T/t7-pipeline-signee.yaml" >/dev/null 2>&1
  pipe=$REG/tekton/pipelines/preuve-test7@$(bundle "$T/t7-pipeline-signee.yaml" tekton/pipelines/preuve-test7 "$RC_PASSAGE")
  st=$(pr_gabarit preuve-test7-hors-liste "$pipe")
  [ "${st%%|*}" = True ] || { echo "KO   preuve-test7-hors-liste : $st" >&2; exit 1; }
  echo "PipelineRun preuve-test7-hors-liste (${pipe#"$REG/"}) : $(cut -d'|' -f1-3 <<< "$st"), Chains : signé=$(signe pipelinerun preuve-test7-hors-liste)"
  t7_derniere preuve-test7-hors-liste
  t7_verdict webhook-hors-liste "$ww,trusted_task.trusted" "$REG/builds/essai-webhook@$APP_DIGEST"
  motif webhook-hors-liste trusted_task.trusted
  pipe_svc=$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value')
  st=$(pr_gabarit preuve-test7-en-service "$pipe_svc")
  [ "${st%%|*}" = True ] || { echo "KO   preuve-test7-en-service : $st" >&2; exit 1; }
  echo "PipelineRun preuve-test7-en-service (gabarit en service) : $(cut -d'|' -f1-3 <<< "$st"), Chains : signé=$(signe pipelinerun preuve-test7-en-service)"
  t7_derniere preuve-test7-en-service
  t7_verdict webhook-en-service "$ww" "$REG/builds/essai-webhook@$APP_DIGEST"
  t7_provenances "$tsvc"
  succes t7-webhook-en-service trusted_task.trusted && grep -q "non listée (preuve-test7" "$T/t7-provenances" \
    && echo "CONSTAT  vraies signatures : trusted_task.trusted en succès, la provenance de preuve-test7-hors-liste (plus ancienne, non listée) restant dans le tag .att" \
    || { echo "KO   en-service : trusted_task.trusted absente des succès, ou provenance de preuve-test7 perdue" >&2; ko=$((ko + 1)); }
  garder apres
  [ "$ko" = 0 ] || { echo "KO   test 7 : $ko mesure(s) contraire(s) à la prédiction" >&2; exit 1; }
}

etape_attseule() { # test 7, complément : attestation signée sans signature d'image (constat du banc C), dans la porte du cluster
  local r v ko=0
  echo "## prédiction (étape séparée du test 7 : le rejouer remettrait des provenances permanentes sur builds/essai-webhook)"
  echo "témoin att-seule ($T7_DEPOT, ConfigMap porte-temoin, source attendue) : provenance réelle listée au sujet réécrit, tag .att signé"
  echo "  par une clé jetable, aucun tag .sig (Chains reste en mode dsse : la porte doit refuser une attestation valide sans signature) ;"
  echo "  refusée, builtin.image.signature_check présent, builtin.attestation.signature_check absent (l'attestation est valide) ;"
  echo "  ensemble complet relevé (ec évalue-t-il les règles quand une seule des deux vérifications échoue : non lu)"
  echo "non couvert : le format bundle de cosign v3 (referrers), qui faisait passer l'attaque au banc C ; Chains est en mode dsse"
  cmp -s <(kubectl get configmap -n porte porte -o jsonpath='{.data.porte\.rego}') "$here/politique/porte/porte.rego" \
    && echo "OK   ConfigMap porte : porte.rego identique au fichier versionné" || { echo "KO   ConfigMap porte différente" >&2; exit 1; }
  garder avant
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  auth_zot "$T/auth/zot.json"
  RC_PASSAGE=$(date -u +%Y%m%dT%H%M%SZ)
  (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$T/auth/rc.key")
  openssl pkey -in "$T/auth/rc.key" -pubout -out "$T/rc.pub"
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$APP" 2>/dev/null \
    | jq -c 'select(.payload | @base64d | fromjson | .predicate.buildDefinition.externalParameters.runSpec.pipelineRef != null)' \
    | jq -sc 'max_by(.payload | @base64d | fromjson | .predicate.runDetails.metadata.finishedOn)' > "$T/rc-env-chains.json"
  jq -r .payload "$T/rc-env-chains.json" | base64 -d > "$T/rc-prov.json"
  t7_prov L '.'
  T7_SANS_SIG=1 t7_temoin att-seule L
  echo "tags du témoin : $(SSL_CERT_FILE=$P/ca-poc.crt crane ls "$REG_HOTE/$T7_DEPOT" 2>/dev/null | grep -F "$(cut -c8-71 "$T/t7-att-seule.image")" | sed 's/^sha256-.\{64\}//' | paste -sd' ' -)"
  kubectl get configmap -n porte porte -o json | jq --rawfile k "$T/rc.pub" '.data["chains.pub"] = $k
    | .metadata = {name: "porte-temoin", namespace: "porte"}' | kubectl apply --server-side -f - >/dev/null
  r=$(juger t7-att-seule "$REG/$T7_DEPOT@$(cat "$T/t7-att-seule.image")" policy.yaml porte-temoin \
    "$(jq -nc --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" --arg r "$TETE_J2" '{git: {url: $u, revision: $r}}')")
  echo "  $r"
  v=$(cut -d'|' -f4 <<< "$r")
  [ "$(cut -d'|' -f1,3 <<< "$r")" = "VERDICT|false" ] && grep -qw builtin.image.signature_check <<< "$v" && ! grep -qw builtin.attestation.signature_check <<< "$v" \
    && echo "OK   att-seule : refusée par builtin.image.signature_check, attestation acceptée ; violations : $v" \
    || { echo "KO   att-seule : prédiction" >&2; ko=1; }
  jq -r '[.components[] | .violations[]?] | map("\(.metadata.code) : \(.msg | .[0:160])") | .[]' "$T/porte-t7-att-seule.json" | sed 's/^/  motif : /'
  kubectl delete configmap -n porte porte-temoin --ignore-not-found >/dev/null
  echo "ConfigMap porte-temoin retirée ; clé jetable effacée avec $T/auth à la sortie"
  garder apres
  [ "$ko" = 0 ] || { echo "KO   att-seule : mesure contraire à la prédiction" >&2; exit 1; }
}

T8_BUNDLES=horodatage/essais-test8   # bundles d'essai du test 8, écrits par poc-horodatage (horodatage/** seulement ; non supprimables)
T8_DEPOT=essais-j8/test8             # témoins au format bundle de cosign v3 (non supprimables de Zot)
TYPE_BUNDLE=application/vnd.dev.sigstore.bundle.v0.3+json

t8_index() { # digest : bundles de ce digest dans horodatage/bundles (referrers, lecture anonyme), un fichier par bundle dans $T/t8-b ;
  # lignes « signature fichier » sur la sortie
  local m l
  mkdir -p "$T/t8-b"
  curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$DEPOT_BUNDLES/referrers/$1" \
    | jq -r --arg t "$TYPE_BUNDLE" '.manifests[] | select(.artifactType == $t) | .digest' | while read -r m; do
      l=$(curl -fsS --cacert "$P/ca-poc.crt" -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
        "https://$REG_HOTE/v2/$DEPOT_BUNDLES/manifests/$m" | jq -r '.layers[0].digest')
      curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$DEPOT_BUNDLES/blobs/$l" > "$T/t8-b/${m#sha256:}.json"
      echo "$(jq -r '.dsseEnvelope.signatures[0].sig' "$T/t8-b/${m#sha256:}.json") $T/t8-b/${m#sha256:}.json"
    done
}

t8_publier() { # cas fichier… : bundles publiés par poc-horodatage en referrers de builds/sample-app@APP_DIGEST (manifeste fait main :
  # sujet hors du dépôt, comme tsa.sh publier_bundle), dans $T8_BUNDLES/<cas>-<passage> ; dépôt sur la sortie
  local r=$T8_BUNDLES/$1-$T8_PASSAGE f i=0 o=(--ca-file "$P/ca-poc.crt" --registry-config "$T/auth/horodatage.json"); shift
  printf '{}' > "$T/t8-vide.json"
  oras blob push "${o[@]}" "$REG_HOTE/$r" "$T/t8-vide.json" >/dev/null
  for f in "$@"; do
    i=$((i + 1))
    oras blob push "${o[@]}" "$REG_HOTE/$r" "$f" >/dev/null
    jq -n --arg t "$TYPE_BUNDLE" --arg ld "sha256:$(sha256sum < "$f" | cut -c1-64)" --argjson ls "$(stat -c%s "$f")" \
      --arg pt "$(jq -r '.dsseEnvelope.payload | @base64d | fromjson | .predicateType' "$f")" --slurpfile s "$T/t8-sujet.json" '{
      schemaVersion: 2, mediaType: "application/vnd.oci.image.manifest.v1+json", artifactType: $t,
      config: {mediaType: "application/vnd.oci.empty.v1+json", digest: "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", size: 2},
      layers: [{mediaType: $t, digest: $ld, size: $ls}],
      subject: $s[0], annotations: {"dev.sigstore.bundle.content": "dsse-envelope", "dev.sigstore.bundle.predicateType": $pt}}' > "$T/t8-manifeste.json"
    oras manifest push "${o[@]}" "$REG_HOTE/$r:b$i" "$T/t8-manifeste.json" >/dev/null
  done
  echo "$r"
}

t8_jeton() { # bundle jeton-der sortie : bundle dont le jeton RFC 3161 est remplacé
  jq -c --arg t "$(base64 -w0 "$2")" '.verificationMaterial.timestampVerificationData.rfc3161Timestamps[0].signedTimestamp = $t' "$1" > "$3"
}

t8_cas() { # cas attendu (ok ou refus) dépôt-des-bundles couvertes-attendues (« k/n ») : image réelle, source attendue, porte du cluster ;
  # ec doit admettre (aucune violation), le contrôle 9 rendre l'attendu ; ko incrémenté
  local r
  r=$(juger "t8-$1" "$REG/$APP" policy.yaml porte "$SRC8" "$REG/$3")
  echo "  $r"
  grep -v '^HORODATAGE|' "$T/porte-t8-$1.horodatage" | sed 's/^/    /'
  [ "$(cut -d'|' -f1,3,4,7 <<< "$r")" = "VERDICT|true||$2" ] && grep -q "^$4 enveloppe" <<< "$(cut -d'|' -f8 <<< "$r")" \
    && echo "OK   $1 : ec admet, contrôle 9 $2 ($4 couvertes) : porte $([ "$2" = ok ] && echo admet || echo refuse)" \
    || { echo "KO   $1 : contrôle 9 $2 ($4 couvertes) prédit" >&2; ko=$((ko + 1)); }
}

t8_ancien() { # cas dépôt attendu (accepté ou refusé) : chemin de J6 sur l'hôte (cosign verify-attestation, bundles du dépôt : un bundle
  # valide du digest suffit, sans lien avec les enveloppes de l'image jugée) ; ko incrémenté
  local k n
  if COSIGN_REPOSITORY=$REG_HOTE/$2 cosign verify-attestation --key "$R/chains-cle-publique.pem" --insecure-ignore-tlog \
      --use-signed-timestamps --trusted-root "$P/tsa-racine-confiance.json" --type slsaprovenance1 \
      --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$APP" > "$T/t8-ancien.out" 2>/dev/null; then k=accepté; else k=refusé; fi
  n=$(grep -c . "$T/t8-ancien.out" || true)
  [ "$k" = "$3" ] && echo "OK   ancien contrôle (J6), $1 : $k, $n bundle(s) vérifié(s), comme prédit" \
    || { echo "KO   ancien contrôle (J6), $1 : $k ($3 prédit)" >&2; ko=$((ko + 1)); }
}

t8_v3() { # cas signer (0 ou 1) : témoin de T8_DEPOT au format bundle de cosign v3 (referrers dans le dépôt de l'image), clé jetable :
  # attestation de la provenance réelle (prédicat repris, sujet posé par cosign), plus la signature d'image si signer=1 ; digest dans
  # $T/t8-<cas>.image
  local d o=(--key "$T/auth/v3.key" --new-bundle-format --use-signing-config=false --tlog-upload=false --yes --registry-cacert "$P/ca-poc.crt")
  d=$(DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt crane mutate --label "poc.test/cas=test8-$1-$RC_PASSAGE" \
    -t "$REG_HOTE/$T8_DEPOT:$1" "$REG_HOTE/$APP" 2>/dev/null)
  d=${d##*@}; echo "$d" > "$T/t8-$1.image"
  DOCKER_CONFIG=$T/auth/docker COSIGN_PASSWORD='' cosign attest "${o[@]}" --type slsaprovenance1 --predicate "$T/t8-predicat.json" \
    "$REG_HOTE/$T8_DEPOT@$d" > "$T/t8-cosign.out" 2>&1 || { cat "$T/t8-cosign.out" >&2; echo "KO   cosign attest ($1)" >&2; exit 1; }
  if [ "$2" = 1 ]; then
    DOCKER_CONFIG=$T/auth/docker COSIGN_PASSWORD='' cosign sign "${o[@]}" "$REG_HOTE/$T8_DEPOT@$d" > "$T/t8-cosign.out" 2>&1 \
      || { cat "$T/t8-cosign.out" >&2; echo "KO   cosign sign ($1)" >&2; exit 1; }
  fi
  echo "$1 : $T8_DEPOT@$d ; referrers : $(curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$T8_DEPOT/referrers/$d" \
    | jq -r '[.manifests[] | "\(.artifactType) (\(.annotations["dev.sigstore.bundle.predicateType"] // "-"))"] | join(", ")') ;"\
    "tags .sig/.att : $(SSL_CERT_FILE=$P/ca-poc.crt crane ls "$REG_HOTE/$T8_DEPOT" 2>/dev/null | grep -c "^sha256-${d#sha256:}\." || true)"
  echo "  sur l'hôte, clé jetable : cosign verify $(cosign verify --key "$T/auth/v3.pub" --insecure-ignore-tlog --new-bundle-format \
    --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$T8_DEPOT@$d" >/dev/null 2>&1 && echo accepte || echo refuse),"\
    "cosign verify-attestation $(cosign verify-attestation --key "$T/auth/v3.pub" --insecure-ignore-tlog --new-bundle-format \
    --type slsaprovenance1 --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$T8_DEPOT@$d" >/dev/null 2>&1 && echo accepte || echo refuse)"
}

etape_test8() {
  local ko=0 e1 e2 s1 s2 b1 b2 bw x r v n w a
  echo "## prédiction (contrôle 9 joint à la porte : politique/porte/horodatage.sh, conteneur horodatage du Job, après ec)"
  echo "règle : chaque signature d'attestation vérifiée par ec doit se retrouver dans un bundle du dépôt de bundles vérifié par cosign v3.1.4"
  echo "  (clé de Chains, sujet = digest jugé, slsaprovenance1, jeton exigé, racine du TSA) ; aucune attestation vérifiée par ec : refus."
  echo "  Porte = ec admet ET contrôle 9 ok. Image réelle $APP, source attendue (test 7) ; ec admet dans tous les cas ci-dessous"
  echo "reel (horodatage/bundles) : ok, n/n ; copie (les n bundles réels, dépôt d'essai) : ok ; aucun : refus, 0/n ; partiel (1 bundle) : refus, 1/n"
  echo "sans-jeton, jeton-altere, autre-signature (jetons échangés), tsa-etrangere : refus, 0/n (motifs de J5 relevés sur l'hôte en J5)"
  echo "webhook-seul (bundles valides de deux enveloppes de builds/essai-webhook, même digest) : refus, 0/n, cosign en vérifie 2"
  echo "autre-digest (bundle valide, Chains et TSA, d'un autre digest, rattaché à $APP par poc-horodatage) : refus, 0/n ; sur l'hôte,"
  echo "  cosign verify-blob-attestation : vérifié avec son digest, refusé avec ${APP_DIGEST:0:19}… (motif relevé : le sujet est-il imposé ?)"
  echo "melange (n bundles réels + autre-digest + un sans jeton) : ok, n/n (poc-horodatage ne bloque pas une image en ajoutant des bundles)"
  echo "ancien contrôle de J6 (un bundle valide du digest suffit), sur l'hôte : copie et partiel et webhook-seul acceptés (CONSTAT), aucun refusé"
  echo "poc-images (builds/essai-images@${APP_DIGEST:7:8}, sans Chains) : ec refuse (signatures, comme au test 7), contrôle 9 refus (aucune attestation)"
  echo "format bundle de cosign v3, témoins de $T8_DEPOT (clé jetable, ConfigMap porte-temoin) :"
  echo "  v3-att (attestation seule, attaque du banc C) : builtin.image.signature_check parmi les succès malgré 0 signature (banc C) ;"
  echo "    refus par porte.image_signature et subject_build_task_matches (sujet du témoin ≠ résultat de build, comme au test 7) ;"
  echo "  v3-sig (signature et attestation) : subject_build_task_matches seule, porte.image_signature parmi les succès ;"
  echo "  contrôle 9 refus pour les deux (aucun bundle horodaté de ces digests)"
  echo "limites écrites d'avance : image d'outils non signée dans la porte ; image neuve refusée jusqu'au passage suivant du CronJob ;"
  echo "  sorties du pod : celles de la NetworkPolicy porte (DNS, Zot), vérification hors ligne"
  garder avant
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  auth_zot "$T/auth/horodatage.json" "" poc-horodatage
  RC_PASSAGE=$(date -u +%Y%m%dT%H%M%SZ); T8_PASSAGE=$(tr 'A-Z' 'a-z' <<< "$RC_PASSAGE")
  SRC8=$(jq -nc --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" --arg r "$TETE_J2" '{git: {url: $u, revision: $r}}')
  [ "$(tete)" = "$TETE_J2" ] && echo "OK   tête de main dans Forgejo : $TETE_J2 (source attendue)" || { echo "KO   tête de main différente de $TETE_J2" >&2; exit 1; }

  echo "## porte élargie"
  cm_porte
  cmp -s <(kubectl get configmap -n porte porte -o jsonpath='{.data.horodatage\.sh}') "$here/politique/porte/horodatage.sh" \
    && cmp -s <(kubectl get configmap -n porte porte -o jsonpath='{.data.porte\.rego}') "$here/politique/porte/porte.rego" \
    && echo "OK   ConfigMap porte : horodatage.sh, porte.rego identiques aux fichiers versionnés ; racine de confiance du TSA ajoutée" \
    || { echo "KO   ConfigMap porte" >&2; exit 1; }
  echo "Job : ec ($PORTE@${PORTE_DIGEST:7:8}, conteneur d'initialisation, --strict=false), puis horodatage ($OUTILS@${OUTILS_DIGEST:7:8})"
  kubectl get networkpolicy -n porte porte -o json | jq -r '"sorties de la NetworkPolicy porte : " + ([.spec.egress[] | (.to[0] | if .ipBlock then .ipBlock.cidr else "kube-dns" end)
    + ":" + ([.ports[].port | tostring] | unique | join(","))] | join(" ; ")) + " ; entrées : aucune"'

  echo "## enveloppes de l'image réelle et bundles de son digest (horodatage/bundles)"
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$APP" 2>/dev/null | jq -r '.signatures[0].sig' > "$T/t8-sigs"
  n=$(grep -c . "$T/t8-sigs")
  [ "$n" = 2 ] || { echo "KO   $n enveloppe(s) de Chains sur $APP, 2 attendues (prédictions en n = 2)" >&2; exit 1; }
  s1=$(sed -n 1p "$T/t8-sigs"); s2=$(sed -n 2p "$T/t8-sigs")
  t8_index "$APP_DIGEST" > "$T/t8-index"
  b1=$(awk -v s="$s1" '$1 == s {print $2; exit}' "$T/t8-index"); b2=$(awk -v s="$s2" '$1 == s {print $2; exit}' "$T/t8-index")
  [ -n "$b1" ] && [ -n "$b2" ] || { echo "KO   enveloppe de l'image réelle sans bundle" >&2; exit 1; }
  echo "$APP : $n enveloppes ; $(wc -l < "$T/t8-index") bundles pour ${APP_DIGEST:0:19}… (toutes les images de ce digest)"
  oras manifest fetch --ca-file "$P/ca-poc.crt" --descriptor "$REG_HOTE/$APP" > "$T/t8-sujet.json"
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-webhook@$APP_DIGEST" 2>/dev/null \
    | jq -r '.signatures[0].sig' | grep -v -x -F -f "$T/t8-sigs" | while read -r x; do awk -v s="$x" '$1 == s {print $2; exit}' "$T/t8-index"; done \
    | awk 'NF && n < 2 {print; n++}' > "$T/t8-webhook"
  [ "$(grep -c . "$T/t8-webhook")" = 2 ] || { echo "KO   moins de deux bundles d'enveloppes de builds/essai-webhook" >&2; exit 1; }

  echo "## bundles falsifiés (à partir des deux bundles réels)"
  jq -c 'del(.verificationMaterial.timestampVerificationData)' "$b1" > "$T/t8-sj1.json"
  jq -c 'del(.verificationMaterial.timestampVerificationData)' "$b2" > "$T/t8-sj2.json"
  for i in 1 2; do
    jq -r '.verificationMaterial.timestampVerificationData.rfc3161Timestamps[0].signedTimestamp' "$(eval echo "\$b$i")" | base64 -d > "$T/t8-jeton$i.der"
    python3 -I -c 'import sys; b = bytearray(open(sys.argv[1], "rb").read()); b[-1] ^= 1; open(sys.argv[2], "wb").write(b)' "$T/t8-jeton$i.der" "$T/t8-alt$i.der"
  done
  t8_jeton "$b1" "$T/t8-alt1.der" "$T/t8-alt1.json"; t8_jeton "$b2" "$T/t8-alt2.der" "$T/t8-alt2.json"
  t8_jeton "$b1" "$T/t8-jeton2.der" "$T/t8-ech1.json"; t8_jeton "$b2" "$T/t8-jeton1.der" "$T/t8-ech2.json"
  echo "jeton altéré : dernier octet (signature ECDSA du TSA) inversé ; jetons échangés entre les deux enveloppes"
  # TSA étrangère (tsa.sh chemins) : même forme, même CN, autre racine, jeton sur les octets bruts de chaque signature
  mkdir -p "$T/t8-etrangere" && cd "$T/t8-etrangere"
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out racine.key 2>/dev/null
  openssl req -x509 -new -key racine.key -subj "/O=Ailleurs/CN=Racine TSA etrangere" -days 30 -sha256 -config "$here/tsa/pki.cnf" -extensions racine_tsa -out racine.crt
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out feuille.key 2>/dev/null
  openssl pkey -in feuille.key -pubout -out feuille.pub
  openssl x509 -new -force_pubkey feuille.pub -subj "/O=Ailleurs/CN=TSA du PoC" -CA racine.crt -CAkey racine.key -set_serial 2 -days 30 -sha256 \
    -extfile "$here/tsa/pki.cnf" -extensions feuille_tsa -out feuille.crt
  printf '[ tsa ]\ndefault_tsa = e\n[ e ]\nserial = ./serial\nsigner_cert = ./feuille.crt\nsigner_key = ./feuille.key\nsigner_digest = sha256\ndefault_policy = 1.3.6.1.4.1.57264.2\ndigests = sha256\ness_cert_id_alg = sha256\ness_cert_id_chain = no\n' > ts.cnf
  echo 01 > serial
  for i in 1 2; do
    jq -r '.dsseEnvelope.signatures[0].sig' "$(eval echo "\$b$i")" | base64 -d > sig$i.bin
    openssl ts -query -data sig$i.bin -sha256 -cert -out req$i.tsq 2>/dev/null
    openssl ts -reply -queryfile req$i.tsq -config ts.cnf -out rep$i.tsr 2>/dev/null
    openssl ts -verify -data sig$i.bin -in rep$i.tsr -CAfile racine.crt -untrusted feuille.crt 2>&1 | grep -q '^Verification: OK' \
      || { echo "KO   TSA étrangère ($i)" >&2; exit 1; }
    t8_jeton "$(eval echo "\$b$i")" rep$i.tsr "$T/t8-etr$i.json"
  done
  cd - >/dev/null
  echo "TSA étrangère : jetons valides pour leur propre racine (même CN « TSA du PoC », autre clé)"
  # Bundle valide d'un autre digest : étiquette <digest>-<empreinte> de horodatage/bundles (horodater.sh), premier autre digest trié
  a=$(oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/$DEPOT_BUNDLES" | grep -E '^[0-9a-f]{64}-[0-9a-f]{16}$' | grep -v "^${APP_DIGEST#sha256:}-" | sort | awk 'NR == 1')
  [ -n "$a" ] || { echo "KO   aucun bundle d'un autre digest" >&2; exit 1; }
  x=$(curl -fsS --cacert "$P/ca-poc.crt" -H 'Accept: application/vnd.oci.image.manifest.v1+json' "https://$REG_HOTE/v2/$DEPOT_BUNDLES/manifests/$a" | jq -r '.layers[0].digest')
  curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$DEPOT_BUNDLES/blobs/$x" > "$T/t8-autre.json"
  x=sha256:$(jq -r '.dsseEnvelope.payload | @base64d | fromjson | .subject[0].digest.sha256' "$T/t8-autre.json")
  echo "autre digest : bundle $a de $DEPOT_BUNDLES, sujet ${x:0:19}… ($(jq -r '.dsseEnvelope.payload | @base64d | fromjson | .subject[0].name' "$T/t8-autre.json"))"
  for d in "$x" "$APP_DIGEST"; do
    if cosign verify-blob-attestation --bundle "$T/t8-autre.json" --new-bundle-format --key "$R/chains-cle-publique.pem" --insecure-ignore-tlog \
        --type slsaprovenance1 --use-signed-timestamps --trusted-root "$P/tsa-racine-confiance.json" --digest "${d#sha256:}" --digestAlg sha256 \
        > "$T/t8-blob.out" 2>&1; then v=vérifié; else v=refusé; fi
    echo "  cosign verify-blob-attestation, --digest ${d:0:19}… : $v ($({ grep -m1 '^Error: ' "$T/t8-blob.out" || echo "-"; } | sed 's/^Error: //' | cut -c1-200))"
    { [ "$d" = "$x" ] && [ "$v" = vérifié ]; } || { [ "$d" = "$APP_DIGEST" ] && [ "$v" = refusé ]; } \
      || { echo "KO   bundle d'un autre digest : $v avec ${d:0:19}…" >&2; ko=$((ko + 1)); }
  done

  echo "## dépôts d'essai ($T8_BUNDLES/<cas>-$T8_PASSAGE, écrits par poc-horodatage)"
  for c in "copie $b1 $b2" "aucun" "partiel $b1" "sans-jeton $T/t8-sj1.json $T/t8-sj2.json" "jeton-altere $T/t8-alt1.json $T/t8-alt2.json" \
      "autre-signature $T/t8-ech1.json $T/t8-ech2.json" "tsa-etrangere $T/t8-etr1.json $T/t8-etr2.json" "webhook-seul $(paste -sd' ' "$T/t8-webhook")" \
      "autre-digest $T/t8-autre.json" "melange $b1 $b2 $T/t8-autre.json $T/t8-sj1.json"; do
    set -- $c
    echo "$1 : $(t8_publier "$@") ($(($# - 1)) bundle(s))"
  done

  echo "## verdicts de la porte (image réelle, source attendue)"
  t8_cas reel ok "$DEPOT_BUNDLES" 2/2
  succes t8-reel slsa_source_correlated.expected_source_code_reference && succes t8-reel trusted_task.trusted \
    && echo "OK   reel : même verdict de ec qu'au test 7 (expected_source_code_reference, trusted_task.trusted parmi les succès)" || { echo "KO   reel : succès de ec" >&2; ko=$((ko + 1)); }
  t8_cas copie ok "$T8_BUNDLES/copie-$T8_PASSAGE" 2/2
  t8_cas aucun refus "$T8_BUNDLES/aucun-$T8_PASSAGE" 0/2
  t8_cas partiel refus "$T8_BUNDLES/partiel-$T8_PASSAGE" 1/2
  for c in sans-jeton jeton-altere autre-signature tsa-etrangere webhook-seul autre-digest; do
    t8_cas "$c" refus "$T8_BUNDLES/$c-$T8_PASSAGE" 0/2
  done
  grep -q '|0/2 enveloppe(s) couverte(s), 2 bundle(s) vérifié(s)' <<< "$(grep -h '^HORODATAGE|' "$T/porte-t8-webhook-seul.horodatage")" \
    && echo "OK   webhook-seul : cosign vérifie les 2 bundles (valides pour le digest), aucun n'est apparié à une enveloppe de l'image jugée" \
    || { echo "KO   webhook-seul : 2 bundles vérifiés prédits" >&2; ko=$((ko + 1)); }
  t8_cas melange ok "$T8_BUNDLES/melange-$T8_PASSAGE" 2/2
  for c in sans-jeton jeton-altere autre-signature tsa-etrangere autre-digest melange; do
    echo "  cosign dans la porte, $c : $(grep -h '^HORODATAGE|' "$T/porte-t8-$c.horodatage" | cut -d'|' -f3)"
  done

  echo "## ancien contrôle de J6, sur l'hôte"
  t8_ancien copie "$T8_BUNDLES/copie-$T8_PASSAGE" accepté
  t8_ancien aucun "$T8_BUNDLES/aucun-$T8_PASSAGE" refusé
  t8_ancien partiel "$T8_BUNDLES/partiel-$T8_PASSAGE" accepté
  t8_ancien webhook-seul "$T8_BUNDLES/webhook-seul-$T8_PASSAGE" accepté
  echo "CONSTAT  l'ancien contrôle (un bundle valide du digest) accepte partiel et webhook-seul, que la porte refuse : le jeton n'y est pas lié aux enveloppes jugées"

  echo "## image sans Chains : builds/essai-images@${APP_DIGEST:7:8} (poussée par poc-images, J7)"
  r=$(juger t8-poc-images "$REG/builds/essai-images@$APP_DIGEST" policy.yaml porte "$SRC8")
  echo "  $r"
  [ "$(cut -d'|' -f1,3,4,7 <<< "$r")" = "VERDICT|false|builtin.attestation.signature_check,builtin.image.signature_check|refus" ] \
    && [ "$(cut -d'|' -f8 <<< "$r")" = "aucune attestation vérifiée par ec" ] \
    && echo "OK   poc-images : ec refuse (signatures), contrôle 9 refus (aucune attestation vérifiée par ec)" || { echo "KO   poc-images" >&2; ko=$((ko + 1)); }

  echo "## format bundle de cosign v3 : témoins à clé jetable ($T8_DEPOT)"
  (cd "$T/auth" && COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix v3 >/dev/null 2>&1)
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$APP" 2>/dev/null \
    | jq -c 'select(.payload | @base64d | fromjson | .predicate.buildDefinition.externalParameters.runSpec.pipelineRef != null)' \
    | jq -sc 'max_by(.payload | @base64d | fromjson | .predicate.runDetails.metadata.finishedOn)' | jq -r .payload | base64 -d | jq .predicate > "$T/t8-predicat.json"
  echo "prédicat repris : provenance de PipelineRun la plus récente de $APP ($(jq -r .runDetails.metadata.invocationId "$T/t8-predicat.json"))"
  t8_v3 v3-att 0
  t8_v3 v3-sig 1
  kubectl get configmap -n porte porte -o json | jq --rawfile k "$T/auth/v3.pub" '.data["chains.pub"] = $k
    | .metadata = {name: "porte-temoin", namespace: "porte"}' | kubectl apply --server-side -f - >/dev/null
  echo "ConfigMap porte-temoin : copie de porte, clé publique jetable à la place de celle de Chains"
  w=slsa_build_scripted_build.subject_build_task_matches
  r=$(juger t8-v3-att "$REG/$T8_DEPOT@$(cat "$T/t8-v3-att.image")" policy.yaml porte-temoin "$SRC8")
  echo "  $r"
  [ "$(cut -d'|' -f1,3,4,7 <<< "$r")" = "VERDICT|false|$(trier "porte.image_signature,$w")|refus" ] \
    && echo "OK   v3-att : refusée par porte.image_signature et $w ; contrôle 9 refus" || { echo "KO   v3-att : prédiction" >&2; ko=$((ko + 1)); }
  succes t8-v3-att builtin.image.signature_check \
    && echo "CONSTAT  v3-att : builtin.image.signature_check parmi les succès avec $(jq '[.components[] | .signatures // [] | length] | add' "$T/porte-t8-v3-att.json") signature d'image (banc C reproduit dans la porte du cluster)" \
    || echo "MESURE   v3-att : builtin.image.signature_check hors des succès (différent du banc C)"
  r=$(juger t8-v3-sig "$REG/$T8_DEPOT@$(cat "$T/t8-v3-sig.image")" policy.yaml porte-temoin "$SRC8")
  echo "  $r"
  [ "$(cut -d'|' -f1,3,4,7 <<< "$r")" = "VERDICT|false|$w|refus" ] && succes t8-v3-sig porte.image_signature \
    && echo "OK   v3-sig : $w seule, porte.image_signature parmi les succès ($(jq '[.components[] | .signatures // [] | length] | add' "$T/porte-t8-v3-sig.json") signature(s) d'image)" \
    || { echo "KO   v3-sig : prédiction" >&2; ko=$((ko + 1)); }
  for c in v3-att v3-sig; do
    jq -r '[.components[] | .violations[]?] | map("\(.metadata.code) : \(.msg | .[0:160])") | .[]' "$T/porte-t8-$c.json" | sed "s/^/  motif $c : /"
  done
  kubectl delete configmap -n porte porte-temoin --ignore-not-found >/dev/null
  echo "ConfigMap porte-temoin retirée ; clé jetable effacée avec $T/auth à la sortie ; ConfigMap porte laissée élargie (porte en service)"
  garder apres
  [ "$ko" = 0 ] || { echo "KO   test 8 : $ko mesure(s) contraire(s) à la prédiction" >&2; exit 1; }
}

lancer preuves J8 "$@"
