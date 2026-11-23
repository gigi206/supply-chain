#!/usr/bin/env bash
# Brique 07b, pièce 5 (ajout du 23/11/2026) : scanner.sh neuf (patch 07b-t3) dans scan-config et image outils-scan b799feda (pièce 3)
# dans les deux CronJob de scan. La pose n'appellera que cm_scan et l'application des deux CronJob rendus (jamais etape_g2_image).
# Étapes (une par journal, jamais réécrit) :
#   sec : rien d'écrit dans le cluster, rien dans Zot, rien sur la VM. Copie de HEAD (git archive) hors du dépôt, patch 07b-t3
#         appliqué, OUTILS_SCAN_DIGEST = b799feda ; rendu des deux CronJob par le code de la pose (g7_periodique avec G7_SEC=1 pour
#         l'image ; rendre_deb et cronjob_deb de s6a.sh pour le deb) ; dry-run serveur comparé au CronJob en service, image d'outils
#         ramenée à l'ancienne ; kubectl diff archivé (lignes changées seules) ; scan-config rendue par le texte de cm_scan de la copie,
#         apply remplacé par diff : seule la clé scanner.sh doit changer.
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/piece5-scanner.sh sec  (journal : resultats/piece5-scanner-sec.log)
set -uo pipefail
export LC_ALL=C KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
here=$(cd "$(dirname "$0")" && pwd)
racine_depot=$(cd "$here/../../.." && pwd)
e=${1:-}
[ "$e" = sec ] || { echo "usage : $0 sec" >&2; exit 2; }
L=$here/resultats/piece5-scanner-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
ANCIEN=sha256:7eb4f26e7148bd9d000fe9609f58ee6e2ba1fd180f38bd7345e029132eb3f83f
NEUF=sha256:b799feda12153cc35c76d951b8b3d51d963e82c17cc80de3563f221657e84649
T=$HOME/.cache/supply-chain-poc/07a/p5-sec
G=$HOME/.cache/supply-chain-poc/07a/g7-periodique   # dossier de travail de g7_periodique (absent avant : contrôlé)
[ ! -e "$T" ] || { echo "dossier de travail déjà présent : $T" >&2; exit 1; }
[ ! -e "$G" ] || { echo "dossier de g7_periodique déjà présent : $G" >&2; exit 1; }
mkdir -m 700 "$T"
trap 'find "$HOME/.cache/supply-chain-poc/07a/p5-sec" -delete; [ ! -e "$HOME/.cache/supply-chain-poc/07a/g7-periodique" ] || find "$HOME/.cache/supply-chain-poc/07a/g7-periodique" -delete' EXIT
KO=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
attendu() { [ "$2" = "$3" ] && ok "$1 : $2" || ko "$1 : $2 (attendu : $3)"; }
exec > "$L" 2>&1
echo "# piece5-scanner.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$racine_depot" rev-parse --short=12 HEAD)"

echo "## copie de HEAD, patch appliqué"
A=$T/arbre; mkdir "$A"
git -C "$racine_depot" archive HEAD poc/bricks/07a-sbom-grype poc/bricks/06-deb-sbuild poc/bricks/08-trust-plane poc/bricks/08c-durcissement/politiques | tar -x -C "$A"
P07=$A/poc/bricks/07a-sbom-grype
patch -p1 -d "$A" -s --dry-run < "$P07/politique/07b-t3.patch" && patch -p1 -d "$A" -s < "$P07/politique/07b-t3.patch" \
  && ok "patch 07b-t3 appliqué à la copie ($(sha256sum < "$P07/politique/07b-t3.patch" | cut -c1-16))" || ko "patch 07b-t3 non appliqué"
attendu "scanner.sh de la copie = scanner.sh du patch, mode vex présent" "$(grep -c '^  vex) lire_vex ;;' "$P07/politique/scanner.sh")" 1
sed -i "s/^OUTILS_SCAN_DIGEST=$ANCIEN /OUTILS_SCAN_DIGEST=$NEUF /" "$P07/plateforme.sh"
attendu "OUTILS_SCAN_DIGEST de la copie" "$(sed -n 's/^OUTILS_SCAN_DIGEST=\([^ ]*\).*/\1/p' "$P07/plateforme.sh")" "$NEUF"
attendu "copie : scan-job.yaml = HEAD (le patch n'y touche pas)" "$(sha256sum < "$P07/politique/scan-job.yaml" | cut -c1-16)" \
  "$(git -C "$racine_depot" show HEAD:poc/bricks/07a-sbom-grype/politique/scan-job.yaml | sha256sum | cut -c1-16)"

echo "## CronJob scan-sample-app : rendu par g7_periodique (G7_SEC=1 : dry-run serveur seul)"
mkdir "$P07/resultats-sec"
sed -i 's#^R=\$here/resultats$#R=$here/resultats-sec#' "$P07/plateforme.sh"
attendu "journal de plateforme.sh de la copie hors de resultats/" "$(grep -c '^R=\$here/resultats-sec$' "$P07/plateforme.sh")" 1
G7_SEC=1 bash "$P07/plateforme.sh" g7_periodique < /dev/null > "$T/g7.out" 2>&1; c=$?
sed 's/^/  /' "$T/g7.out"
attendu "g7_periodique (G7_SEC=1), code" "$c" 0
cp "$G/cronjob.json" "$T/image.json" && find "$HOME/.cache/supply-chain-poc/07a/g7-periodique" -delete

echo "## CronJob scan-sample-app-deb : rendu par rendre_deb et cronjob_deb de s6a.sh (copie)"
S6=$A/poc/bricks/06-deb-sbuild/s6a.sh
REG=$(sed -n 's/^REG=\([^ ]*\).*/\1/p' "$P07/plateforme.sh")
DEB_REF=$(sed -n 's/^DEB_REF=\$REG\/\([^ ]*\).*/\1/p' "$S6"); DEB_REF=$REG/$DEB_REF
DEPOT_SCAN_DEB=builds/scan/sample-app-deb CRON_DEB=scan-sample-app-deb HORAIRE_DEB='15 11 * * *'
LIMITES=$A/poc/bricks/08c-durcissement/politiques/limites.tsv
attendu "constantes du deb relues dans s6a.sh" "$(grep -c -e '^DEPOT_SCAN_DEB=builds/scan/sample-app-deb ' -e '^CRON_DEB=scan-sample-app-deb$' -e "^HORAIRE_DEB='15 11 \* \* \*' " "$S6")" 3
val07() { sed -n "s/^$1=\([^ ]*\).*/\1/p" "$P07/plateforme.sh"; }
eval "$(awk '/^rendre_deb\(\)/,/^}/' "$S6")"
eval "$(awk '/^cronjob_deb\(\)/,/^}/' "$S6")"
TS=$T; T=$TS/deb; mkdir "$T"; cronjob_deb | sed 's/^/  /'; T=$TS
cp "$T/deb/cronjob.json" "$T/deb.json"

echo "## comparaison au service : dry-run serveur, image d'outils ramenée à l'ancienne"
for n in image:scan-sample-app deb:scan-sample-app-deb; do
  f=$T/${n%%:*}.json; cj=${n#*:}
  kubectl apply --server-side --dry-run=server -o json -f "$f" < /dev/null > "$f.serveur" 2> "$f.err" || { ko "$cj : dry-run serveur refusé : $(tail -1 "$f.err" | cut -c1-200)"; continue; }
  kubectl get cronjob -n scan "$cj" -o json < /dev/null > "$f.service"
  attendu "$cj : conteneurs passés sur l'image neuve (rendu)" \
    "$(jq -r --arg n "$NEUF" '[.spec.jobTemplate.spec.template.spec | (.initContainers[]?, .containers[]?) | select(.image | endswith($n)) | .name] | join(",")' "$f.serveur")" \
    "$(jq -r --arg a "$ANCIEN" '[.spec.jobTemplate.spec.template.spec | (.initContainers[]?, .containers[]?) | select(.image | endswith($a)) | .name] | join(",")' "$f.service")"
  attendu "$cj : plus aucun conteneur sur l'ancienne image (rendu)" "$(grep -c "${ANCIEN#sha256:}" "$f.serveur")" 0
  jq -S --arg a "$ANCIEN" --arg n "$NEUF" '.spec | walk(if type == "string" then sub($n; $a) else . end)' "$f.serveur" > "$f.ramene"
  jq -S '.spec' "$f.service" > "$f.spec"
  if cmp -s "$f.ramene" "$f.spec"; then ok "$cj : spec du dry-run, image ramenée = spec en service"
  else ko "$cj : spec différente hors image :"; diff "$f.spec" "$f.ramene" | head -30 | sed 's/^/  /'; fi
  c=0; kubectl diff --server-side -f "$f" < /dev/null > "$f.diff" 2>&1 || c=$?
  echo "  kubectl diff --server-side $cj : code $c ; lignes changées (hors en-têtes et generation) :"
  grep -E '^[-+] ' "$f.diff" | grep -v -E '^[-+] +generation:' | sed 's/^/    /'
  attendu "$cj : lignes changées par kubectl diff, hors generation, toutes des lignes image" \
    "$(grep -E '^[-+] ' "$f.diff" | grep -v -E '^[-+] +generation:' | grep -c -v -E '^[-+] +image: ')" 0
done

echo "## scan-config : texte de cm_scan de la copie, apply remplacé par diff"
f=$(awk '/^cm_scan\(\)/,/^}/' "$P07/plateforme.sh")
attendu "cm_scan de la copie = cm_scan de HEAD (le patch n'y touche pas)" "$(printf '%s\n' "$f" | sha256sum | cut -c1-16)" \
  "$(git -C "$racine_depot" show HEAD:poc/bricks/07a-sbom-grype/plateforme.sh | awk '/^cm_scan\(\)/,/^}/' | sha256sum | cut -c1-16)"
g=${f/kubectl apply --server-side -f -/cat}
attendu "cm_scan : une seule substitution apply -> cat (rendu seul)" "$(printf '%s\n' "$g" | grep -c -- '-o yaml | cat$')/$(printf '%s\n' "$g" | grep -c 'kubectl apply')" 1/0
P=$HOME/.cache/supply-chain-poc/08/pki R=$P07/resultats
eval "${g/cm_scan()/cm_scan_rendu()}"
here_sauve=$here; here=$P07
cm_scan_rendu < /dev/null > "$T/cm.yaml" 2> "$T/cm.err"; c=$?
here=$here_sauve
attendu "rendu de scan-config, code" "$c" 0
kubectl create --dry-run=client -o json -f "$T/cm.yaml" < /dev/null > "$T/cm.json"
kubectl get cm -n scan scan-config -o json < /dev/null > "$T/cm.service"
cles() { jq -r '.data | to_entries[] | "\(.key) \(.value | @base64)"' "$1" | while read -r k v; do echo "$k $(printf '%s' "$v" | base64 -d | sha256sum | cut -c1-16)"; done; }
cles "$T/cm.service" > "$T/cles.service"; cles "$T/cm.json" > "$T/cles.rendu"
sed 's/^/  service : /' "$T/cles.service"; sed 's/^/  rendu   : /' "$T/cles.rendu"
attendu "scan-config : clés présentes, service et rendu" "$(cut -d' ' -f1 "$T/cles.service" | paste -sd, -)" "$(cut -d' ' -f1 "$T/cles.rendu" | paste -sd, -)"
attendu "scan-config : clés dont le contenu change" "$(join "$T/cles.service" "$T/cles.rendu" | awk '$2 != $3 {print $1}' | paste -sd, -)" scanner.sh
attendu "scan-config : scanner.sh rendu = scanner.sh du patch" "$(grep '^scanner.sh ' "$T/cles.rendu" | cut -d' ' -f2)" "$(sha256sum < "$P07/politique/scanner.sh" | cut -c1-16)"
c=0; kubectl diff --server-side -f "$T/cm.yaml" < /dev/null > "$T/cm.diff" 2>&1 || c=$?
echo "  kubectl diff --server-side scan-config : code $c, $(grep -c -E '^[-+] ' "$T/cm.diff") lignes changées"
echo "  empreintes de scanner.sh : service $(kubectl get cm -n scan scan-config -o json < /dev/null | jq -j '.data["scanner.sh"]' | sha256sum | cut -c1-16), HEAD $(git -C "$racine_depot" show HEAD:poc/bricks/07a-sbom-grype/politique/scanner.sh | sha256sum | cut -c1-16), patch $(sha256sum < "$P07/politique/scanner.sh" | cut -c1-16)"
attendu "scan-config en service : scanner.sh = HEAD" "$(kubectl get cm -n scan scan-config -o json < /dev/null | jq -j '.data["scanner.sh"]' | sha256sum | cut -c1-16)" \
  "$(git -C "$racine_depot" show HEAD:poc/bricks/07a-sbom-grype/politique/scanner.sh | sha256sum | cut -c1-16)"
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$KO" = 0 ] && echo "bilan : tenue" || echo "bilan : $KO KO"
