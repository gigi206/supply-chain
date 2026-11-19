#!/usr/bin/env bash
# Brique 09, O2 : banc à sec de o2-interne.sh sur l'hôte (gpg 2.4.8 d'Ubuntu, clé JETABLE), sans réseau, sans racine ni clé du PoC.
# Ne mesure ni le gpg 2.4.7 de Debian ni le 2.3.3 de Rocky (K5 et K5b restent des prédictions d'essai) ; mesure les gardes
# K1 (réseau), K2 (tmpfs), K3 (rien dans le journal), K4 (pas d'écrasement), l'export armuré, la signature et la vérification.
# Dossier fixe ~/.cache/supply-chain-poc/09/o2-banc (refusé s'il existe), à effacer après archivage. Journal : resultats/o2-banc.log.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
B=$HOME/.cache/supply-chain-poc/09/o2-banc
I=$here/o2-interne.sh
[ ! -e "$B" ] || { echo "KO   $B existe déjà" >&2; exit 1; }
mkdir -m 700 "$B"
mkdir -m 700 "$B/g" "$B/x" "$B/disque" "$B/secrets-banc" "$B/secrets-2"
cd "$B"

banc() {
  echo "banc O2 commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; gpg de l'hôte : $(gpg --version | head -1)"
  echo "### BC5a (K1, témoin) : garde réseau lancée sur l'hôte, avec réseau : refus attendu"
  bash "$I" reseau; echo "  code $?"
  unshare --map-auto --map-root-user -n -m -p --fork bash -s -- "$I" "$B" <<'NS'
set -u
I=$1 B=$2
mount -t proc proc /proc
mount -t tmpfs -o size=16m,mode=700 tmpfs "$B/x"
t() { # LIBELLÉ HOMEDIR(tmpfs|disque) commande… : appel avec un homedir neuf, agent arrêté après
  local l=$1 h=$2; shift 2
  echo "### $l"
  if [ "$h" = tmpfs ]; then mount -t tmpfs -o size=16m,mode=700 tmpfs "$B/g"; G=$B/g; else G=$B/disque; fi
  GNUPGHOME=$G bash "$I" "$@"; local rc=$?
  gpgconf --homedir "$G" --kill all 2>/dev/null
  [ "$h" = tmpfs ] && umount -l "$B/g"
  echo "  code $rc"
}
t "BC5b (K1) : garde réseau sans réseau" tmpfs reseau
t "BC1 : création, exports armurés 0600" tmpfs creer "$B/secrets-banc"
a=$(cat "$B"/secrets-banc/*.asc | sha256sum | cut -c1-64)
t "BC2 (K4) : seconde création dans le même dossier, refus attendu" tmpfs creer "$B/secrets-banc"
b=$(cat "$B"/secrets-banc/*.asc | sha256sum | cut -c1-64)
[ "$a" = "$b" ] && echo "OK   BC2 : fichiers inchangés après le refus" || echo "KO   BC2 : fichiers modifiés"
t "BC3 (K2) : homedir sur disque, refus attendu" disque creer "$B/secrets-2"
echo "  fichiers écrits dans secrets-2 : $(find "$B/secrets-2" -type f | wc -l)"
mkdir -p "$B/x/pdc" "$B/x/jet"
t "BC4 : import de la clé et signature" tmpfs signer "$B/secrets-banc/cle-openpgp.asc" "$B/x/pdc"
t "BC4 : vérification par gpgv (et sqv s'il existe)" tmpfs verifier "$B/secrets-banc/cle-publique.asc" "$B/x/pdc/essai.txt" "$B/x/pdc/essai.txt.sig"
t "BC6 : clé jetable" tmpfs jetable "$B/x/jet"
t "BC6 : import de la clé jetable et signature" tmpfs signer "$B/x/jet/jetable.asc" "$B/x/jet"
t "BC8 : signature du PoC vérifiée avec la clé jetable, refus attendu" tmpfs verifier "$B/x/jet/jetable-publique.asc" "$B/x/pdc/essai.txt" "$B/x/pdc/essai.txt.sig"
echo "  modes : secrets-banc $(stat -c %a "$B/secrets-banc") ; $(for f in "$B"/secrets-banc/*; do printf '%s %s ; ' "$(basename "$f")" "$(stat -c %a "$f")"; done)"
NS
  echo "banc O2 fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

banc 2>&1 | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g' | tee "$R/o2-banc.log"
n=$(grep -c 'BEGIN PGP' "$R/o2-banc.log" || true)
m=$(grep -c -F -f <(grep -v -e '^-----' -e '^$' "$B/secrets-banc/cle-openpgp.asc") "$R/o2-banc.log" || true)
{ [ "$n" = 0 ] && echo "OK   BC7 (K3) : aucun « BEGIN PGP » dans le journal" || echo "KO   BC7 (K3) : $n ligne(s) « BEGIN PGP »"
  [ "$m" = 0 ] && echo "OK   BC7 (K3) : aucune ligne de la clé privée jetable dans le journal" || echo "KO   BC7 (K3) : $m ligne(s) de la clé dans le journal"; } | tee -a "$R/o2-banc.log"
