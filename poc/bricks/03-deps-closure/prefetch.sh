#!/usr/bin/env bash
# Brique 03, jalon F2 (protocole du 03/11/2026 ; décisions D1 a, D2 révisée, D3 révisée, D4 a du propriétaire ; npm hors de F2) :
# prefetch des modules Go de sample-app dans la plateforme. Prédictions : resultats/f2-predictions.md. Chaque étape qui modifie
# l'hôte, le cluster ou Zot est soumise à l'accord du propriétaire.
#   image       sur l'hôte : image d'outils du prefetch (Dockerfile.prefetch) ; entrées vérifiées (tag de Hermeto et son commit,
#               roues contrôlées par les empreintes de son requirements.txt, roue de Hermeto construite depuis le tag, clôture
#               nix de python313, gitMinimal et cacert, Go 1.26.10 comparé à sum.golang.org, busybox) ; BuildKit rootless
#               éphémère, deux constructions sans cache au même digest, essai des versions hors réseau ; copie dans Zot
#               (poc-ecriture, plateforme/outils-prefetch, par digest)
#   cilium      l7Proxy: true (cilium/valeurs.yaml) appliqué par cilium.sh appliquer ; exécuté le 03/11/2026 : Envoy embarqué
#               démarré, retour à l7Proxy: false ; ÉTAPE ABANDONNÉE (D2 révisée une seconde fois : sortie 443 hors privé)
#   compte      compte Zot poc-fermetures (stockage.sh zot, Zot redémarré) : création par digest dans builds/fermetures/**
#               acceptée ; tag, autre dépôt de builds/ et suppression refusés ; poc-images refusé dans builds/fermetures/ ;
#               poc-build (Chains) y écrit un tag ; secret zot-fermetures dans builds
#   reseau      CiliumNetworkPolicy prefetch-sortie (politique/prefetch-sortie.yaml) ; invariant : seule politique qui sélectionne
#               les pods de prefetch-gomod ; pod de sonde au label : adresses publiques en 443 et Forgejo joints ; port 80,
#               API de k3s et Zot refusés ; témoin sans le label : tout joint ; flux de Hubble
#   taches      prefetch-gomod et publier-fermeture rendues, signées (tkn), comparées à leur signature versionnée (SIGNER=1 pour
#               la refaire), bundles, digests exigés dans la liste revue ; pipeline prefetch-sample-app signée, bundle
#   prefetch    deux PipelineRuns du même commit (gabarit en service, pipeline remplacée) : réussite, label et nœud des pods,
#               fermetures publiées, arbres comparés entre eux et à la fermeture de l'hôte (0ab5a507), Chains, flux de Hubble
#   provenance  provenance du PipelineRun vérifiée par cosign (clé de Chains) sur la fermeture : sujet, buildType, source,
#               image d'outils et bundles dans resolvedDependencies ; autre clé refusée
#
# Usage (racine du dépôt) : mise run fermetures:f2 -- <étape>…   (journal : resultats/f2-<étape>.log)
set -euo pipefail
export LC_ALL=C

h03=$(cd "$(dirname "$0")" && pwd)
here=$h03/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, OUTILS, sur, refus, purger_pr, bundle, listee, signe, auth_zot
R=$h03/resultats
POC=${POC_OUTILS:?POC_OUTILS absent : lancer par mise run fermetures:f2}
T=$HOME/.cache/supply-chain-poc/03/f2
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets, même en cas d'échec

HERMETO_TAG=0.64.0
HERMETO_COMMIT=1f37e32dfdf28342b50c6f394c3e99914fdb24e9   # mise.toml, outils:hermeto
GO_MODULE=golang.org/toolchain@v0.0.1-go1.26.10.linux-amd64
GOROOT_126=$POC/gomodcache/$GO_MODULE
DEPOT_OUTILS=plateforme/outils-prefetch
PREFETCH_DIGEST=sha256:68e0ae705de5a8f993f168d8252b3218d7d3ed76e704cf24d4414006aea7b8cc   # image d'outils du prefetch : étape image du 03/11/2026, deux constructions
DEPOT_FERMETURE=$REG/builds/fermetures/sample-app
FERMETURE_HOTE=sha256:0ab5a50767bee2e430cdd2db6b4d61580629f89fd48fb352cd1a2a545ee56048   # construction.sh, fermeture de l'hôte
SAMPLE_APP=workspace/sample-app
TETE_J2=6391fd437f26696847041be3226bbbf633f55a2f   # construction.sh : commit de main construit en J7
POLITIQUE=$here/politique/prefetch-sortie.yaml

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
nix_chemin() { nix build --no-link --print-out-paths --offline --inputs-from "$repo/poc/benchmarks/nix" "nixpkgs#$1"; }
contenu() { # répertoire : empreinte des seuls chemins et contenus des fichiers (hors bom.json)
  (cd "$1" && find . -type f ! -name bom.json -printf '%P\n' | sort | while read -r f; do echo "$f $(sha256sum < "$f" | cut -c1-64)"; done) | sha256sum | cut -c1-64
}

etape_image() {
  local c=$T/contexte py gi ca s db d i bk=$T/bk
  py=$(nix_chemin python313); gi=$(nix_chemin gitMinimal); ca=$(nix_chemin cacert)
  echo "## entrées"
  rm -rf -- "${c:?}" "${T:?}/hermeto-src"; mkdir -p "$c/roues"
  git clone -q -c advice.detachedHead=false --depth 1 --branch "$HERMETO_TAG" https://github.com/hermetoproject/hermeto.git "$T/hermeto-src"
  attendu "Hermeto $HERMETO_TAG : commit du tag" "$(git -C "$T/hermeto-src" rev-parse HEAD)" "$HERMETO_COMMIT"
  "$POC/hermeto/bin/pip" download -q --only-binary=:all: --no-deps --require-hashes -r "$T/hermeto-src/requirements.txt" -d "$c/roues"
  cp "$T/hermeto-src/requirements.txt" "$c/roues/"
  echo "roues (empreintes de requirements.txt contrôlées par pip) : $(find "$c/roues" -name '*.whl' | wc -l)"
  for i in a b; do
    rm -rf -- "${T:?}/roue-$i"
    SOURCE_DATE_EPOCH=315532800 "$POC/hermeto/bin/pip" wheel -q --no-deps --no-build-isolation -w "$T/roue-$i" "$T/hermeto-src"
  done
  cmp -s "$T"/roue-a/hermeto-*.whl "$T"/roue-b/hermeto-*.whl && echo "OK   roue de Hermeto identique sur deux constructions : $(basename "$T"/roue-a/hermeto-*.whl) $(sha256sum < "$T"/roue-a/hermeto-*.whl | cut -c1-64)" \
    || { echo "KO   roue de Hermeto différente d'une construction à l'autre" >&2; exit 1; }
  cp "$T"/roue-a/hermeto-*.whl "$c/roues/"
  s=$(cat "$POC/gomodcache/cache/download/${GO_MODULE%@*}/@v/${GO_MODULE#*@}.ziphash")
  db=$(curl -fsS --max-time 30 "https://sum.golang.org/lookup/$GO_MODULE" | awk -v v="${GO_MODULE#*@}" '$2 == v {print $3}')
  [ -n "$s" ] && [ "$s" = "$db" ] && echo "OK   toolchain $GO_MODULE : $s = sum.golang.org" || { echo "KO   toolchain : $s ≠ $db" >&2; exit 1; }
  cp -a "$GOROOT_126" "$c/go"
  cp "$(readlink -f "$POC/busybox/bin/busybox")" "$c/busybox"
  cp "$ca/etc/ssl/certs/ca-bundle.crt" "$c/ca-certificates.crt"
  echo "python $py ; git $gi ; cacert $ca ; busybox $(sha256sum < "$c/busybox" | cut -c1-16)"
  nix path-info -r "$py" "$gi" "$ca" | sort > "$T/cloture.txt"
  while read -r p; do cp -a --parents "$p" "$c/"; done < "$T/cloture.txt"
  echo "clôture nix : $(wc -l < "$T/cloture.txt") chemins, $(du -sm "$c/nix" | cut -f1) Mo ; empreinte $(sha256sum < "$T/cloture.txt" | cut -c1-16)"
  echo "## BuildKit rootless éphémère (nixpkgs du banc B), deux constructions sans cache"
  [ ! -e "$bk" ] || unshare -Ur --map-auto rm -rf -- "$bk"   # fichiers à des uid subordonnés (comme bancs-laptop.sh)
  mkdir -p "$bk"
  rootlesskit --state-dir="$bk/rk" --net=host "$POC/buildkit-nix/bin/buildkitd" --rootless --root "$bk/root" --addr "unix://$bk/sock" \
    --oci-worker=true --containerd-worker=false --oci-worker-snapshotter=native --oci-worker-binary="$POC/runc-nix/bin/runc" \
    > "$bk/buildkitd.log" 2>&1 &
  local pid=$!
  for _ in $(seq 60); do "$POC/buildkit-nix/bin/buildctl" --addr "unix://$bk/sock" debug workers >/dev/null 2>&1 && break; sleep 1; done
  construire() { # cible sortie|- : construction de Dockerfile.prefetch
    "$POC/buildkit-nix/bin/buildctl" --addr "unix://$bk/sock" build --frontend dockerfile.v0 --no-cache \
      --local context="$c" --local dockerfile="$h03" --opt filename=Dockerfile.prefetch --opt target="$1" \
      --opt build-arg:PYTHON="$py" --opt build-arg:GIT="$gi" --opt build-arg:SOURCE_DATE_EPOCH=0 \
      ${2:+--output "type=oci,dest=$2,rewrite-timestamp=true"} 2> "$T/build-$1.log"
  }
  for i in a b; do
    construire outils "$T/outils-$i.tar" || { tail -30 "$T/build-outils.log" >&2; kill "$pid"; exit 1; }
    d=$(tar -xOf "$T/outils-$i.tar" index.json | jq -r '.manifests[0].digest')
    echo "$i : image $d ($(du -m "$T/outils-$i.tar" | cut -f1) Mo)"; echo "$d" > "$T/outils-$i.digest"
  done
  construire essai || { tail -30 "$T/build-essai.log" >&2; kill "$pid"; exit 1; }
  echo "essai hors réseau (cible essai) :"; grep -E '^#[0-9]+ [0-9.]+ ' "$T/build-essai.log" | grep -vE 'DONE|CACHED' | sed 's/^/     /' | tail -6
  kill "$pid"; wait "$pid" 2>/dev/null || true
  attendu "image d'outils identique sur deux constructions" "$(cat "$T/outils-a.digest")" "$(cat "$T/outils-b.digest")"
  echo "## copie dans Zot (poc-ecriture, par digest)"
  d=$(cat "$T/outils-a.digest")
  rm -rf -- "${T:?}/layout"; mkdir -p "$T/layout" && tar -xf "$T/outils-a.tar" -C "$T/layout"
  auth_zot "$T/auth/zot.json"
  oras cp --no-tty --from-oci-layout "$T/layout@$d" "$REG_HOTE/$DEPOT_OUTILS@$d" --to-ca-file "$P/ca-poc.crt" --to-registry-config "$T/auth/zot.json" > /dev/null
  attendu "relue en lecture anonyme" "$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/$DEPOT_OUTILS@$d" | jq -r .digest)" "$d"
  oras manifest fetch --ca-file "$P/ca-poc.crt" "$REG_HOTE/$DEPOT_OUTILS@$d" | jq -c '{couches: (.layers | length), octets: ([.layers[].size] | add)}'
  [ -n "$PREFETCH_DIGEST" ] && attendu "image d'outils (digest épinglé)" "$d" "$PREFETCH_DIGEST" || echo "À ÉPINGLER : PREFETCH_DIGEST=$d"
}

etape_cilium() {
  local a
  echo "## cilium/valeurs.yaml : $(grep -E '^l7Proxy:' "$here/cilium/valeurs.yaml")"
  mise run confiance:cilium -- appliquer
  attendu "cilium-config : enable-l7-proxy" "$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-l7-proxy}')" true
  attendu "cilium-config : external-envoy-proxy" "$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.external-envoy-proxy}')" false
  for a in $(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[*].metadata.name}'); do
    echo "$a ($(kubectl -n kube-system get pod "$a" -o jsonpath='{.spec.nodeName}')) : proxy $(kubectl -n kube-system exec "$a" -c cilium-agent -- cilium-dbg status 2>/dev/null \
      | awk -F': *' '/^Proxy Status/ {print $2}') ; processus envoy : $(kubectl -n kube-system exec "$a" -c cilium-agent -- sh -c 'cat /proc/[0-9]*/comm 2>/dev/null' | grep -c envoy || true)"
  done
  echo "suite : mise run confiance:preuves -- test6 (sortie de la construction refusée sous Cilium, rejouée après le changement)"
}

etape_compte() {
  local code
  mise run confiance:stockage -- zot
  auth_zot "$T/auth/fermetures.json" "" poc-fermetures
  auth_zot "$T/auth/images.json" "" poc-images
  auth_zot "$T/auth/build.json" "" poc-build
  (umask 077 && printf 'Authorization: Basic %s\n' "$(printf 'poc-fermetures:%s' "$(cat "$S/zot-poc-fermetures.password")" | base64 -w0)" > "$T/auth/entete")
  echo "## artefact d'essai (un fichier, layout OCI local)"
  rm -rf -- "${T:?}/essai"; mkdir -p "$T/essai" && echo "essai F2" > "$T/essai/f"
  local d; d=$(cd "$T/essai" && oras push --no-tty --oci-layout --format go-template='{{.digest}}' --artifact-type application/vnd.supply-chain.essai.v1 \
    --annotation org.opencontainers.image.created=1970-01-01T00:00:00Z "$T/essai/l:essai" f:text/plain)
  oras manifest fetch --oci-layout "$T/essai/l@$d" > "$T/essai/manifeste.json"
  put() { # chemin [méthode] : code HTTP d'une écriture du manifeste par poc-fermetures
    curl -s -o "$T/put.out" -w '%{http_code}' --cacert "$P/ca-poc.crt" -H @"$T/auth/entete" -H "Content-Type: application/vnd.oci.image.manifest.v1+json" \
      -X "${2:-PUT}" --data-binary @"$T/essai/manifeste.json" "https://$REG_HOTE/v2/$1"
  }
  for i in 1 2; do
    oras cp --no-tty --from-oci-layout "$T/essai/l@$d" "$REG_HOTE/builds/fermetures/essai@$d" --to-ca-file "$P/ca-poc.crt" --to-registry-config "$T/auth/fermetures.json" > /dev/null
    echo "OK   poc-fermetures : push par digest n° $i dans builds/fermetures/essai"
  done
  code=$(put "builds/fermetures/essai/manifests/essai")
  [ "$code" = 403 ] && grep -qF 'écriture par digest seulement' "$T/put.out" && echo "OK   poc-fermetures : tag refusé (403, motif de la condition)" \
    || { echo "KO   tag : HTTP $code $(cat "$T/put.out")" >&2; exit 1; }
  attendu "poc-fermetures : autre dépôt de builds/ (builds/essai-fermetures)" "$(put "builds/essai-fermetures/manifests/$d")" 403
  attendu "poc-fermetures : suppression" "$(put "builds/fermetures/essai/manifests/$d" DELETE)" 403
  refus "poc-images dans builds/fermetures/" "403|denied|unauthorized" \
    oras cp --no-tty --from-oci-layout "$T/essai/l@$d" "$REG_HOTE/builds/fermetures/essai-images@$d" --to-ca-file "$P/ca-poc.crt" --to-registry-config "$T/auth/images.json"
  oras cp --no-tty --from-oci-layout "$T/essai/l:essai" "$REG_HOTE/builds/fermetures/essai:chains" --to-ca-file "$P/ca-poc.crt" --to-registry-config "$T/auth/build.json" > /dev/null \
    && echo "OK   poc-build (Chains) : tag écrit dans builds/fermetures/essai" || { echo "KO   poc-build : tag refusé" >&2; exit 1; }
  attendu "lecture anonyme" "$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/builds/fermetures/essai@$d" | jq -r .digest)" "$d"
  echo "## secret zot-fermetures de builds"
  auth_zot "$T/auth/fermetures-reg.json" "" poc-fermetures "$REG"
  kubectl create secret generic zot-fermetures -n builds --from-file=config.json="$T/auth/fermetures-reg.json" --dry-run=client -o yaml \
    | kubectl apply --server-side -f - > /dev/null
  kubectl get secret -n builds zot-fermetures -o json | jq -r '"secret \(.metadata.name) : clés \(.data | keys | join(","))"'
}

sonde() { # nom avec|sans : pod de builds au contexte de restricted, image d'outils du prefetch, label tekton.dev/task=prefetch-gomod
  jq -n --arg n "$1" --arg l "$2" --arg i "$REG/$DEPOT_OUTILS@$PREFETCH_DIGEST" '{apiVersion: "v1", kind: "Pod",
    metadata: ({name: $n, namespace: "builds"} + (if $l == "avec" then {labels: {"tekton.dev/task": "prefetch-gomod"}} else {} end)),
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "ca", configMap: {name: "ca-poc"}}],
      containers: [{name: "sonde", image: $i, command: ["sleep", "600"],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
        volumeMounts: [{name: "ca", mountPath: "/etc/ca-poc", readOnly: true}]}]}}' | kubectl apply -f - > /dev/null
  kubectl wait -n builds "pod/$1" --for=condition=Ready --timeout=180s > /dev/null
}
essais_sortie() { # pod : une ligne par destination (joint ou refusé, avec le motif)
  kubectl exec -n builds "$1" -- python3 - <<'PY'
import socket, ssl, subprocess, urllib.request
ctx = ssl.create_default_context(cafile=None)
poc = ssl.create_default_context(cafile="/etc/ca-poc/ca.crt")
for nom, url, c in [("proxy.golang.org", "https://proxy.golang.org/github.com/go-chi/chi/v5/@v/list", ctx),
                    ("storage.googleapis.com", "https://storage.googleapis.com/", ctx),
                    ("sum.golang.org", "https://sum.golang.org/latest", ctx),
                    ("github.com", "https://github.com/", ctx),
                    ("proxy.golang.org en 80", "http://proxy.golang.org/", ctx),
                    ("API de k3s", "https://192.168.161.11:6443/version", ssl._create_unverified_context()),
                    ("Zot", "https://sc-stockage.poc.test:5000/v2/", poc)]:
    try:
        r = urllib.request.urlopen(url, timeout=8, context=c)
        print(f"{nom} : joint (HTTP {r.status})")
    except urllib.error.HTTPError as e:
        print(f"{nom} : joint (HTTP {e.code})")
    except Exception as e:
        print(f"{nom} : refusé ({type(e).__name__} : {str(e)[:80]})")
g = subprocess.run(["git", "-c", "http.sslCAInfo=/etc/ca-poc/ca.crt", "ls-remote", "https://sc-stockage.poc.test:3000/workspace/sample-app.git", "HEAD"],
                   capture_output=True, text=True, timeout=20)
print("Forgejo : " + ("joint (" + g.stdout.split()[0][:12] + ")" if g.returncode == 0 else "refusé (" + g.stderr.strip()[:80] + ")"))
PY
}

etape_reseau() {
  local n a
  [ -n "$PREFETCH_DIGEST" ] || { echo "KO   PREFETCH_DIGEST non épinglé (étape image)" >&2; exit 1; }
  kubectl apply -f "$POLITIQUE" > /dev/null && echo "CiliumNetworkPolicy prefetch-sortie appliquée"
  echo "## invariant : politiques de builds qui sélectionneraient un pod au label tekton.dev/task=prefetch-gomod"
  n=$( { kubectl get networkpolicy -n builds -o json | jq -r '.items[] | select((.spec.podSelector.matchLabels // {}) as $m | ($m | length) == 0
           or $m["tekton.dev/task"] == "prefetch-gomod") | "NetworkPolicy \(.metadata.name)"'
         kubectl get ciliumnetworkpolicy -n builds -o json | jq -r '.items[] | select((.spec.endpointSelector.matchLabels // {}) as $m | ($m | length) == 0
           or $m["tekton.dev/task"] == "prefetch-gomod") | "CiliumNetworkPolicy \(.metadata.name)"'; } | sort | paste -sd' ' -)
  attendu "politiques qui sélectionnent ces pods" "$n" "CiliumNetworkPolicy prefetch-sortie"
  for n in f2-sonde-avec f2-sonde-sans; do kubectl delete pod -n builds "$n" --ignore-not-found --wait=true > /dev/null; done
  sonde f2-sonde-avec avec; sonde f2-sonde-sans sans
  for n in f2-sonde-avec f2-sonde-sans; do echo "## $n ($(kubectl get pod -n builds "$n" -o jsonpath='{.spec.nodeName}'))"; essais_sortie "$n" | sed 's/^/     /'; done
  a=$(kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName="$(kubectl get pod -n builds f2-sonde-avec -o jsonpath='{.spec.nodeName}')" -o jsonpath='{.items[0].metadata.name}')
  echo "## Hubble ($a) : flux de f2-sonde-avec"
  kubectl -n kube-system exec "$a" -c cilium-agent -- hubble observe --pod builds/f2-sonde-avec --last 200 -o compact 2>/dev/null \
    | grep -E 'DROPPED|FORWARDED|dns' | sed -E 's/^[A-Za-z]+ +[0-9]+ [0-9:.]+ //' | cut -c1-170 | sort | uniq -c | sort -rn | head -25
  for n in f2-sonde-avec f2-sonde-sans; do kubectl delete pod -n builds "$n" --wait=false > /dev/null; done
}

signer_tache() { # nom : comme construction.sh (signature versionnée dans la 08, bundle, liste revue)
  local n=$1 v=$here/politique/taches/$1.signee.yaml r
  tkn task sign "$T/$n.yaml" -K "$S/taches.key" -f "$T/$n-signee.yaml" > /dev/null
  if [ -n "${SIGNER:-}" ]; then cp "$T/$n-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans politique/taches/$n.signee.yaml (liste revue à mettre à jour)"; fi
  [ -s "$v" ] || { echo "KO   signature versionnée absente : SIGNER=1, puis revue de politique/porte/taches.yml" >&2; exit 1; }
  cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") \
    && echo "OK   $n : signature versionnée conforme au gabarit rendu, signature exceptée" \
    || { echo "KO   $n : gabarit modifié depuis la signature versionnée (SIGNER=1, puis revue de la liste)" >&2; exit 1; }
  r=$REG/tekton/tasks/$n@$(bundle "$v" "tekton/tasks/$n" f2)
  echo "$r" > "$T/$n.ref"
  if listee "$r"; then echo "OK   $n dans la liste revue : $r"
  elif [ -n "${SIGNER:-}" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml après revue, puis relancer sans SIGNER : $r"
  else echo "KO   $n absente de la liste revue politique/porte/taches.yml : $r" >&2; exit 1; fi
}

etape_taches() {
  local p
  [ -n "$PREFETCH_DIGEST" ] || { echo "KO   PREFETCH_DIGEST non épinglé (étape image)" >&2; exit 1; }
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente (politique.sh taches)" >&2; exit 1; }
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh)
  echo "## tâches (tkn $(tkn version --component client))"
  sed -e "s#@PREFETCH@#$REG/$DEPOT_OUTILS@$PREFETCH_DIGEST#g" "$here/politique/taches/prefetch-gomod.yaml" > "$T/prefetch-gomod.yaml"
  sed -e "s#@OUTILS@#$REG/$OUTILS@$OUTILS_DIGEST#g" "$here/politique/taches/publier-fermeture.yaml" > "$T/publier-fermeture.yaml"
  for p in prefetch-gomod publier-fermeture; do
    ! grep -n '@[A-Z_]*@' "$T/$p.yaml" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans $p" >&2; exit 1; }
    signer_tache "$p"
  done
  echo "## pipeline prefetch-sample-app (signée à chaque passage)"
  sed -e "s#@PREFETCH_TACHE@#$(cat "$T/prefetch-gomod.ref")#" -e "s#@PUBLIER_FERMETURE@#$(cat "$T/publier-fermeture.ref")#" \
    -e "s#@DEPOT_FERMETURE@#$DEPOT_FERMETURE#" "$here/politique/taches/prefetch-sample-app.yaml" > "$T/prefetch-sample-app.yaml"
  ! grep -n '@[A-Z_]*@' "$T/prefetch-sample-app.yaml" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans la pipeline" >&2; exit 1; }
  tkn pipeline sign "$T/prefetch-sample-app.yaml" -K "$S/taches.key" -f "$T/prefetch-sample-app-signee.yaml" > /dev/null
  echo "$REG/tekton/pipelines/prefetch-sample-app@$(bundle "$T/prefetch-sample-app-signee.yaml" tekton/pipelines/prefetch-sample-app f2)" | tee "$T/pipeline.ref"
}

pr_f2() { # nom : PipelineRun du gabarit en service (declencheurs), pipeline remplacée par prefetch-sample-app ; $T/pr-<nom>.json
  kubectl get triggertemplate -n declencheurs sample-app -o json | jq --arg n "$1" --arg b "$(cat "$T/pipeline.ref")" --arg c "$TETE_J2" \
    --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" '.spec.resourcetemplates[0] | .metadata.name = $n
      | .spec.pipelineRef.params |= map(if .name == "bundle" then .value = $b elif .name == "name" then .value = "prefetch-sample-app" else . end)
      | .spec.params |= map(if .name == "commit" then .value = $c elif .name == "depot" then .value = $u else . end)
      | .spec.workspaces = [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "1Gi"}}}}}]
      | del(.spec.taskRunSpecs)' > "$T/pr-$1.json"
}
fin_pr() { # nom : attend la fin (900 s) ; « statut|raison|message »
  local st=""
  for _ in $(seq 900); do
    st=$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}')
    [ -n "$st" ] && [ "$st" != Unknown ] && break; sleep 1
  done
  kubectl get pipelinerun -n builds "$1" -o json | jq -r '.status.conditions[] | select(.type == "Succeeded") | "\(.status)|\(.reason)|\(.message | gsub("\n"; " ") | .[0:300])"'
}

etape_prefetch() {
  local pr r d i a
  [ -s "$T/pipeline.ref" ] || { echo "KO   pipeline absente (étape taches)" >&2; exit 1; }
  for i in 1 2; do
    pr=f2-prefetch-$i
    pr_f2 "$pr"; purger_pr "$pr"
    kubectl create -f "$T/pr-$pr.json" > /dev/null
    echo "## $pr créé ($(jq -r '.spec.params | map(.name + "=" + .value) | join(", ")' "$T/pr-$pr.json"))"
    r=$(fin_pr "$pr")
    for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}'); do
      p=$(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.podName}')
      kubectl logs -n builds "$p" --all-containers > "$T/$t.log" 2>&1 || true
      echo "### TaskRun $t ($(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.conditions[0].reason}')), pod $p sur $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}' 2>/dev/null), tekton.dev/task $(kubectl get pod -n builds "$p" -o jsonpath='{.metadata.labels.tekton\.dev/task}' 2>/dev/null)"
      grep -vE '^\s*$' "$T/$t.log" | grep -vE 'INFO (Downloading|Retrieving)' | tail -8 | sed 's/^/     /'
    done
    attendu "PipelineRun $pr" "$(cut -d'|' -f1,2 <<< "$r")" "True|Succeeded"
    d=$(kubectl get pipelinerun -n builds "$pr" -o json | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
    echo "fermeture publiée : $DEPOT_FERMETURE@$d" && echo "$d" > "$T/fermeture-$i.digest"
    attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
    a=$(kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=sc-build -o jsonpath='{.items[0].metadata.name}')
    echo "Hubble ($a), pod de prefetch : $(kubectl -n kube-system exec "$a" -c cilium-agent -- hubble observe --pod "builds/$(kubectl get pods -n builds -l "tekton.dev/pipelineRun=$pr,tekton.dev/pipelineTask=prefetch" -o jsonpath='{.items[0].metadata.name}')" --last 500 -o jsonpb 2>/dev/null \
      | jq -r 'select(.flow.verdict) | "\(.flow.verdict) \(.flow.destination_names // [] | join(",")) \(.flow.IP.destination // "")"' | sort | uniq -c | sort -rn | head -12 | paste -sd';' -)"
  done
  echo "## comparaisons"
  for i in 1 2; do
    rm -rf -- "${T:?}/f-$i"; oras pull --no-tty --ca-file "$P/ca-poc.crt" -o "$T/f-$i" "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$(cat "$T/fermeture-$i.digest")" > /dev/null
    echo "fermeture $i : $(find "$T/f-$i" -type f | wc -l) fichiers, contenu $(contenu "$T/f-$i")"
  done
  rm -rf -- "${T:?}/f-hote"; oras pull --no-tty --ca-file "$P/ca-poc.crt" -o "$T/f-hote" "$REG_HOTE/entrees/sample-app/fermeture@$FERMETURE_HOTE" > /dev/null
  echo "fermeture de l'hôte (${FERMETURE_HOTE:0:15}…) : $(find "$T/f-hote" -type f | wc -l) fichiers, contenu $(contenu "$T/f-hote")"
  diff <(cd "$T/f-1" && find . -type f -exec sha256sum {} + | sort -k2) <(cd "$T/f-hote" && find . -type f -exec sha256sum {} + | sort -k2) | sed 's/^/     /' | head -20 || true
  [ "$(cat "$T/fermeture-1.digest")" = "$(cat "$T/fermeture-2.digest")" ] && echo "OK   deux prefetch du même commit : même fermeture" \
    || echo "CONSTAT deux prefetch du même commit : fermetures différentes ($(cat "$T/fermeture-1.digest") / $(cat "$T/fermeture-2.digest"))"
}

etape_provenance() {
  local d uid
  d=$(cat "$T/fermeture-1.digest"); uid=$(kubectl get pipelinerun -n builds f2-prefetch-1 -o jsonpath='{.metadata.uid}')
  cosign verify-attestation --key "$here/resultats/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" \
    "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$d" > "$T/att.json" 2> "$T/cosign.err" || { cat "$T/cosign.err" >&2; exit 1; }
  echo "OK   cosign verify-attestation : $(wc -l < "$T/att.json") enveloppe(s) valide(s) sur la fermeture $d"
  jq -c --arg u "$uid" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$T/att.json" > "$T/prov.json"
  attendu "enveloppes du PipelineRun f2-prefetch-1" "$(wc -l < "$T/prov.json")" 1
  jq -r '"sujet : \(.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(", "))", "buildType : \(.predicate.buildDefinition.buildType)",
    "resolvedDependencies :", (.predicate.buildDefinition.resolvedDependencies[] | "  \(.name // "-") \(.uri // "-") \(.digest // {} | to_entries | map(.key + ":" + .value) | join(","))\(if .content then " (contenu)" else "" end)")' "$T/prov.json"
  attendu "sujet" "$(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$T/prov.json")" "$DEPOT_FERMETURE@$d"
  attendu "source" "$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == "git+https://sc-stockage.poc.test:3000/'"$SAMPLE_APP"'.git") | "sha1:" + .digest.sha1' "$T/prov.json")" "sha1:$TETE_J2"
  attendu "image d'outils du prefetch" "$(jq -r --arg u "oci://$REG/$DEPOT_OUTILS" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json" | sort -u)" "$PREFETCH_DIGEST"
  attendu "tâche prefetch-gomod (bundle)" "$(jq -r --arg u "$REG/tekton/tasks/prefetch-gomod" '.predicate.buildDefinition.resolvedDependencies[]
    | select(.name == "pipelineTask" and .uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json")" "$(cut -d@ -f2 "$T/prefetch-gomod.ref")"
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$T/autre.pub" 2> /dev/null
  refus "provenance vérifiée avec une autre clé" "no matching attestations|invalid signature|signature" \
    cosign verify-attestation --key "$T/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$d"
}

lancer() {
  [ $# -gt 0 ] || { echo "usage : $0 $(declare -F | awk '$3 ~ /^etape_/ {sub("etape_", "", $3); printf "%s|", $3}' | sed 's/|$//')…" >&2; exit 2; }
  for e in "$@"; do declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }; done
  for e in "$@"; do
    { echo "# ${0##*/} $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/f2-$e.log"
  done
}
lancer "$@"
