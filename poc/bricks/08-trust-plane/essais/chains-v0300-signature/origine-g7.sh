#!/usr/bin/env bash
# Origine de la quatrième demande de manifeste par bundle (G7 de future-deny.sh) : chaque paquet de règles qui demande les
# manifestes des bundles (tasks, trusted_task, slsa_build_scripted_build ; porte en témoin) est évalué seul par ec opa eval,
# sous la politique service puis regles (rule_data du passage -2), sur les énoncés v0.29.9 gardés par future-deny.sh
# (passage -2, lus sans écriture). Les bundles pointent vers le registre du banc, éteint : chaque demande échoue et ec écrit
# une ligne d'erreur. Puis un processus « ensemble » évalue les quatre paquets d'un coup (garde : 3 et 4 lignes par bundle).
# Passage unique du 2026-11-26 (4 KO, non expliqué, voir resultats/chains-v0300-origine-g7-predictions.md) : tel quel, le script
# rend 4 KO ; il n'est pas à relancer (un seul processus ne laisse qu'une ligne par bundle, la forme ne reproduit pas G7).
# Sans signature ni registre. Tout tourne dans un espace réseau neuf (unshare -rn, boucle locale seule).
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/origine-g7.sh
set -uo pipefail
export LC_ALL=C.UTF-8
[ -n "${BANC_ISOLE:-}" ] || exec unshare -rn env BANC_ISOLE=1 bash "$0" "$@"
ip link set lo up
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
P08=$depot/poc/bricks/08-trust-plane
LOG=$P08/resultats/chains-v0300-origine-g7${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
F=$C/future-deny/travail   # gardé par future-deny.sh, passage -2 (lecture seule ici)
T=$C/origine-g7/travail
[ ! -e ~/.cache/supply-chain-poc/chains-v0300/origine-g7/travail ] || find ~/.cache/supply-chain-poc/chains-v0300/origine-g7/travail -delete
mkdir -p "$T/biblio" "$T/regles" "$T/donnees"
CPOL=$HOME/.cache/supply-chain-poc/08/telechargements/conforma-policy
CPOL_COMMIT=$(sed -n 's/^CPOL_COMMIT=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
CPOL_ARBRE=$(sed -n 's/^CPOL_ARBRE=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
EC_BIN=$(sed -n 's/^EC_BIN=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
REG=127.0.0.1:43233   # registre du banc au passage -2 (lu dans regles.bloc, contrôlé plus bas)
PAQUETS="tasks trusted_task slsa_build_scripted_build porte"
BUNDLES="construire-image preparer-entrees publier-image"
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
entree() { # version : entrée d'ec opa eval (les deux énoncés gardés, image signée du passage -2)
  jq -c '.payload | @base64d | fromjson | {statement: .}' "$F/env-$1.jsonl" \
    | jq -s --arg ref "$REG/builds/sample-app@$(cat "$F/digest-$1")" '{attestations: ., image: {ref: $ref}}' > "$T/entree-$1.json"
}
configurer() { # politique : $T/conf-<politique>/conf.json (rule_data__configuration__)
  mkdir -p "$T/conf-$1"
  case "$1" in
    service) jq -n '{rule_data__configuration__: {allowed_builder_ids: ["https://supply-chain.example/builders/tekton-chains@v1"]}}' ;;
    regles) jq -n --arg p "oci://$REG/tekton/tasks/*" '{rule_data__configuration__: {allowed_builder_ids: ["https://supply-chain.example/builders/tekton-chains@v1"],
      trusted_task_rules_enabled: true, trusted_task_rules: {allow: {banc: [{pattern: $p}]}}}}' ;;
  esac > "$T/conf-$1/conf.json"
}
evaluer() { # version politique nom requête : sortie brute ; erreurs dans $T/err-<version>-<politique>-<nom> (écrasées)
  ec opa eval --format raw -d "$T/biblio/policy" -d "$T/regles" -d "$T/donnees" -d "$T/conf-$2" -i "$T/entree-$1.json" "$4" \
    2> "$T/err-$1-$2-$3"
}
par_bundle() { # fichier d'erreurs : « construire-image:N preparer-entrees:N publier-image:N »
  local b out=""
  for b in $BUNDLES; do out+="$b:$(grep -c "input_ref=\"[^\"]*/tekton/tasks/$b@" "$1") "; done
  echo "${out% }"
}
fonctions() { # fichier d'erreurs : fonctions nommées, triées et comptées
  grep -o 'function=[^ ]*' "$1" | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}' | sed 's/ $//'
}
autres() { # fichier d'erreurs : lignes qui ne sont pas des échecs de récupération de bundle
  grep -vc 'msg="failed to fetch image".*input_ref="[^"]*/tekton/tasks/' "$1"
}
# Prédictions (lignes par bundle, identiques pour les trois bundles)
declare -A LIGNES=(
  [29-service-tasks]=1 [29-service-trusted_task]=1 [29-service-slsa_build_scripted_build]=1 [29-service-porte]=0
  [29-service-ensemble]=3 [29-regles-ensemble]=4 [30-service-ensemble]=0 [30-regles-ensemble]=0
)
{
  echo "# origine-g7.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16)"
  attendu "réseau du banc : interfaces" "$(ip -o link | wc -l)" 1
  attendu "ec : empreinte du verrou (politique.sh)" "$(sha256sum < "$(command -v ec)" | cut -c1-64)" "$EC_BIN"
  attendu "bibliothèque : arbre de $CPOL_COMMIT" "$(git -C "$CPOL" rev-parse "$CPOL_COMMIT^{tree}")" "$CPOL_ARBRE"
  git -C "$CPOL" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$T/biblio"
  find "$T/biblio" -name '*_test.rego' -delete
  cp "$P08/politique/porte/porte.rego" "$T/regles/"
  cp "$F/politique/donnees/taches.yml" "$T/donnees/"
  attendu "porte.rego : identique à la copie du passage -2" "$(cmp -s "$T/regles/porte.rego" "$F/politique/regles/porte.rego" && echo oui || echo non)" oui
  echo "taches.yml du passage -2 : $(sha256sum < "$T/donnees/taches.yml" | cut -c1-16)"
  attendu "registre du banc : motif de regles.bloc" "$(grep -c "oci://$REG/tekton/tasks/\*" "$F/regles.bloc")" 1
  for v in 29 30; do
    entree "$v"
    echo "énoncés gardés v$v : $(sha256sum < "$F/env-$v.jsonl" | cut -c1-16), $(jq '.attestations | length' "$T/entree-$v.json") dans l'entrée"
  done
  for p in service regles; do configurer "$p"; done
  echo "== O1 : garde de données (v29)"
  attendu "service : trusted_task_rules_enabled" "$(evaluer 29 service o1a 'data.lib.rule_data.get("trusted_task_rules_enabled")')" false
  attendu "regles : trusted_task_rules_enabled" "$(evaluer 29 regles o1a 'data.lib.rule_data.get("trusted_task_rules_enabled")')" true
  attendu "service : missing_trusted_task_rules_data" "$(evaluer 29 service o1b 'data.lib.tekton.missing_trusted_task_rules_data')" true
  attendu "regles : missing_trusted_task_rules_data" "$(evaluer 29 regles o1b 'data.lib.tekton.missing_trusted_task_rules_data')" false
  for p in service regles; do
    echo "== O2/O3 : v29 $p, paquet seul (deny et warn)"
    somme=0
    for q in $PAQUETS; do
      n=$(evaluer 29 "$p" "$q" "count(data.$q.deny) + count(data.$q.warn)")
      e=$T/err-29-$p-$q
      echo "   $q : résultats $n ; lignes $(grep -c . "$e") ; par bundle $(par_bundle "$e") ; fonctions $(fonctions "$e") ; autres lignes $(autres "$e")"
      l=$(grep -c "input_ref=\"[^\"]*/tekton/tasks/publier-image@" "$e"); somme=$((somme + l))
      [ -z "${LIGNES[29-$p-$q]:-}" ] || attendu "v29 $p $q : lignes par bundle" "$(par_bundle "$e")" "construire-image:${LIGNES[29-$p-$q]} preparer-entrees:${LIGNES[29-$p-$q]} publier-image:${LIGNES[29-$p-$q]}"
    done
    attendu "v29 $p : somme par paquet (bundle publier-image)" "$somme" "$([ "$p" = service ] && echo 3 || echo 4)"
  done
  echo "== O4/O6 : ensemble (les quatre paquets dans un seul processus)"
  REQ=$(for q in $PAQUETS; do printf 'count(data.%s.deny) + count(data.%s.warn) + ' "$q" "$q"; done | sed 's/ + $//')
  for v in 29 30; do
    for p in service regles; do
      n=$(evaluer "$v" "$p" ensemble "$REQ")
      e=$T/err-$v-$p-ensemble
      echo "   v$v $p : résultats $n ; lignes $(grep -c . "$e") ; fonctions $(fonctions "$e") ; autres lignes $(autres "$e")"
      L=${LIGNES[$v-$p-ensemble]}
      attendu "v$v $p ensemble : lignes par bundle" "$(par_bundle "$e")" "construire-image:$L preparer-entrees:$L publier-image:$L"
    done
  done
  echo "## bilan : $ko KO, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
