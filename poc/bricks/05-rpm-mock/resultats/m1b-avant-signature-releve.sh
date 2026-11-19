#!/usr/bin/env bash
# shellcheck disable=SC1091  # commun.sh chargé par un chemin calculé
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : relevé en lecture seule avant la préparation de la signature des deux tâches neuves (19/11/2026), sans
# pari : état déployé de la porte contre le dépôt (leçon de S4d2a de la 06), place de sc-stockage (/ et /var/lib/zot, écritures dans
# Zot définitives), référence de publier-fermeture lue dans la liste revue (comme ref_revue de m4b.sh), entrées rpm de la liste.
# Ni écriture, ni secret lu : seules des empreintes et des tailles sont relevées.
# Corrigé le 19/11/2026 après le premier passage (m1b-avant-signature-releve-1.log, 16:50:19 UTC) : les références de la liste
# revue sont sous la clé du dépôt (« - ref: sha256:… »), pas en « - ref: oci://…@ » ; motif refait par la fonction refs.
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-avant-signature-releve.sh < /dev/null > poc/bricks/05-rpm-mock/resultats/m1b-avant-signature-releve.log 2>&1
set -euo pipefail
export LC_ALL=C
G=$(git rev-parse --show-toplevel)
here=$G/poc/bricks/08-trust-plane   # commun.sh attend le répertoire de l appelant
. "$here/commun.sh"   # sur, IP
PORTE=$here/politique/porte
echo "# début $(date -u +%FT%TZ) ; HEAD $(git rev-parse --short=12 HEAD)"
echo "## ConfigMap porte (porte) contre le dépôt"
for k in policy.yaml policy-trusted-task.yaml porte.rego taches.yml; do
  j=${k//./\\.}
  d=$(kubectl get configmap -n porte porte -o jsonpath="{.data.$j}" < /dev/null | sha256sum | cut -c1-64)
  f=$(sha256sum < "$PORTE/$k" | cut -c1-64)
  echo "$k : déployé ${d:0:16}… ; dépôt ${f:0:16}… ; $([ "$d" = "$f" ] && echo égal || echo DIFFÉRENT)"
done
echo "## place de sc-stockage"
sur sc-stockage 'df -B1 --output=used,avail / | tail -n 1' < /dev/null | awk '{print "/ : utilisés " $1 " octets ; libres " $2 " octets"}'
sur sc-stockage 'df -B1 --output=target,used,avail /var/lib/zot | tail -n 1' < /dev/null | awk '{print "/var/lib/zot (point de montage " $1 ") : utilisés " $2 " octets ; libres " $3 " octets"}'
echo "## liste revue (dépôt)"
refs() { # nom : digests listés sous l'entrée « oci://…/tekton/tasks/<nom>: » de la liste revue (format « - ref: sha256:… »)
  awk -v k="  oci://sc-stockage.poc.test:5000/tekton/tasks/$1:" '$0 == k {e = 1; next} /^  [^ #-]/ {e = 0} e && $1 == "-" && $2 == "ref:" {print $3}' "$PORTE/taches.yml"
}
echo "publier-fermeture : $(refs publier-fermeture | paste -sd ' ')"
for t in prefetch-rpm construire-rpm prefetch-racine-rpm construire-racine-rpm; do
  echo "$t : $(grep -c "^  oci://sc-stockage.poc.test:5000/tekton/tasks/$t:" "$PORTE/taches.yml" || true) entrée(s), références : $(refs "$t" | cut -c1-19 | paste -sd ' ')"
done
echo "# fin $(date -u +%FT%TZ)"
