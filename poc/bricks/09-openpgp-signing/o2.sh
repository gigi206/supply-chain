#!/usr/bin/env bash
# Brique 09, O2 (décisions D1 à D4 et « racines (a) » du 19/11/2026) : racines de signature sur l'hôte et clé OpenPGP du PoC.
# Mécanisme de la 05 (m1b-amorce-lecture.sh, m1b-repro.sh) : racine dans un dossier, unshare --map-auto --map-root-user, chroot.
# Ni podman, ni cluster, ni Zot. Une étape à la fois ; chacune refuse un dossier cible déjà présent, aucun « rm » dans ce script.
#
#   prealables       lecture locale : amorces, clé Rocky de l'amorce, place, espace de noms, dossiers.
#   banc_chroot      À SEC, sans réseau, sans installation : amorce Rocky (gpg 2.3.3-5.el9_7 déjà présent) extraite dans un
#                    dossier de banc ; même mécanique que cle et essai (CHROOT, liens, tmpfs) avec une clé JETABLE ; import
#                    d'une clé jetable de l'hôte (2.4.8) dans 2.3.3.
#   rocky_telecharger  ACCORD : réseau. Amorce Rocky extraite une fois ; dnf-3 --installroot --downloadonly depuis vault 9.8
#                    (gpgcheck, repo_gpgcheck) ; chaque rpm contrôlé contre le primary vérifié du relevé (sha256).
#   rocky_installer  ACCORD : installation, sans réseau, des rpm contrôlés dans la racine neuve (localpkg_gpgcheck) ; archive.
#   debian_amorce    ACCORD : réseau. Amorce Debian extraite une fois ; mmdebstrap 1.5.7-1+deb13u1 installé depuis l'instantané ;
#                    InRelease comparé au relevé ; .deb contrôlés contre le Packages.xz vérifié du relevé.
#   debian_racine    ACCORD : réseau. Racine minbase par mmdebstrap --mode=root (CR5, confiance faible) ; .deb contrôlés ;
#                    versions épinglées contrôlées ; archive extraite dans la racine de signature.
#   cle              ACCORD : clé du PoC créée dans la racine Debian (gpg 2.4.7), sans réseau, homedir tmpfs ; exports armurés.
#   essai            ACCORD : sans réseau ; signatures et vérifications croisées dans les deux racines (K5), sens inverse (K5b).
# Les étapes avec réseau refusent si le dossier des secrets existe (K1). Code non nul dès qu'une ligne « KO » est journalisée.
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o2.sh <étape>   (journal : resultats/o2-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
I=$here/o2-interne.sh
BASE=$HOME/.cache/supply-chain-poc/09
W=$BASE/o2
S=$BASE/secrets
WB=$BASE/o2-banc-chroot
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont
P1=$BASE/releve-20261119T144438Z      # primary vérifiés de BaseOS et AppStream 9.8 (repomd égaux à vault : o2-releve.log)
P2=$BASE/o2-releve-20261119T154234Z   # Packages.xz de l'instantané, contrôlé par InRelease vérifié (o2-releve.log)
ROCKY_M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d
DEB_M=7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392
VAULT=https://dl.rockylinux.org/vault/rocky/9.8
SNAP=20261105T000000Z
MIROIR=http://snapshot.debian.org/archive/debian/$SNAP   # http : l'amorce n'a pas de certificats ; intégrité par InRelease (06)
INRELEASE=0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675
ROCKY_PAQUETS="gnupg2-2.3.3-5.el9_7 rpm-sign-4.16.1.3-40.el9 createrepo_c-0.20.1-4.el9"
DEB_PAQUETS="gnupg=2.4.7-21+deb13u1,gpg=2.4.7-21+deb13u1+b5,gpgv=2.4.7-21+deb13u1+b5,gpg-agent=2.4.7-21+deb13u1+b5,gpgconf=2.4.7-21+deb13u1+b5,apt-utils=3.0.3,sqv=1.3.0-3+b2"
V_MMDEBSTRAP=1.5.7-1+deb13u1
WR=$W/rocky             # amorce Rocky extraite (utilisée une fois) ; racine de signature dans $WR/racine
RR=$WR/racine
WDA=$W/debian-amorce    # amorce Debian extraite (utilisée une fois)
RD=$W/racine-debian13   # racine Debian de signature (archive de mmdebstrap extraite)
LISTE=$R/releve-amont-telechargements.tsv
mkdir -p "$BASE" "$R"
cd "$BASE"

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; exit 1; }
sans_cle() { [ ! -e "$S" ] || ko "$S existe : aucune étape réseau tant qu'une clé existe sur l'hôte (K1)"; }
absent() { [ ! -e "$1" ] || ko "$1 existe déjà : rien n'est réutilisé ni écrasé"; }
ns_hors() { unshare --map-auto --map-root-user -n -m -p --fork "$@"; }
ns_avec() { unshare --map-auto --map-root-user -m -p --fork "$@"; }

# Lancé dans l'espace de noms : montages puis chroot. Arguments : RACINE RESEAU(0|1) commande…
# LIENS : « source:cible:ro|rw » séparés par des espaces ; TMPFS : chemins (dans la racine) couverts d'un tmpfs.
CHROOT='set -e; r=$1; res=$2; shift 2
mount --rbind /dev "$r/dev"; mount -t proc proc "$r/proc"
if [ "$res" = 1 ]; then mkdir -p "$r/o2"; [ -L "$r/etc/resolv.conf" ] && mv "$r/etc/resolv.conf" "$r/o2/resolv.conf.lien-origine"
  [ -e "$r/etc/resolv.conf" ] || : > "$r/etc/resolv.conf"; mount --bind /etc/resolv.conf "$r/etc/resolv.conf"; fi
for l in ${LIENS:-}; do IFS=: read -r s c m <<<"$l"; if [ -d "$s" ]; then mkdir -p "$r$c"; else mkdir -p "$(dirname "$r$c")"; : > "$r$c"; fi
  mount --bind "$s" "$r$c"; [ "$m" = ro ] && mount -o remount,bind,ro "$r$c"; done
for t in ${TMPFS:-}; do mkdir -p "$r$t"; mount -t tmpfs -o size=64m,mode=700 tmpfs "$r$t"; done
export HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec chroot "$r" "$@"'
dans_hors() { ns_hors bash -c "$CHROOT" _ "$1" 0 "${@:2}"; }
dans_avec() { ns_avec bash -c "$CHROOT" _ "$1" 1 "${@:2}"; }

extraire() { # OCI MANIFESTE DESTINATION : couche unique contrôlée par sha256, extraite sans réseau
  local o=$1 m=$2 d=$3 l
  l=$(python3 -I - "$o" "$m" <<'PY'
import hashlib, json, sys
o, m = sys.argv[1], sys.argv[2]
b = lambda d: f"{o}/blobs/sha256/{d}"
h = lambda d: hashlib.sha256(open(b(d), "rb").read()).hexdigest()
assert h(m) == m, "manifeste"
j = json.load(open(b(m)))
assert len(j["layers"]) == 1, "une seule couche attendue"
d = j["layers"][0]["digest"][7:]
assert h(d) == d, "couche"
print(d)
PY
) || ko "manifeste ou couche $m"
  mkdir -p "$d"
  ns_hors tar -xf "$o/blobs/sha256/$l" -C "$d" --numeric-owner --exclude='dev/*' 2>/dev/null || echo "  tar : code $? (fichiers spéciaux ignorés)"
  mkdir -p "$d/dev" "$d/proc"
  echo "OK   couche ${l:0:12} de ${m:0:12} extraite dans $d"
}
signaler() { # DOSSIER ORIGINE : chaque paquet téléchargé journalisé et ajouté à la liste des téléchargements
  find "$1" -maxdepth 1 -type f \( -name '*.rpm' -o -name '*.deb' \) -printf '%f\t%s\t%p\n' | sort | while IFS=$'\t' read -r n t p; do
    s=$(sha256sum < "$p" | cut -c1-64)
    printf '%s\t%s\t%s\t%s\n' "o2/$n" "$2" "$t" "$s" >> "$LISTE"
    echo "  téléchargé : $n ($t octets, sha256 $s)"
  done
}
controle_rpm() { # DOSSIER : chaque rpm égal (sha256) à son entrée dans les primary vérifiés de BaseOS et AppStream 9.8
  python3 -I - "$1" "$P1/rocky-BaseOS-primary.xml.gz" "$P1/rocky-AppStream-primary.xml.gz" <<'PY'
import glob, gzip, hashlib, os, sys, xml.etree.ElementTree as ET
ns = {"c": "http://linux.duke.edu/metadata/common"}
ref = {}
for f in sys.argv[2:]:
    for p in ET.parse(gzip.open(f)).getroot().findall("c:package", ns):
        ref[os.path.basename(p.find("c:location", ns).get("href"))] = p.find("c:checksum", ns).text
ok = ko = 0
for r in sorted(glob.glob(os.path.join(sys.argv[1], "**", "*.rpm"), recursive=True)):
    s = hashlib.sha256(open(r, "rb").read()).hexdigest()
    if ref.get(os.path.basename(r)) == s: ok += 1
    else: ko += 1; print("     écart : " + os.path.basename(r))
print(("OK   " if ok and not ko else "KO   ") + f"rpm conformes aux primary vérifiés : {ok} sur {ok + ko}")
PY
}
controle_debs() { # FICHIER : lignes « deb <origine> <fichier> <sha256> » comparées au Packages.xz vérifié (logique de la 06)
  python3 -I - "$P2/Packages.xz" "$1" <<'PY'
import lzma, re, sys
pk = {}
for para in lzma.open(sys.argv[1]).read().decode("utf-8", "replace").split("\n\n"):
    d = dict(l.split(": ", 1) for l in para.split("\n") if ": " in l and not l.startswith(" "))
    if "Filename" in d: pk[d["Filename"].rsplit("/", 1)[1]] = d["SHA256"]
n = 0; ko = []
for l in open(sys.argv[2], encoding="utf-8"):
    c = l.split()
    if len(c) == 4 and c[0] == "deb":
        n += 1
        f = re.sub(r"_[0-9]+%3[aA]", "_", c[2])   # apt garde l'époque dans le nom du fichier, le pool non (06)
        if pk.get(f) != c[3]: ko.append(c[2])
print(("OK   " if n and not ko else "KO   ") + f"sha256 des .deb conformes au Packages vérifié : {n - len(ko)} sur {n}")
for k in ko[:10]: print("     écart : " + k)
PY
}
racine_rpm() { # RACINE : liste des paquets installés, signatures, versions épinglées
  dans_hors "$1" rpm -qa --qf '%{NEVRA} %{RSAHEADER:pgpsig}\n' | sort > "$2"
  echo "racine : $(wc -l < "$2") paquets ; liste sha256 $(sha256sum < "$2" | cut -c1-64)"
  for p in $ROCKY_PAQUETS; do grep -q "^$p\." "$2" && echo "OK   $p installé" || echo "KO   $p absent"; done
  echo "clés de signature citées : $(awk '{print $NF}' "$2" | sort | uniq -c | paste -sd' ')"
}

# Programme d'essai, dans un seul espace de noms sans réseau : tmpfs commun (sorties) lié dans les racines D et R ;
# un tmpfs neuf par appel de gpg. Arguments : D R SECRETS INTERNE X [proxy]. « proxy » : clé jetable du gpg de l'hôte importée
# dans R (banc seulement).
PROGRAMME_ESSAI='set -u
D=$1 Rk=$2 S=$3 I=$4 X=$5 P=${6:-}
mount -t tmpfs -o size=64m,mode=700 tmpfs "$X"
mkdir -p "$X/deb" "$X/rpm" "$X/k5b" "$X/hote" "$X/gh"
for r in "$D" "$Rk"; do
  mountpoint -q "$r/proc" && continue
  mount --rbind /dev "$r/dev"; mount -t proc proc "$r/proc"
  for c in /o2/x /o2/secrets /o2/g; do mkdir -p "$r$c"; done
  : > "$r/o2/interne.sh"; mount --bind "$I" "$r/o2/interne.sh"; mount -o remount,bind,ro "$r/o2/interne.sh"
  mount --bind "$S" "$r/o2/secrets"; mount -o remount,bind,ro "$r/o2/secrets"
  mount --bind "$X" "$r/o2/x"
done
g() { local r=$1 l=$2; shift 2
  echo "### $l"
  mount -t tmpfs -o size=32m,mode=700 tmpfs "$r/o2/g"
  HOME=/root GNUPGHOME=/o2/g PATH=/usr/sbin:/usr/bin:/sbin:/bin O2_NOM="Banc 09 PoC cle jetable" O2_EXPIRE=2d chroot "$r" /bin/bash /o2/interne.sh "$@"; local rc=$?
  chroot "$r" gpgconf --homedir /o2/g --kill all 2>/dev/null
  umount -l "$r/o2/g"; echo "  code $rc"; }
g "$D" "E1 racine D : import de la clé et signature" signer /o2/secrets/cle-openpgp.asc /o2/x/deb
g "$D" "E2 racine D : vérification par gpgv et sqv" verifier /o2/secrets/cle-publique.asc /o2/x/deb/essai.txt /o2/x/deb/essai.txt.sig
g "$Rk" "E3 racine R : import de la clé et signature (K5)" signer /o2/secrets/cle-openpgp.asc /o2/x/rpm
g "$Rk" "E4 racine R : vérification de la signature de D par gpgv" verifier /o2/secrets/cle-publique.asc /o2/x/deb/essai.txt /o2/x/deb/essai.txt.sig
g "$D" "E5 racine D : vérification de la signature de R par gpgv et sqv" verifier /o2/secrets/cle-publique.asc /o2/x/rpm/essai.txt /o2/x/rpm/essai.txt.sig
g "$Rk" "E6 racine R : clé jetable créée (K5b)" jetable /o2/x/k5b
g "$D" "E7 racine D : import de la clé jetable de R et signature (K5b)" signer /o2/x/k5b/jetable.asc /o2/x/k5b
g "$Rk" "E8 racine R : vérification de la signature K5b par gpgv" verifier /o2/x/k5b/jetable-publique.asc /o2/x/k5b/essai.txt /o2/x/k5b/essai.txt.sig
if [ "$P" = proxy ]; then
  echo "### E9 hôte (gpg $(gpg --version | head -1 | cut -d" " -f3)) : clé jetable créée hors racine"
  mount -t tmpfs -o size=32m,mode=700 tmpfs "$X/gh"
  GNUPGHOME=$X/gh O2_NOM="Banc 09 PoC cle jetable" O2_EXPIRE=2d bash "$I" jetable "$X/hote"; echo "  code $?"
  gpgconf --homedir "$X/gh" --kill all 2>/dev/null; umount -l "$X/gh"
  g "$Rk" "E10 racine R : import de la clé de l hôte et signature" signer /o2/x/hote/jetable.asc /o2/x/hote
  g "$Rk" "E11 racine R : vérification par gpgv" verifier /o2/x/hote/jetable-publique.asc /o2/x/hote/essai.txt /o2/x/hote/essai.txt.sig
fi'

etape_prealables() {
  set +e
  echo "$(unshare --version) ; python3 $(python3 -I -c 'import sys; print(sys.version.split()[0])') ; $(tar --version | head -1)"
  for e in "rockylinux $OCI/rockylinux/rockylinux $ROCKY_M" "debian $OCI/library/debian $DEB_M"; do
    set -- $e
    python3 -I - "$2" "$3" <<'PY' && echo "OK   amorce $1 : manifeste, configuration et couche égaux à leur sha256" || echo "KO   amorce $1"
import hashlib, json, sys
o, m = sys.argv[1], sys.argv[2]
b = lambda d: f"{o}/blobs/sha256/{d}"
h = lambda d: hashlib.sha256(open(b(d), "rb").read()).hexdigest()
j = json.load(open(b(m)))
assert h(m) == m and h(j["config"]["digest"][7:]) == j["config"]["digest"][7:] and len(j["layers"]) == 1
assert h(j["layers"][0]["digest"][7:]) == j["layers"][0]["digest"][7:]
PY
  done
  python3 -I - "$OCI/rockylinux/rockylinux" "$ROCKY_M" "$P1/RPM-GPG-KEY-Rocky-9" <<'PY' && echo "OK   clé Rocky 9 de l'amorce égale à celle du relevé (empreinte 21CB256A…275D vérifiée le 19/11)" || echo "KO   clé Rocky 9 de l'amorce différente"
import hashlib, json, sys, tarfile
o, m, ref = sys.argv[1:4]
j = json.load(open(f"{o}/blobs/sha256/{m}"))
with tarfile.open(f"{o}/blobs/sha256/{j['layers'][0]['digest'][7:]}", "r:*") as t:
    for i in t:
        if i.name.lstrip("./") == "etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9":
            while i.issym() or i.islnk():
                i = t.getmember(i.linkname if i.islnk() else "etc/pki/rpm-gpg/" + i.linkname)
            a = hashlib.sha256(t.extractfile(i).read()).hexdigest()
            break
b = hashlib.sha256(open(ref, "rb").read()).hexdigest()
print(f"  amorce {a[:16]}…, relevé {b[:16]}…")
sys.exit(a != b)
PY
  for f in "$P1/rocky-BaseOS-primary.xml.gz" "$P1/rocky-AppStream-primary.xml.gz" "$P2/Packages.xz"; do
    [ -f "$f" ] && echo "OK   index vérifié présent : $f" || echo "KO   index absent : $f"
  done
  echo "place libre sous ~/.cache : $(df -B1M --output=avail "$HOME/.cache" | tail -1 | tr -d ' ') Mo"
  mkdir -p "$BASE/o2-sonde"
  ns_hors bash -c 'mount -t tmpfs -o size=1m,mode=700 tmpfs "$1" && mount -t proc proc /proc && echo "OK   espace de noms : tmpfs monté ($(stat -f -c %T "$1")), $(awk "NR > 2" /proc/self/net/dev | wc -l) interface(s)"' _ "$BASE/o2-sonde"
  rmdir "$BASE/o2-sonde"
  for d in "$W" "$S" "$WB"; do [ -e "$d" ] && echo "présent : $d" || echo "absent : $d"; done
  echo "secrets-depot.sh lit : $(grep -oE 'supply-chain-poc/[0-9a-z]+/secrets' "$here/../../../tools/secrets-depot.sh" | sort -u | paste -sd' ')"
}

etape_banc_chroot() {
  set +e
  absent "$WB"
  mkdir -p "$WB"
  extraire "$OCI/rockylinux/rockylinux" "$ROCKY_M" "$WB/rocky"
  dans_hors "$WB/rocky" gpg --version | head -1 | sed 's/^/  gpg de l amorce Rocky : /'
  dans_hors "$WB/rocky" rpm -q gnupg2 | sed 's/^/  paquet : /'
  mkdir -m 700 "$WB/secrets" "$WB/x"
  echo "### BK1 : création d'une clé jetable par gpg 2.3.3, même mécanique que cle (CHROOT, liens, tmpfs)"
  LIENS="$WB/secrets:/o2/secrets:rw $I:/o2/interne.sh:ro" TMPFS="/o2/g" \
    dans_hors "$WB/rocky" env GNUPGHOME=/o2/g O2_NOM="Banc 09 PoC cle jetable" O2_EXPIRE=2d /bin/bash /o2/interne.sh creer /o2/secrets
  echo "  code $?"
  for f in "$WB"/secrets/*; do echo "  $(basename "$f") : $(stat -c '%a %s' "$f") (mode, octets)"; done
  echo "### BK2 (K4) : seconde création, refus attendu"
  LIENS="$WB/secrets:/o2/secrets:rw $I:/o2/interne.sh:ro" TMPFS="/o2/g" \
    dans_hors "$WB/rocky" env GNUPGHOME=/o2/g O2_NOM="Banc 09 PoC cle jetable" O2_EXPIRE=2d /bin/bash /o2/interne.sh creer /o2/secrets
  echo "  code $? (refus attendu)"
  echo "### BK3 : programme d'essai, racine Rocky pour D et pour R, plus import d'une clé de l'hôte (2.4.8 vers 2.3.3)"
  ns_hors bash -c "$PROGRAMME_ESSAI" _ "$WB/rocky" "$WB/rocky" "$WB/secrets" "$I" "$WB/x" proxy
  rmdir "$WB/x"
  echo "à effacer après archivage (chemin littéral, dans l'espace de noms, car les fichiers appartiennent à des sous-UID) :"
  echo "  unshare --map-auto --map-root-user rm -r --one-file-system $WB"
}

etape_rocky_telecharger() {
  set +e
  sans_cle; absent "$WR"
  mkdir -p "$W"
  extraire "$OCI/rockylinux/rockylinux" "$ROCKY_M" "$WR"
  mkdir -p "$WR/o2/repos" "$WR/o2/cache" "$WR/o2/rpm" "$RR"
  for d in BaseOS AppStream; do
    printf '[o2-%s]\nname=vault 9.8 %s\nbaseurl=%s/%s/x86_64/os/\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9\nenabled=1\n\n' \
      "$d" "$d" "$VAULT" "$d" >> "$WR/o2/repos/o2.repo"
  done
  dans_avec "$WR" /usr/bin/dnf-3 -y --installroot=/racine --releasever=9 --setopt=reposdir=/o2/repos --setopt=cachedir=/o2/cache \
    --setopt=install_weak_deps=False --setopt=tsflags=nodocs --downloadonly --downloaddir=/o2/rpm \
    install bash coreutils gawk grep findutils $ROCKY_PAQUETS > "$W/rocky-telecharger-dnf.log" 2>&1
  rc=$?; echo "dnf --downloadonly : code $rc ; dernières lignes :"; tail -4 "$W/rocky-telecharger-dnf.log" | sed 's/^/  | /'
  [ "$rc" = 0 ] || ko "téléchargement Rocky"
  signaler "$WR/o2/rpm" "$VAULT (dnf-3 --downloadonly, gpgcheck=1, repo_gpgcheck=1)"
  controle_rpm "$WR/o2/rpm"
  for p in $ROCKY_PAQUETS; do ls "$WR/o2/rpm/$p."*.rpm >/dev/null 2>&1 && echo "OK   $p téléchargé" || echo "KO   $p absent des téléchargements"; done
}

etape_rocky_installer() {
  set +e
  [ -d "$WR/o2/rpm" ] || ko "rocky_telecharger d'abord"
  [ ! -e "$RR/usr" ] || ko "$RR déjà peuplée"
  absent "$W/rocky98-racine.tar"
  controle_rpm "$WR/o2/rpm" | grep -q '^OK' || ko "rpm non conformes : rien n'est installé"
  dans_hors "$WR" /bin/sh -c '{ rpm --root /racine -q gpg-pubkey-350d275d >/dev/null 2>&1 && echo "clé Rocky 350d275d déjà dans la base rpm de la racine (importée par rocky_telecharger)" || rpm --root /racine --import /etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9; } && /usr/bin/dnf-3 -y --installroot=/racine --releasever=9 --setopt=reposdir=/o2/aucun --setopt=localpkg_gpgcheck=True --setopt=install_weak_deps=False --setopt=tsflags=nodocs install /o2/rpm/*.rpm' \
    > "$W/rocky-installer-dnf.log" 2>&1
  rc=$?; echo "dnf hors ligne : code $rc ; dernières lignes :"; tail -4 "$W/rocky-installer-dnf.log" | sed 's/^/  | /'
  [ "$rc" = 0 ] || ko "installation Rocky hors ligne"
  racine_rpm "$RR" "$W/rocky-paquets.txt"
  dans_hors "$RR" gpg --version | head -1 | sed 's/^/  gpg de la racine Rocky : /'
  ns_hors tar -C "$RR" --numeric-owner --sort=name --exclude=./o2 -cf "$W/rocky98-racine.tar" .   # ./o2 : cache de dnf laissé par rocky_telecharger
  echo "archive rocky98-racine.tar : $(stat -c %s "$W/rocky98-racine.tar") octets, sha256 $(sha256sum < "$W/rocky98-racine.tar" | cut -c1-64)"
}

etape_debian_amorce() {
  set +e
  sans_cle; absent "$WDA"
  mkdir -p "$W"
  extraire "$OCI/library/debian" "$DEB_M" "$WDA"
  mkdir -p "$WDA/o2"
  [ -f "$WDA/etc/apt/sources.list.d/debian.sources" ] && mv "$WDA/etc/apt/sources.list.d/debian.sources" "$WDA/o2/debian.sources.origine"
  # docker-clean (image Debian officielle) efface les .deb après chaque dpkg : mis de côté, sinon aucun .deb à contrôler (premier passage)
  [ -f "$WDA/etc/apt/apt.conf.d/docker-clean" ] && mv "$WDA/etc/apt/apt.conf.d/docker-clean" "$WDA/o2/docker-clean.origine" && echo "docker-clean mis de côté dans o2/"
  echo "deb [check-valid-until=no] $MIROIR trixie main" > "$WDA/etc/apt/sources.list.d/instantane.list"
  dans_avec "$WDA" /bin/sh -c "apt-get -q update && apt-get -q -y --no-install-recommends -o APT::Keep-Downloaded-Packages=true install mmdebstrap=$V_MMDEBSTRAP" > "$W/debian-amorce-apt.log" 2>&1
  rc=$?; echo "apt dans l'amorce : code $rc ; dernières lignes :"; tail -3 "$W/debian-amorce-apt.log" | sed 's/^/  | /'
  [ "$rc" = 0 ] || ko "installation de mmdebstrap dans l'amorce"
  i=$(find "$WDA/var/lib/apt/lists" -maxdepth 1 -name '*_InRelease' | head -1)
  [ -n "$i" ] && [ "$(sha256sum < "$i" | cut -c1-64)" = "$INRELEASE" ] && echo "OK   InRelease lu par apt égal à celui vérifié par le relevé" || echo "KO   InRelease différent du relevé"
  signaler "$WDA/var/cache/apt/archives" "$MIROIR (apt de l'amorce)"
  find "$WDA/var/cache/apt/archives" -maxdepth 1 -name '*.deb' | while read -r f; do echo "deb amorce ${f##*/} $(sha256sum < "$f" | cut -c1-64)"; done > "$W/debian-amorce-debs.txt"
  controle_debs "$W/debian-amorce-debs.txt"
  dans_hors "$WDA" mmdebstrap --version | sed 's/^/  /'
}

etape_debian_racine() {
  set +e
  sans_cle
  [ -x "$WDA/usr/bin/mmdebstrap" ] || ko "debian_amorce d'abord"
  absent "$WDA/o2/debian13.tar"; absent "$RD"
  dans_avec "$WDA" mmdebstrap --mode=root --variant=minbase --include="$DEB_PAQUETS" --skip=cleanup/apt/lists \
    --aptopt='Acquire::Check-Valid-Until "false"' \
    --customize-hook='for f in "$1"/var/cache/apt/archives/*.deb; do echo "deb racine ${f##*/} $(sha256sum < "$f" | cut -c1-64)"; done' \
    --customize-hook='dpkg-query --admindir="$1/var/lib/dpkg" -W -f="paquet \${Package} \${Version}\n"' \
    trixie /o2/debian13.tar "deb [check-valid-until=no] $MIROIR trixie main" > "$W/debian-mmdebstrap.log" 2>&1
  rc=$?; echo "mmdebstrap : code $rc ; dernières lignes :"; grep -v -E '^(deb|paquet) ' "$W/debian-mmdebstrap.log" | tail -4 | sed 's/^/  | /'
  [ "$rc" = 0 ] || ko "mmdebstrap (CR5) : voir les replis de la carte"
  echo "archive debian13.tar : $(stat -c %s "$WDA/o2/debian13.tar") octets, sha256 $(sha256sum < "$WDA/o2/debian13.tar" | cut -c1-64)"
  grep '^deb racine ' "$W/debian-mmdebstrap.log" | awk '{print "  téléchargé : " $3 " (sha256 " $4 ")"}'
  grep '^deb racine ' "$W/debian-mmdebstrap.log" | awk -v o="$MIROIR (mmdebstrap)" '{printf "o2/%s\t%s\t-\t%s\n", $3, o, $4}' >> "$LISTE"
  controle_debs "$W/debian-mmdebstrap.log"
  tr ',' '\n' <<<"$DEB_PAQUETS" | while IFS== read -r p v; do grep -qx "paquet $p $v" "$W/debian-mmdebstrap.log" && echo "OK   $p $v installé" || echo "KO   $p $v absent"; done
  mkdir -p "$RD"
  ns_hors tar -xf "$WDA/o2/debian13.tar" -C "$RD" --numeric-owner --exclude='dev/*' 2>/dev/null || echo "  tar : code $?"
  mkdir -p "$RD/dev" "$RD/proc"
  dans_hors "$RD" gpg --version | head -1 | sed 's/^/  gpg de la racine Debian : /'
}

etape_cle() {
  set +e
  [ -x "$RD/usr/bin/gpg" ] || ko "racine Debian absente : debian_racine d'abord"
  absent "$S"
  mkdir -m 700 "$S"
  LIENS="$S:/o2/secrets:rw $I:/o2/interne.sh:ro" TMPFS="/o2/g" \
    dans_hors "$RD" env GNUPGHOME=/o2/g /bin/bash /o2/interne.sh creer /o2/secrets
  rc=$?; [ "$rc" = 0 ] || ko "création de la clé : code $rc ; $S reste et bloque cle comme les étapes réseau (carte, « échecs »)"
  for f in "$S"/*; do echo "  $(basename "$f") : $(stat -c '%a %s' "$f") (mode, octets)"; done
  echo "dossier des secrets : $(stat -c %a "$S")"
}

etape_essai() {
  set +e
  [ -f "$S/cle-openpgp.asc" ] || ko "clé absente : cle d'abord"
  [ -x "$RR/usr/bin/gpg" ] || ko "racine Rocky absente : rocky_installer d'abord"
  absent "$W/x"; mkdir "$W/x"
  ns_hors bash -c "$PROGRAMME_ESSAI" _ "$RD" "$RR" "$S" "$I" "$W/x"
  rmdir "$W/x"
}

e=${1:-}
case "$e" in
  prealables|banc_chroot|rocky_telecharger|rocky_installer|debian_amorce|debian_racine|cle|essai)
    L=$R/o2-$e.log
    set +e
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o2.sh $(sha256sum < "$here/o2.sh" | cut -c1-16)… ; o2-interne.sh $(sha256sum < "$I" | cut -c1-16)…"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer | tee "$L"; rc=${PIPESTATUS[0]}
    n=$(grep -c -e '-----BEGIN PGP' "$L" || true)
    if [ "$n" != 0 ]; then : > "$L"; echo "KO   K3 : $n ligne(s) de bloc OpenPGP dans le journal : journal vidé" | tee "$L"; exit 1; fi
    echo "OK   K3 : aucune ligne de bloc OpenPGP armuré dans le journal" | tee -a "$L"
    k=$(grep -c '^KO' "$L" || true)
    [ "$e" = banc_chroot ] && k=$(grep -v 'refus attendu\|existe déjà : rien n.est écrasé' "$L" | grep -c '^KO' || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" | tee -a "$L"; rc=1; }
    exit "$rc" ;;
  *) echo "usage : $0 prealables | banc_chroot | rocky_telecharger | rocky_installer | debian_amorce | debian_racine | cle | essai" >&2; exit 64 ;;
esac
