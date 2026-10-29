#!/usr/bin/env bash
# Banc A2 : poids opérationnel de l'appliance (A-5), au repos (aucun build en cours).
# - RAM : RSS du processus qemu de sc-obs vu de l'hôte, et mémoire utilisée dans la VM ;
# - composants : services systemd de longue durée de l'appliance (équivalent des Deployments,
#   StatefulSets et DaemonSets comptés au banc A1) : unités actives, y compris obsscheduler et
#   obsworker, qui lancent leurs démons (bs_sched, bs_worker) puis restent « active (exited) » ;
#   un gabarit (unit@) compte une fois, comme des réplicas ; les unités oneshot d'installation
#   (obsapisetup, obsstoragesetup) sont exclues ;
# - disque : allocation réelle du volume qcow2 et occupation dans la VM.
#
# Usage (racine du dépôt) : mise run obs:etat -- <libellé>
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
lib=${1:-repos}
s() { "$here/ssh-obs.sh" "$@"; }
exec > >(sed -u "s#$HOME#~#g" | tee "$R/etat-$lib.log") 2>&1
echo "# etat.sh $lib, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "## Builds en cours : $(s "osc api /build/_workerstatus" | grep -c '<building ' || true)"
echo "## RAM"
echo "qemu (sc-obs), RSS vu de l'hôte (mémoire touchée par la VM, non rendue) :$(ps -C qemu-system-x86_64 -o rss=,args= | awk '/guest=sc-obs/ {printf "%.2f Gi", $1/1048576}')"
s 'free -m | sed -n 1,2p'
echo "## Composants (services de longue durée)"
s 'systemctl list-units --type=service --state=active --no-legend --plain \
     | awk "{print \$1}" | grep -E "^(obs|apache2|mysql|mariadb|memcached)" | grep -v -E "^(obsapisetup|obsstoragesetup)\.service$" \
     | sed -E "s/@[^.]*\.service$/@.service/" | sort -u' > "$R/composants-$lib.txt"
sed 's/^/  /' "$R/composants-$lib.txt"
echo "total : $(wc -l < "$R/composants-$lib.txt") (gabarits comptés une fois)"
echo "processus de l'appliance (hors noyau) : $(s 'ps -e --no-headers -o comm | grep -v -E "^(kworker|ksoftirqd|migration|rcu_|cpuhp|idle_inject|kthreadd|irq/|watchdog)" | wc -l')"
echo "## Disque"
virsh -c qemu:///system vol-info --pool supply-chain-poc sc-obs.qcow2 | grep -E 'Capacity|Allocation'
s 'df -h / /srv/obs/service | tail -2; du -sh /srv/obs/build /srv/obs/sources /srv/obs/repos /srv/obs/MySQL 2>/dev/null'
