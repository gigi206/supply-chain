#!/usr/bin/env bash
# Brique 08, jalon J6 : politique (accord du propriétaire du 29/10/2026).
#   image      Kyverno v1.19.2 : 5 images (index multi-plateformes) signées sans clé par release.yaml au tag v1.19.2
#              (commit du tag, déclencheur push ; signatures dans ghcr.io/kyverno/signatures) ; même digest sur
#              reg.kyverno.io et ghcr.io ; index et bundles de signature copiés dans Zot, signatures revérifiées sur la copie
#   installer  install.yaml : non signé, mais identique au manifeste du commit du tag (signé, vérifié par GitHub), à la
#              version près ; empreinte épinglée ; réécrit vers Zot, contrôleurs en zone confiance, CA du PoC ;
#              contrôle : toutes les images tirées viennent de Zot
#   parite     C-2 (ADR 0000) : les 17 cas du banc C (setup.sh du banc, poussés dans Zot sous bench/) et les 8 cas
#              d'horodatage de J5, évalués par le CLI (kyverno apply) et à l'admission (kubectl create --dry-run=server)
#              avec le même fichier de politique et le même pod ; tableau cas par cas dans resultats/politique-parite.tsv
# Aucun secret en argument de commande : mots de passe par fichier 0600.
#
# Usage (racine du dépôt) : mise run confiance:politique -- <étape>…   (journal : resultats/politique-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
KY_DEPOT=kyverno/kyverno
KY_COMMIT=e63308f1e16c05cd009ac4864be6ec25c66b49be   # tag léger v1.19.2 (« chore: bump chart to 3.9.2 for v1.19.2 »)
KY_ID=https://github.com/kyverno/kyverno/.github/workflows/release.yaml@refs/tags/v1.19.2
KY_INSTALL=4f785937dc7fe49a0731108b15def1538923c73d9236255bc69d94d498037969   # install.yaml (asset de la release)
# image index (5 plateformes), relevé du 29/10/2026 : même digest sur reg.kyverno.io et ghcr.io
KY_IMAGES="kyverno sha256:c8c4dd09e720d2cd7fd24ca73ac28e46651001372f988e0cba3f2f612f04b955
kyvernopre sha256:27f3cc52e628559b56d08363b85316819802086c9808606914f7805a244148f4
background-controller sha256:c46e124f21ef8a6bb4b48de57106808b1007edcd5ddd4ff7df5d23b9efa60ce2
cleanup-controller sha256:d7340aa7c9315080c3dafa7b765d090ced37353e89e5cd7a3f9ac69e8fb532b2
reports-controller sha256:5fb6d3e738050dbce84f60ecabaede7665fbe0578d07c1e8c912443b035e79c3"
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # images d'essai signées en J4
BANC=$repo/poc/benchmarks/kyverno-seul
NS_ESSAI=bancc   # espace des pods d'essai (jamais créés : dry-run côté serveur)
DL=$O/telechargements/kyverno
T=$W/politique
trap 'rm -rf "$T/auth" "$W/refus.out"' EXIT
mkdir -p "$T" "$DL"

verifier_ky() { # référence [variables d'environnement…] : signature sans clé de la release v1.19.2, par identité exacte
  local ref=$1; shift
  env "$@" cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity "$KY_ID" \
    --certificate-github-workflow-sha "$KY_COMMIT" --certificate-github-workflow-trigger push \
    --certificate-github-workflow-repository "$KY_DEPOT" "$ref" > "$T/cosign.json" 2> "$T/cosign.err" \
    || { cat "$T/cosign.err" >&2; exit 1; }
  echo "OK   signature de $ref : $(jq -r '[.[].critical.type] | unique | join(",")' "$T/cosign.json"), $(jq length "$T/cosign.json") signature(s)"
}

etape_image() {
  local n d a b s
  [ "$(gh api "repos/$KY_DEPOT/git/ref/tags/v1.19.2" --jq '.object.type + " " + .object.sha')" = "commit $KY_COMMIT" ] \
    && [ "$(gh api "repos/$KY_DEPOT/commits/$KY_COMMIT" --jq '.commit.verification.verified')" = true ] \
    && echo "OK   tag v1.19.2 → commit $KY_COMMIT (signature du commit vérifiée par GitHub)" \
    || { echo "KO   tag v1.19.2" >&2; exit 1; }
  mkdir -p "$T/auth" && chmod 700 "$T/auth"
  auth_zot "$T/auth/zot.json"
  cat /etc/ssl/certs/ca-certificates.crt "$P/ca-poc.crt" > "$T/ca-tous.pem"   # cosign joint aussi le TUF de Sigstore
  while read -r n d; do
    echo "## $n"
    a=$(crane digest "reg.kyverno.io/kyverno/$n:v1.19.2"); b=$(crane digest "ghcr.io/kyverno/$n:v1.19.2")
    [ "$a" = "$d" ] && [ "$b" = "$d" ] && echo "OK   reg.kyverno.io et ghcr.io : v1.19.2 → $d (= digest épinglé)" \
      || { echo "KO   $n : reg.kyverno.io $a, ghcr.io $b, épinglé $d" >&2; exit 1; }
    verifier_ky "ghcr.io/kyverno/$n@$d" COSIGN_REPOSITORY=ghcr.io/kyverno/signatures
    [ "$n" != kyverno ] || refus "identité voisine (tag v1.19.1)" "none of the expected identities|no matching" \
      env COSIGN_REPOSITORY=ghcr.io/kyverno/signatures cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      --certificate-identity "${KY_ID%v1.19.2}v1.19.1" "ghcr.io/kyverno/$n@$d"
    miroir "ghcr.io/kyverno/$n@$d" "amont/kyverno/$n" "$T/auth/zot.json"
    # Bundles de signature : dépôt séparé, étiquette de repli des referrers (sha256-<digest>) ; sujet = l'index copié.
    # L'index de repli annonce artifactType vide (application/vnd.oci.empty.v1+json) : tous ses manifestes sont copiés.
    for s in $(crane manifest "ghcr.io/kyverno/signatures:sha256-${d#sha256:}" | jq -r '.manifests[].digest'); do
      miroir "ghcr.io/kyverno/signatures@$s" "amont/kyverno/$n" "$T/auth/zot.json"
    done
    verifier_ky "$REG_HOTE/amont/kyverno/$n@$d" SSL_CERT_FILE="$T/ca-tous.pem"
  done <<< "$KY_IMAGES"
}

etape_installer() {
  local k=$T/kyverno n d
  [ -s "$DL/install.yaml" ] || curl -fsSL --proto '=https' -o "$DL/install.yaml" \
    "https://github.com/$KY_DEPOT/releases/download/v1.19.2/install.yaml"
  echo "$KY_INSTALL  $DL/install.yaml" | sha256sum -c
  gh api -H 'Accept: application/vnd.github.raw' "repos/$KY_DEPOT/contents/config/install-latest-testing.yaml?ref=$KY_COMMIT" \
    | sed -e 's#^\( *app.kubernetes.io/version:\) latest$#\1 v1.19.2#' -e 's#^\( *image: "reg.kyverno.io/kyverno/[a-z-]*\):latest"$#\1:v1.19.2"#' \
    > "$T/install-commit.yaml"
  diff -q "$T/install-commit.yaml" "$DL/install.yaml" >/dev/null \
    && echo "OK   install.yaml = config/install-latest-testing.yaml du commit $KY_COMMIT, latest → v1.19.2 (versions et images)" \
    || { echo "KO   install.yaml diffère du manifeste du commit du tag" >&2; diff "$T/install-commit.yaml" "$DL/install.yaml" | head -20 >&2; exit 1; }
  rm -rf "$k" && mkdir -p "$k"
  cp "$DL/install.yaml" "$k/install.yaml"
  while read -r n d; do
    sed -i "s#\"reg.kyverno.io/kyverno/$n:v1.19.2\"#\"$REG/amont/kyverno/$n@$d\"#" "$k/install.yaml"
  done <<< "$KY_IMAGES"
  cp "$here/politique/kustomization-kyverno.yaml" "$k/kustomization.yaml"
  cp "$P/ca-poc.crt" "$k/ca.crt"
  kubectl kustomize "$k" > "$k/rendu.yaml"
  echo "## références d'images hors de Zot dans le manifeste rendu"
  grep -hoE 'image: *"?[^" ]+' "$k/rendu.yaml" | grep -v "$REG/amont/" | sort | uniq -c || echo "aucune"
  echo "kyverno : $(grep -c '^kind:' "$k/rendu.yaml") objets, sha256 $(sha256sum < "$k/rendu.yaml" | cut -c1-16)…"
  kubectl apply --server-side --force-conflicts -f "$k/rendu.yaml" >/dev/null
  kubectl wait --for=condition=Available deployment --all -n kyverno --timeout=300s
  kubectl get pods -n kyverno -o wide --no-headers | awk '{print $1, $3, $7}'
  echo "## images réellement tirées (imageID des conteneurs)"
  kubectl get pods -n kyverno -o json | jq -r '.items[].status | (.initContainerStatuses // []) + .containerStatuses | .[].imageID' | sort -u > "$T/ids"
  sed 's/@sha256:\(.\{12\}\).*/@sha256:\1…/' "$T/ids"
  grep -v "^$REG/amont/kyverno/" "$T/ids" && { echo "KO   image tirée hors de Zot" >&2; exit 1; } \
    || echo "OK   $(wc -l < "$T/ids") images, toutes tirées de $REG/amont/kyverno/"
  echo "## webhooks d'admission de Kyverno"
  kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -o json \
    | jq -r '.items[] | select(.metadata.name | startswith("kyverno")) | "\(.kind) \(.metadata.name) : \([(.webhooks // [])[] | .failurePolicy] | unique | join(","))"'
}

ms() { local u; read -r u _ < /proc/uptime; echo $(( 10 * 10#${u/./} )); }   # horloge monotone (run.sh du banc)

cli() { # politique pod : décision du CLI 1.19.2 (PASS, FAIL, ERREUR), code de sortie et motif (analyse de run.sh du banc C)
  local c=0
  SSL_CERT_FILE=$P/ca-poc.crt kyverno apply "$1" --resource "$2" --policy-report --output-format json > "$T/cli.json" 2> "$T/cli.err" || c=$?
  python3 -I -c 'import json,re,sys
t = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1]).read())
i = t.find("{")
d = json.loads(t[i:]) if i >= 0 else {}
s = d.get("summary", {})
res = "ERREUR" if s.get("error") else ("FAIL" if s.get("fail") else ("PASS" if s.get("pass") else "INDÉTERMINÉ"))
msg = "; ".join((r.get("message") or "").replace("\n", " ") for r in d.get("results", []) if r.get("result") != "pass")
print(res + " (code " + sys.argv[2] + ")\t" + msg[:160])' "$T/cli.json" "$c"
}

admission() { # pod : décision de l'admission (PASS : admis en dry-run serveur ; FAIL : refusé) et motif
  if kubectl create --dry-run=server -f "$1" > "$T/adm.out" 2>&1; then printf 'PASS\t\n'
  else printf 'FAIL\t%s\n' "$(tr '\n' ' ' < "$T/adm.out" | sed -e 's/^Error from server: //' -e 's/^error when creating "[^"]*": //' | cut -c1-200)"; fi
}

charger() { # fichier nom : ImageValidatingPolicy chargée à l'admission, attendue prête (webhook de Kyverno à jour)
  local i
  kubectl apply -f "$1" >/dev/null
  for i in $(seq 60); do
    [ "$(kubectl get imagevalidatingpolicy "$2" -o jsonpath='{.status.conditionStatus.ready}' 2>/dev/null)" = true ] && break
    sleep 1
  done
  [ "$i" -lt 60 ] || { echo "KO   politique $2 jamais prête" >&2; kubectl get imagevalidatingpolicy "$2" -o yaml >&2; exit 1; }
  sleep 2   # Kyverno publie ensuite la règle dans sa configuration de webhook
}

comparer() { # cas attendu politique pod : une ligne du tableau (CLI, admission, durées) ; ÉCART si les libellés diffèrent
  local c=$1 e=$2 t0 t1 t2 a b
  t0=$(ms); a=$(cli "$3" "$4"); t1=$(ms); b=$(admission "$4"); t2=$(ms)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$c" "$e" "${a%%$'\t'*}" "${b%%$'\t'*}" "$((t1 - t0))" "$((t2 - t1))" "${a#*$'\t'}" "${b#*$'\t'}" >> "$TSV_PARITE"
  if [ "${a%% *}" = "${b%%$'\t'*}" ]; then echo "OK   $c : CLI ${a%%$'\t'*}, admission ${b%%$'\t'*} (attendu $e)"
  else echo "ÉCART $c : CLI ${a%%$'\t'*} (${a#*$'\t'}), admission ${b%%$'\t'*} (${b#*$'\t'}) (attendu $e)"; fi
}

etape_parite() {
  local c e ref r v
  TSV_PARITE=$R/politique-parite.tsv
  printf 'cas\tattendu\tCLI\tadmission\tCLI (ms)\tadmission (ms)\tmotif CLI\tmotif admission\n' > "$TSV_PARITE"
  kubectl create namespace "$NS_ESSAI" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  attendre_sa "$NS_ESSAI"
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  echo "## banc C : 17 cas poussés dans Zot ($REG_HOTE/bench/), clés de test du banc"
  rm -rf "$T/banc"
  WORKDIR=$T/banc REG=$REG_HOTE DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt "$BANC/setup.sh" | sed 's/@sha256:\(.\{12\}\).*/@sha256:\1…/'
  python3 -I - "$BANC/kyverno/ivpol.tmpl.yaml" "$T/banc/keys/chains.pub" "$T/banc/keys/vsa.pub" "$T/banc/ivpol.yaml" <<'PY'
import sys
tmpl = open(sys.argv[1]).read()
indent = lambda p: "\n".join(" " * 12 + l for l in open(p).read().strip().splitlines())
open(sys.argv[4], "w").write(tmpl.replace("__CHAINS_PUB__", indent(sys.argv[2])).replace("__VSA_PUB__", indent(sys.argv[3])))
PY
  sed -i "s#glob: \"localhost:5000/\*\"#glob: \"$REG_HOTE/bench/*\"#" "$T/banc/ivpol.yaml"
  diff <(sed -n '/^spec:/,$p' "$BANC/kyverno/ivpol.tmpl.yaml") <(sed -n '/^spec:/,$p' "$T/banc/ivpol.yaml") | grep '^[<>]' | grep -v -e '^> \{12\}' -e '__\(CHAINS\|VSA\)_PUB__' \
    | sed 's/^/  écart avec le modèle du banc : /' || true
  charger "$T/banc/ivpol.yaml" bench-release
  # Preuve que l'admission évalue bien en dry-run : un cas refusé du banc doit l'être aussi par l'API.
  ref=$(awk -F'\t' '$1 == "c1-unsigned" {print $3}' "$T/banc/images.tsv")
  sed "s|__CASE__|c1-unsigned|; s|__REF__|$ref|; s|namespace: default|namespace: $NS_ESSAI|" "$BANC/kyverno/pod.tmpl.yaml" > "$T/pod.yaml"
  r=$(admission "$T/pod.yaml")
  [ "${r%%$'\t'*}" = FAIL ] && echo "OK   dry-run serveur évalué par Kyverno : c1-unsigned refusé (${r#*$'\t'})" \
    || { echo "KO   c1-unsigned admis en dry-run : l'admission n'évalue pas la politique" >&2; exit 1; }
  while IFS=$'\t' read -r c e ref; do
    sed "s|__CASE__|$c|; s|__REF__|$ref|; s|namespace: default|namespace: $NS_ESSAI|" "$BANC/kyverno/pod.tmpl.yaml" > "$T/pod-$c.yaml"
    comparer "$c" "$e" "$T/banc/ivpol.yaml" "$T/pod-$c.yaml"
  done < "$T/banc/images.tsv"

  echo "## J5 : contrôle 9, attestor à clé sans journal ; une politique par variante (pas de cache partagé entre variantes)"
  cat > "$T/pod-j5.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata: {name: essai-j5, namespace: $NS_ESSAI}
spec:
  containers:
    - name: app
      image: $REG_HOTE/builds/essai-signature@$APP_DIGEST
EOF
  printf '%s\n' "j5-temoin|PASS|horodatage/bundles|" "j5-jeton-valide|PASS|horodatage/bundles|$P/tsa-chaine.pem" \
    "j5-sans-jeton|FAIL|essais-j5/sans-jeton|$P/tsa-chaine.pem" "j5-aucun-bundle|FAIL|essais-j5/aucun|$P/tsa-chaine.pem" \
    "j5-jeton-altere|FAIL|essais-j5/jeton-altere|$P/tsa-chaine.pem" "j5-autre-signature|FAIL|essais-j5/autre-signature|$P/tsa-chaine.pem" \
    "j5-tsa-etrangere|FAIL|essais-j5/tsa-etrangere|$P/tsa-chaine.pem" "j5-att-historique|PASS||" > "$T/cas-j5.txt"
  while IFS='|' read -r c e r v; do
    ivpol "$r" "$v" "$c" > "$T/$c.yaml"
    charger "$T/$c.yaml" "$c"
    comparer "$c" "$e" "$T/$c.yaml" "$T/pod-j5.yaml"
    kubectl delete imagevalidatingpolicy "$c" --wait=true >/dev/null
  done < "$T/cas-j5.txt"
  echo "## synthèse"
  # Décision d'une porte : admis si et seulement si PASS (CLI : code 0 ; admission : requête acceptée).
  awk -F'\t' 'NR > 1 { n++; split($3, c, " "); if (c[1] == $4) p++; else printf "  écart de libellé : %s (CLI %s, admission %s)\n", $1, $3, $4;
    if ((c[1] == "PASS") == ($4 == "PASS")) d++ } END { printf "parité des libellés : %d cas sur %d ; parité des décisions (admis ou refusé) : %d cas sur %d\n", p, n, d, n }' "$TSV_PARITE"
  awk -F'\t' 'NR > 1 { split($3, c, " ") } NR > 1 && c[1] != $2 { printf "  CLI ≠ attendu : %s (%s au lieu de %s)\n", $1, $3, $2 } NR > 1 && $4 != $2 { printf "  admission ≠ attendu : %s (%s au lieu de %s)\n", $1, $4, $2 }' "$TSV_PARITE"
  awk -F'\t' 'NR > 1 { a += $5; b += $6; n++ } END { printf "durée moyenne par cas : CLI %d ms, admission %d ms\n", a / n, b / n }' "$TSV_PARITE"
}

lancer politique J6 "$@"
