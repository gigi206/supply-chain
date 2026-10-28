#!/usr/bin/env bash
# Brique 02 : mesure de tools/index sur un registre peuplé d'artefacts synthétiques.
# Usage : REG=http://localhost:5000 WORKDIR=/tmp/b02 COUNT=10000 ./bench.sh
# Le registre peut aussi contenir de vraies attestations cosign (banc C) : elles
# sont indexées avec le reste.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tools=$(git -C "$here" rev-parse --show-toplevel)/tools/index
W=${WORKDIR:?}
REG=${REG:?}
mkdir -p "$W"
cd "$W"

t0=$(date +%s)
python3 -I "$tools/gen_synthetic.py" --registry "$REG" --count "${COUNT:-10000}" --out attendu.json
echo "génération : $(( $(date +%s) - t0 )) s"
python3 -I "$tools/index.py" --db idx.sqlite crawl --registry "$REG" --rebuild
python3 -I "$tools/index.py" --db idx.sqlite crawl --registry "$REG"
echo "taille de l'index : $(du -h idx.sqlite | cut -f1)"

canary=$(python3 -I -c 'import json; print(json.load(open("attendu.json"))["canary"])')
file=$(python3 -I -c 'import json; print(json.load(open("attendu.json"))["sample_file"])')
python3 -I "$tools/index.py" --db idx.sqlite built-with "$canary" > built.tsv
python3 -I - built.tsv attendu.json <<'PY'
import json, sys
got = {line.split("\t")[2] for line in open(sys.argv[1])}
want = set(json.load(open(sys.argv[2]))["built_with_canary"])
print("built-with (dépendance canari) :", "exact" if got == want else f"ÉCART {got ^ want}", f"({len(got)} artefacts)")
sys.exit(got != want)
PY
python3 -I "$tools/index.py" --db idx.sqlite attestations "${file#sha256:}"
