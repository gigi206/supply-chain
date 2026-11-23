#!/usr/bin/python3 -I
"""Brique 07b, tranche 1 : entrées trouvées par le scan signé, vues dans Grafana (décision « Les deux » du 21/11/2026).
Lancé par entrees-scan.service sur sc-stockage, même motif que fraicheur-scan (07a, G8) : lectures anonymes de Zot, par HTTPS,
bibliothèque standard seulement.
  Pour chaque « dépôt@digest » de SCANS, le referrer de scan le plus récent (org.opencontainers.image.created, comme
  fraicheur-scan), son manifeste, puis son bundle sigstore. Le relevé de l'énoncé in-toto est contrôlé : type du bundle, empreinte
  du blob, payloadType, predicateType et sujet égal au digest demandé. Un écart arrête tout, code d'erreur, rien n'est écrit.
  LA SIGNATURE N'EST PAS VÉRIFIÉE ICI : cosign n'est pas sur sc-stockage. La porte fait foi.
Unité de compte : une entrée = un couple (identifiant, PURL) du prédicat, pas une CVE. Un identifiant GHSA ou GO peut n'avoir
aucun alias CVE.
Sorties :
  SORTIE (fichiers-metriques, brique 19) : comptes par dépôt, grille de gravités fixe (zéros écrits), KEV, avec correctif,
    scannedAt du prédicat lu. Ni HELP ni TYPE, comme fraicheur-scan.prom. Le fichier est créé par la pose ; écrit sur place.
    07b, tranche 3 : scan_entrees compte les entrées trouvées ; scan_entrees_vex (même grille) et scan_entrees_kev_vex celles
    qu'un VEX a écartées (champ vex du prédicat, écrit par le scanner). Réelles = trouvées - écartées, par soustraction dans
    Grafana. Ce sont les entrées que le scanner a écartées, pas celles que la porte admet : la porte juge aussi l'âge du VEX.
    Bloc vex du prédicat (0 s'il est absent, prédicats d'avant la tranche 3) : scan_vex_documents (documents passés au scanner),
    scan_vex_rejetes (vérifiés mais rejetés par le filtre), scan_vex_ecartees_sans_exemption (gagnant non exemptant),
    scan_vex_repli (documents retenus non appliqués : Grype en échec avec les VEX, scan relancé sans eux ; limite 4).
  Sortie standard (journal, puis Loki par Alloy, unite="entrees-scan.service") : une ligne JSON par entrée, avec dépôt et
    scannedAt dans la ligne (chaîne d'origine, et « scanne » en secondes, égal à la série du même nom), jamais en étiquette. Émise une seule fois par referrer de scan : le digest du dernier manifeste émis
    est gardé dans ETAT (StateDirectory). Les autres passages n'écrivent qu'une ligne de résumé.
    07b, tranche 3 : une ligne de plus par document VEX du bloc vex (vexDocument : empreinte, vexTimestamp : horodatage),
    sans id, émise avec les entrées et sous la même marque ; verif les écarte du compte des entrées (vexDocument="").
Aucun referrer de scan pour un dépôt : ses séries ne sont pas écrites (absent() dans les règles), aucune ligne d'entrée."""
import base64
import datetime
import hashlib
import json
import os
import re
import ssl
import sys
import urllib.request

PREDICAT = "https://supply-chain.example/scan/v1"
INDEX = "application/vnd.oci.image.index.v1+json"
MANIFESTE = "application/vnd.oci.image.manifest.v1+json"
BUNDLE = "application/vnd.dev.sigstore.bundle.v0.3+json"
INTOTO = "application/vnd.in-toto+json"
# Gravités de grype ; « autre » reçoit une valeur hors grille, pour qu'aucune entrée ne disparaisse des comptes.
GRAVITES = ("Critical", "High", "Medium", "Low", "Negligible", "Unknown", "autre")


class Refus(Exception):
    pass


def lire(chemin, accepte="application/json"):
    requete = urllib.request.Request(f"https://{os.environ['REG']}/v2/{chemin}", headers={"Accept": accepte})
    with urllib.request.urlopen(requete, timeout=20, context=ssl.create_default_context(cafile=os.environ["CA"])) as reponse:
        return reponse.read()


def epoque(date):
    # scannedAt a des nanosecondes ; fromisoformat n'en accepte pas plus de 6 chiffres avant Python 3.11.
    date = re.sub(r"(\.[0-9]{6})[0-9]+", r"\1", date).replace("Z", "+00:00")
    return int(datetime.datetime.fromisoformat(date).timestamp())


def dernier_releve(depot, digest):
    """(digest du manifeste, énoncé in-toto) du referrer de scan le plus récent, ou None sans referrer."""
    manifestes = [
        m for m in json.loads(lire(f"{depot}/referrers/{digest}", INDEX)).get("manifests") or []
        if m.get("annotations", {}).get("dev.sigstore.bundle.predicateType") == PREDICAT
    ]
    if not manifestes:
        return None
    m = max(manifestes, key=lambda m: epoque(m["annotations"]["org.opencontainers.image.created"]))
    couche = json.loads(lire(f"{depot}/manifests/{m['digest']}", MANIFESTE))["layers"][0]
    if couche.get("mediaType") != BUNDLE:
        raise Refus(f"{depot} : couche {couche.get('mediaType')}, attendu {BUNDLE}")
    blob = lire(f"{depot}/blobs/{couche['digest']}", "application/octet-stream")
    if "sha256:" + hashlib.sha256(blob).hexdigest() != couche["digest"]:
        raise Refus(f"{depot} : empreinte du bundle différente de son digest")
    enveloppe = json.loads(blob)["dsseEnvelope"]
    if enveloppe.get("payloadType") != INTOTO:
        raise Refus(f"{depot} : payloadType {enveloppe.get('payloadType')}")
    enonce = json.loads(base64.b64decode(enveloppe["payload"]))
    if enonce.get("predicateType") != PREDICAT:
        raise Refus(f"{depot} : predicateType {enonce.get('predicateType')}")
    sujets = ["sha256:" + s.get("digest", {}).get("sha256", "") for s in enonce.get("subject") or []]
    if sujets != [digest]:
        raise Refus(f"{depot} : sujet {sujets}, attendu [{digest}]")
    return m["digest"], enonce


def comptes(depot, predicat):
    v = predicat.get("vulnerabilities") or []
    g = dict.fromkeys(GRAVITES, 0)
    for e in v:
        g[e.get("severity") if e.get("severity") in GRAVITES[:-1] else "autre"] += 1
    lignes = [f'scan_entrees{{depot="{depot}",gravite="{k}"}} {n}\n' for k, n in g.items()]
    x = dict.fromkeys(GRAVITES, 0)
    for e in v:
        if e.get("vex"):
            x[e.get("severity") if e.get("severity") in GRAVITES[:-1] else "autre"] += 1
    lignes += [f'scan_entrees_vex{{depot="{depot}",gravite="{k}"}} {n}\n' for k, n in x.items()]
    lignes.append(f'scan_entrees_kev{{depot="{depot}"}} {sum(1 for e in v if e.get("kev"))}\n')
    lignes.append(f'scan_entrees_kev_vex{{depot="{depot}"}} {sum(1 for e in v if e.get("kev") and e.get("vex"))}\n')
    lignes.append(f'scan_entrees_avec_correctif{{depot="{depot}"}} {sum(1 for e in v if e.get("fixedIn"))}\n')
    lignes.append(f'scan_entrees_scanne_timestamp_seconds{{depot="{depot}"}} {epoque(predicat["scannedAt"])}\n')
    b = predicat.get("vex") or {}
    lignes.append(f'scan_vex_documents{{depot="{depot}"}} {len(b.get("documents") or [])}\n')
    lignes.append(f'scan_vex_rejetes{{depot="{depot}"}} {int(b.get("rejetes") or 0)}\n')
    lignes.append(f'scan_vex_ecartees_sans_exemption{{depot="{depot}"}} {int(b.get("ecarteesSansExemption") or 0)}\n')
    lignes.append(f'scan_vex_repli{{depot="{depot}"}} {int(b.get("repli") or 0)}\n')
    return "".join(lignes)


def entrees(depot, predicat):
    scanne = epoque(predicat["scannedAt"])  # même valeur que scan_entrees_scanne_timestamp_seconds : clé de jointure pour Grafana
    for e in predicat.get("vulnerabilities") or []:
        yield json.dumps({"depot": depot, "scannedAt": predicat["scannedAt"], "scanne": scanne, "id": e.get("id"), "aliases": e.get("aliases"),
                          "severity": e.get("severity"), "kev": e.get("kev"), "kevCves": e.get("kevCves"), "epss": e.get("epss"),
                          "fixedIn": e.get("fixedIn"), "package": e.get("package"), "vex": e.get("vex")}, ensure_ascii=False,
                         separators=(",", ":"))



def documents_vex(depot, predicat):
    """Une ligne par document VEX passé au scanner (bloc vex du prédicat, écrit par le scanner ; aucun s'il est absent)."""
    scanne = epoque(predicat["scannedAt"])
    for d in (predicat.get("vex") or {}).get("documents") or []:
        yield json.dumps({"depot": depot, "scannedAt": predicat["scannedAt"], "scanne": scanne, "vexDocument": d.get("sha256"),
                          "vexTimestamp": d.get("timestamp")}, ensure_ascii=False, separators=(",", ":"))

def main():
    scans = [s.split("@", 1) for s in os.environ["SCANS"].split()]
    sortie = os.environ.get("SORTIE", "/etc/fichiers-metriques/entrees-scan.prom")
    etat = os.environ.get("ETAT", "/var/lib/entrees-scan")
    try:
        # Tout est lu et contrôlé avant d'écrire : un refus ou une lecture impossible laisse le fichier inchangé.
        releves = [(depot, dernier_releve(depot, digest)) for depot, digest in scans]
    except Refus as r:
        print(f"refus : {r}", file=sys.stderr)
        return 2
    donnees = "".join(comptes(depot, r[1]["predicate"]) for depot, r in releves if r).encode()
    f = os.open(sortie, os.O_WRONLY)  # réécrit sur place, comme fraicheur-scan : écrire d'abord, couper ensuite
    try:
        os.pwrite(f, donnees, 0)
        os.ftruncate(f, len(donnees))
    finally:
        os.close(f)
    resume = []
    for depot, r in releves:
        if not r:
            resume.append(f"{depot}=aucun")
            continue
        manifeste, enonce = r
        p = enonce["predicate"]
        marque = os.path.join(etat, depot.replace("/", "_"))
        deja = os.path.exists(marque) and open(marque, encoding="ascii").read().strip() == manifeste
        if not deja:
            for ligne in entrees(depot, p):
                print(ligne)
            for ligne in documents_vex(depot, p):
                print(ligne)
            with open(marque + ".neuf", "w", encoding="ascii") as m:
                m.write(manifeste + "\n")
            os.replace(marque + ".neuf", marque)
        resume.append(f"{depot}={len(p.get('vulnerabilities') or [])}@{p['scannedAt']}{'' if deja else ' (liste émise)'}")
    print("entrées " + " ".join(resume))
    return 0


if __name__ == "__main__":
    sys.exit(main())
