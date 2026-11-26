#!/usr/bin/env bash
# Témoin de trusted_task.future_deny_rule (conforma/policy, commit épinglé dans politique.sh), seule règle du paquet trusted_task
# restée sans témoin : elle ne s'active qu'avec trusted_task_rules (rule_data), alors que la liste revue en service est à l'ancien
# format trusted_tasks. Les objets de j7-sample-app sont signés tels quels par v0.29.9 et v0.30.0 sur une image neuve (banc de
# signature, main.go inchangé), puis jugés comme dans temoins.sh (ec v0.10.42) sous trois politiques qui ne diffèrent que par
# le ruleData de policy.yaml :
#   service   politique en service (liste revue trusted_tasks seule)
#   regles    + trusted_task_rules_enabled: true et trusted_task_rules, allow seul (motif oci://<registre>/tekton/tasks/*)
#   futur     regles + une règle deny sur publier-image, effective_on 2099-12-31 (date future)       future_deny_rule
#   immediat  regles + la même règle deny, sans effective_on (effective)                         trusted (témoin de regles)
#   eteint    futur sans trusted_task_rules_enabled (défaut false de la bibliothèque) : rien ne doit changer
# Critère : pour v0.29.9, regles ne change aucun code, futur n'ajoute que l'avertissement future_deny_rule, immediat que le
# refus trusted, eteint rien ; pour v0.30.0, rien ne change, et le bundle de publier-image est contrôlé dans l'énoncé signé.
# Passage -2 : trusted_task_rules_enabled (défaut false, lib/rule_data) manquait au passage 1 ; cas immediat et eteint ajoutés ;
# la sortie d'erreur d'ec est contrôlée (les bundles ne sont pas dans le registre du banc : 9 lignes pour v0.29.9).
# La liste de règles est fabriquée pour le banc : le résultat ne dit rien de la porte en service, qui n'a pas trusted_task_rules.
# Tout tourne dans un espace réseau neuf (unshare -rn, boucle locale seule) : aucun appel ne peut sortir de l'hôte.
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/future-deny.sh
set -uo pipefail
export LC_ALL=C.UTF-8
[ -n "${BANC_ISOLE:-}" ] || exec unshare -rn env BANC_ISOLE=1 bash "$0" "$@"
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
P08=$depot/poc/bricks/08-trust-plane
LOG=$P08/resultats/chains-v0300-future-deny${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
T=$C/future-deny/travail   # effacé au début, gardé à la fin pour relecture
[ ! -e ~/.cache/supply-chain-poc/chains-v0300/future-deny/travail ] || find ~/.cache/supply-chain-poc/chains-v0300/future-deny/travail -delete
mkdir -p "$T/cle" "$T/biblio" "$T/politique/regles" "$T/politique/donnees"
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
FUTUR=2099-12-31T00:00:00Z
REGLE=trusted_task.future_deny_rule
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
trie() { tr ' ' '\n' | grep . | sort -u | tr '\n' ' '; }
abrege() { sed "s#$REG#REGISTRE#g; s#sha256:\([0-9a-f]\{12\}\)[0-9a-f]\{52\}#sha256:\1…#g"; }
juger() { # nom image politique : ec validate image comme le Job de la porte ; $T/e-<nom> : code=refus|avertissement (triés)
  local snap
  snap=$(jq -nc --arg c "banc-$1" --arg i "$2" --arg u "$URL" --arg r "$REV" '{components: [{name: $c, containerImage: $i, source: {git: {url: $u, revision: $r}}}]}')
  SIGSTORE_REKOR_PUBLIC_KEY=$T/cle/cosign.pub ec validate image --images "$snap" --public-key "$T/cle/cosign.pub" \
    --policy "$3" --ignore-rekor --info --show-successes --output "json=$T/ec-$1.json" --strict=false \
    > "$T/ec-$1.out" 2> "$T/ec-$1.err"
  attendu "$1 : ec, code (--strict=false)" "$?" 0
  jq -r '.components[] | ([.violations[]?.metadata.code | . + "=refus"] + [.warnings[]?.metadata.code | . + "=avertissement"]) | unique[]' \
    "$T/ec-$1.json" > "$T/e-$1"
}
etat_ec() { # nom code : refus, avertissement, succès ou absent
  jq -r --arg c "$2" '.components[] | if ([.violations[]?.metadata.code] | index($c)) then "refus" elif ([.warnings[]?.metadata.code] | index($c)) then "avertissement"
    elif ([.successes[]?.metadata.code] | index($c)) then "succès" else "absent" end' "$T/ec-$1.json"
}
signer() { # version : image neuve signée par Chains v0.<version> ; $T/digest-<version>, $T/env-<version>.jsonl
  local B=$C/sig/banc-signature$1 D
  D=$("$B" image "$REG" builds/sample-app); echo "$D" > "$T/digest-$1"
  "$B" signer "$REG" "$T/cle" "$HOTE" "$ANCIEN" "$D" "$PR" "${TRS[@]}" > "$T/sign-$1.json" 2> "$T/zap-$1.log"
  attendu "v$1 : signer, code" "$?" 0
  attendu "v$1 : erreurs de Sign" "$(jq '[.sign[] | select(. != "")] | length' "$T/sign-$1.json")" 0
  cosign verify --key "$T/cle/cosign.pub" --insecure-ignore-tlog=true "$REG/builds/sample-app@$D" > "$T/sig-$1.json" 2> "$T/sig-$1.err" \
    && s=signée || s="non signée"
  attendu "v$1 : signature de l'image (cosign verify)" "$s" signée
  cosign download attestation "$REG/builds/sample-app@$D" > "$T/env-$1.jsonl" 2> "$T/env-$1.err"
  attendu "v$1 : attestations sur l'image" "$(grep -c . "$T/env-$1.jsonl")" 2
}
bundle_publier() { # version : nom de la dépendance de publier et dépôt de son bundle, lus dans l'énoncé signé du PipelineRun
  local e st
  while IFS= read -r e; do
    st=$(jq -r '.payload' <<< "$e" | base64 -d)
    [ "$(jq -r '.predicate.runDetails.metadata.invocationId' <<< "$st")" = "$UID_PR" ] || continue
    jq -r '[.predicate.buildDefinition.resolvedDependencies[] | select((.name // "") | startswith("pipelineTask"))
      | {name, run: (.content | @base64d | fromjson)} | select(.run.metadata.labels["tekton.dev/pipelineTask"] == "publier")
      | .name + " " + ([.run.spec.taskRef.params[] | select(.name == "bundle") | .value | sub("@sha256:[0-9a-f]{64}$"; "")] | join(","))] | join(" ; ")' <<< "$st"
  done < "$T/env-$1.jsonl"
}
{
  echo "# future-deny.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), main.go $(sha256sum < "$here/main.go" | cut -c1-16)"
  ip link set lo up
  attendu "réseau du banc : interfaces" "$(ip -o link | wc -l)" 1
  attendu "réseau du banc : routes de la table principale" "$(ip route show table main | wc -l)" 0
  attendu "ec : empreinte du verrou (politique.sh)" "$(sha256sum < "$(command -v ec)" | cut -c1-64)" "$EC_BIN"
  echo "ec : $(ec version 2>&1 | sed -n 's/^Version *//p') ; cosign : $(cosign version 2>&1 | sed -n 's/^GitVersion: *//p')"
  for v in 29 30; do
    cmp -s "$here/main.go" "$C/src$v/cmd/banc-signature/main.go" && echo "src$v : commit $(git -C "$C/src$v" rev-parse HEAD), main.go identique, binaire $(sha256sum < "$C/sig/banc-signature$v" | cut -c1-16)" \
      || { echo "KO   src$v : main.go différent de celui du dépôt"; ko=$((ko + 1)); }
  done
  attendu "bibliothèque : arbre de $CPOL_COMMIT" "$(git -C "$CPOL" rev-parse "$CPOL_COMMIT^{tree}")" "$CPOL_ARBRE"
  git -C "$CPOL" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$T/biblio"
  find "$T/biblio" -name '*_test.rego' -delete
  echo "cas : $CAS, ${#TRS[@]} TaskRuns, PipelineRun ${UID_PR:0:8}…"
  "$C/sig/banc-signature30" cle "$T/cle"
  "$C/sig/banc-signature30" serve "$T/port" & SERVE=$!
  for _ in $(seq 50); do [ -s "$T/port" ] && break; read -rt 0.1 < /dev/zero || true; done
  REG=127.0.0.1:$(cat "$T/port")
  echo "## politiques"
  sed "s#$HOTE#$REG#g" "$P08/politique/porte/porte.rego" > "$T/politique/regles/porte.rego"
  sed "s#$HOTE#$REG#g" "$P08/politique/porte/taches.yml" > "$T/politique/donnees/taches.yml"
  sed "s#/politique/policy/#$T/biblio/policy/#; s#/etc/porte/#$T/politique/#" "$P08/politique/porte/policy.yaml" > "$T/service.yaml"
  attendu "noms remplacés dans porte.rego et taches.yml" "$(diff "$P08/politique/porte/porte.rego" "$T/politique/regles/porte.rego" | grep -c '^>') $(diff "$P08/politique/porte/taches.yml" "$T/politique/donnees/taches.yml" | grep -c '^>')" "1 15"
  attendu "policy.yaml : seuls les chemins changent" "$(diff <(grep -v '^ *#' "$P08/politique/porte/policy.yaml") <(grep -v '^ *#' "$T/service.yaml") | grep -c '^>')" 4
  # trusted_task_rules ajouté au ruleData, juste après allowed_builder_ids (même indentation que lui)
  printf '      trusted_task_rules_enabled: true\n' > "$T/active.yaml"
  printf '      trusted_task_rules:\n        allow:\n          banc:\n            - pattern: "oci://%s/tekton/tasks/*"\n' "$REG" > "$T/allow.yaml"
  printf '        deny:\n          futur:\n            - pattern: "oci://%s/tekton/tasks/publier-image"\n              effective_on: "%s"\n' "$REG" "$FUTUR" > "$T/deny.yaml"
  printf '        deny:\n          immediat:\n            - pattern: "oci://%s/tekton/tasks/publier-image"\n' "$REG" > "$T/deny-immediat.yaml"
  cat "$T/active.yaml" "$T/allow.yaml" > "$T/regles.bloc"; cat "$T/active.yaml" "$T/allow.yaml" "$T/deny.yaml" > "$T/futur.bloc"
  cat "$T/active.yaml" "$T/allow.yaml" "$T/deny-immediat.yaml" > "$T/immediat.bloc"; cat "$T/allow.yaml" "$T/deny.yaml" > "$T/eteint.bloc"
  for p in regles futur immediat eteint; do
    sed "\#https://supply-chain.example/builders/tekton-chains@v1#r $T/$p.bloc" "$T/service.yaml" > "$T/$p.yaml"
    echo "-- $p : lignes ajoutées à policy.yaml"; diff "$T/service.yaml" "$T/$p.yaml" | sed -n 's/^> /  /p' | abrege
  done
  attendu "regles futur immediat eteint : lignes ajoutées et retirées" "$(for p in regles futur immediat eteint; do printf '%s %s | ' "$(diff "$T/service.yaml" "$T/$p.yaml" | grep -c '^>')" "$(diff "$T/service.yaml" "$T/$p.yaml" | grep -c '^<')"; done)" "5 0 | 9 0 | 8 0 | 8 0 | "
  attendu "futur et immediat : ajouts de regles compris ; eteint = futur moins l'activation" "$(diff "$T/regles.yaml" "$T/futur.yaml" | grep -c '^<') $(diff "$T/regles.yaml" "$T/immediat.yaml" | grep -c '^<') $(diff "$T/futur.yaml" "$T/eteint.yaml" | grep -c '^[<>]')" "0 0 1"
  for v in 29 30; do
    echo "## v$v"
    signer "$v"
    if [ "$v" = 29 ]; then n=pipelineTask; else n=pipelineTask/publier; fi
    attendu "v$v : dépendance de publier et dépôt de son bundle dans l'énoncé signé" "$(bundle_publier "$v" | abrege)" "$n REGISTRE/tekton/tasks/publier-image"
    for p in service regles futur immediat eteint; do
      juger "$p-$v" "$REG/builds/sample-app@$(cat "$T/digest-$v")" "$T/$p.yaml"
      echo "ec $p : $(tr '\n' ' ' < "$T/e-$p-$v" | sed 's/=refus/=R/g; s/=avertissement/=A/g')"
    done
  done
  echo "## référence (service)"
  attendu "service v29 : codes refusés" "$(grep '=refus$' "$T/e-service-29" | sed 's/=refus$//' | trie)" "porte.fermeture_plateforme "
  attendu "service v30 : codes refusés" "$(grep '=refus$' "$T/e-service-30" | sed 's/=refus$//' | trie)" "porte.taches_vues slsa_build_scripted_build.build_task_image_results_found tasks.pipeline_has_tasks "
  echo "## règles trusted_task (service | regles | futur | immediat | eteint)"
  for v in 29 30; do
    for c in $(jq -r '.components[] | [.successes[]?, .violations[]?, .warnings[]?] | map(.metadata.code) | unique[] | select(startswith("trusted_task."))' "$T/ec-service-$v.json"); do
      echo "  v$v $c : $(etat_ec "service-$v" "$c") | $(etat_ec "regles-$v" "$c") | $(etat_ec "futur-$v" "$c") | $(etat_ec "immediat-$v" "$c") | $(etat_ec "eteint-$v" "$c")"
    done
  done
  echo "## contrôles"
  for v in 29 30; do
    attendu "regles v$v : codes ajoutés | retirés" "$(comm -13 "$T/e-service-$v" "$T/e-regles-$v" | trie)| $(comm -23 "$T/e-service-$v" "$T/e-regles-$v" | trie)" "| "
    attendu "regles v$v : trusted_task.trusted" "$(etat_ec "regles-$v" trusted_task.trusted)" succès
    attendu "regles v$v : trusted_task.data_format" "$(etat_ec "regles-$v" trusted_task.data_format)" succès
    attendu "regles v$v : $REGLE" "$(etat_ec "regles-$v" "$REGLE")" succès
    attendu "futur v$v : trusted_task.trusted" "$(etat_ec "futur-$v" trusted_task.trusted)" succès
    attendu "futur v$v : trusted_task.data_format" "$(etat_ec "futur-$v" trusted_task.data_format)" succès
    attendu "futur v$v : codes retirés (face à regles)" "$(comm -23 "$T/e-regles-$v" "$T/e-futur-$v" | trie)" ""
  done
  attendu "futur v29 : codes ajoutés (face à regles)" "$(comm -13 "$T/e-regles-29" "$T/e-futur-29" | trie)" "$REGLE=avertissement "
  attendu "futur v30 : codes ajoutés (face à regles)" "$(comm -13 "$T/e-regles-30" "$T/e-futur-30" | trie)" ""
  attendu "futur v30 : $REGLE" "$(etat_ec futur-30 "$REGLE")" succès
  attendu "futur v29 : message de $REGLE" "$(jq -r --arg c "$REGLE" '[.components[] | .warnings[]? | select(.metadata.code == $c) | .msg] | join(" | ")' "$T/ec-futur-29.json" | abrege)" \
    "Task \"publier\" will be denied by rule pattern \"oci://REGISTRE/tekton/tasks/publier-image\" starting on $FUTUR."
  attendu "futur v29 : terme de $REGLE" "$(jq -r --arg c "$REGLE" '[.components[] | .warnings[]? | select(.metadata.code == $c) | .metadata.term] | join(" ")' "$T/ec-futur-29.json")" publier-image
  # témoin de regles : une règle deny effective fait refuser trusted (sans elle, le silence de regles ne prouverait rien)
  attendu "immediat v29 : codes ajoutés | retirés (face à regles)" "$(comm -13 "$T/e-regles-29" "$T/e-immediat-29" | trie)| $(comm -23 "$T/e-regles-29" "$T/e-immediat-29" | trie)" "trusted_task.trusted=refus | "
  attendu "immediat v29 : terme de trusted_task.trusted" "$(jq -r '[.components[] | .violations[]? | select(.metadata.code == "trusted_task.trusted") | .metadata.term] | join(" ")' "$T/ec-immediat-29.json")" publier-image
  attendu "immediat v29 : raison du refus" "$(jq -r '[.components[] | .violations[]? | select(.metadata.code == "trusted_task.trusted") | .msg | test("The denial reason is: deny_rule")] | map(tostring) | join(" ")' "$T/ec-immediat-29.json")" true
  jq -r '.components[] | .violations[]? | select(.metadata.code == "trusted_task.trusted") | "  message : " + .msg' "$T/ec-immediat-29.json" | abrege
  attendu "immediat v29 : trusted_task.trusted_parameters" "$(etat_ec immediat-29 trusted_task.trusted_parameters)" succès
  attendu "immediat v30 : codes ajoutés | retirés (face à regles)" "$(comm -13 "$T/e-regles-30" "$T/e-immediat-30" | trie)| $(comm -23 "$T/e-regles-30" "$T/e-immediat-30" | trie)" "| "
  # défaut de la bibliothèque : sans trusted_task_rules_enabled, la même donnée que futur ne change rien
  for v in 29 30; do
    attendu "eteint v$v : codes ajoutés | retirés (face à service)" "$(comm -13 "$T/e-service-$v" "$T/e-eteint-$v" | trie)| $(comm -23 "$T/e-service-$v" "$T/e-eteint-$v" | trie)" "| "
  done
  # sortie d'erreur d'ec : bundles absents du registre du banc (lus par ec.oci.image_manifests, qui rend alors {})
  for v in 29 30; do
    if [ "$v" = 29 ]; then a="9 9"; else a="0 0"; fi
    for p in service regles futur immediat eteint; do
      attendu "$p-$v : sortie d'erreur d'ec (lignes, échecs de récupération)" "$(wc -l < "$T/ec-$p-$v.err") $(grep -c 'failed to fetch image' "$T/ec-$p-$v.err")" "$a"
    done
  done
  kill "$SERVE"; wait "$SERVE" 2> /dev/null; SERVE=
  echo "## bilan : $ko KO, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
