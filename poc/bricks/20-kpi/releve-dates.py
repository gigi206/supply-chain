#!/usr/bin/env python3
"""Brique 20, étape 4 : relevé versionné des dates de git que l'exportateur ne peut pas lire (décisions du 24/11 : « Depuis l'épinglage
(Recommandé) » et « Clé publique dans git (Recommandé) »). Mêmes définitions que recalcul.py, importé : date_conf (premier commit qui écrit
la valeur dans un fichier de configuration), dernier commit d'une clé publique. Lecture seule : Zot en anonyme, cosign, git.
  cle <sha256 du fichier> <nom du fichier dans CLES> <date epoch>
  pin <digest d'une dépendance> <date epoch ou -> <present|retire|non-epingle>
Les dépendances viennent de la provenance de PipelineRun la plus récente de chaque sujet, signature vérifiée par cosign.
Le relevé DOIT rester sous poc/bricks/20-kpi/ : HORS_CONF l'exclut ; ailleurs, date_conf y verrait épinglé ce qui ne l'est pas.
Il périme après chaque rejeu, reconstruction ou re-signature (clés recréées, digests neufs) : relancer « verifier ».
Usage (racine du dépôt) : mise exec -- python3 -I poc/bricks/20-kpi/releve-dates.py ecrire|verifier"""
import hashlib
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recalcul as r  # noqa: E402

FICHIER = os.path.join(r.ICI, "releve", "dates-git.tsv")
lignes = set()
for nom, chemin in r.CLES.items():
    contenu = r.subprocess.run(["git", "-C", r.DEPOT, "show", f"HEAD:poc/bricks/{chemin}"], capture_output=True, check=True).stdout
    date = r.git("log", "-1", "--format=%ct", "--", f"poc/bricks/{chemin}").strip()
    lignes.add(f"cle\t{hashlib.sha256(contenu).hexdigest()}\t{nom}.{'pem' if nom == 'tsa' else 'pub'}\t{date}\n")
for nom in r.PRODUITS:
    for d in sorted({f"sha256:{t[7:71]}" for t in r.zot(f"builds/{nom}/tags/list")["tags"] if re.fullmatch(r"sha256-[0-9a-f]{64}\.[a-z]+", t)}):
        pr = [e["predicate"] for e, _ in r.cosign(nom, d, r.CLES["chains"], r.T_PROV)
              if e["predicate"]["runDetails"]["builder"]["id"] == r.BUILDER and e["predicate"]["buildDefinition"]["buildType"] == r.BUILDTYPE
              and "pipelineRef" in e["predicate"]["buildDefinition"]["externalParameters"].get("runSpec", {})]
        if not pr:
            continue
        p = max(pr, key=lambda p: (p["runDetails"]["metadata"]["finishedOn"], p["runDetails"]["metadata"]["invocationId"]))
        for x in p["buildDefinition"]["resolvedDependencies"]:
            v = next(iter(x["digest"].values()))
            date, present = r.date_conf(v)
            lignes.add(f"pin\t{v}\t{date or '-'}\t{('present' if present else 'retire') if date else 'non-epingle'}\n")
texte = "# relevé de releve-dates.py : ne pas modifier à la main\n" + "".join(sorted(lignes))
if sys.argv[1:] == ["ecrire"]:
    os.makedirs(os.path.dirname(FICHIER), exist_ok=True)
    with open(FICHIER, "w", encoding="utf-8") as f:
        f.write(texte)
    print(f"écrit : {sum(1 for x in lignes if x.startswith('cle'))} clés, {sum(1 for x in lignes if x.startswith('pin'))} pins")
elif sys.argv[1:] == ["verifier"]:
    with open(FICHIER, encoding="utf-8") as f:
        lu = f.read()
    print(f"relevé {'identique à git' if lu == texte else 'PÉRIMÉ'} : {len(set(texte.splitlines()) ^ set(lu.splitlines()))} ligne(s) différente(s)")
    sys.exit(lu != texte)
else:
    sys.exit(__doc__)
