"""Brique 07b, tranche 1 : banc local de systemd/entrees-scan.py, avec un faux Zot (la fonction lire est remplacée).
Appelé par 07b-t1-banc.sh, qui calcule les comptes attendus avec jq, indépendamment de ce script.
Usage : python3 -I 07b-t1-banc.py <entrees-scan.py> <attendus.json> <témoin app> <témoin deb> <témoin G6 (prédicat seul)>"""
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import urllib.error

SCRIPT, ATTENDUS, F_APP, F_DEB, F_G6 = sys.argv[1:6]
A = json.load(open(ATTENDUS, encoding="utf-8"))
spec = importlib.util.spec_from_file_location("entrees_scan", SCRIPT)
E = importlib.util.module_from_spec(spec)
spec.loader.exec_module(E)
APP = json.load(open(F_APP, encoding="utf-8"))
DEB = json.load(open(F_DEB, encoding="utf-8"))
D_APP = "sha256:" + APP["subject"][0]["digest"]["sha256"]
D_DEB = "sha256:" + DEB["subject"][0]["digest"]["sha256"]
D_G6 = "sha256:" + "6" * 64
G6 = {"_type": "https://in-toto.io/Statement/v1", "subject": [{"name": "temoin-g6", "digest": {"sha256": "6" * 64}}],
      "predicateType": E.PREDICAT, "predicate": json.load(open(F_G6, encoding="utf-8"))}
SENTINELLE = b"sentinelle 1\n"
KO = 0


def zot(depots):
    """depots : {dépôt : (digest du sujet, énoncé, retouche)} ; retouche(bundle, couche) peut altérer ce que sert le faux Zot."""
    pages = {}
    for depot, (sujet, enonce, retouche) in depots.items():
        if enonce is None:
            pages[f"{depot}/referrers/{sujet}"] = {"manifests": []}
            continue
        bundle = {"mediaType": E.BUNDLE, "dsseEnvelope": {"payloadType": E.INTOTO, "signatures": [{"sig": "faux"}],
                                                          "payload": base64.b64encode(json.dumps(enonce).encode()).decode()}}
        couche = {"mediaType": E.BUNDLE}
        if retouche:
            retouche(bundle, couche)
        blob = json.dumps(bundle).encode()
        couche.setdefault("digest", "sha256:" + hashlib.sha256(blob).hexdigest())
        neuf, vieux = "sha256:" + "a" * 64, "sha256:" + "b" * 64
        pages[f"{depot}/referrers/{sujet}"] = {"manifests": [
            {"digest": vieux, "annotations": {"dev.sigstore.bundle.predicateType": E.PREDICAT,
                                              "org.opencontainers.image.created": "2026-11-01T00:00:00Z"}},
            {"digest": neuf, "annotations": {"dev.sigstore.bundle.predicateType": E.PREDICAT,
                                             "org.opencontainers.image.created": "2026-11-21T00:00:00Z"}},
            {"digest": "sha256:" + "c" * 64, "annotations": {"dev.sigstore.bundle.predicateType": "https://autre/v1",
                                                             "org.opencontainers.image.created": "2026-11-30T00:00:00Z"}}]}
        pages[f"{depot}/manifests/{neuf}"] = {"layers": [couche]}
        pages[f"{depot}/blobs/{couche['digest']}"] = blob
    def lire(chemin, accepte="application/json"):
        if chemin not in pages:
            raise urllib.error.URLError(f"faux Zot : {chemin} absent")
        v = pages[chemin]
        return v if isinstance(v, bytes) else json.dumps(v).encode()
    return lire


def lancer(T, depots, scans, nom):
    E.lire = zot(depots)
    os.environ["SCANS"] = " ".join(f"{d}@{s}" for d, s in scans)
    os.environ["SORTIE"], os.environ["ETAT"] = os.path.join(T, "s.prom"), os.path.join(T, "etat")
    sortie = io.StringIO()
    try:
        with contextlib.redirect_stdout(sortie), contextlib.redirect_stderr(io.StringIO()):
            rc = E.main()
    except Exception as x:  # comme sous systemd : exception non rattrapée, code 1
        rc = f"1 ({type(x).__name__})"
    lignes = sortie.getvalue().splitlines()
    liste = [json.loads(l) for l in lignes if l.startswith("{")]
    resume = [l for l in lignes if not l.startswith("{")]
    prom = open(os.environ["SORTIE"], "rb").read()
    print(f"-- {nom} : rc {rc}, {len(liste)} lignes d'entrée, résumé {resume}")
    return rc, liste, resume, prom


def verifier(nom, cond, detail=""):
    global KO
    print(("OK   " if cond else "KO   ") + nom + (f" ({detail})" if detail and not cond else ""))
    KO += 0 if cond else 1


def series(prom, depot):
    t = prom.decode()
    v = {}
    for l in t.splitlines():
        if f'depot="{depot}"' in l:
            cle, val = l.rsplit(" ", 1)
            v[cle.split("{")[0] + (cle.split('gravite="')[1].split('"')[0] if "gravite" in cle else "")] = int(val)
    return v


def attendu_series(a):
    v = {f"scan_entrees{g}": a["g"].get(g, 0) for g in E.GRAVITES}
    v.update(scan_entrees_kev=a["kev"], scan_entrees_avec_correctif=a["fix"], scan_entrees_scanne_timestamp_seconds=a["t"])
    return v


with tempfile.TemporaryDirectory(dir=os.path.expanduser("~/.cache/supply-chain-poc/07a")) as T:
    os.mkdir(os.path.join(T, "etat"))
    open(os.path.join(T, "s.prom"), "wb").write(SENTINELLE)
    deux = {"builds/scan/sample-app": (D_APP, APP, None), "builds/scan/sample-app-deb": (D_DEB, DEB, None)}
    scans2 = [("builds/scan/sample-app", D_APP), ("builds/scan/sample-app-deb", D_DEB)]

    rc, liste, resume, prom = lancer(T, deux, scans2, "C1 deux témoins réels, état vide")
    verifier("C1 rc 0", rc == 0)
    verifier("C1 séries de sample-app = jq", series(prom, "builds/scan/sample-app") == attendu_series(A["app"]),
             f"{series(prom, 'builds/scan/sample-app')} contre {attendu_series(A['app'])}")
    verifier("C1 séries de sample-app-deb = jq", series(prom, "builds/scan/sample-app-deb") == attendu_series(A["deb"]),
             f"{series(prom, 'builds/scan/sample-app-deb')} contre {attendu_series(A['deb'])}")
    verifier("C1 grille fixe : 7 gravités par dépôt, zéros écrits", prom.decode().count('scan_entrees{') == 14)
    verifier("C1 liste émise : app + deb lignes", len(liste) == A["app"]["n"] + A["deb"]["n"], len(liste))
    verifier("C1 dépôt et scannedAt dans chaque ligne", all(l["depot"] and l["scannedAt"] for l in liste))
    verifier("C1 aucune ligne sans id ni package", all(l["id"] and l["package"] for l in liste))
    verifier("C1 « scanne » de chaque ligne = scannedAt de jq du dépôt (clé de jointure)",
             all(l["scanne"] == A["app" if l["depot"] == "builds/scan/sample-app" else "deb"]["t"] for l in liste))
    verifier("C1 résumé : deux listes émises", len(resume) == 1 and resume[0].count("(liste émise)") == 2, resume)
    p1 = prom

    rc, liste, resume, prom = lancer(T, deux, scans2, "C2 même état, second passage")
    verifier("C2 rc 0, aucune ligne d'entrée, comptes identiques", rc == 0 and liste == [] and prom == p1)
    verifier("C2 résumé sans « liste émise »", "(liste émise)" not in resume[0], resume)

    open(os.path.join(T, "s.prom"), "wb").write(SENTINELLE)
    rc, liste, resume, prom = lancer(T, {"temoin/g6": (D_G6, G6, None)}, [("temoin/g6", D_G6)], "C3 témoin KEV de G6")
    verifier("C3 séries = jq (KEV comprises)", rc == 0 and series(prom, "temoin/g6") == attendu_series(A["g6"]),
             f"{series(prom, 'temoin/g6')} contre {attendu_series(A['g6'])}")
    verifier("C3 lignes KEV dans la liste = jq", sum(1 for l in liste if l["kev"]) == A["g6"]["kev"])
    verifier("C3 « scanne » = jq malgré le décalage +01:00", all(l["scanne"] == A["g6"]["t"] for l in liste))

    vide = json.loads(json.dumps(APP))
    vide["predicate"]["vulnerabilities"] = []
    rc, liste, resume, prom = lancer(T, {"temoin/vide": (D_APP, vide, None)}, [("temoin/vide", D_APP)], "C4 prédicat sans entrée")
    s = series(prom, "temoin/vide")
    verifier("C4 zéros écrits partout, scannedAt présent",
             rc == 0 and liste == [] and all(s[f"scan_entrees{g}"] == 0 for g in E.GRAVITES) and s["scan_entrees_kev"] == 0
             and s["scan_entrees_scanne_timestamp_seconds"] == A["app"]["t"], s)

    rc, liste, resume, prom = lancer(T, {"temoin/sans": (D_APP, None, None), **deux},
                                     [("temoin/sans", D_APP)] + scans2, "C5 un dépôt sans referrer de scan")
    verifier("C5 rc 0, séries du dépôt absentes, les autres écrites",
             rc == 0 and 'depot="temoin/sans"' not in prom.decode() and prom == p1)
    verifier("C5 résumé « aucun »", "temoin/sans=aucun" in resume[0], resume)

    def refus(nom, depots, scans, attendu_rc):
        open(os.path.join(T, "s.prom"), "wb").write(SENTINELLE)
        rc, liste, resume, prom = lancer(T, depots, scans, nom)
        verifier(f"{nom.split()[0]} rc {attendu_rc}, fichier inchangé, aucune ligne d'entrée",
                 str(rc).startswith(str(attendu_rc)) and prom == SENTINELLE and liste == [], f"rc {rc}")

    refus("C6 lecture impossible (referrers absents du faux Zot)", deux, scans2 + [("temoin/absent", D_APP)], 1)
    autre = json.loads(json.dumps(APP))
    autre["subject"][0]["digest"]["sha256"] = "f" * 64
    refus("C7 sujet de l'énoncé différent", {"t/s": (D_APP, autre, None)}, [("t/s", D_APP)], 2)
    refus("C8 payloadType faux", {"t/p": (D_APP, APP, lambda b, c: b["dsseEnvelope"].update(payloadType="text/plain"))},
          [("t/p", D_APP)], 2)
    refus("C9 empreinte du bundle fausse", {"t/e": (D_APP, APP, lambda b, c: c.update(digest="sha256:" + "0" * 64))},
          [("t/e", D_APP)], 2)
    refus("C10 couche d'un autre type", {"t/c": (D_APP, APP, lambda b, c: c.update(mediaType="application/json"))},
          [("t/c", D_APP)], 2)
    pt = json.loads(json.dumps(APP))
    pt["predicateType"] = "https://autre/v1"
    refus("C11 predicateType de l'énoncé différent", {"t/t": (D_APP, pt, None)}, [("t/t", D_APP)], 2)

    hors = json.loads(json.dumps(APP))
    hors["predicate"]["vulnerabilities"][0]["severity"] = "Grave"
    rc, liste, resume, prom = lancer(T, {"t/h": (D_APP, hors, None)}, [("t/h", D_APP)], "C12 gravité hors grille")
    s = series(prom, "t/h")
    verifier("C12 rangée dans « autre », total conservé", rc == 0 and s["scan_entreesautre"] == 1
             and sum(s[f"scan_entrees{g}"] for g in E.GRAVITES) == A["app"]["n"], s)

print(f"## bilan du banc : {KO} KO")
sys.exit(1 if KO else 0)
