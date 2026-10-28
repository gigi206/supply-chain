#!/usr/bin/env python3
"""Peuple un registre de test pour mesurer tools/index à l'échelle (brique 02).

Pour chaque artefact : un fichier ORAS (une couche) dans l'un des dépôts
`synth/projet-NN`, puis une provenance SLSA v1 attachée en referrer (bundle
Sigstore v0.3). Chaque provenance cite 20 dépendances tirées d'un réservoir.
La dépendance « canari » n'apparaît que dans les artefacts dont le numéro est
multiple de 500 ; ses digests et ceux des fichiers sont écrits dans attendu.json.
Les enveloppes ne sont pas signées pour de vrai : l'index ne vérifie rien.

Usage : gen_synthetic.py --registry http://localhost:5000 --count 2000 --out attendu.json
"""
import argparse
import base64
import hashlib
import json
import random
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BUNDLE = "application/vnd.dev.sigstore.bundle.v0.3+json"
EMPTY = {"mediaType": "application/vnd.oci.empty.v1+json",
         "digest": "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", "size": 2}


def sha(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


class Push:
    def __init__(self, base):
        self.base = base.rstrip("/")

    def call(self, method, path, data=None, ctype=None):
        req = urllib.request.Request(self.base + path, data=data, method=method)
        if ctype:
            req.add_header("Content-Type", ctype)
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.headers

    def blob(self, repo, data):
        d = sha(data)
        loc = self.call("POST", f"/v2/{repo}/blobs/uploads/")["Location"]
        sep = "&" if "?" in loc else "?"
        path = loc if loc.startswith("/") else loc[len(self.base):]
        self.call("PUT", f"{path}{sep}digest={d}", data, "application/octet-stream")
        return {"digest": d, "size": len(data)}

    def manifest(self, repo, ref, manifest):
        data = json.dumps(manifest, sort_keys=True).encode()
        self.call("PUT", f"/v2/{repo}/manifests/{ref}", data, manifest["mediaType"])
        return {"mediaType": manifest["mediaType"], "digest": sha(data), "size": len(data)}


def one(p, i, pool, canary):
    repo = f"synth/projet-{i % 50:02d}"
    p.blob(repo, b"{}")
    content = f"binaire {i}\n".encode() * 64
    layer = p.blob(repo, content)
    layer.update(mediaType="application/vnd.supply-chain.binary.v1",
                 annotations={"org.opencontainers.image.title": f"app-{i}"})
    art = p.manifest(repo, f"v{i}", {
        "schemaVersion": 2, "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "artifactType": "application/vnd.supply-chain.binary.v1", "config": EMPTY, "layers": [layer]})
    rng = random.Random(i)
    deps = rng.sample(pool, 20) + ([canary] if i % 500 == 0 else [])
    statement = {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [{"name": f"{repo}:v{i}", "digest": {"sha256": art["digest"][7:]}}],
        "predicateType": "https://slsa.dev/provenance/v1",
        "predicate": {"buildDefinition": {"buildType": "https://tekton.dev/chains/v2/slsa",
                                          "resolvedDependencies": [{"uri": f"oci://zot.example/deps/{d[7:19]}",
                                                                    "digest": {"sha256": d[7:]}} for d in deps]},
                      "runDetails": {"builder": {"id": "https://supply-chain.example/builders/tekton-chains@v1"}}}}
    bundle = {"mediaType": "application/vnd.dev.sigstore.bundle.v0.3+json", "verificationMaterial": {},
              "dsseEnvelope": {"payloadType": "application/vnd.in-toto+json",
                               "payload": base64.b64encode(json.dumps(statement).encode()).decode(),
                               "signatures": [{"sig": "bm9uLXNpZ27DqQ==", "keyid": "synthetique"}]}}
    blayer = p.blob(repo, json.dumps(bundle).encode())
    blayer["mediaType"] = BUNDLE
    att = {"schemaVersion": 2, "mediaType": "application/vnd.oci.image.manifest.v1+json",
           "artifactType": BUNDLE, "config": EMPTY, "layers": [blayer], "subject": art,
           "annotations": {"dev.sigstore.bundle.predicateType": "https://slsa.dev/provenance/v1"}}
    p.manifest(repo, sha(json.dumps(att, sort_keys=True).encode()), att)
    return i, art["digest"], layer["digest"]


def main():
    a = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    a.add_argument("--registry", required=True)
    a.add_argument("--count", type=int, default=2000)
    a.add_argument("--out", required=True)
    args = a.parse_args()
    pool = [sha(f"dep {k}".encode()) for k in range(1000)]
    canary = sha(b"dependance canari compromise")
    p = Push(args.registry)
    with ThreadPoolExecutor(16) as ex:
        res = list(ex.map(lambda i: one(p, i, pool, canary), range(args.count)))
    expected = {"canary": canary,
                "built_with_canary": sorted(d for i, d, _ in res if i % 500 == 0),
                "sample_file": res[7][2], "sample_file_manifest": res[7][1]}
    json.dump(expected, open(args.out, "w"), indent=2)
    print(f"{len(res)} artefacts et provenances poussés")


if __name__ == "__main__":
    main()
