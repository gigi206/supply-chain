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
