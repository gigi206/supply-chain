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
B08=$here/../08b-rke2/config
A08B=$B08/audit-policy.yaml
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

  [ "$DISTRO" != rke2 ] || appoints

  echo "## valeurs de Cilium, rendues sans cluster"
  rendre_cilium hostFirewall
  [ "$ko" = 0 ] || { echo "KO   verifier" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
}

doublons() { sed -n 's/^\([a-z][a-z0-9-]*\):.*/\1/p' "$@" | sort | uniq -d | paste -sd' '; }   # clés sans +, posées dans deux fichiers au moins

appoints() { # readConfigFile de k3s : config.yaml, puis config.yaml.d par nom ; hors clé en +, la dernière valeur remplace les autres
  local d=$T/appoints n
  echo "## appoints de RKE2 sur sc-confiance : noms relevés sur le nœud, fichiers versionnés, sans lire config.yaml"
  rm -rf -- "${d:?}"; mkdir -p "$d"
  cp "$C/durcissement.yaml" "$C/kubelet.yaml" "$d/"
  cp "$B08/sc-confiance-pod-security.yaml" "$d/pod-security.yaml"
  for n in $(sur sc-confiance "sudo ls $D_CONF/config.yaml.d"); do
    if [ -f "$d/$n" ]; then echo "OK   appoint du nœud, versionné : $n"; else echo "KO   appoint du nœud, inconnu : $n"; ko=1; fi
  done
  attendu "clés sans + posées deux fois" "$(doublons "$B08/sc-confiance.yaml" "$d"/*.yaml)" ""
  attendu "fichier d'admission effectif" "$(sed -n 's/^pod-security-admission-config-file: //p' "$B08/sc-confiance.yaml" "$d"/*.yaml | tail -n 1)" "$D_CONF/pod-security.yaml"
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

demarrage_apiserver() { kubectl get pod -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].status.containerStatuses[0].state.running.startedAt}' 2>/dev/null || true; }

reprendre_rattrapage() { kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":false}}' >/dev/null; trap - EXIT; }

suspendre_rattrapage() { # comme kata.sh : aucun passage ni PipelineRun actif pendant les redémarrages, CronJob rétabli à la sortie
  local n
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":true}}' >/dev/null
  trap reprendre_rattrapage EXIT
  for _ in $(seq 60); do [ -z "$(kubectl get cronjob -n declencheurs rattrapage -o jsonpath='{.status.active}')" ] && break; sleep 2; done
  n=$(kubectl get pipelineruns -n builds -o json | jq '[.items[] | select(.status.completionTime == null)] | length')
  [ "$n" = 0 ] || { echo "KO   $n PipelineRun(s) actif(s) : redémarrage reporté" >&2; exit 1; }
}

temoins() { # mêmes témoins que kata.sh exemption
  local i
  sonde_kyverno
  for i in $(seq 30); do kubectl exec -n openbao openbao-0 -- true >/dev/null 2>&1 && break; sleep 2; done
  attendu "OpenBao descellé" "$(kubectl exec -n openbao openbao-0 -- bao status -format=json 2>/dev/null | jq -r .sealed || true)" false
  mise run confiance:openbao -- controle
  mise run confiance:tsa -- temoin
}

rafale_evenements() { # Events réels : EventRateLimit ignore le dry-run. Au moins un 429 prouve que les limites sont chargées
  local f=$T/evenement.json n
  jq -n '{apiVersion: "v1", kind: "Event", metadata: {name: "essai-h1-@N@", namespace: "default", labels: {essai: "08c-h1"}},
    involvedObject: {apiVersion: "v1", kind: "Namespace", name: "default", namespace: "default"},
    reason: "EssaiH1", message: "rafale de la 08c", type: "Normal", source: {component: "essai-h1"}}' > "$f"
  seq 200 | xargs -P 16 -I{} sh -c "sed s/@N@/{}/ '$f' | kubectl create -f - 2>&1" > "$T/rafale.out" || true
  n=$(grep -c 'TooManyRequests' "$T/rafale.out" || true)
  grep -m 1 'TooManyRequests' "$T/rafale.out" | cut -c1-200 || true
  kubectl delete events -n default -l essai=08c-h1 --ignore-not-found >/dev/null
  if [ "$n" -ge 1 ]; then echo "OK   EventRateLimit : $n refus sur 200 événements"; else echo "KO   EventRateLimit : aucun refus sur 200 événements"; ko=1; fi
}

etape_h1_api() {
  exige_rke2
  local a d v
  echo "## état avant"
  temoins
  suspendre_rattrapage
  a=$(demarrage_apiserver)
  echo "kube-apiserver démarré à $a"
  copier sc-confiance /tmp/durcissement "$C/durcissement.yaml" "$C/kubelet.yaml" "$C/admission.yaml"
  sur sc-confiance "sudo install -m 0600 /tmp/durcissement/admission.yaml $D_CONF/pod-security.yaml \
    && sudo install -m 0600 /tmp/durcissement/durcissement.yaml /tmp/durcissement/kubelet.yaml $D_CONF/config.yaml.d/ && sudo rm -rf /tmp/durcissement"
  d=$(date +%s)
  sur sc-confiance "sudo systemctl restart --no-block $D_SERVEUR"
  # /readyz peut répondre sur l'ancien kube-apiserver : attendre un autre démarrage, et ne pas toucher aux agents sinon
  for _ in $(seq 150); do
    v=$(demarrage_apiserver)
    [ -n "$v" ] && [ "$v" != "$a" ] && kubectl get --raw /readyz >/dev/null 2>&1 && break
    v=""; sleep 2
  done
  [ -n "$v" ] || { echo "KO   kube-apiserver non relancé en 300 s, agents non touchés : journal du pod statique, retrait au README" >&2; exit 1; }
  echo "kube-apiserver relancé à $v, API prête $(( $(date +%s) - d )) s après le redémarrage"
  for v in sc-build sc-stockage; do
    copier "$v" /tmp/durcissement "$C/kubelet.yaml"
    sur "$v" "sudo install -d -m 0700 $D_CONF/config.yaml.d && sudo install -m 0600 /tmp/durcissement/kubelet.yaml $D_CONF/config.yaml.d/ && sudo rm -rf /tmp/durcissement && sudo systemctl restart $D_AGENT"
  done
  kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null
  reprendre_rattrapage
  echo "## après"
  args_apiserver | grep -E -- '^--(request-timeout|service-account-lookup)=' || true
  attendu "plugins d'admission" "$(args_apiserver | grep -- '^--enable-admission-plugins=' || true)" "--enable-admission-plugins=NodeRestriction,DenyServiceExternalIPs,EventRateLimit"
  attendu "fichier d'admission" "$(args_apiserver | grep -- '^--admission-control-config-file=' || true)" "--admission-control-config-file=$D_CONF/pod-security.yaml"
  for v in sc-confiance sc-build sc-stockage; do
    attendu "kubelet de $v : pids, seccomp, événements" "$(kubectl get --raw "/api/v1/nodes/$v/proxy/configz" | jq -c '.kubeletconfig | [.podPidsLimit, .seccompDefault, .eventRecordQPS]')" "[4096,true,5]"
  done
  rafale_evenements
  temoins
  mise run confiance:kata -- temoin
  [ "$ko" = 0 ] || { echo "KO   h1_api" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
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
