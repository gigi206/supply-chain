#!/usr/bin/env bash
# Brique 05, jalon M2 (verrou de mock, signatures des rpm, fermeture dans Zot) : relevé préalable seulement. Préparé à sec le
# 12/11/2026 à partir de 14:37:18 UTC, NON LANCÉ. Les étapes de M2 dans le cluster dépendent des mesures de S1 (isolation,
# stockage de podman, mock en root) et de ce relevé : elles seront écrites ensuite, avec leurs prédictions. Protocole et
# embranchements : resultats/m2-predictions.md.
#   releve      hôte seul, ni cluster ni Zot : sources de mock au tag mock-6.9-1 (codeload de GitHub, archive non signée, sha256
#               journalisé ; lues, jamais exécutées) ; lignes archivées au journal : options --calculate-build-dependencies et
#               --hermetic-build (mock.py et page de manuel), arguments de mock-hermetic-repo, contenu de etc/mock/hermetic-build.cfg,
#               clés écrites dans le verrou (plugin buildroot_lock), traitement de bootstrap_image_ready, documentation du mode
#               hermétique (titres et lignes qui citent ces options) ; puis sources effacées
#   releve2     hôte seul, sans réseau (ajouté à sec le 12/11/2026 à partir de 14:52:04 UTC, NON LANCÉ) : relit l'archive du tag
#               gardée par releve, après contrôle de son sha256 ; archive au journal des plages entières de lignes, pour les points
#               que releve a laissés ouverts : options recopiées dans le verrou et champs par paquet (buildroot_lock.py, schéma
#               1.1.0), ce qu'exige une image de bootstrap « prête » (buildroot.py, podman.py), ce qu'impose le mode hermétique
#               (config.py 805 à 875), téléchargement et contrôles de mock-hermetic-repo ; puis sources effacées.
#               Prédictions : resultats/m2-predictions.md, section releve2.
#   releve3     hôte seul, sans réseau (ajouté à sec le 12/11/2026 à partir de 15:11:15 UTC, NON LANCÉ) : même archive, sha256
#               contrôlé ; archive au journal ce que la voie 2 (dossier dir: du bootstrap préparé par nous) doit savoir : podman.py
#               entier (calcul de image_digest, chargement d'une image dir:), usages de bootstrap_image_assert_digest et de dir:,
#               toutes les coupures split(':') du code Python, usages de hermetic_build ; puis sources effacées.
#               Prédictions : resultats/m2-predictions.md, section releve3.
#               Corrigé à sec le 12/11/2026 à partir de 15:14:13 UTC, NON LANCÉ, avant tout accord : options cherchées aussi sans
#               leur préfixe bootstrap_ (mock.py:811 le retire), et 6 lignes de contexte après image_assert_digest.
#   releve4     hôte seul, réseau (ajouté à sec le 12/11/2026 à partir de 16:17:36 UTC, NON LANCÉ) : options des gestes 3 et 4 de
#               la voie 2, lues dans l'amont aux tags des versions de Rocky 9.8 (raw.githubusercontent.com, fichiers non signés,
#               sha256 journalisé, HTTP 200 exigé) : --compatibility de createrepo_c 0.20.1 (cmd_parser.c, et ce qu'elle change
#               dans createrepo_c.c), --preserve-digests de skopeo copy 1.22.2 (copy.go). Une option témoin, sûrement présente,
#               doit être trouvée dans le même fichier : sinon le fichier lu n'est pas le bon (KO). Option absente : résultat
#               ABSENTE, code 0. Les correctifs des paquets de Rocky ne sont pas lus. Prédictions : resultats/m2-predictions.md.
#               Corrigé à sec le 12/11/2026 à partir de 16:20:56 UTC, après le premier passage (16:19:59 UTC, KO attendu du témoin :
#               copy.go ne déclare pas les options de copie, il appelle sharedCopyFlags()), NON RELANCÉ : copy.go doit appeler
#               sharedCopyFlags(), et les options sont lues dans cmd/skopeo/utils.go, qui doit définir func sharedCopyFlags( ;
#               usages de compatibility archivés avec 3 lignes avant et 5 après.
#               Corrigé à sec le 12/11/2026 à partir de 16:22:59 UTC, sur relecture du conseiller, NON RELANCÉ : option et témoin
#               cherchés dans le corps de sharedCopyFlags seul (de func sharedCopyFlags( au premier « } » en début de ligne),
#               archivé au journal, et non plus dans tout utils.go.
#   releve5     hôte seul, sans réseau (ajouté à sec le 12/11/2026 à partir de 16:42:30 UTC, après « continue », sur relecture du
#               conseiller, NON LANCÉ) :
#               même archive que releve2 et releve3, sha256 contrôlé ; archive au journal ce que produit le verrou, pour V1 à V3
#               de m2-predictions.md : installed_packages.py entier (requête des champs, dont sigmd5, et calcul des URL),
#               test_buildroot_lock.py entier (verrous d'exemple), Plugin-BuildrootLock.md entier, définitions de sigmd5,
#               url et signature dans le schéma 1.1.0, toutes les mentions de gpg-pubkey, SIGMD5 et sigmd5 dans le code Python,
#               les tests et la documentation ; puis sources effacées.
#               Prédictions : resultats/m2-predictions.md, section releve5.
#               Lancé le 12/11/2026 à 16:47:23 UTC (« Oui, lance releve5 »), code 0 : W1 à W4 tenues (m2-releve5.log).
#   releve6     hôte seul, sans réseau (ajouté à sec le 12/11/2026 à partir de 17:20:08 UTC, après « continue », sur relecture du
#               conseiller, NON LANCÉ) :
#               même archive, sha256 contrôlé ; archive au journal ce qui décide de quels dépôts dnf repoquery tire les URL du
#               verrou (V1 de m2-predictions.md) : package_manager.py entier (appel normal de dnf, écriture de dnf.conf), options
#               package_manager et releasever de config.py, doOutChroot de buildroot.py (où tourne la commande du verrou),
#               rocky-9.tpl entier ; puis rejoue sur l'hôte, en Python et sans rien exécuter du modèle, le remplacement des
#               mirrorlist de s1.sh (lignes de s1.sh exigées telles quelles, sinon KO) sur le dnf.conf du modèle et liste chaque
#               dépôt (enabled, baseurl, mirrorlist, metalink) et la section [main], ligne à ligne si configparser échoue ;
#               puis sources effacées.
#               Prédictions : resultats/m2-predictions.md, section releve6.
#               Lancé le 12/11/2026 à 17:26:47 UTC (« Oui » à « Je lance releve6 ? »), code 0 : X1 à X6 tenues ; seul extras
#               reste actif hors de vault 9.7, par mirrorlist (m2-releve6.log).
#   releve7     hôte seul, réseau (ajouté à sec le 12/11/2026 à partir de 17:46:28 UTC, après « continue », sur relecture du
#               conseiller, NON LANCÉ) : dépôt extras, resté actif par mirrorlist hors de vault 9.7 (releve6), pour la décision
#               du propriétaire après S5b ; s1.sh lu, jamais modifié (VAULT97, CLE_ROCKY et FP_ROCKY, une ligne chacune, sinon KO).
#               Clé de Rocky téléchargée, empreinte égale à FP_ROCKY exigée, trousseau temporaire ; chroot_setup_cmd relu dans
#               le rocky-9.tpl de l'archive gardée (sha256 contrôlé) ; ce que sert le mirrorlist d'extras-9 : code HTTP, nombre
#               d'URL, segments « /<version>/<dépôt>/ » des chemins (ni hôtes ni commentaires, qui situent le client) ; dossiers
#               de vault/rocky/9.7 (liste HTML non signée) ; pour BaseOS, AppStream, CRB et extras de vault 9.7, et pour
#               pub/rocky/9/extras (baseurl commentée du modèle) : repomd.xml signé par FP_ROCKY (gpgv, VALIDSIG ; témoin
#               altéré refusé), primary égal à la somme de repomd.xml, paquets mis à plat ; extras absent (HTTP 404) : ABSENT,
#               code 0 ; mirrorlist illisible : KO, la suite tourne, code 1 ; puis paquets d'extras listés et croisés avec les
#               noms de chroot_setup_cmd (par nom et par provides) et avec les noms de BaseOS, AppStream et CRB 9.7. Un
#               croisement vide n'exclut pas une dépendance que seul extras satisferait. Fichiers effacés à la fin, sauf
#               après un KO qui arrête l'étape : ils restent alors sous ~/.cache jusqu'au passage suivant. Primary en .gz,
#               .xz ou .bz2 (Rocky 9.8 : .gz, s1-hote.log ; vault 9.7 non lu), somme sha256 exigée.
#               Prédictions : resultats/m2-predictions.md, section releve7. Banc hors réseau : resultats/m2-releve7-essai-local.sh.
#               Lancé le 12/11/2026 à 17:54:37 UTC (« Oui » à « Je lance releve7 ? »), code 0 : Y1 à Y7 tenues ; extras existe
#               dans vault 9.7, signé par la clé de Rocky, 58 paquets ; aucun croisement par nom (m2-releve7.log).
#   releve8     hôte seul, réseau, lecture d'index seulement (ajouté à sec le 16/11/2026, après « Continue », sur
#               relecture du conseiller, NON LANCÉ) : étape 7 de la séquence d'après S5b (spec du rpm), préalables
#               de Q1 et Q2. s1.sh lu, jamais modifié (VAULT97, CLE_ROCKY, FP_ROCKY), et la ligne golang du _buildenv de
#               poc/benchmarks/obs/resultats/build-1/rocky_9 (une ligne chacune, sinon KO). Clé de Rocky, BaseOS, AppStream et CRB
#               de vault 9.7 par lire_r7 et depot_r7, non modifiées (repomd.xml signé par FP_ROCKY, primary égal à sa somme ;
#               témoin altéré refusé), dans leur dossier de travail $T/releve7, vidé au début. Dans les primary : paquets dont le
#               sourcerpm est golang-* et fournisseurs de « golang », avec EVR, tag License: et sourcerpm ; fournisseurs classés
#               par une réécriture en Python de rpmvercmp, sans relecture de la source de rpm (neuf témoins choisis par nous, exigés
#               dans les deux sens ; toutes les constructions sont listées) ; présence et rang de la
#               construction des builds OBS. Puis, pour chaque dépôt qui porte la source golang, l'entrée filelists du même
#               repomd.xml (une seule, sha256, emplacement contrôlé), somme égale ; chaque paquet retenu doit y être ; fichiers sous
#               /usr/share/licenses et /usr/share/doc, et autres fichiers au nom de licence, en majuscules (LICENSE, LICENCE, COPYING, PATENTS, NOTICE, suffixe
#               éventuel après « . », « _ » ou « - »).
#               Aucun rpm téléchargé, aucune normalisation SPDX. Fichiers effacés à la fin, sauf après un KO.
#               Prédictions : resultats/m2-predictions.md, section releve8. Banc hors réseau : resultats/m2-releve8-essai-local.sh.
#               Lancé le 16/11/2026 à 17:59:30 UTC (« Oui » à « Je lance m2.sh releve8 ? »), code 0 : G1 à G7 et G9 tenues, G8
#               non tenue pour le chemin (LICENSE de Go sous /usr/share/doc/golang/) ; golang 1.25.9-1.el9_7 le plus haut (m2-releve8.log).
#   releve9     hôte seul, réseau (ajouté à sec le 16/11/2026, pendant l'attente de M5 de la 06, sur relecture du conseiller,
#               NON LANCÉ) : préalable de Q1 (notice de Go). Partie hors réseau : archive du tag gardée par releve (sha256
#               contrôlé), version de mock-core-configs égale à l'épingle de s1.sh ; nodocs, tsflags et excludedocs cherchés sans
#               distinction de casse dans toute l'archive ; plages archivées (ancre exigée, sinon KO) : choix de --installroot et
#               du chroot d'exécution de dnf (package_manager.py), écriture du dnf.conf du buildroot, uses_bootstrap_image et
#               .rpmmacros d'installation (buildroot.py), options communes de dnf (package_manager.py, config.py) ;
#               _common_opts cherché dans mock-core-configs et dans s1.sh ; tsflags=nodocs de s1.sh situé dans dnf_conf (étape
#               racine).
#               Partie réseau : épingles et golang des builds OBS lus comme releve8 ; clé de Rocky et AppStream de vault 9.7 par
#               lire_r7 et depot_r7, non modifiées (témoin altéré refusé) ; entrée golang 0:<EVR OBS>.x86_64 du primary signé
#               (une seule, sha256, emplacement relatif sans « .. » ni base, taille bornée à 64 Mio) ; filelists par fichiers_r8 ;
#               rpm téléchargé entier, taille et sha256 du primary exigés ; jamais installé ni exécuté. Signature OpenPGP de
#               l'en-tête (tag 268) vérifiée par gpgv avec le trousseau de la clé de Rocky : VALIDSIG par FP_ROCKY exigé et en-tête
#               altéré refusé, sinon KO ; absente : « non vérifiée », code 0. En-tête lu en Python
#               (structure et numéros de tags écrits de mémoire, éprouvés par : nom, EVR et License: égaux au primary, fichiers
#               égaux au filelists, SHA256 de l'en-tête et empreinte de la charge quand ils sont présents) : drapeaux, mode,
#               taille et empreinte des fichiers de doc et de licence ; bits 2 (doc) et 128 (license) éprouvés hors réseau sur
#               des rpm réels (resultats/m2-releve9-temoins.sh). LICENSE et PATENTS comparés par sha256 à ceux de Go 1.24.7
#               (mise.toml). Charge en xz :
#               décompressée en mémoire, LICENSE et PATENTS extraits, sha256 égal à l'en-tête exigé, texte archivé ; autre
#               compresseur ou cpio inattendu : NON LUE, code 0. Fichiers effacés à la fin, sauf après un KO.
#               Prédictions : resultats/m2-predictions.md, section releve9. Banc hors réseau : resultats/m2-releve9-essai-local.sh.
# Cœur de la voie 2 (écrit à sec le 12/11/2026 à partir de 16:34:20 UTC, après « continue », sur relecture du conseiller), NON
# BRANCHÉ : aucune étape ne l'appelle, rien n'est lançable. Il ne dépend ni de l'isolation, ni du stockage de podman, ni de mock
# en root, que le haut de ce fichier attend de S1 ; le pod, l'image, le label et la clé livrée attendent S1, verrou et le
# propriétaire (embranchements 2 et 3). Deux parties :
#   voie2_preparer (hôte) : verrou de mock (schéma 1.1.0) mis à plat en liste.tsv (name, version, release, arch, sigmd5, url),
#               KO sur tout écart : version du verrou, pull_digest différent de BOOT_DIGEST (lu dans s1.sh), bootstrap_image
#               différent de la référence de S1, champ manquant, sigmd5 hors de 32 caractères hexadécimaux, URL hors des
#               baseurl fixes de vault 9.7 (VAULT97 lu dans s1.sh), URL avec un caractère hors de [A-Za-z0-9:/._+-] ou un
#               segment « . » ou « .. », nom de fichier hors de [A-Za-z0-9._+-], doublon ;
#               puis voie2.sh, le cœur avec la référence et le dossier du bootstrap substitués
#   VOIE2 (pod, sh) : les quatre gestes, KO sur tout écart : outils présents ; chaque URL téléchargée (HTTP 200 exigé, « + »
#               encodé comme mock-hermetic-repo.py:58) ; autant de fichiers que de paquets ; rpm -K dans une rpmdb vide où seule
#               la clé de Rocky livrée est importée, « digests signatures OK » exigé pour chaque fichier (même motif que l'étape
#               racine de s1.sh, qui le compte sans s'arrêter) ; nom, version, release,
#               arch et SIGMD5 de chaque en-tête égaux au verrou ; createrepo_c --compatibility (appel de
#               mock-hermetic-repo.py:199) ; skopeo copy --preserve-digests vers dir:<dépôt>/<référence coupée au premier
#               « : »>@<pull_digest> (config.py:846, Q4 de m2-predictions.md), sha256 du manifeste copié égal au pull_digest.
#               Banc hors réseau : resultats/m2-voie2-essai-local.sh. La requête de mock pour sigmd5 (installed_packages.py)
#               n'est pas lue : un format différent donnerait un KO, pas un faux OK.
#               Note du 12/11/2026, à partir de 16:47:47 UTC : installed_packages.py est lu depuis par releve5 (rpm -qa
#               --qf "%{sigmd5}", gpg-pubkey écartées, URL par dnf repoquery --location) ; la phrase ci-dessus n'est pas réécrite.
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/05-rpm-mock/m2.sh releve   (journal : resultats/m2-releve.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve2  (journal : resultats/m2-releve2.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve3  (journal : resultats/m2-releve3.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve4  (journal : resultats/m2-releve4.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve5  (journal : resultats/m2-releve5.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve6  (journal : resultats/m2-releve6.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve7  (journal : resultats/m2-releve7.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve8  (journal : resultats/m2-releve8.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve9  (journal : resultats/m2-releve9.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
MOCK_TAG=mock-6.9-1
ARCHIVE_SHA=3c034916a721bb06b923399c856d5111fbf3d791804934dd6d909e3d292e4d88   # relevé le 12/11/2026 à 14:41:49 UTC (m2-releve.log)
CREATEREPO_TAG=0.20.1   # createrepo_c-0.20.1-4.el9 de pub/rocky/9.8/AppStream (sante-voie2.log)
SKOPEO_TAG=v1.22.2      # skopeo-1.22.2-9.el9_8 épinglé par s1.sh (s1-hote.log)
T=$HOME/.cache/supply-chain-poc/05/m2
mkdir -p "$T"

lignes() { # titre motif-ERE fichier-ou-dossier… : lignes numérotées (chemins relatifs aux sources), coupées à 170 caractères
  local t=$1 m=$2; shift 2
  echo "### $t"
  ( cd "$T/mock-src" && grep -rn -I -E -- "$m" "$@" 2>/dev/null ) | cut -c1-170 | sed 's/^/  /' || true
}

etape_releve() {
  local a=$T/mock.tar.gz s f
  echo "## sources de mock, tag $MOCK_TAG (codeload de GitHub, archive non signée)"
  rm -rf -- "${T:?}/mock-src"; mkdir "$T/mock-src"
  curl -fsSL --max-time 120 -o "$a" "https://codeload.github.com/rpm-software-management/mock/tar.gz/refs/tags/$MOCK_TAG"
  echo "archive : $(stat -c %s "$a") octets, sha256 $(sha256sum < "$a" | cut -c1-64)"
  tar -xzf "$a" -C "$T/mock-src" --strip-components=1
  s=$(sed -n 's/^Version:[[:space:]]*//p' "$T/mock-src/mock/mock.spec" | head -1)
  [ "$s" = 6.9 ] && echo "OK   Version de mock.spec : $s" || { echo "KO   Version de mock.spec : $s (attendu : 6.9)" >&2; exit 1; }
  echo "fichiers : $(find "$T/mock-src" -type f | wc -l) (sources lues, jamais exécutées)"
  echo "## options de mock"
  lignes "mock.py : options du mode hermétique" 'calculate-build-dependencies|hermetic-build|hermetic_build|calculate_build_dep' mock/py/mock.py
  lignes "page de manuel" 'calculate-build-dependencies|hermetic-build' mock/docs mock/mock.1 mock/mock.1.in
  echo "## mock-hermetic-repo"
  lignes "arguments" 'add_argument|ArgumentParser' mock/py/mock-hermetic-repo.py
  lignes "commandes lancées" '(cmd[a-z_]*|check) *= *\[|subprocess|createrepo' mock/py/mock-hermetic-repo.py
  echo "## etc/mock/hermetic-build.cfg"
  f=$(cd "$T/mock-src" && find . -name hermetic-build.cfg | head -1)
  if [ -n "$f" ]; then echo "fichier : ${f#./}"; sed 's/^/  /' "$T/mock-src/$f"; else echo "hermetic-build.cfg absent des sources"; fi
  echo "## verrou (plugin buildroot_lock)"
  lignes "clés écrites" 'data\[|"version"|schema' mock/py/mockbuild/plugins/buildroot_lock.py
  lignes "schémas du verrou" 'buildroot-lock|lockfile' mock/docs mock/py/mockbuild/plugins/buildroot_lock.py
  echo "## image de bootstrap prête"
  lignes "bootstrap_image_ready et hermetic dans le code" 'bootstrap_image_ready|hermetic' mock/py/mockbuild/config.py mock/py/mockbuild/buildroot.py mock/py/mockbuild/backend.py mock/py/mockbuild/util.py
  echo "## documentation du mode hermétique"
  ( cd "$T/mock-src" && grep -rl -I -i 'hermetic' docs mock/docs 2>/dev/null ) | sed 's/^/fichier : /' || true
  lignes "titres et options citées" '^#|calculate-build-dependencies|hermetic-build|mock-hermetic-repo|bootstrap_image_ready|--no-bootstrap' docs/feature-hermetic-builds.md docs/Feature-hermetic-builds.md
  rm -rf -- "${T:?}/mock-src"
  echo "sources effacées ; archive gardée sous ~/.cache (sha256 ci-dessus)"
}

plage() { # titre fichier première dernière : lignes numérotées d'une plage entière, coupées à 220 caractères
  echo "### $1 ($2, lignes $3 à $4)"
  [ -f "$T/mock-src/$2" ] || { echo "  fichier absent"; return 0; }
  awk -v d="$3" -v f="$4" 'NR >= d && NR <= f { printf "  %d: %s\n", NR, $0 }' "$T/mock-src/$2" | cut -c1-220
}

etape_releve2() {
  local a=$T/mock.tar.gz s
  echo "## archive du tag $MOCK_TAG gardée par releve (aucun accès réseau)"
  [ -f "$a" ] || { echo "KO   archive absente : $a (lancer releve d'abord)" >&2; exit 1; }
  s=$(sha256sum < "$a" | cut -c1-64)
  [ "$s" = "$ARCHIVE_SHA" ] && echo "OK   sha256 de l'archive : $s" || { echo "KO   sha256 de l'archive : $s (attendu : $ARCHIVE_SHA)" >&2; exit 1; }
  rm -rf -- "${T:?}/mock-src"; mkdir "$T/mock-src"
  tar -xzf "$a" -C "$T/mock-src" --strip-components=1
  echo "## verrou : options recopiées et champs par paquet"
  plage "plugin buildroot_lock" mock/py/mockbuild/plugins/buildroot_lock.py 1 140
  echo "### schéma 1.1.0 : propriétés déclarées (chemins jq)"
  jq -r 'paths | select(.[-2] == "properties") | map(tostring) | join(".")' "$T/mock-src/mock/docs/buildroot-lock-schema-1.1.0.json" | sed 's/^/  /'
  echo "### schéma 1.1.0 : propriétés exigées"
  jq -r '.. | objects | select(has("required")) | .required | join(", ")' "$T/mock-src/mock/docs/buildroot-lock-schema-1.1.0.json" | sed 's/^/  /'
  echo "## image de bootstrap prête"
  plage "buildroot.py autour de bootstrap_image_ready" mock/py/mockbuild/buildroot.py 1150 1205
  echo "### podman.py : inspect_hermetic_metadata et get_oci_digest"
  ( cd "$T/mock-src" && awk '/def (inspect_hermetic_metadata|get_oci_digest)/ { p = 1 } p && /^[[:space:]]*(def|class) / && !/def (inspect_hermetic_metadata|get_oci_digest)/ { p = 0 } p { printf "  %d: %s\n", FNR, $0 }' mock/py/mockbuild/podman.py ) | cut -c1-220
  plage "site-defaults.cfg, options du mode hermétique" mock/docs/site-defaults.cfg 740 790
  echo "## ce qu'impose le mode hermétique"
  plage "config.py, process_hermetic_build_config" mock/py/mockbuild/config.py 805 875
  echo "## mock-hermetic-repo : téléchargement et contrôles"
  plage "mock-hermetic-repo.py" mock/py/mock-hermetic-repo.py 1 210
  echo "## documentation : image de bootstrap et signatures"
  ( cd "$T/mock-src" && grep -n -i -E 'bootstrap|ready|gpg|signat|checksum|sha256' docs/feature-hermetic-builds.md docs/Plugin-BuildrootLock.md 2>/dev/null ) | cut -c1-220 | sed 's/^/  /' || true
  rm -rf -- "${T:?}/mock-src"
  echo "sources effacées ; archive gardée sous ~/.cache"
}

etape_releve3() {
  local a=$T/mock.tar.gz s
  echo "## archive du tag $MOCK_TAG gardée par releve (aucun accès réseau)"
  [ -f "$a" ] || { echo "KO   archive absente : $a (lancer releve d'abord)" >&2; exit 1; }
  s=$(sha256sum < "$a" | cut -c1-64)
  [ "$s" = "$ARCHIVE_SHA" ] && echo "OK   sha256 de l'archive : $s" || { echo "KO   sha256 de l'archive : $s (attendu : $ARCHIVE_SHA)" >&2; exit 1; }
  rm -rf -- "${T:?}/mock-src"; mkdir "$T/mock-src"
  tar -xzf "$a" -C "$T/mock-src" --strip-components=1
  echo "## image de bootstrap : digest affirmé et chargement d'un dossier dir:"
  echo "### taille de podman.py : $(wc -l < "$T/mock-src/mock/py/mockbuild/podman.py") lignes"
  plage "podman.py entier" mock/py/mockbuild/podman.py 1 2000
  echo "### image_assert_digest, avec ou sans préfixe bootstrap_ (mock.py:811 le retire), et les 6 lignes qui suivent"
  ( cd "$T/mock-src" && grep -rn -I -E -A6 -- 'image_assert_digest' mock/py 2>/dev/null ) | cut -c1-170 | sed 's/^/  /' || true
  lignes "images dir: et oci-archive:, dans tout le code Python" 'dir:|oci-archive' mock/py
  lignes "image_fallback et image_skip_pull, avec ou sans préfixe bootstrap_" 'image_(fallback|skip_pull)' mock/py
  echo "## coupures de références d'image"
  lignes "split(':') et split(\":\"), dans tout le code Python" "split\\(['\"]:['\"]" mock/py
  echo "## mode hermétique : tous les usages"
  lignes "hermetic_build et offline_local_repository" 'hermetic_build|offline_local_repository' mock/py
  rm -rf -- "${T:?}/mock-src"
  echo "sources effacées ; archive gardée sous ~/.cache"
}

lire_amont() { # nom-local URL : lecture HTTP sous $T/releve4, KO si le code n'est pas 200 ; taille et sha256 journalisés
  local h
  h=$(curl -sSL --max-time 60 -o "$T/releve4/$1" -w '%{http_code}' "$2") || { echo "KO   $2 : curl en échec" >&2; exit 1; }
  [ "$h" = 200 ] || { echo "KO   $2 : HTTP $h, fichier non lu" >&2; exit 1; }
  echo "lu : $2 ($(stat -c %s "$T/releve4/$1") octets, sha256 $(sha256sum < "$T/releve4/$1" | cut -c1-64))"
}

option_lue() { # titre fichier-local option témoin : lignes de l'option (et 3 suivantes), ou ABSENTE ; témoin absent : KO
  local f=$T/releve4/$2
  grep -q -F -- "\"$4\"" "$f" || { echo "KO   $1 : témoin \"$4\" absent de $2, ce n'est pas le bon fichier" >&2; exit 1; }
  echo "OK   $1 : témoin \"$4\" présent dans $2"
  if grep -q -F -- "\"$3\"" "$f"; then
    echo "PRÉSENTE $1 : \"$3\""
    grep -n -F -A3 -- "\"$3\"" "$f" | cut -c1-220 | sed 's/^/  /'
  else
    echo "ABSENTE $1 : \"$3\" introuvable dans $2"
  fi
}

etape_releve4() {
  local c=https://raw.githubusercontent.com/rpm-software-management/createrepo_c/$CREATEREPO_TAG
  local s=https://raw.githubusercontent.com/containers/skopeo/$SKOPEO_TAG
  rm -rf -- "${T:?}/releve4"; mkdir "$T/releve4"
  echo "## createrepo_c, tag $CREATEREPO_TAG (fichiers non signés)"
  lire_amont cmd_parser.c "$c/src/cmd_parser.c"
  lire_amont createrepo_c.c "$c/src/createrepo_c.c"
  option_lue "createrepo_c $CREATEREPO_TAG" cmd_parser.c compatibility checksum
  echo "### usages de compatibility dans createrepo_c.c et cmd_parser.c (3 lignes avant, 5 après)"
  ( cd "$T/releve4" && grep -n -F -B3 -A5 -- compatibility createrepo_c.c cmd_parser.c ) | cut -c1-220 | sed 's/^/  /' || true
  echo "## skopeo copy, tag $SKOPEO_TAG (fichiers non signés)"
  lire_amont copy.go "$s/cmd/skopeo/copy.go"
  lire_amont utils.go "$s/cmd/skopeo/utils.go"
  grep -n -F -- 'sharedCopyFlags()' "$T/releve4/copy.go" | sed 's/^/  copy.go:/' \
    || { echo "KO   copy.go n'appelle pas sharedCopyFlags() : les options de copie ne sont pas celles de utils.go" >&2; exit 1; }
  awk '/^func sharedCopyFlags\(/ { p = 1 } p { printf "%d: %s\n", FNR, $0 } p && /^}/ { exit }' "$T/releve4/utils.go" \
    > "$T/releve4/sharedCopyFlags.go"
  [ -s "$T/releve4/sharedCopyFlags.go" ] || { echo "KO   utils.go ne définit pas sharedCopyFlags : ce n'est pas le bon fichier" >&2; exit 1; }
  echo "### corps de sharedCopyFlags (utils.go, lignes numérotées)"
  cut -c1-220 "$T/releve4/sharedCopyFlags.go" | sed 's/^/  /'
  option_lue "skopeo copy $SKOPEO_TAG" sharedCopyFlags.go preserve-digests remove-signatures
  rm -rf -- "${T:?}/releve4"
  echo "fichiers effacés ; les correctifs des paquets de Rocky ne sont pas lus"
}

etape_releve5() {
  local a=$T/mock.tar.gz s
  echo "## archive du tag $MOCK_TAG gardée par releve (aucun accès réseau)"
  [ -f "$a" ] || { echo "KO   archive absente : $a (lancer releve d'abord)" >&2; exit 1; }
  s=$(sha256sum < "$a" | cut -c1-64)
  [ "$s" = "$ARCHIVE_SHA" ] && echo "OK   sha256 de l'archive : $s" || { echo "KO   sha256 de l'archive : $s (attendu : $ARCHIVE_SHA)" >&2; exit 1; }
  rm -rf -- "${T:?}/mock-src"; mkdir "$T/mock-src"
  tar -xzf "$a" -C "$T/mock-src" --strip-components=1
  echo "## verrou : requête des champs et calcul des URL"
  echo "### taille de installed_packages.py : $(wc -l < "$T/mock-src/mock/py/mockbuild/installed_packages.py") lignes"
  plage "installed_packages.py entier" mock/py/mockbuild/installed_packages.py 1 2000
  echo "## verrous d'exemple"
  echo "### taille de test_buildroot_lock.py : $(wc -l < "$T/mock-src/mock/tests/test_buildroot_lock.py") lignes"
  plage "test_buildroot_lock.py entier" mock/tests/test_buildroot_lock.py 1 2000
  echo "### taille de Plugin-BuildrootLock.md : $(wc -l < "$T/mock-src/docs/Plugin-BuildrootLock.md") lignes"
  plage "Plugin-BuildrootLock.md entier" docs/Plugin-BuildrootLock.md 1 2000
  echo "### schéma 1.1.0 : définitions de sigmd5, url et signature"
  jq '.properties.buildroot.properties.rpms.items.properties | {sigmd5, url, signature}' \
    "$T/mock-src/mock/docs/buildroot-lock-schema-1.1.0.json" | sed 's/^/  /'
  echo "## mentions, dans tout le code Python, les tests et la documentation"
  lignes "gpg-pubkey" 'gpg-pubkey|gpg_pubkey|pubkey' mock/py mock/tests docs mock/docs
  lignes "SIGMD5 et sigmd5" 'SIGMD5|sigmd5' mock/py mock/tests docs mock/docs
  rm -rf -- "${T:?}/mock-src"
  echo "sources effacées ; archive gardée sous ~/.cache"
}

fonction() { # titre fichier nom : première définition Python « def nom( », entière (jusqu'à la première ligne non vide de
             # retrait égal ou moindre), lignes numérotées coupées à 220 caractères, puis leur nombre
  local s
  echo "### $1 ($2, def $3)"
  [ -f "$T/mock-src/$2" ] || { echo "  fichier absent"; return 0; }
  s=$(awk -v n="$3" '
    !on && match($0, "^ *def " n "\\(") { on = 1; r = RLENGTH - length("def " n "("); printf "  %d: %s\n", NR, $0; next }
    on && /[^ ]/ { match($0, /^ */); if (RLENGTH <= r) exit }
    on { printf "  %d: %s\n", NR, $0 }' "$T/mock-src/$2" | cut -c1-220)
  if [ -n "$s" ]; then printf '%s\n' "$s"; echo "  ($(printf '%s\n' "$s" | wc -l) lignes)"; else echo "  def $3( absente"; fi
}

etape_releve6() {
  local a=$T/mock.tar.gz s c v
  echo "## archive du tag $MOCK_TAG gardée par releve (aucun accès réseau)"
  [ -f "$a" ] || { echo "KO   archive absente : $a (lancer releve d'abord)" >&2; exit 1; }
  s=$(sha256sum < "$a" | cut -c1-64)
  [ "$s" = "$ARCHIVE_SHA" ] && echo "OK   sha256 de l'archive : $s" || { echo "KO   sha256 de l'archive : $s (attendu : $ARCHIVE_SHA)" >&2; exit 1; }
  rm -rf -- "${T:?}/mock-src"; mkdir "$T/mock-src"
  tar -xzf "$a" -C "$T/mock-src" --strip-components=1
  echo "## appel normal de dnf par mock"
  echo "### taille de package_manager.py : $(wc -l < "$T/mock-src/mock/py/mockbuild/package_manager.py") lignes"
  plage "package_manager.py entier" mock/py/mockbuild/package_manager.py 1 3000
  lignes "config.py : package_manager, releasever, commandes et options communes de dnf" \
    "package_manager|'releasever'|dnf[0-9]*_command|dnf[0-9]*_common_opts|dnf_install_command|system_dnf_command|dnf_builddep_opts" \
    mock/py/mockbuild/config.py
  echo "## où tourne la commande du verrou"
  fonction "doOutChroot" mock/py/mockbuild/buildroot.py doOutChroot
  lignes "définitions et appels de doOutChroot" 'doOutChroot' mock/py
  echo "## modèle rocky-9 et dépôts après le remplacement de s1.sh"
  c=$(cd "$T/mock-src" && find . -path '*/templates/rocky-9.tpl' | sort)
  s=$(printf '%s\n' "$c" | grep -c . || true)
  [ "$s" = 1 ] && echo "OK   rocky-9.tpl trouvés dans l'archive : $s" || { echo "KO   rocky-9.tpl trouvés dans l'archive : $s (attendu : 1)" >&2; exit 1; }
  c=${c#./}
  echo "fichier : $c ; Version de mock-core-configs.spec : $(sed -n 's/^Version:[[:space:]]*//p' "$T/mock-src/mock-core-configs/mock-core-configs.spec" | head -1)"
  echo "### taille de rocky-9.tpl : $(wc -l < "$T/mock-src/$c") lignes"
  plage "rocky-9.tpl entier" "$c" 1 2000
  v=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$here/s1.sh")
  [ -n "$v" ] || { echo "KO   VAULT97 introuvable dans s1.sh" >&2; exit 1; }
  echo "### remplacement de s1.sh rejoué sur l'hôte (Python, str.replace, comme MOCK_CFG ; le modèle est lu, jamais exécuté)"
  python3 -I -u - "$T/mock-src/$c" "$here/s1.sh" "$v" <<'PY' | cut -c1-220
import configparser, re, sys
tpl, s1, vault = sys.argv[1:4]
lignes = open(s1, encoding="utf-8").read().splitlines()
for titre, x in (("boucle", "for r in ('BaseOS', 'AppStream', 'CRB'):"),
                 ("ancien texte", r"""        'mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=\$basearch&repo=%s-\$releasever\n' % r,"""),
                 ("nouveau texte", r"""        'baseurl=$VAULT97/%s/x86_64/os/\n' % r)""")):
    n = lignes.count(x)
    print(f"ligne {titre} du remplacement trouvée telle quelle dans s1.sh : {n} (attendu : 1)")
    if n != 1:
        print("KO   remplacement de s1.sh changé : releve6 à revoir", file=sys.stderr)
        sys.exit(1)
txt = open(tpl, encoding="utf-8").read()
ops = re.findall(r"config_opts\['dnf\.conf'\]\s*(\+?=)", txt)
print(f"affectations de config_opts['dnf.conf'] dans rocky-9.tpl : {ops}")
m = re.findall(r"config_opts\['dnf\.conf'\]\s*=\s*\"\"\"(.*?)\"\"\"", txt, re.S)
if ops != ["="] or len(m) != 1:
    print("KO   dnf.conf du modèle non extrait (attendu : une seule affectation = \"\"\"…\"\"\")", file=sys.stderr)
    sys.exit(1)
conf = m[0]
print(f"dnf.conf extrait : {len(conf.splitlines())} lignes ; marqueurs jinja {{{{ : {conf.count('{{')}, {{% : {conf.count('{%')} ; barres obliques inverses : {conf.count(chr(92))}")
for r in ("BaseOS", "AppStream", "CRB"):
    old = "mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=$basearch&repo=%s-$releasever\n" % r
    print(f"{r} : mirrorlist remplacé {conf.count(old)} fois")
    conf = conf.replace(old, "baseurl=%s/%s/x86_64/os/\n" % (vault, r))
try:
    p = configparser.ConfigParser(interpolation=None, strict=False, default_section="\x00")
    p.read_string(conf)
    sec = {x: dict(p[x]) for x in p.sections()}
except configparser.Error as e:
    print(f"configparser en échec ({type(e).__name__} : {str(e).splitlines()[0]}) : lecture ligne à ligne des sections et des clés"
          " enabled, baseurl, mirrorlist, metalink et reposdir (valeurs répétées mises bout à bout)")
    sec, cur = {}, None
    for x in conf.splitlines():
        m = re.match(r"\s*\[([^\]]+)\]\s*$", x)
        if m:
            cur = m.group(1)
            sec.setdefault(cur, {})
            continue
        m = re.match(r"\s*(enabled|baseurl|mirrorlist|metalink|reposdir)\s*=\s*(.*)$", x)
        if m and cur is not None:
            sec[cur][m.group(1)] = (sec[cur].get(m.group(1), "") + " " + m.group(2)).strip()
if "main" in sec:
    print("[main] : " + " ; ".join(f"{k}={v}" for k, v in sec["main"].items()))
else:
    print("[main] absente")
hors = []
for s, d in sec.items():
    if s == "main":
        continue
    e = d.get("enabled", "(absent)")
    u = [f"{k}={' '.join(d[k].split())}" for k in ("baseurl", "mirrorlist", "metalink") if k in d]
    print(f"dépôt [{s}] : enabled={e} ; " + (" ; ".join(u) if u else "aucune URL"))
    b = d.get("baseurl", "").split()
    if e.strip().lower() not in ("0", "false", "no", "off") and not (b and "mirrorlist" not in d and "metalink" not in d
                                                                      and all(x.startswith(vault + "/") for x in b)):
        hors.append(s)
print(f"dépôts actifs ou sans enabled, hors des seules baseurl de vault 9.7 : {len(hors)} {hors}")
PY
  rm -rf -- "${T:?}/mock-src"
  echo "sources effacées ; archive gardée sous ~/.cache"
}

lire_r7() { # fichier URL : code HTTP sur la sortie (redirections en https seulement) ; curl en échec : KO
  local h
  h=$(curl -sS -L --proto =https --proto-redir =https --max-time 120 -o "$T/releve7/$1" -w '%{http_code}' "$2") \
    || { echo "KO   $2 : curl en échec" >&2; exit 1; }
  printf '%s' "$h"
}

depot_r7() { # étiquette URL-du-dépôt : repomd.xml signé par $fp, primary égal à sa somme, paquets et provides mis à plat
             # (<étiquette>.paquets, <étiquette>.provides) ; HTTP 404 sur repomd.xml : ABSENT, retour 2 ; tout autre écart : KO
  local l=$1 b=$2 d=$T/releve7 h s p x
  h=$(lire_r7 "$l.repomd.xml" "$b/repodata/repomd.xml") || exit 1
  if [ "$h" = 404 ]; then echo "ABSENT $l : HTTP 404 sur $b/repodata/repomd.xml"; return 2; fi
  [ "$h" = 200 ] || { echo "KO   $l : HTTP $h sur $b/repodata/repomd.xml" >&2; exit 1; }
  h=$(lire_r7 "$l.repomd.xml.asc" "$b/repodata/repomd.xml.asc") || exit 1
  [ "$h" = 200 ] || { echo "KO   $l : HTTP $h sur $b/repodata/repomd.xml.asc" >&2; exit 1; }
  s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/$l.repomd.xml.asc" "$d/$l.repomd.xml" 2>/dev/null \
    | awk '$2 == "VALIDSIG" {print $NF}' || true)
  [ "$s" = "$fp" ] && echo "OK   $l : repomd.xml signé par $s" \
    || { echo "KO   $l : signataire de repomd.xml « $s » (attendu : $fp)" >&2; exit 1; }
  echo "$l : repomd.xml sha256 $(sha256sum < "$d/$l.repomd.xml" | cut -c1-64)"
  p=$(python3 -I - "$d/$l.repomd.xml" <<'PY'
import re, sys, xml.etree.ElementTree as E
n = {'r': 'http://linux.duke.edu/metadata/repo'}
d = [x for x in E.parse(sys.argv[1]).getroot().findall('r:data', n) if x.get('type') == 'primary']
if len(d) != 1:
    sys.exit(f"{len(d)} entrées primary dans repomd.xml (attendu : 1)")
c, h = d[0].find('r:checksum', n), d[0].find('r:location', n)
if c is None or h is None or c.get('type') != 'sha256' or not re.fullmatch(r'[0-9a-f]{64}', (c.text or '').strip()):
    sys.exit("somme sha256 du primary absente ou mal formée")
h = h.get('href') or ''
if not re.fullmatch(r'repodata/[A-Za-z0-9._-]+\.xml\.(gz|xz|bz2)', h):
    sys.exit(f"emplacement du primary refusé : {h}")
print(c.text.strip(), h)
PY
  ) || { echo "KO   $l : entrée primary de repomd.xml refusée" >&2; exit 1; }
  s=${p%% *}; p=${p#* }
  x=${p##*.}
  h=$(lire_r7 "$l.primary.xml.$x" "$b/$p") || exit 1
  [ "$h" = 200 ] || { echo "KO   $l : HTTP $h sur $b/$p" >&2; exit 1; }
  [ "$(sha256sum < "$d/$l.primary.xml.$x" | cut -c1-64)" = "$s" ] \
    && echo "OK   $l : primary ($x) conforme à repomd.xml ($(stat -c %s "$d/$l.primary.xml.$x") octets)" \
    || { echo "KO   $l : sha256 du primary différent de repomd.xml ($s)" >&2; exit 1; }
  python3 -I - "$l" "$d/$l.primary.xml.$x" "$d/$l.paquets" "$d/$l.provides" <<'PY' || { echo "KO   $l : primary illisible" >&2; exit 1; }
import bz2, gzip, lzma, sys, xml.etree.ElementTree as E
l, src, out, prov = sys.argv[1:5]
ouvrir = {'gz': gzip.open, 'xz': lzma.open, 'bz2': bz2.open}[src.rsplit('.', 1)[1]]
C = '{http://linux.duke.edu/metadata/common}'; R = '{http://linux.duke.edu/metadata/rpm}'
n = 0
with ouvrir(src) as f, open(out, 'w', encoding='utf-8') as o, open(prov, 'w', encoding='utf-8') as q:
    for _, p in E.iterparse(f):
        if p.tag != C + 'package':
            continue
        if p.get('type') == 'rpm':
            v, nom = p.find(C + 'version'), p.findtext(C + 'name')
            o.write(f"{nom}\t{v.get('epoch')}:{v.get('ver')}-{v.get('rel')}.{p.findtext(C + 'arch')}\n")
            for e in p.findall(f'{C}format/{R}provides/{R}entry'):
                q.write(f"{nom}\t{e.get('name')}\n")
            n += 1
        p.clear()
print(f"{l} : {n} paquets dans le primary")
PY
}

etape_releve7() {
  local d=$T/releve7 a=$T/mock.tar.gz v cle fp s h x n u e=0 r1=0 r2=0
  local -a l=()
  echo "## épingles lues dans s1.sh (non modifié)"
  v=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$here/s1.sh")
  cle=$(sed -n 's|^CLE_ROCKY=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$here/s1.sh")
  fp=$(sed -n 's/^FP_ROCKY=\([0-9A-F]\{40\}\)\([[:space:]].*\)\{0,1\}$/\1/p' "$here/s1.sh")
  for x in "VAULT97:$v" "CLE_ROCKY:$cle" "FP_ROCKY:$fp"; do
    n=$(printf '%s' "${x#*:}" | grep -c . || true)
    [ "$n" = 1 ] && echo "OK   ${x%%:*} : ${x#*:}" \
      || { echo "KO   ${x%%:*} : $n ligne(s) reconnue(s) dans s1.sh (attendu : 1)" >&2; exit 1; }
  done
  rm -rf -- "${d:?}"; mkdir -p "$d/src"; mkdir -m 700 "$d/gnupg"; export GNUPGHOME=$d/gnupg
  echo "## clé de Rocky (trousseau temporaire)"
  h=$(lire_r7 RPM-GPG-KEY-Rocky-9 "$cle") || exit 1
  [ "$h" = 200 ] || { echo "KO   $cle : HTTP $h" >&2; exit 1; }
  s=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}' || true)
  [ "$s" = "$fp" ] && echo "OK   empreinte de la clé de Rocky : $s" \
    || { echo "KO   empreinte de la clé de Rocky : « $s » (attendu : $fp)" >&2; exit 1; }
  gpg --batch --quiet --no-default-keyring --keyring "$d/cles.gpg" --import "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null \
    || { echo "KO   clé de Rocky non importée" >&2; exit 1; }
  echo "## chroot_setup_cmd de rocky-9.tpl (archive du tag $MOCK_TAG gardée par releve, sans réseau)"
  [ -f "$a" ] || { echo "KO   archive absente : $a (lancer releve d'abord)" >&2; exit 1; }
  s=$(sha256sum < "$a" | cut -c1-64)
  [ "$s" = "$ARCHIVE_SHA" ] && echo "OK   sha256 de l'archive : $s" || { echo "KO   sha256 de l'archive : $s (attendu : $ARCHIVE_SHA)" >&2; exit 1; }
  tar -xzf "$a" -C "$d/src" --strip-components=1 --wildcards '*/templates/rocky-9.tpl'
  x=$(cd "$d/src" && find . -path '*/templates/rocky-9.tpl' | sort); n=$(printf '%s' "$x" | grep -c . || true)
  [ "$n" = 1 ] && echo "OK   rocky-9.tpl trouvés dans l'archive : $n" || { echo "KO   rocky-9.tpl trouvés dans l'archive : $n (attendu : 1)" >&2; exit 1; }
  python3 -I - "$d/src/${x#./}" "$d/chroot.noms" <<'PY' || { echo "KO   chroot_setup_cmd non lu" >&2; exit 1; }
import re, sys
t = open(sys.argv[1], encoding='utf-8').read()
m = re.findall(r"^config_opts\['chroot_setup_cmd'\]\s*=\s*'([^']*)'\s*$", t, re.M)
if len(m) != 1:
    sys.exit(f"{len(m)} affectations simples de chroot_setup_cmd (attendu : 1)")
mots = m[0].split()
if not mots or mots[0] != 'install':
    sys.exit("chroot_setup_cmd ne commence pas par install")
noms = [x for x in mots[1:] if re.fullmatch(r'[A-Za-z0-9._+-]+', x)]
autres = [x for x in mots[1:] if x not in noms]
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write('\n'.join(noms) + '\n')
print(f"chroot_setup_cmd : {len(noms)} noms : {' '.join(noms)}")
print(f"mots écartés (groupe, modèle jinja) : {' '.join(autres) or 'aucun'}")
PY
  echo "## ce que sert le mirrorlist d'extras (releasever 9 de rocky-9.tpl, x86_64 ; ni hôtes ni commentaires journalisés)"
  u='https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=extras-9'
  h=$(lire_r7 mirrorlist.txt "$u") || exit 1
  n=$(grep -s -c -E '^https?://' "$d/mirrorlist.txt" || true)
  if [ "$h" = 200 ] && [ "$n" -gt 0 ]; then
    echo "HTTP 200 ; $n URL ; $(grep -s -c -v -E '^https?://' "$d/mirrorlist.txt" || true) autre(s) ligne(s), non journalisée(s)"
    echo "segments « /<version>/<dépôt>/ » des chemins, hôte retiré (nombre d'URL) :"
    { grep -E '^https?://' "$d/mirrorlist.txt" | sed -E 's#^https?://[^/]+##' | grep -oE '/[0-9][0-9.]*/[A-Za-z]+/' | sort | uniq -c | sed 's/^/  /'; } || true
    echo "URL sans segment reconnu : $(grep -E '^https?://' "$d/mirrorlist.txt" | sed -E 's#^https?://[^/]+##' | grep -c -v -E '/[0-9][0-9.]*/[A-Za-z]+/' || true)"
  else
    echo "KO   mirrorlist d'extras : HTTP $h, $n URL ; la suite tourne, code final 1"; e=1
  fi
  echo "## dossiers de $v/ (liste HTML non signée : un index, pas une preuve)"
  h=$(lire_r7 vault.html "$v/") || exit 1
  [ "$h" = 200 ] || { echo "KO   $v/ : HTTP $h" >&2; exit 1; }
  { grep -s -oE 'href="[A-Za-z0-9_.-]+/"' "$d/vault.html" | sed 's/^href="//; s/"$//' | sort -u > "$d/dossiers"; } || true
  echo "$(grep -c . "$d/dossiers" || true) dossiers : $(tr '\n' ' ' < "$d/dossiers")"
  x=$(grep -i -x -F 'extras/' "$d/dossiers" || true); n=$(printf '%s' "$x" | grep -c . || true)
  case $n in
    0) echo "aucun dossier extras/ (casse ignorée) ; repomd.xml cherché quand même sous extras/"; x=extras/ ;;
    1) echo "dossier retenu : $x" ;;
    *) echo "KO   $n dossiers extras/ à la casse près : $(tr '\n' ' ' <<<"$x")" >&2; exit 1 ;;
  esac
  echo "## BaseOS, AppStream et CRB de vault 9.7, épinglés par s1.sh (référence des croisements)"
  for u in BaseOS AppStream CRB; do
    depot_r7 "vault-$u" "$v/$u/x86_64/os" || { echo "KO   vault-$u absent" >&2; exit 1; }
  done
  cp "$d/vault-BaseOS.repomd.xml" "$d/temoin.xml"; echo x >> "$d/temoin.xml"
  s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/vault-BaseOS.repomd.xml.asc" "$d/temoin.xml" 2>/dev/null | awk '$2 == "VALIDSIG"' || true)
  [ -z "$s" ] && echo "OK   témoin altéré (repomd.xml de vault-BaseOS plus une ligne) refusé" \
    || { echo "KO   témoin altéré accepté" >&2; exit 1; }
  echo "## extras de vault 9.7 (ce qu'un remplacement donnerait, si le propriétaire le décide)"
  depot_r7 vault-extras "$v/${x%/}/x86_64/os" || r1=$?
  [ "$r1" = 0 ] && l+=(vault-extras)
  echo "## extras de pub/rocky/9 (baseurl commentée de rocky-9.tpl avec releasever 9 : l'origine des miroirs)"
  depot_r7 pub9-extras https://dl.rockylinux.org/pub/rocky/9/extras/x86_64/os || r2=$?
  [ "$r2" = 0 ] && l+=(pub9-extras)
  echo "## croisements par nom (un croisement vide n'exclut pas une dépendance que seul extras satisferait)"
  python3 -I - "$d" "${l[@]}" <<'PY' || { echo "KO   croisements non faits" >&2; exit 1; }
import os, sys
d, labs = sys.argv[1], sys.argv[2:]
def lire(f):
    with open(os.path.join(d, f), encoding='utf-8') as h:
        return [x.rstrip('\n').split('\t') for x in h if x.strip()]
with open(os.path.join(d, 'chroot.noms'), encoding='utf-8') as h:
    ch = set(h.read().split())
base = {}
for b in ('vault-BaseOS', 'vault-AppStream', 'vault-CRB'):
    for nom, evr in lire(b + '.paquets'):
        base.setdefault(nom, set()).add(f"{b} {evr}")
print(f"noms distincts dans BaseOS, AppStream et CRB 9.7 : {len(base)} ; noms de chroot_setup_cmd : {len(ch)}")
noms = {}
for lab in labs:
    p, pr = lire(lab + '.paquets'), lire(lab + '.provides')
    noms[lab] = {n for n, _ in p}
    print(f"### {lab} : {len(p)} paquets")
    for n, evr in sorted(p):
        print(f"  {n} {evr}")
    print(f"noms de chroot_setup_cmd qui sont des paquets de {lab} : {' '.join(sorted(noms[lab] & ch)) or 'aucun'}")
    b = sorted({f"{x} (par {n})" for n, x in pr if x in ch})
    print(f"noms de chroot_setup_cmd fournis (provides) par {lab} : {' ; '.join(b) or 'aucun'}")
    c = sorted(noms[lab] & base.keys())
    print(f"paquets de {lab} dont le nom est aussi dans BaseOS, AppStream ou CRB 9.7 : {len(c)}")
    for n in c:
        print(f"  {n} : {lab} {' '.join(e for m, e in p if m == n)} ; {' ; '.join(sorted(base[n]))}")
if len(labs) == 2:
    x, y = (noms[k] for k in labs)
    print(f"noms seulement dans {labs[0]} : {' '.join(sorted(x - y)) or 'aucun'}")
    print(f"noms seulement dans {labs[1]} : {' '.join(sorted(y - x)) or 'aucun'}")
if not labs:
    print("aucun dépôt extras lu : pas de croisement")
PY
  gpgconf --kill all 2>/dev/null || true
  rm -rf -- "${d:?}"
  echo "fichiers effacés (clé, métadonnées, modèle extrait) ; archive gardée sous ~/.cache"
  [ "$e" = 0 ] || { echo "KO   écart ci-dessus (mirrorlist) : code 1" >&2; exit 1; }
}

fichiers_r8() { # étiquette URL-du-dépôt : entrée filelists du repomd.xml déjà vérifié par depot_r7 (même passage), somme
                # égale ; fichiers des paquets de <étiquette>.golang mis à plat dans <étiquette>.fichiers ; tout écart : KO
  local lab=$1 b=$2 d=$T/releve7 h s p x
  p=$(python3 -I - "$d/$lab.repomd.xml" <<'PY'
import re, sys, xml.etree.ElementTree as E
n = {'r': 'http://linux.duke.edu/metadata/repo'}
d = [x for x in E.parse(sys.argv[1]).getroot().findall('r:data', n) if x.get('type') == 'filelists']
if len(d) != 1:
    sys.exit(f"{len(d)} entrées filelists dans repomd.xml (attendu : 1)")
c, h = d[0].find('r:checksum', n), d[0].find('r:location', n)
if c is None or h is None or c.get('type') != 'sha256' or not re.fullmatch(r'[0-9a-f]{64}', (c.text or '').strip()):
    sys.exit("somme sha256 du filelists absente ou mal formée")
h = h.get('href') or ''
if not re.fullmatch(r'repodata/[A-Za-z0-9._-]+\.xml\.(gz|xz|bz2)', h):
    sys.exit(f"emplacement du filelists refusé : {h}")
print(c.text.strip(), h)
PY
  ) || { echo "KO   $lab : entrée filelists de repomd.xml refusée" >&2; exit 1; }
  s=${p%% *}; p=${p#* }
  x=${p##*.}
  h=$(lire_r7 "$lab.filelists.xml.$x" "$b/$p") || exit 1
  [ "$h" = 200 ] || { echo "KO   $lab : HTTP $h sur $b/$p" >&2; exit 1; }
  [ "$(sha256sum < "$d/$lab.filelists.xml.$x" | cut -c1-64)" = "$s" ] \
    && echo "OK   $lab : filelists ($x) conforme à repomd.xml ($(stat -c %s "$d/$lab.filelists.xml.$x") octets)" \
    || { echo "KO   $lab : sha256 du filelists différent de repomd.xml ($s)" >&2; exit 1; }
  python3 -I - "$lab" "$d/$lab.filelists.xml.$x" "$d/$lab.golang" "$d/$lab.fichiers" <<'PY' || { echo "KO   $lab : filelists illisible" >&2; exit 1; }
import bz2, gzip, lzma, sys, xml.etree.ElementTree as E
l, src, sel, out = sys.argv[1:5]
ouvrir = {'gz': gzip.open, 'xz': lzma.open, 'bz2': bz2.open}[src.rsplit('.', 1)[1]]
F = '{http://linux.duke.edu/metadata/filelists}'
with open(sel, encoding='utf-8') as f:
    voulus = {tuple(x.rstrip('\n').split('\t')[:2]) for x in f if x.strip()}
vus, n = set(), 0
with ouvrir(src) as f, open(out, 'w', encoding='utf-8') as o:
    for _, p in E.iterparse(f):
        if p.tag != F + 'package':
            continue
        v = p.find(F + 'version')
        c = (p.get('name'), f"{v.get('epoch')}:{v.get('ver')}-{v.get('rel')}.{p.get('arch')}")
        if c in voulus:
            vus.add(c)
            for x in p.findall(F + 'file'):
                if x.get('type') != 'dir':
                    o.write(f"{c[0]}\t{c[1]}\t{x.text}\n")
                    n += 1
        p.clear()
manque = sorted(voulus - vus)
if manque:
    sys.exit(f"{len(manque)} paquet(s) du primary absent(s) du filelists : {' ; '.join(' '.join(m) for m in manque)}")
print(f"{l} : {len(vus)} paquets de la source golang retrouvés dans le filelists, {n} fichiers (dossiers exclus)")
PY
}

etape_releve8() {
  local d=$T/releve7 v cle fp s h x n u o
  local -a l=()
  echo "## épingles lues dans s1.sh (non modifié) et golang des builds OBS (banc A2, archivé)"
  v=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$here/s1.sh")
  cle=$(sed -n 's|^CLE_ROCKY=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$here/s1.sh")
  fp=$(sed -n 's/^FP_ROCKY=\([0-9A-F]\{40\}\)\([[:space:]].*\)\{0,1\}$/\1/p' "$here/s1.sh")
  o=$(sed -n 's/^  <bdep name="golang" version="\([0-9.]*\)" release="\([0-9A-Za-z._]*\)" arch="x86_64" .* project="Rocky:9\.7" repository="appstream"\/>$/\1-\2/p' \
    "$here/../../benchmarks/obs/resultats/build-1/rocky_9/_buildenv")
  for x in "VAULT97:$v" "CLE_ROCKY:$cle" "FP_ROCKY:$fp" "golang de build-1/rocky_9/_buildenv:$o"; do
    n=$(printf '%s' "${x#*:}" | grep -c . || true)
    [ "$n" = 1 ] && echo "OK   ${x%%:*} : ${x#*:}" \
      || { echo "KO   ${x%%:*} : $n ligne(s) reconnue(s) (attendu : 1)" >&2; exit 1; }
  done
  rm -rf -- "${d:?}"; mkdir -p "$d"; mkdir -m 700 "$d/gnupg"; export GNUPGHOME=$d/gnupg
  echo "## clé de Rocky (trousseau temporaire)"
  h=$(lire_r7 RPM-GPG-KEY-Rocky-9 "$cle") || exit 1
  [ "$h" = 200 ] || { echo "KO   $cle : HTTP $h" >&2; exit 1; }
  s=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}' || true)
  [ "$s" = "$fp" ] && echo "OK   empreinte de la clé de Rocky : $s" \
    || { echo "KO   empreinte de la clé de Rocky : « $s » (attendu : $fp)" >&2; exit 1; }
  gpg --batch --quiet --no-default-keyring --keyring "$d/cles.gpg" --import "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null \
    || { echo "KO   clé de Rocky non importée" >&2; exit 1; }
  echo "## BaseOS, AppStream et CRB de vault 9.7, épinglés par s1.sh"
  for u in BaseOS AppStream CRB; do
    depot_r7 "vault-$u" "$v/$u/x86_64/os" || { echo "KO   vault-$u absent" >&2; exit 1; }
  done
  cp "$d/vault-AppStream.repomd.xml" "$d/temoin.xml"; echo x >> "$d/temoin.xml"
  s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/vault-AppStream.repomd.xml.asc" "$d/temoin.xml" 2>/dev/null | awk '$2 == "VALIDSIG"' || true)
  [ -z "$s" ] && echo "OK   témoin altéré (repomd.xml de vault-AppStream plus une ligne) refusé" \
    || { echo "KO   témoin altéré accepté" >&2; exit 1; }
  echo "## paquets de la source golang (sourcerpm golang-*) et fournisseurs de « golang », lus dans les primary signés"
  python3 -I - "$d" "$o" <<'PY' || { echo "KO   paquets golang non relevés" >&2; exit 1; }
import bz2, glob, gzip, lzma, os, re, sys, xml.etree.ElementTree as E
d, obs = sys.argv[1], sys.argv[2]
C = '{http://linux.duke.edu/metadata/common}'; R = '{http://linux.duke.edu/metadata/rpm}'

def segs(s):  # rpmvercmp réécrit sans relecture de la source de rpm : segments, ~ avant tout, ^ après la fin seulement
    i, r = 0, []
    while i < len(s):
        c = s[i]
        if c in '~^':
            r.append(c); i += 1
        elif c.isascii() and c.isdigit():
            j = i
            while j < len(s) and s[j].isascii() and s[j].isdigit():
                j += 1
            r.append(('n', s[i:j])); i = j
        elif c.isascii() and c.isalpha():
            j = i
            while j < len(s) and s[j].isascii() and s[j].isalpha():
                j += 1
            r.append(('a', s[i:j])); i = j
        else:
            i += 1
    return r

def vercmp(a, b):
    if a == b:
        return 0
    x, y = segs(a), segs(b)
    i = 0
    while True:
        p = x[i] if i < len(x) else None
        q = y[i] if i < len(y) else None
        if p == '~' or q == '~':
            if p != '~':
                return 1
            if q != '~':
                return -1
            i += 1; continue
        if p == '^' or q == '^':
            if p is None:
                return -1
            if q is None:
                return 1
            if p != '^':
                return 1
            if q != '^':
                return -1
            i += 1; continue
        if p is None or q is None:
            return 0 if p is None and q is None else (-1 if p is None else 1)
        if p[0] != q[0]:
            return 1 if p[0] == 'n' else -1
        if p[0] == 'n':
            u, v = p[1].lstrip('0'), q[1].lstrip('0')
            if len(u) != len(v):
                return 1 if len(u) > len(v) else -1
        else:
            u, v = p[1], q[1]
        if u != v:
            return 1 if u > v else -1
        i += 1

def evrcmp(a, b):
    for u, v in zip(a, b):
        if u == v:
            continue
        if isinstance(u, int):
            return 1 if u > v else -1
        r = vercmp(u, v)
        if r:
            return r
    return 0

temoins = [('1.25.10', '1.25.9', 1), ('1.25.9', '1.25.9', 0), ('1.el9_7', '2.el9_7', -1), ('1.0~rc1', '1.0', -1),
           ('1.0^git1', '1.0', 1), ('1.0^git1', '1.0.1', -1), ('1.010', '1.9', 1), ('1.a', '1.1', -1), ('el9_10', 'el9_9', 1)]
for a, b, r in temoins:
    if vercmp(a, b) != r or vercmp(b, a) != -r:
        sys.exit(f"témoin de rpmvercmp faux : {a} contre {b} (attendu : {r})")
print(f"OK   rpmvercmp : {len(temoins)} témoins tenus (dans les deux sens)")

def ouvrir(f):
    return {'gz': gzip.open, 'xz': lzma.open, 'bz2': bz2.open}[f.rsplit('.', 1)[1]](f)

fourn, total = [], 0
for dep in ('vault-BaseOS', 'vault-AppStream', 'vault-CRB'):
    src = glob.glob(os.path.join(d, dep + '.primary.xml.*'))
    if len(src) != 1:
        sys.exit(f"{dep} : {len(src)} primary sur disque (attendu : 1)")
    sel = []
    with ouvrir(src[0]) as f:
        for _, p in E.iterparse(f):
            if p.tag != C + 'package':
                continue
            if p.get('type') == 'rpm':
                v = p.find(C + 'version')
                nom, arch = p.findtext(C + 'name'), p.findtext(C + 'arch')
                srpm = p.findtext(f'{C}format/{R}sourcerpm') or ''
                m = re.fullmatch(r'(.+)-([^-]+)-([^-]+)\.src\.rpm', srpm)
                prov = {e.get('name') for e in p.findall(f'{C}format/{R}provides/{R}entry')}
                if (m and m.group(1) == 'golang') or 'golang' in prov:
                    ep = v.get('epoch') or '0'
                    if not ep.isdigit():
                        sys.exit(f"{dep} : époque illisible pour {nom} : {ep}")
                    lic = (p.findtext(f'{C}format/{R}license') or '').strip()
                    sel.append((nom, f"{ep}:{v.get('ver')}-{v.get('rel')}.{arch}", (int(ep), v.get('ver'), v.get('rel')),
                                arch, lic or '(vide)', srpm or '(absent)', 'golang' in prov, bool(m and m.group(1) == 'golang')))
            p.clear()
    total += len(sel)
    with open(os.path.join(d, dep + '.golang'), 'w', encoding='utf-8') as o:
        for s in sel:
            if s[7]:
                o.write(f"{s[0]}\t{s[1]}\n")
    print(f"### {dep} : {len(sel)} paquet(s) de la source golang ou fournisseur(s) de golang")
    for s in sorted(sel, key=lambda s: (s[0], s[1])):
        print(f"  {s[0]} {s[1]} ; License: {s[4]} ; sourcerpm {s[5]}{' ; fournit golang' if s[6] else ''}")
    fourn += [(dep, s) for s in sel if s[6]]
if not total:
    sys.exit("aucun paquet de la source golang dans BaseOS, AppStream ni CRB de vault 9.7")
print("## fournisseurs de « golang » (BuildRequires: golang >= 1.24 du spec), du plus haut au plus bas (rpmvercmp)")
if not fourn:
    sys.exit("aucun fournisseur de golang")
import functools
fourn.sort(key=functools.cmp_to_key(lambda a, b: evrcmp(a[1][2], b[1][2])), reverse=True)
for dep, s in fourn:
    print(f"  {dep} {s[0]} {s[1]}")
h = fourn[0]
egaux = [x for x in fourn if evrcmp(x[1][2], h[1][2]) == 0 and x[1][0] != h[1][0]]
print(f"plus haute version qui fournit golang : {h[1][0]} {h[1][1]} ({h[0]}){' ; même EVR chez : ' + ' '.join(x[1][0] for x in egaux) if egaux else ''}")
gol = [s for _, s in fourn if s[0] == 'golang']
print(f"constructions du paquet golang : {len(gol)}")
print(f"golang {obs} (builds OBS, banc A2) présent dans vault 9.7 : {'oui' if any(s[1].split(':', 1)[1].rsplit('.', 1)[0] == obs for s in gol) else 'non'}")
print(f"golang {obs} est la plus haute construction du paquet golang : {'oui' if gol and max(gol, key=functools.cmp_to_key(lambda a, b: evrcmp(a[2], b[2])))[1].split(':', 1)[1].rsplit('.', 1)[0] == obs else 'non'}")
PY
  echo "## fichiers de licence des paquets de la source golang (filelists signés par la chaîne repomd.xml)"
  for u in BaseOS AppStream CRB; do
    if [ -s "$d/vault-$u.golang" ]; then l+=("vault-$u"); fi
  done
  [ "${#l[@]}" -gt 0 ] || { echo "KO   aucun dépôt ne porte la source golang" >&2; exit 1; }
  for u in "${l[@]}"; do
    fichiers_r8 "$u" "$v/${u#vault-}/x86_64/os"
  done
  python3 -I - "$d" "${l[@]}" <<'PY' || { echo "KO   fichiers de licence non relevés" >&2; exit 1; }
import os, re, sys
d, labs = sys.argv[1], sys.argv[2:]
motif = re.compile(r'(LICEN[CS]E|COPYING|PATENTS|NOTICE)([._-][A-Za-z0-9._-]*)?')
for lab in labs:
    with open(os.path.join(d, lab + '.fichiers'), encoding='utf-8') as f:
        lignes = [x.rstrip('\n').split('\t') for x in f if x.strip()]
    par = {}
    for nom, evr, chemin in lignes:
        par.setdefault((nom, evr), []).append(chemin)
    print(f"### {lab}")
    for (nom, evr), ch in sorted(par.items()):
        doc = sorted(c for c in ch if c.startswith(('/usr/share/licenses/', '/usr/share/doc/')))
        lic = sorted(c for c in ch if motif.fullmatch(os.path.basename(c)) and c not in doc)
        print(f"{nom} {evr} : {len(ch)} fichiers ; {len(doc)} sous /usr/share/licenses ou /usr/share/doc ; {len(lic)} autres au nom de licence")
        for c in doc:
            print(f"  doc  {c}")
        for c in lic:
            print(f"  nom  {c}")
PY
  gpgconf --kill all 2>/dev/null || true
  rm -rf -- "${d:?}"
  echo "fichiers effacés (clé, métadonnées)"
}

passage_r9() { # fichier-relatif-aux-sources début fin ligne-d-ancre texte-d-ancre : plage archivée, ancre exigée (sinon KO)
  local f=$T/mock-src/$1
  [ -f "$f" ] && sed -n "${4}p" "$f" | grep -q -F -- "$5" \
    || { echo "KO   ancre absente : $1:$4 devrait contenir « $5 »" >&2; exit 1; }
  echo "### $1, lignes $2 à $3 (ancre $4 : « $5 »)"
  sed -n "${2},${3}p" "$f" | awk -v n="$2" '{printf "  %d: %s\n", n + NR - 1, $0}' | cut -c1-170
}

etape_releve9() {
  local d=$T/releve7 a=$T/mock.tar.gz v cle fp s h o p g u b9=$((64 * 1024 * 1024))
  echo "## partie hors réseau : archive du tag $MOCK_TAG gardée par releve (lue, jamais exécutée)"
  [ -s "$a" ] || { echo "KO   archive $a absente" >&2; exit 1; }
  s=$(sha256sum < "$a" | cut -c1-64)
  [ "$s" = "$ARCHIVE_SHA" ] && echo "OK   sha256 de l'archive : $s" \
    || { echo "KO   sha256 de l'archive : $s (attendu : $ARCHIVE_SHA)" >&2; exit 1; }
  rm -rf -- "${T:?}/mock-src"; mkdir "$T/mock-src"
  tar -xzf "$a" -C "$T/mock-src" --strip-components=1
  s=$(sed -n 's/^Version:[[:space:]]*//p' "$T/mock-src/mock-core-configs/mock-core-configs.spec" | head -1)
  p=$(grep -c -F '"mock-core-configs 45.2-1.el9 epel9"' "$here/s1.sh" || true)
  [ "$s" = 45.2 ] && [ "$p" = 1 ] && echo "OK   mock-core-configs de l'archive : $s ; épingle de s1.sh : mock-core-configs 45.2-1.el9" \
    || { echo "KO   mock-core-configs de l'archive : « $s », épingle 45.2-1.el9 trouvée $p fois dans s1.sh" >&2; exit 1; }
  echo "### nodocs, tsflags et excludedocs, sans distinction de casse, dans toute l'archive (tests compris)"
  ( cd "$T/mock-src" && grep -rn -I -i -E 'nodocs|tsflags|excludedocs' . ) | cut -c1-170 | sed 's/^/  /' || true
  passage_r9 mock/py/mockbuild/package_manager.py 140 150 147 'self.is_bootstrap_image = buildroot.uses_bootstrap_image'
  passage_r9 mock/py/mockbuild/package_manager.py 155 165 157 "self.common_opts = copy.copy(config.get(f'{self.name}_common_opts', []))"
  passage_r9 mock/py/mockbuild/config.py 374 380 378 "config_opts['dnf4_common_opts'] = ["
  passage_r9 mock/py/mockbuild/package_manager.py 211 251 237 'if self.support_installroot and not self.is_bootstrap_image:'
  passage_r9 mock/py/mockbuild/package_manager.py 284 339 322 'if not self.support_installroot or self.is_bootstrap_image:'
  passage_r9 mock/py/mockbuild/package_manager.py 700 709 706 "dnfconf_path = self.buildroot.make_chroot_path('etc', 'dnf', 'dnf.conf')"
  passage_r9 mock/py/mockbuild/buildroot.py 1155 1158 1158 'return self.is_bootstrap and self.use_chroot_image'
  passage_r9 mock/py/mockbuild/buildroot.py 786 803 797 '.rpmmacros'
  echo "### _common_opts dans les modèles (mock-core-configs) et dans s1.sh"
  ( cd "$T/mock-src" && grep -rn -I -E '_common_opts' mock-core-configs ) | cut -c1-170 | sed 's/^/  /' || true
  echo "  lignes de s1.sh : $(grep -c -E '_common_opts|nodocs|excludedocs' "$here/s1.sh" || true) (_common_opts, nodocs ou excludedocs)"
  rm -rf -- "${T:?}/mock-src"
  echo "### s1.sh (non modifié) : fonction qui porte tsflags=nodocs"
  p=$(grep -n -x 'tsflags=nodocs' "$here/s1.sh" | cut -d: -f1)
  h=$(grep -n '^dnf_conf() { # configuration de dnf de l.étape racine$' "$here/s1.sh" | cut -d: -f1)
  [ "$(printf '%s\n' "$p" | grep -c .)" = 1 ] && [ "$(printf '%s\n' "$h" | grep -c .)" = 1 ] && [ "$h" -lt "$p" ] \
    && [ "$((p - h))" -le 10 ] \
    || { echo "KO   tsflags=nodocs (ligne(s) « $p ») hors de dnf_conf (ligne(s) « $h ») de s1.sh" >&2; exit 1; }
  sed -n "${h},${p}p" "$here/s1.sh" | awk -v n="$h" '{printf "  %d: %s\n", n + NR - 1, $0}'
  echo "## épingles lues dans s1.sh (non modifié) et golang des builds OBS (banc A2, archivé)"
  v=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$here/s1.sh")
  cle=$(sed -n 's|^CLE_ROCKY=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$here/s1.sh")
  fp=$(sed -n 's/^FP_ROCKY=\([0-9A-F]\{40\}\)\([[:space:]].*\)\{0,1\}$/\1/p' "$here/s1.sh")
  o=$(sed -n 's/^  <bdep name="golang" version="\([0-9.]*\)" release="\([0-9A-Za-z._]*\)" arch="x86_64" .* project="Rocky:9\.7" repository="appstream"\/>$/\1-\2/p' \
    "$here/../../benchmarks/obs/resultats/build-1/rocky_9/_buildenv")
  for u in "VAULT97:$v" "CLE_ROCKY:$cle" "FP_ROCKY:$fp" "golang de build-1/rocky_9/_buildenv:$o"; do
    p=$(printf '%s' "${u#*:}" | grep -c . || true)
    [ "$p" = 1 ] && echo "OK   ${u%%:*} : ${u#*:}" \
      || { echo "KO   ${u%%:*} : $p ligne(s) reconnue(s) (attendu : 1)" >&2; exit 1; }
  done
  echo "## copie de comparaison : Go épinglé par mise.toml"
  g=$(go env GOROOT)
  echo "$(go version) ; LICENSE sha256 $(sha256sum < "$g/LICENSE" | cut -c1-64) ; PATENTS sha256 $(sha256sum < "$g/PATENTS" | cut -c1-64)"
  rm -rf -- "${d:?}"; mkdir -p "$d"; mkdir -m 700 "$d/gnupg"; export GNUPGHOME=$d/gnupg
  echo "## clé de Rocky (trousseau temporaire)"
  h=$(lire_r7 RPM-GPG-KEY-Rocky-9 "$cle") || exit 1
  [ "$h" = 200 ] || { echo "KO   $cle : HTTP $h" >&2; exit 1; }
  s=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}' || true)
  [ "$s" = "$fp" ] && echo "OK   empreinte de la clé de Rocky : $s" \
    || { echo "KO   empreinte de la clé de Rocky : « $s » (attendu : $fp)" >&2; exit 1; }
  gpg --batch --quiet --no-default-keyring --keyring "$d/cles.gpg" --import "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null \
    || { echo "KO   clé de Rocky non importée" >&2; exit 1; }
  echo "## AppStream de vault 9.7, épinglé par s1.sh"
  depot_r7 vault-AppStream "$v/AppStream/x86_64/os" || { echo "KO   vault-AppStream absent" >&2; exit 1; }
  cp "$d/vault-AppStream.repomd.xml" "$d/temoin.xml"; echo x >> "$d/temoin.xml"
  s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/vault-AppStream.repomd.xml.asc" "$d/temoin.xml" 2>/dev/null | awk '$2 == "VALIDSIG"' || true)
  [ -z "$s" ] && echo "OK   témoin altéré (repomd.xml de vault-AppStream plus une ligne) refusé" \
    || { echo "KO   témoin altéré accepté" >&2; exit 1; }
  echo "## entrée du rpm golang 0:$o.x86_64 dans le primary signé"
  p=$(python3 -I - "$d" "$o" "$b9" <<'PY'
import bz2, glob, gzip, lzma, re, sys, xml.etree.ElementTree as E
d, o, borne = sys.argv[1], sys.argv[2], int(sys.argv[3])
C = '{http://linux.duke.edu/metadata/common}'; R = '{http://linux.duke.edu/metadata/rpm}'
src = glob.glob(d + '/vault-AppStream.primary.xml.*')
if len(src) != 1:
    sys.exit(f"{len(src)} primary sur disque (attendu : 1)")
ver, rel = o.rsplit('-', 1)
t = []
with {'gz': gzip.open, 'xz': lzma.open, 'bz2': bz2.open}[src[0].rsplit('.', 1)[1]](src[0]) as f:
    for _, p in E.iterparse(f):
        if p.tag != C + 'package':
            continue
        v = p.find(C + 'version')
        if (p.get('type') == 'rpm' and p.findtext(C + 'name') == 'golang' and p.findtext(C + 'arch') == 'x86_64'
                and (v.get('epoch') or '0') == '0' and v.get('ver') == ver and v.get('rel') == rel):
            c, l, z = p.find(C + 'checksum'), p.find(C + 'location'), p.find(C + 'size')
            t.append((c.get('type') if c is not None else None, (c.text or '').strip() if c is not None else '',
                      l.get('href') if l is not None else None, l.get('{http://www.w3.org/XML/1998/namespace}base') if l is not None else None,
                      l.get('base') if l is not None else None, z.get('package') if z is not None else None,
                      (p.findtext(f'{C}format/{R}license') or '').strip()))
        p.clear()
if len(t) != 1:
    sys.exit(f"{len(t)} entrée(s) golang 0:{o}.x86_64 dans le primary (attendu : 1)")
typ, sha, href, b1, b2, taille, lic = t[0]
if typ != 'sha256' or not re.fullmatch(r'[0-9a-f]{64}', sha):
    sys.exit(f"somme du paquet absente ou mal formée : {typ} {sha}")
if b1 is not None or b2 is not None:
    sys.exit(f"location avec base refusée : {b1 or b2}")
if not href or not re.fullmatch(r'[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*\.rpm', href) or any(s in ('.', '..') for s in href.split('/')):
    sys.exit(f"emplacement du paquet refusé : {href}")
if not (taille or '').isdigit() or not 0 < int(taille) <= borne:
    sys.exit(f"taille du paquet hors borne : {taille} (borne : {borne} octets)")
if not lic or '\t' in lic:
    sys.exit("License: absente du primary")
print(f"{sha}\t{href}\t{taille}\t{lic}")
PY
  ) || { echo "KO   entrée du rpm golang refusée" >&2; exit 1; }
  IFS=$'\t' read -r s h u g <<< "$p"
  echo "primary : golang 0:$o.x86_64 ; sha256 $s ; $h ; $u octets (borne : $b9) ; License: $g"
  printf 'golang\t0:%s.x86_64\n' "$o" > "$d/vault-AppStream.golang"
  fichiers_r8 vault-AppStream "$v/AppStream/x86_64/os"
  echo "## rpm golang (téléchargé entier, somme du primary exigée ; jamais installé, jamais exécuté)"
  p=$(lire_r7 golang.rpm "$v/AppStream/x86_64/os/$h") || exit 1
  [ "$p" = 200 ] || { echo "KO   HTTP $p sur $v/AppStream/x86_64/os/$h" >&2; exit 1; }
  [ "$(stat -c %s "$d/golang.rpm")" = "$u" ] || { echo "KO   taille du rpm $(stat -c %s "$d/golang.rpm") (primary : $u)" >&2; exit 1; }
  [ "$(sha256sum < "$d/golang.rpm" | cut -c1-64)" = "$s" ] && echo "OK   rpm conforme au primary : $u octets, sha256 $s" \
    || { echo "KO   sha256 du rpm différent du primary ($s)" >&2; exit 1; }
  python3 -I - "$d/golang.rpm" "$d/vault-AppStream.fichiers" "golang 0:$o.x86_64" "$g" "$(go env GOROOT)" "$d" "$fp" <<'PY' || { echo "KO   en-tête du rpm" >&2; exit 1; }
import hashlib, lzma, os, re, stat, struct, subprocess, sys
rpm, fic, attendu, lic_primary, goroot, d, fp = sys.argv[1:8]   # lecteur repris tel quel par resultats/m2-releve9-temoins.sh
b = open(rpm, 'rb').read()
def ko(m):
    sys.exit(m)
# Structure et numéros de tags écrits de mémoire (format rpm v3/v4) : éprouvés par les contrôles croisés ci-dessous.
if b[:4] != b'\xed\xab\xee\xdb':
    ko("magie du lead absente")
def entete(off, nom):
    if b[off:off + 4] != b'\x8e\xad\xe8\x01':
        ko(f"magie de l'en-tête {nom} absente (octet {off})")
    if len(b) < off + 16:
        ko(f"en-tête {nom} tronqué")
    il, dl = struct.unpack('>II', b[off + 8:off + 16])
    if il > 65536 or dl > 256 * 1024 * 1024:
        ko(f"en-tête {nom} : {il} entrées, {dl} octets de données, hors borne")
    st = off + 16 + 16 * il
    fin = st + dl
    if fin > len(b):
        ko(f"en-tête {nom} tronqué ({fin} > {len(b)})")
    idx = {}
    for i in range(il):
        tag, typ, ofs, cnt = struct.unpack('>IIII', b[off + 16 + 16 * i:off + 32 + 16 * i])
        if ofs >= dl and cnt:
            ko(f"en-tête {nom} : tag {tag} hors des données")
        idx[tag] = (typ, ofs, cnt)
    return idx, b[st:fin], off, fin
def val(h, tag):
    idx, data = h[0], h[1]
    if tag not in idx:
        return None
    typ, ofs, cnt = idx[tag]
    if typ in (6, 8, 9):
        r, p = [], ofs
        for _ in range(1 if typ == 6 else cnt):
            e = data.find(b'\0', p)
            if e < 0:
                ko(f"tag {tag} : chaîne non terminée")
            r.append(data[p:e].decode('utf-8', 'replace')); p = e + 1
        return r[0] if typ == 6 else r
    w = {2: ('B', 1), 1: ('B', 1), 3: ('H', 2), 4: ('I', 4), 5: ('Q', 8)}.get(typ)
    if w:
        if ofs + w[1] * cnt > len(data):
            ko(f"tag {tag} : tableau hors des données")
        return list(struct.unpack(f'>{cnt}{w[0]}', data[ofs:ofs + w[1] * cnt]))
    if typ == 7:
        return data[ofs:ofs + cnt]
    ko(f"tag {tag} : type {typ} inconnu")
sig = entete(96, 'de signature')
m0 = (sig[3] + 7) // 8 * 8
hdr = entete(m0, 'principal')
charge = b[hdr[3]:]
print(f"lead 96 octets ; signature : {len(sig[0])} tags, fin à l'octet {sig[3]} ; en-tête principal : {len(hdr[0])} tags, "
      f"octets {m0} à {hdr[3]} ; charge : {len(charge)} octets")
x = val(sig, 273)
if x is None:
    print("signature, tag 273 (SHA256 de l'en-tête) : absent, non éprouvé")
elif x == hashlib.sha256(b[m0:hdr[3]]).hexdigest():
    print("OK   signature, tag 273 : sha256 de l'en-tête principal égal")
else:
    ko(f"signature, tag 273 : {x} différent du sha256 de l'en-tête principal")
x, alg = val(hdr, 5092), val(hdr, 5093)
if x is None:
    print("tag 5092 (empreinte de la charge) : absent, non éprouvé")
elif alg == [8] and hashlib.sha256(charge).hexdigest() in x:
    print("OK   tag 5092 : sha256 de la charge égal (algorithme 8)")
else:
    ko(f"tag 5092 : {x} (algorithme {alg}) ne correspond pas à la charge")
x = val(sig, 268)
if x is None:
    print("signature OpenPGP de l'en-tête (tag 268) : absente, non vérifiée")
else:
    def gpgv(f):
        r = subprocess.run(['gpgv', '--keyring', os.path.join(d, 'cles.gpg'), '--status-fd', '1', os.path.join(d, 'sig268.bin'), f],
                           capture_output=True, text=True)
        return [z.split()[-1] for z in r.stdout.splitlines() if z.split()[1:2] == ['VALIDSIG']]
    with open(os.path.join(d, 'sig268.bin'), 'wb') as f:
        f.write(x)
    with open(os.path.join(d, 'entete.bin'), 'wb') as f:
        f.write(b[m0:hdr[3]])
    with open(os.path.join(d, 'entete-temoin.bin'), 'wb') as f:
        f.write(b[m0:hdr[3]] + b'x')
    v = gpgv(os.path.join(d, 'entete.bin'))
    if v != [fp]:
        ko(f"signature OpenPGP de l'en-tête (tag 268) refusée : VALIDSIG {v} (attendu : {fp})")
    if gpgv(os.path.join(d, 'entete-temoin.bin')):
        ko("signature (tag 268) acceptée sur l'en-tête altéré")
    print(f"OK   signature OpenPGP de l'en-tête (tag 268) : VALIDSIG {v[0]} ; en-tête altéré refusé")
ep = val(hdr, 1003)
nevr = f"{val(hdr, 1000)} {ep[0] if ep else 0}:{val(hdr, 1001)}-{val(hdr, 1002)}.{val(hdr, 1022)}"
if nevr != attendu:
    ko(f"nom et EVR de l'en-tête : {nevr} (attendu : {attendu})")
print(f"OK   en-tête : {nevr}")
if val(hdr, 1014) != lic_primary:
    ko(f"License: de l'en-tête « {val(hdr, 1014)} » différente du primary « {lic_primary} »")
print(f"OK   License: de l'en-tête égale au primary : {lic_primary}")
print(f"sourcerpm : {val(hdr, 1044)} ; format de charge : {val(hdr, 1124)} ; compresseur : {val(hdr, 1125)} ; drapeaux : {val(hdr, 1126)}")
bn, dn, di = val(hdr, 1117), val(hdr, 1118), val(hdr, 1116)
modes, fl, dg = val(hdr, 1030), val(hdr, 1037), val(hdr, 1035)
tailles = val(hdr, 1028) or val(hdr, 5008)
if None in (bn, dn, di, modes, fl, dg, tailles):
    ko("tags de fichiers absents (1116, 1117, 1118, 1030, 1037, 1035, 1028 ou 5008)")
n = len(bn)
if not all(len(z) == n for z in (di, modes, fl, dg, tailles)) or max(di) >= len(dn):
    ko("tableaux de fichiers de longueurs différentes")
algo = val(hdr, 5011)
print(f"{n} entrées de fichiers ; algorithme des empreintes de fichiers (tag 5011) : {algo if algo else 'absent'}")
ch = [dn[di[i]] + bn[i] for i in range(n)]
reg = {ch[i] for i in range(n) if not stat.S_ISDIR(modes[i] & 0xFFFF)}
with open(fic, encoding='utf-8') as f:
    fl_set = {x.rstrip('\n').split('\t')[2] for x in f if x.strip()}
if reg != fl_set:
    ko(f"fichiers de l'en-tête ≠ filelists : {len(reg - fl_set)} en trop, {len(fl_set - reg)} manquants")
print(f"OK   {len(reg)} fichiers (dossiers exclus) égaux au filelists signé")
bits = {1: 'config', 2: 'doc', 4: 'icon', 8: 'missingok', 16: 'noreplace', 32: 'specfile', 64: 'ghost', 128: 'license',
        256: 'readme', 2048: 'pubkey', 4096: 'artifact'}   # table écrite de mémoire ; 2 et 128 éprouvés (m2-releve9-temoins.sh)
def lire(v):
    return '+'.join(nm for k, nm in bits.items() if v & k) or 'aucun'
par = {}
for i in range(n):
    par.setdefault(fl[i], []).append(i)
print("### drapeaux de fichiers (FILEFLAGS, tag 1037) ; bits 2 et 128 éprouvés, autres bits de mémoire")
for v_, l_ in sorted(par.items()):
    sd = sum(1 for i in l_ if ch[i].startswith('/usr/share/doc/'))
    print(f"  {v_} (0x{v_:x}, {lire(v_)}) : {len(l_)} entrées, dont {sd} sous /usr/share/doc/")
motif = re.compile(r'(LICEN[CS]E|COPYING|PATENTS|NOTICE)([._-][A-Za-z0-9._-]*)?')
ref = {}
for nm in ('LICENSE', 'PATENTS'):
    with open(os.path.join(goroot, nm), 'rb') as f:
        ref[nm] = hashlib.sha256(f.read()).hexdigest()
voulus = {}
print("### fichiers sous /usr/share/doc ou /usr/share/licenses, ou au nom de licence")
for i in range(n):
    if ch[i].startswith(('/usr/share/doc/', '/usr/share/licenses/')) or motif.fullmatch(bn[i]):
        cmp_ = ''
        if algo == [8] and bn[i] in ref:
            cmp_ = f" ; {'égale à' if dg[i] == ref[bn[i]] else 'différente de'} la copie de Go de mise.toml"
            voulus['.' + ch[i]] = (dg[i], bn[i])
        print(f"  {ch[i]} : drapeaux {fl[i]} (0x{fl[i]:x}, {lire(fl[i])}) ; mode {modes[i] & 0xFFFF:o} ; {tailles[i]} octets ; "
              f"empreinte {dg[i]}{cmp_}")
comp = val(hdr, 1125)
print(f"## charge ({val(hdr, 1124)}, {comp})")
if comp not in ('xz', 'lzma'):
    print(f"NON LUE : compresseur {comp}, aucun décompresseur sans installation ; texte non lu")
    sys.exit(0)
if not voulus:
    print("NON LUE : aucune empreinte sha256 de LICENSE ou PATENTS dans l'en-tête")
    sys.exit(0)
dec = lzma.LZMADecompressor(lzma.FORMAT_AUTO)
cp = dec.decompress(charge, max_length=512 * 1024 * 1024)
if not dec.eof:
    ko("charge non décompressée en entier (borne de 512 Mio)")
p, vus, k = 0, {}, 0
while True:
    if cp[p:p + 6] != b'070701':
        print(f"NON LUE : en-tête cpio inattendu à l'octet {p} : {cp[p:p + 6]!r}")
        sys.exit(0)
    f_ = [int(cp[p + 6 + 8 * j:p + 14 + 8 * j], 16) for j in range(13)]
    taille, ln = f_[6], f_[11]
    nom = cp[p + 110:p + 110 + ln - 1].decode('utf-8', 'replace')
    q = (p + 110 + ln + 3) // 4 * 4
    if nom == 'TRAILER!!!':
        break
    k += 1
    if nom in voulus:
        vus[nom] = cp[q:q + taille]
    p = (q + taille + 3) // 4 * 4
print(f"cpio : {k} entrées")
for nom, (e, court) in sorted(voulus.items()):
    t = vus.get(nom)
    if t is None:
        ko(f"{nom} absent de la charge")
    if hashlib.sha256(t).hexdigest() != e:
        ko(f"{nom} : sha256 de la charge différent de l'empreinte de l'en-tête")
    l_ = t.decode('utf-8', 'replace').splitlines()
    print(f"OK   {nom[1:]} : sha256 égal à l'en-tête ; {len(t)} octets ; {len(l_)} lignes")
    for z in l_[:200]:
        print(f"  | {z}")
PY
  gpgconf --kill all 2>/dev/null || true
  rm -rf -- "${d:?}"
  echo "fichiers effacés (clé, métadonnées, rpm)"
}

# Cœur de la voie 2, NON BRANCHÉ (voir l'en-tête) : ni étape, ni pod. Rien ici n'est appelé par lancer.
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }   # comme s1.sh
voie2_preparer() { # verrou dossier : liste.tsv et voie2.sh écrits dans dossier ; KO sur tout écart du verrou
  local v=$1 o=$2 b p a src dos
  b=$(sed -n 's/^BOOT_DIGEST=\(sha256:[0-9a-f]\{64\}\)[[:space:]].*/\1/p' "$here/s1.sh")
  p=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$here/s1.sh")
  a=$(sed -n 's|^DEPOT_AMONT=\([A-Za-z0-9/_.-]*\)$|\1|p' "$here/s1.sh")
  [ -n "$b" ] && [ -n "$p" ] && [ -n "$a" ] || { echo "KO   BOOT_DIGEST, VAULT97 ou DEPOT_AMONT introuvable dans s1.sh" >&2; exit 1; }
  mkdir -p "$o"
  attendu "version du verrou" "$(jq -r '.version' "$v")" 1.1.0
  attendu "pull_digest du verrou" "$(jq -r '.bootstrap.pull_digest // "absent"' "$v")" "$b"
  src=$(jq -r '.config.bootstrap_image // "absent"' "$v")
  attendu "bootstrap_image du verrou" "$src" "$REG/$a@$b"
  dos=${src%%:*}@$b   # split(':')[0] de mock, puis @pull_digest (config.py:846)
  jq -r '.buildroot.rpms[] | [.name, .version, .release, .arch, .sigmd5, .url] | map(if type == "string" then . else "" end) | @tsv' \
    "$v" > "$o/liste.tsv"
  awk -F '\t' -v p="$p" '
    function ko(m) { print "KO   ligne " NR " du verrou : " m > "/dev/stderr"; e = 1 }
    { n++; f = $6; sub(/.*\//, "", f) }
    NF != 6 || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" { ko("champ manquant"); next }
    length($5) != 32 || $5 ~ /[^0-9a-f]/ { ko("sigmd5 inattendu : " $5) }
    index($6, p "/BaseOS/x86_64/os/") != 1 && index($6, p "/AppStream/x86_64/os/") != 1 && index($6, p "/CRB/x86_64/os/") != 1 {
      ko("URL hors des dépôts épinglés : " $6) }
    $6 ~ /[^A-Za-z0-9:\/._+-]/ || index($6, "/../") || index($6, "/./") { ko("URL refusée (caractère ou segment . ou ..) : " $6) }
    f !~ /^[A-Za-z0-9._+-]+\.rpm$/ { ko("nom de fichier refusé : " f) }
    vu[f]++ { ko("nom de fichier en double : " f) }
    END { if (!n) { print "KO   aucun paquet dans le verrou" > "/dev/stderr"; e = 1 }; exit e }' "$o/liste.tsv" \
    || { echo "KO   verrou refusé (motifs ci-dessus)" >&2; exit 1; }
  echo "OK   verrou : $(wc -l < "$o/liste.tsv") paquets, tous sous $p (BaseOS, AppStream, CRB)"
  local x=${VOIE2//@SOURCE@/$src}; x=${x//@DOSSIER@/$dos}; printf '%s\n' "${x//@DIGEST@/$b}" > "$o/voie2.sh"
  echo "bootstrap : docker://$src vers dir:<dépôt>/$dos"
}

VOIE2='set -u
export LC_ALL=C
R=${VOIE2_RACINE:-/w}; D=$R/voie2/depot; B=$R/voie2/rpmdb; L=$R/voie2/liste.tsv; T=$(printf "\t")
ko() { echo "KO   $*"; exit 1; }
for o in curl rpm createrepo_c skopeo sha256sum; do command -v $o >/dev/null 2>&1 || ko "$o absent de l image"; done
rm -rf "${D:?}" "${B:?}"; mkdir -p "$D" "$B"
n=$(wc -l < "$L"); echo "paquets du verrou : $n"
t=$(date +%s)
while IFS="$T" read -r nom ver rel arch md5 url; do
  h=$(curl -sS --proto =https --max-time 120 -o "$D/${url##*/}" -w "%{http_code}" "$(printf %s "$url" | sed "s/+/%2B/g")") || ko "curl en échec : $url"
  [ "$h" = 200 ] || ko "HTTP $h : $url"
done < "$L"
c=$(find "$D" -maxdepth 1 -type f -name "*.rpm" | wc -l)
[ "$c" = "$n" ] || ko "$c fichiers téléchargés pour $n paquets"
echo "téléchargement : $c fichiers en $(($(date +%s) - t)) s"
rpm --dbpath "$B" --initdb </dev/null || ko "rpmdb vide non créée"
rpm --dbpath "$B" --import "$R/cles/RPM-GPG-KEY-Rocky-9" </dev/null || ko "clé de Rocky non importée"
rpm --dbpath "$B" -K "$D"/*.rpm > "$R/voie2/k.log" 2>&1 </dev/null; r=$?
k=$(grep -c -E "digests signatures OK$" "$R/voie2/k.log")
echo "rpm -K : rc $r, $k OK sur $n"
grep -v -E "digests signatures OK$" "$R/voie2/k.log" | head -n 5
[ "$r" = 0 ] && [ "$k" = "$n" ] || ko "signatures des rpm"
while IFS="$T" read -r nom ver rel arch md5 url; do
  q=$(rpm --dbpath "$B" -qp --qf "%{NAME}$T%{VERSION}$T%{RELEASE}$T%{ARCH}$T%{SIGMD5}" "$D/${url##*/}" 2>/dev/null </dev/null)
  [ "$q" = "$nom$T$ver$T$rel$T$arch$T$md5" ] || ko "en-tête de ${url##*/} différent du verrou"
done < "$L"
echo "OK   nom, version, release, arch et sigmd5 des $n rpm égaux au verrou"
t=$(date +%s); createrepo_c --compatibility "$D" > "$R/voie2/createrepo.log" 2>&1 </dev/null; r=$?
echo "createrepo_c --compatibility : rc $r en $(($(date +%s) - t)) s"
[ "$r" = 0 ] || { tail -n 5 "$R/voie2/createrepo.log"; ko "createrepo_c"; }
[ -s "$D/repodata/repomd.xml" ] || ko "repodata/repomd.xml absent"
echo "repomd.xml : sha256 $(sha256sum < "$D/repodata/repomd.xml" | cut -c1-64)"
t=$(date +%s); skopeo copy --preserve-digests "docker://@SOURCE@" "dir:$D/@DOSSIER@" > "$R/voie2/skopeo.log" 2>&1 </dev/null; r=$?
echo "skopeo copy --preserve-digests : rc $r en $(($(date +%s) - t)) s"
[ "$r" = 0 ] || { tail -n 5 "$R/voie2/skopeo.log"; ko "skopeo copy"; }
m=sha256:$(sha256sum < "$D/@DOSSIER@/manifest.json" | cut -c1-64)
[ "$m" = "@DIGEST@" ] || ko "manifeste copié $m, attendu @DIGEST@"
echo "OK   manifeste copié : $m"
'

lancer m2 "05 M2" "$@"
