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
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/05-rpm-mock/m2.sh releve   (journal : resultats/m2-releve.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve2  (journal : resultats/m2-releve2.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve3  (journal : resultats/m2-releve3.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve4  (journal : resultats/m2-releve4.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve5  (journal : resultats/m2-releve5.log)
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
