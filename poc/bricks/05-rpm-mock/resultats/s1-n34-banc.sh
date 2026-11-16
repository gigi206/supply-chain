#!/usr/bin/env bash
# Banc hors réseau de l'ajout N3 et N4 de la brique 05 (s1-n34.patch, n34-binaire.py), écrit le 16/11/2026 avant tout passage.
# Ni cluster, ni Zot, ni réseau. Données lourdes sous ~/.cache (pas sous /tmp).
# A : n34-binaire.py (python3 de l'hôte ; le pod aura 3.9) sur des archives newc faites par le cpio de l'hôte autour du binaire du
#     deb 1.0.0-1 de la 06 (sha256 épinglé, le même que x11-fichiers.sh de la 13a) : sortie comparée à x11-fichiers.log, et refus.
# B : SONDE_N34, extraite de la copie modifiée de s1.sh, sous bash, avec rpm et rpm2cpio simulés et /w remplacé par un dossier.
# C : rapatrier_rpms, extraite de même, sous set -euo pipefail, avec kubectl simulé.
# Non couvert : vrai rpm (format de --qf, nom des membres de rpm2cpio, charge zstd), python3 3.9 réel, vrai kubectl exec.
# Usage : banc-n34.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier de travail, vidé>
set -uo pipefail
export LC_ALL=C
D=$1; S1=$2; B=$3
rm -rf -- "${B:?}"; mkdir -p "$B"
echo "# banc-n34.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), python3 $(python3 -I -c 'import sys; print(sys.version.split()[0])'), $(cpio --version | head -1)"
echo "# n34-binaire.py $(sha256sum < "$D/poc/bricks/05-rpm-mock/n34-binaire.py" | cut -c1-64) ; copie de s1.sh $(sha256sum < "$S1" | cut -c1-64)"
ko=0
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
P="python3 -I $D/poc/bricks/05-rpm-mock/n34-binaire.py"
DEB=$HOME/.cache/supply-chain-poc/06/s6a/fichier/sample-app_1.0.0-1_amd64.deb
X11=$D/poc/bricks/13a-licences/resultats/x11-fichiers.log

echo "## A : n34-binaire.py"
python3 -I - "$DEB" 0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5 "$B/sample-app" <<'EOF'
import hashlib, io, sys, tarfile
deb, dsha, out = sys.argv[1:4]
bd = open(deb, "rb").read()
assert hashlib.sha256(bd).hexdigest() == dsha, "sha256 deb"
k, data = 8, None
while k < len(bd):
    h = bd[k:k + 60]; n = h[:16].decode().strip(); t = int(h[48:58])
    if n == "data.tar.xz":
        data = bd[k + 60:k + 60 + t]
    k += 60 + t + (t & 1)
open(out, "wb").write(tarfile.open(fileobj=io.BytesIO(data), mode="r:xz").extractfile("./usr/bin/sample-app").read())
EOF
python3 -I - "$D/poc/packaging/sample-app.spec" "$B/golang-NOTICES" <<'EOF'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^cat > golang-NOTICES <<'FIN_GOLANG_NOTICES'\n(.*?)^FIN_GOLANG_NOTICES$", s, re.S | re.M)
open(sys.argv[2], "wb").write(m.group(1).encode("utf-8"))
EOF
grep -q 'runtime/memmove_amd64.s' "$B/golang-NOTICES" && ok "golang-NOTICES du spec contient runtime/memmove_amd64.s (raison de l'isolement)" || nok "NOTICES"
arbre() { # dossier binaire : arbre ./usr/bin/sample-app et ./usr/share/licenses/sample-app/golang-NOTICES
  mkdir -p "$1/usr/bin" "$1/usr/share/licenses/sample-app"; cp "$2" "$1/usr/bin/sample-app"; cp "$B/golang-NOTICES" "$1/usr/share/licenses/sample-app/"
}
arbre "$B/t1" "$B/sample-app"
(cd "$B/t1" && printf '%s\n' ./usr ./usr/share ./usr/share/licenses ./usr/share/licenses/sample-app ./usr/share/licenses/sample-app/golang-NOTICES ./usr/bin ./usr/bin/sample-app | cpio -o -H newc --quiet > "$B/nominal.cpio")
attendu=$(sed -n '/^binaire : /,/^témoin négatif/p' "$X11")
[ "$(wc -l <<<"$attendu")" = 12 ] || nok "lignes attendues de x11-fichiers.log : $(wc -l <<<"$attendu")"
cas_a() { # libellé archive code-attendu motif-attendu (vide : sortie égale à x11-fichiers.log)
  local out rc; out=$($P "$2" 2>&1); rc=$?
  if [ -z "$4" ]; then
    [ "$rc" = "$3" ] && [ "$out" = "$attendu" ] && ok "$1 : code $rc, sortie égale aux lignes binaire à témoin négatif de x11-fichiers.log" \
      || { nok "$1 : code $rc"; diff <(echo "$attendu") <(echo "$out") | head -5; }
  else
    [ "$rc" = "$3" ] && grep -q -- "$4" <<<"$out" && ok "$1 : code $rc, « $(grep -m1 -- "$4" <<<"$out" | cut -c1-110) »" || nok "$1 : code $rc, $(head -c 200 <<<"$out")"
  fi
}
cas_a "A1 archive de GNU cpio (noms écrits sans ./, vérifié par cpio -t)" "$B/nominal.cpio" 0 ""
[ "$(cpio -t --quiet < "$B/nominal.cpio" | tail -1)" = usr/bin/sample-app ] && ok "A1 noms de GNU cpio sans ./" || nok "A1 noms"
python3 -I - "$B/nominal.cpio" "$B/point.cpio" <<'FIN'
import sys
a = open(sys.argv[1], "rb").read(); o = bytearray(); k = 0
while True:  # réécriture : chaque nom préfixé par « ./ » (sauf TRAILER!!!), namesize et bourrages recalculés
    h = a[k:k + 110]; t = int(h[54:62], 16); nl = int(h[94:102], 16); nom = a[k + 110:k + 110 + nl - 1]
    d0 = k + ((110 + nl + 3) & ~3); data = a[d0:d0 + t]
    n2 = nom if nom == b"TRAILER!!!" else b"./" + nom
    hh = h[:94] + b"%08X" % (len(n2) + 1) + h[102:110]
    e = hh + n2 + b"\0"; e += b"\0" * (-len(e) % 4); e += data; e += b"\0" * (-len(e) % 4); o += e
    if nom == b"TRAILER!!!":
        break
    k = (d0 + t + 3) & ~3
open(sys.argv[2], "wb").write(bytes(o))
FIN
[ "$(cpio -t --quiet < "$B/point.cpio" | tail -1)" = ./usr/bin/sample-app ] && ok "A1b archive réécrite lue par GNU cpio, noms en ./" || nok "A1b réécriture"
cas_a "A1b noms en ./ (forme supposée de rpm2cpio, non vérifiée)" "$B/point.cpio" 0 ""
(cd "$B/t1" && printf '%s\n' usr/share/licenses/sample-app/golang-NOTICES usr/bin/sample-app | cpio -o -H newc --quiet > "$B/sans-point.cpio")
cas_a "A2 noms sans ./" "$B/sans-point.cpio" 0 ""
printf 'pas un binaire de Go\n' > "$B/faux-binaire"; arbre "$B/t3" "$B/faux-binaire"
(cd "$B/t3" && printf '%s\n' ./usr/share/licenses/sample-app/golang-NOTICES ./usr/bin/sample-app | cpio -o -H newc --quiet > "$B/isole.cpio")
cas_a "A3 isolement (NOTICES porte la chaîne, pas le binaire)" "$B/isole.cpio" 0 "memmove_amd64.s        : absent "
head -c 3000000 "$B/nominal.cpio" > "$B/tronque.cpio"
cas_a "A4 archive tronquée" "$B/tronque.cpio" 1 "KO   archive tronquée dans usr/bin/sample-app"
(cd "$B/t1" && printf '%s\n' ./usr/share/licenses/sample-app/golang-NOTICES | cpio -o -H newc --quiet > "$B/absent.cpio")
cas_a "A5 membre absent" "$B/absent.cpio" 1 "KO   usr/bin/sample-app absent de l'archive"
{ printf 'XXXXXX'; tail -c +7 "$B/nominal.cpio"; } > "$B/magie.cpio"
cas_a "A6 magie fausse" "$B/magie.cpio" 1 "KO   en-tête cpio illisible à l'octet 0"
mkdir -p "$B/t7/usr/bin"; cp "$B/sample-app" "$B/t7/usr/bin/sample-app"; ln "$B/t7/usr/bin/sample-app" "$B/t7/usr/bin/autre"
(cd "$B/t7" && printf '%s\n' ./usr/bin/sample-app ./usr/bin/autre | cpio -o -H newc --quiet > "$B/lien.cpio")
cas_a "A7 lien dur, données sur le dernier lien" "$B/lien.cpio" 1 "KO   usr/bin/sample-app vide"
python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), feature_version=(3, 9))' "$D/poc/bricks/05-rpm-mock/n34-binaire.py" \
  && ok "A8 syntaxe acceptée par ast en version 3.9 (contrôle partiel : pas un python 3.9 réel)" || nok "A8 syntaxe 3.9"

echo "## B : SONDE_N34 (bash, rpm et rpm2cpio simulés)"
W=$B/w; mkdir -p "$W/n34" "$W/res-nspawn" "$W/res-simple" "$B/faux"
cp "$D/poc/bricks/05-rpm-mock/n34-binaire.py" "$W/n34/"
python3 -I - "$S1" "$B/sonde.sh" "$W" <<'EOF'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^SONDE_N34='(.*?\ntrue)'$", s, re.S | re.M)
assert m and "'" not in m.group(1)
open(sys.argv[2], "w", encoding="utf-8").write(m.group(1).replace("/w/", sys.argv[3] + "/"))
EOF
cat > "$B/faux/rpm" <<'EOF'
#!/usr/bin/env bash
q=$3
case $q in
  *FILEDIGESTALGO*) printf 8 ;;
  *FILEFLAGS*) printf '%s\n' "0 /usr/bin/sample-app aaaa" "128 /usr/share/licenses/sample-app/golang-LICENSE 911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad" \
                 "130 /usr/share/licenses/sample-app/golang-PATENTS bbbb" "x1 /usr/share/licenses/sample-app/illisible cccc" "0 /usr/share/licenses/sample-app " ;;
  *BUILDTIME*) printf 'buildtime 1763294400 ; changelogtime 1763294400' ;;
  *FILEMTIMES*) printf '%s\n' 1763294400 1763294400 999999999 1700000000 ;;
esac
EOF
printf '#!/usr/bin/env bash\ncat %q\n' "$B/nominal.cpio" > "$B/faux/rpm2cpio"
chmod +x "$B/faux/rpm" "$B/faux/rpm2cpio"
: > "$W/res-nspawn/sample-app-1.0.0-2.el9.x86_64.rpm"; : > "$W/res-nspawn/sample-app-debuginfo-1.0.0-2.el9.x86_64.rpm"
: > "$W/res-simple/sample-app-1.0.0-2.el9.x86_64.rpm"; : > "$W/res-simple/sample-app-1.0.0-3.el9.x86_64.rpm"
out=$(PATH=$B/faux:$PATH bash -s < "$B/sonde.sh" 2>&1); rc=$?
echo "$out" | sed 's/^/     /'
[ "$rc" = 0 ] && ok "B1 code 0" || nok "B1 code $rc"
for l in "rpm binaire de sample-app (nspawn) : 1 fichier(s)" "algorithme des empreintes de fichiers : 8" "rpm -qp, fichiers : rc 0, 5 ligne(s)" \
         "licence : /usr/share/licenses/sample-app/golang-LICENSE ; drapeaux 128 ; bit 128 : 1 ; empreinte 911f8f57" \
         "licence : /usr/share/licenses/sample-app/golang-PATENTS ; drapeaux 130 ; bit 128 : 1" "licence, ligne illisible : x1 /usr/share/licenses/sample-app/illisible cccc" \
         "licence : /usr/share/licenses/sample-app ; drapeaux 0 ; bit 128 : 0 ; empreinte aucune" \
         "dates : buildtime 1763294400 ; changelogtime 1763294400" "mtime des fichiers : 3 valeur(s) distincte(s), min 999999999, max 1763294400" \
         "n34-binaire.py : rc 0" "memmove_amd64.s        : PRÉSENT" "rpm binaire de sample-app (simple) : 2 fichier(s)" "plusieurs rpm binaires : lecture non faite"; do
  grep -q -F -- "$l" <<<"$out" && ok "B1 « $l »" || nok "B1 ligne absente : « $l »"
done
[ ! -e "$W/n34/charge-nspawn.cpio" ] && ok "B1 charge cpio effacée après lecture" || nok "B1 charge cpio restée"
rm -f "$W"/res-nspawn/* "$W"/res-simple/*
out=$(PATH=$B/faux:$PATH bash -s < "$B/sonde.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q -F "rpm binaire de sample-app (nspawn) : aucun" <<<"$out" && grep -q -F "rpm binaire de sample-app (simple) : aucun" <<<"$out" \
  && ok "B2 aucun rpm : code 0, « aucun » pour les deux isolations" || nok "B2 code $rc : $out"
: > "$W/res-simple/sample-app-1.0.0-2.el9.x86_64.rpm"
printf '#!/usr/bin/env bash\necho "erreur simulée" >&2; exit 1\n' > "$B/faux/rpm2cpio"
out=$(PATH=$B/faux:$PATH bash -s < "$B/sonde.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q -F "rpm2cpio : rc 1, 0 octets" <<<"$out" && grep -q -F "n34-binaire.py : rc 1" <<<"$out" \
  && ok "B3 rpm2cpio en échec : code 0, rc 1 affichés, n34-binaire.py en KO sans arrêter la sonde" || nok "B3 code $rc : $(tail -5 <<<"$out")"

echo "## C : rapatrier_rpms (set -euo pipefail, kubectl simulé)"
python3 -I - "$S1" "$B/fonction.sh" <<'EOF'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^rapatrier_rpms\(\) \{.*?^\}$", s, re.S | re.M)
open(sys.argv[2], "w", encoding="utf-8").write(m.group(0) + "\n")
EOF
cat > "$B/faux/kubectl" <<EOF
#!/usr/bin/env bash
[ "\$4" = absent ] && { echo "pod absent" >&2; exit 1; }
shift 5
a=(); for x in "\$@"; do a+=("\${x//\/w\//$W/}"); done
exec "\${a[@]}"
EOF
chmod +x "$B/faux/kubectl"
rm -f "$W"/res-nspawn/* "$W"/res-simple/*
printf 'contenu nspawn\n' > "$W/res-nspawn/sample-app-1.0.0-2.el9.x86_64.rpm"
printf 'contenu debuginfo\n' > "$W/res-nspawn/sample-app-debuginfo-1.0.0-2.el9.x86_64.rpm"
printf 'contenu simple\n' > "$W/res-simple/sample-app-1.0.0-2.el9.x86_64.rpm"
T=$B/T; mkdir -p "$T"
{ echo "rpm nspawn : sample-app-1.0.0-2.el9.x86_64.rpm $(printf 'contenu nspawn\n' | sha256sum | cut -c1-64)"
  echo "rpm nspawn : sample-app-debuginfo-1.0.0-2.el9.x86_64.rpm $(printf 'x\n' | sha256sum | cut -c1-64)"
  echo "rpm simple : sample-app-1.0.0-2.el9.x86_64.rpm $(printf 'autre contenu\n' | sha256sum | cut -c1-64)"; } > "$T/essais.log"
out=$(PATH=$B/faux:$PATH T=$T bash -c 'set -euo pipefail; . "$1"; rapatrier_rpms s1-05-essais; echo "fin atteinte"' _ "$B/fonction.sh" 2>&1); rc=$?
echo "$out" | sed 's/^/     /'
[ "$rc" = 0 ] && grep -q "^fin atteinte$" <<<"$out" && ok "C1 code 0, fin atteinte" || nok "C1 code $rc"
grep -q "^OK   rpm nspawn rapatrié : sample-app-1.0.0-2.el9.x86_64.rpm " <<<"$out" && ok "C1 nspawn : sha256 égal à la sonde" || nok "C1 nspawn"
grep -q "^ÉCART rpm simple rapatrié : sample-app-1.0.0-2.el9.x86_64.rpm .* (sonde : [0-9a-f]\{64\})$" <<<"$out" && ok "C1 simple : écart signalé, sans arrêt" || nok "C1 simple"
! grep -q debuginfo <<<"$out" && ok "C1 debuginfo ignoré" || nok "C1 debuginfo"
cmp -s "$T/rpm-nspawn/sample-app-1.0.0-2.el9.x86_64.rpm" "$W/res-nspawn/sample-app-1.0.0-2.el9.x86_64.rpm" && ok "C1 copie à l'octet près" || nok "C1 copie"
out=$(PATH=$B/faux:$PATH T=$T bash -c 'set -euo pipefail; . "$1"; rapatrier_rpms absent; echo "fin atteinte"' _ "$B/fonction.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "^fin atteinte$" <<<"$out" && ok "C2 pod absent : code 0, fin atteinte, rien copié ($(grep -c . <<<"$out") ligne(s))" || nok "C2 code $rc : $out"
echo "# bilan : $([ $ko = 0 ] && echo tenu || echo 'NON TENU'), fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
exit $ko
