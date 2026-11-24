#!/usr/bin/env bash
# Brique 07c, étape 7 À SEC : assemblage de l'image sample-app par la voie D (voie-d.sh etape_assembler) avec le binaire de
# Go 1.26.11, comparé à l'image de BuildKit f5e6bcb0, sur un registre Zot JETABLE local (127.0.0.1:5077, mise zot) ; rien n'est
# écrit dans le vrai Zot ni dans le cluster.
# Assemblage recopié de voie-d.sh (tar ustar, crane append --oci-empty-base puis mutate, mêmes options) ; la référence est lue
# dans son layout OCI sur l'hôte (manifeste, configuration et couche par leurs blobs), là où voie-d.sh la lit dans
# workspace/sample-app. Témoin : binaire e3749c68 (Go 1.26.10) face au layout 3a7ca1b1, mesure déjà faite par voie-d.sh au rejeu
# (sinon la recopie est fausse). Le digest de la voie D diffère de la référence par construction (en-tête tar, created) : relevé.
# Usage (racine du dépôt) : bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C
J=$1
W=$HOME/.cache/supply-chain-poc/07c/predire-voie-d
test ! -e "$W" || { echo "existe déjà : $W"; exit 1; }
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
B=$HOME/.cache/supply-chain-poc/07c/banc
R=127.0.0.1:5077
mkdir -p "$W/zot/data"
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
pid=
fin() { [ -z "$pid" ] || kill "$pid" 2>/dev/null; }
trap fin EXIT
blob() { echo "$1/blobs/sha256/${2#sha256:}"; }   # layout digest : chemin du blob
mesure() { # libellé binaire layout digest-de-référence
  local v=$1 bin=$2 lay=$3 ref=$4 i d man cfg c
  echo "## $v : binaire $(sha256sum < "$bin" | cut -c1-16), référence $ref"
  for i in a b; do
    mkdir -p "$W/$v-$i/racine"
    install -m 0755 "$bin" "$W/$v-$i/racine/sample-app"
    tar --format=ustar --numeric-owner --owner=0 --group=0 --mtime=@0 -b 1 -C "$W/$v-$i/racine" -cf "$W/$v-$i/couche.tar" sample-app
    crane append --insecure --oci-empty-base -f "$W/$v-$i/couche.tar" -t "$R/app:$v-$i" >/dev/null 2>"$W/crane.err" || cat "$W/crane.err"
    crane mutate --insecure "$R/app:$v-$i" --set-platform linux/amd64 -u 65532:65532 --entrypoint /sample-app -w / \
      -e PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin -t "$R/app:$v-$i" >/dev/null 2>"$W/crane.err" || cat "$W/crane.err"
    echo "$v $i : couche $(sha256sum < "$W/$v-$i/couche.tar" | cut -c1-64), image $(crane digest --insecure "$R/app:$v-$i")"
  done
  d=$(crane digest --insecure "$R/app:$v-a")
  attendu "$v : image identique sur deux assemblages" "$d" "$(crane digest --insecure "$R/app:$v-b")"
  attendu "$v : index du layout de référence" "$(jq -r '.manifests[0].digest' "$lay/index.json")" "$ref"
  man=$(blob "$lay" "$ref"); cfg=$(blob "$lay" "$(jq -r .config.digest "$man")")
  gzip -dc < "$(blob "$lay" "$(jq -r '.layers[0].digest' "$man")")" > "$W/$v-ref.tar"
  crane config --insecure "$R/app:$v-a" > "$W/$v-d-config.json"
  attendu "$v : binaire extrait de la couche de référence = binaire assemblé" "$(tar -xOf "$W/$v-ref.tar" sample-app | sha256sum | cut -c1-64)" "$(sha256sum < "$bin" | cut -c1-64)"
  attendu "$v : taille du tar (référence, voie D)" "$(stat -c %s "$W/$v-ref.tar") $(stat -c %s "$W/$v-a/couche.tar")" "$(stat -c %s "$W/$v-ref.tar") $(stat -c %s "$W/$v-ref.tar")"
  cmp -l "$W/$v-ref.tar" "$W/$v-a/couche.tar" > "$W/$v-cmp.txt" || true
  echo "octets différents : $(wc -l < "$W/$v-cmp.txt"), aux positions $(awk '{print $1 - 1}' "$W/$v-cmp.txt" | paste -sd' ')"
  c=$(awk '{p = $1 - 1; if (!((p >= 148 && p < 156) || (p >= 329 && p < 345))) print}' "$W/$v-cmp.txt" | wc -l)
  attendu "$v : octets différents hors somme de contrôle, devmajor et devminor" "$c" 0
  attendu "$v : configuration hors rootfs, historique et created (référence = voie D)" \
    "$(jq -S -c 'del(.rootfs, .history, .created)' "$W/$v-d-config.json" | sha256sum | cut -c1-16)" "$(jq -S -c 'del(.rootfs, .history, .created)' "$cfg" | sha256sum | cut -c1-16)"
  attendu "$v : created (référence, voie D)" "$(jq -r .created "$cfg") $(jq -r .created "$W/$v-d-config.json")" "1970-01-01T00:00:00Z 0001-01-01T00:00:00Z"
  echo "DIGEST VOIE D|$v|$d"
}
{
echo "# assemblage de la voie D, Go 1.26.10 (témoin) et 1.26.11, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), crane $(crane version), $(tar --version | head -1)"
umask 022
jq --arg d "$W/zot/data" '.storage.rootDirectory = $d | .http.port = "5077"' poc/bricks/03-deps-closure/zot-config.json > "$W/zot/config.json"
mise exec -- zot serve "$W/zot/config.json" > "$W/zot/zot.log" 2>&1 &
pid=$!
for _ in $(seq 1 30); do curl -fsS "http://$R/v2/" >/dev/null 2>&1 && break; sleep 1; done
mesure 1.26.10 "$B/b04-1.26.10/extrait/sample-app" "$HOME/.cache/supply-chain-poc/w/b04/app-layout" \
  sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
mesure 1.26.11 "$B/b04-1.26.11/extrait/sample-app" "$B/b04-1.26.11/app-layout" \
  sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
fin; pid=
find "$W" -delete
sed -i "s#$HOME#~#g" "$J"
cat "$J"
