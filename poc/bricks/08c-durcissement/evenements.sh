#!/usr/bin/env bash
# Chantier des Events dans Loki, ouvert à part de la 08c (close) : décisions E1 à E4 des Events et prédictions R1 à R8 dans
# resultats/mesures-reelles-predictions.md (additifs de 11:05 et 13:11 UTC le 09/11/2026, et suivants). Lecture seule.
#   releve  R1 à R8 sur les fenêtres déjà archivées (E4 (a)) : lignes {source="evenements-k8s"} lues par l'auditeur à travers Grafana,
#           témoin passif E3 (b) par fenêtre (une ligne evenements-k8s, démarrage d'Alloy lu par ssh sur sc-stockage), comptes de kubectl
#           archivés affichés (E1 (a)) ; n'écrit rien dans le cluster, Loki, Grafana ni les VM ; accord du propriétaire avant tout passage
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08c-durcissement/evenements.sh releve   (journal : resultats/evenements-releve.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
b08=$here/../08-trust-plane
. "$b08/commun.sh"
R08=$b08/resultats
T=$W/evenements
GRAFANA=https://192.168.161.13:3001
MAXL=1000   # maxLines de la requête : une réponse qui l'atteint est tronquée, donc non jugée
ko=0

# Lignes d'Events lues par l'auditeur à travers Grafana, sur une fenêtre bornée des deux côtés (Alloy v1.21.3 horodate chaque ligne
# avec series.lastObservedTime, à défaut lastTimestamp, à défaut eventTime ; source lue au tag, event_controller.go).
# Rend dans $etat : ok, erreur ou tronque ; $n : nombre de lignes ; $T/lignes : « horodatage<TAB>ligne », trié.
loki_lignes() { # requête depuis jusqu'à (RFC 3339)
  local q c de a
  de=$(date -ud "$2" +%s)000
  a=$(date -ud "$3" +%s)000
  q=$(jq -nc --arg e "$1" --arg de "$de" --arg a "$a" --argjson m "$MAXL" \
    '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: $m, direction: "forward"}], from: $de, to: $a}')
  c=$(printf 'user = "auditeur:%s"\n' "$(cat "$S/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$P/ca-poc.crt" -o "$T/reponse.json" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
      "$GRAFANA/api/ds/query" -d "$q") || c=000
  n=0
  : > "$T/lignes"
  if [ "$c" != 200 ]; then etat=erreur; echo "  requête : HTTP $c"; return 0; fi
  if ! jq -e . "$T/reponse.json" >/dev/null 2>&1; then etat=erreur; echo "  requête : réponse illisible"; return 0; fi
  if jq -e '.results.A.error // empty' "$T/reponse.json" >/dev/null; then
    etat=erreur; echo "  requête : erreur de Loki : $(jq -r '.results.A.error' "$T/reponse.json" | head -c 300)"; return 0
  fi
  jq -r '.results.A.frames[]? | .data.values as $v | range(0; ($v[2] // []) | length) | "\($v[1][.] / 1000 | floor | todate)\t\($v[2][.])"' \
    "$T/reponse.json" | sort > "$T/lignes"
  n=$(grep -c . "$T/lignes" || true)
  if [ "$n" -ge "$MAXL" ]; then etat=tronque; else etat=ok; fi
  return 0
}

# Résumé sans le champ msg (les messages ne sont pas archivés) : horodatage, espace absent de la ligne, kind, name, reason, count
resume() {
  cut -f2- "$T/lignes" | jq -R -r 'fromjson? // empty | "\(.kind // "-") \(.name // "-") \(.reason // "-") count=\(.count // "-")"' \
    | sort | uniq -c | sort -rn | head -"${1:-15}" | grep -v -i -E 'jeton|token' | sed 's/^ */    /' || true
}

declare -A V   # verdict par contrôle : OK, KO, NJ (non jugé)
PRE=1          # précondition : R1 et R6 OK (posée après eux)

# E3 (b) : au moins une ligne evenements-k8s dans la fenêtre, et Alloy de sc-stockage non redémarré dans la fenêtre. ActiveEnterTimestamp
# ne donne que le dernier démarrage : une fenêtre qui commence avant lui n'est pas jugeable (additif du 09/11/2026 avant le passage).
temoin_e3() { # depuis jusqu'à : rend 0 si le témoin tient
  local d
  d=$(date -ud "$1" +%s)
  loki_lignes '{source="evenements-k8s"}' "$1" "$2"
  case $etat in
    erreur) echo "  E3 : témoin illisible"; return 1 ;;
    *) [ "$n" -ge 1 ] || { echo "  E3 : aucune ligne evenements-k8s dans la fenêtre"; return 1; }
       echo "  E3 : lignes evenements-k8s dans la fenêtre : $n$([ "$etat" = tronque ] && echo " (au moins)")" ;;
  esac
  if [ "$ALLOY_DEBUT" -ge "$d" ]; then
    echo "  E3 : Alloy démarré le $(date -ud "@$ALLOY_DEBUT" +%Y-%m-%dT%H:%M:%SZ), après le début de la fenêtre : redémarrages antérieurs inconnus"
    return 1
  fi
  echo "  E3 : Alloy démarré avant la fenêtre et pas depuis"
  return 0
}

controle() { # nom libellé requête depuis jusqu'à attendu (0, ou >=N) [fichier archivé] [motif de la lecture par kubectl]
  local nom=$1 lib=$2 req=$3 de=$4 a=$5 att=$6 f=${7:-} m=${8:-} e3=0 ok
  echo "## $nom, $lib"
  echo "  fenêtre : $de à $a ; requête : $req"
  [ -n "$f" ] && echo "  kubectl (archivé, E1) : ${f##*/} : $(grep -F -m1 "$m" "$f" | cut -c1-160 || echo 'ligne introuvable')"
  temoin_e3 "$de" "$a" || e3=1
  loki_lignes "$req" "$de" "$a"
  case $etat in
    erreur)  echo "NJ   $nom : requête en erreur"; V[$nom]=NJ; return 0 ;;
    tronque) echo "NJ   $nom : réponse tronquée à $MAXL lignes"; V[$nom]=NJ; return 0 ;;
  esac
  echo "  lignes (E2 : des lignes, pas des Events) : $n"
  [ "$n" -gt 0 ] && { echo "  première : $(head -1 "$T/lignes" | cut -f1), dernière : $(tail -1 "$T/lignes" | cut -f1)"; resume; }
  if [ "${att#>=}" != "$att" ]; then ok=$([ "$n" -ge "${att#>=}" ] && echo 1 || echo 0); else ok=$([ "$n" = "$att" ] && echo 1 || echo 0); fi
  if [ "${att#>=}" != "$att" ]; then
    # témoin positif : un compte atteint prouve la collecte dans la fenêtre, E3 affiché seulement (additif du 09/11/2026)
    if [ "$ok" = 1 ]; then echo "OK   $nom : $n lignes (attendu : $att)"; V[$nom]=OK
    else echo "KO   $nom : $n lignes (attendu : $att)"; V[$nom]=KO; ko=1; fi
  elif [ "$ok" != 1 ]; then echo "KO   $nom : $n lignes (attendu : $att)"; V[$nom]=KO; ko=1   # une ligne trouvée compte, témoin ou non
  elif [ "$e3" = 1 ]; then echo "NJ   $nom : $n lignes (attendu : $att), témoin E3 absent"; V[$nom]=NJ
  elif [ "$PRE" != 1 ]; then echo "NJ   $nom : $n lignes (attendu : $att), précondition non remplie (R1 ${V[R1]}, R6 ${V[R6]})"; V[$nom]=NJ
  else echo "OK   $nom : $n lignes (attendu : $att)"; V[$nom]=OK
  fi
}

etape_releve() {
  local fin pv='{source="evenements-k8s"} | json | reason="PolicyViolation"' a
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/evenements"' EXIT   # réponses de Grafana jamais archivées
  fin=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  a=$(sur sc-stockage "systemctl show -p ActiveEnterTimestamp --value alloy" </dev/null)
  [ -n "$a" ] || { echo "KO   démarrage d'Alloy illisible sur sc-stockage : relevé arrêté"; return 1; }
  ALLOY_DEBUT=$(date -ud "$a" +%s)
  echo "## Alloy de sc-stockage (affiché, E3) : actif depuis $(date -ud "@$ALLOY_DEBUT" +%Y-%m-%dT%H:%M:%SZ), $(sur sc-stockage 'systemctl is-active alloy' </dev/null || true)"
  echo "  fin des fenêtres ouvertes (R8) : $fin"

  controle R1 "témoin positif de R2 (h2_releve)" "$pv" 2026-11-06T16:49:02Z 2026-11-06T16:53:29Z '>=32' \
    "$here/resultats/durcissement-h2_releve.log" 'événements PolicyViolation depuis H2'
  controle R6 "témoin positif de R5, passage planifié du 09/11" '{source="evenements-k8s", namespace="scan"} | json | kind="CronJob"' \
    2026-11-09T09:30:00Z 2026-11-09T09:35:00Z '>=1'
  # précondition (additif de 13:11 UTC) : si R1 ou R6 n'est pas OK, aucun 0 de R2 à R5, R7 et R8 ne compte (un compte non nul reste KO)
  if [ "${V[R1]}" = OK ] && [ "${V[R6]}" = OK ]; then PRE=1; echo "## précondition remplie : R1 OK, R6 OK"
  else PRE=0; echo "## précondition non remplie : R1 ${V[R1]}, R6 ${V[R6]} ; les 0 de R2 à R5, R7 et R8 sont écrits non jugés"; fi
  controle R2 "durcissement.sh:270, FailedCreate depuis H2" '{source="evenements-k8s"} | json | reason="FailedCreate"' \
    2026-11-06T16:49:02Z 2026-11-06T16:53:29Z 0 "$here/resultats/durcissement-h2_releve.log" 'événements FailedCreate depuis H2'
  controle R3 "preuves.sh:3188 (3184 dans les prédictions), resolveurs_pod" "$pv" 2026-11-07T16:00:56Z 2026-11-07T16:05:56Z 0 \
    "$R08/preuves-h5-resolveurs_pod.log" 'événements PolicyViolation depuis'
  controle R4 "preuves.sh:3242 (3238), scan_saut_suspendre" "$pv" 2026-11-07T16:21:58Z 2026-11-07T16:26:58Z 0 \
    "$R08/preuves-h5-scan_saut_suspendre.log" 'événements PolicyViolation depuis'
  controle R5 "preuves.sh:3302 (3298), CronJob du scan à la reprise" '{source="evenements-k8s", namespace="scan"} | json | kind="CronJob"' \
    2026-11-08T11:40:44Z 2026-11-08T11:45:44Z 0 "$R08/preuves-h5-scan_saut_reprendre.log" 'événements du CronJob du scan'
  controle R7 "preuves.sh:3308 (3304), scan_saut_reprendre" "$pv" 2026-11-08T11:40:44Z 2026-11-08T11:45:44Z 0 \
    "$R08/preuves-h5-scan_saut_reprendre.log" 'événements PolicyViolation depuis'
  controle R8 "cilium.sh:173, Pulling des pods de Cilium" \
    '{source="evenements-k8s", namespace="kube-system"} | json | kind="Pod" | reason="Pulling" | name=~"cilium.*"' \
    2026-11-06T11:00:00Z "$fin" 0 "$R08/cilium-verifier.log" 'événements Pulling des pods de Cilium'   # dernier passage archivé, 06/11 à 13:32:30

  echo "## bilan : $(for c in R1 R2 R3 R4 R5 R6 R7 R8; do printf '%s %s, ' "$c" "${V[$c]}"; done | sed 's/, $//')"
  echo "  ce que R ne prouve pas : verdicts des étapes rejouées avec Loki ; effet d'un redémarrage d'Alloy pendant une étape ; délai"
  echo "  d'ingestion ; Events sans aucun horodatage, écartés par Alloy (1 sur 918 en L4 de la 19b)"
  return $ko
}

lancer evenements events "$@"
