#!/usr/bin/env python3
# Brique 05, M4b, préparation de l'étape rpm (18/11/2026, à sec, hôte seul) : digest attendu de la fermeture publiée par
# publier-fermeture, calculé sans rien pousser. Base : le manifeste du layout local écrit par prealables_taches (section d'envoi de
# la version signée de publier-fermeture, oras 1.3.6 de l'hôte, 230 vrais noms ; 226 fichiers réels, 4 de repodata factices).
# Les 4 descripteurs factices sont remplacés, octet pour octet dans le manifeste, par le sha256 et la taille mesurés en final
# (resultats/m4b-final-arbre.txt) ; tout le reste du manifeste est gardé tel quel.
# Usage : python3 -I m4b-rpm-digest.py <layout> <arbre-de-final>
import hashlib, json, sys

layout, arbre = sys.argv[1:3]
index = json.load(open(f'{layout}/index.json', encoding='utf-8'))
assert len(index['manifests']) == 1, 'index : un seul manifeste attendu'
d = index['manifests'][0]['digest']
brut = open(f'{layout}/blobs/sha256/{d.removeprefix("sha256:")}', 'rb').read()
assert 'sha256:' + hashlib.sha256(brut).hexdigest() == d, 'manifeste local : sha256 différent de son nom'
print(f'manifeste local (prealables_taches) : {d}, {len(brut)} octets')

ref = {}
for ligne in open(arbre, encoding='utf-8'):
    chemin, taille, sha = ligne.split()
    ref['depot/' + chemin] = (int(taille), 'sha256:' + sha)
assert len(ref) == 230, len(ref)

m = json.loads(brut)
assert m['artifactType'] == 'application/vnd.supply-chain.deps-closure.v1', m['artifactType']
assert m['annotations'] == {'org.opencontainers.image.created': '1970-01-01T00:00:00Z'}, m.get('annotations')
titres = [c['annotations']['org.opencontainers.image.title'] for c in m['layers']]
assert sorted(titres) == sorted(ref) and len(titres) == 230, 'titres des couches différents des chemins de final'
nouveau = brut
remplaces = 0
for c in m['layers']:
    t = c['annotations']['org.opencontainers.image.title']
    taille, sha = ref[t]
    if t.startswith('depot/repodata/'):
        ancien = json.dumps({'mediaType': c['mediaType'], 'digest': c['digest'], 'size': c['size'], 'annotations': c['annotations']},
                            separators=(',', ':'), ensure_ascii=False).encode()
        neuf = json.dumps({'mediaType': c['mediaType'], 'digest': sha, 'size': taille, 'annotations': c['annotations']},
                          separators=(',', ':'), ensure_ascii=False).encode()
        assert brut.count(ancien) == 1, f'descripteur factice non trouvé une seule fois : {t}'
        nouveau = nouveau.replace(ancien, neuf)
        remplaces += 1
        print(f'remplacé : {t} : {c["digest"][:19]}… {c["size"]} -> {sha[:19]}… {taille}')
    else:
        assert (c['size'], c['digest']) == (taille, sha), f'fichier réel différent de final : {t}'
assert remplaces == 4, remplaces
m2 = json.loads(nouveau)
assert [(c['annotations']['org.opencontainers.image.title'], c['size'], c['digest']) for c in m2['layers']] \
    == [(t, *ref[t]) for t in titres], 'manifeste calculé : couches différentes de final'
assert {k: v for k, v in m2.items() if k != 'layers'} == {k: v for k, v in m.items() if k != 'layers'}, 'autres champs modifiés'
print(f'couches : {len(m2["layers"])}, octets des fichiers : {sum(c["size"] for c in m2["layers"])}')
print(f'manifeste calculé : {len(nouveau)} octets')
print(f'digest attendu : sha256:{hashlib.sha256(nouveau).hexdigest()}')
