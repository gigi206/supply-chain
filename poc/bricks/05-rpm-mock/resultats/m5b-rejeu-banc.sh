#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, M5b sous l'option C : banc de m5b-rejeu.sh, avant tout lancement (20/11/2026). Rien n'est écrit dans Zot ni dans le
# cluster, rien n'y est lu : CONFIANCE_DIR du banc (travail sous le dossier du banc ; liens en lecture vers le rendu de
# prealables m1bt-20-05 et le layout de M4a ; clé des tâches factice ; certificat public de la CA). Doublures : kubectl, zot_lire,
# oras, sur, auth_zot ; les objets des PipelineRuns sont ceux, réels, de la cascade (gardés sous $W/m1b-fermeture-05 et
# $W/m1b-construction-05, lus seulement), renommés au préfixe du banc.
#   A  lanceur : bash -n, shellcheck, TAG refusés (code 2), étape inconnue ; scripts de mesure inchangés ; rien n'est signé ici
#   B  entree, la vraie fonction sur les vraies entrées de l'hôte : nominal (copie hors de $W faite) ; fuseau,
#      SOURCE_DATE_EPOCH, journal et dossier du TAG présents, clé absente, arbre altéré refusés ; journal de l'étape elle-même
#      ignoré ; (ajouté le 20/11 après la note de 17:52:19Z) copie relue sans $W, copie altérée, entrées absentes partout
#   C  chargements, sur une copie avec des scripts de mesure factices : signature (sorties sous $TS, SIGNER retirée, dossiers
#      auth retirés, refus d'un $TS présent), images (PREFIXE et SIG), artefact, fermeture, construction_rpm (PREFIXE, TAG) ;
#      journal présent refusé par le lanceur
#   D  artefact : etape_local réelle, layout de M4a lu dans la copie (travail sans m4a-05), publication dans un layout OCI
#      local ; reprise, digest local différent, tag occupé, place
#   E  fermeture : nominal, reprise, pipeline absente, PipelineRun présent, place, digest différent, arbre altéré, tâche hors
#      liste, admission refusée
#   F  construction_rpm : nominal, digest différent (relevé), politique absente, entrée absente, PipelineRun présent, pipeline
#      absente ; témoins réseau absents du journal de construire
# Ne couvre pas : Zot (TLS, comptes), Tekton, l'admission réelle, Kyverno, Kata, Chains, tkn, s1.sh, m5b-republier.sh, rejeu.sh.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m5b-rejeu-banc.sh <dossier-neuf>
# shellcheck disable=SC1090,SC2012,SC2016,SC2030,SC2031,SC2034,SC2154,SC2329  # code des cas évalué dans le script sourcé ; variables de ce script
set -uo pipefail
export LC_ALL=C
cd "$(dirname "$0")/../../../.." || exit 2
F=poc/bricks/05-rpm-mock/m5b-rejeu.sh
B=${1:?usage : m5b-rejeu-banc.sh <dossier-neuf>}
[ ! -e "$B" ] || { echo "KO   dossier déjà présent : $B" >&2; exit 2; }
OK=0; KO=0
ok() { echo "OK   $*"; OK=$((OK + 1)); }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
verifie() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else ko "$1 : $2 (attendu : $3)"; fi; }
W0=$(bash -c 'here=poc/bricks/08-trust-plane; . "$here/commun.sh"; echo "$W"')   # travail réel, lu seulement
mkdir -p "$B/O/travail" "$B/O/pki" "$B/O/secrets" "$B/resultats" "$B/vide"
chmod 700 "$B/O/secrets"
ln -s "$W0/m1bt-20-05" "$B/O/travail/m1bt-20-05"
ln -s "$W0/m4a-05" "$B/O/travail/m4a-05"
cp "$(dirname "$W0")/pki/ca-poc.crt" "$B/O/pki/ca-poc.crt"
printf 'clé factice du banc\n' > "$B/O/secrets/taches.key"
export CONFIANCE_DIR=$B/O
export E05=$B/entrees   # copie des entrées de l'hôte, faite par B1
W=$B/O/travail
mkdir -p "$B/O2/travail" "$B/O2/pki" "$B/O2/secrets"; chmod 700 "$B/O2/secrets"   # travail après démontage : ni m1bt-20-05 ni m4a-05
cp "$B/O/pki/ca-poc.crt" "$B/O2/pki/ca-poc.crt"; cp "$B/O/secrets/taches.key" "$B/O2/secrets/taches.key"
REG=sc-stockage.poc.test:5000
echo "# m5b-rejeu-banc.sh, $(date -u +%FT%TZ), dépôt $(git rev-parse --short=8 HEAD), script $(sha256sum < "$F" | cut -c1-16)"
echo "dossier du banc : ${B/#$HOME/\~} ; travail réel lu : ${W0/#$HOME/\~} (m1bt-20-05, m4a-05, m1b-fermeture-05, m1b-construction-05)"

cas() { # nom tag code [script] : sous-shell, script sourcé sous TAG=tag, R du banc ; sortie et code dans $B/cas-<nom>.*
  local r
  ( export TAG=$2; [ -z "${CAS_O:-}" ] || export CONFIANCE_DIR=$CAS_O; [ -z "${CAS_E05:-}" ] || export E05=$CAS_E05
    . "${4:-$F}"; R=$B/resultats; eval "$3" ) > "$B/cas-$1.out" 2>&1; r=$?   # hors d'un || : set -e actif
  echo "$r" > "$B/cas-$1.code"
}
code() { cat "$B/cas-$1.code"; }
lignes() { grep -c -F -- "$2" "$B/cas-$1.out"; }
refus() { # cas motif : code 1 et arrêt sur le motif
  if [ "$(code "$1")" = 1 ] && grep '^KO' "$B/cas-$1.out" | tail -n 1 | grep -q -F -- "$2"; then ok "$1 : arrêt sur « $2 »"
  else ko "$1 : code $(code "$1"), dernier KO : $(grep '^KO' "$B/cas-$1.out" | tail -n 1 | cut -c1-200)"; fi
}
montre() { grep -v '^     \|^       ' "$B/cas-$1.out" | cut -c1-170 | sed 's/^/   | /'; }

echo "## A lanceur"
verifie "A1 bash -n" "$(bash -n "$F" && echo ok)" ok
verifie "A1 shellcheck -x" "$(shellcheck -x "$F" > /dev/null 2>&1 && echo ok)" ok
for t in m1b m4a m4b m4c essai s1 '' A a_b; do
  r=0; TAG=$t bash "$F" entree > /dev/null 2>&1 || r=$?
  verifie "A2 TAG=« $t » refusé (code)" "$r" 2
done
r=0; TAG=banc-a bash "$F" inconnue > /dev/null 2>&1 || r=$?
verifie "A3 étape inconnue (code)" "$r" 2
verifie "A3 aucun journal écrit par A2 et A3 (journaux du banc exceptés)" "$(find poc/bricks/05-rpm-mock/resultats -name 'm5b-rejeu-*-*.log' ! -name 'm5b-rejeu-banc*' | wc -l)" 0
verifie "A4 scripts de mesure, commun.sh, m5b-republier.sh et rejeu.sh inchangés (git diff HEAD)" \
  "$(git diff --quiet HEAD -- poc/bricks/05-rpm-mock/m1b-signature.sh poc/bricks/05-rpm-mock/m1b-pipeline.sh poc/bricks/05-rpm-mock/m1b-artefact.sh \
    poc/bricks/05-rpm-mock/m1b-fermeture.sh poc/bricks/05-rpm-mock/m1b-construction.sh poc/bricks/05-rpm-mock/m5b-republier.sh \
    poc/bricks/08-trust-plane/commun.sh poc/bricks/08-trust-plane/rejeu.sh && echo inchangés)" inchangés
verifie "A5 rien n'est signé par le script lui-même (tkn … sign, cosign sign)" "$(grep -c 'tkn task sign\|tkn pipeline sign\|cosign sign' "$F")" 0
verifie "A5 clé des tâches : une seule ligne, le test -s" "$(grep -c 'taches\.key' "$F") $(grep -c '\[ -s "\$S/taches\.key" \]' "$F")" "1 1"

echo "## B entree, vraie fonction, vraies entrées de l'hôte"
cas B1 banc-b1 'rejeu_entree'
montre B1
verifie "B1 nominal : code" "$(code B1)" 0
verifie "B1 nominal : KO" "$(grep -c '^KO' "$B/cas-B1.out")" 0
for m in "OK   journaux de ce TAG présents (un journal n'est jamais réécrit) : 0" "OK   dossiers de ce TAG présents sous \$W : 0" \
         "OK   rendus contrôlés : 4" "OK   fichiers signés contrôlés : 5" \
         "OK   copie : layout de M4a, manifeste sha256:41c639b7f0f2… (sha256 du blob) : sha256:41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8" \
         "OK   clé des tâches présente (test -s, jamais lue ici) : présente" "OK   tkn (client) : 0.46.2" \
         "OK   arbre de l'essai de la cascade : fichiers : 230" "entrée : rien n'a été écrit dans Zot ni dans le cluster"; do
  verifie "B1 ligne « ${m:0:70}… »" "$(lignes B1 "$m")" 1
done
verifie "B1 mesure d'un autre jour (gardes_mesure de m1b-pipeline.sh) : deux images" "$(grep -c '^OK   [ob] : digest du banc de m1bt-20 égal à celui de m1bt3' "$B/cas-B1.out")" 2
verifie "B1 dossiers laissés sous le travail du banc (chargements)" "$(cd "$W" && ls -d banc-b1-pipeline-05 m5b-republier-banc-b1-05 2> /dev/null | paste -sd' ')" "banc-b1-pipeline-05 m5b-republier-banc-b1-05"
verifie "B1 aucun dossier auth laissé" "$(find "$W" -name auth | wc -l)" 0
verifie "B1 copie faite hors du travail : fichiers (4 rendus, 2 banc-digest, layout de M4a)" \
  "$(lignes B1 'copie faite : ') $(find "$E05/m1bt-20-05" -type f | wc -l) $(cd "$E05/m4a-05/layout-1" && find . -type f | sort | xargs sha256sum | sha256sum | cut -c1-16)" \
  "1 6 $(cd "$W0/m4a-05/layout-1" && find . -type f | sort | xargs sha256sum | sha256sum | cut -c1-16)"
verifie "B1 copie : rendus et banc-digest égaux aux originaux" \
  "$(cd "$E05/m1bt-20-05" && for f in *; do cmp -s "$f" "$W0/m1bt-20-05/$f" || echo "$f"; done | wc -l)" 0
cas B2 banc-b2 'export TZ=UTC; rejeu_entree'; refus B2 "fuseau : décalage de l'époque 0"
cas B3 banc-b3 'export SOURCE_DATE_EPOCH=0; rejeu_entree'; refus B3 "SOURCE_DATE_EPOCH"
: > "$B/resultats/m5b-republier-banc-b4-taches.log"
cas B4 banc-b4 'rejeu_entree'; refus B4 "journaux de ce TAG présents (un journal n'est jamais réécrit) : 1"
cas B5 banc-b1 'rejeu_entree'; refus B5 "dossiers de ce TAG présents sous \$W : 2"
cas B6 banc-b6 'S=$B/vide; rejeu_entree'; refus B6 "clé des tâches présente (test -s, jamais lue ici) : absente"
sed '1s/^./X/' poc/bricks/05-rpm-mock/resultats/m1b-fermeture-essai-arbre.txt > "$B/arbre-altere.txt"
cas B7 banc-b7 'ARBRE_CASCADE=$B/arbre-altere.txt; rejeu_entree'; refus B7 "arbre de l'essai de la cascade (sha256)"
: > "$B/resultats/m5b-rejeu-banc-b8-entree.log"
cas B8 banc-b8 'rejeu_entree'
verifie "B8 journal de l'étape entree elle-même ignoré : code" "$(code B8)" 0
for c in B2 B3 B4 B6; do verifie "$c : arrêt avant tout chargement (aucun dossier du TAG)" "$(find "$W" -maxdepth 1 -name "*banc-${c,,}*" | wc -l)" 0; done
CAS_O=$B/O2 cas B9 banc-b9 'rejeu_entree'
verifie "B9 copie relue, travail sans entrées (après démontage) : code, message" "$(code B9) $(lignes B9 'copie présente, relue : ')" "0 1"
mkdir -p "$B/entrees-alt"; cp -r "$E05/m1bt-20-05" "$E05/m4a-05" "$B/entrees-alt/"
sed -i '1s/^/# altéré par le banc\n/' "$B/entrees-alt/m1bt-20-05/pipeline-o.yaml"
CAS_O=$B/O2 CAS_E05=$B/entrees-alt cas B10 banc-b10 'rejeu_entree'; refus B10 "copie : rendu de prealables pipeline-o.yaml"
CAS_O=$B/O2 CAS_E05=$B/entrees-absente cas B11 banc-b11 'rejeu_entree'; refus B11 "entrées de l'hôte absentes de \$W"
verifie "B11 : aucune copie créée" "$([ -e "$B/entrees-absente" ] && echo créée || echo absente)" absente

echo "## C chargements, copie du script et scripts de mesure factices"
C=$B/c
mkdir -p "$C/05-rpm-mock/resultats"
ln -s "$PWD/poc/bricks/08-trust-plane" "$C/08-trust-plane"
cp "$F" "$C/05-rpm-mock/m5b-rejeu.sh"
entete='here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../08-trust-plane; . "$here/commun.sh"'
cat > "$C/05-rpm-mock/m1b-signature.sh" <<EOF
$entete
T=\$W/m1b-signature-05
(umask 077 && mkdir -p "\$T/auth")
trap 'find "\$T/auth" -depth -delete 2> /dev/null || true' EXIT
etape_taches() { echo "signature : T=\${T#"\$W"/} SIGNER=\${SIGNER-absente} RENDU=\${RENDU#"\$E05"/} T0/auth=\$([ -d "\$T0/auth" ] && echo présent || echo absent) T/auth=\$([ -d "\$T/auth" ] && echo présent || echo absent)"; mkdir -p "\$T/auth/docker"; echo '{}' > "\$T/auth/docker/config.json"; }
EOF
cat > "$C/05-rpm-mock/m1b-pipeline.sh" <<EOF
$entete
N=\${PREFIXE:-m1b}; SIG=\${SIG:-\$W/m1b-signature-05}; MESURE=\${MESURE:-\$W/m1bt-20-05}; T=\$W/\$N-pipeline-05
etape_pipeline() { echo "images : N=\$N SIG=\${SIG#"\$W"/} MESURE=\${MESURE#"\$E05"/}"; }
EOF
for s in artefact fermeture construction; do
  printf '%s\nN=${PREFIXE:-m1b}; TAG=${TAG:-$N}; T=$W/$N-%s-05\n' "$entete" "$s" > "$C/05-rpm-mock/m1b-$s.sh"
done
FC=$C/05-rpm-mock/m5b-rejeu.sh
cas C1 banc-c 'export SIGNER=1; etape_signature' "$FC"
verifie "C1 signature : sorties sous \$TS, SIGNER retirée, les deux dossiers auth présents pendant l'étape" \
  "$(grep '^signature : ' "$B/cas-C1.out")" "signature : T=m5b-rejeu-banc-c-signature-05 SIGNER=absente RENDU=m1bt-20-05 T0/auth=présent T/auth=présent"
verifie "C1 signature : code" "$(code C1)" 0
verifie "C1 dossiers auth retirés après (\$TS et \$W/m1b-signature-05)" "$(find "$W/m5b-rejeu-banc-c-signature-05" "$W/m1b-signature-05" -name auth | wc -l)" 0
cas C2 banc-c 'etape_signature' "$FC"; refus C2 "déjà présent, jamais réécrit : m5b-rejeu-banc-c-signature-05"
cas C3 banc-c 'etape_images' "$FC"
verifie "C3 images : PREFIXE, SIG et MESURE transmis" "$(grep '^images : ' "$B/cas-C3.out")" "images : N=banc-c SIG=m5b-rejeu-banc-c-signature-05 MESURE=m1bt-20-05"
cas C4 banc-c 'rejeu_artefact() { echo "artefact : N=$N TAG=$TAG T=${T#"$W"/} M4A=${M4A_LAYOUT#"$E05"/}"; }; etape_artefact' "$FC"
verifie "C4 artefact : PREFIXE, TAG et layout de M4a" "$(grep '^artefact : ' "$B/cas-C4.out")" "artefact : N=banc-c TAG=banc-c T=banc-c-artefact-05 M4A=m4a-05/layout-1"
cas C5 banc-c 'rejeu_fermeture() { echo "fermeture : N=$N TAG=$TAG"; }; etape_fermeture' "$FC"
verifie "C5 fermeture : PREFIXE et TAG" "$(grep '^fermeture : ' "$B/cas-C5.out")" "fermeture : N=banc-c TAG=banc-c"
cas C6 banc-c 'rejeu_construction() { echo "construction : N=$N TAG=$TAG"; }; etape_construction_rpm' "$FC"
verifie "C6 construction_rpm : PREFIXE et TAG" "$(grep '^construction : ' "$B/cas-C6.out")" "construction : N=banc-c TAG=banc-c"
: > "$C/05-rpm-mock/resultats/m5b-rejeu-banc-c-fermeture.log"
r=0; TAG=banc-c bash "$FC" fermeture > "$B/cas-C7.out" 2>&1 || r=$?
verifie "C7 journal présent refusé par le lanceur (code, message)" "$r $(grep -c 'journal déjà présent, jamais réécrit : m5b-rejeu-banc-c-fermeture.log' "$B/cas-C7.out")" "2 1"

etat() { awk -v r="$2" '$1 == r {x = $2} END {print x}' "$1"; }
communes() { # doublures communes, dans le sous-shell du cas, après le chargement
  zot_lire() { local d; d=$(etat "$BW/zot.txt" "$2"); echo "${d:-absent}"; }
  sur() { echo " ${BANC_LIBRE-3000000000}"; }
  auth_zot() { printf '{"faux":1}\n' > "$1"; }
}

echo "## D artefact : etape_local réelle, layout de M4a lu dans la copie (travail sans m4a-05), publication dans un layout OCI local"
dbl_artefact() {
  communes
  eval "pousser_vrai() $(declare -f pousser | tail -n +2)"
  pousser() { # vers le registre : layout du banc, poussée comptée, état de Zot tenu ; vers un layout (etape_local) : inchangée
    case $2 in
      "$REG_HOTE"/*) local d; d=$(pousser_vrai "$1" "$BW/layout:banc" --oci-layout); echo "$2 $d" >> "$BW/poussees"
        printf '%s %s\n%s %s\n' "${2#*/}" "$d" "$DEPOT@$d" "$d" >> "$BW/zot.txt"; echo "$d" ;;
      *) pousser_vrai "$@" ;;
    esac
  }
  oras() { local x=${*: -1}
    case $1 in
      pull) command oras pull --oci-layout "$BW/layout@${x##*@}" > /dev/null ;;
      push) command oras "$@" ;;
      *) echo "faux oras : $*" >&2; return 3 ;;
    esac
  }
}
cas_d() { # nom code [état-de-Zot]
  local w=$B/$1; mkdir -p "$w"; printf '%s' "${3:-}" > "$w/zot.txt"; : > "$w/poussees"
  CAS_O=$B/O2 cas "$1" banc-d "BW=$w; charger_artefact; dbl_artefact; $2"
}
A333=sha256:333b7322290ab5edd85989908fa2e181a48a72facfd4043e181a2962d2bcfe48
cas_d D1 'rejeu_artefact'
montre D1
verifie "D1 nominal : code, KO" "$(code D1) $(grep -c '^KO' "$B/cas-D1.out")" "0 0"
verifie "D1 nominal : etape_local réelle (A1 à A5 : 3 + 2 + 1 + 1 + 1)" "$(grep -c '^OK   A[1-5] ' "$B/cas-D1.out")" 8
verifie "D1 nominal : digest local égal à 333b7322" "$(lignes D1 "OK   digest local égal à l'artefact cité par la pipeline signée : $A333")" 1
verifie "D1 nominal : deux poussées au tag banc-d" "$(cut -d' ' -f1 "$B/D1/poussees" | sed 's#^[^/]*/##' | sort | uniq -c | sed 's/^ *//')" "2 entrees/sample-app/packaging-rpm:banc-d"
verifie "D1 nominal : P1, P2, P3" "$(grep -c '^OK   P[123] ' "$B/cas-D1.out")" 4
cas_d D2 'etape_local() { :; }; rejeu_artefact' "entrees/sample-app/packaging-rpm@$A333 $A333"
verifie "D2 reprise : code, poussées" "$(code D2) $(wc -l < "$B/D2/poussees")" "0 0"
verifie "D2 reprise : message" "$(lignes D2 "OK   artefact déjà présent dans Zot")" 1
cas_d D3 'etape_local() { echo sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa > "$T/digest-local"; }; rejeu_artefact'
refus D3 "décision du propriétaire ; rien n'est poussé"
verifie "D3 : poussées" "$(wc -l < "$B/D3/poussees")" 0
cas_d D4 'etape_local() { echo "$ARTEFACT_ATTENDU" > "$T/digest-local"; }; rejeu_artefact' "entrees/sample-app/packaging-rpm:banc-d sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
refus D4 "G1 entrees/sample-app/packaging-rpm:banc-d"
verifie "D4 : poussées" "$(wc -l < "$B/D4/poussees")" 0
cas_d D5 'etape_local() { echo "$ARTEFACT_ATTENDU" > "$T/digest-local"; }; BANC_LIBRE=5; rejeu_artefact'
refus D5 "G3 place libre sur / de sc-stockage"
verifie "D5 : poussées" "$(wc -l < "$B/D5/poussees")" 0

transposer() { # source préfixe-source destination préfixe-destination fichier… : objets réels renommés au préfixe du banc
  local s=$1 ps=$2 d=$3 pd=$4 f; shift 4; mkdir -p "$d"
  for f in "$@"; do sed "s/$ps/$pd/g" "$s/$f" > "$d/${f//$ps/$pd}"; done
}
faux_kubectl() { # dans le sous-shell du cas ; objets sous $BANC_OBJ, tâches $BANC_TACHES
  kubectl() {
    echo "kubectl $*" >> "$BW/appels"
    case "$*" in
      "create --dry-run=server -n builds -f "*) [ -z "${BANC_REFUS:-}" ] ;;
      "get pipelinerun -n builds "*" -o name") grep -qx "$5" "$BW/crees" 2> /dev/null || [ -n "${BANC_PR_EXISTE:-}" ] ;;
      "create -f "*) jq -r .metadata.name "${*: -1}" >> "$BW/crees"; cp "${*: -1}" "$BW/cree.json" ;;
      "get pipelinerun -n builds "*" -o json") cat "$BANC_OBJ/etat.json" ;;
      "get pipelinerun -n builds "*" -o jsonpath="*) echo true ;;
      "get taskrun -n builds -l tekton.dev/pipelineRun="*) local x; for x in $BANC_TACHES; do printf '%s ' "${6#*=}-$x"; done ;;
      "get taskrun -n builds "*" -o json") cat "$BANC_OBJ/tr-$5.json" ;;
      "get pod -n builds "*" -o json") cat "$BANC_OBJ/pod-$5.json" ;;
      "logs -n builds "*" -c "*) cat "$BANC_OBJ/${4%-pod}-$6.log" ;;
      "get networkpolicy -n builds -o json") cat "$BANC_OBJ/np.json" ;;
      "get ciliumnetworkpolicy -n builds -o json") echo '{"items": []}' ;;
      *) echo "faux kubectl : appel inattendu : $*" >&2; return 3 ;;
    esac
  }
}

oras_fermeture() { # manifeste du digest de l'état servi : 230 couches
  oras() { case "$*" in *"@$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$BANC_OBJ/etat.json")"*) jq -n '{layers: [range(230) | {}]}' ;;
    *) echo "faux oras : $*" >&2; return 3 ;; esac; }
}
oras_construction() { # descripteur : le digest demandé ; manifeste : une couche
  oras() { local x=${*: -1}
    case "$*" in
      "manifest fetch --descriptor "*) jq -n --arg d "${x##*@}" '{digest: $d}' ;;
      "manifest fetch "*) jq -n '{layers: [{}]}' ;;
      *) echo "faux oras : $*" >&2; return 3 ;;
    esac
  }
}

echo "## E fermeture : vraie fonction, faux kubectl servant les objets réels de m1b-rpm-1"
EO=$B/e-objets
transposer "$W0/m1b-fermeture-05" m1b-rpm-1 "$EO" banc-e-rpm-1 tr-m1b-rpm-1-prefetch.json tr-m1b-rpm-1-publier.json \
  pod-m1b-rpm-1-prefetch-pod.json pod-m1b-rpm-1-publier-pod.json m1b-rpm-1-prefetch-step-prefetch.log m1b-rpm-1-publier-step-publier.log
verifie "E objets transposés (6 fichiers, plus aucun nom m1b-rpm-)" "$(find "$EO" -type f | wc -l) $(cat "$EO"/* | grep -c 'm1b-rpm-')" "6 0"
F09=sha256:0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f
etat_pr() { # dossier digest : PipelineRun réussi, résultats IMAGE_URL et IMAGE_DIGEST
  jq -n --arg u "$REG/builds/fermetures/sample-app-rpm" --arg d "$2" '{status: {conditions: [{type: "Succeeded", status: "True", reason: "Succeeded"}],
    startTime: "2026-11-20T00:00:00Z", completionTime: "2026-11-20T00:02:00Z", results: [{name: "IMAGE_URL", value: $u}, {name: "IMAGE_DIGEST", value: $d}]}}' > "$1/etat.json"
}
etat_pr "$EO" "$F09"
mkdir -p "$B/e-autre" && cp "$EO"/* "$B/e-autre/" && etat_pr "$B/e-autre" sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ZE="tekton/pipelines/prefetch-rpm-sample-app@sha256:61814acd6f15f0fde07f9f701f2e8cfd4324218caf2df9e1befcf182495ca60c sha256:61814acd6f15f0fde07f9f701f2e8cfd4324218caf2df9e1befcf182495ca60c"
cas_e() { # nom code [état-de-Zot] [objets]
  local w=$B/$1; mkdir -p "$w"; printf '%s\n' "${3-$ZE}" > "$w/zot.txt"; : > "$w/appels"
  cas "$1" banc-e "BW=$w; BANC_OBJ=${4:-$EO}; BANC_TACHES='prefetch publier'; charger_mesure m1b-fermeture.sh; communes; faux_kubectl; oras_fermeture; $2"
}
creations() { grep -c '^kubectl create -f ' "$B/$1/appels"; }
cas_e E1 'rejeu_fermeture'
montre E1
verifie "E1 nominal : code, KO" "$(code E1) $(grep -c '^KO' "$B/cas-E1.out")" "0 0"
verifie "E1 nominal : un PipelineRun créé, au préfixe du banc" "$(paste -sd' ' "$B/E1/crees")" banc-e-rpm-1
verifie "E1 nominal : pipeline par digest dans le PipelineRun créé" "$(jq -r '.spec.pipelineRef.params[0].value' "$B/E1/cree.json")" \
  "$REG/tekton/pipelines/prefetch-rpm-sample-app@sha256:61814acd6f15f0fde07f9f701f2e8cfd4324218caf2df9e1befcf182495ca60c"
for m in "OK   fermeture publiée, égale à l'attendue : $F09" "OK   manifeste relu dans Zot (lecture anonyme) : couches : 230" \
         "OK   PipelineRun banc-e-rpm-1 signé par Chains : true" "OK   dans la liste revue : $REG/tekton/tasks/prefetch-rpm@" \
         "OK   dans la liste revue : $REG/tekton/tasks/publier-fermeture@" "OK   fermeture attendue, avant le PipelineRun : absent"; do
  verifie "E1 ligne « ${m:0:70}… »" "$(lignes E1 "$m")" 1
done
verifie "E1 nominal : deux TaskRuns relus" "$(grep -c '^### TaskRun banc-e-rpm-1-' "$B/cas-E1.out")" 2
cas_e E2 'rejeu_fermeture' "$ZE
builds/fermetures/sample-app-rpm@$F09 $F09"
verifie "E2 reprise : code, appels de kubectl" "$(code E2) $(wc -l < "$B/E2/appels")" "0 0"
verifie "E2 reprise : message" "$(lignes E2 "OK   fermeture attendue déjà présente")" 1
cas_e E3 'rejeu_fermeture' ""; refus E3 "pipeline présente dans Zot par digest"
cas_e E4 'BANC_PR_EXISTE=1; rejeu_fermeture'; refus E4 "banc-e-rpm-1 existe déjà"
cas_e E5 'BANC_LIBRE=5; rejeu_fermeture'; refus E5 "espace libre illisible ou sous la garde"
cas_e E6 'rejeu_fermeture' "$ZE" "$B/e-autre"; refus E6 "nouvelle signature et revue de la liste, décision du propriétaire"
cas_e E7 'ARBRE_CASCADE=$B/arbre-altere.txt; rejeu_fermeture'; refus E7 "arbre de l'essai de la cascade (sha256), égal à l'arbre prédit"
cas_e E8 'listee() { return 1; }; rejeu_fermeture'; refus E8 "absente de la liste revue"
cas_e E9 'BANC_REFUS=1; rejeu_fermeture'; refus E9 "admis en dry-run serveur"
verifie "E3 à E5, E7 à E9 : aucune création ; E6 : une" "$(for c in E3 E4 E5 E7 E8 E9 E6; do creations "$c"; done | paste -sd' ')" "0 0 0 0 0 0 1"

echo "## F construction_rpm : vraie fonction, faux kubectl servant les objets réels de m1b-construction-1"
FO=$B/f-objets
fl=(pr-m1b-construction-1-etat.json)
for k in preparer construire publier; do fl+=("tr-m1b-construction-1-$k.json" "pod-m1b-construction-1-$k-pod.json"); done
fl+=(m1b-construction-1-preparer-step-entrees.log m1b-construction-1-preparer-step-sources.log m1b-construction-1-preparer-step-assemblage.log
     m1b-construction-1-construire-step-construire.log m1b-construction-1-publier-step-publier.log)
transposer "$W0/m1b-construction-05" m1b-construction-1 "$FO" banc-f-construction-1 "${fl[@]}"
mv "$FO/pr-banc-f-construction-1-etat.json" "$FO/etat.json"
yq -o=json '{"items": [.]}' poc/bricks/05-rpm-mock/politiques/construction-rpm-sans-sortie.yaml > "$FO/np.json"
verifie "F objets transposés (13 fichiers, plus aucun nom m1b-construction-1)" "$(find "$FO" -type f | wc -l) $(cat "$FO"/* | grep -c 'm1b-construction-1')" "13 0"
D07=sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119
verifie "F état réel : digest publié 07b7bd6f" "$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$FO/etat.json")" "$D07"
mkdir -p "$B/f-autre"; for f in "$FO"/*; do sed "s/${D07#sha256:}/dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/g" "$f" > "$B/f-autre/${f##*/}"; done
mkdir -p "$B/f-sans-np"; cp "$FO"/* "$B/f-sans-np/"; echo '{"items": []}' > "$B/f-sans-np/np.json"
ZF="tekton/pipelines/sample-app-rpm@sha256:7d361cb1d5ea9b7994727f839bc4365a29e4ebdc7948fceff4176b4a371abd6a sha256:7d361cb1d5ea9b7994727f839bc4365a29e4ebdc7948fceff4176b4a371abd6a
builds/fermetures/sample-app-rpm@$F09 $F09
builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21 sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21
entrees/sample-app/packaging-rpm@$A333 $A333"
cas_f() { # nom code [état-de-Zot] [objets]
  local w=$B/$1; mkdir -p "$w"; printf '%s\n' "${3-$ZF}" > "$w/zot.txt"; : > "$w/appels"
  cas "$1" banc-f "BW=$w; BANC_OBJ=${4:-$FO}; BANC_TACHES='preparer construire publier'; charger_mesure m1b-construction.sh; communes; faux_kubectl; oras_construction; $2"
}
cas_f F1 'rejeu_construction'
montre F1
verifie "F1 nominal : code, KO" "$(code F1) $(grep -c '^KO' "$B/cas-F1.out")" "0 0"
verifie "F1 nominal : un PipelineRun créé, au préfixe du banc" "$(paste -sd' ' "$B/F1/crees")" banc-f-construction-1
verifie "F1 nominal : pipeline par digest, commit, Kata pour construire" \
  "$(jq -c '[.spec.pipelineRef.params[0].value, (.spec.params[] | select(.name == "commit") | .value), .spec.taskRunSpecs[0].podTemplate.runtimeClassName]' "$B/F1/cree.json")" \
  "[\"$REG/tekton/pipelines/sample-app-rpm@sha256:7d361cb1d5ea9b7994727f839bc4365a29e4ebdc7948fceff4176b4a371abd6a\",\"6391fd437f26696847041be3226bbbf633f55a2f\",\"kata\"]"
for m in "OK   construire : DIGEST_CONSTRUIT égal au digest publié : $D07" "OK   manifeste relu dans Zot (lecture anonyme) : digest du descripteur, couches : $D07 1" \
         "relevé : artefact rpm $REG/builds/sample-app-rpm@$D07 ; celui de la cascade $D07 : égaux (relevé, non exigé)" \
         "OK   PipelineRun banc-f-construction-1 signé par Chains : true" "OK   construction-rpm-sans-sortie : sélecteur, types, règles d'entrée et de sortie" \
         "OK   entrée présente dans Zot par digest : builds/fermetures/sample-app-sources@" "OK   construire : témoins réseau en échec : 4" \
         "OK   construire : mock --hermetic-build rc 0 : 1" "OK   construire : aucune ligne http ou https (mock.out, root.log, build.log) : 3"; do
  verifie "F1 ligne « ${m:0:70}… »" "$(lignes F1 "$m")" 1
done
verifie "F1 nominal : trois TaskRuns relus" "$(grep -c '^### TaskRun banc-f-construction-1-' "$B/cas-F1.out")" 3
verifie "F1 nominal : lignes jeton ou token non masquées dans la sortie" "$(grep -i 'jeton\|token' "$B/cas-F1.out" | grep -v -c 'ligne masquée : motif jeton|token')" 0
cas_f F2 'rejeu_construction' "$ZF" "$B/f-autre"
verifie "F2 digest différent : code, relevé" "$(code F2) $(grep -c 'celui de la cascade .* : différents (relevé, non exigé)$' "$B/cas-F2.out")" "0 1"
cas_f F3 'rejeu_construction' "$ZF" "$B/f-sans-np"; refus F3 "construction-rpm-sans-sortie : sélecteur, types"
cas_f F4 'rejeu_construction' "$(grep -v sample-app-sources <<< "$ZF")"; refus F4 "entrée présente dans Zot par digest : builds/fermetures/sample-app-sources@"
cas_f F5 'BANC_PR_EXISTE=1; rejeu_construction'; refus F5 "banc-f-construction-1 existe déjà"
cas_f F6 'rejeu_construction' "$(grep -v tekton/pipelines <<< "$ZF")"; refus F6 "pipeline présente dans Zot par digest"
verifie "F3 à F6 : aucune création" "$(for c in F3 F4 F5 F6; do creations "$c"; done | paste -sd' ')" "0 0 0 0"
mkdir -p "$B/f-temoins"; cp "$FO"/* "$B/f-temoins/"
grep -v '^témoin ' "$FO/banc-f-construction-1-construire-step-construire.log" > "$B/f-temoins/banc-f-construction-1-construire-step-construire.log"
verifie "F7 journal de construire sans les lignes de témoins (banc)" "$(grep -c '^témoin ' "$B/f-temoins/banc-f-construction-1-construire-step-construire.log")" 0
cas_f F7 'rejeu_construction' "$ZF" "$B/f-temoins"; refus F7 "construire : témoins réseau en échec"
verifie "F7 : une création (garde après le PipelineRun)" "$(creations F7)" 1

echo "## fin : $(date -u +%FT%TZ)"
echo "bilan : $OK OK, $KO KO"
[ "$KO" = 0 ]
