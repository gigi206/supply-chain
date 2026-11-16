#!/usr/bin/env bash
# Brique 06, révision 1.0.0-2, ligne 10 de la cascade (resultats/revision-predictions.md) : lecture de U13, « ScanEnRetard reste
# inactive de l'étape 8 à l'étape 10 », avant s6a.sh periodique et après fraicheur. Préparé le 16/11/2026 (« Oui, prépare-le ») ;
# prédictions L1 à L7 et L13 de resultats/s6a-service-predictions.md, commitées avant tout lancement. Modèle : scan-saut-resolution.sh
# de la 08c.
# LECTURE SEULE : CronJob et Jobs de l'espace scan (API, sans journaux de pod) ; referrers de builds/scan/sample-app-deb (Zot,
# lecture anonyme) ; règles, séries et ALERTS de Prometheus et journal du récepteur local sur sc-stockage (ssh, champs alerte,
# statut, début et fin seulement). Aucun secret lu ; rien d'écrit hors du journal et d'un dossier temporaire du cache.
# Une lecture ratée (code de kubectl, curl ou ssh non nul, statut de Prometheus autre que success) est signalée par une ligne
# « LECTURE RATÉE » et rend le code 1 : une section vide n'est jamais prise pour « rien ».
# Usage (racine du dépôt) : poc/bricks/06-deb-sbuild/lecture-u13.sh
#   JOURNAL=… pour un autre journal (défaut resultats/lecture-u13.log ; refus s'il existe)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
h06=$(cd "$(dirname "$0")" && pwd)
JOURNAL=${JOURNAL:-$h06/resultats/lecture-u13.log}
O8=$HOME/.cache/supply-chain-poc/08
CA=$O8/pki/ca-poc.crt
ZOT=https://192.168.161.13:5000/v2
DEPUIS=2026-11-15T20:39:34Z                                                      # fin de S4d3 (étape 8 de la carte)
ANCIEN=sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e   # cible du CronJob rendu le 14/11
D=sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e        # deb de S4d3 (s6a.sh, DEB_REF)
PREDICAT=https://supply-chain.example/scan/v1
SSHO=(-n -i "$O8/ssh/id_ed25519" -o "UserKnownHostsFile=$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)

[ ! -e "$JOURNAL" ] || { echo "$JOURNAL existe déjà, rien relevé"; exit 2; }
X=$(mktemp -d "$HOME/.cache/supply-chain-poc/06/lecture-u13.XXXXXX") || exit 1
trap 'rm -rf -- "${X:?}"' EXIT

ko=0
rate() { echo "LECTURE RATÉE : $1"; ko=1; }
stockage() { ssh "${SSHO[@]}" poc@192.168.161.13 "$1" </dev/null; }
# prom fichier requête [paramètres de query_range] : réponse dans $X/fichier, statut success exigé
prom() {
  local f=$1 q=$2; shift 2
  if [ $# = 0 ]; then stockage "curl -fsS -G http://127.0.0.1:9090/api/v1/query --data-urlencode $(printf '%q' "query=$q")" > "$X/$f"
  else stockage "curl -fsS -G http://127.0.0.1:9090/api/v1/query_range --data-urlencode $(printf '%q' "query=$q") $*" > "$X/$f"; fi \
    || { rate "Prometheus ($f), code $?"; return 1; }
  [ "$(jq -r .status "$X/$f" 2>/dev/null)" = success ] || { rate "Prometheus ($f), statut $(jq -r .status "$X/$f" 2>/dev/null)"; return 1; }
  echo "  ($f : $(jq '.data.result | length' "$X/$f") résultat(s))"
}

{
  a=$(date -u +%s); f=$(( a - $(date -ud "$DEPUIS" +%s) ))
  echo "# lecture-u13.sh, $(date -ud "@$a" +%FT%TZ) ; fenêtre depuis $DEPUIS ($f s)"

  echo "## CronJob scan-sample-app-deb et Jobs de l'espace scan (API)"
  if kubectl get cronjob -n scan scan-sample-app-deb -o json </dev/null > "$X/cronjob.json"; then
    jq -r --arg n builds/sample-app-deb@ '
      "horaire \(.spec.schedule) \(.spec.timeZone) ; suspendu \(.spec.suspend // false)",
      "dernier passage planifié \(.status.lastScheduleTime // "aucun") ; dernier succès \(.status.lastSuccessfulTime // "aucun")",
      "cible : \([.spec.jobTemplate.spec.template.spec | (.initContainers // [])[], .containers[] | .env[]? | .value // empty
        | select(contains($n)) | sub(".*@"; "")] | unique | join(" "))"' "$X/cronjob.json"
  else rate "CronJob scan-sample-app-deb"; fi
  if kubectl get jobs -n scan -o json </dev/null > "$X/jobs.json"; then
    echo "  $(jq '.items | length' "$X/jobs.json") Job(s)"
    jq -r '.items[] | "  \(.metadata.name) début \(.status.startTime // "-") fin \(.status.completionTime // "-") succès \(.status.succeeded // 0) échecs \(.status.failed // 0)"' "$X/jobs.json"
  else rate "Jobs de scan"; fi

  echo "## referrers de scan dans builds/scan/sample-app-deb (Zot, lecture anonyme ; date org.opencontainers.image.created)"
  for x in "$ANCIEN" "$D"; do
    c=$(curl -sS --cacert "$CA" -o "$X/referrers.json" -w '%{http_code}' -H 'Accept: application/vnd.oci.image.index.v1+json' \
      "$ZOT/builds/scan/sample-app-deb/referrers/$x" </dev/null) || c="curl $?"
    case $c in
      200) echo "${x:7:8} : HTTP 200, $(jq --arg p "$PREDICAT" '[(.manifests // [])[] | select(.annotations["dev.sigstore.bundle.predicateType"] == $p)] | length' "$X/referrers.json") referrer(s) de scan"
           jq -r --arg p "$PREDICAT" '(.manifests // [])[] | select(.annotations["dev.sigstore.bundle.predicateType"] == $p)
             | "  \(.annotations["org.opencontainers.image.created"])"' "$X/referrers.json" | sort ;;
      404) echo "${x:7:8} : HTTP 404, aucun referrer" ;;
      *) rate "referrers de ${x:7:8}, $c" ;;
    esac
  done

  echo "## Prometheus : règles de scan (nom, santé, état, dernière évaluation)"
  if stockage "curl -fsS 'http://127.0.0.1:9090/api/v1/rules?type=alert'" > "$X/regles.json" && [ "$(jq -r .status "$X/regles.json")" = success ]; then
    jq -r '.data.groups[].rules[] | select(.name | test("^Scan")) | "  \(.name)\t\(.health)\t\(.state)\t\(.lastEvaluation)"' "$X/regles.json"
  else rate "règles de Prometheus"; fi
  echo "## Prometheus : séries de fraîcheur maintenant (nom, dépôt, valeur, date)"
  prom series.json '{__name__=~"scan_dernier_referrer_timestamp_seconds|base_grype_construite_timestamp_seconds"}' \
    && jq -r '.data.result[] | "  \(.metric.__name__) \(.metric.depot) \(.value[1]) \(.value[1] | tonumber | todate)"' "$X/series.json"
  echo "## Prometheus : valeurs distinctes de la série du deb dans la fenêtre (première vue, pas de 60 s)"
  prom plage.json 'scan_dernier_referrer_timestamp_seconds{depot="builds/scan/sample-app-deb"}' --data-urlencode "start=$(( a - f ))" \
    --data-urlencode "end=$a" --data-urlencode step=60 \
    && jq -r '.data.result[].values | reduce .[] as $v ([]; if (length == 0 or .[-1][1] != $v[1]) then . + [$v] else . end)
      | .[] | "  vue dès \(.[0] | todate) : \(.[1]) (\(.[1] | tonumber | todate))"' "$X/plage.json"
  echo "## Prometheus : ALERTS de scan dans la fenêtre (max_over_time ; 0 résultat : jamais pending ni firing)"
  prom alerts.json "max_over_time(ALERTS{alertname=~\"Scan.*\"}[${f}s])" \
    && jq -r '.data.result[] | "  \(.metric.alertname) \(.metric.alertstate) \(.metric.depot // "-")"' "$X/alerts.json"

  echo "## récepteur local : notifications de scan depuis $DEPUIS (reçu à, alerte, statut, début, fin)"
  if stockage "sudo journalctl -u recepteur-alertes -o json --no-pager --since '$(date -ud "$DEPUIS" '+%F %T') UTC'" > "$X/recepteur.json"; then
    echo "  $(grep -c . "$X/recepteur.json" || true) entrée(s) du journal de l'unité dans la fenêtre"
    jq -R -r 'fromjson? | (.__REALTIME_TIMESTAMP | tonumber / 1000000 | floor) as $t | .MESSAGE | (fromjson? // empty)
      | select((.alerte // "") | test("^Scan")) | "  \($t | todate) \(.alerte) \(.statut) \(.debut) \(.fin)"' "$X/recepteur.json" > "$X/scan.txt"
    echo "  $(grep -c . "$X/scan.txt" || true) notification(s) de scan"; cat "$X/scan.txt"
  else rate "journal du récepteur"; fi

  echo "## échéance : dernière valeur de la série du deb plus 26 h"
  v=$(jq -r '[.data.result[] | select(.metric.depot == "builds/scan/sample-app-deb") | .value[1]] | first // empty' "$X/series.json" 2>/dev/null)
  if [ -n "$v" ]; then echo "échéance : $(date -ud "@$(( ${v%.*} + 26 * 3600 ))" +%FT%TZ)"; else rate "série du deb absente ou non lue"; fi
  echo "# fin, $(date -u +%FT%TZ) ; bilan : $([ "$ko" = 0 ] && echo 'toutes les lectures faites' || echo 'LECTURE(S) RATÉE(S)')"
  exit "$ko"
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$JOURNAL"
