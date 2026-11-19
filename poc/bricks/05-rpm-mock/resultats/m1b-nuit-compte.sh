#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Compte les lignes qui contiennent jeton ou token (casse ignorée, motif de MASQUE), sans rien afficher d'autre.
# À lancer avant toute lecture des journaux d'une mesure dont le masquage est inopérant (m1b.sh, m1b-builders.sh).
# Usage : bash m1b-nuit-compte.sh <racine du dépôt> [fichier...]
#   sans fichier : fichiers nouveaux ou modifiés sous poc/bricks/05-rpm-mock/resultats (git status),
#   plus le fichier nommé par la variable SORTIE si elle est donnée (sortie de la tâche d'attente).
# Sortie : « fichier : n » par fichier, puis « # total n ; fichiers f ». Code 2 si grep échoue.
set -euo pipefail
cd "$1"; shift
if [ "$#" -gt 0 ]; then
  fichiers=("$@")
else
  mapfile -t fichiers < <(git status --porcelain -uall -- poc/bricks/05-rpm-mock/resultats | cut -c4-)
  [ -z "${SORTIE:-}" ] || fichiers+=("$SORTIE")
fi
total=0
for f in "${fichiers[@]}"; do
  [ -f "$f" ] || { echo "$f : absent"; continue; }
  c=0; n=$(grep -c -i -E 'jeton|token' -- "$f") || c=$?
  [ "$c" -le 1 ] || { echo "$f : grep code $c"; exit 2; }   # 1 = aucune ligne, 2 = erreur
  echo "$f : $n"
  total=$((total + n))
done
echo "# total $total ; fichiers ${#fichiers[@]}"
