#!/usr/bin/env bash
# Brique 19b (journalisation d'audit dans Grafana, décisions D8 à D12 du propriétaire du 02/11/2026).
# Jalon L1, relevé en lecture seule :
#   telecharger  archives amont épinglées dans ~/.cache/supply-chain-poc/19b/amont : sha256 figés ici ; Alloy et Loki :
#                attestation de release GitHub (gh release verify-asset), mesurée ; Grafana : sha256 publié par Grafana Labs
#                (dl.grafana.com et API grafana.com, concordants au relevé), aucune signature ni attestation de l'archive
#   releve       ressources de sc-stockage ; volume de journald et des journaux de pods sur la dernière heure, par VM et
#                par espace ; événements Kubernetes ; audits existants (k3s, OpenBao, Zot) ; CLA de Grafana Labs
# Jalon L2 (D8, D10, D13 a, D16) : Loki et Grafana sur sc-stockage, en services durcis.
#   certificats  certificats serveur de Loki et de Grafana (CA du PoC) ; certificats clients (mTLS de Loki) : grafana-client,
#                controle (l'hôte, pour les essais) ; mots de passe de l'administrateur et de l'auditeur de Grafana (0600)
#   installer    archives revérifiées dans la VM ; utilisateurs loki et grafana ; configurations, sources de données
#                provisionnées, unités ; mesure du disque (timer disque-metriques, alerte DisqueStockagePlein de la 19) ;
#                compte auditeur (Viewer) de Grafana créé par l'API
#   controle     écoute ; Loki : sans certificat client refusé, avec : ligne témoin écrite puis relue, suppression refusée ;
#                Grafana : anonyme refusé, sources saines, auditeur lit Loki et Prometheus, écritures refusées ; aucune
#                connexion sortante hors du réseau du PoC
# Aucun secret en argument de commande : identifiants passés à curl par sa configuration sur l'entrée standard (-K -).
#
# Usage (racine du dépôt) : mise run journalisation -- <étape>…   (journal : resultats/l1-<étape>.log ; JALON=l2 : l2-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"   # sur, racine, IP, P, S, W, lancer, chrono (R = resultats de la 19b)
A=$HOME/.cache/supply-chain-poc/19b/amont
LOKI_VERSION=3.7.9
LOKI_ARCHIVE=loki-linux-amd64.zip
LOKI_SHA=17a5fae28ce733b3560c27c76620920b169bd2aea9473947b733b511f92e81dd     # SHA256SUMS de v3.7.9, relevé le 02/11/2026
ALLOY_VERSION=1.21.3
ALLOY_ARCHIVE=alloy-linux-amd64.zip
ALLOY_SHA=50d23af2d0f98c00beac6ce9a365693e60f87fb76b6cad6fe1d161e80588af6d    # SHA256SUMS de v1.21.3, relevé le 02/11/2026
GRAFANA_VERSION=13.3.0
GRAFANA_ARCHIVE=grafana_13.3.0_40412481033_linux_amd64.tar.gz
GRAFANA_URL=https://dl.grafana.com/grafana/release/$GRAFANA_VERSION/$GRAFANA_ARCHIVE   # URL donnée par l'API grafana.com
GRAFANA_SHA=cec8f98cc59bc1a1945833b652371a073be678c5c159a9b1695ad63c04fae5a7  # .sha256 de dl.grafana.com et API grafana.com, 02/11/2026
mkdir -p "$A" "$R"

etape_telecharger() {
  [ -s "$A/$LOKI_ARCHIVE" ] || gh release download "v$LOKI_VERSION" -R grafana/loki -p "$LOKI_ARCHIVE" -D "$A"
  [ -s "$A/$ALLOY_ARCHIVE" ] || gh release download "v$ALLOY_VERSION" -R grafana/alloy -p "$ALLOY_ARCHIVE" -D "$A"
  [ -s "$A/$GRAFANA_ARCHIVE" ] || curl -fsSL -o "$A/$GRAFANA_ARCHIVE" "$GRAFANA_URL"
  ls -l "$A" | awk 'NR > 1 {print "  " $5, $9}'
  (cd "$A" && printf '%s  %s\n%s  %s\n%s  %s\n' "$LOKI_SHA" "$LOKI_ARCHIVE" "$ALLOY_SHA" "$ALLOY_ARCHIVE" "$GRAFANA_SHA" "$GRAFANA_ARCHIVE" | sha256sum -c)
  echo "## Grafana : empreinte relue dans l'API grafana.com au moment du téléchargement"
  curl -fsS "https://grafana.com/api/downloads/grafana/versions/$GRAFANA_VERSION" \
    | jq -r --arg u "$GRAFANA_URL" '.packages[] | select(.url == $u) | .sha256' | sed 's/^/  /'
  echo "## attestations de release GitHub (gh release verify-asset)"
  gh release verify-asset "v$ALLOY_VERSION" "$A/$ALLOY_ARCHIVE" -R grafana/alloy 2>&1 | sed 's/^/  alloy : /' || echo "  alloy : ÉCHEC"
  gh release verify-asset "v$LOKI_VERSION" "$A/$LOKI_ARCHIVE" -R grafana/loki 2>&1 | sed 's/^/  loki : /' || echo "  loki : ÉCHEC"
}

etape_releve() {
  local vm t
  t=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%S)
  echo "## sc-stockage : ressources"
  sur sc-stockage "nproc; free -m | sed -n 1,2p; df -h / /var/lib 2>/dev/null | sort -u; sudo du -sh /var/lib/prometheus 2>/dev/null || true"
  echo "## journald, dernière heure (octets de la sortie JSON, lignes ; dix unités les plus bavardes)"
  for vm in sc-confiance sc-build sc-stockage; do
    echo "### $vm"
    sur "$vm" "sudo journalctl --since '1 hour ago' -o json --no-pager | wc -lc; sudo journalctl --disk-usage; \
      sudo journalctl --since '1 hour ago' -o json --no-pager | python3 -c 'import sys, json, collections; c = collections.Counter(); [c.update([(lambda d: d.get(\"_SYSTEMD_UNIT\") or d.get(\"SYSLOG_IDENTIFIER\") or \"?\")(json.loads(l))]) for l in sys.stdin]; [print(f\"{n:8d}  {u}\") for u, n in c.most_common(10)]'"   # jq absent des VM (deuxième passage)
  done
  echo "## journaux de pods depuis $t UTC (lignes CRI horodatées ; octets et lignes par espace, sur chaque nœud)"
  for vm in sc-confiance sc-build; do
    echo "### $vm"
    sur "$vm" "sudo find /var/log/pods -name '*.log' -type f -exec awk -v t='$t' '\$1 >= t { split(FILENAME, p, \"/\"); split(p[5], q, \"_\"); n[q[1]]++; b[q[1]] += length(\$0) + 1 } END { for (k in n) printf \"%10d o %7d lignes  %s\n\", b[k], n[k], k }' {} + | sort -rn; sudo du -sh /var/log/pods"
  done
  echo "## événements Kubernetes"
  kubectl get events -A --no-headers 2>/dev/null | wc -l
  kubectl get events -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -8
  echo "## audits existants"
  echo "### serveur k3s (ligne de commande et configuration)"
  sur sc-confiance "sudo grep -rn audit $D_CONF/ 2>/dev/null || echo '  aucune mention d audit dans $D_CONF'; \
    sudo grep -v '^ *#' $D_CONF/audit-policy.yaml; sudo ls -l $D_ETAT/server/logs/; \
    sudo awk -v t='$t' '\$0 ~ \"requestReceivedTimestamp\" { if (match(\$0, /\"requestReceivedTimestamp\":\"[^\"]*/) && substr(\$0, RSTART + 28, 19) >= t) { n++; b += length(\$0) + 1 } } END { printf \"  dernière heure : %d événements, %d o\\n\", n, b }' $D_ETAT/server/logs/audit.log"
  echo "### OpenBao (devices d'audit)"
  racine <<<'bao audit list -format=json 2>&1 || true'
  kubectl exec -n openbao openbao-0 -- sh -c 'ls -l /openbao/data/audit.log; wc -l < /openbao/data/audit.log; df -h /openbao/data | tail -1'
  echo "### Zot (section log de la configuration)"
  sur sc-stockage "sudo python3 -c 'import json; print(json.dumps(json.load(open(\"/etc/zot/config.json\")).get(\"log\")))'"   # jq absent de la VM (premier passage)
  echo "## CLA de Grafana Labs (fichiers du dépôt, branche par défaut)"
  for r in grafana/grafana grafana/loki grafana/alloy; do
    printf '  %s : ' "$r"
    { curl -fsS "https://api.github.com/repos/$r/contents/CONTRIBUTING.md" | jq -r .content | base64 -d 2>/dev/null; } \
      | grep -o -m1 -E '.{0,60}(\bCLA\b|[Cc]ontributor [Ll]icense [Aa]greement).{0,60}' || echo "aucune mention dans CONTRIBUTING.md (racine)"
  done
  echo "  contrôles de la dernière PR fermée (statut license/cla attendu) :"
  for r in grafana/grafana grafana/loki grafana/alloy; do
    n=$(curl -fsS "https://api.github.com/repos/$r/pulls?state=closed&per_page=1" | jq -r '.[0].number')
    printf '    %s PR %s : %s\n' "$r" "$n" "$(curl -fsS "https://api.github.com/repos/$r/commits/$(curl -fsS "https://api.github.com/repos/$r/pulls/$n" | jq -r .head.sha)/status" | jq -r '[.statuses[].context] | join(", ")')"
  done
  echo "  workflows dont le nom évoque un CLA :"
  for r in grafana/grafana grafana/loki grafana/alloy; do
    printf '    %s : %s\n' "$r" "$(curl -fsS "https://api.github.com/repos/$r/contents/.github/workflows" | jq -r '[.[].name | select(test("cla"; "i"))] | join(", ")')"
  done
}

# ---------------------------------------------------------------------------------------------------------------- L2
HOTE=192.168.161.13
PKI08=$here/../08-trust-plane/stockage/pki.cnf
D=$W/journalisation
trap 'rm -rf "${D:?}" "${W:?}/refus.out"' EXIT   # copies de secrets, même en cas d'échec

cert_serveur() { # nom : certificat serveur de sc-stockage (DNS sc-stockage.poc.test, IP 192.168.161.13), comme certificat() de la 08
  local n=$1
  if [ -s "$S/$n.key" ] && [ -s "$P/$n.crt" ]; then echo "$n : certificat existant"; else
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/$n.key")
    SAN="DNS:sc-stockage.poc.test,IP:$HOTE" openssl req -new -config "$PKI08" -key "$S/$n.key" -subj "/O=supply-chain PoC/CN=sc-stockage.poc.test" -out "$W/$n.csr"
    SAN="DNS:sc-stockage.poc.test,IP:$HOTE" openssl x509 -req -in "$W/$n.csr" -CA "$P/ca-poc.crt" -CAkey "$S/ca-poc.key" -set_serial "0x$(openssl rand -hex 16)" \
      -days 180 -sha256 -extfile "$PKI08" -extensions serveur_poc -out "$P/$n.crt" 2>/dev/null
    rm -f "${W:?}/${n:?}.csr"
  fi
  openssl verify -CAfile "$P/ca-poc.crt" -purpose sslserver "$P/$n.crt"
}
cert_client() { # nom : certificat client <nom>.clients.poc.test (mTLS de Loki, D16)
  local n=$1 c=$here/config/pki-client.cnf
  if [ -s "$S/$n.key" ] && [ -s "$P/$n.crt" ]; then echo "$n : certificat existant"; else
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/$n.key")
    SAN="DNS:$n.clients.poc.test" openssl req -new -config "$c" -key "$S/$n.key" -subj "/O=supply-chain PoC/CN=$n.clients.poc.test" -out "$W/$n.csr"
    SAN="DNS:$n.clients.poc.test" openssl x509 -req -in "$W/$n.csr" -CA "$P/ca-poc.crt" -CAkey "$S/ca-poc.key" -set_serial "0x$(openssl rand -hex 16)" \
      -days 180 -sha256 -extfile "$c" -extensions client_poc -out "$P/$n.crt" 2>/dev/null
    rm -f "${W:?}/${n:?}.csr"
  fi
  openssl verify -CAfile "$P/ca-poc.crt" -purpose sslclient "$P/$n.crt"
}

etape_certificats() {
  cert_serveur loki; cert_serveur grafana
  cert_client grafana-client; cert_client controle
  cert_client loki-interne   # L6 : clients gRPC internes de Loki (grpc_tls_config)
  [ -s "$S/grafana-admin.password" ] || (umask 077 && openssl rand -base64 24 | tr -d '\n' > "$S/grafana-admin.password")
  [ -s "$S/grafana-auditeur.password" ] || (umask 077 && openssl rand -base64 24 | tr -d '\n' > "$S/grafana-auditeur.password")
  stat -c '%a %n' "$S"/grafana-*.password "$S"/loki.key "$S"/grafana*.key "$S"/controle.key | sed "s#$S/##"
}

graf() { # compte méthode chemin [corps-json] : API de Grafana depuis l'hôte ; identifiants par la configuration de curl (entrée standard)
  local c=$1 m=$2 u=$3; shift 3
  printf 'user = "%s:%s"\n' "$c" "$(cat "$S/grafana-$c.password")" \
    | curl -sS -K - --cacert "$P/ca-poc.crt" -o "$W/graf.out" -w '%{http_code}' -X "$m" -H 'Content-Type: application/json' \
      "https://$HOTE:3001$u" ${1:+-d "$1"}
}

etape_installer() {
  [ -s "$P/loki.crt" ] && [ -s "$P/grafana-client.crt" ] && [ -s "$P/loki-interne.crt" ] || { echo "KO   certificats absents (étape certificats)" >&2; exit 1; }
  rm -rf "${D:?}" && (umask 077 && mkdir -p "$D")
  cp "$A/$LOKI_ARCHIVE" "$A/$GRAFANA_ARCHIVE" "$P/ca-poc.crt" "$P/loki.crt" "$S/loki.key" "$P/grafana.crt" "$S/grafana.key" \
     "$P/grafana-client.crt" "$S/grafana-client.key" "$P/loki-interne.crt" "$S/loki-interne.key" "$S/grafana-admin.password" "$here/config/loki.yaml" "$here/config/grafana.ini" \
     "$here/config/provisioning/datasources/sources.yaml" "$here"/systemd/* "$D/"
  copier sc-stockage /tmp/journalisation-installation "$D"/*
  rm -rf "${D:?}"
  sur sc-stockage sudo bash -s <<EOS
set -euo pipefail
cd /tmp/journalisation-installation
printf '%s  %s\n%s  %s\n' "$LOKI_SHA" "$LOKI_ARCHIVE" "$GRAFANA_SHA" "$GRAFANA_ARCHIVE" | sha256sum -c
echo "ports 3001, 3100, 9096 avant installation : \$(ss -ltn | awk '{print \$4}' | grep -cE ':(3001|3100|9096)\$' || true) écoute(s)"
python3 -c 'import zipfile; zipfile.ZipFile("$LOKI_ARCHIVE").extract("loki-linux-amd64")'
for u in loki grafana; do id \$u >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/\$u --no-create-home --shell /usr/sbin/nologin \$u; done
install -m 0755 loki-linux-amd64 /usr/local/bin/loki
[ -d /opt/grafana-$GRAFANA_VERSION ] || tar -xzf "$GRAFANA_ARCHIVE" -C /opt
chown -R root:root /opt/grafana-$GRAFANA_VERSION
install -d -m 0750 -g loki /etc/loki /etc/loki/tls
install -m 0640 -g loki loki.yaml /etc/loki/loki.yaml
install -m 0644 ca-poc.crt loki.crt loki-interne.crt /etc/loki/tls/
install -m 0640 -g loki loki.key loki-interne.key /etc/loki/tls/
install -d -m 0750 -g grafana /etc/grafana /etc/grafana/tls /etc/grafana/secrets /etc/grafana/provisioning /etc/grafana/provisioning/datasources
for d in dashboards plugins alerting; do install -d -m 0750 -g grafana /etc/grafana/provisioning/\$d; done
install -m 0640 -g grafana grafana.ini /etc/grafana/grafana.ini
install -m 0640 -g grafana sources.yaml /etc/grafana/provisioning/datasources/sources.yaml
install -m 0644 ca-poc.crt grafana.crt grafana-client.crt /etc/grafana/tls/
install -m 0640 -g grafana grafana.key grafana-client.key /etc/grafana/tls/
install -m 0640 -g grafana grafana-admin.password /etc/grafana/secrets/admin.password
install -m 0755 disque-metriques.sh /usr/local/lib/observabilite/disque-metriques.sh
install -m 0644 loki.service grafana.service disque-metriques.service disque-metriques.timer /etc/systemd/system/
cd / && rm -rf /tmp/journalisation-installation
/usr/local/bin/loki -version 2>&1 | head -1
/opt/grafana-$GRAFANA_VERSION/bin/grafana --version 2>&1 | head -1
systemctl daemon-reload
systemctl enable --now disque-metriques.timer 2>&1
for u in loki grafana; do systemctl enable \$u 2>&1; systemctl restart \$u; done
for i in \$(seq 60); do curl -s -o /dev/null --cacert /etc/grafana/tls/ca-poc.crt https://$HOTE:3001/api/health && break; sleep 2; done
systemctl is-active loki grafana disque-metriques.timer
EOS
  echo "## compte auditeur (Viewer) de Grafana"
  local c
  c=$(graf admin GET "/api/users/lookup?loginOrEmail=auditeur")
  if [ "$c" = 200 ]; then echo "auditeur existant"; else
    (umask 077 && jq -n --rawfile p "$S/grafana-auditeur.password" '{name: "auditeur", login: "auditeur", email: "auditeur@poc.test", password: $p, OrgId: 1}' > "$W/auditeur.json")
    c=$(printf 'user = "admin:%s"\n' "$(cat "$S/grafana-admin.password")" | curl -sS -K - --cacert "$P/ca-poc.crt" -o "$W/graf.out" -w '%{http_code}' \
      -X POST -H 'Content-Type: application/json' "https://$HOTE:3001/api/admin/users" -d @"$W/auditeur.json")
    rm -f "${W:?}/auditeur.json"
    echo "création de auditeur : HTTP $c"
  fi
  graf admin GET "/api/orgs/1/users" >/dev/null; jq -c '[.[] | {login, role}]' "$W/graf.out"
}

lki() { # certificat-client|aucun chemin [options curl…] : requête vers Loki depuis l'hôte ; code HTTP, 000 si la poignée TLS échoue
  local n=$1 u=$2; shift 2
  if [ "$n" = aucun ]; then curl -sS --cacert "$P/ca-poc.crt" -o "$W/lki.out" -w '%{http_code}' "$@" "https://$HOTE:3100$u" 2>"$W/lki.err" || true
  else curl -sS --cacert "$P/ca-poc.crt" --cert "$P/$n.crt" --key "$S/$n.key" -o "$W/lki.out" -w '%{http_code}' "$@" "https://$HOTE:3100$u" 2>"$W/lki.err" || true; fi
}

etape_controle() {
  local c t m q
  echo "## écoute sur sc-stockage"
  sur sc-stockage "sudo ss -ltnp | grep -E ':(3001|3100|9096) ' | awk '{print \$4, \$6}'"
  echo "## Loki"
  : > "$W/lki.out"
  c=$(lki aucun /ready); echo "sans certificat client : HTTP $c ($(tail -1 "$W/lki.err" | cut -c1-120))"
  [ "$c" = 000 ] && echo "OK   refusé à la poignée TLS" || echo "KO   accepté sans certificat client"
  c=$(lki controle /ready); echo "avec le certificat controle : /ready HTTP $c"
  t=$(date +%s%N); m="temoin-l2-$t"
  jq -nc --arg t "$t" --arg m "$m" '{streams: [{stream: {source: "controle-l2"}, values: [[$t, $m]]}]}' > "$W/push.json"
  c=$(lki controle /loki/api/v1/push -X POST -H 'Content-Type: application/json' --data @"$W/push.json"); echo "écriture de la ligne témoin $m : HTTP $c"
  sleep 3
  c=$(lki controle /loki/api/v1/query_range -G --data-urlencode 'query={source="controle-l2"}' --data-urlencode "start=$((t / 1000000000 - 60))")
  grep -q "$m" "$W/lki.out" && echo "OK   ligne témoin relue (HTTP $c)" || echo "KO   ligne témoin absente (HTTP $c)"
  c=$(lki controle "/loki/api/v1/delete?query=%7Bsource%3D%22controle-l2%22%7D&start=0" -X POST); echo "demande de suppression : HTTP $c ($(head -c 160 "$W/lki.out"))"
  case $c in 4*|5*) echo "OK   suppression refusée" ;; *) echo "KO   suppression acceptée" ;; esac
  echo "## Grafana"
  c=$(curl -sS --cacert "$P/ca-poc.crt" -o /dev/null -w '%{http_code}' "https://$HOTE:3001/api/search"); echo "anonyme, /api/search : HTTP $c"
  [ "$c" = 401 ] && echo "OK   anonyme refusé" || echo "KO   anonyme : $c"
  for q in prometheus loki; do c=$(graf admin GET "/api/datasources/uid/$q/health"); echo "santé de la source $q : HTTP $c $(jq -c '{status, message}' "$W/graf.out" 2>/dev/null | cut -c1-160)"; done
  q=$(jq -nc '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: "{source=\"controle-l2\"}", queryType: "range"}], from: "now-15m", to: "now"}')
  c=$(graf auditeur POST /api/ds/query "$q"); grep -q "$m" "$W/graf.out" && echo "OK   auditeur : ligne témoin lue dans Loki par Grafana (HTTP $c)" || echo "KO   auditeur, Loki : HTTP $c $(head -c 200 "$W/graf.out")"
  q='{"queries":[{"refId":"A","datasource":{"uid":"prometheus"},"expr":"up","instant":true}],"from":"now-5m","to":"now"}'
  c=$(graf auditeur POST /api/ds/query "$q"); echo "auditeur, Prometheus (up) : HTTP $c, $(jq '[.results.A.frames[]?] | length' "$W/graf.out" 2>/dev/null) série(s)"
  c=$(graf auditeur POST /api/dashboards/db '{"dashboard":{"title":"essai-l2"},"overwrite":false}'); echo "auditeur, création de tableau : HTTP $c"
  c=$(graf auditeur POST /api/datasources '{"name":"essai","type":"loki","url":"http://127.0.0.1:1","access":"proxy"}'); echo "auditeur, création de source : HTTP $c"
  c=$(graf admin DELETE /api/datasources/uid/loki); echo "administrateur, suppression de la source provisionnée loki : HTTP $c ($(head -c 120 "$W/graf.out"))"
  echo "## chemin du navigateur : session de l'auditeur (POST /login, cookie, contrôle d'origine)"
  jq -n --rawfile p "$S/grafana-auditeur.password" '{user: "auditeur", password: $p}' | (umask 077 && cat > "$W/login.json")
  c=$(curl -sS --cacert "$P/ca-poc.crt" -c "$W/session" -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -X POST "https://$HOTE:3001/login" -d @"$W/login.json"); echo "POST /login : HTTP $c, cookie de session : $(grep -c grafana_session "$W/session" || true)"
  c=$(curl -sS --cacert "$P/ca-poc.crt" -b "$W/session" -o "$W/graf.out" -w '%{http_code}' -H "Origin: https://$HOTE:3001" "https://$HOTE:3001/api/user")
  echo "GET /api/user avec la session : HTTP $c ($(jq -r '.login // empty' "$W/graf.out" 2>/dev/null))"
  c=$(curl -sS --cacert "$P/ca-poc.crt" -o /dev/null -w '%{redirect_url}' "https://$HOTE:3001/"); echo "redirection de / sans session : $c"
  rm -f "${W:?}/login.json" "${W:?}/session"
  echo "## journal de Grafana : la lecture de l'auditeur est tracée (router_logging)"
  sur sc-stockage "sudo journalctl -u grafana --since '10 min ago' -o cat | grep -E 'path=/api/ds/query' | grep -c 'userId=' || true" | sed 's/^/  requêtes \/api\/ds\/query journalisées avec leur utilisateur : /'
  echo "## appels vers Grafana Labs dans les journaux de loki et grafana depuis leur démarrage"
  sur sc-stockage "sudo journalctl -u grafana -u loki -o cat | grep -ciE 'grafana\.com|stats\.grafana' || true" | sed 's/^/  lignes : /'
  echo "## connexions sortantes de loki et grafana hors du réseau du PoC (après le démarrage)"
  sur sc-stockage "sudo ss -tnp state established | grep -E 'users:\(\(\"(loki|grafana)' | awk '{print \$4}' | grep -vE '^(192\.168\.161\.|127\.0\.0\.1|\[::1\])' || echo '  aucune'"
  echo "## mémoire"
  sur sc-stockage "free -m | sed -n 2p; for u in loki grafana prometheus; do echo \"\$u : \$(( \$(systemctl show -p MemoryCurrent --value \$u) / 1048576 )) Mi\"; done"
  echo "## mesure du disque"
  sur sc-stockage "cat /etc/fichiers-metriques/disque.prom; systemctl list-timers disque-metriques.timer --no-pager | sed -n 2p"
  rm -f "${W:?}/push.json" "${W:?}/lki.out" "${W:?}/lki.err" "${W:?}/graf.out"
}

# ---------------------------------------------------------------------------------------------------------------- L3
declare -A ROLES=([sc-confiance]="commun noeud confiance" [sc-build]="commun noeud" [sc-stockage]="commun stockage")
declare -A PORT_RELAIS=([sc-confiance]=3501 [sc-build]=3502)

ca_noeud() { # vm : autorité propre au nœud (D17), puis certificat client alloy-<vm> qu'elle signe ; hors de la CA du PoC
  local v=$1 c=$here/config/pki-client.cnf n=alloy-$1
  if [ ! -s "$P/ca-$v.crt" ]; then   # SAN vide exigé par pki-client.cnf (premier passage : « variable has no value »)
    [ -s "$S/ca-$v.key" ] || (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/ca-$v.key")
    SAN= openssl req -x509 -new -config "$c" -extensions ca_noeud -key "$S/ca-$v.key" -sha256 -days 180 \
      -subj "/O=supply-chain PoC/CN=autorite $v (relais 19b)" -out "$P/ca-$v.crt"
  fi
  if [ ! -s "$S/$n.key" ]; then
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/$n.key")
    SAN="DNS:$n.clients.poc.test" openssl req -new -config "$c" -key "$S/$n.key" -subj "/O=supply-chain PoC/CN=$n.clients.poc.test" -out "$W/$n.csr"
    SAN="DNS:$n.clients.poc.test" openssl x509 -req -in "$W/$n.csr" -CA "$P/ca-$v.crt" -CAkey "$S/ca-$v.key" -set_serial "0x$(openssl rand -hex 16)" \
      -days 180 -sha256 -extfile "$c" -extensions client_poc -out "$P/$n.crt" 2>/dev/null
    rm -f "${W:?}/${n:?}.csr"
  fi
  openssl verify -CAfile "$P/ca-$v.crt" -purpose sslclient "$P/$n.crt"
  printf '%s, vérifié par la CA du PoC (refus attendu) : %s\n' "$n" "$(openssl verify -CAfile "$P/ca-poc.crt" "$P/$n.crt" 2>&1 | grep -oE 'error [0-9]+ [^:]*: [^\n]*|OK$' | head -1 || true)"
}

etape_certificats_l3() {
  cert_serveur relais
  cert_client alloy-stockage
  ca_noeud sc-confiance; ca_noeud sc-build
  stat -c '%a %n' "$S"/ca-sc-*.key "$S"/alloy-*.key "$S"/relais.key | sed "s#$S/##"
}

etape_evenements() {
  local sa=system:serviceaccount:observabilite:alloy-evenements d
  kubectl apply --server-side -f "$here/cluster/evenements.yaml"
  for _ in $(seq 30); do
    [ -n "$(kubectl -n observabilite get secret alloy-evenements-jeton -o jsonpath='{.data.token}' 2>/dev/null)" ] && break
    sleep 1
  done
  (umask 077 && kubectl -n observabilite get secret alloy-evenements-jeton -o jsonpath='{.data.token}' | base64 -d > "$S/alloy-evenements.token")
  [ -s "$S/alloy-evenements.token" ] || { echo "KO   jeton du compte absent" >&2; exit 1; }
  for d in "list events -A" "watch events.events.k8s.io -A" "get secrets -n openbao" "list pods -A" "get pods --subresource=log -n openbao" "create events -n default"; do
    # shellcheck disable=SC2086
    echo "can-i $d : $(kubectl auth can-i $d --as "$sa" 2>&1 || true)"
  done
}

etape_openbao_sortie() { # D15 (a) : second device d'audit (sortie standard) déclaré dans config.hcl de la 08 ; ConfigMap
  # appliquée comme le fait openbao.sh deployer, puis rechargement par SIGHUP (sans redémarrage : OpenBao reste descellé)
  local h08=$here/../08-trust-plane n
  racine <<<'bao audit list -format=json' | jq -c 'keys'
  kubectl create configmap openbao-config -n openbao --from-file=config.hcl="$h08/openbao/config.hcl" --dry-run=client -o yaml \
    | kubectl apply --server-side -f -
  for _ in $(seq 90); do   # propagation du volume de la ConfigMap par le kubelet (jusqu'à une minute environ)
    kubectl exec -n openbao openbao-0 -- grep -q '"sortie"' /openbao/config/config.hcl 2>/dev/null && break
    sleep 2
  done
  kubectl exec -n openbao openbao-0 -- grep -c '"sortie"' /openbao/config/config.hcl | sed 's/^/config.hcl vue par le pod, mentions de "sortie" : /'
  kubectl exec -n openbao openbao-0 -- kill -HUP 1
  sleep 3
  racine <<<'bao audit list -format=json' | jq -c 'to_entries[] | {chemin: .key, type: .value.type, fichier: .value.options.file_path}'
  racine <<<'bao audit list -format=json' | jq -e 'has("fichier/") and has("sortie/")' >/dev/null \
    && echo "OK   deux devices d'audit actifs" || { echo "KO   devices d'audit" >&2; exit 1; }
  racine <<<'bao read -format=json sys/seal-status >/dev/null'
  n=$(kubectl logs -n openbao openbao-0 --since=30s | grep -c '"type":"request"' || true)
  echo "lignes d'audit (request) sur la sortie standard du pod dans les 30 dernières secondes : $n"
  [ "$n" -gt 0 ] && echo "OK   audit sur la sortie standard" || { echo "KO   aucune ligne d'audit sur la sortie standard" >&2; exit 1; }
  echo "état : $(racine <<<'bao status -format=json' | jq -c '{sealed, initialized}')"
}

etape_alloy() {
  local v r f
  [ -s "$S/alloy-evenements.token" ] && [ -s "$P/alloy-sc-build.crt" ] || { echo "KO   étapes certificats_l3 et evenements d'abord" >&2; exit 1; }
  for v in sc-confiance sc-build sc-stockage; do
    echo "## $v : rôles ${ROLES[$v]}"
    rm -rf "${D:?}" && (umask 077 && mkdir -p "$D/config")
    for r in ${ROLES[$v]}; do cp "$here/config/alloy/$r"/*.alloy "$D/config/"; done
    sed -i "s#/var/lib/rancher/k3s#$D_ETAT#" "$D"/config/*.alloy
    [ "$DISTRO" = k3s ] || cp "$here/../08b-rke2/config/alloy/journaux-rke2.alloy" "$D/config/"   # kubelet et containerd, en fichiers sous RKE2
    cp "$A/$ALLOY_ARCHIVE" "$here/systemd/alloy.service" "$P/ca-poc.crt" "$D/"
    if [ "$v" = sc-stockage ]; then
      cp "$P/alloy-stockage.crt" "$D/client.crt"; cp "$S/alloy-stockage.key" "$D/client.key"
      cp "$P/relais.crt" "$S/relais.key" "$P/ca-sc-confiance.crt" "$P/ca-sc-build.crt" "$S/alloy-evenements.token" "$D/"
      kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$D/k8s-ca.crt"
      printf 'NOEUD=%s\n' "$v" > "$D/env"
    else
      cp "$P/alloy-$v.crt" "$D/client.crt"; cp "$S/alloy-$v.key" "$D/client.key"
      printf 'NOEUD=%s\nRELAIS_URL=https://%s:%s/loki/api/v1/push\n' "$v" "$HOTE" "${PORT_RELAIS[$v]}" > "$D/env"
    fi
    ( cd "$D" && tar -cf alloy-installation.tar --exclude=alloy-installation.tar . )
    copier "$v" /tmp/alloy-installation "$D/alloy-installation.tar"
    rm -rf "${D:?}"
    sur "$v" sudo bash -s <<EOS
set -euo pipefail
cd /tmp/alloy-installation && tar -xf alloy-installation.tar
printf '%s  %s\n' "$ALLOY_SHA" "$ALLOY_ARCHIVE" | sha256sum -c
python3 -c 'import zipfile; zipfile.ZipFile("$ALLOY_ARCHIVE").extract("alloy-linux-amd64")'
id alloy >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/alloy --no-create-home --shell /usr/sbin/nologin alloy
install -m 0755 alloy-linux-amd64 /usr/local/bin/alloy
install -d -m 0750 -g alloy /etc/alloy /etc/alloy/config /etc/alloy/tls /etc/alloy/secrets
rm -f /etc/alloy/config/*.alloy
install -m 0640 -g alloy config/*.alloy /etc/alloy/config/
install -m 0640 -g alloy env /etc/alloy/env
install -m 0644 ca-poc.crt client.crt /etc/alloy/tls/
install -m 0640 -g alloy client.key /etc/alloy/tls/client.key
if [ -f relais.crt ]; then
  install -m 0644 relais.crt ca-sc-confiance.crt ca-sc-build.crt k8s-ca.crt /etc/alloy/tls/
  install -m 0640 -g alloy relais.key /etc/alloy/tls/relais.key
  install -m 0640 -g alloy alloy-evenements.token /etc/alloy/secrets/k8s.token
fi
install -m 0644 alloy.service /etc/systemd/system/alloy.service
cd / && rm -rf /tmp/alloy-installation
/usr/local/bin/alloy --version | head -1
# Pas de « validate && echo » : sous set -e, un échec dans une liste && n'arrête pas le script (même correction qu'etape_grpc_tls).
if ! /usr/local/bin/alloy validate /etc/alloy/config; then
  echo "KO   configuration d'alloy refusée : Alloy ni redémarré ni rechargé, mais binaire, service et /etc/alloy/config déjà remplacés"
  exit 1
fi
echo "configuration valide"
systemctl daemon-reload
systemctl enable alloy 2>&1
systemctl restart alloy
sleep 5
systemctl is-active alloy
journalctl -u alloy --since '-1 min' -o cat | grep -E 'level=(error|warn)' | tail -5 | cut -c1-240 || true
EOS
  done
}

loki_requete() { # LogQL : requête instantanée vers Loki (certificat controle), une ligne par série : étiquettes et valeur
  curl -sS --cacert "$P/ca-poc.crt" --cert "$P/controle.crt" --key "$S/controle.key" -G "https://$HOTE:3100/loki/api/v1/query" \
    --data-urlencode "query=$1" | jq -r '.data.result[]? | "  \(.metric | to_entries | map("\(.key)=\(.value)") | join(",")) \(.value[1])"'
}

etape_controle_l3() {
  local m c t
  # Premier passage (archivé) : contrôle lancé 30 s après le démarrage des agents, pendant la relecture de l'historique.
  for _ in $(seq 36); do
    [ "$(loki_requete 'count(sum by (noeud) (count_over_time({source="journal"}[24h])))' | awk '{print $NF}')" = 3 ] && break
    sleep 5
  done
  echo "## lignes reçues par Loki dans les 10 dernières minutes, par nœud et par source"
  loki_requete 'sum by (noeud, source) (count_over_time({source=~".+"}[10m]))' | sort
  echo "## sources attendues (J1 à J6 et J8)"
  for q in "{noeud=\"sc-confiance\", source=\"journal\", unite=\"$D_SERVEUR.service\"}" '{noeud="sc-build", source="journal"}' \
           '{noeud="sc-stockage", source="journal", unite="forgejo.service"}' '{noeud="sc-stockage", source="journal", unite="recepteur-alertes.service"}' \
           '{noeud="sc-confiance", source="pods", espace="tekton-chains"}' '{noeud="sc-build", source="pods"}' \
           '{noeud="sc-confiance", source="audit-k8s"}' '{source="evenements-k8s"}' \
           '{noeud="sc-confiance", espace="openbao"} |= "\"type\":\"request\""' '{noeud="sc-stockage", source="audit-zot"}' \
           ${D_JOURNAUX:+'{noeud="sc-build", source="rke2", composant="kubelet"}' '{noeud="sc-confiance", source="rke2", composant="containerd"}'}; do
    c=$(loki_requete "sum(count_over_time(${q}[24h]))" | awk '{print $NF}')   # 168h : antérieur au schéma de Loki (avertissements)
    printf '%-110s %s\n' "$q" "${c:-0}"
  done
  echo "## D17 : relais en écriture seule, nœud imposé"
  m="temoin-l3-$(date +%s%N)"
  c=$(curl -sS --cacert "$P/ca-poc.crt" --cert "$P/alloy-sc-build.crt" --key "$S/alloy-sc-build.key" -o /dev/null -w '%{http_code}' \
    "https://$HOTE:3100/ready" 2>&1 | tail -1 || true); echo "certificat de sc-build vers Loki : $c"
  c=$(curl -sS --cacert "$P/ca-poc.crt" --cert "$P/alloy-sc-build.crt" --key "$S/alloy-sc-build.key" -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' "https://$HOTE:3501/loki/api/v1/push" -d '{"streams":[]}' 2>&1 | tail -1 || true)
  echo "certificat de sc-build vers le port de sc-confiance : $c"
  t=$(date +%s%N)
  jq -nc --arg t "$t" --arg m "$m" '{streams: [{stream: {source: "controle-l3", noeud: "sc-confiance"}, values: [[$t, $m]]}]}' > "$W/push.json"
  c=$(curl -sS --cacert "$P/ca-poc.crt" --cert "$P/alloy-sc-build.crt" --key "$S/alloy-sc-build.key" -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' "https://$HOTE:3502/loki/api/v1/push" -d @"$W/push.json" || true)
  echo "certificat de sc-build vers son port, ligne étiquetée noeud=sc-confiance : HTTP $c"
  sleep 5
  loki_requete "sum by (noeud) (count_over_time({source=\"controle-l3\"} |= \"$m\" [5m]))" | sed 's/^/  stockée sous : /'
  rm -f "${W:?}/push.json"
  echo "## Grafana : l'auditeur lit le journal de k3s"
  q='{"queries":[{"refId":"A","datasource":{"uid":"loki"},"expr":"{noeud=\"sc-confiance\", unite=\"'"$D_SERVEUR"'.service\"}","queryType":"range","maxLines":5}],"from":"now-15m","to":"now"}'
  c=$(graf auditeur POST /api/ds/query "$q"); echo "HTTP $c, $(jq '[.results.A.frames[]?.data.values[2]? // [] | length] | add // 0' "$W/graf.out" 2>/dev/null) ligne(s)"
  echo "## Alloy : état et erreurs sur les trois VM"
  for v in sc-confiance sc-build sc-stockage; do
    sur "$v" "echo \"$v : \$(systemctl is-active alloy), \$(( \$(systemctl show -p MemoryCurrent --value alloy) / 1048576 )) Mi, erreurs depuis le démarrage : \$(sudo journalctl -u alloy -o cat | grep -c 'level=error')\"; sudo journalctl -u alloy -o cat | grep 'level=error' | tail -2 | cut -c1-200"
  done
  sur sc-stockage "sudo ss -ltnp | grep -E ':(3501|3502|12345) ' | awk '{print \$4, \$6}'"
  rm -f "${W:?}/graf.out"
}

# ---------------------------------------------------------------------------------------------------------------- L4
H19=$here/../19-observabilite

etape_prometheus_alloy() { # job alloy (127.0.0.1:12345) ajouté à prometheus.yml de la 19 ; règles par observabilite.sh regles deployer
  copier sc-stockage /tmp/prometheus-l4 "$H19/config/prometheus.yml"
  sur sc-stockage sudo bash -s <<'EOS'
set -euo pipefail
install -m 0640 -g prometheus /tmp/prometheus-l4/prometheus.yml /etc/prometheus/prometheus.yml
rm -rf /tmp/prometheus-l4
promtool check config /etc/prometheus/prometheus.yml | tail -1
systemctl restart prometheus
for i in $(seq 60); do
  curl -s http://127.0.0.1:9090/api/v1/targets | python3 -c 'import sys,json; sys.exit(0 if any(t["labels"]["job"] == "alloy" and t["health"] == "up" for t in json.load(sys.stdin)["data"]["activeTargets"]) else 1)' && break
  sleep 2
done
curl -s http://127.0.0.1:9090/api/v1/targets | python3 -c 'import sys,json; [print(t["labels"]["job"], t["health"]) for t in json.load(sys.stdin)["data"]["activeTargets"]]'
EOS
}

vu_grafana() { # sélecteur marqueur : secondes jusqu'à ce que l'auditeur lise la ligne dans Loki à travers Grafana (120 s au plus)
  local t0 q i
  t0=$(date +%s)
  q=$(jq -nc --arg e "$1 |= \"$2\"" '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: 10}], from: "now-15m", to: "now"}')
  for i in $(seq 60); do
    graf auditeur POST /api/ds/query "$q" >/dev/null
    # Dans les lignes renvoyées seulement : la réponse brute contient aussi le texte de la requête, donc le marqueur
    # (sonde du 02/11/2026 : marqueur jamais émis présent 1 fois dans la réponse, 0 fois dans les données).
    jq -e --arg m "$2" '[.results.A.frames[]?.data.values[]?[]? | strings | select(contains($m))] | length > 0' "$W/graf.out" >/dev/null \
      && { echo $(( $(date +%s) - t0 )); return 0; }
    sleep 2
  done
  echo "absent"
}

temoin() { # source sélecteur marqueur : verdict d'un témoin (émis juste avant l'appel)
  local d
  d=$(vu_grafana "$2" "$3")
  if [ "$d" = absent ]; then echo "KO   $1 : $3 absent de Grafana après 120 s"; else echo "OK   $1 : $3 lu par l'auditeur dans Grafana en $d s"; fi
}

etape_temoins() {
  local m v p a
  m=t4-jamais-emis-$(date +%s%N)   # contre-épreuve : un marqueur jamais émis doit rester absent
  [ "$(vu_grafana '{noeud="sc-build", source="journal"}' "$m")" = absent ] && echo "OK   contre-épreuve : marqueur jamais émis absent" \
    || { echo "KO   contre-épreuve : marqueur jamais émis trouvé" >&2; exit 1; }
  for v in sc-confiance sc-build sc-stockage; do
    m=t4-journal-$v-$(date +%s%N); sur "$v" "logger -t temoin-l4 $m"
    temoin "J1 journal de $v" "{noeud=\"$v\", source=\"journal\"}" "$m"
  done
  m=t4-pods-confiance-$(date +%s%N)
  kubectl exec -n openbao openbao-0 -- sh -c "echo $m > /proc/1/fd/1"
  temoin "J2 pods de sc-confiance (openbao-0)" '{noeud="sc-confiance", source="pods", espace="openbao"}' "$m"
  p=$(kubectl get pods -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=sc-build -o jsonpath='{.items[0].metadata.name}')
  m=t4-pods-build-$(date +%s%N)
  kubectl exec -n kube-system "$p" -c cilium-agent -- sh -c "echo $m > /proc/1/fd/1"
  temoin "J2 pods de sc-build ($p)" '{noeud="sc-build", source="pods", espace="kube-system"}' "$m"
  m=t4-audit-k8s-$(date +%s%N)
  kubectl create configmap "$m" -n observabilite >/dev/null && kubectl delete configmap "$m" -n observabilite >/dev/null
  temoin "J3 audit de l'API" '{noeud="sc-confiance", source="audit-k8s"}' "$m"
  m=t4-evenement-$(date +%s%N)
  kubectl create -f - >/dev/null <<EOF
apiVersion: v1
kind: Event
metadata: {name: $m, namespace: observabilite}
involvedObject: {kind: Namespace, name: observabilite, namespace: observabilite, apiVersion: v1}
reason: TemoinL4
firstTimestamp: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
lastTimestamp: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
count: 1
message: "$m"
type: Normal
source: {component: brique-19b}
EOF
  temoin "J4 événements" '{source="evenements-k8s"}' "$m"
  m=t4-openbao-$(date +%s%N)
  racine <<<"bao read sys/policy/$m >/dev/null 2>&1 || true"
  temoin "J5 audit d'OpenBao (sortie du pod)" '{noeud="sc-confiance", espace="openbao"}' "$m"
  m=t4-zot-$(date +%s%N)
  auth_zot "$W/zot-l4.json"
  printf '%s\n' "$m" > "$W/$m.txt"
  ( cd "$W" && DOCKER_CONFIG= oras push --ca-file "$P/ca-poc.crt" --registry-config "$W/zot-l4.json" "$REG_HOTE/essais-19b/temoin:$m" "$m.txt" >/dev/null )
  rm -f "${W:?}/zot-l4.json" "${W:?}/$m.txt"
  temoin "J6 audit de Zot (poc-ecriture, essais-19b/temoin)" '{noeud="sc-stockage", source="audit-zot"}' "$m"
  m=t4-recepteur-$(date +%s%N)
  sur sc-stockage "curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' http://127.0.0.1:9095/alerte \
    -d '{\"alerts\": [{\"status\": \"firing\", \"labels\": {\"alertname\": \"$m\"}}]}'" | sed 's/^/récepteur : HTTP /'; echo
  temoin "J8 récepteur d'alertes" '{noeud="sc-stockage", source="journal", unite="recepteur-alertes.service"}' "$m"
  rm -f "${W:?}/graf.out"
}

etape_secrets() { # aucun secret connu dans Loki : export de tout Loki sur l'hôte (répertoire 0700), recherche par motifs lus dans
  # des fichiers (jamais en argument ni dans une requête) ; témoin positif : une valeur aléatoire écrite dans Loki doit être trouvée
  local x=$W/secrets-l4 f n debut fin c t total attendu v precedent=
  trap 'rm -rf "${W:?}/secrets-l4" "${W:?}/lki.out" "${W:?}/lki.err" "${D:?}" "${W:?}/refus.out"' EXIT   # copies de secrets
  rm -rf "${x:?}" && (umask 077 && mkdir -p "$x/motifs")
  (umask 077 && openssl rand -hex 24 > "$x/motifs/temoin-positif")
  t=$(date +%s%N)
  jq -nc --arg t "$t" --rawfile v "$x/motifs/temoin-positif" '{streams: [{stream: {source: "controle-l4"}, values: [[$t, ("valeur témoin " + ($v | rtrimstr("\n")))]]}]}' > "$x/push.json"
  lki controle /loki/api/v1/push -X POST -H 'Content-Type: application/json' --data @"$x/push.json" >/dev/null; rm -f "$x/push.json"
  for f in "$S"/*; do
    [ -f "$f" ] || continue
    case $f in
      *.key) (umask 077 && grep -vE '^-----' "$f" | awk 'length($0) >= 40' > "$x/motifs/${f##*/}") ;;
      *.crt|*.pub|*.pem|*.json) ;;
      *) [ "$(tr -d '\n' < "$f" | wc -c)" -ge 12 ] && (umask 077 && tr -d '\n' < "$f" > "$x/motifs/${f##*/}"; echo >> "$x/motifs/${f##*/}") ;;
    esac
  done
  # Secrets qui ne vivent que sur les VM, lus par ssh (sortie standard) dans le même répertoire 0700.
  for v in "sc-confiance:$D_ETAT/server/token" "sc-confiance:$D_ETAT/server/agent-token" \
           "sc-stockage:/etc/forgejo/secrets/metrics_token" "sc-stockage:/etc/forgejo/secrets/secret_key" \
           "sc-stockage:/etc/forgejo/secrets/internal_token" "sc-stockage:/etc/forgejo/secrets/jwt_secret"; do
    f=vm-${v%%:*}-$(basename "${v#*:}")
    (umask 077 && sur "${v%%:*}" "sudo cat ${v#*:} 2>/dev/null" | tr -d '\n' > "$x/motifs/$f")
    [ "$(wc -c < "$x/motifs/$f")" -ge 12 ] && echo >> "$x/motifs/$f" || rm -f "${x:?}/motifs/${f:?}"
  done
  # app.ini de Forgejo ne contient pas les valeurs : *_URI = file:/etc/forgejo/secrets/… (troisième passage, archivé).
  for f in "$x"/motifs/*; do [ -s "$f" ] || { echo "motif vide écarté : ${f##*/}"; rm -f "${f:?}"; }; done
  echo "motifs : $(ls "$x/motifs" | wc -l) fichiers (dont $(ls "$x/motifs" | grep -c '^vm-') lus sur les VM : $(ls "$x/motifs" | grep '^vm-' | paste -sd' ')), valeurs jamais affichées ; témoin positif compris"
  sleep 5
  fin=$(date +%s)000000000; debut=$(date -u -d 2026-11-01T00:00:00Z +%s)000000000; total=0   # début du schéma de Loki
  : > "$x/export"
  while :; do   # pagination vers l'avant, 1 000 lignes par requête (5 000 : message gRPC interne de Loki au-delà de 4 Mo, passages archivés)
    for _ in 1 2 3; do
      lki controle /loki/api/v1/query_range -G --data-urlencode 'query={source=~".+"}' --data-urlencode "start=$debut" \
        --data-urlencode "end=$fin" --data-urlencode limit=1000 --data-urlencode direction=forward > "$x/code"
      [ "$(cat "$x/code")" = 200 ] && break
      echo "  page à $debut : HTTP $(cat "$x/code") ($(tail -1 "$W/lki.err" | cut -c1-120)), nouvel essai"; sleep 3
    done
    [ "$(cat "$x/code")" = 200 ] || { echo "KO   page d'export : HTTP $(cat "$x/code") ($(tail -1 "$W/lki.err" | cut -c1-200))" >&2; exit 1; }
    cp "$W/lki.out" "$x/page.json"
    n=$(jq '[.data.result[].values[]] | length' "$x/page.json")
    jq -r '.data.result[] | .stream as $s | .values[] | "\(.[0]) \($s | tostring) \(.[1])"' "$x/page.json" >> "$x/export"
    total=$((total + n))
    [ "$n" -lt 1000 ] && break
    # Reprise à l'horodatage maximal inclus (+1 perdait les lignes de même horodatage au-delà de la page : 213 lignes au troisième
    # passage) ; les lignes relues sont des doublons exacts, retirés ensuite (Loki dédoublonne déjà les entrées identiques d'un flux).
    debut=$(jq -r '[.data.result[].values[][0]] | max' "$x/page.json")
    [ "$n" = 1000 ] && [ "$debut" = "${precedent:-}" ] && { echo "KO   plus de 1 000 lignes au même horodatage" >&2; exit 1; }
    precedent=$debut
  done
  sort -u -o "$x/export" "$x/export"
  total=$(wc -l < "$x/export")
  echo "lignes exportées, doublons de reprise retirés : $total ($(du -h "$x/export" | cut -f1))"
  attendu=$(lki controle /loki/api/v1/query -G --data-urlencode "query=sum(count_over_time({source=~\".+\"}[$(( (fin - $(date -u -d 2026-11-01T00:00:00Z +%s)000000000) / 1000000000 ))s]))" \
    --data-urlencode "time=$fin" >/dev/null; jq -r '.data.result[0].value[1] // "?"' "$W/lki.out")
  echo "lignes comptées par Loki sur la même fenêtre : $attendu"
  [ "$attendu" = "$total" ] && echo "OK   export complet" || echo "ÉCART export incomplet ou doublons : $total exportées pour $attendu"
  for f in "$x"/motifs/*; do
    c=$(grep -c -F -f "$f" "$x/export" || true)
    printf '  %-36s %s ligne(s)\n' "${f##*/}" "$c"
  done
  rm -rf "${x:?}" "${W:?}/lki.out" "${W:?}/lki.err"
}

prom() { # requête PromQL (sans apostrophe) sur Prometheus de sc-stockage ; une ligne par série
  sur sc-stockage "curl -s -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=$1'" \
    | jq -r '.data.result[]? | "\(.metric | del(.__name__) | tostring) \(.value[1])"'
}
alerte_etat() { # nom : état de l'alerte dans Prometheus (inactive, pending, firing)
  sur sc-stockage "curl -s http://127.0.0.1:9090/api/v1/alerts" | jq -r --arg n "$1" '[.data.alerts[] | select(.labels.alertname == $n) | .state] | first // "inactive"'
}

etape_muette() { # Alloy de sc-stockage arrêté sur sc-build pendant au moins 8 min : SourceMuette (noeud sc-build) déclenchée et
  # notifiée ; témoins écrits dans le journal de sc-build pendant l'arrêt, retrouvés après la reprise (positions d'Alloy) ;
  # résolution. Alloy de sc-build toujours relancé, même en cas d'échec.
  local t0 t m1 m2 e i
  echo "SourceMuette avant : $(alerte_etat SourceMuette)"
  t0=$(date +%s)
  trap 'sur sc-build "sudo systemctl start alloy"; rm -rf "${D:?}" "${W:?}/refus.out"' EXIT
  sur sc-build "sudo systemctl stop alloy && systemctl is-active alloy || true"
  echo "Alloy de sc-build arrêté à $(date -u +%H:%M:%S)"
  m1=t4-arret-1-$(date +%s%N); sur sc-build "logger -t temoin-l4 $m1"
  for i in $(seq 120); do
    e=$(alerte_etat SourceMuette)
    [ "$e" = firing ] && break
    [ "$i" = 60 ] && { m2=t4-arret-2-$(date +%s%N); sur sc-build "logger -t temoin-l4 $m2"; }
    sleep 5
  done
  t=$(date +%s)
  echo "SourceMuette : $e après $((t - t0)) s ; étiquettes : $(sur sc-stockage "curl -s http://127.0.0.1:9090/api/v1/alerts" | jq -c '[.data.alerts[] | select(.labels.alertname == "SourceMuette") | .labels.noeud]')"
  [ -n "${m2:-}" ] || { m2=t4-arret-2-$(date +%s%N); sur sc-build "logger -t temoin-l4 $m2"; }
  for i in $(seq 18); do
    sur sc-stockage "sudo journalctl -u recepteur-alertes --since @$t0 -o cat" | grep -q '"alerte": "SourceMuette"' && break
    sleep 5
  done
  sur sc-stockage "sudo journalctl -u recepteur-alertes --since @$t0 -o cat" | grep '"alerte": "SourceMuette"' | jq -c '{statut, noeud: .etiquettes.noeud}' | sed 's/^/notification : /'
  sur sc-build "sudo systemctl start alloy && systemctl is-active alloy"
  trap 'rm -rf "${D:?}" "${W:?}/refus.out"' EXIT
  echo "Alloy de sc-build relancé à $(date -u +%H:%M:%S), après $(( $(date +%s) - t0 )) s d'arrêt"
  temoin "témoin écrit pendant l'arrêt (début)" '{noeud="sc-build", source="journal"}' "$m1"
  temoin "témoin écrit pendant l'arrêt (après le déclenchement)" '{noeud="sc-build", source="journal"}' "$m2"
  for i in $(seq 96); do
    e=$(alerte_etat SourceMuette); [ "$e" = inactive ] && break
    sleep 5
  done
  echo "SourceMuette : $e $(( $(date +%s) - t0 )) s après l'arrêt"
  sleep 60
  sur sc-stockage "sudo journalctl -u recepteur-alertes --since @$t0 -o cat" | grep '"alerte": "SourceMuette"' | jq -c '{statut, noeud: .etiquettes.noeud}' | sort | uniq -c | sed 's/^/notifications : /'
  rm -f "${W:?}/graf.out"
}

# ---------------------------------------------------------------------------------------------------------------- L5 (D18)
etape_battement() { # timer battement-19b sur les trois VM ; puis, après au moins 12 min, aucun silence de 5 min par nœud
  local v
  for v in sc-confiance sc-build sc-stockage; do
    copier "$v" /tmp/battement-19b "$here/systemd/battement-19b.service" "$here/systemd/battement-19b.timer"
    sur "$v" "sudo install -m 0644 /tmp/battement-19b/battement-19b.service /tmp/battement-19b/battement-19b.timer /etc/systemd/system/ \
      && rm -rf /tmp/battement-19b && sudo systemctl daemon-reload && sudo systemctl enable --now battement-19b.timer 2>&1 | tail -1 \
      && systemctl is-active battement-19b.timer"
  done
}

etape_silences() { # depuis l'installation du battement (premier argument du journal : ACTIVATION, horodatage) : plus long silence
  # par nœud dans Loki, valeur minimale de l'expression de SourceMuette, état de l'alerte
  local debut
  debut=$(sur sc-build "systemctl show -p ActiveEnterTimestamp --value battement-19b.timer" | xargs -I{} date -u -d "{}" +%s)
  echo "battement actif depuis $(date -u -d "@$debut" +%H:%M:%S), relevé à $(date -u +%H:%M:%S)"
  for v in sc-confiance sc-build sc-stockage; do
    lki controle /loki/api/v1/query_range -G --data-urlencode "query=sum(count_over_time({noeud=\"$v\"}[1m]))" \
      --data-urlencode "start=$((debut + 60))" --data-urlencode "end=$(date +%s)" --data-urlencode step=60 >/dev/null
    jq -r --arg v "$v" '[.data.result[0].values[] | .[0]] as $t | ($t | length) as $n
      | "\($v) : \($n) minutes avec au moins une ligne, plus long silence \(if $n < 2 then "?" else ([range(1; $n) | ($t[.] - $t[. - 1]) / 60 - 1] | max) end) min"' "$W/lki.out"
    lki controle /loki/api/v1/query -G --data-urlencode "query=sum(count_over_time({noeud=\"$v\", source=\"journal\", unite=\"battement-19b.service\"}[10m]))" >/dev/null
    echo "  battements des 10 dernières minutes : $(jq -r '.data.result[0].value[1] // 0' "$W/lki.out")"
  done
  echo "minimum de increase(…[5m]) par nœud depuis l'installation (Prometheus, pas de 30 s) :"
  prom "min_over_time(label_replace(sum by (component_id) (increase(loki_source_api_entries_written{job=\"alloy\", component_id=~\"loki.source.api.(confiance|build)\"}[5m])), \"noeud\", \"sc-\$1\", \"component_id\", \"loki.source.api.(.*)\")[$(( $(date +%s) - debut - 300 ))s:30s])"
  echo "SourceMuette : $(alerte_etat SourceMuette)"
  rm -f "${W:?}/lki.out" "${W:?}/lki.err"
}

# ---------------------------------------------------------------------------------------------------------------- L6
# Correctif du gRPC (constat du 03/11/2026, choix (b) du propriétaire : « TLS sur le gRPC (b) ») : le pont httpgrpc de dskit sert
# les routes HTTP de Loki et du relais sur leur port gRPC, sans le mTLS du bloc http.
#   certificats_grpc  certificat client loki-interne (CA du PoC), présenté par les clients gRPC internes de Loki
#   avant_grpc        relevé avant correctif : ports d'écoute de loki et d'alloy sur sc-stockage, sondes httpgrpc (lecture /ready)
#   grpc_tls          loki.yaml (grpc_tls_config et clients internes) et relais.alloy (bloc grpc) posés sur sc-stockage :
#                     copies de sauvegarde, validation sur copie, Alloy rechargé (SIGHUP) puis Loki redémarré (WAL activé),
#                     retour arrière automatique si un service ne revient pas
#   controle_grpc     mêmes sondes qu'avant_grpc, plus les certificats acceptés et refusés par port (tunnel SSH vers la boucle
#                     locale pour les certificats des nœuds, dont les clés restent sur l'hôte)
#   pertes_grpc       battements de cœur : lignes de journald et de Loki sur une fenêtre encadrant grpc_tls, par VM (égalité)
trame_grpc() { printf '\x00\x00\x00\x00\x0d\x0a\x03GET\x12\x06/ready'; }   # httpgrpc.HTTPRequest {GET /ready}, trame gRPC (octets nuls : pas de variable)

etape_certificats_grpc() {
  cert_client loki-interne
  stat -c '%a %n' "$S/loki-interne.key" | sed "s#$S/##"
}

sondes_stockage() { # sur sc-stockage : ports de loki et d'alloy, puis httpgrpc /ready en clair et en TLS sans certificat
  sur sc-stockage sudo bash -s <<'EOS'
set -uo pipefail
printf '\x00\x00\x00\x00\x0d\x0a\x03GET\x12\x06/ready' > /root/trame-grpc
reponse() { grep -iE '^HTTP|grpc-status' /root/h 2>/dev/null | tr -d '\r' | tr '\n' ' '; [ -s /root/r ] && tr -cd '[:print:]' < /root/r | grep -oE 'ready' | head -1; echo; rm -f /root/h /root/r; }
echo "## ports en écoute de loki et d'alloy"
ss -ltnpH | grep -E 'users:\(\("(loki|alloy)"' | awk '{print $4, $6}' | sed -E 's/,fd=[0-9]+//' | sort
ports=$(ss -ltnpH | grep -E 'users:\(\("(loki|alloy)"' | awk '{n=split($4,a,":"); print a[n]}' | grep -vxE '3100|3501|3502|12345' | sort -un)
for p in $ports; do
  echo "== $p, httpgrpc en clair"
  curl -sS --max-time 5 --http2-prior-knowledge -H 'content-type: application/grpc' -H 'te: trailers' --data-binary @/root/trame-grpc \
    -D /root/h -o /root/r "http://127.0.0.1:$p/httpgrpc.HTTP/Handle" 2>&1 | head -1; reponse
  echo "== $p, httpgrpc en TLS sans certificat client"
  curl -sS --max-time 5 --http2 --cacert /etc/loki/tls/ca-poc.crt --resolve "sc-stockage.poc.test:$p:127.0.0.1" -H 'content-type: application/grpc' \
    -H 'te: trailers' --data-binary @/root/trame-grpc -D /root/h -o /root/r "https://sc-stockage.poc.test:$p/httpgrpc.HTTP/Handle" 2>&1 | head -1; reponse
done
rm -f /root/trame-grpc
EOS
}

etape_avant_grpc() {
  sondes_stockage
  echo "## depuis l'hôte : ports de sc-stockage hors boucle locale tenus par loki ou alloy (connexion TCP)"
  local p
  for p in $(sur sc-stockage "sudo ss -ltnpH | grep -E 'users:\(\(\"(loki|alloy)\"' | awk '{print \$4}' | grep -v '^127\.' | awk -F: '{print \$NF}' | sort -un"); do
    timeout 3 bash -c "</dev/tcp/$HOTE/$p" 2>/dev/null && echo "$p : ouvert" || echo "$p : fermé"
  done
}

etape_grpc_tls() { # copies de sauvegarde ; validation sur copie ; Alloy rechargé par SIGHUP (seul le serveur du relais redémarre,
  # la file de loki.write reste) avant le redémarrage de Loki ; retour arrière automatique si un service ne revient pas
  [ -s "$P/loki-interne.crt" ] || { echo "KO   étape certificats_grpc d'abord" >&2; exit 1; }
  rm -rf "${D:?}" && (umask 077 && mkdir -p "$D")
  cp "$here/config/loki.yaml" "$here/config/alloy/stockage/relais.alloy" "$P/loki-interne.crt" "$S/loki-interne.key" "$D/"
  copier sc-stockage /tmp/grpc-tls "$D"/*
  rm -rf "${D:?}"
  date +%s > "$W/l6-debut"   # début de la fenêtre de l'étape pertes_grpc
  sur sc-stockage sudo bash -s <<'EOS'
set -euo pipefail
cd /tmp/grpc-tls
alloy_pret() { # 3511 et 3512 sur la boucle locale, aucun port d'alloy sur toutes les interfaces
  local l; l=$(ss -ltnpH | grep 'users:(("alloy"' | awk '{print $4}')
  grep -qx '127.0.0.1:3511' <<<"$l" && grep -qx '127.0.0.1:3512' <<<"$l" && ! grep -qE '^(\*|0\.0\.0\.0|\[::\]):' <<<"$l"
}
loki_pret() {
  [ "$(curl -s -o /dev/null -w '%{http_code}' --cacert /etc/loki/tls/ca-poc.crt --cert /etc/loki/tls/loki-interne.crt \
    --key /etc/loki/tls/loki-interne.key https://192.168.161.13:3100/ready || true)" = 200 ]
}
install -m 0644 loki-interne.crt /etc/loki/tls/
install -m 0640 -g loki loki-interne.key /etc/loki/tls/
cp -p /etc/loki/loki.yaml /etc/loki/loki.yaml.avant-l6
cp -p /etc/alloy/config/relais.alloy /etc/alloy/relais.alloy.avant-l6   # hors de config/ : alloy charge tous les *.alloy
echo "copies de sauvegarde : /etc/loki/loki.yaml.avant-l6, /etc/alloy/relais.alloy.avant-l6"
/usr/local/bin/loki -config.file=loki.yaml -verify-config 2>&1 | tail -1
mkdir -m 0750 alloy-config && cp /etc/alloy/config/*.alloy alloy-config/ && cp relais.alloy alloy-config/
# Pas de « validate && echo » : sous set -e, un échec dans une liste && n'arrête pas le script (défaut trouvé le 09/11 par l'essai
# hors cluster d'evenements.sh de la 08c, corrigé ici le 09/11).
if ! /usr/local/bin/alloy validate alloy-config; then
  echo "KO   configuration d'alloy (copie) refusée : loki.yaml et relais.alloy en place inchangés, Alloy et Loki non touchés"
  cd / && rm -rf /tmp/grpc-tls; exit 1
fi
echo "configuration d'alloy (copie) valide"
echo "## alloy : nouveau relais.alloy, rechargement par SIGHUP (pid $(systemctl show -p MainPID --value alloy))"
install -m 0640 -g alloy relais.alloy /etc/alloy/config/relais.alloy
systemctl kill -s HUP alloy
for i in $(seq 30); do alloy_pret && break; sleep 1; done
if ! alloy_pret; then
  echo "KO   relais non rechargé en 30 s : retour arrière"
  install -m 0640 -g alloy /etc/alloy/relais.alloy.avant-l6 /etc/alloy/config/relais.alloy; systemctl kill -s HUP alloy; exit 1
fi
echo "alloy : $(systemctl is-active alloy), pid $(systemctl show -p MainPID --value alloy), relais rechargé en ${i} s"
echo "## loki : nouveau loki.yaml, redémarrage"
install -m 0640 -g loki loki.yaml /etc/loki/loki.yaml
cd / && rm -rf /tmp/grpc-tls
debut=$(date +%s)
systemctl restart loki
for i in $(seq 90); do loki_pret && break; sleep 2; done   # le délai de 15 s de l'ingester ne court qu'après un premier /ready
if ! loki_pret; then
  echo "KO   loki pas prêt en 180 s : retour arrière"
  install -m 0640 -g loki /etc/loki/loki.yaml.avant-l6 /etc/loki/loki.yaml; systemctl restart loki; exit 1
fi
echo "loki : $(systemctl is-active loki), /ready 200, $(( $(date +%s) - debut )) s après le redémarrage"
echo "## erreurs et avertissements de loki et d'alloy depuis le redémarrage de loki (regroupés)"
journalctl -u loki -u alloy --since "@$debut" -o cat | grep -E 'level=(error|warn)' | sed -E 's/ts=[^ ]+ //; s/duration=[^ ]+ //' | cut -c1-200 | sort | uniq -c | sort -rn | head -12 || true
EOS
}

etape_pertes_grpc() { # battements (un par minute et par VM) : lignes de journald et lignes de Loki sur la même fenêtre, qui commence
  # 2 min avant grpc_tls et finit 1 min avant ce relevé ; égalité attendue
  [ -s "$W/l6-debut" ] || { echo "KO   étape grpc_tls d'abord" >&2; exit 1; }
  local a b v nj nl
  a=$(( $(cat "$W/l6-debut") - 120 )); b=$(( $(date +%s) - 60 ))
  echo "fenêtre : $(date -u -d "@$a" +%H:%M:%S) à $(date -u -d "@$b" +%H:%M:%S) UTC ($(( (b - a) / 60 )) min)"
  for v in sc-confiance sc-build sc-stockage; do
    nj=$(sur "$v" "sudo journalctl -t battement-19b --since @$a --until @$b -o cat | wc -l")
    lki controle /loki/api/v1/query -G --data-urlencode "query=sum(count_over_time({noeud=\"$v\", unite=\"battement-19b.service\"}[$((b - a))s]))" \
      --data-urlencode "time=$b" >/dev/null
    nl=$(jq -r '.data.result[0].value[1] // 0' "$W/lki.out")
    printf '%-13s journald %3s   Loki %3s   %s\n' "$v" "$nj" "$nl" "$([ "$nj" = "$nl" ] && echo OK || echo KO)"
  done
  rm -f "${W:?}/lki.out" "${W:?}/lki.err"
}

etape_controle_grpc() {
  local p cert ctl=$W/tunnel-grpc
  sondes_stockage
  echo "## depuis l'hôte : ports de sc-stockage hors boucle locale tenus par loki ou alloy (connexion TCP)"
  for p in $(sur sc-stockage "sudo ss -ltnpH | grep -E 'users:\(\(\"(loki|alloy)\"' | awk '{print \$4}' | grep -v '^127\.' | awk -F: '{print \$NF}' | sort -un"); do
    timeout 3 bash -c "</dev/tcp/$HOTE/$p" 2>/dev/null && echo "$p : ouvert" || echo "$p : fermé"
  done
  echo "## certificats acceptés par port gRPC (tunnel SSH vers la boucle locale de sc-stockage ; httpgrpc /ready)"
  trame_grpc > "$W/trame-grpc"
  # shellcheck disable=SC2064   # développé maintenant : ctl est locale et n'existe plus à la sortie
  trap "ssh ${SSH_OPTS[*]@Q} -S ${ctl@Q} -O exit poc@$HOTE 2>/dev/null || true" EXIT   # la sous-coquille de lancer : tunnel fermé même en cas d'échec
  ssh "${SSH_OPTS[@]}" -M -S "$ctl" -o ExitOnForwardFailure=yes -f -N \
    -L 127.0.0.1:19096:127.0.0.1:9096 -L 127.0.0.1:13511:127.0.0.1:3511 -L 127.0.0.1:13512:127.0.0.1:3512 "poc@$HOTE"
  for p in 9096 3511 3512; do
    for cert in loki-interne controle alloy-sc-confiance alloy-sc-build; do
      printf '%-5s %-20s ' "$p" "$cert"
      curl -sS --max-time 5 --http2 --cacert "$P/ca-poc.crt" --resolve "sc-stockage.poc.test:1$p:127.0.0.1" --cert "$P/$cert.crt" --key "$S/$cert.key" \
        -H 'content-type: application/grpc' -H 'te: trailers' --data-binary @"$W/trame-grpc" -D "$W/h" -o "$W/r" \
        "https://sc-stockage.poc.test:1$p/httpgrpc.HTTP/Handle" 2>&1 | head -1 | cut -c1-110 || true
      { grep -iE 'grpc-status' "$W/h" 2>/dev/null | tr -d '\r' | tr '\n' ' '; [ -s "$W/r" ] && tr -cd '[:print:]' < "$W/r" | grep -oE 'ready' | head -1; } || true
      [ -s "$W/h" ] && echo; rm -f "$W/h" "$W/r"
    done
  done
  ssh "${SSH_OPTS[@]}" -S "$ctl" -O exit "poc@$HOTE" 2>&1 | sed 's/^/tunnel : /'
  rm -f "${W:?}/trame-grpc"
}

# ---------------------------------------------------------------------------------------------------------------- L7
# Domaine de replay de la brique 10 dans Grafana (demande du propriétaire du 03/11/2026 : « Replay dans Grafana »).
#   corroborer_vsa  lecture seule : écritures de poc-replay sous builds/vsa/ lues par l'auditeur dans l'audit de Zot (J6), à
#                   travers Grafana, sur la fenêtre du dernier push ; heure du PUT du manifeste de la VSA
#                   comparée à timeVerified (le push ne donne qu'une borne haute de l'heure du replay) ; contre-épreuve :
#                   marqueur jamais émis, absent des lignes de données
VSA_MANIFESTE=sha256:69a2b10326017d997ace216a789c1d9c4820a4a5f4440aa60f724e95c7682d9b   # resultats/r5-pousser_vsa.log de la 10
TIME_VERIFIED=2026-11-04T21:27:33Z                                                    # resultats/r5-vsa-enonce.json de la 10
VSA_DE=2026-11-04T22:00:00Z VSA_A=2026-11-04T23:00:00Z                                # fenêtre du push du 04/11/2026

lignes_auditeur() { # expression-LogQL début fin (ISO UTC) : lignes de données lues par l'auditeur à travers Grafana, une par
  # ligne : heure de Loki (UTC) puis la ligne ; la réponse brute contient aussi le texte de la requête, d'où la lecture des
  # seules valeurs de données (défaut trouvé avant L4)
  local q c
  q=$(jq -nc --arg e "$1" --arg de "$(date -ud "$2" +%s)000" --arg a "$(date -ud "$3" +%s)000" \
    '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: 1000, direction: "forward"}], from: $de, to: $a}')
  c=$(graf auditeur POST /api/ds/query "$q")
  echo "requête de l'auditeur : HTTP $c, $(jq '[.results.A.frames[]?.data.values[2]? // [] | length] | add // 0' "$W/graf.out") ligne(s) ; champs : $(jq -c '[.results.A.frames[0]?.schema.fields[]?.name]' "$W/graf.out")" >&2
  jq -r '.results.A.frames[]? | .data.values as $v | range(0; ($v[2] // []) | length) | "\($v[1][.] / 1000 | todate) \($v[2][.])"' "$W/graf.out"
}

etape_corroborer_vsa() {
  local m l t
  echo "## écritures de poc-replay sous builds/vsa/, audit de Zot (noeud sc-stockage), de $VSA_DE à $VSA_A"
  lignes_auditeur '{noeud="sc-stockage", source="audit-zot"} |= "poc-replay" |= "builds/vsa/"' "$VSA_DE" "$VSA_A" > "$W/l7-vsa.txt"
  cat "$W/l7-vsa.txt"
  echo "## PUT du manifeste de la VSA (${VSA_MANIFESTE:0:19}…)"
  l=$(grep -F "manifests/$VSA_MANIFESTE" "$W/l7-vsa.txt" || true)
  echo "lignes : $(printf '%s' "$l" | grep -c . || true)"
  t=$(printf '%s' "$l" | head -1 | cut -d' ' -f2- | jq -r '.time // empty' 2>/dev/null || true)
  echo "heure de Zot : ${t:-absente} ; timeVerified : $TIME_VERIFIED"
  if [ -n "$t" ] && [ "$(date -ud "$t" +%s)" -ge "$(date -ud "$TIME_VERIFIED" +%s)" ]; then
    echo "OK   push postérieur à timeVerified, de $(( $(date -ud "$t" +%s) - $(date -ud "$TIME_VERIFIED" +%s) )) s (borne haute de l'heure du replay)"
  else
    echo "KO   push absent, ou antérieur à timeVerified"
  fi
  echo "## contre-épreuve : marqueur jamais émis"
  m="jamais-emis-l7-$(date +%s%N)"
  echo "lignes de données contenant le marqueur : $(lignes_auditeur "{noeud=\"sc-stockage\", source=\"audit-zot\"} |= \"$m\"" "$VSA_DE" "$VSA_A" | grep -cF "$m" || true)"
  rm -f "${W:?}/l7-vsa.txt" "${W:?}/graf.out"
}

case ${JALON:-} in l2) lancer l2 L2 "$@" ;; l3) lancer l3 L3 "$@" ;; l4) lancer l4 L4 "$@" ;; l5) lancer l5 L5 "$@" ;; l6) lancer l6 L6 "$@" ;; l7) lancer l7 L7 "$@" ;; *) lancer l1 L1 "$@" ;; esac
