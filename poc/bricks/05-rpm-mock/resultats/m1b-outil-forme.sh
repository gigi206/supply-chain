#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b : l'outillage sous la forme décidée pour la tâche (19/11/2026). La cible 7c07083c (i8 par le tar de l'amorce) et
# les pods a à c ont été installés par /usr/bin/dnf, HOME=/root (langue venue de la macro de l'amorce, en_US) et, pour pod_c, la
# limite posée par un ulimit autour de la sonde entière. La tâche, comme le bootstrap (pod_e), poserait :
#   - dnf-3 sous env -i, la limite de fichiers ouverts à 1024 (souple puis dure) dans un sous-shell qui n'entoure que dnf ;
#   - HOME=/m/h, où /m/h/.rpmmacros pose %_install_langs en_US (la valeur que rpm de python lit dans l'amorce, pod_e) ;
#   - racine de l'arbre passée en 0555 avant l'archive ; umask 022 ; SOURCE_DATE_EPOCH=S ; container=oci.
# Banc de l'hôte, hors réseau, sans rien installer sur l'hôte : la racine d'outils de l'amorce (banc du 18/11, lecture seule)
# installe une fois les noms de m1b.sh sur le miroir du banc de l'amorce (lecture seule), avec dnf.conf du banc (d554fb1c) ;
# archive par le tar de l'amorce, options, borne S et exclusions de SONDE_INSTALL (m1b.sh). Montages dans un espace de noms à
# part : le miroir du banc lié d'abord sur le miroir/ du dossier neuf, puis le dossier neuf sur /m de la racine d'outils (le /m
# du banc est masqué, non modifié), miroir repassé en lecture seule. Prédictions OF0 à OF4 dans m1b-predictions.md, écrites avant le lancement. Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-outil-forme.sh > poc/bricks/05-rpm-mock/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
B=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/outils   # racine d'outils de l'amorce et miroir : lecture seule
Y=$HOME/.cache/supply-chain-poc/05/m1b-tar-amorce-20261119T084746Z            # a8-amorce.tar (7c07083c) : lecture seule
Z=7c07083cd7bee149d391180633ad9cca6c82c7ad0dfa5c6bf248acad0b1ef9b7                # cible de l'outillage (m1b-tar-amorce.log)
CONF=d554fb1ce168663f                                                              # dnf.conf du banc (m1b.sh, 16 caractères)
S=1793914619                                                                       # m1b.sh, S_ATT
NOMS="mock-6.9-1.el9 mock-core-configs-45.2-1.el9 podman-5.8.2-8.el9_8 skopeo-1.22.2-9.el9_8 rocky-release shadow-utils"   # m1b.sh, l. 41
U=$(date -u +%Y%m%dT%H%M%SZ)
N=$HOME/.cache/supply-chain-poc/05/m1b-outil-forme-$U                             # dossier neuf, jamais effacé ni réutilisé
ns() { unshare --map-auto --map-root-user -n "$@"; }
q() { ns -m -p --fork bash -c 'umask 022; o=$1; n=$2; shift 2
  mount --rbind /dev "$o/dev" && mount -t proc proc "$o/proc" && mount --bind "$o/m/miroir" "$n/miroir" \
    && mount --rbind "$n" "$o/m" && mount -o remount,bind,ro "$o/m/miroir" || exit 97
  export HOME=/root; exec chroot "$o" "$@"' _ "$B" "$N" "$@"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echo "# m1b-outil-forme.sh, début $(date -u +%FT%TZ) ; dossier $N"
[ ! -e "$N" ] || { echo "KO   dossier déjà présent : $N" >&2; exit 1; }
l=$(df -k --output=avail "$HOME" | tail -1)
echo "place libre sous \$HOME avant : $l kB"
[ "$l" -ge 3000000 ] || { echo "KO   moins de 3 Go libres : arrêt, rien n'est effacé" >&2; exit 1; }
attendu "a8-amorce.tar du 19/11" "$(sha256sum < "$Y/a8-amorce.tar" | cut -c1-64)" "$Z"
attendu "dnf.conf du banc (16 car.)" "$(sha256sum < "$B/m/dnf.conf" | cut -c1-16)" "$CONF"
nb_m=$(ls -A "$B/m" | wc -l); echo "avant : /m de la racine d'outils $nb_m entrée(s), /mnt $(ls -A "$B/mnt" | wc -l)"
mkdir -p "$N/miroir" "$N/aucun" "$N/h" "$N/cles"
cp "$B/m/dnf.conf" "$N/dnf.conf"; cp "$B/m/cles/RPM-GPG-KEY-Rocky-9" "$B/m/cles/RPM-GPG-KEY-EPEL-9" "$N/cles/"
printf '%%_install_langs en_US\n' > "$N/h/.rpmmacros"
echo "## OF0 : outils et témoins dans la racine d'outils"
q bash -c 'rpm -q --qf "%{NEVRA}\n" rpm python3-dnf libsolv libdnf tar dnf' | sed 's/^/     /'
echo "     /m/miroir en lecture seule : $(q bash -c 'touch /m/miroir/.essai 2>/dev/null && echo non || echo oui')"
echo "     rpm dans /m/miroir : $(q bash -c 'find /m/miroir -name "*.rpm" | wc -l')"
for H in /root /m/h; do
  echo "     %_install_langs lu par rpm de python, env -i HOME=$H : [$(q env -i PATH=/usr/sbin:/usr/bin HOME=$H LC_ALL=C python3 -c 'import rpm; print(rpm.expandMacro("%_install_langs"))')]"
done
echo "## OF1 à OF3 : installation sous la forme décidée, début $(date -u +%FT%TZ)"
q bash -c 'set -u; S=$1; p=$2; cd /; umask 022
t=$(date +%s)
( ulimit -Sn 1024 && ulimit -Hn 1024 || exit 97; echo "$(ulimit -Sn) / $(ulimit -Hn)" > /m/lim.txt
  exec env -i PATH=/usr/sbin:/usr/bin HOME=/m/h LC_ALL=C container=oci SOURCE_DATE_EPOCH=$S /usr/bin/dnf-3 -y -c /m/dnf.conf \
    --setopt=reposdir=/m/aucun --setopt=cachedir=/m/cache --installroot=/m/i --releasever=9 install $p ) > /m/dnf.log 2>&1
r=$?; echo "limite de fichiers ouverts dans le sous-shell de dnf : $(cat /m/lim.txt 2>/dev/null) ; limite du shell après : $(ulimit -Sn) / $(ulimit -Hn)"
echo "dnf-3 code $r en $(($(date +%s) - t)) s ; $(wc -l < /m/dnf.log) lignes de journal"
[ $r = 0 ] || { tail -n 15 /m/dnf.log; exit 1; }
grep -E "^(Install|Upgrade|Remove|Downgrade|Reinstall|Skip) +[0-9]+ Package" /m/dnf.log | sed "s/^/résumé de la transaction : /"
echo "paquets installés : $(rpm --root=/m/i -qa | wc -l), dont gpg-pubkey $(rpm --root=/m/i -qa gpg-pubkey | wc -l)"
echo "racine de l arbre avant chmod : $(stat -c %a /m/i)"
chmod 0555 /m/i; echo "racine passée en $(stat -c %a /m/i) ; etc/machine-id : $(stat -c "%s octet(s)" /m/i/etc/machine-id 2>/dev/null || echo absent)"
tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
  --xattrs --xattrs-include="*" --numeric-owner \
  --exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log \
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal \
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id \
  -C /m/i -cf /m/f.tar . 2> /m/tar.err; echo "tar de l amorce : code $? ; stderr $(wc -l < /m/tar.err) lignes"' _ "$S" "$NOMS"
echo "f.tar : $(stat -c %s "$N/f.tar") octets, $(tar -tf "$N/f.tar" | wc -l) membres, sha256 $(sha256sum < "$N/f.tar" | cut -c1-64)"
echo "## OF4 : f.tar contre la cible 7c07083c"
[ "$(sha256sum < "$N/f.tar" | cut -c1-64)" = "$Z" ] && echo "OK   f.tar = 7c07083c octet pour octet" || { echo "ÉCART f.tar différent de 7c07083c"
  python3 -I "$r/m1b-repro2-comparer.py" "$Y/a8-amorce.tar" "$N/f.tar" 2>&1 | sed 's/^/   comparer : /'; }
echo "après : /m de la racine d'outils $(ls -A "$B/m" | wc -l) entrée(s) (avant : $nb_m), /mnt $(ls -A "$B/mnt" | wc -l)"
echo "place libre sous \$HOME après : $(df -k --output=avail "$HOME" | tail -1) kB ; dossier laissé : $N"
echo "# fin $(date -u +%FT%TZ)"
