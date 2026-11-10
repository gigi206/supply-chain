#!/usr/bin/env bash
# Chantier des Events dans Loki, ouvert à part de la 08c (close) : décisions E1 à E4 des Events et prédictions R1 à R8 dans
# resultats/mesures-reelles-predictions.md (additifs de 11:05 et 13:11 UTC le 09/11/2026, et suivants). Lecture seule.
#   releve  R1 à R8 sur les fenêtres déjà archivées (E4 (a)) : lignes {source="evenements-k8s"} lues par l'auditeur à travers Grafana,
#           témoin passif E3 (b) par fenêtre (une ligne evenements-k8s, démarrage d'Alloy lu par ssh sur sc-stockage), comptes de kubectl
#           archivés affichés (E1 (a)) ; n'écrit rien dans le cluster, Loki, Grafana ni les VM ; accord du propriétaire avant tout passage
#   diagnostic (a) dernière ligne evenements-k8s ; (b) journal de sc-stockage dans la fenêtre de R6 ; (c) lignes du composant des Events dans
#           le journal d'alloy.service (classe d'erreur seulement) ; (d) santé et position du composant, API locale d'Alloy lue par ssh ;
#           lecture seule, rien redémarré ; accord du propriétaire (« Oui, (a) à (d) », 09/11/2026)
#   classe  relecture de (c) seule (accord : « Oui, relis la classe »)
#   redemarrage systemctl restart alloy sur sc-stockage, démarrage relevé avant et après (accord : « Oui, redémarre Alloy »)
#   verification lecture seule, après redemarrage : lignes evenements-k8s, journal du composant, santé et position
#   essai_alerte à sec sur sc-stockage, dans /tmp/essai-evenements retiré ensuite : promtool check et test de alertes.yml (19) avec
#           EvenementsMuets, alloy validate de la configuration de sc-stockage (19b) avec le compteur, et deux témoins négatifs qui
#           doivent être refusés (règle sans la branche absent, attribut inconnu dans metric.counter) ; aucun service touché (accord)
#   appliquer_alloy evenements.alloy avec le compteur posé sur sc-stockage (copie de sauvegarde, validation sur copie, SIGHUP, retour
#           arrière si le compteur n'apparaît pas), puis porte : série vue par Prometheus et expression de EvenementsMuets vide (accord)
#   boot    lecture seule par ssh (accord : « 1 oui », 10/11/2026) : journal d'alloy.service de sc-stockage, boot courant jusqu'à
#           FIN_BOOT (UTC) ; comptes par motif dans les lignes du composant des Events, premières et dernières heures, aucune ligne brute
#   appliquer_regles observabilite.sh deployer (alertes.yml, redémarrage de Prometheus), puis état de la règle : saine, inactive (accord)
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
loki_lignes() { # requête depuis jusqu'à (RFC 3339) [sens : forward ou backward] [maxLines]
  local q c de a s=${4:-forward} m=${5:-$MAXL}
  de=$(date -ud "$2" +%s)000
  a=$(date -ud "$3" +%s)000
  q=$(jq -nc --arg e "$1" --arg de "$de" --arg a "$a" --argjson m "$m" --arg s "$s" \
    '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: $m, direction: $s}], from: $de, to: $a}')
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
  if [ "$n" -ge "$m" ]; then etat=tronque; else etat=ok; fi
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

# Lignes logfmt d'Alloy réduites à : horodatage, level, msg, component_id, err (guillemets échappés compris, 300 caractères) et sa classe
# reconnue ; si la ligne entière contient jeton ou token, err n'est pas affichée, seulement sa classe. Corrigé le 09/11/2026 après le
# diagnostic de 16:32 UTC : l'extraction s'arrêtait au premier guillemet échappé de err, et le masque ne portait que sur ce début.
classes() {
  local CL='Unauthorized|Forbidden|connection refused|no such host|i/o timeout|deadline exceeded|x509[^"]*|EOF|context canceled|no route to host|TLS handshake[^"]*|certificate[^"]*|permission denied|server misbehaving|service unavailable'
  while IFS=$'\t' read -r h l; do
    lv=$(grep -o -E 'level=[a-z]+' <<< "$l" | head -1 || true)
    ms=$(grep -o -E 'msg="[^"]*"' <<< "$l" | head -1 || true)
    ci=$(grep -o -E 'component_id=[^ ]+' <<< "$l" | head -1 || true)
    er=$(grep -o -E 'err="([^"\\]|\\.)*"' <<< "$l" | head -1 || true)
    cl=$(grep -o -i -E "$CL" <<< "$er" | sort -u | paste -sd, - || true)
    if [ -n "$er" ] && grep -q -i -E 'jeton|token' <<< "$l"; then er="err masquée par le filtre des secrets"; else er=${er:0:300}; fi
    [ -n "$cl" ] && er="$er ; classe : $cl"
    [ -z "$cl" ] && [ -n "$er" ] && er="$er ; classe : non reconnue"
    printf '%s %s %s %s %s\n' "${h:0:16}" "$lv" "$ms" "$ci" "$er"
  done < "$T/lignes"
}

etape_diagnostic() {
  local fin d0=2026-11-06T16:53:29Z da=2026-11-07T11:00:00Z r
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/evenements"' EXIT   # réponses de Grafana et de l'API d'Alloy jamais archivées
  fin=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "## (a) dernière ligne {source=\"evenements-k8s\"} entre $d0 et $fin (sens backward, maxLines 1)"
  loki_lignes '{source="evenements-k8s"}' "$d0" "$fin" backward 1
  case $etat in
    erreur) echo "NJ   (a) : requête en erreur" ;;
    *) if [ "$n" = 0 ]; then echo "  (a) : aucune ligne après $d0"
       else echo "  (a) : dernière ligne à $(tail -1 "$T/lignes" | cut -f1)"; tail -1 "$T/lignes" > "$T/l1" && mv "$T/l1" "$T/lignes"; resume 1; fi ;;
  esac
  loki_lignes '{source="evenements-k8s"}' 2026-11-07T11:22:39Z "$fin"
  echo "  (a) lignes evenements-k8s depuis le démarrage d'Alloy (07/11, 11:22:39) : $n$([ "$etat" = tronque ] && echo " (au moins)")$([ "$etat" = erreur ] && echo " (requête en erreur)")"
  echo "## (b) Alloy écrit-il encore dans Loki ? fenêtre de R6 (09/11, 09:30:00 à 09:35:00), comptes seulement (MESSAGE non affiché)"
  loki_lignes '{noeud="sc-stockage", source="journal"}' 2026-11-09T09:30:00Z 2026-11-09T09:35:00Z
  echo "  (b) lignes du journal de sc-stockage : $n ($etat)"
  loki_lignes '{source="evenements-k8s"}' 2026-11-09T09:30:00Z 2026-11-09T09:35:00Z
  echo "  (b) lignes evenements-k8s, même fenêtre : $n ($etat)"
  echo "## (c) journal d'alloy.service de sc-stockage depuis $da, lignes du composant des Events"
  loki_lignes '{noeud="sc-stockage", unite="alloy.service"}' "$da" "$fin"
  echo "  (c) lignes d'alloy.service depuis $da : $n ($etat)"
  loki_lignes '{noeud="sc-stockage", unite="alloy.service"} |~ "kubernetes_events|evenements|informer|event watcher|non-Event"' "$da" "$fin"
  echo "  (c) lignes du composant des Events : $n ($etat)"
  [ "$n" -gt 0 ] && classes | uniq -c -f1 | head -40 | sed 's/^ */    /'
  echo "## (d) composant loki.source.kubernetes_events.evenements, API locale d'Alloy (127.0.0.1:12345) lue par ssh sur sc-stockage"
  if r=$(sur sc-stockage "curl -fsS http://127.0.0.1:12345/api/v0/web/components/loki.source.kubernetes_events.evenements" </dev/null 2>"$T/ssh.err"); then
    printf '%s' "$r" > "$T/composant.json"
    jq -r '"  (d) santé : \(.health.state // "-"), \(.health.message // "-"), depuis \(.health.updatedTime // "-")"' "$T/composant.json" | grep -v -i -E 'jeton|token' || true
    echo "  (d) état de débogage (namespace, last_event_timestamp) :"
    jq -c '.debugInfo // "absent"' "$T/composant.json" | grep -v -i -E 'jeton|token' | sed 's/^/    /' || true
    echo "  (d) heure de la VM au moment de la lecture : $(sur sc-stockage 'date -u +%Y-%m-%dT%H:%M:%SZ' </dev/null)"
  else
    echo "NJ   (d) : lecture impossible ($(grep -o -i -E 'Connection refused|Failed to connect|404|not found|timed out' "$T/ssh.err" | head -1 || true))"
  fi
  date -u '+fin du diagnostic %H:%M:%S UTC'
}

etape_classe() { # relecture de (c) seule : classe de l'erreur du composant des Events au démarrage du 07/11 (accord à part)
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/evenements"' EXIT
  echo "## (c) relue : journal d'alloy.service de sc-stockage, composant des Events, 07/11 de 11:00 à 12:00"
  loki_lignes '{noeud="sc-stockage", unite="alloy.service"} |~ "kubernetes_events|evenements|informer|event watcher|non-Event"' \
    2026-11-07T11:00:00Z 2026-11-07T12:00:00Z
  echo "  lignes : $n ($etat)"
  [ "$n" -gt 0 ] && classes | uniq -c -f1 | head -40 | sed 's/^ */    /'
  date -u '+fin de la relecture %H:%M:%S UTC'
}

alloy_debut() { sur sc-stockage "systemctl show -p ActiveEnterTimestamp --value alloy" </dev/null; }

etape_redemarrage() { # modification de sc-stockage, accord du propriétaire (« Oui, redémarre Alloy », 09/11/2026)
  local a0 a1 t
  a0=$(alloy_debut)
  [ -n "$a0" ] || { echo "KO   démarrage d'Alloy illisible : rien redémarré"; return 1; }
  echo "## avant : Alloy actif depuis $(date -ud "$a0" +%Y-%m-%dT%H:%M:%SZ)"
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "## systemctl restart alloy sur sc-stockage, demandé à $t"
  sur sc-stockage "sudo systemctl restart alloy" </dev/null
  a1=$(alloy_debut)
  echo "## après : Alloy actif depuis $(date -ud "$a1" +%Y-%m-%dT%H:%M:%SZ), $(sur sc-stockage 'systemctl is-active alloy' </dev/null || true)"
  if [ "$(date -ud "$a1" +%s)" -gt "$(date -ud "$a0" +%s)" ]; then echo "OK   Alloy redémarré"; else echo "KO   Alloy non redémarré"; return 1; fi
}

etape_verification() { # lecture seule, quelques minutes après redemarrage
  local d de fin r v=0
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/evenements"' EXIT
  fin=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  d=$(date -ud "$(alloy_debut)" +%Y-%m-%dT%H:%M:%SZ)
  de=$(date -ud "$d - 65 minutes" +%Y-%m-%dT%H:%M:%SZ)
  echo "## Alloy actif depuis $d ; lecture à $fin"
  echo "## journal d'alloy.service, composant des Events, depuis $d"
  loki_lignes '{noeud="sc-stockage", unite="alloy.service"} |~ "kubernetes_events|evenements|informer|event watcher|non-Event"' "$d" "$fin"
  echo "  lignes : $n ($etat)"
  [ "$n" -gt 0 ] && classes | uniq -c -f1 | head -40 | sed 's/^ */    /'
  if [ "$etat" = ok ] && grep -q 'watching events for namespace' "$T/lignes" && ! grep -q -E 'event watcher exited with error|failed to start informers' "$T/lignes"
  then echo "OK   observateur démarré, sans erreur"; else echo "KO   observateur : démarrage absent ou en erreur ($etat)"; v=1; fi
  echo "## lignes evenements-k8s de $de (démarrage − 65 min) à $fin"
  loki_lignes '{source="evenements-k8s"}' "$de" "$fin"
  echo "  lignes : $n ($etat)$([ "$n" -gt 0 ] && echo ", première $(head -1 "$T/lignes" | cut -f1), dernière $(tail -1 "$T/lignes" | cut -f1)")"
  [ "$n" -gt 0 ] && resume 10
  if [ "$etat" != erreur ] && [ "$n" -ge 1 ]; then echo "OK   lignes d'Events reçues"; else echo "KO   aucune ligne d'Event ($etat)"; v=1; fi
  loki_lignes '{source="evenements-k8s"}' "$d" "$fin"
  echo "  dont horodatées après le démarrage (affiché, non jugé) : $n ($etat)"
  echo "## composant, API locale d'Alloy"
  if r=$(sur sc-stockage "curl -fsS http://127.0.0.1:12345/api/v0/web/components/loki.source.kubernetes_events.evenements" </dev/null 2>/dev/null); then
    printf '%s' "$r" > "$T/composant.json"
    jq -r '"  santé : \(.health.state // "-"), \(.health.message // "-"), depuis \(.health.updatedTime // "-")"' "$T/composant.json" | grep -v -i -E 'jeton|token' || true
    jq -c '.debugInfo // "absent"' "$T/composant.json" | grep -v -i -E 'jeton|token' | sed 's/^/  /' || true
  else echo "  lecture de l'API d'Alloy impossible"; fi
  [ "$v" = 0 ] && echo "## bilan : collecte des Events rétablie" || echo "## bilan : collecte non rétablie"
  return $v
}

etape_essai_alerte() { # à sec sur sc-stockage, accord à part ; deux témoins négatifs : un « valide » ne vaut que si un cas faux est refusé
  local d=$W/essai-alerte rg=$here/../19-observabilite/config/regles c=$here/../19b-journalisation/config/alloy
  rm -rf -- "${d:?}" && mkdir -p "$d"
  cp "$rg/alertes.yml" "$rg/alertes-tests.yml" "$c/commun"/*.alloy "$c/stockage"/*.alloy "$d/"
  [ "$DISTRO" = k3s ] || cp "$here/../08b-rke2/config/alloy/journaux-rke2.alloy" "$d/"   # même jeu que journalisation.sh installer
  # Témoins : règle sans la branche absent (le cas « compteur absent, up = 1 » doit échouer) ; attribut inconnu dans metric.counter.
  python3 -I - "$d" <<'PY'
import sys
d = sys.argv[1]
def muter(src, dst, avant, apres):
    t = open(f"{d}/{src}", encoding="utf-8").read()
    assert t.count(avant) == 1, f"motif absent ou multiple dans {src}"
    open(f"{d}/{dst}", "w", encoding="utf-8").write(t.replace(avant, apres))
muter("alertes.yml", "alertes.yml.faux",
      ' or (absent(loki_process_custom_evenements_lignes_total{job="alloy"}) and on() (up{job="alloy"} == 1))', '')
muter("evenements.alloy", "evenements.alloy.faux", '      action            = "inc"\n',
      '      action            = "inc"\n      inconnu           = "x"\n')
PY
  echo "## fichiers essayés : $(cd "$d" && ls | paste -sd' ' -)"
  echo "## sha256 de evenements.alloy : $(sha256sum "$d/evenements.alloy" | cut -c1-64) ; de alertes.yml : $(sha256sum "$d/alertes.yml" | cut -c1-64)"
  copier sc-stockage /tmp/essai-evenements "$d"/*
  rm -rf -- "${d:?}"
  sur sc-stockage 'cd /tmp/essai-evenements || exit 1; r=0
promtool --version | head -1
if promtool check rules alertes.yml && promtool test rules alertes-tests.yml; then echo "règles : vérifiées, tests passés"; else echo "règles : échec"; r=1; fi
mkdir faux-regles && cp alertes-tests.yml faux-regles/ && mv alertes.yml.faux faux-regles/alertes.yml
o=$(cd faux-regles && promtool test rules alertes-tests.yml 2>&1); v=$?
if [ "$v" != 0 ] && [ "$(printf "%s\n" "$o" | grep -c "alertname:")" = 1 ] && printf "%s\n" "$o" | grep -q "alertname: EvenementsMuets, time: 6m,"
then echo "témoin promtool (règle sans absent) : refusé sur le seul cas de 6 min, attendu"
else echo "témoin promtool (règle sans absent) : pas le refus attendu (code $v)"; printf "%s\n" "$o" | grep "alertname:"; r=1; fi
mkdir config && mv ./*.alloy config/ && o=$(/usr/local/bin/alloy validate config 2>&1); v=$?; printf "%s\n" "$o" | tail -5
if [ "$v" = 0 ]; then echo "configuration valide"; else echo "configuration refusée (code $v)"; r=1; fi
mkdir faux-alloy && cp config/*.alloy faux-alloy/ && mv evenements.alloy.faux faux-alloy/evenements.alloy
o=$(/usr/local/bin/alloy validate faux-alloy 2>&1); v=$?
if [ "$v" != 0 ] && printf "%s\n" "$o" | grep -q "unrecognized attribute name \"inconnu\""; then echo "témoin alloy (attribut inconnu) : refusé, attendu"
else echo "témoin alloy (attribut inconnu) : non refusé (code $v)"; printf "%s\n" "$o" | tail -5; r=1; fi
cd / && rm -rf /tmp/essai-evenements; exit $r' </dev/null
}

prom() { # expression PromQL sans apostrophe : réponse JSON de l'API de Prometheus de sc-stockage (lecture)
  sur sc-stockage "curl -s -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=$1'" </dev/null
}
COMPTEUR=loki_process_custom_evenements_lignes_total
AVANT_A=5fbb0b5~1   # dernier commit avant le remède (a) : versions attendues en place sur sc-stockage avant l'application
avant_a() { git -C "$repo" show "$AVANT_A:poc/bricks/$1" | sha256sum | cut -c1-64; }

etape_appliquer_alloy() { # accord à part : compteur posé dans Alloy de sc-stockage par SIGHUP, retour arrière automatique ;
  # porte de appliquer_regles : série vue par Prometheus (job alloy) et expression de EvenementsMuets vide sur le Prometheus réel
  local c=$here/../19b-journalisation/config/alloy/stockage/evenements.alloy e n i
  e=$(python3 -I - "$here/../19-observabilite/config/regles/alertes.yml" <<'PY'
import re, sys   # yq n'est pas déclaré dans mise.toml : expression lue par la bibliothèque standard, une seule occurrence exigée
m = re.findall(r"^ *- alert: EvenementsMuets\n *expr: (.+)$", open(sys.argv[1], encoding="utf-8").read(), re.M)
assert len(m) == 1, "EvenementsMuets : expression introuvable ou multiple"
print(m[0])
PY
)
  [ -n "$e" ] || { echo "KO   expression de EvenementsMuets introuvable" >&2; return 1; }
  echo "## sha256 de evenements.alloy : $(sha256sum "$c" | cut -c1-64)"
  copier sc-stockage /tmp/alloy-evenements "$c"
  sur sc-stockage sudo bash -s -- "$(avant_a 19b-journalisation/config/alloy/stockage/evenements.alloy)" <<'EOS'
set -euo pipefail
cd /tmp/alloy-evenements
h=$(sha256sum /etc/alloy/config/evenements.alloy | cut -c1-64)
if [ "$h" != "$1" ]; then
  echo "KO   evenements.alloy en place ($h) différent de la version d'avant (a) ($1) : rien modifié"; cd / && rm -rf /tmp/alloy-evenements; exit 1
fi
echo "evenements.alloy en place : version d'avant (a), sha256 $h"
compteur() { curl -s http://127.0.0.1:12345/metrics | grep -c '^loki_process_custom_evenements_lignes_total' || true; }
echo "avant : séries du compteur dans /metrics d'alloy : $(compteur)"
cp -p /etc/alloy/config/evenements.alloy /etc/alloy/evenements.alloy.avant-a   # hors de config/ : alloy charge tous les *.alloy
echo "copie de sauvegarde : /etc/alloy/evenements.alloy.avant-a, sha256 $(sha256sum /etc/alloy/evenements.alloy.avant-a | cut -c1-64)"
mkdir -m 0750 copie && cp /etc/alloy/config/*.alloy copie/ && cp evenements.alloy copie/
# Pas de « validate && echo » : sous set -e, un échec dans une liste && n'arrête pas le script (trouvé par l'essai hors cluster).
if ! /usr/local/bin/alloy validate copie; then echo "KO   configuration d'alloy (copie) refusée : rien modifié"; cd / && rm -rf /tmp/alloy-evenements; exit 1; fi
echo "configuration d'alloy (copie) valide"
pid=$(systemctl show -p MainPID --value alloy)
install -m 0640 -g alloy evenements.alloy /etc/alloy/config/evenements.alloy
cd / && rm -rf /tmp/alloy-evenements
echo "## alloy : nouveau evenements.alloy, rechargement par SIGHUP (pid $pid)"
systemctl kill -s HUP alloy
for i in $(seq 40); do [ "$(compteur)" -gt 0 ] && break; sleep 3; done
if [ "$(compteur)" -eq 0 ]; then
  echo "KO   compteur absent de /metrics d'alloy 120 s après le rechargement : retour arrière"
  install -m 0640 -g alloy /etc/alloy/evenements.alloy.avant-a /etc/alloy/config/evenements.alloy; systemctl kill -s HUP alloy; exit 1
fi
echo "alloy : $(systemctl is-active alloy), pid $(systemctl show -p MainPID --value alloy), compteur dans /metrics après $((i * 3)) s au plus"
EOS
  echo "## composant des Events après rechargement, API locale d'Alloy"
  sur sc-stockage "curl -fsS http://127.0.0.1:12345/api/v0/web/components/loki.source.kubernetes_events.evenements" </dev/null 2>/dev/null \
    | jq -r '"  santé : \(.health.state // "-"), \(.health.message // "-"), depuis \(.health.updatedTime // "-")"' | grep -v -i -E 'jeton|token' || true
  echo "## Prometheus : série du compteur, job alloy (collecte toutes les 30 s), attente jusqu'à 120 s"
  for i in $(seq 24); do
    n=$(prom "count($COMPTEUR{job=\"alloy\"})" | jq -r '.data.result[0].value[1] // "0"')
    [ "$n" != 0 ] && break; sleep 5
  done
  [ "$n" != 0 ] || { echo "KO   série absente de Prometheus après 120 s : règles non déployées"; return 1; }
  prom "$COMPTEUR" | jq -c '.data.result[] | .metric' | sed 's/^/  /'
  echo "## 180 s d'historique avant d'évaluer la règle (increase sur 15 min d'une série neuve)"
  sleep 180
  prom "sum(increase($COMPTEUR{job=\"alloy\"}[15m]))" | jq -r '"  increase sur 15 min : \(.data.result[0].value[1] // "aucun résultat")"'
  echo "## expression de EvenementsMuets sur le Prometheus réel (règle non déployée) : $e"
  n=$(prom "$e" | jq -r 'if .status != "success" then "erreur" else (.data.result | length | tostring) end')
  if [ "$n" = 0 ]; then echo "OK   expression vide : la règle ne sonnerait pas"
  else echo "KO   expression non vide ou en erreur ($n) : règles non déployées"; return 1; fi
}

etape_appliquer_regles() { # accord à part, après appliquer_alloy : observabilite.sh deployer (journal evenements-deployer.log de la 19),
  # puis état de EvenementsMuets lu dans Prometheus et Alertmanager après trois évaluations
  local r h a
  a=$(avant_a 19-observabilite/config/regles/alertes.yml)
  h=$(sur sc-stockage "sudo sha256sum /etc/prometheus/regles/alertes.yml" </dev/null | cut -c1-64)
  [ "$h" = "$a" ] || { echo "KO   alertes.yml en place ($h) différent de la version d'avant (a) ($a) : rien déployé"; return 1; }
  echo "alertes.yml en place : version d'avant (a), sha256 $h"
  JALON=evenements bash "$here/../19-observabilite/observabilite.sh" deployer
  echo "## 90 s (trois évaluations) puis état de EvenementsMuets"
  sleep 90
  r=$(sur sc-stockage "curl -s http://127.0.0.1:9090/api/v1/rules" </dev/null \
    | jq -r '[.data.groups[].rules[] | select(.name == "EvenementsMuets")] | if length == 0 then "absente" else .[0] | "\(.health) \(.state) \(.lastError // "")" end')
  echo "  règle : $r"
  echo "  alertes en cours dans Prometheus : $(sur sc-stockage "curl -s http://127.0.0.1:9090/api/v1/alerts" </dev/null | jq -r '[.data.alerts[] | select(.labels.alertname == "EvenementsMuets") | .state] | length')"
  echo "  alertes dans Alertmanager : $(sur sc-stockage "curl -s http://127.0.0.1:9093/api/v2/alerts" </dev/null | jq -r '[.[] | select(.labels.alertname == "EvenementsMuets")] | length')"
  if [ "${r% }" = "ok inactive" ]; then echo "## bilan : EvenementsMuets déployée, saine, inactive"
  else echo "## bilan : EvenementsMuets pas dans l'état attendu ($r)"; return 1; fi
}

etape_boot() { # lecture seule par ssh : le premier démarrage d'Alloy après le boot a-t-il perdu l'observateur des Events (07/11) ?
  local fin=${FIN_BOOT:?FIN_BOOT requis, heure UTC « AAAA-MM-JJ HH:MM:SS »} m n
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/evenements"' EXIT
  echo "## sc-stockage : système démarré à $(sur sc-stockage 'uptime -s' </dev/null) (heure de la VM : $(sur sc-stockage 'date +%Z' </dev/null))"
  echo "## fenêtre : boot courant (-b 0) jusqu'à $fin UTC, journal d'alloy.service"
  sur sc-stockage "sudo journalctl -u alloy -b 0 --until '$fin UTC' -o short-iso" </dev/null 2>/dev/null | grep -v -i -E 'jeton|token' > "$T/j" || true
  grep -F 'kubernetes_events' "$T/j" > "$T/k" || true
  echo "  lignes dans la fenêtre : $(wc -l < "$T/j"), dont du composant des Events : $(wc -l < "$T/k")"
  n=$(grep -c -E 'Started (alloy\.service|.*[Aa]lloy)' "$T/j" || true)
  echo "  démarrages d'Alloy (Started) : $n$([ "$n" -gt 0 ] && echo ", premier $(grep -E 'Started (alloy\.service|.*[Aa]lloy)' "$T/j" | head -1 | cut -d' ' -f1)")"
  for m in 'watching events for namespace' 'event watcher exited with error' 'failed to configure informers' 'connection refused' 'stopping watcher for events'; do
    n=$(grep -c -F "$m" "$T/k" || true)
    printf '  %-32s %3s' "$m" "$n"
    [ "$n" -gt 0 ] && printf '   première %s, dernière %s' "$(grep -F "$m" "$T/k" | head -1 | cut -d' ' -f1)" "$(grep -F "$m" "$T/k" | tail -1 | cut -d' ' -f1)"
    echo
  done
}

lancer evenements events "$@"
