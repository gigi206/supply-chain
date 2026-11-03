#!/bin/bash
# Brique 10, R5, DANS LA VM, en root : contre-épreuves N1 et N2 sur des
# COPIES des entrées de R4 (~replay/r4/e : src, deps, image de build du domaine) ; originaux non touchés. Mêmes options de
# buildctl que rebuild.sh. Dossier ~replay/r5n, distinct de ~replay/r5 (VSA) : l'un n'efface jamais l'autre. Résultats :
# ~replay/r5n/n/resultat.txt (clé=valeur) ; rapports diffoscope de N2 dans ~replay/r5n/n ; journal ~replay/r5n/n.log.
#   N1  fermeture altérée : un octet changé dans un fichier .go du zip de go-chi/chi (zip réécrit, valide) ; refus attendu
#   N2  source altérée : ":8080" -> ":8081" dans main.go (littéral compilé ; main.Version est fixée par -ldflags) ; build
#       attendu, digest différent ; diffoscope de la couche et de la config contre l'image publiée (layout de R3)
set -euo pipefail
export LC_ALL=C
R3=/home/replay/r3 E=/home/replay/r4/e D=/home/replay/r5n N=/home/replay/r5n/n BK=/var/lib/replay-buildkit-n
[ -d "$D" ] || { echo "REFUS : $D absent (créé par l'étape negatifs)"; exit 1; }
exec > "$D/n.log" 2>&1
rm -rf -- "${N:?}" && mkdir -p "$N"
res() { echo "$1=$2" >> "$N/resultat.txt"; echo "$1=$2"; }
: > "$N/resultat.txt"
sujet=$(python3 -I -c 'import json,sys; print("sha256:" + json.load(open(sys.argv[1]))["subject"][0]["digest"]["sha256"])' "$R3/provenance.json")
b=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifests"][0]["digest"])' "$E/builder/index.json")
res image_de_build_domaine "$b"
rm -rf -- "${BK:?}" && mkdir -p /tmp/run-bk-n
buildkitd --oci-worker-snapshotter=native --addr unix:///tmp/run-bk-n/bk.sock --root "$BK" > "$N/buildkitd.log" 2>&1 &
k=$!
trap 'kill $k 2> /dev/null || true' EXIT
for _ in $(seq 30); do buildctl --addr unix:///tmp/run-bk-n/bk.sock debug workers > /dev/null 2>&1 && break; sleep 1; done
construire() { # cas src deps : image du cas dans $N/<cas>.tar ; code de sortie de buildctl
  buildctl --addr unix:///tmp/run-bk-n/bk.sock build --frontend dockerfile.v0 --no-cache --opt build-arg:SOURCE_DATE_EPOCH=0 \
    --local context="$2" --local dockerfile="$R3/recette" --opt filename=Dockerfile \
    --oci-layout magasin="$E/builder" --opt "context:builder=oci-layout://magasin@$b" \
    --local deps="$3" --opt context:deps=local:deps \
    --output type=oci,dest="$N/$1.tar",rewrite-timestamp=true > "$N/$1.build.log" 2>&1
}
digest() { tar -xOf "$N/$1.tar" index.json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["manifests"][0]["digest"])'; }

# --- N1 : un octet du contenu d'un fichier .go du zip de chi, zip réécrit (valide : seul go.sum peut le refuser)
cp -a "$E/deps" "$N/deps1"
z=$(find "$N/deps1" -path '*go-chi/chi/v5/@v/*.zip' | head -1)
python3 -I - "$z" <<'PY' >> "$N/resultat.txt"
import sys, zipfile
z = sys.argv[1]
entrees = [(i, zipfile.ZipFile(z).read(i.filename)) for i in zipfile.ZipFile(z).infolist()]
cible = next(n for n, (i, _) in enumerate(entrees) if i.filename.endswith(".go"))
i, d = entrees[cible]
entrees[cible] = (i, d[:-2] + bytes([d[-2] ^ 0x01]) + d[-1:])   # avant-dernier octet (fin du fichier, hors du code utile)
with zipfile.ZipFile(z + ".neuf", "w") as s:
    for i, d in entrees:
        s.writestr(i, d)
print(f"n1_altere={i.filename} (octet {len(d) - 2} sur {len(d)})")
PY
mv "$z.neuf" "$z"
python3 -I -c 'import sys,zipfile; print("n1_zip_valide=" + str(zipfile.ZipFile(sys.argv[1]).testzip() is None))' "$z" | tee -a "$N/resultat.txt"
if construire n1 "$E/src" "$N/deps1"; then
  res n1_build "RÉUSSI ($(digest n1))"
  [ "$(digest n1)" = "$sujet" ] && res n1_verdict PASSED || res n1_verdict FAILED
else
  res n1_build "refusé"
  res n1_motif "$(grep -m3 -E 'checksum mismatch|SECURITY ERROR|verifying|zip' "$N/n1.build.log" | tr -s ' \n' ' ' | cut -c1-300)"
  res n1_verdict FAILED
fi

# --- N2 : littéral compilé changé dans main.go
cp -a "$E/src" "$N/src2"
[ "$(grep -c '":8080"' "$N/src2/main.go")" = 1 ] || { res n2_verdict "REFUS : littéral \":8080\" non unique"; exit 1; }
sed -i 's/":8080"/":8081"/' "$N/src2/main.go"
res n2_altere "main.go : $(grep -n '":8081"' "$N/src2/main.go")"
if construire n2 "$N/src2" "$E/deps"; then
  res n2_build "réussi"
  res n2_image "$(digest n2)"
  [ "$(digest n2)" = "$sujet" ] && res n2_verdict PASSED || res n2_verdict FAILED
else
  res n2_build "ÉCHEC : $(tail -2 "$N/n2.build.log" | tr '\n' ' ' | cut -c1-200)"; exit 1
fi

# --- diffoscope : couche et config, image publiée (layout de R3, tag sujet) contre image de N2
mkdir -p "$N/pub" "$N/n2"
tar -xf "$N/n2.tar" -C "$N/n2"
python3 -I - "$R3/layout" "$N/n2" "$N" <<'PY'
import json, shutil, subprocess, sys
pub, n2, sortie = sys.argv[1:4]
def manifeste(layout, ref=None):
    idx = json.load(open(f"{layout}/index.json"))["manifests"]
    m = next(x for x in idx if ref is None or x.get("annotations", {}).get("org.opencontainers.image.ref.name") == ref)
    return json.load(open(f"{layout}/blobs/sha256/" + m["digest"].split(":")[1]))
for nom, layout, ref in (("pub", pub, "sujet"), ("n2", n2, None)):
    m = manifeste(layout, ref)
    print(f"{nom} : {len(m['layers'])} couche(s)")
    shutil.copy(f"{layout}/blobs/sha256/" + m["config"]["digest"].split(":")[1], f"{sortie}/{nom}.config.json")
    shutil.copy(f"{layout}/blobs/sha256/" + m["layers"][-1]["digest"].split(":")[1], f"{sortie}/{nom}.couche.tar.gz")
PY
for x in couche.tar.gz config.json; do
  set +e; diffoscope --max-text-report-size 200000 --text "$N/diffoscope-${x%%.*}.txt" "$N/pub.$x" "$N/n2.$x" > /dev/null 2>&1; rc=$?; set -e
  res "diffoscope_${x%%.*}" "code $rc ; $(wc -l < "$N/diffoscope-${x%%.*}.txt") lignes"
done
res fichiers_differents_couche "$(grep -oE '^│ (├|└)── [^ ]+' "$N/diffoscope-couche.txt" | sort -u | paste -sd' ' | cut -c1-300)"
res fin "$(date -u +%FT%TZ)"
