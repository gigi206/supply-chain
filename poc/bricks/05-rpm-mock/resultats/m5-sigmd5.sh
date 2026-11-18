#!/usr/bin/env bash
# Mesure hors ligne : rpm -qp --qf %{SIGMD5} sur un rpm intact et sur une copie au payload altéré (en-tête intact),
# avec le rpm de l'image d'outillage mock-rocky9 (couches du banc local, digest 99790c13), sous unshare -r chroot, sans réseau.
set -euo pipefail
date -u +%Y-%m-%dT%H:%M:%SZ
B=$HOME/.cache/supply-chain-poc/05/banc-image/disque/sha256
D=$HOME/.cache/supply-chain-poc/05/m5-sigmd5
R=$HOME/.cache/supply-chain-poc/08/travail/m4b-05/comparaison/tiree/depot/zlib-1.2.11-40.el9.x86_64.rpm
[ ! -e "$D" ] || { echo "dossier déjà présent : $D" >&2; exit 1; }
mkdir -p "$D/racine/m"
for l in e48fc4d689daa5ec7af47350d996f93d76a138ff7267aed6972feefe3e4526bd fd00cdb1ac39ed07d03836b05bd7c24cf435e68a2b29d63403e5dfc4610ac157; do
  echo "couche $l : sha256 $(sha256sum < "$B/$l" | cut -c1-64) ; type $(file -b "$B/$l" | cut -c1-40)"
done
unshare -r bash -c 'for l in "$@"; do tar -xzf "$l" -C "'"$D"'/racine" --no-same-owner --exclude="dev/*" 2>/dev/null || echo "tar code $? (fichiers spéciaux ignorés)"; done' _ "$B/e48fc4d689daa5ec7af47350d996f93d76a138ff7267aed6972feefe3e4526bd" "$B/fd00cdb1ac39ed07d03836b05bd7c24cf435e68a2b29d63403e5dfc4610ac157"
[ -x "$D/racine/usr/bin/rpm" ] || { echo "rpm absent du rootfs" >&2; exit 1; }
cp "$R" "$D/racine/m/intact.rpm"; cp "$R" "$D/racine/m/payload.rpm"
t=$(stat -c %s "$D/racine/m/payload.rpm"); o=$((t - 4096))
python3 -I - "$D/racine/m/payload.rpm" "$o" <<'PY'
import sys
f, o = sys.argv[1], int(sys.argv[2])
with open(f, 'r+b') as h:
    h.seek(o); b = h.read(1); h.seek(o); h.write(bytes([b[0] ^ 0xff]))
print(f'octet {o} inversé (taille du fichier inchangée)')
PY
echo "sha256 intact $(sha256sum < "$D/racine/m/intact.rpm" | cut -c1-16)… ; altéré $(sha256sum < "$D/racine/m/payload.rpm" | cut -c1-16)… ; cmp : $(cmp "$D/racine/m/intact.rpm" "$D/racine/m/payload.rpm" 2>&1 | head -1)"
q() { unshare -rn chroot "$D/racine" /usr/bin/rpm "$@"; }
echo "rpm de l'image : $(q --version)"
for f in intact payload; do
  r=0; s=$(q -qp --qf '%{SIGMD5}' /m/$f.rpm 2> "$D/$f.err") || r=$?
  echo "$f : rpm -qp SIGMD5 = $s ; code $r ; stderr $(wc -l < "$D/$f.err") ligne(s) : $(head -c 200 "$D/$f.err" | tr '\n' ' ')"
done
for f in intact payload; do
  r=0; k=$(q -Kv /m/$f.rpm 2>&1) || r=$?
  echo "$f : rpm -Kv code $r :"; echo "$k" | sed 's/^/    /'
done
date -u +%Y-%m-%dT%H:%M:%SZ
