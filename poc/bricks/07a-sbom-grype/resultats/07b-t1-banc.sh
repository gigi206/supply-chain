#!/usr/bin/env bash
# Brique 07b, tranche 1 : banc de systemd/entrees-scan.py, à sec. Rien n'est posé ; aucune écriture dans Zot, le cluster ou les VM.
#   1. comptes attendus calculés par jq sur les témoins archivés, indépendamment du script ;
#   2. banc local à faux Zot (07b-t1-banc.py) : 12 cas ;
#   3. passage réel depuis l'hôte, en lecture anonyme de Zot, sortie et état dans un dossier temporaire hors dépôt ;
#      comptes comparés à jq sur les énoncés relus au même moment. Seuls des comptes sont écrits au journal.
# Usage (racine du dépôt, outils de mise.toml) : poc/bricks/07a-sbom-grype/resultats/07b-t1-banc.sh > <journal>
set -euo pipefail
export LC_ALL=C
B=poc/bricks/07a-sbom-grype
R=$B/resultats
SCRIPT=$B/systemd/entrees-scan.py
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
REG=192.168.161.13:5000
mkdir -p "$HOME/.cache/supply-chain-poc/07a"
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "entrees-scan.py : $(sha256sum < "$SCRIPT" | cut -c1-16)…, python3 de l'hôte : $(python3 --version)"

# jq : n, gravités, KEV, avec correctif ; scannedAt en secondes par date -ud (le témoin de G6 porte un décalage, que fromdate
# ne lit pas). $1 : chemin du prédicat dans le fichier.
attendus() {
  jq -c --argjson t "$(date -ud "$(jq -r "$1 | .scannedAt" "$2")" +%s)" "$1"' | {n: (.vulnerabilities | length),
    g: (.vulnerabilities | group_by(.severity) | map({(.[0].severity): length}) | add // {}),
    kev: (.vulnerabilities | map(select(.kev)) | length), fix: (.vulnerabilities | map(select((.fixedIn | length) > 0)) | length), t: $t}' "$2"
}
A=$(jq -nc --argjson app "$(attendus .predicate "$R/07b-t1-predicat-sample-app.json")" \
  --argjson deb "$(attendus .predicate "$R/07b-t1-predicat-sample-app-deb.json")" \
  --argjson g6 "$(attendus . "$R/g6-predicat-kev.json")" '{app: $app, deb: $deb, g6: $g6}')
echo "## 1. attendus (jq)"
printf '%s\n' "$A" | jq -r 'to_entries[] | "\(.key) : \(.value.n) entrées, \(.value.g | to_entries | map("\(.key) \(.value)") | join(", ")), KEV \(.value.kev), avec correctif \(.value.fix), scannedAt \(.value.t)"'

echo "## 2. banc local, faux Zot"
KO=0
python3 -I "$R/07b-t1-banc.py" "$SCRIPT" <(printf '%s\n' "$A") "$R/07b-t1-predicat-sample-app.json" \
  "$R/07b-t1-predicat-sample-app-deb.json" "$R/g6-predicat-kev.json" || KO=$((KO + 1))

echo "## 3. passage réel, lecture anonyme de Zot depuis l'hôte"
D_APP=sha256:$(jq -r '.subject[0].digest.sha256' "$R/07b-t1-predicat-sample-app.json")
D_DEB=sha256:$(jq -r '.subject[0].digest.sha256' "$R/07b-t1-predicat-sample-app-deb.json")
T=~/.cache/supply-chain-poc/07a/t1-reel   # chemin écrit en entier : il est effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/07a/t1-reel ] || find ~/.cache/supply-chain-poc/07a/t1-reel -delete
trap 'find ~/.cache/supply-chain-poc/07a/t1-reel -delete' EXIT
mkdir -p "$T/etat"
: > "$T/s.prom"
# Énoncé le plus récent relu par curl et jq, indépendamment du script, juste avant son passage.
releve() {
  local m l
  m=$(curl -fsS --cacert "$CA" "https://$REG/v2/$1/referrers/$2" | jq -r '.manifests
    | map(select(.annotations["dev.sigstore.bundle.predicateType"] == "https://supply-chain.example/scan/v1"))
    | sort_by(.annotations["org.opencontainers.image.created"]) | .[-1].digest')
  l=$(curl -fsS --cacert "$CA" -H 'Accept: application/vnd.oci.image.manifest.v1+json' "https://$REG/v2/$1/manifests/$m" | jq -r '.layers[0].digest')
  curl -fsS --cacert "$CA" "https://$REG/v2/$1/blobs/$l" | jq -r '.dsseEnvelope.payload | @base64d'
}
releve builds/scan/sample-app "$D_APP" > "$T/app.json"
releve builds/scan/sample-app-deb "$D_DEB" > "$T/deb.json"
AR=$(jq -nc --argjson app "$(attendus .predicate "$T/app.json")" --argjson deb "$(attendus .predicate "$T/deb.json")" '{app: $app, deb: $deb}')
for d in app deb; do
  echo "énoncé relu ($d) : scannedAt $(jq -r .predicate.scannedAt "$T/$d.json"), identique au témoin archivé : $(cmp -s <(jq -S . "$T/$d.json") <(jq -S . "$R/07b-t1-predicat-sample-app$([ $d = deb ] && echo -deb).json") && echo oui || echo non)"
done
passage() {
  REG=$REG CA=$CA SCANS="builds/scan/sample-app@$D_APP builds/scan/sample-app-deb@$D_DEB" SORTIE=$T/s.prom ETAT=$T/etat \
    python3 -I "$SCRIPT" > "$T/sortie.txt"
}
for n in 1 2; do
  rc=0; passage || rc=$?
  lignes=$(grep -c '^{' "$T/sortie.txt" || true)
  echo "passage $n : rc $rc, $lignes lignes d'entrée, $(wc -l < "$T/s.prom") séries, résumé : $(grep -v '^{' "$T/sortie.txt")"
  [ "$n" = 1 ] && cp "$T/s.prom" "$T/s1.prom" && cp "$T/sortie.txt" "$T/sortie1.txt"
  [ "$n" = 2 ] && { [ "$lignes" = 0 ] && cmp -s "$T/s.prom" "$T/s1.prom" && echo "OK   passage 2 : aucune ligne d'entrée, comptes identiques" \
    || { echo "KO   passage 2"; KO=$((KO + 1)); }; }
  [ "$n" = 1 ] && { [ "$lignes" = "$(printf '%s\n' "$AR" | jq '.app.n + .deb.n')" ] && echo "OK   passage 1 : lignes d'entrée = jq (app + deb)" \
    || { echo "KO   passage 1 : $lignes lignes d'entrée"; KO=$((KO + 1)); }; }
done
# Comptes du script comparés à jq, série par série ; les séries sont des comptes, archivées telles quelles.
compare() { # $1 dépôt, $2 clé dans AR
  local att obt
  att=$(printf '%s\n' "$AR" | jq -r --arg k "$2" '.[$k] as $a | (["Critical","High","Medium","Low","Negligible","Unknown","autre"]
    | map("scan_entrees\(.) \($a.g[.] // 0)") | .[]), "scan_entrees_kev \($a.kev)", "scan_entrees_avec_correctif \($a.fix)",
    "scan_entrees_scanne_timestamp_seconds \($a.t)"')
  obt=$(grep "depot=\"$1\"" "$T/s.prom" | sed -E 's/\{depot="[^"]*"(,gravite="([^"]*)")?\}/\2/')
  if [ "$att" = "$obt" ]; then echo "OK   séries de $1 = jq"; else echo "KO   séries de $1"; diff <(printf '%s\n' "$att") <(printf '%s\n' "$obt") || true; KO=$((KO + 1)); fi
}
compare builds/scan/sample-app app
compare builds/scan/sample-app-deb deb
echo "séries écrites :"
sed 's/^/  /' "$T/s.prom"
echo "volume émis vers le journal : passage 1, $(wc -c < "$T/sortie1.txt") octets ($(grep -c '^{' "$T/sortie1.txt") lignes d'entrée et le résumé) ; passage 2, $(wc -c < "$T/sortie.txt") octets"
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "## bilan : $KO KO"
[ "$KO" = 0 ]
