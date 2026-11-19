#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : mesure d'un autre jour dans Kata (pas avant le 20/11/2026 à 00:00 UTC), préparée à sec le 19/11/2026.
# Prédictions JK1 à JK3 et JT1 à JT5 : m1b-predictions.md, commitées avant. Scripts inchangés (m1b.sh, m1b-builders.sh) :
#   ancienne forme, PREFIXE m1b-20 : prealables, pod_c (outillage), prealables_boot, pod_e (bootstrap)
#   forme de la tâche, PREFIXE m1bt-20 : prealables, banc, essai_prefetch, essai_construire
# Chaque étape écrit un journal neuf dans resultats/ ; un journal déjà présent arrête tout (aucun écrasement). La première étape en
# échec arrête la suite. Le bilan confronte les valeurs des journaux neufs à celles du 19/11 (m1b-pod_c.log, m1b-pod_e.log,
# m1b-builders-m1bt3-*.log). Aucune politique, aucune signature, aucune écriture dans Zot.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-jour-kata.sh < /dev/null > poc/bricks/05-rpm-mock/resultats/m1b-jour-kata.log 2>&1
set -euo pipefail
export LC_ALL=C
G=$(git rev-parse --show-toplevel)
B=$G/poc/bricks/05-rpm-mock
R=$B/resultats
cd "$G"
echo "# m1b-jour-kata.sh, début $(date -u +%FT%TZ) ; HEAD $(git rev-parse --short=12 HEAD)"
[ "$(date -u +%Y%m%d)" -ge 20261120 ] || { echo "KO   pas avant le 20/11/2026 à 00:00 UTC" >&2; exit 2; }
export DISTRO=rke2 KUBECONFIG=${KUBECONFIG:-$HOME/.kube/supply-chain-poc.yaml}
echo "scripts : m1b.sh $(sha256sum < "$B/m1b.sh" | cut -c1-16) ; m1b-builders.sh $(sha256sum < "$B/m1b-builders.sh" | cut -c1-16)"
nko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; nko=$((nko + 1)); }

lancer() { # script préfixe étape journal
  local j=$R/$4 c=0
  [ ! -e "$j" ] || { echo "KO   journal déjà présent : $4" >&2; exit 2; }
  echo "$(date -u +%FT%TZ) $1 $3 (PREFIXE $2) : journal $4"
  PREFIXE=$2 mise exec -- "$B/$1" "$3" < /dev/null > "$j" 2>&1 || c=$?
  echo "$(date -u +%FT%TZ)    code $c"
  [ "$c" -eq 0 ] || { echo "KO   arrêt sur $1 $3" >&2; exit "$c"; }
}

lancer m1b.sh m1b-20 prealables m1b-20-prealables.log
lancer m1b.sh m1b-20 pod_c m1b-20-pod_c.log
lancer m1b.sh m1b-20 prealables_boot m1b-20-prealables_boot.log
lancer m1b.sh m1b-20 pod_e m1b-20-pod_e.log
for e in prealables banc essai_prefetch essai_construire; do
  lancer m1b-builders.sh m1bt-20 "$e" "m1b-builders-m1bt-20-$e.log"
done

echo "## bilan : valeurs du 20/11 contre celles du 19/11"
val() { # journal motif sed : première valeur extraite
  sed -n "$2" "$R/$1" | head -n 1
}
compare() { # libellé journal-neuf journal-19 motif
  local a b
  a=$(val "$2" "$4"); b=$(val "$3" "$4")
  if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "$1 : $a"; else ko "$1 : 20/11 « $a », 19/11 « $b »"; fi
}
ARCH='s/.*archive du pod : .* sha256 \([0-9a-f]\{64\}\)$/\1/p'
compare "pod_c, archive de l'outillage" m1b-20-pod_c.log m1b-pod_c.log "$ARCH"
compare "pod_e, archive du bootstrap" m1b-20-pod_e.log m1b-pod_e.log "$ARCH"
compare "pod_e, liste rpm -qa après" m1b-20-pod_e.log m1b-pod_e.log 's/.*liste rpm -qa après : .* sha256 \([0-9a-f]\{64\}\)$/\1/p'
N=m1b-builders-m1bt-20 V=m1b-builders-m1bt3
for x in po pb co cb; do
  compare "script-$x rendu" "$N-prealables.log" "$V-prealables.log" "s/^OK   script-$x : .* sha256 \([0-9a-f]\{64\}\)$/\1/p"
done
for x in o b; do
  compare "banc $x, DIGEST_CONSTRUIT" "$N-banc.log" "$V-banc.log" "/## banc $x : code 0/,/^##/s/.*résultat DIGEST_CONSTRUIT : //p"
done
compare "banc o, racine" "$N-banc.log" "$V-banc.log" '/## banc o : début/,/## banc o : code/s/.*racine : .* sha256 \([0-9a-f]\{64\}\)$/\1/p'
compare "banc b, racine" "$N-banc.log" "$V-banc.log" '/## banc b : début/,/## banc b : code/s/.*racine : .* sha256 \([0-9a-f]\{64\}\)$/\1/p'
for r in baseos98 appstream98 epel9 baseos97; do
  compare "prefetch, repomd.xml de $r" "$N-essai_prefetch.log" "$V-essai_prefetch.log" "s/^ *$r : repomd.xml \([0-9a-f]\{64\}\).*/\1/p"
done
for x in po pb; do
  compare "prefetch $x, liste de l'arbre écrit" "$N-essai_prefetch.log" "$V-essai_prefetch.log" "s/^arbre écrit par le pod [a-z0-9-]*-$x : .* liste \([0-9a-f]\{64\}\)$/\1/p"
done
for x in co cb; do
  compare "construire $x, DIGEST_CONSTRUIT" "$N-essai_construire.log" "$V-essai_construire.log" "s/^OK   DIGEST_CONSTRUIT du pod [a-z0-9-]*-$x = celui du banc : //p"
  compare "construire $x, image.tar" "$N-essai_construire.log" "$V-essai_construire.log" "s/^OK   image.tar du pod [a-z0-9-]*-$x = celle du banc (sha256) : //p"
done
echo "# fin $(date -u +%FT%TZ) ; KO $nko"
exit $((nko > 0))
