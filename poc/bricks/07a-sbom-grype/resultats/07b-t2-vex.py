"""Brique 07b, tranche 2 : documents témoins pour 07b-t2-banc.sh (aucune analyse d'atteignabilité ne les fonde).

  openvex <fichier> <vulnérabilité> <produit> <sous-composant|-> <statut> [alias]
  csaf <fichier> <cve> <ghsa> <purl>
  composant <sbom-entrée> <sbom-sortie> <nom> <digest> [type]   (metadata.component, de type container par défaut)
  purl <sbom-entrée> <sbom-sortie> <ancien> <nouveau>             (PURL d'un seul composant remplacé)

JSON compact, sans fin de ligne : un prédicat relu après signature peut être comparé à l'octet près.
"""
import json
import sys

AUTEUR = "témoin du PoC (aucune analyse, tranche 2 de la 07b)"
DATE = "2026-11-21T00:00:00Z"


def ecrire(f, d):
    with open(f, "w", encoding="utf-8") as s:
        s.write(json.dumps(d, ensure_ascii=False, separators=(",", ":")))


def openvex(f, vuln, prod, sous, statut, alias=""):
    p = {"@id": prod}
    if sous != "-":
        p["subcomponents"] = [{"@id": sous}]
    v = {"name": vuln}
    if alias:
        v["aliases"] = [alias]
    e = {"vulnerability": v, "products": [p], "status": statut}
    if statut == "not_affected":
        e["justification"] = "vulnerable_code_not_in_execute_path"
    elif statut == "affected":
        e["action_statement"] = "témoin : aucune action"
    ecrire(f, {"@context": "https://openvex.dev/ns/v0.2.0", "@id": "https://supply-chain.example/vex/temoin-t2",
               "author": AUTEUR, "timestamp": DATE, "version": 1, "statements": [e]})


def csaf(f, cve, ghsa, purl):
    ecrire(f, {
        "document": {"category": "csaf_vex", "csaf_version": "2.0", "title": "témoin t2",
                     "publisher": {"category": "other", "name": AUTEUR, "namespace": "https://supply-chain.example"},
                     "tracking": {"id": "temoin-t2", "status": "final", "version": "1", "initial_release_date": DATE,
                                  "current_release_date": DATE,
                                  "revision_history": [{"date": DATE, "number": "1", "summary": "témoin"}]}},
        "product_tree": {"branches": [{"category": "product_name", "name": "chi", "product": {
            "name": "chi v5.2.3", "product_id": "CHI", "product_identification_helper": {"purl": purl}}}]},
        "vulnerabilities": [{"cve": cve, "ids": [{"system_name": "GHSA", "text": ghsa}],
                             "product_status": {"known_not_affected": ["CHI"]},
                             "flags": [{"label": "vulnerable_code_not_in_execute_path", "product_ids": ["CHI"]}]}]})


def composant(entree, sortie, nom, digest, genre="container"):
    d = json.load(open(entree, encoding="utf-8"))
    d.setdefault("metadata", {})["component"] = {"type": genre, "name": nom, "version": digest,
                                                 "bom-ref": f"pkg:oci/{nom}@{digest}", "purl": f"pkg:oci/{nom}@{digest}"}
    ecrire(sortie, d)


def purl(entree, sortie, ancien, nouveau):
    d = json.load(open(entree, encoding="utf-8"))
    n = 0
    for c in d.get("components", []):
        if c.get("purl") == ancien:
            c["purl"] = nouveau
            n += 1
    if n != 1:
        sys.exit(f"{n} composant(s) au PURL {ancien}, attendu 1")
    ecrire(sortie, d)


if __name__ == "__main__":
    {"openvex": openvex, "csaf": csaf, "composant": composant, "purl": purl}[sys.argv[1]](*sys.argv[2:])
