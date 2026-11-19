#!/usr/bin/env bash
# Essai à sec de helmfile : localisation de l'unique ligne d'écart (une ligne vide ajoutée par helmfile) relevée par essai.sh le
# 19/11/2026. Lit le dossier de travail d'essai.sh, n'exécute ni helm ni helmfile. Valeurs masquées, certificats remplacés.
# Usage (racine du dépôt) : bash poc/benchmarks/deploiement/essai-helmfile/ligne-vide.sh <dossier de travail d'essai.sh> > <journal neuf> 2>&1
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C
W=$1
echo "# ligne-vide.sh, début $(date -u +%FT%TZ) ; dossier $W"
for n in cilium rke2-coredns rke2-metrics-server; do
  echo "## $n : en-têtes de diff (ref masquée contre helmfile masqué)"
  diff "$W/ref/$n.m1" "$W/hf/$n.m" | grep -v '^[<>-]' || true
  l=$( (diff "$W/ref/$n.m1" "$W/hf/$n.m" || true) | grep -v '^[<>-]' | head -1 | sed -E 's/^[0-9]+a([0-9]+)$/\1/')
  echo "ligne ajoutée n° $l sur $(wc -l < "$W/hf/$n.m") ; contexte dans la sortie de helmfile (clés seules, valeurs masquées) :"
  sed -n "$((l-2)),$((l+2))p" "$W/hf/$n.m" | nl -ba -v $((l-2)) -w5 -s ' | ' | sed -E 's/(: ).*/\1<valeur masquée>/' | cut -c1-120
  echo "octets : ref $(wc -c < "$W/ref/$n.m1"), helmfile $(wc -c < "$W/hf/$n.m") ; helmfile sans sa ligne $l égal à ref : $(sed "${l}d" "$W/hf/$n.m" | cmp -s - "$W/ref/$n.m1" && echo oui || echo non)"
done
echo "# fin $(date -u +%FT%TZ)"
