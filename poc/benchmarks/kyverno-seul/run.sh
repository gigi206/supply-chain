#!/usr/bin/env bash
# Évalue les 17 cas du banc avec Conforma (ec validate image) et Kyverno
# (kyverno apply sur une ImageValidatingPolicy) et écrit resultats/resultats.md.
#
# Prérequis : ./setup.sh exécuté (même WORKDIR), registre local démarré.
# Outils : ec (Conforma), kyverno, python3.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="${WORKDIR:-$here/work}"
out="$here/resultats"
mkdir -p "$out" "$WORKDIR/logs" "$WORKDIR/conforma-data"

# Données Conforma dépendant des clés générées.
python3 -c 'import json,sys; print(json.dumps({"bench_keys": {"vsa_public_key": open(sys.argv[1]).read()}}))' \
  "$WORKDIR/keys/vsa.pub" > "$WORKDIR/conforma-data/keys.json"
cat > "$WORKDIR/policy.yaml" <<YAML
sources:
  - name: bench
    policy:
      - $here/conforma/policy
    data:
      - $here/conforma/data
      - $WORKDIR/conforma-data
YAML

# Politique Kyverno avec les clés injectées.
python3 - "$here/kyverno/ivpol.tmpl.yaml" "$WORKDIR/keys/chains.pub" "$WORKDIR/keys/vsa.pub" "$WORKDIR/ivpol.yaml" <<'PY'
import sys
tmpl = open(sys.argv[1]).read()
indent = lambda p: "\n".join(" " * 12 + l for l in open(p).read().strip().splitlines())
open(sys.argv[4], "w").write(tmpl.replace("__CHAINS_PUB__", indent(sys.argv[2])).replace("__VSA_PUB__", indent(sys.argv[3])))
PY

# Horloge monotone (/proc/uptime, au centième) : date +%s%3N suit l'horloge murale, qui peut reculer.
ms() { local u; read -r u _ < /proc/uptime; echo $(( 10 * 10#${u/./} )); }

{
  echo "| Cas | Attendu | Conforma | Kyverno | Conforma (ms) | Kyverno (ms) | Motif Conforma | Motif Kyverno |"
  echo "|---|---|---|---|---|---|---|---|"
} > "$out/resultats.md"

while IFS=$'\t' read -r case expected ref; do
  t0=$(ms)
  if ec validate image --image "$ref" --public-key "$WORKDIR/keys/chains.pub" --policy "$WORKDIR/policy.yaml" \
       --ignore-rekor --output json > "$WORKDIR/logs/conforma-$case.json" 2> "$WORKDIR/logs/conforma-$case.err"; then
    ec_res=PASS
  else
    ec_res=FAIL
  fi
  t1=$(ms)
  ec_msg="$(python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
    print("; ".join(v.get("msg", "") for c in d.get("components", []) for v in c.get("violations", []))[:120])
except Exception:
    print("")' "$WORKDIR/logs/conforma-$case.json")"

  sed "s|__CASE__|$case|; s|__REF__|$ref|" "$here/kyverno/pod.tmpl.yaml" > "$WORKDIR/pod-$case.yaml"
  t2=$(ms)
  kyverno apply "$WORKDIR/ivpol.yaml" --resource "$WORKDIR/pod-$case.yaml" --policy-report --output-format json \
    > "$WORKDIR/logs/kyverno-$case.json" 2> "$WORKDIR/logs/kyverno-$case.err" || true
  t3=$(ms)
  read -r ky_res ky_msg < <(python3 -c 'import json,re,sys
t = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1]).read())
i = t.find("{")
d = json.loads(t[i:]) if i >= 0 else {}
s = d.get("summary", {})
res = "ERREUR" if s.get("error") else ("FAIL" if s.get("fail") else ("PASS" if s.get("pass") else "INDÉTERMINÉ"))
msg = "; ".join((r.get("message") or "").replace("\n", " ") for r in d.get("results", []) if r.get("result") != "pass")
print(res, msg[:120])' "$WORKDIR/logs/kyverno-$case.json")

  printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' "$case" "$expected" "$ec_res" "$ky_res" \
    "$((t1 - t0))" "$((t3 - t2))" "${ec_msg//|/\\|}" "${ky_msg//|/\\|}" >> "$out/resultats.md"
done < "$WORKDIR/images.tsv"

echo "Résultats : $out/resultats.md"
