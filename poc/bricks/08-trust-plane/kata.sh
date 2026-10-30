#!/usr/bin/env bash
# Brique 08, jalon J7 : isolation par Kata Containers 4.3.1 sur sc-build.
#   verifier   sans rien installer : tag et release 4.3.1 (immuable, attestation de release GitHub) ; archive kata-static
#              (empreinte, attestation de release, attestation de build cherchée, contenu, configuration du shim par
#              défaut qemu-runtime-rs) ; chart et image kata-deploy (empreinte, digests des deux registres, signatures,
#              referrers et attestations cherchés, permissions des jobs de publication de l'image)
#   installer  méthode « archive attestée » (accord du propriétaire du 30/10/2026) : fichiers lus par qemu-runtime-rs
#              extraits sur l'hôte de l'archive revérifiée, manifeste sha256 (resultats/kata-manifeste.txt), copiés dans
#              /opt/kata de sc-build et contrôlés sur place ; fichier d'appoint de containerd (kata/containerd-kata.toml) ;
#              k3s-agent redémarré sur sc-build s'il le faut (rattrapage suspendu, aucun PipelineRun ni pod actif sur
#              le nœud), runtime kata relu dans crictl info ; RuntimeClass kata (kata/runtimeclass.yaml)
#   essais     pods de builds conformes à restricted, prédiction d'abord : runc et Kata comparés (noyau, vCPU,
#              mémoire, niveau x86-64 par ld.so, seccomp), annotation default_memory non transmise, pod Kata
#              privilégié refusé par Pod Security dans builds
#   temoin     après un redémarrage des VM (redemarrer.sh) : runtime kata rechargé par containerd, pod Kata lancé dans l'invité
# Retrait : supprimer /opt/kata et le fichier d'appoint sur sc-build, redémarrer k3s-agent, supprimer la RuntimeClass.
#
# Usage (racine du dépôt) : mise run confiance:kata -- <étape>…   (journal : resultats/kata-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
KATA_DEPOT=kata-containers/kata-containers
KATA_VER=4.3.1
KATA_COMMIT=03cf2ec06a5d302f23af811744f6bcea49988bfb   # tag léger 4.3.1
KATA_STATIC=kata-static-4.3.1-amd64.tar.zst
KATA_STATIC_SHA=1463a2b86845f4d3d8e87f2f764ec59856fc0fee3520967a79ade32762be2e97
KD_CHART=kata-deploy-4.3.1.tgz
KD_CHART_SHA=c25077416d37c178bf72df0204ea3ba89418efad1b1299b0d5d34ec02556187e
KD_IMAGE=kata-containers/kata-deploy
KD_QUAY=sha256:7399058e3e6378a766770345abcf9b20b53611a419b1b56e71162c6ac1bf625a   # index quay.io, tag 4.3.1
KD_GHCR=sha256:9f6bbd0972e6fa8c99f5a86b24503032cb87be602d22e830d1c917ba31b4db9f   # index ghcr.io, même tag
KD_CONFIG=sha256:3a70f8106d66d62e8e701f87b2c7f9ffdbdeeed11be1b840e4e5ecc82d968da5   # config linux/amd64 des deux index
SHIM_CONF=/opt/kata/share/defaults/kata-containers/runtime-rs/configuration-qemu-runtime-rs.toml
KATA_FICHIERS=(   # lus par qemu-runtime-rs (shim ; path, kernel, image, virtio_fs_daemon de la configuration ; cibles des liens)
  opt/kata/VERSION
  opt/kata/runtime-rs/bin/containerd-shim-kata-v2
  "${SHIM_CONF#/}"
  opt/kata/bin/qemu-system-x86_64
  opt/kata/share/kata-qemu/qemu
  opt/kata/share/kata-containers/vmlinux.container
  opt/kata/share/kata-containers/vmlinux-6.18.56-208
  opt/kata/share/kata-containers/kata-containers.img
  opt/kata/share/kata-containers/kata-ubuntu-resolute.image
  opt/kata/libexec/virtiofsd
)
DROPIN=/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d/kata.toml
BUSYBOX=$REG/amont/rancher/mirrored-library-busybox@sha256:ad9fa4d07136a83e69a54ef00102f579d04eba431932de3b0f098cc5d5948f9f   # amd64, glibc (tekton.sh miroir)
DL=$O/telechargements/kata
T=$W/kata
mkdir -p "$T" "$DL"

telecharger() { # url fichier
  [ -s "$DL/$2" ] || { curl -fsSL -o "$DL/$2.part" "$1" && mv "$DL/$2.part" "$DL/$2"; }
}

attestation_build() { # cible [options de gh attestation verify] : CONSTAT si absente (HTTP 404), KO sinon
  if gh attestation verify "$@" --repo "$KATA_DEPOT" > "$T/att.out" 2>&1; then
    echo "KO   attestation de build trouvée pour $1, à exploiter" >&2; cat "$T/att.out" >&2; exit 1
  elif grep -qF 'HTTP 404' "$T/att.out"; then echo "CONSTAT $1 : aucune attestation de build (gh attestation verify : HTTP 404)"
  else echo "KO   gh attestation verify $1 :" >&2; cat "$T/att.out" >&2; exit 1; fi
}

taille() { # chemin de l'archive (absolu) : taille en octets, liens symboliques suivis (liste de l'archive)
  local p=$1 l
  for _ in 1 2 3; do
    l=$(awk -v p=".$p" '$6 == p' "$T/liste.txt")
    [ -n "$l" ] || { echo "KO   $p absent de l'archive" >&2; exit 1; }
    case $l in
      l*) p=$(dirname "$p")/$(awk '{print $8}' <<<"$l") ;;
      *) awk '{print $3}' <<<"$l"; return ;;
    esac
  done
  echo "KO   $1 : trop de liens" >&2; exit 1
}

mo() { awk -v t="$1" -v f="$2" 'BEGIN {printf "%7.1f Mo  %s\n", t / 1e6, f}'; }   # octets libellé

permissions_job() { # workflow job : bloc permissions du job, au commit du tag
  gh api -H 'Accept: application/vnd.github.raw' "repos/$KATA_DEPOT/contents/.github/workflows/$1?ref=$KATA_COMMIT" \
    | awk -v j="  $2:" '$0 == j {d=1; next} d && /^  [a-z]/ {exit} d && /^    permissions:/ {p=1; next} p && /^      / {print; next} p {exit}'
}

etape_verifier() {
  local f s d m n c t total
  echo "## tag et release $KATA_VER"
  [ "$(gh api "repos/$KATA_DEPOT/git/ref/tags/$KATA_VER" --jq '.object.type + " " + .object.sha')" = "commit $KATA_COMMIT" ] \
    && [ "$(gh api "repos/$KATA_DEPOT/commits/$KATA_COMMIT" --jq '.commit.verification.verified')" = true ] \
    && echo "OK   tag léger $KATA_VER → commit $KATA_COMMIT, signé et vérifié par GitHub" || { echo "KO   tag $KATA_VER" >&2; exit 1; }
  [ "$(gh api "repos/$KATA_DEPOT/releases/tags/$KATA_VER" --jq .immutable)" = true ] && echo "OK   release immuable" \
    || { echo "KO   release $KATA_VER non immuable" >&2; exit 1; }
  gh release verify "$KATA_VER" --repo "$KATA_DEPOT" > "$T/release.out" 2>&1 && grep -qF "Release $KATA_VER verified" "$T/release.out" \
    && echo "OK   attestation de release vérifiée (gh release verify) : $(grep -F 'Resolved tag' "$T/release.out")" \
    || { cat "$T/release.out" >&2; echo "KO   attestation de release" >&2; exit 1; }

  for f in "$KATA_STATIC $KATA_STATIC_SHA" "$KD_CHART $KD_CHART_SHA"; do
    set -- $f
    echo "## $1"
    telecharger "https://github.com/$KATA_DEPOT/releases/download/$KATA_VER/$1" "$1"
    echo "$2  $DL/$1" | sha256sum -c --quiet && echo "OK   sha256 $2 (épinglé), $(stat -c %s "$DL/$1") octets"
    gh release verify-asset "$KATA_VER" "$DL/$1" --repo "$KATA_DEPOT" > "$T/asset.out" 2>&1 \
      && grep -qF "is present in release $KATA_VER" "$T/asset.out" \
      && echo "OK   présent dans l'attestation de release $KATA_VER (gh release verify-asset)" \
      || { cat "$T/asset.out" >&2; echo "KO   $1 absent de l'attestation de release" >&2; exit 1; }
    attestation_build "$DL/$1"
  done
  echo "le workflow build-kata-static-tarball-amd64.yaml atteste chaque composant poussé sur ghcr.io, pas l'archive fusionnée"

  echo "## contenu de $KATA_STATIC"
  zstd -dc "$DL/$KATA_STATIC" | tar -tv > "$T/liste.txt"
  echo "$(wc -l < "$T/liste.txt") entrées, $(awk '{s += $3} END {printf "%.2f", s / 1e9}' "$T/liste.txt") Go décompressés, sous /opt/kata"
  [ "$(awk '$6 !~ /^\.\/(opt\/(kata(\/.*)?)?)?$/' "$T/liste.txt" | wc -l)" = 0 ] && echo "OK   aucune entrée hors de /opt/kata" \
    || { echo "KO   entrées hors de /opt/kata" >&2; exit 1; }
  for f in /opt/kata/runtime-rs/bin/containerd-shim-kata-v2 "$SHIM_CONF"; do echo "présent : $f ($(taille "$f") octets)"; done
  for f in /opt/kata/bin/containerd-shim-kata-v2 /opt/kata/share/defaults/kata-containers/configuration-qemu.toml; do
    awk -v p=".$f" '$6 == p' "$T/liste.txt" | grep -q . && { echo "KO   $f présent" >&2; exit 1; } || echo "absent  : $f"
  done
  echo "CONSTAT runtime Go absent de kata-static (publié à part, kata-go-static, 1,3 Go) ; configuration.toml pointe vers $(awk '$6 == "./opt/kata/share/defaults/kata-containers/configuration.toml" {print $8}' "$T/liste.txt"), absent"

  echo "## configuration du shim par défaut (qemu-runtime-rs, défaut de kata-deploy en 4.x)"
  rm -rf "$T/x" && mkdir -p "$T/x"
  zstd -dc "$DL/$KATA_STATIC" | tar -x -C "$T/x" ".$SHIM_CONF"
  c=$T/x$SHIM_CONF
  grep -E '^(path|kernel|image|machine_type|rootfs_type|enable_annotations|cpu_features|default_vcpus|default_memory|overhead_vcpus|overhead_memory|shared_fs|virtio_fs_daemon|rootless|disable_nesting_checks|internetworking_model|disable_guest_seccomp|sandbox_cgroup_only|static_sandbox_resource_mgmt|disable_guest_selinux) ' "$c"
  grep -q '^disable_guest_seccomp = true$' "$c" \
    && echo "CONSTAT disable_guest_seccomp = true : le profil seccomp déclaré dans le pod n'est pas appliqué dans l'invité"
  echo "CONSTAT enable_annotations : un pod peut changer kernel_params, default_vcpus et default_memory si containerd lui transmet les annotations (pod_annotations)"
  total=0
  for f in /opt/kata/runtime-rs/bin/containerd-shim-kata-v2 "$SHIM_CONF" \
      $(awk -F' = ' '$1 ~ /^(path|kernel|image|virtio_fs_daemon)$/ {gsub(/"/, "", $2); print $2}' "$c"); do
    t=$(taille "$f"); total=$((total + t)); mo "$t" "$f"
  done
  t=$(awk '$6 ~ /^\.\/opt\/kata\/share\/kata-qemu\/qemu\/./ {s += $3} END {print s}' "$T/liste.txt"); total=$((total + t))
  mo "$t" "/opt/kata/share/kata-qemu/qemu/ (micrologiciels de QEMU)"
  mo "$total" "fichiers lus par qemu-runtime-rs, sur $(awk '{s += $3} END {printf "%.2f", s / 1e9}' "$T/liste.txt") Go"

  echo "## chart $KD_CHART : images"
  tar -xzOf "$DL/$KD_CHART" kata-deploy/values.yaml | awk '/^(image|kubectlImage):/ {i=$1} i && /^  (reference|tag):/ {print i, $0} /^$/ {i=""}'
  echo "CONSTAT le chart désigne ses images par tag (kata-deploy au tag de appVersion, kubectl au tag latest), pas par digest"

  echo "## image $KD_IMAGE:$KATA_VER"
  for f in "quay.io $KD_QUAY" "ghcr.io $KD_GHCR"; do
    set -- $f
    d=$(crane digest "$1/$KD_IMAGE:$KATA_VER")
    [ "$d" = "$2" ] && echo "OK   $1 : index $d (= épinglé)" || { echo "KO   $1 : index $d ≠ $2" >&2; exit 1; }
    m=$(crane digest --platform linux/amd64 "$1/$KD_IMAGE@$2")
    c=sha256:$(crane config --platform linux/amd64 "$1/$KD_IMAGE@$2" | sha256sum | cut -c1-64)
    [ "$c" = "$KD_CONFIG" ] || { echo "KO   $1 : config amd64 $c" >&2; exit 1; }
    crane manifest "$1/$KD_IMAGE@$m" | jq -r '.layers[].digest' > "$T/couches-$1.txt"
    echo "     linux/amd64 $m, config $c, $(wc -l < "$T/couches-$1.txt") couches, $(crane manifest "$1/$KD_IMAGE@$m" | jq '[.layers[].size] | add / 1e9 | . * 100 | round / 100') Go compressés"
    n=$(crane ls "$1/$KD_IMAGE" | grep -c '^sha256-' || true)
    echo "     tags sha256-* (signatures et attestations cosign) dans le dépôt : $n"
    echo "     referrers de l'index : $(oras discover --format json "$1/$KD_IMAGE@$2" | jq '.referrers | length')"
  done
  echo "même config amd64 sur les deux registres, donc mêmes couches décompressées (diff_ids) ; couches compressées propres à chacun :"
  for f in "quay.io -23" "ghcr.io -13"; do
    set -- $f
    for d in $(comm "$2" <(sort "$T/couches-quay.io.txt") <(sort "$T/couches-ghcr.io.txt")); do
      crane blob "$1/$KD_IMAGE@$d" > "$T/couche.gz"
      echo "     $1 $d : en-tête gzip $(head -c 10 "$T/couche.gz" | od -An -tx1 | tr -s ' '), décompressée sha256:$(gzip -dc "$T/couche.gz" | sha256sum | cut -c1-64), $(gzip -dc "$T/couche.gz" | tar -tf - | paste -sd' ')"
    done
  done
  attestation_build "oci://ghcr.io/$KD_IMAGE@$KD_GHCR"
  attestation_build "oci://ghcr.io/$KD_IMAGE@$(crane digest --platform linux/amd64 "ghcr.io/$KD_IMAGE@$KD_GHCR")"
  echo "permissions du job kata-deploy (release-amd64.yaml, au commit du tag) :"; permissions_job release-amd64.yaml kata-deploy | tee "$T/perm.txt"
  echo "permissions du job publish-multi-arch-images (release.yaml) :"; permissions_job release.yaml publish-multi-arch-images | tee -a "$T/perm.txt"
  [ -s "$T/perm.txt" ] || { echo "KO   permissions des jobs illisibles" >&2; exit 1; }
  grep -q 'id-token' "$T/perm.txt" && { echo "KO   id-token présent : chercher la signature" >&2; exit 1; } \
    || echo "CONSTAT image kata-deploy non vérifiable par construction : les jobs qui la publient n'ont pas id-token (ni signature sans clé, ni attestation possibles)"
}

conforme_vm() { # /opt/kata de sc-build conforme au manifeste : fichiers (sha256), liens, aucun fichier ni lien en trop
  sur sc-build "cd / && sha256sum -c --quiet" < "$T/manifeste.sha256" > "$T/vm.out" 2>&1 || return 1
  [ "$(sur sc-build 'cd / && find opt/kata -type l -printf "%p -> %l\n" | sort')" = "$(grep -F ' -> ' "$R/kata-manifeste.txt")" ] \
    && [ "$(sur sc-build 'find /opt/kata -type f | wc -l')" = "$(wc -l < "$T/manifeste.sha256")" ]
}

runtime_kata() { # section kata du runtime CRI chargé par containerd sur sc-build (crictl info), vide si absente
  sur sc-build 'sudo k3s crictl info' 2>/dev/null | jq -c '.config.containerd.runtimes.kata // empty | {runtimeType, runtimePath,
    privileged_without_host_devices, PodAnnotations, ContainerAnnotations, ConfigPath: .options.ConfigPath}' 2>/dev/null || true
}

etape_installer() {
  local n redemarrer=0 r
  echo "## archive $KATA_STATIC"
  echo "$KATA_STATIC_SHA  $DL/$KATA_STATIC" | sha256sum -c --quiet && echo "OK   sha256 $KATA_STATIC_SHA, revérifié avant l'extraction"
  echo "## fichiers lus par qemu-runtime-rs, extraits sur l'hôte (liens conservés)"
  mkdir -p "$T/charge"
  zstd -dc "$DL/$KATA_STATIC" | tar -x -C "$T/charge" "${KATA_FICHIERS[@]/#/./}"
  (cd "$T/charge" && find "${KATA_FICHIERS[@]}" -type f -print0 | sort -z | xargs -0 sha256sum \
    && find "${KATA_FICHIERS[@]}" -type l -printf '%p -> %l\n' | sort) > "$R/kata-manifeste.txt"
  grep -vF ' -> ' "$R/kata-manifeste.txt" > "$T/manifeste.sha256"
  echo "manifeste (resultats/kata-manifeste.txt) : $(wc -l < "$T/manifeste.sha256") fichiers, $(grep -cF ' -> ' "$R/kata-manifeste.txt") liens, $(cd "$T/charge" && du -cb "${KATA_FICHIERS[@]}" | tail -1 | awk '{printf "%.1f Mo", $1 / 1e6}')"
  echo "## /opt/kata sur sc-build"
  if conforme_vm; then echo "déjà en place"
  else
    tar -C "$T/charge" -cf - "${KATA_FICHIERS[@]}" | sur sc-build 'sudo tar -C / --no-same-owner -xf -'
    conforme_vm || { cat "$T/vm.out" >&2; echo "KO   /opt/kata de sc-build non conforme au manifeste" >&2; exit 1; }
  fi
  echo "OK   /opt/kata de sc-build conforme au manifeste (sha256 de chaque fichier, liens, aucun fichier en trop) ; $(sur sc-build 'stat -c "%U:%G %a" /opt/kata/runtime-rs/bin/containerd-shim-kata-v2 /opt/kata/bin/qemu-system-x86_64' | paste -sd' ')"
  echo "## containerd : fichier d'appoint $DROPIN"
  if sur sc-build "sudo cat $DROPIN 2>/dev/null" | cmp -s - "$here/kata/containerd-kata.toml"; then echo "déjà en place, identique au fichier versionné"
  else
    sur sc-build "sudo mkdir -p ${DROPIN%/*} && sudo tee $DROPIN >/dev/null && sudo chmod 0644 $DROPIN" < "$here/kata/containerd-kata.toml"
    redemarrer=1
  fi
  [ -n "$(runtime_kata)" ] || redemarrer=1
  if [ "$redemarrer" = 1 ]; then
    echo "## redémarrage de k3s-agent sur sc-build (containerd embarqué)"
    kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":true}}' >/dev/null
    trap 'kubectl patch cronjob -n declencheurs rattrapage --type merge -p '"'"'{"spec":{"suspend":false}}'"'"' >/dev/null' EXIT
    for _ in $(seq 60); do [ -z "$(kubectl get cronjob -n declencheurs rattrapage -o jsonpath='{.status.active}')" ] && break; sleep 2; done
    n=$(kubectl get pipelineruns -n builds -o json | jq '[.items[] | select(.status.completionTime == null)] | length')
    r=$(kubectl get pods -A --field-selector spec.nodeName=sc-build,status.phase=Running -o name | wc -l)
    [ "$n" = 0 ] && [ "$r" = 0 ] && echo "rattrapage suspendu ; aucun PipelineRun actif, aucun pod en cours sur sc-build" \
      || { echo "KO   $n PipelineRun(s) actif(s), $r pod(s) en cours sur sc-build : redémarrage reporté" >&2; exit 1; }
    sur sc-build 'sudo systemctl restart k3s-agent'
    for _ in $(seq 60); do [ -n "$(runtime_kata)" ] && break; sleep 2; done
    kubectl wait --for=condition=Ready node/sc-build --timeout=180s >/dev/null
    kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":false}}' >/dev/null
    trap - EXIT
    echo "k3s-agent : $(sur sc-build 'systemctl is-active k3s-agent') ; sc-build Ready ; rattrapage réactivé"
  fi
  r=$(runtime_kata)
  echo "runtime kata chargé par containerd : $r"
  jq -e --arg c "$SHIM_CONF" '.runtimeType == "io.containerd.kata.v2" and .runtimePath == "/opt/kata/runtime-rs/bin/containerd-shim-kata-v2"
    and .privileged_without_host_devices == true and (.PodAnnotations // []) == [] and .ConfigPath == $c' <<<"$r" >/dev/null \
    && echo "OK   section kata conforme au fichier d'appoint (aucune annotation de pod transmise)" || { echo "KO   section kata" >&2; exit 1; }
  echo "## RuntimeClass kata"
  kubectl apply --server-side -f "$here/kata/runtimeclass.yaml" >/dev/null
  kubectl get runtimeclass kata -o json | jq -c '{handler, overhead, scheduling}'
}

MESURE='echo "noyau : $(uname -r)"; echo "vCPU : $(nproc)"; grep MemTotal /proc/meminfo
/lib/ld-linux-x86-64.so.2 --help | grep -E "x86-64-v[234]"
echo "drapeaux avx512 : $(grep -o "avx512[a-z_]*" /proc/cpuinfo | sort -u | wc -l)"
grep -E "^(Seccomp|NoNewPrivs|CapEff):" /proc/self/status'

pod_essai() { # nom runtimeClass|- annotation=valeur|- : pod de builds conforme à restricted, journal dans $T/<nom>.log
  local d f
  jq -n --arg n "$1" --arg rc "$2" --arg an "$3" --arg i "$BUSYBOX" --arg s "$MESURE" '{apiVersion: "v1", kind: "Pod",
    metadata: ({name: $n, namespace: "builds"} + (if $an == "-" then {} else {annotations: {($an | split("=")[0]): ($an | split("=")[1])}} end)),
    spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "mesure", image: $i, command: ["sh", "-c", $s],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}
      + (if $rc == "-" then {} else {runtimeClassName: $rc} end))}' > "$T/$1.json"
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true >/dev/null
  kubectl create -f "$T/$1.json" >/dev/null
  kubectl wait -n builds "pod/$1" --for=jsonpath='{.status.phase}'=Succeeded --timeout=240s >/dev/null \
    || { kubectl describe pod -n builds "$1" >&2; echo "KO   pod $1 non terminé" >&2; exit 1; }
  kubectl logs -n builds "$1" > "$T/$1.log"
  d=$(kubectl get pod -n builds "$1" -o json | jq -r '[.metadata.creationTimestamp, .status.containerStatuses[0].state.terminated.startedAt]
    | map(fromdateiso8601) | .[1] - .[0]')
  echo "### $1 (runtimeClassName $2, annotation $3) : nœud $(kubectl get pod -n builds "$1" -o jsonpath='{.spec.nodeName}'), conteneur lancé $d s après la création"
  sed 's/^/     /' "$T/$1.log"
}

champ() { sed -n "s/^$2[[:space:]]*:[[:space:]]*//p" "$T/$1.log" | head -1; }   # pod libellé : valeur d'une ligne « libellé : valeur »

etape_essais() {
  local h m1 m2 v
  h=$(sur sc-build 'uname -r')
  echo "## prédiction"
  echo "runc : noyau de sc-build ($h), seccomp filtré (Seccomp: 2), x86-64-v3 pris en charge, v4 non, aucun drapeau avx512"
  echo "kata : noyau de l'invité 6.18.56, 1 vCPU, MemTotal sous 2048 Mio, Seccomp: 0 (disable_guest_seccomp), x86-64-v3 pris en charge, v4 non"
  echo "kata avec l'annotation default_memory=4096 : même mémoire que kata (annotation non transmise par containerd)"
  echo "kata privilégié dans builds : refusé par Pod Security (enforce restricted), avant Kyverno"
  echo "## mesures"
  pod_essai j7-runc - -
  pod_essai j7-kata kata -
  pod_essai j7-kata-memoire kata io.katacontainers.config.hypervisor.default_memory=4096
  echo "## comparaison"
  [ "$(champ j7-runc noyau)" = "$h" ] && [ "$(champ j7-runc Seccomp)" = 2 ] && echo "OK   runc : noyau de sc-build, seccomp filtré" \
    || { echo "KO   runc" >&2; exit 1; }
  for p in j7-runc j7-kata; do
    grep -qE '^ *x86-64-v3 \(supported, searched\)' "$T/$p.log" && ! grep -qE '^ *x86-64-v4 \(supported' "$T/$p.log" \
      && [ "$(champ "$p" 'drapeaux avx512')" = 0 ] && echo "OK   $p : x86-64-v3 pris en charge, v4 non, aucun drapeau avx512" \
      || { echo "KO   $p : niveau x86-64" >&2; exit 1; }
  done
  v=$(champ j7-kata noyau)
  case $v in 6.18.56*) echo "OK   kata : noyau de l'invité $v (sc-build : $h)" ;; *) echo "KO   kata : noyau $v" >&2; exit 1 ;; esac
  m1=$(champ j7-kata MemTotal | awk '{print $1}'); m2=$(champ j7-kata-memoire MemTotal | awk '{print $1}')
  [ "$(champ j7-kata vCPU)" = 1 ] && [ "$m1" -lt $((2048 * 1024)) ] && echo "OK   kata : 1 vCPU, MemTotal $m1 kB (défaut de 2048 Mio)" \
    || { echo "KO   kata : vCPU ou mémoire" >&2; exit 1; }
  [ "$m2" = "$m1" ] && echo "OK   annotation default_memory=4096 sans effet : MemTotal $m2 kB (pod_annotations vide)" \
    || { echo "KO   annotation transmise : MemTotal $m2 kB contre $m1" >&2; exit 1; }
  if [ "$(champ j7-kata Seccomp)" = 0 ]; then
    echo "CONSTAT kata : Seccomp: 0 dans l'invité malgré seccompProfile RuntimeDefault (disable_guest_seccomp = true) ; le pod est conforme à restricted sans filtre seccomp effectif"
  else echo "KO   kata : Seccomp $(champ j7-kata Seccomp), contraire à la configuration lue" >&2; exit 1; fi
  echo "NoNewPrivs et CapEff : runc $(champ j7-runc NoNewPrivs) $(champ j7-runc CapEff), kata $(champ j7-kata NoNewPrivs) $(champ j7-kata CapEff)"
  echo "## pod Kata privilégié dans builds (dry-run serveur)"
  jq '.metadata.name = "j7-kata-privilegie" | .spec.containers[0].securityContext = {privileged: true, allowPrivilegeEscalation: true}' \
    "$T/j7-kata.json" > "$T/j7-kata-privilegie.json"
  refus "pod Kata privilégié dans builds" 'violates PodSecurity "restricted:latest"' kubectl create --dry-run=server -f "$T/j7-kata-privilegie.json"
  for p in j7-runc j7-kata j7-kata-memoire; do kubectl delete pod -n builds "$p" --wait=false >/dev/null; done
  echo "## qui peut créer, modifier ou supprimer une RuntimeClass (pods-isolation reconnaît Kata au nom de la RuntimeClass)"
  echo "RuntimeClasses : $(kubectl get runtimeclasses -o jsonpath='{range .items[*]}{.metadata.name}={.handler} {end}')"
  # Première prédiction (ramasse-miettes seul) démentie le 30/10/2026 (resultats/kata-essais-premiere-prediction.log) : le
  # contrôleur des espaces de noms peut aussi supprimer (delete sur tout, pour vider un espace). Supprimer la RuntimeClass
  # kata ne contourne rien : l'API refuse un pod qui désigne une RuntimeClass absente.
  echo "prédiction : ramasse-miettes de Kubernetes (update, patch, delete), contrôleur des espaces de noms (delete) ; aucune création ; l'opérateur : rien"
  kubectl get serviceaccounts -A -o jsonpath='{range .items[*]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}' > "$T/comptes"
  { while IFS=: read -r ns nom; do
      for v in create update patch delete; do
        if [ "$(kubectl auth can-i "$v" runtimeclasses.node.k8s.io --as="system:serviceaccount:$ns:$nom" 2>/dev/null || true)" = yes ]; then echo "$ns:$nom $v"; fi
      done
    done < "$T/comptes"
    for v in create update patch delete; do
      if [ "$(kubectl auth can-i "$v" runtimeclasses.node.k8s.io --as=operateur --as-group=operateurs 2>/dev/null || true)" = yes ]; then echo "operateur $v"; fi
    done; } | sort > "$T/rc-droits"
  echo "$(wc -l < "$T/comptes") comptes de service et l'opérateur examinés ; accordés :"; sed 's/^/  /' "$T/rc-droits"
  printf '%s\n' "kube-system:generic-garbage-collector delete" "kube-system:generic-garbage-collector patch" \
    "kube-system:generic-garbage-collector update" "kube-system:namespace-controller delete" | cmp -s - "$T/rc-droits" \
    && echo "OK   ces deux contrôleurs seuls, parmi les comptes de service, et aucune création (plus les administrateurs du cluster)" \
    || echo "CONSTAT  liste différente de la prédiction (ci-dessus)"
}

etape_temoin() {
  local r="" v
  for _ in $(seq 60); do r=$(runtime_kata); [ -n "$r" ] && break; sleep 2; done
  [ -n "$r" ] && echo "OK   runtime kata chargé par containerd sur sc-build" || { echo "KO   runtime kata absent de crictl info" >&2; exit 1; }
  pod_essai j7-kata kata -
  v=$(champ j7-kata noyau)
  case $v in 6.18.56*) echo "OK   pod Kata : noyau de l'invité $v" ;; *) echo "KO   pod Kata : noyau $v" >&2; exit 1 ;; esac
  kubectl delete pod -n builds j7-kata --wait=false >/dev/null
}

lancer kata J7 "$@"
