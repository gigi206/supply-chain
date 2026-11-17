#!/usr/bin/env bash
# Brique 05, M4b : banc hors cluster des étapes prealables_taches et essai_tache de m4b.sh et du gabarit de la tâche prefetch-rpm
# (carte de taches, décision « Oui » sur repomd.xml du 17/11/2026), écrit avant tout passage, hors réseau.
# A : insertions seules contre le m4b.sh d'avant (deux blocs : en-tête, bloc avant lancer) ; bash -n ; shellcheck : SC2016 seulement.
# B : la vraie fonction etape_prealables_taches de la copie, avec les vrais gabarits du dépôt, le vrai publier-fermeture signé, yq,
#     jq et oras de l'hôte (layouts locaux), sur des données du banc (222 rpm factices, verrou du banc au digest d'un faux manifeste,
#     fermeture restaurée et arbre de référence factices) et un faux « sur » : nominal ; fichier restauré différent ; gabarit de la
#     tâche avec une variable d'environnement de plus ; ressources sous computeResources (nom de l'API v1) : code 1.
# C : le script de la tâche, rendu et substitué par les fonctions de la copie comme dans l'étape, chemins /tmp et de la clé
#     réécrits pour le banc, joué par dash avec de faux curl, rpm, createrepo_c, skopeo, gpg et un PATH restreint aux outils de base
#     de l'image : nominal (résultat écrit) ; la vraie liste des 222 rpm passe les contrôles (arrêt au premier téléchargement, faux
#     404) ; repomd.xml attendu faux refusé avant la copie de l'image ; dix entrées invalides refusées ; gpg absent refusé.
# D : la vraie fonction etape_essai_tache de la copie, avec un faux kubectl qui joue les scripts du pod par dash dans un dossier
#     par pod : nominal ; script en échec (pod laissé) ; arbre différent de la référence ; retrait en échec ; PVC restante : code 1.
# Non couvert : vrais pods, réseau, rpm, createrepo_c, Tekton (substitution réelle, workspace, résultat), admission.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4b-taches-banc.sh <dossier-neuf> <m4b.sh avant>
#         <copie modifiée de m4b.sh> [lignes d'en-tête, 14] [lignes du bloc, 165]
set -uo pipefail
export LC_ALL=C
B=$1; AVANT=$2; COPIE=$3; HE=${4:-14}; HB=${5:-165}
DASH=$(command -v dash); RACINE=$PWD; VERROU=$RACINE/poc/bricks/05-rpm-mock/resultats/s1-verrou_derivee.json
LISTE_VRAIE=$RACINE/poc/bricks/05-rpm-mock/resultats/m4b-liste.txt
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"/{bin,base,src}
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4b-taches-banc.sh, $(date -u +%FT%TZ) ; m4b.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; copie $(sha256sum < "$COPIE" | cut -c1-64)"
echo "# gabarits : prefetch-rpm.yaml $(sha256sum < poc/bricks/05-rpm-mock/fermeture/prefetch-rpm.yaml | cut -c1-64) ; prefetch-rpm-sample-app.yaml $(sha256sum < poc/bricks/05-rpm-mock/fermeture/prefetch-rpm-sample-app.yaml | cut -c1-64)"

echo "## A : insertions seules, syntaxe, shellcheck"
diff "$AVANT" "$COPIE" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
egal "lignes insérées (en-tête $HE, bloc $HB)" "$(grep -c '^>' "$B/diff.txt")" "$((HE + HB))"
egal "bash -n" "$(bash -n "$COPIE" && echo ok)" ok
sc() { LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$1" 2>/dev/null | grep -o 'SC[0-9]*' | sort | uniq -c; }
sc "$AVANT" > "$B/sc-avant"; sc "$COPIE" > "$B/sc-copie"
egal "shellcheck : écarts (SC2016 seulement)" "$(diff "$B/sc-avant" "$B/sc-copie" | grep '^[<>]' | tr -s ' ' | awk '{print $1, $3}' | paste -sd' ')" "< SC2016 > SC2016"

# Données du banc
for i in $(seq -w 1 222); do printf 'contenu du rpm %s\n' "$i" > "$B/src/p$i-1.0-1.el9.x86_64.rpm"; done
printf 'contenu du rpm +\n' > "$B/src/q+x-1.0-1.el9.noarch.rpm"; rm -f "$B/src/p222-1.0-1.el9.x86_64.rpm"   # un nom avec « + »
for f in "$B"/src/*.rpm; do echo "https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os/Packages/${f##*/} $(sha256sum < "$f" | cut -c1-64) $(stat -c %s "$f")"; done > "$B/liste.txt"
printf '{"schemaVersion":2}\n' > "$B/manifest.json"
MAN=sha256:$(sha256sum < "$B/manifest.json" | cut -c1-64)
SRC=sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@$MAN; DOS=sc-stockage.poc.test@$MAN
printf 'CLE FACTICE\n' > "$B/cle"
REPOMD_BANC=$( { echo fixe; ls "$B/src" | grep '\.rpm$'; } | sha256sum | cut -c1-64)
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
  *" -K "*) shift 3; for f; do echo "$f: digests signatures OK"; done; exit 0 ;;
esac
echo "faux rpm : $*" >&2; exit 3
E
cat > "$B/bin/createrepo_c" <<'E'
#!/bin/sh
for a; do d=$a; done
[ "$*" = "--compatibility --revision 0 --set-timestamp-to-revision --no-database $d" ] || { echo "options inattendues : $*"; exit 4; }
for f in "$d"/*.rpm; do [ "$(stat -c %Y "$f")" = 0 ] || { echo "rpm non daté à 0 : $f"; exit 5; }; done
[ -z "$(find "$d" -mindepth 1 -type d)" ] || { echo "dossier présent dans le dépôt"; exit 6; }
mkdir -p "$d/repodata"
{ echo fixe; ls "$d" | grep '\.rpm$'; } > "$d/repodata/repomd.xml"
for x in primary filelists other; do echo "$x" > "$d/repodata/$x.xml.gz"; done
E
cat > "$B/bin/skopeo" <<'E'
#!/bin/sh
for a; do d=$a; done; d=${d#dir:}
mkdir -p "$d" && cp "$BANC_MAN" "$d/manifest.json" && echo config > "$d/config" && echo "Directory Transport Version: 1.1" > "$d/version" && echo couche > "$d/couche"
E
cat > "$B/bin/gpg" <<'E'
#!/bin/sh
echo "fpr:::::::::21CB256AE16FC54C6E652949702D426D350D275D:"
E
chmod +x "$B"/bin/*
for f in sh sed cut sha256sum stat mkdir ls cat grep awk tail tr date find wc du cp rm touch sort head env comm id printf; do
  p=$(command -v "$f") && [ "${p#/}" != "$p" ] && ln -s "$p" "$B/base/$f"; done
mkdir -p "$B/bin-sans-gpg" && for f in curl rpm createrepo_c skopeo; do ln -s "$B/bin/$f" "$B/bin-sans-gpg/$f"; done
# arbre de référence : une fermeture produite par les faux outils (222 rpm, 4 de repodata, 4 du dossier dir:)
mkdir -p "$B/ref/depot"; cp "$B"/src/*.rpm "$B/ref/depot/"; touch -h -d @0 "$B"/ref/depot/*.rpm
env -i PATH="$B/bin:$B/base" BANC_MAN="$B/manifest.json" createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database "$B/ref/depot"
env -i PATH="$B/bin:$B/base" BANC_MAN="$B/manifest.json" skopeo copy x "dir:$B/ref/depot/$DOS"
(cd "$B/ref/depot" && find . -type f -printf '%P %s\n' | sort | while read -r f s; do echo "$f $s $(sha256sum < "$f" | cut -c1-64)"; done) > "$B/arbre-ref.txt"
egal "données : arbre de référence (fichiers)" "$(wc -l < "$B/arbre-ref.txt")" 230
# copie jouable : sans commun.sh ni lancer ; R, W, T1 fournis par le banc
python3 -I - "$COPIE" "$B/m4b-jouable.sh" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text().split('\n')
r = {'. "$here/commun.sh"   # repo, O, S, P, W, REG, lancer, chrono': ':', 'R=$h05/resultats': 'R=$BANC_R', 'lancer m4b "05 M4b" "$@"': ':'}
assert all(t.count(a) == 1 for a in r)
pathlib.Path(sys.argv[2]).write_text('\n'.join(r.get(l, l) for l in t))
PY
verrou_banc() { jq --arg s "$SRC" --arg m "$MAN" '.config.bootstrap_image = $s | .bootstrap.pull_digest = $m' "$VERROU" > "$1/s1-verrou_derivee.json"; }
jouer() { # dossier-W dossier-R fonction [VAR=valeur…] : fonction de la copie jouable ; sortie dans <W>/sortie.txt ; code rendu
  local w=$1 r=$2 fn=$3; shift 3
  mkdir -p "$w"
  env W="$w" BANC_R="$r" REG=sc-stockage.poc.test:5000 RACINE="$RACINE" REPOMD_BANC="$REPOMD_BANC" PATH="$B/kbin:$PATH" BANC_K="$w/k" \
    BANC_PATHPOD="$B/bin:$B/base" BANC_SRC="$B/src" BANC_MAN="$B/manifest.json" BANC_CLE="$B/cle" BANC_DASH="$DASH" "$@" bash -c '
    set -euo pipefail
    . "$1"
    TACHES=${TACHES_CAS:-$RACINE/poc/bricks/05-rpm-mock/fermeture}; PUBLIER_SIGNEE=$RACINE/poc/bricks/08-trust-plane/politique/taches/publier-fermeture.signee.yaml
    LISTE_SHA=$(sha256sum < "$LISTE" | cut -c1-64); REPOMD_V2=$REPOMD_BANC; ARBRE_REF=$BANC_R/arbre-ref.txt
    sur() { echo "1000 2000"; }
    "$2"' _ "$B/m4b-jouable.sh" "$fn" > "$w/sortie.txt" 2>&1
}
donnees_r() { mkdir -p "$1"; verrou_banc "$1"; cp "$B/liste.txt" "$1/m4b-liste.txt"; cp "$B/arbre-ref.txt" "$1/arbre-ref.txt"; }
restauree() { # W : fermeture « restaurée » du banc sous <W>/s1-05/m3/restauree-1/depot (226 fichiers réels du banc)
  mkdir -p "$1/s1-05/m3/restauree-1"; cp -a "$B/ref/depot" "$1/s1-05/m3/restauree-1/depot"; rm -rf "$1/s1-05/m3/restauree-1/depot/repodata"
}
cas_etape() { # libellé code motif W R fonction [VAR=valeur…]
  local lib=$1 voulu=$2 motif=$3 w=$4 r=$5 fn=$6 rc; shift 6
  jouer "$w" "$r" "$fn" "$@"; rc=$?
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$w/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 3 "$w/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
}

echo "## B : vraie fonction etape_prealables_taches"
donnees_r "$B/R"; restauree "$B/W1"
cas_etape "nominal" 0 "^utilisés 1000 octets ; libres 2000 octets$" "$B/W1" "$B/R" etape_prealables_taches
S1=$B/W1/sortie.txt; TB=$B/W1/m4b-05
egal "nominal : lignes OK de l'étape" "$(grep -c '^OK   ' "$S1")" 22
egal "nominal : diff du script contre PREFETCH_FINAL archivé dans la sortie" "$(grep -c '^     > ' "$S1")" 29
egal "nominal : couches à titres « @ » et « : »" "$(grep -c '^OK   titres à « : » et « @ » (dossier dir:) : 4$' "$S1")" 1
egal "nominal : deux layouts distincts" "$(ls -d "$TB"/pf/a/layout "$TB"/pf/b/layout | wc -l)" 2
egal "nominal : référence de la tâche dans la pipeline rendue (factice)" "$(yq '.spec.tasks[0].taskRef.params[0].value' "$TB/prefetch-rpm-sample-app.yaml")" \
  "sc-stockage.poc.test:5000/tekton/tasks/prefetch-rpm@sha256:0000000000000000000000000000000000000000000000000000000000000000"
restauree "$B/W2"; echo autre > "$B/W2/s1-05/m3/restauree-1/depot/p100-1.0-1.el9.x86_64.rpm"
cas_etape "fichier restauré différent de final : refusé" 1 "^KO   fichier de la fermeture restaurée différent de final : p100-" "$B/W2" "$B/R" etape_prealables_taches
mkdir -p "$B/taches-env"; cp poc/bricks/05-rpm-mock/fermeture/*.yaml "$B/taches-env/"
sed -i 's/^    - name: HOME$/    - name: LISTE_EN_TROP\n      value: x\n    - name: HOME/' "$B/taches-env/prefetch-rpm.yaml"
restauree "$B/W3"
cas_etape "variable d'environnement de plus dans la tâche : refusée" 1 "^KO   tâche : variables d'environnement du pas" "$B/W3" "$B/R" etape_prealables_taches TACHES_CAS="$B/taches-env"
mkdir -p "$B/taches-v1"; cp poc/bricks/05-rpm-mock/fermeture/*.yaml "$B/taches-v1/"
sed -i 's/^    resources:$/    computeResources:/' "$B/taches-v1/prefetch-rpm.yaml"   # nom du champ dans l'API v1, inconnu du Step de v1beta1
restauree "$B/W4"
cas_etape "ressources sous computeResources (API v1) : refusées" 1 "^KO   tâche : ressources du pas, champ resources de v1beta1" "$B/W4" "$B/R" etape_prealables_taches TACHES_CAS="$B/taches-v1"

echo "## C : script de la tâche (rendu, substitué), par dash"
# script du banc : celui de l'étape nominale, substitué pour des chemins du banc ; /tmp et la clé réécrits (banc seulement)
pour_banc() { # script-substitué dossier : copie jouable du script, /tmp et la clé de l'image sous <dossier>
  mkdir -p "$2/tmp"; sed -e "s#/tmp/#$2/tmp/#g" -e "s#/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9#$B/cle#g" "$1" > "$2/script.sh"
}
copie() { env W="$B/W0" BANC_R="$B/R" REG=sc-stockage.poc.test:5000 bash -c "$@"; }   # fonctions de la copie jouable
subst() { # pipeline-rendue dossier [repomd] : substitution par la fonction de la copie
  copie '. "$1" >/dev/null 2>&1 || true; shift; substituer "$@"' _ "$B/m4b-jouable.sh" "$TB/prefetch-rpm.yaml" "$1" "$2/w" "$2/resultat.json" "$2/subst.sh" ${3:+"$3"}
}
cas_script() { # libellé code motif dossier [sed…] : le script substitué du dossier, retouché par sed, joué par dash
  local lib=$1 voulu=$2 motif=$3 c=$4 rc; shift 4
  pour_banc "$c/subst.sh" "$c"
  [ $# = 0 ] || sed -i "$@" "$c/script.sh"
  env -i PATH="${PATH_CAS:-$B/bin:$B/base}" BANC_SRC="$B/src" BANC_MAN="$B/manifest.json" "$DASH" "$c/script.sh" > "$c/sortie.txt" 2>&1; rc=$?
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$c/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 3 "$c/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
}
i=0
nouveau() { i=$((i + 1)); C=$B/c/$i; mkdir -p "$C"; subst "$TB/prefetch-rpm-sample-app.yaml" "$C" "$@"; }
nouveau; cas_script "nominal" 0 "^fermeture : 230 fichiers" "$C"
egal "nominal : résultat BOOTSTRAP_ARTIFACT_INPUTS" "$(cat "$C/resultat.json")" "{\"uri\":\"oci://${SRC%@*}\",\"digest\":\"$MAN\"}"
egal "nominal : arbre égal à la référence" "$( (cd "$C/w/depot" && find . -type f -printf '%P %s\n' | sort | while read -r f s; do echo "$f $s $(sha256sum < "$f" | cut -c1-64)"; done) | cmp -s - "$B/arbre-ref.txt" && echo égal || echo différent)" égal
# la vraie liste : pipeline rendue avec m4b-liste.txt, faux curl sans aucun de ces fichiers (404 au premier)
mkdir -p "$B/vraie"; sed 's/^/        /' "$LISTE_VRAIE" > "$B/vraie/liste-indentee.txt"
copie '. "$1" >/dev/null 2>&1 || true; remplacer "$2" "$3" "PREFETCH_RPM=x" "PUBLIER_FERMETURE=x" "LISTE=$4" "SOURCE=$5" "DOSSIER=$6" "EMPREINTE=21CB256AE16FC54C6E652949702D426D350D275D" "REPOMD=$7" "DEPOT_FERMETURE=x"' \
  _ "$B/m4b-jouable.sh" "$RACINE/poc/bricks/05-rpm-mock/fermeture/prefetch-rpm-sample-app.yaml" "$B/vraie/pipeline.yaml" "$B/vraie/liste-indentee.txt" "$SRC" "$DOS" "$REPOMD_BANC"
i=$((i + 1)); C=$B/c/$i; mkdir -p "$C"; subst "$B/vraie/pipeline.yaml" "$C"
cas_script "vraie liste (222 lignes) : contrôles passés, arrêt au premier téléchargement" 1 "^KO   HTTP 404 : $(head -n 1 "$LISTE_VRAIE" | cut -d' ' -f1 | sed 's/[.+]/\\&/g')$" "$C"
egal "vraie liste : aucun refus de contrôle" "$(grep -c -E 'invalide|hors de vault|plus de trois champs' "$C/sortie.txt")" 0
nouveau 0000000000000000000000000000000000000000000000000000000000000000
cas_script "repomd.xml attendu faux : refusé" 1 "^KO   repomd.xml différent de l'attendu \(fixé par la pipeline\)$" "$C"
egal "repomd.xml faux : ni dossier dir:, ni résultat" "$(ls -A "$C/w/depot" | grep -c -F "$DOS") $(ls "$C/resultat.json" 2>/dev/null | wc -l)" "0 0"
nouveau; cas_script "source sans digest : refusée" 1 "^KO   source invalide" "$C" "s#^SOURCE='.*'#SOURCE='sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap:latest'#"
nouveau; cas_script "digest de la source trop court : refusé" 1 "^KO   digest de la source invalide" "$C" "s#^SOURCE='\(.*\)[0-9a-f]'#SOURCE='\1'#"
nouveau; cas_script "dossier incohérent : refusé" 1 "^KO   dossier incohérent" "$C" "s#^DOSSIER='.*'#DOSSIER='autre@$MAN'#"
nouveau; cas_script "empreinte en minuscules : refusée" 1 "^KO   empreinte invalide" "$C" "s#^FP_ROCKY='.*'#FP_ROCKY='21cb256ae16fc54c6e652949702d426d350d275d'#"
nouveau; cas_script "repomd attendu mal formé : refusé" 1 "^KO   repomd invalide" "$C" "s#^REPOMD='.*'#REPOMD='abc'#"
nouveau; cas_script "URL hors de vault 9.7 : refusée" 1 "^KO   URL hors de vault 9.7" "$C" '0,\#^https://dl.rockylinux.org/vault/rocky/9.7/#s##https://dl.rockylinux.org/pub/rocky/9.8/#'
nouveau; cas_script "URL avec « .. » : refusée" 1 "^KO   URL invalide" "$C" '0,\#^https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/#s##https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/../#'
nouveau; cas_script "sha256 mal formé : refusé" 1 "^KO   sha256 invalide" "$C" '0,/^\(https:[^ ]*\) [0-9a-f]\{64\} /s//\1 XYZ /'
nouveau; cas_script "taille mal formée : refusée" 1 "^KO   taille invalide" "$C" '0,/^\(https:[^ ]* [0-9a-f]\{64\}\) [0-9]*$/s//\1 12a/'
nouveau; cas_script "ligne à quatre champs : refusée" 1 "^KO   ligne de liste à plus de trois champs" "$C" '0,/^\(https:[^ ]* [0-9a-f]\{64\} [0-9]*\)$/s//\1 en-trop/'
nouveau; PATH_CAS="$B/bin-sans-gpg:$B/base" cas_script "gpg absent : refusé" 1 "^KO   gpg absent de l'image" "$C"

echo "## D : vraie fonction etape_essai_tache, faux kubectl"
cat > "$B/kubectl" <<'E'
#!/usr/bin/env bash
# faux kubectl : état sous $BANC_K (pods/<nom>/{w,tmp}, pvc/<nom>-w) ; scripts et commandes du pod joués dans un dossier par pod
set -u
K=$BANC_K; mkdir -p "$K/pods" "$K/pvc"; echo "kubectl $*" >> "$K/appels"
carte() { sed -e "s#/workspace/sortie#$K/pods/$1/w#g" -e "s#/tmp/#$K/pods/$1/tmp/#g" -e "s#/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9#$BANC_CLE#g"; }
envpod() { env -i PATH="$BANC_PATHPOD" BANC_SRC="$BANC_SRC" BANC_MAN="$BANC_MAN" "$@"; }
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
  exec)   shift; [ "$1" != -i ] || shift; nom=$3; shift 4
          [ -d "$K/pods/$nom" ] || { echo "pod absent : $nom" >&2; exit 1; }
          if [ "$1 $2" = "sh -s" ]; then carte "$nom" > "$K/pods/$nom/script-$$.sh"; envpod "$BANC_DASH" "$K/pods/$nom/script-$$.sh"; exit $?; fi
          if [ "$1 $2" = "sh -c" ]; then envpod "$BANC_DASH" -c "$(printf %s "$3" | carte "$nom")"; exit $?; fi
          a=(); for x; do a+=("$(printf %s "$x" | carte "$nom")"); done; envpod "${a[@]}"; exit $? ;;
esac
echo "faux kubectl : appel inattendu : $*" >&2; exit 3
E
chmod +x "$B/kubectl"; mkdir -p "$B/kbin"; ln -s "$B/kubectl" "$B/kbin/kubectl"
cas_etape "nominal" 0 "^OK   pods et PVC restants au nom de m4b-05-essai-tache : 0$" "$B/D1" "$B/R" etape_essai_tache
egal "nominal : lignes OK de l'étape" "$(grep -c '^OK   ' "$B/D1/sortie.txt")" 14
egal "nominal : pods créés" "$(grep -c '^kubectl create -f' "$B/D1/k/appels")" 1
cas_etape "script en échec : refusé, pod laissé" 1 "^KO   script de la tâche en échec ; pod laissé pour lecture : m4b-05-essai-tache$" "$B/D2" "$B/R" etape_essai_tache BANC_PATHPOD="$B/bin-sans-gpg:$B/base"
egal "script en échec : pod laissé (faux cluster)" "$(ls "$B/D2/k/pods")" m4b-05-essai-tache
mkdir -p "$B/R2"; donnees_r "$B/R2"; echo autre >> "$B/R2/arbre-ref.txt"
cas_etape "arbre différent de la référence : refusé" 1 "^KO   arbre égal à celui de final : différent" "$B/D3" "$B/R2" etape_essai_tache
cas_etape "retrait du pod en échec : refusé" 1 "^KO   retrait du pod \(code de kubectl\) : 1" "$B/D4" "$B/R" etape_essai_tache BANC_RETRAIT_KO=1
cas_etape "PVC restante : refusée" 1 "^KO   PVC m4b-05-essai-tache-w retirée \(code de kubectl wait\) : 1" "$B/D5" "$B/R" etape_essai_tache BANC_PVC_RESTE=1
echo "# bilan : $([ "$k" = 0 ] && echo tenu || echo NON TENU), $n OK, $k KO, fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
