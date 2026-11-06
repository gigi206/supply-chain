#!/usr/bin/env bash
# Brique 08c : jalon S1, décision du propriétaire du 05/11/2026 (« Oui, valide S1 »). Après H4, avant H5. Une étape à la fois.
#   verifier    à sec : sources de l'hôte (noms et droits), scripts rendus avec des valeurs témoins, correctif de Chains joué en local, aller
#               et retour, puis en dry-run serveur ; ne change rien, ne lit aucune valeur
#   s1_source   valeurs, politique chains-zot et rôle chains-zot dans OpenBao, relecture comparée sans affichage, témoins de refus (accord)
#   s1_chains   zot-chains injecté dans le contrôleur par le conteneur d'initialisation, Secret supprimé (accord)
#   s1_copies   zot-images, zot-fermetures et forgejo-webhook recréés depuis OpenBao, valeurs comparées sans affichage (accord)
#   s1_retrait  retour au Secret zot-chains, en cas d'échec (accord)
#
# Aucune valeur en argument ni à l'écran : mots de passe de l'hôte, corps de script sur l'entrée standard, fichiers 0600 effacés par un trap.
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/08c-durcissement/secrets.sh <étape>…   (journal : resultats/secrets-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
b08=$here/../08-trust-plane
. "$b08/commun.sh"
C=$here/config
R=$here/resultats
T=$W/secrets
NS=tekton-chains
DEP=tekton-chains-controller
SUJET=system:serviceaccount:$NS:$DEP
ko=0
mkdir -p "$T" "$R"

# Créé ici et non dans une étape : chaque étape tourne dans le sous-shell du pipeline de journal, dont le trap ne verrait pas ce répertoire.
V=$(umask 077 && mktemp -d "$T/v.XXXXXX")
nettoyer() { rm -rf -- "${V:?}"; }
trap nettoyer EXIT
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }
exige_rke2() { [ "$DISTRO" = rke2 ] || { echo "KO   étape réservée à DISTRO=rke2" >&2; exit 1; }; }

image_bao() { sed -n 's/^BAO_INDEX=\(sha256:[0-9a-f]*\).*/\1/p' "$b08/politique.sh"; }
rendre_injecte() { sed "s#@BAO@#$REG/amont/openbao/openbao@$(image_bao)#" "$C/chains-zot-injecte.yaml"; }

sources() { # répertoire 0700 : valeurs rebâties depuis les fichiers 0600 de l'hôte
  auth_zot "$1/chains.json" "" poc-build "$REG"
  auth_zot "$1/images.json" "" poc-images "$REG"
  auth_zot "$1/fermetures.json" "" poc-fermetures "$REG"
  install -m 0600 "$S/forgejo-webhook.secret" "$1/webhook"
}

script_source() { # répertoire des valeurs : script pour racine, valeurs dans le corps (entrée standard de kubectl exec), jamais en argument
  # Le secret du webhook sans fin de ligne : il entre dans le HMAC.
  cat <<EOF
set -eu
bao secrets list -format=json | grep -q '"kv/"'
bao write kv/tekton-chains/zot config.json=- >&2 <<'JSON'
$(cat "$1/chains.json")
JSON
bao write kv/builds/zot-images config.json=- >&2 <<'JSON'
$(cat "$1/images.json")
JSON
bao write kv/builds/zot-fermetures config.json=- >&2 <<'JSON'
$(cat "$1/fermetures.json")
JSON
printf %s '$(cat "$1/webhook")' | bao write kv/declencheurs/forgejo-webhook secret=- >&2
bao policy write chains-zot - >&2 <<'POL'
$(cat "$C/chains-zot.hcl")
POL
bao write auth/jwt/role/chains-zot role_type=jwt user_claim=sub bound_audiences=openbao \
  bound_subject=$SUJET token_policies=chains-zot token_no_default_policy=true \
  token_type=service token_ttl=1m token_max_ttl=1m >&2
bao read -format=json auth/jwt/role/chains-zot
EOF
}

script_temoins() { # jeton de la politique seule, émis par la racine : ce qu'elle permet et ce qu'elle refuse. Sorties jetées, seul le verdict s'affiche.
  cat <<'EOF'
set -u
BAO_TOKEN=$(bao token create -field=token -no-default-policy -policy=chains-zot -ttl=1m)
export BAO_TOKEN
essai() { l=$1; shift; if "$@" >/dev/null 2>&1; then echo "ACCEPTE|$l"; else echo "REFUSE|$l"; fi; }
essai "lecture de kv/tekton-chains/zot" bao read -field=config.json kv/tekton-chains/zot
essai "lecture de kv/horodatage/zot" bao read -field=config.json kv/horodatage/zot
essai "lecture de kv/builds/zot-images" bao read -field=config.json kv/builds/zot-images
essai "lecture de kv/declencheurs/forgejo-webhook" bao read -field=secret kv/declencheurs/forgejo-webhook
essai "écriture de kv/tekton-chains/zot" bao write kv/tekton-chains/zot config.json=x
essai "lecture de transit/keys/chains" bao read transit/keys/chains
essai "signature par transit/sign/chains" bao write transit/sign/chains input=eA==
essai "révocation de son propre jeton" bao token revoke -self
essai "lecture après révocation" bao read -field=config.json kv/tekton-chains/zot
EOF
}

lire() { racine <<<"bao read -field=$2 $1" > "$3"; }   # chemin clé fichier

meme_json() { cmp -s <(jq -cS . "$1") <(jq -cS . "$2"); }

etape_verifier() {
  local v f n d m
  echo "## sources de l'hôte : noms et droits, jamais les valeurs"
  for f in zot-poc-build.password zot-poc-images.password zot-poc-fermetures.password forgejo-webhook.secret; do
    m=$(stat -c %a "$S/$f" 2>/dev/null || echo absent)
    [ -s "$S/$f" ] || m=vide
    attendu "$f" "$m" 600
  done

  echo "## scripts pour OpenBao, rendus avec des valeurs témoins : syntaxe"
  v=$V
  for f in chains images fermetures; do printf '{"auths":{"%s":{"auth":"dGVtb2lu"}}}\n' "$REG" > "$v/$f.json"; done
  printf temoin > "$v/webhook"
  script_source "$v" > "$v/source.sh"
  script_temoins > "$v/temoins.sh"
  for f in source temoins; do if sh -n "$v/$f.sh"; then echo "OK   $f.sh : syntaxe"; else echo "KO   $f.sh"; ko=1; fi; done
  attendu "chemins de la politique" "$(sed -n 's/^path "\(.*\)" {$/\1/p' "$C/chains-zot.hcl" | paste -sd' ')" "kv/tekton-chains/zot auth/token/revoke-self"

  echo "## valeur du webhook par l'entrée standard, sans fichier sur disque : kubectl lit bien /dev/stdin (client seulement)"
  attendu "from-file sur /dev/stdin" "$(printf temoin | kubectl create secret generic x --from-file=k=/dev/stdin --dry-run=client -o json | jq -r .data.k)" "$(printf temoin | base64)"

  echo "## correctif de Chains, joué en local : aller, puis retour"
  rendre_injecte > "$T/injecte.yaml"
  grep -q '@BAO@' "$T/injecte.yaml" && { echo "KO   image non rendue"; ko=1; }
  attendu "image d'OpenBao par digest" "$(grep -c "image: $REG/amont/openbao/openbao@sha256:[0-9a-f]\{64\}$" "$T/injecte.yaml")" 1
  kubectl get deployment -n "$NS" "$DEP" -o json | jq 'del(.metadata.managedFields, .metadata.resourceVersion, .metadata.uid, .metadata.generation, .metadata.creationTimestamp, .status)' > "$T/avant.json"
  kubectl patch -f "$T/avant.json" --local --type strategic --patch-file "$T/injecte.yaml" -o json > "$T/apres.json"
  jq -c '.spec.template.spec as $s | {init: [$s.initContainers[].name], volume: ($s.volumes[] | select(.name == "zot-chains")), montage: ($s.containers[0].volumeMounts[] | select(.name == "zot-chains")), DOCKER_CONFIG: ($s.containers[0].env[] | select(.name == "DOCKER_CONFIG") | .value)}' "$T/apres.json"
  attendu "volume zot-chains sans Secret" "$(jq -r '.spec.template.spec.volumes[] | select(.name == "zot-chains") | "\(has("secret")) \(.emptyDir.medium)"' "$T/apres.json")" "false Memory"
  attendu "conteneur principal inchangé" "$(jq -cS '.spec.template.spec.containers' "$T/apres.json" | sha256sum | cut -c1-16)" "$(jq -cS '.spec.template.spec.containers' "$T/avant.json" | sha256sum | cut -c1-16)"
  kubectl patch -f "$T/apres.json" --local --type strategic --patch-file "$C/chains-zot-retrait.yaml" -o json > "$T/retour.json"
  attendu "retour : volumes identiques à l'avant" "$(jq -cS '.spec.template.spec.volumes | map(del(.secret.defaultMode))' "$T/retour.json" | sha256sum | cut -c1-16)" "$(jq -cS '.spec.template.spec.volumes | map(del(.secret.defaultMode))' "$T/avant.json" | sha256sum | cut -c1-16)"
  attendu "retour : aucun conteneur d'initialisation" "$(jq -c '.spec.template.spec.initContainers // [] | length' "$T/retour.json")" 0

  echo "## API en service, dry-run serveur : rien n'est créé"
  if kubectl patch deployment -n "$NS" "$DEP" --type strategic --patch-file "$T/injecte.yaml" --dry-run=server -o json > "$T/serveur.json" 2> "$T/serveur.err"; then
    attendu "correctif admis, image du conteneur d'initialisation" "$(jq -r '.spec.template.spec.initContainers[0].image' "$T/serveur.json" | sed 's/@.*//')" "$REG/amont/openbao/openbao"
  else echo "KO   correctif : $(tail -1 "$T/serveur.err")"; ko=1; fi
  for n in avant apres; do
    jq '{apiVersion: "v1", kind: "Pod", metadata: {generateName: "essai-s1-", namespace: .metadata.namespace, labels: .spec.template.metadata.labels}, spec: .spec.template.spec}' "$T/$n.json" > "$T/pod-$n.json"
    if kubectl create --dry-run=server -f "$T/pod-$n.json" > "$T/pod-$n.out" 2>&1; then echo "OK   pod $n : admis"
    else echo "KO   pod $n : $(tail -1 "$T/pod-$n.out" | cut -c1-260)"; ko=1; fi
  done

  echo "## politique.sh chains rejoué sur Chains injecté : un volume à deux sources, refus attendu de l'API"
  kubectl patch -f "$T/apres.json" --local --type strategic --patch-file "$b08/politique/chains-zot.yaml" -o json \
    | jq '{apiVersion: "v1", kind: "Pod", metadata: {generateName: "essai-s1-", namespace: .metadata.namespace, labels: .spec.template.metadata.labels}, spec: .spec.template.spec}' > "$T/pod-rejoue.json"
  if kubectl create --dry-run=server -f "$T/pod-rejoue.json" > "$T/pod-rejoue.out" 2>&1; then echo "KO   volume à deux sources admis"; ko=1
  else echo "OK   refusé :$(grep -m1 "volume type" "$T/pod-rejoue.out" | cut -c2-200)"; fi

  echo "## règle images-zot-par-digest de la 08c, CLI Kyverno (les limites du conteneur principal relèvent de H2)"
  kyverno apply "$here/politiques/kyverno/durcissement.yaml" --resource "$T/pod-apres.json" --policy-report --output-format json > "$T/cli.json" 2> "$T/cli.err" || true
  attendu "images-zot-par-digest" "$(jq -c '[.results[]? // .[]?.results[]? | select(.policy == "images-zot-par-digest") | .result] | unique' "$T/cli.json")" '["pass"]'

  echo "## Secrets en service comparés aux sources de l'hôte, sans affichage : ce que S1 écrira est ce que le cluster utilise déjà"
  mkdir -m 700 "$V/s"
  sources "$V/s"
  for f in tekton-chains/zot-chains:config.json:chains.json builds/zot-images:config.json:images.json builds/zot-fermetures:config.json:fermetures.json declencheurs/forgejo-webhook:secret:webhook; do
    IFS=: read -r d n m <<<"$f"
    kubectl get secret -n "${d%%/*}" "${d##*/}" -o json | jq -r --arg k "$n" '.data[$k]' | base64 -d > "$V/s/lu"
    case "$m" in
      *.json) meme_json "$V/s/lu" "$V/s/$m";;
      *) cmp -s "$V/s/lu" "$V/s/$m";;
    esac && echo "OK   $d : identique à la source" || { echo "KO   $d : différent de la source"; ko=1; }
  done
  attendu "fin de ligne du secret du webhook" "$(tail -c1 "$V/s/webhook" | wc -l)" 0

  echo "## OpenBao en service, lecture : kv actif, rôle et chemins absents"
  d=$(racine <<<'bao secrets list -format=json | grep -c "\"kv/\"" ; bao list -format=json auth/jwt/role ; bao list -format=json kv/' | tr -d ' \n')
  echo "$d" | cut -c1-300
  case "$d" in 1\[*) echo "OK   kv/ actif";; *) echo "KO   kv/ absent"; ko=1;; esac
  case "$d" in *chains-zot*) echo "KO   rôle chains-zot déjà présent"; ko=1;; *) echo "OK   rôle chains-zot absent";; esac
  [ "$ko" = 0 ] || { echo "KO   verifier" >&2; exit 1; }
  echo "RÉSULTAT : conforme"
}

etape_s1_source() {
  local f u
  exige_rke2
  sources "$V"
  echo "## écriture dans OpenBao : valeurs, politique, rôle"
  script_source "$V" | racine | jq -c '.data | {bound_audiences, bound_subject, user_claim, token_policies, token_no_default_policy, token_type, token_ttl, token_max_ttl}'
  echo "## relecture comparée aux sources, sans affichage"
  for f in tekton-chains/zot:chains builds/zot-images:images builds/zot-fermetures:fermetures; do
    lire "kv/${f%%:*}" config.json "$V/lu"
    if meme_json "$V/lu" "$V/${f##*:}.json"; then echo "OK   kv/${f%%:*} : identique à la source"; else echo "KO   kv/${f%%:*}"; ko=1; fi
  done
  lire kv/declencheurs/forgejo-webhook secret "$V/lu"
  if cmp -s "$V/lu" "$V/webhook"; then echo "OK   kv/declencheurs/forgejo-webhook : identique octet pour octet"; else echo "KO   kv/declencheurs/forgejo-webhook"; ko=1; fi
  echo "## témoins : un jeton de la politique seule"
  script_temoins | racine | tee "$T/temoins.txt"
  printf '%s\n' 'ACCEPTE|lecture de kv/tekton-chains/zot' 'REFUSE|lecture de kv/horodatage/zot' 'REFUSE|lecture de kv/builds/zot-images' \
    'REFUSE|lecture de kv/declencheurs/forgejo-webhook' 'REFUSE|écriture de kv/tekton-chains/zot' 'REFUSE|lecture de transit/keys/chains' \
    'REFUSE|signature par transit/sign/chains' 'ACCEPTE|révocation de son propre jeton' 'REFUSE|lecture après révocation' > "$T/temoins-attendus.txt"
  if cmp -s "$T/temoins.txt" "$T/temoins-attendus.txt"; then echo "OK   témoins conformes"; else echo "KO   témoins"; ko=1; fi
  echo "## témoin : rôle refusé à un autre compte (bound_subject)"
  # Jeton court d'un autre compte, jamais en argument : il passe par le corps du script.
  u=$(kubectl create token horodatage -n horodatage --audience openbao --duration 10m)
  if printf 'printf %%s "%s" | bao write auth/jwt/login role=chains-zot jwt=- >/dev/null 2>&1\n' "$u" | racine; then echo "KO   connexion acceptée"; ko=1; else echo "OK   connexion refusée au compte horodatage"; fi
  [ "$ko" = 0 ] || exit 1
}

etape_s1_chains() {
  exige_rke2
  rendre_injecte > "$T/injecte.yaml"
  kubectl patch deployment -n "$NS" "$DEP" --type strategic --patch-file "$T/injecte.yaml" >/dev/null
  kubectl rollout status -n "$NS" "deploy/$DEP" --timeout=180s
  # Pas deploy/$DEP : l'ancien pod encore en Terminating serait choisi, sans ce conteneur (premier passage du 06/11).
  kubectl logs -n "$NS" "$(kubectl get pods -n "$NS" -o json | jq -r '.items[] | select(.metadata.deletionTimestamp == null and any(.spec.initContainers[]?; .name == "identifiants")) | .metadata.name')" -c identifiants
  kubectl delete secret -n "$NS" zot-chains --ignore-not-found >/dev/null
  attendu "Secret zot-chains" "$(kubectl get secret -n "$NS" zot-chains -o name --ignore-not-found | wc -l)" 0
  attendu "volumes Secret du contrôleur" "$(kubectl get deploy -n "$NS" "$DEP" -o json | jq -c '[.spec.template.spec.volumes[] | select(.secret) | .secret.secretName]')" '["signing-secrets"]'
  echo "preuve fonctionnelle : .sig et .att écrits par le prochain passage, puis les 8 tests et la porte du seuil de la brique"
  [ "$ko" = 0 ] || exit 1
}

copie() { # espace nom clé chemin-kv fichier-source
  lire "$4" "$3" "$V/lu"
  [ -s "$V/lu" ] || { echo "KO   $4 : vide" >&2; exit 1; }
  case "$5" in
    *.json) meme_json "$V/lu" "$5";;
    *) cmp -s "$V/lu" "$5";;
  esac || { echo "KO   $4 : différent de la source, Secret non modifié" >&2; exit 1; }
  kubectl create secret generic "$2" -n "$1" --from-file="$3=$V/lu" --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  if kubectl get secret -n "$1" "$2" -o json | jq -r --arg k "$3" '.data[$k]' | base64 -d | cmp -s - "$V/lu"; then echo "OK   $1/$2 : recréé depuis $4, contenu vérifié"
  else echo "KO   $1/$2"; ko=1; fi
}

etape_s1_copies() {
  exige_rke2
  sources "$V"
  copie builds zot-images config.json kv/builds/zot-images "$V/images.json"
  copie builds zot-fermetures config.json kv/builds/zot-fermetures "$V/fermetures.json"
  copie declencheurs forgejo-webhook secret kv/declencheurs/forgejo-webhook "$V/webhook"
  [ "$ko" = 0 ] || exit 1
}

etape_s1_retrait() {
  exige_rke2
  sources "$V"
  kubectl create secret generic zot-chains -n "$NS" --from-file=config.json="$V/chains.json" --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
  kubectl patch deployment -n "$NS" "$DEP" --type strategic --patch-file "$C/chains-zot-retrait.yaml" >/dev/null
  kubectl rollout status -n "$NS" "deploy/$DEP" --timeout=180s
  attendu "conteneurs d'initialisation" "$(kubectl get deploy -n "$NS" "$DEP" -o json | jq '.spec.template.spec.initContainers // [] | length')" 0
  [ "$ko" = 0 ] || exit 1
}

for e in "$@"; do
  { echo "# secrets.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/secrets-$e.log"
  [ "${PIPESTATUS[0]}" = 0 ] || exit 1
done
