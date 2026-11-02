#!/usr/bin/env bash
# Brique 19, jalon O2 (décisions du propriétaire du 02/11/2026) : Prometheus et Alertmanager en services durcis sur
# sc-stockage, collecte des cinq sources, en lecture seule.
#   telecharger   archives amont épinglées (gh release download) dans ~/.cache/supply-chain-poc/19/amont :
#                 sha256 figés ici ; Prometheus : attestation de release GitHub vérifiée (gh attestation verify) ;
#                 Alertmanager : sha256 seul (aucune attestation ni signature publiée, limite consignée : décision 1)
#   certificats   dates d'expiration des certificats du PoC (PKI de la 08 sur l'hôte) en métriques (A6, décision 6)
#   compte        compte de lecture prometheus-lecture (cluster/lecture.yaml) ; droits mesurés : get sur services/proxy
#                 des trois services nommés, refus attendus (Secret, pod, autre service, création) ; jeton en 0600
#   installer     binaires revérifiés dans la VM, configurations, jetons (k3s depuis l'hôte, Forgejo copié dans la VM),
#                 quatre unités (prometheus, alertmanager, fichiers-metriques, recepteur-alertes)
#   cibles        toutes les cibles « up » dans l'API de Prometheus ; noms réels des métriques relevés par source
#   lecture_seule refus attendus : API d'administration, lifecycle, remote-write ; écoute sur 127.0.0.1 seulement
# Aucun secret en argument de commande : fichiers 0600 ou entrée standard.
#
# Usage (racine du dépôt) : mise run observabilite -- <étape>…   (journal : resultats/o2-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"   # sur, copier, refus, IP, P (PKI), S (secrets), W
R19=$here/resultats
A=$HOME/.cache/supply-chain-poc/19/amont
PROM_VERSION=3.13.5
PROM_ARCHIVE=prometheus-$PROM_VERSION.linux-amd64.tar.gz
PROM_SHA=0388822ace519c5a3a8ef556a541ce1b536e21d872f82deded465bd27a5a0699   # sha256sums.txt de v3.13.5, relevé le 02/11/2026
AM_VERSION=0.34.2
AM_ARCHIVE=alertmanager-$AM_VERSION.linux-amd64.tar.gz
AM_SHA=17ee14acd0f6ba6e25a436ff223d9c17ddd5cf484f543ad12f0932eaa89ba186     # sha256sums.txt de v0.34.2, relevé le 02/11/2026
API=https://192.168.161.11:6443
JETON=$S/prometheus-lecture.token
mkdir -p "$A" "$R19"

etape_telecharger() {
  local f
  [ -s "$A/$PROM_ARCHIVE" ] || gh release download "v$PROM_VERSION" -R prometheus/prometheus -p "$PROM_ARCHIVE" -D "$A"
  [ -s "$A/$AM_ARCHIVE" ] || gh release download "v$AM_VERSION" -R prometheus/alertmanager -p "$AM_ARCHIVE" -D "$A"
  (cd "$A" && printf '%s  %s\n%s  %s\n' "$PROM_SHA" "$PROM_ARCHIVE" "$AM_SHA" "$AM_ARCHIVE" | sha256sum -c)
  # Lie l'archive à la release v3.13.5 de prometheus/prometheus (prédicat release v0.2) ; ce n'est pas une provenance de build.
  gh attestation verify "$A/$PROM_ARCHIVE" --repo prometheus/prometheus \
    --predicate-type https://in-toto.io/attestation/release/v0.2 2>&1
  echo "Alertmanager : sha256 seul (aucune attestation ni signature publiée : limite consignée, décision 1)"
  for f in "$PROM_ARCHIVE" "$AM_ARCHIVE"; do tar -tzf "$A/$f" | sed "s#^#  $f : #" | grep -E '/(prometheus|promtool|alertmanager|amtool)$'; done
}

etape_certificats() {
  local f n e
  : > "$W/certificats.prom"
  {
    echo "# HELP certificat_expiration_timestamp_seconds Fin de validité (notAfter) du certificat, PKI de la brique 08."
    echo "# TYPE certificat_expiration_timestamp_seconds gauge"
    for f in ca-poc zot forgejo openbao tsa-feuille tsa-racine; do
      [ -s "$P/$f.crt" ] || { echo "KO   $P/$f.crt absent" >&2; exit 1; }
      e=$(date -u -d "$(openssl x509 -in "$P/$f.crt" -noout -enddate | cut -d= -f2)" +%s)
      echo "certificat_expiration_timestamp_seconds{certificat=\"$f\"} $e"
    done
  } > "$W/certificats.prom"
  sed "s#^#  #" "$W/certificats.prom"
}

etape_compte() {
  local sa=system:serviceaccount:observabilite:prometheus-lecture ns n
  kubectl apply --server-side -f "$here/cluster/lecture.yaml"
  for _ in $(seq 30); do
    [ -n "$(kubectl -n observabilite get secret prometheus-lecture-jeton -o jsonpath='{.data.token}' 2>/dev/null)" ] && break
    sleep 1
  done
  (umask 077 && kubectl -n observabilite get secret prometheus-lecture-jeton -o jsonpath='{.data.token}' | base64 -d > "$JETON")
  [ -s "$JETON" ] || { echo "KO   jeton du compte absent" >&2; exit 1; }
  echo "jeton du compte en 0600 sur l'hôte"
  # Droits déclarés, lus par l'API (kubectl auth can-i), puis par une vraie requête avec le jeton.
  for ns_n in kyverno/kyverno-svc-metrics:8000 tekton-chains/tekton-chains-metrics:9090 openbao/https:openbao:8200; do
    ns=${ns_n%%/*}; n=${ns_n#*/}
    echo "can-i get services/proxy/$n -n $ns : $(kubectl auth can-i get "services/proxy/$n" -n "$ns" --as "$sa" 2>&1 || true)"
  done
  for d in "get secrets -n openbao" "get secrets -n observabilite" "list pods -n kyverno" "get pods/log -n tekton-chains" \
           "create services/proxy/kyverno-svc-metrics:8000 -n kyverno" "get services/proxy/kyverno-svc:443 -n kyverno" \
           "get services/proxy/https:openbao:8201 -n openbao" "get services/proxy/timestamp-authority:3000 -n tsa"; do
    # shellcheck disable=SC2086
    echo "can-i $d : $(kubectl auth can-i $d --as "$sa" 2>&1 || true)"
  done
  (umask 077 && printf 'Authorization: Bearer %s\n' "$(cat "$JETON")" > "$W/entete")
  kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$W/k8s-ca.crt"
  for u in /api/v1/namespaces/kyverno/services/kyverno-svc-metrics:8000/proxy/metrics \
           /api/v1/namespaces/tekton-chains/services/tekton-chains-metrics:9090/proxy/metrics \
           "/api/v1/namespaces/openbao/services/https:openbao:8200/proxy/v1/sys/metrics?format=prometheus" \
           /api/v1/namespaces/openbao/secrets /api/v1/namespaces/kyverno/services/kyverno-svc:443/proxy/; do
    echo "GET $u : HTTP $(curl -s -o /dev/null -w '%{http_code}' --cacert "$W/k8s-ca.crt" -H @"$W/entete" "$API$u" || true)"
  done
  rm -f "$W/entete"
}

etape_installer() {
  local d=$W/observabilite
  [ -s "$JETON" ] || { echo "KO   jeton absent (étape compte)" >&2; exit 1; }
  [ -s "$W/certificats.prom" ] || { echo "KO   certificats.prom absent (étape certificats)" >&2; exit 1; }
  rm -rf "$d" && (umask 077 && mkdir -p "$d")
  kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$d/k8s-ca.crt"
  cp "$A/$PROM_ARCHIVE" "$A/$AM_ARCHIVE" "$JETON" "$P/ca-poc.crt" "$W/certificats.prom" \
     "$here/config/prometheus.yml" "$here/config/alertmanager.yml" "$here"/systemd/*.service "$here"/systemd/*.py "$d/"
  copier sc-stockage /tmp/observabilite-installation "$d"/*
  sur sc-stockage sudo bash -s <<EOF
set -euo pipefail
cd /tmp/observabilite-installation
printf '%s  %s\n%s  %s\n' "$PROM_SHA" "$PROM_ARCHIVE" "$AM_SHA" "$AM_ARCHIVE" | sha256sum -c
tar -xzf "$PROM_ARCHIVE" && tar -xzf "$AM_ARCHIVE"
for u in prometheus alertmanager; do id \$u >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/\$u --no-create-home --shell /usr/sbin/nologin \$u; done
install -m 0755 prometheus-$PROM_VERSION.linux-amd64/prometheus prometheus-$PROM_VERSION.linux-amd64/promtool /usr/local/bin/
install -m 0755 alertmanager-$AM_VERSION.linux-amd64/alertmanager alertmanager-$AM_VERSION.linux-amd64/amtool /usr/local/bin/
install -d -m 0750 -g prometheus /etc/prometheus /etc/prometheus/secrets /etc/prometheus/regles
install -d -m 0750 -g alertmanager /etc/alertmanager
install -d -m 0755 /etc/fichiers-metriques /usr/local/lib/observabilite
install -m 0640 -g prometheus prometheus.yml /etc/prometheus/prometheus.yml
install -m 0644 k8s-ca.crt /etc/prometheus/k8s-ca.crt
install -m 0644 ca-poc.crt /etc/prometheus/ca-poc.crt
install -m 0640 -g prometheus prometheus-lecture.token /etc/prometheus/secrets/k8s.token
install -m 0640 -g prometheus /etc/forgejo/secrets/metrics_token /etc/prometheus/secrets/forgejo.token
install -m 0640 -g alertmanager alertmanager.yml /etc/alertmanager/alertmanager.yml
install -m 0644 certificats.prom /etc/fichiers-metriques/certificats.prom
install -m 0644 fichiers.py recepteur.py /usr/local/lib/observabilite/
install -m 0644 prometheus.service alertmanager.service fichiers-metriques.service recepteur-alertes.service /etc/systemd/system/
cd / && rm -rf /tmp/observabilite-installation
/usr/local/bin/prometheus --version 2>&1 | head -1
/usr/local/bin/alertmanager --version 2>&1 | head -1
systemctl daemon-reload
for u in recepteur-alertes fichiers-metriques alertmanager prometheus; do systemctl enable \$u 2>&1; systemctl restart \$u; done
sleep 3
systemctl is-active recepteur-alertes fichiers-metriques alertmanager prometheus
EOF
  rm -rf "$d"
}

etape_cibles() {
  sleep 35   # un intervalle de collecte (30 s) écoulé
  sur sc-stockage "curl -s http://127.0.0.1:9090/api/v1/targets" \
    | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.health)\t\(.lastError)"' | sort | tee "$W/cibles.tsv"
  for j in kyverno chains openbao zot forgejo fichiers; do
    echo "## $j : noms des métriques"
    sur sc-stockage "curl -s -G http://127.0.0.1:9090/api/v1/label/__name__/values --data-urlencode 'match[]={job=\"$j\"}'" \
      | jq -r '.data[]' | { grep -vE '^(go|process|promhttp|scrape|up)_|^up$' || true; } | sed 's/^/  /' | head -60 || true
  done
  if awk -F'\t' '$2 != "up"' "$W/cibles.tsv" | grep -q .; then echo "KO   cible(s) en échec" >&2; exit 1; fi
  echo "OK   toutes les cibles up"
}

etape_lecture_seule() {
  sur sc-stockage "
    echo \"POST /api/v1/admin/tsdb/delete_series : HTTP \$(curl -s -o /dev/null -w %{http_code} -X POST -G http://127.0.0.1:9090/api/v1/admin/tsdb/delete_series --data-urlencode 'match[]=up')\"
    echo \"POST /-/reload : HTTP \$(curl -s -o /dev/null -w %{http_code} -X POST http://127.0.0.1:9090/-/reload)\"
    echo \"POST /-/quit : HTTP \$(curl -s -o /dev/null -w %{http_code} -X POST http://127.0.0.1:9090/-/quit)\"
    echo \"POST /api/v1/write : HTTP \$(curl -s -o /dev/null -w %{http_code} -X POST http://127.0.0.1:9090/api/v1/write)\"
    echo '## écoute'
    sudo ss -ltnp | grep -E ':(9090|9093|9094|9095|9101) ' | awk '{print \$4, \$6}'
    systemctl is-active prometheus"
}

etapes=("$@")
[ ${#etapes[@]} -gt 0 ] || { echo "usage : $0 <telecharger|certificats|compte|installer|cibles|lecture_seule>…" >&2; exit 2; }
for e in "${etapes[@]}"; do
  declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }
  {
    echo "# observabilite.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    "etape_$e"
  } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R19/o2-$e.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
done
