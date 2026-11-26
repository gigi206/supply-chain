#!/usr/bin/env bash
# Témoin de porte.preparation_appariee sur la voie deb (sample-app-deb-6391fd43…), seule règle de la porte restée sans témoin :
# j7 n'a pas de construire-deb. Sans signature : les énoncés sont ceux du banc à sec du 25/11 (banc29, banc30 : format
# slsa/v2alpha4 de v0.29.9 et v0.30.0 appelé sur les objets capturés), plus l'énoncé signé en service (v0.29.9, gardé par le
# banc à sec, égal à la sortie de banc29 selon P1). Les règles du paquet porte sont évaluées par ec opa eval (politique du
# dépôt, bibliothèque épinglée), pas par ec validate image.
# Cas :
#   signe-29            énoncé signé en service, inchangé
#   base-29, base-30    sortie à sec sur les objets capturés
#   temoin-29, -30      sortie à sec, TaskRun preparer désigné comme preparer-entrees (paramètres name et bundle de taskRef :
#                       _tache reconnaît l'un ou l'autre ; même digest de bundle) ; aucun autre champ changé
# Tout tourne dans un espace réseau neuf (unshare -rn, boucle locale seule) : aucun appel ne peut sortir de l'hôte. Les règles
# de fermeture qui vérifient une provenance (ec.sigstore.verify_attestation) échouent donc : attendu et contrôlé.
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/temoin-deb.sh
set -uo pipefail
export LC_ALL=C.UTF-8
[ -n "${BANC_ISOLE:-}" ] || exec unshare -rn env BANC_ISOLE=1 bash "$0" "$@"
ip link set lo up
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
P08=$depot/poc/bricks/08-trust-plane
LOG=$P08/resultats/chains-v0300-temoin-deb${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
O=$C/objets   # objets capturés (lecture seule ici)
T=$C/temoin-deb/travail
[ ! -e ~/.cache/supply-chain-poc/chains-v0300/temoin-deb/travail ] || find ~/.cache/supply-chain-poc/chains-v0300/temoin-deb/travail -delete
mkdir -p "$T/biblio" "$T/obj-base" "$T/obj-temoin"
N=sample-app-deb-6391fd437f26696847041be3226bbbf633f55a2f
SIGNE=$C/sorties/$N.signe.json
PORTE=$P08/politique/porte/porte.rego
CPOL=$HOME/.cache/supply-chain-poc/08/telechargements/conforma-policy
CPOL_COMMIT=$(sed -n 's/^CPOL_COMMIT=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
CPOL_ARBRE=$(sed -n 's/^CPOL_ARBRE=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
EC_BIN=$(sed -n 's/^EC_BIN=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
empreinte_journal() { # binaire → empreinte écrite dans chains-v0300-provenances.log
  sed -n "s/^src$1 : .*binaire banc$1 sha256 \([0-9a-f]*\)$/\1/p" "$P08/resultats/chains-v0300-provenances.log"
}
evaluer() { # cas requête (erreurs ajoutées, jamais écrasées)
  ec opa eval --format raw -d "$T/biblio/policy" -d "$PORTE" -i "$T/entree-$1.json" "$2" 2>> "$T/err-$1"
}
# Fermetures attendues de preparer-deb quand la vérification ne peut pas joindre le registre (début du message, avant le motif)
F_DEB='fermeture sc-stockage.poc.test:5000/builds/fermetures/sample-app-deb@sha256:bb7599a2e1cde30770fdb4405a5f9cce94de5ea5b12c358e512dfbe7d5b9f290 (FERMETURE_DEB_ARTIFACT_INPUTS) : aucune provenance de la pipeline de prefetch deb'
F_SRC='fermeture sc-stockage.poc.test:5000/builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21 (FERMETURE_SOURCES_ARTIFACT_INPUTS) : aucune provenance de la pipeline de prefetch gomod'
F_TEM='construction sans fermeture lisible dans les résultats de sa préparation | préparation preparer-entrees sans fermeture lisible dans le résultat FERMETURE_ARTIFACT_INPUTS'
# Valeurs attendues (D2 à D5), dans l'ordre : attestations de PipelineRun | tâches vues | tâches reconnues par _tache | codes
# refusés | messages de preparation_appariee | messages de fermeture_plateforme (coupés avant « de la plateforme (motif) »)
declare -A ATTENDU=(
  [signe-29]="1|3|construire-deb preparer-deb|porte.fermeture_plateforme||$F_DEB | $F_SRC"
  [base-29]="1|3|construire-deb preparer-deb|porte.fermeture_plateforme||$F_DEB | $F_SRC"
  [temoin-29]="1|3|construire-deb preparer-entrees|porte.fermeture_plateforme porte.preparation_appariee|construire-deb sans preparer-deb dans la même provenance|$F_TEM"
  [base-30]='1|0||porte.taches_vues||'
  [temoin-30]='1|0||porte.taches_vues||'
)
{
  echo "## témoin deb de preparation_appariee, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  attendu "ec : empreinte du binaire (politique.sh)" "$(sha256sum "$(command -v ec)" | cut -c1-64)" "$EC_BIN"
  attendu "bibliothèque : arbre de $CPOL_COMMIT" "$(git -C "$CPOL" rev-parse "$CPOL_COMMIT^{tree}")" "$CPOL_ARBRE"
  git -C "$CPOL" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$T/biblio"
  find "$T/biblio" -name '*_test.rego' -delete
  for v in 29 30; do
    attendu "banc$v : empreinte (chains-v0300-provenances.log)" "$(sha256sum "$C/banc/banc$v" | cut -c1-64)" "$(empreinte_journal "$v")"
  done
  echo "porte.rego : $(git -C "$depot" log -1 --format=%h -- "$PORTE"), sha256 $(sha256sum "$PORTE" | cut -c1-16)"
  echo "énoncé signé en service : sha256 $(sha256sum "$SIGNE" | cut -c1-16)"
  attendu "réseau : interfaces de l'espace" "$(ip -o link | awk -F': ' '{print $2}' | tr '\n' ' ')" "lo "
  attendu "énoncé signé : sujet = IMAGE_DIGEST du PipelineRun capturé" "sha256:$(jq -r '.subject[0].digest.sha256' "$SIGNE")" \
    "$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$O/pr-$N.json")"
  # Objets : PipelineRun et ses TaskRuns (childReferences), copiés ; le témoin ne change que la taskRef de preparer
  mapfile -t enfants < <(jq -r '.status.childReferences[].name' "$O/pr-$N.json")
  attendu "TaskRuns du PipelineRun capturés" "${#enfants[@]} $(for x in "${enfants[@]}"; do [ -s "$O/tr-$x.json" ] && echo x; done | grep -c x)" "3 3"
  cp "$O/pr-$N.json" "$T/obj-base/pr.json"; cp "$O/pr-$N.json" "$T/obj-temoin/pr.json"
  for x in "${enfants[@]}"; do
    cp "$O/tr-$x.json" "$T/obj-base/tr-$x.json"
    jq 'if .metadata.labels["tekton.dev/pipelineTask"] == "preparer" then .spec.taskRef.params |= map(
          if .name == "name" then .value = "preparer-entrees"
          elif .name == "bundle" then .value |= sub("/tekton/tasks/preparer-deb@"; "/tekton/tasks/preparer-entrees@")
          else . end) else . end' "$O/tr-$x.json" > "$T/obj-temoin/tr-$x.json"
  done
  attendu "témoin : objets changés (fichiers différents de la base)" "$(for f in "$T"/obj-base/*.json; do cmp -s "$f" "$T/obj-temoin/${f##*/}" || echo "${f##*/}"; done | sed 's/.*-//')" "preparer.json"
  attendu "témoin : champs changés dans preparer (chemins)" "$(diff <(jq -c 'paths(scalars) as $p | [$p, getpath($p)]' "$T"/obj-base/tr-*-preparer.json) <(jq -c 'paths(scalars) as $p | [$p, getpath($p)]' "$T"/obj-temoin/tr-*-preparer.json) | sed -n 's/^> \[\(\[[^]]*\]\).*/\1/p' | tr '\n' ' ')" \
    '["spec","taskRef","params",0,"value"] ["spec","taskRef","params",1,"value"] '
  for m in base temoin; do
    for v in 29 30; do
      "$C/banc/banc$v" "$T/obj-$m/pr.json" "$T"/obj-$m/tr-*.json > "$T/st-$m-$v.json" 2> "$T/banc-$m-$v.err"
      attendu "banc$v $m : énoncé produit, sans erreur" "$(jq -r '.predicateType' "$T/st-$m-$v.json") $(wc -c < "$T/banc-$m-$v.err")" "https://slsa.dev/provenance/v1 0"
    done
  done
  cp "$SIGNE" "$T/st-signe-29.json"
  # Le champ changé, lu dans l'énoncé (dépendance pipelineTask pour v0.29.9, pipelineTask/preparer pour v0.30.0)
  for c in signe-29 base-29 base-30 temoin-29 temoin-30; do
    case $c in signe-29) attente=preparer-deb ;; base-*) attente=preparer-deb ;; temoin-*) attente=preparer-entrees ;; esac
    case $c in *-29) dep=pipelineTask ;; *-30) dep=pipelineTask/preparer ;; esac
    attendu "$c : taskRef de preparer dans l'énoncé (dépendance $dep)" "$(jq -r --arg d "$dep" '[.predicate.buildDefinition.resolvedDependencies[] | select(.name == $d) | .content | @base64d | fromjson
        | select(.metadata.labels["tekton.dev/pipelineTask"] == "preparer") | .spec.taskRef.params[] | select(.name == "name" or .name == "bundle") | .value | sub("@sha256:.*"; "")] | join(" ")' "$T/st-$c.json")" \
      "sc-stockage.poc.test:5000/tekton/tasks/$attente $attente"
    jq -n --slurpfile s "$T/st-$c.json" '{attestations: [{statement: $s[0]}]}' > "$T/entree-$c.json"
  done
  for c in signe-29 base-29 temoin-29 base-30 temoin-30; do
    echo "-- $c"
    # le dernier champ garde ses « | » (messages de fermeture joints par « | ») : read lui donne le reste de la ligne
    IFS='|' read -r z_att z_taches z_reconnues z_codes z_appariee z_ferm <<< "${ATTENDU[$c]}"
    debut=$(date +%s%N)
    attendu "$c : attestations de PipelineRun" "$(evaluer "$c" 'count(data.lib.pipelinerun_attestations)')" "$z_att"
    attendu "$c : tâches vues" "$(evaluer "$c" 'count(data.lib.tasks_from_pipelinerun)')" "$z_taches"
    attendu "$c : tâches reconnues par _tache" "$(evaluer "$c" 'concat(" ", sort({n | some n in ["construire-deb", "construire-image", "preparer-deb", "preparer-entrees"]; some t in data.lib.tasks_from_pipelinerun; data.porte._tache(t, n)}))')" "$z_reconnues"
    attendu "$c : codes refusés par la porte" "$(evaluer "$c" 'concat(" ", sort({r.code | some r in data.porte.deny}))')" "$z_codes"
    attendu "$c : messages de preparation_appariee" "$(evaluer "$c" 'concat(" | ", sort([r.msg | some r in data.porte.deny; r.code == "porte.preparation_appariee"]))')" "$z_appariee"
    attendu "$c : messages de fermeture_plateforme" "$(evaluer "$c" 'concat(" | ", sort([m | some r in data.porte.deny; r.code == "porte.fermeture_plateforme"; m := split(r.msg, " de la plateforme (")[0]]))')" "$z_ferm"
    echo "     durée des six requêtes : $(( ($(date +%s%N) - debut) / 1000000 )) ms"
    [ ! -s "$T/err-$c" ] || { echo "KO   $c : erreurs d'évaluation"; sed 's/^/     /' "$T/err-$c" | head -5; ko=$((ko + 1)); }
  done
  echo "## bilan : $ko KO, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
