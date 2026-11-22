#!/usr/bin/env bash
# Brique 07b, tranche 3, pièce 2 de la pose : clé Transit « vex », politique vex-signature et identité du propriétaire par
# userpass dans l'OpenBao du cluster (décision du propriétaire du 22/11/2026 : « userpass puis Keycloak à part »). Écrit à sec
# le 22/11/2026 et éprouvé sur un OpenBao 2.7.2 jetable (resultats/07b-p2-pose-banc.sh). Chaque étape réelle demande un accord
# nommé du propriétaire.
# Mécanisme de la 07a, de la 08 et de la 09 (fonction racine) : le jeton root est lu par ce script et passé sur l'entrée standard
# de kubectl exec dans openbao-0 ; il n'est jamais affiché.
#   releve     lecture seule : état d'OpenBao, clés Transit, politiques, méthodes d'authentification ; absence de la clé vex, de
#              resultats/vex-cle-publique.pem, de la politique vex-signature et du montage userpass/
#   cle_vex    refuse si transit/keys/vex ou la clé publique archivée existe ; sinon crée la clé (ecdsa-p256, non exportable, sans
#              sauvegarde en clair), la relit, exporte sa clé publique dans resultats/vex-cle-publique.pem (lue par cm_scan de
#              plateforme.sh : vex.pub de la ConfigMap scan-config) et vérifie que les autres clés Transit n'ont pas changé
#   acces_vex  À LANCER PAR LE PROPRIÉTAIRE DANS SON TERMINAL. Mot de passe saisi deux fois sur /dev/tty, sans écho : refus si
#              les saisies diffèrent ou s'il compte moins de 12 caractères, et refus si /dev/tty est illisible (une session sans
#              terminal ne peut pas lancer cette étape). Puis : politique vex-signature (politique/vex-signature.hcl ; déjà
#              présente et identique : laissée, différente : refus), montage userpass/ (déjà présent de type userpass : laissé,
#              autre type : refus), utilisateur proprietaire (vex-signature seule, sans default, 15 min, non prolongeable).
#              Utilisateur déjà présent : refus, rien n'est réécrit (une relance ne change jamais le mot de passe : c'est le
#              contournement par la racine que l'audit doit montrer, note du passage 22). Le mot de passe passe sur l'entrée
#              standard de kubectl exec, puis sur celle de « bao write … password=- » dans le pod, sans saut de ligne ; jamais en
#              argument, jamais affiché.
#   essai      À LANCER PAR LE PROPRIÉTAIRE DANS SON TERMINAL, après acces_vex (refus si /dev/tty est illisible). Redirection
#              127.0.0.1:<port libre> vers openbao-0:8200 (o5-cosign.sh de la 09), fermée à la sortie ; connexion « bao login
#              -method=userpass -no-store » par l'invite de bao (mot de passe tapé par le propriétaire) ; jeton dans un fichier
#              0600 d'un dossier de travail neuf à chaque lancement (une connexion ratée n'empêche pas la relance), effacé à la fin. Essais : lecture de la clé vex et signature acceptées (signature vérifiée par openssl avec la clé
#              publique archivée, témoin sur une autre entrée refusé) ; autres clés, export, configuration et sauvegarde de vex,
#              kv, politiques, secret enfant et consultation de soi refusés ; cosign public-key --key hashivault://vex égale à la
#              clé archivée (SPKI) ; révocation de soi acceptée ; signature après révocation refusée.
# Banc : BANC=<dossier> remplace kubectl, le jeton root, la CA et le nom TLS par ceux du banc ; journal dans ce dossier. Seulement
# avec BANC, BANC_MDP (deux lignes : saisies d'acces_vex) et BANC_MDP_CONNEXION (mot de passe de la connexion d'essai, sans saut
# de ligne) remplacent le terminal ; sans elles, le banc pilote le terminal par un pty.
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/vex-openbao.sh <étape>   (journal : resultats/vex-openbao-<étape>.log)
# Les lignes de journal évitent les mots « jeton » et « token », que le masquage remplace (le jeton y est dit « secret »).
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null || echo "$here")
R=$here/resultats
S8=$HOME/.cache/supply-chain-poc/08/secrets
W=$HOME/.cache/supply-chain-poc/07a/vex-openbao
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
NOM_TLS=openbao.openbao.svc.cluster.local
BAO=$HOME/.cache/supply-chain-poc/07a/bao-2.7.2/bao   # extrait de l'image signée et vérifié par resultats/07b-p2-bao.sh
BAO_SHA256=9c5f36287c673f386e1533e9c044169a248e4ee50dd54810fa766e95bd41b788
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
if [ -n "${BANC:-}" ]; then
  R=$BANC/resultats; S8=$BANC/secrets; W=$BANC/travail; CA=$BANC/tls/vault-ca.pem; NOM_TLS=localhost; export PATH=$BANC/bin:$PATH
fi
CLE=vex
PEM=$R/vex-cle-publique.pem
ATTENDU_CLE="ecdsa-p256,false,false,false,1,true"   # type, exportable, sauvegarde en clair, suppression, dernière version, signature
POL=$here/politique/vex-signature.hcl
NOM_POL=vex-signature
UTIL=proprietaire
ATTENDU_UTIL="vex-signature,true,900,900"   # politiques, sans default, durée, durée maximale
JT=$W/secret
ENTREE="brique 07b, pièce 2 : essai de signature du propriétaire avec la clé vex"
# Résultats attendus des essais, dans l'ordre (libellé|ACCEPTE ou REFUSE)
ESSAIS_ATTENDUS="lecture de transit/keys/vex|ACCEPTE
signature avec la clé vex|ACCEPTE
signature avec la clé chains|REFUSE
signature avec la clé scanner|REFUSE
signature avec la clé tsa|REFUSE
signature avec la clé lien|REFUSE
lecture de transit/keys/chains|REFUSE
export de la clé vex|REFUSE
clé vex rendue exportable|REFUSE
sauvegarde de la clé vex|REFUSE
lecture de kv/scan/zot|REFUSE
liste des politiques|REFUSE
création d'un secret enfant|REFUSE
consultation de soi|REFUSE"
PF=; PORT=; MDP=

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; }
racine() { # script sh sur l'entrée standard, exécuté dans openbao-0 avec le jeton root lu sur l'entrée standard (07a, 08, 09)
  { tr -d '\n' < "$S8/openbao-root.token"; echo; cat; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c 'read -r BAO_TOKEN && export BAO_TOKEN && exec sh -s'
}
politiques() { racine <<<'bao policy list -format=json' | jq -r '.[]' | sort; }
methodes() { racine <<<'bao auth list -format=json' | jq -r 'to_entries[] | "\(.key) \(.value.type)"' | sort; }
sans_commentaires() { grep -v -e '^#' -e '^[[:space:]]*$' | sha256sum | cut -c1-16; }
spki() { openssl pkey -pubin -in "$1" -outform DER 2>/dev/null | sha256sum | cut -c1-64; }
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
util_present() { # code 0 si l'utilisateur userpass existe (montage présent et lecture réussie)
  racine <<<"bao read -format=json auth/userpass/users/$UTIL >/dev/null 2>&1 && echo present || echo absent" | grep -qx present
}
util_vu() { # politiques, sans default, durée, durée maximale de l'utilisateur, en valeurs seules (pas de nom de champ)
  racine <<<"bao read -format=json auth/userpass/users/$UTIL" \
    | jq -r '.data | [(.token_policies | sort | join("+")), .token_no_default_policy, .token_ttl, .token_max_ttl] | map(tostring) | join(",")'
}

lire_mdp() { # MDP ← mot de passe saisi deux fois ; code 1 et motif (sans la valeur) si refus
  local src n m2=''
  if [ -n "${BANC:-}" ] && [ -n "${BANC_MDP:-}" ]; then src=$BANC_MDP; else src=/dev/tty; fi
  if ! (: < "$src") 2>/dev/null; then
    echo "REFUS : $src illisible : acces_vex se lance dans le terminal du propriétaire, pas depuis une session sans terminal"; return 1
  fi
  exec 3< "$src"
  [ "$src" = /dev/tty ] && printf 'mot de passe du propriétaire pour OpenBao (userpass, %s), saisie sans écho : ' "$UTIL" > /dev/tty
  IFS= read -rs -u 3 MDP || MDP=
  [ "$src" = /dev/tty ] && printf '\nmême mot de passe, une seconde fois : ' > /dev/tty
  IFS= read -rs -u 3 m2 || m2=
  [ "$src" = /dev/tty ] && printf '\n' > /dev/tty
  exec 3<&-
  if [ "$MDP" != "$m2" ]; then MDP=; m2=; echo "REFUS : les deux saisies diffèrent ; rien n'est écrit"; return 1; fi
  m2=
  # caractères, pas octets (LC_ALL=C compterait les octets) ; printf est interne : la valeur ne passe pas en argument
  n=$(printf '%s' "$MDP" | LC_ALL=C.UTF-8 wc -m)
  if [ "$n" -lt 12 ]; then MDP=; echo "REFUS : mot de passe de moins de 12 caractères ; rien n'est écrit"; return 1; fi
  echo "OK   mot de passe saisi deux fois, identique, $n caractères (valeur jamais affichée)"
}

ouvrir() { # redirection 127.0.0.1:<port libre> → openbao-0:8200 ; PORT et PF (o5-cosign.sh)
  local _
  kubectl port-forward -n openbao pod/openbao-0 --address 127.0.0.1 :8200 > "$W/redirection.log" 2>&1 &
  PF=$!
  for _ in $(seq 1 75); do
    PORT=$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) -> 8200$/\1/p' "$W/redirection.log" | head -1)
    [ -n "$PORT" ] && break
    kill -0 "$PF" 2>/dev/null || break
    sleep 0.2
  done
  [ -n "$PORT" ] && echo "OK   redirection ouverte : 127.0.0.1:$PORT → openbao-0:8200 (processus $PF)" \
    || { ko "redirection non ouverte : $(head -1 "$W/redirection.log" | cut -c1-160)"; kill "$PF" 2>/dev/null; wait "$PF" 2>/dev/null; PF=; return 1; }
}
fermer() { # ferme la redirection et vérifie que le port n'écoute plus
  [ -n "$PF" ] || return 0
  kill "$PF" 2>/dev/null; wait "$PF" 2>/dev/null
  if kill -0 "$PF" 2>/dev/null; then ko "redirection : processus $PF toujours vivant"
  elif [ -z "${BANC:-}" ] && (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then ko "redirection fermée mais 127.0.0.1:$PORT répond encore"
  else echo "OK   redirection fermée : processus $PF arrêté${BANC:+ (banc : le port est celui du serveur du banc, non sondé)}"; fi
  PF=
}
client() { # commande… : environnement du client (bao et cosign) vers la redirection ; secret lu dans le sous-shell, jamais en argument
  ( if [ -s "$JT" ]; then VAULT_TOKEN=$(cat "$JT"); BAO_TOKEN=$VAULT_TOKEN; export VAULT_TOKEN BAO_TOKEN; fi
    export VAULT_ADDR="https://127.0.0.1:$PORT" VAULT_CACERT="$CA" VAULT_TLS_SERVER_NAME="$NOM_TLS"
    export BAO_ADDR="$VAULT_ADDR" BAO_CACERT="$CA" BAO_TLS_SERVER_NAME="$NOM_TLS" HOME="$W/home"
    exec "$@" < /dev/null )
}
essai() { # libellé commande… : ACCEPTE|libellé ou REFUSE|libellé|motif
  local l=$1 o; shift
  if o=$(client "$@" 2>&1); then echo "ACCEPTE|$l"; else echo "REFUSE|$l|$(grep -E 'Code:|\* ' <<<"$o" | tr '\n\t' '  ' | sed 's/  */ /g' | cut -c1-160)"; fi
}

etape_releve() {
  set +e
  local c
  etat_bao && echo "OK   OpenBao initialisé et descellé" || { ko "OpenBao scellé, non initialisé ou illisible"; return 1; }
  c=$(cles) || { ko "liste des clés Transit illisible"; return 1; }
  echo "clés Transit (nom type dernière_version exportable) :"; sed 's/^/     /' <<<"$c"
  grep -q "^$CLE " <<<"$c" && ko "transit/keys/$CLE existe déjà" || echo "OK   transit/keys/$CLE absente"
  [ ! -e "$PEM" ] && echo "OK   ${PEM#"$here"/} absent" || ko "${PEM#"$here"/} existe déjà"
  c=$(politiques); echo "politiques : $(paste -sd' ' <<<"$c")"
  grep -qx "$NOM_POL" <<<"$c" && ko "politique $NOM_POL déjà présente" || echo "OK   politique $NOM_POL absente"
  c=$(methodes); echo "méthodes d'authentification (hors la méthode native) : $(grep -v '^token/ ' <<<"$c" | paste -sd';' -)"
  grep -q '^userpass/ ' <<<"$c" && ko "montage userpass/ déjà présent" || echo "OK   montage userpass/ absent"
}

etape_cle_vex() {
  set +e
  local avant apres cle w rc pub vu
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
  vu=$(jq -r '.data | [.type, .exportable, .allow_plaintext_backup, .deletion_allowed, .latest_version, .supports_signing] | map(tostring) | join(",")' <<<"$cle")
  [ "$vu" = "$ATTENDU_CLE" ] && echo "OK   clé $CLE (type, exportable, sauvegarde en clair, suppression, version, signature) : $vu" \
    || ko "clé $CLE : $vu (attendu : $ATTENDU_CLE)"
  mkdir -p "$R"
  jq -j '.data.keys["1"].public_key' <<<"$cle" > "$PEM"
  if openssl pkey -pubin -in "$PEM" -noout 2>/dev/null; then
    pub=$(spki "$PEM")
    echo "     $(openssl pkey -pubin -in "$PEM" -noout -text | sed -n '1p;/NIST CURVE/p' | paste -sd ';' -)"
    echo "OK   clé publique exportée : ${PEM#"$here"/} (fichier sha256 $(sha256sum < "$PEM" | cut -c1-64) ; SPKI sha256 $pub)"
  else ko "clé publique illisible par openssl"; fi
  apres=$(cles) || { ko "liste des clés Transit illisible (après)"; return 1; }
  echo "après :"; sed 's/^/     /' <<<"$apres"
  [ "$(printf '%s\n%s\n' "$avant" "$CLE ecdsa-p256 1 false" | sed '/^$/d' | sort)" = "$apres" ] \
    && echo "OK   seule différence : transit/keys/$CLE ajoutée ; les autres clés Transit sont inchangées (type, version, exportable)" \
    || ko "clés Transit : différence autre que l'ajout de $CLE"
}

etape_acces_vex() { # MDP lu avant l'étape (hors du journal)
  set +e
  local pa pp ma mp cle vu lu w rc
  [ -n "$MDP" ] || { ko "mot de passe absent"; return 1; }
  etat_bao && echo "OK   OpenBao initialisé et descellé" || { ko "OpenBao scellé, non initialisé ou illisible"; return 1; }
  [ -f "$POL" ] || { ko "${POL#"$here"/} absent"; return 1; }
  cle=$(racine <<<"bao read -format=json transit/keys/$CLE")
  vu=$(jq -r '.data | [.type, .exportable, .allow_plaintext_backup, .deletion_allowed, .latest_version, .supports_signing] | map(tostring) | join(",")' <<<"$cle")
  [ "$vu" = "$ATTENDU_CLE" ] && echo "OK   clé $CLE présente et conforme : $vu" || { ko "clé $CLE : $vu (attendu : $ATTENDU_CLE ; étape cle_vex)"; return 1; }
  pa=$(politiques); ma=$(methodes)
  echo "avant : politiques $(paste -sd' ' <<<"$pa") ; méthodes (hors la méthode native) $(grep -v '^token/ ' <<<"$ma" | paste -sd';' -)"
  # refus d'abord, avant toute écriture
  if grep -q '^userpass/ ' <<<"$ma" && ! grep -qx 'userpass/ userpass' <<<"$ma"; then ko "montage userpass/ d'un autre type : aucune écriture"; return 1; fi
  if grep -qx 'userpass/ userpass' <<<"$ma" && util_present; then
    ko "utilisateur $UTIL déjà présent : aucune écriture (le mot de passe n'est jamais réécrit par ce script)"; return 1
  fi
  if grep -qx "$NOM_POL" <<<"$pa"; then
    lu=$(racine <<<"bao policy read $NOM_POL" | sans_commentaires)
    [ "$lu" = "$(sans_commentaires < "$POL")" ] || { ko "politique $NOM_POL présente et différente du fichier : aucune écriture"; return 1; }
    echo "OK   politique $NOM_POL déjà présente et identique au fichier : laissée"
  else
    echo "### écriture 1 : politique $NOM_POL"
    racine <<EOF 2>&1 | sed 's/^/     | /'
bao policy write $NOM_POL - <<'POL'
$(cat "$POL")
POL
EOF
  fi
  lu=$(racine <<<"bao policy read $NOM_POL" | sans_commentaires)
  [ "$lu" = "$(sans_commentaires < "$POL")" ] && echo "OK   politique $NOM_POL relue = ${POL#"$here"/} (hors commentaires et lignes vides : $lu)" \
    || { ko "politique $NOM_POL relue ($lu) différente du fichier ($(sans_commentaires < "$POL"))"; return 1; }
  if grep -qx 'userpass/ userpass' <<<"$ma"; then echo "OK   montage userpass/ déjà présent : laissé"
  else
    echo "### écriture 2 : montage userpass/"
    w=$(racine <<<'bao auth enable userpass' 2>&1); rc=$?
    sed 's/^/     | /' <<<"$w"
    [ "$rc" = 0 ] || { ko "bao auth enable userpass : code $rc"; return 1; }
  fi
  echo "### écriture 3 : utilisateur $UTIL (mot de passe sur l'entrée standard, sans saut de ligne)"
  w=$( { tr -d '\n' < "$S8/openbao-root.token"; echo; printf '%s' "$MDP"; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c "read -r BAO_TOKEN && export BAO_TOKEN && exec bao write auth/userpass/users/$UTIL \
password=- token_policies=$NOM_POL token_no_default_policy=true token_ttl=15m token_max_ttl=15m" 2>&1); rc=$?
  sed 's/^/     | /' <<<"$w"
  [ "$rc" = 0 ] && echo "OK   utilisateur $UTIL écrit : code 0" || { ko "écriture de l'utilisateur : code $rc"; return 1; }
  vu=$(util_vu)
  [ "$vu" = "$ATTENDU_UTIL" ] && echo "OK   utilisateur $UTIL (politiques, sans default, durée, durée maximale) : $vu" \
    || ko "utilisateur $UTIL : $vu (attendu : $ATTENDU_UTIL)"
  pp=$(politiques); mp=$(methodes)
  [ "$(printf '%s\n%s\n' "$pa" "$NOM_POL" | sed '/^$/d' | sort -u)" = "$pp" ] && echo "OK   politiques : seule $NOM_POL ajoutée (ou déjà là)" \
    || ko "politiques : différence autre que $NOM_POL"
  [ "$(printf '%s\n%s\n' "$ma" 'userpass/ userpass' | sed '/^$/d' | sort -u)" = "$mp" ] && echo "OK   méthodes d'authentification : seul userpass/ ajouté (ou déjà là)" \
    || ko "méthodes d'authentification : différence autre que userpass/"
  echo "clés Transit après : $(cles | paste -sd';' -)"
}

etape_essai() {
  set +e
  local c b64 s v obtenu attendu_l ko_essais=0 pol dur
  [ -f "$PEM" ] || { ko "${PEM#"$here"/} absent (étape cle_vex)"; return 1; }
  [ -f "$CA" ] || { ko "CA absente : $CA"; return 1; }
  [ "$(sha256sum < "$BAO" | cut -c1-64)" = "$BAO_SHA256" ] && echo "OK   bao de l'hôte : empreinte $BAO_SHA256 ($("$BAO" version | head -1))" \
    || { ko "bao de l'hôte : empreinte différente de $BAO_SHA256"; return 1; }
  (umask 077 && mkdir -p "$W/home")   # W : dossier neuf de ce lancement (mktemp), une connexion ratée n'empêche pas la relance
  trap fermer EXIT
  ouvrir || return 1
  echo "### connexion du propriétaire (userpass, -no-store)"
  if [ -n "${BANC:-}" ] && [ -n "${BANC_MDP_CONNEXION:-}" ]; then
    client "$BAO" login -method=userpass -no-store -format=json username="$UTIL" password=@"$BANC_MDP_CONNEXION" > "$W/connexion.json" 2> "$W/connexion.err"; c=$?
  else
    printf 'connexion à OpenBao (userpass, %s) : bao demande le mot de passe\n' "$UTIL" > /dev/tty
    ( umask 077
      VAULT_ADDR="https://127.0.0.1:$PORT" VAULT_CACERT="$CA" VAULT_TLS_SERVER_NAME="$NOM_TLS" BAO_ADDR="https://127.0.0.1:$PORT" \
        BAO_CACERT="$CA" BAO_TLS_SERVER_NAME="$NOM_TLS" HOME="$W/home" \
        "$BAO" login -method=userpass -no-store -format=json username="$UTIL" < /dev/tty > "$W/connexion.json" 2> /dev/tty ); c=$?
  fi
  chmod 600 "$W/connexion.json"
  (umask 077 && jq -j '.auth.client_token // empty' "$W/connexion.json" > "$JT" 2>/dev/null)
  pol=$(jq -r '.auth.policies | sort | join("+")' "$W/connexion.json" 2>/dev/null); dur=$(jq -r '.auth.lease_duration' "$W/connexion.json" 2>/dev/null)
  rm -f -- "$W/connexion.json"
  [ "$c" = 0 ] && [ -s "$JT" ] && echo "OK   connexion : code 0 ; politiques $pol ; durée $dur s ; secret dans un fichier $(stat -c %a "$JT") ; rien dans $W/home : $(find "$W/home" -type f | grep -c . || true) fichier(s)" \
    || { ko "connexion : code $c ; $(head -c 160 "$W/connexion.err" 2>/dev/null)"; return 1; }
  [ "$pol" = "$NOM_POL" ] && [ "$dur" = 900 ] && echo "OK   secret du propriétaire : $NOM_POL seule, 900 s" || ko "secret du propriétaire : $pol, $dur s (attendu : $NOM_POL, 900 s)"
  echo "### essais avec le secret du propriétaire"
  b64=$(printf '%s' "$ENTREE" | openssl dgst -sha256 -binary | base64 -w0)
  s=$(client "$BAO" write -field=signature transit/sign/$CLE/sha2-256 input="$b64" prehashed=true 2>&1); c=$?
  { essai "lecture de transit/keys/vex" "$BAO" read transit/keys/$CLE
    [ "$c" = 0 ] && echo "ACCEPTE|signature avec la clé vex" || echo "REFUSE|signature avec la clé vex|$(head -c 160 <<<"$s")"
    for k in chains scanner tsa lien; do essai "signature avec la clé $k" "$BAO" write transit/sign/$k/sha2-256 input="$b64" prehashed=true; done
    essai "lecture de transit/keys/chains" "$BAO" read transit/keys/chains
    essai "export de la clé vex" "$BAO" read transit/export/signing-key/$CLE
    essai "clé vex rendue exportable" "$BAO" write transit/keys/$CLE/config exportable=true
    essai "sauvegarde de la clé vex" "$BAO" read transit/backup/$CLE
    essai "lecture de kv/scan/zot" "$BAO" read kv/scan/zot
    essai "liste des politiques" "$BAO" policy list
    essai "création d'un secret enfant" "$BAO" token create -policy=$NOM_POL
    essai "consultation de soi" "$BAO" token lookup
  } > "$W/essais.txt"
  sed 's/^/     | /' "$W/essais.txt"
  obtenu=$(grep -E '^(ACCEPTE|REFUSE)\|' "$W/essais.txt" | cut -d'|' -f1-2 | awk -F'|' '{print $2 "|" $1}')
  while IFS= read -r attendu_l; do
    grep -qxF "$attendu_l" <<<"$obtenu" && echo "OK   essai ${attendu_l%|*} : ${attendu_l##*|}" || { ko "essai ${attendu_l%|*} : ${attendu_l##*|} attendu"; ko_essais=1; }
  done <<<"$ESSAIS_ATTENDUS"
  [ "$(grep -c . <<<"$obtenu")" = "$(grep -c . <<<"$ESSAIS_ATTENDUS")" ] || ko "nombre d'essais : $(grep -c . <<<"$obtenu") lignes ($(grep -c . <<<"$ESSAIS_ATTENDUS") attendues)"
  echo "### signature vérifiée sur l'hôte avec la clé publique archivée"
  printf '%s' "$ENTREE" > "$W/entree.txt"
  printf '%s' "${s##*:}" | base64 -d > "$W/signature.der" 2>/dev/null
  echo "     signature Transit : préfixe ${s%:*}, $(wc -c < "$W/signature.der") octets DER"
  v=$(openssl dgst -sha256 -verify "$PEM" -signature "$W/signature.der" "$W/entree.txt" 2>/dev/null)
  [ "$v" = "Verified OK" ] && echo "OK   openssl : signature de la clé vex vérifiée par ${PEM#"$here"/} (Verified OK)" || ko "openssl : $v"
  printf '%s' "autre $ENTREE" > "$W/autre.txt"
  v=$(openssl dgst -sha256 -verify "$PEM" -signature "$W/signature.der" "$W/autre.txt" 2>/dev/null)
  [ "$v" = "Verification failure" ] && echo "OK   témoin : même signature sur une autre entrée refusée (Verification failure)" || ko "témoin : $v"
  echo "### clé publique vue par cosign (client hashivault de signer-vex.sh)"
  c=0; client "$COSIGN" public-key --key hashivault://$CLE > "$W/cosign.pub" 2> "$W/cosign.err" || c=$?
  [ "$c" = 0 ] && [ "$(spki "$W/cosign.pub")" = "$(spki "$PEM")" ] \
    && echo "OK   cosign public-key --key hashivault://$CLE : code 0, SPKI égal à ${PEM#"$here"/} ($($COSIGN version 2>/dev/null | sed -n 's/^GitVersion: *//p'))" \
    || ko "cosign public-key : code $c ; SPKI $(spki "$W/cosign.pub" | cut -c1-16) (attendu $(spki "$PEM" | cut -c1-16)) ; $(head -c 160 "$W/cosign.err")"
  echo "### révocation de soi, puis signature refusée"
  c=0; client "$BAO" token revoke -self > /dev/null 2> "$W/revocation.err" || c=$?
  [ "$c" = 0 ] && echo "OK   révocation de soi : code 0" || ko "révocation de soi : code $c"
  v=$(essai "signature avec la clé vex après révocation" "$BAO" write transit/sign/$CLE/sha2-256 input="$b64" prehashed=true)
  [ "${v%%|*}" = REFUSE ] && echo "OK   signature avec la clé vex après révocation : REFUSE" || ko "signature après révocation : ${v%%|*}"
  fermer; trap - EXIT
  return $ko_essais
}

e=${1:-}
case "$e" in
  releve|cle_vex|acces_vex|essai)
    if [ "$e" = acces_vex ]; then
      set +e
      lire_mdp || exit 1
      set -e
    fi
    if [ "$e" = essai ]; then
      if [ -n "${BANC:-}" ]; then COSIGN=$BANC/bin/cosign; else COSIGN=$(cd "$TOP" && mise which cosign); fi
      if { [ -z "${BANC:-}" ] || [ -z "${BANC_MDP_CONNEXION:-}" ]; } && ! (: < /dev/tty) 2>/dev/null; then
        echo "REFUS : /dev/tty illisible : essai se lance dans le terminal du propriétaire, pas depuis une session sans terminal"; exit 1
      fi
      mkdir -p "$W"
      W=$(umask 077 && mktemp -d "$W/essai-$(date -u +%Y%m%dT%H%M%SZ)-XXXX"); JT=$W/secret
    fi
    mkdir -p "$R"
    L=$R/vex-openbao-$e.log
    set +e
    # Journal écrit d'abord sans affichage (0600), contrôlé par K3 à K6, puis seulement affiché : une valeur secrète n'atteint
    # jamais la sortie standard (calque d'o5-openbao.sh).
    (umask 077 && : > "$L")
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; vex-openbao.sh $(sha256sum < "$here/vex-openbao.sh" | cut -c1-16)…${BANC:+ ; BANC}"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer >> "$L"; rc=${PIPESTATUS[0]}
    vider() { : > "$L"; echo "$1" > "$L"; chmod 644 "$L"; cat "$L"; MDP=; [ -e "$JT" ] && rm -f -- "$JT"; exit 1; }
    n=$(grep -c -E -e '-----BEGIN (PGP|[A-Z ]*PRIVATE)' "$L" || true)
    [ "$n" = 0 ] || vider "KO   K3 : $n ligne(s) de bloc privé dans le journal : journal vidé"
    echo "OK   K3 : aucune ligne de bloc privé dans le journal" >> "$L"
    n=$(tr -d '\n' < "$S8/openbao-root.token" | grep -c -F -f - "$L" || true)   # valeur lue par le script, jamais affichée
    [ "$n" = 0 ] || vider "KO   K4 : valeur du jeton root dans le journal : journal vidé"
    echo "OK   K4 : valeur du jeton root absente du journal" >> "$L"
    [ -e "$JT" ] && [ ! -s "$JT" ] && rm -f -- "$JT"   # connexion ratée : fichier vide
    if [ -s "$JT" ]; then
      n=$(tr -d '\n' < "$JT" | grep -c -F -f - "$L" || true)
      [ "$n" = 0 ] || vider "KO   K5 : valeur du secret du propriétaire dans le journal : journal vidé"
      echo "OK   K5 : valeur du secret du propriétaire absente du journal" >> "$L"
      rm -f -- "$JT"
      [ ! -e "$JT" ] && echo "OK   fichier du secret du propriétaire effacé" >> "$L" || echo "KO   fichier du secret du propriétaire toujours présent" >> "$L"
    fi
    if [ -n "$MDP" ]; then
      n=$(printf '%s' "$MDP" | grep -c -F -f - "$L" || true)
      [ "$n" = 0 ] || vider "KO   K6 : valeur du mot de passe dans le journal : journal vidé"
      echo "OK   K6 : valeur du mot de passe absente du journal" >> "$L"
      MDP=
    fi
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" >> "$L"; rc=1; }
    chmod 644 "$L"; cat "$L"
    exit "$rc" ;;
  *) echo "usage : $0 releve | cle_vex | acces_vex | essai" >&2; exit 64 ;;
esac
