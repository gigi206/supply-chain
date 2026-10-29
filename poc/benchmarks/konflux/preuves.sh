#!/usr/bin/env bash
# Banc A1 : archive les preuves des constats qui ne sortent pas des autres scripts
# (resultats/preuves.log ; chemins personnels, IP du réseau local et nom d'hôte masqués).
# 1. Écarts d'intégration de Konflux v0.2.2 : ports de PaC, NetworkPolicy, options de
#    l'objet PaC de l'opérateur, livraisons de webhooks échouées côté Forgejo.
# 2. Sorties vers des tiers : tpa-scan (URL par défaut, tâche exigée par la politique,
#    blocage par la NetworkPolicy), deprecated-image-check.
# 3. rpm et deb : multi-platform-controller absent de l'opérateur, prérequis du pipeline
#    rpmbuild de Konflux.
# 4. Santé (A-6) : commits humains sur 90 jours, auteurs, domaines et employeurs déclarés.
#
# Usage (racine du dépôt, lecture seule) : mise run konflux:preuves
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
export KUBECONFIG=$HOME/.kube/supply-chain-poc-konflux.yaml
K=${KONFLUX_DIR:-$HOME/.cache/supply-chain-poc/konflux}
F=${FORGEJO_DIR:-$HOME/.cache/supply-chain-poc/forgejo}
NS=default-tenant
TRUSTED=8eaa4f44c2bf67e6e2b20c5777b0d73e978c632b   # data de la politique « default » (CR EnterpriseContractPolicy)
TPA_BUNDLE=quay.io/konflux-ci/tekton-catalog/task-tpa-scan:0.1@sha256:6a204cecc1a1091bf928b3db5a4082735c2111f90befdb5b043c498833c02bcf
DIC_BUNDLE=quay.io/konflux-ci/tekton-catalog/task-deprecated-image-check:0.5@sha256:0ccc688a77e9b7b0b8973c132a1e840844137e77f887be4a0bec8893b0776872
SINCE=$(date -u -d '90 days ago' +%Y-%m-%dT00:00:00Z)
W=$(mktemp -d)
trap 'rm -rf -- "$W"' EXIT
lan=$(ip -4 -br addr | awk '$2 == "UP" {print $3}' | cut -d/ -f1 | grep -vE '^(127|172\.(1[6-9]|2[0-9]|3[01]))\.' | paste -sd'|')
masque() { sed -u -E "s#$HOME#~#g; s#\b(${lan:-^$})\b#<ip-lan>#g; s#\b$(hostname)\b#<hôte>#g"; }
exec > >(masque | tee "$R/preuves.log") 2>&1
echo "# preuves.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "## 1. Écarts d'intégration"
echo "Service NodePort livré par Konflux (dependencies/tekton-config/pac-nodeport-service.yml) : targetPort $(grep -m1 'targetPort' "$K/konflux-ci/dependencies/tekton-config/pac-nodeport-service.yml" | awk '{print $2}')"
echo "Service NodePort en place (corrigé) : $(kubectl get svc -n tekton-pipelines pipelines-as-code-controller-nodeport -o jsonpath='{.spec.ports}')"
echo "Service PaC (opérateur Tekton) : $(kubectl get svc -n tekton-pipelines pipelines-as-code-controller -o jsonpath='{.spec.ports}')"
echo "Conteneur pac-controller : $(kubectl get deploy -n tekton-pipelines pipelines-as-code-controller -o jsonpath='{.spec.template.spec.containers[0].ports}')"
echo "NetworkPolicy pac-controller, entrée : $(kubectl get networkpolicy -n tekton-pipelines pac-controller -o jsonpath='{.spec.ingress}')"
echo "TektonConfig, options PaC : $(kubectl get tektonconfig config -o json | jq -c '.spec.platforms.kubernetes.pipelinesAsCode.options.deployments | keys')"
echo "OpenShiftPipelinesAsCode, options (posées à la main, l'opérateur ne les propage pas) : $(kubectl get openshiftpipelinesascode pipelines-as-code -o json | jq -c '.spec.options.deployments | keys')"
echo "Volumes trusted-ca : $(kubectl get deploy -n tekton-pipelines pipelines-as-code-controller pipelines-as-code-watcher -o json | jq -c '[.items[] | {(.metadata.name): [.spec.template.spec.volumes[].name]}] | add')"
echo "Forgejo, livraisons de webhooks échouées (gitea.log) :"
grep -E 'Unable to deliver webhook' "$F/log/gitea.log" | sed -E 's/^([0-9/]+ [0-9:]+).*task\[([0-9]+)\] in ([^ ]+) due to error in http client: (.{0,90}).*/  \1 tâche \2 → \3 : \4/' | head -6
echo "Journaux des pods PaC d'avant les redéploiements : perdus (pods remplacés)."

echo "## 2. Sorties vers des tiers"
mkdir -p "$W/tpa" "$W/dic"
crane export "$TPA_BUNDLE" - | tar -x -C "$W/tpa"
crane export "$DIC_BUNDLE" - | tar -x -C "$W/dic"
echo "tpa-scan ($TPA_BUNDLE) : tpa-url par défaut = $(jq -r '.spec.params[] | select(.name == "tpa-url") | .default' "$W"/tpa/*)"
echo "  envoi : $(jq -r '.spec.steps[] | select(.name == "get-vulnerabilities") | .script' "$W"/tpa/* | grep -m1 -oE 'curl [^|]*TPA_URL[^|]*')"
echo "deprecated-image-check ($DIC_BUNDLE) : $(jq -r '.spec.steps[].script // ""' "$W"/dic/* | grep -oE 'https?://[^ "$]+' | sort -u | paste -sd' ')"
echo "Politique « default », data $TRUSTED, required_tasks.yml (pipeline docker) :"
gh api "repos/konflux-ci/konflux-operator-trusted-sources/contents/data/required_tasks.yml?ref=$TRUSTED" --jq '.content' | base64 -d \
  | grep -E '^\s+- (tpa-scan|\[clamav|deprecated-image-check)' | sed 's/^/  /'
echo "NetworkPolicy du tenant : $(kubectl get networkpolicy -n "$NS" tpa-scan-sans-sortie -o jsonpath='{.spec}')"
for p in $(kubectl get pods -n "$NS" -l tekton.dev/pipelineTask=tpa-scan -o name); do
  # « Running TPA scan » précède l'envoi du SBOM ; sous la NetworkPolicy, la tâche échoue avant (registre injoignable).
  t=$(kubectl logs -n "$NS" "$p" -c step-get-vulnerabilities 2>&1 | grep -oE 'Running TPA scan on [a-z0-9]+ image manifest|Task tpa-scan failed: [^\\]{0,60}' | head -1 || true)
  echo "  $p ($(kubectl get -n "$NS" "$p" -o jsonpath='{.metadata.creationTimestamp}')) : ${t:-pas de trace}"
done

echo "## 3. rpm et deb"
echo "install.yaml de Konflux v0.2.2 : $(grep -ciE 'multi-?platform' "$K/assets/install.yaml" || true) occurrence de multi-platform-controller"
r=$(gh api repos/konflux-ci/rpmbuild-pipeline/commits/main --jq .sha)
echo "konflux-ci/rpmbuild-pipeline @ $r, docs/architecture.md :"
gh api "repos/konflux-ci/rpmbuild-pipeline/contents/docs/architecture.md?ref=$r" --jq '.content' | base64 -d | grep -E 'allocate a virtual machine|native `x86_64`' | sed 's/^/  /'
echo "Dépôts konflux-ci contenant « deb », « debian » ou « sbuild » : $(gh api 'search/repositories?q=org:konflux-ci+deb+OR+debian+OR+sbuild' --jq '.total_count')"

echo "## 4. Santé (A-6) : commits humains depuis $SINCE"
for repo in konflux-ci/konflux-ci konflux-ci/build-service konflux-ci/integration-service konflux-ci/release-service; do
  gh api --paginate "repos/$repo/commits?since=$SINCE&per_page=100" \
    --jq '.[] | select((.commit.author.name + " " + (.author.login // "")) | test("bot|renovate|dependabot"; "i") | not) | [.commit.author.email, (.author.login // "-")] | @tsv' > "$W/c.tsv"
  echo "$repo : $(wc -l < "$W/c.tsv") commits, $(cut -f2 "$W/c.tsv" | sort -u | wc -l) auteurs ; domaines : $(cut -f1 "$W/c.tsv" | sed 's/.*@//' | sort | uniq -c | sort -rn | head -4 | awk '{printf "%s %s ; ", $2, $1}')"
  cat "$W/c.tsv" >> "$W/tous.tsv"
done
echo "Employeur déclaré (profil GitHub) des auteurs sans adresse redhat.com :"
awk -F'\t' '$1 !~ /redhat\.com$/ && $2 != "-" {print $2}' "$W/tous.tsv" | sort | uniq -c | sort -rn | while read -r n u; do
  echo "  $u ($n) : $(gh api "users/$u" --jq '.company // "non renseigné"')"
done
