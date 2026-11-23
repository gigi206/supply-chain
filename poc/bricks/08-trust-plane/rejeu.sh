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
# le gabarit d'essai la refusent, garde gabarit_essai), sous Cilium aucun compte de service à cluster-admin (preuves.sh helm_cilium,
# option (b) du propriétaire du 01/11/2026), contrôleurs de Tekton et de Chains bornés à builds (preuves.sh controleurs, règle posée
# en J4 par tekton.sh installer), résolveurs bornés à builds (preuves.sh resolveurs), puis contrôle des secrets dans les journaux. Libellé par défaut j1-j6 (nom historique des journaux ; J7 est fini depuis le 01/11/2026) ; avec J7, rejoué sous Cilium le 30/10/2026 en
# cinq morceaux, puis d'un seul tenant avec J8 le 01/11/2026 (libellé j1-j8), puis avec l'option (b) (libellé option-b), puis avec la règle des contrôleurs (libellé controleurs), puis avec leurs droits bornés à builds et les identifiants Zot de l'horodatage dans OpenBao (libellé bornage, 02/11/2026), puis avec les tests négatifs et les mesures de J8 rejoués avant la bascule (libellé cloture, 02/11/2026). Téléchargements, CA et certificats restent en cache ; l'état
# des services est lu dans les VM (administrateur Forgejo, initialisation d'OpenBao), pas dans les fichiers de l'hôte. La voie D
# lit les entrées des bancs du laptop (~/.cache/supply-chain-poc/w/b03, empreintes épinglées) et interroge sum.golang.org.
#
# NON JOUABLE TEL QUEL depuis le 02/11/2026 (inventaire du 03/11/2026, 19:45 UTC, README de la brique 03 ; choix du propriétaire :
# pas de rejeu de zéro pour l'instant) : D6 (brique 03) chargée dès J6 refuse attseule, decision3 et la bascule de J8 tant que J7
# construit sur la fermeture de l'hôte ; detruire efface sc-stockage, donc Loki et Grafana (19b) avec l'historique d'audit, la VSA
# (contrôle 6, brique 10) et les jalons 01, 19 et 19b, qu'aucune étape ci-dessous ne refait.
# Additif du 03/11/2026, 20:23 UTC : intégration complète (choix « b » du propriétaire ; D22 (d) de la 19b : la perte des données
# est acceptée) faite à sec, PAS ENCORE REJOUÉE. Montage (B) : J7 construit sur la fermeture de la plateforme (F2 de la brique 03
# entre les entrées et les tâches de J7 ; construction.sh lit le digest produit par ce passage), F3 n'est plus nécessaire. Après
# J8 : brique 01 (S2 à S4, S6 ; S5 sautée), brique 19 (O2, O3), brique 19b (L2, L3, L5, contrôle de L6, L4 sans muette), puis,
# avec POUSSER_VSA=1 (accord du propriétaire pour ce push), VSA de la brique 10 re-poussée et contrôle 6, enfin fuites.
# Rejoué le 03/11/2026 (libellé complet, 20:31 à 22:42 UTC, cinq parties, trois correctifs, README de la 08) : toutes les étapes
# passent ; plus « NON JOUABLE ».
# Additif du 05/11/2026 : brique 07a ajoutée à sec (G7), PAS ENCORE REJOUÉE. Après la 19b, parce que ses étapes lisent Grafana :
# base (timer, compte poc-vulndb), image d'outils du scanner, clé et rôles, job de scan, CronJob ; avec POUSSER_VSA=1, contrôle 7 et
# témoins signés après le contrôle 6 (C1 de controle7 attend les contrôles 6 et 9 à ok). Rien ne s'y oppose plus tôt dans le
# rejeu : un Job de la porte sans scan échoue sur le conteneur scan, mais les tests de J6 et de J8 ne lisent que les champs de
# VERDICT, dont le champ 3 reste celui de ec ; seul controle7 regarde l'état du Job. J2 pose zot.json avec la rétention (D7 b).
# Additif du 11/11/2026 : S5b de la 06 (rejeu de zéro, jalon de plateforme ; décisions du propriétaire « 1 ok » à « 3 ok » ; carte et
# relevés : README de la 08, section « Rejeu de zéro S5b »), à sec, PAS ENCORE REJOUÉ. Après la VSA et avant fuites, sous RKE2 et
# Cilium seulement, dans l'ordre historique : bloc 08c (durcissement : H1, H4, S1, H5 limites, Deny, rôles ; sortie des builds par
# l'étape rejeu de sortie-builds.sh), « J8 (résolveurs) » déplacée après le bloc (elle attend les 4 lecteurs de Secrets sans
# cilium-operator, que seule la 08c donne ; le chemin k3s ne la rejoue plus), puis bloc 06 (étapes durables de S1 amorce, S4c, S4a,
# S4b, S4d, S4d3 ; S4d3 commence par retirer, sans effet sur un cluster neuf, pour la reprise). La 08d n'a rien installé.
# DEPUIS= : une reprise à une étape antérieure au bloc 08c, la 08c une fois appliquée, casse (kata.sh exemption reposerait le
# fichier Pod Security sans EventRateLimit, politique.sh chains refuserait le volume de S1, les limites de H5 seraient effacées) :
# rejeu complet dans ce cas.
# Additif du 14/11/2026 : S6 de la 06 (décision du propriétaire du 12/11/2026, « (b) intégrer après S6 », après le premier passage
# manuel réel des étapes, le 14/11/2026), à sec, PAS ENCORE REJOUÉ. Après « 06 (S4d3) », dont la porte attend VSA et scan du deb
# refusés : S6a periodique (précédée, dans la même étape, d'une attente jusqu'à 13:00 UTC si l'heure tombe dans la fenêtre des
# passages planifiés, que hors_fenetre de s6a.sh refuse de 09:00 à 12:59 UTC), fraicheur, grafana ; avec POUSSER_VSA=1, S6b
# pousser_vsa et lire_vsa, puis S6a porte. Sans POUSSER_VSA=1, la porte du deb est sautée comme celle de S4d3 : la clé du scanner
# n'entre dans la ConfigMap porte que par cm_porte des contrôles 6 et 7 (déduit du code, non mesuré). Une étape par appel : s6a.sh
# et s6b.sh n'acceptent qu'un argument.
# Additif du 20/11/2026 : M5b de la 05 sous l'option C (décision du propriétaire ; carte 05-rpm-mock/resultats/m5b-carte.md,
# notes de 17:47:22 et 17:50:11 UTC), à sec, PAS ENCORE REJOUÉ, pas avant le 28/11/2026. Avec TAG_05=<tag> seulement, sous RKE2 et
# Cilium : m5b-rejeu.sh entree avant le démontage (hôte seul : TAG, journaux et dossiers du TAG absents, entrées de l'hôte, fichiers
# signés, clé des tâches, fuseau, tkn), puis, après la 06 (sample-app-sources, publier-fermeture et publier-image en viennent) :
# s1.sh amorce et m3_reseau, signature (les deux pipelines des builders signées à nouveau, clé des tâches lue par tkn), images,
# republication sans signature des tâches rpm, artefact de packaging, pipeline de fermeture, fermeture, pipeline de construction,
# construction rpm. Les gardes de M4a, M4b et M4c ne sont pas rejouées (m5b-rejeu.sh). Un journal n'est jamais réécrit : un
# TAG_05 neuf par tentative, reprise par DEPUIS= comprise (entree le refuse sinon). Sans TAG_05, le bloc est sauté.
# Correction du 20/11/2026 (carte de M5b, note de 2026-11-20T17:58:49Z) : les sorties de signature sont sous le TAG, donc une reprise
# à « 05 (images) » sous un TAG_05 neuf repart de « 05 (signature) » ; vm.sh detruire efface $W (l. 152) : entree copie avant
# le démontage les entrées de l'hôte que lisent signature, images et artefact (m5b-rejeu.sh, E05).
# Additif du 21/11/2026 : tranche 1 de la 07b (entrees-scan, posé le 21/11, 07b-t1-pose.log), à sec, PAS ENCORE REJOUÉ.
# entrees-scan.sh pose juste après « 06 (S6a, fraicheur) » : pose exige deux artefacts dans SCANS, que l'unité fraicheur-scan
# ne porte qu'après fraicheur de la 06. Sans elle, une VM recréée (M5b) perdrait entrees-scan (carte de la 07b, note de
# 2026-11-21T16:37:53Z). pose écrit sur sc-stockage (sudo, comme g8_metriques) ; verif est hors du rejeu (« une fois par scan »
# ne se prouve qu'au scan quotidien suivant).
#
# Usage (racine du dépôt) : [POUSSER_VSA=1] [TAG_05=<tag>] mise run confiance:rejeu [-- <libellé>]   (journal : resultats/rejeu-<libellé>.log)
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
. "$here/distro.sh"   # DISTRO=rke2 (brique 08b) : rke2.sh à la place de k3s.sh ; préalable sur l'hôte : rke2.sh telecharger
export DISTRO
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
b05=$here/../05-rpm-mock
# Additif du 2026-11-23T15:06:42Z (incident du rejeu m5b-1) : TAG_05 posé hors RKE2 et Cilium sautait entree en silence, puis le démontage
# effaçait $W et les entrées de M5b. Refus net, avant tout démontage.
if [ -n "${TAG_05:-}" ] && { [ "$DISTRO" != rke2 ] || [ "$RESEAU" != cilium ]; }; then
  echo "KO   TAG_05=$TAG_05 exige DISTRO=rke2 et RESEAU=cilium (DISTRO=$DISTRO, RESEAU=$RESEAU) : rien n'est démonté" >&2; exit 1
fi
if [ -n "${TAG_05:-}" ] && [ "$DISTRO" = rke2 ] && [ "$RESEAU" = cilium ]; then   # M5b de la 05 : contrôle avant tout démontage
  env TAG="$TAG_05" mise exec -- "$b05/m5b-rejeu.sh" entree
fi
# Additif du 2026-11-23 (arrêt du rejeu plateforme-1 dans « 06 (S4c) ») : le bloc 06 lit sous $W des entrées de l'hôte que le rejeu
# ne produit pas (InRelease et Packages.xz de S1, deb de S3) ; vm.sh detruire efface $W. Copie hors de $W, empreintes épinglées,
# avant tout démontage (06-deb-sbuild/rejeu-entrees.sh garder) ; recopie par l'étape « 06 (entrées de l'hôte) ».
if [ "$DISTRO" = rke2 ] && [ "$RESEAU" = cilium ]; then
  "$here/../06-deb-sbuild/rejeu-entrees.sh" garder || { echo "KO   entrées de l'hôte du bloc 06 : rien n'est démonté" >&2; exit 1; }
fi
etape démontage mise run confiance:vm -- detruire
etape VM mise run confiance:vm -- creer
if [ "$DISTRO" = k3s ]; then etape k3s mise run confiance:k3s; else etape RKE2 mise exec -- "$here/../08b-rke2/rke2.sh" installer; fi
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
# Montage (B) du 03/11/2026 : F2 de la brique 03 (prefetch dans la plateforme) entre les entrées de J7 (prefetch.sh compare à la
# fermeture de l'hôte, poussée par entrees) et ses tâches (la pipeline sample-app épingle la fermeture de F2 : règle D6 de la porte,
# chargée dès J6). Étape cilium de F2 abandonnée (D2 révisée). Le cache de F2 survit à detruire : ses digests sont retirés avant.
F2=$HOME/.cache/supply-chain-poc/03/f2
fermeture_f2() {
  rm -f -- "${F2:?}/fermeture-1.digest" "${F2:?}/fermeture-2.digest"
  mise run fermetures:f2 -- image compte reseau taches prefetch provenance
}
etape "J7 (construction, entrées)" mise run confiance:construction -- compte entrees
etape "J7 (fermeture, F2 de la 03)" fermeture_f2
etape "J7 (construction)" mise run confiance:construction -- taches constat_cm construire provenance
etape "J7 (réseau)" mise run confiance:kata -- reseau
# Tests négatifs et mesures de J8, dans l'ordre du premier passage (30/10 au 01/11/2026), avant la bascule qui les refuse
# (garde gabarit_essai) ; ajoutés le 02/11/2026 (décision du propriétaire : rejouer avant la bascule pour clore J8).
# reserve_c retiré le 02/11/2026 (accord du propriétaire) : il lit les dépôts d'essai du test 8 du 01/11, nommés en dur, absents
# d'une installation neuve ; 11 KO garantis qui arrêtaient decision3 et la suite (rejeux cloture et resolveurs).
echo "## reserve_c : sautée (non rejouable : dépôts d'essai du test 8 du 01/11 nommés en dur ; mesure du 01/11 gardée, ADR 0000)"
etape "J8 (tests)" mise run confiance:preuves -- test2 test4 test5 test3 test1 test6 reglec test7 attseule test8 enveloppes decision3
etape "J8 (bascule)" mise run confiance:preuves -- bascule
[ "$RESEAU" != cilium ] || etape "J8 (helm-cilium)" mise run confiance:preuves -- helm_cilium
etape "J8 (contrôleurs)" mise run confiance:preuves -- controleurs
# Résolveurs bornés à builds (02/11/2026) : déplacée après le bloc 08c le 11/11/2026 (S5b), voir plus bas.
# preuves.sh intercepteurs n'est pas rejoué (mesure ponctuelle : retire et remet une liaison).
# Briques 01, 19 et 19b (choix « b » du propriétaire du 03/11/2026), après la bascule : la 01 avant la 19 (groupe synchro de
# fichiers-metriques) ; la 19 installée avant la 19b (répertoires et Prometheus que L2 attend) ; cibles et règles de la 19 après
# Alloy (job alloy de prometheus.yml) ; tout avant fuites, qui contrôle aussi leurs jetons. Les journaux d'étapes des briques sont
# réécrits dans leur resultats/, comme ceux de la 08 (l'historique git garde les précédents).
etape "01 (S2, S4)" mise run synchro:forgejo -- comptes organisations amont miroir archives fork protections refus bout_en_bout
etape "01 (S3)" mise run synchro:executeur -- installer essai planifie fuites
etape "01 (S4, négatifs)" mise run synchro:forgejo -- negatifs
echo "## 01 S5 : sautée (déduit du code, non mesuré : D6 refuserait l'image du fork, sans fermeture propre ; porte en dur sur 3a7ca1b1)"
echo "## 01 reverification, retrait, refspec, niveaux : sautées (mesures ponctuelles du 02/11/2026)"
etape "01 (S6)" mise run synchro:forgejo -- traefik
echo "## 19 telecharger : sautée (archives en cache, sha256 revérifiés par installer) ; reference, O4 et correctifs : sautés (mesures)"
etape "19 (O2)" mise run observabilite -- certificats compte installer
etape "19b (L2)" env JALON=l2 mise run journalisation -- certificats installer controle
etape "19b (L3)" env JALON=l3 mise run journalisation -- certificats_l3 evenements openbao_sortie alloy controle_l3
etape "19b (L5)" env JALON=l5 mise run journalisation -- battement
etape "19 (O2, suite)" mise run observabilite -- cibles lecture_seule
etape "19 (O3)" mise run observabilite -- regles deployer
echo "## 19b L1, avant_grpc, grpc_tls, pertes_grpc : sautées (L2 et L3 posent déjà la configuration finale) ; muette, L7 : sautées"
etape "19b (L6, contrôle)" env JALON=l6 mise run journalisation -- controle_grpc
etape "19b (L4)" env JALON=l4 mise run journalisation -- temoins secrets
# Brique 07a (G7). Sautées, archives en cache revérifiées par g2_image : g0, g2_telecharger, g2_verifier ; sautées, mesures ponctuelles
# ou correctif déjà appliqué : g5_regles, g5_sec, g5_porte, g5_grafana, g6_sec, g7_sec ; sans objet, Zot naît avec la rétention en J2 :
# g7_zot, g7_balayage. g3_openbao réécrit resultats/scanner-cle-publique.pem : une installation neuve a une clé neuve, que cm_porte
# reprend au contrôle 6 ou 7 et que le scan de g4_scan utilise déjà.
plateforme() { mise exec -- "$here/../07a-sbom-grype/plateforme.sh" "$@"; }
etape "07a (G1)" plateforme g1_oras g1_droits g1_base g1_essai g1_grafana
etape "07a (G2)" plateforme g2_image
etape "07a (G3)" plateforme g3_cluster g3_openbao g3_essais g3_cosign g3_grafana
# Additif du 23/11/2026 (07b, intégration au rejeu ; choix du propriétaire « Automatique au rejeu ») : clé Transit vex, politique
# vex-signature et accès userpass du propriétaire dans l'OpenBao recréé ; vex-cle-publique.pem réécrite (à relire et commiter),
# prise par cm_scan dès G4 et par s6a.sh periodique. Compte poc-vex : J2 (stockage.sh, ligne htpasswd du cache de la 07a).
vex07b() { env REJEU="$lib" MDP_FICHIER="$HOME/.cache/supply-chain-poc/07a/secrets/openbao-proprietaire.password" \
  "$here/../07a-sbom-grype/vex-openbao.sh" "$1" | tail -n 3; }
etape "07b (clé VEX)" vex07b cle_vex
etape "07b (accès VEX)" vex07b acces_vex
etape "07a (G4)" plateforme g4_scan g4_verifier g4_grafana
etape "07a (passage périodique)" plateforme g7_periodique g7_grafana
# Additif du 05/11/2026 : G8, à sec, PAS ENCORE REJOUÉ. Les règles sont déployées en O3, avant le scan : ScanEnRetard et BaseGrypeVieillie
# sont actives (absent()) jusqu'à cette étape. g8_grafana et l'incident a7 sont hors du rejeu, mesures ponctuelles.
etape "07a (G8)" plateforme g8_metriques
if [ "${POUSSER_VSA:-}" = 1 ]; then
  # VSA de la brique 10 (bundle versionné, lié au seul digest 3a7ca1b1, que J7 vérifie) re-poussée, puis contrôle 6 de la porte
  etape "10 (VSA)" env JALON=r5 mise run replay -- pousser_vsa
  etape "J8 (contrôle 6)" mise run confiance:preuves -- controle6
  etape "J8 (contrôle 7)" mise run confiance:preuves -- controle7
  etape "07a (G6)" plateforme g6_temoins
else
  echo "## 10 pousser_vsa, J8 controle6, controle7 et 07a g6_temoins : sautés (POUSSER_VSA=1 absent : accord du propriétaire à chaque push de VSA)"
fi
# S5b (11/11/2026, à sec) : blocs 08c et 06, dans l'ordre historique (la 06 a tourné entièrement sous la 08c).
if [ "$DISTRO" = rke2 ] && [ "$RESEAU" = cilium ]; then
  b08c=$here/../08c-durcissement
  b06=$here/../06-deb-sbuild
  # Exclues : verifier, h2_*, h3_*, flux*, *_sec, h5_cilium (dans h4_bloque), h5_tests, h6* (WireGuard retiré), s1_retrait,
  # evenements.sh (compteur et alerte posés par 19b L3 et 19 O3), relevés et essais.
  etape "08c (H1)" mise exec -- "$b08c/durcissement.sh" h1_api
  etape "08c (H4)" mise exec -- "$b08c/durcissement.sh" h4_bloque
  etape "08c (S1)" mise exec -- "$b08c/secrets.sh" s1_source s1_chains s1_copies
  etape "08c (H5, limites)" mise exec -- "$b08c/durcissement.sh" h5_limites
  etape "08c (H5, Deny)" mise exec -- "$b08c/durcissement.sh" h5_deny
  etape "08c (H5, rôles)" mise exec -- "$b08c/durcissement.sh" h5_roles
  etape "08c (sortie des builds)" mise exec -- "$b08c/sortie-builds.sh" rejeu
  # Résolveurs bornés à builds (02/11/2026) : après la bascule et après H4 (tls.secretSync coupé : 4 lecteurs de Secrets)
  etape "J8 (résolveurs)" mise run confiance:preuves -- resolveurs
  # Exclues : S1 sauf amorce, S2, S3 (mesures ; leurs fichiers de l'hôte lus ici sont gardés hors de $W par rejeu-entrees.sh,
  # corrigé le 23/11/2026 : $W est effacé au démontage), s4a comparaison (seule à lire racine.tar et chroot.tar), s4b provenance,
  # essais, provenance, comparaison, S4d2, S5a, diag-exec-kata.sh. s4d prealables est rejouée depuis le 23/11/2026.
  etape "06 (S1, amorce)" mise exec -- "$b06/s1.sh" amorce
  etape "06 (entrées de l'hôte)" "$b06/rejeu-entrees.sh" replacer   # additif du 23/11/2026 (voir garder, avant le démontage)
  etape "06 (S4c)" mise exec -- "$b06/s4c.sh" verrou publier
  etape "06 (S4a)" mise exec -- "$b06/s4a.sh" prealables taches reseau pipeline
  etape "06 (S4b)" mise exec -- "$b06/s4b.sh" prealables taches_deb taches_sources deb sources comparaison
  etape "06 (S4d, prealables)" mise exec -- "$b06/s4d.sh" prealables   # additif du 23/11/2026 : digest-attendu, effacé avec $W
  etape "06 (S4d)" mise exec -- "$b06/s4d.sh" reseau taches pipeline
  if [ "${POUSSER_VSA:-}" = 1 ]; then
    etape "06 (S4d3)" mise exec -- "$b06/s4d3.sh" retirer prealables deployer chemins porte
  else
    etape "06 (S4d3)" mise exec -- "$b06/s4d3.sh" retirer prealables deployer chemins
    echo "## 06 s4d3 porte : sautée (POUSSER_VSA=1 absent : elle attend la VSA de sample-app à ok)"
  fi
  # S6 de la 06 (14/11/2026) : voir l'additif de l'en-tête. Sans intégration, ScanEnRetard resterait active pour le deb (absent()
  # par dépôt, posé en O3) et la porte du deb refuserait le scan après chaque rejeu.
  periodique_s6a() { # attente hors de la fenêtre de hors_fenetre (09:00 à 12:59 UTC), puis periodique : une seule étape, pour
    local h a        # qu'une reprise par DEPUIS= ne saute pas l'attente
    h=$(date -u +%H)
    case $h in
      09|10|11|12) a=$(( $(date -u -d 'today 13:00' +%s) - $(date +%s) ))
        echo "## fenêtre des passages planifiés ($h h UTC) : attente de $a s, jusqu'à 13:00 UTC"
        sleep "$a" ;;
    esac
    mise exec -- "$b06/s6a.sh" periodique
  }
  etape "06 (S6a, periodique)" periodique_s6a
  etape "06 (S6a, fraicheur)" mise exec -- "$b06/s6a.sh" fraicheur
  etape "07b (entrees-scan, pose)" mise exec -- "$here/../07a-sbom-grype/entrees-scan.sh" pose   # additif du 21/11/2026
  etape "06 (S6a, grafana)" mise exec -- "$b06/s6a.sh" grafana
  if [ "${POUSSER_VSA:-}" = 1 ]; then
    etape "06 (S6b, pousser_vsa)" mise exec -- "$b06/s6b.sh" pousser_vsa
    etape "06 (S6b, lire_vsa)" mise exec -- "$b06/s6b.sh" lire_vsa
    etape "06 (S6a, porte)" mise exec -- "$b06/s6a.sh" porte
  else
    echo "## 06 s6b pousser_vsa, lire_vsa et s6a porte : sautées (POUSSER_VSA=1 absent : accord du propriétaire à chaque push de"
    echo "## VSA ; clé du scanner posée dans la ConfigMap porte par les contrôles 6 et 7 seulement)"
  fi
  # M5b de la 05 (20/11/2026, à sec) : voir l'additif de l'en-tête. Un PipelineRun par pipeline ; 333b7322 et 09838980 exigés.
  if [ -n "${TAG_05:-}" ]; then
    etape "05 (S1, amorce et m3_reseau)" env PREFIXE="$TAG_05" mise exec -- "$b05/s1.sh" amorce m3_reseau
    etape "05 (signature)" env TAG="$TAG_05" mise exec -- "$b05/m5b-rejeu.sh" signature
    etape "05 (images)" env TAG="$TAG_05" mise exec -- "$b05/m5b-rejeu.sh" images
    etape "05 (taches)" env TAG="$TAG_05" mise exec -- "$b05/m5b-republier.sh" taches
    etape "05 (artefact)" env TAG="$TAG_05" mise exec -- "$b05/m5b-rejeu.sh" artefact
    etape "05 (pipeline_fermeture)" env TAG="$TAG_05" mise exec -- "$b05/m5b-republier.sh" pipeline_fermeture
    etape "05 (fermeture)" env TAG="$TAG_05" mise exec -- "$b05/m5b-rejeu.sh" fermeture
    etape "05 (pipeline_construction)" env TAG="$TAG_05" mise exec -- "$b05/m5b-republier.sh" pipeline_construction
    etape "05 (construction_rpm)" env TAG="$TAG_05" mise exec -- "$b05/m5b-rejeu.sh" construction_rpm
  else
    echo "## 05 (M5b) : sautée (TAG_05 absent ; un TAG neuf par tentative)"
  fi
else
  echo "## 08c, J8 (résolveurs), 06 et 05 : sautés (DISTRO=$DISTRO, RESEAU=$RESEAU ; RKE2 et Cilium seulement)"
fi
# Additif du 2026-11-23T18:43:04Z : Kyverno corrigé en service (décision du propriétaire « Image + politique », posé le 23/11 après M5b) :
# image corrigée reconstruite et poussée (essais/kyverno-correctif@eec37159), puis politique horodatage-livraison et bascule du
# contrôleur d'admission, en fin de rejeu (après les étapes qui mesurent l'image officielle et après le bloc 05). Journaux suffixés.
etape "08 (Kyverno corrigé, image)" env KA_SUFFIXE="rejeu-$lib" mise exec -- "$here/kyverno-admission.sh" construire
etape "08 (Kyverno corrigé, image poussée)" env KA_SUFFIXE="rejeu-$lib" mise exec -- "$here/kyverno-admission.sh" image
etape "08 (Kyverno corrigé, pose)" mise exec -- "$here/kyverno-permanent.sh" pose "rejeu-$lib"
echo "## 08d : rien à rejouer (relevés seuls, rien installé ; cert-manager lié à l'exposition de services, D7)"
etape fuites mise run confiance:fuites -- "$lib"
[ "$DISTRO" = k3s ] || etape "08b (CIS)" mise exec -- "$here/../08b-rke2/rke2.sh" cis
echo "## durée totale : $(( $(date +%s) - t0 )) s"
