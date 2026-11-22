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
#      Passage 15 : lignes de document VEX (documents_vex), et main() trois fois sur un faux Zot (lire remplacée) : A, A, B.
# Passage 16 : avis de renouvellement de signer-vex.sh (B, dépôt builds/avis ; seuil par défaut confronté à la politique en C).
# Passage 18 : repli sans --vex de scanner.sh (limite 4) : predicat en A ; en B, grype factice devant le vrai (panne injectée,
#   synthétique) ; porte en C ; série scan_vex_repli et comptes de entrees-scan.sh en D.
# Passage 19 : même grype factice, sans VEX retenu : l'échec reste un échec, sans relance.
# Passage 20 : exemptant daté du futur, forme asymétrique (A) : variante hors patch (resultats/07b-t3-variante-futur.patch, amende le
#   choix 3) appliquée à une copie de outil/ ; même table sur le binaire du patch et sur celui de la variante.
# Passage 21 : pièce 2, signer-vex.sh signer avec hashivault://vex dans un OpenBao 2.7.2 jetable (mode dev, B, espace de noms réseau
#   vide ; binaire extrait et vérifié par resultats/07b-p2-bao.sh) ; jeton du propriétaire simulé, émis par la racine du banc.
# Passage 22 : userpass du propriétaire (décision du 22/11), connexion -no-store, révocation, traces dans un audit file du banc.
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
    && COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix etrangere > /dev/null 2>&1 \
    && COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix scanner > /dev/null 2>&1)   # passage 14
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
    attendu "complet : repli absent du prédicat (passage 18)" "$(jq '.vex | has("repli")' "$T/cas/complet/scan.json")" false
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
  # passage 14 : signer-vex.sh verifier dans le Zot jetable ; scans témoins signés par une clé locale « scanner », en referrers
  echo "## B. signer-vex.sh verifier (pièce 8), scan signé lu et vérifié par le script"
  SV=$T/signer; mkdir -p "$SV"
  SV1="$JUSTIF;$IMPACT" EV="$VULN;pkg:oci/sample-app@$Y;$SYFT"
  publier_scan() { # clé prédicat dépôt-du-sujet dépôt-scan : attestation de scan signée, referrer comme publier de scanner.sh
    local w; w=$(mktemp -d "$T/tmp/scan.XXXX")
    COSIGN_PASSWORD='' cosign attest-blob --key "$T/cle/$1.key" --signing-config vide.json --predicate "$2" --type "$SCAN" \
      --bundle "$w/bundle.json" --hash "${Y#sha256:}" --yes sample-app > "$w/cosign.log" 2>&1 || { cat "$w/cosign.log"; return 1; }
    oras manifest fetch --ca-file zot.crt --descriptor "$REG/$3@$Y" > "$w/sujet.json"
    printf '{}' > "$w/config-vide.json"
    oras blob push --ca-file zot.crt "$REG/$4" "$w/config-vide.json" > /dev/null
    oras blob push --ca-file zot.crt "$REG/$4" "$w/bundle.json" > /dev/null
    local TY=application/vnd.dev.sigstore.bundle.v0.3+json
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s",%s,%s,%s,%s}' "$TY" \
      '"config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2}' \
      "\"layers\":[{\"mediaType\":\"$TY\",\"digest\":\"sha256:$(sha256sum < "$w/bundle.json" | cut -c1-64)\",\"size\":$(wc -c < "$w/bundle.json")}]" \
      "\"subject\":$(cat "$w/sujet.json")" \
      "\"annotations\":{\"dev.sigstore.bundle.content\":\"dsse-envelope\",\"dev.sigstore.bundle.predicateType\":\"$SCAN\"}" > "$w/manifeste.json"
    oras manifest push --ca-file zot.crt "$REG/$4@sha256:$(sha256sum < "$w/manifeste.json" | cut -c1-64)" "$w/manifeste.json" > /dev/null
  }
  nscan() { { curl -fsS --cacert zot.crt "https://$REG/v2/builds/scan/$1/sample-app/referrers/$Y" 2>/dev/null || echo '{}'; } | jq '.manifests // [] | length'; }
  jq '.vulnerabilities |= map(if .id == "GO-2026-5774" then .package = "pkg:golang/stdlib@1.24.4" else . end) | .scannedAt = "2026-11-01T00:00:00Z"' \
    "$M0/image-avant.scan.json" > "$SV/scan-deux.json"
  for d in signe deux etranger; do pousser "$M0/image" "builds/$d/sample-app" > /dev/null; done
  publier_scan scanner "$SV/scan-deux.json" builds/signe/sample-app builds/scan/signe/sample-app
  publier_scan scanner "$M0/image-avant.scan.json" builds/signe/sample-app builds/scan/signe/sample-app
  publier_scan scanner "$SV/scan-deux.json" builds/deux/sample-app builds/scan/deux/sample-app
  publier_scan etrangere "$M0/image-avant.scan.json" builds/etranger/sample-app builds/scan/etranger/sample-app
  attendu "scans témoins publiés (signe, deux, etranger)" "$(nscan signe),$(nscan deux),$(nscan etranger)" "2,1,1"
  HF=$(date -ud tomorrow +%FT%TZ); HV=$(date -ud '1 day ago' +%FT%TZ)
  action() { jq -c '.statements |= map(if .status == "affected" then . + {action_statement: "témoin du banc : aucune action"} else . end)' "$1" > "$1.t" && mv "$1.t" "$1"; }
  vex doc "$SV/ok.json" "$HV" "not_affected;$SV1;-;$EV"
  vex doc "$SV/futur.json" "$HF" "not_affected;$SV1;-;$EV"
  vex doc "$SV/futur-enonce.json" "$HV" "not_affected;$SV1;$HF;$EV"
  vex doc "$SV/retract.json" "$HV" "affected;-;-;-;CVE-2025-69725;pkg:oci/sample-app@$Y;$SYFT"; action "$SV/retract.json"
  vex doc "$SV/large.json" "$HV" "not_affected;$SV1;-;$VULN;pkg:oci/sample-app@$Y;-"
  vex doc "$SV/absent.json" "$HV" "not_affected;$SV1;-;$VULN;pkg:oci/sample-app@$Y;pkg:golang/github.com/go-chi/chi@v5.2.4#v5"
  vex doc "$SV/fixed.json" "$HV" "fixed;-;-;-;$EV"
  vex doc "$SV/mixte.json" "$HV" "not_affected;$SV1;-;$EV" "affected;-;-;-;GHSA-j6qf-3m9c-vwj3;pkg:oci/sample-app@$Y;$SYFT"
  vex doc "$SV/sans-impact.json" "$HV" "not_affected;$JUSTIF;-;-;$EV"
  vex doc "$SV/autre-digest.json" "$HV" "not_affected;$SV1;-;$VULN;pkg:oci/sample-app@$DEB;$SYFT"
  vex doc "$SV/sans-vuln.json" "$HV" "not_affected;$SV1;-;-;pkg:oci/sample-app@$Y;$SYFT"
  vex doc "$SV/sans-horo.json" - "not_affected;$SV1;-;$EV"
  vex doc "$SV/retract-faute.json" "$HV" "affected;-;-;-;CVE-2025-69752;pkg:oci/sample-app@$Y;$SYFT"; action "$SV/retract-faute.json"
  vex doc "$SV/retract-sans-action.json" "$HV" "affected;-;-;-;CVE-2025-69725;pkg:oci/sample-app@$Y;$SYFT"
  vex doc "$SV/couple-faux.json" "$HV" "not_affected;$SV1;-;GO-2026-5774;pkg:oci/sample-app@$Y;$SYFT"
  vex doc "$SV/couple-ok.json" "$HV" "not_affected;$SV1;-;GO-2026-5774;pkg:oci/sample-app@$Y;pkg:golang/stdlib@1.24.4"
  sv_verifier() { # document dépôt [référence] : code et motif de signer-vex.sh verifier
    local r=0
    env SCAN_OUTIL="$OUT" CA="$T/zot.crt" CLE_SCANNER="$T/cle/scanner.pub" CLE_PUBLIQUE="$T/cle/vex.pub" bash "$B/signer-vex.sh" verifier "$SV/$1.json" \
      "${3:-$REG/builds/$2/sample-app@$Y}" > "$SV/$1-$2.log" 2>&1 || r=$?
    echo "code $r : $(sed -n 's/^\(JUGE|[a-z]*, [0-9]* énoncé(s) dont [0-9]* large(s)\).*/\1/p; s/^REFUS|\([^:(0-9]*\).*/REFUS|\1/p' "$SV/$1-$2.log" | head -1 | sed 's/ *$//')"
  }
  while read -r c d attendu_r; do attendu "signer-vex verifier : $c ($d)" "$(sv_verifier "$c" "$d")" "$attendu_r"; done <<'FIN'
ok signe code 0 : JUGE|exemption, 1 énoncé(s) dont 0 large(s)
futur signe code 1 : REFUS|horodatage
futur-enonce signe code 1 : REFUS|horodatage
retract signe code 0 : JUGE|retractation, 1 énoncé(s) dont 0 large(s)
large signe code 0 : JUGE|exemption, 1 énoncé(s) dont 1 large(s)
absent signe code 1 : REFUS|sous-composant absent des entrées du prédicat de scan
fixed signe code 1 : REFUS|statut fixed
mixte signe code 1 : REFUS|not_affected mêlé à d'autres statuts
sans-impact signe code 1 : REFUS|rejeté par scan-outil vex
autre-digest signe code 1 : REFUS|énoncé sans produit dont l'@id cite le digest
sans-vuln signe code 1 : REFUS|énoncé sans nom de vulnérabilité
sans-horo signe code 1 : REFUS|énoncés non classables par scan-outil vex
retract-faute signe code 1 : REFUS|énoncé dont aucun nom ne croise une entrée du prédicat de scan
retract-sans-action signe code 1 : REFUS|affected sans action_statement
couple-faux deux code 1 : REFUS|sous-composant sans entrée de cette vulnérabilité dans le prédicat de scan
couple-ok deux code 0 : JUGE|exemption, 1 énoncé(s) dont 0 large(s)
couple-ok signe code 1 : REFUS|sous-composant absent des entrées du prédicat de scan
ok etranger code 1 : REFUS|aucun scan signé vérifié
FIN
  attendu "signer-vex verifier : image sans digest" "$(sv_verifier ok sans-digest "$REG/builds/signe/sample-app:t3" | cut -d' ' -f1,2)" "code 2"
  # passage 16 : ligne PUBLIES| (énoncés publiés vérifiés par CLE_PUBLIQUE) et lignes AVIS| (type seul)
  resume_avis() { echo "publiés $(sed -n 's/^PUBLIES|\([0-9]*\) .*/\1/p' "$1") ; avis $(sed -n 's/^AVIS|\([^ ]*\) :.*/\1/p' "$1" | sort -u | paste -sd, - | grep . || echo aucun)"; }
  attendu "signer-vex verifier : énoncés publiés lus (ok, retract, large sur signe ; couple-ok sur deux)" \
    "$(for x in ok-signe retract-signe large-signe couple-ok-deux; do sed -n 's/^PUBLIES|\([0-9]*\) .*/\1/p' "$SV/$x.log"; done | paste -sd, -)" "0,0,0,2"
  # 18-21 (passage 11) : pièce 8, signer-vex.sh signer avec la clé locale vex (pas hashivault://vex) ; scan signé de builds/scan/signe (passage 14)
  echo "## B. signer-vex.sh signer (pièce 8), clé locale"
  pousser "$M0/image" builds/signe/sample-app > /dev/null
  referents_signe() { { curl -fsS --cacert zot.crt "https://$REG/v2/builds/vex/signe/sample-app/referrers/$Y" 2>/dev/null || echo '{}'; } | jq '.manifests // [] | length'; }
  signer_vex() { # clé document cas : code de signer-vex.sh signer et référents après
    local c=0
    env COSIGN_PASSWORD='' SCAN_OUTIL="$OUT" CLE="$T/cle/$1.key" CLE_PUBLIQUE="$T/cle/vex.pub" CA="$T/zot.crt" CONFIG_REGISTRE="$T/docker/config.json" \
      CLE_SCANNER="$T/cle/scanner.pub" bash "$B/signer-vex.sh" signer "$2" "$REG/builds/signe/sample-app@$Y" > "$T/signer-$3.log" 2>&1 || c=$?
    echo "code $c ; référents $(referents_signe)"
  }
  vex doc "$T/v-signe-futur.json" "$(date -ud tomorrow +%FT%TZ)" "not_affected;$JUSTIF;$IMPACT;-;$VULN;pkg:oci/sample-app@$Y;$SYFT"
  attendu "signer, daté du futur : refus avant signature" "$(signer_vex vex "$T/v-signe-futur.json" futur)" "code 1 ; référents 0"
  attendu "signer, daté du futur : motif" "$(grep -c '^REFUS|horodatage' "$T/signer-futur.log")" 1
  ok_vex "$T/v-signe-ok.json"
  attendu "signer, clé étrangère : refus avant publication" "$(signer_vex etrangere "$T/v-signe-ok.json" etrangere)" "code 1 ; référents 0"
  attendu "signer, clé étrangère : motif" "$(grep -c '^REFUS|signature non vérifiée' "$T/signer-etrangere.log")" 1
  attendu "signer, clé vex : publié" "$(signer_vex vex "$T/v-signe-ok.json" ok)" "code 0 ; référents 1"
  attendu "signer, clé vex : énoncés publiés lus et avis (passage 16)" "$(resume_avis "$T/signer-ok.log")" "publiés 0 ; avis aucun"
  grep -E '^(JUGE|SIGNE|PUBLIE)\|' "$T/signer-ok.log" | cut -c1-200 | sed "s|$T|<banc>|g; s/^/     /" || true
  vex_seul signe-ok builds/signe/sample-app "$Y"; juger_vex signe-ok 1,1,0 4/1
  [ -s "$T/cas/signe-ok/scan.json" ] && attendu "signe-ok : entrée écartée" "$(horo signe-ok)" "$VULN $H1"
  [ -s "$T/cas/signe-ok/scan.json" ] && attendu "signe-ok : documents du prédicat = énoncé signé annoncé par SIGNE" \
    "$(jq -r '[.vex.documents[].sha256] | join(",")' "$T/cas/signe-ok/scan.json")" "$(sed -n 's/^SIGNE|.*énoncé signé sha256 \([0-9a-f]*\).*/\1/p' "$T/signer-ok.log")"
  vex doc "$T/v-signe-retract.json" "$(date -u +%FT%TZ)" "affected;-;-;-;CVE-2025-69725;pkg:oci/sample-app@$Y;$SYFT"
  jq -c '.statements |= map(. + {action_statement: "témoin du banc : aucune action"})' "$T/v-signe-retract.json" > "$T/v-signe-retract.t" && mv "$T/v-signe-retract.t" "$T/v-signe-retract.json"   # passage 12
  attendu "signer, rétractation : publiée" "$(signer_vex vex "$T/v-signe-retract.json" retract)" "code 0 ; référents 2"
  attendu "signer, rétractation : énoncés publiés lus et avis (passage 16)" "$(resume_avis "$T/signer-retract.log")" "publiés 1 ; avis aucun"
  vex_seul signe-retract builds/signe/sample-app "$Y"; juger_vex signe-retract 2,1,1 5/0
  [ -s "$T/cas/signe-retract/scan.json" ] && attendu "signe-retract : écartées sans exemption" "$(jq -r .vex.ecarteesSansExemption "$T/cas/signe-retract/scan.json")" 1
  # passage 16 : avis de renouvellement (limite 3) ; builds/avis : scan signé, P1 (clé vex, 10 jours, .5 s), P2 (clé étrangère, 1 h),
  # P3 (clé vex, non recevable : sans impact_statement, 5 jours)
  echo "## B. signer-vex.sh, avis de renouvellement (passage 16)"
  pousser "$M0/image" builds/avis/sample-app > /dev/null
  publier_scan scanner "$M0/image-avant.scan.json" builds/avis/sample-app builds/scan/avis/sample-app
  HA=$(date -ud '10 days ago' +%FT%T) EM="pkg:oci/sample-app@$Y;$SYFT"
  vex doc "$T/v-avis-p1.json" "$HA.500000000Z" "not_affected;$SV1;-;$EV"
  vex doc "$T/v-avis-p2.json" "$(date -ud '1 hour ago' +%FT%TZ)" "not_affected;$SV1;-;$EV"
  vex doc "$T/v-avis-p3.json" "$(date -ud '5 days ago' +%FT%TZ)" "not_affected;$JUSTIF;-;-;GHSA-j6qf-3m9c-vwj3;$EM"
  publier_vex vex "$T/v-avis-p1.json" "$Y" builds/avis/sample-app "$Y" builds/vex/avis/sample-app
  publier_vex etrangere "$T/v-avis-p2.json" "$Y" builds/avis/sample-app "$Y" builds/vex/avis/sample-app
  publier_vex vex "$T/v-avis-p3.json" "$Y" builds/avis/sample-app "$Y" builds/vex/avis/sample-app
  nvex() { { curl -fsS --cacert zot.crt "https://$REG/v2/builds/vex/$1/sample-app/referrers/$Y" 2>/dev/null || echo '{}'; } | jq '.manifests // [] | length'; }
  attendu "builds/avis : scans et référents VEX" "$(nscan avis),$(nvex avis)" "1,3"
  vex doc "$SV/avis-recent.json" "$(date -ud '1 day ago' +%FT%TZ)" "not_affected;$SV1;-;$EV"
  vex doc "$SV/avis-egal.json" "$HA.500000000Z" "not_affected;$SV1;-;$EV"
  vex doc "$SV/avis-ancien.json" "${HA}Z" "not_affected;$SV1;-;$EV"
  vex doc "$SV/avis-fraction.json" "$HA.700000000Z" "not_affected;$SV1;-;$EV"
  vex doc "$SV/avis-alias.json" "$(date -ud '11 days ago' +%FT%TZ)" "not_affected;$SV1;-;CVE-2025-69725;$EM"
  vex doc "$SV/avis-retract-ancienne.json" "$(date -ud '11 days ago' +%FT%TZ)" "affected;-;-;-;$EV"; action "$SV/avis-retract-ancienne.json"
  vex doc "$SV/avis-retract-recente.json" "$(date -ud '1 day ago' +%FT%TZ)" "affected;-;-;-;$EV"; action "$SV/avis-retract-recente.json"
  vex doc "$SV/avis-non-recevable.json" "$(date -ud '6 days ago' +%FT%TZ)" "not_affected;$SV1;-;GHSA-j6qf-3m9c-vwj3;$EM"
  vex doc "$SV/avis-vieux-31.json" "$(date -ud '31 days ago' +%FT%TZ)" "not_affected;$SV1;-;GO-2026-5775;$EM"
  vex doc "$SV/avis-vieux-29.json" "$(date -ud '708 hours ago' +%FT%TZ)" "not_affected;$SV1;-;GO-2026-5777;$EM"
  vex doc "$SV/avis-vieux-28.json" "$(date -ud '28 days ago' +%FT%TZ)" "not_affected;$SV1;-;GO-2026-5774;$EM"
  sv_avis() { # cas : code, énoncés publiés et avis de signer-vex.sh verifier sur builds/avis
    local r=0
    env SCAN_OUTIL="$OUT" CA="$T/zot.crt" CLE_SCANNER="$T/cle/scanner.pub" CLE_PUBLIQUE="$T/cle/vex.pub" bash "$B/signer-vex.sh" verifier "$SV/avis-$1.json" \
      "$REG/builds/avis/sample-app@$Y" > "$SV/avis-$1.log" 2>&1 || r=$?
    echo "code $r ; $(resume_avis "$SV/avis-$1.log")"
  }
  while read -r c attendu_r; do attendu "signer-vex verifier, avis : $c" "$(sv_avis "$c")" "$attendu_r"; done <<'FIN'
recent code 0 ; publiés 2 ; avis aucun
egal code 0 ; publiés 2 ; avis renouvellement
ancien code 0 ; publiés 2 ; avis renouvellement
fraction code 0 ; publiés 2 ; avis aucun
alias code 0 ; publiés 2 ; avis renouvellement
retract-ancienne code 0 ; publiés 2 ; avis rétractation
retract-recente code 0 ; publiés 2 ; avis aucun
non-recevable code 0 ; publiés 2 ; avis renouvellement
vieux-31 code 0 ; publiés 2 ; avis âge
vieux-29 code 0 ; publiés 2 ; avis âge
vieux-28 code 0 ; publiés 2 ; avis aucun
FIN
  grep -hE '^(PUBLIES|AVIS|ECHEANCE)\|' "$SV/avis-ancien.log" "$SV/avis-retract-ancienne.log" "$SV/avis-vieux-29.log" | cut -c1-240 | sed "s|$T|<banc>|g; s/^/     /" || true
  # passage 17 : la rétractation ancienne en mode signer (après les cas verifier) : avis, publication, puis l'exemption de P1 tient
  c=0
  env COSIGN_PASSWORD='' SCAN_OUTIL="$OUT" CLE="$T/cle/vex.key" CLE_PUBLIQUE="$T/cle/vex.pub" CA="$T/zot.crt" CONFIG_REGISTRE="$T/docker/config.json" \
    CLE_SCANNER="$T/cle/scanner.pub" bash "$B/signer-vex.sh" signer "$SV/avis-retract-ancienne.json" "$REG/builds/avis/sample-app@$Y" > "$T/signer-avis-retract.log" 2>&1 || c=$?
  attendu "signer, rétractation ancienne (passage 17)" "code $c ; référents $(nvex avis) ; $(resume_avis "$T/signer-avis-retract.log")" "code 0 ; référents 4 ; publiés 2 ; avis rétractation"
  attendu "signer, rétractation ancienne : lignes PUBLIE" "$(grep -c '^PUBLIE|' "$T/signer-avis-retract.log")" 1
  vex_seul avis-apres builds/avis/sample-app "$Y"; juger_vex avis-apres 3,1,2 4/1
  [ -s "$T/cas/avis-apres/scan.json" ] && attendu "avis-apres : entrée écartée" "$(horo avis-apres)" "$VULN $HA.5Z"
  # passage 18 : repli sans --vex (limite 4). Panne injectée, donc synthétique : grype factice devant le vrai dans le PATH du cas ;
  # il note chaque appel (sous-commande, nombre de --vex), puis échoue (PANNE=vex : sbom: avec --vex ; tout : tout sbom:) ou passe la main
  echo "## B. scanner.sh analyser, repli sans --vex (passage 18, panne injectée)"
  mkdir -p "$T/faux"
  cat > "$T/faux/grype" <<'FAUX'
#!/bin/sh
n=0 s=autre
for a in "$@"; do
  case $a in --vex) n=$((n + 1)) ;; sbom:*) s=sbom ;; db) [ "$s" = sbom ] || s=db ;; esac
done
echo "$s $n" >> "$APPELS"
case $PANNE:$s:$n in
  vex:sbom:0) ;;
  vex:sbom:*) echo "panne injectée par le banc : --vex refusé" >&2; exit 1 ;;
  tout:sbom:*) echo "panne injectée par le banc : scan refusé" >&2; exit 1 ;;
esac
exec "$GRYPE_VRAI" "$@"
FAUX
  chmod +x "$T/faux/grype"
  GV=$(command -v grype)
  pousser "$M0/image" builds/repli/sample-app > /dev/null
  ok_vex "$T/v-repli.json"; publier_vex vex "$T/v-repli.json" "$Y" builds/repli/sample-app "$Y" builds/vex/repli/sample-app
  appels() { paste -sd, - < "$T/faux/appels-$1" 2>/dev/null || echo aucun; }
  for c in repli panne-totale; do
    mkdir -p "$T/cas/$c"; cp -r "$G0/source" "$T/cas/$c/source"
    p=vex; [ "$c" = repli ] || p=tout
    scanner analyser "$c" IMAGE="$REG/builds/repli/sample-app@$Y" BASES="$REG/vulndb/grype" PATH="$T/faux:$T/outil:$PATH" \
      GRYPE_VRAI="$GV" PANNE="$p" APPELS="$T/faux/appels-$c"
    { grep -E '^(VEX|REJET|REPLI|SCAN|PREDICAT)\|' "$T/cas/$c.journal" || true; } | cut -c1-260 | sed "s|$T|<banc>|g; s/^/     /"
    attendu "$c : appels de grype (sous-commande, nombre de --vex)" "$(appels "$c")" "db 0,sbom 1,sbom 0"
  done
  attendu "repli : ligne REPLI" "$(grep -c '^REPLI|' "$T/cas/repli.journal") ; $(sed -n 's/^REPLI|\(grype code [0-9]* avec [0-9]* VEX\).*/\1/p' "$T/cas/repli.journal")" \
    "1 ; grype code 1 avec 1 VEX"
  juger_vex repli 1,1,0 5/0
  if [ -s "$T/cas/repli/scan.json" ]; then
    attendu "repli : bloc vex du prédicat" "$(jq -cS .vex "$T/cas/repli/scan.json")" '{"documents":[],"ecarteesSansExemption":0,"rejetes":0,"repli":1}'
    [ "$(jq -S '.vulnerabilities | map(del(.vex))' "$T/cas/repli/scan.json")" = "$(jq -S '.vulnerabilities | map(del(.vex))' "$T/cas/complet/scan.json")" ] \
      && ok "repli : entrées = celles de complet sans le champ vex" || ko "repli : entrées différentes de celles de complet"
  fi
  attendu "panne-totale : lignes REPLI" "$(grep -c '^REPLI|' "$T/cas/panne-totale.journal")" 1
  attendu "panne-totale : code final" "$(tail -1 "$T/cas/panne-totale.journal")" "code 1"
  attendu "panne-totale : prédicat" "$([ -e "$T/cas/panne-totale/scan.json" ] && echo présent || echo absent)" absent
  # passage 19 : panne totale sur un dépôt sans VEX publié : aucune relance, l'échec reste un échec
  c=sans-vex-panne
  pousser "$M0/image" builds/sans-vex/sample-app > /dev/null
  mkdir -p "$T/cas/$c"; cp -r "$G0/source" "$T/cas/$c/source"
  scanner analyser "$c" IMAGE="$REG/builds/sans-vex/sample-app@$Y" BASES="$REG/vulndb/grype" PATH="$T/faux:$T/outil:$PATH" \
    GRYPE_VRAI="$GV" PANNE=tout APPELS="$T/faux/appels-$c"
  { grep -E '^(VEX|REJET|REPLI|SCAN|PREDICAT)\|' "$T/cas/$c.journal" || true; } | cut -c1-260 | sed "s|$T|<banc>|g; s/^/     /"
  attendu "$c : appels de grype (sous-commande, nombre de --vex)" "$(appels "$c")" "db 0,sbom 0"
  attendu "$c : VEX vérifiés, retenus, rejetés" "$(ligne_vex "$c")" "0,0,0"
  attendu "$c : lignes REPLI" "$(grep -c '^REPLI|' "$T/cas/$c.journal" || true)" 0
  attendu "$c : message du faux dans le journal" "$(grep -c 'panne injectée par le banc : scan refusé' "$T/cas/$c.journal" || true)" 1
  attendu "$c : code final" "$(tail -1 "$T/cas/$c.journal")" "code 1"
  attendu "$c : prédicat" "$([ -e "$T/cas/$c/scan.json" ] && echo présent || echo absent)" absent
  # passage 21 : pièce 2, clé Transit vex dans un OpenBao 2.7.2 jetable (mode dev, 127.0.0.1:18200 ; jeton racine écrit par le serveur
  # dans $T/bao-home, jamais passé en argument). Jeton du propriétaire simulé : émis par la racine du banc, politique vex-signature
  # seule, sans default, orphelin, 15 min (le mode réel est un choix du propriétaire). Image et scan signé dans un dépôt neuf.
  echo "## B. pièce 2 : signer-vex.sh signer avec hashivault://vex, OpenBao jetable (passage 21, synthétique)"
  mkdir -p "$T/bao-home"; (umask 077 && mkdir -p "$T/cle/bao")
  # passage 22 : device d'audit déclaré dans la configuration (OpenBao 2.7 refuse l'activation par l'API : premier passage du 22)
  printf 'audit "file" "banc" {\n  options {\n    file_path = "%s"\n  }\n}\n' "$T/bao-audit.log" > "$T/bao-audit.hcl"
  HOME=$T/bao-home "$BAO" server -dev -dev-listen-address=127.0.0.1:18200 -config="$T/bao-audit.hcl" > "$T/bao.out" 2>&1 & bp=$!
  # shellcheck disable=SC2064   # développement à la pose, voulu
  trap "kill $zp $bp 2>/dev/null || true" EXIT
  export VAULT_ADDR=http://127.0.0.1:18200
  rb() { HOME=$T/bao-home "$BAO" "$@"; }   # racine du banc : jeton lu par le client dans $T/bao-home
  for _ in $(seq 40); do rb status > /dev/null 2>&1 && break; sleep 0.25; done
  attendu "OpenBao jetable : version, scellé" "$(rb status -format=json | jq -r '"\(.version) \(.sealed)"')" "2.7.2 false"
  rb secrets enable transit > /dev/null
  attendu "audit déclaratif du banc (passage 22)" "$(rb audit list -format=json | jq -r 'to_entries[] | "\(.key) \(.value.type)"' | paste -sd, -)" "banc/ file"
  for k in vex scanner chains; do rb write -f "transit/keys/$k" type=ecdsa-p256 exportable=false allow_plaintext_backup=false > /dev/null; done
  rb policy write vex-signature "$B/politique/vex-signature.hcl" > /dev/null
  rb policy write scanner-signature "$B/politique/scanner-signature.hcl" > /dev/null
  attendu "clé vex (type, exportable, sauvegarde en clair, suppression)" \
    "$(rb read -format=json transit/keys/vex | jq -r '.data | [.type, .exportable, .allow_plaintext_backup, .deletion_allowed] | join(",")')" "ecdsa-p256,false,false,false"
  attendu "politique vex-signature relue = fichier (hors commentaires et lignes vides)" \
    "$(rb policy read vex-signature | grep -v -e '^#' -e '^$' | sha256sum | cut -c1-16)" "$(grep -v -e '^#' -e '^$' "$B/politique/vex-signature.hcl" | sha256sum | cut -c1-16)"
  rb read -format=json transit/keys/vex | jq -r '.data.keys | to_entries | max_by(.key | tonumber) | .value.public_key' > "$T/cle/vex-bao.pub"
  jeton_bao() { rb token create -policy="$1" -no-default-policy -orphan -ttl=15m -format=json > "$T/cle/bao/$1.json"
    jq -r .auth.client_token "$T/cle/bao/$1.json" > "$T/cle/bao/$1"; }
  jeton_bao vex-signature; jeton_bao scanner-signature
  attendu "jeton du propriétaire simulé : politiques, durée, renouvelable" \
    "$(jq -r '.auth | "\(.policies | join(",")) \(.lease_duration) \(.renewable)"' "$T/cle/bao/vex-signature.json")" "vex-signature 900 true"
  pousser "$M0/image" builds/bao/sample-app > /dev/null
  publier_scan scanner "$M0/image-avant.scan.json" builds/bao/sample-app builds/scan/bao/sample-app
  ok_vex "$T/v-bao-ok.json"
  signer_bao() { # jeton clé cas : code de signer-vex.sh signer, référents de builds/vex/bao après, motif du refus
    local c=0
    VAULT_TOKEN=$(cat "$T/cle/bao/$1") SCAN_OUTIL="$OUT" CLE="hashivault://$2" CLE_PUBLIQUE="$T/cle/vex-bao.pub" CA="$T/zot.crt" \
      CONFIG_REGISTRE="$T/docker/config.json" CLE_SCANNER="$T/cle/scanner.pub" bash "$B/signer-vex.sh" signer "$T/v-bao-ok.json" \
      "$REG/builds/bao/sample-app@$Y" > "$T/signer-bao-$3.log" 2>&1 || c=$?
    echo "code $c ; référents $(nvex bao) ; refus $(sed -n 's/^REFUS|\([^:]*\).*/\1/p' "$T/signer-bao-$3.log" | head -1 | sed 's/ *$//' | grep . || echo aucun)"
  }
  attendu "signer, jeton vex, clé hashivault://scanner" "$(signer_bao vex-signature scanner vex-scanner)" "code 1 ; référents 0 ; refus signature en échec"
  attendu "signer, jeton vex, clé hashivault://chains" "$(signer_bao vex-signature chains vex-chains)" "code 1 ; référents 0 ; refus signature en échec"
  attendu "signer, jeton scanner, clé hashivault://vex" "$(signer_bao scanner-signature vex scanner-vex)" "code 1 ; référents 0 ; refus signature en échec"
  attendu "signer, jeton vex, clé hashivault://vex" "$(signer_bao vex-signature vex ok)" "code 0 ; référents 1 ; refus aucun"
  grep -E '^(JUGE|SIGNE|PUBLIE)\|' "$T/signer-bao-ok.log" | cut -c1-200 | sed "s|$T|<banc>|g; s/^/     /" || true
  { grep -h -i 'error\|denied' "$T/signer-bao-vex-scanner.log" || true; } | sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' | head -2 | cut -c1-200 | sed "s|$T|<banc>|g; s/^/     refus vex-scanner : /"
  scanner vex bao-lu IMAGE="$REG/builds/bao/sample-app@$Y" CLE_VEX="$T/cle/vex-bao.pub"
  attendu "bao-lu (clé publique tirée de Transit) : VEX vérifiés, retenus, rejetés" "$(ligne_vex bao-lu)" "1,1,0"
  scanner vex bao-cle-locale IMAGE="$REG/builds/bao/sample-app@$Y"
  attendu "bao-cle-locale (vex.pub du banc) : VEX vérifiés, retenus, rejetés" "$(ligne_vex bao-cle-locale)" "0,0,0"
  refuse_bao() { # libellé commande… : avec le jeton vex-signature, code et nombre de lignes « permission denied »
    local c=0
    VAULT_TOKEN=$(cat "$T/cle/bao/vex-signature") HOME=$T/tmp "$BAO" "${@:2}" > /dev/null 2> "$T/tmp/bao.err" || c=$?
    attendu "jeton vex-signature : $1" "code $c ; $(grep -c 'permission denied' "$T/tmp/bao.err" || true)" "code 2 ; 1"
  }
  refuse_bao "création d'une clé" write -f transit/keys/autre
  refuse_bao "export de la clé vex" read transit/export/signing-key/vex
  refuse_bao "suppression autorisée sur vex" write transit/keys/vex/config deletion_allowed=true
  refuse_bao "écriture d'une politique" policy write autre "$B/politique/vex-signature.hcl"
  refuse_bao "lecture de la clé scanner" read transit/keys/scanner
  refuse_bao "émission d'un jeton" token create -policy=vex-signature
  # passage 22 : identité du propriétaire par userpass (décision du 22/11) ; mot de passe aléatoire du banc dans un fichier 0600, lu
  # par bao (password=@fichier), jamais en argument ; jeton de connexion non écrit (-no-store) ; audit du banc lu en comptes
  echo "## B. pièce 2 : userpass du propriétaire, révocation, traces d'audit (passage 22, synthétique)"
  (umask 077 && head -c 24 /dev/urandom | base64 > "$T/cle/bao/mdp" && printf 'faux-mot-de-passe' > "$T/cle/bao/faux")
  rb auth enable userpass > /dev/null
  rb write auth/userpass/users/proprietaire password=@"$T/cle/bao/mdp" token_policies=vex-signature token_no_default_policy=true \
    token_ttl=15m token_max_ttl=15m > /dev/null
  attendu "userpass : politiques, sans default, durée" \
    "$(rb read -format=json auth/userpass/users/proprietaire | jq -r '.data | "\(.token_policies | join(",")) \(.token_no_default_policy) \(.token_ttl)"')" "vex-signature true 900"
  mkdir -p "$T/proprio"
  c=0; HOME=$T/proprio "$BAO" login -method=userpass -no-store -format=json username=proprietaire password=@"$T/cle/bao/mdp" \
    > "$T/cle/bao/login.json" 2> "$T/tmp/bao.err" || c=$?
  (umask 077 && jq -r '.auth.client_token // empty' "$T/cle/bao/login.json" > "$T/cle/bao/proprietaire" 2> /dev/null || true)
  attendu "login userpass -no-store : code, jeton écrit dans le HOME de la connexion" \
    "code $c ; $([ -e "$T/proprio/.vault-token" ] && echo écrit || echo absent)" "code 0 ; absent"
  attendu "jeton du propriétaire : politiques, utilisateur, durée" \
    "$(jq -r '.auth | "\(.policies | join(",")) \(.metadata.username) \(.lease_duration)"' "$T/cle/bao/login.json" 2> /dev/null)" "vex-signature proprietaire 900"
  pousser "$M0/image" builds/up/sample-app > /dev/null
  publier_scan scanner "$M0/image-avant.scan.json" builds/up/sample-app builds/scan/up/sample-app
  signer_up() { # jeton cas : code de signer-vex.sh signer (clé hashivault://vex), référents de builds/vex/up après, motif du refus
    local c=0
    VAULT_TOKEN=$(cat "$T/cle/bao/$1") SCAN_OUTIL="$OUT" CLE=hashivault://vex CLE_PUBLIQUE="$T/cle/vex-bao.pub" CA="$T/zot.crt" \
      CONFIG_REGISTRE="$T/docker/config.json" CLE_SCANNER="$T/cle/scanner.pub" bash "$B/signer-vex.sh" signer "$T/v-bao-ok.json" \
      "$REG/builds/up/sample-app@$Y" > "$T/signer-up-$2.log" 2>&1 || c=$?
    echo "code $c ; référents $(nvex up) ; refus $(sed -n 's/^REFUS|\([^:]*\).*/\1/p' "$T/signer-up-$2.log" | head -1 | sed 's/ *$//' | grep . || echo aucun)"
  }
  attendu "signer, jeton userpass, clé hashivault://vex" "$(signer_up proprietaire ok)" "code 0 ; référents 1 ; refus aucun"
  c=0; VAULT_TOKEN=$(cat "$T/cle/bao/proprietaire") HOME=$T/tmp "$BAO" token revoke -self > /dev/null 2> "$T/tmp/bao.err" || c=$?
  attendu "révocation par le propriétaire (token revoke -self)" "code $c" "code 0"
  attendu "signer après révocation" "$(signer_up proprietaire revoque)" "code 1 ; référents 1 ; refus signature en échec"
  c=0; HOME=$T/proprio "$BAO" login -method=userpass -no-store username=proprietaire password=@"$T/cle/bao/faux" > /dev/null 2> "$T/tmp/bao.err" || c=$?
  attendu "login, mauvais mot de passe" "code $c ; $(grep -c -i 'invalid username or password' "$T/tmp/bao.err" || true)" "code 2 ; 1"
  rb write auth/userpass/users/proprietaire/password password=@"$T/cle/bao/faux" > /dev/null   # contournement par la racine
  compte_audit() { # filtre jq sur les réponses : « nom affiché nombre », triés, séparés par des virgules
    jq -r "select(.type == \"response\") | select($1) | .auth.display_name" "$T/bao-audit.log" | sort | uniq -c | awk '{print $2 " " $1}' | paste -sd, -
  }
  attendu "audit : changement du mot de passe du propriétaire par la racine (contournement)" \
    "$(compte_audit '.request.path == "auth/userpass/users/proprietaire/password"')" "root 1"
  attendu "audit : signatures réussies sur transit/sign/vex, par identité" \
    "$(compte_audit '(.request.path | startswith("transit/sign/vex")) and ((.error // "") == "")')" "token 1,userpass-proprietaire 1"
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
for f in outil/main.go outil/go.mod politique/scanner.sh politique/porte/scan.rego politique/porte/scan_test.rego politique/porte/policy-scan.yaml plateforme.sh entrees-scan.sh systemd/entrees-scan.py politique/scanner-signature.hcl; do
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
  echo "$c $a $b" >> "$U/table-remplacement"
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
# passage 20 : exemptant daté du futur, forme asymétrique. Variante hors patch (amende le choix 3) : limite = heure du scan + 5 min ;
# un énoncé exemptant postérieur sort du classement, un non exemptant reste. Même table sur les deux binaires.
mkdir -p "$T/variante"; cp -r "$B/outil" "$T/variante/"
(cd "$T/variante" && patch -p1 --quiet < "$R/07b-t3-variante-futur.patch") && ok "variante : diff appliqué à une copie de outil/ du patch" \
  || ko "variante : diff non applicable"
OUTV=$T/variante/scan-outil
(cd "$T/variante/outil" && CGO_ENABLED=0 GOFLAGS=-mod=mod GOCACHE=$T/tmp/gocache go build -trimpath -buildvcs=false -o "$OUTV" .) \
  && ok "variante : scan-outil construit" || ko "variante : construction"
(cd "$T/variante/outil" && GOCACHE=$T/tmp/gocache go vet .) && ok "variante : go vet" || ko "variante : go vet"
"$OUTV" predicat "$M0/image-avant.grype.json" base-g0 "$T/vide.json" > "$T/compat-image-variante.json"
[ "$(jq -S . "$T/compat-image-variante.json")" = "$(jq -S . "$T/compat-image.json")" ] \
  && ok "variante : compatibilité image, prédicat égal à celui du binaire du patch" || ko "variante : compatibilité image, différences"
echo "     heure du scan témoin (ecarte-sans-doc.json) : $(jq -r .descriptor.timestamp "$T/ecarte-sans-doc.json")"
resume() { jq -r --arg v "$VULN" '([.vulnerabilities[] | select(.id == $v) | .vex // empty] | if length == 1 then "vex \(.[0].status) \(.[0].timestamp)" else "aucune" end) + " ; sans exemption \(.vex.ecarteesSansExemption)"' "$1" 2>/dev/null; }
juger_rempl() { # binaire cas documents (séparés par des virgules) : résumé de l'entrée VULN, ou code de sortie
  local o=$1 c=$2 l=$3 x c2=0
  set --; for x in ${l//,/ }; do set -- "$@" "$U/$x.json"; done
  rm -f "$U"/sortie/*
  "$o" vex "${Y#sha256:}" "$U/sortie" "$@" > "$U/q-$c.res" < /dev/null
  "$o" predicat "$T/ecarte-sans-doc.json" base-g0 "$U/q-$c.res" > "$U/q-$c.scan" 2> "$T/tmp/err" < /dev/null || c2=$?
  if [ -s "$U/q-$c.scan" ]; then resume "$U/q-$c.scan"; else echo "code $c2"; fi
}
while read -r c a b; do
  l=$a; [ "$b" = - ] || l=$a,$b
  attendu "variante, table du remplacement : $c" "$(juger_rempl "$OUTV" "t-$c" "$l")" "$(resume "$U/p-$c.scan")"
done < "$U/table-remplacement"
unite pf "$Y" "$OPENVEX" 2027-01-01T00:00:00Z "not_affected;$S1;-;$E"
unite prf "$Y" "$OPENVEX" 2027-01-01T00:00:00Z "affected;-;-;-;$E"
unite pnf-autre-produit "$Y" "$OPENVEX" 2027-01-01T00:00:00Z "not_affected;$S1;-;$VULN;pkg:oci/autre@sha256:$(printf '1%.0s' $(seq 64));$SYFT"
unite p4 "$Y" "$OPENVEX" 2026-11-21T17:27:25Z "not_affected;$S1;-;$E"
unite p6 "$Y" "$OPENVEX" 2026-11-21T17:29:25Z "not_affected;$S1;-;$E"
while IFS='|' read -r cl auj var; do
  read -r c l <<< "$cl"
  attendu "futur, binaire du patch : $c" "$(juger_rempl "$OUT" "a-$c" "$l")" "$auj"
  attendu "futur, variante : $c" "$(juger_rempl "$OUTV" "v-$c" "$l")" "$var"
done <<'FIN'
futur-seul pf|vex not_affected 2027-01-01T00:00:00Z ; sans exemption 0|aucune ; sans exemption 1
futur-et-ancien pa,pf|vex not_affected 2027-01-01T00:00:00Z ; sans exemption 0|vex not_affected 2026-11-01T00:00:00Z ; sans exemption 0
retractation-future pa,prf|aucune ; sans exemption 1|aucune ; sans exemption 1
futur-egalite pf,prf|aucune ; sans exemption 1|aucune ; sans exemption 1
retractation-puis-futur pa,pr,pf|vex not_affected 2027-01-01T00:00:00Z ; sans exemption 0|aucune ; sans exemption 1
futur-autre-produit pa,pnf-autre-produit|aucune ; sans exemption 1|aucune ; sans exemption 1
bord-4-min pa,p4|vex not_affected 2026-11-21T17:27:25Z ; sans exemption 0|vex not_affected 2026-11-21T17:27:25Z ; sans exemption 0
bord-6-min pa,p6|vex not_affected 2026-11-21T17:29:25Z ; sans exemption 0|vex not_affected 2026-11-01T00:00:00Z ; sans exemption 0
FIN
jq '.descriptor.timestamp = "x"' "$T/ecarte-sans-doc.json" > "$T/heure-illisible.json"
c=0; "$OUT" predicat "$T/heure-illisible.json" base-g0 "$U/p-remplacement.res" > /dev/null 2> "$T/tmp/err" || c=$?
attendu "heure du scan illisible, binaire du patch" "code $c" "code 0"
c=0; "$OUTV" predicat "$T/heure-illisible.json" base-g0 "$U/p-remplacement.res" > /dev/null 2> "$T/tmp/err" || c=$?
attendu "heure du scan illisible, variante" "code $c" "code 1"
# passage 18 : predicat en repli (limite 4) : aucun document appliqué, repli = nombre de documents retenus
rm -f "$U"/sortie/*; "$OUT" vex "${Y#sha256:}" "$U/sortie" "$U/valide.json" > "$U/r-valide.res"
"$OUT" predicat "$M0/image-avant.grype.json" base-g0 "$U/r-valide.res" repli > "$T/repli-image.json"
[ "$(jq -S . "$T/repli-image.json")" = "$(jq -S '. + {vex: {documents: [], rejetes: 0, ecarteesSansExemption: 0, repli: 1}}' "$M0/image-avant.scan.json")" ] \
  && ok "predicat repli : prédicat d'avant + bloc vex vide et repli 1" || ko "predicat repli : différences"
c=0; "$OUT" predicat "$M0/image-avant.grype.json" base-g0 "$T/vide.json" repli > /dev/null 2> "$T/tmp/err" || c=$?
attendu "predicat repli sans document retenu" "code $c" "code 1"
c=0; "$OUT" predicat "$T/ecarte-sans-doc.json" base-g0 "$U/r-valide.res" repli > /dev/null 2> "$T/tmp/err" || c=$?
attendu "predicat repli avec une entrée écartée par un VEX" "code $c" "code 1"
c=0; "$OUT" predicat "$M0/image-avant.grype.json" base-g0 "$U/r-valide.res" autre > /dev/null 2> "$T/tmp/err" || c=$?
attendu "predicat à 5 arguments, dernier autre que repli" "code $c" "code 2"

# passages 11 et 12 : les cas signer-vex.sh verifier sont en B depuis le passage 14 (le script lit le scan signé dans Zot)

# ------------------------------------------------------------------------------------------------------------------------------ B
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=zot-jetable -addext subjectAltName=IP:127.0.0.1 \
  -addext basicConstraints=critical,CA:TRUE -keyout "$T/cle/zot.key" -out "$T/zot.crt" 2> /dev/null
jq -n --arg r "$T/zot" --arg c "$T/zot.crt" --arg k "$T/cle/zot.key" '{distSpecVersion: "1.1.1", storage: {rootDirectory: $r, gc: false},
  http: {address: "127.0.0.1", port: "15002", tls: {cert: $c, key: $k}}, log: {level: "error"}}' > "$T/zot.json"
# passage 21 : binaire bao extrait et vérifié hors du banc (resultats/07b-p2-bao.log) ; ici, empreinte et commit seulement
BAO=$HOME/.cache/supply-chain-poc/07a/bao-2.7.2/bao
attendu "bao : empreinte du binaire extrait (07b-p2-bao.log)" "$(sha256sum < "$BAO" | cut -c1-16)" 9c5f36287c673f38
attendu "bao : version et commit" "$("$BAO" version | cut -d' ' -f2,3)" "v2.7.2 (9e0a0d3c3504a0a00b45e61355afac5e35c78379),"
OUT=$OUT BAO=$BAO unshare -rn bash "$0" ns
KO=$((KO + $(cat "$T/ko-ns" 2>/dev/null || echo 1)))

# ------------------------------------------------------------------------------------------------------------------------------ C
echo "## C. porte : ec validate input de l'hôte, règles du patch"
P=$T/porte; mkdir -p "$P/regles"; cp "$B/politique/porte/scan.rego" "$P/regles/"
# passage 6 : le patch porte 30 (choix du propriétaire du 21/11) ; null est fabriqué par le sed inverse, comme contre-épreuve
sed "s#/etc/porte/regles-scan#$P/regles#" "$B/politique/porte/policy-scan.yaml" > "$P/politique-30.yaml"
sed "s#vex_age_max_jours: 30#vex_age_max_jours: null#" "$P/politique-30.yaml" > "$P/politique-null.yaml"
grep -q '^ *vex_age_max_jours: 30$' "$P/politique-30.yaml" && ok "politique du patch telle quelle : vex_age_max_jours 30 (choix du propriétaire)" || ko "politique du patch : 30 absent"
grep -q '^ *vex_age_max_jours: null$' "$P/politique-null.yaml" && ok "politique fabriquée : vex_age_max_jours null (sed inverse)" || ko "politique fabriquée : null absent"
# passage 16 : seuil par défaut de l'avis d'âge de signer-vex.sh, confronté à la politique du patch
attendu "signer-vex.sh : VEX_AGE_MAX_JOURS par défaut = vex_age_max_jours de la politique" \
  "$(sed -n 's/^VEX_AGE_MAX_JOURS=\${VEX_AGE_MAX_JOURS:-\([0-9]*\)}$/\1/p' "$B/signer-vex.sh")" "$(yq '.sources[0].ruleData.vex_age_max_jours' "$B/politique/porte/policy-scan.yaml")"
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
juger_porte "porte, repli (passage 18), $VULN en KEV : aucun VEX appliqué" repli 30 1 scan.kev_without_vex
juger_porte "porte, repli, aucune KEV : champ repli accepté" repli 30 0 "" AUCUNE

echo "## D. entrees-scan.py du patch, sur les prédicats de B"
# passage 13 : séries scan_vex_* (bloc vex du prédicat, 0 s'il est absent) ; signe-retract et un prédicat d'avant la tranche 3
cp "$M0/image-avant.scan.json" "$T/avant-t3.json"
for c in complet deb-complet signe-retract avant-t3 repli; do
  p=$T/cas/$c/scan.json; [ "$c" = avant-t3 ] && p=$T/avant-t3.json
  [ -s "$p" ] || { ko "D $c : aucun prédicat"; continue; }
  r=$(python3 -I - "$B/systemd/entrees-scan.py" "$p" "$T" <<'PYD'
import base64, contextlib, hashlib, importlib.util, io, json, os, sys, tempfile, urllib.error
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
      f"vex {x.get('scan_vex_documents')}/{x.get('scan_vex_rejetes')}/{x.get('scan_vex_ecartees_sans_exemption')}/{x.get('scan_vex_repli')}", end="")
# passage 15 : lignes de document VEX, puis main() sur un faux Zot (lecture synthétique, main réel) : referrer A, encore A, puis B
docs = [json.loads(y) for y in es.documents_vex("builds/x", p)]
egal = "=" if ([y.get("vexDocument") for y in docs] == [y["sha256"] for y in (p.get("vex") or {}).get("documents") or []]
               and all("id" not in y for y in docs) and all("vexDocument" not in y for y in e)) else "≠"
sujet = "sha256:" + "5" * 64
enonce = {"_type": "https://in-toto.io/Statement/v1", "subject": [{"name": "x", "digest": {"sha256": "5" * 64}}],
          "predicateType": es.PREDICAT, "predicate": p}
def zot(ref):
    bundle = {"mediaType": es.BUNDLE, "dsseEnvelope": {"payloadType": es.INTOTO, "signatures": [{"sig": "faux"}],
                                                        "payload": base64.b64encode(json.dumps(enonce).encode()).decode()}}
    blob = json.dumps(bundle).encode()
    couche = {"mediaType": es.BUNDLE, "digest": "sha256:" + hashlib.sha256(blob).hexdigest()}
    pages = {f"builds/x/referrers/{sujet}": json.dumps({"manifests": [{"digest": ref, "annotations": {
                 "dev.sigstore.bundle.predicateType": es.PREDICAT, "org.opencontainers.image.created": "2026-11-21T00:00:00Z"}}]}).encode(),
             f"builds/x/manifests/{ref}": json.dumps({"layers": [couche]}).encode(), f"builds/x/blobs/{couche['digest']}": blob}
    def lire(chemin, accepte="application/json"):
        if chemin not in pages:
            raise urllib.error.URLError(f"faux Zot : {chemin} absent")
        return pages[chemin]
    return lire
d = tempfile.mkdtemp(dir=sys.argv[3])
os.mkdir(os.path.join(d, "etat"))
open(os.path.join(d, "s.prom"), "w").close()
os.environ.update(SCANS=f"builds/x@{sujet}", SORTIE=os.path.join(d, "s.prom"), ETAT=os.path.join(d, "etat"))
n, m = [], []
for ref in ("sha256:" + "a" * 64, "sha256:" + "a" * 64, "sha256:" + "b" * 64):
    es.lire = zot(ref)
    o = io.StringIO()
    with contextlib.redirect_stdout(o):
        rc = es.main()
    l = o.getvalue().splitlines()
    n.append(f"{len(l)}" + ("" if rc == 0 else f" (rc {rc})"))
    m.append("émise" if l and "(liste émise)" in l[-1] else "non")
print(f", documents {len(docs)} {egal} prédicat, main {'/'.join(n)} ({', '.join(m)})")
PYD
  )
  case $c in complet) a="22 séries, trouvées 5, écartées 1, kev écartées 0, lignes 5, lignes avec vex 1, vex 1/0/0/0, documents 1 = prédicat, main 7/1/7 (émise, non, émise)" ;;
    deb-complet) a="22 séries, trouvées 66, écartées 1, kev écartées 0, lignes 66, lignes avec vex 1, vex 1/0/0/0, documents 1 = prédicat, main 68/1/68 (émise, non, émise)" ;;
    signe-retract) a="22 séries, trouvées 5, écartées 0, kev écartées 0, lignes 5, lignes avec vex 0, vex 1/1/1/0, documents 1 = prédicat, main 7/1/7 (émise, non, émise)" ;;
    repli) a="22 séries, trouvées 5, écartées 0, kev écartées 0, lignes 5, lignes avec vex 0, vex 0/0/0/1, documents 0 = prédicat, main 6/1/6 (émise, non, émise)" ;;
    *) a="22 séries, trouvées 5, écartées 0, kev écartées 0, lignes 5, lignes avec vex 0, vex 0/0/0/0, documents 0 = prédicat, main 6/1/6 (émise, non, émise)" ;; esac
  attendu "D $c" "$r" "$a"
done
# passage 18 : séries attendues par entrees-scan.sh à la pose et au verif = deux dépôts × séries de comptes()
n=$(python3 -I - "$B/systemd/entrees-scan.py" "$T/cas/complet/scan.json" <<'PYN'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("es", sys.argv[1])
es = importlib.util.module_from_spec(spec)
spec.loader.exec_module(es)
print(len(es.comptes("builds/x", json.load(open(sys.argv[2], encoding="utf-8"))).splitlines()))
PYN
)
attendu "D entrees-scan.sh : séries attendues à la pose et au verif (2 dépôts × $n)" \
  "$(sed -n 's/.*"séries écrites".* \([0-9]*\)$/\1/p' "$B/entrees-scan.sh") et $(sed -n 's/.*"séries scan_entrees\* et scan_vex\* dans Prometheus".* \([0-9]*\)$/\1/p' "$B/entrees-scan.sh")" \
  "$((2 * n)) et $((2 * n))"

apres=$(empreinte)
[ "$avant" = "$apres" ] && ok "base de G0, source, image et deb inchangés ($avant)" || ko "entrées modifiées : $avant puis $apres"
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "## bilan : $KO écart(s) aux prédictions"
