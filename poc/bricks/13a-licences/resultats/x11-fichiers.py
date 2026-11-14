"""Mesure par fichier : noms de fichiers source de src/runtime présents dans le binaire de sample-app (table des lignes,
gardée par -s -w). Neuf motifs qui gardent X11 (paquets-lies.log) et deux témoins.
Usage : x11-fichiers.py <deb sample-app> <sha256> (appelé par x11-fichiers.sh)"""
import hashlib, io, re, sys, tarfile

deb, dsha = sys.argv[1:3]
bd = open(deb, "rb").read()
assert hashlib.sha256(bd).hexdigest() == dsha, "sha256 deb"
k, data = 8, None
while k < len(bd):
    h = bd[k:k + 60]; n = h[:16].decode().strip(); t = int(h[48:58])
    if n == "data.tar.xz":
        data = bd[k + 60:k + 60 + t]
    k += 60 + t + (t & 1)
assert data
td = tarfile.open(fileobj=io.BytesIO(data), mode="r:xz")
f = td.extractfile("./usr/bin/sample-app")
assert f is not None
b = f.read()
print(f"binaire : {len(b)} octets, sha256 {hashlib.sha256(b).hexdigest()}")
MOTIFS = ["memclr_arm.s", "memmove_386.s", "memmove_amd64.s", "memmove_arm.s", "memmove_plan9_386.s",
          "memmove_plan9_amd64.s", "vlop_386.s", "vlop_arm.s", "vlrt.go"]
TEMOINS = [("asm_amd64.s", "témoin positif"), ("asm_arm.s", "témoin négatif")]


def formes(nom):
    """occurrences du nom de fichier, avec le préfixe réel lu dans le binaire (jusqu'à 40 octets avant)"""
    out = set()
    for m in re.finditer(re.escape(nom.encode()), b):
        a = b[max(0, m.start() - 40):m.end()]
        p = re.search(rb"[A-Za-z0-9_./-]*$", a[:-len(nom)])
        out.add((p.group(0) if p else b"").decode("ascii", "replace") + nom)
    return sorted(out)


for nom, role in [(x, "motif X11") for x in MOTIFS] + TEMOINS:
    fs = formes(nom)
    exact = "runtime/" + nom
    print(f"{role:15} {nom:22} : {'PRÉSENT' if exact in fs else 'absent '} (forme runtime/{nom}) ; occurrences : {fs if fs else 'aucune'}")
