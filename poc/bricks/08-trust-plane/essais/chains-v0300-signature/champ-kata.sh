#!/usr/bin/env bash
# Lecture seule : le champ changé par le témoin construction_kata (porte.sh, passage -3 : TaskRun construire en runc au lieu
# de kata) est-il dans l'énoncé signé du PipelineRun, pour v0.29.9 (dépendance pipelineTask) et v0.30.0 (pipelineTask/<nom>) ?
# Lit les attestations vérifiées par cosign verify-attestation au passage -3, gardées dans le dossier de travail de porte.sh.
# Passage -2 : les attestations lues sont reliées au passage -3 (digest gardé, préfixe au journal, sujet signé).
# Usage (racine du dépôt) : [SUFFIXE=-2] bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/champ-kata.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
LOG=$depot/poc/bricks/08-trust-plane/resultats/chains-v0300-champ-kata${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
W=$C/porte/travail
UID_PR=$(jq -r '.metadata.uid' "$C/objets/pr-j7-sample-app.json")
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
{
  echo "## champ du témoin kata dans l'énoncé signé, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for v in 29 30; do
    echo "attestations gardées v$v : $(sha256sum "$W/att-kata-$v.json" | cut -c1-16) ($(grep -c . "$W/att-kata-$v.json") attestations)"
    n=0
    while read -r e; do
      s=$(jq -r '.payload' <<< "$e" | base64 -d)
      [ "$(jq -r '.predicate.runDetails.metadata.invocationId' <<< "$s")" = "$UID_PR" ] || continue
      n=$((n + 1))
      etat=$(jq -r '[.predicate.buildDefinition.resolvedDependencies[] | select((.name // "") | startswith("pipelineTask")) | .name as $d
        | .content | @base64d | fromjson | ($d + ">" + .metadata.labels["tekton.dev/pipelineTask"] + "=" + (.spec.podTemplate.runtimeClassName // "aucun"))] | join(" ")' <<< "$s")
      echo "v$v : $etat"
      if [ "$v" = 29 ]; then dep=pipelineTask; else dep=pipelineTask/construire; fi
      attendu "v$v : construire en runc sous $dep" "$(tr ' ' '\n' <<< "$etat" | grep -c "^$dep>construire=runc$")" 1
      attendu "v$v : runc ailleurs" "$(tr ' ' '\n' <<< "$etat" | grep -v '>construire=' | grep -c '=runc$')" 0
    done < "$W/att-kata-$v.json"
    attendu "v$v : énoncés du PipelineRun lus" "$n" 1
    # passage -2 : les fichiers gardés sont ceux du passage -3 de porte.sh (digest de l'image du témoin, préfixe au journal)
    D=$(cat "$W/digest-kata-$v")
    attendu "v$v : digest gardé = préfixe du journal porte-3" "$(grep -c "^image du témoin v$v : ${D:0:19}…$" "$depot/poc/bricks/08-trust-plane/resultats/chains-v0300-porte-3.log")" 1
    attendu "v$v : sujet de chaque attestation = digest gardé" "$(while read -r e; do jq -r '.payload' <<< "$e" | base64 -d | jq --arg d "${D#sha256:}" '[.subject[].digest.sha256] | any(. == $d)'; done < "$W/att-kata-$v.json" | sort -u | tr '\n' ' ')" "true "
  done
  echo "## bilan : $ko KO, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
