#!/usr/bin/env bash
# Brique 05, M1b, point 1 A, second banc : sur les deux arbres laissés par m1b-repro.sh (passage du 18/11/2026, 19:44:49 UTC),
# sans réinstaller. Hôte seul, hors ligne (unshare -n), sans cluster ni Zot. Les arbres ne sont pas écrits : les archives vont dans
# un dossier neuf, et la base rpm est lue sur une copie (--dbpath), comme SONDE_BOOT de s1.sh (l. 697).
#   1. E = plus grand BUILDTIME des paquets installés, égal des deux côtés ; entrées dont la mtime dépasse E, par arbre.
#   2. Archive de chaque arbre : options normalisées du premier banc, mtimes bornées à E (--mtime=@E --clamp-mtime), sans les sept
#      fichiers de dnf (quatre journaux, history.sqlite et ses -shm et -wal) ni var/cache/ldconfig/aux-cache ; témoin : arbre 1 deux fois.
#   3. Comparaison des deux archives, membre par membre (m1b-repro2-comparer.py).
#   4. Base rpm : en-têtes de chaque paquet (rpm -qa --xml), comparés étiquette par étiquette ; tables SQLite (m1b-repro2-rpmdb.py).
#   5. cacerts : structure du magasin Java lue et comparée champ par champ (m1b-repro2-cacerts.py).
# Prédictions : m1b-predictions.md (section du second banc), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-repro2.sh > poc/bricks/05-rpm-mock/resultats/m1b-repro2.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
D=$HOME/.cache/supply-chain-poc/05/m1b-repro-20261118T194449Z
U=$(date -u +%Y%m%dT%H%M%SZ)
N=$HOME/.cache/supply-chain-poc/05/m1b-repro2-$U   # archives : dossier neuf, jamais effacé ni réutilisé
C=m/repro2-$U                                     # copies des bases rpm, dans la racine d'outils (hors des arbres i1 et i2)
ns() { unshare --map-auto --map-root-user -n "$@"; }
q() { ns chroot "$D/racine" "$@"; }
echo "# m1b-repro2.sh, début $(date -u +%FT%TZ)"
for i in 1 2; do [ -d "$D/racine/m/i$i/var/lib/rpm" ] || { echo "KO   arbre $i absent" >&2; exit 1; }; done
[ ! -e "$N" ] && [ ! -e "$D/racine/$C" ] || { echo "KO   dossier déjà présent" >&2; exit 1; }
mkdir -p "$N" "$D/racine/$C"
for i in 1 2; do
  ns cp -a "$D/racine/m/i$i/var/lib/rpm" "$D/racine/$C/rpmdb-$i"
  echo "copie de la base rpm de l'arbre $i : $(ns ls "$D/racine/$C/rpmdb-$i" | tr '\n' ' ')"
done

echo "## 1. borne des mtimes"
for i in 1 2; do q /usr/bin/rpm --dbpath "/$C/rpmdb-$i" -qa --qf '%{BUILDTIME}\n' | sort -n | tail -n 1 > "$N/E-$i"; done
E=$(cat "$N/E-1")
[ "$E" = "$(cat "$N/E-2")" ] && echo "OK   E = $E ($(date -u -d "@$E" +%FT%TZ)), égal des deux côtés" \
  || { echo "KO   E diffère : $E et $(cat "$N/E-2")" >&2; exit 1; }
for i in 1 2; do
  ns python3 -I - "$D/racine/m/i$i" "$E" <<'PY'
import os, stat, sys
from collections import Counter
a, e = sys.argv[1], int(sys.argv[2]); c = Counter()
for d, ds, fs in os.walk(a):
    for x in ds + fs:
        s = os.lstat(os.path.join(d, x))
        if s.st_mtime > e:
            c[{stat.S_IFDIR: 'répertoire', stat.S_IFREG: 'fichier', stat.S_IFLNK: 'lien'}.get(stat.S_IFMT(s.st_mode), 'autre')] += 1
print(f'{a.rsplit("/", 1)[-1]} : entrées dont la mtime dépasse E : {sum(c.values())} (' + ', '.join(f'{k} {n}' for k, n in sorted(c.items())) + ')')
PY
done

echo "## 2. archives bornées, sans journaux ni historique de dnf ni aux-cache"
EXCL=(--exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal
  --exclude=./var/cache/ldconfig/aux-cache)
archive() { # arbre fichier
  ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$E" --clamp-mtime \
    --xattrs --xattrs-include='*' --numeric-owner "${EXCL[@]}" -C "$D/racine/m/i$1" -cf "$2" . 2> "$2.err" || echo "tar code $? ($(wc -l < "$2.err") lignes d'erreur)"
  echo "$(basename "$2") : $(stat -c %s "$2") octets, sha256 $(sha256sum < "$2" | cut -c1-64)"
}
archive 1 "$N/a1.tar"
archive 2 "$N/a2.tar"
archive 1 "$N/a1b.tar"
for f in "${EXCL[@]}"; do
  p=${f#--exclude=./}; n=$(tar -tf "$N/a1.tar" | grep -cxF "./$p" || true); echo "exclu, absent de a1.tar : $p ($n occurrence)"
done

echo "## 3. comparaison des deux archives, membre par membre"
python3 -I "$r/m1b-repro2-comparer.py" "$N/a1.tar" "$N/a2.tar"
echo "## témoin : a1.tar et a1b.tar"
cmp -s "$N/a1.tar" "$N/a1b.tar" && echo "OK   a1.tar et a1b.tar identiques octet à octet" || echo "ÉCART a1.tar et a1b.tar différents"

echo "## 4. base rpm"
for i in 1 2; do q /usr/bin/rpm --dbpath "/$C/rpmdb-$i" -qa --xml > "$N/rpmdb-$i.xml" 2> "$N/rpmdb-$i.err" || echo "rpm --xml code $?"; done
python3 -I "$r/m1b-repro2-rpmdb.py" "$N/rpmdb-1.xml" "$N/rpmdb-2.xml" "$D/racine/$C/rpmdb-1/rpmdb.sqlite" "$D/racine/$C/rpmdb-2/rpmdb.sqlite"

echo "## 5. cacerts"
python3 -I "$r/m1b-repro2-cacerts.py" "$D/racine/m/i1/etc/pki/ca-trust/extracted/java/cacerts" "$D/racine/m/i2/etc/pki/ca-trust/extracted/java/cacerts"
echo "# fin $(date -u +%FT%TZ)"
