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
# Horodatage (J5, tsa.sh ; J6, CronJob de politique.sh) : image d'outils du job et dépôt des bundles réémis
OUTILS=plateforme/outils-horodatage
OUTILS_DIGEST=sha256:c7bebae2bd33e57792988b8ba215536dd9360a9871ec0bdf807ee94d4c1f4ca0   # assemblage reproductible (tsa.sh image)
DEPOT_BUNDLES=horodatage/bundles   # bundles réémis, hors des dépôts des images (voir tsa/horodater.sh)
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

ivpol() { # dépôt-des-bundles [chaîne-TSA [nom]] : ImageValidatingPolicy du contrôle 9 (attestor à clé, sans journal ; J5, J6)
  cat <<EOF
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: ${3:-horodatage}
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
  matchImageReferences:
    - glob: "$REG_HOTE/*"
  attestors:
    - name: chains
      cosign:
        key:
          data: |
$(sed 's/^/            /' "$R/chains-cle-publique.pem")
$([ -n "$1" ] && printf '        source:\n          repository: %s\n' "$REG_HOTE/$1")
        ctlog:
          insecureIgnoreTlog: true
$([ -n "${2:-}" ] && printf '          tsaCertChain: |\n' && sed 's/^/            /' "$2")
  attestations:
    - name: prov
      intoto:
        type: https://slsa.dev/provenance/v1
  validations:
    - expression: >-
        images.containers.map(i, verifyAttestationSignatures(i, attestations.prov, [attestors.chains])).all(e, e > 0)
      message: "C9 : provenance sans horodatage RFC 3161 valide"
EOF
}

EL_NS=${EL_NS:-builds}   # espace de l'EventListener forgejo : builds en J4, declencheurs depuis J6
purger_pr() { # --all | nom… : PipelineRuns de builds supprimés, puis leurs TaskRuns (label tekton.dev/pipelineRun),
  # attendus disparus. La suppression au premier plan ne suffit pas : Chains v0.29.9 retire sa finalisation par
  # application côté serveur, et le PipelineRun disparaît aussitôt, avant ses TaskRuns (foregroundDeletion perdue, mesuré
  # en J6). Recréé sous le même nom, il reprendrait un TaskRun encore présent (Pipelines v1.15.5 le cherche par nom).
  local n
  if [ "$1" = --all ]; then
    kubectl delete pipelinerun -n builds --all --wait=true >/dev/null
    kubectl delete taskrun -n builds -l tekton.dev/pipelineRun --ignore-not-found --wait=true >/dev/null
  else
    for n in "$@"; do
      kubectl delete pipelinerun -n builds "$n" --ignore-not-found --wait=true >/dev/null
      kubectl delete taskrun -n builds -l "tekton.dev/pipelineRun=$n" --ignore-not-found --wait=true >/dev/null
    done
  fi
}

audit_api() { # motif (chaîne fixe, sans espace ni guillemet) : lignes de l'audit de l'API qui la contiennent, fichiers tournés
  # compris (audit-log-maxsize=100 : audit-<horodatage>.log par tranche de 100 Mo, puis audit.log), dans l'ordre chronologique
  sur sc-confiance "sudo sh -c 'grep -hF -- $1 \$(ls -1 /var/lib/rancher/k3s/server/logs/audit*.log | LC_ALL=C sort) || true'"
}

el_url() { echo "http://${IP[sc-confiance]}:$(kubectl get svc -n "$EL_NS" el-forgejo -o jsonpath='{.spec.ports[?(@.name=="http-listener")].nodePort}')"; }

el_joignable() { # EventListener de $EL_NS disponible et joignable depuis sc-stockage ; une ligne
  local url n=1
  for _ in $(seq 60); do kubectl get deploy -n "$EL_NS" el-forgejo >/dev/null 2>&1 && break; sleep 2; done
  kubectl wait -n "$EL_NS" --for=condition=Available deploy/el-forgejo --timeout=180s >/dev/null
  url=$(el_url)
  # kube-router rejette le trafic vers un pod neuf pendant quelques secondes (J3) : Forgejo n'a pas relivré un webhook
  # refusé (rejeu de J5, puis code de Forgejo lu en J6) ; on attend la sonde /live depuis sc-stockage (sans événement).
  until [ "$(sur sc-stockage "curl -s -o /dev/null -w '%{http_code}' $url/live" || true)" = 200 ]; do
    [ $n -lt 60 ] || { echo "KO   EventListener injoignable depuis sc-stockage" >&2; exit 1; }
    n=$((n + 1)); sleep 1
  done
  echo "EventListener joignable par Forgejo : $url (NodePort sur sc-confiance ; /live depuis sc-stockage, essai $n)"
}

brancher_forgejo() { # EventListener de $EL_NS attendu, puis seul webhook du dépôt sample-app (J4, J6) ; répertoire $T/auth
  local url id
  el_joignable
  kubectl get pods -n "$EL_NS" -l eventlistener=forgejo -o wide --no-headers | awk '{print "EventListener :", $1, $3, $7}'
  url=$(el_url)
  # Webhook Forgejo : le secret passe par un fichier 0600 (curl -d @fichier), jamais en argument.
  printf 'Authorization: token %s\n' "$(cat "$S/forgejo-admin.token")" > "$T/auth/entete"
  api() { curl -fsS --cacert "$P/ca-poc.crt" -H @"$T/auth/entete" -H 'Content-Type: application/json' "$@"; }
  for id in $(api https://192.168.161.13:3000/api/v1/repos/workspace/sample-app/hooks | jq -r '.[].id'); do
    api -X DELETE "https://192.168.161.13:3000/api/v1/repos/workspace/sample-app/hooks/$id" >/dev/null
  done
  jq -n --arg u "$url" --rawfile s "$S/forgejo-webhook.secret" '{type: "forgejo", active: true, events: ["push"], branch_filter: "main",
    config: {url: $u, content_type: "json", secret: $s}}' > "$T/auth/hook.json"
  api -X POST https://192.168.161.13:3000/api/v1/repos/workspace/sample-app/hooks -d @"$T/auth/hook.json" \
    | jq -c '{id, type, active, events, url: .config.url, content_type: .config.content_type}'
  rm -f "$T/auth/hook.json" "$T/auth/entete"
}

config_horodatage() { # ConfigMap du job d'horodatage (J5) et du CronJob (J6) : script, CA du PoC, clé publique de Chains,
  # racine de confiance du TSA (vérification de bout en bout d'un bundle avant sa publication) ; rien de secret
  kubectl create configmap horodatage -n horodatage --from-file=horodater.sh="$here/tsa/horodater.sh" \
    --from-file=ca-poc.crt="$P/ca-poc.crt" --from-file=chains.pub="$R/chains-cle-publique.pem" \
    --from-file=tsa-racine-confiance.json="$P/tsa-racine-confiance.json" \
    --dry-run=client -o yaml | kubectl apply --server-side -f - >/dev/null
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
    { echo "# ${0##*/} $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/$p-$e.log"
    chrono "$j $e fait"
  done
}
