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
        paquets.py modules <fichier.deb>
        paquets.py stdlib <fichier.deb> <deb de golang-X.Y-src> --sbom <sortie.json>

Mode stdlib (ajouté le 12/11/2026, décision « Axe 3, puis 1+2 ») : la version de Go lue dans chaque binaire de ./usr/bin du deb
(une seule version exigée) doit être la version amont (sans époque ni révision Debian) du paquet golang-*-src donné ; le copyright
DEP-5 de ce paquet devient l'expression d'un second composant du SBOM, pkg:deb/debian/<paquet>@<version>?arch=<arch>, à côté du
composant du deb lui-même (même expression qu'en mode deb). C'est la licence que Debian déclare pour tout le paquet source de la
bibliothèque standard, fichiers non compilés compris : une borne haute, pas la licence des seuls fichiers compilés.

Mode modules (ajouté le 12/11/2026) : pour chaque fichier ordinaire de ./usr/bin du deb, lu en mémoire, jamais écrit ni exécuté,
les informations de build de Go (en-tête « \\xff Go buildinf: », format en ligne de go1.18 et après ; un format plus ancien est
refusé) : version de Go, module principal, dépendances, réglages de build. Chaque dépendance est rapprochée des paragraphes Files
du copyright (le DERNIER paragraphe qui correspond à vendor/<module>/… s'applique, comme en DEP-5) : KO si aucun paragraphe propre
ne la couvre (couverte par « * » seul, elle prendrait la licence du projet). La bibliothèque standard de Go, compilée dans le
binaire sans être dans vendor/ ni dans le copyright, est toujours signalée en ÉCART, avec le champ Built-Using du control. Code 1 sur un KO ou un refus.
"""
import argparse
import fnmatch
import hashlib
import io
import json
import re
import sys
import tarfile

FORMAT = re.compile(r"^https?://www\.debian\.org/doc/packaging-manuals/copyright-format/1\.0/?$")


class Refus(Exception):
    journal: list = []


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


def analyser(texte, souple=False):
    """(expression du paquet ou NOASSERTION, lignes de journal) ; Refus sur un DEP-5 mal formé.

    souple=False (modes deb et dep5, mesurés) : refus au premier défaut ; Files et Copyright exigés sur leur première ligne.
    souple=True (composant de la bibliothèque standard, copyright de Debian non écrit par nous) : Files et Copyright comptent
    aussi quand leur valeur commence à la ligne suivante ; tous les paragraphes sont journalisés et tous les défauts listés,
    puis un seul Refus en donne le nombre ; aucune expression n'est rendue s'il y en a un.
    """
    j, defauts = [], []
    ps = paragraphes(texte)
    if not ps or "format" not in ps[0] or not FORMAT.match(ps[0]["format"][0]):
        j.append("format : absent ou autre que DEP-5 1.0 -> NOASSERTION")
        return "NOASSERTION", j
    j.append(f"format : DEP-5 1.0 ; paragraphes : {len(ps)}")
    textes = {p["license"][0] for p in ps[1:] if "files" not in p and "license" in p and p["license"][1]}
    exprs = []

    def present(p, c):
        return c in p and bool(p[c][0] or (souple and c != "license" and any(p[c][1])))

    for k, p in enumerate(ps[1:], 2):
        if "files" not in p:
            continue
        try:
            manque = [c for c in ("files", "copyright", "license") if not present(p, c)]
            if manque:
                raise Refus(f"paragraphe {k} : champ(s) manquant(s) : {', '.join(manque)}")
            expr, noms = expression_dep5(p["license"][0])
            sans_texte = [n for n in noms if n not in textes and not (p["license"][1] and len(noms) == 1)]
            if sans_texte:
                raise Refus(f"paragraphe {k} : texte de licence absent pour {', '.join(sans_texte)}")
        except Refus as e:
            if not souple:
                raise
            defauts.append(str(e))
            j.append(f"Files {' '.join([p['files'][0]] + p['files'][1])[:120]} : License « {p.get('license', ('', []))[0]} » -> DÉFAUT : {e}")
            continue
        fichiers = " ".join([p["files"][0]] + p["files"][1])
        j.append(f"Files {fichiers[:120] if souple else fichiers} : License « {p['license'][0]} » -> {expr}")
        exprs.append(f"({expr})" if " " in expr else expr)
    if defauts:
        e = Refus(f"{len(defauts)} défaut(s) : " + " | ".join(defauts))
        e.journal = j
        raise e
    if not exprs:
        raise Refus("aucun paragraphe Files")
    return " AND ".join(exprs), j


def fichiers_dep5(texte):
    """[(motifs Files, licence)] dans l'ordre du fichier ; Refus si l'en-tête DEP-5 manque."""
    ps = paragraphes(texte)
    if not ps or "format" not in ps[0] or not FORMAT.match(ps[0]["format"][0]):
        raise Refus("copyright sans en-tête DEP-5 1.0")
    return [(" ".join([p["files"][0]] + p["files"][1]).split(), p.get("license", ("", []))[0]) for p in ps[1:] if "files" in p]


MAGIC = b"\xff Go buildinf:"


def uvarint(b, i):
    x, s = 0, 0
    while True:
        if i >= len(b) or s > 63:
            raise Refus("varint illisible dans les informations de build")
        c = b[i]
        x |= (c & 0x7F) << s
        i += 1
        if c < 0x80:
            return x, i
        s += 7


def infos_build(b):
    """(version de Go, lignes de modinfo) ; Refus si absentes, en double ou d'un format ancien."""
    trouves, i = [], b.find(MAGIC)
    while i >= 0:
        trouves.append(i)
        i = b.find(MAGIC, i + 1)
    if len(trouves) != 1:
        raise Refus(f"en-tête des informations de build : {len(trouves)} occurrence(s), 1 attendue")
    i = trouves[0]
    if len(b) < i + 32 or not b[i + 15] & 2:
        raise Refus("informations de build d'un format antérieur à go1.18 : non traité")
    n, j = uvarint(b, i + 32)
    version = b[j:j + n].decode("utf-8")
    n, j = uvarint(b, j + n)
    mod = b[j:j + n]
    if len(mod) < 33 or mod[-17:-16] != b"\n":
        raise Refus("modinfo illisible")
    return version, mod[16:-16].decode("utf-8").splitlines()


def modules(deb):
    """Lignes de journal ; True si aucun KO."""
    ms = membres_ar(deb)
    if [n for n, _ in ms] != ["debian-binary", "control.tar.xz", "data.tar.xz"]:
        raise Refus(f"membres ar : {[n for n, _ in ms]}")
    ctl = paragraphes(fichier_tar(ms[1][1], "./control").decode("utf-8"))[0]
    nom = ctl["package"][0]
    bu = " ".join([ctl["built-using"][0]] + ctl["built-using"][1]) if "built-using" in ctl else "absent"
    print(f"control : Built-Using {bu}")
    stanzas = fichiers_dep5(fichier_tar(ms[2][1], f"./usr/share/doc/{nom}/copyright").decode("utf-8"))
    ok, binaires = True, []
    with tarfile.open(fileobj=io.BytesIO(ms[2][1]), mode="r:xz") as t:
        for m in t.getmembers():
            if m.name.startswith("./usr/bin/") and m.isfile():
                f = t.extractfile(m)
                if f is None:
                    raise Refus(f"{m.name} : illisible")
                binaires.append((m.name, f.read()))
    if not binaires:
        raise Refus("aucun fichier dans ./usr/bin")
    for chemin, b in binaires:
        print(f"## binaire {chemin} : {len(b)} octets, sha256 {hashlib.sha256(b).hexdigest()}")
        version, lignes = infos_build(b)
        print(f"go : {version}")
        deps = []
        for l in lignes:
            c = l.split("\t")
            if c[0] in ("path", "mod", "build"):
                print(f"{c[0]} : {' '.join(c[1:])}")
            elif c[0] == "dep":
                deps.append(c[1:3])
                print(f"dep : {' '.join(c[1:])}")
            elif c[0] == "=>":
                print(f"remplacement : {' '.join(c[1:])}")
                ok = False
                print("KO   remplacement de module : non traité")
            else:
                print(f"KO   ligne de modinfo inconnue : {c[0]}")
                ok = False
        print(f"dépendances compilées : {len(deps)}")
        for dep, v in deps:
            cand = f"vendor/{dep}/fichier.go"
            app = [(motifs, lic) for motifs, lic in stanzas if any(fnmatch.fnmatchcase(cand, x) for x in motifs)]
            if not app or app[-1][0] == ["*"]:
                print(f"KO   dep {dep} {v} : aucun paragraphe Files propre (couverte par « * » seul : {bool(app)})")
                ok = False
            else:
                print(f"OK   dep {dep} {v} : paragraphe Files {' '.join(app[-1][0])} ({app[-1][1]})")
        for motifs, lic in stanzas:
            for x in motifs:
                if x.startswith("vendor/") and not any(fnmatch.fnmatchcase(f"vendor/{d}/fichier.go", x) for d, _ in deps):
                    print(f"ÉCART paragraphe Files {x} ({lic}) : aucun module compilé ne lui correspond")
        # le copyright décrit les sources du paquet ; la bibliothèque standard n'y est pas (constat, pas un KO)
        print(f"ÉCART bibliothèque standard de {version} : compilée dans le binaire, hors des sources, donc hors du copyright ; Built-Using {bu}")
    return ok


def lire_deb(b):
    """(champs du control, membres ar) d'un deb ; mêmes exigences qu'en mode deb."""
    ms = membres_ar(b)
    if [n for n, _ in ms] != ["debian-binary", "control.tar.xz", "data.tar.xz"] or ms[0][1] != b"2.0\n":
        raise Refus(f"membres ar ou debian-binary inattendus : {[n for n, _ in ms]}")
    ctl = paragraphes(fichier_tar(ms[1][1], "./control").decode("utf-8"))
    if len(ctl) != 1 or any(c not in ctl[0] for c in ("package", "version", "architecture")):
        raise Refus("control : Package, Version ou Architecture absent")
    return {k: v[0] for k, v in ctl[0].items()}, ms


def stdlib(deb, src):
    """Composants du SBOM (deb, puis paquet source de la bibliothèque standard) ; Refus sur toute incohérence."""
    ctl, ms = lire_deb(deb)
    nom = ctl["package"]
    versions = set()
    with tarfile.open(fileobj=io.BytesIO(ms[2][1]), mode="r:xz") as t:
        for m in t.getmembers():
            if m.name.startswith("./usr/bin/") and m.isfile():
                f = t.extractfile(m)
                if f is None:
                    raise Refus(f"{m.name} : illisible")
                v, _ = infos_build(f.read())
                print(f"binaire {m.name} : {v}")
                versions.add(v)
    if len(versions) != 1:
        raise Refus(f"versions de Go dans ./usr/bin : {sorted(versions)}, une seule attendue")
    go = versions.pop()
    sctl, sms = lire_deb(src)
    print(f"paquet de la bibliothèque standard : {sctl['package']} {sctl['version']} {sctl['architecture']}")
    if not re.fullmatch(r"golang-\d+\.\d+-src", sctl["package"]):
        raise Refus(f"{sctl['package']} n'est pas un paquet golang-X.Y-src")
    amont = re.sub(r"^\d+:", "", sctl["version"]).rsplit("-", 1)[0]
    if "go" + amont != go:
        raise Refus(f"version amont {amont} du paquet, {go} dans le binaire")
    print(f"OK   {go} du binaire = version amont {amont} de {sctl['package']}")
    comps = []
    for n, c, v, a, membres in ((nom, None, ctl["version"], ctl["architecture"], ms),
                                (sctl["package"], None, sctl["version"], sctl["architecture"], sms)):
        cr = fichier_tar(membres[2][1], f"./usr/share/doc/{n}/copyright")
        print(f"## copyright de {n} : sha256 {hashlib.sha256(cr).hexdigest()} ({len(cr)} octets)")
        try:
            expr, j = analyser(cr.decode("utf-8"), souple=(n != nom))
        except Refus as e:
            for l in getattr(e, "journal", []):
                print(l)
            raise
        for l in j:
            print(l)
        purl = f"pkg:deb/debian/{n}@{v}?arch={a}"
        print(f"{purl} : {expr}")
        comps += sbom(purl, n, v, expr)["components"]
    return {"bomFormat": "CycloneDX", "specVersion": "1.6", "components": comps}


def sbom(purl, nom, version, expr):
    comp = {"type": "application", "name": nom, "version": version, "purl": purl}
    if expr != "NOASSERTION":
        comp["licenses"] = [{"expression": expr}]
    return {"bomFormat": "CycloneDX", "specVersion": "1.6", "components": [comp]}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("mode", choices=["deb", "dep5", "modules", "stdlib"])
    p.add_argument("fichier")
    p.add_argument("source", nargs="?", help="mode stdlib : deb de golang-X.Y-src")
    p.add_argument("--sbom")
    p.add_argument("--purl")
    a = p.parse_args(argv)
    try:
        b = open(a.fichier, "rb").read()
        print(f"sha256 de l'entrée : {hashlib.sha256(b).hexdigest()} ({len(b)} octets)")
        if a.mode == "modules":
            return 0 if modules(b) else 1
        if not a.sbom:
            raise Refus("--sbom exigé")
        if a.mode == "stdlib":
            if not a.source:
                raise Refus("deb de golang-X.Y-src exigé")
            src = open(a.source, "rb").read()
            print(f"sha256 du paquet de la bibliothèque standard : {hashlib.sha256(src).hexdigest()} ({len(src)} octets)")
            json.dump(stdlib(b, src), open(a.sbom, "w"), indent=1)
            return 0
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
