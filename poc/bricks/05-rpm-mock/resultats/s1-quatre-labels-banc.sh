#!/usr/bin/env bash
# Banc hors cluster du correctif s1-quatre-labels.patch (cascade de M1b, 20/11/2026), écrit avant toute application.
# Ni cluster, ni Zot, ni réseau : kubectl, args_apiserver, sur et pod_spec sont des doublures.
# A : forme du diff contre le s1.sh « avant » donné en argument : une seule ligne changée (la valeur attendue du NotIn), plus des
#     lignes d'en-tête insérées ; rien d'autre.
# B : bash -n ; shellcheck (UTF-8) : mêmes remarques avant et copie.
# C : la valeur attendue de la copie est celle que donne le même jq (sort, join) sur le manifeste du dépôt
#     (08c-durcissement/politiques/cilium-sortie/builds-sans-internet.yaml), et sur la liste attendue par sortie-builds.sh rejeu.
# D : la vraie etape_prealables et le vrai attendu, extraits de chaque fichier, joués sous set -euo pipefail avec les doublures ;
#     NotIn servi dans l'ordre du manifeste (quatre labels), à trois labels, et avec un quatrième label faux.
# Non couvert : le vrai cluster (la lecture réelle est l'étape prealables elle-même, sous un PREFIXE neuf), ssh, kube-apiserver.
# Usage : s1-quatre-labels-banc.sh <racine du dépôt> <s1.sh avant> <copie modifiée de s1.sh> <dossier du banc, absent>
#         [lignes d'en-tête insérées, 3]   (après application : s1.sh avant = celui du commit précédent, en-tête de 4 lignes)
set -uo pipefail
export LC_ALL=C
D=$1; S1A=$2; S1N=$3; B=$4; HE=${5:-3}
MANIFESTE=$D/poc/bricks/08c-durcissement/politiques/cilium-sortie/builds-sans-internet.yaml
SORTIE=$D/poc/bricks/08c-durcissement/sortie-builds.sh
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/t"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# s1-quatre-labels-banc.sh, $(date -u +%FT%TZ) ; s1.sh avant $(sha256sum < "$S1A" | cut -c1-64) ; copie $(sha256sum < "$S1N" | cut -c1-64)"
ANCIEN='    "prefetch-deb,prefetch-gomod,prefetch-rpm"'

echo "## A : forme du diff"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 1
egal "ligne retirée : la valeur attendue à trois labels" "$(grep '^< ' "$B/diff.txt" | cut -c3-)" "$ANCIEN"
egal "blocs : un ajout (en-tête), un changement (code)" "$(grep -E '^[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$' "$B/diff.txt" | sed 's/[0-9,]//g' | paste -sd' ')" "a c"
egal "lignes ajoutées (en-tête $HE, code 1)" "$(grep -c '^>' "$B/diff.txt")" "$((HE + 1))"
egal "lignes d'en-tête ajoutées : commentaires" "$(grep '^> ' "$B/diff.txt" | grep -c '^> #')" "$HE"
NOUVEAU=$(grep '^> ' "$B/diff.txt" | grep -v '^> #' | cut -c3-)
echo "relevé : ligne de code ajoutée : $NOUVEAU"

echo "## B : syntaxe et shellcheck"
egal "bash -n" "$(bash -n "$S1N" && echo ok)" ok
sc() { (cd "$D" && LC_ALL=C.UTF-8 mise exec -- shellcheck -x -e SC1091 "$1" 2>/dev/null) | grep -o 'SC[0-9]*' | sort | uniq -c; }   # UTF-8 : sinon shellcheck s'arrête sur les accents
sc "$S1A" > "$B/sc-avant"; sc "$S1N" > "$B/sc-copie"
egal "shellcheck : remarques, avant et copie égales" "$(cmp -s "$B/sc-avant" "$B/sc-copie" && echo égales)" égales
echo "relevé : shellcheck, remarques de la copie : $(awk '{print $2 "×" $1}' "$B/sc-copie" | paste -sd' ')"

echo "## C : valeur attendue contre ses sources"
V=$(sed -n 's/^    "\(prefetch-[a-z,-]*\)"$/\1/p' <<< "$NOUVEAU")
egal "valeur de la copie, contre le manifeste du dépôt (jq sort, join)" "$V" \
  "$(yq -o=json '.spec.endpointSelector.matchExpressions[0].values' "$MANIFESTE" | jq -r 'sort | join(",")')"
egal "valeur de la copie, contre la liste attendue par sortie-builds.sh rejeu" "$V" \
  "$(sed -n '/^etape_rejeu() /,/^}/p' "$SORTIE" | sed -n "s/^  attendu \"NotIn de builds-sans-internet\" \"\$(notin)\" '\(.*\)'$/\1/p" | jq -r 'sort | join(",")')"

echo "## D : etape_prealables jouée avec des doublures"
extraire() { # fichier sortie : attendu et etape_prealables, tels quels
  { grep '^attendu() ' "$1"; sed -n '/^etape_prealables() /,/^}$/p' "$1"; } > "$2"
}
extraire "$S1A" "$B/f-avant.sh"; extraire "$S1N" "$B/f-copie.sh"
egal "fonctions extraites (lignes, avant et copie)" "$(wc -l < "$B/f-avant.sh") $(wc -l < "$B/f-copie.sh")" "23 23"   # attendu (1) et etape_prealables (22)
cat > "$B/doublures.sh" <<'EOF'
T=$BANC_T; D_CONF=/etc/rancher/rke2; AMORCE=amorce-du-banc
kubectl() {
  case "$*" in
    "get cnp -n builds prefetch-rpm-sortie") return 0 ;;
    "get cnp -n builds builds-sans-internet -o json") cat "$BANC_CNP"; return 0 ;;
    "create --dry-run=server -f $T/s1-05-racine.json") echo admis; return 0 ;;
    "get node sc-build -o json") echo '{"status": {"allocatable": {"cpu": "4", "memory": "8Gi"}}}'; return 0 ;;
    "get pods -A --field-selector spec.nodeName=sc-build,status.phase=Running -o json") echo '{"items": []}'; return 0 ;;
    *) echo "appel inattendu : kubectl $*" >&2; return 99 ;;
  esac
}
args_apiserver() { echo "--admission-control-config-file=$D_CONF/pod-security.yaml"; }
sur() { echo "1000 /var/lib/zot"; }
pod_spec() { echo '{}' > "$T/$1.json"; }
EOF
cnp() { # nom valeurs-json : objet CiliumNetworkPolicy servi par la doublure
  jq -n --argjson v "$2" '{spec: {endpointSelector: {matchExpressions: [{key: "tekton.dev/task", operator: "NotIn", values: $v}]}}}' > "$B/cnp-$1.json"
}
cnp quatre "$(yq -o=json -I=0 '.spec.endpointSelector.matchExpressions[0].values' "$MANIFESTE")"
cnp trois '["prefetch-gomod","prefetch-deb","prefetch-rpm"]'
cnp faux '["prefetch-gomod","prefetch-deb","prefetch-rpm","prefetch-racine-rpmx"]'
echo "relevé : NotIn servi pour « quatre » (ordre du manifeste) : $(jq -c '.spec.endpointSelector.matchExpressions[0].values' "$B/cnp-quatre.json")"
jouer() { # fonctions cas : « code lignes-OK-du-NotIn lignes-KO-du-NotIn appels-inattendus »
  local r=0
  BANC_T=$B/t BANC_CNP=$B/cnp-$2.json bash -c 'set -euo pipefail; . "$1"; . "$2"; etape_prealables' _ "$B/doublures.sh" "$B/f-$1.sh" \
    < /dev/null > "$B/sortie-$1-$2.txt" 2>&1 || r=$?
  echo "$r $(grep -c '^OK   NotIn de builds-sans-internet' "$B/sortie-$1-$2.txt") $(grep -c '^KO   NotIn de builds-sans-internet' "$B/sortie-$1-$2.txt") $(grep -c 'appel inattendu' "$B/sortie-$1-$2.txt")"
}
egal "copie, quatre labels : code 0, NotIn OK, aucun appel inattendu" "$(jouer copie quatre)" "0 1 0 0"
egal "copie, quatre labels : étape jusqu'au bout (lignes OK, place libre)" \
  "$(grep -c '^OK ' "$B/sortie-copie-quatre.txt") $(grep -c '^libre sous /var/lib/zot : 1000 Mo$' "$B/sortie-copie-quatre.txt")" "4 1"
egal "copie, trois labels : arrêt sur le NotIn" "$(jouer copie trois)" "1 0 1 0"
egal "copie, quatrième label faux : arrêt sur le NotIn" "$(jouer copie faux)" "1 0 1 0"
egal "avant, quatre labels : arrêt sur le NotIn (le correctif est nécessaire)" "$(jouer avant quatre)" "1 0 1 0"
egal "avant, trois labels : code 0 (témoin des doublures)" "$(jouer avant trois)" "0 1 0 0"
egal "copie, trois labels : rien après le NotIn" "$(grep -c 'kube-apiserver\|admis\|libre sous' "$B/sortie-copie-trois.txt")" 0

echo "# bilan : $n OK, $k KO"
[ "$k" = 0 ]
