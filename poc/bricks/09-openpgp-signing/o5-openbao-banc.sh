#!/usr/bin/env bash
# Brique 09, banc hors cluster d'o5-openbao.sh : kubectl et bao remplacés par des faux sur l'hôte, jetons factices. Aucun accès
# au cluster ni à OpenBao : le faux kubectl n'exécute que « exec … openbao-0 -- sh -c SCRIPT », sur l'hôte. Le faux bao refuse
# tout appel sans un jeton connu (root factice, ou secret lien qu'il a lui-même émis), applique au secret lien les chemins de
# politique/lien-signature.hcl (ou plus large, en témoin), compte les écritures et signe avec une clé ECDSA P-256 jetable du banc.
# Cas releve et cle_lien (premier accord) : nominaux ; relance ; clé présente ; scellé ; autre clé modifiée ; clé exportable.
# Cas acces_lien (deuxième accord) : nominal ; relance (secret présent) ; politique présente ; création refusée ; politique
# trop large ; signature d'une autre clé ; fuite de la valeur du secret lien dans une réponse.
# Usage : poc/bricks/09-openpgp-signing/o5-openbao-banc.sh   (journal : resultats/o5-openbao-banc-jeton.log ; dossier du banc
# effacé à la main après archivage)
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
mode=$(cat "$E/mode")
refuse() { echo "Error: Code: 403. Errors:"; echo "* permission denied${1:+ $1}"; exit 2; } >&2
if [ "${BAO_TOKEN:-}" = "$(cat "$E/jeton-attendu")" ]; then qui=root
elif [ -s "$E/lien.secret" ] && [ "${BAO_TOKEN:-}" = "$(cat "$E/lien.secret")" ]; then qui=lien
else echo "Error: permission denied (jeton absent ou faux)" >&2; exit 2; fi
echo "$qui $*" >> "$E/appels"
permis() { # chemin : droits du secret lien (politique lien-signature ; plus large en mode trop_large)
  [ "$qui" = root ] && return 0
  case "$1" in
    transit/keys/lien|transit/sign/lien|transit/sign/lien/*) return 0 ;;
    transit/sign/chains/*) [ "$mode" = trop_large ] ;;
    *) return 1 ;;
  esac
}
cle() { # nom type exportable version
  jq -n --arg t "$2" --argjson x "$3" --argjson v "$4" --rawfile p "$E/pub.pem" \
    '{data: {type: $t, exportable: $x, allow_plaintext_backup: false, deletion_allowed: false, latest_version: $v,
             supports_signing: true, keys: {"1": {public_key: $p}}}}' > "$E/cles/$1.json"
}
case "$1 $2" in
  "status -format=json") s=$(cat "$E/scelle"); printf '{"initialized":true,"sealed":%s,"version":"2.7.2-banc"}\n' "$s"; [ "$s" = false ] || exit 2 ;;
  "list -format=json") permis transit/keys || refuse; ls "$E/cles" | sed 's/\.json$//' | jq -R . | jq -s . ;;
  "read -format=json"|"read transit/keys/lien"|"read transit/keys/chains"|"read transit/export/signing-key/lien"|"read kv/horodatage/zot")
    p=${!#}; permis "$p" || refuse
    k=${p#transit/keys/}; [ -f "$E/cles/$k.json" ] && cat "$E/cles/$k.json" || { echo "No value found at $p" >&2; exit 2; } ;;
  "write -f")
    k=${3#transit/keys/}; echo "$k" >> "$E/ecritures"
    case $mode in
      exportable) cle "$k" ecdsa-p256 true 1 ;;
      altere) cle "$k" ecdsa-p256 false 1; cle chains ecdsa-p256 false 2 ;;
      *) cle "$k" ecdsa-p256 false 1 ;;
    esac
    echo "Success! Data written to: $3" ;;
  "write -field=signature"|"write transit/sign/chains/sha2-256"|"write transit/sign/tsa/sha2-256"|"write transit/sign/scanner/sha2-256")
    p=$(printf '%s\n' "$@" | grep '^transit/sign/'); permis "$p" || refuse
    i=$(printf '%s\n' "$@" | sed -n 's/^input=//p')
    k=$E/priv.pem; [ "$mode" = autre_signature ] && k=$E/autre.pem
    printf 'vault:v1:%s\n' "$(printf '%s' "$i" | base64 -d | openssl dgst -sha256 -sign "$k" | base64 -w0)" ;;
  "policy list") [ "$mode" = fuite ] && [ "$qui" = lien ] && refuse "$(cat "$E/lien.secret")"; permis sys/policy || refuse; ls "$E/pol" | jq -R . | jq -s . ;;
  "policy write") permis sys/policy || refuse; echo "pol $3" >> "$E/ecritures"; cat > "$E/pol/$3"; echo "Success! Uploaded policy: $3" ;;
  "policy read") permis sys/policy || refuse; cat "$E/pol/$3" ;;
  "token create")
    permis auth/token/create || refuse
    [ "$mode" = creation_refusee ] && { echo "Error: Code: 400" >&2; exit 2; }
    echo "secret" >> "$E/ecritures"
    printf 's.banc%s' "$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')" > "$E/lien.secret"
    printf 'acc%s' "$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')" > "$E/lien.accesseur"
    jq -n --rawfile t "$E/lien.secret" --rawfile a "$E/lien.accesseur" \
      '{auth: {client_token: $t, accessor: $a, policies: ["lien-signature"], token_policies: ["lien-signature"], lease_duration: 259200, renewable: false, orphan: true}}' ;;
  "token lookup")
    [ "$qui" = root ] || refuse
    [ "${!#}" = "$(cat "$E/lien.accesseur")" ] || { echo "Error: bad accessor" >&2; exit 2; }
    jq -n '{data: {policies: ["lien-signature"], type: "service", orphan: true, renewable: false, explicit_max_ttl: 259200, ttl: 259190,
                   display_name: "token-brique09-lien", num_uses: 0}}' ;;
  *) echo "faux bao : appel inattendu : $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$B/bin/kubectl" "$B/bin/bao"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$B/modele/priv.pem" 2>/dev/null
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$B/modele/autre.pem" 2>/dev/null
openssl pkey -in "$B/modele/priv.pem" -pubout > "$B/modele/pub.pem"
mkdir -p "$B/modele/pol"; printf 'path "sys/x" {}\n' > "$B/modele/pol/default"; printf 'path "y" {}\n' > "$B/modele/pol/chains-signature"

n_ok=0; n_ko=0
verdict() { # libellé condition
  if eval "$2"; then echo "OK   $1"; n_ok=$((n_ok + 1)); else echo "KO   $1 (condition : $2)"; n_ko=$((n_ko + 1)); fi
}
cas() { # nom mode scellé clés_initiales… : nouvel état et nouveau dossier de journaux
  local n=$1 m=$2 s=$3 k; shift 3
  C=$B/cas-$n; mkdir -p "$C/etat/cles" "$C/resultats"
  cp "$B/modele/pub.pem" "$B/modele/priv.pem" "$B/modele/autre.pem" "$C/etat/"; cp -r "$B/modele/pol" "$C/etat/pol"
  printf '%s\n' "$JETON" > "$C/etat/jeton-attendu"
  echo normal > "$C/etat/mode"; echo "$s" > "$C/etat/scelle"
  export BANC_ETAT=$C/etat
  for k in "$@"; do BAO_TOKEN=$JETON "$B/bin/bao" write -f "transit/keys/$k" >/dev/null; done
  echo "$m" > "$C/etat/mode"; : > "$C/etat/ecritures"; : > "$C/etat/appels"
  cp -r "$B/secrets" "$B/bin" "$C/"
}
cas_jeton() { # nom mode : clés chains lien scanner tsa, clé publique déjà exportée (état après cle_lien)
  cas "$1" "$2" false chains lien scanner tsa
  cp "$B/modele/pub.pem" "$C/resultats/lien-cle-publique.pem"
}
# shellcheck disable=SC2034
lancer() { # étape : lance o5-openbao.sh dans le cas courant ; code dans RC, journal dans J (lus par verdict, via eval)
  BANC=$C "$S" "$1" > "$C/$1.sortie" 2>&1; RC=$?; J=$C/resultats/o5-openbao-$1.log
}
ecritures() { grep -c . "$C/etat/ecritures" || true; }

{
echo "banc commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-openbao.sh $(sha256sum < "$S" | cut -c1-16)… ; o5-openbao-banc.sh $(sha256sum < "$0" | cut -c1-16)… ; lien-signature.hcl $(sha256sum < "$here/politique/lien-signature.hcl" | cut -c1-16)…"
set +e
echo "## premier accord : releve et cle_lien"
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
verdict "faux bao jamais appelé sans le jeton" '! grep -q "jeton absent ou faux" "$C"/*.sortie "$C"/resultats/*.log'
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

echo "## deuxième accord : acces_lien"
echo "### 7. nominal"
cas_jeton acces normal
lancer acces_lien
verdict "acces_lien : code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "acces_lien : deux écritures, politique puis secret" '[ "$(paste -sd, "$C/etat/ecritures")" = "pol lien-signature,secret" ]'
verdict "politique écrite = fichier versionné (octets)" 'cmp -s "$C/etat/pol/lien-signature" "$here/politique/lien-signature.hcl"'
verdict "secret lien écrit dans secrets9, mode 600, égal à celui émis" '[ "$(stat -c %a "$C/secrets9/openbao-lien.secret")" = 600 ] && cmp -s "$C/secrets9/openbao-lien.secret" "$C/etat/lien.secret"'
verdict "accesseur écrit, mode 600" '[ "$(stat -c %a "$C/secrets9/openbao-lien.accesseur")" = 600 ] && cmp -s "$C/secrets9/openbao-lien.accesseur" "$C/etat/lien.accesseur"'
verdict "essais : 11 lignes OK" '[ "$(grep -c "^OK   essai " "$J")" = 11 ]'
verdict "signature vérifiée par openssl, témoin refusé" 'grep -q "^OK   openssl : signature de la clé lien vérifiée" "$J" && grep -q "^OK   témoin : même signature sur une autre entrée refusée" "$J"'
verdict "essais faits avec le secret lien (appels « lien » dans le faux bao)" '[ "$(grep -c "^lien " "$C/etat/appels")" = 11 ]'
verdict "valeurs des secrets absentes des journaux et sorties" '! grep -r -q -F -e "$JETON" -e "$(cat "$C/etat/lien.secret")" "$C/resultats" "$C"/*.sortie'
verdict "K5 tenu dans le journal" 'grep -q "^OK   K5 : valeur du secret lien absente du journal" "$J"'
verdict "aucune ligne masquée dans le journal nominal (mots jeton et token évités)" '! grep -q "ligne masquée" "$J"'
cp "$J" "$C/acces_lien-nominal.log"
echo "### 8. acces_lien relancée : secret déjà présent (refus avant le dossier d'essai)"
lancer acces_lien
verdict "relance : refus, aucune écriture, secret inchangé" 'grep -q "^KO   secret lien ou accesseur déjà présent dans 09/secrets : rien n.est écrasé" "$J" && [ "$(ecritures)" = 2 ] && cmp -s "$C/secrets9/openbao-lien.secret" "$C/etat/lien.secret"'
echo "### 9. politique déjà présente"
cas_jeton politique normal
printf 'path "x" {}\n' > "$C/etat/pol/lien-signature"
lancer acces_lien
verdict "politique présente : refus, aucune écriture, aucun secret" 'grep -q "^KO   politique lien-signature déjà présente : aucune écriture" "$J" && [ "$(ecritures)" = 0 ] && [ ! -e "$C/secrets9/openbao-lien.secret" ]'
echo "### 10. création du secret refusée"
cas_jeton refusee creation_refusee
lancer acces_lien
verdict "création refusée : KO, aucun fichier de secret non vide" 'grep -q "^KO   secret lien ou accesseur vide" "$J" && [ ! -s "$C/secrets9/openbao-lien.secret" ]'
echo "### 11. politique trop large (signature avec chains acceptée)"
cas_jeton large trop_large
lancer acces_lien
verdict "droit en trop : détecté" 'grep -q "^KO   essai signature avec la clé chains : REFUSE attendu" "$J"'
echo "### 12. signature par une autre clé"
cas_jeton autre autre_signature
lancer acces_lien
verdict "signature d'une autre clé : refusée par openssl" 'grep -q "^KO   openssl : Verification failure" "$J"'
echo "### 13. valeur du secret lien dans une réponse refusée"
cas_jeton fuite fuite
lancer acces_lien
verdict "fuite : journal vidé par K5, valeur absente" 'grep -q "^KO   K5 : valeur du secret lien dans le journal : journal vidé" "$J" && [ "$(grep -c . "$J")" = 1 ] && ! grep -q -F "$(cat "$C/etat/lien.secret")" "$J"'
verdict "fuite : valeur absente de la sortie standard et d'erreur" '! grep -q -F "$(cat "$C/etat/lien.secret")" "$C/acces_lien.sortie"'
echo "### journal nominal de acces_lien"
sed 's/^/     | /' "$B/cas-acces/acces_lien-nominal.log"
echo "bilan : $n_ok OK, $n_ko KO"
echo "banc fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "à effacer après archivage (chemin littéral) : $B"
[ "$n_ko" = 0 ]
} 2>&1 | tee "$here/resultats/o5-openbao-banc-jeton.log"
