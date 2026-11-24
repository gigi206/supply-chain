#!/usr/bin/env python3
"""Brique 20, étape 4 : lignes au format de entrees-scan.py pour banc-grafana.sh, et délais attendus (mêmes valeurs que banc_comparer.py).
Usage : banc_grafana_lignes.py lignes|beaucoup <racine>   (corps d'écriture de Loki)   |   delais <racine> <fichier lu par le lecteur>"""
import json
import os
import runpy
import sys
import time

quoi, racine = sys.argv[1:3]
D, K = "builds/scan/banc-kev", ["CVE-2026-9000%d" % i for i in (1, 2, 3)]
S = {"2026-11-01T00:00:00Z": [(K[0], 0), (K[1], 0)], "2026-11-08T12:00:00Z": [(K[0], 1), (K[1], 0)], "2026-11-10T00:00:00Z": [(K[0], 1), (K[2], 0)]}
K1, K2, K3 = 1793491200, 1794139200, 1794268800
if quoi == "delais":
    x = runpy.run_path(os.path.join(racine, "tools/metrics-exporter/metrics_exporter.py"))
    d = "builds/banc-kev"
    voulu = sorted(f'kpi_kev_{n}_timestamp_seconds{{depot="{d}",kev="{c}",ouverture="{o}"}} {v}' for n, c, o, v in (
        ("ouverture", K[0], K1, K1), ("fermeture", K[0], K1, K2), ("ouverture", K[1], K1, K1), ("fermeture", K[1], K1, K3), ("ouverture", K[2], K3, K3)))
    lu = sorted(x["kev"](sys.argv[3]).splitlines())
    print("conforme" if lu == voulu else f"différent : {lu}")
    sys.exit()
e = runpy.run_path(os.path.join(racine, "poc/bricks/07a-sbom-grype/systemd/entrees-scan.py"))
v, lignes = [], []
for date, kevs in S.items():
    p = {"scannedAt": date, "vulnerabilities": [{"id": c, "aliases": [], "severity": "High", "kev": True, "kevCves": [c], "epss": 0.1, "fixedIn": [],
                                                 "package": "pkg:generic/x@1", **({"vex": {"status": "not_affected"}} if vex else {})} for c, vex in kevs]}
    lignes += [*e["entrees"](D, p), f"entrées {D}={len(kevs)}@{date} (liste émise)"]
if quoi == "beaucoup":
    lignes = [lignes[0].replace(K[0], f"CVE-2026-{i:05d}") for i in range(5000)]
t = int(time.time())
v = [[f"{t}{i:09d}", x] for i, x in enumerate(lignes)]
print(json.dumps({"streams": [{"stream": {"source": "journal", "unite": "entrees-scan.service"}, "values": v}]}))
