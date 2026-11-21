#!/usr/bin/env bash
# Brique 07b, tranche 2 : VEX à blanc. Rien de partagé : aucune écriture dans le vrai Zot, le cluster ou les VM ; aucun réseau.
#   1. grype --vex hors réseau (unshare -rn), base archivée de G0 (04/11) lue sans modification, sur l'image archivée de sample-app
#      (oci-dir, digest du scan signé réel), sur le SBOM CycloneDX fusionné et sur un SBOM syft-json de l'image : correspondances
#      et entrées ignorées comparées aux prédictions (07b-t2-predictions.md) ; PURL divergents (Syft, Hermeto) ;
#   2. Zot et clé jetables dans un espace de noms réseau vide (127.0.0.1, comme G6) : VEX signé en attest-blob, publié en
#      referrer, relu par verify-attestation (clé jetable, puis clé étrangère), puis rendu à Grype.
# Les VEX sont des témoins (07b-t2-vex.py) : aucune analyse d'atteignabilité ne les fonde.
# Usage (racine du dépôt, outils de mise.toml) : poc/bricks/07a-sbom-grype/resultats/07b-t2-banc.sh > <journal>
set -euo pipefail
export LC_ALL=C
R=poc/bricks/07a-sbom-grype/resultats
G0=$HOME/.cache/supply-chain-poc/07a/g0
T=$HOME/.cache/supply-chain-poc/07a/t2-banc
D=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
VULN=GHSA-mqqf-5wvp-8fh8
SYFT='pkg:golang/github.com/go-chi/chi@v5.2.3#v5'
HERMETO='pkg:golang/github.com/go-chi/chi/v5@v5.2.3?type=module'
PROD=pkg:oci/sample-app@$D
OPENVEX=https://openvex.dev/ns/v0.2.0
REG=127.0.0.1:15001

vex() { python3 -I "$R/07b-t2-vex.py" "$@"; }
KO=0
ok() { echo "OK   $1"; }
ko() { echo "KO   $1"; KO=$((KO + 1)); }
# hors réseau : unshare -rn, sauf dans l'espace de noms vide de la partie 2, qui n'a déjà que lo
offline() {
  set -- env GRYPE_DB_CACHE_DIR="$G0/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
    GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false TMPDIR="$T/tmp" "$@"
  if [ -n "${DANS_NS:-}" ]; then "$@"; else unshare -rn "$@"; fi
}
lancer() { # nom entrée [fichier-vex] : sortie de Grype dans $T/<nom>.json, code dans $T/<nom>.code
  local n=$1 e=$2 v=${3:-} c=0
  if [ -n "$v" ]; then offline grype "$e" --vex "$v" -o json > "$T/$n.json" 2> "$T/$n.err" || c=$?
  else offline grype "$e" -o json > "$T/$n.json" 2> "$T/$n.err" || c=$?; fi
  echo "$c" > "$T/$n.code"
}
juger() { # nom attendu : attendu « m/i », « refus » ou « refus|5/0 »
  local n=$1 a=$2 r c
  c=$(cat "$T/$n.code")
  if [ "$c" = 0 ]; then r=$(jq -r '"\(.matches | length)/\(.ignoredMatches // [] | length)"' "$T/$n.json")
  else r="refus"; echo "     $n, code $c : $(grep -o 'ERROR.*' "$T/$n.err" | head -1 | cut -c1-400 | sed "s|$T|<banc>|g")"; fi
  case "|$a|" in *"|$r|"*) ok "$n : $r" ;; *) ko "$n : $r, prédit $a" ;; esac
}
cas() { lancer "$1" "$3" "${4:-}"; juger "$1" "$2"; }

# 2. Dans l'espace de noms réseau vide : Zot jetable, clés jetables, VEX signé, publié, relu.
if [ "${1:-}" = ns ]; then
  ip link set lo up
  zot serve "$T/zot.json" > "$T/zot.out" 2>&1 & zp=$!
  # shellcheck disable=SC2064   # développement à la pose, voulu
  trap "kill $zp 2>/dev/null || true" EXIT
  for _ in $(seq 40); do curl -fsS --cacert "$T/zot.crt" "https://$REG/v2/" > /dev/null 2>&1 && break; sleep 0.25; done
  export SSL_CERT_FILE=$T/zot.crt DOCKER_CONFIG=$T/docker
  crane push "$G0/image" "$REG/builds/sample-app:base" > /dev/null 2> "$T/crane.err"
  crane digest "$REG/builds/sample-app:base" > "$T/image-poussee" 2>> "$T/crane.err" || true
  cd "$T/cle"
  COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix temoin > /dev/null 2>&1
  COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix etrangere > /dev/null 2>&1
  cd "$T"
  cosign signing-config create --out vide.json > cosign.log 2>&1
  COSIGN_PASSWORD='' cosign attest-blob --key cle/temoin.key --signing-config vide.json --predicate vex-signe.json --type "$OPENVEX" \
    --bundle bundle.json --hash "${D#sha256:}" --yes sample-app >> cosign.log 2>&1
  oras manifest fetch --ca-file zot.crt --descriptor "$REG/builds/sample-app@$D" > sujet.json
  printf '{}' > config-vide.json
  oras blob push --ca-file zot.crt "$REG/builds/vex/sample-app" config-vide.json > /dev/null
  oras blob push --ca-file zot.crt "$REG/builds/vex/sample-app" bundle.json > /dev/null
  TYPE=application/vnd.dev.sigstore.bundle.v0.3+json
  printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s",%s,%s,%s,%s}' "$TYPE" \
    '"config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2}' \
    "\"layers\":[{\"mediaType\":\"$TYPE\",\"digest\":\"sha256:$(sha256sum < bundle.json | cut -c1-64)\",\"size\":$(wc -c < bundle.json)}]" \
    "\"subject\":$(cat sujet.json)" \
    "\"annotations\":{\"dev.sigstore.bundle.content\":\"dsse-envelope\",\"dev.sigstore.bundle.predicateType\":\"$OPENVEX\"}" > manifeste.json
  oras manifest push --ca-file zot.crt "$REG/builds/vex/sample-app@sha256:$(sha256sum < manifeste.json | cut -c1-64)" manifeste.json > /dev/null
  # API des referrers lue directement, comme entrees-scan : le sujet n'est pas dans builds/vex/sample-app
  echo "     referrers de l'image sous builds/vex/sample-app : $(curl -fsS --cacert zot.crt "https://$REG/v2/builds/vex/sample-app/referrers/$D" \
    | jq -r '.manifests | "\(length), artifactType \(map(.artifactType) | unique | join(","))"')"
  for k in temoin etrangere; do
    c=0
    COSIGN_REPOSITORY=$REG/builds/vex/sample-app cosign verify-attestation --key "cle/$k.pub" --insecure-ignore-tlog --type "$OPENVEX" \
      --registry-cacert zot.crt "$REG/builds/sample-app@$D" > "verifiees-$k" 2> "erreur-$k" || c=$?
    echo "$k|$c|$(grep -c '^{' "verifiees-$k" || true)" >> verification.tsv
  done
  { grep '^{' verifiees-temoin | head -1 | jq -r .payload | base64 -d > enonce.json; } 2> /dev/null || true
  if [ -s enonce.json ]; then
    jq .predicate enonce.json > vex-relu.json
    jq -r '"     énoncé relu : predicateType \(.predicateType), sujet \(.subject[0].digest.sha256[0:12])…"' enonce.json
  fi
  # Source registry: (le Zot jetable) : jugée par la partie principale après le retour
  export DANS_NS=1
  RI=registry:$REG/builds/sample-app@$D
  lancer reg-ref "$RI"
  lancer reg-bon "$RI" syft-exact.vex
  lancer reg-nu "$RI" reg-nu.vex
  lancer reg-autre-digest "$RI" autre-digest.vex
  lancer reg-autre-nom "$RI" autre-nom.vex
  lancer reg-produit-texte "$RI" produit-texte.vex
  exit 0
fi

empreinte() { find "$G0/dbcache" "$G0/image" -printf '%p %s %T@\n' | sort | sha256sum | cut -c1-16; }

[ ! -e ~/.cache/supply-chain-poc/07a/t2-banc ] || { chmod -R u+w ~/.cache/supply-chain-poc/07a/t2-banc; find ~/.cache/supply-chain-poc/07a/t2-banc -delete; }
trap 'chmod -R u+w ~/.cache/supply-chain-poc/07a/t2-banc; find ~/.cache/supply-chain-poc/07a/t2-banc -delete' EXIT
(umask 077 && mkdir -p "$T/cle" "$T/docker" "$T/tmp")
echo '{}' > "$T/docker/config.json"
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "outils : grype $(grype version 2>/dev/null | awk '/^Version/ {print $2}'), syft $(syft version 2>/dev/null | awk '/^Version/ {print $2}'),\
 cosign $(cosign version 2>/dev/null | awk '/^GitVersion/ {print $2}'), zot $(zot --version 2>&1 | grep -o 'v[0-9][0-9.]*' | head -1)"
echo "base : $(jq -r '"\(.schemaVersion), construite \(.built), \(.checksum[0:23])…"' "$G0/latest.json") ; script 07b-t2-vex.py $(sha256sum < "$R/07b-t2-vex.py" | cut -c1-16)…"
echo "SBOM fusionné de G0 : $(sha256sum < "$G0/sbom-ok.json" | cut -c1-16)… ; image : $(jq -r '.manifests[0].digest' "$G0/image/index.json")"
avant=$(empreinte)

echo "## 1. grype --vex hors réseau"
I=oci-dir:$G0/image
cas ref 5/0 "$I"
jq -r '.matches[] | "     \(.vulnerability.id) \(.vulnerability.severity) \(.artifact.purl)"' "$T/ref.json"
vex openvex "$T/syft-exact.vex" "$VULN" "$PROD" "$SYFT" not_affected;                                   cas syft-exact 4/1 "$I" "$T/syft-exact.vex"
jq -c '.ignoredMatches[0] | {id: .vulnerability.id, purl: .artifact.purl, appliedIgnoreRules}' "$T/syft-exact.json" | sed 's/^/     forme : /'
vex openvex "$T/hermeto.vex" "$VULN" "$PROD" "$HERMETO" not_affected;                                   cas hermeto 5/0 "$I" "$T/hermeto.vex"
vex openvex "$T/v5-nu.vex" "$VULN" "$PROD" 'pkg:golang/github.com/go-chi/chi/v5@v5.2.3' not_affected;   cas v5-nu 5/0 "$I" "$T/v5-nu.vex"
vex openvex "$T/sans-subpath.vex" "$VULN" "$PROD" 'pkg:golang/github.com/go-chi/chi@v5.2.3' not_affected; cas sans-subpath 4/1 "$I" "$T/sans-subpath.vex"
vex openvex "$T/sans-version.vex" "$VULN" "$PROD" 'pkg:golang/github.com/go-chi/chi#v5' not_affected;   cas sans-version 4/1 "$I" "$T/sans-version.vex"
vex openvex "$T/autre-version.vex" "$VULN" "$PROD" 'pkg:golang/github.com/go-chi/chi@v5.2.2#v5' not_affected; cas autre-version 5/0 "$I" "$T/autre-version.vex"
vex openvex "$T/autre-digest.vex" "$VULN" "pkg:oci/sample-app@sha256:$(printf '0%.0s' $(seq 64))" "$SYFT" not_affected
cas autre-digest 5/0 "$I" "$T/autre-digest.vex"
vex openvex "$T/autre-nom.vex" "$VULN" "pkg:oci/autre-app@$D" "$SYFT" not_affected;                     cas autre-nom 5/0 "$I" "$T/autre-nom.vex"
vex openvex "$T/autre-vuln.vex" GHSA-0000-0000-0000 "$PROD" "$SYFT" not_affected;                        cas autre-vuln 5/0 "$I" "$T/autre-vuln.vex"
vex openvex "$T/alias-cve.vex" CVE-2025-69725 "$PROD" "$SYFT" not_affected;                              cas alias-cve 4/1 "$I" "$T/alias-cve.vex"
vex openvex "$T/affected.vex" "$VULN" "$PROD" "$SYFT" affected;                                          cas affected 5/0 "$I" "$T/affected.vex"
vex openvex "$T/under-investigation.vex" "$VULN" "$PROD" "$SYFT" under_investigation;                    cas under-investigation 5/0 "$I" "$T/under-investigation.vex"
vex openvex "$T/fixed.vex" "$VULN" "$PROD" "$SYFT" fixed;                                                cas fixed 4/1 "$I" "$T/fixed.vex"
Z=sha256:$(printf '0%.0s' $(seq 64))
vex openvex "$T/autre-tout.vex" "$VULN" "pkg:oci/autre-app@$Z" "$SYFT" not_affected;                     cas autre-tout 4/1 "$I" "$T/autre-tout.vex"
vex openvex "$T/autre-tout-sans-sous.vex" "$VULN" "pkg:oci/autre-app@$Z" - not_affected;                 cas autre-tout-sans-sous 4/1 "$I" "$T/autre-tout-sans-sous.vex"
vex openvex "$T/produit-texte.vex" "$VULN" n-importe-quoi - not_affected;                                cas produit-texte 4/1 "$I" "$T/produit-texte.vex"
vex openvex "$T/autre-sous.vex" "$VULN" "$PROD" pkg:golang/stdlib@1.26.10 not_affected;                  cas autre-sous 5/0 "$I" "$T/autre-sous.vex"
vex openvex "$T/alias-liste.vex" CVE-2025-69725 "$PROD" "$SYFT" not_affected "$VULN";                    cas alias-liste 4/1 "$I" "$T/alias-liste.vex"
cas sbom-fusionne refus "sbom:$G0/sbom-ok.json" "$T/syft-exact.vex"
vex composant "$G0/sbom-ok.json" "$T/sbom-composant.cdx" sample-app "$D"
cas sbom-composant 4/1 "sbom:$T/sbom-composant.cdx" "$T/syft-exact.vex"
# sortie de Grype dans $T/<cas>.json : l'entrée a un autre nom (aux deux premiers passages, la redirection vidait le SBOM avant sa lecture)
echo "     SBOM avec composant : source $(jq -c '.source.type' "$T/sbom-composant.json" 2> /dev/null)"
vex composant "$G0/sbom-ok.json" "$T/sbom-application.cdx" sample-app "$D" application
cas sbom-application refus "sbom:$T/sbom-application.cdx" "$T/syft-exact.vex"
cas sbom-composant-autre 4/1 "sbom:$T/sbom-composant.cdx" "$T/autre-tout.vex"
cas sbom-composant-texte 4/1 "sbom:$T/sbom-composant.cdx" "$T/produit-texte.vex"
# sens inverse des PURL divergents : chi au PURL d'Hermeto dans le SBOM à composant (nom inchangé)
vex purl "$T/sbom-composant.cdx" "$T/sbom-hermeto.cdx" "$SYFT" "$HERMETO"
cas inv-ref 5/0 "sbom:$T/sbom-hermeto.cdx"
jq -r '.matches[] | "     \(.vulnerability.id) \(.artifact.purl)"' "$T/inv-ref.json"
cas inv-syft 5/0 "sbom:$T/sbom-hermeto.cdx" "$T/syft-exact.vex"
cas inv-hermeto 4/1 "sbom:$T/sbom-hermeto.cdx" "$T/hermeto.vex"
printf '{}' > "$T/vide.vex"
cas vex-vide refus "$I" "$T/vide.vex"
offline syft scan "$I" -o "syft-json=$T/img.syft.json" -q
echo "     SBOM syft-json : source $(jq -c '.source | {type, version}' "$T/img.syft.json")"
cas syft-json 4/1 "sbom:$T/img.syft.json" "$T/syft-exact.vex"
vex csaf "$T/csaf.vex" CVE-2025-69725 "$VULN" "$SYFT";                                                   cas csaf 'refus|5/0' "$I" "$T/csaf.vex"

echo "## 2. Zot et clé jetables (espace de noms réseau vide, $REG)"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=zot-jetable -addext subjectAltName=IP:127.0.0.1 \
  -addext basicConstraints=critical,CA:TRUE -keyout "$T/cle/zot.key" -out "$T/zot.crt" 2> /dev/null
jq -n --arg r "$T/zot" --arg c "$T/zot.crt" --arg k "$T/cle/zot.key" '{distSpecVersion: "1.1.1", storage: {rootDirectory: $r, gc: false},
  http: {address: "127.0.0.1", port: "15001", tls: {cert: $c, key: $k}}, log: {level: "error"}}' > "$T/zot.json"
cp "$T/syft-exact.vex" "$T/vex-signe.json"
vex openvex "$T/reg-nu.vex" "$VULN" "$REG/builds/sample-app@$D" - not_affected
unshare -rn bash "$0" ns
echo "     source registry : $(jq -c '.source.target | {userInput, repoDigests, tags}' "$T/reg-ref.json" 2> /dev/null)"
juger reg-ref 5/0
juger reg-bon 4/1
juger reg-nu 4/1
juger reg-autre-digest 4/1
juger reg-autre-nom 4/1
juger reg-produit-texte 4/1
[ "$(cat "$T/image-poussee" 2> /dev/null)" = "$D" ] && ok "image poussée dans le Zot jetable au même digest" || ko "image poussée : $(cat "$T/image-poussee" 2> /dev/null), attendu $D ; crane : $(head -c 200 "$T/crane.err" | tr '\n' ' ')"
while IFS='|' read -r k c n; do
  case "$k" in
    temoin) [ "$c" = 0 ] && [ "$n" = 1 ] && ok "zot-cle : verify-attestation, code 0, $n énoncé" || ko "zot-cle : code $c, $n énoncé(s), prédit 0 et 1" ;;
    etrangere) [ "$c" != 0 ] && [ "$n" = 0 ] && ok "zot-cle-etrangere : refus (code $c), 0 énoncé" || ko "zot-cle-etrangere : code $c, $n énoncé(s), prédit refus et 0"
      echo "     $(grep -m1 '^Error' "$T/erreur-etrangere" | cut -c1-200)" ;;
  esac
done < "$T/verification.tsv"
# Comparaison par jq -S (mêmes clés, mêmes valeurs) : l'énoncé est re-sérialisé par cosign, une égalité d'octets ne prouverait rien de plus.
if [ -s "$T/vex-relu.json" ] && cmp -s <(jq -S . "$T/vex-signe.json") <(jq -S . "$T/vex-relu.json"); then ok "prédicat relu égal au VEX signé (jq -S)"
else ko "prédicat relu absent ou différent du VEX signé"; fi
cas zot-vex-relu 4/1 "$I" "$T/vex-relu.json"

apres=$(empreinte)
[ "$avant" = "$apres" ] && ok "base et image de G0 inchangées ($avant)" || ko "base ou image de G0 modifiées : $avant puis $apres"
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "## bilan : $KO écart(s) aux prédictions"
