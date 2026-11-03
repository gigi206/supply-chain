#!/usr/bin/env bash
# Brique 10 : replay indépendant (décisions D1 à D7 du propriétaire du 03/11/2026). Domaine de replay : ses fichiers vivent dans
# ~/.cache/supply-chain-poc/10, sans rien de commun avec 08 (clés, secrets) ; seules des lectures anonymes de Zot et de Forgejo.
# Jalon R1, sur l'hôte, sans VM ni installation :
#   cosign_stockage  Zot 2.1.22 jetable et cosign 3.1.4 dans un espace de noms réseau vide (unshare -rn : boucle locale seule) ;
#                    image et clés jetables ; cosign attest --key d'un prédicat VSA d'essai : besoin de réseau ? stockage en tag
#                    .att ou en referrer OCI 1.1 ?
#   version_go       version de Go de l'entrée plateforme/builder-go-voie-d de la provenance, lue dans ses couches (rien d'exécuté)
#   outils           toolchain Go officielle de go.dev (sha256 de go.dev/dl/?mode=json) ; archives des outils de mise.lock
#                    (BuildKit, runc, rootlesskit, cosign, oras, crane) téléchargées et vérifiées pour la VM
# Jalon R2 (JALON=r2), création du domaine (D1 b, D2 a, D3, réseau distinct, décisions du propriétaire du 03/11/2026) :
#   vm               image Debian 13 vérifiée (sha512, celle des trois VM), pool et réseau NAT propres (supply-chain-replay,
#                    192.168.162.0/24), clés SSH du domaine, VM sc-replay (4 vCPU, 6 Gi, 20 Go) ; trois VM du PoC non touchées
#   isolement        depuis la VM : 192.168.161.0/24 (Zot, Forgejo, API de k3s) injoignable ? extérieur joignable ?
#   paquets          busybox-static et diffoscope-minimal par apt (signatures de l'archive Debian), sans recommandés ;
#                    versions épinglées (celles mesurées au premier passage de R2)
#   outils           archives copiées puis revérifiées DANS la VM (empreintes fixées ci-dessous) ; installation
#                    git ajouté le 03/11/2026 pour R3 (accord du propriétaire : « Installer git »)
#   cle_vsa          paire cosign générée dans la VM par replay (mot de passe aléatoire 0600, jamais sorti) ; clé publique
#                    copiée dans resultats/vsa-cle-publique.pem
# Jalon R3 (JALON=r3), préchargement :
#   transporter      SUR L'HÔTE, transport non fiable : copies anonymes (oras) de l'image, de son tag .att, des bundles
#                    horodatés et des entrées déclarées dans un layout OCI ; bundle git de main (Forgejo, sans compte) ;
#                    ancres de confiance du dépôt (clé de Chains, chaîne de la TSA) ; le tout copié dans la VM (~/r3)
#   verifier_entrees DANS LA VM : bundles horodatés vérifiés hors réseau (clé de Chains, sujet, jeton de la TSA) ; provenance
#                    extraite d'un bundle vérifié ; politique, section 1 ; digests des entrées ; commit ; recette extraite du
#                    bundle construire-image ; version de Go ; heures du build (signée et horodatée)
# Jalon R4 (JALON=r4), rebuild hors ligne, pas avant FIN_BUILD + 24 h :
#   rebuild          bundle preparer-entrees et outils/rebuild.sh copiés dans la VM ; rebuild lancé détaché (systemd-run), lien
#                    de la VM coupé aussitôt (virsh domif-setlink down), compteurs de l'interface relus côté hôte juste après la
#                    coupure et juste avant le rétablissement (ATTENTE_HORS_LIGNE s) ; rebuild.sh refuse de démarrer si la
#                    porteuse est présente ; résultat lu après le rétablissement, valable seulement s'il a fini avant
#   repetition       essai lien ÉTABLI, non compté : copie de rebuild.sh sans l'attente ni le refus de porteuse, même unité
# Jalon R5 (JALON=r5) :
#   signature_hors_registre  sur l'hôte, comme cosign_stockage : VSA signée par cosign attest-blob --statement sans registre,
#                    poussée en referrer par oras attach, vérifiée par cosign (clé de VSA acceptée, autre clé refusée)
# D5 (JALON=d5), compte Zot poc-replay (accord du propriétaire : « Oui, appliquer D5 ») :
#   compte_zot       mot de passe et ligne htpasswd bcrypt dans ~/.cache/supply-chain-poc/10/secrets (la 08 ne lit que le hash)
#   droits_zot       après « mise run confiance:stockage -- zot » : poc-replay sur le dépôt jetable builds/essai-replay (push par
#                    digest et referrer acceptés ; tag, dépôt hors de builds/**, suppression refusés)
#
# Usage (racine du dépôt) : JALON=r2 mise run replay -- <étape>…   (journal : resultats/<jalon>-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
racine_depot=$(cd "$here/../../.." && pwd)
R=$here/resultats
O=$HOME/.cache/supply-chain-poc/10
T=$O/telechargements
E=$O/essais
mkdir -p "$R" "$T" "$E"
ZOT_POC=192.168.161.13:5000                      # Zot du PoC, lecture anonyme seulement
CA_POC=$O/ca-poc.crt                             # certificat public de la CA du PoC (TLS de Zot et de Forgejo), copié une fois
[ -s "$CA_POC" ] || cp "$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt" "$CA_POC"   # public ; aucune clé de 08 n'est lue
IMAGE=builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # sujet de la provenance
INVOCATION=d9006af7-5d9a-4a5e-878e-1c9a5bd96d56   # PipelineRun du 02/11/2026, 13:58:36 à 13:59:30 UTC

# Domaine de replay : VM, réseau, clés (rien de commun avec 08 ; l'image Debian publique est relue dans le cache de 08 et revérifiée)
IMG=$HOME/.cache/supply-chain-poc/08/telechargements/debian/debian-13-generic-amd64-20261026-2643.qcow2
IMG_SHA512=5bd891c6e62d01639f52a5587b72a4607421e445732214be787dba6043cf9797a6ff90bed982aada6a6c7e619f1f956d961c4fad76757171abd607920aac098a
POOL=supply-chain-replay
POOL_DIR=/var/lib/libvirt/supply-chain-replay
NET=supply-chain-replay
VM=sc-replay
VM_IP=192.168.162.14
SSH_DIR=$O/ssh
W=$O/travail
SSH_OPTS=(-i "$SSH_DIR/id_ed25519" -o UserKnownHostsFile="$SSH_DIR/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
# Empreintes attendues par le domaine (mise.lock et go.dev ; signatures vérifiées sur l'hôte pour runc, oras, cosign ;
# BuildKit sur empreinte seule, décision du propriétaire du 03/11/2026 ; Go recoupé avec le module de sum.golang.org)
OUTILS_SHA256="d18b8188b600e201a1b3d08c20e2a1e439cf51d2c2285f132dd9bd51c666f6d6  buildkit-v0.25.2.linux-amd64.tar.gz
8781ab9f71c12f314d21c8e85f13ca1a82d90cf475aa5131a7b543fcc5487543  runc.amd64
424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa  cosign-linux-amd64
66fb0ad7206f3f6fa77ed5b552049d364ccf4b50b1684554f731f76302b52ca0  oras_1.3.6_linux_amd64.tar.gz
ccfe7ae822d2c2f41f4fe7c956199967a4dac22d0ee0d2b2bfdb440aab3b20c5  go1.26.10.linux-amd64.tar.gz"
v() { virsh -c qemu:///system "$@"; }
sur() { ssh "${SSH_OPTS[@]}" "replay@$VM_IP" "$@"; }

lancer() { # jalon étape… : journal resultats/<jalon>-<étape>.log
  local j=$1 e; shift
  [ $# -gt 0 ] || { echo "usage : $0 $(declare -F | awk '$3 ~ /^etape_/ {sub("etape_", "", $3); printf "%s|", $3}' | sed 's/|$//')…" >&2; exit 2; }
  for e in "$@"; do declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }; done
  for e in "$@"; do
    { echo "# ${0##*/} $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/$j-$e.log"
  done
}

etape_cosign_stockage() {
  local d=$E/cosign
  rm -rf -- "${d:?}" && mkdir -p "$d/zot" && cd "$d"
  printf '{"distSpecVersion":"1.1.1","storage":{"rootDirectory":"%s/zot"},"http":{"address":"127.0.0.1","port":"15000"},"log":{"level":"error"}}\n' "$d" > zot.json
  printf '{"verifier":{"id":"https://supply-chain.example/verifiers/essai"},"resourceUri":"essai","policy":{"uri":"essai"},"verificationResult":"PASSED","verifiedLevels":["POC_ESSAI"]}\n' > vsa.json
  printf 'essai\n' > f && tar -cf couche.tar f
  # tout ce qui suit tourne dans un espace de noms réseau vide : aucune route, seule la boucle locale
  unshare -rn bash -s "$d" "$(command -v zot)" "$(command -v crane)" "$(command -v cosign)" <<'EOS'
set -uo pipefail
d=$1 zot=$2 crane=$3 cosign=$4; cd "$d"
ip link set lo up
echo "## interfaces de l'espace de noms : $(ip -o link | awk -F': ' '{print $2}' | paste -sd' ') ; routes : $(ip route | wc -l)"
"$zot" serve zot.json > zot.log 2>&1 & z=$!
for _ in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:15000/v2/ && break; sleep 0.5; done
"$crane" append --insecure --oci-empty-base -f couche.tar -t 127.0.0.1:15000/essai/image:v1 > /dev/null
img=127.0.0.1:15000/essai/image@$("$crane" digest --insecure 127.0.0.1:15000/essai/image:v1)
echo "## image jetable : $img"
export COSIGN_PASSWORD=essai-jetable
"$cosign" generate-key-pair > /dev/null 2>&1 && echo "clés jetables : $(ls cosign.key cosign.pub | paste -sd' ')"
echo "## cosign attest --key, sans option de stockage ni de journal"
timeout 60 "$cosign" attest --key cosign.key --type https://slsa.dev/verification_summary/v1 --predicate vsa.json --allow-http-registry --yes "$img" 2>&1 | tail -6
echo "code de sortie : ${PIPESTATUS[0]}"
echo "## configuration de signature sans aucun service (ni Fulcio, ni Rekor, ni TSA)"
"$cosign" signing-config create --out signature-vide.json 2>&1 | tail -2; jq -c . signature-vide.json
echo "## cosign attest --key --signing-config signature-vide.json"
timeout 60 "$cosign" attest --key cosign.key --signing-config signature-vide.json --type https://slsa.dev/verification_summary/v1 \
  --predicate vsa.json --allow-http-registry --yes "$img" 2>&1 | tail -6
echo "code de sortie : ${PIPESTATUS[0]}"
echo "## cosign verify-attestation --key cosign.pub, sans journal (hors réseau)"
timeout 60 "$cosign" verify-attestation --key cosign.pub --insecure-ignore-tlog --type https://slsa.dev/verification_summary/v1 \
  --allow-http-registry "$img" 2>&1 | grep -vE '^\{' | tail -4
echo "code de sortie : ${PIPESTATUS[0]}"
echo "## tags du dépôt essai/image"
"$crane" ls --insecure 127.0.0.1:15000/essai/image
echo "## referrers de l'image (API OCI 1.1)"
curl -s "http://127.0.0.1:15000/v2/essai/image/referrers/${img#*@}" | jq -c '[.manifests[]? | {artifactType, mediaType, digest: .digest[0:19]}]'
for t in $("$crane" ls --insecure 127.0.0.1:15000/essai/image | grep -E '\.(att|sig)$'); do
  echo "manifeste du tag $t : $("$crane" manifest --insecure "127.0.0.1:15000/essai/image:$t" | jq -c '{mediaType, artifactType, couches: [.layers[].mediaType]}')"
done
kill $z
EOS
  cd / && rm -rf -- "${d:?}"
}

provenance() { # $O/provenance.json : énoncé de la provenance du PipelineRun INVOCATION, tiré du tag .att (lecture anonyme ;
  # sa signature n'est vérifiée qu'en R3, dans le domaine)
  local t l
  [ -s "$O/provenance.json" ] && return
  t=$(echo "${IMAGE#*@}" | tr : -).att
  for l in $(SSL_CERT_FILE=$CA_POC crane manifest "$ZOT_POC/${IMAGE%@*}:$t" | jq -r '.layers[].digest'); do
    SSL_CERT_FILE=$CA_POC crane blob "$ZOT_POC/${IMAGE%@*}@$l" | jq -r '.payload' | base64 -d > "$E/enonce.json"
    if [ "$(jq -r '.predicate.runDetails.metadata.invocationId' "$E/enonce.json")" = "$INVOCATION" ] \
       && [ "$(jq '.predicate.buildDefinition.resolvedDependencies | length' "$E/enonce.json")" -gt 6 ]; then
      mv "$E/enonce.json" "$O/provenance.json"; echo "provenance $INVOCATION : couche $l"; return
    fi
  done
  rm -f "$E/enonce.json"; echo "KO   provenance $INVOCATION introuvable" >&2; exit 1
}

etape_version_go() {
  local d=$E/builder ref l
  rm -rf -- "${d:?}" && mkdir -p "$d"
  provenance
  ref=$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.uri | test("builder-go-voie-d")) | "\(.uri | sub("^oci://"; ""))@sha256:\(.digest.sha256)"' "$O/provenance.json")
  echo "entrée de la provenance : $ref"
  ref=${ref/sc-stockage.poc.test:5000/$ZOT_POC}   # l'hôte ne résout pas poc.test ; le certificat de Zot couvre aussi l'IP
  SSL_CERT_FILE=$CA_POC crane manifest "$ref" | jq -r '.mediaType, (.layers | length | "couches : \(.)")'
  for l in $(SSL_CERT_FILE=$CA_POC crane manifest "$ref" | jq -r '.layers[].digest'); do
    if SSL_CERT_FILE=$CA_POC crane blob "${ref%@*}@$l" | tar -xzf - -C "$d" --wildcards '*go/VERSION' 2>/dev/null; then :; fi
  done
  find "$d" -name VERSION -path '*go/VERSION' -exec sh -c 'echo "${1#$2/} :"; head -2 "$1"' _ {} "$d" \;
  find "$d" -name VERSION -path '*go/VERSION' -exec head -1 {} \; | head -1 > "$O/version-go"
  echo "version retenue pour le domaine : $(cat "$O/version-go")"
  rm -rf -- "${d:?}"
}

etape_outils() {
  local v f s u
  v=$(cat "$O/version-go")
  echo "## toolchain Go officielle $v (go.dev)"
  curl -fsS 'https://go.dev/dl/?mode=json&include=all' -o "$E/go-dl.json"
  s=$(jq -r --arg f "$v.linux-amd64.tar.gz" '.[].files[] | select(.filename == $f) | .sha256' "$E/go-dl.json")
  echo "sha256 publié par go.dev : ${s:-absent}"
  [ -n "$s" ] || { echo "KO   $v.linux-amd64.tar.gz absent de go.dev"; exit 1; }
  [ -s "$T/$v.linux-amd64.tar.gz" ] || curl -fsSL -o "$T/$v.linux-amd64.tar.gz" "https://go.dev/dl/$v.linux-amd64.tar.gz"
  echo "$s  $T/$v.linux-amd64.tar.gz" | sha256sum -c
  rm -f "$E/go-dl.json"
  echo "## archives des outils (url et sha256 de mise.lock)"
  python3 -I - "$racine_depot/mise.lock" <<'PY' > "$E/outils.tsv"
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
for k in ["aqua:moby/buildkit", "aqua:opencontainers/runc", "aqua:rootless-containers/rootlesskit",
          "aqua:sigstore/cosign", "aqua:oras-project/oras", "aqua:google/go-containerregistry"]:
    e = d["tools"][k][0]; p = e["platforms.linux-x64"]
    print(k, e["version"], p["url"], p["checksum"].removeprefix("sha256:"), sep="\t")
PY
  while IFS=$'\t' read -r n v u s; do
    f=$T/${u##*/}
    [ -s "$f" ] || curl -fsSL -o "$f" "$u"
    printf '%-40s %-8s ' "$n" "$v"; echo "$s  $f" | sha256sum -c 2>&1 | sed "s#$T/##"
  done < "$E/outils.tsv"
  rm -f "$E/outils.tsv"
}

etape_vm() {
  local d=$W/graine
  echo "## VM du PoC avant : $(v list --name | grep -E '^sc-' | while read -r n; do printf '%s=%s ' "$n" "$(v domid "$n")"; done)"
  (cd "$(dirname "$IMG")" && echo "$IMG_SHA512  $(basename "$IMG")" | sha512sum -c)
  mkdir -p "$SSH_DIR" "$W" && chmod 0700 "$SSH_DIR" "$W"
  [ -f "$SSH_DIR/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C supply-chain-poc-10-replay -f "$SSH_DIR/id_ed25519"
  [ -f "$SSH_DIR/hote-$VM" ] || ssh-keygen -q -t ed25519 -N '' -C "$VM" -f "$SSH_DIR/hote-$VM"
  printf '%s %s\n' "$VM_IP" "$(cut -d' ' -f1-2 "$SSH_DIR/hote-$VM.pub")" > "$SSH_DIR/known_hosts"
  v pool-list --all --name | grep -qx "$POOL" || { v pool-define-as "$POOL" dir --target "$POOL_DIR"; v pool-build "$POOL"; }
  v pool-list --name | grep -qx "$POOL" || v pool-start "$POOL"
  v net-list --all --name | grep -qx "$NET" || v net-define "$here/libvirt/reseau.xml"
  v net-autostart --disable "$NET" > /dev/null
  v net-list --name | grep -qx "$NET" || v net-start "$NET"
  if ! v vol-info --pool "$POOL" "$VM.qcow2" > /dev/null 2>&1; then
    qemu-img convert -f qcow2 -O qcow2 "$IMG" "$W/$VM.qcow2" && qemu-img resize -q "$W/$VM.qcow2" 20G
    v vol-create-as "$POOL" "$VM.qcow2" "$(stat -c %s "$W/$VM.qcow2")" --format qcow2 > /dev/null
    v vol-upload --pool "$POOL" --sparse "$VM.qcow2" "$W/$VM.qcow2" && rm -f "$W/$VM.qcow2"
  fi
  if ! v vol-info --pool "$POOL" "$VM-graine.iso" > /dev/null 2>&1; then
    rm -rf "$d" && mkdir -p "$d" && chmod 0700 "$d"
    printf 'instance-id: %s-1\nlocal-hostname: %s\n' "$VM" "$VM" > "$d/meta-data"
    awk -v pub="$(cut -d' ' -f1-2 "$SSH_DIR/hote-$VM.pub")" -v cle="$(cat "$SSH_DIR/id_ed25519.pub")" -v priv="$SSH_DIR/hote-$VM" '
      /@CLE_HOTE_PRIVEE@/ { while ((getline l < priv) > 0) print "    " l; next }
      { gsub(/@CLE_HOTE_PUBLIQUE@/, pub); gsub(/@CLE_REPLAY@/, cle); print }' "$here/cloud-init/user-data.in" > "$d/user-data"
    if grep -q '@[A-Z_]*@' "$d/user-data"; then echo "KO   graine incomplète" >&2; exit 1; fi
    genisoimage -quiet -output "$W/$VM-graine.iso" -volid cidata -joliet -rock "$d/user-data" "$d/meta-data"
    rm -rf -- "${d:?}"
    v vol-create-as "$POOL" "$VM-graine.iso" "$(stat -c %s "$W/$VM-graine.iso")" --format raw > /dev/null
    v vol-upload --pool "$POOL" --sparse "$VM-graine.iso" "$W/$VM-graine.iso" && rm -f "$W/$VM-graine.iso"
  fi
  v list --all --name | grep -qx "$VM" || v define "$here/libvirt/$VM.xml"
  v autostart --disable "$VM" > /dev/null
  v list --name | grep -qx "$VM" || v start "$VM"
  local debut=$SECONDS
  for _ in $(seq 90); do sur true 2> /dev/null && break; sleep 2; done
  sur true && echo "SSH de $VM ($VM_IP) : joignable avec la clé d'hôte attendue, $((SECONDS - debut)) s après le démarrage"
  sur 'echo "$(hostname) : $(nproc) vCPU, $(free -g | awk "/Mem/ {print \$2}") Gi, $(df -h / | awk "NR==2 {print \$2}") ; $(. /etc/os-release; echo $PRETTY_NAME)"'
  echo "## VM du PoC après : $(v list --name | grep -E '^sc-' | while read -r n; do printf '%s=%s ' "$n" "$(v domid "$n")"; done)"
  echo "## réseau supply-chain-poc inchangé : $(v net-dumpxml supply-chain-poc | grep -c "host mac") baux fixes, $(v net-info supply-chain-poc | awk '/Active/ {print $2}')"
}

etape_isolement() {
  sur bash -s <<'EOS'
echo "## routes de la VM"; ip -4 route
for c in 192.168.161.13:5000 192.168.161.13:3000 192.168.161.11:6443 192.168.161.1:22; do
  if timeout 5 bash -c "</dev/tcp/${c%:*}/${c#*:}" 2> /dev/null; then echo "$c : JOIGNABLE"; else echo "$c : injoignable"; fi
done
echo "extérieur, https://deb.debian.org : HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://deb.debian.org/debian/ || echo échec)"
EOS
}

etape_paquets() {
  sur sudo bash -s <<'EOS'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update 2>&1 | grep -viE '^(Hit|Get|Reading)' || true
apt-get install -y --no-install-recommends busybox-static=1:1.37.0-6+b9 diffoscope-minimal=297+deb13u1 git=1:2.47.3-0+deb13u1 2>&1 | grep -iE 'warning|untrusted|unauthenticated|^Setting up (busybox-static|diffoscope|git) ' || true
dpkg-query -W -f='${Package} ${Version}\n' busybox-static diffoscope-minimal git
echo "paquets installés en tout : $(dpkg-query -W | wc -l)"
EOS
}

etape_outils() {
  local f fichiers
  echo "$OUTILS_SHA256" > "$W/sha256-attendues"
  for f in $(awk '{print $2}' "$W/sha256-attendues"); do [ -s "$T/$f" ] || { echo "KO   $f absent (R1, étape outils)" >&2; exit 1; }; done
  sur 'rm -rf /tmp/outils && mkdir -m 0700 /tmp/outils'
  mapfile -t fichiers < <(awk -v t="$T" '{print t "/" $2}' "$W/sha256-attendues")
  scp -q "${SSH_OPTS[@]}" "$W/sha256-attendues" "${fichiers[@]}" "replay@$VM_IP:/tmp/outils/"
  sur sudo bash -s <<'EOS'
set -euo pipefail
cd /tmp/outils
echo "## empreintes vérifiées dans la VM"; sha256sum -c sha256-attendues
tar -xzf buildkit-v0.25.2.linux-amd64.tar.gz -C /usr/local bin/buildkitd bin/buildctl
install -m 0755 runc.amd64 /usr/local/bin/runc
install -m 0755 cosign-linux-amd64 /usr/local/bin/cosign
tar -xzf oras_1.3.6_linux_amd64.tar.gz -C /usr/local/bin oras
rm -rf /usr/local/go && tar -xzf go1.26.10.linux-amd64.tar.gz -C /usr/local
cd / && rm -rf /tmp/outils
echo "## versions"
buildctl --version; buildkitd --version; runc --version | head -1; cosign version 2>&1 | grep GitVersion; oras version | head -1
/usr/local/go/bin/go version
EOS
  rm -f "$W/sha256-attendues"
}

etape_cle_vsa() {
  sur bash -s <<'EOS'
set -euo pipefail
umask 077
mkdir -p ~/vsa && cd ~/vsa
[ -s mot-de-passe ] || head -c 32 /dev/urandom | base64 | tr -d '\n' > mot-de-passe
if [ ! -s cosign.key ]; then COSIGN_PASSWORD=$(cat mot-de-passe) cosign generate-key-pair > /dev/null 2>&1; fi
stat -c '%a %U %n' mot-de-passe cosign.key cosign.pub
EOS
  sur 'cat ~/vsa/cosign.pub' > "$R/vsa-cle-publique.pem"
  openssl pkey -pubin -in "$R/vsa-cle-publique.pem" -noout -text | head -2
  echo "empreinte sha256 de la clé publique de VSA : $(openssl pkey -pubin -in "$R/vsa-cle-publique.pem" -outform DER | sha256sum | cut -c1-64)"
  echo "empreinte sha256 de la clé publique de Chains : $(openssl pkey -pubin -in "$racine_depot/poc/bricks/08-trust-plane/resultats/chains-cle-publique.pem" -outform DER | sha256sum | cut -c1-64)"
}

URL_TSA=http://timestamp-authority.tsa.svc.cluster.local:3000/api/v1/timestamp   # identifiant de la TSA dans la racine

etape_transporter() {
  local x=$W/r3 l t n
  rm -rf -- "${x:?}" && mkdir -p "$x/layout" && chmod 0700 "$x"
  oc() { oras copy --from-ca-file "$CA_POC" "$ZOT_POC/$1" --to-oci-layout "$x/layout:$2" > /dev/null && echo "copié : $1 -> $2"; }
  oc "${IMAGE%@*}@${IMAGE#*@}" sujet
  oc "${IMAGE%@*}:$(echo "${IMAGE#*@}" | tr : -).att" att
  n=0
  for t in $(oras repo tags --ca-file "$CA_POC" "$ZOT_POC/horodatage/bundles" | grep "^${IMAGE#*@sha256:}-"); do
    n=$((n + 1)); oc "horodatage/bundles:$t" "bundle-${t##*-}"
  done
  echo "bundles horodatés de l'image : $n"
  # digests des entrées lus dans la provenance NON vérifiée (transport seulement ; la VM vérifie)
  for l in $(oras manifest fetch --ca-file "$CA_POC" "$ZOT_POC/${IMAGE%@*}:$(echo "${IMAGE#*@}" | tr : -).att" \
             | python3 -I -c 'import json,sys; print(" ".join(x["digest"] for x in json.load(sys.stdin)["layers"]))'); do
    oras blob fetch --ca-file "$CA_POC" --output - "$ZOT_POC/${IMAGE%@*}@$l" | python3 -I "$here/outils/entrees.py" "$INVOCATION" >> "$x/entrees.txt"
  done
  while read -r nom depot d; do oc "$depot@sha256:$d" "$nom"; done < "$x/entrees.txt"
  rm -f "$x/entrees.txt"
  rm -rf "$x/git" && GIT_TERMINAL_PROMPT=0 git -c http.sslCAInfo="$CA_POC" clone -q --mirror "https://${ZOT_POC%:*}:3000/workspace/sample-app.git" "$x/git"
  git -C "$x/git" bundle create -q "$x/sample-app.bundle" main && rm -rf "$x/git"
  echo "bundle git : $(du -h "$x/sample-app.bundle" | cut -f1)"
  cp "$racine_depot/poc/bricks/08-trust-plane/resultats/chains-cle-publique.pem" "$x/chains.pub"
  cp "$racine_depot/poc/bricks/08-trust-plane/resultats/tsa-chaine.pem" "$x/tsa-chaine.pem"
  cp "$here/outils/verifier_entrees.py" "$x/"
  ( cd "$x" && sha256sum chains.pub tsa-chaine.pem sample-app.bundle verifier_entrees.py && tar -cf r3.tar layout chains.pub tsa-chaine.pem sample-app.bundle verifier_entrees.py )
  sur 'rm -rf ~/r3 && mkdir -m 0700 ~/r3'
  scp -q "${SSH_OPTS[@]}" "$x/r3.tar" "replay@$VM_IP:r3/"
  sur 'cd ~/r3 && tar -xf r3.tar && rm r3.tar && du -sh ~/r3 | cut -f1 | sed "s/^/taille dans la VM : /"'
  rm -rf -- "${x:?}"
}

etape_verifier_entrees() { # tout se passe dans la VM : verifier_entrees.py (transporté, son sha256 est journalisé)
  sur "cd ~/r3 && sha256sum verifier_entrees.py && python3 -I verifier_entrees.py '$IMAGE' '$INVOCATION' '$URL_TSA'"
}

FIN_BUILD=2026-11-02T13:59:30Z   # runDetails.metadata.finishedOn de la provenance vérifiée en R3
ATTENTE_HORS_LIGNE=${ATTENTE_HORS_LIGNE:-1200}   # secondes lien coupé ; le rebuild doit finir avant le rétablissement

transporter_r4() { # rebuild.sh : bundle preparer-entrees et ce rebuild.sh copiés dans ~/r4 de la VM, vidé d'abord
  local x=$W/r4 d
  rm -rf -- "${x:?}" && mkdir -p "$x" && chmod 0700 "$x"
  # digest de preparer-entrees lu dans la provenance VÉRIFIÉE en R3 (dans la VM) ; la VM le revérifie dans rebuild.sh
  d=$(sur "python3 -I -c 'import json; print([x for x in json.load(open(\"r3/provenance.json\"))[\"predicate\"][\"buildDefinition\"][\"resolvedDependencies\"] if x.get(\"uri\",\"\").endswith(\"preparer-entrees\")][0][\"digest\"][\"sha256\"])'")
  oras copy --from-ca-file "$CA_POC" "$ZOT_POC/tekton/tasks/preparer-entrees@sha256:$d" --to-oci-layout "$x/layout:preparer-entrees" > /dev/null
  cp "$1" "$x/rebuild.sh"
  ( cd "$x" && sha256sum rebuild.sh && tar -cf r4.tar layout rebuild.sh )
  sur 'sudo rm -rf ~/r4 && mkdir -m 0700 ~/r4'   # rebuild.sh écrit en root dans ~/r4
  scp -q "${SSH_OPTS[@]}" "$x/r4.tar" "replay@$VM_IP:r4/"
  sur 'cd ~/r4 && tar -xf r4.tar && rm r4.tar && sha256sum rebuild.sh'
  rm -rf -- "${x:?}"
}

etape_repetition() { # R4, répétition lien ÉTABLI, archivée comme essai et non comptée (choix du propriétaire : « Corriger,
  # répéter, relancer ») : copie de outils/rebuild.sh sans l'attente de 20 s ni le refus si la porteuse est présente (deux
  # lignes retirées, diff journalisé) ; même transport, même unité systemd-run en root ; ~/r4 et la racine BuildKit sont vidés
  # par le second passage
  local c=$W/rebuild-repetition.sh
  sed -e '/^sleep 20 /d' -e '/non coupé"; exit 1; }$/d' "$here/outils/rebuild.sh" > "$c"
  echo "## lignes retirées de outils/rebuild.sh"; diff "$here/outils/rebuild.sh" "$c" | sed -n 's/^< /  /p'
  [ "$(diff "$here/outils/rebuild.sh" "$c" | grep -c '^[<>]')" = 2 ] || { echo "REFUS : copie inattendue"; exit 1; }
  transporter_r4 "$c"; rm -f -- "${c:?}"
  sur 'sudo systemd-run --unit=replay-r4-repetition --collect --wait --property=Type=exec /bin/bash /home/replay/r4/rebuild.sh' 2>&1 | tail -4 || true
  echo "## résultat (écrit dans la VM)"; sur 'cat ~/r4/resultat.txt'
  echo "## journal du rebuild (fin)"; sur 'tail -15 ~/r4/rebuild.log'
}

etape_rebuild() {
  local iface s0 s1 s2 coupe retabli
  if [ "$(date -u +%s)" -lt $(( $(date -u -d "$FIN_BUILD" +%s) + 86400 )) ]; then
    echo "REFUS : moins de 24 h depuis la fin du build ($FIN_BUILD)"; exit 1
  fi
  echo "## délai : $(( ($(date -u +%s) - $(date -u -d "$FIN_BUILD" +%s)) / 60 )) min depuis la fin du build ($FIN_BUILD)"
  transporter_r4 "$here/outils/rebuild.sh"
  iface=$(v domiflist "$VM" | awk '$3 == "supply-chain-replay" {print $1}')
  echo "## interface de $VM côté hôte : $iface"
  # domifstat est vu de la VM (calibré le 03/11, r4-essai-coupure.log) : tx_* = ce que la VM émet ; rx_* bouge pendant la
  # coupure sans que l'invité reçoive (trames du pont) : consigné, pas compté
  st() { v domifstat "$VM" "$iface" | awk '{printf "%s=%s ", $2, $3}'; }
  sortie() { v domifstat "$VM" "$iface" | awk '$2 ~ /^tx_(bytes|packets)$/ {printf "%s=%s ", $2, $3}'; }
  s0=$(st)
  sur 'sudo systemd-run --unit=replay-r4 --collect --property=Type=exec /bin/bash /home/replay/r4/rebuild.sh' 2>&1 | tail -1
  # la VM ne reste jamais coupée sans surveillance ; interface développée à la pose (iface est locale : le premier passage
  # la lisait à la sortie du script, « unbound variable »)
  # shellcheck disable=SC2064   # développement à la pose, voulu
  trap "v domif-setlink '$VM' '$iface' up > /dev/null 2>&1 || true" EXIT
  v domif-setlink "$VM" "$iface" down > /dev/null
  coupe=$(date -u +%FT%TZ)
  s1=$(st); e1=$(sortie)
  echo "lien coupé à $coupe ($(v domif-getlink "$VM" "$iface" | awk '{print $NF}'))"
  echo "compteurs avant le lancement : $s0"
  echo "compteurs juste après la coupure : $s1"
  sleep "$ATTENTE_HORS_LIGNE"
  s2=$(st); e2=$(sortie)
  echo "compteurs juste avant le rétablissement ($ATTENTE_HORS_LIGNE s plus tard) : $s2"
  [ "$e1" = "$e2" ] && echo "OK   sortie de la VM inchangée pendant la coupure ($e2)" || echo "KO   la VM a émis pendant la coupure : $e1 -> $e2"
  v domif-setlink "$VM" "$iface" up > /dev/null
  retabli=$(date -u +%FT%TZ)
  echo "lien rétabli à $retabli"
  for _ in $(seq 60); do sur true 2> /dev/null && break; sleep 2; done
  # code de sortie écrit par rebuild.sh (systemctl show rend des valeurs par défaut une fois l'unité déchargée par --collect)
  echo "## sortie de rebuild.sh : $(sur "sed -n 's/^sortie=//p' ~/r4/resultat.txt" || true)"
  echo "## résultat (écrit dans la VM)"
  sur 'cat ~/r4/resultat.txt'
  fin=$(sur "sed -n 's/^fin=//p' ~/r4/resultat.txt")
  if [ -n "$fin" ] && [ "$(date -u -d "$fin" +%s)" -lt "$(date -u -d "$retabli" +%s)" ]; then
    echo "OK   rebuild terminé ($fin) avant le rétablissement du lien ($retabli)"
  else
    echo "KO   rebuild non terminé avant le rétablissement du lien ($retabli) : résultat non valable hors ligne"
  fi
  echo "## journal du rebuild (fin)"; sur 'tail -15 ~/r4/rebuild.log'
}

etape_signature_hors_registre() { # R5, mesure préalable sur l'hôte (comme cosign_stockage) : VSA signée sans registre, poussée en
  # referrer par oras, trouvée et vérifiée par cosign ; le tout dans un espace de noms réseau vide, avec Zot, image et clés jetables
  local d=$E/signature
  rm -rf -- "${d:?}" && mkdir -p "$d/zot" && cd "$d"
  printf '{"distSpecVersion":"1.1.1","storage":{"rootDirectory":"%s/zot"},"http":{"address":"127.0.0.1","port":"15000"},"log":{"level":"error"}}\n' "$d" > zot.json
  printf 'essai\n' > f && tar -cf couche.tar f
  unshare -rn bash -s "$d" "$(command -v zot)" "$(command -v crane)" "$(command -v cosign)" "$(command -v oras)" <<'EOS'
set -uo pipefail
d=$1 zot=$2 crane=$3 cosign=$4 oras=$5; cd "$d"
ip link set lo up
echo "## espace de noms : $(ip -o link | awk -F': ' '{print $2}' | paste -sd' ') ; routes : $(ip route | wc -l)"
"$zot" serve zot.json > zot.log 2>&1 & z=$!
for _ in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:15000/v2/ && break; sleep 0.5; done
"$crane" append --insecure --oci-empty-base -f couche.tar -t 127.0.0.1:15000/essai/image:v1 > /dev/null 2>&1
dig=$("$crane" digest --insecure 127.0.0.1:15000/essai/image:v1); img=127.0.0.1:15000/essai/image@$dig
echo "image jetable : $img"
export COSIGN_PASSWORD=essai-jetable
mkdir vsa autre && (cd vsa && "$cosign" generate-key-pair > /dev/null 2>&1) && (cd autre && "$cosign" generate-key-pair > /dev/null 2>&1)
"$cosign" signing-config create --out vide.json > /dev/null 2>&1
python3 -I - "$dig" <<'PY'
import json, sys
json.dump({"_type": "https://in-toto.io/Statement/v1",
           "subject": [{"name": "127.0.0.1:15000/essai/image", "digest": {"sha256": sys.argv[1].split(":")[1]}}],
           "predicateType": "https://slsa.dev/verification_summary/v1",
           "predicate": {"verifier": {"id": "https://supply-chain.example/verifiers/essai"}, "resourceUri": "essai",
                         "policy": {"uri": "essai"}, "verificationResult": "PASSED", "verifiedLevels": ["POC_ESSAI"]}},
          open("enonce.json", "w"))
PY
echo "## 1. cosign attest-blob --statement, sans registre (aucune référence d'image donnée)"
"$cosign" attest-blob --statement enonce.json --key vsa/cosign.key --signing-config vide.json --bundle vsa.bundle.json --yes 2>&1 | tail -3
echo "code de sortie : ${PIPESTATUS[0]}"
python3 -I - <<'PY'
import json, base64
b = json.load(open("vsa.bundle.json"))
print("mediaType du bundle :", b.get("mediaType"))
e = b["dsseEnvelope"]; s = json.loads(base64.b64decode(e["payload"]))
print("payloadType :", e["payloadType"], "; sujet :", s["subject"], "; énoncé identique à enonce.json :", s == json.load(open("enonce.json")))
print("tlog :", b["verificationMaterial"].get("tlogEntries"), "; horodatage :", b["verificationMaterial"].get("timestampVerificationData"))
PY
echo "## 2. poussé en referrer par oras attach (modèle de horodater.sh)"
"$oras" attach --plain-http --artifact-type application/vnd.dev.sigstore.bundle.v0.3+json \
  --annotation dev.sigstore.bundle.content=dsse-envelope --annotation dev.sigstore.bundle.predicateType=https://slsa.dev/verification_summary/v1 \
  "$img" vsa.bundle.json:application/vnd.dev.sigstore.bundle.v0.3+json 2>&1 | tail -2
curl -s "http://127.0.0.1:15000/v2/essai/image/referrers/$dig" | python3 -I -c 'import json,sys; print("referrers :", [(m.get("artifactType"), m["digest"][:19]) for m in json.load(sys.stdin)["manifests"]])'
echo "tags : $("$crane" ls --insecure 127.0.0.1:15000/essai/image | paste -sd' ')"
echo "## cosign verify-attestation sur l'image (clé de VSA)"
"$cosign" verify-attestation --key vsa/cosign.pub --insecure-ignore-tlog --type https://slsa.dev/verification_summary/v1 --allow-http-registry "$img" > v.out 2>&1
echo "code de sortie : $? ; $(grep -vE '^\{' v.out | tail -2 | paste -sd' ')"
echo "## cosign verify-attestation sur l'image (autre clé : refus attendu)"
"$cosign" verify-attestation --key autre/cosign.pub --insecure-ignore-tlog --type https://slsa.dev/verification_summary/v1 --allow-http-registry "$img" > v.out 2>&1
echo "code de sortie : $? ; $(grep -m1 '^Error' v.out | cut -c1-160)"
echo "## 3. cosign verify-blob-attestation --bundle (clé de VSA, puis autre clé)"
"$cosign" verify-blob-attestation --bundle vsa.bundle.json --new-bundle-format --key vsa/cosign.pub --insecure-ignore-tlog \
  --type https://slsa.dev/verification_summary/v1 --digest "${dig#sha256:}" --digestAlg sha256 > v.out 2>&1; echo "clé de VSA : code $? ; $(tail -1 v.out)"
"$cosign" verify-blob-attestation --bundle vsa.bundle.json --new-bundle-format --key autre/cosign.pub --insecure-ignore-tlog \
  --type https://slsa.dev/verification_summary/v1 --digest "${dig#sha256:}" --digestAlg sha256 > v.out 2>&1; echo "autre clé : code $? ; $(grep -m1 '^Error' v.out | cut -c1-160)"
kill $z
EOS
  cd / && rm -rf -- "${d:?}"
}

SECRETS=$O/secrets   # secrets du domaine sur l'hôte (compte poc-replay) ; la 08 ne reçoit que le hash

etape_compte_zot() { # D5 : mot de passe de poc-replay et ligne htpasswd bcrypt (coût 12), dans le dossier du domaine
  local h
  mkdir -p "$SECRETS" && chmod 0700 "$SECRETS"
  [ -s "$SECRETS/zot-poc-replay.password" ] || (umask 077 && openssl rand -hex 24 | tr -d '\n' > "$SECRETS/zot-poc-replay.password")
  h=$(mkpasswd -m bcrypt -R 12 -s < "$SECRETS/zot-poc-replay.password")
  case $h in '$2b$12$'*) echo "hash bcrypt de coût 12" ;; *) echo "KO   hash bcrypt inattendu" >&2; exit 1 ;; esac
  (umask 077 && printf 'poc-replay:%s\n' "$h" > "$SECRETS/zot-poc-replay.htpasswd")
  stat -c '%a %n' "$SECRETS"/zot-poc-replay.* | sed "s#$SECRETS/##"
}

etape_droits_zot() { # D5 : droits de poc-replay sur le Zot du PoC, sur un dépôt jetable (builds/essai-replay)
  local x=$W/droits a b img ref r
  rm -rf -- "${x:?}" && (umask 077 && mkdir -p "$x")
  trap 'rm -rf -- "$W/droits"' EXIT   # copie du mot de passe (auth.json) supprimée même en cas d'échec
  printf '{"auths":{"%s":{"auth":"%s"}}}' "$ZOT_POC" "$(printf 'poc-replay:%s' "$(cat "$SECRETS/zot-poc-replay.password")" | base64 -w0)" > "$x/auth.json"
  a=(--registry-config "$x/auth.json" --ca-file "$CA_POC")
  b=(--to-registry-config "$x/auth.json" --to-ca-file "$CA_POC")
  printf 'essai poc-replay %s\n' "$(date -u +%FT%TZ)" > "$x/f.txt"
  ( cd "$x" && oras push --oci-layout "$x/image:v" f.txt > /dev/null )   # image jetable en layout local
  img=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifests"][0]["digest"])' "$x/image/index.json")
  essai() { # libellé attendu(accepte|refus) commande… : résultat d'une écriture
    local l=$1 att=$2; shift 2
    if "$@" > "$x/sortie" 2>&1; then r=accepte; else r=refus; fi
    [ "$r" = "$att" ] && echo "OK   $l : $r" || echo "KO   $l : $r (attendu $att) : $(grep -m1 -iE 'error|denied|unauthor' "$x/sortie" | cut -c1-140)"
  }
  essai "push par digest dans builds/essai-replay" accepte oras cp "${b[@]}" --from-oci-layout "$x/image@$img" "$ZOT_POC/builds/essai-replay@$img"
  essai "push par tag dans builds/essai-replay" refus oras cp "${b[@]}" --from-oci-layout "$x/image@$img" "$ZOT_POC/builds/essai-replay:tag-interdit"
  essai "push par digest dans workspace/essai (hors de builds/**)" refus oras cp "${b[@]}" --from-oci-layout "$x/image@$img" "$ZOT_POC/workspace/essai@$img"
  printf '{"essai":"referrer poc-replay"}' > "$x/vsa.json"
  attacher() { (cd "$x" && oras attach "${a[@]}" --artifact-type application/vnd.dev.sigstore.bundle.v0.3+json "$ZOT_POC/builds/essai-replay@$img" vsa.json:application/vnd.dev.sigstore.bundle.v0.3+json); }   # chemin relatif : oras refuse les chemins absolus
  essai "referrer par oras attach sur builds/essai-replay" accepte attacher
  essai "suppression du manifeste" refus oras manifest delete "${a[@]}" --force "$ZOT_POC/builds/essai-replay@$img"
  ref=$(curl -s --cacert "$CA_POC" "https://$ZOT_POC/v2/builds/essai-replay/referrers/$img" | python3 -I -c 'import json,sys; print([(m.get("artifactType"), m["digest"][:19]) for m in json.load(sys.stdin)["manifests"]])')
  echo "referrers en lecture anonyme : $ref"
  echo "tags de builds/essai-replay : $(oras repo tags --ca-file "$CA_POC" "$ZOT_POC/builds/essai-replay" | paste -sd' ')"
  echo "builds/sample-app : $(oras manifest fetch --ca-file "$CA_POC" "$ZOT_POC/${IMAGE%@*}:$(echo "${IMAGE#*@}" | tr : -).att" | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)["layers"]))') enveloppes dans le tag .att"
  rm -rf -- "${x:?}"
}

lancer "${JALON:-r1}" "$@"
