#!/usr/bin/env python3
"""Brique 20, étape 6 : témoins des requêtes du tableau « KPI supply-chain », pour promtool test rules (promql_expr_test). Les requêtes sont lues
dans le JSON du tableau ; les séries et les valeurs attendues sont écrites ici, à la main, pour quatre états de l'exportateur :
  mixte    4 digests (dont le rpm sans scan et un scan à 0 entrée), KEV fermée, rouverte, et même KEV ouverte dans un autre dépôt ;
  zeros    2 digests, rien de conforme, aucune KEV, tout scanné : des 0, jamais « aucune série » ;
  journal  1 digest sans scan, journal illisible : séries KEV absentes ;
  absent   aucune série kpi_* : toute requête est vide (pas de faux 0).
Toute requête du tableau doit avoir un attendu dans chaque état, et tout attendu une requête.
Usage : tableau_temoins.py <tableau.json> [<panneau+cible> <ancien> <nouveau>]   (écrit le test sur la sortie ; mutant facultatif)"""
import json
import sys

JOB = 'job="fichiers", instance="local"'
A1, A2 = 'depot="builds/sample-app", digest="aaaaaaaaaaaa"', 'depot="builds/sample-app", digest="bbbbbbbbbbbb"'
DEB, RPM = 'depot="builds/sample-app-deb", digest="cccccccccccc"', 'depot="builds/sample-app-rpm", digest="dddddddddddd"'
T = 600  # promtool : time() à 10 min


def serie(nom, etiquettes, valeur):
    return f"{nom}{{{etiquettes}{', ' if etiquettes else ''}{JOB}}}", valeur


def sujets(nom, *paires):
    return [serie(nom, e, v) for e, v in paires]


def kev(quoi, depot, cve, debut, valeur):
    return serie(f"kpi_kev_{quoi}_timestamp_seconds", f'depot="builds/{depot}", kev="{cve}", ouverture="{debut}"', valeur)


def pin(sujet, genre, nom, p, retire, date):
    return serie("kpi_pin_timestamp_seconds", f'{sujet}, genre="{genre}", nom="{nom}", pin="{p}", retire="{retire}"', date)


def exportateur(passage, journal, cles, illisible):
    return [serie("kpi_exportateur_passage_timestamp_seconds", "", passage), serie("kpi_exportateur_journal_timestamp_seconds", "", journal),
            serie("kpi_cles_non_relevees", "", cles), serie("kpi_exportateur_journal_illisible", "", illisible)]


MIXTE = (exportateur(540, 480, 1, 0)
         + sujets("kpi_l3_verifie", (A1, 1), (A2, 0), (DEB, 0), (RPM, 0)) + sujets("kpi_replay_identique", (A1, 1), (A2, 0), (DEB, 1), (RPM, 0))
         + sujets("kpi_provenance_chains_verifiee", (A1, 1), (A2, 1), (DEB, 1), (RPM, 0)) + sujets("kpi_vex_verifies", (A1, 1), (A2, 0), (DEB, 2), (RPM, 0))
         + sujets("kpi_enonces_refuses", (A1, 0), (A2, 1), (DEB, 0), (RPM, 0)) + sujets("kpi_pins_non_releves", (A1, 2), (A2, 0), (DEB, 0), (RPM, 0))
         + sujets("kpi_signatures_refusees", (A1 + ', famille="prov"', 1), (A1 + ', famille="vex"', 0), (DEB + ', famille="vex"', 2))
         + sujets("kpi_scan_entrees", (A1, 6), (A2, 0), (DEB, 67)) + sujets("kpi_scan_ecartees", (A1, 3), (A2, 0), (DEB, 0))
         + sujets("kpi_scan_kev", (A1, 3), (A2, 0), (DEB, 0)) + sujets("kpi_scan_kev_ecartees", (A1, 1), (A2, 0), (DEB, 0))
         + sujets("kpi_scan_timestamp_seconds", (A1, 60), (A2, 60), (DEB, 60))
         + [kev("ouverture", "sample-app", "CVE-1", 100, 100), kev("fermeture", "sample-app", "CVE-1", 100, 300), kev("ouverture", "sample-app", "CVE-1", 400, 400),
            kev("ouverture", "sample-app-deb", "CVE-1", 100, 100)]
         + [serie("kpi_cle_timestamp_seconds", 'cle="chains", empreinte="e1"', 0), serie("kpi_cle_timestamp_seconds", 'cle="vsa", empreinte="e2"', 100)]
         + [pin(A1, "image", "x", "p1", 0, 100), pin(A1, "tache", "y", "p2", 1, 50), pin(DEB, "image", "x", "p1", 0, 100), pin(RPM, "source", "z", "p3", 0, 200)]
         + [serie("kpi_pin_non_epingle", f'{s}, genre="pipeline", nom="{n}", pin="{n}"', 1) for s, n in ((A1, "q1"), (A1, "q2"), (DEB, "q3"))])
ZEROS = (exportateur(600, 600, 0, 0)
         + sujets("kpi_l3_verifie", (A1, 0), (DEB, 0)) + sujets("kpi_replay_identique", (A1, 0), (DEB, 0))
         + sujets("kpi_provenance_chains_verifiee", (A1, 0), (DEB, 0)) + sujets("kpi_vex_verifies", (A1, 0), (DEB, 0))
         + sujets("kpi_enonces_refuses", (A1, 0), (DEB, 0)) + sujets("kpi_pins_non_releves", (A1, 0), (DEB, 0))
         + sujets("kpi_signatures_refusees", (A1 + ', famille="prov"', 0), (DEB + ', famille="vex"', 0))
         + sujets("kpi_scan_entrees", (A1, 4), (DEB, 4)) + sujets("kpi_scan_ecartees", (A1, 0), (DEB, 4))
         + sujets("kpi_scan_kev", (A1, 0), (DEB, 0)) + sujets("kpi_scan_kev_ecartees", (A1, 0), (DEB, 0))
         + sujets("kpi_scan_timestamp_seconds", (A1, 60), (DEB, 60)))
JOURNAL = (exportateur(600, 0, 0, 1) + sujets("kpi_l3_verifie", (RPM, 0)) + sujets("kpi_replay_identique", (RPM, 0))
           + sujets("kpi_provenance_chains_verifiee", (RPM, 1)) + sujets("kpi_vex_verifies", (RPM, 0)) + sujets("kpi_enonces_refuses", (RPM, 0))
           + sujets("kpi_pins_non_releves", (RPM, 0)) + sujets("kpi_signatures_refusees", (RPM + ', famille="prov"', 0)))


def vide():
    return {}


def un(v):
    return {"{}": v}


def local(v):  # vecteur qui garde les étiquettes de collecte, sans nom de métrique
    return {f"{{{JOB}}}": v}


def par(nom, garde, *paires):
    return {f"{nom}{{{e}{', ' + JOB if garde else ''}}}": v for e, v in paires}


def k(depot, cve, debut):
    return f'{{depot="builds/{depot}", kev="{cve}", ouverture="{debut}"}}'


ATTENDUS = {
    "mixte": (MIXTE, {
        "2A": local(60), "2B": local(120), "3A": un(3), "3B": un(1), "3C": par("kpi_cles_non_relevees", False, (JOB, 1)), "3D": un(2),
        "3E": par("kpi_exportateur_journal_illisible", False, (JOB, 0)),
        "4A": un(0.25), "4B": un(1), "4C": un(4), "5A": un(0.5), "5B": un(2), "5C": un(4), "6A": un(0.75), "6B": un(3), "6C": un(4),
        "7A": par("kpi_l3_verifie", True, (A1, 1), (A2, 0), (DEB, 0), (RPM, 0)), "8A": par("kpi_replay_identique", True, (A1, 1), (A2, 0), (DEB, 1), (RPM, 0)),
        "9A": par("kpi_provenance_chains_verifiee", True, (A1, 1), (A2, 1), (DEB, 1), (RPM, 0)),
        "10A": par("", True, (A1, 2), (A2, 0), (DEB, 0)), "11A": par("", True, (A1, 0.5), (A2, "NaN"), (DEB, 0)), "12A": un(1), "12B": un(3),
        "13A": {k("sample-app", "CVE-1", 100): 200},
        "14A": {k("sample-app", "CVE-1", 400)[:-1] + f", {JOB}}}": 200, k("sample-app-deb", "CVE-1", 100)[:-1] + f", {JOB}}}": 500},
        "15A": par("", True, ('cle="chains", empreinte="e1"', 600), ('cle="vsa", empreinte="e2"', 500)),
        "16A": par("", False, (A1, 550), (DEB, 500), (RPM, 400)), "17A": par("", False, (A1, 2), (A2, 0), (DEB, 1), (RPM, 0)),
        "18A": par("", False, ('genre="tache", nom="y", pin="p2", retire="1"', 550), ('genre="image", nom="x", pin="p1", retire="0"', 500),
                   ('genre="source", nom="z", pin="p3", retire="0"', 400))}),
    "zeros": (ZEROS, {
        "2A": local(0), "2B": local(0), "3A": un(0), "3B": un(0), "3C": par("kpi_cles_non_relevees", False, (JOB, 0)), "3D": un(0),
        "3E": par("kpi_exportateur_journal_illisible", False, (JOB, 0)),
        "4A": un(0), "4B": un(0), "4C": un(2), "5A": un(0), "5B": un(0), "5C": un(2), "6A": un(0), "6B": un(0), "6C": un(2),
        "7A": par("kpi_l3_verifie", True, (A1, 0), (DEB, 0)), "8A": par("kpi_replay_identique", True, (A1, 0), (DEB, 0)),
        "9A": par("kpi_provenance_chains_verifiee", True, (A1, 0), (DEB, 0)), "10A": par("", True, (A1, 0), (DEB, 0)),
        "11A": par("", True, (A1, 0), (DEB, 1)), "12A": un(0), "12B": un(0), "13A": vide(), "14A": vide(), "15A": vide(), "16A": vide(),
        "17A": par("", False, (A1, 0), (DEB, 0)), "18A": vide()}),
    "journal": (JOURNAL, {
        "2A": local(0), "2B": local(600), "3A": un(0), "3B": un(0), "3C": par("kpi_cles_non_relevees", False, (JOB, 0)), "3D": un(0),
        "3E": par("kpi_exportateur_journal_illisible", False, (JOB, 1)),
        "4A": un(0), "4B": un(0), "4C": un(1), "5A": un(0), "5B": un(0), "5C": un(1), "6A": un(1), "6B": un(1), "6C": un(1),
        "7A": par("kpi_l3_verifie", True, (RPM, 0)), "8A": par("kpi_replay_identique", True, (RPM, 0)), "9A": par("kpi_provenance_chains_verifiee", True, (RPM, 1)),
        "10A": vide(), "11A": vide(), "12A": un(1), "12B": un(0), "13A": vide(), "14A": vide(), "15A": vide(), "16A": vide(),
        "17A": par("", False, (RPM, 0)), "18A": vide()}),
    "absent": ([], None),
}

with open(sys.argv[1], encoding="utf-8") as f:
    requetes = {f"{p['id']}{t['refId']}": t["expr"] for p in json.load(f)["panels"] for t in p.get("targets", [])}
if sys.argv[2:]:
    ou, ancien, nouveau = sys.argv[2:]
    if ancien not in requetes[ou]:
        sys.exit(f"mutant : « {ancien} » absent de {ou}")
    requetes[ou] = requetes[ou].replace(ancien, nouveau)
tests = []
for etat, (series, attendus) in ATTENDUS.items():
    attendus = dict.fromkeys(requetes, {}) if attendus is None else attendus
    if set(attendus) != set(requetes):
        sys.exit(f"{etat} : requêtes et attendus différents : {sorted(set(attendus) ^ set(requetes))}")
    tests.append({"name": etat, "interval": "1m", "input_series": [{"series": s, "values": f"{v}x20"} for s, v in series],
                  "promql_expr_test": [{"expr": requetes[q], "eval_time": "10m", "exp_samples": [{"labels": e, "value": v} for e, v in attendus[q].items()]}
                                       for q in sorted(requetes)]})
# le test est du YAML : .nan, et non la chaîne "NaN" (premier passage, e6-promql-banc.log)
sys.stdout.write(json.dumps({"evaluation_interval": "1m", "tests": tests}, ensure_ascii=False, indent=1).replace('"value": "NaN"', '"value": .nan'))
print(f"{len(requetes)} requêtes, {len(tests)} états, {sum(len(t['promql_expr_test']) for t in tests)} cas", file=sys.stderr)
