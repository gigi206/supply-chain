#!/usr/bin/env bash
# Brique 05, M1b : relevé en lecture seule après le banc du bootstrap de 21:42:26 UTC (18/11/2026). Mode de la racine des archives,
# membre « . » de la couche 812c4412, dossiers b1 et b2, date du mtime maximal de la couche, membres de c1 absents de x1.
# Aucune archive n'est écrite. Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-boot-modes.sh > poc/bricks/05-rpm-mock/resultats/m1b-boot-modes.log 2>&1
set -euo pipefail
export LC_ALL=C
D=$HOME/.cache/supply-chain-poc/05/m1b-boot-20261118T214226Z
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05   # jamais listé : boot-racine.tar et boot-racine.sha256 seuls lus
L=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256/812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09
echo "# m1b-boot-modes.sh, début $(date -u +%FT%TZ)"
for x in "c1 $D/archives/c1.tar 447ece2b645add4de28b44d893a28b3ce6eb6dff3ff342ea8ff07c005f0ca90a" \
         "x1 $D/archives/x1.tar 28634a12c5e99aae558a0cd6719d8f87fad6bac329724f0afafee252e6b78ab3" \
         "boot-racine.tar $T/boot-racine.tar $(cat "$T/boot-racine.sha256")" \
         "couche-812c4412 $L 812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09"; do
  set -- $x
  s=$(sha256sum < "$2" | cut -c1-64)
  [ "$s" = "$3" ] && echo "OK   $1 : sha256 égal ($s)" || { echo "KO   $1 : sha256 $s (attendu $3)" >&2; exit 1; }
done
python3 -I - "$D/archives/c1.tar" "$D/archives/x1.tar" "$T/boot-racine.tar" "$L" <<'PY'
import sys, tarfile
c1, x1, s1, couche = sys.argv[1:]
for nom, p in (('c1', c1), ('x1', x1), ('boot-racine.tar', s1)):
    with tarfile.open(p, 'r:') as t:
        m = t.next()
        print(f'{nom} : premier membre {m.name!r}, mode {oct(m.mode)}, uid {m.uid}, gid {m.gid}')
with tarfile.open(couche, 'r:*') as t:
    noms = [m.name for m in t]
racine = [n for n in noms if n in ('.', './', '')]
print(f'couche : {len(noms)} membres ; membre racine (« . », « ./ » ou vide) : {len(racine)} {racine}')
print(f'couche : premiers membres {noms[:3]}')
with tarfile.open(c1, 'r:') as t: a = set(t.getnames())
with tarfile.open(x1, 'r:') as t: b = set(t.getnames())
print(f'membres de c1 absents de x1 : {len(a - b)} ; de x1 absents de c1 : {len(b - a)}')
for n in sorted(a - b): print(f'     absent de x1 : {n}')
PY
for i in 1 2; do echo "stat de b$i : $(stat -c '%a %U:%G' "$D/outils/m/b$i")"; done
echo "mtime maximal de la couche, 1763921880 : $(date -u -d @1763921880 +%FT%TZ)"
echo "# fin $(date -u +%FT%TZ)"
