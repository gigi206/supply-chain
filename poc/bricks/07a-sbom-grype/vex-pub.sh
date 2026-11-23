#!/usr/bin/env bash
# Brique 07b, tranche 3, pièce 5 réduite : clé publique VEX (resultats/vex-cle-publique.pem) ajoutée à la ConfigMap scan-config de
# l'espace scan, par la fonction cm_scan de plateforme.sh (seule source de la ConfigMap), sans rien d'autre. Écrit le 23/11/2026
# sur accord du propriétaire (« Oui » à « Je pose la pièce 5 de la 07b (vex.pub dans scan-config) ? »). Le reste de la pièce 5
# (scanner.sh neuf, rendu des deux CronJob, pod d'essai de cosign) suit la pièce 3, pas avant le 29/11 : tant que scanner.sh
# n'a pas changé, la clé est montée mais lue par personne.
#   releve   lecture seule : clés de scan-config et empreintes, comparées aux fichiers du dépôt ; resourceVersion des deux CronJob ;
#            Jobs de scan actifs
#   pose     refuse de 09:00 à 10:00 et de 11:00 à 11:45 UTC (passages de 09:30 et 11:15) et si un Job de scan est actif ; refuse
#            si scan-config diffère du dépôt ou porte déjà vex.pub ; appelle cm_scan (texte de la fonction lu dans plateforme.sh),
#            puis relit : quatre clés, les trois anciennes inchangées, vex.pub égale au fichier (empreinte et SPKI), CronJob non
#            touchés
#   grafana  l'auditeur relit dans Loki, à travers Grafana, l'audit de l'API (source audit-k8s) : écritures de scan-config sur
#            15 min, comptées par verbe et par utilisateur ; comptes seuls, aucune ligne brute
#   grafana_plage  (ajout du 23/11/2026, après la panne de sc-stockage de 06:40 à la relance) même relecture sur une plage
#            fixe, de 08:15:00 à 08:21:00 UTC le 23/11 (pose à 08:16:00), au lieu des 15 dernières minutes
#   scan_0930  (ajout du 23/11/2026, après la pose) lecture seule du premier passage de scan-sample-app avec vex.pub montée
#            (job du 23/11 à 09:30 UTC) : job réussi, ConfigMap montée entière, scan-config inchangée depuis la pose ; préfixes
#            des lignes du journal égaux à ceux du passage du 22/11 ; vulnérabilités et base relevées des deux jours (information) ;
#            lignes du pod dans Loki, à travers Grafana, égales à celles de kubectl logs (comptes seuls)
#   scan_1115  (ajout du 23/11/2026, après scan_0930) même relecture pour le premier passage de scan-sample-app-deb avec vex.pub
#            montée (job du 23/11 à 11:15 UTC), comparé au passage du 22/11 à 11:15
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/vex-pub.sh <étape>   (journal : resultats/vex-pub-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=$HOME/.cache/supply-chain-poc
P=$O/08/pki
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
CLE=$R/vex-cle-publique.pem
SPKI_ATTENDU=2b81df72314a72e85276ce55aa6625306b47ab37e2c9e2a28878ce374b9df1a9
e=${1:-}
case $e in releve|pose|grafana|grafana_plage|scan_0930|scan_1115) ;; *) echo "usage : $0 releve | pose | grafana | grafana_plage | scan_0930 | scan_1115" >&2; exit 64 ;; esac
L=$R/vex-pub-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
ko=0
ok() { echo "OK   $*"; }
attendu() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }
h() { sha256sum | cut -c1-16; }
cm_cle() { kubectl get cm scan-config -n scan -o json | jq -j --arg k "$1" '.data[$k] // empty'; }
cm_cles() { local k; for k in $(kubectl get cm scan-config -n scan -o json | jq -r '.data | keys[]'); do printf '%s %s\n' "$k" "$(cm_cle "$k" | h)"; done; }
fichiers() { printf 'ca-poc.crt %s\nscanner.pub %s\nscanner.sh %s\n' "$(h < "$P/ca-poc.crt")" "$(h < "$R/scanner-cle-publique.pem")" \
  "$(h < "$here/politique/scanner.sh")"; }
crons() { kubectl get cronjob -n scan -o json | jq -r '.items[] | "\(.metadata.name) \(.metadata.resourceVersion) \(.spec.schedule) suspend=\(.spec.suspend)"'; }
actifs() { kubectl get jobs -n scan -o json | jq '[.items[] | select((.status.active // 0) > 0)] | length'; }

{
echo "# vex-pub.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
case $e in
  releve|pose)
    echo "## avant"
    avant=$(cm_cles); echo "$avant" | sed 's/^/  /'
    echo "  fichiers du dépôt :"; fichiers | sed 's/^/    /'
    rv0=$(kubectl get cm scan-config -n scan -o jsonpath='{.metadata.resourceVersion}'); echo "  resourceVersion de scan-config : $rv0"
    c0=$(crons); echo "$c0" | sed 's/^/  CronJob /'
    a=$(actifs); attendu "Jobs de scan actifs" "$a" 0
    attendu "scan-config = fichiers du dépôt (trois clés)" "$avant" "$(fichiers)"
    attendu "clé publique VEX dans le dépôt (fichier, SPKI)" "$(h < "$CLE") $(openssl pkey -pubin -in "$CLE" -outform DER | sha256sum | cut -d' ' -f1)" \
      "79f7eece2f98f442 $SPKI_ATTENDU"
    if [ "$e" = pose ]; then
      [ "$ko" = 0 ] || { echo "KO   relevé non conforme : rien posé"; exit 1; }
      hm=$(date -u +%H%M)
      if { [ "$hm" -ge 0900 ] && [ "$hm" -lt 1000 ]; } || { [ "$hm" -ge 1100 ] && [ "$hm" -lt 1145 ]; }; then
        echo "KO   $hm UTC : fenêtre d'un passage de scan, rien posé"; exit 1; fi
      ok "hors des fenêtres de scan ($hm UTC)"
      echo "## pose : cm_scan de plateforme.sh"
      f=$(awk '/^cm_scan\(\)/,/^}/' "$here/plateforme.sh")
      echo "  texte de cm_scan : $(printf '%s\n' "$f" | h)"
      eval "$f"
      cm_scan 2>&1 | sed 's/^/  /'
      echo "## après"
      apres=$(cm_cles); echo "$apres" | sed 's/^/  /'
      attendu "clés de scan-config" "$(echo "$apres" | cut -d' ' -f1 | paste -sd,)" "ca-poc.crt,scanner.pub,scanner.sh,vex.pub"
      attendu "trois anciennes clés inchangées" "$(echo "$apres" | grep -v '^vex.pub ')" "$avant"
      attendu "vex.pub = fichier (empreinte)" "$(cm_cle vex.pub | h)" 79f7eece2f98f442
      attendu "vex.pub, SPKI" "$(cm_cle vex.pub | openssl pkey -pubin -outform DER | sha256sum | cut -d' ' -f1)" "$SPKI_ATTENDU"
      rv1=$(kubectl get cm scan-config -n scan -o jsonpath='{.metadata.resourceVersion}')
      [ "$rv1" != "$rv0" ] && ok "resourceVersion de scan-config : $rv0 -> $rv1" || { echo "KO   resourceVersion inchangée"; ko=1; }
      echo "  gestionnaires de champs : $(kubectl get cm scan-config -n scan --show-managed-fields -o json | jq -c '[.metadata.managedFields[] | "\(.manager)/\(.operation)"]')"
      attendu "CronJob non touchés" "$(crons)" "$c0"
      attendu "Jobs de scan actifs" "$(actifs)" 0
    else
      attendu "vex.pub absente de scan-config" "$(cm_cle vex.pub | wc -c)" 0
    fi ;;
  grafana|grafana_plage)
    GRAF=https://192.168.161.13:3001
    t0=""; [ "$e" != grafana_plage ] || t0=$(date -ud 2026-11-23T08:21:00Z +%s)
    q() {
      local t body
      t=$(date -u +%s)000
      [ "$e" != grafana_plage ] || t=$(date -ud 2026-11-23T08:21:00Z +%s)000
      body=$(jq -nc --arg q "$1" --arg t "$t" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
      printf 'user = "auditeur:%s"\n' "$(cat "$O/08/secrets/grafana-auditeur.password")" \
        | curl -sS -K - --cacert "$P/ca-poc.crt" -H 'Content-Type: application/json' -X POST "$GRAF/api/ds/query" -d "$body" \
        | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | "\(.schema.fields[1].labels | [.verb // "-", .user_username // "-", .responseStatus_code // "-"] | join("/")) \(.data.values[1][0])"] | if length == 0 then "aucune série" else sort | join(",") end'
    }
    A='{noeud="sc-confiance", source="audit-k8s"} |= "scan-config" | json | objectRef_resource="configmaps" | objectRef_namespace="scan" | objectRef_name="scan-config"'
    w=15m; [ "$e" != grafana_plage ] || w=6m
    echo "fenêtre : $w, jusqu'à $(date -ud "@${t0:-$(date -u +%s)}" +%Y-%m-%dT%H:%M:%SZ)"
    n=$(q "sum by (verb, user_username, responseStatus_code) (count_over_time($A | verb=~\"create|update|patch|delete\" [$w]))")
    echo "écritures de scan-config, par verbe/utilisateur/code : $n"
    case $n in "aucune série") echo "KO   aucune écriture de scan-config dans Grafana"; ko=1 ;; *) ok "écriture de scan-config présente dans Grafana" ;; esac ;;
  scan_0930)
    [ "$(date -u +%Y%m%d%H%M)" -ge 202611230933 ] || { echo "KO   avant 09:33 UTC le 23/11 : rien relevé"; exit 1; }
    jobs_du() { kubectl get jobs -n scan -o json | jq -r --arg d "$1" '.items[] | select(.metadata.ownerReferences[0].name == "scan-sample-app" and .status.startTime == $d) | .metadata.name'; }
    j=$(jobs_du 2026-11-23T09:30:00Z); j0=$(jobs_du 2026-11-22T09:30:00Z)
    echo "job du 23/11 : ${j:-aucun} ; job du 22/11 : ${j0:-aucun}"
    [ -n "$j" ] && [ -n "$j0" ] || { echo "KO   job manquant"; exit 1; }
    attendu "job du 23/11 (réussi/échoué/actif)" "$(kubectl get job "$j" -n scan -o json | jq -r '"\(.status.succeeded // 0)/\(.status.failed // 0)/\(.status.active // 0)"')" 1/0/0
    echo "  durée : $(kubectl get job "$j" -n scan -o json | jq -r '"\(.status.startTime) -> \(.status.completionTime)"')"
    pod=$(kubectl get pods -n scan -l job-name="$j" -o jsonpath='{.items[0].metadata.name}')
    attendu "volume config du pod : scan-config entière (sans items)" "$(kubectl get pod "$pod" -n scan -o json | jq -c '[.spec.volumes[] | select(.configMap.name == "scan-config") | .configMap.items // "entière"]')" '["entière"]'
    attendu "resourceVersion de scan-config (celle de la pose)" "$(kubectl get cm scan-config -n scan -o jsonpath='{.metadata.resourceVersion}')" 8257360
    attendu "clé vex.pub dans scan-config (empreinte)" "$(cm_cle vex.pub | h)" 79f7eece2f98f442
    jl() { kubectl logs -n scan "job/$1" --all-containers 2>&1; }
    pref() { jl "$1" | awk '{ if (tolower($0) ~ /jeton|token/) print "masquée"; else { split($0, a, "|"); print a[1] } }' | sort | paste -sd,; }
    p=$(pref "$j"); p0=$(pref "$j0"); echo "  préfixes du 23/11 : $p"
    attendu "préfixes des lignes du journal, triés (23/11 = 22/11)" "$p" "$p0"
    for x in "$j0" "$j"; do echo "  $x : $(jl "$x" | grep -E '^(BASE|SCAN)\|' | sed 's/@sha256:[0-9a-f]*//; s/, empreinte .*//' | paste -sd' ')"; done
    nl=$(jl "$j" | wc -l)
    GRAF=https://192.168.161.13:3001
    body=$(jq -nc --arg q "sum(count_over_time({espace=\"scan\", pod=\"$pod\"} [3h]))" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
    nk=$(printf 'user = "auditeur:%s"\n' "$(cat "$O/08/secrets/grafana-auditeur.password")" \
      | curl -sS -K - --cacert "$P/ca-poc.crt" -H 'Content-Type: application/json' -X POST "$GRAF/api/ds/query" -d "$body" \
      | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end')
    attendu "lignes du pod $pod dans Grafana (Loki) = kubectl logs" "$nk" "$nl" ;;
  scan_1115)
    [ "$(date -u +%Y%m%d%H%M)" -ge 202611231118 ] || { echo "KO   avant 11:18 UTC le 23/11 : rien relevé"; exit 1; }
    jobs_du() { kubectl get jobs -n scan -o json | jq -r --arg d "$1" '.items[] | select(.metadata.ownerReferences[0].name == "scan-sample-app-deb" and .status.startTime == $d) | .metadata.name'; }
    j=$(jobs_du 2026-11-23T11:15:00Z); j0=$(jobs_du 2026-11-22T11:15:00Z)
    echo "job du 23/11 : ${j:-aucun} ; job du 22/11 : ${j0:-aucun}"
    [ -n "$j" ] && [ -n "$j0" ] || { echo "KO   job manquant"; exit 1; }
    attendu "job du 23/11 (réussi/échoué/actif)" "$(kubectl get job "$j" -n scan -o json | jq -r '"\(.status.succeeded // 0)/\(.status.failed // 0)/\(.status.active // 0)"')" 1/0/0
    echo "  durée : $(kubectl get job "$j" -n scan -o json | jq -r '"\(.status.startTime) -> \(.status.completionTime)"')"
    pod=$(kubectl get pods -n scan -l job-name="$j" -o jsonpath='{.items[0].metadata.name}')
    attendu "volume config du pod : scan-config entière (sans items)" "$(kubectl get pod "$pod" -n scan -o json | jq -c '[.spec.volumes[] | select(.configMap.name == "scan-config") | .configMap.items // "entière"]')" '["entière"]'
    attendu "resourceVersion de scan-config (celle de la pose)" "$(kubectl get cm scan-config -n scan -o jsonpath='{.metadata.resourceVersion}')" 8257360
    attendu "clé vex.pub dans scan-config (empreinte)" "$(cm_cle vex.pub | h)" 79f7eece2f98f442
    jl() { kubectl logs -n scan "job/$1" --all-containers 2>&1; }
    pref() { jl "$1" | awk '{ if (tolower($0) ~ /jeton|token/) print "masquée"; else { split($0, a, "|"); print a[1] } }' | sort | paste -sd,; }
    p=$(pref "$j"); p0=$(pref "$j0"); echo "  préfixes du 23/11 : $p"
    attendu "préfixes des lignes du journal, triés (23/11 = 22/11)" "$p" "$p0"
    for x in "$j0" "$j"; do echo "  $x : $(jl "$x" | grep -E '^(BASE|SCAN)\|' | sed 's/@sha256:[0-9a-f]*//; s/, empreinte .*//' | paste -sd' ')"; done
    nl=$(jl "$j" | wc -l)
    GRAF=https://192.168.161.13:3001
    body=$(jq -nc --arg q "sum(count_over_time({espace=\"scan\", pod=\"$pod\"} [3h]))" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
    nk=$(printf 'user = "auditeur:%s"\n' "$(cat "$O/08/secrets/grafana-auditeur.password")" \
      | curl -sS -K - --cacert "$P/ca-poc.crt" -H 'Content-Type: application/json' -X POST "$GRAF/api/ds/query" -d "$body" \
      | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end')
    attendu "lignes du pod $pod dans Grafana (Loki) = kubectl logs" "$nk" "$nl" ;;
esac
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
k=$ko; [ "$k" = 0 ] && echo "bilan : tenue" || echo "bilan : KO"
exit "$k"
} 2>&1 | tee "$L"
exit "${PIPESTATUS[0]}"
