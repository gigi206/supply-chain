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
#
# Usage (racine du dépôt) : [POUSSER_VSA=1] mise run confiance:rejeu [-- <libellé>]   (journal : resultats/rejeu-<libellé>.log)
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
  # Exclues : S1 sauf amorce, S2, S3 (mesures ; leurs fichiers de l'hôte, $W/s1-06 à s3-06, sont gardés et relus), s4a
  # comparaison, s4b provenance, s4d prealables (digest-attendu gardé dans $W), essais, provenance, comparaison, S4d2, S5a,
  # diag-exec-kata.sh.
  etape "06 (S1, amorce)" mise exec -- "$b06/s1.sh" amorce
  etape "06 (S4c)" mise exec -- "$b06/s4c.sh" verrou publier
  etape "06 (S4a)" mise exec -- "$b06/s4a.sh" prealables taches reseau pipeline
  etape "06 (S4b)" mise exec -- "$b06/s4b.sh" prealables taches_deb taches_sources deb sources comparaison
  etape "06 (S4d)" mise exec -- "$b06/s4d.sh" reseau taches pipeline
  if [ "${POUSSER_VSA:-}" = 1 ]; then
    etape "06 (S4d3)" mise exec -- "$b06/s4d3.sh" retirer prealables deployer chemins porte
  else
    etape "06 (S4d3)" mise exec -- "$b06/s4d3.sh" retirer prealables deployer chemins
    echo "## 06 s4d3 porte : sautée (POUSSER_VSA=1 absent : elle attend la VSA de sample-app à ok)"
  fi
else
  echo "## 08c, J8 (résolveurs) et 06 : sautés (DISTRO=$DISTRO, RESEAU=$RESEAU ; RKE2 et Cilium seulement)"
fi
echo "## 08d : rien à rejouer (relevés seuls, rien installé ; cert-manager lié à l'exposition de services, D7)"
etape fuites mise run confiance:fuites -- "$lib"
[ "$DISTRO" = k3s ] || etape "08b (CIS)" mise exec -- "$here/../08b-rke2/rke2.sh" cis
echo "## durée totale : $(( $(date +%s) - t0 )) s"
