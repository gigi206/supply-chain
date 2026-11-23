#!/usr/bin/env bash
# Brique 07b, pièce 5 (ajout du 23/11/2026) : pod d'essai du scanner neuf dans l'espace scan, sans publication. Conteneurs source et
# analyser du gabarit du CronJob scan-sample-app (mêmes variables, montages, compte et nœud), analyser sur l'image outils-scan
# b799feda (pièce 3) et le scanner.sh de HEAD (celui du patch 07b-t3, reporté dans le dépôt le 23/11), dans une ConfigMap au nom distinct (scan-config-essai : les trois autres clés
# copiées de scan-config). Ni jetons, ni attester, ni publier, ni revocation : rien n'est signé ni écrit dans Zot. Le conteneur
# principal (même image) affiche cosign version et le prédicat produit. Jamais kubectl create job --from=cronjob.
# Étapes (une par journal, jamais réécrit) :
#   avant : lecture seule. Prédicat de référence : scan retenu le plus récent de builds/sample-app (referrers lus en anonyme dans Zot,
#           bundle vérifié par la clé du scanner), gardé hors du dépôt pour essai ; refus Kyverno (Prometheus, à travers Grafana) ;
#           aucun objet d'essai présent.
#   essai : refuse de 09:00 à 10:00 et de 11:00 à 11:45 UTC et si un pod de scan est actif ; crée la ConfigMap et le pod, attend
#           (25 min au plus), relit les journaux, compare le prédicat à la référence (scannedAt et bloc vex mis à part), compte les
#           lignes du pod dans Loki à travers Grafana, efface le pod et la ConfigMap ; refus Kyverno égaux avant et après.
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/piece5-essai.sh <avant|essai>  (journal : resultats/piece5-essai-<étape>.log)
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
racine_depot=$(cd "$here/../../.." && pwd)
O8=$HOME/.cache/supply-chain-poc/08
CA=$O8/pki/ca-poc.crt
ZOT=https://192.168.161.13:5000
NEUF=sha256:b799feda12153cc35c76d951b8b3d51d963e82c17cc80de3563f221657e84649
IMG_D=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # builds/sample-app, IMAGE de la 07a
PREDICAT=https://supply-chain.example/scan/v1
REF=$HOME/.cache/supply-chain-poc/07a/p5-essai-reference.json   # gardée entre avant et essai, effacée à la fin d'essai
POD=p5-essai CM=scan-config-essai
e=${1:-}
case $e in avant|essai) ;; *) echo "usage : $0 <avant|essai>" >&2; exit 2 ;; esac
L=$here/resultats/piece5-essai-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
KO=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
attendu() { [ "$2" = "$3" ] && ok "$1 : $2" || ko "$1 : $2 (attendu : $3)"; }
g() { # corps JSON de /api/ds/query, compte auditeur
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$CA" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$1"
}
refus_kyverno() { g "$(jq -nc --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:"sum(kyverno_admission_requests_total{request_allowed=\"false\"})",instant:true}]}')" \
  | jq -r '[.results.A.frames[]? | .data.values[1][0]? | select(. != null) | tostring] | if length == 0 then "aucune série" else join(",") end'; }
anon() { curl -fsS --cacert "$CA" "$@" < /dev/null; }
exec > "$L" 2>&1
echo "# piece5-essai.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$racine_depot" rev-parse --short=12 HEAD)"
attendu "objets d'essai absents (pod, ConfigMap)" "$(kubectl get pod,cm -n scan "$POD" "$CM" --ignore-not-found -o name 2>/dev/null | wc -l)" 0

case $e in
avant)
  [ ! -e "$REF" ] || { ko "référence déjà présente : $REF"; echo "bilan : $KO KO"; exit 1; }
  echo "## scan retenu de builds/sample-app (referrers en anonyme, bundle vérifié)"
  T=$(mktemp -d -p "$HOME/.cache/supply-chain-poc/07a" p5-avant.XXXXXX)
  anon -H 'Accept: application/vnd.oci.image.index.v1+json' "$ZOT/v2/builds/scan/sample-app/referrers/$IMG_D" > "$T/ref.json"
  n=$(jq '.manifests | length' "$T/ref.json"); echo "  referrers : $n"
  best="" bt=""
  for m in $(jq -r '.manifests[].digest' "$T/ref.json"); do
    anon -H 'Accept: application/vnd.oci.image.manifest.v1+json' "$ZOT/v2/builds/scan/sample-app/manifests/$m" > "$T/m.json" || continue
    c=$(jq -r '.layers[0].digest' "$T/m.json")
    anon -L "$ZOT/v2/builds/scan/sample-app/blobs/$c" > "$T/b-${m#sha256:}.json" || continue
    t=$(jq -r '.dsseEnvelope.payload' "$T/b-${m#sha256:}.json" | base64 -d | jq -r '.predicate.scannedAt' 2>/dev/null)
    s=$(date -ud "$t" +%s 2>/dev/null) || continue
    if [ -z "$bt" ] || [ "$s" -gt "$bt" ]; then bt=$s best=$m; fi
  done
  echo "  retenu : $best, scannedAt $(date -ud "@$bt" +%Y-%m-%dT%H:%M:%SZ)"
  B=$T/b-${best#sha256:}.json
  cosign verify-blob-attestation --bundle "$B" --new-bundle-format --key "$here/resultats/scanner-cle-publique.pem" --insecure-ignore-tlog \
    --type "$PREDICAT" --digest "${IMG_D#sha256:}" --digestAlg sha256 > "$T/v.out" 2>&1 \
    && ok "bundle retenu vérifié par la clé du scanner, sujet $IMG_D" || { ko "bundle retenu non vérifié : $(tail -1 "$T/v.out")"; }
  jq -r '.dsseEnvelope.payload' "$B" | base64 -d | jq '.predicate' > "$REF"
  chmod 600 "$REF"
  attendu "référence : jour du scan retenu" "$(date -ud "@$bt" +%Y-%m-%d)" 2026-11-23
  echo "  référence : $(jq -c '{scannedAt, base: .scanner.db, vulnerabilites: (.vulnerabilities | length), kev: ([.vulnerabilities[] | select(.kev)] | length), vex: (has("vex"))}' "$REF")"
  echo "  empreinte du prédicat de référence : $(sha256sum < "$REF" | cut -c1-16)"
  find "$T" -delete
  echo "## refus Kyverno"
  echo "  sum(kyverno_admission_requests_total{request_allowed=\"false\"}) : $(refus_kyverno)"
  ;;
essai)
  [ -s "$REF" ] || { ko "référence absente : lancer avant"; echo "bilan : $KO KO"; exit 1; }
  hm=$(date -u +%H%M)
  if { [ "$hm" -ge 0900 ] && [ "$hm" -lt 1000 ]; } || { [ "$hm" -ge 1100 ] && [ "$hm" -lt 1145 ]; }; then ko "$hm UTC : fenêtre d'un passage de scan, rien lancé"; echo "bilan : $KO KO"; exit 1; fi
  actifs=$(kubectl get pods -n scan --no-headers -o custom-columns=N:.metadata.name,P:.status.phase | awk '$2 == "Running" || $2 == "Pending" {print $1}')
  [ -z "$actifs" ] || { ko "pod(s) actif(s) dans scan : $actifs"; echo "bilan : $KO KO"; exit 1; }
  ok "hors des fenêtres de scan ($hm UTC), aucun pod actif dans scan"
  k0=$(refus_kyverno); echo "  refus Kyverno avant : $k0"
  nr() { anon -H 'Accept: application/vnd.oci.image.index.v1+json' "$ZOT/v2/builds/scan/sample-app/referrers/$IMG_D" | jq '.manifests | length'; }
  r0=$(nr); echo "  referrers de builds/sample-app avant : $r0"
  T=$(mktemp -d -p "$HOME/.cache/supply-chain-poc/07a" p5-essai.XXXXXX)
  # scanner.sh du patch, reporté dans le dépôt le 23/11 (pièce 5 préparée) : lu dans HEAD
  mkdir -p "$T/poc/bricks/07a-sbom-grype/politique"
  git -C "$racine_depot" show HEAD:poc/bricks/07a-sbom-grype/politique/scanner.sh > "$T/poc/bricks/07a-sbom-grype/politique/scanner.sh"
  attendu "scanner.sh de HEAD = rendu de la pièce 5 à sec" "$(sha256sum < "$T/poc/bricks/07a-sbom-grype/politique/scanner.sh" | cut -c1-16)" 7251df1567c1cfdd
  kubectl get cm -n scan scan-config -o json > "$T/cm.json"
  for k in ca-poc.crt scanner.pub vex.pub; do jq -j --arg k "$k" '.data[$k]' "$T/cm.json" > "$T/$k"; done
  kubectl create configmap "$CM" -n scan --from-file=ca-poc.crt="$T/ca-poc.crt" --from-file=scanner.pub="$T/scanner.pub" \
    --from-file=vex.pub="$T/vex.pub" --from-file=scanner.sh="$T/poc/bricks/07a-sbom-grype/politique/scanner.sh" > /dev/null && ok "ConfigMap $CM créée" || ko "ConfigMap $CM non créée"
  kubectl get cronjob -n scan scan-sample-app -o json | jq --arg pod "$POD" --arg cm "$CM" --arg img "sc-stockage.poc.test:5000/plateforme/outils-scan@$NEUF" '
    .spec.jobTemplate.spec.template.spec as $s
    | {apiVersion: "v1", kind: "Pod", metadata: {name: $pod, namespace: "scan", labels: {app: "scan-essai"}},
       spec: ($s | del(.initContainers, .containers) | .automountServiceAccountToken = false
         | .volumes = [.volumes[] | select(.name == "travail" or .name == "config") | if .name == "config" then .configMap.name = $cm else . end]
         | .initContainers = [$s.initContainers[] | select(.name == "source" or .name == "analyser") | if .name == "analyser" then .image = $img else . end]
         | .containers = [{name: "lire", image: $img, command: ["sh", "-c", "cosign version 2>&1 | grep -E \"^(GitVersion|GitCommit)\"; echo \"PREDICAT_SHA256|$(sha256sum < /travail/scan.json | cut -c1-64)\"; cat /travail/scan.json"],
             resources: {requests: {cpu: "10m", memory: "32Mi"}, limits: {cpu: "200m", memory: "128Mi"}},
             securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}},
             volumeMounts: [{name: "travail", mountPath: "/travail"}]}])}' > "$T/pod.json"
  echo "  pod : $(jq -c '{init: [.spec.initContainers[] | {name, image: (.image | sub(".*@sha256:"; "") | .[0:8]), cmd: (.command | join(" "))}], main: [.spec.containers[].name], volumes: [.spec.volumes[] | .name + ":" + (.configMap.name // "emptyDir")], sa: .spec.serviceAccountName, jeton: .spec.automountServiceAccountToken}' "$T/pod.json")"
  attendu "pod : aucun conteneur qui signe ou publie" "$(jq -r '[.spec.initContainers[], .spec.containers[] | .command | join(" ") | select(test("jetons|attester|publier|revocation"))] | length' "$T/pod.json")" 0
  debut=$(date -u +%s)
  kubectl apply -f "$T/pod.json" > /dev/null && ok "pod $POD créé ($(date -u +%H:%M:%S) UTC)" || ko "pod $POD refusé"
  phase=""
  for _ in $(seq 300); do
    phase=$(kubectl get pod -n scan "$POD" -o jsonpath='{.status.phase}' 2> /dev/null)
    case $phase in Succeeded|Failed) break ;; esac
    sleep 5
  done
  echo "  phase : ${phase:-?}, $(( $(date -u +%s) - debut )) s"
  attendu "phase du pod" "$phase" Succeeded
  for c in source analyser lire; do kubectl logs -n scan "$POD" -c "$c" > "$T/$c.log" 2>&1; done
  echo "### source"; sed 's/^/  /' "$T/source.log"
  echo "### analyser"; sed 's/^/  /' "$T/analyser.log"
  echo "### lire (sans le prédicat)"; grep -v '^[[:space:]{}\[\]"]' "$T/lire.log" | sed 's/^/  /'
  attendu "ligne VEX| d'analyser" "$(grep -c '^VEX|0 énoncé(s) vérifié(s), 0 retenu(s), 0 rejeté(s)|sc-stockage.poc.test:5000/builds/vex/sample-app|' "$T/analyser.log")" 1
  attendu "lignes REPLI| d'analyser" "$(grep -c '^REPLI|' "$T/analyser.log")" 0
  attendu "ligne SCAN| : aucune entrée écartée par un VEX" "$(grep -c '^SCAN|.* 0 écartée(s) par un VEX' "$T/analyser.log")" 1
  echo "  cosign de l'image neuve : $(grep -E '^Git(Version|Commit)' "$T/lire.log" | paste -sd' ')"
  sed -n '/^{/,$p' "$T/lire.log" > "$T/scan.json"
  attendu "prédicat lu = empreinte affichée par le pod" "$(sha256sum < "$T/scan.json" | cut -c1-64)" "$(sed -n 's/^PREDICAT_SHA256|//p' "$T/lire.log")"
  echo "  prédicat de l'essai : $(jq -c '{scannedAt, base: .scanner.db, vulnerabilites: (.vulnerabilities | length), kev: ([.vulnerabilities[] | select(.kev)] | length), vex}' "$T/scan.json")"
  attendu "bloc vex de l'essai" "$(jq -c .vex "$T/scan.json")" '{"documents":[],"ecarteesSansExemption":0,"rejetes":0}'
  attendu "prédicat de l'essai = référence, hors scannedAt et bloc vex" "$(jq -S -c 'del(.scannedAt, .vex)' "$T/scan.json" | sha256sum | cut -c1-16)" "$(jq -S -c 'del(.scannedAt, .vex)' "$REF" | sha256sum | cut -c1-16)"
  jq -S 'del(.scannedAt, .vex)' "$T/scan.json" > "$T/a.json"; jq -S 'del(.scannedAt, .vex)' "$REF" > "$T/b.json"
  cmp -s "$T/a.json" "$T/b.json" || diff "$T/b.json" "$T/a.json" | head -30 | sed 's/^/  diff : /'
  echo "## lignes du pod dans Grafana (Loki), comptes seuls"
  nl=$(cat "$T/source.log" "$T/analyser.log" "$T/lire.log" | wc -l)
  nk=aucune
  for _ in $(seq 24); do
    nk=$(g "$(jq -nc --arg q "sum(count_over_time({espace=\"scan\", pod=\"$POD\"} [3h]))" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')" \
      | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end')
    [ "$nk" = "$nl" ] && break
    sleep 5
  done
  attendu "lignes du pod $POD dans Grafana (Loki) = kubectl logs" "$nk" "$nl"
  echo "## effacement"
  kubectl delete pod -n scan "$POD" --wait=true > /dev/null && ok "pod $POD effacé" || ko "pod $POD non effacé"
  kubectl delete cm -n scan "$CM" > /dev/null && ok "ConfigMap $CM effacée" || ko "ConfigMap $CM non effacée"
  attendu "refus Kyverno après = avant" "$(refus_kyverno)" "$k0"
  attendu "Zot : referrers de builds/sample-app après = avant (rien publié)" "$(nr)" "$r0"
  find "$T" -delete; find "$HOME/.cache/supply-chain-poc/07a/p5-essai-reference.json" -delete
  ;;
esac
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$KO" = 0 ] && echo "bilan : tenue" || echo "bilan : $KO KO"
