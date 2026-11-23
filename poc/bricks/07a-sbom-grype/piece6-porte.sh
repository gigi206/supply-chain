#!/usr/bin/env bash
# Brique 07b, pièce 6 (ajout du 23/11/2026) : porte neuve (scan.rego, scan_test.rego et policy-scan.yaml du patch 07b-t3) dans la
# ConfigMap porte/porte, rendue par cm_porte de la 08 (seule source de la ConfigMap).
# Étapes (une par journal, jamais réécrit) :
#   sec : rien d'écrit dans le cluster, rien dans Zot, rien sur la VM. Copie de HEAD (git archive) hors du dépôt, patch appliqué ;
#         ec opa check et ec opa test des règles du patch ; ConfigMap rendue par le texte de cm_porte de la copie (apply remplacé par
#         cat) et comparée au service clé par clé : seules scan.rego et policy-scan.yaml doivent changer ; porte neuve (ec validate
#         input, politique du patch) contre des prédicats d'avant la tranche 3 et des prédicats neufs du passage 24 du banc.
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/piece6-porte.sh sec  (journal : resultats/piece6-porte-sec.log)
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
racine_depot=$(cd "$here/../../.." && pwd)
e=${1:-}
[ "$e" = sec ] || { echo "usage : $0 sec" >&2; exit 2; }
L=$here/resultats/piece6-porte-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
BANC=$HOME/.cache/supply-chain-poc/07a/t3/banc
T=$HOME/.cache/supply-chain-poc/07a/p6-sec
[ ! -e "$T" ] || { echo "dossier de travail déjà présent : $T" >&2; exit 1; }
mkdir -m 700 "$T"
trap 'find "$HOME/.cache/supply-chain-poc/07a/p6-sec" -delete' EXIT
KO=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
attendu() { [ "$2" = "$3" ] && ok "$1 : $2" || ko "$1 : $2 (attendu : $3)"; }
h() { sha256sum | cut -c1-16; }
exec > "$L" 2>&1
echo "# piece6-porte.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$racine_depot" rev-parse --short=12 HEAD) ; ec $(ec version 2>/dev/null | sed -n 's/^Version *//p' | head -1)"

echo "## copie de HEAD, patch appliqué"
A=$T/arbre; mkdir "$A"
git -C "$racine_depot" archive HEAD poc/bricks/07a-sbom-grype poc/bricks/08-trust-plane poc/bricks/10-independent-replay/resultats | tar -x -C "$A"
P07=$A/poc/bricks/07a-sbom-grype
patch -p1 -d "$A" -s --dry-run < "$P07/politique/07b-t3.patch" > /dev/null && patch -p1 -d "$A" -s < "$P07/politique/07b-t3.patch" \
  && ok "patch 07b-t3 appliqué à la copie ($(h < "$P07/politique/07b-t3.patch"))" || ko "patch non appliqué"
attendu "politique du patch : vex_age_max_jours" "$(yq '.sources[0].ruleData.vex_age_max_jours' "$P07/politique/porte/policy-scan.yaml")" 30
attendu "politique du patch : statuts acceptés" "$(yq -o json '.sources[0].ruleData.vex_statuts_acceptes' "$P07/politique/porte/policy-scan.yaml" | jq -c .)" '["not_affected"]'

echo "## règles du patch : ec opa check et ec opa test"
(cd "$P07/politique/porte" && ec opa check scan.rego scan_test.rego) && ok "ec opa check" || ko "ec opa check"
n=$(grep -c '^test_' "$P07/politique/porte/scan_test.rego")
attendu "ec opa test" "$(cd "$P07/politique/porte" && ec opa test scan.rego scan_test.rego 2>&1 | tail -1)" "PASS: $n/$n"

echo "## ConfigMap porte : texte de cm_porte de la copie, apply remplacé par cat"
P08=$A/poc/bricks/08-trust-plane
f=$(awk '/^cm_porte\(\)/,/^}/' "$P08/politique.sh")
attendu "cm_porte de la copie = cm_porte de HEAD" "$(printf '%s\n' "$f" | h)" "$(git -C "$racine_depot" show HEAD:poc/bricks/08-trust-plane/politique.sh | awk '/^cm_porte\(\)/,/^}/' | h)"
g=${f/kubectl apply --server-side -f - >\/dev\/null/cat}
attendu "cm_porte : une seule substitution apply -> cat" "$(printf '%s\n' "$g" | grep -c -- '-o yaml | cat$')/$(printf '%s\n' "$g" | grep -c 'kubectl apply')" 1/0
eval "${g/cm_porte()/cm_porte_rendu()}"
here_sauve=$here; here=$P08 R=$P08/resultats P=$HOME/.cache/supply-chain-poc/08/pki
cm_porte_rendu < /dev/null > "$T/cm.yaml" 2> "$T/cm.err"; c=$?
here=$here_sauve
attendu "rendu de la ConfigMap porte, code" "$c" 0
kubectl create --dry-run=client -o json -f "$T/cm.yaml" < /dev/null > "$T/cm.json"
kubectl get cm -n porte porte -o json < /dev/null > "$T/cm.service"
cles() { jq -r '.data | to_entries[] | "\(.key) \(.value | @base64)"' "$1" | while read -r k v; do echo "$k $(printf '%s' "$v" | base64 -d | h)"; done; }
cles "$T/cm.service" > "$T/cles.service"; cles "$T/cm.json" > "$T/cles.rendu"
attendu "clés présentes, service et rendu" "$(cut -d' ' -f1 "$T/cles.service" | paste -sd, -)" "$(cut -d' ' -f1 "$T/cles.rendu" | paste -sd, -)"
attendu "clés dont le contenu change" "$(join "$T/cles.service" "$T/cles.rendu" | awk '$2 != $3 {print $1}' | paste -sd, -)" "policy-scan.yaml,scan.rego"
join "$T/cles.service" "$T/cles.rendu" | awk '$2 != $3 {print "  " $1 " : service " $2 ", rendu " $3}'
c=0; kubectl diff --server-side -f "$T/cm.yaml" < /dev/null > "$T/cm.diff" 2>&1 || c=$?
echo "  kubectl diff --server-side porte : code $c, $(grep -c -E '^[-+] ' "$T/cm.diff") lignes changées"

echo "## porte neuve (ec validate input, politique du patch) contre des prédicats d'avant et neufs"
mkdir "$T/regles"; cp "$P07/politique/porte/scan.rego" "$T/regles/"
sed "s#/etc/porte/regles-scan#$T/regles#" "$P07/politique/porte/policy-scan.yaml" > "$T/politique.yaml"
D=1111111111111111111111111111111111111111111111111111111111111111
juger() { # libellé prédicat id-en-KEV verdict-attendu
  local c=0 v
  jq -c --arg d "$D" --arg k "$3" '{digest: $d, statements: [{_type: "https://in-toto.io/Statement/v0.1", subject: [{name: "sample-app", digest: {sha256: $d}}],
    predicateType: "https://supply-chain.example/scan/v1", predicate: (.scanner.db.built = .scannedAt | .vulnerabilities |= map(if .id == $k then .kev = true else . end))}]}' "$2" > "$T/$1.json"
  ec validate input "$T/$1.json" --policy "$T/politique.yaml" --info --output json > "$T/$1.ec" 2> "$T/$1.err" || c=$?
  v=$(jq -r '[.filepaths[].violations[]?.metadata.code] | unique | join(",")' "$T/$1.ec" 2>/dev/null || echo sans-verdict)
  attendu "$1" "$c $v" "$4"
}
juger avant-t3-sans-kev "$BANC/avant-t3.json" AUCUNE "0 "
juger compat-image-sans-kev "$BANC/compat-image.json" AUCUNE "0 "
juger compat-deb-sans-kev "$BANC/compat-deb.json" AUCUNE "0 "
juger avant-t3-une-kev "$BANC/avant-t3.json" "$(jq -r '.vulnerabilities[0].id' "$BANC/avant-t3.json")" "1 scan.kev_without_vex"
juger complet-kev-ecartee "$BANC/cas/complet/scan.json" GHSA-mqqf-5wvp-8fh8 "0 "
juger deb-complet-kev-ecartee "$BANC/cas/deb-complet/scan.json" GO-2025-3849 "0 "
juger repli-une-kev "$BANC/cas/repli/scan.json" "$(jq -r '.vulnerabilities[0].id' "$BANC/cas/repli/scan.json")" "1 scan.kev_without_vex"
echo "  note : VEX du banc horodatés le 22/11 à 08:08:08 ; admis tant qu'ils ont moins de 30 jours (jusqu'au 22/12)"
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$KO" = 0 ] && echo "bilan : tenue" || echo "bilan : $KO KO"
