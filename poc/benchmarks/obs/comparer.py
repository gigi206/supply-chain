#!/usr/bin/env python3
"""Banc A2 : compare deux builds OBS de sample-app (rpm et deb), fichier par fichier.

Usage : comparer.py <répertoire build A> <répertoire build B>
Chaque répertoire contient un sous-répertoire par dépôt (rocky_9, debian_13), tel que collecté
par construire.sh. Pour chaque rpm : NEVRA, date et hôte de build, tags de signature, sha256 du
fichier entier et sha256 « hors signature » (en-tête principal + charge utile, sans l'avance ni
l'en-tête de signature : la signature signd n'entre pas dans B1). Pour chaque deb : sha256 et
version (champ Version du membre control). Code de sortie 0 si tous les paquets sont identiques
hors signature.
"""
import hashlib
import os
import struct
import subprocess
import sys

TAGS = {1000: "NAME", 1001: "VERSION", 1002: "RELEASE", 1022: "ARCH", 1006: "BUILDTIME",
        1007: "BUILDHOST", 1044: "SOURCERPM", 1123: "DISTURL"}
SIG_TAGS = {267: "DSA", 268: "RSA", 1002: "PGP", 1005: "GPG", 278: "OPENPGP"}


def entete(f):
    """Lit un en-tête rpm à la position courante ; renvoie (index, données, taille totale)."""
    debut = f.read(16)
    if debut[:4] != b"\x8e\xad\xe8\x01":
        raise ValueError("magie d'en-tête rpm absente")
    n, taille = struct.unpack(">II", debut[8:16])
    index = [struct.unpack(">IIII", f.read(16)) for _ in range(n)]
    donnees = f.read(taille)
    return index, donnees, 16 + 16 * n + taille


def valeurs(index, donnees, voulus):
    r = {}
    for tag, typ, off, cnt in index:
        if tag not in voulus:
            continue
        if typ == 4:
            r[voulus[tag]] = struct.unpack(">I", donnees[off:off + 4])[0]
        elif typ in (6, 8, 9):
            r[voulus[tag]] = donnees[off:donnees.index(b"\0", off)].decode()
        else:
            r[voulus[tag]] = f"type {typ}, {cnt} élément(s)"
    return r


def rpm(chemin):
    with open(chemin, "rb") as f:
        f.read(96)                                   # avance (lead)
        sidx, sdon, staille = entete(f)
        f.read((8 - staille % 8) % 8)                # alignement de l'en-tête de signature
        pos = f.tell()
        hidx, hdon, _ = entete(f)
        f.seek(pos)
        reste = f.read()
    tags = valeurs(hidx, hdon, TAGS)
    sig = sorted(SIG_TAGS[t[0]] for t in sidx if t[0] in SIG_TAGS)
    return {
        "nevra": f"{tags['NAME']}-{tags['VERSION']}-{tags['RELEASE']}.{tags['ARCH']}",
        "buildtime": tags.get("BUILDTIME"), "buildhost": tags.get("BUILDHOST"),
        "disturl": tags.get("DISTURL"), "signature": ",".join(sig) or "aucune",
        "sha256_hors_signature": hashlib.sha256(reste).hexdigest(),
    }


def deb(chemin):
    sortie = subprocess.run(["dpkg-deb", "-f", chemin, "Package", "Version", "Architecture"],
                            check=True, capture_output=True, text=True).stdout
    champs = dict(l.split(": ", 1) for l in sortie.splitlines() if ": " in l)
    return {"nevra": f"{champs['Package']}_{champs['Version']}_{champs['Architecture']}"}


def sha256(chemin):
    h = hashlib.sha256()
    with open(chemin, "rb") as f:
        for bloc in iter(lambda: f.read(1 << 20), b""):
            h.update(bloc)
    return h.hexdigest()


def paquets(rep):
    r = {}
    for depot in sorted(os.listdir(rep)):
        for nom in sorted(os.listdir(os.path.join(rep, depot))):
            chemin = os.path.join(rep, depot, nom)
            if nom.endswith(".rpm"):
                info = rpm(chemin)
            elif nom.endswith(".deb"):
                info = deb(chemin)
            else:
                continue
            info["sha256"] = sha256(chemin)
            r[(depot, nom)] = info
    return r


a, b = paquets(sys.argv[1]), paquets(sys.argv[2])
identiques = True
for cle in sorted(set(a) | set(b)):
    depot, nom = cle
    ia, ib = a.get(cle), b.get(cle)
    if not ia or not ib:
        print(f"{depot}/{nom} : présent dans un seul build")
        identiques = False
        continue
    print(f"{depot}/{nom}")
    for k in ia:
        egal = "=" if ia[k] == ib[k] else "≠"
        print(f"  {k:24} {egal} {ia[k]}" + ("" if ia[k] == ib[k] else f"  |  {ib[k]}"))
    cle_cmp = "sha256_hors_signature" if nom.endswith(".rpm") else "sha256"
    if ia["nevra"] != ib["nevra"] or ia[cle_cmp] != ib[cle_cmp]:
        identiques = False
    print(f"  => {'IDENTIQUE' if ia['nevra'] == ib['nevra'] and ia[cle_cmp] == ib[cle_cmp] else 'DIFFÉRENT'}"
          f" ({'hors signature' if nom.endswith('.rpm') else 'fichier entier'})")
sys.exit(0 if identiques else 1)
