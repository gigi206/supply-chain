#!/usr/bin/env bash
# Brique 09, O5 réel : publication dans signes/** (compte poc-lien, décision « Oui, signes/** » du 19/11/2026) et attestations de
# lien signées par la clé Transit « lien » (cosign hashivault://lien par la redirection de port, accord « Ok » du 19/11/2026).
# Tout ce qui est écrit dans signes/** reste : poc-lien ne peut rien supprimer. Les inconnues de cosign attest sont donc mesurées
# d'abord avec une clé jetable dans signes/essai-09-*, et la clé lien ne signe rien de faux.
#   construire   hors réseau : trois layouts OCI déterministes (rpm signé, dépôt rpm, dépôt apt), contrôlés par o5-signes.py ;
#                digests écrits dans le journal (prédictions de publier)
#   essai_attest clé cosign jetable, dépôts signes/essai-09-attest, -autre, -altere : relève ce que fait cosign attest sous
#                poc-lien (referrer, tags, _type, forme de la sortie de verify-attestation) ; témoins faux refusés par le contrôle
#   publier      poc-lien, par digest : signes/sample-app-rpm, signes/sample-app-deb (copie du manifeste non signé 60f25f5c…, tirée
#                et contrôlée hors réseau d'abord), signes/depot-rpm, signes/depot-apt ; relu en anonyme ; objet déjà présent : non
#                repoussé
#   attester     clé lien : provenance de Chains revérifiée, prédicats passés au contrôle AVANT signature (tout ou rien), aucun
#                referrer de type lien déjà présent (pas de doublon définitif), puis cosign attest par la redirection, fermée après
#   verifier     anonyme, sans secret ni redirection : cosign verify-attestation (clé publique archivée), une seule attestation de
#                lien par objet, contrôle indépendant sur les octets tirés de Zot, témoin clé jetable refusé ; énoncés archivés
# Écritures dans Zot (essai_attest, publier, attester) refusées de 23:30 à 08:00 UTC : la mesure de M1b part à 00:01 UTC et lit Zot.
# Banc : BANC=<dossier> remplace oras, cosign, curl et kubectl par ceux du banc (o5-signes-banc.sh), qui simulent Zot et OpenBao.
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o5-signes.sh <étape>   (journal : resultats/o5-signes-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$here" rev-parse --show-toplevel)
R=$here/resultats
PY=$here/o5-signes.py
CTL=$here/o5-zot-controle.py
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
REG_HOTE=192.168.161.13:5000
CLE_CHAINS=$TOP/poc/bricks/08-trust-plane/resultats/chains-cle-publique.pem
S9=$HOME/.cache/supply-chain-poc/09/secrets
W=$HOME/.cache/supply-chain-poc/09/o5-signes
ORAS=$(cd "$TOP" && mise which oras)
COSIGN=$(cd "$TOP" && mise which cosign)
CURL=curl
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
if [ -n "${BANC:-}" ]; then
  R=$BANC/resultats; S9=$BANC/secrets9; W=$BANC/travail; ORAS=$BANC/bin/oras; COSIGN=$BANC/bin/cosign; CURL=$BANC/bin/curl
  export PATH=$BANC/bin:$PATH
else
  unset HEURE_BANC
  [ -z "${O5_SIGNES_ATTENDUS:-}" ] || { echo "KO   O5_SIGNES_ATTENDUS est réservé au banc" >&2; exit 64; }
fi
C=$W/construire
JL=$S9/openbao-lien.secret
MDP=$S9/zot-poc-lien.password
DCFG=$S9/zot-poc-lien-docker
PEM=$R/lien-cle-publique.pem
NOM_TLS=openbao.openbao.svc.cluster.local
TYPE=https://supply-chain.example/lien-openpgp/v1
FIN_LIEN=2026-11-22T19:40:00Z   # le secret lien expire au plus tard le 22/11/2026 à 19:49:36 UTC (o5-openbao-acces_lien.log)
RPM=sample-app-1.0.0-2.el9.x86_64.rpm
DEB=sample-app_1.0.0-2_amd64.deb
CAS=(rpm deb depot-rpm depot-apt)
declare -A DEPOT=([rpm]=signes/sample-app-rpm [deb]=signes/sample-app-deb [depot-rpm]=signes/depot-rpm [depot-apt]=signes/depot-apt)
declare -A ORIG=([rpm]=rpm [deb]=deb [depot-rpm]=rpm [depot-apt]=deb)
PF=; PORT=; d=

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; }
spki() { openssl pkey -pubin -in "$1" -outform DER 2>/dev/null | sha256sum | cut -c1-64; }
anonyme() { env DOCKER_CONFIG="$W/docker-vide" "$@" < /dev/null; }
valeur() { sed -n "s/^     $1 : //p" "$d/attendus.txt"; }
erreur() { grep -m1 -i -E '^Error|error|denied|unauthorized|not found' "$1" | cut -c1-200; }

# --- gardes ------------------------------------------------------------------------------------------------------------------
dossier() { # étape : dossier de travail neuf, valeurs archivées relues
  d=$W/$1
  [ ! -e "$d" ] || { ko "$d existe déjà : rien n'est réutilisé"; return 1; }
  mkdir -p "$d" "$W/docker-vide"
  python3 -I "$PY" attendus > "$d/attendus.txt" 2>&1 && echo "OK   valeurs archivées relues (o5-signes.py attendus)$(grep -q '^BANC' "$d/attendus.txt" && echo ' ; BANC : valeurs remplacées')" \
    || { ko "valeurs archivées : $(tail -1 "$d/attendus.txt")"; return 1; }
}
fenetre() { # écritures dans Zot refusées de 23:30 à 08:00 UTC (mesure de M1b)
  local h; h=${HEURE_BANC:-$(date -u +%H%M)}
  if [ "$((10#$h))" -ge 2330 ] || [ "$((10#$h))" -lt 800 ]; then ko "écriture dans Zot refusée entre 23:30 et 08:00 UTC (mesure de M1b) : heure ${h:0:2}:${h:2} UTC"; return 1; fi
  echo "OK   heure ${h:0:2}:${h:2} UTC : hors de la fenêtre 23:30-08:00 UTC"
}
construits() { # digests du journal archivé de construire, égaux au fichier digests du dossier ; DG[cas]
  local c j k
  declare -gA DG=()
  [ -s "$R/o5-signes-construire.log" ] && [ -s "$C/digests" ] || { ko "construire non passée (journal ou dossier absent)"; return 1; }
  for c in rpm depot-rpm depot-apt; do
    j=$(sed -n -E "s/^OK   $c : layout (sha256:[0-9a-f]{64}) \(.*/\1/p" "$R/o5-signes-construire.log")
    k=$(sed -n "s/^$c //p" "$C/digests")
    [ -n "$j" ] && [ "$(grep -c . <<<"$j")" = 1 ] && [ "$j" = "$k" ] || { ko "$c : digest du journal (${j:-absent}) ≠ dossier (${k:-absent})"; return 1; }
    DG[$c]=$j
  done
  DG[deb]=$(valeur deb_manifeste)
  echo "OK   digests de construire (journal archivé = dossier) : rpm ${DG[rpm]:7:12}…, depot-rpm ${DG[depot-rpm]:7:12}…, depot-apt ${DG[depot-apt]:7:12}… ; deb = manifeste non signé ${DG[deb]:7:12}…"
}
poc_lien() { [ -s "$DCFG/config.json" ] && echo "OK   configuration de registre de poc-lien présente (mode $(stat -c %a "$DCFG/config.json"), non lue par la session)" || { ko "configuration de poc-lien absente (droits_zot)"; return 1; }; }

# --- Zot -----------------------------------------------------------------------------------------------------------------------
tirer() { # dépôt digest dossier : oras cp anonyme par digest vers un layout neuf
  anonyme "$ORAS" cp --no-tty --from-ca-file "$CA" "$REG_HOTE/$1@$2" --to-oci-layout "$3:a" > "$3.out" 2>&1 \
    && echo "OK   tiré en anonyme : $1@${2:0:19}…" || { ko "oras cp $1@${2:0:19}… : $(erreur "$3.out")"; return 1; }
}
non_signes() { # tire et contrôle hors réseau les deux images non signées de builds/** ; $d/ns-rpm et $d/ns-deb
  local a n
  for a in rpm deb; do
    [ "$a" = rpm ] && n=$RPM || n=$DEB
    tirer "builds/sample-app-$a" "$(valeur ${a}_manifeste)" "$d/ns-$a" || return 1
    python3 -I "$CTL" layout "$d/ns-$a" "$(valeur ${a}_manifeste)" "$n" "$(valeur ${a}_fichier)" > "$d/ns-$a.controle" 2>&1 \
      && echo "OK   builds/sample-app-$a : layout contrôlé (o5-zot-controle.py), un seul fichier de sha256 archivé" \
      || { ko "builds/sample-app-$a : $(grep -m1 -E '^(REFUS|KO)' "$d/ns-$a.controle")"; return 1; }
  done
}
present() { [ "$(anonyme "$ORAS" manifest fetch --descriptor --ca-file "$CA" "$REG_HOTE/$1@$2" 2>/dev/null | jq -r .digest 2>/dev/null)" = "$2" ]; }
tags() { anonyme "$ORAS" repo tags --ca-file "$CA" "$REG_HOTE/$1" 2>/dev/null | paste -sd' ' -; }
referrers() { # dépôt digest : « n_lien n_total types » des referrers relus en anonyme
  "$CURL" -fsS --cacert "$CA" "https://$REG_HOTE/v2/$1/referrers/$2" 2>/dev/null | jq -r --arg t "$TYPE" \
    '[([.manifests[]? | select(.annotations["dev.sigstore.bundle.predicateType"] == $t)] | length), (.manifests | length),
      ([.manifests[]? | "\(.artifactType)(\(.annotations["dev.sigstore.bundle.predicateType"] // "-"))"] | join(","))] | map(tostring) | join(" ")' 2>/dev/null \
    || echo "erreur"
}
pousser() { # layout digest dépôt : poc-lien, par digest
  "$ORAS" cp --no-tty --to-registry-config "$DCFG/config.json" --to-ca-file "$CA" --from-oci-layout "$1@$2" "$REG_HOTE/$3@$2" < /dev/null > "$d/pousser.out" 2>&1 \
    && echo "OK   poussé par poc-lien : $3@${2:0:19}…" || { ko "poussée $3@${2:0:19}… : $(erreur "$d/pousser.out")"; return 1; }
}
chains() { # provenance de Chains des deux manifestes non signés, vérifiée en anonyme ; $d/chains.json
  local a m
  m=$(sed -n -E 's/^OK   clé publique de Chains \(sha256\) : ([0-9a-f]{64})$/\1/p' "$TOP/poc/bricks/05-rpm-mock/resultats/m4c-provenance.log")
  [ "$(sha256sum < "$CLE_CHAINS" | cut -c1-64)" = "$m" ] && echo "OK   clé publique de Chains : sha256 ${m:0:16}…, égal à m4c-provenance.log (05)" || { ko "clé publique de Chains"; return 1; }
  for a in rpm deb; do
    anonyme "$COSIGN" verify-attestation --key "$CLE_CHAINS" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$CA" \
      "$REG_HOTE/builds/sample-app-$a@$(valeur ${a}_manifeste)" > "$d/chains-$a.jsonl" 2> "$d/chains-$a.err" \
      || { ko "provenance de Chains ($a) : $(erreur "$d/chains-$a.err")"; return 1; }
    python3 -I "$CTL" enveloppes "$d/chains-$a.jsonl" "$(valeur ${a}_manifeste)" > "$d/chains-$a.controle" 2>&1 \
      && echo "OK   provenance de Chains de builds/sample-app-$a : $(grep -c . "$d/chains-$a.jsonl") enveloppe(s), SLSA v1, sujet = manifeste non signé" \
      || { ko "enveloppes de Chains ($a) : $(grep -m1 -E '^(REFUS|KO)' "$d/chains-$a.controle")"; return 1; }
  done
  python3 -I - "$d" "$m" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" <<'PY'
import json, os, sys
d, cle, date = sys.argv[1:4]
r = {a: {"cle": cle, "date": date, "enveloppes": sum(1 for l in open(os.path.join(d, f"chains-{a}.jsonl")) if l.strip())} for a in ("rpm", "deb")}
json.dump(r, open(os.path.join(d, "chains.json"), "w"), sort_keys=True)
PY
}
signe_local() { # cas : layout signé en main pour le contrôle (construire, ou la copie tirée pour le deb)
  [ "$1" = deb ] && echo "$d/ns-deb" || echo "$C/$1"
}
precontrole() { # cas prédicat : le prédicat passe le contrôle indépendant avant toute signature (enveloppe non signée locale)
  python3 -I "$PY" enonce "$1" "$2" "${DG[$1]}" > "$d/local-$1.jsonl" \
    && python3 -I "$PY" controle "$1" "$d/local-$1.jsonl" "${DG[$1]}" "$(signe_local "$1")" "$d/ns-${ORIG[$1]}" > "$d/local-$1.controle" 2>&1
  if tail -1 "$d/local-$1.controle" | grep -qx ACCEPTÉ; then echo "OK   prédicat $1 : contrôle indépendant ACCEPTÉ avant signature"
  else ko "prédicat $1 : $(grep -m1 -E '^(REFUS|KO)' "$d/local-$1.controle")"; return 1; fi
}
verifier_att() { # libellé clé dépôt digest sortie : cosign verify-attestation anonyme du type lien ; code de cosign
  anonyme "$COSIGN" verify-attestation --key "$2" --type "$TYPE" --insecure-ignore-tlog=true --new-bundle-format --registry-cacert "$CA" \
    "$REG_HOTE/$3@$4" > "$5" 2> "$5.err"
}
juger() { # libellé attendu(ACCEPTÉ|REFUS) cas enveloppes digest signé non_signé : contrôle indépendant
  python3 -I "$PY" controle "$3" "$4" "$5" "$6" "$7" > "$4.controle" 2>&1
  local v; v=$(tail -1 "$4.controle")
  case "$2:$v" in
    ACCEPTÉ:ACCEPTÉ) echo "OK   $1 : contrôle indépendant ACCEPTÉ ($(grep -c '^OK' "$4.controle") contrôles OK)" ;;
    REFUS:REFUS*) echo "OK   $1 : contrôle indépendant refuse ($(cut -c7-180 <<<"$v"))" ;;
    *) ko "$1 : contrôle indépendant $(cut -c1-180 <<<"$v") (attendu $2)" ;;
  esac
}

# --- redirection vers OpenBao (comme o5-cosign.sh) --------------------------------------------------------------------------------
ouvrir() {
  local _
  kubectl port-forward -n openbao pod/openbao-0 --address 127.0.0.1 :8200 > "$d/redirection.log" 2>&1 &
  PF=$!
  for _ in $(seq 1 75); do
    PORT=$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) -> 8200$/\1/p' "$d/redirection.log" | head -1)
    [ -n "$PORT" ] && break
    kill -0 "$PF" 2>/dev/null || break
    sleep 0.2
  done
  [ -n "$PORT" ] && echo "OK   redirection ouverte : 127.0.0.1:$PORT → openbao-0:8200 (processus $PF)" \
    || { ko "redirection non ouverte : $(head -1 "$d/redirection.log" | cut -c1-160)"; kill "$PF" 2>/dev/null; wait "$PF" 2>/dev/null; PF=; return 1; }
}
fermer() {
  [ -n "$PF" ] || return 0
  kill "$PF" 2>/dev/null; wait "$PF" 2>/dev/null
  if kill -0 "$PF" 2>/dev/null; then ko "redirection : processus $PF toujours vivant"
  elif (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then ko "redirection fermée mais 127.0.0.1:$PORT répond encore"
  else echo "OK   redirection fermée : processus $PF arrêté, 127.0.0.1:$PORT n'écoute plus"; fi
  PF=
}
avec_bao() { # commande… : environnement du client hashivault ; VAULT_TOKEN lu et exporté dans le sous-shell, jamais en argument
  ( VAULT_TOKEN=$(cat "$JL"); export VAULT_TOKEN
    export VAULT_ADDR="https://127.0.0.1:$PORT" VAULT_CACERT="$CA" VAULT_TLS_SERVER_NAME="$NOM_TLS"
    exec "$@" < /dev/null )
}

# --- étapes --------------------------------------------------------------------------------------------------------------------
etape_construire() {
  set +e
  [ ! -e "$C" ] || { ko "$C existe déjà : rien n'est réutilisé"; return 1; }
  mkdir -p "$W"
  python3 -I "$PY" construire "$C" || { ko "construire refusée"; return 1; }
  mkdir -p "$W/construire-bis"
  python3 -I "$PY" construire "$W/construire-bis" > "$W/construire-bis.out" 2>&1
  cmp -s "$C/digests" "$W/construire-bis/digests" && echo "OK   seconde construction indépendante : mêmes digests (layouts déterministes)" \
    || ko "seconde construction : digests différents"
  echo "     dossier gardé pour publier et attester (à effacer après verifier) : $C ; à effacer après archivage (chemin littéral) : $W/construire-bis"
}

etape_essai_attest() {
  set +e
  local x alt v k
  dossier essai_attest && fenetre && construits && poc_lien || return 1
  mkdir -p "$d/cle"
  (cd "$d/cle" && unshare --map-auto --map-root-user -n env -i PATH=/usr/bin:/bin HOME="$d/cle" COSIGN_PASSWORD= "$COSIGN" generate-key-pair --output-key-prefix jetable > /dev/null 2>&1)
  [ -s "$d/cle/jetable.pub" ] && echo "OK   clé cosign jetable (hors réseau, sans phrase de passe)" || { ko "clé jetable"; return 1; }
  non_signes && chains || return 1
  python3 -I "$PY" predicats "$C" "$d/chains.json" "$d/p" && python3 -I "$PY" temoins "$C" "$d/p" || { ko "prédicats"; return 1; }
  precontrole rpm "$d/p/rpm.json" || return 1
  alt=$(cat "$d/p/rpm-altere.digest")
  echo "### poussées (poc-lien) et attestations par la clé jetable"
  pousser "$C/rpm" "${DG[rpm]}" signes/essai-09-attest && pousser "$C/rpm" "${DG[rpm]}" signes/essai-09-autre \
    && pousser "$d/p/rpm-altere" "$alt" signes/essai-09-altere || return 1
  for x in "attest ${DG[rpm]} rpm" "autre ${DG[rpm]} rpm-autre-manifeste" "altere $alt rpm"; do
    set -- $x
    env DOCKER_CONFIG="$DCFG" COSIGN_PASSWORD= "$COSIGN" attest --key "$d/cle/jetable.key" --type "$TYPE" --predicate "$d/p/$3.json" \
      --new-bundle-format --use-signing-config=false --tlog-upload=false --yes --registry-cacert "$CA" "$REG_HOTE/signes/essai-09-$1@$2" \
      < /dev/null > "$d/attest-$1.out" 2>&1 && echo "OK   cosign attest (clé jetable) signes/essai-09-$1@${2:0:19}… : code 0" \
      || { ko "cosign attest $1 : $(erreur "$d/attest-$1.out")"; continue; }
    echo "     referrers (lien, total, types) : $(referrers "signes/essai-09-$1" "$2") ; tags : $(tags "signes/essai-09-$1" | sed 's/^$/aucun/')"
  done
  echo "### relevés sur signes/essai-09-attest"
  verifier_att jetable "$d/cle/jetable.pub" signes/essai-09-attest "${DG[rpm]}" "$d/v-attest.jsonl"; k=$?
  echo "     cosign verify-attestation --new-bundle-format (clé jetable) : code $k, $(grep -c . "$d/v-attest.jsonl") ligne(s)"
  python3 -I - "$d/v-attest.jsonl" <<'PY'
import base64, json, sys
for i, l in enumerate(x for x in open(sys.argv[1]) if x.strip()):
    o = json.loads(l); e = o.get("dsseEnvelope", o); s = json.loads(base64.b64decode(e["payload"]))
    print(f"     ligne {i + 1} : clés {sorted(o)} ; _type {s.get('_type')} ; predicateType {s.get('predicateType')} ;"
          f" sujet {[ (x.get('name'), sorted(x.get('digest', {}))) for x in s.get('subject', []) ]}")
PY
  echo "### contrôle indépendant sur les octets tirés de Zot"
  tirer signes/essai-09-attest "${DG[rpm]}" "$d/s-attest" && juger "essai-09-attest (prédicat réel)" ACCEPTÉ rpm "$d/v-attest.jsonl" "${DG[rpm]}" "$d/s-attest" "$d/ns-rpm"
  verifier_att jetable "$d/cle/jetable.pub" signes/essai-09-autre "${DG[rpm]}" "$d/v-autre.jsonl" || ko "verify-attestation essai-09-autre : $(erreur "$d/v-autre.jsonl.err")"
  tirer signes/essai-09-autre "${DG[rpm]}" "$d/s-autre" && juger "témoin autre manifeste non signé" REFUS rpm "$d/v-autre.jsonl" "${DG[rpm]}" "$d/s-autre" "$d/ns-rpm"
  verifier_att jetable "$d/cle/jetable.pub" signes/essai-09-altere "$alt" "$d/v-altere.jsonl" || ko "verify-attestation essai-09-altere : $(erreur "$d/v-altere.jsonl.err")"
  tirer signes/essai-09-altere "$alt" "$d/s-altere" && juger "témoin rpm à charge altérée" REFUS rpm "$d/v-altere.jsonl" "$alt" "$d/s-altere" "$d/ns-rpm"
  if verifier_att lien "$PEM" signes/essai-09-attest "${DG[rpm]}" "$d/v-lien.jsonl"; then ko "attestation jetable acceptée avec la clé lien"
  else echo "OK   clé lien : l'attestation de la clé jetable est refusée ($(erreur "$d/v-lien.jsonl.err"))"; fi
  echo "     objets laissés dans Zot (poc-lien ne peut rien supprimer) : signes/essai-09-{attest,autre}@${DG[rpm]:0:19}…, signes/essai-09-altere@${alt:0:19}…, et leurs referrers"
  echo "à effacer après archivage (chemin littéral) : $d"
}

etape_publier() {
  set +e
  local c src
  dossier publier && fenetre && construits && poc_lien || return 1
  non_signes || return 1
  for c in "${CAS[@]}"; do
    [ "$c" = deb ] && src=$d/ns-deb || src=$C/$c
    if present "${DEPOT[$c]}" "${DG[$c]}"; then echo "OK   ${DEPOT[$c]}@${DG[$c]:0:19}… déjà présent : non repoussé"
    else pousser "$src" "${DG[$c]}" "${DEPOT[$c]}" || continue; fi
    present "${DEPOT[$c]}" "${DG[$c]}" && echo "OK   relu en anonyme : ${DEPOT[$c]}@${DG[$c]}" || ko "${DEPOT[$c]} : manifeste non relu en anonyme"
    v=$(tags "${DEPOT[$c]}"); [ -z "$v" ] && echo "OK   ${DEPOT[$c]} : aucun tag" || ko "${DEPOT[$c]} : tags $v"
  done
  echo "à effacer après archivage (chemin littéral) : $d"
}

etape_attester() {
  set +e
  local c n s ok=()
  dossier attester && fenetre && construits && poc_lien || return 1
  [ "$(date -u +%s)" -lt "$(date -u -d "$FIN_LIEN" +%s)" ] && echo "OK   avant $FIN_LIEN (fin du secret lien, 22/11 19:49:36 UTC, moins une marge)" || { ko "secret lien trop proche de sa fin"; return 1; }
  [ -s "$JL" ] && echo "OK   secret lien présent dans 09/secrets (non lu par la session)" || { ko "secret lien absent"; return 1; }
  [ "$(spki "$PEM")" = 42529342ceb102ad76f45285b2655d38265eebbe0c956f53706dcedf08e8d861 ] || [ -n "${BANC:-}" ] \
    && echo "OK   clé publique archivée : SPKI sha256 $(spki "$PEM")" || { ko "clé publique archivée inattendue"; return 1; }
  [ -f "$CA" ] || { ko "CA du PoC absente"; return 1; }
  echo "### objets publiés, sans attestation de lien"
  for c in "${CAS[@]}"; do
    present "${DEPOT[$c]}" "${DG[$c]}" || { ko "${DEPOT[$c]}@${DG[$c]:0:19}… non publié"; return 1; }
    n=$(referrers "${DEPOT[$c]}" "${DG[$c]}")
    [ "${n%% *}" = 0 ] && echo "OK   ${DEPOT[$c]}@${DG[$c]:0:19}… publié, aucune attestation de lien (referrers : $n)" \
      || { ko "${DEPOT[$c]} : attestation de lien déjà présente ou referrers illisibles ($n) : rien n'est signé en double"; return 1; }
  done
  echo "### provenance de Chains et prédicats, avant toute signature"
  non_signes && chains || return 1
  python3 -I "$PY" predicats "$C" "$d/chains.json" "$d/p" || { ko "prédicats"; return 1; }
  for c in "${CAS[@]}"; do precontrole "$c" "$d/p/$c.json" || { ko "aucune signature : un prédicat est refusé"; return 1; }; done
  echo "### signature par hashivault://lien"
  trap fermer EXIT
  ouvrir || return 1
  for c in "${CAS[@]}"; do
    avec_bao env DOCKER_CONFIG="$DCFG" "$COSIGN" attest --key hashivault://lien --type "$TYPE" --predicate "$d/p/$c.json" \
      --new-bundle-format --use-signing-config=false --tlog-upload=false --yes --registry-cacert "$CA" "$REG_HOTE/${DEPOT[$c]}@${DG[$c]}" \
      > "$d/attest-$c.out" 2>&1; s=$?
    [ "$s" = 0 ] && { echo "OK   cosign attest --key hashivault://lien ${DEPOT[$c]}@${DG[$c]:0:19}… : code 0"; ok+=("$c"); } \
      || ko "cosign attest $c : code $s, $(erreur "$d/attest-$c.out")"
  done
  fermer
  for c in "${ok[@]}"; do
    n=$(referrers "${DEPOT[$c]}" "${DG[$c]}")
    [ "${n%% *}" = 1 ] && echo "OK   ${DEPOT[$c]} : une attestation de lien (referrers : $n)" || ko "${DEPOT[$c]} : referrers $n"
    cp "$d/p/$c.json" "$R/o5-signes-predicat-$c.json"
  done
  echo "     prédicats signés archivés : resultats/o5-signes-predicat-{$(IFS=,; echo "${ok[*]}")}.json"
  echo "à effacer après archivage (chemin littéral) : $d"
}

etape_verifier() {
  set +e
  local c k n
  dossier verifier && construits || return 1
  [ -f "$PEM" ] && echo "OK   clé publique archivée : SPKI sha256 $(spki "$PEM")" || { ko "clé publique archivée absente"; return 1; }
  echo "     anonyme : aucun secret lu, aucune redirection ouverte"
  non_signes || return 1
  openssl ecparam -genkey -name prime256v1 2>/dev/null | openssl ec -pubout -out "$d/autre.pub" 2>/dev/null
  for c in "${CAS[@]}"; do
    echo "### $c : ${DEPOT[$c]}@${DG[$c]}"
    n=$(referrers "${DEPOT[$c]}" "${DG[$c]}"); [ "${n%% *}" = 1 ] && echo "OK   une attestation de lien parmi les referrers ($n)" || ko "referrers : $n"
    v=$(tags "${DEPOT[$c]}"); [ -z "$v" ] && echo "OK   aucun tag" || ko "tags : $v"
    verifier_att lien "$PEM" "${DEPOT[$c]}" "${DG[$c]}" "$d/v-$c.jsonl"; k=$?
    [ "$k" = 0 ] && echo "OK   cosign verify-attestation (clé lien archivée) : $(grep -c . "$d/v-$c.jsonl") enveloppe(s)" || { ko "cosign verify-attestation : $(erreur "$d/v-$c.jsonl.err")"; continue; }
    tirer "${DEPOT[$c]}" "${DG[$c]}" "$d/s-$c" || continue
    juger "$c" ACCEPTÉ "$c" "$d/v-$c.jsonl" "${DG[$c]}" "$d/s-$c" "$d/ns-${ORIG[$c]}"
    python3 -I "$PY" extraire "$d/v-$c.jsonl" "$R/o5-signes-enonce-$c.json" > /dev/null 2>&1 && echo "     énoncé archivé : resultats/o5-signes-enonce-$c.json"
    if verifier_att autre "$d/autre.pub" "${DEPOT[$c]}" "${DG[$c]}" "$d/t-$c.jsonl"; then ko "clé jetable acceptée"
    else echo "OK   témoin : clé jetable refusée ($(erreur "$d/t-$c.jsonl.err"))"; fi
  done
  echo "à effacer après archivage (chemin littéral) : $d"
}

e=${1:-}
case "$e" in
  construire|essai_attest|publier|attester|verifier)
    mkdir -p "$R"
    L=$R/o5-signes-$e.log
    set +e
    (umask 077 && : > "$L")
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-signes.sh $(sha256sum < "$here/o5-signes.sh" | cut -c1-16)… ; o5-signes.py $(sha256sum < "$PY" | cut -c1-16)…${BANC:+ ; BANC}"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer >> "$L"; rc=${PIPESTATUS[0]}
    # contrôles avant tout affichage : K3 (bloc privé), K5 (secret lien), K6 (identifiants de poc-lien), journal et dossier de l'étape
    n=$(grep -c -E -e '-----BEGIN [A-Z ]*PRIVATE' "$L" || true)
    [ "$n" = 0 ] || { echo "KO   K3 : bloc privé dans le journal : journal vidé" > "$L"; chmod 644 "$L"; cat "$L"; exit 1; }
    echo "OK   K3 : aucune ligne de bloc privé dans le journal" >> "$L"
    D=$W/$e; [ "$e" = construire ] && D=$C
    if [ -s "$JL" ]; then
      n=$(tr -d '\n' < "$JL" | grep -c -F -f - "$L" || true)
      m=$(tr -d '\n' < "$JL" | grep -r -l -F -f - "$D" 2>/dev/null | grep -c . || true)
      [ "$n" = 0 ] && [ "$m" = 0 ] || { echo "KO   K5 : valeur du secret lien dans le journal ou le dossier de l'étape : journal vidé" > "$L"; chmod 644 "$L"; cat "$L"; exit 1; }
      echo "OK   K5 : valeur du secret lien absente du journal et du dossier de l'étape" >> "$L"
    fi
    if [ -s "$MDP" ]; then
      # motifs lus sur l'entrée standard (grep -f -), jamais en argument
      n=$(( $(tr -d '\n' < "$MDP" | grep -c -F -f - "$L" || true) + $(tr -d '\n' < "$MDP" | grep -r -l -F -f - "$D" 2>/dev/null | grep -c . || true) ))
      n=$(( n + $(printf 'poc-lien:%s' "$(tr -d '\n' < "$MDP")" | base64 -w0 | grep -c -F -f - "$L" || true) ))
      n=$(( n + $(printf 'poc-lien:%s' "$(tr -d '\n' < "$MDP")" | base64 -w0 | grep -r -l -F -f - "$D" 2>/dev/null | grep -c . || true) ))
      [ -s "$S9/zot-poc-lien.htpasswd" ] && n=$((n + $(cut -d: -f2 "$S9/zot-poc-lien.htpasswd" | grep -c -F -f - "$L" || true)))
      [ "$n" = 0 ] || { echo "KO   K6 : identifiant de poc-lien dans le journal ou le dossier de l'étape : journal vidé" > "$L"; chmod 644 "$L"; cat "$L"; exit 1; }
      echo "OK   K6 : ni mot de passe, ni hash, ni chaîne d'authentification de poc-lien dans le journal et le dossier de l'étape" >> "$L"
    fi
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" >> "$L"; rc=1; }
    chmod 644 "$L"; cat "$L"
    exit "$rc" ;;
  *) echo "usage : $0 construire | essai_attest | publier | attester | verifier" >&2; exit 64 ;;
esac
