#!/usr/bin/env bash
# Brique 05, M1b, banc de l'outillage : ré-archivage des arbres i5, i6, i7 du passage du 18/11/2026 (20:57:14 UTC) sans
# etc/machine-id, écrit par le %post de systemd (systemd-machine-id-setup ; m1b-machine-id.log). (18/11/2026)
#   1. Témoin : i5 archivé avec les exclusions du passage (m1b-outil.sh, l. 222-227) : arbre inchangé depuis le passage ?
#   2. b5, b6, b7 : mêmes options, plus --exclude=./etc/machine-id ; comparaisons b5/b6 et b5/b7.
# Hors ligne (unshare -n) ; les arbres ne sont pas modifiés ; archives dans un dossier neuf. Rien n'est installé.
# Prédictions : m1b-predictions.md (section « sans machine-id »), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-sans-machine-id.sh > poc/bricks/05-rpm-mock/resultats/m1b-sans-machine-id.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
D=$HOME/.cache/supply-chain-poc/05/m1b-outil-20261118T205714Z
A=$HOME/.cache/supply-chain-poc/05/m1b-sans-machine-id-$(date -u +%Y%m%dT%H%M%SZ)   # dossier neuf
S=1793914619                                                                          # m1b-outil.log, l. 54
ns() { unshare --map-auto --map-root-user -n "$@"; }
echo "# m1b-sans-machine-id.sh, début $(date -u +%FT%TZ)"
grep -q "^S = $S " "$r/m1b-outil.log" || { echo "KO   S différent de m1b-outil.log" >&2; exit 1; }
[ -d "$D/outils/m/i5" ] && [ ! -e "$A" ] || { echo "KO   banc absent ou dossier déjà présent" >&2; exit 1; }
mkdir -p "$A"
EXCL=(--exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m)
archive() { # arbre fichier [exclusions en plus]
  local a=$1 f=$2; shift 2
  ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
    --xattrs --xattrs-include='*' --numeric-owner "${EXCL[@]}" "$@" -C "$a" -cf "$f" . 2> "$f.err" || echo "tar code $? ($(wc -l < "$f.err") lignes d'erreur)"
  echo "$(basename "$f") : $(stat -c %s "$f") octets, $(tar -tf "$f" | wc -l) membres, sha256 $(sha256sum < "$f" | cut -c1-64)"
}
echo "## 1. témoin : i5 avec les exclusions du passage (a5.tar du passage : sha256 babac006…)"
archive "$D/outils/m/i5" "$A/t5.tar"
[ "$(sha256sum < "$A/t5.tar" | cut -c1-64)" = babac0060652f499bda0e8134b7b51dcbfcf6c0f7567248c49df1764e9bf1827 ] \
  && echo "OK   t5.tar égal à a5.tar du passage" || echo "ÉCART t5.tar différent de a5.tar du passage"
echo "## 2. sans etc/machine-id"
for i in 5 6 7; do archive "$D/outils/m/i$i" "$A/b$i.tar" --exclude=./etc/machine-id; done
for i in 5 6 7; do echo "b$i.tar : membres etc/machine-id : $(tar -tf "$A/b$i.tar" | grep -c '^\./etc/machine-id$' || true)"; done
cmp -s "$A/b5.tar" "$A/b6.tar" && echo "OK   b5.tar et b6.tar identiques octet à octet" || { echo "ÉCART b5.tar et b6.tar différents"; python3 -I "$r/m1b-repro2-comparer.py" "$A/b5.tar" "$A/b6.tar"; }
echo "## 3. b5 contre b7 (installation par fichiers, sans gpg-pubkey)"
python3 -I "$r/m1b-repro2-comparer.py" "$A/b5.tar" "$A/b7.tar"
echo "archives laissées dans $A"
echo "# fin $(date -u +%FT%TZ)"
