#!/usr/bin/env bash
# Brique 20, étape 4 : ce que peut vraiment un compte Grafana de rôle Viewer sur Loki. Banc jetable (unshare -rn, 127.0.0.1 seul) ; jamais sur
# la plateforme. Grafana 13.3.0 et Loki 3.7.9, archives de la 19b en cache, sha256 revérifiés ; aucun téléchargement.
#   - Loki en mTLS, CA jetable ; deletion_mode: disabled, comme en service ; Grafana avec grafana.ini de la 19b (chemins et adresses remplacés)
#     et la source Loki de sources.yaml (certificat client) ;
#   - compte Viewer créé par l'API d'administration ; droits mesurés par /api/ds/query, par le proxy de la source et par ses ressources ;
#   - lecteur_loki.py et kev() de l'exportateur sur des lignes au format de entrees-scan.py (ses fonctions, importées), délais du banc.
# Limites : ni la VM, ni Alloy, ni la source Prometheus.
# VARIANTE=liste : data_source_proxy_whitelist = 127.0.0.1:9090 dans [security] de grafana.ini (la source Prometheus, seule permise au proxy) ;
# le proxy doit refuser Loki, sans changer /api/ds/query ni les ressources. Sans variante : la configuration en service.
# Usage (racine du dépôt) : [VARIANTE=liste] [SUFFIXE=-2] mise exec -- bash poc/bricks/20-kpi/banc-grafana.sh   (journal : resultats/e4-banc-grafana<SUFFIXE>.log)
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
RACINE=$(cd "$here/../../.." && pwd)
LOG=$here/resultats/e4-banc-grafana${VARIANTE:+-$VARIANTE}${SUFFIXE:-}.log
export T=$HOME/.cache/supply-chain-poc/20/banc-grafana   # chemin écrit en entier : effacé à la sortie
A=$HOME/.cache/supply-chain-poc/19b/amont J19=$here/../19b-journalisation
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }

if [ "${1:-}" = ns ]; then
  ip link set lo up
  echo "# routes dans l'espace de noms : $(ip route | wc -l)"
  (cd "$T" && exec ./loki -config.file="$T/loki.yaml") > "$T/loki.out" 2>&1 & lp=$!
  (cd "$T/grafana-13.3.0" && exec ./bin/grafana server --homepath="$T/grafana-13.3.0" --config="$T/grafana.ini") > "$T/grafana.out" 2>&1 & gp=$!
  trap 'kill $lp $gp 2> /dev/null' EXIT
  L=(curl -sS --cacert "$T/ca.crt" --cert "$T/client.crt" --key "$T/client.key" -o "$T/l.out" -w '%{http_code}')
  for _ in $(seq 90); do
    [ "$("${L[@]}" https://127.0.0.1:3100/ready 2> /dev/null)" = 200 ] && curl -fsS --cacert "$T/ca.crt" https://127.0.0.1:3001/api/health > /dev/null 2>&1 && break
    sleep 1
  done
  g() { # compte méthode chemin [corps] : code HTTP, réponse dans g.out ; mot de passe par l'entrée de configuration
    local d=(); [ -z "${4:-}" ] || d=(-d "$4")
    printf 'user = "%s:%s"\n' "$1" "$(cat "$T/$1.mdp")" | curl -sS -K - --cacert "$T/ca.crt" -o "$T/g.out" -w '%{http_code}' -X "$2" \
      -H 'Content-Type: application/json' "${d[@]}" "https://127.0.0.1:3001$3"
  }
  compte() { # lignes de ce marqueur dans Loki, lues en direct par le certificat client
    "${L[@]}" -G https://127.0.0.1:3100/loki/api/v1/query_range --data-urlencode "query={source=~\".+\"} |= \"$1\"" --data-urlencode "start=$(($(date +%s) - 600))" > /dev/null
    jq '[.data.result[]?.values[]?] | length' "$T/l.out"
  }
  corps() { jq -nc --arg t "$(date +%s)000000000" --arg m "$1" '{streams: [{stream: {source: "essai"}, values: [[$t, $m]]}]}'; }
  echo "## 1. Loki en direct (témoins)"
  attendu "sans certificat client" "$(curl -sS --cacert "$T/ca.crt" -o /dev/null -w '%{http_code}' https://127.0.0.1:3100/ready 2> /dev/null)" 000
  attendu "écriture avec le certificat client" "$("${L[@]}" -X POST -H 'Content-Type: application/json' -d "$(corps temoin-direct)" https://127.0.0.1:3100/loki/api/v1/push)" 204
  sleep 2; attendu "ligne témoin directe relue" "$(compte temoin-direct)" 1
  echo "## 2. compte Viewer"
  (umask 077; jq -n --rawfile p "$T/kpi-journal.mdp" '{name: "kpi-journal", login: "kpi-journal", email: "kpi-journal@poc.test", password: $p, OrgId: 1}' > "$T/compte.json")
  attendu "création" "$(printf 'user = "admin:%s"\n' "$(cat "$T/admin.mdp")" | curl -sS -K - --cacert "$T/ca.crt" -o "$T/g.out" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d @"$T/compte.json" https://127.0.0.1:3001/api/admin/users)" 200
  g admin GET /api/orgs/1/users > /dev/null; attendu "rôle relu" "$(jq -r '.[] | select(.login == "kpi-journal") | .role' "$T/g.out")" Viewer
  q='{"queries":[{"refId":"A","datasource":{"uid":"loki"},"expr":"{source=\"essai\"}","queryType":"range"}],"from":"now-15m","to":"now"}'
  attendu "lecture par /api/ds/query" "$(g kpi-journal POST /api/ds/query "$q") $(grep -c temoin-direct "$T/g.out")" "200 1"
  echo "## 3. écritures par le Viewer : code HTTP, lignes arrivées dans Loki"
  essai() { # marqueur compte méthode chemin attendu
    local c; c=$(g "$2" "$3" "$4" "$(corps "$1")"); sleep 2
    attendu "$2, $3 $4" "$c, $(compte "$1") ligne(s)" "$5"
    head -c 160 "$T/g.out" | tr '\n' ' ' | sed 's/^/  réponse : /'; echo
  }
  essai viewer-proxy kpi-journal POST /api/datasources/proxy/uid/loki/loki/api/v1/push "403, 0 ligne(s)"
  essai viewer-put kpi-journal PUT /api/datasources/proxy/uid/loki/loki/api/v1/push "403, 0 ligne(s)"
  essai viewer-ressource kpi-journal POST /api/datasources/uid/loki/resources/loki/api/v1/push "404, 0 ligne(s)"
  essai admin-proxy admin POST /api/datasources/proxy/uid/loki/loki/api/v1/push "403, 0 ligne(s)"
  echo "## 4. autres chemins de Loki par le proxy, Viewer (code HTTP)"
  for x in "GET /config" "GET /metrics" "POST /log_level?log_level=debug" "POST /flush" "GET /flush" "GET /log_level?log_level=debug" "GET /ingester/prepare_shutdown" "PUT /ingester/prepare_shutdown" "DELETE /ingester/prepare_shutdown" "GET /services" "POST /loki/api/v1/delete?query=%7Bsource%3D%22essai%22%7D&start=0"; do
    c=$(g kpi-journal "${x%% *}" "/api/datasources/proxy/uid/loki${x#* }"); echo "MESURE|$x|HTTP $c"
  done
  echo "## 5. lecteur_loki.py, puis kev() : délais du banc"
  python3 -I "$here/banc_grafana_lignes.py" lignes "$RACINE" > "$T/kev.json"
  attendu "lignes de entrees-scan poussées" "$("${L[@]}" -X POST -H 'Content-Type: application/json' -d @"$T/kev.json" https://127.0.0.1:3100/loki/api/v1/push)" 204
  sleep 2; echo avant > "$T/lignes"
  lecteur() { GRAFANA=https://127.0.0.1:3001 CA=$T/ca.crt UTILISATEUR=kpi-journal MDP=$T/kpi-journal.mdp SORTIE=$T/lignes /usr/bin/python3 -I "$RACINE/tools/metrics-exporter/lecteur_loki.py"; }
  lecteur; attendu "lecteur : code" "$?" 0
  attendu "lignes lues : résumés, entrées KEV" "$(grep -c 'liste émise' "$T/lignes") $(grep -c '"kev":true' "$T/lignes")" "3 6"
  attendu "délais des KEV (valeurs de banc_comparer.py)" "$(python3 -I "$here/banc_grafana_lignes.py" delais "$RACINE" "$T/lignes")" conforme
  python3 -I "$here/banc_grafana_lignes.py" beaucoup "$RACINE" > "$T/kev.json"
  attendu "5000 entrées KEV poussées" "$("${L[@]}" -X POST -H 'Content-Type: application/json' -d @"$T/kev.json" https://127.0.0.1:3100/loki/api/v1/push)" 204
  sleep 2; h=$(sha256sum < "$T/lignes"); lecteur; c=$?
  attendu "réponse tronquée : code, fichier inchangé" "$c $([ "$h" = "$(sha256sum < "$T/lignes")" ] && echo oui || echo non)" "2 oui"
  echo "## 6. arrêt de Loki par le proxy, Viewer"
  vie() { echo "Loki $(kill -0 $lp 2> /dev/null && echo vivant || echo arrêté), /ready $("${L[@]}" https://127.0.0.1:3100/ready 2> /dev/null)"; }
  if [ "${VARIANTE:-}" = liste ]; then
    echo "## 7. avec la liste : ce qui doit marcher encore, ce qui doit être refusé"
    attendu "requête normale par /api/ds/query" "$(g kpi-journal POST /api/ds/query "$q") $(grep -c temoin-direct "$T/g.out")" "200 1"
    attendu "noms d'étiquettes par les ressources (explorateur)" "$(g kpi-journal GET "/api/datasources/uid/loki/resources/labels?start=$(($(date +%s) - 600))000000000&end=$(date +%s)000000000") $(jq -r '.data | index("source") != null' "$T/g.out")" "200 true"
    attendu "santé de la source (administrateur)" "$(g admin GET /api/datasources/uid/loki/health)" 200
    attendu "proxy vers la source Prometheus (rien n'écoute : 502, donc permis)" "$(g kpi-journal GET /api/datasources/proxy/uid/prometheus/api/v1/rules)" 502
    for c in kpi-journal admin; do for x in /config /flush "/log_level?log_level=debug" /loki/api/v1/labels; do
      attendu "$c, GET proxy $x" "$(g "$c" GET "/api/datasources/proxy/uid/loki$x")" 403
    done; done
    for x in uid/loki/ingester/shutdown 2/ingester/shutdown uid/loki//ingester/shutdown uid/loki/%2e%2e/ingester/shutdown uid/loki/loki/api/v1/../../../ingester/shutdown; do
      c=$(printf 'user = "kpi-journal:%s"\n' "$(cat "$T/kpi-journal.mdp")" | curl -sS -K - --path-as-is --cacert "$T/ca.crt" -o "$T/g.out" -w '%{http_code}' "https://127.0.0.1:3001/api/datasources/proxy/$x"); sleep 4
      echo "MESURE|GET proxy/$x|HTTP $c|$(head -c 90 "$T/g.out" | tr '\n' ' ')"; attendu "après GET proxy/$x" "$(vie)" "Loki vivant, /ready 200"
    done
    for x in ingester/shutdown /ingester/shutdown ../ingester/shutdown ..%2f..%2f..%2fingester%2fshutdown labels/../../../../ingester/shutdown; do
      c=$(printf 'user = "kpi-journal:%s"\n' "$(cat "$T/kpi-journal.mdp")" | curl -sS -K - --path-as-is --cacert "$T/ca.crt" -o "$T/g.out" -w '%{http_code}' "https://127.0.0.1:3001/api/datasources/uid/loki/resources/$x"); sleep 4
      echo "MESURE|GET resources/$x|HTTP $c"; attendu "après GET resources/$x" "$(vie)" "Loki vivant, /ready 200"
    done
    echo "## bilan : $N cas, $KO écart(s)"
    [ "$KO" = 0 ]; exit $?
  fi
  for x in "POST /api/datasources/proxy/uid/loki/ingester/shutdown" "GET /api/datasources/uid/loki/resources/ingester/shutdown" "GET /api/datasources/proxy/uid/loki/ingester/shutdown"; do
    c=$(g kpi-journal "${x%% *}" "${x#* }"); sleep 8; echo "MESURE|$x|HTTP $c|$(vie)"
  done
  wait "$lp"; attendu "code de sortie de Loki (loki.service : Restart=on-failure ; 0 : systemd ne le relance pas)" "$?" 0
  echo "## bilan : $N cas, $KO écart(s)"
  [ "$KO" = 0 ]; exit $?
fi

[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
[ ! -e ~/.cache/supply-chain-poc/20/banc-grafana ] || find ~/.cache/supply-chain-poc/20/banc-grafana -delete
trap 'find ~/.cache/supply-chain-poc/20/banc-grafana -delete 2> /dev/null' EXIT
mkdir -p "$T"; chmod 700 "$T"
{
  echo "# banc-grafana.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), scripts $(cat "$here/banc-grafana.sh" "$here/banc_grafana_lignes.py" "$RACINE/tools/metrics-exporter/lecteur_loki.py" "$RACINE/tools/metrics-exporter/metrics_exporter.py" | sha256sum | cut -c1-16)"
  v() { sed -n "s/^$1=\([^ ]*\).*/\1/p" "$J19/journalisation.sh"; }
  (cd "$A" && printf '%s  %s\n%s  %s\n' "$(v LOKI_SHA)" "$(v LOKI_ARCHIVE)" "$(v GRAFANA_SHA)" "$(v GRAFANA_ARCHIVE)" | sha256sum -c -) || exit 1
  python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("loki-linux-amd64", sys.argv[2])' "$A/$(v LOKI_ARCHIVE)" "$T" && mv "$T/loki-linux-amd64" "$T/loki" && chmod 755 "$T/loki"
  tar xzf "$A/$(v GRAFANA_ARCHIVE)" -C "$T"
  ec=(-newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes)
  openssl req -x509 "${ec[@]}" -days 1 -subj /CN=ca-jetable -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign -keyout "$T/ca.key" -out "$T/ca.crt" 2> /dev/null
  for k in serveur:serverAuth client:clientAuth; do
    n=${k%%:*}
    openssl req -x509 "${ec[@]}" -days 1 -subj "/CN=$n" -CA "$T/ca.crt" -CAkey "$T/ca.key" -addext subjectAltName=IP:127.0.0.1 \
      -addext basicConstraints=critical,CA:FALSE -addext keyUsage=critical,digitalSignature -addext authorityKeyIdentifier=keyid -addext "extendedKeyUsage=${k#*:}" -keyout "$T/$n.key" -out "$T/$n.crt" 2> /dev/null || echo "KO   certificat $n"
  done
  for c in admin kpi-journal; do (umask 077; openssl rand -hex 16 | tr -d '\n' > "$T/$c.mdp"); done
  cat > "$T/loki.yaml" <<YAML
auth_enabled: false
server: {http_listen_address: 127.0.0.1, http_listen_port: 3100, grpc_listen_address: 127.0.0.1, grpc_listen_port: 9096, log_level: warn,
  http_tls_config: {cert_file: $T/serveur.crt, key_file: $T/serveur.key, client_auth_type: RequireAndVerifyClientCert, client_ca_file: $T/ca.crt}}
common: {instance_addr: 127.0.0.1, path_prefix: $T/loki-data, replication_factor: 1, ring: {kvstore: {store: inmemory}},
  storage: {filesystem: {chunks_directory: $T/loki-data/chunks, rules_directory: $T/loki-data/rules}}}
schema_config: {configs: [{from: 2026-11-01, store: tsdb, object_store: filesystem, schema: v13, index: {prefix: index_, period: 24h}}]}
compactor: {working_directory: $T/loki-data/compactor, retention_enabled: true, delete_request_store: filesystem}
$(sed -n '/^limits_config:/,/^$/p;/^pattern_ingester:/,/^$/p;/^analytics:/,/^$/p' "$J19/config/loki.yaml")
YAML
  sed -E "s#^http_addr = .*#http_addr = 127.0.0.1#; s#^domain = .*#domain = 127.0.0.1#; s#^cert_file = .*#cert_file = $T/serveur.crt#; s#^cert_key = .*#cert_key = $T/serveur.key#
    s#^data = .*#data = $T/g-data#; s#^logs = .*#logs = $T/g-log#; s#^plugins = .*#plugins = $T/g-plugins#; s#^provisioning = .*#provisioning = $T/prov#
    /^data_source_proxy_whitelist/d; s#^admin_password = .*#admin_password = \$__file{$T/admin.mdp}#" "$J19/config/grafana.ini" > "$T/grafana.ini"
  [ -z "${VARIANTE:-}" ] || sed -i "s/^\[security\]$/[security]\ndata_source_proxy_whitelist = 127.0.0.1:9090/" "$T/grafana.ini"
  echo "# variante : ${VARIANTE:-configuration en service} ; grafana.ini : $(grep -c data_source_proxy_whitelist "$T/grafana.ini") ligne de liste"
  mkdir -p "$T"/prov/{datasources,dashboards,plugins,alerting}
  sed "s#192.168.161.13#127.0.0.1#; s#/etc/grafana/tls/ca-poc.crt#$T/ca.crt#; s#/etc/grafana/tls/grafana-client#$T/client#" "$J19/config/provisioning/datasources/sources.yaml" > "$T/prov/datasources/sources.yaml"
  echo "# Loki $("$T/loki" -version 2>&1 | head -1 | cut -d' ' -f3), Grafana $("$T/grafana-13.3.0/bin/grafana" --version | cut -d' ' -f3)"
  unshare -rn bash "$here/banc-grafana.sh" ns; r=$?
  if [ "${VARIANTE:-}" = liste ]; then
    echo "## 8. systemd (gestionnaire utilisateur) : programme qui sort avec le code 0, relancé ?"
    for m in on-failure always; do
      systemd-run --user -q --unit "banc-kpi-$m" -p "Restart=$m" -p RestartSec=1s -p RemainAfterExit=no /usr/bin/sleep 1 2>&1
      sleep 7; n=$(systemctl --user show -p NRestarts --value "banc-kpi-$m" 2> /dev/null)
      systemctl --user stop "banc-kpi-$m" 2> /dev/null
      attendu "Restart=$m : relancé" "$([ "${n:-0}" -gt 0 ] && echo oui || echo non)" "$([ "$m" = always ] && echo oui || echo non)"
    done
    [ "$KO" = 0 ] || r=1
  fi
  [ "$r" = 0 ] || { echo "## fins de journaux (sans ligne de requête)"; grep -E 'lvl=eror|level=error' "$T/grafana.out" "$T/loki.out" | tail -4 | cut -c1-220; }
  exit "$r"
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
