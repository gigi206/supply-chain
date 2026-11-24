#!/usr/bin/env python3
"""Brique 20, étape 3 (complément) : compare, sujet par sujet, l'exportateur lancé sur le vrai Zot (lecture anonyme) au recalcul signé.
Mêmes passages que banc_comparer.py, mais par (nom, dépôt, digest) : les produits ont plusieurs digests par dépôt. Depuis
l'étape 4, rien n'est hors comparaison : kev_delais (une série absente vaut « sans objet (0 KEV vue) » : sans KEV, l'égalité ne prouve que
l'absence), pin_date et cle_date (relevé versionné). Les comptes de signatures (kpi_signatures_*) sont comparés
aux lignes DETAIL| du même recalcul ; le second .prom vient de l'exportateur lancé avec une clé étrangère.
Usage : comparer_zot.py <journal du recalcul> <exportateur.prom> <exportateur, clé étrangère.prom>"""
import re
import sys

A, SO = "absent", "sans objet"
signe = {}
for ligne in open(sys.argv[1], encoding="utf-8"):
    if ligne.startswith("KPI|"):
        _, nom, depot, digest, valeur = ligne.rstrip("\n").split("|", 4)
        assert (nom, depot, digest) not in signe, f"ligne en double : {nom} {depot} {digest}"
        signe[(nom, depot, digest)] = valeur
FAM = re.compile(r'kpi_signatures_(verifiees|refusees)\{depot="([^"]+)",digest="([0-9a-f]{12})",famille="(\w+)"\} (\d+)\n')
s = {}
for ligne in open(sys.argv[2], encoding="utf-8"):
    if FAM.fullmatch(ligne) or re.match("kpi_(exportateur|pins?|cles?|kev)_", ligne):
        continue
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
sans_date = n_kev = 0
for ligne in open(sys.argv[2], encoding="utf-8"):
    m = re.fullmatch(r'kpi_pin_(timestamp_seconds|non_epingle)\{depot="([^"]+)",digest="([0-9a-f]{12})",genre="(\w+)",nom="([^"]+)",'
                     r'pin="([0-9a-f]{12})"(?:,retire="([01])")?\} (\d+)\n', ligne)
    if m:
        exporte[(f"pin_date:{m[4]}:{m[5]}:{m[6]}", m[2], m[3])] = ("non épinglé dans git" if m[1] == "non_epingle"
                                                                 else m[8] + (" (retiré depuis)" if m[7] == "1" else ""))
        continue
    m = re.fullmatch(r'kpi_cle_timestamp_seconds\{cle="(\w+)",empreinte="[0-9a-f]{12}"\} (\d+)\n', ligne)
    if m:
        exporte[(f"cle_date:{m[1]}", "-", "-")] = m[2]
    m = re.fullmatch(r"kpi_(?:pins_non_releves\{.*\}|cles_non_relevees) (\d+)\n", ligne)
    if m:
        sans_date += int(m[1])
    n_kev += ligne.startswith("kpi_kev_")
for n, d, h in signe:
    if n == "kev_delais" and not n_kev:   # une KEV vue doit être convertie comme au banc ; ici, aucune n'est attendue
        exporte[(n, d, h)] = "sans objet (0 KEV vue)"
diff = sorted(k for k in set(signe) | set(exporte) if signe.get(k) != exporte.get(k))
for k in diff:
    print(f"ECART|{'|'.join(k)}|recalcul {signe.get(k)}|exportateur {exporte.get(k)}")
refuses = sum(v for (n, *_), v in s.items() if n == "enonces_refuses")


def signatures(f):
    """{(dépôt, digest, famille): [vérifiées, refusées]}, familles vides omises."""
    v = {}
    for m in filter(None, map(FAM.fullmatch, open(f, encoding="utf-8"))):
        v.setdefault((m[2], m[3], m[4]), [0, 0])[m[1] == "refusees"] = int(m[5])
    return {k: x for k, x in v.items() if x != [0, 0]}


bonnes, temoin, rec = signatures(sys.argv[2]), signatures(sys.argv[3]), {}
for ligne in open(sys.argv[1], encoding="utf-8"):
    c = ligne.split("|")
    if c[0] == "DETAIL" and c[1].startswith("builds/"):
        rec[(c[1], c[2], "sig")] = [int(c[3].split()[1]), 0]
        for x in c[4:8]:
            a, b, _ = map(int, x.split()[1].split("/"))
            if a:
                rec[(c[1], c[2], x.split()[0])] = [b, a - b]
for k in sorted(k for k in set(rec) | set(bonnes) if rec.get(k) != bonnes.get(k)):
    print(f"ECART|signatures|{'|'.join(k)}|recalcul {rec.get(k)}|exportateur {bonnes.get(k)}")
inverse = {k: [0, sum(v)] for k, v in bonnes.items()}
sous_temoin = {}
for ligne in open(sys.argv[3], encoding="utf-8"):
    if ligne.startswith("kpi_exportateur_"):
        continue
    m = re.fullmatch(r"kpi_(\w+)\{[^}]*\} (\d+)\n", ligne)
    if not m[1].startswith("signatures_"):
        sous_temoin[m[1]] = sous_temoin.get(m[1], 0) + int(m[2])
ko = n = 0
for nom, obtenu, voulu in (("sujets", len(sujets), 4), ("valeurs comparées", len(set(signe) | set(exporte)), 105), ("clés et pins sans date", sans_date, 0), ("séries de KEV", n_kev, 0),
                           ("écarts recalcul contre exportateur", len(diff), 0), ("énoncés refusés pour leur forme", refuses, 0),
                           ("comptes de signatures par sujet et famille, recalcul contre exportateur : écarts",
                            sum(1 for k in set(rec) | set(bonnes) if rec.get(k) != bonnes.get(k)), 0),
                           ("signatures refusées avec les clés du dépôt", sum(v[1] for v in bonnes.values()), 0),
                           ("clé étrangère : toutes les signatures refusées, aucune vérifiée", temoin == inverse and len(temoin) > 0, True),
                           ("clé étrangère : séries restantes et leur somme", sous_temoin, {
                               "enonces_refuses": 0, "l3_verifie": 0, "provenance_chains_verifiee": 0, "provenances_pipelinerun": 0,
                               "replay_identique": 0, "vex_verifies": 0})):
    n += 1
    ko += obtenu != voulu
    print(f"{'OK  ' if obtenu == voulu else 'KO  '} {nom} : {obtenu}" + ("" if obtenu == voulu else f" (attendu {voulu})"))
print(f"signatures [vérifiées, refusées] : clés du dépôt {[sum(v[i] for v in bonnes.values()) for i in (0, 1)]}, clé étrangère {[sum(v[i] for v in temoin.values()) for i in (0, 1)]}")
print(f"## bilan : {n} cas, {ko} écart(s)")
sys.exit(1 if ko else 0)
