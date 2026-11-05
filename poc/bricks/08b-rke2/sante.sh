#!/usr/bin/env bash
# Brique 08b : santé de RKE2, cert-manager et local-path-provisioner, selon les critères du doc 04 (§1), sans rien installer.
# Preuves des lignes de ces projets au doc 04 (§2, §3, §5, §6).
#   releves     Scorecard (API publique, tools/health/scorecard.sh), dernière release, commits sur 90 jours, auteurs et domaines
#               des adresses (hors robots), fusionneurs des 100 dernières PR, SECURITY.md, avis publiés
#   signatures  sommes publiées de RKE2 à la version visée ; signatures cherchées sur les images (cosign tree) ; cert-manager :
#               cosign verify avec la clé publiée par le projet, témoin d'une autre image refusé
#   kubebench   mêmes critères pour kube-bench (D5 a)
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08b-rke2/sante.sh <étape>…   (journal : resultats/sante-<étape>.log)
set -uo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
R=$here/resultats
T=$HOME/.cache/supply-chain-poc/08b/sante
DEPUIS=2026-08-07T00:00:00Z   # 90 jours avant le relevé du 05/11/2026
RKE2_TAG=v1.35.9+rke2r1
RKE2_IMAGE=docker.io/rancher/rke2-runtime:v1.35.9-rke2r1
CM_TAG=v1.21.3
CM_CLE=https://cert-manager.io/public-keys/cert-manager-pubkey-2021-09-20.pem
LP_IMAGE=docker.io/rancher/local-path-provisioner:v0.0.37
GH=$(command -v gh)
gh() { env -u GITHUB_TOKEN "$GH" "$@"; }
mkdir -p "$R" "$T"

etape_releves() {
  local r
  printf 'RKE2\trancher/rke2\truntime\toui\ncert-manager\tcert-manager/cert-manager\tsignature\tnon\nlocal-path-provisioner\trancher/local-path-provisioner\tstockage\tnon\n' > "$T/projets.tsv"
  "$repo/tools/health/scorecard.sh" "$T/projets.tsv"
  for r in rancher/rke2 cert-manager/cert-manager rancher/local-path-provisioner; do
    echo "## $r"
    gh api "repos/$r" --jq '"archivé \(.archived), licence \(.license.spdx_id)"'
    echo "dernière release : $(gh api "repos/$r/releases/latest" --jq '"\(.tag_name) du \(.published_at[0:10])"')"
    gh api "repos/$r/commits?since=$DEPUIS&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), (.commit.author.email | split("@")[1]), (.author.type // "-")] | @tsv' > "$T/commits.tsv"
    echo "commits depuis $DEPUIS : $(wc -l < "$T/commits.tsv") ; auteurs humains les plus actifs (compte, domaine de l'adresse) :"
    awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1 "\t" $2}' "$T/commits.tsv" | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
    echo "fusionneurs des 100 dernières PR : $(gh pr list --repo "$r" --state merged --limit 100 --json mergedBy --jq '[.[] | .mergedBy.login] | group_by(.) | map("\(.[0]) \(length)") | join(", ")')"
    echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null || echo absent)"
    echo "avis publiés : $(gh api "repos/$r/security-advisories?per_page=100" --jq 'length') ; depuis un an : $(gh api "repos/$r/security-advisories?per_page=100" --jq '[.[] | select(.published_at > "2025-11-05")] | length')"
    gh api "repos/$r/security-advisories?per_page=100" --jq '.[0:4][] | "  \(.ghsa_id) \(.published_at[0:10]) \(.severity) \(.summary)"'
  done
}

etape_signatures() {
  local rc=0
  echo "## RKE2 $RKE2_TAG : sommes publiées (aucun fichier de signature dans la release)"
  gh api "repos/rancher/rke2/releases/tags/$(printf %s "$RKE2_TAG" | sed 's/+/%2B/')" --jq '.assets[].name' | grep -E 'sha256sum-amd64|\.sig$|\.pem$|\.bundle$|intoto|provenance' | sed 's/^/  /'
  curl -fsSL "https://github.com/rancher/rke2/releases/download/$(printf %s "$RKE2_TAG" | sed 's/+/%2B/')/sha256sum-amd64.txt" \
    | grep -E ' (rke2\.linux-amd64\.tar\.gz|rke2-images-core\.linux-amd64\.tar\.zst)$'
  echo "## signatures cherchées sur les images (cosign tree)"
  for i in "$RKE2_IMAGE" "$LP_IMAGE"; do
    rc=0; cosign tree "$i" > "$T/tree.txt" 2>&1 || rc=$?
    echo "$i : rc $rc ; $(grep -c -E 'Signatures|Attestations|SBOMs|https://' "$T/tree.txt") entrée(s)"; sed 's/^/  /' "$T/tree.txt" | head -8
  done
  echo "## cert-manager $CM_TAG, clé publiée par le projet"
  curl -fsSL "$CM_CLE" -o "$T/cert-manager.pem"
  echo "sha256 de la clé : $(sha256sum "$T/cert-manager.pem" | cut -d' ' -f1)"
  for i in controller webhook cainjector; do
    rc=0; cosign verify --signature-digest-algorithm sha512 --insecure-ignore-tlog --key "$T/cert-manager.pem" "quay.io/jetstack/cert-manager-$i:$CM_TAG" > "$T/verify.json" 2> "$T/verify.err" || rc=$?
    echo "cert-manager-$i : rc $rc$( [ "$rc" = 0 ] && echo " ; digest $(jq -r '.[0].critical.image."docker-manifest-digest"' "$T/verify.json")" || echo " ; $(tail -1 "$T/verify.err")")"
  done
  rc=0; cosign verify --signature-digest-algorithm sha512 --insecure-ignore-tlog --key "$T/cert-manager.pem" "$LP_IMAGE" > /dev/null 2> "$T/verify.err" || rc=$?
  echo "témoin : autre image avec la même clé : rc $rc (refus attendu) ; $(tail -1 "$T/verify.err")"
  echo "provenance cherchée : $(cosign tree "quay.io/jetstack/cert-manager-controller:$CM_TAG" 2>&1 | grep -c -i -E 'attestation|provenance') entrée(s)"
}

etape_kubebench() { # D5 a : outil lancé ponctuellement sur les nœuds, hors du chemin critique
  local r=aquasecurity/kube-bench
  printf 'kube-bench\t%s\tconformité\tnon\n' "$r" > "$T/projets.tsv"
  "$repo/tools/health/scorecard.sh" "$T/projets.tsv"
  gh api "repos/$r" --jq '"archivé \(.archived), licence \(.license.spdx_id)"'
  echo "dernière release : $(gh api "repos/$r/releases/latest" --jq '"\(.tag_name) du \(.published_at[0:10])"')"
  echo "fichiers de la release : $(gh api "repos/$r/releases/latest" --jq '[.assets[].name | select(test("checksums|sig$|pem$|bundle$|intoto"))] | join(", ")')"
  echo "commits depuis $DEPUIS : $(gh api "repos/$r/commits?since=$DEPUIS&per_page=100" --paginate --jq '.[].sha' | wc -l)"
  echo "fusionneurs des 100 dernières PR : $(gh pr list --repo "$r" --state merged --limit 100 --json mergedBy --jq '[.[] | .mergedBy.login] | group_by(.) | map("\(.[0]) \(length)") | join(", ")')"
  echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null || echo absent)"
  echo "avis publiés : $(gh api "repos/$r/security-advisories?per_page=100" --jq 'length')"
  echo "profils RKE2 : $(gh api "repos/$r/contents/cfg" --jq '[.[].name | select(startswith("rke2-"))] | join(" ")')"
}

for e in "$@"; do
  echo "# sante.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$R/sante-$e.log"
  "etape_$e" 2>&1 | tee -a "$R/sante-$e.log"
done
