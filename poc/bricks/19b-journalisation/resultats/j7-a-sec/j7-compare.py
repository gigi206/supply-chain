"""J7 à sec : compare le rendu helm actuel au rendu avec l'export, sans afficher de Secret ni de certificat.
Usage : python3 -I j7-compare.py <rendu-actuel.yaml> <rendu-j7.yaml> <cilium-config vivant .json>"""
import difflib
import json
import re
import sys


a_f, b_f, live_f = sys.argv[1:4]


def docs(f):
    out = {}
    for d in (json.loads(l) for l in open(f, encoding="utf-8") if l.strip()):
        if not d:
            continue
        k = (d.get("kind"), d["metadata"].get("namespace", ""), d["metadata"]["name"])
        out[k] = d
    return out


A, B = docs(a_f), docs(b_f)
sec = [k for k in set(A) | set(B) if k[0] == "Secret"]
print("Secrets du rendu (non comparés, non affichés) :", len(sec))
print("objets ajoutés :", sorted(f"{k[0]}/{k[2]}" for k in set(B) - set(A)))
print("objets retirés :", sorted(f"{k[0]}/{k[2]}" for k in set(A) - set(B)))

# 1. reconstitution : cilium-config rendu contre cilium-config vivant (kubectl get, lecture seule)
live = json.load(open(live_f, encoding="utf-8"))["data"]
cc = A[("ConfigMap", "kube-system", "cilium-config")]["data"]
diff_keys = sorted(k for k in set(live) | set(cc) if str(live.get(k)) != str(cc.get(k)))
print("cilium-config rendu actuel contre vivant : clés", len(cc), "/", len(live), "; différentes :", diff_keys)

# 2. ce que l'export change, hors Secrets
MASQUE = re.compile(r"jeton|token|BEGIN|cert|\.key", re.I)
for k in sorted(set(A) & set(B)):
    if k[0] == "Secret":
        continue
    a = json.dumps(A[k], sort_keys=True, indent=1, ensure_ascii=False).splitlines()
    b = json.dumps(B[k], sort_keys=True, indent=1, ensure_ascii=False).splitlines()
    d = [l for l in difflib.unified_diff(a, b, lineterm="", n=0) if not l.startswith(("---", "+++"))]
    if d:
        print(f"== {k[0]}/{k[2]} : {len(d)} lignes de diff")
        for l in d:
            print("   " + ("[ligne masquée]" if MASQUE.search(l) else l))
for k in sorted(set(B) - set(A)):
    if k[0] == "Secret":
        continue
    print(f"== ajouté {k[0]}/{k[2]}")
    for l in json.dumps(B[k], sort_keys=True, indent=1, ensure_ascii=False).splitlines():
        print("   " + ("[ligne masquée]" if MASQUE.search(l) else l))

# 3. hostPath de /var/run/cilium dans le DaemonSet
ds = B[("DaemonSet", "kube-system", "cilium")]["spec"]["template"]["spec"]
vols = {v["name"]: v.get("hostPath", {}).get("path") for v in ds["volumes"]}
for c in ds["containers"]:
    for m in c.get("volumeMounts", []):
        if m["mountPath"].startswith("/var/run/cilium"):
            print("montage", c["name"], m["mountPath"], "<- volume", m["name"], "hostPath", vols.get(m["name"]))
