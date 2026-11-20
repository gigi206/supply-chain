#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b : banc de m1b-artefact.sh (préparé à sec le 20/11/2026), écrit avant tout passage d'une étape. Rien
# n'est écrit dans Zot, dans le cluster, dans resultats/ ni dans le dossier de travail de la 08 : tout est sous <dossier-neuf>.
# A : syntaxe, shellcheck ; copies de m4a.sh (attendu, fichiers, DEPOT, TYPE, CREE) égales et définies une fois ; pousser égal à
#     celui de m4a.sh au dossier près.
# B : constantes contre des sources indépendantes (journaux de M4a et du verrou de la cascade, m4a.sh, m4c.sh, m1b-signature.sh,
#     layout de M4a).
# C : témoin de méthode : preparer et pousser du script, avec le verrou de M4a, sous deux tags autres que m4a, dans des dossiers
#     du banc : le digest doit être celui de M4a (41c639b7).
# D : comparateur de manifestes sur le manifeste de M4a altéré : seul le changement prévu passe.
# E : gardes jouées sans réseau sur une copie du script (journaux de la copie dans le banc) : PREFIXE et TAG refusés, journal
#     existant refusé, publier sans digest local refusé avant toute lecture de Zot, zone de préparation existante refusée.
# Usage (racine du dépôt) :
#   DISTRO=rke2 mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-artefact-banc.sh <dossier-neuf> <m1b-artefact.sh>
export LC_ALL=C DISTRO=${DISTRO:-rke2}
B=$1; S05=$2
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/t" "$B/d"
D05=$PWD/poc/bricks/05-rpm-mock
M4A=$D05/m4a.sh
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; echo OK >> "$B/compte"; else echo "KO   $1 : $2 (attendu : $3)"; echo KO >> "$B/compte"; fi; }
echo "# m1b-artefact-banc.sh, $(date -u +%FT%TZ) ; m1b-artefact.sh $(sha256sum < "$S05" | cut -c1-64)"
charger() { PREFIXE=banc . "$S05"; set +e; T=$B/t; }   # sourcé sans lancer (garde BASH_SOURCE)

echo "## A : syntaxe, shellcheck, copies de m4a.sh"
egal "bash -n" "$(bash -n "$S05" && echo ok)" ok
egal "shellcheck : codes" "$(LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$S05" 2> /dev/null | grep -o 'SC[0-9]*' | sort -u | paste -sd' ')" "SC2015 SC2154"
for f in attendu fichiers; do
  egal "$f : ligne égale à m4a.sh, définie une fois" "$(grep "^$f() {" "$S05" | sha256sum | cut -c1-16) $(grep -c "^$f() {" "$S05")" \
    "$(grep "^$f() {" "$M4A" | sha256sum | cut -c1-16) 1"
done
for v in DEPOT TYPE CREE; do
  egal "ligne $v égale à m4a.sh, définie une fois" "$(grep "^$v=" "$S05" | sha256sum | cut -c1-16) $(grep -c "^$v=" "$S05")" \
    "$(grep "^$v=" "$M4A" | sha256sum | cut -c1-16) 1"
done
corps() { awk '/^pousser\(\) \{/ {p = 1} p {print} p && /^}$/ {exit}' "$1"; }
egal "pousser : corps de m4a.sh au dossier près (dossier en premier argument, cd dans ce dossier)" \
  "$(corps "$S05" | sed -e 's/^pousser() { # dossier cible-oras/pousser() { # cible oras/' \
      -e 's/^  local dossier=\$1 cible=\$2; shift 2$/  local cible=$1; shift/' -e 's/cd "\$dossier"/cd "$PKG"/' | sha256sum | cut -c1-16)" \
  "$(corps "$M4A" | sha256sum | cut -c1-16)"
egal "aucun rm dans le script" "$(grep -c -E '(^|[^a-z])rm ' "$S05")" 0
egal "aucune écriture vers poc/packaging ni vers m4a-05 (cp, mkdir, >)" \
  "$(grep -E '(cp|mkdir|>)[^#]*(\$PKG|\$VERROU_M4A[^_]|m4a-05)' "$S05" | grep -v -c '^ *#')" 0

echo "## B : constantes contre des sources indépendantes"
( charger
  egal "SPEC_SHA = sample-app.spec au journal de l'étape verrou de M4a" \
    "$(grep -c "^     $SPEC_SHA  sample-app.spec$" "$D05/resultats/m4a-verrou.log")" 1
  egal "VERROU_NEUF_SHA = verrou écrit au journal du verrou de la cascade" \
    "$(grep -c "^verrou écrit : resultats/m1b-verrou.json, sha256 $VERROU_NEUF_SHA, " "$D05/resultats/m1b-verrou-verrou.log")" 1
  egal "VERROU_M4A_SHA = VERROU_SHA de m4a.sh" "$(sed -n 's/^VERROU_SHA=\([0-9a-f]*\) .*/\1/p' "$M4A")" "$VERROU_M4A_SHA"
  egal "M4A_DIGEST = PACKAGING_RPM du journal de publier (M4a) et PACKAGING de m4c.sh" \
    "$(sed -n 's/^PACKAGING_RPM=.*@//p' "$D05/resultats/m4a-publier.log") $(sed -n 's/^PACKAGING=.*@\(sha256:[0-9a-f]*\) .*/\1/p' "$D05/m4c.sh")" \
    "$M4A_DIGEST $M4A_DIGEST"
  egal "BOOTSTRAP = C3 du journal du verrou de la cascade" \
    "$(sed -n 's/^OK   C3 config.bootstrap_image égal à l.image de M1b : //p' "$D05/resultats/m1b-verrou-verrou.log")" "$BOOTSTRAP"
  egal "ID_BOOTSTRAP = G2 et C4 du journal du verrou de la cascade" \
    "$(grep -c -E "^(G2 configuration de l'image de bootstrap \(id attendu dans le verrou\) : sha256:|OK   C4 bootstrap.id égal au digest de la configuration de l'image, relu dans Zot : )$ID_BOOTSTRAP$" "$D05/resultats/m1b-verrou-verrou.log")" 2
  egal "LIBRE_MIN = celui de m1b-signature.sh" "$(sed -n 's/^LIBRE_MIN=\([0-9]*\)$/\1/p' "$D05/m1b-signature.sh")" "$LIBRE_MIN"
  egal "layout de M4a : index sur M4A_DIGEST, tag m4a" \
    "$(jq -r '.manifests[] | .digest + " " + .annotations["org.opencontainers.image.ref.name"]' "$M4A_LAYOUT/index.json")" "$M4A_DIGEST m4a"
  egal "manifeste de M4a : blob relu, sha256" "$( (blob "$M4A_LAYOUT" "$M4A_DIGEST" > /dev/null) && echo contrôlé)" contrôlé
  egal "chemins des sources" "${SPEC#"$PWD"/} ${VERROU_NEUF#"$PWD"/} ${VERROU_M4A#"$PWD"/}" \
    "poc/packaging/sample-app.spec poc/bricks/05-rpm-mock/resultats/m1b-verrou.json poc/packaging/verrou-rpm.json"
  egal "T par défaut et tag par défaut sous PREFIXE=banc" "$(PREFIXE=banc bash -c ". '$S05'; echo \${T#\$W/} \$TAG")" "banc-artefact-05 banc"
)

echo "## C : témoin de méthode, verrou de M4a sous deux tags autres que m4a"
( charger
  for tag in banc m1b; do
    ( set -e; preparer "$B/t/temoin-$tag" "$VERROU_M4A" > "$B/t/preparer-$tag.out" ) ; c=$?
    egal "preparer, tag $tag : code et OK" "$c $(grep -c '^OK   zone' "$B/t/preparer-$tag.out")" "0 2"
    egal "témoin sous le tag $tag : digest de M4a" "$(pousser "$B/t/temoin-$tag" "$B/t/layout-$tag:$tag" --oci-layout)" "$M4A_DIGEST"
  done
  egal "oras" "$(oras version | sed -n 's/^Version: *//p')" 1.3.6
)

echo "## D : comparateur de manifestes"
( charger
  a=$(blob "$M4A_LAYOUT" "$M4A_DIGEST"); vd=sha256:$VERROU_NEUF_SHA; vt=111567
  cas() { # libellé code-attendu filtre-jq
    jq -c "$3" "$a" > "$B/d/neuf.json"
    python3 -I -c "$COMPARE_MANIFESTE" "$B/d/neuf.json" "$a" "$vd" "$vt" > "$B/d/sortie" 2>&1; local c=$?
    egal "$1 : code, ligne A5" "$c $(grep -c "^$([ "$2" = 0 ] && echo OK || echo KO)   A5 " "$B/d/sortie")" "$2 1"
  }
  cas "changement prévu (digest et taille du verrou)" 0 ".layers[1].digest = \"$vd\" | .layers[1].size = $vt"
  cas "aucun changement" 1 '.'
  cas "digest seul" 1 ".layers[1].digest = \"$vd\""
  cas "mauvais digest de verrou" 1 ".layers[1].digest = \"sha256:$(printf 0%.0s {1..64})\" | .layers[1].size = $vt"
  cas "spec changé en plus" 1 ".layers[1].digest = \"$vd\" | .layers[1].size = $vt | .layers[0].size = 1"
  cas "annotation de date changée en plus" 1 ".layers[1].digest = \"$vd\" | .layers[1].size = $vt | .annotations[\"org.opencontainers.image.created\"] = \"2026-11-20T00:00:00Z\""
  cas "configuration changée en plus" 1 ".layers[1].digest = \"$vd\" | .layers[1].size = $vt | .config.size = 3"
  cas "type d'artefact changé en plus" 1 ".layers[1].digest = \"$vd\" | .layers[1].size = $vt | .artifactType = \"x\""
  cas "couche ajoutée" 1 ".layers[1].digest = \"$vd\" | .layers[1].size = $vt | .layers += [.layers[0]]"
  cas "couches inversées" 1 ".layers[1].digest = \"$vd\" | .layers[1].size = $vt | .layers |= reverse"
  cas "titre du verrou changé" 1 ".layers[1].digest = \"$vd\" | .layers[1].size = $vt | .layers[1].annotations[\"org.opencontainers.image.title\"] = \"verrou.json\""
)

echo "## E : gardes sans réseau, sur une copie du script"
C=$B/c; mkdir -p "$C/05-rpm-mock/resultats"; ln -s "$D05/../08-trust-plane" "$C/08-trust-plane"
cp "$S05" "$C/05-rpm-mock/m1b-artefact.sh"
X=$C/05-rpm-mock/m1b-artefact.sh
code() { local c=0; "$@" < /dev/null > "$B/e.out" 2>&1 || c=$?; echo "$c"; }
egal "PREFIXE invalide refusé" "$(PREFIXE=Banc code bash "$X" local) $(grep -c '^PREFIXE invalide' "$B/e.out")" "2 1"
egal "TAG m4a refusé" "$(PREFIXE=bance TAG=m4a code bash "$X" local) $(grep -c '^tag refusé : m4a' "$B/e.out")" "2 1"
egal "TAG invalide refusé" "$(PREFIXE=bance TAG=M1b code bash "$X" local) $(grep -c '^TAG invalide' "$B/e.out")" "2 1"
: > "$C/05-rpm-mock/resultats/bance-artefact-local.log"
egal "journal existant refusé, laissé vide" "$(PREFIXE=bance code bash "$X" local) $(grep -c '^journal déjà présent' "$B/e.out") $(stat -c %s "$C/05-rpm-mock/resultats/bance-artefact-local.log")" "2 1 0"
W08=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}/travail   # W de commun.sh
egal "dossier de travail de bancp absent avant" "$([ -e "$W08/bancp-artefact-05" ] && echo présent || echo absent)" absent
egal "publier sans digest local : refus" "$(PREFIXE=bancp code bash "$X" publier) $(grep -c '^KO   étape local à lancer d.abord' "$C/05-rpm-mock/resultats/bancp-artefact-publier.log")" "1 1"
egal "publier sans digest local : rien d'autre au journal, aucune lecture de Zot" "$(grep -v -c -E '^(# |KO   étape local)' "$C/05-rpm-mock/resultats/bancp-artefact-publier.log")" 0
egal "dossier de travail de bancp absent après" "$([ -e "$W08/bancp-artefact-05" ] && echo présent || echo absent)" absent
( charger
  ( set -e; preparer "$B/t/temoin-banc" "$VERROU_M4A" ) > "$B/e.out" 2>&1; c=$?
  egal "zone de préparation existante refusée" "$c $(grep -c '^KO   déjà présent, jamais réécrit' "$B/e.out")" "1 1"
)

echo "## bilan : $(grep -c '^OK$' "$B/compte") OK, $(grep -c '^KO$' "$B/compte") KO"
