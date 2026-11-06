#!/usr/bin/env bash
# Brique 08c : droits effectifs relevés pour H5, sans rien changer. Tous les sujets de toutes les liaisons, comptes de service, utilisateurs et groupes,
# et pas seulement les comptes de service : lecture de Secrets, moyens équivalents d'y accéder, écriture de HelmChart. Noms seulement, ne lit aucune valeur.
# Calcul sur les objets RBAC, puis recoupement par auth can-i de chaque lecteur trouvé, pour qu'une erreur du calcul se voie.
# Usage (racine du dépôt) : poc/bricks/08c-durcissement/essais-h5-droits.sh   (journal : resultats/durcissement-h5-droits.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
D=$(mktemp -d "$HOME/.cache/supply-chain-poc/08/travail/droits.XXXXXX")
trap 'rm -rf "${D:?}"' EXIT
SSHO=(-n -i "$HOME/.cache/supply-chain-poc/08/ssh/id_ed25519" -o "UserKnownHostsFile=$HOME/.cache/supply-chain-poc/08/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)

for k in clusterroles clusterrolebindings roles rolebindings; do kubectl get "$k" -A -o json </dev/null > "$D/$k.json"; done
kubectl get ns -o name </dev/null | sed 's#namespace/##' > "$D/ns"

{
  date -u '+relevé du %d/%m/%Y à %H:%M:%S UTC, rien de modifié'
  python3 -I - "$D" <<'EOF'
import json, sys, pathlib, collections
D = pathlib.Path(sys.argv[1])
charger = lambda n: json.loads((D / f"{n}.json").read_text())["items"]
cr = {o["metadata"]["name"]: o.get("rules") or [] for o in charger("clusterroles")}
ro = {(o["metadata"]["namespace"], o["metadata"]["name"]): o.get("rules") or [] for o in charger("roles")}

CAS = [
    ("secrets-lecture", "", "secrets", ("get", "list", "watch")),
    ("pods-creation", "", "pods", ("create",)),
    ("pods-exec", "", "pods/exec", ("create", "get")),
    ("jeton-sa", "", "serviceaccounts/token", ("create",)),
    ("noeuds-proxy", "", "nodes/proxy", ("get", "create")),
    ("emprunt", "", "users", ("impersonate",)),
    ("emprunt", "", "groups", ("impersonate",)),
    ("emprunt", "", "serviceaccounts", ("impersonate",)),
    ("rbac-escalade", "rbac.authorization.k8s.io", "clusterroles", ("escalate", "bind")),
    ("rbac-escalade", "rbac.authorization.k8s.io", "roles", ("escalate", "bind")),
    ("rbac-liaison", "rbac.authorization.k8s.io", "clusterrolebindings", ("create", "update", "patch")),
    ("rbac-liaison", "rbac.authorization.k8s.io", "rolebindings", ("create", "update", "patch")),
    ("webhooks", "admissionregistration.k8s.io", "validatingwebhookconfigurations", ("create", "update", "patch", "delete")),
    ("webhooks", "admissionregistration.k8s.io", "mutatingwebhookconfigurations", ("create", "update", "patch", "delete")),
    ("helmchart-ecriture", "helm.cattle.io", "helmcharts", ("create", "update", "patch")),
    ("helmchart-ecriture", "helm.cattle.io", "helmchartconfigs", ("create", "update", "patch")),
]

def donne(regle, groupe, ressource, verbe):
    if regle.get("nonResourceURLs"):
        return None
    g, r, v = regle.get("apiGroups") or [], regle.get("resources") or [], regle.get("verbs") or []
    if not ((groupe in g or "*" in g) and (ressource in r or "*" in r) and (verbe in v or "*" in v)):
        return None
    return "noms:" + ",".join(regle["resourceNames"]) if regle.get("resourceNames") else "tous"

droits = collections.defaultdict(set)
def noter(sujets, regles, portee, role):
    for s in sujets or []:
        ns = s.get("namespace", "")
        nom = f"{s['kind']}:{ns + '/' if ns else ''}{s['name']}"
        for regle in regles:
            for cas, groupe, ressource, verbes in CAS:
                for verbe in verbes:
                    d = donne(regle, groupe, ressource, verbe)
                    if d:
                        droits[nom].add((cas, f"{ressource}.{verbe}", portee, d, role))

for b in charger("clusterrolebindings"):
    noter(b.get("subjects"), cr.get(b["roleRef"]["name"], []), "cluster", b["roleRef"]["name"])
for b in charger("rolebindings"):
    n, ref = b["metadata"]["namespace"], b["roleRef"]
    regles = cr.get(ref["name"], []) if ref["kind"] == "ClusterRole" else ro.get((n, ref["name"]), [])
    noter(b.get("subjects"), regles, f"espace {n}", ref["name"])

ordre = ["secrets-lecture", "helmchart-ecriture", "jeton-sa", "emprunt", "rbac-escalade", "rbac-liaison", "webhooks", "noeuds-proxy", "pods-exec", "pods-creation"]
for cas in ordre:
    print(f"## {cas}")
    lignes = collections.defaultdict(set)
    for sujet, ds in droits.items():
        for c, quoi, portee, d, role in ds:
            if c == cas:
                lignes[(sujet, portee, d, role)].add(quoi.rsplit(".", 1)[1])
    for (sujet, portee, d, role), verbes in sorted(lignes.items(), key=lambda x: (x[0][1] != "cluster", x[0][0], x[0][1])):
        print(f"  {portee:<28} {sujet} {','.join(sorted(verbes))} [{d}] par {role}")
    print(f"  ({len({k[0] for k in lignes})} sujet(s))")

with open(D / "lecteurs", "w") as f:
    for sujet, ds in sorted(droits.items()):
        if any(c == "secrets-lecture" and p == "cluster" and d == "tous" for c, _, p, d, _ in ds) and sujet.startswith("ServiceAccount:"):
            f.write(sujet.split(":", 1)[1] + "\n")
EOF

  echo "## recoupement par auth can-i, à l'échelle du cluster (toutes les valeurs attendues : le calcul ci-dessus)"
  while read -r c; do
    u=system:serviceaccount:${c%/*}:${c#*/}
    echo "  $c get=$(kubectl auth can-i get secrets -A --as="$u" </dev/null 2>/dev/null) list=$(kubectl auth can-i list secrets -A --as="$u" </dev/null 2>/dev/null) watch=$(kubectl auth can-i watch secrets -A --as="$u" </dev/null 2>/dev/null)"
  done < "$D/lecteurs"

  echo "## Secrets du cluster, par espace et type, noms masqués, valeurs non lues"
  kubectl get secrets -A --no-headers -o custom-columns=E:.metadata.namespace,T:.type </dev/null | sort | uniq -c | awk '{printf "  %s %s %s\n", $1, $2, $3}'

  echo "## règle de cilium-operator sur les Secrets, et ce qu'en dit sa configuration"
  kubectl get clusterrole cilium-operator -o json </dev/null | jq -c '.rules[] | select((.resources // []) | index("secrets"))'
  kubectl get roles,rolebindings -A -o json </dev/null | jq -r '.items[] | select(.metadata.name | test("cilium")) | "  \(.kind) \(.metadata.namespace)/\(.metadata.name)"'
  kubectl get configmap -n kube-system cilium-config -o json </dev/null | jq -r '.data | to_entries[] | select(.key | test("ingress|gateway|secrets|tls-|clustermesh|policy-secrets|envoy-secrets")) | "  \(.key)=\(.value | .[0:60])"'

  echo "## lectures de Secrets par les lecteurs, audit de l'API, depuis le début des fichiers conservés (compte, verbe, espace ; champs de métadonnées seulement)"
  ssh "${SSHO[@]}" poc@192.168.161.11 "sudo sh -c 'cat \$(ls -1 /var/lib/rancher/rke2/server/logs/audit*.log | LC_ALL=C sort) | grep -F \"\\\"resource\\\":\\\"secrets\\\"\" | grep -E \"cilium-operator|generic-garbage-collector|namespace-controller|resourcequota-controller|tekton-triggers-core-interceptors\" || true'" </dev/null \
    | jq -r 'select(.stage == "ResponseComplete") | "\(.user.username | sub("system:serviceaccount:"; "")) \(.verb) \(.objectRef.namespace // "<cluster>") \(.responseStatus.code)"' \
    | sort | uniq -c | sort -k2,2 -k1,1rn | awk '{printf "  %s\n", $0}' | head -60

  echo "## contrôleur Helm de RKE2, processus et manifestes (noms seulement ; config.yaml non lu)"
  ssh "${SSHO[@]}" poc@192.168.161.11 "sudo ls -1 /var/lib/rancher/rke2/server/manifests/ 2>&1 | head -20; sudo sh -c 'ls -1 /var/lib/rancher/rke2/server/manifests/ | wc -l'" </dev/null
  kubectl get crd -o name </dev/null | grep -c cattle || true
  kubectl get addons.k3s.cattle.io -A --no-headers </dev/null 2>&1 | cut -c1-90 | head -20
  kubectl get jobs -n kube-system --no-headers </dev/null 2>&1 | cut -c1-90 | head
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$here/resultats/durcissement-h5-droits.log"
