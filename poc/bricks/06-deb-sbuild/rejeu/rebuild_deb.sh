#!/bin/bash
# Brique 06, S6b (contrôle 6 du deb), DANS LA VM sc-replay, compte replay (systemd-run --uid=replay), lien réseau COUPÉ par
# l'hôte. Modèle : rebuild.sh de la brique 10 (R4). Reconstruction du deb de sample-app à partir des entrées vérifiées par
# verifier_deb.py (~/s6b/r3), avec la recette des tâches signées preparer-deb et construire-deb (lignes clés contrôlées par
# verifier_deb.py), le chroot reconstruit dans le domaine (étape chroot) et les outils du domaine (Go officiel de la brique 10,
# dpkg-dev, sbuild et mmdebstrap de trixie, aux versions de la plateforme). Refuse de démarrer si une interface a encore sa
# porteuse (lien non coupé). Résultats : ~/s6b/r4/resultat.txt (clé=valeur) ; journal : ~/s6b/r4/rebuild.log.
# Écarts voulus avec la plateforme : aucun pod (ni Kata, ni runc) ; entrées lues dans le layout transporté (oras --oci-layout) et
# le bundle git, au lieu de Zot et de Forgejo ; un seul arbre de travail sur disque ; témoins réseau remplacés par le refus de
# porteuse et les compteurs de l'interface.
set -euo pipefail
export LC_ALL=C
umask 022
R3=/home/replay/s6b/r3 R4=/home/replay/s6b/r4 E=/home/replay/s6b/r4/e C=/home/replay/s6b/trixie-amd64.tar
exec > "$R4/rebuild.log" 2>&1
res() { echo "$1=$2" >> "$R4/resultat.txt"; echo "$1=$2"; }
: > "$R4/resultat.txt"
trap 'res sortie "code $?"' EXIT
res debut "$(date -u +%FT%TZ)"
res compte "$(id -un) ($(id -u))"
sleep 20   # laisse à l'hôte le temps de couper le lien juste après le lancement
for i in /sys/class/net/*; do
  [ "${i##*/}" = lo ] && continue
  res "porteuse_${i##*/}" "$(cat "$i/carrier" 2>/dev/null || echo ?)"
  [ "$(cat "$i/carrier" 2>/dev/null)" = 0 ] || { res verdict "REFUS : lien ${i##*/} non coupé"; exit 1; }
done
tx() { for i in /sys/class/net/*; do [ "${i##*/}" = lo ] || printf '%s tx_packets=%s tx_bytes=%s ' "${i##*/}" "$(cat "$i/statistics/tx_packets")" "$(cat "$i/statistics/tx_bytes")"; done; }
res sortie_invite_debut "$(tx)"

# --- entrées revérifiées contre la provenance vérifiée (verifier_deb.py) ; chroot inchangé depuis sa vérification
grep -qx 'ko=0' "$R3/verifie.txt" || { res verdict "REFUS : verifier_deb.py n'a pas fini sans KO"; exit 1; }
python3 -I - "$R3/provenance.json" "$R3/layout" <<'PY' >> "$R4/resultat.txt"
import hashlib, json, subprocess, sys
p = json.load(open(sys.argv[1]))["predicate"]["buildDefinition"]["resolvedDependencies"]
for nom, fin in (("construire-deb", "tekton/tasks/construire-deb"), ("preparer-deb", "tekton/tasks/preparer-deb"),
                 ("fermeture-deb", "builds/fermetures/sample-app-deb"), ("fermeture-sources", "builds/fermetures/sample-app-sources"),
                 ("packaging", "entrees/sample-app/packaging-deb")):
    d = [x for x in p if x.get("uri", "").endswith(fin)][0]["digest"]["sha256"]
    m = subprocess.run(["oras", "manifest", "fetch", "--oci-layout", f"{sys.argv[2]}:{nom}"], capture_output=True).stdout
    print(f"entree_{nom}={'OK' if hashlib.sha256(m).hexdigest() == d else 'KO'} {hashlib.sha256(m).hexdigest()}")
PY
c=$(sed -n 's/^chroot_sha256=//p' "$R3/verifie.txt")
[ "$(sha256sum < "$C" | cut -c1-64)" = "$c" ] && res chroot "OK $c" || res chroot "KO"
grep -qE '=KO|^chroot=KO' "$R4/resultat.txt" && { res verdict "REFUS : entrées ou chroot"; exit 1; }

# --- preparer-deb : sources du commit, trois artefacts, fermeture confrontée au verrou, vendor/, marked, debian/
commit=$(sed -n 's/^commit=//p' "$R3/verifie.txt")
rm -rf --one-file-system -- /home/replay/s6b/r4/e && mkdir -p "$E/entrees/src" "$E/tmp"   # chemin littéral
e=$E/entrees
git -C "$R3/src" archive --format=tar "$commit" | tar -xf - -C "$e/src"
oras pull --no-tty --oci-layout "$R3/layout:fermeture-deb" -o "$e/fermeture" > /dev/null
oras pull --no-tty --oci-layout "$R3/layout:fermeture-sources" -o "$e/sources" > /dev/null
oras pull --no-tty --oci-layout "$R3/layout:packaging" -o "$e/packaging" > /dev/null
res entrees "commit $commit ; fermeture deb $(find "$e/fermeture" -type f | wc -l) fichiers ; fermeture applicative $(find "$e/sources" -type f | wc -l) fichiers ; packaging $(find "$e/packaging" -type f | wc -l) fichiers"
v=$e/packaging/verrou-deb.txt
[ -s "$v" ] || { res verdict "REFUS : verrou absent de l'artefact de packaging"; exit 1; }
m=$e/fermeture/miroir
grep -v '^#' "$v" | grep . > "$E/tmp/verrou"
n=0
while read -r _ _ _ s z p; do
  case $p in pool/*.deb) ;; *) res verdict "REFUS : chemin du verrou non admis : $p"; exit 1 ;; esac
  case $p in *..*) res verdict "REFUS : chemin du verrou non admis : $p"; exit 1 ;; esac
  [ -f "$m/$p" ] && [ ! -L "$m/$p" ] || { res verdict "REFUS : paquet du verrou absent : $p"; exit 1; }
  [ "$(sha256sum < "$m/$p" | cut -c1-64)" = "$s" ] || { res verdict "REFUS : paquet différent du verrou : $p"; exit 1; }
  [ "$(($(wc -c < "$m/$p")))" = "$z" ] || { res verdict "REFUS : taille différente du verrou : $p"; exit 1; }
  n=$((n + 1))
done < "$E/tmp/verrou"
[ "$n" -gt 0 ] && [ "$(find "$m/pool" -type f | wc -l)" = "$n" ] || { res verdict "REFUS : pool différent du verrou"; exit 1; }
res verrou "$n paquets, sha256, taille et chemin identiques, aucun autre fichier dans le pool"
(
  export HOME=$E/tmp GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOFLAGS=-mod=mod GOMODCACHE=$E/gomod GOCACHE=$E/gocache CGO_ENABLED=0
  export PATH=/usr/local/go/bin:$PATH
  cp -r "$e/sources/deps/gomod/pkg/mod" "$E/gomod"
  cd "$e/src" && go mod vendor && go mod verify
)
res vendor "$(/usr/local/go/bin/go version | cut -d' ' -f3) : $(find "$e/src/vendor" -type f | wc -l) fichiers"
python3 -I - "$e/src/web/package-lock.json" "$e/sources/deps/npm" "$e/src/web/node_modules/marked" <<'FIN' >> "$R4/resultat.txt"
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
print(f'marked=marked {p["version"]} : integrity conforme au lockfile, {len(m)} membres extraits')
FIN
cp -r "$e/packaging/debian" "$e/debian"
cp "$e/packaging/verrou-deb.txt" "$e/verrou-deb.txt"
find "$e/debian" -type f -exec chmod 0644 {} \;
chmod 0755 "$e/debian/rules"
rm -rf -- /home/replay/s6b/r4/e/entrees/sources /home/replay/s6b/r4/e/entrees/packaging
res preparation "src $(find "$e/src" -type f | wc -l) fichiers, debian $(find "$e/debian" -type f | wc -l) fichiers"

# --- construire-deb : fermeture recopiée à plat, paquet source, sbuild hors ligne, layout OCI fait main
mkdir -p "$E/fermeture"
n=0
while read -r _ _ _ s z p; do
  [ "$(sha256sum < "$e/fermeture/miroir/$p" | cut -c1-64)" = "$s" ] || { res verdict "REFUS : paquet différent du verrou : $p"; exit 1; }
  [ ! -e "$E/fermeture/${p##*/}" ] || { res verdict "REFUS : nom de paquet en double : ${p##*/}"; exit 1; }
  cp "$e/fermeture/miroir/$p" "$E/fermeture/"
  n=$((n + 1))
done < <(grep -v '^#' "$e/verrou-deb.txt" | grep .)
res fermeture "$n paquets copiés à plat"
c=$e/debian/changelog
src=$(dpkg-parsechangelog -l "$c" -SSource); ver=$(dpkg-parsechangelog -l "$c" -SVersion); sde=$(dpkg-parsechangelog -l "$c" -STimestamp)
amont=${ver%-*}
mkdir -p "$E/src"
cp -a "$e/src" "$E/src/$src-$amont"
tar -C "$E/src" --sort=name --mtime="@$sde" --owner=0 --group=0 --numeric-owner --mode=go-w,a+rX \
  --format=gnu -cf - "$src-$amont" | gzip -n -9 > "$E/src/${src}_$amont.orig.tar.gz"
cp -a "$e/debian" "$E/src/$src-$amont/debian"
(cd "$E/src" && SOURCE_DATE_EPOCH=$sde dpkg-source -q -b "$src-$amont" > /dev/null)
dsc=$E/src/${src}_$ver.dsc
res paquet_source "$src $ver (SOURCE_DATE_EPOCH $sde) : $(cd "$E/src" && for f in "${src}_$amont.orig.tar.gz" "${dsc##*/}" "${src}_$ver.debian.tar.xz"; do echo -n "$f $(sha256sum < "$f" | cut -c1-64) ; "; done)"
mkdir -p "$E/home" "$E/sortie"
t=$(date +%s); r=0
( export TMPDIR=$E/tmp HOME=$E/home
  sbuild --chroot-mode=unshare --chroot="$C" --dist=trixie --arch=amd64 --no-apt-update --no-apt-upgrade \
    --no-apt-distupgrade --no-run-lintian --no-run-autopkgtest --no-run-piuparts --no-source-only-changes --build-dir="$E/sortie" \
    --extra-package="$E/fermeture" \
    "--chroot-setup-commands=truncate -s 0 /etc/apt/sources.list" \
    "$dsc" > "$E/sbuild.out" 2>&1 ) || r=$?
res sbuild "code $r en $(($(date +%s) - t)) s ; lignes apt Get, Hit, Ign ou Err en http(s) : $(grep -cE '^(Get|Hit|Ign|Err):[0-9]+ https?://' "$E/sbuild.out" || true)"
[ $r = 0 ] || { tail -n 80 "$E/sbuild.out"; res verdict FAILED; res fin_deb "$(date -u +%FT%TZ)"; exit 1; }
shopt -s nullglob
d=("$E"/sortie/*.deb)
[ ${#d[@]} = 1 ] || { res verdict "FAILED : ${#d[@]} deb produits"; exit 1; }
deb=${d[0]}
res deb "${deb##*/} $(sha256sum < "$deb" | cut -c1-64) ($(stat -c %s "$deb") octets)"
b=("$E"/sortie/*.buildinfo)
[ ${#b[@]} = 1 ] && { echo "----- ${b[0]##*/} -----"; cat "${b[0]}"; echo "----- fin du .buildinfo -----"; }
L=$E/layout
mkdir -p "$L/blobs/sha256" "$E/cc"
cp "$deb" "$E/cc/"
chmod 0644 "$E/cc/${deb##*/}"
tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime=@0 \
  --owner=0 --group=0 --numeric-owner -C "$E/cc" -cf "$E/couche.tar" "${deb##*/}"
l=$(sha256sum < "$E/couche.tar" | cut -c1-64); s=$(stat -c %s "$E/couche.tar")
mv "$E/couche.tar" "$L/blobs/sha256/$l"
blob() { local h; h=$(printf '%s' "$1" | sha256sum | cut -c1-64); printf '%s' "$1" > "$L/blobs/sha256/$h"; echo "$h ${#1}"; }
cfg=$(blob '{"architecture":"amd64","os":"linux","rootfs":{"type":"layers","diff_ids":["sha256:'"$l"'"]}}')
man=$(blob '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:'"${cfg% *}"'","size":'"${cfg#* }"'},"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:'"$l"'","size":'"$s"'}]}')
res couche "sha256:$l ($s octets)"
res manifeste_reconstruit "sha256:${man% *}"
sujet=$(python3 -I -c 'import json,sys; print("sha256:" + json.load(open(sys.argv[1]))["subject"][0]["digest"]["sha256"])' "$R3/provenance.json")
res sujet_provenance "$sujet"
[ "sha256:${man% *}" = "$sujet" ] && res verdict PASSED || res verdict FAILED
res fin_deb "$(date -u +%FT%TZ)"
res sortie_invite_fin "$(tx)"
res porteuse_fin "$(for i in /sys/class/net/*; do [ "${i##*/}" = lo ] || printf '%s=%s ' "${i##*/}" "$(cat "$i/carrier" 2>/dev/null)"; done)"
res fin "$(date -u +%FT%TZ)"
