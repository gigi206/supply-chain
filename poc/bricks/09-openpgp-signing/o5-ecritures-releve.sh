#!/usr/bin/env bash
# Brique 09, O5 réel, carte des écritures : relevé local, sans réseau ni cluster.
#   1. certificat TLS d'OpenBao (08/pki) : noms couverts et date de fin seulement, jamais le certificat ;
#   2. stockage.sh (08) : bloc htpasswd de poc-replay (modèle du bloc proposé pour poc-lien), lignes et empreinte ;
#   3. 07a : dépôt des referrers du scanner, distinct du dépôt de l'image (précédent pour signes/**).
# Journal : resultats/o5-ecritures-releve.log
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$here" rev-parse --show-toplevel)
ST=$TOP/poc/bricks/08-trust-plane/stockage.sh
G=$TOP/poc/bricks/07a-sbom-grype/plateforme.sh
{
  echo "relevé commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-ecritures-releve.sh $(sha256sum < "$here/o5-ecritures-releve.sh" | cut -c1-16)…"
  echo "### certificat TLS d'OpenBao (noms et fin de validité seulement)"
  openssl x509 -in "$HOME/.cache/supply-chain-poc/08/pki/openbao.crt" -noout -ext subjectAltName -enddate | sed 's/^ */     /'
  echo "### stockage.sh (08), $(git -C "$TOP" log -1 --format=%h -- "$ST") : bloc de poc-replay"
  grep -n -E 'poc-replay|h10' "$ST" | sed 's/^/     /'
  grep -n -E 'motif le plus long|accessControl' "$ST" | cut -c1-200 | sed 's/^/     /'
  echo "### 07a : dépôt des referrers du scanner"
  grep -n -E '^DEPOT_SCAN=|^IMAGE=|referrers de l.image dans' "$G" | cut -c1-200 | sed 's/^/     /'
  echo "relevé fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | tee "$here/resultats/o5-ecritures-releve.log"
