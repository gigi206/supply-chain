#!/usr/bin/env bash
# Brique 07c, constat hors périmètre (« s4d.sh de la 06 compile le deb en Go 1.26.10 ; GO-2026-6859 sur le deb non mesuré ») :
# relevé en lecture seule, par l'auditeur dans Grafana, des entrées GO-2026-6859 dans les listes que entrees-scan écrit dans
# Loki (une ligne par entrée et par scan, 07b tranche 1). Comptes et étiquettes seulement : aucune ligne brute archivée.
# Rien n'est écrit, ni sur les VM, ni dans Zot, ni dans Grafana.
# Usage (racine du dépôt) : bash poc/bricks/07c-reconstruction-go/deb-go-6859.sh > <journal>
set -uo pipefail
export LC_ALL=C
O8=$HOME/.cache/supply-chain-poc/08
CA=$O8/pki/ca-poc.crt
GRAF=https://192.168.161.13:3001
N=0; KO=0
T=$HOME/.cache/supply-chain-poc/07c/deb-go-6859   # chemin écrit en entier : effacé à la sortie (correction du 24/11 : plus rien dans /tmp)
[ ! -e ~/.cache/supply-chain-poc/07c/deb-go-6859 ] || find ~/.cache/supply-chain-poc/07c/deb-go-6859 -delete
mkdir -p "$T"
trap 'find ~/.cache/supply-chain-poc/07c/deb-go-6859 -delete' EXIT
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
loki() { # requête LogQL instantanée, réponse JSON de /api/ds/query ; mot de passe par l'entrée standard de curl
  local t
  t=$(date -u +%s)000
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$CA" -H 'Content-Type: application/json' -X POST "$GRAF/api/ds/query" \
      -d "$(jq -nc --arg q "$1" --arg t "$t" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant"}]}')"
}
lignes() { jq -r '[.results.A.frames[]? | "\(.schema.fields[1].labels // {} | tojson) \(.data.values[1][0])"] | sort | .[]'; }
S='{source="journal", unite="entrees-scan.service"}'
echo "# GO-2026-6859 dans les scans signés, relevé dans Loki, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
echo "## entrées par scan (24 h)"
loki "sum by (depot, scannedAt) (count_over_time($S | json | id=~\".+\" [24h]))" | lignes | tee "$T/scans"
echo "## entrées GO-2026-6859 par scan (24 h)"
loki "sum by (depot, scannedAt, id, severity, kev, fixedIn, package) (count_over_time($S |= \"GO-2026-6859\" | json [24h]))" | lignes > "$T/ids"
cat "$T/ids"
dernier() { grep "\"depot\":\"$1\"" "$T/scans" | sed -E 's/.*"scannedAt":"([^"]+)".*/\1/' | sort | tail -1; }
D=$(dernier builds/scan/sample-app-deb); I=$(dernier builds/scan/sample-app)
echo "dernier scan du deb : $D ; dernier scan de l'image : $I"
attendu "GO-2026-6859 dans le dernier scan du deb" "$(grep -c "\"depot\":\"builds/scan/sample-app-deb\".*\"scannedAt\":\"$D\"" "$T/ids")" 1
attendu "GO-2026-6859 hors KEV dans le dernier scan du deb" "$(grep "\"depot\":\"builds/scan/sample-app-deb\".*\"scannedAt\":\"$D\"" "$T/ids" | grep -c '"kev":"false"')" 1
attendu "GO-2026-6859 dans le dernier scan de l'image (f5e6bcb0, Go 1.26.11)" "$(grep -c "\"depot\":\"builds/scan/sample-app\".*\"scannedAt\":\"$I\"" "$T/ids")" 0
echo "## bilan : $N cas, $KO écart(s)"
[ "$KO" = 0 ]
