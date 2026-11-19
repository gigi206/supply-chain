#!/usr/bin/env bash
# Brique 05, M1b : nouvelle référence du bootstrap avec la racine de l'archive en 0555 (décision « Absent » du 19/11/2026 et valeurs
# fixées : en_US, umask 022, racine 0555). Hors ligne, sans installation. Les arbres b1 et b2 du banc du 18/11 (m1b-boot.sh,
# 21:42:26 UTC) ne sont pas modifiés : chacun est copié par cp -a dans un dossier neuf, la racine de la copie passe en 0555 (dans S1,
# ce 0555 vient du cp -a de la racine de la base, s1.sh l. 882), puis la copie est archivée avec la fonction, la borne S et les
# exclusions de m1b-boot.sh (machine-id absent). Prédictions BR0 à BR7 dans m1b-predictions.md, écrites avant le lancement.
# Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-boot-0555.sh > poc/bricks/05-rpm-mock/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
S=1766985142                                                         # S_ATT de m1b-boot.sh (m1b-listes, 153 entrées)
X=$HOME/.cache/supply-chain-poc/05/m1b-boot-20261118T214226Z         # banc du 18/11 : lecture seule
X1=28634a12c5e99aae558a0cd6719d8f87fad6bac329724f0afafee252e6b78ab3   # référence du 18/11 (racine 0775)
U=$(date -u +%Y%m%dT%H%M%SZ)
D=$HOME/.cache/supply-chain-poc/05/m1b-boot-0555-$U                  # dossier neuf, jamais effacé ni réutilisé
ns() { unshare --map-auto --map-root-user -n "$@"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echo "# m1b-boot-0555.sh, début $(date -u +%FT%TZ) ; dossier $D"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }
mkdir -p "$D/copies" "$D/archives"
EXCL=(--exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id)
archive() { # arbre fichier exclusions… (identique à m1b-boot.sh)
  local a=$1 f=$2; shift 2
  ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
    --xattrs --xattrs-include='*' --numeric-owner "$@" -C "$a" -cf "$f" . 2> "$f.err" || echo "tar code $? ($(wc -l < "$f.err") lignes d'erreur)"
  echo "$(basename "$f") : $(stat -c %s "$f") octets, $(tar -tf "$f" | wc -l) membres, sha256 $(sha256sum < "$f" | cut -c1-64)"
}
echo "## 0. arbres du 18/11 avant : mode de la racine"
for b in b1 b2; do echo "$b : $(stat -c %a "$X/outils/m/$b")"; done
echo "## 1. témoin : ré-archivage de b1 tel quel (BR0)"
archive "$X/outils/m/b1" "$D/archives/t1.tar" "${EXCL[@]}"
attendu "t1 = référence du 18/11" "$(sha256sum < "$D/archives/t1.tar" | cut -c1-64)" "$X1"
echo "## 2. copies par cp -a, racine des copies en 0555 (BR1)"
for b in b1 b2; do
  rc=0; ns bash -c 'mkdir "$2" && cp -a "$1/." "$2/" && chmod 0555 "$2"' _ "$X/outils/m/$b" "$D/copies/$b" 2> "$D/copies/$b.err" || rc=$?
  echo "copie $b : code $rc ; stderr $(wc -l < "$D/copies/$b.err") lignes ; racine $(stat -c %a "$D/copies/$b") ; $(du -sk "$D/copies/$b" | cut -f1) kB"
  head -3 "$D/copies/$b.err" | sed 's/^/   stderr : /'
done
echo "## 3. archives y1, y2 (BR2 à BR5)"
archive "$D/copies/b1" "$D/archives/y1.tar" "${EXCL[@]}"
archive "$D/copies/b2" "$D/archives/y2.tar" "${EXCL[@]}"
cmp -s "$D/archives/y1.tar" "$D/archives/y2.tar" && echo "OK   y1.tar et y2.tar identiques octet à octet" || echo "ÉCART y1.tar et y2.tar différents"
for f in t1 y1 y2; do [ -s "$D/archives/$f.tar.err" ] && echo "tar $f : stderr $(wc -l < "$D/archives/$f.tar.err") lignes" || echo "tar $f : stderr vide"; done
python3 -I - "$D/archives/y1.tar" "$X/archives/x1.tar" <<'PY'
import sys, tarfile
def lit(p):
    with tarfile.open(p, 'r:') as t:
        return {m.name: m for m in t.getmembers()}
y, x = lit(sys.argv[1]), lit(sys.argv[2])
print(f"y1 : {len(y)} membres ; x1 : {len(x)} membres ; noms identiques : {'oui' if set(y) == set(x) else 'non'}")
for n in sorted(set(y) ^ set(x))[:10]:
    print(f"     seulement dans {'y1' if n in y else 'x1'} : {n}")
print(f"y1 : racine {oct(y['.'].mode)} ; x1 : racine {oct(x['.'].mode)} ; etc/machine-id dans y1 : {'présent' if './etc/machine-id' in y else 'absent'}")
champs = ('mode', 'uid', 'gid', 'size', 'mtime', 'type', 'linkname', 'pax_headers')
diff = [(n, c) for n in sorted(set(y) & set(x)) for c in champs if getattr(y[n], c) != getattr(x[n], c)]
print(f"membres communs différant par un champ d'en-tête : {len(diff)}")
for n, c in diff[:10]:
    print(f"     {n} : {c} {getattr(x[n], c)!r} -> {getattr(y[n], c)!r}" if c != 'pax_headers' else f"     {n} : pax_headers (clés {sorted(set(x[n].pax_headers) ^ set(y[n].pax_headers)) or 'mêmes clés, valeurs'})")
PY
python3 -I "$r/m1b-repro2-comparer.py" "$X/archives/x1.tar" "$D/archives/y1.tar" 2>&1 | tail -n 8 | sed 's/^/   comparer : /'
echo "## 4. arbres du 18/11 après : mode de la racine (BR6)"
for b in b1 b2; do echo "$b : $(stat -c %a "$X/outils/m/$b")"; done
echo "# fin $(date -u +%FT%TZ)"
