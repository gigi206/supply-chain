#!/usr/bin/env bash
# Brique 09 : garde locale contre une clé privée OpenPGP armurée dans un commit (décision « Garde locale d'abord », 19/11/2026).
# À lancer avant chaque commit de la branche, avec « mise exec -- make reuse » et tools/secrets-depot.sh. Refuse toute ligne qui
# est l'en-tête de bloc de clé privée seul sur sa ligne (espaces et retour chariot tolérés autour), dans l'index (ce qui sera
# commité) et dans l'arbre de travail (fichiers suivis et non suivis non ignorés). N'affiche que des noms de fichiers, jamais de
# contenu. Limites : fichiers binaires non lus (-I : un export non armuré n'est pas vu), fichiers ignorés par .gitignore non lus,
# clé sans sa ligne d'en-tête non vue. Usage : garde-cle-privee.sh [ARBRE] (par défaut, l'arbre git du script). Code 0 si rien
# n'est trouvé, 1 sinon ou si le contrôle est impossible.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
R=$(git -C "${1:-$here}" rev-parse --show-toplevel) || { echo "KO   pas un arbre git : contrôle impossible"; exit 1; }
cd "$R" || exit 1
P='^[[:space:]]*-----BEGIN PGP PRIVATE KEY BLOCK-----[[:space:]]*$'
echo "garde clé privée : $(git ls-files | wc -l) fichier(s) suivi(s), $(git ls-files --others --exclude-standard | wc -l) non suivi(s) non ignoré(s)"
ko=0
for portee in --cached --untracked; do
  l=$(git grep -I -l -E -e "$P" "$portee"); rc=$?
  case $rc in
    0) echo "KO   en-tête de clé privée seul sur sa ligne ($portee) :"; printf '%s\n' "$l" | sed 's/^/     /'; ko=1 ;;
    1) echo "OK   aucun en-tête de clé privée ($portee)" ;;
    *) echo "KO   git grep $portee : code $rc, contrôle impossible"; ko=1 ;;
  esac
done
exit "$ko"
