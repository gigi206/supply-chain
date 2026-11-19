#!/usr/bin/env python3
# Brique 09, O5 réel : objets publiés dans signes/** et contrôle indépendant des attestations de lien, sur l'hôte, sans réseau.
# Les valeurs attendues viennent d'o5-lien.py attendus (journaux archivés), jamais de ce fichier. Les données tirées de Zot sont
# lues sans rien exécuter ni extraire sur le disque.
#   attendus                             valeurs archivées (o5-lien.py attendus, remplacées au banc seulement)
#   extraire ENVELOPPES SORTIE           l'énoncé de lien unique d'une sortie de verify-attestation, pour l'archiver
#   construire SORTIE                    trois layouts OCI déterministes (rpm, depot-rpm, depot-apt) : une couche tar non compressée,
#                                        membres triés, 0/0, 0644, mtime 0 ; chaque arbre est d'abord contrôlé (chaîne complète,
#                                        aucun membre de trop, aucun bloc privé, aucune adresse) ; digests écrits dans SORTIE/digests
#   predicats LAYOUTS CHAINS SORTIE      les quatre prédicats réels (sujet : le manifeste publié) ; CHAINS : provenance de Chains
#                                        vérifiée juste avant par le script (JSON écrit par o5-signes.sh)
#   temoins LAYOUTS SORTIE               prédicat rpm-autre-manifeste et layout rpm-altere (dernier octet du rpm signé inversé)
#   enonce CAS PREDICAT DIGEST           une enveloppe DSSE NON SIGNÉE (une ligne), pour passer le prédicat au contrôle avant signature
#   controle CAS ENVELOPPES DIGEST SIGNE NON_SIGNE
#                                        contrôle indépendant : ENVELOPPES = sortie de cosign verify-attestation (une enveloppe par
#                                        ligne, déjà vérifiée par cosign), une seule de type lien ; sujet = DIGEST = manifeste du layout
#                                        SIGNE ; layout NON_SIGNE (tiré de builds/**) = manifeste et fichier non signés archivés ; B1
#                                        recalculé (rpm), identité (deb), chaîne du dépôt recalculée (dépôts), tout sur les octets lus
# Banc seulement : O5_SIGNES_ATTENDUS=<json> remplace rpm_manifeste et deb_manifeste (layouts non signés construits hors Zot) ; la
# ligne « BANC » le dit dans la sortie, et o5-signes.sh refuse cette variable hors banc.
# Code 0 si accepté, 3 si refusé (ligne « REFUS <motif> »), 2 en cas d'erreur.
import base64
import bz2
import gzip
import hashlib
import importlib.util
import io
import json
import os
import re
import sys
import tarfile

ICI = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("o5_lien", os.path.join(ICI, "o5-lien.py"))
assert _spec is not None and _spec.loader is not None
L = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(L)
Refus = L.Refus
TYPE = L.TYPE
RPM, DEB = L.RPM, L.DEB
ENONCES = ("https://in-toto.io/Statement/v0.1", "https://in-toto.io/Statement/v1")  # _type relevé par essai_attest, pas supposé
MT_MAN = "application/vnd.oci.image.manifest.v1+json"
MT_CFG = "application/vnd.oci.image.config.v1+json"
MT_TAR = "application/vnd.oci.image.layer.v1.tar"
DEPOTS = {"rpm": "signes/sample-app-rpm", "deb": "signes/sample-app-deb",
          "depot-rpm": "signes/depot-rpm", "depot-apt": "signes/depot-apt"}
ORIGINES = {"rpm": "builds/sample-app-rpm", "deb": "builds/sample-app-deb",
            "depot-rpm": "builds/sample-app-rpm", "depot-apt": "builds/sample-app-deb"}
RACINES = {"depot-rpm": "repodata/repomd.xml", "depot-apt": "dists/poc/InRelease"}
ADRESSE = re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")


def h(b):
    return hashlib.sha256(b).hexdigest()


def attendus():
    a = L.attendus()
    p = os.environ.get("O5_SIGNES_ATTENDUS")
    if p:
        r = json.load(open(p, encoding="utf-8"))
        if not set(r) <= {"rpm_manifeste", "deb_manifeste"}:
            raise Refus(f"banc : clés remplacées non admises {sorted(r)}")
        a.update(r)
        print(f"BANC : valeurs archivées remplacées : {', '.join(sorted(r))}")
    return a


# --- arbres et chaînes, sur un dictionnaire chemin → octets ---------------------------------------------------------------------

def arbre(racine):
    f = {}
    for d, ds, fs in os.walk(racine):
        ds.sort()
        for n in sorted(fs + [x for x in ds if os.path.islink(os.path.join(d, x))]):
            p = os.path.join(d, n)
            r = os.path.relpath(p, racine)
            if os.path.islink(p) or not os.path.isfile(p):
                raise Refus(f"arbre : {r} n'est pas un fichier régulier")
            f[r] = open(p, "rb").read()
    return f


def propre(f):
    """Aucun bloc privé ; dans les membres écrits par la brique (tout sauf les paquets, égaux par sha256 aux valeurs archivées et
    déjà publiés dans builds/**), décompressés s'il le faut, aucune adresse hors des domaines réservés .invalid et .example
    (RFC 2606). Les paquets ne sont pas balayés : leurs octets compressés donnent des motifs fortuits (mesuré sur le deb)."""
    n_fictives = 0
    for p, b in sorted(f.items()):
        if b"PRIVATE KEY" in b:
            raise Refus(f"membre {p} : bloc de clé privée")
        if p.endswith((".rpm", ".deb")):
            continue
        t = gzip.decompress(b) if p.endswith(".gz") else bz2.decompress(b) if p.endswith(".bz2") else b
        if b"PRIVATE KEY" in t:
            raise Refus(f"membre {p} (décompressé) : bloc de clé privée")
        for m in ADRESSE.finditer(t):
            dom = m.group(0).rsplit(b"@", 1)[1].lower()
            if not dom.endswith((b".invalid", b".example")):
                raise Refus(f"membre {p} : adresse électronique hors des domaines réservés (non affichée)")
            n_fictives += 1
    print(f"OK   membres écrits par la brique : aucun bloc privé, aucune adresse hors de .invalid et .example"
          f" ({n_fictives} adresse(s) fictive(s))")


def chaine_rpm(f, a):
    vus = {"repodata/repomd.xml", "repodata/repomd.xml.asc"}
    for p in vus:
        if p not in f:
            raise Refus(f"dépôt rpm : {p} absent")
    L.egal("repomd.xml", h(f["repodata/repomd.xml"]), a["repomd"])
    L.egal("repomd.xml.asc", h(f["repodata/repomd.xml.asc"]), a["repomd_asc"])
    x = f["repodata/repomd.xml"].decode()
    n = 0
    for somme, loc in re.findall(r'<checksum type="sha256">([0-9a-f]{64})</checksum>.*?<location href="([^"]+)"/>', x, re.S):
        if loc not in f or h(f[loc]) != somme:
            raise Refus(f"dépôt rpm : {loc} absent ou sha256 ≠ repomd.xml")
        vus.add(loc)
        n += 1
    if n == 0:
        raise Refus("dépôt rpm : aucune entrée sha256 lue dans repomd.xml")
    prim = [c for c in vus if c.endswith("-primary.xml.gz")]
    if len(prim) != 1:
        raise Refus(f"dépôt rpm : {len(prim)} primary.xml.gz")
    px = gzip.decompress(f[prim[0]]).decode()
    pk = re.findall(r'<checksum type="sha256" pkgid="YES">([0-9a-f]{64})</checksum>', px)
    loc = re.findall(r'<location href="([^"]+)"/>', px)
    L.egal("rpm dans primary.xml.gz", pk, [a["rpm_signe"]])
    if loc != [RPM] or RPM not in f:
        raise Refus(f"dépôt rpm : location du paquet {loc} (attendu [{RPM}], présent)")
    L.egal("rpm signé du dépôt", h(f[RPM]), a["rpm_signe"])
    vus.add(RPM)
    trop = sorted(set(f) - vus)
    if trop:
        raise Refus(f"dépôt rpm : {len(trop)} membre(s) hors de la chaîne : {trop[:3]}")
    print(f"OK   dépôt rpm : chaîne repomd.xml → {n} fichiers de repodata → primary → rpm signé ; {len(f)} membres, aucun de trop")


def chaine_apt(f, a):
    d = "dists/poc/"
    vus = {d + "InRelease", d + "Release", d + "Release.gpg"}
    for p in vus:
        if p not in f:
            raise Refus(f"dépôt apt : {p} absent")
    L.egal("InRelease", h(f[d + "InRelease"]), a["inrelease"])
    L.egal("Release", h(f[d + "Release"]), a["release"])
    L.egal("Release.gpg", h(f[d + "Release.gpg"]), a["release_gpg"])
    rel = f[d + "Release"].decode()
    ir = f[d + "InRelease"].decode()
    m = re.match(r"-----BEGIN PGP SIGNED MESSAGE-----\nHash: [A-Z0-9]+\n\n(.*)\n-----BEGIN PGP SIGNATURE-----\n", ir, re.S)
    if not m or re.sub(r"^- ", "", m.group(1), flags=re.M) + "\n" != rel:
        raise Refus("dépôt apt : texte signé d'InRelease ≠ Release")
    print("OK   dépôt apt : texte signé d'InRelease = Release")
    n = 0
    for l in rel.split("\nSHA256:\n", 1)[1].split("\n"):
        x = re.match(r"^ ([0-9a-f]{64}) +\d+ (\S+)$", l)
        if not x:
            break
        p = d + x.group(2)
        if p not in f or h(f[p]) != x.group(1):
            raise Refus(f"dépôt apt : {x.group(2)} absent ou sha256 ≠ Release")
        vus.add(p)
        n += 1
    if n == 0:
        raise Refus("dépôt apt : aucune entrée lue dans la section SHA256 de Release")
    pk = f.get(d + "main/binary-amd64/Packages")
    if pk is None or d + "main/binary-amd64/Packages" not in vus:
        raise Refus("dépôt apt : Packages absent de Release")
    t = pk.decode()
    fn = re.findall(r"^Filename: (\S+)$", t, re.M)
    L.egal("deb dans Packages", re.findall(r"^SHA256: ([0-9a-f]{64})$", t, re.M), [a["deb_fichier"]])
    if len(fn) != 1 or fn[0] not in f:
        raise Refus(f"dépôt apt : Filename {fn} absent du dépôt")
    L.egal("deb du dépôt", h(f[fn[0]]), a["deb_fichier"])
    vus.add(fn[0])
    trop = sorted(set(f) - vus)
    if trop:
        raise Refus(f"dépôt apt : {len(trop)} membre(s) hors de la chaîne : {trop[:3]}")
    print(f"OK   dépôt apt : chaîne InRelease/Release → {n} index → Packages → deb ; {len(f)} membres, aucun de trop")


def membres_controles(cas, f, a):
    propre(f)
    if cas == "rpm":
        if sorted(f) != [RPM]:
            raise Refus(f"image rpm : membres {sorted(f)[:3]} (attendu : {RPM} seul)")
        L.egal("rpm signé", h(f[RPM]), a["rpm_signe"])
    elif cas == "deb":
        if sorted(f) != [DEB]:
            raise Refus(f"image deb : membres {sorted(f)[:3]} (attendu : {DEB} seul)")
        L.egal("deb (identité)", h(f[DEB]), a["deb_fichier"])
    elif cas == "depot-rpm":
        chaine_rpm(f, a)
    else:
        chaine_apt(f, a)


# --- layouts OCI -------------------------------------------------------------------------------------------------------------

def ecrire_layout(d, f):
    os.makedirs(os.path.join(d, "blobs", "sha256"))
    with open(os.path.join(d, "oci-layout"), "w") as o:
        o.write('{"imageLayoutVersion":"1.0.0"}')

    def blob(b):
        x = h(b)
        with open(os.path.join(d, "blobs", "sha256", x), "wb") as o:
            o.write(b)
        return "sha256:" + x
    t = io.BytesIO()
    with tarfile.open(fileobj=t, mode="w", format=tarfile.USTAR_FORMAT) as tf:
        for p in sorted(f):
            i = tarfile.TarInfo(p)
            i.size, i.mode, i.mtime, i.uid, i.gid, i.uname, i.gname = len(f[p]), 0o644, 0, 0, 0, "", ""
            tf.addfile(i, io.BytesIO(f[p]))
    c = t.getvalue()
    dc = blob(c)
    j = lambda o: json.dumps(o, sort_keys=True, separators=(",", ":")).encode()  # noqa: E731
    cfg = j({"architecture": "amd64", "os": "linux", "rootfs": {"type": "layers", "diff_ids": [dc]}})
    m = j({"schemaVersion": 2, "mediaType": MT_MAN, "config": {"mediaType": MT_CFG, "digest": blob(cfg), "size": len(cfg)},
           "layers": [{"mediaType": MT_TAR, "digest": dc, "size": len(c)}]})
    dm = blob(m)
    with open(os.path.join(d, "index.json"), "wb") as o:
        o.write(j({"schemaVersion": 2, "manifests": [{"mediaType": MT_MAN, "digest": dm, "size": len(m)}]}))
    return dm, len(c)


def lire_blob(d, digest):
    algo, x = digest.split(":", 1)
    if algo != "sha256" or not re.fullmatch(r"[0-9a-f]{64}", x):
        raise Refus(f"digest mal formé : {digest[:80]}")
    p = os.path.join(d, "blobs", "sha256", x)
    if not os.path.isfile(p) or os.path.islink(p):
        raise Refus(f"blob absent ou non régulier : {digest[:23]}…")
    b = open(p, "rb").read()
    if h(b) != x:
        raise Refus(f"blob {digest[:23]}… : sha256 des octets différent")
    return b


def lire_layout(d, digest):
    """Membres (chemin → octets) de l'image DIGEST du layout d : un manifeste, une couche tar non compressée, fichiers réguliers."""
    idx = json.load(open(os.path.join(d, "index.json"), encoding="utf-8"))
    if [x.get("digest") for x in idx.get("manifests", [])].count(digest) < 1:
        raise Refus(f"index : aucun manifeste {digest[:23]}…")
    man = json.loads(lire_blob(d, digest))
    cs = man.get("layers", [])
    types = (man.get("mediaType"), man.get("config", {}).get("mediaType"), len(cs), cs[0].get("mediaType") if cs else None)
    if types != (MT_MAN, MT_CFG, 1, MT_TAR):
        raise Refus(f"manifeste {digest[:23]}… : types ou nombre de couches {types}")
    cfg = json.loads(lire_blob(d, man["config"]["digest"]))
    c = lire_blob(d, cs[0]["digest"])
    if len(c) != cs[0].get("size") or cfg.get("rootfs", {}).get("diff_ids") != [cs[0]["digest"]]:
        raise Refus("couche : taille ou diff_ids différents du manifeste")
    f = {}
    with tarfile.open(fileobj=io.BytesIO(c), mode="r:") as t:
        for i in t.getmembers():
            if not i.isreg() or i.name.startswith("/") or ".." in i.name.split("/") or i.name in f:
                raise Refus(f"couche : membre refusé {i.name[:80]!r} (type {i.type!r})")
            x = t.extractfile(i)
            if x is None:
                raise Refus(f"couche : membre illisible {i.name[:80]!r}")
            f[i.name] = x.read()
    print(f"OK   layout {digest[:19]}… : manifeste, configuration et couche recalculés ; {len(f)} membre(s)")
    return f


def construire(sortie):
    a = attendus()
    srcs = {"rpm": {RPM: open(L.FICHIERS["rpm"], "rb").read()},
            "depot-rpm": arbre(L.FICHIERS["depot-rpm"]), "depot-apt": arbre(L.FICHIERS["depot-apt"])}
    lignes = []
    for cas, f in srcs.items():
        print(f"### {cas} : {len(f)} membre(s) lus")
        membres_controles(cas, f, a)
        dm, n = ecrire_layout(os.path.join(sortie, cas), f)
        if lire_layout(os.path.join(sortie, cas), dm) != f:
            raise Refus(f"{cas} : membres relus ≠ membres écrits")
        print(f"OK   {cas} : layout {dm} (couche {n} octets, {len(f)} membre(s))")
        lignes.append(f"{cas} {dm}\n")
    with open(os.path.join(sortie, "digests"), "w") as o:
        o.writelines(lignes)


def digests(layouts):
    r = {}
    for l in open(os.path.join(layouts, "digests")):
        c, d = l.split()
        r[c] = d
    return r


# --- prédicats ---------------------------------------------------------------------------------------------------------------

def predicats(layouts, chains, sortie):
    a = attendus()
    ch = json.load(open(chains, encoding="utf-8"))
    dg = digests(layouts)
    cle = L.sha(L.FICHIERS["cle"])
    L.egal("sha256 de cle-publique.asc", cle, a["cle_sha"])
    openpgp = {"fingerprint": a["empreinte"], "publicKeySha256": cle}
    orig = {"rpm": {"repository": ORIGINES["rpm"], "manifest": a["rpm_manifeste"], "file": {"name": RPM, "sha256": a["rpm_fichier"]}},
            "deb": {"repository": ORIGINES["deb"], "manifest": a["deb_manifeste"], "file": {"name": DEB, "sha256": a["deb_fichier"]}}}

    def prov(x):
        c = ch[x]
        return {"verifiedWith": "cosign verify-attestation --type slsaprovenance1, clé publique de Chains (brique 08)",
                "chainsPublicKeySha256": c["cle"], "envelopes": c["enveloppes"], "verifiedAt": c["date"],
                "transparencyLog": "non (PoC hors ligne)", "timestampTokens": "non vérifiés par cette étape"}
    p = {}
    p["rpm"] = {"link": "rpm-b1", "unsigned": orig["rpm"], "openpgp": openpgp,
                "signed": {"repository": DEPOTS["rpm"], "file": {"name": RPM, "sha256": a["rpm_signe"]}},
                "b1": {"source": "poc/bricks/09-openpgp-signing/resultats/o3-signer.log",
                       "mainHeaderOffset": a["b1_principal"], "equalFromMainHeader": True},
                "tools": a["outils_rpm"], "chainsProvenance": prov("rpm")}
    p["deb"] = {"link": "identity", "unsigned": orig["deb"], "openpgp": openpgp,
                "signed": {"repository": DEPOTS["deb"], "manifestCopiedFrom": ORIGINES["deb"], "file": {"name": DEB, "sha256": a["deb_fichier"]}},
                "tools": a["outils_deb"], "chainsProvenance": prov("deb")}
    for cas, o, x in (("depot-rpm", "rpm", "outils_rpm"), ("depot-apt", "deb", "outils_deb")):
        f = lire_layout(os.path.join(layouts, cas), dg[cas])
        p[cas] = {"link": "repository", "unsigned": orig[o], "openpgp": openpgp,
                  "signed": {"repository": DEPOTS[cas], "root": RACINES[cas]},
                  "covers": [{"path": k, "sha256": h(f[k])} for k in sorted(f)],
                  "tools": a[x], "chainsProvenance": prov(o)}
    os.makedirs(sortie, exist_ok=True)
    for c, v in p.items():
        with open(os.path.join(sortie, f"{c}.json"), "w", encoding="utf-8") as o:
            json.dump(v, o, indent=2, ensure_ascii=False, sort_keys=True)
            o.write("\n")
        print(f"     prédicat {c} : lien {v['link']}, origine {v['unsigned']['manifest'][:19]}…, dépôt {v['signed']['repository']}"
              + (f", {len(v['covers'])} fichiers couverts" if "covers" in v else ""))


def temoins(layouts, sortie):
    a = attendus()
    v = json.load(open(os.path.join(sortie, "rpm.json"), encoding="utf-8"))
    v["unsigned"]["manifest"] = a["deb_manifeste"]
    with open(os.path.join(sortie, "rpm-autre-manifeste.json"), "w", encoding="utf-8") as o:
        json.dump(v, o, indent=2, ensure_ascii=False, sort_keys=True)
        o.write("\n")
    print("     prédicat rpm-autre-manifeste : unsigned.manifest remplacé par le manifeste non signé du deb")
    f = lire_layout(os.path.join(layouts, "rpm"), digests(layouts)["rpm"])
    b = bytearray(f[RPM])
    b[-1] ^= 0x01
    dm, _ = ecrire_layout(os.path.join(sortie, "rpm-altere"), {RPM: bytes(b)})
    with open(os.path.join(sortie, "rpm-altere.digest"), "w") as o:
        o.write(dm + "\n")
    print(f"     layout rpm-altere : dernier octet du rpm signé inversé au bit 0 ; image {dm}")


def enonce(cas, predicat, digest):
    st = {"_type": ENONCES[0], "predicateType": TYPE, "predicate": json.load(open(predicat, encoding="utf-8")),
          "subject": [{"name": "local/" + DEPOTS[cas], "digest": {"sha256": digest.split(":", 1)[1]}}]}
    print(json.dumps({"payloadType": "application/vnd.in-toto+json", "signatures": [],
                      "payload": base64.b64encode(json.dumps(st).encode()).decode()}))


# --- contrôle indépendant ----------------------------------------------------------------------------------------------------

def enonces_lien(fichier):
    r, autres = [], 0
    for l in open(fichier, encoding="utf-8").read().splitlines():
        if not l.strip():
            continue
        e = json.loads(l)
        e = e.get("dsseEnvelope", e)
        if e.get("payloadType") != "application/vnd.in-toto+json":
            raise Refus(f"enveloppe : payloadType {e.get('payloadType')!r}")
        st = json.loads(base64.b64decode(e["payload"]))
        if st.get("predicateType") == TYPE:
            r.append(st)
        else:
            autres += 1
    print(f"     enveloppes lues : {len(r)} de type lien, {autres} d'un autre type")
    if len(r) != 1:
        raise Refus(f"enveloppes : {len(r)} énoncé(s) de type lien, un seul attendu")
    st = r[0]
    if st.get("_type") not in ENONCES:
        raise Refus(f"énoncé : _type {st.get('_type')!r}")
    print(f"OK   énoncé : _type {st['_type']}, prédicat {TYPE}")
    return st


def controle(cas, fichier, digest, signe, non_signe):
    a = attendus()
    st = enonces_lien(fichier)
    s = st.get("subject") or []
    if len(s) != 1 or "sha256:" + s[0].get("digest", {}).get("sha256", "") != digest:
        raise Refus(f"sujet : {[x.get('digest') for x in s]} (attendu : {digest[:23]}…)")
    print(f"OK   sujet : {s[0].get('name')} @ {digest}")
    p = st["predicate"]
    o = "rpm" if cas in ("rpm", "depot-rpm") else "deb"
    L.egal("nature du lien", p.get("link"), {"rpm": "rpm-b1", "deb": "identity"}.get(cas, "repository"))
    L.egal("dépôt d'origine", p["unsigned"]["repository"], ORIGINES[cas])
    L.egal("manifeste non signé", p["unsigned"]["manifest"], a[f"{o}_manifeste"])
    L.egal("fichier non signé", p["unsigned"]["file"]["sha256"], a[f"{o}_fichier"])
    L.egal("dépôt signé", p["signed"]["repository"], DEPOTS[cas])
    L.egal("empreinte OpenPGP", p["openpgp"]["fingerprint"], a["empreinte"])
    L.egal("sha256 de la clé publique", p["openpgp"]["publicKeySha256"], a["cle_sha"])
    fp, _ = L.empreinte_v4(L.FICHIERS["cle"])
    L.egal("empreinte recalculée de cle-publique.asc", fp, a["empreinte"])
    ns = lire_layout(non_signe, a[f"{o}_manifeste"])
    nom = RPM if o == "rpm" else DEB
    if sorted(ns) != [nom]:
        raise Refus(f"image non signée : membres {sorted(ns)[:3]}")
    L.egal("fichier de l'image non signée (lu)", h(ns[nom]), a[f"{o}_fichier"])
    f = lire_layout(signe, digest)
    membres_controles(cas, f, a)
    if cas == "rpm":
        L.egal("fichier signé du prédicat", p["signed"]["file"]["sha256"], a["rpm_signe"])
        ls, nsg, ps, _ = rpm_parties(f[RPM], "signé")
        le, ne, pe, _ = rpm_parties(ns[nom], "non signé")
        print(f"     B1 recalculé : signé {nsg} entrées de signature, en-tête principal à l'octet {ps} ; non signé {ne}, à l'octet {pe}")
        if ls != le or f[RPM][ps:] != ns[nom][pe:]:
            raise Refus("B1 : lead ou octets à partir de l'en-tête principal différents")
        L.egal("en-tête principal du prédicat", p["b1"]["mainHeaderOffset"], ps)
        print(f"OK   B1 recalculé sur les octets lus : lead égal, {len(f[RPM]) - ps} octets égaux à partir de l'en-tête principal")
    elif cas == "deb":
        L.egal("identité : manifeste publié", digest, a["deb_manifeste"])
        L.egal("fichier signé du prédicat", p["signed"]["file"]["sha256"], a["deb_fichier"])
    else:
        vus = [{"path": k, "sha256": h(f[k])} for k in sorted(f)]
        if p.get("covers") != vus:
            raise Refus(f"dépôt : liste couverte ≠ membres lus ({len(p.get('covers') or [])} et {len(vus)} entrées)")
        L.egal("racine du dépôt", p["signed"]["root"], RACINES[cas])
        print(f"OK   dépôt : {len(vus)} fichiers couverts = membres lus")
    print("ACCEPTÉ")


def rpm_parties(d, nom):
    if d[:4] != b"\xed\xab\xee\xdb" or d[96:99] != b"\x8e\xad\xe8":
        raise Refus(f"B1 : rpm {nom} sans lead ou sans en-tête de signature")
    n, taille = int.from_bytes(d[104:108], "big"), int.from_bytes(d[108:112], "big")
    principal = (96 + 16 + 16 * n + taille + 7) // 8 * 8
    if d[principal:principal + 3] != b"\x8e\xad\xe8":
        raise Refus(f"B1 : rpm {nom} : pas d'en-tête principal à l'octet {principal}")
    return d[:96], n, principal, d


def main():
    m, x = (sys.argv[1] if len(sys.argv) > 1 else ""), sys.argv[2:]
    try:
        if m == "attendus" and not x:  # valeurs archivées (remplacées au banc seulement), au format de o5-lien.py attendus
            for k, v in sorted(attendus().items()):
                print(f"     {k} : {v}")
        elif m == "extraire" and len(x) == 2:  # l'énoncé de lien unique d'une sortie de verify-attestation, pour l'archiver
            st = enonces_lien(x[0])
            with open(x[1], "w", encoding="utf-8") as o:
                json.dump(st, o, indent=2, ensure_ascii=False, sort_keys=True)
                o.write("\n")
        elif m == "construire" and len(x) == 1:
            construire(*x)
        elif m == "predicats" and len(x) == 3:
            predicats(*x)
        elif m == "temoins" and len(x) == 2:
            temoins(*x)
        elif m == "enonce" and len(x) == 3:
            enonce(*x)
        elif m == "controle" and len(x) == 5 and x[0] in DEPOTS:
            controle(*x)
        else:
            sys.exit("usage : o5-signes.py construire SORTIE | predicats LAYOUTS CHAINS SORTIE | temoins LAYOUTS SORTIE"
                     " | enonce CAS PREDICAT DIGEST | controle CAS ENVELOPPES DIGEST SIGNE NON_SIGNE")
    except Refus as r:
        print(f"REFUS {r}")
        sys.exit(3)
    except Exception as e:  # noqa: BLE001
        print(f"KO   erreur : {type(e).__name__} : {e}")
        sys.exit(2)


if __name__ == "__main__":
    main()
