#!/usr/bin/env bash
# Brique 08, J7 : réseau Cilium 1.20.4 à la place de flannel et de kube-router (option 1b du contrôle de sortie de la zone build ;
# plan du README accordé par le propriétaire le 30/10/2026 ; installé par k3s.sh avec RESEAU=cilium).
#   telecharger  sur l'hôte, avant tout démontage : chart OCI vérifié par cosign (identité relevée release.yaml@refs/heads/main ;
#                témoin : identité du tag refusée), archive du chart (sha256 égal au digest publié par helm.cilium.io) ; images
#                cilium et operator-generic : index vérifié par cosign (identité documentée au tag ; témoin : autre tag refusé),
#                manifeste amd64 listé par l'index, archive OCI amd64 nommée par son tag et par son digest (le chart référence
#                l'image par digest) ; HelmChart rendu (chart en base64, cilium/valeurs.yaml) ; empreintes dans sums.txt
#   appliquer    HelmChart rendu de nouveau (cilium/valeurs.yaml modifié), installé sur sc-confiance (sha256 revérifié), mise à
#                jour par le contrôleur Helm de k3s, agents et opérateur redémarrés (le chart ne le fait pas), configuration relue
#   verifier     après J1 (point d'arrêt du rejeu), prédiction d'abord : nœuds prêts, agents et opérateur prêts, images importées
#                (digest amd64, aucun tirage), podCIDRs repris de k3s, état des agents, flannel et kube-router absents, binaire
#                hubble dans l'agent, mémoire des agents
# Retrait : rejeu avec RESEAU=flannel (cluster recréé).
#
# Usage (racine du dépôt) : mise run confiance:cilium -- <étape>…   (journal : resultats/cilium-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
CILIUM_VER=1.20.4
CHART=quay.io/cilium/charts/cilium
CHART_MANIFESTE=sha256:712e1f65bf30533d117d1996ac3ace3efdb2521302d31ee887b1e45806bd6b64
CHART_TGZ=sha256:505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed   # digest publié par helm.cilium.io/index.yaml
CHART_ID=https://github.com/cilium/cilium/.github/workflows/release.yaml@refs/heads/main            # relevée par refus volontaire
IMAGES_ID=https://github.com/cilium/cilium/.github/workflows/build-images-releases.yaml@refs/tags/v$CILIUM_VER   # documentée
OIDC=https://token.actions.githubusercontent.com
declare -A INDEX=(   # index multi-plateformes épinglés par le chart (values.yaml)
  [cilium]=sha256:20fe92e4c86641233a450098c158d2d29085f3419931ab6bf681d2485dedf16e
  [operator-generic]=sha256:7a7a3489dc66ad67e420d285c8a8d2e169b0957ad15e120f593d27081bf38d82)
declare -A AMD64=(   # manifestes linux/amd64 listés par ces index
  [cilium]=sha256:fa56fecd779584642c7ec2da6872c03c45c1f1043da66665a73ed8c425584d54
  [operator-generic]=sha256:77a9b4371faed41dc9c2fb3942b6c02a581158be1d4aa46a0e62956ce2f55ff1)
D=$O/telechargements/cilium
T=$W/cilium
mkdir -p "$D" "$T"

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }

signature() { # libellé identité référence : cosign verify (code de retour, types vérifiés et digest, ou motif du refus)
  local rc=0
  cosign verify --certificate-identity "$2" --certificate-oidc-issuer "$OIDC" "$3" > "$T/verify.json" 2> "$T/verify.err" || rc=$?
  if [ "$rc" = 0 ]; then echo "$1 : vérifiée ($(jq -r '[.[].critical.type] | join(", ")' "$T/verify.json")), digest $(jq -r '.[0].critical.image."docker-manifest-digest"' "$T/verify.json")"
  else echo "$1 : refusée ($(grep -o -m1 'expected SAN value "[^"]*", got "[^"]*"' "$T/verify.err" || tail -1 "$T/verify.err"))"; fi
  return "$rc"
}

archive() { # nom : archive OCI linux/amd64 de quay.io/cilium/<nom>, nommée par tag et par digest, dans $D/<nom>-amd64.tar
  local n=$1 l=$T/$1-oci
  rm -rf -- "${T:?}/$n-oci"
  crane pull --format oci "quay.io/cilium/$n@${AMD64[$n]}" "$l"
  attendu "$n : manifeste du layout" "$(jq -r '.manifests | map(.digest) | join(",")' "$l/index.json")" "${AMD64[$n]}"
  jq --arg t "quay.io/cilium/$n:v$CILIUM_VER" --arg d "quay.io/cilium/$n@${AMD64[$n]}" --arg v "v$CILIUM_VER" \
    '.manifests = [(.manifests[0] + {annotations: {"io.containerd.image.name": $t, "org.opencontainers.image.ref.name": $v}}),
                   (.manifests[0] + {annotations: {"io.containerd.image.name": $d}})]' "$l/index.json" > "$l/index.tmp"
  mv "$l/index.tmp" "$l/index.json"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$l" -cf "$D/$n-amd64.tar" oci-layout index.json blobs
  echo "$n : archive $(du -m "$D/$n-amd64.tar" | cut -f1) Mo, noms $(jq -r '[.manifests[].annotations["io.containerd.image.name"]] | join(" et ")' "$l/index.json")"
}

etape_telecharger() {
  local n i s
  echo "## chart $CHART:$CILIUM_VER"
  signature "chart (identité $CHART_ID)" "$CHART_ID" "$CHART:$CILIUM_VER"
  attendu "chart : manifeste signé" "$(jq -r '.[0].critical.image."docker-manifest-digest"' "$T/verify.json")" "$CHART_MANIFESTE"
  ! signature "témoin : chart avec l'identité du tag" "$IMAGES_ID" "$CHART:$CILIUM_VER" || { echo "KO   témoin accepté" >&2; exit 1; }
  attendu "chart : couche du manifeste signé" "$(crane manifest "$CHART@$CHART_MANIFESTE" | jq -r '.layers | map(.digest) | join(",")')" "$CHART_TGZ"
  crane blob "$CHART@$CHART_TGZ" > "$D/cilium-$CILIUM_VER.tgz"
  attendu "chart : archive (digest de helm.cilium.io)" "sha256:$(sha256sum < "$D/cilium-$CILIUM_VER.tgz" | cut -c1-64)" "$CHART_TGZ"
  echo "## images (identité documentée $IMAGES_ID)"
  for n in cilium operator-generic; do
    signature "quay.io/cilium/$n:v$CILIUM_VER" "$IMAGES_ID" "quay.io/cilium/$n@${INDEX[$n]}"
    attendu "$n : index signé" "$(jq -r '.[0].critical.image."docker-manifest-digest"' "$T/verify.json")" "${INDEX[$n]}"
    i=$(crane manifest "quay.io/cilium/$n@${INDEX[$n]}" | jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest')
    attendu "$n : manifeste linux/amd64 listé par l'index" "$i" "${AMD64[$n]}"
    archive "$n"
  done
  ! signature "témoin : cilium avec l'identité du tag v1.20.3" "${IMAGES_ID%v$CILIUM_VER}v1.20.3" "quay.io/cilium/cilium@${INDEX[cilium]}" \
    || { echo "KO   témoin accepté" >&2; exit 1; }
  rendre_helmchart
  du -sm "$D" | awk '{print "téléchargements : " $1 " Mo"}'
}

rendre_helmchart() { # $D/cilium-helmchart.yaml (chart vérifié en base64, cilium/valeurs.yaml, digests amd64) ; empreintes dans sums.txt
  echo "## HelmChart (chart en base64, valeurs de cilium/valeurs.yaml, digests amd64)"
  attendu "chart : archive" "sha256:$(sha256sum < "$D/cilium-$CILIUM_VER.tgz" | cut -c1-64)" "$CHART_TGZ"
  sed -e "s#@CILIUM_AMD64@#${AMD64[cilium]}#" -e "s#@OPERATOR_AMD64@#${AMD64[operator-generic]}#" "$here/cilium/valeurs.yaml" \
    | grep -v '^#' > "$T/valeurs.yaml"
  ! grep -n '@[A-Z0-9_]*@' "$T/valeurs.yaml" || { echo "KO   variable non rendue" >&2; exit 1; }
  { printf 'apiVersion: helm.cattle.io/v1\nkind: HelmChart\nmetadata:\n  name: cilium\n  namespace: kube-system\nspec:\n'
    printf '  bootstrap: true\n  targetNamespace: kube-system\n  chartContent: %s\n  valuesContent: |-\n' "$(base64 -w0 < "$D/cilium-$CILIUM_VER.tgz")"
    sed 's/^/    /' "$T/valeurs.yaml"; } > "$D/cilium-helmchart.yaml"
  (cd "$D" && sha256sum cilium-amd64.tar operator-generic-amd64.tar cilium-helmchart.yaml > sums.txt)
  sed 's/^/  /' "$D/sums.txt"
}

etape_appliquer() {
  local g
  rendre_helmchart
  g=$(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.creationTimestamp}')
  scp -q "${SSH_OPTS[@]}" "$D/cilium-helmchart.yaml" "poc@${IP[sc-confiance]}:/tmp/cilium-helmchart.yaml"
  sur sc-confiance "echo '$(grep ' cilium-helmchart.yaml$' "$D/sums.txt" | cut -c1-64)  /tmp/cilium-helmchart.yaml' | sha256sum -c \
    && sudo install -m 0600 /tmp/cilium-helmchart.yaml /var/lib/rancher/k3s/server/manifests/cilium.yaml && rm -f /tmp/cilium-helmchart.yaml"
  for _ in $(seq 60); do
    [ "$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.policy-cidr-match-mode}' 2>/dev/null)" = nodes ] && break; sleep 2
  done
  echo "cilium-config : policy-cidr-match-mode=$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.policy-cidr-match-mode}')"
  kubectl -n kube-system rollout restart ds/cilium deploy/cilium-operator > /dev/null
  kubectl -n kube-system rollout status ds/cilium --timeout=300s > /dev/null
  kubectl -n kube-system rollout status deploy/cilium-operator --timeout=300s > /dev/null
  attendu "DaemonSet cilium prêt" "$(kubectl -n kube-system get ds cilium -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}')" 3/3
  echo "agents recréés après $g : $(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{range .items[*]}{.spec.nodeName}={.metadata.creationTimestamp} {end}')"
  attendu "policy-cidr-match-mode lu par l'agent de sc-confiance" "$(kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg config --all 2>/dev/null | awk '$1 ~ /PolicyCIDRMatchMode/ {print $NF}' | head -1)" "[nodes]"
}

etape_verifier() {
  local n p v
  echo "## prédiction (écrite le 30/10/2026, avant le premier démarrage de k3s avec Cilium)"
  echo "- trois nœuds prêts ; DaemonSet cilium prêt sur les trois (3/3), opérateur prêt (1/1) sur sc-confiance ; HelmChart installé"
  echo "- images des pods de Cilium : digests des manifestes amd64 (${AMD64[cilium]:7:12}, ${AMD64[operator-generic]:7:12}), importées"
  echo "  depuis les archives (événements « already present on machine », aucun « Pulling »)"
  echo "- podCIDRs des CiliumNodes égaux à ceux de k3s (10.42.N.0/24) ; pods système dans le podCIDR de leur nœud"
  echo "- cilium-dbg status : OK sur les trois agents ; ni interface flannel.1 ni règle KUBE-ROUTER sur les nœuds"
  echo "- binaire hubble présent dans l'agent, flux lisibles (hubble observe)"
  echo "## nœuds"
  kubectl get nodes -o wide -L zone
  kubectl wait node --all --for=condition=Ready --timeout=300s > /dev/null && echo "OK   nœuds prêts"
  kubectl -n kube-system rollout status ds/cilium --timeout=300s > /dev/null
  kubectl -n kube-system rollout status deploy/cilium-operator --timeout=300s > /dev/null
  echo "HelmChart cilium : job $(kubectl -n kube-system get job helm-install-cilium -o jsonpath='{.status.succeeded}' 2>/dev/null || echo -) réussi"
  attendu "DaemonSet cilium prêt" "$(kubectl -n kube-system get ds cilium -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}')" 3/3
  attendu "opérateur prêt, sur" "$(kubectl -n kube-system get pods -l name=cilium-operator -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready} {.spec.nodeName}{end}')" "true sc-confiance"
  echo "## images"
  kubectl -n kube-system get pods -o json | jq '[.items[] | select(.metadata.labels["app.kubernetes.io/part-of"] == "cilium")]' > "$T/pods.json"
  jq -r '.[] | "\(.metadata.name) sur \(.spec.nodeName) : " + ([.status.containerStatuses[] | "\(.name) \(.imageID | sub(".*@"; ""))"] | join(", "))' "$T/pods.json"
  n=$(jq -r '[.[].status.containerStatuses[].imageID | sub(".*@"; "")] | unique | join(",")' "$T/pods.json")
  attendu "digests des images en cours" "$n" "$(printf '%s\n' "${AMD64[cilium]}" "${AMD64[operator-generic]}" | sort | paste -sd,)"
  kubectl -n kube-system get events -o json | jq -r '[.items[] | select(.involvedObject.kind == "Pod" and (.involvedObject.name | test("^cilium")))
    | select(.reason == "Pulled" or .reason == "Pulling")] | group_by(.reason) | map("\(.[0].reason) : \(length), \(.[0].message | .[0:120])") | .[]'
  attendu "événements Pulling des pods de Cilium" "$(kubectl -n kube-system get events -o json | jq '[.items[] | select(.involvedObject.kind == "Pod" and (.involvedObject.name | test("^cilium")) and .reason == "Pulling")] | length')" 0
  echo "## adresses"
  for n in sc-confiance sc-build sc-stockage; do
    attendu "podCIDRs de $n (CiliumNode / k3s)" "$(kubectl get ciliumnode "$n" -o jsonpath='{.spec.ipam.podCIDRs}')" "$(kubectl get node "$n" -o jsonpath='{.spec.podCIDRs}')"
  done
  kubectl get pods -A -o json | jq -r '.items[] | select(.spec.hostNetwork != true and .status.podIP != null) | "\(.metadata.namespace)/\(.metadata.name) \(.spec.nodeName) \(.status.podIP)"' | tee "$T/ip.txt"
  echo "## agents"
  for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[*].metadata.name}'); do
    v=$(kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg status --brief 2>&1 | tail -1)
    echo "$p ($(kubectl -n kube-system get pod "$p" -o jsonpath='{.spec.nodeName}')) : cilium-dbg status --brief : $v ; hubble : $(kubectl -n kube-system exec "$p" -c cilium-agent -- hubble version 2>&1 | head -1)"
  done
  p=$(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
  echo "flux récents (hubble observe --last 3 dans $p) :"
  kubectl -n kube-system exec "$p" -c cilium-agent -- hubble observe --last 3 2>&1 | sed 's/^/  /'
  for n in sc-confiance sc-build sc-stockage; do
    echo "$n : flannel.1 $(sur "$n" 'ip -br link show flannel.1 2>/dev/null | wc -l'), règles KUBE-ROUTER $(sur "$n" 'sudo iptables -S' | grep -c KUBE-ROUTER || true), RSS de cilium-agent $(sur "$n" 'ps -C cilium-agent -o rss= | awk "{s += \$1} END {printf \"%d Mo\", s / 1024}"')"
  done
}

lancer cilium J7 "$@"
