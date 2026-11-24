#!/usr/bin/env python3
"""Brique 20, étape 2 : recalcul de référence des KPI, sur l'hôte, signatures vérifiées (README, décisions du 24/11 à 18:32:11Z).
Lecture seule : Zot en anonyme, Grafana par l'auditeur, git. Ni ssh, ni sudo, ni cluster ; rien n'est écrit hors du dossier de travail.
Principes :
  - dénominateur : sample-app, sample-app-deb et sample-app-rpm, tous les digests présents dans Zot (vus par un tag) ;
  - chaque attestation est LISTÉE (couches du .att, referrers) puis VÉRIFIÉE par cosign, clé de son émetteur ; les deux comptes sont
    écrits. cosign rend le code 1 pour absent, non vérifié et injoignable : il n'est appelé que si la liste n'est pas vide, une erreur
    HTTP arrête tout, et une erreur de cosign autre que « no matching attestations » ou « no valid bundles » aussi ;
  - témoin négatif : les mêmes appels avec une clé étrangère (g6-temoin-cle-publique.pem) doivent vérifier 0 attestation ;
  - des DATES, jamais des âges : l'âge change entre ce recalcul et l'exportateur, la date non ;
  - « L3 vérifié » : VSA de replay qui porte SLSA_BUILD_LEVEL_3 (décision « VSA seule » du 24/11) ; la provenance vérifiée est comptée à
    côté, sous son nom : la politique de la porte n'est pas rejouée ici.
Sortie : lignes KPI|nom|dépôt|digest|valeur (triées, « absent » ou « sans objet » quand il n'y a pas de dénominateur), DETAIL|… et les
cas comparés. Aucun contenu d'énoncé : les VEX portent un auteur."""
import base64
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ICI)
sys.dont_write_bytecode = True
from kpi import comptes_scan, delais_kev, rapport  # noqa: E402

BRIQUES = os.path.dirname(ICI)
DEPOT = os.path.dirname(os.path.dirname(BRIQUES))
CACHE = os.path.expanduser("~/.cache/supply-chain-poc")
CA = f"{CACHE}/08/pki/ca-poc.crt"
REG = "192.168.161.13:5000"
GRAFANA = "https://192.168.161.13:3001"
TRAVAIL = f"{CACHE}/20/recalcul"
URL_TSA = "http://timestamp-authority.tsa.svc.cluster.local:3000/api/v1/timestamp"
PRODUITS = ("sample-app", "sample-app-deb", "sample-app-rpm")
BUILDER = "https://supply-chain.example/builders/tekton-chains@v1"
BUILDTYPE = "https://tekton.dev/chains/v2/slsa-tekton"
VERIFIEUR = "https://supply-chain.example/verifiers/replay-poc-administrateur-unique@v1"
T_PROV, T_SCAN = "https://slsa.dev/provenance/v1", "https://supply-chain.example/scan/v1"
T_VSA, T_VEX = "https://slsa.dev/verification_summary/v1", "https://openvex.dev/ns/v0.2.0"
CLES = {  # clés publiques versionnées ; « chaine » : certificat, exercé par --use-signed-timestamps
    "chains": "08-trust-plane/resultats/chains-cle-publique.pem", "scanner": "07a-sbom-grype/resultats/scanner-cle-publique.pem",
    "vex": "07a-sbom-grype/resultats/vex-cle-publique.pem", "vsa": "10-independent-replay/resultats/vsa-cle-publique.pem",
    "tsa": "08-trust-plane/resultats/tsa-chaine.pem"}
TEMOIN = "07a-sbom-grype/resultats/g6-temoin-cle-publique.pem"
FAMILLES = (("scan", T_SCAN, "scanner"), ("vsa", T_VSA, "vsa"), ("vex", T_VEX, "vex"))
CTX = ssl.create_default_context(cafile=CA)
ACC = ("application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, "
       "application/vnd.docker.distribution.manifest.v2+json")
cas = {"n": 0, "ko": 0}
kpis = []


def attendu(nom, obtenu, voulu):
    cas["n"] += 1
    cas["ko"] += obtenu != voulu
    print(f"{'OK  ' if obtenu == voulu else 'KO  '} {nom} : {obtenu}" + ("" if obtenu == voulu else f" (attendu {voulu})"))


def kpi(nom, depot, digest, valeur):
    kpis.append(f"KPI|{nom}|{depot}|{digest}|{valeur}")


def arret(motif):
    print(f"ARRÊT : {motif}")
    sys.exit(2)


def zot(chemin, absent=None):
    req = urllib.request.Request(f"https://{REG}/v2/{chemin}", headers={"Accept": ACC})
    try:
        with urllib.request.urlopen(req, timeout=20, context=CTX) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404 and absent is not None:
            return absent
        arret(f"Zot {chemin} : HTTP {e.code}")
    except (urllib.error.URLError, OSError) as e:
        arret(f"Zot {chemin} : {e}")


def cosign(nom, digest, cle, typ, depot_att=None, plus=()):
    """Énoncés vérifiés : [(énoncé, signature)] ; type et sujet revérifiés ici. Jamais appelé sans attestation listée."""
    env = dict(os.environ)
    if depot_att:
        env["COSIGN_REPOSITORY"] = f"{REG}/{depot_att}"
    r = subprocess.run(["cosign", "verify-attestation", "--key", f"{BRIQUES}/{cle}", "--type", typ, "--insecure-ignore-tlog=true",
                        "--registry-cacert", CA, *plus, f"{REG}/builds/{nom}@{digest}"],
                       capture_output=True, text=True, env=env, timeout=120, stdin=subprocess.DEVNULL)
    if r.returncode and not re.search(r"no matching attestations|no valid bundles|invalid signature", r.stderr):
        arret(f"cosign {nom} {typ} : code {r.returncode}, motif non reconnu : "
              + " ".join(x for x in r.stderr.splitlines() if "WARNING" not in x)[:200])
    sortie = []
    for ligne in r.stdout.splitlines():
        if not ligne.startswith("{"):
            continue
        d = json.loads(ligne)
        e = json.loads(base64.b64decode(d["payload"]))
        if e.get("predicateType") == typ and any(s.get("digest", {}).get("sha256") == digest[7:] for s in e.get("subject") or []):
            sortie.append((e, d["signatures"][0]["sig"]))
    if r.returncode and sortie:
        arret(f"cosign {nom} {typ} : code {r.returncode} avec des énoncés en sortie")
    return sortie


def git(*args):
    r = subprocess.run(["git", "-C", DEPOT, *args], capture_output=True, text=True, timeout=300)
    if r.returncode:
        arret(f"git {args[0]} : code {r.returncode}")
    return r.stdout


HORS_CONF = [":(exclude)*/resultats/*", ":(exclude)*.md", ":(exclude)*.log", ":(exclude)*.patch", ":(exclude)*_test.rego",
             ":(exclude)poc/bricks/20-kpi/*"]
MEMO = {}


def date_conf(valeur):
    """Date (epoch) du premier commit qui écrit cette valeur dans un fichier de configuration, si elle y est encore."""
    if valeur not in MEMO:
        present = subprocess.run(["git", "-C", DEPOT, "grep", "-q", "-F", valeur, "HEAD", "--", ".", *HORS_CONF]).returncode == 0
        dates = git("log", "--reverse", "--format=%ct", f"-S{valeur}", "--", ".", *HORS_CONF).split()
        MEMO[valeur] = (dates[0] if dates else "", present)
    return MEMO[valeur]


def genre(dep):
    if dep.get("name") in ("pipeline", "pipelineTask"):
        return "pipeline" if dep["name"] == "pipeline" else "tache"
    if dep["uri"].startswith("git+"):
        return "source"
    if "/builds/fermetures/" in dep["uri"]:
        return "fermeture"
    return "entree" if "/entrees/" in dep["uri"] else "image"


def grafana(source, expr, plus):
    mdp = open(f"{CACHE}/08/secrets/grafana-auditeur.password", encoding="utf-8").read().strip()
    corps = {"queries": [{"refId": "A", "datasource": {"uid": source}, "expr": expr, **plus.pop("q")}], **plus}
    req = urllib.request.Request(f"{GRAFANA}/api/ds/query", data=json.dumps(corps).encode(), method="POST", headers={
        "Content-Type": "application/json", "Authorization": "Basic " + base64.b64encode(f"auditeur:{mdp}".encode()).decode()})
    try:
        with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
            a = json.load(r)["results"]["A"]
    except (urllib.error.URLError, OSError) as e:
        arret(f"Grafana {source} : {type(e).__name__} {getattr(e, 'code', '')}")
    if a.get("error"):
        arret(f"Grafana {source} : requête en erreur")
    return a.get("frames") or []


def prom(expr, t):
    return [(f["schema"]["fields"][1].get("labels") or {}, f["data"]["values"][1][0])
            for f in grafana("prometheus", expr, {"from": f"{t}000", "to": f"{t}000", "q": {"instant": True, "queryType": "instant"}})]


def loki(expr, debut, fin):
    """Lignes brutes [(ns, ligne)]. 5000 lignes au plus : atteint, le résultat serait tronqué, donc arrêt."""
    lignes = []
    for f in grafana("loki", expr, {"from": f"{debut}000", "to": f"{fin}000", "q": {"queryType": "range", "maxLines": 5000,
                                                                              "direction": "forward"}}):
        noms = [c["name"] for c in f["schema"]["fields"]]
        if f["data"]["values"] and f["data"]["values"][0]:
            lignes += zip(map(int, f["data"]["values"][noms.index("tsNs")]), f["data"]["values"][noms.index("Line")])
    if len(lignes) >= 5000:
        arret("Loki : 5000 lignes, résultat tronqué")
    return lignes


def epoque(date):
    import datetime
    return int(datetime.datetime.fromisoformat(re.sub(r"(\.[0-9]{6})[0-9]+", r"\1", date).replace("Z", "+00:00")).timestamp())


def main():
    maintenant = int(subprocess.run(["date", "-u", "+%s"], capture_output=True, text=True, check=True).stdout)
    catalogue = set(zot("_catalog")["repositories"])
    os.makedirs(TRAVAIL, exist_ok=True)
    racine = f"{TRAVAIL}/tsa-racine.json"
    r = subprocess.run(["cosign", "trusted-root", "create", f"--tsa=url={URL_TSA},certificate-chain={BRIQUES}/{CLES['tsa']}",
                        "--out", racine], capture_output=True, text=True)
    if r.returncode:
        arret("racine de confiance du TSA")

    print("## 1. sujets : listé, vérifié, vérifié par la clé étrangère (témoin, attendu 0)")
    sujets, total = [], {"liste": 0, "verifie": 0, "temoin": 0}
    for nom in PRODUITS:
        tags = zot(f"builds/{nom}/tags/list")["tags"]
        digests = {f"sha256:{t[7:71]}" for t in tags if re.fullmatch(r"sha256-[0-9a-f]{64}\.[a-z]+", t)}
        for t in tags:
            if not re.fullmatch(r"sha256-[0-9a-f]{64}\.[a-z]+", t):
                req = urllib.request.Request(f"https://{REG}/v2/builds/{nom}/manifests/{t}", method="HEAD", headers={"Accept": ACC})
                try:
                    digests.add(urllib.request.urlopen(req, timeout=20, context=CTX).headers["Docker-Content-Digest"])
                except (urllib.error.URLError, OSError) as e:
                    arret(f"Zot builds/{nom}:{t} : {e}")
        for digest in sorted(digests):
            s = {"nom": nom, "digest": digest, "depot": f"builds/{nom}"}
            h = digest[7:]
            couches = len(zot(f"builds/{nom}/manifests/sha256-{h}.att")["layers"]) if f"sha256-{h}.att" in tags else 0
            s["prov"] = cosign(nom, digest, CLES["chains"], T_PROV) if couches else []
            t = len(cosign(nom, digest, TEMOIN, T_PROV)) if couches else 0
            compte = {"prov": (couches, len(s["prov"]), t)}
            for f, typ, cle in FAMILLES:
                d = f"builds/{f}/{nom}"
                n = len(zot(f"{d}/referrers/{digest}").get("manifests") or []) if d in catalogue else 0
                s[f] = cosign(nom, digest, CLES[cle], typ, d) if n else []
                t = len(cosign(nom, digest, TEMOIN, typ, d)) if n else 0
                compte[f] = (n, len(s[f]), t)
            # horodatage : bundles réémis dans horodatage/bundles, vérifiés avec horodatage exigé ; couverture par signature
            nb = len(zot(f"horodatage/bundles/referrers/{digest}").get("manifests") or [])
            h_tsa = cosign(nom, digest, CLES["chains"], T_PROV, "horodatage/bundles",
                           ("--use-signed-timestamps", f"--trusted-root={racine}")) if nb else []
            couvertes = len({x for _, x in s["prov"]} & {x for _, x in h_tsa})
            # signature d'image (.sig, simplesigning) : liste puis vérification, même clé
            sig = 0
            if f"sha256-{h}.sig" in tags:
                r = subprocess.run(["cosign", "verify", "--key", f"{BRIQUES}/{CLES['chains']}", "--insecure-ignore-tlog=true",
                                    "--registry-cacert", CA, f"{REG}/builds/{nom}@{digest}"], capture_output=True, text=True, timeout=120)
                if r.returncode and not re.search(r"no matching signatures|invalid signature", r.stderr):
                    arret(f"cosign verify {nom} : code {r.returncode}, motif non reconnu")
                sig = sum(1 for x in json.loads(r.stdout or "[]") if x["critical"]["type"] == "cosign container image signature"
                          and x["critical"]["image"]["docker-manifest-digest"] == digest) if r.returncode == 0 else 0
            s.update(sig=sig, tsa=(nb, len(h_tsa), couvertes))
            sujets.append(s)
            for a, b, c in compte.values():
                total["liste"] += a
                total["verifie"] += b
                total["temoin"] += c
            print(f"DETAIL|{s['depot']}|{h[:12]}|sig {sig}|" + "|".join(f"{k} {a}/{b}/{c}" for k, (a, b, c) in compte.items())
                  + f"|tsa {nb} listés, {len(h_tsa)} vérifiés, {couvertes}/{len(s['prov'])} provenances couvertes")
    attendu("attestations listées = vérifiées (toutes les clés en service)", total["verifie"], total["liste"])
    attendu("témoin : attestations vérifiées par la clé étrangère", total["temoin"], 0)

    print("## 2. KPI par sujet")
    for s in sujets:
        d, h = s["depot"], s["digest"][7:19]
        bonnes = [e for e, _ in s["prov"] if e["predicate"]["runDetails"]["builder"]["id"] == BUILDER
                  and e["predicate"]["buildDefinition"]["buildType"] == BUILDTYPE]
        pr = [e for e in bonnes if "pipelineRef" in e["predicate"]["buildDefinition"]["externalParameters"].get("runSpec", {})]
        s["provenance"] = int(bool(pr) and s["sig"] > 0)
        kpi("provenance_chains_verifiee", d, h, s["provenance"])
        kpi("provenances_pipelinerun", d, h, len(pr))
        vsa = [e["predicate"] for e, _ in s["vsa"] if e["predicate"]["verifier"]["id"] == VERIFIEUR
               and e["predicate"]["verificationResult"] == "PASSED"]
        s["replay"] = int(any("POC_REPLAY_BIT_IDENTIQUE" in v["verifiedLevels"] for v in vsa))
        s["l3_vsa"] = int(any("SLSA_BUILD_LEVEL_3" in v["verifiedLevels"] for v in vsa))
        kpi("replay_identique", d, h, s["replay"])
        kpi("l3_verifie", d, h, s["l3_vsa"])
        scans = sorted((e["predicate"] for e, _ in s["scan"]), key=lambda p: p["scannedAt"])
        s["scans"] = scans
        s["dernier"] = scans[-1] if scans else None
        c = comptes_scan(s["dernier"]) if scans else None
        for k in ("entrees", "ecartees", "kev", "kev_ecartees"):
            kpi(f"scan_{k}", d, h, c[k] if c else "absent")
        kpi("kev_ouvertes", d, h, c["kev"] - c["kev_ecartees"] if c else "absent")
        kpi("couverture_vex_entrees", d, h, (rapport(c["ecartees"], c["entrees"]) or "sans objet") if c else "absent")
        kpi("couverture_vex_kev", d, h, (rapport(c["kev_ecartees"], c["kev"]) or "sans objet") if c else "absent")
        kpi("scan_date", d, h, epoque(s["dernier"]["scannedAt"]) if c else "absent")
        kpi("vex_verifies", d, h, len(s["vex"]))
        # pins : provenance de PipelineRun la plus récente, dates d'épinglage (epoch), une ligne par dépendance distincte
        if pr:
            p = max(pr, key=lambda e: (e["predicate"]["runDetails"]["metadata"]["finishedOn"],
                                       e["predicate"]["runDetails"]["metadata"]["invocationId"]))
            for dep in sorted({(genre(x), x["uri"].rsplit("/", 1)[-1], next(iter(x["digest"].values())))
                               for x in p["predicate"]["buildDefinition"]["resolvedDependencies"]}):
                date, present = date_conf(dep[2])
                kpi(f"pin_date:{dep[0]}:{dep[1]}:{dep[2][:12]}", d, h, (date + ("" if present else " (retiré depuis)")) if date
                    else "non épinglé dans git")
    print("## 3. KPI de plateforme")
    n = len(sujets)
    kpi("taux_provenance_chains_verifiee", "-", "-", rapport(sum(s["provenance"] for s in sujets), n))
    kpi("taux_l3_verifie", "-", "-", rapport(sum(s["l3_vsa"] for s in sujets), n))
    kpi("taux_replay_identique", "-", "-", rapport(sum(s["replay"] for s in sujets), n))
    kpi("violations_licences", "-", "-", "source absente")
    for k in sorted(CLES):
        kpi(f"cle_date:{k}", "-", "-", git("log", "-1", "--format=%ct", "--", f"poc/bricks/{CLES[k]}").strip())
    # délai des KEV : Loki, 720 h, par dépôt (les lignes n'ont pas de digest) ; les scans viennent des résumés « liste émise », qui
    # existent même sans entrée, et les KEV des lignes d'entrées. Jointure des scans avec Zot par scannedAt : contrôle seulement.
    debut = maintenant - 719 * 3600
    base = '{source="journal", unite="entrees-scan.service"}'
    resumes = loki(base + ' |= "liste émise"', debut, maintenant)
    scans_loki = {}
    for _, ligne in resumes:
        for depot, nb, date in re.findall(r"(builds/scan/\S+?)=(\d+)@(\S+) \(liste émise\)", ligne):
            scans_loki.setdefault(depot, {})[date] = int(nb)
    entrees = loki(base + ' |= "scannedAt" |= "\\"kev\\":true"', debut, maintenant)
    toutes = loki(base + ' |= "scannedAt" |= "\\"id\\":"', debut, maintenant)
    par_scan, kev = {}, {}
    for _, ligne in toutes:
        e = json.loads(ligne)
        par_scan.setdefault((e["depot"], e["scannedAt"]), set()).add((e["id"], e["package"]))
    for _, ligne in entrees:
        e = json.loads(ligne)
        for cle in e.get("kevCves") or [e["id"]]:
            kev.setdefault((e["depot"], e["scannedAt"]), []).append((cle, bool(e.get("vex"))))
    dates_zot = {p["scannedAt"] for s in sujets for p in s["scans"]}
    for depot in sorted(scans_loki):
        lignes = delais_kev([(epoque(x), kev.get((depot, x), [])) for x in scans_loki[depot]])
        kpi("kev_delais", depot.replace("builds/scan/", "builds/"), "-", lignes or "sans objet (0 KEV vue)")
        print(f"DETAIL|loki|{depot}|{len(scans_loki[depot])} scan(s) en 719 h, {sum(1 for x in scans_loki[depot] if x in dates_zot)}"
              " encore signé(s) dans Zot (jointure par scannedAt)")
    ecarts = sum(1 for d in scans_loki for x, nb in scans_loki[d].items() if len(par_scan.get((d, x), ())) != nb)
    for ligne in sorted(kpis):
        print(ligne)

    print("## 4. comparaisons")
    attendu("Loki : scans dont le nombre d'entrées (couples id et paquet) diffère de leur résumé", ecarts, 0)
    attendu("Loki : lignes d'entrées lues (le zéro KEV n'est pas à vide)", len(toutes) > 0, True)
    attendu("sujets produits", n, 4)
    attendu("clé du TSA exercée : toutes les provenances couvertes par un bundle horodaté",
            [s["digest"][7:15] for s in sujets if s["tsa"][2] != len(s["prov"])], [])
    # Prometheus (exportateur entrees-scan, en service) contre le recalcul signé, par dépôt ; le digest est retrouvé par la date
    series = {m: {(l["depot"], l.get("gravite")): v for l, v in prom(m, maintenant)} for m in (
        "scan_entrees", "scan_entrees_vex", "scan_entrees_kev", "scan_entrees_kev_vex", "scan_entrees_scanne_timestamp_seconds")}
    for depot in sorted({d for d, _ in series["scan_entrees_scanne_timestamp_seconds"]}):
        date = int(series["scan_entrees_scanne_timestamp_seconds"][(depot, None)])
        trouve = [s for s in sujets if s["depot"] == depot.replace("builds/scan/", "builds/") and s["dernier"]
                  and epoque(s["dernier"]["scannedAt"]) == date]
        attendu(f"Prometheus {depot} : la date désigne le dernier scan signé d'un seul sujet", len(trouve), 1)
        if len(trouve) == 1:
            c = comptes_scan(trouve[0]["dernier"])
            somme = [int(sum(v for (d, _), v in series[m].items() if d == depot)) for m in (
                "scan_entrees", "scan_entrees_vex", "scan_entrees_kev", "scan_entrees_kev_vex")]
            attendu(f"Prometheus {depot} ({trouve[0]['digest'][7:15]}) : entrées, écartées, KEV, KEV écartées", somme,
                    [c["entrees"], c["ecartees"], c["kev"], c["kev_ecartees"]])
    print(f"## bilan : {cas['n']} cas, {cas['ko']} écart(s)")
    return 1 if cas["ko"] else 0


if __name__ == "__main__":
    sys.exit(main())
