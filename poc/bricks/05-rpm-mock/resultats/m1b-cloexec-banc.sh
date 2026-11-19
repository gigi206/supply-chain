#!/usr/bin/env bash
# Brique 05, M1b : vérification, sur l'hôte et hors ligne, de l'explication de la lenteur de dnf dans le pod m1b-a
# (m1b-pod-observation.log, m1b-rpm-cloexec.log) : avant l'exec de chaque scriptlet, rpm 4.16.1.3 n'ouvrirait pas /proc/self/fd
# (racine de l'installation sans /proc monté) et appellerait fcntl sur chaque descripteur jusqu'à la limite dure RLIMIT_NOFILE.
# Racine de l'amorce ed654c69 extraite à neuf, entrées de m1b.sh prealables (entrees.tar), même installation que SONDE_INSTALL.
# Quatre installations, chacune dans sa racine d'installation :
#   A  strace -f, openat de /proc/self/fd seulement (-P) : résultat de chaque ouverture, par processus
#   B  strace -f -c, fcntl seulement : nombre d'appels
#   C  sans strace, limite dure de l'hôte (524288) : durée, archive
#   D  sans strace, limite dure abaissée à 1024 : durée, archive
# Correctifs après le premier passage (m1b-cloexec-banc-1.log, arrêté) : strace en --seccomp-bpf, gpg-agent et scdaemon lancés
# par dnf arrêtés à la fin de l'installation (strace -f les attendait). Rien n'est installé sur l'hôte. Prédictions CX1 à CX6 dans m1b-predictions.md, écrites avant le lancement. Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-cloexec-banc.sh > poc/bricks/05-rpm-mock/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux
M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d
E=$HOME/.cache/supply-chain-poc/08/travail/m1b-05     # entrees.tar et entrees.sha256 de m1b.sh prealables
S=1793914619
CIBLE=7c07083cd7bee149d391180633ad9cca6c82c7ad0dfa5c6bf248acad0b1ef9b7
NOMS="mock-6.9-1.el9 mock-core-configs-45.2-1.el9 podman-5.8.2-8.el9_8 skopeo-1.22.2-9.el9_8 rocky-release shadow-utils"
D=$HOME/.cache/supply-chain-poc/05/m1b-cloexec-$(date -u +%Y%m%dT%H%M%SZ)   # dossier neuf, jamais effacé ni réutilisé
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echo "# m1b-cloexec-banc.sh, début $(date -u +%FT%TZ) ; dossier $D"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent" >&2; exit 1; }
echo "strace : $(strace -V | head -1) ; place libre de /home : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB"
attendu "entrees.tar (m1b-prealables.log)" "$(sha256sum < "$E/entrees.tar" | cut -c1-64)" ba6f1f8852dfe4ec42bf67a1a65196520c57a64de6bb4fc84622739e9fd2e383
mkdir -p "$D/r"
L=$(python3 -I -c 'import json, sys; j = json.load(open(sys.argv[1])); assert len(j["layers"]) == 1; print(j["layers"][0]["digest"][7:])' "$O/blobs/sha256/$M")
attendu "couche de l'amorce" "$(sha256sum < "$O/blobs/sha256/$L" | cut -c1-64)" "$L"
unshare --map-auto --map-root-user -n tar -xf "$O/blobs/sha256/$L" -C "$D/r" --numeric-owner --exclude='dev/*' 2>/dev/null || echo "tar code $? (fichiers spéciaux ignorés)"
unshare --map-auto --map-root-user -n mkdir -p "$D/r/dev" "$D/r/proc" "$D/r/w/m"
unshare --map-auto --map-root-user -n tar -xf "$E/entrees.tar" -C "$D/r/w/m"
(cd "$D/r/w/m" && sha256sum -c --quiet "$E/entrees.sha256") && echo "OK   entrées revérifiées ($(wc -l < "$E/entrees.sha256") fichiers)"
unshare --map-auto --map-root-user -n ln -s /w/m "$D/r/m"
# x limite-dure trace(-|a|b) : installation dans /m/i<x>, dans la racine d'outils, umask 022, env -i comme SONDE_INSTALL
inst() {
  local x=$1 lim=$2 tr=$3 pre=() t r
  case $tr in
    a) pre=(strace -f -qq --seccomp-bpf -e trace=openat -P /proc/self/fd -o "$D/trace-$x.txt") ;;
    b) pre=(strace -f -qq --seccomp-bpf -c -e trace=fcntl -o "$D/trace-$x.txt") ;;
  esac
  t=$(date +%s.%N)
  r=0
  unshare --map-auto --map-root-user -n -m -p --fork bash -c 'mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || exit 97
    ulimit -Hn "$2"; ulimit -Sn "$2"; shift 2; exec "$@"' _ "$D/r" "$lim" "${pre[@]}" chroot "$D/r" sh -c 'cd /; umask 022
    echo "limite vue dans la racine d outils : $(ulimit -Sn) / $(ulimit -Hn)"
    env -i PATH=/usr/sbin:/usr/bin HOME=/root LC_ALL=C container=oci SOURCE_DATE_EPOCH='"$S"' /usr/bin/dnf -y -c /m/dnf.conf \
      --setopt=reposdir=/m/aucun --setopt=cachedir=/m/cache-'"$x"' --setopt=keepcache=0 --installroot=/m/i'"$x"' --releasever=9 install '"$NOMS"'
    r=$?; for p in /proc/[0-9]*; do case "$(tr "\0" " " < $p/cmdline 2>/dev/null)" in gpg-agent*|scdaemon*) kill ${p#/proc/};; esac; done; exit $r' \
    > "$D/dnf-$x.log" 2>&1 || r=$?
  echo "$x : limite dure $lim, trace ${tr} : dnf code $r en $(awk -v a="$t" -v b="$(date +%s.%N)" "BEGIN{printf \"%.1f\", b - a}") s ; $(head -1 "$D/dnf-$x.log") ; scriptlets « Running scriptlet » $(grep -c 'Running scriptlet' "$D/dnf-$x.log" || true)"
  [ "$r" = 0 ] || { tail -n 10 "$D/dnf-$x.log"; echo "KO   installation $x" >&2; exit 1; }
}
arch() { # x : archive de /m/i<x> comme SONDE_INSTALL (tar de l'amorce, dans la racine d'outils)
  unshare --map-auto --map-root-user -n chroot "$D/r" tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    --mtime="@$S" --clamp-mtime --xattrs --xattrs-include="*" --numeric-owner \
    --exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log \
    --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal \
    --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id \
    -C "/m/i$1" -cf "/w/$1.tar" .
  s=$(sha256sum < "$D/r/w/$1.tar" | cut -c1-64)
  [ "$s" = "$CIBLE" ] && echo "OK   archive $1 = cible 7c07083c… ($s)" || echo "ÉCART archive $1 : $s"
}
echo "## A : openat de /proc/self/fd, limite de l'hôte"
inst A "$(ulimit -Hn)" a
python3 -I - "$D/trace-A.txt" <<'PY'
import re, sys
from collections import Counter
l = open(sys.argv[1]).read().splitlines()
k = Counter()
for x in l:
    m = re.match(r'(\d+)\s+openat\(.*"/proc/self/fd".*\)\s+=\s+(.*)$', x)
    if m:
        k['réussie' if not m.group(2).startswith('-1') else m.group(2).split(' (')[0].replace('-1 ', '')] += 1
print(f"ouvertures de /proc/self/fd tracées : {sum(k.values())} ; par résultat : {dict(sorted(k.items()))} ; processus distincts : {len({x.split()[0] for x in l if 'openat' in x})}")
for x in l[:3]:
    print('     ' + x[:150])
PY
echo "## B : nombre d'appels fcntl, limite de l'hôte"
inst B "$(ulimit -Hn)" b
grep -E 'fcntl|total|calls' "$D/trace-B.txt" | sed 's/^/     /'
echo "## C : sans trace, limite de l'hôte"
inst C "$(ulimit -Hn)" -
arch C
echo "## D : sans trace, limite dure 1024"
inst D 1024 -
arch D
echo "place libre de /home après : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB"
echo "# fin $(date -u +%FT%TZ)"
