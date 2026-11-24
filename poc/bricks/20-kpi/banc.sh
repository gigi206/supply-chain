#!/usr/bin/env bash
# Brique 20, étape 3 : banc jetable des KPI. Rien de partagé : Zot, clés et attestations jetables dans un espace de noms réseau vide
# (unshare -rn, 127.0.0.1 seul) ; aucune écriture dans le vrai Zot, le cluster ou les VM, aucun téléchargement.
#   1. banc_temoins.py pose 15 sujets témoins (signés, sans VSA, VSA FAILED, signatures fausses, clé d'un autre rôle, signatures
#      illisibles, KEV ouverte puis corrigée) ; e3-banc.log en comptait 9, e3b-banc.log 14 ; 15 depuis l'étape 4 (banc-pins) ;
#   2. le vrai entrees-scan.py (07b) lit chacun des 3 scans de banc-kev ; ses lignes remplacent Loki (Alloy et Loki non exercés) ;
#   3. recalcul.py (BANC=1, signatures vérifiées par cosign) et tools/metrics-exporter (signatures comptées, puis vérifiées par
#      /usr/bin/openssl), puis banc_comparer.py ;
#   4. étape 4 : dates des clés et des pins (RELEVE du banc), journal injecté, même sortie sous Python 3.13 (mise) ;
#   5. exportateur : code 2 et fichier inchangé si SIGNATURES est absent ou inconnu, si une clé est absente, illisible ou P-384, si
#      openssl est inutilisable, refuse tout ou accepte tout, si le vecteur est absent ou différent, si le relevé est illisible ou absent, si
#      Zot est injoignable ;
#   6. lecteur_loki.py (lecteur_banc.py, serveur factice) : code 2 et fichier inchangé sur une réponse tronquée, en erreur ou illisible.
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/20-kpi/banc.sh   (journal : resultats/e4-banc<SUFFIXE>.log)
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
RACINE=$(cd "$here/../../.." && pwd)
LOG=$here/resultats/e4-banc${SUFFIXE:-}.log
export T=$HOME/.cache/supply-chain-poc/20/banc REG=127.0.0.1:15020
export CA=$T/zot.crt

if [ "${1:-}" = ns ]; then
  set -e
  ip link set lo up
  echo "# routes dans l'espace de noms : $(ip route | wc -l)"
  zot serve "$T/zot.json" > "$T/zot.out" 2>&1 & zp=$!
  trap 'kill $zp 2> /dev/null || true' EXIT
  for _ in $(seq 40); do curl -fsS --cacert "$CA" "https://$REG/v2/" > /dev/null 2>&1 && break; sleep 0.25; done
  export SSL_CERT_FILE=$CA
  cosign signing-config create --out "$T/vide.json" > /dev/null 2>&1
  for k in chains scanner vex vsa etrangere temoin; do
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$T/cle/$k.pem" 2> /dev/null
    (cd "$T/cle" && COSIGN_PASSWORD='' cosign import-key-pair --yes --key "$k.pem" --output-key-prefix "$k" > "$T/tmp/import.log" 2>&1) \
      || { cat "$T/tmp/import.log"; exit 1; }
  done
  python3 -I "$here/banc_temoins.py" poser > "$T/scans"
  S=$(sed -n 's/^SCANS=//p' "$T/scans")
  mkdir -p "$T/etat"; : > "$T/entrees.prom"; : > "$T/journal-scans"; : > "$T/comptees.prom"; : > "$T/verifiees.prom"
  for n in 1 2 3; do
    python3 -I "$here/banc_temoins.py" scan-kev "$n"
    SCANS=$S SORTIE=$T/entrees.prom ETAT=$T/etat python3 -I "$here/../07a-sbom-grype/systemd/entrees-scan.py" >> "$T/journal-scans"
  done
  # un quatrième passage, sans nouveau scan : résumé seul, sans « liste émise »
  SCANS=$S SORTIE=$T/entrees.prom ETAT=$T/etat python3 -I "$here/../07a-sbom-grype/systemd/entrees-scan.py" >> "$T/journal-scans"
  echo "entrees-scan.py : $(grep -c '^{' "$T/journal-scans") lignes d'entrées, $(grep -c 'liste émise' "$T/journal-scans") listes émises, $(grep -c '^entrées ' "$T/journal-scans") résumés"
  export PRODUITS="banc-complet banc-sans-vsa banc-vsa-failed banc-forge banc-prov-forgee banc-prov-seule banc-prov-tache banc-sans-sig banc-mauvais-role banc-role-prov banc-sig-forgee banc-illisible banc-att-illisible banc-kev banc-pins"
  set +e
  echo "## recalcul signé"
  BANC=1 CLES_BANC=$T/cle NON_VERIFIEES=13 N_SUJETS=15 LOKI_BANC=$T/journal-scans python3 -I "$here/recalcul.py" > "$T/recalcul.log" 2>&1
  a=$?; cat "$T/recalcul.log"
  X=$RACINE/tools/metrics-exporter/metrics_exporter.py
  python3 -I -c 'import runpy, sys; sys.stdout.buffer.write(runpy.run_path(sys.argv[1])["VECTEUR_PUB"])' "$X" > "$T/cle/vecteur.pub"
  c64() { printf "$1%.0s" $(seq 64); }
  { printf '# relevé du banc\n'
    printf 'cle\t%s\tchains.pub\t1700000011\n' "$(sha256sum < "$T/cle/chains.pub" | cut -c1-64)"
    printf 'cle\t%s\tscanner.pub\t1700000012\n' "$(sha256sum < "$T/cle/scanner.pub" | cut -c1-64)"
    printf 'cle\t%s\tvsa.pub\t1700000013\n' "$(sha256sum < "$T/cle/temoin.pub" | cut -c1-64)"
    printf 'cle\t%s\ttsa.pem\t1700000014\n' "$(c64 9)"
    printf 'pin\t%s\t1700000001\tpresent\n' "$(c64 1)"
    printf 'pin\t%s\t1700000002\tpresent\npin\t%s\t1700000003\tretire\npin\t%s\t-\tnon-epingle\n' "$(c64 2)" "$(c64 3)" "$(c64 4)"
    printf 'pin\t%s\t1700000006\tpresent\npin\t%s\t1700000007\tpresent\npin\t%s\t1700000008\tpresent\n' "$(c64 6)" "$(c64 7)" "$(c64 8)"
  } > "$T/releve.tsv"
  export RELEVE=$T/releve.tsv
  echo "## exportateur, signatures comptées"
  SIGNATURES=comptees JOURNAL=$T/journal-scans SORTIE=$T/comptees.prom /usr/bin/python3 -I "$X"; b=$?
  sed 's/^/PROM|comptees|/' "$T/comptees.prom"
  echo "## exportateur, signatures vérifiées"
  SIGNATURES=verifiees CLES=$T/cle JOURNAL=$T/journal-scans SORTIE=$T/verifiees.prom /usr/bin/python3 -I "$X"; e=$?
  sed 's/^/PROM|verifiees|/' "$T/verifiees.prom"
  echo "## comparaison (code du recalcul $a, de l'exportateur : comptées $b, vérifiées $e)"
  python3 -I "$here/banc_comparer.py" "$T/recalcul.log" "$T/comptees.prom" "$T/verifiees.prom"; c=$?
  echo "## journal injecté, Python 3.13"
  ko4=0
  attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; ko4=$((ko4 + 1)); fi; }
  cp "$T/journal-scans" "$T/journal-injecte"
  jq -nc '{depot: "builds/scan/banc-kev", scannedAt: "2026-11-10T00:00:00Z", id: "x", kev: true, kevCves: ["a\"} 1\nfaux 1"]}' >> "$T/journal-injecte"
  : > "$T/injecte.prom"; : > "$T/py313.prom"
  SIGNATURES=verifiees CLES=$T/cle JOURNAL=$T/journal-injecte SORTIE=$T/injecte.prom /usr/bin/python3 -I "$X" > /dev/null
  attendu "journal injecté : lignes mal formées dans le .prom" "$(grep -cvE '^kpi_[a-z0-9_]+(\{([a-z]+="[A-Za-z0-9._:/+-]*",?)+\})? [0-9]+$' "$T/injecte.prom")" 0
  attendu "journal injecté : séries de KEV illisible" "$(grep -c 'kev="illisible"' "$T/injecte.prom")" 1
  SIGNATURES=verifiees CLES=$T/cle JOURNAL=$T/journal-scans SORTIE=$T/py313.prom python3 -I "$X" > /dev/null
  attendu "même sortie sous $(python3 --version | cut -d. -f1,2) (heure du passage exclue)" \
    "$(diff <(grep -v '^kpi_exportateur_passage' "$T/verifiees.prom") <(grep -v '^kpi_exportateur_passage' "$T/py313.prom") | wc -l)" 0
  attendu "sortie sous Python 3.13 non vide" "$([ "$(wc -l < "$T/py313.prom")" -gt 100 ] && echo oui || echo non)" oui
  # journal malformé (un porteur d'un certificat de la CA écrit dans Loki, limite de D16) : les séries vérifiées ne sont pas figées
  for v in '{"kev":true' '{"scannedAt":"2026-11-10T00:00:00Z","id":"x","kev":true}' 'entrées builds/scan/banc-kev=1@demain (liste émise)'; do
    cp "$T/journal-scans" "$T/journal-injecte"; printf '%s\n' "$v" >> "$T/journal-injecte"; : > "$T/injecte.prom"
    SIGNATURES=verifiees CLES=$T/cle JOURNAL=$T/journal-injecte SORTIE=$T/injecte.prom /usr/bin/python3 -I "$X" > /dev/null; i=$?
    attendu "journal malformé ($v) : code, séries de KEV, illisible, autres séries différentes" \
      "$i $(grep -c '^kpi_kev_' "$T/injecte.prom") $(sed -n 's/^kpi_exportateur_journal_illisible //p' "$T/injecte.prom") $(diff <(grep -vE '^kpi_(kev|exportateur)_' "$T/verifiees.prom") <(grep -vE '^kpi_(kev|exportateur)_' "$T/injecte.prom") | grep -c '^[<>]')" "0 0 1 0"
  done
  echo "## lecteur de Loki, serveur factice"
  python3 -I "$here/lecteur_banc.py" "$RACINE/tools/metrics-exporter/lecteur_loki.py"; l=$?
  echo "## arrêts de l'exportateur : code 2, motif attendu, fichier inchangé"
  ko=0; h=$(sha256sum < "$T/verifiees.prom")
  arret() { # nom, motif attendu, commande
    local n=$1 m=$2 d; shift 2
    "$@" > /dev/null 2> "$T/tmp/arret"; d=$?
    if [ "$d" = 2 ] && grep -q "$m" "$T/tmp/arret" && [ -s "$T/verifiees.prom" ] && [ "$h" = "$(sha256sum < "$T/verifiees.prom")" ]; then echo "OK   $n"
    else echo "KO   $n : code $d, $(head -1 "$T/tmp/arret")"; ko=$((ko + 1)); fi
  }
  for v in absente illisible p384 vide; do
    mkdir -p "$T/cle-$v"; cp "$T/cle/chains.pub" "$T/cle/scanner.pub" "$T/cle/vex.pub" "$T/cle/vecteur.pub" "$T/cle-$v/"
  done
  echo "pas une clé" > "$T/cle-illisible/vsa.pub"; : > "$T/cle-vide/vsa.pub"
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 2> /dev/null | openssl pkey -pubout -out "$T/cle-p384/vsa.pub"
  export SORTIE=$T/verifiees.prom
  arret "SIGNATURES absent" "SIGNATURES : comptees ou verifiees" /usr/bin/python3 -I "$X"
  arret "SIGNATURES inconnu" "SIGNATURES : comptees ou verifiees" env SIGNATURES=oui CLES="$T/cle" /usr/bin/python3 -I "$X"
  arret "CLES absent" "KeyError" env SIGNATURES=verifiees /usr/bin/python3 -I "$X"
  for v in absente illisible p384 vide; do
    arret "clé de la VSA $v" "clé vsa.pub absente, illisible ou pas P-256" env SIGNATURES=verifiees CLES="$T/cle-$v" /usr/bin/python3 -I "$X"
  done
  arret "openssl inutilisable (/dev/null monté dessus)" "PermissionError" unshare -m bash -c 'mount --bind /dev/null /usr/bin/openssl && SIGNATURES=verifiees CLES=$T/cle exec /usr/bin/python3 -I "$0"' "$X"
  cp -r "$T/cle" "$T/cle-sans"; find "$T/cle-sans/vecteur.pub" -delete
  cp -r "$T/cle" "$T/cle-autre"; cp "$T/cle/temoin.pub" "$T/cle-autre/vecteur.pub"
  arret "vecteur absent" "FileNotFoundError" env SIGNATURES=verifiees CLES="$T/cle-sans" /usr/bin/python3 -I "$X"
  arret "vecteur différent" "vecteur.pub différent" env SIGNATURES=verifiees CLES="$T/cle-autre" /usr/bin/python3 -I "$X"
  cp /usr/bin/openssl "$T/openssl-vrai"
  for v in 0 1; do
    printf '#!/bin/bash\nif [ "$1" = dgst ]; then cat > /dev/null; exit %s; fi\nexec %s/openssl-vrai "$@"\n' "$v" "$T" > "$T/openssl-$v"; chmod 755 "$T/openssl-$v"
  done
  faux() { unshare -m bash -c 'mount --bind "$T/openssl-$1" /usr/bin/openssl && SIGNATURES=verifiees CLES=$T/cle exec /usr/bin/python3 -I "$0"' "$X" "$1"; }
  arret "openssl qui accepte tout" "signature fausse acceptée" faux 0
  arret "openssl qui refuse tout" "signature bonne refusée" faux 1
  printf 'pin\tx\tdemain\tpresent\n' > "$T/mauvais.tsv"
  arret "relevé illisible" "ValueError" env SIGNATURES=verifiees CLES="$T/cle" RELEVE="$T/mauvais.tsv" /usr/bin/python3 -I "$X"
  arret "relevé absent" "FileNotFoundError" env SIGNATURES=verifiees CLES="$T/cle" RELEVE="$T/nulle-part" /usr/bin/python3 -I "$X"
  kill "$zp"; wait "$zp" 2> /dev/null
  arret "Zot arrêté" "URLError" env SIGNATURES=verifiees CLES="$T/cle" /usr/bin/python3 -I "$X"
  echo "## bilan des arrêts : 15 cas, $ko écart(s)"
  echo "## bilan des contrôles de l'étape 4 : 7 cas, $ko4 écart(s) ; lecteur : code $l"
  [ "$a$b$c$e$ko$ko4$l" = 0000000 ]; exit $?
fi

[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
[ ! -e ~/.cache/supply-chain-poc/20/banc ] || find ~/.cache/supply-chain-poc/20/banc -delete
trap 'find ~/.cache/supply-chain-poc/20/banc -delete 2> /dev/null' EXIT
mkdir -p "$T/cle" "$T/tmp" "$T/zot"; chmod 700 "$T/cle"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=zot-jetable -addext subjectAltName=IP:127.0.0.1 \
  -addext basicConstraints=critical,CA:TRUE -keyout "$T/cle/zot.key" -out "$T/zot.crt" 2> /dev/null
jq -n --arg r "$T/zot" --arg c "$T/zot.crt" --arg k "$T/cle/zot.key" '{distSpecVersion: "1.1.1", storage: {rootDirectory: $r, gc: false},
  http: {address: "127.0.0.1", port: "15020", tls: {cert: $c, key: $k}}, log: {level: "error"}}' > "$T/zot.json"
{
  echo "# banc.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), scripts $(cat "$here/banc.sh" "$here/banc_temoins.py" "$here/banc_comparer.py" "$here/recalcul.py" "$here/kpi.py" "$here/lecteur_banc.py" "$RACINE/tools/metrics-exporter/lecteur_loki.py" "$RACINE/tools/metrics-exporter/metrics_exporter.py" | sha256sum | cut -c1-16)"
  echo "# cosign $(cosign version 2> /dev/null | awk '/GitVersion/{print $2}'), zot $(zot --version 2>&1 | grep -o 'v2[0-9.]*' | head -1), exportateur $(/usr/bin/python3 --version), $(/usr/bin/openssl version | cut -d' ' -f1,2)"
  unshare -rn bash "$here/banc.sh" ns
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
