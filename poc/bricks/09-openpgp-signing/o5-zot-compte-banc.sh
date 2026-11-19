#!/usr/bin/env bash
# Brique 09, banc de l'étape compte_zot d'o5-zot.sh, dans un dossier jetable (BANC) : nominal, relance, dossier absent.
# Usage : poc/bricks/09-openpgp-signing/o5-zot-compte-banc.sh   (journal : resultats/o5-zot-compte-banc.log ; dossier effacé à la main)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
B=$HOME/.cache/supply-chain-poc/09/o5-zot-compte-banc
S=$here/o5-zot.sh
[ ! -e "$B" ] || { echo "KO   $B existe déjà" >&2; exit 1; }
n_ok=0; n_ko=0
verdict() { if eval "$2"; then echo "OK   $1"; n_ok=$((n_ok + 1)); else echo "KO   $1 (condition : $2)"; n_ko=$((n_ko + 1)); fi; }
# shellcheck disable=SC2034
lancer() { BANC=$C "$S" compte_zot > "$C/sortie" 2>&1; RC=$?; J=$C/resultats/o5-zot-compte_zot.log; }
{
echo "banc commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-zot.sh $(sha256sum < "$S" | cut -c1-16)… ; o5-zot-compte-banc.sh $(sha256sum < "$0" | cut -c1-16)…"
set +e
echo "### 1. nominal"
C=$B/nominal; mkdir -p "$C/secrets9"
lancer
M=$C/secrets9/zot-poc-lien.password; H=$C/secrets9/zot-poc-lien.htpasswd
verdict "code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "mot de passe : 48 hexadécimaux, mode 600" 'grep -qxE "[0-9a-f]{48}" "$M" && [ "$(stat -c %a "$M")" = 600 ]'
verdict "ligne htpasswd : motif de stockage.sh, mode 600" 'grep -qxE "poc-lien:\\\$2b\\\$12\\\$[./A-Za-z0-9]{53}" "$H" && [ "$(stat -c %a "$H")" = 600 ]'
verdict "hash vérifié indépendamment (python crypt absent : mkpasswd avec le sel, hors du script)" \
  '[ "poc-lien:$(mkpasswd -m bcrypt -R 12 -S "$(cut -c17-38 "$H")" -s < "$M")" = "$(cat "$H")" ]'
verdict "un autre mot de passe ne donne pas ce hash" \
  '[ "poc-lien:$(printf autre | mkpasswd -m bcrypt -R 12 -S "$(cut -c17-38 "$H")" -s)" != "$(cat "$H")" ]'
verdict "ni mot de passe ni hash dans le journal ni la sortie" '! grep -q -F -f "$M" "$J" "$C/sortie" && ! cut -d: -f2 "$H" | grep -q -F -f - "$J" "$C/sortie"'
verdict "K6 tenu, aucune ligne masquée" 'grep -q "^OK   K6" "$J" && ! grep -q "ligne masquée" "$J"'
cp "$J" "$C/nominal.log"
# shellcheck disable=SC2034
m1=$(sha256sum "$M" "$H")   # lu par verdict, via eval
echo "### 2. relance : fichiers présents"
lancer
verdict "relance : refus, fichiers inchangés" 'grep -q "^KO   mot de passe ou ligne htpasswd de poc-lien déjà présent" "$J" && [ "$(sha256sum "$M" "$H")" = "$m1" ]'
echo "### 3. dossier de secrets absent"
C=$B/absent; mkdir -p "$C"
lancer
verdict "dossier absent : refus, rien créé" 'grep -q "^KO   dossier 09/secrets absent" "$J" && [ ! -e "$C/secrets9" ]'
echo "### journal nominal"
sed 's/^/     | /' "$B/nominal/nominal.log"
echo "bilan : $n_ok OK, $n_ko KO"
echo "banc fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "à effacer après archivage (chemin littéral) : $B"
[ "$n_ko" = 0 ]
} 2>&1 | tee "$here/resultats/o5-zot-compte-banc.log"
