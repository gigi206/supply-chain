#!/bin/bash
# Brique 10, R4, DANS LA VM, en root (systemd-run), lien réseau COUPÉ par l'hôte : rebuild de l'image rejouée à partir des
# entrées vérifiées en R3 (~replay/r3) et de la recette signée (bundles preparer-entrees et construire-image), avec la
# toolchain et le moteur du domaine. Refuse de démarrer si l'interface a encore sa porteuse (lien non coupé).
# Résultats : ~replay/r4/resultat.txt (lignes clé=valeur) ; journal : ~replay/r4/rebuild.log.
set -euo pipefail
export LC_ALL=C
R3=/home/replay/r3 R4=/home/replay/r4 E=/home/replay/r4/e BK=/var/lib/replay-buildkit
exec > "$R4/rebuild.log" 2>&1
res() { echo "$1=$2" >> "$R4/resultat.txt"; echo "$1=$2"; }
: > "$R4/resultat.txt"
trap 'res sortie "code $?"' EXIT   # code de sortie lu par l'hôte dans resultat.txt (systemctl show ne le donne plus après --collect)
res debut "$(date -u +%FT%TZ)"
sleep 20   # laisse à l'hôte le temps de couper le lien juste après le lancement
for i in /sys/class/net/*; do
  [ "${i##*/}" = lo ] && continue
  res "porteuse_${i##*/}" "$(cat "$i/carrier" 2>/dev/null || echo ?)"
  [ "$(cat "$i/carrier" 2>/dev/null)" = 0 ] || { res verdict "REFUS : lien ${i##*/} non coupé"; exit 1; }
done
tx() { for i in /sys/class/net/*; do [ "${i##*/}" = lo ] || printf '%s tx_packets=%s tx_bytes=%s ' "${i##*/}" "$(cat "$i/statistics/tx_packets")" "$(cat "$i/statistics/tx_bytes")"; done; }
res sortie_invite_debut "$(tx)"

# --- recette de preparer-entrees : digest du bundle transporté comparé ici à la provenance vérifiée en R3
python3 -I - "$R3/provenance.json" "$R4/layout" <<'PY' >> "$R4/resultat.txt"
import hashlib, io, json, subprocess, sys, tarfile
p = json.load(open(sys.argv[1]))["predicate"]["buildDefinition"]["resolvedDependencies"]
d = [x for x in p if x.get("uri", "").endswith("preparer-entrees")][0]["digest"]["sha256"]
m = subprocess.run(["oras", "manifest", "fetch", "--oci-layout", f"{sys.argv[2]}:preparer-entrees"], capture_output=True).stdout
print(f"preparer_entrees_digest={'OK' if hashlib.sha256(m).hexdigest() == d else 'KO'} {hashlib.sha256(m).hexdigest()}")
b = subprocess.run(["oras", "blob", "fetch", "--oci-layout", f"{sys.argv[2]}@{json.loads(m)['layers'][0]['digest']}", "--output", "-"], capture_output=True).stdout
with tarfile.open(fileobj=io.BytesIO(b)) as tf:
    t = json.loads(tf.extractfile([x for x in tf.getmembers() if x.isfile()][0]).read())
s = "\n".join(e.get("script", "") for e in t["spec"]["steps"])
for nom, motif in (("git_archive", 'git -C /tmp/depot archive --format=tar HEAD | tar -xf - -C "$e/src"'),
                   ("fermeture_deps", 'oras pull --no-tty --ca-file /etc/ca-poc/ca.crt -o "$e/deps" "$FERMETURE"'),
                   ("web_dist_src", 'oras pull --no-tty --ca-file /etc/ca-poc/ca.crt -o "$e/src/web/dist" "$WEB_DIST"')):
    print(f"recette_{nom}={'OK' if motif in s else 'KO'}")
PY
grep -q '=KO' "$R4/resultat.txt" && { res verdict "REFUS : recette de preparer-entrees"; exit 1; }

# --- contexte, comme preparer-entrees : sources du commit, fermeture dans deps, web-dist dans src/web/dist
commit=$(python3 -I -c 'import json,sys; print([x for x in json.load(open(sys.argv[1]))["predicate"]["buildDefinition"]["resolvedDependencies"] if x.get("uri","").endswith("sample-app.git")][0]["digest"]["sha1"])' "$R3/provenance.json")
rm -rf "$E" && mkdir -p "$E/src"
# git en tant que replay, propriétaire du dépôt : root ne lit jamais sa configuration (git refuse un dépôt d'un autre
# propriétaire, « dubious ownership », premier passage de R4) ; tar reste en root
runuser -u replay -- git -C "$R3/src" archive --format=tar "$commit" | tar -xf - -C "$E/src"
oras pull --no-tty --oci-layout "$R3/layout:fermeture" -o "$E/deps" > /dev/null
oras pull --no-tty --oci-layout "$R3/layout:web-dist" -o "$E/src/web/dist" > /dev/null
res contexte "commit $commit ; fermeture $(find "$E/deps" -type f | wc -l) fichiers ; web/dist $(find "$E/src/web/dist" -type f | wc -l) fichiers"

# --- image de build DU DOMAINE : busybox-static (Debian), Go officiel (go.dev), Env de l'image de build déclarée
mkdir -p "$E/bctx" && cp /bin/busybox "$E/bctx/busybox" && cp -a /usr/local/go "$E/bctx/go"
python3 -I - "$R3/layout" > "$E/bctx/Dockerfile" <<'PY'
import json, subprocess, sys
L = sys.argv[1]
m = json.loads(subprocess.run(["oras", "manifest", "fetch", "--oci-layout", f"{L}:builder-go-voie-d"], capture_output=True).stdout)
c = json.loads(subprocess.run(["oras", "blob", "fetch", "--oci-layout", f"{L}@{m['config']['digest']}", "--output", "-"], capture_output=True).stdout)
print("FROM scratch\nCOPY busybox /bin/busybox\nRUN [\"/bin/busybox\", \"--install\", \"-s\", \"/bin\"]\nCOPY go /usr/local/go")
print("ENV " + " \\\n    ".join(c["config"]["Env"]))
PY
res env_image_de_build "$(grep -A9 '^ENV' "$E/bctx/Dockerfile" | tr -d '\\\n' | tr -s ' ')"
rm -rf "$BK" && mkdir -p /tmp/run-bk
buildkitd --oci-worker-snapshotter=native --addr unix:///tmp/run-bk/bk.sock --root "$BK" > "$R4/buildkitd.log" 2>&1 &
k=$!
for _ in $(seq 30); do buildctl --addr unix:///tmp/run-bk/bk.sock debug workers > /dev/null 2>&1 && break; sleep 1; done
res buildkit "$(buildkitd --version)"
t=$(date +%s)
buildctl --addr unix:///tmp/run-bk/bk.sock build --frontend dockerfile.v0 --no-cache --opt build-arg:SOURCE_DATE_EPOCH=0 \
  --local context="$E/bctx" --local dockerfile="$E/bctx" --opt filename=Dockerfile \
  --output type=oci,dest="$E/builder.tar",rewrite-timestamp=true
mkdir -p "$E/builder" && tar -xf "$E/builder.tar" -C "$E/builder"
b=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifests"][0]["digest"])' "$E/builder/index.json")
res image_de_build_domaine "$b ($(($(date +%s) - t)) s)"

# --- build de l'image : recette signée (Dockerfile du bundle construire-image), seul le digest de l'image de build change
t=$(date +%s)
buildctl --addr unix:///tmp/run-bk/bk.sock build --frontend dockerfile.v0 --no-cache --opt build-arg:SOURCE_DATE_EPOCH=0 \
  --local context="$E/src" --local dockerfile="$R3/recette" --opt filename=Dockerfile \
  --oci-layout magasin="$E/builder" --opt "context:builder=oci-layout://magasin@$b" \
  --local deps="$E/deps" --opt context:deps=local:deps \
  --output type=oci,dest="$E/image.tar",rewrite-timestamp=true
d=$(tar -xOf "$E/image.tar" index.json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["manifests"][0]["digest"])')
res image_reconstruite "$d ($(($(date +%s) - t)) s)"
sujet=$(python3 -I -c 'import json,sys; print("sha256:" + json.load(open(sys.argv[1]))["subject"][0]["digest"]["sha256"])' "$R3/provenance.json")
res sujet_provenance "$sujet"
kill $k 2> /dev/null || true; wait $k 2> /dev/null || true
[ "$d" = "$sujet" ] && res verdict PASSED || res verdict FAILED
res fin_image "$(date -u +%FT%TZ)"

# second moteur : hors du verdict (politique, section 4) ; un échec est consigné sans interrompre le script
set +e
(
set -e

# --- go build direct (Env de l'image de build, options du RUN du Dockerfile signé), binaire comparé
mkdir -p "$E/image" && tar -xf "$E/image.tar" -C "$E/image"
python3 -I - "$E/image" "$E/binaire-image" <<'PY'
import json, sys, tarfile
L = sys.argv[1]
m = json.load(open(f"{L}/blobs/sha256/" + json.load(open(f"{L}/index.json"))["manifests"][0]["digest"].split(":")[1]))
for c in m["layers"]:
    with tarfile.open(f"{L}/blobs/sha256/" + c["digest"].split(":")[1]) as tf:
        for x in tf.getmembers():
            if x.name.lstrip("./") == "sample-app":
                open(sys.argv[2], "wb").write(tf.extractfile(x).read())
PY
cp -a "$E/src" "$E/src2"
( cd "$E/src2" && env -i PATH=/usr/local/go/bin:/bin:/usr/bin HOME=/tmp CGO_ENABLED=0 GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOSUMDB=off \
    GOPROXY="file://$E/deps/deps/gomod/pkg/mod/cache/download" GOMODCACHE="$E/mod" GOCACHE="$E/cache" \
    go build -trimpath -buildvcs=false -ldflags "-s -w -buildid= -X main.Version=1.0.0" -o "$E/binaire-go" . )
res binaire_image "$(sha256sum < "$E/binaire-image" | cut -c1-64)"
res binaire_go_build "$(sha256sum < "$E/binaire-go" | cut -c1-64)"
grep -q -- '-trimpath -buildvcs=false -ldflags "-s -w -buildid= -X main.Version=1.0.0"' "$R3/recette/Dockerfile" \
  && res options_go_build "identiques au RUN du Dockerfile signé" || res options_go_build "DIFFÉRENTES du Dockerfile signé"
)
rc=$?   # pas de « || » : set -e doit rester actif dans la sous-coquille
set -e
[ "$rc" = 0 ] && res second_moteur "fait" || res second_moteur "ECHEC (code $rc)"
res sortie_invite_fin "$(tx)"
res porteuse_fin "$(for i in /sys/class/net/*; do [ "${i##*/}" = lo ] || printf '%s=%s ' "${i##*/}" "$(cat "$i/carrier" 2>/dev/null)"; done)"
res fin "$(date -u +%FT%TZ)"
