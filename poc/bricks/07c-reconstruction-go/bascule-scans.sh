#!/usr/bin/env bash
# Brique 07c, oubli de l'étape 4 (relevé le 2026-11-24T15:42:24Z) : les unités fraicheur-scan et entrees-scan de sc-stockage
# visent encore builds/scan/sample-app@3a7ca1b1. Bascule étroite de la seule cible sample-app vers f5e6bcb0 ; le deb (60f25f5c)
# est gardé tel quel. Ne relance ni l'étape fraicheur de s6a.sh (déjà portée à f5e6bcb0 pour le rejeu de zéro) ni la 19b.
# Étapes :
#   sec   lecture seule : drop-in s6a-deb.conf en place relu, nouveau drop-in rendu dans $T (seul le digest de sample-app change),
#         référents de scan de f5e6bcb0 relus dans Zot en anonyme ; aucune écriture sur la VM. Sans accord.
#   pose  ACCORD DU PROPRIÉTAIRE (sudo sur sc-stockage, changement de configuration) : drop-in remplacé, daemon-reload, un passage
#         de fraicheur-scan lancé ; contrôles (SCANS en place, résultat, fraicheur-scan.prom). Ensuite, à part :
#         entrees-scan.sh pose (relit SCANS dans fraicheur-scan en place) puis entrees-scan.sh verif.
# L'unité de base fraicheur-scan.service garde DIGEST=3a7ca1b1 : valeur masquée par SCANS (fraicheur-scan.py ne lit DIGEST que
# sans SCANS), laissée pour ne pas toucher à l'unité de la 07a.
# Usage (racine du dépôt) : bash poc/bricks/07c-reconstruction-go/bascule-scans.sh <étape> > <journal>
set -euo pipefail
export LC_ALL=C
O=$HOME/.cache/supply-chain-poc
O8=$O/08
CA=$O8/pki/ca-poc.crt
REG=192.168.161.13:5000
ANCIEN=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
NEUF=sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7
DEB=sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e
DI=/etc/systemd/system/fraicheur-scan.service.d/s6a-deb.conf
SSH_OPTS=(-i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
sur() { env -u SSH_AUTH_SOCK ssh "${SSH_OPTS[@]}" poc@192.168.161.13 "$@"; }   # sc-stockage
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
court() { sed -E 's/sha256:([0-9a-f]{12})[0-9a-f]*/sha256:\1…/g'; }
T=$O/07c/bascule-scans   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/07c/bascule-scans ] || find ~/.cache/supply-chain-poc/07c/bascule-scans -delete
mkdir -p "$T"
trap 'find ~/.cache/supply-chain-poc/07c/bascule-scans -delete' EXIT
echo "# bascule des unités de scan de sc-stockage vers f5e6bcb0, étape ${1:-?}, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"

scans_en_place() { sur "systemctl show -p Environment --value $1.service" </dev/null | tr ' ' '\n' | tr -d '"' | sed -n 's/^SCANS=//;/^builds\//p' | tr '\n' ' ' | sed 's/ $//'; }
dernier_scan() { # dépôt digest : created du référent de scan le plus récent
  curl -fsS --cacert "$CA" "https://$REG/v2/$1/referrers/$2" | jq -r '[.manifests[] | select(.annotations["dev.sigstore.bundle.predicateType"] == "https://supply-chain.example/scan/v1")
    | .annotations["org.opencontainers.image.created"]] | sort | .[-1] // "aucun"'
}

rendre() {
  sur "cat $DI" </dev/null > "$T/en-place.conf"
  sed "s#builds/scan/sample-app@$ANCIEN #builds/scan/sample-app@$NEUF #" "$T/en-place.conf" > "$T/s6a-deb.conf"
  echo "## drop-in en place, puis écart du rendu"
  court < "$T/en-place.conf" | sed 's/^/  /'
  diff "$T/en-place.conf" "$T/s6a-deb.conf" | court | sed 's/^/  /' || true
  attendu "lignes changées par le rendu" "$(diff "$T/en-place.conf" "$T/s6a-deb.conf" | grep -c '^>' || true)" 1
  attendu "SCANS rendu" "$(sed -n 's/^Environment="SCANS=\(.*\)"$/\1/p' "$T/s6a-deb.conf")" "builds/scan/sample-app@$NEUF builds/scan/sample-app-deb@$DEB"
}

etape_sec() {
  attendu "SCANS de fraicheur-scan en place" "$(scans_en_place fraicheur-scan)" "builds/scan/sample-app@$ANCIEN builds/scan/sample-app-deb@$DEB"
  attendu "SCANS de entrees-scan en place" "$(scans_en_place entrees-scan)" "builds/scan/sample-app@$ANCIEN builds/scan/sample-app-deb@$DEB"
  attendu "drop-ins de fraicheur-scan" "$(sur "ls /etc/systemd/system/fraicheur-scan.service.d/" </dev/null | tr '\n' ' ' | sed 's/ $//')" s6a-deb.conf
  rendre
  echo "dernier scan de f5e6bcb0 dans Zot : $(dernier_scan builds/scan/sample-app "$NEUF")"
  echo "dernier scan de 3a7ca1b1 dans Zot : $(dernier_scan builds/scan/sample-app "$ANCIEN")"
  echo "dernier scan du deb dans Zot : $(dernier_scan builds/scan/sample-app-deb "$DEB")"
}

etape_pose() { # ACCORD DU PROPRIÉTAIRE
  : "${ACCORD:?accord du propriétaire requis (changement de configuration sur sc-stockage)}"
  echo "accord du propriétaire (verbatim) : « $ACCORD »"
  rendre
  [ "$KO" = 0 ] || { echo "écart au rendu : rien n'est posé"; return 1; }
  sur "if [ -e /tmp/bascule-scans ]; then find /tmp/bascule-scans -delete; fi; mkdir -m 0700 /tmp/bascule-scans" </dev/null
  env -u SSH_AUTH_SOCK scp -q "${SSH_OPTS[@]}" "$T/s6a-deb.conf" poc@192.168.161.13:/tmp/bascule-scans/ </dev/null
  sur "sudo bash -s" <<'EOS'
set -euo pipefail
install -m 0644 /tmp/bascule-scans/s6a-deb.conf /etc/systemd/system/fraicheur-scan.service.d/s6a-deb.conf
find /tmp/bascule-scans -delete
systemctl daemon-reload
systemctl start fraicheur-scan.service
EOS
  attendu "drop-in installé identique au rendu" "$(sur "sha256sum $DI" </dev/null | cut -c1-64)" "$(sha256sum < "$T/s6a-deb.conf" | cut -c1-64)"
  attendu "SCANS de fraicheur-scan en place" "$(scans_en_place fraicheur-scan)" "builds/scan/sample-app@$NEUF builds/scan/sample-app-deb@$DEB"
  attendu "résultat du passage de fraicheur-scan" "$(sur "systemctl show -p Result --value fraicheur-scan.service" </dev/null)" success
  attendu "timer de fraicheur-scan actif" "$(sur "systemctl is-active fraicheur-scan.timer" </dev/null)" active
  echo "## fraicheur-scan.prom après le passage"
  sur "cat /etc/fichiers-metriques/fraicheur-scan.prom" </dev/null | court | sed 's/^/  /'
  local t
  t=$(sur "cat /etc/fichiers-metriques/fraicheur-scan.prom" </dev/null | sed -n 's/^scan_dernier_referrer_timestamp_seconds{depot="builds\/scan\/sample-app"} //p')
  attendu "horodatage de sample-app = dernier scan de f5e6bcb0" "$(date -u -d "@${t%.*}" +%FT%TZ)" "$(dernier_scan builds/scan/sample-app "$NEUF")"
  echo "rappel : entrees-scan vise encore l'ancien SCANS jusqu'à entrees-scan.sh pose"
}

case "${1:-}" in
  sec|pose) "etape_$1" || true ;;
  *) echo "étape inconnue : ${1:-} (sec | pose)"; exit 2 ;;
esac
echo "## bilan : $N cas, $KO écart(s)"
[ "$KO" = 0 ]
