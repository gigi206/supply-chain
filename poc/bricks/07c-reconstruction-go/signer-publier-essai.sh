#!/usr/bin/env bash
# Brique 07c, étape 7 (option « Un seul digest ») : re-signature de la tâche d'essai publier-essai, rendue comme politique.sh
# declencheurs avec le digest des essais f5e6bcb0 (au lieu de 3a7ca1b1), par la clé des tâches (lue par tkn, jamais affichée).
# SUR ACCORD NOMMÉ DU PROPRIÉTAIRE, passé en ACCORD (recopié au journal). Écrit politique/taches/publier-essai.signee.yaml ;
# vérifie la signature par la clé publique des tâches (témoin : l'ancienne signature ; négatif : copie altérée) ; calcule le
# digest du bundle dans un Zot JETABLE (127.0.0.1:5077, compat docker2s2 comme le vrai Zot ; méthode validée par
# predire-publier-essai.log : 836cd080 redonné). Rien n'est écrit dans le vrai Zot ni dans le cluster ; la liste revue
# (politique/porte/taches.yml) est mise à jour à la main après revue du journal.
# Usage (racine du dépôt) : ACCORD='<réponse du propriétaire>' bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
: "${ACCORD:?accord nommé du propriétaire requis}"
W=$HOME/.cache/supply-chain-poc/07c/signer-publier-essai
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
H=poc/bricks/08-trust-plane
V=$H/politique/taches/publier-essai.signee.yaml
CLE=$HOME/.cache/supply-chain-poc/08/secrets/taches.key
PUB=$HOME/.cache/supply-chain-poc/08/pki/taches.pub
REG=sc-stockage.poc.test:5000
BUSYBOX_AMONT=docker.io/rancher/mirrored-library-busybox:1.37.0   # politique.sh
ANCIEN=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
NOUVEAU=sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7
BUNDLE_ANCIEN=sha256:836cd080991d54ef49c86f5ae8c61421c4fddf615e2e981049c4febb6cea5849
R=127.0.0.1:5077
test -s "$CLE" || { echo "clé des tâches absente"; exit 1; }
mkdir -p "$W/zot/data"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
verifie() { tkn task verify "$1" -K "$PUB" > "$W/verif.out" 2>&1 && echo acceptée || echo "refusée ($(grep -m1 '^Error' "$W/verif.out" | cut -c1-120))"; }
pid=
fin() { [ -z "$pid" ] || kill "$pid" 2>/dev/null; }
trap fin EXIT
{
echo "# re-signature de publier-essai (f5e6bcb0), $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), $(tkn version | head -1)"
echo "accord du propriétaire (verbatim) : « $ACCORD »"
echo "clé publique des tâches : sha256 $(openssl pkey -pubin -in "$PUB" -outform DER | sha256sum | cut -c1-16)… (DER)"
busybox=$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$H/resultats/tekton-images.tsv")
cp "$V" "$W/ancienne.yaml"
attendu "témoin : ancienne signature vérifiée par la clé publique" "$(verifie "$W/ancienne.yaml")" acceptée
sed -e "s#@IMAGE@#$REG/builds/essai-webhook#" -e "s#@DIGEST@#$NOUVEAU#" -e "s#@BUSYBOX@#$busybox#" "$H/politique/taches/publier-essai.yaml" > "$W/rendue.yaml"
tkn task sign "$W/rendue.yaml" -K "$CLE" -f "$W/signee.yaml" > "$W/sign.out" 2>&1; attendu "tkn task sign" "$?" 0
attendu "nouvelle signature vérifiée par la clé publique" "$(verifie "$W/signee.yaml")" acceptée
sed "s/${NOUVEAU#sha256:}/${ANCIEN#sha256:}/" "$W/signee.yaml" > "$W/alteree.yaml"
case $(verifie "$W/alteree.yaml") in refusée*) attendu "négatif : nouvelle signature, digest remis à 3a7ca1b1" refusée refusée ;;
  *) attendu "négatif : nouvelle signature, digest remis à 3a7ca1b1" acceptée refusée ;; esac
diff <(grep -v 'tekton.dev/signature:' "$W/ancienne.yaml") <(grep -v 'tekton.dev/signature:' "$W/signee.yaml") | sed 's/^/  /'
attendu "écart avec l'ancienne, signature exceptée : la seule ligne IMAGE_DIGEST" \
  "$(diff <(grep -v 'tekton.dev/signature:' "$W/ancienne.yaml") <(grep -v 'tekton.dev/signature:' "$W/signee.yaml") | grep '^[<>]' | sed 's/sha256:[0-9a-f]*/D/' | sort -u | wc -l) $(diff <(grep -v 'tekton.dev/signature:' "$W/ancienne.yaml") <(grep -v 'tekton.dev/signature:' "$W/signee.yaml") | grep -c "^> .*'$NOUVEAU' > \$(results.IMAGE_DIGEST.path)")" "2 1"
jq --arg d "$W/zot/data" '.storage.rootDirectory = $d | .http.port = "5077" | .http.compat = ["docker2s2"]' poc/bricks/03-deps-closure/zot-config.json > "$W/zot/config.json"
mise exec -- zot serve "$W/zot/config.json" > "$W/zot/zot.log" 2>&1 &
pid=$!
for _ in $(seq 1 30); do curl -fsS "http://$R/v2/" >/dev/null 2>&1 && break; sleep 1; done
for t in a b; do tkn bundle push "$R/tekton/tasks/publier-essai:$t" -f "$W/signee.yaml" > "$W/tkn-$t.out" 2>&1 || cat "$W/tkn-$t.out"; done
tkn bundle push "$R/tekton/tasks/publier-essai:temoin" -f "$W/ancienne.yaml" > "$W/tkn-t.out" 2>&1 || cat "$W/tkn-t.out"
attendu "témoin : bundle de l'ancienne signature" "$(crane digest --insecure "$R/tekton/tasks/publier-essai:temoin")" "$BUNDLE_ANCIEN"
a=$(crane digest --insecure "$R/tekton/tasks/publier-essai:a")
attendu "bundle de la nouvelle signature : deux poussées, même digest" "$(crane digest --insecure "$R/tekton/tasks/publier-essai:b")" "${a:-vide}"
if [ "$KO" = 0 ]; then
  cp "$W/signee.yaml" "$V"
  attendu "signature versionnée remplacée" "$(cmp -s "$W/signee.yaml" "$V" && echo oui)" oui
  echo "NOUVEAU BUNDLE|$a"
else
  echo "écart : signature versionnée NON remplacée"
fi
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
fin; pid=
find "$W" -delete
sed -i "s#$HOME#~#g" "$J"
cat "$J"
