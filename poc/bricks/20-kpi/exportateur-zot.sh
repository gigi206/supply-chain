#!/usr/bin/env bash
# Brique 20, étape 3 (complément) : exportateur lancé depuis l'hôte sur le vrai Zot, en lecture anonyme, puis recalcul signé et
# comparaison (comparer_zot.py). Rien n'est posé ; la sortie reste sous ~/.cache/supply-chain-poc/20/exportateur-zot, effacé à la fin.
# Essai openssl (e3b) : deux passages de l'exportateur, SIGNATURES=verifiees, avec les clés publiques versionnées, puis avec la clé
# étrangère g6-temoin à la place des quatre (tout doit être refusé). Le passage e3-exportateur-zot.log ne vérifiait rien.
# Étape 4 (journal e4) : RELEVE versionné (dates des clés et des pins) et JOURNAL écrit par lecteur_loki.py, par l'API de Grafana avec le
# compte auditeur de l'hôte (mot de passe lu dans son fichier par le lecteur, jamais en argument).
# Usage (racine du dépôt) : [SUFFIXE=-1] mise exec -- bash poc/bricks/20-kpi/exportateur-zot.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e4-exportateur-zot${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
T=$HOME/.cache/supply-chain-poc/20/exportateur-zot   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/exportateur-zot ] || find ~/.cache/supply-chain-poc/20/exportateur-zot -delete
trap 'find ~/.cache/supply-chain-poc/20/exportateur-zot ~/.cache/supply-chain-poc/20/recalcul -delete 2> /dev/null' EXIT
mkdir -p "$T/cles" "$T/temoin"; : > "$T/kpi.prom"; : > "$T/temoin.prom"
X=$here/../../../tools/metrics-exporter/metrics_exporter.py
B=$here/..
cp "$B/08-trust-plane/resultats/chains-cle-publique.pem" "$T/cles/chains.pub"
cp "$B/07a-sbom-grype/resultats/scanner-cle-publique.pem" "$T/cles/scanner.pub"
cp "$B/07a-sbom-grype/resultats/vex-cle-publique.pem" "$T/cles/vex.pub"
cp "$B/10-independent-replay/resultats/vsa-cle-publique.pem" "$T/cles/vsa.pub"
cp "$B/08-trust-plane/resultats/tsa-chaine.pem" "$T/cles/tsa.pem"
python3 -I -c 'import runpy, sys; sys.stdout.buffer.write(runpy.run_path(sys.argv[1])["VECTEUR_PUB"])' "$X" | tee "$T/temoin/vecteur.pub" > "$T/cles/vecteur.pub"
: > "$T/journal"
for k in chains scanner vex vsa; do cp "$B/07a-sbom-grype/resultats/g6-temoin-cle-publique.pem" "$T/temoin/$k.pub"; done
export REG=192.168.161.13:5000 CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt PRODUITS="sample-app sample-app-deb sample-app-rpm"
{
  echo "# exportateur-zot.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), exportateur $(sha256sum < "$X" | cut -c1-16), $(/usr/bin/python3 --version), $(/usr/bin/openssl version | cut -d' ' -f1,2)"
  GRAFANA=https://192.168.161.13:3001 UTILISATEUR=auditeur MDP=$HOME/.cache/supply-chain-poc/08/secrets/grafana-auditeur.password \
    SORTIE=$T/journal /usr/bin/python3 -I "$here/../../../tools/metrics-exporter/lecteur_loki.py"; e=$?
  echo "JOURNAL|$(grep -c 'liste émise' "$T/journal") résumés|$(grep -c '^{' "$T/journal") entrées KEV|$(grep -vc -e 'liste émise' -e '"kev":true' "$T/journal") autres lignes"
  debut=$(date -u +%s%3N)
  RELEVE=$here/releve/dates-git.tsv JOURNAL=$T/journal SIGNATURES=verifiees CLES=$T/cles SORTIE=$T/kpi.prom /usr/bin/python3 -I "$X"; a=$?
  echo "durée de l'exportateur : $(($(date -u +%s%3N) - debut)) ms"
  sed 's/^/PROM|/' "$T/kpi.prom"
  SIGNATURES=verifiees CLES=$T/temoin SORTIE=$T/temoin.prom /usr/bin/python3 -I "$X"; d=$?
  sed 's/^/PROM|témoin|/' "$T/temoin.prom"
  python3 -I "$here/recalcul.py" > "$T/recalcul.log" 2>&1; b=$?
  grep -E '^(KPI\||DETAIL\|builds|KO|ARRÊT|##)' "$T/recalcul.log"
  echo "## comparaison (code de l'exportateur $a, avec la clé étrangère $d, du recalcul $b)"
  python3 -I "$here/comparer_zot.py" "$T/recalcul.log" "$T/kpi.prom" "$T/temoin.prom"; c=$?
  echo "## codes : lecteur $e, exportateur $a, clé étrangère $d, recalcul $b, comparaison $c"
  [ "$a$b$c$d$e" = 00000 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
