#!/usr/bin/env bash
set -euo pipefail
cd ~/.cache/supply-chain-poc/chains-v0300/objets
for n in j7-sample-app sample-app-deb-6391fd437f26696847041be3226bbbf633f55a2f m5b-4-rpm-1 m5b-4-construction-1 f2-prefetch-1; do
  mapfile -t t < <(jq -r '.status.childReferences[].name' "pr-$n.json")
  f=(); for x in "${t[@]}"; do [ -s "tr-$x.json" ]; f+=("tr-$x.json"); done
  for v in 29 30; do
    ../banc/banc$v "pr-$n.json" "${f[@]}" | jq -S . > "../sorties/$n.$v.json"; [ -s "../sorties/$n.$v.json" ]
    for x in "${t[@]}"; do ../banc/banc$v -tr "tr-$x.json" | jq -S . > "../sorties/tr-$x.$v.json"; [ -s "../sorties/tr-$x.$v.json" ]; done
  done
done
