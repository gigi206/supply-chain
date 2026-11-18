#!/usr/bin/env bash
# Brique 05, M4c : banc de l'étape provenance de m4c.sh (préparée à sec le 18/11/2026, accord permanent du 18/11), écrit avant tout
# passage. Rien n'est écrit dans Zot ni dans le cluster.
# A : insertions seules contre le m4c.sh d'avant (deux blocs : en-tête, bloc avant lancer) ; aucun nom du bloc déjà défini avant
#     ni dans commun.sh ; bash -n ; shellcheck : mêmes codes avant et après.
# B : les vraies fonctions attendu, echec, lire_prov, controler_prov et prov_attendue, extraites de m4c.sh, jouées hors ligne sur
#     des enveloppes fausses de la forme de Chains (payload en base64, contenu des pipelineTask en base64) : dépendances tirées de
#     l'attendu, contenu des pipelineTask = les vrais TaskRuns archivés par l'étape pipeline ($T) ; cas nominal (une enveloppe à
#     l'uid, une autre à un autre uid), puis un écart par cas ; dans chaque cas : code, libellé du KO attendu, écarts imprimés avant.
# C : constantes de l'étape contre les objets archivés par pipeline : dépendances dérivées des objets Tekton (refSource du
#     PipelineRun et des TaskRuns, images des pas, résultats *_ARTIFACT_INPUTS et CHAINS-GIT_*), paramètres et runtimeClassName des
#     specs des TaskRuns, aux deux exécutions ; images des pas des tâches signées ; références dans la liste revue.
# D : lecture seule, réelle (Zot en lecture anonyme, objets de s4d-deb-1 relus dans le cluster) : attestations de l'artefact deb de
#     la 06 vérifiées par cosign avec la clé de Chains ; controler_prov jouée sur l'enveloppe de s4d-deb-1 avec l'attendu dérivé de
#     ses objets Tekton par les mêmes fonctions qu'en C, et recoupé avec les constantes de s4d.sh : la forme réelle d'une pipeline à
#     trois tâches, source git et Kata passe par les mêmes jq.
# Usage (racine du dépôt) :
#   DISTRO=rke2 KUBECONFIG=… mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4c-provenance-banc.sh <dossier-neuf> <m4c.sh avant> <m4c.sh>
export LC_ALL=C DISTRO=${DISTRO:-rke2}
here=$PWD/poc/bricks/08-trust-plane   # comme dans m4c.sh (listee le lit)
. "$here/commun.sh" > /dev/null 2>&1   # P, REG, REG_HOTE, W, OUTILS, OUTILS_DIGEST, listee ; chargé avant set -u
set -uo pipefail
B=$1; AVANT=$2; COPIE=$3
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4c-provenance-banc.sh, $(date -u +%FT%TZ) ; m4c.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; m4c.sh $(sha256sum < "$COPIE" | cut -c1-64)"

echo "## A : insertions seules, noms neufs, syntaxe, shellcheck"
diff "$AVANT" "$COPIE" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
grep '^>' "$B/diff.txt" | cut -c3- > "$B/ajout.txt"
sed -n 's/^\([a-z_][a-z_0-9]*\)() {.*/\1/p; s/^\([A-Z_][A-Z_0-9]*\)=.*/\1/p' "$B/ajout.txt" | sort > "$B/noms.txt"
echo "noms définis par l'ajout : $(paste -sd' ' "$B/noms.txt")"
egal "noms de l'ajout déjà définis avant" "$(while read -r x; do grep -c -E "^($x\(\) \{|$x=)" "$AVANT"; done < "$B/noms.txt" | awk '{s += $1} END {print s + 0}')" 0
egal "commun.sh lisible" "$([ -s "$here/commun.sh" ] && echo oui)" oui
egal "noms de l'ajout déjà définis dans commun.sh" "$(while read -r x; do grep -c -E "^($x\(\) \{|$x=)" "$here/commun.sh"; done < "$B/noms.txt" | awk '{s += $1} END {print s + 0}')" 0
egal "bash -n" "$(bash -n "$COPIE" && echo ok)" ok
sc() { LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$1" 2>/dev/null | grep -o 'SC[0-9]*' | sort | uniq -c; }
egal "shellcheck : mêmes codes avant et après" "$(diff <(sc "$AVANT") <(sc "$COPIE") > /dev/null && echo mêmes || echo différents)" mêmes

echo "## B : controler_prov sur des enveloppes fausses (contenu des pipelineTask : vrais TaskRuns archivés)"
TA=$W/m4c-05   # $T de m4c.sh
{ grep -E '^(PREFETCH_IMAGE|OUTILS_IMAGE|IMAGE_OUTILLAGE|FERMETURE_RPM|FERMETURE_SOURCES|PACKAGING|PUBLIER_REF|EPOQUE|IMAGE|COMMIT|DEPOT_GIT|PIPELINE_REF|PREPARER_REF|CONSTRUIRE_REF|DIGEST_ESSAI|CLE_CHAINS_SHA|KATA_ATTENDU)=' "$COPIE"
  sed -n '/^attendu() {/p; /^echec() {/p; /^lire_prov() {/,/^}/p; /^controler_prov() {/,/^}/p; /^prov_attendue() {/,/^}/p' "$COPIE"; } > "$B/fonctions.sh"
egal "fonctions extraites (attendu, echec, lire_prov, controler_prov, prov_attendue)" \
  "$(grep -c -E '^(attendu|echec|lire_prov|controler_prov|prov_attendue)\(\) \{' "$B/fonctions.sh")" 5
egal "constantes extraites" "$(grep -c -E '^[A-Z_][A-Z_0-9]*=' "$B/fonctions.sh")" 17
mkdir -p "$B/attendu"
( . "$B/fonctions.sh"; set -euo pipefail; prov_attendue "$B/attendu" )
egal "attendu : dépendances, paramètres" "$(wc -l < "$B/attendu/deps-attendues.txt") $(wc -l < "$B/attendu/params-attendus.txt")" "11 8"
sed 's/^/     /' "$B/attendu/deps-attendues.txt" "$B/attendu/params-attendus.txt" | cut -c1-200
for i in 1 2; do for x in preparer construire publier; do
  egal "TaskRun archivé m4c-rpm-$i-$x lisible" "$(jq -r '.kind' "$TA/m4c-rpm-$i-$x.tr.json")" TaskRun
done; done
U=95d9debd-0000-4000-8000-000000000001; AUTRE=95d9debd-0000-4000-8000-000000000002
fabriquer() { # uid exécution : provenance fausse de la forme de Chains (sortie : JSON compact) ; dépendances = attendu ; contenu
  # des pipelineTask = TaskRun archivé de l'exécution dont la référence de bundle est l'uri@digest de la dépendance
  ( . "$B/fonctions.sh"
    jq -nc --arg u "$1" --arg sn "$IMAGE" --arg sd "${DIGEST_ESSAI#sha256:}" --rawfile deps "$B/attendu/deps-attendues.txt" \
      --slurpfile trs <(cat "$TA/m4c-rpm-$2-preparer.tr.json" "$TA/m4c-rpm-$2-construire.tr.json" "$TA/m4c-rpm-$2-publier.tr.json") '
      def ligne: split(" ") | {name: .[0], uri: .[1], digest: (.[2] | split(":") | {(.[0]): .[1]})} | if .name == "-" then del(.name) else . end;
      def bundle: .spec.taskRef.params | map(select(.name == "bundle")) | .[0].value;
      ($deps | split("\n") | map(select(. != "") | ligne)
        | map(if .name == "pipelineTask" then . as $x | . + {content: ($trs | map(select(bundle == ($x.uri + "@sha256:" + $x.digest.sha256)))
          | if length == 1 then .[0] else error("TaskRun introuvable pour " + $x.uri) end | tojson | @base64)} else . end)) as $d
      | {_type: "https://in-toto.io/Statement/v1", subject: [{name: $sn, digest: {sha256: $sd}}], predicateType: "https://slsa.dev/provenance/v1",
        predicate: {buildDefinition: {buildType: "https://tekton.dev/chains/v2/slsa-tekton", externalParameters: {}, resolvedDependencies: $d},
          runDetails: {builder: {id: "https://tekton.dev/chains/v2"}, metadata: {invocationId: $u, startedOn: "2026-11-18T15:39:39Z",
            finishedOn: "2026-11-18T15:41:00Z"}}}}' )
}
envelopper() { jq -c '{payloadType: "application/vnd.in-toto+json", payload: (tojson | @base64), signatures: [{keyid: "", sig: "faux"}]}'; }
fabriquer "$U" 1 > "$B/prov-u.json"; fabriquer "$AUTRE" 2 > "$B/prov-autre.json"
egal "provenances fausses bâties (deux uid)" "$(cat "$B/prov-u.json" "$B/prov-autre.json" | jq -r '.predicate.runDetails.metadata.invocationId' | paste -sd' ')" "$U $AUTRE"
egal "contenus pipelineTask : TaskRuns archivés (noms)" "$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson | .metadata.name' "$B/prov-u.json" | sort | paste -sd' ')" \
  "m4c-rpm-1-construire m4c-rpm-1-preparer m4c-rpm-1-publier"
cas() { # nom code-attendu libellé-du-KO-attendu (vide si nominal) : enveloppes $B/<nom>/enveloppes.json (préparées avant)
  local c=$B/$1 r o
  r=0; ( . "$B/fonctions.sh"; set -euo pipefail
    controler_prov "$c/enveloppes.json" "$U" "$IMAGE@$DIGEST_ESSAI" "$B/attendu/deps-attendues.txt" "$B/attendu/params-attendus.txt" \
      "$KATA_ATTENDU" "git+$DEPOT_GIT sha1:$COMMIT" "$c"
  ) > "$c/sortie.txt" 2>&1 || r=$?
  sed 's/^/     /' "$c/sortie.txt" | cut -c1-200
  egal "$1 : code" "$r" "$2"
  if [ -n "$3" ]; then
    egal "$1 : KO attendu" "$(grep -c "^KO   $3" "$c/sortie.txt")" 1
    o=$(grep -n -m1 '^écarts (comm -3' "$c/sortie.txt" | cut -d: -f1)
    egal "$1 : écarts imprimés avant le KO" "$([ -n "$o" ] && [ "$o" -lt "$(grep -n -m1 '^KO' "$c/sortie.txt" | cut -d: -f1)" ] && echo oui || echo non)" oui
  else
    egal "$1 : OK, aucun KO" "$(grep -c '^OK   ' "$c/sortie.txt") $(grep -c '^KO' "$c/sortie.txt")" "7 0"
  fi
}
prep() { # nom filtre-jq-sur-la-provenance-à-l'uid : enveloppes = provenance modifiée, puis celle de l'autre uid
  mkdir -p "$B/$1"; { jq -c "$2" "$B/prov-u.json" | envelopper; envelopper < "$B/prov-autre.json"; } > "$B/$1/enveloppes.json"
}
contenu() { # tâche filtre : filtre jq appliqué au contenu (TaskRun) de la pipelineTask de cette tâche
  echo ".predicate.buildDefinition.resolvedDependencies |= map(if .name == \"pipelineTask\" then .content |= (@base64d | fromjson
    | if (.spec.taskRef.params | map(select(.name == \"name\")) | .[0].value) == \"$1\" then $2 else . end | tojson | @base64) else . end)"
}
dep() { # filtre-de-sélection modification : sur les dépendances choisies
  echo ".predicate.buildDefinition.resolvedDependencies |= map(if $1 then $2 else . end)"
}
prep nominal .; cas nominal 0 ""
mkdir -p "$B/aucune"; envelopper < "$B/prov-autre.json" > "$B/aucune/enveloppes.json"; cas aucune 1 "enveloppes de l'invocation"
mkdir -p "$B/deux"; { envelopper < "$B/prov-u.json"; envelopper < "$B/prov-u.json"; envelopper < "$B/prov-autre.json"; } > "$B/deux/enveloppes.json"
cas deux 1 "enveloppes de l'invocation"
prep sujet '.subject[0].digest.sha256 = ("0" * 64)'; cas sujet 1 "sujet"
prep buildtype '.predicate.buildDefinition.buildType = "https://tekton.dev/chains/v2/slsa"'; cas buildtype 1 "buildType"
prep git_absente '.predicate.buildDefinition.resolvedDependencies |= map(select(.uri | startswith("git+") | not))'; cas git_absente 1 "source"
prep commit_faux "$(dep '(.uri | startswith("git+"))' '.digest.sha1 = ("1" * 40)')"; cas commit_faux 1 "source"
prep entree_digest "$(dep '(.uri | endswith("/builds/fermetures/sample-app-sources"))' '.digest.sha256 = ("2" * 64)')"; cas entree_digest 1 "resolvedDependencies"
prep image_pas "$(dep '(.uri | endswith("/essais-05/mock-rocky9"))' '.digest.sha256 = ("3" * 64)')"; cas image_pas 1 "resolvedDependencies"
prep dep_en_trop '.predicate.buildDefinition.resolvedDependencies += [{uri: "oci://sc-stockage.poc.test:5000/autre", digest: {sha256: ("4" * 64)}}]'
cas dep_en_trop 1 "resolvedDependencies"
prep epoque "$(contenu construire-rpm '.spec.params |= map(if .name == "epoque" then .value = "1794787200" else . end)')"
egal "epoque : valeur changée dans l'enveloppe" "$(jq -r '.payload | @base64d | fromjson | .predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson | .spec.params[]? | select(.name == "epoque") | .value' "$B/epoque/enveloppes.json" | sort | paste -sd' ')" "1793229566 1794787200"
cas epoque 1 "paramètres des tâches"
prep digest_publier "$(contenu publier-image '.spec.params |= map(if .name == "digest" then .value = "sha256:" + ("5" * 64) else . end)')"
cas digest_publier 1 "paramètres des tâches"
prep kata_retire "$(contenu construire-rpm 'del(.spec.podTemplate.runtimeClassName)')"; cas kata_retire 1 "runtimeClassName"
prep kata_ailleurs "$(contenu publier-image '.spec.podTemplate.runtimeClassName = "kata"')"; cas kata_ailleurs 1 "runtimeClassName"

echo "## C : constantes de l'étape contre les objets archivés par pipeline"
deps_objets() { # PipelineRun TaskRun… : dépendances qu'en tirerait Chains (refSource, images des pas, *_ARTIFACT_INPUTS, CHAINS-GIT_*)
  jq -r -s 'def dg: to_entries | map(.key + ":" + .value) | join(",");
    .[0] as $pr | .[1:] as $trs
    | "pipeline \($pr.status.provenance.refSource.uri) \($pr.status.provenance.refSource.digest | dg)",
      ($trs[] | "pipelineTask \(.status.provenance.refSource.uri) \(.status.provenance.refSource.digest | dg)"),
      ($trs[] | (.status.steps // []) + (.status.sidecars // []) | .[] | .imageID | "- oci://\(sub("@.*$"; "")) \(sub("^.*@"; ""))"),
      ($trs[] | .status.results[]? | select(.name | endswith("_ARTIFACT_INPUTS")) | .value | "inputs/result \(.uri) \(.digest)"),
      ($trs[] | (.status.results // []) | map({key: .name, value: .value}) | from_entries | select(has("CHAINS-GIT_URL"))
        | "inputs/result git+\(.["CHAINS-GIT_URL"]) sha1:\(.["CHAINS-GIT_COMMIT"])")' "$@" | sort -u
}
params_objets() { # TaskRun… : « tâche paramètre valeur » des specs, valeurs à saut de ligne traitées comme lire_prov
  jq -r '((.spec.taskRef.params // []) | map(select(.name == "name")) | .[0].value // "-") as $t
    | .spec.params[]? | "\($t) \(.name) \(.value | if type == "string" then . else tojson end | @base64)"' "$@" \
    | while read -r t x v; do
        if [ "$(base64 -d <<< "$v" | wc -l)" -gt 0 ]; then
          echo "$t $x sha256:$(base64 -d <<< "$v" | sed '/^$/d' | sha256sum | cut -c1-64) ($(base64 -d <<< "$v" | sed '/^$/d' | wc -l) lignes non vides)"
        else echo "$t $x $(base64 -d <<< "$v")"; fi
      done | sort
}
kata_objets() { jq -r '"\((.spec.taskRef.params // []) | map(select(.name == "name")) | .[0].value // "-"):\(.spec.podTemplate.runtimeClassName // "-")"' "$@" | sort | paste -sd' '; }
( . "$B/fonctions.sh"
  egal "clé de Chains (sha256)" "$(sha256sum < "$here/resultats/chains-cle-publique.pem" | cut -c1-64)" "$CLE_CHAINS_SHA"
  for i in 1 2; do
    trs=("$TA/m4c-rpm-$i-preparer.tr.json" "$TA/m4c-rpm-$i-construire.tr.json" "$TA/m4c-rpm-$i-publier.tr.json")
    deps_objets "$TA/pr-m4c-rpm-$i-etat.json" "${trs[@]}" > "$B/deps-objets-$i.txt"
    params_objets "${trs[@]}" > "$B/params-objets-$i.txt"
    comm -3 "$B/deps-objets-$i.txt" <(sort "$B/attendu/deps-attendues.txt") | cut -c1-200 | sed 's/^/     écart : /'
    comm -3 "$B/params-objets-$i.txt" <(sort "$B/attendu/params-attendus.txt") | cut -c1-200 | sed 's/^/     écart : /'
    egal "m4c-rpm-$i : dépendances dérivées des objets égales à l'attendu (sha256 des listes triées)" \
      "$(sha256sum < "$B/deps-objets-$i.txt" | cut -c1-64)" "$(sort "$B/attendu/deps-attendues.txt" | sha256sum | cut -c1-64)"
    egal "m4c-rpm-$i : paramètres des specs des TaskRuns égaux à l'attendu (sha256 des listes triées)" \
      "$(sha256sum < "$B/params-objets-$i.txt" | cut -c1-64)" "$(sort "$B/attendu/params-attendus.txt" | sha256sum | cut -c1-64)"
    egal "m4c-rpm-$i : runtimeClassName des specs des TaskRuns" "$(kata_objets "${trs[@]}")" "$KATA_ATTENDU"
  done
  egal "images des pas de preparer-rpm signée" "$(yq '.spec.steps[].image' "$TA/preparer-rpm-signee.yaml" | sort -u | paste -sd' ')" \
    "$(printf '%s\n' "$PREFETCH_IMAGE" "$OUTILS_IMAGE" | sort | paste -sd' ')"
  egal "image du pas de construire-rpm signée" "$(yq '.spec.steps[].image' "$TA/construire-rpm-signee.yaml")" "$IMAGE_OUTILLAGE"
  egal "image du pas de publier-image signée (08)" "$(yq '.spec.steps[].image' "$here/politique/taches/publier-image.signee.yaml" | sort -u)" "$OUTILS_IMAGE"
  for x in "$PREPARER_REF" "$CONSTRUIRE_REF" "$PUBLIER_REF"; do
    egal "${x##*/} dans la liste revue" "$(listee "$x" && echo oui || echo non)" oui
  done
  egal "pipeline d'etape_taches (copie locale) : référence" "$(cat "$TA/sample-app-rpm.ref")" "$PIPELINE_REF"
  echo "n=$n k=$k" > "$B/c.compte" )
eval "$(sed 's/^n=\([0-9]*\) k=\([0-9]*\)$/n=\1; k=\2/' "$B/c.compte")"

echo "## D : forme réelle, attestations de l'artefact deb de s4d-deb-1 (06), lecture seule"
mkdir -p "$B/deb"
kubectl get pipelinerun -n builds s4d-deb-1 -o json < /dev/null > "$B/deb/pr.json"
for x in preparer construire publier; do
  kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=s4d-deb-1,tekton.dev/pipelineTask=$x" -o json < /dev/null | jq '.items[0]' > "$B/deb/tr-$x.json"
done
u=$(jq -r '.metadata.uid' "$B/deb/pr.json"); d=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$B/deb/pr.json")
DEB=$REG/builds/sample-app-deb@$d
echo "s4d-deb-1 : uid $u ; artefact $DEB"
dtr=("$B/deb/tr-preparer.json" "$B/deb/tr-construire.json" "$B/deb/tr-publier.json")
deps_objets "$B/deb/pr.json" "${dtr[@]}" > "$B/deb/deps-attendues.txt"
params_objets "${dtr[@]}" > "$B/deb/params-attendus.txt"
kd=$(kata_objets "${dtr[@]}")
src=$(jq -r '(.status.results // []) | map({key: .name, value: .value}) | from_entries | "git+\(.["CHAINS-GIT_URL"]) sha1:\(.["CHAINS-GIT_COMMIT"])"' "$B/deb/tr-preparer.json")
echo "attendu deb dérivé des objets : $(wc -l < "$B/deb/deps-attendues.txt") dépendances, $(wc -l < "$B/deb/params-attendus.txt") paramètres ; $kd ; $src"
sed 's/^/     /' "$B/deb/deps-attendues.txt" | cut -c1-200
egal "recoupement : entrées et image de build de s4d.sh dans l'attendu dérivé" "$(for x in FERMETURE_DEB FERMETURE_SOURCES PACKAGING BUILDER; do
    v=$(sed -n "s/^$x=\\\$REG\\([^ ]*\\).*/\\1/p" poc/bricks/06-deb-sbuild/s4d.sh); grep -c -F -e "oci://$REG${v%@*} ${v#*@}" "$B/deb/deps-attendues.txt"; done | paste -sd' ')" "1 1 1 1"
egal "recoupement : source égale à celle de m4c.sh" "$src" "$( . "$B/fonctions.sh"; echo "git+$DEPOT_GIT sha1:$COMMIT")"
egal "recoupement : runtimeClassName des TaskRuns deb" "$kd" "construire-deb:kata preparer-deb:- publier-image:-"
r=0; cosign verify-attestation --key "$here/resultats/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true \
  --registry-cacert "$P/ca-poc.crt" "${DEB/$REG/$REG_HOTE}" < /dev/null > "$B/deb/enveloppes.json" 2> "$B/deb/cosign.err" || r=$?
egal "cosign verify-attestation (clé de Chains) sur l'artefact deb : code" "$r" 0
echo "enveloppes valides : $(grep -c . "$B/deb/enveloppes.json") ; invocationId : $(jq -r '.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId' "$B/deb/enveloppes.json" | sort | paste -sd' ') (relevé)"
echo "contenu des pipelineTask de s4d-deb-1 : clés de premier niveau, kind (relevé) : $(jq -r --arg u "$u" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)
  | .predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson | "\(keys | join(",")) \(.kind // "-")"' "$B/deb/enveloppes.json" | sort -u | paste -sd' ')"
r=0; ( . "$B/fonctions.sh"; set -euo pipefail
  controler_prov "$B/deb/enveloppes.json" "$u" "$DEB" "$B/deb/deps-attendues.txt" "$B/deb/params-attendus.txt" "$kd" "$src" "$B/deb"
) > "$B/deb/sortie.txt" 2>&1 || r=$?
sed 's/^/     /' "$B/deb/sortie.txt" | cut -c1-200
egal "controler_prov sur s4d-deb-1 : code, OK, KO" "$r $(grep -c '^OK   ' "$B/deb/sortie.txt") $(grep -c '^KO' "$B/deb/sortie.txt")" "0 7 0"

echo "# bilan : $n OK, $k KO ; fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
