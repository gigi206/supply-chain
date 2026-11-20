# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
"""Vérifie NT1 à NT4 (m1b_temoins) contre rpm_temoins du 16/11. Usage : python3 -I nt-verif.py <racine>
Seules les adresses résolues sont normalisées (« résolu (…) » devient « résolu »). N'affiche que des libellés et des verdicts."""
import sys, re
R = sys.argv[1]
D = R + "/poc/bricks/08c-durcissement/resultats/"
def sections(p):
    L = open(p, encoding="utf-8").read().split("\n")
    assert not any(re.search("jeton|token", l, re.I) for l in L), p
    s, cur = {}, None
    for l in L:
        m = re.match(r"^### sortie-(\S+) \(label tekton\.dev/task : (\S+)\)$", l)
        if m: cur = m.group(1); s[cur] = {"label": m.group(2), "lignes": []}; continue
        if cur and l.startswith("     "):
            s[cur]["lignes"].append(re.sub(r"résolu \([^)]*\)$", "résolu", l.strip()))
        elif not l.startswith("     "): cur = None
    return s
a, n = sections(D + "sortie-rpm_temoins.log"), sections(D + "sortie-m1b_temoins.log")
ok = ko = 0
def v(lib, c):
    global ok, ko
    print(("OK   " if c else "KO   ") + lib)
    if c: ok += 1
    else: ko += 1
v("cinq témoins le 16/11", sorted(a) == ["construire", "deb", "prefetch", "rpm", "sans-label"])
v("sept témoins le 20/11", sorted(n) == sorted(list(a) + ["racine-p", "racine-c"]))
for k in sorted(a):
    v(f"NT1 {k} : même label", a[k]["label"] == n.get(k, {}).get("label"))
    v(f"NT1 {k} : mêmes lignes ({len(a[k]['lignes'])}) aux adresses près", a[k]["lignes"] == n.get(k, {}).get("lignes"))
v("NT2 label prefetch-racine-rpm", n.get("racine-p", {}).get("label") == "prefetch-racine-rpm")
v("NT2 racine-p : lignes du témoin rpm", n.get("racine-p", {}).get("lignes") == a["rpm"]["lignes"])
v("NT3 label construire-racine-rpm", n.get("racine-c", {}).get("label") == "construire-racine-rpm")
v("NT3 racine-c : lignes du témoin construire", n.get("racine-c", {}).get("lignes") == a["construire"]["lignes"])
v("NT4 racine-c admis (10 lignes rendues)", len(n.get("racine-c", {}).get("lignes", [])) == 10)
print(f"# bilan : OK {ok} ; KO {ko}")
sys.exit(1 if ko else 0)
