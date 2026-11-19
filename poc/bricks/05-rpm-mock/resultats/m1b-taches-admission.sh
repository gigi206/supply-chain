#!/usr/bin/env bash
# shellcheck disable=SC2015  # ok et ko n échouent jamais
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : validation par le webhook de Tekton des deux tâches et des deux pipelines rendues par prealables sous m1bt3,
# en kubectl create --dry-run=server dans builds, comme m4b-taches-admission. Préparé à sec le 19/11/2026. Rien n'est créé, aucun
# fichier n'est écrit : les témoins passent par l'entrée standard.
# Prédictions TD1 à TD5 : m1b-predictions.md, commitées avant tout lancement.
#   TD1 les quatre rendus sont ceux de m1bt3 (sha256 fixés ci-dessous) ;
#   TD2 les deux tâches v1beta1 sont admises (code 0) ; TD3 les deux pipelines sont admises (code 0) ;
#   TD4 témoins : construire-racine-rpm avec computeResources dans le pas, et pipeline-b avec un champ inconnu dans sa
#       première tâche, refusés chacun par le décodage strict (motif compté, jamais le texte du refus) ;
#   TD5 aucune tâche ni pipeline neuve dans builds après le passage (noms avant = noms après).
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-taches-admission.sh < /dev/null > poc/bricks/05-rpm-mock/resultats/m1b-taches-admission.log 2>&1
set -euo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
umask 022
R=$HOME/.cache/supply-chain-poc/08/travail/m1bt3-05   # rendu de prealables sous m1bt3 : lecture seule
nko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; nko=$((nko + 1)); }
attendu() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else ko "$1 : obtenu « $2 », attendu « $3 »"; fi; }
admission() { # objet sur l'entrée standard : « code de kubectl, lignes du motif de décodage strict » ; jamais le texte du refus
  local rc=0 err
  err=$(kubectl create --dry-run=server -n builds -o name -f - 2>&1 > /dev/null) || rc=$?
  echo "$rc $(grep -c -F 'strict decoding error: unknown field' <<< "$err" || true)"
}
noms() { kubectl get tasks.tekton.dev,pipelines.tekton.dev -n builds -o name < /dev/null | sort; }
TEMOIN_T='.spec.steps[0].computeResources = .spec.steps[0].resources | del(.spec.steps[0].resources)'

echo "# début $(date -u +%FT%TZ) ; HEAD $(git rev-parse --short=12 HEAD) ; webhook $(kubectl get deploy -n tekton-pipelines tekton-pipelines-webhook -o jsonpath='{.spec.template.spec.containers[0].image}' < /dev/null | sed -E 's/.*@sha256:(.{12}).*/sha256:\1…/')"
echo "## TD1 rendus de m1bt3"
attendu "prefetch-racine-rpm.yaml (sha256)" "$(sha256sum < "$R/prefetch-racine-rpm.yaml" | cut -c1-64)" b0fdff3895df59897ebc30333689b24f748124ed98e1f610cb4405a170534a05
attendu "construire-racine-rpm.yaml (sha256)" "$(sha256sum < "$R/construire-racine-rpm.yaml" | cut -c1-64)" de77ba0a70b4cee401448e7f6dc161094c71b2594204425a838d7dc45bf97b08
attendu "pipeline-o.yaml (sha256)" "$(sha256sum < "$R/pipeline-o.yaml" | cut -c1-64)" 13836c388b47fe701360631db59239f67b8d787568d2af3491707422d78bfda0
attendu "pipeline-b.yaml (sha256)" "$(sha256sum < "$R/pipeline-b.yaml" | cut -c1-64)" b2443188125b63b71539cb61c73d314dd21f11aaba3a673ab263a644794870f7
avant=$(noms)
echo "tâches et pipelines dans builds avant : $(grep -c . <<< "$avant" || true)"

echo "## TD2 tâches ; TD3 pipelines"
for f in prefetch-racine-rpm construire-racine-rpm pipeline-o pipeline-b; do
  echo "$f : $(yq -o=json -I=0 '[.apiVersion, .kind, .metadata.name, (.spec.params // [] | length), (.spec.tasks // [] | length)]' "$R/$f.yaml")"
  attendu "$f admis à blanc (code de kubectl, lignes du motif)" "$(admission < "$R/$f.yaml")" "0 0"
done

echo "## TD4 témoins"
attendu "témoin tâche : seule la clé du pas change" \
  "$(cmp -s <(yq -o=json '.' "$R/construire-racine-rpm.yaml" | jq -S 'del(.spec.steps[0].resources)') <(yq -o=json "$TEMOIN_T" "$R/construire-racine-rpm.yaml" | jq -S 'del(.spec.steps[0].computeResources)') && echo égal || echo différent)" égal
read -r rc m < <(yq "$TEMOIN_T" "$R/construire-racine-rpm.yaml" | admission)
[ "$rc" != 0 ] && ok "témoin tâche refusé (code $rc)" || ko "témoin tâche admis"
attendu "témoin tâche : motif « strict decoding error: unknown field » (lignes)" "$m" 1
read -r rc m < <(yq '.spec.tasks[0].champinconnu = "x"' "$R/pipeline-b.yaml" | admission)
[ "$rc" != 0 ] && ok "témoin pipeline refusé (code $rc)" || ko "témoin pipeline admis"
attendu "témoin pipeline : motif « strict decoding error: unknown field » (lignes)" "$m" 1

echo "## TD5 rien n'est créé"
attendu "noms des tâches et pipelines de builds, avant = après" "$([ "$avant" = "$(noms)" ] && echo égal || echo différent)" égal
echo "# fin $(date -u +%FT%TZ) ; KO $nko"
[ "$nko" = 0 ]
