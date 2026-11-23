#!/usr/bin/env bash
# Brique 07b, pièce 6 (ajout du 23/11/2026, après le report du patch 07b-t3 dans le dépôt, pièce 9) : pose de la porte neuve dans la
# ConfigMap porte/porte, par cm_porte de la 08 (seule source de la ConfigMap), lancé depuis une copie de HEAD (git archive).
# Accord du propriétaire du 23/11 : « Pièce 6 (porte) », avec les tâches de la 05 que le rendu ajoute à taches.yml.
# Étapes (une par journal, jamais réécrit) :
#   pose    rendu d'abord (apply remplacé par cat, comme piece6-porte.sh sec) : seules policy-scan.yaml, scan.rego et taches.yml
#           changent ; puis cm_porte tel quel ; après : chaque clé du service = clé du rendu ; politique servie : vex_age_max_jours 30,
#           statuts acceptés [not_affected].
#   grafana lecture seule : écritures de la ConfigMap porte dans l'audit de l'API (Loki, à travers Grafana), comptes seuls.
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/piece6-pose.sh <pose|grafana>  (journal : resultats/piece6-pose-<étape>.log)
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
racine_depot=$(cd "$here/../../.." && pwd)
O8=$HOME/.cache/supply-chain-poc/08
e=${1:-}
case $e in pose|grafana) ;; *) echo "usage : $0 <pose|grafana>" >&2; exit 2 ;; esac
L=$here/resultats/piece6-pose-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
KO=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
attendu() { [ "$2" = "$3" ] && ok "$1 : $2" || ko "$1 : $2 (attendu : $3)"; }
arret() { echo "KO   $*"; echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "bilan : rien posé"; exit 1; }
h() { sha256sum | cut -c1-16; }
cles() { jq -r '.data | to_entries[] | "\(.key) \(.value | @base64)"' "$1" | while read -r k v; do echo "$k $(printf '%s' "$v" | base64 -d | h)"; done; }
exec > "$L" 2>&1
echo "# piece6-pose.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$racine_depot" rev-parse --short=12 HEAD)"
case $e in
pose)
  T=$HOME/.cache/supply-chain-poc/07a/p6-pose
  [ ! -e "$T" ] || arret "dossier de travail déjà présent : $T"
  mkdir -m 700 "$T"
  trap 'find "$HOME/.cache/supply-chain-poc/07a/p6-pose" -delete' EXIT
  echo "## préalables"
  [ -z "$(git -C "$racine_depot" status --porcelain -- poc/bricks/07a-sbom-grype/politique poc/bricks/08-trust-plane)" ] || arret "fichiers de la pose modifiés hors commit"
  attendu "HEAD : vex_age_max_jours" "$(git -C "$racine_depot" show HEAD:poc/bricks/07a-sbom-grype/politique/porte/policy-scan.yaml | yq '.sources[0].ruleData.vex_age_max_jours')" 30
  attendu "HEAD : patch 07b-t3 déjà reporté (git apply --reverse --check)" "$(git -C "$racine_depot" apply --reverse --check poc/bricks/07a-sbom-grype/politique/07b-t3.patch > /dev/null 2>&1 && echo oui)" oui
  actifs=$(kubectl get pods -n porte --no-headers -o custom-columns=N:.metadata.name,P:.status.phase 2>/dev/null | awk '$2 == "Running" || $2 == "Pending" {print $1}')
  [ -z "$actifs" ] || arret "pod(s) actif(s) dans porte : $actifs"
  ok "aucun pod actif dans porte"
  [ "$KO" = 0 ] || arret "préalables non tenus"
  echo "## rendu depuis une copie de HEAD (apply remplacé par cat)"
  A=$T/arbre; mkdir "$A"
  git -C "$racine_depot" archive HEAD poc/bricks/07a-sbom-grype poc/bricks/08-trust-plane poc/bricks/10-independent-replay/resultats | tar -x -C "$A"
  P08=$A/poc/bricks/08-trust-plane
  f=$(awk '/^cm_porte\(\)/,/^}/' "$P08/politique.sh"); echo "  texte de cm_porte : $(printf '%s\n' "$f" | h)"
  g=${f/kubectl apply --server-side -f - >\/dev\/null/cat}
  attendu "cm_porte : une seule substitution apply -> cat" "$(printf '%s\n' "$g" | grep -c -- '-o yaml | cat$')/$(printf '%s\n' "$g" | grep -c 'kubectl apply')" 1/0
  eval "${g/cm_porte()/cm_porte_rendu()}"
  eval "$f"
  here_sauve=$here; here=$P08 R=$P08/resultats P=$O8/pki
  cm_porte_rendu < /dev/null > "$T/cm.yaml" 2> "$T/cm.err"; c=$?
  here=$here_sauve
  attendu "rendu de la ConfigMap porte, code" "$c" 0
  kubectl create --dry-run=client -o json -f "$T/cm.yaml" < /dev/null > "$T/cm.json"
  kubectl get cm -n porte porte -o json < /dev/null > "$T/avant.json"
  cles "$T/avant.json" > "$T/cles.avant"; cles "$T/cm.json" > "$T/cles.rendu"
  attendu "clés présentes, service et rendu" "$(cut -d' ' -f1 "$T/cles.avant" | paste -sd, -)" "$(cut -d' ' -f1 "$T/cles.rendu" | paste -sd, -)"
  attendu "clés dont le contenu change" "$(join "$T/cles.avant" "$T/cles.rendu" | awk '$2 != $3 {print $1}' | paste -sd, -)" "policy-scan.yaml,scan.rego,taches.yml"
  join "$T/cles.avant" "$T/cles.rendu" | awk '$2 != $3 {print "  " $1 " : service " $2 ", rendu " $3}'
  [ "$KO" = 0 ] || arret "rendu non conforme"
  echo "## pose ($(date -u +%H:%M:%S) UTC)"
  here_sauve=$here; here=$P08 R=$P08/resultats P=$O8/pki
  cm_porte < /dev/null 2>&1 | sed 's/^/  /'; c=${PIPESTATUS[0]}
  here=$here_sauve
  attendu "cm_porte, code" "$c" 0
  echo "## après ($(date -u +%H:%M:%S) UTC)"
  kubectl get cm -n porte porte -o json < /dev/null > "$T/apres.json"
  cles "$T/apres.json" > "$T/cles.apres"
  attendu "service = rendu, clé par clé" "$(h < "$T/cles.apres")" "$(h < "$T/cles.rendu")"
  attendu "politique servie : vex_age_max_jours" "$(jq -r '.data["policy-scan.yaml"]' "$T/apres.json" | yq '.sources[0].ruleData.vex_age_max_jours')" 30
  attendu "politique servie : statuts acceptés" "$(jq -r '.data["policy-scan.yaml"]' "$T/apres.json" | yq -o json '.sources[0].ruleData.vex_statuts_acceptes' | jq -c .)" '["not_affected"]'
  ;;
grafana)
  A='{noeud="sc-confiance", source="audit-k8s"} | json | objectRef_namespace="porte" | verb=~"patch|update|create|apply" | objectRef_resource="configmaps"'
  b=$(jq -nc --arg q "sum by (objectRef_resource, objectRef_name, verb) (count_over_time($A [30m]))" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$b" \
    | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | "\(.schema.fields[1].labels | "\(.objectRef_resource)/\(.objectRef_name) \(.verb)") : \(.data.values[1][0])"] | if length == 0 then "aucune écriture" else .[] end' \
    | sed 's/^/  /'
  ;;
esac
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$KO" = 0 ] && echo "bilan : tenue" || echo "bilan : $KO KO"
