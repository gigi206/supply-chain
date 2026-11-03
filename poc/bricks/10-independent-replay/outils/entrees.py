# Brique 10, R3, sur l'hôte (transport) : lit une enveloppe DSSE du tag .att sur l'entrée standard et, si c'est la provenance
# du PipelineRun demandé, écrit « nom dépôt digest » pour chaque entrée à transporter. Rien n'est vérifié ici : la VM vérifie.
import base64
import json
import sys


def est_entree(uri, nom):  # la fermeture de la plateforme (F2 de la 03) est rangée sous builds/fermetures/<application>
    return uri.endswith(nom) or (nom == "fermeture" and "/fermetures/" in uri)

enonce = json.loads(base64.b64decode(json.load(sys.stdin)["payload"]))
if enonce["predicate"]["runDetails"]["metadata"].get("invocationId") != sys.argv[1]:
    sys.exit()
for d in enonce["predicate"]["buildDefinition"]["resolvedDependencies"]:
    uri = d.get("uri", "")
    for nom in ("construire-image", "fermeture", "web-dist", "builder-go-voie-d"):
        if est_entree(uri, nom) and "sha256" in d.get("digest", {}):
            print(nom, uri.removeprefix("oci://").replace("sc-stockage.poc.test:5000/", ""), d["digest"]["sha256"])
