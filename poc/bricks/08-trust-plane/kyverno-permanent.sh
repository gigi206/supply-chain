#!/usr/bin/env bash
# Brique 08 : Kyverno corrigé EN SERVICE, avec une politique d'admission qui lit ctlog.tsaCertChain (décision du propriétaire du
# 23/11/2026, « Image + politique », après « Oui, après le rejeu » ; Kyverno 1.20.0 garde le bug, kyverno-correctif-cli_autre-1.20.0.log).
# Image : celle du passage borné du 09/11 (kyverno-admission.sh construire et image, binaire 2b36652a…, image eec37159… dans
# essais/kyverno-correctif), contrôleur d'admission seul ; background, reports et cleanup restent officiels. Construite par nous,
# sans release signée : écart au critère du doc 04, §1, accepté par le propriétaire (ADR à compléter).
# Politique : contrôle 9 de commun.sh (ivpol, attestor à clé de Chains, bundles de horodatage/bundles, sans journal, tsaCertChain de
# la TSA du PoC), bornée à l'espace livraison (créé ici, Pod Security restricted), toutes les images ; évaluation de fond coupée
# (spec.evaluation.background.enabled: false : les contrôleurs officiels ne l'évaluent pas).
# Les fonctions pod, admission, pret et bascule sont celles de kyverno-admission.sh (lues dans le fichier, jamais recopiées).
#   sec     rien d'écrit : politique et espace rendus, dry-run serveur de leur création ; image corrigée attendue dans Zot (si
#           présente) ; image en service relevée.
#   pose    ACCORD DU PROPRIÉTAIRE. Espace livraison et politique horodatage-livraison posés ; témoin avec l'image officielle (le pod
#           d'essai, bundle horodaté valide, est refusé par une erreur interne : le bug) ; bascule du contrôleur d'admission sur
#           l'image corrigée ; le même pod est admis, sans erreur interne ; une image sans provenance (amont/kyverno) est refusée par
#           C9 ; le pod d'essai hors de livraison reste admis (bornage). Pods jamais créés (dry-run serveur).
#   retour  ACCORD DU PROPRIÉTAIRE. Image officielle remise, politique et espace retirés.
# Usage (racine du dépôt) : DISTRO=rke2 poc/bricks/08-trust-plane/kyverno-permanent.sh <sec|pose|retour> [suffixe du journal]
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
KA=$here/kyverno-admission.sh
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # images d'essai signées en J4
DEP=kyverno-admission-controller
NS_LIV=livraison NS_HORS=horodatage NOM=horodatage-livraison
OFF_INDEX=sha256:c8c4dd09e720d2cd7fd24ca73ac28e46651001372f988e0cba3f2f612f04b955
CORR=sha256:eec37159789d9ab1cf75adc69db6589e09f0f96d4718a31508c6a3047ca70d8e   # image corrigée du 09/11 (kyverno-admission-image.digest)
OFFICIELLE=$REG/amont/kyverno/kyverno@$OFF_INDEX
CORRIGEE=$REG/essais/kyverno-correctif@$CORR
T=$W/kyverno-permanent
mkdir -p "$T"
NS=$NS_LIV
# fonctions du passage du 09/11, lues dans kyverno-admission.sh
for f in pod admission pret bascule; do eval "$(awk "/^$f\\(\\) \\{/,/^}/" "$KA")"; done
declare -F pod admission pret bascule > /dev/null || { echo "fonctions de kyverno-admission.sh introuvables"; exit 3; }

politique() { # politique du contrôle 9 bornée à livraison, registre par son nom, évaluation de fond coupée
  ivpol "$DEPOT_BUNDLES" "$P/tsa-chaine.pem" "$NOM" | python3 -I -c '
import sys
reg_hote, reg, ns = sys.argv[1:4]
t = sys.stdin.read()
t = t.replace("    - glob: \"%s/*\"" % reg_hote, "    - glob: \"*\"")
t = t.replace("repository: %s/" % reg_hote, "repository: %s/" % reg)
t = t.replace("  matchConstraints:\n", "  evaluation:\n    background:\n      enabled: false\n  matchConstraints:\n    namespaceSelector:\n      matchExpressions:\n      - {key: kubernetes.io/metadata.name, operator: In, values: [%s]}\n" % ns, 1)
assert reg_hote not in t and t.count("tsaCertChain") == 1 and "enabled: false" in t
sys.stdout.write(t)' "$REG_HOTE" "$REG" "$NS_LIV"
}
espace() { cat <<FIN
apiVersion: v1
kind: Namespace
metadata:
  name: $NS_LIV
  labels: {pod-security.kubernetes.io/enforce: restricted, pod-security.kubernetes.io/enforce-version: latest}
FIN
}
h() { sha256sum | cut -c1-16; }
image_en_service() { kubectl get deploy -n kyverno "$DEP" -o jsonpath='{.spec.template.spec.containers[?(@.name=="kyverno")].image}'; }
cas() { # libellé espace image attendu(PASS|FAIL) interne-attendu(oui|non|*) [zone] : OK ou KO
  local r d i
  pod "essai-$1" "$2" "$3" "${6:-}" > "$T/$1.yaml"
  r=$(admission "$T/$1.yaml" "$NOM"); d=${r%%$'\t'*}; i=$(cut -f2 <<< "$r")
  if [ "$d" = "$4" ] && { [ "$5" = '*' ] || [ "$i" = "$5" ]; }; then echo "OK   $1 : $d ; erreur interne : $i"
  else echo "KO   $1 : $d (attendu $4), erreur interne : $i (attendue $5) ; $(cut -f3 <<< "$r" | cut -c1-200)"; KO=1; fi
}

etape_sec() {
  echo "image en service : $(image_en_service)"
  politique > "$T/politique.yaml"; espace > "$T/espace.yaml"
  echo "politique rendue : $(h < "$T/politique.yaml") ; espace : $(h < "$T/espace.yaml")"
  sed '/-----BEGIN/,/-----END/d' "$T/politique.yaml" | sed 's/^/  | /'   # clé et certificats jamais affichés
  kubectl create --dry-run=server -f "$T/espace.yaml" < /dev/null > /dev/null 2>"$T/e.err" && echo "OK   espace $NS_LIV : dry-run serveur accepté" || { echo "KO   espace : $(head -c 200 "$T/e.err")"; KO=1; }
  kubectl create --dry-run=server -f "$T/politique.yaml" < /dev/null > /dev/null 2>"$T/p.err" && echo "OK   politique $NOM : dry-run serveur accepté" || { echo "KO   politique : $(head -c 200 "$T/p.err")"; KO=1; }
  if SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/essais/kyverno-correctif@$CORR" > /dev/null 2>&1; then
    echo "image corrigée présente dans Zot : $CORR"; else echo "image corrigée absente de Zot (kyverno-admission.sh image à lancer, sur accord)"; fi
  [ -s "$P/tsa-chaine.pem" ] && [ -s "$R/chains-cle-publique.pem" ] && echo "OK   chaîne TSA et clé de Chains présentes" || { echo "KO   chaîne TSA ou clé de Chains absente"; KO=1; }
}

etape_pose() {
  SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/essais/kyverno-correctif@$CORR" > /dev/null 2>&1 || { echo "NON JUGÉ : image corrigée absente de Zot"; exit 3; }
  [ "$(image_en_service)" = "$OFFICIELLE" ] && echo "OK   image en service : officielle" || { echo "NON JUGÉ : image en service $(image_en_service)"; exit 3; }
  echo "## espace et politique ($(date -u +%H:%M:%S) UTC)"
  espace > "$T/espace.yaml"; politique > "$T/politique.yaml"
  kubectl apply -f "$T/espace.yaml" < /dev/null && kubectl apply -f "$T/politique.yaml" < /dev/null || { echo "KO   pose de l'espace ou de la politique"; exit 1; }
  for i in $(seq 60); do [ "$(kubectl get imagevalidatingpolicy "$NOM" -o jsonpath='{.status.conditionStatus.ready}' 2>/dev/null)" = true ] && break; sleep 1; done
  [ "$i" -lt 60 ] && echo "OK   politique $NOM prête" || { echo "KO   politique jamais prête"; KO=1; }
  sleep 2
  local img=$REG/builds/essai-signature@$APP_DIGEST
  echo "## témoin : image officielle"
  cas temoin-officiel "$NS_LIV" "$img" FAIL oui
  echo "## bascule du contrôleur d'admission"
  bascule "$CORRIGEE" "${CORR#sha256:}" || { echo "KO   bascule"; KO=1; }
  echo "## recette : image corrigée"
  cas horodate "$NS_LIV" "$img" PASS non
  cas sans-provenance "$NS_LIV" "$OFFICIELLE" FAIL non
  cas hors-livraison "$NS_HORS" "$img" PASS non confiance   # horodatage est en zone confiance (zone-confiance de J6)
  [ "$(image_en_service)" = "$CORRIGEE" ] && echo "OK   image en service : corrigée ($CORR)" || { echo "KO   image en service $(image_en_service)"; KO=1; }
  echo "retour arrière (sur accord) : poc/bricks/08-trust-plane/kyverno-permanent.sh retour"
}

etape_recette() { # ajout du 2026-11-23T18:42:27Z : recette seule, dry-run serveur, image corrigée en service (pose : témoin hors de livraison
  # sans nodeSelector, refusé par zone-confiance, défaut du script)
  [ "$(image_en_service)" = "$CORRIGEE" ] && echo "OK   image en service : corrigée" || { echo "NON JUGÉ : image en service $(image_en_service)"; exit 3; }
  local img=$REG/builds/essai-signature@$APP_DIGEST
  cas horodate "$NS_LIV" "$img" PASS non
  cas sans-provenance "$NS_LIV" "$OFFICIELLE" FAIL non
  cas hors-livraison "$NS_HORS" "$img" PASS non confiance
}

etape_retour() {
  echo "## image officielle remise ($(date -u +%H:%M:%S) UTC)"
  bascule "$OFFICIELLE" "${OFF_INDEX#sha256:}|6f0c520054d863a4a3df53ac7bb67d571d20421b77b99809013a62ec5f1d5947" || { echo "KO   retour de l'image"; KO=1; }
  kubectl delete imagevalidatingpolicy "$NOM" --ignore-not-found < /dev/null && kubectl delete namespace "$NS_LIV" --ignore-not-found < /dev/null \
    && echo "OK   politique et espace retirés" || { echo "KO   retrait"; KO=1; }
  [ "$(image_en_service)" = "$OFFICIELLE" ] && echo "OK   image en service : officielle" || { echo "KO   image en service $(image_en_service)"; KO=1; }
}

e=${1:?usage : $0 sec|pose|retour [suffixe]}
case $e in sec|pose|recette|retour) ;; *) echo "usage : $0 sec|pose|recette|retour [suffixe]" >&2; exit 2 ;; esac
L=$R/kyverno-permanent-$e${2:+-$2}.log
[ ! -e "$L" ] || { echo "$L existe déjà, rien lancé"; exit 2; }
KO=0
{ date -u "+# kyverno-permanent.sh $e, %Y-%m-%dT%H:%M:%SZ"; "etape_$e"; echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; [ "$KO" = 0 ] && echo "bilan : tenue" || echo "bilan : KO"; } 2>&1 \
  | sed -u "s#$HOME#~#g" | tee "$L"
grep -q '^bilan : tenue' "$L"
