#!/usr/bin/env bash
# Brique 07b, ADR 0004, option 2b (« ajouter le CVSS au prédicat ») : la sortie JSON de Grype 0.104.1 porte-t-elle un CVSS pour
# les entrées de sample-app ? Lecture seule des deux sorties gardées par le banc de la 07c (étape 2, base vulndb/grype:2026-11-24,
# Grype hors ligne, ~/.cache/supply-chain-poc/07c/banc) : Go 1.26.10 (image 3a7ca1b1) et Go 1.26.11 (image f5e6bcb0).
# Rien n'est relancé : ni Grype, ni réseau, ni cluster, ni Zot.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
B=$HOME/.cache/supply-chain-poc/07c/banc
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
{
echo "# CVSS dans la sortie de Grype (ADR 0004, option 2b), $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
for v in 1.26.10 1.26.11; do
  f=$B/grype-$v.json
  echo "## Go $v : $(basename "$f"), sha256 $(sha256sum < "$f" | cut -c1-64), $(stat -c %s "$f") octets"
  jq -r '"grype \(.descriptor.version), base construite \(.descriptor.db.status.built)"' "$f"
  echo "  id | paquet | gravité | CVSS direct (version=score) | CVSS des vulnérabilités liées | EPSS (nombre)"
  jq -r '.matches[] | "  \(.vulnerability.id) | \(.artifact.name)@\(.artifact.version) | \(.vulnerability.severity) | \([.vulnerability.cvss[]? | "\(.version)=\(.metrics.baseScore)"] | join(" ")) | \([.relatedVulnerabilities[]? | select((.cvss // []) | length > 0) | "\(.id):" + ([.cvss[] | "\(.version)=\(.metrics.baseScore)"] | join("/"))] | join(" ")) | \((.vulnerability.epss // []) | length)"' "$f"
  echo "  entrées $(jq '.matches | length' "$f") ; avec CVSS direct $(jq '[.matches[] | select((.vulnerability.cvss // []) | length > 0)] | length' "$f") ; sans CVSS direct mais avec un CVSS lié $(jq '[.matches[] | select(((.vulnerability.cvss // []) | length) == 0 and ([.relatedVulnerabilities[]? | (.cvss // [])[]] | length) > 0)] | length' "$f") ; sans aucun CVSS $(jq '[.matches[] | select(((.vulnerability.cvss // []) | length) == 0 and ([.relatedVulnerabilities[]? | (.cvss // [])[]] | length) == 0)] | length' "$f")"
  echo "  versions de CVSS directes : $(jq -r '[.matches[].vulnerability.cvss[]?.version] | group_by(.) | map("\(.[0]) ×\(length)") | join(", ")' "$f")"
done
f=$B/grype-1.26.11.json
attendu "f5e6bcb0 : version de Grype" "$(jq -r .descriptor.version "$f")" 0.104.1
attendu "f5e6bcb0 : entrées" "$(jq '.matches | length' "$f")" 5
attendu "f5e6bcb0 : entrées avec CVSS direct" "$(jq '[.matches[] | select((.vulnerability.cvss // []) | length > 0)] | length' "$f")" 3
attendu "f5e6bcb0 : entrées sans CVSS direct, avec un CVSS lié" "$(jq '[.matches[] | select(((.vulnerability.cvss // []) | length) == 0 and ([.relatedVulnerabilities[]? | (.cvss // [])[]] | length) > 0)] | length' "$f")" 2
attendu "f5e6bcb0 : entrées sans aucun CVSS" "$(jq '[.matches[] | select(((.vulnerability.cvss // []) | length) == 0 and ([.relatedVulnerabilities[]? | (.cvss // [])[]] | length) == 0)] | length' "$f")" 0
attendu "f5e6bcb0 : versions de CVSS mélangées (directes et liées)" "$(jq -r '[.matches[] | (.vulnerability.cvss[]?, .relatedVulnerabilities[]?.cvss[]?) | .version] | unique | join(",")' "$f")" "3.1,4.0"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
cat "$J"
