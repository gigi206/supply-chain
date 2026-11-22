#!/usr/bin/env bash
# Brique 07b, tranche 3, pièce 2 : banc du script de pose vex-openbao.sh, tel qu'il est dans l'arbre du patch
# (~/.cache/supply-chain-poc/07a/t3/b). Rien de partagé : ni cluster, ni Zot, ni VM, ni secrets du PoC ; aucun réseau.
# OpenBao 2.7.2 jetable (binaire extrait et vérifié par resultats/07b-p2-bao.sh) en -dev -dev-tls, dans un espace de noms réseau
# vide (unshare -rn), audit déclaré dans la configuration (passage 22). Clés chains, scanner, tsa et lien, et kv/scan/zot, créées
# d'abord pour imiter le cluster. Faux kubectl : « exec » lance la commande en local, pointée sur le serveur du banc (TLS, CA du
# banc) ; « port-forward » annonce le port du serveur. Mots de passe aléatoires du banc dans des fichiers 0600, passés au script
# par BANC_MDP et BANC_MDP_CONNEXION (lues seulement avec BANC), jamais en argument ; jamais affichés.
# Cas : releve ; cle_vex, puis relancée ; acces_vex sans terminal, saisies différentes, 11 caractères, puis conforme ; connexion
# avec le mot de passe posé par le canal du script (fichier sans saut de ligne, fichier avec saut de ligne, invite de bao sous un
# pty) ; acces_vex relancée avec un autre mot de passe (refus, ancien mot de passe toujours valable) ; fuite injectée dans une
# copie du script (journal vidé par K6) ; essai, puis relancé ; audit du banc par identité.
# Quatrième passage (chemins relevés par le conseiller) : acces_vex et essai pilotés sous un pty, avec BANC mais sans fichier de
# mot de passe (branches terminal du script) ; reprise d'acces_vex après échec partiel (politique différente : refus ; politique
# et montage déjà là : laissés) ; mot de passe de 11 caractères accentués ; essai après une connexion ratée (dossier neuf).
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/resultats/07b-p2-pose-banc.sh > <journal>
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
  mkdir -p "$T/bao-home" "$T/proprio" "$T/sorties" "$T/journaux" "$BANC/resultats" "$BANC/bin" "$BANC/tls" "$T/pod"
  (umask 077 && mkdir -p "$BANC/secrets" "$T/mdp" "$T/tls-dev")   # -dev-tls-cert-dir doit exister (premier passage)
  printf 'audit "file" "banc" {\n  options {\n    file_path = "%s"\n  }\n}\n' "$T/bao-audit.log" > "$T/bao-audit.hcl"
  HOME=$T/bao-home "$BAO" server -dev -dev-tls -dev-tls-cert-dir="$T/tls-dev" -dev-listen-address=127.0.0.1:18200 \
    -config="$T/bao-audit.hcl" > "$T/bao.out" 2>&1 & bp=$!
  # shellcheck disable=SC2064   # développement à la pose, voulu
  trap "kill $bp 2>/dev/null || true" EXIT
  for _ in $(seq 60); do [ -s "$T/tls-dev/vault-ca.pem" ] && [ -s "$T/bao-home/.vault-token" ] && break; sleep 0.25; done
  cp "$T/tls-dev/vault-ca.pem" "$BANC/tls/vault-ca.pem"
  (umask 077 && cp "$T/bao-home/.vault-token" "$BANC/secrets/openbao-root.token")
  rb() { HOME=$T/bao-home BAO_ADDR=$A BAO_CACERT=$BANC/tls/vault-ca.pem "$BAO" "$@"; }   # racine du banc
  for _ in $(seq 40); do rb status > /dev/null 2>&1 && break; sleep 0.25; done
  attendu "OpenBao jetable en TLS : version, scellé" "$(rb status -format=json | jq -r '"\(.version) \(.sealed)"')" "2.7.2 false"
  attendu "audit déclaratif du banc" "$(rb audit list -format=json | jq -r 'to_entries[] | "\(.key) \(.value.type)"' | paste -sd, -)" "banc/ file"
  rb secrets enable transit > /dev/null
  for k in chains scanner tsa lien; do rb write -f "transit/keys/$k" type=ecdsa-p256 exportable=false allow_plaintext_backup=false > /dev/null; done
  rb secrets enable -path=kv -version=1 kv > /dev/null
  printf '{"auths":{}}' | rb write kv/scan/zot config.json=- > /dev/null
  attendu "cluster imité : clés Transit, montages kv" "$(rb list -format=json transit/keys | jq -r 'join(",")') ; $(rb secrets list -format=json | jq -r 'keys | map(select(. == "kv/" or . == "transit/")) | join(",")')" \
    "chains,lien,scanner,tsa ; kv/,transit/"
  # faux kubectl (appels contrôlés) et cosign réel ; bao du « pod » = même binaire
  ln -s "$BAO" "$T/pod/bao"
  ln -s "$COSIGN" "$BANC/bin/cosign"
  cat > "$BANC/bin/kubectl" <<FIN
#!/usr/bin/env bash
echo "\$*" | cut -c1-60 >> "$T/appels"
case "\$1" in
  exec)
    [ "\$2 \$3 \$4 \$5 \$6" = "-i -n openbao openbao-0 --" ] || { echo "faux kubectl : appel inattendu : \$*" >&2; exit 9; }
    shift 6
    exec env BAO_ADDR=$A BAO_CACERT=$BANC/tls/vault-ca.pem HOME=$T/pod PATH=$T/pod:\$PATH "\$@" ;;
  port-forward)
    [ "\$*" = "port-forward -n openbao pod/openbao-0 --address 127.0.0.1 :8200" ] || { echo "faux kubectl : appel inattendu : \$*" >&2; exit 9; }
    echo "Forwarding from 127.0.0.1:18200 -> 8200"; exec sleep 600 ;;
  *) echo "faux kubectl : appel inattendu : \$*" >&2; exit 9 ;;
esac
FIN
  chmod +x "$BANC/bin/kubectl"
  # mots de passe du banc : 24 caractères aléatoires (base64 de 18 octets), sans saut de ligne dans les fichiers de connexion
  m1=$(head -c 18 /dev/urandom | base64); m2=$(head -c 18 /dev/urandom | base64); m3=$(head -c 18 /dev/urandom | base64)
  (umask 077
    printf '%s\n%s\n' "$m1" "$m1" > "$T/mdp/deux"; printf '%s\n%s\n' "$m1" "$m2" > "$T/mdp/differents"
    printf '%s\n%s\n' "${m1:0:11}" "${m1:0:11}" > "$T/mdp/court"; printf '%s\n%s\n' "$m2" "$m2" > "$T/mdp/autre-deux"
    printf '%s' "$m1" > "$T/mdp/connexion"; printf '%s\n' "$m1" > "$T/mdp/connexion-nl"; printf '%s' "$m2" > "$T/mdp/autre"
    printf '%s' "$m3" > "$T/mdp/troisieme"; printf '%s\n%s\n' "éééééééééé1" "éééééééééé1" > "$T/mdp/court-accentue")
  m1=; m2=; m3=

  lancer() { # cas étape [VAR=valeur…] : script du patch avec BANC ; sortie et journal copiés ; rend le code
    local cas=$1 e=$2 c=0; shift 2
    : > "$BANC/resultats/vex-openbao-$e.log"
    if [ -n "${PTY_MOTIFS:-}" ]; then   # quatrième passage : terminal piloté ; résumé du pty, puis journal de l'étape
      env BANC="$BANC" "$@" python3 -I "$T/pty.py" "$PTY_MDP" "$PTY_MOTIFS" -- bash "${SCRIPT:-$S}" "$e" > "$T/sorties/$cas.out" 2>&1 < /dev/null || c=$?
      cat "$BANC/resultats/vex-openbao-$e.log" >> "$T/sorties/$cas.out"
    else
      env BANC="$BANC" "$@" bash "${SCRIPT:-$S}" "$e" > "$T/sorties/$cas.out" 2>&1 < /dev/null || c=$?
    fi
    cp "$BANC/resultats/vex-openbao-$e.log" "$T/journaux/$cas.log"
    echo "## cas $cas (vex-openbao.sh $e) : code $c" >&2
    sed 's/^/    > /' "$T/sorties/$cas.out" >&2
    echo "$c"
  }
  n() { grep -c -F -- "$2" "$T/sorties/$1.out"; }
  nko() { grep -c '^KO' "$T/sorties/$1.out"; }
  connexion() { # fichier du mot de passe : code de bao login -method=userpass -no-store (sortie jetée)
    local c=0
    HOME=$T/proprio BAO_ADDR=$A BAO_CACERT=$BANC/tls/vault-ca.pem "$BAO" login -method=userpass -no-store -format=json \
      username=proprietaire password=@"$1" > /dev/null 2>&1 < /dev/null || c=$?
    echo "code $c"
  }
  politiques() { rb policy list -format=json | jq -r 'sort | join(",")'; }   # ordre d'OpenBao non trié (deuxième passage)
  methodes() { rb auth list -format=json | jq -r 'keys | join(",")'; }
  exec 2>&1

  echo "## 1. releve"
  c=$(lancer releve releve)
  attendu "releve : code ; vex, clé publique, politique, userpass absents ; KO" \
    "code $c ; $(n releve 'OK   transit/keys/vex absente') $(n releve 'vex-cle-publique.pem absent') $(n releve 'OK   politique vex-signature absente') $(n releve 'OK   montage userpass/ absent') ; $(nko releve)" \
    "code 0 ; 1 1 1 1 ; 0"

  echo "## 2. cle_vex"
  c=$(lancer cle_vex cle_vex)
  attendu "cle_vex : code ; clé conforme ; seule différence ; KO" \
    "code $c ; $(n cle_vex 'OK   clé vex (type, exportable, sauvegarde en clair, suppression, version, signature) : ecdsa-p256,false,false,false,1,true') $(n cle_vex 'OK   seule différence : transit/keys/vex ajoutée') ; $(nko cle_vex)" \
    "code 0 ; 1 1 ; 0"
  attendu "clé publique archivée : courbe ; SPKI égal à celui lu par la racine du banc" \
    "$(openssl pkey -pubin -in "$BANC/resultats/vex-cle-publique.pem" -noout -text | sed -n 's/^NIST CURVE: //p') ; $(cmp -s <(openssl pkey -pubin -in "$BANC/resultats/vex-cle-publique.pem" -outform DER | sha256sum) <(rb read -format=json transit/keys/vex | jq -j '.data.keys["1"].public_key' | openssl pkey -pubin -outform DER | sha256sum) && echo égal || echo différent)" \
    "P-256 ; égal"
  c=$(lancer cle_vex-relance cle_vex)
  attendu "cle_vex relancée : code ; refus « existe déjà » ; clés Transit" \
    "code $c ; $(n cle_vex-relance "existe déjà : rien n'est écrasé") ; $(rb list -format=json transit/keys | jq -r 'join(",")')" "code 1 ; 1 ; chains,lien,scanner,tsa,vex"

  echo "## 3. acces_vex refusée avant toute écriture"
  p0=$(politiques); m0=$(methodes)
  c=$(lancer sans-terminal acces_vex)
  attendu "acces_vex sans terminal : code ; refus" "code $c ; $(n sans-terminal 'REFUS : /dev/tty illisible')" "code 1 ; 1"
  c=$(lancer differents acces_vex BANC_MDP="$T/mdp/differents")
  attendu "acces_vex, saisies différentes : code ; refus" "code $c ; $(n differents 'REFUS : les deux saisies diffèrent')" "code 1 ; 1"
  c=$(lancer court acces_vex BANC_MDP="$T/mdp/court")
  attendu "acces_vex, 11 caractères : code ; refus" "code $c ; $(n court 'REFUS : mot de passe de moins de 12 caractères')" "code 1 ; 1"
  c=$(lancer court-accentue acces_vex BANC_MDP="$T/mdp/court-accentue")
  attendu "acces_vex, 11 caractères accentués ($(head -1 "$T/mdp/court-accentue" | tr -d '\n' | wc -c) octets) : code ; refus" \
    "code $c ; $(n court-accentue 'REFUS : mot de passe de moins de 12 caractères')" "code 1 ; 1"
  attendu "après les quatre refus : politiques et méthodes inchangées ; aucun journal d'acces_vex" \
    "$([ "$(politiques)" = "$p0" ] && [ "$(methodes)" = "$m0" ] && echo inchangées || echo changées) ; $(cat "$T/journaux/sans-terminal.log" "$T/journaux/differents.log" "$T/journaux/court.log" "$T/journaux/court-accentue.log" | grep -c .)" "inchangées ; 0"

  echo "## 4. acces_vex conforme"
  c=$(lancer acces_vex acces_vex BANC_MDP="$T/mdp/deux")
  attendu "acces_vex : code ; politique relue ; utilisateur ; seules différences ; K4 ; K6 ; KO" \
    "code $c ; $(n acces_vex 'OK   politique vex-signature relue = ') $(n acces_vex 'OK   utilisateur proprietaire (politiques, sans default, durée, durée maximale) : vex-signature,true,900,900') $(n acces_vex 'OK   politiques : seule vex-signature ajoutée') $(n acces_vex "OK   méthodes d'authentification : seul userpass/ ajouté") ; $(n acces_vex 'OK   K4 : ') ; $(n acces_vex 'OK   K6 : ') ; $(nko acces_vex)" \
    "code 0 ; 1 1 1 1 ; 1 ; 1 ; 0"
  attendu "politiques et méthodes du banc après acces_vex" "$(politiques) ; $(methodes)" "default,root,vex-signature ; token/,userpass/"
  attendu "mot de passe absent de la sortie et du journal d'acces_vex" \
    "$(head -1 "$T/mdp/deux" | tr -d '\n' | grep -h -c -F -f - "$T/sorties/acces_vex.out" "$T/journaux/acces_vex.log" | awk '{s += $1} END {print s}')" 0

  echo "## 5. connexion avec le mot de passe posé par le canal du script"
  attendu "connexion, fichier sans saut de ligne final" "$(connexion "$T/mdp/connexion")" "code 0"
  attendu "connexion, fichier avec saut de ligne final" "$(connexion "$T/mdp/connexion-nl")" "code 2"
  cat > "$T/pty.py" <<'PY'
# pty.py <fichier du mot de passe> <motif1|motif2…> -- commande… : répond le mot de passe (suivi de \r) à chaque invite, dans
# l'ordre, 0,5 s après l'avoir vue ; n'affiche que le résumé (jamais la sortie de la commande) ; sort avec le code de la commande
import os, pty, select, sys, time
mdp = open(sys.argv[1], "rb").read()
motifs = [m.encode() for m in sys.argv[2].split("|")]
cmd = sys.argv[sys.argv.index("--") + 1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
vu, tout, k = b"", b"", 0
while True:
    r, _, _ = select.select([fd], [], [], 60)
    if not r:
        break
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    tout += d
    vu += d
    if k < len(motifs) and motifs[k] in vu:
        time.sleep(0.5)
        os.write(fd, mdp + b"\r")
        k, vu = k + 1, b""
_, st = os.waitpid(pid, 0)
c = os.waitstatus_to_exitcode(st)
print("pty : code", c, "; invites vues", k, "; échos du mot de passe", tout.count(mdp))
sys.exit(c if 0 <= c < 256 else 1)
PY
  attendu "connexion par l'invite de bao sous un pty (canal du propriétaire)" \
    "$(HOME=$T/proprio BAO_ADDR=$A BAO_CACERT=$BANC/tls/vault-ca.pem python3 -I "$T/pty.py" "$T/mdp/connexion" Password -- "$BAO" login -method=userpass -no-store -format=json username=proprietaire)" \
    "pty : code 0 ; invites vues 1 ; échos du mot de passe 0"
  attendu "rien écrit dans le HOME des connexions" "$(find "$T/proprio" -type f | grep -c .)" 0

  echo "## 6. acces_vex relancée avec un autre mot de passe"
  c=$(lancer relance acces_vex BANC_MDP="$T/mdp/autre-deux")
  attendu "acces_vex relancée : code ; refus « déjà présent »" "code $c ; $(n relance 'KO   utilisateur proprietaire déjà présent : aucune écriture')" "code 1 ; 1"
  attendu "après la relance : premier mot de passe ; autre mot de passe" "$(connexion "$T/mdp/connexion") ; $(connexion "$T/mdp/autre")" "code 0 ; code 2"

  echo "## 7. fuite injectée (copie du script) : K6 vide le journal"
  sed 's/^  \[ -n "\$MDP" \] || { ko "mot de passe absent"; return 1; }$/  echo "fuite : $MDP"\n&/' "$S" > "$B/vex-openbao-fuite.sh"
  attendu "copie : une ligne de fuite injectée" "$(diff "$S" "$B/vex-openbao-fuite.sh" | grep -c '^> ')" 1
  c=$(SCRIPT=$B/vex-openbao-fuite.sh lancer fuite acces_vex BANC_MDP="$T/mdp/deux")
  attendu "fuite : code ; journal réduit à la ligne K6 ; mot de passe absent de la sortie" \
    "code $c ; $(grep -c . "$T/journaux/fuite.log") $(grep -c '^KO   K6 : valeur du mot de passe dans le journal : journal vidé$' "$T/journaux/fuite.log") ; $(head -1 "$T/mdp/deux" | tr -d '\n' | grep -c -F -f - "$T/sorties/fuite.out")" \
    "code 1 ; 1 1 ; 0"

  echo "## 7b. reprise d'acces_vex après échec partiel (quatrième passage)"
  sc() { grep -v -e '^#' -e '^[[:space:]]*$' | sha256sum | cut -c1-16; }
  rb delete auth/userpass/users/proprietaire > /dev/null
  { cat "$B/politique/vex-signature.hcl"; printf 'path "transit/keys/scanner" {\n  capabilities = ["read"]\n}\n'; } | rb policy write vex-signature - > /dev/null
  hm=$(rb policy read vex-signature | sc)
  c=$(lancer differente acces_vex BANC_MDP="$T/mdp/deux")
  attendu "politique différente dans OpenBao, utilisateur absent : code ; refus ; utilisateur ; politique" \
    "code $c ; $(n differente 'KO   politique vex-signature présente et différente du fichier : aucune écriture') ; $(rb read auth/userpass/users/proprietaire > /dev/null 2>&1 && echo présent || echo absent) ; $([ "$(rb policy read vex-signature | sc)" = "$hm" ] && echo inchangée || echo changée)" \
    "code 1 ; 1 ; absent ; inchangée"
  rb policy write vex-signature "$B/politique/vex-signature.hcl" > /dev/null
  c=$(PTY_MDP=$T/mdp/troisieme PTY_MOTIFS='sans écho|une seconde fois' lancer reprise-pty acces_vex)
  attendu "reprise sous pty (deux invites) : code ; pty ; laissée ; laissé ; utilisateur ; K6 ; KO" \
    "code $c ; $(sed -n 1p "$T/sorties/reprise-pty.out") ; $(n reprise-pty 'OK   politique vex-signature déjà présente et identique au fichier : laissée') $(n reprise-pty 'OK   montage userpass/ déjà présent : laissé') $(n reprise-pty 'OK   utilisateur proprietaire (politiques, sans default, durée, durée maximale) : vex-signature,true,900,900') ; $(n reprise-pty 'OK   K6 : ') ; $(nko reprise-pty)" \
    "code 0 ; pty : code 0 ; invites vues 2 ; échos du mot de passe 0 ; 1 1 1 ; 1 ; 0"
  attendu "après la reprise : troisième mot de passe ; premier mot de passe" "$(connexion "$T/mdp/troisieme") ; $(connexion "$T/mdp/connexion")" "code 0 ; code 2"

  echo "## 8. essai du propriétaire"
  c=$(lancer essai-faux essai BANC_MDP_CONNEXION="$T/mdp/autre")
  attendu "essai, mauvais mot de passe : code ; connexion refusée" "code $c ; $(n essai-faux 'KO   connexion : code 2')" "code 1 ; 1"
  c=$(PTY_MDP=$T/mdp/troisieme PTY_MOTIFS=Password lancer essai essai)
  attendu "essai relancé sous pty (invite de bao) : pty" "$(sed -n 1p "$T/sorties/essai.out")" "pty : code 0 ; invites vues 1 ; échos du mot de passe 0"
  attendu "essai : code ; connexion ; 900 s ; essais conformes ; KO" \
    "code $c ; $(n essai 'OK   connexion : code 0 ; politiques vex-signature ; durée 900 s ; secret dans un fichier 600') $(n essai 'OK   secret du propriétaire : vex-signature seule, 900 s') ; $(grep -c '^OK   essai ' "$T/sorties/essai.out") ; $(nko essai)" \
    "code 0 ; 1 1 ; 14 ; 0"
  attendu "essai : openssl ; témoin ; cosign hashivault ; révocation ; signature après révocation" \
    "$(n essai 'OK   openssl : signature de la clé vex vérifiée') $(n essai 'OK   témoin : même signature sur une autre entrée refusée') $(n essai 'OK   cosign public-key --key hashivault://vex : code 0, SPKI égal') $(n essai 'OK   révocation de soi : code 0') $(n essai 'OK   signature avec la clé vex après révocation : REFUSE')" \
    "1 1 1 1 1"
  attendu "essai : redirection fermée ; K4 ; K5 ; fichier du secret effacé ; rien dans le HOME du client" \
    "$(n essai 'OK   redirection fermée') ; $(n essai 'OK   K4 : ') ; $(n essai 'OK   K5 : ') ; $(n essai 'OK   fichier du secret du propriétaire effacé') ; $(cat <(find "$BANC"/travail/essai-*/home -type f) | grep -c .)" \
    "1 ; 1 ; 1 ; 1 ; 0"
  attendu "dossiers d'essai : un par lancement ; fichier du secret restant" "$(find "$BANC/travail" -mindepth 1 -maxdepth 1 -type d -name 'essai-*' | grep -c .) ; $(find "$BANC/travail" -name secret | grep -c .)" "2 ; 0"

  echo "## 9. audit du banc"
  compte_audit() { # filtre jq sur les réponses : « nom affiché nombre », triés, séparés par des virgules
    jq -r "select(.type == \"response\") | select($1) | .auth.display_name" "$T/bao-audit.log" | sort | uniq -c | awk '{print $2 " " $1}' | paste -sd, -
  }
  attendu "audit : écriture de l'utilisateur proprietaire, par identité" \
    "$(compte_audit '.request.path == "auth/userpass/users/proprietaire" and (.request.operation == "create" or .request.operation == "update") and ((.error // "") == "")')" "root 2"
  attendu "audit : signatures réussies sur transit/sign/vex, par identité" \
    "$(compte_audit '(.request.path | startswith("transit/sign/vex")) and ((.error // "") == "")')" "userpass-proprietaire 1"
  attendu "faux kubectl : appels inattendus" "$(grep -c -v -e '^exec -i -n openbao openbao-0 -- ' -e '^port-forward -n openbao pod/openbao-0 --address 127.0' "$T/appels")" 0
  echo "$KO" > "$T/ko-ns"
  exit 0
fi

# ------------------------------------------------------------------------------------------------------------------------ parent
RES=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$RES" rev-parse --show-toplevel)
SRC=$HOME/.cache/supply-chain-poc/07a/t3/b/poc/bricks/07a-sbom-grype
T=$HOME/.cache/supply-chain-poc/07a/p2-pose-banc
BAO=$HOME/.cache/supply-chain-poc/07a/bao-2.7.2/bao
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ ! -e "$T" ] || { echo "KO   $T existe déjà"; exit 1; }
mkdir -p "$T/arbre/poc/bricks/07a-sbom-grype/politique"
attendu "bao : empreinte du binaire extrait (07b-p2-bao.log)" "$(sha256sum < "$BAO" | cut -c1-16)" 9c5f36287c673f38
attendu "bao : version et commit" "$("$BAO" version | cut -d' ' -f2,3)" "v2.7.2 (9e0a0d3c3504a0a00b45e61355afac5e35c78379),"
COSIGN=$(cd "$TOP" && mise which cosign)
echo "cosign : $("$COSIGN" version 2>/dev/null | sed -n 's/^GitVersion: *//p')"
cp "$SRC/vex-openbao.sh" "$T/arbre/poc/bricks/07a-sbom-grype/"
cp "$SRC/politique/vex-signature.hcl" "$T/arbre/poc/bricks/07a-sbom-grype/politique/"
echo "vex-openbao.sh de l'arbre du patch : sha256 $(sha256sum < "$SRC/vex-openbao.sh" | cut -c1-16)… ; vex-signature.hcl : $(sha256sum < "$SRC/politique/vex-signature.hcl" | cut -c1-16)…"
T=$T BAO=$BAO COSIGN=$COSIGN unshare -rn bash "$0" ns
KO=$((KO + $(cat "$T/ko-ns" 2>/dev/null || echo 1)))
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "## bilan : $KO écart(s)"
echo "à effacer après archivage (chemin littéral) : $T"
[ "$KO" = 0 ]
