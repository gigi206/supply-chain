#!/usr/bin/env bash
# Brique 05, M4a : banc de l'étape politiques de m4a.sh (complément de releve), hors cluster. Faux kubectl dans le PATH ; script
# copié dans un dossier neuf (lien dur), liens vers politiques/ et vers la 08 ; journal et chrono.tsv restent dans le banc.
# « En service » : les documents du dépôt, la 08c rendue en Deny comme par h5_deny, sauf un écart injecté sur stepactions-interdites ;
# liste des noms en service : ceux du dépôt, moins zone-confiance, plus un nom intrus.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4a-banc-politiques.sh <dossier-neuf> <m4a.sh>
set -euo pipefail
B=$1; SCRIPT=$2
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
repo=$(git rev-parse --show-toplevel)
mkdir -p "$B/bricks/05-rpm-mock/resultats" "$B/bin"
ln "$SCRIPT" "$B/bricks/05-rpm-mock/m4a.sh"
ln -s "$repo/poc/bricks/05-rpm-mock/politiques" "$B/bricks/05-rpm-mock/politiques"
ln -s "$repo/poc/bricks/08-trust-plane" "$B/bricks/08-trust-plane"

cat > "$B/bin/kubectl" <<'K'
#!/usr/bin/env bash
set -euo pipefail
repo=$BANC_REPO
case "$*" in
  "get -f "*" -o json")
    f=$3
    case "$(jq -r .metadata.name "$f")" in
      stepactions-interdites) jq '.spec.validationActions = ["Audit"]' "$f" ;;
      *) cat "$f" ;;
    esac ;;
  "get validatingpolicies.policies.kyverno.io -o json")
    { yq -N -r 'select(.kind == "ValidatingPolicy") | .metadata.name' "$repo/poc/bricks/08-trust-plane/politique/admission.yaml"
      yq -N -r 'select(.kind == "ValidatingPolicy") | .metadata.name' "$repo/poc/bricks/08c-durcissement/politiques/kyverno/durcissement.yaml"
      echo intrus; } | grep -v '^zone-confiance$' | jq -R '{metadata: {name: .}}' | jq -s '{items: .}' ;;
  *) echo "faux kubectl : appel non prévu : $*" >&2; exit 3 ;;
esac
K
chmod +x "$B/bin/kubectl"

set +e
BANC_REPO=$repo PATH="$B/bin:$PATH" DISTRO=rke2 "$B/bricks/05-rpm-mock/m4a.sh" politiques > "$B/sortie.txt" 2>&1
rc=$?
set -e
j=$B/bricks/05-rpm-mock/resultats/m4a-politiques.log
echo "code de politiques : $rc"
n=0; k=0
verifie() { if grep -q -E -- "$2" "$j"; then echo "OK   $1"; n=$((n + 1)); else echo "KO   $1 : motif « $2 » absent"; k=$((k + 1)); fi; }
if [ "$rc" = 0 ]; then echo "OK   code 0"; n=$((n + 1)); else echo "KO   code $rc"; k=$((k + 1)); fi
c08=$(grep -c ' (08) (spec' "$j" || true); c08c=$(grep -c ' (08c, rendu Deny) (spec' "$j" || true)
if [ "$c08" = 5 ] && [ "$c08c" = 4 ]; then echo "OK   5 politiques de la 08 et 4 de la 08c comparées"; n=$((n + 1)); else echo "KO   comparées : $c08 (08), $c08c (08c)"; k=$((k + 1)); fi
verifie "écart injecté sur stepactions-interdites" '^DIFFÉRENT : ValidatingPolicy stepactions-interdites \(08\)'
verifie "08c égale une fois rendue en Deny" '^égal : ValidatingPolicy limites-obligatoires \(08c, rendu Deny\)'
verifie "décompte des noms" '^dépôt : 9 ; en service : 9 ; en service hors du dépôt : intrus ; dans le dépôt, absentes en service : zone-confiance$'
if grep -q 'non prévu' "$B/sortie.txt"; then echo "KO   appel imprévu du faux kubectl"; k=$((k + 1)); else echo "OK   aucun appel imprévu"; n=$((n + 1)); fi
grep -q '05 M4a politiques fait' "$B/bricks/05-rpm-mock/resultats/chrono.tsv" && { echo "OK   chrono.tsv du banc"; n=$((n + 1)); } || { echo "KO   chrono.tsv du banc"; k=$((k + 1)); }
echo "bilan : $n OK, $k KO"
[ "$k" = 0 ]
