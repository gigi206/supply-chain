#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b, M4b refait (préparé à sec le 20/11/2026, hôte seul, rien n'est poussé) : arbre prédit de la fermeture
# neuve et digest prédit de son manifeste, tels que publier-fermeture les écrirait. Méthode de m4b-rpm-digest.py (descripteurs
# remplacés octet pour octet dans un manifeste réel), avec une base plus forte : le manifeste de la fermeture de M4b tel qu'il est
# dans Zot (2a9e2ea7, relu anonymement par l'appelant, sha256 contrôlé ici).
# Seul le dossier dir: du bootstrap change (mêmes 222 rpm, même liste, même repodata V2 que M4b) : ses 4 fichiers de M4b sont
# remplacés par ceux que skopeo copy --preserve-digests écrira pour le bootstrap neuf, tirés de son manifeste (relu anonymement
# par l'appelant, sha256 = pull_digest du verrou) : manifest.json (octets du manifeste), le blob de configuration et chaque
# couche nommés par leur digest, et version (fichier de skopeo, inchangé : même outil que l'essai de M1b, arbre égal à final).
# Témoin de méthode : avec le manifeste du bootstrap de M4b (f0ccf105), l'arbre prédit doit être celui de final et le digest
# 2a9e2ea7.
# Usage : python3 -I m1b-fermeture-digest.py <arbre-de-final> <manifeste-m4b> <digest-m4b> <manifeste-bootstrap> <pull-digest> <arbre-prédit-sortie>
import hashlib, json, sys

arbre, man_m4b, dig_m4b, man_boot, pull, sortie = sys.argv[1:7]
h = lambda b: hashlib.sha256(b).hexdigest()

brut = open(man_m4b, 'rb').read()
assert 'sha256:' + h(brut) == dig_m4b, 'manifeste de M4b : sha256 différent du digest attendu'
mb = open(man_boot, 'rb').read()
assert 'sha256:' + h(mb) == pull, 'manifeste du bootstrap neuf : sha256 différent du pull_digest'
boot = json.loads(mb)

final = {}
for ligne in open(arbre, encoding='utf-8'):
    chemin, taille, sha = ligne.split()
    final[chemin] = (int(taille), sha)
assert len(final) == 230, len(final)
anciens = sorted({c.split('/', 1)[0] for c in final if '@sha256:' in c.split('/', 1)[0]})
assert len(anciens) == 1, anciens
ancien = anciens[0]
neuf = ancien.split('@', 1)[0] + '@' + pull   # égal à ancien pour le témoin (bootstrap de M4b)
garde = {c: v for c, v in final.items() if not c.startswith(ancien + '/')}
assert len(garde) == 226 and sum(1 for c in garde if c.endswith('.rpm')) == 222, (len(garde), sum(1 for c in garde if c.endswith('.rpm')))
assert sorted(c[len(ancien) + 1:] for c in final if c.startswith(ancien + '/'))[-2:] == ['manifest.json', 'version']
version = final[ancien + '/version']

predit = dict(garde)
predit[neuf + '/manifest.json'] = (len(mb), h(mb))
predit[neuf + '/version'] = version
for d in [boot['config']] + boot['layers']:
    hx = d['digest'].removeprefix('sha256:')
    assert neuf + '/' + hx not in predit, 'blob en double'
    predit[neuf + '/' + hx] = (d['size'], hx)
print(f'bootstrap neuf : {len(boot["layers"])} couche(s), configuration {boot["config"]["digest"]} ({boot["config"]["size"]} octets)')
for d in boot['layers']:
    print(f'  couche {d["digest"]} : {d["size"]} octets, {d["mediaType"]}')
print(f'dossier dir: de M4b : {ancien}')
print(f'dossier dir: neuf : {neuf}')
# même ordre que le pas ARBRE (find -printf "%P %s" | sort, LC_ALL=C), puis le sha256
lignes = sorted(f'{c} {t}' for c, (t, _) in predit.items())
with open(sortie, 'w', encoding='utf-8') as f:
    for l in lignes:
        c = l.rsplit(' ', 1)[0]
        f.write(f'{l} {predit[c][1]}\n')
print(f'arbre prédit : {len(predit)} fichiers, {sum(t for t, _ in predit.values())} octets')

m = json.loads(brut)
assert m['artifactType'] == 'application/vnd.supply-chain.deps-closure.v1', m['artifactType']
assert m['annotations'] == {'org.opencontainers.image.created': '1970-01-01T00:00:00Z'}, m.get('annotations')
titres = [c['annotations']['org.opencontainers.image.title'] for c in m['layers']]
assert titres == sorted('depot/' + c for c in final), 'couches de M4b : ordre ou chemins différents de final'
assert all((c['size'], c['digest']) == (final[t[6:]][0], 'sha256:' + final[t[6:]][1]) for c, t in zip(m['layers'], titres)), 'couches de M4b différentes de final'
types = {c['mediaType'] for c in m['layers']}
assert len(types) == 1, types
ser = lambda c: json.dumps(c, separators=(',', ':'), ensure_ascii=False).encode()
assert all(list(c) == ['mediaType', 'digest', 'size', 'annotations'] and list(c['annotations']) == ['org.opencontainers.image.title'] for c in m['layers'])
idx = [i for i, t in enumerate(titres) if t.startswith('depot/' + ancien + '/')]
assert idx == list(range(idx[0], idx[0] + 4)), 'couches du bootstrap de M4b non contiguës'
bloc = b','.join(ser(m['layers'][i]) for i in idx)
assert brut.count(bloc) == 1, 'bloc du bootstrap de M4b non trouvé une seule fois dans les octets du manifeste'
mt = types.pop()
neufs = sorted('depot/' + c for c in predit if c.startswith(neuf + '/'))
bloc_neuf = b','.join(ser({'mediaType': mt, 'digest': 'sha256:' + predit[t[6:]][1], 'size': predit[t[6:]][0],
                            'annotations': {'org.opencontainers.image.title': t}}) for t in neufs)
nouveau = brut.replace(bloc, bloc_neuf)
m2 = json.loads(nouveau)
t2 = [c['annotations']['org.opencontainers.image.title'] for c in m2['layers']]
assert t2 == sorted('depot/' + c for c in predit), 'manifeste prédit : couches hors de l ordre de publier-fermeture (LC_ALL=C sort)'
assert [(c['size'], c['digest']) for c in m2['layers']] == [(predit[t[6:]][0], 'sha256:' + predit[t[6:]][1]) for t in t2]
assert {k: v for k, v in m2.items() if k != 'layers'} == {k: v for k, v in m.items() if k != 'layers'}, 'autres champs modifiés'
print(f'couches : {len(m2["layers"])}, octets des fichiers : {sum(c["size"] for c in m2["layers"])}')
print(f'manifeste prédit : {len(nouveau)} octets')
print(f'digest prédit : sha256:{h(nouveau)}')
