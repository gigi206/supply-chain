#!/usr/bin/env bash
# Brique 08, jalon J2 : stockage sur sc-stockage (choix validés par le propriétaire le 29/10/2026).
#   pki        CA du PoC (ECDSA P-256, pathlen 0, contraintes de nom : pki.cnf) et un certificat par service ;
#              clés en 0600 dans ~/.cache/supply-chain-poc/08/secrets, certificats dans …/08/pki
#   zot        Zot 2.1.22, binaire de mise.toml revérifié dans la VM, service systemd durci, TLS ;
#              lecture anonyme, écriture par le seul compte poc-ecriture (htpasswd bcrypt), sans suppression
#   registre   push par digest de l'image sample-app de la brique 04 depuis l'hôte, relecture anonyme ;
#              refus attendus : push anonyme, mauvais mot de passe, suppression
#   containerd pull refusé sans la CA, puis CA et registries.yaml sur les trois nœuds (redémarrés un par un) ;
#              pull par digest dans un pod de sc-build, résolution de sc-stockage.poc.test depuis un pod
#   forgejo    git par apt (versions épinglées, accord du propriétaire du 29/10/2026), Forgejo 15.0.11 (binaire GPG de
#              mise.toml revérifié dans la VM) en service systemd durci, HTTPS, sqlite, sans SSH ni inscription ;
#              secrets générés dans la VM ; mot de passe et jeton de l'administrateur en 0600 sur l'hôte
#   depot      organisation workspace, dépôt workspace/sample-app (sources de poc/sample-app à HEAD, commit à
#              auteur et date fixes) ; push sans jeton refusé ; lecture depuis sc-build
# Aucun secret en argument de commande : fichiers 0600 ou entrée standard.
#
# Usage (racine du dépôt) : mise run confiance:stockage -- <étape>…   (journal : resultats/stockage-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
R=$here/resultats
O=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}
S=$O/secrets
P=$O/pki
W=$O/travail
ZOT_SHA=33b9b5bfe05d6788c076de951a01920477dbd6395c330146e23cc2340073e52e   # mise.lock, zot-linux-amd64 v2.1.22
APP_LAYOUT=${APP_LAYOUT:-$HOME/.cache/supply-chain-poc/w/b04/app-layout}   # image sample-app de la brique 04
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
REG_HOTE=192.168.161.13:5000          # depuis l'hôte (pas de résolution de poc.test) : SAN IP du certificat
REG=sc-stockage.poc.test:5000         # depuis les nœuds et les pods
DEPOT=workspace/sample-app
BUSYBOX=docker.io/rancher/mirrored-library-busybox:1.37.0   # images système de k3s (airgap vérifié en J1)
FORGEJO_SHA=17b59b5f8a8f968126b7a6fcc1d45d9531228dbf293f172cf5565d2e72e999a3   # mise.lock, forgejo-15.0.11-linux-amd64
FORGEJO_HOTE=https://192.168.161.13:3000   # depuis l'hôte
FORGEJO=https://sc-stockage.poc.test:3000
# git et ses dépendances (apt-get install -s --no-install-recommends du 29/10/2026), dépôts Debian signés.
GIT_PAQUETS="git=1:2.47.3-0+deb13u1 git-man=1:2.47.3-0+deb13u1 liberror-perl=0.17030-1 perl=5.40.1-6+deb13u1
  libperl5.40=5.40.1-6+deb13u1 perl-modules-5.40=5.40.1-6+deb13u1 libgdbm-compat4t64=1.24-2
  libcurl3t64-gnutls=8.14.1-2+deb13u7 libngtcp2-16=1.11.0-1+deb13u1 libngtcp2-crypto-gnutls8=1.11.0-1+deb13u1"
FG="runuser -u forgejo -- env HOME=/var/lib/forgejo USER=forgejo /usr/local/bin/forgejo -c /etc/forgejo/app.ini -w /var/lib/forgejo"
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
declare -A IP=([sc-confiance]=192.168.161.11 [sc-build]=192.168.161.12 [sc-stockage]=192.168.161.13)
SSH_OPTS=(-i "$O/ssh/id_ed25519" -o UserKnownHostsFile="$O/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
mkdir -p "$R" "$P" "$W"
(umask 077 && mkdir -p "$S")
trap 'rm -rf "$W/zot" "$W/registre" "$W/forgejo" "$W/depot" "$W/refus.out"' EXIT   # copies de secrets, même en cas d'échec
chrono() { printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }
sur() { local vm=$1; shift; ssh "${SSH_OPTS[@]}" "poc@${IP[$vm]}" "$@"; }
copier() { # vm répertoire-distant fichiers…
  local vm=$1 d=$2; shift 2
  sur "$vm" "rm -rf $d && mkdir -m 0700 $d"
  scp -q "${SSH_OPTS[@]}" "$@" "poc@${IP[$vm]}:$d/"
}
refus() { # libellé motif commande… : la commande doit échouer, avec le motif dans sa sortie
  local l=$1 m=$2; shift 2
  if "$@" > "$W/refus.out" 2>&1; then echo "KO   $l : accepté" >&2; exit 1; fi
  if grep -qiE "$m" "$W/refus.out"; then
    echo "OK   $l : refusé ($(grep -oiE "$m" "$W/refus.out" | head -1))"
  else
    echo "KO   $l : refusé pour une autre raison" >&2; cat "$W/refus.out" >&2; exit 1
  fi
}

certificat() { # nom SAN
  local n=$1 cn=${2%%,*}
  if [ -s "$S/$n.key" ] && [ -s "$P/$n.crt" ]; then echo "$n : certificat existant"; else
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/$n.key")
    SAN=$2 openssl req -new -config "$here/stockage/pki.cnf" -key "$S/$n.key" -subj "/O=supply-chain PoC/CN=${cn#DNS:}" -out "$W/$n.csr"
    SAN=$2 openssl x509 -req -in "$W/$n.csr" -CA "$P/ca-poc.crt" -CAkey "$S/ca-poc.key" -set_serial "0x$(openssl rand -hex 16)" \
      -days 180 -sha256 -extfile "$here/stockage/pki.cnf" -extensions serveur_poc -out "$P/$n.crt" 2>/dev/null
    rm -f "$W/$n.csr"
  fi
  openssl verify -CAfile "$P/ca-poc.crt" -purpose sslserver "$P/$n.crt"
  openssl x509 -in "$P/$n.crt" -noout -subject -enddate -ext subjectAltName | paste -sd' ' | sed 's/  */ /g'
}

etape_pki() {
  if [ ! -s "$S/ca-poc.key" ]; then
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/ca-poc.key")
    SAN= openssl req -x509 -new -config "$here/stockage/pki.cnf" -extensions ca_poc -key "$S/ca-poc.key" -sha256 -days 365 \
      -subj "/O=supply-chain PoC/CN=CA du PoC (brique 08)" -out "$P/ca-poc.crt"
  fi
  openssl x509 -in "$P/ca-poc.crt" -noout -subject -enddate -fingerprint -sha256
  openssl x509 -in "$P/ca-poc.crt" -noout -ext basicConstraints,keyUsage,nameConstraints
  certificat zot DNS:sc-stockage.poc.test,IP:192.168.161.13
  certificat forgejo DNS:sc-stockage.poc.test,IP:192.168.161.13
  # Contrôle des contraintes de nom : un certificat hors du PoC, signé par la CA, est refusé à la vérification.
  (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$W/hors-poc.key")
  SAN=DNS:registre.exemple.org openssl req -new -config "$here/stockage/pki.cnf" -key "$W/hors-poc.key" -subj "/CN=registre.exemple.org" -out "$W/hors-poc.csr"
  SAN=DNS:registre.exemple.org openssl x509 -req -in "$W/hors-poc.csr" -CA "$P/ca-poc.crt" -CAkey "$S/ca-poc.key" -set_serial 1 \
    -days 1 -extfile "$here/stockage/pki.cnf" -extensions serveur_poc -out "$W/hors-poc.crt" 2>/dev/null
  refus "certificat registre.exemple.org signé par la CA" "permitted subtree violation" \
    openssl verify -CAfile "$P/ca-poc.crt" -purpose sslserver "$W/hors-poc.crt"
  rm -f "$W"/hors-poc.*
  ls -l "$S" "$P" | sed "s#$HOME#~#g"
}

etape_zot() {
  local z d=$W/zot h
  z=$(type -P zot)
  echo "$ZOT_SHA  $z" | sha256sum -c | sed "s#$HOME#~#g"
  [ -s "$S/zot-poc-ecriture.password" ] || (umask 077 && openssl rand -hex 24 | tr -d '\n' > "$S/zot-poc-ecriture.password")
  h=$(mkpasswd -m bcrypt -R 12 -s < "$S/zot-poc-ecriture.password")
  case $h in '$2b$12$'*) echo "htpasswd : bcrypt, coût 12" ;; *) echo "hash bcrypt inattendu" >&2; exit 1 ;; esac
  rm -rf "$d" && (umask 077 && mkdir -p "$d" && printf 'poc-ecriture:%s\n' "$h" > "$d/htpasswd")
  cp "$z" "$here/stockage/zot.json" "$here/stockage/zot.service" "$P/zot.crt" "$S/zot.key" "$d/"
  copier sc-stockage /tmp/zot-installation "$d"/*
  sur sc-stockage sudo bash -s <<EOF
set -euo pipefail
cd /tmp/zot-installation
echo "$ZOT_SHA  zot" | sha256sum -c
id zot >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/zot --no-create-home --shell /usr/sbin/nologin zot
install -m 0755 zot /usr/local/bin/zot
install -d -m 0750 -g zot /etc/zot /etc/zot/tls
install -m 0640 -g zot zot.json /etc/zot/config.json
install -m 0640 -g zot htpasswd /etc/zot/htpasswd
install -m 0644 zot.crt /etc/zot/tls/zot.crt
install -m 0640 -g zot zot.key /etc/zot/tls/zot.key
install -m 0644 zot.service /etc/systemd/system/zot.service
systemctl daemon-reload
systemctl enable zot 2>&1
systemctl restart zot
cd / && rm -rf /tmp/zot-installation
EOF
  rm -rf "$d"
  local code=000
  for _ in $(seq 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/" || true)
    [ "$code" = 000 ] || break
    sleep 1
  done
  echo "https://$REG_HOTE/v2/ (CA du PoC) : HTTP $code"
  sur sc-stockage "systemctl is-active zot; /usr/local/bin/zot --version 2>&1 | head -3; sudo ss -ltnp | grep ':5000 '; ls -ld /var/lib/zot /var/log/zot /etc/zot; sudo ls -l /etc/zot /etc/zot/tls"
  sur sc-stockage "systemd-analyze security zot 2>/dev/null | tail -1"
}

etape_registre() {
  local A=$W/registre debut
  rm -rf "$A" && (umask 077 && mkdir -p "$A")
  debut=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'")
  # Fichiers d'authentification (format docker) : bon compte, mauvais mot de passe, aucun compte.
  (umask 077
   printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" "$(printf 'poc-ecriture:%s' "$(cat "$S/zot-poc-ecriture.password")" | base64 -w0)" > "$A/ecriture.json"
   printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" "$(printf 'poc-ecriture:%s' "$(openssl rand -hex 24)" | base64 -w0)" > "$A/faux.json"
   echo '{}' > "$A/anonyme.json")
  local src="$APP_LAYOUT@$APP_DIGEST" ca=(--to-ca-file "$P/ca-poc.crt")
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/workspace/essai/blobs/uploads/")
  [ "$code" = 401 ] && echo "OK   ouverture d'un envoi de blob sans identifiants : HTTP $code" || { echo "KO   envoi anonyme : HTTP $code" >&2; exit 1; }
  refus "push anonyme" "401|unauthorized|basic credential not found" oras cp --from-oci-layout "$src" "$REG_HOTE/workspace/essai@$APP_DIGEST" "${ca[@]}" --to-registry-config "$A/anonyme.json"
  refus "push avec un mauvais mot de passe" "401|unauthorized" oras cp --from-oci-layout "$src" "$REG_HOTE/workspace/essai@$APP_DIGEST" "${ca[@]}" --to-registry-config "$A/faux.json"
  oras cp --from-oci-layout "$src" "$REG_HOTE/$DEPOT@$APP_DIGEST" "${ca[@]}" --to-registry-config "$A/ecriture.json"
  echo "OK   push par digest : $REG_HOTE/$DEPOT@$APP_DIGEST (compte poc-ecriture)"
  local lu
  lu=$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" --registry-config "$A/anonyme.json" "$REG_HOTE/$DEPOT@$APP_DIGEST" | jq -r .digest)
  [ "$lu" = "$APP_DIGEST" ] && echo "OK   relecture anonyme du manifeste : $lu" || { echo "KO   relecture : $lu" >&2; exit 1; }
  rm -rf "$A/retour"
  oras cp --to-oci-layout "$REG_HOTE/$DEPOT@$APP_DIGEST" "$A/retour@$APP_DIGEST" --from-ca-file "$P/ca-poc.crt" --from-registry-config "$A/anonyme.json" >/dev/null
  if diff -r "$APP_LAYOUT/blobs" "$A/retour/blobs" >/dev/null; then echo "OK   pull anonyme par digest : blobs identiques à ceux de la brique 04"; else echo "KO   blobs différents" >&2; exit 1; fi
  refus "suppression du manifeste par poc-ecriture" "403|forbidden|denied" \
    oras manifest delete --force --ca-file "$P/ca-poc.crt" --registry-config "$A/ecriture.json" "$REG_HOTE/$DEPOT@$APP_DIGEST"
  refus "lecture sans la CA du PoC" "x509|certificate" oras manifest fetch --registry-config "$A/anonyme.json" "$REG_HOTE/$DEPOT@$APP_DIGEST"
  lu=$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" --registry-config "$A/anonyme.json" "$REG_HOTE/$DEPOT@$APP_DIGEST" | jq -r .digest)
  echo "manifeste toujours présent après la tentative de suppression : $lu"
  echo "## journal d'audit de Zot (écritures acceptées)"
  sur sc-stockage "sudo tail -n 5 /var/log/zot/audit.log" | jq -c '{time, subject, action, object, status}'
  echo "## journal de Zot : refus de cet essai (hors défis 401 sans identifiants, qui précèdent chaque requête authentifiée)"
  sur sc-stockage "sudo journalctl -u zot --since '$debut' -o cat" > "$A/journal"
  jq -cR 'fromjson? | select(.statusCode == 403 or (.statusCode == 401 and .headers.Authorization))
    | {time, username, method, path, statusCode, authorization: .headers.Authorization[0]}' "$A/journal"
  echo "défis 401 sans identifiants : $(jq -R 'fromjson? | select(.statusCode == 401 and (.headers.Authorization | not))' "$A/journal" | grep -c '"statusCode"' || true)"
  rm -rf "$A"
}

etape_containerd() {
  refus "pull sur sc-build sans la CA du PoC" "x509|certificate signed by unknown authority" \
    sur sc-build "sudo k3s crictl pull $REG/$DEPOT@$APP_DIGEST"
  local vm unite
  for vm in sc-stockage sc-build sc-confiance; do
    if [ "$vm" = sc-confiance ]; then unite=k3s; else unite=k3s-agent; fi
    copier "$vm" /tmp/registre-installation "$here/stockage/registries.yaml" "$P/ca-poc.crt"
    sur "$vm" sudo bash -s <<EOF
set -euo pipefail
install -m 0644 /tmp/registre-installation/ca-poc.crt /etc/rancher/k3s/ca-poc.crt
install -m 0600 /tmp/registre-installation/registries.yaml /etc/rancher/k3s/registries.yaml
rm -rf /tmp/registre-installation
systemctl restart $unite
EOF
    local ok=0
    for _ in $(seq 60); do
      if kubectl get node "$vm" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -x True >/dev/null; then ok=1; break; fi
      sleep 2
    done
    [ "$ok" = 1 ] || { echo "KO   $vm pas Ready après redémarrage" >&2; exit 1; }
    echo "$vm : $unite redémarré, nœud Ready ; $(sur "$vm" "sudo cat /var/lib/rancher/k3s/agent/etc/containerd/certs.d/$REG/hosts.toml" | grep -E 'ca|server' | paste -sd' ')"
  done
  kubectl get ns j2-essais >/dev/null 2>&1 || kubectl create ns j2-essais
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: {name: sample-app, namespace: j2-essais}
spec:
  nodeSelector: {zone: build}
  tolerations: [{key: zone, operator: Equal, value: build, effect: NoSchedule}]
  automountServiceAccountToken: false
  containers:
  - name: app
    image: $REG/$DEPOT@$APP_DIGEST
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
---
apiVersion: v1
kind: Pod
metadata: {name: dns, namespace: j2-essais}
spec:
  nodeSelector: {zone: build}
  tolerations: [{key: zone, operator: Equal, value: build, effect: NoSchedule}]
  automountServiceAccountToken: false
  restartPolicy: Never
  containers:
  - name: dns
    image: $BUSYBOX
    imagePullPolicy: Never
    command: [nslookup, sc-stockage.poc.test]
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
EOF
  kubectl wait -n j2-essais --for=condition=Ready pod/sample-app --timeout=120s
  kubectl wait -n j2-essais --for=jsonpath='{.status.phase}'=Succeeded pod/dns --timeout=60s
  kubectl get pods -n j2-essais -o wide
  local id
  id=$(kubectl get pod -n j2-essais sample-app -o jsonpath='{.status.containerStatuses[0].imageID}')
  [ "$id" = "$REG/$DEPOT@$APP_DIGEST" ] && echo "OK   pull par digest dans un pod de sc-build : $id" || { echo "KO   imageID $id" >&2; exit 1; }
  kubectl get events -n j2-essais --field-selector involvedObject.name=sample-app -o custom-columns=RAISON:.reason,MESSAGE:.message --no-headers
  echo "## résolution depuis un pod de sc-build"
  kubectl logs -n j2-essais dns
  kubectl logs -n j2-essais dns | grep '192.168.161.13' >/dev/null && echo "OK   sc-stockage.poc.test résolu depuis un pod (CoreDNS)" || { echo "KO   résolution" >&2; exit 1; }
  kubectl delete ns j2-essais --wait=false
}

etape_forgejo() {
  local f d=$W/forgejo
  f=$(type -P forgejo)
  echo "$FORGEJO_SHA  $f" | sha256sum -c | sed "s#$HOME#~#g"
  rm -rf "$d" && (umask 077 && mkdir -p "$d")
  cp "$f" "$here/stockage/forgejo.ini" "$here/stockage/forgejo.service" "$P/forgejo.crt" "$S/forgejo.key" "$d/"
  copier sc-stockage /tmp/forgejo-installation "$d"/*
  rm -rf "$d"
  sur sc-stockage sudo bash -s <<EOF
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -q --no-install-recommends $(echo $GIT_PAQUETS) > /var/log/apt-git-j2.log 2>&1 || { tail -20 /var/log/apt-git-j2.log; exit 1; }
grep -E '^(Get|Setting up)' /var/log/apt-git-j2.log || true
dpkg-query -W -f='\${Package} \${Version}\n' git perl | paste -sd' '
git --version
cd /tmp/forgejo-installation
echo "$FORGEJO_SHA  forgejo" | sha256sum -c
id forgejo >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/forgejo --no-create-home --shell /usr/sbin/nologin forgejo
install -m 0755 forgejo /usr/local/bin/forgejo
install -d -m 0750 -g forgejo /etc/forgejo /etc/forgejo/tls /etc/forgejo/secrets
install -d -m 0750 -o forgejo -g forgejo /var/lib/forgejo
install -m 0640 -g forgejo forgejo.ini /etc/forgejo/app.ini
install -m 0644 forgejo.crt /etc/forgejo/tls/forgejo.crt
install -m 0640 -g forgejo forgejo.key /etc/forgejo/tls/forgejo.key
for s in SECRET_KEY INTERNAL_TOKEN JWT_SECRET; do
  n=/etc/forgejo/secrets/\${s,,}
  if [ ! -s "\$n" ]; then (umask 027 && /usr/local/bin/forgejo generate secret "\$s" > "\$n" && chgrp forgejo "\$n"); echo "secret \$s généré"; fi
done
install -m 0644 forgejo.service /etc/systemd/system/forgejo.service
cd / && rm -rf /tmp/forgejo-installation
$FG migrate > /var/log/forgejo-migrate.log 2>&1 || { tail -20 /var/log/forgejo-migrate.log; exit 1; }
systemctl daemon-reload
systemctl enable forgejo 2>&1
EOF
  # État lu dans la VM : un Forgejo recréé n'a plus l'administrateur ni le jeton des fichiers de l'hôte.
  if sur sc-stockage "sudo $FG admin user list --admin 2>/dev/null" | awk 'NR > 1 {print $2}' | grep -x poc-admin >/dev/null; then
    echo "administrateur poc-admin existant"
  else
    rm -f "$S/forgejo-admin.token"
    (umask 077 && sur sc-stockage "sudo $FG admin user create --admin --username poc-admin --email poc-admin@poc.test --random-password --random-password-length 32 --must-change-password=false 2>/dev/null" \
      | sed -n "s/^generated random password is '\(.*\)'$/\1/p" > "$S/forgejo-admin.password")
    [ -s "$S/forgejo-admin.password" ] || { echo "KO   mot de passe administrateur non relevé" >&2; exit 1; }
    echo "administrateur poc-admin créé, mot de passe en 0600 sur l'hôte"
  fi
  if [ ! -s "$S/forgejo-admin.token" ]; then
    (umask 077 && sur sc-stockage "sudo $FG admin user generate-access-token --username poc-admin --token-name j2-depots-$(date -u +%Y%m%dT%H%M%SZ) --scopes write:organization,write:repository --raw 2>/dev/null" > "$S/forgejo-admin.token")
    [ -s "$S/forgejo-admin.token" ] || { echo "KO   jeton non relevé" >&2; exit 1; }
    echo "jeton j2-depots (write:organization, write:repository) en 0600 sur l'hôte"
  fi
  sur sc-stockage "sudo systemctl restart forgejo"
  local code=000
  for _ in $(seq 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$P/ca-poc.crt" "$FORGEJO_HOTE/api/healthz" || true)
    [ "$code" = 200 ] && break
    sleep 1
  done
  echo "$FORGEJO_HOTE/api/healthz (CA du PoC) : HTTP $code ; version $(curl -fsS --cacert "$P/ca-poc.crt" "$FORGEJO_HOTE/api/v1/version" | jq -r .version)"
  [ "$code" = 200 ] || { sur sc-stockage "sudo journalctl -u forgejo -n 30 -o cat" >&2; exit 1; }
  sur sc-stockage "systemctl is-active forgejo; sudo ss -ltnp | grep ':3000 '; sudo ls -l /etc/forgejo /etc/forgejo/tls /etc/forgejo/secrets; ls -ld /var/lib/forgejo"
  [ "$(sur sc-stockage "sudo sha256sum /etc/forgejo/app.ini" | cut -d' ' -f1)" = "$(sha256sum "$here/stockage/forgejo.ini" | cut -d' ' -f1)" ] \
    && echo "OK   app.ini inchangé par Forgejo (identique à stockage/forgejo.ini, sans secret)" || { echo "KO   app.ini modifié" >&2; exit 1; }
  curl -fsS --cacert "$P/ca-poc.crt" "$FORGEJO_HOTE/user/sign_up" | grep 'Registration is disabled' >/dev/null \
    && echo "OK   inscription désactivée (/user/sign_up : « Registration is disabled »)" || { echo "KO   inscription ouverte" >&2; exit 1; }
  sur sc-stockage "systemd-analyze security forgejo 2>/dev/null | tail -1"
}

etape_depot() {
  local A=$W/depot code debut
  rm -rf "$A" && (umask 077 && mkdir -p "$A" && printf 'Authorization: token %s\n' "$(cat "$S/forgejo-admin.token")" > "$A/entete")
  debut=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'")
  api() { curl -fsS --cacert "$P/ca-poc.crt" -H @"$A/entete" -H 'Content-Type: application/json' "$@"; }
  code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$P/ca-poc.crt" -X POST -H 'Content-Type: application/json' -d '{"username": "essai"}' "$FORGEJO_HOTE/api/v1/orgs")
  [ "$code" = 401 ] && echo "OK   création d'organisation sans jeton : HTTP $code" || { echo "KO   création anonyme : HTTP $code" >&2; exit 1; }
  api "$FORGEJO_HOTE/api/v1/orgs/workspace" >/dev/null 2>&1 \
    || api -X POST "$FORGEJO_HOTE/api/v1/orgs" -d '{"username": "workspace", "visibility": "public"}' >/dev/null
  api "$FORGEJO_HOTE/api/v1/repos/$DEPOT" >/dev/null 2>&1 \
    || api -X POST "$FORGEJO_HOTE/api/v1/orgs/workspace/repos" -d '{"name": "sample-app", "default_branch": "main", "private": false}' >/dev/null
  git -C "$repo" archive HEAD poc/sample-app | tar -x -C "$A" --strip-components=1
  # Dépôt isolé de la configuration git de l'utilisateur (signature, identité, assistants d'identifiants).
  (export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
   export GIT_AUTHOR_NAME="PoC brique 08" GIT_AUTHOR_EMAIL=poc-admin@poc.test GIT_AUTHOR_DATE=2026-10-29T00:00:00Z
   export GIT_COMMITTER_NAME="PoC brique 08" GIT_COMMITTER_EMAIL=poc-admin@poc.test GIT_COMMITTER_DATE=2026-10-29T00:00:00Z
   cd "$A/sample-app"
   git init -q -b main && git add -A && git commit -qm "sample-app (brique 08, J2)"
   refus "push sans jeton" "401|Authentication failed|could not read Username" \
     env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" git push -q "$FORGEJO_HOTE/$DEPOT.git" main
   GIT_CONFIG_VALUE_0=$(cat "$A/entete")
   export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1=http.sslCAInfo GIT_CONFIG_VALUE_1="$P/ca-poc.crt"
   git push -q "$FORGEJO_HOTE/$DEPOT.git" main)
  local commit arbre distant
  commit=$(git -C "$A/sample-app" rev-parse HEAD)
  arbre=$(git -C "$A/sample-app" rev-parse 'HEAD^{tree}')
  [ "$arbre" = "$(git -C "$repo" rev-parse HEAD:poc/sample-app)" ] && echo "OK   arbre $arbre = poc/sample-app à HEAD ($(git -C "$repo" rev-parse --short HEAD))" || { echo "KO   arbre différent" >&2; exit 1; }
  distant=$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    git ls-remote "$FORGEJO_HOTE/$DEPOT.git" refs/heads/main | cut -f1)
  [ "$distant" = "$commit" ] && echo "OK   $FORGEJO/$DEPOT : main = $commit (lecture anonyme)" || { echo "KO   main distant $distant ≠ $commit" >&2; exit 1; }
  echo "## journal de Forgejo (requêtes de cet essai)"
  sur sc-stockage "sudo journalctl -u forgejo --since '$debut' -o cat" | grep -E 'completed (POST|GET) /(api/v1/orgs|workspace/sample-app.git/(info/refs\?service=git-receive-pack|git-receive-pack))' \
    | sed 's/ for 192.168.161.1:[0-9]*,/,/; s/ in [0-9.]*ms @.*//'
  echo "## depuis sc-build (CA déclarée aux nœuds, résolution par le DNS du réseau)"
  # Forgejo enregistre la branche de façon asynchrone après le premier push (404 pendant quelques secondes).
  local b="" n
  for n in $(seq 30); do
    b=$(sur sc-build "sudo curl -fsS --cacert /etc/rancher/k3s/ca-poc.crt $FORGEJO/api/v1/repos/$DEPOT/branches/main" 2>/dev/null) && break
    sleep 1
  done
  [ -n "$b" ] || { echo "KO   branche main illisible depuis sc-build" >&2; exit 1; }
  echo "branche lue au bout de $n essai(s)"
  jq -c '{branche: .name, commit: .commit.id, auteur: .commit.author.name, date: .commit.timestamp}' <<<"$b"
  [ "$(jq -r .commit.id <<<"$b")" = "$commit" ] && echo "OK   même commit vu depuis la zone build" || { echo "KO   commit différent depuis sc-build" >&2; exit 1; }
  rm -rf "$A"
}

[ $# -gt 0 ] || { echo "usage : $0 pki|zot|registre|containerd|forgejo|depot…" >&2; exit 2; }
for e in "$@"; do
  declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }
done
for e in "$@"; do
  chrono "J2 $e"
  { echo "# stockage.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | tee "$R/stockage-$e.log"
  chrono "J2 $e fait"
done
