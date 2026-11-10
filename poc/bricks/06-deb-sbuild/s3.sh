#!/usr/bin/env bash
# Brique 06, jalon S3 (préparé à sec le 10/11/2026 après le « continue » de 16:36:51 UTC ; simulation lancée à 16:44:06 UTC,
# code 0 ; restauration, builds et comparaison NON LANCÉES) : deux builds de sample-app par sbuild,
# sans accès à l'instantané, depuis la fermeture de S2 restaurée par digest, dans le chroot buildd sans dépendances de S2 (D2 a).
# Prédictions : resultats/s3-predictions.md, écrites et commitées avant toute exécution.
#   simulation   hôte seul, hors ligne (apt sous unshare -rn) : apt de l'hôte simule l'installation des dépendances de build de
#                sample-app (paquet factice : Build-Depends et build-essential, comme le paquet factice de sbuild) sur l'état dpkg
#                du chroot de S2, avec la fermeture pour seule source ; paquets simulés comparés à Installed-Build-Depends
#   restauration lecture dans Zot : deux pulls par digest de la fermeture de S2, chacun dans un répertoire vide, chacun comparé
#                à la liste attendue
#   builds       deux pods Kata privilégiés, UID 1000, l'un après l'autre, SANS label (builds-sans-internet de la 08c : aucune
#                adresse publique) ; image d'essai de s1b (sbuild, mmdebstrap, uidmap, iproute2), dont le chroot embarqué
#                (440ba93b…, dépendances préinstallées) n'est PAS utilisé : le chroot de S2 (e0b1f37c…) est copié dans /w et
#                passé par --chroot ; fermeture restaurée n copiée dans /w/fermeture et revérifiée dans le pod avant sbuild ;
#                témoin négatif vers snapshot.debian.org:80 ; sbuild --chroot-mode=unshare --extra-package=/w/fermeture, sources
#                de l'instantané neutralisées dans le chroot avant la mise en place d'apt (--chroot-setup-commands) ;
#                répertoire de build rapatrié, journal de sbuild archivé (lignes jeton|token retirées)
#   comparaison  hôte seul, hors ligne : sha256 des deux deb ; Installed-Build-Depends des deux .buildinfo contre celui de S2 ;
#                champs différents entre les .buildinfo ; adresses des lignes Get des journaux ; paquets installés par sbuild
#                contre la simulation
# Hors S3 : diffoscope (absent de l'hôte et de l'image : son installation se demande au propriétaire) ; image sous builders/ ;
# Tekton, Chains et deb dans Zot (S4) ; tests négatifs (S5).
# Retrait : rien d'écrit dans Zot ; pods supprimés à la fin de chaque build.
#
# Usage (racine du dépôt, sous bash pour relever le code) :
#   DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s3.sh <étape>…   (journal : resultats/s3-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
DEPOT_FERMETURE=deps/sample-app/deb-buildinfo
FERMETURE_DIGEST=sha256:3a0e54aee9c2bd8967be496ae49af62ebf432046321f6dfa5acc00df53c3677b   # S2, 16:31 UTC
CHROOT_S2=e0b1f37ce1e7e46a98d020fd4c4f6ee85e65f6f5518232534dad02772cca23fa                   # buildd sans --include (S2)
IMAGE_DIGEST=sha256:d8041f9cf7254a1e73523dc1b01e4065c0c9f9f4e7f8c9dc4e3c5fd656f495a1          # essais-06/sbuild-debian13:s1b
IMAGE=$REG/essais-06/sbuild-debian13@$IMAGE_DIGEST
DEB_S1=0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5
BUILDINFO=sample-app_1.0.0-1_amd64.buildinfo
BUILDINFO_S2=$R/s2-$BUILDINFO
CLOSURE=$here/../03-deps-closure/closure.sh
PKG=${PACKAGING_DIR:-$HOME/.cache/supply-chain-poc/packaging}
DSC=sample-app_1.0.0-1.dsc
LISTES=/var/lib/apt/lists/snapshot.debian.org_archive_debian_20261105T000000Z_dists_trixie   # listes de l'instantané dans le chroot
LIMITES='{"cpu": "2", "memory": "6Gi"}'
TMPFS=4Gi
PRIVILEGIE='{"privileged": true, "allowPrivilegeEscalation": true}'
T1=$W/s1-06   # SHA256SUMS.s1 (sources de sample-app)
T2=$W/s2-06   # chroot.tar, Packages, fermeture.attendue, fermeture.apt
T=$W/s3-06
mkdir -p "$T"
umask 022

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }

# pod_spec, pod_demarrer, dans, pod_retirer : repris de s2.sh (même forme de pod)
pod_spec() { # nom runtimeClass|- image uid contexte-JSON [label tekton.dev/task]
  jq -n --arg n "$1" --arg rc "$2" --arg i "$3" --argjson u "$4" --argjson sc "$5" --argjson l "$LIMITES" --arg t "$TMPFS" --arg lb "${6:-}" '{
    apiVersion: "v1", kind: "Pod", metadata: ({name: $n, namespace: "builds"} + (if $lb == "" then {} else {labels: {"tekton.dev/task": $lb}} end)),
    spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: ($u != 0), runAsUser: $u, runAsGroup: $u, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: $t}}],
      containers: [{name: "s3", image: $i, command: ["sleep", "7200"], securityContext: $sc,
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

conforme() { # répertoire : « fichier sha256 » de chaque fichier, comparé à la liste attendue de S2
  local d=$1
  diff <(cd "$d" && find . -type f -printf '%P\n' | sort | xargs -r sha256sum | awk '{print $2, $1}') \
       <(awk '{print $1, $2}' "$T2/fermeture.attendue" | sort) > "$T/conforme.diff" \
    && echo "OK   $d : $(find "$d" -type f | wc -l) fichiers, empreintes identiques à la liste attendue" \
    || { head -n 20 "$T/conforme.diff" >&2; echo "KO   $d : écart avec la liste attendue" >&2; exit 1; }
}

prealables_hote() {
  [ -s "$T2/fermeture.attendue" ] && [ -s "$T2/fermeture.apt" ] && [ -s "$T2/Packages" ] && [ -s "$T2/chroot.tar" ] \
    || { echo "KO   fichiers de S2 absents de $T2" >&2; exit 1; }
  attendu "chroot de S2" "$(sha256sum < "$T2/chroot.tar" | cut -c1-64)" "$CHROOT_S2"
}

etape_simulation() {
  local S=$T/simulation
  prealables_hote
  rm -rf -- "$S" && mkdir -p "$S/depot" "$S/listes/partial" "$S/cache/archives/partial" "$S/vide"
  tar -xOf "$T2/chroot.tar" ./var/lib/dpkg/status > "$S/status"
  # Dépôt simulé : les 162 paragraphes de Packages de la fermeture, plus un paquet factice (dépendances de sbuild : Build-Depends
  # de debian/control et build-essential ; Rules-Requires-Root: no, donc pas de fakeroot)
  python3 -I - "$T2/Packages" "$T2/fermeture.attendue" "$S/depot/Packages" "$PKG/$DSC" <<'PY'
import re, sys
voulu = {l.split()[0] for l in open(sys.argv[2])}
bd = re.search(r'^Build-Depends: (.*)$', open(sys.argv[4], encoding='utf-8').read(), re.M).group(1)
out = []
for para in open(sys.argv[1], encoding='utf-8').read().split('\n\n'):
    m = re.search(r'^Filename: (\S+)$', para, re.M)
    if m and m.group(1).rsplit('/', 1)[1] in voulu: out.append(para.strip('\n'))
print(f'paragraphes de la fermeture : {len(out)} ; Build-Depends du .dsc : {bd}')
out.append('Package: sbuild-build-depends-main-dummy\nVersion: 0.invalid.0\nArchitecture: amd64\n'
           f'Depends: {bd}, build-essential\nFilename: ./factice.deb\nSize: 1\nSHA256: 00\nDescription: simulation')
open(sys.argv[3], 'w').write('\n\n'.join(out) + '\n')
PY
  echo "deb [trusted=yes] file:$S/depot ./" > "$S/sources.list"
  local o="-o APT::Sandbox::User=root -o Dir::State::status=$S/status -o Dir::State::Lists=$S/listes -o Dir::Cache=$S/cache"
  o="$o -o Dir::Etc::sourcelist=$S/sources.list -o Dir::Etc::sourceparts=$S/vide -o Dir::Etc::preferencesparts=$S/vide"
  o="$o -o APT::Architecture=amd64 -o APT::Architectures=amd64 -o Debug::NoLocking=1 -o APT::Install-Recommends=false"
  echo "apt de l'hôte : $(apt-get --version | head -1) (celui du chroot : 3.0.3)"
  unshare -rn sh -c "echo \"interfaces : \$(ip -o link | awk '{print \$2}' | paste -sd' ')\"; apt-get -q $o update >/dev/null && apt-get -s $o install sbuild-build-depends-main-dummy" \
    > "$S/sim.log" 2>&1 || { tail -n 20 "$S/sim.log" >&2; echo "KO   simulation" >&2; exit 1; }
  head -1 "$S/sim.log"
  grep '^Inst ' "$S/sim.log" | grep -v sbuild-build-depends | sed -E 's/^Inst ([^ ]+) \(([^ ]+) .*/\1=\2/' | sort > "$T/simules.v"
  awk '/^Package:/ {p = $2} /^Version:/ {print p "=" $2}' "$S/status" | sort > "$S/chroot.v"
  sort "$T2/fermeture.apt" > "$S/ibd.v"
  echo "chroot de S2 : $(wc -l < "$S/chroot.v") paquets ; Installed-Build-Depends : $(wc -l < "$S/ibd.v") ; simulés : $(wc -l < "$T/simules.v")"
  echo "Installed-Build-Depends déjà dans le chroot (nom et version) : $(comm -12 "$S/ibd.v" "$S/chroot.v" | wc -l)"
  attendu "Installed-Build-Depends ni dans le chroot ni simulés" "$(comm -23 "$S/ibd.v" <(sort -u "$S/chroot.v" "$T/simules.v") | paste -sd' ')" ""
  attendu "simulés hors Installed-Build-Depends" "$(comm -13 "$S/ibd.v" "$T/simules.v" | paste -sd' ')" ""
  cp "$T/simules.v" "$R/s3-simules.txt"
  echo "liste simulée archivée : resultats/s3-simules.txt (nom=version)"
}

etape_restauration() {
  local n
  case "$T$P" in *' '*) echo "KO   chemin avec espace" >&2; exit 1 ;; esac
  auth_zot "$T/zot.json"
  for n in 1 2; do
    rm -rf -- "${T:?}/restauree-$n"
    ORAS_OPTS="--registry-config $T/zot.json --ca-file $P/ca-poc.crt" "$CLOSURE" pull "$REG_HOTE/$DEPOT_FERMETURE@$FERMETURE_DIGEST" "$T/restauree-$n"
    echo "restauration $n depuis $REG/$DEPOT_FERMETURE@$FERMETURE_DIGEST"
    conforme "$T/restauree-$n"
  done
}

# Script du pod (UID 1000). Les commandes de --chroot-setup-commands sont découpées par sbuild aux espaces, sans shell
# (Build.pm, run_command) : ni guillemets, ni joker. Elles tournent en root dans le chroot, avant la mise en place des dépôts
# internes de sbuild (Build.pm, run_chroot_session_locked).
BUILD='set -u
echo "invité : $(uname -r), $(nproc) vCPU ; uid $(id -u) ; /w : $(awk "\$2 == \"/w\" {print \$3}" /proc/mounts)"
echo "chroot : sha256 $(sha256sum < /w/chroot.tar | cut -c1-64)"
cd /w/fermeture && sha256sum -c --quiet /w/fermeture.sha256 > /w/f.log 2>&1; echo "fermeture revérifiée dans le pod : rc $? ($(ls | wc -l) fichiers) $(head -c 300 /w/f.log)"
cd /w/src && sha256sum -c SHA256SUMS.s1 > /w/s.log 2>&1; echo "sources livrées : rc $? $(paste -sd " " /w/s.log)"
getent hosts snapshot.debian.org > /w/dns.log 2>&1; echo "témoin DNS snapshot.debian.org : rc $?"
timeout 10 bash -c "exec 3<>/dev/tcp/snapshot.debian.org/80" > /w/tcp.log 2>&1; echo "témoin TCP snapshot.debian.org:80 (10 s) : rc $? $(head -c 200 /w/tcp.log)"
mkdir -p /w/home @SORTIE@
export TMPDIR=/w HOME=/w/home
t=$(date +%s)
sbuild --chroot-mode=unshare --chroot=/w/chroot.tar --dist=trixie --arch=amd64 --no-apt-update --no-apt-upgrade \
  --no-apt-distupgrade --no-run-lintian --no-run-autopkgtest --no-run-piuparts --no-source-only-changes --build-dir=@SORTIE@ \
  --extra-package=/w/fermeture \
  "--chroot-setup-commands=truncate -s 0 /etc/apt/sources.list" \
  "--chroot-setup-commands=rm -f @LISTES@_InRelease @LISTES@_main_binary-amd64_Packages" \
  /w/src/@DSC@ > /w/sbuild.out 2>&1
r=$?; echo "sbuild : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || tail -n 25 /w/sbuild.out
for f in @SORTIE@/*.deb; do [ -e "$f" ] && echo "deb produit : ${f##*/} $(sha256sum < "$f" | cut -c1-64)"; done; true'

etape_builds() {
  local n p s
  prealables_hote
  (cd "$PKG" && sha256sum -c --quiet "$T1/SHA256SUMS.s1") || { echo "KO   sources de sample-app" >&2; exit 1; }
  awk '{print $2 "  " $1}' "$T2/fermeture.attendue" > "$T/fermeture.sha256"
  for n in 1 2; do
    [ -d "$T/restauree-$n" ] || { echo "KO   lancer d'abord l'étape restauration" >&2; exit 1; }
    conforme "$T/restauree-$n"
    p=s3-build-$n s=/w/b$n/sortie
    pod_spec "$p" kata "$IMAGE" 1000 "$PRIVILEGIE"
    pod_demarrer "$p"
    kubectl exec -i -n builds "$p" -- sh -c 'cat > /w/chroot.tar' < "$T2/chroot.tar"
    tar -C "$T/restauree-$n" -cf - . | kubectl exec -i -n builds "$p" -- sh -c 'mkdir -p /w/fermeture && tar -xf - -C /w/fermeture'
    kubectl exec -i -n builds "$p" -- sh -c 'cat > /w/fermeture.sha256' < "$T/fermeture.sha256"
    tar -C "$PKG" -cf - sample-app_1.0.0.orig.tar.gz sample-app_1.0.0-1.debian.tar.xz "$DSC" \
      | kubectl exec -i -n builds "$p" -- sh -c 'mkdir -p /w/src && tar -xf - -C /w/src'
    kubectl exec -i -n builds "$p" -- sh -c 'cat > /w/src/SHA256SUMS.s1' < "$T1/SHA256SUMS.s1"
    sed -e "s|@DSC@|$DSC|g" -e "s|@SORTIE@|$s|g" -e "s|@LISTES@|$LISTES|g" <<<"$BUILD" | dans "$p" "build-$n"
    rm -rf -- "${T:?}/build-$n" && mkdir -p "$T/build-$n"
    kubectl exec -n builds "$p" -- tar -C "$s" -cf - . </dev/null | tar -xf - -C "$T/build-$n" || true
    pod_retirer "$p"
    # Journal de sbuild : le fichier .build horodaté (l'autre est un lien vers lui)
    find "$T/build-$n" -maxdepth 1 -type f -name '*Z.build' -exec cat {} + | grep -i -v -E 'jeton|token' > "$R/s3-build-$n-sbuild.log" || true
    echo "journal de sbuild : $(wc -l < "$R/s3-build-$n-sbuild.log") lignes, resultats/s3-build-$n-sbuild.log"
    [ -s "$T/build-$n/$BUILDINFO" ] && cp "$T/build-$n/$BUILDINFO" "$R/s3-build-$n.buildinfo" || echo "KO   .buildinfo absent du build $n" >&2
  done
}

etape_comparaison() {
  local n a b
  for n in 1 2; do [ -s "$R/s3-build-$n.buildinfo" ] || { echo "KO   lancer d'abord l'étape builds" >&2; exit 1; }; done
  a=$(sha256sum < "$T/build-1/sample-app_1.0.0-1_amd64.deb" | cut -c1-64)
  b=$(sha256sum < "$T/build-2/sample-app_1.0.0-1_amd64.deb" | cut -c1-64)
  echo "deb du build 1 : $a"
  echo "deb du build 2 : $b"
  [ "$a" = "$b" ] && echo "OK   deb identiques sur les deux builds" || echo "ÉCART deb différents : diffoscope à demander au propriétaire (deb gardés dans $T/build-1 et $T/build-2)"
  [ "$a" = "$DEB_S1" ] && echo "deb égal à celui de s1b et d'OBS (0b489d43…)" || echo "deb différent de celui de s1b et d'OBS (0b489d43…)"
  python3 -I - "$BUILDINFO_S2" "$R/s3-build-1.buildinfo" "$R/s3-build-2.buildinfo" <<'PY'
import re, sys
def champs(f):
    t = open(f, encoding='utf-8').read()
    d = {}
    for m in re.finditer(r'^([A-Za-z0-9-]+):(.*(?:\n[ \t].*)*)', t, re.M): d[m.group(1)] = m.group(2)
    return d
s2, b1, b2 = (champs(f) for f in sys.argv[1:4])
for nom, b in (('build 1', b1), ('build 2', b2)):
    ok = b.get('Installed-Build-Depends') == s2.get('Installed-Build-Depends')
    print(('OK   ' if ok else 'ÉCART ') + f'Installed-Build-Depends du {nom} identique à celui de S2 (s1b)')
for nom, x, y in (('build 1 et build 2', b1, b2), ('S2 (s1b) et build 1', s2, b1)):
    diff = sorted(k for k in set(x) | set(y) if x.get(k) != y.get(k))
    print(f'champs différents entre {nom} : {", ".join(diff) or "aucun"}')
PY
  for n in 1 2; do
    echo "## journal du build $n"
    echo "lignes Get : $(grep -c -E '^Get:' "$R/s3-build-$n-sbuild.log") ; méthodes : $(grep -E '^Get:' "$R/s3-build-$n-sbuild.log" | awk '{print $2}' | sed 's/:.*//' | sort | uniq -c | awk '{print $2 " " $1}' | paste -sd' ')"
    attendu "lignes Get en http ou https" "$(grep -c -E '^Get:[0-9]+ https?:' "$R/s3-build-$n-sbuild.log" || true)" 0
    grep -E '^Setting up [^ ]+ \(' "$R/s3-build-$n-sbuild.log" | grep -v sbuild-build-depends | sed -E 's/^Setting up ([^ ]+) \(([^)]+)\).*/\1=\2/' | sed 's/:amd64=/=/' | sort -u > "$T/installes-$n.v"
    echo "paquets installés par sbuild (hors paquet factice) : $(wc -l < "$T/installes-$n.v")"
    attendu "installés par sbuild = simulés (nom=version)" "$(diff "$T/installes-$n.v" "$R/s3-simules.txt" | grep -c '^[<>]' || true)" 0
    grep -E '^(Status|Build-Time|Package-Time|Build-Space):' "$R/s3-build-$n-sbuild.log" | paste -sd' '
  done
}

lancer s3 "06 S3" "$@"
