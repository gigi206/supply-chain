#!/usr/bin/env bash
# Brique 05, M1b, point 1 A (carte de M1b, décision « Oui » du 18/11/2026) : deux dnf --installroot des mêmes rpm locaux dans deux
# dossiers neufs, puis comparaison des deux arbres et des deux archives. Hôte seul, hors ligne (unshare -n), sans cluster ni Zot.
# Outils : rpm et dnf-3 de l'image d'outillage mock-rocky9 (couches du banc local de image, digest 99790c13), sous chroot, dans un
# espace de noms utilisateur à plage complète (unshare --map-auto --map-root-user), pour que rpm puisse poser les propriétaires.
# rpm : les 222 rpm du buildroot du verrou (poc/packaging/verrou-rpm.json), pris dans la fermeture tirée par la comparaison de
# M4b (liens durs, lecture seule). Prédictions : m1b-predictions.md, commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-repro.sh > poc/bricks/05-rpm-mock/resultats/m1b-repro.log 2>&1
set -euo pipefail
r=$(cd "$(dirname "$0")" && pwd)
V=$r/../../../packaging/verrou-rpm.json
B=$HOME/.cache/supply-chain-poc/05/banc-image/disque/sha256
DEP=$HOME/.cache/supply-chain-poc/08/travail/m4b-05/comparaison/tiree/depot
D=$HOME/.cache/supply-chain-poc/05/m1b-repro-$(date -u +%Y%m%dT%H%M%SZ)   # un dossier par passage : jamais effacé ni réutilisé
COUCHES=(e48fc4d689daa5ec7af47350d996f93d76a138ff7267aed6972feefe3e4526bd fd00cdb1ac39ed07d03836b05bd7c24cf435e68a2b29d63403e5dfc4610ac157)
ns() { unshare --map-auto --map-root-user -n "$@"; }
echo "# m1b-repro.sh, début $(date -u +%FT%TZ)"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }
echo "verrou : sha256 $(sha256sum < "$V" | cut -c1-64)"
echo "correspondance des uid dans l'espace de noms : $(ns cat /proc/self/uid_map | tr -s ' ' | tr '\n' ';')"
mkdir -p "$D/racine/m"   # avant l'extraction : la racine de la couche est en 0555
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
q() { ns chroot "$D/racine" "$@"; }
archive_brute() { ns tar --sort=name --format=posix --xattrs --xattrs-include='*' --numeric-owner -C "$D/racine/m/i$1" -cf - . 2>/dev/null | sha256sum | cut -c1-64; }
archive_norm() { ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --xattrs --xattrs-include='*' --numeric-owner -C "$D/racine/m/i$1" -cf - . 2>/dev/null | sha256sum | cut -c1-64; }
echo "outils : $(q /usr/bin/rpm --version) ; dnf $(q /usr/bin/dnf-3 --version 2>/dev/null | head -1)"
for i in 1 2; do
  echo "## installation $i, début $(date -u +%FT%TZ)"
  rc=0
  # shellcheck disable=SC2046
  q /usr/bin/dnf-3 -y --installroot=/m/i$i --releasever=9 --setopt=reposdir=/m/aucun \
    --disablerepo='*' install $(cat "$D/racine/m/liste") > "$D/dnf-$i.log" 2>&1 || rc=$?
  echo "dnf code $rc ; $(wc -l < "$D/dnf-$i.log") lignes de journal ; dernières :"
  tail -n 4 "$D/dnf-$i.log" | sed 's/^/     /'
  echo "lignes « scriptlet », « warning » ou « error » (casse ignorée) : $(grep -Eci 'scriptlet|(^|[^-[:alnum:]])(warning|error)' "$D/dnf-$i.log" || true)"
  grep -Ei 'scriptlet|(^|[^-[:alnum:]])(warning|error)' "$D/dnf-$i.log" | head -n 10 | cut -c1-200 | sed 's/^/     /' || true
  [ "$rc" = 0 ] || { echo "KO   installation $i en échec" >&2; exit 1; }
  echo "paquets installés : $(q /usr/bin/rpm --root=/m/i$i -qa | wc -l) ; liste triée : sha256 $(q /usr/bin/rpm --root=/m/i$i -qa --qf '%{NEVRA}\n' | sort | sha256sum | cut -c1-64)"
  echo "INSTALLTIME de bash : $(q /usr/bin/rpm --root=/m/i$i -q --qf '%{INSTALLTIME}' bash)"
  echo "dev/null dans la racine installée : $(ns stat -c %F "$D/racine/m/i$i/dev/null" 2>/dev/null || echo absent)"
  echo "cache de dnf : $(ns du -s --block-size=1 "$D/racine/m/i$i/var/cache/dnf" 2>/dev/null | cut -f1 || echo absent) octets sous var/cache/dnf ; m/ dans la racine installée : $([ -e "$D/racine/m/i$i/m" ] && echo présent || echo absent)"
  echo "archive brute (options de s1.sh, racine), passe a : sha256 $(archive_brute "$i")"
  echo "archive normalisée (sans atime ni ctime), passe a : sha256 $(archive_norm "$i")"
  echo "## installation $i, fin $(date -u +%FT%TZ)"
  [ "$i" = 2 ] || sleep 5   # heures d'installation distinctes, à la seconde
done
echo "## témoin de l'archive : arbre 1 archivé de nouveau, après l'installation 2"
echo "archive brute, arbre 1, passe b : sha256 $(archive_brute 1)"
echo "archive normalisée, arbre 1, passe b : sha256 $(archive_norm 1)"
echo "## comparaison des deux arbres"
ns python3 -I "$r/m1b-repro-comparer.py" "$D/racine/m/i1" "$D/racine/m/i2"
echo "# fin $(date -u +%FT%TZ)"
