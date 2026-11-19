#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# M1b, choix 2 : forme du manifeste de base du bootstrap (ee90dc0e), lue dans le cache OCI de s1.sh amorce sur l'hôte.
set -euo pipefail
B=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256
M=ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2
echo "# m1b-base-manifeste.sh, début $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "manifeste $M : $(wc -c < "$B/$M") octets, sha256 $(sha256sum < "$B/$M" | cut -c1-64)"
jq -r '"mediaType : \(.mediaType)", "couches : \([.layers[].digest] | join(" "))", "manifests (index) : \([.manifests[]?] | length)"' "$B/$M"
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
