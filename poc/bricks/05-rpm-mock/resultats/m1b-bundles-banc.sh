#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b : banc hors cluster et hors Zot de m1b-bundles.sh (préparé à sec le 20/11/2026).
#   A  copies : m1b-bundles-copies.py (fonctions recopiées égales aux originaux, étapes d'essai refaites par remplacements comptés).
#   B  constantes : chaque valeur confrontée à sa source (m4b.sh, m4c.sh, m1b-verrou.sh, journaux archivés, git aux commits de
#      signature de M4b et M4c).
#   C  étape local, la vraie fonction, jouée dans la forme de lancer ; CONFIANCE_DIR du banc, entrees.tar réel (lecture seule).
#   D  une_feuille sur des tâches neuves altérées : seule l'image d'outillage passe.
#   E  gardes du lanceur (PREFIXE, TAG, journal existant) et étape taches, la vraie fonction, avec le vrai tkn, une clé P-256
#      jetable du banc (jamais taches.key), des copies des gabarits et des tâches signées ; faux : kubectl (dry-run serveur seul),
#      zot_lire (état du banc), bundle (poussées comptées, digest = sha256 du fichier), auth_zot, sur (octets libres).
#      Cas : nominal ; sans SIGNER ; clé absente ; signature versionnée déjà présente ; tag neuf déjà présent ; tag m4c déplacé ;
#      place basse ; tâche refusée à l'admission ; gabarit altéré (mémoire du pas). Dans chaque cas : poussées, signatures
#      versionnées, $T/auth et appels de kubectl relus.
#   F  (ajoutée le 20/11/2026, après la revue du conseiller) chemins de l'hôte lus par les deux essais, relevés statiquement : tous
#      écrits dans l'étape même ; aucun chemin de prealables de M4c sous $T ; entrees.tar lu par $ENTREES seulement.
# Non couvert : les pods d'essai (cluster), Zot, le vrai dry-run serveur, Tekton (bundles, Trusted Resources), la clé réelle.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-bundles-banc.sh <dossier-neuf>
set -uo pipefail
export LC_ALL=C
B=$1
RACINE=$PWD; D05=$RACINE/poc/bricks/05-rpm-mock; SCRIPT=$D05/m1b-bundles.sh
ENTREES_REEL=$HOME/.cache/supply-chain-poc/08/travail/m4c-05/entrees.tar   # lecture seule
REG=sc-stockage.poc.test:5000
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
val() { sed -n "s/^$2=\([^ ]*\).*/\1/p" "$D05/$1"; }   # fichier variable : valeur affectée en début de ligne (premier mot)
echo "# m1b-bundles-banc.sh, $(date -u +%FT%TZ) ; m1b-bundles.sh $(sha256sum < "$SCRIPT" | cut -c1-64)"
echo "# tkn $(tkn version --component client) ; yq $(yq --version | awk '{print $NF}')"

echo "## A copies"
python3 -I "$D05/resultats/m1b-bundles-copies.py" "$D05" > "$B/copies.txt"; rc=$?
cat "$B/copies.txt"
egal "A copies : code" "$rc" 0
egal "A copies : contrôles OK" "$(grep -c '^OK' "$B/copies.txt")" 24

echo "## B constantes"
egal "B image neuve = DIGEST_OUTILLAGE de m1b-verrou.sh" "$(val m1b-bundles.sh IMAGE_NEUVE)" "\$REG/builds/builders/mock-rocky9@$(val m1b-verrou.sh DIGEST_OUTILLAGE)"
egal "B image d'essai = IMAGE de m4b.sh" "$(val m1b-bundles.sh IMAGE_ESSAI)" "$(val m4b.sh IMAGE)"
egal "B image d'essai = IMAGE_OUTILLAGE de m4c.sh" "$(val m1b-bundles.sh IMAGE_ESSAI)" "$(val m4c.sh IMAGE_OUTILLAGE)"
egal "B prefetch-rpm de M4b = PREFETCH_REF de m4b.sh" "$(val m1b-bundles.sh PREFETCH_M4B)" "$(val m4b.sh PREFETCH_REF)"
egal "B construire-rpm de M4c = CONSTRUIRE_REF de m4c.sh" "$(val m1b-bundles.sh CONSTRUIRE_M4C)" "$(val m4c.sh CONSTRUIRE_REF)"
for v in LISTE_SHA VERROU_SHA FP_ROCKY REPOMD_V2 DEPOT_FERMETURE LABEL VOLUME; do
  egal "B $v = celle de m4b.sh" "$(val m1b-bundles.sh $v)" "$(val m4b.sh $v)"
done
egal "B LIMITES = celle de m4b.sh (ligne)" "$(grep -c -x -F "LIMITES='{\"cpu\": \"2\", \"memory\": \"2Gi\"}'" "$SCRIPT") $(grep -c -x -F "LIMITES='{\"cpu\": \"2\", \"memory\": \"2Gi\"}'" "$D05/m4b.sh")" "1 1"
egal "B SCRIPT_PREFETCH_SHA = SCRIPT_ESSAI_SHA de m4b.sh" "$(val m1b-bundles.sh SCRIPT_PREFETCH_SHA)" "$(val m4b.sh SCRIPT_ESSAI_SHA)"
for v in VERROU_SHA EPOQUE ARCHIVE_SHA RPM_M3_SHA SRPM_M3_SHA MORCEAU_MIO LABEL_PREPARER LABEL_CONSTRUIRE LIBRE_MIN; do
  egal "B $v = celle de m4c.sh" "$(val m1b-bundles.sh $v)" "$(val m4c.sh $v)"
done
egal "B DIGEST_ESSAI_M4C = DIGEST_ESSAI de m4c.sh" "$(val m1b-bundles.sh DIGEST_ESSAI_M4C)" "$(val m4c.sh DIGEST_ESSAI)"
egal "B SCRIPT_CONSTRUIRE_SHA = construire-rpm-construire de m4c.sh" "$(val m1b-bundles.sh SCRIPT_CONSTRUIRE_SHA)" \
  "$(sed -n 's/^construire-rpm-construire:\([0-9a-f]\{64\}\)".*/\1/p' "$D05/m4c.sh")"
egal "B gabarit construire-rpm = GABARITS_SHA de m4c.sh" "$(grep -c -x 'construction/construire-rpm.yaml:e88f5521ede87f5b03330683939fd3494f5ff58544ded9a9326014e30b8d0f88' "$SCRIPT") $(grep -c '^construire-rpm.yaml:e88f5521ede87f5b03330683939fd3494f5ff58544ded9a9326014e30b8d0f88$' "$D05/m4c.sh")" "1 1"
gs() { git -C "$RACINE" show "$1:poc/bricks/05-rpm-mock/$2" | sha256sum | cut -c1-64; }
for e in fermeture/prefetch-rpm.yaml:19837c20 fermeture/prefetch-rpm-sample-app.yaml:19837c20 fermeture/prefetch-rpm.signee.yaml:19837c20 \
         construction/construire-rpm.yaml:75ed22a8 construction/construire-rpm.signee.yaml:75ed22a8; do
  f=${e%%:*}
  egal "B $f au commit de signature ${e#*:} = GABARITS_SHA" "$(gs "${e#*:}" "$f")" "$(grep -o "$f:[0-9a-f]\{64\}" "$SCRIPT" | cut -d: -f2)"
done
egal "B entrees.tar = m4c-prealables.log" "$(val m1b-bundles.sh ENTREES_TAILLE) $(val m1b-bundles.sh ENTREES_SHA)" \
  "$(sed -n 's/^entrees.tar : \([0-9]*\) octets, sha256 \([0-9a-f]\{64\}\)$/\1 \2/p' "$D05/resultats/m4c-prealables.log")"
egal "B arbre de final cité par m4b-final.log" "$(grep -c "$(val m1b-bundles.sh ARBRE_REF_SHA)" "$D05/resultats/m4b-final.log")" 2
egal "B liste de l'outillage au commit c740d944 = LISTE_OUTILLAGE_SHA" "$(gs c740d944 resultats/m1b-listes-outillage.txt)" "$(val m1b-bundles.sh LISTE_OUTILLAGE_SHA)"
egal "B liste rendue de builder-mock-rocky9 = m1b-listes-outillage.txt (m1b-builders-m1bt-20-prealables.log)" \
  "$(grep -c '^OK   pipeline o : liste rendue = m1b-listes-outillage.txt : égale$' "$D05/resultats/m1b-builders-m1bt-20-prealables.log")" 1

echo "## F chemins de l'hôte lus par les deux essais (statique) : tous écrits dans l'étape même"
chemins() { awk -v f="$1" '$0 ~ "^" f "\\(\\) \\{" {b = 1} b; b && /^}$/ {exit}' "$SCRIPT" | grep -o '"\$[Tx]/[^"]*"' | sort -u | paste -sd' '; }
egal "F essai_prefetch" "$(chemins etape_essai_prefetch)" \
  '"$T/$POD.json" "$T/admis-$POD.out" "$T/prefetch-essai-arbre.err" "$T/prefetch-essai-arbre.txt" "$T/prefetch-essai-objets.txt" "$T/prefetch-essai-refus.log" "$T/prefetch-essai.log" "$T/prefetch-rpm-sample-app.yaml" "$T/prefetch-rpm.yaml" "$T/script-essai.sh" "$T/script-refus.sh"'
egal "F essai_construire" "$(chemins etape_essai_construire)" \
  "\"\$T/construire-rpm.yaml\" \"\$x/construire.log\" \"\$x/construire.sh\" \"\$x/image.tar\" \"\$x/lu\" \"\$x/lu/blobs/sha256/\$(jq -r '.layers[0].digest' \" \"\$x/lu/index.json\" \"\$x/pod.json\""
egal "F aucun chemin de prealables de M4c dans le script (entrees.tar, digest-attendu sous \$T)" "$(grep -c -e '"$T/entrees.tar"' -e '$T/digest-attendu' "$SCRIPT")" 0
egal "F entrees.tar lu par \$ENTREES (lignes : local, garde de l'essai, copie dans le pod)" "$(grep -c '"$ENTREES"' "$SCRIPT")" 3

echo "## C étape local (vraie fonction, forme de lancer)"
mkdir -p "$B/O/secrets" "$B/C"
(cd "$RACINE" && env CONFIANCE_DIR="$B/O" DISTRO=rke2 ENTREES_REEL="$ENTREES_REEL" BANC_T="$B/C/t" bash -c '
  set -euo pipefail
  . "$1"; ENTREES=$ENTREES_REEL; T=$BANC_T; mkdir -p "$T"
  { echo "# etape_local (banc)"; etape_local; } 2>&1 | sed -u "s#$HOME#~#g" > "$T/../sortie.txt"' _ "$SCRIPT"); rc=$?
grep -v '^     ' "$B/C/sortie.txt" | cut -c1-160
egal "C local : code" "$rc" 0
egal "C local : OK" "$(grep -c '^OK' "$B/C/sortie.txt")" 23
egal "C local : KO" "$(grep -c '^KO' "$B/C/sortie.txt")" 0
egal "C travail/ du banc : seul le dossier de travail du script, vide (T redirigé)" "$(find "$B/O/travail" -mindepth 1 | sed "s#^$B/O/travail/##" | paste -sd' ')" m1b-bundles-05

echo "## D une_feuille sur des tâches altérées"
J=$B/C/t/local
alt() { # libellé fichier filtre-jq attendu(OK|KO)
  jq -c "$3" "$J/neuf/$2.json" > "$B/D.json"
  (env CONFIANCE_DIR="$B/O" bash -c '. "$1"; une_feuille test "$2" "$3"' _ "$SCRIPT" "$J/$2-$4.json" "$B/D.json" > "$B/D.out" 2>&1) && r=OK || r=KO
  egal "D $1" "$r" "$5"
}
alt "prefetch-rpm neuve telle quelle" prefetch-rpm . m4b OK
alt "construire-rpm neuve telle quelle" construire-rpm . m4c OK
alt "image d'un autre digest" prefetch-rpm '.spec.steps[0].image |= sub("70f8c412"; "70f8c413")' m4b KO
alt "annotation ajoutée" construire-rpm '.metadata.annotations = {"x": "y"}' m4c KO
alt "script changé d'un caractère" prefetch-rpm '.spec.steps[0].script |= . + " "' m4b KO
alt "paramètre retiré" prefetch-rpm 'del(.spec.params[0])' m4b KO
alt "mémoire du pas changée" construire-rpm '.spec.steps[0].resources.limits.memory = "8Gi"' m4c KO
alt "contexte de sécurité retiré" construire-rpm 'del(.spec.steps[0].securityContext)' m4c KO
alt "image d'essai remise (aucune feuille différente)" construire-rpm ".spec.steps[0].image = \"$REG/essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771\"" m4c KO

echo "## E gardes du lanceur"
lanceur() { (cd "$RACINE" && env CONFIANCE_DIR="$B/O-lanceur" DISTRO=rke2 "$@" bash "$SCRIPT" local > "$B/E.out" 2>&1); echo $?; }
egal "E TAG=m4b refusé" "$(lanceur TAG=m4b)" 2
egal "E TAG=m4c refusé" "$(lanceur TAG=m4c)" 2
egal "E TAG=essai refusé" "$(lanceur TAG=essai)" 2
egal "E TAG invalide refusé" "$(lanceur TAG=M1B)" 2
egal "E PREFIXE invalide refusé" "$(lanceur PREFIXE=a/b)" 2
egal "E aucun journal neuf (PREFIXE et TAG refusés)" "$(ls "$D05/resultats" | grep -c -e '^a/b-' -e '^m1b-bundles-local.log$')" 0
egal "E boucle du lanceur présente telle quelle" "$(grep -c -F 'for e in "$@"; do [ ! -e "$R/$N-bundles-$e.log" ] || { echo "journal déjà présent, jamais réécrit : resultats/$N-bundles-$e.log" >&2; exit 2; }; done' "$SCRIPT")" 1

echo "## E étape taches (vraie fonction, faux kubectl, zot_lire, bundle, auth_zot, sur ; vrai tkn, clé jetable)"
mkdir -p "$B/kbin" "$B/cle"
(umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$B/cle/taches.key" 2> /dev/null)
openssl pkey -in "$B/cle/taches.key" -pubout -out "$B/cle/taches.pub" 2> /dev/null
egal "E clé jetable du banc (P-256)" "$(openssl pkey -in "$B/cle/taches.pub" -pubin -noout -text 2> /dev/null | grep -c 'NIST CURVE: P-256')" 1
cat > "$B/kbin/kubectl" <<'K'
#!/usr/bin/env bash
# faux kubectl : dry-run serveur seulement ; computeResources refusé comme le 18/11 ; BANC_REFUSEE : nom d'objet refusé
echo "kubectl $*" >> "$BANC_APPELS"
case "$*" in
  "create --dry-run=server -n builds -f "*)
    f=${*: -1}
    if grep -q computeResources "$f"; then echo 'Error from server (BadRequest): error when creating: Task in version "v1beta1" cannot be handled as a Task: strict decoding error: unknown field "spec.steps[0].computeResources"' >&2; exit 1; fi
    if [ -n "${BANC_REFUSEE:-}" ] && [ "$(yq .metadata.name "$f")" = "$BANC_REFUSEE" ]; then echo "refus du banc" >&2; exit 1; fi
    exit 0 ;;
esac
echo "faux kubectl : appel inattendu : $*" >&2; exit 3
K
chmod +x "$B/kbin/kubectl"
cas() { # dossier [VAR=valeur…] : etape_taches dans la forme de lancer ; code rendu
  local w=$1; shift
  mkdir -p "$w/fermeture" "$w/construction" "$w/O/secrets"
  cp "$D05/fermeture/prefetch-rpm.yaml" "$D05/fermeture/prefetch-rpm-sample-app.yaml" "$D05/fermeture/prefetch-rpm.signee.yaml" "$w/fermeture/"
  cp "$D05/construction/construire-rpm.yaml" "$D05/construction/construire-rpm.signee.yaml" "$w/construction/"
  case " $* " in *" BANC_SANS_CLE=1 "*) ;; *) (umask 077 && cp "$B/cle/taches.key" "$w/O/secrets/taches.key") ;; esac
  printf '%s\n' "tekton/tasks/prefetch-rpm:m4b sha256:9afe09db6d97d065c29245417a44e54a147b5f32a7e37b7ff5f9616c8110893a" \
    "tekton/tasks/construire-rpm:m4c sha256:d7f01398f188931c124273c8b5fb60e2a66c22e9d0a2dfcd229ecadee1e62164" > "$w/zot.txt"
  : > "$w/appels"; : > "$w/poussees"
  (cd "$RACINE" && env CONFIANCE_DIR="$w/O" DISTRO=rke2 PATH="$B/kbin:$PATH" BANC_APPELS="$w/appels" BANC_W="$w" "$@" bash -c '
    set -euo pipefail
    . "$1"
    TACHES=$BANC_W/fermeture; C=$BANC_W/construction
    [ -z "${BANC_ZOT:-}" ] || echo "$BANC_ZOT" >> "$BANC_W/zot.txt"
    [ -z "${BANC_GABARIT:-}" ] || { sed -i "s/memory: 6Gi$/memory: 7Gi/" "$C/construire-rpm.yaml"; [ "$(grep -c "memory: 7Gi$" "$C/construire-rpm.yaml")" = 2 ] || exit 9; }
    [ -z "${BANC_VERSION:-}" ] || : > "$TACHES/prefetch-rpm.m1b.signee.yaml"
    zot_lire() { local d; d=$(awk -v r="$2" "\$1 == r {x = \$2} END {print x}" "$BANC_W/zot.txt"); echo "${d:-absent}"; }
    bundle() { local d; d=sha256:$(sha256sum < "$1" | cut -c1-64); echo "$2:$3 $d" >> "$BANC_W/poussees"; echo "$2:$3 $d" >> "$BANC_W/zot.txt"; echo "$d"; }
    auth_zot() { printf "{\"faux\":1}\n" > "$1"; }
    sur() { echo " ${BANC_LIBRE-3978911744}"; }
    { echo "# etape_taches (banc), $(date -u +%FT%TZ)"; etape_taches; } 2>&1 | sed -u "s#$HOME#~#g" > "$BANC_W/sortie.txt"' _ "$SCRIPT"); local rc=$?
  egal "${w##*/} : \$T/auth absent à la fin" "$([ -e "$w/O/travail/m1b-bundles-05/auth" ] && echo présent || echo absent)" absent
  egal "${w##*/} : appels de kubectl hors dry-run serveur" "$(grep -v -c '^kubectl create --dry-run=server -n builds -f ' "$w/appels")" 0
  echo "$rc"
}
versions() { find "$1/fermeture" "$1/construction" -name '*.m1b.signee.yaml' -size +0 | wc -l; }

w=$B/E1; rc=$(cas "$w" SIGNER=1 | tail -1); grep -v '^     ' "$w/sortie.txt" | cut -c1-160 | sed 's/^/   | /'
egal "E1 nominal : code" "$rc" 0
egal "E1 nominal : KO" "$(grep -c '^KO' "$w/sortie.txt")" 0
egal "E1 nominal : poussées (dépôt:tag)" "$(cut -d' ' -f1 "$w/poussees" | paste -sd' ')" "tekton/tasks/prefetch-rpm:m1b tekton/tasks/construire-rpm:m1b"
egal "E1 nominal : signatures versionnées sous des noms neufs" "$(versions "$w")" 2
egal "E1 nominal : anciennes tâches signées inchangées" "$(cmp -s "$w/fermeture/prefetch-rpm.signee.yaml" "$D05/fermeture/prefetch-rpm.signee.yaml" && cmp -s "$w/construction/construire-rpm.signee.yaml" "$D05/construction/construire-rpm.signee.yaml" && echo inchangées)" inchangées
for t in fermeture/prefetch-rpm construction/construire-rpm; do
  egal "E1 nominal : ${t#*/} versionnée, vérifiée par tkn (clé publique du banc)" "$(tkn task verify "$w/$t.m1b.signee.yaml" -K "$B/cle/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
  egal "E1 nominal : ${t#*/} poussée = versionnée" "$(grep -c "sha256:$(sha256sum < "$w/$t.m1b.signee.yaml" | cut -c1-64)" "$w/poussees")" 1
done
egal "E1 nominal : refus de tkn avec une autre clé" "$(openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2> /dev/null | openssl pkey -pubout -out "$B/cle/autre.pub" 2> /dev/null; tkn task verify "$w/construction/construire-rpm.m1b.signee.yaml" -K "$B/cle/autre.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" refusée
egal "E1 nominal : feuilles relues (prefetch, construire ; signées)" "$(grep -c '^OK   .* : feuilles différentes : .spec.steps\[0\].image : ' "$w/sortie.txt")" 2
egal "E1 nominal : relectures après (P1 et P2)" "$(grep -c '^OK   P[12] ' "$w/sortie.txt")" 4
egal "E1 nominal : références à ajouter à la liste revue" "$(grep -c '^SIGNER : à ajouter à politique/porte/taches.yml' "$w/sortie.txt")" 2

refus() { # dossier libellé motif-du-KO [VAR=valeur…]
  local w=$1 l=$2 m=$3 rc; shift 3
  rc=$(cas "$w" "$@" | tail -1)
  egal "$l : refus (code non nul)" "$([ "$rc" != 0 ] && echo refus || echo "code $rc")" refus
  egal "$l : motif" "$(grep -c -- "$m" "$w/sortie.txt")" 1
  egal "$l : aucune poussée" "$(grep -c . "$w/poussees")" 0
  egal "$l : aucune signature versionnée neuve" "$(find "$w/fermeture" "$w/construction" -name '*.m1b.signee.yaml' -size +0 | wc -l)" 0
}
refus "$B/E2" "E2 sans SIGNER" "^KO   étape taches : SIGNER=1 seulement"
egal "E2 sans SIGNER : aucun appel de kubectl" "$(grep -c . "$B/E2/appels")" 0
refus "$B/E3" "E3 clé absente" "^KO   clé des tâches absente" SIGNER=1 BANC_SANS_CLE=1
refus "$B/E4" "E4 signature versionnée déjà présente" "^KO   déjà présent, jamais réécrit" SIGNER=1 BANC_VERSION=1
refus "$B/E5" "E5 tag m1b déjà présent" "^KO   G1 tekton/tasks/construire-rpm:m1b" SIGNER=1 "BANC_ZOT=tekton/tasks/construire-rpm:m1b sha256:$(printf 'a%.0s' {1..64})"
refus "$B/E6" "E6 tag m4c déplacé" "^KO   G2 tekton/tasks/construire-rpm:m4c" SIGNER=1 "BANC_ZOT=tekton/tasks/construire-rpm:m4c sha256:$(printf 'b%.0s' {1..64})"
refus "$B/E7" "E7 place basse" "^KO   G3 place libre" SIGNER=1 BANC_LIBRE=1000
refus "$B/E8" "E8 construire-rpm refusée à l'admission" "^KO   construire-rpm rendue admise" SIGNER=1 BANC_REFUSEE=construire-rpm
egal "E8 : aucune signature (pas de -signee dans le travail)" "$(find "$B/E8/O/travail" -name '*-signee.yaml' | wc -l)" 0
refus "$B/E9" "E9 gabarit altéré (mémoire du pas)" "^KO   construire-rpm signée contre celle de M4c" SIGNER=1 BANC_GABARIT=1

echo "bilan : $n OK, $k KO"
[ "$k" = 0 ]
