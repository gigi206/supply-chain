#!/usr/bin/env bash
# Brique 19b, J7 : banc local de suspendre_rattrapage et reprendre_rattrapage de j7.sh (correctif du 21/11/2026 : la
# reprise remet l'état relevé au départ, au lieu de false en dur). Les deux fonctions sont extraites de j7.sh telles
# quelles ; kubectl est remplacé par une fonction qui tient l'état du CronJob dans des variables. Aucun accès au cluster.
# Usage (racine du dépôt) : poc/bricks/19b-journalisation/resultats/j7-rattrapage-banc.sh > <journal>
set -euo pipefail
export LC_ALL=C
J=poc/bricks/19b-journalisation/j7.sh
echo "j7.sh : $(sha256sum "$J" | cut -c1-16)…"
F=$(awk '/^ETAT_RATTRAPAGE=/{p=1} p{print} p&&/rattrapage suspendu, aucun PipelineRun actif/{getline; print; exit}' "$J")
[ "$(printf '%s\n' "$F" | tail -n 1)" = "}" ] || { echo "KO   extraction des fonctions"; exit 1; }
echo "fonctions extraites : $(printf '%s\n' "$F" | wc -l) lignes"

cas() { # nom, suspend de départ (true, false, absent, ou autre), PipelineRuns actifs, sortie attendue en fin de cas
  local nom=$1 depart=$2 actifs=$3 attendu=$4 fin rc=0
  fin=$(
    exec 3>&1   # état final sur le descripteur 3 : un arrêt dans « suspendre_rattrapage >&2 » garde cette redirection pendant le trap
    SUSPEND=$depart; ACTIFS=$actifs
    echec() { echo "KO   $*" >&2; exit 1; }
    kubectl() {
      case "$*" in
        "get cronjob -n declencheurs rattrapage -o json")
          if [ "$SUSPEND" = absent ]; then echo '{"spec":{}}'; else echo "{\"spec\":{\"suspend\":\"$SUSPEND\"}}" | sed 's/"\(true\|false\)"}}/\1}}/'; fi ;;
        "get cronjob -n declencheurs rattrapage -o jsonpath={.spec.suspend}") echo "$SUSPEND" ;;
        "get cronjob -n declencheurs rattrapage -o jsonpath={.status.active}") echo "" ;;
        "patch cronjob -n declencheurs rattrapage --type merge -p "*)
          SUSPEND=$(printf '%s' "${*: -1}" | jq -r '.spec.suspend'); echo "  [faux kubectl] suspend <- $SUSPEND" >&2 ;;
        "get pipelineruns -n builds -o json")
          jq -nc --argjson n "$ACTIFS" '{items: [range($n) | {status: {}}]}' ;;
        *) echo "KO   appel inattendu : kubectl $*" >&2; exit 3 ;;
      esac
    }
    eval "$F"
    # même enchaînement que j7.sh : le trap EXIT posé par suspendre_rattrapage appelle reprendre_rattrapage à la sortie ;
    # l'enveloppe ajoute seulement l'état final. Le trap ci-dessous ne sert que si l'arrêt vient avant celui de la fonction.
    eval "$(declare -f reprendre_rattrapage | sed '1s/^reprendre_rattrapage/reprendre_vrai/')"
    reprendre_rattrapage() { reprendre_vrai >&2; echo "FIN suspend=$SUSPEND" >&3; }
    trap 'echo "FIN suspend=$SUSPEND" >&3' EXIT
    suspendre_rattrapage >&2
    echo "  pendant la pose : suspend=$SUSPEND" >&2
  ) || rc=$?
  fin=$(printf '%s\n' "$fin" | grep '^FIN ' || true)
  if [ "$fin" = "FIN suspend=$attendu" ]; then echo "OK   $nom : $fin (rc $rc)"; else echo "KO   $nom : '$fin' (rc $rc, attendu suspend=$attendu)"; KO=$((KO + 1)); fi
}
KO=0
echo "## cas"
cas "R1 départ false, aucun PipelineRun" false 0 false
cas "R2 départ true, aucun PipelineRun" true 0 true
cas "R3 champ suspend absent" absent 0 false
cas "R4 départ false, un PipelineRun actif (arrêt, trap)" false 1 false
cas "R5 départ true, un PipelineRun actif (arrêt, trap)" true 1 true
cas "R6 suspend illisible (arrêt avant tout patch)" bizarre 0 bizarre
echo "## bilan : $KO KO"
[ "$KO" = 0 ]
