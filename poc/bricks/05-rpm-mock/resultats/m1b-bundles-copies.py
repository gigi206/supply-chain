# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
"""Brique 05, cascade de M1b : section A du banc de m1b-bundles.sh. Chaque fonction recopiée est comparée à son original, à
l'octet près ; chaque étape transformée est refaite depuis son original par les remplacements listés ici, chacun compté, puis
comparée. Une ligne OK ou KO par contrôle ; code 1 si un KO.
Usage : python3 -I m1b-bundles-copies.py <dossier de la 05>"""
import sys

d = sys.argv[1]
SCRIPT = "m1b-bundles.sh"
COPIES = [("m4c.sh", n) for n in ("attendu", "ref_revue", "script_etape", "mesure", "pod_retirer", "copier_pod",
                                  "politique_relue", "echec", "admission", "libre_zot", "normaliser")] \
    + [("m4b.sh", n) for n in ("remplacer", "rendre_taches", "substituer", "pod_spec", "dans", "ARBRE")] \
    + [("m1b-artefact.sh", n) for n in ("neuf", "sha", "zot_lire")]
TRANSFORMATIONS = {
    ("m4b.sh", "etape_essai_tache", "etape_essai_prefetch"): [
        ("etape_essai_tache() {", "etape_essai_prefetch() {", 1),
        ('  attendu "liste des rpm (sha256)" "$(sha256sum < "$LISTE" | cut -c1-64)" "$LISTE_SHA"\n', "  sources\n", 1),
        ("POD=m4b-05-essai-tache", "POD=$N-bundles-prefetch", 1),
        ('  echo "script substitué : sha256 $(sha256sum < "$T/script-essai.sh" | cut -c1-64)"',
         '  attendu "script substitué, égal à celui de l\'essai de M4b (sha256)" "$(sha256sum < "$T/script-essai.sh" | cut -c1-64)" "$SCRIPT_PREFETCH_SHA"', 1),
        ("m4b-essai-tache", "prefetch-essai", 9),
    ],
    ("m4c.sh", "etape_essai", "etape_essai_construire"): [
        ("etape_essai() {", "etape_essai_construire() {", 1),
        ("  local p=m4c-essai x=$T/essai rc=0 d s", "  local p=$N-bundles-construire x=$T/essai-construire rc=0 d s", 1),
        ('  [ -s "$T/entrees.tar" ] && [ -s "$T/digest-attendu" ] || { echo "KO   lancer d\'abord prealables" >&2; exit 1; }',
         '  attendu "entrees.tar de m4c prealables (taille, sha256)" "$(stat -c %s "$ENTREES") $(sha "$ENTREES")" "$ENTREES_TAILLE $ENTREES_SHA"', 1),
        ('  rm -rf "$x"; mkdir -p "$x"', '  neuf "$x"; mkdir -p "$x"', 1),
        ("\n  rendre_taches\n", '\n  rendre "$T" "$IMAGE_NEUVE"\n', 1),
        ("\n  politique_relue\n",
         '\n  attendu "script d\'essai : égal à celui de l\'essai de M4c (sha256)" "$(sha "$x/construire.sh")" "$SCRIPT_CONSTRUIRE_SHA"\n  politique_relue\n', 1),
        ("$IMAGE_OUTILLAGE", "$IMAGE_NEUVE", 2),
        ("  trap 'kubectl delete pod -n builds m4c-essai --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true' EXIT",
         '  trap "kubectl delete pod -n builds $p --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true" EXIT', 1),
        ("m4c-essai-construire.log", "$N-bundles-construire-pod.log", 3),
        ('mesure "digest de l\'artefact" "$d" "$(cat "$T/digest-attendu")"',
         'mesure "digest de l\'artefact, égal à celui de l\'essai de M4c" "$d" "$DIGEST_ESSAI_M4C"', 1),
        ('"$VERROU" | sort)', '"$VERROU_ESSAI" | sort)', 1),
    ],
}


def bloc(L, nom):
    if nom == "ARBRE":
        i = L.index("ARBRE=$(cat <<'SH'")
        j = L.index("SH", i)
        assert L[j + 1] == ")"
        return L[i:j + 2]
    deb = [k for k, l in enumerate(L) if l.startswith(nom + "() {")]
    assert len(deb) == 1, (nom, deb)
    i = deb[0]
    if L[i].count("{") == L[i].count("}"):
        return [L[i]]
    return L[i:L.index("}", i) + 1]


lire = lambda f: open(f"{d}/{f}", encoding="utf-8").read().split("\n")
S = lire(SCRIPT)
ko = 0


def res(ok, lib):
    global ko
    print(("OK   " if ok else "KO   ") + lib)
    ko += not ok


for f, nom in COPIES:
    o = bloc(lire(f), nom)
    try:
        c = bloc(S, nom)
    except (AssertionError, ValueError):
        c = None
    res(c == o, f"A copie de {f} : {nom} ({len(o)} ligne(s)), égale à l'original")
for (f, nom, nouveau), regles in TRANSFORMATIONS.items():
    t = "\n".join(bloc(lire(f), nom))
    comptes = []
    for a, b, n in regles:
        comptes.append(t.count(a) == n)
        t = t.replace(a, b)
    res(all(comptes), f"A {f} : {nom}, {len(regles)} remplacement(s), chacun au compte attendu")
    res("\n".join(bloc(S, nouveau)) == t, f"A {nouveau} égale à {nom} de {f} après les remplacements")
sys.exit(1 if ko else 0)
