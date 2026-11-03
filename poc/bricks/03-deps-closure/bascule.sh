#!/usr/bin/env bash
# Brique 03, jalon F3 (protocole du 03/11/2026 ; décisions D5 a et D6 a du propriétaire) : bascule de la construction de
# sample-app sur la fermeture produite par la plateforme en F2. Prédictions : resultats/f3-predictions.md. Chaque étape qui
# modifie le cluster ou Zot est soumise à l'accord du propriétaire.
#   regle       sur l'hôte, sans le PoC : règle porte.fermeture_plateforme (D6) de politique/porte/porte.rego, ec opa check puis
#               ec opa test (politique/porte/porte_test.rego) avec la bibliothèque conforma/policy de la porte et la liste revue ;
#               mutations : chaque condition retirée doit faire échouer un test
#   reel        sur l'hôte, en lecture seule (lecture anonyme de Zot par son adresse IP) : ec opa eval avec la vraie fonction
#               ec.sigstore.verify_attestation (clé de Chains, ignore_rekor) sur la fermeture de F2, chaque provenance passée à
#               la règle ; fermeture lue par la règle dans la provenance archivée de J7 ; autre clé refusée
#   taches      preparer-entrees, construire-image (D5 : workspace entrees en lecture seule) et publier-image rendues, signées
#               (tkn), comparées à leur signature versionnée (SIGNER=construire-image pour refaire la seule signature de
#               construire-image), bundles, digests exigés dans la liste revue ; pipeline sample-app (workspace lié par sous-
#               dossier, fermeture de la plateforme F2) signée, bundle (étiquette f3)
#   temoins     fermeture altérée (zip de module valide mais modifié, poussée par poc-ecriture dans entrees/) et fermeture
#               absente (digest inexistant) : pipelines signées, images dans builds/essai-f3 (jamais builds/sample-app : la
#               porte ne juge que la provenance la plus récente) ; PipelineRuns en échec fermé, rien de poussé
#   lecture_seule  témoin de D5 : PVC écrit par un pod runc, puis monté en sous-dossier readOnly par un pod Kata privilégié en
#               root (contexte de construire-image) : écriture, remontage en lecture-écriture, nouvelle écriture ; relu côté
#               PVC ; PVC et pods supprimés
#   porte       ConfigMap porte (porte.rego avec D6, liste revue de F3) ; image réelle jugée avant la nouvelle construction :
#               refusée (fermeture de l'hôte) ; témoin hors règle (builds/essai-webhook, pipeline d'essai) : verdict inchangé
#   construire  PipelineRun de la pipeline de F3 (gabarit en service, pipeline remplacée, Kata pour construire) : image comparée
#               à 3a7ca1b1, entrees en lecture seule dans le pod, Chains ; porte : image réelle admise
#   provenance  provenance du PipelineRun (clé de Chains ; autre clé refusée) : fermeture de la plateforme, tâches de F3,
#               sous-dossiers des workspaces dans le TaskRun signé
#   bascule     gabarit en service (politique/gabarit-sample-app.yaml) rendu avec la pipeline de F3 et appliqué
#
# Ordre : regle reel (hôte), puis taches temoins lecture_seule porte construire provenance bascule ; porte juste avant construire
# (fenêtre de refus de l'image réelle la plus courte). Retour arrière si construire échoue après porte : ConfigMap porte remise
# avec porte.rego et taches.yml du commit d7d05b4 (cm_porte depuis ces fichiers), au choix du propriétaire.
#
# Usage (racine du dépôt) : mise run fermetures:f3 -- <étape>…   (journal : resultats/f3-<étape>.log)
set -euo pipefail
export LC_ALL=C

h03=$(cd "$(dirname "$0")" && pwd)
. "$h03/../08-trust-plane/politique.sh"   # here (08), commun.sh, juger, cm_porte, passage, PORTE, CPOL_COMMIT ; étapes non lancées
for f in $(declare -F | awk '$3 ~ /^etape_/ {print $3}'); do unset -f "$f"; done   # seules les étapes de F3 sont appelables
R03=$h03/resultats                       # journaux de F3 ($R reste celui de la 08 : clé publique de Chains, lue par cm_porte)
T=$HOME/.cache/supply-chain-poc/03/f3
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets, même en cas d'échec

CPOL=$O/telechargements/conforma-policy   # dépôt nu de politique.sh porte (bibliothèque de l'image de la porte, CPOL_COMMIT)
FERMETURE=$REG/builds/fermetures/sample-app@sha256:74c265e703fb1ab823b64ac7d62c31c73b5e426895a15d54c57670bdfbffbcdd   # F2 : deux prefetch
WEB_DIST=$REG/entrees/sample-app/web-dist@sha256:47f72275aa786c3c2d4393d7601e118fb2b1a17d928dca477f6dac89eb852bcb   # construction.sh
BUILDKIT=$REG/amont/moby/buildkit@sha256:ace6811c21334fa502644b9711e0ea48e8539c5c2a843c2325dfb7b987ab260b            # construction.sh
BUILDER=$REG/plateforme/builder-go-voie-d@sha256:d50ae57551c381b591540643fdfee12dd251ae16675c3c69fde221f8e9c28b67    # construction.sh
DOCKERFILE=$repo/poc/bricks/04-hermetic-repro/Dockerfile
IMAGE=$REG/builds/sample-app
ESSAI=$REG/builds/essai-f3                 # images des témoins
ALTEREE=entrees/sample-app/fermeture-alteree
PREPARER_J7=sha256:2070d601ae3c8df5f96500a3b05b1bdd8fb4441134cca31d20982a3fa098ebe4    # inchangée en F3
CONSTRUIRE_J7=sha256:403ccbd82c534e5611a8fcabf01d4fcd93731e945d50345d94f1fe6d58392d63  # entrées inscriptibles (avant D5)
PUBLIER_J7=sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b     # inchangée en F3
TETE_J2=6391fd437f26696847041be3226bbbf633f55a2f   # construction.sh : commit de main
SRC=$(jq -nc --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" --arg r "$TETE_J2" '{git: {url: $u, revision: $r}}')

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }

etape_regle() {
  local b=$T/regle c r k
  c=$(git -C "$CPOL" rev-parse FETCH_HEAD)
  [ "$c" = "$CPOL_COMMIT" ] && echo "OK   bibliothèque conforma/policy : $c" || { echo "KO   bibliothèque : $c" >&2; exit 1; }
  rm -rf -- "${b:?}"; mkdir -p "$b"
  git -C "$CPOL" archive FETCH_HEAD policy/lib policy/release/lib | tar -xf - -C "$b"
  find "$b/policy" -name '*_test.rego' -delete
  cp "$here/politique/porte/porte.rego" "$here/politique/porte/porte_test.rego" "$here/politique/porte/taches.yml" "$b/"
  echo "ec $(ec version 2>/dev/null | awk '/^Version/ {print $2}') ; $(find "$b/policy" -name '*.rego' | wc -l) modules de la bibliothèque"
  echo "## ec opa check"
  (cd "$b" && ec opa check policy porte.rego porte_test.rego) && echo "OK   aucune erreur"
  echo "## ec opa test"
  (cd "$b" && ec opa test -v policy porte.rego porte_test.rego taches.yml) | grep -E '^data\.porte_test\.|^PASS:|^FAIL:|^-'
  echo "## mutations : chaque condition de la règle retirée tour à tour, au moins un test doit échouer (« survit » : condition"
  echo "## gardée explicitement mais impliquée par la bibliothèque, sa survie est attendue)"
  mkdir -p "$b/m"
  k=0
  while IFS='|' read -r a c; do
    grep -vF -- "$c" "$b/porte.rego" > "$b/m/porte.rego"
    [ "$(wc -l < "$b/m/porte.rego")" = $(($(wc -l < "$b/porte.rego") - 1)) ] || { echo "KO   condition absente ou ambiguë : $c" >&2; exit 1; }
    r=$(cd "$b" && ec opa test policy m/porte.rego porte_test.rego taches.yml 2>&1 | sed -n 's/^data\.porte_test\.\(test_[a-z_]*\): FAIL.*/\1/p' | paste -sd, -) || true
    if [ "$a" = survit ]; then
      [ -z "$r" ] && echo "OK   sans « $c » : aucun échec (attendu : tekton.tasks ne lit les tâches que d'une provenance v1)" || { echo "KO   sans « $c » : $r (survie attendue)"; k=$((k + 1)); }
    else
      [ -n "$r" ] && echo "OK   sans « $c » : $r" || { echo "KO   condition non couverte par les tests : $c"; k=$((k + 1)); }
    fi
  done <<'FIN'
echec|count(_fermetures) == 0
echec|regex.match(`^sha256:[0-9a-f]{64}$`, r.digest)
survit|st.predicateType == lib.slsa_provenance_predicate_type_v1
echec|st.predicate.buildDefinition.buildType == lib.tekton_slsav1_pipeline_run
echec|builder.id in rule_data.get("allowed_builder_ids")
echec|regex.match(`^[^/]+/builds/fermetures/`, f.depot)
echec|s.name == f.depot
echec|sprintf("sha256:%s", [s.digest.sha256]) == f.digest
echec|count(taches) == 2
echec|count(tekton.untrusted_task_refs(taches, {})) == 0
echec|tekton.task_result(p, "IMAGE_URL") == f.depot
echec|tekton.task_result(p, "IMAGE_DIGEST") == f.digest
echec|tekton.task_result(q, "CHAINS-GIT_URL") == f.git
FIN
  [ "$k" = 0 ] || { echo "KO   $k condition(s) non couverte(s)" >&2; exit 1; }
}

etape_reel() {
  local b=$T/reel d=${FERMETURE#*@} k q r
  rm -rf -- "${b:?}"; mkdir -p "$b"
  git -C "$CPOL" archive "$CPOL_COMMIT" policy/lib policy/release/lib | tar -xf - -C "$b"
  find "$b/policy" -name '*_test.rego' -delete
  cp "$here/politique/porte/porte.rego" "$here/politique/porte/taches.yml" "$b/"
  grep -q 'https://supply-chain.example/builders/tekton-chains@v1' "$here/politique/porte/policy.yaml" || { echo "KO   builder.id absent de policy.yaml" >&2; exit 1; }
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$b/autre.pub" 2> /dev/null
  cp "$R/chains-cle-publique.pem" "$b/chains.pub"
  # données comme ec les écrit (conftest_evaluator.go : config.default_sigstore_opts) et ruleData de policy.yaml
  for k in chains autre; do
    jq -n --rawfile p "$b/$k.pub" '{config: {default_sigstore_opts: {public_key: $p, ignore_rekor: true, certificate_identity: "",
      certificate_identity_regexp: "", certificate_oidc_issuer: "", certificate_oidc_issuer_regexp: "", rekor_url: ""}},
      rule_data__configuration__: {allowed_builder_ids: ["https://supply-chain.example/builders/tekton-chains@v1"]}}' > "$b/donnees-$k.json"
  done
  q='v := ec.sigstore.verify_attestation("'"$REG_HOTE/builds/fermetures/sample-app@$d"'", data.config.default_sigstore_opts)
    f := {"ref": "'"$FERMETURE"'", "depot": "'"${FERMETURE%@*}"'", "digest": "'"$d"'", "git": "https://sc-stockage.poc.test:3000/'"$SAMPLE_APP"'.git"}
    atts := object.get(v, "attestations", [])
    r := {"succes": v.success, "erreurs": object.get(v, "errors", []), "verifiees": count(atts),
      "conformes": count([a | some a in atts; data.porte._prefetch(a.statement, f)]),
      "detail": [sprintf("%s pipelineTask=%d conforme=%v", [a.statement.predicate.runDetails.metadata.invocationId,
        count([x | some x in a.statement.predicate.buildDefinition.resolvedDependencies; x.name == "pipelineTask"]),
        count([1 | data.porte._prefetch(a.statement, f)]) == 1]) | some a in atts]}'
  for k in chains autre; do
    echo "## clé $k : verify_attestation sur $REG_HOTE/builds/fermetures/sample-app@$d, puis _prefetch"
    (cd "$b" && SSL_CERT_FILE=$P/ca-poc.crt ec opa eval -f json -d policy -d porte.rego -d taches.yml -d "donnees-$k.json" "$q") \
      | jq -c '.result[0].bindings.r' > "$b/$k.json"
    jq -r '"succès \(.succes), vérifiées \(.verifiees), conformes \(.conformes)", (.detail[] | "  " + .), (.erreurs[] | "  erreur : " + (gsub("\n"; " ") | .[0:200]))' "$b/$k.json"
  done
  attendu "clé de Chains : provenances vérifiées / conformes à la règle" "$(jq -r '"\(.verifiees)/\(.conformes)"' "$b/chains.json")" 4/2
  attendu "autre clé : provenances vérifiées" "$(jq -r '.verifiees' "$b/autre.json")" 0
  echo "## fermeture de l'hôte ($REG_HOTE/entrees/sample-app/fermeture@0ab5a507…), clé de Chains"
  (cd "$b" && SSL_CERT_FILE=$P/ca-poc.crt ec opa eval -f json -d policy -d porte.rego -d taches.yml -d donnees-chains.json \
    'v := ec.sigstore.verify_attestation("'"$REG_HOTE"'/entrees/sample-app/fermeture@sha256:0ab5a50767bee2e430cdd2db6b4d61580629f89fd48fb352cd1a2a545ee56048", data.config.default_sigstore_opts)
     r := {"verifiees": count(object.get(v, "attestations", [])), "erreurs": object.get(v, "errors", [])}') | jq -c '.result[0].bindings.r' > "$b/hote.json"
  jq -r '"vérifiées \(.verifiees)", (.erreurs[] | "  erreur : " + (gsub("\n"; " ") | .[0:200]))' "$b/hote.json"
  attendu "fermeture de l'hôte : provenances vérifiées" "$(jq -r '.verifiees' "$b/hote.json")" 0
  echo "## fermeture lue par la règle dans la provenance archivée de J7 ($W/construction/prov.json)"
  jq -c '{attestations: [{statement: .}]}' "$W/construction/prov.json" > "$b/entree-j7.json"
  r=$(cd "$b" && ec opa eval -f json -d policy -d porte.rego -d taches.yml -d donnees-chains.json -i entree-j7.json 'data.porte._fermetures' \
    | jq -c '.result[0].expressions[0].value')
  echo "$r"
  attendu "fermetures de la provenance de J7" "$(jq -r 'map(.ref + " " + .git) | join(",")' <<< "$r")" \
    "$REG/entrees/sample-app/fermeture@sha256:0ab5a50767bee2e430cdd2db6b4d61580629f89fd48fb352cd1a2a545ee56048 https://sc-stockage.poc.test:3000/$SAMPLE_APP.git"
}

signer_tache() { # nom : comme construction.sh (signature versionnée dans la 08, bundle, liste revue) ; SIGNER=<nom> : seule
  # cette tâche est re-signée (une nouvelle signature change le bundle : les autres tâches doivent garder la leur)
  local n=$1 v=$here/politique/taches/$1.signee.yaml r
  tkn task sign "$T/$n.yaml" -K "$S/taches.key" -f "$T/$n-signee.yaml" > /dev/null
  if [ "${SIGNER:-}" = "$n" ]; then cp "$T/$n-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans politique/taches/$n.signee.yaml (liste revue à mettre à jour)"; fi
  [ -s "$v" ] || { echo "KO   signature versionnée absente" >&2; exit 1; }
  cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") \
    && echo "OK   $n : signature versionnée conforme au gabarit rendu, signature exceptée" \
    || { echo "KO   $n : gabarit modifié depuis la signature versionnée (SIGNER=$n, puis revue de la liste)" >&2; exit 1; }
  r=$REG/tekton/tasks/$n@$(bundle "$v" "tekton/tasks/$n" f3)
  echo "$r" > "$T/$n.ref"
  if listee "$r"; then echo "OK   $n dans la liste revue : $r"
  elif [ "${SIGNER:-}" = "$n" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml après revue, puis relancer sans SIGNER : $r"
  else echo "KO   $n absente de la liste revue politique/porte/taches.yml : $r" >&2; exit 1; fi
}

rendre_pipeline() { # fermeture image étiquette : pipeline sample-app rendue avec les tâches de $T/*.ref, signée, bundle ; référence
  sed -e "s#@PREPARER@#$(cat "$T/preparer-entrees.ref")#" -e "s#@CONSTRUIRE@#$(cat "$T/construire-image.ref")#" \
    -e "s#@PUBLIER@#$(cat "$T/publier-image.ref")#" -e "s#@FERMETURE@#$1#" -e "s#@WEB_DIST@#$WEB_DIST#" -e "s#@BUILDER@#$BUILDER#" \
    -e "s#@IMAGE@#$2#" "$here/politique/taches/sample-app.yaml" > "$T/sample-app-$3.yaml"
  ! grep -n '@[A-Z_]*@' "$T/sample-app-$3.yaml" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans la pipeline $3" >&2; exit 1; }
  tkn pipeline sign "$T/sample-app-$3.yaml" -K "$S/taches.key" -f "$T/sample-app-$3-signee.yaml" > /dev/null
  echo "$REG/tekton/pipelines/sample-app@$(bundle "$T/sample-app-$3-signee.yaml" tekton/pipelines/sample-app "$3")"
}

etape_taches() {
  local s p
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente (politique.sh taches)" >&2; exit 1; }
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh)
  s=$(sha256sum < "$DOCKERFILE" | cut -c1-64)
  echo "## tâches (tkn $(tkn version --component client)) ; Dockerfile de la brique 04 : $s"
  sed -e "s#@BUILDKIT@#$BUILDKIT#g" -e "s#@OUTILS@#$REG/$OUTILS@$OUTILS_DIGEST#g" "$here/politique/taches/preparer-entrees.yaml" > "$T/preparer-entrees.yaml"
  awk -v f="$DOCKERFILE" '$1 == "@DOCKERFILE@" && NF == 1 { match($0, /^ */); i = substr($0, 1, RLENGTH)
      while ((getline l < f) > 0) print (l == "" ? "" : i l); next } { print }' "$here/politique/taches/construire-image.yaml" \
    | sed -e "s#@BUILDKIT@#$BUILDKIT#g" -e "s#@BUILDER_DIGEST@#${BUILDER#*@}#g" -e "s#@DOCKERFILE_SHA@#$s#g" > "$T/construire-image.yaml"
  sed -e "s#@OUTILS@#$REG/$OUTILS@$OUTILS_DIGEST#g" "$here/politique/taches/publier-image.yaml" > "$T/publier-image.yaml"
  for p in preparer-entrees construire-image publier-image; do
    ! grep -n '@[A-Z_]*@' "$T/$p.yaml" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans $p" >&2; exit 1; }
    signer_tache "$p"
  done
  attendu "preparer-entrees inchangée depuis J7" "$(cut -d@ -f2 "$T/preparer-entrees.ref")" "$PREPARER_J7"
  attendu "publier-image inchangée depuis J7" "$(cut -d@ -f2 "$T/publier-image.ref")" "$PUBLIER_J7"
  [ "$(cut -d@ -f2 "$T/construire-image.ref")" != "$CONSTRUIRE_J7" ] && echo "OK   construire-image nouvelle (D5) : $(cut -d@ -f2 "$T/construire-image.ref")" \
    || { echo "KO   construire-image inchangée" >&2; exit 1; }
  listee "$REG/tekton/tasks/construire-image@$CONSTRUIRE_J7" && echo "CONSTAT construire-image de J7 ($CONSTRUIRE_J7, entrées inscriptibles) encore dans la liste revue" \
    || echo "OK   construire-image de J7 ($CONSTRUIRE_J7, entrées inscriptibles) retirée de la liste revue"
  grep -q 'readOnly: true' <(sed -n '/^  workspaces:/,/^  results:/p' "$T/construire-image.yaml") && echo "OK   construire-image : workspace entrees readOnly" \
    || { echo "KO   workspace entrees sans readOnly" >&2; exit 1; }
  echo "## pipeline sample-app (D5 : sous-dossiers du workspace ; fermeture de la plateforme)"
  rendre_pipeline "$FERMETURE" "$IMAGE" f3 | tee "$T/pipeline.ref"
  attendu "fermeture épinglée dans la pipeline" "$(sed -n '/name: fermeture/{n;s/^ *value: //p}' "$T/sample-app-f3.yaml")" "$FERMETURE"
}

etape_porte() {
  local r v=porte.fermeture_plateforme
  listee "$REG/tekton/tasks/construire-image@$CONSTRUIRE_J7" || v="$v,trusted_task.trusted"   # construire-image de J7 retirée de la liste
  echo "## ConfigMap porte : porte.rego (D6) et liste revue de F3"
  cm_porte
  for k in porte.rego taches.yml; do
    cmp -s <(kubectl get configmap -n porte porte -o json | jq -j --arg k "$k" '.data[$k]') "$here/politique/porte/$k" \
      && echo "OK   ConfigMap porte : $k identique au fichier versionné" || { echo "KO   ConfigMap porte : $k" >&2; exit 1; }
  done
  echo "## image réelle, avant la construction de F3 (provenance la plus récente : fermeture de l'hôte)"
  r=$(juger f3-avant "$IMAGE@$APP_DIGEST" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$r"
  jq -r '.components[].violations[]? | select(.metadata.code == "porte.fermeture_plateforme") | "  \(.msg)"' "$T/porte-f3-avant.json"
  attendu "ec (success, violations)" "$(cut -d'|' -f3-4 <<< "$r")" "false|$(trier "$v")"
  echo "## témoin hors règle : builds/essai-webhook@$APP_DIGEST (pipeline d'essai de J6, sans preparer-entrees)"
  r=$(juger f3-essai "$REG/builds/essai-webhook@$APP_DIGEST"); echo "$r"
  attendu "verdict inchangé (c6-sans-vsa, preuves-controle6.log)" "$(cut -d'|' -f3-5 <<< "$r")" \
    "false|slsa_source_correlated.attested_source_code_reference,slsa_source_correlated.source_code_reference_provided,slsa_source_version_controlled.materials_format_okay|trusted_task.tagged"
}

pr_f3() { # nom bundle : PipelineRun du gabarit en service (declencheurs), pipeline remplacée, commit de main, workspace en PVC,
  # Kata pour la seule tâche construire (comme construction.sh pr_j7) ; $T/pr-<nom>.json
  kubectl get triggertemplate -n declencheurs sample-app -o json | jq --arg n "$1" --arg b "$2" --arg c "$TETE_J2" \
    --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" '.spec.resourcetemplates[0] | .metadata.name = $n
      | .spec.pipelineRef.params |= map(if .name == "bundle" then .value = $b elif .name == "name" then .value = "sample-app" else . end)
      | .spec.params |= map(if .name == "commit" then .value = $c elif .name == "depot" then .value = $u else . end)
      | .spec.workspaces = [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "1Gi"}}}}}]
      | .spec.taskRunSpecs = [{pipelineTaskName: "construire", podTemplate: (.spec.taskRunTemplate.podTemplate + {runtimeClassName: "kata"})}]' > "$T/pr-$1.json"
}

fin_pr() { # nom [secondes] : attend la fin ; « statut|raison|message »
  local st=""
  for _ in $(seq "${2:-900}"); do
    st=$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}')
    [ -n "$st" ] && [ "$st" != Unknown ] && break; sleep 1
  done
  kubectl get pipelinerun -n builds "$1" -o json | jq -r '.status.conditions[] | select(.type == "Succeeded") | "\(.status)|\(.reason)|\(.message | gsub("\n"; " ") | .[0:300])"'
}

journaux() { # PipelineRun : état et dernières lignes de chaque TaskRun, journaux complets dans $T
  local t p
  for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$1" -o jsonpath='{.items[*].metadata.name}'); do
    p=$(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.podName}')
    kubectl logs -n builds "$p" --all-containers > "$T/$t.log" 2>&1 || true
    echo "### TaskRun $t ($(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.conditions[0].reason}')), pod $p, runtimeClassName $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.runtimeClassName}' 2>/dev/null)"
    grep -vE '^\s*$' "$T/$t.log" | tail -6 | sed 's/^/     /'
  done
}

ecritures() { # compte dépôt t0 : écritures de manifestes du compte dans le dépôt depuis t0 (audit de Zot)
  sur sc-stockage "sudo cat /var/log/zot/audit.log" | jq -c --arg c "$1" --arg d "/v2/$2/manifests/" --arg t "$3" \
    'select(.time[0:19] >= ($t[0:19]) and .subject == $c and (.object | startswith($d)) and .action != "GET" and .action != "HEAD")' | wc -l
}

etape_temoins() {
  local z d t0 r n
  [ -s "$T/pipeline.ref" ] || { echo "KO   pipeline de F3 absente (étape taches)" >&2; exit 1; }
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"
  echo "## fermeture altérée : copie de la fermeture de F2, un zip de module modifié (zip valide), poussée par poc-ecriture"
  rm -rf -- "${T:?}/f-alteree"; oras pull --no-tty --ca-file "$P/ca-poc.crt" -o "$T/f-alteree" "${FERMETURE/$REG/$REG_HOTE}" > /dev/null
  z=$T/f-alteree/deps/gomod/pkg/mod/cache/download/github.com/go-chi/chi/v5/@v/v5.2.3.zip   # seul module compilé de sample-app
  [ -s "$z" ] || { echo "KO   zip de chi absent de la fermeture" >&2; exit 1; }
  python3 -I - "$z" <<'PY'
import sys, zipfile, shutil
z = sys.argv[1]
with zipfile.ZipFile(z) as a, zipfile.ZipFile(z + '.n', 'w', zipfile.ZIP_DEFLATED) as b:
    m = [i for i in a.infolist() if i.filename.endswith('.go')][0]
    for i in a.infolist():
        d = a.read(i)
        b.writestr(i, d + b'\n// altere\n' if i is m else d)
    print('modifié :', m.filename)
shutil.move(z + '.n', z)
PY
  (cd "$T/f-alteree" && python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).testzip() is None or sys.exit(1)' "$z") && echo "zip valide : ${z#"$T/f-alteree/"}"
  ORAS_OPTS="--ca-file $P/ca-poc.crt --registry-config $T/auth/docker/config.json" "$h03/closure.sh" push "$T/f-alteree" "$REG_HOTE/$ALTEREE:f3" > "$T/alteree.ref"
  d=$(cut -d@ -f2 "$T/alteree.ref"); echo "fermeture altérée : $REG/$ALTEREE@$d"
  [ "$d" != "${FERMETURE#*@}" ] || { echo "KO   même digest que la fermeture de F2" >&2; exit 1; }
  echo "## pipelines des témoins (images dans builds/essai-f3)"
  rendre_pipeline "$REG/$ALTEREE@$d" "$ESSAI" f3-alteree > "$T/pipeline-alteree.ref"
  rendre_pipeline "${FERMETURE%@*}@sha256:$(printf absente | sha256sum | cut -c1-64)" "$ESSAI" f3-absente > "$T/pipeline-absente.ref"
  cat "$T/pipeline-alteree.ref" "$T/pipeline-absente.ref"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for n in alteree absente; do
    echo "## f3-$n"
    pr_f3 "f3-$n" "$(cat "$T/pipeline-$n.ref")"; purger_pr "f3-$n"
    kubectl create -f "$T/pr-f3-$n.json" > /dev/null
    r=$(fin_pr "f3-$n" 900); echo "PipelineRun f3-$n : $r"
    journaux "f3-$n"
    attendu "PipelineRun f3-$n" "${r%%|*}" False
    attendu "TaskRun publier de f3-$n" "$(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=f3-$n,tekton.dev/pipelineTask=publier" -o name | wc -l)" 0
  done
  grep -hE 'checksum mismatch|SECURITY ERROR' "$T"/f3-alteree-construire*.log | head -3 | sed 's/^/     /'
  grep -qE 'checksum mismatch' "$T"/f3-alteree-construire*.log && echo "OK   fermeture altérée : go build refuse le module (go.sum)" \
    || { echo "KO   fermeture altérée : refus de go.sum attendu" >&2; exit 1; }
  grep -hiE 'not found|manifest unknown' "$T"/f3-absente-preparer*.log | head -2 | sed 's/^/     /'
  grep -qiE 'not found|manifest unknown' "$T"/f3-absente-preparer*.log && echo "OK   fermeture absente : preparer échoue au tirage" \
    || { echo "KO   fermeture absente : échec de preparer attendu" >&2; exit 1; }
  attendu "écritures de poc-images dans builds/essai-f3 depuis $t0" "$(ecritures poc-images builds/essai-f3 "$t0")" 0
}

etape_lecture_seule() {
  local n
  echo "## PVC f3-lecture-seule (local-path) écrit par un pod runc restreint (uid 65532)"
  kubectl delete pod -n builds f3-ecrire f3-relire f3-kata --ignore-not-found --wait=true > /dev/null
  kubectl delete pvc -n builds f3-lecture-seule --ignore-not-found --wait=true > /dev/null
  jq -n '{apiVersion: "v1", kind: "PersistentVolumeClaim", metadata: {name: "f3-lecture-seule", namespace: "builds"},
    spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "16Mi"}}}}' | kubectl create -f - > /dev/null
  pod_essai() { # nom image kata|runc script [readOnly] : pod de builds sur sc-build, PVC monté entier (runc) ou en sous-dossier (kata)
    jq -n --arg n "$1" --arg i "$2" --arg m "$3" --arg c "$4" '{apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds"},
      spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
        tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
        volumes: [{name: "v", persistentVolumeClaim: {claimName: "f3-lecture-seule"}}]}
        + if $m == "kata" then {runtimeClassName: "kata", containers: [{name: "essai", image: $i, command: ["/bin/sh", "-c", $c],
            securityContext: {privileged: true, allowPrivilegeEscalation: true, runAsUser: 0, runAsNonRoot: false},
            volumeMounts: [{name: "v", mountPath: "/e", subPath: "entrees", readOnly: true}]}]}
          else {securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: "RuntimeDefault"}},
            containers: [{name: "essai", image: $i, command: ["/busybox/sh", "-c", $c],
            securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
            volumeMounts: [{name: "v", mountPath: "/v"}]}]} end)}' | kubectl create -f - > /dev/null
    kubectl wait -n builds "pod/$1" --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s > /dev/null \
      || { kubectl describe pod -n builds "$1" >&2; echo "KO   pod $1 non terminé" >&2; exit 1; }
    kubectl logs -n builds "$1" | sed "s/^/     $1 : /"
  }
  pod_essai f3-ecrire "$REG/$OUTILS@$OUTILS_DIGEST" runc 'mkdir -p /v/entrees && echo témoin > /v/entrees/temoin && ls -ln /v /v/entrees'
  echo "## pod Kata privilégié en root, sous-dossier entrees en readOnly (comme construire-image)"
  pod_essai f3-kata "$BUILDKIT" kata 'grep " /e " /proc/mounts; echo "lecture : $(cat /e/temoin)";
    touch /e/ecrit-avant 2>&1 && echo "écriture avant remontage : acceptée" || echo "écriture avant remontage : refusée";
    mount -o remount,rw /e 2>&1 && echo "remontage rw : accepté" || echo "remontage rw : refusé";
    grep " /e " /proc/mounts;
    touch /e/ecrit-apres 2>&1 && echo "écriture après remontage : acceptée" || echo "écriture après remontage : refusée"'
  echo "## relu côté PVC (pod runc)"
  pod_essai f3-relire "$REG/$OUTILS@$OUTILS_DIGEST" runc 'ls -ln /v/entrees'
  n=$(kubectl logs -n builds f3-relire | grep -c 'ecrit-' || true)
  echo "fichiers écrits par le pod Kata, vus du PVC : $n"
  kubectl logs -n builds f3-kata > "$T/lecture-seule-kata.log"
  attendu "écriture avant remontage" "$(sed -n 's/^écriture avant remontage : //p' "$T/lecture-seule-kata.log")" refusée
  echo "CONSTAT remontage rw : $(sed -n 's/^remontage rw : //p' "$T/lecture-seule-kata.log") ; écriture après remontage : $(sed -n 's/^écriture après remontage : //p' "$T/lecture-seule-kata.log") ; fichiers vus du PVC : $n"
  kubectl delete pod -n builds f3-ecrire f3-relire f3-kata --wait=false > /dev/null
  kubectl delete pvc -n builds f3-lecture-seule --wait=false > /dev/null
}

etape_construire() {
  local pr=f3-construire r c d t0
  [ -s "$T/pipeline.ref" ] || { echo "KO   pipeline de F3 absente (étape taches)" >&2; exit 1; }
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  pr_f3 "$pr" "$(cat "$T/pipeline.ref")"; purger_pr "$pr"
  kubectl create -f "$T/pr-$pr.json" > /dev/null
  echo "## $pr créé (pipeline $(cat "$T/pipeline.ref" | cut -d@ -f2 | cut -c1-19)…, $(jq -c '.spec.taskRunSpecs' "$T/pr-$pr.json"))"
  r=$(fin_pr "$pr" 900); journaux "$pr"
  attendu "PipelineRun $pr" "$(cut -d'|' -f1,2 <<< "$r")" "True|Succeeded"
  c=$(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr,tekton.dev/pipelineTask=construire" -o jsonpath='{.items[0].status.podName}')
  kubectl get pod -n builds "$c" -o json | jq -r '.spec.containers[] | select(.name == "step-construire") | .volumeMounts[]
    | select(.mountPath | startswith("/workspace")) | "montage \(.mountPath) : subPath \(.subPath // "-"), readOnly \(.readOnly // false)"'
  grep -h '^entrees : ' "$T/$pr-construire.log" || true
  grep -q 'écriture refusée' "$T/$pr-construire.log" && echo "OK   construire : écriture dans entrees refusée" || { echo "KO   écriture dans entrees non refusée" >&2; exit 1; }
  d=$(kubectl get pipelinerun -n builds "$pr" -o json | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
  attendu "image de sample-app construite sur la fermeture de la plateforme" "$d" "$APP_DIGEST"
  attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
  echo "écritures de manifestes de poc-images dans builds/sample-app depuis $t0 : $(ecritures poc-images builds/sample-app "$t0") (non jugées : le manifeste existe déjà)"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "passage d'horodatage (enveloppes de $pr) : $(passage "$t0")"
  echo "## porte : image réelle, provenance la plus récente = $pr"
  r=$(juger f3-apres "$IMAGE@$APP_DIGEST" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$r"
  attendu "ec (success, violations, avertissements)" "$(cut -d'|' -f3-5 <<< "$r")" "true||trusted_task.tagged"
  attendu "contrôle 9 (horodatage)" "$(cut -d'|' -f7 <<< "$r")" ok
  attendu "contrôle 6 (VSA)" "$(cut -d'|' -f9 <<< "$r")" ok
  echo "CONSTAT la VSA retenue atteste le rejeu de la provenance de J7 (fermeture de l'hôte) : vsa.sh la lie au digest, pas à la provenance jugée"
}

etape_provenance() {
  local uid
  uid=$(kubectl get pipelinerun -n builds f3-construire -o jsonpath='{.metadata.uid}')
  cosign verify-attestation --key "$R/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" \
    "$REG_HOTE/builds/sample-app@$APP_DIGEST" > "$T/att.json" 2> "$T/cosign.err" || { cat "$T/cosign.err" >&2; exit 1; }
  echo "OK   cosign verify-attestation : $(wc -l < "$T/att.json") enveloppe(s) valide(s) sur builds/sample-app@$APP_DIGEST"
  jq -c --arg u "$uid" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$T/att.json" > "$T/prov.json"
  attendu "enveloppes du PipelineRun f3-construire" "$(wc -l < "$T/prov.json")" 1
  jq -r '"sujet : \(.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(", "))", "resolvedDependencies :",
    (.predicate.buildDefinition.resolvedDependencies[] | "  \(.name // "-") \(.uri // "-") \(.digest // {} | to_entries | map(.key + ":" + .value) | join(","))\(if .content then " (contenu)" else "" end)")' "$T/prov.json"
  attendu "fermeture" "$(jq -r --arg u "oci://${FERMETURE%@*}" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json")" "${FERMETURE#*@}"
  attendu "tâche construire-image (bundle)" "$(jq -r --arg u "$REG/tekton/tasks/construire-image" '.predicate.buildDefinition.resolvedDependencies[]
    | select(.name == "pipelineTask" and .uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json")" "$(cut -d@ -f2 "$T/construire-image.ref")"
  attendu "workspaces du TaskRun construire (contenu signé)" "$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask" and .content)
    | .content | @base64d | fromjson | select(.metadata.labels["tekton.dev/pipelineTask"] == "construire") | .spec.workspaces | map("\(.name):\(.subPath // "-")") | join(",")' "$T/prov.json")" \
    "entrees:entrees,sortie:image"
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$T/autre.pub" 2> /dev/null
  refus "provenance vérifiée avec une autre clé" "no matching attestations|invalid signature|signature" \
    cosign verify-attestation --key "$T/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/sample-app@$APP_DIGEST"
}

etape_bascule() {
  local p
  [ -s "$T/pipeline.ref" ] || { echo "KO   pipeline de F3 absente (étape taches)" >&2; exit 1; }
  echo "gabarit en service avant : $(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value')"
  sed "s#@PIPELINE@#$(cat "$T/pipeline.ref")#" "$here/politique/gabarit-sample-app.yaml" | kubectl apply -f - > /dev/null
  p=$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value')
  attendu "gabarit en service : pipeline de F3" "$p" "$(cat "$T/pipeline.ref")"
}

lancer() {
  [ $# -gt 0 ] || { echo "usage : $0 $(declare -F | awk '$3 ~ /^etape_/ {sub("etape_", "", $3); printf "%s|", $3}' | sed 's/|$//')…" >&2; exit 2; }
  for e in "$@"; do declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }; done
  for e in "$@"; do
    { echo "# ${0##*/} $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R03/f3-$e.log"
  done
}
lancer "$@"
