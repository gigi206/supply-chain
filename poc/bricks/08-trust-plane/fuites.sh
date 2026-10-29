#!/usr/bin/env bash
# Brique 08 : aucun secret de l'hôte ne doit apparaître dans les journaux des VM (fuite du jeton k3s
# dans le journal sudo en J1). Pour chaque VM : journal systemd complet (sudo compris), fichiers *.log
# de /var/log et journal d'audit de l'API, rapatriés sur l'hôte (0600), puis cherchés avec chaque secret
# de ~/.cache/supply-chain-poc/08/secrets comme motif (grep -F -f : jamais en argument de commande).
# Clés PEM : chaque ligne du corps base64 est un motif. Attendu : 0 partout. Témoin positif : une valeur
# aléatoire non secrète, écrite dans le journal de chaque VM (logger), doit être retrouvée.
#
# Usage (racine du dépôt) : mise run confiance:fuites [-- <libellé>]   (journal : resultats/fuites-<libellé>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}
S=$O/secrets
W=$O/travail/fuites
lib=${1:-j2}
rm -rf "$W" && (umask 077 && mkdir -p "$W")
trap 'rm -rf "$W"' EXIT
exec > >(tee "$R/fuites-$lib.log") 2>&1
echo "# fuites.sh $lib, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Motifs : une ligne par secret ; corps base64 pour les clés PEM.
for f in "$S"/*; do
  [ -f "$f" ] || continue
  grep -v -e '^-----' -e '^$' "$f" > "$W/motif-${f##*/}" || true
done

temoin=$(openssl rand -hex 16)
printf '%s\n' "$temoin" > "$W/temoin"
ko=0
for vm in sc-confiance sc-build sc-stockage; do
  "$here/ssh.sh" "$vm" "logger -t fuites-temoin $temoin" < /dev/null
  (umask 077 && "$here/ssh.sh" "$vm" 'sudo journalctl -o cat --no-pager; sudo find /var/log /var/lib/rancher/k3s/server/logs -type f -name "*.log" -exec cat {} + 2>/dev/null' \
    < /dev/null > "$W/$vm.txt" || true)
  echo "## $vm : $(wc -l < "$W/$vm.txt") lignes de journaux"
  n=$(grep -c -F -f "$W/temoin" "$W/$vm.txt" || true)
  [ "$n" -ge 1 ] && echo "témoin retrouvé ($n)" || { echo "KO   témoin absent : contrôle inopérant sur $vm" >&2; ko=1; }
  for m in "$W"/motif-*; do
    [ -s "$m" ] || continue
    n=$(grep -c -F -f "$m" "$W/$vm.txt" || true)
    printf '%-4s %s\n' "$n" "${m##*/motif-}"
    [ "$n" = 0 ] || ko=1
  done
done
[ "$ko" = 0 ] && echo "OK   aucun secret dans les journaux des trois VM" || { echo "KO   secret trouvé dans un journal" >&2; exit 1; }
