#!/usr/bin/env bash
# Brique 08, jalon J7 : isolation par Kata Containers 4.3.1 sur sc-build.
#   verifier   sans rien installer : tag et release 4.3.1 (immuable, attestation de release GitHub) ; archive kata-static
#              (empreinte, attestation de release, attestation de build cherchée, contenu, configuration du shim par
#              défaut qemu-runtime-rs) ; chart et image kata-deploy (empreinte, digests des deux registres, signatures,
#              referrers et attestations cherchés, permissions des jobs de publication de l'image)
# L'installation attend l'accord du propriétaire (règle : rien au niveau système sans accord).
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

lancer kata J7 "$@"
