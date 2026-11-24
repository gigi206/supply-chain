#!/usr/bin/env bash
# Brique 07c, étape 7 À SEC (option « un seul digest », choix du propriétaire du 24/11/2026) : gabarit de la tâche d'essai
# publier-essai rendu comme politique.sh declencheurs, avec le digest des essais 3a7ca1b1 puis f5e6bcb0 ; seul écart attendu :
# la ligne du résultat IMAGE_DIGEST. Témoin du bundle : la tâche signée versionnée poussée par tkn bundle push dans un Zot
# JETABLE (127.0.0.1:5077) doit redonner 836cd080 (liste revue), deux fois, sinon le digest d'un bundle ne peut pas être calculé
# hors du vrai Zot. RIEN N'EST SIGNÉ (la clé des tâches n'est pas lue) ; rien n'est écrit dans le vrai Zot ni dans le cluster.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
W=$HOME/.cache/supply-chain-poc/07c/predire-publier-essai
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
H=poc/bricks/08-trust-plane
REG=sc-stockage.poc.test:5000
BUSYBOX_AMONT=docker.io/rancher/mirrored-library-busybox:1.37.0   # politique.sh
ANCIEN=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
NOUVEAU=sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7
R=127.0.0.1:5077
mkdir -p "$W/zot/data"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
pid=
fin() { [ -z "$pid" ] || kill "$pid" 2>/dev/null; }
trap fin EXIT
rendre() { sed -e "s#@IMAGE@#$REG/builds/essai-webhook#" -e "s#@DIGEST@#$1#" -e "s#@BUSYBOX@#$busybox#" "$H/politique/taches/publier-essai.yaml"; }
{
echo "# tâche publier-essai, gabarit et bundle, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), $(tkn version | head -1)"
busybox=$(awk -F'\t' -v b="$BUSYBOX_AMONT" '$1 == b {print $4}' "$H/resultats/tekton-images.tsv")
echo "busybox : $busybox"
rendre "$ANCIEN" > "$W/ancien.yaml"; rendre "$NOUVEAU" > "$W/nouveau.yaml"
diff "$W/ancien.yaml" "$W/nouveau.yaml" | sed 's/^/  /'
attendu "lignes différentes entre les deux rendus" "$(diff "$W/ancien.yaml" "$W/nouveau.yaml" | grep -c '^[<>]')" 2
attendu "seule ligne changée : le résultat IMAGE_DIGEST" "$(diff "$W/ancien.yaml" "$W/nouveau.yaml" | grep '^>' | grep -c "printf '%s' '$NOUVEAU' > \$(results.IMAGE_DIGEST.path)")" 1
attendu "la tâche signée versionnée porte l'ancien digest" "$(grep -c "printf '%s' '$ANCIEN' > \$(results.IMAGE_DIGEST.path)" "$H/politique/taches/publier-essai.signee.yaml")" 1
jq --arg d "$W/zot/data" '.storage.rootDirectory = $d | .http.port = "5077"' poc/bricks/03-deps-closure/zot-config.json > "$W/zot/config.json"
mise exec -- zot serve "$W/zot/config.json" > "$W/zot/zot.log" 2>&1 &
pid=$!
for _ in $(seq 1 30); do curl -fsS "http://$R/v2/" >/dev/null 2>&1 && break; sleep 1; done
for t in a b; do
  tkn bundle push "$R/tekton/tasks/publier-essai:$t" -f "$H/politique/taches/publier-essai.signee.yaml" > "$W/tkn-$t.out" 2>&1 || cat "$W/tkn-$t.out"
done
attendu "témoin : bundle de la tâche signée versionnée = liste revue" "$(crane digest --insecure "$R/tekton/tasks/publier-essai:a")" \
  "sha256:$(awk '/tekton\/tasks\/publier-essai:/ {getline; print $3}' "$H/politique/porte/taches.yml" | sed 's/^sha256://')"
attendu "témoin : deux poussées, même digest" "$(crane digest --insecure "$R/tekton/tasks/publier-essai:b")" "$(crane digest --insecure "$R/tekton/tasks/publier-essai:a")"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
fin; pid=
find "$W" -delete
sed -i "s#$HOME#~#g" "$J"
cat "$J"
