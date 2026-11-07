#!/usr/bin/env bash
# Brique 08c, saut d'un passage du scan : contre-relevé, en lecture seule, de la reprise passée par la tâche planifiée
# supply-chain-scan-saut-reprise (08/11/2026, 11:40 UTC) ; son rapport n'est pas une preuve. Relit le journal de l'étape
# scan_saut_reprendre et chrono.tsv, puis l'état réel : CronJob, Jobs, audit de l'API, alertes, récepteur local, et les
# referrers de l'image, pour confirmer AVANT du relevé du 09/11 (W8a, compte de essais-h5-planifie.sh). Rien d'écrit hors du journal.
# Les Events ne vivent qu'une heure (event-ttl, plus vieil Event mis à jour à 15:52 UTC relevé à 16:52 UTC le 07/11) :
# leurs comptes ne prouvent rien au-delà d'une heure après la reprise, l'audit (environ 16 h) les remplace pour les Jobs et le CronJob.
# Usage (racine du dépôt) : poc/bricks/08c-durcissement/scan-saut-reprise-verif.sh   (journal : resultats/scan-saut-reprise-verif.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
PASSAGE=${PASSAGE:-2026-11-08T09:30:00Z}   # passage sauté (P est pris par commun.sh : répertoire de la PKI)
SUJET=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
JOURNAL=${JOURNAL:-$here/resultats/scan-saut-reprise-verif.log}
[ ! -e "$JOURNAL" ] || { echo "$JOURNAL existe déjà, rien relevé"; exit 2; }
cd "$here/../08-trust-plane" || exit 1
DISTRO=rke2 . ./commun.sh   # sur, audit_api, D_ETAT ; P (PKI) et W (travail) sous ~/.cache/supply-chain-poc/08
eval "$(sed -n '/^ss_audit() {/,/^}/p;/^ss_alerte() {/,/^}/p' preuves.sh)"
j=$here/../08-trust-plane/resultats/preuves-h5-scan_saut_reprendre.log

{
  date -u '+contre-relevé du %d/%m/%Y à %H:%M:%S UTC, lecture seule'
  echo "## journal de l'étape (KO, CONSTAT, bilan, audit, début notifié)"
  if [ -e "$j" ]; then
    grep -E '^(KO|CONSTAT)|bilan|audit :|reprise demandée|passage sauté|début notifié|non jugée|active \(pending\)' "$j" || true
    echo "OK : $(grep -c '^OK' "$j" || true) ; KO : $(grep -c '^KO' "$j" || true) ; CONSTAT : $(grep -c '^CONSTAT' "$j" || true)"
  else
    echo "journal absent : poc/bricks/08-trust-plane/resultats/preuves-h5-scan_saut_reprendre.log"
  fi
  echo "## chrono.tsv"
  grep 'scan_saut_reprendre' resultats/chrono.tsv || echo "aucune ligne scan_saut_reprendre"
  echo "## état réel"
  kubectl get cronjob -n scan scan-sample-app -o json </dev/null \
    | jq -r '"suspendu \(.spec.suspend // false) ; dernier passage \(.status.lastScheduleTime // "aucun") ; actifs \(.status.active // [] | length)"'
  echo "Jobs du scan créés depuis $PASSAGE : $(kubectl get job -n scan -o json </dev/null | jq --arg t "$PASSAGE" '[.items[] | select(.metadata.creationTimestamp >= $t)] | length')"
  echo "audit depuis $PASSAGE, créations de Jobs dans scan (heure utilisateur code) :"
  ss_audit create jobs "$PASSAGE" </dev/null | sed 's/^/  /'
  echo "audit depuis $PASSAGE, patchs du CronJob du scan (heure utilisateur code) :"
  ss_audit patch cronjobs "$PASSAGE" </dev/null | sed 's/^/  /'
  echo "Events (une heure seulement, non probants au-delà) : du CronJob dans scan $(kubectl get events -n scan -o json </dev/null \
    | jq '[.items[] | select(.involvedObject.kind == "CronJob")] | length') ; PolicyViolation depuis $PASSAGE $(kubectl get events -A \
    --field-selector reason=PolicyViolation -o json </dev/null | jq --arg t "$PASSAGE" '[.items[] | select(.metadata.creationTimestamp >= $t)] | length')"
  echo "ScanEnRetard : $(ss_alerte ScanEnRetard </dev/null) (attendue firing jusqu'au referrer du 09/11) ; ScanBientotRefuse : $(ss_alerte ScanBientotRefuse </dev/null)"
  echo "## récepteur local, ScanEnRetard depuis $PASSAGE (reçu à, statut, début)"
  sur sc-stockage "sudo journalctl -u recepteur-alertes -o json --no-pager --since '$(date -ud "$PASSAGE" '+%Y-%m-%d %H:%M:%S') UTC'" </dev/null \
    | jq -R -r 'fromjson? | (.__REALTIME_TIMESTAMP | tonumber / 1000000 | floor) as $t | .MESSAGE | (fromjson? // empty)
      | select(.alerte == "ScanEnRetard") | "\($t | todate) \(.statut) \(.debut)"'
  echo "## referrers de l'image (AVANT du relevé du 09/11 : compte de essais-h5-planifie.sh, tous types)"
  curl -fsS --cacert "$P/ca-poc.crt" -H 'Accept: application/vnd.oci.image.index.v1+json' \
    "https://192.168.161.13:5000/v2/builds/scan/sample-app/referrers/$SUJET" </dev/null > "$W/verif-referrers.json"
  jq -r '.manifests[] | "  \(.annotations["org.opencontainers.image.created"] // "?") \(.annotations["dev.sigstore.bundle.predicateType"] // .artifactType // "?")"' \
    "$W/verif-referrers.json" | sort
  echo "referrers : $(jq '.manifests | length' "$W/verif-referrers.json")"
  rm -f -- "$W/verif-referrers.json"
  date -u '+fin %H:%M:%S UTC'
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$JOURNAL"
exit "${PIPESTATUS[0]}"
