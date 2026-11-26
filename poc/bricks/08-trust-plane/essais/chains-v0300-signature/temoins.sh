#!/usr/bin/env bash
# Témoins des règles qui réussissent pour Chains v0.30.0 sans témoin (porte Conforma et reserve-c sous Kyverno) : chaque témoin
# change un seul champ des objets de j7-sample-app (ou une ligne de la liste revue), signés par v0.29.9 et v0.30.0 sur une image
# neuve (banc de signature, main.go inchangé), puis jugés comme dans porte.sh (ec v0.10.42, politique en service) et ivpol.sh
# (kyverno apply 1.19.2, reserve-c en diagnostic, bundles sans jeton TSA en referrers par repli d'étiquette, TaskRun avant
# PipelineRun). Critère : pour v0.29.9, la règle visée passe de succès à refus (ou avertissement) et l'ensemble des codes
# refusés ou avertis ne change que de ce qui est prédit ; pour v0.30.0, rien ne change.
# Témoins :
#   sujet      publier : résultat IMAGE_DIGEST remplacé par un digest nul           subject_build_task_matches
#   echec      preparer : condition Succeeded à False                               successful_pipeline_tasks
#   parametre  publier : paramètre digest remplacé par un digest nul                trusted_parameters
#   artefact   construire : paramètre SOURCE_ARTIFACT (oci:…@digest nul) ajouté     valid_trusted_artifact_inputs
#   epingle    publier : digest retiré de la référence du bundle                    pinned (et trusted)
#   courant    liste revue : expires_on ajouté à publier-image (ec seulement)       current
# Règles sans témoin possible ici, contrôlées : build_script_used (aucune tâche n'a de champ steps au premier niveau, condition
# de refus déjà vraie pour v0.29.9), future_deny_rule (pas de trusted_task_rules dans la liste revue), preparation_appariee (pas
# de construire-deb dans j7).
# Tout tourne dans un espace réseau neuf (unshare -rn, boucle locale seule) : aucun appel ne peut sortir de l'hôte.
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/temoins.sh
set -uo pipefail
export LC_ALL=C.UTF-8
[ -n "${BANC_ISOLE:-}" ] || exec unshare -rn env BANC_ISOLE=1 bash "$0" "$@"
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
P08=$depot/poc/bricks/08-trust-plane
LOG=$P08/resultats/chains-v0300-temoins${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
T=$C/temoins/travail   # effacé au début, gardé à la fin pour relecture
[ ! -e ~/.cache/supply-chain-poc/chains-v0300/temoins/travail ] || find ~/.cache/supply-chain-poc/chains-v0300/temoins/travail -delete
mkdir -p "$T/cle" "$T/biblio" "$T/politique/regles" "$T/politique/donnees" "$T/politique-courant/donnees"
chmod 700 "$T/cle"
SERVE=
trap '[ -z "$SERVE" ] || kill "$SERVE" 2> /dev/null' EXIT
HOTE=sc-stockage.poc.test:5000
O=$C/objets
CAS=j7-sample-app
PR=$O/pr-$CAS.json
mapfile -t TRS < <(jq -r '.status.childReferences[].name' "$PR" | sed "s#^#$O/tr-#; s#\$#.json#")
ANCIEN=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$PR")
UID_PR=$(jq -r '.metadata.uid' "$PR")
URL=$(jq -r '.spec.params[] | select(.name == "depot") | .value' "$PR")
REV=$(jq -r '.spec.params[] | select(.name == "commit") | .value' "$PR")
CPOL=$HOME/.cache/supply-chain-poc/08/telechargements/conforma-policy
CPOL_COMMIT=$(sed -n 's/^CPOL_COMMIT=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
CPOL_ARBRE=$(sed -n 's/^CPOL_ARBRE=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
EC_BIN=$(sed -n 's/^EC_BIN=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
PUBLIER=sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b
NUL=sha256:0000000000000000000000000000000000000000000000000000000000000000
PREDICAT=https://slsa.dev/provenance/v1
TYPE=application/vnd.dev.sigstore.bundle.v0.3+json
# témoin : tâche, filtre jq (champ changé), règle visée, codes ajoutés chez ec et chez reserve-c pour v0.29.9 (code=état)
declare -A TACHE FILTRE AJOUT_EC AJOUT_RC
TACHE[sujet]=publier;      FILTRE[sujet]='.status.results |= map(if .name == "IMAGE_DIGEST" then .value = $nul else . end)'
TACHE[echec]=preparer;     FILTRE[echec]='.status.conditions |= map(if .type == "Succeeded" then .status = "False" else . end)'
TACHE[parametre]=publier;  FILTRE[parametre]='.spec.params |= map(if .name == "digest" then .value = $nul else . end)'
TACHE[artefact]=construire; FILTRE[artefact]='.spec.params = [{"name": "SOURCE_ARTIFACT", "value": ("oci:sc-stockage.poc.test:5000/entrees/absent@" + $nul)}]'
TACHE[epingle]=publier;    FILTRE[epingle]='.spec.taskRef.params |= map(if .name == "bundle" then .value |= sub("@sha256:[0-9a-f]{64}$"; "") else . end)'
AJOUT_EC[sujet]='slsa_build_scripted_build.subject_build_task_matches=refus'
AJOUT_EC[echec]='tasks.successful_pipeline_tasks=refus'
AJOUT_EC[parametre]='trusted_task.trusted_parameters=refus'
AJOUT_EC[artefact]='trusted_task.valid_trusted_artifact_inputs=refus'
AJOUT_EC[epingle]='trusted_task.pinned=avertissement trusted_task.trusted=refus'
AJOUT_EC[courant]='trusted_task.current=avertissement'
AJOUT_RC[sujet]='slsa_build_scripted_build.subject_build_task_matches=ko'
AJOUT_RC[echec]='tasks.successful_pipeline_tasks=ko'
AJOUT_RC[parametre]='trusted_task.trusted_parameters=ko'
AJOUT_RC[artefact]='trusted_task.valid_trusted_artifact_inputs=ko'
AJOUT_RC[epingle]='trusted_task.pinned=avert trusted_task.trusted=ko'
TEMOINS='sujet echec parametre artefact epingle'
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
trie() { tr ' ' '\n' | grep . | sort -u | tr '\n' ' '; }
abrege() { sed "s#$REG#REGISTRE#g; s#sha256:\([0-9a-f]\{12\}\)[0-9a-f]\{52\}#sha256:\1…#g"; }
juger() { # nom image [politique] : ec validate image comme le Job de la porte ; $T/e-<nom> : code=refus|avertissement (triés)
  local snap
  snap=$(jq -nc --arg c "banc-$1" --arg i "$2" --arg u "$URL" --arg r "$REV" '{components: [{name: $c, containerImage: $i, source: {git: {url: $u, revision: $r}}}]}')
  SIGSTORE_REKOR_PUBLIC_KEY=$T/cle/cosign.pub ec validate image --images "$snap" --public-key "$T/cle/cosign.pub" \
    --policy "${3:-$T/politique/policy.yaml}" --ignore-rekor --info --show-successes --output "json=$T/ec-$1.json" --strict=false \
    > "$T/ec-$1.out" 2> "$T/ec-$1.err"
  attendu "$1 : ec, code (--strict=false)" "$?" 0
  jq -r '.components[] | ([.violations[]?.metadata.code | . + "=refus"] + [.warnings[]?.metadata.code | . + "=avertissement"]) | unique[]' \
    "$T/ec-$1.json" > "$T/e-$1"
}
etat_ec() { # nom code : refus, avertissement, succès ou absent
  jq -r --arg c "$2" '.components[] | if ([.violations[]?.metadata.code] | index($c)) then "refus" elif ([.warnings[]?.metadata.code] | index($c)) then "avertissement"
    elif ([.successes[]?.metadata.code] | index($c)) then "succès" else "absent" end' "$T/ec-$1.json"
}
publier() { # nom digest nombre-attendu : bundles sans jeton des attestations de l'image, vérifiés, TaskRun avant PipelineRun
  local n=$1 D=$2 i=0 e W inv
  cosign download attestation "$REG/builds/sample-app@$D" > "$T/env-$n.jsonl" 2> "$T/env-$n.err"
  attendu "$n : attestations sur l'image" "$(grep -c . "$T/env-$n.jsonl")" "$3"
  oras manifest fetch --plain-http --descriptor "$REG/builds/sample-app@$D" > "$T/sujet-$n.json" 2> "$T/sujet-$n.err"
  : > "$T/ordre-$n.pr"; : > "$T/ordre-$n.tr"
  while IFS= read -r e <&3; do
    i=$((i + 1)); W=$T/b-$n-$i; mkdir -p "$W"
    printf '%s' "$e" > "$W/env.json"
    jq -r '.signatures[0].sig' "$W/env.json" > "$W/sig.b64"; jq -r '.payload' "$W/env.json" | base64 -d > "$W/payload.json"
    inv=$(jq -r '.predicate.runDetails.metadata.invocationId' "$W/payload.json")
    cosign bundle create --artifact "$W/payload.json" --signature "$W/sig.b64" --attestation "$W/env.json" --key "$T/cle/cosign.pub" \
      --ignore-tlog --out "$W/bundle.json" > "$W/creation.out" 2>&1 || { echo "KO   $n : bundle $i non créé"; ko=$((ko + 1)); }
    cosign verify-blob-attestation --bundle "$W/bundle.json" --new-bundle-format --key "$T/cle/cosign.pub" --insecure-ignore-tlog \
      --type "$PREDICAT" --digest "${D#sha256:}" --digestAlg sha256 > "$W/verif.out" 2>&1 || { echo "KO   $n : bundle $i non vérifié"; ko=$((ko + 1)); }
    if [ "$inv" = "$UID_PR" ]; then echo "$W pr" >> "$T/ordre-$n.pr"; else echo "$W tr" >> "$T/ordre-$n.tr"; fi
  done 3< "$T/env-$n.jsonl"
  cat "$T/ordre-$n.tr" "$T/ordre-$n.pr" > "$T/ordre-$n"
  attendu "$n : bundles créés et vérifiés, dernier publié" "$(tail -1 "$T/ordre-$n" | cut -d' ' -f2)" pr
  i=0
  while read -r W genre; do
    i=$((i + 1))
    oras blob push --plain-http "$REG/horodatage/bundles" "$W/bundle.json" > /dev/null 2> "$W/blob.err"
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s","config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:%s","size":2},"layers":[{"mediaType":"%s","digest":"sha256:%s","size":%s}],"subject":%s,"annotations":{"dev.sigstore.bundle.content":"dsse-envelope","dev.sigstore.bundle.predicateType":"%s"}}' \
      "$TYPE" "$(printf '{}' | sha256sum | cut -c1-64)" "$TYPE" "$(sha256sum < "$W/bundle.json" | cut -c1-64)" "$(wc -c < "$W/bundle.json")" \
      "$(cat "$T/sujet-$n.json")" "$PREDICAT" > "$W/manifeste.json"
    oras manifest push --plain-http "$REG/horodatage/bundles:${D#sha256:}-$i-$genre" "$W/manifeste.json" > "$W/manifeste.out" 2>&1 \
      || { echo "KO   $n : bundle $genre non publié"; ko=$((ko + 1)); }
  done < "$T/ordre-$n"
}
diag() { # nom image : reserve-c en diagnostic ; $T/r-<nom> : code=ok|ko|avert (triés, uniques) ; provenance retenue contrôlée
  printf 'apiVersion: v1\nkind: Pod\nmetadata: {name: banc, namespace: bancc}\nspec:\n  containers:\n    - name: app\n      image: %s\n' "$2" > "$T/pod-$1.yaml"
  kyverno apply "$T/rc-diag.yaml" --resource "$T/pod-$1.yaml" --policy-report --output-format json > "$T/k-$1.out" 2> "$T/k-$1.err"
  python3 -I -c 'import json,re,sys
t = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1]).read()); i = t.find("{"); d = json.loads(t[i:]) if i >= 0 else {}
r = d.get("results", [])
if len(r) != 1: print("absent\t%d résultats" % len(r)); sys.exit()
print(r[0].get("result", "?") + "\t" + (r[0].get("message") or "").replace("\n", " "))' "$T/k-$1.out" > "$T/k-$1.res"
  attendu "$1 : kyverno, provenance retenue" "$(cut -f2 "$T/k-$1.res" | cut -d' ' -f1-2)" "DIAG $UID_PR"
  cut -f2 "$T/k-$1.res" | tr ' ' '\n' | sed -n '3,$p' | sort -u > "$T/r-$1"
}
etat_rc() { # nom code : statut(s) dans le diagnostic, ou absent
  local s; s=$(sed -n "s/^$2=//p" "$T/r-$1" | sort -u | paste -sd, -); echo "${s:-absent}"
}
signer() { # nom version dossier-objets nombre-attendu : image neuve signée ; $T/digest-<nom>
  local B=$C/sig/banc-signature$2 D L=() f
  for f in "${TRS[@]}"; do L+=("$3/$(basename "$f")"); done
  D=$("$B" image "$REG" builds/sample-app); echo "$D" > "$T/digest-$1"
  "$B" signer "$REG" "$T/cle" "$HOTE" "$ANCIEN" "$D" "$3/$(basename "$PR")" "${L[@]}" > "$T/sign-$1.json" 2> "$T/zap-$1.log"
  attendu "$1 : signer, code" "$?" 0
  attendu "$1 : erreurs de Sign" "$(jq '[.sign[] | select(. != "")] | length' "$T/sign-$1.json")" 0
  publier "$1" "$D" "$4"
}
{
  echo "# temoins.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), main.go $(sha256sum < "$here/main.go" | cut -c1-16)"
  ip link set lo up
  attendu "réseau du banc : interfaces" "$(ip -o link | wc -l)" 1
  attendu "réseau du banc : routes de la table principale" "$(ip route show table main | wc -l)" 0
  attendu "ec : empreinte du verrou (politique.sh)" "$(sha256sum < "$(command -v ec)" | cut -c1-64)" "$EC_BIN"
  attendu "kyverno : version (mise.toml)" "$(kyverno version 2> /dev/null | sed -n 's/^Version: //p')" 1.19.2
  echo "ec : $(ec version 2>&1 | sed -n 's/^Version *//p') ; cosign : $(cosign version 2>&1 | sed -n 's/^GitVersion: *//p') ; oras : $(oras version 2>&1 | sed -n 's/^Version: *//p')"
  for v in 29 30; do
    cmp -s "$here/main.go" "$C/src$v/cmd/banc-signature/main.go" && echo "src$v : commit $(git -C "$C/src$v" rev-parse HEAD), main.go identique, binaire $(sha256sum < "$C/sig/banc-signature$v" | cut -c1-16)" \
      || { echo "KO   src$v : main.go différent de celui du dépôt"; ko=$((ko + 1)); }
  done
  attendu "bibliothèque : arbre de $CPOL_COMMIT" "$(git -C "$CPOL" rev-parse "$CPOL_COMMIT^{tree}")" "$CPOL_ARBRE"
  git -C "$CPOL" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$T/biblio"
  find "$T/biblio" -name '*_test.rego' -delete
  echo "cas : $CAS, ${#TRS[@]} TaskRuns, PipelineRun ${UID_PR:0:8}… ; source attendue : $URL @ ${REV:0:12}…"
  "$C/sig/banc-signature30" cle "$T/cle"
  "$C/sig/banc-signature30" serve "$T/port" & SERVE=$!
  for _ in $(seq 50); do [ -s "$T/port" ] && break; read -rt 0.1 < /dev/zero || true; done
  REG=127.0.0.1:$(cat "$T/port")
  printf '{}' > "$T/vide.json"; oras blob push --plain-http "$REG/horodatage/bundles" "$T/vide.json" > /dev/null 2>&1
  echo "## politiques"
  sed "s#$HOTE#$REG#g" "$P08/politique/porte/porte.rego" > "$T/politique/regles/porte.rego"
  sed "s#$HOTE#$REG#g" "$P08/politique/porte/taches.yml" > "$T/politique/donnees/taches.yml"
  sed "s#/politique/policy/#$T/biblio/policy/#; s#/etc/porte/#$T/politique/#" "$P08/politique/porte/policy.yaml" > "$T/politique/policy.yaml"
  attendu "noms remplacés dans porte.rego et taches.yml" "$(diff "$P08/politique/porte/porte.rego" "$T/politique/regles/porte.rego" | grep -c '^>') $(diff "$P08/politique/porte/taches.yml" "$T/politique/donnees/taches.yml" | grep -c '^>')" "1 15"
  attendu "policy.yaml : seuls les chemins changent" "$(diff <(grep -v '^ *#' "$P08/politique/porte/policy.yaml") <(grep -v '^ *#' "$T/politique/policy.yaml") | grep -c '^>')" 4
  # témoin courant : même politique, liste revue où publier-image porte une date d'expiration (lointaine)
  sed "/- ref: $PUBLIER/a\\      expires_on: \"2099-12-31T00:00:00Z\"" "$T/politique/donnees/taches.yml" > "$T/politique-courant/donnees/taches.yml"
  sed "s#$T/politique/donnees#$T/politique-courant/donnees#" "$T/politique/policy.yaml" > "$T/politique-courant/policy.yaml"
  attendu "témoin courant : lignes ajoutées dans taches.yml ; changées dans policy.yaml" "$(diff "$T/politique/donnees/taches.yml" "$T/politique-courant/donnees/taches.yml" | grep -c '^>') $(diff "$T/politique/policy.yaml" "$T/politique-courant/policy.yaml" | grep -c '^>')" "1 1"
  diff "$T/politique/donnees/taches.yml" "$T/politique-courant/donnees/taches.yml" | sed 's/^/  /'
  python3 -I "$P08/politique/reserve-c/generer.py" "$P08/politique/reserve-c/ivpol.tmpl.yaml" "$T/cle/cosign.pub" "$T/politique/donnees/taches.yml" \
    "$P08/politique/porte/policy.yaml" reserve-c "$REG/*" "$REG/horodatage/bundles" "$URL" "$REV" diagnostic > "$T/rc-diag.yaml"
  attendu "reserve-c rendue" "$?" 0
  echo "## objets des témoins"
  mkdir -p "$T/obj-base"; cp "$PR" "${TRS[@]}" "$T/obj-base/"
  for m in $TEMOINS; do
    M=$T/obj-$m; mkdir -p "$M"; cp "$PR" "$M/"
    for f in "${TRS[@]}"; do
      if [ "$(basename "$f")" = "tr-$CAS-${TACHE[$m]}.json" ]; then jq --arg nul "$NUL" "${FILTRE[$m]}" "$f" > "$M/$(basename "$f")"; else cp "$f" "$M/"; fi
    done
    attendu "$m : fichiers changés (seul ${TACHE[$m]})" "$(for f in "${TRS[@]}" "$PR"; do cmp -s "$f" "$M/$(basename "$f")" || basename "$f" .json; done | tr '\n' ' ')" "tr-$CAS-${TACHE[$m]} "
    diff <(jq -S . "$O/tr-$CAS-${TACHE[$m]}.json") <(jq -S . "$M/tr-$CAS-${TACHE[$m]}.json") | sed 's/^/  /'
  done
  for m in base $TEMOINS; do
    for v in 29 30; do
      echo "## $m v$v"
      if [ "$m" = sujet ]; then n=1; else n=2; fi   # sujet : l'attestation du TaskRun publier a pour sujet le digest nul
      signer "$m-$v" "$v" "$T/obj-$m" "$n"
      I=$REG/builds/sample-app@$(cat "$T/digest-$m-$v")
      juger "$m-$v" "$I"
      echo "ec : $(tr '\n' ' ' < "$T/e-$m-$v" | sed 's/=refus/=R/g; s/=avertissement/=A/g')"
      diag "$m-$v" "$I"
      echo "reserve-c : $(grep -v '=ok$' "$T/r-$m-$v" | tr '\n' ' ')"
    done
  done
  echo "## courant (liste revue avec expires_on), images de base"
  for v in 29 30; do
    juger "courant-$v" "$REG/builds/sample-app@$(cat "$T/digest-base-$v")" "$T/politique-courant/policy.yaml"
    echo "ec : $(tr '\n' ' ' < "$T/e-courant-$v" | sed 's/=refus/=R/g; s/=avertissement/=A/g')"
  done
  echo "## référence (base)"
  attendu "base v29, ec : codes refusés" "$(grep '=refus$' "$T/e-base-29" | sed 's/=refus$//' | trie)" "porte.fermeture_plateforme "
  attendu "base v30, ec : codes refusés" "$(grep '=refus$' "$T/e-base-30" | sed 's/=refus$//' | trie)" "porte.taches_vues slsa_build_scripted_build.build_task_image_results_found tasks.pipeline_has_tasks "
  attendu "base v29, reserve-c : ko" "$(grep -c '=ko$' "$T/r-base-29")" 0
  attendu "base v30, reserve-c : ko" "$(grep '=ko$' "$T/r-base-30" | sed 's/=ko$//' | trie)" "slsa_build_scripted_build.build_task_image_results_found tasks.pipeline_has_tasks "
  echo "## témoins : état de la règle visée (base v29 → témoin v29 | base v30 → témoin v30)"
  for m in $TEMOINS courant; do
    for a in ${AJOUT_EC[$m]}; do
      c=${a%=*}
      echo "  ec $m $c : $(etat_ec "base-29" "$c") → $(etat_ec "$m-29" "$c") | $(etat_ec "base-30" "$c") → $(etat_ec "$m-30" "$c")"
    done
    for a in ${AJOUT_RC[$m]:-}; do
      c=${a%=*}
      echo "  rc $m $c : $(etat_rc "base-29" "$c") → $(etat_rc "$m-29" "$c") | $(etat_rc "base-30" "$c") → $(etat_rc "$m-30" "$c")"
    done
  done
  echo "## contrôles des témoins"
  for m in $TEMOINS courant; do
    attendu "$m v29, ec : codes ajoutés" "$(comm -13 "$T/e-base-29" "$T/e-$m-29" | trie)" "$(trie <<< "${AJOUT_EC[$m]}")"
    attendu "$m v29, ec : codes retirés" "$(comm -23 "$T/e-base-29" "$T/e-$m-29" | trie)" ""
    attendu "$m v30, ec : inchangé" "$(diff "$T/e-base-30" "$T/e-$m-30" | grep -c '^[<>]')" 0
    for a in ${AJOUT_EC[$m]}; do
      attendu "$m : ${a%=*}, succès pour v29 de base" "$(etat_ec base-29 "${a%=*}")" succès
    done
  done
  for m in $TEMOINS; do
    attendu "$m v29, reserve-c : codes ajoutés" "$(comm -13 <(grep -v '=ok$' "$T/r-base-29") <(grep -v '=ok$' "$T/r-$m-29") | trie)" "$(trie <<< "${AJOUT_RC[$m]}")"
    attendu "$m v29, reserve-c : codes retirés" "$(comm -23 <(grep -v '=ok$' "$T/r-base-29") <(grep -v '=ok$' "$T/r-$m-29") | trie)" ""
    attendu "$m v30, reserve-c : inchangé" "$(diff "$T/r-base-30" "$T/r-$m-30" | grep -c '^[<>]')" 0
  done
  for m in $TEMOINS courant; do
    jq -r --arg l "${AJOUT_EC[$m]}" '.components[] | (.violations + .warnings)[]? | select(.metadata.code as $c | $l | split(" ") | map(split("=")[0]) | index($c))
      | "  " + .metadata.code + " : " + (.msg | .[0:220])' "$T/ec-$m-29.json" | abrege | sed "s/^/$m/"
  done
  echo "## règles sans témoin possible ici"
  while read -r e; do
    jq -r '.payload' <<< "$e" | base64 -d > "$T/st.json"
    [ "$(jq -r '.predicate.runDetails.metadata.invocationId' "$T/st.json")" = "$UID_PR" ] && cp "$T/st.json" "$T/st-pr-29.json"
  done < "$T/env-base-29.jsonl"
  jq '[.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson]' "$T/st-pr-29.json" > "$T/taches-29.json"
  attendu "v29 : tâches lues dans la provenance du PipelineRun" "$(jq length "$T/taches-29.json")" 3
  attendu "build_script_used : tâches avec un champ steps au premier niveau (v29)" "$(jq '[.[] | select(has("steps"))] | length' "$T/taches-29.json")" 0
  attendu "build_script_used : état (v29 | v30)" "$(etat_ec base-29 slsa_build_scripted_build.build_script_used) | $(etat_ec base-30 slsa_build_scripted_build.build_script_used)" "succès | succès"
  attendu "future_deny_rule : trusted_task_rules dans la liste revue" "$(grep -c trusted_task_rules "$T/politique/donnees/taches.yml")" 0
  attendu "future_deny_rule : état (v29 | v30)" "$(etat_ec base-29 trusted_task.future_deny_rule) | $(etat_ec base-30 trusted_task.future_deny_rule)" "succès | succès"
  attendu "preparation_appariee : construire-deb dans j7 (v29)" "$(jq '[.[] | .spec.taskRef.params[]? | select(.name == "name" and .value == "construire-deb")] | length' "$T/taches-29.json")" 0
  attendu "preparation_appariee : état (v29 | v30)" "$(etat_ec base-29 porte.preparation_appariee) | $(etat_ec base-30 porte.preparation_appariee)" "succès | succès"
  kill "$SERVE"; wait "$SERVE" 2> /dev/null; SERVE=
  echo "## bilan : $ko KO, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
