# Brique 06, S6b (contrôle 6 du deb), DANS LA VM sc-replay : vérifie ce que l'hôte a transporté dans ~/s6b/r3, sans aucun
# accès à Zot ni à Forgejo. Modèle : verifier_entrees.py de la brique 10 (R3), adapté au deb.
# Arguments : sujet (dépôt@sha256:…), invocationId retenu (décision 1 du propriétaire du 12/11/2026 : 454728c5), identifiant
# de la TSA (racine de confiance), chroot reconstruit (S6b, étape chroot).
#   1. racine de confiance de la TSA construite ici depuis tsa-chaine.pem ;
#   2. chaque bundle horodaté vérifié hors réseau (clé de Chains, sujet = layout du deb, jeton RFC 3161) ; la provenance est
#      extraite du bundle vérifié de l'invocationId demandé, jamais du transport ;
#   3. politique, section 1 ; 4. digests des entrées transportées ; commit (git) ; 5. recette : lignes clés des tâches
#      preparer-deb et construire-deb, lues dans leurs bundles vérifiés ; 6. version de Go de l'image outils-prefetch déclarée,
#      comparée à la toolchain du domaine ; 7. chroot du domaine rangé comme dans l'image de build déclarée (commande tar de
#      construire-builder), comparé à la couche de cette image ; 8. heures du build.
# Sorties dans ~/s6b/r3 : provenance.json, recette/ (preparer-deb.json, construire-deb.json), verifie.txt (clé=valeur, lu par
# rebuild_deb.sh). Code de sortie 1 s'il y a au moins un KO.
import base64
import glob
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile

SUJET_REF, INVOCATION, URL_TSA, CHROOT = sys.argv[1:5]
SUJET = SUJET_REF.split("@sha256:")[1]
L = "layout"
ko = 0
ENTREES = {  # nom : fin de l'uri dans resolvedDependencies (relevé H1 de S6b)
    "construire-deb": "tekton/tasks/construire-deb",
    "preparer-deb": "tekton/tasks/preparer-deb",
    "sbuild-debian13": "builds/builders/sbuild-debian13",
    "outils-prefetch": "plateforme/outils-prefetch",
    "fermeture-deb": "builds/fermetures/sample-app-deb",
    "fermeture-sources": "builds/fermetures/sample-app-sources",
    "packaging": "entrees/sample-app/packaging-deb",
    "sample-app.git": "workspace/sample-app.git",
}


def sh(*args, entree=None):
    return subprocess.run(args, capture_output=True, input=entree, check=False)


def verdict(cond, msg):
    global ko
    print(("OK   " if cond else "KO   ") + msg, flush=True)
    ko += 0 if cond else 1


def manifeste(tag):
    r = sh("oras", "manifest", "fetch", "--oci-layout", f"{L}:{tag}")
    return r.stdout, hashlib.sha256(r.stdout).hexdigest()


def blob(digest):
    return sh("oras", "blob", "fetch", "--oci-layout", f"{L}@{digest}", "--output", "-").stdout


def tache(tag):  # tâche Tekton d'un bundle (premier fichier de la première couche), et le texte de ses scripts
    m, _ = manifeste(tag)
    with tarfile.open(fileobj=io.BytesIO(blob(json.loads(m)["layers"][0]["digest"]))) as tf:
        brut = tf.extractfile([x for x in tf.getmembers() if x.isfile()][0]).read().decode()
    return brut, "\n".join(e.get("script", "") for e in json.loads(brut)["spec"]["steps"])


os.makedirs("travail", exist_ok=True)
os.makedirs("recette", exist_ok=True)
sortie = {}
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
verdict(any(s["digest"].get("sha256") == SUJET for s in provenance["subject"]), "sujet = layout du deb rejoué")
attendus = {}
for nom, fin in ENTREES.items():
    d = [x for x in p["buildDefinition"]["resolvedDependencies"] if x.get("uri", "").endswith(fin)]
    verdict(len(d) == 1, f"entrée {nom} déclarée : {d[0]['digest'] if d else 'absente'}")
    if d:
        attendus[nom] = list(d[0]["digest"].values())[0]

print("## digests des entrées transportées, recalculés")
for nom in ("construire-deb", "preparer-deb", "outils-prefetch", "fermeture-deb", "fermeture-sources", "packaging"):
    _, d = manifeste(nom)
    verdict(d == attendus.get(nom), f"{nom} : transporté {d}")
mb = open("sbuild-debian13.manifeste.json", "rb").read()
verdict(hashlib.sha256(mb).hexdigest() == attendus.get("sbuild-debian13"),
        f"sbuild-debian13 : manifeste transporté seul, {hashlib.sha256(mb).hexdigest()}")

print("## commit")
shutil.rmtree("src", ignore_errors=True)
sh("git", "clone", "-q", "--no-checkout", "sample-app.bundle", "src")
r = sh("git", "-C", "src", "bundle", "verify", "-q", "../sample-app.bundle")
verdict(r.returncode == 0, "bundle git cohérent (git bundle verify, dans le dépôt cloné)")
c = attendus.get("sample-app.git", "")
verdict(sh("git", "-C", "src", "cat-file", "-e", f"{c}^{{commit}}").returncode == 0, f"commit déclaré présent dans le bundle : {c}")
print(f"main du bundle : {sh('git', '-C', 'src', 'rev-parse', 'refs/remotes/origin/main').stdout.decode().strip()}")
r = sh("git", "-C", "src", "checkout", "-q", "--detach", c)
verdict(r.returncode == 0 and sh("git", "-C", "src", "status", "--porcelain").stdout == b"", "arbre de travail extrait au commit déclaré, propre")
sortie["commit"] = c

print("## recette (bundles preparer-deb et construire-deb vérifiés)")
MOTIFS = {
    "preparer-deb": [
        'git -C /tmp/depot archive --format=tar HEAD | tar -xf - -C "$e/src"',
        'oras pull --no-tty --ca-file /etc/ca-poc/ca.crt -o "$e/fermeture" "$FERMETURE_DEB"',
        'oras pull --no-tty --ca-file /etc/ca-poc/ca.crt -o "$e/sources" "$FERMETURE_SOURCES"',
        'oras pull --no-tty --ca-file /etc/ca-poc/ca.crt -o "$e/packaging" "$PACKAGING"',
        'export HOME=/tmp GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOFLAGS=-mod=mod GOMODCACHE=/tmp/gomod GOCACHE=/tmp/gocache CGO_ENABLED=0',
        '(cd "$e/src" && go mod vendor && go mod verify)',
        "calc = 'sha512-' + base64.b64encode(hashlib.sha512(open(a, 'rb').read()).digest()).decode()",
        "t.extractall(dst, members=m, filter='data')",
        'cp -r "$e/packaging/debian" "$e/debian"',
        'chmod 0755 "$e/debian/rules"',
    ],
    "construire-deb": [
        'tar -C /w/src --sort=name --mtime="@$sde" --owner=0 --group=0 --numeric-owner --mode=go-w,a+rX \\\n'
        '  --format=gnu -cf - "$src-$amont" | gzip -n -9 > "/w/src/${src}_$amont.orig.tar.gz"',
        '(cd /w/src && SOURCE_DATE_EPOCH=$sde dpkg-source -q -b "$src-$amont" > /dev/null)',
        'sbuild --chroot-mode=unshare --chroot=/opt/sbuild/trixie-amd64.tar --dist=trixie --arch=amd64 --no-apt-update --no-apt-upgrade \\\n'
        '  --no-apt-distupgrade --no-run-lintian --no-run-autopkgtest --no-run-piuparts --no-source-only-changes --build-dir=/w/sortie \\\n'
        '  --extra-package=/w/fermeture \\\n'
        '  "--chroot-setup-commands=truncate -s 0 /etc/apt/sources.list" \\\n'
        '  "$dsc" > /w/sbuild.out 2>&1 || r=$?',
        'tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime=@0 \\\n'
        '  --owner=0 --group=0 --numeric-owner -C /w/cc -cf /w/couche.tar "${deb##*/}"',
        """cfg=$(blob '{"architecture":"amd64","os":"linux","rootfs":{"type":"layers","diff_ids":["sha256:'"$l"'"]}}')""",
    ],
}
for nom, motifs in MOTIFS.items():
    brut, texte = tache(nom)
    open(f"recette/{nom}.json", "w").write(brut)
    # les scripts des tâches sont indentés dans le YAML d'origine, mais stockés sans indentation commune dans le bundle :
    # on compare après avoir retiré l'indentation de chaque ligne
    plat = "\n".join(x.strip() for x in texte.splitlines())
    for i, motif in enumerate(motifs, 1):
        mplat = "\n".join(x.strip() for x in motif.splitlines())
        verdict(mplat in plat, f"recette {nom}, ligne clé {i} : {' '.join(motif.split())[:110]}")

print("## version de Go de l'image outils-prefetch déclarée (vérifiée)")
m, _ = manifeste("outils-prefetch")
v = "?"
# corrigé avant tout lancement, après b50b6ad : tout fichier VERSION dont la première ligne commence par « go1. », chemin journalisé
# (le chemin d'installation de Go dans outils-prefetch n'est pas relevé)
for c in json.loads(m)["layers"]:
    with tarfile.open(fileobj=io.BytesIO(blob(c["digest"]))) as tf:
        for x in tf.getmembers():
            if x.isfile() and x.name.rsplit("/", 1)[-1] == "VERSION" and x.size < 4096:
                l = (tf.extractfile(x).read().decode(errors="replace").splitlines() or [""])[0]
                if l.startswith("go1."):
                    print(f"  {x.name} : {l}")
                    v = l
locale = sh("/usr/local/go/bin/go", "version").stdout.decode().split()[2]
verdict(v == locale, f"{v} ; toolchain du domaine : {locale}")

print("## chroot du domaine, rangé comme dans l'image de build déclarée (commande tar de construire-builder)")
couches = json.loads(mb)["layers"]
print(f"image de build : {len(couches)} couches ; couche du chroot (2e) {couches[-1]['digest']} ({couches[-1]['size']} octets)")
h = hashlib.sha256(open(CHROOT, "rb").read()).hexdigest()
print(f"chroot du domaine : {CHROOT}, sha256 {h}")
shutil.rmtree("travail/cc", ignore_errors=True)
os.makedirs("travail/cc/opt/sbuild")
for d in ("travail/cc/opt", "travail/cc/opt/sbuild"):  # modes du pod de la plateforme (umask 022), pas de l'umask du compte :
    os.chmod(d, 0o755)                              # en 0775, la couche diffère (mesuré sur l'hôte le 12/11/2026)
shutil.copyfile(CHROOT, "travail/cc/opt/sbuild/trixie-amd64.tar")
os.chmod("travail/cc/opt/sbuild/trixie-amd64.tar", 0o644)
r = subprocess.run("tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime=@0 "
                   "--owner=0 --group=0 --numeric-owner -C travail/cc -cf - opt | sha256sum | cut -c1-64",
                   shell=True, capture_output=True, check=False)
dc = r.stdout.decode().strip()
verdict("sha256:" + dc == couches[-1]["digest"], f"couche du chroot du domaine : sha256:{dc}, égale à celle de l'image de build déclarée")
shutil.rmtree("travail/cc", ignore_errors=True)
sortie["chroot_sha256"] = h

print("## heures du build")
print(f"finishedOn signé : {p['runDetails']['metadata']['finishedOn']} ; jeton de la TSA : {heure_tsa}")
sortie["finishedOn"] = p["runDetails"]["metadata"]["finishedOn"]
for f in glob.glob("travail/*.json") + ["travail/jeton.der"]:
    os.remove(f)
sortie["ko"] = ko
open("verifie.txt", "w").write("".join(f"{k}={v}\n" for k, v in sortie.items()))
print(f"## bilan : {ko} KO")
sys.exit(1 if ko else 0)
