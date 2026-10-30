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
#   exemption  accord du propriétaire du 30/10/2026 (voie retenue en J6) : pods de la RuntimeClass kata exemptés de Pod Security
#              (k3s/pod-security.yaml, passé à kube-apiserver par le fichier d'appoint k3s/sc-confiance-pod-security.yaml),
#              server k3s redémarré (rattrapage suspendu, aucun PipelineRun actif), prédiction d'abord : mêmes conteneurs sur
#              sc-confiance, OpenBao, Kyverno, TSA et CronJobs ; admission mesurée en dry-run serveur. Après essais : posée dès
#              J1, l'exemption ferait mentir le refus du pod Kata privilégié que mesure essais
#   temoin     après un redémarrage des VM (redemarrer.sh) : runtime kata rechargé par containerd, pod Kata lancé dans l'invité
#   reseau     NetworkPolicy sur des pods Kata de sc-build, sous kube-router ou, depuis l'option 1b, sous Cilium (traces par
#              Hubble ; prédictions propres) (kata/sonde-reseau.yaml, posée sur les seuls pods de
#              mesure, retirée à la fin), prédiction d'abord : fenêtre de démarrage (sonde de J6) sous runc et sous Kata,
#              sorties une fois la règle posée, trace NFLOG (groupe 100) sur sc-build, usurpation d'une adresse inutilisée du
#              sous-réseau des pods par un pod Kata privilégié (posture de la construction, voie A)
# Retrait : supprimer /opt/kata et le fichier d'appoint sur sc-build, redémarrer k3s-agent, supprimer la RuntimeClass ;
# exemption : supprimer /etc/rancher/k3s/config.yaml.d/pod-security.yaml et /etc/rancher/k3s/pod-security.yaml sur
# sc-confiance, redémarrer k3s.
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
PSA_FICHIER=/etc/rancher/k3s/pod-security.yaml              # sc-confiance (k3s/pod-security.yaml)
PSA_DROPIN=/etc/rancher/k3s/config.yaml.d/pod-security.yaml  # sc-confiance (k3s/sc-confiance-pod-security.yaml)
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
  grep -E '^(path|kernel|image|machine_type|rootfs_type|enable_annotations|cpu_features|seccomp_sandbox|default_vcpus|default_memory|overhead_vcpus|overhead_memory|shared_fs|virtio_fs_daemon|rootless|disable_nesting_checks|internetworking_model|disable_guest_seccomp|sandbox_cgroup_only|static_sandbox_resource_mgmt|disable_guest_selinux) ' "$c"
  grep -q '^disable_guest_seccomp = true$' "$c" \
    && echo "CONSTAT disable_guest_seccomp = true : le profil seccomp déclaré dans le pod n'est pas appliqué dans l'invité"
  grep -q '^seccomp_sandbox = ""$' "$c" \
    && echo "CONSTAT seccomp_sandbox vide : QEMU tourne sur le nœud sans bac à sable seccomp (lu, non mesuré)"
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

suspendre_rattrapage() { # CronJob de rattrapage suspendu (rétabli à la sortie), aucun passage ni PipelineRun actif ;
  # $1 (option) : nœud sur lequel aucun pod ne doit tourner
  local n r=0
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":true}}' >/dev/null
  trap reprendre_rattrapage EXIT
  for _ in $(seq 60); do [ -z "$(kubectl get cronjob -n declencheurs rattrapage -o jsonpath='{.status.active}')" ] && break; sleep 2; done
  n=$(kubectl get pipelineruns -n builds -o json | jq '[.items[] | select(.status.completionTime == null)] | length')
  [ -z "${1:-}" ] || r=$(kubectl get pods -A --field-selector "spec.nodeName=$1,status.phase=Running" -o name | wc -l)
  [ "$n" = 0 ] && [ "$r" = 0 ] && echo "rattrapage suspendu ; aucun PipelineRun actif${1:+, aucun pod en cours sur $1}" \
    || { echo "KO   $n PipelineRun(s) actif(s)${1:+, $r pod(s) en cours sur $1} : redémarrage reporté" >&2; exit 1; }
}

reprendre_rattrapage() { kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":false}}' >/dev/null; trap - EXIT; }

etape_installer() {
  local redemarrer=0 r
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
    suspendre_rattrapage sc-build
    sur sc-build 'sudo systemctl restart k3s-agent'
    for _ in $(seq 60); do [ -n "$(runtime_kata)" ] && break; sleep 2; done
    kubectl wait --for=condition=Ready node/sc-build --timeout=180s >/dev/null
    reprendre_rattrapage
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

MESURE='echo "noyau : $(uname -r)"; echo "vCPU : $(nproc)"; grep MemTotal /proc/meminfo; grep -m1 "model name" /proc/cpuinfo
/lib/ld-linux-x86-64.so.2 --help | grep -E "x86-64-v[234]"
echo "drapeaux avx512 : $(grep -o "avx512[a-z_]*" /proc/cpuinfo | sort -u | wc -l)"
grep -E "^(Seccomp|NoNewPrivs|CapEff):" /proc/self/status'

pod_spec() { # nom runtimeClass|- annotation=valeur|- script : pod de builds conforme à restricted, dans $T/<nom>.json
  jq -n --arg n "$1" --arg rc "$2" --arg an "$3" --arg i "$BUSYBOX" --arg s "$4" '{apiVersion: "v1", kind: "Pod",
    metadata: ({name: $n, namespace: "builds"} + (if $an == "-" then {} else {annotations: {($an | split("=")[0]): ($an | split("=")[1])}} end)),
    spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "mesure", image: $i, command: ["sh", "-c", $s],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}
      + (if $rc == "-" then {} else {runtimeClassName: $rc} end))}' > "$T/$1.json"
}

pod_essai() { # nom runtimeClass|- annotation=valeur|- : pod de mesure (MESURE) terminé, journal dans $T/<nom>.log
  local d
  pod_spec "$1" "$2" "$3" "$MESURE"
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

ligne_qemu() { # arguments -cpu, -machine, -m et -smp de QEMU sur sc-build, pendant la vie d'un pod Kata qui dort
  pod_spec j7-kata-qemu kata - 'sleep 300'
  kubectl delete pod -n builds j7-kata-qemu --ignore-not-found --wait=true >/dev/null
  kubectl create -f "$T/j7-kata-qemu.json" >/dev/null
  kubectl wait -n builds pod/j7-kata-qemu --for=condition=Ready --timeout=240s >/dev/null
  sur sc-build 'pgrep -a qemu-system' > "$T/qemu.txt"
  kubectl delete pod -n builds j7-kata-qemu --wait=false >/dev/null
  echo "processus QEMU sur sc-build : $(wc -l < "$T/qemu.txt")"
  for a in -cpu -machine -m -smp; do echo "$a $(tr ' ' '\n' < "$T/qemu.txt" | grep -A1 -x -m1 -- "$a" | tail -1)"; done
}

admis() { # libellé commande… : la commande doit réussir (dry-run serveur)
  local l=$1; shift
  if "$@" > "$T/admis.out" 2>&1; then echo "OK   $l : admis ($(head -1 "$T/admis.out"))"
  else echo "KO   $l : refusé" >&2; cat "$T/admis.out" >&2; exit 1; fi
}

args_apiserver() { # arguments du dernier lancement de kube-apiserver par k3s sur sc-confiance (journal de k3s), un par ligne
  sur sc-confiance "sudo journalctl -u k3s --no-pager -o cat | grep 'Running kube-apiserver' | tail -n 1" | tr ' ' '\n'
}

exemption_posee() { args_apiserver | grep -x -- "--admission-control-config-file=$PSA_FICHIER" >/dev/null; }

champ() { sed -n "s/^$2[[:space:]]*:[[:space:]]*//p" "$T/$1.log" | head -1; }   # pod libellé : valeur d'une ligne « libellé : valeur »

etape_essais() {
  local h m1 m2 v e=0
  h=$(sur sc-build 'uname -r')
  if exemption_posee; then e=1; fi
  echo "## prédiction"
  echo "runc : noyau de sc-build ($h), seccomp filtré (Seccomp: 2), x86-64-v3 pris en charge, v4 non, aucun drapeau avx512"
  echo "kata : noyau de l'invité 6.18.56, 1 vCPU, MemTotal sous 2048 Mio, Seccomp: 0 (disable_guest_seccomp), x86-64-v3 pris en charge, v4 non"
  echo "kata avec l'annotation default_memory=4096 : même mémoire que kata (annotation non transmise par containerd)"
  if [ "$e" = 1 ]; then echo "kata privilégié dans builds : admis (exemption de la RuntimeClass kata, étape exemption)"
  else echo "kata privilégié dans builds : refusé par Pod Security (enforce restricted), avant Kyverno"; fi
  echo "kata : QEMU lancé avec -cpu host,pmu=off (type host et cpu_features, lus dans cmdline_generator.rs de runtime-rs 4.3.1),"
  echo "       donc même modèle de CPU (model name) dans l'invité que dans sc-build"
  echo "## mesures"
  pod_essai j7-runc - -
  pod_essai j7-kata kata -
  pod_essai j7-kata-memoire kata io.katacontainers.config.hypervisor.default_memory=4096
  ligne_qemu | tee "$T/qemu-args.txt"
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
  [ "$(awk '$1 == "-cpu" {print $2}' "$T/qemu-args.txt")" = host,pmu=off ] && [ -n "$(champ j7-kata 'model name')" ] \
    && [ "$(champ j7-kata 'model name')" = "$(champ j7-runc 'model name')" ] \
    && echo "OK   kata : QEMU en -cpu host,pmu=off, même modèle de CPU que sc-build ($(champ j7-kata 'model name'))" \
    || { echo "KO   kata : modèle de CPU de l'invité" >&2; exit 1; }
  echo "NoNewPrivs et CapEff : runc $(champ j7-runc NoNewPrivs) $(champ j7-runc CapEff), kata $(champ j7-kata NoNewPrivs) $(champ j7-kata CapEff)"
  echo "## pod Kata privilégié dans builds (dry-run serveur)"
  jq '.metadata.name = "j7-kata-privilegie" | .spec.containers[0].securityContext = {privileged: true, allowPrivilegeEscalation: true}' \
    "$T/j7-kata.json" > "$T/j7-kata-privilegie.json"
  if [ "$e" = 1 ]; then admis "pod Kata privilégié dans builds, exemption posée" kubectl create --dry-run=server -f "$T/j7-kata-privilegie.json"
  else refus "pod Kata privilégié dans builds" 'violates PodSecurity "restricted:latest"' kubectl create --dry-run=server -f "$T/j7-kata-privilegie.json"; fi
  for p in j7-runc j7-kata j7-kata-memoire; do kubectl delete pod -n builds "$p" --wait=false >/dev/null; done
  echo "## qui peut créer, modifier ou supprimer une RuntimeClass (pods-isolation reconnaît Kata au nom de la RuntimeClass)"
  echo "RuntimeClasses : $(kubectl get runtimeclasses -o jsonpath='{range .items[*]}{.metadata.name}={.handler} {end}')"
  echo "runtimes de containerd sur sc-build (crictl info) : $(sur sc-build 'sudo k3s crictl info' | jq -r '.config.containerd.runtimes | keys | join(" ")')"
  echo "les RuntimeClasses créées par k3s (crun, nvidia, wasm…) n'ont pas de runtime derrière sur sc-build : un pod qui les désigne n'y démarre pas"
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

psa_en_place() { # fichiers de l'exemption identiques aux fichiers versionnés sur sc-confiance, et lus par kube-apiserver
  sur sc-confiance "sudo cat $PSA_FICHIER 2>/dev/null" | cmp -s - "$here/k3s/pod-security.yaml" \
    && sur sc-confiance "sudo cat $PSA_DROPIN 2>/dev/null" | cmp -s - "$here/k3s/sc-confiance-pod-security.yaml" && exemption_posee
}

pods_durables() { # pods de sc-confiance qui ne viennent pas d'un Job, en cours : espace/nom
  kubectl get pods -A --field-selector spec.nodeName=sc-confiance,status.phase=Running -o json \
    | jq -r '.items[] | select(any(.metadata.ownerReferences[]?; .kind == "Job") | not) | .metadata.namespace + "/" + .metadata.name' | sort
}

conteneurs_durables() { # conteneurs en cours sur sc-confiance (crictl) des pods de $T/pods-durables.txt : pod conteneur identifiant
  sur sc-confiance 'sudo k3s crictl ps -o json' | jq -r '.containers[] | (.labels["io.kubernetes.pod.namespace"] + "/"
    + .labels["io.kubernetes.pod.name"]) + " " + .metadata.name + " " + .id' | sort | join - "$T/pods-durables.txt"
}

etape_exemption() {
  local t d st
  echo "## prédiction"
  echo "kube-apiserver relancé avec --admission-control-config-file=$PSA_FICHIER (fichier d'appoint de config.yaml.d, clé kube-apiserver-arg+)"
  echo "server k3s redémarré sans arrêter les conteneurs de sc-confiance (unité k3s en KillMode=process) : mêmes conteneurs, mêmes"
  echo "  identifiants ; OpenBao reste descellé, même clé ; Kyverno répond ; témoin TSA vérifié ; un passage réussi de chaque CronJob"
  echo "admission (dry-run serveur) : dans builds, pod Kata privilégié admis, pod Kata non privilégié avec allowPrivilegeEscalation"
  echo "  et les capacités par défaut admis, pod runc privilégié refusé par Pod Security, pod Kata privilégié avec hostPath refusé"
  echo "  par Kyverno (pods-isolation) ; dans tsa, pod Kata privilégié sans nodeSelector refusé par Kyverno (zone-confiance : la"
  echo "  RuntimeClass lui ajoute le nodeSelector et la tolérance de la zone build)"
  if psa_en_place; then
    echo "## exemption déjà en place (fichiers identiques aux fichiers versionnés, argument lu dans le journal de k3s)"
  else
    echo "## état avant"
    mise run confiance:openbao -- temoin
    pods_durables > "$T/pods-durables.txt"
    conteneurs_durables > "$T/conteneurs-avant.txt"
    echo "$(wc -l < "$T/pods-durables.txt") pods durables et $(wc -l < "$T/conteneurs-avant.txt") conteneurs en cours sur sc-confiance"
    echo "kube-apiserver : $(args_apiserver | grep -E -- '^--(enable-admission-plugins|admission-control-config-file)=' | paste -sd' ')"
    suspendre_rattrapage
    echo "## pose sur sc-confiance (0600) et redémarrage du server k3s"
    sur sc-confiance "sudo install -d -m 0700 ${PSA_DROPIN%/*} && sudo tee $PSA_FICHIER >/dev/null && sudo chmod 0600 $PSA_FICHIER" < "$here/k3s/pod-security.yaml"
    sur sc-confiance "sudo tee $PSA_DROPIN >/dev/null && sudo chmod 0600 $PSA_DROPIN" < "$here/k3s/sc-confiance-pod-security.yaml"
    d=$(date +%s)
    sur sc-confiance 'sudo systemctl restart k3s'
    for _ in $(seq 90); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 2; done
    kubectl wait --for=condition=Ready node --all --timeout=180s >/dev/null
    echo "API prête et trois nœuds Ready $(( $(date +%s) - d )) s après le redémarrage ; k3s : $(sur sc-confiance 'systemctl is-active k3s')"
    reprendre_rattrapage
    t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "## après le redémarrage"
    psa_en_place && echo "OK   kube-apiserver : $(args_apiserver | grep -E -- '^--(enable-admission-plugins|admission-control-config-file)=' | paste -sd' ')" \
      || { echo "KO   exemption non lue par kube-apiserver" >&2; exit 1; }
    for _ in $(seq 30); do conteneurs_durables > "$T/conteneurs-apres.txt" && [ -s "$T/conteneurs-apres.txt" ] && break; sleep 2; done
    if cmp -s "$T/conteneurs-avant.txt" "$T/conteneurs-apres.txt"; then
      echo "OK   mêmes conteneurs sur sc-confiance ($(wc -l < "$T/conteneurs-apres.txt")), mêmes identifiants : aucun arrêté par le redémarrage"
    else echo "CONSTAT conteneurs de sc-confiance changés par le redémarrage :"; diff "$T/conteneurs-avant.txt" "$T/conteneurs-apres.txt" || true; fi
    sonde_kyverno
    st=$(kubectl exec -n openbao openbao-0 -- bao status -format=json 2>/dev/null || true)
    if [ "$(jq -r .sealed <<<"$st")" = false ]; then echo "OK   OpenBao descellé après le redémarrage du server"
    else echo "CONSTAT OpenBao scellé après le redémarrage du server : $(jq -c '{initialized, sealed}' <<<"$st")"; mise run confiance:openbao -- deverrouiller; fi
    mise run confiance:openbao -- controle
    mise run confiance:tsa -- temoin
    echo "## CronJobs : un passage réussi de chacun, créé après le redémarrage ($t)"
    passage_ok horodatage horodatage "$t"
    passage_ok declencheurs rattrapage "$t"
  fi
  echo "## admission (dry-run serveur)"
  pod_spec j7-exemption kata - 'true'
  jq '.spec.containers[0].securityContext = {privileged: true, allowPrivilegeEscalation: true}' "$T/j7-exemption.json" > "$T/j7-exemption-privilegie.json"
  admis "pod Kata privilégié dans builds" kubectl create --dry-run=server -f "$T/j7-exemption-privilegie.json"
  jq '.spec.containers[0].securityContext = {allowPrivilegeEscalation: true}' "$T/j7-exemption.json" > "$T/j7-exemption-escalade.json"
  admis "pod Kata non privilégié, allowPrivilegeEscalation et capacités par défaut, dans builds" kubectl create --dry-run=server -f "$T/j7-exemption-escalade.json"
  jq 'del(.spec.runtimeClassName)' "$T/j7-exemption-privilegie.json" > "$T/j7-exemption-runc.json"
  refus "pod runc privilégié dans builds" 'violates PodSecurity "restricted:latest"' kubectl create --dry-run=server -f "$T/j7-exemption-runc.json"
  jq '.spec.volumes = [{name: "h", hostPath: {path: "/var/lib/rancher"}}] | .spec.containers[0].volumeMounts = [{name: "h", mountPath: "/h"}]' \
    "$T/j7-exemption-privilegie.json" > "$T/j7-exemption-hostpath.json"
  refus "pod Kata privilégié avec hostPath dans builds" 'volume hostPath interdit' kubectl create --dry-run=server -f "$T/j7-exemption-hostpath.json"
  jq '.metadata.namespace = "tsa" | del(.spec.nodeSelector, .spec.tolerations, .spec.serviceAccountName)' "$T/j7-exemption-privilegie.json" > "$T/j7-exemption-tsa.json"
  refus "pod Kata privilégié dans tsa, sans nodeSelector" 'zone confiance' kubectl create --dry-run=server -f "$T/j7-exemption-tsa.json"
  echo "## témoin Kata"
  etape_temoin
}

etape_temoin() {
  local r="" v
  for _ in $(seq 60); do r=$(runtime_kata); [ -n "$r" ] && break; sleep 2; done
  [ -n "$r" ] && echo "OK   runtime kata chargé par containerd sur sc-build" || { echo "KO   runtime kata absent de crictl info" >&2; exit 1; }
  echo "exemption Pod Security de la RuntimeClass kata : $(exemption_posee && echo "lue par kube-apiserver (étape exemption)" || echo "absente")"
  pod_essai j7-kata kata -
  v=$(champ j7-kata noyau)
  case $v in 6.18.56*) echo "OK   pod Kata : noyau de l'invité $v" ;; *) echo "KO   pod Kata : noyau $v" >&2; exit 1 ;; esac
  kubectl delete pod -n builds j7-kata --wait=false >/dev/null
}

SONDE=sonde-reseau-j7   # label des pods de mesure et nom de la NetworkPolicy (kata/sonde-reseau.yaml)
USURPEE=10.42.1.250     # adresse du sous-réseau des pods de sc-build (10.42.1.0/24), inutilisée (contrôlé avant l'essai)
# Sonde de J6 (politique.sh rattrapage), adaptée : un refus de Zot ne compte que si Forgejo (permis) répond, pour ne pas
# confondre la règle avec un réseau pas encore prêt ; fin après 3 refus de suite (60 s au plus), puis sorties par adresse.
FENETRE='cs() { read u r < /proc/uptime; echo $(( ${u%.*} * 100 + 1${u#*.} - 100 )); }
t0=$(cs); o=0; f=0; d=-
while [ $f -lt 3 ] && [ $(( $(cs) - t0 )) -lt 6000 ]; do
  t=$(( ($(cs) - t0) * 10 ))
  if nc -z -w 1 192.168.161.13 5000 2>/dev/null; then z=OUVERT; else z=FERME; fi
  if nc -z -w 1 192.168.161.13 3000 2>/dev/null; then g=OUVERT; else g=FERME; fi
  case $z$g in OUVERT*) o=$((o + 1)); f=0; d=$t ;; FERMEOUVERT) f=$((f + 1)) ;; *) f=0 ;; esac
  echo "ESSAI|$t|$z|$g"
  sleep 0.5
done
echo "FENETRE|$o|$d|$f"
for c in Forgejo:192.168.161.13:3000 Zot:192.168.161.13:5000 SSH-stockage:192.168.161.13:22 API-noeud:192.168.161.11:6443 \
         API-service:10.43.0.1:443 kubelet-local:192.168.161.12:10250 kubelet-confiance:192.168.161.11:10250; do
  l=${c%%:*}; r=${c#*:}; h=${r%:*}; p=${r##*:}
  if nc -z -w 3 "$h" "$p" 2>/dev/null; then echo "SORTIE|$l|$h:$p|OUVERT"; else echo "SORTIE|$l|$h:$p|FERME"; fi
done'
TRACE='sleep 8
for i in 1 2 3; do if nc -z -w 1 192.168.161.13 5000 2>/dev/null; then echo "TRACE|$i|OUVERT"; else echo "TRACE|$i|FERME"; fi; sleep 1; done'
USURPATION="sleep 8
o() { if \"\$@\" 2>/dev/null; then echo OUVERT; else echo FERME; fi; }
echo \"AVANT|Zot|\$(o nc -z -w 3 192.168.161.13 5000)\"
echo \"AVANT|Forgejo|\$(o nc -z -w 3 192.168.161.13 3000)\"
ip addr add $USURPEE/32 dev eth0
echo \"ADRESSES|\$(ip -o -4 addr show dev eth0 | awk '{print \$4}' | tr '\n' ' ')\"
for c in Zot:192.168.161.13:5000 SSH-stockage:192.168.161.13:22 API-noeud:192.168.161.11:6443 kubelet-local:192.168.161.12:10250; do
  l=\${c%%:*}; r=\${c#*:}; h=\${r%:*}; p=\${r##*:}
  echo \"USURPEE|\$l|\$h:\$p|\$(o nc -s $USURPEE -z -w 3 \$h \$p)\"
done
echo \"ECHANGE|Zot|\$(printf 'GET / HTTP/1.0\\r\\n\\r\\n' | nc -s $USURPEE -w 3 192.168.161.13 5000 | head -1 | tr -d '\\r')\"
ip addr del $USURPEE/32 dev eth0
echo \"APRES|Zot|\$(o nc -z -w 3 192.168.161.13 5000)\"
echo FIN
sleep 30"

TEMOIN_USURPATION="sleep 8
r=\$(ip addr add $USURPEE/32 dev eth0 2>&1) && echo \"AJOUT|accepté\" || echo \"AJOUT|refusé|\$r\"
r=\$(nc -s $USURPEE -z -w 3 192.168.161.13 5000 2>&1) && echo \"LIAISON|ouverte\" || echo \"LIAISON|refusée|\$r\""

pod_reseau() { # nom runtimeClass|- privilegie|- script : pod de mesure au label de la NetworkPolicy, créé sans attendre
  pod_spec "$1" "$2" - "$4"
  jq --arg l "$SONDE" '.metadata.labels = {app: $l}' "$T/$1.json" > "$T/$1.tmp"
  if [ "$3" = privilegie ]; then
    jq '.spec.securityContext = {} | .spec.containers[0].securityContext = {privileged: true, allowPrivilegeEscalation: true,
      runAsUser: 0, runAsNonRoot: false}' "$T/$1.tmp" > "$T/$1.json"
  else mv "$T/$1.tmp" "$T/$1.json"; fi
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true >/dev/null
  kubectl create -f "$T/$1.json" >/dev/null
}

pod_fini() { # nom : pod terminé, journal dans $T/<nom>.log ; affiche IP, nœud et délai de lancement du conteneur
  kubectl wait -n builds "pod/$1" --for=jsonpath='{.status.phase}'=Succeeded --timeout=240s >/dev/null \
    || { kubectl describe pod -n builds "$1" >&2; echo "KO   pod $1 non terminé" >&2; exit 1; }
  kubectl logs -n builds "$1" > "$T/$1.log"
  kubectl get pod -n builds "$1" -o json | jq -r '"### \(.metadata.name) : IP \(.status.podIP), nœud \(.spec.nodeName), conteneur lancé "
    + "\([.metadata.creationTimestamp, .status.containerStatuses[0].state.terminated.startedAt] | map(fromdateiso8601) | .[1] - .[0]) s après la création"'
}

ip_pod() { kubectl get pod -n builds "$1" -o jsonpath='{.status.podIP}'; }

capture() { # fichier durée filtre… : tcpdump sur sc-build en arrière-plan (PID dans $CAPTURE), attend qu'il écoute
  local f=$1 d=$2; shift 2
  sur sc-build "sudo timeout $d tcpdump -nn -l $* 2>&1" > "$f" &
  CAPTURE=$!
  for _ in $(seq 20); do grep -q '^listening on' "$f" && return 0; sleep 0.5; done
  echo "KO   tcpdump ($*) n'écoute pas" >&2; cat "$f" >&2; exit 1
}

syn() { # fichier source destination.port : nombre de lignes SYN (sans ACK) de source vers destination dans une capture tcpdump
  grep -cE "IP ${2//./\\.}\.[0-9]+ > ${3//./\\.}: Flags \[S\]," "$1" || true
}

syn_distincts() { # mêmes arguments : nombre de SYN distincts (port source et numéro de séquence)
  { grep -E "IP ${2//./\\.}\.[0-9]+ > ${3//./\\.}: Flags \[S\]," "$1" || true; } \
    | sed -E 's/.* IP ([0-9.]+) > .*, seq ([0-9]+),.*/\1 \2/' | sort -u | wc -l
}

nettoyer_reseau() {
  kubectl delete pod -n builds -l "app=$SONDE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete -f "$here/kata/sonde-reseau.yaml" --ignore-not-found >/dev/null 2>&1 || true
}

etape_reseau() { # contrôleur réseau du cluster : Cilium (J7, option 1b) ou kube-router
  if [ "$(reseau)" = cilium ]; then reseau_cilium; else reseau_kube_router; fi
}

reseau_cilium() {
  local ko=0 i p ip o d f n s t0
  echo "## prédiction (écrite le 30/10/2026, avant la mesure, sous Cilium 1.20.4 : routage natif, kube-proxy de k3s, L7 coupé)"
  echo "- la politique ne sélectionne que les pods de mesure (label app=$SONDE) ;"
  echo "- fenêtre : aucune, sous runc comme sous Kata. Le plugin CNI demande une construction synchrone (SyncBuildEndpoint,"
  echo "  plugins/cilium-cni/cmd/cmd.go) ; l'agent résout les labels du pod puis attend la première régénération avant de rendre"
  echo "  la main (WaitForFirstRegeneration, pkg/endpoint/api/endpoint_api_manager.go, au tag v1.20.4) : Zot refusé dès la"
  echo "  première tentative ;"
  echo "- une fois la règle posée, sous runc comme sous Kata : Forgejo seul ouvert ; Zot, SSH de sc-stockage, API (nœud et"
  echo "  service), kubelet local et kubelet de sc-confiance fermés. Un refus de Cilium est une perte de paquet, pas un REJECT :"
  echo "  délai dépassé côté client ;"
  echo "- Hubble (agent de sc-build) : au moins un flux refusé par tentative vers Zot, avec l'IP du pod et un motif de politique,"
  echo "  pour le pod runc comme pour le pod Kata ; aucun plafond ;"
  echo "- usurpation, pod Kata privilégié (root, NET_ADMIN dans l'invité) : avec son IP, Zot refusé ; avec $USURPEE, tout refusé"
  echo "  (vérification de l'adresse source, documentée : annotations de pod), aucune réponse de Zot, flux de $USURPEE refusés"
  echo "  dans Hubble avec un motif d'adresse source ;"
  echo "- témoins sans NET_ADMIN, pod Kata restreint et pod runc restreint : ajout et liaison de l'adresse refusés, comme sous"
  echo "  kube-router (indépendant du contrôleur réseau)"
  echo "## état de départ"
  echo "NetworkPolicy de builds : $(kubectl get netpol -n builds -o name | tr '\n' ' ')"
  n=$(kubectl get netpol -n builds -o name | { grep -x "networkpolicy.networking.k8s.io/$SONDE" || true; } | wc -l)
  [ "$n" = 0 ] && echo "OK   pas de politique $SONDE résiduelle" || { echo "KO   politique $SONDE résiduelle" >&2; exit 1; }
  echo "Cilium : $(kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status --brief 2>&1 | tail -1) ; enable-policy \
$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-policy}') ; routing-mode $(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.routing-mode}')"
  rm -f "$T/fenetres.txt" "$T/traces.txt"
  trap nettoyer_reseau EXIT
  kubectl apply -f "$here/kata/sonde-reseau.yaml" >/dev/null
  echo "NetworkPolicy $SONDE posée : sortie vers Forgejo (192.168.161.13:3000) seule, pour les pods app=$SONDE"

  echo "## fenêtre de démarrage, trois essais alternés runc et Kata"
  for i in 1 2 3; do
    for p in runc kata; do
      pod_reseau "j7-reseau-$p-$i" "$([ $p = kata ] && echo kata || echo -)" - "$FENETRE"
      pod_fini "j7-reseau-$p-$i"
      grep '^ESSAI|' "$T/j7-reseau-$p-$i.log" | awk -F'|' '{printf "  %5d ms : Zot %s ; Forgejo %s\n", $2, $3, $4}'
      IFS='|' read -r _ o d f < <(grep '^FENETRE|' "$T/j7-reseau-$p-$i.log")
      echo "  Zot joignable $o fois, la dernière à $d ms du lancement ; puis $f refus de suite"
      [ "$f" = 3 ] || { echo "KO   $p-$i : règle jamais appliquée en 60 s" >&2; ko=1; }
      echo "$p $o" >> "$T/fenetres.txt"
      grep '^SORTIE|' "$T/j7-reseau-$p-$i.log" | awk -F'|' '{print "  " $4 " " $2 " " $3}'
      s=$(grep '^SORTIE|' "$T/j7-reseau-$p-$i.log" | awk -F'|' '$4 == "OUVERT" {print $2}' | tr '\n' ' ')
      [ "$s" = "Forgejo " ] && echo "OK   $p-$i : une fois la règle posée, Forgejo seul ouvert" \
        || { echo "KO   $p-$i : ouverts : $s" >&2; ko=1; }
      kubectl delete pod -n builds "j7-reseau-$p-$i" --wait=false >/dev/null
    done
  done
  for p in runc kata; do
    n=$(awk -v p=$p '$1 == p && $2 > 0' "$T/fenetres.txt" | wc -l)
    [ "$n" = 0 ] && echo "OK   $p : aucune fenêtre en 3 essais (Zot refusé dès la première tentative)" \
      || { echo "KO   $p : fenêtre ouverte dans $n essai(s) sur 3 (prédiction : aucune)" >&2; ko=1; }
  done
  rm -f "$T/fenetres.txt"

  echo "## trace Hubble sur sc-build (agent Cilium du nœud)"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  pod_reseau j7-reseau-trace-runc - - "$TRACE"
  pod_reseau j7-reseau-trace-kata kata - "$TRACE"
  for p in runc kata; do
    pod_fini "j7-reseau-trace-$p"
    sed 's/^/  /' "$T/j7-reseau-trace-$p.log"
    ip=$(ip_pod "j7-reseau-trace-$p")
    o=$(grep -c '|FERME$' "$T/j7-reseau-trace-$p.log" || true)
    hubble_refus sc-build "$t0" --from-ip "$ip" --to-ip 192.168.161.13 --to-port 5000 > "$T/hubble-trace-$p.txt" || true
    sed 's/^/  Hubble : /' "$T/hubble-trace-$p.txt"
    n=$(wc -l < "$T/hubble-trace-$p.txt")
    [ "$o" = 3 ] && [ "$n" -ge 3 ] && echo "OK   $p ($ip) : 3 connexions refusées, $n flux refusés vers Zot dans Hubble ($(cut -d' ' -f5 "$T/hubble-trace-$p.txt" | sort -u | paste -sd,))" \
      || { echo "KO   $p ($ip) : $o refus, $n flux dans Hubble" >&2; ko=1; }
    kubectl delete pod -n builds "j7-reseau-trace-$p" --wait=false >/dev/null
  done

  echo "## usurpation d'adresse source : témoins sans NET_ADMIN (pods restreints, capacités retirées)"
  for p in runc kata; do
    pod_reseau "j7-reseau-temoin-$p" "$([ $p = kata ] && echo kata || echo -)" - "$TEMOIN_USURPATION"
    pod_fini "j7-reseau-temoin-$p"
    sed 's/^/  /' "$T/j7-reseau-temoin-$p.log"
    grep -q '^AJOUT|refusé|' "$T/j7-reseau-temoin-$p.log" && grep -q '^LIAISON|refusée|' "$T/j7-reseau-temoin-$p.log" \
      && echo "OK   $p restreint : ajout de $USURPEE refusé, liaison de nc refusée" \
      || { echo "KO   $p restreint : $(tr '\n' ' ' < "$T/j7-reseau-temoin-$p.log")" >&2; exit 1; }
    kubectl delete pod -n builds "j7-reseau-temoin-$p" --wait=false >/dev/null
  done
  echo "## usurpation d'adresse source : pod Kata privilégié"
  n=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | grep -cxF "$USURPEE" || true)
  d=$(kubectl get ciliumendpoints -A -o json | jq --arg u "$USURPEE" '[.items[].status.networking.addressing[]?.ipv4 | select(. == $u)] | length')
  [ "$n" = 0 ] && [ "$d" = 0 ] && echo "OK   $USURPEE inutilisée : portée ni par un pod ni par un endpoint de Cilium" \
    || { echo "KO   $USURPEE en usage" >&2; exit 1; }
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  capture "$T/usurpation.txt" 70 -i any host "$USURPEE"
  pod_reseau j7-reseau-usurpation kata privilegie "$USURPATION"
  for _ in $(seq 120); do
    kubectl logs -n builds j7-reseau-usurpation > "$T/j7-reseau-usurpation.log" 2>/dev/null || true
    grep -qx FIN "$T/j7-reseau-usurpation.log" && break; sleep 1
  done
  grep -qx FIN "$T/j7-reseau-usurpation.log" || { kubectl describe pod -n builds j7-reseau-usurpation >&2; echo "KO   essai d'usurpation non terminé" >&2; exit 1; }
  ip=$(ip_pod j7-reseau-usurpation)
  pod_fini j7-reseau-usurpation
  sed 's/^/  /' "$T/j7-reseau-usurpation.log"
  wait
  hubble_refus sc-build "$t0" --from-ip "$ip" --to-port 5000 > "$T/hubble-temoin.txt" || true
  hubble_refus sc-build "$t0" --ip "$USURPEE" > "$T/hubble-usurpation.txt" || true
  sed 's/^/  Hubble (IP du pod) : /' "$T/hubble-temoin.txt"
  sed 's/^/  Hubble ($USURPEE) : /' "$T/hubble-usurpation.txt"
  grep -E 'packets (captured|received)' "$T/usurpation.txt" | sed 's/^/  tcpdump : /' || true
  grep -qx 'AVANT|Zot|FERME' "$T/j7-reseau-usurpation.log" && grep -qx 'AVANT|Forgejo|OUVERT' "$T/j7-reseau-usurpation.log" \
    && grep -qx 'APRES|Zot|FERME' "$T/j7-reseau-usurpation.log" \
    && echo "OK   témoin : avec l'IP du pod, Zot refusé (avant et après), Forgejo ouvert" || { echo "KO   témoin" >&2; ko=1; }
  n=$(wc -l < "$T/hubble-temoin.txt")
  [ "$n" -ge 2 ] && echo "OK   Hubble : $n flux refusés du pod ($ip) vers Zot, ceux du témoin" || { echo "KO   Hubble : $n flux du témoin" >&2; ko=1; }
  s=$(grep '^USURPEE|' "$T/j7-reseau-usurpation.log" | awk -F'|' '$4 == "OUVERT" {print $2}' | tr '\n' ' ')
  [ -z "$s" ] && echo "OK   avec $USURPEE, tout refusé (Zot, SSH de sc-stockage, API, kubelet local)" \
    || { echo "KO   avec $USURPEE, ouverts : $s (prédiction : aucun)" >&2; ko=1; }
  grep -qx 'ECHANGE|Zot|HTTP/1.0 400 Bad Request' "$T/j7-reseau-usurpation.log" \
    && { echo "KO   avec $USURPEE, échange de données avec Zot" >&2; ko=1; } || echo "OK   avec $USURPEE, aucune réponse de Zot"
  n=$(wc -l < "$T/hubble-usurpation.txt")
  [ "$n" -ge 1 ] && echo "OK   Hubble : $n flux de $USURPEE refusés, motif(s) $(cut -d' ' -f5 "$T/hubble-usurpation.txt" | sort -u | paste -sd,)" \
    || { echo "KO   Hubble : aucun flux de $USURPEE" >&2; ko=1; }
  echo "  capture -i any sur sc-build : $(syn_distincts "$T/usurpation.txt" "$USURPEE" 192.168.161.13.5000) SYN distinct(s) de $USURPEE vers Zot, \
$(grep -cE "192\.168\.161\.13\.5000 > ${USURPEE//./\\.}\.[0-9]+: Flags \[S\.\]" "$T/usurpation.txt" || true) ligne(s) SYN-ACK en retour"

  echo "## retrait"
  kubectl delete pod -n builds -l "app=$SONDE" --ignore-not-found --wait=true >/dev/null
  kubectl delete -f "$here/kata/sonde-reseau.yaml" >/dev/null
  trap - EXIT
  [ "$(kubectl get netpol -n builds -o name | { grep -x "networkpolicy.networking.k8s.io/$SONDE" || true; } | wc -l)" = 0 ] \
    && echo "OK   NetworkPolicy et pods de mesure retirés" || { echo "KO   retrait incomplet" >&2; ko=1; }
  [ "$ko" = 0 ] || exit 1
}

reseau_kube_router() {
  local ko=0 i p ip o d f n s
  echo "## prédiction (écrite le 30/10/2026, avant la mesure)"
  echo "- la politique ne sélectionne que les pods de mesure (label app=$SONDE) ;"
  echo "- fenêtre : sous runc sur sc-build, comme en J6 sur sc-confiance, Zot (interdit) joignable dans la première seconde du"
  echo "  conteneur pour au moins un essai sur trois, puis fermé. Sous Kata, même fenêtre : kubelet ne publie l'IP du pod qu'au"
  echo "  passage qui suit le lancement des conteneurs, puis kube-router pose la règle ; la VM retarde le conteneur, pas la règle ;"
  echo "- une fois la règle posée, sous runc comme sous Kata : Forgejo seul ouvert ; Zot, SSH de sc-stockage, API (nœud et"
  echo "  service), kubelet local et kubelet de sc-confiance fermés ;"
  echo "- NFLOG (groupe 100, lu sur sc-build) : chaque SYN refusé vers Zot (3 par pod) y figure deux fois, avec l'IP du pod, pour le"
  echo "  pod runc comme pour le pod Kata : règle de journalisation de la chaîne de la politique (préfixe « DROP by policy"
  echo "  builds/$SONDE »), puis celle de la chaîne du pod, avant le REJECT (règles relevées au premier passage, archivé :"
  echo "  kata-reseau-premiere-prediction.log ; une seule ligne par SYN était prédite). Chaque règle a son plafond (10 par minute) ;"
  echo "- usurpation, pod Kata privilégié (root, NET_ADMIN dans l'invité) : avec son IP, Zot refusé et journalisé ; avec une"
  echo "  adresse inutilisée du sous-réseau des pods ($USURPEE), Zot, SSH de sc-stockage, API et kubelet local joignables,"
  echo "  et une requête en clair à Zot obtient la réponse de son serveur TLS (« HTTP/1.0 400 Bad Request », serveur Go) :"
  echo "  kube-router ne filtre la sortie que par l'IP source des pods qu'il connaît ; la réponse revient par cni0 (ARP résolu"
  echo "  par l'invité) ; aucune trace NFLOG pour l'adresse usurpée, aucune règle de kube-router ne la mentionne ;"
  echo "- témoins sans NET_ADMIN, pod Kata restreint (posture de la voie D) et pod runc restreint (posture de publier) : ajout de"
  echo "  l'adresse refusé (« Operation not permitted »), liaison de nc à l'adresse refusée (adresse non locale)"
  echo "## état de départ"
  echo "NetworkPolicy de builds : $(kubectl get netpol -n builds -o name | tr '\n' ' ')"
  n=$(kubectl get netpol -n builds -o name | { grep -x "networkpolicy.networking.k8s.io/$SONDE" || true; } | wc -l)
  [ "$n" = 0 ] && echo "OK   pas de politique $SONDE résiduelle" || { echo "KO   politique $SONDE résiduelle" >&2; exit 1; }
  echo "sc-build : bridge-nf-call-iptables $(sur sc-build 'cat /proc/sys/net/bridge/bridge-nf-call-iptables'), rp_filter de cni0 \
$(sur sc-build 'cat /proc/sys/net/ipv4/conf/cni0/rp_filter') (2 : lâche), $(sur sc-build 'sudo iptables -S' | grep -c 'KUBE-ROUTER') règles KUBE-ROUTER"
  rm -f "$T/fenetres.txt" "$T/traces.txt"
  trap nettoyer_reseau EXIT
  kubectl apply -f "$here/kata/sonde-reseau.yaml" >/dev/null
  echo "NetworkPolicy $SONDE posée : sortie vers Forgejo (192.168.161.13:3000) seule, pour les pods app=$SONDE"

  echo "## fenêtre de démarrage, trois essais alternés runc et Kata"
  for i in 1 2 3; do
    for p in runc kata; do
      pod_reseau "j7-reseau-$p-$i" "$([ $p = kata ] && echo kata || echo -)" - "$FENETRE"
      pod_fini "j7-reseau-$p-$i"
      grep '^ESSAI|' "$T/j7-reseau-$p-$i.log" | awk -F'|' '{printf "  %5d ms : Zot %s ; Forgejo %s\n", $2, $3, $4}'
      IFS='|' read -r _ o d f < <(grep '^FENETRE|' "$T/j7-reseau-$p-$i.log")
      echo "  Zot joignable $o fois, la dernière à $d ms du lancement ; puis $f refus de suite"
      [ "$f" = 3 ] || { echo "KO   $p-$i : règle jamais appliquée en 60 s" >&2; ko=1; }
      echo "$p $o" >> "$T/fenetres.txt"
      grep '^SORTIE|' "$T/j7-reseau-$p-$i.log" | awk -F'|' '{print "  " $4 " " $2 " " $3}'
      s=$(grep '^SORTIE|' "$T/j7-reseau-$p-$i.log" | awk -F'|' '$4 == "OUVERT" {print $2}' | tr '\n' ' ')
      [ "$s" = "Forgejo " ] && echo "OK   $p-$i : une fois la règle posée, Forgejo seul ouvert" \
        || { echo "KO   $p-$i : ouverts : $s" >&2; ko=1; }
      kubectl delete pod -n builds "j7-reseau-$p-$i" --wait=false >/dev/null
    done
  done
  for p in runc kata; do
    n=$(awk -v p=$p '$1 == p && $2 > 0' "$T/fenetres.txt" | wc -l)
    [ "$n" -ge 1 ] && echo "CONSTAT  $p : fenêtre ouverte dans $n essai(s) sur 3 (Zot joignable avant la pose de la règle)" \
      || { echo "KO   $p : aucune fenêtre observée en 3 essais (prédiction : au moins une)" >&2; ko=1; }
  done
  rm -f "$T/fenetres.txt"

  echo "## trace NFLOG sur sc-build (règle limitée à 10 par minute, rafale de 10 : attente de 65 s avant la capture)"
  sleep 65
  capture "$T/nflog-trace.txt" 60 -i nflog:100
  pod_reseau j7-reseau-trace-runc - - "$TRACE"
  pod_reseau j7-reseau-trace-kata kata - "$TRACE"
  for p in runc kata; do
    pod_fini "j7-reseau-trace-$p"
    sed 's/^/  /' "$T/j7-reseau-trace-$p.log"
    ip=$(ip_pod "j7-reseau-trace-$p")
    o=$(grep -c '|FERME$' "$T/j7-reseau-trace-$p.log" || true)
    echo "$p $ip $o" >> "$T/traces.txt"
  done
  wait "$CAPTURE" || true
  grep -E 'packets (captured|received)' "$T/nflog-trace.txt" | sed 's/^/  tcpdump : /' || true
  while read -r p ip o; do
    n=$(syn "$T/nflog-trace.txt" "$ip" 192.168.161.13.5000)
    d=$(syn_distincts "$T/nflog-trace.txt" "$ip" 192.168.161.13.5000)
    grep -E "IP ${ip//./\\.}\." "$T/nflog-trace.txt" | sed 's/^/  /' || true
    [ "$o" = 3 ] && [ "$d" = 3 ] && [ "$n" = 6 ] && echo "OK   $p ($ip) : 3 connexions refusées, 3 SYN distincts vers Zot dans NFLOG, 2 lignes chacun" \
      || { echo "KO   $p ($ip) : $o refus, $d SYN distincts et $n lignes dans NFLOG" >&2; ko=1; }
  done < "$T/traces.txt"
  rm -f "$T/traces.txt"
  for p in runc kata; do kubectl delete pod -n builds "j7-reseau-trace-$p" --wait=false >/dev/null; done

  echo "## usurpation d'adresse source : témoins sans NET_ADMIN (pods restreints, capacités retirées)"
  for p in runc kata; do
    pod_reseau "j7-reseau-temoin-$p" "$([ $p = kata ] && echo kata || echo -)" - "$TEMOIN_USURPATION"
    pod_fini "j7-reseau-temoin-$p"
    sed 's/^/  /' "$T/j7-reseau-temoin-$p.log"
    grep -q '^AJOUT|refusé|' "$T/j7-reseau-temoin-$p.log" && grep -q '^LIAISON|refusée|' "$T/j7-reseau-temoin-$p.log" \
      && echo "OK   $p restreint : ajout de $USURPEE refusé, liaison de nc refusée" \
      || { echo "KO   $p restreint : $(tr '\n' ' ' < "$T/j7-reseau-temoin-$p.log")" >&2; exit 1; }
    kubectl delete pod -n builds "j7-reseau-temoin-$p" --wait=false >/dev/null
  done
  echo "## usurpation d'adresse source : pod Kata privilégié (attente de 65 s : plafond de NFLOG)"
  sleep 65
  n=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | grep -cxF "$USURPEE" || true)
  sur sc-build "sudo test ! -e /var/lib/cni/networks/cbr0/$USURPEE" && [ "$n" = 0 ] \
    && echo "OK   $USURPEE inutilisée : ni réservée par l'IPAM de sc-build (host-local, cbr0), ni portée par un pod" \
    || { echo "KO   $USURPEE en usage" >&2; exit 1; }
  capture "$T/nflog-usurpation.txt" 70 -i nflog:100
  capture "$T/usurpation.txt" 70 -i any host "$USURPEE"
  pod_reseau j7-reseau-usurpation kata privilegie "$USURPATION"
  for _ in $(seq 120); do
    kubectl logs -n builds j7-reseau-usurpation > "$T/j7-reseau-usurpation.log" 2>/dev/null || true
    grep -qx FIN "$T/j7-reseau-usurpation.log" && break; sleep 1
  done
  grep -qx FIN "$T/j7-reseau-usurpation.log" || { kubectl describe pod -n builds j7-reseau-usurpation >&2; echo "KO   essai d'usurpation non terminé" >&2; exit 1; }
  ip=$(ip_pod j7-reseau-usurpation)
  sur sc-build 'sudo iptables -S' > "$T/iptables-usurpation.txt"
  sur sc-build "ip neigh show $USURPEE" > "$T/voisin-usurpation.txt"
  pod_fini j7-reseau-usurpation
  sed 's/^/  /' "$T/j7-reseau-usurpation.log"
  wait
  echo "  règles iptables de sc-build pendant l'essai : $(grep -c -- "$ip/32" "$T/iptables-usurpation.txt" || true) avec l'IP du pod ($ip), \
$(grep -c -- "$USURPEE" "$T/iptables-usurpation.txt" || true) avec $USURPEE"
  echo "  voisin $USURPEE sur sc-build : $(cat "$T/voisin-usurpation.txt")"
  grep -E 'packets (captured|received)' "$T/nflog-usurpation.txt" "$T/usurpation.txt" | sed 's/^/  tcpdump : /' || true
  grep -E "IP ${ip//./\\.}\.|$USURPEE" "$T/nflog-usurpation.txt" | sed 's/^/  NFLOG : /' || true
  grep -E "ARP|Flags \[S" "$T/usurpation.txt" | sed 's/^/  any : /' || true
  grep -qx 'AVANT|Zot|FERME' "$T/j7-reseau-usurpation.log" && grep -qx 'AVANT|Forgejo|OUVERT' "$T/j7-reseau-usurpation.log" \
    && grep -qx 'APRES|Zot|FERME' "$T/j7-reseau-usurpation.log" \
    && echo "OK   témoin : avec l'IP du pod, Zot refusé (avant et après), Forgejo ouvert" || { echo "KO   témoin" >&2; ko=1; }
  n=$(syn "$T/nflog-usurpation.txt" "$ip" 192.168.161.13.5000)
  d=$(syn_distincts "$T/nflog-usurpation.txt" "$ip" 192.168.161.13.5000)
  [ "$d" = 2 ] && [ "$n" = 4 ] && echo "OK   NFLOG : 2 SYN distincts du pod ($ip) vers Zot, ceux du témoin, 2 lignes chacun" \
    || { echo "KO   NFLOG : $d SYN distincts et $n lignes du pod vers Zot (2 et 4 attendus)" >&2; ko=1; }
  n=$(grep -c -- "$USURPEE" "$T/nflog-usurpation.txt" || true)
  [ "$n" = 0 ] && echo "CONSTAT  NFLOG : aucune trace de $USURPEE" || echo "CONSTAT  NFLOG : $n ligne(s) avec $USURPEE"
  s=$(grep '^USURPEE|' "$T/j7-reseau-usurpation.log" | awk -F'|' '$4 == "OUVERT" {print $2}' | tr '\n' ' ')
  [ "$s" = "Zot SSH-stockage API-noeud kubelet-local " ] \
    && echo "CONSTAT  avec $USURPEE, la NetworkPolicy est contournée : ouverts : $s" \
    || { echo "KO   avec $USURPEE, ouverts : ${s:-aucun} (prédiction : Zot SSH-stockage API-noeud kubelet-local)" >&2; ko=1; }
  grep -qx 'ECHANGE|Zot|HTTP/1.0 400 Bad Request' "$T/j7-reseau-usurpation.log" \
    && echo "CONSTAT  avec $USURPEE, échange de données avec Zot : requête envoyée, réponse lue (HTTP/1.0 400 Bad Request)" \
    || { echo "KO   échange avec Zot : $(grep '^ECHANGE|' "$T/j7-reseau-usurpation.log")" >&2; ko=1; }
  echo "  capture -i any (chaque paquet vu sur la veth du pod et sur cni0) : $(syn_distincts "$T/usurpation.txt" "$USURPEE" 192.168.161.13.5000) \
connexion(s) de $USURPEE vers Zot, $(grep -cE "192\.168\.161\.13\.5000 > ${USURPEE//./\\.}\.[0-9]+: Flags \[S\.\]" "$T/usurpation.txt" || true) lignes SYN-ACK en retour, \
$(grep -cE "ARP, Reply ${USURPEE//./\\.} is-at" "$T/usurpation.txt" || true) lignes de réponse ARP pour $USURPEE"

  echo "## retrait"
  kubectl delete pod -n builds -l "app=$SONDE" --ignore-not-found --wait=true >/dev/null
  kubectl delete -f "$here/kata/sonde-reseau.yaml" >/dev/null
  trap - EXIT
  for _ in $(seq 30); do n=$(sur sc-build 'sudo iptables -S' | grep -c "builds/$SONDE" || true); [ "$n" = 0 ] && break; sleep 1; done
  [ "$(kubectl get netpol -n builds -o name | { grep -x "networkpolicy.networking.k8s.io/$SONDE" || true; } | wc -l)" = 0 ] && [ "$n" = 0 ] \
    && echo "OK   NetworkPolicy et pods de mesure retirés ; aucune règle de kube-router pour builds/$SONDE sur sc-build" \
    || { echo "KO   retrait incomplet ($n règle(s))" >&2; ko=1; }
  [ "$ko" = 0 ] || exit 1
}

lancer kata J7 "$@"
