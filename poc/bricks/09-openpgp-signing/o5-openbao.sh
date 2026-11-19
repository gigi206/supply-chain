#!/usr/bin/env bash
# Brique 09, O5 réel, premier accord du propriétaire (« Oui », 19/11/2026) : clé Transit « lien » dans OpenBao, réservée à
# l'attestation de lien (D3 a). Rien d'autre : ni politique, ni jeton, ni rôle (deuxième accord), ni Zot (troisième accord).
# Mécanisme de la 07a et de la 08 (fonction racine) : le jeton root est lu par ce script et passé sur l'entrée standard de
# kubectl exec dans openbao-0 ; il n'est jamais affiché, ni lu par la session.
#   releve    lecture seule : état d'OpenBao (version, initialisé, scellé), clés Transit (nom, type, dernière version,
#             exportable), absence de transit/keys/lien
#   cle_lien  refuse si transit/keys/lien existe ; sinon la crée (ecdsa-p256, non exportable, sans sauvegarde en clair), la relit,
#             exporte sa clé publique dans resultats/lien-cle-publique.pem et vérifie que les autres clés Transit n'ont pas changé
# Banc : BANC=<dossier> remplace kubectl, bao et le jeton par ceux du banc (o5-openbao-banc.sh) ; journal dans ce dossier.
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o5-openbao.sh <étape>   (journal : resultats/o5-openbao-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
S8=$HOME/.cache/supply-chain-poc/08/secrets
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
if [ -n "${BANC:-}" ]; then R=$BANC/resultats; S8=$BANC/secrets; export PATH=$BANC/bin:$PATH; fi
CLE=lien
PEM=$R/lien-cle-publique.pem
ATTENDU_CLE="ecdsa-p256,false,false,false,1,true"   # type, exportable, sauvegarde en clair, suppression, dernière version, signature

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; }
racine() { # script sh sur l'entrée standard, exécuté dans openbao-0 avec le jeton root lu sur l'entrée standard (07a, 08)
  { tr -d '\n' < "$S8/openbao-root.token"; echo; cat; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c 'read -r BAO_TOKEN && export BAO_TOKEN && exec sh -s'
}
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

e=${1:-}
case "$e" in
  releve|cle_lien)
    mkdir -p "$R"
    L=$R/o5-openbao-$e.log
    set +e
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-openbao.sh $(sha256sum < "$here/o5-openbao.sh" | cut -c1-16)…${BANC:+ ; BANC}"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer | tee "$L"; rc=${PIPESTATUS[0]}
    n=$(grep -c -E -e '-----BEGIN (PGP|[A-Z ]*PRIVATE)' "$L" || true)
    if [ "$n" != 0 ]; then : > "$L"; echo "KO   K3 : $n ligne(s) de bloc privé dans le journal : journal vidé" | tee "$L"; exit 1; fi
    echo "OK   K3 : aucune ligne de bloc privé dans le journal" | tee -a "$L"
    n=$(tr -d '\n' < "$S8/openbao-root.token" | grep -c -F -f - "$L" || true)   # valeur lue par le script, jamais affichée
    if [ "$n" != 0 ]; then : > "$L"; echo "KO   K4 : valeur du jeton root dans le journal : journal vidé" | tee "$L"; exit 1; fi
    echo "OK   K4 : valeur du jeton root absente du journal" | tee -a "$L"
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" | tee -a "$L"; rc=1; }
    exit "$rc" ;;
  *) echo "usage : $0 releve | cle_lien" >&2; exit 64 ;;
esac
