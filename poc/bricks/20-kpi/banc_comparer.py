#!/usr/bin/env python3
"""Brique 20, étape 3 : compare, sur les témoins du banc, les valeurs du recalcul signé (lignes KPI|) et de l'exportateur (.prom) aux
attendus écrits à la main ci-dessous, avant tout passage, puis entre elles. Passage du .prom aux lignes KPI| :
  kpi_<nom>{depot,digest} v         -> <nom> ; série absente d'un sujet qui a une provenance de référence -> « absent » ;
  kev_ouvertes = kev - kev_ecartees ; couverture_vex_* = « n/d », « sans objet » si d = 0, « absent » sans scan ;
  taux_* = somme / nombre de sujets ; kev_delais : séries kpi_kev_ouverture et kpi_kev_fermeture d'un dépôt, par ouverture ;
  violations_licences : aucune série, donc « source absente ».
Usage : banc_comparer.py <journal du recalcul> <exportateur.prom>"""
import re
import sys

J20, J21 = 1795132800, 1795219200   # 2026-11-20 et 2026-11-21, 00:00:00Z
K1, K2, K3 = 1793491200, 1794139200, 1794268800   # 2026-11-01T00:00:00Z, 2026-11-08T12:00:00Z, 2026-11-10T00:00:00Z
NOMS = ("provenance_chains_verifiee", "provenances_pipelinerun", "replay_identique", "l3_verifie", "vex_verifies", "scan_entrees",
        "scan_ecartees", "scan_kev", "scan_kev_ecartees", "kev_ouvertes", "couverture_vex_entrees", "couverture_vex_kev", "scan_date")
A, SO = "absent", "sans objet"
RIEN = (A,) * 8
# une ligne par sujet, dans l'ordre de NOMS (recalcul signé)
SUJETS = {
    "banc-complet": (1, 1, 1, 1, 1, 3, 2, 1, 1, 0, "2/3", "1/1", J20),
    "banc-sans-vsa": (1, 1, 0, 0, 0, 0, 0, 0, 0, 0, SO, SO, J20),
    "banc-vsa-failed": (1, 1, 0, 0, 0, 1, 0, 1, 0, 1, "0/1", "0/1", J20),
    "banc-forge": (1, 1, 0, 0, 0, 1, 0, 1, 0, 1, "0/1", "0/1", J20),
    "banc-prov-forgee": (0, 0, 0, 0, 0) + RIEN,
    "banc-prov-seule": (1, 1, 0, 0, 0) + RIEN,
    "banc-prov-tache": (0, 0, 0, 0, 0) + RIEN,
    "banc-sans-sig": (0, 1, 0, 0, 0) + RIEN,
    "banc-kev": (1, 1, 0, 0, 0, 2, 1, 2, 1, 1, "1/2", "1/2", K3),
}
PLATEFORME = {"taux_provenance_chains_verifiee": "6/9", "taux_l3_verifie": "1/9", "taux_replay_identique": "1/9",
              "violations_licences": "source absente"}
DELAIS = [("CVE-2026-90001", K1, K2), ("CVE-2026-90002", K1, K3), ("CVE-2026-90003", K3, None)]
# écarts prédits de l'exportateur, qui ne vérifie pas : uniquement les deux sujets à signature fausse et les taux qui les comptent
FORGES = {"banc-forge": (1, 1, 1, 1, 1, 0, 0, 0, 0, 0, SO, SO, J21), "banc-prov-forgee": (1, 1, 0, 0, 0) + RIEN}
TAUX_FORGES = {"taux_provenance_chains_verifiee": "7/9", "taux_l3_verifie": "2/9", "taux_replay_identique": "2/9"}


def attendus(sujets, plateforme):
    v = {(n, f"builds/{s}"): str(x) for s, vals in sujets.items() for n, x in zip(NOMS, vals, strict=True)}
    v.update({(n, "-"): x for n, x in plateforme.items()})
    v[("kev_delais", "builds/banc-kev")] = str(DELAIS)
    return v


def lire_recalcul(f):
    v = {}
    for ligne in open(f, encoding="utf-8"):
        if ligne.startswith("KPI|"):
            _, nom, depot, _, valeur = ligne.rstrip("\n").split("|", 4)
            assert (nom, depot) not in v, f"ligne en double : {nom} {depot}"
            v[(nom, depot)] = valeur
    return v


def lire_prom(f):
    s = {}
    for ligne in open(f, encoding="utf-8"):
        nom, etiq, val = re.fullmatch(r"kpi_(\w+)\{(.*)\} (\d+)\n", ligne).groups()
        e = dict(re.findall(r'(\w+)="([^"]*)"', etiq))
        assert (nom, e["depot"], e.get("kev"), e.get("ouverture")) not in s, f"série en double : {ligne}"
        s[(nom, e["depot"], e.get("kev"), e.get("ouverture"))] = int(val)
    depots = sorted({d for n, d, _, _ in s if n == "provenance_chains_verifiee"})
    v = {}
    for d in depots:
        g = lambda n: s.get((n, d, None, None))  # noqa: E731
        for n in ("provenance_chains_verifiee", "provenances_pipelinerun", "replay_identique", "l3_verifie", "vex_verifies",
                  "scan_entrees", "scan_ecartees", "scan_kev", "scan_kev_ecartees"):
            v[(n, d)] = A if g(n) is None else str(g(n))
        v[("scan_date", d)] = A if g("scan_timestamp_seconds") is None else str(g("scan_timestamp_seconds"))
        sans = g("scan_entrees") is None
        v[("kev_ouvertes", d)] = A if sans else str(g("scan_kev") - g("scan_kev_ecartees"))
        for n, a, b in (("couverture_vex_entrees", "scan_ecartees", "scan_entrees"), ("couverture_vex_kev", "scan_kev_ecartees", "scan_kev")):
            v[(n, d)] = A if sans else f"{g(a)}/{g(b)}" if g(b) else SO
    for t, n in (("taux_provenance_chains_verifiee", "provenance_chains_verifiee"), ("taux_l3_verifie", "l3_verifie"),
                 ("taux_replay_identique", "replay_identique")):
        v[(t, "-")] = f"{sum(s[(n, d, None, None)] for d in depots)}/{len(depots)}"
    v[("violations_licences", "-")] = "source absente" if not any(n == "violations_licences" for n, *_ in s) else "série inattendue"
    ouvertes = {}
    for (n, d, k, o), val in s.items():
        if n == "kev_ouverture_timestamp_seconds":
            ouvertes.setdefault(d, []).append((k, int(o), s.get(("kev_fermeture_timestamp_seconds", d, k, o))))
    for d, lignes in ouvertes.items():
        v[("kev_delais", d)] = str(sorted(lignes, key=lambda x: (x[1], x[0])))
    return v, sum(val for (n, *_), val in s.items() if n == "enonces_refuses")


ko = [0, 0]


def cas(nom, obtenu, voulu):
    ko[0] += 1
    ko[1] += obtenu != voulu
    print(f"{'OK  ' if obtenu == voulu else 'KO  '} {nom} : {obtenu}" + ("" if obtenu == voulu else f" (attendu {voulu})"))


def differences(a, b):
    return sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))


signe, (nonsigne, refuses) = lire_recalcul(sys.argv[1]), lire_prom(sys.argv[2])
ref, exp = attendus(SUJETS, PLATEFORME), attendus({**SUJETS, **FORGES}, {**PLATEFORME, **TAUX_FORGES})
for qui, obtenu, voulu in (("recalcul", signe, ref), ("exportateur", nonsigne, exp)):
    for k in differences(obtenu, voulu):
        print(f"DIFF|{qui}|{k[0]}|{k[1]}|{obtenu.get(k)}|attendu {voulu.get(k)}")
    cas(f"{qui} : valeurs différentes des attendus écrits à la main, sur {len(voulu)}", len(differences(obtenu, voulu)), 0)
entre = differences(signe, nonsigne)
for k in entre:
    print(f"ECART|{k[0]}|{k[1]}|recalcul {signe.get(k)}|exportateur {nonsigne.get(k)}")
cas("écarts recalcul contre exportateur hors des témoins à signature fausse et des taux",
    sum(1 for k in entre if k[1] not in ("builds/banc-forge", "builds/banc-prov-forgee", "-")), 0)
cas("écarts recalcul contre exportateur dus aux signatures fausses", len(entre), len(differences(ref, exp)))
cas("énoncés refusés par l'exportateur (forme)", refuses, 0)
print(f"## bilan : {ko[0]} cas, {ko[1]} écart(s)")
sys.exit(1 if ko[1] else 0)
