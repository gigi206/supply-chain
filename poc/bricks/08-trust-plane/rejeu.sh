#!/usr/bin/env bash
# Brique 08 : rejeu complet depuis zéro des jalons faits (J1 à J3) : démontage, VM, k3s, stockage, OpenBao, puis
# contrôle des secrets dans les journaux. Téléchargements, CA et certificats restent en cache ; l'état des services
# est lu dans les VM (administrateur Forgejo, initialisation d'OpenBao), pas dans les fichiers de l'hôte.
#
# Usage (racine du dépôt) : mise run confiance:rejeu [-- <libellé>]   (journal : resultats/rejeu-<libellé>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
lib=${1:-j1-j3}
exec > >(sed -u "s#$HOME#~#g" | tee "$here/resultats/rejeu-$lib.log") 2>&1
echo "# rejeu.sh $lib, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
t0=$(date +%s)
etape() { # libellé commande…
  local t l=$1
  shift
  t=$(date +%s)
  "$@"
  echo "## durée $l : $(( $(date +%s) - t )) s"
}
etape démontage mise run confiance:vm -- detruire
etape VM mise run confiance:vm -- creer
etape k3s mise run confiance:k3s
etape J2 mise run confiance:stockage -- pki zot registre containerd forgejo depot
etape J3 mise run confiance:openbao -- image deployer initialiser configurer essais
etape fuites mise run confiance:fuites -- "$lib"
echo "## durée totale : $(( $(date +%s) - t0 )) s"
