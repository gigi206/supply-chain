#!/usr/bin/env bash
# Brique 07b, tranche 3 à sec : banc du patch politique/07b-t3.patch. Rien de partagé : aucune écriture dans le vrai Zot, le cluster
# ou les VM ; aucun réseau. Le patch est appliqué à une copie des fichiers du dépôt ; ce sont ces copies qui tournent.
#   A. hôte, hors réseau : scan-outil du patch (fusion, vex, predicat), compatibilité avec les prédicats d'avant (mesure 0), règles
#      de la porte (ec opa check, ec opa test, mutations de g5_regles telles que le patch les liste) ;
#   B. Zot et clés jetables dans un espace de noms réseau vide (127.0.0.1, comme G6 et la tranche 2) : scanner.sh du patch, mode
#      analyser complet (image puis deb) et mode vex suivi des mêmes commandes qu'analyser, VEX témoins signés et publiés en referrers ;
#      renouvellement d'un VEX par retrait de l'ancien référent (oras manifest delete, passage 6) ; remplacement (passages 7 à 10) ;
#      pièce 8 (passage 11) : signer-vex.sh verifier en A (sans registre), signer en B (clé locale, jamais hashivault://vex) ;
#   C. porte : ec validate input de l'hôte sur les prédicats produits en B, entrée écartée passée en KEV par jq ;
#   D. entrees-scan.py du patch : fonctions comptes et entrees appelées sur les prédicats produits en B (pas de Zot, pas de VM).
# Les VEX sont des témoins (07b-t3-vex.py) : aucune analyse d'atteignabilité ne les fonde.
# Usage (racine du dépôt, outils de mise.toml) : poc/bricks/07a-sbom-grype/resultats/07b-t3-banc.sh > <journal>
set -euo pipefail
export LC_ALL=C
RACINE=$PWD
R=$RACINE/poc/bricks/07a-sbom-grype/resultats
G0=$HOME/.cache/supply-chain-poc/07a/g0
M0=$HOME/.cache/supply-chain-poc/07a/t3/mesure0
T=$HOME/.cache/supply-chain-poc/07a/t3/banc
B=$T/arbre/poc/bricks/07a-sbom-grype
OUT=$T/outil/scan-outil
REG=127.0.0.1:15002
Y=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
DEB=sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e
VULN=GHSA-mqqf-5wvp-8fh8
SYFT='pkg:golang/github.com/go-chi/chi@v5.2.3#v5'
OPENVEX=https://openvex.dev/ns/v0.2.0
SCAN=https://supply-chain.example/scan/v1
JUSTIF=vulnerable_code_not_in_execute_path
IMPACT="témoin du banc : aucune analyse"

vex() { python3 -I "$R/07b-t3-vex.py" "$@"; }
KO=0
ok() { echo "OK   $1"; }
ko() { echo "KO   $1"; KO=$((KO + 1)); }
attendu() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else ko "$1 : $2 (prédit : $3)"; fi; }
grype_hors_ligne() {
  env GRYPE_DB_CACHE_DIR="$G0/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false GRYPE_CHECK_FOR_APP_UPDATE=false \
    TMPDIR="$T/tmp" grype "$@"
}
mi() { jq -r '"\([.vulnerabilities[] | select(has("vex") | not)] | length)/\([.vulnerabilities[] | select(has("vex"))] | length)"' "$1"; }

# ---------------------------------------------------------------------------------------------------------------- B (espace de noms)
if [ "${1:-}" = ns ]; then
  ip link set lo up
  zot serve "$T/zot.json" > "$T/zot.out" 2>&1 & zp=$!
  # shellcheck disable=SC2064   # développement à la pose, voulu
  trap "kill $zp 2>/dev/null || true" EXIT
  for _ in $(seq 40); do curl -fsS --cacert "$T/zot.crt" "https://$REG/v2/" > /dev/null 2>&1 && break; sleep 0.25; done
  export SSL_CERT_FILE=$T/zot.crt DOCKER_CONFIG=$T/docker
  S=$B/politique/scanner.sh
  cd "$T"
  cosign signing-config create --out vide.json > /dev/null 2>&1
  (cd "$T/cle" && COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix vex > /dev/null 2>&1 \
    && COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix etrangere > /dev/null 2>&1)
  # base de G0 sous vulndb/grype:<date>, annotée comme par base-grype.sh
  f=$(cd "$G0" && ls vulnerability-db_*.tar.zst)
  # type de média explicite, comme fetch-db.sh : le nom du fichier contient « : » (passage 1 : oras y lisait un type)
  (cd "$G0" && oras push --no-tty --ca-file "$T/zot.crt" --artifact-type application/vnd.supply-chain.grype-db.v6 \
    --annotation "dev.anchore.grype.db.checksum=sha256:$(sha256sum < "$f" | cut -c1-64)" \
    "$REG/vulndb/grype:2026-11-04" "$f:application/vnd.anchore.grype.db.v6+zstd" > /dev/null)
  pousser() { # layout dépôt : digest sur la sortie
    crane push "$1" "$REG/$2:t3" > /dev/null 2>> "$T/crane.err"
    crane digest "$REG/$2:t3" 2>> "$T/crane.err"
  }
  publier_vex() { # clé document digest-signé dépôt-du-sujet digest-du-sujet dépôt-vex : referrer comme scanner.sh publier
    local w; w=$(mktemp -d "$T/tmp/pub.XXXX")
    COSIGN_PASSWORD='' cosign attest-blob --key "$T/cle/$1.key" --signing-config vide.json --predicate "$2" --type "$OPENVEX" \
      --bundle "$w/bundle.json" --hash "${3#sha256:}" --yes sample-app > "$w/cosign.log" 2>&1 || { cat "$w/cosign.log"; return 1; }
    oras manifest fetch --ca-file zot.crt --descriptor "$REG/$4@$5" > "$w/sujet.json"
    printf '{}' > "$w/config-vide.json"
    oras blob push --ca-file zot.crt "$REG/$6" "$w/config-vide.json" > /dev/null
    oras blob push --ca-file zot.crt "$REG/$6" "$w/bundle.json" > /dev/null
    local TY=application/vnd.dev.sigstore.bundle.v0.3+json
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s",%s,%s,%s,%s}' "$TY" \
      '"config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2}' \
      "\"layers\":[{\"mediaType\":\"$TY\",\"digest\":\"sha256:$(sha256sum < "$w/bundle.json" | cut -c1-64)\",\"size\":$(wc -c < "$w/bundle.json")}]" \
      "\"subject\":$(cat "$w/sujet.json")" \
      "\"annotations\":{\"dev.sigstore.bundle.content\":\"dsse-envelope\",\"dev.sigstore.bundle.predicateType\":\"$OPENVEX\"}" > "$w/manifeste.json"
    oras manifest push --ca-file zot.crt "$REG/$6@sha256:$(sha256sum < "$w/manifeste.json" | cut -c1-64)" "$w/manifeste.json" > /dev/null
    sha256sum < "$w/manifeste.json" | cut -c1-64 > "$T/manifeste-$(basename "$2" .json)"   # passage 6 : digest du référent, pour le retrait
    jq -r .dsseEnvelope.payload "$w/bundle.json" | base64 -d | sha256sum | cut -c1-64 > "$T/empreinte-$(basename "$2" .json)"
  }
  scanner() { # mode cas [variables…] : scanner.sh du patch, dossier de travail propre au cas
    local m=$1 c=$2; shift 2
    mkdir -p "$T/cas/$c"
    env -i PATH="$T/outil:$PATH" HOME="$T/cas/$c" TMPDIR="$T/tmp" SSL_CERT_FILE="$T/zot.crt" TRAVAIL="$T/cas/$c" CA="$T/zot.crt" \
      CLE_VEX="$T/cle/vex.pub" "$@" sh "$S" "$m" > "$T/cas/$c.journal" 2>&1 || echo "code $?" >> "$T/cas/$c.journal"
  }
  vex_seul() { # cas dépôt-de-l'image digest : mode vex de scanner.sh, puis les commandes d'analyser (fusion, grype, predicat)
    local c=$1 i="$REG/$2@$3"
    scanner vex "$c" IMAGE="$i"
    ( cd "$T/cas/$c"
      "$OUT" fusion "$G0/sbom-source.json" "$M0/image-artefact.json" source image "$i" > sbom.json
      set --; for f in $(sed -n 's/.*"fichier": *"\([^"]*\)".*/\1/p' vex-retenus.json); do set -- "$@" --vex "$f"; done
      grype_hors_ligne sbom:sbom.json "$@" -o json --file grype.json -q
      "$OUT" predicat grype.json base-g0 vex-retenus.json > scan.json ) >> "$T/cas/$c.journal" 2>&1 || echo "code $?" >> "$T/cas/$c.journal"
  }
  ligne_vex() { { grep '^VEX|' "$T/cas/$1.journal" || true; } | head -1 | cut -d'|' -f2 | sed 's/[^0-9,]//g'; }
  juger_vex() { # cas compte-attendu m/i-attendu
    local l v
    l=$(grep '^VEX|' "$T/cas/$1.journal" | head -1 || true)
    v=$(ligne_vex "$1")
    [ "$v" = "$2" ] && ok "$1 : VEX vérifiés, retenus, rejetés $v" || ko "$1 : VEX $v, prédit $2 ; $(cut -c1-300 <<< "$l")"
    grep '^REJET|' "$T/cas/$1.journal" | sed 's/^/     /' || true
    [ -s "$T/cas/$1/scan.json" ] && attendu "$1 : entrées sans VEX / avec VEX" "$(mi "$T/cas/$1/scan.json")" "$3" \
      || ko "$1 : aucun prédicat ; $(grep -v '^VEX\|^REJET' "$T/cas/$1.journal" | tail -2 | cut -c1-300 | tr '\n' ' ')"
  }

  H1=$(date -ud '1 day ago' +%FT%TZ)
  ok_vex() { vex doc "$1" "$H1" "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"; }

  echo "## B. scanner.sh du patch, Zot jetable $REG"
  # 1. analyser complet, image
  d=$(pousser "$M0/image" builds/complet/sample-app); attendu "image poussée (complet)" "$d" "$Y"
  ok_vex "$T/v-complet.json"; publier_vex vex "$T/v-complet.json" "$Y" builds/complet/sample-app "$Y" builds/vex/complet/sample-app
  mkdir -p "$T/cas/complet"; cp -r "$G0/source" "$T/cas/complet/source"
  scanner analyser complet IMAGE="$REG/builds/complet/sample-app@$Y" BASES="$REG/vulndb/grype"
  { grep -E '^(BASE|IMPORT|ARTEFACT|SBOM|VEX|REJET|SCAN|PREDICAT)\|' "$T/cas/complet.journal" || true; } | cut -c1-260 | sed "s|$T|<banc>|g; s/^/     /"
  tail -3 "$T/cas/complet.journal" | grep -i 'code\|error' | cut -c1-300 || true
  juger_vex complet 1,1,0 4/1
  if [ -s "$T/cas/complet/scan.json" ]; then
    attendu "complet : entrée écartée" "$(jq -r '[.vulnerabilities[] | select(has("vex")) | "\(.id) \(.vex.status) \(.vex.timestamp)"] | join(",")' "$T/cas/complet/scan.json")" "$VULN not_affected $H1"
    attendu "complet : documents du prédicat = empreinte de l'énoncé signé" "$(jq -r '[.vex.documents[].sha256] | join(",")' "$T/cas/complet/scan.json")" "$(cat "$T/empreinte-v-complet")"
  fi
  # 2. autre sujet, simple : VEX signé pour X, referrer de X
  d=$(pousser "$M0/image" builds/simple/sample-app)
  x=$(crane mutate --label poc.test/cas=t3-autre -t "$REG/builds/autre/sample-app:t3" "$REG/builds/simple/sample-app@$d" 2>> "$T/crane.err"); x=${x##*@}
  [ "$x" != "$Y" ] && ok "X ($x) différent de Y" || ko "X égal à Y"
  ok_vex "$T/v-simple.json"; publier_vex vex "$T/v-simple.json" "$x" builds/autre/sample-app "$x" builds/vex/simple/sample-app
  vex_seul simple builds/simple/sample-app "$Y"; juger_vex simple 0,0,0 5/0
  # 3. autre sujet, adverse : signé pour X, referrer de Y
  pousser "$M0/image" builds/adverse/sample-app > /dev/null
  ok_vex "$T/v-adverse.json"; publier_vex vex "$T/v-adverse.json" "$x" builds/adverse/sample-app "$Y" builds/vex/adverse/sample-app
  echo "     referrers de Y sous builds/vex/adverse : $(curl -fsS --cacert zot.crt "https://$REG/v2/builds/vex/adverse/sample-app/referrers/$Y" | jq '.manifests | length')"
  vex_seul adverse builds/adverse/sample-app "$Y"; juger_vex adverse 0,0,0 5/0
  # 4. autre clé
  pousser "$M0/image" builds/etrangere/sample-app > /dev/null
  ok_vex "$T/v-etrangere.json"; publier_vex etrangere "$T/v-etrangere.json" "$Y" builds/etrangere/sample-app "$Y" builds/vex/etrangere/sample-app
  vex_seul etrangere builds/etrangere/sample-app "$Y"; juger_vex etrangere 0,0,0 5/0
  # 5. fixed ; 6. sans impact_statement
  pousser "$M0/image" builds/fixed/sample-app > /dev/null
  vex doc "$T/v-fixed.json" "$H1" "fixed;-;-;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  publier_vex vex "$T/v-fixed.json" "$Y" builds/fixed/sample-app "$Y" builds/vex/fixed/sample-app
  vex_seul fixed builds/fixed/sample-app "$Y"; juger_vex fixed 1,0,1 5/0
  pousser "$M0/image" builds/sans-impact/sample-app > /dev/null
  vex doc "$T/v-sans-impact.json" "$H1" "not_affected;$JUSTIF;-;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  publier_vex vex "$T/v-sans-impact.json" "$Y" builds/sans-impact/sample-app "$Y" builds/vex/sans-impact/sample-app
  vex_seul sans-impact builds/sans-impact/sample-app "$Y"; juger_vex sans-impact 1,0,1 5/0
  # 7. deux documents, ancien et récent
  pousser "$M0/image" builds/deux/sample-app > /dev/null
  vex doc "$T/v-deux-a.json" 2026-11-01T00:00:00Z "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  vex doc "$T/v-deux-b.json" 2026-11-20T00:00:00Z "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  publier_vex vex "$T/v-deux-a.json" "$Y" builds/deux/sample-app "$Y" builds/vex/deux/sample-app
  publier_vex vex "$T/v-deux-b.json" "$Y" builds/deux/sample-app "$Y" builds/vex/deux/sample-app
  vex_seul deux builds/deux/sample-app "$Y"; juger_vex deux 2,2,0 4/1
  [ -s "$T/cas/deux/scan.json" ] && attendu "deux : horodatage de l'entrée" "$(jq -r '[.vulnerabilities[] | select(has("vex")) | .vex.timestamp] | join(",")' "$T/cas/deux/scan.json")" 2026-11-20T00:00:00Z
  # 8. clé VEX absente du conteneur
  pousser "$M0/image" builds/sans-cle/sample-app > /dev/null
  ok_vex "$T/v-sans-cle.json"; publier_vex vex "$T/v-sans-cle.json" "$Y" builds/sans-cle/sample-app "$Y" builds/vex/sans-cle/sample-app
  scanner vex sans-cle IMAGE="$REG/builds/sans-cle/sample-app@$Y" CLE_VEX="$T/cle/absente.pub"
  ( cd "$T/cas/sans-cle"
    "$OUT" fusion "$G0/sbom-source.json" "$M0/image-artefact.json" source image "$REG/builds/sans-cle/sample-app@$Y" > sbom.json
    set --; for f in $(sed -n 's/.*"fichier": *"\([^"]*\)".*/\1/p' vex-retenus.json); do set -- "$@" --vex "$f"; done
    grype_hors_ligne sbom:sbom.json "$@" -o json --file grype.json -q
    "$OUT" predicat grype.json base-g0 vex-retenus.json > scan.json ) >> "$T/cas/sans-cle.journal" 2>&1 || true
  juger_vex sans-cle 0,0,0 5/0
  { grep '^VEX|' "$T/cas/sans-cle.journal" || true; } | cut -d'|' -f4 | cut -c1-200 | sed 's/^/     /'
  # 9. analyser complet, deb
  d=$(pousser "$M0/deb" builds/deb-complet/sample-app-deb); attendu "deb poussé" "$d" "$DEB"
  vex doc "$T/v-deb.json" "$H1" "not_affected;$JUSTIF;$IMPACT;-;GO-2025-3849;pkg:oci/sample-app-deb@$DEB;pkg:golang/stdlib@1.24.4"
  publier_vex vex "$T/v-deb.json" "$DEB" builds/deb-complet/sample-app-deb "$DEB" builds/vex/deb-complet/sample-app-deb
  mkdir -p "$T/cas/deb-complet"; cp -r "$G0/source" "$T/cas/deb-complet/source"
  scanner analyser deb-complet IMAGE="$REG/builds/deb-complet/sample-app-deb@$DEB" BASES="$REG/vulndb/grype" NATURE=deb
  { grep -E '^(DEB|EXTRAIT|ARTEFACT|SBOM|VEX|REJET|SCAN)\|' "$T/cas/deb-complet.journal" || true; } | cut -c1-260 | sed "s|$T|<banc>|g; s/^/     /"
  juger_vex deb-complet 1,1,0 65/1
  # 10. VEX daté du futur
  pousser "$M0/image" builds/futur/sample-app > /dev/null
  vex doc "$T/v-futur.json" 2027-01-01T00:00:00Z "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  publier_vex vex "$T/v-futur.json" "$Y" builds/futur/sample-app "$Y" builds/vex/futur/sample-app
  vex_seul futur builds/futur/sample-app "$Y"; juger_vex futur 1,1,0 4/1
  # 11, 12 (passage 5) : énoncé retenu par le filtre, sans products ou sans vulnerability ; issue de Grype relevée
  for c in sans-produits sans-vulnerabilite; do
    pousser "$M0/image" "builds/$c/sample-app" > /dev/null
    case $c in sans-produits) e="not_affected;$JUSTIF;$IMPACT;-;$VULN;-;-" ;; *) e="not_affected;$JUSTIF;$IMPACT;-;-;pkg:oci/sample-app@$Y;$SYFT" ;; esac
    vex doc "$T/v-$c.json" "$H1" "$e"
    publier_vex vex "$T/v-$c.json" "$Y" "builds/$c/sample-app" "$Y" "builds/vex/$c/sample-app"
    vex_seul "$c" "builds/$c/sample-app" "$Y"
    echo "     $c : $(grep '^code' "$T/cas/$c.journal" || echo 'grype et predicat sans erreur') ; $(grep -v '^VEX\|^REJET\|^code' "$T/cas/$c.journal" | head -1 | cut -c1-200)"
    juger_vex "$c" 1,1,0 5/0
  done
  # 13 (passage 5) : sonde du passage 3 archivée, sur les deux documents du cas deux
  for forme in virgule repete; do
    c=0
    case $forme in virgule) set -- --vex "$T/cas/deux/vex/vex-0.json,$T/cas/deux/vex/vex-1.json" ;; *) set -- --vex "$T/cas/deux/vex/vex-0.json" --vex "$T/cas/deux/vex/vex-1.json" ;; esac
    grype_hors_ligne "sbom:$T/cas/deux/sbom.json" "$@" -o json --file "$T/cas/deux-$forme.json" -q > "$T/cas/deux-$forme.err" 2>&1 || c=$?
    r="code $c"; [ "$c" != 0 ] || r="$r, $(jq -r '"\(.matches | length)/\(.ignoredMatches // [] | length)"' "$T/cas/deux-$forme.json")"
    case $forme in virgule) attendu "Grype, --vex a,b" "$r" "code 1" ;; *) attendu "Grype, --vex a --vex b" "$r" "code 0, 4/1" ;; esac
  done
  # 14 (passage 6) : renouvellement d'un VEX par retrait de l'ancien référent ; ancien document à plus de 30 jours, récent de la veille
  referents() { curl -fsS --cacert zot.crt "https://$REG/v2/builds/vex/renouv/sample-app/referrers/$Y" | jq '.manifests | length'; }
  retirer() { # document : retrait du référent qui le porte ; code et référents restants
    local c=0
    oras manifest delete --force --ca-file zot.crt "$REG/builds/vex/renouv/sample-app@sha256:$(cat "$T/manifeste-$1")" > "$T/retrait-$1.log" 2>&1 || c=$?
    echo "code $c ; référents $(referents)"
  }
  pousser "$M0/image" builds/renouv/sample-app > /dev/null
  vex doc "$T/v-renouv-ancien.json" 2026-10-01T00:00:00Z "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  ok_vex "$T/v-renouv-recent.json"
  publier_vex vex "$T/v-renouv-ancien.json" "$Y" builds/renouv/sample-app "$Y" builds/vex/renouv/sample-app
  publier_vex vex "$T/v-renouv-recent.json" "$Y" builds/renouv/sample-app "$Y" builds/vex/renouv/sample-app
  attendu "renouv : référents publiés" "$(referents)" 2
  vex_seul renouv-avant builds/renouv/sample-app "$Y"; juger_vex renouv-avant 2,2,0 4/1
  [ -s "$T/cas/renouv-avant/scan.json" ] && attendu "renouv-avant : horodatage de l'entrée" "$(jq -r '[.vulnerabilities[] | select(has("vex")) | .vex.timestamp] | join(",")' "$T/cas/renouv-avant/scan.json")" "$H1"
  attendu "renouv : retrait de l'ancien référent" "$(retirer v-renouv-ancien)" "code 0 ; référents 1"
  vex_seul renouv-apres builds/renouv/sample-app "$Y"; juger_vex renouv-apres 1,1,0 4/1
  [ -s "$T/cas/renouv-apres/scan.json" ] && attendu "renouv-apres : horodatage de l'entrée" "$(jq -r '[.vulnerabilities[] | select(has("vex")) | .vex.timestamp] | join(",")' "$T/cas/renouv-apres/scan.json")" "$H1"
  attendu "renouv : retrait du dernier référent" "$(retirer v-renouv-recent)" "code 0 ; référents 0"
  vex_seul renouv-vide builds/renouv/sample-app "$Y"; juger_vex renouv-vide 0,0,0 5/0
  # 15-17 (passage 7) : remplacement ; ordre de publication inversé, rétractation sous l'alias, remplacement partiel
  H2=$(date -ud '2 days ago' +%FT%TZ)
  horo() { jq -r '[.vulnerabilities[] | select(has("vex")) | "\(.id) \(.vex.timestamp)"] | join(",")' "$T/cas/$1/scan.json"; }
  pousser "$M0/image" builds/inverse/sample-app > /dev/null
  ok_vex "$T/v-inverse-recent.json"
  vex doc "$T/v-inverse-ancien.json" 2026-10-01T00:00:00Z "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  publier_vex vex "$T/v-inverse-recent.json" "$Y" builds/inverse/sample-app "$Y" builds/vex/inverse/sample-app
  publier_vex vex "$T/v-inverse-ancien.json" "$Y" builds/inverse/sample-app "$Y" builds/vex/inverse/sample-app
  vex_seul inverse builds/inverse/sample-app "$Y"; juger_vex inverse 2,2,0 4/1
  [ -s "$T/cas/inverse/scan.json" ] && attendu "inverse : horodatage de l'entrée" "$(horo inverse)" "$VULN $H1"
  pousser "$M0/image" builds/retract/sample-app > /dev/null
  vex doc "$T/v-retract-ancien.json" "$H2" "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  publier_vex vex "$T/v-retract-ancien.json" "$Y" builds/retract/sample-app "$Y" builds/vex/retract/sample-app
  vex_seul retract-avant builds/retract/sample-app "$Y"; juger_vex retract-avant 1,1,0 4/1
  [ -s "$T/cas/retract-avant/scan.json" ] && attendu "retract-avant : horodatage de l'entrée" "$(horo retract-avant)" "$VULN $H2"
  vex doc "$T/v-retract-affected.json" "$H1" "affected;-;-;-;CVE-2025-69725;pkg:oci/sample-app@$Y;$SYFT"
  publier_vex vex "$T/v-retract-affected.json" "$Y" builds/retract/sample-app "$Y" builds/vex/retract/sample-app
  vex_seul retract-apres builds/retract/sample-app "$Y"; juger_vex retract-apres 2,1,1 5/0
  [ -s "$T/cas/retract-apres/scan.json" ] && attendu "retract-apres : écartées sans exemption" "$(jq -r .vex.ecarteesSansExemption "$T/cas/retract-apres/scan.json")" 1
  pousser "$M0/image" builds/partiel/sample-app > /dev/null
  vex doc "$T/v-partiel-ancien.json" 2026-10-01T00:00:00Z "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT" \
    "not_affected;$JUSTIF;$IMPACT;-;GHSA-j6qf-3m9c-vwj3;pkg:oci/sample-app@$Y;$SYFT"
  ok_vex "$T/v-partiel-recent.json"
  publier_vex vex "$T/v-partiel-ancien.json" "$Y" builds/partiel/sample-app "$Y" builds/vex/partiel/sample-app
  publier_vex vex "$T/v-partiel-recent.json" "$Y" builds/partiel/sample-app "$Y" builds/vex/partiel/sample-app
  vex_seul partiel builds/partiel/sample-app "$Y"; juger_vex partiel 2,2,0 3/2
  [ -s "$T/cas/partiel/scan.json" ] && attendu "partiel : horodatages des entrées" "$(horo partiel)" "GHSA-j6qf-3m9c-vwj3 2026-10-01T00:00:00Z,$VULN $H1"
  # 18-21 (passage 11) : pièce 8, signer-vex.sh signer avec la clé locale vex (pas hashivault://vex) ; prédicat de scan du cas complet
  echo "## B. signer-vex.sh signer (pièce 8), clé locale"
  pousser "$M0/image" builds/signe/sample-app > /dev/null
  referents_signe() { { curl -fsS --cacert zot.crt "https://$REG/v2/builds/vex/signe/sample-app/referrers/$Y" 2>/dev/null || echo '{}'; } | jq '.manifests // [] | length'; }
  signer_vex() { # clé document cas : code de signer-vex.sh signer et référents après
    local c=0
    env COSIGN_PASSWORD='' SCAN_OUTIL="$OUT" CLE="$T/cle/$1.key" CLE_PUBLIQUE="$T/cle/vex.pub" CA="$T/zot.crt" CONFIG_REGISTRE="$T/docker/config.json" \
      bash "$B/signer-vex.sh" signer "$2" "$REG/builds/signe/sample-app@$Y" "$T/cas/complet/scan.json" > "$T/signer-$3.log" 2>&1 || c=$?
    echo "code $c ; référents $(referents_signe)"
  }
  vex doc "$T/v-signe-futur.json" "$(date -ud tomorrow +%FT%TZ)" "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  attendu "signer, daté du futur : refus avant signature" "$(signer_vex vex "$T/v-signe-futur.json" futur)" "code 1 ; référents 0"
  attendu "signer, daté du futur : motif" "$(grep -c '^REFUS|horodatage' "$T/signer-futur.log")" 1
  ok_vex "$T/v-signe-ok.json"
  attendu "signer, clé étrangère : refus avant publication" "$(signer_vex etrangere "$T/v-signe-ok.json" etrangere)" "code 1 ; référents 0"
  attendu "signer, clé étrangère : motif" "$(grep -c '^REFUS|signature non vérifiée' "$T/signer-etrangere.log")" 1
  attendu "signer, clé vex : publié" "$(signer_vex vex "$T/v-signe-ok.json" ok)" "code 0 ; référents 1"
  grep -E '^(JUGE|SIGNE|PUBLIE)\|' "$T/signer-ok.log" | cut -c1-200 | sed "s|$T|<banc>|g; s/^/     /" || true
  vex_seul signe-ok builds/signe/sample-app "$Y"; juger_vex signe-ok 1,1,0 4/1
  [ -s "$T/cas/signe-ok/scan.json" ] && attendu "signe-ok : entrée écartée" "$(horo signe-ok)" "$VULN $H1"
  [ -s "$T/cas/signe-ok/scan.json" ] && attendu "signe-ok : documents du prédicat = énoncé signé annoncé par SIGNE" \
    "$(jq -r '[.vex.documents[].sha256] | join(",")' "$T/cas/signe-ok/scan.json")" "$(sed -n 's/^SIGNE|.*énoncé signé sha256 \([0-9a-f]*\).*/\1/p' "$T/signer-ok.log")"
  vex doc "$T/v-signe-retract.json" "$(date -u +%FT%TZ)" "affected;-;-;-;CVE-2025-69725;pkg:oci/sample-app@$Y;$SYFT"
  jq -c '.statements |= map(. + {action_statement: "témoin du banc : aucune action"})' "$T/v-signe-retract.json" > "$T/v-signe-retract.t" && mv "$T/v-signe-retract.t" "$T/v-signe-retract.json"   # passage 12
  attendu "signer, rétractation : publiée" "$(signer_vex vex "$T/v-signe-retract.json" retract)" "code 0 ; référents 2"
  vex_seul signe-retract builds/signe/sample-app "$Y"; juger_vex signe-retract 2,1,1 5/0
  [ -s "$T/cas/signe-retract/scan.json" ] && attendu "signe-retract : écartées sans exemption" "$(jq -r .vex.ecarteesSansExemption "$T/cas/signe-retract/scan.json")" 1
  echo "$KO" > "$T/ko-ns"
  exit 0
fi

# ---------------------------------------------------------------------------------------------------------------------- préparation
empreinte() { find "$G0/dbcache" "$G0/source" "$G0/sbom-source.json" "$M0/image" "$M0/deb" -printf '%p %s %T@\n' | sort | sha256sum | cut -c1-16; }
[ ! -e ~/.cache/supply-chain-poc/07a/t3/banc ] || { chmod -R u+w ~/.cache/supply-chain-poc/07a/t3/banc; find ~/.cache/supply-chain-poc/07a/t3/banc -delete; }
(umask 077 && mkdir -p "$T/cle" "$T/docker" "$T/tmp" "$T/outil" "$T/cas")
echo '{}' > "$T/docker/config.json"
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "outils : grype $(grype version 2>/dev/null | awk '/^Version/ {print $2}'), syft $(syft version 2>/dev/null | awk '/^Version/ {print $2}'),\
 cosign $(cosign version 2>/dev/null | awk '/^GitVersion/ {print $2}'), zot $(zot --version 2>&1 | grep -o 'v[0-9][0-9.]*' | head -1), ec $(ec version 2>/dev/null | awk '/^Version/ {print $2}'), $(go version | cut -d' ' -f3)"
echo "patch : politique/07b-t3.patch $(sha256sum < "$RACINE/poc/bricks/07a-sbom-grype/politique/07b-t3.patch" | cut -c1-16)… ; 07b-t3-vex.py $(sha256sum < "$R/07b-t3-vex.py" | cut -c1-16)…"
avant=$(empreinte)
for f in outil/main.go outil/go.mod politique/scanner.sh politique/porte/scan.rego politique/porte/scan_test.rego politique/porte/policy-scan.yaml plateforme.sh entrees-scan.sh systemd/entrees-scan.py; do
  mkdir -p "$(dirname "$B/$f")"; cp "$RACINE/poc/bricks/07a-sbom-grype/$f" "$B/$f"
done
(cd "$T/arbre" && patch -p1 --quiet < "$RACINE/poc/bricks/07a-sbom-grype/politique/07b-t3.patch") && ok "patch appliqué sur une copie des fichiers du dépôt" \
  || { ko "patch non applicable"; exit 1; }
(cd "$B/outil" && CGO_ENABLED=0 GOFLAGS=-mod=mod GOCACHE=$T/tmp/gocache go build -trimpath -buildvcs=false -o "$OUT" .) && ok "scan-outil du patch construit"
(cd "$B/outil" && GOCACHE=$T/tmp/gocache go vet .) && ok "go vet"

# ------------------------------------------------------------------------------------------------------------------------------ A
echo "## A. hôte, hors réseau"
c=0; "$OUT" fusion "$G0/sbom-source.json" "$M0/image-artefact.json" source image "sample-app:latest" > /dev/null 2> "$T/tmp/err" || c=$?
attendu "fusion, image sans digest" "code $c" "code 1"
echo '{"retenus":[],"rejetes":[]}' > "$T/vide.json"
for a in image deb; do
  "$OUT" predicat "$M0/$a-avant.grype.json" base-g0 "$T/vide.json" > "$T/compat-$a.json"
  [ "$(jq -S . "$T/compat-$a.json")" = "$(jq -S '. + {vex: {documents: [], rejetes: 0, ecarteesSansExemption: 0}}' "$M0/$a-avant.scan.json")" ] \
    && ok "compatibilité $a : prédicat neuf sans VEX = prédicat d'avant + bloc vex vide (compteur à 0, passage 8)" || ko "compatibilité $a : différences"
done
mkdir -p "$T/regles/m"; cp "$B/politique/porte/scan.rego" "$B/politique/porte/scan_test.rego" "$T/regles/"
(cd "$T/regles" && ec opa check scan.rego scan_test.rego) && ok "ec opa check" || ko "ec opa check"
r=$(cd "$T/regles" && ec opa test scan.rego scan_test.rego 2>&1 | tail -1 || true); [ "$r" = "PASS: $(grep -c '^test_' "$T/regles/scan_test.rego")/$(grep -c '^test_' "$T/regles/scan_test.rego")" ] && ok "ec opa test : $r" || ko "ec opa test : $r"
awk '/^etape_g5_regles\(\)/ {f = 1} f && /^  done <<.FIN.$/ {g = 1; next} g && /^FIN$/ {exit} g' "$B/plateforme.sh" > "$T/regles/mutations"
n=0
while IFS= read -r c; do
  grep -vF -- "$c" "$T/regles/scan.rego" > "$T/regles/m/scan.rego"
  [ "$(wc -l < "$T/regles/m/scan.rego")" = $(($(wc -l < "$T/regles/scan.rego") - 1)) ] || { ko "mutation absente ou ambiguë : $c"; continue; }
  r=$(cd "$T/regles" && ec opa test m/scan.rego scan_test.rego 2>&1 | sed -n 's/^data\.scan_test\.\(test_[a-z0-9_]*\): FAIL.*/\1/p' | paste -sd, -) || true
  [ -n "$r" ] && n=$((n + 1)) || ko "condition non couverte : $c"
done < "$T/regles/mutations"
attendu "mutations couvertes" "$n/$(wc -l < "$T/regles/mutations")" "$(wc -l < "$T/regles/mutations")/$(wc -l < "$T/regles/mutations")"

echo "## A. scan-outil vex, cas unitaires (énoncés non signés)"
U=$T/unit; mkdir -p "$U/sortie"
S1="$JUSTIF;$IMPACT"
unite() { # cas sujet prédicat-type [contexte] -- énoncé(s) : document puis énoncé in-toto
  local c=$1 s=$2 pt=$3 h=$4; shift 4
  vex doc "$U/$c.vex" "$h" "$@"
  vex enonce "$U/$c.json" "$pt" "${s#sha256:}" "$U/$c.vex" ${CTX:+"$CTX"}
}
E="$VULN;pkg:oci/sample-app@$Y;$SYFT"
unite valide "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$E"
unite fixed "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "fixed;-;-;-;$E"
unite affected "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "affected;-;-;-;$E"
unite sans-impact "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$JUSTIF;-;-;$E"
unite impact-blanc "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$JUSTIF;   ;-;$E"
unite sans-justification "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;-;$IMPACT;-;$E"
unite justification-libre "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;parce que;$IMPACT;-;$E"
unite mixte "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$E" "not_affected;$JUSTIF;-;-;$E"
unite autre-sujet "sha256:$(printf '1%.0s' $(seq 64))" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$E"
unite autre-type "$Y" https://example.com/autre 2026-11-20T00:00:00Z "not_affected;$S1;-;$E"
CTX=https://openvex.dev/ns/v0.1.0 unite autre-contexte "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$E"
unite sans-horodatage-enonce "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$E"
unite deux-horodatages "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;2026-11-05T10:00:00Z;$E" "not_affected;$S1;2026-11-03T08:00:00Z;$E"
unite horodatage-illisible "$Y" "$OPENVEX" hier "not_affected;$S1;-;$E"
unite aucun-enonce "$Y" "$OPENVEX" 2026-11-20T00:00:00Z
while read -r c attendu_r; do
  rm -f "$U"/sortie/*
  "$OUT" vex "${Y#sha256:}" "$U/sortie" "$U/$c.json" > "$U/$c.res" 2> "$U/$c.err" || { ko "$c : code $?, $(head -c 200 "$U/$c.err")"; continue; }
  r=$(jq -r 'if (.retenus | length) == 1 then "retenu \(.retenus[0].timestamp)" elif (.rejetes | length) == 1 then "rejeté" else "?" end' "$U/$c.res")
  attendu "vex $c" "$r" "$attendu_r"
  jq -r '.rejetes[] | "     raison : \(.raison)"' "$U/$c.res"
done <<'FIN'
valide retenu 2026-11-20T00:00:00Z
fixed rejeté
affected rejeté
sans-impact rejeté
impact-blanc rejeté
sans-justification rejeté
justification-libre rejeté
mixte rejeté
autre-sujet rejeté
autre-type rejeté
autre-contexte rejeté
sans-horodatage-enonce retenu 2026-11-20T00:00:00Z
deux-horodatages retenu 2026-11-03T08:00:00Z
horodatage-illisible rejeté
aucun-enonce rejeté
FIN
[ "$(jq -S . <<< "$(cd "$U" && "$OUT" vex "${Y#sha256:}" "$U/sortie")")" = "$(jq -S . <<< '{"retenus":[],"rejetes":[]}')" ] && ok "vex sans fichier : 0 retenu, 0 rejeté" || ko "vex sans fichier"
rm -f "$U"/sortie/*; "$OUT" vex "${Y#sha256:}" "$U/sortie" "$U/valide.json" > /dev/null
[ "$(jq -cS . "$U/sortie/vex-0.json")" = "$(jq -cS .predicate "$U/valide.json")" ] && ok "document écrit = prédicat de l'énoncé" || ko "document écrit différent du prédicat"
jq '.ignoredMatches = [.matches[0] + {appliedIgnoreRules: [{namespace: "vex", "vex-status": "not_affected"}]}] | .matches |= .[1:]' "$M0/image-avant.grype.json" > "$T/ecarte-sans-doc.json"
c=0; "$OUT" predicat "$T/ecarte-sans-doc.json" base-g0 "$T/vide.json" > /dev/null 2> "$T/tmp/err" || c=$?
attendu "predicat : écartée par un VEX sans document retenu" "code $c" "code 1"
# passage 7 : remplacement, le plus récent qui nomme l'entrée l'emporte (noms et alias, tout produit) ; égalité fermée
unite pa "$Y" "$OPENVEX" 2026-11-01T00:00:00Z "not_affected;$S1;-;$E"
unite pb "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$E"
unite pr "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "affected;-;-;-;$E"
unite pr-alias "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "affected;-;-;-;CVE-2025-69725;pkg:oci/sample-app@$Y;$SYFT"
unite pr-ancien "$Y" "$OPENVEX" 2026-11-01T00:00:00Z "affected;-;-;-;$E"
unite pb-autre-produit "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$VULN;pkg:oci/autre@sha256:$(printf '1%.0s' $(seq 64));$SYFT"
unite pb-autre-vuln "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;GHSA-j6qf-3m9c-vwj3;pkg:oci/sample-app@$Y;$SYFT"
# passage 9 : le gagnant doit couvrir le paquet de l'entrée (énoncé large, ou PURL parmi les sous-composants)
unite pb-autre-sous "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$VULN;pkg:oci/sample-app@$Y;pkg:golang/stdlib@1.24.4"
unite pb-large "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$VULN;pkg:oci/sample-app@$Y;-"
# passage 10 : un énoncé exemptant qui ne couvre pas le paquet sort du classement ; une rétractation garde sa portée large
unite pd-deux-paquets "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "not_affected;$S1;-;$E" "not_affected;$S1;-;$VULN;pkg:oci/sample-app@$Y;pkg:golang/stdlib@1.24.4"
unite pr-autre-sous "$Y" "$OPENVEX" 2026-11-20T00:00:00Z "affected;-;-;-;$VULN;pkg:oci/sample-app@$Y;pkg:golang/stdlib@1.24.4"
while read -r c a b attendu_r; do
  rm -f "$U"/sortie/*
  set -- "$U/$a.json"; [ "$b" = - ] || set -- "$@" "$U/$b.json"
  "$OUT" vex "${Y#sha256:}" "$U/sortie" "$@" > "$U/p-$c.res"
  c2=0; "$OUT" predicat "$T/ecarte-sans-doc.json" base-g0 "$U/p-$c.res" > "$U/p-$c.scan" 2> "$T/tmp/err" || c2=$?
  r=$(jq -r --arg v "$VULN" '([.vulnerabilities[] | select(.id == $v) | .vex // empty] | if length == 1 then "vex \(.[0].status) \(.[0].timestamp)" else "aucune" end) + " ; sans exemption \(.vex.ecarteesSansExemption)"' "$U/p-$c.scan" 2>/dev/null || echo "code $c2")
  attendu "predicat, remplacement : $c" "$r" "$attendu_r"
done <<'FIN'
remplacement pa pb vex not_affected 2026-11-20T00:00:00Z ; sans exemption 0
ordre-inverse pb pa vex not_affected 2026-11-20T00:00:00Z ; sans exemption 0
retractation pa pr aucune ; sans exemption 1
retractation-alias pa pr-alias aucune ; sans exemption 1
egalite pb pr aucune ; sans exemption 1
reaffirmation pr-ancien pb vex not_affected 2026-11-20T00:00:00Z ; sans exemption 0
autre-produit pa pb-autre-produit aucune ; sans exemption 1
autre-vuln pa pb-autre-vuln vex not_affected 2026-11-01T00:00:00Z ; sans exemption 0
autre-sous-composant pa pb-autre-sous vex not_affected 2026-11-01T00:00:00Z ; sans exemption 0
large pa pb-large vex not_affected 2026-11-20T00:00:00Z ; sans exemption 0
deux-paquets pd-deux-paquets - vex not_affected 2026-11-20T00:00:00Z ; sans exemption 0
affected-autre-sous pa pr-autre-sous aucune ; sans exemption 1
FIN

# passage 11 : pièce 8, signer-vex.sh verifier (jugement avant signature, sans registre) ; prédicat de scan de la mesure 0
echo "## A. signer-vex.sh verifier (pièce 8), témoins non signés"
SV=$T/signer; mkdir -p "$SV"
HF=$(date -ud tomorrow +%FT%TZ); HV=$(date -ud '1 day ago' +%FT%TZ)
vex doc "$SV/ok.json" "$HV" "not_affected;$S1;-;$E"
vex doc "$SV/futur.json" "$HF" "not_affected;$S1;-;$E"
vex doc "$SV/futur-enonce.json" "$HV" "not_affected;$S1;$HF;$E"
# passage 12 : affected exige action_statement (OpenVEX v0.2.0) ; ajouté par jq, 07b-t3-vex.py inchangé
action() { jq -c '.statements |= map(if .status == "affected" then . + {action_statement: "témoin du banc : aucune action"} else . end)' "$1" > "$1.t" && mv "$1.t" "$1"; }
vex doc "$SV/retract.json" "$HV" "affected;-;-;-;CVE-2025-69725;pkg:oci/sample-app@$Y;$SYFT"
action "$SV/retract.json"
vex doc "$SV/large.json" "$HV" "not_affected;$S1;-;$VULN;pkg:oci/sample-app@$Y;-"
vex doc "$SV/absent.json" "$HV" "not_affected;$S1;-;$VULN;pkg:oci/sample-app@$Y;pkg:golang/github.com/go-chi/chi@v5.2.4#v5"
vex doc "$SV/fixed.json" "$HV" "fixed;-;-;-;$E"
vex doc "$SV/mixte.json" "$HV" "not_affected;$S1;-;$E" "affected;-;-;-;GHSA-j6qf-3m9c-vwj3;pkg:oci/sample-app@$Y;$SYFT"
vex doc "$SV/sans-impact.json" "$HV" "not_affected;$JUSTIF;-;-;$E"
vex doc "$SV/autre-digest.json" "$HV" "not_affected;$S1;-;$VULN;pkg:oci/sample-app@$DEB;$SYFT"
vex doc "$SV/sans-vuln.json" "$HV" "not_affected;$S1;-;-;pkg:oci/sample-app@$Y;$SYFT"
vex doc "$SV/sans-horo.json" - "not_affected;$S1;-;$E"
while read -r c attendu_r; do
  r=0; SCAN_OUTIL=$OUT bash "$B/signer-vex.sh" verifier "$SV/$c.json" "$REG/builds/x/sample-app@$Y" "$M0/image-avant.scan.json" > "$SV/$c.log" 2>&1 || r=$?
  attendu "signer-vex verifier : $c" "code $r : $(sed -n 's/^\(JUGE|[a-z]*, [0-9]* énoncé(s) dont [0-9]* large(s)\).*/\1/p; s/^REFUS|\([^:(0-9]*\).*/REFUS|\1/p' "$SV/$c.log" | head -1 | sed 's/ *$//')" "$attendu_r"
done <<'FIN'
ok code 0 : JUGE|exemption, 1 énoncé(s) dont 0 large(s)
futur code 1 : REFUS|horodatage
futur-enonce code 1 : REFUS|horodatage
retract code 0 : JUGE|retractation, 1 énoncé(s) dont 0 large(s)
large code 0 : JUGE|exemption, 1 énoncé(s) dont 1 large(s)
absent code 1 : REFUS|sous-composant absent des entrées du prédicat de scan
fixed code 1 : REFUS|statut fixed
mixte code 1 : REFUS|not_affected mêlé à d'autres statuts
sans-impact code 1 : REFUS|rejeté par scan-outil vex
autre-digest code 1 : REFUS|énoncé sans produit dont l'@id cite le digest
sans-vuln code 1 : REFUS|énoncé sans nom de vulnérabilité
sans-horo code 1 : REFUS|énoncés non classables par scan-outil vex
FIN
r=0; bash "$B/signer-vex.sh" verifier "$SV/ok.json" "$REG/builds/x/sample-app:t3" "$M0/image-avant.scan.json" > /dev/null 2>&1 || r=$?
attendu "signer-vex verifier : image sans digest" "code $r" "code 2"
# passage 12 : noms confrontés au scan (rétractation mal nommée), couple vulnérabilité et paquet, action_statement
jq '.vulnerabilities |= map(if .id == "GO-2026-5774" then .package = "pkg:golang/stdlib@1.24.4" else . end)' "$M0/image-avant.scan.json" > "$SV/scan-deux.json"
vex doc "$SV/retract-faute.json" "$HV" "affected;-;-;-;CVE-2025-69752;pkg:oci/sample-app@$Y;$SYFT"; action "$SV/retract-faute.json"
vex doc "$SV/retract-sans-action.json" "$HV" "affected;-;-;-;CVE-2025-69725;pkg:oci/sample-app@$Y;$SYFT"
vex doc "$SV/couple-faux.json" "$HV" "not_affected;$S1;-;GO-2026-5774;pkg:oci/sample-app@$Y;$SYFT"
vex doc "$SV/couple-ok.json" "$HV" "not_affected;$S1;-;GO-2026-5774;pkg:oci/sample-app@$Y;pkg:golang/stdlib@1.24.4"
while read -r c s attendu_r; do
  r=0; SCAN_OUTIL=$OUT bash "$B/signer-vex.sh" verifier "$SV/$c.json" "$REG/builds/x/sample-app@$Y" "$SV/$s" > "$SV/$c.log" 2>&1 || r=$?
  attendu "signer-vex verifier : $c" "code $r : $(sed -n 's/^\(JUGE|[a-z]*, [0-9]* énoncé(s) dont [0-9]* large(s)\).*/\1/p; s/^REFUS|\([^:(0-9]*\).*/REFUS|\1/p' "$SV/$c.log" | head -1 | sed 's/ *$//')" "$attendu_r"
done <<'FIN'
retract-faute ../../mesure0/image-avant.scan.json code 1 : REFUS|énoncé dont aucun nom ne croise une entrée du prédicat de scan
retract-sans-action ../../mesure0/image-avant.scan.json code 1 : REFUS|affected sans action_statement
couple-faux scan-deux.json code 1 : REFUS|sous-composant sans entrée de cette vulnérabilité dans le prédicat de scan
couple-ok scan-deux.json code 0 : JUGE|exemption, 1 énoncé(s) dont 0 large(s)
FIN

# ------------------------------------------------------------------------------------------------------------------------------ B
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=zot-jetable -addext subjectAltName=IP:127.0.0.1 \
  -addext basicConstraints=critical,CA:TRUE -keyout "$T/cle/zot.key" -out "$T/zot.crt" 2> /dev/null
jq -n --arg r "$T/zot" --arg c "$T/zot.crt" --arg k "$T/cle/zot.key" '{distSpecVersion: "1.1.1", storage: {rootDirectory: $r, gc: false},
  http: {address: "127.0.0.1", port: "15002", tls: {cert: $c, key: $k}}, log: {level: "error"}}' > "$T/zot.json"
OUT=$OUT unshare -rn bash "$0" ns
KO=$((KO + $(cat "$T/ko-ns" 2>/dev/null || echo 1)))

# ------------------------------------------------------------------------------------------------------------------------------ C
echo "## C. porte : ec validate input de l'hôte, règles du patch"
P=$T/porte; mkdir -p "$P/regles"; cp "$B/politique/porte/scan.rego" "$P/regles/"
# passage 6 : le patch porte 30 (choix du propriétaire du 21/11) ; null est fabriqué par le sed inverse, comme contre-épreuve
sed "s#/etc/porte/regles-scan#$P/regles#" "$B/politique/porte/policy-scan.yaml" > "$P/politique-30.yaml"
sed "s#vex_age_max_jours: 30#vex_age_max_jours: null#" "$P/politique-30.yaml" > "$P/politique-null.yaml"
grep -q '^ *vex_age_max_jours: 30$' "$P/politique-30.yaml" && ok "politique du patch telle quelle : vex_age_max_jours 30 (choix du propriétaire)" || ko "politique du patch : 30 absent"
grep -q '^ *vex_age_max_jours: null$' "$P/politique-null.yaml" && ok "politique fabriquée : vex_age_max_jours null (sed inverse)" || ko "politique fabriquée : null absent"
juger_porte() { # libellé cas politique code-attendu règles-attendues [vulnérabilité passée en KEV, défaut $VULN]
  local c=0 v
  [ -s "$T/cas/$2/scan.json" ] || { ko "$1 : aucun prédicat"; return; }
  # base datée du scan : la base de G0 (04/11) serait refusée par base_recente, hors sujet ici ; entrées écartées passées en KEV
  jq -c --arg d "${Y#sha256:}" --arg t "$SCAN" '{digest: $d, statements: [{_type: "https://in-toto.io/Statement/v0.1",
    subject: [{name: "sample-app", digest: {sha256: $d}}], predicateType: $t,
    predicate: (.scanner.db.built = .scannedAt | .vulnerabilities |= map(if .id == "'"${6:-$VULN}"'" then .kev = true else . end))}]}' \
    "$T/cas/$2/scan.json" > "$P/entree-$2.json"
  ec validate input "$P/entree-$2.json" --policy "$P/politique-$3.yaml" --info --output json > "$P/ec-$2-$3.json" 2> "$P/ec.err" || c=$?
  v=$(jq -r '[.filepaths[].violations[]?.metadata.code] | unique | join(",")' "$P/ec-$2-$3.json" 2>/dev/null || echo "sans verdict")
  [ "$c" = "$4" ] && [ "$v" = "$5" ] && ok "$1 : code $c, ${v:-admis}" || ko "$1 : code $c, violations ${v:-aucune} (prédit : code $4, ${5:-aucune}) ; $(tail -1 "$P/ec.err" | cut -c1-200)"
}
juger_porte "porte, image complet, validité 30 j" complet 30 0 ""
juger_porte "porte, VEX daté du futur" futur 30 1 scan.kev_without_vex
juger_porte "porte, autre sujet adverse (sans VEX)" adverse 30 1 scan.kev_without_vex
juger_porte "porte, politique fabriquée à null (sed inverse)" complet null 1 scan.kev_without_vex
juger_porte "porte, renouv avant retrait (01/10 remplacé par la veille, passage 7)" renouv-avant 30 0 ""
juger_porte "porte, renouv après retrait de l'ancien" renouv-apres 30 0 ""
juger_porte "porte, renouv sans référent (contre-épreuve)" renouv-vide 30 1 scan.kev_without_vex
juger_porte "porte, inverse" inverse 30 0 ""
juger_porte "porte, retract-avant" retract-avant 30 0 ""
juger_porte "porte, retract-apres (affected sous l'alias)" retract-apres 30 1 scan.kev_without_vex
juger_porte "porte, partiel, V1 en KEV" partiel 30 0 ""
juger_porte "porte, partiel, V2 en KEV" partiel 30 1 scan.kev_without_vex GHSA-j6qf-3m9c-vwj3

echo "## D. entrees-scan.py du patch, sur les prédicats de B"
# passage 13 : séries scan_vex_* (bloc vex du prédicat, 0 s'il est absent) ; signe-retract et un prédicat d'avant la tranche 3
cp "$M0/image-avant.scan.json" "$T/avant-t3.json"
for c in complet deb-complet signe-retract avant-t3; do
  p=$T/cas/$c/scan.json; [ "$c" = avant-t3 ] && p=$T/avant-t3.json
  [ -s "$p" ] || { ko "D $c : aucun prédicat"; continue; }
  r=$(python3 -I - "$B/systemd/entrees-scan.py" "$p" <<'PYD'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("es", sys.argv[1])
es = importlib.util.module_from_spec(spec)
spec.loader.exec_module(es)
p = json.load(open(sys.argv[2], encoding="utf-8"))
c = es.comptes("builds/x", p)
t = sum(int(l.rsplit(" ", 1)[1]) for l in c.splitlines() if l.startswith("scan_entrees{"))
v = sum(int(l.rsplit(" ", 1)[1]) for l in c.splitlines() if l.startswith("scan_entrees_vex{"))
k = [l.rsplit(" ", 1)[1] for l in c.splitlines() if l.startswith("scan_entrees_kev_vex{")]
e = [json.loads(x) for x in es.entrees("builds/x", p)]
x = {l.split('{')[0]: l.rsplit(' ', 1)[1] for l in c.splitlines() if l.startswith('scan_vex_')}
print(f"{len(c.splitlines())} séries, trouvées {t}, écartées {v}, kev écartées {','.join(k)}, lignes {len(e)}, lignes avec vex {sum(1 for x in e if x.get('vex'))}, "
      f"vex {x.get('scan_vex_documents')}/{x.get('scan_vex_rejetes')}/{x.get('scan_vex_ecartees_sans_exemption')}")
PYD
  )
  case $c in complet) a="21 séries, trouvées 5, écartées 1, kev écartées 0, lignes 5, lignes avec vex 1, vex 1/0/0" ;;
    deb-complet) a="21 séries, trouvées 66, écartées 1, kev écartées 0, lignes 66, lignes avec vex 1, vex 1/0/0" ;;
    signe-retract) a="21 séries, trouvées 5, écartées 0, kev écartées 0, lignes 5, lignes avec vex 0, vex 1/1/1" ;;
    *) a="21 séries, trouvées 5, écartées 0, kev écartées 0, lignes 5, lignes avec vex 0, vex 0/0/0" ;; esac
  attendu "D $c" "$r" "$a"
done

apres=$(empreinte)
[ "$avant" = "$apres" ] && ok "base de G0, source, image et deb inchangés ($avant)" || ko "entrées modifiées : $avant puis $apres"
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "## bilan : $KO écart(s) aux prédictions"
