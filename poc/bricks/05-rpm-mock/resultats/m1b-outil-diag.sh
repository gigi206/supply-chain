#!/usr/bin/env bash
# Brique 05, M1b, banc de l'outillage : diagnostic de l'échec du premier passage (18/11/2026, 20:55:47 UTC) :
# « repomd.xml GPG signature verification error: gpgme_engine_check_version() error: Invalid crypto engine ».
# Hypothèse : la racine d'outils n'a ni /dev (exclu à l'extraction des couches) ni /proc, et gpgme ne trouve pas gpg.
# Lecture seule sur la racine d'outils du premier passage ; hors ligne (unshare -n) ; rien n'est installé.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-outil-diag.sh > poc/bricks/05-rpm-mock/resultats/m1b-outil-diag.log 2>&1
set -uo pipefail
export LC_ALL=C
O=$HOME/.cache/supply-chain-poc/05/m1b-outil-20261118T205447Z/outils
echo "# m1b-outil-diag.sh, début $(date -u +%FT%TZ)"
echo "/dev de la racine : $(find "$O/dev" -mindepth 1 2>/dev/null | wc -l) entrée(s) ; /proc : $(find "$O/proc" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l) entrée(s)"
echo "## A. sans /dev ni /proc (forme du premier passage)"
unshare --map-auto --map-root-user -n chroot "$O" /usr/bin/gpgconf --list-dirs homedir 2>&1 | head -n 3; echo "code ${PIPESTATUS[0]}"
unshare --map-auto --map-root-user -n chroot "$O" /usr/bin/python3 -c 'import gpg; print(gpg.core.check_version())' 2>&1 | tail -n 2
echo "## B. avec /dev lié et /proc monté (espace de montage propre)"
unshare --map-auto --map-root-user -n -m -p --fork bash -c '
  mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || { echo "montage : code $?"; exit 1; }
  chroot "$1" /usr/bin/gpgconf --list-dirs homedir 2>&1 | head -n 3; echo "code ${PIPESTATUS[0]}"
  chroot "$1" /usr/bin/python3 -c "import gpg; print(gpg.core.check_version())" 2>&1 | tail -n 2
  chroot "$1" /usr/bin/python3 -c "import gpg; c = gpg.Context(); print(\"moteur :\", c.engine_info.file_name, c.engine_info.version)" 2>&1 | tail -n 2
' _ "$O"
echo "montages laissés sur la racine après sortie : $(grep -c " $O/" /proc/self/mounts || true)"
echo "# fin $(date -u +%FT%TZ)"
