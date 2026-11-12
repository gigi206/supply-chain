#!/usr/bin/env bash
# Banc hors réseau de l étape modules de paquets.sh (12/11/2026). Un petit programme Go à une dépendance vendorisée est compilé ici
# (go de mise, GOPROXY=off, GOTOOLCHAIN=local, mêmes options que debian/rules) ; paquets.py doit lire les mêmes informations de
# build que « go version -m » ; puis l étape tourne, dans une copie de paquets.sh (DEB_SHA, R et T remplacés), sur des debs
# SYNTHÉTIQUES. Le vrai deb n est pas lu. Usage : mise exec -- bash poc/bricks/13a-licences/resultats/paquets-modules-essai-local.sh
set -uo pipefail
export LC_ALL=C
D=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
B=$D/poc/bricks/13a-licences
H=$(mktemp -d "$HOME/.cache/supply-chain-poc/13a-essai-m.XXXXXX")
trap 'chmod -R u+w -- "${H:?}" 2>/dev/null; rm -rf -- "${H:?}"' EXIT
mkdir -p "$H/res" "$H/src/vendor/example.com/dep"
echo "# banc paquets.sh modules, $(date -u +%FT%TZ), paquets.sh $(sha256sum < "$B/paquets.sh" | cut -c1-64), paquets.py $(sha256sum < "$B/paquets.py" | cut -c1-64), $(go version)"
cd "$H/src" || exit 1
printf 'module example.com/essai\n\ngo 1.24\n\nrequire example.com/dep v1.0.0\n' > go.mod
printf '# example.com/dep v1.0.0\n## explicit\nexample.com/dep\n' > vendor/modules.txt
printf 'package dep\n\nfunc Valeur() int { return 7 }\n' > vendor/example.com/dep/dep.go
printf 'package main\n\nimport (\n\t"fmt"\n\n\t"example.com/dep"\n)\n\nfunc main() { fmt.Println(dep.Valeur()) }\n' > main.go
GOPROXY=off GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS="-mod=vendor -buildvcs=false -trimpath" GOCACHE=$H/gocache GOPATH=$H/gopath \
  go build -ldflags "-s -w -buildid=" -o "$H/essai" . || { echo "KO   banc : go build"; exit 1; }
# second programme : dépendance vendorisée sous le nom de chi (code jetable, pas celui de chi), pour le témoin réel
mkdir -p "$H/src2/vendor/github.com/go-chi/chi/v5" && cd "$H/src2" || exit 1
printf 'module example.com/supply-chain/sample-app\n\ngo 1.24\n\nrequire github.com/go-chi/chi/v5 v5.2.3\n' > go.mod
printf '# github.com/go-chi/chi/v5 v5.2.3\n## explicit\ngithub.com/go-chi/chi/v5\n' > vendor/modules.txt
printf 'package chi\n\nfunc Valeur() int { return 5 }\n' > vendor/github.com/go-chi/chi/v5/chi.go
printf 'package main\n\nimport (\n\t"fmt"\n\n\tchi "github.com/go-chi/chi/v5"\n)\n\nvar Version string\n\nfunc main() { fmt.Println(chi.Valeur(), Version) }\n' > main.go
GOPROXY=off GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS="-mod=vendor -buildvcs=false -trimpath" GOCACHE=$H/gocache GOPATH=$H/gopath \
  go build -ldflags "-s -w -buildid= -X main.Version=1.0.0" -o "$H/essai-chi" . || { echo "KO   banc : go build (chi)"; exit 1; }
cd "$D" || exit 1
go version -m "$H/essai" > "$H/go-m.txt"
cp "$H/essai" "$H/double"; printf '\377 Go buildinf:' >> "$H/double"
printf '#!/bin/sh\necho pas du go\n' > "$H/script"
fabriquer() { # sortie binaire copyright-cas
  python3 -I - "$@" "$D/poc/packaging/debian/copyright" <<'EOP'
import io, sys, tarfile
out, binp, cas = sys.argv[1:4]
en = "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n\nFiles: *\nCopyright: 2026 x\nLicense: Apache-2.0\n texte\n"
dep = "\nFiles: vendor/example.com/dep/*\nCopyright: 2026 y\nLicense: MIT\n texte\n"
orph = "\nFiles: vendor/example.org/orpheline/*\nCopyright: 2026 z\nLicense: ISC\n texte\n"
cr = open(sys.argv[4], "rb").read() if cas == "depot" else {"avec-dep": en + dep, "sans-dep": en, "orpheline": en + dep + orph}[cas].encode()
def tarxz(e):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:xz") as t:
        for nom, data in e:
            ti = tarfile.TarInfo(nom); ti.size = len(data); t.addfile(ti, io.BytesIO(data))
    return b.getvalue()
ctl = tarxz([("./control", b"Package: essai\nVersion: 1.0-1\nArchitecture: amd64\n")])
data = tarxz([("./usr/bin/essai", open(binp, "rb").read()), ("./usr/share/doc/essai/copyright", cr)])
o = b"!<arch>\n"
for n, d in [("debian-binary", b"2.0\n"), ("control.tar.xz", ctl), ("data.tar.xz", data)]:
    o += f"{n:<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(d):<10}".encode() + b"`\n" + d + (b"\n" if len(d) & 1 else b"")
open(out, "wb").write(o)
EOP
}
echo "## lecture des informations de build : paquets.py contre go version -m"
fabriquer "$H/n.deb" "$H/essai" avec-dep
python3 -I "$B/paquets.py" modules "$H/n.deb" > "$H/n.out"; echo "paquets.py modules (nominal) : code $?"
a=$(awk '$1 == "dep" || $1 == "mod" || $1 == "path" {print $1, $2, $3}' "$H/go-m.txt" | sort)
b=$(awk '$1 == "dep" || $1 == "mod" || $1 == "path" {sub(":", "", $2); print $1, $3, $4}' "$H/n.out" | sed 's/ *$//' | sort)
a=$(printf '%s\n' "$a" | sed 's/ *$//')
[ "$a" = "$b" ] && echo "OK   path, mod et dep identiques à go version -m ($(printf '%s\n' "$a" | wc -l) lignes)" || { echo "KO   écart avec go version -m"; diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"); }
v=$(awk 'NR == 1 {print $2}' "$H/go-m.txt"); grep -qx "go : $v" "$H/n.out" && echo "OK   version de Go identique : $v" || echo "KO   version de Go : $(grep '^go : ' "$H/n.out")"
nb=$(grep -c '^build : ' "$H/n.out"); ng=$(grep -c $'^\tbuild\t' "$H/go-m.txt")
[ "$nb" = "$ng" ] && echo "OK   réglages de build : $nb, comme go version -m" || echo "KO   réglages de build : $nb contre $ng"
essai() { # cas binaire copyright code-attendu motif-attendu [garder : TEMOIN_DEP non remplacé]
  local cas=$1 deb=$H/$1.deb s rc td=example.com/dep
  [ "${6:-}" = garder ] && td=github.com/go-chi/chi/v5
  fabriquer "$deb" "$2" "$3"
  s=$(sha256sum < "$deb" | cut -c1-64)
  sed -e "s#^DEB_SHA=.*#DEB_SHA=$s#" -e "s#^R=\$here/resultats\$#R=$H/res#" -e "s#^here=.*#here=$B#" \
      -e "s#^T=.*#T=$H/travail#" -e "s#^TEMOIN_DEP=[^ ]*#TEMOIN_DEP=$td#" "$B/paquets.sh" > "$H/paquets.sh"
  [ "$(grep -c -e "^DEB_SHA=$s" -e "^R=$H/res" -e "^here=$B" -e "^T=$H/travail" -e "^TEMOIN_DEP=$td " "$H/paquets.sh")" = 5 ] || { echo "KO   banc : substitutions"; exit 1; }
  rc=0; DEB=$deb bash "$H/paquets.sh" modules > "$H/$cas.log" 2>&1 || rc=$?
  if [ "$rc" = "$4" ] && grep -qE -- "$5" "$H/$cas.log" && ! grep -q '^Traceback' "$H/$cas.log"; then echo "OK   $cas : code $rc, « $5 »"
  else echo "KO   $cas : code $rc (attendu $4), motif « $5 »"; fi
  grep -E '^(OK|KO|ÉCART|REFUS|bilan|go :|dep :|control)' "$H/$cas.log" | sed "s#$H#<banc>#g; s/^/     /"
}
echo "## étape modules sur debs synthétiques"
essai m-chi-depot "$H/essai-chi" depot 0 '^OK   témoin refusé : KO   dep github.com/go-chi/chi/v5 v5.2.3' garder
grep '^build : ' "$H/m-chi-depot.log" | sed 's/^/     /'
essai m-nominal "$H/essai" avec-dep 0 '^bilan : chaque dépendance compilée a son paragraphe Files'
essai m-sans-dep "$H/essai" sans-dep 1 '^KO   paquets.py modules'
essai m-orpheline "$H/essai" orpheline 0 '^ÉCART paragraphe Files vendor/example.org/orpheline'
essai m-script "$H/script" avec-dep 1 'REFUS : en-tête des informations de build : 0 occurrence'
essai m-double "$H/double" avec-dep 1 'REFUS : en-tête des informations de build : 2 occurrence'
echo "chrono.tsv du banc : $(wc -l < "$H/res/chrono.tsv") lignes ; fichiers de 13a touchés : $(git -C "$D" status --porcelain -- poc/bricks/13a-licences/resultats/chrono.tsv poc/bricks/13a-licences/resultats/paquets-modules.log | wc -l)"
