#!/usr/bin/env bash
# Brique 08 : redémarrage complet des trois VM (arrêt propre puis démarrage), comme après un redémarrage du laptop.
#   Avant : témoin OpenBao (message signé par la clé chains). Après : nœuds Ready, Zot et Forgejo actifs et lisibles
#   (manifeste sample-app par digest, branche main), OpenBao scellé puis descellé (deverrouiller), même clé Transit ;
#   TSA (J5) relancé avec un nouveau jeton OpenBao, jeton témoin vérifié (tsa.sh temoin).
#
# Usage (racine du dépôt) : mise run confiance:redemarrer   (journal : resultats/redemarrage-vm.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
exec > >(sed -u "s#$HOME#~#g" | tee "$R/redemarrage-vm.log") 2>&1
echo "# redemarrer.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
duree() { local t=$1; shift; "$@"; echo "## durée $(( $(date +%s) - t )) s : $*"; }

boot() { kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.nodeInfo.bootID}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null; }

mise run confiance:openbao -- deverrouiller temoin   # descellé d'abord : rejouable après un arrêt
avant=$(boot)
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
kubectl get pods -A -o wide
