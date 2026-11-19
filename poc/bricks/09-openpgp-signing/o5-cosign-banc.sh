#!/usr/bin/env bash
# Brique 09, banc hors cluster d'o5-cosign.sh. Faux kubectl : « port-forward » ouvre un vrai port d'écoute sur 127.0.0.1 (python),
# qui doit être fermé à la fin de chaque étape. Faux cosign : public-key et attest-blob par « hashivault://lien » contrôlent
# l'environnement reçu (VAULT_ADDR vers ce port, VAULT_CACERT, VAULT_TLS_SERVER_NAME, VAULT_TOKEN égal au secret factice, secret
# absent des arguments), puis rendent la clé publique jetable du banc ou signent avec la clé jetable ; version et
# verify-blob-attestation passent au vrai cosign. Aucun accès au cluster ni à OpenBao.
# Cas : cle nominal ; autre clé rendue ; redirection en échec ; essai nominal ; signature refusée ; fuite du secret ; dossier présent.
# Usage : poc/bricks/09-openpgp-signing/o5-cosign-banc.sh   (journal : resultats/o5-cosign-banc.log ; dossier effacé à la main)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
TOP=$(git -C "$here" rev-parse --show-toplevel)
B=$HOME/.cache/supply-chain-poc/09/o5-cosign-banc
S=$here/o5-cosign.sh
VRAI=$(cd "$TOP" && mise which cosign)
SECRET=s.bancfaux0123456789abcd
[ ! -e "$B" ] || { echo "KO   $B existe déjà" >&2; exit 1; }
mkdir -p "$B/bin" "$B/modele"
(cd "$B/modele" && unshare --map-auto --map-root-user -n env -i PATH=/usr/bin:/bin HOME="$B/modele" COSIGN_PASSWORD= "$VRAI" generate-key-pair --output-key-prefix cle > /dev/null 2>&1)
(cd "$B/modele" && unshare --map-auto --map-root-user -n env -i PATH=/usr/bin:/bin HOME="$B/modele" COSIGN_PASSWORD= "$VRAI" generate-key-pair --output-key-prefix autre > /dev/null 2>&1)
cat > "$B/bin/kubectl" <<EOF
#!/usr/bin/env bash
case "\$1" in
  version) echo "Client Version: banc" ;;
  port-forward)
    [ "\$*" = "port-forward -n openbao pod/openbao-0 --address 127.0.0.1 :8200" ] || { echo "faux kubectl : appel inattendu : \$*" >&2; exit 9; }
    [ "\$KUBECONFIG" = "\$HOME/.kube/supply-chain-poc.yaml" ] || { echo "faux kubectl : KUBECONFIG inattendu" >&2; exit 9; }
    [ "\$(cat "$B/etat/mode")" = pf_echec ] && { echo "error: unable to forward port (banc)"; exit 1; }
    exec python3 -I -c '
import socket, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(8)
print(f"Forwarding from 127.0.0.1:{s.getsockname()[1]} -> 8200", flush=True)
while True:
    c, _ = s.accept(); c.close()
' o5-cosign-banc-redirection ;;
  *) echo "faux kubectl : appel inattendu : \$*" >&2; exit 9 ;;
esac
EOF
cat > "$B/bin/cosign" <<EOF
#!/usr/bin/env bash
E=$B/etat
mode=\$(cat "\$E/mode")
controle_env() { # environnement du client hashivault ; erreurs comptées dans etat/erreurs
  local p=\${VAULT_ADDR#https://127.0.0.1:}
  [[ \$p =~ ^[0-9]+\$ ]] && (exec 3<>"/dev/tcp/127.0.0.1/\$p") 2>/dev/null || echo "VAULT_ADDR \$VAULT_ADDR injoignable" >> "\$E/erreurs"
  [ "\${VAULT_CACERT:-}" = "\$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt" ] || echo "VAULT_CACERT" >> "\$E/erreurs"
  [ "\${VAULT_TLS_SERVER_NAME:-}" = openbao.openbao.svc.cluster.local ] || echo "VAULT_TLS_SERVER_NAME" >> "\$E/erreurs"
  [ "\${VAULT_TOKEN:-}" = "$SECRET" ] || echo "VAULT_TOKEN" >> "\$E/erreurs"
  case " \$* " in *"$SECRET"*) echo "secret en argument" >> "\$E/erreurs" ;; esac
  echo "\$1" >> "\$E/appels"
}
case "\$1" in
  version|verify-blob-attestation) exec "$VRAI" "\$@" ;;
  public-key)
    controle_env "\$@"
    [ "\$mode" = fuite ] && { echo "Error: secret \$VAULT_TOKEN" >&2; exit 1; }
    [ "\$mode" = autre_cle ] && exec cat "$B/modele/autre.pub"
    exec cat "$B/modele/cle.pub" ;;
  attest-blob)
    controle_env "\$@"
    [ "\$mode" = signature_refusee ] && { echo "Error: signing: Code: 403 permission denied (banc)" >&2; exit 1; }
    a=(); for x in "\$@"; do [ "\$x" = hashivault://lien ] && x=$B/modele/cle.key; a+=("\$x"); done
    exec unshare --map-auto --map-root-user -n env -i PATH=/usr/bin:/bin HOME=$B/modele COSIGN_PASSWORD= "$VRAI" "\${a[@]}" ;;   # hors réseau
  *) echo "faux cosign : appel inattendu : \$*" >&2; exit 9 ;;
esac
EOF
chmod +x "$B/bin/kubectl" "$B/bin/cosign"

n_ok=0; n_ko=0
verdict() { if eval "$2"; then echo "OK   $1"; n_ok=$((n_ok + 1)); else echo "KO   $1 (condition : $2)"; n_ko=$((n_ko + 1)); fi; }
cas() { # nom mode : nouveau dossier de cas
  C=$B/cas-$1; mkdir -p "$C/secrets9" "$C/resultats" "$C/bin"
  ln -sfn "$C/etat" "$B/etat"; mkdir -p "$C/etat"; echo "$2" > "$C/etat/mode"; : > "$C/etat/erreurs"; : > "$C/etat/appels"
  (umask 077 && printf '%s' "$SECRET" > "$C/secrets9/openbao-lien.secret")
  cp "$B/modele/cle.pub" "$C/resultats/lien-cle-publique.pem"; cp "$B/bin/kubectl" "$B/bin/cosign" "$C/bin/"
}
# shellcheck disable=SC2034
lancer() { BANC=$C "$S" "$1" > "$C/$1.sortie" 2>&1; RC=$?; J=$C/resultats/o5-cosign-$1.log; }
ecoutes() { pgrep -f o5-cosign-banc-redirection | grep -c . || true; }
{
echo "banc commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-cosign.sh $(sha256sum < "$S" | cut -c1-16)… ; o5-cosign-banc.sh $(sha256sum < "$0" | cut -c1-16)…"
set +e
echo "### 1. cle nominal"
cas cle normal; lancer cle
verdict "code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "clé égale à l'archivée" 'grep -q "^OK   clé lue par cosign dans OpenBao = clé publique archivée" "$J"'
verdict "environnement du client conforme, secret jamais en argument" '[ ! -s "$C/etat/erreurs" ] && [ "$(cat "$C/etat/appels")" = public-key ]'
verdict "redirection fermée, plus aucune écoute" 'grep -q "^OK   redirection fermée" "$J" && [ "$(ecoutes)" = 0 ]'
verdict "secret absent du journal, de la sortie et du dossier de travail" '! grep -r -q -F "$SECRET" "$C/resultats" "$C/cle.sortie" "$C/travail"'
verdict "K5 tenu, aucune ligne masquée" 'grep -q "^OK   K5" "$J" && ! grep -q "ligne masquée" "$J"'
cp "$J" "$C/cle-nominal.log"
echo "### 2. cle : OpenBao rend une autre clé"
cas autre autre_cle; lancer cle
verdict "autre clé : KO, redirection fermée" 'grep -q "^KO   clé lue par cosign .* différente de la clé archivée" "$J" && grep -q "^OK   redirection fermée" "$J" && [ "$(ecoutes)" = 0 ]'
echo "### 3. redirection en échec"
cas pf pf_echec; lancer cle
verdict "redirection en échec : KO, cosign jamais appelé" 'grep -q "^KO   redirection non ouverte" "$J" && [ ! -s "$C/etat/appels" ] && [ "$(ecoutes)" = 0 ]'
echo "### 4. essai nominal"
cas essai normal; lancer essai
verdict "code 0, aucune ligne KO" '[ "$RC" = 0 ] && ! grep -q "^KO" "$J"'
verdict "signature vérifiée hors réseau, témoin refusé" 'grep -q "^OK   vérification hors réseau avec la clé publique archivée : Verified OK" "$J" && grep -q "^OK   témoin : même bundle" "$J"'
verdict "environnement conforme, redirection fermée avant la vérification" '[ ! -s "$C/etat/erreurs" ] && [ "$(grep -n "redirection fermée\|vérification hors réseau" "$J" | head -1 | grep -c fermée)" = 1 ] && [ "$(ecoutes)" = 0 ]'
verdict "secret absent du journal, de la sortie et du dossier de travail" '! grep -r -q -F "$SECRET" "$C/resultats" "$C/essai.sortie" "$C/travail"'
cp "$J" "$C/essai-nominal.log"
echo "### 5. signature refusée par OpenBao"
cas refus signature_refusee; lancer essai
verdict "refus : KO attest-blob, redirection fermée" 'grep -q "^KO   attest-blob : code 1" "$J" && grep -q "^OK   redirection fermée" "$J" && [ "$(ecoutes)" = 0 ]'
echo "### 6. fuite du secret dans une erreur du client"
cas fuite fuite; lancer cle
verdict "fuite : journal vidé par K5, secret absent du journal et de la sortie" 'grep -q "^KO   K5" "$J" && [ "$(grep -c . "$J")" = 1 ] && ! grep -q -F "$SECRET" "$J" "$C/cle.sortie" && [ "$(ecoutes)" = 0 ]'
echo "### 7. dossier de travail déjà présent"
cas present normal; mkdir -p "$C/travail"; lancer cle
verdict "dossier présent : refus avant la redirection" 'grep -q "^KO   .*travail existe déjà" "$J" && [ ! -s "$C/etat/appels" ] && [ ! -e "$C/travail/redirection.log" ]'
echo "### journaux nominaux"
sed 's/^/     | /' "$B/cas-cle/cle-nominal.log" "$B/cas-essai/essai-nominal.log"
echo "bilan : $n_ok OK, $n_ko KO"
echo "banc fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "à effacer après archivage (chemin littéral) : $B"
[ "$n_ko" = 0 ]
} 2>&1 | tee "$here/resultats/o5-cosign-banc.log"
