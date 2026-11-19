#!/usr/bin/env bash
# Brique 09, O2 (décisions D1 à D4 et « racines (a) » du 19/11/2026) : racines de signature sur l'hôte et clé OpenPGP du PoC.
# Mécanisme de la 05 (m1b-amorce-lecture.sh, m1b-repro.sh) : racine dans un dossier, unshare --map-auto --map-root-user, chroot.
# Ni podman, ni cluster, ni Zot.
#
#   prealables  lecture locale : amorces du cache OCI, clé Rocky de l'amorce, place, espace de noms, dossiers absents.
#   construire  ACCORD NOMMÉ : réseau et installation de paquets dans des racines neuves. Refuse si le dossier des secrets
#               existe (K1 : aucune étape réseau tant qu'une clé existe sur l'hôte).
#                 Rocky : amorce rockylinux:9.8 (ed654c69) extraite une fois ; dnf-3 --installroot depuis vault/rocky/9.8
#                         (gpgcheck=1, repo_gpgcheck=1) : gnupg2, rpm-sign, createrepo_c épinglés.
#                 Debian : amorce trixie-20261104-slim (7378260c) extraite une fois ; mmdebstrap 1.5.7-1+deb13u1 installé
#                          depuis l'instantané 20261105T000000Z ; racine minbase par mmdebstrap --mode=root : gnupg, gpg, gpgv,
#                          gpg-agent, gpgconf, apt-utils, sqv épinglés.
#   cle         ACCORD NOMMÉ : clé du PoC créée dans la racine Debian (gpg 2.4.7), sans réseau, homedir sur tmpfs ; exports
#               armurés vers le dossier des secrets (0700, fichiers 0600) ; refuse d'écraser (K4).
#   essai       ACCORD NOMMÉ : sans réseau ; import et signature d'un fichier d'essai dans les deux racines (K5), vérifications
#               croisées par gpgv et sqv ; sens inverse sur une clé jetable (K5b) ; aucun journal ne contient « BEGIN PGP » (K3).
#
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o2.sh <étape>   (journal : resultats/o2-<étape>.log)
# Aucun « rm » : les dossiers de travail ont des noms fixes, et chaque étape refuse un dossier déjà présent.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
BASE=$HOME/.cache/supply-chain-poc/09
W=$BASE/o2
S=$BASE/secrets
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont
P1=$BASE/releve-20261119T144438Z
ROCKY_M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d
DEB_M=7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392
VAULT=https://dl.rockylinux.org/vault/rocky/9.8
SNAP=20261105T000000Z
MIROIR=http://snapshot.debian.org/archive/debian/$SNAP   # http : l'amorce n'a pas de certificats ; intégrité par InRelease (06)
INRELEASE=0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675   # o2-releve.log, vérifié par les 3 clés de la 06
ROCKY_PAQUETS="gnupg2-2.3.3-5.el9_7 rpm-sign-4.16.1.3-40.el9 createrepo_c-0.20.1-4.el9"
DEB_PAQUETS="gnupg=2.4.7-21+deb13u1,gpg=2.4.7-21+deb13u1+b5,gpgv=2.4.7-21+deb13u1+b5,gpg-agent=2.4.7-21+deb13u1+b5,gpgconf=2.4.7-21+deb13u1+b5,apt-utils=3.0.3,sqv=1.3.0-3+b2"
V_MMDEBSTRAP=1.5.7-1+deb13u1
RR=$W/amorce-rocky98/racine          # racine Rocky de signature (installroot dans l'amorce, utilisée une fois)
RD=$W/racine-debian13                # racine Debian de signature (archive de mmdebstrap extraite)
LISTE=$R/releve-amont-telechargements.tsv
mkdir -p "$BASE" "$R"
cd "$BASE"

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; exit 1; }
ns_hors() { unshare --map-auto --map-root-user -n -m -p --fork "$@"; }   # sans réseau
ns_avec() { unshare --map-auto --map-root-user -m -p --fork "$@"; }      # avec réseau, jamais avec la clé (K1)

# Programme lancé dans l'espace de noms : montages, puis chroot. Arguments : RACINE RESEAU(0|1) commande…
# Variable LIENS : « source:cible:ro|rw » séparés par des espaces ; TMPFS : chemins (dans la racine) à couvrir d'un tmpfs.
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
  echo "OK   couche ${l:0:12} de ${m:0:12} extraite dans $d ($(du -sb "$d" | cut -f1) octets)"
}
signaler() { # DOSSIER ORIGINE : chaque paquet téléchargé journalisé (nom, origine, taille, sha256) et ajouté à la liste
  find "$1" -type f \( -name '*.rpm' -o -name '*.deb' \) -printf '%f\t%s\t%p\n' | sort | while IFS=$'\t' read -r n t p; do
    s=$(sha256sum < "$p" | cut -c1-64)
    printf '%s\t%s\t%s\t%s\n' "o2/$n" "$2" "$t" "$s" >> "$LISTE"
    echo "  téléchargé : $n ($t octets, sha256 $s)"
  done
}

etape_prealables() {
  set +e
  echo "prealables commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
  echo "place libre sous ~/.cache : $(df -B1M --output=avail "$HOME/.cache" | tail -1 | tr -d ' ') Mo"
  mkdir -p "$BASE/o2-sonde"
  ns_hors bash -c 'mount -t tmpfs -o size=1m,mode=700 tmpfs "$1" && mount -t proc proc /proc && echo "OK   espace de noms : tmpfs monté ($(stat -f -c %T "$1")), interfaces [$(awk -F: "NR > 2 {gsub(/ /, \"\", \$1); print \$1}" /proc/self/net/dev | paste -sd" ")]"' _ "$BASE/o2-sonde"
  rmdir "$BASE/o2-sonde"
  for d in "$W" "$S"; do [ -e "$d" ] && echo "présent : $d" || echo "absent : $d"; done
  echo "secrets-depot.sh lit : $(grep -oE 'supply-chain-poc/[0-9a-z]+/secrets' "$here/../../../tools/secrets-depot.sh" | sort -u | paste -sd' ') (09/secrets à ajouter, A-REPORTER.md)"
  echo "prealables finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

etape_construire() {
  set +e
  echo "construire commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  [ ! -e "$S" ] || ko "$S existe : aucune étape réseau tant qu'une clé existe sur l'hôte (K1)"
  [ ! -e "$W" ] || ko "$W existe déjà : rien n'est réutilisé"
  mkdir -p "$W"

  echo "## Rocky 9.8"
  A=$W/amorce-rocky98
  extraire "$OCI/rockylinux/rockylinux" "$ROCKY_M" "$A"
  mkdir -p "$A/o2/repos" "$A/o2/cache" "$A/racine"
  for d in BaseOS AppStream; do
    printf '[o2-%s]\nname=vault 9.8 %s\nbaseurl=%s/%s/x86_64/os/\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9\nenabled=1\n\n' \
      "$d" "$d" "$VAULT" "$d" >> "$A/o2/repos/o2.repo"
  done
  dans_avec "$A" /usr/bin/dnf-3 -y --installroot=/racine --releasever=9 --setopt=reposdir=/o2/repos --setopt=cachedir=/o2/cache \
    --setopt=keepcache=True --setopt=install_weak_deps=False --setopt=tsflags=nodocs \
    install bash coreutils gawk grep findutils $ROCKY_PAQUETS > "$W/rocky-dnf.log" 2>&1; rc=$?
  echo "dnf --installroot : code $rc ; dernières lignes :"; tail -5 "$W/rocky-dnf.log" | sed 's/^/  | /'
  [ "$rc" = 0 ] || ko "installation Rocky"
  signaler "$A/o2/cache" "$VAULT (dnf, gpgcheck=1)"
  dans_hors "$A" rpm --root /racine -qa --qf '%{NEVRA} %{RSAHEADER:pgpsig}\n' | sort > "$W/rocky-paquets.txt"   # 05 : SIGPGP vide chez Rocky
  echo "racine Rocky : $(wc -l < "$W/rocky-paquets.txt") paquets ; liste sha256 $(sha256sum < "$W/rocky-paquets.txt" | cut -c1-64)"
  for p in $ROCKY_PAQUETS; do grep -q "^$p\." "$W/rocky-paquets.txt" && echo "OK   $p installé" || ko "$p absent"; done
  echo "signatures des paquets (clés citées) : $(awk '{print $NF}' "$W/rocky-paquets.txt" | sort | uniq -c | paste -sd' ')"
  dans_hors "$RR" gpg2 --version | head -1 | sed 's/^/  racine Rocky : /'

  echo "## Debian 13"
  B=$W/amorce-debian13
  extraire "$OCI/library/debian" "$DEB_M" "$B"
  mkdir -p "$B/o2"
  [ -f "$B/etc/apt/sources.list.d/debian.sources" ] && mv "$B/etc/apt/sources.list.d/debian.sources" "$B/o2/debian.sources.origine"
  echo "deb [check-valid-until=no] $MIROIR trixie main" > "$B/etc/apt/sources.list.d/instantane.list"
  dans_avec "$B" /bin/sh -c "apt-get -q update && apt-get -q -y --no-install-recommends -o APT::Keep-Downloaded-Packages=true install mmdebstrap=$V_MMDEBSTRAP" > "$W/debian-amorce-apt.log" 2>&1; rc=$?
  echo "apt dans l'amorce : code $rc ; dernières lignes :"; tail -3 "$W/debian-amorce-apt.log" | sed 's/^/  | /'
  [ "$rc" = 0 ] || ko "installation de mmdebstrap dans l'amorce"
  i=$(find "$B/var/lib/apt/lists" -name '*_InRelease' | head -1)
  [ "$(sha256sum < "$i" | cut -c1-64)" = "$INRELEASE" ] && echo "OK   InRelease lu par apt égal à celui vérifié par le relevé ($INRELEASE)" || ko "InRelease différent du relevé"
  signaler "$B/var/cache/apt/archives" "$MIROIR (apt de l'amorce)"
  dans_avec "$B" mmdebstrap --mode=root --variant=minbase --include="$DEB_PAQUETS" \
    --aptopt='Acquire::Check-Valid-Until "false"' \
    --customize-hook='find "$1/var/cache/apt/archives" -name "*.deb" -exec sha256sum {} + > /o2/debian13-debs.txt' \
    --customize-hook='dpkg-query --admindir="$1/var/lib/dpkg" -W -f="\${Package} \${Version}\n" > /o2/debian13-paquets.txt' \
    trixie /o2/debian13.tar "deb [check-valid-until=no] $MIROIR trixie main" > "$W/debian-mmdebstrap.log" 2>&1; rc=$?
  echo "mmdebstrap : code $rc ; dernières lignes :"; tail -3 "$W/debian-mmdebstrap.log" | sed 's/^/  | /'
  [ "$rc" = 0 ] || ko "mmdebstrap"
  echo "archive debian13.tar : $(stat -c %s "$B/o2/debian13.tar") octets, sha256 $(sha256sum < "$B/o2/debian13.tar" | cut -c1-64)"
  echo "paquets de la racine Debian : $(wc -l < "$B/o2/debian13-paquets.txt") ; debs téléchargés par mmdebstrap : $(wc -l < "$B/o2/debian13-debs.txt")"
  awk '{n=$2; sub(".*/", "", n); print "  téléchargé : " n " (sha256 " $1 ")"}' "$B/o2/debian13-debs.txt"
  awk -v o="$MIROIR (mmdebstrap)" '{n=$2; sub(".*/", "", n); printf "o2/%s\t%s\t-\t%s\n", n, o, $1}' "$B/o2/debian13-debs.txt" >> "$LISTE"
  tr ',' '\n' <<<"$DEB_PAQUETS" | while IFS== read -r p v; do grep -qx "$p $v" "$B/o2/debian13-paquets.txt" && echo "OK   $p $v installé" || ko "$p $v absent"; done
  mkdir -p "$RD"
  ns_hors tar -xf "$B/o2/debian13.tar" -C "$RD" --numeric-owner --exclude='dev/*' 2>/dev/null || echo "  tar : code $?"
  mkdir -p "$RD/dev" "$RD/proc"
  dans_hors "$RD" gpg --version | head -1 | sed 's/^/  racine Debian : /'
  echo "construire finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

etape_cle() {
  set +e
  echo "cle commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  [ -x "$RD/usr/bin/gpg" ] || ko "racine Debian absente : construire d'abord"
  [ ! -e "$S" ] || ko "$S existe déjà : rien n'est écrasé (K4)"
  mkdir -m 700 "$S"
  LIENS="$S:/o2/secrets:rw $here/o2-interne.sh:/o2/interne.sh:ro" TMPFS="/o2/g" \
    dans_hors "$RD" env GNUPGHOME=/o2/g /bin/bash /o2/interne.sh creer /o2/secrets; rc=$?
  [ "$rc" = 0 ] || ko "création de la clé : code $rc"
  for f in "$S"/*; do echo "  $(basename "$f") : $(stat -c '%a %s' "$f") (mode, octets)"; done
  echo "dossier des secrets : $(stat -c %a "$S")"
  echo "cle finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

etape_essai() {
  set +e
  echo "essai commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  [ -f "$S/cle-openpgp.asc" ] || ko "clé absente : cle d'abord"
  mkdir -p "$W/x"
  # Un seul espace de noms sans réseau : un tmpfs commun (sorties), lié dans les deux racines ; un tmpfs neuf par appel de gpg.
  ns_hors bash -s -- "$RD" "$RR" "$S" "$here/o2-interne.sh" "$W/x" <<'NS'
set -u
D=$1 Rk=$2 S=$3 I=$4 X=$5
mount -t tmpfs -o size=64m,mode=700 tmpfs "$X"
mkdir -p "$X/deb" "$X/rpm" "$X/k5b"
for r in "$D" "$Rk"; do
  mount --rbind /dev "$r/dev"; mount -t proc proc "$r/proc"
  for c in /o2/x /o2/secrets /o2/g; do mkdir -p "$r$c"; done
  : > "$r/o2/interne.sh"; mount --bind "$I" "$r/o2/interne.sh"; mount -o remount,bind,ro "$r/o2/interne.sh"
  mount --bind "$S" "$r/o2/secrets"; mount -o remount,bind,ro "$r/o2/secrets"
  mount --bind "$X" "$r/o2/x"
done
g() { # RACINE LIBELLÉ commande… : gpg avec un homedir tmpfs neuf, démonté après
  local r=$1 l=$2; shift 2
  echo "### $l"
  mount -t tmpfs -o size=32m,mode=700 tmpfs "$r/o2/g"
  HOME=/root GNUPGHOME=/o2/g PATH=/usr/sbin:/usr/bin:/sbin:/bin chroot "$r" /bin/bash /o2/interne.sh "$@"; local rc=$?
  chroot "$r" gpgconf --homedir /o2/g --kill all 2>/dev/null
  umount -l "$r/o2/g"
  echo "  code $rc"
}
g "$D" "E1 Debian 2.4.7 : import de la clé du PoC et signature" signer /o2/secrets/cle-openpgp.asc /o2/x/deb
g "$D" "E2 Debian : vérification par gpgv et sqv" verifier /o2/secrets/cle-publique.asc /o2/x/deb/essai.txt /o2/x/deb/essai.txt.sig
g "$Rk" "E3 Rocky 2.3.3 : import de la clé du PoC et signature (K5)" signer /o2/secrets/cle-openpgp.asc /o2/x/rpm
g "$Rk" "E4 Rocky : vérification de la signature Debian par gpgv" verifier /o2/secrets/cle-publique.asc /o2/x/deb/essai.txt /o2/x/deb/essai.txt.sig
g "$D" "E5 Debian : vérification de la signature Rocky par gpgv et sqv" verifier /o2/secrets/cle-publique.asc /o2/x/rpm/essai.txt /o2/x/rpm/essai.txt.sig
g "$Rk" "E6 Rocky 2.3.3 : clé jetable créée (K5b)" jetable /o2/x/k5b
g "$D" "E7 Debian 2.4.7 : import de la clé jetable et signature (K5b)" signer /o2/x/k5b/jetable.asc /o2/x/k5b
g "$Rk" "E8 Rocky : vérification de la signature K5b par gpgv" verifier /o2/x/k5b/jetable-publique.asc /o2/x/k5b/essai.txt /o2/x/k5b/essai.txt.sig
NS
  rmdir "$W/x"
  echo "essai fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

e=${1:-}
case "$e" in
  prealables|construire|cle|essai)
    set +e   # chaque étape vérifie ses codes elle-même (ko) ; le code de l'étape est relu dans PIPESTATUS
    "etape_$e" 2>&1 | masquer | tee "$R/o2-$e.log"; rc=${PIPESTATUS[0]}
    n=$(grep -c 'BEGIN PGP' "$R/o2-$e.log" || true)
    [ "$n" = 0 ] && echo "OK   K3 : aucun « BEGIN PGP » dans resultats/o2-$e.log" | tee -a "$R/o2-$e.log" || { echo "KO   K3 : $n ligne(s) « BEGIN PGP » dans le journal" | tee -a "$R/o2-$e.log"; rc=1; }
    exit "$rc" ;;
  *) echo "usage : $0 prealables | construire | cle | essai" >&2; exit 64 ;;
esac
