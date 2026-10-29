#!/usr/bin/env bash
# Banc A1 : forge de test Forgejo 15.0.11 (binaire vérifié, mise.toml), hors du cluster.
#
# Le build-service de Konflux refuse les dépôts en HTTP et cherche les identifiants par
# un label qui porte l'hôte de l'URL, port compris (« 172.19.0.1:3000 » n'est pas une
# valeur de label valide). Sans réglage système, Forgejo est donc publié dans le cluster
# par un Service sans sélecteur, https://forgejo.banc-a1.svc.cluster.local (port 443),
# dont l'EndpointSlice pointe sur la passerelle du réseau docker `kind` (port 3000).
# Le certificat est émis par la CA de Konflux (ClusterIssuer konflux-issuer), déjà
# diffusée dans tous les espaces de noms par le bundle trusted-ca.
#
# - Écoute sur la passerelle IPv4 du réseau `kind` seulement : joignable par les pods,
#   pas depuis le réseau local. SQLite, pas d'inscription, mode hors ligne.
# - Webhooks autorisés vers loopback seulement : PaC est publié sur 127.0.0.1:8180.
# - Mot de passe administrateur, jeton d'API et clé TLS en 0600, jamais dans les journaux.
#
# Usage (racine du dépôt, cluster démarré) : mise run konflux:forgejo [-- stop]
set -euo pipefail
export LC_ALL=C

PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
export KUBECONFIG=$HOME/.kube/supply-chain-poc-konflux.yaml
F=${FORGEJO_DIR:-$HOME/.cache/supply-chain-poc/forgejo}
NS=banc-a1
HOST=forgejo.$NS.svc.cluster.local
cfg=$F/custom/conf/app.ini
fg() { forgejo -c "$cfg" -w "$F" "$@"; }

if [ "${1:-}" = stop ]; then
  [ ! -f "$F/forgejo.pid" ] || { kill "$(cat "$F/forgejo.pid")" 2>/dev/null || true; rm -f "$F/forgejo.pid"; }
  exit 0
fi
gw=$(docker network inspect kind --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 -E '^[0-9.]+$')

# Publication dans le cluster et certificat.
kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NS
---
apiVersion: v1
kind: Service
metadata:
  name: forgejo
  namespace: $NS
spec:
  ports:
  - name: https
    port: 443
    targetPort: 3000
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: forgejo-hote
  namespace: $NS
  labels:
    kubernetes.io/service-name: forgejo
addressType: IPv4
ports:
- name: https
  port: 3000
endpoints:
- addresses: ["$gw"]
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: forgejo
  namespace: $NS
spec:
  secretName: forgejo-tls
  duration: 720h
  dnsNames: [$HOST, forgejo.$NS.svc]
  ipAddresses: ["$gw"]
  issuerRef:
    kind: ClusterIssuer
    name: konflux-issuer
EOF
kubectl wait -n "$NS" --for=condition=Ready certificate/forgejo --timeout=120s >/dev/null
umask 077
mkdir -p "$F/tls" "$F/custom/conf" "$F/data" "$F/log"
for k in tls.crt tls.key ca.crt; do
  kubectl get secret -n "$NS" forgejo-tls -o jsonpath="{.data.${k//./\\.}}" | base64 -d > "$F/tls/$k"
done
echo "OK   certificat $(openssl x509 -in "$F/tls/tls.crt" -noout -subject -ext subjectAltName | tr '\n' ' ' | sed 's/  */ /g') ; émetteur $(openssl x509 -in "$F/tls/tls.crt" -noout -issuer)"

if [ ! -f "$cfg" ]; then
  cat > "$cfg" <<EOF
APP_NAME = Forgejo (banc A1)
RUN_MODE = prod
WORK_PATH = $F

[server]
PROTOCOL = https
HTTP_ADDR = $gw
HTTP_PORT = 3000
DOMAIN = $HOST
ROOT_URL = https://$HOST/
CERT_FILE = $F/tls/tls.crt
KEY_FILE = $F/tls/tls.key
DISABLE_SSH = true
OFFLINE_MODE = true
LFS_START_SERVER = false

[database]
DB_TYPE = sqlite3
PATH = $F/data/forgejo.db

[repository]
ROOT = $F/data/repos
DEFAULT_BRANCH = main

[security]
INSTALL_LOCK = true
SECRET_KEY = $(forgejo generate secret SECRET_KEY)
INTERNAL_TOKEN = $(forgejo generate secret INTERNAL_TOKEN)

[oauth2]
JWT_SECRET = $(forgejo generate secret JWT_SECRET)

[service]
DISABLE_REGISTRATION = true

[webhook]
ALLOWED_HOST_LIST = loopback

[mailer]
ENABLED = false

[cron.update_checker]
ENABLED = false

[log]
ROOT_PATH = $F/log
MODE = file
LEVEL = Info
EOF
  fg migrate > "$F/log/migrate.out" 2>&1
  fg admin user create --admin --username banc --email banc@localhost --random-password --random-password-length 32 \
    --must-change-password=false 2>/dev/null | sed -n "s/^generated random password is '\(.*\)'$/\1/p" > "$F/admin.password"
  [ -s "$F/admin.password" ] || { echo "KO   mot de passe administrateur non relevé" >&2; exit 1; }
  fg admin user generate-access-token --username banc --token-name banc-a1 --scopes all --raw > "$F/admin.token"
  echo "OK   Forgejo initialisé (administrateur « banc », secrets en 0600)"
fi

api() { curl -fsS -m 3 --cacert "$F/tls/ca.crt" --resolve "$HOST:3000:$gw" "https://$HOST:3000/api/$1"; }
if ! api healthz >/dev/null 2>&1; then
  setsid nohup forgejo -c "$cfg" -w "$F" web > "$F/log/web.out" 2>&1 < /dev/null &
  echo $! > "$F/forgejo.pid"
  for _ in $(seq 1 30); do api healthz >/dev/null 2>&1 && break; sleep 1; done
fi
api healthz >/dev/null && echo "OK   Forgejo $(api v1/version | jq -r .version) : écoute $gw:3000 (pid $(cat "$F/forgejo.pid")), publié https://$HOST"
