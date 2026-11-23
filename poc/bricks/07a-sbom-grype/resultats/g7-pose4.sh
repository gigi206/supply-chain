#!/usr/bin/env bash
# Ajout du 23/11/2026 (G7, après le redémarrage de Zot par la pièce 4 de la 07b, 13:21:33 UTC) : début et fin du balayage de
# démarrage de Zot, lus dans Loki à travers Grafana (compte auditeur), par tranches de 10 s ; comptes seuls, aucune ligne archivée.
# Rien sur la VM, rien dans Zot. Même requête que g7-redemarrage-23-11.sh.
# Étapes (une par journal, jamais réécrit) :
#   debut : fenêtre de 13:15 UTC à maintenant, le balayage a-t-il commencé ?
#   fin   : même fenêtre ; refuse si la dernière tranche de gc a moins de 5 min (balayage peut-être en cours).
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/resultats/g7-pose4.sh <debut|fin>  (journal : g7-pose4-<étape>.log)
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
O8=$HOME/.cache/supply-chain-poc/08
e=${1:-}
case "$e" in debut|fin) ;; *) echo "usage : $0 <debut|fin>" >&2; exit 2;; esac
L=$here/g7-pose4-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
rq() { # expr Loki (compte par tranche de 10 s), début, fin (ISO) ; sortie brute : lignes « epoch_ms compte » des tranches non nulles
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query \
      -d "$(jq -nc --arg q "$1" --arg f "$(date -ud "$2" +%s)000" --arg t "$(date -ud "$3" +%s)000" '{from:$f,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"range",step:"10s",intervalMs:10000,maxLines:1}]}')" \
    | jq -r 'if .results.A.error then "erreur \(.results.A.error)" else
        .results.A.frames[]? | select((.data.values | length) > 1) | [.data.values[0], .data.values[1]] | transpose[] | select(.[1] > 0) | "\(.[0]) \(.[1])" end'
}
resume() { # sortie brute de rq -> phrase
  awk 'BEGIN{n=0} /^erreur/{print; e=1; exit} {if(!n)a=$1; b=$1; s+=$2; n++} END{if(e)exit; if(!n){print "aucune"; exit}
       printf "de %s à %s, %d lignes, %d tranches de 10 s\n", strftime("%Y-%m-%dT%H:%M:%SZ", a/1000, 1), strftime("%Y-%m-%dT%H:%M:%SZ", b/1000, 1), s, n}'
}
Z='{noeud="sc-stockage", source="journal", unite="zot.service"}'
d=2026-11-23T13:15:00Z
f=$(date -u +%Y-%m-%dT%H:%M:00Z)
exec > "$L" 2>&1
echo "# g7-pose4.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; Loki à travers Grafana, tranches de 10 s (heure de la tranche)"
echo "== fenêtre $d -> $f"
gc=$(rq "sum(count_over_time($Z |= \"executing gc of orphaned blobs\" [10s]))" "$d" "$f")
echo "  gc (executing gc of orphaned blobs) : $(printf '%s\n' "$gc" | sed '/^$/d' | resume)"
echo "  rétention (retention, sans casse)   : $(rq "sum(count_over_time($Z |~ \"(?i)retention\" [10s]))" "$d" "$f" | sed '/^$/d' | resume)"
echo "  démarrage (starting|listening|config) : $(rq "sum(count_over_time($Z |~ \"(?i)starting|listening|config\" [10s]))" "$d" "$f" | sed '/^$/d' | resume)"
echo "  toutes les lignes de zot.service    : $(rq "sum(count_over_time($Z [10s]))" "$d" "$f" | sed '/^$/d' | resume)"
ko=0
if [ "$e" = fin ]; then
  der=$(printf '%s\n' "$gc" | sed '/^$/d' | tail -1 | cut -d' ' -f1)
  if [ -z "$der" ] || ! [[ $der =~ ^[0-9]+$ ]]; then echo "KO   aucune tranche de gc lisible"; ko=1
  else
    age=$(( $(date -u +%s) - der / 1000 ))
    echo "  dernière tranche de gc il y a ${age} s"
    [ "$age" -ge 300 ] || { echo "KO   dernière tranche de gc il y a moins de 5 min : balayage peut-être en cours"; ko=1; }
  fi
fi
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$ko" = 0 ] && echo "bilan : relevé fait" || echo "bilan : KO"
