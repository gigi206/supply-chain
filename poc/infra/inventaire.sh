#!/usr/bin/env bash
# Inventaire de l'hôte du PoC (ADR 0001), en lecture seule : aucune installation,
# aucun sudo, aucune modification du système. Seul test actif : `unshare` sans
# effet de bord (création d'un user namespace qui se termine aussitôt).
#
# Ne collecte ni nom d'hôte, ni nom d'utilisateur, ni adresse MAC ou IP, ni
# numéro de série, ni UUID ; un filtre final les masque au cas où.
#
# Usage : ./inventaire.sh > resultats/inventaire-laptop.txt
set -uo pipefail
export LC_ALL=C

section() { printf '\n## %s\n' "$*"; }
val() { printf '%-46s %s\n' "$1" "$2"; }
lire() { if [ -r "$1" ]; then tr -d '\0' < "$1" 2>/dev/null; else echo "absent ou illisible"; fi; }
present() { command -v "$1" >/dev/null 2>&1; }
# Première ligne non vide de la sortie d'une commande, sans jamais bloquer.
version() { timeout 10 "$@" </dev/null 2>&1 | grep -m1 -v '^\s*$' || true; }

main() {
  echo "# inventaire.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  section "Hôte"
  val "systemd-detect-virt" "$(systemd-detect-virt 2>/dev/null || true)"
  val "drapeau hypervisor (cpuinfo)" "$(grep -qw hypervisor /proc/cpuinfo && echo présent || echo absent)"
  val "DMI constructeur" "$(lire /sys/class/dmi/id/sys_vendor)"
  val "DMI modèle" "$(lire /sys/class/dmi/id/product_name)"
  val "DMI version" "$(lire /sys/class/dmi/id/product_version)"
  val "DMI type de châssis (9/10/31 = portable)" "$(lire /sys/class/dmi/id/chassis_type)"
  val "BIOS" "$(lire /sys/class/dmi/id/bios_vendor) $(lire /sys/class/dmi/id/bios_version) ($(lire /sys/class/dmi/id/bios_date))"
  val "Firmware" "$([ -d /sys/firmware/efi ] && echo UEFI || echo BIOS)"

  section "Système"
  grep -E '^(NAME|VERSION|ID|VERSION_ID|VERSION_CODENAME)=' /etc/os-release
  val "noyau" "$(uname -srm)"
  val "ligne de commande du noyau" "$(sed -E 's/(UUID=|root=)[^ ]*/\1<masqué>/g' /proc/cmdline)"
  val "systemd" "$(systemctl --version 2>/dev/null | head -1)"
  val "cgroup" "$(stat -fc %T /sys/fs/cgroup)"
  val "contrôleurs cgroup v2" "$(lire /sys/fs/cgroup/cgroup.controllers)"
  val "LSM actifs" "$(lire /sys/kernel/security/lsm)"
  val "AppArmor activé" "$(lire /sys/module/apparmor/parameters/enabled)"
  val "SELinux" "$([ -e /sys/fs/selinux/enforce ] && lire /sys/fs/selinux/enforce || echo absent)"
  val "BTF (/sys/kernel/btf/vmlinux)" "$([ -r /sys/kernel/btf/vmlinux ] && echo présent || echo absent)"
  cfg=/boot/config-$(uname -r)
  if [ -r "$cfg" ]; then
    echo "Options du noyau ($cfg) :"
    for o in USER_NS KVM KVM_INTEL KVM_AMD VHOST_VSOCK VHOST_NET VIRTIO_FS FUSE_FS OVERLAY_FS \
      BRIDGE_NETFILTER NF_TABLES BPF_SYSCALL CGROUP_BPF DEBUG_INFO_BTF SECCOMP SECCOMP_FILTER \
      SECURITY_APPARMOR SECURITY_LANDLOCK TMPFS_XATTR; do
      printf '  CONFIG_%-22s %s\n' "$o" "$(grep -E "^(# )?CONFIG_${o}[= ]" "$cfg" | sed -E 's/^CONFIG_[A-Z0-9_]+=//; s/^# .* is not set$/n/' | head -1)"
    done
  else
    echo "Options du noyau : $cfg illisible"
  fi

  section "CPU"
  lscpu | grep -vE '^(Flags|Vulnerability)'
  echo "Drapeaux utiles :"
  for f in vmx svm ept npt avx avx2 bmi1 bmi2 fma movbe abm f16c xsave osxsave avx512f sha_ni aes; do
    printf '  %-8s %s\n' "$f" "$(grep -m1 -qw "$f" /proc/cpuinfo && echo oui || echo non)"
  done
  echo "Niveaux x86-64 (glibc) :"
  /lib64/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -E 'x86-64-v[234]' | sed 's/^/ /'
  val "microcode" "$(grep -m1 microcode /proc/cpuinfo | awk -F': ' '{print $2}')"
  if [ -d /sys/devices/cpu_core ] || [ -d /sys/devices/cpu_atom ]; then
    val "cœurs hybrides : P (cpu_core)" "$(lire /sys/devices/cpu_core/cpus)"
    val "cœurs hybrides : E (cpu_atom)" "$(lire /sys/devices/cpu_atom/cpus)"
  else
    val "cœurs hybrides" "non (pas de cpu_core/cpu_atom)"
  fi
  echo "Fréquence maximale par CPU logique (MHz) :"
  lscpu -e=CPU,CORE,MAXMHZ 2>/dev/null | awk 'NR>1 {print $3}' | sort | uniq -c | sed 's/^/ /'
  val "pilote cpufreq" "$(lire /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver)"
  val "gouverneur (cpu0)" "$(lire /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  val "préférence énergie (cpu0)" "$(lire /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)"
  val "profil de plateforme" "$(lire /sys/firmware/acpi/platform_profile)"
  for ps in /sys/class/power_supply/*; do
    [ -e "$ps/type" ] || continue
    case "$(lire "$ps/type")" in
      Mains) val "secteur ($(basename "$ps"))" "$( [ "$(lire "$ps/online")" = 1 ] && echo branché || echo débranché)" ;;
      Battery) val "batterie ($(basename "$ps"))" "$(lire "$ps/capacity") %, $(lire "$ps/status")" ;;
    esac
  done

  section "KVM et virtualisation imbriquée"
  if [ -e /dev/kvm ]; then
    val "/dev/kvm" "$(stat -c '%A %U:%G' /dev/kvm)"
    val "accès lecture/écriture pour l'utilisateur" "$([ -r /dev/kvm ] && [ -w /dev/kvm ] && echo oui || echo non)"
  else
    val "/dev/kvm" "absent"
  fi
  val "utilisateur dans le groupe kvm" "$(id -nG | tr ' ' '\n' | grep -qx kvm && echo oui || echo non)"
  val "utilisateur dans le groupe libvirt" "$(id -nG | tr ' ' '\n' | grep -qx libvirt && echo oui || echo non)"
  for m in kvm_intel kvm_amd; do
    [ -d /sys/module/$m ] || continue
    for p in nested ept enable_apicv unrestricted_guest npt avic; do
      [ -r /sys/module/$m/parameters/$p ] && val "$m.$p" "$(lire /sys/module/$m/parameters/$p)"
    done
  done
  echo "Modules chargés (kvm, vhost, vsock, réseau de conteneurs) :"
  lsmod | awk 'NR>1 {print $1}' | grep -E '^(kvm|kvm_intel|kvm_amd|vhost|vhost_net|vhost_vsock|vsock|vmw_vsock_virtio_transport_common|tun|tap|bridge|br_netfilter|overlay|nf_tables|ip_tables|iptable_nat|xt_comment|veth|wireguard|vxlan)$' \
    | sort | sed 's/^/  /'
  echo "Modules disponibles (modinfo) :"
  for m in vhost_vsock vhost_net br_netfilter overlay vxlan; do
    printf '  %-14s %s\n' "$m" "$(modinfo -F filename "$m" >/dev/null 2>&1 && echo disponible || echo introuvable)"
  done
  echo "Options modprobe (nested) :"
  grep -rhs 'nested' /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null | sed 's/^/  /' || true
  present virt-host-validate && { echo "virt-host-validate qemu :"; timeout 30 virt-host-validate qemu 2>&1 | grep -v '^\s*$' | sed 's/^ *(/      (/; s/^ */  /'; }

  section "Mémoire"
  free -h
  grep -E '^(MemTotal|SwapTotal|HugePages_Total|Hugepagesize)' /proc/meminfo
  echo "Swap :"
  swapon --show 2>/dev/null | sed 's/^/  /'
  for z in /sys/block/zram*; do
    [ -e "$z" ] && val "$(basename "$z") disksize" "$(lire "$z/disksize")"
  done
  val "THP" "$(lire /sys/kernel/mm/transparent_hugepage/enabled)"
  val "KSM run" "$(lire /sys/kernel/mm/ksm/run)"

  section "Disques et systèmes de fichiers"
  lsblk -e 7 -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL 2>/dev/null
  echo
  df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | grep -v '^/dev/loop'
  val "tmpfs /tmp (utilisé, en RAM)" "$(df -h --output=used /tmp 2>/dev/null | tail -1 | tr -d ' ')"
  echo
  for p in / /var /var/lib /home /tmp; do
    printf '%-10s %s\n' "$p" "$(findmnt -no FSTYPE,OPTIONS -T "$p" 2>/dev/null | head -1)"
  done
  echo "Espace libre sur les chemins des runtimes :"
  for p in /var/lib /var/lib/rancher /var/lib/libvirt /var/lib/containerd /home; do
    [ -e "$p" ] && printf '  %-22s %s\n' "$p" "$(df -h --output=avail "$p" | tail -1 | tr -d ' ')"
  done

  section "User namespaces"
  for k in user/max_user_namespaces kernel/unprivileged_userns_clone kernel/apparmor_restrict_unprivileged_userns \
    kernel/apparmor_restrict_unprivileged_unconfined kernel/unprivileged_bpf_disabled kernel/yama/ptrace_scope; do
    val "$(echo "$k" | tr / .)" "$(lire /proc/sys/$k)"
  done
  u=$(id -un)
  val "plages /etc/subuid de l'utilisateur" "$(awk -F: -v u="$u" '$1 == u {print $2 "+" $3}' /etc/subuid 2>/dev/null | paste -sd' ')"
  val "plages /etc/subgid de l'utilisateur" "$(awk -F: -v u="$u" '$1 == u {print $2 "+" $3}' /etc/subgid 2>/dev/null | paste -sd' ')"
  val "newuidmap / newgidmap" "$(present newuidmap && echo -n présent || echo -n absent) / $(present newgidmap && echo présent || echo absent)"
  val "unshare" "$(version unshare --version)"
  for t in "-rn" "-rmn" "-Urn --map-auto"; do
    # shellcheck disable=SC2086
    out=$(timeout 10 unshare $t true 2>&1) && r=réussi || r="échec : $out"
    val "test unshare $t true" "$r"
  done

  section "Réseau (sans adresses)"
  echo "Interfaces (nombre par famille) :"
  ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | awk '
    /^lo$/ {f = "loopback"} /^(en|wl|eth)/ {f = "physique"} /^(docker0|br-)/ {f = "docker"}
    /^virbr/ {f = "libvirt"} /^(lxcbr|lxdbr)/ {f = "lxc/lxd"} /^veth/ {f = "veth"}
    /^(cni|flannel|cali|kube)/ {f = "kubernetes"} {n[f ? f : "autre"]++; f = ""}
    END {for (k in n) printf "  %-12s %d\n", k, n[k]}' | sort
  val "net.ipv4.ip_forward" "$(lire /proc/sys/net/ipv4/ip_forward)"
  val "net.bridge.bridge-nf-call-iptables" "$(lire /proc/sys/net/bridge/bridge-nf-call-iptables)"
  # Seuls les ports utiles au PoC sont relevés : la liste complète des services
  # en écoute ne sert à aucune décision et exposerait la surface de l'hôte.
  echo "Ports prévus par le PoC :"
  for p in 80 443 3000 5000 6443 8080 8200 8443 9090 9093 10250; do
    printf '  %-6s %s\n' "$p" "$(ss -ltnH "sport = :$p" 2>/dev/null | grep -q . && echo occupé || echo libre)"
  done
  echo "Variables de proxy (noms seulement) :"
  env | grep -iE '^[a-z_]*proxy=' | cut -d= -f1 | sed 's/^/  /' || true
  env | grep -qiE '^[a-z_]*proxy=' || echo "  aucune"
  val "CA ajoutées localement" "$(find /usr/local/share/ca-certificates -type f 2>/dev/null | wc -l) fichier(s)"
  timedatectl show -p Timezone -p NTP -p NTPSynchronized 2>/dev/null | sed 's/^/  /'
  val "fs.inotify.max_user_watches" "$(lire /proc/sys/fs/inotify/max_user_watches)"
  val "fs.inotify.max_user_instances" "$(lire /proc/sys/fs/inotify/max_user_instances)"
  val "fs.file-max" "$(lire /proc/sys/fs/file-max)"
  val "ulimit -n (utilisateur)" "$(ulimit -n)"

  section "Runtimes et services déjà présents"
  for c in docker dockerd podman buildah containerd ctr nerdctl runc crun kata-runtime containerd-shim-kata-v2 \
    k3s kubectl kind helm virsh virt-install qemu-system-x86_64 lxc lxd incus multipass vagrant VBoxManage nix snap; do
    if present "$c"; then
      case "$c" in
        kubectl) v=$(version kubectl version --client) ;;
        helm) v=$(version helm version --short) ;;
        virsh) v="libvirt $(version virsh --version)" ;;
        virt-install) v=$(timeout 10 virt-install --version </dev/null 2>&1 | tail -1) ;;
        *) v=$(version "$c" --version) ;;
      esac
      printf '  %-24s %s\n' "$c" "$v"
    fi
  done
  present vagrant && val "plugins vagrant" "$(timeout 20 vagrant plugin list 2>/dev/null | grep -v '^==>' | paste -sd' ')"
  for c in k3d qemu-img genisoimage xorriso; do
    present "$c" && printf '  %-24s %s\n' "$c" "$(version "$c" --version)"
  done
  if present virsh; then
    val "VM libvirt (système) : définies / actives" \
      "$(virsh -c qemu:///system list --all --name 2>/dev/null | grep -c .) / $(virsh -c qemu:///system list --name 2>/dev/null | grep -c .)"
    val "pool libvirt « default »" "$(virsh -c qemu:///system pool-dumpxml default 2>/dev/null | sed -n 's#.*<path>\(.*\)</path>.*#\1#p')"
    val "réseaux libvirt actifs" "$(virsh -c qemu:///system net-list --name 2>/dev/null | grep -c .)"
  fi
  present docker && val "docker : racine, pilote, conteneurs actifs" \
    "$(timeout 10 docker info --format '{{.DockerRootDir}}, {{.Driver}}, {{.ContainersRunning}}' 2>/dev/null)"
  echo "Services systemd :"
  for s in docker containerd podman.socket libvirtd virtqemud k3s k3s-agent ufw firewalld nftables apparmor \
    snap.lxd.daemon incus nix-daemon systemd-timesyncd chrony; do
    a=$(systemctl is-active "$s" 2>/dev/null)
    e=$(systemctl is-enabled "$s" 2>/dev/null)
    [ -n "$e" ] && [ "$e" != "not-found" ] && printf '  %-22s %s, %s\n' "$s" "$a" "$e"
  done
  val "\$HOME/.kube/config" "$([ -e "$HOME/.kube/config" ] && echo présent || echo absent)"

  section "Outils pour les bancs (4b)"
  for c in python3 git make go node npm nix hermeto oras crane skopeo cosign zot buildctl buildkitd runc \
    syft grype ec kyverno reuse unzip jq curl gpg diffoscope; do
    if present "$c"; then
      case "$c" in
        go) v=$(version go version) ;;
        oras|crane|syft|grype|ec|kyverno|cosign) v=$(version "$c" version | tr -s ' ') ;;
        unzip) v=$(version unzip -v) ;;
        *) v=$(version "$c" --version) ;;
      esac
      printf '  %-10s %s\n' "$c" "$v"
    else
      printf '  %-10s absent\n' "$c"
    fi
  done
}

# Filtre de confidentialité : le dépôt a un remote public.
masquer() {
  local h u
  h=$(cat /proc/sys/kernel/hostname)
  u=$(id -un)
  sed -E \
    -e "s#${HOME}#~#g" \
    -e "s#\b${h}\b#<hôte>#g" \
    -e "s#\b${u}\b#<utilisateur>#g" \
    -e 's#([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}#<mac>#g' \
    -e 's#[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}#<uuid>#g'
}

main 2>&1 | masquer
