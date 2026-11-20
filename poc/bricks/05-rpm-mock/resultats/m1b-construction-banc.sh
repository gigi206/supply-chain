#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b, M4c refait : banc de m1b-construction.sh, avant tout lancement. Rien n'est écrit dans Zot ni dans le
# cluster, ni dans resultats/ ; l'étape local réelle tourne sous un préfixe de banc (hôte seul, hors ligne).
#   A  copies : resultats/m1b-construction-copies.py verifier (blocs identiques à m4c.sh et m1b-bundles.sh, transformations comptées)
#   B  lanceur : bash -n ; PREFIXE invalide et m4c refusés ; étape inconnue refusée
#   C  constantes confrontées à leurs sources (m4c.sh, m1b-bundles.sh, m1b-fermeture.sh, liste revue, prédictions de l'artefact)
#   D  étape local réelle, sous le préfixe du banc (dossier $W/<préfixe>-construction-05, retiré à la main après archivage)
#   E  cas altérés : chacun doit s'arrêter en KO sur le contrôle visé ; les essais s'arrêtent avant tout appel à kubectl (doublure)
#      sans local, journal de pod déjà présent, entrees.tar différent du journal ; nominal jusqu'au premier appel à kubectl
#   F  hermetique sur des journaux archivés : celui de l'essai des bundles (bootstrap de M4b : deux écarts attendus, sur les
#      lignes du bootstrap) et sa transposition au bootstrap de M1b (aucun écart)
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-construction-banc.sh
set -uo pipefail
export LC_ALL=C
cd "$(dirname "$0")/../../../.."
F=poc/bricks/05-rpm-mock/m1b-construction.sh
D5=poc/bricks/05-rpm-mock
OK=0; KO=0
ok() { echo "OK   $*"; OK=$((OK + 1)); }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
verifie() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else ko "$1 : $2 (attendu : $3)"; fi; }
B=bancconstruction   # préfixe fixe : ses dossiers sous $W sont retirés à la main, par chemin littéral, après archivage du journal
W0=$(bash -c 'here=poc/bricks/08-trust-plane; . "$here/commun.sh"; echo "$W"')
for d in "$W0/$B-construction-05" "$W0"/$B-*-construction-05 "$W0/$B-ef" "$W0/$B-r3" "$W0/$B-r" "$W0/$B-r2" "$W0/$B-a.txt" "$W0/$B-local.log" "$W0/$B-liste.yml" "$W0/$B-transpose.log"; do
  [ ! -e "$d" ] || { echo "KO   reste d'un banc précédent : ${d#"$W0"/}" >&2; exit 2; }
done
etat_resultats() { git status --porcelain --untracked-files=all -- "$D5/resultats" | sha256sum | cut -c1-64; }
E0=$(etat_resultats)
echo "# banc de m1b-construction.sh ($(sha256sum < "$F" | cut -c1-64)), préfixe $B, début $(date -u +%FT%TZ)"

echo "## A copies"
if python3 -I "$D5/resultats/m1b-construction-copies.py" verifier "$D5" > "$W0/$B-a.txt" 2>&1; then
  ok "copies : $(grep -c '^OK' "$W0/$B-a.txt") contrôles"; else ko "copies : $(tail -n 3 "$W0/$B-a.txt" | tr '\n' ' ')"; fi

echo "## B lanceur"
verifie "bash -n" "$(bash -n "$F" && echo ok)" ok
r=0; PREFIXE='x y' bash "$F" local > /dev/null 2>&1 || r=$?
verifie "PREFIXE invalide refusé (code)" "$r" 2
r=0; PREFIXE=m4c bash "$F" local > /dev/null 2>&1 || r=$?
verifie "PREFIXE m4c refusé (code)" "$r" 2
r=0; PREFIXE=$B-b bash "$F" inconnue > /dev/null 2>&1 || r=$?   # lancer refuse l'étape inconnue avant tout journal
verifie "étape inconnue refusée (code non nul)" "$([ "$r" != 0 ] && echo oui)" oui
for t in m4b m4c essai A; do r=0; TAG=$t bash "$F" local > /dev/null 2>&1 || r=$?; verifie "TAG=$t refusé (code)" "$r" 2; done

echo "## C constantes confrontées à leurs sources"
rhs() { sed -n "s/^$2=\([^ ]*\).*/\1/p" "$1"; }   # fichier variable : membre droit (premier mot) de l'affectation
for v in PREFETCH_IMAGE OUTILS_IMAGE FERMETURE_SOURCES PUBLIER_REF PREPARER_REF EPOQUE IMAGE COMMIT DEPOT_GIT ARBRE SPEC SPEC_SHA S4B PKG \
    ARCHIVE_SHA RPM_M3 RPM_M3_SHA SRPM_M3_SHA GO LISTE_REVUE LAYOUT_PREFETCH BUSYBOX_PREFETCH LABEL_PREPARER LABEL_CONSTRUIRE MORCEAU_MIO FACTICE; do
  verifie "$v égale à celle de m4c.sh" "$(rhs "$F" "$v")" "$(rhs "$D5/m4c.sh" "$v")"
done
verifie "IMAGE_OUTILLAGE égale à IMAGE_NEUVE de m1b-bundles.sh" "$(rhs "$F" IMAGE_OUTILLAGE)" "$(rhs "$D5/m1b-bundles.sh" IMAGE_NEUVE)"
verifie "SCRIPT_CONSTRUIRE_SHA égale à celle de m1b-bundles.sh" "$(rhs "$F" SCRIPT_CONSTRUIRE_SHA)" "$(rhs "$D5/m1b-bundles.sh" SCRIPT_CONSTRUIRE_SHA)"
verifie "DIGEST_ESSAI_M4C égale à celle de m1b-bundles.sh et à DIGEST_ESSAI de m4c.sh" "$(rhs "$F" DIGEST_ESSAI_M4C) $(rhs "$F" DIGEST_ESSAI_M4C)" \
  "$(rhs "$D5/m1b-bundles.sh" DIGEST_ESSAI_M4C) $(rhs "$D5/m4c.sh" DIGEST_ESSAI)"
verifie "FERMETURE_RPM : dépôt de M4b refait et FERMETURE_NEUVE de m1b-fermeture.sh" "$(rhs "$F" FERMETURE_RPM)" \
  "$(rhs "$D5/m1b-fermeture.sh" DEPOT_FERMETURE)@$(rhs "$D5/m1b-fermeture.sh" FERMETURE_NEUVE)"
verifie "PACKAGING égale à la référence citée par les prédictions de l'artefact" "$(rhs "$F" PACKAGING | sed 's#^\$REG/##')" \
  "$(sed -n 's/^\*\*Référence à citer dans la suite de la cascade\*\* : `PACKAGING_RPM=sc-stockage.poc.test:5000\/\([^`]*\)`\.$/\1/p' "$D5/resultats/m1b-predictions.md")"
verifie "VERROU_SHA égale à celle de m1b-fermeture.sh" "$(rhs "$F" VERROU_SHA)" "$(rhs "$D5/m1b-fermeture.sh" VERROU_SHA)"
CR=$(rhs "$F" CONSTRUIRE_REF | sed 's/.*@//')
verifie "CONSTRUIRE_REF : digest présent une fois dans la liste revue" "$(grep -c -F -- "- ref: $CR" "$D5/../08-trust-plane/politique/porte/taches.yml")" 1
verifie "CONSTRUIRE_REF : bundle poussé par l'étape taches des bundles (m1b-bundles-taches.log)" \
  "$(grep -c -F -- "tekton/tasks/construire-rpm@$CR" "$D5/resultats/m1b-bundles-taches.log" | sed 's/^[1-9][0-9]*$/présent/')" présent
verifie "TIREE : dossier tiré par etape_comparaison de m1b-fermeture.sh (T=\$W/\$N-fermeture-05, préfixe m1b)" \
  "$(rhs "$F" TIREE) $(grep -c -F -e '  local c=$T/comparaison ' -e '-o "$c/tiree"' "$D5/m1b-fermeture.sh")" '$W/m1b-fermeture-05/comparaison/tiree 2'
verifie "ARBRE_FERMETURE_SHA : sha256 de l'arbre archivé de l'essai de M4b refait" "$(rhs "$F" ARBRE_FERMETURE_SHA)" \
  "$(sha256sum < "$D5/resultats/m1b-fermeture-essai-arbre.txt" | cut -c1-64)"
for e in construction/preparer-rpm.yaml construction/construire-rpm.yaml construction/sample-app-rpm.yaml; do
  verifie "GABARITS_SHA : $e égal à m4c.sh" "$(grep -o -F "$e:" "$F" | wc -l) $(grep -o "${e#construction/}:[0-9a-f]\{64\}" "$F")" "1 $(grep -o "${e#construction/}:[0-9a-f]\{64\}" "$D5/m4c.sh")"
done

echo "## D étape local réelle"
( PREFIXE=$B; . "$F"; etape_local ) > "$W0/$B-local.log" 2>&1; r=$?   # jamais dans un || : bash y couperait set -e
sed 's/^/     /' "$W0/$B-local.log" | cut -c1-250
verifie "local (code)" "$r" 0
verifie "local : KO" "$(grep -c '^KO' "$W0/$B-local.log")" 0
NL=$(grep -c '^OK' "$W0/$B-local.log")
echo "relevé : local : $NL OK"
verifie "local : entrees.tar journalisé (une ligne)" "$(grep -c '^entrees.tar : [0-9]* octets, sha256 [0-9a-f]\{64\}$' "$W0/$B-local.log")" 1
verifie "local : confrontation au verrou neuf (dossier dir: 6de899ac, image_digest 77cff176)" \
  "$(grep -c '^OK   confrontation : sortie (dossier dir:, image_digest) : sc-stockage.poc.test@sha256:6de899ac[0-9a-f]* 77cff176[0-9a-f]*$' "$W0/$B-local.log")" 1
verifie "local : tâches rendues égales aux signées" "$(grep -c '^OK   \(preparer\|construire\)-rpm rendue égale à construction/.*normalisées : égale$' "$W0/$B-local.log")" 2
verifie "local : entrees/verrou-rpm.json égal au verrou de M1b" "$(grep -c '^OK   entrees/verrou-rpm.json égal au verrou de M1b : égal$' "$W0/$B-local.log")" 1

echo "## E cas altérés (KO attendu sur le contrôle visé)"
altere() { # libellé motif-du-KO-attendu code-bash : préfixe $B-<E…> propre au cas
  local r=0 s
  s=$( ( PREFIXE=$B-${1%% *}; PREFIXE=${PREFIXE,,}; . "$F"; eval "$3" ) 2>&1 ); r=$?   # hors d'un || : set -e actif
  if [ "$r" != 0 ] && grep -q -F -- "$2" <<< "$s"; then ok "$1 : arrêt sur « $2 »"
  else ko "$1 : code $r, dernier message : $(grep '^KO' <<< "$s" | tail -n 1 | cut -c1-200)"; fi
}
FK='kubectl() { echo "KO   kubectl appelé : $*" >&2; exit 9; }'
altere "E1 verrou de M4c à la place du neuf" "KO   verrou neuf : dossier dir: du bootstrap" 'VERROU=$R/s1-verrou_derivee.json; etape_local'
grep -v -F 'ca03f18908d0b5e73edc57ecf9610513e2907267ce1da2d9f41fd36b969289c5' "$D5/../08-trust-plane/politique/porte/taches.yml" > "$W0/$B-liste.yml"
altere "E2 construire-rpm hors de la liste revue" "KO   construire-rpm ca03f189 : absente de la liste revue" "LISTE_REVUE=$W0/$B-liste.yml; etape_local"
altere "E3 image_digest du bootstrap altéré" "KO   verrou neuf : image_digest du bootstrap" 'IMAGE_DIGEST_BOOT=${IMAGE_DIGEST_BOOT/77cf/0000}; etape_local'
altere "E4 gabarit signé de construire-rpm modifié" "KO   construction/construire-rpm.m1b.signee.yaml (sha256)" 'GABARITS_SHA=${GABARITS_SHA/90151d43/00000000}; etape_local'
altere "E5 essai_preparer sans local" "KO   lancer d'abord local" "$FK; etape_essai_preparer"
altere "E6 essai sans local" "KO   lancer d'abord local" "$FK; etape_essai"
mkdir -p "$W0/$B-r"; grep '^entrees.tar : ' "$W0/$B-local.log" > "$W0/$B-r/$B-construction-local.log"
altere "E7 essai : nominal jusqu'au premier appel à kubectl" "KO   kubectl appelé : get networkpolicy" "R=$W0/$B-r; PREFIXE=$B; T=$W0/$B-construction-05; N=$B; $FK; etape_essai"
verifie "E7 : journal de pod non créé" "$(ls -A "$W0/$B-r" | paste -sd' ')" "$B-construction-local.log"
mkdir -p "$W0/$B-r2"; cp "$W0/$B-r/$B-construction-local.log" "$W0/$B-r2/"; : > "$W0/$B-r2/$B-construction-construire-pod.log"
altere "E8 essai : journal de pod déjà présent" "KO   déjà présent" "R=$W0/$B-r2; T=$W0/$B-construction-05; N=$B; $FK; etape_essai"
altere "E9 essai : entrees.tar différent du journal de local" "KO   entrees.tar de local (taille, sha256), égal au journal de local" \
  "R=$W0/$B-r; T=$W0/$B-construction-05; N=$B; sha() { echo 0; }; $FK; etape_essai"
altere "E10 essai_preparer : nominal jusqu'au premier appel à kubectl" "KO   kubectl appelé : get networkpolicy" \
  "R=$W0/$B-r; T=$W0/$B-construction-05; N=$B; $FK; etape_essai_preparer"
verifie "E10 : journal de pod non créé" "$(ls -A "$W0/$B-r" | paste -sd' ')" "$B-construction-local.log"

echo "## F hermetique sur des journaux archivés"
J=$D5/resultats/m1b-bundles-construire-pod.log
s=$( ( PREFIXE=$B; . "$F"; hermetique "$J"; echo "écarts : $ECARTS" ) 2>&1 )
sed 's/^/     /' <<< "$s" | cut -c1-200
verifie "F1 bootstrap de M4b : écarts" "$(sed -n 's/^écarts : //p' <<< "$s")" 2
verifie "F1 : écarts sur les deux lignes du bootstrap (mot qui suit le guillemet)" \
  "$(sed -n 's/^ÉCART ligne du script « \([a-z]*\) \([a-zA-Z«]*\) *\([A-Za-z]*\).*/\1 \3/p' <<< "$s" | paste -sd'|')" "dossier |lignes Checking"
# fichier, non une substitution de processus : hermetique lit le journal plusieurs fois (banc 1)
sed -e 's/f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6/6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3/' \
  -e 's/18d64b0330fe240fff58475e43a3f003e5dcfade898c4caa1d1165e8304be1af/77cff1767fea08670831a740051c2cc0c4025e74b48ed1c96d59cf06824e89ca/' "$J" > "$W0/$B-transpose.log"
s=$( ( PREFIXE=$B; . "$F"; hermetique "$W0/$B-transpose.log"; echo "écarts : $ECARTS" ) 2>&1 )
verifie "F2 transposé au bootstrap de M1b : écarts" "$(sed -n 's/^écarts : //p' <<< "$s")" 0
verifie "F2 : OK" "$(grep -c '^OK' <<< "$s")" 12

echo "## G étape pipeline (vraie fonction, vrai tkn, clé P-256 jetable ; doublures : kubectl, zot_lire, bundle, auth_zot, sur, lire_bundle du bundle neuf)"
EF=$W0/$B-ef
mkdir -p "$EF/cle"
(umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$EF/cle/taches.key" 2> /dev/null)
openssl pkey -in "$EF/cle/taches.key" -pubout -out "$EF/cle/taches.pub" 2> /dev/null
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2> /dev/null | openssl pkey -pubout -out "$EF/cle/autre.pub" 2> /dev/null
verifie "G clé jetable du banc (P-256)" "$(openssl pkey -in "$EF/cle/taches.pub" -pubin -noout -text 2> /dev/null | grep -c 'NIST CURVE: P-256')" 1
CA=$(dirname "$W0")/pki/ca-poc.crt   # certificat public de la CA du PoC (lectures anonymes réelles : bundle de M4c, artefact, .att)
FAUSSE=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa   # digest de pipeline du banc
ZOT_BASE="tekton/pipelines/sample-app-rpm:m4c sha256:ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be
builds/sample-app-rpm@sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119 sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119"
doublures() { # après chargement du script, dans le sous-shell du cas
  eval "lire_bundle_reel() $(declare -f lire_bundle | tail -n +2)"
  kubectl() {
    echo "kubectl $*" >> "$BW/appels"
    case "$*" in
      "create --dry-run=server -n builds -f "*)
        if [ -n "${BANC_REFUSEE:-}" ] && [ "$(yq .metadata.name "${*: -1}")" = "$BANC_REFUSEE" ]; then echo "refus du banc" >&2; return 1; fi
        return 0 ;;
      "get pipelinerun -n builds "*" -o name") if [ -n "${BANC_PR_EXISTE:-}" ]; then return 0; else echo "NotFound (banc)" >&2; return 1; fi ;;
      "get networkpolicy -n builds -o json"|"get ciliumnetworkpolicy -n builds -o json") command kubectl "$@"; return ;;   # lecture réelle
      "create -f "*) cp "${*: -1}" "$BW/cree.json"; echo "création interceptée par le banc" >&2; return 7 ;;
    esac
    echo "faux kubectl : appel inattendu : $*" >&2; return 3
  }
  zot_lire() { local d; d=$(awk -v r="$2" '$1 == r {x = $2} END {print x}' "$BW/zot.txt"); echo "${d:-absent}"; }
  bundle() { local d; d=sha256:$(sha256sum < "$1" | cut -c1-64); echo "$2:$3 $d" >> "$BW/poussees"; echo "$2:$3 $d" >> "$BW/zot.txt"; echo "$d"; }
  auth_zot() { printf '{"faux":1}\n' > "$1"; }
  sur() { echo " ${BANC_LIBRE-3000000000}"; }
  lire_bundle() { if [ "$1" = "$PIPELINE_M4C" ]; then lire_bundle_reel "$@"; else yq -o=json "$C/sample-app-rpm.$TAG.signee.yaml" > "$2"; fi; }
  oras() { # tag de la pipeline du banc : lu dans zot.txt ; tout le reste, le vrai oras (lectures anonymes)
    case "$*" in *"sample-app-rpm:$TAG"*) echo "{\"digest\":\"$(zot_lire t "tekton/pipelines/sample-app-rpm:$TAG")\"}" ;; *) command oras "$@" ;; esac
  }
}
ef() { # nom code-bash [sans-clé] : un cas dans un sous-shell (CONFIANCE_DIR, construction/ et resultats/ du banc, état de Zot) ; code
  local w=$EF/$1 r=0
  mkdir -p "$w/O/pki" "$w/O/secrets" "$w/construction" "$w/r"; chmod 700 "$w/O/secrets"
  cp "$CA" "$w/O/pki/ca-poc.crt"
  cp "$D5/construction/sample-app-rpm.yaml" "$D5/construction/preparer-rpm.yaml" "$D5/construction/construire-rpm.yaml" "$w/construction/"
  cp "$D5/resultats/m1b-construction-essai.log" "$w/r/$B-${1,,}-construction-essai.log"
  [ -n "${3:-}" ] || (umask 077 && cp "$EF/cle/taches.key" "$w/O/secrets/taches.key")
  printf '%s\n' "$ZOT_BASE" > "$w/zot.txt"; : > "$w/appels"; : > "$w/poussees"
  ( export CONFIANCE_DIR=$w/O BW=$w PREFIXE=$B-${1,,}; . "$F"; C=$w/construction; R=$w/r; TIREE=$W0/m1b-fermeture-05/comparaison/tiree
    doublures; eval "$2" ) > "$w/sortie.txt" 2>&1; r=$?   # hors d'un || : set -e actif
  echo "$r"
}
cas() { mkdir -p "$EF/$1"; ef "$@" > "$EF/$1.code"; mv "$EF/$1.code" "$EF/$1/code"; }
attendu_ko() { # cas motif : arrêt en KO sur le motif, sans poussée ni signature versionnée ni création
  local w=$EF/$1
  if [ "$(cat "$w/code")" != 0 ] && grep -q -F -- "$2" "$w/sortie.txt"; then ok "$1 : arrêt sur « $2 »"
  else ko "$1 : code $(cat "$w/code"), dernier message : $(grep '^KO' "$w/sortie.txt" | tail -n 1 | cut -c1-200)"; fi
  verifie "$1 : ni poussée, ni signature versionnée, ni création" \
    "$(wc -l < "$w/poussees") $(find "$w/construction" -name '*.signee.yaml' -size +0 | wc -l) $([ -e "$w/cree.json" ] && echo 1 || echo 0)" "0 0 0"
}
cas G1 'SIGNER=1; etape_pipeline'
grep -v '^     ' "$EF/G1/sortie.txt" | cut -c1-170 | sed 's/^/   | /'
v=$EF/G1/construction/sample-app-rpm.$B-g1.signee.yaml
verifie "G1 nominal : code" "$(cat "$EF/G1/code")" 0
verifie "G1 nominal : KO" "$(grep -c '^KO' "$EF/G1/sortie.txt")" 0
echo "relevé : G1 nominal : $(grep -c '^OK' "$EF/G1/sortie.txt") OK"
verifie "G1 nominal : poussée unique (dépôt:tag digest)" "$(cat "$EF/G1/poussees")" "tekton/pipelines/sample-app-rpm:$B-g1 sha256:$(sha256sum < "$v" | cut -c1-64)"
verifie "G1 nominal : signature versionnée vérifiée par tkn (clé publique du banc)" "$(tkn pipeline verify "$v" -K "$EF/cle/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
verifie "G1 nominal : refus de tkn avec une autre clé" "$(tkn pipeline verify "$v" -K "$EF/cle/autre.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" refusée
verifie "G1 nominal : références de la version (preparer-rpm, construire-rpm, publier-image)" \
  "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$v")" \
  "sc-stockage.poc.test:5000/tekton/tasks/preparer-rpm@sha256:2f65f3903e98caa9944ab3fee4b67585b15d67ad477ff48a8487e8e86af5526f sc-stockage.poc.test:5000/tekton/tasks/construire-rpm@sha256:ca03f18908d0b5e73edc57ecf9610513e2907267ce1da2d9f41fd36b969289c5 sc-stockage.poc.test:5000/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b"
verifie "G1 nominal : entrées de preparer et dépôt de publication dans la version" \
  "$(yq '[.spec.tasks[0].params[2].value, .spec.tasks[0].params[4].value, (.spec.tasks[2].params[] | select(.name == "image") | .value)] | join(" ")' "$v")" \
  "sc-stockage.poc.test:5000/builds/fermetures/sample-app-rpm@sha256:0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f sc-stockage.poc.test:5000/entrees/sample-app/packaging-rpm@sha256:333b7322290ab5edd85989908fa2e181a48a72facfd4043e181a2962d2bcfe48 sc-stockage.poc.test:5000/builds/sample-app-rpm"
verifie "G1 nominal : feuilles relevées (trois)" "$(grep -c '^OK   rendue : feuilles différentes de la pipeline de M4c : .spec.tasks\[0\].params\[2\].value .spec.tasks\[0\].params\[4\].value .spec.tasks\[1\].taskRef.params\[0\].value$' "$EF/G1/sortie.txt")" 1
verifie "G1 nominal : \$T/auth absent à la fin" "$([ -e "$EF/G1/O/travail/$B-g1-construction-05/auth" ] && echo présent || echo absent)" absent
verifie "G1 nominal : appels de kubectl, dry-run serveur seulement" "$(grep -v -c '^kubectl create --dry-run=server -n builds -f ' "$EF/G1/appels")" 0
cas G2 'etape_pipeline'; attendu_ko G2 "KO   étape pipeline : SIGNER=1 seulement"
cas G3 'SIGNER=1; etape_pipeline' sans-cle; attendu_ko G3 "KO   clé des tâches absente"
mkdir -p "$EF/G4/construction"; : > "$EF/G4/construction/sample-app-rpm.$B-g4.signee.yaml"
cas G4 'SIGNER=1; etape_pipeline'
if [ "$(cat "$EF/G4/code")" != 0 ] && grep -q -F "KO   déjà présent" "$EF/G4/sortie.txt" && [ ! -s "$EF/G4/poussees" ]; then ok "G4 version déjà présente : arrêt, sans poussée"; else ko "G4 version déjà présente"; fi
cas G5 'SIGNER=1; echo "tekton/pipelines/sample-app-rpm:$TAG $FAUSSE" >> "$BW/zot.txt"; etape_pipeline'; attendu_ko G5 "de la pipeline, absent"
cas G6 "SIGNER=1; echo \"tekton/pipelines/sample-app-rpm:m4c $FAUSSE\" >> \"\$BW/zot.txt\"; etape_pipeline"; attendu_ko G6 "KO   tag m4c de la pipeline, sur celle de M4c"
cas G7 'SIGNER=1; BANC_LIBRE=1000; etape_pipeline'; attendu_ko G7 "sous 1073741824"
cas G8 'SIGNER=1; BANC_REFUSEE=sample-app-rpm; etape_pipeline'; attendu_ko G8 "KO   pipeline rendue admise"
cas G9 'SIGNER=1; PUBLIER_REF=${PUBLIER_REF/d21931f3/00000000}; etape_pipeline'; attendu_ko G9 "KO   publier-image, lue dans la liste revue"
cas G10 'SIGNER=1; sed -i "s/^écarts : 0$/écarts : 1/" "$R/$N-construction-essai.log"; etape_pipeline'; attendu_ko G10 "KO   essai archivé"
cas G11 'SIGNER=1; FERMETURE_RPM=${FERMETURE_RPM%@*}@sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c; etape_pipeline'; attendu_ko G11 "KO   rendue : feuilles différentes de la pipeline de M4c"   # fermeture de M4b : deux feuilles seulement

echo "## H étape construction, gardes (vraie fonction, mêmes doublures ; la première création réelle est interceptée)"
PR_OK="PIPELINE_REF=\$REG/tekton/pipelines/sample-app-rpm@$FAUSSE; mkdir -p \"\$T/pipeline\"; echo \"\$PIPELINE_REF\" > \"\$T/pipeline/pipeline.ref\"; echo \"tekton/pipelines/sample-app-rpm:\$TAG $FAUSSE\" >> \"\$BW/zot.txt\""
cas H1 'PIPELINE_REF=; etape_construction'; attendu_ko H1 "KO   PIPELINE_REF non épinglée"
verifie "H1 : aucun appel de kubectl" "$(wc -l < "$EF/H1/appels")" 0
cas H2 "PIPELINE_REF=\$REG/tekton/pipelines/sample-app-rpm@$FAUSSE; etape_construction"; attendu_ko H2 "KO   référence de la pipeline absente"
cas H3 "$PR_OK; echo \"tekton/pipelines/sample-app-rpm:m4c $FAUSSE\" >> \"\$BW/zot.txt\"; etape_construction"; attendu_ko H3 "KO   tag m4c de la pipeline, inchangé"
cas H4 "$PR_OK; : > \"\$R/\$N-construction-2-construire.log\"; etape_construction"; attendu_ko H4 "KO   déjà présent"
cas H5 "$PR_OK; sed -i '\$d' \"\$BW/zot.txt\"; etape_construction"; attendu_ko H5 "KO   pipeline relue dans Zot au tag"
cas H6 "$PR_OK; CONSTRUIRE_REF=\${CONSTRUIRE_REF/ca03f189/00000000}; etape_construction"; attendu_ko H6 "absente de la liste revue"
cas H7 "$PR_OK; sed -i '/^builds/d' \"\$BW/zot.txt\"; etape_construction"; attendu_ko H7 "KO   artefact de M4c présent avant le premier PipelineRun"
cas H8 "$PR_OK; BANC_PR_EXISTE=1; etape_construction"; attendu_ko H8 "$B-h8-construction-1 existe déjà"
cas H9 "$PR_OK; BANC_LIBRE=1000; etape_construction"; attendu_ko H9 "KO   espace libre illisible ou sous la garde"
cas H10 "$PR_OK; etape_construction"
grep -v '^     ' "$EF/H10/sortie.txt" | cut -c1-170 | sed 's/^/   | /'
verifie "H10 nominal jusqu'à la création : arrêt sur la création interceptée (code)" "$(cat "$EF/H10/code")" 7
verifie "H10 : KO avant la création" "$(grep -c '^KO' "$EF/H10/sortie.txt")" 0
verifie "H10 : enveloppes relevées avant (lecture anonyme réelle)" "$(grep -c "^relevé : enveloppes d'attestation de l'artefact (avant) : [0-9]* " "$EF/H10/sortie.txt")" 1
verifie "H10 : PipelineRun créé (nom, bundle, nom, PVC, Kata pour construire seule)" \
  "$(jq -c '[.metadata.name, .spec.pipelineRef.params[0].value, .spec.pipelineRef.params[1].value, .spec.workspaces[0].volumeClaimTemplate.spec.resources.requests.storage, [.spec.taskRunSpecs[] | .pipelineTaskName + ":" + .podTemplate.runtimeClassName]]' "$EF/H10/cree.json")" \
  "[\"$B-h10-construction-1\",\"sc-stockage.poc.test:5000/tekton/pipelines/sample-app-rpm@$FAUSSE\",\"sample-app-rpm\",\"2Gi\",[\"construire:kata\"]]"

echo "## I étape construction jusqu'au bout : faux kubectl servant les objets réels des PipelineRuns de M4c (TaskRuns, pods, journaux,"
echo "##   gardés sous \$W/m4c-05), valeurs de M4c remplacées par celles de la cascade ; lectures anonymes réelles de l'artefact et du .att"
M4C=$W0/m4c-05
G=$EF/I-objets
mkdir -p "$G"
for i in 1 2; do
  for f in "pr-m4c-rpm-$i-etat.json" "tr-m4c-rpm-$i-preparer.json" "tr-m4c-rpm-$i-construire.json" "tr-m4c-rpm-$i-publier.json" \
           "pod-m4c-rpm-$i-preparer-pod.json" "pod-m4c-rpm-$i-construire-pod.json" "pod-m4c-rpm-$i-publier-pod.json" \
           "m4c-rpm-$i-preparer-step-sources.log" "m4c-rpm-$i-preparer-step-entrees.log" "m4c-rpm-$i-preparer-step-assemblage.log" \
           "m4c-rpm-$i-construire-step-construire.log" "m4c-rpm-$i-publier-step-publier.log"; do
    sed -e "s/m4c-rpm-/$B-i-construction-/g" \
      -e 's/d7f01398f188931c124273c8b5fb60e2a66c22e9d0a2dfcd229ecadee1e62164/ca03f18908d0b5e73edc57ecf9610513e2907267ce1da2d9f41fd36b969289c5/g' \
      -e "s/ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be/${FAUSSE#sha256:}/g" \
      -e 's/2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c/0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f/g' \
      -e 's/41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8/333b7322290ab5edd85989908fa2e181a48a72facfd4043e181a2962d2bcfe48/g' \
      -e 's/f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6/6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3/g' \
      -e 's/18d64b0330fe240fff58475e43a3f003e5dcfade898c4caa1d1165e8304be1af/77cff1767fea08670831a740051c2cc0c4025e74b48ed1c96d59cf06824e89ca/g' \
      -e 's#essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771#builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae#g' \
      -e 's#essais-05/rocky9-bootstrap#builds/builders/rocky9-bootstrap#g' \
      "$M4C/$f" > "$G/${f//m4c-rpm-/$B-i-construction-}"
  done
done
verifie "I objets de M4c transposés (24 fichiers, plus aucune valeur de M4c)" \
  "$(ls "$G" | wc -l) $(cat "$G"/* | grep -c 'm4c-rpm-\|d7f01398\|ca874375\|2a9e2ea7\|41c639b7\|f0ccf105\|18d64b03\|99790c13\|essais-05')" "24 0"
complet() { # doublures du cas I, après doublures
  kubectl() {
    echo "kubectl $*" >> "$BW/appels"
    case "$*" in
      "create --dry-run=server -n builds -f "*) return 0 ;;
      "get pipelinerun -n builds "*" -o name") grep -qx "$5" "$BW/crees" 2> /dev/null ;;   # $5 : nom de l'objet
      "create -f "*) jq -r .metadata.name "${*: -1}" >> "$BW/crees"; cp "${*: -1}" "$BW/cree-$(jq -r .metadata.name "${*: -1}").json" ;;
      "get pipelinerun -n builds "*" -o json") cat "$BANC_G/pr-$5-etat.json" ;;
      "get pipelinerun -n builds "*" -o jsonpath="*) echo true ;;   # annotation de Chains (signe)
      "get taskrun -n builds -l tekton.dev/pipelineRun="*) echo "${6#*=}-preparer ${6#*=}-construire ${6#*=}-publier" ;;
      "get taskrun -n builds "*" -o json") cat "$BANC_G/tr-$5.json" ;;
      "get pod -n builds "*" -o json") cat "$BANC_G/pod-$5.json" ;;
      "logs -n builds "*" -c "*) cat "$BANC_G/${4%-pod}-$6.log" ;;
      "get networkpolicy -n builds -o json"|"get ciliumnetworkpolicy -n builds -o json") command kubectl "$@" ;;   # lecture réelle
      *) echo "faux kubectl : appel inattendu : $*" >&2; return 3 ;;
    esac
  }
}
cas I "BANC_G=$G; complet; $PR_OK; etape_construction"
grep -v '^     \|^       ' "$EF/I/sortie.txt" | cut -c1-170 | sed 's/^/   | /'
verifie "I : code" "$(cat "$EF/I/code")" 0
verifie "I : KO et ÉCART" "$(grep -c '^KO\|^ÉCART' "$EF/I/sortie.txt")" 0
echo "relevé : I : $(grep -c '^OK' "$EF/I/sortie.txt") OK"
verifie "I : deux PipelineRuns créés, dans l'ordre" "$(paste -sd' ' "$EF/I/crees")" "$B-i-construction-1 $B-i-construction-2"
verifie "I : lignes hermétiques relevées par PipelineRun (11 lignes et les témoins, deux fois)" "$(grep -c '^OK   ligne du script « \|^OK   témoins réseau en échec' "$EF/I/sortie.txt")" 24
verifie "I : enveloppes relevées avant et après" "$(grep -c "^relevé : enveloppes d'attestation de l'artefact (\(avant\|après\)) : [0-9]* " "$EF/I/sortie.txt")" 2
verifie "I : journaux de construire archivés dans le resultats/ du banc" "$(ls "$EF/I/r" | grep -c "^$B-i-construction-[12]-construire.log$")" 2
verifie "I : lignes finales (même artefact, tag m4c inchangé après)" \
  "$(grep -c '^OK   deux exécutions, même artefact\|^OK   tag m4c de la pipeline, inchangé après' "$EF/I/sortie.txt")" 2

echo "## J essai_refus (ajouté le 20/11/2026 après construction) : gardes et chemin jusqu'au premier appel à kubectl (doublure)"
verifie "J0 IMAGE_DIGEST_FAUX : 64 caractères, seul le dernier diffère d'IMAGE_DIGEST_BOOT" \
  "$(rhs "$F" IMAGE_DIGEST_FAUX | wc -c) $(rhs "$F" IMAGE_DIGEST_FAUX | cut -c1-63) $(rhs "$F" IMAGE_DIGEST_FAUX | cut -c64)" \
  "65 $(rhs "$F" IMAGE_DIGEST_BOOT | cut -c1-63) b"
verifie "J0 IMAGE_DIGEST_BOOT : dernier caractère" "$(rhs "$F" IMAGE_DIGEST_BOOT | cut -c64)" a
altere "J1 essai_refus sans local" "KO   lancer d'abord local" "$FK; etape_essai_refus"
mkdir -p "$W0/$B-r3"; cp "$W0/$B-r/$B-construction-local.log" "$W0/$B-r3/"; : > "$W0/$B-r3/$B-construction-refus-pod.log"
altere "J2 essai_refus : journal de pod déjà présent" "KO   déjà présent" "R=$W0/$B-r3; T=$W0/$B-construction-05; N=$B; $FK; etape_essai_refus"
altere "J3 essai_refus : nominal jusqu'au premier appel à kubectl" "KO   kubectl appelé : get networkpolicy" \
  "R=$W0/$B-r; T=$W0/$B-construction-05; N=$B; $FK; etape_essai_refus"
verifie "J3 : journal de pod non créé" "$(ls -A "$W0/$B-r" | paste -sd' ')" "$B-construction-local.log"
verifie "J4 altération : une seule commande sed, du vrai au faux image_digest, dans le conteneur remplir" \
  "$(sed -n '/^etape_essai_refus() {/,/^}/p' "$F" | grep -c -F "kubectl exec -n builds \"\$p\" -c remplir -- sh -c \"sed -i 's/\$IMAGE_DIGEST_BOOT/\$IMAGE_DIGEST_FAUX/' /e/verrou-rpm.json")" 1
verifie "J5 essai_refus : aucune lecture d'image.tar ni de digest (fin remplacée)" \
  "$(sed -n '/^etape_essai_refus() {/,/^}/p' "$F" | grep -c 'tar -xf "$x/image.tar"\|DIGEST_ESSAI_M4C\|hermetique ')" 0
echo "## K comparaison et provenance (ajoutées le 20/11/2026) : arrêt sous le préfixe du banc, lectures réelles seulement"
altere "K1 comparaison sous le préfixe du banc : journaux de construire absents" "KO   journal archivé de construire absent" 'etape_comparaison'
altere "K2 provenance sous le préfixe du banc : PipelineRun absent" "KO   IMAGE_DIGEST de bancconstruction-k2-construction-1" 'etape_provenance'
verifie "K3 comparaison : tirage avec la configuration vide" "$(sed -n '/^etape_comparaison() {/,/^}/p' "$F" | grep -c -F -- '--from-registry-config "$T/vide.json"')" 1
verifie "resultats/ inchangé par le banc (git status)" "$(etat_resultats)" "$E0"
echo "# fin $(date -u +%FT%TZ) : $OK OK, $KO KO"
