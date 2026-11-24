#!/usr/bin/python3 -I
"""Brique 20 : exportateur des KPI supply-chain (docs/02 §7, « tools/metrics-exporter dérive les métriques des attestations »).
Bibliothèque standard seulement, lectures anonymes de Zot par HTTPS, même motif que entrees-scan.py (07b). Ni git, ni cosign, ni secret.
  SIGNATURES, obligatoire et sans défaut (décision du propriétaire du 24/11 : « openssl (Recommandé) », donc « verifiees » en service) :
    - « comptees » : signatures NON vérifiées, les énoncés sont comptés, pas prouvés (comportement de l'étape 3) ;
    - « verifiees » : /usr/bin/openssl dgst -verify (ECDSA P-256) sur le PAE de l'enveloppe DSSE et, pour la signature d'image, sur les
      octets de la couche ; une clé par famille (CLES/chains.pub, scanner.pub, vsa.pub, vex.pub), jamais « l'une des quatre ». Une
      signature fausse, absente ou illisible est comptée (kpi_signatures_refusees) et son énoncé ignoré ; une clé absente, illisible ou
      qui n'est pas P-256, ou openssl absent, arrête tout : openssl rend le même code 1 pour une mauvaise clé et une mauvaise signature.
      Avant toute lecture de Zot, un vecteur publié (RFC 6979, A.2.5 ; CLES/vecteur.pub) est vérifié par le même chemin que les vraies
      signatures : accepté tel quel, refusé avec un octet changé, sinon arrêt.
  Le recalcul signé par cosign (poc/bricks/20-kpi/recalcul.py) reste la référence. Horodatage (TSA) non vérifié ; les lignes du JOURNAL
  (délais des KEV) viennent de entrees-scan, qui ne vérifie pas les signatures : « verifiees » ne les couvre pas.
Écrit sans kpi.py, pour que la comparaison avec le recalcul ne compare pas un code à lui-même. Mêmes règles :
  - sujets : PRODUITS, tous les digests vus par un tag ;
  - provenance : couches du .att (builder.id et buildType de Chains, pipelineRef), plus une signature d'image (.sig) qui nomme le digest ;
  - VSA : PASSED du vérifieur attendu ; une seule suffit, même si une FAILED est plus récente (même règle que le recalcul) ;
  - scan : le plus récent par scannedAt ; entrées, écartées par un VEX, KEV, KEV écartées. Aucun scan : séries absentes, jamais 0 ;
  - KEV : ouverture et fermeture, depuis les lignes de entrees-scan (fichier JOURNAL, écrit par un lecteur séparé : aucun secret ici).
    Sans JOURNAL : séries absentes ;
  - dates (RELEVE, relevé de git versionné, poc/bricks/20-kpi/releve/dates-git.tsv) : clés, liées à l'empreinte du fichier de CLES ; pins,
    liés au digest de chaque dépendance de la provenance de PipelineRun la plus récente. Une empreinte ou un digest que le relevé ne
    connaît pas n'a pas de date (série absente) et se compte : kpi_cles_non_relevees, kpi_pins_non_releves. Des dates, jamais des âges.
kpi_exportateur_passage_timestamp_seconds : heure du dernier passage réussi. Un arrêt laisse le fichier inchangé, donc d'anciennes
valeurs : seule cette série le montre.
Un énoncé illisible, ou qui ne nomme pas son sujet ou son type, est compté (kpi_enonces_refuses) et ignoré. Une erreur HTTP, un JSON
de Zot illisible ou une empreinte fausse arrêtent tout, code d'erreur, fichier inchangé.
Variables : REG, CA, PRODUITS (noms séparés par des espaces), SORTIE (fichier .prom, existant), SIGNATURES, CLES (dossier, si
verifiees), JOURNAL (facultatif), RELEVE (facultatif)."""
import base64
import binascii
import datetime
import hashlib
import json
import os
import re
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

BUILDER = "https://supply-chain.example/builders/tekton-chains@v1"
BUILDTYPE = "https://tekton.dev/chains/v2/slsa-tekton"
VERIFIEUR = "https://supply-chain.example/verifiers/replay-poc-administrateur-unique@v1"
PROVENANCE = "https://slsa.dev/provenance/v1"
FAMILLES = {"scan": "https://supply-chain.example/scan/v1", "vsa": "https://slsa.dev/verification_summary/v1",
            "vex": "https://openvex.dev/ns/v0.2.0"}
CLE_DE = {"prov": "chains", "sig": "chains", "scan": "scanner", "vsa": "vsa", "vex": "vex"}
OPENSSL = "/usr/bin/openssl"
# RFC 6979 (août 2013), A.2.5 « ECDSA, 256 Bits (Prime Field) », SHA-256, message « sample ». La signature fait DER_MAX octets.
VECTEUR_PUB = b"""-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEYP7UuiVanTHJYet0xjVtaMBJuJI7
Yfps5mliLmDyn7Z5A/4QCLi8maQa6elWKLxk8vGyDC1+n1F3o8KU1EYimQ==
-----END PUBLIC KEY-----
"""
VECTEUR_SIG = "MEYCIQDv1IsqrLao/RFA3ZzUXoHWnSyHe1aq+ZHDTQ6oTq83FgIhAPfLHJQtZXxB1DbHobbin2Xz6QDbua/0Bk3Eqy+EOs2o"
NOM = re.compile(r"[A-Za-z0-9._:+-]{1,80}")  # valeur d'étiquette qui vient d'un énoncé ou du journal ; toute autre devient « illisible »
DER_MAX = 72  # plus longue signature ECDSA P-256 en DER ; openssl ne lirait pas au-delà
ANNOTATION = "dev.cosignproject.cosign/signature"
INTOTO = "application/vnd.in-toto+json"
ACC = "application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json"
TAG = re.compile(r"sha256-([0-9a-f]{64})\.[a-z]+")


class Refus(Exception):
    pass


def ouvrir(chemin, methode="GET"):
    requete = urllib.request.Request(f"https://{os.environ['REG']}/v2/{chemin}", method=methode, headers={"Accept": ACC})
    return urllib.request.urlopen(requete, timeout=20, context=ssl.create_default_context(cafile=os.environ["CA"]))


def lire(chemin):
    with ouvrir(chemin) as r:
        return json.load(r)


def blob(depot, digest):
    with ouvrir(f"{depot}/blobs/{digest}") as r:
        octets = r.read()
    if "sha256:" + hashlib.sha256(octets).hexdigest() != digest:
        raise Refus(f"{depot} : empreinte du blob {digest[:19]} différente de son digest")
    return octets


def openssl(args, entree=b"", fds=()):
    r = subprocess.run([OPENSSL, *args], input=entree, capture_output=True, timeout=20, env={"LC_ALL": "C"}, pass_fds=fds)
    if r.returncode not in (0, 1):  # signal, ou code jamais vu : ni vérifié ni refusé
        raise Refus(f"openssl {args[0]} : code {r.returncode}")
    return r


def controler_cles():
    """Vrai si les signatures doivent être vérifiées ; clés contrôlées une fois, avant toute lecture de Zot."""
    mode = os.environ.get("SIGNATURES")
    if mode not in ("comptees", "verifiees"):
        raise Refus("SIGNATURES : comptees ou verifiees")
    if mode == "verifiees":
        for nom in sorted(set(CLE_DE.values())):
            r = openssl(["pkey", "-pubin", "-in", f"{os.environ['CLES']}/{nom}.pub", "-noout", "-text"])
            if r.returncode or b"NIST CURVE: P-256" not in r.stdout:
                raise Refus(f"clé {nom}.pub absente, illisible ou pas P-256")
        with open(f"{os.environ['CLES']}/vecteur.pub", "rb") as f:
            if f.read() != VECTEUR_PUB:
                raise Refus("vecteur.pub différent du vecteur attendu")
        if not signature_bonne("vecteur", b"sample", VECTEUR_SIG):
            raise Refus("vecteur de test : signature bonne refusée par openssl")
        if signature_bonne("vecteur", b"samplf", VECTEUR_SIG):
            raise Refus("vecteur de test : signature fausse acceptée par openssl")
    return mode == "verifiees"


def signature_bonne(cle, message, sig):
    """Signature ECDSA en base64 du message, par la clé CLES/<cle>.pub."""
    try:
        der = base64.b64decode(sig, validate=True)
    except (ValueError, TypeError, binascii.Error):
        return False
    if not 0 < len(der) <= DER_MAX:
        return False
    lu, ecrit = os.pipe()  # pas de fichier : l'unité n'a rien à écrire ; 72 octets tiennent dans le tube
    try:
        os.write(ecrit, der)
        os.close(ecrit)
        return openssl(["dgst", "-sha256", "-verify", f"{os.environ['CLES']}/{cle}.pub", "-signature", f"/proc/self/fd/{lu}"],
                       message, (lu,)).returncode == 0
    finally:
        os.close(lu)


def enonce(octets, famille, typ, digest, comptes):
    """Énoncé in-toto d'une enveloppe DSSE ou d'un bundle sigstore, s'il a ce type, nomme ce sujet et, si les signatures sont vérifiées,
    porte une seule signature, bonne ; None sinon. La signature est vérifiée avant que l'énoncé soit lu, sur les octets de la charge."""
    try:
        d = json.loads(octets)
        d = d.get("dsseEnvelope", d)
        charge, typ_charge = base64.b64decode(d["payload"], validate=True), d["payloadType"]
        if typ_charge != INTOTO:
            raise ValueError
        if comptes["verifier"]:
            t = typ_charge.encode()
            try:
                une, = d["signatures"]
                bonne = signature_bonne(CLE_DE[famille], b"DSSEv1 %d %s %d %s" % (len(t), t, len(charge), charge), une["sig"])
            except (ValueError, KeyError, TypeError):
                bonne = False
            if not bonne:
                comptes["refusees"][famille] += 1
                return None
        e = json.loads(charge)
        bon = (e["predicateType"] == typ and isinstance(e["predicate"], dict)
               and any(s["digest"].get("sha256") == digest[7:] for s in e["subject"]))
    except (ValueError, KeyError, TypeError, AttributeError, binascii.Error):
        bon = False
    if not bon:
        comptes["forme"] += 1
        return None
    comptes["verifiees"][famille] += 1
    return e


def epoque(date):
    return int(datetime.datetime.fromisoformat(re.sub(r"(\.[0-9]{6})[0-9]+", r"\1", date).replace("Z", "+00:00")).timestamp())


def digests(depot, tags):
    vus = set()
    for t in tags:
        m = TAG.fullmatch(t)
        if m:
            vus.add("sha256:" + m.group(1))
        else:
            with ouvrir(f"{depot}/manifests/{t}", "HEAD") as r:
                vus.add(r.headers["Docker-Content-Digest"])
    return sorted(vus)


def provenances(depot, digest, tags, comptes):
    """(énoncés de provenance, signature d'image présente)."""
    h, bons, signee = digest[7:], [], False
    if f"sha256-{h}.att" in tags:
        for c in lire(f"{depot}/manifests/sha256-{h}.att")["layers"]:
            e = enonce(blob(depot, c["digest"]), "prov", PROVENANCE, digest, comptes)
            bons += [e] if e else []
    if f"sha256-{h}.sig" in tags:
        for c in lire(f"{depot}/manifests/sha256-{h}.sig")["layers"]:
            octets = blob(depot, c["digest"])
            if comptes["verifier"] and not signature_bonne(CLE_DE["sig"], octets, (c.get("annotations") or {}).get(ANNOTATION)):
                comptes["refusees"]["sig"] += 1
                continue
            try:
                critique = json.loads(octets)["critical"]
                bonne = (critique["type"] == "cosign container image signature" and critique["image"]["docker-manifest-digest"] == digest)
            except (ValueError, KeyError, TypeError):
                comptes["forme"] += 1
                continue
            comptes["verifiees"]["sig"] += bonne
            signee = signee or bonne
    return bons, signee


def referents(famille, nom, digest, catalogue, comptes):
    depot, bons = f"builds/{famille}/{nom}", []
    if depot not in catalogue:
        return bons
    for m in lire(f"{depot}/referrers/{digest}").get("manifests") or []:
        couches = lire(f"{depot}/manifests/{m['digest']}").get("layers") or []
        e = enonce(blob(depot, couches[0]["digest"]) if couches else b"", famille, FAMILLES[famille], digest, comptes)
        bons += [e] if e else []
    return bons


def de_chains(e):
    try:
        p = e["predicate"]
        return (p["runDetails"]["builder"]["id"] == BUILDER and p["buildDefinition"]["buildType"] == BUILDTYPE
                and "pipelineRef" in p["buildDefinition"]["externalParameters"].get("runSpec", {}))
    except (KeyError, TypeError, AttributeError):
        return False


def releve():
    """Relevé des dates de git : ({empreinte: (fichier, date)}, {digest d'une dépendance: (date ou "", encore présent)}), ou None."""
    if not os.environ.get("RELEVE"):
        return None
    cles, pins = {}, {}
    with open(os.environ["RELEVE"], encoding="utf-8") as f:
        for ligne in f:
            if ligne.startswith("#"):
                continue
            quoi, a, b, c = ligne.rstrip("\n").split("\t")
            if quoi == "cle":
                cles[a] = (b, int(c))
            elif quoi == "pin" and c in ("present", "retire", "non-epingle") and (c == "non-epingle") == (b == "-"):
                pins[a] = ("", False) if b == "-" else (int(b), c == "present")
            else:
                raise Refus(f"relevé : ligne {quoi} illisible")
    return cles, pins


def dates_cles(cles):
    texte, inconnues = "", 0
    for fichier in sorted({f for f, _ in cles.values()} | {f"{c}.pub" for c in CLE_DE.values()}):
        try:
            with open(f"{os.environ['CLES']}/{fichier}", "rb") as f:
                empreinte = hashlib.sha256(f.read()).hexdigest()
        except FileNotFoundError:
            empreinte = ""
        if cles.get(empreinte, ("",))[0] != fichier:
            inconnues += 1
            continue
        texte += f'kpi_cle_timestamp_seconds{{cle="{fichier.rsplit(".", 1)[0]}",empreinte="{empreinte[:12]}"}} {cles[empreinte][1]}\n'
    return texte + f"kpi_cles_non_relevees {inconnues}\n"


def genre(d):
    nom, uri = d.get("name"), d["uri"]
    if nom == "pipeline":
        return "pipeline"
    if nom == "pipelineTask":
        return "tache"
    if uri.startswith("git+"):
        return "source"
    return "fermeture" if "/builds/fermetures/" in uri else "entree" if "/entrees/" in uri else "image"


def dates_pins(prov, pins, etiquettes, comptes):
    """Dates d'épinglage des dépendances de la provenance de PipelineRun la plus récente (fin, puis identifiant)."""
    try:
        p = max((e["predicate"] for e in prov if de_chains(e)),
                key=lambda p: (p["runDetails"]["metadata"]["finishedOn"], p["runDetails"]["metadata"]["invocationId"]))
        vus = {(genre(d), d["uri"].rsplit("/", 1)[-1], str(next(iter(d["digest"].values())))) for d in p["buildDefinition"]["resolvedDependencies"]}
    except (KeyError, TypeError, AttributeError, StopIteration):
        comptes["forme"] += 1
        return ""
    texte, inconnus = "", 0
    for g, nom, digest in sorted(vus):
        if digest not in pins:
            inconnus += 1
            continue
        date, present = pins[digest]
        pin = f'{etiquettes},genre="{g}",nom="{nom if NOM.fullmatch(nom) else "illisible"}",pin="{digest[:12]}"'
        texte += f'kpi_pin_timestamp_seconds{{{pin},retire="{int(not present)}"}} {date}\n' if date != "" else f"kpi_pin_non_epingle{{{pin}}} 1\n"
    return texte + f"kpi_pins_non_releves{{{etiquettes}}} {inconnus}\n"


def sujet(nom, digest, tags, catalogue, verifier, pins):
    depot = f"builds/{nom}"
    comptes = {"verifier": verifier, "forme": 0, "verifiees": dict.fromkeys(CLE_DE, 0), "refusees": dict.fromkeys(CLE_DE, 0)}
    prov, signee = provenances(depot, digest, tags, comptes)
    trouve = {f: referents(f, nom, digest, catalogue, comptes) for f in FAMILLES}
    pr = sum(1 for e in prov if de_chains(e))
    niveaux = [v["predicate"].get("verifiedLevels") or [] for v in trouve["vsa"]
               if (v["predicate"].get("verifier") or {}).get("id") == VERIFIEUR and v["predicate"].get("verificationResult") == "PASSED"]
    etiquettes = f'depot="{depot}",digest="{digest[7:19]}"'
    dates = dates_pins(prov, pins, etiquettes, comptes) if pins is not None and pr else ""
    valeurs = {"kpi_provenance_chains_verifiee": int(pr > 0 and signee), "kpi_provenances_pipelinerun": pr,
               "kpi_replay_identique": int(any("POC_REPLAY_BIT_IDENTIQUE" in n for n in niveaux)),
               "kpi_l3_verifie": int(any("SLSA_BUILD_LEVEL_3" in n for n in niveaux)),
               "kpi_vex_verifies": len(trouve["vex"]), "kpi_enonces_refuses": comptes["forme"]}
    if trouve["scan"]:
        p = max((e["predicate"] for e in trouve["scan"]), key=lambda p: p["scannedAt"])
        v = p.get("vulnerabilities") or []
        valeurs.update({"kpi_scan_entrees": len(v), "kpi_scan_ecartees": len([1 for x in v if x.get("vex")]),
                        "kpi_scan_kev": len([1 for x in v if x.get("kev")]),
                        "kpi_scan_kev_ecartees": len([1 for x in v if x.get("kev") and x.get("vex")]),
                        "kpi_scan_timestamp_seconds": epoque(p["scannedAt"])})
    texte = dates + "".join(f"{k}{{{etiquettes}}} {v}\n" for k, v in sorted(valeurs.items()))
    for quoi in ("verifiees", "refusees") if verifier else ():
        texte += "".join(f'kpi_signatures_{quoi}{{{etiquettes},famille="{f}"}} {n}\n' for f, n in sorted(comptes[quoi].items()))
    return texte


def kev(fichier):
    """Ouvertures et fermetures des KEV, par dépôt. Un scan sans entrée n'émet que son résumé (« liste émise ») : les scans viennent
    donc des résumés, les KEV des lignes d'entrées. Une KEV est ouverte tant qu'une de ses entrées n'est pas écartée."""
    scans, vues = {}, {}
    with open(fichier, encoding="utf-8") as f:
        for ligne in f:
            for depot, date in re.findall(r"(builds/scan/[a-z0-9._-]+)=\d+@(\S+) \(liste émise\)", ligne):
                scans.setdefault(depot, set()).add(date)
            if ligne.startswith("{") and '"kev":true' in ligne:
                e = json.loads(ligne)
                if not e.get("vex"):
                    vues.setdefault((e["depot"], e["scannedAt"]), set()).update(
                        c if NOM.fullmatch(c) else "illisible" for c in e.get("kevCves") or [e["id"]])
    sortie = []
    for depot in sorted(scans):
        ouverte = {}
        for date in sorted(scans[depot], key=epoque):
            reelles = vues.get((depot, date), set())
            for cve in sorted(reelles | set(ouverte)):
                if cve not in ouverte:
                    ouverte[cve] = epoque(date)
                    sortie.append(("ouverture", depot, cve, ouverte[cve], ouverte[cve]))
                elif cve not in reelles:
                    sortie.append(("fermeture", depot, cve, ouverte.pop(cve), epoque(date)))
    return "".join(f'kpi_kev_{quoi}_timestamp_seconds{{depot="{depot.replace("builds/scan/", "builds/", 1)}",kev="{cve}",ouverture="{debut}"}} '
                   f"{valeur}\n" for quoi, depot, cve, debut, valeur in sorted(sortie))


def main():
    try:
        # Tout est lu et contrôlé avant d'écrire : un refus ou une lecture impossible laisse le fichier inchangé.
        verifier = controler_cles()
        dates = releve()
        catalogue = set(lire("_catalog")["repositories"])
        texte = ""
        for nom in os.environ["PRODUITS"].split():
            if f"builds/{nom}" not in catalogue:
                raise Refus(f"builds/{nom} absent du catalogue")
            tags = lire(f"builds/{nom}/tags/list").get("tags") or []
            texte += "".join(sujet(nom, d, tags, catalogue, verifier, dates and dates[1]) for d in digests(f"builds/{nom}", tags))
        if os.environ.get("JOURNAL"):
            texte += kev(os.environ["JOURNAL"])
            texte += f"kpi_exportateur_journal_timestamp_seconds {int(os.stat(os.environ['JOURNAL']).st_mtime)}\n"
        if dates and verifier:
            texte += dates_cles(dates[0])
        texte += f"kpi_exportateur_passage_timestamp_seconds {int(time.time())}\n"
    except (Refus, urllib.error.URLError, OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as e:
        print(f"refus : {type(e).__name__} : {e}", file=sys.stderr)
        return 2
    donnees = texte.encode()
    f = os.open(os.environ["SORTIE"], os.O_WRONLY)  # réécrit sur place, comme entrees-scan : écrire d'abord, couper ensuite
    try:
        os.pwrite(f, donnees, 0)
        os.ftruncate(f, len(donnees))
    finally:
        os.close(f)
    print(f"kpi : {texte.count(chr(10))} séries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
