"""Banc à sec de la couche de configuration de l'étape image : extrait de s1.sh les définitions et les commandes de etape_image
jusqu'au tar, et écrit un script bash qui les rejoue dans un dossier du scratchpad (ni Zot, ni cluster, ni $T).
Usage : python3 -I banc-config.py <s1.sh> <dossier-du-banc>"""
import hashlib, sys
s1, banc = sys.argv[1:3]
s = open(s1, encoding='utf-8').read()
assert hashlib.sha256(s.encode()).hexdigest().startswith('ad16fc99')
L = s.split('\n')
defs = [l for l in L if l.split('=')[0] in ('VAULT97', 'BOOT_DIGEST', 'DEPOT_AMONT', 'CFG', 'CFG_PRET')]
assert len(defs) == 5, defs
a = s.index('MOCK_CFG="include('); b = s.index("STOCKAGE='[storage]"); e = s.index("'\n", b) + 2
bloc = s[a:e]
i = s.index('etape_image() {\n'); j = s.index('  [ -s "$T/docker/config.json" ]', i)
corps = s[i:j].split('\n')[3:]
assert corps[0].startswith('  rm -rf -- "${c:?}"') and corps[-2].strip().startswith('--owner=0'), corps
out = ['set -euo pipefail', 'export LC_ALL=C', 'umask 022', 'REG=sc-stockage.poc.test:5000', *defs,
       'BOOT=$REG/$DEPOT_AMONT@$BOOT_DIGEST', bloc,
       'attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }',
       f'T={banc}', 'c=$T/couche-config', *corps,
       'echo "couche-config.tar : sha256 $(sha256sum < "$T/couche-config.tar" | cut -c1-64), $(stat -c %s "$T/couche-config.tar") octets"',
       'echo "configuration prête : sha256 $(sha256sum < "$c/etc/mock/$CFG_PRET.cfg" | cut -c1-64)"',
       'echo "storage.conf : sha256 $(sha256sum < "$c/etc/containers/storage.conf" | cut -c1-64)"',
       'tar -tvf "$T/couche-config.tar"']
open(banc + '/banc-config.sh', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('écrit', banc + '/banc-config.sh')
