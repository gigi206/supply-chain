#!/usr/bin/env bash
# Brique 08 : rejeu complet depuis zéro des jalons faits (J1 à J6) : démontage, VM, k3s, stockage, OpenBao, Tekton,
# horodatage, politique (test 5 rejoué sous politique entre declencheurs et porte, comme au premier passage ; porte avant
# rattrapage, qui juge avec elle ; droits, qui lit l'audit du test 5 et du rattrapage ; posture), J7 en cours (Kata :
# vérification, installation, essais, exemption Pod Security de la RuntimeClass kata (server k3s redémarré) ; cas d'admission rejoués avec la RuntimeClass kata ; BuildKit : image, essais, mesure après l'exemption ; voie D ; voie A sur sample-app), puis contrôle des
# secrets dans les journaux. Libellé par défaut j1-j6 tant que J7 n'est pas fini ; avec J7, non rejoué au 30/10/2026. Téléchargements, CA et certificats restent en cache ; l'état
# des services est lu dans les VM (administrateur Forgejo, initialisation d'OpenBao), pas dans les fichiers de l'hôte. La voie D
# lit les entrées des bancs du laptop (~/.cache/supply-chain-poc/w/b03, empreintes épinglées) et interroge sum.golang.org.
#
# Usage (racine du dépôt) : mise run confiance:rejeu [-- <libellé>]   (journal : resultats/rejeu-<libellé>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
lib=${1:-j1-j6}
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
etape J3 mise run confiance:openbao -- image deployer initialiser configurer essais redemarrage
etape J4 mise run confiance:tekton -- revue miroir installer signature verifier webhook essais_webhook
etape J5 mise run confiance:tsa -- image pki openbao deployer essais horodater chemins
etape J6 mise run confiance:politique -- image installer parite taches admission chains declencheurs restreint horodatage
etape "test 5 (J6)" env EL_NS=declencheurs JOURNAL=politique JALON=J6 mise run confiance:tekton -- essais_webhook
etape "J6 (suite)" mise run confiance:politique -- porte rattrapage droits posture
etape J7 mise run confiance:kata -- verifier installer essais exemption
etape "J7 (admission)" mise run confiance:politique -- admission
etape "J7 (BuildKit)" mise run confiance:buildkit -- image essais exempte
etape "J7 (voie D)" mise run confiance:voie-d -- image compiler assembler
etape "J7 (voie A, sample-app)" mise run confiance:buildkit -- sample_app
etape fuites mise run confiance:fuites -- "$lib"
echo "## durée totale : $(( $(date +%s) - t0 )) s"
