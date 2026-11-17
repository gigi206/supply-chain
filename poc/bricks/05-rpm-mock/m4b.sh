#!/usr/bin/env bash
# Brique 05, jalon M4b (découpage du 17/11/2026, « Oui, ce découpage » ; transport « Option A » ; rpm de mock « Le retirer ») :
# fermeture rpm produite par la plateforme. Ce script couvre les deux premières étapes, préparées à sec sur « Oui, prépare-les » ;
# les suivantes (taches, rpm, comparaison, provenance) viendront après l'essai. Prédictions : resultats/m4b-predictions.md,
# commitées avant tout lancement. Chaque étape attend un accord nommé.
#   prealables  hôte seul, hors ligne, sans cluster ni Zot : primary de vault 9.7 relus dans le cache de s1.sh (relevés par hote97,
#               fichiers désignés par leur nom) et revérifiés (repomd.xml signé par la clé de Rocky, primary égal à repomd.xml) ;
#               liste des 222 rpm du verrou (URL, sha256, taille) tirée de ces primary, confrontée à la collecte de M2 ; liste
#               archivée sous resultats/m4b-liste.txt (elle sera inscrite dans le gabarit de la pipeline) ; script du pas de
#               prefetch contrôlé (sh -n)
#   essai       cluster (pod d'essai, rien dans Zot) : pod runc sans root (UID 65532, Pod Security restricted), label
#               tekton.dev/task=prefetch-rpm, image d'outillage de M3 par digest, montages de la future tâche (volume éphémère
#               sous un subPath comme le workspace, /tmp, CA du PoC) ; le script du pas de prefetch joué deux fois (p1, p2) :
#               téléchargement, sha256 et taille, rpm -K (clé de Rocky de l'image, empreinte contrôlée), createrepo_c, skopeo
#               copy de l'image de bootstrap ; puis repodata comparés (p1, p2) et deux variantes de createrepo_c essayées deux fois
#               chacune ; pod retiré à la fin, avec son volume éphémère (une PVC et son volume, créés puis retirés avec le pod).
#               Une sonde, qui ne s'arrête sur aucun écart, passe avant les passages : écriture sur le volume, outils de l'image,
#               clé de Rocky, options de createrepo_c, lecture anonyme de l'image de bootstrap sous les deux formes de CA.
#               N'écrit rien dans Zot. Non couvert par l'essai : la liste reçue en paramètre de Tekton (ici, un fichier livré).
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/m4b.sh <étape>…
# (journal : resultats/m4b-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "$0")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, lancer, chrono
R=$h05/resultats
T=$W/m4b-05
T1=$W/s1-05            # cache de s1.sh : primary et repomd.xml de vault 9.7 (hote97) ; fichiers désignés par leur nom
mkdir -p "$T"
umask 022

VERROU_SRC=$R/s1-verrou_derivee.json
VERROU_SHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f   # verrou_derivee (303b428)
VAULT97=https://dl.rockylinux.org/vault/rocky/9.7
DEPOTS97=(BaseOS AppStream CRB extras)
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D   # s1.sh (audit du 05/11/2026)
COLLECTE=$R/s1-collecte.log
LISTE=$R/m4b-liste.txt
IMAGE=$REG/essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771   # « Option 1 »
POD=m4b-05-essai
LABEL=prefetch-rpm
LIMITES='{"cpu": "2", "memory": "2Gi"}'
VOLUME=4Gi            # deux passages de 319 Mo et quatre copies de variantes en liens durs

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }

# Script du pas de prefetch de la future tâche prefetch-rpm, joué tel quel dans le pod d'essai. Entrées par l'environnement :
# SORTIE (dossier de la fermeture), LISTE_FICHIER (lignes « URL sha256 taille »), SOURCE (image de bootstrap, registre@digest),
# DOSSIER (nom du dossier dir: attendu par mock), FP_ROCKY. Écrit SORTIE/depot/ : les rpm, repodata, l'image en dossier dir:.
PREFETCH=$(cat <<'SH'
set -u
ko() { echo "KO   $*" >&2; exit 1; }
for o in curl rpm createrepo_c skopeo sha256sum stat; do command -v "$o" >/dev/null 2>&1 || ko "$o absent de l'image"; done
D=$SORTIE/depot
mkdir -p "$D" || ko "dossier $D non créé"
[ -z "$(ls -A "$D")" ] || ko "dossier $D non vide"
n=0
while read -r url sha taille; do
  [ -n "$url" ] || continue
  f=$D/${url##*/}
  [ ! -e "$f" ] || ko "nom en double : ${url##*/}"
  h=$(curl -sS --proto =https --max-time 120 -o "$f" -w "%{http_code}" "$(printf %s "$url" | sed "s/+/%2B/g")") || ko "curl en échec : $url"
  [ "$h" = 200 ] || ko "HTTP $h : $url"
  [ "$(sha256sum < "$f" | cut -c1-64)" = "$sha" ] || ko "sha256 différent : ${url##*/}"
  [ "$(stat -c %s "$f")" = "$taille" ] || ko "taille différente : ${url##*/}"
  n=$((n + 1))
done < "$LISTE_FICHIER"
echo "téléchargés et contrôlés (sha256, taille) : $n"
K=${CLE_ROCKY:-/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9}   # réglable pour le banc seulement
[ -s "$K" ] || ko "clé de Rocky absente de l'image : $K"
if command -v gpg >/dev/null 2>&1; then
  fp=$(gpg --batch --with-colons --show-keys "$K" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  [ "$fp" = "$FP_ROCKY" ] || ko "empreinte de la clé de l'image : $fp"
  echo "clé de Rocky de l'image : empreinte conforme (gpg)"
else
  echo "gpg absent de l'image : empreinte contrôlée par l'identifiant court de rpm seulement"
fi
B=/tmp/rpmdb-$$
rpm --dbpath "$B" --initdb </dev/null || ko "rpmdb vide non créée"
rpm --dbpath "$B" --import "$K" </dev/null || ko "clé de Rocky non importée"
v=$(rpm --dbpath "$B" -q gpg-pubkey --qf '%{VERSION}\n' </dev/null)
[ "$v" = "$(printf %s "$FP_ROCKY" | tail -c 8 | tr 'A-F' 'a-f')" ] || ko "identifiant court de la clé importée : $v"
r=0; rpm --dbpath "$B" -K "$D"/*.rpm > /tmp/k.log 2>&1 </dev/null || r=$?
k=$(grep -c ': digests signatures OK$' /tmp/k.log)
echo "rpm -K : rc $r, $k OK sur $n"
[ "$r" = 0 ] && [ "$k" = "$n" ] || ko "signatures des rpm"
t=$(date +%s); createrepo_c --compatibility "$D" > /tmp/createrepo.log 2>&1 </dev/null || { tail -n 5 /tmp/createrepo.log; ko "createrepo_c"; }
echo "createrepo_c --compatibility : en $(($(date +%s) - t)) s ; repomd.xml $(sha256sum < "$D/repodata/repomd.xml" | cut -c1-64)"
t=$(date +%s)
skopeo copy --preserve-digests --src-cert-dir /etc/ca-poc "docker://$SOURCE" "dir:$D/$DOSSIER" > /tmp/skopeo.log 2>&1 </dev/null \
  || { tail -n 5 /tmp/skopeo.log; ko "skopeo copy"; }
m=sha256:$(sha256sum < "$D/$DOSSIER/manifest.json" | cut -c1-64)
[ "$m" = "${SOURCE##*@}" ] || ko "manifeste copié : $m"
echo "skopeo copy --preserve-digests : en $(($(date +%s) - t)) s ; manifeste $m"
echo "fermeture : $(find "$D" -type f | wc -l) fichiers, $(du -sb "$D" | cut -f1) octets"
SH
)

# Comparaisons dans le pod d'essai après les deux passages : repodata de p1 et p2, puis deux variantes de createrepo_c, chacune
# jouée sur deux copies en liens durs des rpm (une de p1, une de p2). Les rpm d'une copie sont datés à l'époque 0 (touch -h) :
# primary.xml porte la date de chaque fichier, que curl fixe à l'heure du téléchargement.
COMPARE=$(cat <<'SH'
set -u
# ni cmp ni diff : diffutils n'est pas dans l'image d'outillage (s1-racine.log) ; comparaison par sha256, écarts par comm
meme() { [ "$(sha256sum < "$1")" = "$(sha256sum < "$2")" ]; }
W=${ESPACE:-/workspace/sortie}   # réglable pour le banc seulement
liste() { (cd "$1" && find . -type f ! -path './depot/repodata/*' -printf '%P %s\n' | sort | while read -r f s; do echo "$f $s $(sha256sum < "$f" | cut -c1-64)"; done); }
echo "## passages p1 et p2 : fichiers hors repodata"
liste "$W/p1" > /tmp/l1; liste "$W/p2" > /tmp/l2
if meme /tmp/l1 /tmp/l2; then echo "égaux : $(wc -l < /tmp/l1) fichiers"; else echo "DIFFÉRENTS : $(comm -3 /tmp/l1 /tmp/l2 | wc -l) lignes"; fi
rd() { (cd "$1/depot/repodata" && for f in $(ls | sort); do echo "$f $(sha256sum < "$f" | cut -c1-16)"; done); }
echo "## repodata, défaut (comme en M2)"
rd "$W/p1" > /tmp/r1; rd "$W/p2" > /tmp/r2
echo "p1 : $(sha256sum < "$W/p1/depot/repodata/repomd.xml" | cut -c1-64) ; p2 : $(sha256sum < "$W/p2/depot/repodata/repomd.xml" | cut -c1-64)"
if meme /tmp/r1 /tmp/r2; then echo "repodata égaux"; else echo "repodata différents :"; comm -3 /tmp/r1 /tmp/r2 | sed 's/^/     /'; fi
echo "## options de createrepo_c (aide)"
createrepo_c --version 2>&1 | head -n 1
createrepo_c --help 2>&1 | grep -E -e '--(revision|set-timestamp-to-revision|no-database|compatibility|retain-old-md|distro|content)' | sed 's/^ */     /'
variante() { # nom options… : deux copies, rpm datés à 0, createrepo_c avec ces options, repodata comparés
  v=$1; shift
  for p in p1 p2; do
    c=$W/var-$v-$p
    mkdir -p "$c" && cp -al "$W/$p/depot/." "$c/" && rm -rf "$c/repodata" && find "$c" -maxdepth 1 -name '*.rpm' -exec touch -h -d @0 {} +
    if createrepo_c "$@" "$c" > "/tmp/cr-$v-$p.log" 2>&1 </dev/null; then echo "$v $p : rc 0 ; repomd.xml $(sha256sum < "$c/repodata/repomd.xml" | cut -c1-64)"
    else echo "$v $p : rc $? ; $(tail -n 2 "/tmp/cr-$v-$p.log" | tr '\n' ' ')"; fi
  done
  (cd "$W/var-$v-p1/repodata" 2>/dev/null && for f in $(ls | sort); do echo "$f $(sha256sum < "$f" | cut -c1-16)"; done) > "/tmp/v1"
  (cd "$W/var-$v-p2/repodata" 2>/dev/null && for f in $(ls | sort); do echo "$f $(sha256sum < "$f" | cut -c1-16)"; done) > "/tmp/v2"
  if [ -s /tmp/v1 ] && meme /tmp/v1 /tmp/v2; then echo "$v : repodata égaux ($(wc -l < /tmp/v1) fichiers)"; else echo "$v : repodata différents ou absents"; comm -3 /tmp/v1 /tmp/v2 | sed 's/^/     /'; fi
}
echo "## variante V1 : rpm datés à 0, --compatibility --revision 0 --set-timestamp-to-revision"
variante V1 --compatibility --revision 0 --set-timestamp-to-revision
echo "## variante V2 : V1 et --no-database"
variante V2 --compatibility --revision 0 --set-timestamp-to-revision --no-database
df -k "$W" | awk 'NR == 2 {print "volume : " $2 " kB, utilisés " $3 " kB"}'
SH
)

# Sonde du pod d'essai, jouée avant les passages : rapporte chaque point, ne s'arrête sur aucun.
SONDE=$(cat <<'SH'
set -u
echo "identité : $(id)"
ls -ld /workspace/sortie /tmp 2>&1
if touch /workspace/sortie/.essai 2>/dev/null; then echo "volume inscriptible : oui"; rm -f /workspace/sortie/.essai; else echo "volume inscriptible : NON"; fi
for o in curl rpm createrepo_c skopeo sha256sum stat gpg find du awk touch cp comm sort cmp diff python3; do
  echo "outil $o : $(command -v "$o" 2>/dev/null || echo absent)"; done
K=/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
if [ -s "$K" ]; then
  echo "clé de l'image : présente ; empreinte gpg : $(gpg --batch --with-colons --show-keys "$K" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')"
  B=/tmp/sonde-rpmdb; rpm --dbpath "$B" --initdb </dev/null && rpm --dbpath "$B" --import "$K" </dev/null \
    && echo "clé de l'image : identifiant court rpm $(rpm --dbpath "$B" -q gpg-pubkey --qf '%{VERSION}' </dev/null)"; rm -rf "$B"
else echo "clé de l'image : ABSENTE ($K)"; fi
echo "createrepo_c : $(createrepo_c --version 2>&1 | head -n 1)"
createrepo_c --help 2>&1 | grep -E -e '--(revision|set-timestamp-to-revision|no-database|compatibility)' | sed 's/^ */     /'
r=0; m=$(skopeo inspect --raw --cert-dir /etc/ca-poc "docker://$SOURCE" 2>/tmp/s1.err | sha256sum | cut -c1-64) || r=$?
echo "skopeo inspect, --cert-dir /etc/ca-poc : manifeste sha256:$m ; $(head -c 160 /tmp/s1.err | tr '\n' ' ')"
m=$(SSL_CERT_FILE=/etc/ca-poc/ca.crt skopeo inspect --raw "docker://$SOURCE" 2>/tmp/s2.err | sha256sum | cut -c1-64)
echo "skopeo inspect, SSL_CERT_FILE : manifeste sha256:$m ; $(head -c 160 /tmp/s2.err | tr '\n' ' ')"
echo "attendu : ${SOURCE##*@}"
SH
)

etape_prealables() {
  attendu "verrou de verrou_derivee (sha256)" "$(sha256sum < "$VERROU_SRC" | cut -d' ' -f1)" "$VERROU_SHA"
  echo "## primary de vault 9.7 du cache de s1.sh, revérifiés"
  local x s n
  for n in "${DEPOTS97[@]}"; do
    x=${n,,}97
    for f in "$T1/hote/$x.repomd.xml" "$T1/hote/$x.repomd.xml.asc" "$T1/hote/cles.gpg" "$T1/$x.primary.xml"; do
      [ -s "$f" ] || { echo "KO   fichier absent du cache de s1.sh : ${f#"$W"/}" >&2; exit 1; }
    done
    s=$(gpgv --keyring "$T1/hote/cles.gpg" --status-fd 1 "$T1/hote/$x.repomd.xml.asc" "$T1/hote/$x.repomd.xml" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}')
    attendu "$x : signataire de repomd.xml (clé primaire)" "$s" "$FP_ROCKY"
    python3 -I - "$T1/hote/$x.repomd.xml" "$T1/hote" "$x" "$T1/$x.primary.xml" <<'PY'
import gzip, hashlib, lzma, os, sys, xml.etree.ElementTree as E
repomd, d, x, prim = sys.argv[1:5]
n = {'r': 'http://linux.duke.edu/metadata/repo'}
for e in E.parse(repomd).getroot().findall('r:data', n):
    if e.get('type') == 'primary':
        href = e.find('r:location', n).get('href'); c = e.find('r:checksum', n)
f = os.path.join(d, x + '.' + os.path.basename(href))
data = open(f, 'rb').read()
ok = c.get('type') == 'sha256' and hashlib.sha256(data).hexdigest() == c.text
dec = gzip.decompress(data) if f.endswith('.gz') else lzma.decompress(data) if f.endswith('.xz') else None
egal = dec is not None and dec == open(prim, 'rb').read()
print(f'{"OK  " if ok and egal else "KO  "} {x} : {os.path.basename(href)} égal à repomd.xml : {ok} ; primary décompressé égal à celui du cache : {egal if dec is not None else "format non lu"}')
sys.exit(0 if ok and egal else 1)
PY
  done

  echo "## liste des rpm du verrou, tirée des primary"
  python3 -I - "$VERROU_SRC" "$T1" "$VAULT97" "$COLLECTE" "$T/liste.txt" "${DEPOTS97[@]}" <<'PY'
import json, re, sys, xml.etree.ElementTree as E
verrou, t1, vault, collecte, sortie = sys.argv[1:6]; depots = sys.argv[6:]
C = '{http://linux.duke.edu/metadata/common}'
index = {}
for n in depots:
    for _, p in E.iterparse(f'{t1}/{n.lower()}97.primary.xml'):
        if p.tag == C + 'package':
            loc = p.find(C + 'location').get('href'); cs = p.find(C + 'checksum'); sz = p.find(C + 'size').get('package')
            if cs.get('type') == 'sha256':
                index[f'{vault}/{n}/x86_64/os/{loc}'] = (cs.text, sz)
            p.clear()
urls = sorted(r['url'] for r in json.load(open(verrou))['buildroot']['rpms'])
manque = [u for u in urls if u not in index]
noms = [u.rsplit('/', 1)[1] for u in urls]
lignes = [f'{u} {index[u][0]} {index[u][1]}' for u in urls if u in index]
col = {}
for l in open(collecte, encoding='utf-8'):
    m = re.match(r'^     fichier depot/([^/ ]+\.rpm) ([0-9a-f]{64}) ([0-9]+)$', l)
    if m: col[m.group(1)] = (m.group(2), m.group(3))
ecarts = [u for u in urls if u in index and col.get(u.rsplit('/', 1)[1]) != index[u]]
ok = len(urls) == 222 and not manque and len(set(noms)) == len(noms) and not ecarts and len(col) == 222
print(f'{"OK  " if ok else "KO  "} liste : {len(lignes)} lignes ; {len(manque)} URL absente(s) des primary ; '
      f'{len(noms) - len(set(noms))} nom(s) en double ; collecte : {len(col)} rpm, {len(ecarts)} écart(s) de sha256 ou de taille')
for u in manque[:5] + ecarts[:5]: print(f'     {u}')
open(sortie, 'w').write(''.join(l + '\n' for l in lignes))
sys.exit(0 if ok else 1)
PY
  if [ -e "$LISTE" ]; then
    attendu "liste égale à celle archivée" "$(cmp -s "$T/liste.txt" "$LISTE" && echo égale || echo différente)" égale
  else
    cp "$T/liste.txt" "$LISTE" && echo "liste archivée : resultats/m4b-liste.txt"
  fi
  echo "liste : $(wc -l < "$LISTE") lignes, $(awk '{s += $3} END {print s}' "$LISTE") octets, sha256 $(sha256sum < "$LISTE" | cut -c1-64)"
  echo "## scripts du pod (syntaxe)"
  attendu "pas de prefetch, sh -n" "$(sh -n <<<"$PREFETCH" && echo ok)" ok
  attendu "comparaisons, sh -n" "$(sh -n <<<"$COMPARE" && echo ok)" ok
  attendu "sonde, sh -n" "$(sh -n <<<"$SONDE" && echo ok)" ok
}

pod_spec() { # pod d'essai : runc, sans root, montages de la future tâche ; volume éphémère sous subPath comme un workspace
  jq -n --arg n "$POD" --arg i "$IMAGE" --argjson l "$LIMITES" --arg lb "$LABEL" --arg v "$VOLUME" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"tekton.dev/task": $lb}},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", ephemeral: {volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: $v}}}}}},
        {name: "tmp", emptyDir: {}}, {name: "ca-poc", configMap: {name: "ca-poc"}}],
      containers: [{name: "essai", image: $i, command: ["sleep", "7200"],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
        env: [{name: "HOME", value: "/tmp"}],
        resources: {requests: $l, limits: $l},
        volumeMounts: [{name: "w", mountPath: "/workspace/sortie", subPath: "fermeture"}, {name: "tmp", mountPath: "/tmp"},
          {name: "ca-poc", mountPath: "/etc/ca-poc", readOnly: true}]}]}}' > "$T/$POD.json"
}

dans() { # libellé : script sh sur l'entrée standard, exécuté dans le pod ; sortie dans $T/<libellé>.log, puis affichée
  local rc=0
  kubectl exec -i -n builds "$POD" -- sh -s > "$T/$1.log" 2>&1 || rc=$?
  sed 's/^/     /' "$T/$1.log"
  echo "     (code de l'exec : $rc)"
  return "$rc"
}

etape_essai() {
  [ -s "$LISTE" ] || { echo "KO   étape prealables à lancer d'abord (liste absente)" >&2; exit 1; }
  local src dos rc
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$VERROU_SRC")   # config.py:844-846
  echo "source du bootstrap : $src ; dossier dir: : $dos"
  pod_spec
  if kubectl create --dry-run=server -f "$T/$POD.json" < /dev/null > "$T/admis.out" 2>&1; then echo "OK   pod d'essai admis en dry-run serveur"
  else echo "KO   pod d'essai refusé à l'admission : $(head -c 300 "$T/admis.out" | tr '\n' ' ')" >&2; exit 1; fi
  kubectl delete pod -n builds "$POD" --ignore-not-found --wait=true < /dev/null > /dev/null
  kubectl create -f "$T/$POD.json" < /dev/null > /dev/null
  if ! kubectl wait -n builds "pod/$POD" --for=condition=Ready --timeout=300s < /dev/null > /dev/null; then
    kubectl get pod -n builds "$POD" -o json < /dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state
      | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"' >&2   # raisons, jamais les messages
    echo "KO   pod d'essai non prêt" >&2; exit 1
  fi
  echo "### $POD (runc, uid 65532, label tekton.dev/task=$LABEL) : prêt sur $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.nodeName}' < /dev/null), runtimeClassName « $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.runtimeClassName}' < /dev/null) »"
  echo "## sonde (ne s'arrête sur aucun écart)"
  { printf 'export SOURCE=%q\n' "$src"; printf '%s\n' "$SONDE"; } | dans m4b-sonde || true
  kubectl exec -i -n builds "$POD" -- sh -c 'cat > /tmp/liste.txt' < "$LISTE"
  attendu "liste livrée (sha256)" "$(kubectl exec -i -n builds "$POD" -- sha256sum /tmp/liste.txt < /dev/null | cut -c1-64)" "$(sha256sum < "$LISTE" | cut -c1-64)"
  local p
  for p in p1 p2; do
    echo "## passage $p"
    rc=0
    { printf 'export SORTIE=/workspace/sortie/%s LISTE_FICHIER=/tmp/liste.txt SOURCE=%q DOSSIER=%q FP_ROCKY=%s\n' "$p" "$src" "$dos" "$FP_ROCKY"
      printf 't0=$(date +%%s)\n%s\necho "durée du passage : $(($(date +%%s) - t0)) s"\n' "$PREFETCH"; } | dans "m4b-$p" || rc=$?
    [ "$rc" = 0 ] || { echo "KO   passage $p en échec ; pod laissé pour lecture : $POD" >&2; exit 1; }
  done
  echo "## comparaisons"
  dans m4b-comparaisons <<<"$COMPARE" || true
  kubectl delete pod -n builds "$POD" --wait=false < /dev/null > /dev/null && echo "pod $POD supprimé (volume éphémère avec lui)"
}

lancer m4b "05 M4b" "$@"
