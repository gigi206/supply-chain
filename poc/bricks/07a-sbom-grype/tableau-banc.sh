#!/usr/bin/env bash
# Brique 07b, ADR 0004 (« Oui, un tableau ») : banc jetable du tableau de bord « Vulnérabilités et VEX » avant sa pose.
# Grafana 13.3.0, archive déjà téléchargée et vérifiée par la 19b (~/.cache/supply-chain-poc/19b/amont, sha256 revérifié ici),
# lancé sur l'hôte en utilisateur, dans un espace de noms réseau vide (unshare -rn, boucle locale seule) : rien n'est installé,
# rien ne sort, ni VM, ni cluster, ni Zot. Données et archive extraite dans ~/.cache/supply-chain-poc/07b/banc-tableau, effacées
# à la fin. Mesure :
#   1. Grafana démarre sans fournisseur de tableaux ; puis tableaux.yaml (chemin réécrit vers le banc) et le JSON sont déposés et
#      POST /api/admin/provisioning/dashboards/reload (administrateur, Basic) les prend en compte sans redémarrage ;
#   2. le tableau est servi : uid, titre, 10 panneaux, dossier PoC, marqué provisionné ;
#   3. un enregistrement par l'administrateur est refusé (allowUiUpdates: false), une suppression aussi (disableDeletion) ;
#   4. un compte Viewer lit le tableau et ne peut pas l'enregistrer.
# Les requêtes des panneaux ne sont pas jouées ici (Prometheus absent du banc) : elles sont validées à part par l'auditeur.
# Usage (racine du dépôt) : bash poc/bricks/07a-sbom-grype/tableau-banc.sh <journal>
set -uo pipefail
export LC_ALL=C
J=$1
here=$(cd "$(dirname "$0")" && pwd)
C19=$here/../19b-journalisation/config/provisioning
V=13.3.0
A=$HOME/.cache/supply-chain-poc/19b/amont/grafana_13.3.0_40412481033_linux_amd64.tar.gz
SHA=cec8f98cc59bc1a1945833b652371a073be678c5c159a9b1695ad63c04fae5a7   # GRAFANA_SHA de journalisation.sh (19b)
W=$HOME/.cache/supply-chain-poc/07b/banc-tableau
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
mkdir -p "$W"/{prov/datasources,prov/dashboards,prov/plugins,prov/alerting,data,logs,plugins}
(umask 077 && head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$W/admin.password" && head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$W/lecteur.password")
cat > "$W/prov/datasources/sources.yaml" <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9
    isDefault: true
    editable: false
EOF
cat > "$W/essai.sh" <<'EOS'
set -uo pipefail
W=$1; V=$2; C19=$3
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
ip link set lo up
export GF_PATHS_DATA=$W/data GF_PATHS_LOGS=$W/logs GF_PATHS_PLUGINS=$W/plugins GF_PATHS_PROVISIONING=$W/prov
export GF_SERVER_HTTP_ADDR=127.0.0.1 GF_SERVER_HTTP_PORT=13001 GF_ANALYTICS_REPORTING_ENABLED=false GF_ANALYTICS_CHECK_FOR_UPDATES=false
export GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false GF_NEWS_NEWS_FEED_ENABLED=false GF_AUTH_ANONYMOUS_ENABLED=false GF_LOG_MODE=file
GF_SECURITY_ADMIN_PASSWORD=$(cat "$W/admin.password") "$W/grafana-$V/bin/grafana" server --homepath "$W/grafana-$V" > "$W/logs/sortie.txt" 2>&1 &
pid=$!
for i in $(seq 90); do curl -fs -o /dev/null http://127.0.0.1:13001/api/health && break; sleep 1; done
attendu "Grafana démarré (santé)" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:13001/api/health)" 200
echo "version : $(curl -s http://127.0.0.1:13001/api/health | jq -r .version)"
adm() { printf 'user = "admin:%s"\n' "$(cat "$W/admin.password")" | curl -sS -K - -o "$W/r.json" -w '%{http_code}' -H 'Content-Type: application/json' "$@"; }
lec() { printf 'user = "lecteur:%s"\n' "$(cat "$W/lecteur.password")" | curl -sS -K - -o "$W/r.json" -w '%{http_code}' -H 'Content-Type: application/json' "$@"; }
attendu "avant le dépôt : tableau absent" "$(adm http://127.0.0.1:13001/api/dashboards/uid/vulnerabilites-vex)" 404
mkdir -p "$W/prov/dashboards/tableaux"
sed "s#/etc/grafana/provisioning/dashboards/tableaux#$W/prov/dashboards/tableaux#" "$C19/dashboards/tableaux.yaml" > "$W/prov/dashboards/tableaux.yaml"
attendu "seule ligne réécrite dans le fournisseur" "$(diff "$C19/dashboards/tableaux.yaml" "$W/prov/dashboards/tableaux.yaml" | grep -c '^>')" 1
cp "$C19/dashboards/tableaux/vulnerabilites-vex.json" "$W/prov/dashboards/tableaux/"
attendu "rechargement du provisionnement (administrateur)" "$(adm -X POST http://127.0.0.1:13001/api/admin/provisioning/dashboards/reload)" 200
echo "  réponse : $(jq -c . "$W/r.json")"
attendu "tableau servi après rechargement" "$(adm http://127.0.0.1:13001/api/dashboards/uid/vulnerabilites-vex)" 200
cp "$W/r.json" "$W/tableau.json"
attendu "titre" "$(jq -r .dashboard.title "$W/tableau.json")" "Vulnérabilités et VEX"
attendu "panneaux" "$(jq '.dashboard.panels | length' "$W/tableau.json")" 10
attendu "dossier" "$(jq -r .meta.folderTitle "$W/tableau.json")" PoC
attendu "marqué provisionné" "$(jq -r .meta.provisioned "$W/tableau.json")" true
attendu "panneaux identiques au fichier" "$(jq -S -c '[.dashboard.panels[] | {id, type, title, targets: [.targets[]?.expr]}]' "$W/tableau.json" | sha256sum | cut -c1-16)" \
  "$(jq -S -c '[.panels[] | {id, type, title, targets: [.targets[]?.expr]}]' "$C19/dashboards/tableaux/vulnerabilites-vex.json" | sha256sum | cut -c1-16)"
jq -c '{dashboard: (.dashboard | .title = "modifié"), overwrite: true}' "$W/tableau.json" > "$W/modif.json"
c=$(adm -X POST http://127.0.0.1:13001/api/dashboards/db -d @"$W/modif.json")
attendu "enregistrement par l'administrateur refusé" "$c" 400
echo "  message : $(jq -r .message "$W/r.json")"
c=$(adm -X DELETE http://127.0.0.1:13001/api/dashboards/uid/vulnerabilites-vex)
attendu "suppression par l'administrateur refusée" "$c" 400
echo "  message : $(jq -r .message "$W/r.json")"
jq -n --rawfile p "$W/lecteur.password" '{name: "lecteur", login: "lecteur", email: "lecteur@banc.test", password: ($p | rtrimstr("\n")), OrgId: 1}' > "$W/lecteur.json"
attendu "compte lecteur créé (Viewer par défaut)" "$(adm -X POST http://127.0.0.1:13001/api/admin/users -d @"$W/lecteur.json")" 200
attendu "le lecteur lit le tableau" "$(lec http://127.0.0.1:13001/api/dashboards/uid/vulnerabilites-vex)" 200
attendu "rôle du lecteur" "$(lec http://127.0.0.1:13001/api/user/orgs; jq -r '.[0].role' "$W/r.json")" "200Viewer"
attendu "enregistrement par le lecteur refusé" "$(lec -X POST http://127.0.0.1:13001/api/dashboards/db -d @"$W/modif.json")" 403
attendu "titre inchangé après les refus" "$(adm http://127.0.0.1:13001/api/dashboards/uid/vulnerabilites-vex; jq -r .dashboard.title "$W/r.json")" "200Vulnérabilités et VEX"
echo "lignes d'erreur du journal de Grafana sur le provisionnement : $(grep -ci 'level=error.*provisioning' "$W/logs/grafana.log" 2>/dev/null || echo 0)"
kill "$pid"; wait "$pid" 2>/dev/null
echo "## bilan : $N cas, $KO écart(s)"
EOS
{
echo "# banc du tableau « Vulnérabilités et VEX », Grafana $V, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
echo "fournisseur $(sha256sum < "$C19/dashboards/tableaux.yaml" | cut -c1-16)…, tableau $(sha256sum < "$C19/dashboards/tableaux/vulnerabilites-vex.json" | cut -c1-16)…"
s=$(sha256sum < "$A" | cut -c1-64)
if [ "$s" = "$SHA" ]; then echo "OK   sha256 de l'archive de Grafana : $s"; else echo "KO   sha256 de l'archive : $s (attendu $SHA)"; echo "## bilan : archive refusée"; exit 1; fi
tar -xzf "$A" -C "$W"
unshare -rn bash "$W/essai.sh" "$W" "$V" "$C19"
echo "fin : $(date -u +%FT%TZ)"
} > "$J" 2>&1
chmod -R u+w "$W" 2>/dev/null
find "$W" -delete
sed -i "s#$HOME#~#g" "$J"
cat "$J"
