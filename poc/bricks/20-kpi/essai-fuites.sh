#!/usr/bin/env bash
# Brique 20 : fuites.sh de la 08 cherche le mot de passe de kpi-journal et les secrets des 07a, 09 et 10. Banc sec : HOME jetable, faux secrets, faux ssh.sh, copie de fuites.sh ; aucun
# vrai secret lu, aucun réseau (resultats/e8-predictions.md, puis e10-predictions.md). Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/20-kpi/essai-fuites.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e10-essai-fuites${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
T=$HOME/.cache/supply-chain-poc/20/essai-fuites   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/essai-fuites ] || find ~/.cache/supply-chain-poc/20/essai-fuites -delete
trap 'find ~/.cache/supply-chain-poc/20/essai-fuites -delete' EXIT
AVANT=40dccc25   # dernier commit où fuites.sh ne lit que 08/secrets
AVANT2=000edd4c   # dernier commit où fuites.sh ne lit ni 07a, ni 09, ni 10
NEUFS="07a-zot-poc-vex.password 07a-openbao-proprietaire.password 09-zot-poc-lien.password 09-openbao-lien.secret 09-cle-openpgp.asc 10-zot-poc-replay.password"
chemin() { printf '%s' "$H/.cache/supply-chain-poc/${1%%-*}/secrets/${1#*-}"; }   # $1 : étiquette
N=0 KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
H=$T/h; S8=$H/.cache/supply-chain-poc/08/secrets; F=$H/.cache/supply-chain-poc/20/secrets/grafana-kpi-journal.password
neuf() { # dossier neuf ; $1 : source de fuites.sh (arbre ou commit)
  [ ! -e "$T/h" ] || find ~/.cache/supply-chain-poc/20/essai-fuites/h -delete
  mkdir -p "$S8" "${F%/*}" "$T/b/resultats" "$H/vm"
  cp "$here/../08-trust-plane/distro.sh" "$T/b/"
  if [ "$1" != arbre ]; then git -C "$here" show "$1:poc/bricks/08-trust-plane/fuites.sh" > "$T/b/fuites.sh"; else cp "$here/../08-trust-plane/fuites.sh" "$T/b/"; fi
  printf '%s\n' '#!/bin/sh' 'd=$HOME/vm' 'case $2 in logger*) printf "%s\n" "${2##* }" >> "$d/$1" ;; *) echo ligne ordinaire; cat "$d/$1" ;; esac' > "$T/b/ssh.sh"
  chmod +x "$T/b/ssh.sh" "$T/b/fuites.sh"
  P8=$(openssl rand -hex 24) P20=$(openssl rand -hex 24)   # faux secrets
  printf '%s' "$P8" > "$S8/faux-08"; printf '%s' "$P20" > "$F"
  for e in $NEUFS; do
    mkdir -p "$(dirname "$(chemin "$e")")"; printf '%s' "$(openssl rand -hex 24)" > "$(chemin "$e")"
  done
  C9=$(openssl rand -hex 32)   # fausse clé armurée : en-tête précédé d'une espace, deux lignes de corps, ligne de contrôle
  printf ' -----BEGIN PGP PRIVATE KEY BLOCK-----\n\n%s\n%s\n=ab1Z\n-----END PGP PRIVATE KEY BLOCK-----\n' "$C9" "$(openssl rand -hex 32)" > "$(chemin 09-cle-openpgp.asc)"
}
lancer() { (HOME=$H DISTRO=rke2 CONFIANCE_DIR= bash "$T/b/fuites.sh" banc 2>&1; echo "code $?") | cat > "$T/sortie"; sed 's/^/  /' "$T/sortie"; }
code() { grep '^code' "$T/sortie"; }
compte() { awk -v vm="$1" -v s="$2" '/^## /{v = $2} v == vm && $2 == s {print $1}' "$T/sortie"; }
{
  echo "# essai-fuites.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), fuites $(sha256sum < "$here/../08-trust-plane/fuites.sh" | cut -c1-16)"
  K=grafana-kpi-journal.password
  echo "## 1. aucune fuite"
  neuf arbre; lancer; attendu "code" "$(code)" "code 0"
  attendu "cherché sur les trois VM" "$(grep -c "^0    $K$" "$T/sortie") $(grep -c '^0    faux-08$' "$T/sortie")" "3 3"
  attendu "ligne « absent »" "$(grep -c '^absent' "$T/sortie")" 0
  echo "## 2. fuite du mot de passe de kpi-journal sur sc-stockage"
  neuf arbre; echo "x $P20 y" > "$H/vm/sc-stockage"; lancer; attendu "code" "$(code)" "code 1"
  attendu "compte sc-stockage, sc-build" "$(compte sc-stockage $K) $(compte sc-build $K)" "1 0"
  attendu "valeur absente de la sortie" "$(grep -c -F -e "$P20" -e "$P8" "$T/sortie")" 0
  echo "## 3. témoin : même fuite, fuites.sh d'avant ($AVANT)"
  neuf "$AVANT"; echo "x $P20 y" > "$H/vm/sc-stockage"; lancer; attendu "code (le défaut existait)" "$(code)" "code 0"
  echo "## 4. fichier absent, puis vide ; non-régression de 08/secrets"
  neuf arbre; find "$H/.cache/supply-chain-poc/20/secrets/grafana-kpi-journal.password" -delete; lancer
  attendu "absent" "$(code) $(grep -c '^absent ou vide, non cherché' "$T/sortie") $(grep -c '^0    faux-08$' "$T/sortie")" "code 0 1 3"
  neuf arbre; : > "$F"; lancer; attendu "vide" "$(code) $(grep -c '^absent ou vide, non cherché' "$T/sortie") $(grep -c "$K$" "$T/sortie")" "code 0 1 1"
  neuf arbre; echo "$P8" > "$H/vm/sc-build"; lancer; attendu "fuite d'un secret de la 08" "$(code) $(compte sc-build faux-08) $(compte sc-build $K)" "code 1 1 0"
  echo "## 5. secrets des 07a, 09 et 10 : cherchés, fuite de chacun sur sc-confiance"
  neuf arbre; lancer; n=0; for e in $NEUFS; do n=$((n + $(grep -c "^0    $e$" "$T/sortie"))); done
  attendu "cherchés sur les trois VM, code" "$n $(code)" "18 code 0"
  for e in $NEUFS; do
    neuf arbre; v=$([ "$e" = 09-cle-openpgp.asc ] && printf '%s' "$C9" || cat "$(chemin "$e")"); echo "x $v y" > "$H/vm/sc-confiance"; lancer
    attendu "fuite de $e : code, sc-confiance, sc-build, autres étiquettes, valeur affichée" "$(code) $(compte sc-confiance "$e") $(compte sc-build "$e") $(awk -v e="$e" '$1 == 1 && $2 != e' "$T/sortie" | wc -l) $(grep -c -F -e "$v" "$T/sortie")" "code 1 1 0 0 0"
  done
  echo "## 6. témoin : fuite du secret de la 10, fuites.sh d'avant ($AVANT2)"
  neuf "$AVANT2"; cat "$(chemin 10-zot-poc-replay.password)" > "$H/vm/sc-confiance"; lancer; attendu "code (le défaut existait)" "$(code)" "code 0"
  echo "## 7. clé armurée : en-tête, pied et ligne de contrôle dans un journal, sans corps"
  neuf arbre; printf '%s\n' ' -----BEGIN PGP PRIVATE KEY BLOCK-----' '-----END PGP PRIVATE KEY BLOCK-----' 'a =ab1Z b' > "$H/vm/sc-build"; lancer
  attendu "aucun faux positif" "$(code) $(compte sc-build 09-cle-openpgp.asc)" "code 0 0"
  echo "## 8. fichiers absents, vides, trop courts"
  neuf arbre; for e in $NEUFS; do find "$(chemin "$e")" -delete; done; lancer
  attendu "absents" "$(code) $(grep -c '^absent ou vide, non cherché' "$T/sortie") $(grep -cE '^[0-9]+ +(07a|09|10)-' "$T/sortie")" "code 0 6 0"
  neuf arbre; for e in $NEUFS; do : > "$(chemin "$e")"; done; lancer
  attendu "vides" "$(code) $(grep -c '^absent ou vide, non cherché' "$T/sortie") $(grep -cE '^[0-9]+ +(07a|09|10)-' "$T/sortie")" "code 0 6 0"
  neuf arbre; echo court > "$(chemin 07a-openbao-proprietaire.password)"; echo "un mot court ici" > "$H/vm/sc-build"; lancer
  attendu "trop court" "$(code) $(grep -c '^aucune ligne de 16 caractères, non cherché' "$T/sortie") $(grep -c 'openbao-proprietaire.password$' "$T/sortie")" "code 0 1 1"
  echo "## 9. répertoire de motifs effacé"
  attendu "travail/fuites" "$([ -e "$H/.cache/supply-chain-poc/08/travail/fuites" ] && echo présent || echo absent)" absent
  echo "## bilan : $N cas, $KO écart(s), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$KO" = 0 ]
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$LOG"
exit "${PIPESTATUS[0]}"
