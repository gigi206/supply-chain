# P1 : sortie de v0.29.9 sur les objets du cluster contre la provenance signée, aux champs postérieurs à la signature près.
import base64, json, sys
from pathlib import Path
B = Path.home()/".cache/supply-chain-poc/chains-v0300/sorties"
def net(o):
    o = json.loads(json.dumps(o)); o.pop("kind", None); o.pop("apiVersion", None)
    m = o.get("metadata", {})
    for k in ("resourceVersion", "managedFields", "finalizers"): m.pop(k, None)
    m["annotations"] = {k: v for k, v in m.get("annotations", {}).items() if not k.startswith("chains.tekton.dev/")}
    return o
def norm(p, brut):
    p = json.loads(json.dumps(p)); bd = p["predicate"]["buildDefinition"]
    ip = bd.get("internalParameters", {})
    for k, v in list(ip.items()):
        if isinstance(v, dict) and k == "annotations": ip[k] = {a: b for a, b in v.items() if not a.startswith("chains.tekton.dev/")}
    for d in bd["resolvedDependencies"]:
        if "content" in d:
            t = json.loads(base64.b64decode(d["content"])); brut.append(t); d["content"] = net(t) if "metadata" in t else t
    return p
for n in sys.argv[1:]:
    a, b = (json.loads((B/f"{n}.{x}.json").read_text()) for x in ("signe", "29"))
    ba, bb = [], []
    na, nb = norm(a, ba), norm(b, bb)
    print(("ÉGAL " if na == nb else "DIFFÉRENT "), n, "; contenus", len(ba), len(bb))
    for x, y in zip(ba, bb):
        if "metadata" in x: print("   champs de plus dans l'objet du cluster :", sorted(set(y)-set(x)), "métadonnées", sorted(set(y["metadata"])-set(x["metadata"])), "annotations", sorted(set(y["metadata"].get("annotations",{}))-set(x["metadata"].get("annotations",{}))), "| moins :", sorted(set(x["metadata"])-set(y["metadata"])))
