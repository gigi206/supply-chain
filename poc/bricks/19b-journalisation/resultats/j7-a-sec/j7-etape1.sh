#!/usr/bin/env bash
# J7, étape 1 à sec : rendu helm hors ligne avec et sans l'export, comparaison au cilium-config vivant (lecture seule),
# alloy validate de la composition de sc-build avec et sans hubble.alloy, témoin cassé. Rien n'est posé.
# Usage (racine du dépôt) : bash j7-etape1.sh > poc/bricks/19b-journalisation/resultats/j7-etape1.log
set -euo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
S=/tmp/claude-1000/-home-gigi-Documents-git-github-gigi206-supply-chain/bfc3d105-c072-426f-9505-bf294f280b50/scratchpad/j7
B=poc/bricks
J=$B/19b-journalisation/resultats/j7-a-sec
TGZ=$HOME/.cache/supply-chain-poc/08/telechargements/cilium/cilium-1.20.4.tgz
AL=$HOME/.cache/supply-chain-poc/19b/j7-alloy-bin/alloy-linux-amd64
masque() { sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]'; }
echo "# J7 de la 19b, étape 1 à sec ($(date -u +%Y-%m-%dT%H:%M:%SZ)) : rien n'est posé"
echo "## archives"
echo "chart : sha256 $(sha256sum < "$TGZ" | cut -c1-64) (CHART_TGZ de cilium.sh : 505abff8385811df1a949776fc42e9f10697989a332acc86d6e8933efcb855ed)"
echo "alloy : sha256 $(sha256sum < "$HOME/.cache/supply-chain-poc/19b/amont/alloy-linux-amd64.zip" | cut -c1-64) (ALLOY_SHA de journalisation.sh : 50d23af2d0f98c00beac6ce9a365693e60f87fb76b6cad6fe1d161e80588af6d)"
echo "binaire : $("$AL" --version | head -n 1), extrait hors de /tmp, non installé"
echo "helm : $(mise exec -- helm version --short)"
echo "## fichiers proposés (j7-a-sec/)"
(cd "$J" && sha256sum valeurs-export.yaml hubble.alloy)
echo "## rendu hors ligne (helm template), valeurs de cilium.sh appliquer : cilium/valeurs.yaml rendu, 08b valeurs-cilium.yaml, 08c valeurs-cilium.yaml"
sed -e "s#@CILIUM_AMD64@#sha256:fa56fecd779584642c7ec2da6872c03c45c1f1043da66665a73ed8c425584d54#" \
    -e "s#@OPERATOR_AMD64@#sha256:77a9b4371faed41dc9c2fb3942b6c02a581158be1d4aa46a0e62956ce2f55ff1#" \
    $B/08-trust-plane/cilium/valeurs.yaml | grep -v '^#' > "$S/valeurs.yaml"
F=(-f "$S/valeurs.yaml" -f $B/08b-rke2/config/valeurs-cilium.yaml -f $B/08c-durcissement/config/valeurs-cilium.yaml)
mise exec -- helm template cilium "$TGZ" --namespace kube-system "${F[@]}" > "$S/rendu-actuel.yaml"
mise exec -- helm template cilium "$TGZ" --namespace kube-system "${F[@]}" -f "$J/valeurs-export.yaml" > "$S/rendu-j7.yaml"
for f in rendu-actuel rendu-j7; do mise exec -- yq -o=json -I=0 '.' "$S/$f.yaml" > "$S/$f.jsonl"; done
kubectl -n kube-system get cm cilium-config -o json > "$S/cilium-config-vivant.json"
echo "pas de WireGuard posé (clé enable-wireguard absente du cilium-config vivant) : $(jq -r '.data | has("enable-wireguard") | not' "$S/cilium-config-vivant.json")"
python3 -I "$S/j7-compare.py" "$S/rendu-actuel.jsonl" "$S/rendu-j7.jsonl" "$S/cilium-config-vivant.json" | masque
echo "## alloy validate, composition de sc-build (rôles commun noeud, plus journaux-rke2.alloy sous RKE2)"
C=$B/19b-journalisation/config/alloy
for cas in sans avec temoin; do
  d=$S/compo-$cas; find "$d" -delete 2>/dev/null || true; mkdir -p "$d"
  cp $C/commun/*.alloy $C/noeud/*.alloy $B/08b-rke2/config/alloy/journaux-rke2.alloy "$d/"
  [ "$cas" = sans ] || cp "$J/hubble.alloy" "$d/"
  [ "$cas" != temoin ] || sed -i 's/loki.write.sortie.receiver]/loki.write.inexistant.receiver]/' "$d/hubble.alloy"
  rc=0; "$AL" validate "$d" > "$S/validate-$cas.out" 2>&1 || rc=$?
  echo "$cas : code $rc ; fichiers : $(ls "$d" | tr '\n' ' ')"
  [ "$cas" != temoin ] || grep -m1 -o 'loki.write.inexistant.receiver' "$S/validate-$cas.out" | sed 's/^/  refus sur : /'
done
echo "## alloy fmt (forme seulement)"
for f in "$J/hubble.alloy" $C/noeud/pods.alloy $B/08b-rke2/config/alloy/journaux-rke2.alloy; do
  echo "$(basename "$f") : $("$AL" fmt "$f" | diff - "$f" | grep -c '^[<>]' || true) lignes d'écart avec fmt"
done
