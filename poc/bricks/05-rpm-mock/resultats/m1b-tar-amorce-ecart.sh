#!/usr/bin/env bash
# Brique 05, M1b : lecture seule après m1b-tar-amorce.sh (19/11/2026, 08:47:46 UTC). a8.tar (tar 1.35 de l'hôte) et a8-amorce.tar
# (tar 1.34 de l'amorce) ont les mêmes membres, en-têtes pax et contenus, mais diffèrent octet à octet. Localise les écarts : tailles,
# nombre d'octets différents, blocs de 512 octets touchés, et pour les premiers blocs, le type d'en-tête tar et les champs qui
# diffèrent (nom, mode, uid, gid, taille, mtime, somme, type, magic, version, uname, gname). Aucune archive n'est écrite.
# Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-tar-amorce-ecart.sh > poc/bricks/05-rpm-mock/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
X=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/archives/a8.tar
Y=$HOME/.cache/supply-chain-poc/05/m1b-tar-amorce-20261119T084746Z/a8-amorce.tar
echo "# m1b-tar-amorce-ecart.sh, début $(date -u +%FT%TZ)"
echo "a8.tar : $(stat -c %s "$X") octets, sha256 $(sha256sum < "$X" | cut -c1-16) ; a8-amorce.tar : $(stat -c %s "$Y") octets, sha256 $(sha256sum < "$Y" | cut -c1-16)"
python3 -I - "$X" "$Y" <<'PY'
import sys
from collections import Counter
a, b = (open(p, 'rb').read() for p in sys.argv[1:3])
n = min(len(a), len(b))
blocs = sorted({i // 512 for i in range(n) if a[i] != b[i]})
print(f"octets différents (sur la longueur commune) : {sum(1 for i in range(n) if a[i] != b[i])} ; blocs de 512 touchés : {len(blocs)}")
CH = [('nom', 0, 100), ('mode', 100, 8), ('uid', 108, 8), ('gid', 116, 8), ('taille', 124, 12), ('mtime', 136, 12),
      ('somme', 148, 8), ('type', 156, 1), ('cible', 157, 100), ('magic', 257, 6), ('version', 263, 2), ('uname', 265, 32),
      ('gname', 297, 32), ('devmajor', 329, 8), ('devminor', 337, 8), ('prefixe', 345, 155), ('reste', 500, 12)]
def champs(x, o):
    return {k: x[o + d:o + d + l] for k, d, l in CH}
types, diffs = Counter(), Counter()
for k in blocs:
    o = k * 512
    ha, hb = champs(a, o), champs(b, o)
    est_entete = ha['magic'].startswith(b'ustar')
    t = ha['type'].decode('latin-1') if est_entete else 'données'
    types[t] += 1
    if est_entete:
        for c in ha:
            if ha[c] != hb[c]:
                diffs[(t, c)] += 1
print("blocs touchés par type d'en-tête (x = en-tête pax, 0 = fichier, 5 = dossier, 2 = lien, données = hors en-tête) :")
for t, v in sorted(types.items()):
    print(f"     {t} : {v}")
print("champs différents dans les en-têtes touchés :")
for (t, c), v in sorted(diffs.items()):
    print(f"     type {t}, {c} : {v}")
for k in blocs[:3]:
    o = k * 512
    ha, hb = champs(a, o), champs(b, o)
    if ha['magic'].startswith(b'ustar'):
        nom = ha['nom'].rstrip(b'\0').decode('utf-8', 'replace')[:80]
        print(f"bloc {k} : type {ha['type'].decode('latin-1')}, nom {nom!r}")
        for c in ha:
            if ha[c] != hb[c]:
                print(f"     {c} : 1.35 {ha[c].rstrip(bytes(1))!r} ; 1.34 {hb[c].rstrip(bytes(1))!r}")
PY
echo "# fin $(date -u +%FT%TZ)"
