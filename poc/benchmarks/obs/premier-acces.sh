#!/usr/bin/env bash
# Banc A2 : premier accès à l'appliance par la console série (ni cloud-init ni combustion).
# Connexion root avec le mot de passe public de l'appliance (hash du kiwi, crypt("opensuse")),
# puis aussitôt : clé SSH dédiée, mot de passe root aléatoire (envoyé sous forme de hash),
# sshd activé. Ensuite, par SSH : mot de passe aléatoire pour le compte Admin de l'interface.
# Secrets en 0600 dans ~/.cache/supply-chain-poc/obs/{secrets,ssh} ; known_hosts dédié.
#
# Usage (racine du dépôt) : mise run obs:premier-acces
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}
VM=sc-obs
IP=192.168.161.10
umask 077
mkdir -p "$O/secrets" "$O/ssh"
[[ -s $O/ssh/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N '' -C "$VM-banc-a2" -f "$O/ssh/id_ed25519"
[[ -s $O/secrets/root ]] || openssl rand -base64 24 > "$O/secrets/root"
[[ -s $O/secrets/admin ]] || openssl rand -hex 16 > "$O/secrets/admin"
C=$(mktemp -p "$O/secrets")
trap 'rm -f -- "$C"' EXIT
cat > "$C" <<EOF
install -d -m 700 /root/.ssh
printf '%s\n' '$(cat "$O/ssh/id_ed25519.pub")' > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
usermod -p '$(openssl passwd -6 -stdin < "$O/secrets/root")' root # secret
systemctl enable --now sshd
systemctl is-active sshd
EOF
exec > >(sed -u "s#$HOME#~#g" | tee "$R/premier-acces.log") 2>&1
echo "# premier-acces.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
CONSOLE_MDP=opensuse python3 -I "$here/console.py" "$VM" "$C"

ssh_obs() {
  ssh -o UserKnownHostsFile="$O/ssh/known_hosts" -o StrictHostKeyChecking=accept-new \
      -o IdentitiesOnly=yes -o BatchMode=yes -i "$O/ssh/id_ed25519" "root@$IP" "$@"
}
echo "## SSH"
ssh_obs 'hostname -f; cat /etc/os-release | grep -E "^(PRETTY_NAME|VERSION_ID)="'
echo "empreinte de l'hôte : $(ssh-keygen -l -f "$O/ssh/known_hosts" | awk '{print $2, $4}')"
printf '3. premier accès : root et clé SSH remplacés\t%s\t\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$R/chrono.tsv"
