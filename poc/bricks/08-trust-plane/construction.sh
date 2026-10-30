#!/usr/bin/env bash
# Brique 08, jalon J7 : construction de sample-app dans un PipelineRun, par la voie A (décision du propriétaire du 30/10/2026 :
# BuildKit en root dans un pod Kata privilégié), avec une tâche de push séparée et le compte Zot poc-images (choix et accord
# du propriétaire du 30/10/2026), web/dist tiré de Zot (choix du propriétaire : Node reste hors de la chaîne, comme en brique 04).
#   compte      compte poc-images (stockage.sh zot ; condition CEL de stockage/zot.json) : création par digest dans builds/**
#               acceptée, deux fois ; manifeste par tag, tag .att, digest avec ?tag=, dépôt hors de builds/ et suppression
#               refusés ; secret zot-images et ConfigMap ca-poc (CA publique du PoC) dans builds
#   entrees     fermeture Hermeto (closure.sh de la brique 03) et web/dist (sortie de la brique 03), arbres épinglés de voie-d.sh,
#               poussés dans Zot par poc-ecriture, deux fois : même digest ; relus en lecture anonyme : mêmes contenus
#   taches      construire-image (pod Kata privilégié, BuildKit v0.34.1 en root, état sur tmpfs) et publier-image (pod runc
#               restreint, poc-images) rendues, signées par tkn, comparées à leur signature versionnée (SIGNER=1 pour la refaire),
#               digests exigés dans la liste revue ; pipeline sample-app signée, entrées hors dépôt fixées par digest ; bundles
#   constat_cm  sous Kata 4.3.1, deux conteneurs d'un pod montent la même ConfigMap : quand le premier se termine, le second ne la
#               lit plus (lien ca.crt orphelin) ; témoin : premier conteneur encore en vie ; un emptyDir sur disque survit.
#               D'où la CA montée dans la seule première étape de construire-image, qui la recopie (premier passage en échec)
#   construire  PipelineRun du gabarit en service (pipeline remplacée, commit de main, workspace PVC, runtimeClassName kata pour
#               la seule tâche construire) : image attendue 3a7ca1b1, poussée par poc-images, signée par Chains ; taille de
#               l'invité ; même PipelineRun sans runtimeClassName : pod de construction refusé, rien de poussé
#   provenance  provenance du PipelineRun vérifiée par cosign (clé de Chains ; autre clé refusée) ; sujet, buildType,
#               resolvedDependencies (commit, fermeture, web/dist, image de build, images d'étape, pipeline, tâches) ;
#               runtimeClassName kata dans la spec signée
# Retrait : dépôts Zot entrees/sample-app/*, builds/sample-app, builds/essai-images, tekton/tasks/construire-image,
# tekton/tasks/publier-image, tekton/pipelines/sample-app (Zot n'autorise pas la suppression) ; secret zot-images et ConfigMap
# ca-poc de builds ; compte poc-images (stockage/zot.json, stockage.sh zot).
#
# Usage (racine du dépôt) : mise run confiance:construction -- <étape>…   (journal : resultats/construction-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
B03=${B03:-$HOME/.cache/supply-chain-poc/w/b03}                                   # entrées de la brique 03 (bancs du laptop)
APP_LAYOUT=${APP_LAYOUT:-$HOME/.cache/supply-chain-poc/w/b04/app-layout}          # image sample-app de la brique 04
APP_REF=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # sample-app par BuildKit (brique 04, voie A)
BIN_REF=e3749c68b6babe6d91a0d8af35aa9bddfe42f09dedafa6877d5ce702c5a69f11          # binaire de la brique 03
ARBRE_DIST=f6e8170f1a1a04b589d7a30e07c1effb99973bb6625c4457df435c3c1710910a        # voie-d.sh
ARBRE_DEPS=51ccd0964bea8a2065dfda803dad14b5c6246ad712c55bbccc1005c54cd7b10b        # voie-d.sh
DEPOT_FERMETURE=entrees/sample-app/fermeture
DEPOT_WEB_DIST=entrees/sample-app/web-dist
# Manifestes déterministes (un fichier par couche, date fixe) : relevés au premier passage (30/10/2026), puis épinglés
FERMETURE_DIGEST=sha256:0ab5a50767bee2e430cdd2db6b4d61580629f89fd48fb352cd1a2a545ee56048
WEB_DIST_DIGEST=sha256:47f72275aa786c3c2d4393d7601e118fb2b1a17d928dca477f6dac89eb852bcb
TYPE_WEB_DIST=application/vnd.supply-chain.web-dist.v1
BUILDKIT=$REG/amont/moby/buildkit@sha256:ace6811c21334fa502644b9711e0ea48e8539c5c2a843c2325dfb7b987ab260b          # buildkit.sh image
BUILDER=$REG/plateforme/builder-go-voie-d@sha256:d50ae57551c381b591540643fdfee12dd251ae16675c3c69fde221f8e9c28b67  # voie-d.sh image
DOCKERFILE=$repo/poc/bricks/04-hermetic-repro/Dockerfile
IMAGE=$REG/builds/sample-app
SAMPLE_APP=workspace/sample-app
TETE_J2=6391fd437f26696847041be3226bbbf633f55a2f    # stockage.sh depot ; main y est remise après les essais de J6
ARBRE_J2=30e808ffa327288c656ddda7b6fafe4005234b77   # arbre git de ce commit (= poc/sample-app à HEAD lors de J2)
PR=j7-sample-app
T=$W/construction
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth/docker")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets, même en cas d'échec

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }

contenu() { # répertoire : empreinte des seuls chemins et contenus des fichiers (oras ne restitue ni modes ni répertoires vides)
  (cd "$1" && find . -type f -printf '%P\n' | sort | while read -r f; do echo "$f $(sha256sum < "$f" | cut -c1-64)"; done) | sha256sum | cut -c1-64
}

etape_compte() {
  local mt code
  echo "## prédiction (condition CEL lue dans le code de Zot v2.1.22 : pkg/api/authz.go, manifestWriteAuthzChecks)"
  echo "poc-images : blobs et manifeste par digest dans builds/ acceptés, deux fois (une référence par digest sans tag demande la"
  echo "  création, pas la mise à jour) ; refus 403 : manifeste par tag, tag sha256-….att, digest avec ?tag= (motif de la condition"
  echo "  dans la réponse), dépôt hors de builds/ et suppression (aucune politique)"
  auth_zot "$T/auth/images.json" "" poc-images
  (umask 077 && printf 'Authorization: Basic %s\n' "$(printf 'poc-images:%s' "$(cat "$S/zot-poc-images.password")" | base64 -w0)" > "$T/auth/entete")
  oras manifest fetch --oci-layout "$APP_LAYOUT@$APP_REF" > "$T/manifeste.json"
  mt=$(jq -r .mediaType "$T/manifeste.json")
  put() { # chemin [méthode] : code HTTP d'une écriture du manifeste par poc-images ; corps dans $T/put.out
    curl -s -o "$T/put.out" -w '%{http_code}' --cacert "$P/ca-poc.crt" -H @"$T/auth/entete" -H "Content-Type: $mt" \
      -X "${2:-PUT}" --data-binary @"$T/manifeste.json" "https://$REG_HOTE/v2/$1"
  }
  echo "## écritures de poc-images (image sample-app de la brique 04, $APP_REF)"
  for i in 1 2; do
    oras cp --from-oci-layout "$APP_LAYOUT@$APP_REF" "$REG_HOTE/builds/essai-images@$APP_REF" --to-ca-file "$P/ca-poc.crt" \
      --to-registry-config "$T/auth/images.json" > /dev/null
    echo "OK   push par digest n° $i (oras cp, blobs et manifeste) : builds/essai-images@$APP_REF"
  done
  attendu "PUT du manifeste par digest (curl)" "$(put "builds/essai-images/manifests/$APP_REF")" 201
  for c in "manifests/essai|tag essai" "manifests/sha256-${APP_REF#sha256:}.att|tag .att" "manifests/$APP_REF?tag=essai|digest avec ?tag=essai"; do
    code=$(put "builds/essai-images/${c%%|*}")
    [ "$code" = 403 ] && grep -qF 'écriture par digest seulement' "$T/put.out" \
      && echo "OK   ${c#*|} : refusé (403, $(jq -r '.errors[0].detail.reason // .errors[0].message' "$T/put.out"))" \
      || { echo "KO   ${c#*|} : HTTP $code $(cat "$T/put.out")" >&2; exit 1; }
  done
  attendu "dépôt hors de builds/ (workspace/essai-images)" "$(put "workspace/essai-images/manifests/$APP_REF")" 403
  attendu "suppression du manifeste" "$(put "builds/essai-images/manifests/$APP_REF" DELETE)" 403
  echo "## audit de Zot (écritures de poc-images)"
  sur sc-stockage "sudo cat /var/log/zot/audit.log" | jq -c 'select(.subject == "poc-images" and (.object | test("/manifests/")))
    | {t: .time[11:19], action, objet: (.object | sub("^/v2/"; "") | sub("sha256[-:](?<d>.{12})[0-9a-f]*"; "sha256…\(.d)")), code: .status}' | tail -7
  echo "## objets de builds : secret zot-images (poc-images, $REG) et ConfigMap ca-poc"
  auth_zot "$T/auth/images-reg.json" "" poc-images "$REG"
  kubectl create secret generic zot-images -n builds --from-file=config.json="$T/auth/images-reg.json" --dry-run=client -o yaml \
    | kubectl apply --server-side -f - > /dev/null
  kubectl create configmap ca-poc -n builds --from-file=ca.crt="$P/ca-poc.crt" --dry-run=client -o yaml | kubectl apply --server-side -f - > /dev/null
  kubectl get secret,configmap -n builds -o json | jq -r '.items[] | select(.metadata.name == "zot-images" or .metadata.name == "ca-poc")
    | "\(.kind) \(.metadata.name) : clés \(.data | keys | join(","))"'
  echo "secret zot-images appliqué depuis un fichier 0600 (entrée standard de kubectl, sans annotation last-applied)"
}

pousser_web_dist() { # répertoire dépôt:tag : un fichier par couche, comme closure.sh, manifeste déterministe ; référence par digest
  local d=$1 ref=$2 f fichiers=()
  while IFS= read -r f; do fichiers+=("$f:$TYPE_WEB_DIST.file"); done < <(cd "$d" && find . -type f -printf '%P\n' | sort)
  (cd "$d" && oras push --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json" --no-tty --format go-template='{{.digest}}' \
    --artifact-type "$TYPE_WEB_DIST" --annotation "org.opencontainers.image.created=1970-01-01T00:00:00Z" "$ref" "${fichiers[@]}" \
    | sed "s#^#${ref%:*}@#")
}

etape_entrees() {
  local f1 f2 w1 w2 r
  echo "## prédiction"
  echo "arbres de la brique 03 : fermeture $ARBRE_DEPS, web/dist $ARBRE_DIST (voie-d.sh) ; deux poussées de chacun : même digest"
  echo "  (manifeste sans date, un fichier par couche) ; relus en lecture anonyme : mêmes chemins et contenus"
  attendu "arbre de la fermeture (canon/deps de la brique 03)" "$(arbre "$B03/canon/deps")" "$ARBRE_DEPS"
  attendu "arbre de web/dist (build-apres de la brique 03)" "$(arbre "$B03/build-apres/web/dist")" "$ARBRE_DIST"
  auth_zot "$T/auth/docker/config.json"
  export ORAS_OPTS="--ca-file $P/ca-poc.crt --registry-config $T/auth/docker/config.json"
  f1=$("$repo/poc/bricks/03-deps-closure/closure.sh" push "$B03/canon/deps" "$REG_HOTE/$DEPOT_FERMETURE:b03")
  f2=$("$repo/poc/bricks/03-deps-closure/closure.sh" push "$B03/canon/deps" "$REG_HOTE/$DEPOT_FERMETURE:b03")
  attendu "fermeture poussée deux fois (closure.sh)" "$f2" "$f1"
  w1=$(pousser_web_dist "$B03/build-apres/web/dist" "$REG_HOTE/$DEPOT_WEB_DIST:b03")
  w2=$(pousser_web_dist "$B03/build-apres/web/dist" "$REG_HOTE/$DEPOT_WEB_DIST:b03")
  attendu "web/dist poussé deux fois" "$w2" "$w1"
  for r in "$f1 $B03/canon/deps fermeture" "$w1 $B03/build-apres/web/dist web-dist"; do
    set -- $r
    rm -rf -- "${T:?}/relu-$3" && mkdir -p "$T/relu-$3"
    oras pull --no-tty --ca-file "$P/ca-poc.crt" -o "$T/relu-$3" "$1" > /dev/null
    attendu "$3 relu(e) en lecture anonyme : chemins et contenus" "$(contenu "$T/relu-$3")" "$(contenu "$2")"
    oras manifest fetch --ca-file "$P/ca-poc.crt" "$1" | jq -r '"\(.artifactType), \(.layers | length) couche(s), \([.layers[].size] | add) octets"'
  done
  [ -n "$FERMETURE_DIGEST" ] && attendu "fermeture (digest épinglé)" "${f1#*@}" "$FERMETURE_DIGEST" || echo "À ÉPINGLER : FERMETURE_DIGEST=${f1#*@}"
  [ -n "$WEB_DIST_DIGEST" ] && attendu "web/dist (digest épinglé)" "${w1#*@}" "$WEB_DIST_DIGEST" || echo "À ÉPINGLER : WEB_DIST_DIGEST=${w1#*@}"
}

signer_tache() { # nom : tâche rendue $T/<nom>.yaml signée, comparée à sa signature versionnée (SIGNER=1 : la remplace), publiée en
  # bundle ; référence dans $T/<nom>.ref, exigée dans la liste revue
  local n=$1 v=$here/politique/taches/$1.signee.yaml r
  tkn task sign "$T/$n.yaml" -K "$S/taches.key" -f "$T/$n-signee.yaml" > /dev/null
  if [ -n "${SIGNER:-}" ]; then cp "$T/$n-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans politique/taches/$n.signee.yaml (liste revue à mettre à jour)"; fi
  [ -s "$v" ] || { echo "KO   signature versionnée absente : SIGNER=1, puis revue de politique/porte/taches.yml" >&2; exit 1; }
  cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") \
    && echo "OK   $n : signature versionnée conforme au gabarit rendu, signature exceptée" \
    || { echo "KO   $n : gabarit modifié depuis la signature versionnée (SIGNER=1, puis revue de la liste)" >&2; exit 1; }
  r=$REG/tekton/tasks/$n@$(bundle "$v" "tekton/tasks/$n" j7)
  echo "$r" > "$T/$n.ref"
  if listee "$r"; then echo "OK   $n dans la liste revue : $r"
  elif [ -n "${SIGNER:-}" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml après revue, puis relancer sans SIGNER : $r"
  else echo "KO   $n absente de la liste revue politique/porte/taches.yml : $r" >&2; exit 1; fi
}

etape_taches() {
  local s p
  [ -n "$FERMETURE_DIGEST" ] && [ -n "$WEB_DIST_DIGEST" ] || { echo "KO   digests des entrées non épinglés (étape entrees)" >&2; exit 1; }
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente (politique.sh taches)" >&2; exit 1; }
  auth_zot "$T/auth/docker/config.json"
  s=$(sha256sum < "$DOCKERFILE" | cut -c1-64)
  echo "## tâches (tkn $(tkn version --component client)) ; Dockerfile de la brique 04 : $s"
  awk -v f="$DOCKERFILE" '$1 == "@DOCKERFILE@" && NF == 1 { match($0, /^ */); i = substr($0, 1, RLENGTH)
      while ((getline l < f) > 0) print (l == "" ? "" : i l); next } { print }' "$here/politique/taches/construire-image.yaml" \
    | sed -e "s#@BUILDKIT@#$BUILDKIT#g" -e "s#@OUTILS@#$REG/$OUTILS@$OUTILS_DIGEST#g" -e "s#@BUILDER@#$BUILDER#g" -e "s#@DOCKERFILE_SHA@#$s#g" \
    > "$T/construire-image.yaml"
  sed -e "s#@OUTILS@#$REG/$OUTILS@$OUTILS_DIGEST#g" "$here/politique/taches/publier-image.yaml" > "$T/publier-image.yaml"
  for p in construire-image publier-image; do
    ! grep -n '@[A-Z_]*@' "$T/$p.yaml" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans $p" >&2; exit 1; }
    signer_tache "$p"
  done
  echo "## pipeline sample-app (signée à chaque passage ; ses tâches et ses entrées hors dépôt sont épinglées par digest)"
  sed -e "s#@CONSTRUIRE@#$(cat "$T/construire-image.ref")#" -e "s#@PUBLIER@#$(cat "$T/publier-image.ref")#" \
    -e "s#@FERMETURE@#$REG/$DEPOT_FERMETURE@$FERMETURE_DIGEST#" -e "s#@WEB_DIST@#$REG/$DEPOT_WEB_DIST@$WEB_DIST_DIGEST#" \
    -e "s#@IMAGE@#$IMAGE#" "$here/politique/taches/sample-app.yaml" > "$T/sample-app.yaml"
  tkn pipeline sign "$T/sample-app.yaml" -K "$S/taches.key" -f "$T/sample-app-signee.yaml" > /dev/null
  echo "$REG/tekton/pipelines/sample-app@$(bundle "$T/sample-app-signee.yaml" tekton/pipelines/sample-app j7)" | tee "$T/pipeline.ref"
}

etape_constat_cm() {
  local cas n c a
  echo "## prédiction (relevée sur le premier passage de construire, puis sur un essai exploratoire du 30/10/2026)"
  echo "pod Kata, conteneurs a et b montant la ConfigMap ca-poc et un emptyDir ; a lit la CA, écrit dans l'emptyDir, puis :"
  echo "  sort aussitôt : b, 15 s plus tard, lit l'emptyDir mais plus la CA (No such file or directory) ;"
  echo "  reste en vie (témoin) : b lit l'emptyDir et la CA"
  for cas in "sort|echo écrit > /d/f" "vivant|echo écrit > /d/f; sleep 40"; do
    n=j7-cm-${cas%%|*}
    a="head -c 27 /etc/ca-poc/ca.crt; echo; ${cas#*|}"
    jq -n --arg n "$n" --arg i "$REG/$OUTILS@$OUTILS_DIGEST" --arg a "$a" '{apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds"},
      spec: {runtimeClassName: "kata", restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false,
        securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
        volumes: [{name: "ca", configMap: {name: "ca-poc"}}, {name: "d", emptyDir: {}}],
        containers: [["a", $a], ["b", "sleep 15; echo \"emptyDir : $(cat /d/f 2>&1)\"; echo \"ca.crt : $(head -c 27 /etc/ca-poc/ca.crt 2>&1)\""]]
          | map({name: .[0], image: $i, command: ["/busybox/sh", "-c", .[1]],
              securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
              volumeMounts: [{name: "ca", mountPath: "/etc/ca-poc", readOnly: true}, {name: "d", mountPath: "/d"}]})}}' > "$T/$n.json"
    kubectl delete pod -n builds "$n" --ignore-not-found --wait=true > /dev/null
    kubectl create -f "$T/$n.json" > /dev/null
  done
  for n in j7-cm-sort j7-cm-vivant; do
    kubectl wait -n builds "pod/$n" --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s > /dev/null \
      || { kubectl describe pod -n builds "$n" >&2; echo "KO   pod $n non terminé" >&2; exit 1; }
    echo "### $n"
    for c in a b; do kubectl logs -n builds "$n" -c "$c" > "$T/$n-$c.log" 2>&1; sed "s/^/     $c : /" "$T/$n-$c.log"; done
    kubectl delete pod -n builds "$n" --wait=false > /dev/null
  done
  attendu "a sorti : b lit l'emptyDir, puis la CA" "$(sed -n 's/^emptyDir : //p' "$T/j7-cm-sort-b.log") / $(sed -n 's/^ca.crt : //p' "$T/j7-cm-sort-b.log")" \
    "écrit / head: /etc/ca-poc/ca.crt: No such file or directory"
  attendu "a en vie (témoin) : b lit l'emptyDir, puis la CA" "$(sed -n 's/^emptyDir : //p' "$T/j7-cm-vivant-b.log") / $(sed -n 's/^ca.crt : //p' "$T/j7-cm-vivant-b.log")" \
    "écrit / -----BEGIN CERTIFICATE-----"
  echo "CONSTAT sous Kata 4.3.1 (runtime-rs), la copie d'une ConfigMap dans l'invité disparaît pour tout le pod dès qu'un conteneur"
  echo "        qui la monte se termine ; les étapes de Tekton se terminent l'une après l'autre : une ConfigMap ou un secret partagé"
  echo "        entre étapes n'est lisible que par la première. Non trouvé dans les issues de kata-containers (recherche du 30/10/2026)"
}

pr_j7() { # nom kata|- : PipelineRun du gabarit en service dans declencheurs (pipeline sample-app, commit de main, workspace sortie
  # en PVC ; avec kata, runtimeClassName pour la seule tâche construire, gabarit de pod du PipelineRun recopié) ; $T/pr-<nom>.json
  kubectl get triggertemplate -n declencheurs sample-app -o json | jq --arg n "$1" --arg b "$(cat "$T/pipeline.ref")" --arg c "$TETE_J2" \
    --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" --arg k "$2" '.spec.resourcetemplates[0] | .metadata.name = $n
      | .spec.pipelineRef.params |= map(if .name == "bundle" then .value = $b elif .name == "name" then .value = "sample-app" else . end)
      | .spec.params |= map(if .name == "commit" then .value = $c elif .name == "depot" then .value = $u else . end)
      | .spec.workspaces = [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "1Gi"}}}}}]
      | if $k == "kata" then .spec.taskRunSpecs = [{pipelineTaskName: "construire",
          podTemplate: (.spec.taskRunTemplate.podTemplate + {runtimeClassName: "kata"})}] else . end' > "$T/pr-$1.json"
}

fin_pr() { # nom [secondes] : attend la fin d'un PipelineRun de builds ; « statut|raison|message »
  local st=""
  for _ in $(seq "${2:-600}"); do
    st=$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}')
    [ -n "$st" ] && [ "$st" != Unknown ] && break
    sleep 1
  done
  kubectl get pipelinerun -n builds "$1" -o json | jq -r '.status.conditions[] | select(.type == "Succeeded") | "\(.status)|\(.reason)|\(.message | gsub("\n"; " ") | .[0:300])"'
}

journaux_pr() { # nom : sortie de chaque étape de chaque TaskRun du PipelineRun, archivée dans $T et affichée
  local tr p c
  for tr in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$1" -o jsonpath='{.items[*].metadata.name}'); do
    p=$(kubectl get taskrun -n builds "$tr" -o jsonpath='{.status.podName}')
    echo "### TaskRun $tr ($(kubectl get taskrun -n builds "$tr" -o jsonpath='{.status.conditions[0].reason}'), pod ${p:--})"
    [ -n "$p" ] || continue
    for c in $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null); do
      kubectl logs -n builds "$p" -c "$c" > "$T/$tr-$c.log" 2>&1 || true
      sed "s/^/     $c : /" "$T/$tr-$c.log"
    done
  done
}

etape_construire() {
  local r q cons pub aa n t0
  [ -s "$T/pipeline.ref" ] || { echo "KO   pipeline non publiée (étape taches)" >&2; exit 1; }
  echo "## prédiction"
  echo "PipelineRun $PR (gabarit de declencheurs, commit $TETE_J2) : réussi ; Trusted Resources vérifie la pipeline et les deux tâches"
  echo "  pod affinity assistant admis (contexte du gabarit, compte build sans jeton) ; PVC local-path sur sc-build"
  echo "  construire : pod Kata sur sc-build, QEMU -smp 3 -m 6176M (limites 2 CPU et 6 Gi de la seule étape construire) ; arbre"
  echo "    $ARBRE_J2 ; fermeture et web/dist tirés ; image $APP_REF (binaire $BIN_REF : l'écart web/package*.json du dépôt"
  echo "    ne touche pas l'image, qui ne contient que le binaire)"
  echo "  publier : pod runc conforme à restricted ; push par poc-images (HTTP 201 dans l'audit de Zot), .sig et .att par poc-build"
  echo "  Chains signe les deux TaskRuns et le PipelineRun"
  echo "même PipelineRun sans runtimeClassName : construire refusé à la création du pod (Pod Security restricted : privileged),"
  echo "  publier jamais lancé, aucune écriture de poc-images"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  pr_j7 "$PR" kata
  purger_pr "$PR"
  kubectl create -f "$T/pr-$PR.json" > /dev/null
  echo "## $PR créé ($(jq -c '.spec.taskRunSpecs' "$T/pr-$PR.json"))"
  cons=""
  for _ in $(seq 300); do
    cons=$(kubectl get pods -n builds -l "tekton.dev/pipelineRun=$PR,tekton.dev/pipelineTask=construire" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    [ -n "$cons" ] && [ "$(kubectl get pod -n builds "$cons" -o jsonpath='{.status.phase}')" = Running ] && break
    sleep 1
  done
  [ -n "$cons" ] || { kubectl get pipelinerun,taskrun -n builds -l "tekton.dev/pipelineRun=$PR" >&2; echo "KO   pod construire absent" >&2; exit 1; }
  q=$(sur sc-build "sudo k3s crictl pods --namespace builds --name $cons -q" | sed -n 1p)
  sur sc-build "pgrep -af 'qemu-system.*sandbox-$q'" > "$T/qemu.txt" || true
  echo "processus QEMU du sandbox de $cons : $(wc -l < "$T/qemu.txt")"
  aa=$(kubectl get pods -n builds -l app.kubernetes.io/component=affinity-assistant -o json | jq -r '.items[] | "\(.metadata.name) sur \(.spec.nodeName), phase \(.status.phase)"')
  echo "affinity assistant : ${aa:-aucun}"
  r=$(fin_pr "$PR")
  journaux_pr "$PR"
  echo "## mesures"
  attendu "PipelineRun $PR" "${r%%|*}|$(cut -d'|' -f2 <<< "$r")" "True|Succeeded"
  attendu "kata : QEMU" "$(for f in -smp -m; do printf '%s %s ' "$f" "$(tr ' ' '\n' < "$T/qemu.txt" | grep -A1 -x -m1 -- "$f" | tail -1 | cut -d, -f1)"; done | sed 's/ $//')" "-smp 3 -m 6176M"
  kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$PR" -o json | jq -r '.items[] | "TaskRun \(.metadata.labels["tekton.dev/pipelineTask"]) : TrustedResourcesVerified=\(.status.conditions[] | select(.type == "TrustedResourcesVerified") | .status // "-"), pod \(.status.podName)"'
  kubectl get pipelinerun -n builds "$PR" -o json | jq -r '"PipelineRun : TrustedResourcesVerified=\(.status.conditions[] | select(.type == "TrustedResourcesVerified") | .status // "-") ; résultats \(.status.results | map(.name + "=" + .value) | join(", "))"'
  kubectl get pods -n builds -l "tekton.dev/pipelineRun=$PR" -o json | jq -r '.items[] | "pod \(.metadata.labels["tekton.dev/pipelineTask"]) : nœud \(.spec.nodeName), runtimeClassName \(.spec.runtimeClassName // "-"), étapes \([.spec.containers[] | "\(.name)=\(if .securityContext.privileged then "privilégiée" else "uid \(.securityContext.runAsUser // "pod")" end)"] | join(" "))"'
  pub=$(kubectl get pipelinerun -n builds "$PR" -o json | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
  attendu "image de sample-app construite dans le PipelineRun (voie A, BuildKit v0.34.1 sous Kata)" "$pub" "$APP_REF"
  attendu "arbre du commit (dépôt Forgejo)" "$(sed -n 's/.*arbre \([0-9a-f]\{40\}\).*/\1/p' "$T"/"$PR"-construire-step-sources.log)" "$ARBRE_J2"
  echo "## Chains"
  for r in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$PR" -o jsonpath='{.items[*].metadata.name}'); do
    echo "TaskRun $r signé=$(signe taskrun "$r")"
  done
  attendu "PipelineRun $PR signé par Chains" "$(signe pipelinerun "$PR")" true
  echo "## audit de Zot : écritures de manifestes de builds/sample-app depuis $t0"
  sur sc-stockage "sudo cat /var/log/zot/audit.log" | jq -c --arg t "$t0" 'select(.time[0:19] >= ($t[0:19]) and (.object | test("^/v2/builds/sample-app/manifests/"))
    and .action != "GET" and .action != "HEAD") | {t: .time[11:19], compte: .subject, action, objet: (.object | sub("^/v2/builds/sample-app/manifests/"; "")
    | sub("sha256[-:](?<d>.{12})[0-9a-f]*"; "sha256…\(.d)")), code: .status}' | tee "$T/zot-audit.json"
  n=$(jq -s '[.[] | select(.compte == "poc-images" and .code == 201)] | length' "$T/zot-audit.json")
  [ "$n" -ge 1 ] && echo "OK   image poussée par poc-images ($n écriture(s) par digest)" || { echo "KO   aucune écriture de poc-images" >&2; exit 1; }
  echo "## même PipelineRun sans runtimeClassName"
  pr_j7 "$PR-sans-kata" -
  purger_pr "$PR-sans-kata"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  kubectl create -f "$T/pr-$PR-sans-kata.json" > /dev/null
  r=$(fin_pr "$PR-sans-kata" 300)
  echo "PipelineRun $PR-sans-kata : $r"
  kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$PR-sans-kata" -o json | jq -r '.items[] | "TaskRun \(.metadata.labels["tekton.dev/pipelineTask"]) : \(.status.conditions[0].reason) : \(.status.conditions[0].message | .[0:300])"' | tee "$T/sans-kata.txt"
  [ "${r%%|*}" = False ] && grep -q 'violates PodSecurity "restricted:latest": privileged' "$T/sans-kata.txt" \
    && echo "OK   pod de construction refusé hors Kata (Pod Security restricted de builds)" || { echo "KO   refus attendu" >&2; exit 1; }
  attendu "TaskRun publier du PipelineRun sans Kata" "$(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$PR-sans-kata,tekton.dev/pipelineTask=publier" -o name | wc -l)" 0
  n=$(sur sc-stockage "sudo cat /var/log/zot/audit.log" | jq -c --arg t "$t0" 'select(.time[0:19] >= ($t[0:19]) and .subject == "poc-images")' | wc -l)
  attendu "écritures de poc-images depuis $t0" "$n" 0
}

etape_provenance() {
  local uid
  uid=$(kubectl get pipelinerun -n builds "$PR" -o jsonpath='{.metadata.uid}')
  echo "## prédiction"
  echo "cosign (clé de Chains) : enveloppes valides sur $IMAGE@$APP_REF, dont celle du PipelineRun $PR (invocationId $uid) ;"
  echo "  buildType slsa-tekton ; sujet $IMAGE ; resolvedDependencies : pipeline et deux tâches (bundles), images d'étape (BuildKit,"
  echo "  outils), git+https://…/$SAMPLE_APP.git@sha1:$TETE_J2, fermeture, web/dist et image de build par digest ;"
  echo "  runtimeClassName kata dans les paramètres externes (taskRunSpecs) et dans le TaskRun construire ; autre clé refusée"
  cosign verify-attestation --key "$R/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" \
    "$REG_HOTE/builds/sample-app@$APP_REF" > "$T/att.json" 2> "$T/cosign.err" || { cat "$T/cosign.err" >&2; exit 1; }
  echo "OK   cosign verify-attestation : $(wc -l < "$T/att.json") enveloppe(s) valide(s) sur builds/sample-app@$APP_REF"
  jq -c --arg u "$uid" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$T/att.json" > "$T/prov.json"
  attendu "enveloppes du PipelineRun $PR" "$(wc -l < "$T/prov.json")" 1
  jq -r '"sujet : \(.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(", "))", "buildType : \(.predicate.buildDefinition.buildType)",
    "builder : \(.predicate.runDetails.builder.id)", "paramètres externes : \(.predicate.buildDefinition.externalParameters.runSpec.params | map(.name + "=" + .value) | join(", "))",
    "taskRunSpecs : \(.predicate.buildDefinition.externalParameters.runSpec.taskRunSpecs | tostring)",
    "resolvedDependencies :", (.predicate.buildDefinition.resolvedDependencies[] | "  \(.name // "-") \(.uri // "-") \(.digest // {} | to_entries | map(.key + ":" + .value) | join(","))\(if .content then " (contenu)" else "" end)")' "$T/prov.json"
  attendu "sujet" "$(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$T/prov.json")" "$IMAGE@$APP_REF"
  attendu "buildType" "$(jq -r .predicate.buildDefinition.buildType "$T/prov.json")" https://tekton.dev/chains/v2/slsa-tekton
  attendu "source" "$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == "git+https://sc-stockage.poc.test:3000/'"$SAMPLE_APP"'.git") | "sha1:" + .digest.sha1' "$T/prov.json")" "sha1:$TETE_J2"
  attendu "fermeture" "$(jq -r --arg u "oci://$REG/$DEPOT_FERMETURE" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json")" "$FERMETURE_DIGEST"
  attendu "web/dist" "$(jq -r --arg u "oci://$REG/$DEPOT_WEB_DIST" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json")" "$WEB_DIST_DIGEST"
  attendu "image de build" "$(jq -r --arg u "oci://${BUILDER%@*}" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json")" "${BUILDER#*@}"
  attendu "runtimeClassName de construire (paramètres externes)" \
    "$(jq -r '.predicate.buildDefinition.externalParameters.runSpec.taskRunSpecs[] | select(.pipelineTaskName == "construire") | .podTemplate.runtimeClassName' "$T/prov.json")" kata
  attendu "runtimeClassName du TaskRun construire (contenu signé de resolvedDependencies)" "$(jq -r '.predicate.buildDefinition.resolvedDependencies[]
    | select(.name == "pipelineTask" and .content) | .content | @base64d | fromjson | select(.metadata.labels["tekton.dev/pipelineTask"] == "construire")
    | .spec.podTemplate.runtimeClassName // "-"' "$T/prov.json")" kata
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$T/autre.pub" 2> /dev/null
  refus "provenance vérifiée avec une autre clé" "no matching attestations|invalid signature|signature" \
    cosign verify-attestation --key "$T/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/sample-app@$APP_REF"
}

lancer construction J7 "$@"
