#!/usr/bin/env python3
"""Brique 20, étape 2, contrôle après le passage e2-recalcul.log : quels scans signés de Zot n'ont pas de liste dans Loki ?
Lecture seule (Zot en anonyme, Grafana par l'auditeur). Usage (racine du dépôt) : mise exec -- python3 -I poc/bricks/20-kpi/loki-scans.py"""
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recalcul as r  # noqa: E402

t = int(subprocess.run(["date", "-u", "+%s"], capture_output=True, text=True, check=True).stdout)
print(f"# loki-scans.py, {subprocess.run(['date', '-u', '+%FT%TZ'], capture_output=True, text=True).stdout.strip()}")
emis = {}
for ns, l in r.loki('{source="journal", unite="entrees-scan.service"} |= "liste émise"', t - 719 * 3600, t):
    for depot, _, date in re.findall(r"(builds/scan/\S+?)=(\d+)@(\S+) \(liste émise\)", l):
        emis.setdefault((depot, date), ns // 10**9)
for nom in r.PRODUITS[:2]:
    tags = r.zot(f"builds/{nom}/tags/list")["tags"]
    for d in sorted({f"sha256:{x[7:71]}" for x in tags if re.fullmatch(r"sha256-[0-9a-f]{64}\.[a-z]+", x)}):
        for e, _ in sorted(r.cosign(nom, d, r.CLES["scanner"], r.T_SCAN, f"builds/scan/{nom}"), key=lambda x: x[0]["predicate"]["scannedAt"]):
            s = e["predicate"]["scannedAt"]
            x = emis.get((f"builds/scan/{nom}", s))
            print(f"SCAN|builds/{nom}|{d[7:19]}|{s}|{'liste dans Loki, ' + str(x) if x else 'ABSENT de Loki'}")
