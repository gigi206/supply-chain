#!/usr/bin/env python3
"""Index de provenance reconstructible (brique 02).

Parcourt un registre OCI (Zot) et range dans SQLite les artefacts, leurs couches
et les énoncés in-toto attachés :
  - referrers OCI 1.1 (bundles Sigstore v0.3, mode `sigstore-bundle` de Chains) ;
  - tags cosign `sha256-<hex>.att` (enveloppes DSSE, mode `dsse` de Chains) et
    `sha256-<hex>.sig` (signatures simples, comptées seulement).
L'index n'est **pas** une source de confiance : il ne vérifie aucune signature.
Il sert à retrouver vite ce que la porte et le replay vérifieront. On peut le
supprimer et le reconstruire à tout moment depuis le registre.

  index.py crawl --registry http://localhost:5000 --db index.sqlite
  index.py built-with <sha256>     artefacts dont la provenance cite ce digest
  index.py attestations <sha256>   énoncés dont le sujet est ce digest, ou l'artefact
                                   qui contient ce digest comme couche (fichier ORAS)
"""
import argparse
import base64
import json
import os
import re
import sqlite3
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ACCEPT = ", ".join([
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
])
BUNDLE_TYPES = ("application/vnd.dev.sigstore.bundle.v0.3+json", "application/vnd.dev.sigstore.bundle+json;version=0.3")
DSSE_LAYER = "application/vnd.dsse.envelope.v1+json"
COSIGN_TAG = re.compile(r"^sha256-([0-9a-f]{64})\.(att|sig|sbom)$")
PROVENANCE = ("https://slsa.dev/provenance/v1", "https://slsa.dev/provenance/v0.2")

SCHEMA = """
CREATE TABLE IF NOT EXISTS artifacts (repo TEXT, digest TEXT, artifact_type TEXT, PRIMARY KEY (repo, digest));
CREATE TABLE IF NOT EXISTS tags (repo TEXT, tag TEXT, digest TEXT, PRIMARY KEY (repo, tag));
CREATE TABLE IF NOT EXISTS layers (repo TEXT, manifest TEXT, digest TEXT, title TEXT);
CREATE TABLE IF NOT EXISTS statements (id TEXT PRIMARY KEY, repo TEXT, attached_to TEXT,
  source TEXT, predicate_type TEXT, signatures INTEGER, keyids TEXT);
CREATE TABLE IF NOT EXISTS subjects (statement TEXT, name TEXT, digest TEXT, PRIMARY KEY (statement, name, digest));
CREATE TABLE IF NOT EXISTS deps (statement TEXT, uri TEXT, digest TEXT, PRIMARY KEY (statement, uri, digest));
CREATE TABLE IF NOT EXISTS signatures (id TEXT PRIMARY KEY, repo TEXT, digest TEXT, source TEXT);
CREATE INDEX IF NOT EXISTS i_layers ON layers (digest);
CREATE INDEX IF NOT EXISTS i_subjects ON subjects (digest);
CREATE INDEX IF NOT EXISTS i_deps ON deps (digest);
"""


class Registry:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.headers = {}
        if os.environ.get("INDEX_REGISTRY_AUTH"):  # « utilisateur:mot de passe », lecture seule
            token = base64.b64encode(os.environ["INDEX_REGISTRY_AUTH"].encode()).decode()
            self.headers["Authorization"] = f"Basic {token}"

    def get(self, path, accept=None):
        req = urllib.request.Request(self.base + path, headers=dict(self.headers))
        if accept:
            req.add_header("Accept", accept)
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.read(), r.headers

    def json(self, path, accept=None):
        return json.loads(self.get(path, accept)[0])

    def repos(self):
        last, out = None, []
        while True:
            q = "/v2/_catalog?n=1000" + (f"&last={last}" if last else "")
            page = self.json(q).get("repositories") or []
            out += page
            if len(page) < 1000:
                return out
            last = page[-1]

    def tags(self, repo):
        return self.json(f"/v2/{repo}/tags/list").get("tags") or []

    def manifest(self, repo, ref):
        body, headers = self.get(f"/v2/{repo}/manifests/{ref}", ACCEPT)
        return json.loads(body), headers.get("Docker-Content-Digest")

    def referrers(self, repo, digest):
        try:
            return self.json(f"/v2/{repo}/referrers/{digest}").get("manifests") or []
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return []
            raise

    def blob(self, repo, digest):
        return self.get(f"/v2/{repo}/blobs/{digest}")[0]


def statement_from_envelope(env):
    """(énoncé in-toto, nb de signatures, keyids) d'une enveloppe DSSE, ou None."""
    if env.get("payloadType") != "application/vnd.in-toto+json":
        return None
    st = json.loads(base64.b64decode(env["payload"]))
    sigs = env.get("signatures") or []
    return st, len(sigs), ",".join(sorted({s.get("keyid", "") for s in sigs if s.get("keyid")}))


def dependencies(st):
    """(uri, digest) cités par une provenance SLSA v1 ou v0.2."""
    pred = st.get("predicate") or {}
    items = (pred.get("buildDefinition") or {}).get("resolvedDependencies") or pred.get("materials") or []
    for d in items:
        for alg, value in (d.get("digest") or {}).items():
            yield d.get("uri") or d.get("name") or "", f"{alg}:{value}"


def norm(digest):
    return digest if ":" in digest else f"sha256:{digest}"


class Indexer:
    def __init__(self, reg, db):
        self.reg, self.db = reg, db
        # Manifests d'attestation déjà lus (« <digest>#<couche> ») : un recrawl ne les relit pas.
        ids = [row[0] for row in db.execute("SELECT id FROM statements UNION SELECT id FROM signatures")]
        self.known = {i.split("#")[0] for i in ids}

    def crawl(self, workers=8):
        repos = self.reg.repos()
        with ThreadPoolExecutor(workers) as pool:
            results = list(pool.map(self.scan_repo, repos))
        with self.db:
            for rows in results:
                for table, values in rows:
                    marks = ",".join("?" * len(values))
                    self.db.execute(f"INSERT OR REPLACE INTO {table} VALUES ({marks})", values)
        return len(repos)

    def scan_repo(self, repo):
        """Lit un dépôt ; renvoie des lignes (table, valeurs) à insérer."""
        rows = []
        for tag in self.reg.tags(repo):
            m = COSIGN_TAG.match(tag)
            manifest, digest = self.reg.manifest(repo, tag)
            if m:
                subject = f"sha256:{m.group(1)}"
                if m.group(2) == "att" and digest not in self.known:
                    rows += self.dsse_layers(repo, subject, digest, manifest)
                elif m.group(2) == "sig":
                    rows.append(("signatures", (digest, repo, subject, "tag-sig")))
                continue
            rows.append(("tags", (repo, tag, digest)))
            rows += self.artifact(repo, digest, manifest)
        return rows

    def artifact(self, repo, digest, manifest):
        rows = [("artifacts", (repo, digest, manifest.get("artifactType")
                               or (manifest.get("config") or {}).get("mediaType")))]
        for layer in manifest.get("layers") or []:
            title = (layer.get("annotations") or {}).get("org.opencontainers.image.title")
            rows.append(("layers", (repo, digest, layer["digest"], title)))
        for child in manifest.get("manifests") or []:  # index multi-architecture
            sub, sub_digest = self.reg.manifest(repo, child["digest"])
            rows += self.artifact(repo, sub_digest, sub)
        for ref in self.reg.referrers(repo, digest):
            if ref["digest"] in self.known:
                continue
            if ref.get("artifactType") in BUNDLE_TYPES:
                rows += self.bundle(repo, digest, ref["digest"])
            elif ref.get("artifactType"):
                rows.append(("artifacts", (repo, ref["digest"], ref["artifactType"])))
        return rows

    def bundle(self, repo, subject, digest):
        manifest, _ = self.reg.manifest(repo, digest)
        rows = []
        for i, layer in enumerate(manifest.get("layers") or []):
            b = json.loads(self.reg.blob(repo, layer["digest"]))
            env = b.get("dsseEnvelope")
            if env is None:  # signature « message » sans DSSE
                rows.append(("signatures", (f"{digest}#{i}", repo, subject, "referrer-bundle")))
                continue
            rows += self.record(repo, subject, f"{digest}#{i}", "referrer-bundle", env)
        return rows

    def dsse_layers(self, repo, subject, digest, manifest):
        rows = []
        for i, layer in enumerate(manifest.get("layers") or []):
            sid = f"{digest}#{i}"
            if layer.get("mediaType") != DSSE_LAYER:
                continue
            env = json.loads(self.reg.blob(repo, layer["digest"]))
            rows += self.record(repo, subject, sid, "tag-att", env)
        return rows

    def record(self, repo, attached_to, sid, source, env):
        parsed = statement_from_envelope(env)
        if parsed is None:
            return []
        st, nsig, keyids = parsed
        ptype = st.get("predicateType", "")
        if ptype == "https://sigstore.dev/cosign/sign/v1":
            return [("signatures", (sid, repo, attached_to, source))]
        rows = [("statements", (sid, repo, attached_to, source, ptype, nsig, keyids))]
        for s in st.get("subject") or []:
            for alg, value in (s.get("digest") or {}).items():
                rows.append(("subjects", (sid, s.get("name", ""), f"{alg}:{value}")))
        if ptype in PROVENANCE:
            rows += [("deps", (sid, uri, d)) for uri, d in dependencies(st)]
        return rows


def built_with(db, digest):
    return db.execute("""
        SELECT DISTINCT st.repo, sub.name, sub.digest, d.uri
        FROM deps d JOIN statements st ON st.id = d.statement JOIN subjects sub ON sub.statement = st.id
        WHERE d.digest = ? ORDER BY st.repo, sub.name""", (norm(digest),)).fetchall()


def attestations(db, digest):
    digest = norm(digest)
    # Le digest est un sujet, ou une couche (fichier ORAS) d'un artefact qui est un sujet.
    return db.execute("""
        SELECT DISTINCT st.repo, sub.digest, st.predicate_type, st.source, st.id,
               CASE WHEN sub.digest = ? THEN 'sujet' ELSE 'couche de ' || sub.digest END
        FROM subjects sub JOIN statements st ON st.id = sub.statement
        WHERE sub.digest = ? OR sub.digest IN (SELECT manifest FROM layers WHERE digest = ?)
        ORDER BY st.repo, st.predicate_type""", (digest, digest, digest)).fetchall()


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--db", default="index.sqlite")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("crawl")
    c.add_argument("--registry", required=True)
    c.add_argument("--rebuild", action="store_true", help="repart d'un index vide")
    sub.add_parser("built-with").add_argument("digest")
    sub.add_parser("attestations").add_argument("digest")
    a = p.parse_args(argv)

    if a.cmd == "crawl" and a.rebuild and os.path.exists(a.db):
        os.remove(a.db)
    db = sqlite3.connect(a.db)
    db.executescript(SCHEMA)
    t0 = time.monotonic()
    if a.cmd == "crawl":
        n = Indexer(Registry(a.registry), db).crawl()
        counts = {t: db.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
                  for t in ("artifacts", "statements", "subjects", "deps", "signatures")}
        print(f"{n} dépôts parcourus en {time.monotonic() - t0:.1f} s ; {counts}")
        return 0
    rows = built_with(db, a.digest) if a.cmd == "built-with" else attestations(db, a.digest)
    for r in rows:
        print("\t".join(str(x) for x in r))
    print(f"{len(rows)} résultat(s) en {1000 * (time.monotonic() - t0):.0f} ms", file=sys.stderr)
    return 0 if rows else 1


if __name__ == "__main__":
    sys.exit(main())
