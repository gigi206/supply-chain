#!/usr/bin/env bash
# Brique 10, R5, mesure préalable (à intégrer à replay.sh après R4) : effet d'une VSA rangée en referrer de l'image réelle sur
# ce que la porte de la 08 (ec v0.10.42, politique de la porte) et cosign 3.1.4 chargent. Copie de l'image, de .sig et de .att
# en lecture anonyme, Zot jetable dans un espace de noms réseau vide ; aucune écriture dans le Zot du PoC ni dans le cluster.
set -euo pipefail
racine_depot=/home/gigi/Documents/git/github/gigi206/supply-chain
O=$HOME/.cache/supply-chain-poc/10
E=$O/essais/referrer-porte
ZOT_POC=192.168.161.13:5000
CA_POC=$O/ca-poc.crt
IMAGE=builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
CPOL=$HOME/.cache/supply-chain-poc/08/telechargements/conforma-policy
CPOL_COMMIT=ebd3fbd270297c15f590f4023360465ffb41d4fe
H=$racine_depot/poc/bricks/08-trust-plane
EC_BIN=895c6f7e63cfefe6257a2e54c052c3d90803e8127adf5a7eb13f245262859abf
d=${IMAGE#*@}; t=sha256-${d#sha256:}

rm -rf -- "${E:?}" && mkdir -p "$E/porte/regles" "$E/porte/donnees" "$E/politique" "$E/zot"
cd "$E"
echo "## outils"
[ "$(sha256sum < "$(command -v ec)" | cut -c1-64)" = "$EC_BIN" ] && echo "OK   ec : empreinte de l'image de la porte ($(ec version 2>/dev/null | sed -n 's/^Version *//p' | head -1))" \
  || { echo "KO   empreinte de ec" >&2; exit 1; }
echo "zot $(zot --version 2>&1 | grep -o '"commit":"[^"]*"') ; cosign $(cosign version 2>/dev/null | sed -n 's/^GitVersion: *//p') ; oras $(oras version | sed -n 's/^Version: *//p')"

echo "## copie en lecture anonyme : image, .sig, .att (Zot du PoC -> layout OCI)"
oras cp --from-ca-file "$CA_POC" "$ZOT_POC/$IMAGE" --to-oci-layout "$E/layout:image" > /dev/null
for x in sig att; do oras cp --from-ca-file "$CA_POC" "$ZOT_POC/${IMAGE%@*}:$t.$x" --to-oci-layout "$E/layout:$t.$x" > /dev/null; done
python3 -I -c 'import json,sys; [print("layout :", m["annotations"]["org.opencontainers.image.ref.name"], m["digest"]) for m in json.load(open(sys.argv[1]))["manifests"]]' "$E/layout/index.json"
curl -fsS --cacert "$CA_POC" "https://$ZOT_POC/v2/${IMAGE%@*}/referrers/$d" | python3 -I -c 'import json,sys; print("referrers de l image dans le Zot du PoC :", len(json.load(sys.stdin)["manifests"]))'

echo "## politique de la porte, chemins locaux"
git -C "$CPOL" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$E/politique"
cp "$H/politique/porte/porte.rego" "$E/porte/regles/" && cp "$H/politique/porte/taches.yml" "$E/porte/donnees/"
cp "$H/resultats/chains-cle-publique.pem" "$E/porte/chains.pub"
sed -e "s#/politique/#$E/politique/#" -e "s#/etc/porte/#$E/porte/#" "$H/politique/porte/policy.yaml" > "$E/porte/policy.yaml"
grep -nE '^\s+- /' "$E/porte/policy.yaml"
printf '{"distSpecVersion":"1.1.1","storage":{"rootDirectory":"%s/zot"},"http":{"address":"127.0.0.1","port":"15000"},"log":{"level":"error"}}\n' "$E" > zot.json

unshare -rn bash -s "$E" "$d" "$t" "$(command -v zot)" "$(command -v oras)" "$(command -v cosign)" "$(command -v ec)" <<'EOS'
set -uo pipefail
E=$1 d=$2 t=$3 zot=$4 oras=$5 cosign=$6 ec=$7; cd "$E"
export HOME=$E/home TMPDIR=$E/tmp; mkdir -p "$HOME" "$TMPDIR"
ip link set lo up
echo "## espace de noms : $(ip -o link | awk -F': ' '{print $2}' | paste -sd' ') ; routes : $(ip route | wc -l)"
"$zot" serve zot.json > zot.log 2>&1 & z=$!
for _ in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:15000/v2/ && break; sleep 0.5; done
R=127.0.0.1:15000/builds/sample-app
"$oras" cp --from-oci-layout "$E/layout:image" --to-plain-http "$R@$d" > /dev/null
for x in sig att; do "$oras" cp --from-oci-layout "$E/layout:$t.$x" --to-plain-http "$R:$t.$x" > /dev/null; done
for r in "$d" "$t.sig" "$t.att"; do echo "Zot jetable : $r -> $(curl -fsSI -H 'Accept: application/vnd.oci.image.manifest.v1+json' -H 'Accept: application/vnd.oci.image.index.v1+json' "http://127.0.0.1:15000/v2/builds/sample-app/manifests/$r" | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p')"; done

mesurer() { # libellé : ec avec la politique de la porte, puis cosign (signature d'image et attestations, clé de Chains)
  echo "## $1 : referrers de l'image : $(curl -fsS "http://127.0.0.1:15000/v2/builds/sample-app/referrers/$d" | python3 -I -c 'import json,sys; print([(m.get("artifactType"), m["digest"][:19]) for m in json.load(sys.stdin)["manifests"]])') ; tags : $(curl -fsS http://127.0.0.1:15000/v2/builds/sample-app/tags/list | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)["tags"]))')"
  local m
  for m in sans-source source; do # sans-source : ec comme en J6 (--image) ; source : comme aux tests 7 et 8 (--images, source attendue)
  if [ $m = source ]; then
    "$ec" validate image --images "{\"components\":[{\"name\":\"sample-app\",\"containerImage\":\"$R@$d\",\"source\":{\"git\":{\"url\":\"https://sc-stockage.poc.test:3000/workspace/sample-app.git\",\"revision\":\"6391fd437f26696847041be3226bbbf633f55a2f\"}}}]}" \
      --public-key porte/chains.pub --policy porte/policy.yaml --ignore-rekor --info --show-successes --output json="ec-$1-$m.json" --strict=false > "ec-$1-$m.out" 2> "ec-$1-$m.err"
  else
    "$ec" validate image --image "$R@$d" --public-key porte/chains.pub --policy porte/policy.yaml --ignore-rekor --info \
      --show-successes --output json="ec-$1-$m.json" --strict=false > "ec-$1-$m.out" 2> "ec-$1-$m.err"
  fi
  echo "ec ($m) : code de sortie $? ; récupérations d'images en échec (bundles de tâches, nom du PoC sans DNS ni réseau) : $(grep -c 'failed to fetch image' "ec-$1-$m.err")"
  python3 -I - "ec-$1-$m.json" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1]))
except Exception as e:
    print("ec : sortie JSON illisible :", e); sys.exit(0)
for c in r.get("components", []):
    sig = c.get("signatures") or []
    att = c.get("attestations") or []
    print("ec : success", c.get("success"), "; signatures d'image :", len(sig), [s.get("keyid", "")[:12] for s in sig])
    print("ec : attestations :", len(att), sorted({(a.get("predicateType"), tuple(s.get("keyid", "")[:12] for s in a.get("signatures") or [])) for a in att}))
    code = lambda x: (x.get("metadata") or {}).get("code")
    print("ec : violations :", sorted(code(v) for v in c.get("violations") or []))
    print("ec : avertissements :", sorted(code(v) for v in c.get("warnings") or []))
    print("ec : succès :", len(c.get("successes") or []), "; dont builtin :", sorted(code(v) for v in c.get("successes") or [] if str(code(v)).startswith("builtin")))
    for v in c.get("violations") or []:
        print("   violation", code(v), ":", str(v.get("msg"))[:160])
PY
  grep -v 'failed to fetch image' "ec-$1-$m.err" | grep -q . && echo "ec : autre stderr : $(grep -v 'failed to fetch image' "ec-$1-$m.err" | tail -3 | cut -c1-200 | paste -sd'|')"
  done
  "$cosign" verify --key porte/chains.pub --insecure-ignore-tlog --allow-http-registry "$R@$d" > c.out 2>&1
  echo "cosign verify (clé de Chains) : code $? ; $(grep -m1 -E '^Error|^Verification' c.out | cut -c1-180)"
  "$cosign" verify-attestation --key porte/chains.pub --insecure-ignore-tlog --type slsaprovenance1 --allow-http-registry "$R@$d" > c.out 2> c.err
  echo "cosign verify-attestation (clé de Chains, slsaprovenance1) : code $? ; attestations vérifiées : $(grep -c '^{' c.out) ; $(grep -m1 '^Error' c.err | cut -c1-180)"
}

mesurer avant

echo "## VSA jetable en referrer (comme R5 : attest-blob sans registre, oras attach, bundle v0.3)"
export COSIGN_PASSWORD=essai-jetable
mkdir cle && (cd cle && "$cosign" generate-key-pair > /dev/null 2>&1)
"$cosign" signing-config create --out vide.json > /dev/null 2>&1
python3 -I - "$d" <<'PY'
import json, sys
json.dump({"_type": "https://in-toto.io/Statement/v1",
           "subject": [{"name": "127.0.0.1:15000/builds/sample-app", "digest": {"sha256": sys.argv[1].split(":")[1]}}],
           "predicateType": "https://slsa.dev/verification_summary/v1",
           "predicate": {"verifier": {"id": "https://supply-chain.example/verifiers/essai-referrer-porte"}, "resourceUri": "essai",
                         "policy": {"uri": "essai"}, "verificationResult": "PASSED", "verifiedLevels": ["POC_ESSAI"]}},
          open("enonce.json", "w"))
PY
"$cosign" attest-blob --statement enonce.json --key cle/cosign.key --signing-config vide.json --bundle vsa.bundle.json --yes > /dev/null 2>&1
echo "attest-blob : code $?"
"$oras" attach --plain-http --artifact-type application/vnd.dev.sigstore.bundle.v0.3+json \
  --annotation dev.sigstore.bundle.content=dsse-envelope --annotation dev.sigstore.bundle.predicateType=https://slsa.dev/verification_summary/v1 \
  "$R@$d" vsa.bundle.json:application/vnd.dev.sigstore.bundle.v0.3+json 2>&1 | tail -1

mesurer apres
"$cosign" verify-attestation --key cle/cosign.pub --insecure-ignore-tlog --type https://slsa.dev/verification_summary/v1 --allow-http-registry "$R@$d" > c.out 2>&1
echo "témoin : cosign verify-attestation (clé jetable de la VSA) : code $?"
kill $z
EOS
echo "## fin $(date -u +%T) UTC"
