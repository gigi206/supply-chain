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
#   S1 de la 08c : si le contrôleur de Chains lit ses identifiants dans OpenBao (conteneur identifiants), pod recréé après le
#   descellement, comme celui du TSA. Sous RKE2 : DISTRO=rke2. Préparé à sec le 06/11/2026, jamais lancé sous H1 à H5.
#   Remède (b1) des Events (décision du propriétaire, « ok pour 1 b1 pour le moment », 10/11/2026) : une fois les nœuds Ready,
#   Alloy de sc-stockage est relancé, car Alloy v1.21.3 ne relance jamais l'observateur des Events après une erreur au démarrage
#   (API pas encore à l'écoute). Témoin : compteur de lignes d'Events transmises > 0 après la relance, sans erreur de
#   l'observateur dans le journal d'alloy. Un KO est différé en fin de script : il ne bloque ni OpenBao ni le reste.
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


# Remède (b1) des Events, entre les marqueurs ci-dessous (essai hors cluster : 08c, resultats/b1-essai-local.log).
# debut-b1
alloy_debut() { sur sc-stockage "systemctl show -p ActiveEnterTimestamp --value alloy" </dev/null || true; }
alloy_evenements() { # relance Alloy de sc-stockage ; rend 0 si des lignes d'Events sont transmises après la relance, 1 sinon
  local a0 a1 e u r=0 n=0 err=0
  # « || true » côté distant : list-unit-files rend 1 pour une unité absente ; seul un échec de ssh (255) reste un code non nul
  u=$(sur sc-stockage "systemctl list-unit-files alloy.service --no-legend || true" </dev/null 2>/dev/null) || r=$?
  [ "$r" = 0 ] || { echo "KO   sc-stockage injoignable : unité alloy illisible (code $r), rien relancé" >&2; return 1; }
  [ -n "$u" ] || { echo "--   Alloy absent de sc-stockage (19b non posée) : rien relancé"; return 0; }
  a0=$(alloy_debut)
  sur sc-stockage "sudo systemctl restart alloy" </dev/null || { echo "KO   relance d'Alloy refusée" >&2; return 1; }
  a1=$(alloy_debut)
  if [ -z "$a1" ] || { [ -n "$a0" ] && [ "$(date -ud "$a1" +%s)" -le "$(date -ud "$a0" +%s)" ]; }; then
    echo "KO   Alloy non relancé (actif depuis ${a1:-?}, avant ${a0:-?})" >&2; return 1
  fi
  e=$(date -ud "$a1" +%s)
  echo "Alloy relancé, actif depuis $(date -ud "@$e" +%Y-%m-%dT%H:%M:%SZ)"
  for _ in $(seq 60); do   # 5 min au plus ; le compteur repart de zéro à la relance
    n=$(sur sc-stockage "curl -s http://127.0.0.1:12345/metrics" </dev/null \
      | awk '$1 ~ /^loki_process_custom_evenements_lignes_total/ {s += $NF} END {print (s > 0) ? int(s) : 0}' || true)
    err=$(sur sc-stockage "sudo journalctl -u alloy --since @$e -o cat" </dev/null \
      | grep -c -E 'event watcher exited with error|failed to start informers' || true)
    [ "${err:-0}" -gt 0 ] || [ "${n:-0}" -gt 0 ] && break
    sleep 5
  done
  if [ "${err:-0}" -gt 0 ]; then echo "KO   observateur des Events en erreur après la relance ($err ligne(s) d'erreur)" >&2; return 1; fi
  if [ "${n:-0}" -gt 0 ]; then echo "OK   Events transmis après la relance ($n ligne(s) au compteur)"; return 0; fi
  echo "KO   aucune ligne d'Event transmise 5 min après la relance" >&2; return 1
}
# fin-b1

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
echo "## Alloy de sc-stockage (remède (b1) des Events), avant Cilium : un KO est différé en fin de script"
alloy_ko=0
alloy_evenements || alloy_ko=1

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
if kubectl get deployment -n tekton-chains tekton-chains-controller -o json | jq -e 'any(.spec.template.spec.initContainers[]?; .name == "identifiants")' >/dev/null; then
  echo "## Chains (S1 de la 08c) : identifiants Zot relus dans OpenBao une fois descellé, mêmes relances espacées que le TSA"
  # --wait=true : l'ancien pod disparu, kubectl logs ne peut plus le choisir (premier passage de s1_chains, 06/11/2026)
  kubectl delete pod -n tekton-chains -l app.kubernetes.io/part-of=tekton-chains,app.kubernetes.io/component=controller --wait=true >/dev/null
  prets tekton-chains
  kubectl logs -n tekton-chains -l app.kubernetes.io/part-of=tekton-chains,app.kubernetes.io/component=controller -c identifiants
fi
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
[ "$alloy_ko" = 0 ] || { echo "KO   Events : collecte non rétablie après la relance d'Alloy (voir plus haut) ; l'alerte EvenementsMuets reste le filet" >&2; exit 1; }
