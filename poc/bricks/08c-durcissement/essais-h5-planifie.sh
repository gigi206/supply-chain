#!/usr/bin/env bash
# Brique 08c : relecture du premier passage de scan-sample-app déclenché par le planificateur sous H1 à H5, prédictions P1 à P6 du README.
# Lecture seule : ne crée aucun job, ne change aucune règle. À lancer après PLAN ; refuse avant cette heure et si le journal existe déjà.
# PLAN, AVANT (referrers avant le passage), JOB et JOURNAL se règlent par l'environnement, pour un essai à blanc sur le job manuel.
# Usage (racine du dépôt) : poc/bricks/08c-durcissement/essais-h5-planifie.sh   (journal : resultats/durcissement-h5_planifie.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
O8=$HOME/.cache/supply-chain-poc/08
PLAN=${PLAN:-2026-11-07T09:30:00Z}
AVANT=${AVANT:-3}
JOB=${JOB:-}
JOURNAL=${JOURNAL:-$here/resultats/durcissement-h5_planifie.log}
SUJET=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
CONTENEURS=(source analyser jetons attester publier revocation)
SSHO=(-n -i "$O8/ssh/id_ed25519" -o "UserKnownHostsFile=$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)

plan_s=$(date -ud "$PLAN" +%s)
[ "$(date -u +%s)" -ge "$plan_s" ] || { echo "trop tôt : il est $(date -u +%H:%M:%S) UTC, passage attendu à $PLAN, rien relevé"; exit 2; }
[ ! -e "$JOURNAL" ] || { echo "$JOURNAL existe déjà, rien relevé"; exit 2; }

referrers() { curl -fsS --cacert "$O8/pki/ca-poc.crt" "https://192.168.161.13:5000/v2/builds/scan/sample-app/referrers/$SUJET" </dev/null | jq '.manifests | length'; }

grafana() { # depuis-epoch-ms : lignes du job lues par l'auditeur à travers Grafana, sur le gabarit d'essais-h5-scan.sh
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
  date -u '+relecture du %d/%m/%Y à %H:%M:%S UTC'
  echo "passage attendu : $PLAN"

  echo "## P1, planificateur"
  kubectl get cronjob -n scan scan-sample-app -o json </dev/null > "$here/resultats/.h5_planifie.cron.json"
  uid=$(jq -r .metadata.uid "$here/resultats/.h5_planifie.cron.json")
  jq -r '"suspendu : \(.spec.suspend), dernier planifié : \(.status.lastScheduleTime // "aucun"), dernière réussite : \(.status.lastSuccessfulTime // "aucune"), actifs : \(.status.active // [] | length)"' "$here/resultats/.h5_planifie.cron.json"
  note "dernier passage planifié" "$(jq -r '.status.lastScheduleTime // "aucun"' "$here/resultats/.h5_planifie.cron.json")" "$PLAN"
  rm -f -- "$here/resultats/.h5_planifie.cron.json"
  kubectl get jobs -n scan --sort-by=.metadata.creationTimestamp </dev/null
  if [ -z "$JOB" ]; then
    # jobs créés depuis PLAN seulement : successfulJobsHistoryLimit (3) garde ceux des passages précédents (ajout du 07/11/2026, 16:28 UTC)
    mapfile -t jobs < <(kubectl get jobs -n scan -o json </dev/null | jq -r --arg u "$uid" --arg p "$PLAN" '.items[] | select(any(.metadata.ownerReferences[]?; .uid == $u)) | select(.metadata.name != "scan-sample-app-h5-manuel") | select(.metadata.creationTimestamp >= $p) | .metadata.name')
    note "jobs créés par le planificateur" "${#jobs[@]}" 1
    JOB=${jobs[0]:-}
  fi
  if [ -z "$JOB" ]; then
    echo "KO   aucun job à relire : rien de prouvé sur le planificateur"
    echo "bilan : KO"
    exit 1
  fi
  echo "job relu : $JOB"
  cree=$(kubectl get job -n scan "$JOB" -o jsonpath='{.metadata.creationTimestamp}' </dev/null)
  retard=$(( $(date -ud "$cree" +%s) - plan_s ))
  echo "job créé à $cree, $retard s après l'heure attendue, borne prédite 60 s"
  [ "$retard" -ge 0 ] && [ "$retard" -le 60 ] || { echo "KO   création hors de la minute attendue"; ko=1; }

  echo "## P3, conteneurs"
  kubectl get pods -n scan -l job-name="$JOB" -o json </dev/null > "$here/resultats/.h5_planifie.pod.json"
  jq -c '.items[0] | {noeud: .spec.nodeName, phase: .status.phase, debut: .status.startTime}' "$here/resultats/.h5_planifie.pod.json"
  note "pods créés par le job" "$(jq '.items | length' "$here/resultats/.h5_planifie.pod.json")" 1
  jq -r '.items[0].status | (.initContainerStatuses + .containerStatuses)[] | "\(.name) code=\(.state.terminated.exitCode // "?") motif=\(.state.terminated.reason // "?") redémarrages=\(.restartCount) \(.state.terminated.startedAt // "") \(.state.terminated.finishedAt // "")"' "$here/resultats/.h5_planifie.pod.json"
  note "conteneurs terminés avec le code 0 sur ${#CONTENEURS[@]}" "$(jq '[.items[0].status | (.initContainerStatuses + .containerStatuses)[] | select(.state.terminated.exitCode == 0)] | length' "$here/resultats/.h5_planifie.pod.json")" "${#CONTENEURS[@]}"
  note "job réussi" "$(kubectl get job -n scan "$JOB" -o jsonpath='{.status.succeeded}' </dev/null)" 1
  debut=$(jq -r '.items[0].status.startTime' "$here/resultats/.h5_planifie.pod.json")
  fin=$(jq -r '.items[0].status.containerStatuses[0].state.terminated.finishedAt // ""' "$here/resultats/.h5_planifie.pod.json")
  if [ -n "$fin" ]; then
    d=$(( $(date -ud "$fin" +%s) - $(date -ud "$debut" +%s) ))
    echo "durée du pod : $d s, borne prédite 300 s"
    [ "$d" -le 300 ] || { echo "KO   durée au-dessus de la borne"; ko=1; }
  else
    echo "KO   fin du pod illisible"; ko=1
  fi
  note "revocation, OOM ou redémarrage" "$(jq '[.items[0].status.containerStatuses[] | select(.restartCount > 0 or .lastState.terminated != null or .state.terminated.reason == "OOMKilled")] | length' "$here/resultats/.h5_planifie.pod.json")" 0
  rm -f -- "$here/resultats/.h5_planifie.pod.json"
  for c in "${CONTENEURS[@]}"; do kubectl logs -n scan "job/$JOB" -c "$c" </dev/null 2>&1 | grep -E '^(SOURCE|BASE|SBOM|SCAN|PREDICAT|ATTESTATION|PUBLIE)\||révoqué' | sed "s/^/$c: /" | cut -c1-200; done

  echo "## P4, Zot"
  note "referrers sur l'image" "$(referrers)" "$((AVANT + 1))"
  echo "bases archivées : $(curl -fsS --cacert "$O8/pki/ca-poc.crt" "https://192.168.161.13:5000/v2/vulndb/grype/tags/list" </dev/null | jq -c '.tags')"

  echo "## P1 et P2, audit de l'API, espace scan, depuis l'heure attendue (créations de jobs et de pods, puis refus)"
  # borne comparée en secondes : en chaîne, « 09:30:00.1Z » précède « 09:30:00Z » (KO du 07/11, complément de 09:49:54 UTC ; corrigé le 07/11/2026, 16:29 UTC)
  audit=$(ssh "${SSHO[@]}" poc@192.168.161.11 "sudo sh -c 'cat \$(ls -1 /var/lib/rancher/rke2/server/logs/audit*.log | LC_ALL=C sort) | grep -F \"\\\"namespace\\\":\\\"scan\\\"\" || true'" </dev/null \
    | jq -r --argjson de "$plan_s" 'select(.stage == "ResponseComplete" and (.requestReceivedTimestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) >= $de)
        | (.responseStatus.code // 0) as $c
        | if .verb == "create" and (.objectRef.resource == "jobs" or .objectRef.resource == "pods") and (.objectRef.subresource // "") == "" then "creation \(.user.username) \(.objectRef.resource) \($c)"
          elif $c >= 400 then "refus \(.user.username) \(.verb) \(.objectRef.resource) \(.objectRef.name // "-") \($c) \(.responseStatus.message // "" | .[0:110])"
          else empty end' \
    | sort | uniq -c)
  printf '%s\n' "$audit"
  echo "fin de l'extrait d'audit"
  note "création du job par le planificateur, en 201" "$(printf '%s\n' "$audit" | grep -c 'creation system:serviceaccount:kube-system:cronjob-controller jobs 201' || true)" 1
  note "création du pod par le contrôleur de jobs, en 201" "$(printf '%s\n' "$audit" | grep -c 'creation system:serviceaccount:kube-system:job-controller pods 201' || true)" 1
  note "refus 403 ou 422" "$(printf '%s\n' "$audit" | grep -cE '^ *[0-9]+ refus .* (403|422) ' || true)" 0
  kubectl get policyreport -n scan --no-headers -o custom-columns=N:.metadata.name,P:.summary.pass,F:.summary.fail,W:.summary.warn,E:.summary.error </dev/null 2>&1 | cut -c1-90

  echo "## P6, Grafana, lu par l'auditeur"
  note "marqueurs SOURCE, SCAN, PUBLIE et les deux révocations lus dans Grafana" "$(grafana "${plan_s}000" | grep -cE '^(SOURCE|SCAN|PUBLIE)\||révoqué' || true)" 5

  [ "$ko" = 0 ] && echo "bilan : OK" || echo "bilan : KO"
  date -u '+fin du relevé %H:%M:%S UTC'
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$JOURNAL"
