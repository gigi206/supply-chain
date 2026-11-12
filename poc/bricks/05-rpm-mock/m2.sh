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
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/05-rpm-mock/m2.sh releve   (journal : resultats/m2-releve.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve2  (journal : resultats/m2-releve2.log)
#                          mise exec -- poc/bricks/05-rpm-mock/m2.sh releve3  (journal : resultats/m2-releve3.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
MOCK_TAG=mock-6.9-1
ARCHIVE_SHA=3c034916a721bb06b923399c856d5111fbf3d791804934dd6d909e3d292e4d88   # relevé le 12/11/2026 à 14:41:49 UTC (m2-releve.log)
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
  lignes "bootstrap_image_assert_digest, dans tout le code Python" 'bootstrap_image_assert_digest' mock/py
  lignes "images dir: et oci-archive:, dans tout le code Python" 'dir:|oci-archive' mock/py
  lignes "bootstrap_image_fallback et bootstrap_image_skip_pull" 'bootstrap_image_(fallback|skip_pull)' mock/py
  echo "## coupures de références d'image"
  lignes "split(':') et split(\":\"), dans tout le code Python" "split\\(['\"]:['\"]" mock/py
  echo "## mode hermétique : tous les usages"
  lignes "hermetic_build et offline_local_repository" 'hermetic_build|offline_local_repository' mock/py
  rm -rf -- "${T:?}/mock-src"
  echo "sources effacées ; archive gardée sous ~/.cache"
}

lancer m2 "05 M2" "$@"
