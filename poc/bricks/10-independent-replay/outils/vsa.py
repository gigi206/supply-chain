#!/usr/bin/env python3
# Brique 10, R5, DANS LA VM : énoncé de la VSA, construit seulement d'après
# ce que la VM revérifie ici (bundle horodaté de la provenance : clé de Chains, sujet, jeton de la TSA) et le résultat de R4
# (~/r4/resultat.txt) ; refus (code 1, aucun énoncé) si une condition de la politique manque. Signature : par l'appelant.
# Usage : python3 -I vsa.py <registre> <dépôt@sha256:…> <invocationId> <uri de la politique>
import base64, datetime, glob, hashlib, json, subprocess, sys

REG, IMAGE, INVOCATION, POLITIQUE_URI = sys.argv[1:5]
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

print("## résultat de R4 (~/r4/resultat.txt)")
r4 = dict(l.split("=", 1) for l in open(f"{R4}/resultat.txt").read().splitlines() if "=" in l)
verdict(r4.get("verdict") == "PASSED", f"verdict de R4 : {r4.get('verdict')}")
verdict(r4.get("image_reconstruite", "").split(" ")[0] == SUJET, f"image reconstruite : {r4.get('image_reconstruite')}")

print("## provenance : bundle horodaté de l'invocation, revérifié ici")
bundle, enonce = None, None
for chemin in sorted(glob.glob(f"{R3}/travail/bundle-*.json")):
    b = json.load(open(chemin))
    e = json.loads(base64.b64decode(b["dsseEnvelope"]["payload"]))
    if e["predicate"]["runDetails"]["metadata"].get("invocationId") == INVOCATION:
        bundle, enonce = chemin, e
        break
verdict(bundle is not None, f"bundle de l'invocation {INVOCATION} : {bundle}")
if bundle is None or enonce is None:
    sys.exit(1)
r = subprocess.run(["cosign", "verify-blob-attestation", "--bundle", bundle, "--new-bundle-format", "--key", f"{R3}/chains.pub",
                    "--insecure-ignore-tlog", "--type", "https://slsa.dev/provenance/v1", "--digest", SUJET.split(":")[1],
                    "--digestAlg", "sha256", "--use-signed-timestamps", "--trusted-root", f"{R3}/travail/racine.json"],
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

ref = bundle.rsplit("/", 1)[1].removesuffix(".json")   # bundle-<empreinte>, nom dans le layout de R3
mb = next(m["digest"] for m in json.load(open(f"{R3}/layout/index.json"))["manifests"]
          if m["annotations"]["org.opencontainers.image.ref.name"] == ref)
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
