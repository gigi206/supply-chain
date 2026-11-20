#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b, M4b refait : banc de m1b-fermeture.sh, avant tout lancement. Rien n'est écrit dans Zot ni dans le
# cluster ; lectures anonymes de Zot et df sur sc-stockage seulement (étape local réelle).
#   A  copies : resultats/m1b-fermeture-copies.py verifier (blocs identiques à m1b-bundles.sh, etape_essai transformée et comptée)
#   B  lanceur : PREFIXE et TAG refusés (m4b, m4c, essai, invalides), étape inconnue refusée ; bash -n
#   C  étape local réelle, sous un préfixe de banc (dossier $W/<préfixe>-fermeture-05, retiré à la fin)
#   D  cas altérés de local et d'essai : chacun doit s'arrêter en KO sur le contrôle visé, avant toute action sur le cluster
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-fermeture-banc.sh
set -uo pipefail
export LC_ALL=C
cd "$(dirname "$0")/../../../.."
F=poc/bricks/05-rpm-mock/m1b-fermeture.sh
OK=0; KO=0
ok() { echo "OK   $*"; OK=$((OK + 1)); }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
verifie() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else ko "$1 : $2 (attendu : $3)"; fi; }
B=bancfermeture   # préfixe fixe : ses dossiers sous $W sont retirés à la main, par chemin littéral, après archivage du journal
W0=$(bash -c 'here=poc/bricks/08-trust-plane; . "$here/commun.sh"; echo "$W"')
for d in "$W0/$B-fermeture-05" "$W0/$B-b-fermeture-05" "$W0"/$B-d[1-9]-fermeture-05 "$W0/$B-r" "$W0/$B-a.txt" "$W0/$B-local.log"; do
  [ ! -e "$d" ] || { echo "KO   reste d'un banc précédent : ${d#"$W0"/}" >&2; exit 2; }
done
echo "# banc de m1b-fermeture.sh ($(sha256sum < "$F" | cut -c1-64)), préfixe $B, début $(date -u +%FT%TZ)"

echo "## A copies"
if python3 -I poc/bricks/05-rpm-mock/resultats/m1b-fermeture-copies.py verifier poc/bricks/05-rpm-mock > "$W0/$B-a.txt" 2>&1; then
  ok "copies : $(grep -c '^OK' "$W0/$B-a.txt") contrôles"; else ko "copies : $(tail -n 3 "$W0/$B-a.txt" | tr '\n' ' ')"; fi

echo "## B lanceur"
verifie "bash -n" "$(bash -n "$F" && echo ok)" ok
for t in m4b m4c essai 'A' ''; do
  [ -n "$t" ] || continue
  r=0; TAG=$t bash "$F" local > /dev/null 2>&1 || r=$?
  verifie "TAG=$t refusé (code)" "$r" 2
done
r=0; PREFIXE='x y' bash "$F" local > /dev/null 2>&1 || r=$?
verifie "PREFIXE invalide refusé (code)" "$r" 2
r=0; PREFIXE=$B-b bash "$F" digest-py > /dev/null 2>&1 || r=$?   # lancer refuse l'étape inconnue avant tout journal
verifie "étape inconnue refusée (code non nul)" "$([ "$r" != 0 ] && echo oui)" oui

echo "## C étape local réelle"
r=0; ( PREFIXE=$B; . "$F"; etape_local ) > "$W0/$B-local.log" 2>&1 || r=$?
sed 's/^/     /' "$W0/$B-local.log" | cut -c1-250
verifie "local (code)" "$r" 0
verifie "local : KO" "$(grep -c '^KO' "$W0/$B-local.log")" 0
verifie "local : OK" "$(grep -c '^OK' "$W0/$B-local.log")" 35

echo "## D cas altérés (KO attendu sur le contrôle visé)"
altere() { # libellé motif-du-KO-attendu code-bash : préfixe $B-<D1…> propre au cas (dossier neuf, rien à vider)
  local r=0 s
  s=$( ( PREFIXE=$B-${1%% *}; PREFIXE=${PREFIXE,,}; . "$F"; eval "$3" ) 2>&1 ) || r=$?
  if [ "$r" != 0 ] && grep -q -F "$2" <<< "$s"; then ok "$1 : arrêt sur « $2 »"
  else ko "$1 : code $r, dernier message : $(grep '^KO' <<< "$s" | tail -n 1 | cut -c1-200)"; fi
}
altere "D1 script neuf altéré" "KO   script neuf : tâche signée" 'SCRIPT_NEUF_SHA=${SCRIPT_NEUF_SHA/4d8b/0000}; etape_local'
altere "D2 arbre prédit altéré" "KO   arbre prédit (sha256)" 'ARBRE_PREDIT_SHA=${ARBRE_PREDIT_SHA/a731/0000}; etape_local'
altere "D3 verrou de M4b à la place du neuf : feuilles" "KO   feuilles différentes" 'VERROU_SRC=$VERROU_M4B; VERROU_SHA=$VERROU_M4B_SHA; etape_local'
altere "D4 prefetch-rpm hors de la liste revue" "KO   prefetch-rpm de la cascade, lue dans la liste revue" 'PREFETCH_REF=${PREFETCH_REF/b9bbeba3/00000000}; etape_local'
altere "D5 digest prédit altéré" "KO   digest prédit" 'DIGEST_PREDIT=${DIGEST_PREDIT/0983/0000}; etape_local'
altere "D6 essai sans local" "KO   arbre prédit absent" 'kubectl() { echo "kubectl appelé" >&2; exit 9; }; etape_essai'
mkdir -p "$W0/$B-r"; : > "$W0/$B-r/$B-d7-fermeture-essai-arbre.txt"
altere "D7 essai : arbre déjà archivé" "KO   déjà présent" "R=$W0/$B-r; kubectl() { echo kubectl >&2; exit 9; }; etape_essai"
mkdir -p "$W0/$B-d8-fermeture-05/local"; cp "$W0/$B-fermeture-05/local/arbre-predit.txt" "$W0/$B-d8-fermeture-05/local/"
altere "D8 essai : script substitué altéré" "KO   script substitué" 'SCRIPT_NEUF_SHA=${SCRIPT_NEUF_SHA/4d8b/0000}; R=/nonexistent-banc; kubectl() { echo kubectl >&2; exit 9; }; etape_essai'
altere "D9 gabarit modifié" "KO   fermeture/prefetch-rpm-sample-app.yaml (sha256)" \
  'GABARITS_SHA=${GABARITS_SHA/ee74c258/00000000}; etape_local'

echo "     dossiers du banc laissés sous \$W : $B-fermeture-05, $B-b-fermeture-05, $B-d1…d9-fermeture-05, $B-r, $B-a.txt, $B-local.log"
echo "# fin $(date -u +%FT%TZ) : $OK OK, $KO KO"
[ "$KO" = 0 ]
