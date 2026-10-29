#!/usr/bin/env bash
# Banc A1 : forge de test Forgejo 15.0.11 (binaire vérifié, mise.toml), hors du cluster.
# - Écoute sur la passerelle IPv4 du réseau docker `kind` seulement : joignable par les
#   pods, pas depuis le réseau local. SQLite, pas d'inscription, mode hors ligne.
# - Webhooks autorisés vers loopback seulement : PaC est publié sur 127.0.0.1:8180.
# - Mot de passe administrateur et jeton d'API dans des fichiers 0600, jamais dans les journaux.
#
# Usage (racine du dépôt) : mise run konflux:forgejo [-- stop]
set -euo pipefail
export LC_ALL=C

PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
F=${FORGEJO_DIR:-$HOME/.cache/supply-chain-poc/forgejo}
cfg=$F/custom/conf/app.ini
fg() { forgejo -c "$cfg" -w "$F" "$@"; }

if [ "${1:-}" = stop ]; then
  [ ! -f "$F/forgejo.pid" ] || { kill "$(cat "$F/forgejo.pid")" 2>/dev/null || true; rm -f "$F/forgejo.pid"; }
  exit 0
fi
gw=$(docker network inspect kind --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 -E '^[0-9.]+$')
url=http://$gw:3000

if [ ! -f "$cfg" ]; then
  umask 077
  mkdir -p "$F/custom/conf" "$F/data" "$F/log"
  cat > "$cfg" <<EOF
APP_NAME = Forgejo (banc A1)
RUN_MODE = prod
WORK_PATH = $F

[server]
PROTOCOL = http
HTTP_ADDR = $gw
HTTP_PORT = 3000
DOMAIN = $gw
ROOT_URL = $url/
DISABLE_SSH = true
OFFLINE_MODE = true
LFS_START_SERVER = false

[database]
DB_TYPE = sqlite3
PATH = $F/data/forgejo.db

[repository]
ROOT = $F/data/repos

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
  echo "OK   Forgejo initialisé dans $F (administrateur « banc », secrets en 0600)"
fi

if ! curl -fsS -m 2 "$url/api/healthz" >/dev/null 2>&1; then
  setsid nohup forgejo -c "$cfg" -w "$F" web > "$F/log/web.out" 2>&1 < /dev/null &
  echo $! > "$F/forgejo.pid"
  for _ in $(seq 1 30); do curl -fsS -m 2 "$url/api/healthz" >/dev/null 2>&1 && break; sleep 1; done
fi
curl -fsS -m 2 "$url/api/healthz" >/dev/null && echo "OK   $(forgejo --version | cut -d' ' -f1-3) sur $url (pid $(cat "$F/forgejo.pid"))"
ss -ltnH | awk '$4 ~ /:3000$/ {print "     écoute : " $4}'
