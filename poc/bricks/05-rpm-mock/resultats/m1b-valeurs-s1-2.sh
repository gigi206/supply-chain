#!/usr/bin/env bash
# Brique 05, M1b : second relevé en lecture seule (19/11/2026), complément de m1b-valeurs-s1.sh. Mode du membre « . » dans les
# archives des quatre références du 18/11 (a8, b5, a3, x1, sha256 contrôlés), etc/machine-id dans la couche amont 812c4412 (base
# du bootstrap ; taille et mode, contenu jamais lu), et mode que le paquet filesystem donne à « / ». Aucune archive n'est écrite.
# Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-valeurs-s1-2.sh > poc/bricks/05-rpm-mock/resultats/m1b-valeurs-s1-2.log 2>&1
set -euo pipefail
export LC_ALL=C
B=$HOME/.cache/supply-chain-poc/05
L=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256/812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09
F=$B/m1b-outil-amorce-20261118T212517Z/outils/m/rpms/filesystem-3.16-5.el9.x86_64.rpm
echo "# m1b-valeurs-s1-2.sh, début $(date -u +%FT%TZ)"
a=()
for x in "a8 $B/m1b-outil-amorce-20261118T212517Z/archives/a8.tar 06c289ad" \
         "b5 $B/m1b-sans-machine-id-20261118T210852Z/b5.tar 05d35d64" \
         "a3 $B/m1b-repro3-20261118T201556Z/archives/a3.tar 0c00666a" \
         "x1 $B/m1b-boot-20261118T214226Z/archives/x1.tar 28634a12" \
         "couche-812c4412 $L 812c4412"; do
  set -- $x
  s=$(sha256sum < "$2" | cut -c1-64)
  [ "${s:0:8}" = "$3" ] && echo "OK   $1 : sha256 $s (référence $3…)" || { echo "KO   $1 : sha256 $s (attendu $3…)" >&2; exit 1; }
  a+=("$1=$2")
done
python3 -I - "${a[@]}" <<'PY'
import sys, tarfile
for x in sys.argv[1:]:
    nom, p = x.split('=', 1)
    with tarfile.open(p, 'r:*') as t:
        membres = t.getmembers()
    racine = [m for m in membres if m.name in ('.', './', '')]
    mid = [m for m in membres if m.name.lstrip('./') == 'etc/machine-id']
    print(f'{nom} : {len(membres)} membres ; membre racine : '
          + (', '.join(f'{m.name!r} mode {oct(m.mode)}' for m in racine) or 'aucun')
          + ' ; etc/machine-id : '
          + (', '.join(f'{m.size} octet(s), mode {oct(m.mode)}' for m in mid) or 'absent'))
PY
echo "## paquet filesystem : $(basename "$F"), sha256 $(sha256sum < "$F" | cut -c1-64)"
echo "rpm -K : $(rpm -K --nosignature "$F" 2>&1 | sed 's/^.*: //')"
rpm -qp --nosignature --qf '[%{FILEMODES:perms} %{FILEUSERNAME}:%{FILEGROUPNAME} %{FILENAMES}\n]' "$F" 2>/dev/null | awk '$3=="/"{print "entrée « / » : " $0; n++} END{print "entrées « / » : " n+0}'
echo "# fin $(date -u +%FT%TZ)"
