#!/usr/bin/env python3
"""Tests de tools/index avec un registre en mémoire : python3 -m unittest -v test_index"""
import base64
import hashlib
import json
import sqlite3
import unittest

import index


def sha(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def envelope(subject, ptype, deps=()):
    st = {"_type": "https://in-toto.io/Statement/v1", "predicateType": ptype,
          "subject": [{"name": "app", "digest": {"sha256": subject[7:]}}],
          "predicate": {"buildDefinition": {"resolvedDependencies": [
              {"uri": u, "digest": {"sha256": d[7:]}} for u, d in deps]}}}
    return {"payloadType": "application/vnd.in-toto+json",
            "payload": base64.b64encode(json.dumps(st).encode()).decode(),
            "signatures": [{"sig": "eA==", "keyid": "chains"}]}


class FakeRegistry:
    """Registre minimal : dépôts → tags → manifests, referrers et blobs."""

    def __init__(self):
        self.blobs, self.manifests, self.tagmap, self.refs = {}, {}, {}, {}
        self.calls = 0

    def put_blob(self, data):
        d = sha(data)
        self.blobs[d] = data
        return d

    def put_manifest(self, repo, m, tag=None):
        d = sha(json.dumps(m, sort_keys=True).encode())
        self.manifests[d] = m
        if tag:
            self.tagmap.setdefault(repo, {})[tag] = d
        if "subject" in m:
            self.refs.setdefault(m["subject"]["digest"], []).append(
                {"digest": d, "artifactType": m.get("artifactType")})
        return d

    def repos(self):
        return sorted(self.tagmap)

    def tags(self, repo):
        return sorted(self.tagmap[repo])

    def manifest(self, repo, ref):
        self.calls += 1
        d = self.tagmap.get(repo, {}).get(ref, ref)
        return self.manifests[d], d

    def referrers(self, repo, digest):
        return self.refs.get(digest, [])

    def blob(self, repo, digest):
        self.calls += 1
        return self.blobs[digest]


class IndexTest(unittest.TestCase):
    def setUp(self):
        self.reg = r = FakeRegistry()
        self.dep = sha(b"fermeture hermeto")
        # Artefact ORAS (un fichier) avec provenance en referrer (bundle Sigstore v0.3).
        self.file = r.put_blob(b"binaire")
        self.art = r.put_manifest("apps/a", {"artifactType": "application/x-bin",
                                             "layers": [{"digest": self.file, "annotations": {
                                                 "org.opencontainers.image.title": "a"}}]}, tag="1.0")
        bundle = {"dsseEnvelope": envelope(self.art, "https://slsa.dev/provenance/v1",
                                           [("oci://zot/deps/a", self.dep)])}
        r.put_manifest("apps/a", {"artifactType": index.BUNDLE_TYPES[0], "subject": {"digest": self.art},
                                  "layers": [{"digest": r.put_blob(json.dumps(bundle).encode())}]})
        sig = {"dsseEnvelope": envelope(self.art, "https://sigstore.dev/cosign/sign/v1")}
        r.put_manifest("apps/a", {"artifactType": index.BUNDLE_TYPES[0], "subject": {"digest": self.art},
                                  "layers": [{"digest": r.put_blob(json.dumps(sig).encode())}]})
        # Image avec provenance en tag cosign .att (mode dsse de Chains) et signature .sig.
        self.img = r.put_manifest("apps/b", {"config": {"mediaType": "application/vnd.oci.image.config.v1+json"},
                                             "layers": []}, tag="2.0")
        att = r.put_blob(json.dumps(envelope(self.img, "https://slsa.dev/provenance/v1",
                                             [("oci://zot/deps/b", self.dep)])).encode())
        r.put_manifest("apps/b", {"layers": [{"mediaType": index.DSSE_LAYER, "digest": att}]},
                       tag=f"sha256-{self.img[7:]}.att")
        r.put_manifest("apps/b", {"layers": []}, tag=f"sha256-{self.img[7:]}.sig")
        self.db = sqlite3.connect(":memory:")
        self.db.executescript(index.SCHEMA)

    def crawl(self):
        index.Indexer(self.reg, self.db).crawl(workers=1)

    def test_construit_avec(self):
        self.crawl()
        rows = index.built_with(self.db, self.dep)
        self.assertEqual({(r[0], r[2]) for r in rows}, {("apps/a", self.art), ("apps/b", self.img)})
        self.assertEqual(index.built_with(self.db, sha(b"inconnu")), [])

    def test_attestations_par_sujet_et_par_fichier(self):
        self.crawl()
        by_subject = index.attestations(self.db, self.img[7:])  # digest « brut », sans préfixe
        self.assertEqual([(r[2], r[3]) for r in by_subject], [("https://slsa.dev/provenance/v1", "tag-att")])
        by_file = index.attestations(self.db, self.file)
        self.assertEqual(len(by_file), 1)
        self.assertEqual(by_file[0][5], f"couche de {self.art}")

    def test_signatures_comptees_pas_comme_attestations(self):
        self.crawl()
        sources = sorted(r[0] for r in self.db.execute("SELECT source FROM signatures"))
        self.assertEqual(sources, ["referrer-bundle", "tag-sig"])
        types = {r[0] for r in self.db.execute("SELECT predicate_type FROM statements")}
        self.assertNotIn("https://sigstore.dev/cosign/sign/v1", types)

    def test_recrawl_idempotent_et_incremental(self):
        self.crawl()
        counts = [self.db.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
                  for t in ("statements", "subjects", "deps", "signatures")]
        self.reg.calls = 0
        self.crawl()
        again = [self.db.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
                 for t in ("statements", "subjects", "deps", "signatures")]
        self.assertEqual(counts, again)
        self.assertEqual(self.reg.calls, 4, "seuls les 4 manifests taggés sont relus, ni bundles ni blobs")

    def test_provenance_v02_materials(self):
        st = {"predicate": {"materials": [{"uri": "git+x", "digest": {"sha1": "ab"}}]}}
        self.assertEqual(list(index.dependencies(st)), [("git+x", "sha1:ab")])


if __name__ == "__main__":
    unittest.main()
