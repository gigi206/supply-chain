#!/usr/bin/env python3
"""Tests de la brique 01 sur des dépôts git locaux : python3 -m unittest -v test_sync"""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import sync

os.environ.update({
    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_AUTHOR_NAME": "amont", "GIT_AUTHOR_EMAIL": "amont@example.invalid",
    "GIT_COMMITTER_NAME": "amont", "GIT_COMMITTER_EMAIL": "amont@example.invalid",
})


def sh(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


class SyncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        self.up, self.mirror, self.reports, self.bundles = d / "amont", d / "miroir", d / "rapports", d / "bundles"
        self.forgejo = d / "forgejo.git"
        self.n = 0
        sh(d, "init", "--quiet", "-b", "main", str(self.up))
        self.a = self.commit("A")
        sh(self.up, "tag", "-a", "v1.0.0", "-m", "v1.0.0")

    def tearDown(self):
        self.tmp.cleanup()

    def commit(self, msg):
        sh(self.up, "commit", "--quiet", "--allow-empty", "-m", msg)
        return sh(self.up, "rev-parse", "HEAD")

    def run_sync(self, *extra, allow_file=True):
        self.n += 1
        self.stamp = f"20261028T0000{self.n:02d}Z"
        args = ["--mirror", str(self.mirror), "--upstream", f"file://{self.up}",
                "--report-dir", str(self.reports), "--bundle-dir", str(self.bundles),
                "--stamp", self.stamp, *extra]
        code = sync.main(args + (["--allow-file"] if allow_file else []))
        report = json.loads((self.reports / f"{self.stamp}.json").read_text())
        return code, report

    def events(self, report):
        return {(e["type"], e["ref"]) for e in report["events"]}

    def mirror_refs(self, repo=None, prefixes=("refs/upstream/", "refs/archive/")):
        out = sh(repo or self.mirror, "for-each-ref", "--format=%(refname) %(objectname)", *prefixes)
        return dict(line.split() for line in out.splitlines())

    def test_premier_run_puis_avance_rapide(self):
        code, rep = self.run_sync()
        self.assertEqual(code, 0)
        self.assertEqual(self.events(rep), {("branch-created", "heads/main"), ("tag-created", "tags/v1.0.0")})
        self.assertIsNotNone(rep["bundle"])
        b = self.commit("B")
        code, rep = self.run_sync()
        self.assertEqual(code, 0)
        self.assertEqual(self.events(rep), {("fast-forward", "heads/main")})
        self.assertIsNone(rep["events"][0]["archive"])
        self.assertEqual(rep["refs"]["refs/upstream/heads/main"], b)
        self.assertEqual(rep["bundle"]["refs"], ["refs/upstream/heads/main"])
        self.assertEqual(rep["bundle"]["prerequisites"], sorted({self.a, sh(self.up, "rev-parse", "v1.0.0")}))
        self.assertEqual(self.mirror_refs(prefixes=("refs/sync/incoming/",)), {}, "zone de transit vidée")

    def test_force_push_protege_detecte_et_archive(self):
        b = self.commit("B")
        self.run_sync()
        sh(self.up, "reset", "--quiet", "--hard", self.a)
        c = self.commit("C réécrit")
        code, rep = self.run_sync()
        self.assertEqual(code, 2)
        self.assertEqual(rep["status"], "rewrite-detected")
        (ev,) = rep["events"]
        self.assertEqual((ev["type"], ev["old"], ev["new"]), ("force-push", b, c))
        self.assertEqual(rep["refs"][ev["archive"]], b)
        self.assertEqual(rep["refs"]["refs/upstream/heads/main"], c)
        sh(self.mirror, "cat-file", "-e", f"{b}^{{commit}}")  # l'ancien historique reste dans le miroir

    def test_force_push_branche_non_protegee(self):
        sh(self.up, "checkout", "--quiet", "-b", "feature/x")
        f1 = self.commit("F1")
        self.run_sync()
        sh(self.up, "reset", "--quiet", "--hard", self.a)
        self.commit("F2")
        code, rep = self.run_sync()
        self.assertEqual(code, 0)
        (ev,) = rep["events"]
        self.assertEqual(ev["type"], "force-push-unprotected")
        self.assertEqual(rep["refs"][ev["archive"]], f1)

    def test_tag_deplace_tag_supprime_branche_supprimee(self):
        sh(self.up, "branch", "old")
        old_tag = sh(self.up, "rev-parse", "v1.0.0")
        self.run_sync()
        self.commit("B")
        sh(self.up, "tag", "-f", "-a", "v1.0.0", "-m", "v1.0.0 déplacé")
        code, rep = self.run_sync()
        self.assertEqual(code, 2)
        self.assertIn(("tag-moved", "tags/v1.0.0"), self.events(rep))
        moved = next(e for e in rep["events"] if e["type"] == "tag-moved")
        self.assertEqual(rep["refs"][moved["archive"]], old_tag)

        sh(self.up, "branch", "-D", "old")
        code, rep = self.run_sync()
        self.assertEqual(code, 0)
        self.assertEqual(self.events(rep), {("branch-deleted", "heads/old")})
        self.assertNotIn("refs/upstream/heads/old", rep["refs"])
        self.assertEqual(rep["refs"][rep["events"][0]["archive"]], self.a)

        sh(self.up, "tag", "-d", "v1.0.0")
        code, rep = self.run_sync()
        self.assertEqual(code, 2)
        self.assertEqual(self.events(rep), {("tag-deleted", "tags/v1.0.0")})

    def test_refs_custom_jamais_touchees(self):
        self.run_sync()
        sh(self.mirror, "update-ref", "refs/heads/custom/packaging", self.a)
        sh(self.mirror, "update-ref", "refs/notes/revue", self.a)
        sh(self.up, "reset", "--quiet", "--hard", self.a)
        self.commit("C")
        sh(self.up, "push", "--quiet", ".", "HEAD:refs/heads/custom/packaging")  # même nom côté amont
        self.run_sync()
        self.assertEqual(sh(self.mirror, "rev-parse", "refs/heads/custom/packaging"), self.a)
        self.assertEqual(sh(self.mirror, "rev-parse", "refs/notes/revue"), self.a)

    def test_rien_de_change(self):
        self.run_sync()
        code, rep = self.run_sync()
        self.assertEqual((code, rep["events"], rep["bundle"]), (0, [], None))
        self.assertEqual(len(list(self.bundles.glob("*.bundle"))), 1)

    def test_restauration_depuis_bundles_et_rapport(self):
        sh(self.up, "branch", "old")
        self.run_sync()
        self.commit("B")
        self.run_sync()
        sh(self.up, "reset", "--quiet", "--hard", self.a)
        self.commit("C")
        sh(self.up, "tag", "-f", "-a", "v1.0.0", "-m", "déplacé")
        sh(self.up, "branch", "-D", "old")
        self.run_sync()
        self.run_sync()  # run sans changement
        cible = Path(self.tmp.name) / "restaure"
        self.assertEqual(sync.main(["--mirror", str(self.mirror), "--report-dir", str(self.reports),
                                    "--bundle-dir", str(self.bundles), "--restore", str(cible)]), 0)
        self.assertEqual(self.mirror_refs(cible), self.mirror_refs())
        self.assertGreater(len(self.mirror_refs(cible, ("refs/archive/",))), 0)

    def test_bundle_rate_rattrape_au_run_suivant(self):
        self.run_sync()
        b = self.commit("B")
        vrai = sync.write_bundle

        def panne(*args):
            raise sync.GitError("disque plein")
        sync.write_bundle = panne
        try:
            code, rep = self.run_sync()
        finally:
            sync.write_bundle = vrai
        self.assertEqual((code, rep["status"]), (1, "error"))
        self.assertEqual(self.events(rep), {("fast-forward", "heads/main")}, "événements conservés")
        sh(self.up, "reset", "--quiet", "--hard", self.a)  # B n'existe plus qu'en archive
        self.commit("C")
        code, rep = self.run_sync()
        self.assertEqual(code, 2)
        self.assertIn(f"refs/archive/{self.stamp}/heads/main", rep["bundle"]["refs"])
        cible = Path(self.tmp.name) / "restaure"
        sync.main(["--mirror", str(self.mirror), "--report-dir", str(self.reports),
                   "--bundle-dir", str(self.bundles), "--restore", str(cible)])
        self.assertEqual(self.mirror_refs(cible), self.mirror_refs())
        sh(cible, "cat-file", "-e", f"{b}^{{commit}}")

    def test_publication_vers_forgejo(self):
        sh(Path(self.tmp.name), "init", "--quiet", "--bare", str(self.forgejo))
        sh(self.up, "branch", "old")
        self.run_sync("--push", f"file://{self.forgejo}")
        sh(self.up, "branch", "-D", "old")
        self.run_sync("--push", f"file://{self.forgejo}")
        fj = self.mirror_refs(self.forgejo, ("refs/",))
        self.assertEqual(set(fj), {"refs/heads/main", "refs/tags/v1.0.0", f"refs/archive/{self.stamp}/heads/old"})

    def test_protocole_file_refuse_sans_option(self):
        code, rep = self.run_sync(allow_file=False)
        self.assertEqual((code, rep["status"]), (1, "error"))
        self.assertIn("transport 'file' not allowed", rep["error"])


if __name__ == "__main__":
    unittest.main()
