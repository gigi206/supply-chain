#!/usr/bin/env bash
# Cherche chaque secret des briques 08, 09 et 07a (fichiers nommés) et 10, et tout en-tête de clé privée seul sur sa ligne, dans les fichiers modifiés ou nouveaux du dépôt (motifs en fichier, jamais en argument).
# À lancer avant chaque commit. Les motifs vivent dans un dossier privé (0700), supprimé même en cas d'échec.
set -euo pipefail
cd "$(dirname "$0")/.."
M=$(mktemp -d)
trap 'rm -rf -- "${M:?}"' EXIT
for f in "$HOME"/.cache/supply-chain-poc/08/secrets/* "$HOME"/.cache/supply-chain-poc/10/secrets/*; do   # 10 : domaine de replay (brique 10)
  [ -f "$f" ] || continue
  b=${f%/secrets/*}   # 08 ou 10 : préfixe du motif (deux briques peuvent avoir le même nom de fichier)
  grep -v -e '^-----' -e '^$' "$f" > "$M/motif-${b##*/}-${f##*/}" || true
done
# 09 (signature OpenPGP) : fichiers nommés seulement, jamais tout le dossier (les lignes de cle-publique.asc bloqueraient
# tout commit de la clé publique) ; lignes d'au moins 16 caractères (une ligne courte d'un export armuré donnerait de faux refus).
Z="$HOME"/.cache/supply-chain-poc/09/secrets
for f in "$Z"/cle-openpgp.asc "$Z"/revocation.asc "$Z"/openbao-lien.secret "$Z"/zot-poc-lien.password; do
  [ -f "$f" ] || continue
  grep -v -e '^-----' -e '^$' "$f" | awk 'length($0) >= 16' > "$M/motif-09-${f##*/}" || true
done
# 09 : authentification de poc-lien dans zot-poc-lien-docker/config.json = base64 de « poc-lien:<mot de passe> », calculée sans argument.
[ ! -f "$Z/zot-poc-lien.password" ] || { printf 'poc-lien:'; tr -d '\n' < "$Z/zot-poc-lien.password"; } | base64 -w0 > "$M/motif-09-zot-poc-lien-auth"
# 07a (ajout du 23/11/2026, brique 07b) : mot de passe OpenBao du propriétaire (pièce 2) et de poc-vex (pièce 4), fichiers nommés ;
# authentification de poc-vex en base64, calculée sans argument.
Z7="$HOME"/.cache/supply-chain-poc/07a/secrets
for f in "$Z7"/openbao-proprietaire.password "$Z7"/zot-poc-vex.password; do
  [ -f "$f" ] || continue
  grep -v -e '^$' "$f" | awk 'length($0) >= 16' > "$M/motif-07a-${f##*/}" || true
done
[ ! -f "$Z7/zot-poc-vex.password" ] || { printf 'poc-vex:'; tr -d '\n' < "$Z7/zot-poc-vex.password"; } | base64 -w0 > "$M/motif-07a-zot-poc-vex-auth"
mapfile -t fichiers < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
n=$(find "$M" -name 'motif-*' | wc -l)
echo "fichiers : ${#fichiers[@]} ; motifs : $n"
[ "$n" -gt 0 ] || { echo "KO   aucun motif lu : contrôle impossible"; exit 1; }   # 0 motif ne doit jamais donner OK
openssl rand -hex 16 > "$M/temoin"
cp "$M/temoin" "$M/temoin.txt"
n=$(grep -c -F -f "$M/temoin" "$M/temoin.txt" || true)
echo "témoin retrouvé : $n"
ko=0
for m in "$M"/motif-*; do
  [ -s "$m" ] || continue
  n=$(grep -l -F -f "$m" -- "${fichiers[@]}" 2>/dev/null | wc -l || true)
  [ "$n" = 0 ] || { echo "KO   ${m##*/motif-} : $n fichier(s)"; ko=1; }
done
# Toute clé privée armurée, quelle que soit son origine (OpenPGP, cosign, OpenSSH…) : en-tête seul sur sa ligne.
n=$(grep -l -x -E -e '-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----' -- "${fichiers[@]}" 2>/dev/null | wc -l || true)
[ "$n" = 0 ] || { echo "KO   en-tête de clé privée seul sur sa ligne : $n fichier(s)"; ko=1; }
[ "$ko" = 0 ] && echo "OK   aucun secret dans les fichiers modifiés ou nouveaux"
