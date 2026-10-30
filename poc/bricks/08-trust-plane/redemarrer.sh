#!/usr/bin/env bash
# Brique 08 : redémarrage complet des trois VM (arrêt propre puis démarrage), comme après un redémarrage du laptop.
#   Avant : témoin OpenBao (message signé par la clé chains). Après : nœuds Ready, Zot et Forgejo actifs et lisibles
#   (manifeste sample-app par digest, branche main), OpenBao scellé puis descellé (deverrouiller), même clé Transit ;
#   TSA (J5) relancé avec un nouveau jeton OpenBao, jeton témoin vérifié (tsa.sh temoin).
#   J6 : Kyverno prêt et répondant avant OpenBao, le TSA et Tekton (webhooks en failurePolicy Fail : un pod créé avant
#   qu'il réponde est refusé ; sonde : refus attendu de la règle zone-confiance, dry-run serveur) ; Tekton et
#   EventListener prêts ; un passage réussi de chaque CronJob (horodatage, rattrapage) créé après le retour du TSA.
#   J7 : runtime kata rechargé par containerd sur sc-build, exemption Pod Security de kata relue, pod Kata lancé dans l'invité
#   (kata.sh temoin). sonde_kyverno et passage_ok sont dans commun.sh (aussi utilisées par kata.sh exemption).
#   Cilium (J7, option 1b), seulement si le cluster tourne sous Cilium : agents et opérateur prêts depuis le redémarrage, avant
#   les autres contrôles (sans agent prêt, aucun pod du nœud n'a de réseau) ; cilium-dbg status et policy-cidr-match-mode
#   (bêta) relus dans chaque agent ; en fin de script, la mesure réseau de référence (kata.sh reseau : fenêtre, usurpations).
#
# Usage (racine du dépôt) : mise run confiance:redemarrer   (journal : resultats/redemarrage-vm.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
T=$W/redemarrer
mkdir -p "$T"
exec > >(sed -u "s#$HOME#~#g" | tee "$R/redemarrage-vm.log") 2>&1
echo "# redemarrer.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
duree() { local t=$1; shift; "$@"; echo "## durée $(( $(date +%s) - t )) s : $*"; }

boot() { kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.nodeInfo.bootID}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null; }

prets() { # espace : chaque pod hors jobs passé Ready après l'arrêt ($arret) ; l'API garde l'état d'avant tant que kubelet
  # n'a pas réécrit le statut du pod
  local ns=$1 n=1 total=0
  for _ in $(seq 120); do
    read -r total n < <(kubectl get pods -n "$ns" -o json | jq -r --arg t "$arret" '[.items[] | select(any(.metadata.ownerReferences[]?; .kind == "Job") | not)]
      | [length, ([.[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True" and .lastTransitionTime >= $t) | not)] | length)] | @tsv') || { total=0; n=1; }
    [ "$total" -ge 1 ] && [ "$n" = 0 ] && break
    sleep 2
  done
  [ "$total" -ge 1 ] && [ "$n" = 0 ] && echo "OK   $ns : $total pod(s) prêts depuis le redémarrage" \
    || { echo "KO   $ns : $n pod(s) sur $total non prêts depuis le redémarrage" >&2; kubectl get pods -n "$ns" >&2; exit 1; }
}


mise run confiance:openbao -- deverrouiller temoin   # descellé d'abord : rejouable après un arrêt
avant=$(boot)
arret=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # aucun pod ne peut passer Ready entre l'arrêt et le démarrage : marge d'horloge
duree "$(date +%s)" mise run confiance:vm -- arreter
duree "$(date +%s)" mise run confiance:vm -- demarrer
# Juste après le démarrage, l'API garde l'état d'avant (nœuds « Ready », pods prêts) tant que les kubelets ne se sont pas
# réenregistrés : on attend un nouveau bootID sur chaque nœud, puis Ready.
t=$(date +%s)
ok=0
for _ in $(seq 120); do
  apres=$(boot || true)
  n=0
  while IFS='=' read -r nom id pret; do
    [ -n "$nom" ] || continue
    grep -qxF "$nom=$id=True" <<<"$avant" && continue
    [ "$pret" = True ] && ! grep -F "=$id=" <<<"$avant" >/dev/null && n=$((n + 1))
  done <<<"$apres"
  [ "$n" = 3 ] && { ok=1; break; }
  sleep 2
done
[ "$ok" = 1 ] || { echo "KO   nœuds non redémarrés ou non prêts" >&2; boot >&2; exit 1; }
echo "## durée $(( $(date +%s) - t )) s : trois nœuds réenregistrés (nouveau bootID) et Ready"
for vm in sc-confiance sc-build sc-stockage; do echo "$vm : démarré à $(sur "$vm" 'uptime -s')"; done
kubectl get nodes -o wide -L zone

if [ "$(reseau)" = cilium ]; then
  echo "## Cilium (J7, option 1b), avant les autres contrôles"
  echo "prédiction (écrite le 30/10/2026, avant le premier redémarrage des VM sous Cilium) : agents (3/3) et opérateur prêts"
  echo "depuis le redémarrage ; cilium-dbg status OK et policy-cidr-match-mode nodes relu par chacun des trois agents ;"
  echo "kata.sh reseau, en fin de script : mêmes constats qu'avant le redémarrage (aucune fenêtre, usurpations refusées)"
  prets kube-system
  d=$(kubectl -n kube-system get ds cilium -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}')
  [ "$d" = 3/3 ] && echo "OK   DaemonSet cilium : $d" || { echo "KO   DaemonSet cilium : $d" >&2; exit 1; }
  for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[*].metadata.name}'); do
    n=$(kubectl -n kube-system get pod "$p" -o jsonpath='{.spec.nodeName}')
    s=$(kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg status --brief 2>&1 | tail -1 || true)
    m=$(kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg config --all 2>/dev/null | awk '$1 ~ /PolicyCIDRMatchMode/ {v = $NF} END {print v}' || true)
    [ "$s" = OK ] && [ "$m" = "[nodes]" ] && echo "OK   agent $p ($n) : cilium-dbg status $s, PolicyCIDRMatchMode $m" \
      || { echo "KO   agent $p ($n) : cilium-dbg status $s, PolicyCIDRMatchMode $m" >&2; exit 1; }
  done
fi

echo "## stockage"
sur sc-stockage "systemctl is-active zot forgejo" | paste -sd' '
code=$(curl -s -o /dev/null -w '%{http_code}' -I --cacert "$P/ca-poc.crt" -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  "https://$REG_HOTE/v2/workspace/sample-app/manifests/$APP_DIGEST")
[ "$code" = 200 ] && echo "OK   Zot : manifeste sample-app par digest, lecture anonyme (HTTP $code)" || { echo "KO   Zot : HTTP $code" >&2; exit 1; }
c=$(curl -fsS --cacert "$P/ca-poc.crt" https://192.168.161.13:3000/api/v1/repos/workspace/sample-app/branches/main | jq -r .commit.id)
[ "$c" = 6391fd437f26696847041be3226bbbf633f55a2f ] && echo "OK   Forgejo : workspace/sample-app, main = $c" || { echo "KO   Forgejo : $c" >&2; exit 1; }

echo "## Kyverno (J6), avant OpenBao, le TSA et Tekton"
prets kyverno
sonde_kyverno

echo "## OpenBao"
st=""
for _ in $(seq 90); do
  st=$(kubectl exec -n openbao openbao-0 -- bao status -format=json 2>/dev/null || true)
  [ -n "$st" ] && break
  sleep 2
done
echo "après redémarrage : $(jq -c '{initialized, sealed}' <<<"$st") ; redémarrages du conteneur : $(kubectl get pod -n openbao openbao-0 -o jsonpath='{.status.containerStatuses[0].restartCount}')"
[ "$(jq -r .sealed <<<"$st")" = true ] && echo "OK   OpenBao scellé après le redémarrage des VM" || { echo "KO   OpenBao non scellé" >&2; exit 1; }
mise run confiance:openbao -- deverrouiller controle
echo "## TSA (J5) : nouveau jeton OpenBao au démarrage du pod, une fois OpenBao descellé"
# Pendant le scellement, la connexion du conteneur d'initialisation échoue et kubelet espace ses relances (jusqu'à 5 min) :
# on recrée le pod plutôt que d'attendre la relance suivante.
kubectl delete pod -n tsa -l app=timestamp-authority --wait=false >/dev/null
kubectl rollout status -n tsa deployment/timestamp-authority --timeout=180s
kubectl logs -n tsa deployment/timestamp-authority -c connexion
mise run confiance:tsa -- temoin
t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "## Tekton et EventListener (J6)"
for ns in tekton-pipelines tekton-pipelines-resolvers tekton-chains declencheurs; do prets "$ns"; done
echo "## CronJobs (J6) : un passage réussi de chacun, créé après le retour du TSA ($t)"
passage_ok horodatage horodatage "$t"
passage_ok declencheurs rattrapage "$t"
echo "## Kata (J7)"
mise run confiance:kata -- temoin
if [ "$(reseau)" = cilium ]; then
  echo "## Réseau des pods après le redémarrage (Cilium) : mesure de référence (journal resultats/kata-reseau.log)"
  mise run confiance:kata -- reseau
fi
kubectl get pods -A -o wide
