#!/usr/bin/env python3
"""Brique 20, étape 2 : essais des calculs purs (kpi.py) sur un jeu synthétique. Il n'y a aucune KEV dans la plateforme : sans ce
jeu, le délai de correction ne serait jamais exercé. Usage (racine du dépôt) : python3 poc/bricks/20-kpi/essais_kpi.py"""
import os
import sys

sys.dont_write_bytecode = True

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kpi import comptes_scan, delais_kev, rapport  # noqa: E402

CAS = [
    ("rapport ordinaire", rapport(2, 4), "2/4"),
    ("rapport nul", rapport(0, 4), "0/4"),
    ("rapport 0/0 : sans objet", rapport(0, 0), None),
    ("scan sans vulnérabilité", comptes_scan({"vulnerabilities": []}), {"entrees": 0, "ecartees": 0, "kev": 0, "kev_ecartees": 0}),
    ("scan : champ absent", comptes_scan({}), {"entrees": 0, "ecartees": 0, "kev": 0, "kev_ecartees": 0}),
    ("scan : KEV ouverte, KEV écartée, entrée écartée, entrée simple",
     comptes_scan({"vulnerabilities": [{"kev": True}, {"kev": True, "vex": {"statut": "x"}}, {"vex": {"statut": "x"}}, {}]}),
     {"entrees": 4, "ecartees": 2, "kev": 2, "kev_ecartees": 1}),
    ("délai : aucun scan", delais_kev([]), []),
    ("délai : aucune KEV", delais_kev([(10, []), (20, [])]), []),
    ("délai : ouverte puis absente", delais_kev([(10, [("A", False)]), (30, [])]), [("A", 10, 30)]),
    ("délai : ouverte puis écartée par un VEX", delais_kev([(10, [("A", False)]), (30, [("A", True)])]), [("A", 10, 30)]),
    ("délai : toujours ouverte", delais_kev([(10, [("A", False)]), (30, [("A", False)])]), [("A", 10, None)]),
    ("délai : écartée dès le premier scan, jamais ouverte", delais_kev([(10, [("A", True)])]), []),
    ("délai : rouverte", delais_kev([(10, [("A", False)]), (20, []), (30, [("A", False)])]), [("A", 10, 20), ("A", 30, None)]),
    ("délai : deux paquets, un seul écarté, donc ouverte",
     delais_kev([(10, [("A", False), ("A", False)]), (20, [("A", True), ("A", False)])]), [("A", 10, None)]),
    ("délai : scans reçus dans le désordre", delais_kev([(30, []), (10, [("A", False)])]), [("A", 10, 30)]),
    ("délai : deux KEV, deux durées",
     delais_kev([(10, [("A", False), ("B", False)]), (20, [("B", False)]), (40, [])]), [("A", 10, 20), ("B", 10, 40)]),
]
ko = 0
for nom, obtenu, attendu in CAS:
    ok = obtenu == attendu
    ko += not ok
    print(f"{'OK  ' if ok else 'KO  '} {nom} : {obtenu}{'' if ok else f' (attendu {attendu})'}")
print(f"## bilan : {len(CAS)} cas, {ko} écart(s)")
sys.exit(1 if ko else 0)
