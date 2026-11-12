#!/usr/bin/env bash
# Brique 05, jalon S1 (M1 du README) : mock dans un pod Kata privilégié (D1 a). Risque principal : podman imbriqué (image de
# bootstrap de mock), puis l'isolation nspawn contre simple (prédictions 3 et 4 du README). Verrou et --hermetic-build : M2.
# Prédictions : resultats/s1-predictions.md, écrites et commitées avant toute exécution. Préparé à sec le 12/11/2026 à partir de
# 14:12:09 UTC, NON LANCÉ. À lancer après S5b (Zot est remis à zéro par le rejeu), chaque étape sur accord nommé.
#   hote        hôte seul, ni cluster ni Zot (peut tourner avant S5b ; à rejouer avant racine, pub/9.8 et EPEL bougent) : sources
#               de sample-app ; clés de Rocky et d'EPEL comparées aux empreintes publiées ; repomd.xml de Rocky 9.8 (BaseOS,
#               AppStream) et 9.7 (BaseOS, AppStream, CRB) vérifiés par gpgv ; repomd d'EPEL 9 (signature relevée) ; primary
#               contrôlé par repomd ; NEVRA et sha256 des quatre paquets épinglés
#   prealables  cluster et Zot, lecture seule et dry-run : politique de sortie rpm en place (prefetch-rpm-sortie, et prefetch-rpm
#               dans le NotIn de builds-sans-internet : décision du propriétaire, appliquée hors de ce script) ; exemption Pod
#               Security de kata ; spec admise en dry-run serveur ; sc-build ; place libre de Zot
#   amorce      copie par digest de rockylinux 9.8 (outillage, D4 a) et 9.7 (bootstrap de mock, D2 a), amd64, dans Zot,
#               amont/rockylinux/rockylinux
#   racine      pod Kata privilégié, root, label prefetch-rpm, image 9.8 : dnf --installroot des quatre paquets épinglés avec les
#               clés vérifiées sur l'hôte, dépendances selon les candidats ; repomd lus par dnf comparés à ceux de l'hôte ; sha256
#               de chaque rpm comparé sur l'hôte au primary vérifié ; rpm -K ; archive rapatriée, sha256 comparé
#   image       image d'essai assemblée sans rien exécuter (crane append) : racine, puis une couche de configuration (mock :
#               vault 9.7 en baseurl fixes, bootstrap par digest dans Zot, macros d'OBS ; stockage de podman sous /w) ;
#               poussée dans Zot sous essais-05/mock-rocky9:s1
#   essais      pod Kata privilégié, root, label prefetch-rpm, image d'essai : sonde (capacités, montages, versions, clés,
#               dépôts actifs de mock) ; podman pull de l'image de bootstrap par digest et image mount ; puis, pour nspawn puis
#               simple : mock --buildsrpm et --rebuild de sample-app, sha256 du src.rpm et du rpm, place de /w, scrub
# Les replis (stockage vfs, mock non root, bootstrap sans image) ne sont pas lancés ici : chacun demande sa prédiction et un accord.
# Retrait : Zot n'autorise pas la suppression ; dépôts amont/rockylinux/rockylinux et essais-05/mock-rocky9 définitifs.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh <étape>…   (journal : resultats/s1-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
ROCKY98=https://dl.rockylinux.org/pub/rocky/9.8
VAULT97=https://dl.rockylinux.org/vault/rocky/9.7
EPEL9=https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64
CLE_ROCKY=https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D            # publiée sur rockylinux.org/resources/gpg-key-info (audit du 05/11)
CLE_EPEL=https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
PAGE_EPEL=https://fedoraproject.org/security/                 # empreinte comparée à la page publiée, jamais écrite de mémoire
# nom version-release dépôt (relevé amont du 05/11 et audit de podman : mock et mock-core-configs dans EPEL 9 ; podman et skopeo de 9.8)
EPINGLES=("mock 6.9-1.el9 epel9" "mock-core-configs 45.2-1.el9 epel9" "podman 5.8.2-8.el9_8 appstream98" "skopeo 1.22.2-9.el9_8 appstream98")
AMORCE_DIGEST=sha256:ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d   # rockylinux:9.8, amd64 (audit du 05/11)
BOOT_DIGEST=sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2     # rockylinux:9.7, amd64 (audit du 05/11)
DEPOT_AMONT=amont/rockylinux/rockylinux
AMORCE=$REG/$DEPOT_AMONT@$AMORCE_DIGEST
BOOT=$REG/$DEPOT_AMONT@$BOOT_DIGEST
DEPOT_ESSAI=essais-05/mock-rocky9
PREFIXE=${PREFIXE:-s1}
PKG=${PACKAGING_DIR:-$HOME/.cache/supply-chain-poc/packaging}
LABEL=prefetch-rpm
LIMITES='{"cpu": "2", "memory": "6Gi"}'      # demandes = limites ; tmpfs /w compté dans la mémoire du pod
TMPFS=4Gi
PRIVILEGIE='{"privileged": true, "allowPrivilegeEscalation": true}'
CFG=poc-rocky-9.7-x86_64
T=$W/s1-05
mkdir -p "$T"
umask 022

zot() { DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt "$@"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
champ() { sed -n "s/^$2[[:space:]]*:[[:space:]]*//p" "$T/$1.log" | head -1; }   # journal libellé : valeur

pod_spec() { # nom image : pod de builds Kata privilégié, root, label prefetch-rpm, qui attend ; tmpfs /w, limites, zone build
  jq -n --arg n "$1" --arg i "$2" --argjson l "$LIMITES" --arg t "$TMPFS" --arg lb "$LABEL" --argjson sc "$PRIVILEGIE" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"tekton.dev/task": $lb}},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      runtimeClassName: "kata",
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: false, runAsUser: 0, runAsGroup: 0, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: $t}}],
      containers: [{name: "s1", image: $i, command: ["sleep", "10800"], securityContext: $sc,
        resources: {requests: $l, limits: $l}, volumeMounts: [{name: "w", mountPath: "/w"}]}]}}' > "$T/$1.json"
}

pod_demarrer() { # nom : pod de $T/<nom>.json créé et prêt
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true </dev/null >/dev/null
  kubectl create -f "$T/$1.json" </dev/null >/dev/null
  kubectl wait -n builds "pod/$1" --for=condition=Ready --timeout=300s </dev/null >/dev/null \
    || { kubectl get pod -n builds "$1" -o json </dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state
           | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"' >&2; echo "KO   pod $1 non prêt" >&2; exit 1; }   # raisons, jamais les messages
  echo "### $1 (kata, uid 0, privilégié, label tekton.dev/task=$LABEL) : prêt"
}

dans() { # nom libellé : script sh sur l'entrée standard, exécuté dans le pod ; sortie dans $T/<libellé>.log, puis affichée
  local rc=0
  kubectl exec -i -n builds "$1" -- sh -s > "$T/$2.log" 2>&1 || rc=$?
  sed 's/^/     /' "$T/$2.log"
  echo "     (code de l'exec : $rc)"
}

livrer() { # nom chemin-dans-le-pod fichier-local : petit fichier copié par l'entrée standard (aucun gros transfert entrant)
  kubectl exec -i -n builds "$1" -- sh -c "mkdir -p \"\$(dirname '$2')\" && cat > '$2'" < "$3"
}

pod_retirer() { kubectl delete pod -n builds "$1" --wait=false </dev/null >/dev/null; echo "pod $1 supprimé"; }

decompresser() { # fichier : contenu décompressé sur la sortie standard, d'après l'extension
  case $1 in
    *.gz) gzip -dc "$1" ;; *.xz) xz -dc "$1" ;; *.bz2) bzip2 -dc "$1" ;; *.zst) zstd -qdc "$1" ;;
    *) echo "KO   compression inconnue : $1" >&2; exit 1 ;;
  esac
}

depot_hote() { # nom url signé(1|0) : repomd.xml vérifié (gpgv, si signé), primary contrôlé par repomd et décompressé dans $T/<nom>.primary.xml
  local d=$T/hote h p s
  curl -fsSL --max-time 60 -o "$d/$1.repomd.xml" "$2/repodata/repomd.xml"
  if curl -fsSL --max-time 60 -o "$d/$1.repomd.xml.asc" "$2/repodata/repomd.xml.asc" 2>/dev/null; then
    s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/$1.repomd.xml.asc" "$d/$1.repomd.xml" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}')
    echo "$1 : repomd.xml signé, signataire ${s:-aucun valide}"
    [ "$3" = 0 ] || attendu "$1 : signataire de repomd.xml (clé primaire)" "$s" "$4"
  else
    echo "$1 : repomd.xml.asc absent"
    [ "$3" = 0 ] || { echo "KO   $1 : repomd.xml non signé" >&2; exit 1; }
  fi
  h=$(sha256sum < "$d/$1.repomd.xml" | cut -c1-64); echo "$h" > "$T/$1.repomd.sha256"
  echo "$1 : repomd.xml sha256 $h"
  read -r p s < <(python3 -I - "$d/$1.repomd.xml" <<'PY'
import sys, xml.etree.ElementTree as E
n = {'r': 'http://linux.duke.edu/metadata/repo'}
for d in E.parse(sys.argv[1]).getroot().findall('r:data', n):
    if d.get('type') == 'primary':
        c = d.find('r:checksum', n)
        print(d.find('r:location', n).get('href'), c.text if c.get('type') == 'sha256' else 'type-' + c.get('type'))
PY
  )
  curl -fsSL --max-time 300 -o "$d/$1.${p##*/}" "$2/$p"
  attendu "$1 : ${p##*/} contrôlé par repomd.xml" "$(sha256sum < "$d/$1.${p##*/}" | cut -c1-64)" "$s"
  decompresser "$d/$1.${p##*/}" > "$T/$1.primary.xml"
}

etape_prealables() { # cluster et Zot, en lecture seule et dry-run
  echo "## politique de sortie rpm (décision du propriétaire, appliquée hors de ce script)"
  kubectl get cnp -n builds prefetch-rpm-sortie </dev/null >/dev/null 2>&1 \
    && echo "OK   CiliumNetworkPolicy prefetch-rpm-sortie présente" \
    || { echo "KO   prefetch-rpm-sortie absente : proposition dans politiques/prefetch-rpm-sortie.yaml, à décider" >&2; exit 1; }
  attendu "NotIn de builds-sans-internet" \
    "$(kubectl get cnp -n builds builds-sans-internet -o json </dev/null | jq -r '.spec.endpointSelector.matchExpressions[0].values | sort | join(",")')" \
    "prefetch-deb,prefetch-gomod,prefetch-rpm"
  echo "## exemption Pod Security de la RuntimeClass kata"
  args_apiserver | grep -x -- "--admission-control-config-file=$D_CONF/pod-security.yaml" >/dev/null \
    && echo "OK   kube-apiserver lit $D_CONF/pod-security.yaml" || { echo "KO   exemption de kata absente" >&2; exit 1; }
  echo "## admission en dry-run serveur (image d'amorce : les règles ne lisent que la forme de la référence)"
  pod_spec s1-05-racine "$AMORCE"
  if kubectl create --dry-run=server -f "$T/s1-05-racine.json" </dev/null > "$T/admis.out" 2>&1; then echo "OK   s1-05-racine : admis"
  else echo "KO   s1-05-racine : refusé à l'admission" >&2; cat "$T/admis.out" >&2; exit 1; fi
  echo "## sc-build"
  kubectl get node sc-build -o json </dev/null | jq -r '"allouable : \(.status.allocatable.cpu) CPU, \(.status.allocatable.memory)"'
  kubectl get pods -A --field-selector spec.nodeName=sc-build,status.phase=Running -o json </dev/null \
    | jq -r '[.items[].spec.containers[].resources.requests.memory // empty] | "demandes de mémoire en cours : \(length) conteneur(s) : \(join(" "))"'
  echo "## place libre pour Zot"
  sur sc-stockage 'df -B1M --output=avail,target /var/lib/zot | tail -n 1' </dev/null | awk '{print "libre sous " $2 " : " $1 " Mo"}'
}

etape_hote() { # hôte seul, ni cluster ni Zot : peut tourner avant S5b ; à rejouer avant racine (pub/9.8 et EPEL bougent)
  local d n fp e
  echo "## sources de sample-app"
  (cd "$PKG" && grep -E '  (sample-app-1\.0\.0\.tar\.gz|sample-app\.spec)$' SHA256SUMS | sha256sum -c -)
  echo "## clés, vérifiées sur l'hôte"
  d=$T/hote; rm -rf -- "${d:?}"; mkdir -p "$d"
  curl -fsSL --max-time 60 -o "$d/RPM-GPG-KEY-Rocky-9" "$CLE_ROCKY"
  curl -fsSL --max-time 60 -o "$d/RPM-GPG-KEY-EPEL-9" "$CLE_EPEL"
  for n in RPM-GPG-KEY-Rocky-9 RPM-GPG-KEY-EPEL-9; do
    gpg --no-default-keyring --keyring "$d/cles.gpg" --batch --quiet --import "$d/$n" 2>/dev/null
    echo "$n : sha256 $(sha256sum < "$d/$n" | cut -c1-64)"
  done
  fp=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  attendu "empreinte de la clé de Rocky" "$fp" "$FP_ROCKY"
  e=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-EPEL-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  echo "empreinte de la clé d'EPEL 9 : $e"
  curl -fsSL --max-time 60 "$PAGE_EPEL" | tr -d ' \n' | tr 'a-f' 'A-F' > "$d/page-epel.txt"
  grep -q -- "$e" "$d/page-epel.txt" && echo "OK   empreinte d'EPEL 9 présente sur $PAGE_EPEL" \
    || { echo "KO   empreinte d'EPEL 9 absente de $PAGE_EPEL" >&2; exit 1; }
  echo "$e" > "$T/fp-epel"
  echo "## dépôts, vérifiés sur l'hôte"
  depot_hote baseos98 "$ROCKY98/BaseOS/x86_64/os" 1 "$FP_ROCKY"
  depot_hote appstream98 "$ROCKY98/AppStream/x86_64/os" 1 "$FP_ROCKY"
  depot_hote epel9 "$EPEL9" 0 "$e"
  for n in BaseOS AppStream CRB; do
    curl -fsSL --max-time 60 -o "$d/v97-$n.repomd.xml" "$VAULT97/$n/x86_64/os/repodata/repomd.xml"
    curl -fsSL --max-time 60 -o "$d/v97-$n.repomd.xml.asc" "$VAULT97/$n/x86_64/os/repodata/repomd.xml.asc"
    attendu "vault 9.7 $n : signataire de repomd.xml" \
      "$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/v97-$n.repomd.xml.asc" "$d/v97-$n.repomd.xml" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}')" "$FP_ROCKY"
    echo "vault 9.7 $n : repomd.xml sha256 $(sha256sum < "$d/v97-$n.repomd.xml" | cut -c1-64)"
  done
  echo "## paquets épinglés"
  python3 -I - "$T" "${EPINGLES[@]}" <<'PY'
import sys, xml.etree.ElementTree as E
t = sys.argv[1]; ko = 0
n = {'c': 'http://linux.duke.edu/metadata/common'}
idx = {}
for depot in ('baseos98', 'appstream98', 'epel9'):   # lecture en flux : le primary d'AppStream est gros
    for _, p in E.iterparse(f'{t}/{depot}.primary.xml'):
        if p.tag != '{http://linux.duke.edu/metadata/common}package': continue
        v = p.find('c:version', n)
        idx.setdefault((depot, p.find('c:name', n).text, f"{v.get('ver')}-{v.get('rel')}"), []).append(
            (p.find('c:arch', n).text, v.get('epoch'), p.find('c:checksum', n).text, p.find('c:location', n).get('href')))
        p.clear()
for e in sys.argv[2:]:
    nom, vr, depot = e.split()
    c = [x for x in idx.get((depot, nom, vr), []) if x[0] in ('x86_64', 'noarch')]
    if len(c) == 1:
        a, ep, h, href = c[0]
        print(f'OK   {nom}-{ep}:{vr}.{a} dans {depot} : sha256 {h} ({href})')
    else:
        ko = 1; print(f'KO   {nom}-{vr} dans {depot} : {len(c)} candidat(s) x86_64 ou noarch')
sys.exit(ko)
PY
}

etape_amorce() {
  auth_zot "$T/zot.json"
  mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"
  miroir "quay.io/rockylinux/rockylinux@$AMORCE_DIGEST" "$DEPOT_AMONT" "$T/zot.json"
  miroir "quay.io/rockylinux/rockylinux@$BOOT_DIGEST" "$DEPOT_AMONT" "$T/zot.json"
  attendu "digest de l'amorce 9.8 dans Zot" "$(zot crane digest "$REG_HOTE/$DEPOT_AMONT@$AMORCE_DIGEST")" "$AMORCE_DIGEST"
  attendu "digest du bootstrap 9.7 dans Zot" "$(zot crane digest "$REG_HOTE/$DEPOT_AMONT@$BOOT_DIGEST")" "$BOOT_DIGEST"
}

# Script de la racine (root, image 9.8). dnf ne lit que /w/dnf.conf (reposdir vide) ; les clés viennent de l'hôte.
RACINE='set -u
echo "invité : $(uname -r), $(nproc) vCPU, $(awk "/MemTotal/ {print \$2}" /proc/meminfo) kB ; /w : $(awk "\$2 == \"/w\" {print \$3}" /proc/mounts)"
echo "dnf : $(dnf --version 2>/dev/null | head -1) ; rpm : $(rpm --version)"
mkdir -p /w/aucun /w/racine /w/cache
t=$(date +%s)
dnf -y -q -c /w/dnf.conf --setopt=reposdir=/w/aucun --installroot=/w/racine --releasever=9 makecache > /w/makecache.log 2>&1
echo "makecache : rc $? en $(($(date +%s) - t)) s"
C="/w/cache /w/racine/w/cache"   # dnf peut placer cachedir dans la racine (--installroot) : les deux sont lus
echo "caches : $(for c in $C; do [ -d $c ] && printf "%s " $c; done)"
for r in baseos98 appstream98 epel9; do f=$(find $C -path "*/$r-*/repodata/repomd.xml" 2>/dev/null | head -1); echo "repomd $r : sha256 $(sha256sum < "$f" | cut -c1-64)"; done
t=$(date +%s)
dnf -y -c /w/dnf.conf --setopt=reposdir=/w/aucun --installroot=/w/racine --releasever=9 install @PAQUETS@ rocky-release shadow-utils > /w/install.log 2>&1
r=$?; echo "installation : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || { tail -n 25 /w/install.log; exit 0; }
for f in $(find $C -name "*.rpm" 2>/dev/null | sort); do d=$(basename "$(dirname "$(dirname "$f")")"); echo "rpm ${d%-*} ${f##*/} $(sha256sum < $f | cut -c1-64)"; done
rpm --root /w/racine -K $(find $C -name "*.rpm" 2>/dev/null) > /w/k.log 2>&1
echo "rpm -K : $(grep -c -E "digests signatures OK$" /w/k.log) OK sur $(find $C -name "*.rpm" 2>/dev/null | wc -l)"
grep -v -E "digests signatures OK$" /w/k.log | head -n 5
rpm --root /w/racine -qa --qf "%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort > /w/nevra.txt
echo "paquets installés : $(wc -l < /w/nevra.txt)"
for p in mock mock-core-configs podman skopeo systemd-container; do echo "installé : $(grep -E "^$p-[0-9]+:" /w/nevra.txt || echo "$p absent")"; done
rm -rf /w/racine/var/cache/dnf /w/racine/w
tar --sort=name --format=posix --xattrs --xattrs-include="*" --numeric-owner -C /w/racine -cf /w/racine.tar .
echo "archive racine : $(stat -c %s /w/racine.tar) octets, sha256 $(sha256sum < /w/racine.tar | cut -c1-64)"
'

dnf_conf() { # configuration de dnf de l'étape racine
  cat <<EOF
[main]
gpgcheck=1
install_weak_deps=0
keepcache=1
cachedir=/w/cache
reposdir=/w/aucun
tsflags=nodocs
[baseos98]
name=Rocky 9.8 BaseOS
baseurl=$ROCKY98/BaseOS/x86_64/os/
repo_gpgcheck=1
gpgkey=file:///w/cles/RPM-GPG-KEY-Rocky-9
[appstream98]
name=Rocky 9.8 AppStream
baseurl=$ROCKY98/AppStream/x86_64/os/
repo_gpgcheck=1
gpgkey=file:///w/cles/RPM-GPG-KEY-Rocky-9
[epel9]
name=EPEL 9
baseurl=$EPEL9/
repo_gpgcheck=0
gpgkey=file:///w/cles/RPM-GPG-KEY-EPEL-9
EOF
}

controle_rpms() { # journal : chaque « rpm <dépôt> <fichier> <sha256> » comparé au primary vérifié sur l'hôte
  python3 -I - "$T" "$1" <<'PY'
import sys, xml.etree.ElementTree as E
t = sys.argv[1]; n = {'c': 'http://linux.duke.edu/metadata/common'}; pk = {}
for depot in ('baseos98', 'appstream98', 'epel9'):   # lecture en flux
    for _, p in E.iterparse(f'{t}/{depot}.primary.xml'):
        if p.tag != '{http://linux.duke.edu/metadata/common}package': continue
        pk[(depot, p.find('c:location', n).get('href').rsplit('/', 1)[1])] = p.find('c:checksum', n).text
        p.clear()
c = {}; ko = []
for l in open(sys.argv[2], encoding='utf-8'):
    x = l.split()
    if len(x) == 4 and x[0] == 'rpm':
        c[x[1]] = c.get(x[1], 0) + 1
        if pk.get((x[1], x[2])) != x[3]: ko.append(x[1] + ' ' + x[2])
print('paquets contrôlés : ' + ', '.join(f'{k} {v}' for k, v in sorted(c.items())))
print(('OK   ' if not ko and c else 'KO   ') + f'sha256 des rpm conformes aux primary vérifiés : {sum(c.values()) - len(ko)} sur {sum(c.values())}')
for k in ko[:10]: print('     écart : ' + k)
sys.exit(1 if ko or not c else 0)
PY
}

etape_racine() {
  local s r p=""
  for r in baseos98 appstream98 epel9; do [ -s "$T/$r.repomd.sha256" ] && [ -s "$T/$r.primary.xml" ] || { echo "KO   lancer d'abord l'étape hote" >&2; exit 1; }; done
  for r in "${EPINGLES[@]}"; do set -- $r; p="$p $1-$2"; done
  pod_spec s1-05-racine "$AMORCE"
  pod_demarrer s1-05-racine
  livrer s1-05-racine /w/cles/RPM-GPG-KEY-Rocky-9 "$T/hote/RPM-GPG-KEY-Rocky-9"
  livrer s1-05-racine /w/cles/RPM-GPG-KEY-EPEL-9 "$T/hote/RPM-GPG-KEY-EPEL-9"
  dnf_conf > "$T/dnf.conf" && livrer s1-05-racine /w/dnf.conf "$T/dnf.conf"
  sed -e "s|@PAQUETS@|${p# }|g" <<<"$RACINE" | dans s1-05-racine racine
  for r in baseos98 appstream98 epel9; do
    attendu "repomd $r lu par dnf dans le pod = repomd vérifié sur l'hôte" "$(champ racine "repomd $r" | sed 's/^sha256 //')" "$(cat "$T/$r.repomd.sha256")"
  done
  controle_rpms "$T/racine.log" || echo "ÉCART empreintes des rpm : voir ci-dessus (dnf les a déjà contrôlées contre ses métadonnées)"
  s=$(sed -n 's/^archive racine : .*sha256 \([0-9a-f]\{64\}\)$/\1/p' "$T/racine.log")
  [ -n "$s" ] || { pod_retirer s1-05-racine; echo "KO   archive racine absente" >&2; exit 1; }
  kubectl exec -n builds s1-05-racine -- cat /w/racine.tar </dev/null > "$T/racine.tar"
  attendu "archive racine rapatriée" "$(sha256sum < "$T/racine.tar" | cut -c1-64)" "$s"
  pod_retirer s1-05-racine
}

# Configuration de mock : modèle rocky-9 de mock-core-configs 45.2-1, mirrorlist de BaseOS, AppStream et CRB remplacés par les
# baseurl fixes de vault 9.7 (D2 a) ; image de bootstrap par digest dans Zot, non « prête » (mock y installe dnf : M2 exigera
# une image prête) ; macros d'OBS (poc.prjconf) ; racines de mock sous /w (tmpfs).
MOCK_CFG="include('templates/rocky-9.tpl')
config_opts['root'] = '$CFG'
config_opts['target_arch'] = 'x86_64'
config_opts['legal_host_arches'] = ('x86_64',)
config_opts['basedir'] = '/w/mock'
config_opts['cache_topdir'] = '/w/mock-cache'
config_opts['use_bootstrap_image'] = True
config_opts['bootstrap_image'] = '$BOOT'
config_opts['bootstrap_image_ready'] = False
config_opts['macros']['%_buildhost'] = 'reproducible'
config_opts['macros']['%source_date_epoch_from_changelog'] = '1'
config_opts['macros']['%use_source_date_epoch_as_buildtime'] = '1'
config_opts['macros']['%clamp_mtime_to_source_date_epoch'] = '1'
for r in ('BaseOS', 'AppStream', 'CRB'):
    config_opts['dnf.conf'] = config_opts['dnf.conf'].replace(
        'mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=\$basearch&repo=%s-\$releasever\n' % r,
        'baseurl=$VAULT97/%s/x86_64/os/\n' % r)
"

STOCKAGE='[storage]
driver = "overlay"
graphroot = "/w/containers"
runroot = "/w/run-containers"
'

etape_image() {
  local d c=$T/couche-config
  [ -s "$T/racine.tar" ] || { echo "KO   lancer d'abord l'étape racine" >&2; exit 1; }
  rm -rf -- "${c:?}" && mkdir -p "$c/etc/mock" "$c/etc/containers"
  printf '%s' "$MOCK_CFG" > "$c/etc/mock/$CFG.cfg"
  printf '%s' "$STOCKAGE" > "$c/etc/containers/storage.conf"
  echo "configuration de mock : sha256 $(sha256sum < "$c/etc/mock/$CFG.cfg" | cut -c1-64)"
  tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime=@0 \
    --owner=0 --group=0 --numeric-owner -C "$c" -cf "$T/couche-config.tar" etc
  [ -s "$T/docker/config.json" ] || { auth_zot "$T/zot.json"; mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"; }
  zot crane append --oci-empty-base -f "$T/racine.tar" -f "$T/couche-config.tar" -t "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" >/dev/null 2>"$T/crane.err" \
    || { cat "$T/crane.err" >&2; exit 1; }
  zot crane mutate "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" --set-platform linux/amd64 -t "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" \
    -e PATH=/usr/sbin:/usr/bin:/sbin:/bin -e HOME=/root >/dev/null 2>"$T/crane.err" || { cat "$T/crane.err" >&2; exit 1; }
  d=$(zot crane digest "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE")
  echo "$d" > "$T/image.digest"
  zot crane manifest "$REG_HOTE/$DEPOT_ESSAI@$d" | jq -r '.layers[] | "couche \(.digest) \(.size) octets"'
  echo "image d'essai : $REG/$DEPOT_ESSAI@$d"
}

SONDE='set -u
echo "uid : $(id -u)"
grep -E "^(CapEff|CapBnd|NoNewPrivs|Seccomp):" /proc/self/status
awk "\$2 == \"/\" || \$2 == \"/w\" {print \"montage \" \$2 \" : \" \$3 \" \" \$4}" /proc/mounts
rpm -q mock mock-core-configs podman skopeo systemd-container distribution-gpg-keys 2>&1 | sed "s/^/version : /"
grep -h -E "gpgkey" /etc/mock/templates/rocky-9.tpl | sort -u | head -n 5 | sed "s/^/gpgkey du modèle : /"
for k in /usr/share/distribution-gpg-keys/rocky/*; do
  echo "clé ${k##*/} : $(gpg --batch --with-colons --show-keys "$k" 2>/dev/null | awk -F: "\$1 == \"fpr\" {print \$10; exit}")"
done
mock -r @CFG@ --debug-config > /w/debug-config.log 2>&1; echo "mock --debug-config : rc $?"
grep -o -E "(baseurl|mirrorlist|metalink)=[^[:space:]\\\\]+" /w/debug-config.log | sort | uniq -c | sed "s/^/dépôt de mock : /"
n=$(grep -o -E "mirrorlist=[^[:space:]\\\\]*repo=(BaseOS|AppStream|CRB)-[$]releasever([^-]|$)" /w/debug-config.log | wc -l)
echo "mirrorlist restants pour BaseOS, AppStream et CRB : $n"
[ "$n" = 0 ] || { echo "KO   remplacement des mirrorlist par vault 9.7 incomplet : mock non lancé"; exit 0; }
echo "## podman imbriqué"
podman info --format "stockage : {{.Store.GraphDriverName}} sous {{.Store.GraphRoot}}" 2>&1 | tail -n 1
t=$(date +%s); podman pull @BOOT@ > /w/pull.log 2>&1
r=$?; echo "podman pull du bootstrap : rc $r en $(($(date +%s) - t)) s"; [ $r = 0 ] || tail -n 5 /w/pull.log
m=$(podman image mount @BOOT@ 2>/w/mount.err); r=$?
echo "podman image mount : rc $r ; os-release : $(grep -h ^VERSION_ID= "$m/etc/os-release" 2>/dev/null)"; [ $r = 0 ] || tail -n 3 /w/mount.err
podman image umount @BOOT@ >/dev/null 2>&1
echo "## mock"
cd /w/src && sha256sum -c SHA256SUMS.s1 > /w/c.log 2>&1; echo "sources livrées : rc $? $(paste -sd " " /w/c.log)"
for iso in nspawn simple; do
  mkdir -p /w/res-$iso
  t=$(date +%s)
  mock -r @CFG@ --isolation=$iso --uniqueext=$iso --resultdir=/w/res-$iso --buildsrpm --spec /w/src/sample-app.spec \
    --sources /w/src > /w/mock-$iso-srpm.log 2>&1
  r=$?; echo "mock $iso --buildsrpm : rc $r en $(($(date +%s) - t)) s"
  [ $r = 0 ] || { tail -n 25 /w/mock-$iso-srpm.log; tail -n 25 /w/res-$iso/root.log 2>/dev/null; mock -r @CFG@ --uniqueext=$iso --scrub=all >/dev/null 2>&1; continue; }
  s=$(ls /w/res-$iso/*.src.rpm | head -1); echo "src.rpm $iso : ${s##*/} $(sha256sum < $s | cut -c1-64)"
  t=$(date +%s)
  mock -r @CFG@ --isolation=$iso --uniqueext=$iso --resultdir=/w/res-$iso --no-clean --rebuild "$s" > /w/mock-$iso-rebuild.log 2>&1
  r=$?; echo "mock $iso --rebuild : rc $r en $(($(date +%s) - t)) s"
  [ $r = 0 ] || { tail -n 25 /w/mock-$iso-rebuild.log; tail -n 25 /w/res-$iso/build.log 2>/dev/null; }
  for f in /w/res-$iso/*.rpm; do case $f in *.src.rpm) ;; *) [ -e "$f" ] && echo "rpm $iso : ${f##*/} $(sha256sum < $f | cut -c1-64)" ;; esac; done
  echo "place de /w après $iso : $(du -sm /w 2>/dev/null | cut -f1) Mo"
  mock -r @CFG@ --uniqueext=$iso --scrub=all > /w/scrub-$iso.log 2>&1; echo "scrub $iso : rc $?"
done
true'

etape_essais() {
  local d img n=s1-05-essais
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  img=$REG/$DEPOT_ESSAI@$d
  echo "image : $img"
  (cd "$PKG" && grep -E '  (sample-app-1\.0\.0\.tar\.gz|sample-app\.spec)$' SHA256SUMS) > "$T/SHA256SUMS.s1"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$n" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$n" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  sed -e "s|@CFG@|$CFG|g" -e "s|@BOOT@|$BOOT|g" <<<"$SONDE" | dans "$n" essais
  kubectl exec -n builds "$n" -- sh -c 'for f in /w/res-*/build.log /w/res-*/root.log; do [ -e "$f" ] && { echo "### $f"; tail -n 200 "$f"; }; done' \
    </dev/null 2>&1 | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-essais-mock.log" || true
  echo "journaux de mock : $(wc -l < "$R/$PREFIXE-essais-mock.log") lignes, resultats/$PREFIXE-essais-mock.log"
  pod_retirer "$n"
}

lancer "$PREFIXE" "05 S1" "$@"
