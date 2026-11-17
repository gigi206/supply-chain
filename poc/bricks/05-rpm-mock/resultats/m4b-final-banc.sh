#!/usr/bin/env bash
# Brique 05, M4b : banc hors cluster de l'étape final de m4b.sh (pas de prefetch final, décision « V2 » du 17/11/2026), écrit avant
# tout passage, hors réseau.
# A : insertions seules contre le m4b.sh d'avant (trois blocs : en-tête, scripts du pod, fonction) ; PREFETCH_FINAL comparé à
#     PREFETCH (diff archivé) : seules les lignes voulues changent (gpg obligatoire, repli retiré, rpm datés à 0, createrepo_c V2,
#     repomd.xml imprimé) ; options de createrepo_c identiques à celles de BLOC_V2 (s1.sh) et de la variante V2 (COMPARE).
# B : bash -n, dash -n des deux scripts du pod ; shellcheck (UTF-8) : un SC2016 de plus seulement.
# C : PREFETCH_FINAL joué par dash, PATH restreint aux outils de base de l'image et à de faux curl, rpm, createrepo_c, skopeo, gpg ;
#     le faux createrepo_c exige les options exactes, des rpm datés à 0 et aucun dossier dans le dépôt ; nominal ; gpg absent
#     refusé ; createrepo_c en échec (fin de son journal imprimée) ; refus inchangés de PREFETCH.
# D : la vraie fonction etape_final de la copie, avec les vrais attendu, pod_spec et dans, et un faux kubectl qui joue les scripts
#     du pod par dash dans un dossier par pod : nominal (arbre archivé, puis égal), puis code 1 pour repomd.xml faux, arbres
#     différents entre passages, retrait en échec, PVC restante, passage en échec, liste différente, arbre archivé différent.
# Non couvert : vrai pod, vrai réseau, vrais rpm et vrai createrepo_c (mesurés à l'essai), vraie admission.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4b-final-banc.sh <dossier-neuf> <m4b.sh avant>
#         <copie modifiée de m4b.sh> [lignes d'en-tête, 7] [lignes de scripts, 65] [lignes de fonction, 48]
set -uo pipefail
export LC_ALL=C
B=$1; AVANT=$2; COPIE=$3; HE=${4:-7}; HS=${5:-65}; HF=${6:-48}
DASH=$(command -v dash); RACINE=$PWD; S1=$RACINE/poc/bricks/05-rpm-mock/s1.sh; VERROU=$RACINE/poc/bricks/05-rpm-mock/resultats/s1-verrou_derivee.json
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"/{bin,base,src,cas,pod}
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4b-final-banc.sh, $(date -u +%FT%TZ) ; m4b.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; copie $(sha256sum < "$COPIE" | cut -c1-64)"

echo "## A : insertions seules ; PREFETCH_FINAL contre PREFETCH"
diff "$AVANT" "$COPIE" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 3
egal "lignes insérées (en-tête $HE, scripts $HS, fonction $HF)" "$(grep -c '^>' "$B/diff.txt")" "$((HE + HS + HF))"
python3 -I - "$COPIE" "$B" <<'PY'
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text(); b = pathlib.Path(sys.argv[2])
for nom in ('PREFETCH', 'PREFETCH_FINAL', 'ARBRE', 'COMPARE'):
    m = re.search('^' + nom + r"=\$\(cat <<'SH'\n(.*?)\nSH\n\)", t, re.S | re.M)
    (b / (nom.lower() + '.sh')).write_text(m.group(1) + '\n')
PY
diff "$B/prefetch.sh" "$B/prefetch_final.sh" > "$B/diff-prefetch.txt"
sed 's/^/     /' "$B/diff-prefetch.txt"
egal "PREFETCH : lignes retirées" "$(grep -c '^<' "$B/diff-prefetch.txt")" 10
egal "PREFETCH : lignes retirées hors gpg et createrepo_c" "$(grep '^<' "$B/diff-prefetch.txt" | grep -c -v -E 'gpg|"\$fp"|^< else$|^< fi$|createrepo_c|^< for o in curl')" 0
egal "PREFETCH_FINAL : lignes ajoutées" "$(grep -c '^>' "$B/diff-prefetch.txt")" 10
egal "PREFETCH_FINAL : lignes ajoutées hors gpg, dates, createrepo_c et repomd.xml" "$(grep '^>' "$B/diff-prefetch.txt" | grep -c -v -E 'gpg|^> fp=|"\$fp"|touch -h -d @0|createrepo_c|repodata V2|repomd\.xml V2|^> t=\$\(date \+%s\)$')" 0
egal "PREFETCH_FINAL : outils, gpg compris" "$(grep -c '^for o in curl rpm createrepo_c skopeo sha256sum stat gpg; do command -v' "$B/prefetch_final.sh")" 1
egal "PREFETCH_FINAL : plus aucun « gpg absent »" "$(grep -c 'gpg absent' "$B/prefetch_final.sh")" 0
egal "PREFETCH_FINAL : contrôle de l'identifiant court gardé" "$(grep -c 'identifiant court de la clé importée' "$B/prefetch_final.sh")" 1
opt() { grep -o -E 'createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database' "$1" | sort -u; }
egal "options de createrepo_c : PREFETCH_FINAL, BLOC_V2 de s1.sh" "$(opt "$B/prefetch_final.sh") | $(opt "$S1")" \
  "createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database | createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database"
egal "options de createrepo_c : variante V2 de COMPARE" "$(grep -c -F -x 'variante V2 --compatibility --revision 0 --set-timestamp-to-revision --no-database' "$B/compare.sh")" 1
egal "PREFETCH_FINAL : rpm datés à 0 avant createrepo_c" "$(grep -n -E 'touch -h -d @0|^createrepo_c ' "$B/prefetch_final.sh" | cut -d: -f2 | cut -c1-12 | paste -sd'|')" 'find "$D" -m|createrepo_c'

echo "## B : syntaxe et shellcheck"
egal "bash -n" "$(bash -n "$COPIE" && echo ok)" ok
egal "dash -n PREFETCH_FINAL et ARBRE" "$(dash -n "$B/prefetch_final.sh" && dash -n "$B/arbre.sh" && echo ok)" ok
sc() { LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$1" 2>/dev/null | grep -o 'SC[0-9]*' | sort | uniq -c; }   # UTF-8 : sinon arrêt sur les accents
sc "$AVANT" > "$B/sc-avant"; sc "$COPIE" > "$B/sc-copie"
egal "shellcheck : écarts (SC2016 seulement)" "$(diff "$B/sc-avant" "$B/sc-copie" | grep '^[<>]' | tr -s ' ' | awk '{print $1, $3}' | paste -sd' ')" "< SC2016 > SC2016"
a16=$(awk '$2 == "SC2016" {print $1}' "$B/sc-avant")
egal "shellcheck : SC2016, avant et copie (un de plus)" "$a16 $(awk '$2 == "SC2016" {print $1}' "$B/sc-copie")" "$a16 $((a16 + 1))"

# Faux outils du pod
for i in $(seq -w 1 222); do printf 'contenu du rpm %s\n' "$i" > "$B/src/p$i-1.0-1.el9.x86_64.rpm"; done
printf 'contenu du rpm +\n' > "$B/src/q+x-1.0-1.el9.noarch.rpm"; rm -f "$B/src/p222-1.0-1.el9.x86_64.rpm"   # un nom avec « + »
for f in "$B"/src/*.rpm; do echo "https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os/Packages/${f##*/} $(sha256sum < "$f" | cut -c1-64) $(stat -c %s "$f")"; done > "$B/liste.txt"
printf '{"schemaVersion":2}\n' > "$B/manifest.json"
MAN=sha256:$(sha256sum < "$B/manifest.json" | cut -c1-64)
printf 'CLE FACTICE\n' > "$B/cle"
cat > "$B/bin/curl" <<'E'
#!/bin/sh
o=; for a; do case "$p" in -o) o=$a ;; esac; p=$a; done
u=$a; f=${u##*/}; f=$(printf %s "$f" | sed 's/%2B/+/g')
cp "$BANC_SRC/$f" "$o" 2>/dev/null || { printf 404; exit 0; }
printf 200
E
cat > "$B/bin/rpm" <<'E'
#!/bin/sh
case "$*" in
  *--initdb*|*--import*) exit 0 ;;
  *"-q gpg-pubkey"*) echo "${BANC_ID:-350d275d}"; exit 0 ;;
  *" -K "*) shift 3; for f; do case "$f" in *"${BANC_SIG_KO:-@@}"*) echo "$f: digests SIGNATURES NOT OK"; r=1 ;; *) echo "$f: digests signatures OK" ;; esac; done; exit ${r:-0} ;;
esac
echo "faux rpm : $*" >&2; exit 3
E
cat > "$B/bin/createrepo_c" <<'E'
#!/bin/sh
[ -z "${BANC_CR_KO:-}" ] || { echo "erreur factice de createrepo_c, ligne 1"; echo "erreur factice de createrepo_c, ligne 2"; exit 1; }
for a; do d=$a; done
[ "$*" = "--compatibility --revision 0 --set-timestamp-to-revision --no-database $d" ] || { echo "options inattendues : $*"; exit 4; }
for f in "$d"/*.rpm; do [ "$(stat -c %Y "$f")" = 0 ] || { echo "rpm non daté à 0 : $f"; exit 5; }; done
[ -z "$(find "$d" -mindepth 1 -type d)" ] || { echo "dossier présent dans le dépôt"; exit 6; }
mkdir -p "$d/repodata"
{ echo "fixe${BANC_REPOMD_AUTRE:-}"; ls "$d" | grep '\.rpm$'; } > "$d/repodata/repomd.xml"
for x in primary filelists other; do echo "$x" > "$d/repodata/$x.xml.gz"; done
E
cat > "$B/bin/skopeo" <<'E'
#!/bin/sh
for a; do d=$a; done; d=${d#dir:}
mkdir -p "$d" && cp "$BANC_MAN" "$d/manifest.json" && echo config > "$d/config" && echo "Directory Transport Version: 1.1" > "$d/version"
case "$d" in *"${BANC_BLOB_AUTRE:-@@}"*) echo "couche autre" > "$d/couche" ;; *) echo couche > "$d/couche" ;; esac
E
cat > "$B/bin/gpg" <<'E'
#!/bin/sh
echo "fpr:::::::::${BANC_FP:-21CB256AE16FC54C6E652949702D426D350D275D}:"
E
chmod +x "$B"/bin/*
# outils de base de l'image (coreutils, findutils, gawk, sed, grep) ; ni cmp ni diff
for f in sh sed cut sha256sum stat mkdir ls cat grep awk tail tr date find wc du cp rm touch sort head env comm id printf; do
  p=$(command -v "$f") && [ "${p#/}" != "$p" ] && ln -s "$p" "$B/base/$f"; done
mkdir -p "$B/bin-sans-gpg" && for f in curl rpm createrepo_c skopeo; do ln -s "$B/bin/$f" "$B/bin-sans-gpg/$f"; done
mkdir -p "$B/bin-sans-cr" && for f in curl rpm skopeo gpg; do ln -s "$B/bin/$f" "$B/bin-sans-cr/$f"; done

echo "## C : PREFETCH_FINAL par dash"
cas() { # libellé code-attendu motif-attendu [VAR=valeur…]
  local lib=$1 voulu=$2 motif=$3 c rc; shift 3
  c=$B/cas/$((n + k + 1)); mkdir -p "$c/tmp"
  env -i PATH="$B/bin:$B/base" BANC_SRC="$B/src" BANC_MAN="$B/manifest.json" SORTIE="$c/sortie" LISTE_FICHIER="${LISTE_CAS:-$B/liste.txt}" \
    SOURCE="sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@${MAN_CAS:-$MAN}" DOSSIER="sc-stockage.poc.test@$MAN" \
    FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D CLE_ROCKY="$B/cle" "$@" "$DASH" "$B/prefetch_final.sh" > "$c/sortie.txt" 2>&1
  rc=$?
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$c/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 3 "$c/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
  C_DERNIER=$c
}
cas "nominal : 222 rpm, repodata V2 de 4 fichiers, dossier dir: de 4 fichiers" 0 "^fermeture : 230 fichiers"
c=$C_DERNIER
egal "nominal : repomd.xml imprimé en entier (lignes préfixées)" "$(grep -c '^repomd.xml V2 : ' "$c/sortie.txt")" "$(wc -l < "$c/sortie/depot/repodata/repomd.xml")"
egal "nominal : ligne repodata V2" "$(grep '^repodata V2 : ' "$c/sortie.txt" | cut -d' ' -f1-5,7-8)" "repodata V2 : repomd.xml $(sha256sum < "$c/sortie/depot/repodata/repomd.xml" | cut -c1-64) fichiers 4"
egal "nominal : nom avec « + » téléchargé (%2B)" "$(ls "$c/sortie/depot" | grep -c -F 'q+x-')" 1
cas "gpg absent : refusé (repli retiré)" 1 "KO   gpg absent de l'image" PATH="$B/bin-sans-gpg:$B/base"
cas "createrepo_c en échec : refusé, fin de son journal imprimée" 1 "erreur factice de createrepo_c, ligne 2" BANC_CR_KO=1
grep -q "KO   createrepo_c V2" "$C_DERNIER/sortie.txt" && egal "createrepo_c en échec : message" ok ok || egal "createrepo_c en échec : message" absent ok
cas "createrepo_c absent : refusé" 1 "KO   createrepo_c absent" PATH="$B/bin-sans-cr:$B/base"
sed '1s/ [0-9a-f]\{64\} / 0000000000000000000000000000000000000000000000000000000000000000 /' "$B/liste.txt" > "$B/liste-sha"
LISTE_CAS=$B/liste-sha cas "sha256 faux refusé" 1 "KO   sha256 différent"
awk 'NR == 1 {$3 = $3 + 1} {print}' "$B/liste.txt" > "$B/liste-taille"
LISTE_CAS=$B/liste-taille cas "taille fausse refusée" 1 "KO   taille différente"
{ cat "$B/liste.txt"; head -n 1 "$B/liste.txt"; } > "$B/liste-double"
LISTE_CAS=$B/liste-double cas "nom en double refusé" 1 "KO   nom en double"
sed '1s#Packages/p#Packages/z#' "$B/liste.txt" > "$B/liste-404"
LISTE_CAS=$B/liste-404 cas "fichier absent du dépôt (HTTP 404) refusé" 1 "KO   HTTP 404"
cas "signature d'un rpm refusée" 1 "KO   signatures des rpm" BANC_SIG_KO=p100-
cas "empreinte gpg fausse refusée" 1 "KO   empreinte de la clé" BANC_FP=0000000000000000000000000000000000000000
cas "identifiant court faux refusé" 1 "KO   identifiant court" BANC_ID=deadbeef
MAN_CAS=sha256:0000000000000000000000000000000000000000000000000000000000000000 cas "manifeste différent refusé" 1 "KO   manifeste copié"

echo "## D : vraie fonction etape_final, faux kubectl"
# copie jouable : sans commun.sh ni lancer ; R et W fournis par le banc ; le reste de la copie inchangé
python3 -I - "$COPIE" "$B/m4b-jouable.sh" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text().split('\n')
r = {'. "$here/commun.sh"   # repo, O, S, P, W, REG, lancer, chrono': ':', 'R=$h05/resultats': 'R=$BANC_R', 'lancer m4b "05 M4b" "$@"': ':'}
assert all(t.count(a) == 1 for a in r)
pathlib.Path(sys.argv[2]).write_text('\n'.join(r.get(l, l) for l in t))
PY
egal "copie jouable : trois lignes remplacées" "$(diff "$COPIE" "$B/m4b-jouable.sh" | grep -c '^>')" 3
cat > "$B/kubectl" <<'E'
#!/usr/bin/env bash
# faux kubectl : état sous $BANC_K (pods/<nom>/{w,tmp}, pvc/<nom>-w) ; scripts du pod joués par dash, chemins du pod réécrits
set -u
K=$BANC_K; mkdir -p "$K/pods" "$K/pvc"; echo "kubectl $*" >> "$K/appels"
carte() { sed -e "s#/workspace/sortie#$K/pods/$1/w#g" -e "s#/tmp/#$K/pods/$1/tmp/#g"; }
envpod() { env -i PATH="$BANC_PATHPOD" BANC_SRC="$BANC_SRC" BANC_MAN="$BANC_MAN" CLE_ROCKY="$BANC_CLE" BANC_BLOB_AUTRE="${BANC_BLOB_AUTRE:-@@}" BANC_REPOMD_AUTRE="${BANC_REPOMD_AUTRE:-}" "$@"; }
case "$1" in
  create) if [ "$2" = --dry-run=server ]; then exit 0; fi
          nom=$(jq -r .metadata.name "$3"); mkdir -p "$K/pods/$nom/w" "$K/pods/$nom/tmp"; : > "$K/pvc/$nom-w"; exit 0 ;;
  delete) nom=$5
          case "$*" in *--ignore-not-found*) rm -rf "${K:?}/pods/$nom"; exit 0 ;; esac
          [ -z "${BANC_RETRAIT_KO:-}" ] || exit 1
          rm -rf "${K:?}/pods/$nom"; [ -n "${BANC_PVC_RESTE:-}" ] || rm -f "$K/pvc/$nom-w"; exit 0 ;;
  wait)   case "$*" in *--for=delete*) for a; do case "$a" in pvc/*) p=${a#pvc/} ;; esac; done; [ ! -e "$K/pvc/$p" ]; exit $? ;; esac
          exit 0 ;;
  get)    case "$*" in
            "get pods,pvc -n builds -o name") for d in "$K"/pods/*/; do [ -d "$d" ] && { d=${d%/}; echo "pod/${d##*/}"; }; done
                                              for f in "$K"/pvc/*; do [ -e "$f" ] && echo "persistentvolumeclaim/${f##*/}"; done; exit 0 ;;
            *nodeName*) echo noeud-banc; exit 0 ;;
            *runtimeClassName*) exit 0 ;;
          esac; echo "faux kubectl : get inattendu : $*" >&2; exit 3 ;;
  exec)   nom=$5; shift 6
          [ -d "$K/pods/$nom" ] || { echo "pod absent : $nom" >&2; exit 1; }
          if [ "$1 $2" = "sh -s" ]; then carte "$nom" > "$K/pods/$nom/script.sh"; envpod "$BANC_DASH" "$K/pods/$nom/script.sh"; exit $?; fi
          if [ "$1 $2" = "sh -c" ]; then envpod "$BANC_DASH" -c "$(printf %s "$3" | carte "$nom")"; exit $?; fi
          if [ "$1" = sha256sum ]; then envpod sha256sum "$(printf %s "$2" | carte "$nom")"; exit $?; fi
          echo "faux kubectl : exec inattendu : $*" >&2; exit 3 ;;
esac
echo "faux kubectl : appel inattendu : $*" >&2; exit 3
E
chmod +x "$B/kubectl"; mkdir -p "$B/kbin"; ln -s "$B/kubectl" "$B/kbin/kubectl"
# verrou du banc : le vrai, avec l'image de bootstrap au digest du faux manifeste (seuls champs lus par l'étape)
verrou_banc() { jq --arg m "$MAN" '.config.bootstrap_image = "sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@" + $m | .bootstrap.pull_digest = $m' "$VERROU" > "$1/s1-verrou_derivee.json"; }
REPOMD_BANC=$( { echo fixe; ls "$B/src" | grep '\.rpm$'; } | sha256sum | cut -c1-64)
etape() { # libellé code-attendu motif-attendu dossier-R [VAR=valeur…] : etape_final de la copie jouable, dans un W neuf
  local lib=$1 voulu=$2 motif=$3 r=$4 c rc; shift 4
  c=$B/etape/$((n + k + 1)); mkdir -p "$c/W"
  if [ ! -d "$r" ]; then mkdir -p "$r"; verrou_banc "$r"; cp "$B/liste.txt" "$r/m4b-liste.txt"; fi
  env BANC_K="$c/k" BANC_R="$r" W="$c/W" REG=sc-stockage.poc.test:5000 PATH="$B/kbin:$PATH" BANC_PATHPOD="$B/bin:$B/base" \
    BANC_SRC="$B/src" BANC_MAN="$B/manifest.json" BANC_CLE="$B/cle" BANC_DASH="$DASH" REPOMD_BANC="$REPOMD_BANC" "$@" bash -c '
    set -euo pipefail
    . "$1"
    LISTE_SHA=${LISTE_SHA_CAS:-$(sha256sum < "$LISTE" | cut -c1-64)}; REPOMD_V2=${REPOMD_CAS:-$REPOMD_BANC}
    etape_final' _ "$B/m4b-jouable.sh" > "$c/sortie.txt" 2>&1
  rc=$?
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$c/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 3 "$c/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
  E_DERNIER=$c
}
R1=$B/R1
etape "nominal : deux pods, arbres égaux, arbre archivé" 0 "^arbre archivé : resultats/m4b-final-arbre.txt$" "$R1"
c=$E_DERNIER
egal "nominal : lignes OK de l'étape" "$(grep -c '^OK   ' "$c/sortie.txt")" 19
egal "nominal : arbre archivé, fichiers" "$(wc -l < "$R1/m4b-final-arbre.txt")" 230
egal "nominal : arbre archivé, repodata" "$(grep -c '^repodata/' "$R1/m4b-final-arbre.txt")" 4
egal "nominal : pods et PVC restants (faux cluster)" "$( (ls -A "$c/k/pods"; ls -A "$c/k/pvc") | wc -l)" 0
egal "nominal : pods créés, noms" "$(grep '^kubectl create -f' "$c/k/appels" | sed 's#.*/##' | paste -sd' ')" "m4b-05-final-p1.json m4b-05-final-p2.json"
egal "nominal : spec du pod p1 (label, uid, subPath, image)" "$(jq -r '[.metadata.labels["tekton.dev/task"], .spec.securityContext.runAsUser, .spec.containers[0].volumeMounts[0].subPath, (.spec.containers[0].image | split("@")[1][0:15])] | join(" ")' "$c/W/m4b-05/m4b-05-final-p1.json")" "prefetch-rpm 65532 fermeture sha256:99790c13"
egal "nominal : journaux distincts de ceux de l'essai" "$(ls "$c/W/m4b-05" | grep -c -E '^m4b-(p1|p2|sonde|comparaisons)\.log$')" 0
etape "nominal rejoué : arbre égal à celui archivé" 0 "^OK   arbre égal à celui archivé : égal$" "$R1"
etape "repomd.xml différent de l'attendu : refusé" 1 "^KO   p1 : repomd.xml V2" "$B/R2" REPOMD_CAS=239a5a71c887d4370228ffdff016517282086f19de93418ee740482c089be164
etape "arbres p1 et p2 différents : refusé" 1 "^KO   arbres p1 et p2 égaux : différents" "$B/R3" BANC_BLOB_AUTRE=final-p2
etape "retrait du pod en échec : refusé" 1 "^KO   p1 : retrait du pod \(code de kubectl\) : 1" "$B/R4" BANC_RETRAIT_KO=1
etape "PVC restante : refusé" 1 "^KO   p1 : PVC m4b-05-final-p1-w retirée \(code de kubectl wait\) : 1" "$B/R5" BANC_PVC_RESTE=1
etape "passage en échec : refusé, pod laissé" 1 "^KO   passage p1 en échec ; pod laissé pour lecture : m4b-05-final-p1$" "$B/R6" BANC_PATHPOD="$B/bin-sans-gpg:$B/base"
egal "passage en échec : pod laissé (faux cluster)" "$(ls "$E_DERNIER/k/pods")" m4b-05-final-p1
etape "liste différente de celle de prealables : refusé" 1 "^KO   liste des rpm \(sha256\)" "$B/R7" LISTE_SHA_CAS=95541ee86a3c8891d231df6896558a78f73a607037b2a7035312337ab80b8910
mkdir -p "$B/R8"; verrou_banc "$B/R8"; cp "$B/liste.txt" "$B/R8/m4b-liste.txt"; echo autre > "$B/R8/m4b-final-arbre.txt"
etape "arbre archivé différent : refusé" 1 "^KO   arbre égal à celui archivé : différent" "$B/R8"
echo "# bilan : $([ "$k" = 0 ] && echo tenu || echo NON TENU), $n OK, $k KO, fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
