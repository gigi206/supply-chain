"""Somme des tailles (paquet et installée) des rpm du verrou, lues dans les primary de vault 9.7 vérifiés par hote97.
Usage : python3 -I s1-m2-tailles.py <dossier de travail T, primary lus par leur nom> <verrou>"""
import json, os, sys, xml.etree.ElementTree as E
T, J = sys.argv[1:3]
C = '{http://linux.duke.edu/metadata/common}'
v = json.load(open(J))['buildroot']['rpms']
voulu = {r['url'].rsplit('/', 1)[1]: r for r in v}
trouve = {}
for d in ('baseos97', 'appstream97'):
    for _, e in E.iterparse(f'{T}/{d}.primary.xml'):
        if e.tag == C + 'package':
            f = e.find(C + 'location').get('href').rsplit('/', 1)[1]
            if f in voulu:
                s = e.find(C + 'size'); ck = e.find(C + 'checksum')
                trouve[f] = (d, int(s.get('package')), int(s.get('installed')), ck.get('type'))
            e.clear()
print('paquets du verrou :', len(voulu), '; trouvés dans les primary :', len(trouve))
print('absents :', sorted(set(voulu) - set(trouve))[:5])
print('taille des rpm (package) :', sum(x[1] for x in trouve.values()), 'octets')
print('taille installée :', sum(x[2] for x in trouve.values()), 'octets')
print('types de somme :', sorted({x[3] for x in trouve.values()}))
