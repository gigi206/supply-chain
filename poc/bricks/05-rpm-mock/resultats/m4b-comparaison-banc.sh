#!/usr/bin/env bash
# Brique 05, M4b : banc hors cluster et hors Zot de l'étape comparaison de m4b.sh (préparée à sec le 18/11/2026, accord permanent du
# 18/11), écrit avant tout passage.
# A : insertions seules contre le m4b.sh d'avant (deux blocs : en-tête, bloc avant lancer) ; aucun nom du bloc déjà défini avant ;
#     bash -n ; shellcheck : mêmes codes avant et après.
# B : les vraies fonctions attendu, echec, arbre_de et confronter, extraites de m4b.sh, jouées sur des arbres faux (noms à « : » et
#     « @ » compris), avec une référence triée dans un autre ordre (tri inverse) : cas nominal, puis un écart par cas (fichier
#     manquant, fichier en trop, taille fausse dans la référence, contenu faux de même taille, fichier hors de depot/ à compte égal,
#     lien symbolique en plus) ; dans chaque cas : code, libellé du KO attendu, écarts imprimés avant le KO.
# C : contrôles de l'étape au-delà de l'arbre, joués sur les vrais fichiers archivés (arbre de final, liste, verrou) : les 222 rpm
#     de la référence préfixée égaux à la liste transformée comme dans l'étape, repomd.xml de la référence égal à REPOMD_V2, dossier
#     de l'image de bootstrap unique, manifest.json au digest du verrou, blobs nommés par leur sha256.
# Non couvert : Zot (manifeste, oras pull), kubectl, réseau.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4b-comparaison-banc.sh <dossier-neuf> <m4b.sh avant> <m4b.sh>
set -uo pipefail
export LC_ALL=C
B=$1; AVANT=$2; COPIE=$3
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4b-comparaison-banc.sh, $(date -u +%FT%TZ) ; m4b.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; m4b.sh $(sha256sum < "$COPIE" | cut -c1-64)"

echo "## A : insertions seules, noms neufs, syntaxe, shellcheck"
diff "$AVANT" "$COPIE" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
grep '^>' "$B/diff.txt" | cut -c3- > "$B/ajout.txt"
sed -n 's/^\([a-z_][a-z_0-9]*\)() {.*/\1/p; s/^\([A-Z_][A-Z_0-9]*\)=.*/\1/p' "$B/ajout.txt" | sort > "$B/noms.txt"
echo "noms définis par l'ajout : $(paste -sd' ' "$B/noms.txt")"
egal "noms de l'ajout déjà définis avant" "$(while read -r x; do grep -c -E "^($x\(\) \{|$x=)" "$AVANT"; done < "$B/noms.txt" | awk '{s += $1} END {print s + 0}')" 0
egal "bash -n" "$(bash -n "$COPIE" && echo ok)" ok
sc() { LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$1" 2>/dev/null | grep -o 'SC[0-9]*' | sort | uniq -c; }
egal "shellcheck : mêmes codes avant et après" "$(diff <(sc "$AVANT") <(sc "$COPIE") > /dev/null && echo mêmes || echo différents)" mêmes

echo "## B : confronter sur des arbres faux"
sed -n '/^attendu() {/p; /^echec() {/p; /^arbre_de() {/,/^}/p; /^confronter() {/,/^}/p' "$COPIE" > "$B/fonctions.sh"
egal "fonctions extraites (attendu, echec, arbre_de, confronter)" "$(grep -c -E '^(attendu|echec|arbre_de|confronter)\(\) \{' "$B/fonctions.sh")" 4
F=$B/final; mkdir -p "$F/repodata" "$F/sc-stockage.poc.test@sha256:abc"
printf 'rpm a\n' > "$F/a-1.0-1.el9.x86_64.rpm"; printf 'rpm bb\n' > "$F/b-2.0-1.el9.noarch.rpm"
printf '<repomd/>\n' > "$F/repodata/repomd.xml"; printf '{}\n' > "$F/sc-stockage.poc.test@sha256:abc/manifest.json"
# référence relative à depot/, dans un ordre autre que celui de l'hôte (tri inverse) : confronter doit la retrier
(. "$B/fonctions.sh"; arbre_de "$F") | sort -r > "$B/ref.txt"
egal "référence fausse : 4 lignes, ordre différent du tri de l'hôte" "$(wc -l < "$B/ref.txt") $(sort -c "$B/ref.txt" 2> /dev/null && echo trié || echo non-trié)" "4 non-trié"
cas() { # nom code-attendu libellé-du-KO-attendu (vide si nominal) : arbre $B/<nom>/x (préparé avant), référence $B/<nom>/ref.txt
  local c=$B/$1 r o
  r=0; ( . "$B/fonctions.sh"; set -euo pipefail; confronter "$c/x" "$c/ref.txt" "$c" ) > "$c/sortie.txt" 2>&1 || r=$?
  sed 's/^/     /' "$c/sortie.txt"
  egal "$1 : code" "$r" "$2"
  if [ -n "$3" ]; then
    egal "$1 : KO attendu" "$(grep -c "^KO   $3" "$c/sortie.txt")" 1
    o=$(grep -n -m1 '^écarts (comm -3' "$c/sortie.txt" | cut -d: -f1)
    egal "$1 : écarts imprimés avant le KO" "$([ -n "$o" ] && [ "$o" -lt "$(grep -n -m1 '^KO' "$c/sortie.txt" | cut -d: -f1)" ] && echo oui || echo non)" oui
  else
    egal "$1 : OK, aucun KO" "$(grep -c '^OK   ' "$c/sortie.txt") $(grep -c '^KO' "$c/sortie.txt")" "4 0"
  fi
}
prep() { mkdir -p "$B/$1/x"; cp -a "$F" "$B/$1/x/depot"; cp "$B/ref.txt" "$B/$1/ref.txt"; }
prep nominal; cas nominal 0 ""
prep manquant; rm "$B/manquant/x/depot/b-2.0-1.el9.noarch.rpm"; cas manquant 1 "fichiers tirés"
prep en_trop; printf 'rpm c\n' > "$B/en_trop/x/depot/c-1-1.el9.noarch.rpm"; cas en_trop 1 "fichiers tirés"
prep taille; sed -i 's/^\(a-1.0-1.el9.x86_64.rpm\) 6 /\1 7 /' "$B/taille/ref.txt"
egal "taille : référence modifiée" "$(grep -c '^a-1.0-1.el9.x86_64.rpm 7 ' "$B/taille/ref.txt")" 1
cas taille 1 "arbre tiré égal"
prep contenu; printf 'rpm A\n' > "$B/contenu/x/depot/a-1.0-1.el9.x86_64.rpm"; cas contenu 1 "arbre tiré égal"
prep hors_depot; mv "$B/hors_depot/x/depot/b-2.0-1.el9.noarch.rpm" "$B/hors_depot/x/"; cas hors_depot 1 "fichiers hors de depot/"
prep lien; ln -s a-1.0-1.el9.x86_64.rpm "$B/lien/x/depot/lien.rpm"; cas lien 1 "objets ni fichier ni dossier"

echo "## C : contrôles au-delà de l'arbre, sur les vrais fichiers archivés"
R=poc/bricks/05-rpm-mock/resultats
eval "$(grep -E '^(ARBRE_SHA|LISTE_SHA|VERROU_SHA|REPOMD_V2)=' "$COPIE")"
egal "arbre de final (sha256)" "$(sha256sum < "$R/m4b-final-arbre.txt" | cut -c1-64)" "$ARBRE_SHA"
egal "liste (sha256)" "$(sha256sum < "$R/m4b-liste.txt" | cut -c1-64)" "$LISTE_SHA"
egal "verrou (sha256)" "$(sha256sum < "$R/s1-verrou_derivee.json" | cut -c1-64)" "$VERROU_SHA"
sed 's|^|depot/|' "$R/m4b-final-arbre.txt" | sort > "$B/vraie-ref.txt"
awk '{n = $1; sub(/.*\//, "", n); print "depot/" n, $3, $2}' "$R/m4b-liste.txt" | sort > "$B/liste-rpm.txt"
grep -E '^depot/[^/]+\.rpm ' "$B/vraie-ref.txt" > "$B/ref-rpm.txt"
egal "rpm de la référence au premier niveau de depot/" "$(wc -l < "$B/ref-rpm.txt")" 222
egal "rpm de la référence égaux à la liste transformée" "$(sha256sum < "$B/ref-rpm.txt" | cut -c1-64)" "$(sha256sum < "$B/liste-rpm.txt" | cut -c1-64)"
egal "repomd.xml de la référence" "$(awk '$1 == "depot/repodata/repomd.xml" {print $3}' "$B/vraie-ref.txt")" "$REPOMD_V2"
src=$(jq -r '.config.bootstrap_image' "$R/s1-verrou_derivee.json")
egal "dossier de l'image de bootstrap dans la référence" "$(cut -d' ' -f1 "$B/vraie-ref.txt" | grep -E '^depot/[^/]+/' | cut -d/ -f2 | sort -u | grep -c "@${src#*@}$")" 1
egal "manifest.json au digest du verrou" "$(awk '$1 ~ /@sha256:[0-9a-f]+\/manifest.json$/ {print "sha256:" $3}' "$B/vraie-ref.txt")" "${src#*@}"
egal "blobs nommés par leur sha256" "$(awk '$1 ~ /@sha256:[0-9a-f]+\/[0-9a-f]{64}$/ {m = $1; sub(/.*\//, "", m); print (m == $3 ? "oui" : "non")}' "$B/vraie-ref.txt" | sort | uniq -c | awk '{print $1, $2}')" "2 oui"
egal "fichiers de la référence : rpm, repodata, image de bootstrap" \
  "$(wc -l < "$B/ref-rpm.txt") $(grep -c '^depot/repodata/' "$B/vraie-ref.txt") $(grep -c '@sha256:' "$B/vraie-ref.txt")" "222 4 4"
echo "# bilan : $n OK, $k KO ; fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
