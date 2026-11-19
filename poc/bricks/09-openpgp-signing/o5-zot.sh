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

e=${1:-}
case "$e" in
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
  *) echo "usage : $0 lecture" >&2; exit 64 ;;
esac
