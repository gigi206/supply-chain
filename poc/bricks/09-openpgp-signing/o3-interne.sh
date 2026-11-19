#!/bin/bash
# Brique 09, O3 : signature et vérification du rpm, exécutées DANS une racine (sous chroot, sans réseau) par o3.sh.
#   signer SECRETS T   racine Rocky de signature (gpg 2.3.3, rpm-sign, createrepo_c) ; GNUPGHOME sur tmpfs ; clé importée de
#                      SECRETS (lecture seule) ; rpm de T/entree signé dans T/depot, dépôt createrepo_c et repomd.xml.asc ;
#                      --delsign sur une copie ; trois dépôts témoins ; clé publique exportée dans T.
#   verifier T         amorce Rocky 9.8 neuve (dnf, rpm) : rpmkeys --checksig avant et après import de la clé publique,
#                      témoins, puis dnf avec gpgcheck=1 et repo_gpgcheck=1 sur les dépôts témoins et sur le dépôt signé.
# Aucune sortie de clé privée (K3) ; réseau absent (K1, seulement lo dans /proc/self/net/dev). Ne lit ni n'écrit hors de T,
# SECRETS et GNUPGHOME, sauf la base rpm et le cache de dnf de l'amorce de vérification, jetée ensuite.
set -uo pipefail
export LC_ALL=C
RPM=sample-app-1.0.0-2.el9.x86_64.rpm
QF='SIGPGP=%{SIGPGP:pgpsig} | RSAHEADER=%{RSAHEADER:pgpsig} | SHA256HEADER=%{SHA256HEADER} | PAYLOADDIGEST=%{PAYLOADDIGEST}\n'
ko() { echo "KO   $*"; exit 1; }
reseau_ou_ko() {
  n=$(awk -F: 'NR > 2 {gsub(/ /, "", $1); print $1}' /proc/self/net/dev | paste -sd' ')
  [ "$n" = lo ] || ko "$(wc -w <<<"$n") interfaces réseau visibles, dont autre chose que lo (K1 ; noms non journalisés)"
  echo "OK   réseau absent : seule l'interface lo est visible (K1)"
}
code() { # LIBELLÉ ATTENDU(0|non0) COMMANDE... : lance, journalise la sortie (indentée) et compare le code
  local l=$1 a=$2 rc; shift 2
  "$@" 2>&1 | sed 's/^/     | /'; rc=${PIPESTATUS[0]}
  if { [ "$a" = 0 ] && [ "$rc" = 0 ]; } || { [ "$a" = non0 ] && [ "$rc" != 0 ]; }; then echo "OK   $l : code $rc"
  else echo "KO   $l : code $rc (attendu $a)"; fi
}
gpgx() { gpg --batch --no-tty --quiet "$@"; }

case "${1:-}" in
  signer)
    S=$2 T=$3
    umask 077
    reseau_ou_ko
    [ "$(stat -f -c %T "$GNUPGHOME")" = tmpfs ] || ko "GNUPGHOME pas sur tmpfs (K2)"
    echo "OK   GNUPGHOME sur tmpfs ($GNUPGHOME)"
    echo "outils : $(rpm -q rpm rpm-sign createrepo_c gnupg2 | paste -sd' ')"
    gpgx --import "$S/cle-openpgp.asc" 2>&1 | grep -v -i -E 'secret key|clé secrète' | sed 's/^/     gpg : /'
    fpr=$(gpgx --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10; exit}')
    [ -n "$fpr" ] || ko "aucune clé secrète importée"
    echo "clé importée : $fpr"
    mkdir -p "$T/depot" "$T/delsign" "$T/temoins"
    cp -- "$T/entree/$RPM" "$T/depot/$RPM"
    code "S1 rpmsign --addsign (gpg2 de la racine, SHA-512)" 0 \
      rpmsign --addsign --define "_gpg_name $fpr" --define "_gpg_path $GNUPGHOME" --define "_gpg_digest_algo sha512" "$T/depot/$RPM"
    echo "S2 en-têtes (rpm -qp) :"
    for f in "$T/entree/$RPM" "$T/depot/$RPM"; do echo "     ${f#"$T"/} : $(rpm -qp --nosignature --qf "$QF" "$f" 2>&1)"; done
    cp -- "$T/depot/$RPM" "$T/delsign/$RPM"
    code "S3 rpmsign --delsign sur une copie" 0 rpmsign --delsign "$T/delsign/$RPM"
    echo "     delsign : $(sha256sum < "$T/delsign/$RPM" | cut -c1-64) ; entrée : $(sha256sum < "$T/entree/$RPM" | cut -c1-64)"
    gpgx --armor -o "$T/cle-publique.asc" --export "$fpr" && echo "clé publique exportée : $(wc -c < "$T/cle-publique.asc") octets"
    code "S4 createrepo_c du dépôt signé" 0 createrepo_c --quiet "$T/depot"
    code "S5 repomd.xml.asc (signature détachée armurée, SHA-512)" 0 \
      gpgx --digest-algo sha512 -u "$fpr" --armor --detach-sign -o "$T/depot/repodata/repomd.xml.asc" "$T/depot/repodata/repomd.xml"
    # témoins : autre clé (jetable, même homedir tmpfs), repomd modifié après signature, rpm non signé dans un dépôt signé
    printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 3072' 'Key-Usage: sign' 'Name-Real: Banc 09 O3 autre cle jetable' \
      'Expire-Date: 2d' '%commit' > "$GNUPGHOME/autre"
    gpgx --gen-key "$GNUPGHOME/autre" 2>&1 | sed 's/^/     gpg : /'
    autre=$(gpgx --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10}' | grep -v -x "$fpr" | head -1)
    echo "clé jetable du témoin « autre clé » : ${autre:-absente}"
    for t in autre-cle repomd-modifie rpm-non-signe; do
      mkdir -p "$T/temoins/$t"
      if [ "$t" = rpm-non-signe ]; then cp -- "$T/entree/$RPM" "$T/temoins/$t/$RPM"; else cp -- "$T/depot/$RPM" "$T/temoins/$t/$RPM"; fi
      createrepo_c --quiet "$T/temoins/$t"
      [ "$t" = autre-cle ] && k=$autre || k=$fpr
      gpgx --digest-algo sha512 -u "$k" --armor --detach-sign -o "$T/temoins/$t/repodata/repomd.xml.asc" "$T/temoins/$t/repodata/repomd.xml"
      [ "$t" = repomd-modifie ] && printf '\n' >> "$T/temoins/$t/repodata/repomd.xml"
      echo "     témoin $t : $(ls "$T/temoins/$t/repodata" | wc -l) fichiers de métadonnées, signé par ${k:0:16}…"
    done
    gpgconf --homedir "$GNUPGHOME" --kill all 2>/dev/null
    ;;
  verifier)
    T=$2
    reseau_ou_ko
    echo "outils : $(rpm -q rpm dnf gnupg2 | paste -sd' ') ; clés dans la base rpm : $(rpm -q gpg-pubkey 2>/dev/null | paste -sd' ')"
    code "V1 rpmkeys --checksig du rpm signé, clé du PoC absente (refus attendu : NOKEY)" non0 rpmkeys --checksig -v "$T/depot/$RPM"
    code "V2 import de la clé publique dans la base rpm" 0 rpmkeys --import "$T/cle-publique.asc"
    echo "     $(rpm -q gpg-pubkey --qf '%{NAME}-%{VERSION}-%{RELEASE} %{SUMMARY}\n' | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g' | paste -sd';')"
    code "V3 rpmkeys --checksig du rpm signé" 0 rpmkeys --checksig -v "$T/depot/$RPM"
    code "V4 rpm altéré d'un octet (refus attendu)" non0 rpmkeys --checksig -v "$T/temoins/altere.rpm"
    echo "### V5 rpm d'origine non signé (code relevé, pas de refus prédit par rpmkeys)"
    rpmkeys --checksig -v "$T/entree/$RPM" 2>&1 | sed 's/^/     | /'; echo "     code ${PIPESTATUS[0]}"
    for t in autre-cle repomd-modifie rpm-non-signe; do
      code "V6 dnf, témoin $t (refus attendu)" non0 dnf-3 -y --setopt=reposdir="$T/repos/$t" --setopt=install_weak_deps=False install sample-app
      rpm -q sample-app >/dev/null 2>&1 && echo "KO   sample-app installé après le témoin $t" || echo "OK   sample-app non installé après le témoin $t"
    done
    code "V7 dnf, dépôt signé (gpgcheck=1, repo_gpgcheck=1)" 0 dnf-3 -y --setopt=reposdir="$T/repos/depot" --setopt=install_weak_deps=False install sample-app
    echo "     installé : $(rpm -q sample-app --qf '%{NAME}-%{VERSION}-%{RELEASE} ; RSAHEADER=%{RSAHEADER:pgpsig}\n' 2>&1)"
    ;;
  *) echo "usage : $0 signer SECRETS T | verifier T" >&2; exit 64 ;;
esac
