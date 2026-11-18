#!/usr/bin/env bash
# Brique 05, M1b : compléments demandés par la relecture du conseiller (18/11/2026), lecture locale seule, sans réseau.
#   1. Révision et sha256 de chaque repomd.xml téléchargé par m1b-sources.sh (dossier laissé en place).
#   2. Les 985 fichiers dont la mtime dépasse E et est égale dans les deux arbres du premier banc : mtime comparée à FILEMTIMES
#      de leur en-tête (copie de la base rpm de l'arbre 1, faite par m1b-repro2.sh), et paquet propriétaire.
# Prédictions : m1b-predictions.md (section des compléments), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-complements.sh > poc/bricks/05-rpm-mock/resultats/m1b-complements.log 2>&1
set -euo pipefail
export LC_ALL=C
S=$HOME/.cache/supply-chain-poc/05/m1b-sources-20261118T195832Z
D=$HOME/.cache/supply-chain-poc/05/m1b-repro-20261118T194449Z
C=m/repro2-20261118T200256Z
E=1778602708
ns() { unshare --map-auto --map-root-user -n "$@"; }
echo "# m1b-complements.sh, début $(date -u +%FT%TZ)"
echo "## 1. révisions des repomd.xml de $S"
for f in "$S"/*.repomd.xml; do
  v=$(grep -o '<revision>[^<]*' "$f" | cut -c11-)
  case $v in ''|*[!0-9]*) d=- ;; *) d=$(date -u -d "@$v" +%FT%TZ) ;; esac
  echo "$(basename "$f" .repomd.xml) : sha256 $(sha256sum < "$f" | cut -c1-64) ; révision $v ($d)"
done
echo "## 2. fichiers au-dessus de E à mtime égale, contre FILEMTIMES"
ns chroot "$D/racine" /usr/bin/rpm --dbpath "/$C/rpmdb-1" -qa --qf '[%{FILEMTIMES}\t%{=NAME}\t%{FILENAMES}\n]' > "$D/racine/$C/filemtimes.tsv"
echo "lignes de FILEMTIMES : $(wc -l < "$D/racine/$C/filemtimes.tsv")"
ns python3 -I - "$D/racine/m/i1" "$D/racine/m/i2" "$E" "$D/racine/$C/filemtimes.tsv" <<'PY'
import os, stat, sys
from collections import Counter
a1, a2, e, tsv = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
h = {}
for l in open(tsv, encoding='utf-8', errors='surrogateescape'):
    m, n, f = l.rstrip('\n').split('\t', 2)
    h.setdefault(f.lstrip('/'), []).append((int(m), n))
vus = []
for d, ds, fs in os.walk(a1):
    for x in ds + fs:
        p = os.path.join(d, x); r = os.path.relpath(p, a1); s1 = os.lstat(p); s2 = os.lstat(os.path.join(a2, r))
        if s1.st_mtime > e and s1.st_mtime_ns == s2.st_mtime_ns:
            vus.append((r, s1))
print(f'au-dessus de E à mtime égale : {len(vus)}')
eg = [r for r, s in vus if r in h and any(m == int(s.st_mtime) for m, _ in h[r])]
sans = [r for r, s in vus if r not in h]
print(f'mtime égale à FILEMTIMES : {len(eg)} ; chemin absent des en-têtes : {len(sans)} ; autre mtime : {len(vus) - len(eg) - len(sans)}')
print('paquets propriétaires : ' + ', '.join(f'{n} {c}' for n, c in sorted(Counter(n for r, _ in vus if r in h for _, n in h[r][:1]).items())))
for r in sans[:10]:
    print(f'     absent des en-têtes : {r}')
PY
echo "# fin $(date -u +%FT%TZ)"
