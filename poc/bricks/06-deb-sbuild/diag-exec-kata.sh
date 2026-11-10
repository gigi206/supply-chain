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
  date -u +'%Y-%m-%d %H:%M:%S' > "$T/fenetre-debut"
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
  date -u +'%Y-%m-%d %H:%M:%S' > "$T/fenetre-fin"
  echo "fenêtre gardée pour l'étape noeud : $(cat "$T/fenetre-debut") à $(cat "$T/fenetre-fin") UTC"
  pod_retirer "$POD"
}

etape_noeud() {
  local d f
  d=$(cat "$T/fenetre-debut" 2>/dev/null) && f=$(cat "$T/fenetre-fin" 2>/dev/null) || { echo "KO   lancer d'abord l'étape pod" >&2; exit 1; }
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

lancer diag-exec "06 diagnostic exec Kata" "$@"
