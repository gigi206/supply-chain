#!/usr/bin/env bash
# Essai hors réseau de releve9 (m2.sh), écrit le 16/11/2026 avant tout passage. commun.sh remplacé par un lancer() qui appelle
# etape_<nom> ; HOME isolé, où l'archive réelle du tag mock-6.9-1 est copiée (sha256 contrôlé par l'étape) ; m2.sh et s1.sh copiés
# dans un arbre d'essai (p/bricks/05-rpm-mock), s1.sh avec FP_ROCKY remplacé par l'empreinte d'une clé d'essai jetable (gpg, sans
# phrase de passe, effacée à la fin) ; _buildenv de build-1/rocky_9 copié tel quel du dépôt ; curl simulé : chaque URL est servie
# depuis un dossier de pages, 404 sinon ; go simulé : GOROOT d'essai (LICENSE et PATENTS synthétiques). gpg et gpgv sont les vrais.
# Le rpm golang est synthétique, fabriqué ici en Python selon la même structure écrite de mémoire que le lecteur de l'étape :
# le banc éprouve la logique et les refus, pas la conformité au vrai format rpm (que seul le vrai passage éprouve).
# Cas : nominal (charge xz, en-tête signé par la clé d'essai, LICENSE égale à la copie de comparaison) ; zstd (charge non lue,
# code 0) ; differente (LICENSE différente de la copie, code 0) ; sans_sig (pas de tag 268 : « non vérifiée », code 0) ; somme du
# rpm fausse ; magie du lead fausse ; en-tête tronqué ; nombre d'entrées de l'en-tête hors borne ; fichier de l'en-tête absent du
# filelists ; taille du primary hors borne ; LICENSE de la charge différente de l'empreinte de l'en-tête ; archive de mock
# altérée ; signature d'AppStream fausse ; release de l'en-tête différente du primary ; SHA256 de l'en-tête (signature) faux ;
# emplacement du rpm avec « .. » ; signature (tag 268) d'un autre contenu.
# python3 du banc : l'interpréteur réel, lié dans bin/ avant le changement de HOME.
# Non couvert : vrai rpm golang de Rocky (structure, tags 268, 273, 5092 et bits 2 et 128 éprouvés à part sur des rpm réels :
# m2-releve9-temoins.sh) ; ancre absente dans les sources de mock (l'archive réelle est la
# seule acceptée) ; redirections ; réseau ; le vrai lancer (sous-shell d'un tube, journal, chrono.tsv).
# Usage : m2-releve9-essai-local.sh <racine du dépôt> <dossier vidé>
set -u
D=$1; H=$2
rm -rf -- "${H:?}"
B=$H/p/bricks/05-rpm-mock
mkdir -p "$H/bin" "$H/home/.cache/supply-chain-poc/05/m2" "$B/resultats" "$H/p/benchmarks/obs/resultats/build-1/rocky_9" "$H/goroot"
mkdir -m 700 "$H/gk"; export GNUPGHOME=$H/gk H
G=(gpg --batch --quiet --pinentry-mode loopback --passphrase '')
"${G[@]}" --quick-gen-key 'essai <essai@essai.test>' ed25519 sign never 2>/dev/null
FP=$(gpg --batch --with-colons --list-keys 'essai@essai.test' 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
gpg --batch --armor --export "$FP" > "$H/cle.asc"
echo "clé d'essai : $(printf '%s\n' "$FP" | grep -c -E '^[0-9A-F]{40}$') empreinte de 40 caractères"

printf 'R=%s\nlancer() { "etape_$3"; }\n' "$B/resultats" > "$H/commun.sh"
sed -e "s#^\. \"\$here/../08-trust-plane/commun.sh\"\$#. $H/commun.sh#" "$D/poc/bricks/05-rpm-mock/m2.sh" > "$B/m2.sh"
sed -e "s#^FP_ROCKY=[0-9A-F]\{40\} #FP_ROCKY=$FP #" "$D/poc/bricks/05-rpm-mock/s1.sh" > "$B/s1.sh"
cp "$D/poc/benchmarks/obs/resultats/build-1/rocky_9/_buildenv" "$H/p/benchmarks/obs/resultats/build-1/rocky_9/_buildenv"
grep -c "^\. $H/commun.sh\$" "$B/m2.sh" | sed 's/^/source remplacée : /'
grep -c "^FP_ROCKY=$FP " "$B/s1.sh" | sed 's/^/FP_ROCKY d essai : /'
V=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$B/s1.sh")
CLE=$(sed -n 's|^CLE_ROCKY=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$B/s1.sh")
ARCH=$HOME/.cache/supply-chain-poc/05/m2/mock.tar.gz
printf 'Copyright essai\nlicence d essai\n' > "$H/goroot/LICENSE"; printf 'brevets d essai\n' > "$H/goroot/PATENTS"

cat > "$H/bin/curl" <<'EOF2'
#!/usr/bin/env bash
o=/dev/stdout; w=; u=${*: -1}
while [ $# -gt 0 ]; do case $1 in -o) o=$2; shift ;; -w) w=$2; shift ;; esac; shift; done
f=$H/web/$(printf %s "$u" | sha256sum | cut -c1-16)
if [ -f "$f" ]; then c=200; cp "$f" "$o"; else c=404; echo absent > "$o"; fi
[ -n "$w" ] && printf '%s' "$c"; exit 0
EOF2
cat > "$H/bin/go" <<'EOF2'
#!/usr/bin/env bash
case "$*" in "env GOROOT") echo "$H/goroot" ;; version) echo "go version go-essai linux/amd64" ;; *) exit 2 ;; esac
EOF2
chmod +x "$H/bin/curl" "$H/bin/go"
ln -s "$(python3 -I -c 'import sys; print(sys.executable)')" "$H/bin/python3"

servir() { cp "$2" "$H/web/$(printf %s "$1" | sha256sum | cut -c1-16)"; }
monter() { # cas : AppStream signé (primary et filelists en .gz), rpm golang synthétique, pages servies pour ce cas
  local r=$H/depot b=$V/AppStream/x86_64/os href hp hf hr
  rm -rf -- "${H:?}/web" "$r"; mkdir -p "$H/web" "$r"
  servir "$CLE" "$H/cle.asc"
  if [ "$1" = archive ]; then { cat "$ARCH"; echo x; } > "$H/home/.cache/supply-chain-poc/05/m2/mock.tar.gz"
  else cp "$ARCH" "$H/home/.cache/supply-chain-poc/05/m2/mock.tar.gz"; fi
  href=$(CAS=$1 FP=$FP python3 -I - "$r" "$H/goroot/LICENSE" <<'PY'
import gzip, hashlib, lzma, os, struct, subprocess, sys
o, ref = sys.argv[1:3]
cas = os.environ['CAS']
def entete(tags):
    idx, data = b'', b''
    for tag, typ, v in sorted(tags):
        while len(data) % {3: 2, 4: 4}.get(typ, 1):
            data += b'\0'
        ofs = len(data)
        if typ == 6:
            data += v.encode() + b'\0'; n = 1
        elif typ == 8:
            data += b''.join(s.encode() + b'\0' for s in v); n = len(v)
        elif typ == 4:
            data += struct.pack(f'>{len(v)}I', *v); n = len(v)
        elif typ == 3:
            data += struct.pack(f'>{len(v)}H', *v); n = len(v)
        elif typ == 7:
            data += v; n = len(v)
        idx += struct.pack('>IIII', tag, typ, ofs, n)
    il = len(tags) + {'tronque': 1000, 'borne': 100000}.get(cas, 0)
    return b'\x8e\xad\xe8\x01\0\0\0\0' + struct.pack('>II', il, len(data)) + idx + data
lic = open(ref, 'rb').read() if cas != 'differente' else b'Copyright autre\n'
pat = b'brevets d essai\n'
fichiers = [('/usr/bin/go', 0o100755, 0, b'binaire'), ('/usr/lib/golang', 0o40755, 0, b''),
            ('/usr/share/doc/golang', 0o40755, 0, b''),
            ('/usr/share/doc/golang/LICENSE', 0o100644, 2, lic), ('/usr/share/doc/golang/PATENTS', 0o100644, 2, pat)]
if cas == 'fichiers':
    fichiers.append(('/usr/lib/golang/VERSION', 0o100644, 0, b'go1.25.9'))
def cpio(fs):
    out, i = b'', 0
    for nm, mode, _, dat in fs + [('TRAILER!!!', 0, 0, b'')]:
        if cas == 'charge' and nm.endswith('/LICENSE'):
            dat = dat + b'altere\n'
        i += 1
        n = (('.' + nm) if nm != 'TRAILER!!!' else nm).encode() + b'\0'
        out += b'070701' + b''.join(b'%08X' % x for x in [i, mode, 0, 0, 1, 0, len(dat), 0, 0, 0, 0, len(n), 0]) + n
        out += b'\0' * (-len(out) % 4) + dat
        out += b'\0' * (-len(out) % 4)
    return out
charge = lzma.compress(cpio(fichiers), format=lzma.FORMAT_XZ) if cas != 'zstd' else b'(\xb5/\xfd' + os.urandom(64)
dirs = sorted({os.path.dirname(p) + '/' for p, *_ in fichiers})
tags = [(1000, 6, 'golang'), (1001, 6, '1.25.9'), (1002, 6, '2.el9_7' if cas == 'evr' else '1.el9_7'), (1022, 6, 'x86_64'),
        (1014, 6, 'BSD and Public Domain'), (1044, 6, 'golang-1.25.9-1.el9_7.src.rpm'), (1124, 6, 'cpio'),
        (1125, 6, 'zstd' if cas == 'zstd' else 'xz'), (1126, 6, '2'),
        (1116, 4, [dirs.index(os.path.dirname(p) + '/') for p, *_ in fichiers]),
        (1117, 8, [os.path.basename(p) for p, *_ in fichiers]), (1118, 8, dirs),
        (1030, 3, [m for _, m, _, _ in fichiers]), (1037, 4, [f for _, _, f, _ in fichiers]),
        (1035, 8, [hashlib.sha256(d).hexdigest() if m & 0o100000 else '' for _, m, _, d in fichiers]),
        (1028, 4, [len(d) for *_, d in fichiers]), (5011, 4, [8]),
        (5092, 8, [hashlib.sha256(charge).hexdigest()]), (5093, 4, [8])]
h = entete(tags)
sg = subprocess.run(['gpg', '--batch', '--quiet', '--pinentry-mode', 'loopback', '--passphrase', '', '-u', os.environ['FP'],
                     '--detach-sign', '-o', '-'], input=b'autre' if cas == 'sig_fausse' else h, capture_output=True, check=True).stdout
s = entete([(273, 6, '0' * 64 if cas == 'sha_entete' else hashlib.sha256(h).hexdigest())] + ([] if cas == 'sans_sig' else [(268, 7, sg)]))
s += b'\0' * (-(96 + len(s)) % 8)
lead = (b'\x00\x00\x00\x00' if cas == 'magie' else b'\xed\xab\xee\xdb') + b'\0' * 92
rpm = lead + s + h + charge
href = 'Packages/g/../golang-1.25.9-1.el9_7.x86_64.rpm' if cas == 'emplacement' else 'Packages/g/golang-1.25.9-1.el9_7.x86_64.rpm'
open(f'{o}/golang.rpm', 'wb').write(rpm)
sha = '0' * 64 if cas == 'somme' else hashlib.sha256(rpm).hexdigest()
taille = 64 * 1024 * 1024 + 1 if cas == 'taille' else len(rpm)
p = ['<?xml version="1.0" encoding="UTF-8"?>',
     '<metadata xmlns="http://linux.duke.edu/metadata/common" xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="2">',
     f'<package type="rpm"><name>golang</name><arch>x86_64</arch><version epoch="0" ver="1.25.9" rel="1.el9_7"/>'
     f'<checksum type="sha256" pkgid="YES">{sha}</checksum><size package="{taille}" installed="1" archive="1"/>'
     f'<location href="{href}"/><format><rpm:license>BSD and Public Domain</rpm:license>'
     f'<rpm:sourcerpm>golang-1.25.9-1.el9_7.src.rpm</rpm:sourcerpm><rpm:provides><rpm:entry name="golang"/></rpm:provides>'
     f'</format></package>',
     '<package type="rpm"><name>golang-bin</name><arch>x86_64</arch><version epoch="0" ver="1.25.9" rel="1.el9_7"/>'
     '<checksum type="sha256" pkgid="YES">' + 'a' * 64 + '</checksum><size package="10"/>'
     '<location href="Packages/g/golang-bin-1.25.9-1.el9_7.x86_64.rpm"/><format><rpm:license>BSD and Public Domain</rpm:license>'
     '<rpm:sourcerpm>golang-1.25.9-1.el9_7.src.rpm</rpm:sourcerpm></format></package>', '</metadata>']
fl = ['<?xml version="1.0" encoding="UTF-8"?>', '<filelists xmlns="http://linux.duke.edu/metadata/filelists" packages="2">',
      '<package pkgid="' + '1' * 64 + '" name="golang" arch="x86_64"><version epoch="0" ver="1.25.9" rel="1.el9_7"/>'
      + ''.join(f'<file>{q}</file>' if m & 0o100000 else f'<file type="dir">{q}</file>'
                for q, m, _, _ in fichiers if not (cas == 'fichiers' and q.endswith('VERSION'))) + '</package>',
      '<package pkgid="' + '2' * 64 + '" name="golang-bin" arch="x86_64"><version epoch="0" ver="1.25.9" rel="1.el9_7"/>'
      '<file>/usr/lib/golang/bin/go</file></package>', '</filelists>']
bp, bf = gzip.compress('\n'.join(p).encode()), gzip.compress('\n'.join(fl).encode())
open(f'{o}/primary.xml.gz', 'wb').write(bp); open(f'{o}/filelists.xml.gz', 'wb').write(bf)
sp, sf = hashlib.sha256(bp).hexdigest(), hashlib.sha256(bf).hexdigest()
with open(f'{o}/repomd.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<repomd xmlns="http://linux.duke.edu/metadata/repo">'
            f'<data type="primary"><checksum type="sha256">{sp}</checksum><location href="repodata/{sp[:8]}-primary.xml.gz"/></data>'
            f'<data type="filelists"><checksum type="sha256">{sf}</checksum><location href="repodata/{sf[:8]}-filelists.xml.gz"/></data>'
            '</repomd>\n')
print(sp[:8], sf[:8], href)
PY
  )
  read -r hp hf hr <<< "$href"
  if [ "$1" = signature ]; then echo autre > "$r/autre"; "${G[@]}" -u "$FP" --armor --detach-sign -o "$r/repomd.xml.asc" "$r/autre"
  else "${G[@]}" -u "$FP" --armor --detach-sign -o "$r/repomd.xml.asc" "$r/repomd.xml"; fi
  servir "$b/repodata/repomd.xml" "$r/repomd.xml"; servir "$b/repodata/repomd.xml.asc" "$r/repomd.xml.asc"
  servir "$b/repodata/$hp-primary.xml.gz" "$r/primary.xml.gz"; servir "$b/repodata/$hf-filelists.xml.gz" "$r/filelists.xml.gz"
  servir "$b/$hr" "$r/golang.rpm"
}
cas() {
  echo "== cas $1"
  monter "$1"
  HOME=$H/home PATH=$H/bin:$PATH bash "$B/m2.sh" releve9 2>&1 | sed -e "s#$H#<essai>#g" -e "s#$FP#<empreinte d essai>#g"
  echo "code ${PIPESTATUS[0]}"
}
for c in nominal zstd differente sans_sig somme magie tronque borne fichiers taille charge archive signature evr sha_entete emplacement sig_fausse; do cas "$c"; done
gpgconf --kill all 2>/dev/null || true
rm -rf -- "${H:?}"
