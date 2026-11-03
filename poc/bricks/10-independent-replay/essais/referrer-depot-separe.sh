#!/usr/bin/env bash
# Brique 10, R5, mesure préalable (suite de referrer-porte.sh, dont il reprend le layout et la politique locale) : VSA rangée
# en referrer dans un dépôt séparé (modèle de horodatage/bundles : manifeste fait main, sujet = descripteur de l'image),
# poussée par digest sans étiquette ; effet sur la porte (ec) et lecture par COSIGN_REPOSITORY. Zot jetable, réseau vide.
set -euo pipefail
O=$HOME/.cache/supply-chain-poc/10
E=$O/essais/referrer-porte
IMAGE=builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
d=${IMAGE#*@}; t=sha256-${d#sha256:}
[ -s "$E/layout/index.json" ] && [ -s "$E/porte/policy.yaml" ] || { echo "KO   layout ou politique absents (referrer-porte.sh d'abord)" >&2; exit 1; }
rm -rf -- "${E:?}/zot" "$E/home" "$E/tmp" "$E/separe" && mkdir -p "$E/zot" "$E/separe"
unshare -rn bash -s "$E" "$d" "$t" "$(command -v zot)" "$(command -v oras)" "$(command -v cosign)" "$(command -v ec)" <<'EOS'
set -uo pipefail
E=$1 d=$2 t=$3 zot=$4 oras=$5 cosign=$6 ec=$7; cd "$E"
export HOME=$E/home TMPDIR=$E/tmp; mkdir -p "$HOME" "$TMPDIR"
ip link set lo up
echo "## espace de noms : $(ip -o link | awk -F': ' '{print $2}' | paste -sd' ') ; routes : $(ip route | wc -l)"
"$zot" serve zot.json > zot.log 2>&1 & z=$!
for _ in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:15000/v2/ && break; sleep 0.5; done
Z=127.0.0.1:15000; R=$Z/builds/sample-app; V=$Z/builds/vsa/sample-app
"$oras" cp --from-oci-layout "$E/layout:image" --to-plain-http "$R@$d" > /dev/null
for x in sig att; do "$oras" cp --from-oci-layout "$E/layout:$t.$x" --to-plain-http "$R:$t.$x" > /dev/null; done
for r in "$d" "$t.sig" "$t.att"; do echo "Zot jetable : $r -> $(curl -fsSI -H 'Accept: application/vnd.oci.image.manifest.v1+json' -H 'Accept: application/vnd.oci.image.index.v1+json' "http://$Z/v2/builds/sample-app/manifests/$r" | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p')"; done

echo "## VSA jetable (attest-blob sans registre), rangée dans builds/vsa/sample-app par un manifeste fait main poussé par digest"
cd separe
export COSIGN_PASSWORD=essai-jetable
mkdir cle && (cd cle && "$cosign" generate-key-pair > /dev/null 2>&1)
"$cosign" signing-config create --out vide.json > /dev/null 2>&1
python3 -I - "$d" <<'PY'
import json, sys
json.dump({"_type": "https://in-toto.io/Statement/v1",
           "subject": [{"name": "127.0.0.1:15000/builds/sample-app", "digest": {"sha256": sys.argv[1].split(":")[1]}}],
           "predicateType": "https://slsa.dev/verification_summary/v1",
           "predicate": {"verifier": {"id": "https://supply-chain.example/verifiers/essai-depot-separe"}, "resourceUri": "essai",
                         "policy": {"uri": "essai"}, "verificationResult": "PASSED", "verifiedLevels": ["POC_ESSAI"]}},
          open("enonce.json", "w"))
PY
"$cosign" attest-blob --statement enonce.json --key cle/cosign.key --signing-config vide.json --bundle bundle.json --yes > /dev/null 2>&1
echo "attest-blob : code $?"
TYPE=application/vnd.dev.sigstore.bundle.v0.3+json
printf '{}' > vide.json.cfg
"$oras" blob push --plain-http "$V" bundle.json > /dev/null && "$oras" blob push --plain-http "$V" vide.json.cfg > /dev/null
curl -fsSI -H 'Accept: application/vnd.oci.image.manifest.v1+json' -H 'Accept: application/vnd.oci.image.index.v1+json' "http://$Z/v2/builds/sample-app/manifests/$d" \
  | tr -d '\r' | python3 -I -c 'import sys,json; h={l.split(": ",1)[0].lower(): l.split(": ",1)[1] for l in sys.stdin.read().splitlines() if ": " in l}; print(json.dumps({"mediaType": h["content-type"], "digest": h["docker-content-digest"], "size": int(h["content-length"])}))' > sujet.json
echo "sujet : $(cat sujet.json)"
printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s","config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:%s","size":2},"layers":[{"mediaType":"%s","digest":"sha256:%s","size":%s}],"subject":%s,"annotations":{"dev.sigstore.bundle.content":"dsse-envelope","dev.sigstore.bundle.predicateType":"https://slsa.dev/verification_summary/v1"}}' \
  "$TYPE" "$(sha256sum < vide.json.cfg | cut -c1-64)" "$TYPE" "$(sha256sum < bundle.json | cut -c1-64)" "$(wc -c < bundle.json)" "$(cat sujet.json)" > manifeste.json
m=sha256:$(sha256sum < manifeste.json | cut -c1-64)
"$oras" manifest push --plain-http "$V@$m" manifeste.json > p.out 2>&1; echo "push par digest ($m) : code $? ; $(tail -1 p.out)"
echo "referrers de $d dans builds/vsa/sample-app : $(curl -fsS "http://$Z/v2/builds/vsa/sample-app/referrers/$d" | python3 -I -c 'import json,sys; print([(m.get("artifactType"), m["digest"][:19]) for m in json.load(sys.stdin)["manifests"]])')"
echo "étiquettes de builds/vsa/sample-app : $(curl -s "http://$Z/v2/builds/vsa/sample-app/tags/list")"
echo "referrers de l'image dans builds/sample-app : $(curl -fsS "http://$Z/v2/builds/sample-app/referrers/$d" | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)["manifests"]))')"
cd "$E"

echo "## porte (ec, source attendue) sur l'image réelle"
"$ec" validate image --images "{\"components\":[{\"name\":\"sample-app\",\"containerImage\":\"$R@$d\",\"source\":{\"git\":{\"url\":\"https://sc-stockage.poc.test:3000/workspace/sample-app.git\",\"revision\":\"6391fd437f26696847041be3226bbbf633f55a2f\"}}}]}" \
  --public-key porte/chains.pub --policy porte/policy.yaml --ignore-rekor --info --show-successes --output json=separe/ec.json --strict=false > separe/ec.out 2> separe/ec.err
echo "ec : code de sortie $? ; récupérations d'images en échec (sans réseau) : $(grep -c 'failed to fetch image' separe/ec.err)"
python3 -I - separe/ec.json <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["components"][0]
code = lambda x: (x.get("metadata") or {}).get("code")
print("ec : success", c.get("success"), "; signatures d'image :", len(c.get("signatures") or []), "; attestations :", len(c.get("attestations") or []),
      "; violations :", sorted(code(v) for v in c.get("violations") or []), "; avertissements :", sorted(code(v) for v in c.get("warnings") or []),
      "; succès :", len(c.get("successes") or []))
PY
"$cosign" verify --key porte/chains.pub --insecure-ignore-tlog --allow-http-registry "$R@$d" > c.out 2>&1; echo "cosign verify (clé de Chains) : code $?"
"$cosign" verify-attestation --key porte/chains.pub --insecure-ignore-tlog --type slsaprovenance1 --allow-http-registry "$R@$d" > c.out 2> c.err
echo "cosign verify-attestation (clé de Chains) : code $? ; attestations vérifiées : $(grep -c '^{' c.out)"

echo "## lecture de la VSA par COSIGN_REPOSITORY=$V"
COSIGN_REPOSITORY=$V "$cosign" verify-attestation --key separe/cle/cosign.pub --insecure-ignore-tlog --type https://slsa.dev/verification_summary/v1 \
  --allow-http-registry "$R@$d" > c.out 2> c.err; echo "clé de la VSA : code $? ; attestations vérifiées : $(grep -c '^{' c.out) ; $(grep -m1 '^Error' c.err | cut -c1-160)"
COSIGN_REPOSITORY=$V "$cosign" verify-attestation --key porte/chains.pub --insecure-ignore-tlog --type https://slsa.dev/verification_summary/v1 \
  --allow-http-registry "$R@$d" > c.out 2> c.err; echo "clé de Chains : code $? ; $(grep -m1 '^Error' c.err | cut -c1-160)"
kill $z
EOS
echo "## fin $(date -u +%T) UTC"
