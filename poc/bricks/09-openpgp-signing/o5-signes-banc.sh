#!/usr/bin/env bash
# Brique 09, banc hors cluster d'o5-signes.sh : aucun accès à Zot, au cluster ni à OpenBao.
# Faux Zot : un dossier de layouts par dépôt et digest (zot/<dépôt>/<hex>), referrers dans <hex>.att (une enveloppe par ligne) et
# <hex>.cles (clé de chaque enveloppe). Faux oras (cp dans les deux sens, manifest fetch, repo tags), faux curl (API referrers),
# faux cosign (verify-attestation de Chains et du type lien, attest, avec contrôle de l'environnement hashivault et du compte
# poc-lien ; version et generate-key-pair passent au vrai cosign), faux kubectl (port-forward : vrai port d'écoute sur 127.0.0.1).
# Les faux outils lisent leur état à côté d'eux (BANC/zot, BANC/etat) : chaque cas copie l'état du cas nominal au bon moment.
# Images non signées de builds/** construites localement (rpm d'entrée d'O3, deb d'O4) : leurs digests remplacent les valeurs
# archivées par O5_SIGNES_ATTENDUS, admis au banc seulement. Le banc ne signe ni ne vérifie aucune signature : la signature réelle
# de cosign est mesurée par essai_attest (clé jetable) avant la clé lien.
# Usage : poc/bricks/09-openpgp-signing/o5-signes-banc.sh   (journal : resultats/o5-signes-banc.log ; dossier effacé à la main)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$here" rev-parse --show-toplevel)
B=$HOME/.cache/supply-chain-poc/09/o5-signes-banc
S=$here/o5-signes.sh
VRAI=$(cd "$TOP" && mise which cosign)
SECRET=s.bancfaux0123456789abcd
MDP_FAUX=0123456789abcdef0123456789abcdef0123456789abcdef
[ ! -e "$B" ] || { echo "KO   $B existe déjà" >&2; exit 1; }
N=$B/nominal
mkdir -p "$N/bin" "$N/etat" "$N/zot" "$N/secrets9/zot-poc-lien-docker" "$N/resultats" "$B/modele"
echo normal > "$N/etat/mode"; echo "$VRAI" > "$N/etat/vrai"; : > "$N/etat/appels"; : > "$N/etat/erreurs"
(umask 077 && printf '%s' "$SECRET" > "$N/secrets9/openbao-lien.secret" && printf '%s' "$MDP_FAUX" > "$N/secrets9/zot-poc-lien.password" \
  && printf 'poc-lien:$2b$12$%s\n' "$(printf 'x%.0s' $(seq 53))" > "$N/secrets9/zot-poc-lien.htpasswd" \
  && printf '{"auths":{"192.168.161.13:5000":{"auth":"%s"}}}\n' "$(printf 'poc-lien:%s' "$MDP_FAUX" | base64 -w0)" > "$N/secrets9/zot-poc-lien-docker/config.json")
(cd "$B/modele" && unshare --map-auto --map-root-user -n env -i PATH=/usr/bin:/bin HOME="$B/modele" COSIGN_PASSWORD= "$VRAI" generate-key-pair --output-key-prefix lien > /dev/null 2>&1)
cp "$B/modele/lien.pub" "$N/resultats/lien-cle-publique.pem"
# images non signées de builds/** (locales) et valeurs remplacées
python3 -I - "$here/o5-signes.py" "$N/zot" "$B/attendus.json" <<'PY'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("s", sys.argv[1]); s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
z, sortie = sys.argv[2], sys.argv[3]
r = {}
for cle, depot, nom, src in (("rpm_manifeste", "builds/sample-app-rpm", s.RPM, s.L.FICHIERS["rpm-entree"]),
                             ("deb_manifeste", "builds/sample-app-deb", s.DEB, s.L.FICHIERS["deb"])):
    t = os.path.join(z, depot, "tmp")
    dm, _ = s.ecrire_layout(t, {nom: open(src, "rb").read()})
    os.rename(t, os.path.join(z, depot, dm.split(":")[1]))
    r[cle] = dm
json.dump(r, open(sortie, "w"))
print(f"     images non signées locales : rpm {r['rpm_manifeste'][:19]}…, deb {r['deb_manifeste'][:19]}…")
PY
export O5_SIGNES_ATTENDUS=$B/attendus.json

cat > "$N/bin/oras" <<'EOF'
#!/usr/bin/env bash
ICI=$(cd "$(dirname "$0")/.." && pwd); Z=$ICI/zot; E=$ICI/etat; REG=192.168.161.13:5000
echo "oras $*" >> "$E/appels"
ref=; lay=; frm=; cfg=; a=("$@")
for ((i = 0; i < $#; i++)); do
  case "${a[i]}" in --to-oci-layout) lay=${a[i+1]} ;; --from-oci-layout) frm=${a[i+1]} ;; --to-registry-config) cfg=${a[i+1]} ;; "$REG"/*) ref=${a[i]} ;; esac
done
repo=${ref#"$REG"/}; repo=${repo%@*}; hex=${ref##*@sha256:}
case "$1" in
  version) echo "Version: banc" ;;
  cp)
    if [ -n "$lay" ]; then
      [ -d "$Z/$repo/$hex" ] || { echo "Error: $ref: not found"; exit 1; }
      cp -r "$Z/$repo/$hex" "${lay%:a}"; echo "Copied (banc)"; exit 0
    fi
    [ "$cfg" = "$ICI/secrets9/zot-poc-lien-docker/config.json" ] && [ -s "$cfg" ] || { echo "Error: unauthorized (banc)"; exit 1; }
    src=${frm%@*}
    [ "${frm##*@}" = "sha256:$hex" ] && [ -f "$src/blobs/sha256/$hex" ] && [ "$(sha256sum < "$src/blobs/sha256/$hex" | cut -c1-64)" = "$hex" ] \
      || { echo "Error: $frm: not found in layout (banc)"; exit 1; }
    [ ! -e "$Z/$repo/$hex" ] || { echo "Error: denied: update refused (banc)"; exit 1; }
    mkdir -p "$Z/$repo"; cp -r "$src" "$Z/$repo/$hex"; echo "poussée $repo@sha256:$hex" >> "$E/poussees"; echo "Pushed (banc)" ;;
  manifest) [ -d "$Z/$repo/$hex" ] && printf '{"digest":"sha256:%s"}\n' "$hex" || { echo "Error: not found" >&2; exit 1; } ;;
  repo) exit 0 ;;
  *) echo "faux oras : appel inattendu : $*" >&2; exit 9 ;;
esac
EOF
cat > "$N/bin/curl" <<'EOF'
#!/usr/bin/env bash
ICI=$(cd "$(dirname "$0")/.." && pwd); Z=$ICI/zot
url=${*: -1}; p=${url#https://*/v2/}; repo=${p%/referrers/*}; hex=${p##*/sha256:}
[ -d "$Z/$repo/$hex" ] || exit 22
python3 -I - "$Z/$repo/$hex.att" <<'PY'
import base64, json, os, sys
m = []
if os.path.exists(sys.argv[1]):
    for l in open(sys.argv[1]).read().splitlines():
        s = json.loads(base64.b64decode(json.loads(l)["payload"]))
        m.append({"artifactType": "application/vnd.dev.sigstore.bundle.v0.3+json", "annotations": {"dev.sigstore.bundle.predicateType": s["predicateType"]}})
print(json.dumps({"schemaVersion": 2, "manifests": m}))
PY
EOF
cat > "$N/bin/cosign" <<'EOF'
#!/usr/bin/env bash
ICI=$(cd "$(dirname "$0")/.." && pwd); Z=$ICI/zot; E=$ICI/etat; REG=192.168.161.13:5000
mode=$(cat "$E/mode")
case "$1" in version|generate-key-pair) exec "$(cat "$E/vrai")" "$@" ;; esac
SEC=$(cat "$ICI/secrets9/openbao-lien.secret")
case " $* " in *"$SEC"*) echo "secret en argument" >> "$E/erreurs" ;; esac
cmd=$1; shift; key=; typ=; pred=; ref=
while [ $# -gt 0 ]; do case "$1" in --key) key=$2; shift ;; --type) typ=$2; shift ;; --predicate) pred=$2; shift ;; "$REG"/*) ref=$1 ;; esac; shift; done
repo=${ref#"$REG"/}; repo=${repo%@*}; hex=${ref##*@sha256:}; P=$Z/$repo/$hex
case "$cmd" in
  verify-attestation)
    if [ "$typ" = slsaprovenance1 ]; then
      [ "$mode" = chains_ko ] && { echo "Error: no matching attestations: (banc)" >&2; exit 1; }
      [ -d "$P" ] || { echo "Error: not found (banc)" >&2; exit 1; }
      python3 -I -c 'import base64, json, sys
st = {"_type": "https://in-toto.io/Statement/v0.1", "predicateType": "https://slsa.dev/provenance/v1", "subject": [{"name": "banc", "digest": {"sha256": sys.argv[1]}}],
      "predicate": {"buildDefinition": {"buildType": "banc"}, "runDetails": {"builder": {"id": "banc"}, "metadata": {"invocationId": "banc"}}}}
for _ in range(2): print(json.dumps({"payloadType": "application/vnd.in-toto+json", "payload": base64.b64encode(json.dumps(st).encode()).decode(), "signatures": [{"sig": "banc"}]}))' "$hex"
      exit 0
    fi
    case "$(basename "$key")" in lien-cle-publique.pem) lab=lien ;; *) lab=${key%.pub}.key ;; esac
    if ! python3 -I -c 'import base64, json, os, sys
a, c, lab, t = sys.argv[1:5]
n = 0
if os.path.exists(a):
    for l, k in zip(open(a).read().splitlines(), open(c).read().splitlines()):
        if k == lab and json.loads(base64.b64decode(json.loads(l)["payload"]))["predicateType"] == t:
            print(l); n += 1
sys.exit(0 if n else 1)' "$P.att" "$P.cles" "$lab" "$typ"; then echo "Error: no matching attestations: (banc)" >&2; exit 1; fi ;;
  attest)
    [ "${DOCKER_CONFIG:-}" = "$ICI/secrets9/zot-poc-lien-docker" ] && [ -s "$DOCKER_CONFIG/config.json" ] || { echo "Error: unauthorized (banc)" >&2; exit 1; }
    if [ "$key" = hashivault://lien ]; then
      p=${VAULT_ADDR#https://127.0.0.1:}
      [[ $p =~ ^[0-9]+$ ]] && (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null || echo "VAULT_ADDR ${VAULT_ADDR:-} injoignable" >> "$E/erreurs"
      [ "${VAULT_CACERT:-}" = "$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt" ] || echo "VAULT_CACERT" >> "$E/erreurs"
      [ "${VAULT_TLS_SERVER_NAME:-}" = openbao.openbao.svc.cluster.local ] || echo "VAULT_TLS_SERVER_NAME" >> "$E/erreurs"
      [ "${VAULT_TOKEN:-}" = "$SEC" ] || echo "VAULT_TOKEN" >> "$E/erreurs"
      [ "$mode" = fuite ] && { echo "Error: signing: secret $VAULT_TOKEN refusé (banc)" >&2; exit 1; }
      lab=lien
    else lab=$key; fi
    [ -d "$P" ] || { echo "Error: entity not found (banc)" >&2; exit 1; }
    python3 -I -c 'import base64, json, sys
pred, t, nom, hexa = sys.argv[1:5]
st = {"_type": "https://in-toto.io/Statement/v0.1", "predicateType": t, "subject": [{"name": nom, "digest": {"sha256": hexa}}], "predicate": json.load(open(pred))}
print(json.dumps({"payloadType": "application/vnd.in-toto+json", "payload": base64.b64encode(json.dumps(st).encode()).decode(), "signatures": [{"sig": "banc"}]}))' \
      "$pred" "$typ" "$REG/$repo" "$hex" >> "$P.att"
    echo "$lab" >> "$P.cles"; echo "attest $lab $repo" >> "$E/appels" ;;
  *) echo "faux cosign : appel inattendu : $cmd" >&2; exit 9 ;;
esac
EOF
cat > "$N/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
E=$(cd "$(dirname "$0")/.." && pwd)/etat
case "$1" in
  version) echo "Client Version: banc" ;;
  port-forward)
    [ "$*" = "port-forward -n openbao pod/openbao-0 --address 127.0.0.1 :8200" ] || { echo "faux kubectl : appel inattendu : $*" >&2; exit 9; }
    [ "$KUBECONFIG" = "$HOME/.kube/supply-chain-poc.yaml" ] || { echo "faux kubectl : KUBECONFIG inattendu" >&2; exit 9; }
    [ "$(cat "$E/mode")" = pf_echec ] && { echo "error: unable to forward port (banc)"; exit 1; }
    echo "port-forward" >> "$E/appels"
    exec python3 -I -c '
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(8)
print(f"Forwarding from 127.0.0.1:{s.getsockname()[1]} -> 8200", flush=True)
while True:
    c, _ = s.accept(); c.close()
' o5-signes-banc-redirection ;;
  *) echo "faux kubectl : appel inattendu : $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$N/bin/"*

n_ok=0; n_ko=0
verdict() { if eval "$2"; then echo "OK   $1"; n_ok=$((n_ok + 1)); else echo "KO   $1 (condition : $2)"; n_ko=$((n_ko + 1)); fi; }
# shellcheck disable=SC2034
lancer() { # cas étape [mode] [heure] : RC, J (journal), O (sortie)
  local c=$B/$1; echo "${3:-normal}" > "$c/etat/mode"
  BANC=$c HEURE_BANC=${4:-1200} "$S" "$2" > "$c/$2.sortie" 2>&1; RC=$?; J=$c/resultats/o5-signes-$2.log; O=$c/$2.sortie
}
# shellcheck disable=SC2034
hors_banc() { O5_SIGNES_ATTENDUS=$B/attendus.json "$S" verifier > "$B/hors-banc.sortie" 2>&1; RC=$?; }
copier() { cp -a "$N" "$B/$1"; : > "$B/$1/etat/appels"; }
attests() { grep -c '^attest ' "$B/$1/etat/appels" || true; }
ecoutes() { pgrep -f o5-signes-banc-redirection | grep -c . || true; }
sans_secret() { ! grep -r -q -F "$SECRET" "$1/resultats" "$1/travail" "$1"/*.sortie && ! grep -r -q -F "$MDP_FAUX" "$1/resultats" "$1/travail" "$1"/*.sortie; }
{
echo "banc commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-signes.sh $(sha256sum < "$S" | cut -c1-16)… ; o5-signes.py $(sha256sum < "$here/o5-signes.py" | cut -c1-16)… ; o5-signes-banc.sh $(sha256sum < "$0" | cut -c1-16)…"
set +e
echo "### 1. construire"
lancer nominal construire
verdict "code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "trois layouts, seconde construction égale" '[ "$(grep -c -E "^OK   (rpm|depot-rpm|depot-apt) : layout sha256:" "$J")" = 3 ] && grep -q "^OK   seconde construction indépendante : mêmes digests" "$J"'
verdict "chaînes complètes, aucun membre de trop, balayage des membres" '[ "$(grep -c "aucun de trop" "$J")" = 2 ] && [ "$(grep -c "^OK   membres écrits par la brique" "$J")" = 3 ]'
echo "### 2. essai_attest (clé jetable)"
lancer nominal essai_attest
verdict "code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "prédicat réel accepté, deux témoins refusés par le contrôle" 'grep -q "^OK   essai-09-attest (prédicat réel) : contrôle indépendant ACCEPTÉ" "$J" && grep -q "^OK   témoin autre manifeste non signé : contrôle indépendant refuse (lien : manifeste non signé" "$J" && grep -q "^OK   témoin rpm à charge altérée : contrôle indépendant refuse" "$J"'
verdict "clé lien refuse l'attestation jetable ; trois attestations jetables, aucune par la clé lien" 'grep -q "^OK   clé lien : l.attestation de la clé jetable est refusée" "$J" && [ "$(attests nominal)" = 3 ] && ! grep -q "^attest lien" "$N/etat/appels"'
verdict "relevé de la forme de la sortie de verify-attestation" 'grep -q "^     ligne 1 : clés .*_type https://in-toto.io/Statement/v0.1" "$J"'
cp "$J" "$N/essai_attest-nominal.log"
echo "### 3. publier"
lancer nominal publier
verdict "code 0 ; quatre objets poussés par poc-lien, relus en anonyme, sans tag" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J" && [ "$(grep -c "^OK   poussé par poc-lien : signes/" "$J")" = 4 ] && [ "$(grep -c "^OK   relu en anonyme" "$J")" = 4 ] && [ "$(grep -c "aucun tag" "$J")" = 4 ]'
verdict "copie du deb : même digest que le manifeste non signé" '[ -d "$N/zot/signes/sample-app-deb/$(python3 -I -c "import json; print(json.load(open(\"$B/attendus.json\"))[\"deb_manifeste\"][7:])")" ]'
cp "$J" "$N/publier-nominal.log"
copier corrompu; copier fuite; copier pf; copier refus
mv "$N/travail/publier" "$N/travail/publier-1"
lancer nominal publier
verdict "relance : quatre objets déjà présents, rien repoussé" '[ "$RC" = 0 ] && [ "$(grep -c "déjà présent : non repoussé" "$J")" = 4 ] && [ "$(grep -c . "$N/etat/poussees")" = 7 ]'
echo "### 4. fenêtre de la mesure de M1b"
mkdir -p "$B/heure"; cp -a "$N/bin" "$N/secrets9" "$B/heure/"; mkdir -p "$B/heure/etat" "$B/heure/resultats"; cp "$N/etat/vrai" "$B/heure/etat/"; : > "$B/heure/etat/appels"
lancer heure publier normal 2345
verdict "23:45 UTC : publier refusée avant tout appel à oras" 'grep -q "^KO   écriture dans Zot refusée entre 23:30 et 08:00 UTC" "$J" && [ "$RC" != 0 ] && [ ! -s "$B/heure/etat/appels" ]'
lancer heure attester normal 0759
verdict "07:59 UTC : attester refusée avant tout appel" 'grep -q "^KO   écriture dans Zot refusée" "$J" && [ ! -s "$B/heure/etat/appels" ]'
echo "### 5. attester nominal"
lancer nominal attester
verdict "code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "quatre prédicats acceptés avant signature, quatre signatures par la clé lien" '[ "$(grep -c "contrôle indépendant ACCEPTÉ avant signature" "$J")" = 4 ] && [ "$(grep -c "^attest lien signes/" "$N/etat/appels")" = 4 ]'
verdict "environnement hashivault conforme, secret jamais en argument, compte poc-lien" '[ ! -s "$N/etat/erreurs" ]'
verdict "une attestation de lien par objet ; prédicats archivés" '[ "$(grep -c "^OK   signes/.* : une attestation de lien" "$J")" = 4 ] && [ "$(ls "$N/resultats"/o5-signes-predicat-*.json | grep -c .)" = 4 ]'
verdict "redirection fermée, plus aucune écoute" 'grep -q "^OK   redirection fermée" "$J" && [ "$(ecoutes)" = 0 ]'
verdict "K5 et K6 tenus ; secret et mot de passe absents des journaux, sorties et dossiers" 'grep -q "^OK   K5" "$J" && grep -q "^OK   K6" "$J" && sans_secret "$N"'
cp "$J" "$N/attester-nominal.log"
mv "$N/travail/attester" "$N/travail/attester-1"
lancer nominal attester
verdict "relance : refus avant signature (attestation déjà présente), aucune redirection" 'grep -q "^KO   signes/sample-app-rpm : attestation de lien déjà présente" "$J" && [ "$(grep -c "^attest lien" "$N/etat/appels")" = 4 ] && [ ! -e "$N/travail/attester/redirection.log" ]'
echo "### 6. attester : layout corrompu après construire"
python3 -I -c 'import json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "index.json")))["manifests"][0]["digest"][7:]
c = json.load(open(os.path.join(d, "blobs/sha256", m)))["layers"][0]["digest"][7:]
p = os.path.join(d, "blobs/sha256", c); b = bytearray(open(p, "rb").read()); b[600] ^= 1; open(p, "wb").write(b)' "$B/corrompu/travail/construire/depot-apt"
lancer corrompu attester
verdict "corrompu : refus avant signature, aucune redirection" '[ "$RC" != 0 ] && grep -q "^KO   prédicats" "$J" && [ "$(attests corrompu)" = 0 ] && [ ! -e "$B/corrompu/travail/attester/redirection.log" ]'
echo "### 7. attester : provenance de Chains refusée"
lancer refus attester chains_ko
verdict "Chains refusée : aucune signature, aucune redirection" 'grep -q "^KO   provenance de Chains (rpm)" "$J" && [ "$(attests refus)" = 0 ] && [ ! -e "$B/refus/travail/attester/redirection.log" ]'
echo "### 8. attester : redirection en échec"
lancer pf attester pf_echec
verdict "redirection en échec : KO, aucune signature" 'grep -q "^KO   redirection non ouverte" "$J" && [ "$(attests pf)" = 0 ] && [ "$(ecoutes)" = 0 ]'
echo "### 9. attester : secret dans une erreur du client"
lancer fuite attester fuite
verdict "fuite : journal vidé par K5, secret absent du journal et de la sortie, redirection fermée" 'grep -q "^KO   K5" "$J" && [ "$(grep -c . "$J")" = 1 ] && ! grep -q -F "$SECRET" "$J" "$O" && [ "$(ecoutes)" = 0 ]'
echo "### 10. verifier"
lancer nominal verifier
verdict "code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "quatre contrôles indépendants ACCEPTÉ, quatre énoncés archivés" '[ "$(grep -c -E "^OK   (rpm|deb|depot-rpm|depot-apt) : contrôle indépendant ACCEPTÉ" "$J")" = 4 ] && [ "$(ls "$N/resultats"/o5-signes-enonce-*.json | grep -c .)" = 4 ]'
verdict "B1 recalculé, identité du deb, chaînes des dépôts recalculées" 'grep -q "OK   B1 recalculé sur les octets lus" "$N/travail/verifier/v-rpm.jsonl.controle" && grep -q "identité : manifeste publié" "$N/travail/verifier/v-deb.jsonl.controle" && grep -q "aucun de trop" "$N/travail/verifier/v-depot-rpm.jsonl.controle" && grep -q "aucun de trop" "$N/travail/verifier/v-depot-apt.jsonl.controle"'
verdict "quatre témoins clé jetable refusés ; aucun secret lu (étape anonyme)" '[ "$(grep -c "^OK   témoin : clé jetable refusée" "$J")" = 4 ] && ! grep -q "secret lien présent" "$J"'
cp "$J" "$N/verifier-nominal.log"
echo "### 11. variable de banc hors banc"
hors_banc
verdict "O5_SIGNES_ATTENDUS refusée hors banc (code 64), avant tout" '[ "$RC" = 64 ] && grep -q "réservé au banc" "$B/hors-banc.sortie"'
echo "### journaux nominaux"
for x in essai_attest publier attester verifier; do sed 's/^/     | /' "$N/$x-nominal.log"; done
echo "bilan : $n_ok OK, $n_ko KO"
echo "banc fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "à effacer après archivage (chemin littéral) : $B"
[ "$n_ko" = 0 ]
} 2>&1 | tee "$here/resultats/o5-signes-banc.log"
