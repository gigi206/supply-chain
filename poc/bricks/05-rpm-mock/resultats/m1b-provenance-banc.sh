#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, M1b : banc de m1b-provenance.sh (préparé à sec le 20/11/2026), écrit avant tout passage de l'étape. Rien n'est écrit
# dans Zot ni dans le cluster : lectures seules (Zot en lecture anonyme, objets Tekton relus).
# A : syntaxe, shellcheck (seuls SC2015, comme m1b-pipeline.sh et m1b-signature.sh) ; constantes du script contre des sources
#     indépendantes : références écrites par m1b-signature.sh, sha256 des pipelines signées, digests du journal des PipelineRuns,
#     images des pas des tâches signées (05) et de publier-image (08), base de m1b-pipeline.sh, clé de Chains, liste revue.
# B : les vraies fonctions du script (sourcé, sans lancer) jouées sur les vraies attestations des deux images, vérifiées par cosign
#     avec la clé de Chains : les quatre PipelineRuns, cas nominal.
# C : deux dérivations indépendantes de l'attendu : dépendances tirées des objets Tekton (refSource, images des pas, résultats
#     *_ARTIFACT_INPUTS) et paramètres des specs des TaskRuns, contre deps_attendues et params_attendus.
# D : un écart par cas, sur une copie altérée de l'enveloppe de $N-o-1 (ou de $N-b-1) : code 1, libellé du KO attendu, écarts
#     imprimés avant le KO.
# Usage (racine du dépôt) :
#   DISTRO=rke2 KUBECONFIG=… mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-provenance-banc.sh <dossier-neuf> <m1b-provenance.sh>
export LC_ALL=C DISTRO=${DISTRO:-rke2}
B=$1; S05=$2
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
D05=$PWD/poc/bricks/05-rpm-mock
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m1b-provenance-banc.sh, $(date -u +%FT%TZ) ; m1b-provenance.sh $(sha256sum < "$S05" | cut -c1-64)"
# Le script sourcé dans des sous-shells : fonctions et constantes, sans lancer (garde BASH_SOURCE) ; T redirigé vers le banc
charger() { . "$S05"; set +e; T=$B/t; }

echo "## A : syntaxe, shellcheck, constantes contre des sources indépendantes"
egal "bash -n" "$(bash -n "$S05" && echo ok)" ok
egal "shellcheck : codes" "$(LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$S05" 2> /dev/null | grep -o 'SC[0-9]*' | sort -u | paste -sd' ')" SC2015
( charger
  egal "clé de Chains (sha256)" "$(sha256sum < "$CLE_CHAINS" | cut -c1-64)" "$CLE_CHAINS_SHA"
  egal "PREFETCH_REF = référence de m1b-signature.sh" "$(cat "$SIG/prefetch-racine-rpm.ref")" "$PREFETCH_REF"
  egal "CONSTRUIRE_REF = référence de m1b-signature.sh" "$(cat "$SIG/construire-racine-rpm.ref")" "$CONSTRUIRE_REF"
  egal "PUBLIER_REF = celle de m1b-pipeline.sh" "$(sed -n 's/^PUBLIER_REF=\$REG\([^ ]*\).*/\1/p' "$D05/m1b-pipeline.sh")" "${PUBLIER_REF#"$REG"}"
  for x in o b; do
    nom=$(v NOM "$x")
    egal "$nom : PIPELINE = référence de m1b-signature.sh" "$(cat "$SIG/$nom.ref")" "$(v PIPELINE "$x")"
    egal "$nom : SIGNEE = sha256 au journal SG4" "$(grep -c "^$nom-signee.yaml (travail) : sha256 $(v SIGNEE "$x") ; tkn pipeline verify : vérifiée$" "$D05/resultats/m1b-signature-sg4.log")" 1
    egal "$nom : IMAGE et DIGEST = journal des PipelineRuns (deux exécutions)" \
      "$(grep -c "^OK   digest publié égal au banc et aux essais (m1bt3 et mesure d'un autre jour) : $(v DIGEST "$x")$" "$D05/resultats/m1b-pipeline-pipeline.log") $(grep -c "^OK   dépôt publié : $(v IMAGE "$x")$" "$D05/resultats/m1b-pipeline-pipeline.log")" "2 2"
  done
  egal "AMORCE = image des pas des deux tâches signées" "$(for f in prefetch construire; do yq '.spec.steps[].image' "$D05/builders/$f-racine-rpm.signee.yaml"; done | sort -u)" "$AMORCE"
  egal "HORODATAGE = image du pas de publier-image signée (08)" "$(yq '.spec.steps[].image' "$here/politique/taches/publier-image.signee.yaml" | sort -u)" "$HORODATAGE"
  egal "BASE_b = base de m1b-pipeline.sh" "$(sed -n "s/^BASE_b='\(.*\)'$/\1/p" "$D05/m1b-pipeline.sh" | jq -r '"\(.uri | sub("^oci://"; ""))@\(.digest)"')" "$BASE_b"
  for r in "$PREFETCH_REF" "$CONSTRUIRE_REF" "$PUBLIER_REF"; do
    egal "${r##*/} dans la liste revue" "$(awk -v d="oci://${r%@*}:" -v x="${r#*@}" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
      b && $1 == "-" && $2 == "ref:" && $3 == x {t = 1} END {print t ? "oui" : "non"}' "$here/politique/porte/taches.yml")" oui
  done
  egal "SUBST_DIGEST : seule valeur substituée des deux pipelines signées" "$(for x in o b; do yq '[.spec.tasks[].params[]? | select(.value | tag == "!!str") | select(.value | test("[$][(]")) | .value] | join(" ")' "$SIG/$(v NOM "$x")-signee.yaml"; done | sort -u)" "$SUBST_DIGEST"
  echo "n=$n k=$k" > "$B/a.compte" )
eval "$(sed 's/^n=\([0-9]*\) k=\([0-9]*\)$/n=\1; k=\2/' "$B/a.compte")"

echo "## B : vraies attestations, vraies fonctions, quatre PipelineRuns"
( charger
  for x in o b; do
    nom=$(v NOM "$x"); s=$(v IMAGE "$x")@$(v DIGEST "$x"); c=$B/$x; mkdir -p "$c"
    r=0; cosign verify-attestation --key "$CLE_CHAINS" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" \
      "${s/$REG/$REG_HOTE}" < /dev/null > "$c/enveloppes.json" 2> "$c/cosign.err" || r=$?
    egal "$nom : cosign verify-attestation (clé de Chains), code et enveloppes" "$r $(grep -c . "$c/enveloppes.json")" "0 4"
    deps_attendues "$x" "$c/deps-attendues.txt"
    params_attendus "$SIG/$nom-signee.yaml" "$(v DIGEST "$x")" "$c/params-attendus.txt"
    egal "$nom : attendu (dépendances, paramètres)" "$(wc -l < "$c/deps-attendues.txt") $(wc -l < "$c/params-attendus.txt")" "$([ "$x" = b ] && echo 7 || echo 6) 20"
    for i in 1 2; do
      pr=$N-$x-$i; mkdir -p "$c/$pr"
      kubectl get pipelinerun -n builds "$pr" -o json < /dev/null > "$c/$pr/pr.json"
      kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o json < /dev/null > "$c/$pr/trs.json"
      uid=$(jq -r '.metadata.uid' "$c/$pr/pr.json"); echo "$uid" > "$c/$pr/uid"
      r=0; ( set -euo pipefail; controler_prov "$c/enveloppes.json" "$uid" "$s" "$c/deps-attendues.txt" "$c/params-attendus.txt" "$KATA_ATTENDU" "$c/$pr" ) \
        > "$c/$pr/sortie.txt" 2>&1 || r=$?
      sed 's/^/     /' "$c/$pr/sortie.txt" | cut -c1-200
      egal "$pr : controler_prov, code, OK, KO" "$r $(grep -c '^OK   ' "$c/$pr/sortie.txt") $(grep -c '^KO' "$c/$pr/sortie.txt")" "0 7 0"
    done
    egal "$nom : enveloppes d'un objet hors des deux PipelineRuns" "$(jq -r '.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId' "$c/enveloppes.json" \
      | while read -r u; do cat "$c/$N-$x-1/pr.json" "$c/$N-$x-2/pr.json" "$c/$N-$x-1/trs.json" "$c/$N-$x-2/trs.json" | jq -r '.metadata.uid // empty, .items[]?.metadata.uid' | grep -qx "$u" || echo "$u"; done | grep -c .)" 0
  done
  echo "n=$n k=$k" > "$B/b.compte" )
eval "$(sed 's/^n=\([0-9]*\) k=\([0-9]*\)$/n=\1; k=\2/' "$B/b.compte")"

echo "## C : attendu contre les objets Tekton (deux dérivations indépendantes)"
( charger
  for x in o b; do for i in 1 2; do
    pr=$N-$x-$i; c=$B/$x
    jq -r -s 'def dg: to_entries | map(.key + ":" + .value) | join(",");
      .[0] as $pr | .[1].items as $trs
      | "pipeline \($pr.status.provenance.refSource.uri) \($pr.status.provenance.refSource.digest | dg)",
        ($trs[] | "pipelineTask \(.status.provenance.refSource.uri) \(.status.provenance.refSource.digest | dg)"),
        ($trs[] | (.status.steps // []) + (.status.sidecars // []) | .[] | .imageID | "- oci://\(sub("@.*$"; "")) \(sub("^.*@"; ""))"),
        ($trs[] | .status.results[]? | select(.name | endswith("_ARTIFACT_INPUTS")) | .value | "inputs/result \(.uri) \(.digest)")' \
      "$c/$pr/pr.json" "$c/$pr/trs.json" | sort -u > "$c/$pr/deps-objets.txt"
    jq -r '.items[] | ((.spec.taskRef.params // []) | map(select(.name == "name")) | .[0].value // "-") as $t
      | .spec.params[]? | "\($t) \(.name) \(.value | if type == "string" then . else tojson end | @base64)"' "$c/$pr/trs.json" | params_lignes > "$c/$pr/params-objets.txt"
    comm -3 "$c/$pr/deps-objets.txt" <(sort "$c/deps-attendues.txt") | cut -c1-200 | sed 's/^/     écart : /'
    comm -3 "$c/$pr/params-objets.txt" <(sort "$c/params-attendus.txt") | cut -c1-200 | sed 's/^/     écart : /'
    egal "$pr : dépendances tirées des objets = deps_attendues" "$(sha256sum < "$c/$pr/deps-objets.txt" | cut -c1-64)" "$(sort "$c/deps-attendues.txt" | sha256sum | cut -c1-64)"
    egal "$pr : paramètres des specs des TaskRuns = params_attendus" "$(sha256sum < "$c/$pr/params-objets.txt" | cut -c1-64)" "$(sort "$c/params-attendus.txt" | sha256sum | cut -c1-64)"
    egal "$pr : runtimeClassName des specs des TaskRuns" "$(jq -r '.items[] | "\((.spec.taskRef.params // []) | map(select(.name == "name")) | .[0].value // "-"):\(.spec.podTemplate.runtimeClassName // "-")"' "$c/$pr/trs.json" | sort | paste -sd' ')" "$KATA_ATTENDU"
  done; done
  echo "n=$n k=$k" > "$B/c.compte" )
eval "$(sed 's/^n=\([0-9]*\) k=\([0-9]*\)$/n=\1; k=\2/' "$B/c.compte")"

echo "## D : un écart par cas (copies altérées des vraies enveloppes)"
envelopper() { jq -c '{payloadType: "application/vnd.in-toto+json", payload: (tojson | @base64), signatures: [{keyid: "", sig: "faux"}]}'; }
prep() { # nom image filtre-jq : enveloppes = la provenance de $N-<image>-1 modifiée, puis les autres enveloppes de l'image inchangées
  local u; u=$(cat "$B/$2/m1b-$2-1/uid"); mkdir -p "$B/d/$1"
  { jq -c --arg u "$u" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$B/$2/enveloppes.json" | jq -c "$3" | envelopper
    jq -c --arg u "$u" 'select(.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId != $u)' "$B/$2/enveloppes.json"; } > "$B/d/$1/enveloppes.json"
}
cas() { # nom image libellé-du-KO-attendu [params-attendus] : controler_prov sur $B/d/<nom>/enveloppes.json
  local c=$B/d/$1 r o p=${4:-$B/$2/params-attendus.txt}
  r=0; ( charger; set -euo pipefail
    controler_prov "$c/enveloppes.json" "$(cat "$B/$2/m1b-$2-1/uid")" "$(v IMAGE "$2")@$(v DIGEST "$2")" "$B/$2/deps-attendues.txt" "$p" "$KATA_ATTENDU" "$c"
  ) > "$c/sortie.txt" 2>&1 || r=$?
  grep -E '^(KO|enveloppes de l)' "$c/sortie.txt" | sed 's/^/     /' | cut -c1-200
  egal "$1 : code" "$r" 1
  egal "$1 : KO attendu" "$(grep -c "^KO   $3" "$c/sortie.txt")" 1
  o=$(grep -n -m1 '^écarts (comm -3' "$c/sortie.txt" | cut -d: -f1)
  egal "$1 : écarts imprimés avant le KO" "$([ -n "$o" ] && [ "$o" -lt "$(grep -n -m1 '^KO' "$c/sortie.txt" | cut -d: -f1)" ] && echo oui || echo non)" oui
}
contenu() { # tâche filtre : filtre jq appliqué au contenu (TaskRun) de la pipelineTask de cette tâche
  echo ".predicate.buildDefinition.resolvedDependencies |= map(if .name == \"pipelineTask\" then .content |= (@base64d | fromjson
    | if (.spec.taskRef.params | map(select(.name == \"name\")) | .[0].value) == \"$1\" then $2 else . end | tojson | @base64) else . end)"
}
dep() { echo ".predicate.buildDefinition.resolvedDependencies |= map(if $1 then $2 else . end)"; }
prep temoin o .
egal "témoin : copie réenveloppée sans changement, code" "$( ( charger; set -euo pipefail; mkdir -p "$B/d/temoin/t"
  controler_prov "$B/d/temoin/enveloppes.json" "$(cat "$B/o/m1b-o-1/uid")" "$IMAGE_o@$DIGEST_o" "$B/o/deps-attendues.txt" "$B/o/params-attendus.txt" "$KATA_ATTENDU" "$B/d/temoin/t" ) > /dev/null 2>&1 && echo 0 || echo 1)" 0
mkdir -p "$B/d/aucune"; jq -c --arg u "$(cat "$B/o/m1b-o-1/uid")" 'select(.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId != $u)' "$B/o/enveloppes.json" > "$B/d/aucune/enveloppes.json"
cas aucune o "enveloppes de l'invocation"
mkdir -p "$B/d/deux"; cat "$B/o/enveloppes.json" "$B/o/enveloppes.json" > "$B/d/deux/enveloppes.json"; cas deux o "enveloppes de l'invocation"
prep sujet o '.subject[0].digest.sha256 = ("0" * 64)'; cas sujet o "sujet"
prep sujet_autre_image o '.subject[0].name = "sc-stockage.poc.test:5000/builds/builders/rocky9-bootstrap"'; cas sujet_autre_image o "sujet"
prep buildtype o '.predicate.buildDefinition.buildType = "https://tekton.dev/chains/v2/slsa"'; cas buildtype o "buildType"
prep git_ajoutee o '.predicate.buildDefinition.resolvedDependencies += [{name: "inputs/result", uri: "git+https://exemple.test/x.git", digest: {sha1: ("1" * 40)}}]'
cas git_ajoutee o "source git"
prep amorce_digest o "$(dep '(.uri // "" | endswith("/amont/rockylinux/rockylinux")) and (.name // "-") != "inputs/result"' '.digest.sha256 = ("2" * 64)')"
cas amorce_digest o "resolvedDependencies"
prep tache_digest o "$(dep '(.uri // "" | endswith("/construire-racine-rpm"))' '.digest.sha256 = ("3" * 64)')"; cas tache_digest o "resolvedDependencies"
prep dep_en_trop o '.predicate.buildDefinition.resolvedDependencies += [{uri: "oci://sc-stockage.poc.test:5000/autre", digest: {sha256: ("4" * 64)}}]'
cas dep_en_trop o "resolvedDependencies"
prep base_retiree b "$(dep '(.name // "-") == "inputs/result"' 'empty')"; cas base_retiree b "resolvedDependencies"
prep base_en_trop o '.predicate.buildDefinition.resolvedDependencies += [{name: "inputs/result", uri: "oci://sc-stockage.poc.test:5000/amont/rockylinux/rockylinux", digest: {sha256: "ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2"}}]'
cas base_en_trop o "resolvedDependencies"
prep racine o "$(contenu construire-racine-rpm '.spec.params |= map(if .name == "racine" then .value = ("5" * 64) else . end)')"; cas racine o "paramètres des tâches"
prep liste o "$(contenu prefetch-racine-rpm '.spec.params |= map(if .name == "liste" then .value |= sub("\n"; "\nx\n") else . end)')"; cas liste o "paramètres des tâches"
prep digest_publier o "$(contenu publier-image '.spec.params |= map(if .name == "digest" then .value = "sha256:" + ("6" * 64) else . end)')"; cas digest_publier o "paramètres des tâches"
prep param_retire o "$(contenu construire-racine-rpm '.spec.params |= map(select(.name != "langue"))')"; cas param_retire o "paramètres des tâches"
prep kata_retire o "$(contenu construire-racine-rpm 'del(.spec.podTemplate.runtimeClassName)')"; cas kata_retire o "runtimeClassName"
prep kata_ailleurs o "$(contenu prefetch-racine-rpm '.spec.podTemplate.runtimeClassName = "kata"')"; cas kata_ailleurs o "runtimeClassName"
prep attendu_faux o .
( charger; params_attendus "$SIG/$NOM_o-signee.yaml" "sha256:$(printf '7%.0s' $(seq 64))" "$B/d/attendu_faux/params-faux.txt" )
cas attendu_faux o "paramètres des tâches" "$B/d/attendu_faux/params-faux.txt"

echo "# bilan : $n OK, $k KO ; fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
