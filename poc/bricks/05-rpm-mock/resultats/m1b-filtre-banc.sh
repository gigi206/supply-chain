#!/usr/bin/env bash
# shellcheck disable=SC2015  # ok et ko ne échouent jamais
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : banc de la fonction filtre (masquage jeton/token et adresses), préparé à sec le 19/11/2026.
# Pour chaque script donné en argument, le banc extrait la ligne MASQUE= et la ligne filtre() telles qu'elles sont écrites,
# les évalue seules (rien d'autre du script ne tourne) et passe des lignes témoins factices. Aucun secret : les témoins sont
# des mots inventés. Ni cluster, ni Zot, ni réseau.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-filtre-banc.sh <script>... < /dev/null > <journal> 2>&1
set -euo pipefail
OK=0; KO=0
ok() { echo "OK   $*"; OK=$((OK + 1)); }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
MASQUEE='[ligne masquée : motif jeton|token]'
echo "# m1b-filtre-banc.sh, début $(date -u +%FT%TZ)"
echo "sed : $(sed --version | head -n 1)"
for s in "$@"; do
  echo "## $s : sha256 $(sha256sum "$s" | cut -c1-64)"
  m=$(grep -c '^MASQUE=' "$s"); f=$(grep -c '^filtre()' "$s")
  [ "$m" = 1 ] && [ "$f" = 1 ] && ok "une seule ligne MASQUE= et une seule ligne filtre()" || { ko "lignes MASQUE= : $m, filtre() : $f"; continue; }
  echo "   $(grep '^filtre()' "$s")"
  # shellcheck disable=SC1090  # lignes du script évaluées telles quelles
  source <(grep -E '^(MASQUE=|filtre\(\))' "$s")
  cas() { # libellé, entrée, sortie attendue
    local r c
    c=0; r=$(printf '%s\n' "$2" | filtre) || c=$?
    [ "$c" = 0 ] && [ "$r" = "$3" ] && ok "$1" || ko "$1 (code $c, sortie : $r)"
  }
  cas "jeton en minuscules masqué"  'valeur SENTINELLE-jeton ici'      "$MASQUEE"
  cas "TOKEN en capitales masqué"   'TOKEN=SENTINELLE-A'               "$MASQUEE"
  cas "Token au milieu masqué"      'x-auth-Token: SENTINELLE-B'       "$MASQUEE"
  cas "Jeton au début masqué"       'Jeton de service SENTINELLE-C'    "$MASQUEE"
  cas "barre verticale seule gardée" 'a|b sans motif'                  'a|b sans motif'
  cas "ligne ordinaire gardée"      'paquet rpm-4.16.1.3 installé'     'paquet rpm-4.16.1.3 installé'
  cas "adresse retirée"             'auteur <personne@exemple.test> ok' 'auteur <adresse retirée> ok'
  cas "adresse et jeton : masquée"  '<personne@exemple.test> token'    "$MASQUEE"
  r=$(printf 'un\ntoken SENTINELLE-D\ntrois\n' | filtre) || r="code $?"
  [ "$r" = "$(printf 'un\n%s\ntrois' "$MASQUEE")" ] && ok "trois lignes : seule celle du motif est remplacée" || ko "trois lignes : $r"
  r=$(printf 'SENTINELLE-E token\n' | filtre) || r="code $?"
  case "$r" in *SENTINELLE*) ko "témoin encore visible";; *) ok "aucun témoin visible en sortie";; esac
  unset -f filtre cas; unset MASQUE
done
echo "# bilan : OK $OK ; KO $KO ; fin $(date -u +%FT%TZ)"
[ "$KO" = 0 ]
