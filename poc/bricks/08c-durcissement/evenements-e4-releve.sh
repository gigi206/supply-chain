#!/usr/bin/env bash
# Chantier des Events, suite d'E4 : passage en lecture seule des requêtes d'evenements-loki.sh sur le vrai Loki (accord du propriétaire,
# « 2 ok », 10/11/2026). Prédictions V0 à V9 : resultats/mesures-reelles-predictions.md, additif du 10/11/2026 à 08:35 UTC, écrites avant.
#   e4_releve  témoins positifs des filtres (scan du 10/11 à 09:30 UTC, pods de Cilium du 06/11), R1 rejoué, délai du témoin E3 et
#              hypothèse du rattrapage (trois essais), comptes affichés des quatre requêtes depuis le dernier démarrage d'Alloy.
# Effets : requêtes de l'auditeur à travers Grafana (lecture), un systemctl show par ssh sur sc-stockage. Rien n'est écrit dans le cluster,
# Loki, Grafana ni les VM ; aucune lecture par kubectl. Les réponses de Grafana ne sont jamais archivées, le champ msg n'est jamais affiché.
#
# Usage (racine du dépôt, après 09:35 UTC) : DISTRO=rke2 mise exec -- poc/bricks/08c-durcissement/evenements-e4-releve.sh e4_releve
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
b08=$here/../08-trust-plane
. "$b08/commun.sh"
. "$here/evenements-loki.sh"
ko=0

# compte nom libellé requête début fin attendu (>=N, N, ou - pour affiché seulement)
compte() {
  local de a
  de=$(date -ud "$4" +%s); a=$(date -ud "$5" +%s)
  echo "## $1, $2"
  echo "  fenêtre : $4 à $5 ; requête : $3"
  ev_requete "$3" "$de" "$a" "$EV_MAXL"
  if [ "$ev_etat" = erreur ]; then echo "KO   $1 : requête en erreur ($ev_err)"; ko=1; return 0; fi
  echo "  lignes : $ev_n$([ "$ev_etat" = tronque ] && echo ' (au moins, réponse tronquée)' || true)"
  if [ "$ev_n" -gt 0 ]; then
    echo "  première : $(head -1 "$EV_T/lignes" | cut -f1), dernière : $(tail -1 "$EV_T/lignes" | cut -f1)"
    ev_resume
  fi
  case $6 in
    -) echo "     $1 : affiché, non jugé" ;;
    '>='*) if [ "$ev_n" -ge "${6#>=}" ]; then echo "OK   $1 : $ev_n (attendu : $6)"; else echo "KO   $1 : $ev_n (attendu : $6)"; ko=1; fi ;;
    *) if [ "$ev_n" = "$6" ]; then echo "OK   $1 : $ev_n (attendu : $6)"; else echo "KO   $1 : $ev_n (attendu : $6)"; ko=1; fi ;;
  esac
}

# Un essai du témoin E3 : délai jusqu'à la première ligne evenements-k8s horodatée après l'instant de départ (interrogée toutes les 2 s,
# 120 s au plus), puis hypothèse du rattrapage : la fenêtre des 120 s qui précèdent le départ, comptée dès le témoin vu puis 30 s après,
# ne doit pas grossir (une ligne arrivée après le témoin la réfuterait pour cet essai).
temoin() { # n° de l'essai
  local tc v n1 n2 i
  tc=$(date -u +%s)
  for ((i = 0; i < 60; i++)); do
    ev_requete '{source="evenements-k8s"}' "$tc" "$(($(date -u +%s) + 1))" 1
    if [ "$ev_etat" = erreur ]; then echo "KO   témoin $1 : requête en erreur ($ev_err)"; ko=1; return 0; fi
    if [ "$ev_n" -ge 1 ]; then break; fi
    sleep 2
  done
  if [ "$ev_n" -lt 1 ]; then echo "KO   témoin $1 : aucune ligne en 120 s"; ko=1; return 0; fi
  v=$(date -u +%s)
  ev_requete '{source="evenements-k8s"}' "$((tc - 120))" "$tc" "$EV_MAXL"; n1=$ev_n
  sleep 30
  ev_requete '{source="evenements-k8s"}' "$((tc - 120))" "$tc" "$EV_MAXL"; n2=$ev_n
  echo "  témoin $1 : départ $(date -ud "@$tc" +%H:%M:%S), vu après $((v - tc)) s ; 120 s d'avant : $n1 lignes au témoin, $n2 lignes 30 s après"
  if [ $((v - tc)) -le 75 ]; then echo "OK   témoin $1 : délai $((v - tc)) s (attendu : au plus 75 s)"; else echo "KO   témoin $1 : délai $((v - tc)) s (attendu : au plus 75 s)"; ko=1; fi
  if [ "$n2" = "$n1" ]; then echo "OK   rattrapage $1 : fenêtre d'avant inchangée ($n1)"
  else echo "KO   rattrapage $1 : fenêtre d'avant passée de $n1 à $n2 lignes après le témoin : hypothèse réfutée pour cet essai"; ko=1; fi
}

etape_e4_releve() {
  local d fin
  EV_T=$W/ev-loki-releve
  rm -rf -- "${EV_T:?}" && (umask 077 && mkdir -p "$EV_T")
  trap 'rm -rf -- "$W/ev-loki-releve"' EXIT   # réponses de Grafana jamais archivées
  [ -r "$S/grafana-auditeur.password" ] || { echo "KO   mot de passe de l'auditeur absent : rien lu"; return 1; }
  fin=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  d=$(ev_alloy_debut)
  [ -n "$d" ] || { echo "KO   démarrage d'Alloy illisible sur sc-stockage : rien lu"; return 1; }
  echo "## V0, démarrage d'Alloy de sc-stockage : $(date -ud "@$d" +%Y-%m-%dT%H:%M:%SZ) (prédit : 2026-11-09T17:05:19Z) ; lecture à $fin"
  if [ "$(date -ud "@$d" +%Y-%m-%dT%H:%M:%SZ)" = 2026-11-09T17:05:19Z ]; then echo "OK   V0"; else echo "KO   V0"; ko=1; fi

  compte V1 "témoin positif de EV_CRONJOB_SCAN, passage du scan du 10/11" "$EV_CRONJOB_SCAN" 2026-11-10T09:30:00Z 2026-11-10T09:35:00Z '>=1'
  compte V2 "toutes les lignes de l'espace scan, même fenêtre" '{source="evenements-k8s", namespace="scan"}' \
    2026-11-10T09:30:00Z 2026-11-10T09:35:00Z -
  compte V3 "témoin positif des filtres kind et name de EV_PULLING_CILIUM (sans reason)" \
    '{source="evenements-k8s", namespace="kube-system"} | json | kind="Pod" | name=~"cilium.*"' 2026-11-06T11:00:00Z 2026-11-07T11:22:39Z '>=1'
  compte V4 "EV_PULLING_CILIUM, même fenêtre (R8 non jugé le 09/11)" "$EV_PULLING_CILIUM" 2026-11-06T11:00:00Z 2026-11-07T11:22:39Z 0
  compte V5 "EV_PV, fenêtre de R1 rejouée" "$EV_PV" 2026-11-06T16:49:02Z 2026-11-06T16:53:29Z '>=32'
  for c in EV_PV EV_FAILEDCREATE EV_CRONJOB_SCAN EV_PULLING_CILIUM; do
    compte "V6 $c" "depuis le démarrage d'Alloy" "${!c}" "$(date -ud "@$d" +%Y-%m-%dT%H:%M:%SZ)" "$fin" -
  done
  echo "## V7 à V9, témoin E3 et hypothèse du rattrapage, trois essais"
  temoin 1; temoin 2; temoin 3
  echo "## bilan : $([ "$ko" = 0 ] && echo 'toutes les prédictions jugées tenues' || echo 'au moins une prédiction non tenue')"
  return $ko
}

lancer evenements events "$@"
