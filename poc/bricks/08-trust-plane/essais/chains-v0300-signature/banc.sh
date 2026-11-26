#!/usr/bin/env bash
# Banc de signature de Chains v0.30.0 contre v0.29.9 (témoin) : ObjectSigner.Sign sur les vrais objets de j7-sample-app, registre en
# mémoire sur 127.0.0.1, clé cosign jetable créée par le banc, faux clients Kubernetes et Tekton. Rien ne sort de l'hôte.
# Vérifie avec cosign (mise) ce qui est stocké : signature simplesigning, attestations, noms des dépendances pipelineTask.
# Cas « aucun signataire » : même appel avec un dossier de clé vide. Usage (racine du dépôt) :
#   [SUFFIXE=-2] mise exec -- bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/banc.sh
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
LOG=$depot/poc/bricks/08-trust-plane/resultats/chains-v0300-signature${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
T=$C/sig/travail   # effacé au début, gardé à la fin pour relecture
[ ! -e ~/.cache/supply-chain-poc/chains-v0300/sig/travail ] || find ~/.cache/supply-chain-poc/chains-v0300/sig/travail -delete
mkdir -p "$T/cle" "$T/vide"
chmod 700 "$T/cle"
SERVE=
trap '[ -z "$SERVE" ] || kill "$SERVE" 2> /dev/null' EXIT
HOTE=sc-stockage.poc.test:5000
O=$C/objets
CAS=j7-sample-app
PR=$O/pr-$CAS.json
mapfile -t TRS < <(jq -r '.status.childReferences[].name' "$PR" | sed "s#^#$O/tr-#; s#\$#.json#")
ANCIEN=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$PR")
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
noms() { # registre digest : noms pipelineTask des attestations vérifiées, triés, une ligne par attestation
  jq -r '.payload | @base64d | fromjson | [.predicate.buildDefinition.resolvedDependencies[]?.name // empty | select(startswith("pipelineTask") or startswith("pipeline"))] | join(",")' "$1" | sort
}
# Énoncé normalisé : content des dépendances (JSON) et des byproducts (texte) décodé, annotations (objets et internalParameters) et finaliseurs chains.tekton.dev retirés (ils viennent de la signature en service),
# clés triées. Appliqué à l'énoncé signé (hôte et digest du banc remis à ceux d'origine) et à la sortie du banc à sec.
NORM='def net: .metadata.annotations |= ((. // {}) | with_entries(select(.key | startswith("chains.tekton.dev/") | not)))
  | .metadata.finalizers |= ((. // []) | map(select(startswith("chains.tekton.dev") | not)));
  .predicate.buildDefinition.resolvedDependencies |= map(if .content then .content |= (@base64d | fromjson | net) else . end)
  | .predicate.buildDefinition.internalParameters.annotations |= ((. // {}) | with_entries(select(.key | startswith("chains.tekton.dev/") | not)))
  | .predicate.runDetails.byproducts |= ((. // []) | map(if .content then .content |= @base64d else . end))'
enonce() { # fichier d'attestations, version, filtre de sélection : énoncé normalisé sur la sortie
  jq -c '.payload | @base64d | fromjson' "$1" | jq -c "select($3)" | jq -c "$NORM" | sed "s#$REG#$HOTE#g; s#${D#sha256:}#${ANCIEN#sha256:}#g" | jq -S .
}
{
  echo "# banc.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), main.go $(sha256sum < "$here/main.go" | cut -c1-16)"
  echo "cosign : $(cosign version 2>&1 | sed -n 's/^GitVersion: *//p')"
  for v in 29 30; do
    cmp -s "$here/main.go" "$C/src$v/cmd/banc-signature/main.go" && echo "src$v : commit $(git -C "$C/src$v" rev-parse HEAD), main.go identique, binaire $(sha256sum < "$C/sig/banc-signature$v" | cut -c1-16)" \
      || { echo "KO   src$v : main.go différent de celui du dépôt"; ko=$((ko + 1)); }
  done
  echo "cas : $CAS, ${#TRS[@]} TaskRuns, digest d'origine ${ANCIEN:0:19}…"
  "$C/sig/banc-signature30" cle "$T/cle"; attendu "clé jetable créée" "$(ls "$T/cle" | tr '\n' ' ')" "cosign.key cosign.password cosign.pub "
  for v in 29 30; do
    echo "## v$v"
    B=$C/sig/banc-signature$v
    find ~/.cache/supply-chain-poc/chains-v0300/sig/travail -maxdepth 1 -name port -delete
    "$B" serve "$T/port" & SERVE=$!
    for _ in $(seq 50); do [ -s "$T/port" ] && break; read -rt 0.1 < /dev/zero || true; done
    REG=127.0.0.1:$(cat "$T/port")
    D=$("$B" image "$REG" builds/sample-app); echo "image du banc : ${D:0:19}…"
    "$B" signer "$REG" "$T/cle" "$HOTE" "$ANCIEN" "$D" "$PR" "${TRS[@]}" > "$T/sign-$v.json" 2> "$T/zap-$v.log"; attendu "v$v signer, code" "$?" 0
    jq -c '.sign' "$T/sign-$v.json"
    jq -c '.recorder' "$T/sign-$v.json"
    jq -c '.annotations | map_values(keys)' "$T/sign-$v.json"
    echo "avertissements et erreurs du journal zap : $(grep -c -E '	(WARN|ERROR)	' "$T/zap-$v.log")"
    grep -E '	(WARN|ERROR)	' "$T/zap-$v.log" | cut -f2,4 | cut -c1-200 | sort | uniq -c | sed "s#$HOME#~#g"
    attendu "v$v erreurs de Sign" "$(jq '[.sign[] | select(. != "")] | length' "$T/sign-$v.json")" 0
    cosign verify --key "$T/cle/cosign.pub" --insecure-ignore-tlog=true "$REG/builds/sample-app@$D" > "$T/sig-$v.json" 2> "$T/sig-$v.err"; c=$?
    attendu "v$v cosign verify (simplesigning), code" "$c" 0; [ "$c" -eq 0 ] || sed "s#$HOME#~#g" "$T/sig-$v.err" | tail -3
    cosign verify-attestation --key "$T/cle/cosign.pub" --insecure-ignore-tlog=true --type slsaprovenance1 "$REG/builds/sample-app@$D" > "$T/att-$v.json" 2> "$T/att-$v.err"; c=$?
    attendu "v$v cosign verify-attestation, code" "$c" 0; [ "$c" -eq 0 ] || sed "s#$HOME#~#g" "$T/att-$v.err" | tail -3
    attendu "v$v attestations vérifiées" "$(grep -c . "$T/att-$v.json")" 2
    noms "$T/att-$v.json" > "$T/noms-$v.txt"; sed 's/^/  noms : /' "$T/noms-$v.txt"
    [ "$v" = 29 ] && n=pipeline,pipelineTask,pipelineTask,pipelineTask || n=pipeline,pipelineTask/preparer,pipelineTask/construire,pipelineTask/publier
    attendu "v$v noms pipeline* de l'attestation du PipelineRun" "$(grep . "$T/noms-$v.txt")" "$n"
    attendu "v$v objets annotés signed=true" "$(jq '[.annotations[] | select(."chains.tekton.dev/signed" == "true")] | length' "$T/sign-$v.json")" 4
    attendu "v$v erreurs comptées par le Recorder" "$(jq '[.recorder | to_entries[] | select(.key | startswith("erreur:"))] | length' "$T/sign-$v.json")" 0
    enonce "$T/att-$v.json" "$v" '[.predicate.buildDefinition.resolvedDependencies[]?.name] | index("pipeline")' > "$T/enonce-pr-$v.json"
    jq -S "$NORM" "$C/sorties/$CAS.$v.json" > "$T/sec-pr-$v.json"
    attendu "v$v énoncé signé du PipelineRun = sortie à sec" "$(cmp -s "$T/enonce-pr-$v.json" "$T/sec-pr-$v.json" && echo égal || echo différent)" égal
    cmp -s "$T/enonce-pr-$v.json" "$T/sec-pr-$v.json" || diff <(jq -c 'paths(scalars) as $p | [$p, getpath($p)]' "$T/sec-pr-$v.json") <(jq -c 'paths(scalars) as $p | [$p, getpath($p)]' "$T/enonce-pr-$v.json") | cut -c1-240 | head -40
    enonce "$T/att-$v.json" "$v" '[.predicate.buildDefinition.resolvedDependencies[]?.name] | index("task")' > "$T/enonce-tr-$v.json"
    jq -S "$NORM" "$C/sorties/tr-$CAS-publier.$v.json" > "$T/sec-tr-$v.json"
    attendu "v$v énoncé signé de publier = sortie à sec" "$(cmp -s "$T/enonce-tr-$v.json" "$T/sec-tr-$v.json" && echo égal || echo différent)" égal
    cmp -s "$T/enonce-tr-$v.json" "$T/sec-tr-$v.json" || diff <(jq -c 'paths(scalars) as $p | [$p, getpath($p)]' "$T/sec-tr-$v.json") <(jq -c 'paths(scalars) as $p | [$p, getpath($p)]' "$T/enonce-tr-$v.json") | cut -c1-240 | head -40
    # aucun signataire : dossier de clé vide, nouvelle image
    D2=$("$B" image "$REG" builds/sans-cle)
    "$B" signer "$REG/builds/sans-cle" "$T/vide" "$HOTE/builds/sample-app" "$ANCIEN" "$D2" "$PR" "${TRS[@]}" > "$T/vide-$v.json" 2> "$T/zap-vide-$v.log"
    sed -i "s#$REG/builds/sans-cle#REGISTRE/builds/sans-cle#g" "$T/vide-$v.json"
    echo "aucun signataire, Sign :"; jq -c '.sign' "$T/vide-$v.json"
    [ "$v" = 29 ] && e=0 || e=4
    attendu "v$v aucun signataire, objets en erreur" "$(jq '[.sign[] | select(test("no signer x509 configured"))] | length' "$T/vide-$v.json")" "$e"
    [ "$v" = 29 ] && e=4 || e=0
    attendu "v$v aucun signataire, objets marqués signed=true" "$(jq '[.annotations[] | select(."chains.tekton.dev/signed" == "true")] | length' "$T/vide-$v.json")" "$e"
    attendu "v$v aucun signataire, erreurs comptées par le Recorder" "$(jq '[.recorder | to_entries[] | select(.key | startswith("erreur:"))] | length' "$T/vide-$v.json")" 0
    echo "aucun signataire, recorder : $(jq -c '.recorder' "$T/vide-$v.json")"
    echo "aucun signataire, annotations : $(jq -c '.annotations' "$T/vide-$v.json")"
    cosign tree "$REG/builds/sans-cle@$D2" > "$T/arbre-vide-$v.txt" 2>&1
    echo "aucun signataire, cosign tree :"; sed -E "s#$REG#REGISTRE#g; s#sha256:([0-9a-f]{12})[0-9a-f]{52}#sha256:\\1…#g; s/^/  /" "$T/arbre-vide-$v.txt"; echo
    attendu "v$v aucun signataire, rien d'attaché à l'image" "$(grep -c 'No Supply Chain Security Related Artifacts found' "$T/arbre-vide-$v.txt")" 1
    kill "$SERVE"; wait "$SERVE" 2> /dev/null; SERVE=
  done
  echo "## comparaison"
  sed -E 's#pipelineTask/[^,]*#pipelineTask/<nom>#g' "$T/noms-30.txt" | sort > "$T/noms-30-gen.txt"
  echo "v29 : $(sort -u "$T/noms-29.txt" | tr '\n' ' ')"
  echo "v30 : $(sort -u "$T/noms-30.txt" | tr '\n' ' ')"
  echo "## bilan : $ko KO"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
