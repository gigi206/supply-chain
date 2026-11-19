#!/usr/bin/env python3
# Brique 09, O5 réel, troisième accord : contrôles hors réseau des données tirées de Zot (données non fiables, lues sans rien
# exécuter ni extraire sur le disque).
#   layout DOSSIER DIGEST NOM SHA256   layout OCI tiré par oras : un seul manifeste, de digest DIGEST (sha256 des octets recalculé),
#                                      une couche tar non compressée (sha256 recalculé), un seul membre NOM, fichier régulier, de
#                                      sha256 SHA256 ; configuration et diff_ids recoupés
#   enveloppes FICHIER DIGEST          sortie de cosign verify-attestation (une enveloppe DSSE par ligne) : chaque énoncé porte un
#                                      seul sujet, de digest DIGEST, et le type de prédicat SLSA v1 ; relevé de buildType,
#                                      builder.id et invocationId
# Code 0 si tout est conforme, 3 si un contrôle refuse (ligne « REFUS … »), 2 en cas d'erreur.
import base64
import hashlib
import json
import os
import sys
import tarfile


class Refus(Exception):
    pass


def h(p):
    s = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            s.update(b)
    return s.hexdigest()


def blob(d, digest):
    algo, hexa = digest.split(":", 1)
    if algo != "sha256" or len(hexa) != 64 or not all(c in "0123456789abcdef" for c in hexa):
        raise Refus(f"digest mal formé : {digest[:80]}")
    p = os.path.join(d, "blobs", "sha256", hexa)
    if not os.path.isfile(p) or os.path.islink(p):
        raise Refus(f"blob absent ou non régulier : {digest[:23]}…")
    if h(p) != hexa:
        raise Refus(f"blob {digest[:23]}… : sha256 des octets différent")
    return p


def layout(d, digest, nom, attendu):
    idx = json.load(open(os.path.join(d, "index.json"), encoding="utf-8"))
    m = [x for x in idx.get("manifests", []) if x.get("digest") == digest]
    if len(m) != 1:
        raise Refus(f"index : {len(m)} entrée(s) pour {digest[:23]}…")
    pm = blob(d, digest)
    print(f"OK   manifeste : sha256 des octets lus = {digest}")
    man = json.load(open(pm, encoding="utf-8"))
    couches = man.get("layers", [])
    types = f"{man.get('mediaType')} {man.get('config', {}).get('mediaType')} {len(couches)} {couches[0].get('mediaType') if couches else '-'}"
    if types != "application/vnd.oci.image.manifest.v1+json application/vnd.oci.image.config.v1+json 1 application/vnd.oci.image.layer.v1.tar":
        raise Refus(f"manifeste : types ou nombre de couches : {types}")
    print(f"OK   manifeste : {types}")
    pc = blob(d, man["config"]["digest"])
    cfg = json.load(open(pc, encoding="utf-8"))
    pl = blob(d, couches[0]["digest"])
    if os.path.getsize(pl) != couches[0].get("size"):
        raise Refus("couche : taille différente du manifeste")
    if cfg.get("rootfs", {}).get("diff_ids") != [couches[0]["digest"]]:
        raise Refus("configuration : diff_ids différents de la couche non compressée")
    print(f"OK   couche {couches[0]['digest'][:23]}… ({couches[0]['size']} octets) = diff_ids de la configuration {man['config']['digest'][:23]}…")
    with tarfile.open(pl, mode="r:") as t:
        membres = t.getmembers()
        print(f"     membres de la couche : {len(membres)}")
        if len(membres) != 1 or membres[0].name != nom or not membres[0].isreg():
            raise Refus(f"couche : membres {[ (x.name, x.type) for x in membres ][:5]} (attendu : un fichier régulier {nom})")
        s = hashlib.sha256()
        f = t.extractfile(membres[0])
        if f is None:
            raise Refus("couche : membre illisible")
        for b in iter(lambda: f.read(1 << 20), b""):
            s.update(b)
    print(f"     {nom} : {membres[0].size} octets, mode {oct(membres[0].mode)}, sha256 {s.hexdigest()}")
    if s.hexdigest() != attendu:
        raise Refus(f"fichier de la couche : sha256 {s.hexdigest()[:16]}… ≠ attendu {attendu[:16]}…")
    print(f"OK   fichier de la couche = {attendu} (lien manifeste → fichier recalculé)")


def enveloppes(fichier, digest):
    lignes = [l for l in open(fichier, encoding="utf-8").read().splitlines() if l.strip()]
    if not lignes:
        raise Refus("aucune enveloppe")
    vus = {"buildType": set(), "builder": set(), "invocationId": set()}
    for i, l in enumerate(lignes, 1):
        e = json.loads(l)
        if e.get("payloadType") != "application/vnd.in-toto+json":
            raise Refus(f"enveloppe {i} : payloadType {e.get('payloadType')!r}")
        st = json.loads(base64.b64decode(e["payload"]))
        if st.get("predicateType") != "https://slsa.dev/provenance/v1":
            raise Refus(f"enveloppe {i} : predicateType {st.get('predicateType')!r}")
        sujets = st.get("subject") or []
        if len(sujets) != 1 or "sha256:" + sujets[0].get("digest", {}).get("sha256", "") != digest:
            raise Refus(f"enveloppe {i} : sujet(s) {[x.get('digest') for x in sujets]} (attendu : {digest[:23]}…)")
        p = st.get("predicate", {})
        vus["buildType"].add(p.get("buildDefinition", {}).get("buildType", "-"))
        vus["builder"].add(p.get("runDetails", {}).get("builder", {}).get("id", "-"))
        vus["invocationId"].add(p.get("runDetails", {}).get("metadata", {}).get("invocationId", "-"))
    print(f"OK   {len(lignes)} enveloppe(s), toutes SLSA v1, un seul sujet = {digest}")
    for k, v in vus.items():
        print(f"     {k} : {len(v)} valeur(s) : {', '.join(sorted(v))[:200]}")


def main():
    try:
        if sys.argv[1:2] == ["layout"]:
            layout(*sys.argv[2:6])
        elif sys.argv[1:2] == ["enveloppes"]:
            enveloppes(*sys.argv[2:4])
        else:
            sys.exit("usage : o5-zot-controle.py layout DOSSIER DIGEST NOM SHA256 | enveloppes FICHIER DIGEST")
    except Refus as r:
        print(f"REFUS {r}")
        sys.exit(3)
    except Exception as x:  # noqa: BLE001
        print(f"KO   erreur : {type(x).__name__} : {x}")
        sys.exit(2)


if __name__ == "__main__":
    main()
