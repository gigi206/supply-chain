#!/usr/bin/env bash
# Brique 05, jalon M5a (carte de M5 et décision « Ok » du 18/11/2026) : tests négatifs de la voie rpm, chacun avec son témoin,
# par des TaskRuns isolés des tâches déjà signées et revues (règle tekton-references de la 08 : bundle de tekton/tasks par
# digest, compte build, workspaces emptyDir ou PVC) et par des pods d'essai. Aucune tâche neuve, aucune signature, aucune
# écriture dans Zot. Le rejeu de zéro est M5b, jalon à part. Modèle : s5.sh de la 06. Prédictions : resultats/m5-predictions.md,
# commitées avant tout lancement. Préparé à sec sous l'accord permanent du 18/11.
#   prealables  hôte, hors ligne : copies altérées (m5-alterer.py) d'un arbre entrees/ local, preuves des liens durs (source
#               inchangée, chaque copie ne diffère que par l'objet voulu) ; confrontation au verrou tirée de construire-rpm signée,
#               jouée avec le rpm de l'image d'outillage (rootfs de m5-sigmd5.sh, unshare -rnm chroot) sur chaque copie ;
#               rpm -i --test relevé sur la cible intacte et sur R4 ; sonde de m5-reseau.spec jouée sous unshare -rn.
#               Lecture (cluster, Zot) : pipeline signée exportée, références des tâches et paramètres figés ; politiques de
#               builds relues ; aucun objet $N-* ; TaskRuns, PVC et pods rendus et admis à blanc côté serveur ; enveloppes
#               de l'artefact de M4c comptées (état de départ)
#   banc_juges  ajoutée le 18/11/2026 après prealables, comme les suivantes (préparées à sec, accord permanent du 18/11) ; hôte
#               seul : juges des constructions sur des TaskRuns et journaux fabriqués (refus, accepté, refus dans mock, non mesuré)
#   preparer    cluster : PVC $N-entrees, puis TaskRun isolé de preparer-rpm (runc), qui tire les entrées de Zot par digest ;
#               résultats relus
#   alterer     cluster : pod runc (UID 65532) sur le PVC ; empreinte de entrees/ égale à la source locale ; sept copies par liens
#               durs (m5-alterer.py), preuves avant et après ; pod supprimé
#   fermeture   cluster : TaskRuns isolés de construire-rpm sous Kata, sur la copie intacte (témoin : rpm de M3, digest de M4c,
#               rien n'est publié), puis sur R1 à R6 ; R1, R2, R3, R5 refusées par la confrontation ; R4, R6 classées (refus dans
#               mock, accepté, non mesuré), lignes qui nomment la barrière imprimées
#   sans_kata   cluster : R8, TaskRun isolé de construire-rpm sans runtimeClassName ; PodAdmissionFailed, aucun pod
#   reseau      cluster : R7, deux pods d'essai Kata privilégiés (a sans label de tâche, b au label construire-rpm) ; TCP vers Zot
#               depuis le pod, puis mock --hermetic-build de m5-reseau.spec, sonde de %build lue dans build.log ; pods supprimés
#   invariance  lecture : 4 enveloppes sur l'artefact de M4c ; annotations de Chains des TaskRuns du jalon ; PipelineRuns de M4c
#   retirer     cluster : TaskRuns, pods et PVC au label poc.test/jalon=$N supprimés, jamais ceux de M4c ; rien n'est retiré de Zot
# $N (PREFIXE, m5 par défaut) préfixe chaque objet : une relance se fait sous un autre préfixe, jamais en purgeant.
# Aucun secret en argument de commande ; journaux filtrés (jeton|token) ; jamais le message d'une condition ni d'un Event.
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/m5.sh <étape>… (journal : resultats/m5-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "$0")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, refus, listee, lancer, chrono
R=$h05/resultats
N=${PREFIXE:-m5}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
T=$W/$N-05
mkdir -p "$T"
umask 022

# Références épinglées (m4c.sh, vérifiées dans le dépôt)
PIPELINE_REF=$REG/tekton/pipelines/sample-app-rpm@sha256:ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be   # a56a85b
PREPARER_REF=$REG/tekton/tasks/preparer-rpm@sha256:2f65f3903e98caa9944ab3fee4b67585b15d67ad477ff48a8487e8e86af5526f       # liste revue (1d5e27d)
CONSTRUIRE_REF=$REG/tekton/tasks/construire-rpm@sha256:d7f01398f188931c124273c8b5fb60e2a66c22e9d0a2dfcd229ecadee1e62164   # liste revue (1d5e27d)
PREFETCH_IMAGE=$REG/plateforme/outils-prefetch@sha256:68e0ae705de5a8f993f168d8252b3218d7d3ed76e704cf24d4414006aea7b8cc   # preparer-rpm (python3)
IMAGE_OUTILLAGE=$REG/essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771       # « Option 1 »
FERMETURE_RPM=$REG/builds/fermetures/sample-app-rpm@sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c    # M4b
FERMETURE_SOURCES=$REG/builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21   # S4b (06)
PACKAGING=$REG/entrees/sample-app/packaging-rpm@sha256:41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8      # M4a
EPOQUE=1793229566
COMMIT=6391fd437f26696847041be3226bbbf633f55a2f
DEPOT_GIT=https://sc-stockage.poc.test:3000/workspace/sample-app.git
DIGEST_ESSAI=sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119   # artefact de M4c (essai, pipeline)
IMAGE=$REG/builds/sample-app-rpm
CLE_CHAINS=$here/resultats/chains-cle-publique.pem
CLE_CHAINS_SHA=1e7b2a03f9d5d289898e63b57410aeafa4e3680e86474d4f35aaa4e01f0c5e65
LABEL_PREPARER=preparer-rpm
LABEL_CONSTRUIRE=construire-rpm   # sélectionné par construction-rpm-sans-sortie (M3)
PVC_TAILLE=2Gi   # entrees/ : 305 Mio ; copies par liens durs, fichiers neufs : R4 (92 187 o), R5, R6 (97 742 593 o)
# Hôte : arbre entrees/ de m4c.sh prealables (fermeture tirée par comparaison de M4b), rootfs de l'image d'outillage (m5-sigmd5.sh)
SOURCE_HOTE=$W/m4c-05/prealables/ws/entrees
SOURCE_EMPREINTE=d3a610bbd9e1ba6fa56abaaaec4e54addf7a4669d3c9e252b0f6ff65041be8e7   # m5-alterer.py empreinte, 273 fichiers (18/11)
RACINE=$HOME/.cache/supply-chain-poc/05/m5-sigmd5/racine
ALTERER=$h05/m5-alterer.py
SPEC_SONDE=$h05/m5-reseau.spec
CIBLE=zlib-1.2.11-40.el9.x86_64.rpm
CAS="intacte r1 r2 r3 r4 r5 r6"
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echec() { echo "KO   $*" >&2; exit 1; }
filtre() { sed "$MASQUE"; }
ZONE='{"nodeSelector": {"zone": "build"}, "tolerations": [{"key": "zone", "operator": "Equal", "value": "build", "effect": "NoSchedule"}],
  "securityContext": {"runAsNonRoot": true, "runAsUser": 65532, "seccompProfile": {"type": "RuntimeDefault"}}}'   # pr_m4c de m4c.sh

# --- hôte ---------------------------------------------------------------------------------------------------------------------
confrontation() { # fichier : bloc Python de confrontation au verrou, tiré du pas construire de construire-rpm signée
  yq '.spec.steps[] | select(.name == "construire") | .script' "$h05/construction/construire-rpm.signee.yaml" \
    | awk '/^read -r dos id < <\(python3 -I - \/w\/verrou.json "\$D" <<.FIN.$/ {b = 1; next} b && /^FIN$/ {exit} b' > "$1"
}
dans_racine() { # dossier-monté commande… : commande exécutée dans le rootfs, sans réseau, le dossier monté sur /mnt
  local d=$1; shift
  unshare -rnm bash -c 'd=$1 r=$2; shift 2; mount --bind "$d" "$r/mnt" && exec chroot "$r" "$@"' _ "$d" "$RACINE" "$@"
}
sonde_build() { # spec : section %build (« %% » rendu en « % »), telle que rpmbuild la passerait à sh -e
  awk '/^%build$/ {b = 1; next} b && /^%install$/ {exit} b' "$1" | sed 's/%%/%/g'
}

# --- objets rendus ------------------------------------------------------------------------------------------------------------
tr_json() { # nom bundle tâche params-json workspaces-json kata|- : TaskRun rendu dans $T/tr-<nom>.json
  jq -n --arg n "$1" --arg b "$2" --arg t "$3" --argjson p "$4" --argjson w "$5" --arg k "$6" --argjson z "$ZONE" --arg j "$N" '
    {apiVersion: "tekton.dev/v1", kind: "TaskRun", metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": $j}},
     spec: {taskRef: {resolver: "bundles", params: [{name: "bundle", value: $b}, {name: "name", value: $t}, {name: "kind", value: "task"}]},
       params: $p, serviceAccountName: "build", workspaces: $w,
       podTemplate: (if $k == "kata" then $z + {runtimeClassName: "kata"} else $z end)}}' > "$T/tr-$1.json"
}
pvc_json() { # nom taille
  jq -n --arg n "$1" --arg s "$2" --arg j "$N" '{apiVersion: "v1", kind: "PersistentVolumeClaim", metadata: {name: $n, namespace: "builds",
    labels: {"poc.test/jalon": $j}}, spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: $s}}}}' > "$T/pvc-$1.json"
}
pod_alterer_json() { # nom : pod runc restreint (UID 65532), image de preparer-rpm (python3), PVC monté sur /m ; sans label de tâche
  jq -n --arg n "$1" --arg i "$PREFETCH_IMAGE" --arg c "$N-entrees" --arg j "$N" --argjson z "$ZONE" '
    {apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": $j}},
     spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, enableServiceLinks: false,
       volumes: [{name: "m", persistentVolumeClaim: {claimName: $c}}, {name: "tmp", emptyDir: {}}],
       containers: [{name: "alterer", image: $i, command: ["sleep", "3600"],
         securityContext: {allowPrivilegeEscalation: false, runAsUser: 65532, runAsGroup: 65532, runAsNonRoot: true, capabilities: {drop: ["ALL"]}},
         resources: {requests: {cpu: "100m", memory: "256Mi"}, limits: {cpu: "1", memory: "1Gi"}},
         volumeMounts: [{name: "m", mountPath: "/m"}, {name: "tmp", mountPath: "/tmp"}]}]} + $z)}' > "$T/pod-$1.json"
}
pod_reseau_json() { # nom label|- : pod d'essai Kata, à la forme de l'essai de M4c (contexte du pas de construire-rpm signée au
  # niveau du conteneur), entrées intactes du PVC en lecture seule sur /e ; label tekton.dev/task posé seulement si demandé
  jq -n --arg n "$1" --arg lb "$2" --arg i "$IMAGE_OUTILLAGE" --arg c "$N-entrees" --arg j "$N" --argjson z "$ZONE" \
    --argjson sc "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .securityContext' "$h05/construction/construire-rpm.signee.yaml")" \
    --argjson res "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .resources' "$h05/construction/construire-rpm.signee.yaml")" '
    {apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds",
       labels: ({"poc.test/jalon": $j} + (if $lb == "-" then {} else {"tekton.dev/task": $lb} end))},
     spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, enableServiceLinks: false,
       runtimeClassName: "kata",
       volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: "4Gi"}}, {name: "e", persistentVolumeClaim: {claimName: $c, readOnly: true}}],
       containers: [{name: "essai", image: $i, command: ["sleep", "7200"], securityContext: $sc, resources: $res,
         volumeMounts: [{name: "w", mountPath: "/w"}, {name: "e", mountPath: "/e", subPath: "alt/intacte/entrees", readOnly: true}]}]} + $z)}' > "$T/pod-$1.json"
}
ws_pvc() { # nom-workspace sous-dossier|. [nom-workspace sous-dossier|.]… : workspaces sur le PVC $N-entrees ; « - » : emptyDir
  local a='[]'
  while [ $# -gt 0 ]; do
    a=$(jq -c --arg n "$1" --arg c "$N-entrees" --arg s "$2" '. + [if $s == "-" then {name: $n, emptyDir: {}}
      else {name: $n, persistentVolumeClaim: {claimName: $c}} + (if $s == "." then {} else {subPath: $s} end) end]' <<< "$a"); shift 2
  done
  echo "$a"
}
exporter() { # référence fichier : objet du bundle (JSON), lecture anonyme (comme s5.sh de la 06)
  SSL_CERT_FILE=$P/ca-poc.crt crane export "$REG_HOTE/${1#*/}" - < /dev/null | tar -xO > "$2"
}
params_tache() { jq -c --arg t "$2" '.spec.tasks[] | select(.name == $t) | .params // []' "$1"; }   # pipeline tâche-de-pipeline
figer() { # params-json : $(params.commit) et $(params.depot) remplacés par les valeurs de pr_m4c (commit, dépôt de Forgejo)
  jq -c --arg c "$COMMIT" --arg u "$DEPOT_GIT" 'map(.value |= (if . == "$(params.commit)" then $c elif . == "$(params.depot)" then $u else . end))' <<< "$1"
}
rendre_tout() { # pipeline exportée dans $T/pipeline.json : tous les objets de M5a dans $T
  local pp pc c
  pp=$(figer "$(params_tache "$T/pipeline.json" preparer)"); pc=$(params_tache "$T/pipeline.json" construire)
  pvc_json "$N-entrees" "$PVC_TAILLE"
  tr_json "$N-preparer" "$PREPARER_REF" preparer-rpm "$pp" "$(ws_pvc sortie .)" -
  for c in $CAS; do
    tr_json "$N-$c" "$CONSTRUIRE_REF" construire-rpm "$pc" "$(ws_pvc entrees "alt/$c/entrees" sortie -)" kata
  done
  tr_json "$N-sans-kata" "$CONSTRUIRE_REF" construire-rpm "$pc" "$(ws_pvc entrees alt/intacte/entrees sortie -)" -
  pod_alterer_json "$N-alterer"
  pod_reseau_json "$N-reseau-a" -
  pod_reseau_json "$N-reseau-b" "$LABEL_CONSTRUIRE"
}
objets() { # liste des fichiers rendus, dans l'ordre de création
  echo "$T/pvc-$N-entrees.json $T/tr-$N-preparer.json"
  for c in $CAS; do echo "$T/tr-$N-$c.json"; done
  echo "$T/tr-$N-sans-kata.json $T/pod-$N-alterer.json $T/pod-$N-reseau-a.json $T/pod-$N-reseau-b.json"
}
a_blanc() { # fichier : création admise à blanc côté serveur (rien n'est créé) ; jamais le texte du refus, seulement des motifs
  local r=0
  kubectl create --dry-run=server -o name -f "$1" < /dev/null > /dev/null 2> "$T/a-blanc.err" || r=$?
  if [ $r = 0 ]; then echo "OK   admis à blanc : ${1##*/}"
  else echo "KO   refusé à blanc : ${1##*/} (code $r ; motifs PodSecurity $(grep -ci 'podsecurity\|pod security' "$T/a-blanc.err" || true), ValidatingAdmissionPolicy $(grep -ci 'validatingadmissionpolicy' "$T/a-blanc.err" || true), kyverno $(grep -ci kyverno "$T/a-blanc.err" || true))" >&2; exit 1; fi
}
politique_relue() { # m4c.sh : construction-rpm-sans-sortie relue, aucune politique de builds n'autorise de trafic à construire-rpm
  local t=$T/politiques.json
  { kubectl get networkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "NetworkPolicy"'
    kubectl get ciliumnetworkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "CiliumNetworkPolicy"'; } | jq -s '{items: .}' > "$t"
  echo "politiques de builds : $(jq -r '[.items[] | "\(.kind) \(.metadata.name)"] | join(", ")' "$t")"
  attendu "construction-rpm-sans-sortie : sélecteur, types, règles d'entrée et de sortie" \
    "$(jq -c '[.items[] | select(.kind == "NetworkPolicy" and .metadata.name == "construction-rpm-sans-sortie")
      | [.spec.podSelector, (.spec.policyTypes | sort), (.spec.ingress // []), (.spec.egress // [])]]' "$t")" \
    "[[{\"matchLabels\":{\"tekton.dev/task\":\"$LABEL_CONSTRUIRE\"}},[\"Egress\",\"Ingress\"],[],[]]]"
  attendu "politiques de builds qui sélectionnent $LABEL_CONSTRUIRE et autorisent du trafic" "$(jq -r -L "$here" --arg l "$LABEL_CONSTRUIRE" \
    'include "selecteurs"; [.items[] | select(selectionne({"tekton.dev/task": $l}) and autorise) | nom] | join(", ")' "$t")" ""
  echo "relevé : politiques de builds qui sélectionnent un pod sans label de tâche : $(jq -r -L "$here" --arg j "$N" \
    'include "selecteurs"; [.items[] | select(selectionne({"poc.test/jalon": $j})) | nom] | join(", ")' "$t")"
}
enveloppes() { # nombre d'enveloppes valides (clé de Chains, sans journal de transparence, lecture anonyme) sur l'artefact de M4c
  cosign verify-attestation --key "$CLE_CHAINS" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" \
    "$REG_HOTE/${IMAGE#*/}@$DIGEST_ESSAI" < /dev/null 2> /dev/null | grep -c . || true
}

etape_prealables() {
  local b=$T/banc-hote-$(date -u +%Y%m%dT%H%M%SZ) c o r m k   # correction du 18/11 : un dossier par passage (relance sous le même préfixe)
  echo "## hôte, hors ligne"
  attendu "rpm du rootfs de l'image d'outillage (m5-sigmd5.sh)" "$(dans_racine "$h05" /usr/bin/rpm --version)" "RPM version 4.16.1.3"
  echo "m5-alterer.py $(sha256sum < "$ALTERER" | cut -c1-64) ; m5-reseau.spec $(sha256sum < "$SPEC_SONDE" | cut -c1-64)"
  attendu "source locale entrees/ (m4c.sh prealables) : empreinte avant" "$(python3 -I "$ALTERER" empreinte "$SOURCE_HOTE")" "$SOURCE_EMPREINTE"
  [ ! -e "$b" ] || echec "$b existe déjà : relancer sous un autre PREFIXE"
  mkdir -p "$b"
  python3 -I "$ALTERER" faire "$SOURCE_HOTE" "$b/alt" | sed 's/^/     /'
  r=0; python3 -I "$ALTERER" comparer "$SOURCE_HOTE" "$b/alt" > "$b/comparer.txt" || r=$?
  sed 's/^/     /' "$b/comparer.txt"
  attendu "copies : chacune ne diffère de la source que par l'objet voulu (code, lignes OK)" "$r $(grep -c '^OK ' "$b/comparer.txt")" "0 7"
  attendu "source locale : empreinte après (liens durs rompus à chaque altération)" "$(python3 -I "$ALTERER" empreinte "$SOURCE_HOTE")" "$SOURCE_EMPREINTE"
  confrontation "$b/conf.py"
  echo "confrontation tirée de construire-rpm signée : $(wc -l < "$b/conf.py") lignes, sha256 $(sha256sum < "$b/conf.py" | cut -c1-64)"
  attendu "confrontation : appel de rpm -qp --qf %{SIGMD5}" "$(grep -c "subprocess.run(\['rpm', '-qp', '--qf', '%{SIGMD5}'" "$b/conf.py")" 1
  echo "## confrontation jouée dans le rootfs, avec le vrai rpm, sur chaque copie"
  for c in $CAS; do
    r=0; o=$(dans_racine "$b" /usr/bin/python3 -I - "/mnt/alt/$c/entrees/verrou-rpm.json" "/mnt/alt/$c/entrees/fermeture/depot" < "$b/conf.py" 2>&1) || r=$?   # comme le pas : python3 -I - verrou depot
    printf '%s\n' "$o" > "$b/conf-$c.txt"
    echo "     $c : code $r : $(tr '\n' ' ' < "$b/conf-$c.txt" | cut -c1-200)"
    case $c in
      intacte|r4|r6) m="fermeture confrontée au verrou : 222 rpm (noms et sigmd5)"; k=0 ;;
      r1) m="sigmd5 différent du verrou : $CIBLE"; k=1 ;;
      r2) m="fermeture : 1 objet(s) hors du verrou, de repodata/ et du dossier dir: : ['m5-en-trop.rpm']"; k=1 ;;
      r3) m="fermeture : 1 rpm du verrou absent(s) : ['$CIBLE']"; k=1 ;;
      r5) m="manifest.json du dossier dir: différent du pull_digest"; k=1 ;;
    esac
    attendu "confrontation sur $c : code, ligne attendue" "$r $(grep -cF -- "$m" "$b/conf-$c.txt" || true)" "$k 1"
  done
  echo "## relevé : rpm -i --test (racine vide, --nodeps) sur la cible intacte et sur R4"
  for c in intacte r4; do
    r=0; o=$(dans_racine "$b" /usr/bin/rpm --root "/tmp/$N-racine-$c" --dbpath "/tmp/$N-db-$c" -i --test --nodeps "/mnt/alt/$c/entrees/fermeture/depot/$CIBLE" 2>&1) || r=$?
    echo "     $c : code $r : $(tr '\n' ' ' <<< "$o" | cut -c1-240)"
  done
  echo "## sonde de m5-reseau.spec (%build) jouée par sh -e sous unshare -rn"
  sonde_build "$SPEC_SONDE" > "$b/sonde.sh"
  r=0; unshare -rn sh -e "$b/sonde.sh" < /dev/null > "$b/sonde.txt" 2>&1 || r=$?
  sed 's/^/     /' "$b/sonde.txt"
  attendu "sonde : code, marqueurs de début et de fin" "$r $(grep -c '^M5-SONDE début de %build$' "$b/sonde.txt") $(grep -c '^M5-SONDE fin de %build$' "$b/sonde.txt")" "0 1 1"
  attendu "sonde sans réseau : interfaces vues" "$(sed -n 's/^M5-SONDE interfaces : //p' "$b/sonde.txt")" "lo "
  attendu "sonde sans réseau : connexion refusée (code non nul)" "$(sed -n 's/^M5-SONDE tcp 192.168.161.13\/5000 code //p' "$b/sonde.txt" | grep -c '^[1-9][0-9]*$')" 1

  echo "## lecture : cluster et Zot"
  attendu "clé publique de Chains (sha256)" "$(sha256sum < "$CLE_CHAINS" | cut -c1-64)" "$CLE_CHAINS_SHA"
  exporter "$PIPELINE_REF" "$T/pipeline.json"
  attendu "pipeline signée exportée de Zot : nom, tâches" \
    "$(jq -r '.metadata.name + " " + ([.spec.tasks[] | .name + ":" + (.taskRef.params[] | select(.name == "name") | .value)] | join(" "))' "$T/pipeline.json")" \
    "sample-app-rpm preparer:preparer-rpm construire:construire-rpm publier:publier-image"
  attendu "pipeline : bundle de preparer" "$(jq -r '.spec.tasks[] | select(.name == "preparer") | .taskRef.params[] | select(.name == "bundle") | .value' "$T/pipeline.json")" "$PREPARER_REF"
  attendu "pipeline : bundle de construire" "$(jq -r '.spec.tasks[] | select(.name == "construire") | .taskRef.params[] | select(.name == "bundle") | .value' "$T/pipeline.json")" "$CONSTRUIRE_REF"
  for r in "$PREPARER_REF" "$CONSTRUIRE_REF"; do
    if listee "$r"; then echo "OK   dans la liste revue : $r"; else echec "absente de la liste revue : $r"; fi
  done
  o=$(figer "$(params_tache "$T/pipeline.json" preparer)")
  attendu "paramètres de preparer, figés (triés par nom)" "$(jq -r 'sort_by(.name) | map(.name + "=" + .value) | join(" ")' <<< "$o")" \
    "commit=$COMMIT depot=$DEPOT_GIT fermeture-rpm=$FERMETURE_RPM fermeture-sources=$FERMETURE_SOURCES packaging=$PACKAGING"
  attendu "paramètres de construire" "$(params_tache "$T/pipeline.json" construire)" "[{\"name\":\"epoque\",\"value\":\"$EPOQUE\"}]"
  politique_relue
  echo "relevé : classe de stockage par défaut : $(kubectl get storageclass -o json < /dev/null | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | "\(.metadata.name) (\(.provisioner))"] | join(", ")')"
  echo "relevé : nœuds de la zone build, stockage éphémère allouable : $(kubectl get nodes -l zone=build -o json < /dev/null | jq -r '[.items[] | "\(.metadata.name) \(.status.allocatable["ephemeral-storage"])"] | join(", ")')"
  attendu "objets du jalon déjà présents (TaskRuns, pods, PVC au label poc.test/jalon=$N)" \
    "$(kubectl get taskrun,pod,pvc -n builds -l "poc.test/jalon=$N" -o name < /dev/null | wc -l)" 0
  for o in "$N-entrees" "$N-preparer" "$N-alterer" "$N-reseau-a" "$N-reseau-b" "$N-sans-kata" $(for c in $CAS; do echo "$N-$c"; done); do
    [ -z "$(kubectl get taskrun,pod,pvc -n builds --field-selector "metadata.name=$o" -o name < /dev/null 2> /dev/null)" ] || echec "objet $o déjà présent dans builds"
  done
  echo "OK   aucun objet de builds ne porte un nom du jalon"
  rendre_tout
  attendu "objets rendus : variables de pipeline restantes" "$(cat $(objets) | grep -c '\$(params\.' || true)" 0
  attendu "TaskRuns de construire : runtimeClassName (7 sous Kata, sans-kata sans)" \
    "$(for c in $CAS sans-kata; do jq -r '.spec.podTemplate.runtimeClassName // "-"' "$T/tr-$N-$c.json"; done | paste -sd' ')" "kata kata kata kata kata kata kata -"
  attendu "pods d'essai de R7 : labels de tâche (a, b)" \
    "$(for c in a b; do jq -r '.metadata.labels["tekton.dev/task"] // "-"' "$T/pod-$N-reseau-$c.json"; done | paste -sd' ')" "- $LABEL_CONSTRUIRE"
  attendu "pods d'essai de R7 : contexte du conteneur, celui du pas signé (JSON trié)" "$(jq -cS '.spec.containers[0].securityContext' "$T/pod-$N-reseau-a.json")" \
    '{"allowPrivilegeEscalation":true,"privileged":true,"runAsGroup":0,"runAsNonRoot":false,"runAsUser":0}'   # correction du 18/11 : ordre des clés
  for o in $(objets); do a_blanc "$o"; done
  echo "relevé : PipelineRuns de M4c gardés : $(kubectl get pipelinerun -n builds m4c-rpm-1 m4c-rpm-2 -o name < /dev/null | paste -sd' ')"
  attendu "enveloppes valides sur l'artefact de M4c (état de départ)" "$(enveloppes)" 4
}

# --- M5a, étapes du cluster (ajoutées le 18/11/2026 après prealables, préparées à sec sous l'accord permanent du 18/11) -------
RPM_M3_SHA=864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f   # m3_comparaison, M4c
ZOT_CIBLE=192.168.161.13/5000   # première cible des témoins de construire-rpm, sonde de m5-reseau.spec
present() { kubectl get "$1" -n builds "$2" -o name < /dev/null > /dev/null 2>&1; }   # type nom
creer() { # fichier type nom : garde d'absence (jamais de purge), puis création
  ! present "$2" "$3" || echec "$2 $3 déjà présent : relancer sous un autre PREFIXE"
  kubectl create -f "$1" < /dev/null > /dev/null
  echo "$2 $3 créé à $(date -u +%H:%M:%S)"
}
tr_attendre() { # nom : fin du TaskRun (3600 s au plus) ; TaskRun, pod et journaux filtrés dans $T ; « statut|raison »
  local st="" p
  for _ in $(seq 1800); do
    st=$(kubectl get taskrun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' < /dev/null 2> /dev/null || true)
    [ -n "$st" ] && [ "$st" != Unknown ] && break; sleep 2
  done
  kubectl get taskrun -n builds "$1" -o json < /dev/null > "$T/$1.tr.json"
  p=$(jq -r '.status.podName // ""' "$T/$1.tr.json")
  if [ -n "$p" ] && present pod "$p"; then
    kubectl logs -n builds "$p" --all-containers < /dev/null 2>&1 | filtre > "$T/$1.log"
    kubectl get pod -n builds "$p" -o json < /dev/null > "$T/$1.pod.json"
  else : > "$T/$1.log"; echo '{}' > "$T/$1.pod.json"; fi
  echo "TaskRun $1 terminé à $(date -u +%H:%M:%S)" >&2
  jq -r '.status.conditions[] | select(.type == "Succeeded") | "\(.status)|\(.reason)"' "$T/$1.tr.json"
}
tr_resultat() { jq -r --arg r "$2" '[.status.results[]? | select(.name == $r) | .value][0] // ""' "$T/$1.tr.json"; }
tr_pod() { jq -r '"\(.metadata.labels["tekton.dev/task"] // "-")|\(.spec.nodeName // "-")|\(.spec.runtimeClassName // "-")"' "$T/$1.pod.json"; }
nb() { grep -cF -- "$2" "$1" 2> /dev/null || true; }   # fichier motif : nombre de lignes qui contiennent le motif
motifs_message() { # nom : motifs comptés dans le message de la condition Succeeded, jamais affiché ni écrit
  local m
  m=$(jq -r '.status.conditions[] | select(.type == "Succeeded") | .message' "$T/$1.tr.json")
  echo "PodSecurity $(grep -ci 'podsecurity\|pod security' <<< "$m" || true), privileged $(grep -ci 'privileged' <<< "$m" || true), ValidatingAdmissionPolicy $(grep -ci 'validatingadmissionpolicy' <<< "$m" || true), kyverno $(grep -ci kyverno <<< "$m" || true), runtimeClassName $(grep -ci runtimeclass <<< "$m" || true)"
}
# Juge d'une construction (fichiers $T/<nom>.tr.json et $T/<nom>.log) : « statut|raison|confrontation passée|ligne de refus|rc de mock|
# sha256 du rpm|DIGEST_CONSTRUIT », puis classe : refus-confrontation, refus-mock, accepte, non-mesure
juger_construction() { # nom motif-de-refus|-
  local f=$T/$1.log s rc sha d conf ref
  s=$(jq -r '.status.conditions[] | select(.type == "Succeeded") | "\(.status)|\(.reason)"' "$T/$1.tr.json")
  conf=$(nb "$f" "fermeture confrontée au verrou : 222 rpm (noms et sigmd5)")
  if [ "$2" = - ]; then ref=0; else ref=$(nb "$f" "$2"); fi
  rc=$(sed -n 's/^mock --hermetic-build : rc \([0-9]*\) en .*/\1/p' "$f" | head -n 1)
  sha=$(sed -n 's/^rpm : sample-app-[^ ]*\.x86_64\.rpm sha256 \([0-9a-f]\{64\}\) .*/\1/p' "$f" | head -n 1)
  d=$(tr_resultat "$1" DIGEST_CONSTRUIT)
  echo "$s|$conf|$ref|${rc:--}|${sha:--}|${d:--}"
}
classer() { # ligne de juger_construction : classe
  local s conf ref rc
  IFS='|' read -r s _ conf ref rc _ _ <<< "$1"
  if [ "$s" = True ]; then echo accepte
  elif [ "$s" = False ] && [ "$conf" = 0 ] && [ "$ref" = 1 ] && [ "$rc" = - ]; then echo refus-confrontation
  elif [ "$s" = False ] && [ "$conf" = 1 ] && [ "$rc" != - ] && [ "$rc" != 0 ]; then echo refus-mock
  else echo non-mesure; fi
}
barriere() { # nom : lignes du journal qui nomment une barrière (digest, somme de contrôle, vérification), filtrées et coupées
  grep -iE 'digest|checksum|verify|BAD|mismatch|corrupt|signature|fallback' "$T/$1.log" | grep -v '^paquet ' | head -n 15 | cut -c1-240 | sed 's/^/     /' || true
}
etape_banc_juges() { # hôte seul : juger_construction et classer sur des TaskRuns et journaux fabriqués, un par issue
  local n l c m
  for n in refus succes mock avant; do
    case $n in
      succes) jq -n --arg d "$DIGEST_ESSAI" '{status: {conditions: [{type: "Succeeded", status: "True", reason: "Succeeded"}], results: [{name: "DIGEST_CONSTRUIT", value: $d}]}}' ;;
      *) jq -n '{status: {conditions: [{type: "Succeeded", status: "False", reason: "Failed"}], results: []}}' ;;
    esac > "$T/banc-$n.tr.json"
  done
  printf 'invité : x\nsigmd5 différent du verrou : %s (5832caf6)\nconfrontation au verrou en échec\n' "$CIBLE" > "$T/banc-refus.log"
  printf 'fermeture confrontée au verrou : 222 rpm (noms et sigmd5), image\nmock --hermetic-build : rc 0 en 200 s\nrpm : sample-app-1.0.0-2.el9.x86_64.rpm sha256 %s (1 octets) ; NEVRA x\n' "$RPM_M3_SHA" > "$T/banc-succes.log"
  printf 'fermeture confrontée au verrou : 222 rpm (noms et sigmd5), image\nmock --hermetic-build : rc 30 en 20 s\nmock en échec\n' > "$T/banc-mock.log"
  printf 'invité : x\nKO   192.168.161.13/5000 joint\n' > "$T/banc-avant.log"
  while IFS='#' read -r c m l; do
    attendu "juge sur banc-$c (motif « ${m:0:40} »)" "$(juger_construction "banc-$c" "$m")|$(classer "$(juger_construction "banc-$c" "$m")")" "$l"
  done <<EOF
refus#sigmd5 différent du verrou : $CIBLE#False|Failed|0|1|-|-|-|refus-confrontation
succes#-#True|Succeeded|1|0|0|$RPM_M3_SHA|$DIGEST_ESSAI|accepte
mock#-#False|Failed|1|0|30|-|-|refus-mock
avant#-#False|Failed|0|0|-|-|-|non-mesure
refus#-#False|Failed|0|0|-|-|-|non-mesure
EOF
}

etape_preparer() { # PVC $N-entrees, puis TaskRun isolé de preparer-rpm (runc) qui remplit entrees/ ; résultats relus
  local n=$N-preparer s a
  rendre_tout
  attendu "enveloppes valides sur l'artefact de M4c (avant)" "$(enveloppes)" 4
  creer "$T/pvc-$N-entrees.json" pvc "$N-entrees"
  creer "$T/tr-$n.json" taskrun "$n"
  s=$(tr_attendre "$n")
  echo "pod : $(tr_pod "$n") ; journal : $(wc -l < "$T/$n.log") lignes"
  grep -v '^paquet ' "$T/$n.log" | tail -n 12 | cut -c1-220 | sed 's/^/     /'
  attendu "TaskRun $n" "$s" "True|Succeeded"
  attendu "pod de $n : label de tâche, runtimeClassName" "$(tr_pod "$n" | cut -d'|' -f1,3)" "$LABEL_PREPARER|-"
  attendu "résultat CHAINS-GIT_URL" "$(tr_resultat "$n" CHAINS-GIT_URL)" "$DEPOT_GIT"
  attendu "résultat CHAINS-GIT_COMMIT" "$(tr_resultat "$n" CHAINS-GIT_COMMIT)" "$COMMIT"
  for a in "FERMETURE_RPM $FERMETURE_RPM" "FERMETURE_SOURCES $FERMETURE_SOURCES" "PACKAGING $PACKAGING"; do
    set -- $a
    attendu "résultat $1_ARTIFACT_INPUTS" "$(tr_resultat "$n" "$1_ARTIFACT_INPUTS")" "{\"uri\":\"oci://${2%@*}\",\"digest\":\"${2#*@}\"}"
  done
  echo "relevé : annotation de Chains sur $n : $(kubectl get taskrun -n builds "$n" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}' < /dev/null)"
}

etape_alterer() { # pod runc sur le PVC : empreinte de entrees/ (égale à la source locale), sept copies, preuves ; pod supprimé
  local p=$N-alterer r
  present taskrun "$N-preparer" || echec "lancer d'abord preparer"
  rendre_tout
  creer "$T/pod-$p.json" pod "$p"
  kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null || echec "pod $p non prêt"
  kubectl exec -i -n builds "$p" -- sh -c 'cat > /tmp/a.py' < "$ALTERER"
  attendu "m5-alterer.py dans le pod (sha256)" "$(kubectl exec -n builds "$p" -- python3 -I -c 'import hashlib; print(hashlib.sha256(open("/tmp/a.py", "rb").read()).hexdigest())' < /dev/null)" "$(sha256sum < "$ALTERER" | cut -c1-64)"
  attendu "entrees/ du PVC (preparer-rpm) : empreinte, égale à la source locale" "$(kubectl exec -n builds "$p" -- python3 -I /tmp/a.py empreinte /m/entrees < /dev/null)" "$SOURCE_EMPREINTE"
  kubectl exec -n builds "$p" -- python3 -I /tmp/a.py faire /m/entrees /m/alt < /dev/null | cut -c1-240 | sed 's/^/     /'
  r=0; kubectl exec -n builds "$p" -- python3 -I /tmp/a.py comparer /m/entrees /m/alt < /dev/null > "$T/comparer.txt" || r=$?
  cut -c1-240 "$T/comparer.txt" | sed 's/^/     /'
  attendu "copies : chacune ne diffère de la source que par l'objet voulu (code, lignes OK)" "$r $(grep -c '^OK ' "$T/comparer.txt")" "0 7"
  attendu "entrees/ du PVC : empreinte après" "$(kubectl exec -n builds "$p" -- python3 -I /tmp/a.py empreinte /m/entrees < /dev/null)" "$SOURCE_EMPREINTE"
  echo "relevé : PVC : $(kubectl exec -n builds "$p" -- df -k /m < /dev/null | awk 'NR == 2 {print $3 " kB utilisés sur " $2}')"
  kubectl delete pod -n builds "$p" --wait=true < /dev/null > /dev/null; echo "pod $p supprimé"
}

etape_fermeture() { # témoin puis R1 à R6 : TaskRuns isolés de construire-rpm sous Kata sur chaque copie ; rien n'est publié
  local c n s l k m
  ! present pod "$N-alterer" || echec "pod $N-alterer encore présent"
  [ -s "$T/comparer.txt" ] && [ "$(grep -c '^OK ' "$T/comparer.txt")" = 7 ] || echec "lancer d'abord alterer"
  rendre_tout
  for c in $CAS; do
    n=$N-$c
    echo "## $c"
    creer "$T/tr-$n.json" taskrun "$n"
    s=$(tr_attendre "$n")
    echo "pod : $(tr_pod "$n") ; statut $s"
    grep -v '^paquet ' "$T/$n.log" | grep -E 'confront|sigmd5|objet|absent|manifest|mock|rpm :|écriture refusée|témoin' | cut -c1-220 | sed 's/^/     /' || true
    case $c in
      intacte|r4|r6) m=- ;;
      r1) m="sigmd5 différent du verrou : $CIBLE" ;;
      r2) m="fermeture : 1 objet(s) hors du verrou, de repodata/ et du dossier dir: : ['m5-en-trop.rpm']" ;;
      r3) m="fermeture : 1 rpm du verrou absent(s) : ['$CIBLE']" ;;
      r5) m="manifest.json du dossier dir: différent du pull_digest" ;;
    esac
    l=$(juger_construction "$n" "$m"); k=$(classer "$l")
    echo "juge : $l ; classe : $k"
    attendu "pod de $n : label de tâche, runtimeClassName" "$(tr_pod "$n" | cut -d'|' -f1,3)" "$LABEL_CONSTRUIRE|kata"
    attendu "$n : écriture refusée sur les entrées, témoins TCP atteints" "$(grep -c '^invité : .*, écriture refusée$' "$T/$n.log") $(grep -c '^témoin TCP .* : échec, code [0-9]* (attendu)$' "$T/$n.log")" "1 3"
    case $c in
      intacte)
        attendu "témoin : TaskRun, classe" "$s $k" "True|Succeeded accepte"
        attendu "témoin : rpm égal à celui de M3" "$(cut -d'|' -f6 <<< "$l")" "$RPM_M3_SHA"
        attendu "témoin : DIGEST_CONSTRUIT égal à l'artefact de M4c" "$(cut -d'|' -f7 <<< "$l")" "$DIGEST_ESSAI" ;;
      r1|r2|r3|r5)
        attendu "$c : classe (refus par la confrontation, mock jamais lancé)" "$k" refus-confrontation ;;
      r4|r6)
        echo "relevé : $c, classe : $k (refus-mock, accepte ou non-mesure ; prédictions écrites avant le lancement)"
        echo "lignes qui nomment une barrière :"; barriere "$n"
        [ "$k" != accepte ] || echo "CONSTAT : $c accepté ; rpm $(cut -d'|' -f6 <<< "$l") (M3 : $RPM_M3_SHA), DIGEST_CONSTRUIT $(cut -d'|' -f7 <<< "$l")" ;;
    esac
  done
}

etape_sans_kata() { # R8 : TaskRun isolé de construire-rpm sans runtimeClassName, sur la copie intacte
  local n=$N-sans-kata s
  present taskrun "$N-intacte" || echec "lancer d'abord fermeture"
  rendre_tout
  creer "$T/tr-$n.json" taskrun "$n"
  s=$(tr_attendre "$n")
  echo "statut $s ; pod : $(jq -r '.status.podName // "-"' "$T/$n.tr.json") ; motifs du message : $(motifs_message "$n")"
  attendu "R8 : TaskRun refusé à la création du pod" "$s" "False|PodAdmissionFailed"
  attendu "R8 : aucun pod" "$(kubectl get pod -n builds -l "tekton.dev/taskRun=$n" -o name < /dev/null | wc -l)" 0
}

etape_reseau() { # R7 : deux pods d'essai Kata privilégiés (a : sans label de tâche ; b : label construire-rpm), entrées intactes
  # en lecture seule ; connexion TCP à Zot depuis le pod, puis mock --hermetic-build de m5-reseau.spec ; sonde lue dans build.log
  local c p r
  present taskrun "$N-intacte" || echec "lancer d'abord fermeture"
  rendre_tout
  cat > "$T/reseau-pod.sh" <<EOF
set -u
echo "M5-POD uid \$(id -u) ; interfaces : \$(sed -n '3,\$ s/:.*//p' /proc/net/dev | tr -d ' ' | tr '\n' ' ')"
r=0; timeout 10 bash -c 'exec 3<>/dev/tcp/$ZOT_CIBLE' 2> /dev/null || r=\$?
echo "M5-POD tcp $ZOT_CIBLE code \$r"
mkdir -p /w/src /w/fermeture && cp -a /e/fermeture/. /w/fermeture/ && cp /e/verrou-rpm.json /w/verrou.json || { echo "M5-POD copie des entrées en échec"; exit 1; }
t=\$(date +%s); r=0
mock --hermetic-build /w/verrou.json /w/fermeture/depot --isolation=simple --no-cleanup-after --config-opts=basedir=/w/mock \\
  --config-opts=cache_topdir=/w/mock-cache --resultdir=/w/res --spec /w/m5-reseau.spec --sources /w/src > /w/mock.out 2>&1 || r=\$?
echo "M5-POD mock rc \$r en \$((\$(date +%s) - t)) s"
grep '^M5-SONDE' /w/res/build.log 2> /dev/null || echo "M5-POD aucune ligne M5-SONDE dans build.log"
[ \$r = 0 ] || { echo "----- fin de mock.out -----"; tail -n 30 /w/mock.out; }
ls /w/res/*.rpm 2> /dev/null | sed 's/^/M5-POD produit : /'
EOF
  for c in a b; do
    p=$N-reseau-$c
    echo "## bras $c ($(jq -r '.metadata.labels["tekton.dev/task"] // "sans label de tâche"' "$T/pod-$p.json"))"
    creer "$T/pod-$p.json" pod "$p"
    kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null || echec "pod $p non prêt"
    echo "pod prêt sur $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName {.spec.runtimeClassName}' < /dev/null)"
    kubectl exec -i -n builds "$p" -- sh -c 'cat > /w/m5-reseau.spec' < "$SPEC_SONDE"
    kubectl exec -i -n builds "$p" -- sh -c 'cat > /w/s.sh' < "$T/reseau-pod.sh"
    attendu "$p : spec et script copiés (sha256)" "$(kubectl exec -n builds "$p" -- sh -c 'sha256sum /w/m5-reseau.spec /w/s.sh | cut -c1-64 | paste -sd" "' < /dev/null)" \
      "$(sha256sum < "$SPEC_SONDE" | cut -c1-64) $(sha256sum < "$T/reseau-pod.sh" | cut -c1-64)"
    r=0; timeout 1800 kubectl exec -n builds "$p" -- bash /w/s.sh < /dev/null 2>&1 | filtre > "$T/reseau-$c.log" || r=$?
    cut -c1-220 "$T/reseau-$c.log" | sed 's/^/     /'
    kubectl delete pod -n builds "$p" --wait=false < /dev/null > /dev/null; echo "pod $p supprimé (code de l'exec : $r)"
    echo "relevé : bras $c : pod tcp $(sed -n "s#^M5-POD tcp $ZOT_CIBLE code ##p" "$T/reseau-$c.log") ; %build : début $(nb "$T/reseau-$c.log" 'M5-SONDE début de %build'), fin $(nb "$T/reseau-$c.log" 'M5-SONDE fin de %build'), tcp $(sed -n "s#^M5-SONDE tcp $ZOT_CIBLE code ##p" "$T/reseau-$c.log"), interfaces « $(sed -n 's/^M5-SONDE interfaces : //p' "$T/reseau-$c.log") »"
  done
}

etape_invariance() { # lecture : enveloppes sur l'artefact de M4c ; annotations de Chains des TaskRuns du jalon ; PipelineRuns de M4c
  attendu "enveloppes valides sur l'artefact de M4c (après)" "$(enveloppes)" 4
  echo "relevé : TaskRuns du jalon, annotation chains.tekton.dev/signed : $(kubectl get taskrun -n builds -l "poc.test/jalon=$N" -o json < /dev/null | jq -r '[.items[] | "\(.metadata.name)=\(.metadata.annotations["chains.tekton.dev/signed"] // "-")"] | join(" ")')"
  attendu "PipelineRuns de M4c gardés" "$(kubectl get pipelinerun -n builds m4c-rpm-1 m4c-rpm-2 -o name < /dev/null | wc -l)" 2
}

etape_retirer() { # TaskRuns, pods et PVC du jalon (label poc.test/jalon=$N) supprimés ; rien d'autre ; rien n'est retiré de Zot
  local o
  o=$(kubectl get taskrun,pod,pvc -n builds -l "poc.test/jalon=$N" -o name < /dev/null)
  echo "à retirer : $(echo "$o" | grep -c .) objet(s) : $(echo "$o" | paste -sd' ')"
  ! grep -q 'm4c-rpm' <<< "$o" || echec "un objet de M4c porte le label du jalon"
  kubectl delete taskrun -n builds -l "poc.test/jalon=$N" --wait=true < /dev/null > /dev/null
  kubectl delete pod -n builds -l "poc.test/jalon=$N" --wait=true < /dev/null > /dev/null
  kubectl delete pvc -n builds -l "poc.test/jalon=$N" --wait=true < /dev/null > /dev/null
  attendu "objets du jalon restants" "$(kubectl get taskrun,pod,pvc -n builds -l "poc.test/jalon=$N" -o name < /dev/null | wc -l)" 0
  attendu "PipelineRuns de M4c gardés" "$(kubectl get pipelinerun -n builds m4c-rpm-1 m4c-rpm-2 -o name < /dev/null | wc -l)" 2
}

lancer m5 "05 M5a" "$@"
