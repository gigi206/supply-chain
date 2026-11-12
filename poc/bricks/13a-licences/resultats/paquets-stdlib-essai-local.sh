#!/usr/bin/env bash
# Banc hors réseau de l étape stdlib de paquets.sh (12/11/2026). Un petit programme Go est compilé ici (go de mise, GOPROXY=off) ;
# debs SYNTHÉTIQUES de l application et d un faux golang-X.Y-src ; copie de paquets.sh avec DEB_SHA, SRC_SHA, SRC_BI, R, T et les
# chemins du verrou et du buildinfo remplacés. Les vrais paquets ne sont pas lus.
# Usage : mise exec -- bash poc/bricks/13a-licences/resultats/paquets-stdlib-essai-local.sh
set -uo pipefail
export LC_ALL=C
D=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
B=$D/poc/bricks/13a-licences
H=$(mktemp -d "$HOME/.cache/supply-chain-poc/13a-essai-s.XXXXXX")
trap 'chmod -R u+w -- "${H:?}" 2>/dev/null; rm -rf -- "${H:?}"' EXIT
mkdir -p "$H/res" "$H/src"
echo "# banc paquets.sh stdlib, $(date -u +%FT%TZ), paquets.sh $(sha256sum < "$B/paquets.sh" | cut -c1-64), paquets.py $(sha256sum < "$B/paquets.py" | cut -c1-64), $(go version)"
cd "$H/src" || exit 1
printf 'module example.com/essai\n\ngo 1.24\n' > go.mod
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println(1) }\n' > main.go
GOPROXY=off GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS="-buildvcs=false -trimpath" GOCACHE=$H/gocache GOPATH=$H/gopath \
  go build -ldflags "-s -w -buildid=" -o "$H/essai" . || { echo "KO   banc : go build"; exit 1; }
cd "$D" || exit 1
GV=$(go version -m "$H/essai" | awk 'NR == 1 {print $2}'); AM=${GV#go}
echo "version de Go du binaire d essai : $GV"
fabriquer() { # sortie paquet version licence [binaire]
  python3 -I - "$@" <<'EOP'
import io, sys, tarfile
out, pq, ver, lic = sys.argv[1:5]
binp = sys.argv[5] if len(sys.argv) > 5 else None
en = "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n"
if lic == "suite":    # Copyright et Files dont la valeur commence à la ligne suivante (DEP-5 valide)
    cr = en + "\nFiles:\n *\nCopyright:\n 2009 The Go Authors\nLicense: BSD-3-clause\n texte\n"
elif lic == "deux":   # deux défauts distincts dans deux paragraphes
    cr = en + "\nFiles: *\nCopyright: 2026 x\nLicense: GPL-2+ with Autoconf exception\n\nFiles: a/*\nCopyright: 2026 y\nLicense: Inconnue\n"
else:
    cr = en + f"\nFiles: *\nCopyright: 2026 x\nLicense: {lic}\n texte\n"
cr = cr.encode()
def tarxz(e):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:xz") as t:
        for nom, data in e:
            ti = tarfile.TarInfo(nom); ti.size = len(data); t.addfile(ti, io.BytesIO(data))
    return b.getvalue()
ctl = tarxz([("./control", f"Package: {pq}\nVersion: {ver}\nArchitecture: {'amd64' if binp else 'all'}\n".encode())])
e = [(f"./usr/share/doc/{pq}/copyright", cr)] + ([("./usr/bin/" + pq, open(binp, "rb").read())] if binp else [])
data = tarxz(e)
o = b"!<arch>\n"
for n, d in [("debian-binary", b"2.0\n"), ("control.tar.xz", ctl), ("data.tar.xz", data)]:
    o += f"{n:<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(d):<10}".encode() + b"`\n" + d + (b"\n" if len(d) & 1 else b"")
open(out, "wb").write(o)
EOP
}
fabriquer "$H/app.deb" essai 1.0-1 Apache-2.0 "$H/essai"
essai() { # cas paquet version licence code-attendu motif-attendu
  local cas=$1 src=$H/$1-src.deb s1 s2 rc
  fabriquer "$src" "$2" "$3" "$4"
  s1=$(sha256sum < "$H/app.deb" | cut -c1-64); s2=$(sha256sum < "$src" | cut -c1-64)
  printf '%s %s all %s 1 pool/main/g/x/%s.deb\n' "$2" "$3" "$s2" "$2" > "$H/verrou.txt"
  printf 'Installed-Build-Depends:\n %s (= %s),\n' "$2" "$3" > "$H/bi.txt"
  sed -e "s#^DEB_SHA=.*#DEB_SHA=$s1#" -e "s#^SRC_SHA=[^ ]*#SRC_SHA=$s2#" -e "s#^SRC_BI=\"[^\"]*\"#SRC_BI=\"$2 (= $3)\"#" \
      -e "s#^R=\$here/resultats\$#R=$H/res#" -e "s#^here=.*#here=$B#" -e "s#^T=.*#T=$H/travail#" \
      -e "s#\"\$repo/poc/packaging/verrou-deb.txt\"#\"$H/verrou.txt\"#" \
      -e "s#\"\$repo/poc/bricks/06-deb-sbuild/resultats/s3-build-1.buildinfo\"#\"$H/bi.txt\"#" "$B/paquets.sh" > "$H/paquets.sh"
  [ "$(grep -c -e "^DEB_SHA=$s1" -e "^SRC_SHA=$s2 " -e "^SRC_BI=\"$2 (= $3)\"" -e "^R=$H/res" -e "^here=$B" -e "^T=$H/travail" -e "\"$H/verrou.txt\"" -e "\"$H/bi.txt\"" "$H/paquets.sh")" = 8 ] \
    || { echo "KO   banc : substitutions ($cas)"; exit 1; }
  rc=0; DEB=$H/app.deb SRC=$src bash "$H/paquets.sh" stdlib > "$H/$cas.log" 2>&1 || rc=$?
  if [ "$rc" = "$5" ] && grep -qE -- "$6" "$H/$cas.log" && ! grep -q '^Traceback' "$H/$cas.log"; then echo "OK   $cas : code $rc, « $6 »"
  else echo "KO   $cas : code $rc (attendu $5), motif « $6 »"; fi
  grep -E '^(OK|KO|REFUS|bilan|binaire|paquet de|pkg:|licences\.py|Files|format)|^ +(ok|error|warning) ' "$H/$cas.log" | sed "s#$H#<banc>#g; s/^/     /"
}
essai s-nominal golang-1.24-src "$AM-1" BSD-3-clause 0 '^bilan : bibliothèque standard déclarée'
essai s-epoque golang-1.24-src "2:$AM-1" BSD-3-clause 0 '^OK   go.* = version amont'
essai s-version golang-1.24-src 1.24.0-1 BSD-3-clause 1 '^REFUS : version amont 1.24.0 du paquet'
essai s-nom golang-src "$AM-1" BSD-3-clause 1 "^REFUS : golang-src n'est pas un paquet golang-X.Y-src"
essai s-expat golang-1.24-src "$AM-1" Expat 1 '^KO   verdict non conforme'
essai s-suite golang-1.24-src "$AM-1" suite 0 '^bilan : bibliothèque standard déclarée'
essai s-deux golang-1.24-src "$AM-1" deux 1 '^REFUS : 2 défaut\(s\) : .*« with » non traité.*texte de licence absent pour Inconnue'
echo "chrono.tsv du banc : $(wc -l < "$H/res/chrono.tsv") lignes ; fichiers de 13a touchés : $(git -C "$D" status --porcelain -- poc/bricks/13a-licences/resultats/chrono.tsv poc/bricks/13a-licences/resultats/paquets-stdlib.log poc/bricks/13a-licences/resultats/paquets-stdlib.licences.json | wc -l)"
