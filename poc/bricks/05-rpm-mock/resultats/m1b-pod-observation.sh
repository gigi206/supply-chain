#!/usr/bin/env bash
# Brique 05, M1b : observation en lecture seule du pod m1b-a pendant son installation (demande du propriétaire du 19/11/2026,
# « regarde ce qu'il se passe sur le pod kata »). Rien n'est écrit dans le pod ni dans le cluster. Relève : limite de fichiers
# ouverts du conteneur et de l'hôte, avancement de dnf, et pour chaque fils du processus dnf : âge, temps CPU (utime, stime),
# exécutable et ligne de commande, en plusieurs échantillons. Un fils encore « python3.9 dnf » n'a pas fait son exec.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-pod-observation.sh > <journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/supply-chain-poc.yaml}
P=${POD:-m1b-a}
echo "# m1b-pod-observation.sh, début $(date -u +%FT%TZ) ; pod $P"
echo "hôte : limite de fichiers ouverts $(ulimit -n) (souple) / $(ulimit -Hn) (dure)"
kubectl exec -n builds "$P" -- sh -c '
d=$(for q in /proc/[0-9]*; do tr "\0" " " < $q/cmdline 2>/dev/null | grep -q "^/usr/bin/python3.9 /usr/bin/dnf" && echo ${q#/proc/}; done | sort -n | head -1)   # le plus ancien : dnf principal (correctif après le premier passage)
echo "pod : processus dnf principal $d ; limite de fichiers ouverts : $(grep -i "open files" /proc/$d/limits | tr -s " " | cut -d" " -f4,5)"
echo "pod : CLK_TCK $(getconf CLK_TCK) ; vCPU $(nproc) ; noyau $(uname -r)"
for i in 1 2 3 4 5 6; do
  t=$(cut -d" " -f1 /proc/uptime)
  echo "échantillon $i, $(date -u +%T) : paquets « Installing » $(grep -c Installing /w/dnf.log) ; dernière ligne : $(tail -n1 /w/dnf.log | tr -s " " | cut -c1-80)"
  for q in /proc/[0-9]*; do
    [ "$(cut -d" " -f4 $q/stat 2>/dev/null)" = "$d" ] || continue
    s=$(cut -d" " -f22 $q/stat)
    echo "     fils ${q#/proc/} : état $(cut -d" " -f3 $q/stat) ; âge $(awk -v t=$t -v s=$s "BEGIN{printf \"%.0f\", t - s/100}") s ; utime $(cut -d" " -f14 $q/stat) stime $(cut -d" " -f15 $q/stat) (tops) ; exe $(readlink $q/exe) ; cmdline $(tr "\0" " " < $q/cmdline | cut -c1-40)"
  done
  sleep 20
done
echo "dnf principal : utime $(cut -d" " -f14 /proc/$d/stat) stime $(cut -d" " -f15 /proc/$d/stat) (tops)"
' < /dev/null 2>&1 | sed -E -e 's/<[^>]*@[^>]*>/<adresse retirée>/g' -e '/jeton|token/I c\[ligne masquée : motif jeton|token]'
echo "# fin $(date -u +%FT%TZ)"
