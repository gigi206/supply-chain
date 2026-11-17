#!/usr/bin/env bash
# Brique 05, M4a : banc de l'étape releve de m4a.sh, hors cluster et hors Zot. Faux kubectl et faux oras dans le PATH ; le script
# est copié dans un dossier neuf (lien dur), avec des liens vers politiques/ et vers la 08 : son journal et chrono.tsv restent dans
# le banc. Les objets « en service » sont ceux du dépôt, sauf trois écarts injectés (une valeur, un champ en service seulement, une
# clé de clé publique changée) ; ConfigMap porte rendue depuis les fichiers du dépôt, une clé changée ; Zot : une référence
# présente, une refusée (401, doit donner NON CONCLUANT), une absente (not found).
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4a-banc.sh <dossier-neuf> <m4a.sh>
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
# faux kubectl du banc : lit le dépôt, injecte des écarts
set -euo pipefail
repo=$BANC_REPO
case "$*" in
  "get -f "*" -o json")
    f=$3; n=$(jq -r .metadata.name "$f")
    case "$n" in
      construction-rpm-sans-sortie) jq '.spec.policyTypes = ["Egress"]' "$f" ;;
      zone-build) jq '.spec.validationActions = (.spec.validationActions // ["Deny"]) | .spec.ajoutDuServeur = true' "$f" ;;
      taches-plateforme) jq '.spec.authorities[0].key.data = "-----BEGIN PUBLIC KEY-----\nAUTRE\n-----END PUBLIC KEY-----\n"' "$f" ;;
      limites-obligatoires) echo 'Error from server (NotFound): validatingpolicies "limites-obligatoires" not found' >&2; exit 1 ;;
      *) cat "$f" ;;
    esac ;;
  "get configmap porte -n porte -o json")
    p=$repo/poc/bricks/08-trust-plane/politique/porte; q=$repo/poc/bricks/07a-sbom-grype/politique/porte
    jq -n --rawfile a "$p/porte.rego" --rawfile b "$p/taches.yml" --rawfile c "$p/policy.yaml" --rawfile e "$q/scan.rego" \
      '{data: {"porte.rego": $a, "taches.yml": ($b + "# changé\n"), "policy.yaml": $c, "scan.rego": $e, "chains.pub": "-----BEGIN PUBLIC KEY-----\nX\n"}}' ;;
  "get configmap config-defaults -n tekton-pipelines -o json")
    jq -n --rawfile d "$repo/poc/bricks/08c-durcissement/politiques/tekton-defauts.yaml" '{data: {"default-container-resource-requirements": $d}}' ;;
  "get configmap feature-flags -n tekton-pipelines -o json")
    echo '{"data":{"trusted-resources-verification-no-match-policy":"fail","disable-inline-spec":"pipeline,pipelinerun,taskrun"}}' ;;
  "get networkpolicies -n builds -o json") echo '{"items":[{"metadata":{"name":"construction-rpm-sans-sortie"}},{"metadata":{"name":"construction-sans-sortie"}}]}' ;;
  "get ciliumnetworkpolicies -n builds -o json") echo '{"items":[{"metadata":{"name":"prefetch-rpm-sortie"}}]}' ;;
  "get imagevalidatingpolicies.policies.kyverno.io -o json")
    echo '{"items":[{"metadata":{"name":"essai"},"spec":{"matchImageReferences":[{"glob":"sc/builds/essai-signature*"}]}}]}' ;;
  "get "*".kyverno.io -A -o json") echo '{"items":[{"metadata":{"name":"zone-build"}}]}' ;;
  *) echo "faux kubectl : appel non prévu : $*" >&2; exit 3 ;;
esac
K
cat > "$B/bin/oras" <<'O'
#!/usr/bin/env bash
# faux oras du banc : manifest fetch seulement
set -euo pipefail
[ "$1 $2 $3" = "manifest fetch --descriptor" ] || { echo "faux oras : appel non prévu : $*" >&2; exit 3; }
ref=${*: -1}
case "$ref" in
  *packaging-rpm*) echo 'Error: failed to fetch the content of "x": x: not found' >&2; exit 1 ;;
  *rocky9-bootstrap*) echo 'Error response from registry: unauthorized: authentication required' >&2; exit 1 ;;
  *) echo "{\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\",\"digest\":\"${ref##*@}\",\"size\":1}" ;;
esac
O
chmod +x "$B/bin/kubectl" "$B/bin/oras"

set +e
BANC_REPO=$repo PATH="$B/bin:$PATH" DISTRO=rke2 "$B/bricks/05-rpm-mock/m4a.sh" releve > "$B/sortie.txt" 2>&1
rc=$?
set -e
j=$B/bricks/05-rpm-mock/resultats/m4a-releve.log
echo "code de releve : $rc"
n=0; k=0
verifie() { if grep -q -F -- "$2" "$j"; then echo "OK   $1"; n=$((n + 1)); else echo "KO   $1 : « $2 » absent du journal"; k=$((k + 1)); fi; }
absent() { if grep -q -F -- "$2" "$j"; then echo "KO   $1 : « $2 » présent"; k=$((k + 1)); else echo "OK   $1"; n=$((n + 1)); fi; }
if [ "$rc" = 0 ]; then echo "OK   code 0"; n=$((n + 1)); else echo "KO   code $rc"; k=$((k + 1)); fi
verifie "écart de valeur détecté" "spec.policyTypes : dépôt"
verifie "champ en service seulement détecté" "spec.ajoutDuServeur : en service seulement"
verifie "objet égal reconnu" "égal : CiliumNetworkPolicy builds/prefetch-rpm-sortie"
verifie "objet absent signalé" "ABSENT : ValidatingPolicy limites-obligatoires (08c)"
verifie "clé changée détectée" "spec.authorities[0].key.data : dépôt sha256"
absent  "aucune clé affichée (journal)" "BEGIN PUBLIC KEY"
absent  "aucune clé affichée (contenu AUTRE)" "AUTRE"
verifie "ConfigMap : clé changée" "DIFFÉRENT : taches.yml"
verifie "ConfigMap : clé égale" "égal : porte.rego"
verifie "ConfigMap : fichier 07a comparé" "égal : scan.rego"
verifie "ConfigMap : clé attendue absente" "ABSENTE en service : scan-verifier.sh"
verifie "ConfigMap : clé non comparée, nom seul" "clé présente, non comparée : chains.pub"
verifie "config-defaults égal" "égal : config-defaults, default-container-resource-requirements"
verifie "feature-flags" "feature-flags : disable-inline-spec=pipeline,pipelinerun,taskrun"
verifie "noms des NetworkPolicy" "networkpolicies : construction-rpm-sans-sortie construction-sans-sortie"
verifie "ImageValidatingPolicy" "ImageValidatingPolicy essai : globs sc/builds/essai-signature*"
verifie "Zot présent" "OK   image d'outillage de M3 : présent"
verifie "Zot refus = non concluant" "NON CONCLUANT   image de bootstrap"
verifie "Zot not found = absent" "OK   artefact de packaging rpm, avant M4a : absent"
[ -f "$B/bricks/05-rpm-mock/resultats/chrono.tsv" ] && grep -q '05 M4a releve fait' "$B/bricks/05-rpm-mock/resultats/chrono.tsv" \
  && { echo "OK   chrono.tsv du banc écrit (fin)"; n=$((n + 1)); } || { echo "KO   chrono.tsv du banc"; k=$((k + 1)); }
echo "bilan : $n OK, $k KO"
[ "$k" = 0 ]
