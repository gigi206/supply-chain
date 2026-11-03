#!/usr/bin/env python3
# Brique 10, R5, DANS LA VM (dossier ~/r5, sous unshare -rn) : énoncé de la VSA, construit seulement d'après
# ce que la VM revérifie ici (bundle horodaté de la provenance : clé de Chains, sujet, jeton de la TSA) et le résultat de R4
# (~/r4/resultat.txt) ; refus (code 1, aucun énoncé) si une condition de la politique manque. Signature : par l'appelant.
# La racine de la TSA et le bundle sont refaits ici, dans travail/ : verifier_entrees.py vide ~/r3/travail en fin de R3.
# Usage : python3 -I vsa.py <registre> <dépôt@sha256:…> <invocationId> <uri de la politique> <identifiant de la TSA>
import base64, datetime, hashlib, json, os, subprocess, sys

REG, IMAGE, INVOCATION, POLITIQUE_URI, URL_TSA = sys.argv[1:6]
DEPOT, SUJET = IMAGE.split("@")
R3, R4 = "/home/replay/r3", "/home/replay/r4"
ko = []

def verdict(ok, texte):
    print(("OK   " if ok else "KO   ") + texte)
    if not ok:
        ko.append(texte)

def sha256(chemin):
    return hashlib.sha256(open(chemin, "rb").read()).hexdigest()

def heure(texte):
    return datetime.datetime.strptime(texte, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)

def sh(*args):
    return subprocess.run(args, capture_output=True, check=False)

def couche(ref):   # octets de la première couche d'une étiquette du layout de R3 (lecture seule), et digest du manifeste
    m = sh("oras", "manifest", "fetch", "--oci-layout", f"{R3}/layout:{ref}").stdout
    d = json.loads(m)["layers"][0]["digest"]
    return sh("oras", "blob", "fetch", "--oci-layout", f"{R3}/layout@{d}", "--output", "-").stdout, "sha256:" + hashlib.sha256(m).hexdigest()

print("## résultat de R4 (~/r4/resultat.txt)")
r4 = dict(l.split("=", 1) for l in open(f"{R4}/resultat.txt").read().splitlines() if "=" in l)
verdict(r4.get("verdict") == "PASSED", f"verdict de R4 : {r4.get('verdict')}")
verdict(r4.get("image_reconstruite", "").split(" ")[0] == SUJET, f"image reconstruite : {r4.get('image_reconstruite')}")

print("## provenance : bundle horodaté de l'invocation, revérifié ici")
os.makedirs("travail", exist_ok=True)
r = sh("cosign", "trusted-root", "create", f"--tsa=url={URL_TSA},certificate-chain={R3}/tsa-chaine.pem", "--out", "travail/racine.json")
verdict(r.returncode == 0, "racine de confiance de la TSA construite ici")
refs = sorted(m["annotations"]["org.opencontainers.image.ref.name"] for m in json.load(open(f"{R3}/layout/index.json"))["manifests"]
              if m["annotations"]["org.opencontainers.image.ref.name"].startswith("bundle-"))
candidats = []
for ref in refs:
    octets, mb = couche(ref)
    e = json.loads(base64.b64decode(json.loads(octets)["dsseEnvelope"]["payload"]))
    if e["predicate"]["runDetails"]["metadata"].get("invocationId") == INVOCATION:
        candidats.append((ref, mb, octets, e))
verdict(len(candidats) == 1, f"bundles de l'invocation {INVOCATION} parmi {len(refs)} : {[c[0] for c in candidats]}")
if len(candidats) != 1:
    sys.exit(1)
ref, mb, octets, enonce = candidats[0]
bundle = f"travail/{ref}.json"
open(bundle, "wb").write(octets)
r = subprocess.run(["cosign", "verify-blob-attestation", "--bundle", bundle, "--new-bundle-format", "--key", f"{R3}/chains.pub",
                    "--insecure-ignore-tlog", "--type", "https://slsa.dev/provenance/v1", "--digest", SUJET.split(":")[1],
                    "--digestAlg", "sha256", "--use-signed-timestamps", "--trusted-root", "travail/racine.json"],
                   capture_output=True)
verdict(r.returncode == 0, "signature de Chains et jeton de la TSA du bundle (cosign verify-blob-attestation)")
verdict(enonce == json.load(open(f"{R3}/provenance.json")), "énoncé identique à la provenance vérifiée en R3")
p = enonce["predicate"]

print("## politique, sections 1 et 3 (niveaux et délai)")
verdict(enonce["_type"] == "https://in-toto.io/Statement/v1" and enonce["predicateType"] == "https://slsa.dev/provenance/v1",
        "_type et predicateType")
verdict(p["runDetails"]["builder"]["id"] == "https://supply-chain.example/builders/tekton-chains@v1", "builder.id")
verdict(p["buildDefinition"]["buildType"] == "https://tekton.dev/chains/v2/slsa-tekton", "buildType")
verdict(["sha256:" + s["digest"]["sha256"] for s in enonce["subject"]] == [SUJET], "sujet de la provenance")
fini, verifie = heure(p["runDetails"]["metadata"]["finishedOn"]), heure(r4["fin_image"])
verdict(verifie - fini >= datetime.timedelta(hours=24), f"timeVerified {r4['fin_image']} au moins 24 h après finishedOn")

if ko:
    print(f"REFUS : {len(ko)} condition(s) manquante(s), aucun énoncé écrit")
    sys.exit(1)

vsa = {
    "_type": "https://in-toto.io/Statement/v1",
    "subject": [{"name": f"{REG}/{DEPOT}", "digest": {"sha256": SUJET.split(":")[1]}}],
    "predicateType": "https://slsa.dev/verification_summary/v1",
    "predicate": {
        "verifier": {"id": "https://supply-chain.example/verifiers/replay-poc-administrateur-unique@v1",
                     "version": {"buildkit": r4["buildkit"], "go": open("/usr/local/go/VERSION").readline().strip(),
                                 "verifier_entrees.py": sha256(f"{R3}/verifier_entrees.py"), "rebuild.sh": sha256(f"{R4}/rebuild.sh"),
                                 "vsa.py": sha256("vsa.py")}},
        "timeVerified": r4["fin_image"],
        "resourceUri": f"oci://{REG}/{IMAGE}",
        "policy": {"uri": POLITIQUE_URI, "digest": {"sha256": sha256("politique-replay.md")}},
        "inputAttestations": [{"uri": f"oci://{REG}/horodatage/bundles@{mb}", "digest": {"sha256": mb.split(":")[1]}}],
        "verificationResult": "PASSED",
        "verifiedLevels": ["SLSA_BUILD_LEVEL_3", "POC_REPLAY_BIT_IDENTIQUE"],
        "slsaVersion": "1.2",
    },
}
json.dump(vsa, open("enonce.json", "w"), indent=1)
print(json.dumps(vsa["predicate"], indent=1))
