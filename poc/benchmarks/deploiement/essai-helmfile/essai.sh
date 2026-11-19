#!/usr/bin/env bash
# Essai à sec de helmfile (accord du propriétaire du 18/11/2026 : « Oui, essai à sec ») : les trois charts que les scripts installent
# depuis l'hôte, rendus par helm template (comme etape_rendu de rke2.sh, l. 188 à 193) puis par helmfile template, et comparés.
# Sans cluster, sans réseau (unshare -n), sans greffon Helm (HELM_PLUGINS vers un dossier vide, car helm-diff 3.11.0 et helm-git 1.3.0,
# de provenance inconnue, sont présents sur l'hôte). helmfile vient de mise.toml (installation accordée à part).
# Usage (racine du dépôt) : bash poc/benchmarks/deploiement/essai-helmfile/essai.sh > poc/benchmarks/deploiement/resultats/<journal neuf> 2>&1
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
r=$(cd "$here/../../../.." && pwd)
W=$HOME/.cache/supply-chain-poc/dep-helmfile-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$W" ] || { echo "KO   $W existe" >&2; exit 1; }
mkdir -p "$W/greffons" "$W/ref" "$W/hf" "$W/cache" "$W/config" "$W/data"
ns() { unshare --map-auto --map-root-user -n "$@"; }
HELM=$(cd "$r" && mise which helm) HELMFILE=$(cd "$r" && mise which helmfile)   # chemins absolus résolus à la racine du dépôt (mise.toml)
echo "greffons Helm de l'hôte avant isolement (helm plugin list) :"; "$HELM" plugin list 2>&1 | sed 's/^/  /'
export HELM_PLUGINS=$W/greffons HELM_CACHE_HOME=$W/cache HELM_CONFIG_HOME=$W/config HELM_DATA_HOME=$W/data
export CHART_CILIUM=$HOME/.cache/supply-chain-poc/08/telechargements/cilium/cilium-1.20.4.tgz
export CHART_COREDNS=$HOME/.cache/supply-chain-poc/08b/telechargements/rke2-coredns-1.47.102.tgz
export CHART_METRICS=$HOME/.cache/supply-chain-poc/08b/telechargements/rke2-metrics-server-3.14.001.tgz
export VALEURS_CILIUM=$W/valeurs.yaml VALEURS_CILIUM_RKE2=$r/poc/bricks/08b-rke2/config/valeurs-cilium.yaml VALEURS_COREDNS=$r/poc/bricks/08b-rke2/config/valeurs-coredns.yaml
echo "# essai.sh (helmfile), début $(date -u +%FT%TZ) ; dossier $W"
echo "helm : $HELM $("$HELM" version --short) ; helmfile : $HELMFILE $("$HELMFILE" version -o short 2>/dev/null || "$HELMFILE" --version 2>&1 | head -1)"
echo "greffons Helm vus avec HELM_PLUGINS vide : [$("$HELM" plugin list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')]"
for f in "$CHART_CILIUM" "$CHART_COREDNS" "$CHART_METRICS" "$VALEURS_CILIUM_RKE2" "$VALEURS_COREDNS" "$here/helmfile.yaml.gotmpl"; do echo "entrée $(basename "$f") : sha256 $(sha256sum < "$f" | cut -c1-16)"; done
# valeurs de Cilium rendues exactement comme rke2.sh, l. 191
sed -e 's/^#.*//' -e 's#@CILIUM_AMD64@#sha256:fa56fecd779584642c7ec2da6872c03c45c1f1043da66665a73ed8c425584d54#' -e 's#@OPERATOR_AMD64@#sha256:77a9b4371faed41dc9c2fb3942b6c02a581158be1d4aa46a0e62956ce2f55ff1#' \
  "$r/poc/bricks/08-trust-plane/cilium/valeurs.yaml" > "$VALEURS_CILIUM"
echo "## références : helm template, comme rke2.sh (sans réseau), rendues deux fois (témoin de stabilité)"
for k in 1 2; do
  ns "$HELM" template cilium "$CHART_CILIUM" --namespace kube-system -f "$VALEURS_CILIUM" -f "$VALEURS_CILIUM_RKE2" > "$W/ref/cilium.$k"
  ns "$HELM" template rke2-coredns "$CHART_COREDNS" --namespace kube-system -f "$VALEURS_COREDNS" > "$W/ref/rke2-coredns.$k"
  ns "$HELM" template rke2-metrics-server "$CHART_METRICS" --namespace kube-system > "$W/ref/rke2-metrics-server.$k"
done
for n in cilium rke2-coredns rke2-metrics-server; do
  if cmp -s "$W/ref/$n.1" "$W/ref/$n.2"; then echo "OK   témoin $n : deux rendus identiques"; else echo "INSTABLE $n : $(diff "$W/ref/$n.1" "$W/ref/$n.2" | grep -c '^[<>]') lignes diffèrent entre deux helm template ; 6 premières (valeurs masquées) :"; diff "$W/ref/$n.1" "$W/ref/$n.2" | grep '^[<>]' | head -6 | sed -E 's/(: ).*/\1<valeur masquée>/' | cut -c1-120 || true; fi
  cp "$W/ref/$n.1" "$W/ref/$n.yaml"
done
for n in cilium rke2-coredns rke2-metrics-server; do echo "ref $n : $(wc -l < "$W/ref/$n.yaml") lignes, sha256 $(sha256sum < "$W/ref/$n.yaml" | cut -c1-16)"; done
echo "## helmfile template, une release à la fois (sans réseau, sans greffon)"
for n in cilium rke2-coredns rke2-metrics-server; do
  rc=0; ( cd "$W" && ns "$HELMFILE" --helm-binary "$HELM" --file "$here/helmfile.yaml.gotmpl" --selector "name=$n" template --skip-deps > "$W/hf/$n.yaml" 2> "$W/hf/$n.err" ) || rc=$?
  echo "helmfile $n : code $rc ; $(wc -l < "$W/hf/$n.yaml") lignes, sha256 $(sha256sum < "$W/hf/$n.yaml" | cut -c1-16) ; stderr : $(wc -l < "$W/hf/$n.err") lignes"
  sed -E 's/[0-9a-f]{40,}/<hex>/g' "$W/hf/$n.err" | head -5 | sed 's/^/   stderr : /'
  if cmp -s "$W/ref/$n.yaml" "$W/hf/$n.yaml"; then echo "OK   $n : sortie identique octet pour octet à helm template"
  else echo "ÉCART $n : $(diff "$W/ref/$n.yaml" "$W/hf/$n.yaml" | grep -c '^[<>]') lignes différentes ; 10 premières (valeurs masquées) :"; diff "$W/ref/$n.yaml" "$W/hf/$n.yaml" | grep '^[<>]' | head -10 | sed -E 's/(: ).*/\1<valeur masquée>/' | cut -c1-120 || true
    cmp -s "$W/ref/$n.1" "$W/ref/$n.2" || echo "     ($n est instable entre deux helm template : écart à juger hors des objets instables)"; fi
done
# ajout du 19/11/2026, après le premier passage (essai-helmfile-1.log) : Cilium génère des certificats à chaque rendu. Comparaison
# des rendus avec les valeurs des seules clés ca.crt, ca.key, tls.crt et tls.key remplacées par un repère, témoin compris.
echo "## comparaison hors certificats générés (valeurs de ca.crt, ca.key, tls.crt, tls.key remplacées)"
mq() { sed -E 's/^( *)(ca\.crt|ca\.key|tls\.crt|tls\.key): .*/\1\2: <certificat>/' "$1"; }
for n in cilium rke2-coredns rke2-metrics-server; do
  mq "$W/ref/$n.1" > "$W/ref/$n.m1"; mq "$W/ref/$n.2" > "$W/ref/$n.m2"; mq "$W/hf/$n.yaml" > "$W/hf/$n.m"
  echo "$n : lignes remplacées $(diff "$W/ref/$n.1" "$W/ref/$n.m1" | grep -c '^>' || true)"
  if cmp -s "$W/ref/$n.m1" "$W/ref/$n.m2"; then echo "OK   témoin $n hors certificats : deux rendus identiques"; else echo "INSTABLE $n hors certificats : $(diff "$W/ref/$n.m1" "$W/ref/$n.m2" | grep -c '^[<>]' || true) lignes"; fi
  if cmp -s "$W/ref/$n.m1" "$W/hf/$n.m"; then echo "OK   $n hors certificats : helmfile identique à helm template"
  else echo "ÉCART $n hors certificats : $(diff "$W/ref/$n.m1" "$W/hf/$n.m" | grep -c '^[<>]' || true) lignes ; 10 premières (valeurs masquées) :"; diff "$W/ref/$n.m1" "$W/hf/$n.m" | grep '^[<>]' | head -10 | sed -E 's/(: ).*/\1<valeur masquée>/' | cut -c1-120 || true; fi
done
echo "## taille : helmfile.yaml contre les appels qu'il remplacerait"
echo "helmfile.yaml.gotmpl : $(grep -vc '^#' "$here/helmfile.yaml.gotmpl") lignes hors commentaires ; appels helm upgrade --install des scripts : rke2.sh l. 166 à 169, cilium.sh $(grep -cE '\bhelm (upgrade|install)' "$r/poc/bricks/08-trust-plane/cilium.sh")"
echo "greffons après l'essai : [$(ls "$HELM_PLUGINS" | tr '\n' ' ')]"
echo "# fin $(date -u +%FT%TZ)"
