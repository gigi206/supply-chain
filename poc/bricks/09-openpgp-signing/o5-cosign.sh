#!/usr/bin/env bash
# Brique 09, O5 réel, accord du propriétaire (« Ok », 19/11/2026) : redirection de port locale vers OpenBao, pour que cosign
# signe avec la clé Transit « lien » (client hashivault). Redirection sur 127.0.0.1 seulement, vers openbao-0:8200, ouverte le
# temps de l'étape et fermée à la sortie (trap). Le client reçoit VAULT_ADDR, VAULT_CACERT (CA du PoC), VAULT_TLS_SERVER_NAME
# (seul nom du certificat d'OpenBao) et VAULT_TOKEN, lu dans 09/secrets/openbao-lien.secret par un sous-shell et exporté :
# jamais en argument, jamais affiché.
#   cle    lecture seule : cosign public-key --key hashivault://lien, comparée (SPKI) à resultats/lien-cle-publique.pem
#   essai  signature d'essai : cosign attest-blob --key hashivault://lien d'un énoncé d'essai (type …/lien-openpgp/essai), sans
#          journal de transparence (drapeaux du banc d'O5, mesurés hors réseau) ; bundle vérifié ensuite SANS réseau (unshare -n)
#          avec la clé publique archivée ; témoin : même bundle sur une autre entrée refusé. Rien n'est écrit dans Zot.
# Banc : BANC=<dossier> remplace kubectl et cosign par ceux du banc (o5-cosign-banc.sh) ; journal dans ce dossier.
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o5-cosign.sh <étape>   (journal : resultats/o5-cosign-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$here" rev-parse --show-toplevel)
R=$here/resultats
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
S9=$HOME/.cache/supply-chain-poc/09/secrets
W=$HOME/.cache/supply-chain-poc/09/o5-cosign
COSIGN=$(cd "$TOP" && mise which cosign)
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
if [ -n "${BANC:-}" ]; then R=$BANC/resultats; S9=$BANC/secrets9; W=$BANC/travail; COSIGN=$BANC/bin/cosign; export PATH=$BANC/bin:$PATH; fi
JL=$S9/openbao-lien.secret
PEM=$R/lien-cle-publique.pem   # après BANC (banc : la clé jetable du banc, pas la clé lien)
NOM_TLS=openbao.openbao.svc.cluster.local
TYPE_ESSAI=https://supply-chain.example/lien-openpgp/essai
PF=; PORT=

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; }
spki() { openssl pkey -pubin -in "$1" -outform DER 2>/dev/null | sha256sum | cut -c1-64; }
ouvrir() { # redirection 127.0.0.1:<port libre> → openbao-0:8200 ; PORT et PF
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
  elif (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then ko "redirection fermée mais 127.0.0.1:$PORT répond encore"
  else echo "OK   redirection fermée : processus $PF arrêté, 127.0.0.1:$PORT n'écoute plus"; fi
  PF=
}
avec_bao() { # commande… : exécutée avec l'environnement du client hashivault ; VAULT_TOKEN lu et exporté dans le sous-shell
  ( VAULT_TOKEN=$(cat "$JL"); export VAULT_TOKEN
    export VAULT_ADDR="https://127.0.0.1:$PORT" VAULT_CACERT="$CA" VAULT_TLS_SERVER_NAME="$NOM_TLS"
    exec "$@" < /dev/null )
}
gardes() { # aussi : la redirection est fermée à la sortie du sous-shell de l'étape, quoi qu'il arrive
  trap fermer EXIT
  [ -s "$JL" ] && echo "OK   secret lien présent dans 09/secrets (non lu par la session)" || { ko "secret lien absent"; return 1; }
  [ -f "$PEM" ] && echo "OK   clé publique archivée : SPKI sha256 $(spki "$PEM")" || { ko "${PEM#"$here"/} absent"; return 1; }
  [ -f "$CA" ] || { ko "CA du PoC absente"; return 1; }
  [ ! -e "$W" ] || { ko "$W existe déjà : rien n'est réutilisé"; return 1; }
  mkdir -p "$W"
  echo "     cosign $("$COSIGN" version 2>&1 | sed -n 's/^GitVersion: *//p') ; kubectl $(kubectl version --client 2>/dev/null | sed -n 's/^Client Version: *//p')"
}

etape_cle() {
  set +e
  local s
  gardes || return 1
  ouvrir || return 1
  avec_bao "$COSIGN" public-key --key hashivault://lien > "$W/cle.pem" 2> "$W/cle.err"; s=$?
  fermer
  [ "$s" = 0 ] && echo "OK   cosign public-key --key hashivault://lien : code 0" \
    || { ko "cosign public-key : code $s, $(grep -m1 -E 'Error|error' "$W/cle.err" | cut -c1-200)"; return 1; }
  [ "$(spki "$W/cle.pem")" = "$(spki "$PEM")" ] && echo "OK   clé lue par cosign dans OpenBao = clé publique archivée (SPKI $(spki "$PEM"))" \
    || ko "clé lue par cosign ($(spki "$W/cle.pem")) différente de la clé archivée"
  echo "à effacer après archivage (chemin littéral) : $W"
}

etape_essai() {
  set +e
  local s v
  gardes || return 1
  printf '%s' "brique 09, O5 : entrée d'essai signée par hashivault://lien" > "$W/entree.txt"
  printf '{"essai":"brique 09, O5 : signature d essai par la clé Transit lien, sans journal de transparence"}\n' > "$W/predicat.json"
  ouvrir || return 1
  avec_bao "$COSIGN" attest-blob --key hashivault://lien --type "$TYPE_ESSAI" --predicate "$W/predicat.json" --bundle "$W/essai.bundle" \
    --new-bundle-format --use-signing-config=false --tlog-upload=false --yes "$W/entree.txt" > "$W/essai.out" 2>&1; s=$?
  fermer
  [ "$s" = 0 ] && echo "OK   cosign attest-blob --key hashivault://lien : code 0" \
    || { ko "attest-blob : code $s, $(grep -m1 -E 'Error|error' "$W/essai.out" | cut -c1-200)"; return 1; }
  echo "     bundle : $(python3 -I -c 'import json,sys; b=json.load(open(sys.argv[1])); print(b.get("mediaType"), "; clés :", ", ".join(sorted(b)), "; verificationMaterial :", ", ".join(sorted(b.get("verificationMaterial", {}))))' "$W/essai.bundle")"
  v=$(unshare --map-auto --map-root-user -n env -i PATH=/usr/bin:/bin HOME="$W" LC_ALL=C "$COSIGN" verify-blob-attestation --bundle "$W/essai.bundle" \
    --new-bundle-format --key "$PEM" --insecure-ignore-tlog --type "$TYPE_ESSAI" "$W/entree.txt" 2>&1)
  grep -q '^Verified OK' <<<"$v" && echo "OK   vérification hors réseau avec la clé publique archivée : Verified OK" || ko "vérification : $(tail -1 <<<"$v" | cut -c1-200)"
  printf '%s' "autre" > "$W/autre.txt"
  v=$(unshare --map-auto --map-root-user -n env -i PATH=/usr/bin:/bin HOME="$W" LC_ALL=C "$COSIGN" verify-blob-attestation --bundle "$W/essai.bundle" \
    --new-bundle-format --key "$PEM" --insecure-ignore-tlog --type "$TYPE_ESSAI" "$W/autre.txt" 2>&1)
  grep -q -E '^Error: .*digest' <<<"$v" && echo "OK   témoin : même bundle sur une autre entrée refusé ($(grep -m1 '^Error' <<<"$v" | cut -c1-140))" \
    || ko "témoin : $(tail -1 <<<"$v" | cut -c1-200)"
  echo "à effacer après archivage (chemin littéral) : $W"
}

e=${1:-}
case "$e" in
  cle|essai)
    mkdir -p "$R"
    L=$R/o5-cosign-$e.log
    set +e
    (umask 077 && : > "$L")
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-cosign.sh $(sha256sum < "$here/o5-cosign.sh" | cut -c1-16)…${BANC:+ ; BANC}"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer >> "$L"; rc=${PIPESTATUS[0]}
    n=$(grep -c -E -e '-----BEGIN [A-Z ]*PRIVATE' "$L" || true)
    [ "$n" = 0 ] || { : > "$L"; echo "KO   K3 : bloc privé dans le journal : journal vidé" > "$L"; chmod 644 "$L"; cat "$L"; exit 1; }
    echo "OK   K3 : aucune ligne de bloc privé dans le journal" >> "$L"
    if [ -s "$JL" ]; then
      n=$(tr -d '\n' < "$JL" | grep -c -F -f - "$L" || true)
      m=$(tr -d '\n' < "$JL" | grep -r -l -F -f - "$W" 2>/dev/null | grep -c . || true)
      [ "$n" = 0 ] && [ "$m" = 0 ] || { : > "$L"; echo "KO   K5 : valeur du secret lien dans le journal ou le dossier de travail : journal vidé" > "$L"; chmod 644 "$L"; cat "$L"; exit 1; }
      echo "OK   K5 : valeur du secret lien absente du journal et du dossier de travail" >> "$L"
    fi
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" >> "$L"; rc=1; }
    chmod 644 "$L"; cat "$L"
    exit "$rc" ;;
  *) echo "usage : $0 cle | essai" >&2; exit 64 ;;
esac
