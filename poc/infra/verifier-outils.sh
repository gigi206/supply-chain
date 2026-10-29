#!/usr/bin/env bash
# Vérifie les outils déclarés dans mise.toml : chaque artefact de mise.lock (linux-x64)
# est retéléchargé, son sha256 comparé au verrou et au fichier de sommes amont, puis sa
# signature vérifiée quand le projet en publie une. Les signatures sigstore sont
# vérifiées avec le cosign du nixpkgs épinglé (canal indépendant de mise), les
# signatures GPG dans un trousseau temporaire, les attestations GitHub avec `gh`
# (racine de confiance GitHub, absente de cosign).
#
# Usage (depuis la racine du dépôt) : mise run outils:verifier
# Variables : POC_OUTILS (posée par mise.toml), COSIGN (défaut : $POC_OUTILS/cosign-nix/bin/cosign).
set -uo pipefail
export LC_ALL=C

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
COSIGN=${COSIGN:-$POC_OUTILS/cosign-nix/bin/cosign}
W=$(mktemp -d)
export GNUPGHOME=$W/gnupg
mkdir -m 700 "$GNUPGHOME"
trap 'rm -rf -- "$W"' EXIT
ko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; ko=1; }
na() { echo "--   $*"; }
get() { curl -fsSL --retry 2 --max-time 120 -o "$W/${2:-${1##*/}}" "$1"; }
relurl() { echo "https://github.com/$1/releases/download/$2/$3"; }
sigstore() { # $1 = nom, $2 = dépôt GitHub (identité attendue : ses workflows), $3… = options de verify-blob
  local n=$1 r=$2
  shift 2
  sigstore_id "$n" "workflows de github.com/$r" --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    --certificate-identity-regexp "^https://github.com/$r/" "$@"
}
sigstore_id() { # $1 = nom, $2 = identité lisible, $3… = options de verify-blob (identité comprise)
  local n=$1 id=$2
  shift 2
  if "$COSIGN" verify-blob "$@" >"$W/cosign.log" 2>&1; then
    ok "$n : signature sigstore ($id)"
  else
    ko "$n : signature sigstore refusée ($(tail -1 "$W/cosign.log"))"
  fi
}
gpgv() { # $1 = nom, $2 = clés, $3 = signature, $4 = fichier signé
  gpg -q --import "$2" 2>/dev/null
  if gpg --status-fd 1 --verify "$3" "$4" 2>/dev/null >"$W/gpg.log" && grep -q '^\[GNUPG:\] VALIDSIG' "$W/gpg.log"; then
    ok "$1 : signature GPG, clé $(awk '/VALIDSIG/ {print $NF}' "$W/gpg.log" | head -1)"
  else
    ko "$1 : signature GPG refusée"
  fi
}

echo "# verifier-outils.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), vérificateur sigstore : $("$COSIGN" version 2>/dev/null | awk '/GitVersion/ {print $2}') (nixpkgs épinglé)"
python3 -I - "$repo/mise.lock" > "$W/lock.tsv" <<'PY'
import sys, tomllib
for name, entries in tomllib.load(open(sys.argv[1], "rb"))["tools"].items():
    for e in entries:
        p = e["platforms.linux-x64"]
        print(name, e["version"], p["checksum"].removeprefix("sha256:"), p["url"], sep="\t")
PY

while IFS=$'\t' read -r name ver sum url; do
  f=${url##*/}
  if ! get "$url"; then ko "$name $ver : téléchargement impossible"; continue; fi
  got=$(sha256sum "$W/$f" | cut -c1-64)
  [ "$got" = "$sum" ] && ok "$name $ver : sha256 = mise.lock ($sum)" || { ko "$name $ver : sha256 $got ≠ mise.lock $sum"; continue; }
  case "$name" in
    aqua:sigstore/cosign)
      # Identité documentée par Sigstore (docs.sigstore.dev, « Verifying Cosign releases »).
      get "$url.sigstore.json" && sigstore_id "$name" "keyless@projectsigstore.iam.gserviceaccount.com, émetteur accounts.google.com" \
        --certificate-identity keyless@projectsigstore.iam.gserviceaccount.com \
        --certificate-oidc-issuer https://accounts.google.com --bundle "$W/$f.sigstore.json" "$W/$f" ;;
    aqua:kyverno/kyverno)
      get "$url.sigstore.json" && sigstore "$name" kyverno/kyverno --bundle "$W/$f.sigstore.json" "$W/$f" ;;
    aqua:kubernetes/kubernetes/kubectl)
      # Identité documentée par Kubernetes (kubernetes.io, « Verify Signed Kubernetes Artifacts »).
      get "$url.sig" && get "$url.cert" && sigstore_id "$name" "krel-staging@k8s-releng-prod.iam.gserviceaccount.com, émetteur accounts.google.com" \
        --certificate-identity krel-staging@k8s-releng-prod.iam.gserviceaccount.com \
        --certificate-oidc-issuer https://accounts.google.com --signature "$W/$f.sig" --certificate "$W/$f.cert" "$W/$f" ;;
    forgejo:forgejo/forgejo)
      # Clé de l'équipe de release : empreinte publiée sur forgejo.org/download, clé tirée de keys.openpgp.org.
      fpr=EB114F5E6C0DC2BCDD183550A4B61A2DC5923710
      get "$url.asc" && get "https://keys.openpgp.org/vks/v1/by-fingerprint/$fpr" forgejo.pub \
        && gpgv "$name" "$W/forgejo.pub" "$W/$f.asc" "$W/$f" \
        && { awk '/VALIDSIG/ {print $NF}' "$W/gpg.log" | grep -qx "$fpr" \
          && ok "$name : clé principale = empreinte publiée sur forgejo.org" || ko "$name : clé principale ≠ $fpr"; } ;;
    aqua:anchore/syft|aqua:anchore/grype)
      p=${name#aqua:anchore/}
      c=${p}_${ver}_checksums.txt
      get "$(relurl "anchore/$p" "v$ver" "$c")" && get "$(relurl "anchore/$p" "v$ver" "$c.sig")" && get "$(relurl "anchore/$p" "v$ver" "$c.pem")" \
        && sigstore "$name" "anchore/$p" --certificate "$W/$c.pem" --signature "$W/$c.sig" "$W/$c" \
        && { grep -q "^$sum  $f$" "$W/$c" && ok "$name : sha256 présent dans $c signé" || ko "$name : sha256 absent de $c"; } ;;
    aqua:oras-project/oras)
      get "$url.asc" && get "https://raw.githubusercontent.com/oras-project/oras/v$ver/KEYS" oras.KEYS \
        && gpgv "$name" "$W/oras.KEYS" "$W/$f.asc" "$W/$f" ;;
    aqua:opencontainers/runc)
      get "$url.asc" && get "https://raw.githubusercontent.com/opencontainers/runc/v$ver/runc.keyring" runc.keyring \
        && gpgv "$name" "$W/runc.keyring" "$W/$f.asc" "$W/$f" ;;
    aqua:rootless-containers/rootlesskit)
      get "$(relurl rootless-containers/rootlesskit "v$ver" SHA256SUMS)" && get "$(relurl rootless-containers/rootlesskit "v$ver" SHA256SUMS.asc)" \
        && get https://github.com/AkihiroSuda.gpg akihirosuda.gpg \
        && gpgv "$name" "$W/akihirosuda.gpg" "$W/SHA256SUMS.asc" "$W/SHA256SUMS" \
        && { grep -q "^$sum  \*\?$f$" "$W/SHA256SUMS" && ok "$name : sha256 présent dans SHA256SUMS signé" || ko "$name : sha256 absent de SHA256SUMS"; } ;;
    node)
      # SHASUMS256.txt signé par l'équipe de release (clés actives de github.com/nodejs/release-keys).
      get "${url%/*}/SHASUMS256.txt" && get "${url%/*}/SHASUMS256.txt.sig" \
        && get https://raw.githubusercontent.com/nodejs/release-keys/main/gpg-only-active-keys/pubring.kbx node.kbx \
        && gpg -q --no-default-keyring --keyring "$W/node.kbx" --export > "$W/node.keys" \
        && gpgv "$name" "$W/node.keys" "$W/SHASUMS256.txt.sig" "$W/SHASUMS256.txt" \
        && { grep -q "^$sum  $f$" "$W/SHASUMS256.txt" && ok "$name : sha256 présent dans SHASUMS256.txt signé" || ko "$name : sha256 absent de SHASUMS256.txt"; } ;;
    go)
      get "$url.asc" && get https://dl.google.com/linux/linux_signing_key.pub google.pub \
        && gpgv "$name" "$W/google.pub" "$W/$f.asc" "$W/$f" ;;
    python)
      # Attestation signée par l'instance Sigstore de GitHub (horodatage, sans journal Rekor) : `gh` porte sa racine de confiance.
      if ! command -v gh >/dev/null; then
        na "$name : attestation GitHub non vérifiée (gh absent) ; sha256 = SHA256SUMS amont"
      elif gh attestation verify "$W/$f" --repo astral-sh/python-build-standalone --format json >"$W/gh.json" 2>"$W/gh.log"; then
        ok "$name : attestation GitHub ($(jq -r '.[0].verificationResult.statement.predicateType' "$W/gh.json"), $(jq -r '.[0].verificationResult.signature.certificate.subjectAlternativeName' "$W/gh.json"))"
      else
        ko "$name : attestation GitHub refusée ($(tail -1 "$W/gh.log"))"
      fi ;;
    aqua:moby/buildkit)
      get "${url%.tar.gz}.provenance.json" "$f.provenance.json" \
        && { jq -e --arg s "$sum" '[.. | objects | select(.sha256? == $s)] | length > 0' "$W/$f.provenance.json" >/dev/null \
          && na "$name : aucune signature publiée ; sha256 cité par la provenance amont, non signée" \
          || ko "$name : sha256 absent de la provenance amont"; } ;;
    aqua:google/go-containerregistry|aqua:project-zot/zot|github:conforma/cli|aqua:kubernetes-sigs/kind)
      case "$name" in
        *go-containerregistry) c=checksums.txt; why="provenance SLSA publiée (multiple.intoto.jsonl), non vérifiée ici (il faut slsa-verifier)" ;;
        *zot) c=checksums.sha256.txt; why="aucune signature publiée (docs/04 §5)" ;;
        *kind) c=$f.sha256sum; why="aucune signature publiée" ;;
        *) c=$f.sha256; why="aucune signature publiée (docs/04 §5)" ;;
      esac
      get "${url%/*}/$c" sums.txt && grep -qE "^$sum [ *]?(dist/)?$f$" "$W/sums.txt" \
        && na "$name : $why ; sha256 présent dans $c amont, non signé" || ko "$name : sha256 absent de $c amont" ;;
    *) ko "$name : méthode de vérification inconnue" ;;
  esac
done < "$W/lock.tsv"

# Hors mise.lock : tâches outils:*.
v=$("$HERMETO" --version 2>/dev/null)
[ "$v" = "hermeto 0.64.0" ] && ok "hermeto : $v (tag 0.64.0 = commit 1f37e32d, dépendances installées avec --require-hashes)" || ko "hermeto : $v"
m=golang.org/toolchain@v0.0.1-go1.26.10.linux-amd64
s=$(cat "$POC_OUTILS/gomodcache/cache/download/golang.org/toolchain/@v/v0.0.1-go1.26.10.linux-amd64.ziphash" 2>/dev/null)
db=$(curl -fsS --max-time 30 "https://sum.golang.org/lookup/$m" | awk '$2 == "v0.0.1-go1.26.10.linux-amd64" {print $3}')
[ -n "$s" ] && [ "$s" = "$db" ] && ok "go 1.26.10 : module $m, $s = sum.golang.org" || ko "go 1.26.10 : $s ≠ sum.golang.org $db"
for l in busybox spdx-json reuse cosign-nix buildkit-nix runc-nix; do
  p=$(readlink -f "$POC_OUTILS/$l")
  nix path-info --sigs "$p" 2>/dev/null | grep -q 'cache.nixos.org-1:' \
    && ok "nix $(basename "$p") : signature cache.nixos.org-1" || ko "nix $p : signature absente"
done

exit $ko
