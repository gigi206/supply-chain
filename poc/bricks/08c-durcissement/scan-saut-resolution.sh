#!/usr/bin/env bash
# Brique 08c, W8 du saut d'un passage du scan : résolution de ScanEnRetard après le passage du 09/11 (resultats/mesures-reelles-predictions.md,
# additif du 07/11/2026 à 16:31 UTC). Le passage lui-même est relu par essais-h5-planifie.sh (PLAN=2026-11-09T09:30:00Z AVANT=4).
# Lecture seule : Prometheus, le journal du récepteur local et Zot sur sc-stockage, le CronJob par l'API ; rien d'écrit hors du journal.
# Ajout du 07/11/2026, 17:58 UTC, avant le passage (accord du propriétaire : « Oui, prépare-le ») : les notifications du récepteur sont aussi
# lues dans Loki, par l'auditeur à travers Grafana. Le journal local de sc-stockage a perdu ses lignes du 06/11 antérieures à 17:03 UTC
# (chains-echec-signature.log). Loki est affiché et comparé au journal local, sans changer les OK et KO prédits.
# Refuse avant FENETRE et si le journal existe ; ne juge rien si le CronJob est suspendu ou si le passage de PLAN n'a pas eu lieu.
# Usage (racine du dépôt) : poc/bricks/08c-durcissement/scan-saut-resolution.sh   (journal : resultats/scan-saut-w8_resolution.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
O8=$HOME/.cache/supply-chain-poc/08
PLAN=${PLAN:-2026-11-09T09:30:00Z}
FENETRE=${FENETRE:-2026-11-09T10:00:00Z}
DEPUIS=${DEPUIS:-2026-11-08 11:30:00}   # journal du récepteur relu depuis (UTC) : avant le firing attendu vers 11:36:48 UTC le 08/11
JOURNAL=${JOURNAL:-$here/resultats/scan-saut-w8_resolution.log}
SSHO=(-n -i "$O8/ssh/id_ed25519" -o "UserKnownHostsFile=$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)

[ "$(date -u +%s)" -ge "$(date -ud "$FENETRE" +%s)" ] || { echo "trop tôt : il est $(date -u +%H:%M:%S) UTC, relevé permis dès $FENETRE, rien relevé"; exit 2; }
[ ! -e "$JOURNAL" ] || { echo "$JOURNAL existe déjà, rien relevé"; exit 2; }

stockage() { ssh "${SSHO[@]}" poc@192.168.161.13 "$1" </dev/null; }
regle() { stockage "curl -fsS 'http://127.0.0.1:9090/api/v1/rules?type=alert'" | jq -r --arg n "$1" '[.data.groups[].rules[] | select(.name == $n) | .state] | first // "absente"'; }

{
  ko=0
  note() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2, attendu $3"; ko=1; fi; }
  date -u '+relevé du %d/%m/%Y à %H:%M:%S UTC'
  echo "## prédiction (écrite le 07/11/2026, avant le passage du 09/11, additif W8 de resultats/mesures-reelles-predictions.md)"
  echo "- garde : CronJob repris, dernier passage planifié $PLAN ; sinon rien n'est jugé"
  echo "- ScanEnRetard et ScanBientotRefuse inactives ; métrique du dernier referrer après $PLAN, égale à la date du referrer le plus récent dans Zot"
  echo "- récepteur : une seule notification resolved de ScanEnRetard, même début que les firing ; fin 0 à 1200 s après le nouveau referrer"
  echo "- firing notifiées : 6 (repeat_interval 4h de 11:36 UTC le 08/11 à la résolution), compte en CONSTAT"
  echo "- ajout du 07/11/2026, 17:58 UTC, avant le passage : mêmes notifications dans Loki ; un écart avec le journal local est un CONSTAT"

  echo "## garde"
  etat=$(kubectl get cronjob -n scan scan-sample-app -o json </dev/null | jq -r '"\(.spec.suspend // false)|\(.status.lastScheduleTime // "aucun")"')
  echo "suspendu|dernier passage planifié : $etat"
  if [ "$etat" != "false|$PLAN" ]; then
    echo "NON JUGÉ : la reprise n'a pas eu lieu ou le passage de $PLAN manque ; W8 non relevée"
    echo "bilan : non jugé"
    exit 3
  fi

  echo "## Prometheus et Zot"
  r1=$(stockage "curl -fsS -G http://127.0.0.1:9090/api/v1/query --data-urlencode query=scan_dernier_referrer_timestamp_seconds" | jq -r '.data.result[0].value[1] // "0" | tonumber | floor')
  z=$(curl -fsS --cacert "$O8/pki/ca-poc.crt" -H 'Accept: application/vnd.oci.image.index.v1+json' \
    "https://192.168.161.13:5000/v2/builds/scan/sample-app/referrers/sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5" </dev/null \
    | jq -r '[.manifests[] | select(.annotations["dev.sigstore.bundle.predicateType"] == "https://supply-chain.example/scan/v1")
      | .annotations["org.opencontainers.image.created"] | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601] | max // 0')
  echo "métrique du dernier referrer : $(date -ud "@$r1" +%FT%TZ) ; referrer de scan le plus récent dans Zot : $(date -ud "@$z" +%FT%TZ)"
  note "métrique postérieure au passage" "$([ "$r1" -ge "$(date -ud "$PLAN" +%s)" ] && echo oui || echo non)" oui
  note "métrique égale au referrer le plus récent de Zot" "$r1" "$z"
  note "ScanEnRetard" "$(regle ScanEnRetard)" inactive
  note "ScanBientotRefuse" "$(regle ScanBientotRefuse)" inactive

  echo "## récepteur local, ScanEnRetard depuis $DEPUIS UTC (reçu à, statut, début, fin)"
  stockage "sudo journalctl -u recepteur-alertes -o json --no-pager --since '$DEPUIS UTC'" \
    | jq -R -r 'fromjson? | (.__REALTIME_TIMESTAMP | tonumber / 1000000 | floor) as $t | .MESSAGE | (fromjson? // empty)
      | select(.alerte == "ScanEnRetard") | "\($t | todate) \(.statut) \(.debut) \(.fin)"' > "$here/resultats/.w8_recepteur"
  cat "$here/resultats/.w8_recepteur"
  echo "firing notifiées : $(grep -c ' firing ' "$here/resultats/.w8_recepteur" || true)"
  [ "$(grep -c ' firing ' "$here/resultats/.w8_recepteur" || true)" = 6 ] || echo "CONSTAT nombre de firing notifiées différent de 6 (redémarrage d'Alertmanager ou de la VM, ou décalage des répétitions)"
  note "notifications resolved" "$(grep -c ' resolved ' "$here/resultats/.w8_recepteur" || true)" 1
  note "débuts distincts (firing et resolved)" "$(cut -d' ' -f3 "$here/resultats/.w8_recepteur" | sort -u | grep -c . || true)" 1
  fin=$(awk '$2 == "resolved" {print $4; exit}' "$here/resultats/.w8_recepteur")
  if [ -n "$fin" ]; then
    d=$(( $(date -ud "$fin" +%s) - r1 ))
    # borne : fraicheur-scan.timer (OnUnitActiveSec=15min, AccuracySec 1 min), collecte 30 s, évaluation 30 s, marge 120 s ; 597 s le 07/11
    [ "$d" -ge 0 ] && [ "$d" -le 1200 ] && echo "OK   fin de ScanEnRetard $d s après le nouveau referrer" \
      || echo "CONSTAT fin de ScanEnRetard $d s après le nouveau referrer (prédit : 0 à 1200 s)"
    echo "reçue au récepteur $(( $(date -ud "$(awk '$2 == "resolved" {print $1; exit}' "$here/resultats/.w8_recepteur")" +%s) - $(date -ud "$fin" +%s) )) s après la fin (affiché, non contrôlé)"
  fi

  echo "## récepteur dans Loki ({unite=\"recepteur-alertes.service\"}, auditeur à travers Grafana), ScanEnRetard depuis $DEPUIS UTC"
  q=$(jq -nc --arg e '{unite="recepteur-alertes.service"} |= "ScanEnRetard"' --arg de "$(date -ud "$DEPUIS" +%s)000" --arg a "$(date -u +%s)000" \
    '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: 1000, direction: "forward"}], from: $de, to: $a}')
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -X POST -H 'Content-Type: application/json' "https://192.168.161.13:3001/api/ds/query" -d "$q" \
    | jq -r '(.results.A.error // empty | "ERREUR Loki : \(.)"), (.results.A.frames[]? | .data.values as $v | range(0; ($v[2] // []) | length) | "\($v[1][.])\t\($v[2][.])")' \
    | jq -R -r 'if startswith("ERREUR") then . else split("\t") as $p | ($p[0] | tonumber / 1000 | floor) as $t | ($p[1:] | join("\t") | fromjson? // empty)
        | select(.alerte == "ScanEnRetard") | "\($t | todate) \(.statut) \(.debut) \(.fin)" end' | sort > "$here/resultats/.w8_loki"
  cat "$here/resultats/.w8_loki"
  echo "Loki : firing $(grep -c ' firing ' "$here/resultats/.w8_loki" || true), resolved $(grep -c ' resolved ' "$here/resultats/.w8_loki" || true)"
  if sort "$here/resultats/.w8_recepteur" | cmp -s - "$here/resultats/.w8_loki"; then echo "Loki et journal local : mêmes lignes"
  else echo "CONSTAT Loki et journal local diffèrent (lignes présentes d'un seul côté ci-dessous, < journal local, > Loki)"
    diff <(sort "$here/resultats/.w8_recepteur") "$here/resultats/.w8_loki" | grep '^[<>]' || true
  fi
  rm -f -- "$here/resultats/.w8_recepteur" "$here/resultats/.w8_loki"

  [ "$ko" = 0 ] && echo "bilan : OK" || echo "bilan : KO"
  date -u '+fin du relevé %H:%M:%S UTC'
  exit "$ko"
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$JOURNAL"
exit "${PIPESTATUS[0]}"
