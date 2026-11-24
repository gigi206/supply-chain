#!/usr/bin/python3 -I
"""Brique 20 : lecteur des lignes de entrees-scan dans Loki, pour les délais des KEV (décision du 24/11 : « Loki, 720 h (Recommandé) »).
Séparé de l'exportateur : celui qui analyse le contenu de Zot et lance openssl ne porte aucun secret. Ce programme n'analyse rien : il
écrit les lignes brutes dans SORTIE, le fichier JOURNAL de metrics_exporter.py. Transport : API de Grafana (/api/ds/query), compte en
lecture seule, mot de passe lu dans un fichier ; l'accès en service est un choix du propriétaire à poser (étape 4).
Deux requêtes : les résumés « liste émise » (les scans, même sans entrée) et les entrées KEV. Fenêtre de 719 h (Loki refuse plus de
721 h). LIMITE lignes rendues : la réponse est peut-être tronquée. Réponse tronquée, en erreur, illisible ou HTTP autre que 200 :
code 2, fichier inchangé.
Variables : GRAFANA (https://hôte:port), CA, UTILISATEUR, MDP (fichier), SORTIE (existant)."""
import base64
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

BASE = '{source="journal", unite="entrees-scan.service"}'
REQUETES = (BASE + ' |= "liste émise"', BASE + ' |= "\\"kev\\":true"')
LIMITE = 5000


class Refus(Exception):
    pass


def lire(expr, debut, fin):
    with open(os.environ["MDP"], encoding="utf-8") as f:
        acces = f"{os.environ['UTILISATEUR']}:{f.read().strip()}"
    corps = {"from": f"{debut}000", "to": f"{fin}000", "queries": [
        {"refId": "A", "datasource": {"uid": "loki"}, "expr": expr, "queryType": "range", "maxLines": LIMITE, "direction": "forward"}]}
    requete = urllib.request.Request(f"{os.environ['GRAFANA']}/api/ds/query", data=json.dumps(corps).encode(), method="POST", headers={
        "Content-Type": "application/json", "Authorization": "Basic " + base64.b64encode(acces.encode()).decode()})
    with urllib.request.urlopen(requete, timeout=60, context=ssl.create_default_context(cafile=os.environ["CA"])) as r:
        a = json.load(r)["results"]["A"]
    if a.get("error") or a.get("status", 200) != 200:
        raise Refus("requête en erreur")
    lignes = []
    for f in a.get("frames") or []:
        noms = [c["name"] for c in f["schema"]["fields"]]
        if f["data"]["values"]:
            lignes += f["data"]["values"][noms.index("Line")]
    if len(lignes) >= LIMITE:
        raise Refus(f"{len(lignes)} lignes, réponse peut-être tronquée")
    return lignes


def main():
    fin = int(time.time())
    try:
        lignes = [x for q in REQUETES for x in lire(q, fin - 719 * 3600, fin)]
        if any(not isinstance(x, str) or "\n" in x for x in lignes):
            raise Refus("ligne illisible")
    except (Refus, urllib.error.URLError, OSError, ValueError, KeyError, TypeError, AttributeError) as e:
        print(f"refus : {type(e).__name__}" + (f" : {e}" if isinstance(e, Refus) else f" {getattr(e, 'code', '')}"), file=sys.stderr)
        return 2
    donnees = "".join(x + "\n" for x in lignes).encode()
    f = os.open(os.environ["SORTIE"], os.O_WRONLY)  # réécrit sur place, comme l'exportateur
    try:
        os.pwrite(f, donnees, 0)
        os.ftruncate(f, len(donnees))
        os.utime(f)  # même contenu : l'heure de lecture doit avancer quand même
    finally:
        os.close(f)
    print(f"journal : {len(lignes)} lignes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
