#!/usr/bin/env bash
# Brique 09, banc hors cluster d'o5-openbao.sh : kubectl et bao remplacés par des faux sur l'hôte, jeton factice. Aucun accès au
# cluster ni à OpenBao (KUBECONFIG pointe vers un fichier absent). Le faux bao refuse tout appel sans le jeton factice attendu,
# ce qui contrôle que la fonction racine le transmet ; il compte les écritures.
# Cas : releve et cle_lien nominaux ; cle_lien relancée (clé et fichier présents) ; clé présente sans fichier ; OpenBao scellé ;
# écriture qui modifie aussi une autre clé ; clé créée exportable.
# Usage : poc/bricks/09-openpgp-signing/o5-openbao-banc.sh   (journal : resultats/o5-openbao-banc.log ; dossier du banc effacé à la main)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
B=$HOME/.cache/supply-chain-poc/09/o5-banc-openbao
S=$here/o5-openbao.sh
JETON=zq81-banc-faux-0000

[ ! -e "$B" ] || { echo "KO   $B existe déjà" >&2; exit 1; }
mkdir -p "$B/bin" "$B/secrets" "$B/modele"
printf '%s\n' "$JETON" > "$B/secrets/openbao-root.token"
cat > "$B/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
# faux kubectl : n'accepte que « exec -i -n openbao openbao-0 -- sh -c SCRIPT » et exécute SCRIPT sur l'hôte
[ "$1 $2 $3 $4 $5 $6 $7" = "exec -i -n openbao openbao-0 -- sh" ] && [ "$8" = "-c" ] || { echo "faux kubectl : appel inattendu : $*" >&2; exit 9; }
[ "$KUBECONFIG" = "$HOME/.kube/supply-chain-poc.yaml" ] || { echo "faux kubectl : KUBECONFIG inattendu" >&2; exit 9; }
exec sh -c "$9"
EOF
cat > "$B/bin/bao" <<'EOF'
#!/usr/bin/env bash
E=$BANC_ETAT
[ "${BAO_TOKEN:-}" = "$(cat "$E/jeton-attendu")" ] || { echo "Error: permission denied (jeton absent ou faux)" >&2; exit 2; }
echo "$*" >> "$E/appels"
cle() { # nom type exportable version
  jq -n --arg t "$2" --argjson x "$3" --argjson v "$4" --rawfile p "$E/pub.pem" \
    '{data: {type: $t, exportable: $x, allow_plaintext_backup: false, deletion_allowed: false, latest_version: $v,
             supports_signing: true, keys: {"1": {public_key: $p}}}}' > "$E/cles/$1.json"
}
case "$1 $2" in
  "status -format=json") s=$(cat "$E/scelle"); printf '{"initialized":true,"sealed":%s,"version":"2.7.2-banc"}\n' "$s"; [ "$s" = false ] || exit 2 ;;
  "list -format=json") ls "$E/cles" | sed 's/\.json$//' | jq -R . | jq -s . ;;
  "read -format=json") k=${3#transit/keys/}; [ -f "$E/cles/$k.json" ] && cat "$E/cles/$k.json" || { echo "No value found at $3" >&2; exit 2; } ;;
  "write -f")
    k=${3#transit/keys/}; echo "$k" >> "$E/ecritures"
    case $(cat "$E/mode") in
      normal) cle "$k" ecdsa-p256 false 1 ;;
      exportable) cle "$k" ecdsa-p256 true 1 ;;
      altere) cle "$k" ecdsa-p256 false 1; cle chains ecdsa-p256 false 2 ;;
    esac
    echo "Success! Data written to: $3" ;;
  *) echo "faux bao : appel inattendu : $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$B/bin/kubectl" "$B/bin/bao"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2>/dev/null | openssl pkey -pubout > "$B/modele/pub.pem"

n_ok=0; n_ko=0
verdict() { # libellé condition
  if eval "$2"; then echo "OK   $1"; n_ok=$((n_ok + 1)); else echo "KO   $1 (condition : $2)"; n_ko=$((n_ko + 1)); fi
}
cas() { # nom mode scellé clés_initiales… : nouvel état et nouveau dossier de journaux
  local n=$1 m=$2 s=$3 k; shift 3
  C=$B/cas-$n; mkdir -p "$C/etat/cles"
  cp "$B/modele/pub.pem" "$C/etat/pub.pem"; printf '%s\n' "$JETON" > "$C/etat/jeton-attendu"
  echo normal > "$C/etat/mode"; echo "$s" > "$C/etat/scelle"; : > "$C/etat/ecritures"; : > "$C/etat/appels"
  export BANC_ETAT=$C/etat
  for k in "$@"; do BAO_TOKEN=$JETON "$B/bin/bao" write -f "transit/keys/$k" >/dev/null; done
  echo "$m" > "$C/etat/mode"; : > "$C/etat/ecritures"; : > "$C/etat/appels"
  mkdir -p "$C/resultats"; cp -r "$B/secrets" "$B/bin" "$C/"
}
# shellcheck disable=SC2034
lancer() { # étape : lance o5-openbao.sh dans le cas courant ; code dans RC, journal dans J (lus par verdict, via eval)
  BANC=$C "$S" "$1" > "$C/$1.sortie" 2>&1; RC=$?; J=$C/resultats/o5-openbao-$1.log
}
ecritures() { grep -c . "$C/etat/ecritures" || true; }

{
echo "banc commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-openbao.sh $(sha256sum < "$S" | cut -c1-16)… ; o5-openbao-banc.sh $(sha256sum < "$0" | cut -c1-16)…"
set +e
echo "### 1. nominal : releve puis cle_lien (chains, tsa, scanner présentes)"
cas nominal normal false chains tsa scanner
lancer releve
verdict "releve : code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "releve : lien absente, aucune écriture" 'grep -q "^OK   transit/keys/lien absente" "$J" && [ "$(ecritures)" = 0 ]'
lancer cle_lien
verdict "cle_lien : code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "cle_lien : une seule écriture, sur lien" '[ "$(cat "$C/etat/ecritures")" = lien ]'
verdict "cle_lien : relecture conforme" 'grep -q "^OK   clé lien (type, exportable, sauvegarde en clair, suppression, version, signature) : ecdsa-p256,false,false,false,1,true$" "$J"'
verdict "cle_lien : clé publique exportée = clé du faux bao" 'cmp -s "$C/resultats/lien-cle-publique.pem" "$B/modele/pub.pem"'
verdict "cle_lien : autres clés inchangées" 'grep -q "^OK   seule différence : transit/keys/lien ajoutée" "$J"'
verdict "jeton factice absent des journaux et sorties" '! grep -r -q -F "$JETON" "$C/resultats" "$C"/*.sortie'
verdict "faux bao jamais appelé sans le jeton" '! grep -q "permission denied" "$C"/*.sortie "$C"/resultats/*.log'
cp "$J" "$C/cle_lien-nominal.log"
echo "### 2. cle_lien relancée : clé et fichier déjà présents"
lancer cle_lien
verdict "relance : refus (KO), aucune écriture" 'grep -q "^KO   .*lien-cle-publique.pem existe déjà : rien n.est écrasé" "$J" && [ "$(ecritures)" = 1 ]'
echo "### 3. clé lien présente, fichier absent"
cas presente normal false chains tsa scanner lien
lancer cle_lien
verdict "clé présente : refus, aucune écriture, pas de fichier" 'grep -q "^KO   transit/keys/lien existe déjà : aucune écriture" "$J" && [ "$(ecritures)" = 0 ] && [ ! -e "$C/resultats/lien-cle-publique.pem" ]'
lancer releve
verdict "releve : signale la clé présente" 'grep -q "^KO   transit/keys/lien existe déjà" "$J"'
echo "### 4. OpenBao scellé"
cas scelle normal true chains tsa
lancer cle_lien
verdict "scellé : refus avant toute écriture" 'grep -q "^KO   OpenBao scellé" "$J" && [ "$(ecritures)" = 0 ]'
echo "### 5. écriture qui modifie aussi chains"
cas altere altere false chains tsa scanner
lancer cle_lien
verdict "autre clé modifiée : détectée" 'grep -q "^KO   clés Transit : différence autre que l.ajout de lien" "$J"'
echo "### 6. clé créée exportable"
cas exportable exportable false chains tsa scanner
lancer cle_lien
verdict "clé exportable : détectée" 'grep -q "^KO   clé lien : ecdsa-p256,true,false,false,1,true" "$J"'
echo "### journal nominal de cle_lien (extrait)"
sed 's/^/     | /' "$B/cas-nominal/cle_lien-nominal.log" | head -40
echo "bilan : $n_ok OK, $n_ko KO"
echo "banc fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "à effacer après archivage (chemin littéral) : $B"
[ "$n_ko" = 0 ]
} 2>&1 | tee "$here/resultats/o5-openbao-banc.log"
