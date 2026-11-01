#!/usr/bin/env bash
# Brique 08 : rejeu complet depuis zéro des jalons faits (J1 à J6) : démontage, VM, k3s, stockage, OpenBao, Tekton,
# horodatage, politique (test 5 rejoué sous politique entre declencheurs et porte, comme au premier passage ; porte avant
# rattrapage, qui juge avec elle ; droits, qui lit l'audit du test 5 et du rattrapage ; posture), J7 en cours (Kata :
# vérification, installation, essais, exemption Pod Security de la RuntimeClass kata (server k3s redémarré) ; cas d'admission rejoués avec la RuntimeClass kata ; BuildKit : image, essais, mesure après l'exemption ; voie D ; voie A sur sample-app ; voie A
# sans réseau (NetworkPolicy construction-sans-sortie, image de build en layout OCI) ; construction de sample-app dans un
# PipelineRun : compte Zot poc-images, entrées, tâches signées, constat sur les ConfigMaps sous Kata, construction sans sortie
# réseau et ses témoins, provenance ; réseau des pods Kata :
# fenêtre de démarrage, trace des refus (Hubble sous Cilium, NFLOG sous kube-router), usurpation d'adresse), bascule du gabarit
# en service vers la pipeline sample-app (J8, preuves.sh bascule : en dernier, les étapes de J6 et les tests de J8 qui supposent
# le gabarit d'essai la refusent, garde gabarit_essai), puis contrôle des secrets dans les journaux. Libellé par défaut j1-j6 (nom historique des journaux ; J7 est fini depuis le 01/11/2026) ; avec J7, rejoué sous Cilium le 30/10/2026 en
# cinq morceaux, puis d'un seul tenant avec J8 le 01/11/2026 (libellé j1-j8). Téléchargements, CA et certificats restent en cache ; l'état
# des services est lu dans les VM (administrateur Forgejo, initialisation d'OpenBao), pas dans les fichiers de l'hôte. La voie D
# lit les entrées des bancs du laptop (~/.cache/supply-chain-poc/w/b03, empreintes épinglées) et interroge sum.golang.org.
#
# Usage (racine du dépôt) : mise run confiance:rejeu [-- <libellé>]   (journal : resultats/rejeu-<libellé>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
lib=${1:-j1-j6}
# RESEAU=cilium, par défaut (J7, option 1b ; décision du propriétaire du 30/10/2026 de garder Cilium) : k3s.sh installe Cilium,
# contrôlé par cilium.sh verifier juste après J1 ; préalable sur l'hôte : mise run confiance:cilium -- telecharger. RESEAU=flannel :
# flannel et kube-router de k3s (retour arrière ; chemin non rejoué depuis les adaptations de J7). JUSQUA=<étape> arrête
# après cette étape (point d'arrêt) ; DEPUIS=<étape> reprend à cette étape, les précédentes étant sautées.
RESEAU=${RESEAU:-cilium}
export RESEAU   # même réseau pour k3s.sh, lancé par mise
DEPUIS=${DEPUIS:-}
JUSQUA=${JUSQUA:-}
actif=1
[ -z "$DEPUIS" ] || actif=0
exec > >(sed -u "s#$HOME#~#g" | tee "$here/resultats/rejeu-$lib.log") 2>&1
echo "# rejeu.sh $lib, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
t0=$(date +%s)
etape() { # libellé commande…
  local t l=$1
  shift
  [ "$l" != "$DEPUIS" ] || actif=1
  [ "$actif" = 1 ] || { echo "## $l : sautée (reprise à $DEPUIS)"; return 0; }
  t=$(date +%s)
  "$@"
  echo "## durée $l : $(( $(date +%s) - t )) s"
  [ "$l" != "$JUSQUA" ] || { echo "## arrêt après $l (JUSQUA), $(( $(date +%s) - t0 )) s"; exit 0; }
}
echo "réseau : $RESEAU${DEPUIS:+ ; reprise à $DEPUIS}${JUSQUA:+ ; arrêt après $JUSQUA}"
etape démontage mise run confiance:vm -- detruire
etape VM mise run confiance:vm -- creer
etape k3s mise run confiance:k3s
[ "$RESEAU" != cilium ] || etape Cilium mise run confiance:cilium -- verifier
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
etape "J7 (sans réseau)" mise run confiance:buildkit -- sans_reseau
etape "J7 (construction)" mise run confiance:construction -- compte entrees taches constat_cm construire provenance
etape "J7 (réseau)" mise run confiance:kata -- reseau
etape "J8 (bascule)" mise run confiance:preuves -- bascule
etape fuites mise run confiance:fuites -- "$lib"
echo "## durée totale : $(( $(date +%s) - t0 )) s"
