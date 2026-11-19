#!/bin/bash
# Brique 09, O2 : manipulation de la clé OpenPGP, exécutée DANS une racine de signature (sous chroot, sans réseau) par o2.sh,
# ou sur l'hôte par o2-banc.sh (gpg de l'hôte, clé jetable). Ne lit ni n'écrit rien hors des chemins passés en argument.
# Gardes : GNUPGHOME doit être un tmpfs (K2) ; aucune sortie de clé sur la sortie standard (K3) ; pas d'écrasement (K4) ;
# réseau absent (K1, seulement lo dans /proc/self/net/dev).
# Usage : o2-interne.sh creer SECRETS | signer CLE SORTIE | verifier PUBLIQUE FICHIER SIGNATURE | jetable SORTIE | reseau
set -euo pipefail
umask 077
export LC_ALL=C

ko() { echo "KO   $*"; exit 1; }
tmpfs_ou_ko() {
  [ -n "${GNUPGHOME:-}" ] || ko "GNUPGHOME non défini"
  t=$(stat -f -c %T "$GNUPGHOME")
  [ "$t" = tmpfs ] || ko "GNUPGHOME $GNUPGHOME sur $t, pas sur tmpfs (K2)"
  echo "OK   GNUPGHOME sur tmpfs ($GNUPGHOME)"
}
reseau_ou_ko() {
  n=$(awk -F: 'NR > 2 {gsub(/ /, "", $1); print $1}' /proc/self/net/dev | paste -sd' ')
  [ "$n" = lo ] || ko "$(wc -w <<<"$n") interfaces réseau visibles, dont autre chose que lo (K1 ; noms non journalisés)"
  echo "OK   réseau absent : seule l'interface lo est visible (K1)"
}
gpgx() { gpg --batch --no-tty --quiet "$@"; }
decrire() { # empreinte, algorithme, taille, expiration, usages de la clé primaire, sans rien d'autre
  # sans strftime : l'awk de Debian minbase est mawk ; les dates passent par date -u
  gpgx --with-colons --list-keys "$1" | awk -F: '$1=="pub"{print $4, $3, $6, ($7 == "" ? 0 : $7), $12} $1=="fpr"{print "fpr", $10; exit}' \
    | while read -r a b c d e; do
        if [ "$a" = fpr ]; then echo "  empreinte : $b"
        else echo "  primaire : algo $a, $b bits, créée $(date -u -d "@$c" +%F), expire $([ "$d" = 0 ] && echo jamais || date -u -d "@$d" +%F), usages $e"; fi
      done
}
parametres() { # fichier de paramètres de génération ; aucun secret (clé sans phrase de passe, D2 et accord)
  printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 4096' 'Key-Usage: sign' \
    "Name-Real: $1" "Name-Comment: $2" "Expire-Date: $3" '%commit' > "$GNUPGHOME/parametres"
}

case "${1:-}" in
  reseau) reseau_ou_ko ;;
  creer)
    S=$2
    reseau_ou_ko; tmpfs_ou_ko
    [ -d "$S" ] || ko "dossier des secrets absent : $S"
    for f in cle-openpgp.asc cle-publique.asc revocation.asc; do [ ! -e "$S/$f" ] || ko "$S/$f existe déjà : rien n'est écrasé (K4)"; done
    echo "gpg : $(gpg --version | head -1)"
    # O2_NOM et O2_EXPIRE : identité et durée d'une clé de banc (jetable) ; par défaut, la clé du PoC
    parametres "${O2_NOM:-PoC supply-chain signature des paquets et des depots}" "${O2_COMMENTAIRE:-cle de PoC, fichier sur l'hote d'administration}" "${O2_EXPIRE:-1y}"
    gpgx --gen-key "$GNUPGHOME/parametres" 2>/dev/null
    F=$(gpgx --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10; exit}')
    [ -n "$F" ] || ko "clé non créée"
    decrire "$F"
    gpgx --armor -o "$S/cle-openpgp.asc" --export-secret-keys "$F"
    gpgx --armor -o "$S/cle-publique.asc" --export "$F"
    [ -f "$GNUPGHOME/openpgp-revocs.d/$F.rev" ] || ko "certificat de révocation absent"
    cp "$GNUPGHOME/openpgp-revocs.d/$F.rev" "$S/revocation.asc"
    for f in cle-openpgp.asc cle-publique.asc revocation.asc; do
      echo "  $f : $(stat -c '%a %s' "$S/$f") (mode, octets), sha256 $(sha256sum < "$S/$f" | cut -c1-64)"
    done
    head -1 "$S/cle-openpgp.asc" | grep -qx -- '-----BEGIN PGP PRIVATE KEY BLOCK-----' && echo "OK   clé privée exportée armurée (K3)" || ko "export de la clé privée non armuré"
    echo "empreinte créée : $F"
    ;;
  signer)
    C=$2; O=$3
    reseau_ou_ko; tmpfs_ou_ko
    echo "gpg : $(gpg --version | head -1)"
    gpgx --import "$C" 2>/dev/null || ko "import de la clé refusé (K5)"
    F=$(gpgx --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10; exit}')
    [ -n "$F" ] || ko "aucune clé secrète après import (K5)"
    decrire "$F"
    printf 'brique 09, O2 : fichier d essai signé hors ligne\n' > "$O/essai.txt"
    gpgx --local-user "$F" --digest-algo SHA512 --detach-sign -o "$O/essai.txt.sig" "$O/essai.txt" || ko "signature refusée"
    echo "OK   essai.txt signé par $F (SHA-512), signature de $(stat -c %s "$O/essai.txt.sig") octets"
    ;;
  verifier)
    P=$2; X=$3; Y=$4
    reseau_ou_ko; tmpfs_ou_ko
    gpgx --dearmor -o "$GNUPGHOME/verif.gpg" "$P"
    if gpgv --homedir "$GNUPGHOME" --keyring "$GNUPGHOME/verif.gpg" --status-fd 1 "$Y" "$X" 2>/dev/null | awk '$2=="VALIDSIG"{print "OK   gpgv : signature valide, " $NF; v=1} END{exit !v}'; then :; else echo "KO   gpgv : signature non vérifiée"; fi
    if command -v sqv >/dev/null; then
      sqv --keyring "$P" "$Y" "$X" > "$GNUPGHOME/sqv.out" 2>&1 && echo "OK   sqv : signature valide, $(tr '\n' ' ' < "$GNUPGHOME/sqv.out")" || echo "KO   sqv : $(tr '\n' ' ' < "$GNUPGHOME/sqv.out" | cut -c1-200)"
    else echo "sqv absent de cette racine"; fi
    ;;
  jetable)
    O=$2
    reseau_ou_ko; tmpfs_ou_ko
    echo "gpg : $(gpg --version | head -1)"
    parametres "Banc 09 PoC cle jetable" "jetable" "2d"
    gpgx --gen-key "$GNUPGHOME/parametres" 2>/dev/null
    F=$(gpgx --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10; exit}')
    decrire "$F"
    gpgx --armor -o "$O/jetable.asc" --export-secret-keys "$F"
    gpgx --armor -o "$O/jetable-publique.asc" --export "$F"
    echo "OK   clé jetable $F exportée dans $O (tmpfs)"
    ;;
  *) echo "usage : $0 creer SECRETS | signer CLE SORTIE | verifier PUBLIQUE FICHIER SIGNATURE | jetable SORTIE | reseau" >&2; exit 64 ;;
esac
