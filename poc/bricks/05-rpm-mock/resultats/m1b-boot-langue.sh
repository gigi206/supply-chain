#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b : langue du bootstrap, séparée des outils (19/11/2026). La référence du bootstrap b063feb3 a été installée par les
# outils de a8 (%_install_langs all, libsolv 0.7.24-6) ; la tâche tournerait sur l'amorce ed654c69 (en_US, libsolv 0.7.24-4). Banc
# de l'hôte, hors réseau, sans rien installer sur l'hôte : la racine d'outils de l'amorce (banc du 18/11, lecture seule) installe
# deux fois la base rockylinux:9.7 plus les dix lignes, avec la sonde prévue pour le pod :
#   - extraction de la couche 812c4412 par le tar de l'amorce (pas de podman) ; racine de l'arbre passée en 0555 avant l'archive ;
#   - dnf-3 sous env -i, la limite de fichiers ouverts à 1024 (souple puis dure) dans un sous-shell qui n'entoure que dnf
#     (forme décidée, « Limite seule ») ; umask 022 ; SOURCE_DATE_EPOCH=S ; container=oci ;
#   - en : HOME=/root, macro de l'amorce telle quelle ; all : HOME=/m/h, où /m/h/.rpmmacros pose %_install_langs all ;
#   - archive par le tar de l'amorce, options, borne S et exclusions de m1b-boot-amorce.sh.
# Montages, dans un espace de noms à part : un dossier neuf sur /m de la racine d'outils (le /m du banc de l'amorce est masqué, non
# modifié) ; le miroir du banc du bootstrap du 18/11 en lecture seule sur /m/miroir. Prédictions LG0 à LG6 dans m1b-predictions.md,
# écrites avant le lancement. Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-boot-langue.sh > poc/bricks/05-rpm-mock/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
B=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/outils   # racine d'outils de l'amorce : lecture seule
X=$HOME/.cache/supply-chain-poc/05/m1b-boot-20261118T214226Z/outils/m         # banc du bootstrap du 18/11 : lecture seule
Y=$HOME/.cache/supply-chain-poc/05/m1b-boot-amorce-20261119T124518Z            # z-b1.tar (b063feb3) : lecture seule
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256
L=812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09                # couche de ee90dc0e
Z=b063feb3206deb3f1c0ad4eb7b497d683693967d194c7fdd366a2b0094823348                # référence du bootstrap, langues all, tar 1.34
CONF=7f49d5d39d0f1b1b232482a2b9e416c235ece7885a6858256bae0a2692e9f5ef             # dnf97.conf du 18/11 (m1b-boot.log)
S=1766985142
U=$(date -u +%Y%m%dT%H%M%SZ)
N=$HOME/.cache/supply-chain-poc/05/m1b-boot-langue-$U                           # dossier neuf, jamais effacé ni réutilisé
ns() { unshare --map-auto --map-root-user -n "$@"; }
q() { ns -m -p --fork bash -c 'umask 022; o=$1; n=$2; x=$3; shift 3
  mount --rbind /dev "$o/dev" && mount -t proc proc "$o/proc" && mount --bind "$n" "$o/m" \
    && mount --bind "$x/miroir" "$o/m/miroir" && mount -o remount,bind,ro "$o/m/miroir" || exit 97
  export HOME=/root; exec chroot "$o" "$@"' _ "$B" "$N" "$X" "$@"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echo "# m1b-boot-langue.sh, début $(date -u +%FT%TZ) ; dossier $N"
[ ! -e "$N" ] || { echo "KO   dossier déjà présent : $N" >&2; exit 1; }
l=$(df -k --output=avail "$HOME" | tail -1)
echo "place libre sous \$HOME avant : $l kB"
[ "$l" -ge 1500000 ] || { echo "KO   moins de 1,5 Go libres : arrêt, rien n'est effacé" >&2; exit 1; }
attendu "z-b1.tar du 19/11" "$(sha256sum < "$Y/z-b1.tar" | cut -c1-64)" "$Z"
attendu "dnf97.conf du 18/11" "$(sha256sum < "$X/dnf97.conf" | cut -c1-64)" "$CONF"
attendu "couche $L" "$(sha256sum < "$O/$L" | cut -c1-64)" "$L"
nb_m=$(ls -A "$B/m" | wc -l); echo "avant : /m de la racine d'outils $nb_m entrée(s), /mnt $(ls -A "$B/mnt" | wc -l)"
mkdir -p "$N/miroir" "$N/aucun" "$N/h" "$N/cles"
cp "$X/dnf97.conf" "$N/dnf97.conf"; cp "$X/cles/RPM-GPG-KEY-Rocky-9" "$N/cles/"; cp "$O/$L" "$N/couche.tar.gz"
printf '%%_install_langs all\n' > "$N/h/.rpmmacros"
p=$(sed -n 's/^paquets demandés : //p' "$r/s1-boot_racine.log"); echo "paquets demandés : $p"
sed -n 's/^     racine dérivée, liste : //p' "$r/s1-boot_racine.log" | sort > "$N/s1-apres.txt"
echo "liste rpm -qa de S1 après : $(wc -l < "$N/s1-apres.txt") lignes"
echo "## LG0 : outils et témoins dans la racine d'outils"
q bash -c 'rpm -q --qf "%{NEVRA}\n" rpm python3-dnf libsolv libdnf tar dnf' | sed 's/^/     /'
echo "     /m/miroir en lecture seule : $(q bash -c 'touch /m/miroir/.essai 2>/dev/null && echo non || echo oui')"
for H in /root /m/h; do
  echo "     %_install_langs lu par rpm de python, env -i HOME=$H : [$(q env -i PATH=/usr/sbin:/usr/bin HOME=$H LC_ALL=C python3 -c 'import rpm; print(rpm.expandMacro("%_install_langs"))')]"
done
Q='%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE} sigpgp=%{SIGPGP:pgpsig} rsaheader=%{RSAHEADER:pgpsig}\n'
for x in en all; do
  [ "$x" = en ] && H=/root || H=/m/h
  echo "## installation $x (HOME=$H), début $(date -u +%FT%TZ)"
  q bash -c 'set -u; x=$1; H=$2; S=$3; p=$4; Q=$5; cd /; umask 022
mkdir /m/b-$x && tar -xzf /m/couche.tar.gz -C /m/b-$x --numeric-owner --xattrs --xattrs-include="*" 2> /m/ext-$x.err; echo "extraction par le tar de l amorce : code $? ; stderr $(wc -l < /m/ext-$x.err) lignes ; racine $(stat -c %a /m/b-$x)"
rpm --root /m/b-$x -qa --qf "$Q" 2>/dev/null | sort > /m/avant-$x.txt; echo "avant : rpm -qa $(wc -l < /m/avant-$x.txt) lignes"
t=$(date +%s)
( ulimit -Sn 1024 && ulimit -Hn 1024 || exit 97; echo "$(ulimit -Sn) / $(ulimit -Hn)" > /m/lim-$x.txt
  exec env -i PATH=/usr/sbin:/usr/bin HOME=$H LC_ALL=C container=oci SOURCE_DATE_EPOCH=$S /usr/bin/dnf-3 -y -c /m/dnf97.conf \
    --setopt=reposdir=/m/aucun --setopt=cachedir=/m/cache-$x --installroot=/m/b-$x --releasever=9 install $p ) > /m/dnf-$x.log 2>&1
r=$?; echo "limite de fichiers ouverts dans le sous-shell de dnf : $(cat /m/lim-$x.txt 2>/dev/null) ; limite du shell après : $(ulimit -Sn) / $(ulimit -Hn)"
echo "dnf-3 code $r en $(($(date +%s) - t)) s ; $(wc -l < /m/dnf-$x.log) lignes de journal"
[ $r = 0 ] || { tail -n 15 /m/dnf-$x.log; exit 1; }
grep -E "^(Install|Upgrade|Remove|Downgrade|Reinstall|Skip) +[0-9]+ Package" /m/dnf-$x.log | sed "s/^/résumé de la transaction : /"
rpm --root /m/b-$x -qa --qf "$Q" 2>/dev/null | sort > /m/apres-$x.txt
cmp -s /m/apres-$x.txt /m/s1-apres.txt && echo "OK   liste rpm -qa après ($(wc -l < /m/apres-$x.txt) lignes) = celle de S1" || echo "ÉCART liste rpm -qa après différente de celle de S1"
chmod 0555 /m/b-$x; echo "racine passée en $(stat -c %a /m/b-$x) ; etc/machine-id : $(stat -c "%s octet(s)" /m/b-$x/etc/machine-id 2>/dev/null || echo absent)"
tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
  --xattrs --xattrs-include="*" --numeric-owner \
  --exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log \
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal \
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id \
  -C /m/b-$x -cf /m/z-$x.tar . 2> /m/tar-$x.err; echo "tar de l amorce : code $? ; stderr $(wc -l < /m/tar-$x.err) lignes"' _ "$x" "$H" "$S" "$p" "$Q"
  echo "z-$x.tar : $(stat -c %s "$N/z-$x.tar") octets, $(tar -tf "$N/z-$x.tar" | wc -l) membres, sha256 $(sha256sum < "$N/z-$x.tar" | cut -c1-64)"
  echo "## installation $x, fin $(date -u +%FT%TZ)"
done
echo "## LG4 : z-all contre la référence b063feb3"
[ "$(sha256sum < "$N/z-all.tar" | cut -c1-64)" = "$Z" ] && echo "OK   z-all.tar = b063feb3 octet pour octet" || { echo "ÉCART z-all.tar différent de b063feb3"
  python3 -I "$r/m1b-repro2-comparer.py" "$Y/z-b1.tar" "$N/z-all.tar" 2>&1 | sed 's/^/   comparer : /'; }
echo "## LG5 : z-en contre z-all (membre à membre)"
cmp -s "$N/z-en.tar" "$N/z-all.tar" && echo "OK   z-en.tar et z-all.tar identiques" || python3 -I "$r/m1b-repro2-comparer.py" "$N/z-all.tar" "$N/z-en.tar" 2>&1 | sed 's/^/   comparer : /'
python3 -I - "$N/z-all.tar" "$N/z-en.tar" <<'PY'
import sys, tarfile
for n, p in (('z-all', sys.argv[1]), ('z-en', sys.argv[2])):
    with tarfile.open(p, 'r:') as t:
        m = [x.name for x in t]
    loc = [x for x in m if x.startswith('./usr/share/locale/')]
    print(f'{n} : {len(m)} membres ; {len(loc)} sous usr/share/locale, dont {sum(1 for x in loc if x.endswith(".mo"))} fichiers .mo')
PY
echo "après : /m de la racine d'outils $(ls -A "$B/m" | wc -l) entrée(s) (avant : $nb_m), /mnt $(ls -A "$B/mnt" | wc -l)"
echo "place libre sous \$HOME après : $(df -k --output=avail "$HOME" | tail -1) kB ; dossier laissé : $N"
echo "# fin $(date -u +%FT%TZ)"
