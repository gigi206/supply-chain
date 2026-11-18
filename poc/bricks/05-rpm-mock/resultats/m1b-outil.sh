#!/usr/bin/env bash
# Brique 05, M1b, point 1 A, banc de l'outillage : deux dnf --installroot des paquets épinglés de l'outillage, sous SOURCE_DATE_EPOCH,
# depuis un miroir partiel (métadonnées amont, 199 rpm de la liste épinglée) donnent-ils la même archive bornée ? (18/11/2026)
# Hôte seul. Lecture publique pour le miroir (vault/rocky/9.8, pub/archive/epel/9.8), puis hors ligne (unshare -n) pour le reste.
#   1. Clés : empreintes contrôlées (Rocky : s1.sh ; EPEL : relevé de m1b-sources). repomd.xml des trois dépôts téléchargés et comparés
#      aux copies du 18/11 (m1b-sources) ; signature gpgv exigée pour vault ; relecture de l'instantané archive/epel/9.8.
#   2. Toutes les métadonnées citées par repomd.xml, sha256 contrôlé ; les 199 rpm de m1b-listes-outillage.txt, sha256 = liste
#      = primary ; rpm -K avec les deux clés.
#   3. Borne S = max(BUILDTIME, FILEMTIMES) par rpm -qp sur les 199 fichiers.
#   4. Racine d'outils neuve (couches de 99790c13). Installations i5 et i6 : forme de l'étape racine de S1 (mêmes options de dnf,
#      mêmes noms, repo_gpgcheck sur vault), miroir en file://, cache propre à chaque installation, 5 s d'écart ; témoin i7 :
#      install des 199 fichiers locaux, dépôts coupés.
#   5. Archives bornées à S (exclusions du troisième banc, plus le cache de dnf) : a5, a6, a5b (témoin), a7 ; comparaisons ;
#      contenu seul (sans dates ni en-têtes pax) de a5 contre racine.tar de S1.
# Prédictions : m1b-predictions.md (section du banc de l'outillage), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-outil.sh > poc/bricks/05-rpm-mock/resultats/m1b-outil.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
LISTE=$r/m1b-listes-outillage.txt
SRC=$HOME/.cache/supply-chain-poc/05/m1b-sources-20261118T195832Z   # relevé des sources du 18/11 : lecture seule
LD=$HOME/.cache/supply-chain-poc/05/m1b-listes-20261118T204944Z    # relevé des listes : lecture seule
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05                    # jamais listé : racine.tar seule y est lue
B=$HOME/.cache/supply-chain-poc/05/banc-image/disque/sha256
U=$(date -u +%Y%m%dT%H%M%SZ)
D=$HOME/.cache/supply-chain-poc/05/m1b-outil-$U                      # dossier neuf, jamais effacé ni réutilisé
COUCHES=(e48fc4d689daa5ec7af47350d996f93d76a138ff7267aed6972feefe3e4526bd fd00cdb1ac39ed07d03836b05bd7c24cf435e68a2b29d63403e5dfc4610ac157)
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D                   # s1.sh, l. 164
VAULT=https://dl.rockylinux.org/vault/rocky/9.8
EPA=https://dl.fedoraproject.org/pub/archive/epel/9.8/Everything/x86_64
DEPOTS=("baseos98 $VAULT/BaseOS/x86_64/os vault98-baseos98 $FP_ROCKY" "appstream98 $VAULT/AppStream/x86_64/os vault98-appstream98 $FP_ROCKY"
        "epel9 $EPA archive-9.8 -")
NOMS="mock-6.9-1.el9 mock-core-configs-45.2-1.el9 podman-5.8.2-8.el9_8 skopeo-1.22.2-9.el9_8 rocky-release shadow-utils"   # étape racine de S1
ns() { unshare --map-auto --map-root-user -n "$@"; }
# correction (18/11/2026, après le passage de 20:54:47 UTC, m1b-outil-1.log et m1b-outil-diag.log) : sans /proc, gpgconf ne lit pas
# /proc/self/exe et gpgme rejette le moteur (repo_gpgcheck). La racine d'outils reçoit /dev (lié) et /proc, dans un espace de
# montage propre qui disparaît avec la commande ; HOME=/root, au lieu du HOME de l'hôte.
q() { ns -m -p --fork bash -c 'mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || exit 97; export HOME=/root; exec chroot "$@"' _ "$D/outils" "$@"; }
get() { curl -fsSL --max-time 300 -o "$1" "$2"; }
echo "# m1b-outil.sh, début $(date -u +%FT%TZ)"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }
[ -s "$LISTE" ] && [ -s "$LD/outillage.qa" ] && [ -s "$T/racine.tar" ] || { echo "KO   liste, relevé des listes ou racine.tar absent" >&2; exit 1; }
echo "liste épinglée : $(grep -vc '^#' "$LISTE") rpm, sha256 $(sha256sum < "$LISTE" | cut -c1-64)"
mkdir -p "$D/outils/m/miroir" "$D/outils/m/rpms" "$D/outils/m/cles" "$D/outils/m/aucun" "$D/archives"

echo "## 1. clés et repomd.xml"
fp() { gpg --batch --with-colons --show-keys "$1" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}'; }
fe=$(sed -n "s/^OK   clé d'EPEL 9 : \([0-9A-F]*\) .*/\1/p" "$r/m1b-sources.log" | head -1)
for k in "RPM-GPG-KEY-Rocky-9 $FP_ROCKY" "RPM-GPG-KEY-EPEL-9 $fe"; do
  set -- $k
  f=$(fp "$SRC/$1")
  [ -n "$2" ] && [ "$f" = "$2" ] && echo "OK   $1 : empreinte $f" || { echo "KO   $1 : empreinte $f (attendue : ${2:-vide})" >&2; exit 1; }
  cp "$SRC/$1" "$D/outils/m/cles/$1"
  gpg --no-default-keyring --keyring "$D/cles.gpg" --batch --quiet --import "$SRC/$1" 2>/dev/null
done
for x in "${DEPOTS[@]}"; do
  set -- $x
  mkdir -p "$D/outils/m/miroir/$1/repodata"
  get "$D/outils/m/miroir/$1/repodata/repomd.xml" "$2/repodata/repomd.xml"
  s=$(sha256sum < "$D/outils/m/miroir/$1/repodata/repomd.xml" | cut -c1-64); s0=$(sha256sum < "$SRC/$3.repomd.xml" | cut -c1-64)
  echo "$1 : repomd.xml sha256 $s ; copie du 18/11 ($3) : $s0"
  [ "$s" = "$s0" ] && echo "OK   $1 : repomd.xml égal à la copie du 18/11" || { echo "KO   $1 : repomd.xml a changé depuis le 18/11" >&2; exit 1; }
  if [ "$4" != - ]; then
    get "$D/outils/m/miroir/$1/repodata/repomd.xml.asc" "$2/repodata/repomd.xml.asc"
    v=$(gpgv --keyring "$D/cles.gpg" --status-fd 1 "$D/outils/m/miroir/$1/repodata/repomd.xml.asc" "$D/outils/m/miroir/$1/repodata/repomd.xml" 2>/dev/null \
      | awk '$2 == "VALIDSIG" {print $NF}' || true)
    [ "$v" = "$4" ] && echo "OK   $1 : signature de repomd.xml valide ($v)" || { echo "KO   $1 : signataire ${v:-aucun}" >&2; exit 1; }
  else
    echo "$1 : repomd.xml non signé (instantané d'EPEL) ; ancre : sha256 de la copie du 18/11 et de la liste épinglée"
  fi
done

echo "## 2. métadonnées et rpm du miroir partiel"
for x in "${DEPOTS[@]}"; do
  set -- $x
  n=0; t=0
  while read -r ty h s; do
    mkdir -p "$(dirname "$D/outils/m/miroir/$1/$h")"
    get "$D/outils/m/miroir/$1/$h" "$2/$h"
    c=$(sha256sum < "$D/outils/m/miroir/$1/$h" | cut -c1-64)
    [ "$c" = "$s" ] || { echo "KO   $1 : $ty ($h) : sha256 $c, repomd $s" >&2; exit 1; }
    n=$((n + 1)); t=$((t + $(stat -c %s "$D/outils/m/miroir/$1/$h")))
    echo "     $1 : $ty, $(stat -c %s "$D/outils/m/miroir/$1/$h") octets, sha256 conforme"
  done < <(python3 -I - "$D/outils/m/miroir/$1/repodata/repomd.xml" <<'PY'
import sys, xml.etree.ElementTree as E
n = {'r': 'http://linux.duke.edu/metadata/repo'}
for d in E.parse(sys.argv[1]).getroot().findall('r:data', n):
    if d.get('type').endswith('_db'):   # bases sqlite de createrepo, que dnf 4 ne lit pas : citées, non téléchargées
        print('écarté', d.get('type'), '-', file=sys.stderr); continue
    c = d.find('r:checksum', n)
    assert c.get('type') == 'sha256', c.get('type')
    print(d.get('type'), d.find('r:location', n).get('href'), c.text)
PY
)
  echo "OK   $1 : $n fichier(s) de métadonnées, $t octets, sha256 conformes à repomd.xml"
done
python3 -I - "$D/outils/m/miroir" "$LISTE" > "$D/a-telecharger" <<'PY'
import gzip, lzma, os, sys, xml.etree.ElementTree as E
m, liste = sys.argv[1:]
nr = {'r': 'http://linux.duke.edu/metadata/repo'}; nc = '{http://linux.duke.edu/metadata/common}'
pk = {}
for depot in sorted(os.listdir(m)):
    for d in E.parse(f'{m}/{depot}/repodata/repomd.xml').getroot().findall('r:data', nr):
        if d.get('type') != 'primary': continue
        h = d.find('r:location', nr).get('href'); f = f'{m}/{depot}/{h}'
        o = gzip.open if h.endswith('.gz') else lzma.open if h.endswith('.xz') else None
        assert o, h
        for _, p in E.iterparse(o(f)):
            if p.tag == nc + 'package':
                loc = p.find(nc + 'location').get('href')
                pk[(depot, loc.rsplit('/', 1)[1])] = (loc, p.find(nc + 'checksum').text)
                p.clear()
ko = 0
for l in open(liste, encoding='utf-8'):
    if l.startswith('#'): continue
    depot, f, s = l.split()
    loc, c = pk.get((depot, f), (None, None))
    if c != s:
        ko += 1; print(f'KO {depot} {f} : primary {c}', file=sys.stderr); continue
    print(depot, loc, s)
sys.exit(1 if ko else 0)
PY
echo "OK   199 rpm de la liste trouvés dans les primary, même sha256 : $(wc -l < "$D/a-telecharger")"
for x in "${DEPOTS[@]}"; do set -- $x; echo "$1 $2" ; done > "$D/urls"
n=0; t=0
while read -r dep loc s; do
  u=$(awk -v d="$dep" '$1 == d {print $2}' "$D/urls")
  mkdir -p "$(dirname "$D/outils/m/miroir/$dep/$loc")"
  get "$D/outils/m/miroir/$dep/$loc" "$u/$loc"
  c=$(sha256sum < "$D/outils/m/miroir/$dep/$loc" | cut -c1-64)
  [ "$c" = "$s" ] || { echo "KO   $dep $loc : sha256 $c, attendu $s" >&2; exit 1; }
  ln "$D/outils/m/miroir/$dep/$loc" "$D/outils/m/rpms/${loc##*/}"
  n=$((n + 1)); t=$((t + $(stat -c %s "$D/outils/m/rpms/${loc##*/}")))
done < "$D/a-telecharger"
echo "OK   rpm téléchargés, sha256 égal à la liste et au primary : $n, $t octets"

echo "## 3. racine d'outils, signatures et borne S"
for l in "${COUCHES[@]}"; do
  s=$(sha256sum < "$B/$l" | cut -c1-64)
  [ "$s" = "$l" ] || { echo "KO   couche $l : sha256 $s" >&2; exit 1; }
  echo "OK   couche $l : sha256 égal à son nom"
done
ns bash -c 'for l in "$@"; do tar -xzf "$l" -C "'"$D"'/outils" --numeric-owner --exclude="dev/*" --exclude="./m" 2>/dev/null || echo "tar code $? (fichiers spéciaux ignorés)"; done' _ "${COUCHES[@]/#/$B/}"
[ -x "$D/outils/usr/bin/rpm" ] && [ -x "$D/outils/usr/bin/dnf-3" ] || { echo "KO   rpm ou dnf-3 absent de la racine d'outils" >&2; exit 1; }
echo "outils : $(q /usr/bin/rpm --version) ; dnf $(q /usr/bin/dnf-3 --version 2>/dev/null | head -1)"
mkdir -p "$D/outils/m/clesdb"
for k in RPM-GPG-KEY-Rocky-9 RPM-GPG-KEY-EPEL-9; do q /usr/bin/rpm --dbpath /m/clesdb --import "/m/cles/$k"; done
q bash -c 'rpm --dbpath /m/clesdb -K /m/rpms/*.rpm' > "$D/k.log" 2>&1 || true
echo "rpm -K : $(grep -c -E 'digests signatures OK$' "$D/k.log") « digests signatures OK » sur $(ls "$D/outils/m/rpms" | wc -l)"
grep -v -E 'digests signatures OK$' "$D/k.log" | head -n 5 || true
E=$(q bash -c 'rpm -qp --nosignature --qf "%{BUILDTIME}\n" /m/rpms/*.rpm' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)
F=$(q bash -c 'rpm -qp --nosignature --qf "[%{FILEMTIMES}\n]" /m/rpms/*.rpm' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)
S=$(( E > F ? E : F ))
echo "plus grand BUILDTIME E = $E ($(date -u -d "@$E" +%FT%TZ)) ; plus grande FILEMTIMES F = $F ($(date -u -d "@$F" +%FT%TZ))"
echo "S = $S ($(date -u -d "@$S" +%FT%TZ)) ; porteur de F : $(q bash -c 'rpm -qp --nosignature --qf "[%{FILEMTIMES} %{=NEVRA}\n]" /m/rpms/*.rpm' 2>/dev/null | awk -v f="$F" '$1 == f {print $2}' | sort -u | tr '\n' ' ')"

echo "## 4. installations"
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
echo "dnf.conf : sha256 $(sha256sum < "$D/outils/m/dnf.conf" | cut -c1-64)"
for i in 5 6 7; do
  echo "## installation $i, début $(date -u +%FT%TZ)"
  rc=0
  if [ "$i" = 7 ]; then
    q /usr/bin/env SOURCE_DATE_EPOCH="$S" bash -c 'dnf-3 -y -c /m/dnf.conf --setopt=reposdir=/m/aucun --setopt=cachedir=/m/cache-7 --installroot=/m/i7 --releasever=9 --disablerepo="*" install /m/rpms/*.rpm' > "$D/dnf-$i.log" 2>&1 || rc=$?
  else
    # shellcheck disable=SC2086
    q /usr/bin/env SOURCE_DATE_EPOCH="$S" /usr/bin/dnf-3 -y -c /m/dnf.conf --setopt=reposdir=/m/aucun --setopt=cachedir=/m/cache-$i \
      --installroot=/m/i$i --releasever=9 install $NOMS > "$D/dnf-$i.log" 2>&1 || rc=$?
  fi
  echo "dnf code $rc ; $(wc -l < "$D/dnf-$i.log") lignes de journal"
  echo "lignes « scriptlet », « warning » ou « error » (casse ignorée) : $(grep -Eci 'scriptlet|(^|[^-[:alnum:]])(warning|error)' "$D/dnf-$i.log" || true)"
  grep -Ei 'importing|import|clé|key' "$D/dnf-$i.log" | grep -vi 'fingerprint\|empreinte' | head -n 6 | sed 's/^/     /' || true
  [ "$rc" = 0 ] || { tail -n 15 "$D/dnf-$i.log"; echo "KO   installation $i en échec" >&2; exit 1; }
  q /usr/bin/rpm --root=/m/i$i -qa --qf '%{NAME}|%{EPOCHNUM}|%{VERSION}|%{RELEASE}|%{ARCH}|%{INSTALLTIME}|%{INSTALLTID}\n' | sort > "$D/i$i.qa"
  echo "## installation $i, fin $(date -u +%FT%TZ)"
  [ "$i" = 7 ] || sleep 5
done
python3 -I - "$D" "$LD/outillage.qa" "$S" <<'PY'
import collections, sys
d, ref, s = sys.argv[1], sys.argv[2], int(sys.argv[3])
cle = lambda x: '|'.join(x[:5])
r = {cle(x.split('|')) for x in open(ref, encoding='utf-8').read().split('\n') if x and not x.startswith('gpg-pubkey|')}
print(f'référence : {len(r)} NEVRA hors gpg-pubkey (base de racine.tar)')
for i in (5, 6, 7):
    e = [x.split('|') for x in open(f'{d}/i{i}.qa', encoding='utf-8').read().split('\n') if x]
    g = [x for x in e if x[0] == 'gpg-pubkey']; v = [x for x in e if x[0] != 'gpg-pubkey']
    n = {cle(x) for x in v}
    print(f'i{i} : {len(e)} entrée(s), dont {len(g)} gpg-pubkey ; NEVRA égaux à la référence : {"oui" if n == r else "non"}'
          f' (en plus : {len(n - r)}, en moins : {len(r - n)})')
    for x in sorted(n - r)[:5]: print(f'     en plus : {x}')
    for x in sorted(r - n)[:5]: print(f'     en moins : {x}')
    for x in g: print(f'     gpg-pubkey {x[2]}-{x[3]} : INSTALLTIME S{int(x[5]) - s:+d} ; INSTALLTID S{int(x[6]) - s:+d}')
    it = sorted(int(x[5]) - s for x in v); tid = collections.Counter(int(x[6]) - s for x in v)
    print(f'     rpm : INSTALLTIME de S{it[0]:+d} à S{it[-1]:+d}, {len(set(it))} valeur(s) ; INSTALLTID : ' + ', '.join(f'S{k:+d} ({c})' for k, c in sorted(tid.items())))
PY

echo "## 5. archives bornées à S"
EXCL=(--exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m)
archive() { # arbre fichier
  ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
    --xattrs --xattrs-include='*' --numeric-owner "${EXCL[@]}" -C "$1" -cf "$2" . 2> "$2.err" || echo "tar code $? ($(wc -l < "$2.err") lignes d'erreur)"
  echo "$(basename "$2") : $(stat -c %s "$2") octets, sha256 $(sha256sum < "$2" | cut -c1-64)"
}
for i in 5 6 7; do
  echo "i$i : cache de dnf dans la racine : $(ns find "$D/outils/m/i$i" -maxdepth 3 \( -path '*/var/cache/dnf' -o -path '*/m/cache*' \) | sed "s|$D/outils/m/i$i||" | tr '\n' ' ')"
done
archive "$D/outils/m/i5" "$D/archives/a5.tar"
archive "$D/outils/m/i6" "$D/archives/a6.tar"
archive "$D/outils/m/i5" "$D/archives/a5b.tar"
archive "$D/outils/m/i7" "$D/archives/a7.tar"
echo "## 5a. i5 et i6 (miroir, même variable)"
cmp -s "$D/archives/a5.tar" "$D/archives/a6.tar" && echo "OK   a5.tar et a6.tar identiques octet à octet" || { echo "ÉCART a5.tar et a6.tar différents"; python3 -I "$r/m1b-repro2-comparer.py" "$D/archives/a5.tar" "$D/archives/a6.tar"; }
cmp -s "$D/archives/a5.tar" "$D/archives/a5b.tar" && echo "OK   témoin : a5.tar et a5b.tar identiques octet à octet" || echo "ÉCART témoin : a5.tar et a5b.tar différents"
echo "## 5b. i5 et i7 (miroir contre fichiers locaux)"
python3 -I "$r/m1b-repro2-comparer.py" "$D/archives/a5.tar" "$D/archives/a7.tar"
echo "## 5c. contenu seul : a5 contre racine.tar de S1 (sans mtime ni en-têtes pax)"
python3 -I - "$D/archives/a5.tar" "$T/racine.tar" <<'PY'
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
a, b = membres(sys.argv[1]), membres(sys.argv[2])
print(f'membres : a5 {len(a)} ; racine.tar {len(b)}')
sa, sb = sorted(set(a) - set(b)), sorted(set(b) - set(a))
diff = {p: [k for k in a[p] if a[p][k] != b[p].get(k)] for p in sorted(set(a) & set(b))}
diff = {p: c for p, c in diff.items() if c}
print(f'seulement dans a5 : {len(sa)} ; seulement dans racine.tar : {len(sb)} ; présents des deux côtés et différents : {len(diff)}')
for p in sa[:20]: print(f'     seul dans a5 : {p}')
for p in sb[:20]: print(f'     seul dans racine.tar : {p}')
for p, c in list(diff.items())[:40]: print(f'     écart : {p} ({", ".join(c)})')
print('champs en cause : ' + (', '.join(f'{k} {n}' for k, n in sorted(Counter(k for c in diff.values() for k in c).items())) or 'aucun'))
PY
echo "# fin $(date -u +%FT%TZ)"
