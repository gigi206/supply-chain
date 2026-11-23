#!/usr/bin/env bash
# Banc de rejeu-entrees.sh (2026-11-23) : dossiers jetables sous ~/.cache/supply-chain-poc/06/banc-rejeu-entrees (pas dans /tmp,
# en mémoire) ; le vrai $W est lu seulement (source des copies), jamais écrit. Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1; S=poc/bricks/06-deb-sbuild/rejeu-entrees.sh
B=$HOME/.cache/supply-chain-poc/06/banc-rejeu-entrees
test ! -e "$B" || { echo "existe déjà : $B"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
VRAI=$HOME/.cache/supply-chain-poc/08
mkdir -p "$B"
N=0; KO=0
cas() { # libellé code-attendu motif-attendu commande…
  local l=$1 ca=$2 m=$3 o c; shift 3
  o=$("$@" 2>&1); c=$?
  N=$((N + 1))
  if [ "$c" = "$ca" ] && grep -q -- "$m" <<< "$o"; then echo "OK   $l (code $c)"; else echo "KO   $l : code $c (attendu $ca), motif « $m » ; sortie :"; sed 's/^/     /' <<< "$o"; KO=$((KO + 1)); fi
}
{
echo "# banc de rejeu-entrees.sh, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), script $(sha256sum < "$S" | cut -c1-16)"
cas "garder : copie depuis le vrai \$W" 0 "copie faite" env E06="$B/e06" bash "$S" garder
cas "garder : copie relue, jamais réécrite" 0 "copie présente, relue" env E06="$B/e06" bash "$S" garder
cas "replacer : dossier de travail vide, fichiers créés et Packages régénéré" 0 "OK   \$W/s1-06/Packages" env E06="$B/e06" CONFIANCE_DIR="$B/o8" bash "$S" replacer
cas "replacer : relancé, fichiers présents comparés" 0 "déjà présent, comparé : \$W/s3-06" env E06="$B/e06" CONFIANCE_DIR="$B/o8" bash "$S" replacer
printf x | dd of="$B/o8/travail/s3-06/build-1/sample-app_1.0.0-2_amd64.deb" bs=1 seek=100 conv=notrunc status=none
cas "replacer : deb altéré sous \$W, refusé" 1 "KO   \$W/s3-06" env E06="$B/e06" CONFIANCE_DIR="$B/o8" bash "$S" replacer
cp -r "$B/e06" "$B/e06-altere"; printf x | dd of="$B/e06-altere/s1-06/hote/InRelease" bs=1 seek=100 conv=notrunc status=none
cas "garder : copie altérée, refusée" 1 "KO   copie s1-06/hote/InRelease" env E06="$B/e06-altere" bash "$S" garder
cas "garder : ni \$W ni copie, refusé, rien n'est démonté" 1 "rien n'est démonté" env E06="$B/absent" CONFIANCE_DIR="$B/vide" bash "$S" garder
cas "replacer : sans copie, refusé" 1 "copie absente" env E06="$B/absent" CONFIANCE_DIR="$B/o8b" bash "$S" replacer
cas "usage : étape inconnue" 2 "usage" bash "$S" autre
cas "vrai \$W intact (deb)" 0 "f66bbeb2aba31e52" sha256sum "$VRAI/travail/s3-06/build-1/sample-app_1.0.0-2_amd64.deb"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
find "$HOME/.cache/supply-chain-poc/06/banc-rejeu-entrees" -delete
cat "$J"
