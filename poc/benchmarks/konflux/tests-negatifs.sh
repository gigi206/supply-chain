#!/usr/bin/env bash
# Banc A1 : tests négatifs du doc 01 transposés à Konflux (règle A-2 : un contrôle absent
# compte « non bloqué »). Journal : resultats/tests-negatifs.log.
#
# - T1, T2, T3, T4, T6 : PR « tests-negatifs » qui déclare dans .tekton/ un PipelineRun hostile
#   (tests-negatifs/tests-negatifs.yaml), seul moyen offert aux tenants de lancer un build ;
#   T3 aussi par RBAC (utilisateur authentifié du tenant et compte de build).
# - T5 : webhook non signé, webhook à signature fausse, puis rejeu à l'identique d'une
#   livraison valide archivée par Forgejo (ouverture de la PR) ; on compte les PipelineRuns.
# - T8 : configuration de Chains (horodatage, journal de transparence).
# T7 (artefact non signé, ou ne portant que des attestations) : ec-tests.sh, après un build signé.
#
# Usage (racine du dépôt, Konflux, Forgejo et sample-app embarqués) : mise run konflux:tests-negatifs
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
PATH=$(tr : '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd:)
export KUBECONFIG=$HOME/.kube/supply-chain-poc-konflux.yaml
F=${FORGEJO_DIR:-$HOME/.cache/supply-chain-poc/forgejo}
W=${WORKDIR:-$HOME/.cache/supply-chain-poc/konflux/tests-negatifs}
NS=default-tenant
BRANCHE=tests-negatifs
gw=$(docker network inspect kind --format '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -m1 -E '^[0-9.]+$')
base=https://$gw:3000

rm -rf "$W"
mkdir -p "$W"
chmod 700 "$W"
exec > >(sed -u "s#$HOME#~#g" | tee "$R/tests-negatifs.log") 2>&1
echo "# tests-negatifs.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
umask 077
printf 'Authorization: token %s\n' "$(tr -d '\n' < "$F/admin.token")" > "$W/entete"
api() { curl -fsS --cacert "$F/tls/ca.crt" -H @"$W/entete" -H 'Content-Type: application/json' "$@"; }
runs() { kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/original-prname=$1" --no-headers 2>/dev/null | wc -l; }
attendre_run() { # $1 = nombre de PipelineRuns attendu, $2 = nom d'origine ; affiche le plus récent
  local n
  for _ in $(seq 1 60); do n=$(runs "$2"); [ "$n" -ge "$1" ] && break; sleep 5; done
  kubectl get pipelineruns -n "$NS" -l "pipelinesascode.tekton.dev/original-prname=$2" --sort-by=.metadata.creationTimestamp -o name | tail -1
}

# PR hostile.
GIT_CONFIG_VALUE_0=$(cat "$W/entete")
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0 \
  GIT_CONFIG_KEY_1=http.sslCAInfo GIT_CONFIG_VALUE_1="$F/tls/ca.crt"
export GIT_AUTHOR_NAME="banc A1" GIT_AUTHOR_EMAIL=banc@localhost GIT_COMMITTER_NAME="banc A1" GIT_COMMITTER_EMAIL=banc@localhost
api -X DELETE "$base/api/v1/repos/banc/sample-app/branches/$BRANCHE" >/dev/null 2>&1 || true
git clone -q --branch main "$base/banc/sample-app.git" "$W/depot"
mkdir -p "$W/depot/.tekton"
cp "$here/tests-negatifs/tests-negatifs.yaml" "$W/depot/.tekton/"
git -C "$W/depot" checkout -q -b "$BRANCHE"
git -C "$W/depot" add .tekton
git -C "$W/depot" commit -qm "Tests négatifs du banc A1"
git -C "$W/depot" push -q origin "$BRANCHE" 2>/dev/null
avant=$(runs tests-negatifs)
pr=$(api -X POST "$base/api/v1/repos/banc/sample-app/pulls" -d "{\"head\": \"$BRANCHE\", \"base\": \"main\", \"title\": \"Tests négatifs\"}" | jq -r .number)
echo "PR n° $pr ouverte (branche $BRANCHE, commit $(git -C "$W/depot" rev-parse --short HEAD))"
run=$(attendre_run $((avant + 1)) tests-negatifs)
[ -n "$run" ] || { echo "KO   aucun PipelineRun pour la PR hostile"; exit 1; }
echo "T2 : $run créé par PaC depuis .tekton/ avec un taskSpec inline (aucun refus à l'admission)"
kubectl wait -n "$NS" --for=condition=Succeeded=True "$run" --timeout=600s >/dev/null 2>&1 \
  || kubectl wait -n "$NS" --for=condition=Succeeded=False "$run" --timeout=60s >/dev/null 2>&1 || true
echo "état : $(kubectl get -n "$NS" "$run" -o jsonpath='{.status.conditions[0].reason} {.status.conditions[0].message}')"
pod=$(kubectl get pods -n "$NS" -l "tekton.dev/pipelineRun=${run#*/}" -o name | head -1)
kubectl logs -n "$NS" "$pod" --all-containers --prefix=false 2>&1 | grep -E '^T[0-9]' || echo "(pas de journal : $(kubectl get -n "$NS" "$pod" -o jsonpath='{.status.phase}'))"
cle=$(kubectl get secret -n tekton-pipelines signing-secrets -o jsonpath='{.data.cosign\.key}' | base64 -d | sha256sum | cut -c1-64)
echo "référence : sha256 de cosign.key du secret tekton-pipelines/signing-secrets (lu par l'administrateur) = $cle"
echo "PSA du tenant : $(kubectl get ns "$NS" -o json | jq -c '.metadata.labels | with_entries(select(.key | startswith("pod-security")))')"

# T3 par RBAC.
for who in "user2@konflux.dev --as-group=system:authenticated" "system:serviceaccount:$NS:build-pipeline-sample-app"; do
  read -r -a as <<<"$who"
  for v in "patch taskruns.tekton.dev --subresource=status" "update pipelineruns.tekton.dev --subresource=status" "create taskruns.tekton.dev" "create pods" "get secrets"; do
    read -r -a verbe <<<"$v"
    echo "RBAC ${as[0]##*:} : $v -n $NS -> $(kubectl auth can-i "${verbe[@]}" -n "$NS" --as="${as[0]}" "${as[@]:1}" 2>&1 | head -1)"
  done
done

# T5 : webhooks. Livraison de référence : ouverture de la PR hostile (pull_request opened).
python3 -I - "$F/data/forgejo.db" "$pr" "$W" <<'PY'
import json, sqlite3, sys
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
for rid, req, payload in db.execute("select id, request_content, payload_content from hook_task where event_type = 'pull_request' and is_succeed = 1 order by id desc"):
    p = json.loads(payload)
    if p.get("action") == "opened" and str(p.get("number")) == sys.argv[2]:
        r = json.loads(req)
        open(f"{sys.argv[3]}/corps.json", "w").write(r["body"])
        hs = r["headers"]
        open(f"{sys.argv[3]}/entetes-valides", "w").write("".join(f"{k}: {v}\n" for k, v in hs.items()))
        open(f"{sys.argv[3]}/entetes-sans-signature", "w").write("".join(f"{k}: {v}\n" for k, v in hs.items() if "ignature" not in k))
        open(f"{sys.argv[3]}/entetes-signature-fausse", "w").write("".join(f"{k}: {'0' * 64 if 'ignature' in k and 'Hub' not in k else v}\n" for k, v in hs.items() if 'Hub' not in k))
        print(f"livraison de référence : hook_task {rid}, X-Forgejo-Delivery {hs.get('X-Forgejo-Delivery')}")
        break
else:
    sys.exit("livraison d'ouverture de PR introuvable")
PY
envoyer() { curl -s -o "$W/reponse" -w '%{http_code}' -X POST -H @"$W/$1" --data-binary @"$W/corps.json" http://127.0.0.1:8180/; }
for cas in sans-signature signature-fausse valides; do
  avant=$(runs tests-negatifs)
  code=$(envoyer "entetes-$cas")
  sleep 20
  apres=$(runs tests-negatifs)
  echo "T5 $cas : HTTP $code ($(head -c 120 "$W/reponse" | tr '\n' ' ')), PipelineRuns de la PR hostile : $avant -> $apres"
done
kubectl logs -n tekton-pipelines deploy/pipelines-as-code-controller --since=2m 2>/dev/null \
  | jq -r 'select(.level == "error" or .level == "warn") | .msg' 2>/dev/null | grep -iE 'signature|secret' | sort | uniq -c | sed 's/^/     PaC : /'

# T8 : horodatage.
kubectl get cm -n tekton-pipelines chains-config -o json | jq -r '.data | to_entries[] | select(.key | test("transparency|timestamp|tsa|rekor|fulcio")) | "T8 chains-config : \(.key)=\(.value)"'
kubectl get cm -n tekton-pipelines chains-config -o json | jq -e '.data | keys | map(select(test("timestamp|tsa"))) | length > 0' >/dev/null \
  || echo "T8 : aucun horodatage RFC 3161 configuré dans Chains (contrôle absent)"
