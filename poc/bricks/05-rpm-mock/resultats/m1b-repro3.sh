#!/usr/bin/env bash
# Brique 05, M1b, point 1 A, troisième banc : les écarts restants du second banc (rpmdb.sqlite : Installtime et Installtid ;
# cacerts : horodatage de génération) disparaissent-ils si SOURCE_DATE_EPOCH est posé pendant dnf --installroot ?
# Lecture préalable (18/11/2026, sans journal, reprise ici) : la chaîne SOURCE_DATE_EPOCH est présente dans librpm.so.9 (près de
# « rpmts.c ») et dans /usr/bin/trust de p11-kit ; ce qu'elle fixe n'est pas lu. Ce banc le mesure.
# Hôte seul, hors ligne (unshare -n), sans cluster ni Zot ; mêmes outils (couches de 99790c13) et mêmes 222 rpm que le premier banc,
# dans un dossier neuf. Le premier banc n'est que lu (arbre i1 et copie de sa base rpm faite par le second banc).
#   1. Borne S = max(plus grand BUILDTIME, plus grande FILEMTIMES) des en-têtes installés (copie de la base de i1).
#   2. Deux installations i3 et i4 avec SOURCE_DATE_EPOCH=S, 5 s d'écart.
#   3. Archives bornées à S, sans les huit fichiers du second banc : i3, i4, i3 de nouveau (témoin), i1 (témoin sans la variable).
#   4. Comparaisons membre par membre (m1b-repro2-comparer.py), base rpm (m1b-repro2-rpmdb.py), cacerts (m1b-repro2-cacerts.py).
#   5. Champs au jour près : troisième champ de etc/shadow (dernier changement, en jours), i1 et i3.
# Prédictions : m1b-predictions.md (section du troisième banc), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-repro3.sh > poc/bricks/05-rpm-mock/resultats/m1b-repro3.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
V=$r/../../../packaging/verrou-rpm.json
B=$HOME/.cache/supply-chain-poc/05/banc-image/disque/sha256
DEP=$HOME/.cache/supply-chain-poc/08/travail/m4b-05/comparaison/tiree/depot
D1=$HOME/.cache/supply-chain-poc/05/m1b-repro-20261118T194449Z   # premier banc : lecture seule
B1=m/repro2-20261118T200256Z/rpmdb-1                            # copie de la base rpm de i1 (second banc)
U=$(date -u +%Y%m%dT%H%M%SZ)
D=$HOME/.cache/supply-chain-poc/05/m1b-repro3-$U                 # dossier neuf, jamais effacé ni réutilisé
COUCHES=(e48fc4d689daa5ec7af47350d996f93d76a138ff7267aed6972feefe3e4526bd fd00cdb1ac39ed07d03836b05bd7c24cf435e68a2b29d63403e5dfc4610ac157)
ns() { unshare --map-auto --map-root-user -n "$@"; }
q1() { ns chroot "$D1/racine" "$@"; }
q() { ns chroot "$D/racine" "$@"; }
echo "# m1b-repro3.sh, début $(date -u +%FT%TZ)"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }
[ -d "$D1/racine/m/i1/var/lib/rpm" ] && [ -f "$D1/racine/$B1/rpmdb.sqlite" ] || { echo "KO   premier banc absent" >&2; exit 1; }
echo "verrou : sha256 $(sha256sum < "$V" | cut -c1-64)"

echo "## 1. borne S"
E=$(q1 /usr/bin/rpm --dbpath "/$B1" -qa --qf '%{BUILDTIME}\n' | grep -E '^[0-9]+$' | sort -n | tail -n 1)
F=$(q1 /usr/bin/rpm --dbpath "/$B1" -qa --qf '[%{FILEMTIMES}\n]' | grep -E '^[0-9]+$' | sort -n | tail -n 1)
S=$(( E > F ? E : F ))
echo "plus grand BUILDTIME E = $E ($(date -u -d "@$E" +%FT%TZ)) ; plus grande FILEMTIMES F = $F ($(date -u -d "@$F" +%FT%TZ))"
echo "S = $S ($(date -u -d "@$S" +%FT%TZ)) ; jour de S : $((S / 86400)) ; jour du passage : $(( $(date -u +%s) / 86400 ))"

echo "## 2. installations avec SOURCE_DATE_EPOCH=S"
mkdir -p "$D/racine/m"
for l in "${COUCHES[@]}"; do
  s=$(sha256sum < "$B/$l" | cut -c1-64)
  [ "$s" = "$l" ] || { echo "KO   couche $l : sha256 $s" >&2; exit 1; }
  echo "OK   couche $l : sha256 égal à son nom"
done
ns bash -c 'for l in "$@"; do tar -xzf "$l" -C "'"$D"'/racine" --numeric-owner --exclude="dev/*" 2>/dev/null || echo "tar code $? (fichiers spéciaux ignorés)"; done' _ "${COUCHES[@]/#/$B/}"
[ -x "$D/racine/usr/bin/rpm" ] && [ -x "$D/racine/usr/bin/dnf-3" ] || { echo "KO   rpm ou dnf-3 absent de la racine" >&2; exit 1; }
cp -al "$DEP" "$D/racine/m/depot"
python3 -I - "$V" "$D/racine/m/depot" "$D/racine/m/liste" <<'PY'
import json, os, sys
j = json.load(open(sys.argv[1], encoding='utf-8'))
n = sorted(p['url'].rsplit('/', 1)[-1] for p in j['buildroot']['rpms'])
assert len(n) == 222 and len(set(n)) == 222, len(n)
manque = [x for x in n if not os.path.isfile(os.path.join(sys.argv[2], x))]
assert not manque, manque
open(sys.argv[3], 'w', encoding='utf-8').write(''.join(f'/m/depot/{x}\n' for x in n))
print(f'OK   liste : {len(n)} rpm du buildroot, tous présents dans la fermeture')
PY
echo "outils : $(q /usr/bin/rpm --version) ; dnf $(q /usr/bin/dnf-3 --version 2>/dev/null | head -1)"
echo "variable vue dans la racine d'outils : SOURCE_DATE_EPOCH=$(q /usr/bin/env SOURCE_DATE_EPOCH="$S" /usr/bin/printenv SOURCE_DATE_EPOCH)"
for i in 3 4; do
  echo "## installation $i, début $(date -u +%FT%TZ)"
  rc=0
  # shellcheck disable=SC2046
  q /usr/bin/env SOURCE_DATE_EPOCH="$S" /usr/bin/dnf-3 -y --installroot=/m/i$i --releasever=9 --setopt=reposdir=/m/aucun \
    --disablerepo='*' install $(cat "$D/racine/m/liste") > "$D/dnf-$i.log" 2>&1 || rc=$?
  echo "dnf code $rc ; $(wc -l < "$D/dnf-$i.log") lignes de journal"
  echo "lignes « scriptlet », « warning » ou « error » (casse ignorée) : $(grep -Eci 'scriptlet|(^|[^-[:alnum:]])(warning|error)' "$D/dnf-$i.log" || true)"
  [ "$rc" = 0 ] || { echo "KO   installation $i en échec" >&2; exit 1; }
  echo "paquets installés : $(q /usr/bin/rpm --root=/m/i$i -qa | wc -l) ; liste triée : sha256 $(q /usr/bin/rpm --root=/m/i$i -qa --qf '%{NEVRA}\n' | sort | sha256sum | cut -c1-64)"
  echo "couples (INSTALLTIME, INSTALLTID) distincts, avec leur nombre de paquets :"
  q /usr/bin/rpm --root=/m/i$i -qa --qf '%{INSTALLTIME} %{INSTALLTID}\n' | sort | uniq -c | sed 's/^/     /'
  echo "## installation $i, fin $(date -u +%FT%TZ)"
  [ "$i" = 4 ] || sleep 5
done
for i in 3 4; do
  ns python3 -I - "$D/racine/m/i$i" "$S" <<'PY'
import os, stat, sys
from collections import Counter
a, e = sys.argv[1], int(sys.argv[2]); c = Counter()
for d, ds, fs in os.walk(a):
    for x in ds + fs:
        s = os.lstat(os.path.join(d, x))
        if s.st_mtime > e:
            c[{stat.S_IFDIR: 'répertoire', stat.S_IFREG: 'fichier', stat.S_IFLNK: 'lien'}.get(stat.S_IFMT(s.st_mode), 'autre')] += 1
print(f'{a.rsplit("/", 1)[-1]} : entrées dont la mtime dépasse S : {sum(c.values())} (' + ', '.join(f'{k} {n}' for k, n in sorted(c.items())) + ')')
PY
done

echo "## 3. archives bornées à S, sans journaux ni historique de dnf ni aux-cache"
EXCL=(--exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal
  --exclude=./var/cache/ldconfig/aux-cache)
mkdir -p "$D/archives"
archive() { # arbre fichier
  ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
    --xattrs --xattrs-include='*' --numeric-owner "${EXCL[@]}" -C "$1" -cf "$2" . 2> "$2.err" || echo "tar code $? ($(wc -l < "$2.err") lignes d'erreur)"
  echo "$(basename "$2") : $(stat -c %s "$2") octets, sha256 $(sha256sum < "$2" | cut -c1-64)"
}
archive "$D/racine/m/i3" "$D/archives/a3.tar"
archive "$D/racine/m/i4" "$D/archives/a4.tar"
archive "$D/racine/m/i3" "$D/archives/a3b.tar"
archive "$D1/racine/m/i1" "$D/archives/a1s.tar"

echo "## 4a. comparaison i3 et i4 (même variable)"
python3 -I "$r/m1b-repro2-comparer.py" "$D/archives/a3.tar" "$D/archives/a4.tar"
cmp -s "$D/archives/a3.tar" "$D/archives/a4.tar" && echo "OK   a3.tar et a4.tar identiques octet à octet" || echo "ÉCART a3.tar et a4.tar différents"
echo "## témoin : a3.tar et a3b.tar"
cmp -s "$D/archives/a3.tar" "$D/archives/a3b.tar" && echo "OK   a3.tar et a3b.tar identiques octet à octet" || echo "ÉCART a3.tar et a3b.tar différents"
echo "## 4b. témoin sans la variable : i1 (premier banc) et i3, bornés à S"
python3 -I "$r/m1b-repro2-comparer.py" "$D/archives/a1s.tar" "$D/archives/a3.tar"
echo "## 4c. base rpm de i3 et i4"
for i in 3 4; do
  ns cp -a "$D/racine/m/i$i/var/lib/rpm" "$D/racine/m/rpmdb-$i"
  q /usr/bin/rpm --dbpath "/m/rpmdb-$i" -qa --xml > "$D/rpmdb-$i.xml" 2> "$D/rpmdb-$i.err" || echo "rpm --xml code $?"
done
python3 -I "$r/m1b-repro2-rpmdb.py" "$D/rpmdb-3.xml" "$D/rpmdb-4.xml" "$D/racine/m/rpmdb-3/rpmdb.sqlite" "$D/racine/m/rpmdb-4/rpmdb.sqlite"
echo "## 4d. cacerts de i3 et i4"
python3 -I "$r/m1b-repro2-cacerts.py" "$D/racine/m/i3/etc/pki/ca-trust/extracted/java/cacerts" "$D/racine/m/i4/etc/pki/ca-trust/extracted/java/cacerts"

echo "## 5. etc/shadow, troisième champ (dernier changement, en jours) : valeurs et nombre de lignes"
for t in "$D1/racine/m/i1" "$D/racine/m/i3"; do
  if ns test -e "$t/etc/shadow"; then
    echo "${t##*/} : $(ns cut -d: -f3 "$t/etc/shadow" | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
  else
    echo "${t##*/} : etc/shadow absent"
  fi
done
echo "# fin $(date -u +%FT%TZ)"
