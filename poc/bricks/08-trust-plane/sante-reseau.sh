#!/usr/bin/env bash
# Brique 08, J7 : santé des candidats de l'option 1 du contrôle de sortie de la zone build (anti-usurpation côté nœud), selon
# les critères du doc 04 (§1), sans rien installer. Preuves des lignes Cilium et kube-router amont du doc 04 (§2, §3, §5, §6).
#   releves     Scorecard (API publique, tools/health/scorecard.sh), dernière release, commits sur 90 jours, auteurs et domaines
#               des adresses (hors robots), fusionneurs des 100 dernières PR, DCO ou CLA, SECURITY.md, avis publiés
#   signatures  images signées sans clé : cosign verify avec l'identité exacte du workflow au tag (documentée pour Cilium, lue
#               dans le workflow au tag pour kube-router), témoin d'identité refusé ; types des signatures (image et SBOM) ;
#               provenance cherchée (attestations SLSA par cosign, attestations GitHub, manifestes d'attestation de l'index) ;
#               binaire linux_amd64 de kube-router : sha256 face à checksums.txt, provenance SLSA v1 par gh attestation verify
#               (workflow signataire exact au tag ; témoin : autre workflow refusé)
#
# Usage (racine du dépôt) : mise run confiance:sante-reseau -- <étape>…   (journal : resultats/sante-reseau-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
DEPUIS=2026-08-01T00:00:00Z   # 90 jours avant le relevé du 30/10/2026
CILIUM_TAG=v1.20.4
CILIUM_ID=https://github.com/cilium/cilium/.github/workflows/build-images-releases.yaml@refs/tags/$CILIUM_TAG   # documentée
KR_TAG=v2.11.2
KR_ID=https://github.com/cloudnativelabs/kube-router/.github/workflows/ci-container.yml@refs/tags/$KR_TAG       # workflow au tag
KR_SIGNATAIRE=cloudnativelabs/kube-router/.github/workflows/ci-release.yml                                    # binaires
OIDC=https://token.actions.githubusercontent.com
T=$W/sante-reseau
mkdir -p "$T"

etape_releves() {
  local r
  printf 'Cilium\tcilium/cilium\tréseau\toui\nkube-router (amont)\tcloudnativelabs/kube-router\tréseau\toui\n' > "$T/projets.tsv"
  "$repo/tools/health/scorecard.sh" "$T/projets.tsv"
  for r in cilium/cilium cloudnativelabs/kube-router; do
    echo "## $r"
    gh api "repos/$r" --jq '"archivé \(.archived), licence \(.license.spdx_id)"'
    echo "dernière release : $(gh release list --repo "$r" --limit 1 --exclude-pre-releases --json tagName,publishedAt,isLatest --jq '.[0] | "\(.tagName) du \(.publishedAt[0:10])"')"
    gh api "repos/$r/commits?since=$DEPUIS&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), (.commit.author.email | split("@")[1]), (.author.type // "-")] | @tsv' > "$T/commits.tsv"
    echo "commits depuis $DEPUIS : $(wc -l < "$T/commits.tsv") ; auteurs humains les plus actifs (compte, domaine de l'adresse) :"
    awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1 "\t" $2}' "$T/commits.tsv" | sort | uniq -c | sort -rn | head -12 | sed 's/^/  /'
    echo "fusionneurs des 100 dernières PR : $(gh pr list --repo "$r" --state merged --limit 100 --json mergedBy --jq '[.[] | .mergedBy.login] | group_by(.) | map("\(.[0]) \(length)") | join(", ")')"
    echo "période : $(gh pr list --repo "$r" --state merged --limit 100 --json mergedAt --jq '"\(.[-1].mergedAt[0:10]) à \(.[0].mergedAt[0:10])"')"
    echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null || echo absent)"
    echo "avis publiés : $(gh api "repos/$r/security-advisories?per_page=100" --jq 'length') dont $(gh api "repos/$r/security-advisories?per_page=100" --jq '[.[] | select(.published_at >= "2025-10-30")] | length') depuis le 30/10/2025 ; les plus récents :"
    gh api "repos/$r/security-advisories?per_page=100" --jq '.[0:4][] | "  \(.ghsa_id) \(.published_at[0:10]) \(.severity), corrigé en \(.vulnerabilities[0].patched_versions // "-")"'
  done
  echo "## DCO ou CLA (guides de contribution au dépôt)"
  echo "cilium : $(gh api repos/cilium/cilium/contents/Documentation/contributing/development/contributing_guide.rst --jq .content | base64 -d | grep -o -i -E 'developer certificate of origin|contributor license agreement' | sort -u | tr '\n' ' ')"
  echo "kube-router : $(for f in CONTRIBUTING.md docs/developing.md; do gh api "repos/cloudnativelabs/kube-router/contents/$f" --jq .content | base64 -d; done | grep -o -i -E 'developer certificate of origin|contributor license agreement|signed-off-by' | sort -u | tr '\n' ' ' || true) (rien trouvé si vide)"
}

verifie() { # libellé identité image : cosign verify, code de retour et types des signatures vérifiées
  local rc=0
  cosign verify --certificate-identity "$2" --certificate-oidc-issuer "$OIDC" "$3" > "$T/verify.json" 2> "$T/verify.err" || rc=$?
  echo "$1 : rc $rc$( [ "$rc" = 0 ] && echo " ; types $(jq -r '[.[].critical.type] | join(", ")' "$T/verify.json") ; digest $(jq -r '.[0].critical.image."docker-manifest-digest"' "$T/verify.json")" \
    || echo " ; $(grep -o -m1 'expected SAN value "[^"]*", got "[^"]*"' "$T/verify.err" || tail -1 "$T/verify.err")")"
}

attestation() { # libellé type identité image : cosign verify-attestation, code de retour
  local rc=0
  cosign verify-attestation --type "$2" --certificate-identity "$3" --certificate-oidc-issuer "$OIDC" "$4" > /dev/null 2>&1 || rc=$?
  echo "$1 ($2) : rc $rc"
}

etape_signatures() {
  local i d a rc
  echo "## Cilium $CILIUM_TAG (identité documentée : https://docs.cilium.io/en/stable/configuration/verify-image-signatures/)"
  for i in cilium operator-generic; do verifie "quay.io/cilium/$i:$CILIUM_TAG" "$CILIUM_ID" "quay.io/cilium/$i:$CILIUM_TAG"; done
  verifie "témoin : identité du tag v1.20.3" "${CILIUM_ID%v1.20.4}v1.20.3" "quay.io/cilium/cilium:$CILIUM_TAG"
  for a in slsaprovenance slsaprovenance1 slsaprovenance02 spdxjson; do attestation "attestation de l'image cilium" "$a" "$CILIUM_ID" "quay.io/cilium/cilium:$CILIUM_TAG"; done
  d=$(crane digest "quay.io/cilium/cilium:$CILIUM_TAG")
  echo "index de l'image cilium ($d) : $(crane manifest "quay.io/cilium/cilium:$CILIUM_TAG" | jq -r '[.manifests[]? | "\(.platform.os)/\(.platform.architecture)\(if .annotations["vnd.docker.reference.type"] then " (" + .annotations["vnd.docker.reference.type"] + ")" else "" end)"] | join(", ")')"
  if a=$(gh api "repos/cilium/cilium/attestations/$d" --jq '.attestations | length' 2>/dev/null); then echo "attestations GitHub de l'image cilium : $a"
  else echo "attestations GitHub de l'image cilium : aucune (HTTP 404)"; fi
  echo "## kube-router $KR_TAG (identité lue dans .github/workflows/ci-container.yml au tag ; non documentée)"
  verifie "docker.io/cloudnativelabs/kube-router:$KR_TAG" "$KR_ID" "docker.io/cloudnativelabs/kube-router:$KR_TAG"
  verifie "témoin : identité volontairement fausse" "https://example.invalid/identite" "docker.io/cloudnativelabs/kube-router:$KR_TAG"
  for a in slsaprovenance1 spdxjson; do attestation "attestation de l'image kube-router" "$a" "$KR_ID" "docker.io/cloudnativelabs/kube-router:$KR_TAG"; done
  rm -rf -- "${T:?}/release" && mkdir -p "$T/release"
  gh release download "$KR_TAG" --repo cloudnativelabs/kube-router -p checksums.txt -p "kube-router_${KR_TAG#v}_linux_amd64.tar.gz" -D "$T/release"
  (cd "$T/release" && grep "linux_amd64.tar.gz$" checksums.txt | sha256sum -c -)
  rc=0; gh attestation verify "$T/release/kube-router_${KR_TAG#v}_linux_amd64.tar.gz" --repo cloudnativelabs/kube-router --signer-workflow "$KR_SIGNATAIRE" \
    --source-ref "refs/tags/$KR_TAG" --predicate-type https://slsa.dev/provenance/v1 > /dev/null 2>&1 || rc=$?
  echo "provenance SLSA v1 du binaire linux_amd64 (signataire $KR_SIGNATAIRE au tag) : rc $rc"
  rc=0; gh attestation verify "$T/release/kube-router_${KR_TAG#v}_linux_amd64.tar.gz" --repo cloudnativelabs/kube-router \
    --signer-workflow cloudnativelabs/kube-router/.github/workflows/ci.yml > /dev/null 2>&1 || rc=$?
  echo "témoin : signataire ci.yml : rc $rc"
}

lancer sante-reseau J7 "$@"
