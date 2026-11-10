#!/usr/bin/env bash
# Brique 06, jalon S1 : sbuild en mode unshare dans un pod Kata (risque principal : newuidmap, setuid root, sur la racine
# virtio-fs de l'invité). Prédictions : resultats/s1-predictions.md, écrites et commitées avant toute exécution.
#   prealables  lecture seule et dry-run : exemption Pod Security de la RuntimeClass kata lue par kube-apiserver ; chaque spec
#               de pod admise en dry-run serveur (un refus d'admission n'est pas un échec d'exécution) ; mémoire allouable de
#               sc-build ; sources de sample-app (SHA256SUMS de packaging:sources) ; InRelease de l'instantané vérifié sur
#               l'hôte par gpgv avec les clés de ftp-master (indépendantes de l'image), signataires comparés aux empreintes
#               épinglées ; Packages.xz contrôlé par InRelease, versions épinglées présentes
#   amorce      copie par digest de debian:trixie-20261104-slim (amd64) dans Zot, amont/library/debian (D4 a : amorce seule)
#   racine      pod Kata privilégié, root, image d'amorce : apt sur l'instantané (InRelease comparé à celui de l'hôte), mmdebstrap
#               épinglé ; deux archives par mmdebstrap --mode=root : racine du constructeur (minbase, sbuild, mmdebstrap, uidmap
#               épinglés, compte constructeur 1000, plages subuid et subgid) et chroot de sbuild (buildd, dépendances de build
#               de sample-app préinstallées : ce n'est pas la fermeture D2 a, prévue en S2) ; sha256 de chaque .deb comparé sur
#               l'hôte au Packages vérifié ; archives rapatriées par kubectl exec, sha256 comparé
#   image       image d'essai assemblée sans rien exécuter (crane append) : racine de mmdebstrap, puis le chroot sous
#               /opt/sbuild ; poussée dans Zot sous essais-06/sbuild-debian13 (builders/ attend S2, image reproductible)
#   essais      même sonde dans trois pods, UID 1000 : Kata privilégié (D1 a), Kata non privilégié avec allowPrivilegeEscalation
#               (D1 b), runc en restricted (témoin négatif) ; montages de / et de /w, NoNewPrivs, CapBnd, mode de newuidmap et
#               newgidmap, /etc/subuid ; puis newuidmap par unshare --map-auto ; puis, s'il passe, sbuild --chroot-mode=unshare
#               sur le paquet source de sample-app, sans réseau ni mise à jour d'apt ; sha256 du deb
# Les replis du README (tmpfs, root sans unshare, --xattr) ne sont pas lancés ici : chacun demande sa prédiction et un accord.
# Retrait : Zot n'autorise pas la suppression ; dépôts amont/library/debian et essais-06/sbuild-debian13 définitifs.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s1.sh <étape>…   (journal : resultats/s1-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
SNAP=20261105T000000Z
MIROIR=http://snapshot.debian.org/archive/debian/$SNAP   # http : l'amorce n'a pas de certificats ; intégrité par InRelease
SOURCE_LISTE="deb [check-valid-until=no] $MIROIR trixie main"
CLES="B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8 04B54C3CDCA79751B16BC6B5225629DF75B188BD 41587F7DB8C774BCCF131416762F67A0B2C39DE4"
#     archive 12/bookworm, archive 13/trixie, release 13/trixie (https://ftp-master.debian.org/keys.html, lu le 10/11/2026)
V_SBUILD=0.89.3+deb13u4
V_MMDEBSTRAP=1.5.7-1+deb13u1
V_UIDMAP=1:4.17.4-2
V_IPROUTE2=6.15.0-1   # « Recommends » de sbuild, absent au premier passage : sbuild-usernsexec lance ip link set lo up
PREFIXE=${PREFIXE:-s1}   # s1b : second passage (iproute2), journaux à part
GARDER_CHROOT=${GARDER_CHROOT:-0}   # 1 : chroot de sbuild du premier passage réutilisé, pas reconstruit
AMORCE_DIGEST=sha256:7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392   # trixie-20261104-slim, amd64 (audit du 05/11)
AMORCE=$REG/amont/library/debian@$AMORCE_DIGEST
DEPOT_ESSAI=essais-06/sbuild-debian13
PKG=${PACKAGING_DIR:-$HOME/.cache/supply-chain-poc/packaging}
DSC=sample-app_1.0.0-1.dsc
LIMITES='{"cpu": "2", "memory": "6Gi"}'      # demandes = limites ; tmpfs /w compté dans la mémoire du pod
TMPFS=4Gi
PRIVILEGIE='{"privileged": true, "allowPrivilegeEscalation": true}'
ESCALADE='{"allowPrivilegeEscalation": true}'
RESTREINT='{"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}}'
T=$W/s1-06
mkdir -p "$T"
umask 022

zot() { DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt "$@"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
champ() { sed -n "s/^$2[[:space:]]*:[[:space:]]*//p" "$T/$1.log" | head -1; }   # journal libellé : valeur

pod_spec() { # nom runtimeClass|- image uid contexte-JSON : pod de builds qui attend, tmpfs /w, limites, zone build
  jq -n --arg n "$1" --arg rc "$2" --arg i "$3" --argjson u "$4" --argjson sc "$5" --argjson l "$LIMITES" --arg t "$TMPFS" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds"},
    spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: ($u != 0), runAsUser: $u, runAsGroup: $u, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: $t}}],
      containers: [{name: "s1", image: $i, command: ["sleep", "7200"], securityContext: $sc,
        resources: {requests: $l, limits: $l}, volumeMounts: [{name: "w", mountPath: "/w"}]}]}
      + (if $rc == "-" then {} else {runtimeClassName: $rc} end))}' > "$T/$1.json"
}

pod_demarrer() { # nom : pod de $T/<nom>.json créé et prêt
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true </dev/null >/dev/null
  kubectl create -f "$T/$1.json" </dev/null >/dev/null
  kubectl wait -n builds "pod/$1" --for=condition=Ready --timeout=300s </dev/null >/dev/null \
    || { kubectl describe pod -n builds "$1" </dev/null | tail -n 20 >&2; echo "KO   pod $1 non prêt" >&2; exit 1; }
  echo "### $1 ($(jq -r '"runtimeClassName \(.spec.runtimeClassName // "-"), uid \(.spec.securityContext.runAsUser), contexte \(.spec.containers[0].securityContext | tostring)"' "$T/$1.json")) : prêt"
}

dans() { # nom libellé : script sh sur l'entrée standard, exécuté dans le pod ; sortie dans $T/<libellé>.log, puis affichée
  local rc=0
  kubectl exec -i -n builds "$1" -- sh -s > "$T/$2.log" 2>&1 || rc=$?
  sed 's/^/     /' "$T/$2.log"
  echo "     (code de l'exec : $rc)"
}

pod_retirer() { kubectl delete pod -n builds "$1" --wait=false </dev/null >/dev/null; echo "pod $1 supprimé"; }

etape_prealables() {
  local d s n
  echo "## exemption Pod Security de la RuntimeClass kata"
  args_apiserver | grep -x -- "--admission-control-config-file=$D_CONF/pod-security.yaml" >/dev/null \
    && echo "OK   kube-apiserver lit $D_CONF/pod-security.yaml" || { echo "KO   exemption de kata absente" >&2; exit 1; }
  echo "## admission en dry-run serveur (image d'amorce pour les quatre specs : les règles ne lisent que la forme de la référence)"
  pod_spec s1-racine kata "$AMORCE" 0 "$PRIVILEGIE"
  pod_spec s1-kata-privilegie kata "$AMORCE" 1000 "$PRIVILEGIE"
  pod_spec s1-kata-escalade kata "$AMORCE" 1000 "$ESCALADE"
  pod_spec s1-runc-restreint - "$AMORCE" 1000 "$RESTREINT"
  for n in s1-racine s1-kata-privilegie s1-kata-escalade s1-runc-restreint; do
    if kubectl create --dry-run=server -f "$T/$n.json" </dev/null > "$T/admis.out" 2>&1; then echo "OK   $n : admis"
    else echo "KO   $n : refusé à l'admission" >&2; cat "$T/admis.out" >&2; exit 1; fi
  done
  echo "## sc-build"
  kubectl get node sc-build -o json </dev/null | jq -r '"allouable : \(.status.allocatable.cpu) CPU, \(.status.allocatable.memory)"'
  kubectl get pods -A --field-selector spec.nodeName=sc-build,status.phase=Running -o json </dev/null \
    | jq -r '[.items[].spec.containers[].resources.requests.memory // empty] | "demandes de mémoire en cours : \(length) conteneur(s) : \(join(" "))"'
  echo "## place libre pour Zot (images d'essai : environ 1,5 Go prévus)"
  sur sc-stockage 'df -B1M --output=avail,target /var/lib/zot | tail -n 1' </dev/null | awk '{print "libre sous " $2 " : " $1 " Mo"}'
  echo "## sources de sample-app"
  (cd "$PKG" && sha256sum -c SHA256SUMS)
  echo "## instantané $SNAP, vérifié sur l'hôte"
  d=$T/hote; rm -rf "$d"; mkdir -p "$d"
  for n in archive-key-12 archive-key-13 release-13; do
    curl -fsS --max-time 60 -o "$d/$n.asc" "https://ftp-master.debian.org/keys/$n.asc"
    gpg --no-default-keyring --keyring "$d/cles.gpg" --batch --quiet --import "$d/$n.asc" 2>/dev/null
  done
  curl -fsSL --max-time 60 -o "$d/InRelease" "$MIROIR/dists/trixie/InRelease"
  s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/InRelease" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' | sort | paste -sd' ')
  attendu "signataires d'InRelease (clés primaires)" "$s" "$(tr ' ' '\n' <<<"$CLES" | sort | paste -sd' ')"
  echo "InRelease : sha256 $(sha256sum < "$d/InRelease" | cut -c1-64), $(sed -n 's/^Date: //p' "$d/InRelease")"
  sha256sum < "$d/InRelease" | cut -c1-64 > "$T/inrelease.sha256"
  s=$(awk '/^SHA256:/ {f = 1; next} /^[A-Z]/ {f = 0} f && $3 == "main/binary-amd64/Packages.xz" {print $1}' "$d/InRelease")
  curl -fsSL --max-time 120 -o "$d/Packages.xz" "$MIROIR/dists/trixie/main/binary-amd64/Packages.xz"
  attendu "Packages.xz contrôlé par InRelease" "$(sha256sum < "$d/Packages.xz" | cut -c1-64)" "$s"
  xz -dc "$d/Packages.xz" > "$T/Packages"
  for n in "sbuild $V_SBUILD" "libsbuild-perl $V_SBUILD" "mmdebstrap $V_MMDEBSTRAP" "uidmap $V_UIDMAP"; do
    set -- $n
    attendu "version de $1 dans l'instantané" "$(awk -v p="$1" '$1 == "Package:" {q = ($2 == p)} q && $1 == "Version:" {print $2}' "$T/Packages" | paste -sd' ')" "$2"
  done
}

etape_amorce() {
  auth_zot "$T/zot.json"
  mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"
  miroir "docker.io/library/debian@$AMORCE_DIGEST" amont/library/debian "$T/zot.json"
  attendu "digest de l'amorce dans Zot" "$(zot crane digest "$REG_HOTE/amont/library/debian@$AMORCE_DIGEST")" "$AMORCE_DIGEST"
}

# Script de l'amorce (root). La configuration docker-clean de l'image efface les .deb : retirée pour garder leurs empreintes.
RACINE='set -u
echo "invité : $(uname -r), $(nproc) vCPU, $(awk "/MemTotal/ {print \$2}" /proc/meminfo) kB ; /w : $(awk "\$2 == \"/w\" {print \$3}" /proc/mounts)"
rm -f /etc/apt/sources.list.d/* /etc/apt/apt.conf.d/docker-clean
echo "@SOURCE@" > /etc/apt/sources.list
t=$(date +%s)
apt-get -q -o Acquire::Retries=2 update > /w/update.log 2>&1; echo "apt-get update : rc $? en $(($(date +%s) - t)) s, $(grep -c -E "^(Get|Atteint|Hit)" /w/update.log) ligne(s) Get"
echo "InRelease : sha256 $(sha256sum /var/lib/apt/lists/*_InRelease | cut -c1-64)"
t=$(date +%s)
apt-get -q -y --no-install-recommends -o APT::Keep-Downloaded-Packages=true install mmdebstrap=@V_MMDEBSTRAP@ > /w/install.log 2>&1
echo "installation de mmdebstrap : rc $? en $(($(date +%s) - t)) s ; $(mmdebstrap --version 2>&1)"
for f in /var/cache/apt/archives/*.deb; do echo "deb amorce ${f##*/} $(sha256sum < $f | cut -c1-64)"; done
export SOURCE_DATE_EPOCH=@SDE@ TMPDIR=/w
mm() { # nom variante paquets [crochets…] : archive /w/<nom>.tar ; empreintes des .deb téléchargés (crochet de personnalisation)
  n=$1 v=$2 i=$3; shift 3
  t=$(date +%s)
  mmdebstrap --mode=root --variant=$v --format=tar --include=$i --skip=cleanup/apt/lists \
    --customize-hook="for f in \"\$1\"/var/cache/apt/archives/*.deb; do echo \"deb $n \${f##*/} \$(sha256sum < \$f | cut -c1-64)\"; done" \
    "$@" trixie /w/$n.tar "@SOURCE@" > /w/mm-$n.log 2>&1
  r=$?
  grep "^deb $n " /w/mm-$n.log
  echo "mmdebstrap $n : rc $r en $(($(date +%s) - t)) s, $(stat -c %s /w/$n.tar 2>/dev/null) octets, sha256 $(sha256sum < /w/$n.tar 2>/dev/null | cut -c1-64)"
  [ $r = 0 ] || grep -i -E "error|E:|failed" /w/mm-$n.log | head -n 5
}
mm racine minbase sbuild=@V_SBUILD@,libsbuild-perl=@V_SBUILD@,mmdebstrap=@V_MMDEBSTRAP@,uidmap=@V_UIDMAP@@IPROUTE2@ \
  --customize-hook="chroot \"\$1\" useradd -m -u 1000 -U -s /bin/sh constructeur" \
  --customize-hook="echo constructeur:100000:65536 > \"\$1\"/etc/subuid" \
  --customize-hook="echo constructeur:100000:65536 > \"\$1\"/etc/subgid"
[ @GARDER_CHROOT@ = 1 ] || mm chroot buildd debhelper,golang-go,nodejs
'

controle_debs() { # journal : chaque « deb <origine> <fichier> <sha256> » comparé au Packages vérifié sur l'hôte
  python3 -I - "$T/Packages" "$1" <<'PY'
import re, sys
pk = {}
for para in open(sys.argv[1], encoding='utf-8').read().split('\n\n'):
    d = dict(l.split(': ', 1) for l in para.split('\n') if ': ' in l and not l.startswith(' '))
    if 'Filename' in d: pk[d['Filename'].rsplit('/', 1)[1]] = d['SHA256']
n = {}; ko = []
for l in open(sys.argv[2], encoding='utf-8'):
    c = l.split()
    if len(c) == 4 and c[0] == 'deb':
        n[c[1]] = n.get(c[1], 0) + 1
        f = re.sub(r'_[0-9]+%3[aA]', '_', c[2])   # apt garde l'époque dans le nom du fichier, le pool non
        if pk.get(f) != c[3]: ko.append(c[1] + ' ' + c[2])
print('paquets contrôlés : ' + ', '.join(f'{k} {v}' for k, v in n.items()))
print(('OK   ' if not ko and n else 'KO   ') + f'sha256 des .deb conformes au Packages vérifié : {sum(n.values()) - len(ko)} sur {sum(n.values())}')
for k in ko[:10]: print('     écart : ' + k)
sys.exit(1 if ko or not n else 0)
PY
}

etape_racine() {
  local s f
  [ -s "$T/inrelease.sha256" ] && [ -s "$T/Packages" ] || { echo "KO   lancer d'abord l'étape prealables" >&2; exit 1; }
  s=$(date -u -d "$(sed -n 's/^Date: //p' "$T/hote/InRelease")" +%s)
  pod_spec s1-racine kata "$AMORCE" 0 "$PRIVILEGIE"
  pod_demarrer s1-racine
  sed -e "s|@SOURCE@|$SOURCE_LISTE|g" -e "s|@V_SBUILD@|$V_SBUILD|g" -e "s|@V_MMDEBSTRAP@|$V_MMDEBSTRAP|g" \
    -e "s|@V_UIDMAP@|$V_UIDMAP|g" -e "s|@SDE@|$s|g" -e "s|@GARDER_CHROOT@|$GARDER_CHROOT|g" \
    -e "s|@IPROUTE2@|$([ "$PREFIXE" = s1 ] || echo ",iproute2=$V_IPROUTE2")|g" <<<"$RACINE" | dans s1-racine racine
  attendu "InRelease lu par apt dans le pod = InRelease vérifié sur l'hôte" "$(champ racine InRelease | sed 's/^sha256 //')" "$(cat "$T/inrelease.sha256")"
  controle_debs "$T/racine.log" || echo "ÉCART empreintes des .deb : voir ci-dessus (apt les a déjà contrôlées contre Packages)"
  for f in racine chroot; do
    if [ "$f" = chroot ] && [ "$GARDER_CHROOT" = 1 ]; then
      attendu "chroot du premier passage, réutilisé" "$(sha256sum < "$T/chroot.tar" | cut -c1-64)" 440ba93bf3e42cd5b9d401db8b74227d77805bcae05c973ca516b7de1407b315
      continue
    fi
    s=$(sed -n "s/^mmdebstrap $f : rc 0 .*sha256 \([0-9a-f]\{64\}\)$/\1/p" "$T/racine.log")
    [ -n "$s" ] || { pod_retirer s1-racine; echo "KO   mmdebstrap $f" >&2; exit 1; }
    kubectl exec -n builds s1-racine -- cat "/w/$f.tar" </dev/null > "$T/$f.tar"
    attendu "archive $f rapatriée" "$(sha256sum < "$T/$f.tar" | cut -c1-64)" "$s"
  done
  pod_retirer s1-racine
}

etape_image() {
  local d
  [ -s "$T/racine.tar" ] && [ -s "$T/chroot.tar" ] || { echo "KO   lancer d'abord l'étape racine" >&2; exit 1; }
  rm -rf "$T/couche-chroot" && mkdir -p "$T/couche-chroot/opt/sbuild"
  cp "$T/chroot.tar" "$T/couche-chroot/opt/sbuild/trixie-amd64.tar"
  tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime=@0 \
    --owner=0 --group=0 --numeric-owner -C "$T/couche-chroot" -cf "$T/couche-chroot.tar" opt
  zot crane append --oci-empty-base -f "$T/racine.tar" -f "$T/couche-chroot.tar" -t "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" >/dev/null 2>"$T/crane.err" \
    || { cat "$T/crane.err" >&2; exit 1; }
  zot crane mutate "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" --set-platform linux/amd64 -t "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" \
    -e PATH=/usr/sbin:/usr/bin:/sbin:/bin -e HOME=/w/home >/dev/null 2>"$T/crane.err" || { cat "$T/crane.err" >&2; exit 1; }
  d=$(zot crane digest "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE")
  echo "$d" > "$T/image.digest"
  zot crane manifest "$REG_HOTE/$DEPOT_ESSAI@$d" | jq -r '.layers[] | "couche \(.digest) \(.size) octets"'
  echo "image d'essai : $REG/$DEPOT_ESSAI@$d"
}

SONDE='set -u
echo "uid : $(id -u)"
grep -E "^(CapEff|CapBnd|NoNewPrivs|Seccomp):" /proc/self/status
awk "\$2 == \"/\" || \$2 == \"/w\" {print \"montage \" \$2 \" : \" \$3 \" \" \$4}" /proc/mounts
stat -c "%n : %A %U" /usr/bin/newuidmap /usr/bin/newgidmap
echo "subuid : $(cat /etc/subuid)"; echo "subgid : $(cat /etc/subgid)"
mkdir -p /w/home /w/src /w/sortie
export TMPDIR=/w HOME=/w/home
unshare --user --map-auto sh -c "echo \"uid_map : \$(tr -s \" \" < /proc/self/uid_map | paste -sd \";\")\"" > /w/u.log 2>&1
r=$?; echo "unshare map-auto : rc $r $(paste -sd " " /w/u.log)"
[ $r = 0 ] || exit 0
cd /w/src && sha256sum -c SHA256SUMS.s1 > /w/c.log 2>&1; echo "sources livrées : rc $? $(paste -sd " " /w/c.log)"
t=$(date +%s)
sbuild --chroot-mode=unshare --chroot=/opt/sbuild/trixie-amd64.tar --dist=trixie --arch=amd64 --no-apt-update --no-apt-upgrade \
  --no-apt-distupgrade --no-run-lintian --no-run-autopkgtest --no-run-piuparts --no-source-only-changes --build-dir=/w/sortie \
  /w/src/@DSC@ > /w/sbuild.log 2>&1
r=$?; echo "sbuild : rc $r en $(($(date +%s) - t)) s"
grep -E "^(Status|Fail-Stage|Build-Time):" /w/sbuild.log
[ $r = 0 ] || tail -n 25 /w/sbuild.log
for f in /w/sortie/*.deb; do [ -e "$f" ] && echo "deb produit : ${f##*/} $(sha256sum < "$f" | cut -c1-64)"; done; true'

etape_essais() {
  local d img n p
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  img=$REG/$DEPOT_ESSAI@$d
  echo "image : $img"
  (cd "$PKG" && grep -E "  (sample-app_1.0.0.orig.tar.gz|sample-app_1.0.0-1.debian.tar.xz|$DSC)$" SHA256SUMS) > "$T/SHA256SUMS.s1"
  for p in "s1-kata-privilegie kata $PRIVILEGIE" "s1-kata-escalade kata $ESCALADE" "s1-runc-restreint - $RESTREINT"; do
    n=${p%% *}; p=${p#* }
    pod_spec "$n" "${p%% *}" "$img" 1000 "${p#* }"
    pod_demarrer "$n"
    tar -C "$PKG" -cf - sample-app_1.0.0.orig.tar.gz sample-app_1.0.0-1.debian.tar.xz "$DSC" \
      | kubectl exec -i -n builds "$n" -- sh -c 'mkdir -p /w/src && tar -xf - -C /w/src'
    kubectl exec -i -n builds "$n" -- sh -c 'cat > /w/src/SHA256SUMS.s1' < "$T/SHA256SUMS.s1"
    sed "s|@DSC@|$DSC|g" <<<"$SONDE" | dans "$n" "$n"
    pod_retirer "$n"
  done
}

# Relance (préparée à 13:14 UTC le 10/11/2026, après l'échec de sbuild en essais) : seul le pod Kata privilégié, même sonde ;
# le journal .build de sbuild est copié sur l'hôte avant la suppression du pod (resultats/s1-relance-sbuild.log, lignes
# jeton|token retirées).
etape_relance() {
  local d img n=s1-kata-privilegie
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  img=$REG/$DEPOT_ESSAI@$d
  echo "image : $img"
  pod_spec "$n" kata "$img" 1000 "$PRIVILEGIE"
  pod_demarrer "$n"
  tar -C "$PKG" -cf - sample-app_1.0.0.orig.tar.gz sample-app_1.0.0-1.debian.tar.xz "$DSC" \
    | kubectl exec -i -n builds "$n" -- sh -c 'mkdir -p /w/src && tar -xf - -C /w/src'
  kubectl exec -i -n builds "$n" -- sh -c 'cat > /w/src/SHA256SUMS.s1' < "$T/SHA256SUMS.s1"
  sed "s|@DSC@|$DSC|g" <<<"$SONDE" | dans "$n" relance
  kubectl exec -n builds "$n" -- sh -c 'ls /w/sortie; cat /w/sortie/*.build' </dev/null 2>&1 | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-relance-sbuild.log" || true
  echo "journal de sbuild : $(wc -l < "$R/$PREFIXE-relance-sbuild.log") lignes, resultats/$PREFIXE-relance-sbuild.log"
  pod_retirer "$n"
}

lancer "$PREFIXE" "06 S1" "$@"
