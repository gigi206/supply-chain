#!/usr/bin/env bash
# Évaluation du déploiement : lectures complémentaires après relecture par le conseiller (raison de l'option (b) et de D1, variantes
# d'installation d'Argo CD, bornage des droits de Flux, OpenPGP de Flux, verify et kustomize de helmfile, statut CNCF, images de Flux).
# Lecture seule (fichiers du dépôt, API de GitHub, cosign tree). Usage (racine du dépôt) :
#   bash poc/benchmarks/deploiement/lecture-2.sh > poc/benchmarks/deploiement/resultats/<journal neuf> 2>&1
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C
D=$HOME/.cache/supply-chain-poc/dep-lecture2-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$D" ] || { echo "KO   $D existe" >&2; exit 1; }
mkdir -p "$D"
g() { env -u GITHUB_TOKEN gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/$2?ref=$3" > "$D/$4"; echo "lu : $1 $2 @ $3 -> $4 ($(stat -c %s "$D/$4") octets)"; }
x() { echo "--- $1, l. $2 à $3"; sed -n "$2,$3p" "$1" | nl -ba -v "$2" -w4 -s ' | ' | cut -c1-700; }
echo "# lecture-2.sh (déploiement), début $(date -u +%FT%TZ) ; dossier $D"
echo "## Raison de l'option (b) du 01/11/2026 et de D1 (fichiers du dépôt)"
x poc/bricks/08-trust-plane/README.md 647 647
x poc/bricks/08b-rke2/README.md 57 57
echo; echo "## G5 : témoins J2 (journaux de pods) et J3 (audit de l'API) lus dans Grafana (19b, L4, 02/11/2026, sous k3s)"
x poc/bricks/19b-journalisation/README.md 312 312
echo; echo "## Argo CD v3.6.2 : variantes d'installation"
for f in core-install.yaml namespace-install.yaml; do
  g argoproj/argo-cd "manifests/$f" v3.6.2 "argocd-$f"
  echo "### $f : $(yq -o=json . "$D/argocd-$f" | jq -r -s '[.[] | select(.kind=="Deployment" or .kind=="StatefulSet") | .metadata.name] | join(" ")')"
  grep -oE 'image: *[^ ]+' "$D/argocd-$f" | sort | uniq -c
  yq -o=json . "$D/argocd-$f" | jq -c -s '.[] | select(.kind=="ClusterRole" or .kind=="Role") | {kind, name: .metadata.name, rules: [.rules[] | select(((.resources // []) | index("*")) or ((.resources // []) | index("secrets"))) | {apiGroups, resources, verbs}]} | select(.rules | length > 0)'
  yq -o=json . "$D/argocd-$f" | jq -c -s '.[] | select(.kind=="ClusterRoleBinding" or .kind=="RoleBinding") | {kind, name: .metadata.name, role: .roleRef.name, sa: [.subjects[] | .name]}'
done
echo; echo "## Flux : bornage des droits (kustomize-controller v1.10.1, helm-controller v1.7.1)"
g fluxcd/kustomize-controller docs/spec/v1/kustomizations.md v1.10.1 kc.md
grep -n -i 'serviceAccountName\|impersonat\|default-service-account\|no-cross-namespace' "$D/kc.md" | cut -c1-200 | head -12
g fluxcd/helm-controller docs/spec/v2/helmreleases.md v1.7.1 hc.md
grep -n -i 'serviceAccountName\|impersonat\|default-service-account' "$D/hc.md" | cut -c1-200 | head -8
echo; echo "## Flux : OpenPGP (gitrepositories.md, source-controller v1.10.1)"
g fluxcd/source-controller docs/spec/v1/gitrepositories.md v1.10.1 fg.md
grep -n -i 'openpgp\|\.spec.verify\|gpg' "$D/fg.md" | cut -c1-200 | head -10
echo; echo "## Flux v2.10.0 : signatures des sept images du manifeste (cosign tree au tag)"
curl -fsSL --max-time 60 -o "$D/flux-install.yaml" https://github.com/fluxcd/flux2/releases/download/v2.10.0/install.yaml
for i in $(grep -oE 'image: *[^ ]+' "$D/flux-install.yaml" | awk '{print $2}' | sort -u); do
  echo "### $i : $(cosign tree "$i" 2>&1 | grep -oE 'Signatures|Attestations|SBOMs' | sort -u | tr '\n' ' ' || true)"
done
echo; echo "## helmfile v1.8.4 : verify et kustomize"
g helmfile/helmfile docs/configuration.md v1.8.4 hfc.md
x "$D/hfc.md" 55 62
g helmfile/helmfile docs/advanced-features.md v1.8.4 hfa.md
x "$D/hfa.md" 188 212
echo; echo "## Adoption : statut CNCF dans les README aux tags"
g argoproj/argo-cd README.md v3.6.2 argo-readme.md
grep -n -i 'cncf\|graduat' "$D/argo-readme.md" | cut -c1-200 | head -4
g fluxcd/flux2 README.md v2.10.0 flux-readme.md
grep -n -i 'cncf\|graduat' "$D/flux-readme.md" | cut -c1-200 | head -4
g helmfile/helmfile README.md v1.8.4 hf-readme.md
grep -n -i 'cncf\|graduat\|sandbox' "$D/hf-readme.md" | cut -c1-200 | head -4 || echo "helmfile : aucune mention de la CNCF dans le README"
echo; echo "# fin $(date -u +%FT%TZ)"
