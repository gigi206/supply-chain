#!/usr/bin/env bash
# Brique 08c : durcissement du cluster RKE2, après le rejeu de la 08b. Une étape à la fois, pour qu'un échec soit attribuable.
#   verifier  à sec, sur l'hôte : politique d'audit simulée, règles Kyverno jouées par le CLI sur des pods d'essai, manifestes validés par l'API en
#             dry-run ; ne change rien au cluster, y compris sous k3s
#   h1_api    plugins d'admission, EventRateLimit, kubelet : fichiers d'appoint, redémarrage de RKE2 (accord)
#   h2_kyverno  règles en Audit (accord)
#   h3_audit  pare-feu d'hôte et politiques de Cilium en mode audit, sans blocage (accord ; console virsh prête)
#   h4_bloque fin du mode audit (accord, après revue des verdicts relevés en h3)
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08c-durcissement/durcissement.sh <étape>…   (journal : resultats/durcissement-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
b08=$here/../08-trust-plane
. "$b08/commun.sh"
C=$here/config
A08B=$here/../08b-rke2/config/audit-policy.yaml
T=$W/durcissement
ko=0
mkdir -p "$T"

attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }
exige_rke2() { [ "$DISTRO" = rke2 ] || { echo "KO   étape réservée à DISTRO=rke2" >&2; exit 1; }; }

audit_json() { # YAML vers JSON par le moteur de gabarits de Helm : l'hôte n'a pas d'analyseur YAML
  rm -rf -- "${T:?}/c"; mkdir -p "$T/c/templates"
  printf 'apiVersion: v2\nname: c\nversion: 0.0.1\n' > "$T/c/Chart.yaml"
  cp "$A08B" "$T/c/a.yaml"
  # shellcheck disable=SC2016
  printf '%s\n' '{{ (.Files.Get "a.yaml" | fromYaml) | toJson }}' > "$T/c/templates/a.yaml"
  helm template c "$T/c" | sed -n '/^{/p'
}

etape_verifier() {
  local f n v cas
  echo "## politique d'audit : première règle qui correspond, sur des cas prédits"
  audit_json > "$T/audit.json"
  python3 -I - "$T/audit.json" <<'PY' | tee "$T/audit.txt"
import fnmatch, json, sys
r = json.load(open(sys.argv[1]))["rules"]
def niveau(u, v, g, x):
    for i in r:
        if "users" in i and u not in i["users"]: continue
        if "verbs" in i and v not in i["verbs"]: continue
        if "nonResourceURLs" in i: continue
        if "resources" in i:
            ok = any(j.get("group", "") == g and ("resources" not in j or x in j["resources"]) for j in i["resources"])
            if not ok: continue
        return i["level"]
    return "ABSENT"
ctl = "system:serviceaccount:tekton-chains:tekton-chains-controller"
for c, a in [
    (("alice", "get", "", "secrets"), "Metadata"), ((ctl, "get", "", "secrets"), "Metadata"),
    (("system:kube-controller-manager", "get", "", "secrets"), "Metadata"), (("alice", "create", "", "secrets"), "Metadata"),
    (("alice", "patch", "", "configmaps"), "Metadata"), (("alice", "create", "", "serviceaccounts/token"), "Metadata"),
    (("alice", "create", "", "pods/exec"), "RequestResponse"), (("alice", "get", "", "pods/exec"), "RequestResponse"),
    (("alice", "patch", "rbac.authorization.k8s.io", "clusterroles"), "RequestResponse"),
    (("alice", "delete", "policies.kyverno.io", "validatingpolicies"), "RequestResponse"),
    (("alice", "create", "cilium.io", "ciliumclusterwidenetworkpolicies"), "RequestResponse"),
    (("alice", "create", "", "pods"), "Request"), (("alice", "create", "tekton.dev", "pipelineruns"), "Request"),
    (("alice", "patch", "tekton.dev", "taskruns/status"), "Metadata"), (("alice", "get", "", "pods"), "Metadata"),
    (("system:kube-scheduler", "get", "", "pods"), "None"), (("alice", "watch", "", "pods"), "None"),
    (("alice", "create", "coordination.k8s.io", "leases"), "None"),
]:
    n = niveau(*c); print(("OK  " if n == a else "KO  "), n, *c)
print("règles :", len(r), ", dernière :", r[-1])
for i in r:
    if i["level"] in ("Request", "RequestResponse"):
        for j in i.get("resources", []):
            assert not ({"secrets", "configmaps", "serviceaccounts/token"} & set(j.get("resources", []))), j
print("OK   aucun corps de requête pour les Secrets, les ConfigMaps et les jetons")
PY
  grep -q '^KO' "$T/audit.txt" && ko=1
  grep -q '^OK   aucun corps' "$T/audit.txt" || ko=1

  echo "## règles Kyverno, CLI sur des pods d'essai (attendu dans le nom : -pass ou -fail)"
  for f in "$here"/essais/*.yaml; do
    n=$(basename "$f" .yaml)
    kyverno apply "$here/politiques/kyverno/durcissement.yaml" --resource "$f" --policy-report --output-format json > "$T/cli.json" 2> "$T/cli.err" || true
    v=$(jq -c '[.results[]? // .[]?.results[]? | select(.policy == "'"${n%%--*}"'") | .result] | unique' "$T/cli.json" 2>/dev/null || echo erreur)
    cas=${n##*-}
    attendu "$n" "$v" "[\"$cas\"]"
  done

  echo "## manifestes validés par l'API en service (dry-run : rien n'est créé)"
  for f in "$here"/politiques/cilium/*.yaml "$here"/politiques/kyverno/*.yaml; do
    if kubectl apply --dry-run=server -f "$f" > "$T/dry.out" 2>&1; then echo "OK   $(basename "$f") : $(wc -l < "$T/dry.out") objet(s)"
    else echo "KO   $(basename "$f") : $(tail -1 "$T/dry.out")"; ko=1; fi
  done

  echo "## valeurs de Cilium, rendues sans cluster"
  rendre_cilium hostFirewall
  [ "$ko" = 0 ] || { echo "KO   verifier" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
}

rendre_cilium() {
  local c=$O/telechargements/cilium v=$T/valeurs.yaml
  sed -e 's/^#.*//' -e 's#@CILIUM_AMD64@#sha256:fa56fecd779584642c7ec2da6872c03c45c1f1043da66665a73ed8c425584d54#' \
      -e 's#@OPERATOR_AMD64@#sha256:77a9b4371faed41dc9c2fb3942b6c02a581158be1d4aa46a0e62956ce2f55ff1#' "$b08/cilium/valeurs.yaml" > "$v"
  for e in valeurs-cilium-audit valeurs-cilium valeurs-cilium-wireguard; do
    helm template cilium "$c/cilium-1.20.4.tgz" --namespace kube-system -f "$v" -f "$here/../08b-rke2/config/valeurs-cilium.yaml" -f "$C/$e.yaml" \
      | grep -E '^  (enable-host-firewall|policy-audit-mode|enable-wireguard|enable-encryption-strict-mode-egress|encryption-strict-egress-cidr|enable-l7-proxy|kube-proxy-replacement): ' \
      | tr -s ' ' | sort | paste -sd';' | sed "s/^/$e :/"
  done
}

etape_h1_api() {
  exige_rke2
  copier sc-confiance /tmp/durcissement "$C/durcissement.yaml" "$C/kubelet.yaml" "$C/admission.yaml"
  sur sc-confiance "sudo install -m 0600 /tmp/durcissement/admission.yaml $D_CONF/admission.yaml \
    && sudo install -m 0600 /tmp/durcissement/durcissement.yaml /tmp/durcissement/kubelet.yaml $D_CONF/config.yaml.d/ && sudo rm -rf /tmp/durcissement"
  sur sc-confiance "sudo systemctl restart $D_SERVEUR"
  for _ in $(seq 120); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 2; done
  for v in sc-build sc-stockage; do
    copier "$v" /tmp/durcissement "$C/kubelet.yaml"
    sur "$v" "sudo install -d -m 0700 $D_CONF/config.yaml.d && sudo install -m 0600 /tmp/durcissement/kubelet.yaml $D_CONF/config.yaml.d/ && sudo rm -rf /tmp/durcissement && sudo systemctl restart $D_AGENT"
  done
  kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null
  args_apiserver | grep -E -- '^--(enable-admission-plugins|admission-control-config-file|request-timeout|service-account-lookup)='
}

etape_h2_kyverno() {
  exige_rke2
  kubectl apply --server-side -f "$here/politiques/kyverno/durcissement.yaml"
}

etape_h3_audit() {
  exige_rke2
  VALEURS_08C=$C/valeurs-cilium-audit.yaml "$b08/cilium.sh" appliquer
  kubectl apply --server-side -f "$here/politiques/cilium/"
  echo "relevé des verdicts : cilium-dbg monitor -t policy-verdict sur chaque nœud, et Hubble"
}

etape_h4_bloque() {
  exige_rke2
  VALEURS_08C=$C/valeurs-cilium.yaml "$b08/cilium.sh" appliquer
  mise run confiance:preuves -- test6
}

for e in "$@"; do
  { echo "# durcissement.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ), DISTRO=$DISTRO"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/durcissement-$e.log"
  [ "${PIPESTATUS[0]}" = 0 ] || exit 1
done
