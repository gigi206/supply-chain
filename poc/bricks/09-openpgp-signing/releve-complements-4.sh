#!/usr/bin/env bash
# Brique 09 : quatrième complément, en lecture publique, écrit après la relecture finale du conseiller (19/11/2026).
# 1. Portée de « sha1.second_preimage_resistance » dans la politique de Sequoia (sequoia-policy-config, branche main, ref mobile ;
#    sequoia-openpgp au tag openpgp/v2.4.2) : la ligne de default-sequoia.config d'apt vise-t-elle les signatures de données ?
# 2. Ce que la pipeline S4d de la brique 06 publie : .changes et .buildinfo dans la couche, ou dans le journal seulement.
# Lecture sur la sortie standard, rien n'est écrit sur disque hors du journal : resultats/releve-complements-4.log.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
S4D=$here/../06-deb-sbuild/resultats/s4d-pipeline.log
cd "$HOME/.cache/supply-chain-poc/09"
{
  set +e
  echo "quatrième complément commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo; echo "## 1. sequoia-policy-config (main) : README, lignes citant second_preimage, collision, sha1"
  curl -fsSL --max-time 30 https://gitlab.com/sequoia-pgp/sequoia-policy-config/-/raw/main/README.md \
    | grep -n -iE 'second_preimage|collision|sha1|hash_algorithms' | head -30 | sed 's/^/  /'
  echo "## sequoia-openpgp, tag openpgp/v2.4.2, openpgp/src/policy.rs : commentaires sur les deux propriétés"
  curl -fsSL --max-time 30 "https://gitlab.com/sequoia-pgp/sequoia/-/raw/openpgp/v2.4.2/openpgp/src/policy.rs" \
    | grep -n -E '^\s*///.*(SecondPreImageResistance|CollisionResistance|second pre-image|collision resistance|self-signature|attacker)' | head -30 | sed 's/^/  /'
  echo "## même fichier : seuils par défaut de SHA1 (lignes citant SHA1 et une date ou un cutoff)"
  curl -fsSL --max-time 30 "https://gitlab.com/sequoia-pgp/sequoia/-/raw/openpgp/v2.4.2/openpgp/src/policy.rs" \
    | grep -n -E 'SHA1' | head -20 | sed 's/^/  /'
  echo; echo "## 2. Brique 06, journal S4d ($S4D) : couche publiée et fichiers cités"
  grep -n -E 'couche sha256|membre|deb produit|\.changes|\.buildinfo -----' "$S4D" | head -12 | sed 's/^/  /'
  echo "  lignes citant .changes : $(grep -c '\.changes' "$S4D")"
  echo "quatrième complément fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g' | tee "$R/releve-complements-4.log"
