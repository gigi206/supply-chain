#!/usr/bin/env bash
# Brique 19b, J7, étape 2 recadrée (carte resultats/j7-carte.md, note « Étape 2 recadrée ») : deux pods Kata d'essai dans
# builds, puis lecture de Hubble dans l'agent Cilium de sc-build, en comptes seulement (jamais de flux bruts archivés).
# Les valeurs de Cilium ne sont pas touchées : aucun export n'est posé.
#   sec     à sec : les deux pods rendus, créés en dry-run serveur (admission comprise) ; rien n'est créé
#   mesure  cluster : pod a (sans label de tâche, témoin positif T0) puis pod b (label construire-rpm, T1 à T6, T8) ;
#           témoins de construire-rpm dans le pod ; ACCORD NOMMÉ DU PROPRIÉTAIRE : kubectl exec dans l'agent Cilium de
#           sc-build (hubble observe, date) ; arrêt si le pod a n'a aucun flux autorisé (T0) ; pods supprimés et flux bruts
#           effacés de $T en fin d'étape comme sur arrêt (trap) ; catalogue de Zot relu en anonyme avant et après
# Étape 4a (forme (a) : fichier combiné, valeurs de la 08c puis export, en VALEURS_08C ; disparaît au rejeu de zéro) :
#   pose_sec  à sec : fichier combiné, rendu hors ligne comparé au rendu de l'étape 1 (fichiers séparés) ; rien n'est posé
#   pose      ACCORD : cilium.sh appliquer avec le fichier combiné (redémarre les agents des trois nœuds), hors de 08:00 à
#             11:30 UTC et hors des balayages n°2 et n°3 de Zot ; rattrapage suspendu, aucun PipelineRun actif ; E1, E2, E3, E6
#   export    ACCORD : pods a et b comme « mesure », plus les relevés de l'invité Kata ; fichier d'export lu dans les
#             agents (kubectl exec), comptes seulement, copie effacée ; E4, E5, T7, réserve de T9 (préfixe)
#   retour    ACCORD : cilium.sh appliquer avec le seul fichier de la 08c (commande de etape_h5_cilium) ; export retiré
# Usage (racine du dépôt) : mise exec -- poc/bricks/19b-journalisation/j7.sh <étape>…   (journal : resultats/j7-<étape>.log)
set -euo pipefail
export LC_ALL=C

h19b=$(cd "$(dirname "$0")" && pwd)
here=$h19b/../08-trust-plane
. "$here/commun.sh"   # O, P, W, REG, REG_HOTE, lancer, chrono
R=$h19b/resultats
N=${PREFIXE:-j7}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
T=$W/$N-19b
mkdir -p "$T"
umask 022

TACHE=$h19b/../05-rpm-mock/construction/construire-rpm.m1b.signee.yaml   # contexte et ressources du pas construire
IMAGE_OUTILLAGE=$REG/builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae   # M1b (m1b-r1r8.sh)
LABEL_CONSTRUIRE=construire-rpm   # sélectionné par construction-rpm-sans-sortie
ZOT_CIBLE=192.168.161.13/5000
ZONE='{"nodeSelector": {"zone": "build"}, "tolerations": [{"key": "zone", "operator": "Equal", "value": "build", "effect": "NoSchedule"}],
  "securityContext": {"runAsNonRoot": true, "runAsUser": 65532, "seccompProfile": {"type": "RuntimeDefault"}}}'   # m1b-r1r8.sh
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'
V08C=$h19b/../08c-durcissement/config/valeurs-cilium.yaml   # fichier de la 08c, posé par etape_h5_cilium
EXPORT=$R/j7-a-sec/valeurs-export.yaml                       # export proposé à l'étape 1
FICHIER=/var/run/cilium/hubble/builds.log                   # filePath de l'exportateur builds (hostPath cilium-run)
TGZ=$O/telechargements/cilium/cilium-1.20.4.tgz

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echec() { echo "KO   $*" >&2; exit 1; }
filtre() { sed "$MASQUE"; }
present() { kubectl get pod -n builds "$1" -o name < /dev/null > /dev/null 2>&1; }

pod_json() { # nom label|- : pod d'essai Kata, forme des pods de R7 (m1b-r1r8.sh), sans PVC ; label de tâche seulement si demandé
  jq -n --arg n "$1" --arg lb "$2" --arg i "$IMAGE_OUTILLAGE" --arg j "$N" --argjson z "$ZONE" \
    --argjson sc "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .securityContext' "$TACHE")" \
    --argjson res "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .resources' "$TACHE")" '
    {apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds",
       labels: ({"poc.test/jalon": $j} + (if $lb == "-" then {} else {"tekton.dev/task": $lb} end))},
     spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, enableServiceLinks: false,
       runtimeClassName: "kata",
       volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: "1Gi"}}],
       containers: [{name: "essai", image: $i, command: ["sleep", "900"], securityContext: $sc, resources: $res,
         volumeMounts: [{name: "w", mountPath: "/w"}]}]} + $z)}' > "$T/pod-$1.json"
}

rendre() {
  pod_json "$N-a" -
  pod_json "$N-b" "$LABEL_CONSTRUIRE"
  attendu "labels de tâche (a, b)" "$(jq -r '.metadata.labels["tekton.dev/task"] // "-"' "$T/pod-$N-a.json" "$T/pod-$N-b.json" | paste -sd' ')" "- $LABEL_CONSTRUIRE"
  attendu "contexte du conteneur, celui du pas signé" "$(jq -cS '.spec.containers[0].securityContext' "$T/pod-$N-b.json")" \
    "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .securityContext' "$TACHE" | jq -cS .)"
}

# Témoins du pod : ceux de construire-rpm (lignes 76 à 82 de construire-rpm.yaml) pour b ; TCP vers Zot seul pour a
temoins() { # a|b : script des témoins, codes sur la sortie
  if [ "$1" = a ]; then
    printf '%s\n' 'r=0; timeout 10 bash -c "exec 3<>/dev/tcp/'"$ZOT_CIBLE"'" 2> /dev/null || r=$?; echo "J7-POD tcp '"$ZOT_CIBLE"' code $r"'
  else
    printf '%s\n' 'r=0; timeout 10 getent hosts dl.rockylinux.org > /dev/null 2>&1 || r=$?; echo "J7-POD dns dl.rockylinux.org code $r"' \
      'for c in 192.168.161.13/5000 192.168.161.13/3000 199.232.170.132/80; do r=0; timeout 10 bash -c "exec 3<>/dev/tcp/$c" 2> /dev/null || r=$?; echo "J7-POD tcp $c code $r"; done'
  fi
}

agent_build() { kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=sc-build -o jsonpath='{.items[0].metadata.name}' < /dev/null; }

comptes() { # fichier-json-lignes libellé ip-du-pod : comptes seulement (aucun flux brut n'est affiché ni archivé)
  jq -rs --arg l "$2" --arg ip "$3" '
    def c(f): (map(f // "-" | tostring) | group_by(.) | map("\(.[0])=\(length)") | join(" "));
    def dst: (.IP.destination // "-") + ":" + ((.l4.TCP.destination_port // .l4.UDP.destination_port // "-") | tostring);
    def proto: (.l4 // {} | keys | join(",")) as $k | if $k == "" then "-" else $k end;
    (map(select(.flow == null)) | length) as $sansflux |
    map(select(.flow != null) | .flow) |
    "\($l) : \(length) flux ; lignes sans flow (lost_events, autres) : \($sansflux)",
    "  verdict : \(c(.verdict))",
    "  drop_reason_desc : \(c(.drop_reason_desc))",
    "  event_type.type : \(c(.event_type.type))",
    "  verdict × sens × is_reply × source=pod : \(c("\(.verdict)|\(.traffic_direction // "-")|\(if .is_reply == null then "-" else (.is_reply | tostring) end)|\(if .IP.source == $ip then "pod" else "autre" end)"))",
    "  protocole × destination : \(c("\(proto)|\(dst)"))",
    "  horodatages distincts par destination : \(group_by(dst) | map("\(.[0] | dst)=\(map(.time) | unique | length)") | join(" "))",
    "  source.namespace/pod_name : \(c((.source.namespace // "∅") + "/" + (.source.pod_name // "∅")))",
    "  destination.namespace/pod_name : \(c((.destination.namespace // "∅") + "/" + (.destination.pod_name // "∅")))",
    "  sortants du pod non DROPPED : \(map(select(.traffic_direction == "EGRESS" and .IP.source == $ip and .verdict != "DROPPED")) | length)",
    "  sortants du pod FORWARDED vers Zot : \(map(select(.traffic_direction == "EGRESS" and .IP.source == $ip and .verdict == "FORWARDED" and dst == "192.168.161.13:5000")) | length)"' "$1"
}

catalogue() { # nombre de dépôts du catalogue de Zot, lecture anonyme ; échec si crane échoue ou si le compte est nul
  local n
  mkdir -p "$T/anonyme"
  n=$(DOCKER_CONFIG=$T/anonyme SSL_CERT_FILE=$P/ca-poc.crt crane catalog "$REG_HOTE" < /dev/null | grep -c .) || echec "catalogue de Zot illisible"
  [ "$n" -gt 0 ] || echec "catalogue de Zot vide"
  echo "$n"
}

observer() { # agent depuis fichier filtre… : hubble observe dans l'agent ; arrêt sur un code non nul (jamais de « 0 flux » par échec)
  local a=$1 d=$2 f=$3 rc=0; shift 3
  kubectl -n kube-system exec "$a" -c cilium-agent -- hubble observe --since "$d" -o json "$@" < /dev/null > "$f" 2> "$f.err" || rc=$?
  echo "hubble observe $* : code $rc, $(grep -c . "$f" || true) ligne(s), $(grep -c . "$f.err" || true) ligne(s) d'erreur"
  [ "$rc" = 0 ] || { filtre < "$f.err" | head -n 3 | cut -c1-200; echec "hubble observe en échec"; }
}

nettoyer() { # pods du jalon supprimés et flux bruts effacés, en fin d'étape comme sur arrêt
  kubectl delete pod -n builds -l "poc.test/jalon=$N" --wait=true < /dev/null > /dev/null 2>&1 || true
  find "$T" -maxdepth 1 -name 'hubble-*' -delete
  echo "nettoyage : pods du jalon restants $(kubectl get pod -n builds -l "poc.test/jalon=$N" -o name < /dev/null | wc -l), flux bruts de $T effacés"
}

etape_sec() { # rien n'est créé : dry-run serveur (admission comprise)
  local p
  rendre
  for p in "$N-a" "$N-b"; do
    ! present "$p" || echec "pod $p déjà présent : relancer sous un autre PREFIXE"
    kubectl create --dry-run=server -f "$T/pod-$p.json" -o json < /dev/null > "$T/sec-$p.json" 2> "$T/sec-$p.err" \
      || { filtre < "$T/sec-$p.err" | cut -c1-300; echec "pod $p refusé en dry-run serveur"; }
    echo "OK   $p admis à blanc : $(jq -r '[.spec.runtimeClassName, .spec.nodeSelector.zone, (.metadata.labels["tekton.dev/task"] // "sans label de tâche"), .spec.containers[0].image[-19:]] | join(" ; ")' "$T/sec-$p.json")"
  done
  echo "agent Cilium de sc-build : $(agent_build) (aucun exec à cette étape)"
}

etape_mesure() { # ACCORD NOMMÉ : kubectl exec dans l'agent Cilium de sc-build (hubble observe, date ; lecture seule, comptes)
  local c p ip t0 a k0 k1 n
  rendre
  for p in "$N-a" "$N-b"; do ! present "$p" || echec "pod $p déjà présent : relancer sous un autre PREFIXE"; done
  trap nettoyer EXIT
  a=$(agent_build); echo "agent Cilium de sc-build : $a"
  echo "horloge : agent de sc-build moins hôte = $(( $(kubectl -n kube-system exec "$a" -c cilium-agent -- date -u +%s < /dev/null) - $(date -u +%s) )) s"
  k0=$(catalogue); echo "catalogue de Zot (anonyme), avant : $k0 dépôt(s)"
  for c in a b; do
    p=$N-$c
    echo "## pod $c ($(jq -r '.metadata.labels["tekton.dev/task"] // "sans label de tâche"' "$T/pod-$p.json"))"
    kubectl create -f "$T/pod-$p.json" < /dev/null > /dev/null
    t0=$(kubectl get pod -n builds "$p" -o jsonpath='{.metadata.creationTimestamp}' < /dev/null)
    echo "pod $p créé à $t0 (horloge de l'API ; début de la fenêtre de Hubble)"
    kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null || echec "pod $p non prêt"
    ip=$(kubectl get pod -n builds "$p" -o jsonpath='{.status.podIP}' < /dev/null)
    echo "pod prêt : $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName {.spec.runtimeClassName}' < /dev/null), IP $ip"
    temoins "$c" > "$T/temoins-$c.sh"
    kubectl exec -i -n builds "$p" -- bash -s < "$T/temoins-$c.sh" 2>&1 | filtre | tee "$T/temoins-$c.out"
    sleep 5
    observer "$a" "$t0" "$T/hubble-ip-$c.json" --ip "$ip"
    observer "$a" "$t0" "$T/hubble-pod-$c.json" --pod "builds/$p"
    comptes "$T/hubble-ip-$c.json" "Hubble, filtre --ip $ip (comme la 08)" "$ip"
    comptes "$T/hubble-pod-$c.json" "Hubble, filtre --pod builds/$p (celui de l'export)" "$ip"
    kubectl delete pod -n builds "$p" --wait=true < /dev/null > /dev/null; echo "pod $p supprimé à $(date -u +%H:%M:%S)"
    if [ "$c" = a ]; then   # témoin positif (T0) : sans lui, « aucun flux autorisé » du pod b ne prouverait rien
      n=$(jq -s --arg ip "$ip" '[.[] | .flow | select(. != null and .traffic_direction == "EGRESS" and .IP.source == $ip and .verdict == "FORWARDED")] | length' "$T/hubble-ip-$c.json")
      [ "$n" -ge 1 ] || echec "T0 : aucun flux sortant FORWARDED du pod a dans Hubble ; arrêt avant le pod b"
      echo "OK   T0 : $n flux sortant(s) FORWARDED du pod a"
    fi
  done
  k1=$(catalogue); attendu "catalogue de Zot (anonyme), après" "$k1" "$k0"
}

# --- étape 4a ------------------------------------------------------------------------------------------------------------
valeurs_j7() { # fichier combiné : 08c puis export ; clés de tête distinctes (même motif que valeurs_h6 de la 08c)
  cat "$V08C" "$EXPORT" > "$T/valeurs-j7.yaml"
  attendu "clés de tête du fichier combiné" "$(yq -r 'keys | join(" ")' "$T/valeurs-j7.yaml")" "hostFirewall policyAuditMode tls hubble"
}

rendu() { # sortie fichiers-de-valeurs… : helm template hors ligne, valeurs de cilium.sh (08, 08b) puis les fichiers donnés
  local o=$1; shift
  sed -e "s#@CILIUM_AMD64@#sha256:fa56fecd779584642c7ec2da6872c03c45c1f1043da66665a73ed8c425584d54#" \
      -e "s#@OPERATOR_AMD64@#sha256:77a9b4371faed41dc9c2fb3942b6c02a581158be1d4aa46a0e62956ce2f55ff1#" \
      "$here/cilium/valeurs.yaml" | grep -v '^#' > "$T/valeurs-08.yaml"
  local f=(-f "$T/valeurs-08.yaml" -f "$h19b/../08b-rke2/config/valeurs-cilium.yaml") v
  for v in "$@"; do f+=(-f "$v"); done
  helm template cilium "$TGZ" --namespace kube-system "${f[@]}" | yq -o=json -I=0 '.' \
    | jq -c 'select(. != null and .kind != "Secret")' | jq -sc 'sort_by(.kind, .metadata.name)' > "$o"
}

garde_fenetre() { # pose et retour redémarrent les agents des trois nœuds : hors des scans de G7 et des balayages de Zot
  local j m
  j=$(date -u +%Y-%m-%d); m=$(( 10#$(date -u +%H) * 60 + 10#$(date -u +%M) ))
  [ "$m" -lt 480 ] || [ "$m" -gt 690 ] || echec "fenêtre refusée : entre 08:00 et 11:30 UTC (import de la base grype, scans de G7)"
  case $j in
    2026-11-21) [ "$m" -lt 1290 ] || [ "$m" -gt 1365 ] || echec "fenêtre refusée : balayage n°2 de Zot (21/11, 21:30 à 22:45 UTC)" ;;
    2026-11-22) [ "$m" -lt 1335 ] || [ "$m" -gt 1410 ] || echec "fenêtre refusée : balayage n°3 de Zot (22/11, 22:15 à 23:30 UTC)" ;;
    2026-11-2[0-2]) ;;
    *) echec "fenêtre non calculée pour $j : recalculer les balayages de Zot avant de poser" ;;
  esac
  echo "OK   fenêtre : $(date -u +%Y-%m-%dT%H:%M:%SZ), hors de 08:00 à 11:30 UTC et hors des balayages n°2 et n°3"
}

reprendre_rattrapage() { kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":false}}' < /dev/null > /dev/null; echo "rattrapage repris"; }
suspendre_rattrapage() { # comme etape_h5_cilium (08c) : aucun passage ni PipelineRun actif pendant les redémarrages
  local n
  kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":true}}' < /dev/null > /dev/null
  trap reprendre_rattrapage EXIT
  for _ in $(seq 60); do [ -z "$(kubectl get cronjob -n declencheurs rattrapage -o jsonpath='{.status.active}' < /dev/null)" ] && break; sleep 2; done
  n=$(kubectl get pipelineruns -n builds -o json < /dev/null | jq '[.items[] | select(.status.completionTime == null)] | length')
  [ "$n" = 0 ] || echec "$n PipelineRun(s) actif(s) : pose reportée"
  echo "OK   rattrapage suspendu, aucun PipelineRun actif"
}

versions_certs() { kubectl get secret -n kube-system cilium-ca hubble-server-certs --no-headers -o custom-columns=N:.metadata.name,V:.metadata.resourceVersion < /dev/null | tr -s ' ' | paste -sd' ' -; }   # 08c ; aucune valeur affichée
redemarrages() { # hors pods de Cilium, recréés par cilium.sh appliquer (compteurs remis à zéro)
  kubectl get pods -A -o json < /dev/null | jq '[.items[] | select((.metadata.labels["k8s-app"] // "") != "cilium" and (.metadata.labels["io.cilium/app"] // "") != "operator") | .status.containerStatuses[]?.restartCount] | add // 0'
}
exige_rke2() { # cilium.sh choisit ses fichiers par DISTRO (défaut k3s dans distro.sh) : sans rke2, --reset-values retirerait le fichier de la 08b
  [ "$DISTRO" = rke2 ] || echec "DISTRO=$DISTRO : lancer avec DISTRO=rke2 (sinon la pose retirerait kubeProxyReplacement de la 08b)"
  echo "OK   DISTRO=rke2"
}
agent_de() { kubectl get pods -n kube-system -l k8s-app=cilium --field-selector "spec.nodeName=$1" -o jsonpath='{.items[0].metadata.name}' < /dev/null; }
cfg() { kubectl -n kube-system get cm cilium-config -o json < /dev/null; }
fichier_export() { # nœud : état du fichier d'export dans l'agent du nœud (ls ; absent si aucun)
  kubectl -n kube-system exec "$(agent_de "$1")" -c cilium-agent -- sh -c "ls -l --time-style=+%H:%M:%S $(dirname "$FICHIER") 2>/dev/null | grep -c 'builds' ; wc -c 2>/dev/null < $FICHIER || echo absent" < /dev/null | paste -sd' ' -
}

apres_pose() { # contrôles communs à pose et retour : nœuds, API, Zot, agents, Hubble, certificats, redémarrages
  local c0=$1 r0=$2 p v
  kubectl wait --for=condition=Ready node --all --timeout=120s < /dev/null > /dev/null
  attendu "API" "$(kubectl get --raw /readyz < /dev/null || true)" ok
  v=$(curl -k -s -o /dev/null --max-time 8 -w '%{http_code}' "https://$REG_HOTE/v2/" < /dev/null || true)
  [ "${v:-000}" != 000 ] && echo "OK   Zot joignable depuis l'hôte : HTTP $v" || echec "Zot injoignable depuis l'hôte"
  attendu "certificats de Cilium et de Hubble (versions d'objet)" "$(versions_certs)" "$c0"
  sleep 30
  while read -r p; do
    attendu "$p, état" "$(kubectl exec -n kube-system "$p" -c cilium-agent -- cilium-dbg status --brief < /dev/null 2>&1 | tail -1)" OK
    attendu "$p, Hubble" "$(kubectl exec -n kube-system "$p" -c cilium-agent -- cilium-dbg status < /dev/null 2> /dev/null | awk '$1 == "Hubble:" {print $2}')" Ok
  done < <(kubectl get pods -n kube-system -l k8s-app=cilium -o json < /dev/null | jq -r '.items[].metadata.name')
  attendu "redémarrages de conteneurs du cluster, hors pods de Cilium" "$(redemarrages)" "$r0"
  attendu "redémarrages des pods de Cilium recréés" "$(kubectl get pods -n kube-system -l k8s-app=cilium -o json < /dev/null | jq '[.items[].status.containerStatuses[].restartCount] | add')" 0
  attendu "enable-host-firewall" "$(cfg | jq -r '.data["enable-host-firewall"]')" true
}

etape_pose_sec() { # rien n'est posé
  valeurs_j7
  rendu "$T/rendu-combine.json" "$T/valeurs-j7.yaml"
  rendu "$T/rendu-separe.json" "$V08C" "$EXPORT"
  rendu "$T/rendu-actuel.json" "$V08C"
  attendu "rendu du fichier combiné = rendu de l'étape 1 (fichiers séparés), hors Secrets" "$(sha256sum < "$T/rendu-combine.json" | cut -c1-16)" "$(sha256sum < "$T/rendu-separe.json" | cut -c1-16)"
  attendu "objets ajoutés par l'export" "$(jq -r --slurpfile a "$T/rendu-actuel.json" '[.[] | "\(.kind)/\(.metadata.name)"] - [$a[0][] | "\(.kind)/\(.metadata.name)"] | join(" ")' "$T/rendu-combine.json")" "ConfigMap/cilium-flowlog-config"
  attendu "cilium-config rendu actuel = cilium-config vivant (clés et valeurs)" \
    "$(jq -cS '.[] | select(.kind == "ConfigMap" and .metadata.name == "cilium-config") | .data' "$T/rendu-actuel.json" | sha256sum | cut -c1-16)" "$(cfg | jq -cS '.data' | sha256sum | cut -c1-16)"
  attendu "clés de cilium-config : vivant, puis après la pose" "$(cfg | jq '.data | length') $(jq '.[] | select(.kind == "ConfigMap" and .metadata.name == "cilium-config") | .data | length' "$T/rendu-combine.json")" "163 164"
  echo "commande de pose   : VALEURS_08C=$T/valeurs-j7.yaml $here/cilium.sh appliquer" | sed "s#$HOME#~#g"
  echo "commande de retour : VALEURS_08C=$V08C $here/cilium.sh appliquer   (celle de etape_h5_cilium)" | sed "s#$HOME#~#g"
  ( garde_fenetre ) || echo "information : la fenêtre actuelle serait refusée"
  ( exige_rke2 ) || echo "information : DISTRO=$DISTRO ici ; pose et retour exigent DISTRO=rke2"
}

etape_pose() { # ACCORD NOMMÉ : valeurs de Cilium (export), redémarrage des agents des trois nœuds
  local c0 r0
  exige_rke2
  garde_fenetre
  echo "en cas de KO après cilium.sh : l'export peut rester posé ; retour : DISTRO=rke2 [FORCER_RETOUR=1] j7.sh retour"
  valeurs_j7
  attendu "export absent avant la pose" "$(cfg | jq -r '.data | has("hubble-flowlogs-config-path")')" false
  c0=$(versions_certs); r0=$(redemarrages)
  suspendre_rattrapage
  date -u '+pose %H:%M:%S UTC'
  VALEURS_08C=$T/valeurs-j7.yaml "$here/cilium.sh" appliquer < /dev/null
  date -u '+agents prêts %H:%M:%S UTC'
  apres_pose "$c0" "$r0"
  attendu "E1 : clés de cilium-config, hubble-flowlogs-config-path" "$(cfg | jq -r '"\(.data | length) \(.data["hubble-flowlogs-config-path"])"')" "164 /flowlog-config/flowlogs.yaml"
  attendu "E2 : exportateurs de cilium-flowlog-config" "$(kubectl -n kube-system get cm cilium-flowlog-config -o jsonpath='{.data.flowlogs\.yaml}' < /dev/null | yq -r '[.flowLogs[].name] | join(" ")')" builds
  echo "E3 : sc-build : $(fichier_export sc-build)"
  echo "E6 : sc-confiance : $(fichier_export sc-confiance) ; sc-stockage : $(fichier_export sc-stockage)"
}

lire_export() { # nœud depuis : copie du fichier d'export du nœud dans $T (effacée par nettoyer), lignes depuis l'heure donnée ;
  # arrêt si l'exec échoue (jamais de « 0 flux » par échec) ; lignes non JSON (dernière ligne coupée) comptées, pas fatales
  local rc=0
  kubectl -n kube-system exec "$(agent_de "$1")" -c cilium-agent -- cat "$FICHIER" < /dev/null > "$T/hubble-export-$1.json" 2> "$T/hubble-export-$1.err" || rc=$?
  [ "$rc" = 0 ] || { filtre < "$T/hubble-export-$1.err" | head -n 3 | cut -c1-200; echec "lecture du fichier d'export de $1 en échec (code $rc)"; }
  echo "fichier d'export de $1 : $(grep -c . "$T/hubble-export-$1.json" || true) ligne(s), dont non JSON : $(jq -R 'fromjson? // "NONJSON" | select(. == "NONJSON")' "$T/hubble-export-$1.json" | grep -c . || true)"
  jq -cR --arg d "$2" 'fromjson? | select(.time[:19] >= $d[:19])' "$T/hubble-export-$1.json" > "$T/hubble-export-$1-depuis.json"
}

etape_export() { # ACCORD NOMMÉ : pods d'essai, kubectl exec dans les agents (hubble observe, lecture du fichier d'export)
  local c p ip t0 tp a n
  attendu "export posé" "$(cfg | jq -r '.data["hubble-flowlogs-config-path"]')" /flowlog-config/flowlogs.yaml
  rendre
  for p in "$N-a" "$N-b"; do ! present "$p" || echec "pod $p déjà présent : relancer sous un autre PREFIXE"; done
  trap nettoyer EXIT
  a=$(agent_build); echo "agent Cilium de sc-build : $a"
  echo "fichier d'export avant : sc-build $(fichier_export sc-build)"
  tp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for c in a b; do
    p=$N-$c
    echo "## pod $c ($(jq -r '.metadata.labels["tekton.dev/task"] // "sans label de tâche"' "$T/pod-$p.json"))"
    kubectl create -f "$T/pod-$p.json" < /dev/null > /dev/null
    t0=$(kubectl get pod -n builds "$p" -o jsonpath='{.metadata.creationTimestamp}' < /dev/null)
    echo "pod $p créé à $t0"
    kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null || echec "pod $p non prêt"
    ip=$(kubectl get pod -n builds "$p" -o jsonpath='{.status.podIP}' < /dev/null)
    echo "pod prêt : $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName {.spec.runtimeClassName}' < /dev/null), IP $ip"
    echo "invité Kata : $(kubectl exec -n builds "$p" -- sh -c 'for k in tcp_syn_retries tcp_syn_linear_timeouts; do printf "%s=%s " $k "$(cat /proc/sys/net/ipv4/$k 2>/dev/null || echo absent)"; done; uname -r' < /dev/null)"
    temoins "$c" > "$T/temoins-$c.sh"
    kubectl exec -i -n builds "$p" -- bash -s < "$T/temoins-$c.sh" 2>&1 | filtre | tee "$T/temoins-$c.out"
    sleep 5
    observer "$a" "$t0" "$T/hubble-ip-$c.json" --ip "$ip"
    comptes "$T/hubble-ip-$c.json" "Hubble, filtre --ip $ip" "$ip"
    echo "  drapeaux TCP des flux du pod : $(jq -rs --arg ip "$ip" '[.[] | .flow | select(. != null and .IP.source == $ip) | (.l4.TCP.flags // {} | keys | join(","))] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' "$T/hubble-ip-$c.json")"
    echo "  motif × destination : $(jq -rs '[.[] | .flow | select(. != null) | "\(.drop_reason_desc // "-")|\(.IP.destination):\(.l4.TCP.destination_port // .l4.UDP.destination_port // "-")"] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' "$T/hubble-ip-$c.json")"
    lire_export sc-build "$t0"
    n=$(jq -s --arg ip "$ip" '[.[] | .flow | select(. != null and (.IP.source == $ip or .IP.destination == $ip))] | length' "$T/hubble-export-sc-build-depuis.json")
    comptes "$T/hubble-export-sc-build-depuis.json" "fichier d'export de sc-build depuis $t0 (préfixe builds/)" "$ip"
    echo "  T9 (préfixe) : flux du pod dans le fichier $n ; dans hubble observe --ip $(grep -c . "$T/hubble-ip-$c.json" || true)"
    kubectl delete pod -n builds "$p" --wait=true < /dev/null > /dev/null; echo "pod $p supprimé à $(date -u +%H:%M:%S)"
  done
  sleep 5
  lire_export sc-build "$tp"
  echo "## E4, E5 : fichier de sc-build depuis $tp"
  echo "lignes : $(grep -c . "$T/hubble-export-sc-build-depuis.json" || true) ; octets : $(wc -c < "$T/hubble-export-sc-build-depuis.json")"
  echo "clés de tête : $(jq -r 'keys | join(",")' "$T/hubble-export-sc-build-depuis.json" | sort | uniq -c | awk '{print $2 "=" $1}' | paste -sd' ' -)"
  echo "champs de flow : $(jq -r '.flow // {} | keys[]' "$T/hubble-export-sc-build-depuis.json" | sort | uniq -c | awk '{print $2 "=" $1}' | paste -sd' ' -)"
  echo "verdict au format nom : $(jq -r '.flow.verdict // empty' "$T/hubble-export-sc-build-depuis.json" | sort -u | paste -sd' ' -)"
  echo "sources hors de builds : $(jq -r 'select(.flow != null) | .flow | select((.source.namespace // "") != "builds" and (.destination.namespace // "") != "builds") | 1' "$T/hubble-export-sc-build-depuis.json" | grep -c . || true)"
  echo "## fichier entier et rotation"
  echo "sc-build : $(fichier_export sc-build) ; fichiers tournés : $(kubectl -n kube-system exec "$a" -c cilium-agent -- sh -c "ls $(dirname "$FICHIER") | grep -c '^builds-'" < /dev/null || true)"
  echo "E6 : sc-confiance : $(fichier_export sc-confiance) ; sc-stockage : $(fichier_export sc-stockage)"
}

etape_retour() { # ACCORD NOMMÉ : valeurs de la 08c seules (commande de etape_h5_cilium), redémarrage des agents
  local c0 r0
  exige_rke2
  if [ "${FORCER_RETOUR:-0}" = 1 ]; then echo "ATTENTION fenêtre non contrôlée : FORCER_RETOUR=1 ($(date -u +%Y-%m-%dT%H:%M:%SZ))"; else garde_fenetre; fi
  c0=$(versions_certs); r0=$(redemarrages)
  suspendre_rattrapage
  date -u '+retour %H:%M:%S UTC'
  VALEURS_08C=$V08C "$here/cilium.sh" appliquer < /dev/null
  date -u '+agents prêts %H:%M:%S UTC'
  apres_pose "$c0" "$r0"
  attendu "clés de cilium-config, export retiré" "$(cfg | jq -r '"\(.data | length) \(.data | has("hubble-flowlogs-config-path"))"')" "163 false"
  attendu "ConfigMap cilium-flowlog-config" "$(kubectl -n kube-system get cm cilium-flowlog-config --ignore-not-found -o name < /dev/null)" ""
  echo "fichier d'export laissé sur sc-build (tmpfs /run probable, non lu) : $(fichier_export sc-build)"
}

for e in "$@"; do [ ! -e "$R/$N-$e.log" ] || { echo "journal déjà présent : resultats/$N-$e.log (relancer sous un autre PREFIXE)" >&2; exit 2; }; done
lancer "$N" "19b J7" "$@"
