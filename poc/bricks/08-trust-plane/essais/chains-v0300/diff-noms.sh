#!/usr/bin/env bash
# P2 à P4 : toutes les sorties égales hors noms des dépendances et des byproducts ? Usage : bash <ce fichier>
set -euo pipefail
cd ~/.cache/supply-chain-poc/chains-v0300/sorties
q='del(.predicate.runDetails.byproducts[]?.name, .predicate.buildDefinition.resolvedDependencies[]?.name)'
for f in *.29.json; do n=${f%.29.json}; if cmp -s <(jq -S "$q" "$f") <(jq -S "$q" "$n.30.json"); then echo "égal hors noms : $n"; else echo "DIFFÉRENT : $n"; fi; done
