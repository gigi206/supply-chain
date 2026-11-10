#!/usr/bin/env bash
# Brique 06, diagnostic du blocage de kubectl exec sous Kata (préparé à sec le 10/11/2026, NON LANCÉ), à la demande du propriétaire
# (« il faut trouver ce qu'il se passe », 18:21:02 UTC). Mesuré en S3 (resultats/s3-sonde.log) : sous Kata 4.3.1, une copie de
# 512 Mio par l'entrée standard de kubectl exec arrive entière dans le pod, mais l'exec ne rend pas la main en 120 s (WebSocket et
# SPDY) ; 64 Mio passe ; sous runc, 512 Mio passe en 3,6 s. Prédictions : resultats/diag-exec-predictions.md, écrites et commitées
# avant toute exécution.
#   pod        un pod Kata privilégié, UID 1000, sans label, image d'essai de s1b (forme des builds de S3), dans builds sur sc-build,
#              supprimé à la fin de l'étape ; trois mesures, dans l'ordre :
#              taille       copies de 128 puis 256 Mio à plein débit, un seul exec chacune (délai de 150 s) : code, durée, octets reçus
#              duree        32 Mio envoyés lentement, en 32 envois de 1 Mio espacés de 2,8 s (environ 90 s), un seul exec (délai de
#                           150 s) : une durée longue suffit-elle à bloquer, à petite taille ?
#              instantane   512 Mio en arrière-plan (délai de 240 s) ; à 100 s, relevé dans le pod par un second exec (processus
#                           vivants lus dans /proc : pid, état, ligne de commande ; taille du fichier) et sur l'hôte (position et
#                           ouverture de l'entrée standard de kubectl) ; puis code final ; fenêtre horaire gardée pour l'étape noeud
#   noeud      lecture sur la VM sc-build, par ssh, dans la fenêtre de la mesure instantane : lignes de containerd.log de RKE2 et du
#              journal système qui citent kata, le shim, l'exec ou les E/S (run_io_copy, wait, exit, CloseIO, stdin), lignes
#              jeton|token retirées, 300 caractères au plus ; rien n'est modifié sur la VM
# Rien n'est écrit dans Zot ni sur les VM.
# Additif du 10/11/2026, 18:47 UTC : étapes pod (18:27 UTC), releve et noeud (18:41 à 18:43 UTC) lancées, code 0 ; étape croise
# ajoutée à sec, NON LANCÉE (resultats/diag-exec-predictions.md) :
#   croise     (a) pod runc restricted, 128 Mio envoyés à plein débit, lus dans le pod à environ 10 Mio/s (dd de 1 Mio avec
#              iflag=fullblock, puis sleep 0.1, 128 fois) : un consommateur lent suffit-il à bloquer hors de Kata ?
#              (b) pod Kata, 128 Mio envoyés à environ 5 Mio/s (1 Mio toutes les 0,2 s), sous le débit du pod : la taille totale
#              bloque-t-elle sans données en attente dans la chaîne ? Un seul exec par mesure, délai de 150 s.
#
# Usage (racine du dépôt, sous bash pour relever le code) :
#   DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/diag-exec-kata.sh <étape>…   (journal : resultats/diag-exec-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
IMAGE_DIGEST=sha256:d8041f9cf7254a1e73523dc1b01e4065c0c9f9f4e7f8c9dc4e3c5fd656f495a1          # essais-06/sbuild-debian13:s1b
IMAGE=$REG/essais-06/sbuild-debian13@$IMAGE_DIGEST
LIMITES='{"cpu": "2", "memory": "6Gi"}'
TMPFS=4Gi
PRIVILEGIE='{"privileged": true, "allowPrivilegeEscalation": true}'
POD=diag-exec-kata
T=$W/diag-exec
mkdir -p "$T"
umask 022

pod_spec() { # nom runtimeClass image uid contexte-JSON (forme des pods de s3.sh, sans label)
  jq -n --arg n "$1" --arg rc "$2" --arg i "$3" --argjson u "$4" --argjson sc "$5" --argjson l "$LIMITES" --arg t "$TMPFS" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds"},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: $u, runAsGroup: $u, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: $t}}],
      containers: [{name: "diag", image: $i, command: ["sleep", "7200"], securityContext: $sc,
        resources: {requests: $l, limits: $l}, volumeMounts: [{name: "w", mountPath: "/w"}]}],
      runtimeClassName: $rc}}' > "$T/$1.json"
}

pod_retirer() { kubectl delete pod -n builds "$1" --wait=false </dev/null >/dev/null; echo "pod $1 supprimé"; }

ms() { echo $(( $(date +%s%N) / 1000000 )); }
heure() { date -u +%H:%M:%S; }
recu() { kubectl exec -n builds "$POD" -- stat -c %s "$1" </dev/null 2>/dev/null || echo "?"; }

alea() { # Mio : fichier aléatoire sur l'hôte
  local f=$T/alea-$1.bin
  [ -s "$f" ] || head -c $(($1 * 1048576)) /dev/urandom > "$f"
  echo "$f"
}

copie() { # libellé fichier délai : un seul exec, entrée standard depuis le fichier
  local n rc=0 t0 c=/w/$1
  n=$(stat -c %s "$2"); t0=$(ms)
  timeout "$3" kubectl exec -i -n builds "$POD" -- sh -c "head -c $n > $c" < "$2" 2>"$T/err" || rc=$?
  echo "$1 : $n octets, code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(recu "$c") $(grep -i -v -E 'jeton|token' "$T/err" | head -c 200 | tr '\n' ' ')"
  kubectl exec -n builds "$POD" -- rm -f "$c" </dev/null || true
}

PROCESSUS='for p in /proc/[0-9]*; do
  [ -r "$p/cmdline" ] || continue
  c=$(tr "\0" " " < "$p/cmdline"); [ -n "$c" ] || continue
  echo "     processus ${p#/proc/} état $(awk "{print \$3}" "$p/stat") : $c"
done'

etape_pod() {
  local f n t0 pid rc=0 k
  pod_spec "$POD" kata "$IMAGE" 1000 "$PRIVILEGIE"
  kubectl delete pod -n builds "$POD" --ignore-not-found --wait=true </dev/null >/dev/null
  kubectl create -f "$T/$POD.json" </dev/null >/dev/null
  kubectl wait -n builds "pod/$POD" --for=condition=Ready --timeout=300s </dev/null >/dev/null \
    || { pod_retirer "$POD"; echo "KO   pod non prêt" >&2; exit 1; }
  echo "### $POD (kata, uid 1000, sans label) : prêt à $(heure) UTC ; kubectl : $(kubectl version --client 2>/dev/null | head -1)"

  echo "## taille (plein débit, un exec par copie, délai de 150 s)"
  copie taille-128 "$(alea 128)" 150
  copie taille-256 "$(alea 256)" 150

  echo "## duree (32 Mio en 32 envois de 1 Mio espacés de 2,8 s, un seul exec, délai de 150 s)"
  f=$(alea 32); n=$(stat -c %s "$f"); t0=$(ms); rc=0
  { for ((k = 0; k < 32; k++)); do dd if="$f" bs=1M skip=$k count=1 status=none; sleep 2.8; done; } \
    | timeout 150 kubectl exec -i -n builds "$POD" -- sh -c "head -c $n > /w/duree" 2>"$T/err" || rc=$?
  echo "duree : $n octets, code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(recu /w/duree) $(grep -i -v -E 'jeton|token' "$T/err" | head -c 200 | tr '\n' ' ')"
  kubectl exec -n builds "$POD" -- rm -f /w/duree </dev/null || true

  echo "## instantane (512 Mio, délai de 240 s, relevé à 100 s)"
  f=$(alea 512); n=$(stat -c %s "$f"); rc=0
  date -u +'%Y-%m-%d %H:%M:%S' > "$T/fenetre-instantane-debut"
  t0=$(ms)
  timeout 240 kubectl exec -i -n builds "$POD" -- sh -c "head -c $n > /w/instantane" < "$f" 2>"$T/err-instantane" &
  pid=$!
  sleep 100
  echo "relevé à $(heure) UTC, $(( ($(ms) - t0) / 1000 )) s après le lancement :"
  echo "     fichier dans le pod : $(recu /w/instantane) octets sur $n"
  kubectl exec -n builds "$POD" -- sh -c "$PROCESSUS" </dev/null 2>&1 | grep -i -v -E 'jeton|token' || true
  k=$(pgrep -P "$pid" -x kubectl || true)
  if [ -n "$k" ]; then
    echo "     kubectl (hôte, pid $k) : entrée standard $(readlink "/proc/$k/fd/0" 2>/dev/null | sed "s|$T/||") ; $(head -1 "/proc/$k/fdinfo/0" 2>/dev/null)"
  else
    echo "     kubectl (hôte) : déjà terminé"
  fi
  wait "$pid" || rc=$?
  echo "instantane : $n octets, code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(recu /w/instantane) $(grep -i -v -E 'jeton|token' "$T/err-instantane" | head -c 200 | tr '\n' ' ')"
  date -u +'%Y-%m-%d %H:%M:%S' > "$T/fenetre-instantane-fin"
  echo "fenêtre gardée pour l'étape noeud : $(cat "$T/fenetre-instantane-debut") à $(cat "$T/fenetre-instantane-fin") UTC"
  pod_retirer "$POD"
}

# Étape releve (ajoutée à sec le 10/11/2026 à 18:39 UTC, NON LANCÉE) : G4 non mesurée par l'étape pod (filtre grep sans -a,
# sortie tronquée). 128 Mio (bloque, mesuré) en arrière-plan, délai de 120 s ; à 60 s, relevé brut gardé puis affiché par grep -a :
# processus du pod (pid, état, ligne de commande, descripteurs 0 à 2), taille du fichier, entrée standard de kubectl sur l'hôte.
PROCESSUS_FD='for p in /proc/[0-9]*; do
  [ -r "$p/cmdline" ] || continue
  c=$(tr "\0" " " < "$p/cmdline" | tr -cd "[:print:]"); [ -n "$c" ] || continue
  echo "     processus ${p#/proc/} état $(awk "{print \$3}" "$p/stat") : $c"
  for d in 0 1 2; do echo "       fd $d -> $(readlink "$p/fd/$d" 2>&1 | tr -cd "[:print:]")"; done
done'

etape_releve() {
  local f n t0 pid rc=0 k
  pod_spec "$POD" kata "$IMAGE" 1000 "$PRIVILEGIE"
  kubectl delete pod -n builds "$POD" --ignore-not-found --wait=true </dev/null >/dev/null
  kubectl create -f "$T/$POD.json" </dev/null >/dev/null
  kubectl wait -n builds "pod/$POD" --for=condition=Ready --timeout=300s </dev/null >/dev/null \
    || { pod_retirer "$POD"; echo "KO   pod non prêt" >&2; exit 1; }
  echo "### $POD (kata, uid 1000, sans label) : prêt à $(heure) UTC"
  f=$(alea 128); n=$(stat -c %s "$f")
  date -u +'%Y-%m-%d %H:%M:%S' > "$T/fenetre-releve-debut"
  t0=$(ms)
  timeout 120 kubectl exec -i -n builds "$POD" -- sh -c "head -c $n > /w/releve" < "$f" 2>"$T/err-releve" &
  pid=$!
  sleep 60
  echo "relevé à $(heure) UTC, $(( ($(ms) - t0) / 1000 )) s après le lancement :"
  echo "     fichier dans le pod : $(recu /w/releve) octets sur $n"
  kubectl exec -n builds "$POD" -- sh -c "$PROCESSUS_FD" </dev/null > "$T/releve.brut" 2>&1 || true
  grep -a -i -v -E 'jeton|token' "$T/releve.brut" || true
  k=$(pgrep -P "$pid" -x kubectl || true)
  [ -n "$k" ] && echo "     kubectl (hôte, pid $k) : entrée standard $(readlink "/proc/$k/fd/0" 2>/dev/null | sed "s|$T/||") ; $(head -1 "/proc/$k/fdinfo/0" 2>/dev/null)" \
    || echo "     kubectl (hôte) : déjà terminé"
  wait "$pid" || rc=$?
  echo "releve : $n octets, code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(recu /w/releve)"
  date -u +'%Y-%m-%d %H:%M:%S' > "$T/fenetre-releve-fin"
  echo "fenêtre gardée pour l'étape noeud (FENETRE=releve) : $(cat "$T/fenetre-releve-debut") à $(cat "$T/fenetre-releve-fin") UTC"
  pod_retirer "$POD"
}

etape_noeud() {
  local d f
  local w=${FENETRE:-instantane}   # instantane (étape pod) ou releve (étape releve)
  d=$(cat "$T/fenetre-$w-debut" 2>/dev/null) && f=$(cat "$T/fenetre-$w-fin" 2>/dev/null) || { echo "KO   fenêtre $w absente" >&2; exit 1; }
  echo "## sc-build, fenêtre $d à $f UTC (lignes jeton|token retirées, 300 caractères au plus)"
  # Heures de containerd.log : champ time="…Z" (UTC, comparé en texte) ; journal système lu en UTC. Script envoyé par l'entrée
  # standard de ssh (sh -s), sans secret ; sortie filtrée sur l'hôte.
  sur sc-build "sudo sh -s '${d/ /T}' '${f/ /T}'" > "$T/noeud.brut" 2>/dev/null <<'NOEUD' || true
D=$1 F=$2
echo "### containerd.log de RKE2"
awk -v d="$D" -v f="$F" 'match($0, /time="[^"]+"/) { t = substr($0, RSTART + 6, 19); if (t >= d && t <= f) print }' \
  /var/lib/rancher/rke2/agent/containerd/containerd.log | grep -i -E 'kata|shim|exec|run_io|wait|exit|closeio|stdin' | tail -n 400
echo "### journal système"
journalctl --since "$(echo "$D" | tr T ' ') UTC" --until "$(echo "$F" | tr T ' ') UTC" -o short-iso --no-pager \
  | grep -i -E 'kata|shim|run_io|wait process|exit|closeio|stdin' | tail -n 400
NOEUD
  grep -i -v -E 'jeton|token' "$T/noeud.brut" | cut -c1-300
}

RESTREINT='{"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}}'
LECTEUR_LENT='for i in $(seq 1 128); do dd bs=1M count=1 iflag=fullblock status=none || exit 1; sleep 0.1; done > /w/croise'

croise_pod() { # runtimeClass|- contexte : pod $POD prêt
  pod_spec "$POD" "$1" "$IMAGE" 1000 "$2"
  [ "$1" = - ] && jq 'del(.spec.runtimeClassName)' "$T/$POD.json" > "$T/$POD.json.tmp" && mv "$T/$POD.json.tmp" "$T/$POD.json"
  kubectl delete pod -n builds "$POD" --ignore-not-found --wait=true </dev/null >/dev/null
  kubectl create -f "$T/$POD.json" </dev/null >/dev/null
  kubectl wait -n builds "pod/$POD" --for=condition=Ready --timeout=300s </dev/null >/dev/null \
    || { pod_retirer "$POD"; echo "KO   pod non prêt" >&2; exit 1; }
  echo "### $POD (runtimeClassName $(jq -r '.spec.runtimeClassName // "-"' "$T/$POD.json"), uid 1000, sans label) : prêt à $(heure) UTC"
}

etape_croise() {
  local f n t0 rc k
  f=$(alea 128); n=$(stat -c %s "$f")
  echo "## (a) runc restricted, envoi à plein débit, lecture lente dans le pod"
  croise_pod - "$RESTREINT"
  rc=0; t0=$(ms)
  timeout 150 kubectl exec -i -n builds "$POD" -- sh -c "$LECTEUR_LENT" < "$f" 2>"$T/err" || rc=$?
  echo "(a) : $n octets, code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(recu /w/croise) ; sha256 $([ "$(kubectl exec -n builds "$POD" -- sha256sum /w/croise </dev/null | cut -c1-64)" = "$(sha256sum < "$f" | cut -c1-64)" ] && echo conforme || echo "non conforme")"
  pod_retirer "$POD"
  kubectl wait -n builds "pod/$POD" --for=delete --timeout=120s </dev/null >/dev/null || true
  echo "## (b) Kata, envoi lent (1 Mio toutes les 0,2 s), lecture à plein débit"
  croise_pod kata "$PRIVILEGIE"
  rc=0; t0=$(ms)
  { for ((k = 0; k < 128; k++)); do dd if="$f" bs=1M skip=$k count=1 status=none; sleep 0.2; done; } \
    | timeout 150 kubectl exec -i -n builds "$POD" -- sh -c "head -c $n > /w/croise" 2>"$T/err" || rc=$?
  echo "(b) : $n octets, code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(recu /w/croise)"
  pod_retirer "$POD"
}

# Étape bisection (préparée à sec le 10/11/2026 à 19:37 UTC, NON LANCÉE) : l'étape croise met Kata hors de cause (runc, pod qui lit
# lentement 128 Mio : l'exec ne rend pas la main). Pod runc restricted, puis, sur la VM sc-build (ssh, sudo sh -s, script par l'entrée
# standard de ssh, aucun fichier écrit sur la VM), trois exec dans son conteneur, 128 Mio tirés de /dev/urandom sur le nœud, délai de
# 150 s chacun :
#   B1  crictl exec -i, lecture lente (contourne apiserver et kubelet, garde le serveur de flux CRI de containerd)
#   B2  crictl exec -i, lecture rapide (témoin)
#   B3  ctr -n k8s.io task exec, lecture lente (contourne aussi CRI : API de tâches de containerd et FIFO)
# Octets reçus relevés après chaque exec, fichier supprimé ; pod supprimé à la fin.
etape_bisection() {
  local id
  croise_pod - "$RESTREINT"
  id=$(kubectl get pod -n builds "$POD" -o jsonpath='{.status.containerStatuses[0].containerID}' </dev/null)
  id=${id#containerd://}
  [[ "$id" =~ ^[0-9a-f]{64}$ ]] || { pod_retirer "$POD"; echo "KO   identifiant de conteneur illisible" >&2; exit 1; }
  echo "conteneur : ${id:0:12}…"
  { printf 'CRICTL=%q\nCTR=%q\nID=%q\n' "$D_CRICTL" "$D_CTR" "$id"
     cat <<'BISECTION'
N=134217728
LENT='for i in $(seq 1 128); do dd bs=1M count=1 iflag=fullblock status=none || exit 1; sleep 0.1; done > /w/b'
RAPIDE="head -c $N > /w/b"
mesure() { # libellé, puis la commande d'exec
  l=$1; shift
  t0=$(date +%s%N); rc=0
  head -c $N /dev/urandom | timeout 150 "$@" > /dev/null 2>&1 || rc=$?
  d=$(( ($(date +%s%N) - t0) / 1000000 ))
  r=$($CRICTL exec "$ID" stat -c %s /w/b 2>/dev/null || echo "?")
  echo "$l : code $rc en $d ms ; reçus dans le pod : $r sur $N"
  $CRICTL exec "$ID" rm -f /w/b > /dev/null 2>&1 || true
}
echo "crictl : $($CRICTL --version 2>&1 | head -1) ; ctr : $($CTR --version 2>&1 | head -1)"
mesure "B1 crictl exec, lecture lente" $CRICTL exec -i "$ID" sh -c "$LENT"
mesure "B2 crictl exec, lecture rapide" $CRICTL exec -i "$ID" sh -c "$RAPIDE"
mesure "B3 ctr task exec, lecture lente" $CTR -n k8s.io task exec --exec-id "diag-b3-$(date +%s)" "$ID" sh -c "$LENT"
BISECTION
  } | sur sc-build "sudo sh -s" 2>&1 | grep -a -i -v -E 'jeton|token' || true
  pod_retirer "$POD"
}

# Étape amont (préparée à sec le 10/11/2026 à 19:44 UTC, NON LANCÉE) : la bisection met containerd hors de cause (crictl exec et
# ctr task exec passent avec lecture lente). Pod runc restricted ; même exec à lecture lente de 128 Mio (délai de 150 s) :
#   C1  kubectl de l'hôte (témoin dans la fenêtre : bloque d'après croise)
#   C2  kubectl de sc-confiance (D_KUBECTL : binaire de RKE2 et rke2.yaml, jamais lu), 128 Mio tirés de /dev/urandom sur
#       sc-confiance : retire le poste, son réseau et le client de l'hôte
# Puis lecture, dans la fenêtre de la mesure, du journal de kubelet sur sc-build et de celui de kube-apiserver sur sc-confiance
# (lignes qui citent exec, flux, websocket, spdy, upgrade, proxy, timeout ou stdin ; jeton|token retirés ; 300 caractères au plus).
# Rien n'est écrit sur les VM.
etape_amont() {
  local f n t0 rc d fin
  croise_pod - "$RESTREINT"
  f=$(alea 128); n=$(stat -c %s "$f")
  d=$(date -u +'%Y-%m-%dT%H:%M:%S')
  echo "## C1 kubectl de l'hôte, lecture lente"
  rc=0; t0=$(ms)
  timeout 150 kubectl exec -i -n builds "$POD" -- sh -c "$LECTEUR_LENT" < "$f" 2>"$T/err" || rc=$?
  echo "C1 : $n octets, code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(recu /w/croise)"
  kubectl exec -n builds "$POD" -- rm -f /w/croise </dev/null || true
  echo "## C2 kubectl de sc-confiance, lecture lente"
  { printf 'K=%q\nP=%q\nL=%q\n' "$D_KUBECTL" "$POD" "$LECTEUR_LENT"
     cat <<'AMONT'
t0=$(date +%s%N); rc=0
head -c 134217728 /dev/urandom | timeout 150 $K exec -i -n builds "$P" -- sh -c "$L" > /dev/null 2>&1 || rc=$?
echo "C2 : 134217728 octets, code $rc en $(( ($(date +%s%N) - t0) / 1000000 )) ms ; kubectl de sc-confiance : $($K version --client 2>/dev/null | head -1)"
AMONT
  } | sur sc-confiance "sudo sh -s" 2>&1 | grep -a -i -v -E 'jeton|token' || true
  echo "     reçus dans le pod : $(recu /w/croise)"
  fin=$(date -u +'%Y-%m-%dT%H:%M:%S')
  pod_retirer "$POD"
  echo "## journaux, fenêtre $d à $fin UTC (VM en UTC : journal système relevé en +00:00 à l'étape noeud)"
  echo "### kubelet (sc-build, $D_ETAT/agent/logs/kubelet.log)"
  sur sc-build "sudo sh -s '$d' '$fin'" 2>/dev/null <<'KUBELET' | grep -a -i -v -E 'jeton|token' | cut -c1-300 || true
d=$(echo "$1" | cut -c12-19); f=$(echo "$2" | cut -c12-19); j=$(echo "$1" | cut -c6-7)$(echo "$1" | cut -c9-10)
awk -v d="$d" -v f="$f" -v j="$j" 'substr($1, 2, 4) == j { t = substr($2, 1, 8); if (t >= d && t <= f) print }' /var/lib/rancher/rke2/agent/logs/kubelet.log \
  | grep -i -E 'exec|stream|websocket|spdy|upgrade|proxy|timeout|stdin' | tail -n 200
KUBELET
  echo "### kube-apiserver (sc-confiance, /var/log/pods)"
  sur sc-confiance "sudo sh -s '$d' '$fin'" 2>/dev/null <<'APISERVER' | grep -a -i -v -E 'jeton|token' | cut -c1-300 || true
for f in /var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log; do
  awk -v d="$1" -v f="$2" '{ t = substr($1, 1, 19); if (t >= d && t <= f) print }' "$f"
done | grep -i -E 'exec|stream|websocket|spdy|upgrade|proxy|timeout|stdin' | tail -n 200
APISERVER
}

# Étape kubelet (préparée à sec le 10/11/2026 à 19:55 UTC, NON LANCÉE) : l'étape amont situe le blocage dans l'apiserver ou
# kubelet. Exec direct sur l'API de kubelet de sc-build (port 10250), sans apiserver, depuis sc-confiance, par diag-exec-kubelet.py
# (WebSocket v5.channel.k8s.io, bibliothèque standard ; script par l'entrée standard de ssh, rien d'écrit sur la VM) avec le
# certificat client de l'apiserver vers kubelet (chemins lus dans les arguments de kube-apiserver, sinon chemins par défaut de
# RKE2 ; fichiers utilisés, jamais affichés). Pod runc restricted ; 128 Mio tirés sur sc-confiance, délai de 150 s :
#   K2  lecture rapide (témoin : le client fonctionne)
#   K1  lecture lente (même commande que croise, amont et bisection)
etape_kubelet() {
  local cert cle m r d
  d=$(date -u +%H:%M:%S)
  cert=$(args_apiserver | sed -n 's/^--kubelet-client-certificate=//p' | head -1)
  cle=$(args_apiserver | sed -n 's/^--kubelet-client-key=//p' | head -1)
  # Corrigé à 19:59 UTC, NON REJOUÉ : la forme ${cle:+…}${cle:-…} affichait aussi le chemin de la clé (un chemin, pas son contenu)
  echo "certificat client vers kubelet dans les arguments de kube-apiserver : ${cert:-absent} ; clé : $([ -n "$cle" ] && echo présente || echo absente)"
  cert=${cert:-$D_ETAT/server/tls/client-kube-apiserver.crt}; cle=${cle:-$D_ETAT/server/tls/client-kube-apiserver.key}
  sur sc-confiance "sudo test -r '$cert' && sudo test -r '$cle'" </dev/null \
    || { echo "KO   certificat ou clé illisible sur sc-confiance : $cert" >&2; exit 1; }
  echo "fichiers utilisés : $cert et la clé associée (non affichée) ; python : $(sur sc-confiance 'python3 --version' </dev/null 2>&1)"
  croise_pod - "$RESTREINT"
  for m in rapide lent; do
    r=$(sur sc-confiance "sudo python3 -I - ${IP[sc-build]} 10250 builds $POD diag $m 134217728 '$cert' '$cle' 150" < "$here/diag-exec-kubelet.py" 2>&1 \
      | grep -a -i -v -E 'jeton|token' | tail -n 3 || true)
    echo "K $m : $r ; reçus dans le pod : $(recu /w/k)"
    kubectl exec -n builds "$POD" -- rm -f /w/k </dev/null || true
  done
  pod_retirer "$POD"
  # Ajouté à 20:01 UTC, NON REJOUÉ : journal de kubelet sur sc-build pendant l'étape (refus, autorisation, exec, upgrade)
  echo "### kubelet (sc-build), de $d à $(date -u +%H:%M:%S) UTC"
  sur sc-build "sudo sh -s '$d' '$(date -u +%m%d)'" 2>/dev/null <<'KREFUS' | grep -a -i -v -E 'jeton|token' | cut -c1-400 || true
awk -v d="$1" -v j="$2" 'substr($1, 2, 4) == j && substr($2, 1, 8) >= d' /var/lib/rancher/rke2/agent/logs/kubelet.log \
  | grep -i -E 'forbidden|authoriz|exec|upgrade|websocket|403|denied' | tail -n 50
KREFUS
}

# Étape pile (préparée à sec le 10/11/2026 à 20:03 UTC, NON LANCÉE) : l'exec direct sur kubelet (client maison) est mis de côté
# (403, corps vide : on diagnostiquait le client). Relevés de goroutines par le kubectl standard, en simple GET, sans secret lu :
# kubelet de sc-build par le proxy de nœud (/debug/pprof/goroutine?debug=2) et kube-apiserver (/debug/pprof/goroutine?debug=2,
# si --profiling est actif : CIS 1.2.15 en échec dans 08b/resultats/rke2-cis.log). Trois moments : avant l'exec, pendant (exec à
# lecture lente de 128 Mio dans un pod runc, relevé à 45 s, processus déjà fini vers 15 s), après (fin du délai de 150 s).
# Piles brutes gardées dans $T (hors dépôt) ; archivé : seulement les goroutines dont la pile cite le relais de flux, avec leur
# état et leur durée d'attente, et la différence entre les moments.
PILE_MOTIF='remotecommand|httpstream|spdy|wsstream|websocket|proxy\.|streaming|UpgradeAware|Translator|portforward|exec'

pile_releve() { # moment : piles de kubelet et de l'apiserver dans $T/pile-<composant>-<moment>.txt
  local c u
  for c in kubelet apiserver; do
    [ "$c" = kubelet ] && u="/api/v1/nodes/sc-build/proxy/debug/pprof/goroutine?debug=2" || u="/debug/pprof/goroutine?debug=2"
    if kubectl get --raw "$u" </dev/null > "$T/pile-$c-$1.txt" 2>"$T/pile-err"; then
      echo "pile $c $1 : $(grep -c '^goroutine ' "$T/pile-$c-$1.txt") goroutines"
    else
      echo "pile $c $1 : indisponible ($(grep -a -i -v -E 'jeton|token' "$T/pile-err" | head -c 200 | tr '\n' ' '))"; : > "$T/pile-$c-$1.txt"
    fi
  done
}

etape_pile() {
  local f n pid rc=0 t0
  croise_pod - "$RESTREINT"
  pile_releve avant
  f=$(alea 128); n=$(stat -c %s "$f"); t0=$(ms)
  timeout 150 kubectl exec -i -n builds "$POD" -- sh -c "$LECTEUR_LENT" < "$f" 2>"$T/err" &
  pid=$!
  sleep 45
  echo "relevé pendant, $(( ($(ms) - t0) / 1000 )) s après le lancement ; reçus dans le pod : $(recu /w/croise)"
  pile_releve pendant
  wait "$pid" || rc=$?
  echo "exec : code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(recu /w/croise)"
  sleep 5
  pile_releve apres
  pod_retirer "$POD"
  python3 -I - "$T" "$PILE_MOTIF" <<'PILE' | grep -a -i -v -E 'jeton|token'
import re, sys
T, motif = sys.argv[1], re.compile(sys.argv[2])
def blocs(c, m):
    try: t = open(f'{T}/pile-{c}-{m}.txt', encoding='utf-8', errors='replace').read()
    except OSError: return {}
    r = {}
    for b in t.split('\n\n'):
        l = b.strip().split('\n')
        if not l or not l[0].startswith('goroutine ') or not motif.search(b): continue
        fonctions = [re.sub(r'\([^()]*\)$', '', x) for x in l[1:] if x and not x.startswith('\t')][:12]
        sig = ' <- '.join(fonctions)
        etat = re.search(r'\[(.*)\]', l[0]); etat = etat.group(1) if etat else '?'
        r.setdefault(sig, []).append(etat)
    return r
for c in ('kubelet', 'apiserver'):
    a, p, z = (blocs(c, m) for m in ('avant', 'pendant', 'apres'))
    print(f'## {c} : goroutines du relais de flux : avant {sum(map(len, a.values()))}, pendant {sum(map(len, p.values()))}, après {sum(map(len, z.values()))}')
    for sig, etats in p.items():
        if sig not in a:
            print(f'pendant seulement{" (encore après)" if sig in z else ""} : {len(etats)} × [{"; ".join(sorted(set(etats)))}]')
            print(f'     {sig[:900]}')
PILE
}

# Étape connexions (préparée à sec le 10/11/2026 à 20:08 UTC, NON LANCÉE) : la pile de kubelet ne montre plus aucun relais
# pendant le blocage ; celle de l'apiserver est indisponible (profilage coupé). Relevé des connexions TCP établies, sans rien
# changer : sur sc-build, celles de kubelet sur le port 10250 venant de sc-confiance (apiserver) ; sur sc-confiance, celles de
# kube-apiserver vers sc-build:10250 et celles reçues sur 6443 depuis l'hôte ; sur l'hôte, celles du processus kubectl de l'exec.
# Trois moments (avant, pendant à 45 s, après le délai) autour du même exec à lecture lente de 128 Mio dans un pod runc.
# Adresses et ports seulement (ss -tn, sans -p ni contenu) ; rien n'est écrit sur les VM.
connexions_releve() { # moment [pid de kubectl]
  echo "### $1"
  echo "sc-build, kubelet :10250 depuis ${IP[sc-confiance]} : $(sur sc-build "sudo ss -Htn state established '( sport = :10250 )' dst ${IP[sc-confiance]}" </dev/null 2>/dev/null | wc -l)"
  echo "sc-confiance, vers ${IP[sc-build]}:10250 : $(sur sc-confiance "sudo ss -Htn state established dst ${IP[sc-build]}:10250" </dev/null 2>/dev/null | wc -l)"
  echo "sc-confiance, :6443 reçues : $(sur sc-confiance "sudo ss -Htn state established '( sport = :6443 )'" </dev/null 2>/dev/null | wc -l)"
  if [ -n "${2:-}" ] && [ -d "/proc/$2" ]; then
    echo "hôte, sockets TCP du kubectl de l'exec (pid $2) : $(find "/proc/$2/fd" -lname 'socket:*' 2>/dev/null | wc -l) ; $(ss -Htnp 2>/dev/null | grep -c "pid=$2," ) établie(s)"
  elif [ -n "${2:-}" ]; then
    echo "hôte, kubectl de l'exec : terminé"
  fi
}

etape_connexions() {
  local f pid rc=0 t0 k
  croise_pod - "$RESTREINT"
  connexions_releve avant
  f=$(alea 128); t0=$(ms)
  timeout 150 kubectl exec -i -n builds "$POD" -- sh -c "$LECTEUR_LENT" < "$f" 2>"$T/err" &
  pid=$!
  sleep 45
  k=$(pgrep -P "$pid" -x kubectl || true)
  echo "pendant, $(( ($(ms) - t0) / 1000 )) s après le lancement ; reçus dans le pod : $(recu /w/croise)"
  connexions_releve pendant "$k"
  wait "$pid" || rc=$?
  echo "exec : code $rc en $(( $(ms) - t0 )) ms"
  sleep 5
  connexions_releve apres
  pod_retirer "$POD"
}

# Étape tunnel (préparée à sec le 10/11/2026 à 20:13 UTC, NON LANCÉE) : l'étape connexions ne montre aucune connexion directe de
# kube-apiserver vers kubelet. Vérifie le passage par le tunnel de l'agent RKE2 et le relève pendant un blocage :
#   1. argument --egress-selector-config-file de kube-apiserver et contenu de ce fichier (configuration, sans secret attendu ;
#      lignes jeton|token retirées)
#   2. connexions établies vers le port 9345 du superviseur (sc-confiance) depuis sc-build, avant, pendant et après
#   3. exec à lecture lente de 128 Mio dans un pod runc (délai de 150 s)
#   4. journaux de rke2-server (sc-confiance) et rke2-agent (sc-build) dans la fenêtre : lignes qui citent tunnel, remotedialer,
#      proxy, egress, 10250, stream, connexion, erreur ou délai ; jeton|token retirés ; 300 caractères au plus
# Rien n'est changé ni écrit sur les VM.
tunnel_releve() {
  echo "$1 : sc-confiance, :9345 établies depuis ${IP[sc-build]} : $(sur sc-confiance "sudo ss -Htn state established '( sport = :9345 )' dst ${IP[sc-build]}" </dev/null 2>/dev/null | wc -l)"
}

etape_tunnel() {
  local e f pid rc=0 t0 d fin
  e=$(args_apiserver | sed -n 's/^--egress-selector-config-file=//p' | head -1)
  echo "## sélecteur de sortie de kube-apiserver : ${e:-argument absent}"
  [ -n "$e" ] && sur sc-confiance "sudo cat '$e'" </dev/null 2>/dev/null | grep -a -i -v -E 'jeton|token' | sed 's/^/     /'
  croise_pod - "$RESTREINT"
  d=$(date -u +'%Y-%m-%d %H:%M:%S')
  tunnel_releve avant
  f=$(alea 128); t0=$(ms)
  timeout 150 kubectl exec -i -n builds "$POD" -- sh -c "$LECTEUR_LENT" < "$f" 2>"$T/err" &
  pid=$!
  sleep 45
  echo "pendant, $(( ($(ms) - t0) / 1000 )) s après le lancement ; reçus dans le pod : $(recu /w/croise)"
  tunnel_releve pendant
  wait "$pid" || rc=$?
  echo "exec : code $rc en $(( $(ms) - t0 )) ms"
  sleep 5
  tunnel_releve apres
  pod_retirer "$POD"
  fin=$(date -u +'%Y-%m-%d %H:%M:%S')
  for v in "sc-confiance $D_SERVEUR" "sc-build $D_AGENT"; do
    set -- $v
    echo "### journal de $2 ($1), $d à $fin UTC"
    sur "$1" "sudo journalctl -u $2 --since '$d UTC' --until '$fin UTC' -o short-iso --no-pager" </dev/null 2>/dev/null \
      | grep -a -i -E 'tunnel|remotedialer|proxy|egress|10250|stream|connect|error|erreur|timeout|closed' \
      | grep -a -i -v -E 'jeton|token' | cut -c1-300 | tail -n 100 || true
  done
}

# Étape local (préparée à sec le 10/11/2026 à 20:30 UTC, NON LANCÉE) : sous RKE2, kube-apiserver joint kubelet par le proxy
# CONNECT du superviseur (127.0.0.1:9345). D'après le code de k3s embarqué par RKE2 v1.35.9+rke2r1 (k3s 58877f27,
# pkg/daemons/control/tunnel.go, dialBackend), le kubelet du nœud du superviseur est joint en direct, sans session remotedialer ;
# celui de sc-build passe par la session de l'agent. Les deux passent par proxy.Proxy. Pod runc restricted sur sc-confiance
# (espace default : les pods de builds sont tenus à sc-build par zone-build), mémoire réduite ; admission essayée à blanc
# d'abord ; même exec à lecture lente de 128 Mio par le kubectl de l'hôte, délai de 150 s.
etape_local() {
  # Corrigé à 20:33 UTC le 10/11/2026, NON REJOUÉ : l'espace default est refusé (espace-default-interdit, 20:31 UTC) ; choix du
  # propriétaire : « Diag ». Espace dédié diag (Pod Security restricted), créé pour l'étape et supprimé à la fin, même en cas
  # d'échec ; admission de l'espace et du pod essayée à blanc d'abord.
  local f n rc=0 t0 ns=diag
  jq -n '{apiVersion: "v1", kind: "Namespace", metadata: {name: "diag", labels: {"pod-security.kubernetes.io/enforce": "restricted",
    "pod-security.kubernetes.io/enforce-version": "latest"}}}' > "$T/diag-ns.json"
  jq -n --arg i "$IMAGE" '{apiVersion: "v1", kind: "Pod", metadata: {name: "diag-exec-local", namespace: "diag"},
    spec: {restartPolicy: "Never", automountServiceAccountToken: false, nodeSelector: {"kubernetes.io/hostname": "sc-confiance"},
      securityContext: {runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: "512Mi"}}],
      containers: [{name: "diag", image: $i, command: ["sleep", "7200"],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
        resources: {requests: {cpu: "500m", memory: "1Gi"}, limits: {cpu: "1", memory: "1Gi"}},
        volumeMounts: [{name: "w", mountPath: "/w"}]}]}}' > "$T/diag-exec-local.json"
  kubectl get namespace diag </dev/null >/dev/null 2>&1 && { echo "KO   l'espace diag existe déjà : rien lancé" >&2; exit 1; }
  kubectl create --dry-run=server -f "$T/diag-ns.json" </dev/null > "$T/admis.out" 2>&1 \
    || { grep -a -i -v -E 'jeton|token' "$T/admis.out" | head -c 600; echo; echo "KO   espace diag refusé : rien lancé" >&2; exit 1; }
  echo "espace diag : admis à blanc"
  kubectl create -f "$T/diag-ns.json" </dev/null >/dev/null
  trap 'kubectl delete namespace diag --wait=false </dev/null >/dev/null 2>&1; echo "espace diag supprimé (demande envoyée)"' EXIT
  echo "espace diag créé à $(heure) UTC"
  kubectl create --dry-run=server -f "$T/diag-exec-local.json" </dev/null > "$T/admis.out" 2>&1 \
    || { grep -a -i -v -E 'jeton|token' "$T/admis.out" | head -c 600; echo; echo "KO   pod d'essai refusé à l'admission" >&2; exit 1; }
  echo "pod d'essai : admis à blanc"
  kubectl create -f "$T/diag-exec-local.json" </dev/null >/dev/null
  kubectl wait -n "$ns" pod/diag-exec-local --for=condition=Ready --timeout=300s </dev/null >/dev/null \
    || { echo "KO   pod non prêt" >&2; exit 1; }
  echo "### diag-exec-local (runc, uid 1000, nœud $(kubectl get pod -n "$ns" diag-exec-local -o jsonpath='{.spec.nodeName}' </dev/null)) : prêt à $(heure) UTC"
  f=$(alea 128); n=$(stat -c %s "$f"); t0=$(ms)
  timeout 150 kubectl exec -i -n "$ns" diag-exec-local -- sh -c "$LECTEUR_LENT" < "$f" 2>"$T/err" || rc=$?
  echo "L1 sc-confiance, sans tunnel : $n octets, code $rc en $(( $(ms) - t0 )) ms ; reçus dans le pod : $(kubectl exec -n "$ns" diag-exec-local -- stat -c %s /w/croise </dev/null 2>/dev/null || echo '?')"
}

lancer diag-exec "06 diagnostic exec Kata" "$@"
