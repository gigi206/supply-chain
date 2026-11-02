#!/usr/bin/env bash
# Brique 01, S1 : à quel nom git compare-t-il un refspec négatif au push, la source ou la destination ?
# Dépôts jetables ; aucune option de l'utilisateur (GIT_CONFIG_GLOBAL=/dev/null). Usage : ./essai-refspec-negatif.sh
set -euo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=essai GIT_AUTHOR_EMAIL=essai@example.invalid GIT_COMMITTER_NAME=essai GIT_COMMITTER_EMAIL=essai@example.invalid
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
git --version
git init -q "$D/w"
git -C "$D/w" commit -q --allow-empty -m A
A=$(git -C "$D/w" rev-parse HEAD)
git -C "$D/w" commit -q --allow-empty -m C
C=$(git -C "$D/w" rev-parse HEAD)
essai() { # libellé négatif : la source porte la vue amont sous refs/upstream/heads, la destination a custom-1 à A
  rm -rf "$D/src.git" "$D/dst.git"
  git init -q --bare "$D/src.git" && git init -q --bare "$D/dst.git"
  git -C "$D/w" push -q "$D/src.git" "$C:refs/upstream/heads/main" "$C:refs/upstream/heads/custom-1"
  git -C "$D/w" push -q "$D/dst.git" "$A:refs/heads/custom-1"
  git -C "$D/src.git" push -q --force "$D/dst.git" "refs/upstream/heads/*:refs/heads/*" "$2"
  local v
  v=$(git -C "$D/dst.git" rev-parse refs/heads/custom-1)
  if [ "$v" = "$A" ]; then echo "$1 ($2) : custom-1 épargnée"; else echo "$1 ($2) : custom-1 écrasée"; fi
}
essai "négatif sur la source" "^refs/upstream/heads/custom-*"
essai "négatif sur la source, nom exact" "^refs/upstream/heads/custom-1"
essai "négatif sur la destination" "^refs/heads/custom-*"
