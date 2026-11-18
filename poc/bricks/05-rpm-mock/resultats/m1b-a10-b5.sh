#!/usr/bin/env bash
# Brique 05, M1b : a10 (outils de l'amorce, macro de langue masquée, umask 022 ; banc de 21:25:17 UTC) contre b5 (outils de 99790c13,
# umask de l'hôte 0002 ; ré-archivage de 21:08:52 UTC, référence 05d35d64). Les outils entiers comptent-ils, ou la macro de langue
# et le umask seuls ? (18/11/2026) Lecture seule, hors ligne ; aucune archive n'est écrite.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-a10-b5.sh > poc/bricks/05-rpm-mock/resultats/m1b-a10-b5.log 2>&1
set -euo pipefail
export LC_ALL=C
A=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/archives/a10.tar
B=$HOME/.cache/supply-chain-poc/05/m1b-sans-machine-id-20261118T210852Z/b5.tar
echo "# m1b-a10-b5.sh, début $(date -u +%FT%TZ)"
for x in "a10 $A d04abddacc75e34ffab1c2bfb7110a5107b73f31879c8a8f9f4f99f743236c8b" "b5 $B 05d35d64f09692b13bd08af86b405607bca75c72d359550864fcf89a0321a59a"; do
  set -- $x
  s=$(sha256sum < "$2" | cut -c1-64)
  [ "$s" = "$3" ] && echo "OK   $1 : $(stat -c %s "$2") octets, sha256 égal au journal de son passage" || { echo "KO   $1 : sha256 $s" >&2; exit 1; }
done
cmp -s "$A" "$B" && echo "a10 et b5 identiques octet à octet" || echo "a10 et b5 différents octet à octet"
contenu() { # archive-a archive-b nom-a nom-b : contenu seul (sans mtime ni en-têtes pax)
  python3 -I - "$@" <<'PY'
import hashlib, sys, tarfile
from collections import Counter
def membres(p):
    r = {}
    with tarfile.open(p, 'r:') as t:
        for m in t:
            e = {'type': m.type, 'mode': m.mode, 'uid': m.uid, 'gid': m.gid, 'taille': m.size, 'cible': m.linkname}
            if m.isfile():
                h = hashlib.sha256(); f = t.extractfile(m)
                for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
                e['sha256'] = h.hexdigest()
            r[m.name] = e
    return r
a, b = membres(sys.argv[1]), membres(sys.argv[2]); na, nb = sys.argv[3], sys.argv[4]
print(f'membres : {na} {len(a)} ; {nb} {len(b)}')
for nom, x in ((na, a), (nb, b)):
    loc = [p for p in x if p.startswith('./usr/share/locale/')]
    print(f'{nom} : {len(loc)} membres sous usr/share/locale, dont {sum(1 for p in loc if p.endswith(".mo"))} fichiers .mo')
sa, sb = sorted(set(a) - set(b)), sorted(set(b) - set(a))
diff = {p: [k for k in a[p] if a[p][k] != b[p].get(k)] for p in sorted(set(a) & set(b))}
diff = {p: c for p, c in diff.items() if c}
print(f'seulement dans {na} : {len(sa)} ; seulement dans {nb} : {len(sb)} ; présents des deux côtés et différents : {len(diff)}')
for p in sa[:20]: print(f'     seul dans {na} : {p}')
for p in sb[:20]: print(f'     seul dans {nb} : {p}')
for p, c in list(diff.items())[:40]: print(f'     écart : {p} ({", ".join(c)})')
print('champs en cause : ' + (', '.join(f'{k} {n}' for k, n in sorted(Counter(k for c in diff.values() for k in c).items())) or 'aucun'))
PY
}
contenu "$A" "$B" a10 b5
echo "# fin $(date -u +%FT%TZ)"
