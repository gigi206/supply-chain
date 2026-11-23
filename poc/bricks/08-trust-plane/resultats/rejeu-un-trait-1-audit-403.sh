#!/usr/bin/env bash
# Rejeu un-trait-1, arrêt à « J8 (contrôleurs) » (2026-11-23, 22:07:01 UTC) : relevé en LECTURE SEULE, archivé avant tout démontage
# (l'audit de l'API vit sur sc-confiance et disparaît avec la VM). Rien n'est créé ni modifié dans le cluster.
#   - démarrages de kube-apiserver (état courant et précédent du conteneur du pod statique) ;
#   - refus 403 des lectures de Secrets par les deux contrôleurs (ceux que compte etape_controleurs), avec leurs annotations
#     d'autorisation ;
#   - rafale de 403 de tout le cluster autour du démarrage : comptes par utilisateur, premier et dernier 403 des comptes system: ;
#   - première surveillance des Secrets de builds en 200 par le contrôleur de Pipelines après le refus ;
#   - écritures sur les liaisons et rôles *-tenant-access depuis la création de builds (aucune attendue) ;
#   - refus des droits dans les journaux des deux contrôleurs (refus_droits de preuves.sh, lue dans le fichier) ;
#   - restes de l'étape interrompue : espace preuve-controleurs et liaisons qui rendent des droits aux contrôleurs.
# Usage (racine du dépôt) : DISTRO=rke2 bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C DISTRO=${DISTRO:-rke2}
J=$1
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
here=poc/bricks/08-trust-plane
. "$here/commun.sh"
eval "$(awk '/^refus_droits\(\) \{/,/^}/' "$here/preuves.sh")"
declare -F refus_droits > /dev/null || { echo "refus_droits introuvable dans preuves.sh"; exit 3; }
A=$(mktemp -d "$HOME/.cache/supply-chain-poc/audit-403.XXXXXX")   # pas dans /tmp (en mémoire) : l'audit pèse
trap 'find "$A" -delete' EXIT
{
echo "# relevé de l'arrêt du rejeu un-trait-1 à « J8 (contrôleurs) », $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD)"
sur sc-confiance "sudo sh -c 'cat \$(ls -1 $D_ETAT/server/logs/audit*.log | LC_ALL=C sort)'" > "$A/audit.json"
echo "audit de l'API lu : $(wc -l < "$A/audit.json") lignes, de $(head -1 "$A/audit.json" | jq -r .requestReceivedTimestamp) à $(tail -1 "$A/audit.json" | jq -r .requestReceivedTimestamp)"
echo "## démarrages de kube-apiserver (pod statique de sc-confiance)"
kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].status.containerStatuses[0]
  | "courant : \(.state.running.startedAt) ; précédent : \(.lastState.terminated.startedAt // "-") à \(.lastState.terminated.finishedAt // "-") ; redémarrages : \(.restartCount)"'
D=$(kubectl get pod -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].status.containerStatuses[0].state.running.startedAt}')
echo "## 403 sur les Secrets, par les deux contrôleurs (filtre d'etape_controleurs, sans --as)"
jq -c 'select(.objectRef.resource == "secrets" and .impersonatedUser == null and .responseStatus.code == 403
  and (.user.username | test("^system:serviceaccount:tekton-(pipelines:tekton-pipelines|chains:tekton-chains)-controller$")))
  | {t: .requestReceivedTimestamp, stage, user: (.user.username | split(":") | last), verb, ns: .objectRef.namespace,
     raison: .responseStatus.reason, autorisation: (.annotations // {} | with_entries(select(.key | startswith("authorization.k8s.io/"))))}' "$A/audit.json"
echo "## 403 de tout le cluster dans la fenêtre [démarrage - 30 s, démarrage + 120 s] (ResponseComplete, par utilisateur)"
d=$(date -u -d "$D" +%s)
jq -r --arg a "$(date -u -d "@$((d - 30))" +%FT%T)" --arg b "$(date -u -d "@$((d + 120))" +%FT%T)" \
  'select(.responseStatus.code == 403 and .stage == "ResponseComplete" and .requestReceivedTimestamp >= $a and .requestReceivedTimestamp <= $b)
  | "\(.user.username) \(.verb) \(.objectRef.resource)"' "$A/audit.json" | sort | uniq -c | sort -rn
echo "## étendue de la rafale : 403 des comptes system: et des comptes de service, de part et d'autre du démarrage ($D)"
jq -r --arg a "$(date -u -d "@$((d - 300))" +%FT%T)" --arg b "$(date -u -d "@$((d + 300))" +%FT%T)" \
  'select(.responseStatus.code == 403 and .stage == "ResponseComplete" and (.user.username | startswith("system:"))
  and .requestReceivedTimestamp >= $a and .requestReceivedTimestamp <= $b) | .requestReceivedTimestamp' "$A/audit.json" | sort \
  | awk 'NR == 1 {p = $0} {d = $0; n++} END {print "403 dans ±300 s : " n ", premier " p ", dernier " d}'
echo "## première surveillance des Secrets de builds en 200 par le contrôleur de Pipelines après le refus"
jq -r 'select(.objectRef.resource == "secrets" and .objectRef.namespace == "builds" and .impersonatedUser == null
  and .user.username == "system:serviceaccount:tekton-pipelines:tekton-pipelines-controller" and .responseStatus.code == 200
  and .requestReceivedTimestamp > "2026-11-23T21:21:09.219027Z") | "\(.requestReceivedTimestamp) \(.verb) \(.stage)"' "$A/audit.json" | sort | head -3
echo "## écritures sur les liaisons et rôles *-tenant-access (création de builds : $(kubectl get ns builds -o jsonpath='{.metadata.creationTimestamp}'))"
jq -r 'select((.objectRef.resource // "" | test("^(cluster)?role(binding)?s$")) and (.objectRef.name // "" | test("tenant-access"))
  and (.verb | test("^(create|update|patch|delete|deletecollection)$")) and .stage == "ResponseComplete")
  | "\(.requestReceivedTimestamp) \(.user.username) \(.verb) \(.objectRef.resource) \(.objectRef.namespace // "-")/\(.objectRef.name) \(.responseStatus.code) dryRun=\(.requestURI | test("dryRun"))"' "$A/audit.json" | sort
echo "## refus des droits dans les journaux des contrôleurs (refus_droits de preuves.sh ; watch écartés dans la minute du démarrage)"
for c in tekton-pipelines/tekton-pipelines-controller tekton-chains/tekton-chains-controller; do echo "${c#*/} : $(refus_droits "$c" 2>"$A/rd.err")" ; sed 's/^/  écarté : /' "$A/rd.err" | cut -c1-220; done
echo "## restes de l'étape interrompue"
echo "espace preuve-controleurs : $(kubectl get ns preuve-controleurs -o name 2>&1 | grep -c '^namespace/' || true) (1 = présent)"
echo "liaisons de tout le cluster vers les deux contrôleurs (ClusterRoleBinding) :"
kubectl get clusterrolebindings -o json | jq -r '.items[] | select(any(.subjects[]?; .kind == "ServiceAccount"
  and ((.namespace == "tekton-pipelines" and .name == "tekton-pipelines-controller") or (.namespace == "tekton-chains" and .name == "tekton-chains-controller"))))
  | "  \(.metadata.name) → \(.roleRef.kind)/\(.roleRef.name)"'
echo "# fin $(date -u +%FT%TZ)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
cat "$J"
