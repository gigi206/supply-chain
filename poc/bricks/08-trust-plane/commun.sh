# Brique 08 : variables et fonctions communes des jalons J2 et suivants (chargé par stockage.sh, openbao.sh…).
# Le script appelant pose `here` (son répertoire) avant de charger ce fichier.
repo=$(git -C "$here" rev-parse --show-toplevel)
R=$here/resultats
O=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}
S=$O/secrets
P=$O/pki
W=$O/travail
REG_HOTE=192.168.161.13:5000          # Zot depuis l'hôte (pas de résolution de poc.test) : SAN IP du certificat
REG=sc-stockage.poc.test:5000         # Zot depuis les nœuds et les pods
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
declare -A IP=([sc-confiance]=192.168.161.11 [sc-build]=192.168.161.12 [sc-stockage]=192.168.161.13)
SSH_OPTS=(-i "$O/ssh/id_ed25519" -o UserKnownHostsFile="$O/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
mkdir -p "$R" "$P" "$W"
(umask 077 && mkdir -p "$S")
chrono() { printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }
sur() { local vm=$1; shift; ssh "${SSH_OPTS[@]}" "poc@${IP[$vm]}" "$@"; }
copier() { # vm répertoire-distant fichiers…
  local vm=$1 d=$2; shift 2
  sur "$vm" "rm -rf $d && mkdir -m 0700 $d"
  scp -q "${SSH_OPTS[@]}" "$@" "poc@${IP[$vm]}:$d/"
}
refus() { # libellé motif commande… : la commande doit échouer, avec le motif dans sa sortie
  local l=$1 m=$2; shift 2
  if "$@" > "$W/refus.out" 2>&1; then echo "KO   $l : accepté" >&2; exit 1; fi
  if grep -iE "$m" "$W/refus.out" >/dev/null; then
    echo "OK   $l : refusé ($(grep -oiE "$m" "$W/refus.out" | head -1))"
  else
    echo "KO   $l : refusé pour une autre raison" >&2; cat "$W/refus.out" >&2; exit 1
  fi
}

racine() { # script sh sur l'entrée standard, exécuté dans openbao-0 avec le jeton root lu sur l'entrée standard (J3, J5)
  { tr -d '\n' < "$S/openbao-root.token"; echo; cat; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c 'read -r BAO_TOKEN && export BAO_TOKEN && exec sh -s'
}

attendre_sa() { # espace : le compte de service default d'un espace neuf est créé de façon asynchrone par le contrôleur
  for _ in $(seq 60); do kubectl get serviceaccount default -n "$1" >/dev/null 2>&1 && return 0; sleep 1; done
  echo "KO   compte de service default absent de $1" >&2; return 1
}

auth_zot() { # fichier [mot-de-passe-fichier] [compte] [registre] : authentification Zot au format docker (0600)
  local compte=${3:-poc-ecriture}
  (umask 077 && printf '{"auths":{"%s":{"auth":"%s"}}}\n' "${4:-$REG_HOTE}" \
    "$(printf '%s:%s' "$compte" "$(cat "${2:-$S/zot-$compte.password}")" | base64 -w0)" > "$1")
}

miroir() { # source@digest dépôt-zot fichier-auth-zot [-r] : copie par digest d'une image amont dans Zot (REG_HOTE), par
  # un cache OCI local (…/08/telechargements/oci/<dépôt>) rempli une seule fois : le rejeu ne dépend plus du débit du
  # registre amont (Zot coupe un envoi qui stagne : « i/o timeout »), et Zot reçoit les blobs à la vitesse du réseau local.
  # Les blobs sont relus et vérifiés par digest à chaque copie (oras).
  local src=$1 dst=$2 auth=$3 d=${1##*@} cache=$O/telechargements/oci/$2; shift 3
  mkdir -p "$cache"
  oras manifest fetch --oci-layout --descriptor "$cache@$d" >/dev/null 2>&1 \
    || oras cp "$@" "$src" --to-oci-layout "$cache@$d" >/dev/null
  oras cp "$@" --from-oci-layout "$cache@$d" "$REG_HOTE/$dst@$d" --to-ca-file "$P/ca-poc.crt" --to-registry-config "$auth" >/dev/null
  echo "copié dans Zot : $REG_HOTE/$dst@$d (cache $([ "${1:-}" = -r ] && echo 'avec referrers, ')${cache#"$O"/})"
}

certificat() { # nom SAN : certificat de service signé par la CA du PoC (stockage.sh pki), clé en 0600
  local n=$1 cn=${2%%,*}
  if [ -s "$S/$n.key" ] && [ -s "$P/$n.crt" ]; then echo "$n : certificat existant"; else
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$S/$n.key")
    SAN=$2 openssl req -new -config "$here/stockage/pki.cnf" -key "$S/$n.key" -subj "/O=supply-chain PoC/CN=${cn#DNS:}" -out "$W/$n.csr"
    SAN=$2 openssl x509 -req -in "$W/$n.csr" -CA "$P/ca-poc.crt" -CAkey "$S/ca-poc.key" -set_serial "0x$(openssl rand -hex 16)" \
      -days 180 -sha256 -extfile "$here/stockage/pki.cnf" -extensions serveur_poc -out "$P/$n.crt" 2>/dev/null
    rm -f "$W/$n.csr"
  fi
  openssl verify -CAfile "$P/ca-poc.crt" -purpose sslserver "$P/$n.crt"
  openssl x509 -in "$P/$n.crt" -noout -subject -enddate -ext subjectAltName | paste -sd' ' | sed 's/  */ /g'
}

lancer() { # préfixe-du-journal jalon étape… : chaque étape etape_<nom> tourne avec son journal resultats/<préfixe>-<nom>.log
  local p=$1 j=$2 e; shift 2
  [ $# -gt 0 ] || { echo "usage : $0 $(declare -F | awk '$3 ~ /^etape_/ {sub("etape_", "", $3); printf "%s|", $3}' | sed 's/|$//')…" >&2; exit 2; }
  for e in "$@"; do declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }; done
  for e in "$@"; do
    chrono "$j $e"
    { echo "# $p.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/$p-$e.log"
    chrono "$j $e fait"
  done
}
