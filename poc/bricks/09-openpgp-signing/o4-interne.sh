#!/bin/bash
# Brique 09, O4 : dépôt apt signé et vérification par apt, exécutés DANS une racine (sous chroot, sans réseau) par o4.sh.
#   signer SECRETS T   racine Debian 13 de signature (gpg 2.4.7, apt-ftparchive 3.0.3) ; GNUPGHOME sur tmpfs ; clé importée de
#                      SECRETS (lecture seule) ; deb de T/depot/pool laissé tel quel (D1 a) ; Packages, Packages.gz, Release,
#                      Release.gpg (armuré) et InRelease (SHA-512) ; clé publique exportée dans T ; témoins sous T/temoins.
#   verifier T B       tous les cas : apt-get update avec Signed-By (un dossier de sources, de listes, de cache et de
#                      téléchargement par cas, sous B), apt-get download du deb. Lancé deux fois par o4.sh : dans la racine
#                      Debian (apt 3.0.3, sqv ET gpgv présents ; B lié depuis l'hôte) et dans l'amorce Debian 13 neuve (apt 3.0.4,
#                      gpgv absent ; B dans l'amorce). Le vérificateur employé est lu dans les messages de refus (P5).
# Aucune sortie de clé privée (K3) ; réseau absent (K1, seulement lo dans /proc/self/net/dev). Ne lit ni n'écrit hors de T,
# SECRETS, GNUPGHOME et B.
set -uo pipefail
export LC_ALL=C
DEB=sample-app_1.0.0-2_amd64.deb
POOL=pool/main/s/sample-app
ko() { echo "KO   $*"; exit 1; }
reseau_ou_ko() {
  n=$(awk -F: 'NR > 2 {gsub(/ /, "", $1); print $1}' /proc/self/net/dev | paste -sd' ')
  [ "$n" = lo ] || ko "$(wc -w <<<"$n") interfaces réseau visibles, dont autre chose que lo (K1 ; noms non journalisés)"
  echo "OK   réseau absent : seule l'interface lo est visible (K1)"
}
publics() { sed -E 's/-----(BEGIN|END) PGP (SIGNED MESSAGE|SIGNATURE)-----/[en-tête public \1 \2 retiré]/'; }
code() { # LIBELLÉ ATTENDU(0|non0) COMMANDE... : lance, journalise la sortie (indentée), juge le code et, pour un refus, le motif.
  # non0 : refus attendu, compté OK seulement si la sortie porte le motif du cas (variable MOTIF, passée par l'appelant, sans
  # tenir compte de la casse) ; toutes les lignes qui le portent sont citées, séparées par « | ».
  # Les en-têtes publics de message signé ou de signature sont remplacés (la garde K3 d'o4.sh vide tout journal portant un
  # bloc OpenPGP) ; un en-tête de clé privée n'est pas remplacé et reste attrapé par K3.
  local l=$1 a=$2 rc out m; shift 2
  out=$("$@" 2>&1); rc=$?; DERNIERE=$out
  printf '%s\n' "$out" | publics | sed 's/^/     | /'
  m=$(printf '%s\n' "$out" | grep -i -E -e "${MOTIF:?motif absent}" | publics | sed 's/^ *//' | paste -sd'|')
  case $a in
    0) [ "$rc" = 0 ] && echo "OK   $l : code $rc" || echo "KO   $l : code $rc (attendu 0)" ;;
    non0) if [ "$rc" != 0 ] && [ -n "$m" ]; then echo "OK   $l : code $rc, motif « $MOTIF » : $m"
          elif [ "$rc" != 0 ]; then echo "KO   $l : code $rc, refus sans le motif attendu « $MOTIF »"
          else echo "KO   $l : code 0 (refus attendu)"; fi ;;
  esac
}
gpgx() { gpg --batch --no-tty --quiet "$@"; }
OPTS=(-o APT::FTPArchive::Release::Origin=poc -o APT::FTPArchive::Release::Label=poc -o APT::FTPArchive::Release::Suite=poc
      -o APT::FTPArchive::Release::Codename=poc -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main)
signer_detache() { # CLÉ DOSSIER ALGO [binaire] : Release.gpg seule (détachée, armurée sauf « binaire »)
  local a=(--armor); [ "${4:-}" = binaire ] && a=()
  gpgx --local-user "$1" --digest-algo "$3" "${a[@]}" --detach-sign -o "$2/dists/poc/Release.gpg" "$2/dists/poc/Release"
}
signer_release() { # CLÉ DOSSIER [ALGO] : Release.gpg (détachée, armurée) et InRelease (en clair), ALGO SHA512 par défaut
  signer_detache "$1" "$2" "${3:-SHA512}" &&
  gpgx --local-user "$1" --digest-algo "${3:-SHA512}" --clearsign -o "$2/dists/poc/InRelease" "$2/dists/poc/Release"
}
paquets_sig() { # FICHIER : paquet de signature (algorithme de clé, identifiant), version, algorithme de condensat.
  # Un InRelease est un message signé en clair : gpg --list-packets s'arrête aux données littérales ; le bloc de signature
  # est donc extrait (public) dans GNUPGHOME avant la lecture.
  local f=$1
  if [ "${f##*/}" = InRelease ]; then
    sed -n '/^-----BEGIN PGP SIGNATURE-----$/,/^-----END PGP SIGNATURE-----$/p' "$f" > "$GNUPGHOME/bloc-inrelease.asc"; f=$GNUPGHOME/bloc-inrelease.asc
  fi
  gpgx --list-packets "$f" 2>/dev/null | grep -E 'signature packet|version|digest algo' | tr -s ' \t' ' ' | paste -sd' '
}
sig_ok() { # LIBELLÉ DOSSIER CONDENSAT(10|2) CLÉ [FICHIERS] : signatures présentes, v4, RSA, condensat et clé attendus
  local l=$1 d=$2 n=$3 k=${4:(-16)} f p e=0
  for f in ${5:-Release.gpg InRelease}; do
    [ -f "$d/dists/poc/$f" ] || { echo "KO   $l : $f absent"; e=1; continue; }
    p=$(paquets_sig "$d/dists/poc/$f")
    echo "     $f : $p"
    if printf '%s' "$p" | grep -q -i "algo 1, keyid $k" && printf '%s' "$p" | grep -q 'version 4,' && printf '%s' "$p" | grep -q "digest algo $n,"; then :
    else echo "KO   $l : $f n'est pas une signature v4 RSA de ${k} avec le condensat $n"; e=1; fi
  done
  [ "$e" = 0 ] && echo "OK   $l : ${5:-Release.gpg InRelease}, v4, RSA, clé ${k}, condensat $n"
}
copie() { # DESTINATION SIGNATURES(avec|sans|sans-inrelease) : copie du dépôt signé, deb compris
  local d=$1
  mkdir -p "$d/$POOL" "$d/dists/poc/main/binary-amd64"
  cp -- "$T/depot/$POOL/$DEB" "$d/$POOL/$DEB"
  cp -- "$T/depot/dists/poc/main/binary-amd64/Packages" "$T/depot/dists/poc/main/binary-amd64/Packages.gz" "$d/dists/poc/main/binary-amd64/"
  cp -- "$T/depot/dists/poc/Release" "$d/dists/poc/Release"
  case $2 in
    avec) cp -- "$T/depot/dists/poc/Release.gpg" "$T/depot/dists/poc/InRelease" "$d/dists/poc/" ;;
    sans-inrelease) cp -- "$T/depot/dists/poc/Release.gpg" "$d/dists/poc/" ;;
  esac
}
TEMOINS="autre-cle release-modifie packages-modifie deb-modifie sha1 sans-inrelease release-gpg-binaire"

case "${1:-}" in
  signer)
    S=$2 T=$3
    umask 022   # le dépôt et la clé publique sont publics ; GNUPGHOME est un tmpfs en 700
    reseau_ou_ko
    [ "$(stat -f -c %T "$GNUPGHOME")" = tmpfs ] || ko "GNUPGHOME pas sur tmpfs (K2)"
    echo "OK   GNUPGHOME sur tmpfs ($GNUPGHOME)"
    echo "outils : $(dpkg-query -W -f='${Package} ${Version}\n' gnupg gpg gpgv apt-utils gzip 2>&1 | paste -sd';')"
    gpgx --import "$S/cle-openpgp.asc" 2>&1 | grep -v -i -E 'secret key|clé secrète' | sed 's/^/     gpg : /'
    fpr=$(gpgx --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10; exit}')
    [ -n "$fpr" ] || ko "aucune clé secrète importée"
    echo "clé importée : $fpr"
    [ -f "$T/depot/$POOL/$DEB" ] || ko "deb absent de T/depot/$POOL"
    mkdir -p "$T/depot/dists/poc/main/binary-amd64" "$T/temoins"
    gpgx --armor -o "$T/cle-publique.asc" --export "$fpr" && echo "clé publique exportée : $(wc -c < "$T/cle-publique.asc") octets"
    ( cd "$T/depot" && apt-ftparchive packages pool > dists/poc/main/binary-amd64/Packages ) && echo "OK   A1 apt-ftparchive packages : code 0" || echo "KO   A1 apt-ftparchive packages"
    gzip -9 -n -k "$T/depot/dists/poc/main/binary-amd64/Packages"
    sed 's/^/     | /' "$T/depot/dists/poc/main/binary-amd64/Packages"
    ( cd "$T/depot" && apt-ftparchive "${OPTS[@]}" release dists/poc > "$T/Release.tmp" ) && mv "$T/Release.tmp" "$T/depot/dists/poc/Release" \
      && echo "OK   A2 apt-ftparchive release : code 0" || echo "KO   A2 apt-ftparchive release"
    sed 's/^/     | /' "$T/depot/dists/poc/Release"
    # relevé R1 : apt-ftparchive 3.0.3 et SOURCE_DATE_EPOCH, deux sorties hors du dépôt
    for i in 1 2; do ( cd "$T/depot" && SOURCE_DATE_EPOCH=1763337600 apt-ftparchive "${OPTS[@]}" release dists/poc > "$T/Release.sde$i" ); done
    echo "R1 Date avec SOURCE_DATE_EPOCH=1763337600 : « $(grep '^Date:' "$T/Release.sde1" | cut -c7-) » ; deux sorties identiques : $(cmp -s "$T/Release.sde1" "$T/Release.sde2" && echo oui || echo non)"
    code "A3 signature de Release (SHA-512, clé du dépôt, Release.gpg armuré)" 0 signer_release "$fpr" "$T/depot"
    sig_ok "A3 dépôt" "$T/depot" 10 "$fpr"
    head -1 "$T/depot/dists/poc/Release.gpg" | grep -q -x -- '-----BEGIN PGP SIGNATURE-----' && echo "OK   A3 Release.gpg armuré" || echo "KO   A3 Release.gpg non armuré"
    # témoins : autre clé (jetable, même homedir tmpfs), Release modifié après signature, Packages modifié, deb modifié,
    # signature SHA-1 (clé du dépôt), sans InRelease (accepté attendu), Release.gpg binaire sans InRelease
    printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 3072' 'Key-Usage: sign' 'Name-Real: Banc 09 O4 autre cle jetable' \
      'Expire-Date: 2d' '%commit' > "$GNUPGHOME/autre"
    gpgx --gen-key "$GNUPGHOME/autre" 2>&1 | sed 's/^/     gpg : /'
    autre=$(gpgx --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10}' | grep -v -x "$fpr" | head -1)
    [ -n "$autre" ] && echo "clé jetable du témoin « autre clé » : $autre" || echo "KO   témoin autre-cle : clé jetable absente"
    W=$T/temoins
    copie "$W/autre-cle" sans; signer_release "$autre" "$W/autre-cle"; sig_ok "construction du témoin autre-cle" "$W/autre-cle" 10 "${autre:-0000000000000000}"
    copie "$W/release-modifie" avec; sed -i 's/^Label: poc$/Label: pod/' "$W/release-modifie/dists/poc/Release" "$W/release-modifie/dists/poc/InRelease"
    echo "     release-modifie : $(grep -c '^Label: pod$' "$W/release-modifie/dists/poc/Release" "$W/release-modifie/dists/poc/InRelease" | paste -sd' ')"
    copie "$W/packages-modifie" avec
    sed -i '/^Package: sample-app$/a X-Ajout: oui' "$W/packages-modifie/dists/poc/main/binary-amd64/Packages"
    gzip -9 -n -c "$W/packages-modifie/dists/poc/main/binary-amd64/Packages" > "$W/packages-modifie/dists/poc/main/binary-amd64/Packages.gz"
    copie "$W/deb-modifie" avec; printf 'x' >> "$W/deb-modifie/$POOL/$DEB"
    copie "$W/sha1" sans; signer_release "$fpr" "$W/sha1" SHA1; sig_ok "construction du témoin sha1" "$W/sha1" 2 "$fpr"
    copie "$W/sans-inrelease" sans-inrelease
    copie "$W/release-gpg-binaire" sans; signer_detache "$fpr" "$W/release-gpg-binaire" SHA512 binaire
    sig_ok "construction du témoin release-gpg-binaire" "$W/release-gpg-binaire" 10 "$fpr" Release.gpg
    head -1 "$W/release-gpg-binaire/dists/poc/Release.gpg" | grep -q -- '-----BEGIN' && echo "KO   témoin release-gpg-binaire : Release.gpg armuré" || echo "OK   témoin release-gpg-binaire : Release.gpg binaire, sans InRelease"
    for t in $TEMOINS; do
      echo "     témoin $t : $(ls "$W/$t/dists/poc" | paste -sd' ') ; deb $(sha256sum < "$W/$t/$POOL/$DEB" | cut -c1-16)…"
    done
    gpgconf --homedir "$GNUPGHOME" --kill all 2>/dev/null
    ;;
  verifier)
    T=$2 B=$3 lieu=$4
    reseau_ou_ko
    echo "outils ($lieu) : $(dpkg-query -W -f='${Package} ${Version}\n' apt sqv gpgv gnupg 2>&1 | paste -sd';')"
    for b in /usr/bin/sqv /usr/bin/gpgv; do [ -x "$b" ] && echo "     $b présent" || echo "     $b absent"; done
    for c in depot sans-inrelease autre-cle release-modifie packages-modifie deb-modifie sha1 sans-signed-by release-gpg-binaire; do
      D=$B/$c/telechargement
      mkdir -p "$B/$c/listes/partial" "$B/$c/cache/archives/partial" "$D"
      chown _apt "$D" 2>/dev/null || echo "     chown _apt de $D refusé : téléchargement hors bac à sable attendu"
      AO=(-o Dir::Etc::SourceList=/dev/null -o "Dir::Etc::SourceParts=/o2/t/sources/$c" -o "Dir::State::Lists=$B/$c/listes"
          -o "Dir::Cache=$B/$c/cache" -o Acquire::Languages=none)
      case $c in
        depot) code "V1 ($lieu) apt-get update, dépôt signé (Signed-By, InRelease)" 0 apt-get "${AO[@]}" update ;;
        sans-inrelease) code "V2 ($lieu) apt-get update, dépôt sans InRelease (Release + Release.gpg armuré)" 0 apt-get "${AO[@]}" update ;;
        deb-modifie) code "V3 ($lieu) apt-get update, témoin deb-modifie (index intacts, accepté)" 0 apt-get "${AO[@]}" update ;;
        autre-cle|sans-signed-by) MOTIF='Missing key' code "V4 ($lieu) apt-get update, témoin $c (refus attendu)" non0 apt-get "${AO[@]}" update ;;
        release-modifie) MOTIF='manipulated' code "V4 ($lieu) apt-get update, témoin $c (refus attendu)" non0 apt-get "${AO[@]}" update ;;
        packages-modifie) MOTIF='Hash Sum mismatch' code "V4 ($lieu) apt-get update, témoin $c (refus attendu)" non0 apt-get "${AO[@]}" update ;;
        sha1) MOTIF='SHA1' code "V5 ($lieu) apt-get update, témoin sha1 (refus attendu)" non0 apt-get "${AO[@]}" update ;;
        release-gpg-binaire) MOTIF='binary format' code "V8 ($lieu) apt-get update, témoin Release.gpg binaire sans InRelease (refus attendu)" non0 apt-get "${AO[@]}" update ;;
      esac
      if [ "$c" = autre-cle ]; then
        # P5 : le vérificateur employé, lu dans le message de refus (Debug::Acquire::gpgv n'a rien produit au premier passage)
        v=$(printf '%s\n' "$DERNIERE" | grep -o -E 'Sub-process /[^ ]+' | sort | uniq -c | paste -sd';')
        printf '%s\n' "$DERNIERE" | grep -q 'Sub-process /usr/bin/sqv' && echo "OK   P5 ($lieu) : vérificateur nommé par le refus : $v" || echo "ÉCART P5 ($lieu) : sqv non nommé par le refus ; sous-processus cités : ${v:-aucun}"
      fi
      case $c in
        depot|sans-inrelease)
          ( cd "$D" && code "V6 ($lieu) apt-get download, cas $c" 0 apt-get "${AO[@]}" download sample-app )
          echo "     téléchargé ($lieu, $c) : $(ls "$D" | paste -sd' ') ; sha256 $( [ -f "$D/$DEB" ] && sha256sum < "$D/$DEB" | cut -c1-64 || echo absent) ; octets $(stat -c %s "$D/$DEB" 2>/dev/null || echo -)" ;;
        deb-modifie)
          ( cd "$D" && MOTIF='Hash Sum mismatch' code "V7 ($lieu) apt-get download, témoin deb-modifie (refus attendu)" non0 apt-get "${AO[@]}" download sample-app )
          [ -e "$D/$DEB" ] && echo "KO   ($lieu) deb altéré présent dans le dossier de téléchargement" || echo "OK   ($lieu) aucun deb dans le dossier de téléchargement" ;;
        *)
          apt-cache "${AO[@]}" show sample-app >/dev/null 2>&1 && echo "KO   ($lieu) sample-app connu d'apt après le témoin $c" || echo "OK   ($lieu) sample-app inconnu d'apt après le témoin $c" ;;
      esac
    done
    ;;
  *) echo "usage : $0 signer SECRETS T | verifier T B LIEU" >&2; exit 64 ;;
esac
