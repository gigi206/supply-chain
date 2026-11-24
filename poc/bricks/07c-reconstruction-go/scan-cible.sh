#!/usr/bin/env bash
# Brique 07c, étape 4 (e) : cible du CronJob scan/scan-sample-app portée de 3a7ca1b1 à l'image reconstruite en Go 1.26.11
# (accord du propriétaire du 24/11/2026, « J'autorise l'étape 4 »), puis un passage lancé à la main depuis le CronJob
# (kubectl create job --from), sans attendre le calendrier. Seules les valeurs IMAGE des conteneurs d'init changent.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
J=$1
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
A=3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
B=f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7
W=$HOME/.cache/supply-chain-poc/07c/scan-cible
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
mkdir -p "$W"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
images() { kubectl get cronjob -n scan scan-sample-app -o json | jq -r '[.spec.jobTemplate.spec.template.spec.initContainers[].env[]? | select(.name == "IMAGE") | .value | sub(".*@sha256:"; "") | .[0:8]] | join(",")'; }
{
echo "# cible du scan de sample-app, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
attendu "cible avant" "$(images)" "3a7ca1b1,3a7ca1b1,3a7ca1b1"
kubectl get cronjob -n scan scan-sample-app -o json > "$W/avant.json"
jq --arg a "$A" --arg b "$B" '.spec.jobTemplate.spec.template.spec.initContainers |= map(.env |= (if . == null then . else map(if .name == "IMAGE" then .value |= sub($a; $b) else . end) end))' "$W/avant.json" > "$W/apres.json"
echo "différences (hors IMAGE) : $(diff <(jq -S 'del(.spec.jobTemplate.spec.template.spec.initContainers[].env)' "$W/avant.json") <(jq -S 'del(.spec.jobTemplate.spec.template.spec.initContainers[].env)' "$W/apres.json") | grep -c '^[<>]')"
kubectl replace -f "$W/apres.json" > /dev/null; echo "replace : code $?"
attendu "cible après" "$(images)" "f5e6bcb0,f5e6bcb0,f5e6bcb0"
j=scan-sample-app-07c-$(date -u +%H%M%S)
kubectl create job -n scan --from=cronjob/scan-sample-app "$j" > /dev/null; echo "job $j : code $?"
kubectl wait -n scan "job/$j" --for=condition=complete --timeout=900s > /dev/null; echo "attente : code $?"
echo "Job : $(kubectl get job -n scan "$j" -o json | jq -r '"début \(.status.startTime), fin \(.status.completionTime // "-"), réussi \(.status.succeeded // 0)"')"
pod=$(kubectl get pods -n scan -l "job-name=$j" -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n scan "$pod" --all-containers 2>/dev/null | grep -E '^(VEX|REPLI|SCAN|PUBLIE)\|' | cut -c1-260 | tee "$W/lignes" | sed 's/^/  /'
attendu "Job réussi" "$(kubectl get job -n scan "$j" -o jsonpath='{.status.succeeded}')" 1
attendu "SCAN| : image reconstruite, 5 vulnérabilités, 0 KEV" "$(grep -c "SCAN|.*sample-app@sha256:$B.*, 5 vulnérabilités, 0 KEV" "$W/lignes")" 1
attendu "PUBLIE| : scan publié" "$(grep -c 'PUBLIE|' "$W/lignes")" 1
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
find "$W" -delete
sed -i "s#$HOME#~#g" "$J"
cat "$J"
