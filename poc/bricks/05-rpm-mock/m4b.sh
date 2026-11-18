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
#   final       ajoutée le 17/11/2026 sur « Oui, prépare-le » (décision « V2 »), NON LANCÉE : le pas de prefetch final, joué
#               entier (PREFETCH_FINAL, script distinct ; PREFETCH reste celui mesuré à l'essai), dans deux pods neufs (un par
#               passage, chacun avec son volume éphémère), montages et label de l'essai : gpg obligatoire (repli sur l'identifiant
#               court retiré, contrôle de l'identifiant court gardé), rpm datés à 0 puis createrepo_c en variante V2, repomd.xml
#               imprimé en entier ; côté hôte : repomd.xml de chaque passage égal à celui de l'essai, arbre entier (repodata
#               compris : chemin, taille, sha256) égal entre les deux passages et archivé, retrait de chaque pod relu (code de
#               kubectl, pods et PVC au nom du pod). N'écrit rien dans Zot.
#   prealables_taches  ajoutée le 17/11/2026 sur « Oui, prépare-les » (carte de taches, décision « Oui » sur repomd.xml), NON
#               LANCÉE ; hôte, plus une lecture sur sc-stockage : gabarits fermeture/prefetch-rpm.yaml et
#               fermeture/prefetch-rpm-sample-app.yaml rendus (références des tâches factices) et relus ; script de la tâche comparé
#               à PREFETCH_FINAL (écarts attendus seulement), puis substitué comme Tekton le fera (paramètres de la pipeline rendue,
#               workspace, résultat) : aucune référence de Tekton restante, liste du heredoc égale à resultats/m4b-liste.txt ;
#               section d'envoi de publier-fermeture (version signée) jouée deux fois sur l'hôte, en layout OCI local, sur un arbre
#               aux 230 vrais noms de resultats/m4b-final-arbre.txt (226 fichiers réels, en liens durs depuis la fermeture
#               restaurée de M3, contrôlés par sha256 ; 4 de repodata factices) : même digest, 230 couches aux titres attendus ;
#               espace de /var/lib/zot relevé (df, sans sudo). N'écrit rien dans Zot ni dans le cluster.
#   essai_tache ajoutée de même, NON LANCÉE ; cluster, pod d'essai, rien dans Zot : le script substitué de la tâche, tel qu'il sera
#               signé, joué dans un pod neuf de l'essai (runc, UID 65532, label prefetch-rpm), workspace à /workspace/sortie ;
#               code 0, repomd.xml égal à l'attendu, résultat BOOTSTRAP_ARTIFACT_INPUTS relu, arbre égal à celui de final ; puis
#               le même script avec un repomd.xml attendu faux, dans un sous-dossier neuf : refus attendu avant la copie de
#               l'image ; retrait du pod et de sa PVC relus.
#   taches      ajoutée le 18/11/2026 (préparée à sec, accord permanent du 18/11), NON LANCÉE ; écritures dans Zot (bundles, compte
#               poc-ecriture), rien dans le cluster (dry-run serveur seulement) : publier-fermeture lue dans la liste revue
#               (7fa92ad3) ; gabarits rendus admis en dry-run serveur dans builds, témoin refusé (computeResources, nom du champ
#               en v1, dans un pas v1beta1 : refus mesuré dans resultats/m4b-taches-admission.log) ; prefetch-rpm signée par tkn
#               avec la clé des tâches (jamais lue ici), contrôlée avant tout versionnement (signature, image, paramètres,
#               ressources, sécurité, env, résultat objet, script substitué égal à celui de essai_tache) ; avec SIGNER=1 :
#               signature versionnée dans fermeture/prefetch-rpm.signee.yaml si le contenu a changé, bundle
#               tekton/tasks/prefetch-rpm:m4b, digest à ajouter à la liste revue de la 08 après revue du propriétaire, pipeline
#               non signée ; sans SIGNER : bundle de la tâche présent dans la liste revue, pipeline rendue avec les deux références
#               de la liste, admise, signée, relue, bundle tekton/pipelines/prefetch-rpm-sample-app:m4b.
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
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copie du secret de Zot (étape taches), retirée même en cas d'échec ; comme m4a.sh
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

# Pas de prefetch final (décision « V2 » du 17/11/2026), base du script de la tâche prefetch-rpm : PREFETCH avec trois changements
# seulement. 1. gpg obligatoire : plus de repli sur l'identifiant court seul (contrôle de l'identifiant court gardé). 2. rpm datés à
# l'époque 0 puis createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database (variante V2 de l'essai et de
# m4b_mock_v2), fin de son journal imprimée en cas d'échec. 3. repomd.xml imprimé en entier et nombre de fichiers de repodata.
# Entrées et sorties : celles de PREFETCH. La valeur attendue de repomd.xml reste côté hôte.
PREFETCH_FINAL=$(cat <<'SH'
set -u
ko() { echo "KO   $*" >&2; exit 1; }
for o in curl rpm createrepo_c skopeo sha256sum stat gpg; do command -v "$o" >/dev/null 2>&1 || ko "$o absent de l'image"; done
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
fp=$(gpg --batch --with-colons --show-keys "$K" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
[ "$fp" = "$FP_ROCKY" ] || ko "empreinte de la clé de l'image : $fp"
echo "clé de Rocky de l'image : empreinte conforme (gpg)"
B=/tmp/rpmdb-$$
rpm --dbpath "$B" --initdb </dev/null || ko "rpmdb vide non créée"
rpm --dbpath "$B" --import "$K" </dev/null || ko "clé de Rocky non importée"
v=$(rpm --dbpath "$B" -q gpg-pubkey --qf '%{VERSION}\n' </dev/null)
[ "$v" = "$(printf %s "$FP_ROCKY" | tail -c 8 | tr 'A-F' 'a-f')" ] || ko "identifiant court de la clé importée : $v"
r=0; rpm --dbpath "$B" -K "$D"/*.rpm > /tmp/k.log 2>&1 </dev/null || r=$?
k=$(grep -c ': digests signatures OK$' /tmp/k.log)
echo "rpm -K : rc $r, $k OK sur $n"
[ "$r" = 0 ] && [ "$k" = "$n" ] || ko "signatures des rpm"
find "$D" -maxdepth 1 -name "*.rpm" -exec touch -h -d @0 {} + || ko "dates des rpm"
t=$(date +%s)
createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database "$D" > /tmp/createrepo.log 2>&1 </dev/null \
  || { tail -n 20 /tmp/createrepo.log; ko "createrepo_c V2"; }
echo "repodata V2 : repomd.xml $(sha256sum < "$D/repodata/repomd.xml" | cut -c1-64) ; fichiers $(ls "$D/repodata" | wc -l) ; en $(($(date +%s) - t)) s"
sed "s/^/repomd.xml V2 : /" "$D/repodata/repomd.xml"
t=$(date +%s)
skopeo copy --preserve-digests --src-cert-dir /etc/ca-poc "docker://$SOURCE" "dir:$D/$DOSSIER" > /tmp/skopeo.log 2>&1 </dev/null \
  || { tail -n 5 /tmp/skopeo.log; ko "skopeo copy"; }
m=sha256:$(sha256sum < "$D/$DOSSIER/manifest.json" | cut -c1-64)
[ "$m" = "${SOURCE##*@}" ] || ko "manifeste copié : $m"
echo "skopeo copy --preserve-digests : en $(($(date +%s) - t)) s ; manifeste $m"
echo "fermeture : $(find "$D" -type f | wc -l) fichiers, $(du -sb "$D" | cut -f1) octets"
SH
)

# Arbre de la fermeture après le pas final, repodata compris : « chemin taille sha256 » par fichier, trié. Hors tâche.
ARBRE=$(cat <<'SH'
set -u
cd "$SORTIE/depot" || exit 1
find . -type f -printf '%P %s\n' | sort | while read -r f s; do echo "$f $s $(sha256sum < "$f" | cut -c1-64)"; done
SH
)
REPOMD_V2=239a5a71c887d4370228ffdff016517282086f19de93418ee740482c089be164   # essai de M4b (deux copies) et m4b_mock_v2 (f14ec28)
LISTE_SHA=95541ee86a3c8891d231df6896558a78f73a607037b2a7035312337ab80b8910   # resultats/m4b-liste.txt (prealables, c29cd30)
ARBRE_REF=$R/m4b-final-arbre.txt

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

etape_final() { # deux pods neufs, un par passage ; le pas final entier dans chacun ; arbres comparés sur l'hôte ; retraits relus
  [ -s "$LISTE" ] || { echo "KO   étape prealables à lancer d'abord (liste absente)" >&2; exit 1; }
  attendu "liste des rpm (sha256)" "$(sha256sum < "$LISTE" | cut -c1-64)" "$LISTE_SHA"
  local src dos rc p POD
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$VERROU_SRC")   # config.py:844-846
  echo "source du bootstrap : $src ; dossier dir: : $dos"
  for p in p1 p2; do
    POD=m4b-05-final-$p
    echo "## passage $p : pod neuf $POD"
    pod_spec
    if kubectl create --dry-run=server -f "$T/$POD.json" < /dev/null > "$T/admis-$POD.out" 2>&1; then echo "OK   $POD admis en dry-run serveur"
    else echo "KO   $POD refusé à l'admission : $(head -c 300 "$T/admis-$POD.out" | tr '\n' ' ')" >&2; exit 1; fi
    kubectl delete pod -n builds "$POD" --ignore-not-found --wait=true < /dev/null > /dev/null
    kubectl create -f "$T/$POD.json" < /dev/null > /dev/null
    if ! kubectl wait -n builds "pod/$POD" --for=condition=Ready --timeout=300s < /dev/null > /dev/null; then
      kubectl get pod -n builds "$POD" -o json < /dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state
        | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"' >&2   # raisons, jamais les messages
      echo "KO   $POD non prêt" >&2; exit 1
    fi
    echo "### $POD (runc, uid 65532, label tekton.dev/task=$LABEL) : prêt sur $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.nodeName}' < /dev/null), runtimeClassName « $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.runtimeClassName}' < /dev/null) »"
    kubectl exec -i -n builds "$POD" -- sh -c 'cat > /tmp/liste.txt' < "$LISTE"
    attendu "$p : liste livrée (sha256)" "$(kubectl exec -i -n builds "$POD" -- sha256sum /tmp/liste.txt < /dev/null | cut -c1-64)" "$LISTE_SHA"
    rc=0
    { printf 'export SORTIE=/workspace/sortie LISTE_FICHIER=/tmp/liste.txt SOURCE=%q DOSSIER=%q FP_ROCKY=%s\n' "$src" "$dos" "$FP_ROCKY"
      printf 't0=$(date +%%s)\n%s\necho "durée du passage : $(($(date +%%s) - t0)) s"\n' "$PREFETCH_FINAL"; } | dans "m4b-final-$p" || rc=$?
    [ "$rc" = 0 ] || { echo "KO   passage $p en échec ; pod laissé pour lecture : $POD" >&2; exit 1; }
    attendu "$p : repomd.xml V2" "$(grep -m 1 '^repodata V2 : repomd.xml ' "$T/m4b-final-$p.log" | cut -d' ' -f5)" "$REPOMD_V2"
    rc=0; printf 'export SORTIE=/workspace/sortie\n%s\n' "$ARBRE" | kubectl exec -i -n builds "$POD" -- sh -s > "$T/m4b-final-$p-arbre.txt" 2> "$T/m4b-final-$p-arbre.err" || rc=$?
    attendu "$p : arbre relevé (code de l'exec)" "$rc" 0
    echo "$p : arbre de $(wc -l < "$T/m4b-final-$p-arbre.txt") fichiers, dont repodata $(grep -c '^repodata/' "$T/m4b-final-$p-arbre.txt"), sha256 de la liste $(sha256sum < "$T/m4b-final-$p-arbre.txt" | cut -c1-64)"
    rc=0; kubectl delete pod -n builds "$POD" --wait=true --timeout=180s < /dev/null > /dev/null || rc=$?
    attendu "$p : retrait du pod (code de kubectl)" "$rc" 0
    rc=0; kubectl wait -n builds --for=delete "pvc/$POD-w" --timeout=180s < /dev/null > /dev/null 2>&1 || rc=$?   # PVC du volume éphémère : <pod>-<volume>
    attendu "$p : PVC $POD-w retirée (code de kubectl wait)" "$rc" 0
    rc=0; kubectl get pods,pvc -n builds -o name < /dev/null > "$T/m4b-final-$p-objets.txt" 2>&1 || rc=$?
    attendu "$p : objets de builds relus (code de kubectl)" "$rc" 0
    attendu "$p : pods et PVC restants au nom de $POD" "$(grep -c -F "$POD" "$T/m4b-final-$p-objets.txt" || true)" 0
  done
  echo "## arbres des deux passages (repodata compris)"
  attendu "arbres p1 et p2 égaux" "$([ "$(sha256sum < "$T/m4b-final-p1-arbre.txt")" = "$(sha256sum < "$T/m4b-final-p2-arbre.txt")" ] && echo égaux || echo différents)" égaux
  attendu "arbre : fichiers (222 rpm, 4 de repodata, 4 du dossier dir:)" "$(wc -l < "$T/m4b-final-p1-arbre.txt")" 230
  if [ -e "$ARBRE_REF" ]; then
    attendu "arbre égal à celui archivé" "$([ "$(sha256sum < "$T/m4b-final-p1-arbre.txt")" = "$(sha256sum < "$ARBRE_REF")" ] && echo égal || echo différent)" égal
  else
    cp "$T/m4b-final-p1-arbre.txt" "$ARBRE_REF" && echo "arbre archivé : resultats/${ARBRE_REF##*/}"
  fi
}

# Brique 05, M4b, étape taches : préalables et pod d'essai de la tâche prefetch-rpm (carte du 17/11/2026, décision « Oui »).
TACHES=$h05/fermeture
PUBLIER_SIGNEE=$here/politique/taches/publier-fermeture.signee.yaml
DEPOT_FERMETURE=$REG/builds/fermetures/sample-app-rpm
RESTAUREE=$T1/m3/restauree-1/depot   # fermeture de M2 restaurée en M3 : 226 des 230 fichiers de final, mêmes sha256
FACTICE=sha256:$(printf '0%.0s' {1..64})
remplacer() { # source destination clé=valeur… : @CLE@ remplacées hors des commentaires ; LISTE = fichier indenté (s4b.sh de la 06)
  python3 -I - "$@" <<'FIN'
import sys
src, dst, *kv = sys.argv[1:]
paires = [a.split('=', 1) for a in kv]
r = []
for ligne in open(src, encoding='utf-8').read().split('\n'):
    if not ligne.lstrip().startswith('#'):   # les commentaires citent les variables : non rendus
        for k, v in paires:
            if k == 'LISTE':
                v = open(v, encoding='utf-8').read().rstrip('\n')
            ligne = ligne.replace(f'@{k}@', v)
    r.append(ligne)
open(dst, 'w', encoding='utf-8').write('\n'.join(r))
FIN
  ! grep -n '@[A-Z_]*@' "$2" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans ${2##*/}" >&2; exit 1; }
}
rendre_taches() { # référence-prefetch-rpm référence-publier-fermeture source dossier : gabarits rendus sous $T
  sed 's/^/        /' "$LISTE" > "$T/liste-indentee.txt"
  remplacer "$TACHES/prefetch-rpm.yaml" "$T/prefetch-rpm.yaml" "IMAGE=$IMAGE"
  remplacer "$TACHES/prefetch-rpm-sample-app.yaml" "$T/prefetch-rpm-sample-app.yaml" "PREFETCH_RPM=$1" "PUBLIER_FERMETURE=$2" \
    "LISTE=$T/liste-indentee.txt" "SOURCE=$3" "DOSSIER=$4" "EMPREINTE=$FP_ROCKY" "REPOMD=$REPOMD_V2" "DEPOT_FERMETURE=$DEPOT_FERMETURE"
}
substituer() { # tâche-rendue pipeline-rendue chemin-du-workspace chemin-du-résultat sortie [repomd] : script du pas, comme Tekton
  python3 -I - "$@" <<'FIN'
import json, subprocess, sys
tache, pipe, ws, res, out = sys.argv[1:6]
y = lambda f, q: json.loads(subprocess.run(['yq', '-o=json', q, f], capture_output=True, text=True, check=True).stdout)
s = y(tache, '.spec.steps[0].script')
p = {x['name']: x['value'] for x in y(pipe, '.spec.tasks[0].params')}
if len(sys.argv) > 6:
    p['repomd'] = sys.argv[6]   # cas refusé de essai_tache seulement
assert sorted(p) == ['dossier', 'empreinte', 'liste', 'repomd', 'source'], sorted(p)
for k, v in p.items():
    s = s.replace('$(params.' + k + ')', v)
s = s.replace('$(workspaces.sortie.path)', ws).replace('$(results.BOOTSTRAP_ARTIFACT_INPUTS.path)', res)
assert not any(m in s for m in ('$(params.', '$(workspaces.', '$(results.', '$(context.')), 'référence de Tekton restante'
open(out, 'w', encoding='utf-8').write(s)
FIN
}
extraire() { # nom-de-variable : corps d'un script heredoc de ce fichier (PREFETCH_FINAL…)
  awk -v n="$1" '$0 == n "=$(cat <<'"'"'SH'"'"'" {b = 1; next} b && $0 == "SH" {exit} b' "${BASH_SOURCE[0]}"
}

etape_prealables_taches() {
  attendu "liste des rpm (sha256)" "$(sha256sum < "$LISTE" | cut -c1-64)" "$LISTE_SHA"
  local src dos x n a d1 d2
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$VERROU_SRC")   # config.py:844-846
  echo "source du bootstrap : $src ; dossier dir: : $dos"
  echo "## gabarits rendus (références des tâches factices)"
  rendre_taches "$REG/tekton/tasks/prefetch-rpm@$FACTICE" "$REG/tekton/tasks/publier-fermeture@$FACTICE" "$src" "$dos"
  attendu "tâche : nom, image" "$(yq '.metadata.name + " " + .spec.steps[0].image' "$T/prefetch-rpm.yaml")" "prefetch-rpm $IMAGE"
  attendu "tâche : paramètres" "$(yq -o=json -I=0 '[.spec.params[].name]' "$T/prefetch-rpm.yaml")" '["liste","source","dossier","empreinte","repomd"]'
  attendu "tâche : UID, runAsNonRoot, capacités, élévation" \
    "$(yq '.spec.stepTemplate.securityContext | [.runAsUser, .runAsNonRoot, .capabilities.drop[0], .allowPrivilegeEscalation] | join(" ")' "$T/prefetch-rpm.yaml")" "65532 true ALL false"
  attendu "tâche : ressources du pas, champ resources de v1beta1 (demandes, limites)" \
    "$(yq -o=json -I=0 '[.spec.steps[0].resources, ([.. | select(tag == "!!map") | keys[] | select(. == "computeResources")] | length)]' "$T/prefetch-rpm.yaml")" '[{"requests":{"cpu":"2","memory":"2Gi"},"limits":{"cpu":"2","memory":"2Gi"}},0]'
  attendu "tâche : variables d'environnement du pas" "$(yq -o=json -I=0 '.spec.steps[0].env' "$T/prefetch-rpm.yaml")" '[{"name":"HOME","value":"/tmp"}]'
  attendu "pipeline : liste rendue identique à la liste" \
    "$(yq '.spec.tasks[0].params[] | select(.name == "liste") | .value' "$T/prefetch-rpm-sample-app.yaml" | sed '/^$/d' | cmp -s - "$LISTE" && echo identique || echo différente)" identique
  attendu "pipeline : source, dossier, empreinte, repomd" \
    "$(yq '[.spec.tasks[0].params[] | select(.name != "liste") | .value] | join(" ")' "$T/prefetch-rpm-sample-app.yaml")" "$src $dos $FP_ROCKY $REPOMD_V2"
  attendu "pipeline : subPath de prefetch, racine pour publier" \
    "$(yq -o=json -I=0 '[.spec.tasks[].workspaces[0].subPath]' "$T/prefetch-rpm-sample-app.yaml")" '["fermeture",null]'
  attendu "pipeline : tâches, dépôt de la fermeture" \
    "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "name") | .value] + [.spec.tasks[1].params[0].value] | join(" ")' "$T/prefetch-rpm-sample-app.yaml")" \
    "prefetch-rpm publier-fermeture $DEPOT_FERMETURE"
  echo "## script de la tâche contre PREFETCH_FINAL (étape final)"
  yq '.spec.steps[0].script' "$T/prefetch-rpm.yaml" | sed '${/^$/d}' > "$T/script-tache.sh"   # yq ajoute une ligne vide finale
  extraire PREFETCH_FINAL > "$T/prefetch-final.sh"
  diff "$T/prefetch-final.sh" "$T/script-tache.sh" > "$T/diff-script.txt" || true
  sed 's/^/     /' "$T/diff-script.txt"
  attendu "ligne retirée de PREFETCH_FINAL (la clé réglable)" "$(grep '^<' "$T/diff-script.txt" | cut -c3- | sed 's/ .*//' | paste -sd' ')" 'K=${CLE_ROCKY:-/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9}'
  attendu "lignes ajoutées (en-tête 13, contrôles 13, clé 1, repomd.xml 1, résultat 1)" "$(grep -c '^>' "$T/diff-script.txt")" 29
  attendu "script de la tâche, dash -n" "$(sh -n "$T/script-tache.sh" && echo ok)" ok
  echo "## script substitué comme par Tekton"
  substituer "$T/prefetch-rpm.yaml" "$T/prefetch-rpm-sample-app.yaml" /workspace/sortie /tmp/resultat-bootstrap.json "$T/script-essai.sh"
  attendu "script substitué, dash -n" "$(sh -n "$T/script-essai.sh" && echo ok)" ok
  attendu "liste du heredoc égale à la liste" \
    "$(awk '$0 == "cat > /tmp/liste <<'"'"'FIN_LISTE'"'"'" {b = 1; next} $0 == "FIN_LISTE" {exit} b' "$T/script-essai.sh" | sed '/^$/d' | cmp -s - "$LISTE" && echo égale || echo différente)" égale
  echo "script substitué : $(wc -c < "$T/script-essai.sh") octets, sha256 $(sha256sum < "$T/script-essai.sh" | cut -c1-64)"
  echo "## publier-fermeture : section d'envoi (version signée) sur les 230 vrais noms"
  x=$T/pf; rm -rf -- "${x:?}"; mkdir -p "$x/a/fermeture/depot"
  n=0; a=0
  while read -r f s h; do
    mkdir -p "$x/a/fermeture/depot/$(dirname "$f")"
    case $f in
      repodata/*) printf 'repodata factice : %s\n' "$f" > "$x/a/fermeture/depot/$f"; a=$((a + 1)) ;;
      *) [ "$(sha256sum < "$RESTAUREE/$f" | cut -c1-64) $(stat -c %s "$RESTAUREE/$f")" = "$h $s" ] \
           || { echo "KO   fichier de la fermeture restaurée différent de final : $f" >&2; exit 1; }
         ln "$RESTAUREE/$f" "$x/a/fermeture/depot/$f"; n=$((n + 1)) ;;
    esac
  done < "$ARBRE_REF"
  attendu "arbre : fichiers réels (liens durs, sha256 et taille de final), factices de repodata" "$n $a" "226 4"
  cp -al "$x/a" "$x/b"
  for d in a b; do
    { echo 'set -eu'; echo "f=$x/$d/fermeture"
      yq '.spec.steps[0].script' "$PUBLIER_SIGNEE" | sed -n '/^cd "\$f"$/,/^  --annotation/p' | sed "s#/layout/f:#$x/$d/layout:#"
      echo 'echo "$d"'; } > "$x/$d/publier.sh"
  done
  attendu "section extraite : cd, boucle find, oras push" "$(grep -c '^cd "$f"$\|find . -type f\|oras push' "$x/a/publier.sh")" 3
  d1=$(sh "$x/a/publier.sh" 2>&1 | tail -n 1); d2=$(sh "$x/b/publier.sh" 2>&1 | tail -n 1)
  attendu "digest du manifeste, layout local" "$d1" "$(jq -r '.manifests[0].digest' "$x/a/layout/index.json")"
  attendu "seconde poussée, autre copie : même digest" "$d2" "$d1"
  jq -r '.layers[].annotations["org.opencontainers.image.title"]' "$x/a/layout/blobs/sha256/${d1#sha256:}" | LC_ALL=C sort > "$x/titres.txt"
  attendu "couches : nombre, titres distincts" "$(wc -l < "$x/titres.txt") $(sort -u "$x/titres.txt" | wc -l)" "230 230"
  attendu "titres égaux aux chemins de final, préfixés par depot/" \
    "$(sed 's#^#depot/#' "$ARBRE_REF" | cut -d' ' -f1 | LC_ALL=C sort | cmp -s - "$x/titres.txt" && echo égaux || echo différents)" égaux
  attendu "titres à « : » et « @ » (dossier dir:)" "$(grep -c -F "depot/$dos/" "$x/titres.txt")" 4
  echo "manifeste local : $d1 ; layout : $(du -sb "$x/a/layout" | cut -f1) octets ; oras de l'hôte : $(oras version 2>/dev/null | head -n 1)"
  echo "## espace de /var/lib/zot (lecture sur sc-stockage, sans sudo)"
  sur sc-stockage 'df -B1 --output=used,avail /var/lib/zot | tail -n 1' < /dev/null | awk '{print "utilisés " $1 " octets ; libres " $2 " octets"}'
}

etape_essai_tache() { # pod d'essai : le script substitué de la tâche, tel qu'il sera signé ; puis le cas refusé (repomd.xml faux)
  attendu "liste des rpm (sha256)" "$(sha256sum < "$LISTE" | cut -c1-64)" "$LISTE_SHA"
  local src dos rc POD=m4b-05-essai-tache faux=0000000000000000000000000000000000000000000000000000000000000000
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$VERROU_SRC")
  rendre_taches "$REG/tekton/tasks/prefetch-rpm@$FACTICE" "$REG/tekton/tasks/publier-fermeture@$FACTICE" "$src" "$dos"
  substituer "$T/prefetch-rpm.yaml" "$T/prefetch-rpm-sample-app.yaml" /workspace/sortie /tmp/resultat-bootstrap.json "$T/script-essai.sh"
  substituer "$T/prefetch-rpm.yaml" "$T/prefetch-rpm-sample-app.yaml" /workspace/sortie/refus /tmp/resultat-refus.json "$T/script-refus.sh" "$faux"
  attendu "scripts : nominal et refusé, seuls écarts le workspace, le résultat et repomd" \
    "$(diff "$T/script-essai.sh" "$T/script-refus.sh" | grep -c '^>')" 3
  echo "script substitué : sha256 $(sha256sum < "$T/script-essai.sh" | cut -c1-64)"
  pod_spec
  if kubectl create --dry-run=server -f "$T/$POD.json" < /dev/null > "$T/admis-$POD.out" 2>&1; then echo "OK   $POD admis en dry-run serveur"
  else echo "KO   $POD refusé à l'admission : $(head -c 300 "$T/admis-$POD.out" | tr '\n' ' ')" >&2; exit 1; fi
  kubectl delete pod -n builds "$POD" --ignore-not-found --wait=true < /dev/null > /dev/null
  kubectl create -f "$T/$POD.json" < /dev/null > /dev/null
  if ! kubectl wait -n builds "pod/$POD" --for=condition=Ready --timeout=300s < /dev/null > /dev/null; then
    kubectl get pod -n builds "$POD" -o json < /dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state
      | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"' >&2   # raisons, jamais les messages
    echo "KO   $POD non prêt" >&2; exit 1
  fi
  echo "### $POD (runc, uid 65532, label tekton.dev/task=$LABEL) : prêt sur $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.nodeName}' < /dev/null), runtimeClassName « $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.runtimeClassName}' < /dev/null) »"
  echo "## script de la tâche, nominal"
  rc=0; { printf 't0=$(date +%%s)\n'; cat "$T/script-essai.sh"; printf 'echo "durée du pas : $(($(date +%%s) - t0)) s"\n'; } | dans m4b-essai-tache || rc=$?
  [ "$rc" = 0 ] || { echo "KO   script de la tâche en échec ; pod laissé pour lecture : $POD" >&2; exit 1; }
  attendu "repomd.xml V2" "$(grep -m 1 '^repodata V2 : repomd.xml ' "$T/m4b-essai-tache.log" | cut -d' ' -f5)" "$REPOMD_V2"
  attendu "résultat BOOTSTRAP_ARTIFACT_INPUTS" "$(kubectl exec -n builds "$POD" -- cat /tmp/resultat-bootstrap.json < /dev/null)" \
    "{\"uri\":\"oci://${src%@*}\",\"digest\":\"${src##*@}\"}"
  rc=0; printf 'export SORTIE=/workspace/sortie\n%s\n' "$ARBRE" | kubectl exec -i -n builds "$POD" -- sh -s > "$T/m4b-essai-tache-arbre.txt" 2> "$T/m4b-essai-tache-arbre.err" || rc=$?
  attendu "arbre relevé (code de l'exec)" "$rc" 0
  attendu "arbre égal à celui de final" "$([ "$(sha256sum < "$T/m4b-essai-tache-arbre.txt")" = "$(sha256sum < "$ARBRE_REF")" ] && echo égal || echo différent)" égal
  echo "## même script, repomd.xml attendu faux, workspace neuf (refus attendu avant la copie de l'image)"
  rc=0; dans m4b-essai-tache-refus < "$T/script-refus.sh" || rc=$?
  attendu "cas refusé : code" "$rc" 1
  attendu "cas refusé : message" "$(grep -c '^KO   repomd.xml différent de l.attendu (fixé par la pipeline)$' "$T/m4b-essai-tache-refus.log")" 1
  attendu "cas refusé : ni dossier dir:, ni résultat" \
    "$(kubectl exec -n builds "$POD" -- sh -c "ls -A /workspace/sortie/refus/depot | grep -c -F '$dos' ; ls /tmp/resultat-refus.json 2>/dev/null | wc -l" < /dev/null | paste -sd' ')" "0 0"
  rc=0; kubectl delete pod -n builds "$POD" --wait=true --timeout=180s < /dev/null > /dev/null || rc=$?
  attendu "retrait du pod (code de kubectl)" "$rc" 0
  rc=0; kubectl wait -n builds --for=delete "pvc/$POD-w" --timeout=180s < /dev/null > /dev/null 2>&1 || rc=$?   # PVC du volume éphémère
  attendu "PVC $POD-w retirée (code de kubectl wait)" "$rc" 0
  rc=0; kubectl get pods,pvc -n builds -o name < /dev/null > "$T/m4b-essai-tache-objets.txt" 2>&1 || rc=$?
  attendu "objets de builds relus (code de kubectl)" "$rc" 0
  attendu "pods et PVC restants au nom de $POD" "$(grep -c -F "$POD" "$T/m4b-essai-tache-objets.txt" || true)" 0
}

# Brique 05, M4b, étape taches (préparée à sec le 18/11/2026, accord permanent du 18/11) : signature de prefetch-rpm, bundles.
SCRIPT_ESSAI_SHA=572fb78cf6b3104dbbbe2c834d236d313f1eb49e0da9b4171d03fc299fc42145   # script substitué de prealables_taches et essai_tache
PUBLIER_REF=$REG/tekton/tasks/publier-fermeture@sha256:7fa92ad3e4adb0d4b9bc4209ee04096d476dee5ffa173fc08b9cac0614e2b135   # liste revue
echec() { echo "KO   $*" >&2; exit 1; }   # les ko() de ce fichier sont dans les scripts heredoc du pod, pas au niveau haut
ref_revue() { # dépôt-de-tâche préfixe-du-digest : référence complète lue dans la liste revue de la 08 (une seule ; s4b.sh de la 06)
  local r
  r=$(awk -v d="oci://$REG/tekton/tasks/$1:" -v p="sha256:$2" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && index($3, p) == 1 {print $3}' "$here/politique/porte/taches.yml")
  [ "$(grep -c . <<< "$r")" = 1 ] && [ -n "$r" ] || { echo "KO   $1 $2 : absente de la liste revue ou ambiguë" >&2; exit 1; }
  echo "$REG/tekton/tasks/$1@$r"
}
admission() { # fichier : kubectl create --dry-run=server dans builds (rien n'est créé) ; code de kubectl, sortie dans $T/admission.out
  local rc=0
  kubectl create --dry-run=server -n builds -f "$1" < /dev/null > "$T/admission.out" 2>&1 || rc=$?
  echo "$rc"
}
controler_signee() { # tâche-signée pipeline-rendue : contenu signé relu (signature, ressources, script substitué comme Tekton)
  attendu "tâche signée : annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$1")" true
  attendu "tâche signée : nom, image, paramètres" "$(yq -o=json -I=0 '[.metadata.name, .spec.steps[0].image, [.spec.params[].name]]' "$1")" \
    "[\"prefetch-rpm\",\"$IMAGE\",[\"liste\",\"source\",\"dossier\",\"empreinte\",\"repomd\"]]"
  attendu "tâche signée : ressources du pas (resources de v1beta1, clés triées), aucun computeResources" \
    "$(yq -o=json -I=0 '[(.spec.steps[0].resources | sort_keys(..)), ([.. | select(tag == "!!map") | keys[] | select(. == "computeResources")] | length)]' "$1")" \
    '[{"limits":{"cpu":"2","memory":"2Gi"},"requests":{"cpu":"2","memory":"2Gi"}},0]'
  attendu "tâche signée : UID, runAsNonRoot, capacités, élévation" \
    "$(yq '.spec.stepTemplate.securityContext | [.runAsUser, .runAsNonRoot, .capabilities.drop[0], .allowPrivilegeEscalation] | join(" ")' "$1")" "65532 true ALL false"
  attendu "tâche signée : variables d'environnement du pas" "$(yq -o=json -I=0 '.spec.steps[0].env' "$1")" '[{"name":"HOME","value":"/tmp"}]'
  attendu "tâche signée : résultat objet BOOTSTRAP_ARTIFACT_INPUTS (uri, digest)" \
    "$(yq -o=json -I=0 '[.spec.results[0].name, .spec.results[0].type, (.spec.results[0].properties | keys | sort)]' "$1")" '["BOOTSTRAP_ARTIFACT_INPUTS","object",["digest","uri"]]'
  substituer "$1" "$2" /workspace/sortie /tmp/resultat-bootstrap.json "$T/script-signe.sh"
  attendu "script de la tâche signée, substitué comme à l'essai (sha256)" "$(sha256sum < "$T/script-signe.sh" | cut -c1-64)" "$SCRIPT_ESSAI_SHA"
}

etape_taches() { # SIGNER=1 : prefetch-rpm signée, contrôlée, versionnée, bundle, à ajouter à la liste revue ; sinon : de plus la pipeline
  attendu "liste des rpm (sha256)" "$(sha256sum < "$LISTE" | cut -c1-64)" "$LISTE_SHA"
  [ -s "$S/taches.key" ] || echec "clé des tâches absente"
  local src dos v=$TACHES/prefetch-rpm.signee.yaml r rc p
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$VERROU_SRC")
  attendu "publier-fermeture, lue dans la liste revue" "$(ref_revue publier-fermeture 7fa92ad3)" "$PUBLIER_REF"
  echo "## gabarits rendus (prefetch-rpm factice) ; admission en dry-run serveur, rien n'est créé"
  rendre_taches "$REG/tekton/tasks/prefetch-rpm@$FACTICE" "$PUBLIER_REF" "$src" "$dos"
  attendu "tâche rendue admise (code de kubectl)" "$(admission "$T/prefetch-rpm.yaml")" 0
  attendu "pipeline rendue admise (code de kubectl)" "$(admission "$T/prefetch-rpm-sample-app.yaml")" 0
  yq '.spec.steps[0].computeResources = .spec.steps[0].resources | del(.spec.steps[0].resources)' "$T/prefetch-rpm.yaml" > "$T/temoin-v1beta1.yaml"
  rc=$(admission "$T/temoin-v1beta1.yaml")
  [ "$rc" != 0 ] || echec "témoin (computeResources dans un pas v1beta1) admis : le dry-run ne contrôle plus le nom du champ"
  attendu "témoin refusé : champ inconnu (mesuré le 18/11, m4b-taches-admission.log)" \
    "$(grep -c -F 'strict decoding error: unknown field "spec.steps[0].computeResources"' "$T/admission.out")" 1
  echo "## signature de prefetch-rpm (tkn $(tkn version --component client)), contrôlée avant tout versionnement"
  tkn task sign "$T/prefetch-rpm.yaml" -K "$S/taches.key" -f "$T/prefetch-rpm-signee.yaml" > /dev/null
  controler_signee "$T/prefetch-rpm-signee.yaml" "$T/prefetch-rpm-sample-app.yaml"
  if [ -n "${SIGNER:-}" ] && ! { [ -s "$v" ] && cmp -s <(grep -v 'tekton.dev/signature:' "$T/prefetch-rpm-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v"); }; then
    cp "$T/prefetch-rpm-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans fermeture/prefetch-rpm.signee.yaml"
  fi
  [ -s "$v" ] || echec "signature versionnée absente : SIGNER=1, puis revue de la liste"
  attendu "signature versionnée conforme au gabarit rendu, signature exceptée" \
    "$(cmp -s <(grep -v 'tekton.dev/signature:' "$T/prefetch-rpm-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") && echo conforme || echo différente)" conforme
  echo "fermeture/prefetch-rpm.signee.yaml : sha256 $(sha256sum < "$v" | cut -c1-64)"
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh), compte poc-ecriture
  r=$REG/tekton/tasks/prefetch-rpm@$(bundle "$v" tekton/tasks/prefetch-rpm m4b)
  echo "$r" > "$T/prefetch-rpm.ref"
  if listee "$r"; then echo "OK   prefetch-rpm dans la liste revue : $r"
  elif [ -n "${SIGNER:-}" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml (08) après revue du propriétaire : $r"
    echo "SIGNER : pipeline non signée tant que la liste revue n'a pas été acceptée"; return 0
  else echec "prefetch-rpm absente de la liste revue : $r"; fi
  echo "## pipeline prefetch-rpm-sample-app, tâches de la liste revue"
  rendre_taches "$r" "$PUBLIER_REF" "$src" "$dos"
  attendu "pipeline rendue (références réelles) admise (code de kubectl)" "$(admission "$T/prefetch-rpm-sample-app.yaml")" 0
  attendu "pipeline : références des tâches" \
    "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$T/prefetch-rpm-sample-app.yaml")" "$r $PUBLIER_REF"
  controler_signee "$v" "$T/prefetch-rpm-sample-app.yaml"
  tkn pipeline sign "$T/prefetch-rpm-sample-app.yaml" -K "$S/taches.key" -f "$T/prefetch-rpm-sample-app-signee.yaml" > /dev/null
  attendu "pipeline signée : annotation de signature" \
    "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$T/prefetch-rpm-sample-app-signee.yaml")" true
  attendu "pipeline signée : références des tâches" \
    "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$T/prefetch-rpm-sample-app-signee.yaml")" "$r $PUBLIER_REF"
  attendu "pipeline signée : liste égale à la liste" \
    "$(yq '.spec.tasks[0].params[] | select(.name == "liste") | .value' "$T/prefetch-rpm-sample-app-signee.yaml" | sed '/^$/d' | cmp -s - "$LISTE" && echo égale || echo différente)" égale
  attendu "pipeline signée : source, dossier, empreinte, repomd" \
    "$(yq '[.spec.tasks[0].params[] | select(.name != "liste") | .value] | join(" ")' "$T/prefetch-rpm-sample-app-signee.yaml")" "$src $dos $FP_ROCKY $REPOMD_V2"
  attendu "pipeline signée : subPath de prefetch, racine pour publier ; dépôt de la fermeture" \
    "$(yq -o=json -I=0 '[[.spec.tasks[].workspaces[0].subPath], .spec.tasks[1].params[0].value]' "$T/prefetch-rpm-sample-app-signee.yaml")" "[[\"fermeture\",null],\"$DEPOT_FERMETURE\"]"
  p=$REG/tekton/pipelines/prefetch-rpm-sample-app@$(bundle "$T/prefetch-rpm-sample-app-signee.yaml" tekton/pipelines/prefetch-rpm-sample-app m4b)
  echo "$p" | tee "$T/prefetch-rpm-sample-app.ref"
}

lancer m4b "05 M4b" "$@"
