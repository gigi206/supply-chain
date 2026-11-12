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
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/05-rpm-mock/m2.sh releve   (journal : resultats/m2-releve.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
MOCK_TAG=mock-6.9-1
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

lancer m2 "05 M2" "$@"
