#!/usr/bin/env bash
# Brique 19b, correction du constat du 24/11/2026 : liste du proxy des sources de Grafana (data_source_proxy_whitelist), éprouvée au banc
# (poc/bricks/20-kpi/banc-grafana.sh, VARIANTE=liste). ÉCRIT À SEC, RIEN DE POSÉ. Tant que config/grafana.ini ne porte pas la ligne, pose refuse.
# JAMAIS de requête vers un chemin qui agit (/ingester/shutdown, /flush, /log_level) sur la plateforme : /loki/api/v1/status/buildinfo seulement.
#   avant    lecture seule, auditeur : le proxy mène-t-il à Loki et à Prometheus ? (code HTTP)
#   pose     ACCORD DU PROPRIÉTAIRE (sudo sur sc-stockage) : seule la ligne de liste est ajoutée à /etc/grafana/grafana.ini, copie gardée,
#            refus si le reste diffère du dépôt ; Grafana redémarré ; s'il ne revient pas, copie remise et arrêt ; contrôles.
#   apres    lecture seule, auditeur : proxy vers Loki refusé, vers Prometheus permis, requêtes et explorateur inchangés.
#   retrait  ACCORD DU PROPRIÉTAIRE (sudo) : copie remise, Grafana redémarré.
# Usage (racine du dépôt) : bash poc/bricks/19b-journalisation/liste-proxy.sh <étape> > <journal>
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
O8=$HOME/.cache/supply-chain-poc/08
CA=$O8/pki/ca-poc.crt GRAF=https://192.168.161.13:3001
LIGNE='data_source_proxy_whitelist = 127.0.0.1:9090'
SSH_OPTS=(-i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
sur() { env -u SSH_AUTH_SOCK ssh "${SSH_OPTS[@]}" poc@192.168.161.13 "$@"; }
ko=0
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }
auditeur() { # méthode chemin [corps] : code HTTP, réponse dans R
  local d=(); [ -z "${3:-}" ] || d=(-d "$3")
  R=$(printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$CA" -w '\n%{http_code}' -X "$1" -H 'Content-Type: application/json' "${d[@]}" "$GRAF$2")
  C=${R##*$'\n'}; R=${R%$'\n'*}
}
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ), étape ${1:-?}, dépôt $(git -C "$here" rev-parse --short=8 HEAD)"
controles() { # code attendu du proxy vers Loki
  auditeur GET /api/datasources/proxy/uid/loki/loki/api/v1/status/buildinfo; attendu "proxy vers Loki (buildinfo)" "$C" "$1"
  auditeur GET /api/datasources/proxy/uid/prometheus/api/v1/rules; attendu "proxy vers Prometheus (règles)" "$C" 200
  auditeur POST /api/ds/query '{"queries":[{"refId":"A","datasource":{"uid":"loki"},"expr":"sum(count_over_time({source=\"journal\"}[5m]))","queryType":"instant"}],"from":"now-5m","to":"now"}'
  attendu "requête Loki par /api/ds/query, trames non vides" "$C $(jq '[.results.A.frames[]? | select((.data.values | length) > 1)] | length > 0' <<< "$R")" "200 true"
  auditeur POST /api/ds/query '{"queries":[{"refId":"A","datasource":{"uid":"prometheus"},"expr":"up","instant":true}],"from":"now-5m","to":"now"}'
  attendu "requête Prometheus par /api/ds/query" "$C" 200
  auditeur GET "/api/datasources/uid/loki/resources/labels"; attendu "étiquettes de l'explorateur" "$C $(jq -r '.data | index("source") != null' <<< "$R")" "200 true"
}
etape_avant() { controles 200; return $ko; }
etape_apres() { controles 403; return $ko; }
etape_pose() { # ACCORD DU PROPRIÉTAIRE
  attendu "ligne dans le dépôt" "$(grep -cx "$LIGNE" "$here/config/grafana.ini")" 1
  [ "$ko" = 0 ] || return 1
  local sans; sans=$(grep -vx "$LIGNE" "$here/config/grafana.ini" | sha256sum | cut -c1-64)
  attendu "grafana.ini en service = dépôt sans la ligne" "$(sur "sudo sha256sum /etc/grafana/grafana.ini" | cut -c1-64)" "$sans"
  [ "$ko" = 0 ] || return 1
  sur "cat > /tmp/grafana-liste.ini" < "$here/config/grafana.ini" || return 1
  sur "sudo bash -s" <<'EOS'
set -euo pipefail
trap 'find /tmp/grafana-liste.ini -delete' EXIT
cp -p /etc/grafana/grafana.ini /etc/grafana/grafana.ini.avant-liste
install -m 0640 -g grafana /tmp/grafana-liste.ini /etc/grafana/grafana.ini
vivant() { for i in $(seq 30); do curl -fs -o /dev/null --cacert /etc/grafana/tls/ca-poc.crt https://192.168.161.13:3001/api/health && return 0; sleep 2; done; return 1; }
if ! systemctl restart grafana || ! vivant; then
  echo "Grafana ne revient pas : copie remise"
  cp -p /etc/grafana/grafana.ini.avant-liste /etc/grafana/grafana.ini
  systemctl restart grafana && vivant && echo "Grafana revenu avec la copie"
  exit 3
fi
EOS
  attendu "pose" "$?" 0
  [ "$ko" = 0 ] || return 1
  attendu "Grafana actif" "$(sur "systemctl is-active grafana")" active
  attendu "grafana.ini en service = dépôt" "$(sur "sudo sha256sum /etc/grafana/grafana.ini" | cut -c1-64)" "$(sha256sum < "$here/config/grafana.ini" | cut -c1-64)"
  controles 403
  return $ko
}
etape_retrait() { # ACCORD DU PROPRIÉTAIRE
  sur "sudo bash -s" <<'EOS'
set -euo pipefail
test -e /etc/grafana/grafana.ini.avant-liste
install -m 0640 -g grafana /etc/grafana/grafana.ini.avant-liste /etc/grafana/grafana.ini
systemctl restart grafana
for i in $(seq 30); do curl -fs -o /dev/null --cacert /etc/grafana/tls/ca-poc.crt https://192.168.161.13:3001/api/health && exit 0; sleep 2; done
exit 3
EOS
  attendu "retrait" "$?" 0
  return $ko
}
case ${1:-} in avant|pose|apres|retrait) ;; *) echo "usage : $0 avant|pose|apres|retrait" >&2; exit 2 ;; esac
rc=0
"etape_$1" || rc=$?
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ), bilan : $([ "$rc" = 0 ] && echo tenu || echo KO)"
exit "$rc"
