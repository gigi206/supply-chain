#!/usr/bin/env bash
# Cause du silence de slsa_build_scripted_build.build_script_used sur une provenance SLSA v1 (porte en service, Chains v0.29.9).
# La règle (conforma/policy, commit épinglé dans politique.sh) refuse si une tâche de construction a zéro étape lue par
# task_steps (champ steps au premier niveau, absent d'un TaskRun v1), mais son message lit build_task.name (absent aussi :
# un TaskRun porte metadata.name) : si ce terme est indéfini, le corps de la règle échoue et rien n'est refusé.
# Évaluation directe de la règle par ec opa eval (sans signature ni registre) sur l'énoncé signé du PipelineRun gardé par
# temoins.sh (passage -3), avec deux contrôles qui ne changent que l'entrée non signée :
#   nom          champ name (= étiquette tekton.dev/pipelineTask) ajouté au premier niveau de chaque TaskRun   la règle doit refuser
#   nom-etapes   même chose, plus steps non vide                                                              la règle doit se taire
# Passage -2 : chaque valeur est contrôlée (attendu) et les erreurs de toutes les requêtes sont gardées (2>>).
# Tout tourne dans un espace réseau neuf (unshare -rn, boucle locale seule) : aucun appel ne peut sortir de l'hôte.
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/cause-build-script.sh
set -uo pipefail
export LC_ALL=C.UTF-8
[ -n "${BANC_ISOLE:-}" ] || exec unshare -rn env BANC_ISOLE=1 bash "$0" "$@"
ip link set lo up
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
P08=$depot/poc/bricks/08-trust-plane
LOG=$P08/resultats/chains-v0300-cause-build-script${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
W=$C/temoins/travail   # gardé par temoins.sh (lecture seule ici)
T=$C/cause-build-script/travail
[ ! -e ~/.cache/supply-chain-poc/chains-v0300/cause-build-script/travail ] || find ~/.cache/supply-chain-poc/chains-v0300/cause-build-script/travail -delete
mkdir -p "$T/biblio"
UID_PR=$(jq -r '.metadata.uid' "$C/objets/pr-j7-sample-app.json")
CPOL=$HOME/.cache/supply-chain-poc/08/telechargements/conforma-policy
CPOL_COMMIT=$(sed -n 's/^CPOL_COMMIT=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
CPOL_ARBRE=$(sed -n 's/^CPOL_ARBRE=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
EC_BIN=$(sed -n 's/^EC_BIN=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
REGLE=slsa_build_scripted_build.build_script_used
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
enonce() { # version → énoncé du PipelineRun (invocationId = uid de j7) tiré des enveloppes gardées
  while read -r e; do
    jq -r '.payload' <<< "$e" | base64 -d > "$T/st.json"
    [ "$(jq -r '.predicate.runDetails.metadata.invocationId' "$T/st.json")" = "$UID_PR" ] && { cat "$T/st.json"; return; }
  done < "$W/env-base-$1.jsonl"
}
muter() { # version variante : entrée de ec opa eval
  local filtre=.
  case "$2" in
    nom) filtre='.name = .metadata.labels["tekton.dev/pipelineTask"]' ;;
    nom-etapes) filtre='.name = .metadata.labels["tekton.dev/pipelineTask"] | .steps = [{"name": "temoin", "image": "temoin"}]' ;;
  esac
  jq --argjson s "$(enonce "$1")" -n '{attestations: [{statement: $s}]}' \
    | jq "(.attestations[0].statement.predicate.buildDefinition.resolvedDependencies[] | select((.name // \"\") | startswith(\"pipelineTask\")) | .content)
          |= (@base64d | fromjson | $filtre | tojson | @base64)" > "$T/entree-$1-$2.json"
}
evaluer() { # version variante requête (erreurs ajoutées, jamais écrasées, d'une requête à l'autre)
  ec opa eval --format raw -d "$T/biblio/policy" -i "$T/entree-$1-$2.json" "$3" 2>> "$T/err-$1-$2"
}
# Passage -2 : valeurs attendues (Z1 à Z4), dans l'ordre : attestations de PipelineRun | tâches vues | tâches de construction
# (étiquette:name:étapes) | refus de la règle | message de build_script_used
declare -A ATTENDU=(
  [29-base]='1|3|publier:ABSENT:0||'
  [29-nom]='1|3|publier:publier:0|slsa_build_scripted_build.build_script_used|Build task "publier" does not contain any steps'
  [29-nom-etapes]='1|3|publier:publier:1||'
  [30-base]='1|0||slsa_build_scripted_build.build_task_image_results_found|'
  [30-nom]='1|0||slsa_build_scripted_build.build_task_image_results_found|'
  [30-nom-etapes]='1|0||slsa_build_scripted_build.build_task_image_results_found|'
)
{
  echo "## cause de build_script_used, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  attendu "ec : empreinte du binaire (politique.sh)" "$(sha256sum "$(command -v ec)" | cut -c1-64)" "$EC_BIN"
  attendu "bibliothèque : arbre de $CPOL_COMMIT" "$(git -C "$CPOL" rev-parse "$CPOL_COMMIT^{tree}")" "$CPOL_ARBRE"
  git -C "$CPOL" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$T/biblio"
  find "$T/biblio" -name '*_test.rego' -delete
  attendu "réseau : interfaces de l'espace" "$(ip -o link | awk -F': ' '{print $2}' | tr '\n' ' ')" "lo "
  for v in 29 30; do
    echo "enveloppes gardées v$v : $(sha256sum "$W/env-base-$v.jsonl" | cut -c1-16) ($(grep -c . "$W/env-base-$v.jsonl") attestations)"
    attendu "v$v : énoncé du PipelineRun trouvé" "$(enonce "$v" | jq -r '.predicateType')" https://slsa.dev/provenance/v1
  done
  for v in 29 30; do
    for m in base nom nom-etapes; do
      muter "$v" "$m"
      A='data.lib.pipelinerun_attestations[0]'
      echo "-- v$v $m"
      IFS='|' read -r z_att z_taches z_constr z_refus z_msg <<< "${ATTENDU[$v-$m]}"
      attendu "v$v $m : attestations de PipelineRun" "$(evaluer "$v" "$m" 'count(data.lib.pipelinerun_attestations)')" "$z_att"
      attendu "v$v $m : tâches vues" "$(evaluer "$v" "$m" "count(data.lib.tekton.tasks($A))")" "$z_taches"
      attendu "v$v $m : tâches de construction (étiquette:name:étapes)" "$(evaluer "$v" "$m" "concat(\" \", [sprintf(\"%s:%s:%d\", [t.metadata.labels[\"tekton.dev/pipelineTask\"], object.get(t, \"name\", \"ABSENT\"), count(data.slsa_build_scripted_build.task_steps(t))]) | some t in data.lib.tekton.build_tasks($A)])")" "$z_constr"
      attendu "v$v $m : refus de la règle" "$(evaluer "$v" "$m" "concat(\" \", sort([r.code | some r in data.slsa_build_scripted_build.deny]))")" "$z_refus"
      attendu "v$v $m : message de build_script_used" "$(evaluer "$v" "$m" "concat(\" | \", [r.msg | some r in data.slsa_build_scripted_build.deny; r.code == \"$REGLE\"])")" "$z_msg"
      [ ! -s "$T/err-$v-$m" ] || { echo "KO   v$v $m : erreurs d'évaluation"; sed 's/^/     /' "$T/err-$v-$m" | head -5; ko=$((ko + 1)); }
    done
  done
  echo "## bilan : $ko KO, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
