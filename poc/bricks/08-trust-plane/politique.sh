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
#   taches     Trusted Resources : clé des tâches de la plateforme (ECDSA P-256, 0600 sur l'hôte, distincte de celles de
#              Chains et du TSA) ; tâche v1beta1 signée par tkn v0.46.2 (une v1 signée est rejetée : tektoncd/cli#2894),
#              publiée en bundle Tekton dans Zot (tekton/tasks/) ;
#              Tekton : vérification obligatoire (no-match-policy fail), specs en ligne interdites (disable-inline-spec),
#              résolveur bundles seul ; VerificationPolicy dans builds ; essais : tâche signée exécutée ; non signée,
#              modifiée, signée par une autre clé, hors de tekton/, en ligne et par les résolveurs désactivés : refusées
#   admission  règles d'admission de Kyverno (politique/admission.yaml, CEL) : références Tekton signées (test 2), isolation
#              des pods (test 4), confinement de la zone confiance, StepActions interdites ; 30 cas présentés au CLI et à
#              l'admission (dry-run serveur), tableau dans resultats/politique-admission.tsv
#   chains     identifiants Zot de Chains (compte poc-build) sortis de builds : secret zot-chains dans tekton-chains,
#              DOCKER_CONFIG (politique/chains-zot.yaml) ; compte build sans imagePullSecrets ni jeton ; zot-build supprimé
#   declencheurs  tâche et pipeline de J4 en v1beta1, signées et publiées en bundles (tekton/tasks, tekton/pipelines) ;
#              PipelineRun du bundle signé exécuté et signé par Chains (push de poc-build dans l'audit de Zot), pipeline
#              modifiée après signature refusée ; EventListener, secret du webhook et TriggerTemplate déplacés dans
#              l'espace de confiance declencheurs, droits réduits (politique/declencheurs.yaml) ; webhook Forgejo rebranché ;
#              tâche en service : signature versionnée (politique/taches/publier-essai.signee.yaml, SIGNER=1 pour la
#              refaire), conforme au gabarit, digest exigé dans la liste revue (politique/porte/taches.yml) ;
#              objets de J4 retirés de builds. Puis test 5 rejoué : EL_NS=declencheurs JOURNAL=politique JALON=J6
#              mise run confiance:tekton -- essais_webhook
#   restreint  Pod Security restricted pour les pods des TaskRuns : drapeau set-security-context de Pipelines (conteneurs
#              d'initialisation de Tekton), stepTemplate restreint des tâches signées (étapes), contexte de pod du gabarit ;
#              builds en warn, audit et enforce restricted (décision du propriétaire du 30/10/2026) : tâche en service et
#              tâche d'essai exécutées, tâche signée sans stepTemplate et drapeau désactivé refusés par Pod Security ;
#              enforce levé le temps d'un cas : violation tracée dans l'audit de l'API sous warn et audit ; exécutions vers
#              l'image d'essai sérialisées (signature de Chains attendue, deux enveloppes exigées : constat-att-ecrasee.log)
#   horodatagehorodatage automatique par réconciliation périodique : CronJob horodatage (politique/horodatage-cronjob.yaml,
#              tsa/horodater.sh sans $IMAGE) qui parcourt builds/ dans Zot et horodate chaque enveloppe de Chains vérifiée
#              (clé de Chains, sujet, prédicat) ; trois témoins posés par poc-ecriture (autre clé, autre sujet : refusés ;
#              tag .att illisible : anomalie) à chaque passage, sans arrêter le parcours ; rattrapage, nouvelle exécution
#              signée puis supprimée de l'API (latence), passage sans nouveauté ; une requête de jeton par enveloppe
#              horodatée dans le journal du TSA ; chaque enveloppe a son bundle (appariés par signature), bundles
#              orphelins listés (enveloppe perdue du tag .att après horodatage), aucun nouveau ; chemin de la porte
#   rattrapage rattrapage des webhooks perdus (Forgejo v15.0.11 ne retente jamais une livraison échouée) : réconciliateur
#              en Go (politique/rattrapage, bibliothèque standard seule), compilé deux fois (même empreinte), image d'une
#              couche sur base vide (même digest) ; CronJob rattrapage de declencheurs (politique/rattrapage.yaml) qui crée
#              le PipelineRun de la tête de main s'il manque, depuis la TriggerTemplate en service ; sorties du pod
#              (NetworkPolicy, fenêtre de démarrage) ; webhook perdu (EventListener à 0 réplique), aucune relivraison en
#              150 s, rattrapage, horodatage, course avec l'EventListener ; même spec et même runSpec signé qu'un
#              PipelineRun de l'EventListener ; internalParameters signés (slsa-tekton) : seuls les labels de chaque créateur
#              diffèrent ; verdict de la porte sur la provenance de chaque chemin (après l'étape porte) ; main remise à
#              6391fd43 (force-push)
#   porte      porte de release : Conforma (ec v0.10.42, empreinte du verrou mise) et la bibliothèque conforma/policy
#              v1.0.28 (commit signé, arbre vérifié) dans une image d'une couche sur base vide (même digest) ; Job de
#              l'espace porte (zone confiance, DNS et Zot seulement, aucun droit sur l'API) ; collection slsa3, trusted_task
#              (liste revue politique/porte/taches.yml) et règles du PoC (politique/porte) ; Chains en buildType slsa-tekton
#              (décision du propriétaire du 30/10/2026) ; tâche en service (exécution de l'essai, sans adoption), et images
#              d'essai : buildType slsa (Chains basculé le temps d'une image), tâche hors liste, version non listée, non
#              signée ; plus le témoin signé par une autre clé ; aucune liste de tâches requises (choisie par un label)
#   droits     rôle des opérateurs (politique/droits.yaml) ; matrice kubectl auth can-i (compte build, EventListener,
#              opérateur, job d'horodatage, rattrapage, porte, contrôleurs de Pipelines et de Chains ; RBAC seul,
#              l'admission n'y figure pas) dans resultats/politique-droits.tsv ; comptes de service du cluster qui peuvent
#              modifier un PipelineRun de builds ; écritures de l'EventListener (test 5) et du rattrapage dans l'audit de l'API
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
BUSYBOX_AMONT=docker.io/rancher/mirrored-library-busybox:1.37.0   # image d'étape de J4 (copie dans Zot : tekton-images.tsv)
DL=$O/telechargements/kyverno
RATTRAPAGE=plateforme/rattrapage
RATTRAPAGE_BIN=f6d7dcc6d2040203e723149d0eb52b43125a8d26c8354191cb214779f57e952f   # politique/rattrapage, Go 1.26.10 de mise.toml
RATTRAPAGE_DIGEST=sha256:c3992728ff77d2d7b412626ab2c34de8d84154bb384aae572042b9aabe0e3c03   # base vide, une couche, linux/amd64, utilisateur 65532
# Porte de release : ec v0.10.42 (mise.toml) et bibliothèque conforma/policy v1.0.28 dans une image d'une couche
EC_BIN=895c6f7e63cfefe6257a2e54c052c3d90803e8127adf5a7eb13f245262859abf   # ec_linux_amd64 v0.10.42 (mise.lock)
CPOL_DEPOT=conforma/policy
CPOL_TAG=6b5d1d2c94fa81bd1a00ce5f5a5f3b41e0e6976a      # tag annoté v1.0.28, non signé (GitHub Action, 26/08/2026)
CPOL_COMMIT=ebd3fbd270297c15f590f4023360465ffb41d4fe   # commit du tag, signé par GitHub (fusion de la PR #1817)
CPOL_ARBRE=0fd26021bb08582553f392565ca0faf316c51229    # arbre du commit (contenu signé)
PORTE=plateforme/porte
PORTE_DIGEST=sha256:e77994c20705b4bffd434067033ef2c2f748cf2311f9997c7346b33f0b943926   # base vide, une couche (ec, policy/release et policy/lib sans tests)
# règles de source de la porte, en échec attendu jusqu'à J7 (aucune source git dans la provenance des essais)
SRC_J7=slsa_source_correlated.attested_source_code_reference,slsa_source_correlated.source_code_reference_provided,slsa_source_version_controlled.materials_format_okay
FORGEJO_HOTE=https://192.168.161.13:3000
SAMPLE_APP=workspace/sample-app
TETE_J2=6391fd437f26696847041be3226bbbf633f55a2f   # commit de stockage.sh depot ; main y est remise après les essais
EL_NS=declencheurs   # EventListener de J6 (commun.sh : el_url, brancher_forgejo)
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

admission() { # pod : décision de l'admission (PASS : admis en dry-run serveur ; FAIL : refusé par un webhook) et motif ;
  # ERREUR : autre réponse de l'API (espace absent, par exemple), qui n'est pas une décision d'admission
  local m
  if kubectl create --dry-run=server -f "$1" > "$T/adm.out" 2>&1; then printf 'PASS\t\n'; return; fi
  m=$(tr '\n' ' ' < "$T/adm.out" | sed -e 's/^Error from server\( ([A-Za-z]*)\)\{0,1\}: //' -e 's/^error when creating "[^"]*": //' | cut -c1-200)
  if grep -q 'denied the request' "$T/adm.out"; then printf 'FAIL\t%s\n' "$m"; else printf 'ERREUR\t%s\n' "$m"; fi
}

charger() { # fichier nom [type] : politique chargée à l'admission, attendue prête (webhook de Kyverno à jour)
  local i k=${3:-imagevalidatingpolicy}
  kubectl apply -f "$1" >/dev/null
  for i in $(seq 60); do
    [ "$(kubectl get "$k" "$2" -o jsonpath='{.status.conditionStatus.ready}' 2>/dev/null)" = true ] && break
    sleep 1
  done
  [ "$i" -lt 60 ] || { echo "KO   politique $2 jamais prête" >&2; kubectl get "$k" "$2" -o yaml >&2; exit 1; }
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

creer() { # fichier : création dans builds ; un refus à l'admission (Kyverno, webhook de Tekton) est une issue du même format
  kubectl create -f "$1" > "$T/creer.out" 2>&1 && return 0
  printf 'False|RefusAdmission|-|%s|\n' "$(tr '\n' ' ' < "$T/creer.out" | sed -e 's/^Error from server\( ([A-Za-z]*)\)\{0,1\}: //' -e 's/^error when creating "[^"]*": //' | cut -c1-230)"
  return 1
}

issue() { # type nom : attend la fin d'un TaskRun ou d'un PipelineRun de builds ; issue, vérification, résultats
  local st
  for _ in $(seq 120); do
    st=$(kubectl get "$1" -n builds "$2" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}')
    [ -n "$st" ] && [ "$st" != Unknown ] && break
    sleep 1
  done
  kubectl get "$1" -n builds "$2" -o json | jq -r '.status as $s | ($s.conditions // []) as $c
    | ($c[] | select(.type == "Succeeded")) as $r
    | "\($r.status)|\($r.reason)|\(($c[] | select(.type == "TrustedResourcesVerified") | .status) // "-")|\($r.message // "" | gsub("\n"; " ") | .[0:230])|\($s.results // [] | map(.name + "=" + .value) | join(","))"'
}

taskrun() { # nom résolveur bundle : TaskRun d'essai créé dans builds, puis attendu ; affiche l'issue et la vérification
  local n=$1
  sed -e "s#@NOM@#$n#" -e "s#@RESOLVEUR@#$2#" -e "s#@BUNDLE@#$3#" "$here/politique/taches/taskrun.yaml" > "$T/tr-$n.yaml"
  kubectl delete taskrun -n builds "$n" --ignore-not-found --wait=true >/dev/null
  creer "$T/tr-$n.yaml" || return 0
  issue taskrun "$n"
}

pipelinerun() { # nom bundle commit : PipelineRun du gabarit de declencheurs.yaml (rendu), créé dans builds ; issue
  # (suppressions au premier plan : un PipelineRun recréé sous le même nom reprendrait le TaskRun encore présent de
  # l'ancien, cherché par nom par Pipelines v1.15.5, voir tekton.sh essais_webhook)
  local n=$1
  awk '/^kind: TriggerTemplate$/ {t = 1} t && /^  - apiVersion: tekton.dev\/v1$/ {p = 1} p && /^---$/ {exit} p' "$T/declencheurs.yaml" \
    | sed -e 's/^    //' -e 's/^  - apiVersion/apiVersion/' -e "s#name: sample-app-\$(tt.params.commit)#name: $n#" \
      -e "s#value: \$(tt.params.commit)#value: '$3'#" -e 's#value: \$(tt.params.depot)#value: https://sc-stockage.poc.test:3000/workspace/sample-app.git#' \
      -e "s#value: $REG/tekton/pipelines/sample-app-essai@.*#value: $2#" > "$T/pr-$n.yaml"
  kubectl delete pipelinerun -n builds --cascade=foreground "$n" --ignore-not-found --wait=true >/dev/null
  creer "$T/pr-$n.yaml" || return 0
  issue pipelinerun "$n"
}

verdict() { # libellé attendu (True|False) issue : ligne OK ou KO
  local l=$1 e=$2 st r v m res
  IFS='|' read -r st r v m res <<< "$3"
  if [ "$st" = "$e" ]; then echo "OK   $l : $([ "$st" = True ] && echo "exécutée ($res)" || echo "refusée, $r : $m") ; TrustedResourcesVerified=$v"
  else echo "KO   $l : Succeeded=$st, $r : $m ; TrustedResourcesVerified=$v" >&2; exit 1; fi
}

bundle() { # fichier dépôt [tag] : bundle Tekton poussé dans Zot par tkn (date de création fixe : digest reproductible) ; digest
  DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt tkn bundle push "$REG_HOTE/$2:${3:-essai}" -f "$1" > "$T/tkn.out" 2>&1 \
    || { cat "$T/tkn.out" >&2; exit 1; }
  SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$2:${3:-essai}"
}

etape_taches() {
  local b d tr
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  echo "## clé des tâches de la plateforme (ADR 0003 : clés séparées par usage)"
  if [ -s "$S/taches.key" ]; then echo "clé existante"; else
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/taches.key")
  fi
  openssl pkey -in "$S/taches.key" -pubout -out "$P/taches.pub"
  echo "clé publique : $P/taches.pub, sha256 $(openssl pkey -pubin -in "$P/taches.pub" -outform DER | sha256sum | cut -c1-16)…"
  for f in "$R/chains-cle-publique.pem" "$P/tsa-chaine.pem"; do
    ! cmp -s <(openssl pkey -pubin -in "$P/taches.pub" -outform DER) <(openssl pkey -pubin -in "$f" -outform DER 2>/dev/null || openssl x509 -in "$f" -pubkey -noout | openssl pkey -pubin -outform DER) \
      || { echo "KO   clé des tâches = $f" >&2; exit 1; }
  done
  echo "OK   distincte de la clé de Chains et de celle du TSA"
  (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$T/autre.key")

  echo "## tâche d'essai signée par tkn $(tkn version --component client)"
  sed "s#@BUSYBOX@#$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")#" "$here/politique/taches/essai-confiance.yaml" > "$T/tache.yaml"
  sed 's#^apiVersion: tekton.dev/v1beta1$#apiVersion: tekton.dev/v1#' "$T/tache.yaml" > "$T/tache-v1.yaml"
  tkn task sign "$T/tache-v1.yaml" -K "$S/taches.key" -f "$T/signee-v1.yaml" >/dev/null
  tkn task sign "$T/tache.yaml" -K "$S/taches.key" -f "$T/signee.yaml" >/dev/null
  tkn task sign "$T/tache.yaml" -K "$T/autre.key" -f "$T/autre-cle.yaml" >/dev/null
  sed 's/tâche signée par la plateforme/tâche modifiée après signature/' "$T/signee.yaml" > "$T/modifiee.yaml"
  echo "annotation tekton.dev/signature : $(grep -c 'tekton.dev/signature' "$T/signee.yaml") (signée), $(grep -c 'tekton.dev/signature' "$T/tache.yaml") (non signée) ;" \
    "modifiée : $(diff "$T/signee.yaml" "$T/modifiee.yaml" | grep -c '^>') ligne changée, même annotation"
  : > "$T/bundles.txt"
  for b in signee:tekton/tasks/essai-confiance tache:tekton/tasks/essai-non-signee modifiee:tekton/tasks/essai-modifiee \
      autre-cle:tekton/tasks/essai-autre-cle signee:essais-j6/tasks/essai-confiance signee-v1:tekton/tasks/essai-v1; do
    d=$(bundle "$T/${b%%:*}.yaml" "${b#*:}")
    echo "${b#*:} $REG/${b#*:}@$d" >> "$T/bundles.txt"
    echo "bundle ${b#*:} ← ${b%%:*}.yaml : $d"
  done

  echo "## Tekton : vérification obligatoire, specs en ligne interdites, résolveur bundles seul"
  kubectl patch configmap feature-flags -n tekton-pipelines --type merge \
    -p '{"data":{"trusted-resources-verification-no-match-policy":"fail","disable-inline-spec":"pipeline,pipelinerun,taskrun"}}' >/dev/null
  kubectl patch configmap resolvers-feature-flags -n tekton-pipelines-resolvers --type merge -p '{"data":{"enable-bundles-resolver":"true",
    "enable-cluster-resolver":"false","enable-git-resolver":"false","enable-http-resolver":"false","enable-hub-resolver":"false"}}' >/dev/null
  kubectl get configmap feature-flags -n tekton-pipelines -o json | jq -r '.data | "feature-flags : trusted-resources-verification-no-match-policy=\(.["trusted-resources-verification-no-match-policy"]), disable-inline-spec=\(.["disable-inline-spec"])"'
  kubectl get configmap resolvers-feature-flags -n tekton-pipelines-resolvers -o json | jq -r '.data | to_entries | map("\(.key)=\(.value)") | join(", ") | "résolveurs : " + .'
  awk -v f="$P/taches.pub" '/^@CLE@$/ { while ((getline l < f) > 0) print "        " l; next } { print }' \
    "$here/politique/verification-policy.yaml" | kubectl apply -f - >/dev/null
  kubectl get verificationpolicy -n builds taches-plateforme -o json | jq -r '"VerificationPolicy \(.metadata.name) : \(.spec.mode), motif \(.spec.resources[0].pattern), autorité \(.spec.authorities[0].name)"'
  sleep 5   # les contrôleurs relisent les ConfigMaps par informer

  echo "## essais (TaskRuns dans builds, pods sur sc-build)"
  tr=$(taskrun j6-signee bundles "$(awk '$1 == "tekton/tasks/essai-confiance" {print $2}' "$T/bundles.txt")")
  verdict "tâche signée, tekton/tasks" True "$tr"
  verdict "tâche non signée" False "$(taskrun j6-non-signee bundles "$(awk '$1 == "tekton/tasks/essai-non-signee" {print $2}' "$T/bundles.txt")")"
  verdict "tâche modifiée après signature" False "$(taskrun j6-modifiee bundles "$(awk '$1 == "tekton/tasks/essai-modifiee" {print $2}' "$T/bundles.txt")")"
  verdict "tâche signée par une autre clé" False "$(taskrun j6-autre-cle bundles "$(awk '$1 == "tekton/tasks/essai-autre-cle" {print $2}' "$T/bundles.txt")")"
  verdict "tâche v1 signée par tkn (constat tektoncd/cli#2894)" False "$(taskrun j6-v1 bundles "$(awk '$1 == "tekton/tasks/essai-v1" {print $2}' "$T/bundles.txt")")"
  verdict "tâche signée, hors de tekton/ (essais-j6/)" False "$(taskrun j6-hors-politique bundles "$(awk '$1 == "essais-j6/tasks/essai-confiance" {print $2}' "$T/bundles.txt")")"
  for b in git http hub cluster; do
    verdict "résolveur $b désactivé" False "$(taskrun "j6-resolveur-$b" "$b" "$(awk '$1 == "tekton/tasks/essai-confiance" {print $2}' "$T/bundles.txt")")"
  done
  { sed -n '1,/^  taskRef:$/p' "$T/tr-j6-signee.yaml" | sed -e '$d' -e 's/name: j6-signee/name: j6-en-ligne/'; echo '  taskSpec:'
    sed -n '/^  results:$/,$p' "$T/tache.yaml" | sed 's/^/  /'; } > "$T/tr-en-ligne.yaml"
  refus "taskSpec en ligne (TaskRun), webhook de Tekton" "must not set the field\(s\): spec.taskSpec" kubectl create --dry-run=server -f "$T/tr-en-ligne.yaml"
}

etape_admission() {
  local c e a desc d n r t0
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  TSV_PARITE=$R/politique-admission.tsv
  printf 'cas\tattendu\tCLI\tadmission\tCLI (ms)\tadmission (ms)\tmotif CLI\tmotif admission\n' > "$TSV_PARITE"
  kubectl create namespace "$NS_ESSAI" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  sed -n '1,/^---$/p' "$here/politique/declencheurs.yaml" | kubectl apply --server-side -f - >/dev/null   # espace des cas zone-declencheurs
  sed -n '1,/^---$/p' "$here/politique/porte.yaml" | kubectl apply --server-side -f - >/dev/null   # espace du cas zone-porte
  d=$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/tekton/tasks/essai-confiance:essai")
  rm -rf "$T/adm"
  python3 -I "$here/politique/cas-admission.py" "$T/adm" "$REG/tekton/tasks/essai-confiance@$d" \
    "$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")"
  echo "## politiques chargées ($(grep -c '^kind: ValidatingPolicy' "$here/politique/admission.yaml") ValidatingPolicy, $(grep -c '^  - expression:' "$here/politique/admission.yaml") validations)"
  for n in $(awk '/^kind: ValidatingPolicy/ {k = 1} k && /^  name:/ {print $2; k = 0}' "$here/politique/admission.yaml"); do
    charger "$here/politique/admission.yaml" "$n" validatingpolicy
    echo "prête : $n"
  done
  echo "ValidatingAdmissionPolicy natives générées par Kyverno : $(kubectl get validatingadmissionpolicies -o name 2>/dev/null | grep -c . || true)"
  echo "## $(wc -l < "$T/adm/cas.tsv") cas, CLI puis admission (dry-run serveur)"
  while IFS=$'\t' read -r c e a desc; do
    if [ "$a" = oui ]; then comparer "$c" "$e" "$here/politique/admission.yaml" "$T/adm/$c.json"
    else
      r=$(cli "$here/politique/admission.yaml" "$T/adm/$c.json")
      printf '%s\t%s\t%s\t-\t-\t-\t%s\t%s\n' "$c" "$e" "${r%%$'\t'*}" "${r#*$'\t'}" "$desc" >> "$TSV_PARITE"
      [ "${r%% *}" = "$e" ] && echo "OK   $c : CLI ${r%%$'\t'*} (attendu $e ; admission non évaluée : $desc)" \
        || { echo "KO   $c : CLI ${r%%$'\t'*} (attendu $e)" >&2; exit 1; }
    fi
  done < "$T/adm/cas.tsv"
  echo "## synthèse"
  awk -F'\t' 'NR > 1 && $4 != "-" { n++; split($3, c, " "); if (c[1] == $4) p++; else printf "  écart : %s (CLI %s, admission %s)\n", $1, $3, $4 }
    END { printf "parité CLI / admission : %d cas sur %d\n", p, n }' "$TSV_PARITE"
  awk -F'\t' 'NR > 1 { split($3, c, " ") } NR > 1 && c[1] != $2 { printf "  CLI ≠ attendu : %s (%s au lieu de %s)\n", $1, $3, $2; k++ }
    NR > 1 && $4 != "-" && $4 != $2 { printf "  admission ≠ attendu : %s (%s au lieu de %s)\n", $1, $4, $2; k++ }
    END { printf "conformes au résultat attendu : %s\n", k ? "non (" k " écarts)" : "tous"; exit k > 0 }' "$TSV_PARITE"
  awk -F'\t' 'NR > 1 && $4 == "FAIL" { split($8, m, " denied the request: "); w[$1] = m[1] } END { for (c in w) n[w[c]]++; for (x in n) printf "  refus par %s : %d cas\n", x, n[x] }' "$TSV_PARITE" | sort
  echo "## trace : événements PolicyViolation de Kyverno (émis aussi pour un refus en dry-run)"
  kubectl get events -A --field-selector reason=PolicyViolation -o json | jq -r --arg t "$t0" '.items[]
    | select(.involvedObject.kind == "ValidatingPolicy" and (.lastTimestamp // .eventTime) >= $t)
    | "\(.involvedObject.name)"' | sort | uniq -c | sed 's/^ */  /; s/ \([a-z]\)/ événements, politique \1/'
}

etape_chains() {
  local d
  mkdir -p "$T/auth" && chmod 700 "$T/auth"
  echo "## identifiants Zot de Chains (compte poc-build) : secret zot-chains dans tekton-chains, DOCKER_CONFIG"
  auth_zot "$T/auth/chains.json" "" poc-build "$REG"
  kubectl create secret generic zot-chains -n tekton-chains --from-file=config.json="$T/auth/chains.json" --dry-run=client -o yaml \
    | kubectl apply --server-side -f - >/dev/null
  kubectl patch deployment -n tekton-chains tekton-chains-controller --type strategic --patch-file "$here/politique/chains-zot.yaml" >/dev/null
  kubectl rollout status -n tekton-chains deploy/tekton-chains-controller --timeout=180s
  kubectl get deploy -n tekton-chains tekton-chains-controller -o json | jq -r '.spec.template.spec as $p | ($p.containers[0].env[] | select(.name == "DOCKER_CONFIG") | "DOCKER_CONFIG=\(.value)"),
    ($p.volumes[] | select(.secret.secretName == "zot-chains") | "volume \(.name) : secret \(.secret.secretName)")'
  echo "## compte build : ni imagePullSecrets ni jeton ; zot-build retiré de builds"
  kubectl patch serviceaccount build -n builds --type merge -p '{"imagePullSecrets":null,"automountServiceAccountToken":false}' >/dev/null
  kubectl delete secret -n builds zot-build --ignore-not-found --wait=true >/dev/null
  kubectl get serviceaccount build -n builds -o json | jq -c '{compte: .metadata.name, imagePullSecrets: (.imagePullSecrets // []), automountServiceAccountToken}'
  d=$(kubectl get serviceaccount build -n builds -o json | jq -r '(.imagePullSecrets // [] | length) == 0 and .automountServiceAccountToken == false')
  [ "$d" = true ] && echo "OK   compte build sans identifiant de registre ni jeton monté" || { echo "KO   compte build" >&2; exit 1; }
}

signe() { # type nom : attend l'annotation de Chains sur un TaskRun ou un PipelineRun de builds ; sa valeur
  local v=""
  for _ in $(seq 60); do
    v=$(kubectl get "$1" -n builds "$2" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')
    [ "$v" = true ] && break
    sleep 2
  done
  echo "${v:-absente}"
}

listee() { # bundle (par digest) : présent dans la liste revue des tâches approuvées (politique/porte/taches.yml)
  awk -v d="oci://${1%@*}:" -v r="${1#*@}" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && $3 == r {t = 1} END {exit !t}' "$here/politique/porte/taches.yml"
}

etape_declencheurs() {
  local busybox tache pipe autre t0 n o
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente (étape taches)" >&2; exit 1; }
  kubectl get validatingpolicy zone-build >/dev/null 2>&1 || { echo "KO   règles d'admission absentes (étape admission)" >&2; exit 1; }
  busybox=$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")

  echo "## tâche et pipeline de J4 en v1beta1, signées par la clé des tâches et publiées en bundles"
  sed -e "s#@IMAGE@#$REG/builds/essai-webhook#" -e "s#@DIGEST@#$APP_DIGEST#" -e "s#@BUSYBOX@#$busybox#" \
    "$here/politique/taches/publier-essai.yaml" > "$T/publier-essai.yaml"
  tkn task sign "$T/publier-essai.yaml" -K "$S/taches.key" -f "$T/publier-essai-signee.yaml" >/dev/null
  # Tâche en service : signature versionnée (une nouvelle signature donnerait un autre digest), digest dans la liste revue.
  # SIGNER=1 : nouvelle signature écrite dans le dépôt, à faire revoir avec politique/porte/taches.yml.
  if [ -n "${SIGNER:-}" ]; then
    cp "$T/publier-essai-signee.yaml" "$here/politique/taches/publier-essai.signee.yaml"
    echo "SIGNER : nouvelle signature dans politique/taches/publier-essai.signee.yaml (liste revue à mettre à jour)"
  fi
  cmp -s <(grep -v 'tekton.dev/signature:' "$T/publier-essai-signee.yaml") <(grep -v 'tekton.dev/signature:' "$here/politique/taches/publier-essai.signee.yaml") \
    && echo "OK   tâche signée versionnée (politique/taches/publier-essai.signee.yaml) conforme au gabarit rendu, signature exceptée" \
    || { echo "KO   gabarit modifié depuis la signature versionnée : SIGNER=1, puis revue de politique/porte/taches.yml" >&2; exit 1; }
  tache=$REG/tekton/tasks/publier-essai@$(bundle "$here/politique/taches/publier-essai.signee.yaml" tekton/tasks/publier-essai)
  echo "tâche publier-essai : $tache"
  listee "$tache" && echo "OK   tâche en service dans la liste revue (politique/porte/taches.yml)" \
    || { echo "KO   tâche en service absente de la liste revue politique/porte/taches.yml" >&2; exit 1; }
  sed "s#@TACHE@#$tache#" "$here/politique/taches/sample-app-essai.yaml" > "$T/sample-app-essai.yaml"
  tkn pipeline sign "$T/sample-app-essai.yaml" -K "$S/taches.key" -f "$T/sample-app-essai-signee.yaml" >/dev/null
  pipe=$REG/tekton/pipelines/sample-app-essai@$(bundle "$T/sample-app-essai-signee.yaml" tekton/pipelines/sample-app-essai)
  echo "pipeline sample-app-essai : $pipe"
  # Pipeline modifiée après signature : sa tâche est remplacée par une autre tâche signée (essai-confiance).
  autre=$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/tekton/tasks/essai-confiance:essai")
  sed "s#value: $tache#value: $REG/tekton/tasks/essai-confiance@$autre#" "$T/sample-app-essai-signee.yaml" > "$T/pipeline-modifiee.yaml"
  echo "pipeline modifiée : $(diff "$T/sample-app-essai-signee.yaml" "$T/pipeline-modifiee.yaml" | grep -c '^>') ligne changée (référence de tâche), même signature"
  autre=$REG/tekton/pipelines/essai-modifiee@$(bundle "$T/pipeline-modifiee.yaml" tekton/pipelines/essai-modifiee)
  sed "s#@PIPELINE@#$pipe#" "$here/politique/declencheurs.yaml" > "$T/declencheurs.yaml"

  echo "## PipelineRuns du bundle (dans builds, gabarit de la TriggerTemplate) ; signature par Chains avec ses identifiants"
  verdict "pipeline signée (tâche tirée de son bundle signé)" True "$(pipelinerun j6-pipeline-signee "$pipe" 3333333333333333333333333333333333333333)"
  o=$(kubectl get taskrun -n builds -l tekton.dev/pipelineRun=j6-pipeline-signee -o jsonpath='{.items[0].metadata.name}')
  kubectl get taskrun -n builds "$o" -o json | jq -r '"TaskRun enfant \(.metadata.name) : taskRef \(.spec.taskRef.resolver) \(.spec.taskRef.params[] | select(.name == "bundle") | .value | .[0:72])… ; TrustedResourcesVerified=\(.status.conditions[] | select(.type == "TrustedResourcesVerified") | .status)"'
  echo "Chains : TaskRun $o signé=$(signe taskrun "$o"), PipelineRun j6-pipeline-signee signé=$(signe pipelinerun j6-pipeline-signee)"
  echo "## audit de Zot : écritures de manifestes depuis $t0 (Chains ; compte attendu poc-build)"
  sur sc-stockage "sudo cat /var/log/zot/audit.log" | jq -c --arg t "$t0" 'select(.time >= $t and (.object | test("/manifests/")) and .action != "GET" and .action != "HEAD")
    | {t: .time[11:19], compte: .subject, action, objet: (.object | sub("^/v2/"; "") | sub("sha256-(?<d>.{12}).*[.](?<s>sig|att)$"; "sha256-\(.d)….\(.s)")), code: .status}' > "$T/zot-audit.json"
  grep -F 'builds/essai-webhook' "$T/zot-audit.json" || true
  n=$(jq -s '[.[] | select((.objet | test("^builds/essai-webhook/manifests/sha256-.*[.]att$")) and .compte == "poc-build" and .code == 201)] | length' "$T/zot-audit.json")
  [ "$n" -ge 1 ] && echo "OK   Chains pousse l'attestation avec poc-build (DOCKER_CONFIG) : $n écriture(s) .att" \
    || { echo "KO   aucune écriture .att de poc-build depuis $t0" >&2; exit 1; }
  verdict "pipeline modifiée après signature" False "$(pipelinerun j6-pipeline-modifiee "$autre" 4444444444444444444444444444444444444444)"

  echo "## EventListener, secret du webhook et TriggerTemplate : de builds (J4) à declencheurs"
  kubectl delete eventlistener -n builds forgejo --ignore-not-found --wait=true >/dev/null
  kubectl delete triggertemplate -n builds sample-app --ignore-not-found >/dev/null
  kubectl delete pipeline.tekton.dev -n builds sample-app-essai --ignore-not-found >/dev/null
  kubectl delete task.tekton.dev -n builds publier-essai --ignore-not-found >/dev/null
  kubectl delete rolebinding -n builds el-forgejo --ignore-not-found >/dev/null
  kubectl delete serviceaccount -n builds el-forgejo --ignore-not-found >/dev/null
  kubectl delete clusterrolebinding el-forgejo-builds --ignore-not-found >/dev/null
  kubectl delete secret -n builds forgejo-webhook --ignore-not-found >/dev/null
  kubectl apply --server-side -f "$T/declencheurs.yaml" >/dev/null
  kubectl create secret generic forgejo-webhook -n declencheurs --from-file=secret="$S/forgejo-webhook.secret" --dry-run=client -o yaml \
    | kubectl apply --server-side -f - >/dev/null
  brancher_forgejo

  echo "## contrôles"
  n=$(kubectl get secret -n builds -o name | wc -l)
  [ "$n" = 0 ] && echo "OK   aucun secret dans builds" || { echo "KO   $n secret(s) dans builds : $(kubectl get secret -n builds -o name | paste -sd' ')" >&2; exit 1; }
  n=$(kubectl get eventlisteners,triggertemplates,triggerbindings,tasks.tekton.dev,pipelines.tekton.dev -n builds -o name | wc -l)
  [ "$n" = 0 ] && echo "OK   ni EventListener, ni gabarit, ni tâche ou pipeline locale dans builds" || { echo "KO   $n objet(s) de J4 restant(s) dans builds" >&2; exit 1; }
  kubectl get clusterrolebindings,rolebindings -A -o json | jq -r '.items[] | select(.roleRef.name | startswith("tekton-triggers-eventlistener")) | "\(.kind) \(.metadata.name)"' > "$T/liaisons-el"
  [ ! -s "$T/liaisons-el" ] && echo "OK   ClusterRoles tekton-triggers-eventlistener-* (secrets du cluster, impersonation) liées à rien" \
    || { echo "KO   liaisons restantes : $(paste -sd' ' "$T/liaisons-el")" >&2; exit 1; }
  kubectl get pods -n declencheurs -o json | jq -r '.items[] | "pod \(.metadata.name) : nœud \(.spec.nodeName), compte \(.spec.serviceAccountName)"'
}

pr_gabarit() { # nom pipeline : PipelineRun du gabarit en service dans declencheurs (pipeline remplacée, commit de main remise
  # à zéro), créé dans builds puis attendu ; issue
  kubectl get triggertemplate -n declencheurs sample-app -o json | jq --arg n "$1" --arg b "$2" --arg c "$TETE_J2" \
    --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" '.spec.resourcetemplates[0] | .metadata.name = $n
      | .spec.pipelineRef.params |= map(if .name == "bundle" then .value = $b else . end)
      | .spec.params |= map(if .name == "commit" then .value = $c elif .name == "depot" then .value = $u else . end)' > "$T/pr-$1.json"
  kubectl delete pipelinerun -n builds --cascade=foreground "$1" --ignore-not-found --wait=true >/dev/null
  creer "$T/pr-$1.json" || return 0
  issue pipelinerun "$1"
}

drapeau() { # valeur : set-security-context de Pipelines, relu par le contrôleur (informer)
  kubectl patch configmap feature-flags -n tekton-pipelines --type merge -p "{\"data\":{\"set-security-context\":\"$1\"}}" >/dev/null
  sleep 5
}

conteneurs() { # pod de builds : contexte de sécurité du pod, puis de chaque conteneur (initialisation compris)
  kubectl get pod -n builds "$1" -o json | jq -r '.spec as $s | "  pod : \($s.securityContext | tostring)",
    (($s.initContainers // []) + $s.containers | .[] | "  \(.name) : allowPrivilegeEscalation=\(.securityContext.allowPrivilegeEscalation
      | if . == null then "absent" else tostring end), capabilities.drop=\(.securityContext.capabilities.drop // [] | join(","))")'
}

violations() { # instant pod : annotation audit-violations de Pod Security sur la création du pod (audit de l'API), ou « aucune »
  audit_api "$2" | jq -r --arg t "$1" --arg p "$2" 'select(.stageTimestamp >= $t and .verb == "create" and .objectRef.resource == "pods"
    and .objectRef.subresource == null and .objectRef.name == $p)
    | "\(.annotations["pod-security.kubernetes.io/enforce-policy"]) ; \(.annotations["pod-security.kubernetes.io/audit-violations"] // "aucune")"' | tail -1
}

enfant() { # PipelineRun : issue de son TaskRun publier (raison et message)
  kubectl get taskrun -n builds "$1-publier" -o json | jq -r '.status.conditions[] | select(.type == "Succeeded")
    | "\(.reason) : \(.message // "" | gsub("\n"; " ") | .[0:400])"'
}

etape_restreint() {
  local t0 busybox pipe sans conf st m
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente (étape taches)" >&2; exit 1; }
  kubectl get triggertemplate -n declencheurs sample-app >/dev/null 2>&1 || { echo "KO   gabarit absent (étape declencheurs)" >&2; exit 1; }
  busybox=$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")
  pipe=$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value')
  conf=$REG/tekton/tasks/essai-confiance@$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/tekton/tasks/essai-confiance:essai")

  echo "## état de départ"
  kubectl get namespace builds -o json | jq -r '"labels de builds : \(.metadata.labels | to_entries | map(select(.key | startswith("pod-security"))) | map("\(.key)=\(.value)") | join(", ") | if . == "" then "aucun label pod-security (niveau privileged par défaut)" else . end)"'
  echo "set-security-context : $(kubectl get configmap feature-flags -n tekton-pipelines -o jsonpath='{.data.set-security-context}')"
  echo "pods existants de builds au regard de restricted (label enforce en dry-run serveur) :"
  kubectl label --dry-run=server --overwrite namespace builds pod-security.kubernetes.io/enforce=restricted 2>&1 | sed 's/^/  /'

  echo "## Pipelines : set-security-context (prepare, place-scripts, working-dir-initializer, sidecar des résultats)"
  drapeau true
  echo "## builds : Pod Security restricted en warn et audit, puis enforce (décision du propriétaire du 30/10/2026)"
  kubectl label --overwrite namespace builds pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/warn-version=latest \
    pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/audit-version=latest >/dev/null

  echo "## variante : tâche en service signée sans son stepTemplate"
  sed -e "s#@IMAGE@#$REG/builds/essai-webhook#" -e "s#@DIGEST@#$APP_DIGEST#" -e "s#@BUSYBOX@#$busybox#" \
    -e '/^  stepTemplate:$/,/^  steps:$/{/^  steps:$/!d;}' "$here/politique/taches/publier-essai.yaml" > "$T/sans-restriction.yaml"
  [ "$(grep -c securityContext "$T/sans-restriction.yaml")" = 0 ] || { echo "KO   stepTemplate non retiré" >&2; exit 1; }
  tkn task sign "$T/sans-restriction.yaml" -K "$S/taches.key" -f "$T/sans-restriction-signee.yaml" >/dev/null
  sans=$REG/tekton/tasks/publier-sans-restriction@$(bundle "$T/sans-restriction-signee.yaml" tekton/tasks/publier-sans-restriction restreint)
  sed "s#@TACHE@#$sans#" "$here/politique/taches/sample-app-essai.yaml" > "$T/sans-restriction-pipeline.yaml"
  tkn pipeline sign "$T/sans-restriction-pipeline.yaml" -K "$S/taches.key" -f "$T/sans-restriction-pipeline-signee.yaml" >/dev/null
  sans=$REG/tekton/pipelines/sans-restriction@$(bundle "$T/sans-restriction-pipeline-signee.yaml" tekton/pipelines/sans-restriction restreint)
  echo "pipeline signée : ${sans#"$REG/"}"

  echo "## audit : enforce levé le temps de ce seul cas (le piège le repose) ; création du pod tracée, sans refus"
  trap 'kubectl label --overwrite namespace builds pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest >/dev/null 2>&1
    drapeau true; rm -rf "$T/auth" "$W/refus.out"' EXIT
  kubectl label namespace builds pod-security.kubernetes.io/enforce- pod-security.kubernetes.io/enforce-version- >/dev/null 2>&1 || true
  ENV_N=$(enveloppes builds/essai-webhook)
  verdict "tâche sans stepTemplate, sous warn et audit" True "$(pr_gabarit j6-sans-restriction "$sans")"
  attestee j6-sans-restriction
  m=$(violations "$t0" j6-sans-restriction-publier-pod)
  echo "audit de l'API : $m"
  grep -q 'container "step-publier"' <<< "$m" && ! grep -qE 'container "(prepare|place-scripts)"' <<< "$m" \
    && echo "OK   violations tracées pour l'étape seule" || { echo "KO   annotation d'audit" >&2; exit 1; }

  echo "## enforce restricted sur builds"
  kubectl label --overwrite namespace builds pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest 2>&1 \
    | grep -v '^namespace/' | sed 's/^/  /' || true
  verdict "tâche en service (pipeline du gabarit)" True "$(pr_gabarit j6-restreint "$pipe")"
  attestee j6-restreint
  kubectl get taskrun -n builds j6-restreint-publier -o json | jq -r '"tâche en service : stepTemplate.securityContext \(.status.taskSpec.stepTemplate.securityContext | tostring)"'
  conteneurs j6-restreint-publier-pod
  echo "audit de l'API : $(violations "$t0" j6-restreint-publier-pod)"
  verdict "tâche d'essai de Trusted Resources (TaskRun, essai-confiance)" True "$(taskrun j6-restreint-confiance bundles "$conf")"
  conteneurs j6-restreint-confiance-pod
  st=$(pr_gabarit j6-sans-restriction-enforce "$sans")
  m=$(enfant j6-sans-restriction-enforce)
  echo "tâche sans stepTemplate : PipelineRun ${st%%|*}, TaskRun $m"
  [ "${st%%|*}" = False ] && grep -q '^PodAdmissionFailed : .*violates PodSecurity' <<< "$m" && grep -q 'container "step-publier"' <<< "$m" \
    && ! grep -qE 'container "(prepare|place-scripts)"' <<< "$m" && echo "OK   refusée par Pod Security (étape seule)" \
    || { echo "KO   tâche sans stepTemplate" >&2; exit 1; }
  drapeau false
  st=$(pr_gabarit j6-sans-drapeau "$pipe")
  m=$(enfant j6-sans-drapeau)
  drapeau true
  echo "set-security-context désactivé, tâche en service : PipelineRun ${st%%|*}, TaskRun $m"
  [ "${st%%|*}" = False ] && grep -q '^PodAdmissionFailed : .*violates PodSecurity' <<< "$m" && grep -q 'containers "prepare", "place-scripts"' <<< "$m" \
    && ! grep -q '"step-publier"' <<< "$m" && echo "OK   refusée par Pod Security (conteneurs d'initialisation de Tekton seuls)" \
    || { echo "KO   drapeau désactivé" >&2; exit 1; }
  trap 'rm -rf "$T/auth" "$W/refus.out"' EXIT

  echo "## contrôles"
  kubectl get namespace builds -o json | jq -r '"labels de builds : \(.metadata.labels | to_entries | map(select(.key | startswith("pod-security"))) | map("\(.key)=\(.value)") | join(", "))"'
  [ "$(kubectl get namespace builds -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" = restricted ] \
    && [ "$(kubectl get configmap feature-flags -n tekton-pipelines -o jsonpath='{.data.set-security-context}')" = true ] \
    && echo "OK   enforce restricted sur builds, set-security-context=true" || { echo "KO   état final" >&2; exit 1; }
  sed -n '1,/^---$/p' "$here/tekton/builds.yaml" | sed '$d' | kubectl apply --server-side --dry-run=server -f - -o json \
    | jq -e '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted" and .metadata.labels["pod-security.kubernetes.io/audit"] == "restricted"' >/dev/null \
    && echo "OK   tekton.sh signature (apply de tekton/builds.yaml, dry-run serveur) conserve les labels" \
    || { echo "KO   tekton/builds.yaml retire les labels" >&2; exit 1; }
}

TEMOIN_CLE=essai-j6-autre-cle       # enveloppe bien formée, signée par une autre clé que celle de Chains
TEMOIN_SUJET=essai-j6-autre-sujet   # enveloppe authentique de Chains, posée sur une autre image
TEMOIN_ILLISIBLE=essai-j6-att-illisible   # tag .att dont la couche n'est pas du JSON (cosign download échoue)

zot_ecrire() { oras "$@" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/zot.json"; }   # poc-ecriture, depuis l'hôte
existe() { oras manifest fetch --ca-file "$P/ca-poc.crt" --descriptor "$REG_HOTE/$1" >/dev/null 2>&1; }

image_temoin() { # dépôt : image témoin dans builds (manifeste fait main : même digest à chaque exécution de l'étape) ; digest
  printf 'témoin J6 : builds/%s\n' "$1" > "$T/temoin.txt"
  printf '{}' > "$T/vide.json"
  zot_ecrire blob push "$REG_HOTE/builds/$1" "$T/vide.json" >/dev/null
  zot_ecrire blob push "$REG_HOTE/builds/$1" "$T/temoin.txt" >/dev/null
  jq -nc --arg d "sha256:$(sha256sum < "$T/temoin.txt" | cut -c1-64)" --argjson n "$(stat -c%s "$T/temoin.txt")" '{schemaVersion: 2,
    mediaType: "application/vnd.oci.image.manifest.v1+json", artifactType: "application/vnd.poc.temoin.v1",
    config: {mediaType: "application/vnd.oci.empty.v1+json", digest: "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", size: 2},
    layers: [{mediaType: "text/plain", digest: $d, size: $n}]}' > "$T/temoin.json"
  zot_ecrire manifest push "$REG_HOTE/builds/$1:temoin" "$T/temoin.json" | sed -n 's/^Digest: //p'
}

att_temoin() { # dépôt digest enveloppe : tag .att d'une seule enveloppe, au format de Chains (couche DSSE, config rootfs)
  local l c
  l=sha256:$(sha256sum < "$3" | cut -c1-64)
  jq -nc --arg l "$l" '{architecture: "", os: "", config: {}, rootfs: {type: "layers", diff_ids: [$l]}}' > "$T/att-config.json"
  c=sha256:$(sha256sum < "$T/att-config.json" | cut -c1-64)
  zot_ecrire blob push "$REG_HOTE/builds/$1" "$3" >/dev/null
  zot_ecrire blob push "$REG_HOTE/builds/$1" "$T/att-config.json" >/dev/null
  jq -nc --arg l "$l" --argjson n "$(stat -c%s "$3")" --arg c "$c" --argjson cn "$(stat -c%s "$T/att-config.json")" '{schemaVersion: 2,
    mediaType: "application/vnd.oci.image.manifest.v1+json", config: {mediaType: "application/vnd.oci.image.config.v1+json", digest: $c, size: $cn},
    layers: [{mediaType: "application/vnd.dsse.envelope.v1+json", digest: $l, size: $n,
      annotations: {"dev.cosignproject.cosign/signature": "", "dev.sigstore.cosign/certificate": "", "dev.sigstore.cosign/chain": ""}}]}' > "$T/att.json"
  zot_ecrire manifest push "$REG_HOTE/builds/$1:sha256-${2#sha256:}.att" "$T/att.json" >/dev/null
}

verif_blob() { # enveloppe clé digest : bundle sans jeton vérifié sur l'hôte comme dans le réconciliateur ; « Verified OK » ou motif
  jq -r '.signatures[0].sig' "$1" > "$T/vb.sig"
  jq -r .payload "$1" | base64 -d > "$T/vb.payload"
  cosign bundle create --artifact "$T/vb.payload" --signature "$T/vb.sig" --attestation "$1" --key "$2" --ignore-tlog \
    --out "$T/vb.bundle" 2>/dev/null
  cosign verify-blob-attestation --bundle "$T/vb.bundle" --new-bundle-format --key "$2" --insecure-ignore-tlog \
    --type https://slsa.dev/provenance/v1 --digest "${3#sha256:}" --digestAlg sha256 2>&1 | grep -E '^(Verified OK|Error: )' | head -1
}

enveloppes() { # dépôt : nombre d'enveloppes de Chains dans le tag .att de l'image d'essai
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$1@$APP_DIGEST" 2>/dev/null | wc -l
}

bundles() { # digest : nombre de bundles horodatés de ce digest dans horodatage/bundles (referrers, lecture anonyme)
  curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$DEPOT_BUNDLES/referrers/$1" \
    | jq '[.manifests[] | select(.artifactType == "application/vnd.dev.sigstore.bundle.v0.3+json")] | length'
}

couverture() { # enveloppes de Chains de APP_DIGEST (builds/essai-signature et builds/essai-webhook) et bundles horodatés de ce
  # digest, appariés par la signature de l'enveloppe : $T/sans-bundle (enveloppes à horodater), $T/orphelins (bundles dont
  # l'enveloppe a quitté les tags .att, réécrits sans verrou par Chains : constat-att-ecrasee.log), $T/doublons
  local d m l
  for d in essai-signature essai-webhook; do
    cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/$d@$APP_DIGEST" 2>/dev/null | jq -r '.signatures[0].sig'
  done | sort > "$T/sig-env"
  curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$DEPOT_BUNDLES/referrers/$APP_DIGEST" \
    | jq -r '.manifests[] | select(.artifactType == "application/vnd.dev.sigstore.bundle.v0.3+json") | .digest' | while read -r m; do
      l=$(curl -fsS --cacert "$P/ca-poc.crt" -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
        "https://$REG_HOTE/v2/$DEPOT_BUNDLES/manifests/$m" | jq -r '.layers[0].digest')
      curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$DEPOT_BUNDLES/blobs/$l" > "$T/bundle.json"
      jq -r --arg m "$m" '"\(.dsseEnvelope.signatures[0].sig) \($m) " + (.dsseEnvelope.payload | @base64d | fromjson | .predicate
        | "\(if .buildDefinition.externalParameters.runSpec.pipelineRef != null then "PipelineRun" else "TaskRun" end)"
          + " \(.buildDefinition.internalParameters.labels["tekton.dev/pipelineRun"] // "-"), début \(.runDetails.metadata.startedOn)")' "$T/bundle.json"
    done | sort > "$T/sig-bun"
  cut -d' ' -f1 "$T/sig-bun" | sort > "$T/sig-bun-seules"
  comm -23 "$T/sig-env" "$T/sig-bun-seules" > "$T/sans-bundle"
  comm -13 <(sort -u "$T/sig-env") <(sort -u "$T/sig-bun-seules") > "$T/orphelins"
  uniq -d "$T/sig-bun-seules" > "$T/doublons"
  echo "$APP_DIGEST : $(wc -l < "$T/sig-env") enveloppe(s) de Chains, $(wc -l < "$T/sig-bun") bundle(s) ; sans bundle : $(wc -l < "$T/sans-bundle"),"\
    "orphelin(s) : $(wc -l < "$T/orphelins"), doublon(s) : $(wc -l < "$T/doublons")"
}

couverte() { # n : chaque enveloppe de Chains de APP_DIGEST a son bundle horodaté, aucun doublon, au plus n orphelins (ceux d'avant l'étape)
  local s
  couverture
  [ ! -s "$T/sans-bundle" ] && [ ! -s "$T/doublons" ] && echo "OK   chaque enveloppe de Chains a son bundle horodaté, aucun doublon" \
    || { echo "KO   enveloppe sans bundle ou bundle en double" >&2; exit 1; }
  while read -r s; do
    grep "^$s " "$T/sig-bun" | cut -d' ' -f2- | sed 's/^/  orphelin : bundle /'
  done < "$T/orphelins"
  [ "$(wc -l < "$T/orphelins")" -le "$1" ] || { echo "KO   bundles orphelins : $1 au départ, $(wc -l < "$T/orphelins") maintenant (enveloppe perdue pendant l'étape)" >&2; exit 1; }
  [ -s "$T/orphelins" ] && echo "CONSTAT  $(wc -l < "$T/orphelins") bundle(s) orphelin(s), aucun nouveau : enveloppe(s) perdue(s) du tag .att après leur horodatage, avant cette étape (constat-att-ecrasee-j6.log) ; le dépôt d'horodatage en garde la trace" || true
}

attestee() { # nom : exécution vers builds/essai-webhook@APP_DIGEST sérialisée. Le tag .att est réécrit sans verrou à chaque envoi
  # (constat-att-ecrasee.log) : on attend que Chains ait signé le PipelineRun (il le signe après son TaskRun) avant toute autre
  # exécution vers ce digest, et l'on exige ses deux enveloppes. ENV_N : nombre d'enveloppes de builds/essai-webhook avant.
  local n
  [ "$(signe pipelinerun "$1")" = true ] || { echo "KO   $1 non signé par Chains" >&2; exit 1; }
  n=$(enveloppes builds/essai-webhook)
  [ "$n" = $((ENV_N + 2)) ] && echo "OK   $1 signé par Chains, enveloppes du TaskRun et du PipelineRun présentes ($ENV_N → $n)" \
    || { echo "KO   $1 : $ENV_N → $n enveloppe(s), deux attendues en plus" >&2; exit 1; }
  ENV_N=$n
}

passage() { # instant [espace CronJob] : premier passage du CronJob (horodatage par défaut) créé après cet instant, attendu
  # terminé ; nom du job
  local j="" ns=${2:-horodatage} cj=${3:-horodatage}
  for _ in $(seq 100); do
    j=$(kubectl get jobs -n "$ns" -o json | jq -r --arg t "$1" --arg c "$cj" '[.items[] | select(any(.metadata.ownerReferences[]?; .kind == "CronJob"
      and .name == $c) and .metadata.creationTimestamp > $t and ((.status.succeeded // 0) + (.status.failed // 0)) > 0)]
      | sort_by(.metadata.creationTimestamp) | .[0].metadata.name // empty')
    [ -n "$j" ] && break
    sleep 2
  done
  [ -n "$j" ] || { echo "KO   aucun passage du CronJob $cj terminé depuis $1" >&2; exit 1; }
  echo "$j"
}

analyser() { # job : journal du passage (enveloppes déjà horodatées résumées) ; requêtes de jeton reçues par le TSA pendant
  # le passage (une par enveloppe horodatée, aucune pour une enveloppe refusée) ; témoins : deux refus, une anomalie
  local j=$1 a b ip h r an
  kubectl logs -n horodatage "job/$j" > "$T/passage.log"
  kubectl get job -n horodatage "$j" -o json > "$T/job.json"
  [ "$(jq -r '.status.succeeded // 0' "$T/job.json")" = 1 ] || { cat "$T/passage.log" >&2; echo "KO   passage $j en échec" >&2; exit 1; }
  read -r a b < <(jq -r '[.status.startTime, .status.completionTime] | map(fromdateiso8601) | @tsv' "$T/job.json")
  ip=$(kubectl get pods -n horodatage -l job-name="$j" -o jsonpath='{.items[0].status.podIP}')
  kubectl logs -n tsa deploy/timestamp-authority -c timestamp-server --since-time="$(jq -r .status.startTime "$T/job.json")" \
    | jq -Rr --argjson a "$a" --argjson b "$b" 'fromjson? | select(.ts >= $a - 1 and .ts <= $b + 1) | .message
      | select(test("\"POST [^ ]*/api/v1/timestamp ")) | capture("from (?<ip>[0-9.]+):").ip' > "$T/posts"
  h=$(grep -c '^HORODATEE' "$T/passage.log" || true)
  r=$(grep -c '^REFUSEE' "$T/passage.log" || true)
  grep -v '^DEJA_HORODATEE' "$T/passage.log" | sed 's/^/  /'
  awk -F'|' '$1 == "DEJA_HORODATEE" {n[$2]++} END {for (d in n) printf "  DEJA_HORODATEE|%s ×%d\n", d, n[d]}' "$T/passage.log" | sort
  echo "passage $j : $(jq -r '"\(.status.startTime[11:19]) → \(.status.completionTime[11:19])"' "$T/job.json"), pod $ip ;" \
    "requêtes de jeton reçues par le TSA : $(wc -l < "$T/posts")$(sort -u "$T/posts" | sed 's/^/, depuis /' | paste -sd' ')"
  [ "$(wc -l < "$T/posts")" = "$h" ] && [ "$(sort -u "$T/posts" | grep -vxF "$ip" | wc -l)" = 0 ] \
    && echo "OK   une requête de jeton par enveloppe horodatée ($h), toutes du pod du passage ; aucune pour les $r refusées" \
    || { echo "KO   $(wc -l < "$T/posts") requête(s) de jeton pour $h enveloppe(s) horodatée(s)" >&2; exit 1; }
  [ "$r" = 2 ] || { echo "KO   $r enveloppe(s) refusée(s) au lieu des 2 témoins" >&2; exit 1; }
  an=$(grep -cE '^(IMAGE_ABSENTE|AUCUNE_ATTESTATION|ATTESTATIONS_ILLISIBLES|TAGS_ILLISIBLES)\|' "$T/passage.log" || true)
  [ "$an" = 1 ] && grep -q "^ATTESTATIONS_ILLISIBLES|builds/$TEMOIN_ILLISIBLE|" "$T/passage.log" \
    || { echo "KO   $an anomalie(s) au lieu du seul témoin illisible" >&2; exit 1; }
}

etape_horodatage() {
  local x y z pt t j e0 e1 b0 o0 n w jeton pipe o
  kubectl get secret -n horodatage zot-horodatage >/dev/null 2>&1 || { echo "KO   secret zot-horodatage absent (tsa.sh horodater)" >&2; exit 1; }
  kubectl get triggertemplate -n declencheurs sample-app >/dev/null 2>&1 || { echo "KO   gabarit absent (étape declencheurs)" >&2; exit 1; }
  mkdir -p "$T/auth" && chmod 700 "$T/auth"
  auth_zot "$T/auth/zot.json"
  config_horodatage   # avant les témoins : le script de J5 échouerait sur le témoin illisible, à chaque passage

  echo "## témoins posés dans builds par poc-ecriture (compte d'écriture général) : jamais horodatables"
  # Sortie dans un fichier, puis première ligne : « | head -1 » fermait le tube avant la fin de l'écriture de cosign, arrêté
  # par SIGPIPE (code 141, fatal sous pipefail), observé le 30/10/2026 avec 66 enveloppes (376 ko).
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-webhook@$APP_DIGEST" 2>/dev/null > "$T/att-webhook.jsonl"
  head -1 "$T/att-webhook.jsonl" > "$T/chains-env.json"
  x=$(image_temoin "$TEMOIN_CLE")
  if existe "builds/$TEMOIN_CLE:sha256-${x#sha256:}.att"; then echo "builds/$TEMOIN_CLE@$x : témoin existant"; else
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$T/auth/autre.key")
    openssl pkey -in "$T/auth/autre.key" -pubout -out "$T/autre.pub"
    jq -r .payload "$T/chains-env.json" | base64 -d | jq -c --arg x "${x#sha256:}" '.subject |= map(.digest.sha256 = $x)' > "$T/faux.payload"
    pt=$(jq -r .payloadType "$T/chains-env.json")
    { printf 'DSSEv1 %d %s %d ' "${#pt}" "$pt" "$(stat -c%s "$T/faux.payload")"; cat "$T/faux.payload"; } > "$T/faux.pae"
    openssl dgst -sha256 -sign "$T/auth/autre.key" -out "$T/faux.sig" "$T/faux.pae"
    jq -nc --arg t "$pt" --arg p "$(base64 -w0 "$T/faux.payload")" --arg s "$(base64 -w0 "$T/faux.sig")" \
      '{payloadType: $t, payload: $p, signatures: [{keyid: "", sig: $s}]}' > "$T/faux-env.json"
    att_temoin "$TEMOIN_CLE" "$x" "$T/faux-env.json"
    echo "builds/$TEMOIN_CLE@$x : provenance de Chains réécrite pour l'image témoin, signée (DSSE) par une clé jetable"
    echo "  sur l'hôte : clé du témoin → $(verif_blob "$T/faux-env.json" "$T/autre.pub" "$x") ; clé de Chains → $(verif_blob "$T/faux-env.json" "$R/chains-cle-publique.pem" "$x")"
  fi
  y=$(image_temoin "$TEMOIN_SUJET")
  if existe "builds/$TEMOIN_SUJET:sha256-${y#sha256:}.att"; then echo "builds/$TEMOIN_SUJET@$y : témoin existant"; else
    att_temoin "$TEMOIN_SUJET" "$y" "$T/chains-env.json"
    echo "builds/$TEMOIN_SUJET@$y : enveloppe authentique de Chains (sujet $APP_DIGEST), posée sur l'image témoin"
    echo "  sur l'hôte : digest de l'image d'essai → $(verif_blob "$T/chains-env.json" "$R/chains-cle-publique.pem" "$APP_DIGEST") ; digest du témoin → $(verif_blob "$T/chains-env.json" "$R/chains-cle-publique.pem" "$y")"
  fi
  z=$(image_temoin "$TEMOIN_ILLISIBLE")
  if existe "builds/$TEMOIN_ILLISIBLE:sha256-${z#sha256:}.att"; then echo "builds/$TEMOIN_ILLISIBLE@$z : témoin existant"; else
    printf 'pas du JSON\n' > "$T/illisible.txt"
    att_temoin "$TEMOIN_ILLISIBLE" "$z" "$T/illisible.txt"
    echo "builds/$TEMOIN_ILLISIBLE@$z : tag .att dont la couche n'est pas du JSON (sonde : resultats/politique-horodatage-sonde-att.log)"
  fi
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/$TEMOIN_ILLISIBLE@$z" > /dev/null 2> "$T/illisible.err" \
    && { echo "KO   témoin illisible lu par cosign" >&2; exit 1; }
  echo "  sur l'hôte : cosign download attestation échoue ($(sed -n 's/^Error: //p' "$T/illisible.err" | head -1)) ; le script de J5 (set -e) aurait échoué à chaque passage"

  echo "## CronJob horodatage (politique/horodatage-cronjob.yaml)"
  couverture | sed 's/^/avant : /'
  b0=$(wc -l < "$T/sans-bundle"); o0=$(wc -l < "$T/orphelins")
  echo "prédiction du premier passage : $b0 horodatée(s) (enveloppes sans bundle), 2 refusées et 1 anomalie (témoins), $b0 requête(s) de jeton"
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed -e "s#@OUTILS@#$REG/$OUTILS@$OUTILS_DIGEST#" -e "s#@REG@#$REG#g" "$here/politique/horodatage-cronjob.yaml" \
    | kubectl apply --server-side -f - >/dev/null
  kubectl get cronjob -n horodatage horodatage -o json | jq -c '{schedule: .spec.schedule, concurrencyPolicy: .spec.concurrencyPolicy,
    startingDeadlineSeconds: .spec.startingDeadlineSeconds, activeDeadlineSeconds: .spec.jobTemplate.spec.activeDeadlineSeconds}'

  echo "## premier passage : rattrapage"
  j=$(passage "$t")
  analyser "$j"
  [ "$(grep -c '^HORODATEE' "$T/passage.log" || true)" = "$b0" ] && echo "OK   prédiction tenue" \
    || { echo "KO   prédiction : $b0 horodatée(s)" >&2; exit 1; }
  grep -q "^REFUSEE|builds/$TEMOIN_CLE|.*accepted signatures do not match threshold" "$T/passage.log" \
    && grep -q "^REFUSEE|builds/$TEMOIN_SUJET|.*provided artifact digest does not match" "$T/passage.log" \
    && echo "OK   témoins refusés pour leur motif (autre clé ; autre sujet ; illisible en anomalie), avant toute demande au TSA, sans arrêter le parcours" \
    || { echo "KO   motifs des refus" >&2; exit 1; }
  kubectl get pods -n horodatage -l job-name="$j" -o json | jq -r '.items[0] | "pod \(.metadata.name) : nœud \(.spec.nodeName), compte \(.spec.serviceAccountName), volumes de jeton projetés \([.spec.volumes[] | select(.projected)] | length), sortie \(.status.containerStatuses[0].state.terminated.reason)"'

  echo "## nouvelle exécution signée, supprimée de l'API après sa signature : horodatée au passage suivant"
  pipe=$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value')
  sed "s#@PIPELINE@#$pipe#" "$here/politique/declencheurs.yaml" > "$T/declencheurs.yaml"
  e0=$(enveloppes builds/essai-webhook)
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  verdict "exécution du bundle signé" True "$(pipelinerun j6-horodatage "$pipe" 5555555555555555555555555555555555555555)"
  o=$(kubectl get taskrun -n builds -l tekton.dev/pipelineRun=j6-horodatage -o jsonpath='{.items[0].metadata.name}')
  echo "Chains : TaskRun $o signé=$(signe taskrun "$o"), PipelineRun j6-horodatage signé=$(signe pipelinerun j6-horodatage)"
  e1=$(enveloppes builds/essai-webhook)
  w=$(sur sc-stockage "sudo cat /var/log/zot/audit.log" | jq -r --arg t "$t" 'select(.time >= $t and .subject == "poc-build" and .status == 201
    and (.object | test("^/v2/builds/essai-webhook/manifests/sha256-.*[.]att$"))) | .time' | tail -1)
  echo "builds/essai-webhook : $e0 → $e1 enveloppe(s) ; dernière écriture .att de poc-build (audit de Zot) : ${w:-absente}"
  [ "$e1" -gt "$e0" ] && [ -n "$w" ] || { echo "KO   aucune nouvelle enveloppe de Chains" >&2; exit 1; }
  kubectl delete pipelinerun -n builds --cascade=foreground j6-horodatage --wait=true >/dev/null
  n=$(kubectl get pipelineruns,taskruns -n builds -l tekton.dev/pipelineRun=j6-horodatage -o name | wc -l)
  [ "$n" = 0 ] && ! kubectl get pipelinerun -n builds j6-horodatage >/dev/null 2>&1 \
    && echo "PipelineRun j6-horodatage et son TaskRun supprimés de l'API avant le passage (seul Zot garde la trace)" \
    || { echo "KO   exécution encore présente dans l'API" >&2; exit 1; }
  j=$(passage "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
  analyser "$j"
  n=$(grep -c '^HORODATEE|builds/essai-webhook|' "$T/passage.log" || true)
  [ "$n" = $((e1 - e0)) ] && echo "OK   $n nouvelle(s) enveloppe(s) horodatée(s) au premier passage après la signature, exécution déjà purgée de l'API" \
    || { echo "KO   $n horodatée(s) pour $((e1 - e0)) nouvelle(s)" >&2; exit 1; }
  jeton=$(grep '^HORODATEE|builds/essai-webhook|' "$T/passage.log" | tail -1 | cut -d'|' -f6)
  echo "latence : écriture .att par Chains $(date -u -d "$w" +%T) → jeton du TSA $(date -u -d "${jeton% UTC}" +%T) :" \
    "$(( $(date -d "${jeton% UTC}" +%s) - $(date -d "$w" +%s) )) s (borne : période de 60 s, plus la durée d'un passage)"

  echo "## passage suivant : rien de nouveau"
  oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/$DEPOT_BUNDLES" | sort > "$T/tags-avant"
  j=$(passage "$(jq -r .metadata.creationTimestamp "$T/job.json")")
  analyser "$j"
  oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/$DEPOT_BUNDLES" | sort > "$T/tags-apres"
  [ "$(grep -c '^HORODATEE' "$T/passage.log" || true)" = 0 ] && cmp -s "$T/tags-avant" "$T/tags-apres" \
    && echo "OK   aucune enveloppe horodatée, aucun jeton demandé, étiquettes de $DEPOT_BUNDLES inchangées ($(wc -l < "$T/tags-apres"))" \
    || { echo "KO   passage sans nouveauté" >&2; exit 1; }

  echo "## contrôles"
  couverte "$o0"
  [ "$(bundles "$x")" = 0 ] && [ "$(bundles "$y")" = 0 ] && [ "$(bundles "$z")" = 0 ] && echo "OK   aucun bundle pour les images témoins" || { echo "KO   bundle d'un témoin" >&2; exit 1; }
  COSIGN_REPOSITORY=$REG_HOTE/$DEPOT_BUNDLES cosign verify-attestation --key "$R/chains-cle-publique.pem" --insecure-ignore-tlog \
    --use-signed-timestamps --trusted-root "$P/tsa-racine-confiance.json" --type slsaprovenance1 \
    --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-webhook@$APP_DIGEST" > "$T/porte.out" 2> "$T/porte.err" \
    || { cat "$T/porte.err" >&2; echo "KO   vérification de la porte" >&2; exit 1; }
  echo "OK   chemin de la porte (cosign v3.1.4, bundles de $DEPOT_BUNDLES, jeton exigé, racine du TSA) : $(wc -l < "$T/porte.out") attestation(s) vérifiée(s)"
}

tete() { curl -fsS --cacert "$P/ca-poc.crt" "$FORGEJO_HOTE/api/v1/repos/$SAMPLE_APP/branches/main" | jq -r .commit.id; }

tete_servie() { # commit : attend ce commit en tête de main dans l'API de Forgejo (mise à jour asynchrone, J2)
  for _ in $(seq 30); do [ "$(tete)" = "$1" ] && return 0; sleep 1; done
  echo "KO   tête de main ≠ $1" >&2; exit 1
}

git_forgejo() { # commande git… dans le clone $T/depot, isolé de la configuration de l'utilisateur ; jeton de poc-admin par
  # l'environnement (en-tête http.extraHeader), jamais en argument ; auteur et dates fixes : commits d'essai reproductibles
  (export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
   export GIT_AUTHOR_NAME="PoC brique 08" GIT_AUTHOR_EMAIL=poc-admin@poc.test GIT_AUTHOR_DATE=2026-10-30T00:00:00Z
   export GIT_COMMITTER_NAME="PoC brique 08" GIT_COMMITTER_EMAIL=poc-admin@poc.test GIT_COMMITTER_DATE=2026-10-30T00:00:00Z
   GIT_CONFIG_VALUE_0=$(cat "$T/auth/entete")
   export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1=http.sslCAInfo GIT_CONFIG_VALUE_1="$P/ca-poc.crt"
   git -C "$T/depot" "$@")
}

journal_rattrapage() { # job : journal d'un passage du CronJob rattrapage (réussi exigé), dans $T/rattrapage.log
  kubectl logs -n declencheurs "job/$1" > "$T/rattrapage.log" 2>&1 || true
  sed "s/^/  /" "$T/rattrapage.log"
  [ "$(kubectl get job -n declencheurs "$1" -o jsonpath='{.status.succeeded}')" = 1 ] || { echo "KO   passage $1 en échec" >&2; exit 1; }
}

origine() { # nom : chemin de création d'un PipelineRun de builds, lu dans ses labels
  kubectl get pipelinerun -n builds "$1" -o json | jq -r '.metadata.labels // {} | if .["poc.test/declencheur"] then "rattrapage"
    elif .["triggers.tekton.dev/eventlistener"] then "EventListener \(.["triggers.tekton.dev/eventlistener"])" else "inconnue" end'
}

creations() { # instant nom : créations du PipelineRun nom dans l'audit de l'API depuis l'instant (compte, code)
  audit_api "$2" | jq -r --arg d "$1" --arg n "$2" 'select(.stageTimestamp >= $d
    and .verb == "create" and .objectRef.resource == "pipelineruns" and .objectRef.namespace == "builds"
    and .objectRef.name == $n) | "\(.user.username | sub("system:serviceaccount:"; "")) \(.responseStatus.code)"' \
    | sort | uniq -c | sed 's/^ */    /'
}

livraisons() { # instant : échecs de livraison dans le journal de Forgejo (Info : un succès n'est tracé qu'en Trace)
  sur sc-stockage "sudo journalctl -u forgejo --since '$1' -o cat" | grep 'Unable to deliver webhook task' | cut -c1-220 || true
}

provenance() { # nom : runSpec (externalParameters) de la provenance de Chains de ce PipelineRun de builds, retrouvée par son
  # UID (invocationId) parmi les enveloppes de builds/essai-webhook ; commit remplacé par « COMMIT »
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-webhook@$APP_DIGEST" 2>/dev/null \
    | jq -cS --arg u "$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.metadata.uid}')" '.payload | @base64d | fromjson | .predicate
      | select(.runDetails.metadata.invocationId == $u) | .buildDefinition.externalParameters.runSpec
      | .params |= map(if .name == "commit" then .value = "COMMIT" else . end)'
}

internes() { # nom : internalParameters (drapeaux, labels, annotations) de la provenance de Chains de ce PipelineRun, et labels et
  # annotations du TaskRun signé dans son entrée pipelineTask (TaskRun complet en slsa-tekton)
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/builds/essai-webhook@$APP_DIGEST" 2>/dev/null \
    | jq -cS --arg u "$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.metadata.uid}')" '.payload | @base64d | fromjson | .predicate
      | select(.runDetails.metadata.invocationId == $u) | .buildDefinition
      | {drapeaux: .internalParameters["tekton-pipelines-feature-flags"], labels: .internalParameters.labels,
         annotations: .internalParameters.annotations,
         taskrun: ([.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
           | {labels: .metadata.labels, annotations: .metadata.annotations}][0])}'
}

derniere() { # nom : la provenance de PipelineRun la plus récente de builds/essai-webhook, seule jugée par la porte, est la sienne
  local u; u=$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.metadata.uid}')
  [ "$(prov_pr "builds/essai-webhook@$APP_DIGEST" | jq -sr 'max_by(.predicate.runDetails.metadata.finishedOn).predicate.runDetails.metadata.invocationId')" = "$u" ] \
    && echo "OK   la provenance la plus récente de builds/essai-webhook est celle de $1" || { echo "KO   provenance la plus récente hors de $1" >&2; exit 1; }
}

etape_rattrapage() {
  local i d c1 c2 t tr tp tpush j n pr v1 v2 s o0
  kubectl get triggertemplate -n declencheurs sample-app >/dev/null 2>&1 || { echo "KO   gabarit absent (étape declencheurs)" >&2; exit 1; }
  kubectl get configmap -n porte porte >/dev/null 2>&1 || { echo "KO   porte absente (étape porte d'abord)" >&2; exit 1; }
  couverture > /dev/null; o0=$(wc -l < "$T/orphelins")
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  printf 'Authorization: token %s\n' "$(cat "$S/forgejo-admin.token")" > "$T/auth/entete"

  echo "## réconciliateur (politique/rattrapage : Go, bibliothèque standard seule) : deux compilations indépendantes"
  GOROOT=$GOROOT_DIR "$GOROOT_DIR/bin/go" version   # mise exporte le GOROOT de Go 1.24.7 (banc B)
  for i in 1 2; do
    rm -rf "$T/gocache-$i"
    (cd "$here/politique/rattrapage" && GOROOT=$GOROOT_DIR GOTOOLCHAIN=local GOCACHE="$T/gocache-$i" CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOFLAGS= \
      "$GOROOT_DIR/bin/go" build -trimpath -buildvcs=false -ldflags='-s -w -buildid=' -o "$T/rattrapage-$i" .)
  done
  (cd "$T" && sha256sum rattrapage-1 rattrapage-2)
  [ "$(sha256sum < "$T/rattrapage-1" | cut -c1-64)" = "$RATTRAPAGE_BIN" ] && cmp -s "$T/rattrapage-1" "$T/rattrapage-2" \
    && echo "OK   binaire reproductible, empreinte épinglée" || { echo "KO   binaire ≠ $RATTRAPAGE_BIN" >&2; exit 1; }
  echo "## image : une couche (le binaire), base vide, linux/amd64, utilisateur 65532"
  rm -rf "$T/racine" && mkdir -p "$T/racine" && chmod 0755 "$T/racine"
  install -m 0755 "$T/rattrapage-1" "$T/racine/rattrapage"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$T/couche.tar" -C "$T/racine" rattrapage
  DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt crane append --oci-empty-base -f "$T/couche.tar" -t "$REG_HOTE/$RATTRAPAGE:v1" >/dev/null 2>&1
  d=$(DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt crane mutate --set-platform linux/amd64 --user 65532:65532 \
    --entrypoint /rattrapage -t "$REG_HOTE/$RATTRAPAGE:v1" "$REG_HOTE/$RATTRAPAGE:v1" 2>/dev/null)
  SSL_CERT_FILE=$P/ca-poc.crt crane config "$REG_HOTE/$RATTRAPAGE@${d##*@}" | jq -c '{os, architecture, user: .config.User, entrypoint: .config.Entrypoint, couches: (.rootfs.diff_ids | length)}'
  echo "image : $REG_HOTE/$RATTRAPAGE@${d##*@}"
  [ "${d##*@}" = "$RATTRAPAGE_DIGEST" ] && echo "OK   même digest que l'image épinglée (assemblage reproductible)" \
    || { echo "KO   digest différent de l'image épinglée $RATTRAPAGE_DIGEST" >&2; exit 1; }

  echo "## état de départ : main en $TETE_J2, PipelineRuns des commits d'essai retirés"
  rm -rf "$T/depot" && mkdir -p "$T/depot"
  git_forgejo clone -q --bare "$FORGEJO_HOTE/$SAMPLE_APP.git" .
  c1=$(git_forgejo commit-tree "$TETE_J2^{tree}" -p "$TETE_J2" -m "J6 : essai du rattrapage (webhook perdu)")
  c2=$(git_forgejo commit-tree "$TETE_J2^{tree}" -p "$c1" -m "J6 : essai de course (webhook et rattrapage)")
  echo "commits d'essai (arbre de $TETE_J2, auteur et dates fixes) : c1 $c1, c2 $c2"
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":true}}' >/dev/null 2>&1 || true
  kubectl scale deploy -n declencheurs el-forgejo --replicas=1 >/dev/null
  [ "$(tete)" = "$TETE_J2" ] || { git_forgejo push -q --force "$FORGEJO_HOTE/$SAMPLE_APP.git" "$TETE_J2:refs/heads/main"; tete_servie "$TETE_J2"; }
  kubectl delete pipelinerun -n builds --cascade=foreground "sample-app-$c1" "sample-app-$c2" --ignore-not-found --wait=true >/dev/null
  if kubectl get pipelinerun -n builds "sample-app-$TETE_J2" >/dev/null 2>&1; then
    kubectl get pipelinerun -n builds "sample-app-$TETE_J2" -o json | jq -r '"\(.metadata.name) : créé \(.metadata.creationTimestamp), signé=\(.metadata.annotations["chains.tekton.dev/signed"])"'
    d=PRESENT
  else
    echo "sample-app-$TETE_J2 absent de l'API"; d=CREE
  fi
  echo "prédiction du premier passage : $d|builds/sample-app-$TETE_J2"

  echo "## CronJob rattrapage (politique/rattrapage.yaml)"
  kubectl create configmap rattrapage -n declencheurs --from-file=ca-poc.crt="$P/ca-poc.crt" --dry-run=client -o yaml \
    | kubectl apply --server-side -f - >/dev/null
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed "s#@RATTRAPAGE@#$REG/$RATTRAPAGE@$RATTRAPAGE_DIGEST#" "$here/politique/rattrapage.yaml" | kubectl apply --server-side --force-conflicts -f - >/dev/null
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":false}}' >/dev/null
  j=$(passage "$t" declencheurs rattrapage)
  journal_rattrapage "$j"
  grep -q "^$d|builds/sample-app-$TETE_J2" "$T/rattrapage.log" && echo "OK   prédiction tenue" || { echo "KO   prédiction" >&2; exit 1; }
  kubectl get pods -n declencheurs -l job-name="$j" -o json | jq -r '.items[0] | "pod \(.metadata.name) : nœud \(.spec.nodeName), compte \(.spec.serviceAccountName), automountServiceAccountToken=\(.spec.automountServiceAccountToken), jeton projeté \([.spec.volumes[] | .projected.sources[]? | .serviceAccountToken.expirationSeconds | select(.)] | join(",")) s, sortie \(.status.containerStatuses[0].state.terminated.reason)"'

  echo "## NetworkPolicy rattrapage : sorties d'un pod d'essai au même label (busybox de J4)"
  sed -e "s#@BUSYBOX@#$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")#" \
    -e "s#@EL@#$(kubectl get pods -n declencheurs -l eventlistener=forgejo -o jsonpath='{.items[0].status.podIP}')#" > "$T/reseau.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: essai-reseau-rattrapage
  namespace: declencheurs
  labels:
    app: rattrapage
spec:
  automountServiceAccountToken: false
  enableServiceLinks: false
  restartPolicy: Never
  nodeSelector:
    zone: confiance
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: essai
    image: @BUSYBOX@
    command:
    - sh
    - -c
    - |
      # Fenêtre de démarrage : Zot (interdit) tenté dès le lancement, toutes les 0,5 s, jusqu'à 3 échecs de suite (60 s au plus).
      cs() { read u r < /proc/uptime; echo $(( ${u%.*} * 100 + 1${u#*.} - 100 )); }
      t0=$(cs); o=0; f=0; d=-
      while [ $f -lt 3 ] && [ $(( $(cs) - t0 )) -lt 6000 ]; do
        if nc -z -w 1 192.168.161.13 5000 2>/dev/null; then o=$((o + 1)); f=0; d=$(( ($(cs) - t0) * 10 )); else f=$((f + 1)); fi
        sleep 0.5
      done
      echo "FENETRE|Zot joignable $o fois, la dernière à $d ms du lancement du conteneur, puis $f refus de suite"
      for c in Forgejo:192.168.161.13:3000 API-noeud:192.168.161.11:6443 API-service:10.43.0.1:443 Zot:192.168.161.13:5000 \
               SSH-stockage:192.168.161.13:22 kubelet-build:192.168.161.12:10250 EventListener:@EL@:8080 \
               TSA:timestamp-authority.tsa.svc.cluster.local:3000 OpenBao:openbao.openbao.svc.cluster.local:8200; do
        l=${c%%:*}; r=${c#*:}; h=${r%:*}; p=${r##*:}
        if nc -z -w 3 "$h" "$p" 2>/dev/null; then echo "OUVERT $l $h:$p"; else echo "FERME $l $h:$p"; fi
      done
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
EOF
  kubectl delete pod -n declencheurs essai-reseau-rattrapage --ignore-not-found --wait=true >/dev/null
  kubectl create -f "$T/reseau.yaml" >/dev/null
  kubectl wait -n declencheurs --for=jsonpath='{.status.phase}'=Succeeded pod/essai-reseau-rattrapage --timeout=180s >/dev/null
  kubectl logs -n declencheurs essai-reseau-rattrapage | tee "$T/reseau.txt" | sed 's/^/  /'
  kubectl delete pod -n declencheurs essai-reseau-rattrapage --wait=false >/dev/null
  [ "$(grep -c '^OUVERT' "$T/reseau.txt")" = 3 ] && grep -q '^OUVERT Forgejo ' "$T/reseau.txt" && grep -q '^OUVERT API-noeud ' "$T/reseau.txt" \
    && grep -q '^OUVERT API-service ' "$T/reseau.txt" && echo "OK   sorties, une fois la règle posée : Forgejo et l'API seulement (plus le DNS)" \
    || { echo "KO   sorties du pod de rattrapage" >&2; exit 1; }
  grep -q '^FENETRE|.*puis 3 refus de suite$' "$T/reseau.txt" || { echo "KO   règle jamais appliquée en 60 s" >&2; exit 1; }
  echo "CONSTAT  fenêtre de démarrage : une sortie interdite passe pendant la première seconde du conteneur, avant que kube-router ne pose la règle (sonde : resultats/politique-rattrapage-sonde-fenetre.log)"

  echo "## webhook perdu : EventListener arrêté (0 réplique), push de c1"
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":true}}' >/dev/null
  for _ in $(seq 60); do [ "$(kubectl get cronjob -n declencheurs rattrapage -o jsonpath='{.status.active}')" = "" ] && break; sleep 2; done
  kubectl scale deploy -n declencheurs el-forgejo --replicas=0 >/dev/null
  kubectl wait -n declencheurs --for=delete pod -l eventlistener=forgejo --timeout=120s >/dev/null 2>&1 || true
  echo "EventListener : $(kubectl get deploy -n declencheurs el-forgejo -o jsonpath='{.spec.replicas}') réplique, $(kubectl get pods -n declencheurs -l eventlistener=forgejo --no-headers 2>/dev/null | wc -l) pod ; CronJob suspendu"
  tp=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'"); tpush=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  git_forgejo push -q "$FORGEJO_HOTE/$SAMPLE_APP.git" "$c1:refs/heads/main"
  tete_servie "$c1"
  echo "push de c1 à $tpush ; tête de main dans Forgejo : $(tete)"
  for _ in $(seq 30); do [ -n "$(livraisons "$tp")" ] && break; sleep 1; done
  livraisons "$tp" | tee "$T/livraisons" | sed 's/^/  Forgejo : /'
  [ "$(wc -l < "$T/livraisons")" = 1 ] && echo "OK   une tentative de livraison, en échec" || { echo "KO   $(wc -l < "$T/livraisons") échec(s) de livraison" >&2; exit 1; }

  echo "## EventListener rétabli : aucune relivraison (attente de 150 s)"
  kubectl scale deploy -n declencheurs el-forgejo --replicas=1 >/dev/null
  el_joignable
  sleep 150
  livraisons "$tp" > "$T/livraisons-2"
  n=$({ kubectl get pipelinerun -n builds "sample-app-$c1" -o name 2>/dev/null || true; } | wc -l)   # absent : pipefail
  echo "après 150 s : $n PipelineRun pour c1 ; échecs de livraison dans le journal de Forgejo : $(wc -l < "$T/livraisons-2") ; créations dans l'audit de l'API :"
  creations "$tpush" "sample-app-$c1" | tee "$T/creations"
  [ "$n" = 0 ] && cmp -s "$T/livraisons" "$T/livraisons-2" && [ ! -s "$T/creations" ] \
    && echo "OK   push perdu : Forgejo n'a ni relivré ni retenté, aucune création demandée à l'API" || { echo "KO   relivraison ou PipelineRun inattendu" >&2; exit 1; }

  echo "## rattrapage : CronJob réactivé"
  # Suspendu depuis le push : aucun passage avant la réactivation. Le contrôleur lance aussitôt le passage manqué
  # (startingDeadlineSeconds), parfois dans la même seconde : l'instant de référence est pris une seconde plus tôt.
  tr=$(date -u +%Y-%m-%dT%H:%M:%SZ); t=$(date -u -d "$tr -1 second" +%Y-%m-%dT%H:%M:%SZ)
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":false}}' >/dev/null
  j=$(passage "$t" declencheurs rattrapage)
  journal_rattrapage "$j"
  grep -q "^CREE|builds/sample-app-$c1|commit $c1|depot https://sc-stockage.poc.test:3000/$SAMPLE_APP.git$" "$T/rattrapage.log" \
    && echo "OK   PipelineRun de c1 créé par le rattrapage" || { echo "KO   rattrapage de c1" >&2; exit 1; }
  pr=sample-app-$c1
  verdict "exécution rattrapée" True "$(issue pipelinerun "$pr")"
  echo "$pr : origine $(origine "$pr") ; labels $(kubectl get pipelinerun -n builds "$pr" -o json | jq -c '.metadata.labels | with_entries(select(.key | startswith("tekton.dev") | not))') ; Chains : signé=$(signe pipelinerun "$pr")"
  echo "créations de $pr dans l'audit de l'API depuis le push :"; creations "$tpush" "$pr"
  echo "délais : push de c1 $(date -u -d "$tpush" +%T), CronJob réactivé $(date -u -d "$tr" +%T), PipelineRun créé $(kubectl get pipelinerun -n builds "$pr" -o jsonpath='{.metadata.creationTimestamp}' | cut -c12-19)"

  echo "## passage suivant : rien à rattraper"
  j=$(passage "$(kubectl get job -n declencheurs "$j" -o jsonpath='{.metadata.creationTimestamp}')" declencheurs rattrapage)
  journal_rattrapage "$j"
  grep -qx "PRESENT|builds/$pr" "$T/rattrapage.log" && echo "OK   PRESENT : aucun PipelineRun créé" || { echo "KO   passage sans nouveauté" >&2; exit 1; }

  echo "## horodatage de l'exécution rattrapée (CronJob horodatage)"
  # Un passage de la minute écoulée a pu les horodater déjà : on attend un passage postérieur à la signature, puis on
  # vérifie l'invariant de l'étape horodatage (un bundle par enveloppe de Chains).
  j=$(passage "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
  analyser "$j"
  couverte "$o0"
  echo "OK   l'exécution rattrapée est horodatée"

  echo "## porte sur la provenance de l'exécution rattrapée (prédiction : celle de la tâche en service, étape porte)"
  derniere "$pr"
  v1=$(juger rattrapage "$REG/builds/essai-webhook@$APP_DIGEST"); echo "  $v1"

  echo "## course : EventListener et rattrapage actifs, push de c2"
  tp=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'"); tpush=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  git_forgejo push -q "$FORGEJO_HOTE/$SAMPLE_APP.git" "$c2:refs/heads/main"
  tete_servie "$c2"
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # tout passage créé ensuite lit c2
  pr=sample-app-$c2
  for _ in $(seq 90); do kubectl get pipelinerun -n builds "$pr" >/dev/null 2>&1 && break; sleep 1; done
  j=$(passage "$t" declencheurs rattrapage)
  journal_rattrapage "$j"
  echo "créations de $pr dans l'audit de l'API depuis le push :"; creations "$tpush" "$pr"
  echo "$pr : origine $(origine "$pr") ; échecs de livraison : $(livraisons "$tp" | wc -l)"
  verdict "exécution de c2" True "$(issue pipelinerun "$pr")"
  [ "$(kubectl get pipelineruns -n builds -o name | grep -c "/$pr$")" = 1 ] && echo "OK   un seul PipelineRun pour c2" || { echo "KO   doublon" >&2; exit 1; }
  echo "Chains : $pr signé=$(signe pipelinerun "$pr")"
  echo "## porte sur la provenance de l'exécution créée par l'EventListener"
  derniere "$pr"
  v2=$(juger eventlistener "$REG/builds/essai-webhook@$APP_DIGEST"); echo "  $v2"

  echo "## même PipelineRun par les deux chemins : c1 (rattrapage) et c2 (EventListener, créé par Triggers), au commit près"
  [ "$(origine "sample-app-$c1")" = rattrapage ] && [ "$(origine "$pr")" = "EventListener forgejo" ] \
    || { echo "KO   origines : c1 $(origine "sample-app-$c1"), c2 $(origine "$pr") (course gagnée par le rattrapage : relancer l'étape)" >&2; exit 1; }
  for n in "$c1" "$c2"; do
    kubectl get pipelinerun -n builds "sample-app-$n" -o json | jq -S '.spec | .params |= map(if .name == "commit" then .value = "COMMIT" else . end)' > "$T/spec-$n.json"
    provenance "sample-app-$n" > "$T/prov-$n"
  done
  diff "$T/spec-$c2.json" "$T/spec-$c1.json" && echo "OK   spec identique (depot, pipeline signée, gabarit de pod, compte), commit excepté" \
    || { echo "KO   spec différente" >&2; exit 1; }
  [ "$(wc -l < "$T/prov-$c1")" = 1 ] && cmp -s "$T/prov-$c2" "$T/prov-$c1" \
    && echo "OK   provenances de Chains (retrouvées par l'UID de chaque PipelineRun) : même runSpec, commit excepté" \
    || { diff "$T/prov-$c2" "$T/prov-$c1" >&2 || true; echo "KO   provenances" >&2; exit 1; }

  echo "## internalParameters signés (buildType slsa-tekton) : labels et annotations du PipelineRun, et du TaskRun de l'entrée pipelineTask"
  echo "prédiction : drapeaux et annotations identiques ; labels : poc.test/declencheur=rattrapage (c1) contre les trois labels de Triggers"
  echo "(c2), aux deux niveaux ; dans le TaskRun, en plus, tekton.dev/pipelineRun et tekton.dev/pipelineRunUID (nom et UID de chaque PipelineRun)"
  for n in "$c1" "$c2"; do internes "sample-app-$n" > "$T/internes-$n"; done
  jq -nS --slurpfile a "$T/internes-$c1" --slurpfile b "$T/internes-$c2" '
    def ecart($x; $y): {rattrapage: ($x | with_entries(select(.key as $k | $y | has($k) | not))),
      eventlistener: ($y | with_entries(select(.key as $k | $x | has($k) | not))),
      differents: [$x | keys[] | select(. as $k | ($y | has($k)) and $x[$k] != $y[$k])]};
    $a[0] as $x | $b[0] as $y
    | {drapeaux_identiques: ($x.drapeaux == $y.drapeaux), annotations_identiques: ($x.annotations == $y.annotations),
       annotations_taskrun_identiques: ($x.taskrun.annotations == $y.taskrun.annotations),
       labels: ecart($x.labels; $y.labels), labels_taskrun: ecart($x.taskrun.labels; $y.taskrun.labels)}' > "$T/internes-ecart"
  jq -c 'to_entries[]' "$T/internes-ecart" | sed 's/^/  /'
  jq -e '.drapeaux_identiques and .annotations_identiques and .annotations_taskrun_identiques
    and .labels.rattrapage == {"poc.test/declencheur": "rattrapage"} and .labels.differents == []
    and (.labels.eventlistener | keys) == ["triggers.tekton.dev/eventlistener", "triggers.tekton.dev/trigger", "triggers.tekton.dev/triggers-eventid"]
    and .labels.eventlistener["triggers.tekton.dev/eventlistener"] == "forgejo"
    and .labels_taskrun.rattrapage == .labels.rattrapage and .labels_taskrun.eventlistener == .labels.eventlistener
    and .labels_taskrun.differents == ["tekton.dev/pipelineRun", "tekton.dev/pipelineRunUID"]' "$T/internes-ecart" >/dev/null \
    && echo "OK   seul écart signé : les labels posés par chaque créateur (chemin déclaré, identifiant d'événement de Triggers) ; aucun n'est vérifié par Chains" \
    || { echo "KO   internalParameters : écart non prédit" >&2; exit 1; }
  s=$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value')
  SSL_CERT_FILE=$P/ca-poc.crt crane export "$REG_HOTE/${s#*/}" - | tar -xO | jq -r '.metadata.annotations["tekton.dev/signature"]' > "$T/sig-pipeline"
  grep -o 'tekton.dev/signature: .*' "$here/politique/taches/publier-essai.signee.yaml" | cut -d' ' -f2 > "$T/sig-tache"
  jq -r '.taskrun.annotations["tekton.dev/signature"]' "$T/internes-$c1" > "$T/sig-taskrun"
  if cmp -s "$T/sig-taskrun" "$T/sig-pipeline" && ! cmp -s "$T/sig-taskrun" "$T/sig-tache"; then
    echo "CONSTAT  annotation tekton.dev/signature du TaskRun signé : celle de la pipeline en service ($(cut -c1-12 "$T/sig-pipeline")…, lue dans son bundle),"
    echo "         pas celle de la tâche ($(cut -c1-12 "$T/sig-tache")…) : Pipelines v1.15.5 propage au TaskRun les annotations du PipelineRun, reçues de"
    echo "         la Pipeline, et elles priment sur celles de la Task ; aucune politique ne la lit, trusted_task épingle par digest"
  else echo "signature du TaskRun signé : $(cut -c1-12 "$T/sig-taskrun")… ; pipeline : $(cut -c1-12 "$T/sig-pipeline")… ; tâche : $(cut -c1-12 "$T/sig-tache")…"; fi

  echo "## porte : verdicts des deux chemins (prédiction : celui de la tâche en service)"
  for s in "$v1" "$v2"; do
    [ "$(cut -d'|' -f3-5 <<< "$s")" = "false|$(trier "$SRC_J7")|trusted_task.tagged" ] || { echo "KO   verdict non prédit : $s" >&2; exit 1; }
  done
  succes rattrapage trusted_task.trusted && succes eventlistener trusted_task.trusted \
    && echo "OK   même verdict par les deux chemins : règles de source seules en échec (attendu jusqu'à J7), trusted_task.trusted parmi les succès ; l'écart des labels est sans effet sur la porte" \
    || { echo "KO   trusted_task.trusted absent des succès" >&2; exit 1; }

  echo "## main remise à $TETE_J2 (force-push) : livraison acceptée, rejeu sans effet"
  tpush=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  git_forgejo push -q --force "$FORGEJO_HOTE/$SAMPLE_APP.git" "$TETE_J2:refs/heads/main"
  tete_servie "$TETE_J2"
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "tête de main : $(tete)"
  j=$(passage "$t" declencheurs rattrapage)
  journal_rattrapage "$j"
  grep -qx "PRESENT|builds/sample-app-$TETE_J2" "$T/rattrapage.log" || { echo "KO   tête $TETE_J2" >&2; exit 1; }
  echo "créations de sample-app-$TETE_J2 dans l'audit de l'API depuis la remise à zéro :"; creations "$tpush" "sample-app-$TETE_J2"
  kubectl get pipelinerun -n builds "sample-app-$TETE_J2" -o jsonpath='{.metadata.creationTimestamp}{"\n"}' | sed 's/^/sample-app-'"$TETE_J2"' : créé /'
  rm -f "$T/auth/entete"; rm -rf "$T/depot"
}

prov_pr() { # image (REG_HOTE, par digest) : provenances de PipelineRun signées par Chains (une par ligne), lues dans Zot
  cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$1" 2>/dev/null \
    | jq -c '.payload | @base64d | fromjson | select(.predicate.buildDefinition.externalParameters.runSpec.pipelineRef != null)'
}

variante() { # cas dépôt-de-la-tâche : image builds/essai-porte:<cas> (digest propre au cas), tâche et pipeline signées par la
  # clé des tâches et publiées en bundles, PipelineRun du gabarit de declencheurs, exécuté et signé ; $T/porte-<cas>.{image,tache}
  local c=$1 d tache pipe st
  d=$(DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt crane mutate --label "poc.test/cas=$c" \
    -t "$REG_HOTE/builds/essai-porte:$c" "$REG_HOTE/builds/essai-webhook@$APP_DIGEST" 2>/dev/null)
  echo "${d##*@}" > "$T/porte-$c.image"
  [ "$c" = non-signee ] && { echo "$c : image builds/essai-porte@${d##*@}, jamais présentée à Chains"; return; }
  sed -e "s#@IMAGE@#$REG/builds/essai-porte#" -e "s#@DIGEST@#${d##*@}#" -e "s#@BUSYBOX@#$busybox#" \
    "$here/politique/taches/publier-essai.yaml" > "$T/porte-$c-tache.yaml"
  tkn task sign "$T/porte-$c-tache.yaml" -K "$S/taches.key" -f "$T/porte-$c-tache-signee.yaml" >/dev/null 2>&1
  tache=$REG/$2@$(bundle "$T/porte-$c-tache-signee.yaml" "$2" "porte-$c")
  echo "$tache" > "$T/porte-$c.tache"
  sed "s#@TACHE@#$tache#" "$here/politique/taches/sample-app-essai.yaml" > "$T/porte-$c-pipeline.yaml"
  tkn pipeline sign "$T/porte-$c-pipeline.yaml" -K "$S/taches.key" -f "$T/porte-$c-pipeline-signee.yaml" >/dev/null 2>&1
  pipe=$REG/tekton/pipelines/porte-$c@$(bundle "$T/porte-$c-pipeline-signee.yaml" "tekton/pipelines/porte-$c" "porte-$c")
  st=$(pr_gabarit "j6-porte-$c" "$pipe")
  [ "${st%%|*}" = True ] || { echo "KO   j6-porte-$c : $st" >&2; exit 1; }
  echo "$c : tâche ${tache#"$REG/"}, image builds/essai-porte@${d##*@} ; PipelineRun exécuté, Chains : signé=$(signe pipelinerun "j6-porte-$c")"
}

juger() { # cas image (nom vu des pods, par digest) [politique] : Job de la porte ; une ligne VERDICT|cas|success|violations|
  # avertissements|durée du conteneur en s (codes de règles triés), ou ERREUR|cas|motif si ec n'a rendu aucun verdict
  local j=porte-$1 l d
  kubectl delete job -n porte "$j" --ignore-not-found --wait=true >/dev/null
  sed -e "s#@NOM@#$j#" -e "s#@IMAGE@#$2#" -e "s#@PORTE@#$REG/$PORTE@$PORTE_DIGEST#" -e "s#@POLITIQUE@#${3:-policy.yaml}#" \
    "$here/politique/porte-job.yaml" | kubectl create -f - >/dev/null
  for _ in $(seq 150); do
    [ -n "$(kubectl get job -n porte "$j" -o jsonpath='{.status.succeeded}{.status.failed}')" ] && break
    sleep 2
  done
  kubectl logs -n porte "job/$j" > "$T/$j.log" 2>&1 || true
  l=$(grep -m1 '^{' "$T/$j.log" || true)
  [ -n "$l" ] || { echo "ERREUR|$1|$(tail -1 "$T/$j.log" | cut -c1-200)"; return; }
  printf '%s\n' "$l" > "$T/$j.json"
  d=$(kubectl get pod -n porte -l job-name="$j" -o json | jq -r '.items[0].status.containerStatuses[0].state.terminated
    | (.finishedAt | fromdate) - (.startedAt | fromdate)')
  jq -r --arg c "$1" --arg d "$d" '[.components[] | .violations[]? | .metadata.code] as $v
    | [.components[] | .warnings[]? | .metadata.code] as $w
    | "VERDICT|\($c)|\(.success)|\($v | unique | join(","))|\($w | unique | join(","))|\($d)"' "$T/$j.json"
}

succes() { # cas code : la règle figure parmi les succès du verdict de la porte
  jq -e --arg c "$2" '[.components[] | .successes[]? | .metadata.code] | index($c) != null' "$T/porte-$1.json" >/dev/null
}

trier() { tr ',' '\n' <<< "$1" | sort -u | paste -sd, -; }

etape_porte() {
  local d e bt0 r v c n k=0 prevu busybox t st pipe tache
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente (étape taches)" >&2; exit 1; }
  kubectl get triggertemplate -n declencheurs sample-app >/dev/null 2>&1 || { echo "KO   gabarit absent (étape declencheurs)" >&2; exit 1; }
  kubectl get validatingpolicy zone-confiance -o json | jq -e '.spec.matchConstraints.namespaceSelector.matchExpressions[0].values
    | index("porte") != null' >/dev/null || { echo "KO   porte absent de la règle zone-confiance (étape admission)" >&2; exit 1; }
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  auth_zot "$T/auth/docker/config.json"
  busybox=$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$R/tekton-images.tsv")

  echo "## bibliothèque $CPOL_DEPOT v1.0.28 (Apache-2.0)"
  [ "$(gh api "repos/$CPOL_DEPOT/git/ref/tags/v1.0.28" --jq '.object.type + " " + .object.sha')" = "tag $CPOL_TAG" ] \
    && [ "$(gh api "repos/$CPOL_DEPOT/git/tags/$CPOL_TAG" --jq '.object.type + " " + .object.sha + " " + (.verification.verified | tostring)')" = "commit $CPOL_COMMIT false" ] \
    && [ "$(gh api "repos/$CPOL_DEPOT/commits/$CPOL_COMMIT" --jq '(.commit.verification.verified | tostring) + " " + (.commit.verification.payload | split("\n")[0])')" = "true tree $CPOL_ARBRE" ] \
    && echo "OK   tag v1.0.28 (annoté, non signé) → commit $CPOL_COMMIT, signé (vérifié par GitHub), arbre $CPOL_ARBRE dans le contenu signé" \
    || { echo "KO   tag v1.0.28 de $CPOL_DEPOT" >&2; exit 1; }
  d=$O/telechargements/conforma-policy
  [ -d "$d" ] || git init -q --bare "$d"
  git -C "$d" cat-file -e "$CPOL_COMMIT^{commit}" 2>/dev/null \
    || git -C "$d" -c transfer.fsckObjects=true fetch -q --depth 1 "https://github.com/$CPOL_DEPOT" "$CPOL_COMMIT"
  [ "$(git -C "$d" rev-parse "$CPOL_COMMIT^{tree}")" = "$CPOL_ARBRE" ] \
    && echo "OK   commit récupéré par git (objets vérifiés), même arbre" || { echo "KO   arbre du commit" >&2; exit 1; }

  echo "## image de la porte : ec v0.10.42 et bibliothèque (policy/release, policy/lib, sans les tests), une couche, base vide"
  e=$(command -v ec)
  [ "$(sha256sum < "$e" | cut -c1-64)" = "$EC_BIN" ] && echo "OK   ec : empreinte du verrou mise ($EC_BIN)" \
    || { echo "KO   empreinte de $e" >&2; exit 1; }
  rm -rf "$T/porte-racine" && mkdir -p "$T/porte-racine/politique"
  install -m 0755 "$e" "$T/porte-racine/ec"
  git -C "$d" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$T/porte-racine/politique"
  find "$T/porte-racine/politique" -name '*_test.rego' -delete
  find "$T/porte-racine/politique" -type d -exec chmod 0755 {} +
  find "$T/porte-racine/politique" -type f -exec chmod 0644 {} +
  chmod 0755 "$T/porte-racine"
  echo "bibliothèque : $(find "$T/porte-racine/politique" -name '*.rego' | wc -l) fichiers Rego"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$T/porte.tar" -C "$T/porte-racine" ec politique
  DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt crane append --oci-empty-base -f "$T/porte.tar" -t "$REG_HOTE/$PORTE:v1" >/dev/null 2>&1
  d=$(DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt crane mutate --set-platform linux/amd64 --user 65532:65532 \
    --entrypoint /ec -t "$REG_HOTE/$PORTE:v1" "$REG_HOTE/$PORTE:v1" 2>/dev/null)
  echo "image : $REG_HOTE/$PORTE@${d##*@}"
  [ "${d##*@}" = "$PORTE_DIGEST" ] && echo "OK   même digest que l'image épinglée (assemblage reproductible)" \
    || { echo "KO   digest différent de l'image épinglée $PORTE_DIGEST" >&2; exit 1; }

  echo "## état de départ : buildType de Chains (slsa-tekton, décision du propriétaire du 30/10/2026)"
  bt0=$(kubectl get configmap -n tekton-chains chains-config -o jsonpath='{.data.builddefinition\.buildtype}')
  echo "chains-config : builddefinition.buildtype=$bt0"
  [ "$bt0" = https://tekton.dev/chains/v2/slsa-tekton ] || { echo "KO   buildType inattendu (tekton/chains/chains-config.yaml)" >&2; exit 1; }
  pipe=$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value')

  echo "## tâche en service : PipelineRun du gabarit ; la provenance jugée (la plus récente de builds/essai-webhook) doit venir de lui"
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  st=$(pr_gabarit j6-porte-en-service "$pipe")
  [ "${st%%|*}" = True ] || { echo "KO   j6-porte-en-service : $st" >&2; exit 1; }
  echo "PipelineRun j6-porte-en-service exécuté, Chains : signé=$(signe pipelinerun j6-porte-en-service)"
  kubectl get taskrun -n builds j6-porte-en-service-publier -o json \
    | jq -r --arg u "$(kubectl get pipelinerun -n builds j6-porte-en-service -o jsonpath='{.metadata.uid}')" --arg t "$t" \
      'if .metadata.ownerReferences[0].uid == $u and .metadata.creationTimestamp >= $t then (.spec.taskRef.params[] | select(.name == "bundle") | .value) else "-" end' \
    > "$T/porte-en-service.tache"
  grep -q '@sha256:' "$T/porte-en-service.tache" && listee "$(cat "$T/porte-en-service.tache")" \
    && echo "OK   TaskRun créé par ce PipelineRun ; tâche ${tache:=$(cat "$T/porte-en-service.tache")} dans la liste revue" \
    || { echo "KO   TaskRun repris d'un autre PipelineRun, ou tâche hors de la liste revue" >&2; exit 1; }
  echo "$APP_DIGEST" > "$T/porte-en-service.image"
  prov_pr "builds/essai-webhook@$APP_DIGEST" > "$T/prov-webhook.jsonl"
  jq -sr --arg t "$t" --arg k "$tache" 'length as $n | max_by(.predicate.runDetails.metadata.finishedOn) | (tostring | length) as $o | .predicate
    | ([.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask" and .uri != null) | (.uri | sub("^oci://"; "")) + "@sha256:" + .digest.sha256][0] // "") as $u
    | "\(if .runDetails.metadata.startedOn >= $t and $u == $k then "OK  " else "KO  " end) la plus récente des \($n) : début \(.runDetails.metadata.startedOn), "
      + "\($o) octets, buildType \(.buildDefinition.buildType), entrées pipelineTask avec contenu : "
      + "\([.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask" and .content != null)] | length)"' "$T/prov-webhook.jsonl" | tee "$T/prov-webhook.ligne"
  grep -q '^OK' "$T/prov-webhook.ligne" || { echo "KO   provenance la plus récente hors de cette exécution" >&2; exit 1; }
  jq -sr 'max_by(.predicate.runDetails.metadata.finishedOn).predicate.buildDefinition.internalParameters
    | "internalParameters : \(keys | join(", ")) ; labels du PipelineRun : \(.labels // {} | keys | join(", "))"' "$T/prov-webhook.jsonl"

  echo "## images d'essai : une par cas (la bibliothèque ne juge que la provenance la plus récente d'un digest)"
  echo "mesure en buildType slsa (J4, J5) : Chains basculé le temps d'une image, puis rétabli en slsa-tekton"
  trap 'kubectl patch configmap -n tekton-chains chains-config --type merge -p "{\"data\":{\"builddefinition.buildtype\":\"'"$bt0"'\"}}" >/dev/null; rm -rf "$T/auth" "$W/refus.out"' EXIT
  kubectl patch configmap -n tekton-chains chains-config --type merge -p '{"data":{"builddefinition.buildtype":"https://tekton.dev/chains/v2/slsa"}}' >/dev/null
  variante slsa tekton/tasks/publier-essai
  kubectl patch configmap -n tekton-chains chains-config --type merge -p "{\"data\":{\"builddefinition.buildtype\":\"$bt0\"}}" >/dev/null
  trap 'rm -rf "$T/auth" "$W/refus.out"' EXIT
  echo "chains-config rétabli : $(kubectl get configmap -n tekton-chains chains-config -o jsonpath='{.data.builddefinition\.buildtype}')"
  variante hors-liste tekton/tasks/publier-hors-liste
  variante version-non-listee tekton/tasks/publier-essai
  variante non-signee -
  for c in slsa hors-liste version-non-listee; do
    prov_pr "builds/essai-porte@$(cat "$T/porte-$c.image")" | jq -sr --arg c "$c" 'max_by(.predicate.runDetails.metadata.finishedOn)
      | "\($c) : \(tostring | length) octets, buildType \(.predicate.buildDefinition.buildType), entrées pipelineTask avec contenu : "
      + "\([.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask" and .content != null)] | length)"'
  done
  [ "$(prov_pr "builds/essai-porte@$(cat "$T/porte-slsa.image")" | jq -sr 'max_by(.predicate.runDetails.metadata.finishedOn).predicate.buildDefinition.buildType')" \
    = https://tekton.dev/chains/v2/slsa ] || { echo "KO   provenance de la variante slsa hors slsa" >&2; exit 1; }

  echo "## ConfigMap porte : politique (politique/porte/policy.yaml), règles du PoC (politique/porte/porte.rego), liste revue des"
  echo "## tâches approuvées (politique/porte/taches.yml, ancien format trusted_tasks : digest épinglé), clé publique de Chains, CA du PoC"
  grep -v '^ *#' "$here/politique/porte/taches.yml" | sed 's/^/  /'
  kubectl apply --server-side -f "$here/politique/porte.yaml" >/dev/null
  kubectl create configmap porte -n porte --from-file=policy.yaml="$here/politique/porte/policy.yaml" \
    --from-file=policy-trusted-task.yaml="$here/politique/porte/policy-trusted-task.yaml" \
    --from-file=porte.rego="$here/politique/porte/porte.rego" --from-file=taches.yml="$here/politique/porte/taches.yml" \
    --from-file=chains.pub="$R/chains-cle-publique.pem" --from-file=ca-poc.crt="$P/ca-poc.crt" --dry-run=client -o yaml \
    | kubectl apply --server-side -f - >/dev/null
  # Lu dans la bibliothèque (lib/tekton/pipeline.rego) : la liste de tâches requises est choisie par le label
  # build.appstudio.redhat.com/build_type du TaskRun, à défaut par pipelines.openshift.io/runtime des internalParameters,
  # labels que pose le créateur du PipelineRun.
  ! grep -qE '^ *(required-tasks|pipeline-required-tasks):' "$here/politique/porte/taches.yml" "$here/politique/porte/policy.yaml" \
    "$here/politique/porte/policy-trusted-task.yaml" \
    && echo "OK   aucune liste de tâches requises (required-tasks, pipeline-required-tasks) : les labels qui la choisiraient sont sans effet" \
    || { echo "KO   listes de tâches requises fournies : le créateur du PipelineRun choisirait la sienne par un label" >&2; exit 1; }

  echo "## verdicts de la porte (Job de l'espace porte, sorties DNS et Zot) ; prédiction : codes des règles en violation"
  echo "règles de source (slsa_source_*) en échec attendu jusqu'à J7 : aucune source git dans la provenance de l'essai, aucune source attendue fournie"
  c=$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/builds/$TEMOIN_CLE:temoin")
  while IFS='|' read -r n r pol prevu; do
    prevu=$(trier "${prevu//@SRC@/$SRC_J7}")
    v=$(juger "$n" "$REG/$r" "$pol")
    echo "  $v"
    case $v in
      VERDICT\|*) if [ "$prevu" = PASS ]; then
          [ "$(cut -d'|' -f3,4 <<< "$v")" = "true|" ] && echo "OK   $n : admis, comme prédit" || { echo "KO   $n : admission prédite" >&2; k=$((k + 1)); }
        else
          [ "$(cut -d'|' -f4 <<< "$v")" = "$prevu" ] && [ "$(cut -d'|' -f3 <<< "$v")" = false ] \
            && echo "OK   $n : refus, violations prédites" || { echo "KO   $n : prédiction $prevu" >&2; k=$((k + 1)); }
        fi ;;
      *) echo "KO   $n : aucun verdict" >&2; k=$((k + 1)) ;;
    esac
  done <<EOF
slsa|builds/essai-porte@$(cat "$T/porte-slsa.image")|policy.yaml|porte.taches_vues,tasks.pipeline_has_tasks,slsa_build_scripted_build.build_task_image_results_found,@SRC@
slsa-trusted-task-seul|builds/essai-porte@$(cat "$T/porte-slsa.image")|policy-trusted-task.yaml|PASS
en-service|builds/essai-webhook@$APP_DIGEST|policy.yaml|@SRC@
hors-liste|builds/essai-porte@$(cat "$T/porte-hors-liste.image")|policy.yaml|trusted_task.trusted,@SRC@
version-non-listee|builds/essai-porte@$(cat "$T/porte-version-non-listee.image")|policy.yaml|trusted_task.trusted,@SRC@
non-signee|builds/essai-porte@$(cat "$T/porte-non-signee.image")|policy.yaml|builtin.attestation.signature_check,builtin.image.signature_check
autre-cle|builds/$TEMOIN_CLE@$c|policy.yaml|builtin.attestation.signature_check,builtin.image.signature_check
EOF
  [ "$k" = 0 ] || exit 1
  succes en-service trusted_task.trusted && succes en-service porte.taches_vues \
    && echo "OK   en-service : trusted_task.trusted et porte.taches_vues parmi les succès" || { echo "KO   succès de en-service" >&2; exit 1; }
  succes slsa trusted_task.trusted && echo "CONSTAT  slsa : trusted_task.trusted compté parmi les succès alors qu'aucune tâche n'est vue (succès à vide) ; seuls tasks.pipeline_has_tasks (collection slsa3) et le témoin porte.taches_vues refusent ; avec trusted_task seul, l'image est admise"
  jq -sr --arg t "$tache" 'sort_by(.predicate.runDetails.metadata.finishedOn)
    | map(.predicate | ([.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask" and .uri != null) | (.uri | sub("^oci://"; "")) + "@sha256:" + .digest.sha256][0] // "") as $u
      | "  \(.runDetails.metadata.finishedOn) \(.buildDefinition.buildType // "-" | sub(".*/"; "")) \(if $u == "" then "sans tâche" elif $u == $t then "listée" else "non listée" end)")
    | .[]' "$T/prov-webhook.jsonl" > "$T/provenances-en-service"
  echo "provenances de PipelineRun de builds/essai-webhook (image de la tâche en service) : $(wc -l < "$T/provenances-en-service") ; listées : $(grep -cE ' (slsa|slsa-tekton|-) listée$' "$T/provenances-en-service" || true),"\
    "non listées : $(grep -c 'non listée$' "$T/provenances-en-service" || true), sans tâche : $(grep -c 'sans tâche$' "$T/provenances-en-service" || true) ; les trois plus récentes :"
  tail -3 "$T/provenances-en-service"
  n=$(grep -c 'non listée$' "$T/provenances-en-service" || true)
  if [ "$n" -gt 0 ] && tail -1 "$T/provenances-en-service" | grep -qE ' (slsa|slsa-tekton|-) listée$'; then
    echo "CONSTAT  la bibliothèque ne juge que la provenance la plus récente d'un digest (max de finishedOn) : $n provenance(s) plus ancienne(s), signée(s) par Chains avec une tâche non listée, n'empêche(nt) pas trusted_task.trusted"
  else echo "provenance unique ou dernière non listée : jugement de la seule provenance la plus récente non observable à cette exécution"; fi
  jq -r '[.components[] | .violations[]? | select(.metadata.code == "trusted_task.trusted") | .msg] | .[0]' "$T/porte-hors-liste.json" | cut -c1-200 | sed 's/^/  motif hors-liste : /'
  jq -r '[.components[] | .violations[]?] | map("\(.metadata.code) : \(.msg | .[0:120])") | .[]' "$T/porte-non-signee.json" | sed 's/^/  motif non-signee : /'
}

etape_droits() {
  local debut sujet as verbe ressource ns attendu obtenu nom n k=0
  kubectl apply --server-side -f "$here/politique/droits.yaml" >/dev/null
  TSV_DROITS=$R/politique-droits.tsv
  printf 'sujet\tverbe\tressource\tespace\tattendu\tobtenu\n' > "$TSV_DROITS"
  echo "## kubectl auth can-i (RBAC seul : un droit accordé reste soumis à l'admission, Kyverno compris)"
  while IFS='|' read -r sujet verbe ressource ns attendu; do
    case $sujet in
      '#'*|'') continue ;;
      build) as=(--as=system:serviceaccount:builds:build) ;;
      el-forgejo) as=(--as=system:serviceaccount:declencheurs:el-forgejo) ;;
      operateur) as=(--as=operateur --as-group=operateurs) ;;
      horodatage) as=(--as=system:serviceaccount:horodatage:horodatage) ;;
      rattrapage) as=(--as=system:serviceaccount:declencheurs:rattrapage) ;;
      porte) as=(--as=system:serviceaccount:porte:porte) ;;
      pipelines) as=(--as=system:serviceaccount:tekton-pipelines:tekton-pipelines-controller) ;;
      chains) as=(--as=system:serviceaccount:tekton-chains:tekton-chains-controller) ;;
      *) echo "KO   sujet inconnu : $sujet" >&2; exit 1 ;;
    esac
    if [ "$ns" = '*' ]; then obtenu=$(kubectl auth can-i "$verbe" "$ressource" -A "${as[@]}" 2>/dev/null || true)
    else obtenu=$(kubectl auth can-i "$verbe" "$ressource" -n "$ns" "${as[@]}" 2>/dev/null || true); fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sujet" "$verbe" "$ressource" "$ns" "$attendu" "$obtenu" >> "$TSV_DROITS"
    [ "$obtenu" = "$attendu" ] || { echo "KO   $sujet $verbe $ressource ($ns) : $obtenu au lieu de $attendu" >&2; k=$((k + 1)); }
  done < "$here/politique/droits.txt"
  awk -F'\t' 'NR > 1 { n++; if ($5 == $6) ok++ } END { printf "%d vérifications, %d conformes\n", n, ok }' "$TSV_DROITS"
  awk -F'\t' 'NR > 1 && $6 == "yes" { printf "  accordé : %s %s %s (%s)\n", $1, $2, $3, $4 }' "$TSV_DROITS"
  [ "$k" = 0 ] || exit 1
  echo "## comptes de service du cluster qui peuvent modifier un PipelineRun de builds (update ou patch), donc ses labels et annotations,"
  echo "## que Chains signe en slsa-tekton (internalParameters) ; prédiction : contrôleurs de Pipelines et de Chains, ramasse-miettes de Kubernetes"
  # Première prédiction (contrôleurs seuls, d'après la matrice) démentie le 30/10/2026 : le ramasse-miettes de Kubernetes
  # (kube-system:generic-garbage-collector, propriétaires et finaliseurs) peut aussi modifier tout objet.
  kubectl get serviceaccounts -A -o jsonpath='{range .items[*]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}' > "$T/comptes"
  while IFS=: read -r ns nom; do
    for verbe in update patch; do
      if [ "$(kubectl auth can-i "$verbe" pipelineruns.tekton.dev -n builds --as="system:serviceaccount:$ns:$nom" 2>/dev/null || true)" = yes ]; then
        echo "$ns:$nom $verbe"
      fi
    done
  done < "$T/comptes" | sort > "$T/modifient"
  echo "$(wc -l < "$T/comptes") comptes de service examinés ; accordés :"; sed 's/^/  /' "$T/modifient"
  printf '%s\n' "kube-system:generic-garbage-collector patch" "kube-system:generic-garbage-collector update" \
    "tekton-chains:tekton-chains-controller patch" "tekton-chains:tekton-chains-controller update" \
    "tekton-pipelines:tekton-pipelines-controller patch" "tekton-pipelines:tekton-pipelines-controller update" | cmp -s - "$T/modifient" \
    && echo "OK   seuls ces trois contrôleurs, parmi les comptes de service (plus les administrateurs du cluster)" \
    || echo "CONSTAT  liste différente de la prédiction (ci-dessus) : compte de service ajouté ou retiré"
  echo "## droits complets du compte build dans builds (kubectl auth can-i --list)"
  kubectl auth can-i --list -n builds --as=system:serviceaccount:builds:build | sed 's/^/  /'
  echo "## écritures du compte el-forgejo dans l'audit de l'API, depuis le dernier test 5 (lectures non journalisées)"
  debut=$(awk -F'\t' '$1 == "J6 essais_webhook" {d = $2} END {print d}' "$R/chrono.tsv")
  [ -n "$debut" ] || { echo "KO   test 5 de J6 absent de chrono.tsv" >&2; exit 1; }
  audit_api system:serviceaccount:declencheurs:el-forgejo \
    | jq -r --arg d "$debut" 'select(.stageTimestamp >= $d and .user.username == "system:serviceaccount:declencheurs:el-forgejo")
      | "\(.verb) \(.objectRef.resource)\(if .objectRef.subresource then "/" + .objectRef.subresource else "" end) \(.objectRef.namespace // "-") \(.responseStatus.code)"' \
    | sort | uniq -c | sed 's/^ */  /' | tee "$T/audit-el"
  [ -s "$T/audit-el" ] && ! grep -qE ' 403$' "$T/audit-el" && echo "OK   aucun refus (403) pour el-forgejo depuis $debut" \
    || { echo "KO   refus RBAC ou aucune écriture pour el-forgejo" >&2; exit 1; }
  echo "## écritures et refus du compte rattrapage dans l'audit de l'API, depuis la dernière étape rattrapage"
  debut=$(awk -F'\t' '$1 == "J6 rattrapage" {d = $2} END {print d}' "$R/chrono.tsv")
  [ -n "$debut" ] || { echo "KO   étape rattrapage absente de chrono.tsv" >&2; exit 1; }
  audit_api system:serviceaccount:declencheurs:rattrapage \
    | jq -r --arg d "$debut" 'select(.stageTimestamp >= $d and .user.username == "system:serviceaccount:declencheurs:rattrapage")
      | "\(.verb) \(.objectRef.resource)\(if .objectRef.subresource then "/" + .objectRef.subresource else "" end) \(.objectRef.namespace // "-") \(.responseStatus.code)"' \
    | sort | uniq -c | sed 's/^ */  /' | tee "$T/audit-rattrapage"
  [ -s "$T/audit-rattrapage" ] && ! grep -qE ' 403$' "$T/audit-rattrapage" && echo "OK   aucun refus (403) pour rattrapage depuis $debut" \
    || { echo "KO   refus RBAC ou aucune écriture pour rattrapage" >&2; exit 1; }
  echo "## journal de l'EventListener : refus de lecture (informateurs) depuis son déplacement"
  nom=$(kubectl get pods -n declencheurs -l eventlistener=forgejo -o jsonpath='{.items[0].metadata.name}')
  n=$(kubectl logs -n declencheurs "$nom" | grep -ci 'forbidden' || true)
  [ "$n" = 0 ] && echo "OK   aucun « forbidden » dans le journal de $nom" || { echo "KO   $n « forbidden » dans le journal de $nom" >&2; exit 1; }
}

lancer politique J6 "$@"
