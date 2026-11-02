#!/usr/bin/env bash
# Brique 19, jalon O2 (décisions du propriétaire du 02/11/2026) : Prometheus et Alertmanager en services durcis sur
# sc-stockage, collecte des cinq sources, en lecture seule.
#   telecharger   archives amont épinglées (gh release download) dans ~/.cache/supply-chain-poc/19/amont :
#                 sha256 figés ici ; Prometheus : attestation de release GitHub vérifiée (gh release verify-asset) ;
#                 Alertmanager : sha256 seul (aucune attestation ni signature publiée, limite consignée : décision 1)
#   certificats   dates d'expiration des certificats du PoC (PKI de la 08 sur l'hôte) en métriques (A6, décision 6)
#   compte        compte de lecture prometheus-lecture (cluster/lecture.yaml) ; droits mesurés : get sur services/proxy
#                 des trois services nommés, refus attendus (Secret, pod, autre service, création) ; jeton en 0600
#   installer     binaires revérifiés dans la VM, configurations, jetons (k3s depuis l'hôte, Forgejo copié dans la VM),
#                 quatre unités (prometheus, alertmanager, fichiers-metriques, recepteur-alertes)
#   cibles        toutes les cibles « up » dans l'API de Prometheus ; noms réels des métriques relevés par source
#   lecture_seule refus attendus : API d'administration, lifecycle, remote-write ; écoute sur 127.0.0.1 seulement
# Jalon O3 (règles, config/regles/) :
#   regles        promtool check rules et promtool test rules dans un répertoire temporaire de la VM (promtool installé
#                 en O2), sans déploiement
#   reference     requêtes en lecture sur Prometheus : début des données, refus de Kyverno et échecs de Chains sur
#                 l'historique (référence de A5 et A2), évaluation de chaque expression de alertes.yml avant déploiement
#   deployer      alertes.yml dans /etc/prometheus/regles/, redémarrage de Prometheus (lifecycle désactivé : pas de
#                 rechargement par l'API), règles chargées lues dans l'API
# Jalon O4 (incidents simulés, un par alerte ; chaque étape relève les changements d'état dans Prometheus et Alertmanager,
# puis les notifications firing et resolved reçues par le récepteur local) :
#   fichiers      fichiers.py servant aussi /etc/fichiers-metriques/*.prom (séries de test), service redémarré
#   a1            OpenBao redémarré, donc scellé (état mesuré en O2), puis descellé (procédure de J3) ; clé Transit
#                 inchangée ; reprise des CronJobs horodatage et rattrapage
#   a2            build de la 01 (commit sur custom/s5 du fork) pendant qu'OpenBao est scellé : échec de signature réel de
#                 Chains, puis descellement et purge des exécutions en échec (decision3 de la 08, premier choix, suppose le
#                 gabarit d'essai de J6, basculé en J8 : premier passage archivé)
#   a3, a4, a6    séries de test dans /etc/fichiers-metriques/essais-o4.prom, retour à la normale par la valeur, retirées
#   a5            rafales de créations refusées par Kyverno (dry-run serveur) : 4 refus (sous le seuil), puis 10
# Aucun secret en argument de commande : fichiers 0600 ou entrée standard.
#
# Usage (racine du dépôt) : mise run observabilite -- <étape>…   (journal : resultats/<jalon>-<étape>.log ; JALON=o4 pour
# rejouer regles ou deployer sans écraser les journaux d'O3)
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
trap 'rm -rf "$W/observabilite" "$W/entete"' EXIT   # copies de secrets, même en cas d'échec (convention de stockage.sh)

etape_telecharger() {
  local f
  [ -s "$A/$PROM_ARCHIVE" ] || gh release download "v$PROM_VERSION" -R prometheus/prometheus -p "$PROM_ARCHIVE" -D "$A"
  [ -s "$A/$AM_ARCHIVE" ] || gh release download "v$AM_VERSION" -R prometheus/alertmanager -p "$AM_ARCHIVE" -D "$A"
  (cd "$A" && printf '%s  %s\n%s  %s\n' "$PROM_SHA" "$PROM_ARCHIVE" "$AM_SHA" "$AM_ARCHIVE" | sha256sum -c)
  # Lie l'archive à la release v3.13.5 de prometheus/prometheus (attestation de release, prédicat release v0.2) ; ce n'est
  # pas une provenance de build. gh attestation verify ne la trouve pas (« no attestations found », premier passage du
  # 02/11/2026) : les attestations de release se vérifient par gh release verify-asset.
  gh release verify-asset "v$PROM_VERSION" "$A/$PROM_ARCHIVE" -R prometheus/prometheus 2>&1
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
    echo "can-i get services/$n --subresource=proxy -n $ns : $(kubectl auth can-i get "services/$n" --subresource=proxy -n "$ns" --as "$sa" 2>&1 || true)"
  done
  # Syntaxe de can-i pour un sous-ressource : services/<nom> --subresource=proxy (« services/proxy/<nom> » répond « no »
  # à tort : premier passage du 02/11/2026, archivé).
  for d in "get secrets -n openbao" "get secrets -n observabilite" "list pods -n kyverno" "get pods --subresource=log -n tekton-chains" \
           "create services/kyverno-svc-metrics:8000 --subresource=proxy -n kyverno" "get services/kyverno-svc:443 --subresource=proxy -n kyverno" \
           "get services/https:openbao:8201 --subresource=proxy -n openbao" "get services/kyverno-svc-metrics --subresource=proxy -n kyverno" \
           "get services/timestamp-authority:3000 --subresource=proxy -n tsa"; do
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
  [ -s "$S/zot-poc-metriques.password" ] || { echo "KO   mot de passe de poc-metriques absent (confiance:stockage -- zot)" >&2; exit 1; }
  cp "$A/$PROM_ARCHIVE" "$A/$AM_ARCHIVE" "$JETON" "$S/zot-poc-metriques.password" "$P/ca-poc.crt" "$W/certificats.prom" \
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
install -m 0640 -g prometheus zot-poc-metriques.password /etc/prometheus/secrets/zot.password
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

REGLES=$here/config/regles

etape_regles() {
  copier sc-stockage /tmp/regles-test "$REGLES/alertes.yml" "$REGLES/alertes-tests.yml"
  sur sc-stockage 'cd /tmp/regles-test && promtool --version | head -1 && promtool check rules alertes.yml && promtool test rules alertes-tests.yml; r=$?; cd / && rm -rf /tmp/regles-test; exit $r'
}

requete() { # expression PromQL (sans apostrophe) : résultat instantané, une ligne par série
  sur sc-stockage "curl -s -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=$1'" \
    | jq -r 'if .status != "success" then "ERREUR \(.error)" elif (.data.result | length) == 0 then "  (aucun résultat)" else .data.result[] | "  \(.metric | del(.__name__) | tostring) \(.value[1])" end'
}

etape_reference() {
  local d e
  d=$(requete 'prometheus_tsdb_lowest_timestamp_seconds' | awk '{print $2}')
  echo "début des données de Prometheus : $(date -u -d "@${d%.*}" +%Y-%m-%dT%H:%M:%SZ)"
  echo "## A5 : refus de Kyverno sur l'historique, par espace"
  requete 'sum by (resource_namespace) (increase(kyverno_admission_requests_total{request_allowed="false"}[3h]))'
  echo "## A5 : maximum, sur l'historique, des refus en 5 min (tous espaces)"
  requete 'max_over_time(sum(increase(kyverno_admission_requests_total{request_allowed="false"}[5m]))[3h:1m])'
  echo "## A5 : admissions acceptées sur l'historique (activité de référence)"
  requete 'sum(increase(kyverno_admission_requests_total{request_allowed="true"}[3h]))'
  echo "## A2 : échecs de signature de Chains sur l'historique"
  requete 'sum by (error_type) (increase(watcher_pipelinerun_signing_failures_total[3h]))'
  requete 'sum by (error_type) (increase(watcher_taskrun_signing_failures_total[3h]))'
  echo "## expressions de alertes.yml évaluées sur le Prometheus réel (règles non déployées)"
  while IFS= read -r e <&3; do   # descripteur 3 : ssh (requete) lirait sinon la suite de la liste sur l'entrée standard
    echo "- $e"
    requete "$e"
  done 3< <(sed -n 's/^ *expr: //p' "$REGLES/alertes.yml")
}

etape_deployer() {
  copier sc-stockage /tmp/regles-deploiement "$REGLES/alertes.yml"
  sur sc-stockage sudo bash -s <<'EOF2'
set -euo pipefail
install -m 0640 -g prometheus /tmp/regles-deploiement/alertes.yml /etc/prometheus/regles/alertes.yml
rm -rf /tmp/regles-deploiement
systemctl restart prometheus
sleep 5
systemctl is-active prometheus
EOF2
  sur sc-stockage "curl -s http://127.0.0.1:9090/api/v1/rules" \
    | jq -r '.data.groups[] | .file as $f | .rules[] | "  \($f)\t\(.name)\t\(.health)\t\(.state)"'
}

ESSAIS=/etc/fichiers-metriques/essais-o4.prom   # séries de test de A3, A4 et A6, retirées en fin d'étape

etape_fichiers() {
  copier sc-stockage /tmp/fichiers-o4 "$here/systemd/fichiers.py"
  sur sc-stockage sudo bash -s <<'EOF3'
set -euo pipefail
install -m 0644 /tmp/fichiers-o4/fichiers.py /usr/local/lib/observabilite/fichiers.py
rm -rf /tmp/fichiers-o4 /tmp/regles-mutation   # avec la copie laissée par le contrôle par mutation d'O3 (aucun secret)
systemctl restart fichiers-metriques
sleep 2
systemctl is-active fichiers-metriques
EOF3
  sleep 35   # une collecte
  requete 'up{job="fichiers"}'
  requete 'count by (__name__) ({job="fichiers", __name__!~"up|scrape_.*"})'
}

etat_alerte() { # nom : <état dans Prometheus>|<état dans Alertmanager>, « inactive|absente » hors incident
  local p a
  p=$(sur sc-stockage "curl -s http://127.0.0.1:9090/api/v1/alerts" | jq -r --arg n "$1" \
    '[.data.alerts[] | select(.labels.alertname == $n) | .state] | unique | if length == 0 then "inactive" else join(",") end')
  a=$(sur sc-stockage "curl -s http://127.0.0.1:9093/api/v2/alerts" | jq -r --arg n "$1" \
    '[.[] | select(.labels.alertname == $n) | .status.state] | unique | if length == 0 then "absente" else join(",") end')
  echo "$p|$a"
}

attendre() { # nom état-visé délai-en-s : chaque changement d'état, horodaté, jusqu'à l'état visé
  local n=$1 vise=$2 fin=$((SECONDS + $3)) e prec=""
  while [ $SECONDS -lt $fin ]; do
    e=$(etat_alerte "$n")
    [ "$e" = "$prec" ] || { echo "$(date -u +%H:%M:%S) $n : prometheus=${e%|*}, alertmanager=${e#*|}"; prec=$e; }
    [ "$e" = "$vise" ] && return 0
    sleep 5
  done
  echo "KO   $n : « $vise » non atteint en $3 s" >&2; return 1
}

recues() { # nom époque statut : notifications de ce statut reçues par le récepteur local depuis l'instant
  sur sc-stockage "sudo journalctl -u recepteur-alertes --since @$2 -o short-iso --no-pager" \
    | grep -F "\"alerte\": \"$1\"" | grep -F "\"statut\": \"$3\"" || true
}

attendre_recue() { # nom époque statut délai-en-s
  local fin=$((SECONDS + $4)) l
  while [ $SECONDS -lt $fin ]; do
    l=$(recues "$1" "$2" "$3")
    [ -n "$l" ] && { sed 's/^/  reçu : /' <<<"$l"; return 0; }
    sleep 5
  done
  echo "KO   $1 : aucune notification « $3 » reçue en $4 s" >&2; return 1
}

debut() { # nom : l'alerte doit être inactive avant l'incident
  local e
  e=$(etat_alerte "$1")
  [ "$e" = "inactive|absente" ] && echo "OK   $1 inactive avant l'incident" || { echo "KO   $1 déjà active : $e" >&2; exit 1; }
}
declenchee() { # nom époque délai-en-s : firing dans Prometheus, active dans Alertmanager, notification firing reçue
  attendre "$1" "firing|active" "$3" || exit 1
  attendre_recue "$1" "$2" firing 120 || exit 1
}
resolue() { # nom époque délai-en-s : retour à la normale, notification resolved reçue
  attendre "$1" "inactive|absente" "$3" || exit 1
  attendre_recue "$1" "$2" resolved 180 || exit 1
  echo "OK   $1 : déclenchée puis résolue, notifications firing et resolved reçues"
}

essai() { # séries… : fichier de test servi par fichiers-metriques (écriture atomique ; sans HELP ni TYPE)
  printf '%s\n' "$@" | sur sc-stockage "sudo sh -c 'cat > /etc/fichiers-metriques/.essais-o4 && mv /etc/fichiers-metriques/.essais-o4 $ESSAIS'"
  echo "$(date -u +%H:%M:%S) essais-o4.prom : $*"
}
essai_retirer() {
  sur sc-stockage "sudo rm -f $ESSAIS /etc/fichiers-metriques/.essais-o4"
  echo "$(date -u +%H:%M:%S) essais-o4.prom retiré"
}

etape_a3() { # contrat de la brique 10 : replay_dernier_resultat à 0, puis à 1
  local t0
  debut ReplayNonBitIdentique
  trap essai_retirer EXIT
  t0=$(date +%s)
  essai 'replay_dernier_resultat{projet="essai-o4"} 0'
  declenchee ReplayNonBitIdentique "$t0" 180
  essai 'replay_dernier_resultat{projet="essai-o4"} 1'
  resolue ReplayNonBitIdentique "$t0" 180
  trap - EXIT; essai_retirer
  echo "## collecte des fichiers pendant l'incident (minimum de up sur 10 min)"
  requete 'min_over_time(up{job="fichiers"}[10m])'
}

etape_a4() { # dernière réussite vieille de 25 h, puis rattrapée (horodatage présent)
  local t0
  debut MiroirEnRetard
  trap essai_retirer EXIT
  t0=$(date +%s)
  essai "sync_derniere_reussite_timestamp_seconds{projet=\"essai-o4\"} $((t0 - 90000))"
  declenchee MiroirEnRetard "$t0" 480
  essai "sync_derniere_reussite_timestamp_seconds{projet=\"essai-o4\"} $(date +%s)"
  resolue MiroirEnRetard "$t0" 180
  trap - EXIT; essai_retirer
  requete 'min_over_time(up{job="fichiers"}[10m])'
}

etape_a6() { # certificat à 20 jours de l'échéance, puis renouvelé (60 jours)
  local t0
  debut CertificatExpireBientot
  trap essai_retirer EXIT
  t0=$(date +%s)
  essai "certificat_expiration_timestamp_seconds{certificat=\"essai-o4\"} $((t0 + 20 * 86400))"
  declenchee CertificatExpireBientot "$t0" 180
  essai "certificat_expiration_timestamp_seconds{certificat=\"essai-o4\"} $(($(date +%s) + 60 * 86400))"
  resolue CertificatExpireBientot "$t0" 180
  trap - EXIT; essai_retirer
  requete 'min_over_time(up{job="fichiers"}[10m])'
}

refus_kyverno() { # n : n créations du pod de sonde de la 08 (tsa, sans nodeSelector) en dry-run serveur, refusées par Kyverno
  local i ok=0 msg img
  img=$(kubectl get deployment -n tsa timestamp-authority -o jsonpath='{.spec.template.spec.containers[0].image}')
  jq -n --arg i "$img" '{apiVersion: "v1", kind: "Pod", metadata: {name: "sonde-o4", namespace: "tsa"},
    spec: {automountServiceAccountToken: false, securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "sonde", image: $i, securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}}' > "$W/sonde-o4.json"
  for i in $(seq "$1"); do
    msg=$(kubectl create --dry-run=server -f "$W/sonde-o4.json" 2>&1 || true)
    grep -qF 'zone confiance : nodeSelector zone=confiance obligatoire' <<<"$msg" && ok=$((ok + 1))
  done
  echo "$(date -u +%H:%M:%S) rafale : $ok refus de zone-confiance sur $1 créations (dry-run serveur)"
  [ "$ok" = "$1" ] || { echo "KO   refus attendus : $1" >&2; exit 1; }
}
compteur_refus() { # compteur brut des refus (tous espaces) et valeur de l'expression de A5, après une collecte
  sleep 35
  echo "compteur brut des refus :"; requete 'sum(kyverno_admission_requests_total{request_allowed="false"})'
  echo "somme des hausses sur 5 min (extrapolée) :"; requete 'sum(increase(kyverno_admission_requests_total{request_allowed="false"}[5m]))'
}

etape_a5() {
  local t0 fin e
  debut KyvernoRefusAnormaux
  compteur_refus
  echo "## rafale sous le seuil : 4 refus, l'alerte doit rester inactive pendant toute la fenêtre de 5 min"
  refus_kyverno 4
  compteur_refus
  fin=$((SECONDS + 300))
  while [ $SECONDS -lt $fin ]; do
    e=$(etat_alerte KyvernoRefusAnormaux)
    [ "$e" = "inactive|absente" ] || { echo "KO   KyvernoRefusAnormaux $e après 4 refus" >&2; exit 1; }
    sleep 10
  done
  echo "maximum de l'expression sur 6 min :"
  requete 'max_over_time(sum(increase(kyverno_admission_requests_total{request_allowed="false"}[5m]))[6m:30s])'
  echo "OK   4 refus : KyvernoRefusAnormaux restée inactive"
  echo "## rafale au-dessus du seuil : 10 refus"
  t0=$(date +%s)
  refus_kyverno 10
  declenchee KyvernoRefusAnormaux "$t0" 180
  compteur_refus
  resolue KyvernoRefusAnormaux "$t0" 480
  echo "maximum de l'expression sur 8 min :"
  requete 'max_over_time(sum(increase(kyverno_admission_requests_total{request_allowed="false"}[5m]))[8m:30s])'
}

cle_chains_empreinte() { racine <<<'bao read -format=json transit/keys/chains' | jq -r '.data.keys["1"].public_key' | sha256sum | cut -c1-16; }
desceller_o4() { # descellement de J3 (clé sur l'entrée standard), puis pod prêt ; attend d'abord le pod en marche (sinon,
  # appelé tôt par le trap, le statut serait vide et le descellement sauté)
  local st
  for _ in $(seq 90); do
    [ "$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && break
    sleep 2
  done
  sleep 6   # au moins une sonde, comme etape_redemarrage de la 08
  st=$(kubectl exec -n openbao openbao-0 -- bao status -format=json 2>/dev/null || true)
  if [ "$(jq -r .sealed <<<"$st")" = true ]; then
    tr -d '\n' < "$S/openbao-descellement.b64" | kubectl exec -i -n openbao openbao-0 -- bao write -format=json sys/unseal key=- \
      | jq -c '(.data // .) | {sealed}'
  fi
  kubectl wait --for=condition=Ready pod/openbao-0 -n openbao --timeout=120s
}
passage_reussi() { # espace CronJob époque : un passage créé après l'instant, réussi (attente bornée à 6 min : concurrence Forbid,
  # un passage lancé pendant le scellement peut retarder le suivant)
  local j=""
  for _ in $(seq 72); do
    j=$(kubectl get jobs -n "$1" -o json | jq -r --arg c "$2" --arg t "$(date -u -d "@$3" +%Y-%m-%dT%H:%M:%SZ)" '[.items[]
      | select(any(.metadata.ownerReferences[]?; .name == $c) and .metadata.creationTimestamp > $t and (.status.succeeded // 0) > 0)]
      | .[0].metadata.name // empty')
    [ -n "$j" ] && { echo "OK   $1/$2 : passage $j réussi après le descellement"; return 0; }
    sleep 5
  done
  echo "KO   $1/$2 : aucun passage réussi depuis le descellement" >&2; return 1
}

etape_a1() {
  local t0 t1 c1 c2
  debut OpenBaoScelle
  c1=$(cle_chains_empreinte)
  echo "clé Transit chains avant : $c1…"
  trap desceller_o4 EXIT   # OpenBao jamais laissé scellé, même en cas d'échec
  t0=$(date +%s)
  echo "$(date -u +%H:%M:%S) incident : suppression du pod openbao-0 (il redémarre scellé)"
  kubectl delete pod -n openbao openbao-0 --wait=true >/dev/null
  declenchee OpenBaoScelle "$t0" 300
  echo "## branche de l'expression"
  requete 'vault_core_unsealed'
  requete 'up{job=~"openbao|kyverno"}'
  echo "## effets de bord pendant le scellement"
  kubectl get jobs -n horodatage -o json | jq -r --arg t "$(date -u -d "@$t0" +%Y-%m-%dT%H:%M:%SZ)" '.items[]
    | select(.metadata.creationTimestamp > $t) | "  horodatage/\(.metadata.name) réussi=\(.status.succeeded // 0) échoué=\(.status.failed // 0)"'
  echo "ChainsEchecSignature : $(etat_alerte ChainsEchecSignature)"
  t1=$(date +%s)
  echo "$(date -u +%H:%M:%S) retour : descellement"
  desceller_o4
  trap - EXIT
  resolue OpenBaoScelle "$t0" 300
  c2=$(cle_chains_empreinte)
  [ "$c1" = "$c2" ] && echo "OK   clé Transit chains inchangée ($c2…)" || { echo "KO   clé Transit chains : $c1… puis $c2…" >&2; exit 1; }
  passage_reussi horodatage horodatage "$t1"
  passage_reussi declencheurs rattrapage "$t1"
  echo "TSA : $(kubectl get deployment -n tsa timestamp-authority -o jsonpath='{.status.readyReplicas}/{.spec.replicas}') prêt(s)"
}

FORGEJO_HOTE=https://192.168.161.13:3000
FORK_S5=workspace/sample-app-sync   # fork de la brique 01, branche custom/s5 : build par le webhook du fork (D2 b de la 01)

objets_chains() { # PipelineRun : « type/nom signed=… retries=… » pour lui et ses TaskRuns
  { kubectl get pipelinerun -n builds "$1" -o json; kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$1" -o json | jq '.items[]'; } \
    | jq -r '"\(.kind)/\(.metadata.name) signed=\(.metadata.annotations["chains.tekton.dev/signed"] // "absente") retries=\(.metadata.annotations["chains.tekton.dev/retries"] // "-")"'
}

enveloppes_att() { # PipelineRun : pour lui et son TaskRun publier (exécutions à sujet image), présence d'une enveloppe de son UID
  # dans le tag .att de l'image (règle du contrôle exécutions/enveloppes de la 08, reproduite ici : ABSENTE ou COUVERTE)
  local img dg k n u l
  img=$(kubectl get pipelinerun -n builds "$1" -o json | jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value')
  dg=$(kubectl get pipelinerun -n builds "$1" -o json | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
  : > "$W/o4-uids"
  oras manifest fetch --ca-file "$P/ca-poc.crt" "$REG_HOTE/${img#*/}:sha256-${dg#sha256:}.att" > "$W/o4-att.json"
  for l in $(jq -r '.layers[].digest' "$W/o4-att.json"); do
    oras blob fetch --ca-file "$P/ca-poc.crt" --output - "$REG_HOTE/${img#*/}@$l" \
      | jq -r '.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId // empty' >> "$W/o4-uids"
  done
  echo "tag .att de ${img#*/}@${dg:7:12} : $(jq '.layers | length' "$W/o4-att.json") enveloppe(s)"
  { echo "pipelinerun $1 $(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.metadata.uid}')"
    kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$1,tekton.dev/pipelineTask=publier" -o json \
      | jq -r '.items[] | "taskrun \(.metadata.name) \(.metadata.uid)"'; } | while read -r k n u; do
    grep -qx -F "$u" "$W/o4-uids" && echo "  COUVERTE $k $n (${u:0:8})" || echo "  ABSENTE $k $n (${u:0:8}) : signed=$(kubectl get "$k" -n builds "$n" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')"
  done
  rm -f "$W/o4-att.json" "$W/o4-uids"
}

etape_a2() { # échec de signature réel : un build de la 01 pendant qu'OpenBao est scellé (incident prévu au protocole) ;
  # Chains v0.29.9 échoue en ouvert (deuxième passage) : l'alerte attendue est ChainsMarqueSansSignature (A2, second volet)
  local t0 t1 c c1 c2 pr st fin
  debut ChainsMarqueSansSignature
  debut ChainsEchecSignature
  echo "## compteurs d'échec avant"
  requete 'watcher_pipelinerun_signing_failures_total or watcher_taskrun_signing_failures_total'
  c1=$(cle_chains_empreinte)
  echo "clé Transit chains avant : $c1…"
  trap desceller_o4 EXIT   # OpenBao jamais laissé scellé, même en cas d'échec
  t0=$(date +%s)
  echo "$(date -u +%H:%M:%S) scellement : suppression du pod openbao-0"
  kubectl delete pod -n openbao openbao-0 --wait=true >/dev/null
  for _ in $(seq 90); do
    st=$(kubectl exec -n openbao openbao-0 -- bao status -format=json 2>/dev/null || true)
    [ "$(jq -r .sealed <<<"$st" 2>/dev/null)" = true ] && break
    sleep 2
  done
  [ "$(jq -r .sealed <<<"$st")" = true ] && echo "$(date -u +%H:%M:%S) OpenBao scellé" || { echo "KO   OpenBao pas scellé" >&2; exit 1; }
  echo "## build : commit poussé sur custom/s5 du fork par poc-dev"
  rm -rf "$W/o4-w"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    git clone -q "$FORGEJO_HOTE/$FORK_S5.git" "$W/o4-w"
  git -C "$W/o4-w" checkout -q origin/custom/s5   # branche protégée contre le force-push : avance rapide
  git -C "$W/o4-w" -c user.name="PoC brique 19" -c user.email=poc-dev@poc.test -c commit.gpgsign=false commit -q --allow-empty -m "brique 19, O4 : A2"
  c=$(git -C "$W/o4-w" rev-parse HEAD)
  # En-tête du jeton dans l'environnement de git, limité à l'URL du fork (jamais en argument), comme declencheur.sh de la 01.
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    GIT_CONFIG_KEY_1="http.$FORGEJO_HOTE/$FORK_S5.git.extraHeader" GIT_CONFIG_VALUE_1="Authorization: token $(cat "$S/forgejo-poc-dev.token")" \
    git -C "$W/o4-w" push -q "$FORGEJO_HOTE/$FORK_S5.git" HEAD:refs/heads/custom/s5
  rm -rf "$W/o4-w"
  pr=sample-app-sync-$c
  echo "$(date -u +%H:%M:%S) commit ${c:0:12} poussé"
  for _ in $(seq 60); do kubectl get pipelinerun -n builds "$pr" >/dev/null 2>&1 && break; sleep 2; done
  kubectl get pipelinerun -n builds "$pr" >/dev/null 2>&1 && echo "OK   PipelineRun $pr créé" || { echo "KO   aucun PipelineRun $pr" >&2; exit 1; }
  kubectl wait -n builds --for=condition=Succeeded "pipelinerun/$pr" --timeout=600s >/dev/null \
    || { kubectl get pipelinerun -n builds "$pr" -o json | jq -c '.status.conditions' >&2; exit 1; }
  echo "$(date -u +%H:%M:%S) build réussi : $(kubectl get pipelinerun -n builds "$pr" -o json | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')"
  echo "## Chains pendant le scellement (OpenBao gardé scellé jusqu'à l'issue de chaque objet, au plus 6 min)"
  fin=$((SECONDS + 360))
  while [ $SECONDS -lt $fin ]; do
    objets_chains "$pr" | grep -q 'signed=absente' || break
    sleep 5
  done
  objets_chains "$pr" | sed "s/^/  $(date -u +%H:%M:%S) /"
  declenchee ChainsMarqueSansSignature "$t0" 300
  echo "ChainsEchecSignature (premier volet, aveugle à cette panne) : $(etat_alerte ChainsEchecSignature)"
  echo "## compteurs de Chains pendant le scellement (hausse sur 10 min)"
  for m in pipelinerun_marked_signed pipelinerun_sign_created taskrun_marked_signed taskrun_sign_created pipelinerun_signing_failures taskrun_signing_failures; do
    echo "  $m : $(requete "sum(increase(watcher_${m}_total[10m]))" | awk '{print $2}')"
  done
  echo "## contrôle exécutions/enveloppes avant la purge"
  enveloppes_att "$pr"
  echo "## journal du contrôleur de Chains depuis le scellement (erreurs de signature, 10 premières)"
  kubectl logs -n tekton-chains deploy/tekton-chains-controller --since-time="$(date -u -d "@$t0" +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null \
    | grep -iE 'error|fail' | cut -c1-300 | head -10 | sed 's/^/  /' || true
  t1=$(date +%s)
  echo "$(date -u +%H:%M:%S) descellement"
  desceller_o4
  trap - EXIT
  c2=$(cle_chains_empreinte)
  [ "$c1" = "$c2" ] && echo "OK   clé Transit chains inchangée ($c2…)" || { echo "KO   clé Transit chains : $c1… puis $c2…" >&2; exit 1; }
  sleep 30
  echo "## objets après le descellement (une reprise de Chains serait visible ici)"
  objets_chains "$pr" | sed 's/^/  /'
  purger_pr "$pr"
  echo "exécutions $pr purgées (référence de la 08 gardée)"
  resolue OpenBaoScelle "$t0" 300
  resolue ChainsMarqueSansSignature "$t0" 900
  echo "## compteurs d'échec à la fin"
  requete 'watcher_pipelinerun_signing_failures_total or watcher_taskrun_signing_failures_total'
  echo "ChainsEchecSignature pendant tout l'incident : $(recues ChainsEchecSignature "$t0" firing | grep -c . || true) notification(s)"
  passage_reussi horodatage horodatage "$t1"
  passage_reussi declencheurs rattrapage "$t1"
}

etapes=("$@")
[ ${#etapes[@]} -gt 0 ] || { echo "usage : $0 <telecharger|certificats|compte|installer|cibles|lecture_seule|regles|reference|deployer|fichiers|a1|a2|a3|a4|a5|a6>…" >&2; exit 2; }
for e in "${etapes[@]}"; do
  declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }
  case $e in regles|reference|deployer) jalon=${JALON:-o3} ;; fichiers|a[1-6]) jalon=o4 ;; *) jalon=o2 ;; esac
  {
    echo "# observabilite.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    "etape_$e"
  } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R19/$jalon-$e.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
done
