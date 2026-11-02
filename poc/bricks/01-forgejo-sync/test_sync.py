#!/usr/bin/env python3
"""Tests de la brique 01 sur des dépôts git locaux : python3 -m unittest -v test_sync"""
import datetime
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

    # Refs propres (B7, décisions du propriétaire du 02/11/2026) : motifs du projet ajoutés aux globaux ;
    # collision critique, publiée dans le miroir, jamais propagée au fork.
    def config(self, conf):
        path = Path(self.tmp.name) / "refs-propres.json"
        path.write_text(json.dumps(conf))
        return path

    def b7(self):
        return self.config({"global": {"branches": ["custom-*"], "tags": ["custom-*"]},
                            "depots": {"p": {"branches": ["paquet/*"]}, "q": {"branches": ["autre-*"]}}})

    def fork(self, *refs_a):
        sh(Path(self.tmp.name), "init", "--quiet", "--bare", str(self.forgejo))
        fork = Path(self.tmp.name) / "fork.git"
        sh(Path(self.tmp.name), "init", "--quiet", "--bare", str(fork))
        sh(self.up, "push", "--quiet", f"file://{fork}", *(f"{self.a}:{r}" for r in refs_a))
        return fork

    def test_config_globale_completee_par_depot(self):
        c = self.b7()
        self.assertEqual(sync.own_patterns(c, "p"), {"branches": ["custom-*", "paquet/*"], "tags": ["custom-*"]})
        self.assertEqual(sync.own_patterns(c, None), {"branches": ["custom-*"], "tags": ["custom-*"]})
        self.assertEqual(sync.own_patterns(c, "inconnu"), sync.own_patterns(c, None))
        self.assertEqual(sync.own_patterns(None, None), {"branches": [], "tags": []})

    def test_motif_invalide_refuse_avant_git(self):
        for motif in ("a*b*", "v?", "[ab]", "^x", ""):
            c = self.config({"global": {"branches": [motif]}})
            code, rep = self.run_sync("--refs-propres", str(c))
            self.assertEqual((code, rep["status"]), (1, "error"), motif)
            self.assertIn("motif de ref propre invalide", rep["error"])
        self.assertFalse(self.mirror.exists(), "aucun appel à git")

    def test_fork_mis_a_jour_sans_perte(self):
        fork = self.fork("refs/heads/custom-1", "refs/heads/paquet/deb", "refs/tags/custom-1")
        sh(self.up, "branch", "old")
        opts = ("--refs-propres", str(self.b7()), "--projet", "p", "--fork", f"file://{fork}")
        self.assertEqual(self.run_sync(*opts)[0], 0)
        sh(self.up, "branch", "-D", "old")
        b = self.commit("B")
        code, rep = self.run_sync(*opts)
        self.assertEqual(code, 0)
        self.assertEqual(rep["refs_propres"], {"branches": ["custom-*", "paquet/*"], "tags": ["custom-*"]})
        fk = self.mirror_refs(fork, ("refs/",))
        self.assertEqual(fk, {"refs/heads/main": b, "refs/heads/old": self.a, "refs/tags/v1.0.0": sh(self.up, "rev-parse", "v1.0.0"),
                              "refs/heads/custom-1": self.a, "refs/heads/paquet/deb": self.a, "refs/tags/custom-1": self.a},
                         "branche amont supprimée gardée, refs propres intactes")

    def test_collision_branche_et_tag(self):
        fork = self.fork("refs/heads/custom-1", "refs/heads/paquet/deb")
        opts = ("--refs-propres", str(self.b7()), "--projet", "p", "--push", f"file://{self.forgejo}", "--fork", f"file://{fork}")
        self.run_sync(*opts)
        c = self.commit("C amont")
        for r in ("refs/heads/custom-1", "refs/heads/paquet/deb", "refs/heads/autre-1"):
            sh(self.up, "update-ref", r, c)
        sh(self.up, "tag", "custom-2")
        code, rep = self.run_sync(*opts)
        self.assertEqual((code, rep["status"]), (2, "rewrite-detected"))
        self.assertEqual({r for t, r in self.events(rep) if t == "collision"},
                         {"heads/custom-1", "heads/paquet/deb", "tags/custom-2"}, "autre-1 est propre au projet q seulement")
        fj = self.mirror_refs(self.forgejo, ("refs/heads/", "refs/tags/"))
        self.assertEqual((fj["refs/heads/custom-1"], fj["refs/tags/custom-2"]), (c, c), "collision publiée dans le miroir")
        fk = self.mirror_refs(fork, ("refs/",))
        self.assertEqual((fk["refs/heads/custom-1"], fk["refs/heads/paquet/deb"]), (self.a, self.a), "refs propres du fork intactes")
        self.assertNotIn("refs/tags/custom-2", fk)
        self.assertEqual(fk["refs/heads/autre-1"], c)
        d = self.commit("D")
        sh(self.up, "update-ref", "refs/heads/custom-1", d)  # avance rapide amont de la ref en collision
        code, rep = self.run_sync(*opts)
        self.assertEqual(code, 2)
        self.assertIn(("collision", "heads/custom-1"), self.events(rep))
        self.assertEqual(self.mirror_refs(fork, ("refs/heads/custom-1",)), {"refs/heads/custom-1": self.a})

    def test_metriques_deduites_des_rapports(self):
        def epoch(st):
            return str(int(datetime.datetime.strptime(st, "%Y%m%dT%H%M%SZ")
                           .replace(tzinfo=datetime.timezone.utc).timestamp()))
        prom = Path(self.tmp.name) / "sync.prom"
        m = ("--metriques", str(prom), "--projet", "p")
        self.run_sync(*m)
        un = self.stamp
        self.commit("B")
        self.run_sync(*m)
        sh(self.up, "reset", "--quiet", "--hard", self.a)
        self.commit("C")
        self.assertEqual(self.run_sync(*m)[0], 2)
        reecriture = self.stamp
        self.assertEqual(self.run_sync(*m, allow_file=False)[0], 1)  # run en erreur
        val = {l.rsplit(" ", 1)[0]: l.rsplit(" ", 1)[1] for l in prom.read_text().splitlines() if not l.startswith("#")}
        self.assertEqual(val, {
            'sync_derniere_reussite_timestamp_seconds{projet="p"}': epoch(reecriture),
            'sync_derniere_reecriture_timestamp_seconds{projet="p"}': epoch(reecriture),
            'sync_dernier_run_statut{projet="p",statut="ok"}': "0",
            'sync_dernier_run_statut{projet="p",statut="rewrite-detected"}': "0",
            'sync_dernier_run_statut{projet="p",statut="error"}': "1"})
        self.assertNotEqual(epoch(un), epoch(reecriture))
        self.assertEqual([f.name for f in prom.parent.glob(".sync.prom*")], [], "pas de fichier temporaire laissé")

    def test_metriques_sans_reussite(self):
        prom = Path(self.tmp.name) / "sync.prom"
        self.run_sync("--metriques", str(prom), allow_file=False)
        txt = prom.read_text()
        self.assertNotIn("sync_derniere_reussite_timestamp_seconds{", txt, "absente tant qu'aucun run n'a réussi")
        self.assertIn('sync_dernier_run_statut{projet="miroir",statut="error"} 1', txt)

    def test_protocole_file_refuse_sans_option(self):
        code, rep = self.run_sync(allow_file=False)
        self.assertEqual((code, rep["status"]), (1, "error"))
        self.assertIn("transport 'file' not allowed", rep["error"])


if __name__ == "__main__":
    unittest.main()
