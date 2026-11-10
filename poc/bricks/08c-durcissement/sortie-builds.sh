#!/usr/bin/env bash
# Brique 08c : sortie Internet des pods de builds (constat P3 de la brique 06, S1, 10/11/2026). Option (a), préparée à sec,
# NON APPLIQUÉE : CiliumNetworkPolicy builds-sans-internet (politiques/cilium-sortie/), refus pur des adresses publiques pour
# tout pod de builds sauf prefetch-gomod. Prédictions : resultats/sortie-predictions.md, écrites et commitées avant exécution.
#   prealables  lecture seule : version des agents Cilium, enable-ipv6, policy-cidr-match-mode ; politiques de builds ; invariants
#               d'union (évaluateur commun ../08-trust-plane/selecteurs.jq) avant la règle
#   avant       témoins dans l'état actuel : trois pods runc de builds (sans label, label prefetch-gomod, label construire-image),
#               image d'outils du prefetch par digest, contexte de restricted, limites ; destinations : snapshot.debian.org (80),
#               proxy.golang.org (443), API de RKE2, Zot, Forgejo, résolution DNS
#   appliquer   règle posée ; invariants : pods de prefetch-gomod sélectionnés par prefetch-sortie seule ; aucune politique qui
#               autorise du trafic aux pods de construire-image hors construction-sans-sortie ; toute politique de builds qui
#               autorise une sortie par CIDR sélectionne des labels exclus du refus
#   apres       mêmes témoins, règle en place
#   bout_en_bout  vrai PipelineRun de la tête de main par le chemin du webhook (../08-trust-plane/preuves.sh construction_durcie) ;
#               journal de la 08 sauvé puis remis, celui de ce passage archivé ici (resultats/sortie-construction_durcie-preuves.log)
#   test6       test 6 de la 08 rejoué sous la règle (option (ii) : POLICY_DENY admis vers EXTERNE, contre-épreuve sans sortie vers
#               EXTERNE, témoin de capture par un pod brut au label prefetch-gomod) ; journal archivé ici (sortie-test6-preuves.log)
#   retirer     règle supprimée ; témoin : le pod sans label rejoint snapshot.debian.org
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/08c-durcissement/sortie-builds.sh <étape>…   (journal : resultats/sortie-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
b08=$here/../08-trust-plane
. "$b08/commun.sh"
REGLE=$here/politiques/cilium-sortie/builds-sans-internet.yaml
IMAGE=$REG/plateforme/outils-prefetch@sha256:68e0ae705de5a8f993f168d8252b3218d7d3ed76e704cf24d4414006aea7b8cc   # prefetch.sh (03)
LIMITES='{"cpu": "500m", "memory": "256Mi"}'
T=$W/sortie-builds
mkdir -p "$T"

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
politiques() { { kubectl get networkpolicy -n builds -o json </dev/null; kubectl get ciliumnetworkpolicy -n builds -o json </dev/null; } \
  | jq -s '{items: ([.[].items[]])}' > "$T/politiques.json"; }
sel() { jq -r -L "$b08" "include \"selecteurs\"; $1" "$T/politiques.json"; }   # filtre jq sur les politiques de builds

invariants() {
  politiques
  echo "politiques de builds : $(sel '[.items[] | nom] | join(", ")')"
  attendu "politiques qui sélectionnent un pod de prefetch-gomod" \
    "$(sel '[.items[] | select(selectionne({"tekton.dev/task": "prefetch-gomod"})) | nom] | sort | join(", ")')" "CiliumNetworkPolicy prefetch-sortie"
  attendu "politiques qui autorisent du trafic à un pod de construire-image" \
    "$(sel '[.items[] | select(selectionne({"tekton.dev/task": "construire-image"}) and autorise) | nom] | join(", ")')" ""
  # toute politique qui autorise une sortie par CIDR : ses matchLabels (seul sélecteur employé par ces règles) ne doivent pas être
  # retenus par une politique de refus de builds ; sinon le refus l'emporte sans bruit (deny.rst)
  attendu "politiques à sortie CIDR dont les pods seraient aussi sous un refus" \
    "$(sel '. as $tout | [.items[] | select(sortie_cidr) | (selecteur.matchLabels // {}) as $l | nom as $n
         | select(any($tout.items[]; ((.spec.egressDeny // []) | length > 0) and selectionne($l))) | $n] | join(", ")')" ""
}

DESTINATIONS='import socket, ssl, subprocess, urllib.request
ctx = ssl.create_default_context()
poc = ssl.create_default_context(cafile="/etc/ca-poc/ca.crt")
for nom in ["snapshot.debian.org", "sc-stockage.poc.test"]:
    try: print(f"DNS {nom} : résolu ({socket.getaddrinfo(nom, None)[0][4][0]})")
    except Exception as e: print(f"DNS {nom} : échec ({type(e).__name__})")
for nom, url, c in [("snapshot.debian.org en 80", "http://snapshot.debian.org/archive/debian/20261105T000000Z/dists/trixie/InRelease", None),
                    ("proxy.golang.org en 443", "https://proxy.golang.org/github.com/go-chi/chi/v5/@v/list", ctx),
                    ("API de RKE2", "https://192.168.161.11:6443/version", ssl._create_unverified_context()),
                    ("Zot", "https://sc-stockage.poc.test:5000/v2/", poc)]:
    try:
        r = urllib.request.urlopen(url, timeout=8, context=c) if c else urllib.request.urlopen(url, timeout=8)
        print(f"{nom} : joint (HTTP {r.status})")
    except urllib.error.HTTPError as e:
        print(f"{nom} : joint (HTTP {e.code})")
    except Exception as e:
        print(f"{nom} : refusé ({type(e).__name__})")
g = subprocess.run(["git", "-c", "http.sslCAInfo=/etc/ca-poc/ca.crt", "ls-remote", "https://sc-stockage.poc.test:3000/workspace/sample-app.git", "HEAD"],
                   capture_output=True, text=True, timeout=30)
print("Forgejo : " + ("joint" if g.returncode == 0 else "refusé"))'

temoins() { # libellé : trois pods, une ligne par destination
  local n l
  for p in "sans-label -" "prefetch prefetch-gomod" "construire construire-image"; do
    n=sortie-${p%% *}; l=${p#* }
    jq -n --arg n "$n" --arg l "$l" --arg i "$IMAGE" --argjson r "$LIMITES" '{apiVersion: "v1", kind: "Pod",
      metadata: ({name: $n, namespace: "builds"} + (if $l == "-" then {} else {labels: {"tekton.dev/task": $l}} end)),
      spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
        tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
        securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: "RuntimeDefault"}},
        volumes: [{name: "ca", configMap: {name: "ca-poc"}}],
        containers: [{name: "sonde", image: $i, command: ["sleep", "600"], resources: {requests: $r, limits: $r},
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
          volumeMounts: [{name: "ca", mountPath: "/etc/ca-poc", readOnly: true}]}]}}' > "$T/$n.json"
    kubectl delete pod -n builds "$n" --ignore-not-found --wait=true </dev/null >/dev/null
    kubectl create -f "$T/$n.json" </dev/null >/dev/null
    kubectl wait -n builds "pod/$n" --for=condition=Ready --timeout=180s </dev/null >/dev/null
    echo "### $n (label tekton.dev/task : $l)"
    kubectl exec -i -n builds "$n" -- python3 - <<<"$DESTINATIONS" 2>&1 | sed 's/^/     /' | tee "$T/$1-$n.txt"
    kubectl delete pod -n builds "$n" --wait=false </dev/null >/dev/null
  done
}

etape_prealables() {
  kubectl -n kube-system get ds cilium -o jsonpath='{.spec.template.spec.containers[0].image}' </dev/null | sed 's/^/agents Cilium : /'; echo
  kubectl -n kube-system get cm cilium-config -o json </dev/null \
    | jq -r '.data | "enable-ipv6 : \(.["enable-ipv6"] // "absent") ; policy-cidr-match-mode : \(.["policy-cidr-match-mode"] // "absent") ; enable-policy : \(.["enable-policy"] // "absent")"'
  echo "## invariants avant la règle (l'invariant à sortie CIDR est vide tant qu'aucun refus n'existe)"
  invariants
  kubectl get ciliumnetworkpolicy -n builds builds-sans-internet </dev/null >/dev/null 2>&1 && { echo "KO   règle déjà posée" >&2; exit 1; } || echo "OK   règle builds-sans-internet absente"
}
etape_avant() { temoins avant; }
etape_appliquer() {
  kubectl apply -f "$REGLE" </dev/null | sed 's/^/kubectl : /'
  for _ in $(seq 30); do [ "$(kubectl get cnp -n builds builds-sans-internet -o jsonpath='{.status.conditions[?(@.type=="Valid")].status}' </dev/null 2>/dev/null)" = True ] && break; sleep 2; done
  attendu "règle valide pour Cilium" "$(kubectl get cnp -n builds builds-sans-internet -o jsonpath='{.status.conditions[?(@.type=="Valid")].status}' </dev/null)" True
  invariants
}
etape_apres() { temoins apres; }
preuves() { # étape de ../08-trust-plane/preuves.sh : journal de la 08 sauvé puis remis, celui de ce passage archivé ici
  local j=$b08/resultats/preuves-$1.log rc=0
  cp "$j" "$T/preuves-$1.sauve"
  trap 'cp "$T/preuves-$1.sauve" "$j"' EXIT
  "$b08/preuves.sh" "$1" > /dev/null 2>&1 || rc=$?
  grep -i -v -E 'jeton|token' "$j" > "$R/sortie-$1-preuves.log"
  cp "$T/preuves-$1.sauve" "$j"; trap - EXIT
  grep -E '^(OK|KO)|durée du PipelineRun|builds-sans-internet' "$R/sortie-$1-preuves.log"
  attendu "preuves.sh $1, code de sortie" "$rc" 0
}
etape_bout_en_bout() { preuves construction_durcie; }
etape_test6() { preuves test6; }   # option (ii) : attentes du test 6 sous builds-sans-internet (preuves.sh, 10/11/2026)
etape_retirer() {
  kubectl delete -f "$REGLE" </dev/null | sed 's/^/kubectl : /'
  temoins retrait
}

lancer sortie "08c sortie de builds" "$@"
