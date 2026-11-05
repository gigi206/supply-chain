#!/usr/bin/env bash
# Brique 08b : preuve que la conversion ne change rien sous k3s, le défaut, en lecture seule. Le cluster en service et le relevé du 06/11/2026
# passent par ces scripts. 1) substitution inverse : chaque script converti, variables remplacées par leurs valeurs k3s, comparé à la version
# d'avant la conversion ; ne restent que les lignes structurelles, listées pour revue. 2) lectures réelles sur le cluster k3s par les chemins
# convertis. 3) args_apiserver de RKE2 sur un manifeste d'essai.
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08b-rke2/essai-k3s.sh [<commit d'avant la conversion>]   (journal : resultats/essai-k3s.log)
set -uo pipefail
export LC_ALL=C
unset DISTRO
here=$(cd "$(dirname "$0")" && pwd)
b08=$here/../08-trust-plane
. "$b08/commun.sh"
R=$here/resultats
BASE=${1:-d1ae7b1}
ko=0
ok() { if eval "$2"; then echo "OK   $1"; else echo "KO   $1"; ko=1; fi; }
exec > >(sed -u "s#$HOME#~#g" | tee "$R/essai-k3s.log") 2>&1
echo "# essai-k3s.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), base $BASE"
echo "## 1. substitution inverse (lignes restantes : ce qui change vraiment)"
for f in $(git -C "$repo" diff --name-only "$BASE" -- poc/bricks/08-trust-plane poc/bricks/19b-journalisation | grep -v distro.sh); do
  git -C "$repo" show "$BASE:$f" > "$W/avant" 2>/dev/null || continue
  sed -e "s#\$D_ETAT#$D_ETAT#g" -e "s#\$D_CONF#$D_CONF#g" -e "s#\$D_CRICTL#$D_CRICTL#g" -e "s#\$D_CTR#$D_CTR#g" -e "s#\$D_SERVEUR#$D_SERVEUR#g" \
      -e "s#\$D_AGENT#$D_AGENT#g" -e "s#\$D_SERVING#$D_SERVING#g" -e "s#\$D_LP_NS#$D_LP_NS#g" "$repo/$f" > "$W/apres"
  n=$(diff "$W/avant" "$W/apres" | grep -c '^[<>]')
  echo "--- $f : $n ligne(s)"
  diff "$W/avant" "$W/apres" | grep '^[<>]' | cut -c1-150
done
echo "## 2. lectures réelles sous k3s"
ok "DISTRO par défaut" '[ "$DISTRO" = k3s ]'
ok "unités actives" '[ "$(sur sc-confiance "systemctl is-active $D_SERVEUR")" = active ] && [ "$(sur sc-build "systemctl is-active $D_AGENT")" = active ]'
ok "args_apiserver : exemption lue" '[ "$(args_apiserver | grep -c -x -- "--admission-control-config-file=$D_CONF/pod-security.yaml")" = 1 ]'
ok "audit_api lit le journal" '[ "$(audit_api create | wc -l)" -gt 0 ]'
ok "D_CRICTL" 'sur sc-build "sudo $D_CRICTL info" | jq -e ".config.containerd.runtimes.kata" >/dev/null'
ok "D_CTR" 'sur sc-confiance "sudo $D_CTR -n k8s.io images ls -q" | grep -c . | grep -qv "^0$"'
ok "D_KUBECTL" '[ "$(sur sc-confiance "sudo $D_KUBECTL get nodes --no-headers" | wc -l)" = 3 ]'
ok "clé de service lue par le chemin converti" 'sur sc-confiance "sudo openssl pkey -in $D_ETAT/server/tls/service.key -pubout" | grep -q "BEGIN PUBLIC KEY"'
ok "local-path dans son espace" '[ -n "$(kubectl get pods -n "$D_LP_NS" -l app=local-path-provisioner -o name)" ]'
ok "registries.yaml rendu identique" 'sed "s#/etc/rancher/k3s#$D_CONF#" "$b08/stockage/registries.yaml" | cmp -s - "$b08/stockage/registries.yaml"'
ok "XML de sc-confiance rendu identique sous k3s" 'sed "" "$b08/libvirt/sc-confiance.xml" | cmp -s - "$b08/libvirt/sc-confiance.xml"'
echo "## 3. args_apiserver de RKE2, manifeste d'essai"
printf 'spec:\n  containers:\n  - args:\n    - --audit-log-path=/a\n    - "--admission-control-config-file=/etc/rancher/rke2/pod-security.yaml"\n    command:\n    - kube-apiserver\n' > "$W/manifeste.yaml"
n=$(sed -n 's/^ *- "\{0,1\}\(--[^"]*\)"\{0,1\}$/\1/p' "$W/manifeste.yaml" | grep -c -x -- '--admission-control-config-file=/etc/rancher/rke2/pod-security.yaml')
ok "ligne entre guillemets reconnue" '[ "$n" = 1 ]'
ok "commande non confondue avec un argument" '! sed -n "s/^ *- \"\{0,1\}\(--[^\"]*\)\"\{0,1\}$/\1/p" "$W/manifeste.yaml" | grep -q kube-apiserver'
[ "$ko" = 0 ] && echo "RÉSULTAT : conforme" || echo "RÉSULTAT : KO"
exit "$ko"
