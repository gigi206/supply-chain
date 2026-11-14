#!/usr/bin/env bash
# Banc hors réseau (brique 13a, point X11 de lies). Lit le deb de S3 de la 06 (sha256 épinglé, même valeur que DEB_SHA de
# paquets.sh) et cherche, dans la table des lignes du binaire sample-app, les noms de fichiers source des neuf motifs qui gardent
# le paragraphe X11 (paquets-lies.log), plus deux témoins. Ne modifie rien ; rien sur le réseau.
# Usage : bash poc/bricks/13a-licences/resultats/x11-fichiers.sh > poc/bricks/13a-licences/resultats/x11-fichiers.log
set -uo pipefail
export LC_ALL=C
ici=$(cd "$(dirname "$0")" && pwd)
DEB=${DEB:-$HOME/.cache/supply-chain-poc/08/travail/s3-06/build-1/sample-app_1.0.0-1_amd64.deb}
DEB_SHA=0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5
echo "# x11-fichiers.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), x11-fichiers.py $(sha256sum < "$ici/x11-fichiers.py" | cut -c1-64), $(python3 -I -c 'import sys; print(sys.version.split()[0])')"
test -f "$DEB" || { echo "KO   deb absent"; exit 1; }
rc=0
python3 -I "$ici/x11-fichiers.py" "$DEB" "$DEB_SHA" || rc=$?
echo "# code $rc, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
exit "$rc"
