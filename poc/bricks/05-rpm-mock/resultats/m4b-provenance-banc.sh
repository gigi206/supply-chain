#!/usr/bin/env bash
# Brique 05, M4b : banc de l'étape provenance de m4b.sh (préparée à sec le 18/11/2026, accord permanent du 18/11), écrit avant tout
# passage. Rien n'est écrit dans Zot ni dans le cluster.
# A : insertions seules contre le m4b.sh d'avant (deux blocs : en-tête, bloc avant lancer) ; aucun nom du bloc déjà défini avant ;
#     bash -n ; shellcheck : mêmes codes avant et après.
# B : les vraies fonctions attendu, echec, lire_prov, controler_prov et prov_attendue, extraites de m4b.sh, jouées hors ligne sur
#     des enveloppes fausses de la forme de Chains (payload en base64, contenu des pipelineTask en base64), bâties à partir des
#     valeurs attendues du rpm (vraie liste, vrai verrou) : cas nominal (une enveloppe à l'uid, une autre à un autre uid), puis un
#     écart par cas (aucune enveloppe à l'uid, deux, sujet faux, buildType faux, dépendance retirée, digest de l'image de bootstrap
#     faux, dépendance en trop, une ligne de la liste changée, paramètre en trop) ; dans chaque cas : code, libellé du KO attendu,
#     écarts imprimés avant le KO ; enfin une ligne vide ajoutée à la liste, acceptée (règle du retrait des lignes vides, relevée).
# C : constantes de l'étape contre les fichiers archivés : clé de Chains, images des deux tâches signées, deux tâches dans la liste
#     revue, liste sans ligne vide ; paramètres attendus égaux à ceux de la pipeline signée par etape_taches (copie locale de $T).
# D : lecture seule, réelle (Zot en lecture anonyme, un PipelineRun relu) : attestations de la fermeture deb de la 06 vérifiées par
#     cosign avec la clé de Chains ; controler_prov jouée sur l'enveloppe de s4b-deb-1, avec l'attendu tiré des journaux archivés de
#     la 06 : la forme réelle des enveloppes de Chains passe par les mêmes jq.
# Usage (racine du dépôt) :
#   DISTRO=rke2 KUBECONFIG=… mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4b-provenance-banc.sh <dossier-neuf> <m4b.sh avant> <m4b.sh>
export LC_ALL=C DISTRO=${DISTRO:-rke2}
here=$PWD/poc/bricks/08-trust-plane   # comme dans m4b.sh (commun.sh ne le définit pas ; listee le lit)
. "$here/commun.sh" > /dev/null 2>&1   # P, REG, REG_HOTE, W, listee ; chargé avant set -u (sortie silencieuse sinon)
set -uo pipefail
B=$1; AVANT=$2; COPIE=$3
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4b-provenance-banc.sh, $(date -u +%FT%TZ) ; m4b.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; m4b.sh $(sha256sum < "$COPIE" | cut -c1-64)"

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

echo "## B : controler_prov sur des enveloppes fausses"
R=poc/bricks/05-rpm-mock/resultats
{ grep -E '^(PIPELINE_REF|PREFETCH_REF|PUBLIER_REF|IMAGE|HORODATAGE|FP_ROCKY|LISTE_SHA|REPOMD_V2|DEPOT_FERMETURE|FERMETURE_RPM|CLE_CHAINS_SHA|VERROU_SHA)=' "$COPIE"
  echo "LISTE=$R/m4b-liste.txt VERROU_SRC=$R/s1-verrou_derivee.json"
  sed -n '/^attendu() {/p; /^echec() {/p; /^lire_prov() {/,/^}/p; /^controler_prov() {/,/^}/p; /^prov_attendue() {/,/^}/p' "$COPIE"; } > "$B/fonctions.sh"
egal "fonctions extraites (attendu, echec, lire_prov, controler_prov, prov_attendue)" \
  "$(grep -c -E '^(attendu|echec|lire_prov|controler_prov|prov_attendue)\(\) \{' "$B/fonctions.sh")" 5
egal "constantes extraites" "$(grep -c -E '^[A-Z_][A-Z_0-9]*=' "$B/fonctions.sh")" 13
src=$(jq -r '.config.bootstrap_image' "$R/s1-verrou_derivee.json"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$R/s1-verrou_derivee.json")
mkdir -p "$B/attendu"
( . "$B/fonctions.sh"; set -euo pipefail; prov_attendue "$src" "$dos" "$B/attendu" )
egal "attendu : dépendances, paramètres" "$(wc -l < "$B/attendu/deps-attendues.txt") $(wc -l < "$B/attendu/params-attendus.txt")" "6 6"
sed 's/^/     /' "$B/attendu/deps-attendues.txt" "$B/attendu/params-attendus.txt" | cut -c1-200
U=2f1c276d-0000-4000-8000-000000000001; AUTRE=2f1c276d-0000-4000-8000-000000000002
fabriquer() { # uid : une provenance fausse de la forme de Chains, bâtie avec les valeurs attendues (sortie : JSON compact)
  ( . "$B/fonctions.sh"
    jq -nc --arg u "$1" --arg sn "$DEPOT_FERMETURE" --arg sd "${FERMETURE_RPM#sha256:}" --rawfile liste "$LISTE" --arg src "$src" --arg dos "$dos" \
      --arg fp "$FP_ROCKY" --arg repomd "$REPOMD_V2" --arg depot "$DEPOT_FERMETURE" --arg pipe "$PIPELINE_REF" --arg pre "$PREFETCH_REF" \
      --arg pub "$PUBLIER_REF" --arg image "$IMAGE" --arg horo "$HORODATAGE" '
      def sansd(r): r | sub("@.*$"; ""); def hex(r): r | sub("^.*@sha256:"; "");
      def dep(nom; r): {name: nom, uri: sansd(r), digest: {sha256: hex(r)}};
      def img(r): {uri: ("oci://" + sansd(r)), digest: {sha256: hex(r)}};
      def tache(nom; r; ps): dep("pipelineTask"; r) + {content: ({spec: {taskRef: {resolver: "bundles", params: [{name: "bundle", value: r},
        {name: "name", value: nom}, {name: "kind", value: "task"}]}, params: ps}} | tojson | @base64)};
      {_type: "https://in-toto.io/Statement/v1", subject: [{name: $sn, digest: {sha256: $sd}}], predicateType: "https://slsa.dev/provenance/v1",
        predicate: {buildDefinition: {buildType: "https://tekton.dev/chains/v2/slsa-tekton", externalParameters: {}, resolvedDependencies: [
          dep("pipeline"; $pipe),
          tache("prefetch-rpm"; $pre; [{name: "liste", value: $liste}, {name: "source", value: $src}, {name: "dossier", value: $dos},
            {name: "empreinte", value: $fp}, {name: "repomd", value: $repomd}]),
          img($image), tache("publier-fermeture"; $pub; [{name: "depot", value: $depot}]), img($horo),
          {name: "inputs/result", uri: ("oci://" + sansd($src)), digest: {sha256: hex($src)}}]},
          runDetails: {builder: {id: "https://tekton.dev/chains/v2"}, metadata: {invocationId: $u, startedOn: "2026-11-18T11:01:19Z",
            finishedOn: "2026-11-18T11:03:11Z"}}}}' )
}
envelopper() { jq -c '{payloadType: "application/vnd.in-toto+json", payload: (tojson | @base64), signatures: [{keyid: "", sig: "faux"}]}'; }
fabriquer "$U" > "$B/prov-u.json"; fabriquer "$AUTRE" > "$B/prov-autre.json"
egal "provenances fausses bâties (deux uid)" "$(cat "$B/prov-u.json" "$B/prov-autre.json" | jq -r '.predicate.runDetails.metadata.invocationId' | paste -sd' ')" "$U $AUTRE"
cas() { # nom code-attendu libellé-du-KO-attendu (vide si nominal) : enveloppes $B/<nom>/enveloppes.json (préparées avant)
  local c=$B/$1 r o
  r=0; ( . "$B/fonctions.sh"; set -euo pipefail
    controler_prov "$c/enveloppes.json" "$U" "$DEPOT_FERMETURE@$FERMETURE_RPM" "$B/attendu/deps-attendues.txt" "$B/attendu/params-attendus.txt" "$c"
  ) > "$c/sortie.txt" 2>&1 || r=$?
  sed 's/^/     /' "$c/sortie.txt" | cut -c1-200
  egal "$1 : code" "$r" "$2"
  if [ -n "$3" ]; then
    egal "$1 : KO attendu" "$(grep -c "^KO   $3" "$c/sortie.txt")" 1
    o=$(grep -n -m1 '^écarts (comm -3' "$c/sortie.txt" | cut -d: -f1)
    egal "$1 : écarts imprimés avant le KO" "$([ -n "$o" ] && [ "$o" -lt "$(grep -n -m1 '^KO' "$c/sortie.txt" | cut -d: -f1)" ] && echo oui || echo non)" oui
  else
    egal "$1 : OK, aucun KO" "$(grep -c '^OK   ' "$c/sortie.txt") $(grep -c '^KO' "$c/sortie.txt")" "5 0"
  fi
}
prep() { # nom filtre-jq-sur-la-provenance-à-l'uid [enveloppes en plus] : enveloppes = provenance modifiée, puis celle de l'autre uid
  mkdir -p "$B/$1"; { jq -c "$2" "$B/prov-u.json" | envelopper; envelopper < "$B/prov-autre.json"; } > "$B/$1/enveloppes.json"
}
contenu() { echo ".predicate.buildDefinition.resolvedDependencies |= map(if .name == \"pipelineTask\" then .content |= (@base64d | fromjson | $1 | tojson | @base64) else . end)"; }
prep nominal .; cas nominal 0 ""
mkdir -p "$B/aucune"; envelopper < "$B/prov-autre.json" > "$B/aucune/enveloppes.json"; cas aucune 1 "enveloppes de l'invocation"
mkdir -p "$B/deux"; { envelopper < "$B/prov-u.json"; envelopper < "$B/prov-u.json"; envelopper < "$B/prov-autre.json"; } > "$B/deux/enveloppes.json"
cas deux 1 "enveloppes de l'invocation"
prep sujet '.subject[0].digest.sha256 = ("0" * 64)'; cas sujet 1 "sujet"
prep buildtype '.predicate.buildDefinition.buildType = "https://tekton.dev/chains/v2/slsa"'; cas buildtype 1 "buildType"
prep dep_retiree '.predicate.buildDefinition.resolvedDependencies |= map(select(.name != "inputs/result"))'; cas dep_retiree 1 "resolvedDependencies"
prep dep_digest '.predicate.buildDefinition.resolvedDependencies |= map(if .name == "inputs/result" then .digest.sha256 = ("1" * 64) else . end)'
cas dep_digest 1 "resolvedDependencies"
prep dep_en_trop '.predicate.buildDefinition.resolvedDependencies += [{uri: "oci://sc-stockage.poc.test:5000/autre", digest: {sha256: ("2" * 64)}}]'
cas dep_en_trop 1 "resolvedDependencies"
prep liste "$(contenu 'if (.spec.taskRef.params[1].value == "prefetch-rpm") then .spec.params |= map(if .name == "liste" then .value |= sub(" 1116611\n"; " 1116612\n") else . end) else . end')"
egal "liste : une ligne changée dans l'enveloppe" "$(jq -r '.payload | @base64d | fromjson | .predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson | .spec.params[] | select(.name == "liste") | .value' "$B/liste/enveloppes.json" | grep -c ' 1116612$')" 1
cas liste 1 "paramètres des tâches"
prep param_en_trop "$(contenu 'if (.spec.taskRef.params[1].value == "publier-fermeture") then .spec.params += [{name: "autre", value: "x"}] else . end')"
cas param_en_trop 1 "paramètres des tâches"
prep ligne_vide "$(contenu 'if (.spec.taskRef.params[1].value == "prefetch-rpm") then .spec.params |= map(if .name == "liste" then .value |= ("\n" + .) else . end) else . end')"
cas ligne_vide 0 ""

echo "## C : constantes de l'étape contre les fichiers archivés"
( . "$B/fonctions.sh"
  egal "clé de Chains (sha256)" "$(sha256sum < "$here/resultats/chains-cle-publique.pem" | cut -c1-64)" "$CLE_CHAINS_SHA"
  egal "image du pas de publier-fermeture (tâche signée de la 08)" "$(yq '.spec.steps[].image' "$here/politique/taches/publier-fermeture.signee.yaml")" "$HORODATAGE"
  egal "image du pas de prefetch-rpm (tâche signée de la 05)" "$(yq '.spec.steps[].image' poc/bricks/05-rpm-mock/fermeture/prefetch-rpm.signee.yaml)" "$IMAGE"
  for x in "$PREFETCH_REF" "$PUBLIER_REF"; do
    egal "${x##*/} dans la liste revue" "$(listee "$x" && echo oui || echo non)" oui
  done
  egal "liste : sans ligne vide, 222 lignes" "$(sed '/^$/d' "$LISTE" | sha256sum | cut -c1-64) $(grep -c . "$LISTE")" "$LISTE_SHA 222"
  egal "verrou (sha256)" "$(sha256sum < "$VERROU_SRC" | cut -c1-64)" "$VERROU_SHA"
  egal "pipeline signée d'etape_taches (copie locale) : référence" "$(cat "$W/m4b-05/prefetch-rpm-sample-app.ref")" "$PIPELINE_REF"
  yq -o=json -I=0 '.spec.tasks[] | {"t": .taskRef.params[1].value, "p": .params}' "$W/m4b-05/prefetch-rpm-sample-app-signee.yaml" \
    | jq -r '.t as $t | .p[] | "\($t) \(.name) \(.value | @base64)"' | while read -r t x v; do
        if [ "$(base64 -d <<< "$v" | wc -l)" -gt 0 ]; then
          echo "$t $x sha256:$(base64 -d <<< "$v" | sed '/^$/d' | sha256sum | cut -c1-64) ($(base64 -d <<< "$v" | sed '/^$/d' | wc -l) lignes non vides)"
        else echo "$t $x $(base64 -d <<< "$v")"; fi
      done | sort > "$B/params-pipeline.txt"
  comm -3 "$B/params-pipeline.txt" <(sort "$B/attendu/params-attendus.txt") | cut -c1-200 | sed 's/^/     écart : /'
  egal "paramètres attendus égaux à ceux de la pipeline signée" "$(sha256sum < "$B/params-pipeline.txt" | cut -c1-64)" "$(sort "$B/attendu/params-attendus.txt" | sha256sum | cut -c1-64)"
  echo "n=$n k=$k" > "$B/c.compte" )
eval "$(sed 's/^n=\([0-9]*\) k=\([0-9]*\)$/n=\1; k=\2/' "$B/c.compte")"

echo "## D : forme réelle, attestations de la fermeture deb de la 06 (lecture seule)"
DEB=$REG/builds/fermetures/sample-app-deb@sha256:bb7599a2e1cde30770fdb4405a5f9cce94de5ea5b12c358e512dfbe7d5b9f290   # s4b-provenance.log (06)
mkdir -p "$B/deb"
r=0; cosign verify-attestation --key "$here/resultats/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true \
  --registry-cacert "$P/ca-poc.crt" "${DEB/$REG/$REG_HOTE}" < /dev/null > "$B/deb/enveloppes.json" 2> "$B/deb/cosign.err" || r=$?
egal "cosign verify-attestation (clé de Chains) sur la fermeture deb : code" "$r" 0
echo "enveloppes valides : $(grep -c . "$B/deb/enveloppes.json") ; invocationId : $(jq -r '.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId' "$B/deb/enveloppes.json" | sort | paste -sd' ') (relevé)"
u=$(kubectl get pipelinerun -n builds s4b-deb-1 -o jsonpath='{.metadata.uid}' < /dev/null)
echo "s4b-deb-1 : uid $u"
# attendu deb, tiré des journaux archivés de la 06 (chaque ligne y est recherchée ci-dessous)
printf '%s\n' "pipeline $REG/tekton/pipelines/prefetch-deb-sample-app sha256:206a539e1b1cd57edaec1ae917fccec5390f4de379f496ff68934bcad3aadd39" \
  "pipelineTask $REG/tekton/tasks/prefetch-deb sha256:4dac0609a5d1d980501f4f08cdeb0916912b4f3accd9cf56fea456a399e793a5" \
  "pipelineTask $REG/tekton/tasks/publier-fermeture sha256:7fa92ad3e4adb0d4b9bc4209ee04096d476dee5ffa173fc08b9cac0614e2b135" \
  "- oci://$REG/amont/library/debian sha256:7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392" \
  "- oci://$REG/plateforme/outils-horodatage sha256:c7bebae2bd33e57792988b8ba215536dd9360a9871ec0bdf807ee94d4c1f4ca0" \
  "inputs/result http://snapshot.debian.org/archive/debian/20261105T000000Z/dists/trixie/InRelease sha256:0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675" \
  > "$B/deb/deps-attendues.txt"
printf '%s\n' "prefetch-deb inrelease 0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675" \
  "prefetch-deb instantane http://snapshot.debian.org/archive/debian/20261105T000000Z" \
  "prefetch-deb liste sha256:a63fe5fc7494d641c9c281b0ee9318807597cc7c35e5d7c7a087459c89de50aa (162 lignes non vides)" \
  "publier-fermeture depot $REG/builds/fermetures/sample-app-deb" > "$B/deb/params-attendus.txt"
J06=poc/bricks/06-deb-sbuild/resultats
egal "digest de la pipeline deb dans s4b-deb.log (06)" "$(grep -c 'prefetch-deb-sample-app@sha256:206a539e1b1cd57edaec1ae917fccec5390f4de379f496ff68934bcad3aadd39' "$J06/s4b-deb.log" | awk '{print ($1 > 0)}')" 1
egal "autres dépendances dans s4b-provenance.log (06)" "$(sed -n '2,6p' "$B/deb/deps-attendues.txt" | while read -r a b c; do grep -c -F -e "$a $b $c" "$J06/s4b-provenance.log"; done | awk '$1 > 0' | wc -l)" 5
egal "liste deb (sha256) dans s4b-provenance.log (06)" "$(grep -c 'a63fe5fc7494d641c9c281b0ee9318807597cc7c35e5d7c7a087459c89de50aa' "$J06/s4b-provenance.log")" 1
r=0; ( . "$B/fonctions.sh"; set -euo pipefail
  controler_prov "$B/deb/enveloppes.json" "$u" "$DEB" "$B/deb/deps-attendues.txt" "$B/deb/params-attendus.txt" "$B/deb"
) > "$B/deb/sortie.txt" 2>&1 || r=$?
sed 's/^/     /' "$B/deb/sortie.txt" | cut -c1-200
egal "controler_prov sur s4b-deb-1 : code, OK, KO" "$r $(grep -c '^OK   ' "$B/deb/sortie.txt") $(grep -c '^KO' "$B/deb/sortie.txt")" "0 5 0"

echo "# bilan : $n OK, $k KO ; fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
