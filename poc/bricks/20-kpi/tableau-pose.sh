#!/usr/bin/env bash
# Brique 20, étape 6 : pose du tableau « KPI supply-chain » dans le Grafana de sc-stockage, repris de 07a-sbom-grype/tableau-pose.sh.
# Fichier : 19b-journalisation/config/provisioning/dashboards/tableaux/kpi-supply-chain.json, mesuré au banc jetable (tableau-banc.sh,
# promql-banc.sh) ; le fournisseur tableaux.yaml est déjà posé (ADR 0004) et n'est pas touché. Étapes :
#   sec       lecture seule, par l'auditeur, sans ssh : tableau absent de Grafana, « Vulnérabilités et VEX » servi, chaque requête des
#             panneaux jouée sur le vrai Prometheus par /api/ds/query (séries comptées, valeurs archivées, pas de secret). Sans accord.
#   pose      ACCORD DU PROPRIÉTAIRE (sudo sur sc-stockage, changement de configuration de Grafana) : fichier installé (0640, groupe
#             grafana), puis POST /api/admin/provisioning/dashboards/reload par l'administrateur (pas de redémarrage).
#   controle  lecture seule, par l'auditeur : tableau servi, provisionné, 18 panneaux identiques au fichier ; enregistrement refusé ;
#             « Vulnérabilités et VEX » toujours servi ; requêtes jouées comme en sec.
#   retrait   ACCORD DU PROPRIÉTAIRE (sudo) : fichier retiré, rechargement. disableDeletion garde le tableau dans la base de Grafana :
#             non exercé, l'effet est relevé, pas supposé.
# Identifiants passés à curl par sa configuration sur l'entrée standard (-K -), jamais en argument.
# Usage (racine du dépôt) : bash poc/bricks/20-kpi/tableau-pose.sh <étape> > <journal>
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
C19=$here/../19b-journalisation/config/provisioning/dashboards
O8=$HOME/.cache/supply-chain-poc/08
CA=$O8/pki/ca-poc.crt
GRAF=https://192.168.161.13:3001
SSH_OPTS=(-i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
sur() { env -u SSH_AUTH_SOCK ssh "${SSH_OPTS[@]}" poc@192.168.161.13 "$@"; }   # sc-stockage
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
T=$HOME/.cache/supply-chain-poc/20/tableau-pose   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/tableau-pose ] || find ~/.cache/supply-chain-poc/20/tableau-pose -delete
mkdir -p "$T"
trap 'find ~/.cache/supply-chain-poc/20/tableau-pose -delete' EXIT
graf() { # compte méthode chemin [fichier-corps] : code HTTP, réponse dans $T/r.json
  local c=$1 m=$2 u=$3
  printf 'user = "%s:%s"\n' "$c" "$(cat "$O8/secrets/grafana-$c.password")" \
    | curl -sS -K - --cacert "$CA" -o "$T/r.json" -w '%{http_code}' -X "$m" -H 'Content-Type: application/json' "$GRAF$u" ${4:+-d @"$4"}
}
echo "# tableau « KPI supply-chain », étape ${1:-?}, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
echo "tableau $(sha256sum < "$C19/tableaux/kpi-supply-chain.json" | cut -c1-16)…, script $(sha256sum < "$0" | cut -c1-16)"

TAB=$C19/tableaux/kpi-supply-chain.json

requetes() { # chaque cible de chaque panneau ; nombre de séries attendu écrit dans resultats/e6-predictions.md (24/11/2026)
  local id q n a t c
  echo "## requêtes des panneaux, jouées par l'auditeur ($(date -u +%FT%TZ))"
  while IFS=$'\t' read -r id q; do
    t=$(date -u +%s)000
    jq -nc --arg q "$q" --arg t "$t" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:$q,instant:true,range:false}]}' > "$T/q.json"
    c=$(graf auditeur POST /api/ds/query "$T/q.json")
    n=$(jq -r '[.results.A.frames[]? | select((.data.values | length) > 1)] | length' "$T/r.json")
    a=$(awk -v i="$id" '$1 == i {print $2}' <<<"$SERIES")
    attendu "panneau $id : code, séries, erreur" "$c $n $(jq -r '.results.A.error // "aucune"' "$T/r.json")" "200 ${a:-?} aucune"
    [ "$n" -gt 8 ] || jq -r '.results.A.frames[]? | select((.data.values | length) > 1) | "       \(.schema.fields[1].labels // {} | del(.job, .instance, .__name__) | to_entries | map(.value) | join(" ")) = \(.data.values[1][0])"' "$T/r.json"
  done < <(jq -r '.panels[] | .id as $i | (.targets // [])[] | "\($i)\(.refId)\t\(.expr)"' "$TAB")
}
# nombre de séries par requête : 4 digests, 3 scannés, 5 clés, 24 pins distincts, 0 KEV ; relevé du 24/11/2026, à revoir après un rejeu ou une reconstruction
SERIES='2A 1
2B 1
3A 1
3B 1
3C 1
3D 1
3E 1
4A 1
4B 1
4C 1
5A 1
5B 1
5C 1
6A 1
6B 1
6C 1
7A 4
8A 4
9A 4
10A 3
11A 3
12A 1
12B 1
13A 0
14A 0
15A 5
16A 4
17A 4
18A 24'

etape_sec() {
  attendu "tableau absent de Grafana (auditeur)" "$(graf auditeur GET /api/dashboards/uid/kpi-supply-chain)" 404
  attendu "« Vulnérabilités et VEX » servi (auditeur)" "$(graf auditeur GET /api/dashboards/uid/vulnerabilites-vex)" 200
  requetes
}

etape_pose() { # ACCORD DU PROPRIÉTAIRE
  : "${ACCORD:?accord du propriétaire requis (changement de configuration de Grafana)}"
  echo "accord du propriétaire (verbatim) : « $ACCORD »"
  sur "if [ -e /tmp/tableau-pose ]; then find /tmp/tableau-pose -delete; fi; mkdir -m 0700 /tmp/tableau-pose" </dev/null || return 1
  env -u SSH_AUTH_SOCK scp -q "${SSH_OPTS[@]}" "$TAB" poc@192.168.161.13:/tmp/tableau-pose/ </dev/null || return 1
  sur "sudo bash -s" <<'EOS' || return 1
set -euo pipefail
trap 'if [ -e /tmp/tableau-pose ]; then find /tmp/tableau-pose -delete; fi' EXIT
test -d /etc/grafana/provisioning/dashboards/tableaux
install -m 0640 -g grafana /tmp/tableau-pose/kpi-supply-chain.json /etc/grafana/provisioning/dashboards/tableaux/kpi-supply-chain.json
EOS
  attendu "fichier posé identique" "$(sur "sudo sha256sum /etc/grafana/provisioning/dashboards/tableaux/kpi-supply-chain.json" </dev/null | cut -c1-64)" "$(sha256sum < "$TAB" | cut -c1-64)"
  attendu "rechargement du provisionnement (administrateur)" "$(graf admin POST /api/admin/provisioning/dashboards/reload)" 200
  echo "  réponse : $(jq -c . "$T/r.json")"
  etape_controle
}

etape_controle() {
  # cache des droits de l'utilisateur : voir 07a-sbom-grype/tableau-pose.sh, passage pose-1
  attendu "cache des droits de l'auditeur rechargé" "$(graf auditeur GET '/api/access-control/user/permissions?reloadcache=true')" 200
  attendu "tableau servi (auditeur)" "$(graf auditeur GET /api/dashboards/uid/kpi-supply-chain)" 200
  cp "$T/r.json" "$T/tableau.json"
  attendu "titre" "$(jq -r .dashboard.title "$T/tableau.json")" "KPI supply-chain"
  attendu "dossier" "$(jq -r .meta.folderTitle "$T/tableau.json")" PoC
  attendu "marqué provisionné" "$(jq -r .meta.provisioned "$T/tableau.json")" true
  attendu "panneaux" "$(jq '.dashboard.panels | length' "$T/tableau.json")" 18
  attendu "panneaux identiques au fichier" "$(jq -S -c '[.dashboard.panels[] | {id, type, title, targets: [.targets[]?.expr]}]' "$T/tableau.json" | sha256sum | cut -c1-16)" \
    "$(jq -S -c '[.panels[] | {id, type, title, targets: [.targets[]?.expr]}]' "$TAB" | sha256sum | cut -c1-16)"
  jq -c '{dashboard: (.dashboard | .title = "modifié"), overwrite: true}' "$T/tableau.json" > "$T/modif.json"
  attendu "enregistrement par l'auditeur refusé" "$(graf auditeur POST /api/dashboards/db "$T/modif.json")" 403
  attendu "« Vulnérabilités et VEX » servi (auditeur)" "$(graf auditeur GET /api/dashboards/uid/vulnerabilites-vex)" 200
  requetes
}

etape_retrait() { # ACCORD DU PROPRIÉTAIRE
  : "${ACCORD:?accord du propriétaire requis}"
  sur "sudo find /etc/grafana/provisioning/dashboards/tableaux/kpi-supply-chain.json -delete" </dev/null || return 1
  attendu "rechargement (administrateur)" "$(graf admin POST /api/admin/provisioning/dashboards/reload)" 200
  echo "MESURE|tableau après retrait du fichier|HTTP $(graf auditeur GET /api/dashboards/uid/kpi-supply-chain)"
}

case "${1:-}" in
  sec|pose|controle|retrait) "etape_$1" ;;
  *) echo "étape inconnue : ${1:-} (sec | pose | controle | retrait)"; exit 2 ;;
esac
echo "## bilan : $N cas, $KO écart(s)"
[ "$KO" = 0 ]
