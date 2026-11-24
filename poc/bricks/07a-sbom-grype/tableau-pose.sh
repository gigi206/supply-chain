#!/usr/bin/env bash
# Brique 07b, ADR 0004 (« Oui, un tableau ») : pose du tableau « Vulnérabilités et VEX » dans le Grafana de sc-stockage.
# Fichiers : 19b-journalisation/config/provisioning/dashboards/tableaux.yaml (fournisseur) et tableaux/vulnerabilites-vex.json,
# mesurés au banc jetable (tableau-banc.sh). Étapes :
#   sec       lecture seule : répertoire de provisionnement des tableaux sur la VM (sans sudo : 0750 grafana, donc seulement son
#             existence), tableau absent de Grafana (auditeur), empreintes des fichiers. Sans accord.
#   pose      ACCORD DU PROPRIÉTAIRE (sudo sur sc-stockage, changement de configuration de Grafana) : fichiers installés (0640,
#             groupe grafana), puis POST /api/admin/provisioning/dashboards/reload par l'administrateur (pas de redémarrage).
#   controle  lecture seule, par l'auditeur : tableau servi, provisionné, 10 panneaux identiques au fichier ; enregistrement refusé ;
#             chaque requête des panneaux jouée par /api/ds/query (valeurs archivées, pas de secret).
# Identifiants passés à curl par sa configuration sur l'entrée standard (-K -), jamais en argument.
# Usage (racine du dépôt) : bash poc/bricks/07a-sbom-grype/tableau-pose.sh <étape> > <journal>
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
T=$HOME/.cache/supply-chain-poc/07b/tableau-pose   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/07b/tableau-pose ] || find ~/.cache/supply-chain-poc/07b/tableau-pose -delete
mkdir -p "$T"
trap 'find ~/.cache/supply-chain-poc/07b/tableau-pose -delete' EXIT
graf() { # compte méthode chemin [fichier-corps] : code HTTP, réponse dans $T/r.json
  local c=$1 m=$2 u=$3
  printf 'user = "%s:%s"\n' "$c" "$(cat "$O8/secrets/grafana-$c.password")" \
    | curl -sS -K - --cacert "$CA" -o "$T/r.json" -w '%{http_code}' -X "$m" -H 'Content-Type: application/json' "$GRAF$u" ${4:+-d @"$4"}
}
echo "# tableau « Vulnérabilités et VEX », étape ${1:-?}, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
echo "fournisseur $(sha256sum < "$C19/tableaux.yaml" | cut -c1-16)…, tableau $(sha256sum < "$C19/tableaux/vulnerabilites-vex.json" | cut -c1-16)…"

etape_sec() {
  # /etc/grafana est en 0750 (groupe grafana) : sans sudo, son contenu n'est pas visible (passage sec-1) ; seule son existence l'est
  attendu "/etc/grafana sur la VM (droits, groupe)" "$(sur 'stat -c %a:%G /etc/grafana' </dev/null 2>&1)" 750:grafana
  attendu "tableau absent de Grafana (auditeur)" "$(graf auditeur GET /api/dashboards/uid/vulnerabilites-vex)" 404
  attendu "sources de données : Prometheus (uid prometheus)" "$(graf auditeur GET /api/datasources/uid/prometheus; jq -r .type "$T/r.json")" 200prometheus
}

etape_pose() { # ACCORD DU PROPRIÉTAIRE
  : "${ACCORD:?accord du propriétaire requis (changement de configuration de Grafana)}"
  echo "accord du propriétaire (verbatim) : « $ACCORD »"
  sur "if [ -e /tmp/tableau-pose ]; then find /tmp/tableau-pose -delete; fi; mkdir -m 0700 /tmp/tableau-pose" </dev/null || return 1
  env -u SSH_AUTH_SOCK scp -q "${SSH_OPTS[@]}" "$C19/tableaux.yaml" "$C19/tableaux/vulnerabilites-vex.json" poc@192.168.161.13:/tmp/tableau-pose/ </dev/null || return 1
  sur "sudo bash -s" <<'EOS' || return 1
set -euo pipefail
cd /tmp/tableau-pose
install -d -m 0750 -g grafana /etc/grafana/provisioning/dashboards/tableaux
install -m 0640 -g grafana tableaux.yaml /etc/grafana/provisioning/dashboards/tableaux.yaml
install -m 0640 -g grafana vulnerabilites-vex.json /etc/grafana/provisioning/dashboards/tableaux/vulnerabilites-vex.json
cd / && find /tmp/tableau-pose -delete
sha256sum /etc/grafana/provisioning/dashboards/tableaux.yaml /etc/grafana/provisioning/dashboards/tableaux/vulnerabilites-vex.json | cut -c1-16
EOS
  attendu "rechargement du provisionnement (administrateur)" "$(graf admin POST /api/admin/provisioning/dashboards/reload)" 200
  echo "  réponse : $(jq -c . "$T/r.json")"
  etape_controle
}

etape_controle() {
  attendu "tableau servi (auditeur)" "$(graf auditeur GET /api/dashboards/uid/vulnerabilites-vex)" 200
  cp "$T/r.json" "$T/tableau.json"
  attendu "titre" "$(jq -r .dashboard.title "$T/tableau.json")" "Vulnérabilités et VEX"
  attendu "dossier" "$(jq -r .meta.folderTitle "$T/tableau.json")" PoC
  attendu "marqué provisionné" "$(jq -r .meta.provisioned "$T/tableau.json")" true
  attendu "panneaux identiques au fichier" "$(jq -S -c '[.dashboard.panels[] | {id, type, title, targets: [.targets[]?.expr]}]' "$T/tableau.json" | sha256sum | cut -c1-16)" \
    "$(jq -S -c '[.panels[] | {id, type, title, targets: [.targets[]?.expr]}]' "$C19/tableaux/vulnerabilites-vex.json" | sha256sum | cut -c1-16)"
  jq -c '{dashboard: (.dashboard | .title = "modifié"), overwrite: true}' "$T/tableau.json" > "$T/modif.json"
  attendu "enregistrement par l'auditeur refusé" "$(graf auditeur POST /api/dashboards/db "$T/modif.json")" 403
  echo "## requêtes des panneaux, jouées par l'auditeur ($(date -u +%FT%TZ))"
  local q t
  jq -r '.panels[] | select(.targets) | "\(.id)\t\(.targets[0].expr)"' "$C19/tableaux/vulnerabilites-vex.json" | while IFS=$'\t' read -r id q; do
    t=$(date -u +%s)000
    jq -nc --arg q "$q" --arg t "$t" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:$q,instant:true,range:false}]}' > "$T/q.json"
    graf auditeur POST /api/ds/query "$T/q.json" > /dev/null
    echo "  panneau $id : $(jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | "\(.schema.fields[1].labels // {} | [.depot, .gravite] | map(select(.)) | join("/")) = \(.data.values[1][0])"] | join(" ; ")' "$T/r.json")"
  done
}

case "${1:-}" in
  sec|pose|controle) "etape_$1" ;;
  *) echo "étape inconnue : ${1:-} (sec | pose | controle)"; exit 2 ;;
esac
echo "## bilan : $N cas, $KO écart(s)"
[ "$KO" = 0 ]
