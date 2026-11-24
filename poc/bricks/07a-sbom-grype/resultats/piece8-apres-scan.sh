#!/usr/bin/env bash
# Brique 07b, pièce 8 (2026-11-24) : effet du premier VEX publié (builds/vex/sample-app@sha256:fbf5d0bf…, 5 énoncés not_affected)
# sur le scan quotidien de sample-app du CronJob scan/scan-sample-app (30 9 * * *, Etc/UTC). LECTURE SEULE : rien n'est lancé,
# le Job est celui du calendrier.
#   1. Job de 09:30 : réussi ; lignes VEX|, SCAN| et PUBLIE| de son journal ;
#   2. Grafana (Loki, compte auditeur) : la ligne SCAN| de ce pod, avec « 5 écartée(s) par un VEX » ;
#   3. vex-gabarit.sh sur le nouveau scan signé : colonne « VEX appliqué » remplie pour les 5 entrées, vide pour GO-2026-6859.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
J=$1; R=poc/bricks/07a-sbom-grype
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
O8=$HOME/.cache/supply-chain-poc/08
export CA=$O8/pki/ca-poc.crt CLE_SCANNER=$R/resultats/scanner-cle-publique.pem
APP=192.168.161.13:5000/builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
g() { printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
  | curl -sS -K - --cacert "$CA" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$1"; }
{
echo "# effet du VEX sur le scan de sample-app, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
echo "## 1. Job du calendrier"
job=$(kubectl get jobs -n scan -o json | jq -r '[.items[] | select(.metadata.ownerReferences[]?.name == "scan-sample-app")
  | select(.metadata.creationTimestamp >= "2026-11-24T09:29:00Z")] | .[0].metadata.name // ""')
echo "Job : $job ; $(kubectl get job -n scan "$job" -o json | jq -r '"début \(.status.startTime), fin \(.status.completionTime // "-"), réussi \(.status.succeeded // 0)"')"
attendu "Job réussi" "$(kubectl get job -n scan "$job" -o jsonpath='{.status.succeeded}')" 1
pod=$(kubectl get pods -n scan -l "job-name=$job" -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n scan "$pod" --all-containers 2>/dev/null | grep -E '^(VEX|REPLI|SCAN|PUBLIE)\|' | cut -c1-240 | sed 's/^/  /' > "$HOME/.cache/supply-chain-poc/07a/piece8-apres-scan.lignes"
cat "$HOME/.cache/supply-chain-poc/07a/piece8-apres-scan.lignes"
L=$HOME/.cache/supply-chain-poc/07a/piece8-apres-scan.lignes
attendu "VEX| : 1 attestation vérifiée (le document), 1 retenue, 0 rejetée" "$(grep -c 'VEX|1 énoncé(s) vérifié(s), 1 retenu(s), 0 rejeté(s)' "$L")" 1
attendu "SCAN| : 6 vulnérabilités, 0 KEV, 5 écartées par un VEX" "$(grep -c 'SCAN|.*sample-app@sha256:3a7ca1b1.*, 6 vulnérabilités, 0 KEV, 5 écartée(s) par un VEX' "$L")" 1
attendu "PUBLIE| : scan publié" "$(grep -c 'PUBLIE|' "$L")" 1
find "$L" -delete
echo "## 2. Grafana (Loki)"
n=$(g "$(jq -nc --arg q "sum(count_over_time({espace=\"scan\", pod=\"$pod\"} |= \"5 écartée(s) par un VEX\" [3h]))" --arg t "$(date -u +%s)000" \
  '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')" \
  | jq -r '[.results.A.frames[]? | .data.values[1][0]? | select(. != null)] | if length == 0 then "aucune" else (.[0] | tostring) end')
attendu "ligne SCAN| du pod avec « 5 écartée(s) par un VEX », visible dans Grafana" "$n" 1
echo "## 3. tableau du nouveau scan signé (vex-gabarit.sh)"
o=$(timeout 120 bash "$R/vex-gabarit.sh" "$APP" - 2>&1); echo "$o" | cut -c1-220
attendu "entrées marquées par un VEX" "$(grep '^| [0-9]' <<< "$o" | awk -F'|' '$10 !~ /^ *- *$/' | wc -l)" 5
attendu "GO-2026-6859 sans VEX" "$(grep '^| [0-9] | GO-2026-6859 ' <<< "$o" | awk -F'|' '{gsub(/ /, "", $10); print $10}')" -
attendu "comptes : écartées par un VEX" "$(grep -o 'écartées par un VEX [0-9]*' <<< "$o")" "écartées par un VEX 5"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
cat "$J"
