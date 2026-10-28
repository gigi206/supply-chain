#!/usr/bin/env bash
# Brique 07a : SBOM (Hermeto + Syft) et scan Grype sans réseau, avec la base
# officielle archivée, puis porte de release (politiques du banc C).
#
# 1. Restaure la base Grype par digest et l'importe dans un cache vierge (sans réseau).
# 2. SBOM : celui de la fermeture (referrer de la fermeture Hermeto dans le registre)
#    fusionné avec celui de Syft sur le binaire (sans réseau).
# 3. Deux cas : « ok » (sample-app telle quelle) et « kev » (même SBOM plus
#    log4j-core 2.14.1, CVE-2021-44228 au catalogue KEV de la CISA).
# 4. Image de test par cas, signée et attestée (provenance, VSA, licences, scan),
#    évaluée par Conforma et Kyverno avec les politiques du banc C.
#    Attendu : ok → PASS ; kev → FAIL (kev_without_vex).
#
# Usage : DB_REF=<reg>/vulndb/grype@sha256:… CLOSURE_REF=<reg>/deps/sample-app@sha256:…
#         APP_BIN=…/sample-app REG=localhost:5000 WORKDIR=/tmp/b07 ./bench.sh
# Outils : syft, grype, oras, cosign v3, crane, ec, kyverno, python3, unshare.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
benchc=$(git -C "$here" rev-parse --show-toplevel)/poc/benchmarks/kyverno-seul
W=${WORKDIR:?}
REG=${REG:?}
: "${DB_REF:?}" "${CLOSURE_REF:?}" "${APP_BIN:?}"
SYFT=${SYFT:-syft} GRYPE=${GRYPE:-grype} ORAS=${ORAS:-oras}
read -r -a oras_opts <<<"${ORAS_OPTS:---plain-http}"
cosign_opts=(--use-signing-config=false --tlog-upload=false --allow-http-registry --yes)
export COSIGN_PASSWORD=""
ko=0
ms() { date +%s%3N; }

chmod -R u+w -- "$W" 2>/dev/null || true
rm -rf -- "${W:?}"
mkdir -p "$W"
cd "$W"
offline() { unshare -rn env GRYPE_DB_CACHE_DIR="$W/dbcache" GRYPE_DB_AUTO_UPDATE=false \
  GRYPE_DB_VALIDATE_AGE=false GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false "$@"; }

# 1. Base Grype restaurée par digest, importée sans réseau.
"$ORAS" pull "${oras_opts[@]}" --no-tty -o db "$DB_REF" >/dev/null
t0=$(ms)
offline "$GRYPE" db import db/vulnerability-db_*.tar.zst >/dev/null 2>&1
echo "base importée hors réseau en $(( ($(ms) - t0) / 1000 )) s : $(offline "$GRYPE" db status 2>/dev/null | grep -E 'Schema|Built' | tr -s ' ' | paste -sd' ')"

# 2. SBOM : referrer CycloneDX de la fermeture + Syft sur le binaire, fusionnés.
sbom=$("$ORAS" discover "${oras_opts[@]}" --format json --artifact-type application/vnd.cyclonedx+json "$CLOSURE_REF" |
  python3 -I -c 'import json, sys; d = json.load(sys.stdin); print((d.get("referrers") or d.get("manifests"))[0]["digest"])')
"$ORAS" pull "${oras_opts[@]}" --no-tty -o hermeto "${CLOSURE_REF%@*}@$sbom" >/dev/null
offline "$SYFT" scan "file:$APP_BIN" -o cyclonedx-json=syft.json -q
python3 -I "$here/sbom_merge.py" hermeto/bom.json syft.json > sbom-ok.json
python3 -I - sbom-ok.json sbom-kev.json <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))
b["components"].append({"type": "library", "name": "log4j-core", "version": "2.14.1",
                        "purl": "pkg:maven/org.apache.logging.log4j/log4j-core@2.14.1"})
json.dump(b, open(sys.argv[2], "w"), indent=2)
PY
echo "SBOM fusionné : $(python3 -I -c 'import json, sys; print(", ".join(c["purl"].split("?")[0] for c in json.load(open(sys.argv[1]))["components"]))' sbom-ok.json)"

# 3. Scans sans réseau et prédicats.
for c in ok kev; do
  t0=$(ms)
  offline "$GRYPE" "sbom:sbom-$c.json" -o json --file "grype-$c.json" -q
  python3 -I "$here/scan_predicate.py" "grype-$c.json" "$DB_REF" > "scan-$c.json"
  echo "scan $c en $(( $(ms) - t0 )) ms : $(python3 -I -c 'import json, sys
v = json.load(open(sys.argv[1]))["vulnerabilities"]
print(len(v), "vulnérabilités dont", sum(x["kev"] for x in v), "KEV :", ", ".join(sorted({c for x in v for c in x["kevCves"]})) or "-")' "scan-$c.json")"
done

# 4. Porte : images de test, signatures et attestations, Conforma et Kyverno.
mkdir -p keys
for k in chains vsa; do (cd keys && cosign generate-key-pair --output-key-prefix "$k" >/dev/null 2>&1); done
python3 -I "$benchc/gen_predicates.py" ok preds >/dev/null
python3 -I -c 'import json, sys; print(json.dumps({"bench_keys": {"vsa_public_key": open(sys.argv[1]).read()}}))' \
  keys/vsa.pub > conforma-data.json
mkdir -p conforma-data && mv conforma-data.json conforma-data/keys.json
cat > policy.yaml <<YAML
sources:
  - name: porte
    policy:
      - $benchc/conforma/policy
    data:
      - $benchc/conforma/data
      - $W/conforma-data
YAML
python3 -I - "$benchc/kyverno/ivpol.tmpl.yaml" keys/chains.pub keys/vsa.pub ivpol.yaml <<'PY'
import sys
tmpl = open(sys.argv[1]).read()
indent = lambda p: "\n".join(" " * 12 + l for l in open(p).read().strip().splitlines())
open(sys.argv[4], "w").write(tmpl.replace("__CHAINS_PUB__", indent(sys.argv[2])).replace("__VSA_PUB__", indent(sys.argv[3])))
PY
mkdir -p layer
cp "$APP_BIN" layer/sample-app
tar -C layer -cf layer.tar sample-app
for c in ok kev; do
  ref=$(crane append --oci-empty-base -f layer.tar -t "$REG/porte07a/$c:1" --insecure 2>/dev/null | tail -1)
  cosign sign --key keys/chains.key "${cosign_opts[@]}" "$ref" >/dev/null 2>&1
  cosign attest --key keys/chains.key "${cosign_opts[@]}" --type slsaprovenance1 --predicate preds/prov.json "$ref" >/dev/null 2>&1
  cosign attest --key keys/vsa.key "${cosign_opts[@]}" --type https://slsa.dev/verification_summary/v1 --predicate preds/vsa.json "$ref" >/dev/null 2>&1
  cosign attest --key keys/chains.key "${cosign_opts[@]}" --type https://supply-chain.example/licences/v1 --predicate preds/lic.json "$ref" >/dev/null 2>&1
  cosign attest --key keys/chains.key "${cosign_opts[@]}" --type https://supply-chain.example/scan/v1 --predicate "scan-$c.json" "$ref" >/dev/null 2>&1

  ec validate image --image "$ref" --public-key keys/chains.pub --policy policy.yaml --ignore-rekor \
    --output json > "ec-$c.json" 2>/dev/null && ec_res=PASS || ec_res=FAIL
  sed "s|__CASE__|$c|; s|__REF__|$ref|" "$benchc/kyverno/pod.tmpl.yaml" > "pod-$c.yaml"
  kyverno apply ivpol.yaml --resource "pod-$c.yaml" --policy-report --output-format json > "ky-$c.json" 2>/dev/null || true
  ky_res=$(python3 -I -c 'import json, re, sys
t = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1]).read()); i = t.find("{")
s = (json.loads(t[i:]) if i >= 0 else {}).get("summary", {})
print("ERREUR" if s.get("error") else "FAIL" if s.get("fail") else "PASS" if s.get("pass") else "?")' "ky-$c.json")
  motif=$(python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
print("; ".join(v.get("msg", "") for x in d.get("components", []) for v in x.get("violations", [])))' "ec-$c.json")
  attendu=PASS
  [ "$c" = kev ] && attendu=FAIL
  [ "$ec_res" = "$attendu" ] && [ "$ky_res" = "$attendu" ] && r=OK || { r=KO; ko=1; }
  echo "$r   porte, cas $c : attendu $attendu ; Conforma $ec_res ; Kyverno $ky_res${motif:+ ; motif : $motif}"
done
exit $ko
