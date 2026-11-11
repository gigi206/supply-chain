#!/usr/bin/env bash
# Brique 06, jalon S4d2a (décision du propriétaire du 11/11/2026, 20:08:42 UTC : « Oui, S4d2a ») : porte étendue à la voie deb,
# avant tout trigger (S4d3). Règles de politique/porte/porte.rego de la 08 : Kata pour construire-deb (construction_kata),
# fermetures typées par le nom du résultat et préparation complète (fermeture_plateforme), construire-deb appariée à preparer-deb
# (preparation_appariee). Les contrôles 6 (VSA) et 7 (scan) du deb sont hors de S4d2a : ils refusent (échec fermé).
# Prédictions : resultats/s4d2-predictions.md, commitées avant tout lancement. Chaque étape attend un accord nommé.
#   regle   hôte seul, hors ligne : bibliothèque conforma/policy du commit de la porte (sans ses tests), ec opa check, ec opa test
#           (porte_test.rego : tests de F3 et de S4d2a), mutations (chaque condition neuve modifiée tour à tour : au moins un
#           test doit échouer, sauf survie annoncée)
#   reel    hôte, lecture anonyme de Zot (adresse IP) : provenances réelles du deb (builds/sample-app-deb@039949f9) et de
#           l'image sample-app (3a7ca1b1) vérifiées par cosign (clé de Chains) ; fermetures lues par la règle, chacune vérifiée
#           par la vraie fonction ec.sigstore.verify_attestation (clé de Chains, puis une autre clé) ; règles porte.* évaluées
#           sur ces provenances, avec ces vérifications ; témoins : provenance du deb modifiée (hors Kata, sans fermeture deb,
#           fermetures permutées, sans preparer-deb)
#   porte   cluster : Job de la porte sur le deb avant la mise à jour (ConfigMap en service) ; ConfigMap porte mise à jour
#           (cm_porte de la 08 : porte.rego et taches.yml versionnés) ; Job de la porte sur le deb, puis sur l'image sample-app
#           (non-régression). Retour arrière : ConfigMap remise avec le porte.rego enregistré avant la mise à jour
#           ($T/porte-avant.rego, égal à celui du commit a7c7405), au choix du propriétaire.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4d2.sh <étape>…   (journal : resultats/s4d2-<étape>.log)
set -euo pipefail
export LC_ALL=C

h06=$(cd "$(dirname "$0")" && pwd)
. "$h06/../08-trust-plane/politique.sh"   # here (08), commun.sh, juger, cm_porte, CPOL_COMMIT, APP_DIGEST, TETE_J2, SAMPLE_APP
for f in $(declare -F | awk '$3 ~ /^etape_/ {print $3}'); do unset -f "$f"; done   # seules les étapes de S4d2a sont appelables
R08=$here/resultats                      # clé publique de Chains (lue par cm_porte dans $R)
R=$h06/resultats                         # journaux de S4d2a et chrono.tsv de la 06
P08=$here/politique/porte
T=$W/s4d2-06
mkdir -p "$T"
CPOL=$O/telechargements/conforma-policy   # dépôt de la bibliothèque (politique.sh porte), commit CPOL_COMMIT

DEB=builds/sample-app-deb@sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e   # S4d1
APP=builds/sample-app@$APP_DIGEST                                                                  # image réelle (preuves.sh)
SRC=$(jq -nc --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" --arg r "$TETE_J2" '{git: {url: $u, revision: $r}}')
CODES='porte.construction_kata porte.fermeture_plateforme porte.preparation_appariee porte.taches_vues'   # règles évaluées sur l'hôte

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
ECARTS=0
mesure() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS=$((ECARTS + 1)); }; }

bib() { # répertoire : bibliothèque conforma/policy du commit de la porte (sans ses tests), porte.rego, porte_test.rego, taches.yml
  [ "$(git -C "$CPOL" cat-file -t "$CPOL_COMMIT" < /dev/null)" = commit ] || { echo "KO   commit $CPOL_COMMIT absent de $CPOL" >&2; exit 1; }
  rm -rf -- "${1:?}"; mkdir -p "$1"
  git -C "$CPOL" archive "$CPOL_COMMIT" policy/lib policy/release/lib < /dev/null | tar -xf - -C "$1"
  find "$1/policy" -name '*_test.rego' -delete
  cp "$P08/porte.rego" "$P08/porte_test.rego" "$P08/taches.yml" "$1/"
}

etape_regle() {
  local b=$T/regle i n a k=0 r
  bib "$b"
  echo "ec $(ec version 2>/dev/null | awk '/^Version/ {print $2}') ; bibliothèque $CPOL_COMMIT, $(find "$b/policy" -name '*.rego' | wc -l) modules"
  echo "## ec opa check"
  (cd "$b" && ec opa check policy porte.rego porte_test.rego) && echo "OK   aucune erreur"
  echo "## ec opa test"
  (cd "$b" && ec opa test -v policy porte.rego porte_test.rego taches.yml) > "$b/test.out" 2>&1 || true
  grep -E '^data\.porte_test\.|^PASS:|^FAIL:|^ERROR|error' "$b/test.out" | sed 's/ ([0-9.]*[µm]*s)$//'
  attendu "tests" "$(grep -cE '^data\.porte_test\.test_[a-z0-9_]*: PASS' "$b/test.out")/$(grep -c '^test_' "$b/porte_test.rego")" 39/39
  echo "## mutations : chaque condition modifiée tour à tour, au moins un test doit échouer (« survit » : survie annoncée, motif donné)"
  mkdir -p "$b/m"
  n=$(grep -c . "$h06/deb/mutations-porte.txt")
  for i in $(seq "$n"); do
    a=$(python3 -I - "$b/porte.rego" "$b/m/porte.rego" "$h06/deb/mutations-porte.txt" "$i" <<'PY'
import sys
src, dst, table, i = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
l = [x for x in open(table, encoding="utf-8").read().split("\n") if x][i - 1]
attendu, ancien, nouveau = l.split(" ⟹ ")
t = open(src, encoding="utf-8").read()
if t.count(ancien) != 1:
    print(f"AMBIGU|{t.count(ancien)}|{ancien}")
    sys.exit(0)
open(dst, "w", encoding="utf-8").write(t.replace(ancien, nouveau))
print(f"{attendu}|{ancien} ⟹ {nouveau or '(retirée)'}")
PY
)
    case $a in AMBIGU*) echo "KO   condition absente ou ambiguë : $a"; k=$((k + 1)); continue ;; esac
    r=$(cd "$b" && ec opa test policy m/porte.rego porte_test.rego taches.yml 2>&1 \
      | sed -n 's/^data\.porte_test\.\(test_[a-z0-9_]*\): \(FAIL\|ERROR\).*/\1/p' | sort -u | paste -sd, -) || true
    if [ "${a%%|*}" = survit ]; then
      [ -z "$r" ] && echo "OK   survit : ${a#*|}" || { echo "KO   survie annoncée, échecs : $r : ${a#*|}"; k=$((k + 1)); }
    else
      [ -n "$r" ] && echo "OK   ${a#*|} : $r" || { echo "KO   condition non couverte par les tests : ${a#*|}"; k=$((k + 1)); }
    fi
  done
  attendu "mutations conformes à l'annonce" "$k écart(s) sur $n" "0 écart(s) sur $n"
}

attestations() { # dépôt@digest (nom vu de l'hôte) fichier : énoncés vérifiés par cosign (clé de Chains), un par ligne
  cosign verify-attestation --key "$R08/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true \
    --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$1" < /dev/null 2> "$T/cosign.err" | grep '^{' | jq -c '.payload | @base64d | fromjson' > "$2"
}

evaluer() { # répertoire énoncés(fichier, un par ligne) clé(chains|autre) : codes porte.* de la règle, triés, sur cette provenance ;
  # fermetures lues par la règle et vérifiées par la vraie fonction (référence réécrite vers l'adresse de Zot vue de l'hôte)
  local b=$1 e=$2 c=$3 q
  jq -sc '{attestations: [.[] | {statement: .}]}' "$e" > "$b/entree.json"
  (cd "$b" && ec opa eval -f json -d policy -d porte.rego -d taches.yml -d "donnees-$c.json" -i entree.json 'data.porte._fermetures') \
    | jq -c '[.result[0].expressions[0].value[] | {ref, resultat, forme}]' > "$b/fermetures.json"
  q=$(jq -r --arg r "$REG" --arg h "$REG_HOTE" '[.[] | "\"\(.ref)\": ec.sigstore.verify_attestation(\"\(.ref | sub("^" + $r; $h))\", data.config.default_sigstore_opts)"]
    | "v := {" + join(", ") + "}"' "$b/fermetures.json")
  (cd "$b" && SSL_CERT_FILE=$P/ca-poc.crt ec opa eval -f json -d policy -d porte.rego -d taches.yml -d "donnees-$c.json" "$q") \
    | jq -c '{verifs: .result[0].bindings.v}' > "$b/verifs.json"
  jq -r '.verifs | to_entries[] | "  \(.key) : \(.value.attestations | length) provenance(s) vérifiée(s)\(if (.value.errors | length) > 0 then " ; " + (.value.errors[0] | gsub("\n"; " ") | .[0:120]) else "" end)"' "$b/verifs.json" >&2
  (cd "$b" && ec opa eval -f json -d policy -d porte.rego -d taches.yml -d "donnees-$c.json" -d verifs.json -d reel.rego -i entree.json \
    'd := data.porte.deny with ec.sigstore.verify_attestation as data.reel.verif') > "$b/deny.json"
  jq -r '.result[0].bindings.d[] | "  \(.code) : \(.msg | .[0:240])"' "$b/deny.json" >&2
  jq -r --arg c "$CODES" '[.result[0].bindings.d[].code | select(. as $x | $c | split(" ") | index($x))] | unique | join(",")' "$b/deny.json"
}

modifier() { # filtre jq sur le contenu des TaskRuns (fonction nom : nom de la tâche) : provenance de PipelineRun la plus récente du deb modifiée
  jq -c 'def nom: (.spec.taskRef.params // [] | map(select(.name == "name")) | .[0].value);
    def tr(f): .predicate.buildDefinition.resolvedDependencies |= map(if .name == "pipelineTask"
      then .content |= (@base64d | fromjson | f | tojson | @base64) else . end);
    '"$1" "$T/reel/deb-derniere.jsonl"
}

etape_reel() {
  local b=$T/reel c r
  bib "$b"
  cp "$R08/chains-cle-publique.pem" "$b/chains.pub"
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$b/autre.pub" 2> /dev/null
  grep -q 'https://supply-chain.example/builders/tekton-chains@v1' "$P08/policy.yaml" || { echo "KO   builder.id absent de policy.yaml" >&2; exit 1; }
  for c in chains autre; do   # données comme ec les écrit (bascule.sh reel de la 03) et ruleData de policy.yaml
    jq -n --rawfile p "$b/$c.pub" '{config: {default_sigstore_opts: {public_key: $p, ignore_rekor: true, certificate_identity: "",
      certificate_identity_regexp: "", certificate_oidc_issuer: "", certificate_oidc_issuer_regexp: "", rekor_url: ""}},
      rule_data__configuration__: {allowed_builder_ids: ["https://supply-chain.example/builders/tekton-chains@v1"]}}' > "$b/donnees-$c.json"
  done
  printf '%s\n' 'package reel' '' 'import rego.v1' '' '# Résultats réels de ec.sigstore.verify_attestation, calculés avant par evaluer (une référence par fermeture lue)' \
    'verif(ref, _) := data.verifs[ref]' > "$b/reel.rego"
  echo "## provenances vérifiées par cosign (clé de Chains)"
  attestations "$DEB" "$b/deb.jsonl"
  attestations "$APP" "$b/app.jsonl"
  for c in deb app; do
    echo "$c : $(wc -l < "$b/$c.jsonl") énoncé(s), dont $(jq -s '[.[] | select(.predicate.buildDefinition.resolvedDependencies | map(.name) | index("pipelineTask"))] | length' "$b/$c.jsonl") de PipelineRun ; le plus récent : $(jq -rs '[.[] | select(.predicate.buildDefinition.resolvedDependencies | map(.name) | index("pipelineTask"))] | max_by(.predicate.runDetails.metadata.finishedOn) | .predicate.runDetails.metadata | "\(.invocationId) \(.finishedOn)"' "$b/$c.jsonl")"
  done
  jq -cs '[.[] | select(.predicate.buildDefinition.resolvedDependencies | map(.name) | index("pipelineTask"))] | max_by(.predicate.runDetails.metadata.finishedOn)' "$b/deb.jsonl" > "$b/deb-derniere.jsonl"
  echo "## deb, clé de Chains (prédiction : aucun code porte.*)"
  mesure "deb, clé de Chains" "$(evaluer "$b" "$b/deb.jsonl" chains)" ""
  jq -r '.[] | "  fermeture lue : \(.resultat) \(.forme) \(.ref)"' "$b/fermetures.json"
  mesure "fermetures lues dans la provenance du deb" "$(jq -r 'map(.resultat + " " + .forme) | sort | join(",")' "$b/fermetures.json")" \
    "FERMETURE_DEB_ARTIFACT_INPUTS deb,FERMETURE_SOURCES_ARTIFACT_INPUTS gomod"
  echo "## deb, autre clé (prédiction : porte.fermeture_plateforme)"
  mesure "deb, autre clé" "$(evaluer "$b" "$b/deb.jsonl" autre)" porte.fermeture_plateforme
  echo "## image sample-app, clé de Chains (non-régression ; prédiction : aucun code porte.*)"
  mesure "sample-app, clé de Chains" "$(evaluer "$b" "$b/app.jsonl" chains)" ""
  echo "## témoins : provenance la plus récente du deb modifiée"
  modifier 'tr(if nom == "construire-deb" then del(.spec.podTemplate.runtimeClassName) else . end)' > "$b/t-kata.jsonl"
  modifier 'tr(if nom == "preparer-deb" then .status.results |= map(select(.name != "FERMETURE_DEB_ARTIFACT_INPUTS")) else . end)' > "$b/t-sans-fd.jsonl"
  modifier 'tr(if nom == "preparer-deb" then .status.results as $r | ($r | map(select(.name == "FERMETURE_DEB_ARTIFACT_INPUTS")) | .[0].value) as $d
    | ($r | map(select(.name == "FERMETURE_SOURCES_ARTIFACT_INPUTS")) | .[0].value) as $s
    | .status.results |= map(if .name == "FERMETURE_DEB_ARTIFACT_INPUTS" then .value = $s elif .name == "FERMETURE_SOURCES_ARTIFACT_INPUTS" then .value = $d else . end)
    else . end)' > "$b/t-permutees.jsonl"
  modifier '.predicate.buildDefinition.resolvedDependencies |= map(select(.name != "pipelineTask" or ((.content | @base64d | fromjson | nom) != "preparer-deb")))' > "$b/t-sans-preparer.jsonl"
  mesure "deb hors Kata" "$(evaluer "$b" "$b/t-kata.jsonl" chains)" porte.construction_kata
  mesure "deb sans fermeture deb" "$(evaluer "$b" "$b/t-sans-fd.jsonl" chains)" porte.fermeture_plateforme
  mesure "deb, fermetures permutées" "$(evaluer "$b" "$b/t-permutees.jsonl" chains)" porte.fermeture_plateforme
  mesure "deb sans preparer-deb" "$(evaluer "$b" "$b/t-sans-preparer.jsonl" chains)" porte.fermeture_plateforme,porte.preparation_appariee
  echo "## règles de la porte en service (commit a7c7405) sur la provenance réelle du deb (prédiction : aucun code, succès à vide)"
  git -C "$repo" show a7c7405:poc/bricks/08-trust-plane/politique/porte/porte.rego < /dev/null > "$b/porte.rego"
  mesure "deb, règles en service" "$(evaluer "$b" "$b/deb.jsonl" chains)" ""
  mesure "deb hors Kata, règles en service" "$(evaluer "$b" "$b/t-kata.jsonl" chains)" ""
  [ "$ECARTS" = 0 ] || { echo "KO   $ECARTS écart(s)" >&2; exit 1; }
}

champ() { cut -d'|' -f"$2" <<< "$1"; }

etape_porte() {
  local v c
  kubectl get configmap -n porte porte -o jsonpath='{.data.porte\.rego}' > "$T/porte-avant.rego"
  kubectl get configmap -n porte porte -o jsonpath='{.data.taches\.yml}' > "$T/taches-avant.yml"
  attendu "porte.rego en service égal à celui du commit a7c7405" \
    "$(sha256sum < "$T/porte-avant.rego" | cut -c1-64)" "$(git -C "$repo" show a7c7405:poc/bricks/08-trust-plane/politique/porte/porte.rego < /dev/null | sha256sum | cut -c1-64)"
  attendu "taches.yml en service égal au fichier versionné" "$(sha256sum < "$T/taches-avant.yml" | cut -c1-64)" "$(sha256sum < "$P08/taches.yml" | cut -c1-64)"
  echo "## deb, porte en service (prédictions : ec en succès sans violation, succès à vide des règles du PoC ; VSA et scan refusés)"
  v=$(juger s4d2-deb-avant "$REG/$DEB" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$v"
  for c in vsa scan-verifier; do sed "s/^/    $c : /" "$T/porte-s4d2-deb-avant.$c"; done
  mesure "deb avant : succès de ec" "$(champ "$v" 3)" true
  mesure "deb avant : violations" "$(champ "$v" 4)" ""
  mesure "deb avant : VSA" "$(champ "$v" 9)" refus
  mesure "deb avant : scan" "$(champ "$v" 11)" refus
  echo "## ConfigMap porte mise à jour (porte.rego de S4d2a, liste revue inchangée)"
  R=$R08 cm_porte
  attendu "porte.rego en service égal au fichier versionné" "$(kubectl get configmap -n porte porte -o jsonpath='{.data.porte\.rego}' | sha256sum | cut -c1-64)" "$(sha256sum < "$P08/porte.rego" | cut -c1-64)"
  echo "## deb, porte étendue (prédictions : ec en succès sans violation ; horodatage complet ; VSA et scan refusés)"
  v=$(juger s4d2-deb "$REG/$DEB" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$v"
  for c in horodatage vsa scan-verifier; do sed "s/^/    $c : /" "$T/porte-s4d2-deb.$c"; done
  jq -r '[.components[] | .successes[]? | .metadata.code | select(startswith("porte."))] | unique | "    succès porte.* : " + join(",")' "$T/porte-s4d2-deb.json"
  mesure "deb : succès de ec" "$(champ "$v" 3)" true
  mesure "deb : violations" "$(champ "$v" 4)" ""
  mesure "deb : avertissements" "$(champ "$v" 5)" trusted_task.tagged
  mesure "deb : horodatage" "$(champ "$v" 7)" ok
  mesure "deb : VSA" "$(champ "$v" 9)" refus
  mesure "deb : scan" "$(champ "$v" 11)" refus
  mesure "deb : règles du PoC parmi les succès" "$(jq -r '[.components[] | .successes[]? | .metadata.code | select(startswith("porte."))] | unique | join(",")' "$T/porte-s4d2-deb.json")" \
    porte.construction_kata,porte.fermeture_plateforme,porte.image_signature,porte.preparation_appariee,porte.taches_vues
  echo "## image sample-app, porte étendue (non-régression ; prédiction : verdict de c7-reelle, 07/11/2026)"
  v=$(juger s4d2-reelle "$REG/$APP" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$v"
  mesure "sample-app : succès de ec" "$(champ "$v" 3)" true
  mesure "sample-app : violations" "$(champ "$v" 4)" ""
  mesure "sample-app : avertissements" "$(champ "$v" 5)" trusted_task.tagged
  mesure "sample-app : horodatage" "$(champ "$v" 7)" ok
  mesure "sample-app : VSA" "$(champ "$v" 9)" ok
  mesure "sample-app : scan" "$(champ "$v" 11)" ok
  [ "$ECARTS" = 0 ] || { echo "KO   $ECARTS écart(s)" >&2; exit 1; }
}

lancer s4d2 S4d2a "$@"
