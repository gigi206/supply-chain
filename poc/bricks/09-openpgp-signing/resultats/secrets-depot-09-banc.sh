#!/usr/bin/env bash
# Banc de l'ajout 09 à tools/secrets-depot.sh (§4 quater d'A-REPORTER) : HOME factice, secrets inventés de même forme,
# copie détachée de HEAD dans le scratchpad. Puis un passage sous le vrai HOME, sur la copie propre : comptes seulement.
set -uo pipefail
D=/home/gigi/Documents/git/github/gigi206/supply-chain
S=/tmp/claude-1000/-home-gigi-Documents-git-github-gigi206-supply-chain/8e4ef563-ec63-44dd-b5a2-5f0729c4e8b2/scratchpad/sd09
C=$S/copie; F=$S/home
for x in "$C" "$F"; do [ ! -e "$x" ] || { echo "REFUS : $x existe"; exit 1; }; done
cd "$D" && git worktree add -q --detach "$C" HEAD </dev/null || exit 1
cp "$D/tools/secrets-depot.sh" "$C/tools/secrets-depot.sh"
ok=0; ko=0
verdict() { if [ "$1" = "$2" ]; then echo "OK   $3"; ok=$((ok+1)); else echo "KO   $3 (attendu $2, vu $1)"; ko=$((ko+1)); fi; }
# secrets inventés
Z=$F/.cache/supply-chain-poc/09/secrets; mkdir -p "$Z/zot-poc-lien-docker" "$F/.cache/supply-chain-poc/08/secrets"
openssl rand -hex 24 > "$F/.cache/supply-chain-poc/08/secrets/factice-08"
armure() { echo "-----BEGIN $1-----"; echo; for i in 1 2 3 4; do openssl rand -base64 48; done; echo "=Ab1z"; echo "-----END $1-----"; }
armure "PGP PRIVATE KEY BLOCK" > "$Z/cle-openpgp.asc"; armure "PGP PUBLIC KEY BLOCK" > "$Z/revocation.asc"; armure "PGP PUBLIC KEY BLOCK" > "$Z/cle-publique.asc"
openssl rand -base64 19 | cut -c1-26 > "$Z/openbao-lien.secret"; openssl rand -hex 24 > "$Z/zot-poc-lien.password"
A=$({ printf 'poc-lien:'; tr -d '\n' < "$Z/zot-poc-lien.password"; } | base64 -w0)
printf '{"auths":{"registre:5000":{"auth":"%s"}}}\n' "$A" > "$Z/zot-poc-lien-docker/config.json"
cd "$C"
cas() {  # nom attendu(OK|KO) contenu...
  local nom=$1 att=$2; shift 2
  printf '%s\n' "$@" > "$C/essai-banc.txt"
  local o r=0; o=$(HOME=$F tools/secrets-depot.sh </dev/null 2>&1) || r=$?
  rm -f -- "$C/essai-banc.txt"
  if [ "$att" = OK ]; then verdict "$r" 0 "$nom : accepté"; else verdict "$([ "$r" -ne 0 ] && echo refus)" refus "$nom : refusé"; fi
  printf '%s\n' "$o" | grep '^KO' | sed 's/^/     /'
}
cas "rien de secret" OK "ligne ordinaire"
cas "ligne de la clé privée" KO "$(sed -n 3p "$Z/cle-openpgp.asc")"
cas "ligne du certificat de révocation" KO "x $(sed -n 4p "$Z/revocation.asc") y"
cas "secret openbao-lien" KO "secret: $(cat "$Z/openbao-lien.secret")"
cas "mot de passe de poc-lien" KO "$(cat "$Z/zot-poc-lien.password")"
cas "auth de poc-lien seule" KO "\"auth\": \"$A\""
cas "config.json de poc-lien copié" KO "$(cat "$Z/zot-poc-lien-docker/config.json")"
cas "ligne de la clé publique" OK "$(sed -n 3p "$Z/cle-publique.asc")"
cas "ligne courte de l'armure (=Ab1z)" OK "texte =Ab1z texte"
cas "en-tête OpenPGP privé seul" KO "-----BEGIN PGP PRIVATE KEY BLOCK-----"
cas "en-tête cosign seul" KO "-----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----"
cas "en-tête OpenSSH seul" KO "-----BEGIN OPENSSH PRIVATE KEY-----"
cas "en-tête cité dans une phrase" OK "la ligne \`-----BEGIN PGP PRIVATE KEY BLOCK-----\` entre accents graves"
cas "en-tête de clé publique seul" OK "-----BEGIN PGP PUBLIC KEY BLOCK-----"
# l'ancien script ne voit pas la 09 : écart attendu
printf '%s\n' "$(cat "$Z/zot-poc-lien.password")" > "$C/essai-banc.txt"
git -C "$C" show HEAD:tools/secrets-depot.sh > "$C/tools/ancien-banc.sh"
r=0; HOME=$F bash "$C/tools/ancien-banc.sh" </dev/null >/dev/null 2>&1 || r=$?
rm -f -- "$C/essai-banc.txt" "$C/tools/ancien-banc.sh"
verdict "$r" 0 "script actuel du dépôt : mot de passe de poc-lien NON vu (écart que l'ajout comble)"
# HOME factice sans 09 : rien ne change pour 08
mv "$F/.cache/supply-chain-poc/09" "$F/.cache/supply-chain-poc/09-cache"
o=$(HOME=$F tools/secrets-depot.sh </dev/null 2>&1); r=$?
verdict "$r" 0 "sans dossier 09 : OK"
verdict "$(printf '%s\n' "$o" | sed -n 's/^fichiers : [0-9]* ; motifs : \([0-9]*\)$/\1/p')" 1 "sans dossier 09 : 1 motif (08)"
mv "$F/.cache/supply-chain-poc/09-cache" "$F/.cache/supply-chain-poc/09"
find "$F" -type f -delete; find "$F" -depth -type d -empty -delete
verdict "$([ -e "$F" ] && echo reste || echo parti)" parti "HOME factice effacé"
# vrai HOME, copie propre : comptes seulement
o=$(tools/secrets-depot.sh </dev/null 2>&1); r=$?
verdict "$r" 0 "vrai HOME, copie propre : OK"
m=$(printf '%s\n' "$o" | sed -n 's/^fichiers : [0-9]* ; motifs : \([0-9]*\)$/\1/p')
git -C "$C" show HEAD:tools/secrets-depot.sh > "$C/tools/ancien-banc.sh"; m0=$(bash "$C/tools/ancien-banc.sh" </dev/null 2>&1 | sed -n 's/^fichiers : [0-9]* ; motifs : \([0-9]*\)$/\1/p')
rm -f -- "$C/tools/ancien-banc.sh"; verdict "$((m - m0))" 5 "vrai HOME : 5 motifs de plus (4 fichiers nommés + auth dérivée)"
cd "$D" && git worktree remove --force "$C" </dev/null && git worktree prune </dev/null
verdict "$([ -e "$C" ] && echo reste || echo parti)" parti "copie retirée"
echo "# bilan : OK $ok ; KO $ko"
[ "$ko" = 0 ]
