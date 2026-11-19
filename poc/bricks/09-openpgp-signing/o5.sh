#!/usr/bin/env bash
# Brique 09, O5 À SEC : banc hôte de l'attestation de lien (D3 a). Sans cluster, sans OpenBao, sans Zot, sans réseau,
# sans installation : cosign 3.1.4 de mise (sha256 contrôlé contre mise.lock), python3 de l'hôte. cosign tourne dans un
# espace de noms réseau vide (unshare -n), environnement vidé, HOME jetable : un drapeau mal compris échoue au lieu de publier.
#   prealables  lecture locale : cosign (empreinte, version, drapeaux hors ligne analysés par --help seul), valeurs archivées,
#               fichiers gardés d'O3 et d'O4 (sha256), empreinte de la clé OpenPGP recalculée sans gpg.
#   banc        deux clés cosign JETABLES (lien, autre), sans mot de passe, hors du dépôt ; quatre énoncés in-toto signés par
#               attest-blob (rpm signé, deb, dépôt rpm, dépôt apt), vérifiés par cosign puis par le contrôle indépendant
#               d'o5-lien.py (sujet, lien vers les valeurs archivées, B1 recalculé sans rpm, chaînes des dépôts) ; témoins
#               de refus. Le dossier du banc (clés comprises) est à effacer après archivage.
# Ne mesure pas : la signature par la clé Transit « lien » d'OpenBao, le referrer dans Zot, la provenance de Chains du manifeste
# non signé, un sujet de type manifeste OCI (ici le sujet est un fichier).
# Usage (racine du dépôt) : poc/bricks/09-openpgp-signing/o5.sh <étape>   (journal : resultats/o5-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$here" rev-parse --show-toplevel)
R=$here/resultats
PY=$here/o5-lien.py
BASE=$HOME/.cache/supply-chain-poc/09
O5=$BASE/o5
B=$O5/banc
TYPE=https://supply-chain.example/lien-openpgp/v1
CAS="rpm deb depot-rpm depot-apt"
COSIGN=$(cd "$TOP" && mise which cosign)
RESEAU='dial tcp|lookup |no such host|connection refused|network is unreachable|tuf|TUF|rekor|fulcio|timeout'

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
ko() { echo "KO   $*"; }
lien() { python3 -I "$PY" "$@"; }
cos() { # cosign sans réseau, environnement vidé ; HOME en premier argument
  local h=$1; shift
  unshare --map-auto --map-root-user -n env -i PATH=/usr/bin:/bin HOME="$h" LC_ALL=C COSIGN_PASSWORD= "$COSIGN" "$@"
}
fichier() {
  case $1 in
    rpm) echo "$BASE/o3/signer/depot/sample-app-1.0.0-2.el9.x86_64.rpm" ;;
    deb) echo "$BASE/o4/signer/depot/pool/main/s/sample-app/sample-app_1.0.0-2_amd64.deb" ;;
    depot-rpm) echo "$BASE/o3/signer/depot/repodata/repomd.xml" ;;
    depot-apt) echo "$BASE/o4/signer/depot/dists/poc/InRelease" ;;
  esac
}
prives() { # dossier… : nombre de fichiers portant un en-tête de clé privée (OpenPGP, sigstore, PEM), sans rien afficher
  { grep -r -l -E -e '-----BEGIN [A-Z ]*PRIVATE KEY' "$@" 2>/dev/null || true; } | grep -c . || true
}

sonde() { # sous-commande drapeaux… : analyse des drapeaux par cobra (--help), aucune exécution
  local c=$1 out rc; shift
  out=$(cos /nonexistent "$c" "$@" --help 2>&1); rc=$?
  if [ "$rc" = 0 ]; then echo "OK   cosign $c accepte : $*"; else ko "cosign $c $* : code $rc, $(grep -m1 -i -E 'unknown|error' <<<"$out" | cut -c1-160)"; fi
  grep -i -m3 'deprecated' <<<"$out" | sed 's/^/     note : /' || true
}

etape_prealables() {
  set +e
  local s a
  echo "cosign : ${COSIGN#"$HOME"/}"
  s=$(sha256sum < "$COSIGN" | cut -c1-64)
  a=$(grep -A1 -F '[tools."aqua:sigstore/cosign"."platforms.linux-x64"]' "$TOP/mise.lock" | grep -o -E '[0-9a-f]{64}')
  [ -n "$a" ] && [ "$s" = "$a" ] && echo "OK   cosign : sha256 $s égal à mise.lock" || ko "cosign : sha256 $s, mise.lock ${a:-absent}"
  echo "     $(cos /nonexistent version 2>&1 | grep -E '^(GitVersion|GitCommit|BuildDate):' | tr -s ' ' | paste -sd ';' -)"
  sonde generate-key-pair --output-key-prefix=x
  sonde attest-blob --new-bundle-format --use-signing-config=false --tlog-upload=false --yes
  sonde verify-blob-attestation --new-bundle-format --insecure-ignore-tlog
  echo "python3 : $(python3 -I -c 'import sys; print(sys.version.split()[0])')"
  echo "### valeurs archivées et fichiers gardés"
  lien attendus || ko "valeurs archivées ou fichiers gardés"
  echo "OK   en-têtes de clé privée dans o3/signer et o4/signer : $(prives "$BASE/o3/signer" "$BASE/o4/signer") fichier(s) (0 attendu)"
  [ "$(prives "$BASE/o3/signer" "$BASE/o4/signer")" = 0 ] || ko "en-tête de clé privée dans un dossier gardé"
  [ ! -e "$B" ] && echo "OK   $B absent" || ko "$B existe déjà"
}

attester() { # clé prédicat fichier bundle
  cos "$B/home" attest-blob --key "$1" --type "$TYPE" --predicate "$2" --bundle "$4" --new-bundle-format \
    --use-signing-config=false --tlog-upload=false --yes "$3" > "$4.out" 2>&1
}
verifier() { # bundle clé fichier : code de cosign ; sortie dans bundle.verif
  cos "$B/home" verify-blob-attestation --bundle "$1" --new-bundle-format --key "$2" --insecure-ignore-tlog --type "$TYPE" "$3" \
    > "$1.verif" 2>&1
}
derniere_erreur() { grep -E '^Error' "$1" | tail -1 | cut -c1-220; }

cosign_accepte() { # libellé bundle clé fichier
  verifier "$2" "$3" "$4"; local rc=$?
  if [ "$rc" = 0 ] && grep -q '^Verified OK' "$2.verif"; then echo "OK   $1 : cosign verify-blob-attestation : Verified OK"
  else ko "$1 : cosign : code $rc, $(derniere_erreur "$2.verif")"; fi
}
cosign_refuse() { # libellé bundle clé fichier motif
  verifier "$2" "$3" "$4"; local rc=$? m
  m=$(derniere_erreur "$2.verif")
  if [ "$rc" = 0 ]; then ko "$1 : cosign accepte (refus attendu)"
  elif grep -q -E "$RESEAU" <<<"$m"; then ko "$1 : refus de cosign sans motif de signature (réseau ou TUF) : $m"
  elif grep -q -i -E "$5" <<<"$m"; then echo "OK   $1 : cosign refuse, code $rc, motif « $5 » : $m"
  else ko "$1 : cosign refuse, code $rc, sans le motif « $5 » : $m"; fi
}
controle_accepte() { # libellé cas bundle fichier
  local out rc
  out=$(lien controle "$2" "$3" "$4" 2>&1); rc=$?
  sed 's/^/     | /' <<<"$out"
  [ "$rc" = 0 ] && tail -1 <<<"$out" | grep -q '^ACCEPTÉ$' && echo "OK   $1 : contrôle indépendant : accepté" \
    || ko "$1 : contrôle indépendant : code $rc"
}
controle_refuse() { # libellé cas bundle fichier motif
  local out rc
  out=$(lien controle "$2" "$3" "$4" 2>&1); rc=$?
  sed 's/^/     | /' <<<"$out"
  if [ "$rc" = 3 ] && grep -q -E "^REFUS $5" <<<"$out"; then echo "OK   $1 : contrôle indépendant refuse, motif « $5 »"
  else ko "$1 : contrôle indépendant : code $rc, motif « $5 » attendu"; fi
}

etape_banc() {
  set +e
  local c k f
  [ ! -e "$B" ] || { ko "$B existe déjà : rien n'est réutilisé ni écrasé"; return 1; }
  mkdir -p "$B/home" "$B/cles" "$B/p" "$B/b"
  echo "### valeurs archivées"
  lien attendus > "$B/attendus.txt" 2>&1 && echo "OK   valeurs archivées et fichiers gardés relus ($(grep -c '^OK' "$B/attendus.txt") contrôles)" \
    || { cat "$B/attendus.txt"; ko "valeurs archivées"; return 1; }
  echo "### clés cosign jetables (sans mot de passe, hors du dépôt, jamais affichées)"
  for k in lien autre; do
    if (cd "$B/cles" && cos "$B/home" generate-key-pair --output-key-prefix "$k") > "$B/cles/$k.out" 2>&1 \
        && [ -f "$B/cles/$k.key" ] && [ -f "$B/cles/$k.pub" ]; then
      echo "OK   clé $k : publique $(sha256sum < "$B/cles/$k.pub" | cut -c1-16)… ; en-tête de la clé privée :" \
        "$(grep -c -E '^-----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----$' "$B/cles/$k.key") ligne(s) « ENCRYPTED SIGSTORE PRIVATE KEY »," \
        "$(grep -c -E '^[[:space:]]*-----BEGIN PGP PRIVATE KEY BLOCK-----[[:space:]]*$' "$B/cles/$k.key") ligne(s) du motif de garde-cle-privee.sh"
    else ko "generate-key-pair $k : $(grep -m1 -i error "$B/cles/$k.out" | cut -c1-160)"; return 1; fi
  done
  echo "### prédicats (valeurs relues dans les journaux archivés)"
  lien predicats "$B/p" || { ko "prédicats"; return 1; }
  lien temoins "$B/p" || { ko "témoins"; return 1; }
  echo "### L1 à L4 : attest-blob (clé lien) puis vérification par cosign et par le contrôle indépendant"
  for c in $CAS; do
    f=$(fichier "$c")
    if attester "$B/cles/lien.key" "$B/p/$c.json" "$f" "$B/b/$c.json"; then echo "OK   attest-blob $c : code 0"
    else ko "attest-blob $c : $(derniere_erreur "$B/b/$c.json.out")"; continue; fi
    cosign_accepte "$c" "$B/b/$c.json" "$B/cles/lien.pub" "$f"
    controle_accepte "$c" "$c" "$B/b/$c.json" "$f"
    lien extraire "$B/b/$c.json" "$R/o5-enonce-$c.json"
  done
  f=$(fichier rpm)
  echo "### T1 : clé étrangère (énoncé du rpm signé par la clé autre)"
  attester "$B/cles/autre.key" "$B/p/rpm.json" "$f" "$B/b/t1.json" || ko "attest-blob t1 : $(derniere_erreur "$B/b/t1.json.out")"
  cosign_refuse "T1 clé étrangère" "$B/b/t1.json" "$B/cles/lien.pub" "$f" 'signature|verif'
  echo "### T2 : lien vers un autre digest (énoncé signé par la clé lien, prédicat faux)"
  for k in autre-manifeste:'lien : manifeste non signé' autre-fichier:'lien : fichier non signé'; do
    attester "$B/cles/lien.key" "$B/p/rpm-${k%%:*}.json" "$f" "$B/b/t2-${k%%:*}.json" || ko "attest-blob t2 ${k%%:*}"
    cosign_accepte "T2 ${k%%:*} (cosign ne lit pas le prédicat)" "$B/b/t2-${k%%:*}.json" "$B/cles/lien.pub" "$f"
    controle_refuse "T2 ${k%%:*}" rpm "$B/b/t2-${k%%:*}.json" "$f" "${k#*:}"
  done
  echo "### T3 : rpm à charge altérée (énoncé valide, signé par la clé lien, sujet = rpm altéré)"
  attester "$B/cles/lien.key" "$B/p/rpm.json" "$B/p/rpm-altere.rpm" "$B/b/t3.json" || ko "attest-blob t3"
  cosign_accepte "T3 (sujet = rpm altéré)" "$B/b/t3.json" "$B/cles/lien.pub" "$B/p/rpm-altere.rpm"
  controle_refuse "T3 charge altérée" rpm "$B/b/t3.json" "$B/p/rpm-altere.rpm" 'B1 : octets différents'
  echo "### T4 : énoncé du rpm signé présenté avec le rpm altéré"
  cosign_refuse "T4 sujet" "$B/b/rpm.json" "$B/cles/lien.pub" "$B/p/rpm-altere.rpm" 'digest|subject|match'
  controle_refuse "T4 sujet" rpm "$B/b/rpm.json" "$B/p/rpm-altere.rpm" 'sujet'
  echo "### contrôles de fin"
  echo "     forme d'un bundle : $(python3 -I -c 'import json,sys; b=json.load(open(sys.argv[1])); print(b.get("mediaType"), "; clés :", ", ".join(sorted(b)))' "$B/b/rpm.json")"
  k=$(prives "$B/b" "$B/p" "$R")
  [ "$k" = 0 ] && echo "OK   aucun en-tête de clé privée dans les bundles, les prédicats ni resultats/" || ko "$k fichier(s) avec en-tête de clé privée hors de $B/cles"
  cp "$B/p/rpm.json" "$R/o5-predicat-rpm.json"
  echo "     archivés : resultats/o5-predicat-rpm.json et resultats/o5-enonce-{$(echo $CAS | tr ' ' ',')}.json"
  echo "à effacer après archivage (chemin littéral ; clés jetables comprises) : $B"
}

e=${1:-}
case "$e" in
  prealables|banc)
    [ "$e" = prealables ] || mkdir -p "$O5"
    L=$R/o5-$e.log
    set +e
    { echo "étape $e commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5.sh $(sha256sum < "$here/o5.sh" | cut -c1-16)… ; o5-lien.py $(sha256sum < "$PY" | cut -c1-16)…"
      "etape_$e"; echo "étape $e finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; } 2>&1 | masquer | tee "$L"; rc=${PIPESTATUS[0]}
    n=$(grep -c -E -e '-----BEGIN (PGP|[A-Z ]*PRIVATE)' "$L" || true)
    if [ "$n" != 0 ]; then : > "$L"; echo "KO   K3 : $n ligne(s) de bloc armuré dans le journal : journal vidé" | tee "$L"; exit 1; fi
    echo "OK   K3 : aucune ligne de bloc armuré (OpenPGP ou clé privée) dans le journal" | tee -a "$L"
    k=$(grep -c '^KO' "$L" || true)
    [ "$k" = 0 ] || { echo "bilan : $k ligne(s) KO" | tee -a "$L"; rc=1; }
    exit "$rc" ;;
  *) echo "usage : $0 prealables | banc" >&2; exit 64 ;;
esac
