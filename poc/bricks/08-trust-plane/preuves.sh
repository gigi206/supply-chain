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
# Aucun secret en argument de commande.
#
# Usage (racine du dépôt) : mise run confiance:preuves -- <étape>…   (journal : resultats/preuves-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/politique.sh"   # fonctions de J6 et commun.sh ; les étapes de politique.sh ne sont pas lancées
T=$W/preuves
trap 'rm -rf "$T/auth" "$W/refus.out"' EXIT
mkdir -p "$T"
EL=system:serviceaccount:declencheurs:el-forgejo
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

tentative() { # libellé compte(admin|el) fichier : création réelle, refus attendu ; motif du refus dans $T/motif
  local as=()
  [ "$2" = el ] && as=(--as "$EL")
  if kubectl create "${as[@]}" -f "$3" > "$T/creation.out" 2>&1; then
    echo "KO   $1 : créé ($(tr '\n' ' ' < "$T/creation.out"))" >&2; kubectl delete -f "$3" --wait=false >/dev/null 2>&1 || true; exit 1
  fi
  tr '\n' ' ' < "$T/creation.out" | sed 's/^Error from server\( ([A-Za-z]*)\)\{0,1\}: //; s/^error when creating "[^"]*": //' | cut -c1-260 > "$T/motif"
}

temoin() { # libellé compte(admin|el) fichier : même compte, admis en dry-run serveur
  local as=()
  [ "$2" = el ] && as=(--as "$EL")
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

lancer preuves J8 "$@"
