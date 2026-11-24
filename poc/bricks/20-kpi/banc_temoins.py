#!/usr/bin/env python3
"""Brique 20, étape 3 : pose les sujets témoins du banc dans le Zot jetable (banc.sh). Clés, énoncés et dépôts jetables ; auteur de VEX
fictif. Provenances et signatures d'image au format de Chains (tags .att et .sig, formes relevées sur f5e6bcb0 le 24/11 à 19:39:43Z),
signées par openssl ; scans, VSA et VEX en bundles sigstore signés par cosign attest-blob et publiés en référents, comme scanner.sh.
Usage : banc_temoins.py poser | scan-kev <1|2|3>   (REG, CA et T dans l'environnement, espace de noms réseau vide)"""
import base64
import hashlib
import json
import os
import ssl
import subprocess
import sys
import urllib.request

REG, CA, T = os.environ["REG"], os.environ["CA"], os.environ["T"]
CTX = ssl.create_default_context(cafile=CA)
OCI = "application/vnd.oci.image.manifest.v1+json"
BUNDLE = "application/vnd.dev.sigstore.bundle.v0.3+json"
INTOTO = "application/vnd.in-toto+json"
PROV, SCAN = "https://slsa.dev/provenance/v1", "https://supply-chain.example/scan/v1"
VSA, VEX = "https://slsa.dev/verification_summary/v1", "https://openvex.dev/ns/v0.2.0"
BIT, L3 = "POC_REPLAY_BIT_IDENTIQUE", "SLSA_BUILD_LEVEL_3"


def http(methode, chemin, corps=None, typ=None):
    req = urllib.request.Request(chemin if chemin.startswith("https://") else f"https://{REG}/v2/{chemin}", data=corps, method=methode,
                                 headers={"Content-Type": typ or "application/octet-stream"})
    return urllib.request.urlopen(req, timeout=20, context=CTX)


def empreinte(octets):
    return "sha256:" + hashlib.sha256(octets).hexdigest()


def blob(depot, octets, typ):
    with http("POST", f"{depot}/blobs/uploads/", b"") as r:
        lieu = r.headers["Location"]
    lieu = lieu if lieu.startswith("https://") else f"https://{REG}{lieu}"
    http("PUT", lieu + ("&" if "?" in lieu else "?") + "digest=" + empreinte(octets), octets).close()
    return {"mediaType": typ, "digest": empreinte(octets), "size": len(octets)}


def manifeste(depot, couches, tag=None, config=b"{}", config_typ="application/vnd.oci.empty.v1+json", **plus):
    octets = json.dumps({"schemaVersion": 2, "mediaType": OCI, "config": blob(depot, config, config_typ), "layers": couches, **plus}).encode()
    http("PUT", f"{depot}/manifests/{tag or empreinte(octets)}", octets, OCI).close()
    return {"mediaType": OCI, "digest": empreinte(octets), "size": len(octets)}


def signer(cle, octets):
    r = subprocess.run(["openssl", "dgst", "-sha256", "-sign", f"{T}/cle/{cle}.pem"], input=octets, capture_output=True, check=True)
    return base64.b64encode(r.stdout).decode()


def dsse(cle, enonce):
    charge = json.dumps(enonce).encode()
    pae = b"DSSEv1 %d %s %d %s" % (len(INTOTO), INTOTO.encode(), len(charge), charge)
    return json.dumps({"payloadType": INTOTO, "payload": base64.b64encode(charge).decode(),
                       "signatures": [{"keyid": "", "sig": signer(cle, pae)}]}).encode()


def sujet(nom):
    d = f"builds/{nom}"
    return manifeste(d, [blob(d, f"témoin {nom} de la brique 20\n".encode(), "application/vnd.oci.image.layer.v1.tar")], "banc",
                     artifactType="application/vnd.supply-chain.temoin")


def chains(nom, s, refs, cle="chains", sig=True, cle_sig=None, illisible=False, plus=None):
    """Tags .att (une enveloppe par élément de refs : pipelineRef ou taskRef) et .sig, comme Chains. plus : par rang dans refs, (dépendances,
    fin, clé). illisible : une couche .att de plus,
    à signature vide, et une annotation de signature d'image vide."""
    d, h = f"builds/{nom}", s["digest"][7:]
    couches = []
    for i, ref in enumerate(refs):
        deps, fin, cle_i = (plus or {}).get(i, ([], "2026-11-19T00:00:00Z", cle))
        e = {"_type": "https://in-toto.io/Statement/v1", "predicateType": PROV,
             "subject": [{"name": f"{REG}/{d}", "digest": {"sha256": h}}],
             "predicate": {"buildDefinition": {"buildType": "https://tekton.dev/chains/v2/slsa-tekton", "resolvedDependencies": deps,
                                               "externalParameters": {"runSpec": {ref: {}}}, "internalParameters": {}},
                           "runDetails": {"builder": {"id": "https://supply-chain.example/builders/tekton-chains@v1"},
                                          "metadata": {"invocationId": f"banc-{i}", "finishedOn": fin}}}}
        couches.append({**blob(d, dsse(cle_i, e), "application/vnd.dsse.envelope.v1+json"),
                        "annotations": {"dev.cosignproject.cosign/signature": ""}})
    if illisible:
        d_vide = json.loads(dsse(cle, e))
        d_vide["signatures"][0]["sig"] = ""
        couches.append({**blob(d, json.dumps(d_vide).encode(), "application/vnd.dsse.envelope.v1+json"),
                        "annotations": {"dev.cosignproject.cosign/signature": ""}})
    cfg = "application/vnd.oci.image.config.v1+json"
    manifeste(d, couches, f"sha256-{h}.att", b'{"architecture":"","os":"","rootfs":{"type":"layers","diff_ids":[]}}', cfg)
    if sig:
        p = json.dumps({"critical": {"identity": {"docker-reference": f"{REG}/{d}"}, "image": {"docker-manifest-digest": s["digest"]},
                                     "type": "cosign container image signature"}, "optional": None}).encode()
        c = {**blob(d, p, "application/vnd.dev.cosign.simplesigning.v1+json"), "annotations": {
            "dev.cosignproject.cosign/signature": "" if illisible else signer(cle_sig or cle, p)}}
        manifeste(d, [c], f"sha256-{h}.sig", b'{"architecture":"","os":"","rootfs":{"type":"layers","diff_ids":[]}}', cfg)


def referent(famille, nom, s, typ, predicat, cle, cree="2026-11-20T00:00:00Z", sig=None):
    w = f"{T}/tmp"
    with open(f"{w}/predicat.json", "w", encoding="utf-8") as f:
        json.dump(predicat, f)
    subprocess.run(["cosign", "attest-blob", "--key", f"{T}/cle/{cle}.key", "--signing-config", f"{T}/vide.json", "--predicate",
                    f"{w}/predicat.json", "--type", typ, "--bundle", f"{w}/bundle.json", "--hash", s["digest"][7:], "--yes", nom],
                   env={**os.environ, "COSIGN_PASSWORD": ""}, check=True, capture_output=True, stdin=subprocess.DEVNULL)
    with open(f"{w}/bundle.json", "rb") as f:
        octets = f.read()
    if sig is not None:  # signature remplacée : vide, pas du DER, pas du base64
        b = json.loads(octets)
        b["dsseEnvelope"]["signatures"][0]["sig"] = sig
        octets = json.dumps(b).encode()
    d = f"builds/{famille}/{nom}"
    manifeste(d, [blob(d, octets, BUNDLE)], artifactType=BUNDLE, subject=s, annotations={
        "dev.sigstore.bundle.content": "dsse-envelope", "dev.sigstore.bundle.predicateType": typ, "org.opencontainers.image.created": cree})


def entree(ident, vex=False, kev=False):
    e = {"id": ident, "aliases": [], "severity": "High", "kev": kev, "kevCves": [ident] if kev else [], "epss": 0.1, "fixedIn": [],
         "package": f"pkg:generic/{ident.lower()}@1"}
    return {**e, "vex": {"status": "not_affected", "timestamp": "2026-11-02T00:00:00Z"}} if vex else e


def scan(nom, s, date, entrees, cle="scanner", sig=None):
    referent("scan", nom, s, SCAN, {"scannedAt": date, "vulnerabilities": entrees}, cle, date, sig)


def vsa(nom, s, resultat, niveaux, cle="vsa", sig=None):
    referent("vsa", nom, s, VSA, {"verifier": {"id": "https://supply-chain.example/verifiers/replay-poc-administrateur-unique@v1"},
                                  "timeVerified": "2026-11-20T00:00:00Z", "resourceUri": f"{REG}/builds/{nom}", "slsaVersion": "1.0",
                                  "policy": {"uri": "https://supply-chain.example/banc"}, "inputAttestations": [],
                                  "verificationResult": resultat, "verifiedLevels": niveaux}, cle, sig=sig)


def vex(nom, s, cle="vex", sig=None):
    referent("vex", nom, s, VEX, {"@context": VEX, "@id": "https://supply-chain.example/vex/banc", "author": "banc de la brique 20",
                                  "timestamp": "2026-11-02T00:00:00Z", "version": 1, "statements": []}, cle, sig=sig)


def dep(nom, chiffre, uri=None):
    return {"uri": uri or f"oci://{REG}/x/{nom}", "digest": {"sha256": chiffre * 64}}


def poser():
    J = "2026-11-20T00:00:00Z"
    PR, TR = "pipelineRef", "taskRef"
    s = sujet("banc-complet"); chains("banc-complet", s, [PR, TR])
    scan("banc-complet", s, J, [entree("CVE-A"), entree("CVE-B", vex=True), entree("CVE-C", vex=True, kev=True)])
    vsa("banc-complet", s, "PASSED", [BIT, L3]); vex("banc-complet", s)
    s = sujet("banc-sans-vsa"); chains("banc-sans-vsa", s, [PR]); scan("banc-sans-vsa", s, J, [])
    s = sujet("banc-vsa-failed"); chains("banc-vsa-failed", s, [PR]); scan("banc-vsa-failed", s, J, [entree("CVE-D", kev=True)])
    vsa("banc-vsa-failed", s, "FAILED", [BIT, L3])
    s = sujet("banc-forge"); chains("banc-forge", s, [PR]); scan("banc-forge", s, J, [entree("CVE-E", kev=True)])
    # signatures fausses : énoncés bien formés, clé étrangère (ce qu'un compte autorisé à écrire dans Zot peut poser sans la clé)
    scan("banc-forge", s, "2026-11-21T00:00:00Z", [], "etrangere"); vsa("banc-forge", s, "PASSED", [BIT, L3], "etrangere")
    vex("banc-forge", s, "etrangere")
    s = sujet("banc-prov-forgee"); chains("banc-prov-forgee", s, [PR], "etrangere")
    s = sujet("banc-prov-seule"); chains("banc-prov-seule", s, [PR])
    s = sujet("banc-prov-tache"); chains("banc-prov-tache", s, [TR])
    s = sujet("banc-sans-sig"); chains("banc-sans-sig", s, [PR], sig=False)
    # essai openssl (e3b) : clé d'un autre rôle, signature d'image forgée, signatures illisibles
    s = sujet("banc-mauvais-role"); chains("banc-mauvais-role", s, [PR]); scan("banc-mauvais-role", s, J, [entree("CVE-F", kev=True)], "vsa")
    vsa("banc-mauvais-role", s, "PASSED", [BIT, L3], "scanner"); vex("banc-mauvais-role", s, "scanner")
    s = sujet("banc-role-prov"); chains("banc-role-prov", s, [PR], "vex")
    s = sujet("banc-sig-forgee"); chains("banc-sig-forgee", s, [PR], cle_sig="etrangere")
    s = sujet("banc-illisible"); chains("banc-illisible", s, [PR]); scan("banc-illisible", s, J, [entree("CVE-G", kev=True)])
    scan("banc-illisible", s, "2026-11-21T00:00:00Z", [], sig="")
    vsa("banc-illisible", s, "PASSED", [BIT, L3], sig=base64.b64encode(b"pas une signature").decode()); vex("banc-illisible", s, sig="!!!")
    s = sujet("banc-att-illisible"); chains("banc-att-illisible", s, [PR], illisible=True)
    # étape 4 : quatre provenances ; seule compte la plus récente des PipelineRun vérifiées (rang 1). Rang 2 : TaskRun ; rang 3 : clé
    # étrangère, plus récente
    s = sujet("banc-pins")
    chains("banc-pins", s, [PR, PR, TR, PR], plus={
        0: ([dep("ancien", "1")], "2026-11-18T00:00:00Z", "chains"),
        1: ([dep("present", "2"), dep("retire", "3"), dep("jamais", "4"), dep("inconnu", "5"), dep('a"} 1', "6"),
             dep("present", "2", "git+https://forge.test/x/source.git"), {**dep("t", "7"), "name": "pipelineTask"},
             dep("present", "2")], "2026-11-19T00:00:00Z", "chains"),
        2: ([dep("tache", "8")], "2026-11-20T00:00:00Z", "chains"),
        3: ([dep("forge", "2")], "2026-11-21T00:00:00Z", "etrangere")})
    s = sujet("banc-kev"); chains("banc-kev", s, [PR])
    print(f"SCANS=builds/scan/banc-kev@{s['digest']}")


def scan_kev(n):
    s = sujet("banc-kev")  # même contenu, donc même digest
    k1, k2, k3 = "CVE-2026-90001", "CVE-2026-90002", "CVE-2026-90003"
    date, entrees = {1: ("2026-11-01T00:00:00Z", [entree(k1, kev=True), entree(k2, kev=True)]),
                     2: ("2026-11-08T12:00:00Z", [entree(k1, vex=True, kev=True), entree(k2, kev=True)]),
                     3: ("2026-11-10T00:00:00Z", [entree(k1, vex=True, kev=True), entree(k3, kev=True)])}[n]
    scan("banc-kev", s, date, entrees)


if __name__ == "__main__":
    poser() if sys.argv[1] == "poser" else scan_kev(int(sys.argv[2]))
