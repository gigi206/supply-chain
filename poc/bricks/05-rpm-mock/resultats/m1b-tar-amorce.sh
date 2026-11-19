#!/usr/bin/env bash
# Brique 05, M1b : la tâche archivera avec le tar de l'amorce ed654c69, les références avec celui de l'hôte. Ré-archivage de l'arbre
# i8 du banc de l'amorce du 18/11 (référence a8 = 06c289ad) par le tar de l'amorce, dans sa racine d'outils (chroot du banc, umask
# 022), mêmes options, borne S et exclusions ; archive écrite sur la sortie standard vers un dossier neuf. Hors ligne, rien n'est
# installé ; l'arbre et la racine d'outils ne sont pas modifiés. Compte aussi les en-têtes SCHILY.xattr de a8. Prédictions TA1 à TA4
# dans m1b-predictions.md, écrites avant le lancement. Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-tar-amorce.sh > poc/bricks/05-rpm-mock/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
B=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z   # banc du 18/11 : lecture seule
A8=06c289ad8da33198dd845be6cc899f688ecfb8986e77e4b333629e838876dfa5
S=1793914619                                                          # S du banc de l'amorce (AJ4, m1b-outil-amorce.log)
U=$(date -u +%Y%m%dT%H%M%SZ)
N=$HOME/.cache/supply-chain-poc/05/m1b-tar-amorce-$U                   # dossier neuf, jamais effacé ni réutilisé
ns() { unshare --map-auto --map-root-user -n "$@"; }
q() { ns -m -p --fork bash -c 'umask 022; mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || exit 97
  export HOME=/root; exec chroot "$@"' _ "$B/outils" "$@"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echo "# m1b-tar-amorce.sh, début $(date -u +%FT%TZ) ; dossier $N"
[ ! -e "$N" ] || { echo "KO   dossier déjà présent : $N" >&2; exit 1; }
mkdir -p "$N"
grep -q "S = $S" "$r/m1b-outil-amorce.log" && echo "OK   S = $S dans m1b-outil-amorce.log" || { echo "KO   S absente du journal" >&2; exit 1; }
attendu "a8.tar du 18/11" "$(sha256sum < "$B/archives/a8.tar" | cut -c1-64)" "$A8"
echo "tar de l'hôte : $(tar --version | head -1)"
echo "tar de l'amorce : $(q tar --version | head -1) ; paquet $(q rpm -q tar)"
echo "## ré-archivage de i8 par le tar de l'amorce (TA1, TA2)"
rc=0
q tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
  --xattrs --xattrs-include='*' --numeric-owner \
  --exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log \
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal \
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id \
  -C /m/i8 -cf - . > "$N/a8-amorce.tar" 2> "$N/a8-amorce.err" || rc=$?
echo "tar de l'amorce : code $rc ; stderr $(wc -l < "$N/a8-amorce.err") lignes"
head -3 "$N/a8-amorce.err" | sed 's/^/   stderr : /'
s=$(sha256sum < "$N/a8-amorce.tar" | cut -c1-64)
echo "a8-amorce.tar : $(stat -c %s "$N/a8-amorce.tar") octets, $(tar -tf "$N/a8-amorce.tar" | wc -l) membres, sha256 $s"
[ "$s" = "$A8" ] && echo "OK   a8-amorce.tar = a8.tar (06c289ad) octet pour octet" || echo "ÉCART a8-amorce.tar différent de a8.tar"
echo "## comparaison membre à membre (TA3)"
python3 -I "$r/m1b-repro2-comparer.py" "$B/archives/a8.tar" "$N/a8-amorce.tar" 2>&1 | tail -n 12 | sed 's/^/   comparer : /'
echo "## en-têtes pax de a8 (TA4)"
python3 -I - "$B/archives/a8.tar" <<'PY'
import sys, tarfile
from collections import Counter
k = Counter(); n = 0
with tarfile.open(sys.argv[1], 'r:') as t:
    for m in t:
        x = [c for c in m.pax_headers if c.startswith('SCHILY.xattr.')]
        n += bool(x)
        k.update(x)
print(f"membres avec un en-tête SCHILY.xattr : {n}")
for c, v in sorted(k.items()):
    print(f"     {c} : {v}")
PY
echo "# fin $(date -u +%FT%TZ)"
