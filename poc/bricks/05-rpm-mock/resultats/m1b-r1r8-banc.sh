#!/usr/bin/env bash
# Banc de m1b-r1r8.sh (cascade de M1b, décision « Rejouer les huit » du 20/11/2026), écrit avant tout lancement.
# Ni cluster, ni Zot : seules les parties hôte sont jouées pour de bon, dans une copie du script placée dans le dossier du banc
# (journaux et chrono.tsv du banc hors du dépôt ; 08-trust-plane, m5-alterer.py, m5-reseau.spec et construction/ y sont des liens).
# A : m1b-r1r8.sh égal au produit de m5.sh par m1b-r1r8-copies.py ; m5.sh égal à celui du commit.
# B : bash -n ; shellcheck (UTF-8) : mêmes remarques que m5.sh.
# C : constantes contre leurs sources (m1b-construction.sh, liste revue, arbre de l'hôte, rootfs, tâche signée de la cascade).
# D : partie hôte de prealables jouée pour de bon, copie arrêtée avant « ## lecture : cluster et Zot » (comme le banc de M5a).
# E : banc_juges joué pour de bon dans la copie.
# F : gardes de préfixe et de journal présent.
# Non couvert : le cluster, Zot, Kata, mock, Chains (les étapes de cluster sont celles de m5.sh, mesurées en M5a).
# Usage : m1b-r1r8-banc.sh <racine du dépôt> <dossier du banc, absent>
set -uo pipefail
export LC_ALL=C
D=$1; B=$2; h=$D/poc/bricks/05-rpm-mock; RES=$h/resultats
SCRIPT=$h/m1b-r1r8.sh; M5=$h/m5.sh; MC=$h/m1b-construction.sh
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/05-rpm-mock/resultats"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m1b-r1r8-banc.sh, $(date -u +%FT%TZ) ; m1b-r1r8.sh $(sha256sum < "$SCRIPT" | cut -c1-64) ; m5.sh $(sha256sum < "$M5" | cut -c1-64)"

echo "## A : copies"
r=0; o=$(python3 -I "$RES/m1b-r1r8-copies.py" verifier "$M5" "$SCRIPT") || r=$?
egal "produit de m5.sh (code, ligne)" "$r $o" "0 OK   m1b-r1r8.sh égal au produit de m5.sh (19 remplacements, 28 occurrences)"
egal "m5.sh égal à celui du commit" "$(cd "$D" && git show HEAD:poc/bricks/05-rpm-mock/m5.sh | sha256sum | cut -c1-64)" "$(sha256sum < "$M5" | cut -c1-64)"

echo "## B : syntaxe et shellcheck"
egal "bash -n" "$(bash -n "$SCRIPT" && echo ok)" ok
# correction après le premier passage : format gcc (une ligne par remarque ; le format par défaut compte aussi les liens du wiki)
sc() { (cd "$D" && LC_ALL=C.UTF-8 mise exec -- shellcheck -x -e SC1091 -f gcc "$1" 2>/dev/null) | grep -o '\[SC[0-9]*\]' | sort | uniq -c; }
sc "$M5" > "$B/sc-m5"; sc "$SCRIPT" > "$B/sc-r1r8"
egal "shellcheck : seul écart, SC2034 de m5.sh (R inutilisé ; m1b-r1r8.sh le lit dans la garde des journaux)" \
  "$(diff "$B/sc-m5" "$B/sc-r1r8" | grep '^[<>]' | tr -s ' ' | paste -sd' ')" "< 1 [SC2034]"
echo "relevé : shellcheck, remarques : $(awk '{print $2 "×" $1}' "$B/sc-r1r8" | paste -sd' ')"

echo "## C : constantes contre leurs sources"
val() { sed -n "s/^$1=\([^ ]*\).*/\1/p" "$2"; }   # nom fichier : valeur de la ligne NOM=…
for v in PIPELINE_REF PREPARER_REF CONSTRUIRE_REF PREFETCH_IMAGE IMAGE_OUTILLAGE FERMETURE_RPM FERMETURE_SOURCES PACKAGING EPOQUE COMMIT DEPOT_GIT DIGEST_ESSAI CLE_CHAINS_SHA; do
  egal "$v égal à m1b-construction.sh" "$(val "$v" "$SCRIPT")" "$(val "$v" "$MC")"
done
egal "IMAGE (dépôt de l'artefact) égal à m1b-construction.sh" "$(val IMAGE "$SCRIPT")" "$(val IMAGE "$MC")"
for v in PREPARER_REF CONSTRUIRE_REF; do
  r=0; (cd "$D" && DISTRO=rke2 bash -c 'here=$PWD/poc/bricks/08-trust-plane; . "$here/commun.sh" > /dev/null; v=$1; listee "${v/\$REG/$REG}"' _ "$(val "$v" "$SCRIPT")") || r=$?   # correction : here posé avant commun.sh
  egal "$v dans la liste revue (listee, taches.yml du dépôt)" "$r" 0
done
echo "relevé : REG de commun.sh : $(cd "$D" && DISTRO=rke2 bash -c 'here=$PWD/poc/bricks/08-trust-plane; . "$here/commun.sh" > /dev/null; echo "$REG"')"
W=$(cd "$D" && DISTRO=rke2 bash -c 'here=$PWD/poc/bricks/08-trust-plane; . "$here/commun.sh" > /dev/null; echo "$W"')
SRC=$W/m1b-construction-05/local/ws/entrees
egal "SOURCE_HOTE" "$(val SOURCE_HOTE "$SCRIPT")" '$W/m1b-construction-05/local/ws/entrees'
egal "SOURCE_EMPREINTE, recalculée sur l'arbre de l'hôte" "$(val SOURCE_EMPREINTE "$SCRIPT")" "$(python3 -I "$h/m5-alterer.py" empreinte "$SRC")"
egal "arbre de l'hôte : fichiers" "$(find "$SRC" -type f | wc -l)" 273
RAC=$HOME/.cache/supply-chain-poc/05/m1b-refus-racine/racine
egal "RACINE" "$(val RACINE "$SCRIPT")" '$HOME/.cache/supply-chain-poc/05/m1b-refus-racine/racine'
egal "rootfs : rpm, python3, /mnt" "$(unshare -rn chroot "$RAC" /usr/bin/rpm --version) $(unshare -rn chroot "$RAC" /usr/bin/python3 --version) $([ -d "$RAC/mnt" ] && echo mnt)" \
  "RPM version 4.16.1.3 Python 3.9.25 mnt"
S=$h/construction/construire-rpm.m1b.signee.yaml
egal "tâche signée de la cascade : sha256, égal aux gabarits de m1b-construction.sh" "$(sha256sum < "$S" | cut -c1-64)" \
  "$(grep -o 'construction/construire-rpm.m1b.signee.yaml:[0-9a-f]*' "$MC" | head -n 1 | cut -d: -f2)"
pas() { yq '.spec.steps[] | select(.name == "construire") | .script' "$1"; }
egal "pas construire : script égal entre la tâche de M4c et celle de la cascade" "$(cmp -s <(pas "$h/construction/construire-rpm.signee.yaml") <(pas "$S") && echo égal)" égal
egal "pas construire : contexte et ressources égaux" \
  "$(cmp -s <(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | [.securityContext, .resources]' "$h/construction/construire-rpm.signee.yaml") \
            <(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | [.securityContext, .resources]' "$S") && echo égal)" égal
egal "fichiers lus par le script : construire-rpm.m1b.signee.yaml (3), construire-rpm.signee.yaml (0)" \
  "$(grep -c 'construire-rpm.m1b.signee.yaml' "$SCRIPT") $(grep -c 'construire-rpm.signee.yaml' "$SCRIPT")" "3 0"
egal "enveloppes attendues : 8 (trois lignes), 4 (aucune)" "$(grep -c '"$(enveloppes)" 8' "$SCRIPT") $(grep -c '"$(enveloppes)" 4' "$SCRIPT")" "3 0"
egal "PipelineRuns gardés : quatre noms (trois lignes), compte 4 (deux lignes)" \
  "$(grep -c 'm4c-rpm-1 m4c-rpm-2 m1b-construction-1 m1b-construction-2' "$SCRIPT") $(grep -c 'wc -l)" 4$' "$SCRIPT")" "3 2"
egal "gabarit de pod de R7 : image d'outillage de M1b" "$(grep -c 'IMAGE_OUTILLAGE=\$REG/builds/builders/mock-rocky9@sha256:70f8c412' "$SCRIPT")" 1

echo "## D : partie hôte de prealables, pour de bon (copie arrêtée avant la lecture)"
C=$B/05-rpm-mock
ln -s "$D/poc/bricks/08-trust-plane" "$B/08-trust-plane"
for f in m5-alterer.py m5-reseau.spec construction; do ln -s "$h/$f" "$C/$f"; done
sed 's/^  echo "## lecture : cluster et Zot"$/  echo "## banc : arrêt avant la lecture"; return 0/' "$SCRIPT" > "$C/m1b-r1r8.sh"; chmod 755 "$C/m1b-r1r8.sh"
egal "copie : une ligne changée" "$(diff "$SCRIPT" "$C/m1b-r1r8.sh" | grep -c '^[<>]')" 2
r=0; (cd "$D" && PREFIXE=m1br1r8banc1 DISTRO=rke2 mise exec -- "$C/m1b-r1r8.sh" prealables) < /dev/null > "$B/prealables.out" 2>&1 || r=$?
L=$C/resultats/m1br1r8banc1-prealables.log
egal "prealables (hôte) : code, journal au préfixe du banc" "$r $([ -s "$L" ] && echo journal)" "0 journal"
egal "prealables (hôte) : lignes OK, KO, arrêt du banc" "$(grep -c '^OK' "$L") $(grep -c '^KO' "$L") $(grep -c '^## banc : arrêt avant la lecture$' "$L")" "15 0 1"
egal "lignes du journal au motif de secret" "$(grep -ci 'jeton\|token' "$L")" 0
sed "s#$HOME#~#g" "$L" | sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' | cut -c1-240 | sed 's/^/     /'
egal "chrono du banc hors du dépôt" "$(grep -c 'M1b R1-R8 prealables' "$C/resultats/chrono.tsv")" 2

echo "## E : banc_juges, pour de bon"
r=0; (cd "$D" && PREFIXE=m1br1r8banc1 DISTRO=rke2 mise exec -- "$C/m1b-r1r8.sh" banc_juges) < /dev/null > "$B/juges.out" 2>&1 || r=$?
L=$C/resultats/m1br1r8banc1-banc_juges.log
egal "banc_juges : code, lignes OK, KO" "$r $(grep -c '^OK' "$L") $(grep -c '^KO' "$L")" "0 5 0"

echo "## F : gardes"
for p in m5 m4c m1b-construction m1bt3 m1b-refus-x; do
  r=0; (cd "$D" && PREFIXE=$p DISTRO=rke2 mise exec -- "$C/m1b-r1r8.sh" banc_juges) < /dev/null > "$B/garde-$p.out" 2>&1 || r=$?
  egal "PREFIXE=$p refusé (code, message)" "$r $(grep -c "^PREFIXE refusé (déjà pris par un jalon) : $p$" "$B/garde-$p.out")" "2 1"
done
r=0; (cd "$D" && PREFIXE=m1br1r8banc1 DISTRO=rke2 mise exec -- "$C/m1b-r1r8.sh" banc_juges) < /dev/null > "$B/garde-journal.out" 2>&1 || r=$?
egal "journal présent : arrêt avant toute étape (code, message, journal inchangé)" \
  "$r $(grep -c '^journal déjà présent : resultats/m1br1r8banc1-banc_juges.log' "$B/garde-journal.out") $(grep -c '^OK' "$L")" "2 1 5"
egal "chrono du banc : aucune ligne pour les passages refusés" "$(grep -c 'M1b R1-R8 banc_juges' "$C/resultats/chrono.tsv")" 2

echo "# bilan : $n OK, $k KO"
[ "$k" = 0 ]
