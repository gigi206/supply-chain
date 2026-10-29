#!/usr/bin/env bash
# Brique 08, jalon J4 : Tekton Pipelines v1.15.5 (LTS), Chains v0.29.9, Triggers v0.37.2. Les release.yaml et les images
# ne sont pas vérifiables (doc 04 §5) : épinglage par digest après revue (décision du propriétaire du 29/10/2026).
#   revue      release.yaml identiques sur deux sources (GitHub, infra.tekton.dev) et aux digests des assets GitHub,
#              épinglés ici ; images : digest du release.yaml = digest du tag dans le registre, manifeste linux/amd64
#              listé dans l'index épinglé ; revue des droits (ClusterRoles) et des webhooks ; resultats/tekton-*.{log,tsv}
#   miroir     manifeste linux/amd64 de chaque image copié dans Zot (amont/…) ; image shell : busybox des images
#              airgap de k3s (vérifiées en J1) au lieu de cgr.dev/chainguard/busybox (identité de signature non documentée)
#   installer  manifestes réécrits vers Zot (aucune référence externe tirée), contrôleurs en zone confiance (kustomize) ;
#              Chains : KMS hashivault://chains (OpenBao, JWT avec un jeton projeté d'audience openbao), slsa/v2alpha4,
#              stockage OCI en dsse, sans transparence publique ; contrôle : toutes les images tirées viennent de Zot
#   signature  essai de la chaîne de signature : TaskRun sur sc-build qui ne fait que publier IMAGE_URL/IMAGE_DIGEST d'une
#              image poussée depuis l'hôte ; Chains signe via OpenBao, pousse .sig et .att dans Zot ; vérification cosign
#              avec la clé publique de Transit. Ce n'est pas un build : la provenance décrit une image non construite
#   verifier   cosign verify et verify-attestation (slsaprovenance1) avec la clé publique de Transit ; autre clé refusée ;
#              contenu de la provenance ; audit d'OpenBao
#
# Usage (racine du dépôt) : mise run confiance:tekton -- <étape>…   (journal : resultats/tekton-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
D=$O/telechargements/tekton
T=$W/tekton
trap 'rm -rf "$T/auth" "$W/refus.out"' EXIT
# composant version fichier sha256 (assets GitHub = infra.tekton.dev, relevé du 29/10/2026)
RELEASES="pipeline v1.15.5 release.yaml c2fe5c2ac98af2984f2d58199e81ef2056802f671051744d986ec998ad19ba84
chains v0.29.9 release.yaml a3f9154467f8dd40d438ccd7a0b144d4ff419b18189c99b9b5e6e1a2af31fa46
triggers v0.37.2 release.yaml c4113c01e977e313d0223b2a0eab5ba0f9be01c618cb0421b5c0a9fc9d46d426
triggers v0.37.2 interceptors.yaml cf2a59a98817d97c8112138186b4a8ca4f90a84a80748dc77db348aa080c5baa"
BUSYBOX_AMONT=docker.io/rancher/mirrored-library-busybox:1.37.0
BUSYBOX_INDEX=sha256:101b4afd76732482eff9b95cae5f94bcf295e521fbec4e01b69c5421f3f3f3e5   # = image airgap de k3s v1.35.9
TSV=$R/tekton-images.tsv
mkdir -p "$T"

ref_images() { grep -hoE '[a-z0-9.-]+\.[a-z]+/[a-zA-Z0-9._/-]+(:[a-zA-Z0-9._-]+)?@sha256:[0-9a-f]{64}' "$@" | sort -u; }
amd64() { crane manifest "$1" | jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64" and (.platform.variant // "") == "") | .digest'; }
documents() { # fichier types… : documents YAML des types demandés, en JSON (kubectl, sans envoi au serveur)
  local f=$1 y; shift
  y=$(awk -v types="$*" 'BEGIN { split(types, t, " ") } /^---/ { if (doc != "" && keep) print doc "\n---"; doc = ""; keep = 0; next }
    { doc = doc "\n" $0; for (i in t) if ($0 == "kind: " t[i]) keep = 1 } END { if (keep) print doc }' "$f")
  [ -n "$y" ] || return 0
  kubectl create --dry-run=client -o json -f - <<<"$y" | jq -c 'if .kind == "List" then .items[] else . end'
}

etape_revue() {
  local comp ver f sha g i d
  echo "## release.yaml (deux sources, empreintes épinglées)"
  while read -r comp ver f sha; do
    for src in github infra; do
      mkdir -p "$D/$comp-$ver/$src"
      if [ ! -s "$D/$comp-$ver/$src/$f" ]; then
        case $src in
          github) curl -fsSL --proto '=https' -o "$D/$comp-$ver/$src/$f" "https://github.com/tektoncd/$comp/releases/download/$ver/$f" ;;
          infra) curl -fsSL --proto '=https' -o "$D/$comp-$ver/$src/$f" "https://infra.tekton.dev/tekton-releases/$comp/previous/$ver/$f" ;;
        esac
      fi
      echo "$sha  $D/$comp-$ver/$src/$f" | sha256sum -c --quiet
    done
    g=$(gh api "repos/tektoncd/$comp/releases/tags/$ver" --jq ".assets[] | select(.name == \"$f\") | .digest")
    [ "$g" = "sha256:$sha" ] && echo "OK   $comp $ver $f : ${sha:0:16}… = GitHub = infra.tekton.dev = digest de l'asset GitHub" || { echo "KO   $comp $f : $g" >&2; exit 1; }
  done <<<"$RELEASES"

  echo "## images (digest du release.yaml = digest du tag ; manifeste linux/amd64 dans l'index épinglé)"
  printf 'source\tdigest_release\tdigest_amd64\tmiroir\n' > "$TSV"
  while read -r i; do
    d=${i#*@}
    local nom=${i%@*} tag reg a m
    case $nom in
      mcr.microsoft.com/powershell*) echo "--   ${nom##*/} : image Windows (-shell-image-win), jamais tirée sur des nœuds Linux, non copiée"; continue ;;
      cgr.dev/chainguard/busybox*) echo "--   ${nom##*/} (image shell) : remplacée par $BUSYBOX_AMONT ($BUSYBOX_INDEX)"; continue ;;
    esac
    tag=${nom##*/}; tag=${tag#*:}
    reg=$(crane digest "$nom")
    a=$(amd64 "${nom%:*}@$d")
    m=$REG/amont/${nom#*/}; m=${m%:*}@$a
    [ "$reg" = "$d" ] && [ -n "$a" ] && echo "OK   ${nom##*/} : ${d:7:12} = tag $tag ; linux/amd64 ${a:7:12}" || { echo "KO   $nom : registre $reg, amd64 $a" >&2; exit 1; }
    printf '%s\t%s\t%s\t%s\n' "$nom" "$d" "$a" "$m" >> "$TSV"
  done < <(ref_images "$D"/*/github/*.yaml)
  d=$(crane digest "$BUSYBOX_AMONT")
  a=$(amd64 "${BUSYBOX_AMONT%:*}@$BUSYBOX_INDEX")
  sur sc-confiance "sudo k3s ctr -n k8s.io images ls name==$BUSYBOX_AMONT" | grep -F "$BUSYBOX_INDEX" >/dev/null \
    && [ "$d" = "$BUSYBOX_INDEX" ] && echo "OK   busybox 1.37.0 : ${BUSYBOX_INDEX:7:12} = image airgap de k3s sur sc-confiance = tag docker.io ; linux/amd64 ${a:7:12}" \
    || { echo "KO   busybox : $d" >&2; exit 1; }
  printf '%s\t%s\t%s\t%s\n' "$BUSYBOX_AMONT" "$BUSYBOX_INDEX" "$a" "$REG/amont/rancher/mirrored-library-busybox@$a" >> "$TSV"
  echo "$(($(wc -l < "$TSV") - 1)) images dans $(basename "$TSV")"

  echo "## droits : ClusterRoles (règles à surveiller : secrets, pods, exec, jetons, impersonation, jokers) et portée des liaisons"
  for f in "$D"/*/github/*.yaml; do
    documents "$f" ClusterRoleBinding RoleBinding | jq -s 'map(select(.roleRef.kind == "ClusterRole")) | group_by(.roleRef.name)
      | map({key: .[0].roleRef.name, value: (map(if .kind == "ClusterRoleBinding" then "cluster" else "ns:" + .metadata.namespace end) | unique | join(","))}) | from_entries' > "$T/liaisons.json"
    documents "$f" ClusterRole | jq -r --arg f "${f#"$D"/}" --slurpfile l "$T/liaisons.json" '. as $r | .rules[]? | select(
        ((.resources // []) | any(. == "*" or . == "secrets" or . == "pods" or . == "pods/exec" or . == "serviceaccounts/token" or . == "serviceaccounts" or . == "clusterroles" or . == "rolebindings" or . == "clusterrolebindings"))
        or ((.verbs // []) | any(. == "*" or . == "impersonate" or . == "escalate" or . == "bind")))
      | "\($f | split("/")[0])\t\($r.metadata.name)\t\($l[0][$r.metadata.name] // "aucune")\t\((.apiGroups // [""]) | map(if . == "" then "core" else . end) | join(","))\t\(.resources | join(","))\t\(.verbs | join(","))\t\(if .resourceNames then "seulement " + (.resourceNames | join(",")) else "tous" end)"' \
      | column -t -s $'\t'
  done
  echo "## webhooks d'admission (failurePolicy, effets de bord, portée)"
  for f in "$D"/*/github/*.yaml; do
    documents "$f" MutatingWebhookConfiguration ValidatingWebhookConfiguration \
      | jq -r --arg f "${f#"$D"/}" '. as $w | .webhooks[] | "\($f | split("/")[0])\t\($w.kind | sub("WebhookConfiguration"; ""))\t\(.name)\t\(.failurePolicy // "-")\t\(.sideEffects // "-")\t\(.objectSelector // .namespaceSelector // {} | tostring)"' \
      | column -t -s $'\t'
  done
}

etape_miroir() {
  local src d a m n=0
  mkdir -p "$T/auth" && chmod 700 "$T/auth"
  auth_zot "$T/auth/zot.json"
  while IFS=$'\t' read -r src d a m; do
    [ "$src" = source ] && continue
    oras cp "${src%:*}@$a" "$REG_HOTE/${m#"$REG"/}" --to-ca-file "$P/ca-poc.crt" --to-registry-config "$T/auth/zot.json" >/dev/null
    [ "$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/${m#"$REG"/}" | jq -r .digest)" = "$a" ] || { echo "KO   $m" >&2; exit 1; }
    n=$((n + 1))
  done < "$TSV"
  echo "OK   $n manifestes linux/amd64 copiés dans Zot sous amont/ et relus par digest"
}

rendre() { # composant fichier : manifeste réécrit vers Zot + correctifs (kustomize), dans $T/<composant>/rendu.yaml
  local c=$1 f=$2 k=$T/$1 src d a m
  rm -rf "$k" && mkdir -p "$k"
  cp "$f" "$k/release.yaml"
  while IFS=$'\t' read -r src d a m; do
    [ "$src" = source ] && continue
    sed -i "s#${src}@${d}#${m}#g" "$k/release.yaml"
  done < "$TSV"
  sed -i "s#cgr.dev/chainguard/busybox@sha256:[0-9a-f]*#$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$TSV")#g" "$k/release.yaml"
  cp "$here/tekton/kustomization-$c.yaml" "$k/kustomization.yaml"
  [ ! -d "$here/tekton/$c" ] || cp "$here/tekton/$c"/* "$k/"
  kubectl kustomize "$k" > "$k/rendu.yaml"
}

etape_installer() {
  local c
  rendre pipeline "$D/pipeline-v1.15.5/github/release.yaml"
  rendre triggers "$D/triggers-v0.37.2/github/release.yaml"
  rendre interceptors "$D/triggers-v0.37.2/github/interceptors.yaml"
  rendre chains "$D/chains-v0.29.9/github/release.yaml"
  echo "## références d'images restantes hors de Zot dans les manifestes rendus"
  grep -hoE '(ghcr\.io|cgr\.dev|gcr\.io|docker\.io|quay\.io|registry\.k8s\.io|mcr\.microsoft\.com)/[^" ,]+' "$T"/*/rendu.yaml | sort | uniq -c || true
  for c in pipeline triggers interceptors chains; do
    echo "$c : $(grep -c '^kind:' "$T/$c/rendu.yaml") objets, sha256 $(sha256sum < "$T/$c/rendu.yaml" | cut -c1-16)…"
  done
  kubectl create configmap ca-poc -n tekton-chains --from-file=ca.crt="$P/ca-poc.crt" --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  kubectl apply --server-side --force-conflicts -f "$T/pipeline/rendu.yaml" >/dev/null
  kubectl wait --for=condition=Available deployment --all -n tekton-pipelines --timeout=300s
  kubectl wait --for=condition=Available deployment --all -n tekton-pipelines-resolvers --timeout=300s
  kubectl apply --server-side --force-conflicts -f "$T/triggers/rendu.yaml" >/dev/null
  kubectl wait --for=condition=Available deployment --all -n tekton-pipelines --timeout=300s
  kubectl apply --server-side --force-conflicts -f "$T/interceptors/rendu.yaml" >/dev/null
  kubectl apply --server-side --force-conflicts -f "$T/chains/rendu.yaml" >/dev/null
  kubectl wait --for=condition=Available deployment --all -n tekton-pipelines --timeout=300s
  kubectl wait --for=condition=Available deployment --all -n tekton-chains --timeout=300s
  for n in tekton-pipelines tekton-pipelines-resolvers tekton-chains; do kubectl get pods -n "$n" -o wide --no-headers | awk -v n="$n" '{print n, $1, $3, $7}'; done
  echo "## images réellement tirées (imageID des conteneurs)"
  kubectl get pods -n tekton-pipelines -o json | jq -r '.items[].status.containerStatuses[].imageID' > "$T/ids"
  for n in tekton-pipelines-resolvers tekton-chains; do kubectl get pods -n "$n" -o json | jq -r '.items[].status.containerStatuses[].imageID' >> "$T/ids"; done
  sort -u "$T/ids" | sed 's/@sha256:\(.\{12\}\).*/@sha256:\1…/'
  grep -v "^$REG/amont/" "$T/ids" && { echo "KO   image tirée hors de Zot" >&2; exit 1; } || echo "OK   $(sort -u "$T/ids" | wc -l) images, toutes tirées de $REG/amont/"
  echo "## configuration de Chains"
  kubectl get configmap -n tekton-chains chains-config -o json | jq -r '.data | to_entries[] | "\(.key) = \(.value)"'
}

etape_signature() {
  local img=$REG/builds/essai-signature dig=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
  mkdir -p "$T/auth" && chmod 700 "$T/auth"
  # Image d'essai poussée depuis l'hôte (sample-app de la brique 04) ; la tâche ne la construit pas.
  auth_zot "$T/auth/zot.json"
  oras cp --from-oci-layout "$HOME/.cache/supply-chain-poc/w/b04/app-layout@$dig" "$REG_HOTE/builds/essai-signature@$dig" \
    --to-ca-file "$P/ca-poc.crt" --to-registry-config "$T/auth/zot.json" >/dev/null
  # Zone build : compte Zot poc-build (builds/** seulement), utilisé par Chains pour pousser .sig et .att.
  kubectl apply --server-side -f "$here/tekton/builds.yaml" >/dev/null
  auth_zot "$T/auth/build.json" "" poc-build "$REG"
  kubectl create secret generic zot-build -n builds --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson="$T/auth/build.json" \
    --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  kubectl delete taskrun -n builds essai-signature --ignore-not-found --wait=true >/dev/null
  sed -e "s#@IMAGE@#$img#" -e "s#@DIGEST@#$dig#" -e "s#@BUSYBOX@#$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$TSV")#" \
    "$here/tekton/essai-signature.yaml" | kubectl apply -f - >/dev/null
  kubectl wait -n builds --for=condition=Succeeded taskrun/essai-signature --timeout=180s
  kubectl get taskrun -n builds essai-signature -o json | jq -c '{pod: .status.podName, "résultats": ([.status.results[] | {(.name): .value}] | add)}'
  local signe=""
  for _ in $(seq 60); do
    signe=$(kubectl get taskrun -n builds essai-signature -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')
    [ -n "$signe" ] && break
    sleep 2
  done
  echo "annotation chains.tekton.dev/signed = ${signe:-absente}"
  kubectl logs -n tekton-chains deploy/tekton-chains-controller --since=5m | grep -iE 'error|signed|openbao|vault|kms|pushed|upload' | jq -Rc 'fromjson? // . | if type == "object" then {level, msg: (.msg // .message), error} else . end' | tail -15
  [ "$signe" = true ] || { echo "KO   TaskRun non signé" >&2; exit 1; }
  oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/builds/essai-signature"
}

etape_verifier() { # signature et attestation de l'essai, vérifiées sur l'hôte avec la clé publique de Transit
  local ref=$REG_HOTE/builds/essai-signature@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5 debut
  local cle=$R/chains-cle-publique.pem opts=(--insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt")
  debut=$(kubectl get taskrun -n builds essai-signature -o jsonpath='{.status.startTime}')
  mise run confiance:openbao -- cle | grep 'clé publique'
  cosign verify --key "$cle" "${opts[@]}" "$ref" 2> "$T/cosign.err" > "$T/sig.json" \
    && echo "OK   signature de l'image vérifiée avec la clé Transit chains : $(jq -c '[.[] | .critical | {type, digest: .image."docker-manifest-digest"[7:19], ref: .identity."docker-reference"}] | unique' "$T/sig.json")" \
    || { cat "$T/cosign.err" >&2; exit 1; }
  cosign verify-attestation --key "$cle" --type slsaprovenance1 "${opts[@]}" "$ref" 2> "$T/cosign.err" > "$T/att.json" \
    && echo "OK   attestation SLSA v1 vérifiée ($(wc -l < "$T/att.json") enveloppe(s))" || { cat "$T/cosign.err" >&2; exit 1; }
  head -1 "$T/att.json" | jq -r .payload | base64 -d > "$T/provenance.json"
  jq '{predicateType, subject, buildType: .predicate.buildDefinition.buildType, externalParameters: .predicate.buildDefinition.externalParameters,
       internalParameters: .predicate.buildDefinition.internalParameters,
       resolvedDependencies: [.predicate.buildDefinition.resolvedDependencies[]? | {uri, digest}],
       builder: .predicate.runDetails.builder.id, invocationId: .predicate.runDetails.metadata.invocationID}' "$T/provenance.json"
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2>/dev/null | openssl pkey -pubout > "$T/autre.pem"
  refus "signature vérifiée avec une autre clé" "no matching signatures|invalid signature|failed to verify" cosign verify --key "$T/autre.pem" "${opts[@]}" "$ref"
  echo "## audit d'OpenBao pendant l'essai (depuis $debut)"
  kubectl exec -n openbao openbao-0 -- cat /openbao/data/audit.log \
    | jq -c --arg d "$debut" 'select(.type == "response" and .time >= $d) | {time: .time[11:19], chemin: .request.path, compte: .auth.display_name, politiques: .auth.policies, erreur: (.error // .response.data.error // null)}'
}

lancer tekton J4 "$@"
