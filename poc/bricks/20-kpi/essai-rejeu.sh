#!/usr/bin/env bash
# Brique 20, étape 7 : kpi-pose.sh au rejeu, à sec, dans un clone jetable (resultats/e7-predictions.md). Hôte seulement, sans ssh : un faux ssh et un
# faux scp, en tête du PATH, échouent et laissent une trace. Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/20-kpi/essai-rejeu.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e7-essai-rejeu${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
T=$HOME/.cache/supply-chain-poc/20/essai-rejeu   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/essai-rejeu ] || find ~/.cache/supply-chain-poc/20/essai-rejeu -delete
mkdir -p "$T/bin"
trap 'find ~/.cache/supply-chain-poc/20/essai-rejeu -delete' EXIT
for x in ssh scp; do printf '#!/bin/sh\necho %s >> "%s/reseau"\nexit 99\n' "$x" "$T" > "$T/bin/$x"; chmod +x "$T/bin/$x"; done
export PATH=$T/bin:$PATH
B=poc/bricks K=poc/bricks/20-kpi N=0 KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
clone() { [ ! -e "$T/c" ] || find ~/.cache/supply-chain-poc/20/essai-rejeu/c -delete; git clone -q --local "$here/../../.." "$T/c"; }
lancer() { (cd "$T/c" && bash "$K/kpi-pose.sh" "$1" < /dev/null; echo "code $?") 2>&1 | tee "$T/sortie" | grep -E '^(OK|KO|refus|clés|écrit|code)' | sed 's/^/  /' >&3; }
dernier() { tail -1 "$T/sortie"; }
{
  exec 3>&1
  echo "# essai-rejeu.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), kpi-pose $(sha256sum < "$here/kpi-pose.sh" | cut -c1-16)"
  echo "## 1 et 2. arbre propre"
  clone; lancer sec; attendu "sec, arbre propre" "$(dernier)" "code 0"
  lancer sec_rejeu; attendu "sec_rejeu, arbre propre" "$(dernier), $(grep -o 'clés sans date : [0-9]*' "$T/sortie")" "code 0, clés sans date : 0"
  attendu "relevé inchangé" "$(git -C "$T/c" diff --quiet HEAD && echo oui || echo non)" oui
  echo "## 3. deux clés réécrites, relevé périmé"
  clone; for f in 08-trust-plane/resultats/chains-cle-publique.pem 07a-sbom-grype/resultats/vex-cle-publique.pem; do echo >> "$T/c/$B/$f"; done
  sed -i '/\tnon-epingle$/d' "$T/c/$K/releve/dates-git.tsv"
  attendu "lignes retirées du relevé" "$(git -C "$T/c" diff --numstat HEAD -- "$K/releve/dates-git.tsv" | cut -f1,2 | tr '\t' ' ')" "0 3"
  lancer sec; attendu "sec : clés, relevé" "$(dernier), $(grep -c '^KO' "$T/sortie") KO, $(grep -o 'différentes de HEAD : [0-9]*' "$T/sortie")" "code 1, 2 KO, différentes de HEAD : 2"
  lancer sec_rejeu; attendu "sec_rejeu" "$(dernier), $(grep -o 'clés sans date : [0-9]*' "$T/sortie")" "code 0, clés sans date : 2"
  attendu "relevé redevenu celui de HEAD" "$(git -C "$T/c" diff --quiet HEAD -- "$K/releve" && echo oui || echo non)" oui
  echo "## témoin de la tolérance exacte : SANS_DATE forcé à 1"
  sed -i 's/^  SANS_DATE=$(cles_changees) ||.*/  SANS_DATE=1/' "$T/c/$K/kpi-pose.sh"
  attendu "copie modifiée" "$(grep -c '^  SANS_DATE=1$' "$T/c/$K/kpi-pose.sh")" 1
  lancer sec_rejeu; attendu "sec_rejeu, tolérance trop basse" "$(dernier), $(grep '^KO' "$T/sortie" | sed 's/^KO   //' | paste -sd ';')" "code 1, clés sans date : 2 (attendu : 1)"
  echo "## 4. clé de Chains étrangère"
  clone; cp "$T/c/$B/07a-sbom-grype/resultats/g6-temoin-cle-publique.pem" "$T/c/$B/08-trust-plane/resultats/chains-cle-publique.pem"
  lancer sec_rejeu; attendu "sec_rejeu, clé étrangère" "$(dernier), signatures refusées $(grep -c '^KO   signatures refusées' "$T/sortie") KO" "code 1, signatures refusées 1 KO"
  echo "## 5. pose_rejeu sans REJEU"
  clone; lancer pose_rejeu; attendu "pose_rejeu refusée, ssh ou scp appelés" "$([ "$(dernier)" = "code 0" ] && echo lancée || echo refusée), $([ -e "$T/reseau" ] && echo oui || echo non)" "refusée, non"
  echo "## bilan : $N cas, $KO écart(s)"
  [ "$KO" = 0 ]
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$LOG"
exit "${PIPESTATUS[0]}"
