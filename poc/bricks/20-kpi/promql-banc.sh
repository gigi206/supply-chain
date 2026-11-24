#!/usr/bin/env bash
# Brique 20, étape 6 et alertes : banc à sec des requêtes, promtool 3.13.5 (archive de la 19 en cache, sha256 revérifié), sur l'hôte, sans
# Prometheus, ni ssh, ni Grafana, ni cluster.
#   1. tableau « KPI supply-chain » : chaque requête de chaque panneau, dans quatre états de l'exportateur (tableau_temoins.py) ;
#   2. mutants du tableau : chacun doit être refusé, sinon les témoins ne voient pas le défaut ;
#   3. alertes-kpi.patch (20) appliqué à une copie des règles de la 19 : check, tests (tous, anciens compris), puis mutants refusés.
# Limite : promtool évalue des séries écrites à la main ; ni la collecte, ni l'affichage de Grafana, ni Alertmanager.
# Usage (racine du dépôt) : [SUFFIXE=-2] bash poc/bricks/20-kpi/promql-banc.sh   (journal : resultats/e6-promql-banc<SUFFIXE>.log)
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e6-promql-banc${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
A=$HOME/.cache/supply-chain-poc/19/amont/prometheus-3.13.5.linux-amd64.tar.gz
SHA=0388822ace519c5a3a8ef556a541ce1b536e21d872f82deded465bd27a5a0699   # PROM_SHA de observabilite.sh (19)
TAB=$here/../19b-journalisation/config/provisioning/dashboards/tableaux/kpi-supply-chain.json
REG=$here/../19-observabilite/config/regles
T=$HOME/.cache/supply-chain-poc/20/promql-banc   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/promql-banc ] || find ~/.cache/supply-chain-poc/20/promql-banc -delete
mkdir -p "$T"
trap 'find ~/.cache/supply-chain-poc/20/promql-banc -delete' EXIT
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
essai() { (cd "$(dirname "$1")" && "$T/promtool" test rules "$(basename "$1")") > "$T/sortie" 2>&1 && echo passé || { grep -qE '^ *(expr|alertname):' "$T/sortie" && echo refusé || echo erreur; }; }
{
  echo "# promql-banc.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), témoins $(sha256sum < "$here/tableau_temoins.py" | cut -c1-16), tableau $(sha256sum < "$TAB" | cut -c1-16), correctif $(sha256sum < "$here/alertes-kpi.patch" | cut -c1-16)"
  s=$(sha256sum < "$A" | cut -c1-64)
  attendu "sha256 de l'archive de Prometheus" "$s" "$SHA"
  [ "$s" = "$SHA" ] || exit 1
  tar -xzf "$A" -C "$T" --strip-components=1 prometheus-3.13.5.linux-amd64/promtool
  "$T/promtool" --version | head -1
  echo "## 1. tableau, quatre états"
  python3 -I "$here/tableau_temoins.py" "$TAB" 2> "$T/compte" > "$T/tableau.yml"; attendu "témoins écrits, requêtes toutes couvertes (code)" "$?" 0; cat "$T/compte"
  attendu "requêtes du tableau" "$(essai "$T/tableau.yml")" passé
  [ "$(tail -1 "$T/sortie")" = "  SUCCESS" ] || sed 's/^/  /' "$T/sortie" | head -60
  echo "## 2. mutants du tableau"
  m=0
  while IFS='|' read -r ou ancien nouveau; do
    m=$((m + 1))
    python3 -I "$here/tableau_temoins.py" "$TAB" "$ou" "$ancien" "$nouveau" > "$T/mutant.yml" 2> "$T/compte" || { cat "$T/compte"; echo > "$T/mutant.yml"; }
    attendu "mutant $m, $ou : « $ancien » devient « $nouveau »" "$(essai "$T/mutant.yml")" refusé
  done <<'FIN'
4A|avg(|sum(
5C|count(kpi_replay_identique)|count(kpi_replay_identique == 1)
10A| - kpi_scan_kev_ecartees|
11A|kpi_scan_ecartees / |1 - kpi_scan_ecartees / 
12A| or (0 * count(kpi_l3_verifie))|
12A|0 * count(kpi_l3_verifie)|vector(0)
13A|on (depot, kev, ouverture)|on (kev, ouverture)
13A|on (depot, kev, ouverture)|on (depot, kev)
14A|on (depot, kev, ouverture)|on (kev, ouverture)
14A|on (depot, kev, ouverture)|on (depot, kev)
16A|min by|max by
17A| or (0 * sum by (depot, digest) (kpi_l3_verifie))|
17A|0 * sum by (depot, digest) (kpi_l3_verifie)|0 * kpi_l3_verifie
18A|, retire)|, retire, depot)
FIN
  echo "## 3. règles d'alerte, alertes-kpi.patch sur une copie"
  mkdir -p "$T/copie/poc/bricks/19-observabilite/config/regles" && cp "$REG/alertes.yml" "$REG/alertes-tests.yml" "$T/copie/poc/bricks/19-observabilite/config/regles/"
  (cd "$T/copie" && git apply "$here/alertes-kpi.patch"); attendu "correctif appliqué (code)" "$?" 0
  R=$T/copie/poc/bricks/19-observabilite/config/regles
  attendu "promtool check rules" "$("$T/promtool" check rules "$R/alertes.yml" > "$T/sortie" 2>&1 && echo valide || echo invalide)" valide
  sed 's/^/  /;s#'"$T"'#T#' "$T/sortie"
  attendu "règles de plus que celles de HEAD" "$(( $(grep -c '^      - alert:' "$R/alertes.yml") - $(grep -c '^      - alert:' "$REG/alertes.yml") ))" 2
  attendu "toute alerte a une ligne expr" "$(( $(grep -c '^      - alert:' "$R/alertes.yml") - $(grep -c '^        expr: ' "$R/alertes.yml") ))" 0
  attendu "tests des règles, anciens et nouveaux" "$(essai "$R/alertes-tests.yml")" passé
  [ "$(tail -1 "$T/sortie")" = "  SUCCESS" ] || sed 's/^/  /' "$T/sortie" | head -60
  m=0
  while IFS='|' read -r quoi ancien nouveau; do
    m=$((m + 1))
    mkdir -p "$T/m$m" && cp "$R/alertes-tests.yml" "$T/m$m/"
    ANCIEN=$ancien NOUVEAU=$nouveau python3 -I -c 'import os, sys
t = open(sys.argv[1], encoding="utf-8").read(); a = os.environ["ANCIEN"].replace("\\n", "\n")
i = t.index("- alert: " + sys.argv[3]); assert t[i:].count(a) >= 1
open(sys.argv[2], "w", encoding="utf-8").write(t[:i] + t[i:].replace(a, os.environ["NOUVEAU"].replace("\\n", "\n"), 1))' "$R/alertes.yml" "$T/m$m/alertes.yml" "$quoi"
    attendu "mutant $m, $quoi : « $ancien » devient « $nouveau »" "$(essai "$T/m$m/alertes-tests.yml")" refusé
  done <<'FIN'
KpiPassageEnRetard|45 * 60|90 * 60
KpiPassageEnRetard|45 * 60|20 * 60
KpiPassageEnRetard| or absent(kpi_exportateur_passage_timestamp_seconds)|
KpiPassageEnRetard|for: 10m|for: 0m
KpiSignatureRefusee|> 0|> 1
KpiSignatureRefusee|kpi_signatures_refusees > 0|sum(kpi_signatures_refusees) > 0
FIN
  echo "## bilan : $N cas, $KO écart(s)"
  [ "$KO" = 0 ]
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$LOG"
exit "${PIPESTATUS[0]}"
