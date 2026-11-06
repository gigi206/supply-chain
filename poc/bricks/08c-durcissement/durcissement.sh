#!/usr/bin/env bash
# Brique 08c : durcissement du cluster RKE2, après le rejeu de la 08b. Une étape à la fois, pour qu'un échec soit attribuable.
#   verifier  à sec, sur l'hôte : politique d'audit simulée, règles Kyverno jouées par le CLI sur des pods d'essai, manifestes validés par l'API en
#             dry-run ; ne change rien au cluster, y compris sous k3s
#   h1_api    plugins d'admission, EventRateLimit, kubelet : fichiers d'appoint, redémarrage de RKE2 (accord)
#   h1_controle contrôles de h1_api, sans redémarrage ; crée deux pods d'essai et une rafale d'Events, retirés ensuite
#   h2_kyverno  règles en Audit (accord)
#   h2_releve écarts relevés, sans rien changer
#   h3_audit  pare-feu d'hôte et politiques de Cilium en mode audit, sans blocage (accord ; console virsh prête)
#   h3_releve verdicts audit des trois agents, sans rien changer
#   h3_resume relit les verdicts du dernier relevé
#   flux      verdicts et refus des trois agents pendant une construction, sans rien changer
#   h4_bloque fin du mode audit (accord, après revue des verdicts relevés en h3)
#   h5_sec    à sec : correctifs de limites, gabarits et règles en Deny présentés à l'API, couverture, essais de politiques ; ne change rien
#   h5_limites limites posées, règles encore en Audit (accord) ; CronJobs par minute suspendus, OpenBao redémarré puis descellé d'abord, puis Tekton, Chains, TSA, EventListener
#   h5_deny   quatre règles en Deny (accord, après une construction sous limites) ; retour : h2_kyverno
#   h5_tests_sec à sec : pods du test 4 et PipelineRun d'essai en dry-run serveur, décompte du test 8 ; ne change rien
#   h5_tests  tests 2, 4, 3, 1, 7 et 8 sous H1 à H5 (accord) ; gabarit en service inchangé, journaux preuves-h5-<test>.log de la 08
#   h5_roles_sec à sec : règles de politiques/roles en dry-run serveur, chart de Cilium rendu avec et sans la synchronisation de Secrets ; ne change rien
#   h5_roles  deux règles de politiques/roles (accord) ; contrôleurs de Triggers et agent de sc-build redémarrés ; retour : kubectl delete -f politiques/roles/roles.yaml
#   h5_cilium_sec à sec : chart rendu avec et sans la synchronisation de Secrets, documents Secret retirés, pods de Cilium en dry-run serveur, état de départ ; ne change rien
#   h5_cilium tls.secretSync.enabled=false (config/valeurs-cilium.yaml), agents et opérateur redémarrés (accord) ; retour : retirer la clé, cilium.sh appliquer
#   h6_sec    à sec : chart rendu avec et sans WireGuard, documents Secret retirés, règle du tunnel en dry-run serveur, module des nœuds, état de départ ; ne change rien
#   h6        WireGuard en mesure (accord) : politiques/cilium-h6 puis valeurs-cilium.yaml et valeurs-cilium-wireguard.yaml, agents redémarrés, coupure relevée ; retour : h6_retrait
#   h6_mesure construction de contrôle sous WireGuard (accord), en-têtes capturés sur sc-build, fragments et refus relevés ; journal preuves-h6-construction_durcie.log de la 08
#   h6_retrait retour à valeurs-cilium.yaml, puis retrait de la règle du tunnel (accord) ; le module wireguard reste chargé jusqu'au redémarrage des nœuds
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
BUSYBOX=$REG/amont/rancher/mirrored-library-busybox@sha256:ad9fa4d07136a83e69a54ef00102f579d04eba431932de3b0f098cc5d5948f9f
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
  etape_h1_controle
}

seccomp_pod() { # nom securityContext : champ Seccomp d'un pod runc de sc-build, dans kube-system, seul espace où un pod sans profil déclaré est admis
  jq -n --arg n "$1" --arg i "$BUSYBOX" --argjson s "$2" '{apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "kube-system"},
    spec: {nodeName: "sc-build", restartPolicy: "Never", automountServiceAccountToken: false, tolerations: [{operator: "Exists"}], securityContext: $s,
      containers: [{name: "c", image: $i, command: ["grep", "Seccomp:", "/proc/self/status"]}]}}' | kubectl apply -f - >/dev/null
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$1" -n kube-system --timeout=90s >/dev/null || true
  kubectl logs -n kube-system "$1" | awk '{print $2}'
  kubectl delete pod -n kube-system "$1" --wait=false >/dev/null
}

etape_h1_controle() { # contrôles de H1, sans redémarrage
  exige_rke2
  local v
  echo "## après"
  args_apiserver | grep -E -- '^--(request-timeout|service-account-lookup)=' || true
  # RKE2 écrit l'argument deux fois, le sien puis celui de config.yaml.d : le refus d'externalIPs et la rafale disent ce qui est chargé
  attendu "plugins d'admission, dernier argument" "$(args_apiserver | grep -- '^--enable-admission-plugins=' | tail -n 1 || true)" "--enable-admission-plugins=NodeRestriction,DenyServiceExternalIPs,EventRateLimit"
  attendu "fichier d'admission" "$(args_apiserver | grep -- '^--admission-control-config-file=' || true)" "--admission-control-config-file=$D_CONF/pod-security.yaml"
  attendu "externalIPs, à sec" "$(jq -n '{apiVersion: "v1", kind: "Service", metadata: {name: "essai-h1", namespace: "default"}, spec: {ports: [{port: 80}], externalIPs: ["192.0.2.1"]}}' \
    | kubectl create --dry-run=server -f - 2>&1 | grep -c 'denied by admission control' || true)" 1
  for v in sc-confiance sc-build sc-stockage; do # seccomp-default est un drapeau du kubelet, absent de configz : drapeau lu ici, effet mesuré par seccomp_pod
    attendu "kubelet de $v : pids, événements" "$(kubectl get --raw "/api/v1/nodes/$v/proxy/configz" | jq -c '.kubeletconfig | [.podPidsLimit, .eventRecordQPS]')" "[4096,5]"
    attendu "kubelet de $v : --seccomp-default=true" "$(sur "$v" "sudo pgrep -a -x kubelet | tr ' ' '\n' | grep -c -x -- --seccomp-default=true" || true)" 1
  done
  attendu "runc sans profil déclaré, Seccomp" "$(seccomp_pod essai-h1-defaut '{}')" 2
  attendu "témoin, Unconfined déclaré, Seccomp" "$(seccomp_pod essai-h1-temoin '{"seccompProfile": {"type": "Unconfined"}}')" 0
  rafale_evenements
  temoins
  mise run confiance:kata -- temoin
  [ "$ko" = 0 ] || { echo "KO   h1_controle" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
}

etape_h2_kyverno() {
  exige_rke2
  kubectl apply --server-side -f "$here/politiques/kyverno/durcissement.yaml"
}

etape_h2_releve() { # écarts des règles : pas de balayage de fond, donc les pods en service sont joués par le CLI, ceux créés depuis H2 lus dans les rapports
  exige_rke2
  local d=$T/h2 i=0 p t0
  t0=$(sed -n '1s/.*, \(20[^,]*\), DISTRO.*/\1/p' "$R/durcissement-h2_kyverno.log")
  echo "règles appliquées à $t0"
  rm -rf -- "${d:?}"; mkdir -p "$d/pods"
  kubectl get pods -A -o json > "$d/pods.json"
  jq -c '.items[] | select(.metadata.namespace | IN("kube-system", "kube-public", "kube-node-lease") | not)' "$d/pods.json" > "$d/lignes"
  while read -r p; do i=$((i+1)); printf '%s\n' "$p" | yq -P -o yaml > "$d/pods/$i.yaml"; done < "$d/lignes"
  kyverno apply "$here/politiques/kyverno/durcissement.yaml" --resource "$d/pods" --policy-report --output-format json > "$d/cli.json" 2> "$d/cli.err" || true
  echo "## pods en service, CLI : $i pods"
  jq -r '.results | group_by([.policy, .result]) | map("  \(.[0].policy) \(.[0].result) : \(length)") | .[]' "$d/cli.json"
  echo "## limites-obligatoires, échecs par espace, conteneurs sans limites relevés à part"
  jq -r '.results[] | select(.result == "fail") | .resources[0] | "\(.namespace)"' "$d/cli.json" | sort | uniq -c | sed 's/^ */  /'
  attendu "échecs du CLI et décompte direct" "$(jq '[.results[] | select(.policy == "limites-obligatoires" and .result == "fail")] | length' "$d/cli.json")" \
    "$(jq '[.items[] | select(.metadata.namespace | IN("kube-system", "kube-public", "kube-node-lease", "kyverno", "local-path-storage") | not)
      | select(any(.spec.containers[]; (.resources.limits.memory == null) or (.resources.limits.cpu == null)))] | length' "$d/pods.json")"
  echo "## pods créés depuis H2, rapports de Kyverno"
  kubectl get policyreports -A -o json | jq -r '[.items[].results[]? | select(.policy | IN("limites-obligatoires", "images-zot-par-digest", "espace-default-interdit", "jeton-compte-default"))]
    | group_by([.policy, .result]) | map("  \(.[0].policy) \(.[0].result) : \(length)") | .[]'
  echo "## rien de refusé depuis H2"
  kubectl get jobs -A -o json | jq -r --arg t "$t0" '[.items[] | select(.metadata.creationTimestamp > $t)] | group_by(.metadata.namespace)
    | map("  \(.[0].metadata.namespace) : \(length) Job(s) créé(s) depuis H2, \([.[] | select(.status.succeeded == 1)] | length) réussi(s)") | .[]'
  attendu "événements FailedCreate depuis H2" "$(kubectl get events -A --field-selector reason=FailedCreate -o json | jq --arg t "$t0" '[.items[] | select((.lastTimestamp // .eventTime) > $t)] | length')" 0
  echo "événements PolicyViolation depuis H2 : $(kubectl get events -A --field-selector reason=PolicyViolation -o json | jq --arg t "$t0" '[.items[] | select((.lastTimestamp // .eventTime) > $t)] | length')"
  [ "$ko" = 0 ] || { echo "KO   h2_releve" >&2; exit 1; }
  echo "RÉSULTAT : relevé fait"
}

etape_h3_audit() {
  exige_rke2
  VALEURS_08C=$C/valeurs-cilium-audit.yaml "$b08/cilium.sh" appliquer
  kubectl apply --server-side -f "$here/politiques/cilium/"
  attendu "pare-feu d'hôte et mode audit" "$(kubectl -n kube-system get cm cilium-config -o json | jq -c '[.data["enable-host-firewall"], .data["policy-audit-mode"]]')" '["true","true"]'
  kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
  [ "$ko" = 0 ] || { echo "KO   h3_audit" >&2; exit 1; }
}

verdicts() { # lignes de cilium-dbg monitor : ce qui serait refusé, regroupé ; le port source et l'identifiant de flux sont retirés
  sed -n -E 's/.*remote ID ([^,]+), proto ([0-9]+), (ingress|egress), action audit.*, ([0-9.]+)(:[0-9]+)? -> ([0-9.]+)(:[0-9]+)?.*/\3 proto \2 \4 -> \6\7/p' "$1" | sort | uniq -c | sort -rn
}

etape_h3_releve() { # ${DUREE:-2400} s de verdicts sur les trois agents : plus que T1 du bail DHCP, 27 min, pour voir un renouvellement
  exige_rke2
  local d=$T/h3 p n
  rm -rf -- "${d:?}"; mkdir -p "$d"
  date -u '+début %H:%M:%S UTC'
  while read -r p n; do
    kubectl exec -n kube-system "$p" -c cilium-agent -- timeout "${DUREE:-2400}" cilium-dbg monitor -t policy-verdict > "$d/$n.txt" 2> "$d/$n.err" </dev/null &
  done < <(kubectl get pods -n kube-system -l k8s-app=cilium -o json | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"')
  wait
  date -u '+fin %H:%M:%S UTC'
  etape_h3_resume
}

etape_flux() { # ${DUREE:-420} s de verdicts et de refus sur les trois agents, données brutes dans $T/flux ; sans rien changer
  exige_rke2
  local d=$T/flux p n
  rm -rf -- "${d:?}"; mkdir -p "$d"
  date -u '+début %H:%M:%S UTC'
  while read -r p n; do
    kubectl exec -n kube-system "$p" -c cilium-agent -- timeout "${DUREE:-420}" cilium-dbg monitor -t policy-verdict > "$d/$n.txt" 2>/dev/null </dev/null &
    kubectl exec -n kube-system "$p" -c cilium-agent -- timeout "${DUREE:-420}" cilium-dbg monitor -t drop > "$d/$n-refus.txt" 2>/dev/null </dev/null &
  done < <(kubectl get pods -n kube-system -l k8s-app=cilium -o json | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"')
  wait
  date -u '+fin %H:%M:%S UTC'
  etape_flux_resume
}

etape_flux_resume() { # relit le dernier relevé de flux
  exige_rke2
  local d=$T/flux n
  for n in sc-confiance sc-build sc-stockage; do
    echo "## $n : $(wc -l < "$d/$n.txt") verdicts, $(grep -c 'action deny' "$d/$n.txt" || true) refusés, $(grep -c 'Policy denied' "$d/$n-refus.txt" || true) refus de politique"
    { grep -h 'action deny' "$d/$n.txt" || true; } | sed -E 's/^.*(ingress|egress), action deny.*, ([0-9.]+)(:[0-9]+)? -> ([0-9.]+)(:[0-9]+)?.*/\1 \2 -> \4\5/' | sort | uniq -c | sort -rn | head -n 20
  done
}

etape_h3_resume() { # relit les verdicts du dernier relevé
  exige_rke2
  local d=$T/h3 n
  for n in sc-confiance sc-build sc-stockage; do
    echo "## $n : $(wc -l < "$d/$n.txt") verdicts, $(grep -c 'action audit' "$d/$n.txt" || true) seraient refusés"
    verdicts "$d/$n.txt"
  done
  echo "## flux admis vers les nœuds, tous les relevés"
  cat "$d"/sc-*.txt | grep 'action allow' | sed -n -E 's/.*(ingress), action allow, auth: [a-z]+, match [^,]+, ([0-9.]+)(:[0-9]+)? -> (192\.168\.161\.[0-9]+:[0-9]+).*/\2 -> \4/p' \
    | sed -E 's/^10\.42\.[0-9.]+/pod/' | sort | uniq -c | sort -rn
}

etape_h4_bloque() {
  exige_rke2
  local v
  kubectl apply --server-side -f "$here/politiques/cilium/"
  VALEURS_08C=$C/valeurs-cilium.yaml "$b08/cilium.sh" appliquer
  attendu "pare-feu d'hôte et mode audit" "$(kubectl -n kube-system get cm cilium-config -o json | jq -c '[.data["enable-host-firewall"], .data["policy-audit-mode"]]')" '["true","false"]'
  kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
  for v in sc-confiance sc-build sc-stockage; do attendu "SSH de $v" "$(sur "$v" 'echo joint' </dev/null || true)" joint; done
  attendu "API" "$(kubectl get --raw /readyz || true)" ok
  v=$(curl -k -s -o /dev/null --max-time 8 -w '%{http_code}' "https://$REG_HOTE/v2/" || true)
  if [ "${v:-000}" != 000 ]; then echo "OK   Zot joignable depuis l'hôte : HTTP $v"; else echo "KO   Zot injoignable depuis l'hôte"; ko=1; fi
  temoins
  T6_FERMES="Supervisor Etcd" mise run confiance:preuves -- test6
  [ "$ko" = 0 ] || { echo "KO   h4_bloque" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
}

LIMITES=$here/politiques/limites.tsv
limites_correctifs() { # une ligne par objet de la table : type, espace, nom, correctif en JSON ; OpenBao d'abord, ses dépendants démarrent ainsi face à un OpenBao descellé
  grep -v '^#' "$LIMITES" | jq -Rrs '
    split("\n") | map(select(length > 0) | split("\t")) | group_by(.[0:3]) | sort_by(.[0][0] != "StatefulSet") | .[]
    | .[0] as $o
    | (map({g: .[4], c: {name: .[3], resources: {requests: {cpu: .[5], memory: .[6]}, limits: {cpu: .[7], memory: .[8]}}}})
       | group_by(.g) | map({key: .[0].g, value: map(.c)}) | from_entries) as $s
    | (if $o[0] == "EventListener" then {spec: {resources: {kubernetesResource: {spec: {template: {spec: {containers: ($s.containers | map({resources}))}}}}}}}
       elif $o[0] == "CronJob" then {spec: {jobTemplate: {spec: {template: {spec: $s}}}}}
       else {spec: {template: {spec: $s}}} end) as $p
    | [$o[0], $o[1], $o[2], ($p | tojson)] | @tsv'
}
patcher() { # type espace nom correctif [options] : un EventListener n'accepte pas le correctif stratégique
  local t=strategic
  [ "$1" != EventListener ] || t=merge
  kubectl patch "${1,,}" -n "$2" "$3" --type "$t" -p "$4" "${@:5}"
}
defauts_tekton() { jq -Rs '{data: {"default-container-resource-requirements": (split("\n") | map(select(startswith("#") | not)) | join("\n"))}}' "$here/politiques/tekton-defauts.yaml"; }
regles_deny() { sed 's/^  validationActions: \[Audit\]$/  validationActions: [Deny]/' "$here/politiques/kyverno/durcissement.yaml"; }
essai_cas() { # nom filtre jq : variante du pod de base présentée à l'admission, à sec
  local m e
  m=$(jq "$2" "$T/h5-base.json" | kubectl create --dry-run=server -f - 2>&1) && e=admis || e=refusé
  echo "$e $1 : $(sed -n 's/.*\(durcissement : [^"]*\).*/\1/p' <<< "$m" | head -1)"
  [ "$e" = admis ] || [ -n "$(sed -n '/durcissement :/p' <<< "$m")" ] || echo "  autre motif : $m" | cut -c1-240
}
essais_politiques() { # les pods de essais/ visent le CLI ; ici, le pod réel de rattrapage, admis par les règles en service, puis une entorse par règle
  kubectl get cronjob -n declencheurs rattrapage -o json | jq '{apiVersion: "v1", kind: "Pod",
    metadata: {name: "essai-h5", namespace: "declencheurs", labels: .spec.jobTemplate.spec.template.metadata.labels},
    spec: (.spec.jobTemplate.spec.template.spec | .containers[0].resources = {limits: {cpu: "100m", memory: "64Mi"}})}' > "$T/h5-base.json"
  essai_cas temoin .
  essai_cas sans-limite 'del(.spec.containers[0].resources)'
  essai_cas image-par-tag ".spec.containers[0].image = \"$REG/amont/busybox:1.37.0\""
  essai_cas jeton-default '.spec.serviceAccountName = "default" | .spec.automountServiceAccountToken = true'
  essai_cas espace-default '.metadata.namespace = "default" | .spec.serviceAccountName = "default"'
}

etape_h5_sec() {
  exige_rke2
  local ty ns nom p n o
  o=$T/h5-objets.json
  echo "## correctifs de limites, dry-run serveur"
  : > "$o"
  while IFS=$'\t' read -r ty ns nom p; do
    if patcher "$ty" "$ns" "$nom" "$p" --dry-run=server -o json >> "$o"; then echo "OK   $ty $ns/$nom"; else echo "KO   $ty $ns/$nom"; ko=1; fi
  done < <(limites_correctifs)
  attendu "config-defaults, dry-run serveur" "$(kubectl patch cm -n tekton-pipelines config-defaults --type merge -p "$(defauts_tekton)" --dry-run=server -o json | jq -r '.data | has("default-container-resource-requirements")')" true
  echo "## couverture de limites-obligatoires : contrôleurs vivants, correctifs simulés appliqués"
  kubectl get deploy,sts,cronjob -A -o json | jq '.items[]' > "$T/h5-vivants.json"
  jq -s --slurpfile o "$o" '
    (($o | map({key: "\(.kind)/\(.metadata.namespace)/\(.metadata.name)", value: .}) | from_entries)) as $d
    | map(. as $v | ($d["\(.kind // "CronJob")/\(.metadata.namespace)/\(.metadata.name)"] // $v))
    | map(select(.metadata.namespace | test("^(kube-system|kube-public|kube-node-lease|kyverno|local-path-storage)$") | not))
    | map(select(.metadata.name != "el-forgejo"))
    | map(. as $x | ($x.spec.template.spec // $x.spec.jobTemplate.spec.template.spec).containers[]
        | select((.resources.limits.cpu == null) or (.resources.limits.memory == null)) | "\($x.metadata.namespace)/\($x.metadata.name)/\(.name)")' "$T/h5-vivants.json" > "$T/h5-ecarts.json"
  attendu "contrôleurs encore sans limite" "$(jq -c . "$T/h5-ecarts.json")" "[]"
  attendu "EventListener : limites du conteneur" "$(jq -s -c 'map(select(.kind == "EventListener"))[0].spec.resources.kubernetesResource.spec.template.spec.containers[0].resources.limits' "$o")" '{"cpu":"250m","memory":"128Mi"}'
  attendu "EventListener : reste du gabarit inchangé par le correctif" "$(jq -s -c 'map(select(.kind == "EventListener"))[0].spec.resources.kubernetesResource | del(.spec.template.spec.containers)' "$o")" "$(kubectl get eventlistener -n declencheurs forgejo -o json | jq -c '.spec.resources.kubernetesResource | del(.spec.template.spec.containers)')"
  attendu "Deployment el-forgejo : un seul conteneur, couvert par l'EventListener" "$(kubectl get deploy -n declencheurs el-forgejo -o json | jq '.spec.template.spec.containers | length')" 1
  echo "## gabarits des Jobs rendus, dry-run serveur"
  local d=sha256:0000000000000000000000000000000000000000000000000000000000000000
  sed -e 's#@NOM@#essai-h5#' -e "s#@[A-Z_]*@#$REG/essai@$d#g" -e 's#/etc/porte/sc-stockage[^ ]*#/etc/porte/policy.yaml#' "$b08/politique/porte-job.yaml" > "$T/h5-porte.yaml"
  sed -E 's/^( *name: )"?'"$REG"'[^"]*"?$/\1porte/' "$T/h5-porte.yaml" | kubectl create --dry-run=server -f - -o json > "$T/h5-porte.json"
  n=$(jq -c '.spec.template.spec | [(.initContainers + .containers)[] | select((.resources.limits.cpu == null) or (.resources.requests.cpu != "50m"))] | length' "$T/h5-porte.json")
  attendu "porte-job.yaml : conteneurs sans limite ou à requête CPU autre que 50m" "$n" 0
  sed -e 's#@NOM@#essai-h5#' -e "s#@[A-Z_]*@#$REG/essai@$d#g" "$b08/tsa/horodatage-job.yaml" > "$T/h5-horodatage.yaml"
  sed -E 's/^( *name: )"?'"$REG"'[^"]*"?$/\1essai/' "$T/h5-horodatage.yaml" | kubectl create --dry-run=server -f - -o json > "$T/h5-horodatage.json"
  attendu "horodatage-job.yaml : conteneurs principaux sans limite" "$(jq -c '[.spec.template.spec.containers[] | select(.resources.limits.cpu == null)] | length' "$T/h5-horodatage.json")" 0
  echo "## requêtes de CPU ajoutées, en millicoeurs : table $(grep -v '^#' "$LIMITES" | awk -F'\t' '{v = $6; if (v ~ /m$/) { sub(/m$/, "", v) } else { v *= 1000 } s += v} END {print s}') ; porte 150 à l'exécution ; sc-confiance : 4 000 allouables, 1 875 demandés"
  echo "## règles en Deny, dry-run serveur"
  attendu "objets acceptés en Deny" "$(regles_deny | kubectl apply --server-side --dry-run=server -f - -o name | grep -c . || true)" 4
  attendu "règles encore en Audit au cluster" "$(kubectl get validatingpolicies.policies.kyverno.io -o json | jq '[.items[] | select(.spec.validationActions == ["Audit"])] | length')" 4
  echo "## quatre règles en Deny, CLI, pods tirés de chaque gabarit réel, résultats par pod"
  local f v
  rm -rf -- "${T:?}/h5-pods"; mkdir -p "$T/h5-pods"
  regles_deny > "$T/h5-regles.yaml"
  jq -c -s --slurpfile o "$o" '
    (($o | map({key: "\(.kind)/\(.metadata.namespace)/\(.metadata.name)", value: .}) | from_entries)) as $d
    | map(. as $v | ($d["\(.kind // "CronJob")/\(.metadata.namespace)/\(.metadata.name)"] // $v))
    | map(select(.metadata.namespace | test("^(kube-system|kube-public|kube-node-lease|kyverno|local-path-storage)$") | not))
    | .[] | {apiVersion: "v1", kind: "Pod", metadata: {name: .metadata.name, namespace: .metadata.namespace},
        spec: (.spec.template.spec // .spec.jobTemplate.spec.template.spec)}
    | if .metadata.name == "el-forgejo" then .spec.containers[0].resources = {limits: {cpu: "250m", memory: "128Mi"}} else . end' "$T/h5-vivants.json" > "$T/h5-pods.jsonl"
  jq -c '{apiVersion: "v1", kind: "Pod", metadata: {name: "gabarit-porte", namespace: .metadata.namespace}, spec: .spec.template.spec}' "$T/h5-porte.json" >> "$T/h5-pods.jsonl"
  jq -c '{apiVersion: "v1", kind: "Pod", metadata: {name: "gabarit-horodatage", namespace: .metadata.namespace}, spec: .spec.template.spec}' "$T/h5-horodatage.json" >> "$T/h5-pods.jsonl"
  n=0
  while read -r p; do
    n=$((n + 1)); f=$T/h5-pods/$n.json
    printf '%s\n' "$p" > "$f"
    kyverno apply "$T/h5-regles.yaml" --resource "$f" --policy-report --output-format json > "$T/cli.json" 2> "$T/cli.err" || true
    v=$(jq -c '[.results[]? // .[]?.results[]? | "\(.policy):\(.result)"] | sort' "$T/cli.json" 2>/dev/null || echo erreur)
    echo "$(jq -r '"\(.metadata.namespace)/\(.metadata.name)"' "$f") $v"
    if [ "$v" = "[]" ] || [ "$v" = erreur ] || grep -q -E ':(fail|error)"' <<< "$v"; then echo "KO   $f"; ko=1; fi
  done < "$T/h5-pods.jsonl"
  attendu "pods jugés par le CLI" "$n" "$(wc -l < "$T/h5-pods.jsonl")"
  kyverno apply "$T/h5-regles.yaml" --resource "$here/essais/limites-obligatoires--b-fail.yaml" --policy-report --output-format json > "$T/cli.json" 2> "$T/cli.err" || true
  attendu "témoin du CLI, pod sans limite" "$(jq -c '[.results[]? // .[]?.results[]? | select(.policy == "limites-obligatoires") | .result] | unique' "$T/cli.json")" '["fail"]'
  echo "## entorses à l'admission actuelle : toutes admises attendues, chacune ne heurtant que l'une des quatre règles"
  essais_politiques | tee "$T/h5-essais.txt"
  attendu "entorses refusées par une règle déjà en Deny" "$(grep -c '^refusé' "$T/h5-essais.txt" || true)" 0
  [ "$ko" = 0 ] || { echo "KO   h5_sec" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
}

crons_suspendus() { # true ou false : horodatage et rattrapage tournent chaque minute et lisent OpenBao ou l'EventListener
  kubectl patch cronjob -n horodatage horodatage --type merge -p "{\"spec\":{\"suspend\":$1}}" >/dev/null
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p "{\"spec\":{\"suspend\":$1}}" >/dev/null
}
etape_h5_limites() {
  exige_rke2
  local ty ns nom p u v s=$T/h5-avant
  attendu "PipelineRun en cours" "$(kubectl get pipelineruns -A -o json | jq '[.items[] | select(.status.completionTime == null)] | length')" 0
  [ "$ko" = 0 ] || exit 1
  # État d'avant, pour le retour : rollout undo ne couvre ni les CronJobs, ni l'EventListener, ni config-defaults
  rm -rf -- "${s:?}"; mkdir -p "$s"
  kubectl get cm -n tekton-pipelines config-defaults -o json > "$s/config-defaults.json"
  while IFS=$'\t' read -r ty ns nom p; do kubectl get "${ty,,}" -n "$ns" "$nom" -o json > "$s/$ty-$ns-$nom.json"; done < <(limites_correctifs)
  crons_suspendus true
  trap 'crons_suspendus false' EXIT
  for _ in $(seq 60); do
    [ -z "$(kubectl get cronjob -n horodatage horodatage -o jsonpath='{.status.active}')$(kubectl get cronjob -n declencheurs rattrapage -o jsonpath='{.status.active}')" ] && break
    sleep 2
  done
  kubectl patch cm -n tekton-pipelines config-defaults --type merge -p "$(defauts_tekton)"
  u=$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.metadata.uid}')
  while IFS=$'\t' read -r ty ns nom p; do
    patcher "$ty" "$ns" "$nom" "$p"
    case $ty in
      Deployment) kubectl rollout status -n "$ns" "deploy/$nom" --timeout=180s ;;
      EventListener) sleep 3; kubectl rollout status -n "$ns" "deploy/el-$nom" --timeout=180s ;;
      StatefulSet) # redémarre scellé : prêt seulement après le descellement
        for _ in $(seq 90); do
          v=$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.metadata.uid} {.status.phase}' 2>/dev/null || true)
          case $v in "$u "*|"") ;; *" Running") break ;; esac
          sleep 2
        done
        for _ in $(seq 60); do   # pod Running ne dit pas que bao répond : desceller sauterait le descellement sur un état vide
          [ "$(kubectl exec -n openbao openbao-0 -- bao status -format=json 2>/dev/null | jq -r .sealed || true)" = true ] && break
          sleep 2
        done
        mise run confiance:openbao -- deverrouiller
        kubectl rollout status -n openbao statefulset/openbao --timeout=180s ;;
    esac
  done < <(limites_correctifs)
  crons_suspendus false
  trap - EXIT
  temoins
  [ "$ko" = 0 ] || { echo "KO   h5_limites" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
}

etape_h5_deny() {
  exige_rke2
  local l e f m
  regles_deny | kubectl apply --server-side -f -
  attendu "règles encore en Audit" "$(kubectl get validatingpolicies.policies.kyverno.io -o json | jq '[.items[] | select(.spec.validationActions == ["Audit"])] | length')" 0
  for _ in $(seq 60); do   # webhook de Kyverno à jour : la bascule n'est pas instantanée
    essais_politiques > "$T/h5-essais.txt"
    grep -q '^refusé sans-limite' "$T/h5-essais.txt" && break
    sleep 2
  done
  while read -r l; do
    case $l in "autre motif"*) echo "KO   $l"; ko=1; continue ;; esac
    f=${l#* }; f=${f%% :*}
    case $f in
      temoin) e="admis" ; m="" ;;
      sans-limite) e=refusé; m="durcissement : limites de mémoire et de CPU obligatoires" ;;
      image-par-tag) e=refusé; m="durcissement : image du Zot du PoC, par digest" ;;
      jeton-default) e=refusé; m="durcissement : le compte default ne monte pas de jeton" ;;
      espace-default) e=refusé; m="$(sed -n 's/.*message: "\(durcissement : [^"]*\)".*/\1/p' "$here/politiques/kyverno/durcissement.yaml" | grep -i -m1 'default' | grep -v 'compte' || true)" ;;
    esac
    attendu "$f" "$l" "$e $f :${m:+ $m}"
  done < "$T/h5-essais.txt"
  temoins
  [ "$ko" = 0 ] || { echo "KO   h5_deny" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
}

pipe_essai() { # bundle de sample-app-essai, lu sur un PipelineRun de J6 resté dans builds : le gabarit en service ne le cite plus
  local b
  b=$(kubectl get pipelinerun -n builds j6-porte-en-service -o json | jq -r '.spec.pipelineRef.params[] | select(.name == "bundle") | .value')
  [[ $b == "$REG"/tekton/pipelines/sample-app-essai@sha256:* ]] || { echo "KO   bundle de la pipeline d'essai : ${b:-absent}" >&2; exit 1; }
  echo "$b"
}

etape_h5_tests_sec() {
  exige_rke2
  local p
  p=$(pipe_essai)
  PIPE_ESSAI=$p JOURNAL=preuves-h5 mise run confiance:preuves -- sec_h5
}

etape_h5_tests() {
  exige_rke2
  local p
  p=$(pipe_essai)
  PIPE_ESSAI=$p JOURNAL=preuves-h5 mise run confiance:preuves -- test2 test4 test3 test1 test7 test8
}

jeton_essai() { # identité : demande réelle pour builds/build, 10 min, audience essai ; le dry-run émet tout de même un jeton, jamais lu ni gardé ; motif de refus sur la sortie
  printf '{"apiVersion":"authentication.k8s.io/v1","kind":"TokenRequest","spec":{"audiences":["essai"],"expirationSeconds":600}}' > "$T/tr.json"
  if kubectl create --raw '/api/v1/namespaces/builds/serviceaccounts/build/token?dryRun=All' --as="$1" -f "$T/tr.json" </dev/null >/dev/null 2>"$T/tr.err"; then echo admis
  else tr '\n' ' ' < "$T/tr.err" | cut -c1-320; fi
  rm -f "$T/tr.json" "$T/tr.err"
}

webhook_essai() { # compte configuration : modification présentée à l'API, dry-run serveur, au nom d'un compte de Triggers
  kubectl patch validatingwebhookconfiguration "$2" --type=merge -p '{"metadata":{"labels":{"essai":"h5"}}}' --dry-run=server \
    --as="system:serviceaccount:tekton-pipelines:$1" </dev/null 2>&1 | tr '\n' ' ' | cut -c1-320 || true   # un refus est un résultat, pas une fin de script
}

etape_h5_roles_sec() {
  exige_rke2
  local c=$HOME/.cache/supply-chain-poc/08/telechargements/cilium/cilium-1.20.4.tgz v
  mkdir -p "$T"
  kubectl apply --server-side --dry-run=server -f "$here/politiques/roles/roles.yaml" </dev/null
  echo "## chart de Cilium rendu sur l'hôte, sans le cluster ; décomptes seulement, le rendu contient des clés de démonstration"
  for v in "" tls.secretSync.enabled=false; do
    helm template cilium "$c" -n kube-system -f "$b08/cilium/valeurs.yaml" -f "$B08/valeurs-cilium.yaml" ${v:+--set "$v"} > "$T/cilium-rendu.yaml"
    echo "${v:-valeurs en service} : règles nommant secrets $(grep -c '^  - secrets$' "$T/cilium-rendu.yaml" || true), enable-policy-secrets-sync $(grep -c 'enable-policy-secrets-sync' "$T/cilium-rendu.yaml" || true), rôle tlsinterception de l'opérateur $(grep -c 'name: cilium-operator-tlsinterception-secrets' "$T/cilium-rendu.yaml" || true)"
  done
  rm -f "$T/cilium-rendu.yaml"
}

audit_vu() { # motif depuis filtre-jq : requêtes de l'audit de l'API qui contiennent le motif, depuis une date, sélectionnées par le filtre ; nombre
  sur sc-confiance "sudo sh -c 'cat \$(ls -1 $D_ETAT/server/logs/audit*.log | LC_ALL=C sort) | grep -F -- $1 || true'" </dev/null \
    | jq -c --arg t "$2" 'select(.stage == "ResponseComplete" and .stageTimestamp[0:19] >= ($t[0:19])) | select('"$3"')' | grep -c . || true
}

etape_h5_roles() {
  exige_rke2
  local t1 n a0 a1
  local c=system:rke2-controller w=system:serviceaccount:tekton-pipelines:tekton-triggers-webhook
  mkdir -p "$T"
  attendu "avant la règle, RBAC laisse passer la demande de jeton" "$(kubectl auth can-i create serviceaccounts --subresource=token -n builds --as="$c" </dev/null 2>/dev/null)" yes
  kubectl apply --server-side -f "$here/politiques/roles/roles.yaml" </dev/null
  sleep 5
  n=$(jeton_essai "$c"); grep -F 'ne demande pas de jeton' <<< "$n" >/dev/null && echo "OK   jeton refusé : $n" || { echo "KO   jeton : $n"; ko=1; }
  attendu "témoin, jeton demandé par system:kube-controller-manager" "$(jeton_essai system:kube-controller-manager)" admis
  n=$(webhook_essai tekton-triggers-controller kyverno-policy-validating-webhook-cfg); grep -F "n'écrit que ses propres webhooks" <<< "$n" >/dev/null && echo "OK   webhook de Kyverno refusé : $n" || { echo "KO   webhook de Kyverno : $n"; ko=1; }
  n=$(webhook_essai tekton-triggers-webhook validation.webhook.triggers.tekton.dev); grep -F ' patched' <<< "$n" >/dev/null && echo "OK   témoin, webhook de Triggers : $n" || { echo "KO   témoin webhook de Triggers : $n"; ko=1; }
  t1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  a0=$(sur sc-build "systemctl show -p ActiveEnterTimestamp --value rke2-agent" </dev/null)
  kubectl rollout restart -n tekton-pipelines deploy/tekton-triggers-webhook deploy/tekton-triggers-controller </dev/null
  kubectl rollout status -n tekton-pipelines deploy/tekton-triggers-webhook --timeout=180s </dev/null
  kubectl rollout status -n tekton-pipelines deploy/tekton-triggers-controller --timeout=180s </dev/null
  sur sc-build "sudo systemctl restart rke2-agent" </dev/null
  a1=$(sur sc-build "systemctl show -p ActiveEnterTimestamp --value rke2-agent" </dev/null)
  [ "$a1" != "$a0" ] && echo "OK   agent de sc-build redémarré : $a0 → $a1" || { echo "KO   agent de sc-build non redémarré"; ko=1; }
  sleep 20
  kubectl wait --for=condition=Ready node/sc-build --timeout=180s </dev/null
  # Témoins relevés le 06/11 : chaque démarrage d'agent fait un get nodes, chaque redémarrage du webhook met à jour ses configurations
  for _ in $(seq 18); do
    n=$(audit_vu system:rke2-controller "$t1" ".user.username == \"$c\" and .responseStatus.code < 300")
    [ "$n" -ge 1 ] && break
    sleep 5
  done
  [ "$n" -ge 1 ] && echo "OK   témoin : $n requête(s) acceptée(s) de $c après le redémarrage" || { echo "KO   aucune requête de $c après le redémarrage : le contrôle suivant serait vide"; ko=1; }
  attendu "requêtes de $c refusées par l'API depuis $t1" "$(audit_vu system:rke2-controller "$t1" ".user.username == \"$c\" and .responseStatus.code >= 400 and .responseStatus.code != 409")" 0
  n=$(audit_vu webhookconfigurations "$t1" ".user.username == \"$w\" and .verb == \"update\" and .responseStatus.code == 200")
  [ "$n" -ge 1 ] && echo "OK   témoin : $n mise(s) à jour de ses webhooks par Triggers après le redémarrage" || { echo "KO   aucune mise à jour de webhook par Triggers : le contrôle suivant serait vide"; ko=1; }
  attendu "écritures de webhooks de Triggers refusées depuis $t1" "$(audit_vu webhookconfigurations "$t1" ".user.username == \"$w\" and .responseStatus.code >= 400 and .responseStatus.code != 409")" 0
  kubectl get nodes --no-headers </dev/null
  [ "$ko" = 0 ] && echo "OK   h5_roles" || { echo "KO   h5_roles"; exit 1; }
}

rendu_cilium() { # fichier [--set …] : chart rendu sur l'hôte avec les trois -f de cilium.sh appliquer ; documents Secret retirés, eux seuls portent des clés, générées à chaque rendu
  local f=$1; shift
  rendre_cilium_valeurs
  helm template cilium "$O/telechargements/cilium/cilium-1.20.4.tgz" --namespace kube-system -f "$T/valeurs.yaml" -f "$B08/valeurs-cilium.yaml" -f "$C/valeurs-cilium.yaml" "$@" \
    | awk 'BEGIN { RS = "\n---\n"; ORS = "\n---\n" } !/(^|\n)kind: Secret\n/' > "$f"
}

rendre_cilium_valeurs() {
  sed -e 's/^#.*//' -e 's#@CILIUM_AMD64@#sha256:fa56fecd779584642c7ec2da6872c03c45c1f1043da66665a73ed8c425584d54#' \
      -e 's#@OPERATOR_AMD64@#sha256:77a9b4371faed41dc9c2fb3942b6c02a581158be1d4aa46a0e62956ce2f55ff1#' "$b08/cilium/valeurs.yaml" > "$T/valeurs.yaml"
}

pod_cilium() { # type nom : spec en service présentée à l'admission comme un pod, en dry-run serveur, Kyverno compris
  kubectl get "$1" -n kube-system "$2" -o json </dev/null \
    | jq '{apiVersion: "v1", kind: "Pod", metadata: {generateName: "essai-h5-", namespace: "kube-system", annotations: (.spec.template.metadata.annotations // {})}, spec: .spec.template.spec}' \
    | kubectl create --dry-run=server -f - 2>&1 | tr '\n' ' ' | cut -c1-320 || true
}

versions_certs() { # versions d'objet de la CA de Cilium et du certificat de Hubble : une rotation les changerait ; aucune valeur affichée
  kubectl get secret -n kube-system cilium-ca hubble-server-certs --no-headers -o custom-columns=N:.metadata.name,V:.metadata.resourceVersion </dev/null | tr -s ' ' | paste -sd' ' -
}

pare_feu() { # depuis sc-build, port de sc-confiance : ouvert ou fermé
  local p
  for p in 6443 2379; do
    printf '%s=%s ' "$p" "$(sur sc-build "timeout 4 bash -c 'exec 3<>/dev/tcp/192.168.161.11/$p' 2>/dev/null && echo ouvert || echo ferme" </dev/null)"
  done
}

droits_cilium() { # lecture de Secrets par l'opérateur et les agents, à l'échelle du cluster et dans cilium-secrets
  local c s
  for c in cilium-operator cilium; do
    s=system:serviceaccount:kube-system:$c
    printf '%s cluster=%s cilium-secrets=%s ' "$c" "$(kubectl auth can-i list secrets -A --as="$s" </dev/null 2>/dev/null || true)" "$(kubectl auth can-i list secrets -n cilium-secrets --as="$s" </dev/null 2>/dev/null || true)"
  done
}

etape_h5_cilium_sec() {
  exige_rke2
  local a=$T/cilium-avant.yaml b=$T/cilium-apres.yaml
  mkdir -p "$T"
  rendu_cilium "$a" --set tls.secretSync.enabled=true
  rendu_cilium "$b"
  attendu "aucune clé dans les documents comparés" "$(cat "$a" "$b" | grep -cE 'PRIVATE KEY|LS0tLS1CRUdJTi' || true)" 0
  echo "## rendu : valeurs en service (-) contre valeurs préparées (+), documents Secret retirés"
  diff -U0 "$a" "$b" | grep -vE '^(---|\+\+\+|@@)' | cut -c1-120 || true
  echo "## cilium-config : en service contre rendu des valeurs en service"
  kubectl get cm -n kube-system cilium-config -o json </dev/null | jq -r '.data | to_entries[] | "\(.key)=\(.value)"' | sort > "$T/cm-vivant"
  awk 'BEGIN { RS = "\n---\n" } /\n  name: cilium-config\n/' "$a" | sed -n -E '/^data:/,$s/^  ([a-z0-9-]+): +"?([^"]*)"?$/\1=\2/p' | sort > "$T/cm-rendu"
  echo "$(wc -l < "$T/cm-vivant") clés en service, $(wc -l < "$T/cm-rendu") rendues"
  diff "$T/cm-vivant" "$T/cm-rendu" | cut -c1-120 || true
  echo "## valeurs de la release en service, digests retirés"
  helm get values cilium -n kube-system -o json </dev/null | jq -c 'del(.image, .operator.image)'
  attendu "politiques de Cilium qui citent un Secret ou du TLS" "$(kubectl get cnp,ccnp -A -o json </dev/null | jq '[.items[] | tostring | select(test("terminatingTLS|originatingTLS|secret"; "i"))] | length')" 0
  echo "## pods de Cilium présentés à l'admission (dry-run serveur)"
  grep -F 'created (server dry run)' <<< "$(pod_cilium deploy cilium-operator)" >/dev/null && echo "OK   opérateur admis" || { echo "KO   opérateur"; ko=1; }
  grep -F 'created (server dry run)' <<< "$(pod_cilium ds cilium)" >/dev/null && echo "OK   agent admis" || { echo "KO   agent"; ko=1; }
  echo "## état de départ"
  echo "certificats : $(versions_certs)"
  echo "pare-feu depuis sc-build : $(pare_feu)"
  echo "droits : $(droits_cilium)"
  rm -f "$a" "$b" "$T/cm-vivant" "$T/cm-rendu"
  [ "$ko" = 0 ] && echo "OK   h5_cilium_sec" || { echo "KO   h5_cilium_sec"; exit 1; }
}

etape_h5_cilium() {
  exige_rke2
  local c0 p0 t1 p n v q
  c0=$(versions_certs); p0=$(pare_feu)
  attendu "avant, droits" "$(droits_cilium)" "cilium-operator cluster=yes cilium-secrets=yes cilium cluster=no cilium-secrets=yes "
  suspendre_rattrapage
  VALEURS_08C=$C/valeurs-cilium.yaml "$b08/cilium.sh" appliquer
  # Le nouveau pod seul, depuis sa création : la fermeture de la surveillance de l'ancien tombe dans la fenêtre, et les lectures d'un démarrage la précèdent
  q=$(kubectl get pods -n kube-system -l io.cilium/app=operator -o jsonpath='{.items[0].metadata.name}' </dev/null)
  t1=$(kubectl get pod -n kube-system "$q" -o jsonpath='{.metadata.creationTimestamp}' </dev/null)
  attendu "pare-feu d'hôte et mode audit" "$(kubectl -n kube-system get cm cilium-config -o json | jq -c '[.data["enable-host-firewall"], .data["policy-audit-mode"]]')" '["true","false"]'
  attendu "enable-policy-secrets-sync dans cilium-config" "$(kubectl -n kube-system get cm cilium-config -o json | jq '.data | has("enable-policy-secrets-sync")')" false
  attendu "rôle de l'opérateur dans cilium-secrets" "$(kubectl get role -n cilium-secrets cilium-operator-tlsinterception-secrets --ignore-not-found -o name </dev/null)" ""
  kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
  for v in sc-confiance sc-build sc-stockage; do attendu "SSH de $v" "$(sur "$v" 'echo joint' </dev/null || true)" joint; done
  attendu "API" "$(kubectl get --raw /readyz || true)" ok
  v=$(curl -k -s -o /dev/null --max-time 8 -w '%{http_code}' "https://$REG_HOTE/v2/" || true)
  if [ "${v:-000}" != 000 ]; then echo "OK   Zot joignable depuis l'hôte : HTTP $v"; else echo "KO   Zot injoignable depuis l'hôte"; ko=1; fi
  attendu "droits" "$(droits_cilium)" "cilium-operator cluster=no cilium-secrets=no cilium cluster=no cilium-secrets=yes "
  attendu "certificats" "$(versions_certs)" "$c0"
  attendu "pare-feu depuis sc-build" "$(pare_feu)" "$p0"
  sonde_kyverno
  sleep 60   # l'opérateur prend son bail et ses observations : les relevés suivants ne doivent pas être vides
  while read -r p; do
    attendu "$p, état" "$(kubectl exec -n kube-system "$p" -c cilium-agent -- cilium-dbg status --brief </dev/null 2>&1 | tail -1)" OK
    attendu "$p, Hubble" "$(kubectl exec -n kube-system "$p" -c cilium-agent -- cilium-dbg status </dev/null 2>/dev/null | awk '$1 == "Hubble:" {print $2}')" Ok
  done < <(kubectl get pods -n kube-system -l k8s-app=cilium -o json </dev/null | jq -r '.items[].metadata.name')
  attendu "redémarrages de conteneurs de Cilium" "$(kubectl get pods -n kube-system -l 'k8s-app=cilium' -o json </dev/null | jq '[.items[].status.containerStatuses[].restartCount] | add')" 0
  attendu "redémarrages de l'opérateur" "$(kubectl get pods -n kube-system -l io.cilium/app=operator -o json </dev/null | jq '[.items[].status.containerStatuses[].restartCount] | add')" 0
  attendu "lignes forbidden du journal de l'opérateur" "$(kubectl logs -n kube-system deploy/cilium-operator </dev/null | grep -ci forbidden || true)" 0
  n=$(audit_vu "$q" "$t1" ".")
  [ "$n" -ge 1 ] && echo "OK   témoin : $n requête(s) de l'opérateur depuis $t1" || { echo "KO   aucune requête de l'opérateur : le contrôle suivant serait vide"; ko=1; }
  attendu "requêtes de l'opérateur sur des Secrets depuis $t1" "$(audit_vu "$q" "$t1" ".objectRef.resource == \"secrets\"")" 0
  kubectl get nodes --no-headers </dev/null
  [ "$ko" = 0 ] && echo "OK   h5_cilium" || { echo "KO   h5_cilium"; exit 1; }
}

WG_POL=$here/politiques/cilium-h6/hote-wireguard.yaml

valeurs_h6() { cat "$C/valeurs-cilium.yaml" "$C/valeurs-cilium-wireguard.yaml" > "$T/valeurs-h6.yaml"; }   # VALEURS_08C ne prend qu'un fichier ; clés distinctes, le pare-feu d'hôte et H5 restent

ip_coredns() { # nœud : adresse de son pod coredns, stable pendant h6, l'autoscaler écarté par le motif
  kubectl get pods -n kube-system -o json </dev/null | jq -r --arg n "$1" '[.items[] | select(.spec.nodeName == $n and (.metadata.name | test("^rke2-coredns-rke2-coredns-[0-9a-f]+-[a-z0-9]+$"))) | .status.podIP] | first'
}

temoins_h6() { # depuis sc-build, par l'hôte et par l'endpoint de santé (chemin d'un pod) : sc-stockage passe par le tunnel, et son pare-feu doit tenir sur le trafic déchiffré ; pare_feu ne le voit pas, sc-confiance restant hors du chiffrement de nœud à nœud
  local s c
  s=$(kubectl get ciliumnode sc-stockage -o jsonpath='{.spec.health.ipv4}' </dev/null)
  c=$(kubectl get ciliumnode sc-confiance -o jsonpath='{.spec.health.ipv4}' </dev/null)
  sur sc-build "sudo bash -c '
    p=\$(pgrep -f cilium-health-responder | head -1)
    t() { timeout 3 bash -c \"exec 3<>/dev/tcp/\$1/\$2\" 2>/dev/null && echo ouvert || echo ferme; }
    v() { nsenter -t \$p -n timeout 3 bash -c \"exec 3<>/dev/tcp/\$1/\$2\" 2>/dev/null && echo ouvert || echo ferme; }
    for q in 3100 3001 5000 3501; do printf \"hote:%s=%s \" \$q \"\$(t 192.168.161.13 \$q)\"; done
    for q in 3100 3001 5000; do printf \"sante:%s=%s \" \$q \"\$(v 192.168.161.13 \$q)\"; done
    printf \"sante-stockage=%s sante-confiance=%s\" \"\$(v $s 4240)\" \"\$(v $c 4240)\"'" </dev/null
}

etat_chiffrement() { # pod : ligne Encryption de cilium-dbg status, clé publique retirée. Pas de cilium-dbg encrypt status : il charge le module du nœud (21:06:40, sc-build)
  kubectl exec -n kube-system "$1" -c cilium-agent -- cilium-dbg status </dev/null 2>/dev/null | awk '$1 == "Encryption:"' | sed -E 's/Pubkey: [^,]*, //; s/[[:space:]]+/ /g; s/ $//'
}

agent_de() { kubectl get pods -n kube-system -l k8s-app=cilium --field-selector "spec.nodeName=$1" -o jsonpath='{.items[0].metadata.name}' </dev/null; }

mtu_routes() { # nœud : MTU de la route par défaut de l'endpoint de santé, recréé par l'agent, et de coredns, resté en service
  sur "$1" "sudo bash -c 'for p in \$(pgrep -f cilium-health-responder | head -1) \$(pgrep -x coredns | head -1); do nsenter -t \$p -n ip route show default; done'" </dev/null \
    | awk '{ for (i = 1; i <= NF; i++) if ($i == "mtu") printf "%s ", $(i + 1) }'
}

fragments() { sur "$1" 'nstat -asz IpFragCreates IpFragFails IpReasmOKs IpReasmFails' </dev/null | awk '$1 ~ /^Ip/ { printf "%s=%s ", $1, $2 }'; }

refus_agent() { # nœud : compteurs de refus de son agent, par motif
  kubectl exec -n kube-system "$(agent_de "$1")" -c cilium-agent -- cilium-dbg metrics list -o json </dev/null 2>/dev/null \
    | jq -c '[.[] | select(.name == "cilium_drop_count_total")] | group_by(.labels.reason) | map({(.[0].labels.reason): (map(.value) | add)}) | add // {}'
}

redemarrages() { kubectl get pods -A -o json </dev/null | jq '[.items[].status.containerStatuses[]?.restartCount] | add'; }

sonde_coupure() { # durée cible… : chaque seconde, depuis sc-build, une connexion par cible
  local d=$1; shift
  sur sc-build "for i in \$(seq $d); do printf %s \$(date -u +%H:%M:%S); for c in $*; do timeout 1 bash -c \"exec 3<>/dev/tcp/\${c%:*}/\${c#*:}\" 2>/dev/null && printf ' 1' || printf ' 0'; done; echo; sleep 1; done" </dev/null
}

resume_coupure() { # fichier : échecs par cible, avec leur première et leur dernière heure
  awk '{ for (i = 2; i <= NF; i++) if ($i == 0) { n[i]++; if (!d[i]) d[i] = $1; f[i] = $1 } } END { for (i = 2; i <= NF; i++) printf "  cible %d : %d échec(s)%s\n", i - 1, n[i] + 0, (n[i] ? " de " d[i] " à " f[i] : ""); print "  " NR " mesures" }' "$1"
}

classes_capture() { # lignes de tcpdump -q, en-têtes seuls, vues sur enp1s0 de sc-build : paquets par classe et par pair ; un fragment non initial n'a pas de port
  awk '$2 == "IP" {
    s = $3; d = $5; sub(/:$/, "", d); p = split(s, a, "."); q = split(d, b, ".")
    hs = a[1] "." a[2] "." a[3] "." a[4]; hd = b[1] "." b[2] "." b[3] "." b[4]
    pair = (hs == "192.168.161.12" ? hd : hs)
    if (hs ~ /^10\.42\./ || hd ~ /^10\.42\./) c = "pods-en-clair"
    else if ($0 ~ /ip-proto-17/) c = "fragment"
    else if (p == 5 && q == 5 && a[5] == "51871" && b[5] == "51871") c = "tunnel"
    else c = "clair"
    n[c " " pair]++
  } END { for (k in n) print k, n[k] }' "$1" | sort
}

etape_h6_sec() {
  exige_rke2
  local a=$T/cilium-avant.yaml b=$T/cilium-apres.yaml v
  mkdir -p "$T"
  rendu_cilium "$a"
  rendu_cilium "$b" -f "$C/valeurs-cilium-wireguard.yaml"
  attendu "aucune clé dans les documents comparés" "$(cat "$a" "$b" | grep -cE 'PRIVATE KEY|LS0tLS1CRUdJTi' || true)" 0
  echo "## rendu : valeurs en service (-) contre valeurs de H6 (+), documents Secret retirés"
  diff -U0 "$a" "$b" | grep -vE '^(---|\+\+\+|@@)' | cut -c1-120 || true
  attendu "lignes du rendu hors de cilium-config" "$(diff -U0 "$a" "$b" | grep -E '^[-+] ' | grep -vE '^\+  (enable-wireguard|wireguard-persistent-keepalive|encrypt-node|enable-encryption-strict-mode-egress|encryption-strict-egress-cidr|encryption-strict-egress-allow-remote-node-identities): ' | grep -c . || true)" 0
  echo "## cilium-config : en service contre rendu des valeurs en service"
  kubectl get cm -n kube-system cilium-config -o json </dev/null | jq -r '.data | to_entries[] | "\(.key)=\(.value)"' | sort > "$T/cm-vivant"
  awk 'BEGIN { RS = "\n---\n" } /\n  name: cilium-config\n/' "$a" | sed -n -E '/^data:/,$s/^  ([a-z0-9-]+): +"?([^"]*)"?$/\1=\2/p' | sort > "$T/cm-rendu"
  echo "$(wc -l < "$T/cm-vivant") clés en service, $(wc -l < "$T/cm-rendu") rendues"
  diff "$T/cm-vivant" "$T/cm-rendu" | cut -c1-120 || true
  echo "## règle du tunnel"
  attendu "hote-wireguard en service" "$(kubectl get ccnp hote-wireguard --ignore-not-found -o name </dev/null)" ""
  kubectl apply --server-side --dry-run=server -f "$WG_POL" </dev/null
  attendu "règles du répertoire appliqué en bloc qui ouvrent 51871" "$(grep -l 51871 "$here"/politiques/cilium/*.yaml 2>/dev/null | grep -c . || true)" 0
  echo "## module des nœuds"
  for v in sc-confiance sc-build sc-stockage; do
    echo "$v : modules_disabled=$(sur "$v" 'cat /proc/sys/kernel/modules_disabled' </dev/null), chargé=$(sur "$v" 'lsmod | grep -c "^wireguard " || true' </dev/null), interface=$(sur "$v" 'ip -br link show type wireguard | grep -c . || true' </dev/null), $(sur "$v" 'sudo /usr/sbin/modprobe -n wireguard && echo modprobe-ok' </dev/null)"
    attendu "$v, chiffrement" "$(etat_chiffrement "$(agent_de "$v")")" "Encryption: Disabled"
    echo "$v : MTU de route $(mtu_routes "$v"), $(fragments "$v")"
  done
  echo "## état de départ"
  echo "certificats : $(versions_certs)"
  echo "pare-feu depuis sc-build : $(pare_feu)"
  echo "témoins vers sc-stockage : $(temoins_h6)"
  echo "coredns : sc-confiance $(ip_coredns sc-confiance), sc-stockage $(ip_coredns sc-stockage)"
  echo "sonde de coupure, deux secondes (heure, Zot, coredns de sc-stockage, coredns de sc-confiance ; 1 joint) :"
  sonde_coupure 2 192.168.161.13:5000 "$(ip_coredns sc-stockage):53" "$(ip_coredns sc-confiance):53" | sed 's/^/  /'
  echo "redémarrages de conteneurs du cluster : $(redemarrages)"
  rm -f "$a" "$b" "$T/cm-vivant" "$T/cm-rendu"
  [ "$ko" = 0 ] && echo "OK   h6_sec" || { echo "KO   h6_sec"; exit 1; }
}

etape_h6() {
  exige_rke2
  local c0 p0 w0 r0 v p n a
  c0=$(versions_certs); p0=$(pare_feu); w0=$(temoins_h6); r0=$(redemarrages)
  a=$T/coupure-h6.txt
  attendu "avant, chiffrement de sc-build" "$(etat_chiffrement "$(agent_de sc-build)")" "Encryption: Disabled"
  suspendre_rattrapage
  kubectl apply --server-side -f "$WG_POL" </dev/null
  valeurs_h6
  sonde_coupure 240 192.168.161.13:5000 "$(ip_coredns sc-stockage):53" "$(ip_coredns sc-confiance):53" > "$a" &
  date -u '+application %H:%M:%S UTC'
  VALEURS_08C=$T/valeurs-h6.yaml "$b08/cilium.sh" appliquer
  date -u '+agents prêts %H:%M:%S UTC'
  wait
  echo "## connexions depuis sc-build, chaque seconde : Zot, coredns de sc-stockage, coredns de sc-confiance"
  resume_coupure "$a"
  attendu "configuration" "$(kubectl -n kube-system get cm cilium-config -o json </dev/null | jq -c '[.data["enable-wireguard"], .data["encrypt-node"], .data["enable-encryption-strict-mode-egress"], .data["encryption-strict-egress-cidr"], .data["enable-host-firewall"], .data["policy-audit-mode"]]')" '["true","true","true","10.42.0.0/16","true","false"]'
  kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
  for v in sc-confiance sc-build sc-stockage; do attendu "SSH de $v" "$(sur "$v" 'echo joint' </dev/null || true)" joint; done
  attendu "API" "$(kubectl get --raw /readyz || true)" ok
  v=$(curl -k -s -o /dev/null --max-time 8 -w '%{http_code}' "https://$REG_HOTE/v2/" || true)
  if [ "${v:-000}" != 000 ]; then echo "OK   Zot joignable depuis l'hôte : HTTP $v"; else echo "KO   Zot injoignable depuis l'hôte"; ko=1; fi
  attendu "certificats" "$(versions_certs)" "$c0"
  attendu "pare-feu depuis sc-build" "$(pare_feu)" "$p0"
  attendu "témoins vers sc-stockage, par le tunnel" "$(temoins_h6)" "$w0"
  sonde_kyverno
  sleep 60   # pairs échangés, MTU des endpoints mis à jour
  attendu "sc-confiance, chiffrement" "$(etat_chiffrement "$(agent_de sc-confiance)")" "Encryption: Wireguard [NodeEncryption: OptedOut, cilium_wg0 (Port: 51871, Peers: 2)]"
  attendu "sc-build, chiffrement" "$(etat_chiffrement "$(agent_de sc-build)")" "Encryption: Wireguard [NodeEncryption: Enabled, cilium_wg0 (Port: 51871, Peers: 2)]"
  attendu "sc-stockage, chiffrement" "$(etat_chiffrement "$(agent_de sc-stockage)")" "Encryption: Wireguard [NodeEncryption: Enabled, cilium_wg0 (Port: 51871, Peers: 2)]"
  while read -r p; do
    attendu "$p, état" "$(kubectl exec -n kube-system "$p" -c cilium-agent -- cilium-dbg status --brief </dev/null 2>&1 | tail -1)" OK
    attendu "$p, Hubble" "$(kubectl exec -n kube-system "$p" -c cilium-agent -- cilium-dbg status </dev/null 2>/dev/null | awk '$1 == "Hubble:" {print $2}')" Ok
  done < <(kubectl get pods -n kube-system -l k8s-app=cilium -o json </dev/null | jq -r '.items[].metadata.name')
  attendu "redémarrages de conteneurs du cluster" "$(redemarrages)" "$r0"
  for v in sc-confiance sc-build sc-stockage; do echo "$v : MTU de route $(mtu_routes "$v")"; echo "$v : refus $(refus_agent "$v")"; done
  kubectl get nodes --no-headers </dev/null
  [ "$ko" = 0 ] && echo "OK   h6" || { echo "KO   h6"; exit 1; }
}

etape_h6_mesure() {
  exige_rke2
  local f0 s0 d0 c=0 k=$T/capture-h6.txt j=$b08/resultats/preuves-h6-construction_durcie.log
  attendu "sc-build, chiffrement" "$(etat_chiffrement "$(agent_de sc-build)")" "Encryption: Wireguard [NodeEncryption: Enabled, cilium_wg0 (Port: 51871, Peers: 2)]"
  f0=$(fragments sc-build); s0=$(fragments sc-stockage); d0=$(refus_agent sc-build)
  sur sc-build "sudo timeout -s INT 900 tcpdump -n -q -l -p -i enp1s0 'ip and not port 22' 2>/dev/null" </dev/null > "$k" &
  sleep 2
  JOURNAL=preuves-h6 timeout 840 mise run confiance:preuves -- construction_durcie </dev/null || c=$?
  sur sc-build 'sudo pkill -INT -x tcpdump' </dev/null || true
  wait
  attendu "construction, code de retour" "$c" 0
  echo "## paquets vus sur enp1s0 de sc-build pendant la construction : classe, pair, nombre"
  classes_capture "$k" | tee "$k.classes"
  attendu "paquets de pods en clair" "$(awk '$1 == "pods-en-clair" { n += $3 } END { print n + 0 }' "$k.classes")" 0
  attendu "paquets en clair avec sc-stockage" "$(awk '$1 == "clair" && $2 == "192.168.161.13" { n += $3 } END { print n + 0 }' "$k.classes")" 0
  [ "$(awk '$1 == "tunnel" && $2 == "192.168.161.13" { n += $3 } END { print n + 0 }' "$k.classes")" -ge 1 ] && echo "OK   témoin : paquets du tunnel vers sc-stockage" || { echo "KO   aucun paquet du tunnel vers sc-stockage : le contrôle serait vide"; ko=1; }
  echo "## fragments, avant puis après"
  echo "sc-build : $f0 / $(fragments sc-build)"
  echo "sc-stockage : $s0 / $(fragments sc-stockage)"
  echo "## refus de l'agent de sc-build, avant puis après"
  echo "$d0"; refus_agent sc-build
  if grep -Fq 'IMAGE_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5' "$j"; then echo "OK   image 3a7ca1b1 identique"; else echo "KO   image différente de 3a7ca1b1"; ko=1; fi
  rm -f "$k"
  [ "$ko" = 0 ] && echo "OK   h6_mesure" || { echo "KO   h6_mesure"; exit 1; }
}

etape_h6_retrait() {
  exige_rke2
  local c0 p0 w0 r0 v a=$T/coupure-h6-retrait.txt
  c0=$(versions_certs); p0=$(pare_feu); w0=$(temoins_h6); r0=$(redemarrages)
  suspendre_rattrapage
  sonde_coupure 240 192.168.161.13:5000 "$(ip_coredns sc-stockage):53" "$(ip_coredns sc-confiance):53" > "$a" &
  date -u '+retrait %H:%M:%S UTC'
  VALEURS_08C=$C/valeurs-cilium.yaml "$b08/cilium.sh" appliquer
  date -u '+agents prêts %H:%M:%S UTC'
  wait
  resume_coupure "$a"
  kubectl delete -f "$WG_POL" </dev/null
  attendu "clés de chiffrement dans cilium-config" "$(kubectl -n kube-system get cm cilium-config -o json </dev/null | jq -c '[.data | keys[] | select(test("wireguard|encrypt"))]')" '[]'
  kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
  sleep 30
  for v in sc-confiance sc-build sc-stockage; do
    attendu "SSH de $v" "$(sur "$v" 'echo joint' </dev/null || true)" joint
    attendu "$v, chiffrement" "$(etat_chiffrement "$(agent_de "$v")")" "Encryption: Disabled"
    attendu "$v, interfaces WireGuard" "$(sur "$v" 'ip -br link show type wireguard | grep -c . || true' </dev/null)" 0
    echo "$v : module chargé=$(sur "$v" 'lsmod | grep -c "^wireguard " || true' </dev/null), MTU de route $(mtu_routes "$v")"
  done
  attendu "API" "$(kubectl get --raw /readyz || true)" ok
  attendu "certificats" "$(versions_certs)" "$c0"
  attendu "pare-feu depuis sc-build" "$(pare_feu)" "$p0"
  attendu "témoins vers sc-stockage" "$(temoins_h6)" "$w0"
  sonde_kyverno
  attendu "redémarrages de conteneurs du cluster" "$(redemarrages)" "$r0"
  attendu "hote-wireguard en service" "$(kubectl get ccnp hote-wireguard --ignore-not-found -o name </dev/null)" ""
  kubectl get nodes --no-headers </dev/null
  [ "$ko" = 0 ] && echo "OK   h6_retrait" || { echo "KO   h6_retrait"; exit 1; }
}

for e in "$@"; do
  { echo "# durcissement.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ), DISTRO=$DISTRO"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/durcissement-$e.log"
  [ "${PIPESTATUS[0]}" = 0 ] || exit 1
done
