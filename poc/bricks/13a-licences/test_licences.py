#!/usr/bin/env python3
"""Tests de licences.py : python3 -m unittest -v test_licences"""
import tempfile
import unittest
from pathlib import Path

import licences

SPDX = {"licenseListVersion": "test", "licenses": [{"licenseId": i} for i in (
    "MIT", "Apache-2.0", "BSD-3-Clause", "GPL-2.0-only", "GPL-3.0-or-later", "LGPL-2.1-only", "CC-BY-SA-4.0")]}
EXC = {"exceptions": [{"licenseExceptionId": "Classpath-exception-2.0"}]}
POLICY = {"allow": ["MIT", "Apache-2.0", "BSD-3-Clause"], "warn": ["LGPL-*", "CC-BY-SA-4.0"],
          "deny": ["GPL-*"], "sourceObligation": ["GPL-*", "LGPL-*"], "excludePurlTypes": ["github"],
          "licenseRefs": ["LicenseRef-interne"]}


def comp(purl, *entries):
    return {"type": "library", "purl": purl, "licenses": list(entries)}


def lid(x):
    return {"license": {"id": x}}


class LicencesTest(unittest.TestCase):
    def verdicts(self, components, curations=(), closure=None, policy=POLICY):
        pred = licences.run({"components": components}, policy, SPDX, EXC, list(curations), closure)
        return pred, {c["purl"]: c for c in pred["components"]}

    def test_expressions_valides_et_normalisees(self):
        tree = licences.canonical(licences.parse("mit OR (apache-2.0 AND GPL-2.0-only WITH classpath-exception-2.0)"),
                                  {l["licenseId"].lower(): l["licenseId"] for l in SPDX["licenses"]},
                                  {"classpath-exception-2.0": "Classpath-exception-2.0"}, set())
        self.assertEqual(licences.render(tree),
                         "MIT OR (Apache-2.0 AND GPL-2.0-only WITH Classpath-exception-2.0)")

    def test_expressions_invalides(self):
        for expr in ("MIT AND", "(MIT", "MIT OR OR Apache-2.0", "MIT; rm -rf", "Inconnue-1.0", "MIT WITH Rien"):
            _, v = self.verdicts([comp("pkg:npm/x@1", {"expression": expr})])
            self.assertEqual(v["pkg:npm/x@1"]["verdict"], "error", expr)
            self.assertTrue(v["pkg:npm/x@1"].get("invalid"), expr)

    def test_noassertion_est_une_erreur_et_la_curation_la_leve(self):
        pred, v = self.verdicts([comp("pkg:golang/example.com/a@v1.0.0")])
        self.assertEqual((v["pkg:golang/example.com/a@v1.0.0"]["verdict"], pred["noassertion"]), ("error", 1))
        cur = [{"purl": "pkg:golang/example.com/a@v1.0.0", "expression": "MIT", "reviewer": "r"}]
        pred, v = self.verdicts([comp("pkg:golang/example.com/a@v1.0.0")], cur)
        self.assertEqual((v["pkg:golang/example.com/a@v1.0.0"]["verdict"], pred["noassertion"]), ("ok", 0))
        self.assertEqual(v["pkg:golang/example.com/a@v1.0.0"]["source"], "curation")

    def test_curation_trouvee_malgre_un_purl_ecrit_autrement(self):
        cur = [{"purl": "pkg:golang/github.com/go-chi/chi/v5@v5.2.3?type=module", "expression": "MIT"}]
        _, v = self.verdicts([comp("pkg:golang/github.com/go-chi/chi@v5.2.3#v5")], cur)
        self.assertEqual(v["pkg:golang/github.com/go-chi/chi@v5.2.3#v5"]["verdict"], "ok")

    def test_or_favorable_and_defavorable(self):
        _, v = self.verdicts([comp("pkg:npm/a@1", {"expression": "MIT OR GPL-3.0-or-later"}),
                              comp("pkg:npm/b@1", {"expression": "MIT AND GPL-3.0-or-later"}),
                              comp("pkg:npm/c@1", lid("MIT"), lid("CC-BY-SA-4.0"))])
        self.assertEqual(v["pkg:npm/a@1"]["verdict"], "ok")
        self.assertEqual(v["pkg:npm/b@1"]["verdict"], "error")
        self.assertEqual((v["pkg:npm/c@1"]["verdict"], v["pkg:npm/c@1"]["expression"]), ("warning", "CC-BY-SA-4.0 AND MIT"))

    def test_licence_hors_politique_et_licenseref(self):
        policy = dict(POLICY, allow=["MIT"])
        _, v = self.verdicts([comp("pkg:npm/a@1", lid("Apache-2.0")),
                              comp("pkg:npm/b@1", {"expression": "LicenseRef-interne"}),
                              comp("pkg:npm/c@1", {"expression": "LicenseRef-autre"})], policy=policy)
        self.assertEqual(v["pkg:npm/a@1"]["verdict"], "error")  # absente de la politique
        self.assertEqual(v["pkg:npm/b@1"]["verdict"], "error")  # autorisée comme référence, mais non classée
        self.assertTrue(v["pkg:npm/c@1"].get("invalid"))

    def test_entree_non_spdx_ignoree_avec_avertissement(self):
        _, v = self.verdicts([comp("pkg:npm/a@1", lid("MIT"), {"license": {"name": "sha256:abc"}}),
                              comp("pkg:npm/b@1", {"license": {"name": "Voir le fichier LICENSE"}})])
        self.assertEqual((v["pkg:npm/a@1"]["verdict"], v["pkg:npm/a@1"]["expression"]), ("warning", "MIT"))
        self.assertEqual((v["pkg:npm/b@1"]["verdict"], v["pkg:npm/b@1"]["expression"]), ("error", "NOASSERTION"))

    def test_fichiers_et_types_exclus(self):
        pred, _ = self.verdicts([{"type": "file", "name": "x.yml"}, comp("pkg:github/actions/checkout@v4")])
        self.assertEqual(pred["components"], [])

    def test_obligation_de_sources(self):
        with tempfile.TemporaryDirectory() as d:
            closure = Path(d)
            z = closure / "deps/gomod/pkg/mod/cache/download/example.com/!l!g!p!l/@v/v1.0.0.zip"
            z.parent.mkdir(parents=True)
            z.write_bytes(b"zip")
            comps = [comp("pkg:golang/example.com/LGPL@v1.0.0", lid("LGPL-2.1-only")),
                     comp("pkg:golang/example.com/absent@v1.0.0", lid("LGPL-2.1-only"))]
            pred, v = self.verdicts(comps, closure=closure)
            self.assertEqual(v["pkg:golang/example.com/LGPL@v1.0.0"]["verdict"], "warning")
            self.assertEqual(v["pkg:golang/example.com/LGPL@v1.0.0"]["sourceFile"], str(z.relative_to(closure)))
            self.assertEqual(v["pkg:golang/example.com/absent@v1.0.0"]["verdict"], "error")
            self.assertEqual(len(pred["sourceObligations"]), 2)


if __name__ == "__main__":
    unittest.main()
