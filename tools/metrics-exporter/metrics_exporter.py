#!/usr/bin/python3 -I
"""Brique 20 : exportateur des KPI supply-chain (docs/02 §7, « tools/metrics-exporter dérive les métriques des attestations »).
Bibliothèque standard seulement, lectures anonymes de Zot par HTTPS, même motif que entrees-scan.py (07b). Ni git, ni cosign : les dates
des pins et des clés ne viennent pas d'ici (relevé versionné, étape 4).
  LES SIGNATURES NE SONT PAS VÉRIFIÉES : les énoncés sont comptés, pas prouvés. Choix du propriétaire à poser (étape 4) ; le banc de
  l'étape 3 mesure ce que cela change. Le recalcul signé (poc/bricks/20-kpi/recalcul.py) reste la référence.
Écrit sans kpi.py, pour que la comparaison avec le recalcul ne compare pas un code à lui-même. Mêmes règles :
  - sujets : PRODUITS, tous les digests vus par un tag ;
  - provenance : couches du .att (builder.id et buildType de Chains, pipelineRef), plus une signature d'image (.sig) qui nomme le digest ;
  - VSA : PASSED du vérifieur attendu ; une seule suffit, même si une FAILED est plus récente (même règle que le recalcul) ;
  - scan : le plus récent par scannedAt ; entrées, écartées par un VEX, KEV, KEV écartées. Aucun scan : séries absentes, jamais 0 ;
  - KEV : ouverture et fermeture, depuis les lignes de entrees-scan (fichier JOURNAL ; en service, la source sera Loki). Sans JOURNAL :
    séries absentes.
Un énoncé illisible, ou qui ne nomme pas son sujet ou son type, est compté (kpi_enonces_refuses) et ignoré. Une erreur HTTP, un JSON
de Zot illisible ou une empreinte fausse arrêtent tout, code d'erreur, fichier inchangé.
Variables : REG, CA, PRODUITS (noms séparés par des espaces), SORTIE (fichier .prom, existant), JOURNAL (facultatif)."""
import base64
import binascii
import datetime
import hashlib
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.request

BUILDER = "https://supply-chain.example/builders/tekton-chains@v1"
BUILDTYPE = "https://tekton.dev/chains/v2/slsa-tekton"
VERIFIEUR = "https://supply-chain.example/verifiers/replay-poc-administrateur-unique@v1"
PROVENANCE = "https://slsa.dev/provenance/v1"
FAMILLES = {"scan": "https://supply-chain.example/scan/v1", "vsa": "https://slsa.dev/verification_summary/v1",
            "vex": "https://openvex.dev/ns/v0.2.0"}
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


def enonce(octets, typ, digest):
    """Énoncé in-toto d'une enveloppe DSSE ou d'un bundle sigstore, s'il a ce type et nomme ce sujet ; None sinon."""
    try:
        d = json.loads(octets)
        d = d.get("dsseEnvelope", d)
        e = json.loads(base64.b64decode(d["payload"], validate=True))
        bon = (d["payloadType"] == INTOTO and e["predicateType"] == typ and isinstance(e["predicate"], dict)
               and any(s["digest"].get("sha256") == digest[7:] for s in e["subject"]))
    except (ValueError, KeyError, TypeError, AttributeError, binascii.Error):
        return None
    return e if bon else None


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


def provenances(depot, digest, tags):
    """(énoncés de provenance, énoncés refusés, signature d'image présente)."""
    h, bons, refus, signee = digest[7:], [], 0, False
    if f"sha256-{h}.att" in tags:
        for c in lire(f"{depot}/manifests/sha256-{h}.att")["layers"]:
            e = enonce(blob(depot, c["digest"]), PROVENANCE, digest)
            refus += e is None
            bons += [e] if e else []
    if f"sha256-{h}.sig" in tags:
        for c in lire(f"{depot}/manifests/sha256-{h}.sig")["layers"]:
            try:
                critique = json.loads(blob(depot, c["digest"]))["critical"]
                signee = signee or (critique["type"] == "cosign container image signature"
                                    and critique["image"]["docker-manifest-digest"] == digest)
            except (ValueError, KeyError, TypeError):
                refus += 1
    return bons, refus, signee


def referents(famille, nom, digest, catalogue):
    depot, bons, refus = f"builds/{famille}/{nom}", [], 0
    if depot not in catalogue:
        return bons, refus
    for m in lire(f"{depot}/referrers/{digest}").get("manifests") or []:
        couches = lire(f"{depot}/manifests/{m['digest']}").get("layers") or []
        e = enonce(blob(depot, couches[0]["digest"]), FAMILLES[famille], digest) if couches else None
        refus += e is None
        bons += [e] if e else []
    return bons, refus


def de_chains(e):
    try:
        p = e["predicate"]
        return (p["runDetails"]["builder"]["id"] == BUILDER and p["buildDefinition"]["buildType"] == BUILDTYPE
                and "pipelineRef" in p["buildDefinition"]["externalParameters"].get("runSpec", {}))
    except (KeyError, TypeError, AttributeError):
        return False


def sujet(nom, digest, tags, catalogue):
    depot = f"builds/{nom}"
    prov, refus, signee = provenances(depot, digest, tags)
    trouve = {}
    for f in FAMILLES:
        trouve[f], r = referents(f, nom, digest, catalogue)
        refus += r
    pr = sum(1 for e in prov if de_chains(e))
    niveaux = [v["predicate"].get("verifiedLevels") or [] for v in trouve["vsa"]
               if (v["predicate"].get("verifier") or {}).get("id") == VERIFIEUR and v["predicate"].get("verificationResult") == "PASSED"]
    valeurs = {"kpi_provenance_chains_verifiee": int(pr > 0 and signee), "kpi_provenances_pipelinerun": pr,
               "kpi_replay_identique": int(any("POC_REPLAY_BIT_IDENTIQUE" in n for n in niveaux)),
               "kpi_l3_verifie": int(any("SLSA_BUILD_LEVEL_3" in n for n in niveaux)),
               "kpi_vex_verifies": len(trouve["vex"]), "kpi_enonces_refuses": refus}
    if trouve["scan"]:
        p = max((e["predicate"] for e in trouve["scan"]), key=lambda p: p["scannedAt"])
        v = p.get("vulnerabilities") or []
        valeurs.update({"kpi_scan_entrees": len(v), "kpi_scan_ecartees": len([1 for x in v if x.get("vex")]),
                        "kpi_scan_kev": len([1 for x in v if x.get("kev")]),
                        "kpi_scan_kev_ecartees": len([1 for x in v if x.get("kev") and x.get("vex")]),
                        "kpi_scan_timestamp_seconds": epoque(p["scannedAt"])})
    etiquettes = f'depot="{depot}",digest="{digest[7:19]}"'
    return "".join(f"{k}{{{etiquettes}}} {v}\n" for k, v in sorted(valeurs.items()))


def kev(fichier):
    """Ouvertures et fermetures des KEV, par dépôt. Un scan sans entrée n'émet que son résumé (« liste émise ») : les scans viennent
    donc des résumés, les KEV des lignes d'entrées. Une KEV est ouverte tant qu'une de ses entrées n'est pas écartée."""
    scans, vues = {}, {}
    with open(fichier, encoding="utf-8") as f:
        for ligne in f:
            for depot, date in re.findall(r"(builds/scan/\S+?)=\d+@(\S+) \(liste émise\)", ligne):
                scans.setdefault(depot, set()).add(date)
            if ligne.startswith("{") and '"kev":true' in ligne:
                e = json.loads(ligne)
                if not e.get("vex"):
                    vues.setdefault((e["depot"], e["scannedAt"]), set()).update(e.get("kevCves") or [e["id"]])
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
        catalogue = set(lire("_catalog")["repositories"])
        texte = ""
        for nom in os.environ["PRODUITS"].split():
            if f"builds/{nom}" not in catalogue:
                raise Refus(f"builds/{nom} absent du catalogue")
            tags = lire(f"builds/{nom}/tags/list").get("tags") or []
            texte += "".join(sujet(nom, d, tags, catalogue) for d in digests(f"builds/{nom}", tags))
        if os.environ.get("JOURNAL"):
            texte += kev(os.environ["JOURNAL"])
    except (Refus, urllib.error.URLError, OSError, ValueError, KeyError, TypeError) as e:
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
