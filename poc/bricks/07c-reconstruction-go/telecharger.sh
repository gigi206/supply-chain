#!/usr/bin/env bash
# Brique 07c, étape 1 : Go 1.26.11 comme module golang.org/toolchain (accord du propriétaire du 24/11/2026, « Chantier à part »),
# comme la tâche mise outils:go-toolchain pour 1.26.10, mais SANS modifier mise.toml : le go de mise (1.24.7) télécharge le
# module par GOTOOLCHAIN, vérifié par sum.golang.org (GOSUMDB) ; puis ziphash relu et comparé à la ligne de sum.golang.org
# relevée avant l'accord ; la toolchain 1.26.10 doit rester intacte.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
O=$HOME/.cache/supply-chain-poc/outils/gomodcache
V=v0.0.1-go1.26.11.linux-amd64
D=$O/cache/download/golang.org/toolchain/@v
H1=h1:KyINmJ/FQdKRmDYGuTAAXkumyeR2DyUlSNHZj7XaLFg=   # sum.golang.org, relu le 2026-11-24T12:53:21Z
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
{
echo "# Go 1.26.11, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
attendu "module absent avant" "$(test -e "$D/$V.zip" && echo présent || echo absent)" absent
avant=$(cat "$D/v0.0.1-go1.26.10.linux-amd64.ziphash")
echo "1.26.10 avant : $avant"
GOMODCACHE=$O GOTOOLCHAIN=go1.26.11 GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org mise exec -- go version 2>&1 | tail -2
attendu "taille du module" "$(stat -c %s "$D/$V.zip" 2>/dev/null)" 71800213
attendu "ziphash = sum.golang.org (relevé avant l'accord)" "$(cat "$D/$V.ziphash" 2>/dev/null)" "$H1"
attendu "sum.golang.org relu maintenant" "$(curl -fsS --max-time 30 "https://sum.golang.org/lookup/golang.org/toolchain@$V" | awk -v v=$V '$2 == v {print $3}')" "$H1"
attendu "go version de la toolchain" "$(env -u GOROOT -u GOBIN "$O/golang.org/toolchain@$V/bin/go" version)" "go version go1.26.11 linux/amd64"
attendu "1.26.10 intacte" "$(cat "$D/v0.0.1-go1.26.10.linux-amd64.ziphash")" "$avant"
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
cat "$J"
