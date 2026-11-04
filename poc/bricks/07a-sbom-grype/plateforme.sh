#!/usr/bin/env bash
# Brique 07a : scan dans la plateforme (protocole du 04/11/2026, décisions D1 à D6 du propriétaire, README « Suite sur le
# laptop »). Une étape par jalon ; journal dans resultats/<étape>.log.
#   g0  relevés sur l'hôte seul (rien dans Zot, Forgejo ni le cluster) : base Grype du jour téléchargée, empreinte vérifiée,
#       signature cherchée ; import hors réseau par la Grype épinglée (D5 a) ; SBOM de D1 (a) : Syft sur l'image lue par
#       digest dans Zot et sur la source au commit lue dans Forgejo, fusionnés ; scans hors réseau de sample-app et du cas KEV
#       (log4j-core 2.14.1 ajouté au SBOM, comme bench.sh)
#   G1 (D2, D3 a ; Zot reconfiguré avant par « mise run confiance:stockage -- zot » : comptes poc-vulndb et poc-scan,
#       dépôts vulndb/** et builds/scan/**) :
#   g1_oras   oras 1.3.6 de J5 (archive de …/08/telechargements/tsa, empreinte de mise.lock et signature GPG revérifiées) installé
#             dans sc-stockage (/usr/local/bin/oras), empreinte revérifiée dans la VM
#   g1_droits droits de Zot (D2) sur des dépôts jetables : poc-scan crée par digest dans builds/scan/, pas de tag, rien ailleurs ;
#             poc-images et poc-replay ne créent plus dans builds/scan/ ; poc-vulndb crée sous vulndb/, ne remplace pas un tag
#   g1_base   service et timer base-grype sur sc-stockage (utilisateur dédié, mot de passe de poc-vulndb par LoadCredential)
#   g1_essai  run du service : base du jour archivée sous vulndb/grype:<date>, empreinte et annotations relues en lecture
#             anonyme ; second run : déjà archivée ; contre-épreuve : archive tronquée refusée, rien poussé ; mot de passe absent
#             du journal ; timer activé
#   g1_grafana journal de base-grype.service lu par l'auditeur à travers Grafana (19b)
#   G2 (D5 a, D8) : image d'outils du scanner, plateforme/outils-scan dans Zot :
#   g2_telecharger archives de release de Grype 0.104.1 et Syft 1.38.0, checksums.txt, .sig et .pem (…/07a/telechargements)
#   g2_verifier    empreintes de mise.lock et de checksums.txt ; signature sans clé de checksums.txt vérifiée par cosign
#                  (identité : workflow de release du dépôt anchore, émetteur GitHub Actions ; vérification seule, comme
#                  tsa.sh pour cosign) ; contre-épreuve : identité d'un autre dépôt refusée
#   g2_image       couche reproductible (grype, syft, oras de J5, scan-outil construit depuis outil/ à cache vide) sur l'image
#                  cosign v3.1.4-dev (busybox) déjà copiée dans Zot par J5 ; poussée par poc-ecriture ; second assemblage :
#                  même digest
# Usage (racine du dépôt, outils de mise.toml) : mise exec -- poc/bricks/07a-sbom-grype/plateforme.sh <étape>…
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
O8=$O/08
S8=$O8/secrets
DL=$O8/telechargements/tsa
ORAS_TGZ_SHA=66fb0ad7206f3f6fa77ed5b552049d364ccf4b50b1684554f731f76302b52ca0   # mise.lock, oras 1.3.6 (comme tsa.sh)
ORAS_FPR=C6FC42F0DE84A345FAADB742F44418110791EF37   # « ORAS Project Release Signing » (KEYS du dépôt, oras.land ; tsa.sh)
DL7=$W/telechargements
GRYPE_TGZ_SHA=2cb820b6c81f88fd6aff3fb4ca5a7161e9ab70af0f27fc5e99cd16deb987cd5f   # mise.lock, grype 0.104.1
SYFT_TGZ_SHA=bc664debb00db1b9b4b9dae4ba1a29d99621e33b641b94b78b9048374b812a3d    # mise.lock, syft 1.38.0
COSIGN_BASE=amont/sigstore/cosign/cosign@sha256:c142f6bc0c6d8e5e4a3d31b941200a12502ad90bb5ce93b78c875c868905619d   # J5 (tsa.sh), v3.1.4-dev amd64
OUTILS_SCAN=plateforme/outils-scan
SSH_OPTS=(-i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
sur() { ssh "${SSH_OPTS[@]}" poc@192.168.161.13 "$@"; }   # sc-stockage
copier() { # répertoire-distant fichiers… (comme commun.sh de la 08)
  local d=$1; shift
  sur "rm -rf $d && mkdir -m 0700 $d"
  scp -q "${SSH_OPTS[@]}" "$@" "poc@192.168.161.13:$d/"
}
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
  # PURL de Syft des deux côtés (D1 a) : chi s'écrit …/chi@v5.2.3#v5, pas …/chi/v5@v5.2.3 comme chez Hermeto (constat de la
  # 07a ; premier passage du 04/11/2026 en KO sur ce seul contrôle, resultats/g0-premier-passage.log)
  for p in 'pkg:golang/github.com/go-chi/chi@v5.2.3#v5' 'pkg:golang/stdlib@' 'pkg:npm/marked@16.4.1'; do
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

etape_g1_oras() {
  T=$W/g1-oras
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T/gnupg")
  GNUPGHOME=$T/gnupg gpg --batch --quiet --import "$DL/oras-KEYS" 2>/dev/null
  s=$(GNUPGHOME=$T/gnupg gpg --batch --status-fd 1 --verify "$DL/oras_1.3.6_checksums.txt.asc" "$DL/oras_1.3.6_checksums.txt" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}')
  attendu "signature GPG de oras_1.3.6_checksums.txt (clé primaire)" "$s" "$ORAS_FPR"
  (cd "$DL" && grep ' oras_1.3.6_linux_amd64.tar.gz$' oras_1.3.6_checksums.txt | sha256sum -c && echo "$ORAS_TGZ_SHA  oras_1.3.6_linux_amd64.tar.gz" | sha256sum -c)
  tar -xzf "$DL/oras_1.3.6_linux_amd64.tar.gz" -C "$T" oras
  b=$(sha256sum < "$T/oras" | cut -c1-64)
  attendu "binaire extrait identique à celui de mise" "$b" "$(sha256sum < "$(type -P oras)" | cut -c1-64)"
  copier /tmp/oras-installation "$T/oras"
  sur "sudo bash -s" <<EOF
set -euo pipefail
echo "$b  /tmp/oras-installation/oras" | sha256sum -c
install -m 0755 /tmp/oras-installation/oras /usr/local/bin/oras
rm -rf /tmp/oras-installation
echo "$b  /usr/local/bin/oras" | sha256sum -c
/usr/local/bin/oras version | head -1
EOF
  rm -rf -- "${T:?}"
  return $ko
}

etape_g1_droits() {
  local x=$W/g1-droits img r
  rm -rf -- "${x:?}" && (umask 077 && mkdir -p "$x")
  trap 'rm -rf -- "$W/g1-droits"' EXIT   # copies des mots de passe (auth-*.json) supprimées même en cas d'échec
  for c in poc-scan poc-vulndb poc-images; do
    printf '{"auths":{"%s":{"auth":"%s"}}}' "$REG_HOTE" "$(printf '%s:%s' "$c" "$(cat "$S8/zot-$c.password")" | base64 -w0)" > "$x/auth-$c.json"
  done
  printf 'essai 07a %s\n' "$(date -u +%FT%TZ)" > "$x/f.txt"
  ( cd "$x" && oras push --oci-layout "$x/image:v" f.txt > /dev/null )
  img=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifests"][0]["digest"])' "$x/image/index.json")
  essai() { # libellé attendu(accepte|refus) compte référence-cible
    if oras cp --to-registry-config "$x/auth-$3.json" --to-ca-file "$P/ca-poc.crt" --from-oci-layout "$x/image@$img" "$REG_HOTE/$4" > "$x/sortie" 2>&1; then r=accepte; else r=refus; fi
    [ "$r" = "$2" ] && echo "OK   $1 : $r" || { echo "KO   $1 : $r (attendu $2) : $(grep -m1 -iE 'error|denied|unauthor' "$x/sortie" | cut -c1-140)"; ko=1; }
  }
  essai "poc-scan, par digest dans builds/scan/essai-07a" accepte poc-scan "builds/scan/essai-07a@$img"
  essai "poc-scan, par tag dans builds/scan/essai-07a" refus poc-scan "builds/scan/essai-07a:tag-interdit"
  essai "poc-scan, par digest dans builds/essai-07a (hors de builds/scan/)" refus poc-scan "builds/essai-07a@$img"
  essai "poc-images, par digest dans builds/scan/essai-07a (motif le plus long)" refus poc-images "builds/scan/essai-07a@$img"
  essai "poc-images, par digest dans builds/essai-07a (témoin : droit inchangé)" accepte poc-images "builds/essai-07a@$img"
  essai "poc-vulndb, tag dans vulndb/essai-07a" accepte poc-vulndb "vulndb/essai-07a:v1"
  essai "poc-vulndb, même tag repoussé (mise à jour)" refus poc-vulndb "vulndb/essai-07a:v1"
  essai "poc-vulndb, par digest dans builds/essai-07a" refus poc-vulndb "builds/essai-07a@$img"
  if [ -s "$HOME/.cache/supply-chain-poc/10/secrets/zot-poc-replay.password" ]; then
    printf '{"auths":{"%s":{"auth":"%s"}}}' "$REG_HOTE" "$(printf 'poc-replay:%s' "$(cat "$HOME/.cache/supply-chain-poc/10/secrets/zot-poc-replay.password")" | base64 -w0)" > "$x/auth-poc-replay.json"
    essai "poc-replay, par digest dans builds/scan/essai-07a" refus poc-replay "builds/scan/essai-07a@$img"
  fi
  echo "tags de vulndb/essai-07a : $(oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/vulndb/essai-07a" | paste -sd' ')"
  rm -rf -- "${x:?}"
  return $ko
}

etape_g1_base() {
  copier /tmp/base-grype-installation "$here/fetch-db.sh" "$here/systemd/base-grype.sh" "$here/systemd/base-grype.service" \
    "$here/systemd/base-grype.timer" "$P/ca-poc.crt" "$S8/zot-poc-vulndb.password"
  sur "sudo bash -s" <<'EOF'
set -euo pipefail
cd /tmp/base-grype-installation
id base-grype >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/cache/base-grype --no-create-home --shell /usr/sbin/nologin base-grype
install -d -m 0755 /usr/local/lib/base-grype /etc/base-grype
install -d -m 0700 /etc/base-grype/secrets
install -m 0755 fetch-db.sh base-grype.sh /usr/local/lib/base-grype/
install -m 0644 ca-poc.crt /etc/base-grype/
install -m 0600 zot-poc-vulndb.password /etc/base-grype/secrets/poc-vulndb.password
install -m 0644 base-grype.service base-grype.timer /etc/systemd/system/
cd / && rm -rf /tmp/base-grype-installation
systemctl daemon-reload
ls -l /usr/local/lib/base-grype /etc/base-grype /etc/base-grype/secrets
EOF
  for f in fetch-db.sh systemd/base-grype.sh; do
    attendu "$(basename "$f") installé identique" "$(sur "sha256sum /usr/local/lib/base-grype/$(basename "$f")" | cut -c1-64)" "$(sha256sum < "$here/$f" | cut -c1-64)"
  done
  sur "systemd-analyze security base-grype.service 2>/dev/null | tail -1"
  return $ko
}

etape_g1_essai() {
  local debut r jour ref m
  debut=$(sur "date '+%Y-%m-%d %H:%M:%S'")
  r=0; sur "sudo systemctl start base-grype.service" || r=$?
  echo "premier run : code $r ; $(sur "systemctl show -p Result -p ExecMainStatus --value base-grype.service" | paste -sd' ')"
  echo "## journal du premier run"; sur "sudo journalctl -u base-grype.service --since '$debut' -o cat"
  [ "$r" = 0 ] || { echo "KO   premier run"; return 1; }
  curl -fsS -o "$W/latest.json" "$BASE/latest.json"
  read -r path checksum built < <(python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1])); print(d["path"], d["checksum"], d["built"])' "$W/latest.json")
  jour=${built%%T*}
  ref=$(oras manifest fetch --ca-file "$P/ca-poc.crt" --descriptor "$REG_HOTE/vulndb/grype:$jour" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["digest"])')
  echo "vulndb/grype:$jour -> $ref (lecture anonyme)"
  oras manifest fetch --ca-file "$P/ca-poc.crt" "$REG_HOTE/vulndb/grype@$ref" > "$W/manifeste.json"
  m=$(python3 -I -c 'import json, sys
m = json.load(open(sys.argv[1])); a = m.get("annotations", {})
c = [l["digest"] for l in m["layers"] if l["mediaType"] == "application/vnd.anchore.grype.db.v6+zstd"]
print(m.get("artifactType"), a.get("dev.anchore.grype.db.checksum"), a.get("org.opencontainers.image.created"), c[0] if c else "-")' "$W/manifeste.json")
  read -r at an cr co <<<"$m"
  attendu "artifactType" "$at" application/vnd.supply-chain.grype-db.v6
  attendu "empreinte annoncée (annotation)" "$an" "$checksum"
  attendu "date de construction (annotation)" "$cr" "$built"
  attendu "couche de l'archive = empreinte annoncée" "$co" "$checksum"
  debut=$(sur "date '+%Y-%m-%d %H:%M:%S'")
  r=0; sur "sudo systemctl start base-grype.service" || r=$?
  attendu "second run (code)" "$r" 0
  attendu "second run : base déjà archivée" "$(sur "sudo journalctl -u base-grype.service --since '$debut' -o cat" | grep -c '^déjà archivée : ')" 1
  echo "## contre-épreuve : archive tronquée dans le répertoire de travail (sans identifiants)"
  r=0; sur "bash -s" > "$W/alteree.out" 2>&1 <<EOF || r=$?
set -euo pipefail
t=\$(mktemp -d); trap 'rm -rf "\$t"' EXIT
curl -fsS -o "\$t/latest.json" $BASE/latest.json
p=\$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["path"])' "\$t/latest.json")
curl -fsS -r 0-1048575 -o "\$t/\$p" "$BASE/\$p"
ORAS=/usr/local/bin/oras ORAS_OPTS="--ca-file /etc/base-grype/ca-poc.crt" REG=192.168.161.13:5000 WORKDIR=\$t /usr/local/lib/base-grype/fetch-db.sh
EOF
  cat "$W/alteree.out"
  [ "$r" != 0 ] && grep -q '^empreinte invalide' "$W/alteree.out" && echo "OK   archive tronquée refusée (code $r)" || { echo "KO   contre-épreuve : code $r"; ko=1; }
  attendu "tags de vulndb/grype après la contre-épreuve" "$(oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/vulndb/grype" | paste -sd' ')" "$jour"
  if sur "sudo journalctl -u base-grype.service -o cat" | grep -q -F -f "$S8/zot-poc-vulndb.password"; then echo "KO   mot de passe dans le journal"; ko=1; else echo "OK   mot de passe de poc-vulndb absent du journal de l'unité"; fi
  sur "sudo systemctl enable --now base-grype.timer 2>&1; systemctl list-timers base-grype.timer --no-pager | head -2"
  rm -f "$W/latest.json" "$W/manifeste.json" "$W/alteree.out"
  return $ko
}

etape_g1_grafana() { # journal de base-grype.service lu par l'auditeur à travers Grafana (19b), depuis le début de G1
  local q c o=$W/graf.out
  q=$(jq -nc --arg e '{noeud="sc-stockage", source="journal", unite="base-grype.service"}' --arg de "$(date -ud 2026-11-04T19:20:00Z +%s)000" \
    --arg a "$(date -u +%s)000" '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: 1000, direction: "forward"}], from: $de, to: $a}')
  c=$(printf 'user = "auditeur:%s"\n' "$(cat "$S8/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$P/ca-poc.crt" -o "$o" -w '%{http_code}' -X POST -H 'Content-Type: application/json' "https://192.168.161.13:3001/api/ds/query" -d "$q")
  attendu "requête de l'auditeur (HTTP)" "$c" 200
  jq -r '.results.A.frames[]? | .data.values as $v | range(0; ($v[2] // []) | length) | "\($v[1][.] / 1000 | todate) \($v[2][.])"' "$o" > "$W/lignes"
  cat "$W/lignes"
  grep -q '/vulndb/grype@sha256:' "$W/lignes" && echo "OK   archivage visible dans Grafana" || { echo "KO   archivage absent de Grafana"; ko=1; }
  if grep -q -F -f "$S8/zot-poc-vulndb.password" "$o"; then echo "KO   mot de passe dans la réponse de Grafana"; ko=1; else echo "OK   mot de passe de poc-vulndb absent de la réponse"; fi
  rm -f "$o" "$W/lignes"
  return $ko
}

etape_g2_telecharger() {
  local o v
  mkdir -p "$DL7"
  for o in grype:0.104.1 syft:1.38.0; do
    v=${o#*:}; o=${o%%:*}
    for f in "${o}_${v}_linux_amd64.tar.gz" "${o}_${v}_checksums.txt" "${o}_${v}_checksums.txt.sig" "${o}_${v}_checksums.txt.pem"; do
      [ -s "$DL7/$f" ] || curl -fsSL -o "$DL7/$f" "https://github.com/anchore/$o/releases/download/v$v/$f"
      echo "$f : $(stat -c %s "$DL7/$f") octets"
    done
  done
}

etape_g2_verifier() {
  local o v c id
  T=$W/g2-verifier
  rm -rf -- "${T:?}" && mkdir -p "$T"
  for o in grype:0.104.1:$GRYPE_TGZ_SHA syft:1.38.0:$SYFT_TGZ_SHA; do
    IFS=: read -r o v c <<<"$o"
    echo "## $o $v"
    (cd "$DL7" && echo "$c  ${o}_${v}_linux_amd64.tar.gz" | sha256sum -c && grep " ${o}_${v}_linux_amd64.tar.gz\$" "${o}_${v}_checksums.txt" | sha256sum -c)
    # Certificat publié en PEM encodé en base64 (goreleaser) ou en PEM : ramené au PEM.
    if grep -q -- '-----BEGIN' "$DL7/${o}_${v}_checksums.txt.pem"; then cp "$DL7/${o}_${v}_checksums.txt.pem" "$T/$o.pem"; else base64 -d < "$DL7/${o}_${v}_checksums.txt.pem" > "$T/$o.pem"; fi
    id=$(openssl x509 -in "$T/$o.pem" -noout -ext subjectAltName | sed -n 's/^ *URI://p')
    echo "identité du certificat : $id"
    if cosign verify-blob --certificate "$T/$o.pem" --signature "$DL7/${o}_${v}_checksums.txt.sig" \
         --certificate-identity-regexp "^https://github\.com/anchore/$o/\.github/workflows/release\.yaml@refs/" \
         --certificate-oidc-issuer https://token.actions.githubusercontent.com "$DL7/${o}_${v}_checksums.txt" > "$T/v.out" 2>&1; then
      echo "OK   signature sans clé de ${o}_${v}_checksums.txt : $id"
    else cat "$T/v.out"; echo "KO   signature de ${o}_${v}_checksums.txt"; ko=1; fi
    if cosign verify-blob --certificate "$T/$o.pem" --signature "$DL7/${o}_${v}_checksums.txt.sig" \
         --certificate-identity-regexp "^https://github\.com/anchore/autre/" \
         --certificate-oidc-issuer https://token.actions.githubusercontent.com "$DL7/${o}_${v}_checksums.txt" > "$T/v.out" 2>&1; then
      echo "KO   identité d'un autre dépôt acceptée"; ko=1
    else echo "OK   identité d'un autre dépôt refusée : $(grep -m1 -iE 'error|expected' "$T/v.out" | cut -c1-140)"; fi
  done
  rm -rf -- "${T:?}"
  return $ko
}

etape_g2_image() {
  local d1 d2 b
  T=$W/g2-image
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T/docker")
  trap 'rm -rf -- "$W/g2-image"' EXIT   # copie du mot de passe de poc-ecriture supprimée même en cas d'échec
  printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" "$(printf 'poc-ecriture:%s' "$(cat "$S8/zot-poc-ecriture.password")" | base64 -w0)" > "$T/docker/config.json"
  (cd "$DL" && echo "$ORAS_TGZ_SHA  oras_1.3.6_linux_amd64.tar.gz" | sha256sum -c)
  (cd "$DL7" && echo "$GRYPE_TGZ_SHA  grype_0.104.1_linux_amd64.tar.gz" | sha256sum -c && echo "$SYFT_TGZ_SHA  syft_1.38.0_linux_amd64.tar.gz" | sha256sum -c)
  b=$T/racine/usr/local/bin
  mkdir -p "$b" && chmod 0755 "$T/racine" "$T/racine/usr" "$T/racine/usr/local" "$b"
  tar -xzf "$DL/oras_1.3.6_linux_amd64.tar.gz" -C "$b" oras
  tar -xzf "$DL7/grype_0.104.1_linux_amd64.tar.gz" -C "$b" grype
  tar -xzf "$DL7/syft_1.38.0_linux_amd64.tar.gz" -C "$b" syft
  (cd "$here/outil" && CGO_ENABLED=0 GOCACHE=$T/cache GOFLAGS=-mod=mod go build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o "$b/scan-outil" .)
  rm -rf -- "${T:?}/cache"
  chmod 0755 "$b"/*
  (cd "$b" && sha256sum grype syft oras scan-outil)
  attendu "grype de l'image = grype de mise" "$(sha256sum < "$b/grype" | cut -c1-64)" "$(sha256sum < "$(type -P grype)" | cut -c1-64)"
  attendu "syft de l'image = syft de mise" "$(sha256sum < "$b/syft" | cut -c1-64)" "$(sha256sum < "$(type -P syft)" | cut -c1-64)"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$T/couche.tar" -C "$T/racine" usr
  echo "couche : $(sha256sum < "$T/couche.tar" | cut -c1-64), $(stat -c %s "$T/couche.tar") octets"
  d1=$(DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt crane append -b "$REG_HOTE/$COSIGN_BASE" -f "$T/couche.tar" \
    -t "$REG_HOTE/$OUTILS_SCAN:grype-0.104.1-syft-1.38.0" 2>/dev/null)
  echo "image d'outils du scanner : $d1"
  d2=$(DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt crane append -b "$REG_HOTE/$COSIGN_BASE" -f "$T/couche.tar" \
    -t "$REG_HOTE/$OUTILS_SCAN:grype-0.104.1-syft-1.38.0" 2>/dev/null)
  attendu "second assemblage (même digest)" "${d2##*@}" "${d1##*@}"
  attendu "relue en lecture anonyme" "$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$OUTILS_SCAN:grype-0.104.1-syft-1.38.0")" "${d1##*@}"
  rm -rf -- "${T:?}"
  return $ko
}

[ $# -ge 1 ] || { sed -n 2,27p "$0"; exit 2; }
mkdir -p "$R" "$W"
for e in "$@"; do
  case $e in
    g0|g1_oras|g1_droits|g1_base|g1_essai|g1_grafana|g2_telecharger|g2_verifier|g2_image) ;;
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
