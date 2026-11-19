#!/usr/bin/env bash
# Brique 05, jalon M1b (carte resultats/m1b-carte.md, points 2 à 4) : les deux tâches neuves (prefetch-racine-rpm en runc sans root,
# construire-racine-rpm en Kata privilégié sans sortie) et le gabarit de pipeline builder-rpm, préparés à sec le 19/11/2026, puis
# éprouvés avant toute signature (processus allégé) :
#   prealables       hôte, hors ligne : valeurs relues contre les bancs et les journaux archivés ; gabarits rendus pour les deux
#                    images (références de tâches factices) ; contrôles de forme ; fichiers de configuration de l'outillage tirés de
#                    la couche de S1 et repassés par l'analyseur de la tâche ; scripts substitués comme par Tekton (quatre : prefetch
#                    et construction, outillage et bootstrap), bash -n, shellcheck, tailles
#   banc             hôte, hors ligne : les deux scripts de construction substitués, joués tels quels dans une racine de l'amorce
#                    extraite à neuf (chroot sous unshare -n, /w et /tmp à part), sur les entrées des bancs du 18/11 assemblées comme
#                    le prefetch les écrirait ; racines comparées aux cibles (par la tâche elle-même) ; layouts relus (python, oras)
#   essai_prefetch   cluster : PVC $N-w ; deux pods runc au label prefetch-rpm (sortie posée le 16/11 : DNS, 443, Zot), un par
#                    image, qui jouent le script de prefetch substitué ; arbres écrits comparés, fichier par fichier, aux entrées
#                    des bancs ; pods retirés, PVC gardé
#   essai_construire cluster : deux pods Kata au label construire-rpm (construction-rpm-sans-sortie), entrées lues sur le PVC en
#                    lecture seule ; script de construction substitué ; image.tar et digest comparés au banc ; pods et PVC retirés
# Les pods d'essai portent des labels existants : aucune politique neuve, aucune signature, aucune écriture dans Zot. Les labels et
# politiques des tâches neuves sont des changements du cluster à soumettre un par un (point 4 de la carte).
# $N (PREFIXE, m1bt par défaut) préfixe chaque objet : une relance se fait sous un autre préfixe, jamais en purgeant.
# Aucun secret en argument de commande ; journaux filtrés (jeton|token, adresses) ; jamais le message d'une condition ni d'un Event.
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m1b-builders.sh <étape> > …/resultats/m1b-builders-<étape>.log 2>&1
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "$0")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE
N=${PREFIXE:-m1bt}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
T=$W/$N-05
mkdir -p "$T"
umask 022

GAB=$h05/builders
AMORCE=$REG/amont/rockylinux/rockylinux@sha256:ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d   # s1.sh, l. 169
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256   # cache de s1.sh amorce
COUCHE_AMORCE=99c753a880cc03bbe9da8bf6e354c8ba2d99f19058e87b8a55b6487ffcf52f8a   # m1b-amorce-outils.log
BANC_O=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/outils/m   # banc de l'outillage : lecture seule
BANC_B=$HOME/.cache/supply-chain-poc/05/m1b-boot-20261118T214226Z/outils/m          # banc du bootstrap : lecture seule
BANC_IMAGE=$HOME/.cache/supply-chain-poc/05/banc-image/disque/sha256                 # blobs de 99790c13 (passage local de S1)
CONFIG_S1=d3002ab075686a9355bca64963934f6b80bc657ae17d5ca49c1dcd674762b672             # configuration de 99790c13
COUCHE_CONFIG_S1=fd00cdb1ac39ed07d03836b05bd7c24cf435e68a2b29d63403e5dfc4610ac157      # couche de configuration de S1 (gzip)
DIFF_CONFIG_S1=f5710d475bc0e83b67701a96b5aa3dbd01fe971d2d68f097358019c72ba52560        # son diff_id
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D; CLE_ROCKY=3a66e521e7a4abac9768d889c7cd60a8250f59512b275cf576c8a10ff34624c1
FP_EPEL=FF8AD1344597106ECE813B918A3872BF3228467C; CLE_EPEL=fcf0eab4f05a1c0de6363ac4b707600a27a9d774e9b491059e59e6921b255a84
VAULT98=https://dl.rockylinux.org/vault/rocky/9.8; EPA=https://dl.fedoraproject.org/pub/archive/epel/9.8/Everything/x86_64   # m1b-outil.sh
VAULT97=https://dl.rockylinux.org/vault/rocky/9.7
DEPOTS_O="baseos98 $VAULT98/BaseOS/x86_64/os abac8b17ece74b6f242af937c8143f2e76537eb6a82bdc876682bac38b1af163 RPM-GPG-KEY-Rocky-9
appstream98 $VAULT98/AppStream/x86_64/os a3ca4230ce7eda565514f3ab084ce1811903c3eb6308a4c0e0cc7b8af819907b RPM-GPG-KEY-Rocky-9
epel9 $EPA e86fdcd8122292255cddfe6b9ac46f734cd53df89ba0230abbf62efd8cc71e61 -"   # repomd.xml : m1b-outil.log
DEPOTS_B="baseos97 $VAULT97/BaseOS/x86_64/os fa6d50542ea30eff797235527b46f0d21b7ec4159980f64580b4797589055258 RPM-GPG-KEY-Rocky-9"   # s1-hote97.log
CLES_O="RPM-GPG-KEY-Rocky-9 $CLE_ROCKY $FP_ROCKY
RPM-GPG-KEY-EPEL-9 $CLE_EPEL $FP_EPEL"
CLES_B="RPM-GPG-KEY-Rocky-9 $CLE_ROCKY $FP_ROCKY"
LISTE_O=$h05/resultats/m1b-listes-outillage.txt
DNF_O=$GAB/outillage-dnf.conf; DNF_B=$GAB/bootstrap-dnf.conf; CLE_EPEL_F=$GAB/RPM-GPG-KEY-EPEL-9   # copies suivies des bancs (contrôlées)
FICHIERS_O=$GAB/outillage-fichiers.txt; LISTE_B=$GAB/bootstrap-liste.txt                       # idem (couche de S1, s1-hote97.log)
CONF_O=d554fb1ce168663f; CONF_B=7f49d5d39d0f1b1b232482a2b9e416c235ece7885a6858256bae0a2692e9f5ef   # m1b.sh
S_O=1793914619; S_B=1766985142                                                                     # m1b.sh
CIBLE_O=7c07083cd7bee149d391180633ad9cca6c82c7ad0dfa5c6bf248acad0b1ef9b7; CIBLE_B=b063feb3206deb3f1c0ad4eb7b497d683693967d194c7fdd366a2b0094823348
COUCHE_BOOT=812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09; BOOT_DIGEST=sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2
NOMS_O="mock-6.9-1.el9 mock-core-configs-45.2-1.el9 podman-5.8.2-8.el9_8 skopeo-1.22.2-9.el9_8 rocky-release shadow-utils"   # m1b.sh, l. 41
CONFIG_O='{"Env":["PATH=/usr/sbin:/usr/bin:/sbin:/bin","HOME=/root"]}'   # s1.sh, etape_image (crane mutate -e)
ANNOT_B='{"org.opencontainers.image.base.name":"'$REG'/amont/rockylinux/rockylinux","org.opencontainers.image.base.digest":"'$BOOT_DIGEST'"}'   # s1.sh, boot_image
IMAGE_O=$REG/builds/builders/mock-rocky9; IMAGE_B=$REG/builds/builders/rocky9-bootstrap
FACTICE=sha256:0000000000000000000000000000000000000000000000000000000000000000
LABEL_P=prefetch-rpm; LABEL_C=construire-rpm   # labels des pods d'essai : politiques posées (16/11 et M3)
BORNE=131071   # Args[1] du pas, mesuré en M4b (script.go)
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echec() { echo "KO   $*" >&2; exit 1; }
filtre() { sed -E -e 's/<[^>]*@[^>]*>/<adresse retirée>/g' -e "$MASQUE"; }
indenter() { sed 's/^/        /'; }

liste_b() { # liste du bootstrap au format de la tâche, tirée de s1-hote97.log (dix lignes vérifiées par hote97)
  sed -n 's/^OK   .* dans baseos97 : sha256 \([0-9a-f]\{64\}\) (Packages\/[^)]*\/\([^/)]*\.rpm\))$/baseos97 \2 \1/p' "$h05/resultats/s1-hote97.log"
}
noms_b() { sed -n 's/^paquets demandés : //p' "$h05/resultats/s1-boot_racine.log"; }

etape_prealables() {
  local x f
  echo "## valeurs, relues contre les bancs et les journaux archivés"
  attendu "dnf.conf de l'outillage (16 car.)" "$(sha256sum < "$BANC_O/dnf.conf" | cut -c1-16)" "$CONF_O"
  attendu "dnf97.conf du bootstrap" "$(sha256sum < "$BANC_B/dnf97.conf" | cut -c1-64)" "$CONF_B"
  for x in baseos98 appstream98 epel9; do
    attendu "repomd.xml de $x (banc) = valeur de la pipeline" "$(sha256sum < "$BANC_O/miroir/$x/repodata/repomd.xml" | cut -c1-64)" "$(awk -v d="$x" '$1 == d {print $3}' <<< "$DEPOTS_O")"
    grep -q "^$x : repomd.xml sha256 $(awk -v d="$x" '$1 == d {print $3}' <<< "$DEPOTS_O") ; copie du 18/11" "$h05/resultats/m1b-outil.log" \
      && echo "OK   repomd.xml de $x cité par m1b-outil.log" || echec "repomd.xml de $x absent de m1b-outil.log"
  done
  attendu "repomd.xml de baseos97 (banc) = valeur de la pipeline" "$(sha256sum < "$BANC_B/miroir/baseos97/repodata/repomd.xml" | cut -c1-64)" "$(awk '{print $3}' <<< "$DEPOTS_B")"
  attendu "clé de Rocky (banc de l'outillage)" "$(sha256sum < "$BANC_O/cles/RPM-GPG-KEY-Rocky-9" | cut -c1-64)" "$CLE_ROCKY"
  attendu "clé de Rocky (banc du bootstrap)" "$(sha256sum < "$BANC_B/cles/RPM-GPG-KEY-Rocky-9" | cut -c1-64)" "$CLE_ROCKY"
  attendu "clé d'EPEL (banc de l'outillage)" "$(sha256sum < "$BANC_O/cles/RPM-GPG-KEY-EPEL-9" | cut -c1-64)" "$CLE_EPEL"
  attendu "couche de l'amorce (cache OCI)" "$(sha256sum < "$OCI/$COUCHE_AMORCE" | cut -c1-64)" "$COUCHE_AMORCE"
  attendu "couche de base du bootstrap (cache OCI)" "$(sha256sum < "$OCI/$COUCHE_BOOT" | cut -c1-64)" "$COUCHE_BOOT"
  attendu "liste de l'outillage : lignes de rpm" "$(grep -vc '^#' "$LISTE_O")" 199
  attendu "liste du bootstrap : lignes" "$(wc -l < "$LISTE_B")" 10
  attendu "builders/bootstrap-liste.txt = liste tirée de s1-hote97.log" "$(liste_b | cmp -s - "$LISTE_B" && echo égale || echo différente)" égale
  attendu "builders/outillage-dnf.conf = dnf.conf du banc" "$(cmp -s "$DNF_O" "$BANC_O/dnf.conf" && echo égal || echo différent)" égal
  attendu "builders/bootstrap-dnf.conf = dnf97.conf du banc" "$(cmp -s "$DNF_B" "$BANC_B/dnf97.conf" && echo égal || echo différent)" égal
  attendu "builders/RPM-GPG-KEY-EPEL-9 = clé du banc" "$(cmp -s "$CLE_EPEL_F" "$BANC_O/cles/RPM-GPG-KEY-EPEL-9" && echo égale || echo différente)" égale
  echo "noms de l'outillage : $NOMS_O ; noms du bootstrap : $(noms_b)"
  [ -n "$(noms_b)" ] || echec "noms du bootstrap absents de s1-boot_racine.log"
  echo "## fichiers de configuration de l'outillage, tirés de la couche de S1 ($COUCHE_CONFIG_S1)"
  attendu "configuration de 99790c13 : diff_id de la couche 2" "$(jq -r '.rootfs.diff_ids[1]' "$BANC_IMAGE/$CONFIG_S1")" "sha256:$DIFF_CONFIG_S1"
  attendu "couche de configuration de S1, décompressée" "$(gzip -dc < "$BANC_IMAGE/$COUCHE_CONFIG_S1" | sha256sum | cut -c1-64)" "$DIFF_CONFIG_S1"
  x=$T/config-s1; [ ! -e "$x" ] || echec "$x existe (relancer sous un autre PREFIXE)"
  mkdir -p "$x"; tar -xzf "$BANC_IMAGE/$COUCHE_CONFIG_S1" -C "$x"
  ( cd "$x" && find . -type f | sed 's|^\./||' | sort ) > "$T/config-s1.noms"
  attendu "fichiers de la couche de S1" "$(paste -sd' ' "$T/config-s1.noms")" "etc/containers/storage.conf etc/mock/poc-rocky-9.7-pret-x86_64.cfg etc/mock/poc-rocky-9.7-x86_64.cfg"
  while read -r f; do
    [ "$(tail -c 1 "$x/$f" | od -An -c | tr -d ' ')" = '\n' ] || echec "$f : ne finit pas par une fin de ligne"
    ! grep -q '^=== ' "$x/$f" || echec "$f : ligne « === » dans le contenu"
    ! tail -n 1 "$x/$f" | grep -q '^$' || echec "$f : ligne vide finale"
    printf '=== %s\n' "$f"; cat "$x/$f"
  done < "$T/config-s1.noms" > "$T/fichiers-outillage.txt"
  echo "paramètre fichiers de l'outillage : $(wc -l < "$T/fichiers-outillage.txt") lignes, $(wc -c < "$T/fichiers-outillage.txt") octets"
  attendu "builders/outillage-fichiers.txt = fichiers de la couche de S1" "$(cmp -s "$FICHIERS_O" "$T/fichiers-outillage.txt" && echo égal || echo différent)" égal
  echo "## gabarits rendus (références de tâches factices)"
  sed "s|@AMORCE@|$AMORCE|" "$GAB/prefetch-racine-rpm.yaml" > "$T/prefetch-racine-rpm.yaml"
  sed "s|@AMORCE@|$AMORCE|" "$GAB/construire-racine-rpm.yaml" > "$T/construire-racine-rpm.yaml"
  rendre_pipeline o builder-mock-rocky9 "$DEPOTS_O" "$LISTE_O" "$CLES_O" "$CLE_EPEL_F" - - "$DNF_O" "$NOMS_O" en_US "$S_O" \
    "$CIBLE_O" "$FICHIERS_O" "$CONFIG_O" '{}' "$IMAGE_O"
  rendre_pipeline b builder-rocky9-bootstrap "$DEPOTS_B" "$LISTE_B" "$CLES_B" - "amont/rockylinux/rockylinux $COUCHE_BOOT" "$COUCHE_BOOT" \
    "$DNF_B" "$(noms_b)" all "$S_B" "$CIBLE_B" - '{}' "$ANNOT_B" "$IMAGE_B"
  for f in prefetch-racine-rpm construire-racine-rpm; do
    attendu "$f : image du pas" "$(yq '.spec.steps[0].image' "$T/$f.yaml")" "$AMORCE"
    attendu "$f : aucun computeResources, aucune variable d'environnement autre que HOME" \
      "$(yq -o=json -I=0 '[([.. | select(tag == "!!map") | keys[] | select(. == "computeResources")] | length), [.spec.steps[0].env[]?.name]]' "$T/$f.yaml")" \
      "$([ $f = prefetch-racine-rpm ] && echo '[0,["HOME"]]' || echo '[0,[]]')"
  done
  attendu "prefetch : UID, runAsNonRoot, capacités, élévation" \
    "$(yq '.spec.stepTemplate.securityContext | [.runAsUser, .runAsNonRoot, .capabilities.drop[0], .allowPrivilegeEscalation] | join(" ")' "$T/prefetch-racine-rpm.yaml")" "65532 true ALL false"
  attendu "construire : contexte du pas = celui du pas construire de construire-rpm signée" \
    "$(yq -o=json -I=0 '.spec.steps[0].securityContext | sort_keys(.)' "$T/construire-racine-rpm.yaml")" \
    "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .securityContext | sort_keys(.)' "$h05/construction/construire-rpm.signee.yaml")"
  attendu "construire : ressources du pas = celles du pas construire de construire-rpm signée" \
    "$(yq -o=json -I=0 '.spec.steps[0].resources | sort_keys(..)' "$T/construire-racine-rpm.yaml")" \
    "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .resources | sort_keys(..)' "$h05/construction/construire-rpm.signee.yaml")"
  for x in o b; do
    f=$T/pipeline-$x.yaml
    attendu "pipeline $x : paramètres de prefetch = ceux de la tâche" "$(yq -o=json -I=0 '[.spec.tasks[0].params[].name]' "$f")" "$(yq -o=json -I=0 '[.spec.params[].name]' "$T/prefetch-racine-rpm.yaml")"
    attendu "pipeline $x : paramètres de construire = ceux de la tâche" "$(yq -o=json -I=0 '[.spec.tasks[1].params[].name]' "$f")" "$(yq -o=json -I=0 '[.spec.params[].name]' "$T/construire-racine-rpm.yaml")"
    attendu "pipeline $x : depots, liste et cles identiques entre prefetch et construire" \
      "$(yq -o=json -I=0 '[.spec.tasks[0].params[] | select(.name == "depots" or .name == "liste" or .name == "cles")] == [.spec.tasks[1].params[] | select(.name == "depots" or .name == "liste" or .name == "cles")]' "$f")" true
    attendu "pipeline $x : sous-dossiers des workspaces" "$(yq -o=json -I=0 '[.spec.tasks[].workspaces[].subPath]' "$f")" '["entrees","entrees","image","image"]'
  done
  attendu "pipeline o : dnf_conf_sha256 = sha256 de dnf.conf du banc" "$(yq '.spec.tasks[1].params[] | select(.name == "dnf_conf_sha256") | .value' "$T/pipeline-o.yaml")" "$(sha256sum < "$BANC_O/dnf.conf" | cut -c1-64)"
  attendu "pipeline b : dnf_conf_sha256 = sha256 de dnf97.conf du banc" "$(yq '.spec.tasks[1].params[] | select(.name == "dnf_conf_sha256") | .value' "$T/pipeline-b.yaml")" "$CONF_B"
  attendu "pipeline o : liste rendue = m1b-listes-outillage.txt" "$(yq '.spec.tasks[0].params[] | select(.name == "liste") | .value' "$T/pipeline-o.yaml" | sed '/^$/d' | cmp -s - "$LISTE_O" && echo égale || echo différente)" égale
  attendu "pipeline b : liste rendue = liste du bootstrap" "$(yq '.spec.tasks[0].params[] | select(.name == "liste") | .value' "$T/pipeline-b.yaml" | sed '/^$/d' | cmp -s - "$LISTE_B" && echo égale || echo différente)" égale
  echo "## analyseur du paramètre fichiers (section de la tâche), sur la valeur rendue"
  yq '.spec.tasks[1].params[] | select(.name == "fichiers") | .value' "$T/pipeline-o.yaml" > "$T/fichiers-rendus.txt"
  x=$T/config-analyse; [ ! -e "$x" ] || echec "$x existe"
  awk 'index($0, "python3 -I - /tmp/fichiers /w/cc <<") > 0 {b = 1; next} b && $0 == "PY" {exit} b' \
    <(yq '.spec.steps[0].script' "$T/construire-racine-rpm.yaml") > "$T/analyseur.py"
  attendu "analyseur extrait (lignes)" "$([ "$(wc -l < "$T/analyseur.py")" -gt 10 ] && echo ok)" ok
  python3 -I "$T/analyseur.py" "$T/fichiers-rendus.txt" "$x" | sed 's/^/     /'
  attendu "fichiers produits = fichiers de la couche de S1, octet pour octet" \
    "$(diff -r "$x" "$T/config-s1" > /dev/null && echo identiques || echo différents)" identiques
  echo "## scripts substitués comme par Tekton"
  substituer "$T/prefetch-racine-rpm.yaml" "$T/pipeline-o.yaml" 0 "$T/script-po.sh" sortie=/workspace/sortie
  substituer "$T/prefetch-racine-rpm.yaml" "$T/pipeline-b.yaml" 0 "$T/script-pb.sh" sortie=/workspace/sortie
  substituer "$T/construire-racine-rpm.yaml" "$T/pipeline-o.yaml" 1 "$T/script-co.sh" entrees=/workspace/entrees sortie=/workspace/sortie DIGEST_CONSTRUIT=/tmp/resultat
  substituer "$T/construire-racine-rpm.yaml" "$T/pipeline-b.yaml" 1 "$T/script-cb.sh" entrees=/workspace/entrees sortie=/workspace/sortie DIGEST_CONSTRUIT=/tmp/resultat
  for x in po pb co cb; do
    attendu "script-$x : bash -n" "$(bash -n "$T/script-$x.sh" && echo ok)" ok
    shellcheck -S warning -s bash "$T/script-$x.sh" > "$T/shellcheck-$x.txt" 2>&1 && echo "OK   script-$x : shellcheck sans avertissement" \
      || { sed 's/^/     /' "$T/shellcheck-$x.txt"; echec "script-$x : shellcheck"; }
    f=$(wc -c < "$T/script-$x.sh"); b=$(base64 -w0 < "$T/script-$x.sh" | wc -c)
    # Args[1] de place-scripts : le base64 du script plus un préfixe (59 869 octets pour 59 668 caractères de base64 en M4b, RP4)
    [ $((b + 1000)) -lt "$BORNE" ] && echo "OK   script-$x : $f octets, base64 $b caractères (+ 1 000 de marge sous la borne de $BORNE) ; sha256 $(sha256sum < "$T/script-$x.sh" | cut -c1-64)" \
      || echec "script-$x : base64 de $b caractères"
  done
  echo "## entrées attendues du prefetch (bancs du 18/11), liste des sha256"
  attendus o > "$T/attendu-o.sha256"; attendus b > "$T/attendu-b.sha256"
  for x in o b; do echo "entrées attendues $x : $(wc -l < "$T/attendu-$x.sha256") fichiers, liste $(sha256sum < "$T/attendu-$x.sha256" | cut -c1-64)"; done
  echo "place libre de /home : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB"
}

rendre_pipeline() { # x nom depots liste cles cle_sup(fichier|-) couche_prefetch couche dnf.conf noms langue sde racine fichiers(fichier|-) config annotations image
  local x=$1 a=$T/rendu-$1
  mkdir -p "$a"
  printf '%s\n' "$3" | indenter > "$a/depots"; indenter < "$4" > "$a/liste"; printf '%s\n' "$5" | indenter > "$a/cles"
  if [ "$6" = - ]; then echo - | indenter > "$a/cle_sup"; else indenter < "$6" > "$a/cle_sup"; fi
  indenter < "$9" > "$a/dnf"
  if [ "${14}" = - ]; then echo - | indenter > "$a/fichiers"; else indenter < "${14}" > "$a/fichiers"; fi
  python3 -I - "$GAB/builder-rpm.yaml" "$T/pipeline-$x.yaml" "$a" "$2" "$REG/tekton/tasks/prefetch-racine-rpm@$FACTICE" \
    "$REG/tekton/tasks/construire-racine-rpm@$FACTICE" "$REG/tekton/tasks/publier-image@$FACTICE" "$7" "$8" \
    "$(python3 -I -c 'import hashlib, sys; t = open(sys.argv[1], "rb").read().rstrip(b"\n") + b"\n"; print(hashlib.sha256(t).hexdigest())' "$9")" \
    "${10}" "${11}" "${12}" "${13}" "${15}" "${16}" "${17}" <<'PY'
import sys
gab, out, a, nom, pre, con, pub, cpre, cou, dsha, noms, langue, sde, racine, config, annot, image = sys.argv[1:]
g = open(gab, encoding='utf-8').read()
i = g.index('\napiVersion:') + 1
tete, t = g[:i], g[i:]   # en-tête de commentaires gardé tel quel : les marqueurs n'y sont pas remplacés
lu = lambda n: open(f'{a}/{n}', encoding='utf-8').read().rstrip('\n')
for k, v in [('@NOM@', nom), ('@PREFETCH@', pre), ('@CONSTRUIRE@', con), ('@PUBLIER@', pub), ('@DEPOTS@', lu('depots')),
             ('@LISTE@', lu('liste')), ('@CLES@', lu('cles')), ('@CLE_SUP@', lu('cle_sup')), ('@COUCHE_PREFETCH@', cpre),
             ('@COUCHE@', cou), ('@DNF_CONF@', lu('dnf')), ('@DNF_CONF_SHA256@', dsha), ('@NOMS@', noms), ('@LANGUE@', langue),
             ('@SDE@', sde), ('@RACINE@', racine), ('@FICHIERS@', lu('fichiers')), ('@CONFIG@', config), ('@ANNOTATIONS@', annot),
             ('@IMAGE@', image)]:
    assert k in t, k
    t = t.replace(k, v)
open(out, 'w', encoding='utf-8').write(tete + t)
PY
  attendu "pipeline $x : yq la relit, nom" "$(yq '.metadata.name' "$T/pipeline-$x.yaml")" "$2"
  grep -n '@[A-Z][A-Z_]*@' <(sed -n '/^apiVersion/,$p' "$T/pipeline-$x.yaml") && echec "pipeline $x : marqueur non remplacé" || echo "OK   pipeline $x : aucun marqueur restant"
}

substituer() { # tâche pipeline index sortie clé=chemin… : script du pas, comme Tekton (paramètres de la pipeline, workspaces, résultat)
  python3 -I - "$@" <<'FIN'
import json, subprocess, sys
tache, pipe, i, out = sys.argv[1:5]
y = lambda f, q: json.loads(subprocess.run(['yq', '-o=json', q, f], capture_output=True, text=True, check=True).stdout)
s = y(tache, '.spec.steps[0].script')
attendus = [p['name'] for p in y(tache, '.spec.params')]
p = {x['name']: x['value'] for x in y(pipe, f'.spec.tasks[{i}].params')}
assert sorted(p) == sorted(attendus), (sorted(p), sorted(attendus))
for k, v in p.items():
    s = s.replace('$(params.' + k + ')', v)
for kv in sys.argv[5:]:
    k, v = kv.split('=', 1)
    s = s.replace('$(workspaces.' + k + '.path)', v).replace('$(results.' + k + '.path)', v)
assert not any(m in s for m in ('$(params.', '$(workspaces.', '$(results.', '$(context.')), 'référence de Tekton restante'
open(out, 'w', encoding='utf-8').write(s)
FIN
}

attendus() { # o|b : liste « sha256  chemin » des entrées que le prefetch doit écrire, tirée des bancs (ordre des chemins)
  local m; [ "$1" = o ] && m=$BANC_O || m=$BANC_B
  python3 -I - "$m" "$1" "$OCI/$COUCHE_BOOT" <<'PY'
import hashlib, os, sys
m, x, couche = sys.argv[1:]
f = {}
for d in ('cles', 'miroir'):
    for r, _, fs in os.walk(f'{m}/{d}'):
        for n in fs:
            p = os.path.join(r, n); f[os.path.relpath(p, m)] = p
if x == 'b':
    f['couche.tar.gz'] = couche
for k in sorted(f, key=lambda s: s.encode()):
    print(f"{hashlib.sha256(open(f[k], 'rb').read()).hexdigest()}  {k}")
PY
}

# Banc : racine de l'amorce extraite à neuf, chroot sous unshare -n ; entrées assemblées par liens durs, montées en lecture seule.
banc_un() { # x : script-<c x> joué dans $D/r-x ; sortie $D/sortie-x, /tmp $D/tmp-x (résultat), /w $D/w-x (gardé pour lecture si écart)
  local x=$1 r=0
  unshare --map-auto --map-root-user bash -c 'mkdir "$1" && tar -xzf "$2" -C "$1" --numeric-owner' _ "$D/r-$x" "$OCI/$COUCHE_AMORCE" \
    || echec "extraction de l'amorce ($x)"
  mkdir -p "$D/sortie-$x" "$D/tmp-$x" "$D/s-$x" "$D/w-$x"
  cp "$T/script-c$x.sh" "$D/s-$x/script.sh"
  echo "## banc $x : début $(date -u +%FT%TZ)"
  unshare --map-auto --map-root-user -n -m -p --fork bash -c 'set -e; r=$1; e=$2; s=$3; t=$4; c=$5; w=$6
    mkdir -p "$r/workspace/entrees" "$r/workspace/sortie" "$r/w" "$r/s"
    mount --rbind /dev "$r/dev"; mount -t proc proc "$r/proc"
    mount --bind "$e" "$r/workspace/entrees"; mount -o remount,bind,ro "$r/workspace/entrees"
    mount --bind "$s" "$r/workspace/sortie"; mount --bind "$w" "$r/w"; mount --bind "$t" "$r/tmp"
    mount --bind "$c" "$r/s"; mount -o remount,bind,ro "$r/s"
    exec chroot "$r" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin /bin/bash /s/script.sh' _ \
    "$D/r-$x" "$D/entrees-$x" "$D/sortie-$x" "$D/tmp-$x" "$D/s-$x" "$D/w-$x" > "$D/banc-$x.log" 2>&1 || r=$?
  filtre < "$D/banc-$x.log" | sed 's/^/     /'
  echo "## banc $x : code $r, fin $(date -u +%FT%TZ)"
  [ "$r" = 0 ] || echec "banc $x"
}

layout_relu() { # image.tar digest dossier : layout relu par python (blobs, tailles, diff_ids) puis par oras
  mkdir -p "$3" && tar -xf "$1" -C "$3"
  python3 -I - "$3" "$2" <<'PY'
import hashlib, json, os, sys
d, dig = sys.argv[1:]
b = lambda h: open(f'{d}/blobs/sha256/{h}', 'rb').read()
idx = json.load(open(f'{d}/index.json'))
assert len(idx['manifests']) == 1 and idx['manifests'][0]['digest'] == dig, idx
for h in os.listdir(f'{d}/blobs/sha256'):
    assert hashlib.sha256(b(h)).hexdigest() == h, h
m = json.loads(b(dig[7:])); c = json.loads(b(m['config']['digest'][7:]))
assert len(b(m['config']['digest'][7:])) == m['config']['size']
for l in m['layers']:
    assert len(b(l['digest'][7:])) == l['size'] and l['mediaType'] == 'application/vnd.oci.image.layer.v1.tar', l
assert c['rootfs']['diff_ids'] == [l['digest'] for l in m['layers']]
print(f"OK   layout relu (python) : {len(os.listdir(f'{d}/blobs/sha256'))} blobs, sha256 conformes ; {len(m['layers'])} couche(s) ; "
      f"config {json.dumps(c['config'], separators=(',', ':'))} ; annotations {json.dumps(m.get('annotations', {}), separators=(',', ':'))}")
PY
  attendu "manifeste lu par oras dans le layout (sha256)" "$(oras manifest fetch --oci-layout "$3@$2" 2> /dev/null | sha256sum | cut -c1-64)" "${2#sha256:}"
}

etape_banc() {
  local x
  [ -s "$T/script-co.sh" ] && [ -s "$T/script-cb.sh" ] || echec "étape prealables à lancer d'abord"
  D=$HOME/.cache/supply-chain-poc/05/m1b-builders-banc-$(date -u +%Y%m%dT%H%M%SZ)   # dossier neuf, jamais effacé ni réutilisé
  [ ! -e "$D" ] || echec "$D existe"
  echo "dossier du banc : $D ; place libre de /home : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB"
  mkdir -p "$D/entrees-o" "$D/entrees-b"
  cp -al "$BANC_O/miroir" "$BANC_O/cles" "$D/entrees-o/"
  cp -al "$BANC_B/miroir" "$BANC_B/cles" "$D/entrees-b/"
  ln "$OCI/$COUCHE_BOOT" "$D/entrees-b/couche.tar.gz"
  for x in o b; do
    attendu "entrées du banc $x = entrées attendues du prefetch" \
      "$( (cd "$D/entrees-$x" && find . -type f | sed 's|^\./||' | sort | xargs sha256sum) | cmp -s - "$T/attendu-$x.sha256" && echo égales || echo différentes)" égales
  done
  for x in o b; do
    banc_un "$x"
    echo "     résultat DIGEST_CONSTRUIT : $(cat "$D/tmp-$x/resultat")"
    cp "$D/tmp-$x/resultat" "$T/banc-digest-$x"
    sha256sum < "$D/sortie-$x/image.tar" | cut -c1-64 > "$T/banc-image-$x"
    layout_relu "$D/sortie-$x/image.tar" "$(cat "$D/tmp-$x/resultat")" "$D/layout-$x"
  done
  echo "## couche de configuration de l'outillage contre celle de S1"
  x=$(jq -r '.layers[1].digest' "$D/layout-o/blobs/sha256/$(cut -c8- "$T/banc-digest-o")")
  echo "couche de configuration du banc : $x ; S1 : sha256:$DIFF_CONFIG_S1"
  mkdir -p "$D/config-banc" && tar -xf "$D/layout-o/blobs/sha256/${x#sha256:}" -C "$D/config-banc"
  attendu "contenu de la couche de configuration = celui de S1, fichier par fichier" \
    "$(diff -r "$D/config-banc" "$T/config-s1" > /dev/null && echo identique || echo différent)" identique
  gzip -dc < "$BANC_IMAGE/$COUCHE_CONFIG_S1" > "$D/config-s1.tar"
  python3 -I "$h05/resultats/m1b-repro2-comparer.py" "$D/config-s1.tar" "$D/layout-o/blobs/sha256/${x#sha256:}" 2>&1 | sed 's/^/   comparer : /' || true
  echo "place libre de /home après : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB ; dossier laissé : $D"
}

# Pods d'essai
pvc_json() {
  jq -n --arg n "$N-w" --arg j "$N" '{apiVersion: "v1", kind: "PersistentVolumeClaim",
    metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": $j}},
    spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "2Gi"}}}}' > "$T/$N-w.json"
}
pod_prefetch_json() { # nom sous-dossier
  jq -n --arg n "$1" --arg i "$AMORCE" --arg lb "$LABEL_P" --arg j "$N" --arg c "$N-w" --arg sp "$2" \
    --argjson res "$(yq -o=json -I=0 '.spec.steps[0].resources' "$T/prefetch-racine-rpm.yaml")" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": $j, "tekton.dev/task": $lb}},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, enableServiceLinks: false,
      nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", persistentVolumeClaim: {claimName: $c}}, {name: "tmp", emptyDir: {}}, {name: "ca-poc", configMap: {name: "ca-poc"}}],
      containers: [{name: "essai", image: $i, command: ["sleep", "7200"],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}, env: [{name: "HOME", value: "/tmp"}],
        resources: $res,
        volumeMounts: [{name: "w", mountPath: "/workspace/sortie", subPath: $sp}, {name: "tmp", mountPath: "/tmp"},
          {name: "ca-poc", mountPath: "/etc/ca-poc", readOnly: true}]}]}}' > "$T/$1.json"
}
pod_construire_json() { # nom sous-dossier-entrees sous-dossier-sortie
  jq -n --arg n "$1" --arg i "$AMORCE" --arg lb "$LABEL_C" --arg j "$N" --arg c "$N-w" --arg se "$2" --arg ss "$3" \
    --argjson sc "$(yq -o=json -I=0 '.spec.steps[0].securityContext' "$T/construire-racine-rpm.yaml")" \
    --argjson res "$(yq -o=json -I=0 '.spec.steps[0].resources' "$T/construire-racine-rpm.yaml")" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": $j, "tekton.dev/task": $lb}},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, enableServiceLinks: false,
      runtimeClassName: "kata", nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: false, runAsUser: 0, runAsGroup: 0, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "pvc", persistentVolumeClaim: {claimName: $c}}, {name: "w", emptyDir: {medium: "Memory", sizeLimit: "4Gi"}},
        {name: "tmp", emptyDir: {}}],
      containers: [{name: "essai", image: $i, command: ["sleep", "7200"], securityContext: $sc, resources: $res,
        volumeMounts: [{name: "pvc", mountPath: "/workspace/entrees", subPath: $se, readOnly: true},
          {name: "pvc", mountPath: "/workspace/sortie", subPath: $ss}, {name: "w", mountPath: "/w"}, {name: "tmp", mountPath: "/tmp"}]}]}}' > "$T/$1.json"
}
a_blanc() { # fichier : création admise à blanc côté serveur ; jamais le texte du refus, seulement des motifs comptés
  local r=0
  kubectl create --dry-run=server -o name -f "$1" < /dev/null > /dev/null 2> "$T/a-blanc.err" || r=$?
  if [ $r = 0 ]; then echo "OK   admis à blanc : ${1##*/}"
  else echo "KO   refusé à blanc : ${1##*/} (code $r ; motifs PodSecurity $(grep -ci 'podsecurity\|pod security' "$T/a-blanc.err" || true), kyverno $(grep -ci kyverno "$T/a-blanc.err" || true))" >&2; exit 1; fi
}
labels_neufs() { # fichier label-neuf : même objet sous le label de la tâche neuve, admis à blanc ? (relevé, n'arrête pas l'étape)
  local r=0 f=${1%.json}-neuf.json
  jq --arg l "$2" '.metadata.labels["tekton.dev/task"] = $l' "$1" > "$f"
  kubectl create --dry-run=server -o name -f "$f" < /dev/null > /dev/null 2> "$T/a-blanc-neuf.err" || r=$?
  if [ $r = 0 ]; then echo "relevé : ${1##*/} sous le label $2 : admis à blanc"
  else echo "relevé : ${1##*/} sous le label $2 : refusé à blanc (code $r ; motifs PodSecurity $(grep -ci 'podsecurity\|pod security' "$T/a-blanc-neuf.err" || true), kyverno $(grep -ci kyverno "$T/a-blanc-neuf.err" || true))"; fi
}
absent() { [ -z "$(kubectl get "$1" -n builds --field-selector "metadata.name=$2" -o name < /dev/null 2> /dev/null)" ] || echec "$1 $2 déjà présent (relancer sous un autre PREFIXE)"; }
pret() { # pod
  if ! kubectl wait -n builds "pod/$1" --for=condition=Ready --timeout=300s < /dev/null > /dev/null 2>&1; then
    kubectl get pod -n builds "$1" -o json < /dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state
      | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"' >&2   # raisons, jamais les messages
    echec "$1 non prêt"
  fi
  echo "pod $1 prêt : nœud $(kubectl get pod -n builds "$1" -o jsonpath='{.spec.nodeName}' < /dev/null), runtimeClassName « $(kubectl get pod -n builds "$1" -o jsonpath='{.spec.runtimeClassName}' < /dev/null) », label $(kubectl get pod -n builds "$1" -o jsonpath='{.metadata.labels.tekton\.dev/task}' < /dev/null)"
}
jouer() { # pod script libellé : script copié dans le pod (/tmp/script.sh), puis exécuté par bash ; journal filtré dans $T/<libellé>.log
  local rc=0
  kubectl exec -i -n builds "$1" -- sh -c 'cat > /tmp/script.sh' < "$2" || echec "copie du script dans $1"
  attendu "script copié dans $1 (sha256)" "$(kubectl exec -n builds "$1" -- sha256sum /tmp/script.sh < /dev/null | cut -c1-64)" "$(sha256sum < "$2" | cut -c1-64)"
  echo "## $3 : début $(date -u +%FT%TZ)"
  kubectl exec -n builds "$1" -- bash /tmp/script.sh < /dev/null > "$T/$3.brut" 2>&1 || rc=$?
  filtre < "$T/$3.brut" > "$T/$3.log"; rm -f -- "$T/$3.brut"
  sed 's/^/     /' "$T/$3.log"
  echo "## $3 : code $rc, fin $(date -u +%FT%TZ)"
  return $rc
}
retirer() { # pod : retrait attendu
  local rc=0
  kubectl delete pod -n builds "$1" --wait=true --timeout=180s < /dev/null > /dev/null || rc=$?
  attendu "retrait du pod $1 (code de kubectl)" "$rc" 0
}
politiques_relues() {
  attendu "prefetch-rpm-sortie : sélecteur" "$(kubectl get ciliumnetworkpolicy -n builds prefetch-rpm-sortie -o json < /dev/null | jq -c '.spec.endpointSelector')" \
    "{\"matchLabels\":{\"tekton.dev/task\":\"$LABEL_P\"}}"
  attendu "construction-rpm-sans-sortie : sélecteur, types, règles" \
    "$(kubectl get networkpolicy -n builds construction-rpm-sans-sortie -o json < /dev/null | jq -c '[.spec.podSelector, (.spec.policyTypes | sort), (.spec.ingress // []), (.spec.egress // [])]')" \
    "[{\"matchLabels\":{\"tekton.dev/task\":\"$LABEL_C\"}},[\"Egress\",\"Ingress\"],[],[]]"
}

etape_essai_prefetch() {
  local x p
  [ -s "$T/script-po.sh" ] && [ -s "$T/attendu-o.sha256" ] || echec "étape prealables à lancer d'abord"
  politiques_relues
  absent pvc "$N-w"; pvc_json; a_blanc "$T/$N-w.json"
  for x in o b; do absent pod "$N-p$x"; pod_prefetch_json "$N-p$x" "entrees-$x"; a_blanc "$T/$N-p$x.json"; done
  labels_neufs "$T/$N-po.json" prefetch-racine-rpm
  kubectl create -f "$T/$N-w.json" < /dev/null > /dev/null
  echo "PVC $N-w créé (2Gi, local-path, liaison au premier pod)"
  for x in o b; do
    p=$N-p$x
    kubectl create -f "$T/$p.json" < /dev/null > /dev/null
    pret "$p"
    jouer "$p" "$T/script-p$x.sh" "essai-p$x" || { echo "pod $p laissé pour lecture" >&2; echec "prefetch $x"; }
    kubectl exec -n builds "$p" -- sh -c 'export LC_ALL=C; cd /workspace/sortie && find . -type f | sed "s|^\./||" | sort | xargs sha256sum' < /dev/null > "$T/essai-p$x.sha256"
    echo "arbre écrit par le pod $p : $(wc -l < "$T/essai-p$x.sha256") fichiers, liste $(sha256sum < "$T/essai-p$x.sha256" | cut -c1-64)"
    if cmp -s "$T/essai-p$x.sha256" "$T/attendu-$x.sha256"; then echo "OK   arbre du pod $p = entrées du banc, fichier par fichier"
    else echo "ÉCART arbre du pod $p différent des entrées du banc :"; diff "$T/attendu-$x.sha256" "$T/essai-p$x.sha256" | head -n 20 | sed 's/^/     /'; fi
    retirer "$p"
  done
  echo "PVC $N-w gardé pour essai_construire : $(kubectl get pvc -n builds "$N-w" -o jsonpath='{.status.phase} {.spec.volumeName}' < /dev/null)"
}

etape_essai_construire() {
  local x p
  [ -s "$T/script-co.sh" ] && [ -s "$T/banc-digest-o" ] && [ -s "$T/banc-digest-b" ] || echec "étapes prealables et banc à lancer d'abord"
  [ -n "$(kubectl get pvc -n builds --field-selector "metadata.name=$N-w" -o name < /dev/null 2> /dev/null)" ] || echec "PVC $N-w absent (essai_prefetch d'abord)"
  politiques_relues
  for x in o b; do absent pod "$N-c$x"; pod_construire_json "$N-c$x" "entrees-$x" "image-$x"; a_blanc "$T/$N-c$x.json"; done
  labels_neufs "$T/$N-co.json" construire-racine-rpm
  for x in o b; do
    p=$N-c$x
    kubectl create -f "$T/$p.json" < /dev/null > /dev/null
    pret "$p"
    jouer "$p" "$T/script-c$x.sh" "essai-c$x" || { echo "pod $p laissé pour lecture" >&2; echec "construction $x"; }
    attendu "DIGEST_CONSTRUIT du pod $p = celui du banc" "$(kubectl exec -n builds "$p" -- cat /tmp/resultat < /dev/null)" "$(cat "$T/banc-digest-$x")"
    attendu "image.tar du pod $p = celle du banc (sha256)" "$(kubectl exec -n builds "$p" -- sha256sum /workspace/sortie/image.tar < /dev/null | cut -c1-64)" "$(cat "$T/banc-image-$x")"
    retirer "$p"
  done
  local rc=0
  kubectl delete pvc -n builds "$N-w" --wait=true --timeout=180s < /dev/null > /dev/null || rc=$?
  attendu "retrait du PVC $N-w (code de kubectl)" "$rc" 0
  kubectl get pods,pvc -n builds -o name < /dev/null > "$T/objets-apres.txt" 2>&1
  attendu "pods et PVC restants au préfixe $N-" "$(grep -c "/$N-" "$T/objets-apres.txt" || true)" 0
}

[ $# -ge 1 ] || { echo "usage : $0 prealables|banc|essai_prefetch|essai_construire…" >&2; exit 2; }
for e in "$@"; do
  case $e in prealables|banc|essai_prefetch|essai_construire) ;; *) echo "étape inconnue : $e" >&2; exit 2 ;; esac
  echo "# m1b-builders.sh $e (PREFIXE $N), début $(date -u +%FT%TZ)"
  "etape_$e"
  echo "# fin $e $(date -u +%FT%TZ)"
done
