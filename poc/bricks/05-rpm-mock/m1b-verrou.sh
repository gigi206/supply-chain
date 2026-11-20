#!/usr/bin/env bash
# Brique 05, cascade de M1b (§5 de resultats/m1b-carte.md), premier point : le verrou refait hors de la plateforme (décision
# « Hors plateforme »), avec le bootstrap neuf que la plateforme a construit en M1b. Préparé à sec le 20/11/2026, NON LANCÉ.
# Modèle : étape verrou_derivee de s1.sh (passée le 17/11/2026, verrou b6d0f8f1). Seuls changent :
#   - l'image du pod : l'outillage de M1b, builds/builders/mock-rocky9@70f8c412 (au lieu de essais-05/mock-rocky9@99790c13) ;
#   - le bootstrap de la configuration dérivée : builds/builders/rocky9-bootstrap@6de899ac (au lieu de essais-05/…@f0ccf105) ;
#   - la référence de comparaison : le verrou de verrou_derivee (b6d0f8f1), et non plus celui de verrou_brut ;
#   - les noms : pod $N-05-verrou, journaux resultats/$N-verrou-*.log, verrou resultats/$N-verrou.json, jamais écrasé.
# La racine de la configuration dérivée garde son nom (poc-rocky-9.7-derivee-x86_64). La configuration neuve ne diffère donc de
# celle de verrou_derivee que par bootstrap_image (deux lignes de diff, contrôlées avant le pod).
# Recopiés de s1.sh à l'identique, par extraction (le banc les compare aux originaux) : attendu, champ, pod_spec, pod_demarrer,
# dans, livrer, pod_retirer, MOCK_CFG, SONDE_VERROU, SONDE_BOOT, SONDE_CFG_DERIVEE, SONDE_REPLI.
# Écrit : resultats/$N-verrou.json et resultats/$N-verrou-mock.log. Rien dans Zot. poc/packaging/verrou-rpm.json n'est pas
# touché : il appartient à l'artefact de M4a, point suivant de la cascade. Cluster : un pod d'essai dans builds, retiré à la fin.
#   verrou   gardes en lecture seule (verrou de référence, manifestes relus anonymement dans Zot, configurations, politiques
#            réseau du label, dry-run serveur du pod) ; puis pod Kata privilégié au label prefetch-rpm (sortie de
#            prefetch-rpm-sortie : vault 9.7 et Zot), mock --buildsrpm puis --calculate-build-dependencies, repli cherché,
#            bootstrap de mock comparé à l'image ; enfin verrou comparé à b6d0f8f1, feuille par feuille.
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/m1b-verrou.sh verrou
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # P, W, REG, REG_HOTE, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
N=${PREFIXE:-m1b}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
T=$W/$N-verrou-05
mkdir -p "$T"
umask 022

# Valeurs reprises de s1.sh (le banc les compare aux lignes de s1.sh)
VAULT97=https://dl.rockylinux.org/vault/rocky/9.7
BOOT_DIGEST=sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2     # rockylinux:9.7, amd64 (audit du 05/11)
DEPOT_AMONT=amont/rockylinux/rockylinux
BOOT=$REG/$DEPOT_AMONT@$BOOT_DIGEST
LABEL=prefetch-rpm
LIMITES='{"cpu": "2", "memory": "6Gi"}'      # demandes = limites ; tmpfs /w compté dans la mémoire du pod
TMPFS=4Gi
PRIVILEGIE='{"privileged": true, "allowPrivilegeEscalation": true}'
CFG=poc-rocky-9.7-x86_64
CFG_DERIVE=poc-rocky-9.7-derivee-x86_64   # étape verrou_derivee : livrée dans le pod, bootstrap = image dérivée, prête
PKG=$HOME/.cache/supply-chain-poc/packaging   # valeur par défaut de PACKAGING_DIR dans s1.sh
ISOLATION=simple                              # valeur par défaut de s1.sh, celle de verrou_derivee ; non surchargeable ici

# Images de M1b (m1b-pipeline-pipeline.log, m1b-provenance.sh) et référence de verrou_derivee (s1-verrou_derivee.log)
DEPOT_OUTILLAGE=builds/builders/mock-rocky9
DIGEST_OUTILLAGE=sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae
DEPOT_BOOTSTRAP=builds/builders/rocky9-bootstrap
DIGEST_BOOTSTRAP=sha256:6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3
DEPOT_DERIVE_S1=essais-05/rocky9-bootstrap
DIGEST_DERIVE_S1=sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6
VERROU_REF=$R/s1-verrou_derivee.json
VERROU_REF_SHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f   # comme VERROU_SHA de m4a.sh
MOCK_CFG_SHA=a8e5f2bc8d2b4a54f6b5fb7fea62ebd55628e3499abd8608014e38285bc6ea31     # configuration de base relue dans le pod de verrou_derivee
CFG_DERIVE_S1_SHA=78645df78c3d47b90fd9617844058105b752146402e5a5288aa0abc66e73d2d8  # configuration dérivée de verrou_derivee
POLITIQUES_LABEL="CiliumNetworkPolicy prefetch-rpm-sortie"   # relevé du 20/11 : seule politique de builds qui sélectionne le label
OUT=$R/$N-verrou.json
MOCKLOG=$R/$N-verrou-mock.log

# --- recopié de s1.sh ---
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
      containers: [{name: "s1", image: $i, command: ["sleep", "43200"], securityContext: $sc,
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
for r in ('BaseOS', 'AppStream', 'CRB', 'extras'):
    config_opts['dnf.conf'] = config_opts['dnf.conf'].replace(
        'mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=\$basearch&repo=%s-\$releasever\n' % r,
        'baseurl=$VAULT97/%s/x86_64/os/\n' % r)
"

SONDE_VERROU='set -u
echo "isolation : @ISO@ ; configuration : @CFG_PRET@"
cd /w/src && sha256sum -c SHA256SUMS.s1 > /w/c.log 2>&1; echo "sources livrées : rc $? $(paste -sd " " /w/c.log)"
mock -r @CFG_PRET@ --debug-config > /w/verrou-debug-config.log 2>&1; rd=$?; echo "mock --debug-config : rc $rd"
if [ $rd != 0 ]; then echo "configuration : illisible, --debug-config en échec"; tail -n 5 /w/verrou-debug-config.log
else
  P="^config_opts\[.bootstrap_image_ready.\]"
  if grep -q -E "$P" /w/verrou-debug-config.log; then grep -E "$P" /w/verrou-debug-config.log | sed "s/^/configuration : /"
  else echo "configuration : bootstrap_image_ready absent de --debug-config, donc valeur par défaut (False)"; fi
  O="^config_opts\[.bootstrap_(module_enable|module_install|module_setup_commands|chroot_additional_packages).\]"
  echo "options bootstrap_* qui annulent « prête », posées : $(grep -c -E "$O" /w/verrou-debug-config.log) (absente = valeur par défaut, vide)"
  grep -E "$O" /w/verrou-debug-config.log | sed "s/^/option posée : /"
fi
M="Not updating bootstrap chroot|Package management in bootstrap|Bootstrap image not marked ready"
etat() { c=$(grep -c -E "$M" /w/res-verrou/root.log 2>/dev/null); echo "root.log, $1 : ${c:-root.log absent} ligne(s) sur le bootstrap prêt ou non, cumulées"
  grep -E "$M" /w/res-verrou/root.log 2>/dev/null | sed "s/^/root.log, $1 : /"; }
mkdir -p /w/res-verrou
t=$(date +%s)
mock -r @CFG_PRET@ --isolation=@ISO@ --resultdir=/w/res-verrou --buildsrpm --spec /w/src/sample-app.spec --sources /w/src > /w/verrou-srpm.log 2>&1
r=$?; echo "mock --buildsrpm (image prête) : rc $r en $(($(date +%s) - t)) s"
etat "après --buildsrpm"
[ $r = 0 ] || { tail -n 25 /w/verrou-srpm.log; tail -n 25 /w/res-verrou/root.log 2>/dev/null; exit 0; }
s=$(ls /w/res-verrou/*.src.rpm | head -1); echo "src.rpm : ${s##*/} $(sha256sum < $s | cut -c1-64)"
t=$(date +%s)
mock -r @CFG_PRET@ --isolation=@ISO@ --resultdir=/w/res-verrou --calculate-build-dependencies "$s" > /w/verrou-calc.log 2>&1
r=$?; echo "mock --calculate-build-dependencies : rc $r en $(($(date +%s) - t)) s"
etat "après --calculate-build-dependencies"
[ $r = 0 ] || { tail -n 25 /w/verrou-calc.log; tail -n 25 /w/res-verrou/root.log 2>/dev/null; }
ls -l /w/res-verrou | sed "s/^/résultat : /"
for f in /w/res-verrou/*.json; do [ -e "$f" ] && echo "verrou : ${f##*/} $(stat -c %s "$f") octets, sha256 $(sha256sum < "$f" | cut -c1-64)"; done
true'

SONDE_BOOT='set -u
export LC_ALL=C
Q="%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE} sigpgp=%{SIGPGP:pgpsig} rsaheader=%{RSAHEADER:pgpsig}\n"
liste() { # racine nom libellé : var/lib/rpm de la racine copié sous /w, lu par --dbpath ; liste triée, stderr à part
  rm -rf "/w/rpmdb-$2"
  cp -a "$1/var/lib/rpm" "/w/rpmdb-$2" 2> "/w/$2.cp.err" || { echo "$3 : copie de var/lib/rpm en échec"; tail -n 3 "/w/$2.cp.err"; return 1; }
  rpm --dbpath "/w/rpmdb-$2" -qa --qf "$Q" > "/w/$2.brut" 2> "/w/$2.err"; r=$?
  sort "/w/$2.brut" > "/w/$2.txt"
  echo "$3 : rpm -qa rc $r, $(wc -l < "/w/$2.txt") ligne(s), stderr $(wc -l < "/w/$2.err") ligne(s)"
  head -n 3 "/w/$2.err" | sed "s/^/$3, stderr : /"
}
set -- /w/mock/@CFG@-bootstrap*/root
echo "bootstrap préparé par mock : $# chemin(s) pour /w/mock/@CFG@-bootstrap*/root ; retenu : $1"
a=0
if [ -d "$1" ]; then liste "$1" boot-mock "bootstrap de mock" && a=1
else echo "bootstrap préparé par mock : $1 absent"; ls -d /w/mock/* 2>&1 | sed "s/^/dossier de mock : /"; fi
i=0
t=$(date +%s); podman pull @BOOT@ > /w/pull-brut.log 2>&1; r=$?
echo "podman pull de rockylinux:9.7 brut : rc $r en $(($(date +%s) - t)) s"
if [ $r = 0 ]; then
  m=$(podman image mount @BOOT@ 2>/w/mount-brut.err); r=$?; echo "podman image mount : rc $r"
  if [ $r = 0 ]; then liste "$m" boot-image "rockylinux:9.7 brut" && i=1; podman image umount @BOOT@ >/dev/null 2>&1
  else tail -n 3 /w/mount-brut.err; fi
else tail -n 5 /w/pull-brut.log; fi
if [ $a = 1 ] && [ $i = 1 ]; then
  comm -13 /w/boot-image.txt /w/boot-mock.txt | sed "s/^/seulement dans le bootstrap de mock : /"
  comm -23 /w/boot-image.txt /w/boot-mock.txt | sed "s/^/seulement dans rockylinux:9.7 brut : /"
  echo "lignes communes : $(comm -12 /w/boot-image.txt /w/boot-mock.txt | wc -l)"
else
  echo "comparaison non faite (bootstrap de mock lu : $a ; rockylinux:9.7 brut lu : $i)"
  [ $a = 0 ] || sed "s/^/bootstrap de mock, liste : /" /w/boot-mock.txt
  [ $i = 0 ] || sed "s/^/rockylinux:9.7 brut, liste : /" /w/boot-image.txt
fi
df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
true'

SONDE_CFG_DERIVEE='set -u
echo "configuration de base, image du pod : sha256 $(sha256sum < /etc/mock/@CFG@.cfg | cut -c1-64)"
echo "configuration dérivée livrée : sha256 $(sha256sum < /etc/mock/@CFG_DERIVE@.cfg | cut -c1-64)"
mock -r @CFG_DERIVE@ --debug-config > /w/derivee-debug-config.log 2>&1; echo "mock --debug-config : rc $?"
grep -E "^config_opts\[.(root|bootstrap_image|bootstrap_image_ready|bootstrap_image_fallback|bootstrap_image_assert_digest).\]" \
  /w/derivee-debug-config.log | sed "s/^/configuration lue par mock : /"
t=$(date +%s); podman pull @DERIVEE@ > /w/pull-derivee.log 2>&1; r=$?
echo "podman pull, image dérivée : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || tail -n 5 /w/pull-derivee.log
podman image inspect --format "image dérivée, inspect : {{.Digest}} {{.Os}}/{{.Architecture}}" @DERIVEE@ 2>&1 | tail -n 1
true'
SONDE_REPLI='for f in /w/res-verrou/root.log /w/verrou-srpm.log /w/verrou-calc.log; do
  c=$(grep -c "falling back to chroot installation" "$f" 2>/dev/null); echo "${f#/w/} : ${c:-fichier absent} ligne(s) de repli sans image"
done
true'
# --- fin de la copie ---

derivee() { # image-de-bootstrap : configuration dérivée de MOCK_CFG, comme etape_verrou_derivee (racine, bootstrap_image, prête)
  printf '%s' "$MOCK_CFG" | sed -e "s|'root'\] = '$CFG'|'root'] = '$CFG_DERIVE'|" \
    -e "s|'bootstrap_image'\] = '$BOOT'|'bootstrap_image'] = '$1'|" \
    -e "s|'bootstrap_image_ready'\] = False|'bootstrap_image_ready'] = True|"
}

manifeste() { # dépôt digest : manifeste lu anonymement par l'adresse IP de Zot, sha256 contrôlé ; digest de la configuration
  local m=$T/manifeste-${2:7:12}.json
  echo '{}' > "$T/vide.json"
  oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" "$REG_HOTE/$1@$2" < /dev/null > "$m"
  attendu "Zot, $1, sha256 du manifeste lu anonymement" "sha256:$(sha256sum < "$m" | cut -c1-64)" "$2" >&2
  jq -r .config.digest "$m"
}

gardes() { # lecture seule ; écrit $T/<pod>.json, $T/$CFG.cfg, $T/derivee-s1.cfg, $T/$CFG_DERIVE.cfg et $T/config-bootstrap
  local n=$1 boot_d=$REG/$DEPOT_BOOTSTRAP@$DIGEST_BOOTSTRAP c=$T/$CFG_DERIVE.cfg t=$T/politiques.json e
  echo "## gardes, en lecture seule"
  [ ! -e "$OUT" ] && [ ! -e "$MOCKLOG" ] \
    || { echo "KO   verrou ou journal de mock déjà écrit, jamais écrasé : resultats/${OUT##*/} (relancer sous un autre PREFIXE)" >&2; exit 1; }
  echo "OK   G0 sorties absentes : resultats/${OUT##*/}, resultats/${MOCKLOG##*/}"
  attendu "G1 verrou de référence de verrou_derivee, sha256" "$(sha256sum < "$VERROU_REF" | cut -c1-64)" "$VERROU_REF_SHA"
  manifeste "$DEPOT_OUTILLAGE" "$DIGEST_OUTILLAGE" > /dev/null
  manifeste "$DEPOT_BOOTSTRAP" "$DIGEST_BOOTSTRAP" > "$T/config-bootstrap"
  echo "G2 configuration de l'image de bootstrap (id attendu dans le verrou) : $(cat "$T/config-bootstrap")"
  printf '%s' "$MOCK_CFG" > "$T/$CFG.cfg"
  attendu "G3 MOCK_CFG recopiée, égale à la configuration de base relue dans le pod de verrou_derivee" \
    "$(sha256sum < "$T/$CFG.cfg" | cut -c1-64)" "$MOCK_CFG_SHA"
  derivee "$REG/$DEPOT_DERIVE_S1@$DIGEST_DERIVE_S1" > "$T/derivee-s1.cfg"
  attendu "G3 configuration dérivée de verrou_derivee, recalculée" "$(sha256sum < "$T/derivee-s1.cfg" | cut -c1-64)" "$CFG_DERIVE_S1_SHA"
  derivee "$boot_d" > "$c"
  attendu "G3 configuration neuve contre MOCK_CFG : racine, bootstrap_image et bootstrap_image_ready" \
    "$(diff "$T/$CFG.cfg" "$c" | grep -c '^[<>]')" 6
  attendu "G3 configuration neuve contre celle de verrou_derivee : bootstrap_image seul" "$(diff "$T/derivee-s1.cfg" "$c" | grep -c '^[<>]')" 2
  { diff "$T/derivee-s1.cfg" "$c" || true; } | grep '^[<>]' | sed 's/^/écart prévu : /'
  echo "configuration neuve : sha256 $(sha256sum < "$c" | cut -c1-64)"
  attendu "G4 spec de sample-app : cache de s1.sh égal au dépôt" "$(cmp -s "$PKG/sample-app.spec" "$repo/poc/packaging/sample-app.spec" && echo égal || echo différent)" égal
  (cd "$PKG" && grep -E '  (sample-app-1\.0\.0\.tar\.gz|sample-app\.spec)$' SHA256SUMS) > "$T/SHA256SUMS.s1"
  attendu "G4 sources de sample-app contrôlées par SHA256SUMS" "$(cd "$PKG" && sha256sum -c "$T/SHA256SUMS.s1" 2>&1 | paste -sd' ')" \
    "sample-app-1.0.0.tar.gz: OK sample-app.spec: OK"
  { kubectl get networkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "NetworkPolicy"'
    kubectl get ciliumnetworkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "CiliumNetworkPolicy"'; } | jq -s '{items: .}' > "$t"
  attendu "G5 politiques de builds qui sélectionnent $LABEL" "$(jq -r -L "$here" --arg l "$LABEL" \
    'include "selecteurs"; [.items[] | select(selectionne({"tekton.dev/task": $l})) | nom] | join(", ")' "$t")" "$POLITIQUES_LABEL"
  attendu "G5 politiques de builds qui sélectionnent $LABEL et autorisent du trafic" "$(jq -r -L "$here" --arg l "$LABEL" \
    'include "selecteurs"; [.items[] | select(selectionne({"tekton.dev/task": $l}) and autorise) | nom] | join(", ")' "$t")" "$POLITIQUES_LABEL"
  pod_spec "$n" "$REG/$DEPOT_OUTILLAGE@$DIGEST_OUTILLAGE"
  attendu "G6 pod $n absent du cluster" "$(kubectl get pod -n builds "$n" --ignore-not-found -o name < /dev/null)" ""
  if e=$(kubectl create --dry-run=server -f "$T/$n.json" -o name < /dev/null 2> "$T/dry-run.err"); then
    attendu "G6 pod admis en dry-run serveur" "$e" "pod/$n"
  else
    sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' "$T/dry-run.err" | head -c 400 >&2
    echo "KO   G6 pod refusé en dry-run serveur" >&2; exit 1
  fi
}

comparer_verrou() { # verrou-neuf verrou-de-référence pull-digest bootstrap_image id : écarts feuille par feuille, code 1 si KO
  python3 -I - "$@" <<'PY'
import json, re, sys
neuf, ref = (json.load(open(f, encoding='utf-8')) for f in sys.argv[1:3])
pull, image, ident = sys.argv[3:6]
def feuilles(x, p=''):
    if isinstance(x, dict):
        for k, v in x.items():
            yield from feuilles(v, p + '.' + k)
    else:
        yield p, x   # une liste est une feuille : comparée en entier
a, b = dict(feuilles(neuf)), dict(feuilles(ref))
ecarts = sorted(k for k in set(a) | set(b) if a.get(k, '<absent>') != b.get(k, '<absent>'))
prevus = ['.bootstrap.id', '.bootstrap.image_digest', '.bootstrap.pull_digest', '.config.bootstrap_image']
ko = 0
def dire(ok, texte):
    global ko
    ko += not ok
    print(('OK   ' if ok else 'KO   ') + texte)
dire(ecarts == prevus, 'C1 feuilles qui diffèrent de verrou_derivee : ' + (', '.join(ecarts) or 'aucune') + ' (prévues : ' + ', '.join(prevus) + ')')
for k in ecarts:
    if k != '.buildroot.rpms':
        print(f'     {k} : {b.get(k, "<absent>")} -> {a.get(k, "<absent>")}')
rn, rr = neuf.get('buildroot', {}).get('rpms', []), ref.get('buildroot', {}).get('rpms', [])
cle = lambda r: json.dumps(r, sort_keys=True)
sn, sr = {cle(r) for r in rn}, {cle(r) for r in rr}
dire(len(rn) == len(rr) == 222 and sn == sr,
     f'C2 rpm du buildroot, tous les champs : ici {len(rn)}, verrou_derivee {len(rr)} ; seulement ici {len(sn - sr)} ; seulement dans verrou_derivee {len(sr - sn)}')
for x in sorted(sn - sr)[:10]: print('     seulement ici :', x)
for x in sorted(sr - sn)[:10]: print('     seulement dans verrou_derivee :', x)
bs, cf = neuf.get('bootstrap', {}), neuf.get('config', {})
dire(bs.get('pull_digest') == pull, f'C3 bootstrap.pull_digest égal au digest de l\'image de M1b : {bs.get("pull_digest")}')
dire(cf.get('bootstrap_image') == image, f'C3 config.bootstrap_image égal à l\'image de M1b : {cf.get("bootstrap_image")}')
dire(cf.get('bootstrap_image_ready') is True, f'C3 config.bootstrap_image_ready : {cf.get("bootstrap_image_ready")}')
dire(bs.get('id') == ident, f'C4 bootstrap.id égal au digest de la configuration de l\'image, relu dans Zot : {bs.get("id")}')
dire(re.fullmatch('[0-9a-f]{64}', str(bs.get('image_digest'))) is not None,
     f'C5 bootstrap.image_digest présent, 64 caractères hexadécimaux : {bs.get("image_digest")} (verrou_derivee : {ref.get("bootstrap", {}).get("image_digest")})')
print(f'bilan de la comparaison : {ko} KO')
sys.exit(1 if ko else 0)
PY
}

controles_cfg() { # sha256-de-la-configuration-livrée digest-du-bootstrap : journal $T/verrou-derivee-cfg.log du pod
  attendu "V1 configuration de base du pod égale à MOCK_CFG de s1.sh" "$(champ verrou-derivee-cfg 'configuration de base, image du pod')" \
    "sha256 $MOCK_CFG_SHA"
  attendu "V1 configuration dérivée livrée dans le pod" "$(champ verrou-derivee-cfg 'configuration dérivée livrée')" "sha256 $1"
  attendu "V2 podman pull du bootstrap par le pod" "$(champ verrou-derivee-cfg 'podman pull, image dérivée' | cut -d' ' -f1-2)" "rc 0"
  attendu "V2 bootstrap tiré, inspect" "$(champ verrou-derivee-cfg 'image dérivée, inspect')" "$2 linux/amd64"
}

controles_journaux() { # journaux du pod dans $T (verrou-derivee, -repli, -boot) et verrou copié $T/verrou.json
  local s
  attendu "V3 mock --buildsrpm" "$(champ verrou-derivee 'mock --buildsrpm (image dérivée)' | cut -d' ' -f1-2)" "rc 0"
  attendu "V3 mock --calculate-build-dependencies" "$(champ verrou-derivee 'mock --calculate-build-dependencies' | cut -d' ' -f1-2)" "rc 0"
  attendu "V3 root.log : bootstrap non mis à jour, car prêt" \
    "$(grep -c 'Not updating bootstrap chroot, bootstrap_image_ready=True$' "$T/verrou-derivee.log")" 2
  attendu "V4 repli sans image : trois fichiers lus, zéro ligne chacun" "$(grep -c ' : 0 ligne(s) de repli sans image$' "$T/verrou-derivee-repli.log")" 3
  attendu "V5 bootstrap de mock contre image tirée : lignes propres à l'un ou à l'autre" "$(grep -c '^seulement dans' "$T/verrou-derivee-boot.log")" 0
  attendu "V5 bootstrap de mock et image lus (rpm -qa rc 0)" "$(grep -c ': rpm -qa rc 0, ' "$T/verrou-derivee-boot.log")" 2
  echo "V5 lignes communes : $(champ verrou-derivee-boot 'lignes communes')"
  [ -s "$T/verrou.json" ] || { echo "KO   V6 aucun verrou produit" >&2; exit 1; }
  s=$(sha256sum < "$T/verrou.json" | cut -c1-64)
  attendu "V6 verrou copié égal à celui du pod (sha256)" "$(sed -n 's/^verrou : [^ ]* [0-9]* octets, sha256 //p' "$T/verrou-derivee.log" | head -1)" "$s"
  attendu "V6 lignes du verrou au motif jeton|token" "$(grep -c -i -E 'jeton|token' "$T/verrou.json" || true)" 0
}

etape_verrou() {
  local n=$N-05-verrou bd=$DIGEST_BOOTSTRAP boot_d=$REG/$DEPOT_BOOTSTRAP@$DIGEST_BOOTSTRAP c=$T/$CFG_DERIVE.cfg f
  find "$T" -maxdepth 1 -name verrou.json -delete
  gardes "$n"
  echo "## pod : image $REG/$DEPOT_OUTILLAGE@$DIGEST_OUTILLAGE ; isolation : $ISOLATION ; configuration : $CFG_DERIVE (bootstrap_image_ready=True)"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$n" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$n" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  livrer "$n" "/etc/mock/$CFG_DERIVE.cfg" "$c"
  dans "$n" outils <<< 'rpm -q mock mock-core-configs podman python3-dnf 2>&1 | sed "s/^/paquet de l outillage : /"; true'
  sed -e "s|@CFG@|$CFG|g" -e "s|@CFG_DERIVE@|$CFG_DERIVE|g" -e "s|@DERIVEE@|$boot_d|g" <<<"$SONDE_CFG_DERIVEE" \
    | dans "$n" verrou-derivee-cfg
  ( controles_cfg "$(sha256sum < "$c" | cut -c1-64)" "$bd" ) || { pod_retirer "$n"; exit 1; }
  sed -e "s|@CFG_PRET@|$CFG_DERIVE|g" -e "s|@ISO@|$ISOLATION|g" -e "s|(image prête)|(image dérivée)|" \
    -e "s|--resultdir=/w/res-verrou --calculate-build-dependencies |--resultdir=/w/res-verrou --calculate-build-dependencies --no-cleanup-after |" \
    <<<"$SONDE_VERROU" | dans "$n" verrou-derivee
  dans "$n" verrou-derivee-repli <<<"$SONDE_REPLI"
  sed -e "s|@CFG@|$CFG_DERIVE|g" -e "s|@BOOT@|$boot_d|g" -e "s|de rockylinux:9\.7 brut|de l'image dérivée|g" \
    -e "s|dans rockylinux:9\.7 brut|dans l'image dérivée|g" -e "s|rockylinux:9\.7 brut lu|image dérivée lue|g" \
    -e "s|rockylinux:9\.7 brut|image dérivée|g" -e "s|-brut\.|-derivee.|g" <<<"$SONDE_BOOT" | dans "$n" verrou-derivee-boot
  kubectl exec -n builds "$n" -- sh -c 'for f in /w/res-verrou/root.log /w/res-verrou/build.log; do [ -e "$f" ] && { echo "### $f"; tail -n 400 "$f"; }; done
    for f in /w/verrou-srpm.log /w/verrou-calc.log; do [ -e "$f" ] && { echo "### $f"; tail -n 60 "$f"; }; done; true' \
    < /dev/null 2>&1 | sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' > "$MOCKLOG" || true
  echo "journaux de mock : $(wc -l < "$MOCKLOG") lignes, resultats/${MOCKLOG##*/}"
  f=$(kubectl exec -n builds "$n" -- sh -c 'ls /w/res-verrou/*.json 2>/dev/null | head -1' < /dev/null || true)
  [ -z "$f" ] || kubectl exec -n builds "$n" -- cat "$f" < /dev/null > "$T/verrou.json" || echo "copie du verrou : code non nul"
  pod_retirer "$n"
  echo "## contrôles, sur les journaux du pod et le verrou copié"
  controles_journaux
  cp "$T/verrou.json" "$OUT"
  echo "verrou écrit : resultats/${OUT##*/}, sha256 $(sha256sum < "$OUT" | cut -c1-64), $(stat -c %s "$OUT") octets"
  comparer_verrou "$OUT" "$VERROU_REF" "$bd" "$boot_d" "$(sed 's/^sha256://' "$T/config-bootstrap")"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then lancer "$N-verrou" "05 cascade de M1b, verrou" "$@"; fi
