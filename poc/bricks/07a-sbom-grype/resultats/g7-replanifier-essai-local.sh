#!/usr/bin/env bash
# Essai hors cluster de g7-replanifier.sh releve : VM simulée (sur() local, sudo neutre), Zot simulé par un dossier.
set -u
D=$1; H=$2   # D : racine du dépôt ; H : dossier d'essai (vidé)
rm -rf -- "${H:?}"; mkdir -p "$H/racine/builds/scan/sample-app/blobs/sha256" "$H/w"
touch -d '2026-11-13T10:00:00Z' "$H/racine/builds/scan/sample-app/blobs/sha256/aa"
touch -d '2026-11-14T09:30:00Z' "$H/racine/builds/scan/sample-app/blobs/sha256/bb"
jq --arg r "$H/racine" '.storage.rootDirectory=$r' "$D/poc/bricks/08-trust-plane/stockage/zot.json" > "$H/conf.json"
cp "$H/conf.json" "$H/depot.json"
cat > "$H/stub.sh" <<EOF
W=$H/w
sur() { shift; case \$1 in
  "systemctl show zot.service -p ActiveState --value") echo "\${ETAT_ZOT-active}" ;;
  systemctl*) echo "\${DEMARRAGE_ZOT-Fri 2026-11-13 08:00:00 UTC}" ;;
  "sudo cat /etc/zot/config.json") cat "$H/conf.json" ;;
  *) bash -c "sudo() { \"\\\$@\"; }; \$1" ;; esac; }
lancer() { etape_\$3; }
EOF
sed -e "s#^\. \"\$here/../08-trust-plane/commun.sh\"\$#. $H/stub.sh#" \
    -e "s#^CONF_DEPOT=.*#CONF_DEPOT=$H/depot.json#" \
    "$D/poc/bricks/07a-sbom-grype/g7-replanifier.sh" > "$H/essai.sh"
grep -c "stub.sh\|depot.json" "$H/essai.sh"
echo "== essai 1 : vulndb/grype absent, deux blobs de scan"
bash "$H/essai.sh" releve; echo "code $?"
echo "== essai 2 : find en échec (dossier illisible simulé)"
mkdir -p "$H/racine/vulndb/grype"; chmod 000 "$H/racine/vulndb/grype"
bash "$H/essai.sh" releve 2>&1 | tail -3; echo "code ${PIPESTATUS[0]}"
chmod 755 "$H/racine/vulndb/grype"
echo "== essai 3 : rootDirectory du dépôt différent de la VM"
jq '.storage.rootDirectory="/ailleurs"' "$H/conf.json" > "$H/depot.json"
bash "$H/essai.sh" releve 2>&1 | tail -1; echo "code ${PIPESTATUS[0]}"
cp "$H/conf.json" "$H/depot.json"
echo "== essai 4 : ActiveEnterTimestamp vide (ajouté le 12/11/2026)"
DEMARRAGE_ZOT='' bash "$H/essai.sh" releve 2>&1 | tail -1; echo "code ${PIPESTATUS[0]}"
echo "== essai 5 : zot.service inactif (ajouté le 12/11/2026)"
ETAT_ZOT=inactive bash "$H/essai.sh" releve 2>&1 | tail -1; echo "code ${PIPESTATUS[0]}"
rm -rf -- "${H:?}"
