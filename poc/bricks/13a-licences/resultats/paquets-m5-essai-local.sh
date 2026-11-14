#!/usr/bin/env bash
# Banc hors réseau de la bascule de M5 (paquets.py modules lit Static-Built-Using), préparé à sec le 14/11/2026. Un programme Go
# sans dépendance est compilé ici (go de mise, GOPROXY=off, -s -w -trimpath) ; debs SYNTHÉTIQUES (control avec ou sans
# Static-Built-Using, copyright avec ou sans Comment d'en-tête) ; les vrais paquets ne sont pas lus. Le cas sans champ est aussi
# passé au paquets.py d'avant la bascule (a821111) : sorties identiques exigées.
# Usage : mise exec -- bash poc/bricks/13a-licences/resultats/paquets-m5-essai-local.sh
set -uo pipefail
export LC_ALL=C
D=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
B=$D/poc/bricks/13a-licences
AVANT=a821111
H=$(mktemp -d "$HOME/.cache/supply-chain-poc/13a-essai-m5.XXXXXX")
trap 'chmod -R u+w -- "${H:?}" 2>/dev/null; rm -rf -- "${H:?}"' EXIT
mkdir -p "$H/src"
git -C "$D" show "$AVANT:poc/bricks/13a-licences/paquets.py" > "$H/paquets-avant.py" </dev/null || { echo "KO   banc : paquets.py de $AVANT"; exit 1; }
echo "# banc bascule M5, $(date -u +%FT%TZ), paquets.py $(sha256sum < "$B/paquets.py" | cut -c1-64), avant ($AVANT) $(sha256sum < "$H/paquets-avant.py" | cut -c1-64), $(go version)"
cd "$H/src" || exit 1
printf 'module example.com/essai\n\ngo 1.24\n' > go.mod
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println(1) }\n' > main.go
GOPROXY=off GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS="-buildvcs=false -trimpath" GOCACHE=$H/gocache GOPATH=$H/gopath \
  go build -ldflags "-s -w -buildid=" -o "$H/essai" . || { echo "KO   banc : go build"; exit 1; }
cd "$D" || exit 1
GV=$(go version -m "$H/essai" | awk 'NR == 1 {print $2}')
[[ $GV =~ ^go([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo "KO   banc : version de Go $GV hors de la forme goX.Y.Z"; exit 1; }
MA=${BASH_REMATCH[1]}; MI=${BASH_REMATCH[2]}; PA=${BASH_REMATCH[3]}
XY=$MA.$MI; AM=$XY.$PA
echo "version de Go du binaire d essai : $GV"
fabriquer() { # sortie champ(- si absent) comment(oui|non)
  python3 -I - "$H/essai" "$@" <<'EOP'
import io, sys, tarfile
binp, out, champ, com = sys.argv[1:5]
fmt = "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n"
if com == "oui":
    fmt += "Comment: notice synthétique du banc\n ligne de suite\n"
cr = fmt + "\nFiles: *\nCopyright: 2026 x\nLicense: Apache-2.0\n texte\n"
ctl = "Package: essai\nVersion: 1.0-1\nArchitecture: amd64\n"
if champ != "-":
    ctl += champ + "\n"
ctl += "Description: banc\n"
def tarxz(e):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:xz") as t:
        for nom, data in e:
            ti = tarfile.TarInfo(nom); ti.size = len(data); t.addfile(ti, io.BytesIO(data))
    return b.getvalue()
c = tarxz([("./control", ctl.encode())])
d = tarxz([("./usr/share/doc/essai/copyright", cr.encode()), ("./usr/bin/essai", open(binp, "rb").read())])
o = b"!<arch>\n"
for n, x in [("debian-binary", b"2.0\n"), ("control.tar.xz", c), ("data.tar.xz", d)]:
    o += f"{n:<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(x):<10}".encode() + b"`\n" + x + (b"\n" if len(x) & 1 else b"")
open(out, "wb").write(o)
EOP
}
essai() { # cas champ comment code-attendu motif-attendu
  local cas=$1 rc
  fabriquer "$H/$cas.deb" "$2" "$3" || { echo "KO   banc : fabrication ($cas)"; exit 1; }
  rc=0; python3 -I "$B/paquets.py" modules "$H/$cas.deb" > "$H/$cas.log" 2>&1 || rc=$?
  if [ "$rc" = "$4" ] && grep -qE -- "$5" "$H/$cas.log" && ! grep -q '^Traceback' "$H/$cas.log"; then echo "OK   $cas : code $rc, « $5 »"
  else echo "KO   $cas : code $rc (attendu $4), motif « $5 »"; fi
  grep -E '^(control|OK   Static|KO|REFUS|ÉCART bib)' "$H/$cas.log" | sed "s/^/     /"
}
essai sans-champ - non 0 "^ÉCART bibliothèque standard de $GV : compilée dans le binaire, hors des sources, donc hors du copyright ; Built-Using absent\$"
rc=0; python3 -I "$H/paquets-avant.py" modules "$H/sans-champ.deb" > "$H/avant.log" 2>&1 || rc=$?
if [ "$rc" = 0 ] && cmp -s "$H/avant.log" "$H/sans-champ.log"; then echo "OK   sans-champ : sortie identique à celle de paquets.py $AVANT (code $rc)"
else echo "KO   sans-champ : sortie différente de celle de paquets.py $AVANT (code $rc)"; diff "$H/avant.log" "$H/sans-champ.log" | sed "s/^/     /"; fi
essai juste "Static-Built-Using: golang-$XY (= $AM-1)" oui 0 "^OK   Static-Built-Using golang-$XY \(= $AM-1\) : paquet source et version amont égaux à $GV du buildinfo\$"
grep -qE "^ÉCART bibliothèque standard de $GV : .*hors des paragraphes Files du copyright ; Comment d'en-tête présent, contenu non contrôlé ; Static-Built-Using golang-$XY \(= $AM-1\)\$" "$H/juste.log" \
  && echo "OK   juste : ÉCART avec Comment présent" || echo "KO   juste : ÉCART avec Comment présent attendu"
essai sans-comment "Static-Built-Using: golang-$XY (= $AM-1)" non 0 "Comment d'en-tête absent, contenu non contrôlé"
essai version-fausse "Static-Built-Using: golang-$XY (= $XY.$((PA + 1))-1)" oui 1 "^KO   Static-Built-Using .* : ne correspond pas à $GV du buildinfo\$"
essai autre-source "Static-Built-Using: golang-$MA.$((MI + 1)) (= $AM-1)" oui 1 "^KO   Static-Built-Using .* : ne correspond pas à $GV du buildinfo\$"
essai deux-entrees "Static-Built-Using: golang-$XY (= $AM-1), libfoo (= 1.0-1)" oui 1 "^KO   Static-Built-Using .* : forme attendue"
essai operateur "Static-Built-Using: golang-$XY (>= $AM-1)" oui 1 "^KO   Static-Built-Using .* : forme attendue"
# limite écrite dans les prédictions : la révision Debian n'est pas contrôlée (doit sortir OK)
essai limite-revision "Static-Built-Using: golang-$XY (= $AM-99)" oui 0 "^OK   Static-Built-Using golang-$XY \(= $AM-99\) : paquet source et version amont"
echo "fichiers de 13a touchés par le banc : $(git -C "$D" status --porcelain -- poc/bricks/13a-licences/resultats/chrono.tsv poc/bricks/13a-licences/resultats/paquets-modules.log | wc -l)"
