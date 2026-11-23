#!/usr/bin/env bash
# Brique 07b, intégration au rejeu de zéro (23/11/2026, choix du propriétaire « Automatique au rejeu ») : banc du mode REJEU de
# vex-openbao.sh, tel qu'il est dans HEAD (lu par git show, jamais l'arbre de travail). Même montage que 07b-p2-pose-banc.sh :
# OpenBao 2.7.2 jetable en -dev -dev-tls dans un espace de noms réseau vide (unshare -rn), clés chains, scanner, tsa et lien et
# kv/scan/zot créées d'abord, faux kubectl (exec local). Rien de partagé : ni cluster, ni Zot, ni VM, ni secrets du PoC ; le mot
# de passe est un aléa du banc dans un fichier 0600, jamais affiché.
# Cas : cle_vex en REJEU avec un .pem et un journal de pose déjà là (pem remplacé, journal de pose intact, journal du rejeu à
# part) ; même REJEU relancé (refus : journal présent) ; autre REJEU (refus : clé vex présente) ; acces_vex REJEU avec
# MDP_FICHIER en 0644 (refus), puis en 0600 (utilisateur créé) ; connexion avec ce fichier ; mot de passe absent du journal ;
# acces_vex sans REJEU et sans terminal (refus, comme avant) ; essai en REJEU (refus) ; fonction vex07b de rejeu.sh (code d'un
# échec propagé par pipefail).
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/resultats/07b-rejeu-vex-banc.sh > <journal>
set -uo pipefail
export LC_ALL=C
KO=0
ok() { echo "OK   $1"; }
ko() { echo "KO   $1"; KO=$((KO + 1)); }
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; KO=$((KO + 1)); fi; }

if [ "${1:-}" = ns ]; then
  ip link set lo up
  B=$T/arbre/poc/bricks/07a-sbom-grype
  S=$B/vex-openbao.sh
  BANC=$T/b
  A=https://127.0.0.1:18200
  mkdir -p "$T/bao-home" "$T/proprio" "$BANC/resultats" "$BANC/bin" "$BANC/tls" "$T/pod" "$T/sorties"
  (umask 077 && mkdir -p "$BANC/secrets" "$T/mdp" "$T/tls-dev")
  HOME=$T/bao-home "$BAO" server -dev -dev-tls -dev-tls-cert-dir="$T/tls-dev" -dev-listen-address=127.0.0.1:18200 > "$T/bao.out" 2>&1 & bp=$!
  # shellcheck disable=SC2064
  trap "kill $bp 2>/dev/null || true" EXIT
  for _ in $(seq 60); do [ -s "$T/tls-dev/vault-ca.pem" ] && [ -s "$T/bao-home/.vault-token" ] && break; sleep 0.25; done
  cp "$T/tls-dev/vault-ca.pem" "$BANC/tls/vault-ca.pem"
  (umask 077 && cp "$T/bao-home/.vault-token" "$BANC/secrets/openbao-root.token")
  rb() { HOME=$T/bao-home BAO_ADDR=$A BAO_CACERT=$BANC/tls/vault-ca.pem "$BAO" "$@"; }
  for _ in $(seq 40); do rb status > /dev/null 2>&1 && break; sleep 0.25; done
  attendu "OpenBao jetable en TLS : version, scellé" "$(rb status -format=json | jq -r '"\(.version) \(.sealed)"')" "2.7.2 false"
  rb secrets enable transit > /dev/null
  for k in chains scanner tsa lien; do rb write -f "transit/keys/$k" type=ecdsa-p256 exportable=false allow_plaintext_backup=false > /dev/null; done
  rb secrets enable -path=kv -version=1 kv > /dev/null
  printf '{"auths":{}}' | rb write kv/scan/zot config.json=- > /dev/null
  ln -s "$BAO" "$T/pod/bao"
  cat > "$BANC/bin/kubectl" <<FIN
#!/usr/bin/env bash
case "\$1" in
  exec)
    [ "\$2 \$3 \$4 \$5 \$6" = "-i -n openbao openbao-0 --" ] || { echo "faux kubectl : appel inattendu : \$*" >&2; exit 9; }
    shift 6
    exec env BAO_ADDR=$A BAO_CACERT=$BANC/tls/vault-ca.pem HOME=$T/pod PATH=$T/pod:\$PATH "\$@" ;;
  *) echo "faux kubectl : appel inattendu : \$*" >&2; exit 9 ;;
esac
FIN
  chmod +x "$BANC/bin/kubectl"
  (umask 077; m=$(head -c 18 /dev/urandom | base64); printf '%s' "$m" > "$T/mdp/proprietaire"; m=)
  cp "$T/mdp/proprietaire" "$T/mdp/ouvert"; chmod 644 "$T/mdp/ouvert"
  spki() { openssl pkey -pubin -in "$1" -outform DER 2>/dev/null | sha256sum | cut -c1-64; }
  lancer() { # cas étape [VAR=valeur…] : sortie gardée ; rend le code
    local cas=$1 e=$2 c=0; shift 2
    env BANC="$BANC" "$@" bash "$S" "$e" > "$T/sorties/$cas.out" 2>&1 < /dev/null || c=$?
    echo "## cas $cas (vex-openbao.sh $e, $*) : code $c" >&2
    sed 's/^/    > /' "$T/sorties/$cas.out" >&2
    echo "$c"
  }
  exec 2>&1

  echo "## 1. cle_vex en REJEU, avec un .pem et un journal de pose déjà présents"
  rb write -f transit/keys/ancienne type=ecdsa-p256 > /dev/null
  rb read -format=json transit/keys/ancienne | jq -j '.data.keys["1"].public_key' > "$BANC/resultats/vex-cle-publique.pem"
  rb delete transit/keys/ancienne > /dev/null 2>&1 || true
  s0=$(spki "$BANC/resultats/vex-cle-publique.pem")
  printf 'journal de la pose du 22/11 (témoin)\n' > "$BANC/resultats/vex-openbao-cle_vex.log"; j0=$(sha256sum < "$BANC/resultats/vex-openbao-cle_vex.log")
  c=$(lancer rejeu1 cle_vex REJEU=banc1)
  attendu "cle_vex REJEU=banc1 : code" "$c" 0
  attendu "journal du rejeu à part" "$(test -s "$BANC/resultats/vex-openbao-cle_vex-rejeu-banc1.log" && echo présent)" présent
  attendu "journal de la pose intact" "$(sha256sum < "$BANC/resultats/vex-openbao-cle_vex.log")" "$j0"
  s1=$(spki "$BANC/resultats/vex-cle-publique.pem")
  attendu ".pem remplacé (SPKI différente de l'ancienne)" "$([ -n "$s1" ] && [ "$s1" != "$s0" ] && echo oui)" oui
  attendu ".pem = clé publique de transit/keys/vex" "$s1" "$(rb read -format=json transit/keys/vex | jq -j '.data.keys["1"].public_key' > "$T/vex.pem"; spki "$T/vex.pem")"
  attendu "message de remplacement au journal" "$(grep -c 'remplacé par la clé neuve' "$BANC/resultats/vex-openbao-cle_vex-rejeu-banc1.log")" 1

  echo "## 2. même REJEU relancé : refus (journal présent), .pem inchangé"
  c=$(lancer rejeu1-bis cle_vex REJEU=banc1)
  attendu "code ; refus" "$c ; $(grep -c 'REFUS : journal déjà présent' "$T/sorties/rejeu1-bis.out")" "1 ; 1"
  attendu ".pem inchangé" "$(spki "$BANC/resultats/vex-cle-publique.pem")" "$s1"

  echo "## 3. autre REJEU, clé vex déjà là : refus, .pem inchangé"
  c=$(lancer rejeu2 cle_vex REJEU=banc2)
  attendu "code non nul ; KO clé présente" "$([ "$c" != 0 ] && echo oui) ; $(grep -c 'transit/keys/vex existe déjà' "$T/sorties/rejeu2.out")" "oui ; 1"
  attendu ".pem inchangé" "$(spki "$BANC/resultats/vex-cle-publique.pem")" "$s1"

  echo "## 4. acces_vex en REJEU : fichier en 0644 refusé, puis 0600 accepté"
  c=$(lancer acces-ouvert acces_vex REJEU=banc1 MDP_FICHIER="$T/mdp/ouvert")
  attendu "0644 : code ; refus" "$c ; $(grep -c 'REFUS : MDP_FICHIER absent ou pas en 0600' "$T/sorties/acces-ouvert.out")" "1 ; 1"
  attendu "0644 : aucun journal écrit" "$(test -e "$BANC/resultats/vex-openbao-acces_vex-rejeu-banc1.log" && echo présent || echo absent)" absent
  c=$(lancer acces acces_vex REJEU=banc1 MDP_FICHIER="$T/mdp/proprietaire")
  attendu "0600 : code" "$c" 0
  # lire_mdp parle avant l'ouverture du journal (comme la saisie au terminal) : l'annonce est sur la sortie (passage 1 : KO du banc)
  attendu "0600 : lecture dans MDP_FICHIER annoncée (sortie)" "$(grep -c 'OK   mot de passe lu dans MDP_FICHIER (rejeu), 24 caractères' "$T/sorties/acces.out")" 1
  attendu "utilisateur proprietaire : politiques" "$(rb read -format=json auth/userpass/users/proprietaire | jq -r '.data.token_policies | join(",")')" vex-signature
  attendu "K6 : mot de passe absent du journal" "$(grep -c -F -f "$T/mdp/proprietaire" "$BANC/resultats/vex-openbao-acces_vex-rejeu-banc1.log")" 0
  attendu "K6 annoncé au journal" "$(grep -c '^OK   K6 : ' "$BANC/resultats/vex-openbao-acces_vex-rejeu-banc1.log")" 1
  c=0; HOME=$T/proprio BAO_ADDR=$A BAO_CACERT=$BANC/tls/vault-ca.pem "$BAO" login -method=userpass -no-store -format=json \
    username=proprietaire password=@"$T/mdp/proprietaire" > /dev/null 2>&1 < /dev/null || c=$?
  attendu "connexion userpass avec le fichier : code" "$c" 0

  echo "## 5. sans REJEU, sans terminal : refus (comportement d'avant)"
  c=$(lancer sans-rejeu acces_vex MDP_FICHIER="$T/mdp/proprietaire")
  attendu "code ; refus terminal" "$c ; $(grep -c 'REFUS : /dev/tty illisible' "$T/sorties/sans-rejeu.out")" "1 ; 1"

  echo "## 6. essai en REJEU : refus"
  c=$(lancer essai-rejeu essai REJEU=banc1 BANC_MDP_CONNEXION="$T/mdp/proprietaire")
  attendu "code ; refus" "$c ; $(grep -c 'REFUS : essai hors du rejeu' "$T/sorties/essai-rejeu.out")" "1 ; 1"

  echo "## 7. fonction vex07b de rejeu.sh (pipefail) : un échec reste un échec"
  eval "$(sed -n '/^vex07b() {/,/; }$/p' "$T/rejeu.sh" | sed "s#\"\$here/../07a-sbom-grype/vex-openbao.sh\"#env BANC=$BANC bash $S#; s#\$HOME/.cache/supply-chain-poc/07a/secrets/openbao-proprietaire.password#$T/mdp/proprietaire#")"
  set -o pipefail
  lib=banc3; c=0; vex07b cle_vex > "$T/sorties/vex07b.out" 2>&1 || c=$?
  attendu "vex07b cle_vex (clé présente) : code non nul" "$([ "$c" != 0 ] && echo oui)" oui
  attendu "vex07b : trois dernières lignes seulement" "$(wc -l < "$T/sorties/vex07b.out")" 3
  echo "$KO" > "$T/ko-ns"
  exit 0
fi

RES=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$RES" rev-parse --show-toplevel)
T=$HOME/.cache/supply-chain-poc/07a/rejeu-vex-banc
BAO=$HOME/.cache/supply-chain-poc/07a/bao-2.7.2/bao
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$TOP" rev-parse --short=12 HEAD)"
[ ! -e "$T" ] || { echo "KO   $T existe déjà"; exit 1; }
mkdir -p "$T/arbre/poc/bricks/07a-sbom-grype/politique"
attendu "bao : empreinte du binaire extrait (07b-p2-bao.log)" "$(sha256sum < "$BAO" | cut -c1-16)" 9c5f36287c673f38
git -C "$TOP" show HEAD:poc/bricks/07a-sbom-grype/vex-openbao.sh > "$T/arbre/poc/bricks/07a-sbom-grype/vex-openbao.sh"
git -C "$TOP" show HEAD:poc/bricks/07a-sbom-grype/politique/vex-signature.hcl > "$T/arbre/poc/bricks/07a-sbom-grype/politique/vex-signature.hcl"
git -C "$TOP" show HEAD:poc/bricks/08-trust-plane/rejeu.sh > "$T/rejeu.sh"
echo "HEAD : vex-openbao.sh $(sha256sum < "$T/arbre/poc/bricks/07a-sbom-grype/vex-openbao.sh" | cut -c1-16)… ; rejeu.sh $(sha256sum < "$T/rejeu.sh" | cut -c1-16)…"
T=$T BAO=$BAO unshare -rn bash "$0" ns
KO=$((KO + $(cat "$T/ko-ns" 2>/dev/null || echo 1)))
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "## bilan : $KO écart(s)"
find "$HOME/.cache/supply-chain-poc/07a/rejeu-vex-banc" -delete
[ "$KO" = 0 ]
