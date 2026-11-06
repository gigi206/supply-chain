#!/usr/bin/env bash
# Brique 08c : pics de mémoire et de CPU, sans rien changer. kubectl top toutes les 5 s, cgroups des trois nœuds toutes les 2 s (memory.peak, usage_usec).
# metrics-server ne voit pas les conteneurs brefs : le cgroup donne le pic réel. Sous Kata, le cgroup du pod est celui de la VM, pas celui de la tâche.
# Usage (racine du dépôt) : DUREE=480 poc/bricks/08c-durcissement/essais-h5-pics.sh sonder ; puis ... resumer (journal : resultats/durcissement-h5-pics.log)
set -uo pipefail
export LC_ALL=C
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
O=$HOME/.cache/supply-chain-poc/08
K=$O/ssh
D=$O/travail/durcissement/pics
SSH=(ssh -i "$K/id_ed25519" -o UserKnownHostsFile="$K/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)

sonder() {
  rm -rf -- "${D:?}"; mkdir -p "$D"
  date -u '+début %H:%M:%S UTC'
  for ip in 11 12 13; do
    "${SSH[@]}" "poc@192.168.161.$ip" "sudo -n timeout ${DUREE:-480} sh -s" > "$D/cgroup-$ip.txt" 2>/dev/null <<'S' &
while :; do
  echo "T $(date +%s)"
  find /sys/fs/cgroup/kubepods.slice -name memory.peak | while read -r f; do
    c=${f%/memory.peak}
    echo "$c $(cat "$f" 2>/dev/null) $(sed -n 's/^usage_usec //p' "$c/cpu.stat" 2>/dev/null)"
  done
  sleep 2
done
S
  done
  fin=$(($(date +%s) + ${DUREE:-480}))
  while [ "$(date +%s)" -lt "$fin" ]; do
    { date -u '+T %H:%M:%S'; kubectl top pods -A --containers --no-headers </dev/null 2>/dev/null; } >> "$D/top.txt"
    sleep 5 </dev/null
  done
  wait
  kubectl get pods -A -o json </dev/null > "$D/pods.json"
  date -u '+fin %H:%M:%S UTC'
}

resumer() {
  {
    date -u '+résumé du %d/%m/%Y à %H:%M:%S UTC'
    echo "échantillons : $(grep -c '^T ' "$D/top.txt") de kubectl top, $(cat "$D"/cgroup-*.txt | grep -c '^T ') de cgroups"
    echo "lignes de kubectl top sur les pods de la construction : $(grep -c '^builds ' "$D/top.txt"), sur ceux de la porte : $(grep -c '^porte ' "$D/top.txt")"
    # Pods supprimés avant la fin (Jobs purgés) : le nom est perdu, le cgroup reste ; pods statiques de kube-system écartés (UID sans tiret). Pic pris sur 2 s : un conteneur plus bref peut échapper à sa portée, pas au cgroup du pod.
    # Clé : UID du pod et conteneur s'il y a une portée cri-containerd. Le pic mémoire est gardé, le CPU est le débit maximal entre deux échantillons.
    jq -r '.items[] | .metadata as $m | ($m.uid | gsub("-"; "_")) as $u | "P \($u) \($m.namespace) \($m.name)",
      ((.status.containerStatuses // []) + (.status.initContainerStatuses // []) | .[] | select(.containerID != null) | "C \(.containerID | sub("^containerd://"; "")) \(.name)")' "$D/pods.json" > "$D/noms.txt"
    awk '
      FNR == NR { if ($1 == "P") { ns[$2] = $3; pod[$2] = $4 } else { ctr[$2] = $3 } next }
      $1 == "T" { t = $2; next }
      {
        k = $1; m = $2; u = $3
        if (m > pic[k]) pic[k] = m
        if (k in tp && t > tp[k] && u >= up[k]) { r = (u - up[k]) / ((t - tp[k]) * 1000); if (r > cpu[k]) cpu[k] = r }
        tp[k] = t; up[k] = u
      }
      END {
        for (k in pic) {
          if (!match(k, /pod[0-9a-f_]+\.slice/)) continue
          uid = substr(k, RSTART + 3, RLENGTH - 9)
          nom = "-"
          if (match(k, /cri-containerd-[0-9a-f]+\.scope/)) { id = substr(k, RSTART + 15, RLENGTH - 21); nom = (id in ctr) ? ctr[id] : "(pause ou sandbox)" }
          if (!(uid in ns)) { if (nom == "-" && uid ~ /_/) printf "(pod disparu) %s %s %d Mi %d m\n", uid, nom, pic[k] / 1048576, cpu[k]; continue }
          if (ns[uid] ~ /^(kube-system|kyverno|local-path-storage)$/) continue
          printf "%s %s %s %d Mi %d m\n", ns[uid], pod[uid], nom, pic[k] / 1048576, cpu[k]
        }
      }' "$D/noms.txt" "$D"/cgroup-*.txt | sort -k1,1 -k2,2 -k3,3
  } 2>&1 | sed -u "s#$HOME#~#g" | tee "$here/resultats/durcissement-h5-pics.log"
}

"$1"
