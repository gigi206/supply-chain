#!/usr/bin/env bash
# Brique 05, M4b : banc des scripts du pod d'essai de m4b.sh (pas de prefetch et comparaisons), hors cluster, hors réseau. Les deux
# scripts sont extraits de m4b.sh et joués par dash (/bin/sh) avec de faux curl, rpm, createrepo_c, skopeo et gpg dans le PATH :
# cas nominal, puis un cas refusé par écart (sha256, taille, nom en double, signature, outil absent, empreinte, manifeste).
# Le faux createrepo_c date repomd.xml sauf avec --revision : les comparaisons doivent voir le défaut différer et V1, V2 égaux.
# PATH restreint aux faux outils et aux seuls outils de base présents dans l'image d'outillage (s1-racine.log : ni cmp ni diff).
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m4b-banc.sh <dossier-neuf> <m4b.sh>
set -euo pipefail
B=$1; SCRIPT=$2
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/bin" "$B/src" "$B/cas"
python3 -I - "$SCRIPT" "$B" <<'PY'
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text(); b = pathlib.Path(sys.argv[2])
for nom in ('SONDE', 'PREFETCH', 'COMPARE'):
    m = re.search(nom + r"=\$\(cat <<'SH'\n(.*?)\nSH\n\)", t, re.S)
    (b / (nom.lower() + '.sh')).write_text(m.group(1) + '\n')
PY
# rpm factices et liste
for n in a-1.0-1.el9.x86_64.rpm b-2.0-1.el9.noarch.rpm c-3.0-1.el9.x86_64.rpm; do printf 'contenu de %s\n' "$n" > "$B/src/$n"; done
liste() { for f in "$B"/src/*.rpm; do echo "https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os/Packages/${f##*/} $(sha256sum < "$f" | cut -c1-64) $(stat -c %s "$f")"; done; }
liste > "$B/liste.txt"
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
case "$1" in --version) echo "Version: 0.20.1 (factice)"; exit 0 ;; --help) printf '  --revision=REVISION\n  --set-timestamp-to-revision\n  --no-database\n  --compatibility\n'; exit 0 ;; esac
for a; do d=$a; done
mkdir -p "$d/repodata"
case "$*" in *--revision*) echo "fixe $(ls "$d" | grep -c rpm)" > "$d/repodata/repomd.xml" ;; *) echo "daté $(date +%s%N)" > "$d/repodata/repomd.xml" ;; esac
case "$*" in *--no-database*) ;; *) echo base > "$d/repodata/primary.sqlite.bz2" ;; esac
E
cat > "$B/bin/skopeo" <<'E'
#!/bin/sh
[ "$1" = inspect ] && { cat "$BANC_MAN"; exit 0; }
for a; do d=$a; done; d=${d#dir:}
mkdir -p "$d" && cp "$BANC_MAN" "$d/manifest.json" && echo couche > "$d/blob" && echo "Directory Transport Version: 1.1" > "$d/version"
E
cat > "$B/bin/gpg" <<'E'
#!/bin/sh
echo "fpr:::::::::${BANC_FP:-21CB256AE16FC54C6E652949702D426D350D275D}:"
E
chmod +x "$B"/bin/*
# outils de base de l'image (coreutils, findutils, gawk, sed, grep, bash) ; ni cmp ni diff
mkdir -p "$B/base" && for f in sh sed cut sha256sum stat mkdir ls cat grep awk tail tr date find wc du cp rm touch sort head env comm id; do ln -s "$(command -v "$f")" "$B/base/$f"; done

n=0; k=0
cas() { # libellé code-attendu motif-attendu [VAR=valeur…] : pas de prefetch joué par dash dans un dossier neuf
  local lib=$1 voulu=$2 motif=$3 c rc; shift 3
  c=$B/cas/$((n + k + 1)); mkdir -p "$c/tmp"
  set +e
  env -i PATH="$B/bin:$B/base" BANC_SRC="$B/src" BANC_MAN="$B/manifest.json" SORTIE="$c/sortie" LISTE_FICHIER="${LISTE_CAS:-$B/liste.txt}" \
    SOURCE="sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@${MAN_CAS:-$MAN}" DOSSIER="sc-stockage.poc.test@$MAN" \
    FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D CLE_ROCKY="$B/cle" TMPDIR="$c/tmp" "$@" sh "$B/prefetch.sh" > "$c/sortie.txt" 2>&1
  rc=$?
  set -e
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$c/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 2 "$c/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
}
cas "nominal, passage p1 (3 rpm, 2 fichiers de repodata, 3 du dossier dir:)" 0 "fermeture : 8 fichiers"
# PATH sans gpg
mkdir -p "$B/bin-sans-gpg" && for f in curl rpm createrepo_c skopeo; do ln -s "$B/bin/$f" "$B/bin-sans-gpg/$f"; done
cas "gpg absent : identifiant court seul (PATH sans gpg)" 0 "gpg absent de l'image" PATH="$B/bin-sans-gpg:$B/base"
sed '1s/ [0-9a-f]\{64\} / 0000000000000000000000000000000000000000000000000000000000000000 /' "$B/liste.txt" > "$B/liste-sha"
LISTE_CAS=$B/liste-sha cas "sha256 faux refusé" 1 "KO   sha256 différent"
awk 'NR == 1 {$3 = $3 + 1} {print}' "$B/liste.txt" > "$B/liste-taille"
LISTE_CAS=$B/liste-taille cas "taille fausse refusée" 1 "KO   taille différente"
{ cat "$B/liste.txt"; head -n 1 "$B/liste.txt"; } > "$B/liste-double"
LISTE_CAS=$B/liste-double cas "nom en double refusé" 1 "KO   nom en double"
sed '1s#Packages/a-#Packages/z-#' "$B/liste.txt" > "$B/liste-404"
LISTE_CAS=$B/liste-404 cas "fichier absent du dépôt (HTTP 404) refusé" 1 "KO   HTTP 404"
cas "signature d'un rpm refusée" 1 "KO   signatures des rpm" BANC_SIG_KO=b-2.0
cas "empreinte gpg fausse refusée" 1 "KO   empreinte de la clé" BANC_FP=0000000000000000000000000000000000000000
cas "identifiant court faux refusé" 1 "KO   identifiant court" BANC_ID=deadbeef
MAN_CAS=sha256:0000000000000000000000000000000000000000000000000000000000000000 cas "manifeste différent refusé" 1 "KO   manifeste copié"
mkdir -p "$B/bin-sans-cr" && for f in curl rpm skopeo gpg; do ln -s "$B/bin/$f" "$B/bin-sans-cr/$f"; done
cas "createrepo_c absent refusé" 1 "KO   createrepo_c absent" PATH="$B/bin-sans-cr:$B/base"

# comparaisons : deux passages nominaux dans un espace, puis le script des comparaisons
E2=$B/espace
for p in p1 p2; do
  mkdir -p "$B/tmp-$p"
  env -i PATH="$B/bin:$B/base" BANC_SRC="$B/src" BANC_MAN="$B/manifest.json" SORTIE="$E2/$p" LISTE_FICHIER="$B/liste.txt" \
    SOURCE="sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@$MAN" DOSSIER="sc-stockage.poc.test@$MAN" \
    FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D CLE_ROCKY="$B/cle" sh "$B/prefetch.sh" > "$B/passage-$p.txt" 2>&1
done
env -i PATH="$B/bin:$B/base" ESPACE="$E2" sh "$B/compare.sh" > "$B/comparaisons.txt" 2>&1 || true
env -i PATH="$B/bin:$B/base" BANC_MAN="$B/manifest.json" SOURCE="sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@$MAN" sh "$B/sonde.sh" > "$B/sonde.txt" 2>&1 || true
sonde() { if grep -q -E -- "$2" "$B/sonde.txt"; then echo "OK   $1"; n=$((n + 1)); else echo "KO   $1 : « $2 » absent"; k=$((k + 1)); fi; }
sonde "sonde : outil absent signalé sans arrêt" "^outil cmp : absent$"
sonde "sonde : clé absente signalée sans arrêt (pas de /etc/pki sur l'hôte)" "^clé de l'image : ABSENTE"
sonde "sonde : lecture du manifeste, première forme" "^skopeo inspect, --cert-dir /etc/ca-poc : manifeste $MAN"
sonde "sonde : lecture du manifeste, seconde forme" "^skopeo inspect, SSL_CERT_FILE : manifeste $MAN"
sonde "sonde : options de createrepo_c relevées" "set-timestamp-to-revision"
verifie() { if grep -q -E -- "$2" "$B/comparaisons.txt"; then echo "OK   $1"; n=$((n + 1)); else echo "KO   $1 : « $2 » absent"; k=$((k + 1)); fi; }
verifie "p1 et p2 égaux hors repodata" "^égaux : 6 fichiers$"
verifie "repodata par défaut différents" "^repodata différents"
verifie "aide de createrepo_c relevée" "--set-timestamp-to-revision"
verifie "V1 : deux copies, repodata égaux" "^V1 : repodata égaux"
verifie "V2 : deux copies, repodata égaux, sans base sqlite" "^V2 : repodata égaux \(1 fichiers\)"
echo "bilan : $n OK, $k KO"
[ "$k" = 0 ]
