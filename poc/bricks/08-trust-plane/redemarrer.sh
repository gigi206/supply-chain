#!/usr/bin/env bash
# Brique 08 : redémarrage complet des trois VM (arrêt propre puis démarrage), comme après un redémarrage du laptop.
#   Avant : témoin OpenBao (message signé par la clé chains). Après : nœuds Ready, Zot et Forgejo actifs et lisibles
#   (manifeste sample-app par digest, branche main), OpenBao scellé puis descellé (deverrouiller), même clé Transit ;
#   TSA (J5) relancé avec un nouveau jeton OpenBao, jeton témoin vérifié (tsa.sh temoin).
#   J6 : Kyverno prêt et répondant avant OpenBao, le TSA et Tekton (webhooks en failurePolicy Fail : un pod créé avant
#   qu'il réponde est refusé ; sonde : refus attendu de la règle zone-confiance, dry-run serveur) ; Tekton et
#   EventListener prêts ; un passage réussi de chaque CronJob (horodatage, rattrapage) créé après le retour du TSA.
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

sonde_kyverno() { # pod de tsa sans nodeSelector (conforme à Pod Security restricted, qui passe avant les webhooks), créé en
  # dry-run serveur : refus attendu de la règle zone-confiance de Kyverno, pas une erreur d'appel du webhook
  local img msg="" i
  img=$(kubectl get deployment -n tsa timestamp-authority -o jsonpath='{.spec.template.spec.containers[0].image}')
  jq -n --arg i "$img" '{apiVersion: "v1", kind: "Pod", metadata: {name: "sonde-kyverno", namespace: "tsa"},
    spec: {automountServiceAccountToken: false, securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "sonde", image: $i, securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}}' > "$T/sonde-kyverno.json"
  for i in $(seq 90); do
    msg=$(kubectl create --dry-run=server -f "$T/sonde-kyverno.json" 2>&1 || true)
    grep -qF 'zone confiance : nodeSelector zone=confiance obligatoire' <<<"$msg" && break
    sleep 2
  done
  grep -qF 'zone confiance : nodeSelector zone=confiance obligatoire' <<<"$msg" \
    && echo "OK   Kyverno répond à l'admission ($i essai(s)) : pod sans nodeSelector refusé par zone-confiance" \
    || { echo "KO   Kyverno ne répond pas : $msg" >&2; exit 1; }
}

passage_ok() { # espace CronJob instant : premier passage créé après l'instant, attendu réussi ; résumé de son journal.
  # Concurrence Forbid : un passage lancé avant le descellement peut retarder le suivant jusqu'à son échéance (300 s)
  local ns=$1 cj=$2 t=$3 j=""
  for _ in $(seq 210); do
    j=$(kubectl get jobs -n "$ns" -o json | jq -r --arg t "$t" --arg c "$cj" '[.items[] | select(any(.metadata.ownerReferences[]?; .kind == "CronJob"
      and .name == $c) and .metadata.creationTimestamp > $t and ((.status.succeeded // 0) + (.status.failed // 0)) > 0)]
      | sort_by(.metadata.creationTimestamp) | .[0].metadata.name // empty')
    [ -n "$j" ] && break
    sleep 2
  done
  [ -n "$j" ] || { echo "KO   aucun passage du CronJob $ns/$cj terminé depuis $t" >&2; exit 1; }
  kubectl logs -n "$ns" "job/$j" > "$T/passage-$cj.log" 2>&1 || true
  echo "passage $j : $(cut -d'|' -f1 "$T/passage-$cj.log" | sort | uniq -c | awk '{printf "%s %s ; ", $2, $1}')"
  [ "$(kubectl get job -n "$ns" "$j" -o jsonpath='{.status.succeeded}')" = 1 ] && echo "OK   $ns/$cj : passage réussi après le retour du TSA" \
    || { cat "$T/passage-$cj.log" >&2; echo "KO   $ns/$cj : passage $j en échec" >&2; exit 1; }
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
kubectl get pods -A -o wide
