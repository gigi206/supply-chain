#!/usr/bin/env bash
# Brique 09, O6-M0 (carte : resultats/o6-carte.md ; prédictions : resultats/o6-porte-banc-predictions.md) : la porte de la 08 telle
# quelle (ec v0.10.42, empreinte de l'image de la porte ; politique de la porte en chemins locaux) sur des copies des quatre objets
# de signes/** et de leurs referrers, dans un Zot jetable, dans un espace de noms réseau vide (unshare -rn, sans sudo), comme la
# mesure R5 de la brique 10 (10-independent-replay/essais/referrer-porte.sh). ec avec la clé de Chains, puis avec la clé lien ;
# cosign verify-attestation du type lien avec les deux clés. Lecture anonyme du Zot du PoC ; clés publiques archivées ; ni secret,
# ni redirection de port, ni écriture dans le Zot du PoC ou dans le cluster. Aucun effacement : le dossier du banc est effacé à la
# main, par chemin littéral, après archivage.
# Usage : mise exec -- poc/bricks/09-openpgp-signing/o6-porte-banc.sh   (journal : resultats/o6-porte-banc.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
H08=$(cd "$here/../08-trust-plane" && pwd)
E=$HOME/.cache/supply-chain-poc/09/o6-porte-banc
ZOT_POC=192.168.161.13:5000
CA_POC=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
CPOL=$HOME/.cache/supply-chain-poc/08/telechargements/conforma-policy
CPOL_COMMIT=ebd3fbd270297c15f590f4023360465ffb41d4fe
EC_BIN=895c6f7e63cfefe6257a2e54c052c3d90803e8127adf5a7eb13f245262859abf
TYPE=https://supply-chain.example/lien-openpgp/v1
OBJETS=(sample-app-rpm@sha256:fa5b175786dcaf0cbd989b7e7098c6306e3d66427d4cf6ae2f3ecb1fd857a283
sample-app-deb@sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e
depot-rpm@sha256:ed666ab80dd15b871b45c4bbba2295146fa395a8e4bd6d1bafe066b2cb97b915
depot-apt@sha256:90909a869321b2455693408a394114725e5d9f2d75e723c9ecda811e2cc2630a)
[ ! -e "$E" ] || { echo "KO   $E existe déjà" >&2; exit 1; }
mkdir -p "$E/porte/regles" "$E/porte/donnees" "$E/politique" "$E/zot"
{
echo "## début $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o6-porte-banc.sh $(sha256sum < "$0" | cut -c1-16)…"
echo "## outils"
if [ "$(sha256sum < "$(command -v ec)" | cut -c1-64)" = "$EC_BIN" ]; then echo "OK   ec : empreinte de l'image de la porte ($(ec version 2>/dev/null | sed -n 's/^Version *//p' | head -1))"
else echo "KO   empreinte de ec ($(command -v ec)) : lancer par mise exec --" >&2; exit 1; fi
echo "zot $(zot --version 2>&1 | grep -o '"commit":"[^"]*"') ; cosign $(cosign version 2>/dev/null | sed -n 's/^GitVersion: *//p') ; oras $(oras version | sed -n 's/^Version: *//p')"

echo "## copie en lecture anonyme, referrers compris (Zot du PoC -> layout OCI)"
for o in "${OBJETS[@]}"; do
  n=${o%@*} d=${o#*@}
  oras cp -r --from-ca-file "$CA_POC" "$ZOT_POC/signes/$o" --to-oci-layout "$E/layout:$n" > /dev/null
  curl -fsS --cacert "$CA_POC" "https://$ZOT_POC/v2/signes/$n/referrers/$d" \
    | python3 -I -c 'import json,sys; print("Zot du PoC :", sys.argv[1], "referrers", [(m.get("artifactType"), m["digest"][:19]) for m in json.load(sys.stdin)["manifests"]])' "$n"
done

echo "## politique de la porte, chemins locaux ; clés publiques archivées"
git -C "$CPOL" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$E/politique"
cp "$H08/politique/porte/porte.rego" "$E/porte/regles/" && cp "$H08/politique/porte/taches.yml" "$E/porte/donnees/"
cp "$H08/resultats/chains-cle-publique.pem" "$E/porte/chains.pub"
cp "$here/resultats/lien-cle-publique.pem" "$E/porte/lien.pub"
sed -e "s#/politique/#$E/politique/#" -e "s#/etc/porte/#$E/porte/#" "$H08/politique/porte/policy.yaml" > "$E/porte/policy.yaml"
grep -nE '^\s+- /' "$E/porte/policy.yaml"
for k in chains lien; do echo "clé $k : SPKI sha256 $(openssl pkey -pubin -in "$E/porte/$k.pub" -outform DER 2>/dev/null | sha256sum | cut -c1-16)…"; done
printf '{"distSpecVersion":"1.1.1","storage":{"rootDirectory":"%s/zot"},"http":{"address":"127.0.0.1","port":"15000"},"log":{"level":"error"}}\n' "$E" > "$E/zot-banc.json"

unshare -rn bash -s "$E" "$TYPE" "$(command -v zot)" "$(command -v oras)" "$(command -v cosign)" "$(command -v ec)" "${OBJETS[@]}" <<'EOS'
set -uo pipefail
E=$1 TYPE=$2 zot=$3 oras=$4 cosign=$5 ec=$6; shift 6; cd "$E"
export HOME=$E/home TMPDIR=$E/tmp; mkdir -p "$HOME" "$TMPDIR"
ip link set lo up
echo "## espace de noms : $(ip -o link | awk -F': ' '{print $2}' | paste -sd' ') ; routes : $(ip route | wc -l)"
"$zot" serve zot-banc.json > zot.log 2>&1 & z=$!
for _ in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:15000/v2/ && break; sleep 0.5; done
Z=127.0.0.1:15000
for o in "$@"; do
  n=${o%@*} d=${o#*@} R=$Z/signes/${o%@*}
  "$oras" cp -r --from-oci-layout "$E/layout:$n" --to-plain-http "$R@$d" > /dev/null
  echo "### $n"
  echo "Zot jetable : $d -> $(curl -fsSI -H 'Accept: application/vnd.oci.image.manifest.v1+json' "http://$Z/v2/signes/$n/manifests/$d" | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p')"
  curl -fsS "http://$Z/v2/signes/$n/referrers/$d" \
    | python3 -I -c 'import json,sys; print("Zot jetable : referrers", [(m.get("artifactType"), m["digest"][:19]) for m in json.load(sys.stdin)["manifests"]])'
  for k in chains lien; do
    "$ec" validate image --image "$R@$d" --public-key "porte/$k.pub" --policy porte/policy.yaml --ignore-rekor --info \
      --show-successes --output json="ec-$n-$k.json" --strict=false > "ec-$n-$k.out" 2> "ec-$n-$k.err"
    echo "ec (clé $k) : code de sortie $? ; récupérations d'images en échec : $(grep -c 'failed to fetch image' "ec-$n-$k.err")"
    python3 -I - "ec-$n-$k.json" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1]))
except Exception as e:
    print("ec : sortie JSON illisible :", e); sys.exit(0)
for c in r.get("components", []):
    sig = c.get("signatures") or []
    att = c.get("attestations") or []
    print("ec : success", c.get("success"), "; signatures d'image :", len(sig), [s.get("keyid", "")[:12] for s in sig])
    print("ec : attestations :", len(att), sorted({(a.get("type"), a.get("predicateType"), len(a.get("signatures") or [])) for a in att}, key=str))
    code = lambda x: (x.get("metadata") or {}).get("code")
    print("ec : violations :", sorted(str(code(v)) for v in c.get("violations") or []))
    print("ec : avertissements :", sorted(str(code(v)) for v in c.get("warnings") or []))
    print("ec : succès :", len(c.get("successes") or []), "; dont builtin :", sorted(str(code(v)) for v in c.get("successes") or [] if str(code(v)).startswith("builtin")))
    for v in c.get("violations") or []:
        print("   violation", code(v), ":", str(v.get("msg"))[:160])
PY
    grep -v 'failed to fetch image' "ec-$n-$k.err" | grep -q . && echo "ec : autre stderr : $(grep -v 'failed to fetch image' "ec-$n-$k.err" | tail -3 | cut -c1-200 | paste -sd'|')"
    "$cosign" verify-attestation --key "porte/$k.pub" --type "$TYPE" --insecure-ignore-tlog=true --new-bundle-format --allow-http-registry \
      "$R@$d" > "c-$n-$k.out" 2> "c-$n-$k.err"
    echo "cosign verify-attestation --new-bundle-format (clé $k, type lien) : code $? ; enveloppes : $(grep -c '^{' "c-$n-$k.out") ; $(grep -m1 '^Error' "c-$n-$k.err" | cut -c1-180)"
  done
done
kill "$z" 2> /dev/null; wait "$z" 2> /dev/null
true
EOS
echo "## fin $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "à effacer après archivage (chemin littéral) : $E"
} 2>&1 | tee "$here/resultats/o6-porte-banc.log"
