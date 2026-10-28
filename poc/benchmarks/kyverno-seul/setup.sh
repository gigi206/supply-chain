#!/usr/bin/env bash
# Prépare le banc : clés de test, une image par cas, signatures et attestations
# (bundles Sigstore en OCI referrers, sans journal de transparence) dans un
# registre local. Écrit $WORKDIR/images.tsv (cas, référence par digest).
#
# Variables : REG (défaut localhost:5000), WORKDIR (défaut ./work).
# Outils requis : cosign v3, crane, python3.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
REG="${REG:-localhost:5000}"
WORKDIR="${WORKDIR:-$here/work}"
export COSIGN_PASSWORD=""
cosign_opts=(--use-signing-config=false --tlog-upload=false --allow-http-registry --yes)

mkdir -p "$WORKDIR/keys"
for k in chains vsa rogue; do
  [ -f "$WORKDIR/keys/$k.key" ] || (cd "$WORKDIR/keys" && cosign generate-key-pair --output-key-prefix "$k" >/dev/null)
done

: > "$WORKDIR/images.tsv"
grep -v '^#' "$here/cases.tsv" | while IFS=$'\t' read -r case expected _; do
  dir="$WORKDIR/cases/$case"
  mkdir -p "$dir/layer"
  echo "$case" > "$dir/layer/case.txt"
  tar -C "$dir/layer" -cf "$dir/layer.tar" case.txt
  ref="$(crane append --oci-empty-base -f "$dir/layer.tar" -t "$REG/bench/$case:1" --insecure 2>/dev/null | tail -1)"

  python3 "$here/gen_predicates.py" "$case" "$dir"
  while IFS=$'\t' read -r ptype key file; do
    [ "$key" = "-" ] && continue
    if [ "$ptype" = "image" ]; then
      cosign sign --key "$WORKDIR/keys/$key.key" "${cosign_opts[@]}" "$ref" >/dev/null 2>&1
    else
      cosign attest --key "$WORKDIR/keys/$key.key" "${cosign_opts[@]}" \
        --type "$ptype" --predicate "$file" "$ref" >/dev/null 2>&1
    fi
  done < "$dir/plan.tsv"
  printf '%s\t%s\t%s\n' "$case" "$expected" "$ref" >> "$WORKDIR/images.tsv"
  echo "préparé : $case → $ref"
done
