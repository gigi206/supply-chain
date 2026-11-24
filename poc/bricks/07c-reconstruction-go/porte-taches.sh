#!/usr/bin/env bash
# Brique 07c, étape 4 (b) : pose de la liste revue augmentée (politique/porte/taches.yml) dans la ConfigMap porte/porte, SUR LA
# SEULE CLÉ taches.yml (les autres clés, posées par d'autres briques, ne sont pas touchées). Accord du propriétaire du 24/11/2026.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
J=$1; L=poc/bricks/08-trust-plane/politique/porte/taches.yml
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
cles() { kubectl get cm -n porte porte -o json | jq -r '.data | to_entries[] | select(.key != "taches.yml") | "\(.key) \(.value | @base64)"' | sha256sum | cut -c1-16; }
{
echo "# liste revue dans la porte, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
attendu "taches.yml du cluster = version commitée précédente" "$(kubectl get cm -n porte porte -o jsonpath='{.data.taches\.yml}' | sha256sum | cut -c1-16)" cb2d78ff9a5321e2   # taches.yml au commit fc3a31df, avant l'ajout
avant=$(cles); echo "autres clés (empreinte) : $avant"
kubectl patch cm -n porte porte --type merge -p "$(jq -n --rawfile t "$L" '{data: {"taches.yml": $t}}')" > /dev/null; echo "patch : code $?"
attendu "taches.yml du cluster = dépôt" "$(kubectl get cm -n porte porte -o jsonpath='{.data.taches\.yml}' | sha256sum | cut -c1-16)" "$(sha256sum < "$L" | cut -c1-16)"
attendu "nouvelle référence présente" "$(kubectl get cm -n porte porte -o jsonpath='{.data.taches\.yml}' | grep -c 'ref: sha256:4dcbc4b7468137d8')" 1
attendu "ancienne référence gardée" "$(kubectl get cm -n porte porte -o jsonpath='{.data.taches\.yml}' | grep -c 'ref: sha256:66a9f2980a45d289')" 1
attendu "autres clés inchangées" "$(cles)" "$avant"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
cat "$J"
