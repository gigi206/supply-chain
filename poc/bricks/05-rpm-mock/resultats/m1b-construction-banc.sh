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
for d in "$W0/$B-construction-05" "$W0"/$B-*-construction-05 "$W0/$B-r" "$W0/$B-r2" "$W0/$B-a.txt" "$W0/$B-local.log" "$W0/$B-liste.yml" "$W0/$B-transpose.log"; do
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
r=0; PREFIXE=$B-b bash "$F" pipeline > /dev/null 2>&1 || r=$?   # lancer refuse l'étape inconnue avant tout journal
verifie "étape inconnue (pipeline, pas encore écrite) refusée (code non nul)" "$([ "$r" != 0 ] && echo oui)" oui

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

verifie "resultats/ inchangé par le banc (git status)" "$(etat_resultats)" "$E0"
echo "# fin $(date -u +%FT%TZ) : $OK OK, $KO KO"
