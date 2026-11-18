#!/usr/bin/env bash
# Évaluation du déploiement (hors ADR 0000) : lecture des manifestes de release et de la doc aux tags épinglés, par l'API de
# GitHub et le registre (cosign tree, lecture seule). Rien n'est installé, aucun binaire n'est téléchargé (manifestes YAML et Markdown seulement).
# Usage (racine du dépôt) : bash poc/benchmarks/deploiement/lecture.sh > poc/benchmarks/deploiement/resultats/<journal neuf> 2>&1
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C
D=$HOME/.cache/supply-chain-poc/dep-lecture-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$D" ] || { echo "KO   $D existe" >&2; exit 1; }
mkdir -p "$D"
g() { env -u GITHUB_TOKEN gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/$2?ref=$3" > "$D/$4"; echo "lu : $1 $2 @ $3 -> $4 ($(stat -c %s "$D/$4") octets, sha256 $(sha256sum < "$D/$4" | cut -c1-16))"; }
x() { echo "--- $1, l. $2 à $3"; sed -n "$2,$3p" "$D/$1" | nl -ba -v "$2" -w4 -s ' | '; }
echo "# lecture.sh (déploiement), début $(date -u +%FT%TZ) ; dossier $D"
g argoproj/argo-cd manifests/install.yaml v3.6.2 argocd-install.yaml
curl -fsSL --max-time 60 -o "$D/flux-install.yaml" https://github.com/fluxcd/flux2/releases/download/v2.10.0/install.yaml
echo "lu : install.yaml de la release flux2 v2.10.0 ($(stat -c %s "$D/flux-install.yaml") octets, sha256 $(sha256sum < "$D/flux-install.yaml" | cut -c1-16))"
g argoproj/argo-cd docs/user-guide/source-integrity.md v3.6.2 argocd-integrity.md
g argoproj/argo-cd docs/user-guide/gpg-verification.md v3.6.2 argocd-gpg.md
g argoproj/argo-cd docs/user-guide/oci.md v3.6.2 argocd-oci.md
g fluxcd/source-controller docs/spec/v1/gitrepositories.md v1.10.1 flux-git.md
g fluxcd/source-controller docs/spec/v1/ocirepositories.md v1.10.1 flux-oci.md
g helmfile/helmfile README.md v1.8.4 helmfile-readme.md
g helmfile/helmfile docs/index.md v1.8.4 helmfile-index.md
g helmfile/helmfile docs/configuration.md v1.8.4 helmfile-config.md
g helmfile/helmfile go.mod v1.8.4 helmfile-go.mod

echo; echo "## G1, G2 : ClusterRoles larges (ressource * ou secrets) et leurs liaisons, manifestes par défaut"
for f in argocd-install.yaml flux-install.yaml; do
  echo "### $f"
  yq -o=json . "$D/$f" | jq -c -s '.[] | select(.kind=="ClusterRole") | {name: .metadata.name, rules: [.rules[] | select(((.resources // []) | index("*")) or ((.resources // []) | index("secrets"))) | {apiGroups, resources, verbs}]} | select(.rules | length > 0)'
  yq -o=json . "$D/$f" | jq -c -s '.[] | select(.kind=="ClusterRoleBinding") | {name: .metadata.name, role: .roleRef.name, sa: [.subjects[] | .name]}'
done
echo; echo "## G6, G8 : composants et images des manifestes par défaut"
for f in argocd-install.yaml flux-install.yaml; do
  echo "### $f : $(yq -o=json . "$D/$f" | jq -r -s '[.[] | select(.kind=="Deployment" or .kind=="StatefulSet") | .metadata.name] | join(" ")')"
  grep -oE 'image: *[^ ]+' "$D/$f" | sort | uniq -c
done
echo; echo "## G6 : signatures des images au tag (cosign tree, lecture du registre)"
for i in quay.io/argoproj/argocd:v3.6.2 ghcr.io/dexidp/dex:v2.46.0 public.ecr.aws/docker/library/redis:8.10.1-alpine ghcr.io/fluxcd/kustomize-controller:v1.10.1 ghcr.io/fluxcd/helm-controller:v1.7.1 ghcr.io/fluxcd/source-controller:v1.10.1; do
  echo "### $i"; cosign tree "$i" 2>&1 | grep -E 'Signatures|Attestations|SBOMs|Error|error' | sed 's/^/  /' || echo "  (aucune ligne de signature, d'attestation ni de SBOM)"
done
echo; echo "## G4, Argo CD : intégrité des sources"; x argocd-integrity.md 1 29; x argocd-gpg.md 1 6
echo "--- argocd-oci.md : lignes qui citent signature, cosign, verif ou digest"; grep -n -i 'signature\|cosign\|verif\|digest' "$D/argocd-oci.md" | cut -c1-200 || echo "(aucune)"
echo; echo "## G4, Flux : vérification des commits (gitrepositories.md)"; grep -n -i 'SSH-signed\|OpenPGP\|^### Verification\|mode:' "$D/flux-git.md" | cut -c1-200 | head -12; x flux-git.md 706 716
echo; echo "## G4, Flux : vérification des artefacts OCI (ocirepositories.md)"; x flux-oci.md 611 616
echo "--- flux-oci.md : épinglage par digest"; grep -n -i '\.digest\|ref.digest\|digest:' "$D/flux-oci.md" | cut -c1-180 | head -5
echo; echo "## G4, G3, G8 : helmfile"
grep -n -i 'helm-diff\|helmfile init' "$D/helmfile-readme.md" | cut -c1-200
grep -n -i 'supports both Helm\|Helm 3+' "$D/helmfile-index.md" | cut -c1-200
grep -n 'helm.sh/helm' "$D/helmfile-go.mod"
grep -n -i '^ *verify:' "$D/helmfile-config.md" | cut -c1-120
echo "--- helmfile-config.md : épinglage par digest (@sha256 ou digest)"; grep -n -i '@sha256\|digest' "$D/helmfile-config.md" | cut -c1-160 || echo "(aucune mention)"
echo; echo "## G6 : versions corrigées des avis critiques d'Argo CD publiés en 2026"
env -u GITHUB_TOKEN gh api "repos/argoproj/argo-cd/security-advisories?per_page=100" \
  --jq '.[] | select(.published_at > "2026-01-01" and .severity == "critical") | "\(.ghsa_id)\t\(.published_at[0:10])\tcorrigé en : \([.vulnerabilities[].patched_versions] | join(" ; "))"'
echo; echo "## SECURITY.md de l'organisation fluxcd"
env -u GITHUB_TOKEN gh api "repos/fluxcd/.github/contents" --jq '.[].name' 2>/dev/null | grep -i security | sed 's/^/fluxcd\/.github : /' || echo "fluxcd/.github : aucun fichier de sécurité à la racine"
env -u GITHUB_TOKEN gh api "repos/fluxcd/community/contents" --jq '.[].name' 2>/dev/null | grep -i security | sed 's/^/fluxcd\/community : /' || true
echo; echo "# fin $(date -u +%FT%TZ)"
