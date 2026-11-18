#!/bin/sh
set -eu
e=/workspace/sortie/entrees
export HOME=/tmp GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOFLAGS=-mod=mod GOMODCACHE=/tmp/gomod GOCACHE=/tmp/gocache CGO_ENABLED=0
# vendor/ : cache de modules copié hors du workspace (go y extrait les modules en lecture seule)
cp -r "$e/sources/deps/gomod/pkg/mod" /tmp/gomod
(cd "$e/src" && go mod vendor && go mod verify)
echo "$(go version) : vendor/ reconstitué, $(find "$e/src/vendor" -type f | wc -l) fichiers"
# marked : integrity du lockfile, puis extraction (premier composant retiré, comme tar --strip-components=1)
python3 -I - "$e/src/web/package-lock.json" "$e/sources/deps/npm" "$e/src/web/node_modules/marked" <<'FIN'
import base64, hashlib, json, os, sys, tarfile
lock, npm, dst = sys.argv[1:]
p = json.load(open(lock, encoding='utf-8'))['packages']['node_modules/marked']
a = os.path.join(npm, 'marked-' + p['version'] + '.tgz')
calc = 'sha512-' + base64.b64encode(hashlib.sha512(open(a, 'rb').read()).digest()).decode()
if calc != p['integrity']:
    sys.exit(f'integrity de {os.path.basename(a)} différente du lockfile')
os.makedirs(dst)
with tarfile.open(a) as t:
    m = []
    for x in t.getmembers():
        n = x.name.split('/', 1)
        if n == ['package', ''] and x.isdir():
            continue
        if len(n) < 2 or n[0] != 'package' or not n[1]:
            sys.exit(f'membre inattendu dans {os.path.basename(a)} : {x.name}')
        x.name = n[1]
        m.append(x)
    t.extractall(dst, members=m, filter='data')
print(f'marked {p["version"]} : integrity conforme au lockfile, {len(m)} membres extraits')
FIN
# spec et verrou de l'artefact de packaging
cp "$e/packaging/sample-app.spec" "$e/sample-app.spec"
cp "$e/packaging/verrou-rpm.json" "$e/verrou-rpm.json"
chmod 0644 "$e/sample-app.spec" "$e/verrou-rpm.json"
rm -rf "$e/sources" "$e/packaging"
echo "entrées prêtes : src ($(find "$e/src" -type f | wc -l) fichiers), fermeture rpm ($(find "$e/fermeture" -type f | wc -l) fichiers), spec $(sha256sum < "$e/sample-app.spec" | cut -c1-64), verrou $(sha256sum < "$e/verrou-rpm.json" | cut -c1-64)"

