#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b, M4b refait : banc de m1b-fermeture.sh, avant tout lancement. Rien n'est écrit dans Zot ni dans le
# cluster ; lectures anonymes de Zot et df sur sc-stockage seulement (étape local réelle).
#   A  copies : resultats/m1b-fermeture-copies.py verifier (blocs identiques à m1b-bundles.sh, etape_essai transformée et comptée)
#   B  lanceur : PREFIXE et TAG refusés (m4b, m4c, essai, invalides), étape inconnue refusée ; bash -n
#   C  étape local réelle, sous un préfixe de banc (dossier $W/<préfixe>-fermeture-05, retiré à la fin)
#   D  cas altérés de local et d'essai : chacun doit s'arrêter en KO sur le contrôle visé, avant toute action sur le cluster
#   E  (ajoutée le 20/11/2026) étape pipeline, la vraie fonction, avec le vrai tkn et une clé P-256 jetable du banc (jamais
#      taches.key) ; doublures : kubectl (dry-run serveur), zot_lire (état du banc), bundle (poussées comptées), auth_zot, sur,
#      lire_bundle du bundle neuf (celui de M4b est relu réellement). Cas : nominal, puis huit refus sans poussée ni version.
#   F  (ajoutée de même) étape rpm, la vraie fonction, mêmes doublures : huit gardes refusées avant toute création ; nominal
#      jusqu'à la première création réelle, interceptée par le faux kubectl (PipelineRun relu).
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-fermeture-banc.sh
set -uo pipefail
export LC_ALL=C
cd "$(dirname "$0")/../../../.."
F=poc/bricks/05-rpm-mock/m1b-fermeture.sh
OK=0; KO=0
ok() { echo "OK   $*"; OK=$((OK + 1)); }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
verifie() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else ko "$1 : $2 (attendu : $3)"; fi; }
B=bancfermeture   # préfixe fixe : ses dossiers sous $W sont retirés à la main, par chemin littéral, après archivage du journal
W0=$(bash -c 'here=poc/bricks/08-trust-plane; . "$here/commun.sh"; echo "$W"')
for d in "$W0/$B-fermeture-05" "$W0/$B-b-fermeture-05" "$W0"/$B-d[1-9]-fermeture-05 "$W0/$B-r" "$W0/$B-a.txt" "$W0/$B-local.log" "$W0/$B-ef"; do
  [ ! -e "$d" ] || { echo "KO   reste d'un banc précédent : ${d#"$W0"/}" >&2; exit 2; }
done
echo "# banc de m1b-fermeture.sh ($(sha256sum < "$F" | cut -c1-64)), préfixe $B, début $(date -u +%FT%TZ)"

echo "## A copies"
if python3 -I poc/bricks/05-rpm-mock/resultats/m1b-fermeture-copies.py verifier poc/bricks/05-rpm-mock > "$W0/$B-a.txt" 2>&1; then
  ok "copies : $(grep -c '^OK' "$W0/$B-a.txt") contrôles"; else ko "copies : $(tail -n 3 "$W0/$B-a.txt" | tr '\n' ' ')"; fi

echo "## B lanceur"
verifie "bash -n" "$(bash -n "$F" && echo ok)" ok
for t in m4b m4c essai 'A' ''; do
  [ -n "$t" ] || continue
  r=0; TAG=$t bash "$F" local > /dev/null 2>&1 || r=$?
  verifie "TAG=$t refusé (code)" "$r" 2
done
r=0; PREFIXE='x y' bash "$F" local > /dev/null 2>&1 || r=$?
verifie "PREFIXE invalide refusé (code)" "$r" 2
r=0; PREFIXE=$B-b bash "$F" digest-py > /dev/null 2>&1 || r=$?   # lancer refuse l'étape inconnue avant tout journal
verifie "étape inconnue refusée (code non nul)" "$([ "$r" != 0 ] && echo oui)" oui

echo "## C étape local réelle"
( PREFIXE=$B; . "$F"; etape_local ) > "$W0/$B-local.log" 2>&1; r=$?   # jamais dans un || : bash y couperait set -e
sed 's/^/     /' "$W0/$B-local.log" | cut -c1-250
verifie "local (code)" "$r" 0
verifie "local : KO" "$(grep -c '^KO' "$W0/$B-local.log")" 0
verifie "local : OK" "$(grep -c '^OK' "$W0/$B-local.log")" 35

echo "## D cas altérés (KO attendu sur le contrôle visé)"
altere() { # libellé motif-du-KO-attendu code-bash : préfixe $B-<D1…> propre au cas (dossier neuf, rien à vider)
  local r=0 s
  s=$( ( PREFIXE=$B-${1%% *}; PREFIXE=${PREFIXE,,}; . "$F"; eval "$3" ) 2>&1 ); r=$?   # hors d'un || : set -e actif
  if [ "$r" != 0 ] && grep -q -F "$2" <<< "$s"; then ok "$1 : arrêt sur « $2 »"
  else ko "$1 : code $r, dernier message : $(grep '^KO' <<< "$s" | tail -n 1 | cut -c1-200)"; fi
}
altere "D1 script neuf altéré" "KO   script neuf : tâche signée" 'SCRIPT_NEUF_SHA=${SCRIPT_NEUF_SHA/4d8b/0000}; etape_local'
altere "D2 arbre prédit altéré" "KO   arbre prédit (sha256)" 'ARBRE_PREDIT_SHA=${ARBRE_PREDIT_SHA/a731/0000}; etape_local'
altere "D3 verrou de M4b à la place du neuf : feuilles" "KO   feuilles différentes" 'VERROU_SRC=$VERROU_M4B; VERROU_SHA=$VERROU_M4B_SHA; etape_local'
altere "D4 prefetch-rpm hors de la liste revue" "KO   prefetch-rpm de la cascade, lue dans la liste revue" 'PREFETCH_REF=${PREFETCH_REF/b9bbeba3/00000000}; etape_local'
altere "D5 digest prédit altéré" "KO   digest prédit" 'DIGEST_PREDIT=${DIGEST_PREDIT/0983/0000}; etape_local'
altere "D6 essai sans local" "KO   arbre prédit absent" 'kubectl() { echo "kubectl appelé" >&2; exit 9; }; etape_essai'
mkdir -p "$W0/$B-r"; : > "$W0/$B-r/$B-d7-fermeture-essai-arbre.txt"
altere "D7 essai : arbre déjà archivé" "KO   déjà présent" "R=$W0/$B-r; kubectl() { echo kubectl >&2; exit 9; }; etape_essai"
mkdir -p "$W0/$B-d8-fermeture-05/local"; cp "$W0/$B-fermeture-05/local/arbre-predit.txt" "$W0/$B-d8-fermeture-05/local/"
altere "D8 essai : script substitué altéré" "KO   script substitué" 'SCRIPT_NEUF_SHA=${SCRIPT_NEUF_SHA/4d8b/0000}; R=/nonexistent-banc; kubectl() { echo kubectl >&2; exit 9; }; etape_essai'
altere "D9 gabarit modifié" "KO   fermeture/prefetch-rpm-sample-app.yaml (sha256)" \
  'GABARITS_SHA=${GABARITS_SHA/ee74c258/00000000}; etape_local'

echo "## E étape pipeline (vraie fonction, vrai tkn, clé P-256 jetable ; doublures : kubectl, zot_lire, bundle, auth_zot, sur, lire_bundle du bundle neuf)"
EF=$W0/$B-ef
mkdir -p "$EF/cle"
(umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$EF/cle/taches.key" 2> /dev/null)
openssl pkey -in "$EF/cle/taches.key" -pubout -out "$EF/cle/taches.pub" 2> /dev/null
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2> /dev/null | openssl pkey -pubout -out "$EF/cle/autre.pub" 2> /dev/null
verifie "E clé jetable du banc (P-256)" "$(openssl pkey -in "$EF/cle/taches.pub" -pubin -noout -text 2> /dev/null | grep -c 'NIST CURVE: P-256')" 1
CA=$(dirname "$W0")/pki/ca-poc.crt   # certificat public de la CA du PoC (lectures anonymes réelles du bundle de M4b)
ZOT_BASE="tekton/pipelines/prefetch-rpm-sample-app:m4b sha256:9b89b0299353cd66f37c02484628d5d177f27043624f3f05b8f1a642738eb9db
tekton/tasks/prefetch-rpm:m1b sha256:b9bbeba3e8c62113431cdb88aa74afe76bab13a28ab548a5b5ae6ffed22675dc
builds/fermetures/sample-app-rpm@sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c"
FAUSSE=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa   # digest de pipeline du banc (étape rpm)
doublures() { # après chargement du script, dans le sous-shell du cas
  eval "lire_bundle_reel() $(declare -f lire_bundle | tail -n +2)"
  kubectl() {
    echo "kubectl $*" >> "$BW/appels"
    case "$*" in
      "create --dry-run=server -n builds -f "*)
        if [ -n "${BANC_REFUSEE:-}" ] && [ "$(yq .metadata.name "${*: -1}")" = "$BANC_REFUSEE" ]; then echo "refus du banc" >&2; return 1; fi
        return 0 ;;
      "get pipelinerun -n builds "*" -o name") if [ -n "${BANC_PR_EXISTE:-}" ]; then return 0; else echo "NotFound (banc)" >&2; return 1; fi ;;
      "create -f "*) cp "${*: -1}" "$BW/cree.json"; echo "création interceptée par le banc" >&2; return 7 ;;
    esac
    echo "faux kubectl : appel inattendu : $*" >&2; return 3
  }
  zot_lire() { local d; d=$(awk -v r="$2" '$1 == r {x = $2} END {print x}' "$BW/zot.txt"); echo "${d:-absent}"; }
  bundle() { local d; d=sha256:$(sha256sum < "$1" | cut -c1-64); echo "$2:$3 $d" >> "$BW/poussees"; echo "$2:$3 $d" >> "$BW/zot.txt"; echo "$d"; }
  auth_zot() { printf '{"faux":1}\n' > "$1"; }
  sur() { echo " ${BANC_LIBRE-3000000000}"; }
  lire_bundle() { if [ "$1" = "$PIPELINE_M4B" ]; then lire_bundle_reel "$@"; else yq -o=json "$TACHES/prefetch-rpm-sample-app.$TAG.signee.yaml" > "$2"; fi; }
}
ef() { # nom code-bash [sans-clé] : un cas dans un sous-shell (CONFIANCE_DIR du banc, gabarits copiés, état de Zot) ; code rendu
  local w=$EF/$1 r=0
  mkdir -p "$w/O/pki" "$w/O/secrets" "$w/fermeture"; chmod 700 "$w/O/secrets"
  cp "$CA" "$w/O/pki/ca-poc.crt"
  cp poc/bricks/05-rpm-mock/fermeture/prefetch-rpm.yaml poc/bricks/05-rpm-mock/fermeture/prefetch-rpm-sample-app.yaml "$w/fermeture/"
  [ -n "${3:-}" ] || (umask 077 && cp "$EF/cle/taches.key" "$w/O/secrets/taches.key")
  printf '%s\n' "$ZOT_BASE" > "$w/zot.txt"; : > "$w/appels"; : > "$w/poussees"
  ( export CONFIANCE_DIR=$w/O BW=$w; . "$F"; TACHES=$w/fermeture; doublures; eval "$2" ) > "$w/sortie.txt" 2>&1; r=$?   # hors d'un || : set -e actif
  echo "$r"
}
attendu_ko() { # cas motif : arrêt en KO sur le motif, sans poussée ni signature versionnée ni création
  local w=$EF/$1
  if [ "$(cat "$w/code")" != 0 ] && grep -q -F "$2" "$w/sortie.txt"; then ok "$1 : arrêt sur « $2 »"
  else ko "$1 : code $(cat "$w/code"), dernier message : $(grep '^KO' "$w/sortie.txt" | tail -n 1 | cut -c1-200)"; fi
  verifie "$1 : ni poussée, ni signature versionnée, ni création" \
    "$(wc -l < "$w/poussees") $(find "$w/fermeture" -name '*.m1b.signee.yaml' -size +0 | wc -l) $([ -e "$w/cree.json" ] && echo 1 || echo 0)" "0 0 0"
}
ef E1 'SIGNER=1; etape_pipeline' > "$EF/code.E1"; mkdir -p "$EF/E1"; mv "$EF/code.E1" "$EF/E1/code"
grep -v '^     ' "$EF/E1/sortie.txt" | cut -c1-170 | sed 's/^/   | /'
v=$EF/E1/fermeture/prefetch-rpm-sample-app.m1b.signee.yaml
verifie "E1 nominal : code" "$(cat "$EF/E1/code")" 0
verifie "E1 nominal : KO" "$(grep -c '^KO' "$EF/E1/sortie.txt")" 0
verifie "E1 nominal : OK" "$(grep -c '^OK' "$EF/E1/sortie.txt")" 28
verifie "E1 nominal : poussée unique (dépôt:tag digest)" "$(cat "$EF/E1/poussees")" "tekton/pipelines/prefetch-rpm-sample-app:m1b sha256:$(sha256sum < "$v" | cut -c1-64)"
verifie "E1 nominal : signature versionnée vérifiée par tkn (clé publique du banc)" "$(tkn pipeline verify "$v" -K "$EF/cle/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
verifie "E1 nominal : refus de tkn avec une autre clé" "$(tkn pipeline verify "$v" -K "$EF/cle/autre.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" refusée
verifie "E1 nominal : références de la version (prefetch-rpm, publier-fermeture)" \
  "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$v")" \
  "sc-stockage.poc.test:5000/tekton/tasks/prefetch-rpm@sha256:b9bbeba3e8c62113431cdb88aa74afe76bab13a28ab548a5b5ae6ffed22675dc sc-stockage.poc.test:5000/tekton/tasks/publier-fermeture@sha256:7fa92ad3e4adb0d4b9bc4209ee04096d476dee5ffa173fc08b9cac0614e2b135"
verifie "E1 nominal : dépôt de la fermeture dans la version" "$(yq '.spec.tasks[1].params[0].value' "$v")" sc-stockage.poc.test:5000/builds/fermetures/sample-app-rpm
verifie "E1 nominal : \$T/auth absent à la fin" "$([ -e "$EF/E1/O/travail/m1b-fermeture-05/auth" ] && echo présent || echo absent)" absent
verifie "E1 nominal : appels de kubectl, dry-run serveur seulement" "$(grep -v -c '^kubectl create --dry-run=server -n builds -f ' "$EF/E1/appels")" 0
cas() { ef "$@" > "$EF/code.$1"; mv "$EF/code.$1" "$EF/$1/code"; }
cas E2 'etape_pipeline'; attendu_ko E2 "KO   étape pipeline : SIGNER=1 seulement"
cas E3 'SIGNER=1; etape_pipeline' sans-cle; attendu_ko E3 "KO   clé des tâches absente"
mkdir -p "$EF/E4/fermeture"; : > "$EF/E4/fermeture/prefetch-rpm-sample-app.m1b.signee.yaml"
cas E4 'SIGNER=1; etape_pipeline'
if [ "$(cat "$EF/E4/code")" != 0 ] && grep -q -F "KO   déjà présent" "$EF/E4/sortie.txt" && [ ! -s "$EF/E4/poussees" ]; then ok "E4 version déjà présente : arrêt, sans poussée"; else ko "E4 version déjà présente"; fi
cas E5 'SIGNER=1; echo "tekton/pipelines/prefetch-rpm-sample-app:m1b $FAUSSE" >> "$BW/zot.txt"; etape_pipeline'; attendu_ko E5 "KO   tag m1b de la pipeline, absent"
cas E6 'SIGNER=1; echo "tekton/pipelines/prefetch-rpm-sample-app:m4b $FAUSSE" >> "$BW/zot.txt"; etape_pipeline'; attendu_ko E6 "KO   tag m4b de la pipeline, sur celle de M4b"
cas E7 'SIGNER=1; BANC_LIBRE=1000; etape_pipeline'; attendu_ko E7 "sous 1073741824"
cas E8 'SIGNER=1; BANC_REFUSEE=prefetch-rpm-sample-app; etape_pipeline'; attendu_ko E8 "KO   pipeline rendue admise"
cas E9 'SIGNER=1; PUBLIER_REF=${PUBLIER_REF/7fa92ad3/00000000}; etape_pipeline'; attendu_ko E9 "KO   publier-fermeture, lue dans la liste revue"

echo "## F étape rpm, gardes (vraie fonction, mêmes doublures ; la première création réelle est interceptée)"
PR_OK="PIPELINE_REF=\$REG/tekton/pipelines/prefetch-rpm-sample-app@$FAUSSE; echo \"tekton/pipelines/prefetch-rpm-sample-app:m1b $FAUSSE\" >> \"\$BW/zot.txt\""
cas F1 'PIPELINE_REF=; etape_rpm'; attendu_ko F1 "KO   PIPELINE_REF non épinglée"
verifie "F1 : aucun appel de kubectl" "$(wc -l < "$EF/F1/appels")" 0
cas F2 "PIPELINE_REF=\$REG/tekton/pipelines/prefetch-rpm-sample-app@$FAUSSE; etape_rpm"; attendu_ko F2 "KO   pipeline relue dans Zot au tag m1b"
cas F3 "$PR_OK; echo \"tekton/pipelines/prefetch-rpm-sample-app:m4b $FAUSSE\" >> \"\$BW/zot.txt\"; etape_rpm"; attendu_ko F3 "KO   tag m4b de la pipeline, inchangé"
cas F4 "$PR_OK; sed -i '/^builds/d' \"\$BW/zot.txt\"; etape_rpm"; attendu_ko F4 "KO   fermeture de M4b présente dans le même dépôt"
cas F5 "$PR_OK; echo \"builds/fermetures/sample-app-rpm@\$DIGEST_PREDIT \$DIGEST_PREDIT\" >> \"\$BW/zot.txt\"; etape_rpm"; attendu_ko F5 "KO   fermeture prédite absente avant le premier PipelineRun"
cas F6 "$PR_OK; BANC_PR_EXISTE=1; etape_rpm"; attendu_ko F6 "m1b-rpm-1 existe déjà"
cas F7 "$PR_OK; BANC_LIBRE=1000; etape_rpm"; attendu_ko F7 "KO   espace libre illisible ou sous la garde"
cas F8 "$PR_OK; PREFETCH_REF=\${PREFETCH_REF/b9bbeba3/00000000}; etape_rpm"; attendu_ko F8 "KO   prefetch-rpm absente de la liste revue"
cas F9 "$PR_OK; etape_rpm"
grep -v '^     ' "$EF/F9/sortie.txt" | cut -c1-170 | sed 's/^/   | /'
verifie "F9 nominal jusqu'à la création : arrêt sur la création interceptée (code)" "$(cat "$EF/F9/code")" 7
verifie "F9 : KO avant la création" "$(grep -c '^KO' "$EF/F9/sortie.txt")" 0
verifie "F9 : appels de kubectl (get, dry-run, create)" "$(cut -d' ' -f2-3 "$EF/F9/appels" | paste -sd'|')" "get pipelinerun|create --dry-run=server|create -f"
verifie "F9 : PipelineRun créé (nom, bundle de la pipeline, nom, workspace, sans runtimeClassName)" \
  "$(jq -c '[.metadata.name, .spec.pipelineRef.params[0].value, .spec.pipelineRef.params[1].value, .spec.workspaces[0].volumeClaimTemplate.spec.resources.requests.storage, (.spec.taskRunTemplate.podTemplate.runtimeClassName // "aucun")]' "$EF/F9/cree.json")" \
  "[\"m1b-rpm-1\",\"sc-stockage.poc.test:5000/tekton/pipelines/prefetch-rpm-sample-app@$FAUSSE\",\"prefetch-rpm-sample-app\",\"1Gi\",\"aucun\"]"
verifie "F9 : couches attendues tirées de l'arbre de l'essai" "$(grep -c '^OK   arbre de l.essai archivé (sha256), égal à l.arbre prédit' "$EF/F9/sortie.txt")" 1

echo "## G étape rpm jusqu'au bout (ajoutée le 20/11/2026 après la signature de la pipeline) : faux kubectl servant les objets"
echo "##   réels des PipelineRuns de M4b (TaskRuns, pods, journaux des pas, gardés sous \$W/m4b-05), valeurs de M4b remplacées par"
echo "##   celles de la cascade (noms m1b-rpm-*, bootstrap neuf, digest prédit) ; faux oras pour le manifeste neuf seulement"
M4B=$W0/m4b-05
G=$EF/G-objets
mkdir -p "$G"
for i in 1 2; do
  for f in "tr-m4b-rpm-$i-prefetch.json" "tr-m4b-rpm-$i-publier.json" "pod-m4b-rpm-$i-prefetch-pod.json" "pod-m4b-rpm-$i-publier-pod.json" \
           "m4b-rpm-$i-prefetch-step-prefetch.log" "m4b-rpm-$i-publier-step-publier.log"; do
    sed -e 's/m4b-rpm-/m1b-rpm-/g' -e 's#essais-05/rocky9-bootstrap#builds/builders/rocky9-bootstrap#g' \
      -e 's/f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6/6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3/g' \
      -e 's/2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c/0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f/g' \
      "$M4B/$f" > "$G/${f//m4b-rpm-/m1b-rpm-}"
  done
done
verifie "G objets de M4b transposés (12 fichiers, plus aucune valeur de M4b)" \
  "$(ls "$G" | wc -l) $(cat "$G"/* | grep -c 'm4b-rpm-\|f0ccf105\|2a9e2ea7\|essais-05/rocky9-bootstrap')" "12 0"
complet() { # doublures du cas G, après doublures
  kubectl() {
    echo "kubectl $*" >> "$BW/appels"
    case "$*" in
      "create --dry-run=server -n builds -f "*) return 0 ;;
      "get pipelinerun -n builds "*" -o name") grep -qx "$5" "$BW/crees" 2> /dev/null ;;   # $5 : nom de l'objet
      "create -f "*) jq -r .metadata.name "${*: -1}" >> "$BW/crees"; cp "${*: -1}" "$BW/cree-$(jq -r .metadata.name "${*: -1}").json" ;;
      "get pipelinerun -n builds "*" -o json")
        jq -n --arg u "$DEPOT_FERMETURE" --arg d "$DIGEST_PREDIT" '{status: {conditions: [{type: "Succeeded", status: "True", reason: "Succeeded"}],
          startTime: "2026-11-20T00:00:00Z", completionTime: "2026-11-20T00:03:00Z", results: [{name: "IMAGE_URL", value: $u}, {name: "IMAGE_DIGEST", value: $d}]}}' ;;
      "get pipelinerun -n builds "*" -o jsonpath="*) echo true ;;   # annotation de Chains (signe)
      "get taskrun -n builds -l tekton.dev/pipelineRun="*) echo "${6#*=}-prefetch ${6#*=}-publier" ;;
      "get taskrun -n builds "*" -o json") cat "$BANC_G/tr-$5.json" ;;
      "get pod -n builds "*" -o json") cat "$BANC_G/pod-$5.json" ;;
      "logs -n builds "*" -c "*) cat "$BANC_G/${4%-pod}-$6.log" ;;
      *) echo "faux kubectl : appel inattendu : $*" >&2; return 3 ;;
    esac
  }
  oras() { # manifeste de la fermeture prédite : 230 couches ; tout le reste, le vrai oras
    case "$*" in *"@$DIGEST_PREDIT"*) jq -n '{layers: [range(230) | {}]}' ;; *) command oras "$@" ;; esac
  }
}
cas G "BANC_G=$G; complet; echo \"tekton/pipelines/prefetch-rpm-sample-app:m1b \${PIPELINE_REF##*@}\" >> \"\$BW/zot.txt\"; etape_rpm"
grep -v '^     \|^       ' "$EF/G/sortie.txt" | cut -c1-170 | sed 's/^/   | /'
verifie "G : code" "$(cat "$EF/G/code")" 0
verifie "G : KO" "$(grep -c '^KO' "$EF/G/sortie.txt")" 0
verifie "G : OK" "$(grep -c '^OK' "$EF/G/sortie.txt")" 36
verifie "G : deux PipelineRuns créés, dans l'ordre" "$(paste -sd' ' "$EF/G/crees")" "m1b-rpm-1 m1b-rpm-2"
verifie "G : PipelineRun créé, bundle de la pipeline épinglée" "$(jq -r '.spec.pipelineRef.params[0].value' "$EF/G/cree-m1b-rpm-2.json")" \
  "sc-stockage.poc.test:5000/tekton/pipelines/prefetch-rpm-sample-app@sha256:61814acd6f15f0fde07f9f701f2e8cfd4324218caf2df9e1befcf182495ca60c"
verifie "G : lignes finales (même fermeture, M4b présente après, fermeture neuve)" \
  "$(grep -c '^OK   deux exécutions, même fermeture\|^OK   fermeture de M4b toujours présente après\|^fermeture neuve : sc-stockage.poc.test:5000/builds/fermetures/sample-app-rpm@sha256:0983898054a9' "$EF/G/sortie.txt")" 3
verifie "G : couches attendues = 230 (journal de publier et manifeste)" "$(grep -c '^OK   \(publier : 230 couches dans le journal\|manifeste relu dans Zot (lecture anonyme) : couches : 230\)' "$EF/G/sortie.txt")" 4
verifie "G : digest relevé égal au prédit (relevé)" "$(grep -c 'calculé\|prédit à sec sha256:0983898054a9[0-9a-f]* : égaux' "$EF/G/sortie.txt")" 2

echo "     dossiers du banc laissés sous \$W : $B-fermeture-05, $B-b-fermeture-05, $B-d1…d9-fermeture-05, $B-r, $B-a.txt, $B-local.log, $B-ef"
echo "# fin $(date -u +%FT%TZ) : $OK OK, $KO KO"
[ "$KO" = 0 ]
