#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b : référence du bootstrap refaite avec le tar de l'amorce ed654c69 (tar 1.34), qui archivera dans la tâche, au lieu
# du tar 1.35 de l'hôte qui a écrit f2652169 (m1b-boot-0555.sh). Même méthode que m1b-tar-amorce.sh pour l'outillage : les copies
# b1 et b2 en 0555 du banc du 19/11 (08:40:18 UTC) sont ré-archivées par le tar de l'amorce, dans la racine d'outils du banc de
# l'amorce (chroot, umask 022), avec les options, la borne S et les exclusions de m1b-boot-0555.sh. Chaque copie est montée en
# lecture seule sur /mnt de la racine d'outils (dossier vide), dans un espace de montage à part : ni les copies ni la racine
# d'outils ne sont modifiées. Hors ligne, rien n'est installé. Prédictions BA1 à BA5 dans m1b-predictions.md, écrites avant le
# lancement. Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-boot-amorce.sh > poc/bricks/05-rpm-mock/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
B=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z   # racine d'outils du banc de l'amorce : lecture seule
X=$HOME/.cache/supply-chain-poc/05/m1b-boot-0555-20261119T084018Z      # copies b1, b2 en 0555 et y1.tar : lecture seule
F=f265216965e3e4723dfeb8931469cb9e57335e231ecfa4b7dc9151ba40545ee7     # référence du 19/11, tar de l'hôte (BR7)
S=1766985142                                                           # S du bootstrap (m1b-boot-0555.sh)
U=$(date -u +%Y%m%dT%H%M%SZ)
N=$HOME/.cache/supply-chain-poc/05/m1b-boot-amorce-$U                   # dossier neuf, jamais effacé ni réutilisé
ns() { unshare --map-auto --map-root-user -n "$@"; }
# chroot dans la racine d'outils, umask 022, la copie $1 montée en lecture seule sur /mnt
qm() { local c=$1; shift; ns -m -p --fork bash -c 'umask 022; o=$1; c=$2; shift 2
  mount --rbind /dev "$o/dev" && mount -t proc proc "$o/proc" && mount --bind "$c" "$o/mnt" && mount -o remount,bind,ro "$o/mnt" || exit 97
  export HOME=/root; exec chroot "$o" "$@"' _ "$B/outils" "$c" "$@"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echo "# m1b-boot-amorce.sh, début $(date -u +%FT%TZ) ; dossier $N"
[ ! -e "$N" ] || { echo "KO   dossier déjà présent : $N" >&2; exit 1; }
mkdir -p "$N"
attendu "y1.tar du 19/11 (référence du bootstrap, tar de l'hôte)" "$(sha256sum < "$X/archives/y1.tar" | cut -c1-64)" "$F"
echo "avant : /mnt de la racine d'outils $(stat -c %a "$B/outils/mnt"), $(ls -A "$B/outils/mnt" | wc -l) entrée(s) ; racines des copies : b1 $(stat -c %a "$X/copies/b1"), b2 $(stat -c %a "$X/copies/b2")"
echo "tar de l'hôte : $(tar --version | head -1)"
echo "tar de l'amorce : $(qm "$X/copies/b1" tar --version | head -1) ; paquet $(qm "$X/copies/b1" rpm -q tar)"
echo "témoin : racine vue sous /mnt dans le chroot : $(qm "$X/copies/b1" stat -c %a /mnt) ; écriture refusée : $(qm "$X/copies/b1" bash -c 'touch /mnt/.essai 2>/dev/null && echo non || echo oui')"
for b in b1 b2; do
  echo "## ré-archivage de la copie $b par le tar de l'amorce (BA1, BA2)"
  rc=0
  qm "$X/copies/$b" tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
    --xattrs --xattrs-include='*' --numeric-owner \
    --exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log \
    --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal \
    --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id \
    -C /mnt -cf - . > "$N/z-$b.tar" 2> "$N/z-$b.err" || rc=$?
  echo "tar de l'amorce ($b) : code $rc ; stderr $(wc -l < "$N/z-$b.err") lignes"
  head -3 "$N/z-$b.err" | sed 's/^/   stderr : /'
  echo "z-$b.tar : $(stat -c %s "$N/z-$b.tar") octets, $(tar -tf "$N/z-$b.tar" | wc -l) membres, sha256 $(sha256sum < "$N/z-$b.tar" | cut -c1-64)"
done
z1=$(sha256sum < "$N/z-b1.tar" | cut -c1-64)
[ "$z1" = "$F" ] && echo "OK   z-b1.tar = f2652169 octet pour octet" || echo "ÉCART z-b1.tar différent de f2652169"
cmp -s "$N/z-b1.tar" "$N/z-b2.tar" && echo "OK   z-b1.tar et z-b2.tar identiques octet à octet (BA4)" || echo "ÉCART z-b1.tar et z-b2.tar différents"
echo "## comparaison membre à membre contre y1.tar (BA3)"
python3 -I "$r/m1b-repro2-comparer.py" "$X/archives/y1.tar" "$N/z-b1.tar" 2>&1 | tail -n 12 | sed 's/^/   comparer : /'
echo "## en-têtes d'en-tête ustar : devmajor et devminor (BA2)"
python3 -I - "$X/archives/y1.tar" "$N/z-b1.tar" <<'PY'
import sys
from collections import Counter
def champs(p):
    c = Counter()
    with open(p, 'rb') as f:
        while True:
            h = f.read(512)
            if len(h) < 512 or h == b'\0' * 512:
                break
            taille = int(h[124:136].rstrip(b'\0 ').decode() or '0', 8)
            c[(h[329:337], h[337:345])] += 1
            f.seek(((taille + 511) // 512) * 512, 1)
    return c
for n, p in (('y1.tar', sys.argv[1]), ('z-b1.tar', sys.argv[2])):
    print(f'{n} : ' + ' ; '.join(f'devmajor {a!r} devminor {b!r} : {k} en-têtes' for (a, b), k in sorted(champs(p).items())))
PY
echo "après : /mnt de la racine d'outils $(stat -c %a "$B/outils/mnt"), $(ls -A "$B/outils/mnt" | wc -l) entrée(s) ; racines des copies : b1 $(stat -c %a "$X/copies/b1"), b2 $(stat -c %a "$X/copies/b2")"
echo "# fin $(date -u +%FT%TZ)"
