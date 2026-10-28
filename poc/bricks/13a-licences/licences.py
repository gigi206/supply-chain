#!/usr/bin/env python3
"""Brique 13a : verdict sur les licences déclarées d'un SBOM CycloneDX.

Pour chaque composant (hors types exclus par la politique) :
  1. expression retenue : la curation revue si elle existe, sinon les licences
     déclarées dans le SBOM (identifiants et expressions SPDX, combinés par AND) ;
     sans rien de valide, NOASSERTION ;
  2. validation de l'expression contre la liste SPDX (identifiants, exceptions,
     LicenseRef autorisés par la politique) ;
  3. verdict : chaque licence est classée « allow », « warn » ou « deny » par la
     politique (motifs fnmatch) ; OR retient la branche la plus favorable, AND
     la plus défavorable. NOASSERTION, expression invalide ou licence inconnue
     de la politique donnent ERROR ;
  4. obligations de sources (GPL, LGPL, MPL…) : avec --closure, le fichier
     source de la dépendance (zip de module Go, archive npm) doit être présent
     dans la fermeture, sinon ERROR.

Sortie : prédicat https://supply-chain.example/licences/v1 (lu par la porte du
banc C : violations.error). Code de sortie 1 s'il y a au moins une ERROR.

Usage : licences.py --sbom sbom.json --policy policy.json --spdx licenses.json
          [--exceptions exceptions.json] [--curations curations.json] [--closure DIR]
"""
import argparse
import fnmatch
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "07a-sbom-grype"))
from sbom_merge import key  # noqa: E402  clé PURL normalisée, partagée avec la brique 07a

RANK = {"allow": 0, "warn": 1, "deny": 2}
TOKEN = re.compile(r"\s*(\(|\)|[A-Za-z0-9.\-+:]+)")


class Invalid(Exception):
    pass


def parse(expr):
    """Arbre d'une expression SPDX : ("lic", id, exception) | ("and"|"or", [fils])."""
    tokens = TOKEN.findall(expr)
    if "".join(tokens) != re.sub(r"\s+", "", expr):
        raise Invalid(f"caractères invalides dans « {expr} »")
    pos = 0

    def peek():
        return tokens[pos] if pos < len(tokens) else None

    def take():
        nonlocal pos
        pos += 1
        return tokens[pos - 1]

    def binary(op, sub):
        items = [sub()]
        while peek() and peek().upper() == op:
            take()
            items.append(sub())
        return items[0] if len(items) == 1 else (op.lower(), items)

    def atom():
        t = peek()
        if t is None:
            raise Invalid(f"expression incomplète : « {expr} »")
        if t == "(":
            take()
            node = binary("OR", lambda: binary("AND", atom))
            if peek() != ")":
                raise Invalid(f"parenthèse non fermée : « {expr} »")
            take()
            return node
        if t == ")" or t.upper() in ("AND", "OR", "WITH"):
            raise Invalid(f"opérande attendu, « {t} » trouvé : « {expr} »")
        lic, exc = take(), None
        if peek() and peek().upper() == "WITH":
            take()
            if peek() is None:
                raise Invalid(f"exception manquante après WITH : « {expr} »")
            exc = take()
        return ("lic", lic, exc)

    tree = binary("OR", lambda: binary("AND", atom))
    if pos != len(tokens):
        raise Invalid(f"jeton inattendu « {tokens[pos]} » : « {expr} »")
    return tree


def canonical(tree, ids, exceptions, refs):
    """Valide et normalise la casse des identifiants ; renvoie l'arbre normalisé."""
    if tree[0] == "lic":
        _, lic, exc = tree
        plus = lic.endswith("+")
        base = lic[:-1] if plus else lic
        if base.startswith(("LicenseRef-", "DocumentRef-")):
            if base not in refs:
                raise Invalid(f"{base} non autorisé par la politique")
            name = base
        elif base.lower() in ids:
            name = ids[base.lower()]
        else:
            raise Invalid(f"identifiant SPDX inconnu : {base}")
        if exc is not None:
            if exc.lower() not in exceptions:
                raise Invalid(f"exception SPDX inconnue : {exc}")
            exc = exceptions[exc.lower()]
        return ("lic", name + ("+" if plus else ""), exc)
    return (tree[0], [canonical(t, ids, exceptions, refs) for t in tree[1]])


def render(tree, top=True):
    if tree[0] == "lic":
        return tree[1] + (f" WITH {tree[2]}" if tree[2] else "")
    s = f" {tree[0].upper()} ".join(render(t, False) for t in tree[1])
    return s if top else f"({s})"


def classify(lic, policy):
    for verdict in ("deny", "warn", "allow"):  # le plus strict l'emporte en cas de double motif
        if any(fnmatch.fnmatchcase(lic, p) for p in policy.get(verdict, [])):
            return verdict
    return None


def evaluate(tree, policy):
    """(verdict, licences retenues) : OR → branche la plus favorable, AND → la pire."""
    if tree[0] == "lic":
        lic = tree[1].rstrip("+")
        return classify(lic, policy) or "unknown", [lic]
    results = [evaluate(t, policy) for t in tree[1]]
    order = lambda r: RANK.get(r[0], 3)
    if tree[0] == "or":
        return min(results, key=order)
    worst = max(results, key=order)
    return worst[0], [l for r in results for l in r[1]]


def declared(component, valid):
    """Expressions déclarées dans le SBOM, et entrées non SPDX ignorées.

    Une expression (champ `expression`) est gardée telle quelle, même invalide :
    la validation la signalera. Un `id` ou un `name` n'est gardé que s'il est
    une expression SPDX valide ; sinon (texte libre, empreinte d'un fichier de
    licence non reconnu…) il est ignoré et signalé.
    """
    exprs, ignored = [], []
    for entry in component.get("licenses") or []:
        if entry.get("expression"):
            exprs.append(entry["expression"])
            continue
        lic = entry.get("license") or {}
        value = lic.get("id") or lic.get("name") or ""
        if value and valid(value):
            exprs.append(value)
        elif value:
            ignored.append(value)
    return sorted(set(exprs)), ignored


def closure_file(purl, closure):
    """Fichier source de la dépendance dans la fermeture Hermeto, ou None."""
    k = key(purl)
    if k is None:
        return None
    ptype, name, version = k
    if ptype == "golang":
        escaped = re.sub(r"[A-Z]", lambda m: "!" + m.group(0).lower(), name)
        f = closure / "deps/gomod/pkg/mod/cache/download" / escaped / "@v" / f"{version}.zip"
    elif ptype == "npm":
        f = closure / "deps/npm" / f"{name.split('/')[-1]}-{version}.tgz"
    else:
        return None
    return f if f.is_file() else None


def run(sbom, policy, spdx, exceptions, curations, closure):
    ids = {l["licenseId"].lower(): l["licenseId"] for l in spdx["licenses"]}
    excs = {e["licenseExceptionId"].lower(): e["licenseExceptionId"] for e in exceptions.get("exceptions", [])}
    refs = set(policy.get("licenseRefs", []))
    cur = {key(c["purl"]): c for c in curations}

    def valid(expr):
        try:
            canonical(parse(expr), ids, excs, refs)
            return True
        except Invalid:
            return False

    out = []
    for c in sbom.get("components", []):
        purl = c.get("purl") or ""
        if not purl or c.get("type") == "file":  # fichiers inventoriés par Syft, pas des dépendances
            continue
        if purl.split(":", 1)[-1].split("/", 1)[0] in policy.get("excludePurlTypes", []):
            continue
        item = {"purl": purl, "source": "sbom", "reasons": []}
        k = key(purl)
        if k in cur:
            item.update(source="curation", expression=cur[k]["expression"], reviewer=cur[k].get("reviewer"))
        else:
            exprs, ignored = declared(c, valid)
            item["reasons"] += [f"entrée de licence non SPDX ignorée : {x[:40]}" for x in ignored]
            if len(exprs) > 1:
                exprs = [f"({e})" if " " in e else e for e in exprs]
            item["expression"] = " AND ".join(exprs) or "NOASSERTION"
        verdict = "error"
        if item["expression"] == "NOASSERTION":
            item["reasons"].append("NOASSERTION : curation nécessaire")
        else:
            try:
                tree = canonical(parse(item["expression"]), ids, excs, refs)
                item["expression"] = render(tree)
                v, chosen = evaluate(tree, policy)
                verdict = {"allow": "ok", "warn": "warning", "deny": "error"}.get(v, "error")
                if v == "unknown":
                    item["reasons"].append(f"licence absente de la politique : {', '.join(chosen)}")
                elif v != "allow":
                    item["reasons"].append(f"{v} : {', '.join(chosen)}")
                needs = [l for l in chosen if any(fnmatch.fnmatchcase(l, p) for p in policy.get("sourceObligation", []))]
                if needs:
                    item["sourceObligation"] = needs
                    if closure is not None:
                        f = closure_file(purl, closure)
                        if f is None:
                            verdict = "error"
                            item["reasons"].append("source à fournir introuvable dans la fermeture")
                        else:
                            item["sourceFile"] = str(f.relative_to(closure))
            except Invalid as e:
                item["reasons"].append(f"expression invalide : {e}")
                item["invalid"] = True
        if verdict == "ok" and item["reasons"]:
            verdict = "warning"
        item["verdict"] = verdict
        out.append(item)
    count = lambda v: sum(1 for i in out if i["verdict"] == v)
    return {
        "policy": {"version": policy.get("version"), "sha256": hashlib.sha256(json.dumps(policy, sort_keys=True).encode()).hexdigest()},
        "spdxListVersion": spdx.get("licenseListVersion"),
        "violations": {"error": count("error"), "warning": count("warning")},
        "noassertion": sum(1 for i in out if i["expression"] == "NOASSERTION"),
        "invalid": sum(1 for i in out if i.get("invalid")),
        "sourceObligations": [{"purl": i["purl"], "file": i.get("sourceFile")} for i in out if i.get("sourceObligation")],
        "components": sorted(out, key=lambda i: i["purl"]),
    }


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--sbom", required=True)
    p.add_argument("--policy", required=True)
    p.add_argument("--spdx", required=True, help="licenses.json de la liste SPDX")
    p.add_argument("--exceptions", help="exceptions.json de la liste SPDX")
    p.add_argument("--curations")
    p.add_argument("--closure", type=Path, help="fermeture Hermeto, pour les obligations de sources")
    a = p.parse_args(argv)
    load = lambda f, default: json.load(open(f)) if f else default
    pred = run(load(a.sbom, {}), load(a.policy, {}), load(a.spdx, {}), load(a.exceptions, {}),
               load(a.curations, []), a.closure)
    json.dump(pred, sys.stdout, indent=2, ensure_ascii=False)
    print()
    return 1 if pred["violations"]["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
