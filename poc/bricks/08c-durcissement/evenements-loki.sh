# shellcheck shell=bash disable=SC2034
# (SC2034 : EV_PV, EV_N, EV_SOURCE et les autres EV_ sont lus par les scripts qui chargent ce fichier.)
# Chantier des Events (brique 08c), suite d'E4 : lecture dans Loki pour les six contrôles qui attendaient 0 Events lus par kubectl
# (preuves.sh resolveurs_pod, scan_saut_suspendre, scan_saut_reprendre deux fois, durcissement.sh h2_releve, cilium.sh verifier).
# Décisions E1 (a), E2, E3 (b) et E4 (a), et règle de verdict : resultats/mesures-reelles-predictions.md, additif du 09/11/2026 à 23:23 UTC.
# À charger après commun.sh de la 08 (S, P, W, O, IP, SSH_OPTS). N'installe aucun trap ; n'écrit que dans $W/ev-loki, retiré à chaque appel.
# La lecture de Loki à travers Grafana reprend celle d'evenements.sh, laissé inchangé (empreinte de ses passages archivés).
#
# Règle de verdict (lecture d'E1 (a) pour les cas que la décision ne tranche pas) : Loki ne décide que s'il peut juger.
#   - au moins une ligne dans Loki (réponse tronquée comprise) : le compte de Loki décide, donc KO ;
#   - 0 ligne, témoin E3 vu, kubectl 0 : verdict de Loki, OK ;
#   - 0 ligne, témoin vu, kubectl au moins 1 : une ligne manque à Loki, qui ne juge donc pas : le compte de kubectl décide, KO ;
#   - Loki non jugé (témoin absent, Alloy démarré dans la fenêtre ou démarrage illisible, requête en erreur, mot de passe absent) :
#     le compte de kubectl décide, comme avant le chantier.
# Le script appelant garde son attendu ou ba_attendu sur EV_N : sa façon de traiter un KO ne change pas.

EV_GRAFANA=${EV_GRAFANA:-https://192.168.161.13:3001}
EV_ATTENTE=${EV_ATTENTE:-120}   # attente du témoin, en secondes
EV_PAS=${EV_PAS:-10}            # intervalle entre deux interrogations du témoin
EV_MAXL=1000                    # maxLines du compte : une réponse qui l'atteint compte au moins 1000 lignes
# Requêtes de R1 à R8 (evenements.sh), telles quelles ; seule la forme de EV_PV a rendu des lignes réelles (R1, 09/11/2026).
EV_PV='{source="evenements-k8s"} | json | reason="PolicyViolation"'
EV_FAILEDCREATE='{source="evenements-k8s"} | json | reason="FailedCreate"'
EV_CRONJOB_SCAN='{source="evenements-k8s", namespace="scan"} | json | kind="CronJob"'
EV_PULLING_CILIUM='{source="evenements-k8s", namespace="kube-system"} | json | kind="Pod" | reason="Pulling" | name=~"cilium.*"'

# Requête de plage à travers Grafana (auditeur, lecture seule). Arguments : requête, début et fin en secondes Unix, maxLines.
# Pose ev_etat (ok, tronque, erreur), ev_err et ev_n ; lignes « horodatage<TAB>ligne » dans $EV_T/lignes, triées.
ev_requete() {
  local q c=000
  ev_n=0; ev_err=""; ev_etat=erreur
  : > "$EV_T/lignes"
  q=$(jq -nc --arg e "$1" --arg de "${2}000" --arg a "${3}000" --argjson m "$4" \
    '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: $m, direction: "forward"}], from: $de, to: $a}')
  c=$(printf 'user = "auditeur:%s"\n' "$(cat "$S/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$P/ca-poc.crt" --connect-timeout 5 --max-time 30 -o "$EV_T/reponse.json" -w '%{http_code}' \
      -X POST -H 'Content-Type: application/json' "$EV_GRAFANA/api/ds/query" -d "$q" 2>/dev/null) || c=${c:-000}
  if [ "$c" != 200 ]; then ev_err="HTTP $c"; return 0; fi
  if ! jq -e . "$EV_T/reponse.json" >/dev/null 2>&1; then ev_err="réponse illisible"; return 0; fi
  if jq -e '.results.A.error // empty' "$EV_T/reponse.json" >/dev/null 2>&1; then
    ev_err="erreur de Loki : $(jq -r '.results.A.error' "$EV_T/reponse.json" | head -c 200 | grep -v -i -E 'jeton|token' || true)"; return 0
  fi
  jq -r '.results.A.frames[]? | .data.values as $v | range(0; ($v[2] // []) | length) | "\($v[1][.] / 1000 | floor | todate)\t\($v[2][.])"' \
    "$EV_T/reponse.json" | sort > "$EV_T/lignes" || { ev_err="lignes illisibles"; return 0; }
  ev_n=$(grep -c . "$EV_T/lignes" || true)
  if [ "$ev_n" -ge "$4" ]; then ev_etat=tronque; else ev_etat=ok; fi
  return 0
}

# Dernier démarrage d'Alloy de sc-stockage en secondes Unix, vide s'il est illisible (service absent, VM injoignable).
ev_alloy_debut() {
  local a
  a=$(ssh "${SSH_OPTS[@]}" -o ConnectTimeout=10 "poc@${IP[sc-stockage]}" "systemctl show -p ActiveEnterTimestamp --value alloy" \
    </dev/null 2>/dev/null) || a=""
  [ -n "$a" ] && date -ud "$a" +%s 2>/dev/null || true
}

# Résumé des lignes sans le champ msg : kind, name, reason, count (E2 : des lignes, pas des Events).
ev_resume() {
  cut -f2- "$EV_T/lignes" | jq -R -r 'fromjson? // empty | "\(.kind // "-") \(.name // "-") \(.reason // "-") count=\(.count // "-")"' \
    | sort | uniq -c | sort -rn | head -10 | grep -v -i -E 'jeton|token' | sed 's/^ */    /' || true
}

# ev_juge libellé requête début(RFC 3339) compte-kubectl : pose EV_N (le compte qui décide) et EV_SOURCE (d'où il vient).
# À appeler hors de $(…), puis : attendu "libellé ($EV_SOURCE)" "$EV_N" 0.
ev_juge() {
  local lib=$1 req=$2 nk=$4 de="" tc vu="" fin d0="" d1="" raison="" nl=0 tr="" i
  EV_N=$nk; EV_SOURCE=""
  tc=$(date -u +%s)
  echo "## $lib : Loki (E1 (a)) depuis $3, kubectl : ${nk:-vide}"
  de=$(date -ud "$3" +%s 2>/dev/null) || de=""
  if [ -z "$de" ]; then raison="début de fenêtre illisible ($3)"
  elif [ ! -r "$S/grafana-auditeur.password" ]; then raison="mot de passe de l'auditeur absent"
  else
    d0=$(ev_alloy_debut)
    if [ -z "$d0" ]; then raison="démarrage d'Alloy illisible sur sc-stockage"
    elif [ "$d0" -ge "$de" ]; then raison="Alloy démarré le $(date -ud "@$d0" +%Y-%m-%dT%H:%M:%SZ), après le début de la fenêtre"
    fi
  fi
  if [ -z "$raison" ]; then
    EV_T=$W/ev-loki
    rm -rf -- "${EV_T:?}" && (umask 077 && mkdir -p "$EV_T")
    # E3 (b) : une ligne evenements-k8s horodatée après l'instant du contrôle montre que la collecte l'a dépassé
    for ((i = 0; ; i++)); do
      ev_requete '{source="evenements-k8s"}' "$tc" "$(($(date -u +%s) + 1))" 1
      if [ "$ev_etat" = erreur ]; then raison="témoin illisible ($ev_err)"; break; fi
      if [ "$ev_n" -ge 1 ]; then vu=$(date -u +%s); break; fi
      if [ "$i" -ge $((EV_ATTENTE / EV_PAS)) ]; then raison="aucune ligne evenements-k8s dans les $EV_ATTENTE s qui suivent le contrôle"; break; fi
      sleep "$EV_PAS"
    done
    [ -n "$vu" ] && echo "  E3 : ligne evenements-k8s postérieure au contrôle vue après $((vu - tc)) s"
    fin=${vu:-$(date -u +%s)}
    # compte : toute ligne trouvée compte, témoin ou non
    ev_requete "$req" "$de" "$((fin + 1))" "$EV_MAXL"
    if [ "$ev_etat" = erreur ]; then
      [ -n "$raison" ] || raison="compte illisible ($ev_err)"
    else
      nl=$ev_n; [ "$ev_etat" = tronque ] && tr=" au moins"
      echo "  Loki : $nl ligne(s)$tr de $(date -ud "@$de" +%H:%M:%S) à $(date -ud "@$fin" +%H:%M:%S) UTC ; requête : $req"
      [ "$nl" -gt 0 ] && ev_resume
      if [ -z "$raison" ]; then
        d1=$(ev_alloy_debut)
        [ "$d1" = "$d0" ] || raison="démarrage d'Alloy changé pendant la lecture (${d1:-illisible})"
      fi
    fi
    rm -rf -- "${EV_T:?}"
  fi
  if [ "$nl" -gt 0 ]; then
    EV_N=$nl; EV_SOURCE="Loki, $nl ligne(s)$tr"
  elif [ -n "$raison" ]; then
    EV_SOURCE="kubectl, Loki non jugé : $raison"
  elif [ "$nk" != 0 ]; then
    EV_SOURCE="kubectl, ${nk:-vide} absent(s) de Loki, qui ne juge donc pas cette fenêtre"
  else
    EV_N=0; EV_SOURCE="Loki, témoin E3 vu, kubectl 0"
  fi
  return 0
}
