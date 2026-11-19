#!/usr/bin/env bash
# Brique 09, O4 : relevé local, sans réseau, sans lire 09/secrets.
#   1. date de création de l'image de l'amorce Debian 13 (configuration OCI, manifeste et configuration contrôlés par sha256) ;
#   2. clé publique du PoC : sha256 de o4/signer/cle-publique.asc et de o3/signer/cle-publique.asc, comparés à la valeur
#      archivée dans resultats/o2-cle.log (étape cle d'O2).
# Journal : resultats/o4-releve.log
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
BASE=$HOME/.cache/supply-chain-poc/09
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/library/debian
DEB_M=7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392
{
  echo "relevé commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o4-releve.sh $(sha256sum < "$here/o4-releve.sh" | cut -c1-16)…"
  python3 -I - "$OCI" "$DEB_M" <<'PY'
import hashlib, json, sys
o, m = sys.argv[1:3]
b = lambda d: f"{o}/blobs/sha256/{d}"
h = lambda d: hashlib.sha256(open(b(d), "rb").read()).hexdigest()
assert h(m) == m, "manifeste"
j = json.load(open(b(m)))
c = j["config"]["digest"][7:]
assert h(c) == c, "configuration"
k = json.load(open(b(c)))
print(f"OK   image de l'amorce : manifeste {m[:16]}…, configuration {c[:16]}… contrôlés ; created {k.get('created')}")
PY
  a=$(grep -o -E 'cle-publique\.asc : 600 [0-9]+ \(mode, octets\), sha256 [0-9a-f]{64}' "$R/o2-cle.log" | grep -o -E '[0-9a-f]{64}$')
  echo "clé publique dans o2-cle.log : ${a:-absente}"
  for f in "$BASE/o4/signer/cle-publique.asc" "$BASE/o3/signer/cle-publique.asc"; do
    s=$(sha256sum < "$f" | cut -c1-64)
    [ -n "$a" ] && [ "$s" = "$a" ] && echo "OK   ${f#"$BASE"/} : $s, égal à o2-cle.log" || echo "KO   ${f#"$BASE"/} : $s, différent de o2-cle.log"
  done
  echo "relevé fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | tee "$R/o4-releve.log"
k=$(grep -c '^KO' "$R/o4-releve.log" || true)
[ "$k" = 0 ]
