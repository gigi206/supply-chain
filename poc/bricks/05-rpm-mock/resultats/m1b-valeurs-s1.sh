#!/usr/bin/env bash
# Brique 05, M1b : relevé en lecture seule, le 19/11/2026, avant la question des valeurs de la carte. Pour les deux archives de S1
# (racine.tar, boot-racine.tar) et les couches des deux registres de banc locaux : membre racine (premier membre, nom, mode) et
# membre etc/machine-id (taille, mode ; contenu jamais lu). Les deux faits d'archive ont été vus une première fois par un tar -tvf
# non archivé juste avant l'écriture de ce script. Aucune archive n'est écrite. Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-valeurs-s1.sh > poc/bricks/05-rpm-mock/resultats/m1b-valeurs-s1.log 2>&1
set -euo pipefail
export LC_ALL=C
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05   # jamais listé : racine.tar, boot-racine.tar, boot-racine.sha256 seuls lus
B=$HOME/.cache/supply-chain-poc/05
echo "# m1b-valeurs-s1.sh, début $(date -u +%FT%TZ)"
s=$(sha256sum < "$T/boot-racine.tar" | cut -c1-64)
[ "$s" = "$(cat "$T/boot-racine.sha256")" ] && echo "OK   boot-racine.tar : sha256 égal à boot-racine.sha256 ($s)" || { echo "KO   boot-racine.tar : sha256 $s" >&2; exit 1; }
echo "racine.tar : sha256 $(sha256sum < "$T/racine.tar" | cut -c1-64)"
c=()
for f in "$B"/banc-image/disque/sha256/* "$B"/banc-boot-image/disque/sha256/*; do
  [ "$(stat -c %s "$f")" -gt 52428800 ] || continue
  [ "$(sha256sum < "$f" | cut -c1-64)" = "$(basename "$f")" ] && echo "OK   blob $(basename "$(dirname "$(dirname "$(dirname "$f")")")")/$(basename "$f" | cut -c1-16) : $(stat -c %s "$f") octets, sha256 = nom" \
    || { echo "KO   blob $f : sha256 différent du nom" >&2; exit 1; }
  c+=("$f")
done
python3 -I - "$T/racine.tar" "$T/boot-racine.tar" "${c[@]}" <<'PY'
import sys, tarfile, os
for p in sys.argv[1:]:
    nom = os.path.basename(p) if p.endswith('.tar') else p.split('/05/')[1].split('/')[0] + '/couche ' + os.path.basename(p)[:16]
    with tarfile.open(p, 'r:*') as t:
        membres = t.getmembers()
    m0 = membres[0]
    racine = [m for m in membres if m.name in ('.', './', '')]
    mid = [m for m in membres if m.name.lstrip('./') == 'etc/machine-id']
    print(f'{nom} : {len(membres)} membres ; premier {m0.name!r} mode {oct(m0.mode)} ; membre racine : '
          + (', '.join(f'{m.name!r} mode {oct(m.mode)}' for m in racine) or 'aucun'))
    for m in mid:
        print(f'     etc/machine-id : {m.name!r}, {m.size} octet(s), mode {oct(m.mode)}, type {"fichier" if m.isfile() else m.type!r}')
    if not mid:
        print('     etc/machine-id : absent')
PY
echo "# fin $(date -u +%FT%TZ)"
