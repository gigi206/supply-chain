#!/usr/bin/env bash
# Brique 07c, étape 6 (copie de 07a-sbom-grype/resultats/deb-apres-scan.sh) : effet du VEX chi signé (builds/vex/sample-app@b139ef42…,
# 5 énoncés) sur un passage du CronJob scan/scan-sample-app (cible f5e6bcb0) lancé à la main (kubectl create job --from), sans
# attendre 09:30 UTC ; puis Grafana (Loki) et le tableau
# de vex-gabarit.sh sur le scan neuf. Rien d'autre n'est modifié.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
J=$1; R=poc/bricks/07a-sbom-grype
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
O8=$HOME/.cache/supply-chain-poc/08
export CA=$O8/pki/ca-poc.crt CLE_SCANNER=$R/resultats/scanner-cle-publique.pem
DEB=192.168.161.13:5000/builds/sample-app@sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
g() { printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
  | curl -sS -K - --cacert "$CA" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$1"; }
{
echo "# effet du VEX chi sur le scan de sample-app f5e6bcb0, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
j=scan-sample-app-07c-vex-$(date -u +%H%M%S)
kubectl create job -n scan --from=cronjob/scan-sample-app "$j" > /dev/null; echo "job $j : code $?"
kubectl wait -n scan "job/$j" --for=condition=complete --timeout=900s > /dev/null; echo "attente : code $?"
echo "Job : $(kubectl get job -n scan "$j" -o json | jq -r '"début \(.status.startTime), fin \(.status.completionTime // "-"), réussi \(.status.succeeded // 0)"')"
pod=$(kubectl get pods -n scan -l "job-name=$j" -o jsonpath='{.items[0].metadata.name}')
L=$(kubectl logs -n scan "$pod" --all-containers 2>/dev/null | grep -E '^(VEX|REPLI|SCAN|PUBLIE)\|' | cut -c1-260)
echo "$L" | sed 's/^/  /'
attendu "Job réussi" "$(kubectl get job -n scan "$j" -o jsonpath='{.status.succeeded}')" 1
attendu "VEX| : 1 document vérifié, retenu" "$(grep -c '^VEX|1 énoncé(s) vérifié(s), 1 retenu(s), 0 rejeté(s)' <<< "$L")" 1
attendu "SCAN| : 5 vulnérabilités, 0 KEV, 5 écartées par un VEX" "$(grep -c 'SCAN|.*sample-app@sha256:f5e6bcb0.*, 5 vulnérabilités, 0 KEV, 5 écartée(s) par un VEX' <<< "$L")" 1
attendu "PUBLIE| : scan publié" "$(grep -c '^PUBLIE|' <<< "$L")" 1
sleep 30   # acheminement vers Loki
n=$(g "$(jq -nc --arg q "sum(count_over_time({espace=\"scan\", pod=\"$pod\"} |= \"5 écartée(s) par un VEX\" [1h]))" --arg t "$(date -u +%s)000" \
  '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')" \
  | jq -r '[.results.A.frames[]? | .data.values[1][0]? | select(. != null)] | if length == 0 then "aucune" else (.[0] | tostring) end')
attendu "ligne SCAN| du pod visible dans Grafana" "$n" 1
o=$(timeout 180 bash "$R/vex-gabarit.sh" "$DEB" - 2>&1)
grep -o 'comptes : .*' <<< "$o" | sed 's/^/  /'
attendu "tableau : écartées par un VEX" "$(grep -o 'écartées par un VEX [0-9]*' <<< "$o")" "écartées par un VEX 5"
for id in GHSA-3fxj-6jh8-hvhx GHSA-j6qf-3m9c-vwj3 GHSA-mqqf-5wvp-8fh8 GO-2026-5775 GO-2026-5777; do echo "  $id : $(grep "^| [0-9]* | $id " <<< "$o" | awk -F'|' '{gsub(/^ +| +$/, "", $10); print $10}')"; done
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
cat "$J"
