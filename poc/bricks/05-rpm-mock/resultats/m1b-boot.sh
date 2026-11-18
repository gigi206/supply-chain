#!/usr/bin/env bash
# Brique 05, M1b, point 1 A, banc du bootstrap : base rockylinux:9.7 (ee90dc0e, cache OCI local) plus les dix lignes de
# verrou_brut (décision « Dix lignes »), installées deux fois le même jour, hors réseau, puis archivées bornées à S. (18/11/2026)
#   1. Réseau (lecture publique seule) : repomd.xml de vault 9.7 BaseOS (sha256 = s1-hote97.log, signature gpgv de la clé Rocky),
#      métadonnées au sha256 de repomd.xml, dix rpm au sha256 de s1-hote97.log (l. 25 à 34). Seul baseos97 est miroité ; S1 avait
#      quatre dépôts actifs (BaseOS, AppStream, CRB, extras) et sa transaction n'a tiré que de baseos97.
#   2. Racine d'outils : arbre de a8.tar (outils de l'amorce, sha256 06c289ad, banc de 21:25:17 UTC). Pas de /usr/bin/dnf : dnf-3,
#      comme boot_racine de S1 (qui a tourné sur 99790c13). Témoins : umask, %_install_langs, versions. rpm -K des dix rpm ; borne S
#      par rpm -qp (dix rpm) et rpm --root -qa (base), attendue 1766985142 (m1b-listes).
#   3. Base : couche 812c4412 de ee90dc0e extraite deux fois (--xattrs, erreurs comptées). Témoins avant installation : rpm -qa
#      (147 lignes dans S1), membres de la couche au-delà de S, deux extractions nues archivées (n1, n2).
#   4. Installations b1 et b2 : forme de boot_racine de S1 (options [main] de dnf97_conf sauf cachedir, mêmes dix NEVRA dans le même
#      ordre, dnf-3, --installroot, --releasever=9), miroir en file://, cache propre, 5 s d'écart, umask 022, TZ=UTC,
#      SOURCE_DATE_EPOCH=S, container=oci. Transaction contrôlée (6 installations, 4 montées) ; liste rpm -qa comparée à celle de S1.
#   5. Archives bornées à S : c1, c2, c1b (témoin) n'excluent que ./m (cache de dnf placé sous la racine) ; x1, x2 ajoutent les
#      exclusions du banc de l'outillage. Comparaisons ; contenu seul (sans dates ni en-têtes pax, xattrs compris) : c1 contre
#      boot-racine.tar de S1 (archivée sans borne), n1 contre c1.
# Prédictions : m1b-predictions.md (section du banc du bootstrap), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-boot.sh > poc/bricks/05-rpm-mock/resultats/m1b-boot.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
SRC=$HOME/.cache/supply-chain-poc/05/m1b-sources-20261118T195832Z   # relevé des sources du 18/11 : clé Rocky, lecture seule
A8=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/archives/a8.tar   # lecture seule
A8S=06c289ad8da33198dd845be6cc899f688ecfb8986e77e4b333629e838876dfa5
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux   # cache de s1.sh amorce : lecture seule
B=ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2   # rockylinux:9.7, BOOT de s1.sh
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05                    # jamais listé : boot-racine.tar et boot-racine.sha256 seuls lus
VAULT97=https://dl.rockylinux.org/vault/rocky/9.7                   # s1.sh, l. 161
REPOMD97=fa6d50542ea30eff797235527b46f0d21b7ec4159980f64580b4797589055258   # s1-hote97.log, l. 6
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D                   # s1.sh, l. 164
S_ATT=1766985142                                                    # m1b-listes : S du bootstrap (153 entrées)
# copie de s1.sh, l. 185 à 188 (DERIVEE) : nom epoch:version-release arch
DERIVEE=("dbus-libs 1:1.12.20-8.el9 x86_64" "python3-dateutil 1:2.9.0.post0-1.el9_7 noarch" "python3-dbus 0:1.2.18-2.el9.0.1 x86_64"
  "python3-dnf-plugins-core 0:4.3.0-24.el9_7 noarch" "python3-six 0:1.15.0-9.el9 noarch" "python3-systemd 0:234-19.el9 x86_64"
  "dnf 0:4.14.0-31.el9.rocky.0.1 noarch" "dnf-data 0:4.14.0-31.el9.rocky.0.1 noarch" "python3-dnf 0:4.14.0-31.el9.rocky.0.1 noarch"
  "yum 0:4.14.0-31.el9.rocky.0.1 noarch")
Q='%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE} sigpgp=%{SIGPGP:pgpsig} rsaheader=%{RSAHEADER:pgpsig}\n'   # format de S1
U=$(date -u +%Y%m%dT%H%M%SZ)
D=$HOME/.cache/supply-chain-poc/05/m1b-boot-$U                       # dossier neuf, jamais effacé ni réutilisé
ns() { unshare --map-auto --map-root-user -n "$@"; }
# racine d'outils : /dev lié, /proc monté, HOME=/root, TZ=UTC, umask donné, dans un espace de montage propre ; q : umask 022
qx() { local u=$1; shift; ns -m -p --fork bash -c 'umask "$1"; shift
  mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || exit 97; export HOME=/root TZ=UTC; exec chroot "$@"' _ "$u" "$D/outils" "$@"; }
q() { qx 022 "$@"; }
masque() { sed -E -e 's/<[^>]*@[^>]*>/<adresse retirée>/g' -e '/jeton|token/I c\[ligne masquée : motif jeton|token]'; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
dl() { curl -fsS --proto =https --tlsv1.2 --retry 2 -o "$2" "$1" || { echo "KO   téléchargement : $1" >&2; exit 1; }; }
echo "# m1b-boot.sh, début $(date -u +%FT%TZ)"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }
[ -s "$A8" ] && [ -s "$T/boot-racine.tar" ] && [ -s "$T/boot-racine.sha256" ] && [ -s "$SRC/RPM-GPG-KEY-Rocky-9" ] \
  || { echo "KO   a8.tar, boot-racine.tar, boot-racine.sha256 ou clé Rocky absent" >&2; exit 1; }
p=""; for x in "${DERIVEE[@]}"; do set -- $x; p="$p $1-${2#0:}.$3"; done; p=${p# }
attendu "paquets demandés = ceux de boot_racine de S1" "$p" "$(sed -n 's/^paquets demandés : //p' "$r/s1-boot_racine.log")"
echo "umask de l'hôte (pour mémoire) : $(umask)"
mkdir -p "$D/outils/m" "$D/archives"   # m créé avant l'extraction de la racine d'outils

echo "## 1. clé, métadonnées de vault 9.7 BaseOS et dix rpm (réseau, lecture publique)"
mkdir -p "$D/outils/m/cles" "$D/outils/m/miroir/baseos97/repodata"
f=$(gpg --batch --with-colons --show-keys "$SRC/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
attendu "RPM-GPG-KEY-Rocky-9 : empreinte" "$f" "$FP_ROCKY"
cp "$SRC/RPM-GPG-KEY-Rocky-9" "$D/outils/m/cles/"
gpg --no-default-keyring --keyring "$D/cles.gpg" --batch --quiet --import "$SRC/RPM-GPG-KEY-Rocky-9" 2>/dev/null
M=$D/outils/m/miroir/baseos97
dl "$VAULT97/BaseOS/x86_64/os/repodata/repomd.xml" "$M/repodata/repomd.xml"
dl "$VAULT97/BaseOS/x86_64/os/repodata/repomd.xml.asc" "$M/repodata/repomd.xml.asc"
attendu "baseos97 : repomd.xml, sha256 égal à hote97" "$(sha256sum < "$M/repodata/repomd.xml" | cut -c1-64)" "$REPOMD97"
v=$(gpgv --keyring "$D/cles.gpg" --status-fd 1 "$M/repodata/repomd.xml.asc" "$M/repodata/repomd.xml" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' || true)
attendu "baseos97 : signataire de repomd.xml" "$v" "$FP_ROCKY"
python3 -I - "$M" <<'PY' > "$D/metadonnees.txt"
import sys, xml.etree.ElementTree as E
n = {'r': 'http://linux.duke.edu/metadata/repo'}
for d in E.parse(f'{sys.argv[1]}/repodata/repomd.xml').getroot().findall('r:data', n):
    if d.get('type').endswith('_db'): continue   # bases sqlite : non téléchargées, comme au banc de l'outillage
    c = d.find('r:checksum', n); assert c.get('type') == 'sha256', c.get('type')
    print(d.find('r:location', n).get('href'), c.text)
PY
while read -r h s; do
  mkdir -p "$(dirname "$M/$h")"; dl "$VAULT97/BaseOS/x86_64/os/$h" "$M/$h"
  [ "$(sha256sum < "$M/$h" | cut -c1-64)" = "$s" ] || { echo "KO   $h : sha256 différent de repomd.xml" >&2; exit 1; }
done < "$D/metadonnees.txt"
echo "OK   baseos97 : $(wc -l < "$D/metadonnees.txt") fichier(s) de métadonnées, sha256 conformes à repomd.xml, $(du -sk "$M/repodata" | cut -f1) kB"
sed -n 's/^OK   .* dans baseos97 : sha256 \([0-9a-f]\{64\}\) (\(Packages\/[^)]*\.rpm\))$/\2 \1/p' "$r/s1-hote97.log" > "$D/epingles.txt"
attendu "rpm épinglés dans s1-hote97.log" "$(wc -l < "$D/epingles.txt")" 10
mkdir -p "$D/outils/m/rpms"
while read -r h s; do
  mkdir -p "$(dirname "$M/$h")"; dl "$VAULT97/BaseOS/x86_64/os/$h" "$M/$h"
  [ "$(sha256sum < "$M/$h" | cut -c1-64)" = "$s" ] || { echo "KO   $h : sha256 différent de hote97" >&2; exit 1; }
  ln "$M/$h" "$D/outils/m/rpms/${h##*/}"
done < "$D/epingles.txt"
echo "OK   dix rpm au sha256 de hote97 : $(ls "$D/outils/m/rpms" | wc -l), $(cat "$D"/outils/m/rpms/*.rpm | wc -c) octets"
echo "fin du réseau : $(date -u +%FT%TZ) ; la suite tourne sans réseau (unshare -n)"

echo "## 2. racine d'outils (a8), témoins, signatures et borne S"
attendu "a8.tar : sha256" "$(sha256sum < "$A8" | cut -c1-64)" "$A8S"
rc=0; ns tar -xf "$A8" -C "$D/outils" --numeric-owner 2> "$D/outils.err" || rc=$?
echo "extraction de a8 : code $rc, $(wc -l < "$D/outils.err") ligne(s) d'erreur"; head -n 5 "$D/outils.err" | masque | sed 's/^/     /'
ns mkdir -p "$D/outils/dev" "$D/outils/proc"
[ -x "$D/outils/usr/bin/rpm" ] && [ -x "$D/outils/usr/bin/dnf-3" ] || { echo "KO   rpm ou dnf-3 absent de la racine d'outils" >&2; exit 1; }
echo "témoin /usr/bin/dnf dans la racine d'outils : $([ -e "$D/outils/usr/bin/dnf" ] && echo présent || echo absent)"
echo "témoin macros.image-language-conf : $([ -e "$D/outils/etc/rpm/macros.image-language-conf" ] && echo présent || echo absent)"
echo "témoin umask (dans la racine d'outils) : $(q bash -c umask)"
echo "témoin %_install_langs (dans la racine d'outils) : [$(q /usr/bin/rpm -E '%_install_langs')]"
echo "outils : $(q /usr/bin/rpm --version) ; dnf-3 $(q /usr/bin/dnf-3 --version 2>/dev/null | head -1)"
q bash -c 'rpm -q --qf "%{NEVRA}\n" rpm dnf python3-dnf libsolv libdnf 2>&1 || true' | sed 's/^/     /'   # dnf absent : rpm -q rend 1
mkdir -p "$D/outils/m/clesdb"
q /usr/bin/rpm --dbpath /m/clesdb --import /m/cles/RPM-GPG-KEY-Rocky-9
q bash -c 'rpm --dbpath /m/clesdb -K /m/rpms/*.rpm' > "$D/k.log" 2>&1 || true
echo "rpm -K : $(grep -c -E 'digests signatures OK$' "$D/k.log") « digests signatures OK » sur $(ls "$D/outils/m/rpms" | wc -l)"
grep -v -E 'digests signatures OK$' "$D/k.log" | head -n 5 || true

echo "## 3. base rockylinux:9.7 (ee90dc0e)"
attendu "manifeste ee90dc0e : sha256" "$(sha256sum < "$O/blobs/sha256/$B" | cut -c1-64)" "$B"
L=$(python3 -I -c 'import json, sys; j = json.load(open(sys.argv[1])); assert len(j["layers"]) == 1; print(j["layers"][0]["digest"][7:])' "$O/blobs/sha256/$B")
attendu "couche ${L:0:12} : sha256" "$(sha256sum < "$O/blobs/sha256/$L" | cut -c1-64)" "$L"
python3 -I - "$O/blobs/sha256/$L" "$S_ATT" <<'PY'
import sys, tarfile
s = int(sys.argv[2]); n = au_dela = wh = spec = x = 0; mx = 0
with tarfile.open(sys.argv[1], 'r:*') as t:
    for m in t:
        n += 1; mx = max(mx, int(m.mtime))
        au_dela += m.mtime > s
        wh += m.name.rsplit('/', 1)[-1].startswith('.wh.')
        spec += m.ischr() or m.isblk() or m.isfifo()
        x += any(k.startswith('SCHILY.xattr.') for k in m.pax_headers)
print(f'couche : {n} membres ; mtime max {mx} ; au-delà de S ({s}) : {au_dela} ; .wh. : {wh} ; spéciaux : {spec} ; avec xattrs : {x}')
PY
for i in 1 2; do
  mkdir -p "$D/outils/m/b$i"; rc=0
  ns tar -xf "$O/blobs/sha256/$L" -C "$D/outils/m/b$i" --numeric-owner --xattrs --xattrs-include='*' 2> "$D/base-$i.err" || rc=$?
  echo "extraction b$i : code $rc, $(wc -l < "$D/base-$i.err") ligne(s) d'erreur"; head -n 5 "$D/base-$i.err" | masque | sed 's/^/     /'
  q bash -c "rpm --root /m/b$i -qa --qf '$Q' 2>/m/avant-$i.err | sort > /m/avant-$i.txt"
  echo "b$i avant : rpm -qa $(wc -l < "$D/outils/m/avant-$i.txt") ligne(s), stderr $(wc -l < "$D/outils/m/avant-$i.err") ligne(s) ; gpg-pubkey : $(grep -c '^gpg-pubkey' "$D/outils/m/avant-$i.txt" || true)"
done
E=$(q bash -c 'rpm -qp --nosignature --qf "%{BUILDTIME}\n" /m/rpms/*.rpm' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)
F=$(q bash -c 'rpm -qp --nosignature --qf "[%{FILEMTIMES}\n]" /m/rpms/*.rpm' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)
Eb=$(q bash -c 'rpm --root /m/b1 -qa --qf "%{BUILDTIME}\n"' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)
Fb=$(q bash -c 'rpm --root /m/b1 -qa --qf "[%{FILEMTIMES}\n]"' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)
echo "dix rpm : BUILDTIME max $E, FILEMTIMES max $F ; base : BUILDTIME max $Eb, FILEMTIMES max $Fb"
S=$(printf '%s\n' "$E" "$F" "$Eb" "$Fb" | sort -n | tail -n 1)
attendu "S ($(date -u -d "@$S" +%FT%TZ))" "$S" "$S_ATT"

echo "## 4. archives bornées à S et installations"
EXCL0=(--exclude=./m)
EXCL=(--exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id)
archive() { # arbre fichier exclusions…
  local a=$1 f=$2; shift 2
  ns tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@$S" --clamp-mtime \
    --xattrs --xattrs-include='*' --numeric-owner "$@" -C "$a" -cf "$f" . 2> "$f.err" || echo "tar code $? ($(wc -l < "$f.err") lignes d'erreur)"
  echo "$(basename "$f") : $(stat -c %s "$f") octets, $(tar -tf "$f" | wc -l) membres, sha256 $(sha256sum < "$f" | cut -c1-64)"
}
archive "$D/outils/m/b1" "$D/archives/n1.tar" "${EXCL0[@]}"
archive "$D/outils/m/b2" "$D/archives/n2.tar" "${EXCL0[@]}"
cmp -s "$D/archives/n1.tar" "$D/archives/n2.tar" && echo "OK   témoin : n1.tar et n2.tar (extractions nues) identiques octet à octet" || echo "ÉCART témoin : n1.tar et n2.tar différents"
cat > "$D/outils/m/dnf97.conf" <<'EOF'
[main]
gpgcheck=1
install_weak_deps=0
best=1
keepcache=1
cachedir=/m/cache
reposdir=/m/aucun
[baseos97]
name=Rocky 9.7 BaseOS (vault, miroir partiel)
baseurl=file:///m/miroir/baseos97/
repo_gpgcheck=1
gpgkey=file:///m/cles/RPM-GPG-KEY-Rocky-9
EOF
mkdir -p "$D/outils/m/aucun"
echo "dnf97.conf : sha256 $(sha256sum < "$D/outils/m/dnf97.conf" | cut -c1-64)"
for i in 1 2; do
  echo "## installation b$i, début $(date -u +%FT%TZ)"
  rc=0; t=$(date +%s)
  # shellcheck disable=SC2086
  q /usr/bin/env container=oci SOURCE_DATE_EPOCH="$S" /usr/bin/dnf-3 -y -c /m/dnf97.conf --setopt=reposdir=/m/aucun --setopt=cachedir=/m/cache-$i \
    --installroot=/m/b$i --releasever=9 install $p > "$D/dnf-$i.log" 2>&1 || rc=$?
  echo "dnf-3 code $rc en $(($(date +%s) - t)) s ; $(wc -l < "$D/dnf-$i.log") lignes de journal"
  echo "lignes « scriptlet », « warning » ou « error » (casse ignorée) : $(grep -Eci 'scriptlet|(^|[^-[:alnum:]])(warning|error)' "$D/dnf-$i.log" || true)"
  grep -Ei 'importing|import|clé|key' "$D/dnf-$i.log" | grep -vi 'fingerprint\|empreinte' | head -n 6 | masque | sed 's/^/     /' || true
  [ "$rc" = 0 ] || { tail -n 15 "$D/dnf-$i.log" | masque; echo "KO   installation b$i en échec" >&2; exit 1; }
  grep -E "^(Install|Upgrade|Remove|Downgrade|Reinstall|Skip) +[0-9]+ Package" "$D/dnf-$i.log" | sed "s/^/résumé de la transaction : /" || true
  q bash -c "rpm --root /m/b$i -qa --qf '$Q' 2>/m/apres-$i.err | sort > /m/apres-$i.txt"
  echo "b$i après : rpm -qa $(wc -l < "$D/outils/m/apres-$i.txt") ligne(s), stderr $(wc -l < "$D/outils/m/apres-$i.err") ligne(s)"
  echo "## installation b$i, fin $(date -u +%FT%TZ)"
  [ "$i" = 2 ] || sleep 5
done
sed -n 's/^     racine dérivée, liste : //p' "$r/s1-boot_racine.log" | sort > "$D/s1-apres.txt"
for i in 1 2; do
  cmp -s "$D/outils/m/apres-$i.txt" "$D/s1-apres.txt" && echo "OK   liste rpm -qa de b$i égale à celle de S1 ($(wc -l < "$D/s1-apres.txt") lignes)" \
    || { echo "ÉCART liste rpm -qa de b$i différente de celle de S1"; diff "$D/s1-apres.txt" "$D/outils/m/apres-$i.txt" | head -n 20 || true; }
done
archive "$D/outils/m/b1" "$D/archives/c1.tar" "${EXCL0[@]}"
archive "$D/outils/m/b2" "$D/archives/c2.tar" "${EXCL0[@]}"
archive "$D/outils/m/b1" "$D/archives/c1b.tar" "${EXCL0[@]}"
archive "$D/outils/m/b1" "$D/archives/x1.tar" "${EXCL[@]}"
archive "$D/outils/m/b2" "$D/archives/x2.tar" "${EXCL[@]}"

echo "## 5. comparaisons"
contenu() { # archive-a archive-b nom-a nom-b : contenu seul (sans mtime ni en-têtes pax), xattrs compris
  python3 -I - "$@" <<'PY'
import hashlib, sys, tarfile
from collections import Counter
def membres(p):
    r = {}
    with tarfile.open(p, 'r:') as t:
        for m in t:
            e = {'type': m.type, 'mode': m.mode, 'uid': m.uid, 'gid': m.gid, 'taille': m.size, 'cible': m.linkname,
                 'xattrs': sorted((k, v) for k, v in m.pax_headers.items() if k.startswith('SCHILY.xattr.'))}
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
    print(f'{nom} : {len(loc)} membres sous usr/share/locale, dont {sum(1 for p in loc if p.endswith(".mo"))} fichiers .mo ; '
          f'{sum(1 for e in x.values() if e["xattrs"])} membre(s) avec xattrs')
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
compare() { # a b
  if cmp -s "$D/archives/$1.tar" "$D/archives/$2.tar"; then echo "OK   $1.tar et $2.tar identiques octet à octet"
  else echo "ÉCART $1.tar et $2.tar différents"; contenu "$D/archives/$1.tar" "$D/archives/$2.tar" "$1" "$2"; fi
}
echo "## 5a. c1 et c2 (n'excluent que ./m)"
compare c1 c2
echo "## 5b. témoin : c1 et c1b"
compare c1 c1b
echo "## 5c. x1 et x2 (exclusions du banc de l'outillage)"
compare x1 x2
echo "## 5d. contenu seul : c1 contre boot-racine.tar de S1"
attendu "boot-racine.tar de S1 : sha256 égal à boot-racine.sha256" "$(sha256sum < "$T/boot-racine.tar" | cut -c1-64)" "$(cat "$T/boot-racine.sha256")"
contenu "$D/archives/c1.tar" "$T/boot-racine.tar" c1 boot-racine.tar
echo "## 5e. contenu seul : n1 (base nue) contre c1"
contenu "$D/archives/n1.tar" "$D/archives/c1.tar" n1 c1
echo "arbres et archives laissés dans $D"
echo "# fin $(date -u +%FT%TZ)"
