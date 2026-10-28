#!/usr/bin/env python3
"""Brique 07a : convertit un rapport Grype (JSON) en prédicat de scan signable.

Type de prédicat : https://supply-chain.example/scan/v1 (celui que lisent les
politiques Conforma et Kyverno du banc C). Le prédicat garde la trace de la base
utilisée : date de construction, schéma, et digest OCI de l'archive restaurée,
pour qu'un scan puisse être rejoué à l'identique plus tard.

Usage : scan_predicate.py <grype.json> <ref-de-la-base@sha256:…> > scan.json
"""
import json
import sys


def predicate(report, db_ref):
    status = report["descriptor"]["db"]["status"]
    vulns = {}
    for m in report["matches"]:
        v = m["vulnerability"]
        key = (v["id"], m["artifact"]["purl"])
        kev = sorted({k["cve"] for k in v.get("knownExploited") or []})
        epss = max((e["epss"] for e in v.get("epss") or []), default=None)
        vulns[key] = {
            "id": v["id"],
            "aliases": sorted({r["id"] for r in m.get("relatedVulnerabilities") or []} - {v["id"]}),
            "severity": v.get("severity", "Unknown"),
            "kev": bool(kev),
            "kevCves": kev,
            "epss": epss,
            "package": m["artifact"]["purl"],
            "fixedIn": (v.get("fix") or {}).get("versions") or [],
        }
    return {
        "scanner": {"id": "grype", "version": report["descriptor"]["version"],
                    "db": {"built": status["built"], "schema": status["schemaVersion"], "ref": db_ref}},
        "scannedAt": report["descriptor"]["timestamp"],
        "vulnerabilities": sorted(vulns.values(), key=lambda x: (x["package"], x["id"])),
        # Paquets malveillants (OSV MAL-) : contrôle de la brique 07b (2c).
        "malicious": [],
    }


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    json.dump(predicate(json.load(open(argv[1])), argv[2]), sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
