#!/usr/bin/env bash
# Brique 09, O3 : rpm signé et dépôt rpm signé (D1 à D4, clé du PoC créée en O2). Tout sur l'hôte, sans réseau, sans installation
# sur l'hôte ; mécanisme d'o2.sh (unshare --map-auto --map-root-user -n, chroot). Fonctions ns_hors, CHROOT, dans_hors et
# extraire reprises d'o2.sh telles quelles (o2.sh 1a6f9cd0…).
#   prealables  lecture locale : copie du rpm (sha256 égal à 864d55f4…, M4c), racines, amorce, macros de signature de rpm.
#   repetition  À SEC : chaîne complète avec une clé JETABLE créée dans la racine Rocky ; tout est effacé après archivage.
#   signer      chaîne complète avec la clé du PoC (09/secrets, liée en lecture seule, jamais listée ni lue par la session) ;
#               le dépôt signé (rpm, repodata, repomd.xml.asc) et la clé publique restent dans o3/signer/ pour O5.
# Chaîne : signer (racine Rocky, gpg 2.3.3, rpm-sign, createrepo_c) ; contrôle B1 sur l'hôte (octets à partir de l'en-tête
# principal) ; témoins ; vérifier (amorce Rocky 9.8 neuve : rpmkeys, dnf avec gpgcheck=1 et repo_gpgcheck=1).
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o3.sh <étape>   (journal : resultats/o3-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
I2=$here/o2-interne.sh
I3=$here/o3-interne.sh
BASE=$HOME/.cache/supply-chain-poc/09
S=$BASE/secrets
RR=$BASE/o2/rocky/racine
O3=$BASE/o3
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont
ROCKY_M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d
RPM=sample-app-1.0.0-2.el9.x86_64.rpm
RPM_SRC=$HOME/.cache/supply-chain-poc/05/banc-m4c-comparaison-copie/m3/$RPM
RPM_SHA=864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f
cd "$BASE"

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; exit 1; }
absent() { [ ! -e "$1" ] || ko "$1 existe déjà : rien n'est réutilisé ni écrasé"; }
ns_hors() { unshare --map-auto --map-root-user -n -m -p --fork "$@"; }
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

b1() { # T : contrôle B1 sur l'hôte et rpm altéré d'un octet pour le témoin V4
  python3 -I - "$1/entree/$RPM" "$1/depot/$RPM" "$1/temoins/altere.rpm" <<'PY'
import hashlib, struct, sys
def lire(p):
    b = open(p, "rb").read()
    assert b[:4] == b"\xed\xab\xee\xdb", "lead"
    o = 96
    assert b[o:o + 3] == b"\x8e\xad\xe8", "en-tête de signature"
    n, h = struct.unpack(">II", b[o + 8:o + 16])
    fin = o + 16 + 16 * n + h
    p8 = fin + (-fin % 8)
    assert b[p8:p8 + 3] == b"\x8e\xad\xe8", "en-tête principal"
    return b, n, p8
a, na, pa = lire(sys.argv[1]); s, ns, ps = lire(sys.argv[2])
sh = lambda x: hashlib.sha256(x).hexdigest()
print(f"     entrée : {len(a)} octets, sha256 {sh(a)}, en-tête de signature à {na} entrées, en-tête principal à l'octet {pa}")
print(f"     signé  : {len(s)} octets, sha256 {sh(s)}, en-tête de signature à {ns} entrées, en-tête principal à l'octet {ps}")
print(f"     à partir de l'en-tête principal : entrée {sh(a[pa:])[:16]}…, signé {sh(s[ps:])[:16]}…")
print(("OK   " if a[pa:] == s[ps:] else "KO   ") + "B1 : octets égaux à partir de l'en-tête principal (en-tête principal et charge utile inchangés)")
print(("OK   " if a[:96] == s[:96] else "écart ") + "lead : 96 premiers octets " + ("égaux" if a[:96] == s[:96] else "différents"))
x = bytearray(s); x[-1] ^= 1
open(sys.argv[3], "wb").write(x)
print(f"     témoin altere.rpm : dernier octet de la charge utile inversé (bit de poids faible), sha256 {sh(bytes(x))[:16]}…")
PY
}

depots() { # T : un dossier de configuration de dnf par dépôt (chemins vus dans l'amorce de vérification, sous /o2/t)
  local t c
  for t in depot temoins/autre-cle temoins/repomd-modifie temoins/rpm-non-signe; do
    c=$1/repos/${t##*/}; mkdir -p "$c"
    printf '%s\n' "[o3-${t##*/}]" "name=Brique 09 O3 ${t##*/}" "baseurl=file:///o2/t/$t" 'enabled=1' 'gpgcheck=1' 'repo_gpgcheck=1' \
      'gpgkey=file:///o2/t/cle-publique.asc' 'metadata_expire=0' > "$c/o3.repo"
  done
  echo "dépôts de dnf écrits : $(ls "$1/repos" | paste -sd' ')"
}

chaine() { # MODE SECRETS : signer, B1, témoins, vérifier
  local m=$1 sec=$2 T=$O3/$1 V=$O3/$1-vierge
  absent "$T"; absent "$V"
  [ -x "$RR/usr/bin/rpmsign" ] || ko "racine Rocky absente : O2 d'abord"
  mkdir -p "$T/entree"
  cp -- "$RPM_SRC" "$T/entree/$RPM"
  [ "$(sha256sum < "$T/entree/$RPM" | cut -c1-64)" = "$RPM_SHA" ] && echo "OK   rpm d'entrée égal à ${RPM_SHA:0:16}… (M4c)" || ko "rpm d'entrée différent de $RPM_SHA"
  echo "### signer (racine Rocky, sans réseau, GNUPGHOME sur tmpfs)"
  LIENS="$sec:/o2/secrets:ro $T:/o2/t:rw $I3:/o2/o3-interne.sh:ro" TMPFS="/o2/g" \
    dans_hors "$RR" env GNUPGHOME=/o2/g /bin/bash /o2/o3-interne.sh signer /o2/secrets /o2/t
  echo "  code $?"
  [ -f "$T/depot/$RPM" ] && [ -f "$T/depot/repodata/repomd.xml.asc" ] || ko "signer n'a pas produit le dépôt signé"
  echo "### B1 sur l'hôte"
  b1 "$T"
  depots "$T"
  echo "### vérifier (amorce Rocky 9.8 neuve, sans réseau)"
  extraire "$OCI/rockylinux/rockylinux" "$ROCKY_M" "$V"
  LIENS="$T:/o2/t:ro $I3:/o2/o3-interne.sh:ro" dans_hors "$V" /bin/bash /o2/o3-interne.sh verifier /o2/t
  echo "  code $?"
  echo "produits : rpm signé $(sha256sum < "$T/depot/$RPM" | cut -c1-64) ; repomd.xml $(sha256sum < "$T/depot/repodata/repomd.xml" | cut -c1-64) ; repomd.xml.asc $(sha256sum < "$T/depot/repodata/repomd.xml.asc" | cut -c1-64)"
  echo "à effacer après archivage (chemins littéraux, dans l'espace de noms) : $V$([ "$m" = repetition ] && echo " et $T")"
}

etape_prealables() {
  [ "$(sha256sum < "$RPM_SRC" | cut -c1-64)" = "$RPM_SHA" ] && echo "OK   copie locale du rpm égale à ${RPM_SHA:0:16}… ($(stat -c %s "$RPM_SRC") octets)" || echo "KO   copie locale du rpm différente"
  for f in "$RR/usr/bin/rpmsign" "$RR/usr/bin/createrepo_c" "$RR/usr/bin/gpg2"; do [ -x "$f" ] && echo "OK   ${f#"$BASE"/} présent" || echo "KO   ${f#"$BASE"/} absent"; done
  [ -f "$OCI/rockylinux/rockylinux/blobs/sha256/$ROCKY_M" ] && echo "OK   manifeste de l'amorce Rocky 9.8 ${ROCKY_M:0:12} dans le cache local" || echo "KO   manifeste de l'amorce absent"
  [ -f "$S/cle-publique.asc" ] && echo "OK   clé publique du PoC présente (test -f, dossier non listé)" || echo "KO   clé publique du PoC absente"
  echo "macros de signature de la racine Rocky :"
  grep -n -E '^%__gpg[[:space:]]|_gpg_name|_gpg_path|_gpg_digest_algo|^%_pkgverify_level' "$RR/usr/lib/rpm/macros" | sed 's/^/  /'
  echo "dépendances du rpm (racine Rocky, rpm -qpR) :"
  LIENS="$RPM_SRC:/o2/entree.rpm:ro" dans_hors "$RR" rpm -qpR --nosignature /o2/entree.rpm 2>&1 | sed 's/^/  /'
  echo "place libre sous $BASE : $(df -B1M --output=avail "$BASE" | tail -1 | tr -d ' ') Mo"
  [ -e "$O3" ] && echo "KO   $O3 existe déjà" || echo "OK   $O3 absent"
}
etape_repetition() {
  set +e
  absent "$O3/repetition-secrets"
  mkdir -p -m 700 "$O3/repetition-secrets"
  echo "### clé jetable créée dans la racine Rocky (o2-interne.sh creer, RSA 4096, 2 jours)"
  LIENS="$O3/repetition-secrets:/o2/secrets:rw $I2:/o2/interne.sh:ro" TMPFS="/o2/g" \
    dans_hors "$RR" env GNUPGHOME=/o2/g O2_NOM="Banc 09 O3 cle jetable" O2_EXPIRE=2d /bin/bash /o2/interne.sh creer /o2/secrets
  echo "  code $?"
  chaine repetition "$O3/repetition-secrets"
  echo "à effacer aussi : $O3/repetition-secrets"
}
etape_signer() {
  set +e
  [ -f "$S/cle-openpgp.asc" ] || ko "clé du PoC absente"
  chaine signer "$S"
}

e=${1:-}
case "$e" in
  prealables|repetition|signer)
    [ "$e" = prealables ] || mkdir -p "$O3"
    L=$R/o3-$e.log
    set +e
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o3.sh $(sha256sum < "$here/o3.sh" | cut -c1-16)… ; o3-interne.sh $(sha256sum < "$I3" | cut -c1-16)… ; o2-interne.sh $(sha256sum < "$I2" | cut -c1-16)…"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer | tee "$L"; rc=${PIPESTATUS[0]}
    n=$(grep -c -e '-----BEGIN PGP' "$L" || true)
    if [ "$n" != 0 ]; then : > "$L"; echo "KO   K3 : $n ligne(s) de bloc OpenPGP dans le journal : journal vidé" | tee "$L"; exit 1; fi
    echo "OK   K3 : aucune ligne de bloc OpenPGP armuré dans le journal" | tee -a "$L"
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" | tee -a "$L"; rc=1; }
    exit "$rc" ;;
  *) echo "usage : $0 prealables | repetition | signer" >&2; exit 64 ;;
esac
