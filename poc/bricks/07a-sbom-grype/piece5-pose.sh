#!/usr/bin/env bash
# Brique 07b, pièce 5 (ajout du 23/11/2026, écrit avant la pose) : pose du scanner neuf. scanner.sh (patch 07b-t3, reporté dans le
# dépôt le 23/11) dans scan-config par cm_scan, et image outils-scan b799feda dans les deux CronJob de scan (analyser, attester,
# publier). Objets rendus depuis une copie de HEAD (git archive), comme l'étape sec de piece5-scanner.sh : plateforme.sh n'est jamais
# lancé dans le dépôt (son journal resultats/g7_periodique.log serait réécrit), et g7_periodique n'est lancé qu'avec G7_SEC=1 (sinon
# il lance un Job qui publie). Jamais etape_g2_image.
# Étapes (une par journal, jamais réécrit) :
#   pose    ACCORD DU PROPRIÉTAIRE. Refuse sans sa décision du 23/11 dans 07b-carte.md (pose avant le relevé du 24/11), sans
#           essai tenu (piece5-essai-essai.log), si un pod de scan est actif, et dans les 10 min qui précèdent un passage planifié
#           (09:20 à 09:30, 11:05 à 11:15 UTC). Avant : HEAD porte scanner.sh 7251df15 et le digest b799feda ; le service, l'ancien
#           scanner.sh et l'ancienne image. Pose : cm_scan de la copie, puis kubectl apply --server-side des deux CronJob rendus.
#           Après : seule la clé scanner.sh a changé ; spec des CronJob, image ramenée, égale à celle d'avant.
#   grafana lecture seule : écritures de scan-config et des deux CronJob dans l'audit de l'API (Loki, à travers Grafana), comptes seuls.
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/piece5-pose.sh <pose|grafana>  (journal : resultats/piece5-pose-<étape>.log)
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
racine_depot=$(cd "$here/../../.." && pwd)
O8=$HOME/.cache/supply-chain-poc/08
ANCIEN=sha256:7eb4f26e7148bd9d000fe9609f58ee6e2ba1fd180f38bd7345e029132eb3f83f
NEUF=sha256:b799feda12153cc35c76d951b8b3d51d963e82c17cc80de3563f221657e84649
SC_ANCIEN=88e7bfe80df12ae4 SC_NEUF=7251df1567c1cfdd
e=${1:-}
case $e in pose|grafana) ;; *) echo "usage : $0 <pose|grafana>" >&2; exit 2 ;; esac
L=$here/resultats/piece5-pose-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
KO=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
attendu() { [ "$2" = "$3" ] && ok "$1 : $2" || ko "$1 : $2 (attendu : $3)"; }
arret() { echo "KO   $*"; echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "bilan : rien posé"; exit 1; }
h() { sha256sum | cut -c1-16; }
cles() { kubectl get cm -n scan scan-config -o json | jq -r '.data | keys[]' | while read -r k; do echo "$k $(kubectl get cm -n scan scan-config -o json | jq -j --arg k "$k" '.data[$k]' | h)"; done; }
images() { kubectl get cronjob -n scan "$1" -o json | jq -r '[.spec.jobTemplate.spec.template.spec | (.initContainers[]?, .containers[]?) | "\(.name)=\(.image | sub(".*@sha256:"; "") | .[0:8])"] | join(",")'; }
exec > "$L" 2>&1
echo "# piece5-pose.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$racine_depot" rev-parse --short=12 HEAD)"

case $e in
pose)
  echo "## préalables"
  # modifié le 23/11/2026 (note de 2026-11-23T14:38:33Z) : décision du propriétaire, pièce 5 posée avant le relevé du 24/11
  grep -q '^## Décisions du propriétaire : ne plus attendre le calendrier (note de' "$here/resultats/07b-carte.md" || arret "décision du propriétaire absente de la carte"
  ok "décision du propriétaire : pose avant le relevé du 24/11"
  grep -q '^bilan : tenue' "$here/resultats/piece5-essai-essai.log" 2> /dev/null || arret "pod d'essai absent ou non tenu"
  ok "pod d'essai tenu"
  hm=$(date -u +%H%M)
  if { [ "$hm" -ge 0920 ] && [ "$hm" -lt 0930 ]; } || { [ "$hm" -ge 1105 ] && [ "$hm" -lt 1115 ]; }; then arret "$hm UTC : 10 min avant un passage planifié"; fi
  actifs=$(kubectl get pods -n scan --no-headers -o custom-columns=N:.metadata.name,P:.status.phase | awk '$2 == "Running" || $2 == "Pending" {print $1}')
  [ -z "$actifs" ] || arret "pod(s) actif(s) dans scan : $actifs"
  ok "$hm UTC, aucun pod actif dans scan"
  [ -z "$(git -C "$racine_depot" status --porcelain -- poc/bricks/07a-sbom-grype/plateforme.sh poc/bricks/07a-sbom-grype/politique poc/bricks/06-deb-sbuild/s6a.sh)" ] \
    || arret "fichiers de la pose modifiés hors commit"
  attendu "HEAD : scanner.sh" "$(git -C "$racine_depot" show HEAD:poc/bricks/07a-sbom-grype/politique/scanner.sh | h)" "$SC_NEUF"
  attendu "HEAD : OUTILS_SCAN_DIGEST" "$(git -C "$racine_depot" show HEAD:poc/bricks/07a-sbom-grype/plateforme.sh | sed -n 's/^OUTILS_SCAN_DIGEST=\([^ ]*\).*/\1/p')" "$NEUF"
  avant=$(cles); echo "$avant" | sed 's/^/  scan-config avant : /'
  attendu "service : scanner.sh" "$(echo "$avant" | sed -n 's/^scanner.sh //p')" "$SC_ANCIEN"
  for cj in scan-sample-app scan-sample-app-deb; do
    attendu "service : images de $cj" "$(images "$cj")" "source=ace6811c,analyser=${ANCIEN:7:8},jetons=50469110,attester=${ANCIEN:7:8},publier=${ANCIEN:7:8},revocation=50469110"
  done
  [ "$KO" = 0 ] || arret "préalables non tenus"
  T=$HOME/.cache/supply-chain-poc/07a/p5-pose G=$HOME/.cache/supply-chain-poc/07a/g7-periodique
  [ ! -e "$T" ] && [ ! -e "$G" ] || arret "dossier de travail déjà présent ($T ou $G)"
  mkdir -m 700 "$T"
  trap 'find "$HOME/.cache/supply-chain-poc/07a/p5-pose" -delete; [ ! -e "$HOME/.cache/supply-chain-poc/07a/g7-periodique" ] || find "$HOME/.cache/supply-chain-poc/07a/g7-periodique" -delete' EXIT
  for cj in scan-sample-app scan-sample-app-deb; do kubectl get cronjob -n scan "$cj" -o json | jq -S .spec > "$T/$cj.avant"; done
  echo "## rendu depuis une copie de HEAD"
  A=$T/arbre; mkdir "$A"
  git -C "$racine_depot" archive HEAD poc/bricks/07a-sbom-grype poc/bricks/06-deb-sbuild poc/bricks/08-trust-plane poc/bricks/08c-durcissement/politiques | tar -x -C "$A"
  P07=$A/poc/bricks/07a-sbom-grype
  mkdir "$P07/resultats-pose"; sed -i 's#^R=\$here/resultats$#R=$here/resultats-pose#' "$P07/plateforme.sh"
  attendu "journal de plateforme.sh de la copie hors de resultats/" "$(grep -c '^R=\$here/resultats-pose$' "$P07/plateforme.sh")" 1
  G7_SEC=1 bash "$P07/plateforme.sh" g7_periodique < /dev/null > "$T/g7.out" 2>&1; c=$?
  sed 's/^/  /' "$T/g7.out"; attendu "g7_periodique (G7_SEC=1), code" "$c" 0
  cp "$G/cronjob.json" "$T/scan-sample-app.json" && find "$HOME/.cache/supply-chain-poc/07a/g7-periodique" -delete
  S6=$A/poc/bricks/06-deb-sbuild/s6a.sh
  REG=$(sed -n 's/^REG=\([^ ]*\).*/\1/p' "$P07/plateforme.sh")
  DEB_REF=$REG/$(sed -n 's/^DEB_REF=\$REG\/\([^ ]*\).*/\1/p' "$S6")
  DEPOT_SCAN_DEB=builds/scan/sample-app-deb CRON_DEB=scan-sample-app-deb HORAIRE_DEB='15 11 * * *'
  LIMITES=$A/poc/bricks/08c-durcissement/politiques/limites.tsv
  val07() { sed -n "s/^$1=\([^ ]*\).*/\1/p" "$P07/plateforme.sh"; }
  eval "$(awk '/^rendre_deb\(\)/,/^}/' "$S6")"; eval "$(awk '/^cronjob_deb\(\)/,/^}/' "$S6")"
  TS=$T; T=$TS/deb; mkdir "$T"; cronjob_deb | sed 's/^/  /'; T=$TS
  cp "$T/deb/cronjob.json" "$T/scan-sample-app-deb.json"
  for cj in scan-sample-app scan-sample-app-deb; do
    attendu "rendu de $cj : conteneurs sur l'image neuve" "$(jq -r --arg n "$NEUF" '[.spec.jobTemplate.spec.template.spec | (.initContainers[]?, .containers[]?) | select(.image | endswith($n)) | .name] | join(",")' "$T/$cj.json")" analyser,attester,publier
  done
  [ "$KO" = 0 ] || arret "rendu non conforme"
  echo "## pose ($(date -u +%H:%M:%S) UTC)"
  f=$(awk '/^cm_scan\(\)/,/^}/' "$P07/plateforme.sh"); echo "  texte de cm_scan : $(printf '%s\n' "$f" | h)"
  P=$O8/pki R=$P07/resultats
  eval "$f"
  here_sauve=$here; here=$P07; cm_scan < /dev/null 2>&1 | sed 's/^/  /'; here=$here_sauve
  for cj in scan-sample-app scan-sample-app-deb; do kubectl apply --server-side -f "$T/$cj.json" < /dev/null 2>&1 | sed 's/^/  /'; done
  echo "## après ($(date -u +%H:%M:%S) UTC)"
  apres=$(cles); echo "$apres" | sed 's/^/  scan-config après : /'
  attendu "scan-config : scanner.sh" "$(echo "$apres" | sed -n 's/^scanner.sh //p')" "$SC_NEUF"
  attendu "scan-config : autres clés inchangées" "$(echo "$apres" | grep -v '^scanner.sh ')" "$(echo "$avant" | grep -v '^scanner.sh ')"
  for cj in scan-sample-app scan-sample-app-deb; do
    attendu "images de $cj" "$(images "$cj")" "source=ace6811c,analyser=${NEUF:7:8},jetons=50469110,attester=${NEUF:7:8},publier=${NEUF:7:8},revocation=50469110"
    kubectl get cronjob -n scan "$cj" -o json | jq -S --arg a "$ANCIEN" --arg n "$NEUF" '.spec | walk(if type == "string" then sub($n; $a) else . end)' > "$T/$cj.ramene"
    cmp -s "$T/$cj.avant" "$T/$cj.ramene" && ok "$cj : spec, image ramenée = spec d'avant" || { ko "$cj : spec changée hors image"; diff "$T/$cj.avant" "$T/$cj.ramene" | head -20 | sed 's/^/  /'; }
  done
  ;;
grafana)
  A='{noeud="sc-confiance", source="audit-k8s"} | json | objectRef_namespace="scan" | verb=~"patch|update|create|apply" | objectRef_resource=~"configmaps|cronjobs"'
  b=$(jq -nc --arg q "sum by (objectRef_resource, objectRef_name, verb) (count_over_time($A [30m]))" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$O8/pki/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query -d "$b" \
    | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | "\(.schema.fields[1].labels | "\(.objectRef_resource)/\(.objectRef_name) \(.verb)") : \(.data.values[1][0])"] | if length == 0 then "aucune écriture sur 30 min" else .[] end' \
    | sed 's/^/  /'
  ;;
esac
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$KO" = 0 ] && echo "bilan : tenue" || echo "bilan : $KO KO"
