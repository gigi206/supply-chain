#!/usr/bin/env python3
"""Brique 07a : fusionne le SBOM de fermeture (Hermeto) et le SBOM de l'artefact (Syft).

Hermeto décrit les dépendances prefetchées (dont celles embarquées sans trace
dans le binaire, comme une bibliothèque npm intégrée par go:embed) ; Syft décrit
l'artefact réel (dont la version de la bibliothèque standard Go). Les deux
outils n'écrivent pas le même PURL pour un même module Go :
  Hermeto : pkg:golang/github.com/go-chi/chi/v5@v5.2.3?type=module
  Syft    : pkg:golang/github.com/go-chi/chi@v5.2.3#v5
La fusion se fait donc sur une clé normalisée. Les composants sans version
(paquets de la bibliothèque standard listés par Hermeto) sont écartés : ils ne
sont pas corrélables.

Usage : sbom_merge.py <hermeto.json> <syft.json> > fusion.json   (CycloneDX 1.6)
"""
import json
import re
import sys
from urllib.parse import unquote


def key(purl):
    """(type, nom complet, version) d'un PURL, ou None s'il n'a pas de version."""
    m = re.match(r"pkg:([^/]+)/([^@?#]+)@([^?#]+)(?:\?[^#]*)?(?:#(.*))?$", purl or "")
    if not m:
        return None
    ptype, name, version, subpath = m.groups()
    name = unquote(name)
    if ptype == "golang" and subpath and re.fullmatch(r"v\d+", subpath):
        name = f"{name}/{subpath}"  # module majeur ≥ 2 : …/v5
    return ptype, name, unquote(version)


def merge(docs):
    out, seen = [], {}
    for source, doc in docs:
        for c in doc.get("components", []):
            k = key(c.get("purl"))
            if k is None:
                continue
            if k in seen:
                seen[k]["properties"].append({"name": "supply-chain:source", "value": source})
                continue
            comp = {"type": c.get("type", "library"), "name": c.get("name", k[1]),
                    "version": k[2], "purl": c["purl"],
                    "properties": [{"name": "supply-chain:source", "value": source}]}
            if c.get("licenses"):
                comp["licenses"] = c["licenses"]
            seen[k] = comp
            out.append(comp)
    return {"bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
            "metadata": {"tools": {"components": [{"type": "application", "name": "sbom_merge"}]}},
            "components": sorted(out, key=lambda c: c["purl"])}


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    docs = [("hermeto", json.load(open(argv[1]))), ("syft", json.load(open(argv[2])))]
    json.dump(merge(docs), sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
