"""Regroupe les deux fichiers de tests du correctif v2 (tsa_key_attestor_test.go puis tsa_extra_test.go) en un seul,
tsa_cert_chain_test.go, sans toucher à la logique : un seul bloc d'imports (bibliothèque standard, puis le reste, triés,
dédoublonnés, alias gardés), puis les corps des deux fichiers à la suite, tels quels. Assertions : mêmes déclarations de
premier niveau, sans doublon ; 9 fonctions Test.
Usage : python3 -I regrouper-tests.py <répertoire du paquet cosign>"""
import os, re, sys

d = sys.argv[1]
SRC = ["tsa_key_attestor_test.go", "tsa_extra_test.go"]
DST = "tsa_cert_chain_test.go"
DECL = re.compile(r"^(?:func (?:\([^)]*\) )?(\w+)|type (\w+)|const (\w+)|var (\w+))", re.M)

def decoupe(c):
    m = re.search(r"^import \(\n(.*?)^\)\n", c, re.M | re.S)
    assert m and c.startswith("package cosign\n"), "en-tête inattendu"
    specs = [l.strip() for l in m.group(1).splitlines() if l.strip()]
    return specs, c[m.end():]

def decls(c):
    return [next(g for g in m.groups() if g) for m in DECL.finditer(c)]

specs, corps, avant = [], [], []
for f in SRC:
    c = open(os.path.join(d, f), encoding="utf-8").read()
    s, b = decoupe(c)
    specs += s; corps.append(b); avant += decls(c)
assert len(avant) == len(set(avant)), "déclaration en double"
def chemin(s): return s.split('"')[1]
uniques = sorted(set(specs), key=chemin)
assert len({chemin(s) for s in uniques}) == len(uniques), "même chemin importé sous deux formes"
std = [s for s in uniques if "." not in chemin(s).split("/")[0]]
ext = [s for s in uniques if s not in std]
out = "package cosign\n\nimport (\n" + "".join(f"\t{s}\n" for s in std) + "\n" + "".join(f"\t{s}\n" for s in ext) + ")\n"
out += corps[0].rstrip("\n") + "\n" + corps[1]
apres = decls(out)
assert sorted(apres) == sorted(avant), "déclarations différentes"
assert sum(1 for n in apres if n.startswith("Test")) == 9, "9 fonctions Test attendues"
open(os.path.join(d, DST), "w", encoding="utf-8").write(out)
for f in SRC:
    os.remove(os.path.join(d, f))
print(f"{DST} écrit : {len(out.splitlines())} lignes, {len(uniques)} imports ({len(std)} standard), {len(apres)} déclarations, 9 tests")
