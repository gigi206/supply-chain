#!/usr/bin/env python3
"""Génère les prédicats in-toto d'un cas de test du banc « Kyverno seul ».

Usage : gen_predicates.py <cas> <répertoire de sortie>
Écrit prov.json, vsa.json, scan.json, lic.json (selon le cas) et plan.tsv,
qui liste « type de prédicat, clé de signature, fichier » à attester.
"""
import copy
import json
import pathlib
import sys

TRUSTED_TASK = "1" * 64
BASE_PROV = {
    "buildDefinition": {
        "buildType": "https://tekton.dev/chains/v2/slsa",
        "externalParameters": {
            "git": {
                "url": "forgejo.example/workspace/app",
                "ref": "refs/heads/custom/el9",
                "commit": "0123456789abcdef0123456789abcdef01234567",
            }
        },
        "internalParameters": {"hermetic": True, "isolation": "kata", "cpuModel": "x86-64-v3"},
        "resolvedDependencies": [
            {"uri": "git+forgejo.example/workspace/app@refs/heads/custom/el9",
             "digest": {"sha1": "0123456789abcdef0123456789abcdef01234567"}},
            {"uri": "oci://zot.example/builders/go-builder", "digest": {"sha256": "a" * 64}},
            {"uri": "oci://zot.example/deps/app/hermeto", "digest": {"sha256": "b" * 64}},
            {"uri": "oci://zot.example/tekton/tasks/build-go", "digest": {"sha256": TRUSTED_TASK}},
        ],
    },
    "runDetails": {
        "builder": {"id": "https://supply-chain.example/builders/tekton-chains@v1"},
        "metadata": {"invocationId": "bench-run"},
    },
}
BASE_VSA = {
    "verifier": {"id": "https://supply-chain.example/replay"},
    "timeVerified": "2026-10-28T00:00:00Z",
    "resourceUri": "oci://zot.example/artifacts/app/image",
    "policy": {"uri": "https://supply-chain.example/policies/replay@v1"},
    "verificationResult": "PASSED",
    "verifiedLevels": ["SLSA_BUILD_LEVEL_3"],
}
BASE_SCAN = {
    "scanner": {"id": "grype", "db": "2026-10-28"},
    "vulnerabilities": [{"id": "CVE-2026-0001", "severity": "High", "kev": False}],
    "malicious": [],
}
BASE_LIC = {"violations": {"error": 0, "warning": 1}}

PROV_T = "https://slsa.dev/provenance/v1"
VSA_T = "https://slsa.dev/verification_summary/v1"
SCAN_T = "https://supply-chain.example/scan/v1"
LIC_T = "https://supply-chain.example/licences/v1"


def build(case):
    prov, vsa = copy.deepcopy(BASE_PROV), copy.deepcopy(BASE_VSA)
    scan, lic = copy.deepcopy(BASE_SCAN), copy.deepcopy(BASE_LIC)
    deps = prov["buildDefinition"]["resolvedDependencies"]
    keys = {"image": "chains", "prov": "chains", "vsa": "vsa", "scan": "chains", "lic": "chains"}
    if case == "c1-unsigned":
        keys["image"] = None
    elif case == "c1-rogue":
        keys = {k: "rogue" for k in keys}
    elif case == "c2-no-prov":
        prov = None
    elif case == "c2-bad-builder":
        prov["runDetails"]["builder"]["id"] = "https://evil.example/builder"
    elif case == "c3-bad-source":
        prov["buildDefinition"]["externalParameters"]["git"]["url"] = "github.com/evil/app"
    elif case == "c4-unpinned":
        deps[2].pop("digest")
    elif case == "c4-external-dep":
        deps.append({"uri": "oci://docker.io/library/golang", "digest": {"sha256": "c" * 64}})
    elif case == "c5-untrusted-task":
        deps[3]["digest"]["sha256"] = "9" * 64
    elif case == "c6-no-vsa":
        vsa = None
    elif case == "c6-vsa-failed":
        vsa["verificationResult"] = "FAILED"
    elif case == "c6-vsa-wrong-key":
        keys["vsa"] = "chains"
    elif case == "c7-kev":
        scan["vulnerabilities"].append({"id": "CVE-2026-9999", "severity": "Critical", "kev": True})
    elif case == "c7-kev-vex-ok":
        scan["vulnerabilities"].append({"id": "CVE-2026-9999", "severity": "Critical", "kev": True,
                                        "vex": {"status": "not_affected", "expires": "2027-06-01T00:00:00Z"}})
    elif case == "c7-mal":
        scan["malicious"].append("MAL-2026-1234")
    elif case == "c8-licence":
        lic["violations"]["error"] = 2
    elif case == "c10-vex-expired":
        scan["vulnerabilities"].append({"id": "CVE-2026-9999", "severity": "Critical", "kev": True,
                                        "vex": {"status": "not_affected", "expires": "2026-01-01T00:00:00Z"}})
    elif case != "ok":
        sys.exit(f"cas inconnu : {case}")
    return keys, {"prov": (PROV_T, prov), "vsa": (VSA_T, vsa), "scan": (SCAN_T, scan), "lic": (LIC_T, lic)}


def main():
    case, out = sys.argv[1], pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    keys, preds = build(case)
    plan = [f"image\t{keys['image'] or '-'}\t-"]
    for name, (ptype, body) in preds.items():
        if body is None:
            continue
        path = out / f"{name}.json"
        path.write_text(json.dumps(body, indent=2))
        plan.append(f"{ptype}\t{keys[name]}\t{path}")
    (out / "plan.tsv").write_text("\n".join(plan) + "\n")


if __name__ == "__main__":
    main()
