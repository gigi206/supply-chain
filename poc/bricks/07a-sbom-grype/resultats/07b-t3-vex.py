"""Brique 07b, tranche 3 : témoins VEX du banc (aucune analyse ne les fonde ; auteur « témoin »).

  doc <fichier> <horodatage-du-document|-> <énoncé>…
      énoncé : « statut;justification;impact;horodatage;vulnérabilité;produit;sous-composant », « - » pour un champ absent
      (vulnérabilité ou produit absent : clé absente de l'énoncé, cas du passage 5)
  enonce <fichier> <predicateType> <sha256-du-sujet> <prédicat.json> [contexte]
      énoncé in-toto v0.1 non signé (cas unitaires de scan-outil vex) ; contexte remplace @context du prédicat

JSON compact, sans fin de ligne.
"""
import json
import sys

AUTEUR = "témoin du PoC (aucune analyse, tranche 3 de la 07b)"
OPENVEX = "https://openvex.dev/ns/v0.2.0"


def ecrire(f, d):
    with open(f, "w", encoding="utf-8") as s:
        s.write(json.dumps(d, separators=(",", ":"), ensure_ascii=False))


def doc(f, horodatage, *enonces):
    d = {"@context": OPENVEX, "@id": "https://supply-chain.example/vex/temoin-" + f.rsplit("/", 1)[-1],
         "author": AUTEUR, "version": 1, "statements": []}
    if horodatage != "-":
        d["timestamp"] = horodatage
    for e in enonces:
        statut, justif, impact, h, vuln, produit, sous = e.split(";")
        s = {"status": statut}
        if vuln != "-":
            s["vulnerability"] = {"name": vuln}
        if produit != "-":
            p = {"@id": produit}
            if sous != "-":
                p["subcomponents"] = [{"@id": sous}]
            s["products"] = [p]
        if justif != "-":
            s["justification"] = justif
        if impact != "-":
            s["impact_statement"] = impact
        if h != "-":
            s["timestamp"] = h
        d["statements"].append(s)
    ecrire(f, d)


def enonce(f, ptype, sujet, predicat, contexte=None):
    p = json.load(open(predicat, encoding="utf-8"))
    if contexte is not None:
        p["@context"] = contexte
    ecrire(f, {"_type": "https://in-toto.io/Statement/v0.1", "subject": [{"name": "sample-app", "digest": {"sha256": sujet}}],
               "predicateType": ptype, "predicate": p})


if __name__ == "__main__":
    {"doc": doc, "enonce": enonce}[sys.argv[1]](*sys.argv[2:])
