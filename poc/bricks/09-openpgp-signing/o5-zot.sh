#!/usr/bin/env bash
# Brique 09, O5 réel, troisième accord du propriétaire (« Oui, prépare-le », 19/11/2026) : lecture de Zot, anonyme, depuis
# l'hôte, comme les étapes comparaison et provenance de la 05 (oras et cosign de mise, CA du PoC). Rien n'est écrit dans Zot.
#   lecture  pour les deux manifestes non signés (rpm 07b7bd6f…, deb 60f25f5c…, valeurs relues par o5-lien.py dans les journaux
#            archivés des briques 05 et 06) :
#            1. tirage par digest dans un layout OCI neuf (oras cp, DOCKER_CONFIG vide : lecture anonyme), contrôlé hors réseau
#               par o5-zot-controle.py : manifeste, couche, un seul fichier, de sha256 égal au fichier non signé ; le lien
#               manifeste → fichier, relu jusqu'ici dans les journaux, est recalculé ;
#            2. provenance de Chains : cosign verify-attestation avec la clé publique archivée de Chains (sha256 contrôlé),
#               sans journal de transparence, comme la 05 ; enveloppes contrôlées (SLSA v1, sujet = le manifeste) ;
#            3. refus : la même vérification avec une clé jetable est refusée.
#            Ne vérifie pas les jetons d'horodatage (TSA) des enveloppes, que contrôle la porte.
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o5-zot.sh lecture   (journal : resultats/o5-zot-lecture.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$here" rev-parse --show-toplevel)
R=$here/resultats
PY=$here/o5-zot-controle.py
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
REG_HOTE=192.168.161.13:5000                                       # Zot depuis l'hôte (comme la 05 et la 07a)
CLE_CHAINS=$TOP/poc/bricks/08-trust-plane/resultats/chains-cle-publique.pem
W=$HOME/.cache/supply-chain-poc/09/o5-zot
ORAS=$(cd "$TOP" && mise which oras)
COSIGN=$(cd "$TOP" && mise which cosign)
# compte_zot (décision « Oui, signes/** » du 19/11/2026) : mot de passe et ligne htpasswd de poc-lien, sur l'hôte, sans réseau,
# comme replay.sh compte_zot (brique 10) ; la brique 08 ne lira que la ligne htpasswd (A-REPORTER §4 quinquies).
S9=$HOME/.cache/supply-chain-poc/09/secrets
if [ -n "${BANC:-}" ]; then R=$BANC/resultats; S9=$BANC/secrets9; mkdir -p "$R"; fi
MDP=$S9/zot-poc-lien.password
HTP=$S9/zot-poc-lien.htpasswd

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; }
valeur() { # clé : valeur archivée relue par o5-lien.py attendus
  sed -n "s/^     $1 : //p" "$W/attendus.txt"
}
anonyme() { env DOCKER_CONFIG="$W/docker-vide" "$@" < /dev/null; }

etape_lecture() {
  set +e
  local a depot digest nom sha d m
  [ ! -e "$W" ] || { ko "$W existe déjà : rien n'est réutilisé"; return 1; }
  mkdir -p "$W/docker-vide"
  echo "### gardes"
  python3 -I "$here/o5-lien.py" attendus > "$W/attendus.txt" 2>&1 && echo "OK   valeurs archivées relues par o5-lien.py" \
    || { ko "valeurs archivées"; return 1; }
  m=$(sed -n -E 's/^OK   clé publique de Chains \(sha256\) : ([0-9a-f]{64})$/\1/p' "$TOP/poc/bricks/05-rpm-mock/resultats/m4c-provenance.log")
  [ "$(sha256sum < "$CLE_CHAINS" | cut -c1-64)" = "$m" ] \
    && echo "OK   clé publique de Chains (08) : sha256 $m, égal à m4c-provenance.log (05)" || { ko "clé publique de Chains"; return 1; }
  [ -f "$CA" ] && echo "OK   CA du PoC présente (non affichée)" || { ko "CA du PoC absente"; return 1; }
  echo "     oras $("$ORAS" version 2>/dev/null | sed -n 's/^Version: *//p') ; cosign $("$COSIGN" version 2>&1 | sed -n 's/^GitVersion: *//p')"
  for a in rpm deb; do
    depot=builds/sample-app-$a
    digest=$(valeur "${a}_manifeste"); sha=$(valeur "${a}_fichier")
    [ "$a" = rpm ] && nom=sample-app-1.0.0-2.el9.x86_64.rpm || nom=sample-app_1.0.0-2_amd64.deb
    d=$W/$a; mkdir -p "$d"
    echo "### $a : $depot@$digest"
    if anonyme "$ORAS" cp --no-tty --from-ca-file "$CA" "$REG_HOTE/$depot@$digest" --to-oci-layout "$d/layout:a" > "$d/cp.out" 2>&1; then
      echo "OK   oras cp par digest, lecture anonyme : code 0"
    else ko "oras cp : $(grep -m1 -i -E 'error|denied|unauthorized' "$d/cp.out" | cut -c1-200)"; continue; fi
    python3 -I "$PY" layout "$d/layout" "$digest" "$nom" "$sha" || ko "$a : layout refusé"
    if anonyme "$COSIGN" verify-attestation --key "$CLE_CHAINS" --type slsaprovenance1 --insecure-ignore-tlog=true \
        --registry-cacert "$CA" "$REG_HOTE/$depot@$digest" > "$d/enveloppes.json" 2> "$d/cosign.err"; then
      echo "OK   cosign verify-attestation (clé de Chains) : $(grep -c . "$d/enveloppes.json") enveloppe(s) valide(s)"
    else ko "cosign verify-attestation : $(grep -m1 -E '^Error' "$d/cosign.err" | cut -c1-200)"; continue; fi
    python3 -I "$PY" enveloppes "$d/enveloppes.json" "$digest" || ko "$a : enveloppes refusées"
    openssl ecparam -genkey -name prime256v1 2>/dev/null | openssl ec -pubout -out "$d/autre.pub" 2>/dev/null
    if anonyme "$COSIGN" verify-attestation --key "$d/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true \
        --registry-cacert "$CA" "$REG_HOTE/$depot@$digest" > /dev/null 2> "$d/autre.err"; then
      ko "$a : provenance acceptée avec une clé jetable"
    else
      m=$(grep -m1 -E '^Error' "$d/autre.err" | cut -c1-200)
      grep -q -E 'no matching attestations|invalid signature' <<<"$m" && echo "OK   témoin : clé jetable refusée ($m)" || ko "témoin : refus sans le motif attendu ($m)"
    fi
  done
  echo "à effacer après archivage (chemin littéral) : $W"
}

etape_compte_zot() {
  set +e
  local h s
  [ -d "$S9" ] || { ko "dossier 09/secrets absent"; return 1; }
  [ ! -e "$MDP" ] && [ ! -e "$HTP" ] && echo "OK   mot de passe et ligne htpasswd de poc-lien absents de 09/secrets" \
    || { ko "mot de passe ou ligne htpasswd de poc-lien déjà présent : rien n'est écrasé"; return 1; }
  echo "     mkpasswd : $(command -v mkpasswd) ; $(dpkg-query -W -f '${Package} ${Version}' whois 2>/dev/null || echo 'paquet whois non relevé')"
  (umask 077 && openssl rand -hex 24 | tr -d '\n' > "$MDP")
  grep -qxE '[0-9a-f]{48}' "$MDP" && echo "OK   mot de passe : 48 caractères hexadécimaux (openssl rand -hex 24), jamais affiché" \
    || { ko "mot de passe de forme inattendue"; return 1; }
  h=$(mkpasswd -m bcrypt -R 12 -s < "$MDP")
  case $h in '$2b$12$'*) ;; *) ko "hash bcrypt inattendu"; return 1 ;; esac
  (umask 077 && printf 'poc-lien:%s\n' "$h" > "$HTP")
  h=
  grep -qxE 'poc-lien:\$2b\$12\$[./A-Za-z0-9]{53}' "$HTP" \
    && echo "OK   ligne htpasswd conforme au motif proposé pour stockage.sh (poc-lien, bcrypt, coût 12)" || ko "ligne htpasswd non conforme"
  s=$(cut -c17-38 "$HTP")   # sel bcrypt (22 caractères après « poc-lien:$2b$12$ »)
  [ "poc-lien:$(mkpasswd -m bcrypt -R 12 -S "$s" -s < "$MDP")" = "$(cat "$HTP")" ] \
    && echo "OK   hash recalculé depuis le mot de passe avec le même sel : égal à la ligne htpasswd" || ko "hash recalculé différent"
  s=
  [ "$(stat -c %a "$MDP")" = 600 ] && [ "$(stat -c %a "$HTP")" = 600 ] \
    && echo "OK   modes : zot-poc-lien.password 600, zot-poc-lien.htpasswd 600" || ko "modes inattendus"
  echo "     suite : la session principale ajoute le bloc du §4 quinquies d'A-REPORTER à stockage.sh et l'entrée signes/** à zot.json, puis redémarre Zot"
}

# droits_zot (après l'application par la session principale, commit 4fe5e8a3 de la 08) : droits de poc-lien sur signes/**, essayés
# sur des dépôts jetables signes/essai-09*, comme replay.sh droits_zot (brique 10). Configuration de registre de poc-lien écrite par
# ce script dans 09/secrets/zot-poc-lien-docker/config.json (0600, gardée pour la publication et cosign) ; témoin poc-ecriture
# (mot de passe lu par ce script dans 08/secrets) dans une configuration temporaire, vidée à la fin. Rien n'est supprimé dans Zot :
# poc-lien ne le peut pas, et les objets d'essai restent.
DCFG=$S9/zot-poc-lien-docker
TEMOIN=$S9/temoin-poc-ecriture-docker
S8=$HOME/.cache/supply-chain-poc/08/secrets
etape_droits_zot() {
  set +e
  local x=$W/droits img autre r rp
  [ -s "$MDP" ] || { ko "mot de passe de poc-lien absent (compte_zot)"; return 1; }
  [ ! -e "$W" ] || { ko "$W existe déjà : rien n'est réutilisé"; return 1; }
  mkdir -p "$x" "$W/docker-vide"
  if [ ! -s "$DCFG/config.json" ]; then
    (umask 077 && mkdir -p "$DCFG" && printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" "$(printf 'poc-lien:%s' "$(cat "$MDP")" | base64 -w0)" > "$DCFG/config.json")
    echo "OK   configuration de registre de poc-lien écrite dans 09/secrets/zot-poc-lien-docker (mode $(stat -c %a "$DCFG/config.json"))"
  else echo "OK   configuration de registre de poc-lien déjà présente (mode $(stat -c %a "$DCFG/config.json"))"; fi
  (umask 077 && mkdir -p "$TEMOIN" && printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" "$(printf 'poc-ecriture:%s' "$(cat "$S8/zot-poc-ecriture.password")" | base64 -w0)" > "$TEMOIN/config.json")
  # image jetable : un layout OCI, une couche tar d'un fichier daté (digest neuf à chaque passage)
  python3 -I - "$x/image" "essai des droits de poc-lien, brique 09, $(date -u '+%Y-%m-%dT%H:%M:%SZ')" <<'PY'
import hashlib, io, json, os, sys, tarfile
d, texte = sys.argv[1], sys.argv[2].encode()
os.makedirs(os.path.join(d, "blobs", "sha256"))
open(os.path.join(d, "oci-layout"), "w").write('{"imageLayoutVersion":"1.0.0"}')
def ecrire(b):
    h = hashlib.sha256(b).hexdigest(); open(os.path.join(d, "blobs", "sha256", h), "wb").write(b); return "sha256:" + h
t = io.BytesIO()
with tarfile.open(fileobj=t, mode="w", format=tarfile.USTAR_FORMAT) as tf:
    i = tarfile.TarInfo("essai.txt"); i.size = len(texte); i.mtime = 0; tf.addfile(i, io.BytesIO(texte))
c = ecrire(t.getvalue()); n = len(t.getvalue())
cfg = json.dumps({"architecture": "amd64", "os": "linux", "rootfs": {"type": "layers", "diff_ids": [c]}}).encode(); dc = ecrire(cfg)
m = json.dumps({"schemaVersion": 2, "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "config": {"mediaType": "application/vnd.oci.image.config.v1+json", "digest": dc, "size": len(cfg)},
                "layers": [{"mediaType": "application/vnd.oci.image.layer.v1.tar", "digest": c, "size": n}]}).encode()
dm = ecrire(m)
json.dump({"schemaVersion": 2, "manifests": [{"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": dm, "size": len(m)}]},
          open(os.path.join(d, "index.json"), "w"))
print(dm)
PY
  img=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifests"][0]["digest"])' "$x/image/index.json")
  echo "image jetable : $img"
  essai() { # libellé attendu(accepte|refus) commande… : résultat d'une écriture
    local l=$1 att=$2; shift 2
    if "$@" < /dev/null > "$x/sortie" 2>&1; then r=accepte; else r=refus; fi
    [ "$r" = "$att" ] && echo "OK   $l : $r$([ "$r" = refus ] && echo " ($(grep -m1 -iE 'error|denied|unauthor|forbidden|not found' "$x/sortie" | cut -c1-140))")" \
      || echo "KO   $l : $r (attendu $att) : $(grep -m1 -iE 'error|denied|unauthor|forbidden|not found' "$x/sortie" | cut -c1-140)"
  }
  local L1=(--to-registry-config "$DCFG/config.json" --to-ca-file "$CA") A1=(--registry-config "$DCFG/config.json" --ca-file "$CA")
  echo "### poc-lien"
  essai "poc-lien, par digest dans signes/essai-09" accepte "$ORAS" cp "${L1[@]}" --from-oci-layout "$x/image@$img" "$REG_HOTE/signes/essai-09@$img"
  essai "poc-lien, par tag dans signes/essai-09" refus "$ORAS" cp "${L1[@]}" --from-oci-layout "$x/image@$img" "$REG_HOTE/signes/essai-09:tag-interdit"
  essai "poc-lien, par digest dans builds/essai-09 (hors de signes/**)" refus "$ORAS" cp "${L1[@]}" --from-oci-layout "$x/image@$img" "$REG_HOTE/builds/essai-09@$img"
  printf '{"essai":"referrer de poc-lien"}' > "$x/bundle.json"
  attacher() { (cd "$x" && "$ORAS" attach "${A1[@]}" --artifact-type application/vnd.dev.sigstore.bundle.v0.3+json "$REG_HOTE/$1@$img" bundle.json:application/vnd.dev.sigstore.bundle.v0.3+json); }
  essai "poc-lien, referrer (oras attach) sur signes/essai-09@image" accepte attacher signes/essai-09
  essai "poc-lien, referrer dans signes/essai-09-sans-sujet, sujet absent de ce dépôt" refus attacher signes/essai-09-sans-sujet
  essai "poc-lien, suppression du manifeste" refus "$ORAS" manifest delete "${A1[@]}" --force "$REG_HOTE/signes/essai-09@$img"
  echo "### autres"
  essai "anonyme, par digest dans signes/essai-09-anonyme" refus env DOCKER_CONFIG="$W/docker-vide" "$ORAS" cp --to-ca-file "$CA" --from-oci-layout "$x/image@$img" "$REG_HOTE/signes/essai-09-anonyme@$img"
  essai "poc-ecriture, par digest dans signes/essai-09-ecriture (motif le plus long)" refus "$ORAS" cp --to-registry-config "$TEMOIN/config.json" --to-ca-file "$CA" --from-oci-layout "$x/image@$img" "$REG_HOTE/signes/essai-09-ecriture@$img"
  : > "$TEMOIN/config.json"; echo "     configuration temporaire du témoin poc-ecriture vidée ($(wc -c < "$TEMOIN/config.json") octet)"
  echo "### lecture anonyme"
  autre=$(anonyme "$ORAS" manifest fetch --descriptor --ca-file "$CA" "$REG_HOTE/signes/essai-09@$img" 2>/dev/null | jq -r .digest)
  [ "$autre" = "$img" ] && echo "OK   manifeste relu en anonyme : $img" || ko "lecture anonyme du manifeste : ${autre:-rien}"
  rp=$(curl -fsS --cacert "$CA" "https://$REG_HOTE/v2/signes/essai-09/referrers/$img" | jq -r '[.manifests[] | .artifactType] | join(",")')
  [ "$rp" = application/vnd.dev.sigstore.bundle.v0.3+json ] && echo "OK   referrers relus en anonyme : $rp" || ko "referrers : ${rp:-rien}"
  echo "     tags de signes/essai-09 : $(anonyme "$ORAS" repo tags --ca-file "$CA" "$REG_HOTE/signes/essai-09" 2>/dev/null | paste -sd' ' | sed 's/^$/aucun/')"
  echo "     objets laissés dans Zot (poc-lien ne peut rien supprimer) : signes/essai-09@$img et son referrer"
  echo "à effacer après archivage (chemin littéral) : $W"
}

e=${1:-}
case "$e" in
  compte_zot|droits_zot)
    L=$R/o5-zot-$e.log
    set +e
    (umask 077 && : > "$L")
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-zot.sh $(sha256sum < "$here/o5-zot.sh" | cut -c1-16)…${BANC:+ ; BANC}"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer >> "$L"; rc=${PIPESTATUS[0]}
    # contrôles avant tout affichage : ni le mot de passe ni le hash dans le journal
    n=0
    [ -s "$MDP" ] && n=$(grep -c -F -f "$MDP" "$L" || true)
    [ -s "$HTP" ] && [ "$n" = 0 ] && n=$(cut -d: -f2 "$HTP" | grep -c -F -f - "$L" || true)
    [ -s "$MDP" ] && [ "$n" = 0 ] && n=$(printf 'poc-lien:%s' "$(cat "$MDP")" | base64 -w0 | grep -c -F -f - "$L" || true)
    [ -s "$S8/zot-poc-ecriture.password" ] && [ "$n" = 0 ] && n=$(grep -c -F -f "$S8/zot-poc-ecriture.password" "$L" || true)
    if [ "$n" != 0 ]; then : > "$L"; echo "KO   K6 : mot de passe ou hash de poc-lien dans le journal : journal vidé" > "$L"; chmod 644 "$L"; cat "$L"; exit 1; fi
    echo "OK   K6 : ni le mot de passe ni le hash de poc-lien dans le journal" >> "$L"
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" >> "$L"; rc=1; }
    chmod 644 "$L"; cat "$L"
    exit "$rc" ;;
  lecture)
    L=$R/o5-zot-$e.log
    set +e
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-zot.sh $(sha256sum < "$here/o5-zot.sh" | cut -c1-16)… ; o5-zot-controle.py $(sha256sum < "$PY" | cut -c1-16)…"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer > "$L"; rc=${PIPESTATUS[0]}
    n=$(grep -c -E -e '-----BEGIN' "$L" || true)
    if [ "$n" != 0 ]; then : > "$L"; echo "KO   K3 : $n ligne(s) de bloc armuré dans le journal : journal vidé" | tee "$L"; exit 1; fi
    echo "OK   K3 : aucune ligne de bloc armuré dans le journal" >> "$L"
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" >> "$L"; rc=1; }
    cat "$L"
    exit "$rc" ;;
  *) echo "usage : $0 lecture | compte_zot | droits_zot" >&2; exit 64 ;;
esac
