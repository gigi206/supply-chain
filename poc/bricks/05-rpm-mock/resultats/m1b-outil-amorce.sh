#!/usr/bin/env bash
# Brique 05, M1b, point 1 A, banc de l'outillage avec les outils de l'amorce : la racine de rockylinux:9.8 (ed654c69), celle qui a
# servi d'outils à l'étape racine de S1, remplace la racine d'outils de 99790c13 ; umask 022 fixé dans chaque commande. (18/11/2026)
# Hôte seul, entièrement hors ligne : aucun téléchargement.
#   1. Clés : empreintes contrôlées (Rocky : s1.sh ; EPEL : relevé de m1b-sources). Miroir partiel du banc de 20:57:14 UTC copié dans
#      un dossier neuf, puis revérifié : repomd.xml égaux aux copies du 18/11 (m1b-sources), signature gpgv de vault, métadonnées
#      au sha256 de repomd.xml, 199 rpm au sha256 de la liste épinglée.
#   2. Couche de l'amorce (cache OCI de s1.sh amorce) : sha256 contrôlé, extraite dans le dossier neuf. Témoins lus dans la racine
#      d'outils : umask, %_install_langs, versions de rpm et dnf. rpm -K des 199 rpm avec les deux clés ; borne S par rpm -qp.
#   3. Installations : forme de l'étape racine de S1 (même dnf.conf que le banc de 20:57:14 UTC, même commande dnf que s1.sh
#      l. 366, mêmes noms), miroir en file://, cache propre à chaque installation, 5 s d'écart, SOURCE_DATE_EPOCH=S, container=oci
#      (Env de l'image). i8 et i9 : umask 022 ; témoin i10 : umask 022, /etc/rpm/macros.image-language-conf de la racine d'outils
#      masqué (/dev/null lié dessus) ; témoin i11 : umask 0002.
#   4. Archives bornées à S, exclusions du ré-archivage de 21:08:52 UTC (dont ./etc/machine-id) : a8, a9, a8b (témoin), a10, a11 ;
#      comparaisons ; contenu seul (sans dates ni en-têtes pax) : a8 contre racine.tar de S1, a10 contre a8, a11 contre a8.
# Prédictions : m1b-predictions.md (section du banc avec les outils de l'amorce), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-outil-amorce.sh > poc/bricks/05-rpm-mock/resultats/m1b-outil-amorce.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
LISTE=$r/m1b-listes-outillage.txt
SRC=$HOME/.cache/supply-chain-poc/05/m1b-sources-20261118T195832Z   # relevé des sources du 18/11 : lecture seule
LD=$HOME/.cache/supply-chain-poc/05/m1b-listes-20261118T204944Z    # relevé des listes : lecture seule
MIR=$HOME/.cache/supply-chain-poc/05/m1b-outil-20261118T205714Z/outils/m/miroir   # miroir du banc de 20:57:14 UTC : lecture seule
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux   # cache de s1.sh amorce : lecture seule
M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d                   # s1.sh, l. 169
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05                    # jamais listé : racine.tar seule y est lue
U=$(date -u +%Y%m%dT%H%M%SZ)
D=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-$U               # dossier neuf, jamais effacé ni réutilisé
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D                   # s1.sh, l. 164
DEPOTS=("baseos98 vault98-baseos98 $FP_ROCKY" "appstream98 vault98-appstream98 $FP_ROCKY" "epel9 archive-9.8 -")
NOMS="mock-6.9-1.el9 mock-core-configs-45.2-1.el9 podman-5.8.2-8.el9_8 skopeo-1.22.2-9.el9_8 rocky-release shadow-utils"   # étape racine de S1
ns() { unshare --map-auto --map-root-user -n "$@"; }
# racine d'outils : /dev lié, /proc monté, HOME=/root, umask donné, macro de langue masquée ou non, dans un espace de montage
# propre qui disparaît avec la commande ; q : umask 022, macro en place
qx() { local u=$1 k=$2; shift 2; ns -m -p --fork bash -c 'umask "$1"; k=$2; shift 2
  [ "$k" = 0 ] || mount --bind /dev/null "$1/etc/rpm/macros.image-language-conf" || exit 96
  mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || exit 97; export HOME=/root; exec chroot "$@"' _ "$u" "$k" "$D/outils" "$@"; }
q() { qx 022 0 "$@"; }
masque() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
echo "# m1b-outil-amorce.sh, début $(date -u +%FT%TZ)"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }
[ -s "$LISTE" ] && [ -s "$LD/outillage.qa" ] && [ -s "$T/racine.tar" ] && [ -d "$MIR" ] || { echo "KO   liste, relevé des listes, miroir ou racine.tar absent" >&2; exit 1; }
echo "liste épinglée : $(grep -vc '^#' "$LISTE") rpm, sha256 $(sha256sum < "$LISTE" | cut -c1-64)"
echo "umask de l'hôte (pour mémoire) : $(umask)"
mkdir -p "$D/outils/m" "$D/archives"   # m créé avant l'extraction de la couche

echo "## 1. clés et miroir partiel"
mkdir -p "$D/outils/m/cles"
fp() { gpg --batch --with-colons --show-keys "$1" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}'; }
fe=$(sed -n "s/^OK   clé d'EPEL 9 : \([0-9A-F]*\) .*/\1/p" "$r/m1b-sources.log" | head -1)
for k in "RPM-GPG-KEY-Rocky-9 $FP_ROCKY" "RPM-GPG-KEY-EPEL-9 $fe"; do
  set -- $k
  f=$(fp "$SRC/$1")
  [ -n "$2" ] && [ "$f" = "$2" ] && echo "OK   $1 : empreinte $f" || { echo "KO   $1 : empreinte $f (attendue : ${2:-vide})" >&2; exit 1; }
  cp "$SRC/$1" "$D/outils/m/cles/$1"
  gpg --no-default-keyring --keyring "$D/cles.gpg" --batch --quiet --import "$SRC/$1" 2>/dev/null
done
cp -a "$MIR" "$D/outils/m/miroir"
echo "miroir copié depuis le banc de 20:57:14 UTC : $(find "$D/outils/m/miroir" -type f | wc -l) fichier(s)"
for x in "${DEPOTS[@]}"; do
  set -- $x
  R=$D/outils/m/miroir/$1/repodata
  s=$(sha256sum < "$R/repomd.xml" | cut -c1-64); s0=$(sha256sum < "$SRC/$2.repomd.xml" | cut -c1-64)
  [ "$s" = "$s0" ] && echo "OK   $1 : repomd.xml égal à la copie du 18/11 ($2), sha256 $s" || { echo "KO   $1 : repomd.xml $s, copie $s0" >&2; exit 1; }
  if [ "$3" != - ]; then
    v=$(gpgv --keyring "$D/cles.gpg" --status-fd 1 "$R/repomd.xml.asc" "$R/repomd.xml" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' || true)
    [ "$v" = "$3" ] && echo "OK   $1 : signature de repomd.xml valide ($v)" || { echo "KO   $1 : signataire ${v:-aucun}" >&2; exit 1; }
  else
    echo "$1 : repomd.xml non signé (instantané d'EPEL) ; ancre : sha256 de la copie du 18/11 et de la liste épinglée"
  fi
  python3 -I - "$D/outils/m/miroir/$1" <<'PY'
import hashlib, os, sys, xml.etree.ElementTree as E
m = sys.argv[1]; n = {'r': 'http://linux.duke.edu/metadata/repo'}; k = 0
for d in E.parse(f'{m}/repodata/repomd.xml').getroot().findall('r:data', n):
    if d.get('type').endswith('_db'): continue   # bases sqlite de createrepo : non téléchargées au banc de 20:57:14 UTC
    h = d.find('r:location', n).get('href'); c = d.find('r:checksum', n)
    assert c.get('type') == 'sha256', c.get('type')
    assert hashlib.sha256(open(f'{m}/{h}', 'rb').read()).hexdigest() == c.text, h
    k += 1
print(f'OK   {os.path.basename(m)} : {k} fichier(s) de métadonnées, sha256 conformes à repomd.xml')
PY
done
mkdir -p "$D/outils/m/rpms"
n=0
while read -r dep f s; do
  [ "${dep:0:1}" = "#" ] && continue
  p=$(find "$D/outils/m/miroir/$dep" -type f -name "$f" | head -1)
  [ -n "$p" ] && [ "$(sha256sum < "$p" | cut -c1-64)" = "$s" ] || { echo "KO   $dep $f : absent ou sha256 différent" >&2; exit 1; }
  ln "$p" "$D/outils/m/rpms/$f"; n=$((n + 1))
done < "$LISTE"
echo "OK   rpm du miroir au sha256 de la liste épinglée : $n, $(cat "$D"/outils/m/rpms/*.rpm | wc -c) octets"

echo "## 2. racine d'outils de l'amorce, témoins, signatures et borne S"
[ "$(sha256sum < "$O/blobs/sha256/$M" | cut -c1-64)" = "$M" ] && echo "OK   manifeste ed654c69 : sha256 égal" || { echo "KO   manifeste" >&2; exit 1; }
L=$(python3 -I -c 'import json, sys; j = json.load(open(sys.argv[1])); assert len(j["layers"]) == 1; print(j["layers"][0]["digest"][7:])' "$O/blobs/sha256/$M")
[ "$(sha256sum < "$O/blobs/sha256/$L" | cut -c1-64)" = "$L" ] && echo "OK   couche ${L:0:12} : sha256 égal, $(stat -c %s "$O/blobs/sha256/$L") octets" || { echo "KO   couche" >&2; exit 1; }
ns tar -xf "$O/blobs/sha256/$L" -C "$D/outils" --numeric-owner --exclude='dev/*' --exclude='./m' 2>/dev/null || echo "tar code $? (fichiers spéciaux ignorés)"
ns mkdir -p "$D/outils/dev" "$D/outils/proc"
[ -x "$D/outils/usr/bin/rpm" ] && [ -x "$D/outils/usr/bin/dnf" ] || { echo "KO   rpm ou dnf absent de la racine d'outils" >&2; exit 1; }
echo "témoin umask (dans la racine d'outils) : $(q bash -c umask)"
echo "témoin umask de i11 : $(qx 0002 0 bash -c umask)"
echo "témoin %_install_langs (dans la racine d'outils) : [$(q /usr/bin/rpm -E '%_install_langs')]"
echo "témoin %_install_langs de i10 (macros.image-language-conf masqué) : [$(qx 022 1 /usr/bin/rpm -E '%_install_langs')]"
echo "outils : $(q /usr/bin/rpm --version) ; dnf $(q /usr/bin/dnf --version 2>/dev/null | head -1)"
q bash -c 'rpm -q --qf "%{NEVRA}\n" rpm dnf python3-dnf libsolv libdnf 2>&1' | sed 's/^/     /'
mkdir -p "$D/outils/m/clesdb"
for k in RPM-GPG-KEY-Rocky-9 RPM-GPG-KEY-EPEL-9; do q /usr/bin/rpm --dbpath /m/clesdb --import "/m/cles/$k"; done
q bash -c 'rpm --dbpath /m/clesdb -K /m/rpms/*.rpm' > "$D/k.log" 2>&1 || true
echo "rpm -K : $(grep -c -E 'digests signatures OK$' "$D/k.log") « digests signatures OK » sur $(ls "$D/outils/m/rpms" | wc -l)"
grep -v -E 'digests signatures OK$' "$D/k.log" | head -n 5 || true
E=$(q bash -c 'rpm -qp --nosignature --qf "%{BUILDTIME}\n" /m/rpms/*.rpm' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)
F=$(q bash -c 'rpm -qp --nosignature --qf "[%{FILEMTIMES}\n]" /m/rpms/*.rpm' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)
S=$(( E > F ? E : F ))
echo "S = $S ($(date -u -d "@$S" +%FT%TZ))"

echo "## 3. installations"
cat > "$D/outils/m/dnf.conf" <<'EOF'
[main]
gpgcheck=1
install_weak_deps=0
keepcache=1
cachedir=/m/cache
reposdir=/m/aucun
tsflags=nodocs
[baseos98]
name=Rocky 9.8 BaseOS
baseurl=file:///m/miroir/baseos98/
repo_gpgcheck=1
gpgkey=file:///m/cles/RPM-GPG-KEY-Rocky-9
[appstream98]
name=Rocky 9.8 AppStream
baseurl=file:///m/miroir/appstream98/
repo_gpgcheck=1
gpgkey=file:///m/cles/RPM-GPG-KEY-Rocky-9
[epel9]
name=EPEL 9
baseurl=file:///m/miroir/epel9/
repo_gpgcheck=0
gpgkey=file:///m/cles/RPM-GPG-KEY-EPEL-9
EOF
mkdir -p "$D/outils/m/aucun"
echo "dnf.conf : sha256 $(sha256sum < "$D/outils/m/dnf.conf" | cut -c1-64)"
for x in "8 022 0" "9 022 0" "10 022 1" "11 0002 0"; do
  set -- $x; i=$1
  echo "## installation $i (umask $2, macro de langue masquée : $3), début $(date -u +%FT%TZ)"
  rc=0
  # shellcheck disable=SC2086
  qx "$2" "$3" /usr/bin/env container=oci SOURCE_DATE_EPOCH="$S" /usr/bin/dnf -y -c /m/dnf.conf --setopt=reposdir=/m/aucun --setopt=cachedir=/m/cache-$i \
    --installroot=/m/i$i --releasever=9 install $NOMS > "$D/dnf-$i.log" 2>&1 || rc=$?
  echo "dnf code $rc ; $(wc -l < "$D/dnf-$i.log") lignes de journal"
  echo "lignes « scriptlet », « warning » ou « error » (casse ignorée) : $(grep -Eci 'scriptlet|(^|[^-[:alnum:]])(warning|error)' "$D/dnf-$i.log" || true)"
  grep -Ei 'importing|import|clé|key' "$D/dnf-$i.log" | grep -vi 'fingerprint\|empreinte' | head -n 6 | masque | sed 's/^/     /' || true
  [ "$rc" = 0 ] || { tail -n 15 "$D/dnf-$i.log" | masque; echo "KO   installation $i en échec" >&2; exit 1; }
  q /usr/bin/rpm --root=/m/i$i -qa --qf '%{NAME}|%{EPOCHNUM}|%{VERSION}|%{RELEASE}|%{ARCH}|%{INSTALLTIME}|%{INSTALLTID}\n' | sort > "$D/i$i.qa"
  echo "## installation $i, fin $(date -u +%FT%TZ)"
  [ "$i" = 11 ] || sleep 5
done
python3 -I - "$D" "$LD/outillage.qa" <<'PY'
import sys
d, ref = sys.argv[1:]
cle = lambda x: '|'.join(x[:5])
r = {cle(x.split('|')) for x in open(ref, encoding='utf-8').read().split('\n') if x and not x.startswith('gpg-pubkey|')}
print(f'référence : {len(r)} NEVRA hors gpg-pubkey (base de racine.tar)')
for i in (8, 9, 10, 11):
    e = [x.split('|') for x in open(f'{d}/i{i}.qa', encoding='utf-8').read().split('\n') if x]
    g = [x for x in e if x[0] == 'gpg-pubkey']; n = {cle(x) for x in e if x[0] != 'gpg-pubkey'}
    print(f'i{i} : {len(e)} entrée(s), dont {len(g)} gpg-pubkey ; NEVRA égaux à la référence : {"oui" if n == r else "non"}'
          f' (en plus : {len(n - r)}, en moins : {len(r - n)})')
PY

echo "## 4. archives bornées à S"
EXCL=(--exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id)
archive() { # arbre fichier
  ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
    --xattrs --xattrs-include='*' --numeric-owner "${EXCL[@]}" -C "$1" -cf "$2" . 2> "$2.err" || echo "tar code $? ($(wc -l < "$2.err") lignes d'erreur)"
  echo "$(basename "$2") : $(stat -c %s "$2") octets, $(tar -tf "$2" | wc -l) membres, sha256 $(sha256sum < "$2" | cut -c1-64)"
}
archive "$D/outils/m/i8" "$D/archives/a8.tar"
archive "$D/outils/m/i9" "$D/archives/a9.tar"
archive "$D/outils/m/i8" "$D/archives/a8b.tar"
archive "$D/outils/m/i10" "$D/archives/a10.tar"
archive "$D/outils/m/i11" "$D/archives/a11.tar"
echo "## 4a. i8 et i9"
cmp -s "$D/archives/a8.tar" "$D/archives/a9.tar" && echo "OK   a8.tar et a9.tar identiques octet à octet" || { echo "ÉCART a8.tar et a9.tar différents"; python3 -I "$r/m1b-repro2-comparer.py" "$D/archives/a8.tar" "$D/archives/a9.tar"; }
cmp -s "$D/archives/a8.tar" "$D/archives/a8b.tar" && echo "OK   témoin : a8.tar et a8b.tar identiques octet à octet" || echo "ÉCART témoin : a8.tar et a8b.tar différents"
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
echo "## 4b. contenu seul : a8 contre racine.tar de S1"
contenu "$D/archives/a8.tar" "$T/racine.tar" a8 racine.tar
echo "## 4c. témoin de langue : a10 (macro masquée) contre a8"
contenu "$D/archives/a10.tar" "$D/archives/a8.tar" a10 a8
echo "## 4d. témoin de umask : a11 (umask 0002) contre a8"
contenu "$D/archives/a11.tar" "$D/archives/a8.tar" a11 a8
echo "arbres et archives laissés dans $D"
echo "# fin $(date -u +%FT%TZ)"
