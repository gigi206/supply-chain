#!/usr/bin/env bash
# Brique 07a : scan dans la plateforme (protocole du 04/11/2026, décisions D1 à D6 du propriétaire, README « Suite sur le
# laptop »). Une étape par jalon ; journal dans resultats/<étape>.log.
#   g0  relevés sur l'hôte seul (rien dans Zot, Forgejo ni le cluster) : base Grype du jour téléchargée, empreinte vérifiée,
#       signature cherchée ; import hors réseau par la Grype épinglée (D5 a) ; SBOM de D1 (a) : Syft sur l'image lue par
#       digest dans Zot et sur la source au commit lue dans Forgejo, fusionnés ; scans hors réseau de sample-app et du cas KEV
#       (log4j-core 2.14.1 ajouté au SBOM, comme bench.sh)
# Usage (racine du dépôt, outils de mise.toml) : mise exec -- poc/bricks/07a-sbom-grype/plateforme.sh g0
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=$HOME/.cache/supply-chain-poc
P=$O/08/pki
W=$O/07a
REG_HOTE=192.168.161.13:5000                                   # Zot depuis l'hôte (SAN IP du certificat)
FORGEJO=https://192.168.161.13:3000/workspace/sample-app.git   # lecture anonyme
COMMIT=6391fd437f26696847041be3226bbbf633f55a2f                # tête de main relevée le 04/11/2026 à 18:31 UTC
IMAGE=builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
BASE=https://grype.anchore.io/databases/v6
ko=0
ok() { echo "OK   $1"; }
attendu() { # libellé valeur attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi
}
offline() { unshare -rn env GRYPE_DB_CACHE_DIR="$T/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
  GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false "$@"; }
ms() { local u; read -r u _ < /proc/uptime; echo $(( 10 * 10#${u/./} )); }
purls() { python3 -I -c 'import json, sys; print("\n".join(sorted(c["purl"] for c in json.load(open(sys.argv[1])).get("components", []) if c.get("purl"))))' "$1"; }

etape_g0() {
  T=$W/g0
  chmod -R u+w -- "$T" 2>/dev/null || true
  rm -rf -- "${T:?}"
  mkdir -p "$T"
  cd "$T"
  echo "## outils : grype $(grype version 2>/dev/null | sed -n 's/^Version: *//p') ($(grype version 2>/dev/null | sed -n 's/^BuildDate: *//p')), syft $(syft version 2>/dev/null | sed -n 's/^Version: *//p'), oras $(oras version 2>/dev/null | sed -n 's/^Version: *//p')"

  echo "## base du jour"
  curl -fsS -o latest.json "$BASE/latest.json"
  read -r path checksum built schema < <(python3 -I -c 'import json
d = json.load(open("latest.json"))
print(d["path"], d["checksum"], d["built"], d["schemaVersion"])')
  echo "latest.json : $(python3 -I -c 'import json; print(", ".join(sorted(json.load(open("latest.json")))))') ; construite $built ; schéma $schema"
  attendu "schéma" "$schema" v6.1.10
  t0=$(ms)
  curl -fsS -o "$path" "$BASE/$path"
  echo "archive $path : $(stat -c %s "$path") octets en $(( ($(ms) - t0) / 1000 )) s"
  attendu "empreinte de l'archive" "sha256:$(sha256sum < "$path" | cut -c1-64)" "$checksum"
  for s in "$path.sig" "$path.sigstore.json" "$path.pem" latest.json.sig latest.json.sigstore.json; do
    echo "signature cherchée : $s -> $(curl -s -o /dev/null -w '%{http_code}' "$BASE/$s")"
  done
  t0=$(ms)
  offline grype db import "$path" > import.out 2>&1 || { cat import.out; echo "KO   import hors réseau"; exit 1; }
  echo "import hors réseau en $(( ($(ms) - t0) / 1000 )) s : $(offline grype db status 2>/dev/null | grep -E 'Schema|Built|Status' | tr -s ' ' | paste -sd' ')"
  echo "base importée : $(du -sm dbcache | cut -f1) Mo"

  echo "## SBOM de D1 (a)"
  GIT_SSL_CAINFO=$P/ca-poc.crt git -c init.defaultBranch=main clone -q --no-checkout "$FORGEJO" source
  git -C source -c advice.detachedHead=false checkout -q "$COMMIT"
  attendu "commit de la source" "$(git -C source rev-parse HEAD)" "$COMMIT"
  git -C source fsck --no-progress > /dev/null 2>&1 && ok "git fsck de la source"
  echo "fichiers de verrou : $(cd source && find . -path ./.git -prune -o \( -name go.mod -o -name go.sum -o -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml \) -print | sort | paste -sd' ')"
  rm -rf source/.git
  oras copy --no-tty --from-ca-file "$P/ca-poc.crt" --to-oci-layout "$REG_HOTE/$IMAGE" "image:sample-app" > /dev/null
  attendu "digest de l'image lue" "$(python3 -I -c 'import json; print(json.load(open("image/index.json"))["manifests"][0]["digest"])')" "${IMAGE#*@}"
  offline syft scan "oci-dir:image" -o cyclonedx-json=sbom-image.json -q
  offline syft scan "dir:source" -o cyclonedx-json=sbom-source.json -q
  echo "image (Syft) :"; purls sbom-image.json | sed 's/^/  /'
  echo "source (Syft) :"; purls sbom-source.json | sed 's/^/  /'
  python3 -I "$here/sbom_merge.py" sbom-source.json sbom-image.json source image > sbom-ok.json
  echo "fusion :"; purls sbom-ok.json | sed 's/^/  /'
  for p in 'pkg:golang/github.com/go-chi/chi/v5@v5.2.3' 'pkg:golang/stdlib@' 'pkg:npm/marked@16.4.1'; do
    if purls sbom-ok.json | grep -q -F "$p"; then ok "fusion : $p"; else echo "KO   fusion : $p absent"; ko=1; fi
  done
  if purls sbom-image.json | grep -q 'pkg:npm/marked'; then echo "KO   image : marked vu par Syft (prédit absent)"; ko=1; else ok "image : marked absent (prédit)"; fi
  python3 -I - sbom-ok.json sbom-kev.json <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))
b["components"].append({"type": "library", "name": "log4j-core", "version": "2.14.1",
                        "purl": "pkg:maven/org.apache.logging.log4j/log4j-core@2.14.1"})
json.dump(b, open(sys.argv[2], "w"), indent=2)
PY

  echo "## scans hors réseau"
  for c in ok kev; do
    t0=$(ms)
    offline grype "sbom:sbom-$c.json" -o json --file "grype-$c.json" -q
    python3 -I "$here/scan_predicate.py" "grype-$c.json" "$BASE/$path ($checksum)" > "scan-$c.json"
    python3 -I -c 'import json, sys
v = json.load(open(sys.argv[1]))["vulnerabilities"]
print("scan", sys.argv[2], "en", sys.argv[3], "ms :", len(v), "vulnérabilités dont", sum(x["kev"] for x in v), "KEV :", ", ".join(sorted({c for x in v for c in x["kevCves"]})) or "-")
for x in v: print("  ", x["package"], x["id"], x["severity"], "KEV" if x["kev"] else "")' "scan-$c.json" "$c" "$(( $(ms) - t0 ))"
  done
  attendu "KEV de sample-app" "$(python3 -I -c 'import json, sys; print(sum(x["kev"] for x in json.load(open(sys.argv[1]))["vulnerabilities"]))' scan-ok.json)" 0
  for c in CVE-2021-44228 CVE-2021-45046; do
    if python3 -I -c 'import json, sys; sys.exit(0 if any(sys.argv[2] in x["kevCves"] for x in json.load(open(sys.argv[1]))["vulnerabilities"]) else 1)' scan-kev.json "$c"; then
      ok "cas KEV : $c"; else echo "KO   cas KEV : $c absente"; ko=1; fi
  done
  echo "## empreintes"; sha256sum sbom-image.json sbom-source.json sbom-ok.json scan-ok.json scan-kev.json
  return $ko
}

[ $# -ge 1 ] || { sed -n 2,8p "$0"; exit 2; }
mkdir -p "$R" "$W"
for e in "$@"; do
  case $e in
    g0) ;;
    *) echo "étape inconnue : $e" >&2; exit 2 ;;
  esac
  echo "# plateforme.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$R/$e.log"
  set +e
  ( set -e; "etape_$e" ) 2>&1 | tee -a "$R/$e.log"
  rc=${PIPESTATUS[0]}
  set -e
  echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ), code $rc" | tee -a "$R/$e.log"
  [ "$rc" = 0 ] || exit "$rc"
done
