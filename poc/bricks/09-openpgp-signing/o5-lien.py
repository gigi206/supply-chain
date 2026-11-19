#!/usr/bin/env python3
# Brique 09, O5 à sec : prédicats des énoncés de lien et contrôle indépendant, sur l'hôte, sans réseau, sans rpm ni gpg.
# Toute valeur attendue est relue dans un journal archivé (motif trouvé avec une seule valeur), jamais écrite dans ce fichier.
#   attendus                          relit les valeurs archivées et contrôle les fichiers gardés d'O3 et d'O4 (prealables)
#   predicats DOSSIER                 écrit les quatre prédicats (rpm, deb, depot-rpm, depot-apt), comme le ferait le service
#   temoins DOSSIER                   écrit les prédicats faux (autre manifeste, autre fichier) et le rpm à charge altérée
#   controle CAS BUNDLE FICHIER       contrôle indépendant d'un bundle cosign déjà vérifié : forme, sujet, lien, B1 recalculé,
#                                     dépôt recalculé ; code 0 si accepté, 3 si refusé (ligne « REFUS <motif> »), 2 si erreur
# Usage : python3 -I o5-lien.py <mode> … (lancé par o5.sh)
import base64
import gzip
import hashlib
import json
import os
import re
import struct
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
R = os.path.join(ICI, "resultats")
BRIQUES = os.path.dirname(ICI)
BASE = os.path.expanduser("~/.cache/supply-chain-poc/09")
TYPE = "https://supply-chain.example/lien-openpgp/v1"
ENONCE = "https://in-toto.io/Statement/v0.1"  # valeur écrite par cosign 3.1.4 attest-blob (mesurée, o5-banc-premier-passage.log)
RPM = "sample-app-1.0.0-2.el9.x86_64.rpm"
DEB = "sample-app_1.0.0-2_amd64.deb"
O3 = os.path.join(BASE, "o3/signer")
O4 = os.path.join(BASE, "o4/signer")
FICHIERS = {
    "rpm": os.path.join(O3, "depot", RPM),
    "rpm-entree": os.path.join(O3, "entree", RPM),
    "depot-rpm": os.path.join(O3, "depot"),
    "deb": os.path.join(O4, "depot/pool/main/s/sample-app", DEB),
    "depot-apt": os.path.join(O4, "depot"),
    "cle": os.path.join(O4, "cle-publique.asc"),
}
H64 = "[0-9a-f]{64}"


class Refus(Exception):
    pass


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def archive(log, motif):
    """Valeur unique du groupe 1 de `motif` dans un journal archivé ; arrêt si absente ou ambiguë."""
    t = open(os.path.join(BRIQUES, log), encoding="utf-8").read()
    v = set(re.findall(motif, t, re.M))
    if len(v) != 1:
        sys.exit(f"KO   {log} : motif {motif!r} : {len(v)} valeur(s) distincte(s), une attendue")
    return v.pop()


def attendus():
    a = {}
    a["rpm_manifeste"] = archive("05-rpm-mock/resultats/m4c-comparaison.log",
                                 rf"^OK   manifeste : sha256 des octets lus : (sha256:{H64})$")
    a["rpm_fichier"] = archive("05-rpm-mock/resultats/m4c-comparaison.log",
                               rf"^OK   rpm tiré égal à celui de M3 \(sha256\) : ({H64})$")
    a["deb_manifeste"] = archive("06-deb-sbuild/resultats/s4d-pipeline.log",
                                 rf"^OK   artefact égal au digest attendu \(prealables\) : (sha256:{H64})$")
    a["deb_fichier"] = archive("06-deb-sbuild/resultats/s4d-pipeline.log",
                               rf"deb produit : {re.escape(DEB)} ({H64}) ")
    p3 = "09-openpgp-signing/resultats/o3-signer.log"
    a["rpm_signe"] = archive(p3, rf"^produits : rpm signé ({H64}) ;")
    a["repomd"] = archive(p3, rf"^produits : .* ; repomd\.xml ({H64}) ;")
    a["repomd_asc"] = archive(p3, rf"^produits : .* ; repomd\.xml\.asc ({H64})")
    a["b1_ok"] = archive(p3, r"^(OK   B1 : octets égaux à partir de l'en-tête principal) ")
    a["b1_principal"] = int(archive(p3, rf"^ +signé  : \d+ octets, sha256 {a['rpm_signe']}, en-tête de signature à \d+ entrées,"
                                        r" en-tête principal à l'octet (\d+)$"))
    a["outils_rpm"] = archive(p3, r"^outils : (rpm-\S+ rpm-sign-.+)$")  # signature ; la ligne « outils » de la vérification n'a pas rpm-sign
    p4 = "09-openpgp-signing/resultats/o4-signer.log"
    a["inrelease"] = archive(p4, rf"^produits : InRelease ({H64}) ;")
    a["release"] = archive(p4, rf"^produits : .* ; Release ({H64}) ;")
    a["release_gpg"] = archive(p4, rf"^produits : .* ; Release\.gpg ({H64})")
    a["outils_deb"] = archive(p4, r"^outils : (.+)$")
    p2 = "09-openpgp-signing/resultats/o2-cle.log"
    a["empreinte"] = archive(p2, r"^empreinte créée : ([0-9A-F]{40})$")
    a["cle_sha"] = archive(p2, rf"cle-publique\.asc : 600 [0-9]+ \(mode, octets\), sha256 ({H64})")
    return a


def empreinte_v4(asc):
    """Empreinte v4 du premier paquet de clé publique d'un certificat armuré, calculée sans gpg."""
    lignes = open(asc, encoding="ascii").read().splitlines()
    if "-----BEGIN PGP PUBLIC KEY BLOCK-----" not in lignes:
        raise Refus("clé : pas de bloc de clé publique armuré")
    i = lignes.index("-----BEGIN PGP PUBLIC KEY BLOCK-----") + 1
    while lignes[i].strip():
        i += 1
    b64 = []
    for l in lignes[i + 1:]:
        if l.startswith("=") or l.startswith("-----END"):
            break
        b64.append(l.strip())
    d = base64.b64decode("".join(b64))
    t = d[0]
    if t & 0x40:  # format nouveau
        tag, n = t & 0x3F, d[1]
        if n < 192:
            corps = d[2:2 + n]
        elif n < 224:
            n = ((n - 192) << 8) + d[2] + 192
            corps = d[3:3 + n]
        else:
            n = struct.unpack(">I", d[2:6])[0]
            corps = d[6:6 + n]
    else:  # format ancien
        tag, lt = (t >> 2) & 0x0F, t & 0x03
        if lt == 0:
            n, corps = d[1], d[2:2 + d[1]]
        elif lt == 1:
            n = struct.unpack(">H", d[1:3])[0]
            corps = d[3:3 + n]
        else:
            n = struct.unpack(">I", d[1:5])[0]
            corps = d[5:5 + n]
    if tag != 6 or corps[0] != 4:
        raise Refus(f"clé : premier paquet de tag {tag}, version {corps[0]} (clé publique v4 attendue)")
    return hashlib.sha1(b"\x99" + struct.pack(">H", len(corps)) + corps).hexdigest().upper(), corps[5]


def rpm_parties(p):
    """(lead, entrées de l'en-tête de signature, début de l'en-tête principal, octets) lus sans rpm."""
    d = open(p, "rb").read()
    if d[:4] != b"\xed\xab\xee\xdb":
        raise Refus(f"B1 : {os.path.basename(p)} n'a pas le lead d'un rpm")
    if d[96:99] != b"\x8e\xad\xe8":
        raise Refus(f"B1 : {os.path.basename(p)} : pas d'en-tête de signature à l'octet 96")
    n, taille = struct.unpack(">II", d[104:112])
    fin = 96 + 16 + 16 * n + taille
    principal = (fin + 7) // 8 * 8
    if d[principal:principal + 3] != b"\x8e\xad\xe8":
        raise Refus(f"B1 : {os.path.basename(p)} : pas d'en-tête principal à l'octet {principal}")
    return d[:96], n, principal, d


def b1(signe, entree):
    ls, ns, ps, ds = rpm_parties(signe)
    le, ne, pe, de = rpm_parties(entree)
    print(f"     B1 recalculé : signé {ns} entrées de signature, en-tête principal à l'octet {ps} ;"
          f" entrée {ne} entrées, en-tête principal à l'octet {pe}")
    if ls != le:
        raise Refus("B1 : lead différent")
    if ds[ps:] != de[pe:]:
        k = next((i for i, (x, y) in enumerate(zip(ds[ps:], de[pe:])) if x != y), min(len(ds) - ps, len(de) - pe))
        raise Refus(f"B1 : octets différents à partir de l'en-tête principal (premier écart à {k} octets de son début ;"
                    f" longueurs {len(ds) - ps} et {len(de) - pe})")
    print(f"OK   B1 recalculé : lead égal, {len(ds) - ps} octets égaux à partir de l'en-tête principal")


def couverts(racine, sujet):
    r = []
    for d, _, fs in os.walk(racine):
        for f in sorted(fs):
            p = os.path.join(d, f)
            if os.path.abspath(p) != os.path.abspath(sujet):
                r.append({"path": os.path.relpath(p, racine), "sha256": sha(p)})
    return sorted(r, key=lambda x: x["path"])


def predicats(dossier):
    a = attendus()
    cle_sha = sha(FICHIERS["cle"])
    openpgp = {"fingerprint": a["empreinte"], "publicKeySha256": cle_sha}
    chains = "non vérifiée : banc hors cluster, sans Zot (le service la vérifierait avant de signer, D3 a)"
    rpm_origine = {"manifest": a["rpm_manifeste"], "file": {"name": RPM, "sha256": a["rpm_fichier"]}}
    deb_origine = {"manifest": a["deb_manifeste"], "file": {"name": DEB, "sha256": a["deb_fichier"]}}
    p = {
        "rpm": {"link": "rpm-b1", "unsigned": rpm_origine, "openpgp": openpgp,
                "b1": {"source": "poc/bricks/09-openpgp-signing/resultats/o3-signer.log",
                       "mainHeaderOffset": a["b1_principal"], "equalFromMainHeader": True},
                "tools": a["outils_rpm"], "chainsProvenance": chains},
        "deb": {"link": "identity", "unsigned": deb_origine, "openpgp": openpgp,
                "tools": a["outils_deb"], "chainsProvenance": chains},
        "depot-rpm": {"link": "repository", "unsigned": rpm_origine, "openpgp": openpgp,
                      "covers": couverts(FICHIERS["depot-rpm"], os.path.join(FICHIERS["depot-rpm"], "repodata/repomd.xml")),
                      "tools": a["outils_rpm"], "chainsProvenance": chains},
        "depot-apt": {"link": "repository", "unsigned": deb_origine, "openpgp": openpgp,
                      "covers": couverts(FICHIERS["depot-apt"], os.path.join(FICHIERS["depot-apt"], "dists/poc/InRelease")),
                      "tools": a["outils_deb"], "chainsProvenance": chains},
    }
    os.makedirs(dossier, exist_ok=True)
    for c, v in p.items():
        with open(os.path.join(dossier, f"{c}.json"), "w", encoding="utf-8") as f:
            json.dump(v, f, indent=2, ensure_ascii=False, sort_keys=True)
            f.write("\n")
        print(f"     prédicat {c} : lien {v['link']}, origine {v['unsigned']['manifest'][:19]}… / {v['unsigned']['file']['sha256'][:16]}…"
              + (f", {len(v['covers'])} fichiers couverts" if "covers" in v else ""))


def temoins(dossier):
    a = attendus()
    base = json.load(open(os.path.join(dossier, "rpm.json"), encoding="utf-8"))
    for nom, champ, valeur in (("rpm-autre-manifeste", "manifest", a["deb_manifeste"]),
                               ("rpm-autre-fichier", "file", {"name": RPM, "sha256": a["deb_fichier"]})):
        v = json.loads(json.dumps(base))
        v["unsigned"][champ] = valeur
        with open(os.path.join(dossier, f"{nom}.json"), "w", encoding="utf-8") as f:
            json.dump(v, f, indent=2, ensure_ascii=False, sort_keys=True)
            f.write("\n")
        print(f"     prédicat {nom} : unsigned.{champ} remplacé par une valeur archivée du deb")
    d = bytearray(open(FICHIERS["rpm"], "rb").read())
    d[-1] ^= 0x01
    sortie = os.path.join(dossier, "rpm-altere.rpm")
    with open(sortie, "wb") as f:
        f.write(d)
    print(f"     rpm à charge altérée : dernier octet ({len(d) - 1}) inversé au bit 0 ; sha256 {sha(sortie)}")


def enonce(bundle):
    b = json.load(open(bundle, encoding="utf-8"))
    env = b.get("dsseEnvelope")
    if not isinstance(env, dict):
        raise Refus(f"forme : pas de dsseEnvelope (clés : {sorted(b)})")
    if env.get("payloadType") != "application/vnd.in-toto+json":
        raise Refus(f"forme : payloadType {env.get('payloadType')!r}")
    e = json.loads(base64.b64decode(env["payload"]))
    if e.get("_type") != ENONCE:
        raise Refus(f"forme : _type {e.get('_type')!r}")
    if e.get("predicateType") != TYPE:
        raise Refus(f"forme : predicateType {e.get('predicateType')!r}")
    print(f"OK   forme : bundle {b.get('mediaType')}, énoncé {ENONCE}, prédicat {TYPE}")
    return e


def egal(libelle, vu, attendu):
    if vu != attendu:
        raise Refus(f"lien : {libelle} {str(vu)[:80]} (attendu : {str(attendu)[:80]})")
    print(f"OK   lien : {libelle} égal à la valeur archivée ({str(attendu)[:23]}…)")


def controle(cas, bundle, fichier):
    a = attendus()
    e = enonce(bundle)
    s = e.get("subject") or []
    if len(s) != 1:
        raise Refus(f"sujet : {len(s)} sujets, un attendu")
    h = sha(fichier)
    if s[0].get("digest", {}).get("sha256") != h:
        raise Refus(f"sujet : sha256 {s[0].get('digest', {}).get('sha256', '-')[:16]}… ≠ fichier en main {h[:16]}…")
    print(f"OK   sujet : {s[0].get('name')} = fichier en main ({h[:16]}…)")
    p = e["predicate"]
    rpm = cas in ("rpm", "depot-rpm")
    egal("manifeste non signé", p["unsigned"]["manifest"], a["rpm_manifeste" if rpm else "deb_manifeste"])
    egal("fichier non signé", p["unsigned"]["file"]["sha256"], a["rpm_fichier" if rpm else "deb_fichier"])
    egal("empreinte OpenPGP", p["openpgp"]["fingerprint"], a["empreinte"])
    fp, _ = empreinte_v4(FICHIERS["cle"])
    egal("empreinte recalculée de cle-publique.asc", fp, a["empreinte"])
    egal("sha256 de cle-publique.asc", sha(FICHIERS["cle"]), a["cle_sha"])
    if cas == "rpm":
        egal("nature du lien", p["link"], "rpm-b1")
        ent = FICHIERS["rpm-entree"]
        egal("rpm d'entrée en main", sha(ent), a["rpm_fichier"])
        b1(fichier, ent)
    elif cas == "deb":
        egal("nature du lien", p["link"], "identity")
        egal("deb en main (identité)", h, a["deb_fichier"])
    else:
        egal("nature du lien", p["link"], "repository")
        racine = FICHIERS[cas]
        vus = couverts(racine, fichier)
        if p["covers"] != vus:
            raise Refus(f"dépôt : liste couverte ≠ fichiers en main ({len(p['covers'])} et {len(vus)} entrées)")
        print(f"OK   dépôt : {len(vus)} fichiers couverts, tous égaux aux fichiers en main")
        f = {c["path"]: c["sha256"] for c in vus}
        if cas == "depot-rpm":
            egal("repomd.xml (sujet)", h, a["repomd"])
            egal("repomd.xml.asc", f.get("repodata/repomd.xml.asc"), a["repomd_asc"])
            egal("rpm signé du dépôt", f.get(RPM), a["rpm_signe"])
            x = open(fichier, encoding="utf-8").read()
            n = 0
            for somme, loc in re.findall(r'<checksum type="sha256">([0-9a-f]{64})</checksum>.*?<location href="([^"]+)"/>', x, re.S):
                if f.get(loc) != somme:
                    raise Refus(f"dépôt : {loc} : sha256 ≠ repomd.xml")
                n += 1
            if n == 0:
                raise Refus("dépôt : aucune entrée sha256 lue dans repomd.xml")
            prim = [c for c in f if c.endswith("-primary.xml.gz")]
            if len(prim) != 1:
                raise Refus(f"dépôt : {len(prim)} primary.xml.gz")
            pk = re.findall(r'<checksum type="sha256" pkgid="YES">([0-9a-f]{64})</checksum>',
                            gzip.open(os.path.join(racine, prim[0])).read().decode())
            egal("rpm dans primary.xml.gz", pk, [a["rpm_signe"]])
            print(f"OK   dépôt : chaîne repomd.xml → {n} fichiers de repodata → primary → rpm signé")
        else:
            egal("InRelease (sujet)", h, a["inrelease"])
            egal("Release", f.get("dists/poc/Release"), a["release"])
            egal("Release.gpg", f.get("dists/poc/Release.gpg"), a["release_gpg"])
            rel = open(os.path.join(racine, "dists/poc/Release"), encoding="utf-8").read()
            sec = rel.split("\nSHA256:\n", 1)[1].split("\n")
            n = 0
            for l in sec:
                m = re.match(r"^ ([0-9a-f]{64}) +\d+ (\S+)$", l)
                if not m:
                    break
                if f.get("dists/poc/" + m.group(2)) != m.group(1):
                    raise Refus(f"dépôt : {m.group(2)} : sha256 ≠ Release")
                n += 1
            if n == 0:
                raise Refus("dépôt : aucune entrée lue dans la section SHA256 de Release")
            pkgs = open(os.path.join(racine, "dists/poc/main/binary-amd64/Packages"), encoding="utf-8").read()
            egal("deb dans Packages", re.findall(r"^SHA256: ([0-9a-f]{64})$", pkgs, re.M), [a["deb_fichier"]])
            egal("deb du dépôt", f.get(f"pool/main/s/sample-app/{DEB}"), a["deb_fichier"])
            print(f"OK   dépôt : chaîne Release → {n} index → Packages → deb")
    print("ACCEPTÉ")


def main():
    m = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if m == "attendus":
            a = attendus()
            for k in sorted(a):
                print(f"     {k} : {a[k]}")
            for nom, cle in (("rpm signé", "rpm_signe"), ("rpm d'entrée", "rpm_fichier"), ("deb", "deb_fichier")):
                p = FICHIERS[{"rpm_signe": "rpm", "rpm_fichier": "rpm-entree", "deb_fichier": "deb"}[cle]]
                egal(f"{nom} gardé ({os.path.relpath(p, BASE)})", sha(p), a[cle])
            egal("repomd.xml gardé", sha(os.path.join(FICHIERS["depot-rpm"], "repodata/repomd.xml")), a["repomd"])
            egal("repomd.xml.asc gardé", sha(os.path.join(FICHIERS["depot-rpm"], "repodata/repomd.xml.asc")), a["repomd_asc"])
            for n, k in (("InRelease", "inrelease"), ("Release", "release"), ("Release.gpg", "release_gpg")):
                egal(f"{n} gardé", sha(os.path.join(FICHIERS["depot-apt"], "dists/poc", n)), a[k])
            egal("cle-publique.asc gardée", sha(FICHIERS["cle"]), a["cle_sha"])
            fp, algo = empreinte_v4(FICHIERS["cle"])
            egal(f"empreinte v4 recalculée sans gpg (algorithme {algo})", fp, a["empreinte"])
        elif m == "predicats":
            predicats(sys.argv[2])
        elif m == "temoins":
            temoins(sys.argv[2])
        elif m == "controle":
            controle(sys.argv[2], sys.argv[3], sys.argv[4])
        elif m == "extraire":  # énoncé d'un bundle (sans signature ni clé), pour l'archiver
            b = json.load(open(sys.argv[2], encoding="utf-8"))
            e = json.loads(base64.b64decode(b["dsseEnvelope"]["payload"]))
            with open(sys.argv[3], "w", encoding="utf-8") as f:
                json.dump(e, f, indent=2, ensure_ascii=False, sort_keys=True)
                f.write("\n")
            print(f"     énoncé archivé : {os.path.basename(sys.argv[3])} ; mediaType du bundle {b.get('mediaType')} ;"
                  f" verificationMaterial : {', '.join(sorted(b.get('verificationMaterial', {})))}")
        else:
            sys.exit("usage : o5-lien.py attendus | predicats DOSSIER | temoins DOSSIER | controle CAS BUNDLE FICHIER"
                     " | extraire BUNDLE SORTIE")
    except Refus as r:
        print(f"REFUS {r}")
        sys.exit(3)
    except Exception as x:  # noqa: BLE001
        print(f"KO   erreur : {type(x).__name__} : {x}")
        sys.exit(2)


if __name__ == "__main__":
    main()
