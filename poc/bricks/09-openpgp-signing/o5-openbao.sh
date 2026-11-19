#!/usr/bin/env bash
# Brique 09, O5 réel, premier accord du propriétaire (« Oui », 19/11/2026) : clé Transit « lien » dans OpenBao, réservée à
# l'attestation de lien (D3 a). Rien d'autre : ni politique, ni jeton, ni rôle (deuxième accord), ni Zot (troisième accord).
# Mécanisme de la 07a et de la 08 (fonction racine) : le jeton root est lu par ce script et passé sur l'entrée standard de
# kubectl exec dans openbao-0 ; il n'est jamais affiché, ni lu par la session.
#   releve    lecture seule : état d'OpenBao (version, initialisé, scellé), clés Transit (nom, type, dernière version,
#             exportable), absence de transit/keys/lien
#   cle_lien  refuse si transit/keys/lien existe ; sinon la crée (ecdsa-p256, non exportable, sans sauvegarde en clair), la relit,
#             exporte sa clé publique dans resultats/lien-cle-publique.pem et vérifie que les autres clés Transit n'ont pas changé
#   acces_lien  deuxième accord (« Oui », 19/11/2026) : politique lien-signature (politique/lien-signature.hcl) et un jeton de
#             service borné (cette politique seule, sans la politique default, orphelin, 72 h, non renouvelable), écrit par ce
#             script dans 09/secrets/openbao-lien.secret (0600), jamais affiché ni lu par la session ; son accesseur à côté. Essais
#             avec ce jeton : lecture de la clé lien et signature acceptées (signature vérifiée sur l'hôte par openssl avec la clé
#             publique archivée) ; autres clés, export, kv, politiques, jeton enfant et consultation de soi refusés.
#             Refuse si la politique ou le fichier du jeton existe déjà.
# Banc : BANC=<dossier> remplace kubectl, bao et le jeton par ceux du banc (o5-openbao-banc.sh) ; journal dans ce dossier.
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o5-openbao.sh <étape>   (journal : resultats/o5-openbao-<étape>.log)
# Les lignes de journal évitent les mots « jeton » et « token », que le masquage remplace (le jeton y est dit « secret lien »).
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
S8=$HOME/.cache/supply-chain-poc/08/secrets
S9=$HOME/.cache/supply-chain-poc/09/secrets
ESSAI=$HOME/.cache/supply-chain-poc/09/o5-essai-signature
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
if [ -n "${BANC:-}" ]; then R=$BANC/resultats; S8=$BANC/secrets; S9=$BANC/secrets9; ESSAI=$BANC/essai; export PATH=$BANC/bin:$PATH; fi
CLE=lien
PEM=$R/lien-cle-publique.pem
ATTENDU_CLE="ecdsa-p256,false,false,false,1,true"   # type, exportable, sauvegarde en clair, suppression, dernière version, signature
POL=$here/politique/lien-signature.hcl
NOM_POL=lien-signature
JL=$S9/openbao-lien.secret
JA=$S9/openbao-lien.accesseur
ENTREE="brique 09, O5 : essai de signature avec le secret lien-signature"
# Résultats attendus des essais, dans l'ordre (libellé|ACCEPTE ou REFUSE)
ESSAIS_ATTENDUS="lecture de transit/keys/lien|ACCEPTE
signature avec la clé lien|ACCEPTE
signature avec la clé chains|REFUSE
signature avec la clé tsa|REFUSE
signature avec la clé scanner|REFUSE
lecture de transit/keys/chains|REFUSE
export de la clé lien|REFUSE
lecture de kv/horodatage/zot|REFUSE
liste des politiques|REFUSE
création d'un secret enfant|REFUSE
consultation de soi|REFUSE"

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; }
racine() { # script sh sur l'entrée standard, exécuté dans openbao-0 avec le jeton root lu sur l'entrée standard (07a, 08)
  { tr -d '\n' < "$S8/openbao-root.token"; echo; cat; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c 'read -r BAO_TOKEN && export BAO_TOKEN && exec sh -s'
}
en_lien() { # script sh sur l'entrée standard, exécuté dans openbao-0 avec le jeton lien lu sur l'entrée standard ; refus() comme la 08
  { tr -d '\n' < "$JL"; echo; cat; } | kubectl exec -i -n openbao openbao-0 -- sh -c '
read -r BAO_TOKEN && export BAO_TOKEN
refus() { l=$1; shift; if o=$("$@" 2>&1); then echo "ACCEPTE|$l"; else echo "REFUSE|$l|$(echo "$o" | grep -E "Code:|\* " | tr "\n\t" "  " | sed "s/  */ /g")"; fi; }
eval "$(cat)"'
}
politiques() { racine <<<'bao policy list -format=json' | jq -r '.[]' | sort; }
sans_commentaires() { grep -v -e '^#' -e '^[[:space:]]*$' | sha256sum | cut -c1-16; }
cles() { # une ligne par clé Transit : nom type dernière_version exportable, triée
  local l k
  l=$(racine <<<'bao list -format=json transit/keys') || { echo "ERREUR liste"; return 1; }
  for k in $(jq -r '.[]' <<<"$l"); do
    [[ $k =~ ^[a-z0-9-]+$ ]] || { echo "ERREUR nom de clé inattendu"; return 1; }
    racine <<<"bao read -format=json transit/keys/$k" | jq -r --arg k "$k" '.data | "\($k) \(.type) \(.latest_version) \(.exportable)"'
  done | sort
}
etat_bao() {
  local s
  s=$(racine <<<'bao status -format=json || true')
  echo "OpenBao : $(jq -r '"version \(.version), initialisé \(.initialized), scellé \(.sealed)"' <<<"$s")"
  [ "$(jq -r .sealed <<<"$s")" = false ] && [ "$(jq -r .initialized <<<"$s")" = true ]
}

etape_releve() {
  set +e
  local c
  etat_bao && echo "OK   OpenBao initialisé et descellé" || { ko "OpenBao scellé, non initialisé ou illisible"; return 1; }
  c=$(cles) || { ko "liste des clés Transit illisible"; return 1; }
  echo "clés Transit (nom type dernière_version exportable) :"; sed 's/^/     /' <<<"$c"
  grep -q "^$CLE " <<<"$c" && ko "transit/keys/$CLE existe déjà" || echo "OK   transit/keys/$CLE absente"
  [ ! -e "$PEM" ] && echo "OK   ${PEM#"$here"/} absent" || ko "${PEM#"$here"/} existe déjà"
}

etape_cle_lien() {
  set +e
  local avant apres cle w rc pub
  etat_bao && echo "OK   OpenBao initialisé et descellé" || { ko "OpenBao scellé, non initialisé ou illisible"; return 1; }
  [ ! -e "$PEM" ] || { ko "${PEM#"$here"/} existe déjà : rien n'est écrasé"; return 1; }
  avant=$(cles) || { ko "liste des clés Transit illisible (avant)"; return 1; }
  echo "avant :"; sed 's/^/     /' <<<"$avant"
  if grep -q "^$CLE " <<<"$avant"; then ko "transit/keys/$CLE existe déjà : aucune écriture"; return 1; fi
  echo "### création (seule écriture de l'étape)"
  w=$(racine <<<"bao write -f transit/keys/$CLE type=ecdsa-p256 exportable=false allow_plaintext_backup=false" 2>&1); rc=$?
  sed 's/^/     | /' <<<"$w"
  [ "$rc" = 0 ] && echo "OK   bao write -f transit/keys/$CLE : code 0" || { ko "bao write : code $rc"; return 1; }
  echo "### relecture"
  cle=$(racine <<<"bao read -format=json transit/keys/$CLE")
  local vu
  vu=$(jq -r '.data | [.type, .exportable, .allow_plaintext_backup, .deletion_allowed, .latest_version, .supports_signing] | map(tostring) | join(",")' <<<"$cle")
  [ "$vu" = "$ATTENDU_CLE" ] && echo "OK   clé $CLE (type, exportable, sauvegarde en clair, suppression, version, signature) : $vu" \
    || ko "clé $CLE : $vu (attendu : $ATTENDU_CLE)"
  jq -j '.data.keys["1"].public_key' <<<"$cle" > "$PEM"   # -j : octets de la chaîne d'OpenBao, sans saut de ligne ajouté (banc)
  if openssl pkey -pubin -in "$PEM" -noout 2>/dev/null; then
    pub=$(openssl pkey -pubin -in "$PEM" -outform DER | sha256sum | cut -c1-64)
    echo "     $(openssl pkey -pubin -in "$PEM" -noout -text | sed -n '1p;/NIST CURVE/p' | paste -sd ';' -)"
    echo "OK   clé publique exportée : ${PEM#"$here"/} (fichier sha256 $(sha256sum < "$PEM" | cut -c1-64) ; SPKI sha256 $pub)"
  else ko "clé publique illisible par openssl"; fi
  apres=$(cles) || { ko "liste des clés Transit illisible (après)"; return 1; }
  echo "après :"; sed 's/^/     /' <<<"$apres"
  [ "$(printf '%s\n%s\n' "$avant" "$CLE ecdsa-p256 1 false" | sed '/^$/d' | sort)" = "$apres" ] \
    && echo "OK   seule différence : transit/keys/$CLE ajoutée ; les autres clés Transit sont inchangées (type, version, exportable)" \
    || ko "clés Transit : différence autre que l'ajout de $CLE"
}

etape_acces_lien() {
  set +e
  local avant apres cle out vu p lu b64 s attendu_l obtenu ko_essais=0
  etat_bao && echo "OK   OpenBao initialisé et descellé" || { ko "OpenBao scellé, non initialisé ou illisible"; return 1; }
  [ ! -e "$JL" ] && [ ! -e "$JA" ] && echo "OK   secret lien et accesseur absents de 09/secrets" \
    || { ko "secret lien ou accesseur déjà présent dans 09/secrets : rien n'est écrasé"; return 1; }
  [ -f "$PEM" ] || { ko "${PEM#"$here"/} absent (étape cle_lien)"; return 1; }
  cle=$(racine <<<"bao read -format=json transit/keys/$CLE")
  vu=$(jq -r '.data | [.type, .exportable, .allow_plaintext_backup, .deletion_allowed, .latest_version, .supports_signing] | map(tostring) | join(",")' <<<"$cle")
  [ "$vu" = "$ATTENDU_CLE" ] && echo "OK   clé $CLE toujours conforme : $vu" || { ko "clé $CLE : $vu (attendu : $ATTENDU_CLE)"; return 1; }
  cmp -s <(jq -j '.data.keys["1"].public_key' <<<"$cle") "$PEM" && echo "OK   clé publique de $CLE égale à ${PEM#"$here"/}" \
    || { ko "clé publique de $CLE différente de ${PEM#"$here"/}"; return 1; }
  avant=$(politiques)
  echo "politiques avant : $(paste -sd' ' <<<"$avant")"
  grep -qx "$NOM_POL" <<<"$avant" && { ko "politique $NOM_POL déjà présente : aucune écriture"; return 1; }
  echo "### écriture 1 : politique $NOM_POL"
  racine <<EOF 2>&1 | sed 's/^/     | /'
bao policy write $NOM_POL - <<'POL'
$(cat "$POL")
POL
EOF
  lu=$(racine <<<"bao policy read $NOM_POL" | sans_commentaires)
  [ "$lu" = "$(sans_commentaires < "$POL")" ] && echo "OK   politique $NOM_POL relue = politique/lien-signature.hcl (hors commentaires et lignes vides : $lu)" \
    || ko "politique $NOM_POL relue ($lu) différente du fichier ($(sans_commentaires < "$POL"))"
  echo "### écriture 2 : secret lien (service, $NOM_POL seule, orphelin, 72 h, non renouvelable)"
  out=$(racine <<<"bao token create -format=json -policy=$NOM_POL -no-default-policy -orphan -ttl=72h -explicit-max-ttl=72h -renewable=false -display-name=brique09-lien" 2>/dev/null)
  mkdir -p "$S9"
  (umask 077 && jq -j '.auth.client_token // empty' <<<"$out" > "$JL" && jq -j '.auth.accessor // empty' <<<"$out" > "$JA")
  echo "     réponse : politiques $(jq -c '.auth.policies' <<<"$out"), durée $(jq -r '.auth.lease_duration' <<<"$out") s, renouvelable $(jq -r '.auth.renewable' <<<"$out"), orphelin $(jq -r '.auth.orphan' <<<"$out")"
  out=
  if [ -s "$JL" ] && [ -s "$JA" ]; then
    echo "OK   secret lien écrit dans 09/secrets/openbao-lien.secret : mode $(stat -c %a "$JL"), $(wc -c < "$JL") octets, préfixe « s. » : $([ "$(head -c2 "$JL")" = s. ] && echo oui || echo non) ; accesseur à côté (mode $(stat -c %a "$JA"))"
  else ko "secret lien ou accesseur vide : création refusée ?"; return 1; fi
  [ "$(stat -c %a "$JL")" = 600 ] && [ "$(stat -c %a "$JA")" = 600 ] || ko "mode des fichiers du secret lien différent de 600"
  echo "### relecture par root (accesseur)"
  p=$( { echo "bao token lookup -format=json -accessor $(cat "$JA")"; } | racine | jq -r '.data | [(.policies | sort | join("+")), .type, .orphan, .renewable, .explicit_max_ttl, (.ttl > 259000 and .ttl <= 259200), (.display_name | endswith("brique09-lien")), .num_uses] | map(tostring) | join(",")')
  [ "$p" = "$NOM_POL,service,true,false,259200,true,true,0" ] \
    && echo "OK   secret lien (politiques, type, orphelin, renouvelable, durée maximale, durée restante, nom, usages) : $p" \
    || ko "secret lien : $p (attendu : $NOM_POL,service,true,false,259200,true,true,0)"
  echo "### essais avec le secret lien"
  b64=$(printf '%s' "$ENTREE" | base64 -w0)
  s=$(en_lien <<EOF
refus "lecture de transit/keys/lien" bao read transit/keys/lien
if o=\$(bao write -field=signature transit/sign/lien/sha2-256 input=$b64 2>&1); then echo "ACCEPTE|signature avec la clé lien"; echo "SIGNATURE|\$o"
else echo "REFUSE|signature avec la clé lien|\$(echo "\$o" | grep -E "Code:|\\* " | tr "\\n\\t" "  ")"; fi
refus "signature avec la clé chains" bao write transit/sign/chains/sha2-256 input=$b64
refus "signature avec la clé tsa" bao write transit/sign/tsa/sha2-256 input=$b64
refus "signature avec la clé scanner" bao write transit/sign/scanner/sha2-256 input=$b64
refus "lecture de transit/keys/chains" bao read transit/keys/chains
refus "export de la clé lien" bao read transit/export/signing-key/lien
refus "lecture de kv/horodatage/zot" bao read kv/horodatage/zot
refus "liste des politiques" bao policy list
refus "création d'un secret enfant" bao token create -policy=$NOM_POL
refus "consultation de soi" bao token lookup
EOF
)
  grep -v '^SIGNATURE|' <<<"$s" | sed 's/^/     | /'
  obtenu=$(grep -E '^(ACCEPTE|REFUSE)\|' <<<"$s" | cut -d'|' -f1-2 | awk -F'|' '{print $2 "|" $1}')
  while IFS= read -r attendu_l; do
    grep -qxF "$attendu_l" <<<"$obtenu" && echo "OK   essai ${attendu_l%|*} : ${attendu_l##*|}" || { ko "essai ${attendu_l%|*} : ${attendu_l##*|} attendu"; ko_essais=1; }
  done <<<"$ESSAIS_ATTENDUS"
  [ "$(grep -c . <<<"$obtenu")" = "$(grep -c . <<<"$ESSAIS_ATTENDUS")" ] || ko "nombre d'essais : $(grep -c . <<<"$obtenu") lignes ($(grep -c . <<<"$ESSAIS_ATTENDUS") attendues)"
  echo "### signature vérifiée sur l'hôte avec la clé publique archivée"
  [ ! -e "$ESSAI" ] || { ko "$ESSAI existe déjà"; return 1; }
  mkdir -p "$ESSAI"
  printf '%s' "$ENTREE" > "$ESSAI/entree.txt"
  s=$(grep -m1 '^SIGNATURE|' <<<"$s" | cut -d'|' -f2-)
  echo "     signature Transit : préfixe ${s%:*}, $(printf '%s' "${s##*:}" | base64 -d 2>/dev/null | wc -c) octets DER"
  printf '%s' "${s##*:}" | base64 -d > "$ESSAI/signature.der" 2>/dev/null
  echo "     $(openssl version)"
  # sortie standard seule : en cas d'échec, openssl 3 écrit aussi une pile d'erreurs sur stderr, parfois avant (banc)
  v=$(openssl dgst -sha256 -verify "$PEM" -signature "$ESSAI/signature.der" "$ESSAI/entree.txt" 2>/dev/null)
  [ "$v" = "Verified OK" ] && echo "OK   openssl : signature de la clé lien vérifiée par ${PEM#"$here"/} (Verified OK)" || ko "openssl : $v"
  printf '%s' "autre $ENTREE" > "$ESSAI/autre.txt"
  v=$(openssl dgst -sha256 -verify "$PEM" -signature "$ESSAI/signature.der" "$ESSAI/autre.txt" 2>/dev/null)
  [ "$v" = "Verification failure" ] && echo "OK   témoin : même signature sur une autre entrée refusée (Verification failure)" || ko "témoin : $v"
  echo "à effacer après archivage (chemin littéral) : $ESSAI"
  apres=$(politiques)
  [ "$(printf '%s\n%s\n' "$avant" "$NOM_POL" | sort)" = "$apres" ] && echo "OK   seule politique ajoutée : $NOM_POL" || ko "politiques : différence autre que l'ajout de $NOM_POL"
  apres=$(cles)
  echo "clés Transit après : $(paste -sd';' <<<"$apres")"
  [ "$apres" = "$(printf '%s\n' 'chains ecdsa-p256 1 false' 'lien ecdsa-p256 1 false' 'scanner ecdsa-p256 1 false' 'tsa ecdsa-p256 1 false')" ] \
    && echo "OK   clés Transit inchangées depuis cle_lien" || ko "clés Transit changées depuis cle_lien"
  return $ko_essais
}

e=${1:-}
case "$e" in
  releve|cle_lien|acces_lien)
    mkdir -p "$R"
    L=$R/o5-openbao-$e.log
    set +e
    # Journal écrit d'abord sans affichage (0600), contrôlé par K3, K4 et K5, puis seulement affiché : une valeur secrète
    # n'atteint jamais la sortie standard (banc, cas « fuite »).
    (umask 077 && : > "$L")
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-openbao.sh $(sha256sum < "$here/o5-openbao.sh" | cut -c1-16)…${BANC:+ ; BANC}"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer >> "$L"; rc=${PIPESTATUS[0]}
    vider() { : > "$L"; echo "$1" > "$L"; chmod 644 "$L"; cat "$L"; exit 1; }
    n=$(grep -c -E -e '-----BEGIN (PGP|[A-Z ]*PRIVATE)' "$L" || true)
    [ "$n" = 0 ] || vider "KO   K3 : $n ligne(s) de bloc privé dans le journal : journal vidé"
    echo "OK   K3 : aucune ligne de bloc privé dans le journal" >> "$L"
    n=$(tr -d '\n' < "$S8/openbao-root.token" | grep -c -F -f - "$L" || true)   # valeur lue par le script, jamais affichée
    [ "$n" = 0 ] || vider "KO   K4 : valeur du jeton root dans le journal : journal vidé"
    echo "OK   K4 : valeur du jeton root absente du journal" >> "$L"
    if [ -s "$JL" ]; then
      n=$(tr -d '\n' < "$JL" | grep -c -F -f - "$L" || true)
      [ "$n" = 0 ] || vider "KO   K5 : valeur du secret lien dans le journal : journal vidé"
      echo "OK   K5 : valeur du secret lien absente du journal" >> "$L"
    fi
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" >> "$L"; rc=1; }
    chmod 644 "$L"; cat "$L"
    exit "$rc" ;;
  *) echo "usage : $0 releve | cle_lien | acces_lien" >&2; exit 64 ;;
esac
