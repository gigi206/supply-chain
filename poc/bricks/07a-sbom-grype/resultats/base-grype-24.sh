#!/usr/bin/env bash
# Ajout du 23/11/2026, après base-grype-trou.sh et base-grype-timer.sh : relevés en lecture seule autour du renouvellement de la
# base Grype, par l auditeur à travers Grafana (Prometheus, et comptes Loki seuls), et par kubectl pour le journal du scan.
# Rien sur la VM, rien d écrit dans le cluster.
#   alertes_23  historique de la série ALERTS de Prometheus le 23/11 de 06:00 à 09:30 UTC (panne de sc-stockage) : par alerte et
#               par état, nombre de séries, premier et dernier point
#   releve_24   refuse avant le 24/11 à 09:33 UTC, avant d ouvrir son journal : état de la règle BaseGrypeVieillie ; historique
#               de cette alerte le 24/11 de 05:00 à 10:00 UTC ; date de construction de la base la plus récente (métrique
#               base_grype_construite_timestamp_seconds) ; messages de systemd et du service base-grype dans Loki (comptes) ;
#               job de scan-sample-app du 24/11 à 09:30 : réussi, ligne BASE, préfixes du 23/11 plus VEX, lignes dans Grafana
#   compteurs_23  (ajout du 23/11/2026, après alertes_23) ChainsEchecSignature (A2) et KyvernoRefusAnormaux (A5) déclenchées
#               à la reprise de la collecte : compteurs qu elles lisent, sommés, avant la panne (06:40), à la reprise (08:36) et
#               après (08:50 et 09:30) ; égaux, ils excluent un nouvel échec de signature ou un nouveau refus
#   fins_23     (ajout du 23/11/2026, après compteurs_23, sur relecture du conseiller) : la requête par plage d alertes_23 prolonge
#               le dernier échantillon d une série arrêtée sans marqueur de fin (fenêtre de 5 min) ; horodatage réel du dernier
#               échantillon de chaque alerte déclenchée (timestamp) à 08:37, 08:40 et 08:45 ; présence des séries lues par A2 et
#               A5 de 08:25 à 08:36 ; cibles (job, instance) de CollecteEnPanne ; dernier échantillon avant la reprise
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/resultats/base-grype-24.sh <étape>  (journal : base-grype-24-<étape>.log)
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
O8=$HOME/.cache/supply-chain-poc/08
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
e=${1:-}
case $e in alertes_23|releve_24|compteurs_23|fins_23) ;; *) echo "usage : $0 alertes_23 | releve_24 | compteurs_23 | fins_23" >&2; exit 64 ;; esac
if [ "$e" = releve_24 ] && [ "$(date -u +%Y%m%d%H%M)" -lt 202611240933 ]; then echo "avant le 24/11 à 09:33 UTC : rien relevé, aucun journal" >&2; exit 1; fi
L=$here/base-grype-24-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }

ko=0
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }
g() { # corps JSON de /api/ds/query
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$1"
}
gget() { # chemin de l API de Grafana
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" "https://192.168.161.13:3001$1"
}
q() { # expr Loki, heure de fin (epoch s) : compte
  g "$(jq -nc --arg q "$1" --arg t "${2}000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')" \
    | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end'
}
alertes() { # expr PromQL, début, fin (ISO) : une ligne par alerte et par état
  local f t
  f=$(date -ud "$2" +%s); t=$(date -ud "$3" +%s)
  g "$(jq -nc --arg q "$1" --arg f "${f}000" --arg t "${t}000" '{from:$f,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:$q,range:true,instant:false,intervalMs:30000,maxDataPoints:2000}]}')" \
    | jq -r 'if .results.A.error then "erreur : \(.results.A.error)" else
        [.results.A.frames[]? | select((.data.values | length) > 1 and (.data.values[0] | length) > 0) | {a: .schema.fields[1].labels.alertname, s: .schema.fields[1].labels.alertstate, d: .data.values[0][0], f: .data.values[0][-1]}]
        | if length == 0 then "aucune" else group_by([.a, .s]) | map("\(.[0].a) \(.[0].s) : \(length) série(s), de \(map(.d) | min / 1000 | todate) à \(map(.f) | max / 1000 | todate)") | .[] end end'
}

{
echo "# base-grype-24.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
case $e in
  alertes_23)
    echo "ALERTS, 2026-11-23 de 06:00 à 09:30 UTC, pas de 30 s :"
    alertes ALERTS 2026-11-23T06:00:00Z 2026-11-23T09:30:00Z | sed 's/^/  /'
    echo "BaseGrypeVieillie, même plage :"
    alertes 'ALERTS{alertname="BaseGrypeVieillie"}' 2026-11-23T06:00:00Z 2026-11-23T09:30:00Z | sed 's/^/  /' ;;
  releve_24)
    attendu "règle BaseGrypeVieillie (état, santé)" "$(gget /api/datasources/proxy/uid/prometheus/api/v1/rules \
      | jq -r '[.data.groups[].rules[] | select(.name == "BaseGrypeVieillie") | "\(.state) \(.health)"] | join(",")')" "inactive ok"
    echo "BaseGrypeVieillie, 2026-11-24 de 05:00 à 10:00 UTC, pas de 30 s :"
    alertes 'ALERTS{alertname="BaseGrypeVieillie"}' 2026-11-24T05:00:00Z 2026-11-24T10:00:00Z | sed 's/^/  /'
    now=$(date -u +%s)
    b=$(g "$(jq -nc --arg t "${now}000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:"base_grype_construite_timestamp_seconds",instant:true}]}')" \
      | jq -r '[.results.A.frames[]? | .data.values[1][0]] | if length == 1 then .[0] | tostring else "lecture impossible" end')
    case $b in ''|*[!0-9]*) echo "KO   base_grype_construite_timestamp_seconds illisible : $b"; ko=1 ;;
      *) echo "base la plus récente construite le : $(date -ud "@$b" +%FT%TZ)"
         attendu "jour de construction de la base la plus récente" "$(date -ud "@$b" +%F)" 2026-11-24 ;; esac
    S='{noeud="sc-stockage", source="journal", unite="init.scope"} |= "base-grype"'
    t=$(date -ud 2026-11-24T08:45:00Z +%s)
    for f in base-grype.timer base-grype.service Starting Finished Failed; do
      echo "init.scope base-grype |= $f, 24/11 de 07:55 à 08:45 : $(q "sum(count_over_time($S |= \"$f\" [50m]))" "$t")"
    done
    echo "unite base-grype.service, 24/11 de 07:55 à 08:45 : $(q 'sum(count_over_time({noeud="sc-stockage", source="journal", unite="base-grype.service"} [50m]))' "$t")"
    jobs_du() { kubectl get jobs -n scan -o json | jq -r --arg d "$1" '.items[] | select(.metadata.ownerReferences[0].name == "scan-sample-app" and .status.startTime == $d) | .metadata.name'; }
    j=$(jobs_du 2026-11-24T09:30:00Z); j0=$(jobs_du 2026-11-23T09:30:00Z)
    echo "job du 24/11 : ${j:-aucun} ; job du 23/11 : ${j0:-aucun}"
    if [ -z "$j" ] || [ -z "$j0" ]; then echo "KO   job manquant"; ko=1; else
      attendu "job du 24/11 (réussi/échoué/actif)" "$(kubectl get job "$j" -n scan -o json | jq -r '"\(.status.succeeded // 0)/\(.status.failed // 0)/\(.status.active // 0)"')" 1/0/0
      echo "  durée : $(kubectl get job "$j" -n scan -o json | jq -r '"\(.status.startTime) -> \(.status.completionTime)"')"
      jl() { kubectl logs -n scan "job/$1" --all-containers 2>&1; }
      pref() { jl "$1" | awk '{ if (tolower($0) ~ /jeton|token/) print "masquée"; else { split($0, a, "|"); print a[1] } }' | sort | paste -sd,; }
      # modifié le 23/11/2026 (note de 2026-11-23T14:38:33Z de 07b-carte.md, avant le relevé) : pièce 5 posée avant le relevé, sur décision
      # du propriétaire ; le scanner neuf ajoute une ligne VEX| : préfixes du 24/11 = ceux du 23/11 plus VEX
      attendu "préfixes des lignes du journal, triés (24/11 = 23/11 plus VEX)" "$(pref "$j")" "$( { pref "$j0" | tr , '\n'; echo VEX; } | sort | paste -sd,)"
      for x in "$j0" "$j"; do echo "  $x : $(jl "$x" | grep -E '^(BASE|SCAN)\|' | sed 's/@sha256:[0-9a-f]*//; s/, empreinte .*//' | paste -sd' ')"; done
      attendu "date de la base dans la ligne BASE du 24/11" "$(jl "$j" | sed -n 's/^BASE|\([0-9-]*\).*/\1/p')" 2026-11-24
      pod=$(kubectl get pods -n scan -l job-name="$j" -o jsonpath='{.items[0].metadata.name}')
      attendu "lignes du pod $pod dans Grafana (Loki) = kubectl logs" "$(q "sum(count_over_time({espace=\"scan\", pod=\"$pod\"} [3h]))" "$now")" "$(jl "$j" | wc -l)"
    fi ;;
  compteurs_23)
    pi() { # expr PromQL, heure ISO : valeurs instantanées
      g "$(jq -nc --arg q "$1" --arg t "$(date -ud "$2" +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:$q,instant:true}]}')" \
        | jq -r '[.results.A.frames[]? | .data.values[1][0]? | select(. != null) | tostring] | if length == 0 then "aucune série" else join(",") end'
    }
    for x in 'sum(watcher_pipelinerun_signing_failures_total)' 'sum(watcher_taskrun_signing_failures_total)' \
             'sum(kyverno_admission_requests_total{request_allowed="false"})' 'count(up == 1)'; do
      v0=$(pi "$x" 2026-11-23T06:40:00Z); echo "$x : 06:40 $v0"
      for t in 08:36 08:50 09:30; do attendu "$x, $t = 06:40" "$(pi "$x" "2026-11-23T${t}:00Z")" "$v0"; done
    done ;;
  fins_23)
    pj() { # expr PromQL, heure ISO, filtre jq sur [{l, v}]
      g "$(jq -nc --arg q "$1" --arg t "$(date -ud "$2" +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:$q,instant:true}]}')" \
        | jq -r "[.results.A.frames[]? | select((.data.values | length) > 1) | {l: (.schema.fields[1].labels // {}), v: .data.values[1][0]}] | $3"
    }
    for t in 08:37 08:40 08:45; do
      echo "dernier échantillon de chaque alerte déclenchée, vu à $t :"
      pj 'max by (alertname) (timestamp(ALERTS{alertstate="firing"}))' "2026-11-23T${t}:00Z" \
        'if length == 0 then "  aucune" else .[] | "  \(.l.alertname) \(.v | floor | todate)" end'
    done
    for t in 08:25 08:30 08:33 08:35 08:36; do
      for x in 'count(watcher_taskrun_signing_failures_total)' 'count(watcher_pipelinerun_signing_failures_total)' \
               'count(kyverno_admission_requests_total{request_allowed="false"})'; do
        echo "$x à $t : $(pj "$x" "2026-11-23T${t}:00Z" 'if length == 0 then "aucune série" else map(.v | tostring) | join(",") end')"
      done
    done
    echo "cibles de CollecteEnPanne, vues à 07:30 :"
    pj 'ALERTS{alertname="CollecteEnPanne"}' 2026-11-23T07:30:00Z '.[] | "  \(.l.job) \(.l.instance)"'
    echo "dernier échantillon de up (toutes cibles), vu à 08:34 : $(pj 'max(timestamp(up))' 2026-11-23T08:34:00Z '.[0].v | floor | todate')"
    echo "dernier échantillon de up{job=\"prometheus\"}, vu à 08:37 : $(pj 'timestamp(up{job="prometheus"})' 2026-11-23T08:37:00Z '.[0].v | floor | todate')" ;;
esac
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$e" = alertes_23 ] || [ "$e" = fins_23 ]; then echo "bilan : relevé fait"; elif [ "$ko" = 0 ]; then echo "bilan : tenue"; else echo "bilan : KO"; fi
exit "$ko"
} 2>&1 | tee "$L"
exit "${PIPESTATUS[0]}"
