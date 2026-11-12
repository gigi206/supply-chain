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
#   v4      ACCORD NOMMÉ DU PROPRIÉTAIRE. V4 remesurée (ajoutée le 12/11/2026 après le second passage de releve, où curl, sans -L,
#           n'a pas suivi la redirection 302) ; et la ligne « déjà là » de V1 remplacée par l'état dpkg de chaque paquet.
#           VM seule, sans sudo, sans apt-get update : rien d'installé ; seule écriture, un dossier temporaire supprimé à la fin.
#       V4a cible de la redirection, sans la suivre
#       V4b InRelease lu en suivant les redirections (http et https seulement, 5 au plus), comme s1.sh (curl -fsSL) ; URL finale ;
#           sha256 comparé à celui de S1
#       V4c signature de cet InRelease vérifiée par gpgv avec le trousseau debian-archive-keyring de la VM, indépendant de la
#           plateforme et des clés de ftp-master lues par S1 ; signataires (clés primaires) comparés à ceux de S1
#   sqv     ACCORD NOMMÉ DU PROPRIÉTAIRE (ajoutée le 12/11/2026, écrite avant 09:51:20 UTC, après « Oui, prépare-les »). Témoin de signature de
#           l'InRelease avec sqv, le vérificateur qu'apt utilise dans la VM, et le trousseau de la VM. VM seule, sans sudo, rien
#           d'installé ; seule écriture, un dossier temporaire supprimé à la fin. Syntaxe tirée de sqv(1) de trixie
#           (--cleartext, --output obligatoire, -n : nombre de certificats distincts exigés) ; sqv --help est journalisé.
#       S1  InRelease lu comme en V4b, sha256 comparé à celui de S1
#       S2  sqv -n 1, puis -n 3 (les trois signataires de S1) : codes de sortie ; message extrait : sa ligne Packages.xz
#           porte le sha256 contrôlé en S1
#       S3  témoin négatif : une copie dont un chiffre de la ligne Date: est changé doit être refusée (code non nul)
#   installer  ACCORD NOMMÉ DU PROPRIÉTAIRE (installation système dans sc-replay). Décision du 12/11/2026, 08:50:32 UTC, point 3 :
#           mmdebstrap, sbuild, libsbuild-perl et uidmap par apt, versions épinglées, sans recommandés. Pas d'apt-get update : les
#           listes sont celles du relevé de 09:23:13 UTC, où les candidats sont égaux à l'instantané.
#       I1  apt-get clean, puis téléchargement seul (--download-only) des quatre paquets épinglés et de leurs dépendances
#       I2  sha256 des quatre .deb téléchargés comparés à builder/paquets.txt (liste de la plateforme, lue sur l'hôte) AVANT
#           toute installation ; un écart arrête tout et vide le cache
#       I3  installation depuis le cache (rien de plus à télécharger) ; avertissements et erreurs d'apt
#       I4  versions installées égales aux épinglées ; paquets nouveaux (nom et version) ; nombre de paquets avant et après ;
#           services actifs avant et après ; mmdebstrap --version, sbuild --version, newuidmap et newgidmap ; cache vidé
#   trousseau  ACCORD NOMMÉ DU PROPRIÉTAIRE (ajoutée le 12/11/2026, préparée à partir de 10:08:24 UTC (date -u au début de la préparation), après « Oui, prépare-les »). VM
#           seule, sans sudo, rien d'installé ; seule écriture, un dossier temporaire supprimé à la fin.
#       K1  les fichiers du trousseau debian-archive-keyring (.gpg nommé par apt dans Signed-By, .pgp lu par l'étape sqv) : type,
#           cible, taille, sha256 ; dpkg -V debian-archive-keyring (aucune ligne : fichiers conformes au paquet)
#       K2  sqv -n 3 avec le .gpg sur l'InRelease : code et signataires, comparés à ceux de S1
#   chroot  ACCORD NOMMÉ DU PROPRIÉTAIRE. Décision 2 du 12/11/2026 (voie A) : chroot reconstruit dans sc-replay depuis
#           l'instantané, lien ouvert, avec les options du chroot de la plateforme (builder/construire-builder.yaml, fonction mm :
#           --mode=root, variante buildd, SOURCE_DATE_EPOCH de s4a.sh, crochets hostname, resolv.conf et sources.list). Écarts
#           voulus : source http de l'instantané au lieu du miroir file:// (ni crochet file-mirror-automount ni rmdir de son point
#           de montage) ; signed-by explicite sur le trousseau .gpg de la VM ; un crochet qui ne fait que lire le cache d'apt
#           (comme s2.sh). sudo dans la VM ; écritures sous /home/replay/s6b seulement (chemins littéraux dans les rm).
#       C1  sha256 de chaque .deb du cache, au moment des crochets, présent dans builder/paquets.txt
#       C2  taille et sha256 du chroot comparés à ceux de la plateforme (s4a-pipeline.log : 451786240 octets, aec1c7a9…)
#       C3  paquets installés dans le chroot (var/lib/dpkg/status de l'archive) : nom et version présents dans builder/paquets.txt
#       (corrigé avant lancement, après b8ae77e : C2 compare aussi les listes des noms et le détail de tar -tv à celles du chroot de
#       la plateforme ; C3 exige l'égalité avec ses paquets installés ; voir le commentaire d'etape_chroot)
#       C4  témoin négatif : mmdebstrap, variante essential, avec signed-by sur un trousseau qui ne porte pas les clés de trixie
#           (clés retirées du paquet, sinon un fichier vide) : doit échouer, sur la signature
#
#   Rejeu du deb (préparé le 12/11/2026 à partir de 10:33:26 UTC, après « Oui, prépare-les » ; modèle : R3 et R4 de la brique 10) :
#   transporter  ACCORD NOMMÉ. SUR L'HÔTE, transport non fiable : copies anonymes (oras) du layout du deb, de son tag .att, de
#           ses bundles horodatés et des entrées de la provenance 454728c5 (décision 1 du 12/11/2026), lues sans vérification,
#           dans un layout OCI ; manifeste seul de l'image de build ; bundle git de toutes les références de Forgejo ; ancres
#           de confiance de la 08 ; verifier_deb.py. Le tout copié dans /home/replay/s6b/r3, vidé d'abord.
#   verifier  ACCORD NOMMÉ. DANS LA VM : rejeu/verifier_deb.py (bundles horodatés vérifiés hors réseau, provenance extraite,
#           politique section 1, digests des entrées, commit, lignes clés de la recette, Go, chroot du domaine comparé à la
#           couche de l'image de build déclarée, heures). Écrit provenance.json, recette/ et verifie.txt.
#   repetition  ACCORD NOMMÉ. Lien ÉTABLI, non comptée : copie de rejeu/rebuild_deb.sh sans l'attente ni le refus de porteuse,
#           lancée par systemd-run --uid=replay --wait.
#   rebuild  ACCORD NOMMÉ. Pas avant finishedOn + 24 h (lu dans verifie.txt). rejeu/rebuild_deb.sh lancé détaché
#           (systemd-run --uid=replay), lien de la VM coupé aussitôt (virsh domif-setlink down), compteurs relus après la
#           coupure et avant le rétablissement (ATTENTE_HORS_LIGNE s) ; résultat lu après le rétablissement, valable seulement
#           s'il a fini avant.
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/06-deb-sbuild/s6b.sh <étape>
#   étapes : releve|v4|sqv|installer|trousseau|chroot|transporter|verifier|repetition|rebuild (journal : resultats/s6b-<étape>.log)
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
CLES="B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8 04B54C3CDCA79751B16BC6B5225629DF75B188BD 41587F7DB8C774BCCF131416762F67A0B2C39DE4"  # s1.sh
PACKAGES_XZ=7778d3e3f303b7ddb8ce0fe7c8d57473a076c6bf2e8f241f75421d2396352498     # s1-prealables.log : Packages.xz contrôlé par InRelease
SDE=1789199741                                                                  # s4a.sh : Date de l'InRelease
CHROOT_SHA=aec1c7a98b80772e032da0d54a622f6b42728069bf4cc36292c346a1e078d086      # s4a-pipeline.log : chroot de 749d746c
CHROOT_TAILLE=451786240
DEB_SUJET=builds/sample-app-deb@$DEB_DIGEST
INVOCATION=454728c5-59a8-45e1-b972-549d343aadac      # décision 1 du propriétaire du 12/11/2026 (s6b-releve.log, H1)
URL_TSA=http://timestamp-authority.tsa.svc.cluster.local:3000/api/v1/timestamp   # identifiant de la TSA (replay.sh de la 10)
R08=$h06/../08-trust-plane/resultats                  # clé publique de Chains et chaîne de la TSA (comme s4d2.sh)
VM=sc-replay
ATTENTE_HORS_LIGNE=${ATTENTE_HORS_LIGNE:-1200}       # secondes lien coupé ; le rebuild doit finir avant le rétablissement
EPINGLES="mmdebstrap=1.5.7-1+deb13u1 sbuild=0.89.3+deb13u4 libsbuild-perl=0.89.3+deb13u4 uidmap=1:4.17.4-2"   # V3 du relevé
VM_IP=192.168.162.14                                                            # sc-replay (replay.sh de la 10)
SSH_DIR=$HOME/.cache/supply-chain-poc/10/ssh
# IdentitiesOnly : seule la clé du domaine est proposée (premier passage du 12/11/2026, 09:16 UTC : « Too many authentication
# failures », sans doute des clés d'un agent proposées avant elle)
SSH_OPTS=(-i "$SSH_DIR/id_ed25519" -o IdentitiesOnly=yes -o UserKnownHostsFile="$SSH_DIR/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
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

etape_v4() {
  echo "## V4 : instantané Debian depuis sc-replay (sans sudo, rien d'installé)"
  # clés jointes par des virgules : ssh recolle les arguments et le shell distant les redécoupe (corrigé le 12/11/2026 après
  # 844bf9e, avant tout lancement : « $CLES » arrivait en trois arguments, et $3 ne contenait que la première clé)
  sur bash -s "$INSTANTANE" "$INRELEASE" "${CLES// /,}" <<'EOS'
set -euo pipefail
export LC_ALL=C
d=$(mktemp -d); trap 'rm -rf -- "$d"' EXIT
echo "## V1 corrigée : état dpkg (ii = installé ; un = connu, non installé)"
for p in mmdebstrap sbuild libsbuild-perl uidmap schroot gpgv sqv debian-archive-keyring ca-certificates; do
  s=$(dpkg-query -W -f='${db:Status-Abbrev}${Version}' "$p" 2>/dev/null || true)
  echo "$p : ${s:-inconnu de dpkg}"
done
echo "## V4a : redirection, non suivie"
r=0; curl -sS -o /dev/null --max-time 30 -w 'HTTP %{http_code} ; cible %{redirect_url}\n' "$1/dists/trixie/InRelease" || r=$?
echo "curl : code $r"
echo "## V4b : InRelease, redirections suivies (http et https, 5 au plus)"
r=0; curl -fsSL --proto-redir =http,https --max-redirs 5 --max-time 60 -o "$d/InRelease" \
  -w 'HTTP %{http_code} ; %{num_redirects} redirection(s) ; URL finale %{url_effective}\n' "$1/dists/trixie/InRelease" || r=$?
echo "curl : code $r"
[ $r = 0 ] || { echo "KO   InRelease non lu"; exit 1; }
s=$(sha256sum < "$d/InRelease" | cut -c1-64)
echo "InRelease : sha256 $s, $(sed -n 's/^Date: //p' "$d/InRelease")"
[ "$s" = "$2" ] && echo "OK   sha256 identique à celui de S1" || echo "DIFFÉRENT de celui de S1 ($2)"
echo "## V4c : signature, trousseau Debian de la VM"
k=$(dpkg -L debian-archive-keyring 2>/dev/null | grep -E '^/usr/share/keyrings/debian-archive-keyring\.(gpg|pgp)$' | head -1 || true)
echo "trousseau : ${k:-absent}"
if [ -n "$k" ] && command -v gpgv > /dev/null; then
  v=$(gpgv --keyring "$k" --status-fd 1 "$d/InRelease" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' | sort | paste -sd' ' || true)
  e=$(tr ',' '\n' <<< "$3" | sort | paste -sd' ')
  echo "signataires (clés primaires) : ${v:-aucun}"
  [ "$v" = "$e" ] && echo "OK   mêmes signataires qu'en S1" || echo "DIFFÉRENTS de ceux de S1 ($e)"
else
  echo "gpgv ou trousseau absent : signature non vérifiée (rien installé)"
fi
EOS
}

etape_sqv() {
  echo "## S1 à S3 : signature de l'InRelease par sqv, trousseau de sc-replay (sans sudo, rien d'installé)"
  sur bash -s "$INSTANTANE" "$INRELEASE" "$PACKAGES_XZ" <<'EOS'
set -euo pipefail
export LC_ALL=C
# corrigé avant tout lancement, après relecture du conseiller (12/11/2026, après a530dcb) : un KO donne le code 1 ; S3 n'est
# jugé que si sqv -n 1 accepte l'original ; Packages.xz lu sur message-1 si -n 3 échoue ; sources apt et vérificateur d'apt
# journalisés (Signed-By, apt-config) : que apt utilise sqv avec ce trousseau est déduit, pas mesuré
d=$(mktemp -d); trap 'rm -rf -- "$d"' EXIT
ko=0
k=/usr/share/keyrings/debian-archive-keyring.pgp
echo "$(sqv --version 2>&1) ; trousseau $k : sha256 $(sha256sum < "$k" | cut -c1-64)"
echo "--- sqv --help"; sqv --help 2>&1 | sed 's/^/  /'; echo "---"
sqv --help 2>&1 | grep -q -- '--cleartext' && echo "--cleartext présent dans sqv --help" || echo "--cleartext ABSENT de sqv --help"
echo "sources apt : $(ls /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | paste -sd' ')"
grep -rhiE '^(Signed-By|URIs|Suites):|^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | sed 's/^/  /' || true
echo "apt-config (sqv, gpgv) :"; apt-config dump 2>/dev/null | grep -iE 'sqv|gpgv' | sed 's/^/  /' || echo "  aucune ligne"
echo "## S1 : InRelease"
curl -fsSL --proto-redir =http,https --max-redirs 5 --max-time 60 -o "$d/InRelease" "$1/dists/trixie/InRelease"
s=$(sha256sum < "$d/InRelease" | cut -c1-64)
[ "$s" = "$2" ] && echo "OK   sha256 identique à celui de S1" || { echo "KO   sha256 $s (attendu : $2)"; exit 1; }
echo "## S2 : sqv --cleartext"
declare -A code
for n in 1 3; do
  r=0; sqv --keyring "$k" --cleartext -n "$n" --output "$d/message-$n" "$d/InRelease" > "$d/sortie-$n" 2>&1 < /dev/null || r=$?
  code[$n]=$r
  echo "sqv -n $n : code $r ; sortie :"; sed 's/^/  /' "$d/sortie-$n"
  [ $r = 0 ] && echo "OK   sqv -n $n accepte l'InRelease" || { echo "KO   sqv -n $n refuse l'InRelease"; ko=1; }
done
m=""; [ "${code[3]}" = 0 ] && m=3 || { [ "${code[1]}" = 0 ] && m=1; }
if [ -n "$m" ] && [ -s "$d/message-$m" ]; then
  echo "message extrait (-n $m) : $(wc -l < "$d/message-$m") lignes, $(grep -c '^-----BEGIN PGP' "$d/message-$m" || true) ligne(s) BEGIN PGP"
  l=$(awk '/^SHA256:/ {f = 1; next} /^[A-Z]/ {f = 0} f && $3 == "main/binary-amd64/Packages.xz" {print $1}' "$d/message-$m")
  [ "$l" = "$3" ] && echo "OK   Packages.xz du message extrait : sha256 de S1" || { echo "KO   Packages.xz du message extrait : ${l:-absent} (attendu : $3)"; ko=1; }
else
  echo "KO   aucun message extrait par une vérification acceptée"; ko=1
fi
echo "## S3 : témoin négatif (un chiffre de la ligne Date: changé)"
sed '0,/^Date: /s/^\(Date: [A-Za-z]*, \)1/\12/' "$d/InRelease" > "$d/InRelease.altere"
echo "lignes différentes : $(diff "$d/InRelease" "$d/InRelease.altere" | grep -c '^>' || true) ; $(grep -m1 '^Date:' "$d/InRelease.altere")"
r=0; sqv --keyring "$k" --cleartext -n 1 --output "$d/message-altere" "$d/InRelease.altere" > "$d/sortie-altere" 2>&1 < /dev/null || r=$?
echo "sqv -n 1 sur la copie altérée : code $r ; sortie :"; sed 's/^/  /' "$d/sortie-altere"
if [ "${code[1]}" != 0 ]; then
  echo "S3 NON JUGÉ : sqv -n 1 refuse aussi l'original"; ko=1
elif [ $r != 0 ]; then
  echo "OK   copie altérée refusée, original accepté"
else
  echo "KO   copie altérée ACCEPTÉE"; ko=1
fi
[ $ko = 0 ] && echo "bilan : tout OK" || { echo "bilan : au moins un KO"; exit 1; }
EOS
}

etape_installer() {
  local a p v
  a=""
  for p in $EPINGLES; do   # sha256 attendus, tirés de la liste de la plateforme
    v=$(awk -v n="${p%%=*}" -v v="${p#*=}" '$1 == n && $2 == v {print $4}' "$h06/builder/paquets.txt")
    [ ${#v} = 64 ] || { echo "KO   ${p%%=*} ${p#*=} absent de builder/paquets.txt" >&2; exit 1; }
    a="$a${a:+,}$p=$v"
  done
  echo "## I1 à I4 : installation dans sc-replay, versions épinglées, sans recommandés"
  echo "attendus (builder/paquets.txt) : ${a//,/ ; }"
  sur sudo bash -s "${EPINGLES// /,}" "$a" <<'EOS'
set -euo pipefail
export LC_ALL=C DEBIAN_FRONTEND=noninteractive
# corrigé avant tout lancement, après relecture du conseiller (12/11/2026, après a530dcb) : apt-get lit /dev/null, et non le
# script (bash -s le lit sur stdin, dont hériteraient dpkg et les scripts des paquets) ; un KO d'I4 donne le code 1
d=$(mktemp -d); trap 'rm -rf -- "$d"' EXIT
ko=0
IFS=, read -ra epingles <<< "$1"; IFS=, read -ra attendus <<< "$2"
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' | awk '$1 == "ii" {print $2, $3}' | sort > "$d/avant"
systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | sort > "$d/services-avant"
echo "avant : $(wc -l < "$d/avant") paquets installés, $(wc -l < "$d/services-avant") services actifs"
echo "## I1 : téléchargement seul"
apt-get clean < /dev/null
r=0; apt-get install --download-only --no-install-recommends -y "${epingles[@]}" > "$d/apt-dl" 2>&1 < /dev/null || r=$?
grep -E '^(Need to get|[0-9]+ upgraded|W:|E:)' "$d/apt-dl" || true
[ $r = 0 ] || { echo "KO   téléchargement : code $r"; tail -5 "$d/apt-dl"; apt-get clean < /dev/null; exit 1; }
echo "$(ls /var/cache/apt/archives/*.deb | wc -l) .deb dans le cache"
echo "## I2 : sha256 des quatre .deb épinglés, comparés à builder/paquets.txt, avant installation"
ko=0
for x in "${attendus[@]}"; do
  n=${x%%=*}; r=${x#*=}; v=${r%=*}; h=${r##*=}; t=""
  for f in /var/cache/apt/archives/*.deb; do
    [ "$(dpkg-deb -f "$f" Package)" = "$n" ] && [ "$(dpkg-deb -f "$f" Version)" = "$v" ] && t="$t $f"
  done
  set -- $t
  if [ $# != 1 ]; then echo "KO   $n $v : $# fichier(s) dans le cache"; ko=1; continue; fi
  s=$(sha256sum < "$1" | cut -c1-64)
  [ "$s" = "$h" ] && echo "OK   $n $v : sha256 $s" || { echo "KO   $n $v : sha256 $s (attendu : $h)"; ko=1; }
done
[ $ko = 0 ] || { echo "KO   écart : rien d'installé, cache vidé"; apt-get clean < /dev/null; exit 1; }
echo "## I3 : installation depuis le cache"
r=0; apt-get install --no-install-recommends -y "${epingles[@]}" > "$d/apt-in" 2>&1 < /dev/null || r=$?
grep -E '^(Need to get|[0-9]+ upgraded|W:|E:)' "$d/apt-in" || true
[ $r = 0 ] || { echo "KO   installation : code $r"; tail -5 "$d/apt-in"; exit 1; }
echo "## I4 : état après"
for x in "${epingles[@]}"; do
  n=${x%%=*}; v=${x#*=}; s=$(dpkg-query -W -f='${db:Status-Abbrev}${Version}' "$n" 2>/dev/null || true)
  [ "$s" = "ii $v" ] && echo "OK   $n $v installé" || { echo "KO   $n : ${s:-inconnu} (attendu : ii $v)"; ko=1; }
done
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' | awk '$1 == "ii" {print $2, $3}' | sort > "$d/apres"
systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | sort > "$d/services-apres"
echo "après : $(wc -l < "$d/apres") paquets installés ; nouveaux : $(comm -13 "$d/avant" "$d/apres" | wc -l) ; disparus ou changés : $(comm -23 "$d/avant" "$d/apres" | wc -l)"
comm -13 "$d/avant" "$d/apres" | sed 's/^/  + /'
comm -23 "$d/avant" "$d/apres" | sed 's/^/  - /'
echo "services actifs après : $(wc -l < "$d/services-apres") ; nouveaux : $(comm -13 "$d/services-avant" "$d/services-apres" | paste -sd' ')"
echo "$(mmdebstrap --version 2>&1 | head -1) ; $(sbuild --version 2>&1 | head -1)"
ls -l /usr/bin/newuidmap /usr/bin/newgidmap
apt-get clean < /dev/null
echo "cache vidé : $(ls /var/cache/apt/archives/*.deb 2>/dev/null | wc -l) .deb"
[ $ko = 0 ] && echo "bilan : tout OK" || { echo "bilan : au moins un KO"; exit 1; }
EOS
}

etape_trousseau() {
  echo "## K1 et K2 : trousseau Debian de sc-replay (sans sudo, rien d'installé)"
  sur bash -s "$INSTANTANE" "$INRELEASE" "${CLES// /,}" <<'EOS'
set -euo pipefail
export LC_ALL=C
d=$(mktemp -d); trap 'rm -rf -- "$d"' EXIT
ko=0
echo "## K1 : fichiers"
echo "paquet : $(dpkg-query -W -f='${db:Status-Abbrev}${Version}' debian-archive-keyring)"
dpkg -L debian-archive-keyring | grep '^/usr/share/keyrings/' | sed 's/^/  /'
for f in /usr/share/keyrings/debian-archive-keyring.gpg /usr/share/keyrings/debian-archive-keyring.pgp; do
  if [ -e "$f" ]; then
    echo "$f : $(stat -c '%F, %s octets' "$f") ; cible $(readlink -f "$f") ; sha256 $(sha256sum < "$f" | cut -c1-64)"
  else
    echo "$f : absent"
  fi
done
v=$(dpkg -V debian-archive-keyring 2>&1 || true)
[ -z "$v" ] && echo "OK   dpkg -V debian-archive-keyring : aucune ligne" || { echo "KO   dpkg -V : $v"; ko=1; }
echo "## K2 : sqv avec le .gpg"
k=/usr/share/keyrings/debian-archive-keyring.gpg
curl -fsSL --proto-redir =http,https --max-redirs 5 --max-time 60 -o "$d/InRelease" "$1/dists/trixie/InRelease" < /dev/null
[ "$(sha256sum < "$d/InRelease" | cut -c1-64)" = "$2" ] && echo "OK   InRelease : sha256 de S1" || { echo "KO   InRelease : sha256 différent"; ko=1; }
r=0; sqv --keyring "$k" --cleartext -n 3 --output "$d/message" "$d/InRelease" > "$d/sortie" 2>&1 < /dev/null || r=$?
echo "sqv -n 3 (.gpg) : code $r ; sortie :"; sed 's/^/  /' "$d/sortie"
e=$(tr ',' '\n' <<< "$3" | sort | paste -sd' '); g=$(grep -E '^[0-9A-F]{40}$' "$d/sortie" | sort | paste -sd' ' || true)
[ $r = 0 ] && [ "$g" = "$e" ] && echo "OK   .gpg : les trois signataires de S1" || { echo "KO   .gpg : code $r, signataires ${g:-aucun} (attendus : $e)"; ko=1; }
[ $ko = 0 ] && echo "bilan : tout OK" || { echo "bilan : au moins un KO"; exit 1; }
EOS
}

etape_chroot() {
  # corrigé avant tout lancement, après relecture du conseiller (12/11/2026, après b8ae77e) : listes de référence tirées sur
  # l'hôte du chroot de la plateforme (copie de la comparaison de S4a, sha256 revérifié) pour diagnostiquer un écart de C2 ;
  # C3 exige l'égalité avec ses paquets ; motif de C4 sans « keyring » et fin du journal du témoin toujours affichée ;
  # rm du trap en --one-file-system ; dossier temporaire de mmdebstrap sous /var/tmp (traversable par _apt), modes journalisés
  local shas nv ref=$HOME/.cache/supply-chain-poc/08/travail/s4a-06/comparaison/couche2/opt/sbuild/trixie-amd64.tar
  shas=$(awk '{print $4}' "$h06/builder/paquets.txt" | paste -sd,)
  nv=$(awk '{print $1 "=" $2}' "$h06/builder/paquets.txt" | paste -sd,)
  echo "## C0 à C4 : chroot par mmdebstrap dans sc-replay, depuis l'instantané (sudo, lien ouvert)"
  echo "## référence, sur l'hôte : chroot de la plateforme (comparaison de S4a)"
  mkdir -p "$T/ref"
  attendu "sha256 de la copie du chroot de la plateforme" "$(sha256sum < "$ref" | cut -c1-64)" "$CHROOT_SHA"
  tar -xOf "$ref" ./var/lib/dpkg/status | awk '/^Package: / {p = $2} /^Status: / {s = $0} /^Version: / {v = $2}
    /^$/ {if (s == "Status: install ok installed") print p "=" v; p = v = s = ""} END {if (s == "Status: install ok installed") print p "=" v}' \
    | sort > "$T/ref/installes.txt"
  tar -tf "$ref" > "$T/ref/noms.txt"
  TZ=UTC tar --numeric-owner --full-time -tvf "$ref" > "$T/ref/detail.txt"
  local ri rn rd
  ri=$(sha256sum < "$T/ref/installes.txt" | cut -c1-64); rn=$(sha256sum < "$T/ref/noms.txt" | cut -c1-64); rd=$(sha256sum < "$T/ref/detail.txt" | cut -c1-64)
  echo "$(tar --version | head -1) ; installés : $(wc -l < "$T/ref/installes.txt"), sha256 $ri ; noms : $(wc -l < "$T/ref/noms.txt"), sha256 $rn ; détail : sha256 $rd"
  echo "builder/paquets.txt : $(wc -l < "$h06/builder/paquets.txt") paquets ; chroot de la plateforme : $CHROOT_TAILLE octets, sha256 $CHROOT_SHA"
  sur sudo bash -s "$INSTANTANE" "$SDE" "$CHROOT_SHA" "$CHROOT_TAILLE" "$shas" "$nv" "$ri" "$rn" "$rd" <<'EOS'
set -euo pipefail
export LC_ALL=C
ko=0
D=/home/replay/s6b; W=/var/tmp/s6b-mm; k=/usr/share/keyrings/debian-archive-keyring.gpg
# chemins littéraux dans les rm : jamais une variable
nettoyer() { rm -rf --one-file-system -- /var/tmp/s6b-mm /home/replay/s6b/temoin.tar; }
trap 'nettoyer; chown -R replay:replay /home/replay/s6b' EXIT
nettoyer
mkdir -p /home/replay/s6b /var/tmp/s6b-mm
rm -f -- /home/replay/s6b/trixie-amd64.tar /home/replay/s6b/mm-chroot.log /home/replay/s6b/mm-temoin.log
echo "modes : $(stat -c '%n %a %U' /home/replay /home/replay/s6b /var/tmp /var/tmp/s6b-mm | paste -sd';')"
src="deb [check-valid-until=no signed-by=$k] $1 trixie main"
finale="deb [check-valid-until=no] $1 trixie main"
echo "## C0 : mmdebstrap"
echo "$(mmdebstrap --version) ; $(tar --version | head -1) ; SOURCE_DATE_EPOCH=$2 ; disque libre : $(df -BM --output=avail "$D" | tail -1)"
echo "source : $src"
t=$(date +%s); r=0
SOURCE_DATE_EPOCH=$2 TMPDIR=$W mmdebstrap --mode=root --variant=buildd --format=tar \
  --customize-hook='for f in "$1"/var/cache/apt/archives/*.deb; do echo "deb-cache ${f##*/} $(sha256sum < "$f" | cut -c1-64)"; done' \
  --customize-hook='echo sbuild > "$1/etc/hostname"' \
  --customize-hook=': > "$1/etc/resolv.conf"' \
  --customize-hook="echo '$finale' > \"\$1/etc/apt/sources.list\"" \
  trixie "$D/trixie-amd64.tar" "$src" > "$D/mm-chroot.log" 2>&1 < /dev/null || r=$?
echo "mmdebstrap : code $r en $(($(date +%s) - t)) s ; journal de mmdebstrap ($(wc -l < "$D/mm-chroot.log") lignes) :"
sed 's/^/  /' "$D/mm-chroot.log"
[ $r = 0 ] || { echo "KO   mmdebstrap : code $r"; exit 1; }
echo "## C1 : .deb du cache, comparés à builder/paquets.txt"
declare -A connu; IFS=, read -ra l <<< "$5"; for h in "${l[@]}"; do connu[$h]=1; done
n=0; hors=0
while read -r _ f h; do
  n=$((n + 1)); [ -n "${connu[$h]:-}" ] || { echo "KO   hors de la liste : $f $h"; hors=$((hors + 1)); }
done < <(grep '^deb-cache ' "$D/mm-chroot.log" | grep -v '\*\.deb ' || true)
[ $n -gt 0 ] && [ $hors = 0 ] && echo "OK   $n .deb, tous dans builder/paquets.txt" || { echo "KO   $n .deb, $hors hors de la liste"; ko=1; }
echo "## C2 : archive comparée au chroot de la plateforme"
z=$(stat -c %s "$D/trixie-amd64.tar"); c=$(sha256sum < "$D/trixie-amd64.tar" | cut -c1-64)
echo "chroot : $z octets, sha256 $c"
[ "$c" = "$3" ] && echo "OK   identique au chroot de la plateforme" || { echo "DIFFÉRENT du chroot de la plateforme ($4 octets, $3)"; ko=1; }
tar -tf "$D/trixie-amd64.tar" > "$D/noms.txt"
TZ=UTC tar --numeric-owner --full-time -tvf "$D/trixie-amd64.tar" > "$D/detail.txt"
x=$(sha256sum < "$D/noms.txt" | cut -c1-64); y=$(sha256sum < "$D/detail.txt" | cut -c1-64)
[ "$x" = "$8" ] && echo "OK   liste des noms : $(wc -l < "$D/noms.txt") entrées, identique" || echo "DIFFÉRENTE liste des noms : $(wc -l < "$D/noms.txt") entrées, sha256 $x"
[ "$y" = "$9" ] && echo "OK   liste détaillée (modes, propriétaires, tailles, dates) identique" || echo "DIFFÉRENTE liste détaillée : sha256 $y"
echo "## C3 : paquets installés dans le chroot, comparés au chroot de la plateforme et à builder/paquets.txt"
declare -A nv; IFS=, read -ra l <<< "$6"; for x in "${l[@]}"; do nv[$x]=1; done
tar -xOf "$D/trixie-amd64.tar" ./var/lib/dpkg/status | awk '/^Package: / {p = $2} /^Status: / {s = $0} /^Version: / {v = $2}
  /^$/ {if (s == "Status: install ok installed") print p "=" v; p = v = s = ""} END {if (s == "Status: install ok installed") print p "=" v}' \
  | sort > "$D/installes.txt"
n=0; hors=0
while read -r x; do n=$((n + 1)); [ -n "${nv[$x]:-}" ] || { echo "KO   hors de builder/paquets.txt : $x"; hors=$((hors + 1)); }; done < "$D/installes.txt"
[ $n -gt 0 ] && [ $hors = 0 ] && echo "OK   $n paquets installés, tous dans builder/paquets.txt" || { echo "KO   $n paquets, $hors hors de builder/paquets.txt"; ko=1; }
x=$(sha256sum < "$D/installes.txt" | cut -c1-64)
[ "$x" = "$7" ] && echo "OK   paquets installés identiques à ceux du chroot de la plateforme (noms et versions)" || { echo "KO   paquets installés différents de ceux de la plateforme (sha256 de la liste $x)"; ko=1; }
echo "## C4 : témoin négatif (trousseau sans les clés de trixie)"
m=""; for f in /usr/share/keyrings/debian-archive-removed-keys.gpg /usr/share/keyrings/debian-archive-removed-keys.pgp; do [ -s "$f" ] && { m=$f; break; }; done
[ -n "$m" ] || { m=$W/vide.gpg; : > "$m"; }
echo "trousseau du témoin : $m"
r=0; SOURCE_DATE_EPOCH=$2 TMPDIR=$W mmdebstrap --mode=root --variant=essential --format=tar \
  trixie "$D/temoin.tar" "deb [check-valid-until=no signed-by=$m] $1 trixie main" > "$D/mm-temoin.log" 2>&1 < /dev/null || r=$?
echo "mmdebstrap du témoin : code $r ; fin de son journal :"
tail -n 15 "$D/mm-temoin.log" | sed 's/^/  /'
if [ $r != 0 ] && grep -qiE 'NO_PUBKEY|not signed|signature|openpgp' "$D/mm-temoin.log"; then
  echo "OK   témoin refusé, sur la signature"
elif [ $r != 0 ]; then
  echo "NON CONCLUANT : refus sans message de signature"; ko=1
else
  echo "KO   témoin ACCEPTÉ"; ko=1
fi
nettoyer
chmod 0644 "$D/trixie-amd64.tar"
echo "gardés dans la VM : $(ls "$D" | paste -sd' ') ; disque libre : $(df -BM --output=avail "$D" | tail -1)"
[ $ko = 0 ] && echo "bilan : tout OK" || { echo "bilan : au moins un KO ou un écart"; exit 1; }
EOS
  echo "listes de référence gardées sur l'hôte : ${T/#$HOME/~}/ref"
}

v() { virsh -c qemu:///system "$@"; }

etape_transporter() { # SUR L'HÔTE, transport non fiable (modèle : etape_transporter de la 10, R3) : la VM vérifie tout
  local x=${T:?}/transport t n nom ref
  rm -rf -- "${x:?}" && mkdir -p "$x/layout" && chmod 0700 "$x"
  oc() { oras copy --from-ca-file "$CA" "$ZOT/$1" --to-oci-layout "$x/layout:$2" > /dev/null && echo "copié : $1 -> $2"; }
  oc "$DEB_SUJET" sujet
  oc "${DEB_SUJET%@*}:${DEB_DIGEST/:/-}.att" att
  n=0
  for t in $(oras repo tags --ca-file "$CA" "$ZOT/horodatage/bundles" | grep "^${DEB_DIGEST#sha256:}-"); do
    n=$((n + 1)); oc "horodatage/bundles:$t" "bundle-${t##*-}"
  done
  echo "bundles horodatés du deb : $n"
  # digests des entrées lus dans la provenance NON vérifiée de l'invocation retenue (transport seulement ; la VM vérifie)
  for t in $(oras manifest fetch --ca-file "$CA" "$ZOT/${DEB_SUJET%@*}:${DEB_DIGEST/:/-}.att" \
             | python3 -I -c 'import json,sys; print(" ".join(x["digest"] for x in json.load(sys.stdin)["layers"]))'); do
    oras blob fetch --ca-file "$CA" --output - "$ZOT/${DEB_SUJET%@*}@$t" | python3 -I -c '
import base64, json, sys
e = json.loads(base64.b64decode(json.load(sys.stdin)["payload"]))
if e["predicate"]["runDetails"]["metadata"].get("invocationId") != sys.argv[1]:
    sys.exit()
noms = {"tekton/tasks/construire-deb": "construire-deb", "tekton/tasks/preparer-deb": "preparer-deb",
        "builds/builders/sbuild-debian13": "sbuild-debian13", "plateforme/outils-prefetch": "outils-prefetch",
        "builds/fermetures/sample-app-deb": "fermeture-deb", "builds/fermetures/sample-app-sources": "fermeture-sources",
        "entrees/sample-app/packaging-deb": "packaging"}
for d in e["predicate"]["buildDefinition"]["resolvedDependencies"]:
    u = d.get("uri", "").removeprefix("oci://").replace("sc-stockage.poc.test:5000/", "")
    if u in noms and "sha256" in d.get("digest", {}):
        print(noms[u], u + "@sha256:" + d["digest"]["sha256"])' "$INVOCATION" >> "$x/entrees.txt"
  done
  echo "entrées lues (non vérifiées) : $(wc -l < "$x/entrees.txt")"
  while read -r nom ref; do
    if [ "$nom" = sbuild-debian13 ]; then   # image de build : manifeste seul (le chroot est reconstruit dans le domaine)
      oras manifest fetch --ca-file "$CA" "$ZOT/$ref" > "$x/sbuild-debian13.manifeste.json" && echo "manifeste seul : $ref"
    else
      oc "$ref" "$nom"
    fi
  done < "$x/entrees.txt"
  rm -f "$x/entrees.txt"
  GIT_TERMINAL_PROMPT=0 git -c http.sslCAInfo="$CA" clone -q --mirror "https://${ZOT%:*}:3000/workspace/sample-app.git" "$x/git" < /dev/null
  git -C "$x/git" bundle create -q "$x/sample-app.bundle" --all < /dev/null && rm -rf -- "${x:?}/git"
  echo "bundle git : $(du -h "$x/sample-app.bundle" | cut -f1) (toutes les références)"
  cp "$R08/chains-cle-publique.pem" "$x/chains.pub"
  cp "$R08/tsa-chaine.pem" "$x/tsa-chaine.pem"
  cp "$h06/rejeu/verifier_deb.py" "$x/"
  ( cd "$x" && sha256sum chains.pub tsa-chaine.pem sample-app.bundle sbuild-debian13.manifeste.json verifier_deb.py \
      && tar -cf r3.tar layout chains.pub tsa-chaine.pem sample-app.bundle sbuild-debian13.manifeste.json verifier_deb.py )
  echo "archive transportée : $(du -h "$x/r3.tar" | cut -f1)"
  sur 'rm -rf -- /home/replay/s6b/r3 && mkdir -m 0700 /home/replay/s6b/r3'
  scp -q "${SSH_OPTS[@]}" "$x/r3.tar" "replay@$VM_IP:/home/replay/s6b/r3/" < /dev/null
  sur 'cd /home/replay/s6b/r3 && tar -xf r3.tar && rm r3.tar && du -sh /home/replay/s6b/r3 | cut -f1 | sed "s/^/taille dans la VM : /"'
  rm -rf -- "${x:?}"
}

etape_verifier() { # DANS LA VM (verifier_deb.py, transporté ; son sha256 est journalisé)
  sur "cd /home/replay/s6b/r3 && sha256sum verifier_deb.py && python3 -I verifier_deb.py '$DEB_SUJET' '$INVOCATION' '$URL_TSA' /home/replay/s6b/trixie-amd64.tar"
}

transporter_r4() { # rebuild_deb.sh (ou sa copie de répétition) copié dans ~/s6b/r4 de la VM, vidé d'abord
  sur 'rm -rf -- /home/replay/s6b/r4 && mkdir -m 0700 /home/replay/s6b/r4'
  scp -q "${SSH_OPTS[@]}" "$1" "replay@$VM_IP:/home/replay/s6b/r4/rebuild_deb.sh" < /dev/null
  echo "rebuild_deb.sh transporté : sha256 local $(sha256sum < "$1" | cut -c1-64) ; dans la VM $(sur 'sha256sum < /home/replay/s6b/r4/rebuild_deb.sh | cut -c1-64')"
}

etape_repetition() { # lien ÉTABLI, non comptée (comme la répétition de R4) : copie sans l'attente de 20 s ni le refus de porteuse
  local c=$T/rebuild-repetition.sh
  sed -e '/^sleep 20 /d' -e '/non coupé"; exit 1; }$/d' "$h06/rejeu/rebuild_deb.sh" > "$c"
  echo "## lignes retirées de rejeu/rebuild_deb.sh"; { diff "$h06/rejeu/rebuild_deb.sh" "$c" || true; } | sed -n 's/^< /  /p'
  [ "$(diff "$h06/rejeu/rebuild_deb.sh" "$c" | grep -c '^[<>]')" = 2 ] || { echo "REFUS : copie inattendue"; exit 1; }
  transporter_r4 "$c"; rm -f -- "${c:?}"
  sur 'sudo systemd-run --unit=s6b-repetition --collect --wait --property=Type=exec --uid=replay --gid=replay /bin/bash /home/replay/s6b/r4/rebuild_deb.sh' 2>&1 | tail -4 || true
  echo "## résultat (écrit dans la VM)"; sur 'cat /home/replay/s6b/r4/resultat.txt'
  echo "## journal (fin)"; sur 'tail -25 /home/replay/s6b/r4/rebuild.log'
}

etape_rebuild() { # lien COUPÉ (modèle : etape_rebuild de la 10, R4) ; pas avant finishedOn + 24 h (vsa.py)
  local iface s0 s1 s2 e1 e2 coupe retabli fin fo
  fo=$(sur "sed -n 's/^finishedOn=//p' /home/replay/s6b/r3/verifie.txt")
  [ -n "$fo" ] || { echo "REFUS : finishedOn absent de verifie.txt (étape verifier)"; exit 1; }
  if [ "$(date -u +%s)" -lt $(( $(date -u -d "$fo" +%s) + 86400 )) ]; then
    echo "REFUS : moins de 24 h depuis la fin du build ($fo, provenance vérifiée)"; exit 1
  fi
  echo "## délai : $(( ($(date -u +%s) - $(date -u -d "$fo" +%s)) / 60 )) min depuis la fin du build ($fo)"
  transporter_r4 "$h06/rejeu/rebuild_deb.sh"
  iface=$(v domiflist "$VM" | awk '$3 == "supply-chain-replay" {print $1}')
  [ -n "$iface" ] || { echo "REFUS : interface de $VM sur supply-chain-replay introuvable"; exit 1; }
  echo "## interface de $VM côté hôte : $iface"
  st() { v domifstat "$VM" "$iface" | awk '{printf "%s=%s ", $2, $3}'; }
  sortie() { v domifstat "$VM" "$iface" | awk '$2 ~ /^tx_(bytes|packets)$/ {printf "%s=%s ", $2, $3}'; }
  s0=$(st)
  sur 'sudo systemd-run --unit=s6b-rebuild --collect --property=Type=exec --uid=replay --gid=replay /bin/bash /home/replay/s6b/r4/rebuild_deb.sh' 2>&1 | tail -1
  # shellcheck disable=SC2064   # développement à la pose, voulu (la VM ne reste jamais coupée sans surveillance)
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
  echo "## sortie de rebuild_deb.sh : $(sur "sed -n 's/^sortie=//p' /home/replay/s6b/r4/resultat.txt" || true)"
  echo "## résultat (écrit dans la VM)"
  sur 'cat /home/replay/s6b/r4/resultat.txt'
  fin=$(sur "sed -n 's/^fin=//p' /home/replay/s6b/r4/resultat.txt")
  if [ -n "$fin" ] && [ "$(date -u -d "$fin" +%s)" -lt "$(date -u -d "$retabli" +%s)" ]; then
    echo "OK   rebuild terminé ($fin) avant le rétablissement du lien ($retabli)"
  else
    echo "KO   rebuild non terminé avant le rétablissement du lien ($retabli) : résultat non valable hors ligne"
  fi
  echo "## journal (fin)"; sur 'tail -25 /home/replay/s6b/r4/rebuild.log'
}

case "${1:-}:$#" in releve:1|v4:1|sqv:1|installer:1|trousseau:1|chroot:1|transporter:1|verifier:1|repetition:1|rebuild:1) ;;
  *) echo "usage : $0 releve|v4|sqv|installer|trousseau|chroot|transporter|verifier|repetition|rebuild" >&2; exit 2 ;; esac
chrono "S6b $1"
{ echo "# ${0##*/} $1, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$1"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/s6b-$1.log"
chrono "S6b $1 fait"
