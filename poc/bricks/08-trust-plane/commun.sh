# Brique 08 : variables et fonctions communes des jalons J2 et suivants (chargé par stockage.sh, openbao.sh…).
# Le script appelant pose `here` (son répertoire) avant de charger ce fichier.
. "${BASH_SOURCE[0]%/*}/distro.sh"
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

gabarit_essai() { # l'étape suppose le gabarit d'essai de J6 (declencheurs.yaml, pipeline sample-app-essai) ; KO sinon, notamment
  # après la bascule de J8 (preuves.sh bascule, politique/gabarit-sample-app.yaml) : à rejouer avant elle, ou après
  # politique.sh declencheurs (qui remet le gabarit d'essai)
  local n
  n=$(kubectl get triggertemplate -n declencheurs sample-app -o json 2>/dev/null \
    | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "name") | .value') || n=""
  [ "$n" = sample-app-essai ] || { echo "KO   gabarit en service : pipeline ${n:-absente} ; l'étape suppose le gabarit d'essai de J6 (politique.sh declencheurs)" >&2; exit 1; }
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
  sur sc-confiance "sudo sh -c 'grep -hF -- $1 \$(ls -1 $D_ETAT/server/logs/audit*.log | LC_ALL=C sort) || true'"
}

el_url() { echo "http://${IP[sc-confiance]}:$(kubectl get svc -n "$EL_NS" el-forgejo -o jsonpath='{.spec.ports[?(@.name=="http-listener")].nodePort}')"; }

# Livraisons vers l'EventListener et suivi des PipelineRuns de sample-app (J4, tekton.sh essais_webhook ; J8, preuves.sh test5).
# envoyer écrit la réponse dans $T/webhook/reponse ($T : répertoire de travail du script appelant).
hmac_corps() { # fichier : HMAC-SHA256 (hex) du fichier avec le secret du webhook, lu dans un fichier (jamais en argument)
  python3 -I -c 'import hashlib, hmac, sys; print(hmac.new(open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read(), hashlib.sha256).hexdigest())' \
    "$S/forgejo-webhook.secret" "$1"
}
non_repris() { # commit : le TaskRun publier de sample-app-<commit> appartient à ce PipelineRun (pas d'adoption après purge)
  local u
  u=$(kubectl get pipelinerun -n builds "sample-app-$1" -o jsonpath='{.metadata.uid}')
  [ "$(kubectl get taskrun -n builds "sample-app-$1-publier" -o jsonpath='{.metadata.ownerReferences[0].uid}' 2>/dev/null)" = "$u" ] \
    && echo "OK   TaskRun sample-app-$1-publier créé par ce PipelineRun (propriétaire $u)" \
    || { echo "KO   sample-app-$1 : TaskRun publier absent ou d'un autre PipelineRun (repris après la purge)" >&2; exit 1; }
}
pr_attendre() { # commit : attend le PipelineRun sample-app-<commit> (présent, puis terminé)
  for _ in $(seq 60); do kubectl get pipelinerun -n builds "sample-app-$1" >/dev/null 2>&1 && break; sleep 2; done
  kubectl wait -n builds --for=condition=Succeeded "pipelinerun/sample-app-$1" --timeout=180s >/dev/null
}
envoyer() { # libellé fichier-corps signature|"" : livraison vers l'EventListener, comme Forgejo (en-têtes GitHub)
  local h=() code
  [ -z "$3" ] || h=(-H "X-Hub-Signature-256: sha256=$3")
  code=$(curl -s -o "$T/webhook/reponse" -w '%{http_code}' -H 'Content-Type: application/json' -H 'X-GitHub-Event: push' \
    -H "X-GitHub-Delivery: $(cat /proc/sys/kernel/random/uuid)" "${h[@]}" --data-binary @"$2" "$(el_url)")
  echo "$1 : HTTP $code $(jq -c '{eventID}' "$T/webhook/reponse" 2>/dev/null)"
}
signe_attendre() { # commit : attend que Chains ait signé le TaskRun et le PipelineRun de ce commit. Les écritures du tag
  # .att d'un même digest ne sont pas atomiques (lecture puis réécriture) : deux envois simultanés perdent une enveloppe
  # (constat-att-ecrasee.log). Les essais sérialisent donc les exécutions qui visent la même image.
  local o
  for o in "taskrun/sample-app-$1-publier" "pipelinerun/sample-app-$1"; do
    for _ in $(seq 60); do
      [ "$(kubectl get -n builds "$o" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}' 2>/dev/null)" = true ] && break
      sleep 2
    done
  done
}
nb_pr() { kubectl get pipelinerun -n builds -o name | grep -c "sample-app-$1" || true; }

reseau() { # contrôleur réseau du cluster : cilium (DaemonSet cilium de kube-system, J7, option 1b) ou flannel (flannel et kube-router)
  if kubectl get ds -n kube-system cilium >/dev/null 2>&1; then echo cilium; else echo flannel; fi
}

hubble_refus() { # nœud depuis [filtres de hubble observe…] : flux refusés (DROPPED) vus par l'agent Cilium du nœud depuis une date
  # RFC 3339 ; une ligne par flux : heure, source, destination:port, drapeaux TCP, motif, sens
  local n=$1 d=$2 p
  shift 2
  p=$(kubectl -n kube-system get pods -l k8s-app=cilium --field-selector "spec.nodeName=$n" -o jsonpath='{.items[0].metadata.name}')
  kubectl -n kube-system exec "$p" -c cilium-agent -- hubble observe --since "$d" --verdict DROPPED -o json "$@" \
    | jq -r '.flow | [.time[11:23], (.IP.source + " > " + .IP.destination + ":" + ((.l4.TCP.destination_port // .l4.UDP.destination_port // "-") | tostring)),
        ((.l4.TCP.flags // {}) | keys | join(",")), (.drop_reason_desc // "-"), (.traffic_direction // "-")] | join(" ")'
}

capture() { # fichier durée filtre… : tcpdump sur sc-build en arrière-plan (PID dans $CAPTURE), attend qu'il écoute
  local f=$1 d=$2; shift 2
  sur sc-build "sudo timeout $d tcpdump -nn -l $* 2>&1" > "$f" &
  CAPTURE=$!
  for _ in $(seq 20); do grep -q '^listening on' "$f" && return 0; sleep 0.5; done
  echo "KO   tcpdump ($*) n'écoute pas" >&2; cat "$f" >&2; exit 1
}

syn() { # fichier source destination.port : nombre de lignes SYN (sans ACK) de source vers destination dans une capture tcpdump
  grep -cE "IP ${2//./\\.}\.[0-9]+ > ${3//./\\.}: Flags \[S\]," "$1" || true
}

syn_distincts() { # mêmes arguments : nombre de SYN distincts (port source et numéro de séquence)
  { grep -E "IP ${2//./\\.}\.[0-9]+ > ${3//./\\.}: Flags \[S\]," "$1" || true; } \
    | sed -E 's/.* IP ([0-9.]+) > .*, seq ([0-9]+),.*/\1 \2/' | sort -u | wc -l
}

el_joignable() { # EventListener de $EL_NS disponible et joignable depuis sc-stockage ; une ligne
  local url n=1
  for _ in $(seq 60); do kubectl get deploy -n "$EL_NS" el-forgejo >/dev/null 2>&1 && break; sleep 2; done
  kubectl wait -n "$EL_NS" --for=condition=Available deploy/el-forgejo --timeout=180s >/dev/null
  url=$(el_url)
  # kube-router rejette le trafic vers un pod neuf pendant quelques secondes (J3 ; à mesurer sous Cilium) : Forgejo n'a pas relivré un webhook
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

# Contrôles après un redémarrage (redemarrer.sh ; J7 : kata.sh exemption, redémarrage du server k3s). Fichiers dans $T.
adresse_libre() { # préfixe du /24 : première adresse de .250 à .200 portée ni par un pod ni par un endpoint de Cilium, qui tire au hasard
  local p=$1 i prises
  prises=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}'
    kubectl get ciliumendpoints -A -o json | jq -r '.items[].status.networking.addressing[]?.ipv4')
  for i in $(seq 250 -1 200); do grep -qxF "$p.$i" <<< "$prises" || { echo "$p.$i"; return 0; }; done
  return 1
}

sonde_kyverno() { # pod de tsa sans nodeSelector (conforme à Pod Security restricted, qui passe avant les webhooks), créé en
  # dry-run serveur : refus attendu de la règle zone-confiance de Kyverno, pas une erreur d'appel du webhook
  local img msg="" i
  img=$(kubectl get deployment -n tsa timestamp-authority -o jsonpath='{.spec.template.spec.containers[0].image}')
  jq -n --arg i "$img" '{apiVersion: "v1", kind: "Pod", metadata: {name: "sonde-kyverno", namespace: "tsa"},
    spec: {automountServiceAccountToken: false, securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "sonde", image: $i, securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}}' > "$T/sonde-kyverno.json"
  for i in $(seq 90); do
    msg=$(kubectl create --dry-run=server -f "$T/sonde-kyverno.json" 2>&1 || true)
    grep -qF 'zone confiance : nodeSelector zone=confiance obligatoire' <<<"$msg" && break
    sleep 2
  done
  grep -qF 'zone confiance : nodeSelector zone=confiance obligatoire' <<<"$msg" \
    && echo "OK   Kyverno répond à l'admission ($i essai(s)) : pod sans nodeSelector refusé par zone-confiance" \
    || { echo "KO   Kyverno ne répond pas : $msg" >&2; exit 1; }
}

passage_ok() { # espace CronJob instant : premier passage créé après l'instant, attendu réussi ; résumé de son journal.
  # Concurrence Forbid : un passage lancé avant le descellement peut retarder le suivant jusqu'à son échéance (300 s)
  local ns=$1 cj=$2 t=$3 j=""
  for _ in $(seq 210); do
    j=$(kubectl get jobs -n "$ns" -o json | jq -r --arg t "$t" --arg c "$cj" '[.items[] | select(any(.metadata.ownerReferences[]?; .kind == "CronJob"
      and .name == $c) and .metadata.creationTimestamp > $t and ((.status.succeeded // 0) + (.status.failed // 0)) > 0)]
      | sort_by(.metadata.creationTimestamp) | .[0].metadata.name // empty')
    [ -n "$j" ] && break
    sleep 2
  done
  [ -n "$j" ] || { echo "KO   aucun passage du CronJob $ns/$cj terminé depuis $t" >&2; exit 1; }
  kubectl logs -n "$ns" "job/$j" > "$T/passage-$cj.log" 2>&1 || true
  echo "passage $j : $(cut -d'|' -f1 "$T/passage-$cj.log" | sort | uniq -c | awk '{printf "%s %s ; ", $2, $1}')"
  [ "$(kubectl get job -n "$ns" "$j" -o jsonpath='{.status.succeeded}')" = 1 ] && echo "OK   $ns/$cj : passage réussi après le retour du TSA" \
    || { cat "$T/passage-$cj.log" >&2; echo "KO   $ns/$cj : passage $j en échec" >&2; exit 1; }
}

# Empreinte d'arbre (J7 : voie-d.sh, construction.sh).
arbre() { # répertoire : empreinte de l'arbre (chemins relatifs, types, modes et sha256 des fichiers, cibles des liens)
  (cd "$1" && find . -printf '%y %m %p %l\n' | sort | while read -r y m p l; do
    case $y in f) echo "f $m $p $(sha256sum < "$p" | cut -c1-64)" ;; l) echo "l $p -> $l" ;; *) echo "$y $m $p" ;; esac
  done) | sha256sum | cut -c1-64
}

# Tâches et pipelines signées (J6 : politique.sh ; J7 : construction.sh). Fichiers dans $T, authentification Zot dans $T/auth/docker.
bundle() { # fichier dépôt [tag] : bundle Tekton poussé dans Zot par tkn (date de création fixe : digest reproductible) ; digest
  DOCKER_CONFIG=$T/auth/docker SSL_CERT_FILE=$P/ca-poc.crt tkn bundle push "$REG_HOTE/$2:${3:-essai}" -f "$1" > "$T/tkn.out" 2>&1 \
    || { cat "$T/tkn.out" >&2; exit 1; }
  SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$2:${3:-essai}"
}

signe() { # type nom : attend l'annotation de Chains sur un TaskRun ou un PipelineRun de builds ; sa valeur
  local v=""
  for _ in $(seq 60); do
    v=$(kubectl get "$1" -n builds "$2" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')
    [ "$v" = true ] && break
    sleep 2
  done
  echo "${v:-absente}"
}

listee() { # bundle (par digest) : présent dans la liste revue des tâches approuvées (politique/porte/taches.yml)
  awk -v d="oci://${1%@*}:" -v r="${1#*@}" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && $3 == r {t = 1} END {exit !t}' "$here/politique/porte/taches.yml"
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
