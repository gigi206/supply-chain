#!/usr/bin/env bash
# Brique 09, banc hors réseau des refus d'o5-signes.py non déclenchés par o5-signes-banc.sh ni par essai_attest (relecture du
# conseiller, 19/11/2026) : membre hors de la chaîne, adresse hors des domaines réservés, deux ou zéro enveloppe de lien, sujet
# différent. Arbres copiés des dépôts gardés d'O3 et d'O4, layouts construits par o5-signes.py ; images non signées locales, dont
# les digests remplacent les valeurs archivées (O5_SIGNES_ATTENDUS, banc seulement). Rien n'est écrit hors du dossier du banc.
# Usage : poc/bricks/09-openpgp-signing/o5-signes-refus-banc.sh   (journal : resultats/o5-signes-refus-banc.log ; dossier effacé à la main)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
B=$HOME/.cache/supply-chain-poc/09/o5-signes-refus-banc
[ ! -e "$B" ] || { echo "KO   $B existe déjà" >&2; exit 1; }
mkdir -p "$B"
{
echo "banc commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-signes.py $(sha256sum < "$here/o5-signes.py" | cut -c1-16)… ; o5-signes-refus-banc.sh $(sha256sum < "$0" | cut -c1-16)…"
python3 -I - "$here/o5-signes.py" "$B" <<'PY'
import base64, contextlib, importlib.util, io, json, os, shutil, sys
spec = importlib.util.spec_from_file_location("s", sys.argv[1]); s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
B = sys.argv[2]
ok = ko = 0
def cas(libelle, attendu, f, *a):
    """attendu : motif du refus (sous-chaîne) ou None pour ACCEPTÉ"""
    global ok, ko
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            f(*a)
        r = "ACCEPTÉ"
    except s.Refus as e:
        r = f"REFUS {e}"
    bon = (r == "ACCEPTÉ") if attendu is None else (r.startswith("REFUS") and attendu in r)
    print(f"{'OK' if bon else 'KO'}   {libelle} : {r[:170]}")
    ok, ko = ok + bon, ko + (not bon)
# images non signées locales et valeurs remplacées
r = {}
for cle, nom, src in (("rpm_manifeste", s.RPM, s.L.FICHIERS["rpm-entree"]), ("deb_manifeste", s.DEB, s.L.FICHIERS["deb"])):
    dm, _ = s.ecrire_layout(os.path.join(B, "ns-" + cle[:3]), {nom: open(src, "rb").read()}); r[cle] = dm
json.dump(r, open(os.path.join(B, "attendus.json"), "w")); os.environ["O5_SIGNES_ATTENDUS"] = os.path.join(B, "attendus.json")
a = s.attendus()
print("### arbres de dépôt (membres_controles, comme construire)")
for c in ("depot-rpm", "depot-apt"):
    f = s.arbre(s.L.FICHIERS[c])
    cas(f"{c} tel quel", None, lambda f=f, c=c: s.membres_controles(c, f, a))
    g = dict(f); g["en-trop.txt"] = b"fichier sans lien avec la chaine\n"
    cas(f"{c} + un membre hors de la chaîne", "hors de la chaîne", lambda g=g, c=c: s.membres_controles(c, g, a))
    g = dict(f); g["note.txt"] = b"contact : quelqu" + b"un@exemple-prive.fr\n"
    cas(f"{c} + une adresse hors de .invalid et .example", "hors des domaines réservés", lambda g=g, c=c: s.membres_controles(c, g, a))
    g = dict(f); g["note.txt"] = b"contact : banc@supply-chain.invalid\n"
    cas(f"{c} + une adresse en .invalid : admise par le balayage, refusée par la chaîne", "hors de la chaîne", lambda g=g, c=c: s.membres_controles(c, g, a))
    g = dict(f); del g[sorted(k for k in f if not k.endswith((".rpm", ".deb")))[-1]]
    cas(f"{c} − un membre de la chaîne", "", lambda g=g, c=c: s.membres_controles(c, g, a))
print("### enveloppes (controle, sur le rpm signé construit et l'image non signée locale)")
L = os.path.join(B, "layouts")
with contextlib.redirect_stdout(io.StringIO()):
    s.construire(L)
dg = s.digests(L)
ch = os.path.join(B, "chains.json")
json.dump({x: {"cle": "banc", "date": "banc", "enveloppes": 0} for x in ("rpm", "deb")}, open(ch, "w"))
with contextlib.redirect_stdout(io.StringIO()):
    s.predicats(L, ch, os.path.join(B, "p"))
def enveloppe(pred, digest):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        s.enonce("rpm", pred, digest)
    return out.getvalue()
une = enveloppe(os.path.join(B, "p", "rpm.json"), dg["rpm"])
def ctl(lignes, digest=dg["rpm"]):
    p = os.path.join(B, "env.jsonl"); open(p, "w").write(lignes)
    s.controle("rpm", p, digest, os.path.join(L, "rpm"), os.path.join(B, "ns-rpm"))
cas("une enveloppe de lien", None, ctl, une)
cas("deux enveloppes de lien", "2 énoncé(s) de type lien", ctl, une + une)
autre = json.loads(une); st = json.loads(base64.b64decode(autre["payload"])); st["predicateType"] = "https://slsa.dev/provenance/v1"
autre["payload"] = base64.b64encode(json.dumps(st).encode()).decode()
cas("zéro enveloppe de lien (une enveloppe d'un autre type)", "0 énoncé(s) de type lien", ctl, json.dumps(autre) + "\n")
cas("sujet différent du digest attendu", "sujet", ctl, une, dg["depot-rpm"])
print(f"bilan : {ok} OK, {ko} KO")
sys.exit(1 if ko else 0)
PY
echo "banc fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "à effacer après archivage (chemin littéral) : $B"
} 2>&1 | tee "$here/resultats/o5-signes-refus-banc.log"
