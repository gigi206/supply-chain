#!/bin/bash
# Ajout du 23/11/2026, sur accord du propriétaire (« Oui, lis le timer ») : état de base-grype.timer et de base-grype.service dans
# sc-stockage, lu par SSH avec l utilisateur poc, sans sudo et sans journal. Propriétés choisies une à une (systemctl show -p) :
# ni Environment ni ligne de commande. Horodatage du dernier passage gardé par Persistent=true : date de modification du fichier
# /var/lib/systemd/timers/stamp-base-grype.timer. Rien n est écrit ni relancé.
set -uo pipefail
O8=$HOME/.cache/supply-chain-poc/08
SSH_OPTS=(-i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
echo "heure (hôte) : $(date -u +%FT%TZ)"
ssh "${SSH_OPTS[@]}" poc@192.168.161.13 'bash -s' <<'FIN'
export LC_ALL=C TZ=UTC SYSTEMD_PAGER=
echo "heure (VM) : $(date -u +%FT%TZ)"
echo "démarrage de la VM : $(uptime -s) UTC"
echo "--- base-grype.timer"
systemctl show base-grype.timer -p UnitFileState -p ActiveState -p SubState -p Result -p Persistent -p RandomizedDelayUSec \
  -p TimersCalendar -p LastTriggerUSec -p NextElapseUSecRealtime -p ActiveEnterTimestamp -p InactiveEnterTimestamp
echo "--- list-timers"
systemctl list-timers base-grype.timer --all --no-pager --no-legend
echo "--- stamp-base-grype.timer"
ls -l --time-style=+%FT%TZ /var/lib/systemd/timers/stamp-base-grype.timer 2>&1
echo "--- base-grype.service"
systemctl show base-grype.service -p ActiveState -p SubState -p Result -p ExecMainStartTimestamp -p ExecMainExitTimestamp \
  -p ExecMainStatus -p InactiveEnterTimestamp -p NRestarts
echo "--- systemd"
systemctl show -p SystemState -p Version -p UserspaceTimestamp -p FinishTimestamp
FIN
echo "code ssh : $?"
