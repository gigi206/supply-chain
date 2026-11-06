#!/usr/bin/env bash
# Brique 08c : premier passage réel de scan-sample-app sous H1 à H5, par un job créé depuis le CronJob, prédictions N1 à N6 du README.
# Crée un job et son pod dans l'espace scan, publie un referrer de scan dans Zot ; ne change aucune règle. Ne prouve pas le déclenchement par le planificateur.
# Lance une seule fois : refuse si le job existe déjà. Noms et marqueurs seulement, aucune valeur de secret.
# Usage (racine du dépôt) : poc/bricks/08c-durcissement/essais-h5-scan.sh   (journal : resultats/durcissement-h5_scan.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
O8=$HOME/.cache/supply-chain-poc/08
JOB=scan-sample-app-h5-manuel
SUJET=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
CONTENEURS=(source analyser jetons attester publier revocation)
SSHO=(-n -i "$O8/ssh/id_ed25519" -o "UserKnownHostsFile=$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)

referrers() { curl -fsS --cacert "$O8/pki/ca-poc.crt" "https://192.168.161.13:5000/v2/builds/scan/sample-app/referrers/$SUJET" </dev/null | jq '.manifests | length'; }
libre() { ssh "${SSHO[@]}" poc@192.168.161.11 "df -m --output=avail / | tail -1" </dev/null | tr -d ' '; }

grafana() { # depuis-epoch-ms : lignes du job lues par l'auditeur à travers Grafana, sur le gabarit de grafana_lignes (07a)
  local q
  q=$(jq -nc --arg de "$1" --arg a "$(date -u +%s)000" \
    '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: "{espace=\"scan\", conteneur=~\"source|analyser|jetons|attester|publier|revocation\"}", queryType: "range", maxLines: 1000, direction: "forward"}], from: $de, to: $a}')
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -X POST -H 'Content-Type: application/json' "https://192.168.161.13:3001/api/ds/query" -d "$q" \
    | jq -r '.results.A.frames[]? | .data.values as $v | range(0; ($v[2] // []) | length) | $v[2][.]'
}

{
  ko=0
  note() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2, attendu $3"; ko=1; fi; }
  date -u '+passage du %d/%m/%Y à %H:%M:%S UTC'
  if kubectl get job -n scan "$JOB" </dev/null >/dev/null 2>&1; then echo "KO   le job $JOB existe déjà, rien lancé"; exit 1; fi
  avant=$(referrers); mini=$(libre); de=$(date -u +%s)
  echo "départ : referrers $avant, place libre sur sc-confiance $mini Mo"

  echo "## N1, admission"
  kubectl create job "$JOB" -n scan --from=cronjob/scan-sample-app </dev/null || { echo "KO   création refusée, aucun job"; exit 1; }
  etat=/
  for _ in $(seq 360); do
    etat=$(kubectl get job -n scan "$JOB" -o jsonpath='{.status.succeeded}/{.status.failed}' </dev/null)
    l=$(libre); [ -n "$l" ] && [ "$l" -lt "$mini" ] && mini=$l
    case $etat in 1/*|*/1) break ;; esac
    sleep 5
  done
  fin=$(date -u +%s)
  date -u '+fin de l attente %H:%M:%S UTC'
  kubectl get events -n scan --sort-by=.lastTimestamp --no-headers -o custom-columns=T:.type,R:.reason,O:.involvedObject.name,M:.message </dev/null | cut -c1-170
  kubectl get pods -n scan -l job-name="$JOB" -o json </dev/null > "$here/resultats/.h5_scan.pod.json"
  jq -c '.items[0] | {noeud: .spec.nodeName, phase: .status.phase, debut: .status.startTime}' "$here/resultats/.h5_scan.pod.json"
  note "pods créés par le job" "$(jq '.items | length' "$here/resultats/.h5_scan.pod.json")" 1

  echo "## N2 et N3, conteneurs"
  jq -r '.items[0].status | (.initContainerStatuses + .containerStatuses)[] | "\(.name) code=\(.state.terminated.exitCode // "?") motif=\(.state.terminated.reason // "?") redémarrages=\(.restartCount) \(.state.terminated.startedAt // "") \(.state.terminated.finishedAt // "")"' "$here/resultats/.h5_scan.pod.json"
  note "conteneurs terminés avec le code 0 sur ${#CONTENEURS[@]}" "$(jq '[.items[0].status | (.initContainerStatuses + .containerStatuses)[] | select(.state.terminated.exitCode == 0)] | length' "$here/resultats/.h5_scan.pod.json")" "${#CONTENEURS[@]}"
  note "job réussi" "${etat%%/*}" 1
  d=$((fin - de)); echo "durée mesurée à 5 s près : $d s, borne prédite 300 s"
  [ "$d" -le 300 ] || { echo "KO   durée au-dessus de la borne"; ko=1; }
  jq -c '.items[0].spec.containers[] | select(.name == "revocation") | .resources' "$here/resultats/.h5_scan.pod.json"
  note "revocation, OOM ou redémarrage" "$(jq '[.items[0].status.containerStatuses[] | select(.restartCount > 0 or .lastState.terminated != null or .state.terminated.reason == "OOMKilled")] | length' "$here/resultats/.h5_scan.pod.json")" 0
  rm -f -- "$here/resultats/.h5_scan.pod.json"
  for c in "${CONTENEURS[@]}"; do kubectl logs -n scan "job/$JOB" -c "$c" </dev/null 2>&1 | grep -E '^(SOURCE|BASE|SBOM|SCAN|PREDICAT|ATTESTATION|PUBLIE)\||révoqué' | sed "s/^/$c: /" | cut -c1-200; done

  echo "## N4, Zot"
  note "referrers sur l'image" "$(referrers)" "$((avant + 1))"

  echo "## N5, CronJob"
  kubectl get cronjob -n scan scan-sample-app -o jsonpath='suspendu : {.spec.suspend}, dernier planifié : {.status.lastScheduleTime}, dernière réussite : {.status.lastSuccessfulTime}, actifs : {.status.active}{"\n"}' </dev/null
  echo "place libre la plus basse sur sc-confiance : $mini Mo"

  echo "## N1, refus dans l'audit de l'API, espace scan, depuis le départ (verbe, ressource, nom, code)"
  ssh "${SSHO[@]}" poc@192.168.161.11 "sudo sh -c 'cat \$(ls -1 /var/lib/rancher/rke2/server/logs/audit*.log | LC_ALL=C sort) | grep -F \"\\\"namespace\\\":\\\"scan\\\"\" || true'" </dev/null \
    | jq -r --arg de "$(date -ud "@$de" +%FT%TZ)" 'select(.stage == "ResponseComplete" and .requestReceivedTimestamp >= $de and (.responseStatus.code // 0) >= 400) | "  \(.user.username) \(.verb) \(.objectRef.resource) \(.objectRef.name // "-") \(.responseStatus.code) \(.responseStatus.message // "" | .[0:110])"' \
    | sort | uniq -c
  echo "fin de la liste des refus"
  kubectl get policyreport -n scan --no-headers -o custom-columns=N:.metadata.name,P:.summary.pass,F:.summary.fail,W:.summary.warn,E:.summary.error </dev/null 2>&1 | cut -c1-90

  echo "## N6, Grafana, lu par l'auditeur"
  n=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    n=$(grafana "${de}000" | grep -cE '^(SOURCE|SCAN|PUBLIE)\||révoqué' || true)
    [ "$n" -ge 4 ] && break
    sleep 10
  done
  note "marqueurs SOURCE, SCAN, PUBLIE et révocation lus dans Grafana" "$n" 4

  [ "$ko" = 0 ] && echo "bilan : OK" || echo "bilan : KO"
  date -u '+fin du relevé %H:%M:%S UTC'
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$here/resultats/durcissement-h5_scan.log"
