#!/usr/bin/env bash
# Banc hors réseau de l étape deb de paquets.sh (12/11/2026) : debs SYNTHÉTIQUES fabriqués ici (ar et tar.xz par python3), copie
# de paquets.sh avec DEB_SHA et R remplacés (rien n est écrit dans resultats/ ni dans chrono.tsv de 13a). Le vrai deb n est pas lu.
# Usage : mise exec -- bash poc/bricks/13a-licences/resultats/paquets-essai-local.sh
set -uo pipefail
export LC_ALL=C
D=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
B=$D/poc/bricks/13a-licences
H=$(mktemp -d "$HOME/.cache/supply-chain-poc/13a-essai.XXXXXX")
trap 'rm -rf -- "${H:?}"' EXIT
mkdir -p "$H/res"
fabriquer() { # sortie cas : deb synthétique
  python3 -I - "$1" "$2" "$D/poc/packaging/debian/copyright" <<'EOP'
import io, sys, tarfile
out, cas, vrai = sys.argv[1:4]
def tarxz(entrees):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:xz") as t:
        for nom, data, lien in entrees:
            ti = tarfile.TarInfo(nom)
            if lien:
                ti.type, ti.linkname = tarfile.SYMTYPE, lien
                t.addfile(ti)
            else:
                ti.size = len(data); t.addfile(ti, io.BytesIO(data))
    return b.getvalue()
def ar(membres):
    o = b"!<arch>\n"
    for nom, data in membres:
        o += f"{nom:<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}".encode() + b"`\n" + data + (b"\n" if len(data) & 1 else b"")
    return o
cr = open(vrai, "rb").read()
if cas == "gpl":
    cr = b"Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n\nFiles: *\nCopyright: 2026 x\nLicense: GPL-3.0-or-later\n texte\n"
ctl = tarxz([("./control", b"Package: sample-app\nVersion: 1.0.0-1\nArchitecture: amd64\n", None)])
doc = [("./usr/share/doc/sample-app/copyright", cr, None)] if cas != "lien" else [("./usr/share/doc/sample-app/copyright", b"", "../../../../etc/passwd")]
if cas == "sans-copyright":
    doc = [("./usr/share/doc/sample-app/changelog.gz", b"x", None)]
data = tarxz(doc + [("./usr/bin/sample-app", b"binaire", None)])
m = [("debian-binary", b"2.0\n"), ("control.tar.xz", ctl), ("data.tar.zst" if cas == "zst" else "data.tar.xz", data)]
if cas == "membre-en-plus":
    m.append(("_gpgbuilder", b"x"))
open(out, "wb").write(ar(m))
EOP
}
essai() { # cas code-attendu [expression sed en plus] : étape deb sur le deb synthétique du cas
  local cas=$1 attendu=$2 plus=${3:-} deb=$H/$1.deb s rc
  fabriquer "$deb" "$cas"
  s=$(sha256sum < "$deb" | cut -c1-64)
  [ "$cas" = "sha-faux" ] && s=0000000000000000000000000000000000000000000000000000000000000000
  sed -e "s#^DEB_SHA=.*#DEB_SHA=$s#" -e "s#^R=\$here/resultats\$#R=$H/res#" -e "s#^here=.*#here=$B#" \
      -e "s#^T=.*#T=$H/travail#" ${plus:+-e "$plus"} "$B/paquets.sh" > "$H/paquets.sh"
  [ "$(grep -c -e "^DEB_SHA=$s" -e "^R=$H/res" -e "^here=$B" -e "^T=$H/travail" "$H/paquets.sh")" = 4 ] || { echo "KO   banc : substitutions"; exit 1; }
  [ -z "$plus" ] || ! cmp -s <(sed -e "s#^DEB_SHA=.*#DEB_SHA=$s#" -e "s#^R=\$here/resultats\$#R=$H/res#" -e "s#^here=.*#here=$B#" -e "s#^T=.*#T=$H/travail#" "$B/paquets.sh") "$H/paquets.sh" \
    || { echo "KO   banc : substitution du cas $cas sans effet"; exit 1; }
  rc=0; DEB=$deb bash "$H/paquets.sh" deb > "$H/$cas.log" 2>&1 || rc=$?
  if [ "$rc" = "$attendu" ]; then echo "OK   $cas : code $rc"; else echo "KO   $cas : code $rc, attendu $attendu"; fi
  grep -E '^(OK|KO|ÉCART|REFUS|bilan|expression|Files|format|licences\.py)' "$H/$cas.log" | sed "s#$H#<banc>#g; s/^/     /"
}
echo "# banc paquets.sh deb, $(date -u +%FT%TZ), paquets.sh $(sha256sum < "$B/paquets.sh" | cut -c1-64), paquets.py $(sha256sum < "$B/paquets.py" | cut -c1-64)"
essai nominal 0
essai gpl 1
essai lien 1
essai sans-copyright 1
essai zst 1
essai membre-en-plus 1
essai sha-faux 1
# témoins en échec pour une autre raison : trace python de paquets.py (mode dep5 seul), puis motif attendu changé : KO exigé
printf 'import runpy, sys\nif sys.argv[1] == "dep5":\n    raise RuntimeError("panne simulee")\nrunpy.run_path("%s", run_name="__main__")\n' "$B/paquets.py" > "$H/casse.py"
essai temoin-trace 1 "s#\"\$here/paquets.py\" dep5#\"$H/casse.py\" dep5#"
essai temoin-motif 1 "s#^t-expat|politique|identifiant SPDX inconnu : Expat\$#t-expat|politique|motif qui n existe pas#"
echo "chrono.tsv du banc : $(wc -l < "$H/res/chrono.tsv") lignes ; resultats/ de 13a : $(git -C "$D" status --porcelain -- poc/bricks/13a-licences/resultats/chrono.tsv poc/bricks/13a-licences/resultats/paquets-deb.log poc/bricks/13a-licences/resultats/paquets-deb.licences.json | wc -l) fichier(s) touchés"
