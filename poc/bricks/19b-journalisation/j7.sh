#!/usr/bin/env bash
# Brique 19b, J7, étape 2 recadrée (carte resultats/j7-carte.md, note « Étape 2 recadrée ») : deux pods Kata d'essai dans
# builds, puis lecture de Hubble dans l'agent Cilium de sc-build, en comptes seulement (jamais de flux bruts archivés).
# Les valeurs de Cilium ne sont pas touchées : aucun export n'est posé.
#   sec     à sec : les deux pods rendus, créés en dry-run serveur (admission comprise) ; rien n'est créé
#   mesure  cluster : pod a (sans label de tâche, témoin positif T0) puis pod b (label construire-rpm, T1 à T6, T8) ;
#           témoins de construire-rpm dans le pod ; ACCORD NOMMÉ DU PROPRIÉTAIRE : kubectl exec dans l'agent Cilium de
#           sc-build (hubble observe) ; pods supprimés ; catalogue de Zot relu en anonyme avant et après
# Usage (racine du dépôt) : mise exec -- poc/bricks/19b-journalisation/j7.sh <étape>…   (journal : resultats/j7-<étape>.log)
set -euo pipefail
export LC_ALL=C

h19b=$(cd "$(dirname "$0")" && pwd)
here=$h19b/../08-trust-plane
. "$here/commun.sh"   # O, P, W, REG, REG_HOTE, lancer, chrono
R=$h19b/resultats
N=${PREFIXE:-j7}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
T=$W/$N-19b
mkdir -p "$T"
umask 022

TACHE=$h19b/../05-rpm-mock/construction/construire-rpm.m1b.signee.yaml   # contexte et ressources du pas construire
IMAGE_OUTILLAGE=$REG/builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae   # M1b (m1b-r1r8.sh)
LABEL_CONSTRUIRE=construire-rpm   # sélectionné par construction-rpm-sans-sortie
ZOT_CIBLE=192.168.161.13/5000
ZONE='{"nodeSelector": {"zone": "build"}, "tolerations": [{"key": "zone", "operator": "Equal", "value": "build", "effect": "NoSchedule"}],
  "securityContext": {"runAsNonRoot": true, "runAsUser": 65532, "seccompProfile": {"type": "RuntimeDefault"}}}'   # m1b-r1r8.sh
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echec() { echo "KO   $*" >&2; exit 1; }
filtre() { sed "$MASQUE"; }
present() { kubectl get pod -n builds "$1" -o name < /dev/null > /dev/null 2>&1; }

pod_json() { # nom label|- : pod d'essai Kata, forme des pods de R7 (m1b-r1r8.sh), sans PVC ; label de tâche seulement si demandé
  jq -n --arg n "$1" --arg lb "$2" --arg i "$IMAGE_OUTILLAGE" --arg j "$N" --argjson z "$ZONE" \
    --argjson sc "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .securityContext' "$TACHE")" \
    --argjson res "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .resources' "$TACHE")" '
    {apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds",
       labels: ({"poc.test/jalon": $j} + (if $lb == "-" then {} else {"tekton.dev/task": $lb} end))},
     spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, enableServiceLinks: false,
       runtimeClassName: "kata",
       volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: "1Gi"}}],
       containers: [{name: "essai", image: $i, command: ["sleep", "900"], securityContext: $sc, resources: $res,
         volumeMounts: [{name: "w", mountPath: "/w"}]}]} + $z)}' > "$T/pod-$1.json"
}

rendre() {
  pod_json "$N-a" -
  pod_json "$N-b" "$LABEL_CONSTRUIRE"
  attendu "labels de tâche (a, b)" "$(jq -r '.metadata.labels["tekton.dev/task"] // "-"' "$T/pod-$N-a.json" "$T/pod-$N-b.json" | paste -sd' ')" "- $LABEL_CONSTRUIRE"
  attendu "contexte du conteneur, celui du pas signé" "$(jq -cS '.spec.containers[0].securityContext' "$T/pod-$N-b.json")" \
    "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .securityContext' "$TACHE" | jq -cS .)"
}

# Témoins du pod : ceux de construire-rpm (lignes 76 à 82 de construire-rpm.yaml) pour b ; TCP vers Zot seul pour a
temoins() { # a|b : script des témoins, codes sur la sortie
  if [ "$1" = a ]; then
    printf '%s\n' 'r=0; timeout 10 bash -c "exec 3<>/dev/tcp/'"$ZOT_CIBLE"'" 2> /dev/null || r=$?; echo "J7-POD tcp '"$ZOT_CIBLE"' code $r"'
  else
    printf '%s\n' 'r=0; timeout 10 getent hosts dl.rockylinux.org > /dev/null 2>&1 || r=$?; echo "J7-POD dns dl.rockylinux.org code $r"' \
      'for c in 192.168.161.13/5000 192.168.161.13/3000 199.232.170.132/80; do r=0; timeout 10 bash -c "exec 3<>/dev/tcp/$c" 2> /dev/null || r=$?; echo "J7-POD tcp $c code $r"; done'
  fi
}

agent_build() { kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=sc-build -o jsonpath='{.items[0].metadata.name}' < /dev/null; }

comptes() { # fichier-json-lignes libellé : comptes seulement (aucun flux brut n'est affiché ni archivé)
  echo "$2 : $(grep -c . "$1" || true) flux"
  jq -rs '
    def c(f): (map(f // "-" | tostring) | group_by(.) | map("\(.[0])=\(length)") | join(" "));
    map(.flow) |
    "  verdict : \(c(.verdict))",
    "  drop_reason_desc : \(c(.drop_reason_desc))",
    "  traffic_direction : \(c(.traffic_direction))",
    "  event_type.type : \(c(.event_type.type))",
    "  destination (adresse:port) : \(c((.IP.destination // "-") + ":" + ((.l4.TCP.destination_port // .l4.UDP.destination_port // "-") | tostring)))",
    "  source.namespace/pod_name : \(c((.source.namespace // "∅") + "/" + (.source.pod_name // "∅")))",
    "  destination.namespace/pod_name : \(c((.destination.namespace // "∅") + "/" + (.destination.pod_name // "∅")))",
    "  sortants non DROPPED : \(map(select(.traffic_direction == "EGRESS" and .verdict != "DROPPED")) | length)"' "$1"
}

catalogue() { mkdir -p "$T/anonyme"; DOCKER_CONFIG=$T/anonyme SSL_CERT_FILE=$P/ca-poc.crt crane catalog "$REG_HOTE" < /dev/null | grep -c . || true; }

etape_sec() { # rien n'est créé : dry-run serveur (admission comprise)
  local p
  rendre
  for p in "$N-a" "$N-b"; do
    ! present "$p" || echec "pod $p déjà présent : relancer sous un autre PREFIXE"
    kubectl create --dry-run=server -f "$T/pod-$p.json" -o json < /dev/null > "$T/sec-$p.json" 2> "$T/sec-$p.err" \
      || { filtre < "$T/sec-$p.err" | cut -c1-300; echec "pod $p refusé en dry-run serveur"; }
    echo "OK   $p admis à blanc : $(jq -r '[.spec.runtimeClassName, .spec.nodeSelector.zone, (.metadata.labels["tekton.dev/task"] // "sans label de tâche"), .spec.containers[0].image[-19:]] | join(" ; ")' "$T/sec-$p.json")"
  done
  echo "agent Cilium de sc-build : $(agent_build) (aucun exec à cette étape)"
}

etape_mesure() { # ACCORD NOMMÉ : kubectl exec dans l'agent Cilium de sc-build (hubble observe, lecture seule, comptes)
  local c p ip t0 a k0 k1
  rendre
  a=$(agent_build); echo "agent Cilium de sc-build : $a"
  k0=$(catalogue); echo "catalogue de Zot (anonyme), avant : $k0 dépôt(s)"
  for c in a b; do
    p=$N-$c
    echo "## pod $c ($(jq -r '.metadata.labels["tekton.dev/task"] // "sans label de tâche"' "$T/pod-$p.json"))"
    ! present "$p" || echec "pod $p déjà présent : relancer sous un autre PREFIXE"
    kubectl create -f "$T/pod-$p.json" < /dev/null > /dev/null; echo "pod $p créé à $(date -u +%H:%M:%S)"
    kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null || echec "pod $p non prêt"
    ip=$(kubectl get pod -n builds "$p" -o jsonpath='{.status.podIP}' < /dev/null)
    echo "pod prêt : $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName {.spec.runtimeClassName}' < /dev/null), IP $ip"
    temoins "$c" > "$T/temoins-$c.sh"
    t0=$(date -u +%Y-%m-%dT%H:%M:%SZ); sleep 1
    kubectl exec -i -n builds "$p" -- bash -s < "$T/temoins-$c.sh" 2>&1 | filtre | tee "$T/temoins-$c.out"
    sleep 5
    kubectl -n kube-system exec "$a" -c cilium-agent -- hubble observe --since "$t0" --pod "builds/$p" -o json < /dev/null > "$T/hubble-pod-$c.json" 2> "$T/hubble-pod-$c.err" || true
    kubectl -n kube-system exec "$a" -c cilium-agent -- hubble observe --since "$t0" --ip "$ip" -o json < /dev/null > "$T/hubble-ip-$c.json" 2> "$T/hubble-ip-$c.err" || true
    [ ! -s "$T/hubble-pod-$c.err" ] || { echo "sortie d'erreur de hubble (filtre --pod) :"; filtre < "$T/hubble-pod-$c.err" | head -n 3; }
    comptes "$T/hubble-ip-$c.json" "Hubble, filtre --ip $ip (comme la 08)"
    comptes "$T/hubble-pod-$c.json" "Hubble, filtre --pod builds/$p (celui de l'export)"
    kubectl delete pod -n builds "$p" --wait=true < /dev/null > /dev/null; echo "pod $p supprimé à $(date -u +%H:%M:%S)"
  done
  k1=$(catalogue); attendu "catalogue de Zot (anonyme), après" "$k1" "$k0"
  attendu "pods du jalon restants" "$(kubectl get pod -n builds -l "poc.test/jalon=$N" -o name < /dev/null | wc -l)" 0
}

for e in "$@"; do [ ! -e "$R/$N-$e.log" ] || { echo "journal déjà présent : resultats/$N-$e.log (relancer sous un autre PREFIXE)" >&2; exit 2; }; done
lancer "$N" "19b J7" "$@"
