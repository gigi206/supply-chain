#!/usr/bin/env bash
# Banc hors réseau de l étape lies de paquets.sh (12/11/2026). Un programme Go qui importe fmt (et ni debug/elf ni image/jpeg) est
# compilé ici (go de mise, GOPROXY=off, -s -w -trimpath) ; faux golang-X.Y-src avec copyright et sources SYNTHÉTIQUES sous
# ./usr/share/go-1.24/src/ ; copie de paquets.sh avec DEB_SHA, SRC_SHA, SRC_BI, R, T, verrou, buildinfo et traductions remplacés.
# Les vrais paquets ne sont pas lus. Usage : mise exec -- bash poc/bricks/13a-licences/resultats/paquets-lies-essai-local.sh
set -uo pipefail
export LC_ALL=C
D=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
B=$D/poc/bricks/13a-licences
H=$(mktemp -d "$HOME/.cache/supply-chain-poc/13a-essai-l.XXXXXX")
trap 'chmod -R u+w -- "${H:?}" 2>/dev/null; rm -rf -- "${H:?}"' EXIT
mkdir -p "$H/res" "$H/src"
echo "# banc paquets.sh lies, $(date -u +%FT%TZ), paquets.sh $(sha256sum < "$B/paquets.sh" | cut -c1-64), paquets.py $(sha256sum < "$B/paquets.py" | cut -c1-64), $(go version)"
cd "$H/src" || exit 1
printf 'module example.com/essai\n\ngo 1.24\n' > go.mod
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println(1) }\n' > main.go
GOPROXY=off GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS="-buildvcs=false -trimpath" GOCACHE=$H/gocache GOPATH=$H/gopath \
  go build -ldflags "-s -w -buildid=" -o "$H/essai" . || { echo "KO   banc : go build"; exit 1; }
cd "$D" || exit 1
GV=$(go version -m "$H/essai" | awk 'NR == 1 {print $2}'); AM=${GV#go}
echo "version de Go du binaire d essai : $GV"
fabriquer() { # sortie paquet version cas [binaire]
  python3 -I - "$@" <<'EOP'
import io, sys, tarfile
out, pq, ver, cas = sys.argv[1:5]
binp = sys.argv[5] if len(sys.argv) > 5 else None
en = "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n\nFiles: *\nCopyright: 2026 x\nLicense: BSD-3-clause\n texte\n"
def par(files, cr="Copyright: 2026 y\n"):
    return f"\nFiles: {files}\n{cr}License: FreeBSD\n texte freebsd\n"
S = "./usr/share/go-1.24/src/"
sources = [(S + "debug/elf/file.go", b"package elf\n\nfunc Open() {\n}\n"),
           (S + "internal/goarch/goarch.go", b"package goarch\n\nconst PtrSize = 8\n"),
           (S + "internal/arm/x_arm64.go", b"package arm\n\nfunc F() {\n}\n"),
           (S + "fmt/print.go", b"package fmt\n\nfunc Println() {\n}\n")]
cr = {"absent": en + par("src/debug/elf/*"), "present": en + par("src/fmt/*"), "sans-fonction": en + par("src/internal/goarch/*"),
      "autre-arch": en + par("src/internal/arm/*"), "cmd": en + par("src/cmd/x/* debian/*"), "defaut": en + par("src/debug/elf/*", ""),
      "vide": en + par("src/debug/elf/*")}.get(cas, "")
if cas == "vide":
    sources = []
def tarxz(e):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:xz") as t:
        for nom, data in e:
            ti = tarfile.TarInfo(nom); ti.size = len(data); t.addfile(ti, io.BytesIO(data))
    return b.getvalue()
ctl = tarxz([("./control", f"Package: {pq}\nVersion: {ver}\nArchitecture: {'amd64' if binp else 'all'}\n".encode())])
if binp:
    e = [(f"./usr/share/doc/{pq}/copyright", en.split("\n\nFiles")[0].encode() + b"\n\nFiles: *\nCopyright: 2026 x\nLicense: Apache-2.0\n texte\n"),
         ("./usr/bin/" + pq, open(binp, "rb").read())]
else:
    e = [(f"./usr/share/doc/{pq}/copyright", cr.encode())] + sources
data = tarxz(e)
o = b"!<arch>\n"
for n, d in [("debian-binary", b"2.0\n"), ("control.tar.xz", ctl), ("data.tar.xz", data)]:
    o += f"{n:<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(d):<10}".encode() + b"`\n" + d + (b"\n" if len(d) & 1 else b"")
open(out, "wb").write(o)
EOP
}
fabriquer "$H/app.deb" essai 1.0-1 app "$H/essai"
echo '[]' > "$H/trad.json"
essai() { # cas cas-du-copyright étape code-attendu motif-attendu
  local cas=$1 src=$H/$1-src.deb s1 s2 rc x
  fabriquer "$src" golang-1.24-src "$AM-1" "$2"
  s1=$(sha256sum < "$H/app.deb" | cut -c1-64); s2=$(sha256sum < "$src" | cut -c1-64)
  printf 'golang-1.24-src %s all %s 1 pool/main/g/x/golang-1.24-src.deb\n' "$AM-1" "$s2" > "$H/verrou.txt"
  printf 'Installed-Build-Depends:\n golang-1.24-src (= %s),\n' "$AM-1" > "$H/bi.txt"
  sed -e "s#^DEB_SHA=.*#DEB_SHA=$s1#" -e "s#^SRC_SHA=[^ ]*#SRC_SHA=$s2#" -e "s#^SRC_BI=\"[^\"]*\"#SRC_BI=\"golang-1.24-src (= $AM-1)\"#" \
      -e "s#^R=\$here/resultats\$#R=$H/res#" -e "s#^here=.*#here=$B#" -e "s#^T=.*#T=$H/travail#" \
      -e "s#\"\$repo/poc/packaging/verrou-deb.txt\"#\"$H/verrou.txt\"#g" \
      -e "s#\"\$repo/poc/bricks/06-deb-sbuild/resultats/s3-build-1.buildinfo\"#\"$H/bi.txt\"#g" \
      -e "s#\"\$here/traductions-dep5.json\"#\"$H/trad.json\"#g" "$B/paquets.sh" > "$H/paquets.sh"
  for x in "^DEB_SHA=$s1\$" "^SRC_SHA=$s2 " "^SRC_BI=\"golang-1.24-src (= $AM-1)\"" "^R=$H/res\$" "^here=$B\$" "^T=$H/travail\$" "\"$H/verrou.txt\"" "\"$H/bi.txt\"" "\"$H/trad.json\""; do
    grep -q -- "$x" "$H/paquets.sh" || { echo "KO   banc : substitution absente ($cas) : $x"; exit 1; }
  done
  ! grep -q -e '"\$repo/poc/packaging/verrou-deb.txt"' -e '"\$repo/poc/bricks/06-deb-sbuild/resultats/s3-build-1.buildinfo"' -e '"\$here/traductions-dep5.json"' "$H/paquets.sh" \
    || { echo "KO   banc : chemin réel restant ($cas)"; exit 1; }
  rc=0; DEB=$H/app.deb SRC=$src bash "$H/paquets.sh" "$3" > "$H/$cas.log" 2>&1 || rc=$?
  if [ "$rc" = "$4" ] && grep -qE -- "$5" "$H/$cas.log" && ! grep -q '^Traceback' "$H/$cas.log"; then echo "OK   $cas : code $rc, « $5 »"
  else echo "KO   $cas : code $rc (attendu $4), motif « $5 »"; fi
  grep -E '^(OK|KO|REFUS|bilan|pkg:|licences\.py|Files|écarté|gardé|  motif|## règle)|^ +(ok|error|warning) ' "$H/$cas.log" | sed "s#$H#<banc>#g; s/^/     /"
}
essai l-absent absent lies 0 '^écarté : paragraphe 3 \(FreeBSD\)'
essai l-sans-option absent stdlib 1 '^KO   verdict non conforme'
essai l-present present lies 1 '^KO   verdict non conforme'
essai l-sans-fonction sans-fonction lies 1 'internal/goarch : 0, absence non probante'
essai l-autre-arch autre-arch lies 1 'internal/arm : 0, absence non probante'
essai l-cmd cmd lies 0 '^écartés : 1 sur 2 paragraphe'
essai l-defaut defaut lies 1 '^REFUS : 1 défaut\(s\) : paragraphe 3 : champ\(s\) manquant\(s\) : copyright'
essai l-vide vide lies 1 '^REFUS : règle des paragraphes non liés : aucun paquet de la source indexé'
echo "chrono.tsv du banc : $(wc -l < "$H/res/chrono.tsv") lignes ; fichiers de 13a touchés : $(git -C "$D" status --porcelain -- poc/bricks/13a-licences/resultats/chrono.tsv poc/bricks/13a-licences/resultats/paquets-lies.log poc/bricks/13a-licences/resultats/paquets-lies.licences.json | wc -l)"
