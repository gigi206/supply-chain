#!/usr/bin/env bash
# Essai à sec de helmfile : vérification de l'installation de helmfile 1.8.4 par mise (accord du propriétaire du 18/11/2026,
# « Oui, après relances »). Lancé APRÈS l'ajout à mise.toml, mise lock et mise install. Rien n'est installé ici :
#   1. ligne de mise.lock (url, somme) ;
#   2. tarball et checksums.txt de la release, téléchargés à part dans un dossier neuf ; somme comparée à checksums.txt et à mise.lock ;
#   3. gh attestation verify du tarball, avec le workflow signataire attendu par le registre aqua ;
#   4. binaire installé par mise (mise which) comparé au binaire extrait du tarball vérifié.
# Usage (racine du dépôt) : bash poc/benchmarks/deploiement/essai-helmfile/installation.sh > poc/benchmarks/deploiement/resultats/<journal neuf> 2>&1
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C
V=1.8.4 T=helmfile_1.8.4_linux_amd64.tar.gz
W=$HOME/.cache/supply-chain-poc/dep-hf-installation-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$W" ] || { echo "KO   $W existe" >&2; exit 1; }
mkdir -p "$W/telechargement" "$W/extrait"
echo "# installation.sh (helmfile $V), début $(date -u +%FT%TZ) ; dossier $W"
echo "## 1. mise.toml et mise.lock"
grep -n 'aqua:helmfile/helmfile' mise.toml
l=$(awk '/^\[\[tools."aqua:helmfile\/helmfile"\]\]/{f=1} f&&/^$/{n++} f&&n<2{print} n>=2{exit}' mise.lock)
echo "$l" | sed 's/^/  /'
lsum=$(echo "$l" | sed -nE 's/^checksum = "sha256:([0-9a-f]{64})"/\1/p'); lurl=$(echo "$l" | sed -nE 's/^url = "(.*)"/\1/p')
[ -n "$lsum" ] && [ -n "$lurl" ] || { echo "KO   somme ou url absente de mise.lock"; exit 1; }
echo "## 2. release téléchargée à part"
u=https://github.com/helmfile/helmfile/releases/download/v$V
curl -fsSL --max-time 120 -o "$W/telechargement/$T" "$u/$T"
curl -fsSL --max-time 60 -o "$W/telechargement/helmfile_${V}_checksums.txt" "$u/helmfile_${V}_checksums.txt"
s=$(sha256sum < "$W/telechargement/$T" | cut -c1-64)
c=$(awk -v t="$T" '$2==t{print $1}' "$W/telechargement/helmfile_${V}_checksums.txt")
echo "tarball : $(stat -c %s "$W/telechargement/$T") octets, sha256 $s ; checksums.txt : $c ; mise.lock : $lsum"
[ "$s" = "$c" ] && echo "OK   somme égale à checksums.txt" || { echo "KO   somme différente de checksums.txt"; exit 1; }
[ "$s" = "$lsum" ] && echo "OK   somme égale à mise.lock" || { echo "KO   somme différente de mise.lock"; exit 1; }
[ "$lurl" = "$u/$T" ] && echo "OK   url de mise.lock = $u/$T" || echo "ÉCART url de mise.lock : $lurl"
echo "## 3. attestation d'artefact (GitHub)"
env -u GITHUB_TOKEN gh attestation verify "$W/telechargement/$T" --repo helmfile/helmfile \
  --signer-workflow helmfile/helmfile/.github/workflows/releaser.yaml --format json > "$W/attestation.json"
echo "OK   gh attestation verify : code 0"
jq -r '.[0].verificationResult.signature.certificate | "émetteur : \(.issuer) ; workflow : \(.buildSignerURI) ; dépôt : \(.sourceRepositoryURI) ; ref : \(.sourceRepositoryRef) ; commit : \(.sourceRepositoryDigest)"' "$W/attestation.json"
echo "## 4. binaire installé par mise"
b=$(mise which helmfile)
tar -xzf "$W/telechargement/$T" -C "$W/extrait" helmfile
echo "mise which helmfile : $b"
echo "installé : sha256 $(sha256sum < "$b" | cut -c1-64) ; extrait du tarball vérifié : sha256 $(sha256sum < "$W/extrait/helmfile" | cut -c1-64)"
cmp -s "$b" "$W/extrait/helmfile" && echo "OK   binaire installé identique au binaire du tarball vérifié" || { echo "KO   binaire installé différent"; exit 1; }
echo "version : $("$b" --version 2>&1 | head -1)"
echo "# fin $(date -u +%FT%TZ)"
