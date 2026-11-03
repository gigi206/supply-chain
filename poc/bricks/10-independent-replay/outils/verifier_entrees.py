# Brique 10, R3, DANS LA VM du domaine de replay : vérifie ce que l'hôte a transporté dans ~/r3, sans aucun accès à Zot ni à
# Forgejo. Arguments : image (dépôt@sha256:…), invocationId du PipelineRun rejoué, identifiant de la TSA (racine de confiance).
#   1. racine de confiance de la TSA construite ici depuis tsa-chaine.pem (cosign trusted-root create) ;
#   2. chaque bundle horodaté vérifié hors réseau (clé de Chains, sujet = image, jeton RFC 3161) ; la provenance est extraite
#      du bundle vérifié de l'invocationId demandé, jamais du transport ;
#   3. politique, section 1 ; 4. digests des entrées transportées et commit (git) ; 5. recette (Dockerfile contrôlé par le
#      sha256 que la tâche contient, options de buildctl) ; 6. version de Go de l'image de build déclarée ; 7. heures du build.
# Sorties : provenance.json et recette/ (Dockerfile, buildctl.txt, tache.json) dans ~/r3. Code de sortie 1 s'il y a au moins un KO.
import base64
import glob
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tarfile

IMAGE, INVOCATION, URL_TSA = sys.argv[1:4]
SUJET = IMAGE.split("@sha256:")[1]
L = "layout"
ko = 0


def est_entree(uri, nom):  # la fermeture de la plateforme (F2 de la 03) est rangée sous builds/fermetures/<application>
    return uri.endswith(nom) or (nom == "fermeture" and "/fermetures/" in uri)


def sh(*args, entree=None):
    return subprocess.run(args, capture_output=True, input=entree, check=False)


def verdict(cond, msg):
    global ko
    print(("OK   " if cond else "KO   ") + msg, flush=True)
    ko += 0 if cond else 1


def manifeste(tag):  # octets du manifeste d'une étiquette du layout (oras), et son sha256
    r = sh("oras", "manifest", "fetch", "--oci-layout", f"{L}:{tag}")
    return r.stdout, hashlib.sha256(r.stdout).hexdigest()


def blob(digest):
    return sh("oras", "blob", "fetch", "--oci-layout", f"{L}@{digest}", "--output", "-").stdout


os.makedirs("travail", exist_ok=True)
os.makedirs("recette", exist_ok=True)
print("## ancres de confiance (copiées depuis le dépôt)")
for f in ("chains.pub", "tsa-chaine.pem"):
    print(f"  {hashlib.sha256(open(f, 'rb').read()).hexdigest()}  {f}")
r = sh("cosign", "trusted-root", "create", f"--tsa=url={URL_TSA},certificate-chain=tsa-chaine.pem", "--out", "travail/racine.json")
verdict(r.returncode == 0, "racine de confiance de la TSA construite dans la VM")

_, d = manifeste("sujet")
verdict(d == SUJET, f"digest du sujet transporté : {d}")

print("## bundles horodatés : vérifiés hors réseau (clé de Chains, sujet, jeton de la TSA)")
index = json.load(open(f"{L}/index.json"))
tags = sorted(m["annotations"]["org.opencontainers.image.ref.name"] for m in index["manifests"]
              if m["annotations"]["org.opencontainers.image.ref.name"].startswith("bundle-"))
provenance, heure_tsa, n_ok = None, None, 0
for t in tags:
    m, _ = manifeste(t)
    chemin = f"travail/{t}.json"
    open(chemin, "wb").write(blob(json.loads(m)["layers"][0]["digest"]))
    r = sh("cosign", "verify-blob-attestation", "--bundle", chemin, "--new-bundle-format", "--key", "chains.pub",
           "--insecure-ignore-tlog", "--type", "https://slsa.dev/provenance/v1", "--digest", SUJET, "--digestAlg", "sha256",
           "--use-signed-timestamps", "--trusted-root", "travail/racine.json")
    if r.returncode != 0:
        print(f"REFUS {t} : {next((l for l in r.stderr.decode().splitlines() if l.startswith('Error')), '?')[:160]}")
        continue
    n_ok += 1
    b = json.load(open(chemin))
    enonce = json.loads(base64.b64decode(b["dsseEnvelope"]["payload"]))
    inv = enonce["predicate"]["runDetails"]["metadata"].get("invocationId")
    jeton = base64.b64decode(b["verificationMaterial"]["timestampVerificationData"]["rfc3161Timestamps"][0]["signedTimestamp"])
    open("travail/jeton.der", "wb").write(jeton)
    # signedTimestamp contient la réponse complète de la TSA (TimeStampResp), pas seulement le jeton (mesuré au 1er passage)
    texte = sh("openssl", "ts", "-reply", "-in", "travail/jeton.der", "-text").stdout.decode()
    heure = next((l.split(":", 1)[1].strip() for l in texte.splitlines() if l.startswith("Time stamp")), "?")
    print(f"OK   {t} : vérifié ; invocationId {inv} ; jeton de la TSA : {heure}")
    if inv == INVOCATION:
        provenance, heure_tsa = enonce, heure
print(f"bundles vérifiés : {n_ok} sur {len(tags)}")
verdict(provenance is not None, f"provenance {INVOCATION} extraite d'un bundle vérifié")
if provenance is None:
    sys.exit(1)
json.dump(provenance, open("provenance.json", "w"), indent=1)

print("## politique, section 1 (provenance vérifiée)")
p = provenance["predicate"]
verdict(provenance["_type"] == "https://in-toto.io/Statement/v1", f"_type {provenance['_type']}")
verdict(provenance["predicateType"] == "https://slsa.dev/provenance/v1", f"predicateType {provenance['predicateType']}")
verdict(p["runDetails"]["builder"]["id"] == "https://supply-chain.example/builders/tekton-chains@v1",
        f"builder.id {p['runDetails']['builder']['id']}")
verdict(p["buildDefinition"]["buildType"] == "https://tekton.dev/chains/v2/slsa-tekton", f"buildType {p['buildDefinition']['buildType']}")
verdict(any(s["digest"].get("sha256") == SUJET for s in provenance["subject"]), "sujet = image rejouée")
attendus = {}
for nom in ("construire-image", "fermeture", "web-dist", "builder-go-voie-d", "sample-app.git"):
    d = [x for x in p["buildDefinition"]["resolvedDependencies"] if est_entree(x.get("uri", ""), nom)]
    verdict(len(d) == 1, f"entrée {nom} déclarée : {d[0]['digest'] if d else 'absente'}")
    if d:
        attendus[nom] = list(d[0]["digest"].values())[0]

print("## digests des entrées transportées, recalculés")
for nom in ("construire-image", "fermeture", "web-dist", "builder-go-voie-d"):
    _, d = manifeste(nom)
    verdict(d == attendus.get(nom), f"{nom} : transporté {d}")

print("## commit")
# le bundle ne porte que refs/heads/main, sans HEAD : le clone n'a que origin/main (mesuré au 1er passage)
sh("rm", "-rf", "src")
sh("git", "clone", "-q", "--no-checkout", "sample-app.bundle", "src")
r = sh("git", "-C", "src", "bundle", "verify", "-q", "../sample-app.bundle")
verdict(r.returncode == 0, "bundle git cohérent (git bundle verify, dans le dépôt cloné)")
c = sh("git", "-C", "src", "rev-parse", "refs/remotes/origin/main").stdout.decode().strip()
verdict(c == attendus.get("sample-app.git"), f"commit de main {c}")
r = sh("git", "-C", "src", "checkout", "-q", "--detach", c)
verdict(r.returncode == 0 and sh("git", "-C", "src", "status", "--porcelain").stdout == b"", "arbre de travail extrait au commit déclaré, propre")

print("## recette (bundle construire-image vérifié)")
m, _ = manifeste("construire-image")
with tarfile.open(fileobj=io.BytesIO(blob(json.loads(m)["layers"][0]["digest"]))) as tf:
    membres = [x for x in tf.getmembers() if x.isfile()]
    tache_brute = tf.extractfile(membres[0]).read().decode()
open("recette/tache.json", "w").write(tache_brute)
# la tâche est stockée en JSON (mesuré au 1er passage) : on cherche dans le script de chaque étape
tache = "\n".join(e.get("script", "") for e in json.loads(tache_brute)["spec"]["steps"])
bloc = re.search(r"cat > /tmp/df/Dockerfile <<'FIN'\n(.*?)\n *FIN\n", tache, re.S)
lignes = bloc.group(1).split("\n") if bloc else []
retrait = min((len(x) - len(x.lstrip()) for x in lignes if x.strip()), default=0)
dockerfile = "\n".join(x[retrait:] for x in lignes) + "\n"
open("recette/Dockerfile", "w").write(dockerfile)
controle = re.search(r'sha256sum < /tmp/df/Dockerfile \| cut -c1-64\)" = ([0-9a-f]{64})', tache)
h = hashlib.sha256(dockerfile.encode()).hexdigest()
verdict(bool(controle) and controle.group(1) == h, f"Dockerfile : sha256 {h}, contrôlé par la tâche : {controle.group(1) if controle else 'absent'}")
b = re.search(r"(buildctl --addr \S+ build .*?rewrite-timestamp=true)", tache, re.S)
open("recette/buildctl.txt", "w").write(b.group(1) if b else "")
verdict(bool(b), "options de buildctl : " + (" ".join(b.group(1).replace("\\\n", " ").split()) if b else "absentes"))
print("RUN :", [x.strip() for x in dockerfile.splitlines() if x.strip().startswith("RUN")])

print("## version de Go de l'image de build déclarée (vérifiée)")
m, _ = manifeste("builder-go-voie-d")
with tarfile.open(fileobj=io.BytesIO(blob(json.loads(m)["layers"][0]["digest"]))) as tf:
    v = next((tf.extractfile(x).read().decode().splitlines()[0] for x in tf.getmembers() if x.name.endswith("go/VERSION")), "?")
locale = sh("/usr/local/go/bin/go", "version").stdout.decode().split()[2]
verdict(v == locale, f"{v} ; toolchain du domaine : {locale}")

print("## heures du build")
print(f"finishedOn signé : {p['runDetails']['metadata']['finishedOn']} ; jeton de la TSA : {heure_tsa}")
for f in glob.glob("travail/*.json") + ["travail/jeton.der"]:
    os.remove(f)
print(f"## bilan : {ko} KO")
sys.exit(1 if ko else 0)
