#!/bin/bash
# Brique 09, O4 : dépôt apt signé et vérification par apt, exécutés DANS une racine (sous chroot, sans réseau) par o4.sh.
#   signer SECRETS T   racine Debian 13 de signature (gpg 2.4.7, apt-ftparchive 3.0.3) ; GNUPGHOME sur tmpfs ; clé importée de
#                      SECRETS (lecture seule) ; deb de T/depot/pool laissé tel quel (D1 a) ; Packages, Packages.gz, Release,
#                      Release.gpg et InRelease (SHA-512) ; clé publique exportée dans T ; témoins sous T/temoins.
#   verifier T         amorce Debian 13 neuve : apt-get update avec Signed-By sur chaque dépôt (un dossier de sources, de listes
#                      et de cache par cas), méthode de vérification relevée (Debug::Acquire::gpgv), apt-get download du deb.
#   methode T A        racine Debian (sqv ET gpgv présents) : apt-get update du seul dépôt signé, listes et cache dans A (jetable),
#                      pour relever le vérificateur choisi par apt quand il a le choix (prédiction 5 du README).
# Aucune sortie de clé privée (K3) ; réseau absent (K1, seulement lo dans /proc/self/net/dev). Ne lit ni n'écrit hors de T,
# SECRETS et GNUPGHOME, sauf les listes, le cache et le dossier de téléchargement d'apt dans l'amorce, jetée ensuite.
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
MOTIF_SIG='gpg|signature|signed|pubkey|missing key|sqv'
MOTIF_EMP='hash|mismatch|unexpected size|size'
code() { # LIBELLÉ ATTENDU(0|non0) COMMANDE... : lance, journalise la sortie (indentée), juge le code et, pour un refus, le motif.
  # non0 : refus attendu, compté OK seulement si la sortie porte le motif du cas (variable MOTIF, passée par l'appelant ;
  # MOTIF_SIG ou MOTIF_EMP) ; toutes les lignes qui le portent sont citées.
  local l=$1 a=$2 rc out m; shift 2
  out=$("$@" 2>&1); rc=$?; DERNIERE=$out
  # en-têtes publics de message signé ou de signature remplacés (la garde K3 d'o4.sh vide tout journal portant un bloc OpenPGP ;
  # un en-tête de clé privée n'est pas remplacé et reste attrapé par K3)
  printf '%s\n' "$out" | sed -E 's/-----(BEGIN|END) PGP (SIGNED MESSAGE|SIGNATURE)-----/[en-tête public \1 \2 retiré]/; s/^/     | /'
  m=$(printf '%s\n' "$out" | grep -i -E "${MOTIF:-$MOTIF_SIG}" | sed -E 's/-----(BEGIN|END) PGP (SIGNED MESSAGE|SIGNATURE)-----/[en-tête public retiré]/' | paste -sd'¦')
  case $a in
    0) [ "$rc" = 0 ] && echo "OK   $l : code $rc" || echo "KO   $l : code $rc (attendu 0)" ;;
    non0) if [ "$rc" != 0 ] && [ -n "$m" ]; then echo "OK   $l : code $rc, motif : $m"
          elif [ "$rc" != 0 ]; then echo "KO   $l : code $rc, refus sans le motif attendu (${MOTIF:-$MOTIF_SIG})"
          else echo "KO   $l : code 0 (refus attendu)"; fi ;;
  esac
}
gpgx() { gpg --batch --no-tty --quiet "$@"; }
OPTS=(-o APT::FTPArchive::Release::Origin=poc -o APT::FTPArchive::Release::Label=poc -o APT::FTPArchive::Release::Suite=poc
      -o APT::FTPArchive::Release::Codename=poc -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main)
signer_release() { # CLÉ DOSSIER [ALGO] : Release.gpg (détachée, binaire) et InRelease (en clair), avec ALGO (SHA512 par défaut)
  gpgx --local-user "$1" --digest-algo "${3:-SHA512}" --detach-sign -o "$2/dists/poc/Release.gpg" "$2/dists/poc/Release" &&
  gpgx --local-user "$1" --digest-algo "${3:-SHA512}" --clearsign -o "$2/dists/poc/InRelease" "$2/dists/poc/Release"
}
paquets_sig() { # FICHIER : paquet de signature (algorithme de clé, identifiant), version, algorithme de condensat
  gpgx --list-packets "$1" 2>/dev/null | grep -E 'signature packet|version|digest algo' | tr -s ' \t' ' ' | paste -sd' '
}
sig_ok() { # LIBELLÉ DOSSIER CONDENSAT(10|2) CLÉ : Release.gpg et InRelease présents, v4, RSA, condensat et clé attendus
  local l=$1 d=$2 n=$3 k=${4:(-16)} f p e=0
  for f in Release.gpg InRelease; do
    [ -f "$d/dists/poc/$f" ] || { echo "KO   $l : $f absent"; e=1; continue; }
    p=$(paquets_sig "$d/dists/poc/$f")
    echo "     $f : $p"
    if printf '%s' "$p" | grep -q -i "algo 1, keyid $k" && printf '%s' "$p" | grep -q 'version 4,' && printf '%s' "$p" | grep -q "digest algo $n,"; then :
    else echo "KO   $l : $f n'est pas une signature v4 RSA de ${k} avec le condensat $n"; e=1; fi
  done
  [ "$e" = 0 ] && echo "OK   $l : Release.gpg et InRelease, v4, RSA, clé ${k}, condensat $n"
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
    # relevé R1 (non prédit au-delà du README) : apt-ftparchive 3.0.3 et SOURCE_DATE_EPOCH, deux sorties hors du dépôt
    for i in 1 2; do ( cd "$T/depot" && SOURCE_DATE_EPOCH=1763337600 apt-ftparchive "${OPTS[@]}" release dists/poc > "$T/Release.sde$i" ); done
    echo "R1 Date avec SOURCE_DATE_EPOCH=1763337600 : « $(grep '^Date:' "$T/Release.sde1" | cut -c7-) » ; deux sorties identiques : $(cmp -s "$T/Release.sde1" "$T/Release.sde2" && echo oui || echo non)"
    code "A3 signature de Release (SHA-512, clé du dépôt)" 0 signer_release "$fpr" "$T/depot"
    sig_ok "A3 dépôt" "$T/depot" 10 "$fpr"
    # témoins : autre clé (jetable, même homedir tmpfs), Release modifié après signature, Packages modifié, deb modifié,
    # signature SHA-1 (clé du dépôt), sans InRelease (cas accepté attendu)
    printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 3072' 'Key-Usage: sign' 'Name-Real: Banc 09 O4 autre cle jetable' \
      'Expire-Date: 2d' '%commit' > "$GNUPGHOME/autre"
    gpgx --gen-key "$GNUPGHOME/autre" 2>&1 | sed 's/^/     gpg : /'
    autre=$(gpgx --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10}' | grep -v -x "$fpr" | head -1)
    [ -n "$autre" ] && echo "clé jetable du témoin « autre clé » : $autre" || echo "KO   témoin autre-cle : clé jetable absente"
    W=$T/temoins
    copie "$W/autre-cle" sans; signer_release "$autre" "$W/autre-cle"; sig_ok "construction du témoin autre-cle" "$W/autre-cle" 10 "${autre:-0000000000000000}"
    copie "$W/release-modifie" avec; sed -i 's/^Label: poc$/Label: pod/' "$W/release-modifie/dists/poc/Release" "$W/release-modifie/dists/poc/InRelease"
    copie "$W/packages-modifie" avec
    sed -i '/^Package: sample-app$/a X-Ajout: oui' "$W/packages-modifie/dists/poc/main/binary-amd64/Packages"
    gzip -9 -n -c "$W/packages-modifie/dists/poc/main/binary-amd64/Packages" > "$W/packages-modifie/dists/poc/main/binary-amd64/Packages.gz"
    copie "$W/deb-modifie" avec; printf 'x' >> "$W/deb-modifie/$POOL/$DEB"
    copie "$W/sha1" sans; signer_release "$fpr" "$W/sha1" SHA1; sig_ok "construction du témoin sha1" "$W/sha1" 2 "$fpr"
    copie "$W/sans-inrelease" sans-inrelease
    for t in autre-cle release-modifie packages-modifie deb-modifie sha1 sans-inrelease; do
      echo "     témoin $t : $(ls "$W/$t/dists/poc" | paste -sd' ') ; deb $(sha256sum < "$W/$t/$POOL/$DEB" | cut -c1-16)…"
    done
    gpgconf --homedir "$GNUPGHOME" --kill all 2>/dev/null
    ;;
  verifier|methode)
    # verifier T : amorce Debian 13 neuve, tous les cas. methode T A : racine Debian (sqv ET gpgv présents), cas depot seul,
    # listes et cache dans A (dossier jetable lié en écriture), pour relever le choix d'apt quand les deux vérificateurs existent.
    m=$1 T=$2 A=${3:-}
    reseau_ou_ko
    echo "outils : $(dpkg-query -W -f='${Package} ${Version}\n' apt sqv gpgv gnupg 2>&1 | paste -sd';')"
    for b in /usr/bin/sqv /usr/bin/gpgv; do [ -x "$b" ] && echo "     $b présent" || echo "     $b absent"; done
    echo "     APT::Key::GPGVCommand : « $(apt-config dump APT::Key::GPGVCommand 2>&1 | paste -sd' ') »"
    [ "$m" = methode ] && cas=depot || cas="depot sans-inrelease autre-cle release-modifie packages-modifie deb-modifie sha1 sans-signed-by"
    for c in $cas; do
      if [ "$m" = methode ]; then L=$A/listes C=$A/cache; else L=/var/lib/apt/o4/$c/listes C=/var/cache/apt/o4/$c; fi
      mkdir -p "$L/partial" "$C/archives/partial"; [ "$m" = methode ] || mkdir -p "/root/o4/$c"
      AO=(-o Dir::Etc::SourceList=/dev/null -o "Dir::Etc::SourceParts=/o2/t/sources/$c" -o "Dir::State::Lists=$L"
          -o "Dir::Cache=$C" -o Acquire::Languages=none)
      case $c in
        depot)
          [ "$m" = methode ] && n="P5b apt-get update dans la racine Debian (sqv et gpgv présents)" || n="V1 apt-get update, dépôt signé (Signed-By)"
          code "$n, journal de la méthode" 0 apt-get "${AO[@]}" -o Debug::Acquire::gpgv=true update
          echo "     méthode (même passage) : $(printf '%s\n' "$DERNIERE" | grep -c 'Preparing to exec') ligne(s) « Preparing to exec » ; binaires cités : $(printf '%s\n' "$DERNIERE" | grep 'Preparing to exec' | grep -o -E '/usr/bin/(sqv|gpgv)' | sort | uniq -c | paste -sd';')"
          printf '%s\n' "$DERNIERE" | grep 'Preparing to exec' | sed 's/^/     exec : /'
          ns=$(printf '%s\n' "$DERNIERE" | grep 'Preparing to exec' | grep -c '/usr/bin/sqv'); ng=$(printf '%s\n' "$DERNIERE" | grep 'Preparing to exec' | grep -c '/usr/bin/gpgv')
          # prédiction, pas défaut de la chaîne : un écart est marqué ÉCART (pas KO) et lu dans la note
          [ "$ns" -gt 0 ] && [ "$ng" = 0 ] && echo "OK   P5 ($m) : sqv cité $ns fois, gpgv jamais" || echo "ÉCART P5 ($m) : sqv cité $ns fois, gpgv $ng fois"
          [ "$m" = methode ] && continue
          ;;
        sans-inrelease) code "V2 apt-get update, dépôt sans InRelease (Release + Release.gpg)" 0 apt-get "${AO[@]}" update ;;
        deb-modifie) code "V3 apt-get update, témoin deb-modifie (index intacts, accepté)" 0 apt-get "${AO[@]}" update ;;
        sha1) MOTIF=$MOTIF_SIG code "V5 apt-get update, témoin sha1 (refus attendu, confiance faible)" non0 apt-get "${AO[@]}" update
              echo "     mention de SHA-1 dans la sortie : $(printf '%s\n' "$DERNIERE" | grep -i -c -E 'sha-?1') ligne(s)" ;;
        packages-modifie) MOTIF=$MOTIF_EMP code "V4 apt-get update, témoin $c (refus attendu, motif d'empreinte)" non0 apt-get "${AO[@]}" update ;;
        *) MOTIF=$MOTIF_SIG code "V4 apt-get update, témoin $c (refus attendu, motif de signature)" non0 apt-get "${AO[@]}" update ;;
      esac
      case $c in
        depot|sans-inrelease)
          ( cd "/root/o4/$c" && code "V6 apt-get download, cas $c" 0 apt-get "${AO[@]}" download sample-app )
          f=$(ls "/root/o4/$c" 2>/dev/null | paste -sd' ')
          echo "     téléchargé ($c) : $f ; sha256 $( [ -f "/root/o4/$c/$DEB" ] && sha256sum < "/root/o4/$c/$DEB" | cut -c1-64 || echo absent) ; octets $(stat -c %s "/root/o4/$c/$DEB" 2>/dev/null || echo -)" ;;
        deb-modifie)
          ( cd "/root/o4/$c" && MOTIF=$MOTIF_EMP code "V7 apt-get download, témoin deb-modifie (refus attendu, motif d'empreinte)" non0 apt-get "${AO[@]}" download sample-app )
          [ -e "/root/o4/$c/$DEB" ] && echo "KO   deb altéré présent dans le dossier de téléchargement" || echo "OK   aucun deb dans le dossier de téléchargement" ;;
        *)
          apt-cache "${AO[@]}" show sample-app >/dev/null 2>&1 && echo "KO   sample-app connu d'apt après le témoin $c" || echo "OK   sample-app inconnu d'apt après le témoin $c" ;;
      esac
    done
    ;;
  *) echo "usage : $0 signer SECRETS T | verifier T | methode T A" >&2; exit 64 ;;
esac
