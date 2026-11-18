#!/usr/bin/env bash
# Essai à sec de helmfile : lectures citées par le cadre, archivées avant toute installation (code et doc de helmfile v1.8.4,
# registre aqua à un SHA, appels réels de cilium.sh, greffons Helm de l'hôte). Lecture seule.
# Usage (racine du dépôt) : bash poc/benchmarks/deploiement/essai-helmfile/lecture.sh > poc/benchmarks/deploiement/resultats/<journal neuf> 2>&1
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C
D=$HOME/.cache/supply-chain-poc/dep-hf-lecture-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$D" ] || { echo "KO   $D existe" >&2; exit 1; }
mkdir -p "$D"
g() { env -u GITHUB_TOKEN gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/$2?ref=$3" > "$D/$4"; echo "lu : $1 $2 @ $3 -> $4 ($(stat -c %s "$D/$4") octets)"; }
x() { echo "--- $1, l. $2 à $3"; sed -n "$2,$3p" "$1" | nl -ba -v "$2" -w4 -s ' | ' | cut -c1-220; }
echo "# lecture.sh (essai helmfile), début $(date -u +%FT%TZ)"
g helmfile/helmfile pkg/app/init.go v1.8.4 init.go; x "$D/init.go" 20 57
g helmfile/helmfile pkg/app/app.go v1.8.4 app.go
echo "--- app.go : lignes qui citent helm-diff ou une préparation pour diff"; grep -n -i 'helm-diff\|WithPreparedCharts("diff"' "$D/app.go" | cut -c1-180
echo "--- app.go : fonction Template"; grep -n '^func (a \*App) Template' "$D/app.go"
g helmfile/helmfile docs/templating.md v1.8.4 templating.md; x "$D/templating.md" 86 86
g helmfile/helmfile docs/configuration.md v1.8.4 configuration.md; x "$D/configuration.md" 96 111; x "$D/configuration.md" 469 469
s=$(env -u GITHUB_TOKEN gh api repos/aquaproj/aqua-registry/commits/main --jq .sha)
g aquaproj/aqua-registry pkgs/helmfile/helmfile/registry.yaml "$s" aqua.yaml; echo "registre aqua au commit $s"; x "$D/aqua.yaml" 17 27
echo; echo "## installations réelles des scripts"
x poc/bricks/08-trust-plane/cilium.sh 116 120
x poc/bricks/08b-rke2/rke2.sh 166 169
echo "HELM_PLUGINS fixé dans cilium.sh, rke2.sh ou les scripts de la 08c : $(grep -l 'HELM_PLUGINS' poc/bricks/08-trust-plane/cilium.sh poc/bricks/08b-rke2/rke2.sh poc/bricks/08c-durcissement/*.sh 2>/dev/null | tr '\n' ' ' || true)[fin]"
echo; echo "## greffons Helm de l'hôte (HELM_PLUGINS par défaut)"
helm plugin list 2>&1 | sed 's/^/  /'
echo "dossier des greffons : $(helm env HELM_PLUGINS)"
echo; echo "# fin $(date -u +%FT%TZ)"
