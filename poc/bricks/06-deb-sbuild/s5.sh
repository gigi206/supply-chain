#!/usr/bin/env bash
# Brique 06, jalon S5a (décision du propriétaire du 11/11/2026, 21:14:51 UTC : « Oui, les trois ») : tests négatifs de la voie deb,
# chacun avec son témoin accepté, par des TaskRuns isolés des tâches déjà signées et revues (règle tekton-references de la 08 :
# bundle de tekton/tasks par digest, compte build, workspaces emptyDir ou PVC) et par un pod d'essai. Aucune tâche neuve, aucune
# signature. Le rejeu de zéro est S5b, jalon de plateforme à part. Prédictions : resultats/s5-predictions.md, commitées avant tout
# lancement. Paramètres pris dans les pipelines signées (bundles exportés de Zot), jamais recopiés.
#   prealables  lecture (API, Zot) et hôte : pipelines builder-sbuild et sample-app-deb exportées, tâches dans la liste revue,
#               paramètres extraits ; copie de la fermeture deb de S4b confrontée au verrou ; layout de la copie intacte comparé à
#               bb7599a2 (mesure), layouts des deux fermetures altérées (digests annoncés) ; TaskRuns, PVC et pods rendus et admis à
#               blanc côté serveur ; politiques réseau de builds relevées ; enveloppes de Chains comptées (état de départ)
#   zot         écriture dans Zot (poc-ecriture), sur accord nommé à part : les deux fermetures altérées sous
#               entrees/sample-app-deb/fermeture-alteree (tags paquet-modifie et paquet-en-trop), relues en lecture anonyme
#   prefetch    cluster (Internet en 80 par prefetch-deb-sortie) : N1 témoin (un paquet, bon sha256), N1 hash faux, N2 InRelease
#               au mauvais sha256 ; TaskRuns sur emptyDir
#   miroir      cluster (Internet en 80) : N3, prefetch-deb complet sur le PVC s5-miroir ; pod d'essai runc (amorce, UID 65532)
#               qui fait deux copies par liens durs, une avec un .deb altéré, une avec l'InRelease altéré ; construire-builder sous
#               Kata sur chaque copie, puis sur le miroir intact (témoin, rien n'est publié) ; N4, apt seul dans le même pod sur les
#               trois miroirs ; pod supprimé
#   fermeture   cluster : N5, preparer-deb sur la vraie fermeture (témoin, PVC s5-entrees gardé pour N7), puis sur les deux
#               fermetures altérées (étape zot faite)
#   kata        cluster : N7, construire-deb sur les entrées du témoin de N5, sans runtimeClassName, puis sous Kata (témoin, rien
#               n'est publié)
#   sbuild      cluster : N6, pod d'essai Kata privilégié (image de build, UID 1000) hors de construction-deb-sans-sortie ;
#               connexion TCP à Zot depuis le pod (témoin), puis depuis debian/rules d'un paquet minimal construit par sbuild
#               --chroot-mode=unshare ; pod supprimé
#   porte       cluster : invariance ; enveloppes recomptées ; provenance la plus récente du deb toujours celle du chemin 2 de
#               S4d3 ; Job de la porte sur le deb puis sur l'image sample-app, verdicts de S4d3
#   retirer     cluster : TaskRuns s5-* (et leurs pods), pods d'essai et PVC s5-* supprimés ; rien n'est retiré de Zot
# Aucun secret en argument de commande ; journaux filtrés (jeton|token).
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s5.sh <étape>…   (journal : resultats/s5-<étape>.log)
set -euo pipefail
export LC_ALL=C

h06=$(cd "$(dirname "$0")" && pwd)
. "$h06/../08-trust-plane/politique.sh"   # here (08), commun.sh, juger, passage, prov_pr, listee, auth_zot, lancer…
for f in $(declare -F | awk '$3 ~ /^etape_/ {print $3}'); do unset -f "$f"; done   # seules les étapes de S5a sont appelables
R=$h06/resultats
T=$W/s5-06
mkdir -p "$T"
trap 'rm -rf "$T/auth"' EXIT
umask 022

PIPE_BUILDER=$REG/tekton/pipelines/builder-sbuild@sha256:a9d48331da1290b06e7ead017c5536161bb0a8a515d39e61f99c8f752dfdc88b   # S4a
PIPE_DEB=$REG/tekton/pipelines/sample-app-deb@sha256:82c8373d725941bf65d6530e0c88904bb291e5f8b5c18c2209919a6d355f54a5     # S4d1
BUILDER_DIGEST=sha256:749d746cc9e1a9cfa8c80feac8ff68eae96bd6752c73ae9e46b304c38ad0c590   # S4a (A13)
BUILDER=$REG/builds/builders/sbuild-debian13@$BUILDER_DIGEST
DEB_DIGEST=sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e        # S4d1
FERMETURE_DIGEST=sha256:bb7599a2e1cde30770fdb4405a5f9cce94de5ea5b12c358e512dfbe7d5b9f290  # S4b
DEB=builds/sample-app-deb@$DEB_DIGEST
APP=builds/sample-app@$APP_DIGEST
FERMETURE=builds/fermetures/sample-app-deb@$FERMETURE_DIGEST
CONSTRUIT=builds/builders/sbuild-debian13@$BUILDER_DIGEST
ALTEREE=entrees/sample-app-deb/fermeture-alteree
COPIE=$W/s4b-06/comparaison/deb   # fermeture deb tirée par digest en S4b (167 fichiers sous miroir/)
VERROU=$repo/poc/packaging/verrou-deb.txt
URL=https://sc-stockage.poc.test:3000/$SAMPLE_APP.git
SRC=$(jq -nc --arg u "$URL" --arg r "$TETE_J2" '{git: {url: $u, revision: $r}}')
ZOT_IP=192.168.161.13
LIMITES='{"cpu": "2", "memory": "6Gi"}'
PETIT='{"cpu": "500m", "memory": "512Mi"}'
TYPE_FICHIER=application/vnd.supply-chain.deps-closure.file.v1
TYPE_FERMETURE=application/vnd.supply-chain.deps-closure.v1

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
ECARTS=0
mesure() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS=$((ECARTS + 1)); }; }
champ() { cut -d'|' -f"$2" <<< "$1"; }
ecarts() { [ "$ECARTS" = 0 ] || { echo "KO   $ECARTS écart(s)" >&2; exit 1; }; }
envel() { cosign download attestation --registry-cacert "$P/ca-poc.crt" "$REG_HOTE/$1" 2>/dev/null | grep -c . || true; }   # dépôt@digest
filtre() { grep -viE 'jeton|token' || true; }

# --- pipelines signées : bundles exportés de Zot, paramètres et tâches extraits ---------------------------------------------
exporter() { # bundle fichier : objet du bundle (JSON)
  SSL_CERT_FILE=$P/ca-poc.crt crane export "$REG_HOTE/${1#*/}" - | tar -xO > "$2"
}
pipelines() { # $T/builder.json, $T/deb.json ; refs des tâches dans $T/ref-<tâche>
  [ -s "$T/builder.json" ] || exporter "$PIPE_BUILDER" "$T/builder.json"
  [ -s "$T/deb.json" ] || exporter "$PIPE_DEB" "$T/deb.json"
  jq -r '.spec.tasks[] | "\(.taskRef.params[] | select(.name == "name") | .value) \(.taskRef.params[] | select(.name == "bundle") | .value)"' \
    "$T/builder.json" "$T/deb.json" | while read -r n b; do printf '%s' "$b" > "$T/ref-$n"; done
  [ -s "$T/tache-prefetch-deb.json" ] || exporter "$(cat "$T/ref-prefetch-deb")" "$T/tache-prefetch-deb.json"
}
AMORCE=$REG/amont/library/debian@sha256:7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392   # s1.sh, s4a.sh
params() { # fichier-pipeline tâche-de-pipeline : paramètres de cette tâche (tableau JSON name/value)
  jq -c --arg t "$2" '.spec.tasks[] | select(.name == $t) | .params' "$1"
}

# --- objets rendus ------------------------------------------------------------------------------------------------------------
ZONE='{"nodeSelector": {"zone": "build"}, "tolerations": [{"key": "zone", "operator": "Equal", "value": "build", "effect": "NoSchedule"}],
  "securityContext": {"runAsNonRoot": true, "runAsUser": 65532, "seccompProfile": {"type": "RuntimeDefault"}}}'
tr_json() { # nom tâche params-json workspaces-json runtime(kata|-) : TaskRun rendu dans $T/tr-<nom>.json
  jq -n --arg n "$1" --arg t "$2" --arg b "$(cat "$T/ref-$2")" --argjson p "$3" --argjson w "$4" --arg k "$5" --argjson z "$ZONE" '
    {apiVersion: "tekton.dev/v1", kind: "TaskRun", metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": "s5"}},
     spec: {taskRef: {resolver: "bundles", params: [{name: "bundle", value: $b}, {name: "name", value: $t}, {name: "kind", value: "task"}]},
       params: $p, serviceAccountName: "build", workspaces: $w,
       podTemplate: (if $k == "kata" then $z + {runtimeClassName: "kata"} else $z end)}}' > "$T/tr-$1.json"
}
pvc_json() { # nom taille : PVC rendu dans $T/pvc-<nom>.json
  jq -n --arg n "$1" --arg s "$2" '{apiVersion: "v1", kind: "PersistentVolumeClaim", metadata: {name: $n, namespace: "builds",
    labels: {"poc.test/jalon": "s5"}}, spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: $s}}}}' > "$T/pvc-$1.json"
}
pod_json() { # nom image kata|runc pvc|- : pod d'essai rendu dans $T/pod-<nom>.json (sleep ; sans label tekton.dev/task)
  jq -n --arg n "$1" --arg i "$2" --arg k "$3" --arg v "$4" --argjson l "$LIMITES" --argjson pl "$PETIT" --argjson z "$ZONE" '
    {apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": "s5"}},
     spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, enableServiceLinks: false,
       volumes: ([{name: "w", emptyDir: (if $k == "kata" then {medium: "Memory", sizeLimit: "4Gi"} else {} end)}]
         + (if $v == "-" then [] else [{name: "m", persistentVolumeClaim: {claimName: $v}}] end)),
       containers: [{name: "essai", image: $i, command: ["sleep", "7200"],
         securityContext: (if $k == "kata" then {privileged: true, allowPrivilegeEscalation: true, runAsUser: 1000, runAsGroup: 1000, runAsNonRoot: true}
           else {allowPrivilegeEscalation: false, runAsUser: 65532, runAsGroup: 65532, runAsNonRoot: true, capabilities: {drop: ["ALL"]}} end),
         resources: (if $k == "kata" then {requests: $l, limits: $l} else {requests: $pl, limits: $pl} end),
         volumeMounts: ([{name: "w", mountPath: "/w"}] + (if $v == "-" then [] else [{name: "m", mountPath: "/m"}] end))}]}
       + $z + (if $k == "kata" then {runtimeClassName: "kata"} else {} end))}' > "$T/pod-$1.json"
}
ws_vide() { jq -nc --arg n "$1" '[{name: $n, emptyDir: {}}]'; }
ws_pvc() { # nom-workspace pvc sous-dossier [nom-workspace pvc sous-dossier]… : workspaces sur PVC
  local a='[]'
  while [ $# -gt 0 ]; do a=$(jq -c --arg n "$1" --arg c "$2" --arg s "$3" '. + [{name: $n, persistentVolumeClaim: {claimName: $c}} + (if $s == "." then {} else {subPath: $s} end)]' <<< "$a"); shift 3; done
  echo "$a"
}
a_blanc() { # fichier : création admise à blanc côté serveur
  kubectl create --dry-run=server -o name -f "$1" > /dev/null 2> "$T/a-blanc.err" \
    && echo "OK   admis à blanc : ${1##*/}" || { echo "ÉCART refusé à blanc : ${1##*/} ($(tr '\n' ' ' < "$T/a-blanc.err" | cut -c1-260))"; ECARTS=$((ECARTS + 1)); }
}

# --- TaskRuns et pods ---------------------------------------------------------------------------------------------------------
tr_lancer() { # nom : TaskRun rendu créé (purgé d'abord s'il existe), attendu (3600 s au plus) ; « statut|raison » ; journal $T/<nom>.log
  local st="" p
  kubectl delete taskrun -n builds "$1" --ignore-not-found --wait=true < /dev/null > /dev/null
  kubectl create -f "$T/tr-$1.json" < /dev/null > /dev/null
  echo "TaskRun $1 créé à $(date -u +%H:%M:%S)" >&2
  for _ in $(seq 1800); do
    st=$(kubectl get taskrun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' < /dev/null 2>/dev/null || true)
    [ -n "$st" ] && [ "$st" != Unknown ] && break; sleep 2
  done
  kubectl get taskrun -n builds "$1" -o json < /dev/null > "$T/$1.tr.json"
  p=$(jq -r '.status.podName // ""' "$T/$1.tr.json")
  if [ -n "$p" ] && kubectl get pod -n builds "$p" < /dev/null > /dev/null 2>&1; then
    kubectl logs -n builds "$p" --all-containers < /dev/null 2>&1 | filtre > "$T/$1.log"
    kubectl get pod -n builds "$p" -o json < /dev/null > "$T/$1.pod.json"
  else : > "$T/$1.log"; echo '{}' > "$T/$1.pod.json"; fi
  echo "$(jq -r '.status.conditions[] | select(.type == "Succeeded") | "\(.status)|\(.reason)"' "$T/$1.tr.json")"
}
tr_message() { jq -r '.status.conditions[] | select(.type == "Succeeded") | .message' "$T/$1.tr.json" | tr '\n' ' ' | filtre | cut -c1-400; }
tr_resultat() { jq -r --arg r "$2" '[.status.results[]? | select(.name == $r) | .value][0] // ""' "$T/$1.tr.json"; }
tr_journal() { # nom : lignes du journal, filtrées et coupées
  grep -vE '^\s*$' "$T/$1.log" | grep -v -e '^Installed-Build-Depends:' -e '^ [a-z0-9]' | tail -n "${2:-12}" | cut -c1-220 | sed 's/^/     /'
}
tr_pod() { jq -r '"\(.metadata.labels["tekton.dev/task"] // "-")|\(.spec.nodeName // "-")|\(.spec.runtimeClassName // "-")"' "$T/$1.pod.json"; }
tr_signe() { kubectl get taskrun -n builds "$1" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}' < /dev/null 2>/dev/null || true; }
lignes() { grep -cF -- "$2" "$T/$1.log" || true; }   # nom motif : nombre de lignes du journal qui contiennent le motif

pod_creer() { # nom : pod rendu créé, prêt
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true < /dev/null > /dev/null
  kubectl create -f "$T/pod-$1.json" < /dev/null > /dev/null
  echo "pod $1 créé à $(date -u +%H:%M:%S)"
  kubectl wait -n builds "pod/$1" --for=condition=Ready --timeout=300s < /dev/null > /dev/null \
    || { kubectl describe pod -n builds "$1" < /dev/null | tail -n 20 | filtre >&2; echo "KO   pod $1 non prêt" >&2; exit 1; }
  echo "pod $1 prêt sur $(kubectl get pod -n builds "$1" -o jsonpath='{.spec.nodeName}, runtimeClassName « {.spec.runtimeClassName} »' < /dev/null)"
}
pod_script() { # pod fichier-hôte journal : script copié dans le pod (/w/s.sh), exécuté par bash, entrée standard fermée ; code
  local rc=0
  kubectl exec -i -n builds "$1" -- sh -c 'cat > /w/s.sh' < "$2"
  timeout 1800 kubectl exec -n builds "$1" -- bash /w/s.sh < /dev/null > "$3" 2>&1 || rc=$?
  filtre < "$3" > "$3.f" && mv "$3.f" "$3"
  return $rc
}

# --- fermetures altérées (hôte) -----------------------------------------------------------------------------------------------
verrou_ok() { # dossier : confrontation de la copie au verrou (sha256, taille, chemin ; aucun autre fichier dans le pool) ; nombre
  local n=0 s z p
  while read -r _ _ _ s z p; do
    [ "$(sha256sum < "$1/miroir/$p" | cut -c1-64)" = "$s" ] && [ "$(stat -c %s "$1/miroir/$p")" = "$z" ] || { echo "KO   copie différente du verrou : $p" >&2; exit 1; }
    n=$((n + 1))
  done < <(grep -v '^#' "$VERROU" | grep .)
  [ "$(find "$1/miroir/pool" -type f | wc -l)" = "$n" ] || { echo "KO   pool de la copie différent du verrou" >&2; exit 1; }
  echo "$n"
}
layout() { # dossier layout : poussée locale de la fermeture comme publier-fermeture (03) ; digest
  local a=()
  rm -rf "$2"
  while read -r p; do a+=("$p:$TYPE_FICHIER"); done < <(cd "$1" && find . -type f ! -name bom.json | sed 's#^\./##' | LC_ALL=C sort)
  (cd "$1" && oras push --no-tty --oci-layout --format go-template='{{.digest}}' --artifact-type "$TYPE_FERMETURE" \
    --annotation org.opencontainers.image.created=1970-01-01T00:00:00Z "$2:fermeture" "${a[@]}")
}
alterer() { # prépare $T/alt/{intacte,paquet-modifie,paquet-en-trop} et leurs layouts ; digests dans $T/digest-<cas>
  local f c
  rm -rf "$T/alt" && mkdir -p "$T/alt"
  for c in intacte paquet-modifie paquet-en-trop; do cp -a "$COPIE" "$T/alt/$c"; done
  f=$(cat "$T/paquet-fermeture")
  # Paquet modifié : dernier octet remplacé, taille inchangée
  python3 -I - "$T/alt/paquet-modifie/miroir/$f" <<'FIN'
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
b[-1] ^= 0xff
open(p, 'wb').write(b)
FIN
  # Fichier en trop dans le pool, de contenu propre (aucun blob en double dans le manifeste)
  mkdir -p "$T/alt/paquet-en-trop/miroir/pool/main/s/s5-en-trop"
  printf 's5 : fichier en trop dans le pool\n' > "$T/alt/paquet-en-trop/miroir/pool/main/s/s5-en-trop/s5-en-trop_1.0_all.deb"
  for c in intacte paquet-modifie paquet-en-trop; do layout "$T/alt/$c" "$T/alt/layout-$c" > "$T/digest-$c"; done
}

etape_prealables() {
  local b n f t
  echo "## pipelines signées (bundles exportés de Zot)"
  rm -f "$T/builder.json" "$T/deb.json" "$T/tache-prefetch-deb.json"
  pipelines
  mesure "image de prefetch-deb (amorce, pour le pod d'essai de N3 et N4)" "$(jq -r '.spec.steps[0].image' "$T/tache-prefetch-deb.json")" "$AMORCE"
  mesure "pipeline builder-sbuild, tâches" "$(jq -r '[.spec.tasks[].name] | join(",")' "$T/builder.json")" prefetch,construire,publier
  mesure "pipeline sample-app-deb, tâches" "$(jq -r '[.spec.tasks[].name] | join(",")' "$T/deb.json")" preparer,construire,publier
  for t in prefetch-deb construire-builder preparer-deb construire-deb; do
    b=$(cat "$T/ref-$t")
    listee "$b" && echo "OK   $t dans la liste revue : ${b#"$REG/"}" || { echo "ÉCART $t hors de la liste revue : $b"; ECARTS=$((ECARTS + 1)); }
  done
  params "$T/builder.json" prefetch > "$T/p-prefetch.json"
  params "$T/builder.json" construire > "$T/p-construire-builder.json"
  params "$T/deb.json" preparer > "$T/p-preparer.json"
  mesure "paramètres de prefetch" "$(jq -r 'map(.name) | join(",")' "$T/p-prefetch.json")" instantane,inrelease,liste
  mesure "paramètres de construire (builder)" "$(jq -r 'map(.name) | sort | join(",")' "$T/p-construire-builder.json")" amorce,inclure,inrelease,instantane,liste,sde
  mesure "paramètres de preparer" "$(jq -r 'map(.name) | join(",")' "$T/p-preparer.json")" depot,commit,fermeture-deb,fermeture-sources,packaging
  mesure "fermeture deb de la pipeline" "$(jq -r '.[] | select(.name == "fermeture-deb") | .value' "$T/p-preparer.json")" "$REG/$FERMETURE"
  mesure "liste de la pipeline builder égale à builder/paquets.txt (colonnes 4 à 6)" \
    "$(jq -r '.[] | select(.name == "liste") | .value' "$T/p-prefetch.json" | grep . | sha256sum | cut -c1-64)" "$(awk '{print $4, $5, $6}' "$h06/builder/paquets.txt" | sha256sum | cut -c1-64)"
  # Paquet témoin du miroir du constructeur (N1, N3, N4) : le plus petit de la liste
  jq -r '.[] | select(.name == "liste") | .value' "$T/p-prefetch.json" | grep . | sort -k2,2n | head -1 > "$T/paquet-miroir"
  echo "paquet témoin du miroir : $(cat "$T/paquet-miroir")"
  echo "## fermeture deb : copie de S4b, fermetures altérées (hôte)"
  n=$(verrou_ok "$COPIE")
  mesure "copie de S4b confrontée au verrou (paquets)" "$n" 162
  mesure "fichiers de la copie" "$(find "$COPIE" -type f | wc -l)" 167
  (cd "$COPIE/miroir" && find pool -type f -printf '%s %p\n' | sort -n | head -1 | cut -d' ' -f2) > "$T/paquet-fermeture"
  echo "paquet modifié de la fermeture : $(cat "$T/paquet-fermeture")"
  alterer
  echo "oras de l'hôte : $(oras version | head -1)"
  mesure "layout de la copie intacte (même commande que publier-fermeture)" "$(cat "$T/digest-intacte")" "$FERMETURE_DIGEST"
  for f in paquet-modifie paquet-en-trop; do
    echo "fermeture $f : $(cat "$T/digest-$f") ; couches : $(oras manifest fetch --oci-layout "$T/alt/layout-$f@$(cat "$T/digest-$f")" | jq '.layers | length')"
  done
  mesure "couches différentes de l'intacte (paquet-modifie)" "$(comm -13 <(oras manifest fetch --oci-layout "$T/alt/layout-intacte@$(cat "$T/digest-intacte")" | jq -r '.layers[].digest' | sort) \
    <(oras manifest fetch --oci-layout "$T/alt/layout-paquet-modifie@$(cat "$T/digest-paquet-modifie")" | jq -r '.layers[].digest' | sort) | wc -l)" 1
  mesure "couches différentes de l'intacte (paquet-en-trop)" "$(comm -13 <(oras manifest fetch --oci-layout "$T/alt/layout-intacte@$(cat "$T/digest-intacte")" | jq -r '.layers[].digest' | sort) \
    <(oras manifest fetch --oci-layout "$T/alt/layout-paquet-en-trop@$(cat "$T/digest-paquet-en-trop")" | jq -r '.layers[].digest' | sort) | wc -l)" 1
  echo "## objets rendus, admis à blanc côté serveur"
  rendre_tout
  for f in "$T"/tr-*.json "$T"/pvc-*.json "$T"/pod-*.json; do a_blanc "$f"; done
  echo "## politiques réseau de builds (sélecteurs)"
  kubectl get networkpolicy -n builds -o json | jq -r '.items[] | "     NetworkPolicy \(.metadata.name) : \(.spec.podSelector | tostring)"'
  kubectl get ciliumnetworkpolicy -n builds -o json | jq -r '.items[] | "     CiliumNetworkPolicy \(.metadata.name) : \(.spec.endpointSelector | tostring)"'
  echo "## état de départ"
  mesure "objets s5 dans builds" "$(kubectl get taskrun,pod,pvc -n builds -l poc.test/jalon=s5 -o name | wc -l)" 0
  mesure "dépôt $ALTEREE dans Zot" "$(SSL_CERT_FILE=$P/ca-poc.crt crane ls "$REG_HOTE/$ALTEREE" 2>/dev/null | paste -sd, - || true)" ""
  for f in "$DEB" "$APP" "$FERMETURE" "$CONSTRUIT"; do echo "$f $(envel "$f")"; done | tee "$T/enveloppes-avant"
  mesure "enveloppes de départ (deb, sample-app)" "$(awk 'NR <= 2 {print $2}' "$T/enveloppes-avant" | paste -sd' ' -)" "8 28"
  ecarts
}

rendre_tout() { # tous les TaskRuns, PVC et pods de S5a dans $T (refs des fermetures altérées : digests des layouts locaux)
  local p1 faux inr
  p1=$(cat "$T/paquet-miroir")
  faux="${p1:0:63}$( [ "${p1:63:1}" = 0 ] && echo 1 || echo 0) ${p1#* }"   # dernier chiffre du sha256 changé
  inr=$(jq -r '.[] | select(.name == "inrelease") | .value' "$T/p-prefetch.json")
  jq -c --arg l "$p1" 'map(if .name == "liste" then .value = $l else . end)' "$T/p-prefetch.json" > "$T/p-n1-temoin.json"
  jq -c --arg l "$faux" 'map(if .name == "liste" then .value = $l else . end)' "$T/p-prefetch.json" > "$T/p-n1-faux.json"
  jq -c --arg l "$p1" --arg i "$( [ "${inr:0:1}" = 0 ] && echo 1 || echo 0)${inr:1}" \
    'map(if .name == "liste" then .value = $l elif .name == "inrelease" then .value = $i else . end)' "$T/p-prefetch.json" > "$T/p-n2.json"
  tr_json s5-n1-temoin prefetch-deb "$(cat "$T/p-n1-temoin.json")" "$(ws_vide sortie)" -
  tr_json s5-n1-faux prefetch-deb "$(cat "$T/p-n1-faux.json")" "$(ws_vide sortie)" -
  tr_json s5-n2-inrelease prefetch-deb "$(cat "$T/p-n2.json")" "$(ws_vide sortie)" -
  pvc_json s5-miroir 4Gi
  tr_json s5-n3-prefetch prefetch-deb "$(cat "$T/p-prefetch.json")" "$(ws_pvc sortie s5-miroir .)" -
  for c in deb inrelease intact; do
    tr_json "s5-n3-$c" construire-builder "$(cat "$T/p-construire-builder.json")" \
      "$(ws_pvc entrees s5-miroir "$( [ $c = intact ] && echo miroir || echo "miroir-$c")" sortie s5-miroir "image-$c")" kata
  done
  pod_json s5-miroir-essai "$AMORCE" runc s5-miroir
  pvc_json s5-entrees 1Gi
  tr_json s5-n5-temoin preparer-deb "$(cat "$T/p-preparer.json")" "$(ws_pvc sortie s5-entrees .)" -
  for c in paquet-modifie paquet-en-trop; do
    tr_json "s5-n5-$c" preparer-deb "$(jq -c --arg r "$REG/$ALTEREE@$(cat "$T/digest-$c")" 'map(if .name == "fermeture-deb" then .value = $r else . end)' "$T/p-preparer.json")" \
      "$(ws_vide sortie)" -
  done
  tr_json s5-n7-hors-kata construire-deb '[]' "$(ws_pvc entrees s5-entrees entrees sortie s5-entrees image-hors-kata)" -
  tr_json s5-n7-kata construire-deb '[]' "$(ws_pvc entrees s5-entrees entrees sortie s5-entrees image-kata)" kata
  pod_json s5-sbuild "$BUILDER" kata -
}

etape_zot() {
  local c d l
  [ -s "$T/digest-paquet-modifie" ] && [ -s "$T/digest-paquet-en-trop" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  (umask 077 && mkdir -p "$T/auth/docker") && auth_zot "$T/auth/docker/config.json"   # compte poc-ecriture, comme F3 (03) et S4c
  for c in paquet-modifie paquet-en-trop; do
    d=$(cat "$T/digest-$c")
    oras cp --no-tty --from-oci-layout "$T/alt/layout-$c@$d" "$REG_HOTE/$ALTEREE:$c" --to-ca-file "$P/ca-poc.crt" \
      --to-registry-config "$T/auth/docker/config.json" > /dev/null
    l=$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/$ALTEREE:$c" | jq -r '.digest')
    mesure "$c : relu dans Zot en lecture anonyme" "$l" "$d"
  done
  rm -rf "$T/auth"
  ecarts
}

etape_prefetch() {
  local r
  [ -s "$T/tr-s5-n1-temoin.json" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  echo "## N1 témoin : un paquet, bon sha256 ($(cut -d' ' -f3 "$T/paquet-miroir"))"
  r=$(tr_lancer s5-n1-temoin); tr_journal s5-n1-temoin 6
  mesure "N1 témoin : TaskRun" "$r" "True|Succeeded"
  mesure "N1 témoin : pod (tekton.dev/task|nœud|runtime)" "$(tr_pod s5-n1-temoin)" "prefetch-deb|sc-build|-"
  mesure "N1 témoin : miroir d'un paquet" "$(lignes s5-n1-temoin 'miroir : 1 paquets')" 1
  echo "## N1 : même paquet, sha256 faux (dernier chiffre changé)"
  r=$(tr_lancer s5-n1-faux); tr_journal s5-n1-faux 8
  mesure "N1 hash faux : TaskRun" "$r" "False|Failed"
  mesure "N1 hash faux : refus par apt-helper (« téléchargement refusé »)" "$(lignes s5-n1-faux "téléchargement refusé : $(cut -d' ' -f3 "$T/paquet-miroir")")" 1
  mesure "N1 hash faux : contrôle du shell non atteint (« sha256 différent »)" "$(lignes s5-n1-faux 'sha256 différent')" 0
  mesure "N1 hash faux : message d'apt-helper « Hash Sum mismatch »" "$( [ "$(lignes s5-n1-faux 'Hash Sum mismatch')" -ge 1 ] && echo oui || echo non)" oui
  echo "## N2 : InRelease au mauvais sha256 (premier chiffre changé)"
  r=$(tr_lancer s5-n2-inrelease); tr_journal s5-n2-inrelease 8
  mesure "N2 : TaskRun" "$r" "False|Failed"
  mesure "N2 : refus par apt-helper sur l'InRelease" "$(lignes s5-n2-inrelease 'téléchargement refusé : dists/trixie/InRelease')" 1
  mesure "N2 : aucun index ni paquet téléchargé" "$(lignes s5-n2-inrelease 'index main/')" 0
  for r in s5-n1-temoin s5-n1-faux s5-n2-inrelease; do echo "     $r : chains.tekton.dev/signed « $(tr_signe $r) »"; done
  ecarts
}

etape_miroir() {
  local r p s z v
  [ -s "$T/tr-s5-n3-prefetch.json" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  read -r s z p < "$T/paquet-miroir"
  attendu "PVC s5-miroir absent (sinon : étape retirer)" "$(kubectl get pvc -n builds s5-miroir -o name < /dev/null 2>/dev/null || echo absent)" absent
  echo "## N3 : miroir complet sur le PVC s5-miroir"
  kubectl apply -f "$T/pvc-s5-miroir.json" < /dev/null > /dev/null
  r=$(tr_lancer s5-n3-prefetch); tr_journal s5-n3-prefetch 4
  attendu "N3 prefetch : TaskRun" "$r" "True|Succeeded"
  echo "## pod d'essai runc (amorce, UID 65532) : copies altérées par liens durs"
  trap 'kubectl delete pod -n builds s5-miroir-essai --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true; rm -rf "$T/auth"' EXIT
  pod_creer s5-miroir-essai
  cat > "$T/alterer.sh" <<FIN
set -eu
cd /m
rm -rf miroir-deb miroir-inrelease
cp -al miroir miroir-deb
cp -al miroir miroir-inrelease
# .deb : copie de lien rompue, dernier octet remplacé, taille inchangée
cp miroir/$p miroir-deb/$p.n && mv miroir-deb/$p.n miroir-deb/$p
if [ "\$(tail -c 1 miroir-deb/$p | od -An -tu1 | tr -d ' ')" = 255 ]; then b='\\000'; else b='\\377'; fi
printf "\$b" | dd of=miroir-deb/$p bs=1 seek=\$((\$(stat -c %s miroir-deb/$p) - 1)) conv=notrunc status=none
# InRelease : une lettre de la partie signée, taille inchangée
sed 's/^Origin: Debian\$/Origin: Debiam/' miroir/dists/trixie/InRelease > miroir-inrelease/dists/trixie/InRelease.n
mv miroir-inrelease/dists/trixie/InRelease.n miroir-inrelease/dists/trixie/InRelease
for d in miroir miroir-deb miroir-inrelease; do
  echo "\$d : InRelease \$(sha256sum < \$d/dists/trixie/InRelease | cut -c1-64) \$(stat -c %s \$d/dists/trixie/InRelease) ; $p \$(sha256sum < \$d/$p | cut -c1-64) \$(stat -c %s \$d/$p)"
done
echo "lignes Origin : \$(grep -c '^Origin: Debiam\$' miroir-inrelease/dists/trixie/InRelease) altérée, \$(grep -c '^Origin: Debian\$' miroir/dists/trixie/InRelease) intacte"
FIN
  pod_script s5-miroir-essai "$T/alterer.sh" "$T/alterer.log" || { cat "$T/alterer.log"; echo "KO   altération" >&2; exit 1; }
  sed 's/^/     /' "$T/alterer.log"
  mesure "miroir intact : paquet témoin au sha256 de la liste" "$(awk '$1 == "miroir" {print $8}' "$T/alterer.log")" "$s"
  mesure "miroir-deb : paquet témoin altéré, même taille" "$(awk '$1 == "miroir-deb" {print ($8 != s) "|" $9}' s="$s" "$T/alterer.log")" "1|$z"
  mesure "miroir-inrelease : InRelease altéré, même taille" \
    "$(awk '$1 == "miroir" {a = $4; t = $5} $1 == "miroir-inrelease" {print ($4 != a) "|" ($5 == t)}' "$T/alterer.log")" "1|1"
  echo "## N3 : construire-builder sous Kata sur chaque copie"
  r=$(tr_lancer s5-n3-deb); tr_journal s5-n3-deb 6
  mesure "N3 .deb altéré : TaskRun" "$r" "False|Failed"
  mesure "N3 .deb altéré : refus par la revérification (« paquet altéré »)" "$(lignes s5-n3-deb "paquet altéré : $p")" 1
  mesure "N3 .deb altéré : ni miroir revérifié ni apt lancé" "$(lignes s5-n3-deb 'miroir revérifié')|$(lignes s5-n3-deb 'apt-get install hors ligne')" "0|0"
  r=$(tr_lancer s5-n3-inrelease); tr_journal s5-n3-inrelease 6
  mesure "N3 InRelease altéré : TaskRun" "$r" "False|Failed"
  mesure "N3 InRelease altéré : refus par la revérification" "$(lignes s5-n3-inrelease 'InRelease du miroir différent')" 1
  mesure "N3 : pods sous Kata (tekton.dev/task|nœud|runtime)" "$(tr_pod s5-n3-deb) $(tr_pod s5-n3-inrelease)" "construire-builder|sc-build|kata construire-builder|sc-build|kata"
  echo "## N3 témoin : construire-builder sur le miroir intact (rien n'est publié)"
  r=$(tr_lancer s5-n3-intact); tr_journal s5-n3-intact 6
  mesure "N3 témoin : TaskRun" "$r" "True|Succeeded"
  mesure "N3 témoin : DIGEST_CONSTRUIT (image de S4a)" "$(tr_resultat s5-n3-intact DIGEST_CONSTRUIT)" "$BUILDER_DIGEST"
  echo "## N4 : apt seul, dans le pod d'essai, sur les trois miroirs (file:, sans trusted=yes)"
  v=${p##*/}; v=${v%%_*}   # nom du paquet (une seule version dans l'index de l'instantané)
  cat > "$T/apt.sh" <<FIN
set -u
for d in miroir miroir-inrelease miroir-deb; do
  r=/w/apt-\$d; rm -rf \$r; mkdir -p \$r/listes/partial \$r/cache/archives/partial \$r/dl
  echo "deb [check-valid-until=no] file:/m/\$d trixie main" > \$r/sources.list
  o="-o Dir::Etc::SourceList=\$r/sources.list -o Dir::Etc::SourceParts=/nonexistent -o Dir::State::Lists=\$r/listes -o Dir::Cache=\$r/cache -o Debug::NoLocking=1"
  u=0; apt-get \$o update > \$r/update.log 2>&1 || u=\$?
  n=\$(find \$r/listes -maxdepth 1 -name '*_Packages*' | wc -l)
  echo "\$d|update|\$u|\$n"
  grep -iE 'sign|sqv|gpg|not signed|Err|^E:|^W:' \$r/update.log | cut -c1-200 | sed "s#^#\$d|apt|#"
  if [ "\$n" -gt 0 ]; then
    t=0; (cd \$r/dl && apt-get \$o download "$v" > \$r/download.log 2>&1) || t=\$?
    echo "\$d|download|\$t|\$(ls \$r/dl | wc -l)"
    grep -iE 'hash|mismatch|^E:|^W:' \$r/download.log | cut -c1-200 | sed "s#^#\$d|apt|#"
  fi
done
FIN
  pod_script s5-miroir-essai "$T/apt.sh" "$T/apt.log" || true
  sed 's/^/     /' "$T/apt.log"
  mesure "N4 témoin, miroir intact : update (code|index Packages)" "$(awk -F'|' '$1 == "miroir" && $2 == "update" {print $3 "|" ($4 > 0)}' "$T/apt.log")" "0|1"
  mesure "N4 témoin, miroir intact : téléchargement du paquet témoin (code|fichiers)" "$(awk -F'|' '$1 == "miroir" && $2 == "download" {print $3 "|" $4}' "$T/apt.log")" "0|1"
  mesure "N4 InRelease altéré : update refusé, aucun index (code non nul|index)" "$(awk -F'|' '$1 == "miroir-inrelease" && $2 == "update" {print ($3 != 0) "|" $4}' "$T/apt.log")" "1|0"
  mesure "N4 .deb altéré : index acceptés" "$(awk -F'|' '$1 == "miroir-deb" && $2 == "update" {print $3 "|" ($4 > 0)}' "$T/apt.log")" "0|1"
  mesure "N4 .deb altéré : téléchargement refusé, aucun fichier (code non nul|fichiers)" "$(awk -F'|' '$1 == "miroir-deb" && $2 == "download" {print ($3 != 0) "|" $4}' "$T/apt.log")" "1|0"
  mesure "N4 .deb altéré : message « Hash Sum mismatch »" "$( grep -q '^miroir-deb|apt|.*Hash Sum mismatch' "$T/apt.log" && echo oui || echo non)" oui
  kubectl delete pod -n builds s5-miroir-essai --wait=false < /dev/null > /dev/null; echo "pod s5-miroir-essai supprimé"
  for r in s5-n3-prefetch s5-n3-deb s5-n3-inrelease s5-n3-intact; do echo "     $r : chains.tekton.dev/signed « $(tr_signe $r) »"; done
  ecarts
}

etape_fermeture() {
  local r c
  [ -s "$T/tr-s5-n5-temoin.json" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  attendu "PVC s5-entrees absent (sinon : étape retirer)" "$(kubectl get pvc -n builds s5-entrees -o name < /dev/null 2>/dev/null || echo absent)" absent
  echo "## N5 témoin : preparer-deb sur la vraie fermeture (PVC s5-entrees, gardé pour N7)"
  kubectl apply -f "$T/pvc-s5-entrees.json" < /dev/null > /dev/null
  r=$(tr_lancer s5-n5-temoin); tr_journal s5-n5-temoin 6
  mesure "N5 témoin : TaskRun" "$r" "True|Succeeded"
  mesure "N5 témoin : confrontation au verrou" "$(lignes s5-n5-temoin 'fermeture deb confrontée au verrou : 162 paquets')" 1
  for c in paquet-modifie paquet-en-trop; do
    attendu "$c dans Zot (étape zot)" "$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/$ALTEREE@$(cat "$T/digest-$c")" 2>/dev/null | jq -r '.digest' || true)" "$(cat "$T/digest-$c")"
    echo "## N5 : preparer-deb sur la fermeture $c"
    r=$(tr_lancer "s5-n5-$c"); tr_journal "s5-n5-$c" 6
    mesure "N5 $c : TaskRun" "$r" "False|Failed"
    mesure "N5 $c : tirage par digest réussi (oras)" "$(lignes "s5-n5-$c" 'fermeture deb : ')" 1
  done
  mesure "N5 paquet-modifie : refus par la confrontation au verrou" "$(lignes s5-n5-paquet-modifie "paquet différent du verrou : $(cat "$T/paquet-fermeture")")" 1
  mesure "N5 paquet-en-trop : refus par la confrontation au verrou" "$(lignes s5-n5-paquet-en-trop 'pool : 163 fichiers, 162 dans le verrou')" 1
  for r in s5-n5-temoin s5-n5-paquet-modifie s5-n5-paquet-en-trop; do echo "     $r : chains.tekton.dev/signed « $(tr_signe $r) »"; done
  ecarts
}

etape_kata() {
  local r
  attendu "N5 témoin réussi (entrées sur s5-entrees)" "$(kubectl get taskrun -n builds s5-n5-temoin -o jsonpath='{.status.conditions[0].reason}' < /dev/null 2>/dev/null || true)" Succeeded
  echo "## N7 : construire-deb sans runtimeClassName"
  r=$(tr_lancer s5-n7-hors-kata)
  echo "     message : $(tr_message s5-n7-hors-kata)"
  mesure "N7 hors Kata : TaskRun" "$r" "False|PodAdmissionFailed"
  mesure "N7 hors Kata : refus de Pod Security restricted (privileged)" \
    "$(tr_message s5-n7-hors-kata | grep -c 'violates PodSecurity "restricted:latest".*privileged' || true)" 1
  mesure "N7 hors Kata : aucun pod" "$(jq -r '.status.podName // ""' "$T/s5-n7-hors-kata.tr.json")" ""
  echo "## N7 témoin : construire-deb sous Kata (rien n'est publié)"
  r=$(tr_lancer s5-n7-kata); tr_journal s5-n7-kata 8
  mesure "N7 témoin : TaskRun" "$r" "True|Succeeded"
  mesure "N7 témoin : pod (tekton.dev/task|nœud|runtime)" "$(tr_pod s5-n7-kata)" "construire-deb|sc-build|kata"
  mesure "N7 témoin : deb de S1, S3 et S4d" "$(grep -o 'deb produit : [^ ]* [0-9a-f]*' "$T/s5-n7-kata.log" | awk '{print $4}' | cut -c1-8)" 0b489d43
  mesure "N7 témoin : DIGEST_CONSTRUIT" "$(tr_resultat s5-n7-kata DIGEST_CONSTRUIT)" "$DEB_DIGEST"
  for r in s5-n7-hors-kata s5-n7-kata; do echo "     $r : chains.tekton.dev/signed « $(tr_signe $r) »"; done
  ecarts
}

paquet_reseau() { # $T/paquet/s5-reseau-1.0 : paquet source natif minimal ; debian/rules essaie une connexion TCP à Zot pendant build
  local d=$T/paquet/s5-reseau-1.0
  rm -rf "$T/paquet" && mkdir -p "$d/debian/source"
  echo '3.0 (native)' > "$d/debian/source/format"
  cat > "$d/debian/control" <<'FIN'
Source: s5-reseau
Section: misc
Priority: optional
Maintainer: PoC <poc@poc.test>
Standards-Version: 4.7.0
Rules-Requires-Root: no

Package: s5-reseau
Architecture: any
Description: témoin de S5a
 Essai de connexion pendant la construction.
FIN
  cat > "$d/debian/changelog" <<'FIN'
s5-reseau (1.0) trixie; urgency=medium

  * Témoin de S5a.

 -- PoC <poc@poc.test>  Wed, 11 Nov 2026 21:00:00 +0000
FIN
  printf '%s\n' '#!/usr/bin/make -f' 'build build-arch build-indep:' \
    "	@r=0; timeout 10 bash -c 'exec 3<>/dev/tcp/$ZOT_IP/5000' 2>/dev/null || r=\$\$?; echo \"S5-RESEAU|regles|\$\$r\"" \
    "	@echo \"S5-RESEAU|interfaces|\$\$(awk -F: 'NR > 2 {gsub(/ /, \"\", \$\$1); printf \"%s \", \$\$1}' /proc/net/dev)\"" \
    'binary binary-arch binary-indep:' \
    '	mkdir -p debian/tmp/DEBIAN' \
    '	dpkg-gencontrol -ps5-reseau -Pdebian/tmp' \
    '	dpkg-deb --root-owner-group --build debian/tmp ..' \
    'clean:' \
    '	rm -rf debian/tmp debian/files' > "$d/debian/rules"
  chmod 0755 "$d/debian/rules"
}

etape_sbuild() {
  [ -s "$T/pod-s5-sbuild.json" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  paquet_reseau
  echo "## debian/rules du paquet témoin"
  sed 's/^/     /' "$T/paquet/s5-reseau-1.0/debian/rules"
  echo "## N6 : pod d'essai Kata (image de build, UID 1000), sans label tekton.dev/task"
  trap 'kubectl delete pod -n builds s5-sbuild --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true; rm -rf "$T/auth"' EXIT
  pod_creer s5-sbuild
  tar -C "$T/paquet" -cf - s5-reseau-1.0 | kubectl exec -i -n builds s5-sbuild -- sh -c 'mkdir -p /w/src && tar -xf - -C /w/src'
  { echo "ZOT=$ZOT_IP"; cat <<'FIN'
set -u
export LC_ALL=C
r=0; timeout 10 bash -c "exec 3<>/dev/tcp/$ZOT/5000" 2>/dev/null || r=$?
echo "pod|$r"
(cd /w/src && dpkg-source -q -b s5-reseau-1.0 > /dev/null) || { echo "dpkg-source en échec"; exit 1; }
mkdir -p /w/home /w/sortie
export TMPDIR=/w HOME=/w/home
s=0
sbuild --chroot-mode=unshare --chroot=/opt/sbuild/trixie-amd64.tar --dist=trixie --arch=amd64 --no-apt-update --no-apt-upgrade \
  --no-apt-distupgrade --no-run-lintian --no-run-autopkgtest --no-run-piuparts --no-source-only-changes --build-dir=/w/sortie \
  "--chroot-setup-commands=truncate -s 0 /etc/apt/sources.list" /w/src/s5-reseau_1.0.dsc > /w/sbuild.out 2>&1 || s=$?
echo "sbuild|$s"
grep '^S5-RESEAU|' /w/sbuild.out | sed 's/^S5-RESEAU|//'
[ $s = 0 ] || tail -n 25 /w/sbuild.out
FIN
  } > "$T/sbuild.sh"
  pod_script s5-sbuild "$T/sbuild.sh" "$T/sbuild.log" || true
  sed 's/^/     /' "$T/sbuild.log" | cut -c1-220
  mesure "N6 témoin : connexion TCP à Zot depuis le pod (code)" "$(awk -F'|' '$1 == "pod" {print $2}' "$T/sbuild.log")" 0
  mesure "N6 : debian/rules exécuté sous sbuild (lignes)" "$(grep -c '^regles|' "$T/sbuild.log" || true)" 1
  mesure "N6 : connexion TCP à Zot depuis debian/rules sous sbuild (échec)" "$(awk -F'|' '$1 == "regles" {print ($2 != 0)}' "$T/sbuild.log")" 1
  mesure "N6 : interfaces vues par debian/rules" "$(awk -F'|' '$1 == "interfaces" {print $2}' "$T/sbuild.log" | sed 's/ *$//')" lo
  echo "     sbuild : code $(awk -F'|' '$1 == "sbuild" {print $2}' "$T/sbuild.log") (le paquet témoin peut échouer sans changer la mesure)"
  kubectl delete pod -n builds s5-sbuild --wait=false < /dev/null > /dev/null; echo "pod s5-sbuild supprimé"
  ecarts
}

etape_porte() {
  local t j v f a
  [ -s "$T/enveloppes-avant" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  attendu "TaskRuns s5 en cours" "$(kubectl get taskrun -n builds -l poc.test/jalon=s5 -o json | jq '[.items[] | select((.status.conditions[0].status // "Unknown") == "Unknown")] | length')" 0
  echo "## enveloppes de Chains (avant → après)"
  while read -r f a; do mesure "enveloppes sur $f" "$a → $(envel "$f")" "$a → $a"; done < "$T/enveloppes-avant"
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  j=$(passage "$t")
  echo "passage d'horodatage $j"
  mesure "provenance de PipelineRun la plus récente de $DEB (chemin 2 de S4d3)" \
    "$(prov_pr "$DEB" | jq -sr 'max_by(.predicate.runDetails.metadata.finishedOn).predicate.runDetails.metadata.invocationId')" "$(cat "$W/s4d3-06/uid-chemin-2")"
  echo "## deb (verdict de S4d3)"
  v=$(juger s5-deb "$REG/$DEB" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$v"
  mesure "deb : succès, violations, avertissements" "$(champ "$v" 3)|$(champ "$v" 4)|$(champ "$v" 5)" "true||trusted_task.tagged"
  mesure "deb : horodatage" "$(champ "$v" 7)|$(champ "$v" 8 | cut -d' ' -f1)" "ok|8/8"
  mesure "deb : VSA, scan" "$(champ "$v" 9)|$(champ "$v" 11)" "refus|refus"
  echo "## image sample-app (verdict de S4d3)"
  v=$(juger s5-reelle "$REG/$APP" policy.yaml porte "$SRC" "$REG/$DEPOT_BUNDLES"); echo "$v"
  mesure "sample-app : succès, violations, avertissements" "$(champ "$v" 3)|$(champ "$v" 4)|$(champ "$v" 5)" "true||trusted_task.tagged"
  mesure "sample-app : horodatage" "$(champ "$v" 7)|$(champ "$v" 8 | cut -d' ' -f1)" "ok|28/28"
  mesure "sample-app : VSA, scan" "$(champ "$v" 9)|$(champ "$v" 11)" "ok|ok"
  ecarts
}

etape_retirer() {
  kubectl delete pod -n builds s5-miroir-essai s5-sbuild --ignore-not-found --wait=true < /dev/null
  kubectl delete taskrun -n builds -l poc.test/jalon=s5 --wait=true < /dev/null
  kubectl delete pvc -n builds -l poc.test/jalon=s5 --wait=true < /dev/null
  echo "objets s5 restants dans builds : $(kubectl get taskrun,pod,pvc -n builds -l poc.test/jalon=s5 -o name < /dev/null | wc -l) (rien n'est retiré de Zot)"
}

lancer s5 S5a "$@"
