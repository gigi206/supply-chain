#!/usr/bin/env bash
# Brique 06, jalon S6b (contrôle 6 du deb ; décision du propriétaire du 12/11/2026, 08:50:32 UTC, point 3 : chroot reconstruit dans
# sc-replay, domaine de la brique 10, mmdebstrap et sbuild par apt, versions épinglées, sans recommandés, comme busybox-static en R2).
# Prédictions : resultats/s6b-predictions.md, commitées avant tout lancement.
#   releve  ACCORD NOMMÉ DU PROPRIÉTAIRE. Rien installé, rien dans le cluster, rien d'écrit dans Zot ; la seule écriture hors de
#           ~/.cache/supply-chain-poc/06/s6b et de resultats/ est la mise à jour des listes d'apt de sc-replay (sudo apt-get update).
#     hôte (lecture anonyme de Zot, sans vérification de signature : elle se fera dans le domaine) :
#       H1  provenances du deb : tag .att de builds/sample-app-deb@039949f9, une ligne par couche (invocationId, startedOn,
#           finishedOn, nombre d'entrées résolues) et ses entrées ; manifeste du deb gardé pour H2
#       H2  layout du deb reconstruit à partir des seuls octets du deb de S3, hors réseau (unshare -rn), avec les commandes de
#           deb/construire-deb.yaml et le tar de l'hôte ; manifeste comparé octet à octet à celui de Zot, digest à 039949f9
#       H3  taille des entrées que le domaine devra transporter : fermeture deb bb7599a2, fermeture des sources 50dc73f7,
#           packaging c1719b13 (manifestes seulement)
#     VM sc-replay (ssh, clés du domaine de la 10) :
#       V1  vCPU, mémoire, disque, nombre de paquets ; mmdebstrap ou sbuild déjà présents ?
#       V2  espaces de noms sans privilège (sbuild --chroot-mode=unshare) ; subuid et subgid du compte replay
#       V3  apt-get update ; candidats de mmdebstrap, sbuild, libsbuild-perl, uidmap ; ce qu'apt installerait sans recommandés
#           (apt-get install --assume-no : rien installé)
#       V4  instantané 20261105T000000Z joignable depuis la VM ? sha256 de son InRelease comparé à celui de S1
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/06-deb-sbuild/s6b.sh releve   (journal : resultats/s6b-releve.log)
set -euo pipefail
export LC_ALL=C
h06=$(cd "$(dirname "$0")" && pwd)
R=$h06/resultats
T=$HOME/.cache/supply-chain-poc/06/s6b
DEB=$HOME/.cache/supply-chain-poc/08/travail/s3-06/build-1/sample-app_1.0.0-1_amd64.deb
DEB_SHA=0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5      # deb de builds/sample-app-deb@039949f9 (S4d1)
DEB_DIGEST=sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e
ZOT=192.168.161.13:5000                                                         # Zot du PoC depuis l'hôte, lecture anonyme
CA=$HOME/.cache/supply-chain-poc/10/ca-poc.crt                                  # copie publique de la CA du PoC (brique 10)
ENTREES="builds/fermetures/sample-app-deb@sha256:bb7599a2e1cde30770fdb4405a5f9cce94de5ea5b12c358e512dfbe7d5b9f290
builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21
entrees/sample-app/packaging-deb@sha256:c1719b133236f49c7e2492f4b608a8dc421bf812d7f7e438d879a871f61c2e51"   # s4d.sh
INSTANTANE=http://snapshot.debian.org/archive/debian/20261105T000000Z            # s4a.sh, s4b.sh
INRELEASE=0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675       # s1-prealables.log : signataires vérifiés
VM_IP=192.168.162.14                                                            # sc-replay (replay.sh de la 10)
SSH_DIR=$HOME/.cache/supply-chain-poc/10/ssh
SSH_OPTS=(-i "$SSH_DIR/id_ed25519" -o UserKnownHostsFile="$SSH_DIR/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
sur() { ssh "${SSH_OPTS[@]}" "replay@$VM_IP" "$@"; }

chrono() { printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
crn() { SSL_CERT_FILE=$CA crane "$@"; }

etape_releve() {
  rm -rf -- "${T:?}"; mkdir -p "$T"/{att,cc,layout/blobs/sha256}

  echo "## H1 : provenances du deb (tag .att, lecture anonyme, signatures NON vérifiées ici)"
  crn manifest "$ZOT/builds/sample-app-deb@$DEB_DIGEST" > "$T/manifeste-zot.json"
  attendu "digest du manifeste lu" "sha256:$(sha256sum < "$T/manifeste-zot.json" | cut -c1-64)" "$DEB_DIGEST"
  crn manifest "$ZOT/builds/sample-app-deb:${DEB_DIGEST/:/-}.att" > "$T/att.json"
  local l i=0
  for l in $(python3 -I -c 'import json, sys; [print(x["digest"]) for x in json.load(open(sys.argv[1]))["layers"]]' "$T/att.json"); do
    i=$((i + 1))
    crn blob "$ZOT/builds/sample-app-deb@$l" > "$T/att/$i.json"
    python3 -I - "$T/att/$i.json" "$l" <<'EOF'
import base64, json, sys
e = json.load(open(sys.argv[1]))
s = json.loads(base64.b64decode(e["payload"]))
p = s.get("predicate", {})
m = p.get("runDetails", {}).get("metadata", {})
d = p.get("buildDefinition", {}).get("resolvedDependencies", [])
print(f"couche {sys.argv[2][7:19]} : {s.get('predicateType')} ; sujets {[x['digest']['sha256'][:8] for x in s.get('subject', [])]}")
print(f"  invocationId {m.get('invocationId')} ; startedOn {m.get('startedOn')} ; finishedOn {m.get('finishedOn')} ; {len(d)} entrées résolues")
for x in d:
    print(f"    {x.get('uri', x.get('name'))} {','.join(f'{k}:{v[:12]}' for k, v in x.get('digest', {}).items())}")
EOF
  done
  echo "$i couche(s) dans le tag .att"

  echo "## H2 : layout du deb reconstruit à partir des octets du deb (hors réseau, $(tar --version | head -1))"
  attendu "sha256 du deb de S3" "$(sha256sum < "$DEB" | cut -c1-64)" "$DEB_SHA"
  cp "$DEB" "$T/cc/" && chmod 0644 "$T/cc/${DEB##*/}"
  /usr/bin/unshare -rn tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime=@0 \
    --owner=0 --group=0 --numeric-owner -C "$T/cc" -cf "$T/couche.tar" "${DEB##*/}"
  local c s cfg man
  c=$(sha256sum < "$T/couche.tar" | cut -c1-64); s=$(stat -c %s "$T/couche.tar")
  cfg='{"architecture":"amd64","os":"linux","rootfs":{"type":"layers","diff_ids":["sha256:'"$c"'"]}}'
  man='{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:'"$(printf '%s' "$cfg" | sha256sum | cut -c1-64)"'","size":'"${#cfg}"'},"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:'"$c"'","size":'"$s"'}]}'
  printf '%s' "$man" > "$T/manifeste-reconstruit.json"
  echo "couche sha256:$c ($s octets)"
  if cmp -s "$T/manifeste-reconstruit.json" "$T/manifeste-zot.json"; then echo "OK   manifeste reconstruit identique, octet à octet, à celui de Zot"
  else echo "DIFFÉRENT : manifeste reconstruit et manifeste de Zot"; diff <(tr ',' '\n' < "$T/manifeste-reconstruit.json") <(tr ',' '\n' < "$T/manifeste-zot.json") || true; fi
  echo "digest reconstruit : sha256:$(sha256sum < "$T/manifeste-reconstruit.json" | cut -c1-64)"

  echo "## H3 : entrées à transporter dans le domaine (manifestes)"
  local e
  while read -r e; do
    crn manifest "$ZOT/$e" | python3 -I -c 'import json, sys
m = json.load(sys.stdin)
c = m.get("layers", [])
n, d = sys.argv[1].split("@sha256:")
print(n + "@" + d[:8], ":", len(c), "couche(s),", sum(x.get("size", 0) for x in c), "octets, artifactType", m.get("artifactType"))' "$e"
  done <<< "$ENTREES"

  echo "## V1 à V4 : sc-replay"
  sur sudo bash -s "$INSTANTANE" "$INRELEASE" <<'EOS'
set -euo pipefail
export LC_ALL=C DEBIAN_FRONTEND=noninteractive
echo "## V1 : ressources"
echo "$(hostname) : $(nproc) vCPU ; mémoire $(free -m | awk '/Mem/ {print $2 " Mo, " $7 " disponibles"}') ; / $(df -BM --output=size,avail / | tail -1 | awk '{print $1 " dont " $2 " libres"}') ; $(. /etc/os-release; echo "$PRETTY_NAME") ; noyau $(uname -r)"
echo "paquets installés : $(dpkg-query -W | wc -l) ; déjà là : $(dpkg-query -W -f='${Package} ${Version}\n' mmdebstrap sbuild libsbuild-perl uidmap schroot 2>/dev/null | tr '\n' ';' || true)"
echo "## V2 : espaces de noms sans privilège, subuid et subgid"
for f in /proc/sys/kernel/unprivileged_userns_clone /proc/sys/user/max_user_namespaces /proc/sys/kernel/apparmor_restrict_unprivileged_userns; do
  [ -r "$f" ] && echo "$f = $(cat "$f")" || echo "$f : absent"
done
echo "subuid replay : $(grep -c '^replay:' /etc/subuid || true) ligne(s) ; subgid replay : $(grep -c '^replay:' /etc/subgid || true) ligne(s)"
grep '^replay:' /etc/subuid /etc/subgid || true
echo "## V3 : apt (listes mises à jour ; rien installé)"
apt-get update 2>&1 | grep -viE '^(Hit|Get|Reading|Atteint|Réception|Lecture)' || true
apt-cache policy mmdebstrap sbuild libsbuild-perl uidmap | grep -E '^[a-z]|Installed|Candidate|Installé|Candidat'
set +e
apt-get install --no-install-recommends --assume-no mmdebstrap sbuild uidmap > /tmp/s6b-apt.out 2>&1; r=$?
set -e
echo "apt-get install --assume-no : code $r (1 attendu : réponse non)"
sed -n '/NEW packages\|NOUVEAUX paquets/,/upgraded\|mis à jour/p' /tmp/s6b-apt.out
grep -E '^(Need to get|After this operation|Il est nécessaire|Après cette)' /tmp/s6b-apt.out || true
rm -f /tmp/s6b-apt.out
echo "paquets installés après : $(dpkg-query -W | wc -l)"
echo "## V4 : instantané Debian depuis la VM"
code=$(curl -s -o /tmp/s6b-inrelease -w '%{http_code}' --max-time 30 "$1/dists/trixie/InRelease" || echo échec)
echo "InRelease de l'instantané : HTTP $code, sha256 $(sha256sum < /tmp/s6b-inrelease 2>/dev/null | cut -c1-64)"
[ "$(sha256sum < /tmp/s6b-inrelease | cut -c1-64)" = "$2" ] && echo "OK   identique à celui de S1" || echo "DIFFÉRENT de celui de S1"
grep -m1 '^Date:' /tmp/s6b-inrelease || true
rm -f /tmp/s6b-inrelease
EOS
}

[ "${1:-}" = releve ] && [ $# = 1 ] || { echo "usage : $0 releve" >&2; exit 2; }
chrono "S6b releve"
{ echo "# ${0##*/} releve, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; etape_releve; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/s6b-releve.log"
chrono "S6b releve fait"
