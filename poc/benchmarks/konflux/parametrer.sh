#!/usr/bin/env bash
# Banc A1 : règle les paramètres natifs des PipelineRuns que le build-service a proposés
# dans la PR de configuration (branche konflux-sample-app), par un commit sur cette branche :
# - hermetic=true et prefetch-input gomod + npm (le Containerfile lit /cachi2) ;
# - source-date-epoch=0 et rewrite-timestamp=true (reproductibilité, critère A-3) ;
# - image de sortie sous registry-service.kind-registry (nom couvert par le certificat du registre).
# Le push déclenche le pipeline de PR (événement pull_request synchronisé).
#
# Usage (racine du dépôt) : mise run konflux:parametrer
set -euo pipefail
export LC_ALL=C

F=${FORGEJO_DIR:-$HOME/.cache/supply-chain-poc/forgejo}
W=${WORKDIR:-$HOME/.cache/supply-chain-poc/konflux/parametrage}
BRANCHE=konflux-sample-app
gw=$(docker network inspect kind --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 -E '^[0-9.]+$')

rm -rf "$W"
mkdir -p "$W"
chmod 700 "$W"
GIT_CONFIG_VALUE_0="Authorization: token $(tr -d '\n' < "$F/admin.token")"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0 \
  GIT_CONFIG_KEY_1=http.sslCAInfo GIT_CONFIG_VALUE_1="$F/tls/ca.crt"
export GIT_AUTHOR_NAME="banc A1" GIT_AUTHOR_EMAIL=banc@localhost GIT_COMMITTER_NAME="banc A1" GIT_COMMITTER_EMAIL=banc@localhost

git clone -q --branch "$BRANCHE" "https://$gw:3000/banc/sample-app.git" "$W/sample-app"
python3 -I - "$W"/sample-app/.tekton/sample-app-*.yaml <<'PY'
import sys
ajout = '''  - name: hermetic
    value: "true"
  - name: prefetch-input
    value: '[{"type": "gomod", "path": "."}, {"type": "npm", "path": "web"}]'
  - name: source-date-epoch
    value: "0"
  - name: rewrite-timestamp
    value: "true"
'''
ancre = "  - name: path-context\n    value: .\n  pipelineSpec:\n"
for p in sys.argv[1:]:
    s = open(p).read()
    # Le certificat du registre interne couvre registry-service.kind-registry, pas la forme .svc.cluster.local.
    s = s.replace("registry-service.kind-registry.svc.cluster.local/", "registry-service.kind-registry/")
    open(p, "w").write(s)
    if "  - name: hermetic\n    value:" in s.split("  pipelineSpec:")[0]:
        continue
    assert s.count(ancre) == 1, p
    open(p, "w").write(s.replace(ancre, ancre.replace("  pipelineSpec:\n", ajout + "  pipelineSpec:\n")))
PY
git -C "$W/sample-app" diff --stat
git -C "$W/sample-app" commit -qam "Banc A1 : build hermétique, prefetch gomod et npm, SOURCE_DATE_EPOCH=0"
git -C "$W/sample-app" push -q origin "$BRANCHE"
echo "OK   $BRANCHE : $(git -C "$W/sample-app" rev-parse HEAD)"
