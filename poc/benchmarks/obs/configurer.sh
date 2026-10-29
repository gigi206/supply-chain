#!/usr/bin/env bash
# Banc A2 : configuration de l'appliance après le premier accès (tout se passe dans la VM).
# - mot de passe du compte Admin remplacé (POST /person/Admin?cmd=change_password), ancien refusé ;
# - osc de l'appliance configuré pour root (oscrc en 0600) ;
# - worker : 1 instance de 4 jobs et 3 Gi (6 instances par défaut, une par vCPU, ne tiennent
#   pas dans 8 Gi), type de VM « kvm » imposé (pas de repli silencieux en chroot) ;
# - provenance SLSA activée pour le projet poc ($slsaprovenance, désactivée par défaut) ;
# - contrôles : CPU (x86-64-v3 sans v4), /dev/kvm, sortie réseau, services, RAM et disque.
#
# Usage (racine du dépôt) : mise run obs:configurer
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}
s() { "$here/ssh-obs.sh" "$@"; }
exec > >(sed -u "s#$HOME#~#g" | tee "$R/configuration.log") 2>&1
echo "# configurer.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "## Compte Admin"
# Le mot de passe passe par l'entrée standard de SSH, jamais par une ligne de commande.
s 'p=$(cat); c=$(curl -sk -o /dev/null -w "%{http_code}" -u Admin:opensuse https://localhost/person/Admin)
   if [ "$c" = 200 ]; then
     curl -sk -u Admin:opensuse -X POST --data-binary "$p" "https://localhost/person/Admin?cmd=change_password" | grep -o "code=\"[a-z]*\""
   fi
   umask 077; mkdir -p /root/.config/osc
   printf "[general]\napiurl = https://localhost\n\n[https://localhost]\nuser = Admin\npass = %s\ncredentials_mgr_class = osc.credentials.PlaintextConfigFileCredentialsManager\ncafile = /srv/obs/certs/server.crt\n" "$p" > /root/.config/osc/oscrc
   echo "ancien mot de passe sur /person/Admin : HTTP $(curl -sk -o /dev/null -w "%{http_code}" -u Admin:opensuse https://localhost/person/Admin)"
   echo "nouveau mot de passe sur /person/Admin : HTTP $(curl -sk -o /dev/null -w "%{http_code}" -u "Admin:$p" https://localhost/person/Admin)"' < "$O/secrets/admin"
s 'osc api /about | grep -E "revision|commit"'

echo "## Worker"
s 'sed -i -e "s/^OBS_WORKER_INSTANCES=.*/OBS_WORKER_INSTANCES=\"1\"/" \
          -e "s/^OBS_WORKER_JOBS=.*/OBS_WORKER_JOBS=\"4\"/" \
          -e "s/^OBS_INSTANCE_MEMORY=.*/OBS_INSTANCE_MEMORY=\"3072\"/" \
          -e "s/^OBS_VM_TYPE=.*/OBS_VM_TYPE=\"kvm\"/" /etc/sysconfig/obs-server
   grep -E "^OBS_(WORKER_INSTANCES|WORKER_JOBS|INSTANCE_MEMORY|VM_TYPE|VM_DISK_AUTOSETUP_ROOT_FILESIZE)=" /etc/sysconfig/obs-server
   systemctl restart obsworker
   journalctl -u obsworker --no-pager -n 20 | grep -E "Run [0-9]+ obsworker|Type of obsworker"
   sleep 5; ls /srv/obs/workers/idle 2>/dev/null | sed "s/^/worker inactif : /"'

echo "## Provenance SLSA du projet poc (\$slsaprovenance, préfixe « projet/dépôt » : BSSched/BuildJob.pm)"
s 'f=/usr/lib/obs/server/BSConfig.pm
   grep -q "^our \$slsaprovenance" "$f" || sed -i "s|^1;\$|our \$slsaprovenance = [ \"poc/\" ];\n\n1;|" "$f"
   grep -n "^our \$slsaprovenance" "$f"; perl -c "$f" 2>&1
   systemctl restart obssrcserver obsrepserver obsscheduler obsdispatcher obssigner obspublisher obsworker
   systemctl is-active obssrcserver obsrepserver obsscheduler obsdispatcher obssigner obspublisher obsworker | paste -sd" "'

echo "## Contrôles"
s '/lib64/ld-linux-x86-64.so.2 --help | grep -E "x86-64-v[34]"
   grep -q -w -E "avx512[a-z]*" /proc/cpuinfo && echo "AVX-512 visible" || echo "AVX-512 absent"
   echo "/dev/kvm : $(stat -c "%A %G" /dev/kvm) ; modules : $(lsmod | awk "/^kvm/ {print \$1}" | paste -sd" ")"
   echo "sortie réseau : HTTP $(curl -sS -o /dev/null -w "%{http_code}" https://download.opensuse.org/)"
   echo "services OBS actifs : $(systemctl list-units --type=service --state=active --no-legend "obs*" apache2.service mysql.service memcached.service | awk "{print \$1}" | paste -sd" ")"
   echo "RPM installés : $(rpm -qa 2>/dev/null | wc -l)"
   echo "clé OBS dans la base rpm : $(rpm -q gpg-pubkey-c5c219e7 2>/dev/null), copie de 2013 expirée le 30/04/2015 (embarquée dans config.sh de l appliance)"
   free -m | head -2; df -h / /srv/obs/service | tail -2'
echo "RAM de la VM vue par l'hôte (RSS de qemu) : $(ps -C qemu-system-x86_64 -o rss=,args= | awk '/sc-obs/ {printf "%.1f Gi", $1/1048576}')"

echo "## Paquets rpm de la VM comparés au SBOM de la qcow2 (même build)"
sb=$O/appliance/obs-server.x86_64-2.10.51-qcow2-Build53.24.cdx.json
echo "composants du SBOM : $(jq -r '[.components[] | .purl // "sans purl" | split("/")[0]] | group_by(.) | map("\(.[0]) \(length)") | join(", ")' "$sb")"
diff <(jq -r '.components[] | select((.purl // "") | startswith("pkg:rpm/")) | "\(.name) \(.version)"' "$sb" | sort -u) \
     <(s "rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' 2>/dev/null" | grep -v '^gpg-pubkey ' | sort -u) > "$O/travail-sbom.diff" && r=0 || r=$?
echo "écarts : $(grep -c '^[<>]' "$O/travail-sbom.diff" || true) lignes (code diff $r)"
head -20 "$O/travail-sbom.diff"
rm -f "$O/travail-sbom.diff"
