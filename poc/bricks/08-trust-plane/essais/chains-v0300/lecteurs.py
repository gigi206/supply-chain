#!/usr/bin/env python3
"""Banc à sec de Chains v0.30.0 (brique 08) : effet du nom pipelineTask/<nom> sur les lecteurs de provenance, règles de la porte,
genre() de la 20 et tests de la porte. Entrées : énoncés signés (cosign, Zot en anonyme) et sorties réelles de v0.30.0 (main.go).
Lecture seule ; écrit sous ~/.cache/supply-chain-poc/chains-v0300. Usage (racine du dépôt) : mise exec -- python3 -I <ce fichier>"""
import base64, copy, json, os, re, subprocess, sys
from pathlib import Path

sys.dont_write_bytecode = True
DEPOT = Path.cwd()
P08 = DEPOT / "poc/bricks/08-trust-plane"
B = Path.home() / ".cache/supply-chain-poc/chains-v0300"
S, L = B / "sorties", B / "regles"
REG, HOTE = "sc-stockage.poc.test:5000", "192.168.161.13:5000"
CA = str(Path.home() / ".cache/supply-chain-poc/08/pki/ca-poc.crt")
REV = "6391fd437f26696847041be3226bbbf633f55a2f"
PAQUETS = ["porte", "trusted_task", "attestation_type", "slsa_build_build_service", "slsa_build_scripted_build",
           "slsa_provenance_available", "slsa_source_correlated", "slsa_source_version_controlled", "tasks"]
lire = lambda f: json.loads(f.read_text())
lignes = lambda f: [json.loads(x) for x in f.read_text().splitlines() if x]
est_pr = lambda s: "pipelineRef" in s["predicate"]["buildDefinition"]["externalParameters"].get("runSpec", {})
fin = lambda s: s["predicate"]["runDetails"]["metadata"]["finishedOn"]
deps = lambda s: s["predicate"]["buildDefinition"]["resolvedDependencies"]


def opa(*a, env=None):
    r = subprocess.run(["ec", "opa", "eval", "-f", "json", *a], cwd=L, capture_output=True, text=True, env={**os.environ, **(env or {})})
    if r.returncode != 0:
        sys.exit(f"KO ec opa : {r.stderr[:400] or r.stdout[:400]}")
    return json.loads(r.stdout)["result"][0]["expressions"][0]["value"]


BASE = ["-d", "policy", "-d", "porte.rego", "-d", "taches.yml", "-d", "donnees.json"]


def entree(enonces, image, n):
    sha = image.split("@sha256:")[1]
    e = {"attestations": [{"statement": s} for s in enonces],
         "image": {"ref": image, "signatures": [{"keyid": "", "sig": "x"}],
                   "source": {"git": {"url": "https://sc-stockage.poc.test:3000/workspace/sample-app.git", "revision": REV}}}}
    (L / n).write_text(json.dumps(e))
    return sha


def verifs(n, transforme):
    """fermetures lues par porte.rego dans cette entrée, vérifiées par la vraie fonction d'ec, énoncés transformés ensuite"""
    f = opa(*BASE, "-i", n, "data.porte._fermetures")
    d = {}
    for x in f:
        ref = x["ref"].replace(REG, HOTE)
        q = f'ec.sigstore.verify_attestation("{ref}", data.config.default_sigstore_opts)'
        v = opa("-d", "donnees.json", q, env={"SSL_CERT_FILE": CA})
        v["attestations"] = [{**a, "statement": transforme(a["statement"])} for a in v["attestations"]]
        d[x["ref"]] = v
    # bundles des tâches : vrais manifestes, pris par l'adresse (l'hôte ne résout pas le nom du registre : ec réessaie et chaque règle attend)
    refs = opa(*BASE, "-i", n, "data.lib.pipelinerun_bundle_refs")
    q = "ec.oci.image_manifests({" + ",".join(json.dumps(x.replace(REG, HOTE)) for x in refs) + "})" if refs else "{}"
    m = {k.replace(HOTE, REG): v for k, v in opa(q, env={"SSL_CERT_FILE": CA}).items()}
    if set(m) != set(refs):
        sys.exit(f"KO manifestes de bundles : {len(m)} lus pour {len(refs)}")
    (L / "verifs.json").write_text(json.dumps({"verifs": d, "manifestes": m}))
    return len(d), sum(len(v["attestations"]) for v in d.values())


def codes(enonces, image, transforme=lambda s: s):
    """codes de refus des règles évaluées, bundles et fermetures pris dans le registre puis injectés ; (codes, fermetures, provenances de fermeture)"""
    entree(enonces, image, "entree.json")
    nf, na = verifs("entree.json", transforme)
    out = set()
    for p in PAQUETS:
        r = subprocess.run(["ec", "opa", "eval", "-f", "json", *BASE, "-d", "verifs.json", "-d", "reel.rego", "-i", "entree.json",
                            f"d := data.{p}.deny with ec.sigstore.verify_attestation as data.reel.verif with ec.oci.image_manifests as data.reel.manifestes"],
                           cwd=L, capture_output=True, text=True, env={**os.environ, "SSL_CERT_FILE": CA})
        if r.returncode:
            sys.exit(f"KO {p} : {r.stderr[:400]}{r.stdout[:400]}")
        out |= {x["code"] for x in json.loads(r.stdout)["result"][0]["bindings"]["d"]}
    return sorted(out), nf, na


def renomme(s):
    """énoncé ancien -> noms de v0.30.0 (forme mesurée sur les sorties réelles)"""
    s = copy.deepcopy(s)
    if est_pr(s):
        for d in deps(s):
            if d.get("name") == "pipelineTask":
                t = json.loads(base64.b64decode(d["content"]))
                d["name"] = "pipelineTask/" + t["metadata"]["labels"]["tekton.dev/pipelineTask"]
    return s


def date(s, d):
    s = copy.deepcopy(s)
    s["predicate"]["runDetails"]["metadata"]["finishedOn"] = d
    return s


def main():
    ecarts = 0

    def cas(nom, vu, attendu):
        nonlocal ecarts
        ok = attendu(vu) if callable(attendu) else vu == attendu
        ecarts += not ok
        print(f"{'OK   ' if ok else 'ÉCART'} {nom} : {vu}")

    print(f"# lecteurs.py, dépôt {subprocess.run(['git', 'rev-parse', '--short=8', 'HEAD'], capture_output=True, text=True).stdout.strip()}")
    for f, d in (("donnees.json", {"config": {"default_sigstore_opts": {"public_key": (P08 / "resultats/chains-cle-publique.pem").read_text(),
        "ignore_rekor": True, "certificate_identity": "", "certificate_identity_regexp": "", "certificate_oidc_issuer": "",
        "certificate_oidc_issuer_regexp": "", "rekor_url": ""}},
        "rule_data__configuration__": {"allowed_builder_ids": ["https://supply-chain.example/builders/tekton-chains@v1"]}}),):
        (L / f).write_text(json.dumps(d))
    (L / "reel.rego").write_text("package reel\n\nimport rego.v1\n\nverif(ref, _) := data.verifs[ref]\n\n"
                                "manifestes(refs) := {r: data.manifestes[r] | some r in refs}\n")
    print("## forme de v0.30.0 sur les sorties réelles")
    for n in ("j7-sample-app", "sample-app-deb-" + REV, "m5b-4-rpm-1", "m5b-4-construction-1", "f2-prefetch-1"):
        a, b = lire(S / f"{n}.29.json"), lire(S / f"{n}.30.json")
        na = [d.get("name", "") for d in deps(a)]
        nb = [d.get("name", "") for d in deps(b)]
        cas(f"{n}, noms de tâche", sorted(x for x in nb if x.startswith("pipelineTask")),
            lambda v, k=na.count("pipelineTask"): len(v) == k > 0 and all(x.startswith("pipelineTask/") for x in v))
        for s in (a, b):
            for d in deps(s):
                d.pop("name", None)
            for x in s["predicate"]["runDetails"].get("byproducts", []):
                x["name"] = x["name"].rsplit("/", 1)[1]
        cas(f"{n}, hors noms des dépendances et du TaskRun dans les byproducts", "égal" if a == b else "différent", "égal")
        cas(f"{n}, renomme() égale à la sortie réelle de v0.30.0 sur les noms", [d.get("name", "") for d in deps(renomme(lire(S / f"{n}.29.json")))], nb)
    images = {"app": ("f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7", "builds/sample-app", "j7-sample-app"),
              "deb": ("60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e", "builds/sample-app-deb", "sample-app-deb-" + REV)}
    for c, (sha, dep, n) in images.items():
        img = f"{REG}/{dep}@sha256:{sha}"
        anc = lignes(S / f"signees-{c}.jsonl")
        prs = sorted((s for s in anc if est_pr(s)), key=fin)
        neuf = lire(S / f"{n}.30.json")
        print(f"## {c} : {len(anc)} énoncés signés, {len(prs)} de PipelineRun, le plus récent fini à {fin(prs[-1])} ; neuf fini à {fin(neuf)}")
        r, nf, na = codes(anc, img)
        print(f"  fermetures {nf}, provenances de fermeture vérifiées {na}")
        cas(f"{c} P6 ancien seul", r, [])
        reste = [s for s in anc if not est_pr(s)]
        r, nf, _ = codes(reste + [neuf], img)
        cas(f"{c} P5 neuf seul (fermetures lues {nf})", r, lambda v: "porte.taches_vues" in v)
        r, *_ = codes([renomme(s) for s in anc], img)
        cas(f"{c} P5 tous renommés", r, lambda v: "porte.taches_vues" in v)
        r, *_ = codes(anc + [date(neuf, "2026-11-26T00:00:00Z")], img)
        cas(f"{c} P7 mélange, neuf le plus récent", r, lambda v: "porte.taches_vues" in v)
        r, *_ = codes(anc + [date(neuf, "2026-11-01T00:00:00Z")], img)
        cas(f"{c} P7 mélange, ancien le plus récent", r, [])
        r, nf, na = codes(anc, img, transforme=renomme)
        cas(f"{c} P8 fermetures prouvées par des énoncés neufs ({na} provenances)", r, lambda v: "porte.fermeture_plateforme" in v)
    print("## genre() (P10)")
    sys.path.insert(0, str(DEPOT / "poc/bricks/20-kpi"))
    src = {}
    for nom, f in (("exportateur", DEPOT / "tools/metrics-exporter/metrics_exporter.py"), ("recalcul", DEPOT / "poc/bricks/20-kpi/recalcul.py")):
        m = re.search(r"^def genre\(.*?(?=^\S)", f.read_text(), re.S | re.M)   # la fonction seule, sans lancer le module
        e = {}
        exec(m.group(0), e)
        src[nom] = e["genre"]
    for n in ("j7-sample-app", "sample-app-deb-" + REV, "m5b-4-construction-1"):
        for v in (29, 30):
            g = {k: [f(d) for d in deps(lire(S / f"{n}.{v}.json")) if d.get("name", "").startswith("pipelineTask") and "uri" in d] for k, f in src.items()}
            cas(f"{n}, v0.{v}.x, exportateur et recalcul", g, lambda x, v=v: x["exportateur"] == x["recalcul"] and len(x["recalcul"]) > 0
                and set(x["recalcul"]) == ({"tache"} if v == 29 else {"image"}))
    print("## porte_test.rego (P9)")
    for nom, f in (("nom ancien", lambda t: t), ("nom neuf", lambda t: t.replace('"name": "pipelineTask"', '"name": "pipelineTask/x"'))):
        (L / "t").mkdir(exist_ok=True)
        (L / "t/porte_test.rego").write_text(f((P08 / "politique/porte/porte_test.rego").read_text()))
        r = subprocess.run(["ec", "opa", "test", "-v", "policy", "porte.rego", "t/porte_test.rego", "taches.yml"], cwd=L, capture_output=True, text=True)
        p = len(set(re.findall(r"^data\.porte_test\.(test_\w+): PASS", r.stdout, re.M)))
        k = len(set(re.findall(r"^data\.porte_test\.(test_\w+): (?:FAIL|ERROR)", r.stdout, re.M)))   # opa liste deux fois chaque échec
        cas(f"tests, {nom} (PASS, FAIL)", (p, k), (39, 0) if nom == "nom ancien" else lambda v: v[1] > 0)
    print("## sélections jq des scripts (P11) : dépendances et contenus retenus")
    for n in ("j7-sample-app", "sample-app-deb-" + REV):
        for v in (29, 30):
            d = deps(lire(S / f"{n}.{v}.json"))
            cas(f"{n}, v0.{v}.x, select(.name == \"pipelineTask\")", sum(x.get("name") == "pipelineTask" for x in d), 3 if v == 29 else 0)
    print(f"## bilan : {ecarts} écart(s) avec la prédiction")
    return ecarts


sys.exit(1 if main() else 0)
