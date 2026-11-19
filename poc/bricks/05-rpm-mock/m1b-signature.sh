#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : signature des deux tâches neuves et des deux pipelines (carte resultats/m1b-carte.md, point 4), préparée à
# sec le 19/11/2026 sur le modèle de l'étape taches de m4c.sh. Script à part : m1b-builders.sh, dont le sha256 est cité par les
# prédictions de la mesure d'un autre jour, n'est pas touché.
#   taches  entrées : les quatre objets rendus par m1b-builders.sh prealables sous un préfixe ($RENDU, m1bt-20 par défaut), dont
#           le sha256 doit égaler celui validé par Tekton (TD1, m1b-taches-admission.log) ; admission en dry-run serveur ;
#           SIGNER=1 : prefetch-racine-rpm et construire-racine-rpm signées (tkn, clé des tâches), relues (égales aux tâches
#           rendues, signature exceptée ; image de l'amorce), versionnées sous builders/, bundles poussés dans Zot (tag m1b,
#           écritures définitives), à ajouter à la liste revue de la 08 après revue du propriétaire ; une fois les deux listées :
#           les deux pipelines (builder-mock-rocky9, builder-rocky9-bootstrap) reçoivent les références réelles des tâches
#           (prefetch, construire, et publier-image de la liste revue), seul changement contrôlé, sont admises, signées, relues
#           et poussées en bundles (tekton/pipelines/<nom>, tag m1b).
# Garde : octets libres sur / de sc-stockage (porte /var/lib/zot) au moins LIBRE_MIN avant toute poussée.
# Aucun secret en argument ; l'authentification de Zot est écrite sous $T/auth (0700) et retirée à la sortie, même en échec.
# Usage (racine du dépôt) : [SIGNER=1] DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m1b-signature.sh taches
#         (journal : resultats/m1b-signature-taches.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # O, S, P, W, REG, REG_HOTE, bundle, auth_zot, sur, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
RENDU=${RENDU:-$W/m1bt-20-05}                     # rendu de prealables (lecture seule)
VERSIONS=${VERSIONS:-$h05/builders}               # signatures versionnées
LISTE_REVUE=${LISTE_REVUE:-$here/politique/porte/taches.yml}
T=$W/m1b-signature-05
(umask 077 && mkdir -p "$T/auth")
trap 'find "$T/auth" -depth -delete 2> /dev/null || true' EXIT   # copies de secrets, retirées même en cas d'échec (sans rm)
AMORCE=$REG/amont/rockylinux/rockylinux@sha256:ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d   # D4 (a), « (a) Figée »
FACTICE=sha256:0000000000000000000000000000000000000000000000000000000000000000
LIBRE_MIN=1073741824
# Rendus validés par le webhook de Tekton le 19/11/2026 (TD1, m1b-taches-admission.log)
RENDUS_SHA="prefetch-racine-rpm.yaml:b0fdff3895df59897ebc30333689b24f748124ed98e1f610cb4405a170534a05
construire-racine-rpm.yaml:de77ba0a70b4cee401448e7f6dc161094c71b2594204425a838d7dc45bf97b08
pipeline-o.yaml:13836c388b47fe701360631db59239f67b8d787568d2af3491707422d78bfda0
pipeline-b.yaml:b2443188125b63b71539cb61c73d314dd21f11aaba3a673ab263a644794870f7"
TACHES="prefetch-racine-rpm construire-racine-rpm"

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echec() { echo "KO   $*" >&2; exit 1; }
admission() { # fichier : kubectl create --dry-run=server dans builds (rien n'est créé) ; code de kubectl ; motif compté, jamais le texte
  local rc=0
  kubectl create --dry-run=server -n builds -f "$1" < /dev/null > /dev/null 2> "$T/admission.err" || rc=$?
  echo "$rc"
}
libre_zot() { sur sc-stockage 'df -B1 --output=avail / | tail -n 1' < /dev/null | tr -d ' '; }   # m4b.sh
normaliser() { # fichier : JSON sans la signature ni les champs vides que tkn écrit (m4c.sh, mesuré au banc du 18/11), clés triées
  yq -o=json -I=0 'del(.metadata.annotations["tekton.dev/signature"]) | del(.. | select(tag == "!!map" and length == 0 and (path | .[-1]) == "resources"))
    | del(.. | select(tag == "!!str" and . == "" and (path | .[-1]) == "description"))
    | del(.metadata.annotations | select(length == 0)) | sort_keys(..)' "$1"
}
ref_revue() { # dépôt-de-tâche [préfixe-du-digest] : référence complète lue dans la liste revue (une seule) ; de m4c.sh
  local r
  r=$(awk -v d="oci://$REG/tekton/tasks/$1:" -v p="sha256:${2:-}" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && index($3, p) == 1 {print $3}' "$LISTE_REVUE")
  [ "$(grep -c . <<< "$r")" = 1 ] && [ -n "$r" ] || return 1
  echo "$REG/tekton/tasks/$1@$r"
}
listee_ref() { # référence par digest : présente dans la liste revue (sous la clé de son dépôt)
  awk -v d="oci://${1%@*}:" -v r="${1#*@}" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && $3 == r {t = 1} END {exit !t}' "$LISTE_REVUE"
}
bundles_pipeline() { yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$1"; }
controler_tache() { # tâche-signée : annotation, égalité au rendu (signature exceptée), nom, image de l'amorce
  local f=$1 n
  n=$(yq .metadata.name "$f")
  attendu "$n signée : annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$f")" true
  attendu "$n signée : égale à la tâche rendue (TD1), signature exceptée (normalisées)" \
    "$(cmp -s <(normaliser "$f") <(normaliser "$RENDU/$n.yaml") && echo égale || echo différente)" égale
  attendu "$n signée : images des pas" "$(yq '[.spec.steps[].image] | join(" ")' "$f")" "$AMORCE"
}
versionner() { # tâche : signature versionnée sous builders/ (SIGNER=1 : écrite si absente ou si le contenu hors signature change)
  local n=$1 v=$VERSIONS/$1.signee.yaml
  if [ -n "${SIGNER:-}" ] && ! { [ -s "$v" ] && cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v"); }; then
    cp "$T/$n-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans builders/$n.signee.yaml"
  fi
  [ -s "$v" ] || echec "$n : signature versionnée absente : SIGNER=1, puis revue de la liste"
  attendu "$n : signature versionnée conforme à la tâche rendue, signature exceptée" \
    "$(cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") && echo conforme || echo différente)" conforme
  echo "builders/$n.signee.yaml : sha256 $(sha256sum < "$v" | cut -c1-64)"
}

etape_taches() {
  local e n r l=0 libre x nom pub refs
  [ -s "$S/taches.key" ] || echec "clé des tâches absente"
  pub=$(ref_revue publier-image d21931f3) || echec "publier-image d21931f3 : absente de la liste revue ou ambiguë"
  attendu "publier-image, lue dans la liste revue" "$pub" "$REG/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b"
  echo "rendu lu : ${RENDU/#$HOME/\~}"
  for e in $RENDUS_SHA; do
    attendu "${e%%:*} rendu égal à celui validé par Tekton (TD1, sha256)" "$(sha256sum < "$RENDU/${e%%:*}" 2> /dev/null | cut -c1-64)" "${e#*:}"
  done
  echo "## admission en dry-run serveur, rien n'est créé"
  for n in $TACHES pipeline-o pipeline-b; do attendu "$n admis (code de kubectl)" "$(admission "$RENDU/$n.yaml")" 0; done
  echo "## signatures des tâches (tkn $(tkn version --component client)) ; relues avant tout versionnement et toute poussée"
  for n in $TACHES; do tkn task sign "$RENDU/$n.yaml" -K "$S/taches.key" -f "$T/$n-signee.yaml" > /dev/null; done
  for n in $TACHES; do controler_tache "$T/$n-signee.yaml"; done
  libre=$(libre_zot)
  echo "relevé : octets libres sur / de sc-stockage (porte /var/lib/zot) avant les poussées : $libre"
  [ "$libre" -ge "$LIBRE_MIN" ] 2> /dev/null || echec "octets libres sur / de sc-stockage sous $LIBRE_MIN : $libre"
  for n in $TACHES; do versionner "$n"; done
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh), compte poc-ecriture
  for n in $TACHES; do
    r=$REG/tekton/tasks/$n@$(bundle "$VERSIONS/$n.signee.yaml" "tekton/tasks/$n" m1b)
    echo "$r" > "$T/$n.ref"
    if listee_ref "$r"; then echo "OK   $n dans la liste revue : $r"; l=$((l + 1))
    elif [ -n "${SIGNER:-}" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml (08) après revue du propriétaire : $r"
    else echec "$n absente de la liste revue : $r"; fi
  done
  [ "$l" = 2 ] || { echo "SIGNER : pipelines non signées tant que la liste revue n'a pas été acceptée"; return 0; }
  for x in o b; do
    nom=$(yq .metadata.name "$RENDU/pipeline-$x.yaml")
    echo "## pipeline $nom, tâches de la liste revue"
    refs="$(cat "$T/prefetch-racine-rpm.ref") $(cat "$T/construire-racine-rpm.ref") $pub"
    attendu "$nom rendue : références factices des trois tâches" "$(bundles_pipeline "$RENDU/pipeline-$x.yaml")" \
      "$REG/tekton/tasks/prefetch-racine-rpm@$FACTICE $REG/tekton/tasks/construire-racine-rpm@$FACTICE $REG/tekton/tasks/publier-image@$FACTICE"
    A=$(cat "$T/prefetch-racine-rpm.ref") B=$(cat "$T/construire-racine-rpm.ref") C=$pub yq '.spec.tasks[0].taskRef.params[0].value = strenv(A)
      | .spec.tasks[1].taskRef.params[0].value = strenv(B) | .spec.tasks[2].taskRef.params[0].value = strenv(C)' "$RENDU/pipeline-$x.yaml" > "$T/$nom.yaml"
    attendu "$nom : références des tâches" "$(bundles_pipeline "$T/$nom.yaml")" "$refs"
    attendu "$nom : seul changement, les trois références (normalisées, références remises à factice)" \
      "$(cmp -s <(F=$FACTICE yq '.spec.tasks[].taskRef.params[0].value |= sub("@sha256:[0-9a-f]{64}$"; "@" + strenv(F))' "$T/$nom.yaml" | normaliser /dev/stdin) \
        <(normaliser "$RENDU/pipeline-$x.yaml") && echo égale || echo différente)" égale
    attendu "$nom (références réelles) admise (code de kubectl)" "$(admission "$T/$nom.yaml")" 0
    tkn pipeline sign "$T/$nom.yaml" -K "$S/taches.key" -f "$T/$nom-signee.yaml" > /dev/null
    attendu "$nom signée : annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$T/$nom-signee.yaml")" true
    attendu "$nom signée : égale à la pipeline relue, signature exceptée" \
      "$(cmp -s <(normaliser "$T/$nom-signee.yaml") <(normaliser "$T/$nom.yaml") && echo égale || echo différente)" égale
    r=$REG/tekton/pipelines/$nom@$(bundle "$T/$nom-signee.yaml" "tekton/pipelines/$nom" m1b)
    echo "$r" | tee "$T/$nom.ref"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then lancer m1b-signature "05 M1b signature" "$@"; fi
