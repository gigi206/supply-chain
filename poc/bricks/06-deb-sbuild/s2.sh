#!/usr/bin/env bash
# Brique 06, jalon S2 (préparé à sec le 10/11/2026 à partir de 15:43 UTC, NON LANCÉ) : chroot de sbuild sans dépendances
# préinstallées (D2 a), construit deux fois ; fermeture du .buildinfo résolue sur l'instantané, poussée dans Zot fichier par
# fichier, puis restaurée par digest. Prédictions : resultats/s2-predictions.md, écrites et commitées avant toute exécution.
#   buildinfo    hôte seul, hors ligne (sous unshare -rn) : InRelease de l'instantané revérifié par gpgv (clés et fichiers de
#                l'étape prealables de s1.sh, déjà sur l'hôte) ; Packages.xz contrôlé par InRelease ; .buildinfo de sample-app
#                reconstitué depuis le journal de sbuild archivé (resultats/s1b-relance-sbuild.log), comparé à l'empreinte que
#                le .changes du même journal lui donne ; chaque paquet de Installed-Build-Depends cherché (nom, version) dans
#                Packages : liste attendue de la fermeture (fichier du pool, sha256, taille), archivée
#   racine       pod Kata privilégié, root, image d'amorce, label tekton.dev/task=prefetch-deb (sortie prefetch-deb-sortie
#                de la 08c : DNS et adresses publiques en 80) : apt sur l'instantané, mmdebstrap épinglé ; deux archives
#                --variant=buildd sans --include (chroot-a, chroot-b), mêmes options que le chroot de s1.sh ; puis
#                apt-get download des paquets de la liste attendue ; .deb contrôlés sur l'hôte contre Packages ; chroot-a et
#                fermeture rapatriés par kubectl exec, empreintes comparées
#   fermeture    écriture dans Zot (compte poc-ecriture), définitive : closure.sh de la brique 03 (un fichier par couche,
#                manifeste déterministe), poussée deux fois sous deux tags : même digest attendu ; digest de chaque couche
#                comparé au SHA256 de Packages
#   restauration lecture dans Zot : pull par digest dans un répertoire vide, chaque fichier comparé à la liste attendue
# Hors S2 : S3 (deux builds hors ligne depuis la fermeture restaurée) ; image sous builders/ (étape à part, accord à part) ;
# déduplication entre deux fermetures (il n'en existe qu'une : voir les prédictions).
# Retrait : Zot n'autorise pas la suppression ; le dépôt de la fermeture est définitif.
# Additif du 10/11/2026, 15:53 UTC : étape buildinfo lancée à 15:50:39 UTC (code 0) ; racine, fermeture et restauration NON LANCÉES.
#
# Usage (racine du dépôt, sous bash pour relever le code) :
#   DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s2.sh <étape>…   (journal : resultats/s2-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
SNAP=20261105T000000Z
MIROIR=http://snapshot.debian.org/archive/debian/$SNAP   # http : l'amorce n'a pas de certificats ; intégrité par InRelease
SOURCE_LISTE="deb [check-valid-until=no] $MIROIR trixie main"
CLES="B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8 04B54C3CDCA79751B16BC6B5225629DF75B188BD 41587F7DB8C774BCCF131416762F67A0B2C39DE4"
V_MMDEBSTRAP=1.5.7-1+deb13u1
AMORCE_DIGEST=sha256:7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392   # trixie-20261104-slim, amd64 (audit du 05/11)
AMORCE=$REG/amont/library/debian@$AMORCE_DIGEST
DEPOT_FERMETURE=${DEPOT_FERMETURE:-deps/sample-app/deb-buildinfo}   # nom du jalon S2 (README) et du doc 02, §4
BUILDINFO=sample-app_1.0.0-1_amd64.buildinfo
JOURNAL_SBUILD=$R/s1b-relance-sbuild.log   # passage s1b, sbuild rc 0, deb 0b489d43…
DEB_S1=0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5
CLOSURE=$here/../03-deps-closure/closure.sh
LIMITES='{"cpu": "2", "memory": "6Gi"}'
TMPFS=4Gi
PRIVILEGIE='{"privileged": true, "allowPrivilegeEscalation": true}'
T1=$W/s1-06   # étape prealables de s1.sh : InRelease, Packages.xz, clés de ftp-master
T=$W/s2-06
mkdir -p "$T"
umask 022

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
champ() { sed -n "s/^$2[[:space:]]*:[[:space:]]*//p" "$T/$1.log" | head -1; }

# pod_spec, pod_demarrer, dans, pod_retirer, controle_debs : repris de s1.sh (même forme de pod, même contrôle des .deb)
pod_spec() { # nom runtimeClass|- image uid contexte-JSON [label tekton.dev/task]
  jq -n --arg n "$1" --arg rc "$2" --arg i "$3" --argjson u "$4" --argjson sc "$5" --argjson l "$LIMITES" --arg t "$TMPFS" --arg lb "${6:-}" '{
    apiVersion: "v1", kind: "Pod", metadata: ({name: $n, namespace: "builds"} + (if $lb == "" then {} else {labels: {"tekton.dev/task": $lb}} end)),
    spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: ($u != 0), runAsUser: $u, runAsGroup: $u, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: $t}}],
      containers: [{name: "s2", image: $i, command: ["sleep", "7200"], securityContext: $sc,
        resources: {requests: $l, limits: $l}, volumeMounts: [{name: "w", mountPath: "/w"}]}]}
      + (if $rc == "-" then {} else {runtimeClassName: $rc} end))}' > "$T/$1.json"
}

pod_demarrer() {
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true </dev/null >/dev/null
  kubectl create -f "$T/$1.json" </dev/null >/dev/null
  kubectl wait -n builds "pod/$1" --for=condition=Ready --timeout=300s </dev/null >/dev/null \
    || { kubectl describe pod -n builds "$1" </dev/null | tail -n 20 >&2; echo "KO   pod $1 non prêt" >&2; exit 1; }
  echo "### $1 ($(jq -r '"runtimeClassName \(.spec.runtimeClassName // "-"), uid \(.spec.securityContext.runAsUser), label \(.metadata.labels["tekton.dev/task"] // "-")"' "$T/$1.json")) : prêt"
}

dans() {
  local rc=0
  kubectl exec -i -n builds "$1" -- sh -s > "$T/$2.log" 2>&1 || rc=$?
  sed 's/^/     /' "$T/$2.log"
  echo "     (code de l'exec : $rc)"
}

pod_retirer() { kubectl delete pod -n builds "$1" --wait=false </dev/null >/dev/null; echo "pod $1 supprimé"; }

controle_debs() { # journal : chaque « deb <origine> <fichier> <sha256> » comparé au Packages vérifié
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
        f = re.sub(r'_[0-9]+%3[aA]', '_', c[2])
        if pk.get(f) != c[3]: ko.append(c[1] + ' ' + c[2])
print('paquets contrôlés : ' + ', '.join(f'{k} {v}' for k, v in n.items()))
print(('OK   ' if not ko and n else 'KO   ') + f'sha256 des .deb conformes au Packages vérifié : {sum(n.values()) - len(ko)} sur {sum(n.values())}')
for k in ko[:10]: print('     écart : ' + k)
sys.exit(1 if ko or not n else 0)
PY
}

conforme() { # répertoire : « fichier sha256 » de chaque fichier, comparé à la liste attendue (fichier du pool, sha256)
  local d=$1
  diff <(cd "$d" && find . -type f -printf '%P\n' | sort | xargs -r sha256sum | awk '{print $2, $1}') \
       <(awk '{print $1, $2}' "$T/fermeture.attendue" | sort) > "$T/conforme.diff" \
    && echo "OK   $d : $(find "$d" -type f | wc -l) fichiers, empreintes identiques à la liste attendue" \
    || { head -n 20 "$T/conforme.diff" >&2; echo "KO   $d : écart avec la liste attendue" >&2; exit 1; }
}

etape_buildinfo() {
  local d=$T1/hote s
  [ -s "$d/InRelease" ] && [ -s "$d/Packages.xz" ] && [ -s "$d/cles.gpg" ] || { echo "KO   étape prealables de s1.sh absente" >&2; exit 1; }
  echo "## instantané $SNAP, revérifié hors ligne"
  s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/InRelease" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' | sort | paste -sd' ')
  attendu "signataires d'InRelease (clés primaires)" "$s" "$(tr ' ' '\n' <<<"$CLES" | sort | paste -sd' ')"
  echo "InRelease : sha256 $(sha256sum < "$d/InRelease" | cut -c1-64), $(sed -n 's/^Date: //p' "$d/InRelease")"
  s=$(awk '/^SHA256:/ {f = 1; next} /^[A-Z]/ {f = 0} f && $3 == "main/binary-amd64/Packages.xz" {print $1}' "$d/InRelease")
  attendu "Packages.xz contrôlé par InRelease" "$(sha256sum < "$d/Packages.xz" | cut -c1-64)" "$s"
  xz -dc "$d/Packages.xz" > "$T/Packages"
  echo "## .buildinfo reconstitué depuis ${JOURNAL_SBUILD#"$here"/}"
  # Premier bloc « Format: 1.0 » jusqu'à la première ligne vide ; empreinte attendue : ligne Checksums-Sha256 du .changes
  awk '/^Format: 1.0$/ {f = 1} f && /^$/ {exit} f' "$JOURNAL_SBUILD" > "$R/s2-$BUILDINFO"
  s=$(grep -m1 -E "^ [0-9a-f]{64} [0-9]+ $BUILDINFO$" "$JOURNAL_SBUILD" | awk '{print $1}')
  attendu "sha256 du .buildinfo (.changes du journal)" "$(sha256sum < "$R/s2-$BUILDINFO" | cut -c1-64)" "$s"
  attendu "deb décrit par le .buildinfo (deb de s1b)" "$(awk '/^Checksums-Sha256:/ {f = 1; next} /^[A-Z]/ {f = 0} f && $3 ~ /\.deb$/ {print $1}' "$R/s2-$BUILDINFO")" "$DEB_S1"
  echo "## Installed-Build-Depends contre Packages"
  python3 -I - "$T/Packages" "$R/s2-$BUILDINFO" "$T/fermeture.attendue" "$T/fermeture.apt" <<'PY'
import re, sys
pk = {}
for para in open(sys.argv[1], encoding='utf-8').read().split('\n\n'):
    d = dict(l.split(': ', 1) for l in para.split('\n') if ': ' in l and not l.startswith(' '))
    if 'Filename' in d and d.get('Architecture') in ('amd64', 'all'):
        pk.setdefault((d['Package'], d['Version']), []).append(d)
bi = open(sys.argv[2], encoding='utf-8').read()
m = re.search(r'^Installed-Build-Depends:\n((?: .*\n?)+)', bi, re.M)
dep = [re.fullmatch(r'\s*(\S+) \(= (\S+)\),?', l) for l in m.group(1).splitlines()]
if not all(dep): sys.exit('KO   ligne de Installed-Build-Depends illisible')
dep = [(x.group(1).split(':')[0], x.group(2)) for x in dep]
manque = [f'{p}={v}' for p, v in dep if len(pk.get((p, v), [])) != 1]
lignes = sorted((pk[(p, v)][0]['Filename'].rsplit('/', 1)[1], pk[(p, v)][0]['SHA256'], int(pk[(p, v)][0]['Size']), pk[(p, v)][0]['Architecture'])
                for p, v in dep if (p, v) not in [tuple(x.split('=', 1)) for x in manque])
print(f'Installed-Build-Depends : {len(dep)} paquets, {len(set(dep))} distincts')
print(('OK   ' if not manque else 'KO   ') + f'présents une fois dans Packages (amd64 ou all) : {len(dep) - len(manque)} sur {len(dep)}')
for x in manque[:10]: print('     absent ou ambigu : ' + x)
print(f'fermeture attendue : {len(lignes)} fichiers, {sum(x[2] for x in lignes)} octets ; '
      f'amd64 {sum(x[3] == "amd64" for x in lignes)}, all {sum(x[3] == "all" for x in lignes)}')
for x in sorted(lignes, key=lambda x: -x[2])[:5]: print(f'     plus gros : {x[0]} {x[2]} octets')
with open(sys.argv[3], 'w') as f:
    for x in lignes: f.write(f'{x[0]} {x[1]} {x[2]}\n')
with open(sys.argv[4], 'w') as f:
    for p, v in dep: f.write(f'{p}={v}\n')
sys.exit(1 if manque else 0)
PY
  cp "$T/fermeture.attendue" "$R/s2-fermeture-attendue.txt"
  echo "liste attendue archivée : resultats/s2-fermeture-attendue.txt (fichier sha256 taille)"
}

# Script du pod racine (root). Mêmes options de mmdebstrap que le chroot de s1.sh, sans --include (D2 a : les dépendances de
# build viendront de la fermeture restaurée, en S3).
RACINE='set -u
echo "invité : $(uname -r), $(nproc) vCPU, $(awk "/MemTotal/ {print \$2}" /proc/meminfo) kB ; /w : $(awk "\$2 == \"/w\" {print \$3}" /proc/mounts)"
rm -f /etc/apt/sources.list.d/* /etc/apt/apt.conf.d/docker-clean
echo "@SOURCE@" > /etc/apt/sources.list
t=$(date +%s)
apt-get -q -o Acquire::Retries=2 update > /w/update.log 2>&1; echo "apt-get update : rc $? en $(($(date +%s) - t)) s"
echo "InRelease : sha256 $(sha256sum /var/lib/apt/lists/*_InRelease | cut -c1-64)"
t=$(date +%s)
apt-get -q -y --no-install-recommends -o APT::Keep-Downloaded-Packages=true install mmdebstrap=@V_MMDEBSTRAP@ > /w/install.log 2>&1
echo "installation de mmdebstrap : rc $? en $(($(date +%s) - t)) s ; $(mmdebstrap --version 2>&1)"
for f in /var/cache/apt/archives/*.deb; do echo "deb amorce ${f##*/} $(sha256sum < $f | cut -c1-64)"; done
export SOURCE_DATE_EPOCH=@SDE@ TMPDIR=/w
mm() { # nom : archive /w/<nom>.tar, variante buildd, sans --include
  n=$1
  t=$(date +%s)
  mmdebstrap --mode=root --variant=buildd --format=tar --skip=cleanup/apt/lists \
    --customize-hook="for f in \"\$1\"/var/cache/apt/archives/*.deb; do echo \"deb $n \${f##*/} \$(sha256sum < \$f | cut -c1-64)\"; done" \
    trixie /w/$n.tar "@SOURCE@" > /w/mm-$n.log 2>&1
  r=$?
  grep "^deb $n " /w/mm-$n.log
  echo "mmdebstrap $n : rc $r en $(($(date +%s) - t)) s, $(stat -c %s /w/$n.tar 2>/dev/null) octets, sha256 $(sha256sum < /w/$n.tar 2>/dev/null | cut -c1-64)"
  [ $r = 0 ] || grep -i -E "error|E:|failed" /w/mm-$n.log | head -n 5
}
mm chroot-a
mm chroot-b
mkdir -p /w/fermeture && cd /w/fermeture
t=$(date +%s)
xargs apt-get -q -o Acquire::Retries=2 download < /w/fermeture.apt > /w/download.log 2>&1
echo "apt-get download : rc $? en $(($(date +%s) - t)) s, $(ls | wc -l) fichier(s), $(du -sb . | cut -f1) octets"
grep -E "^(E|W):" /w/download.log | head -n 5
for f in /w/fermeture/*.deb; do echo "deb fermeture ${f##*/} $(sha256sum < $f | cut -c1-64)"; done'

etape_racine() {
  local s a b
  [ -s "$T/fermeture.apt" ] && [ -s "$T/Packages" ] || { echo "KO   lancer d'abord l'étape buildinfo" >&2; exit 1; }
  s=$(date -u -d "$(sed -n 's/^Date: //p' "$T1/hote/InRelease")" +%s)
  pod_spec s2-racine kata "$AMORCE" 0 "$PRIVILEGIE" prefetch-deb
  pod_demarrer s2-racine
  kubectl exec -i -n builds s2-racine -- sh -c 'cat > /w/fermeture.apt' < "$T/fermeture.apt"
  sed -e "s|@SOURCE@|$SOURCE_LISTE|g" -e "s|@V_MMDEBSTRAP@|$V_MMDEBSTRAP|g" -e "s|@SDE@|$s|g" <<<"$RACINE" | dans s2-racine racine
  attendu "InRelease lu par apt dans le pod = InRelease vérifié sur l'hôte" "$(champ racine InRelease | sed 's/^sha256 //')" "$(sha256sum < "$T1/hote/InRelease" | cut -c1-64)"
  controle_debs "$T/racine.log" || { pod_retirer s2-racine; echo "KO   empreintes des .deb" >&2; exit 1; }
  a=$(sed -n 's/^mmdebstrap chroot-a : rc 0 .*sha256 \([0-9a-f]\{64\}\)$/\1/p' "$T/racine.log")
  b=$(sed -n 's/^mmdebstrap chroot-b : rc 0 .*sha256 \([0-9a-f]\{64\}\)$/\1/p' "$T/racine.log")
  [ -n "$a" ] && [ -n "$b" ] || { pod_retirer s2-racine; echo "KO   mmdebstrap" >&2; exit 1; }
  attendu "chroot-b identique à chroot-a" "$b" "$a"
  kubectl exec -n builds s2-racine -- cat /w/chroot-a.tar </dev/null > "$T/chroot.tar"
  attendu "chroot rapatrié" "$(sha256sum < "$T/chroot.tar" | cut -c1-64)" "$a"
  rm -rf -- "${T:?}/fermeture" && mkdir -p "$T/fermeture"
  kubectl exec -n builds s2-racine -- tar -C /w/fermeture -cf - . </dev/null | tar -xf - -C "$T/fermeture"
  pod_retirer s2-racine
  # apt garde l'époque dans le nom (« _1%3a… ») ; le pool et la liste attendue non : renommage avant comparaison
  (cd "$T/fermeture" && for f in *%3[aA]*.deb; do [ -e "$f" ] && mv -- "$f" "$(sed 's/_[0-9]*%3[aA]/_/' <<<"$f")"; done; true)
  conforme "$T/fermeture"
}

oras_zot() { echo "--registry-config $T/zot.json --ca-file $P/ca-poc.crt"; }   # chemins sans espace (contrôlé ci-dessous)

etape_fermeture() {
  local r1 r2 d
  [ -d "$T/fermeture" ] || { echo "KO   lancer d'abord l'étape racine" >&2; exit 1; }
  case "$T$P" in *' '*) echo "KO   chemin avec espace" >&2; exit 1 ;; esac
  conforme "$T/fermeture"
  auth_zot "$T/zot.json"
  r1=$(ORAS_OPTS=$(oras_zot) "$CLOSURE" push "$T/fermeture" "$REG_HOTE/$DEPOT_FERMETURE:s2")
  r2=$(ORAS_OPTS=$(oras_zot) "$CLOSURE" push "$T/fermeture" "$REG_HOTE/$DEPOT_FERMETURE:s2-bis")
  echo "fermeture : ${r1/$REG_HOTE/$REG}"
  attendu "digest du second envoi" "${r2#*@}" "${r1#*@}"
  d=${r1#*@}; echo "$d" > "$T/fermeture.digest"
  # shellcheck disable=SC2046
  # Corrigé à 16:25 UTC le 10/11/2026, NON REJOUÉ : oras 1.3.6 refuse --no-tty pour manifest fetch (« unknown flag », 16:23 UTC)
  oras manifest fetch $(oras_zot) "$REG_HOTE/$DEPOT_FERMETURE@$d" > "$T/manifest.json"
  attendu "couches du manifeste" "$(jq '.layers | length' "$T/manifest.json")" "$(wc -l < "$T/fermeture.attendue")"
  attendu "digest de chaque couche = SHA256 de Packages (fichier par fichier)" \
    "$(jq -r '.layers[] | "\(.annotations["org.opencontainers.image.title"]) \(.digest | ltrimstr("sha256:"))"' "$T/manifest.json" | sort | sha256sum | cut -c1-64)" \
    "$(awk '{print $1, $2}' "$T/fermeture.attendue" | sort | sha256sum | cut -c1-64)"
}

etape_restauration() {
  local d
  d=$(cat "$T/fermeture.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape fermeture" >&2; exit 1; }
  auth_zot "$T/zot.json"
  rm -rf -- "${T:?}/restauree"
  ORAS_OPTS=$(oras_zot) "$CLOSURE" pull "$REG_HOTE/$DEPOT_FERMETURE@$d" "$T/restauree"
  echo "restaurée depuis ${REG}/$DEPOT_FERMETURE@$d"
  conforme "$T/restauree"
}

lancer s2 "06 S2" "$@"
