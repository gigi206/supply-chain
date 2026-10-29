#!/usr/bin/env bash
# Banc A1, test négatif T6 selon la règle validée : sortie réseau en build hermétique.
# PR depuis la branche de configuration (PipelineRuns avec hermetic=true) dont le
# Containerfile ajoute un RUN qui ouvre une connexion TCP vers la passerelle du réseau kind
# (Forgejo, 3000). Attendu : le RUN échoue, donc le build échoue. Journal :
# resultats/t6-hermetique.log.
#
# Usage (racine du dépôt) : mise run konflux:t6-hermetique
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
export KUBECONFIG=$HOME/.kube/supply-chain-poc-konflux.yaml
F=${FORGEJO_DIR:-$HOME/.cache/supply-chain-poc/forgejo}
W=${WORKDIR:-$HOME/.cache/supply-chain-poc/konflux/t6}
NS=default-tenant
BRANCHE=t6-hermetique
gw=$(docker network inspect kind --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 -E '^[0-9.]+$')
base=https://$gw:3000

rm -rf "$W"
mkdir -p "$W"
chmod 700 "$W"
exec > >(sed -u "s#$HOME#~#g" | tee "$R/t6-hermetique.log") 2>&1
echo "# t6-hermetique.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
umask 077
printf 'Authorization: token %s\n' "$(tr -d '\n' < "$F/admin.token")" > "$W/entete"
api() { curl -fsS --cacert "$F/tls/ca.crt" -H @"$W/entete" -H 'Content-Type: application/json' "$@"; }
GIT_CONFIG_VALUE_0=$(cat "$W/entete")
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0 \
  GIT_CONFIG_KEY_1=http.sslCAInfo GIT_CONFIG_VALUE_1="$F/tls/ca.crt"
export GIT_AUTHOR_NAME="banc A1" GIT_AUTHOR_EMAIL=banc@localhost GIT_COMMITTER_NAME="banc A1" GIT_COMMITTER_EMAIL=banc@localhost

api -X DELETE "$base/api/v1/repos/banc/sample-app/branches/$BRANCHE" >/dev/null 2>&1 || true
git clone -q --branch konflux-sample-app "$base/banc/sample-app.git" "$W/depot"
git -C "$W/depot" checkout -q -b "$BRANCHE"
python3 -I - "$W/depot/Containerfile" "$gw" <<'PY'
import sys
p, gw = sys.argv[1], sys.argv[2]
s = open(p).read()
ancre = "COPY --from=web /src/web/dist web/dist\n"
assert s.count(ancre) == 1
sonde = (f"RUN timeout 10 bash -c 'echo > /dev/tcp/{gw}/3000' && echo 'T6 : connexion TCP ouverte pendant le build' "
         "|| { echo 'T6 : connexion TCP impossible pendant le build'; exit 1; }\n")
open(p, "w").write(s.replace(ancre, ancre + sonde))
PY
git -C "$W/depot" commit -qam "T6 : connexion réseau pendant un build hermétique"
git -C "$W/depot" push -q origin "$BRANCHE" 2>/dev/null
sha=$(git -C "$W/depot" rev-parse HEAD)
pr=$(api -X POST "$base/api/v1/repos/banc/sample-app/pulls" -d "{\"head\": \"$BRANCHE\", \"base\": \"main\", \"title\": \"T6 hermétique\"}" | jq -r .number)
echo "PR n° $pr, commit ${sha:0:12}, hermetic=$(awk '/- name: hermetic/ {getline; print $2; exit}' "$W/depot/.tekton/sample-app-pull-request.yaml")"
for _ in $(seq 1 60); do
  run=$(kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/sha=$sha" -o name | head -1)
  [ -n "$run" ] && break
  sleep 5
done
[ -n "${run:-}" ] || { echo "KO   aucun PipelineRun"; exit 1; }
tr=${run#*/}-build-container
for _ in $(seq 1 120); do
  kubectl get taskrun -n "$NS" "$tr" -o jsonpath='{.status.completionTime}' 2>/dev/null | grep -q . && break
  sleep 10
done
echo "$tr : $(kubectl get taskrun -n "$NS" "$tr" -o jsonpath='{.status.conditions[0].reason}')"
kubectl logs -n "$NS" "${tr}-pod" -c step-build 2>&1 | grep -E 'T6 :|/dev/tcp|unshare|--network' | grep -v 'RUN timeout' | head -5
kubectl patch pipelinerun -n "$NS" "${run#*/}" --type merge -p '{"spec":{"status":"Cancelled"}}' >/dev/null 2>&1 || true
