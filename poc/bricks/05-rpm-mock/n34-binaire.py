"""Brique 05, prédiction N4 (s1.sh essais, ajout ../s1-n34.patch) : le binaire usr/bin/sample-app est isolé dans l'archive cpio
(newc) d'un rpm, produite par rpm2cpio, puis mesuré comme le binaire du deb par ../13a-licences/resultats/x11-fichiers.py :
MOTIFS, TEMOINS, formes() et les lignes affichées sont repris à l'identique. Isoler le binaire est nécessaire : golang-NOTICES,
dans le même rpm, contient la chaîne runtime/memmove_amd64.s. Écrit pour le python3 3.9 de l'image d'essai (Rocky 9) ; rien sur
le réseau, rien écrit.
Usage : python3 -I n34-binaire.py <archive cpio newc>"""
import hashlib, re, sys

VOULU = "usr/bin/sample-app"


def membre(chemin, voulu):
    """contenu du membre voulu (nom sans « ./ » ni « / » de tête) ; arrêt en KO sur toute incohérence"""
    a = open(chemin, "rb").read()
    k = 0
    while True:
        h = a[k:k + 110]
        if len(h) < 110 or h[:6] not in (b"070701", b"070702"):
            sys.exit(f"KO   en-tête cpio illisible à l'octet {k}")
        taille = int(h[54:62], 16)
        nl = int(h[94:102], 16)
        if nl < 1 or k + 110 + nl > len(a):
            sys.exit(f"KO   nom hors de l'archive à l'octet {k}")
        nom = a[k + 110:k + 110 + nl - 1].decode("utf-8", "replace")
        k += (110 + nl + 3) & ~3
        if nom == "TRAILER!!!":
            sys.exit(f"KO   {voulu} absent de l'archive")
        if k + taille > len(a):
            sys.exit(f"KO   archive tronquée dans {nom}")
        n = nom[2:] if nom.startswith("./") else nom.lstrip("/")
        if n == voulu:
            if taille == 0:
                sys.exit(f"KO   {voulu} vide dans l'archive (lien dur ?)")
            return a[k:k + taille]
        k = (k + taille + 3) & ~3


b = membre(sys.argv[1], VOULU)
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
