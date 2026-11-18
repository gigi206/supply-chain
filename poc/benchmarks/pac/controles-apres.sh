#!/usr/bin/env bash
# Banc PaC : contrôles après le banc, sans requête au cluster du PoC (relecture du conseiller) : forme des objets soumis au dry-run,
# démontage (processus, ports, clusters kind), droits des fichiers de secrets du banc (stat seulement, jamais lus).
# Usage (racine du dépôt) : bash poc/benchmarks/pac/controles-apres.sh > poc/benchmarks/pac/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
W=$HOME/.cache/supply-chain-poc/pac/banc
echo "# controles-apres.sh, début $(date -u +%FT%TZ)"
echo "## objets soumis au dry-run (fichiers locaux)"
jq -r .apiVersion "$W/admission/reel.json" | sed 's/^/reel.json : apiVersion /'
for v in temoin env hostile enligne; do jq -c --arg v "$v" '{v: $v, apiVersion, kind, env: .spec.taskRunTemplate.podTemplate.env, pipelineRef: (.spec.pipelineRef.resolver // null), pipelineSpec: (.spec.pipelineSpec != null)}' "$W/admission/v-$v.json"; done
echo "## démontage"
p=$(cat "$W/forgejo/forgejo.pid"); if ps -p "$p" >/dev/null 2>&1; then echo "KO   Forgejo du banc (pid $p) encore vivant"; else echo "OK   Forgejo du banc (pid $p) absent"; fi
echo "ports 3010 et 8182 à l'écoute : $(ss -ltn | awk '{print $4}' | grep -cE ':(3010|8182)$' || true)"
echo "clusters kind : [$(kind get clusters 2>/dev/null | tr '\n' ' ')]"
echo "conteneurs banc-pac : $(docker ps -a --format '{{.Names}}' | grep -c banc-pac || true)"
echo "## fichiers de secrets du banc laissés dans le cache (mode seulement, jamais lus)"
for f in admin.token webhook.secret entete-api hook.json; do echo "$f : $(stat -c %a "$W/forgejo/$f")"; done
echo "# fin $(date -u +%FT%TZ)"
