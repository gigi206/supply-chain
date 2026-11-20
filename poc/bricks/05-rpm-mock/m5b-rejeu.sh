#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, M5b sous l'option C : chemin du rejeu de zéro, préparé à sec le 20/11/2026 (carte resultats/m5b-carte.md). Script
# frère : les scripts de mesure (m1b-signature.sh, m1b-pipeline.sh, m1b-artefact.sh, m1b-fermeture.sh, m1b-construction.sh) ne
# sont pas touchés. Chaque étape source l'un d'eux dans un sous-shell, sous PREFIXE=$TAG, et réutilise ses fonctions et ses
# références épinglées. Les gardes qui renvoient à M4a, M4b, M4c ou aux images d'essai (tags m4a, m4b, m4c ; fermeture
# 2a9e2ea7 ; artefact de M4c présent avant ; arbre de l'essai, pipeline.ref et digest-local sous le préfixe) ne sont pas
# rejouées : un Zot neuf ne les a pas. Les gardes de sûreté le sont : liste revue, politiques, place libre, PipelineRun absent,
# dry-run d'admission, signature de Chains. Les entrées sont des fichiers du dépôt épinglés par sha256 et des objets de Zot lus
# par digest.
#   entree        avant le démontage, sans cluster ni Zot : TAG, journaux et dossiers de ce TAG absents, entrées de l'hôte
#                 (rendu de prealables, mesure d'un autre jour, layout de M4a, arbre de l'essai et verrou de la cascade),
#                 fichiers signés, clé des tâches présente (test -s), fuseau, SOURCE_DATE_EPOCH, tkn.
#   signature     etape_taches de m1b-signature.sh, sans SIGNER : les deux tâches des builders republiées depuis builders/
#                 (tag m1b), les deux pipelines des builders SIGNÉES À NOUVEAU par tkn avec la clé des tâches (lue par tkn
#                 seulement, jamais ici) et poussées au tag m1b. Leurs digests changent (ECDSA). Sorties sous
#                 $W/m5b-rejeu-$TAG-signature-05, pas sous $W/m1b-signature-05.
#   images        etape_pipeline de m1b-pipeline.sh, sous PREFIXE=$TAG et SIG=les sorties de signature : quatre PipelineRuns,
#                 images 70f8c412 et 6de899ac.
#   artefact      etape_local de m1b-artefact.sh (hôte seul), puis la publication de son etape_publier sans la garde du tag m4a
#                 (G2, P3) : digest local égal à 333b7322 (cité par la pipeline signée sample-app-rpm), sinon arrêt avant
#                 toute poussée ; déjà présent : rien n'est poussé (reprise).
#   fermeture     un PipelineRun de prefetch-rpm-sample-app (pipeline par digest, PIPELINE_REF de m1b-fermeture.sh) ;
#                 fermeture 09838980 (citée par la pipeline signée sample-app-rpm) exigée ; déjà présente : aucun PipelineRun.
#   construction_rpm  un PipelineRun de sample-app-rpm (PIPELINE_REF de m1b-construction.sh) ; artefact rpm relevé, comparé à
#                 07b7bd6f sans l'exiger (confiance moyenne ; rien ne l'épingle en aval).
# Ordre dans le rejeu (bloc 05 de rejeu.sh) : s1.sh amorce m3_reseau (PREFIXE=$TAG), signature, images,
# m5b-republier.sh taches, artefact, m5b-republier.sh pipeline_fermeture, fermeture, m5b-republier.sh pipeline_construction,
# construction_rpm. Les pipelines rpm sont relues par digest : le TAG de m5b-republier.sh peut être celui-ci ou un autre.
# Un digest différent de 333b7322 ou de 09838980 arrête l'étape : il demande une nouvelle signature et une revue de la liste,
# décision du propriétaire, jamais prise ici.
# TAG obligatoire, sans défaut : un TAG par tentative, car un journal existant n'est jamais réécrit.
# Aucun secret en argument ; l'authentification de Zot est écrite sous un dossier auth (0700) retiré à la sortie, même en échec.
# Usage (racine du dépôt) : TAG=<tag> DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m5b-rejeu.sh <étape>…
#         (journaux : resultats/m5b-rejeu-<tag>-<étape>.log)
# shellcheck disable=SC2030,SC2031,SC2153  # variables des scripts sourcés, chaque étape dans son sous-shell
set -euo pipefail
export LC_ALL=C
export TZ=Europe/Paris   # bundle (tâches des builders) : digest dépendant du fuseau (RE5 à RE7, 20/11/2026)
unset SOURCE_DATE_EPOCH  # lue par tkn bundle push

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
# shellcheck disable=SC1091  # chemin calculé
. "$here/commun.sh"   # S, P, W, REG, REG_HOTE, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
TAG=${TAG:-}
case $TAG in
  m1b|m4a|m4b|m4c|essai|s1) echo "tag refusé : $TAG appartient à la cascade de M1b, à M4a, M4b, M4c, aux essais ou à S1" >&2; exit 2 ;;
  ''|*[!a-z0-9-]*) echo "TAG absent ou invalide : « $TAG » (un TAG neuf par tentative)" >&2; exit 2 ;;
esac
TS=$W/m5b-rejeu-$TAG-signature-05   # sorties de l'étape signature (références, pipelines signées), lues par images (SIG)
TKN_VERSION=0.46.2                   # m5b-republier.sh
DECALAGE=+01:00                      # m5b-republier.sh
MASQUE05='/jeton\|token/I c\[ligne masquée : motif jeton|token]'   # BRE : jamais sous sed -E
# Valeurs attendues, recoupées avec les scripts de mesure sourcés
PIPE_FERMETURE=tekton/pipelines/prefetch-rpm-sample-app@sha256:61814acd6f15f0fde07f9f701f2e8cfd4324218caf2df9e1befcf182495ca60c   # m1b-fermeture.sh
PIPE_CONSTRUCTION=tekton/pipelines/sample-app-rpm@sha256:7d361cb1d5ea9b7994727f839bc4365a29e4ebdc7948fceff4176b4a371abd6a        # m1b-construction.sh
FERMETURE_ATTENDUE=sha256:0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f   # citée par sample-app-rpm signée
ARTEFACT_ATTENDU=sha256:333b7322290ab5edd85989908fa2e181a48a72facfd4043e181a2962d2bcfe48     # citée par sample-app-rpm signée
ARBRE_CASCADE=$R/m1b-fermeture-essai-arbre.txt   # arbre de l'essai de la cascade (a731fbce), 230 fichiers = couches attendues
VERROU_CASCADE=$R/m1b-verrou.json
VERROU_CASCADE_SHA=c544599aba4b7460f7496066e7c0361c80a59b8e345655553509024a254a6c83   # m1b-verrou.sh verrou (6da4e4a1)

echec() { echo "KO   $*" >&2; exit 1; }
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echec "$1 : $2 (attendu : $3)"; fi; }

# --- chargements : chacun dans le sous-shell de son étape ---
charger_signature() { # m1b-signature.sh ; ses sorties sous $TS, pas sous $W/m1b-signature-05
  unset SIGNER
  # shellcheck disable=SC1091
  . "$h05/m1b-signature.sh"   # T=$W/m1b-signature-05 : crée $T/auth et pose son trap
  T0=$T; T=$TS
  [ ! -e "$T" ] || echec "déjà présent, jamais réécrit : ${T#"$W"/}"
  (umask 077 && mkdir -p "$T/auth")
  trap 'find "$T/auth" "$T0/auth" -depth -delete 2> /dev/null || true' EXIT   # copies de secrets ; sans rm
}
charger_images() { # m1b-pipeline.sh sous PREFIXE=$TAG, références des pipelines lues sous $TS ; globales (SIG=${SIG:-…} au
  # shellcheck disable=SC2034  # lue par le script sourcé
  PREFIXE=$TAG   # chargement : une locale serait perdue au retour), dans le sous-shell de l'étape
  # shellcheck disable=SC2034  # lue par le script sourcé
  SIG=$TS
  # shellcheck disable=SC1091
  . "$h05/m1b-pipeline.sh"
}
charger_mesure() { # script : m1b-artefact.sh, m1b-fermeture.sh ou m1b-construction.sh, sous PREFIXE=$TAG et TAG=$TAG
  # shellcheck disable=SC2034  # lue par le script sourcé
  local PREFIXE=$TAG
  # shellcheck disable=SC1090
  . "$h05/$1"
}

# --- étapes : le corps, une fois le script de mesure chargé ---
rejeu_entree() {
  local e f j d n
  echo "## TAG $TAG : journaux et dossiers absents"
  n=0
  for j in "$R/m5b-rejeu-$TAG-"*.log "$R/m5b-republier-$TAG-"*.log "$R/$TAG-amorce.log" "$R/$TAG-m3_reseau.log" \
           "$R/m1b-pipeline-$TAG-"*.log "$R/$TAG-"*.log; do
    [ "$j" != "$R/m5b-rejeu-$TAG-entree.log" ] || continue   # celui de cette étape, ouvert par lancer
    [ ! -e "$j" ] || { echo "     présent : resultats/${j##*/}"; n=$((n + 1)); }
  done
  attendu "journaux de ce TAG présents (un journal n'est jamais réécrit)" "$n" 0
  n=0
  for d in "$W/m5b-rejeu-$TAG-"* "$W/m5b-republier-$TAG-05" "$W/$TAG-pipeline-05" "$W/$TAG-artefact-05" \
           "$W/$TAG-fermeture-05" "$W/$TAG-construction-05"; do
    [ ! -e "$d" ] || { echo "     présent : ${d#"$W"/}"; n=$((n + 1)); }
  done
  attendu "dossiers de ce TAG présents sous \$W" "$n" 0
  echo "## outils et environnement"
  attendu "fuseau : décalage de l'époque 0 (TZ=$TZ)" "$(date -d @0 +%:z)" "$DECALAGE"
  attendu "SOURCE_DATE_EPOCH" "${SOURCE_DATE_EPOCH-absente}" absente
  attendu "tkn (client)" "$(tkn version --component client)" "$TKN_VERSION"
  attendu "clé des tâches présente (test -s, jamais lue ici)" "$([ -s "$S/taches.key" ] && echo présente || echo absente)" présente
  echo "## entrées de l'hôte (hors du dépôt)"
  n=0
  while IFS=: read -r f e; do
    [ -n "$f" ] || continue
    attendu "rendu de prealables : $f (sha256, RENDUS_SHA de m1b-signature.sh)" "$(sha256sum < "$W/m1bt-20-05/$f" 2> /dev/null | cut -c1-64)" "$e"
    n=$((n + 1))
  done < <(sed -n '/^RENDUS_SHA="/,/"/{s/^RENDUS_SHA="//;s/".*$//;p}' "$h05/m1b-signature.sh")
  attendu "rendus contrôlés" "$n" 4
  (charger_images > /dev/null; gardes_mesure)
  attendu "layout de M4a (étape local de m1b-artefact.sh)" "$([ -s "$W/m4a-05/layout-1/index.json" ] && echo présent || echo absent)" présent
  echo "## fichiers du dépôt"
  attendu "arbre de l'essai de la cascade (sha256)" "$(sha256sum < "$ARBRE_CASCADE" | cut -c1-64)" a731fbce8ba11021508ff700e2ba6f72d976a92c5c835ba8e419b4ff88db014a
  attendu "arbre de l'essai de la cascade : fichiers" "$(wc -l < "$ARBRE_CASCADE")" 230
  attendu "verrou de la cascade (sha256)" "$(sha256sum < "$VERROU_CASCADE" | cut -c1-64)" "$VERROU_CASCADE_SHA"
  (
    # shellcheck disable=SC1091
    . "$h05/m5b-republier.sh"   # crée $T/auth, vide ; retiré ici
    trap 'find "$T/auth" -depth -delete 2> /dev/null || true' EXIT
    n=0
    while read -r f d e _; do
      attendu "$f (sha256, m5b-republier.sh)" "$(sha256sum < "$h05/$f" | cut -c1-64)" "$e"; n=$((n + 1))
    done <<< "$TACHES_M1B
$PIPE_FERMETURE
$PIPE_CONSTRUCTION"
    attendu "fichiers signés contrôlés" "$n" 5
  )
  echo "entrée : rien n'a été écrit dans Zot ni dans le cluster"
}

rejeu_artefact() { # après charger_mesure m1b-artefact.sh
  local d d1 d2 libre
  etape_local
  echo "## publication (etape_publier de m1b-artefact.sh, sans le tag m4a)"
  d=$(cat "$T/digest-local")
  [ "$d" = "$ARTEFACT_ATTENDU" ] || echec "digest local $d, attendu $ARTEFACT_ATTENDU (cité par la pipeline signée sample-app-rpm) : nouvelle signature et revue de la liste, décision du propriétaire ; rien n'est poussé"
  echo "OK   digest local égal à l'artefact cité par la pipeline signée : $d"
  attendu "P0 sources inchangées depuis local" "$(sha "$SPEC") $(sha "$VERROU_NEUF")" "$SPEC_SHA $VERROU_NEUF_SHA"
  attendu "P0 zone de préparation inchangée" "$(sha "$T/paquet/sample-app.spec") $(sha "$T/paquet/verrou-rpm.json")" "$SPEC_SHA $VERROU_NEUF_SHA"
  echo '{}' > "$T/vide.json"
  d1=$(zot_lire "artefact attendu" "$DEPOT@$d")
  if [ "$d1" = "$d" ]; then echo "OK   artefact déjà présent dans Zot : $DEPOT@$d1 ; rien n'est poussé (reprise)"; return 0; fi
  attendu "artefact attendu, avant la poussée" "$d1" absent
  attendu "G1 $DEPOT:$TAG, lecture anonyme" "$(zot_lire "tag $TAG" "$DEPOT:$TAG")" absent
  libre=$(libre_zot)
  case $libre in ''|*[!0-9]*) echec "G3 place libre illisible : $libre" ;; esac
  [ "$libre" -ge "$LIBRE_MIN" ] || echec "G3 place libre sur / de sc-stockage : $libre octets, sous $LIBRE_MIN"
  echo "OK   G3 octets libres sur / de sc-stockage (porte /var/lib/zot) : $libre (seuil $LIBRE_MIN)"
  neuf "$T/tire"
  (umask 077 && mkdir -p "$T/auth/docker")
  trap 'find "$T/auth" -depth -delete 2> /dev/null || true' EXIT   # copies de secrets ; sans rm
  auth_zot "$T/auth/docker/config.json"   # compte poc-ecriture, comme m4a.sh
  d1=$(pousser "$T/paquet" "$REG_HOTE/$DEPOT:$TAG" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json")
  d2=$(pousser "$T/paquet" "$REG_HOTE/$DEPOT:$TAG" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json")
  attendu "P1 deux poussées dans Zot, même digest" "$d1" "$d2"
  attendu "P1 digest Zot égal au digest local" "$d1" "$d"
  mkdir "$T/tire"
  (cd "$T/tire" && oras pull --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json" --no-tty "$REG_HOTE/$DEPOT@$d1" > /dev/null)
  attendu "P2 fichiers tirés par digest égaux à la zone de préparation" \
    "$(cd "$T/tire" && find . -type f -printf '%P\n' | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)" \
    "$(fichiers | sort | (cd "$T/paquet" && xargs sha256sum) | sha256sum | cut -d' ' -f1)"
  attendu "P3 $DEPOT:$TAG, lecture anonyme après" "$(zot_lire "tag $TAG" "$DEPOT:$TAG")" "$d1"
  echo "octets libres sur / de sc-stockage après : $(libre_zot)"
}

rejeu_fermeture() { # après charger_mesure m1b-fermeture.sh
  local pr=$N-rpm-1 r d u t p c n l
  echo '{}' > "$T/vide.json"
  echo "## gardes, avant toute création"
  attendu "PIPELINE_REF de m1b-fermeture.sh" "$PIPELINE_REF" "$REG/$PIPE_FERMETURE"
  attendu "fermeture attendue, FERMETURE_NEUVE de m1b-fermeture.sh" "$FERMETURE_NEUVE" "$FERMETURE_ATTENDUE"
  attendu "pipeline présente dans Zot par digest (lecture anonyme)" "$(zot_lire pipeline "$PIPE_FERMETURE")" "${PIPE_FERMETURE##*@}"
  for r in "$PREFETCH_REF" "$PUBLIER_REF"; do
    if listee "$r"; then echo "OK   dans la liste revue : $r"; else echec "absente de la liste revue : $r"; fi
  done
  attendu "arbre de l'essai de la cascade (sha256), égal à l'arbre prédit" "$(sha "$ARBRE_CASCADE")" "$ARBRE_PREDIT_SHA"
  n=$(wc -l < "$ARBRE_CASCADE")
  d=$(zot_lire "fermeture attendue" "${DEPOT_FERMETURE#"$REG"/}@$FERMETURE_NEUVE")
  if [ "$d" = "$FERMETURE_NEUVE" ]; then echo "OK   fermeture attendue déjà présente : $DEPOT_FERMETURE@$d ; aucun PipelineRun (reprise)"; return 0; fi
  attendu "fermeture attendue, avant le PipelineRun" "$d" absent
  r=0; kubectl get pipelinerun -n builds "$pr" -o name < /dev/null > /dev/null 2>&1 || r=$?
  [ "$r" != 0 ] || echec "$pr existe déjà : rien n'est purgé, décision avant toute relance"
  l=$(libre_zot)
  echo "/ de sc-stockage : $l octets libres à $(date -u +%H:%M:%S) (garde : $LIBRE_MIN)"
  if ! [[ $l =~ ^[0-9]+$ ]] || [ "$l" -lt "$LIBRE_MIN" ]; then echec "espace libre illisible ou sous la garde sur sc-stockage"; fi
  pr_rpm "$pr"
  attendu "$pr : pipeline par digest" "$(jq -r '.spec.pipelineRef.params[] | select(.name == "bundle") | .value' "$T/pr-$pr.json")" "$REG/$PIPE_FERMETURE"
  attendu "$pr admis en dry-run serveur (ni résolveur, ni signatures, ni pods) : code de kubectl" "$(admission "$T/pr-$pr.json")" 0
  echo "## $pr"
  kubectl create -f "$T/pr-$pr.json" < /dev/null > /dev/null
  echo "$pr créé à $(date -u +%H:%M:%S) ($PIPELINE_REF)"
  r=$(attendre_pr "$pr")
  echo "$pr : condition Succeeded « $r », relevée à $(date -u +%H:%M:%S)"
  kubectl get pipelinerun -n builds "$pr" -o json < /dev/null > "$T/pr-$pr-etat.json"
  jq -r '"     début \(.status.startTime // "-") ; fin \(.status.completionTime // "-")"' "$T/pr-$pr-etat.json"
  for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
    kubectl get taskrun -n builds "$t" -o json < /dev/null > "$T/tr-$t.json"
    p=$(jq -r '.status.podName // ""' "$T/tr-$t.json")
    echo "### TaskRun $t : $(jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "-")|\(.reason // "-")"' "$T/tr-$t.json")"
    jq -r '.status.results[]? | "     résultat \(.name) : \(.value | if type == "string" then . else tojson end)"' "$T/tr-$t.json"
    [ -n "$p" ] || { echo "     aucun pod"; continue; }
    releve_pod "$p"
    for c in $(jq -r '.spec.containers[].name' "$T/pod-$p.json"); do
      kubectl logs -n builds "$p" -c "$c" < /dev/null 2>&1 | sed "$MASQUE05" > "$T/$t-$c.log" || true
      echo "     journal de $c : $(wc -l < "$T/$t-$c.log") lignes, dont $(grep -c '^repomd.xml V2 : ' "$T/$t-$c.log" || true) de repomd.xml imprimé (non répétées)"
      grep -v '^repomd.xml V2 : \|^\s*$' "$T/$t-$c.log" | cut -c1-240 | sed 's/^/       /'
    done
  done
  jq -r '.status.results[]? | "résultat de \(.name) : \(.value)"' "$T/pr-$pr-etat.json"
  attendu "PipelineRun $pr" "$r" "True|Succeeded"
  u=$(jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value' "$T/pr-$pr-etat.json")
  d=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$T/pr-$pr-etat.json")
  attendu "dépôt publié" "$u" "$DEPOT_FERMETURE"
  [ "$d" = "$FERMETURE_NEUVE" ] || echec "fermeture publiée $d, attendue $FERMETURE_NEUVE (citée par la pipeline signée sample-app-rpm) : nouvelle signature et revue de la liste, décision du propriétaire"
  echo "OK   fermeture publiée, égale à l'attendue : $d"
  attendu "manifeste relu dans Zot (lecture anonyme) : couches" \
    "$(oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$d" < /dev/null | jq '.layers | length')" "$n"
  attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
  echo "/ de sc-stockage : $(libre_zot) octets libres à $(date -u +%H:%M:%S)"
}

rejeu_construction() { # après charger_mesure m1b-construction.sh
  local pr=$N-construction-1 r d u t p k c l
  echo '{}' > "$T/vide.json"
  echo "## gardes, avant toute création"
  attendu "PIPELINE_REF de m1b-construction.sh" "$PIPELINE_REF" "$REG/$PIPE_CONSTRUCTION"
  attendu "FERMETURE_RPM et PACKAGING de m1b-construction.sh" "${FERMETURE_RPM##*@} ${PACKAGING##*@}" "$FERMETURE_ATTENDUE $ARTEFACT_ATTENDU"
  attendu "pipeline présente dans Zot par digest (lecture anonyme)" "$(zot_lire pipeline "$PIPE_CONSTRUCTION")" "${PIPE_CONSTRUCTION##*@}"
  for r in "$FERMETURE_RPM" "$FERMETURE_SOURCES" "$PACKAGING"; do
    attendu "entrée présente dans Zot par digest : ${r#"$REG"/}" "$(zot_lire entrée "${r#"$REG"/}")" "${r##*@}"
  done
  for r in "$PREPARER_REF" "$CONSTRUIRE_REF" "$PUBLIER_REF"; do
    if listee "$r"; then echo "OK   dans la liste revue : $r"; else echec "absente de la liste revue : $r"; fi
  done
  politique_relue
  r=0; kubectl get pipelinerun -n builds "$pr" -o name < /dev/null > /dev/null 2>&1 || r=$?
  [ "$r" != 0 ] || echec "$pr existe déjà : rien n'est purgé, décision avant toute relance"
  l=$(libre_zot)
  echo "/ de sc-stockage : $l octets libres à $(date -u +%H:%M:%S) (garde : $LIBRE_MIN)"
  if ! [[ $l =~ ^[0-9]+$ ]] || [ "$l" -lt "$LIBRE_MIN" ]; then echec "espace libre illisible ou sous la garde sur sc-stockage"; fi
  pr_m4c "$pr"
  attendu "$pr : pipeline par digest" "$(jq -r '.spec.pipelineRef.params[] | select(.name == "bundle") | .value' "$T/pr-$pr.json")" "$REG/$PIPE_CONSTRUCTION"
  attendu "$pr : podTemplate commun sans env ; Kata pour construire seule" \
    "$(jq -c '[(.spec.taskRunTemplate.podTemplate | has("env")), [.spec.taskRunSpecs[] | .pipelineTaskName + ":" + (.podTemplate.runtimeClassName // "")]]' "$T/pr-$pr.json")" \
    '[false,["construire:kata"]]'
  attendu "$pr admis en dry-run serveur (ni résolveur, ni signatures, ni pods) : code de kubectl" "$(admission "$T/pr-$pr.json")" 0
  echo "## $pr"
  kubectl create -f "$T/pr-$pr.json" < /dev/null > /dev/null
  echo "$pr créé à $(date -u +%H:%M:%S) ($PIPELINE_REF)"
  r=$(attendre_pr "$pr")
  echo "$pr : condition Succeeded « $r », relevée à $(date -u +%H:%M:%S)"
  kubectl get pipelinerun -n builds "$pr" -o json < /dev/null > "$T/pr-$pr-etat.json"
  jq -r '"     début \(.status.startTime // "-") ; fin \(.status.completionTime // "-")"' "$T/pr-$pr-etat.json"
  for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
    kubectl get taskrun -n builds "$t" -o json < /dev/null > "$T/tr-$t.json"
    k=$(jq -r '.metadata.labels["tekton.dev/pipelineTask"] // "-"' "$T/tr-$t.json")
    p=$(jq -r '.status.podName // ""' "$T/tr-$t.json")
    echo "### TaskRun $t (tâche $k) : $(jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "-")|\(.reason // "-")"' "$T/tr-$t.json")"
    jq -r '.status.results[]? | "     résultat \(.name) : \(.value | if type == "string" then . else tojson end)"' "$T/tr-$t.json"
    cp "$T/tr-$t.json" "$T/$pr-$k.tr.json"
    [ -n "$p" ] || { echo "     aucun pod"; continue; }
    releve_pod "$p"
    for c in $(jq -r '.spec.containers[].name' "$T/pod-$p.json"); do
      kubectl logs -n builds "$p" -c "$c" < /dev/null 2>&1 | sed "$MASQUE05" > "$T/$pr-$k-$c.log" || true
      echo "     journal de $c : $(wc -l < "$T/$pr-$k-$c.log") lignes, dont $(lignes '^paquet ' "$T/$pr-$k-$c.log") « paquet » (non répétées)"
      grep -v '^paquet \|^\s*$' "$T/$pr-$k-$c.log" | cut -c1-240 | sed 's/^/       /'
    done
  done
  jq -r '.status.results[]? | "résultat de \(.name) : \(.value)"' "$T/pr-$pr-etat.json"
  attendu "PipelineRun $pr" "$r" "True|Succeeded"
  u=$(jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value' "$T/pr-$pr-etat.json")
  d=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$T/pr-$pr-etat.json")
  attendu "dépôt publié" "$u" "$IMAGE"
  attendu "construire : DIGEST_CONSTRUIT égal au digest publié" \
    "$(jq -r '.status.results[] | select(.name == "DIGEST_CONSTRUIT") | .value' "$T/$pr-construire.tr.json")" "$d"
  attendu "manifeste relu dans Zot (lecture anonyme) : digest du descripteur, couches" \
    "$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" "${IMAGE/$REG/$REG_HOTE}@$d" < /dev/null | jq -r .digest) $(
      oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" "${IMAGE/$REG/$REG_HOTE}@$d" < /dev/null | jq '.layers | length')" "$d 1"
  echo "relevé : artefact rpm $IMAGE@$d ; celui de la cascade $DIGEST_ESSAI : $([ "$d" = "$DIGEST_ESSAI" ] && echo égaux || echo différents) (relevé, non exigé)"
  attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
  echo "/ de sc-stockage : $(libre_zot) octets libres à $(date -u +%H:%M:%S)"
}

etape_entree() { rejeu_entree; }
etape_signature() { (charger_signature; etape_taches); }
etape_images() { (charger_images; etape_pipeline); }
etape_artefact() { (charger_mesure m1b-artefact.sh; rejeu_artefact); }
etape_fermeture() { (charger_mesure m1b-fermeture.sh; rejeu_fermeture); }
etape_construction_rpm() { (charger_mesure m1b-construction.sh; rejeu_construction); }

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  for e in "$@"; do
    [ ! -e "$R/m5b-rejeu-$TAG-$e.log" ] || { echo "journal déjà présent, jamais réécrit : m5b-rejeu-$TAG-$e.log" >&2; exit 2; }
  done
  lancer "m5b-rejeu-$TAG" "05 M5b rejeu ($TAG)" "$@"
fi
