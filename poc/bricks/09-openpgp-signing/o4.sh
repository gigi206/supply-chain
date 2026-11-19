#!/usr/bin/env bash
# Brique 09, O4 : dépôt apt signé (D1 a : le deb reste tel quel), vérifié par apt de Debian 13. Tout sur l'hôte, sans réseau,
# sans installation sur l'hôte ; mécanisme d'o2.sh (unshare --map-auto --map-root-user -n, chroot). Fonctions ns_hors, CHROOT,
# dans_hors et extraire reprises d'o3.sh telles quelles.
#   prealables  lecture locale : copie du deb (sha256 égal à f66bbeb2…, S3 de la 06), racine Debian, amorce Debian 13.
#   repetition  À SEC : chaîne complète avec une clé JETABLE créée dans la racine Debian ; tout est effacé après archivage.
#   signer      chaîne complète avec la clé du PoC (09/secrets, liée en lecture seule, jamais listée ni lue par la session) ;
#               le dépôt signé et la clé publique restent dans o4/signer/ pour O5.
# Chaîne : signer (racine Debian, gpg 2.4.7, apt-ftparchive 3.0.3) ; contrôle du lien sur l'hôte (Release → Packages → deb) ;
# vérifier, deux fois : dans la racine Debian (apt 3.0.3, sqv et gpgv présents) et dans l'amorce Debian 13 neuve (apt 3.0.4,
# gpgv absent) : apt-get update avec Signed-By, vérificateur lu dans les refus, apt-get download ; contrôle du deb
# téléchargé sur l'hôte ; aucun en-tête de clé privée dans le dossier produit.
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o4.sh <étape>   (journal : resultats/o4-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
I2=$here/o2-interne.sh
I4=$here/o4-interne.sh
BASE=$HOME/.cache/supply-chain-poc/09
S=$BASE/secrets
RD=$BASE/o2/racine-debian13
O4=$BASE/o4
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont
DEB_M=7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392
DEB=sample-app_1.0.0-2_amd64.deb
POOL=pool/main/s/sample-app
DEB_SRC=$HOME/.cache/supply-chain-poc/08/travail/s3-06/build-1/$DEB
DEB_SHA=f66bbeb2aba31e5220b332ff3941697dce7660259aa182047a58e77f4f51892b
CAS="depot sans-inrelease autre-cle release-modifie packages-modifie deb-modifie sha1 sans-signed-by release-gpg-binaire"
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
couche() { # OCI MANIFESTE : digest de la couche unique, manifeste et couche contrôlés par sha256
  python3 -I - "$1" "$2" <<'PY'
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
}
extraire() { # OCI MANIFESTE DESTINATION : couche unique contrôlée par sha256, extraite sans réseau
  local o=$1 m=$2 d=$3 l
  l=$(couche "$o" "$m") || ko "manifeste ou couche $m"
  mkdir -p "$d"
  ns_hors tar -xf "$o/blobs/sha256/$l" -C "$d" --numeric-owner --exclude='dev/*' 2>/dev/null || echo "  tar : code $? (fichiers spéciaux ignorés)"
  mkdir -p "$d/dev" "$d/proc"
  echo "OK   couche ${l:0:12} de ${m:0:12} extraite dans $d"
}

lien() { # T : chaîne Release → Packages → deb sur l'hôte (le lien deb de D1 a est une identité d'empreinte)
  python3 -I - "$1/depot/dists/poc/Release" "$1/depot/dists/poc" "$1/depot" "$DEB_SHA" <<'PY'
import hashlib, os, sys
release, dists, depot, attendu = sys.argv[1:5]
def h(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest(), os.path.getsize(p)
champs, section = {}, None
for l in open(release, encoding="utf-8").read().splitlines():
    if l.startswith(" ") and section == "SHA256":
        s, n, f = l.split()
        champs[f] = (s, int(n))
    elif not l.startswith(" "):
        section = l.split(":")[0]
erreurs = 0
for f in ("main/binary-amd64/Packages", "main/binary-amd64/Packages.gz"):
    if f not in champs:
        print(f"     {f} absent de Release"); erreurs += 1; continue
    if h(os.path.join(dists, f)) == champs[f]:
        print(f"     {f} : sha256 et taille égaux à Release ({champs[f][0][:16]}…, {champs[f][1]} octets)")
    else:
        print(f"     {f} : DIFFÉRENT de Release"); erreurs += 1
strophes = [s for s in open(os.path.join(dists, "main/binary-amd64/Packages"), encoding="utf-8").read().split("\n\n") if s.strip()]
print(f"     Packages : {len(strophes)} strophe(s)")
for s in strophes:
    d = dict(l.split(": ", 1) for l in s.splitlines() if ": " in l and not l.startswith(" "))
    print(f"     strophe : {d.get('Package')} {d.get('Version')} Size {d.get('Size')} Filename {d.get('Filename')} SHA256 {d.get('SHA256')}")
    if d.get("SHA256") != attendu:
        print("     SHA256 de la strophe différent de f66bbeb2…"); erreurs += 1
    s2, n2 = h(os.path.join(depot, d["Filename"]))
    if s2 != d.get("SHA256") or str(n2) != d.get("Size"):
        print("     fichier du dépôt différent de la strophe"); erreurs += 1
print(("OK   " if erreurs == 0 and len(strophes) == 1 else "KO   ") + "L1 lien : Release → Packages → deb, strophe unique portant f66bbeb2…, fichier égal")
PY
}

sources() { # T : un dossier de sources apt par cas (chemins vus dans l'amorce, sous /o2/t)
  local c u
  for c in $CAS; do
    mkdir -p "$1/sources/$c"
    case $c in depot|sans-signed-by) u=depot ;; *) u=temoins/$c ;; esac
    { printf '%s\n' 'Types: deb' "URIs: file:/o2/t/$u" 'Suites: poc' 'Components: main'
      [ "$c" = sans-signed-by ] || printf '%s\n' 'Signed-By: /o2/t/cle-publique.asc'; } > "$1/sources/$c/o4.sources"
  done
  echo "sources apt écrites : $(ls "$1/sources" | paste -sd' ')"
}

chaine() { # MODE SECRETS : signer, lien, vérifier, contrôles sur l'hôte
  local m=$1 sec=$2 T=$O4/$1 V=$O4/$1-vierge s n
  absent "$T"; absent "$V"
  [ -x "$RD/usr/bin/apt-ftparchive" ] && [ -x "$RD/usr/bin/gpg" ] || ko "racine Debian absente : O2 d'abord"
  mkdir -p "$T/depot/$POOL"
  cp -- "$DEB_SRC" "$T/depot/$POOL/$DEB"
  [ "$(sha256sum < "$T/depot/$POOL/$DEB" | cut -c1-64)" = "$DEB_SHA" ] && echo "OK   deb d'entrée égal à ${DEB_SHA:0:16}… (S3 de la 06)" || ko "deb d'entrée différent de $DEB_SHA"
  echo "### signer (racine Debian, sans réseau, GNUPGHOME sur tmpfs)"
  LIENS="$sec:/o2/secrets:ro $T:/o2/t:rw $I4:/o2/o4-interne.sh:ro" TMPFS="/o2/g" \
    dans_hors "$RD" env GNUPGHOME=/o2/g /bin/bash /o2/o4-interne.sh signer /o2/secrets /o2/t
  echo "  code $?"
  [ -f "$T/depot/dists/poc/InRelease" ] && [ -f "$T/depot/dists/poc/Release.gpg" ] || ko "signer n'a pas produit le dépôt signé"
  echo "### lien sur l'hôte"
  lien "$T"
  sources "$T"
  echo "### vérifier dans la racine Debian (apt 3.0.3, sqv et gpgv présents ; dossiers d'apt jetables liés, secrets non liés)"
  absent "$O4/$m-racine-apt"; mkdir -p "$O4/$m-racine-apt"
  LIENS="$T:/o2/t:ro $I4:/o2/o4-interne.sh:ro $O4/$m-racine-apt:/o2/apt:rw" dans_hors "$RD" /bin/bash /o2/o4-interne.sh verifier /o2/t /o2/apt racine
  echo "  code $?"
  echo "### vérifier (amorce Debian 13 neuve, sans réseau)"
  extraire "$OCI/library/debian" "$DEB_M" "$V"
  LIENS="$T:/o2/t:ro $I4:/o2/o4-interne.sh:ro" dans_hors "$V" /bin/bash /o2/o4-interne.sh verifier /o2/t /var/tmp/o4 amorce
  echo "  code $?"
  echo "### contrôles sur l'hôte"
  for d in "racine:$O4/$m-racine-apt" "amorce:$V/var/tmp/o4"; do
    for c in depot sans-inrelease; do
      s=$(sha256sum < "${d#*:}/$c/telechargement/$DEB" 2>/dev/null | cut -c1-64)
      [ "$s" = "$DEB_SHA" ] && echo "OK   deb téléchargé par apt (${d%%:*}, $c) égal à ${DEB_SHA:0:16}… (relu sur l'hôte)" || echo "KO   deb téléchargé par apt (${d%%:*}, $c) : ${s:-absent}"
    done
  done
  s=$(sha256sum < "$T/depot/$POOL/$DEB" | cut -c1-64)
  [ "$s" = "$DEB_SHA" ] && echo "OK   deb du dépôt signé inchangé (D1 a)" || echo "KO   deb du dépôt signé modifié : $s"
  n=$(grep -r -l -E '^[[:space:]]*-----BEGIN PGP PRIVATE KEY BLOCK-----[[:space:]]*$' "$T" | wc -l)
  [ "$n" = 0 ] && echo "OK   aucun fichier de $T ne porte d'en-tête de clé privée" || echo "KO   $n fichier(s) de $T portent un en-tête de clé privée"
  echo "produits : InRelease $(sha256sum < "$T/depot/dists/poc/InRelease" | cut -c1-64) ; Release $(sha256sum < "$T/depot/dists/poc/Release" | cut -c1-64) ; Release.gpg $(sha256sum < "$T/depot/dists/poc/Release.gpg" | cut -c1-64)"
  echo "à effacer après archivage (chemins littéraux, dans l'espace de noms) : $V et $O4/$m-racine-apt$([ "$m" = repetition ] && echo " et $T")"
}

etape_prealables() {
  local l t
  [ "$(sha256sum < "$DEB_SRC" | cut -c1-64)" = "$DEB_SHA" ] && echo "OK   copie locale du deb égale à ${DEB_SHA:0:16}… ($(stat -c %s "$DEB_SRC") octets)" || echo "KO   copie locale du deb différente"
  for f in "$RD/usr/bin/gpg" "$RD/usr/bin/apt-ftparchive" "$RD/usr/bin/gzip" "$RD/usr/bin/gpgconf"; do [ -x "$f" ] && echo "OK   ${f#"$BASE"/} présent" || echo "KO   ${f#"$BASE"/} absent"; done
  echo "paquets de la racine Debian (dpkg-query dans la racine, sans réseau) :"
  dans_hors "$RD" dpkg-query -W -f='${Package} ${Version}\n' gnupg gpg gpgv apt apt-utils sqv gzip 2>&1 | sed 's/^/  /'
  l=$(couche "$OCI/library/debian" "$DEB_M") && echo "OK   manifeste ${DEB_M:0:12} et couche ${l:0:12} de l'amorce Debian 13 contrôlés par sha256" || echo "KO   manifeste ou couche de l'amorce Debian"
  echo "amorce Debian 13, entrées de la couche (tar -t, sans extraction ; liste lue en entier, sans grep -q dans un tube) :"
  t=$(tar -tf "$OCI/library/debian/blobs/sha256/$l") || echo "KO   tar -t de la couche : code $?"
  echo "  $(printf '%s\n' "$t" | wc -l) entrées"
  for p in usr/bin/sqv usr/bin/gpgv usr/bin/gpg usr/share/apt/default-sequoia.config etc/apt/apt.conf.d/docker-clean; do
    [ "$(printf '%s\n' "$t" | grep -c -x "$p")" -gt 0 ] && echo "  $p : présent" || echo "  $p : absent"
  done
  echo "chaînes de libapt-pkg.so.7.0 de la racine Debian (grep -a, relevé du choix du vérificateur) :"
  grep -a -o -E '/usr/bin/sqv|/usr/bin/gpgv|APT::Key::GPGVCommand|Debug::Acquire::gpgv|Preparing to exec: ' "$RD/usr/lib/x86_64-linux-gnu/libapt-pkg.so.7.0" | sort | uniq -c | sed 's/^/  /'
  echo "utilisateur _apt dans la racine Debian : $(grep -c '^_apt:' "$RD/etc/passwd") ligne(s) ; dans la couche de l'amorce : $(printf '%s\n' "$t" | grep -c -x 'etc/passwd') fichier passwd"
  [ -f "$S/cle-publique.asc" ] && echo "OK   clé publique du PoC présente (test -f, dossier non listé)" || echo "KO   clé publique du PoC absente"
  echo "place libre sous $BASE : $(df -B1M --output=avail "$BASE" | tail -1 | tr -d ' ') Mo"
  [ -e "$O4" ] && echo "KO   $O4 existe déjà" || echo "OK   $O4 absent"
}
etape_repetition() {
  set +e
  absent "$O4/repetition-secrets"
  mkdir -p -m 700 "$O4/repetition-secrets"
  echo "### clé jetable créée dans la racine Debian (o2-interne.sh creer, RSA 4096, 2 jours)"
  LIENS="$O4/repetition-secrets:/o2/secrets:rw $I2:/o2/interne.sh:ro" TMPFS="/o2/g" \
    dans_hors "$RD" env GNUPGHOME=/o2/g O2_NOM="Banc 09 O4 cle jetable" O2_EXPIRE=2d /bin/bash /o2/interne.sh creer /o2/secrets
  echo "  code $?"
  chaine repetition "$O4/repetition-secrets"
  echo "à effacer aussi : $O4/repetition-secrets"
}
etape_signer() {
  set +e
  [ -f "$S/cle-openpgp.asc" ] || ko "clé du PoC absente"
  chaine signer "$S"
}

e=${1:-}
case "$e" in
  prealables|repetition|signer)
    [ "$e" = prealables ] || mkdir -p "$O4"
    L=$R/o4-$e.log
    set +e
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o4.sh $(sha256sum < "$here/o4.sh" | cut -c1-16)… ; o4-interne.sh $(sha256sum < "$I4" | cut -c1-16)… ; o2-interne.sh $(sha256sum < "$I2" | cut -c1-16)…"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer | tee "$L"; rc=${PIPESTATUS[0]}
    n=$(grep -c -e '-----BEGIN PGP' "$L" || true)
    if [ "$n" != 0 ]; then : > "$L"; echo "KO   K3 : $n ligne(s) de bloc OpenPGP dans le journal : journal vidé" | tee "$L"; exit 1; fi
    echo "OK   K3 : aucune ligne de bloc OpenPGP armuré dans le journal" | tee -a "$L"
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" | tee -a "$L"; rc=1; }
    exit "$rc" ;;
  *) echo "usage : $0 prealables | repetition | signer" >&2; exit 64 ;;
esac
