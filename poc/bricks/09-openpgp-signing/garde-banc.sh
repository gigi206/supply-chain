#!/usr/bin/env bash
# Brique 09 : banc de garde-cle-privee.sh, sur l'hôte, sans réseau ni installation. Clé jetable ed25519 (identité fictive, sans
# adresse, sans phrase de passe, 1 jour) créée par le gpg de l'hôte dans un GNUPGHOME sur tmpfs, exportée armurée par -o sous
# umask 077 dans une copie superficielle de la branche (clone file://, hors du dépôt). Cas GB0 à GB12 : voir
# resultats/garde-predictions.md. Journal : resultats/garde-banc.log ; aucune ligne de clé n'y est écrite (GB11).
set -uo pipefail
umask 077
here=$(cd "$(dirname "$0")" && pwd)
L=$here/resultats/garde-banc.log
C09=$HOME/.cache/supply-chain-poc/09
D=$C09/garde-banc
G=$XDG_RUNTIME_DIR/o9-garde-gnupg
B=poc/bricks/09-openpgp-signing
GARDE=$here/garde-cle-privee.sh
[ -e "$D" ] || [ -e "$G" ] && { echo "KO   $D ou $G existe déjà : rien lancé"; exit 1; }
cas() {   # cas NOM CODE_ATTENDU [ARBRE] : lance la garde, compare le code
  local nom=$1 attendu=$2 sortie rc
  sortie=$("$GARDE" "${3:-$D}"); rc=$?
  printf '%s\n' "$sortie" | sed 's/^/     | /'
  [ "$rc" = "$attendu" ] && echo "OK   $nom : code $rc (attendu $attendu)" || echo "KO   $nom : code $rc (attendu $attendu)"
}
{
  echo "banc de la garde commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; garde sha256 $(sha256sum < "$GARDE" | cut -c1-16)… ; banc sha256 $(sha256sum < "$here/garde-banc.sh" | cut -c1-16)… ; $(git --version) ; $(gpg --version | head -1)"
  t=$(stat -f -c %T "$XDG_RUNTIME_DIR")
  [ "$t" = tmpfs ] && echo "OK   GB0 : $XDG_RUNTIME_DIR est un tmpfs" || { echo "KO   GB0 : $XDG_RUNTIME_DIR est $t : arrêt"; exit 1; }

  echo "## GB1 : arbre réel de la branche"
  cas GB1 0 "$here"

  echo "## copie superficielle et clé jetable"
  git clone -q --depth 1 --single-branch --branch "$(git -C "$here" rev-parse --abbrev-ref HEAD)" "file://$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)" "$D" \
    && echo "copie : $(git -C "$D" rev-parse --short HEAD), $(git -C "$D" ls-files | wc -l) fichiers suivis" || { echo "KO   clone : arrêt"; exit 1; }
  mkdir -m 700 "$G"
  printf '%s\n' '%no-protection' 'Key-Type: eddsa' 'Key-Curve: ed25519' 'Key-Usage: sign' 'Name-Real: Banc garde brique 09' \
    'Name-Comment: cle jetable sans adresse' 'Expire-Date: 1d' '%commit' > "$G/parametres"
  gpg --homedir "$G" --batch --gen-key "$G/parametres" 2>&1 | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/^/     gpg : /'
  gpg --homedir "$G" --batch --pinentry-mode loopback --armor -o "$G/fuite.asc" --export-secret-keys 2>&1 | sed 's/^/     gpg : /'
  gpg --homedir "$G" --batch --armor -o "$G/publique.asc" --export 2>&1 | sed 's/^/     gpg : /'
  echo "export privé : $(wc -l < "$G/fuite.asc") lignes, mode $(stat -c %a "$G/fuite.asc") ; export public : $(wc -l < "$G/publique.asc") lignes"

  echo "## GB2 : copie propre"
  cas GB2 0
  echo "## GB3 : clé privée en fichier non suivi"
  cp -- "$G/fuite.asc" "$D/$B/fuite.asc"
  cas GB3 1
  echo "## GB4 : même fichier ajouté à l'index"
  git -C "$D" add -- "$B/fuite.asc"
  cas GB4 1
  echo "## GB5 : dans l'index seulement (fichier retiré de l'arbre de travail)"
  ( cd "$D/$B" && rm -- fuite.asc )
  cas GB5 1
  git -C "$D" rm -q --cached -- "$B/fuite.asc"
  echo "## GB6 : clé indentée de quatre espaces à la fin d'un fichier suivi"
  sed 's/^/    /' "$G/fuite.asc" >> "$D/$B/README.md"
  cas GB6 1
  git -C "$D" checkout -q -- "$B/README.md"
  echo "## GB7 : clé avec fins de ligne CRLF"
  sed 's/$/\r/' "$G/fuite.asc" > "$D/$B/fuite-crlf.asc"
  cas GB7 1
  ( cd "$D/$B" && rm -- fuite-crlf.asc )
  echo "## GB8 : clé publique seule"
  cp -- "$G/publique.asc" "$D/$B/cle-publique.asc"
  cas GB8 0
  ( cd "$D/$B" && rm -- cle-publique.asc )
  echo "## GB9 : clé privée dans un dossier ignoré (limite attendue : non lue)"
  mkdir -p "$D/$B/__pycache__"
  cp -- "$G/fuite.asc" "$D/$B/__pycache__/fuite.asc"
  echo "     check-ignore : $(git -C "$D" check-ignore -- "$B/__pycache__/fuite.asc" || echo 'non ignoré')"
  cas GB9 0
  ( cd "$D/$B" && rm -r -- __pycache__ )
  echo "## GB10 : arbre qui n'est pas un dépôt git"
  cas GB10 1 "$G"

  echo "## GB11b : aucune ligne de la clé privée jetable dans le journal (lignes de 16 caractères ou plus, en-têtes exclus)"
  grep -v -e '^-----' "$G/fuite.asc" | awk 'length($0) >= 16' > "$G/motifs"
  m=$(wc -l < "$G/motifs"); n=$(grep -c -F -f "$G/motifs" "$L" || true)
  [ "$m" -gt 0 ] && [ "$n" = 0 ] && echo "OK   GB11b : $m motifs, 0 ligne du journal" || echo "KO   GB11b : $m motifs, $n ligne(s) du journal"
  echo "## GB12 : effacement"
  gpgconf --homedir "$G" --kill all
  ( cd "$XDG_RUNTIME_DIR" && rm -r -- o9-garde-gnupg )
  ( cd "$C09" && rm -r --one-file-system -- garde-banc )
  [ ! -e "$G" ] && [ ! -e "$D" ] && echo "OK   GB12 : GNUPGHOME et copie effacés" || echo "KO   GB12 : reste $(ls -d "$G" "$D" 2>/dev/null | paste -sd' ')"
  echo "banc de la garde fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "$L" 2>&1
n=$(grep -c 'BEGIN PGP' "$L" || true)
if grep -q '^KO   GB11b' "$L"; then : > "$L"; echo "KO   GB11b : ligne de clé dans le journal : journal vidé" >> "$L"
elif [ "$n" = 0 ]; then echo "OK   GB11 (K3) : aucun « BEGIN PGP » dans le journal" >> "$L"; else : > "$L"; echo "KO   GB11 (K3) : $n ligne(s) « BEGIN PGP » : journal vidé" >> "$L"; fi
cat "$L"
! grep -q '^KO' "$L"
