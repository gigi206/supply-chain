#!/usr/bin/env bash
# Banc A2 : rebuild hors ligne (critère 2, B5). Dans l'appliance, une table nftables bloque toute
# sortie autre que locale et journalise chaque tentative (préfixe « banc-a2-sortie »). Restent
# permis : lo, l'appliance elle-même, les réponses SSH vers l'hôte (sinon le banc perd la main) et
# le DNS du résolveur libvirt (192.168.161.1), compté à part : le backend résout sc-obs.poc.test
# par ce DNS (absent de /etc/hosts). On reconstruit sample-app (build-<libellé>), on compare au build de
# référence, puis on lit le compteur et le journal, et on retire la table.
# Les entrées viennent alors uniquement du cache de l'appliance : sources du projet et paquets
# déjà téléchargés à la demande (:full des projets Debian:13 et Rocky:9.7).
#
# Usage (racine du dépôt) : mise run obs:horsligne -- <libellé> <référence>   (ex. build-5 build-3)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
lib=${1:?libellé du build hors ligne}
ref=${2:?build de référence}
s() { "$here/ssh-obs.sh" "$@"; }
retirer() { s 'nft delete table inet banc_a2 2>/dev/null || true'; }
trap retirer EXIT
mkdir -p "$R/$lib"

{
  echo "# horsligne.sh $lib (référence $ref), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  s 'set -e
     nft add table inet banc_a2
     nft add chain inet banc_a2 sortie "{ type filter hook output priority 0; policy accept; }"
     nft add rule inet banc_a2 sortie oif lo accept
     nft add rule inet banc_a2 sortie ip daddr 192.168.161.10 accept
     nft add rule inet banc_a2 sortie ip daddr 192.168.161.1 tcp sport 22 accept
     nft add rule inet banc_a2 sortie ip daddr 192.168.161.1 meta l4proto { tcp, udp } th dport 53 counter accept
     nft add rule inet banc_a2 sortie counter log prefix \"banc-a2-sortie \" drop
     nft list table inet banc_a2
     date -u +%Y-%m-%dT%H:%M:%S > /root/banc-a2/horsligne.debut
     if curl -sS -m 10 -o /dev/null https://download.opensuse.org/ 2>/dev/null; then echo "contrôle : SORTIE OUVERTE"; else echo "contrôle : sortie bloquée (curl échoue)"; fi'
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/$lib/horsligne.log"

"$here/construire.sh" reconstruire "$lib" > /dev/null
{
  echo "## Build hors ligne"
  sed -n '/## Collecte/,$p' "$R/$lib/construire.log"
  echo "## Sorties bloquées pendant le build"
  s 'nft list chain inet banc_a2 sortie | grep -E "counter" | sed -E "s/^[[:space:]]+//"
     journalctl -k --since "$(cat /root/banc-a2/horsligne.debut)" --no-pager -o cat | grep "banc-a2-sortie" \
       | grep -o -E "DST=[0-9.]+ .*PROTO=[A-Z]+ .*DPT=[0-9]+" | sed -E "s/^DST=([0-9.]+) .*PROTO=([A-Z]+) .*DPT=([0-9]+)/\1 \2 \3/" \
       | sort | uniq -c | sort -rn | head -10'
  echo "## Comparaison avec $ref"
  "$here/comparer.sh" "$ref" "$lib" | tail -n +2
} 2>&1 | sed -u "s#$HOME#~#g" | tee -a "$R/$lib/horsligne.log"
