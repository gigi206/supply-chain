#!/usr/bin/env bash
# Brique 08 : étape C de la validation du correctif Kyverno (plantage de ctlog.tsaCertChain), à l'admission.
# Décision C0 du propriétaire, option (a), « (i) passage borné » (09/11/2026) ; protocole et prédictions C7 à C13 dans
# resultats/kyverno-correctif-c-predictions.md (additifs de 13:18 et 13:39 UTC). Écrit à sec le 09/11/2026 vers 13:46 UTC :
# aucune étape n'a tourné à cette heure. Chaque étape qui touche Zot ou le cluster attend son propre accord.
#   construire  local : binaire ./cmd/kyverno du clone v1.19.2 portant le correctif v2, go1.26.9 et réglages du binaire
#               officiel (reproduit au bit près, kyverno-correctif-c-reproduction.log) ; couche ko-app/kyverno. Rien hors de l'hôte.
#   image       Zot : lecture anonyme du manifeste amd64 officiel, écriture de essais/kyverno-correctif par poc-ecriture
#               (crane append) ; contrôle de l'image poussée. poc-ecriture ne peut pas supprimer : l'image reste (accepté).
#   temoins     lecture seule du cluster et lecture anonyme de Zot : image en service, répliques, webhooks, politiques
#               d'images, espace bancc, CronJobs, dépôts de J5 et images du banc C (06/11). Rien écrit.
#   passage     cluster : CronJobs horodatage et rattrapage suspendus, espace bancc créé s'il manque, politiques d'essai
#               bornées par l'espace bancc et par l'image, image officielle (avant), bascule vers l'image corrigée, retour à
#               l'image officielle (après) ; pods présentés en dry-run serveur seulement ; tout est retiré et contrôlé.
# Usage (racine du dépôt) : poc/bricks/08-trust-plane/kyverno-admission.sh <étape>   (journal : resultats/kyverno-admission-<étape>.log)
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # images d'essai signées en J4
K=$O/kyverno-correctif
B=$K/bin
T=$W/kyverno-admission
PATCH=$here/kyverno-correctif/correctif-v2-final.patch
GO=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.26.9.linux-amd64
LDF="-s -w -X github.com/kyverno/kyverno/pkg/version.BuildVersion=v1.19.2"   # Makefile de v1.19.2 (LD_FLAGS avec VERSION)
OFF_INDEX=sha256:c8c4dd09e720d2cd7fd24ca73ac28e46651001372f988e0cba3f2f612f04b955   # politique.sh, KY_IMAGES
OFF_AMD64=sha256:6f0c520054d863a4a3df53ac7bb67d571d20421b77b99809013a62ec5f1d5947   # manifeste amd64 de l'index
OFF_BIN=7913082b95920ca27f3490a80c5fe63fc5b0b894d2aab5791e16b2a1f044f7b3            # binaire officiel /ko-app/kyverno
BIN=$B/kyverno-admission-v1.19.2-v2
DEPOT_ESSAI=essais/kyverno-correctif
TAG_ESSAI=v1.19.2-v2
REF_DIGEST=$R/kyverno-admission-image.digest   # digest de l'image corrigée, écrit par l'étape image
NS=bancc          # espace des pods d'essai (jamais créés : dry-run serveur)
NS_HORS=horodatage   # espace du témoin de bornage (pods jamais créés)
DEP=kyverno-admission-controller
MOTIF_OFF="${OFF_INDEX#sha256:}|${OFF_AMD64#sha256:}"
BANC_W=$W/politique/banc   # banc C préparé en J6 (06/11/2026) : clés de test, images.tsv, politique rendue
ETIQ=poc.test/essai=kyverno-admission
mkdir -p "$B" "$T"

go_env() { # chaîne go1.26.9, modules du cache hors ligne (même environnement que le témoin de reproduction)
  export GOROOT=$GO PATH=$GO/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPROXY=off GOSUMDB=off \
    GOMODCACHE=$K/gomodcache GOCACHE=$K/gocache GOPATH=$K/gopath GOENV=off GOTELEMETRY=off CGO_ENABLED=0
}

etape_construire() {
  local s
  ( go_env; cd "$K/v1.19.2" || exit 1
    [ "$(git rev-parse HEAD)" = e63308f1e16c05cd009ac4864be6ec25c66b49be ] && echo "OK   tête e63308f1e16c" || { echo "KO   tête $(git rev-parse HEAD)"; exit 1; }
    git apply -R --check "$PATCH" 2>/dev/null && echo "OK   correctif v2 présent (patch final applicable à l'envers)" || { echo "KO   correctif v2 absent ou différent"; exit 1; }
    echo "fichiers modifiés ou non suivis : $(git status --porcelain | wc -l) (arbre « sale », comme le binaire officiel)"
    go version
    go build -trimpath -ldflags "$LDF" -o "$BIN" ./cmd/kyverno && echo "OK   construit : $BIN" || exit 1
    go version -m "$BIN" | grep -E '^\S|mod\s+github.com/kyverno/kyverno|vcs\.(revision|modified)|-trimpath|CGO_ENABLED' ) || return 1
  s=$(sha256sum "$BIN" | cut -c1-64)
  echo "sha256 corrigé : $s"
  [ "$s" != "$OFF_BIN" ] && echo "OK   différent du binaire officiel ($OFF_BIN)" || { echo "KO   identique au binaire officiel : correctif absent du binaire"; return 1; }
  rm -rf "$T/couche" && mkdir -p "$T/couche/ko-app"
  cp "$BIN" "$T/couche/ko-app/kyverno"
  chmod 0555 "$T/couche/ko-app/kyverno" "$T/couche/ko-app"   # modes de la couche officielle (dr-xr-xr-x, -r-xr-xr-x, 0:0)
  tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -C "$T/couche" -cf "$T/couche.tar" ko-app
  chmod u+w "$T/couche/ko-app"
  tar -tvf "$T/couche.tar" | sed 's/^/  /'
  echo "sha256 couche (non compressée) : $(sha256sum < "$T/couche.tar" | cut -c1-64)"
  echo "bilan : OK"
}

etape_image() {
  local d m o
  [ -s "$T/couche.tar" ] && [ -x "$BIN" ] || { echo "NON JUGÉ : étape construire non faite"; exit 3; }
  mkdir -p "$T/auth/docker" && chmod 700 "$T/auth"
  trap 'rm -f "$T/auth/docker/config.json"' EXIT   # copie des identifiants de poc-ecriture, retirée à la sortie
  auth_zot "$T/auth/docker/config.json"   # poc-ecriture ; valeur jamais affichée
  export DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt
  echo "## base : $REG_HOTE/amont/kyverno/kyverno@$OFF_AMD64 (manifeste amd64 de l'index $OFF_INDEX)"
  crane manifest "$REG_HOTE/amont/kyverno/kyverno@$OFF_AMD64" > "$T/base.json" || { echo "NON JUGÉ : base illisible dans Zot"; exit 3; }
  [ "$(sha256sum < "$T/base.json" | cut -c1-64)" = "${OFF_AMD64#sha256:}" ] && echo "OK   manifeste de base lu, digest conforme" || { echo "KO   digest du manifeste de base"; exit 1; }
  echo "## envoi : $REG_HOTE/$DEPOT_ESSAI:$TAG_ESSAI (poc-ecriture)"
  crane append -b "$REG_HOTE/amont/kyverno/kyverno@$OFF_AMD64" -f "$T/couche.tar" -t "$REG_HOTE/$DEPOT_ESSAI:$TAG_ESSAI" > "$T/append.out" 2>&1 \
    || { echo "KO   crane append : $(tail -1 "$T/append.out" | cut -c1-200)"; exit 1; }
  d=$(crane digest "$REG_HOTE/$DEPOT_ESSAI:$TAG_ESSAI") || { echo "KO   digest de l'image poussée illisible"; exit 1; }
  echo "image corrigée : $REG/$DEPOT_ESSAI@$d"
  echo "## contrôles de l'image poussée"
  crane manifest "$REG_HOTE/$DEPOT_ESSAI@$d" > "$T/essai.json"
  m=$(jq -r '[.layers[].digest] | length' "$T/essai.json")
  [ "$m" = 4 ] && echo "OK   4 couches (3 officielles et la couche ajoutée)" || { echo "KO   $m couches"; exit 1; }
  o=$(jq -c '[.layers[0:3][].digest]' "$T/base.json")
  [ "$(jq -c '[.layers[0:3][].digest]' "$T/essai.json")" = "$o" ] && echo "OK   trois premières couches identiques à l'officielle (base, kodata, binaire officiel masqué)" \
    || { echo "KO   couches de base différentes"; exit 1; }
  crane config "$REG_HOTE/amont/kyverno/kyverno@$OFF_AMD64" | jq -S '.config | {Entrypoint, User, Env, WorkingDir}' > "$T/cfg-off.json"
  crane config "$REG_HOTE/$DEPOT_ESSAI@$d" | jq -S '.config | {Entrypoint, User, Env, WorkingDir}' > "$T/cfg-essai.json"
  diff -q "$T/cfg-off.json" "$T/cfg-essai.json" >/dev/null && echo "OK   point d'entrée, utilisateur, environnement identiques : $(jq -c '{Entrypoint, User}' "$T/cfg-essai.json")" \
    || { echo "KO   configuration différente"; diff "$T/cfg-off.json" "$T/cfg-essai.json"; exit 1; }
  crane blob "$REG_HOTE/$DEPOT_ESSAI@$(jq -r '.layers[3].digest' "$T/essai.json")" | tar -xzO ko-app/kyverno > "$T/bin-zot"
  [ "$(sha256sum < "$T/bin-zot" | cut -c1-64)" = "$(sha256sum < "$BIN" | cut -c1-64)" ] && echo "OK   binaire de la couche ajoutée identique au binaire construit" \
    || { echo "KO   binaire de la couche ajoutée différent"; exit 1; }
  echo "$d" > "$REF_DIGEST"
  echo "digest écrit dans $REF_DIGEST"
  echo "bilan : OK"
}

etape_temoins() {
  local d n r ko=0
  echo "## image en service du contrôleur d'admission (attendu : $REG/amont/kyverno/kyverno@$OFF_INDEX)"
  kubectl get deployment -n kyverno "$DEP" -o json > "$T/dep.json" || { echo "NON JUGÉ : Deployment $DEP illisible"; exit 3; }
  jq -r '"spec : \(.spec.template.spec.containers[] | select(.name == "kyverno") | .image) ; répliques \(.spec.replicas) ; stratégie \(.spec.strategy | tojson)"' "$T/dep.json"
  kubectl get pods -n kyverno -l app.kubernetes.io/component=admission-controller -o json \
    | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName) \(.status.phase) \([.status.containerStatuses[] | select(.name == "kyverno") | .imageID] | join(","))"'
  [ "$(kubectl get pods -n kyverno -l app.kubernetes.io/component=admission-controller -o name | wc -l)" -ge 1 ] \
    && echo "OK   étiquette app.kubernetes.io/component=admission-controller présente" || { echo "KO   aucun pod sous l'étiquette admission-controller"; ko=1; }
  echo "## PodDisruptionBudget de kyverno"
  kubectl get pdb -n kyverno -o custom-columns=NOM:.metadata.name,MIN:.spec.minAvailable,MAX:.spec.maxUnavailable,PERMIS:.status.disruptionsAllowed --no-headers
  echo "## webhooks de Kyverno (failurePolicy)"
  kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -o json \
    | jq -r '.items[] | select(.metadata.name | startswith("kyverno")) | "\(.kind) \(.metadata.name) : \([(.webhooks // [])[] | .failurePolicy] | unique | join(","))"'
  echo "## politiques d'images en service (attendu : aucune)"
  n=$(kubectl get imagevalidatingpolicies -o name 2>/dev/null | wc -l); echo "ImageValidatingPolicy : $n"
  echo "## espaces"
  if kubectl get ns "$NS" -o json > "$T/ns.json" 2>/dev/null; then
    jq -r '"\(.metadata.name) présent ; étiquettes pod-security : \(.metadata.labels | with_entries(select(.key | startswith("pod-security"))) | tojson)"' "$T/ns.json"
  else echo "$NS absent (sera créé puis retiré)"; fi
  kubectl get ns "$NS_HORS" -o json | jq -r '"\(.metadata.name) : étiquettes pod-security \(.metadata.labels | with_entries(select(.key | startswith("pod-security"))) | tojson)"'
  echo "## pods témoins en dry-run serveur, sans politique d'essai (un refus peut produire un Event PolicyViolation)"
  pod essai-pret "$NS_HORS" "$REG/builds/essai-signature@$APP_DIGEST" confiance > "$T/pret.yaml"
  r=$(admission "$T/pret.yaml" aucune); echo "$NS_HORS : ${r%%$'\t'*} ${r##*$'\t'}" | cut -c1-240; [ "${r%%$'\t'*}" = PASS ] || ko=1
  if kubectl get ns "$NS" >/dev/null 2>&1; then
    pod essai-j5 "$NS" "$REG/builds/essai-signature@$APP_DIGEST" > "$T/pod-j5.yaml"
    r=$(admission "$T/pod-j5.yaml" aucune); echo "$NS : ${r%%$'\t'*} ${r##*$'\t'}" | cut -c1-240; [ "${r%%$'\t'*}" = PASS ] || ko=1
  fi
  echo "## CronJobs suspendus par le passage"
  kubectl get cronjob -n horodatage horodatage -o jsonpath='horodatage : suspend={.spec.suspend} dernier={.status.lastScheduleTime}{"\n"}'
  kubectl get cronjob -n declencheurs rattrapage -o jsonpath='rattrapage : suspend={.spec.suspend} dernier={.status.lastScheduleTime}{"\n"}'
  echo "## Zot, lecture anonyme : dépôts de J5"
  for d in "$DEPOT_BUNDLES" essais-j5/sans-jeton essais-j5/jeton-altere essais-j5/autre-signature essais-j5/tsa-etrangere essais-j5/aucun; do
    n=$(curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$d/referrers/$APP_DIGEST" 2>/dev/null | jq '.manifests | length' 2>/dev/null) || n=illisible
    echo "$d : ${n:-illisible} referrer(s)"
    case "$d" in essais-j5/aucun) ;; *) [ "$n" != illisible ] && [ "${n:-0}" -ge 1 ] 2>/dev/null || ko=1 ;; esac
  done
  echo "## Zot, lecture anonyme : images du banc C (images.tsv du 06/11)"
  [ -s "$BANC_W/images.tsv" ] && [ -s "$BANC_W/ivpol.yaml" ] || { echo "KO   banc de J6 absent de $BANC_W"; ko=1; }
  while IFS=$'\t' read -r n _ r; do
    SSL_CERT_FILE=$P/ca-poc.crt crane digest "$r" >/dev/null 2>&1 && echo "OK   $n présent" || { echo "KO   $n absent de Zot"; ko=1; }
  done < "$BANC_W/images.tsv"
  echo "## image corrigée"
  [ -s "$REF_DIGEST" ] && { SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$DEPOT_ESSAI@$(cat "$REF_DIGEST")" >/dev/null 2>&1 \
    && echo "OK   $DEPOT_ESSAI@$(cut -c1-19 "$REF_DIGEST")… présente" || { echo "KO   image corrigée absente de Zot"; ko=1; }; } || echo "pas encore poussée"
  [ "$ko" = 0 ] && echo "bilan : OK" || echo "bilan : KO"
  return "$ko"
}

# --- passage ---------------------------------------------------------------------------------------------------------

garde_horaire() { # pas de passage près du scan (09:30 UTC) ni de la tâche de Zot du 21/11 (16:00 UTC) ; durée prévue < 30 min
  local h j
  h=$(date -u +%H%M); j=$(date -u +%Y-%m-%d)
  { [ "$h" -ge 0845 ] && [ "$h" -le 0950 ]; } && { echo "NON JUGÉ : garde horaire, trop près du scan de 09:30 UTC"; exit 3; }
  { [ "$j" = 2026-11-21 ] && [ "$h" -ge 1500 ] && [ "$h" -le 1630 ]; } && { echo "NON JUGÉ : garde horaire, tâche de Zot du 21/11"; exit 3; }
  echo "OK   garde horaire ($(date -u +%H:%M) UTC)"
}

pod() { # nom espace image [zone] : pod conforme à restricted et aux 4 règles de la 08c, jamais créé (dry-run serveur)
  cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $1, namespace: $2}
spec:
  automountServiceAccountToken: false
$([ -n "${4:-}" ] && printf '  nodeSelector: {zone: %s}\n' "$4")
  securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: app
      image: $3
      resources: {limits: {cpu: 50m, memory: 32Mi}, requests: {cpu: 50m, memory: 32Mi}}
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
EOF
}

ivpol_c() { # nom dépôt-des-bundles [chaîne-TSA] : politique du contrôle 9 de commun.sh, bornée à l'espace bancc et à
  # l'image d'essai, registre désigné par son nom (règle images-zot-par-digest) ; étiquetée pour le retrait
  ivpol "$2" "${3:-}" "$1" | python3 -I -c '
import sys
reg_hote, reg, ns, etiq, nom = sys.argv[1:6]
t = sys.stdin.read()
t = t.replace("    - glob: \"%s/*\"" % reg_hote, "    - glob: \"%s/builds/essai-signature*\"" % reg)
t = t.replace("repository: %s/" % reg_hote, "repository: %s/" % reg)
k, v = etiq.split("=")
t = t.replace("  name: %s\n" % nom, "  name: %s\n  labels: {%s: %s}\n" % (nom, k, v), 1)
t = t.replace("  matchConstraints:\n", "  matchConstraints:\n    namespaceSelector:\n      matchExpressions:\n      - {key: kubernetes.io/metadata.name, operator: In, values: [%s]}\n" % ns, 1)
assert reg_hote not in t, "adresse de l hôte restante"
sys.stdout.write(t)' "$REG_HOTE" "$REG" "$NS" "$ETIQ" "$1"
}

banc_pol() { # politique du banc C rendue en J6, bornée à bancc, images désignées par le nom du registre
  python3 -I -c '
import sys
reg_hote, reg, ns, etiq, src = sys.argv[1:6]
t = open(src).read()
assert t.count("glob: \"%s/bench/*\"" % reg_hote) == 1
t = t.replace("glob: \"%s/bench/*\"" % reg_hote, "glob: \"%s/bench/*\"" % reg)
k, v = etiq.split("=")
t = t.replace("  name: bench-release\n", "  name: bench-release\n  labels: {%s: %s}\n" % (k, v), 1)
t = t.replace("  matchConstraints:\n", "  matchConstraints:\n    namespaceSelector:\n      matchExpressions:\n      - {key: kubernetes.io/metadata.name, operator: In, values: [%s]}\n" % ns, 1)
assert reg_hote not in t
sys.stdout.write(t)' "$REG_HOTE" "$REG" "$NS" "$ETIQ" "$BANC_W/ivpol.yaml"
}

charger() { # fichier nom : politique d'images prête, puis 2 s pour la configuration des webhooks (politique.sh)
  local i
  kubectl apply -f "$1" < /dev/null >/dev/null || return 1
  for i in $(seq 60); do
    [ "$(kubectl get imagevalidatingpolicy "$2" -o jsonpath='{.status.conditionStatus.ready}' 2>/dev/null)" = true ] && break
    sleep 1
  done
  [ "$i" -lt 60 ] || { echo "KO   politique $2 jamais prête"; return 1; }
  sleep 2
}

admission() { # fichier politique : PASS (admis), FAIL (refus attribué à cette politique), AUTRE (refus d'une autre règle),
  # INATTRIBUÉ (refus du webhook sans motif reconnaissable : forme du message d'une erreur interne jamais relue), ERREUR ;
  # puis « interne » si le motif porte une erreur interne ; puis le motif
  local m i=non
  if kubectl create --dry-run=server -f "$1" < /dev/null > "$T/adm.out" 2>&1; then printf 'PASS\tnon\t\n'; return; fi
  m=$(tr '\n' ' ' < "$T/adm.out" | sed 's/^Error from server\( ([A-Za-z]*)\)\{0,1\}: //' | cut -c1-300)
  grep -qiE 'internal error|nil pointer|panic' "$T/adm.out" && i=oui
  # Attribution : AUTRE si un motif des autres règles apparaît (« durcissement : » de la 08c, « zone … : » de J6, Pod Security) ;
  # FAIL si le message cite la politique d'essai (son nom, ou l'un de ses messages « C9 : », « C1 : »…) ; sinon INATTRIBUÉ.
  if grep -q 'denied the request' "$T/adm.out"; then
    if grep -qE 'durcissement :|zone (build|confiance) :|violates PodSecurity' "$T/adm.out"; then printf 'AUTRE\t%s\t%s\n' "$i" "$m"
    elif grep -qF "$2" "$T/adm.out" || grep -qE '\<C[0-9]+ : ' "$T/adm.out"; then printf 'FAIL\t%s\t%s\n' "$i" "$m"
    else printf 'INATTRIBUÉ\t%s\t%s\n' "$i" "$m"; fi
  else printf 'ERREUR\t%s\t%s\n' "$i" "$m"; fi
}

hors_bancc() { # image politique : le même pod hors de bancc reste admis (bornage de la politique, C8)
  local r
  pod essai-hors-bancc "$NS_HORS" "$1" confiance > "$T/hors.yaml"
  r=$(admission "$T/hors.yaml" "$2")
  [ "${r%%$'\t'*}" = PASS ] || { echo "KO   bornage : pod hors de $NS refusé avec la politique $2 chargée (${r##*$'\t'}) ; arrêt, retrait par le trap"; exit 1; }
}

# cas|dépôt des bundles|chaîne TSA|attendu image officielle|attendu image corrigée (C9 à C11)
cas_j5() {
  printf '%s\n' "j5-temoin|$DEPOT_BUNDLES||PASS|PASS" "j5-jeton-valide|$DEPOT_BUNDLES|$P/tsa-chaine.pem|FAIL|PASS" \
    "j5-sans-jeton|essais-j5/sans-jeton|$P/tsa-chaine.pem|FAIL|FAIL" "j5-aucun-bundle|essais-j5/aucun|$P/tsa-chaine.pem|FAIL|FAIL" \
    "j5-jeton-altere|essais-j5/jeton-altere|$P/tsa-chaine.pem|FAIL|FAIL" "j5-autre-signature|essais-j5/autre-signature|$P/tsa-chaine.pem|FAIL|FAIL" \
    "j5-tsa-etrangere|essais-j5/tsa-etrangere|$P/tsa-chaine.pem|FAIL|FAIL" "j5-att-historique|||FAIL|FAIL"
}

juger() { # phase cas attendu décision interne motif : OK, CONSTAT (refus INATTRIBUÉ, attendu FAIL : affiché, non jugé) ou KO ;
  # avec l'image corrigée, une erreur interne est KO (C11) ; avec l'image officielle, elle est affichée (C9, non jugée)
  local ph=$1 c=$2 e=$3 d=$4 i=$5 m=$6
  if [ "$d" = "$e" ] && { [ "$ph" != corrigee ] || [ "$i" = non ]; }; then echo "OK   $c : $d (attendu $e) ; erreur interne : $i"
  elif [ "$d" = INATTRIBUÉ ] && [ "$e" = FAIL ] && { [ "$ph" != corrigee ] || [ "$i" = non ]; }; then
    echo "CONSTAT $c : refus du webhook non attribué (attendu FAIL) ; erreur interne : $i ; ${m:0:200}"
  else echo "KO   $c : $d, attendu $e ; erreur interne : $i ; ${m:0:200}"; return 1; fi
}

serie() { # phase (avant|corrigee|apres) : 8 cas j5 et 17 cas du banc ; une ligne par cas dans $TSV ; KO si décision ≠ attendu
  local ph=$1 c r v e1 e2 e a d i m ko=0 n img
  img=$REG/builds/essai-signature@$APP_DIGEST
  pod essai-j5 "$NS" "$img" > "$T/pod-j5.yaml"
  echo "## $ph : 8 cas j5"
  while IFS='|' read -r c r v e1 e2; do
    e=$([ "$ph" = corrigee ] && echo "$e2" || echo "$e1")
    ivpol_c "$c" "$r" "$v" > "$T/$c.yaml"
    charger "$T/$c.yaml" "$c" || { echo "KO   politique $c non chargée : arrêt"; exit 1; }
    hors_bancc "$img" "$c"
    a=$(admission "$T/pod-j5.yaml" "$c")
    printf '%s\t%s\t%s\t%s\n' "$ph" "$c" "$e" "$a" >> "$TSV"
    IFS=$'\t' read -r d i m <<< "$a"
    juger "$ph" "$c" "$e" "$d" "$i" "$m" || ko=1
    kubectl delete imagevalidatingpolicy "$c" --wait=true < /dev/null >/dev/null
  done < <(cas_j5)
  echo "## $ph : 17 cas du banc C"
  banc_pol > "$T/banc.yaml"
  charger "$T/banc.yaml" bench-release || { echo "KO   politique bench-release non chargée : arrêt"; exit 1; }
  r=$(awk -F'\t' '$1 == "c1-unsigned" {print $3}' "$BANC_W/images.tsv")
  hors_bancc "${r/$REG_HOTE/$REG}" bench-release   # témoin de bornage sur un cas refusé dans bancc
  while IFS=$'\t' read -r c e r; do
    r=${r/$REG_HOTE/$REG}
    pod "$c" "$NS" "$r" > "$T/pod-$c.yaml"
    a=$(admission "$T/pod-$c.yaml" bench-release)
    printf '%s\t%s\t%s\t%s\n' "$ph" "$c" "$e" "$a" >> "$TSV"
    IFS=$'\t' read -r d i m <<< "$a"
    juger "$ph" "$c" "$e" "$d" "$i" "$m" || ko=1
  done < "$BANC_W/images.tsv"
  kubectl delete imagevalidatingpolicy bench-release --wait=true >/dev/null
  return "$ko"
}

pret() { # référence motif : déploiement terminé, au moins un pod et chacun sur une image dont le digest correspond au motif
  # (l'imageID d'une image officielle tirée par index peut porter l'index ou le manifeste amd64 : non relu), webhook à l'écoute
  # (le pod témoin admis ne prouve pas que le webhook de Kyverno évalue : la preuve est le premier refus attribué de la série)
  local i ref=$1 motif=$2
  kubectl rollout status -n kyverno "deployment/$DEP" --timeout=300s || return 1
  kubectl get pods -n kyverno -l app.kubernetes.io/component=admission-controller -o json \
    | jq -r '.items[] | select(.metadata.deletionTimestamp == null) | "\(.metadata.name) \([.status.containerStatuses[] | select(.name == "kyverno") | .imageID] | join(","))"' > "$T/ids"
  sed 's/^/  /' "$T/ids"
  [ -s "$T/ids" ] && awk -v d="$motif" '$2 !~ d {k = 1} END {exit k}' "$T/ids" && echo "OK   tous les pods sur ${ref##*@}" \
    || { echo "KO   aucun pod, ou pod sur une autre image"; return 1; }
  pod essai-pret "$NS_HORS" "$REG/builds/essai-signature@$APP_DIGEST" confiance > "$T/pret.yaml"
  for i in $(seq 60); do kubectl create --dry-run=server -f "$T/pret.yaml" < /dev/null >/dev/null 2>&1 && break; sleep 2; done
  [ "$i" -lt 60 ] && echo "OK   webhook à l'écoute ($((2 * (i - 1))) s)" || { echo "KO   webhook muet"; return 1; }
}

bascule() { # référence motif
  echo "## bascule : $1 ($(date -u +%H:%M:%S) UTC)"
  kubectl set image -n kyverno "deployment/$DEP" "kyverno=$1" >/dev/null || return 1
  pret "$1" "$2"
}

nettoyer() { # retrait de tout ce que le passage a posé ; image officielle remise si besoin ; CronJobs repris
  local c
  echo "## retrait ($(date -u +%H:%M:%S) UTC)"
  kubectl delete imagevalidatingpolicy -l "$ETIQ" --wait=true --ignore-not-found
  c=$(kubectl get deployment -n kyverno "$DEP" -o jsonpath='{.spec.template.spec.containers[?(@.name=="kyverno")].image}')
  [ "$c" = "$REF_OFF" ] || { echo "image en service $c : retour à $REF_OFF"; kubectl set image -n kyverno "deployment/$DEP" "kyverno=$REF_OFF" >/dev/null; pret "$REF_OFF" "$MOTIF_OFF"; }
  [ "$NS_CREE" = oui ] && kubectl delete ns "$NS" --wait=true --timeout=120s
  kubectl patch cronjob -n horodatage horodatage --type merge -p '{"spec":{"suspend":false}}' >/dev/null
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":false}}' >/dev/null
  echo "CronJobs repris"
}

passage_cron() { # espace CronJob instant : un Job créé après l'instant, terminé avec succès (attente 180 s)
  local i j
  for i in $(seq 90); do
    j=$(kubectl get jobs -n "$1" -o json | jq -r --arg c "$2" --arg t "$3" '[.items[] | select(.metadata.ownerReferences[0].name == $c
      and .metadata.creationTimestamp > $t and (.status.succeeded // 0) >= 1)] | .[0].metadata.name // empty')
    [ -n "$j" ] && { echo "OK   $2 : $j réussi"; return 0; }
    sleep 2
  done
  echo "KO   $2 : aucun passage réussi en 180 s"; return 1
}

etape_passage() {
  local d t0 t1 ko=0 n
  garde_horaire
  [ -s "$REF_DIGEST" ] || { echo "NON JUGÉ : étape image non faite"; exit 3; }
  [ -s "$R/kyverno-admission-temoins.log" ] && grep -q '^bilan : OK' "$R/kyverno-admission-temoins.log" || { echo "NON JUGÉ : témoins non faits ou KO"; exit 3; }
  d=$(cat "$REF_DIGEST")
  REF_ESSAI=$REG/$DEPOT_ESSAI@$d
  REF_OFF=$(kubectl get deployment -n kyverno "$DEP" -o jsonpath='{.spec.template.spec.containers[?(@.name=="kyverno")].image}')
  [ "$REF_OFF" = "$REG/amont/kyverno/kyverno@$OFF_INDEX" ] && echo "OK   image en service officielle : $REF_OFF" || { echo "NON JUGÉ : image en service $REF_OFF"; exit 3; }
  n=$(kubectl get imagevalidatingpolicies -o name | wc -l)
  [ "$n" = 0 ] || { echo "NON JUGÉ : $n politique(s) d'images déjà présente(s)"; exit 3; }
  NS_CREE=non
  TSV=$R/kyverno-admission-passage.tsv
  printf 'phase\tcas\tattendu\tadmission\terreur interne\tmotif\n' > "$TSV"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "## suspension de horodatage et rattrapage ($t0)"
  kubectl patch cronjob -n horodatage horodatage --type merge -p '{"spec":{"suspend":true}}' >/dev/null
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":true}}' >/dev/null
  trap nettoyer EXIT
  trap 'echo "interrompu : retrait"; exit 1' INT TERM HUP
  kubectl get ns "$NS" >/dev/null 2>&1 || { kubectl create ns "$NS" >/dev/null && NS_CREE=oui && attendre_sa "$NS"; echo "$NS créé"; }
  serie avant || ko=1
  # Avant toute bascule : j5-temoin admis, j5-sans-jeton refusé et attribué (Kyverno lit Zot et juge), bornage tenu (sinon déjà arrêté).
  awk -F'\t' '$1 == "avant" && $2 == "j5-temoin" && $4 == "PASS" {a = 1} $1 == "avant" && $2 == "j5-sans-jeton" && $4 == "FAIL" {b = 1}
    END {exit !(a && b)}' "$TSV" && echo "OK   condition de bascule : j5-temoin admis, j5-sans-jeton refusé et attribué" \
    || { echo "KO   condition de bascule non remplie : arrêt sans bascule, retrait par le trap"; exit 1; }
  bascule "$REF_ESSAI" "${d#sha256:}" || { echo "KO   bascule vers l'image corrigée"; exit 1; }
  serie corrigee || ko=1
  bascule "$REF_OFF" "$MOTIF_OFF" || { echo "KO   retour à l'image officielle"; exit 1; }
  serie apres || ko=1
  echo "## C13 : retour identique à avant"
  diff <(awk -F'\t' '$1 == "avant" {print $2, $4}' "$TSV") <(awk -F'\t' '$1 == "apres" {print $2, $4}' "$TSV") >/dev/null \
    && echo "OK   décisions après le retour identiques à celles d'avant" || { echo "KO   décisions différentes après le retour"; ko=1; }
  t1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  trap - EXIT INT TERM HUP
  nettoyer
  echo "## contrôle du retrait"
  n=$(kubectl get imagevalidatingpolicies -o name | wc -l); [ "$n" = 0 ] && echo "OK   aucune politique d'images" || { echo "KO   $n politique(s) restante(s)"; ko=1; }
  [ "$NS_CREE" = non ] || { kubectl get ns "$NS" >/dev/null 2>&1 && { echo "KO   $NS toujours présent"; ko=1; } || echo "OK   $NS retiré"; }
  echo "## C12 : créations refusées pendant le passage ($t0 à $t1)"
  n=$(kubectl get events -A --field-selector reason=FailedCreate -o json | jq --arg a "$t0" '[.items[] | select(((.lastTimestamp // .eventTime)[0:19]) >= ($a[0:19]))] | length')
  [ "$n" = 0 ] && echo "OK   0 FailedCreate" || { echo "KO   $n FailedCreate"; ko=1; }
  echo "## reprise : un passage réussi de chaque CronJob"
  passage_cron horodatage horodatage "$t1" || ko=1
  passage_cron declencheurs rattrapage "$t1" || ko=1
  [ "$ko" = 0 ] && echo "bilan : OK" || echo "bilan : KO"
  return "$ko"
}

e=${1:?usage : $0 construire|image|temoins|passage}
L=$R/kyverno-admission-$e.log
[ ! -e "$L" ] || { echo "$L existe déjà, rien lancé"; exit 2; }
{ date -u "+# kyverno-admission.sh $e, %Y-%m-%dT%H:%M:%SZ"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$L"
exit "${PIPESTATUS[0]}"
