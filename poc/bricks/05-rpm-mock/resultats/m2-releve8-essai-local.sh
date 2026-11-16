#!/usr/bin/env bash
# Essai hors réseau de releve8 (m2.sh), écrit le 16/11/2026 avant tout passage. commun.sh remplacé par un lancer() qui appelle
# etape_<nom> ; HOME isolé ; m2.sh et s1.sh copiés dans un arbre d'essai (p/bricks/05-rpm-mock), s1.sh avec FP_ROCKY remplacé par
# l'empreinte d'une clé d'essai jetable (gpg, sans phrase de passe, effacée à la fin) ; _buildenv de build-1/rocky_9 copié tel
# quel du dépôt ; curl simulé : chaque URL est servie depuis un dossier de pages, 404 sinon. gpg et gpgv sont les vrais.
# Cas : nominal (dont license.go dans golang-src, qui ne doit pas être retenu) ; plusieurs versions (1.25.10 au-dessus de 1.25.9 : comparaison non lexicale) ; signature d'AppStream fausse ;
# somme du filelists fausse ; zéro entrée filelists ; deux entrées filelists ; aucun paquet golang ; empreinte de clé
# différente ; paquet du primary absent du filelists. Le primary et le filelists d'AppStream sont en .xz, les autres en .gz.
# python3 du banc : l'interpréteur réel, lié dans bin/ avant le changement de HOME.
# Non couvert : vrais formats des repomd, primary et filelists de Rocky ; redirections ; réseau ; curl lui-même en échec ; un
# code HTTP autre que 200 et 404 ; .bz2 ; le vrai lancer (sous-shell d'un tube, journal, chrono.tsv).
# Usage : m2-releve8-essai-local.sh <racine du dépôt> <dossier vidé>
set -u
D=$1; H=$2
rm -rf -- "${H:?}"
B=$H/p/bricks/05-rpm-mock
mkdir -p "$H/bin" "$H/home" "$B/resultats" "$H/p/benchmarks/obs/resultats/build-1/rocky_9"
mkdir -m 700 "$H/gk"; export GNUPGHOME=$H/gk H
G=(gpg --batch --quiet --pinentry-mode loopback --passphrase '')
"${G[@]}" --quick-gen-key 'essai <essai@essai.test>' ed25519 sign never 2>/dev/null
"${G[@]}" --quick-gen-key 'autre <autre@essai.test>' ed25519 sign never 2>/dev/null
FP=$(gpg --batch --with-colons --list-keys 'essai@essai.test' 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
FA=$(gpg --batch --with-colons --list-keys 'autre@essai.test' 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
gpg --batch --armor --export "$FP" > "$H/cle.asc"; gpg --batch --armor --export "$FA" > "$H/autre.asc"
echo "clés d'essai : $(printf '%s\n' "$FP" "$FA" | grep -c -E '^[0-9A-F]{40}$') empreintes de 40 caractères"

printf 'R=%s\nlancer() { "etape_$3"; }\n' "$B/resultats" > "$H/commun.sh"
sed -e "s#^\. \"\$here/../08-trust-plane/commun.sh\"\$#. $H/commun.sh#" "$D/poc/bricks/05-rpm-mock/m2.sh" > "$B/m2.sh"
sed -e "s#^FP_ROCKY=[0-9A-F]\{40\} #FP_ROCKY=$FP #" "$D/poc/bricks/05-rpm-mock/s1.sh" > "$B/s1.sh"
cp "$D/poc/benchmarks/obs/resultats/build-1/rocky_9/_buildenv" "$H/p/benchmarks/obs/resultats/build-1/rocky_9/_buildenv"
grep -c "^\. $H/commun.sh\$" "$B/m2.sh" | sed 's/^/source remplacée : /'
grep -c "^FP_ROCKY=$FP " "$B/s1.sh" | sed 's/^/FP_ROCKY d essai : /'
V=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$B/s1.sh")
CLE=$(sed -n 's|^CLE_ROCKY=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$B/s1.sh")

cat > "$H/bin/curl" <<'EOF2'
#!/usr/bin/env bash
o=/dev/stdout; w=; u=${*: -1}
while [ $# -gt 0 ]; do case $1 in -o) o=$2; shift ;; -w) w=$2; shift ;; esac; shift; done
f=$H/web/$(printf %s "$u" | sha256sum | cut -c1-16)
if [ -f "$f" ]; then c=200; cp "$f" "$o"; else c=404; echo absent > "$o"; fi
[ -n "$w" ] && printf '%s' "$c"; exit 0
EOF2
chmod +x "$H/bin/curl"
ln -s "$(python3 -I -c 'import sys; print(sys.executable)')" "$H/bin/python3"

servir() { cp "$2" "$H/web/$(printf %s "$1" | sha256sum | cut -c1-16)"; }
depot() { # étiquette URL-de-base « nom|ver|rel|arch|sourcerpm|licence|provides,…|fichiers,… »… ; variables d'environnement :
          # FORMAT (gz, xz), FAUX_SHA_FL=1 (somme du filelists fausse), FL=0|2 (entrées filelists), SANS_FL=nom (paquet retiré du
          # filelists), FAUSSE_SIG=1 (autre contenu signé)
  local b=$2 r=$H/depots/$1 hp hf; shift 2
  mkdir -p "$r"
  read -r hp hf < <(python3 -I - "$r" "$@" <<'PY'
import gzip, hashlib, lzma, os, sys
o, pk = sys.argv[1], [s.split('|') for s in sys.argv[2:]]
z = os.environ.get('FORMAT', 'gz')
comp = lzma.compress if z == 'xz' else gzip.compress
x = ['<?xml version="1.0" encoding="UTF-8"?>',
     f'<metadata xmlns="http://linux.duke.edu/metadata/common" xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="{len(pk)}">']
y = ['<?xml version="1.0" encoding="UTF-8"?>', f'<filelists xmlns="http://linux.duke.edu/metadata/filelists" packages="{len(pk)}">']
for i, (nom, ver, rel, arch, srpm, lic, prov, fic) in enumerate(pk):
    e = ''.join(f'<rpm:entry name="{p}"/>' for p in [nom] + [q for q in prov.split(',') if q])
    x.append(f'<package type="rpm"><name>{nom}</name><arch>{arch}</arch><version epoch="0" ver="{ver}" rel="{rel}"/>'
             f'<format><rpm:license>{lic.replace("_", " ")}</rpm:license><rpm:sourcerpm>{srpm}</rpm:sourcerpm>'
             f'<rpm:provides>{e}</rpm:provides></format></package>')
    if nom != os.environ.get('SANS_FL'):
        f = ''.join(f'<file>{c}</file>' for c in fic.split(',') if c) + '<file type="dir">/usr/lib/golang</file>'
        y.append(f'<package pkgid="{i:064x}" name="{nom}" arch="{arch}"><version epoch="0" ver="{ver}" rel="{rel}"/>{f}</package>')
x.append('</metadata>'); y.append('</filelists>')
bp, bf = comp('\n'.join(x).encode()), comp('\n'.join(y).encode())
open(f'{o}/primary.xml.{z}', 'wb').write(bp); open(f'{o}/filelists.xml.{z}', 'wb').write(bf)
sp = hashlib.sha256(bp).hexdigest()
sf = '0' * 64 if os.environ.get('FAUX_SHA_FL') else hashlib.sha256(bf).hexdigest()
hp, hf = f'repodata/{sp[:8]}-primary.xml.{z}', f'repodata/{sf[:8]}-filelists.xml.{z}'
d = [f'<data type="primary"><checksum type="sha256">{sp}</checksum><location href="{hp}"/></data>']
d += [f'<data type="filelists"><checksum type="sha256">{sf}</checksum><location href="{hf}"/></data>'] * int(os.environ.get('FL', '1'))
with open(f'{o}/repomd.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<repomd xmlns="http://linux.duke.edu/metadata/repo">' + ''.join(d) + '</repomd>\n')
print(hp, hf)
PY
  )
  if [ -n "${FAUSSE_SIG:-}" ]; then echo autre > "$r/autre"; "${G[@]}" -u "$FP" --armor --detach-sign -o "$r/repomd.xml.asc" "$r/autre"
  else "${G[@]}" -u "$FP" --armor --detach-sign -o "$r/repomd.xml.asc" "$r/repomd.xml"; fi
  servir "$b/repodata/repomd.xml" "$r/repomd.xml"; servir "$b/repodata/repomd.xml.asc" "$r/repomd.xml.asc"
  servir "$b/$hp" "$r/primary.xml.${FORMAT:-gz}"; servir "$b/$hf" "$r/filelists.xml.${FORMAT:-gz}"
}
GO='golang|1.25.9|1.el9_7|x86_64|golang-1.25.9-1.el9_7.src.rpm|BSD_and_Public_Domain||/usr/bin/go,/usr/share/licenses/golang/LICENSE,/usr/share/licenses/golang/PATENTS'
BIN='golang-bin|1.25.9|1.el9_7|x86_64|golang-1.25.9-1.el9_7.src.rpm|BSD_and_Public_Domain||/usr/lib/golang/bin/go'
SRC='golang-src|1.25.9|1.el9_7|noarch|golang-1.25.9-1.el9_7.src.rpm|BSD_and_Public_Domain||/usr/lib/golang/src/vendor/golang.org/x/net/LICENSE,/usr/lib/golang/src/fmt/print.go,/usr/lib/golang/src/go/build/license.go,/usr/lib/golang/src/cmd/vendor/golang.org/x/mod/PATENTS'
VIEUX='golang|1.24.6|1.el9_6|x86_64|golang-1.24.6-1.el9_6.src.rpm|BSD_and_Public_Domain||/usr/bin/go,/usr/share/licenses/golang/LICENSE'
NEUF='golang|1.25.10|1.el9_7|x86_64|golang-1.25.10-1.el9_7.src.rpm|BSD_and_Public_Domain||/usr/bin/go,/usr/share/licenses/golang/LICENSE'
LEURRE='golang-github-x-y|1.0|1.el9|noarch|golang-github-x-y-1.0-1.el9.src.rpm|MIT||/usr/share/gocode/LICENSE'
monter() { # cas : pages servies pour ce cas
  rm -rf -- "${H:?}/web" "${H:?}/depots"; mkdir -p "$H/web" "$H/depots"
  if [ "$1" = cle ]; then servir "$CLE" "$H/autre.asc"; else servir "$CLE" "$H/cle.asc"; fi
  depot vault-BaseOS "$V/BaseOS/x86_64/os" 'bash|5.1.8|9.el9|x86_64|bash-5.1.8-9.el9.src.rpm|GPLv3+||/usr/bin/bash'
  depot vault-CRB "$V/CRB/x86_64/os" 'libfoo-devel|1.0|1.el9|x86_64|libfoo-1.0-1.el9.src.rpm|MIT||/usr/include/foo.h'
  case $1 in
    plusieurs) FORMAT=xz depot vault-AppStream "$V/AppStream/x86_64/os" "$GO" "$BIN" "$SRC" "$VIEUX" "$NEUF" "$LEURRE" ;;
    signature) FAUSSE_SIG=1 FORMAT=xz depot vault-AppStream "$V/AppStream/x86_64/os" "$GO" "$BIN" "$SRC" ;;
    somme) FAUX_SHA_FL=1 FORMAT=xz depot vault-AppStream "$V/AppStream/x86_64/os" "$GO" "$BIN" "$SRC" ;;
    zero) FL=0 FORMAT=xz depot vault-AppStream "$V/AppStream/x86_64/os" "$GO" "$BIN" "$SRC" ;;
    deux) FL=2 FORMAT=xz depot vault-AppStream "$V/AppStream/x86_64/os" "$GO" "$BIN" "$SRC" ;;
    absent) FORMAT=xz depot vault-AppStream "$V/AppStream/x86_64/os" "$LEURRE" 'nodejs|16.20|1.el9|x86_64|nodejs-16.20-1.el9.src.rpm|MIT||/usr/bin/node' ;;
    manque) SANS_FL=golang-src FORMAT=xz depot vault-AppStream "$V/AppStream/x86_64/os" "$GO" "$BIN" "$SRC" ;;
    *) FORMAT=xz depot vault-AppStream "$V/AppStream/x86_64/os" "$GO" "$BIN" "$SRC" "$VIEUX" "$LEURRE" ;;
  esac
}
cas() {
  echo "== cas $1"
  monter "$1"
  HOME=$H/home PATH=$H/bin:$PATH bash "$B/m2.sh" releve8 2>&1 | sed -e "s#$H#<essai>#g" -e "s#$FP#<empreinte d essai>#g" -e "s#$FA#<autre empreinte>#g"
  echo "code ${PIPESTATUS[0]}"
}
for c in nominal plusieurs signature somme zero deux absent cle manque; do cas $c; done
gpgconf --kill all 2>/dev/null || true
rm -rf -- "${H:?}"
