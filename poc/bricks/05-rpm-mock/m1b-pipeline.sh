#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : étape pipeline (carte resultats/m1b-carte.md, « deux PipelineRuns par image (même digest) »), préparée à
# sec le 19/11/2026 sur le modèle de l'étape pipeline de m4c.sh, NON LANCÉE. Script à part : m1b-builders.sh et m1b-signature.sh,
# dont les sha256 sont cités par des prédictions, ne sont pas touchés.
#   pipeline  cluster et Zot : quatre PipelineRuns, deux par image, l'un après l'autre ($N-o-1, $N-o-2 : builder-mock-rocky9 ;
#             $N-b-1, $N-b-2 : builder-rocky9-bootstrap), pipelines signées au tag m1b ; podTemplate de M4c (ni env), Kata pour
#             la seule tâche construire (taskRunSpecs). Gardes, toutes avant la première création :
#             - mesure d'un autre jour : digests du banc et des essais de $MESURE égaux à ceux de m1bt3 (sinon refus : la mesure
#               a divergé, rien n'est comparé à hier) ; tailles des image.tar lues dans son journal d'essai ;
#             - pipelines : référence écrite par m1b-signature.sh, relue dans Zot au tag m1b (lecture anonyme) ; trois tâches
#               dans la liste revue, celles de la signature ; image publiée et racine fixée par la pipeline signée ;
#             - politiques de builds relues dans le cluster : NotIn de builds-sans-internet à quatre labels ; prefetch-racine-rpm
#               sélectionné par sa seule sortie ; construire-racine-rpm sélectionné par builds-sans-internet et sa NetworkPolicy,
#               aucune n'autorise de trafic ;
#             puis, avant chaque PipelineRun : nom absent, dépôt de l'image absent avant le premier, place libre sur / de
#             sc-stockage au moins LIBRE_MIN plus la taille de l'image.tar, dry-run serveur. Rien n'est purgé : une relance se
#             fait sous un autre PREFIXE. Preuve imprimée avant toute assertion ; jamais le message d'une condition ni une
#             variable d'environnement. Contrôles : tâches, Kata et nœud par pod ; journaux de prefetch et de construire
#             (témoins réseau, racine conforme, manifeste) ; BASE_ARTIFACT_INPUTS (outillage : déclaré, non écrit, relevé ;
#             bootstrap : la base vérifiée) ; DIGEST_CONSTRUIT, IMAGE_URL, IMAGE_DIGEST, ligne de publication, manifeste relu
#             dans Zot (lecture anonyme, nombre de couches) ; PipelineRun signé par Chains ; deux exécutions, même digest.
# Aucun secret : rien n'est écrit dans Zot par ce script (publier-image pousse, avec son compte, dans le pod).
# Usage (racine du dépôt) : [PREFIXE=m1b] DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m1b-pipeline.sh pipeline
#         (journal : resultats/m1b-pipeline-pipeline.log ; journaux des pas : resultats/m1b-pipeline-<PipelineRun>-<tâche>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # O, S, P, W, REG, REG_HOTE, sur, signe, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
N=${PREFIXE:-m1b}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
MESURE=${MESURE:-$W/m1bt-20-05}                   # mesure d'un autre jour (m1b-jour-kata.sh, préfixe de la tâche m1bt-20)
SIG=${SIG:-$W/m1b-signature-05}                   # sorties de m1b-signature.sh (références, pipelines signées)
LISTE_REVUE=${LISTE_REVUE:-$here/politique/porte/taches.yml}
T=$W/$N-pipeline-05
mkdir -p "$T"
umask 022

PUBLIER_REF=$REG/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b   # liste revue
LIBRE_MIN=1073741824   # garde de M4 (1 Gio), plus la taille de l'image à pousser (couches non compressées)
PVC_TAILLE=2Gi         # essais de m1bt3 : entrées et image.tar des deux images sur un seul PVC de 2Gi
LABELS_NOTIN=prefetch-deb,prefetch-gomod,prefetch-racine-rpm,prefetch-rpm   # après m1b_sortie (08c)
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'
# Par image : nom de la pipeline, dépôt publié, digest et racine (banc et essais de m1bt3, 19/11/2026 ; journaux archivés), nombre
# de rpm, d'entrées et liste de leurs sha256 (essai_prefetch de m1bt3), nombre de couches
# shellcheck disable=SC2034  # table lue par indirection (v)
{
  NOM_o=builder-mock-rocky9;      IMAGE_o=$REG/builds/builders/mock-rocky9
  DIGEST_o=sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae
  CIBLE_o=7c07083cd7bee149d391180633ad9cca6c82c7ad0dfa5c6bf248acad0b1ef9b7; RPM_o=199; ENTREES_o=224
  LISTE_o=93f2a63ef2e49607d2844e07d7dfc7f793537f350be492c4acf82815ec280535; COUCHES_o=2
  NOM_b=builder-rocky9-bootstrap; IMAGE_b=$REG/builds/builders/rocky9-bootstrap
  DIGEST_b=sha256:6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3
  CIBLE_b=b063feb3206deb3f1c0ad4eb7b497d683693967d194c7fdd366a2b0094823348; RPM_b=10; ENTREES_b=20
  LISTE_b=7af63de76df231b2c106629aff7ce628282053dd5831d50bc157dafcb6ca2325; COUCHES_b=1
}
BASE_b='{"digest":"sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2","uri":"oci://sc-stockage.poc.test:5000/amont/rockylinux/rockylinux"}'
ECARTS=0

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
mesure() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS=$((ECARTS + 1)); }; }
echec() { echo "KO   $*" >&2; exit 1; }
v() { local n="$1_$2"; echo "${!n}"; }   # champ image : valeur de la table ci-dessus
lignes() { grep -c -- "$1" "$2" || true; }   # motif fichier : nombre de lignes
filtre() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g' | sed "$MASQUE"; }   # MASQUE est en BRE : hors de sed -E (banc du 19/11)
admission() { # fichier : kubectl create --dry-run=server dans builds (rien n'est créé) ; code de kubectl ; jamais le texte
  local rc=0
  kubectl create --dry-run=server -n builds -f "$1" < /dev/null > /dev/null 2> "$T/admission.err" || rc=$?
  echo "$rc"
}
libre_zot() { sur sc-stockage 'df -B1 --output=avail / | tail -n 1' < /dev/null | tr -d ' '; }   # m4b.sh
listee_ref() { # référence par digest : présente dans la liste revue (sous la clé de son dépôt) ; m1b-signature.sh
  awk -v d="oci://${1%@*}:" -v r="${1#*@}" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && $3 == r {t = 1} END {exit !t}' "$LISTE_REVUE"
}
bundles_pipeline() { yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$1"; }
descripteur() { oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "${1/$REG/$REG_HOTE}" < /dev/null | jq -r .digest; }
politiques() { # politiques de builds relues dans le cluster (lecture seule) ; sel : filtre jq avec selecteurs.jq (08)
  { kubectl get networkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "NetworkPolicy"'
    kubectl get ciliumnetworkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "CiliumNetworkPolicy"'; } | jq -s '{items: .}' > "$T/politiques.json"
}
sel() { jq -r -L "$here" "include \"selecteurs\"; $1" "$T/politiques.json"; }
politiques_m1b() { # invariants de sortie-builds.sh (m1b_sortie, m1b_sans_sortie), relus sur le cluster
  politiques
  echo "politiques de builds : $(sel '[.items[] | nom] | join(", ")')"
  attendu "NotIn de builds-sans-internet" \
    "$(sel '[.items[] | select(nom == "CiliumNetworkPolicy builds-sans-internet") | .spec.endpointSelector.matchExpressions[0].values | sort | join(",")] | join(" ")')" "$LABELS_NOTIN"
  attendu "politiques qui sélectionnent un pod de prefetch-racine-rpm" \
    "$(sel '[.items[] | select(selectionne({"tekton.dev/task": "prefetch-racine-rpm"})) | nom] | sort | join(", ")')" "CiliumNetworkPolicy prefetch-racine-rpm-sortie"
  attendu "politiques qui sélectionnent un pod de construire-racine-rpm" \
    "$(sel '[.items[] | select(selectionne({"tekton.dev/task": "construire-racine-rpm"})) | nom] | sort | join(", ")')" \
    "CiliumNetworkPolicy builds-sans-internet, NetworkPolicy construction-racine-rpm-sans-sortie"
  attendu "politiques qui autorisent du trafic à un pod de construire-racine-rpm" \
    "$(sel '[.items[] | select(selectionne({"tekton.dev/task": "construire-racine-rpm"}) and autorise) | nom] | join(", ")')" ""
  attendu "types des NetworkPolicy qui sélectionnent un pod de construire-racine-rpm" \
    "$(sel '[.items[] | select(.kind == "NetworkPolicy" and selectionne({"tekton.dev/task": "construire-racine-rpm"})) | (.spec.policyTypes | sort | join("+"))] | join(", ")')" "Egress+Ingress"
}
pr_json() { # nom pipeline référence : PipelineRun ; podTemplate de M4c (nodeSelector, tolérance, contexte de sécurité ; ni env) ;
  # Kata pour la seule tâche construire (taskRunSpecs) ; workspace sortie sur un PVC de $PVC_TAILLE ; aucun paramètre (tous fixés
  # par la pipeline signée)
  jq -n --arg n "$1" --arg p "$2" --arg b "$3" --arg t "$PVC_TAILLE" '
    {nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}}} as $z
    | {apiVersion: "tekton.dev/v1", kind: "PipelineRun", metadata: {name: $n, namespace: "builds"},
      spec: {pipelineRef: {resolver: "bundles", params: [{name: "bundle", value: $b}, {name: "name", value: $p}, {name: "kind", value: "pipeline"}]},
        workspaces: [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: $t}}}}}],
        taskRunTemplate: {serviceAccountName: "build", podTemplate: $z},
        taskRunSpecs: [{pipelineTaskName: "construire", podTemplate: ($z + {runtimeClassName: "kata"})}]}}' > "$T/pr-$1.json"
}
statut() { # type nom : « statut|raison » de la condition Succeeded (jamais le message) ; m4c.sh
  kubectl get "$1" -n builds "$2" -o json < /dev/null | jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "")|\(.reason // "")"'
}
attendre_pr() { # nom : attend la fin (3600 s au plus) ; « statut|raison » ; m4c.sh
  local st=""
  for _ in $(seq 1800); do
    st=$(statut pipelinerun "$1"); case $st in True\|*|False\|*) break ;; esac; sleep 2
  done
  echo "$st"
}
releve_pod() { # pod : nœud, runtimeClassName, label ; conteneurs (état, code, raison) ; ressources ; jamais de message ni d'env
  kubectl get pod -n builds "$1" -o json < /dev/null > "$T/pod-$1.json" || { echo "     pod $1 illisible"; return 0; }
  jq -r '"     pod \(.metadata.name) : nœud \(.spec.nodeName // "-"), runtimeClassName « \(.spec.runtimeClassName // "") », tekton.dev/task \(.metadata.labels["tekton.dev/task"] // "-"), phase \(.status.phase // "-")",
    ((.status.initContainerStatuses // []) + (.status.containerStatuses // []) | .[] |
      "     conteneur \(.name) : \(.state | to_entries[0] | "\(.key) code \(.value.exitCode // "-") raison \(.value.reason // "-")")"),
    ((.spec.initContainers // []) + .spec.containers | .[] |
      "     ressources \(.name) : demandes \(.resources.requests // {} | tojson) ; limites \(.resources.limits // {} | tojson)")' "$T/pod-$1.json"
}
gardes_mesure() { # la mesure d'un autre jour a redonné les digests de m1bt3 ; tailles des image.tar
  local pt x j
  pt=$(basename "$MESURE"); pt=${pt%-05}
  echo "## mesure d'un autre jour : $pt (${MESURE/#$HOME/\~})"
  j=$R/m1b-builders-$pt-essai_construire.log
  [ -s "$j" ] || echec "journal de l'essai de construction de $pt absent : ${j#"$R"/}"
  for x in o b; do
    attendu "$x : digest du banc de $pt égal à celui de m1bt3" "$(cat "$MESURE/banc-digest-$x" 2> /dev/null)" "$(v DIGEST "$x")"
    attendu "$x : DIGEST_CONSTRUIT de l'essai $pt-c$x égal au banc" \
      "$(lignes "^OK   DIGEST_CONSTRUIT du pod $pt-c$x = celui du banc : $(v DIGEST "$x")$" "$j")" 1
    printf -v "TAILLE_$x" '%s' "$(sed -n "/^## essai-c$x : début/,/^## essai-c$x : code/s/^ *image.tar : \([0-9]*\) octets, .*/\1/p" "$j")"
    [[ $(v TAILLE "$x") =~ ^[0-9]+$ ]] || echec "$x : taille de image.tar illisible dans ${j#"$R"/}"
    echo "$x : image.tar de l'essai $pt-c$x : $(v TAILLE "$x") octets"
  done
}
gardes_pipelines() { # pipelines signées, relues dans Zot ; leurs tâches dans la liste revue
  local x nom ref f r a
  for x in o b; do
    nom=$(v NOM "$x"); f=$SIG/$nom-signee.yaml
    echo "## pipeline $nom"
    [ -s "$SIG/$nom.ref" ] && [ -s "$f" ] || echec "$nom : référence ou pipeline signée absente (m1b-signature.sh, seconde passe)"
    ref=$(cat "$SIG/$nom.ref")
    [[ $ref =~ ^$REG/tekton/pipelines/$nom@sha256:[0-9a-f]{64}$ ]] || echec "$nom : référence de forme inattendue : $ref"
    printf -v "REF_$x" '%s' "$ref"
    attendu "$nom relue dans Zot au tag m1b (lecture anonyme)" "$REG/tekton/pipelines/$nom@$(descripteur "$REG/tekton/pipelines/$nom:m1b")" "$ref"
    attendu "$nom signée : nom" "$(yq .metadata.name "$f")" "$nom"
    a="$(cat "$SIG/prefetch-racine-rpm.ref") $(cat "$SIG/construire-racine-rpm.ref") $PUBLIER_REF"
    attendu "$nom signée : tâches (celles de la signature et publier-image)" "$(bundles_pipeline "$f")" "$a"
    for r in $a; do listee_ref "$r" && echo "OK   dans la liste revue : $r" || echec "absente de la liste revue : $r"; done
    attendu "$nom signée : dépôt publié" "$(yq '.spec.tasks[2].params[] | select(.name == "image") | .value' "$f")" "$(v IMAGE "$x")"
    attendu "$nom signée : racine fixée" "$(yq '.spec.tasks[1].params[] | select(.name == "racine") | .value' "$f")" "$(v CIBLE "$x")"
  done
}
controler_pr() { # PipelineRun image : preuve imprimée, puis assertions (stop) et mesures (écarts)
  local pr=$1 x=$2 r t k p c j g d u pf cf
  r=$(attendre_pr "$pr")
  echo "$pr : condition Succeeded « $r », relevée à $(date -u +%H:%M:%S)"
  kubectl get pipelinerun -n builds "$pr" -o json < /dev/null > "$T/pr-$pr-etat.json"
  jq -r '"     début \(.status.startTime // "-") ; fin \(.status.completionTime // "-")"' "$T/pr-$pr-etat.json"
  for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
    kubectl get taskrun -n builds "$t" -o json < /dev/null > "$T/tr-$t.json"
    k=$(jq -r '.metadata.labels["tekton.dev/pipelineTask"] // "-"' "$T/tr-$t.json")
    p=$(jq -r '.status.podName // ""' "$T/tr-$t.json")
    echo "### TaskRun $t (tâche $k) : $(jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "-")|\(.reason // "-")"' "$T/tr-$t.json") ; début $(jq -r '.status.startTime // "-"' "$T/tr-$t.json") ; fin $(jq -r '.status.completionTime // "-"' "$T/tr-$t.json")"
    jq -r '.status.results[]? | "     résultat \(.name) : \(.value | if type == "string" then . else tojson end)"' "$T/tr-$t.json"
    cp "$T/tr-$t.json" "$T/$pr-$k.tr.json"
    [ -n "$p" ] || { echo "     aucun pod"; continue; }
    echo "$p" > "$T/$pr-$k.pod"
    releve_pod "$p"
    for c in $(jq -r '.spec.containers[].name' "$T/pod-$p.json"); do
      kubectl logs -n builds "$p" -c "$c" < /dev/null 2>&1 | filtre > "$T/$pr-$k-$c.log" || true
      echo "     journal de $c : $(wc -l < "$T/$pr-$k-$c.log") lignes"
      head -n 200 "$T/$pr-$k-$c.log" | cut -c1-240 | sed 's/^/       /'
    done
  done
  jq -r '.status.results[]? | "résultat de \(.name) : \(.value)"' "$T/pr-$pr-etat.json"
  pf=$T/$pr-prefetch-step-prefetch.log; cf=$T/$pr-construire-step-construire.log
  for j in "$pf:prefetch" "$cf:construire"; do [ ! -f "${j%%:*}" ] || cp "${j%%:*}" "$R/m1b-pipeline-$pr-${j##*:}.log"; done
  attendu "PipelineRun $pr" "$r" "True|Succeeded"
  for j in prefetch:prefetch-racine-rpm: construire:construire-racine-rpm:kata publier:publier-image:; do
    IFS=: read -r k g c <<< "$j"
    attendu "$pr, $k : tekton.dev/task|runtimeClassName|nœud" \
      "$(jq -r '"\(.metadata.labels["tekton.dev/task"] // "")|\(.spec.runtimeClassName // "")|\(.spec.nodeName // "")"' "$T/pod-$(cat "$T/$pr-$k.pod").json")" "$g|$c|sc-build"
  done
  attendu "prefetch : rpm -K" "$(lignes "^rpm -K : rc 0, $(v RPM "$x") OK sur $(v RPM "$x")$" "$pf")" 1
  mesure "prefetch : entrées (nombre, liste des sha256 égale à l'essai de m1bt3)" \
    "$(sed -n 's/^entrées : \([0-9]*\) fichiers, [0-9]* octets ; liste des sha256 : \([0-9a-f]\{64\}\) ;.*/\1 \2/p' "$pf")" "$(v ENTREES "$x") $(v LISTE "$x")"
  if [ "$x" = o ]; then
    echo "relevé : outillage, BASE_ARTIFACT_INPUTS déclaré : $(jq -r '[.status.taskSpec.results[]? | select(.name == "BASE_ARTIFACT_INPUTS")] | length' "$T/$pr-prefetch.tr.json") ; ligne « non écrit » : $(lignes '^aucune base : BASE_ARTIFACT_INPUTS non écrit$' "$pf")"
    attendu "prefetch (outillage) : BASE_ARTIFACT_INPUTS absent des résultats du TaskRun" \
      "$(jq '[.status.results[]? | select(.name == "BASE_ARTIFACT_INPUTS")] | length' "$T/$pr-prefetch.tr.json")" 0
  else
    attendu "prefetch (bootstrap) : BASE_ARTIFACT_INPUTS (clés triées)" \
      "$(jq -cS '.status.results[] | select(.name == "BASE_ARTIFACT_INPUTS") | .value' "$T/$pr-prefetch.tr.json")" "$BASE_b"
  fi
  attendu "construire : témoins réseau en échec" "$(lignes '^témoin .* : échec, code [0-9]* (attendu)$' "$cf")" 3
  attendu "construire : entrées en lecture seule" "$(lignes '^invité : .*, écriture refusée$' "$cf")" 1
  attendu "construire : racine conforme à la valeur fixée par la pipeline" "$(lignes '^racine conforme à la valeur fixée par la pipeline$' "$cf")" 1
  mesure "construire : racine (sha256)" "$(sed -n 's/^racine : [0-9]* octets, [0-9]* membres, sha256 \([0-9a-f]\{64\}\)$/\1/p' "$cf")" "$(v CIBLE "$x")"
  mesure "construire : manifeste" "$(sed -n 's/^couches : .* ; manifeste \(sha256:[0-9a-f]\{64\}\) .*/\1/p' "$cf")" "$(v DIGEST "$x")"
  u=$(jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value' "$T/pr-$pr-etat.json")
  d=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$T/pr-$pr-etat.json")
  echo "$d" > "$T/$pr.digest"
  attendu "dépôt publié" "$u" "$(v IMAGE "$x")"
  attendu "construire : DIGEST_CONSTRUIT égal au digest publié" \
    "$(jq -r '.status.results[] | select(.name == "DIGEST_CONSTRUIT") | .value' "$T/$pr-construire.tr.json")" "$d"
  attendu "publier : ligne de publication" "$(lignes "^publiée : $(v IMAGE "$x")@$d (relue en lecture anonyme)$" "$T/$pr-publier-step-publier.log")" 1
  attendu "manifeste relu dans Zot (lecture anonyme) : digest du descripteur, couches" \
    "$(descripteur "$(v IMAGE "$x")@$d") $(oras manifest fetch --ca-file "$P/ca-poc.crt" "${u/$REG/$REG_HOTE}@$d" < /dev/null | jq '.layers | length')" "$d $(v COUCHES "$x")"
  mesure "digest publié égal au banc et aux essais (m1bt3 et mesure d'un autre jour)" "$d" "$(v DIGEST "$x")"
  attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
}

etape_pipeline() { # quatre PipelineRuns, deux par image ; gardes avant la première création ; rien n'est purgé
  local x i pr l s
  gardes_mesure
  gardes_pipelines
  echo "## politiques de builds (lecture seule)"
  politiques_m1b
  echo "## PipelineRuns absents, avant toute création"
  for x in o b; do for i in 1 2; do
    pr=$N-$x-$i
    [ -z "$(kubectl get pipelinerun -n builds --field-selector "metadata.name=$pr" -o name < /dev/null 2> /dev/null)" ] \
      && echo "OK   $pr absent" || echec "$pr existe déjà : rien n'est purgé, relancer sous un autre PREFIXE"
  done; done
  echo "relevé : / de sc-build : $(sur sc-build 'df -B1 --output=avail / | tail -n 1' < /dev/null 2> /dev/null | tr -d ' ' || echo illisible) octets libres (PVC local-path)"
  for x in o b; do
    for i in 1 2; do
      pr=$N-$x-$i
      echo "## $pr ($(v NOM "$x"))"
      if [ "$i" = 1 ]; then
        s=$(oras repo tags --ca-file "$P/ca-poc.crt" "$(v IMAGE $x | sed "s#^$REG#$REG_HOTE#")" < /dev/null 2>&1 || true)
        attendu "dépôt $(v IMAGE "$x") absent avant le premier PipelineRun" "$(grep -c 'name unknown' <<< "$s")" 1
      fi
      l=$(libre_zot)
      echo "/ de sc-stockage : $l octets libres à $(date -u +%H:%M:%S) (garde : $LIBRE_MIN + $(v TAILLE "$x"))"
      if ! [[ $l =~ ^[0-9]+$ ]] || [ "$l" -lt $((LIBRE_MIN + $(v TAILLE "$x"))) ]; then echec "espace libre illisible ou sous la garde sur sc-stockage"; fi
      pr_json "$pr" "$(v NOM "$x")" "$(v REF "$x")"
      attendu "$pr : podTemplate commun sans env ; Kata pour construire seule ; aucun paramètre" \
        "$(jq -c '[(.spec.taskRunTemplate.podTemplate | has("env")), [.spec.taskRunSpecs[] | .pipelineTaskName + ":" + (.podTemplate.runtimeClassName // "")], (.spec | has("params"))]' "$T/pr-$pr.json")" \
        '[false,["construire:kata"],false]'
      attendu "$pr admis en dry-run serveur (ni résolveur, ni signatures, ni pods) : code de kubectl" "$(admission "$T/pr-$pr.json")" 0
      kubectl create -f "$T/pr-$pr.json" < /dev/null > /dev/null
      echo "$pr créé à $(date -u +%H:%M:%S) ($(v REF "$x"))"
      controler_pr "$pr" "$x"
      echo "/ de sc-stockage : $(libre_zot) octets libres à $(date -u +%H:%M:%S)"
    done
    mesure "$(v NOM "$x") : deux exécutions, même digest" "$(cat "$T/$N-$x-2.digest")" "$(cat "$T/$N-$x-1.digest")"
  done
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then lancer m1b-pipeline "05 M1b pipeline" "$@"; fi
