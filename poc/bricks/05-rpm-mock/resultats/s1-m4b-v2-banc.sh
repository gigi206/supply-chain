#!/usr/bin/env bash
# Banc hors cluster de l'étape m4b_mock_v2 (s1-m4b-v2.patch, décision « V2 » du 17/11/2026), écrit avant tout passage.
# A : insertions seules, deux blocs (en-tête, code) contre le s1.sh « avant » donné en argument ; aucune ligne retirée ni changée.
# B : bash -n ; shellcheck (UTF-8) : remarques de la copie contre celles du s1.sh avant, deux SC2016 de plus seulement.
# C : constantes REPOMD_V2, RPM_M3 et SRPM_M3 égales aux valeurs des journaux (m4b-essai.log, s1-m3_comparaison.log) ; la vraie
#     fonction etape_m4b_mock_v2 de la copie, jouée avec les vrais attendu, champ et mesure_m3 de la copie et un m3_build simulé
#     (il garde la sonde composée, écrit un journal de sonde et deux rpm factices) : composition (sonde de M3 et BLOC_V2 seuls,
#     BLOC_V2 après la porte d'intégrité et les sources, avant « mkdir -p "$B/res" » ; dash -n et bash -n), copie en liens durs ;
#     nominal code 0 et « écarts : 0 » ; repomd.xml faux, rpm faux, src.rpm faux, ligne « repodata V2 » absente : code 1.
# D : BLOC_V2 joué par dash sur un dépôt factice, faux createrepo_c : repodata ancien retiré, rpm datés à 0, options exactes,
#     ligne « repodata V2 » lisible, repomd.xml imprimé ligne à ligne ; createrepo_c absent et en échec : ko, fin de son journal
#     imprimée en cas d'échec.
# Le reste de m3_build est inchangé : non-régression par s1-m3-2-banc.sh et s1-n34-banc.sh, rejoués à part.
# Non couvert : vrai pod Kata, vrai mock, vrai createrepo_c (mesuré à l'essai de M4b, sous runc).
# Usage : s1-m4b-v2-banc.sh <racine du dépôt> <s1.sh avant> <copie modifiée de s1.sh> <dossier du banc, absent> [lignes d'en-tête
#         insérées, 7] [lignes de code insérées, 33]
# (après application : s1.sh avant = celui du commit précédent, en-tête de 8 lignes avec la ligne datée)
set -uo pipefail
export LC_ALL=C
D=$1; S1A=$2; S1N=$3; B=$4; HE=${5:-7}; HC=${6:-33}; RES=$D/poc/bricks/05-rpm-mock/resultats
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# s1-m4b-v2-banc.sh, $(date -u +%FT%TZ) ; s1.sh avant $(sha256sum < "$S1A" | cut -c1-64) ; copie $(sha256sum < "$S1N" | cut -c1-64)"

echo "## A : insertions seules"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
egal "lignes insérées (en-tête $HE, code $HC)" "$(grep -c '^>' "$B/diff.txt")" "$((HE + HC))"

echo "## B : syntaxe et shellcheck"
egal "bash -n" "$(bash -n "$S1N" && echo ok)" ok
sc() { (cd "$D" && LC_ALL=C.UTF-8 mise exec -- shellcheck -x -e SC1091 "$1" 2>/dev/null) | grep -o 'SC[0-9]*' | sort | uniq -c; }   # UTF-8 : sinon shellcheck s'arrête sur les accents
sc "$S1A" > "$B/sc-avant"; sc "$S1N" > "$B/sc-copie"
egal "shellcheck : écarts (SC2016 seulement)" "$(diff "$B/sc-avant" "$B/sc-copie" | grep '^[<>]' | tr -s ' ' | awk '{print $1, $3}' | paste -sd' ')" "< SC2016 > SC2016"
a16=$(awk '$2 == "SC2016" {print $1}' "$B/sc-avant")
egal "shellcheck : SC2016, avant et copie (deux de plus)" "$a16 $(awk '$2 == "SC2016" {print $1}' "$B/sc-copie")" "$a16 $((a16 + 2))"

echo "## C : constantes, et la vraie fonction avec un m3_build simulé"
python3 -I - "$S1N" "$B" > "$B/c.txt" <<'PY'
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text(); b = pathlib.Path(sys.argv[2])
g = lambda p: re.search(p, t, re.S | re.M).group(0)
(b / 'sonde-m3.txt').write_text(re.search(r"^SONDE_M3='(.*?)'\n\nm3_build\(\)", t, re.S | re.M).group(1))
(b / 'bloc-v2.txt').write_text(re.search(r"^BLOC_V2='(.*?)'\netape_m4b_mock_v2\(\)", t, re.S | re.M).group(1))
(b / 'fonctions.sh').write_text(''.join([g(r"^attendu\(\) \{.*?\n"), g(r"^champ\(\) \{.*?\n"), g(r"^ECARTS_M3=0\n"),
                                         g(r"^mesure_m3\(\) \{.*?\n"), g(r"^etape_m4b_mock_v2\(\) \{.*?^\}\n")]))
for c in ('REPOMD_V2', 'RPM_M3', 'SRPM_M3'):
    print(c, re.search(rf"^{c}=([0-9a-f]{{64}})", t, re.M).group(1))
PY
cv() { sed -n "s/^$1 //p" "$B/c.txt"; }
egal "REPOMD_V2 égale à V2 dans m4b-essai.log (deux copies)" "$(grep -c -F "repomd.xml $(cv REPOMD_V2)" "$RES/m4b-essai.log")" 2
egal "RPM_M3 et SRPM_M3 présentes dans s1-m3_comparaison.log" \
  "$(grep -q -F -e "$(cv RPM_M3)" "$RES/s1-m3_comparaison.log" && echo oui) $(grep -q -F -e "$(cv SRPM_M3)" "$RES/s1-m3_comparaison.log" && echo oui)" "oui oui"
cat > "$B/jouer.sh" <<'E'
set -uo pipefail
BANC=$1; CAS=$2; T=$BANC/t-$CAS; mkdir -p "$T/m3/restauree-1/depot"; for f in a b c; do echo "$f" > "$T/m3/restauree-1/depot/$f.rpm"; done
SONDE_M3=$(cat "$BANC/sonde-m3.txt"); BLOC_V2=$(cat "$BANC/bloc-v2.txt")$'\n'
REPOMD_V2=$(printf r | sha256sum | cut -c1-64); RPM_M3=$(printf rpm | sha256sum | cut -c1-64); SRPM_M3=$(printf srpm | sha256sum | cut -c1-64)
. "$BANC/fonctions.sh"
m3_build() { # simulé : sonde composée gardée, journal de sonde et rpm selon le cas
  [ "$1" = v2 ] || { echo "m3_build appelé avec $1"; exit 1; }
  printf %s "$SONDE_M3" > "$T/sonde-composee.txt"
  mkdir -p "$T/m3/build-v2"; printf rpm > "$T/m3/build-v2/sample-app-1.0.0-2.el9.x86_64.rpm"; printf srpm > "$T/m3/build-v2/sample-app-1.0.0-2.el9.src.rpm"
  case "$CAS" in
    nominal) echo "repodata V2 : repomd.xml $REPOMD_V2 ; fichiers 4" > "$T/m3-buildv2.log" ;;
    repomd) echo "repodata V2 : repomd.xml $(printf x | sha256sum | cut -c1-64) ; fichiers 4" > "$T/m3-buildv2.log" ;;
    rpm) echo "repodata V2 : repomd.xml $REPOMD_V2 ; fichiers 4" > "$T/m3-buildv2.log"; printf autre > "$T/m3/build-v2/sample-app-1.0.0-2.el9.x86_64.rpm" ;;
    srpm) echo "repodata V2 : repomd.xml $REPOMD_V2 ; fichiers 4" > "$T/m3-buildv2.log"; printf autre > "$T/m3/build-v2/sample-app-1.0.0-2.el9.src.rpm" ;;
    ligne) echo "autre chose" > "$T/m3-buildv2.log" ;;
  esac
}
etape_m4b_mock_v2
E
for c in nominal repomd rpm srpm ligne; do bash "$B/jouer.sh" "$B" "$c" > "$B/jouer-$c.out" 2>&1; echo "$?" > "$B/code-$c"; done
egal "nominal : code et « écarts : 0 »" "$(cat "$B/code-nominal") $(grep -c '^écarts : 0$' "$B/jouer-nominal.out")" "0 1"
egal "nominal : six OK (insertion, composition, repomd, fichiers, rpm, src.rpm)" "$(grep -c '^OK   ' "$B/jouer-nominal.out")" 6
egal "repomd.xml faux : code 1, un écart" "$(cat "$B/code-repomd") $(grep -c '^ÉCART repodata V2 dans le pod, repomd.xml' "$B/jouer-repomd.out")" "1 1"
egal "rpm faux : code 1, un écart" "$(cat "$B/code-rpm") $(grep -c '^ÉCART rpm sample-app' "$B/jouer-rpm.out")" "1 1"
egal "src.rpm faux : code 1, un écart" "$(cat "$B/code-srpm") $(grep -c '^ÉCART src.rpm' "$B/jouer-srpm.out")" "1 1"
egal "ligne absente : code 1, deux écarts" "$(cat "$B/code-ligne") $(grep -c '^écarts : 2$' "$B/jouer-ligne.out")" "1 1"
sed 's/^/     /' "$B/jouer-nominal.out"
egal "copie en liens durs de la fermeture" "$(stat -c %h "$B/t-nominal/m3/restauree-v2/depot/a.rpm")" 2
python3 -I - "$B" > "$B/c2.txt" <<'PY'
import sys, pathlib
b = pathlib.Path(sys.argv[1])
s, bl, c = (b / 'sonde-m3.txt').read_text(), (b / 'bloc-v2.txt').read_text(), (b / 't-nominal/sonde-composee.txt').read_text()
m = 'mkdir -p "$B/res"'
print('composition', 'OK' if c == s.replace(m, bl + m, 1) and c.count(bl) == 1 else 'KO')
i, g, h = c.find(bl.splitlines()[0]), c.find('ko "sources de sample-app"'), c.find('ko "fermeture différente de la liste de collecte"')
print('ordre', 'OK' if 0 < h < g < i < c.find(m) < c.find('mock --hermetic-build') else 'KO')
PY
egal "sonde composée : sonde de M3 et BLOC_V2 seuls, inséré une fois" "$(sed -n 's/^composition //p' "$B/c2.txt")" OK
egal "ordre : porte d'intégrité, sources, BLOC_V2, mkdir, mock" "$(sed -n 's/^ordre //p' "$B/c2.txt")" OK
egal "sonde composée, dash -n" "$(sh -n "$B/t-nominal/sonde-composee.txt" && echo ok)" ok
egal "sonde composée, bash -n" "$(bash -n "$B/t-nominal/sonde-composee.txt" && echo ok)" ok

echo "## D : BLOC_V2 joué par dash"
mkdir -p "$B/fx/bin" "$B/fx/sans" "$B/fx/w/fermeture/depot/repodata" "$B/fx/w/fermeture/depot/dir@x"
for r in a b c; do echo "$r" > "$B/fx/w/fermeture/depot/$r.rpm"; touch -d '2026-11-17 12:00' "$B/fx/w/fermeture/depot/$r.rpm"; done
echo ancien > "$B/fx/w/fermeture/depot/repodata/ancien-primary.sqlite.bz2"
cat > "$B/fx/bin/createrepo_c" <<'E'
#!/bin/sh
echo "$*" > "$BANC_ARGS"
[ -z "${BANC_ECHEC:-}" ] || { echo "erreur factice de createrepo_c"; exit 1; }
for a; do d=$a; done; mkdir -p "$d/repodata"; printf '<repomd>\n<revision>0</revision>\n</repomd>\n' > "$d/repodata/repomd.xml"
for f in p.xml.gz f.xml.gz o.xml.gz; do echo "$f" > "$d/repodata/$f"; done
E
chmod +x "$B/fx/bin/createrepo_c"
for o in sh sha256sum cut ls wc find touch rm mkdir cat sed tail; do ln -sf "$(command -v $o)" "$B/fx/bin/$o"; ln -sf "$(command -v $o)" "$B/fx/sans/$o"; done
bloc() { printf 'B=%s\nD=%s\nko() { echo "KO   $*"; exit 1; }\n%s\n' "$B/fx/w" "$B/fx/w/fermeture/depot" "$(cat "$B/bloc-v2.txt")" > "$B/fx/bloc.sh"
  env -i PATH="$1" BANC_ARGS="$B/fx/args" ${2:+BANC_ECHEC=1} sh "$B/fx/bloc.sh"; }
o=$(bloc "$B/fx/bin"); egal "nominal : code" "$?" 0
egal "repodata ancien retiré" "$([ -e "$B/fx/w/fermeture/depot/repodata/ancien-primary.sqlite.bz2" ] && echo présent || echo retiré)" retiré
egal "rpm datés à l'époque 0" "$(stat -c %Y "$B"/fx/w/fermeture/depot/*.rpm | sort -u | paste -sd' ')" 0
egal "options de createrepo_c" "$(cut -d' ' -f1-5 "$B/fx/args")" "--compatibility --revision 0 --set-timestamp-to-revision --no-database"
egal "ligne repodata V2 lisible comme par champ (repomd.xml, sha256 de 64, 4 fichiers)" \
  "$(sed -n 's/^repodata V2[[:space:]]*:[[:space:]]*//p' <<<"$o" | awk '{print $1, length($2), $NF}')" "repomd.xml 64 4"
egal "repomd.xml imprimé ligne à ligne" "$(grep -c '^repomd.xml V2 : ' <<<"$o")" 3
o=$(bloc "$B/fx/sans"); egal "createrepo_c absent : ko" "$?:$(grep -c '^KO   createrepo_c absent' <<<"$o")" "1:1"
o=$(bloc "$B/fx/bin" echec); egal "createrepo_c en échec : ko et fin de son journal" "$?:$(grep -c '^KO   createrepo_c V2' <<<"$o"):$(grep -c '^erreur factice de createrepo_c' <<<"$o")" "1:1:1"
echo "# bilan : $([ "$k" = 0 ] && echo tenu || echo NON TENU), $n OK, $k KO, fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
