#!/usr/bin/env bash
# Brique 05, carte de M5b (18/11/2026) : présence, taille et sha256 des deux archives de racine gardées sur l'hôte par S1
# (racine.tar de l'étape racine, boot-racine.tar de l'étape boot_racine), comparés aux valeurs des journaux archivés. Hôte seul,
# hors ligne, lecture seule ; seuls ces deux fichiers nommés sont lus, le dossier n'est pas listé.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m5b-archives.sh > poc/bricks/05-rpm-mock/resultats/m5b-archives.log
set -euo pipefail
r=$(cd "$(dirname "$0")" && pwd)
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05   # T de s1.sh, l. 190
ko=0
echo "# m5b-archives.sh, début $(date -u +%FT%TZ)"
controle() { # fichier, journal, motif de la ligne qui porte la taille et le sha256
  local f=$T/$1 l=$r/$2 t s ta sa
  t=$(sed -n "s/^ *$3.* \([0-9]\+\) octets, sha256 \([0-9a-f]\{64\}\)$/\1/p" "$l" | head -1)
  s=$(sed -n "s/^ *$3.* \([0-9]\+\) octets, sha256 \([0-9a-f]\{64\}\)$/\2/p" "$l" | head -1)
  [ -n "$t" ] && [ -n "$s" ] || { echo "KO   $1 : valeur attendue introuvable dans $2"; ko=1; return 0; }
  [ -s "$f" ] || { echo "KO   $1 absent ou vide"; ko=1; return 0; }
  ta=$(stat -c %s "$f"); sa=$(sha256sum < "$f" | cut -c1-64)
  echo "     $1 : $ta octets, sha256 $sa"
  echo "     attendu ($2) : $t octets, sha256 $s"
  if [ "$ta" = "$t" ] && [ "$sa" = "$s" ]; then echo "OK   $1 égal au journal archivé"; else echo "KO   $1 différent du journal archivé"; ko=1; fi
}
controle racine.tar s1-racine.log 'archive racine :'
controle boot-racine.tar s1-boot_racine.log 'archive racine dérivée : rc 0,'
echo "# fin $(date -u +%FT%TZ), code $ko"
exit "$ko"
