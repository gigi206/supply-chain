#!/usr/bin/env bash
# Témoins hors réseau du lecteur d'en-tête rpm de releve9 (m2.sh), écrit le 16/11/2026 avant tout passage de releve9. Deux rpm
# réels, jeux d'essai de modules Go déjà en cache (cache de modules du correctif de Kyverno, brique 08), lus dans les zip du cache :
#   - rocky-basesystem-11-13.el9.noarch.rpm (github.com/sassoftware/relic/v8 v8.2.0, functest/packages) : rpm de Rocky 9 ;
#   - zlib-1.2.8-10.fc24.i686.rpm (github.com/sassoftware/relic v7.2.1+incompatible, functest/packages) : rpm de Fedora 24.
# Provenance : h1 de chaque zip recalculé ici (somme des sha256 des entrées triées, algorithme Hash1 de Go écrit de mémoire), exigé
# égal au .ziphash du cache ET à la ligne d'un go.sum de Kyverno (v8 : main-b2e65e2 ; v7.2.1 : v1.19.2), sinon KO.
# 1. basesystem : le lecteur de l'étape, extrait tel quel de m2.sh (du heredoc qui suit « python3 -I - "$d/golang.rpm" » à « PY »),
#    lancé avec le paquet attendu « basesystem 0:11-13.el9.noarch », License « Public Domain », une liste de fichiers vide et la
#    clé de Rocky (empreinte égale à FP_ROCKY de s1.sh exigée). Attendu : signature 268 (VALIDSIG), tag 273, tag 5092, nom, EVR et
#    License tenus, puis KO « tags de fichiers absents » : basesystem ne porte aucun fichier.
# 2. zlib : lecteur minimal à part (la clé de Fedora 24 n'est pas là, le lecteur de l'étape s'arrêterait à la signature) : drapeaux
#    des fichiers (bits 2 et 128 face aux dossiers où rpmbuild place %doc et %license), compresseur ; charge en xz : cpio lu,
#    empreinte de chaque fichier régulier recalculée (algorithme du tag 5011, md5 si absent) et exigée égale à l'en-tête.
# Usage : m2-releve9-temoins.sh <racine du dépôt> <dossier vidé>
set -u
D=$1; W=$2
G=$HOME/.cache/supply-chain-poc/08/kyverno-correctif
rm -rf -- "${W:?}"; mkdir -p "$W"; mkdir -m 700 "$W/gnupg"; export GNUPGHOME=$W/gnupg
ko() { echo "KO   $*"; gpgconf --kill all 2>/dev/null; rm -rf -- "${W:?}"; exit 1; }
FP=$(sed -n 's/^FP_ROCKY=\([0-9A-F]\{40\}\)\([[:space:]].*\)\{0,1\}$/\1/p' "$D/poc/bricks/05-rpm-mock/s1.sh")
[ "$(printf '%s' "$FP" | grep -c .)" = 1 ] || ko "FP_ROCKY illisible dans s1.sh"
s=$(gpg --batch --with-colons --show-keys "$HOME/.cache/supply-chain-poc/05/sante/rocky.key" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
[ "$s" = "$FP" ] && echo "OK   clé de Rocky (cache de la santé de la 05) : empreinte $s égale à FP_ROCKY" || ko "empreinte de la clé : « $s »"
gpg --batch --quiet --no-default-keyring --keyring "$W/cles.gpg" --import "$HOME/.cache/supply-chain-poc/05/sante/rocky.key" 2>/dev/null \
  || ko "clé de Rocky non importée"
python3 -I - "$G" "$W" <<'PY' || ko "zip des modules"
import base64, hashlib, os, sys, zipfile
g, w = sys.argv[1:3]
mods = [('github.com/sassoftware/relic/v8', 'v8.2.0', 'functest/packages/rocky-basesystem-11-13.el9.noarch.rpm', 'basesystem.rpm',
         'main-b2e65e2'),
        ('github.com/sassoftware/relic', 'v7.2.1+incompatible', 'functest/packages/zlib-1.2.8-10.fc24.i686.rpm', 'zlib.rpm', 'v1.19.2')]
for mod, ver, chemin, sortie, src in mods:
    gosum = open(os.path.join(g, src, 'go.sum'), encoding='utf-8').read().splitlines()
    base = os.path.join(g, 'gomodcache', 'cache', 'download', mod, '@v', ver)
    with zipfile.ZipFile(base + '.zip') as z:
        noms = sorted(n for n in z.namelist() if not n.endswith('/'))
        resume = ''.join(f"{hashlib.sha256(z.read(n)).hexdigest()}  {n}\n" for n in noms)
        h1 = 'h1:' + base64.b64encode(hashlib.sha256(resume.encode()).digest()).decode()
        zh = open(base + '.ziphash').read().strip()
        ligne = f"{mod} {ver} {h1}"
        if h1 != zh or ligne not in gosum:
            sys.exit(f"{mod} {ver} : h1 recalculé {h1}, .ziphash {zh}, ligne du go.sum de Kyverno {src} {'présente' if ligne in gosum else 'absente'}")
        donnees = z.read(f"{mod}@{ver}/{chemin}")
    open(os.path.join(w, sortie), 'wb').write(donnees)
    print(f"OK   {mod} {ver} : h1 recalculé {h1}, égal au .ziphash et au go.sum de Kyverno {src} ; {chemin} : {len(donnees)} octets, "
          f"sha256 {hashlib.sha256(donnees).hexdigest()}")
PY
echo "## 1. rocky-basesystem (Rocky 9) par le lecteur de l'étape, extrait de m2.sh"
awk '/^  python3 -I - "\$d\/golang\.rpm"/ {f = 1; next} f && /^PY$/ {exit} f' "$D/poc/bricks/05-rpm-mock/m2.sh" > "$W/lecteur.py"
echo "lecteur extrait : $(wc -l < "$W/lecteur.py") lignes, sha256 $(sha256sum < "$W/lecteur.py" | cut -c1-64)"
: > "$W/vide.fichiers"
python3 -I "$W/lecteur.py" "$W/basesystem.rpm" "$W/vide.fichiers" "basesystem 0:11-13.el9.noarch" "Public Domain" "$(go env GOROOT)" "$W" "$FP" 2>&1
echo "code $? (attendu : 1, « tags de fichiers absents », après les lignes OK)"
echo "## 2. zlib (Fedora 24) par un lecteur minimal à part"
python3 -I - "$W/zlib.rpm" <<'PY' || ko "zlib"
import hashlib, lzma, struct, sys
b = open(sys.argv[1], 'rb').read()
def entete(off):
    if b[off:off + 4] != b'\x8e\xad\xe8\x01':
        sys.exit(f"magie absente à {off}")
    il, dl = struct.unpack('>II', b[off + 8:off + 16]); st = off + 16 + 16 * il; idx = {}
    for i in range(il):
        t, ty, o, c = struct.unpack('>IIII', b[off + 16 + 16 * i:off + 32 + 16 * i]); idx[t] = (ty, o, c)
    return idx, b[st:st + dl], st + dl
def v(h, t):
    if t not in h[0]:
        return None
    ty, o, c = h[0][t]; d = h[1]
    if ty in (6, 8, 9):
        r, p = [], o
        for _ in range(1 if ty == 6 else c):
            e = d.find(b'\0', p); r.append(d[p:e].decode('utf-8', 'replace')); p = e + 1
        return r[0] if ty == 6 else r
    if ty == 4:
        return list(struct.unpack(f'>{c}I', d[o:o + 4 * c]))
    if ty == 3:
        return list(struct.unpack(f'>{c}H', d[o:o + 2 * c]))
sig = entete(96); h = entete((sig[2] + 7) // 8 * 8)
print(f"{v(h, 1000)} {v(h, 1001)}-{v(h, 1002)}.{v(h, 1022)} ; compresseur {v(h, 1125)} ; tag 5011 {v(h, 5011)}")
bn, dn, di, fl, md, dg = v(h, 1117), v(h, 1118), v(h, 1116), v(h, 1037), v(h, 1030), v(h, 1035)
ch = [dn[di[i]] + bn[i] for i in range(len(bn))]
for i in range(len(bn)):
    print(f"  drapeaux {fl[i]:4d} (0x{fl[i]:x}) ; mode {md[i]:o} ; {ch[i]}")
for i in range(len(bn)):
    if fl[i] & 2 and not ch[i].startswith('/usr/share/doc/'):
        sys.exit(f"bit 2 hors de /usr/share/doc : {ch[i]}")
    if fl[i] & 128 and not ch[i].startswith('/usr/share/licenses/'):
        sys.exit(f"bit 128 hors de /usr/share/licenses : {ch[i]}")
n2 = sum(1 for x in fl if x & 2); n128 = sum(1 for x in fl if x & 128)
print(f"OK   bit 2 sur {n2} fichier(s), tous sous /usr/share/doc/ ; bit 128 sur {n128} fichier(s), tous sous /usr/share/licenses/")
if v(h, 1125) != 'xz':
    sys.exit(f"compresseur {v(h, 1125)} : cpio non éprouvé")
cp = lzma.decompress(b[h[2]:])
algo = {None: 'md5', 1: 'md5', 8: 'sha256'}[(v(h, 5011) or [None])[0]]
voulu = {'.' + ch[i]: dg[i] for i in range(len(bn)) if md[i] & 0o170000 == 0o100000}
p, k, ok = 0, 0, 0
while cp[p:p + 6] == b'070701':
    f = [int(cp[p + 6 + 8 * j:p + 14 + 8 * j], 16) for j in range(13)]
    nom = cp[p + 110:p + 110 + f[11] - 1].decode(); q = (p + 110 + f[11] + 3) // 4 * 4
    if nom == 'TRAILER!!!':
        break
    k += 1
    if nom in voulu and f[6]:
        if hashlib.new(algo, cp[q:q + f[6]]).hexdigest() != voulu[nom]:
            sys.exit(f"{nom} : empreinte de la charge différente de l'en-tête")
        ok += 1
    p = (q + f[6] + 3) // 4 * 4
print(f"OK   cpio (newc) : {k} entrées ; {ok} fichier(s) régulier(s) non vide(s) à l'empreinte {algo} égale à l'en-tête "
      f"(sur {len(voulu)} réguliers ; un lien physique ne porte ses données qu'une fois)")
PY
gpgconf --kill all 2>/dev/null || true
rm -rf -- "${W:?}"
echo "fichiers effacés"
