#!/usr/bin/env bash
# Banc hors réseau de l étape noms de paquets.sh (12/11/2026). Un programme Go qui importe image/png (et pas image/jpeg) est compilé
# ici (go de mise, GOPROXY=off, -s -w -trimpath) ; faux golang-1.24-src au copyright synthétique ; copie de paquets.sh avec les
# empreintes, R, T, le verrou et le buildinfo remplacés. Les vrais paquets ne sont pas lus.
# Usage : mise exec -- bash poc/bricks/13a-licences/resultats/paquets-noms-essai-local.sh
set -uo pipefail
export LC_ALL=C
D=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
B=$D/poc/bricks/13a-licences
H=$(mktemp -d "$HOME/.cache/supply-chain-poc/13a-essai-n.XXXXXX")
trap 'chmod -R u+w -- "${H:?}" 2>/dev/null; rm -rf -- "${H:?}"' EXIT
mkdir -p "$H/res" "$H/src"
echo "# banc paquets.sh noms, $(date -u +%FT%TZ), paquets.sh $(sha256sum < "$B/paquets.sh" | cut -c1-64), paquets.py $(sha256sum < "$B/paquets.py" | cut -c1-64), $(go version)"
cd "$H/src" || exit 1
printf 'module example.com/essai\n\ngo 1.24\n' > go.mod
printf 'package main\n\nimport (\n\t"fmt"\n\t"image/png"\n)\n\nvar _ = png.Decode\n\nfunc main() { fmt.Println(1) }\n' > main.go
GOPROXY=off GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS="-buildvcs=false -trimpath" GOCACHE=$H/gocache GOPATH=$H/gopath \
  go build -ldflags "-s -w -buildid=" -o "$H/essai" . || { echo "KO   banc : go build"; exit 1; }
cd "$D" || exit 1
cp "$H/essai" "$H/faux-temoin"; printf '\000cmd/link/internal/ld.Main' >> "$H/faux-temoin"
AM=$(go version -m "$H/essai" | awk 'NR == 1 {sub("^go", "", $2); print $2}')
fabriquer() { # sortie paquet version [binaire]
  python3 -I - "$@" "$SPDX/details/X11.json" <<'EOP'
import io, json, sys, tarfile
out, pq, ver = sys.argv[1:4]
binp = sys.argv[4] if len(sys.argv) > 5 else None
x11 = json.load(open(sys.argv[-1]))["licenseText"]
x11 = "\n".join(" " + (l if l.strip() else ".") for l in x11.strip().splitlines())
cr = ("Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n\n"
      "Files: *\nCopyright: 2026 x\nLicense: Go\n\n"
      "Files: src/image/png/reader.go\nCopyright: 2026 y\nLicense: MIT\n texte\n\n"
      "Files: src/image/jpeg/idct.go\nCopyright: 2026 z\nLicense: MPEG\n\n"
      "Files: src/cmd/internal/objabi/head.go\nCopyright: 2026 w\nLicense: X11\n\n"
      "Files: src/debug/dwarf/testdata/*\nCopyright: 2026 v\nLicense: Go\n\n"
      "Files: debian/*\nCopyright: 2026 u\nLicense: Go\n\n"
      "License: Go\n texte go\n\nLicense: MPEG\n texte mpeg\n\nLicense: X11\n" + x11 + "\n").encode()
def tarxz(e):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:xz") as t:
        for nom, data in e:
            ti = tarfile.TarInfo(nom); ti.size = len(data); t.addfile(ti, io.BytesIO(data))
    return b.getvalue()
ctl = tarxz([("./control", f"Package: {pq}\nVersion: {ver}\nArchitecture: {'amd64' if binp else 'all'}\n".encode())])
e = ([("./usr/bin/" + pq, open(binp, "rb").read())] if binp else [(f"./usr/share/doc/{pq}/copyright", cr)])
o = b"!<arch>\n"
for n, d in [("debian-binary", b"2.0\n"), ("control.tar.xz", ctl), ("data.tar.xz", tarxz(e))]:
    o += f"{n:<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(d):<10}".encode() + b"`\n" + d + (b"\n" if len(d) & 1 else b"")
open(out, "wb").write(o)
EOP
}
fabriquer "$H/src.deb" golang-1.24-src "$AM-1"
essai() { # cas binaire code-attendu motif-attendu
  local cas=$1 deb=$H/$1.deb s1 s2 rc
  fabriquer "$deb" essai 1.0-1 "$2"
  s1=$(sha256sum < "$deb" | cut -c1-64); s2=$(sha256sum < "$H/src.deb" | cut -c1-64)
  printf 'golang-1.24-src %s all %s 1 pool/x.deb\n' "$AM-1" "$s2" > "$H/verrou.txt"
  printf ' golang-1.24-src (= %s),\n' "$AM-1" > "$H/bi.txt"
  sed -e "s#^DEB_SHA=.*#DEB_SHA=$s1#" -e "s#^SRC_SHA=[^ ]*#SRC_SHA=$s2#" -e "s#^SRC_BI=\"[^\"]*\"#SRC_BI=\"golang-1.24-src (= $AM-1)\"#" \
      -e "s#^R=\$here/resultats\$#R=$H/res#" -e "s#^here=.*#here=$B#" -e "s#^T=.*#T=$H/travail#" \
      -e "s#\"\$repo/poc/packaging/verrou-deb.txt\"#\"$H/verrou.txt\"#g" \
      -e "s#\"\$repo/poc/bricks/06-deb-sbuild/resultats/s3-build-1.buildinfo\"#\"$H/bi.txt\"#g" "$B/paquets.sh" > "$H/paquets.sh"
  ! grep -q -e '"\$repo/poc/packaging/verrou-deb.txt"' -e '"\$repo/poc/bricks/06-deb-sbuild/resultats/s3-build-1.buildinfo"' "$H/paquets.sh" \
    && grep -q "^SRC_SHA=$s2 " "$H/paquets.sh" && grep -q "^DEB_SHA=$s1\$" "$H/paquets.sh" || { echo "KO   banc : substitutions ($cas)"; exit 1; }
  rc=0; DEB=$deb SRC=$H/src.deb bash "$H/paquets.sh" noms > "$H/$cas.log" 2>&1 || rc=$?
  if [ "$rc" = "$3" ] && grep -qE -- "$4" "$H/$cas.log" && ! grep -q '^Traceback' "$H/$cas.log"; then echo "OK   $cas : code $rc, « $4 »"
  else echo "KO   $cas : code $rc (attendu $3), motif « $4 »"; fi
  grep -vE '^(#|paquets.py :)' "$H/$cas.log" | sed "s#$H#<banc>#g; s/^/     /"
}
essai n-nominal "$H/essai" 0 '^  motif lié : src/image/png/reader.go \(image/png : [1-9][0-9]*\)$'
grep -E 'paragraphe [4-7] .*: non lié|paragraphe 2 \(Go\) : LIÉ|  X11 : .*ratio 1\.000' "$H/n-nominal.log" | wc -l | awk '{print ($1 == 6 ? "OK   n-nominal : jpeg, cmd, testdata, debian non liés ; * lié ; X11 identique au texte SPDX" : "KO   n-nominal : " $1 " ligne(s) sur 6")}'
essai n-script "$H/src.deb" 1 'REFUS : en-tête des informations de build|REFUS : 0 fichier'
essai n-temoin "$H/faux-temoin" 1 'KO   témoin cmd/link/internal/ld : 1 occurrence'
echo "chrono.tsv du banc : $(wc -l < "$H/res/chrono.tsv") lignes ; fichiers de 13a touchés : $(git -C "$D" status --porcelain -- poc/bricks/13a-licences/resultats/chrono.tsv poc/bricks/13a-licences/resultats/paquets-noms.log | wc -l)"
