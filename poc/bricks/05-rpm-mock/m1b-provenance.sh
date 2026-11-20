#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : étape provenance (carte resultats/m1b-carte.md, « provenance » après les PipelineRuns), préparée à sec le
# 20/11/2026 sur le modèle de l'étape provenance de m4c.sh, NON LANCÉE. Script à part : m1b-pipeline.sh, m1b-signature.sh et
# m1b-builders.sh, dont les sha256 sont cités par des prédictions, ne sont pas touchés.
#   provenance  lecture seule (cluster lu, Zot lu anonymement, rien n'est créé ni supprimé dans le cluster ou dans Zot), pour
#               chacune des deux images publiées par $N-o-1/$N-o-2 (mock-rocky9) et $N-b-1/$N-b-2 (rocky9-bootstrap) :
#               - gardes : clé publique de Chains (sha256) ; pipelines signées de m1b-signature.sh (sha256 épinglés, référence
#                 au tag m1b) ; IMAGE_DIGEST de chaque PipelineRun, relu dans le cluster ;
#               - attestations de l'image vérifiées par cosign avec la clé de Chains (sans journal de transparence) ; aucune
#                 enveloppe d'un objet étranger aux deux PipelineRuns de l'image ; une enveloppe par PipelineRun (invocationId) ;
#               - sujet, buildType, aucune source git (les builders n'ont pas de dépôt), resolvedDependencies (pipeline, trois
#                 tâches, images des pas : amorce et outils-horodatage ; base ee90dc0e en entrée pour le bootstrap seul) égales à
#                 l'attendu tiré des références épinglées ; paramètres des tâches égaux à ceux de la pipeline signée (digest de
#                 publier substitué par celui de l'image) ; runtimeClassName dans la spec signée : Kata pour construire seule ;
#               - signature simplesigning relevée (non exigée) ; refus avec une autre clé.
# Valeurs à saut de ligne : comparées par sha256 après retrait des lignes vides (comme m4c.sh), jamais imprimées en entier.
# Aucun secret : la clé de Chains est publique, Zot est lu anonymement.
# Usage (racine du dépôt) : [PREFIXE=m1b] DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m1b-provenance.sh provenance
#         (journal : resultats/m1b-provenance-provenance.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # P, W, REG, REG_HOTE, refus, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
N=${PREFIXE:-m1b}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
SIG=${SIG:-$W/m1b-signature-05}                   # sorties de m1b-signature.sh (pipelines signées, références)
T=$W/$N-provenance-05
umask 022

CLE_CHAINS=$here/resultats/chains-cle-publique.pem
CLE_CHAINS_SHA=1e7b2a03f9d5d289898e63b57410aeafa4e3680e86474d4f35aaa4e01f0c5e65   # comme m4b.sh et m4c.sh
AMORCE=$REG/amont/rockylinux/rockylinux@sha256:ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d   # D4 (a)
HORODATAGE=$REG/plateforme/outils-horodatage@sha256:c7bebae2bd33e57792988b8ba215536dd9360a9871ec0bdf807ee94d4c1f4ca0   # pas de publier-image
PREFETCH_REF=$REG/tekton/tasks/prefetch-racine-rpm@sha256:16a32993160ae0f6f8e766658b3d594403f6734c295baa5048dcb05c674bf251
CONSTRUIRE_REF=$REG/tekton/tasks/construire-racine-rpm@sha256:bdde08ed7c2b58dcad95b091892988243953b0381cac7cc690dcc29529b32f0f
PUBLIER_REF=$REG/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b
KATA_ATTENDU="construire-racine-rpm:kata prefetch-racine-rpm:- publier-image:-"
# shellcheck disable=SC2016  # chaîne littérale de Tekton, jamais développée
SUBST_DIGEST='$(tasks.construire.results.DIGEST_CONSTRUIT)'   # seule valeur substituée des pipelines signées (relevé du 20/11)
# Par image : pipeline signée (référence et sha256 du fichier de m1b-signature.sh, second passage du 20/11/2026), image publiée et
# digest (m1b-pipeline-pipeline.log), base déclarée par le prefetch (bootstrap seul)
# shellcheck disable=SC2034  # table lue par indirection (v)
{
  NOM_o=builder-mock-rocky9
  PIPELINE_o=$REG/tekton/pipelines/builder-mock-rocky9@sha256:4b9daf42a74f247223ae27fd5520a41ca396b750b041691babbe4fa7490d2f0c
  SIGNEE_o=d31c871840301fe50b2fc9ac31e60a70a2f6d0792d80192ff0434b8869a68d3a
  IMAGE_o=$REG/builds/builders/mock-rocky9; DIGEST_o=sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae
  BASE_o=
  NOM_b=builder-rocky9-bootstrap
  PIPELINE_b=$REG/tekton/pipelines/builder-rocky9-bootstrap@sha256:eb57d44c1b65f0fa3fe3ba6be1e663d15a2fffd4f47dbf7174bdb0f853f56615
  SIGNEE_b=15123e7fae50e03999e6e582ff9c0974a259c3353bc0aa81215c330aa42bc848
  IMAGE_b=$REG/builds/builders/rocky9-bootstrap; DIGEST_b=sha256:6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3
  BASE_b=$REG/amont/rockylinux/rockylinux@sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2
}

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echec() { echo "KO   $*" >&2; exit 1; }
v() { local n="$1_$2"; echo "${!n}"; }   # champ image : valeur de la table ci-dessus
params_lignes() { # lignes « tâche paramètre valeur-en-base64 » sur l'entrée : « tâche paramètre valeur », valeur à saut de ligne
  # remplacée par son sha256 après retrait des lignes vides et le nombre de ces lignes (m4c.sh) ; liste triée
  local t n x
  while read -r t n x; do
    if [ "$(base64 -d <<< "$x" | wc -l)" -gt 0 ]; then
      echo "$t $n sha256:$(base64 -d <<< "$x" | sed '/^$/d' | sha256sum | cut -c1-64) ($(base64 -d <<< "$x" | sed '/^$/d' | wc -l) lignes non vides)"
    else
      echo "$t $n $(base64 -d <<< "$x")"
    fi
  done | sort
}
lire_prov() { # provenance (un objet JSON décodé) travail : resolvedDependencies (« nom uri digest ») dans deps.txt ; paramètres des
  # pipelineTask dans params.txt ; « tâche:runtimeClassName » dans taches.txt ; listes triées ; jamais le contenu en entier
  local p=$1 a=$2
  jq -r '.predicate.buildDefinition.resolvedDependencies[]
    | "\(.name // "-") \(.uri // "-") \(.digest // {} | to_entries | map(.key + ":" + .value) | join(","))"' "$p" | sort > "$a/deps.txt"
  jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
    | ((.spec.taskRef.params // []) | map(select(.name == "name")) | .[0].value // "-") as $t
    | .spec.params[]? | "\($t) \(.name) \(.value | if type == "string" then . else tojson end | @base64)"' "$p" | params_lignes > "$a/params.txt"
  jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
    | "\((.spec.taskRef.params // []) | map(select(.name == "name")) | .[0].value // "-"):\(.spec.podTemplate.runtimeClassName // "-")"' "$p" \
    | sort > "$a/taches.txt"
}
deps_attendues() { # image fichier : dépendances attendues, tirées des références épinglées de ce fichier
  local r
  {
    r=$(v PIPELINE "$1"); echo "pipeline ${r%@*} ${r#*@}"
    for r in "$PREFETCH_REF" "$CONSTRUIRE_REF" "$PUBLIER_REF"; do echo "pipelineTask ${r%@*} ${r#*@}"; done
    for r in "$AMORCE" "$HORODATAGE"; do echo "- oci://${r%@*} ${r#*@}"; done
    r=$(v BASE "$1"); [ -z "$r" ] || echo "inputs/result oci://${r%@*} ${r#*@}"
  } > "$2"
}
params_attendus() { # pipeline-signée digest fichier : paramètres des trois tâches tels que la pipeline signée les fixe, la seule
  # substitution (digest construit, donné à publier) remplacée par le digest de l'image ; même forme que lire_prov
  yq -o=json -I=0 '.spec.tasks' "$1" | jq -r --arg s "$SUBST_DIGEST" --arg d "$2" '.[]
    | ((.taskRef.params // []) | map(select(.name == "name")) | .[0].value // "-") as $t
    | .params[]? | "\($t) \(.name) \(.value | if type == "string" then (if . == $s then $d else . end) else tojson end | @base64)"' \
    | params_lignes > "$3"
}
controler_prov() { # enveloppes uid sujet deps-attendues params-attendus kata-attendu travail : tout imprimé, puis assertions ;
  # hors ligne (banc)
  local e=$1 u=$2 a=$7 n
  jq -c --arg u "$u" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$e" > "$a/prov.json"
  n=$(grep -c . "$a/prov.json" || true)
  : > "$a/deps.txt"; : > "$a/params.txt"; : > "$a/taches.txt"
  [ "$n" != 1 ] || lire_prov "$a/prov.json" "$a"
  echo "enveloppes de l'invocation $u : $n"
  echo "sujet : $(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$a/prov.json" | paste -sd' ')"
  echo "buildType : $(jq -r '.predicate.buildDefinition.buildType' "$a/prov.json" | paste -sd' ') ; builder.id : $(jq -r '.predicate.runDetails.builder.id // "-"' "$a/prov.json" | paste -sd' ') (relevé)"
  echo "début et fin : $(jq -r '"\(.predicate.runDetails.metadata.startedOn // "-") \(.predicate.runDetails.metadata.finishedOn // "-")"' "$a/prov.json" | paste -sd' ') (relevé)"
  echo "resolvedDependencies ($(wc -l < "$a/deps.txt")) :"; sed 's/^/     /' "$a/deps.txt"
  echo "paramètres des tâches ($(wc -l < "$a/params.txt")) :"; cut -c1-200 "$a/params.txt" | sed 's/^/     /'
  echo "runtimeClassName des tâches (spec signée) : $(paste -sd' ' "$a/taches.txt")"
  sort "$4" > "$a/deps-attendues-triees.txt"; sort "$5" > "$a/params-attendus-tries.txt"   # copies triées, sous d'autres noms
  echo "écarts (comm -3 ; sans retrait : provenance seule ; avec retrait : attendu seul) : dépendances, puis paramètres"
  comm -3 "$a/deps.txt" "$a/deps-attendues-triees.txt" | cut -c1-200 | sed 's/^/     /'
  comm -3 "$a/params.txt" "$a/params-attendus-tries.txt" | cut -c1-200 | sed 's/^/     /'
  attendu "enveloppes de l'invocation" "$n" 1
  attendu "sujet" "$(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$a/prov.json")" "$3"
  attendu "buildType" "$(jq -r '.predicate.buildDefinition.buildType' "$a/prov.json")" https://tekton.dev/chains/v2/slsa-tekton
  attendu "source git (dépendances git+, aucune attendue)" \
    "$(jq '[.predicate.buildDefinition.resolvedDependencies[] | select(.uri // "" | startswith("git+"))] | length' "$a/prov.json")" 0
  attendu "resolvedDependencies égales à l'attendu (sha256 des listes triées)" \
    "$(sha256sum < "$a/deps.txt" | cut -c1-64)" "$(sha256sum < "$a/deps-attendues-triees.txt" | cut -c1-64)"
  attendu "paramètres des tâches égaux à ceux de la pipeline signée (sha256 des listes triées)" \
    "$(sha256sum < "$a/params.txt" | cut -c1-64)" "$(sha256sum < "$a/params-attendus-tries.txt" | cut -c1-64)"
  attendu "runtimeClassName des tâches dans la spec signée" "$(paste -sd' ' "$a/taches.txt")" "$6"
}
etape_provenance() { # lecture seule : pour chaque image, attestations vérifiées par cosign (clé de Chains), une par PipelineRun ;
  # refus avec une autre clé
  local x c i pr uid s r nom
  [ ! -e "$T" ] || find "$T" -depth -delete   # dossier de travail de cette étape seule (sans rm)
  mkdir -p "$T"
  echo "## gardes"
  attendu "clé publique de Chains (sha256)" "$(sha256sum < "$CLE_CHAINS" | cut -c1-64)" "$CLE_CHAINS_SHA"
  for x in o b; do
    nom=$(v NOM "$x")
    attendu "$nom signée (m1b-signature.sh, sha256)" "$(sha256sum < "$SIG/$nom-signee.yaml" 2> /dev/null | cut -c1-64)" "$(v SIGNEE "$x")"
    attendu "$nom : référence au tag m1b (m1b-signature.sh)" "$(cat "$SIG/$nom.ref" 2> /dev/null)" "$(v PIPELINE "$x")"
    for i in 1 2; do
      attendu "IMAGE_DIGEST de $N-$x-$i (relu dans le cluster)" \
        "$(kubectl get pipelinerun -n builds "$N-$x-$i" -o json < /dev/null | jq -r '.status.results[]? | select(.name == "IMAGE_DIGEST") | .value')" "$(v DIGEST "$x")"
    done
  done
  for x in o b; do
    nom=$(v NOM "$x"); c=$T/$x; s=$(v IMAGE "$x")@$(v DIGEST "$x")
    mkdir -p "$c"
    echo "## $nom : $s"
    deps_attendues "$x" "$c/deps-attendues.txt"
    params_attendus "$SIG/$nom-signee.yaml" "$(v DIGEST "$x")" "$c/params-attendus.txt"
    echo "attendu : $(wc -l < "$c/deps-attendues.txt") dépendances, $(wc -l < "$c/params-attendus.txt") paramètres"
    echo "### cosign verify-attestation (clé de Chains, sans journal de transparence), lecture anonyme"
    cosign verify-attestation --key "$CLE_CHAINS" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" \
      "${s/$REG/$REG_HOTE}" < /dev/null > "$c/enveloppes.json" 2> "$c/cosign.err" || { sed -n '1,5p' "$c/cosign.err" >&2; echec "cosign verify-attestation"; }
    echo "OK   cosign verify-attestation : $(grep -c . "$c/enveloppes.json") enveloppe(s) valide(s) sur $(v DIGEST "$x")"
    for i in 1 2; do
      kubectl get pipelinerun -n builds "$N-$x-$i" -o jsonpath='{.metadata.uid} PipelineRun {.metadata.name}{"\n"}' < /dev/null
      kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$N-$x-$i" -o jsonpath='{range .items[*]}{.metadata.uid} TaskRun {.metadata.name}{"\n"}{end}' < /dev/null
    done > "$c/objets.txt"
    echo "invocationId des enveloppes (nombre, valeur, objet) :"
    jq -r '.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId // "-"' "$c/enveloppes.json" | sort | uniq -c \
      | while read -r i uid; do echo "     $i $uid $(awk -v u="$uid" '$1 == u {print $2, $3}' "$c/objets.txt" | grep . || echo "(hors des PipelineRuns de l'image)")"; done
    attendu "enveloppes d'un objet hors des deux PipelineRuns de l'image" "$(jq -r '.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId // "-"' "$c/enveloppes.json" \
      | while read -r uid; do awk -v u="$uid" '$1 == u' "$c/objets.txt" | grep -q . || echo "$uid"; done | grep -c . || true)" 0
    for i in 1 2; do
      pr=$N-$x-$i
      uid=$(kubectl get pipelinerun -n builds "$pr" -o jsonpath='{.metadata.uid}' < /dev/null)
      echo "### provenance de $pr ($uid)"
      mkdir -p "$c/$pr"
      controler_prov "$c/enveloppes.json" "$uid" "$s" "$c/deps-attendues.txt" "$c/params-attendus.txt" "$KATA_ATTENDU" "$c/$pr"
    done
    echo "### signature simplesigning (tag .sig), relevé"
    r=0; cosign verify --key "$CLE_CHAINS" --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "${s/$REG/$REG_HOTE}" \
      < /dev/null > "$c/signatures.json" 2> "$c/verify.err" || r=$?
    echo "cosign verify : code $r ; $(jq -s 'flatten | length' "$c/signatures.json" 2> /dev/null || echo -) signature(s) valide(s) ; digests signés : $(
      jq -r -s 'flatten | map(.critical.image["docker-manifest-digest"]) | unique | join(" ")' "$c/signatures.json" 2> /dev/null || echo -) (relevé, non exigé)"
    echo "### refus"
    openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$c/autre.pub" 2> /dev/null
    refus "$nom : provenance vérifiée avec une autre clé" "no matching attestations|invalid signature" \
      cosign verify-attestation --key "$c/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "${s/$REG/$REG_HOTE}"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then lancer m1b-provenance "05 M1b provenance" "$@"; fi
