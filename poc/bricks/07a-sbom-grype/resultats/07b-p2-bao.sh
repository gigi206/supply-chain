#!/usr/bin/env bash
# Brique 07b, pièce 2, préparation du passage 21 : binaire bao 2.7.2 extrait de la copie de l'image OpenBao en miroir dans Zot
# (08, etape_image : digest épinglé, signature vérifiée). Lecture anonyme de Zot seulement ; aucune écriture dans Zot, le cluster
# ou les VM. Le binaire sert au banc de la tranche 3 (OpenBao jetable, mode dev, espace de noms réseau vide).
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/07a-sbom-grype/resultats/07b-p2-bao.sh > poc/bricks/07a-sbom-grype/resultats/07b-p2-bao.log 2>&1
set -euo pipefail
export LC_ALL=C
REG_HOTE=192.168.161.13:5000
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
MIROIR=amont/openbao/openbao
BAO_INDEX=sha256:5046911075e137e154ce49ab051502f4ec7cf367d484ae4a4dce665d9b90561f   # 2.7.2, index multi-plateforme signé (08)
BAO_AMD64=sha256:a78eb12a9fc7a3ebb4bec1724e2bdd6a28e33394820641d061166919a3f1866b
BAO_COMMIT=9e0a0d3c3504a0a00b45e61355afac5e35c78379   # tag v2.7.2
BAO_ID=https://github.com/openbao/openbao/.github/workflows/release-images.yml@refs/tags/v2.7.2
D=$HOME/.cache/supply-chain-poc/07a/bao-2.7.2
ko=0
ok() { echo "OK   $1"; }
[ ! -e "$D" ] || { echo "KO   $D existe déjà" >&2; exit 1; }
mkdir -p "$D/tmp"
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "outils : cosign $(cosign version 2>/dev/null | awk '/^GitVersion/ {print $2}'), crane $(crane version)"
SSL_CERT_FILE=$CA crane manifest "$REG_HOTE/$MIROIR@$BAO_INDEX" | jq -e --arg d "$BAO_AMD64" \
  '.manifests[] | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest == $d' > /dev/null \
  && ok "l'index signé référence le manifeste linux/amd64 $BAO_AMD64" || { echo "KO   manifeste amd64"; ko=1; }
if cosign verify --registry-cacert "$CA" --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity "$BAO_ID" \
  --certificate-github-workflow-sha "$BAO_COMMIT" --certificate-github-workflow-trigger release "$REG_HOTE/$MIROIR@$BAO_INDEX" > "$D/tmp/cosign.json" 2> "$D/tmp/cosign.err"; then
  ok "signature de $MIROIR@$BAO_INDEX dans Zot : $BAO_ID, commit $BAO_COMMIT, déclencheur release"
  grep -E '^  - ' "$D/tmp/cosign.err" || true
  echo "signatures vérifiées : $(jq length "$D/tmp/cosign.json")"
else
  echo "KO   signature"; tail -3 "$D/tmp/cosign.err" | cut -c1-300; ko=1
fi
SSL_CERT_FILE=$CA crane export "$REG_HOTE/$MIROIR@$BAO_AMD64" - | tar -xf - -C "$D/tmp" usr/bin/bao
mv "$D/tmp/usr/bin/bao" "$D/bao"
echo "bao : $(wc -c < "$D/bao") octets, sha256 $(sha256sum < "$D/bao" | cut -c1-64)"
v=$("$D/bao" version)
echo "$v"
case $v in "OpenBao v2.7.2 ($BAO_COMMIT)"*) ok "bao version : v2.7.2, commit du tag" ;; *) echo "KO   version"; ko=1 ;; esac
find "$D/tmp" -delete
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "## bilan : $ko"
exit $ko
