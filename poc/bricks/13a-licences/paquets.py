#!/usr/bin/env python3
"""Brique 13a, volet rpm/deb : licences déclarées d'un deb construit, en SBOM CycloneDX pour licences.py.

Lit le deb sans rien extraire sur disque ni exécuter (ar, puis tar.xz par la bibliothèque standard) :
  1. membres ar exigés, dans cet ordre : debian-binary (« 2.0 »), control.tar.xz, data.tar.xz ; tout autre membre ou
     compression : refus ;
  2. ./control de control.tar.xz : Package, Version, Architecture ;
  3. ./usr/share/doc/<Package>/copyright de data.tar.xz : fichier ordinaire exigé (lien refusé) ;
  4. analyse DEP-5 1.0 (en-tête Format exigé, sinon NOASSERTION) : chaque paragraphe Files doit avoir Files, Copyright
     et License ; chaque nom de licence employé doit avoir son texte (dans le paragraphe ou dans un paragraphe License
     autonome) ; « and » et « or » sont réécrits en AND et OR ; « with » n'est pas traité (refus, jamais deviné) ;
     aucun nom DEP-5 n'est traduit en SPDX (Expat, GPL-2+… restent tels quels : licences.py les jugera invalides) ;
  5. expression du paquet : AND des expressions des paragraphes Files, chacune entre parenthèses si composée.

Sortie : lignes « clé : valeur » sur la sortie standard (journal), SBOM CycloneDX dans le fichier --sbom.
Code 1 sur un refus (lignes « REFUS : … »), 0 sinon ; NOASSERTION n'est pas un refus ici : licences.py le refusera.

Usage : paquets.py deb <fichier.deb> --sbom <sortie.json>
        paquets.py dep5 <fichier copyright> --sbom <sortie.json> --purl <purl>   (témoins, sans deb)
"""
import argparse
import hashlib
import io
import json
import re
import sys
import tarfile

FORMAT = re.compile(r"^https?://www\.debian\.org/doc/packaging-manuals/copyright-format/1\.0/?$")


class Refus(Exception):
    pass


def membres_ar(b):
    if b[:8] != b"!<arch>\n":
        raise Refus("pas une archive ar")
    out, i = [], 8
    while i < len(b):
        h = b[i:i + 60]
        if len(h) < 60 or h[58:60] != b"`\n":
            raise Refus("en-tête ar invalide")
        nom, taille = h[:16].decode("ascii").strip().rstrip("/"), int(h[48:58])
        out.append((nom, b[i + 60:i + 60 + taille]))
        i += 60 + taille + (taille & 1)
    return out


def fichier_tar(donnees, chemin):
    with tarfile.open(fileobj=io.BytesIO(donnees), mode="r:xz") as t:
        trouves = [m for m in t.getmembers() if m.name in (chemin, chemin.lstrip("./"), "./" + chemin.lstrip("./"))]
        if len(trouves) != 1:
            raise Refus(f"{chemin} : {len(trouves)} entrée(s) dans l'archive, 1 attendue")
        m = trouves[0]
        if not m.isfile():
            raise Refus(f"{chemin} : pas un fichier ordinaire (type {m.type!r})")
        f = t.extractfile(m)
        if f is None:
            raise Refus(f"{chemin} : illisible")
        return f.read()


def paragraphes(texte):
    """Paragraphes deb822 : liste de dict champ -> (première ligne, lignes de continuation)."""
    out, cur, champ = [], {}, None
    for n, ligne in enumerate(texte.splitlines(), 1):
        if not ligne.strip():
            if cur:
                out.append(cur)
            cur, champ = {}, None
        elif ligne[0] in " \t":
            if champ is None:
                raise Refus(f"ligne {n} : continuation sans champ")
            cur[champ][1].append(ligne.strip())
        else:
            m = re.match(r"^([A-Za-z0-9][A-Za-z0-9-]*):\s*(.*)$", ligne)
            if not m:
                raise Refus(f"ligne {n} : champ illisible")
            champ = m.group(1).lower()
            if champ in cur:
                raise Refus(f"ligne {n} : champ {m.group(1)} répété")
            cur[champ] = (m.group(2).strip(), [])
    if cur:
        out.append(cur)
    return out


def expression_dep5(court):
    """Nom court DEP-5 vers expression : « and » / « or » réécrits, « with » refusé ; rien d'autre n'est traduit."""
    mots = court.replace(",", " , ").split()
    if any(m.lower() == "with" for m in mots):
        raise Refus(f"« with » non traité : {court}")
    if "," in mots:
        raise Refus(f"virgule non traitée : {court}")
    noms = [m for m in mots if m.lower() not in ("and", "or")]
    expr = " ".join(m.upper() if m.lower() in ("and", "or") else m for m in mots)
    return expr, noms


def analyser(texte):
    """(expression du paquet ou NOASSERTION, lignes de journal) ; Refus sur un DEP-5 mal formé."""
    j = []
    ps = paragraphes(texte)
    if not ps or "format" not in ps[0] or not FORMAT.match(ps[0]["format"][0]):
        j.append("format : absent ou autre que DEP-5 1.0 -> NOASSERTION")
        return "NOASSERTION", j
    j.append(f"format : DEP-5 1.0 ; paragraphes : {len(ps)}")
    textes = {p["license"][0] for p in ps[1:] if "files" not in p and "license" in p and p["license"][1]}
    exprs = []
    for k, p in enumerate(ps[1:], 2):
        if "files" not in p:
            continue
        manque = [c for c in ("files", "copyright", "license") if c not in p or not p[c][0]]
        if manque:
            raise Refus(f"paragraphe {k} : champ(s) manquant(s) : {', '.join(manque)}")
        expr, noms = expression_dep5(p["license"][0])
        sans_texte = [n for n in noms if n not in textes and not (p["license"][1] and len(noms) == 1)]
        if sans_texte:
            raise Refus(f"paragraphe {k} : texte de licence absent pour {', '.join(sans_texte)}")
        fichiers = " ".join([p["files"][0]] + p["files"][1])
        j.append(f"Files {fichiers} : License « {p['license'][0]} » -> {expr}")
        exprs.append(f"({expr})" if " " in expr else expr)
    if not exprs:
        raise Refus("aucun paragraphe Files")
    return " AND ".join(exprs), j


def sbom(purl, nom, version, expr):
    comp = {"type": "application", "name": nom, "version": version, "purl": purl}
    if expr != "NOASSERTION":
        comp["licenses"] = [{"expression": expr}]
    return {"bomFormat": "CycloneDX", "specVersion": "1.6", "components": [comp]}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("mode", choices=["deb", "dep5"])
    p.add_argument("fichier")
    p.add_argument("--sbom", required=True)
    p.add_argument("--purl")
    a = p.parse_args(argv)
    try:
        b = open(a.fichier, "rb").read()
        print(f"sha256 de l'entrée : {hashlib.sha256(b).hexdigest()} ({len(b)} octets)")
        if a.mode == "deb":
            ms = membres_ar(b)
            noms = [n for n, _ in ms]
            if noms != ["debian-binary", "control.tar.xz", "data.tar.xz"]:
                raise Refus(f"membres ar : {noms}")
            if ms[0][1] != b"2.0\n":
                raise Refus("debian-binary différent de 2.0")
            ctl = paragraphes(fichier_tar(ms[1][1], "./control").decode("utf-8"))
            if len(ctl) != 1 or any(c not in ctl[0] for c in ("package", "version", "architecture")):
                raise Refus("control : Package, Version ou Architecture absent")
            nom, version, arch = (ctl[0][c][0] for c in ("package", "version", "architecture"))
            if not re.fullmatch(r"[a-z0-9][a-z0-9.+-]+", nom):
                raise Refus(f"nom de paquet invalide : {nom!r}")
            print(f"paquet : {nom} {version} {arch}")
            cr = fichier_tar(ms[2][1], f"./usr/share/doc/{nom}/copyright")
            purl = f"pkg:deb/debian/{nom}@{version}?arch={arch}"
        else:
            if not a.purl:
                raise Refus("--purl exigé en mode dep5")
            m = re.fullmatch(r"pkg:deb/[^/]+/([^@]+)@([^?#]+)(\?.*)?", a.purl)
            if not m:
                raise Refus(f"purl invalide : {a.purl}")
            cr, purl, nom, version = b, a.purl, m.group(1), m.group(2)
        print(f"copyright : sha256 {hashlib.sha256(cr).hexdigest()} ({len(cr)} octets)")
        expr, j = analyser(cr.decode("utf-8"))
        for l in j:
            print(l)
        print(f"purl : {purl}")
        print(f"expression du paquet : {expr}")
        json.dump(sbom(purl, nom, version, expr), open(a.sbom, "w"), indent=1)
        return 0
    except (Refus, UnicodeDecodeError, tarfile.TarError, ValueError) as e:
        print(f"REFUS : {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
