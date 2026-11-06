#!/usr/bin/env bash
# Brique 08c : valeurs figées des étapes de preuves.sh sans passage sous H5 (reglec, attseule, enveloppes, reserve_c, decision3, bascule,
# controle6, controle7, temoins_scan, test 5), relevées sans les rejouer. Rien n'est créé : lectures de l'API, de Zot (anonyme), de l'audit
# de Zot et de l'audit de l'API. Aucune valeur de secret : présence et taille non nulle des fichiers seulement. Continue après un écart,
# pour tous les lister. Refuse si le journal existe déjà.
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/08c-durcissement/essais-h5-figees.sh   (journal : resultats/durcissement-h5_figees_sec.log)
set -uo pipefail
export LC_ALL=C
d8c=$(cd "$(dirname "$0")" && pwd)
JOURNAL=${JOURNAL:-$d8c/resultats/durcissement-h5_figees_sec.log}
[ ! -e "$JOURNAL" ] || { echo "$JOURNAL existe déjà, rien relevé"; exit 2; }
here=$d8c/../08-trust-plane
h7=$here/../07a-sbom-grype
. "$here/commun.sh"
T=$HOME/.cache/supply-chain-poc/08c-sec-figees
mkdir -p "$T"
trap 'rm -rf "${T:?}"' EXIT
exec > >(sed -u "s#$HOME#~#g" | tee "$JOURNAL") 2>&1

APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # politique.sh
BUILDKIT_DEPOT=amont/moby/buildkit
BUILDKIT_DIGEST=sha256:ace6811c21334fa502644b9711e0ea48e8539c5c2a843c2325dfb7b987ab260b   # preuves.sh
H5_DENY=2026-11-06T19:26:00Z
ecarts=0
ko() { echo "KO   $*"; ecarts=$((ecarts + 1)); }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || ko "$1 : $2 (attendu : $3)"; }
manifeste() { # dépôt référence : code HTTP d'un HEAD anonyme
  curl -s -o /dev/null -w '%{http_code}' -I --cacert "$P/ca-poc.crt" \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://$REG_HOTE/v2/$1/manifests/$2"
}
tags() { curl -s -o /dev/null -w '%{http_code}' --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$1/tags/list"; }   # dépôt : code HTTP
referrers() { curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$1/referrers/$APP_DIGEST" | jq '.manifests | length'; }

echo "# essais-h5-figees.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), DISTRO=$DISTRO"
echo "Prédiction (écrite le 06/11/2026 à 22:55 UTC, avant ce relevé, après lecture du code, rien de mesuré sur ces valeurs) :"
echo "- C1 ConfigMap porte : 14 clés sur 14 identiques aux fichiers versionnés ; cm_porte de controle6 et controle7 n'y changerait rien"
echo "- C2 empreintes DER : clé de VSA 578dd771 (R2), clé du scanner 8cbcbb4e (G3)"
echo "- C3 fichiers de l'hôte présents, non vides, malgré S1 : pipeline.ref, taches.key, forgejo-webhook.secret, forgejo-admin.token,"
echo "  zot-poc-ecriture.password, zot-poc-build.password"
echo "- C4 configuration de Zot en service = stockage/zot.json ; poc-build dans la première politique de builds/** (filtre de decision3)"
echo "- C5 audit de Zot depuis h5_deny : écritures .att par poc-build seul, au moins 1 ; S1 n'a changé que le chemin des identifiants"
echo "- C6 Zot : essai-webhook@3a7ca1b1, BuildKit par digest, bundle du gabarit, tous les témoins de G6, referrers VSA et scan présents ;"
echo "  horodatage/bundles présent, les cinq dépôts d'essai du 01/11 lus par reserve_c absents (rejeu.sh le dit, sans mesure depuis le 02/11)"
echo "- C7 cluster : gabarit en service sample-app, donc garde gabarit_essai en KO pour test5 sans condition, et pour enveloppes et decision3"
echo "  sans PIPE_ESSAI ; blocage dû à la bascule, pas à H5 ; j7-sample-app, j6-porte-en-service-publier, j6-autre-cle présents ;"
echo "  pipeline.ref = bundle du gabarit"
echo "- C8 audit de l'API depuis h5_deny : 0 création réelle de PipelineRun par le compte rattrapage, chemin 2 de la bascule donc sans"
echo "  passage sous H5 ; dernier passage du CronJob réussi, dernière ligne PRESENT"
echo "- C9 Jobs de la porte créés depuis h5_deny : au moins 1 réussi, gabarit à conteneurs vsa, scan-verifier et scan"
echo "- écart attendu : 0"

echo "## C1 ConfigMap porte"
kubectl get configmap -n porte porte -o json > "$T/porte.json"
attendu "clés de la ConfigMap" "$(jq '.data | length' "$T/porte.json")" 14
n=0
while IFS='|' read -r k f; do
  jq -j --arg k "$k" '.data[$k]' "$T/porte.json" > "$T/cle"
  if cmp -s "$T/cle" "$f"; then n=$((n + 1)); else ko "ConfigMap porte, clé $k différente de ${f#"$d8c/../"}"; fi
done <<EOF
policy.yaml|$here/politique/porte/policy.yaml
policy-trusted-task.yaml|$here/politique/porte/policy-trusted-task.yaml
porte.rego|$here/politique/porte/porte.rego
taches.yml|$here/politique/porte/taches.yml
chains.pub|$R/chains-cle-publique.pem
ca-poc.crt|$P/ca-poc.crt
horodatage.sh|$here/politique/porte/horodatage.sh
tsa-racine-confiance.json|$P/tsa-racine-confiance.json
vsa.sh|$here/politique/porte/vsa.sh
vsa.pub|$here/../10-independent-replay/resultats/vsa-cle-publique.pem
scan-verifier.sh|$h7/politique/porte/scan-verifier.sh
scan.rego|$h7/politique/porte/scan.rego
policy-scan.yaml|$h7/politique/porte/policy-scan.yaml
scanner.pub|$h7/resultats/scanner-cle-publique.pem
EOF
attendu "clés identiques aux fichiers" "$n" 14

echo "## C2 empreintes"
attendu "clé de VSA" "$(openssl pkey -pubin -in "$here/../10-independent-replay/resultats/vsa-cle-publique.pem" -outform DER | sha256sum | cut -c1-8)" 578dd771
attendu "clé du scanner" "$(openssl pkey -pubin -in "$h7/resultats/scanner-cle-publique.pem" -outform DER | sha256sum | cut -c1-8)" 8cbcbb4e

echo "## C3 fichiers de l'hôte (présence, taille non nulle, jamais lus ici sauf pipeline.ref, public)"
for f in "$W/construction/pipeline.ref" "$S/taches.key" "$S/forgejo-webhook.secret" "$S/forgejo-admin.token" "$S/zot-poc-ecriture.password" "$S/zot-poc-build.password"; do
  [ -s "$f" ] && echo "OK   $(basename "$f") : présent" || ko "$(basename "$f") : absent ou vide"
done

echo "## C4 configuration de Zot"
attendu "empreinte en service" "$(sur sc-stockage 'sudo sha256sum /etc/zot/config.json' </dev/null | cut -c1-64)" "$(sha256sum "$here/stockage/zot.json" | cut -c1-64)"
attendu "poc-build dans la première politique de builds/**" \
  "$(jq -r '.http.accessControl.repositories["builds/**"].policies[0].users | index("poc-build") != null' "$here/stockage/zot.json")" true

echo "## C5 audit de Zot, écritures .att depuis $H5_DENY"
sur sc-stockage 'sudo cat /var/log/zot/audit.log' </dev/null | jq -r --arg t "$H5_DENY" 'select(.time[0:19] >= ($t[0:19]) and .status == 201
  and ((.object // "") | test("[.]att$"))) | .subject' | sort | uniq -c | sed 's/^ */  /' | tee "$T/att"
attendu "comptes" "$(awk '{print $2}' "$T/att" | paste -sd,)" poc-build
[ "$(awk '{print $1}' "$T/att" | head -1)" -ge 1 ] 2>/dev/null && echo "OK   au moins une écriture" || ko "aucune écriture .att relevée"

echo "## C6 Zot"
attendu "builds/essai-webhook@3a7ca1b1" "$(manifeste builds/essai-webhook "$APP_DIGEST")" 200
attendu "BuildKit par digest" "$(manifeste "$BUILDKIT_DEPOT" "$BUILDKIT_DIGEST")" 200
g=$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "bundle") | .value')
r=${g#*/}
attendu "bundle du gabarit" "$(manifeste "${r%@*}" "${r#*@}")" 200
n=0; t=0
for d in $(cut -d'|' -f2 "$h7/resultats/g6-temoins.tsv" | sort -u); do
  t=$((t + 1))
  [ "$(manifeste builds/essai-scan "sha256:$d")" = 200 ] && n=$((n + 1)) || ko "témoin G6 absent : ${d:0:12}"
done
echo "témoins G6 présents : $n sur $t digests distincts"
for d in builds/sample-app builds/vsa/sample-app builds/scan/sample-app; do
  c=$(referrers "$d" 2>/dev/null || echo 0)
  [ "${c:-0}" -ge 1 ] && echo "OK   referrers de $d : $c" || ko "aucun referrer dans $d"
done
attendu "horodatage/bundles" "$(tags horodatage/bundles)" 200
for d in copie-20261101t120333z copie-20261101t122804z partiel-20261101t120333z partiel-20261101t122804z webhook-seul-20261101t122804z; do
  attendu "dépôt d'essai $d (reserve_c)" "$(tags "horodatage/essais-test8/$d")" 404
done

echo "## C7 cluster"
attendu "pipeline du gabarit en service" "$(kubectl get triggertemplate -n declencheurs sample-app -o json | jq -r '.spec.resourcetemplates[0].spec.pipelineRef.params[] | select(.name == "name") | .value')" sample-app
attendu "pipeline.ref = bundle du gabarit" "$(cat "$W/construction/pipeline.ref")" "$g"
attendu "PipelineRun j7-sample-app" "$(kubectl get pipelinerun -n builds j7-sample-app -o name 2>&1)" pipelinerun.tekton.dev/j7-sample-app
for n in j6-porte-en-service-publier j6-autre-cle; do
  attendu "TaskRun $n" "$(kubectl get taskrun -n builds "$n" -o name 2>&1)" "taskrun.tekton.dev/$n"
done

echo "## C8 rattrapage"
audit_api serviceaccount:declencheurs:rattrapage </dev/null | jq -c --arg t "$H5_DENY" 'select(.stage == "ResponseComplete" and .verb == "create"
  and .objectRef.resource == "pipelineruns" and .stageTimestamp[0:19] >= ($t[0:19])) | {t: .stageTimestamp, code: .responseStatus.code, dry: (.requestURI | test("dryRun"))}' \
  > "$T/rattrapage.json"
sed 's/^/  /' "$T/rattrapage.json"
attendu "créations réelles depuis h5_deny" "$(jq -s '[.[] | select(.dry | not)] | length' "$T/rattrapage.json")" 0
j=$(kubectl get jobs -n declencheurs -o json | jq -r '[.items[] | select(any(.metadata.ownerReferences[]?; .kind == "CronJob" and .name == "rattrapage") and (.status.succeeded // 0) >= 1)]
  | sort_by(.metadata.creationTimestamp) | last | .metadata.name // ""')
[ -n "$j" ] && echo "dernier passage réussi : $j" || ko "aucun passage réussi gardé"
v=$(kubectl logs -n declencheurs "job/$j" --all-containers=true 2>&1 | tail -1)
attendu "dernière ligne du passage" "${v%%|*}" PRESENT

echo "## C9 Jobs de la porte depuis $H5_DENY"
kubectl get jobs -n porte -o json | jq -r --arg t "$H5_DENY" '[.items[] | select(.metadata.creationTimestamp >= $t)] as $j
  | "créés \($j | length), réussis \([$j[] | select((.status.succeeded // 0) >= 1)] | length), en échec \([$j[] | select((.status.failed // 0) >= 1)] | length)",
    ([$j[] | select((.status.succeeded // 0) >= 1)] | last | if . then "dernier réussi : \(.metadata.name), conteneurs \([.spec.template.spec.initContainers[]?.name, .spec.template.spec.containers[].name] | join(","))" else "aucun réussi" end)' \
  | tee "$T/jobs"
for c in vsa scan-verifier scan; do
  grep -qE "conteneurs .*\b$c\b" "$T/jobs" && echo "OK   conteneur $c dans le dernier Job réussi" || ko "conteneur $c absent du dernier Job réussi"
done

echo "## bilan : $ecarts écart(s) aux prédictions"
