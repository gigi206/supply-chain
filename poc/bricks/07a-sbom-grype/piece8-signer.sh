#!/usr/bin/env bash
# Brique 07b, pièce 8 : signer et publier dans le VRAI Zot un VEX du dépôt (vex/), contenu validé par le propriétaire. Écrit le
# 2026-11-24 : aucun script ne le faisait (l'essai de la pose du 22/11 et les bancs visaient un Zot jetable).
# Étapes :
#   prealables : LECTURE SEULE. Document présent et contenu figé (sha256 attendu en argument), binaire bao vérifié, mots de passe
#                présents (test -s, jamais lus ici), poc-vex authentifié sur /v2/ du vrai Zot (200), redirection vers openbao-0
#                ouverte puis fermée sans connexion, juge scan-outil reconstruit depuis HEAD (7dde1a8ed457f254), signer-vex.sh
#                verifier sur une copie horodatée (acceptée attendue), aucun VEX déjà publié sur le digest.
#   signer     : ACCORD NOMMÉ DU PROPRIÉTAIRE OBLIGATOIRE (variable ACCORD : sa phrase, recopiée dans le journal). Horodatage du
#                document du dépôt (timestamp du document et des énoncés, date -u du lancement ; seul champ écrit), verifier,
#                connexion userpass « proprietaire » (-no-store, mot de passe lu par bao dans son fichier : password=@…, jamais
#                en argument ni affiché), signer-vex.sh signer (hashivault://vex, publication par poc-vex), révocation de soi,
#                fermeture de la redirection, relecture : verifier voit l'énoncé publié (PUBLIES|n, n = énoncés du document).
#                Secrets (jeton d'OpenBao, configuration d'oras) dans un dossier 0700 neuf, effacé à la fin.
# Le registre est lu et écrit par 192.168.161.13:5000 (sc-stockage.poc.test ne se résout pas sur l'hôte, note du 23/11).
# Les lignes de journal évitent les mots « jeton » et « token » (le jeton y est dit « secret »).
# Usage (racine du dépôt) : [ACCORD='…'] piece8-signer.sh prealables|signer <vex/…json> <sha256 attendu du document, 16 premiers>
#   journal : resultats/piece8-signer-<étape>-<nom du document>.log (refus s'il existe)
set -uo pipefail
export LC_ALL=C
[ $# = 3 ] || { echo "usage : piece8-signer.sh prealables|signer <vex/…json> <sha256 attendu (16)>" >&2; exit 2; }
E=$1 DOC=$2 ATT=$3
case $E in prealables | signer) ;; *) echo "étape inconnue : $E" >&2; exit 2 ;; esac
R=poc/bricks/07a-sbom-grype
test -f "$DOC" || { echo "document introuvable : $DOC" >&2; exit 2; }
NOM=$(basename "$DOC" .json)
J=$R/resultats/piece8-signer-$E-$NOM.log
test ! -e "$J" || { echo "existe déjà : $J" >&2; exit 1; }
if [ "$E" = signer ] && [ -z "${ACCORD:-}" ]; then echo "signer : ACCORD (phrase du propriétaire) absent, rien n'est fait" >&2; exit 2; fi
S7=$HOME/.cache/supply-chain-poc/07a/secrets
MDP_BAO=$S7/openbao-proprietaire.password
MDP_VEX=$S7/zot-poc-vex.password
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
NOM_TLS=openbao.openbao.svc.cluster.local
BAO=$HOME/.cache/supply-chain-poc/07a/bao-2.7.2/bao
BAO_SHA256=9c5f36287c673f386e1533e9c044169a248e4ee50dd54810fa766e95bd41b788
REG=192.168.161.13:5000
# Image déduite du document (ajout du 24/11, VEX du deb) : produit pkg:oci/<nom>@sha256:<hex>, le même pour tous les énoncés
P_OCI=$(jq -r '[.statements[].products[]."@id"] | unique | if length == 1 then .[0] else "plusieurs" end' "$DOC")
printf '%s' "$P_OCI" | grep -qE '^pkg:oci/[a-z0-9-]+@sha256:[0-9a-f]{64}$' || { echo "produit du document illisible ou multiple : $P_OCI" >&2; exit 2; }
APP=$REG/builds/${P_OCI#pkg:oci/}
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml CA CLE_SCANNER=$R/resultats/scanner-cle-publique.pem \
  CLE_PUBLIQUE=$R/resultats/vex-cle-publique.pem
GO=$(mise which go)
W=$(mktemp -d "$HOME/.cache/supply-chain-poc/07a/piece8-signer.XXXXXX"); chmod 700 "$W"
JT=$W/secret
PF=; PORT=
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
masquer() { sed -E '/jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ouvrir() {
  kubectl port-forward -n openbao pod/openbao-0 --address 127.0.0.1 :8200 > "$W/redirection.log" 2>&1 &
  PF=$!
  for _ in $(seq 1 75); do
    PORT=$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) -> 8200$/\1/p' "$W/redirection.log" | head -1)
    [ -n "$PORT" ] && break; kill -0 "$PF" 2>/dev/null || break; sleep 0.2
  done
  [ -n "$PORT" ]
}
fermer() {
  [ -n "$PF" ] || return 0
  kill "$PF" 2>/dev/null; wait "$PF" 2>/dev/null
  if kill -0 "$PF" 2>/dev/null || (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then echo "KO   redirection encore ouverte"; KO=$((KO + 1))
  else echo "OK   redirection fermée"; fi
  PF=
}
client() { # commande… : environnement d'OpenBao (bao et cosign) ; secret lu dans le sous-shell, jamais en argument
  ( if [ -s "$JT" ]; then VAULT_TOKEN=$(cat "$JT"); BAO_TOKEN=$VAULT_TOKEN; export VAULT_TOKEN BAO_TOKEN; fi
    export VAULT_ADDR="https://127.0.0.1:$PORT" VAULT_CACERT="$CA" VAULT_TLS_SERVER_NAME="$NOM_TLS"
    export BAO_ADDR="$VAULT_ADDR" BAO_CACERT="$CA" BAO_TLS_SERVER_NAME="$NOM_TLS" HOME="$W/home"
    exec "$@" < /dev/null )
}
verifier() { env SCAN_OUTIL="$W/bin/scan-outil" timeout 120 bash "$R/signer-vex.sh" verifier "$1" "$APP" 2>&1; }
fin() { fermer > /dev/null 2>&1; find "$W" -delete 2>/dev/null; }
trap fin EXIT
corps() {
echo "# piece8-signer.sh $E $DOC, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
[ "$E" = signer ] && echo "accord du propriétaire (verbatim) : « $ACCORD »"
echo "## préalables (lecture seule)"
attendu "document : sha256 (16) attendu, avant tout horodatage" "$(sha256sum < "$DOC" | cut -c1-16)" "$ATT"
attendu "document : horodatages encore vides" "$(jq -c '[.timestamp, (.statements[].timestamp)] | unique' "$DOC")" '[""]'
jq -c '{id: ."@id", author, enonces: [.statements[] | {n: .vulnerability.name, j: .justification}]}' "$DOC"
attendu "binaire bao" "$(sha256sum < "$BAO" | cut -c1-64)" "$BAO_SHA256"
attendu "mot de passe du propriétaire pour OpenBao présent (test -s)" "$(test -s "$MDP_BAO" && echo oui)" oui
attendu "mot de passe de poc-vex présent (test -s)" "$(test -s "$MDP_VEX" && echo oui)" oui
attendu "poc-vex authentifié sur /v2/ du vrai Zot (code HTTP)" "$(printf 'user = "poc-vex:%s"\n' "$(cat "$MDP_VEX")" \
  | curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" -K - "https://$REG/v2/")" 200
git archive HEAD "$R/outil" | tar -x -C "$W" && mkdir -p "$W/bin" "$W/cache" "$W/home"
(cd "$W/$R/outil" && CGO_ENABLED=0 GOPROXY=off GOCACHE=$W/cache GOFLAGS=-mod=mod \
  "$GO" build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o "$W/bin/scan-outil" .) > "$W/build.err" 2>&1
attendu "juge scan-outil depuis HEAD" "$(sha256sum < "$W/bin/scan-outil" 2>/dev/null | cut -c1-16)" 7dde1a8ed457f254
ouvrir; attendu "redirection vers openbao-0 ouverte (aucune connexion)" "$([ -n "$PORT" ] && echo oui)" oui
fermer
if [ "$E" = prealables ]; then
  h=$(date -u +%FT%TZ)
  jq --arg h "$h" '.timestamp = $h | .statements |= map(.timestamp = $h)' "$DOC" > "$W/copie.json"
  o=$(verifier "$W/copie.json"); c=$?; echo "$o" | cut -c1-220 | masquer
  attendu "copie horodatée ($h) : acceptée par verifier" "$c" 0
  attendu "aucun VEX déjà publié sur le digest" "$(grep -c '^PUBLIES|0 ' <<< "$o")" 1
  echo "## bilan : $N cas, $KO écart(s) ; rien signé, rien publié, document du dépôt inchangé ($(sha256sum < "$DOC" | cut -c1-16))"
  return 0
fi
[ "$KO" = 0 ] || { echo "## arrêt : $KO écart(s) aux préalables, rien signé"; return 1; }
echo "## horodatage du document du dépôt (seul champ écrit)"
h=$(date -u +%FT%TZ)
jq --arg h "$h" '.timestamp = $h | .statements |= map(.timestamp = $h)' "$DOC" > "$W/horodate.json" && cat "$W/horodate.json" > "$DOC"
echo "horodatage : $h ; document sha256 $(sha256sum < "$DOC" | cut -c1-64)"
attendu "seuls les horodatages ont changé" "$(jq -S 'del(.timestamp) | .statements |= map(del(.timestamp))' "$DOC" | sha256sum | cut -c1-16)" \
  "$(git show "HEAD:$DOC" | jq -S 'del(.timestamp) | .statements |= map(del(.timestamp))' | sha256sum | cut -c1-16)"
o=$(verifier "$DOC"); c=$?; echo "$o" | cut -c1-220 | masquer
attendu "document horodaté : accepté par verifier" "$c" 0
[ "$KO" = 0 ] || { echo "## arrêt : $KO écart(s), rien signé"; return 1; }
echo "## connexion du propriétaire (userpass, -no-store, mot de passe lu par bao dans son fichier)"
ouvrir || { echo "KO   redirection non ouverte"; return 1; }
client "$BAO" login -method=userpass -no-store -format=json username=proprietaire password=@"$MDP_BAO" > "$W/connexion.json" 2> "$W/connexion.err"; c=$?
(umask 077 && jq -j '.auth.client_token // empty' "$W/connexion.json" > "$JT" 2>/dev/null)
pol=$(jq -r '.auth.policies | sort | join("+")' "$W/connexion.json" 2>/dev/null); dur=$(jq -r '.auth.lease_duration' "$W/connexion.json" 2>/dev/null)
find "$W/connexion.json" -delete
attendu "connexion : code, secret présent, politiques, durée" "$c,$(test -s "$JT" && echo oui),$pol,$dur" "0,oui,vex-signature,900"
[ "$KO" = 0 ] || { echo "connexion : $(head -c 160 "$W/connexion.err" | masquer)"; echo "## arrêt, rien signé"; return 1; }
echo "## signature et publication (signer-vex.sh signer, hashivault://vex, poc-vex)"
(umask 077 && printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG" "$(printf '%s:%s' poc-vex "$(cat "$MDP_VEX")" | base64 -w0)" > "$W/oras.json")
o=$(client env SCAN_OUTIL="$W/bin/scan-outil" CONFIG_REGISTRE="$W/oras.json" CA="$CA" CLE_SCANNER="$CLE_SCANNER" CLE_PUBLIQUE="$CLE_PUBLIQUE" \
  timeout 300 bash "$R/signer-vex.sh" signer "$DOC" "$APP" 2>&1); c=$?
echo "$o" | cut -c1-240 | masquer
attendu "signer-vex.sh signer : code" "$c" 0
attendu "ligne PUBLIE" "$(grep -c '^PUBLIE|' <<< "$o")" 1
echo "## révocation de soi et fermeture"
client "$BAO" token revoke -self > /dev/null 2> "$W/revocation.err"; attendu "révocation de soi : code" "$?" 0
find "$JT" "$W/oras.json" -delete
fermer
echo "## relecture : énoncés publiés vérifiés par la clé publique VEX"
o=$(verifier "$DOC"); echo "$o" | grep '^PUBLIES|\|^AVIS|' | cut -c1-220 | masquer
attendu "énoncés publiés vérifiés sur le digest" "$(sed -n 's/^PUBLIES|\([0-9]*\) .*/\1/p' <<< "$o")" "$(jq '.statements | length' "$DOC")"
echo "## bilan : $N cas, $KO écart(s)"
}
corps > "$J" 2>&1
c=$?
sed -i "s#$HOME#~#g" "$J"
cat "$J"
exit "$c"
