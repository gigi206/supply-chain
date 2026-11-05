#!/usr/bin/python3 -I
"""Brique 07a, G8 : fraîcheur de ce que la porte exige (D4), en métriques servies par fichiers-metriques (brique 19), lancé par
fraicheur-scan.service sur sc-stockage. Lectures anonymes de Zot, par HTTPS, bibliothèque standard seulement :
  referrer de scan le plus récent de l'image : org.opencontainers.image.created, annotation écrite par scanner.sh (publier) ;
                                               elle n'est pas signée, la porte lit le scannedAt signé
  base la plus récente de vulndb/grype       : tag daté choisi comme scanner.sh, org.opencontainers.image.created de son manifeste
Lecture impossible : code d'erreur, fichier inchangé, et l'âge continue de croître. Aucun referrer de scan, ou aucune base : la
série n'est pas écrite (absent() des règles). Le fichier est créé par plateforme.sh g8_metriques, seul chemin écrit ici."""
import datetime
import json
import os
import re
import ssl
import urllib.request

REG = os.environ["REG"]
DEPOT_SCAN = os.environ["DEPOT_SCAN"]
DEPOT_BASE = os.environ["DEPOT_BASE"]
DIGEST = os.environ["DIGEST"]
SORTIE = os.environ.get("SORTIE", "/etc/fichiers-metriques/fraicheur-scan.prom")
PREDICAT = "https://supply-chain.example/scan/v1"
INDEX = "application/vnd.oci.image.index.v1+json"
MANIFESTE = "application/vnd.oci.image.manifest.v1+json"
TLS = ssl.create_default_context(cafile=os.environ["CA"])


def lire(chemin, accepte="application/json"):
    requete = urllib.request.Request(f"https://{REG}/v2/{chemin}", headers={"Accept": accepte})
    with urllib.request.urlopen(requete, timeout=20, context=TLS) as reponse:
        return json.load(reponse)


def epoque(date):
    return int(datetime.datetime.fromisoformat(date).timestamp())


def dernier_scan():
    dates = [
        epoque(m["annotations"]["org.opencontainers.image.created"])
        for m in lire(f"{DEPOT_SCAN}/referrers/{DIGEST}", INDEX).get("manifests") or []
        if m.get("annotations", {}).get("dev.sigstore.bundle.predicateType") == PREDICAT
    ]
    return max(dates, default=None)


def derniere_base():
    tags = lire(f"{DEPOT_BASE}/tags/list").get("tags") or []
    dates = [t for t in tags if re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", t)]
    if not dates:
        return None
    return epoque(lire(f"{DEPOT_BASE}/manifests/{max(dates)}", MANIFESTE)["annotations"]["org.opencontainers.image.created"])


def serie(nom, depot, valeur):
    # Ni HELP ni TYPE : essais-o4.prom, servi avant ce fichier, porte les mêmes noms (incident a7 de la 19).
    return "" if valeur is None else f'{nom}{{depot="{depot}"}} {valeur}\n'


def main():
    scan, base = dernier_scan(), derniere_base()
    corps = serie("scan_dernier_referrer_timestamp_seconds", DEPOT_SCAN, scan)
    corps += serie("base_grype_construite_timestamp_seconds", DEPOT_BASE, base)
    # Réécrit sur place : écrire d'abord, couper ensuite. Jamais de fichier vide ; un fichier raccourci garde sa fin le temps d'un appel.
    donnees = corps.encode()
    f = os.open(SORTIE, os.O_WRONLY)
    try:
        os.pwrite(f, donnees, 0)
        os.ftruncate(f, len(donnees))
    finally:
        os.close(f)
    print(f"scan {scan}, base {base}")


main()
