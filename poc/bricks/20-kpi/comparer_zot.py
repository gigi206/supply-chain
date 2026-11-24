#!/usr/bin/env python3
"""Brique 20, étape 3 (complément) : compare, sujet par sujet, l'exportateur lancé sur le vrai Zot (lecture anonyme) au recalcul signé.
Mêmes passages que banc_comparer.py, mais par (nom, dépôt, digest) : les produits ont plusieurs digests par dépôt. Hors comparaison :
kev_delais (source Loki, non lue par l'exportateur), pin_date et cle_date (git).
Usage : comparer_zot.py <journal du recalcul> <exportateur.prom>"""
import re
import sys

A, SO = "absent", "sans objet"
HORS = re.compile(r"kev_delais|pin_date:.*|cle_date:.*")
signe, ignores = {}, 0
for ligne in open(sys.argv[1], encoding="utf-8"):
    if ligne.startswith("KPI|"):
        _, nom, depot, digest, valeur = ligne.rstrip("\n").split("|", 4)
        if HORS.fullmatch(nom):
            ignores += 1
        else:
            signe[(nom, depot, digest)] = valeur
s = {}
for ligne in open(sys.argv[2], encoding="utf-8"):
    nom, depot, digest, val = re.fullmatch(r'kpi_(\w+)\{depot="([^"]+)",digest="([0-9a-f]{12})"\} (\d+)\n', ligne).groups()
    s[(nom, depot, digest)] = int(val)
sujets = sorted({(d, h) for n, d, h in s if n == "provenance_chains_verifiee"})
exporte = {}
for d, h in sujets:
    g = lambda n: s.get((n, d, h))  # noqa: E731
    for n, serie in [(n, n) for n in ("provenance_chains_verifiee", "provenances_pipelinerun", "replay_identique", "l3_verifie",
                                      "vex_verifies", "scan_entrees", "scan_ecartees", "scan_kev", "scan_kev_ecartees")] + [
                                          ("scan_date", "scan_timestamp_seconds")]:
        exporte[(n, d, h)] = A if g(serie) is None else str(g(serie))
    sans = g("scan_entrees") is None
    exporte[("kev_ouvertes", d, h)] = A if sans else str(g("scan_kev") - g("scan_kev_ecartees"))
    for n, a, b in (("couverture_vex_entrees", "scan_ecartees", "scan_entrees"), ("couverture_vex_kev", "scan_kev_ecartees", "scan_kev")):
        exporte[(n, d, h)] = A if sans else f"{g(a)}/{g(b)}" if g(b) else SO
for t, n in (("taux_provenance_chains_verifiee", "provenance_chains_verifiee"), ("taux_l3_verifie", "l3_verifie"),
             ("taux_replay_identique", "replay_identique")):
    exporte[(t, "-", "-")] = f"{sum(s[(n, d, h)] for d, h in sujets)}/{len(sujets)}"
exporte[("violations_licences", "-", "-")] = "source absente"
diff = sorted(k for k in set(signe) | set(exporte) if signe.get(k) != exporte.get(k))
for k in diff:
    print(f"ECART|{'|'.join(k)}|recalcul {signe.get(k)}|exportateur {exporte.get(k)}")
refuses = sum(v for (n, *_), v in s.items() if n == "enonces_refuses")
ko = 0
for nom, obtenu, voulu in (("sujets", len(sujets), 4), ("valeurs comparées", len(set(signe) | set(exporte)), 56),
                           ("écarts recalcul contre exportateur", len(diff), 0), ("énoncés refusés pour leur forme", refuses, 0)):
    ko += obtenu != voulu
    print(f"{'OK  ' if obtenu == voulu else 'KO  '} {nom} : {obtenu}" + ("" if obtenu == voulu else f" (attendu {voulu})"))
print(f"hors comparaison : {ignores} lignes KPI| (délais des KEV, dates git)\n## bilan : 4 cas, {ko} écart(s)")
sys.exit(1 if ko else 0)
