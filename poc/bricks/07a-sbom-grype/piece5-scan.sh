#!/usr/bin/env bash
# Brique 07b, pièce 5 (ajout du 23/11/2026, après la pose) : premier scan réel du scanner neuf, lancé à la main depuis le CronJob
# scan-sample-app (accord du propriétaire du 23/11 : « Scan lancé à la main »). Le Job signe et publie un scan dans le vrai Zot,
# comme un passage planifié. Seuls ScanEnRetard et ScanBientotRefuse lisent l'âge du dernier scan : un scan de plus le rajeunit.
# Étape unique (journal jamais réécrit) :
#   manuel : refuse de 09:00 à 10:00 et de 11:00 à 11:45 UTC et si un pod de scan est actif ; kubectl create job --from=cronjob ;
#            attend (30 min au plus) ; journal du Job ; lignes VEX|, REPLI|, SCAN|, ATTESTATION|, PUBLIE| ; préfixes = ceux du
#            job planifié du 23/11 plus VEX (contrôle de releve_24 ajusté) ; referrers de builds/scan/sample-app : un de plus, celui
#            de PUBLIE| ; son bundle vérifié par la clé du scanner ; bloc vex du prédicat ; lignes du pod dans Loki = kubectl logs ;
#            refus Kyverno inchangés. Le Job reste (historique du CronJob).
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/piece5-scan.sh manuel  (journal : resultats/piece5-scan-manuel.log)
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
racine_depot=$(cd "$here/../../.." && pwd)
O8=$HOME/.cache/supply-chain-poc/08
CA=$O8/pki/ca-poc.crt
ZOT=https://192.168.161.13:5000
IMG_D=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
PREDICAT=https://supply-chain.example/scan/v1
e=${1:-}
[ "$e" = manuel ] || { echo "usage : $0 manuel" >&2; exit 2; }
L=$here/resultats/piece5-scan-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
KO=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
attendu() { [ "$2" = "$3" ] && ok "$1 : $2" || ko "$1 : $2 (attendu : $3)"; }
g() {
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$CA" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$1"
}
refus_kyverno() { g "$(jq -nc --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:"sum(kyverno_admission_requests_total{request_allowed=\"false\"})",instant:true}]}')" \
  | jq -r '[.results.A.frames[]? | .data.values[1][0]? | select(. != null) | tostring] | if length == 0 then "aucune série" else join(",") end'; }
anon() { curl -fsS --cacert "$CA" "$@" < /dev/null; }
nr() { anon -H 'Accept: application/vnd.oci.image.index.v1+json' "$ZOT/v2/builds/scan/sample-app/referrers/$IMG_D" | jq '.manifests | length'; }
pref() { awk '{ if (tolower($0) ~ /jeton|token/) print "masquée"; else { split($0, a, "|"); print a[1] } }' | sort | paste -sd,; }
{
echo "# piece5-scan.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$racine_depot" rev-parse --short=12 HEAD)"
hm=$(date -u +%H%M)
if { [ "$hm" -ge 0900 ] && [ "$hm" -lt 1000 ]; } || { [ "$hm" -ge 1100 ] && [ "$hm" -lt 1145 ]; }; then ko "$hm UTC : fenêtre d'un passage de scan, rien lancé"; echo "bilan : $KO KO"; exit 1; fi
actifs=$(kubectl get pods -n scan --no-headers -o custom-columns=N:.metadata.name,P:.status.phase | awk '$2 == "Running" || $2 == "Pending" {print $1}')
[ -z "$actifs" ] || { ko "pod(s) actif(s) dans scan : $actifs"; echo "bilan : $KO KO"; exit 1; }
ok "hors des fenêtres de scan ($hm UTC), aucun pod actif dans scan"
attendu "scan-config : scanner.sh (pièce 5 posée)" "$(kubectl get cm -n scan scan-config -o json | jq -j '.data["scanner.sh"]' | sha256sum | cut -c1-16)" 7251df1567c1cfdd
k0=$(refus_kyverno); echo "  refus Kyverno avant : $k0"
r0=$(nr); echo "  referrers de builds/scan/sample-app avant : $r0"
j0=$(kubectl get jobs -n scan -o json | jq -r '.items[] | select(.metadata.ownerReferences[0].name == "scan-sample-app" and .status.startTime == "2026-11-23T09:30:00Z") | .metadata.name')
echo "  job planifié du 23/11 (référence des préfixes) : ${j0:-aucun}"
T=$(mktemp -d -p "$HOME/.cache/supply-chain-poc/07a" p5-scan.XXXXXX)
J=scan-sample-app-manuel-$(date -u +%H%M%S)
debut=$(date -u +%s)
kubectl create job -n scan --from=cronjob/scan-sample-app "$J" > /dev/null && ok "Job $J créé ($(date -u +%H:%M:%S) UTC)" || ko "Job $J refusé"
etat=""
for _ in $(seq 360); do
  etat=$(kubectl get job -n scan "$J" -o json 2> /dev/null | jq -r '"\(.status.succeeded // 0)/\(.status.failed // 0)/\(.status.active // 0)"')
  case $etat in 1/*|*/1/0) break ;; esac
  sleep 5
done
echo "  durée : $(( $(date -u +%s) - debut )) s"
attendu "Job (réussi/échoué/actif)" "$etat" 1/0/0
kubectl logs -n scan "job/$J" --all-containers > "$T/job.log" 2>&1
echo "### journal du Job (préfixes VEX, REPLI, SCAN, ATTESTATION, PUBLIE, BASE)"
grep -E '^(VEX|REPLI|SCAN|ATTESTATION|PUBLIE|BASE)\|' "$T/job.log" | sed 's/^/  /'
attendu "ligne VEX|" "$(grep -c '^VEX|0 énoncé(s) vérifié(s), 0 retenu(s), 0 rejeté(s)|sc-stockage.poc.test:5000/builds/vex/sample-app|' "$T/job.log")" 1
attendu "lignes REPLI|" "$(grep -c '^REPLI|' "$T/job.log")" 0
attendu "ligne SCAN| : aucune entrée écartée par un VEX" "$(grep -c '^SCAN|.* 0 écartée(s) par un VEX' "$T/job.log")" 1
attendu "ligne ATTESTATION|" "$(grep -c '^ATTESTATION|' "$T/job.log")" 1
attendu "ligne PUBLIE|" "$(grep -c '^PUBLIE|' "$T/job.log")" 1
if [ -n "$j0" ]; then
  attendu "préfixes triés = ceux du 23/11 à 09:30 plus VEX" "$(pref < "$T/job.log")" "$( { kubectl logs -n scan "job/$j0" --all-containers 2>&1 | pref | tr , '\n'; echo VEX; } | sort | paste -sd,)"
else ko "job planifié du 23/11 introuvable"; fi
echo "## Zot (anonyme)"
attendu "referrers de builds/scan/sample-app après = avant + 1" "$(nr)" "$((r0 + 1))"
d=$(sed -n 's/^PUBLIE|[^@]*@\(sha256:[0-9a-f]*\),.*/\1/p' "$T/job.log")
attendu "referrer de PUBLIE| listé" "$(anon -H 'Accept: application/vnd.oci.image.index.v1+json' "$ZOT/v2/builds/scan/sample-app/referrers/$IMG_D" | jq --arg d "$d" '[.manifests[] | select(.digest == $d)] | length')" 1
anon -H 'Accept: application/vnd.oci.image.manifest.v1+json' "$ZOT/v2/builds/scan/sample-app/manifests/$d" > "$T/m.json"
anon -L "$ZOT/v2/builds/scan/sample-app/blobs/$(jq -r '.layers[0].digest' "$T/m.json")" > "$T/b.json"
cosign verify-blob-attestation --bundle "$T/b.json" --new-bundle-format --key "$here/resultats/scanner-cle-publique.pem" --insecure-ignore-tlog \
  --type "$PREDICAT" --digest "${IMG_D#sha256:}" --digestAlg sha256 > "$T/v.out" 2>&1 \
  && ok "bundle publié vérifié par la clé du scanner, sujet $IMG_D" || ko "bundle publié non vérifié : $(tail -1 "$T/v.out")"
jq -r '.dsseEnvelope.payload' "$T/b.json" | base64 -d | jq '.predicate' > "$T/p.json"
echo "  prédicat publié : $(jq -c '{scannedAt, base: .scanner.db, vulnerabilites: (.vulnerabilities | length), kev: ([.vulnerabilities[] | select(.kev)] | length), vex}' "$T/p.json")"
attendu "bloc vex du prédicat publié" "$(jq -c .vex "$T/p.json")" '{"documents":[],"ecarteesSansExemption":0,"rejetes":0}'
echo "## lignes du pod dans Grafana (Loki), comptes seuls"
pod=$(kubectl get pods -n scan -l job-name="$J" -o jsonpath='{.items[0].metadata.name}')
nl=$(wc -l < "$T/job.log"); nk=aucune
for _ in $(seq 24); do
  nk=$(g "$(jq -nc --arg q "sum(count_over_time({espace=\"scan\", pod=\"$pod\"} [3h]))" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')" \
    | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end')
  [ "$nk" = "$nl" ] && break
  sleep 5
done
attendu "lignes du pod $pod dans Grafana (Loki) = kubectl logs" "$nk" "$nl"
attendu "refus Kyverno après = avant" "$(refus_kyverno)" "$k0"
find "$T" -delete
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$KO" = 0 ] && echo "bilan : tenue" || echo "bilan : $KO KO"
} > "$L" 2>&1
sed -i '/jeton\|token/I c\[ligne masquée : motif jeton|token]' "$L"
cat "$L"
grep -q '^bilan : tenue' "$L"
