#!/usr/bin/env bash
# Brique 06, jalon S6a (contrôle 7 du deb ; décision du propriétaire du 12/11/2026, 08:50:32 UTC : « 1 ok / 2 ok / 3 ok / 4 ok »).
# Prédictions : resultats/s6a-predictions.md, commitées avant tout lancement.
#   releve  hôte seul, hors réseau (syft et grype sous unshare -rn), rien dans le cluster ni dans Zot, rien installé ; écritures
#           sous ~/.cache/supply-chain-poc/06/s6a et dans resultats/ seulement :
#           entrées vérifiées (sha256 du deb de S3 = celui de builds/sample-app-deb@039949f9 ; layout local de l'image de base
#           d'outils-scan, blobs revérifiés) ; P1 format du deb (ar t) ; P2 applets de busybox dans les couches de cette base
#           (noms listés, rien exécuté) ; P3 étiquettes des catalogueurs de syft ; P4 SBOM de l'artefact seul (syft dir: sur
#           data.tar extrait) ; P5 le deb comme fichier (syft dir: sur un dossier qui ne contient que lui) ; P6 grype sur le
#           SBOM de P4, base de G0 ; P7 syft dir: sur un dossier vide avec -q, puis fusion (scan-outil de la 07a) avec le SBOM
#           de la source (arbre HEAD:poc/sample-app, celui du commit 6391fd43).
#   essai   ACCORD NOMMÉ DU PROPRIÉTAIRE. Pod d'essai du mode deb (processus allégé, levier e) : correctif s6a-scanner-deb.patch
#           appliqué à une COPIE de politique/scanner.sh de la 07a (l'arbre de travail n'est pas touché : S5b déploie scanner.sh
#           tel quel) ; ConfigMap essai-s6a et pod essai-s6a dans l'espace scan (image outils-scan, sans compte de service, sans
#           jeton ni identifiant ; Zot lu en anonyme), mode artefact sur cinq cas ; pod et ConfigMap supprimés ensuite. Rien
#           d'écrit dans Zot. Remis si un pod de l'espace scan est actif (CronJob scan-sample-app à 09:30 UTC).
#
# Ajouté à sec le 12/11/2026 (pas 3 et 4 de S6a, NON LANCÉS) : APRÈS S5b ET LE RELEVÉ DU 21/11 (ordre c), chaque étape sur
# ACCORD NOMMÉ DU PROPRIÉTAIRE. Prédictions : resultats/s6a-service-predictions.md. Les correctifs s6a-scanner-deb.patch,
# s6a-fraicheur-deb.patch et s6a-alertes-deb.patch doivent être appliqués et commités d'abord : chaque étape le vérifie.
#   periodique  cluster et Zot : ConfigMap scan-config réappliquée avec scanner.sh corrigé (comme cm_scan de la 07a : l'image
#               passe aussi par le plancher) ; CronJob scan-sample-app-deb (11:15 UTC), rendu de scan-job.yaml (07a) sur le deb,
#               NATURE=deb dans analyser, limites de revocation tirées de limites.tsv (08c) ; il doit égaler le CronJob en service
#               scan-sample-app hors image, nom, dépôt, NATURE et horaire ; un passage lancé depuis lui, referrer de
#               builds/scan/sample-app-deb vérifié sur l'hôte. S6A_SEC=1 : rendu, dry-run serveur et comparaison seulement.
#   fraicheur   sc-stockage : fraicheur-scan.py corrigé installé, dépôts passés par un fichier complémentaire de l'unité
#               (fraicheur-scan.service.d/s6a-deb.conf, SCANS), unité de la 07a inchangée ; séries comparées à Zot et à Prometheus.
#   porte       cluster (DISTRO=rke2) : Job de la porte sur le deb, juger de politique.sh (08) comme l'étape porte de s4d3.sh ;
#               scan attendu ok ; VSA attendue ok seulement si builds/vsa/sample-app-deb porte un referrer du deb (pousser_vsa).
# Ajouté à sec le 12/11/2026, à partir de 13:04:25 UTC (après « continue »), NON LANCÉ, même cadre et même accord nommé :
#   grafana     lectures seules, par l'auditeur à travers Grafana (comme g7_grafana et g8_grafana de la 07a), après periodique et
#               fraicheur réussis et avant tout passage planifié : journaux du job s6a-manuel, signature dans l'audit d'OpenBao,
#               poussage dans l'audit de Zot, journal de fraicheur-scan avec les deux dépôts ; identifiants de poc-scan absents des
#               réponses. Rien n'est écrit hors du journal de l'étape ; les réponses de Grafana sont effacées en fin d'étape.
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/06-deb-sbuild/s6a.sh releve|essai|periodique|fraicheur|porte|grafana
#   (porte : DISTRO=rke2 devant ; journal : resultats/s6a-<étape>.log)
set -euo pipefail
export LC_ALL=C
h06=$(cd "$(dirname "$0")" && pwd)
racine=$(cd "$h06/../../.." && pwd)
R=$h06/resultats
T=$HOME/.cache/supply-chain-poc/06/s6a
DEB=$HOME/.cache/supply-chain-poc/08/travail/s3-06/build-1/sample-app_1.0.0-1_amd64.deb
DEB_SHA=0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5      # deb de builds/sample-app-deb@039949f9 (S4d1)
G0=$HOME/.cache/supply-chain-poc/07a/g0                                          # base grype du 04/11/2026 (G0 de la 07a)
SCAN_OUTIL=$HOME/.cache/supply-chain-poc/07a/outil/scan-outil                    # construit depuis 07a-sbom-grype/outil
BASE=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/sigstore/cosign/cosign
BASE_DIGEST=c142f6bc0c6d8e5e4a3d31b941200a12502ad90bb5ce93b78c875c868905619d     # COSIGN_BASE de 07a-sbom-grype/plateforme.sh
ARBRE=30e808ffa327288c656ddda7b6fafe4005234b77                                   # arbre de poc/sample-app au commit 6391fd43
PATCH=$h06/s6a-scanner-deb.patch
REG=sc-stockage.poc.test:5000                                                    # Zot depuis les pods (plateforme.sh de la 07a)
OUTILS=$REG/plateforme/outils-scan@sha256:7eb4f26e7148bd9d000fe9609f58ee6e2ba1fd180f38bd7345e029132eb3f83f   # G2 de la 07a
DEB_REF=$REG/builds/sample-app-deb@sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e    # S4d1
APP_REF=$REG/builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5        # IMAGE de la 07a
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml

chrono() { printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
hors() { /usr/bin/unshare -rn env GRYPE_DB_CACHE_DIR="$G0/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
  GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false "$@"; }
purls() { python3 -I -c 'import json, sys
c = [x for x in json.load(open(sys.argv[1])).get("components", []) if x.get("purl")]
print(f"{len(c)} composant(s) avec PURL")
for x in sorted(x["purl"] for x in c): print("  ", x)' "$1"; }

etape_releve() {
  rm -rf -- "${T:?}"; mkdir -p "$T"/{deb,data,fichier,vide,source}

  echo "## entrées"
  echo "syft $(syft version 2>/dev/null | sed -n 's/^Version: *//p'), grype $(grype version 2>/dev/null | sed -n 's/^Version: *//p')"
  attendu "sha256 du deb de S3" "$(sha256sum < "$DEB" | cut -c1-64)" "$DEB_SHA"
  attendu "manifeste du layout de la base" "$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["manifests"][0]["digest"])' "$BASE/index.json")" "sha256:$BASE_DIGEST"
  local b k=0
  for b in "$BASE"/blobs/sha256/*; do
    [ "$(sha256sum < "$b" | cut -c1-64)" = "${b##*/}" ] || { echo "KO   blob altéré : ${b##*/}" >&2; exit 1; }
    k=$((k + 1))
  done
  echo "OK   $k blobs de la base revérifiés par leur sha256"
  echo "scan-outil (07a, hôte) : sha256 $(sha256sum < "$SCAN_OUTIL" | cut -c1-64)"

  echo "## P1 : format du deb (ar t)"
  ar t "$DEB"

  echo "## P2 : applets de busybox dans les couches de l'image de base (noms seulement)"
  local m c
  m=$BASE/blobs/sha256/$BASE_DIGEST
  python3 -I -c 'import json, sys; [print(l["digest"][7:], l["mediaType"]) for l in json.load(open(sys.argv[1]))["layers"]]' "$m" > "$T/couches"
  : > "$T/noms"
  while read -r c _; do tar -tf "$BASE/blobs/sha256/$c" >> "$T/noms" 2>/dev/null || echo "couche $c illisible par tar" ; done < "$T/couches"
  echo "$(wc -l < "$T/couches") couches, $(wc -l < "$T/noms") entrées"
  for a in ar tar xz unxz zstd unzstd gunzip dpkg-deb; do
    printf '%-9s %s\n' "$a" "$(grep -E "(^|/)$a\$" "$T/noms" | sort -u | tr '\n' ' ')"
  done

  echo "## P3 : catalogueurs de syft (nom, étiquettes)"
  hors syft cataloger list -o json > "$T/catalogueurs.json"
  python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
print("sélection par défaut :", json.dumps(d.get("default")), json.dumps(d.get("selection")))
for x in d["catalogers"]:   # structure lue le 12/11/2026 : {"default", "selection", "catalogers": [{"name", "tags"}]}
    if x.get("name") in ("go-module-binary-cataloger", "deb-archive-cataloger", "dpkg-db-cataloger"):
        print(x["name"], ":", ",".join(sorted(x.get("tags") or [])))' "$T/catalogueurs.json"

  echo "## P4 : SBOM de l'artefact seul (syft dir: sur data.tar extrait)"
  (cd "$T/deb" && ar x "$DEB")
  ls "$T/deb"
  tar -xf "$T"/deb/data.tar* -C "$T/data"
  (cd "$T/data" && find . -type f | sort)
  set +e; hors syft scan "dir:$T/data" -o cyclonedx-json="$T/sbom-artefact.json" -q 2> "$T/p4.err"; c=$?; set -e
  echo "code $c, sortie d'erreur : $(wc -c < "$T/p4.err") octets"
  purls "$T/sbom-artefact.json"

  echo "## P5 : le deb comme fichier (syft dir: sur un dossier qui ne contient que lui)"
  cp "$DEB" "$T/fichier/"
  set +e; hors syft scan "dir:$T/fichier" -o cyclonedx-json="$T/sbom-fichier.json" -q 2> "$T/p5.err"; c=$?; set -e
  echo "code $c, sortie d'erreur : $(wc -c < "$T/p5.err") octets"
  purls "$T/sbom-fichier.json"

  echo "## P6 : grype sur le SBOM de P4 (base de G0, sans -q : avertissements gardés)"
  set +e; hors grype "sbom:$T/sbom-artefact.json" -o json --file "$T/grype-artefact.json" 2> "$T/p6.err"; c=$?; set -e
  echo "code $c ; avertissements : $(grep -c -i warn "$T/p6.err" || true)"
  grep -i warn "$T/p6.err" | cut -c1-200 | head -5 || true
  python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
m = d.get("matches", [])
print("correspondances :", len(m), "; distro vue par grype :", json.dumps(d.get("distro")))
for x in sorted(m, key=lambda x: (x["artifact"]["name"], x["vulnerability"]["id"])):
    v, a = x["vulnerability"], x["artifact"]
    kev = "KEV" if v.get("knownExploited") else "-"
    print("  ", a["name"], a["version"], v["id"], v.get("severity"), v.get("namespace"), kev, ",".join(v.get("fix", {}).get("versions", [])))' "$T/grype-artefact.json"

  echo "## P7 : dossier vide avec -q, puis fusion avec le SBOM de la source"
  set +e; hors syft scan "dir:$T/vide" -o cyclonedx-json="$T/sbom-vide.json" -q 2> "$T/p7.err"; c=$?; set -e
  echo "code $c, sortie d'erreur : $(wc -c < "$T/p7.err") octets"
  purls "$T/sbom-vide.json"
  attendu "arbre de poc/sample-app à HEAD" "$(git -C "$racine" rev-parse HEAD:poc/sample-app)" "$ARBRE"
  git -C "$racine" archive --format=tar "$ARBRE" | tar -xf - -C "$T/source"
  hors syft scan "dir:$T/source" -o cyclonedx-json="$T/sbom-source.json" -q
  echo "source seule : $(purls "$T/sbom-source.json" | head -1)"
  (cd "$T" && "$SCAN_OUTIL" fusion sbom-source.json sbom-vide.json source image > sbom-fusion-vide.json)
  echo "fusion source + vide : $(purls "$T/sbom-fusion-vide.json" | head -1)"
  (cd "$T" && "$SCAN_OUTIL" fusion sbom-source.json sbom-artefact.json source image > sbom-fusion-artefact.json)
  echo "fusion source + artefact : $(purls "$T/sbom-fusion-artefact.json" | head -1)"
}

# Script du pod d'essai (sh de busybox) : chaque cas dans son propre dossier de travail, mode artefact du scanner corrigé.
SCRIPT_POD='set -u
echo "busybox : $(busybox 2>&1 | head -1)"
for a in ar tar unxz gunzip sha256sum; do printf "%s : %s\n" "$a" "$(command -v "$a" || echo absent)"; done
cas() {
  d=/travail/$1; mkdir "$d"
  if TRAVAIL=$d NATURE=$2 IMAGE=$3 sh /etc/scan/scanner.sh artefact > "$d.out" 2>&1; then r=0; else r=$?; fi
  sed "s/^/$1|/" "$d.out"; echo "CAS|$1|NATURE=$2|code $r"
  rm -rf "$d" "$d.out"
}
cas A deb "$DEB"
cas B deb "$APP"
cas C image "$DEB"
cas D image "$APP"
cas E autre "$DEB"
echo FIN'

nettoyer() {
  kubectl delete pod -n scan essai-s6a --ignore-not-found --wait=true </dev/null >/dev/null || true
  kubectl delete configmap -n scan essai-s6a --ignore-not-found </dev/null >/dev/null || true
}

etape_essai() {
  rm -rf -- "${T:?}/essai"; mkdir -p "$T/essai"
  echo "## correctif, appliqué à une copie"
  git -C "$racine" apply --check "$PATCH" && echo "OK   git apply --check (arbre de travail non modifié)"
  patch -s -o "$T/essai/scanner.sh" "$racine/poc/bricks/07a-sbom-grype/politique/scanner.sh" < "$PATCH"
  echo "scanner.sh de l'arbre : sha256 $(sha256sum < "$racine/poc/bricks/07a-sbom-grype/politique/scanner.sh" | cut -c1-64)"
  echo "scanner.sh corrigé    : sha256 $(sha256sum < "$T/essai/scanner.sh" | cut -c1-64)"

  echo "## espace scan avant l'essai"
  local actifs phase=""
  actifs=$(kubectl get pods -n scan --no-headers -o custom-columns=N:.metadata.name,P:.status.phase </dev/null | awk '$2 == "Running" || $2 == "Pending" {print $1}')
  [ -z "$actifs" ] || { echo "KO   pod(s) actif(s) dans scan, essai remis : $actifs" >&2; exit 1; }
  echo "OK   aucun pod actif dans scan"

  echo "## pod essai-s6a"
  trap nettoyer EXIT
  nettoyer
  kubectl create configmap essai-s6a -n scan --from-file=scanner.sh="$T/essai/scanner.sh" --from-file=ca-poc.crt="$CA" \
    --dry-run=client -o yaml </dev/null | kubectl apply -f - >/dev/null
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: {name: essai-s6a, namespace: scan}
spec:
  automountServiceAccountToken: false
  enableServiceLinks: false
  restartPolicy: Never
  nodeSelector: {zone: confiance}
  securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: essai
    image: $OUTILS
    command: [sh, -c, $(python3 -I -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<<"$SCRIPT_POD")]
    env: [{name: HOME, value: /travail}, {name: TMPDIR, value: /travail}, {name: DEB, value: "$DEB_REF"}, {name: APP, value: "$APP_REF"}]
    resources: {requests: {cpu: 100m, memory: 512Mi}, limits: {cpu: "1", memory: 2Gi}}   # limites-obligatoires (08c, H5)
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    volumeMounts: [{name: travail, mountPath: /travail}, {name: config, mountPath: /etc/scan, readOnly: true}]
  volumes: [{name: travail, emptyDir: {sizeLimit: 1Gi}}, {name: config, configMap: {name: essai-s6a}}]
EOF
  local debut; debut=$(date +%s)
  for _ in $(seq 150); do
    phase=$(kubectl get pod -n scan essai-s6a -o jsonpath='{.status.phase}' </dev/null)
    case $phase in Succeeded|Failed) break ;; esac
    sleep 2
  done
  echo "phase ${phase:-?} après $(( $(date +%s) - debut )) s"
  kubectl logs -n scan essai-s6a -c essai </dev/null > "$T/essai/journal" || true
  echo "$(grep -ciE 'jeton|token' "$T/essai/journal" || true) ligne(s) filtrée(s) (jeton|token)"
  grep -viE 'jeton|token' "$T/essai/journal" || true
  nettoyer
  trap - EXIT
  [ -z "$(kubectl get pod,configmap -n scan --field-selector metadata.name=essai-s6a -o name </dev/null)" ] \
    || { echo "KO   pod ou ConfigMap essai-s6a encore présent" >&2; exit 1; }
  echo "OK   pod et ConfigMap essai-s6a supprimés"
  echo "## bilan"
  grep '^CAS|' "$T/essai/journal" || true
}

# --- Pas 3 et 4 de S6a (ajoutés à sec le 12/11/2026, NON LANCÉS) : après S5b et le relevé du 21/11, sur accord nommé ---
P07=$racine/poc/bricks/07a-sbom-grype
R07=$P07/resultats
LIMITES=$racine/poc/bricks/08c-durcissement/politiques/limites.tsv
REG_HOTE=192.168.161.13:5000                                                    # Zot depuis l'hôte (SAN IP du certificat)
DEB_DIGEST=${DEB_REF##*@}
APP_DIGEST=${APP_REF##*@}
DEPOT_SCAN_DEB=builds/scan/sample-app-deb                                       # dérivé par scan-verifier.sh de builds/sample-app-deb
CRON_DEB=scan-sample-app-deb
HORAIRE_DEB='15 11 * * *'   # le passage de l'image (09:30) finit au plus tard à 11:00 (3600 s d'échéance, 1800 s d'exécution)
JOB_DEB=s6a-manuel
PREDICAT_SCAN=https://supply-chain.example/scan/v1
O8=$HOME/.cache/supply-chain-poc/08
SSH8=(-n -i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10)
ECARTS=0
mesure() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS=$((ECARTS + 1)); }; }
ecarts() { [ "$ECARTS" = 0 ] || { echo "KO   $ECARTS écart(s)" >&2; exit 1; }; echo "bilan : tout OK"; }
val07() { sed -n "s/^$1=\([^ ]*\).*/\1/p" "$P07/plateforme.sh"; }   # constante de plateforme.sh (07a), sans guillemets ni espace
anon() { curl -fsS --cacert "$CA" "$@" </dev/null; }
applique() { # correctif : appliqué à l'arbre (sa réciproque s'applique), sans modification hors commit des fichiers qu'il touche
  git -C "$racine" apply -R --check "$h06/$1" </dev/null 2>/dev/null || { echo "KO   $1 non appliqué à l'arbre de travail" >&2; exit 1; }
  [ -z "$(git -C "$racine" status --porcelain -- $(sed -n 's#^+++ b/##p' "$h06/$1") </dev/null)" ] \
    || { echo "KO   fichiers de $1 modifiés hors commit" >&2; exit 1; }
  echo "OK   $1 appliqué et commité"
}
nb_referrers() { # dépôt digest : nombre de referrers (0 si le dépôt n'existe pas encore : 404), comme g7_periodique
  local c
  c=$(curl -sS --cacert "$CA" -o "$T/referrers.json" -w '%{http_code}' "https://$REG_HOTE/v2/$1/referrers/$2" </dev/null)
  case $c in
    200) jq '.manifests | length' "$T/referrers.json" ;;
    404) echo 0 ;;
    *) echo "KO   referrers de $1 : HTTP $c" >&2; exit 1 ;;
  esac
}
present() { # dépôt digest : le manifeste est dans Zot (lecture anonyme, HEAD)
  curl -fsS -o /dev/null --head --cacert "$CA" -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    "https://$REG_HOTE/v2/$1/manifests/$2" </dev/null || { echo "KO   $1@$2 absent de Zot (décision du propriétaire après S5b)" >&2; exit 1; }
  echo "OK   $1@$2 présent dans Zot"
}
hors_fenetre() { # ni le passage de l'image (09:30 à 11:00) ni celui du deb (11:15 à 12:45), ni pod actif dans scan
  local h actifs
  h=$(date -u +%H)
  case $h in 09|10|11|12) echo "KO   $h h UTC : fenêtre des passages planifiés (09:00 à 12:59), étape remise" >&2; exit 1 ;; esac
  actifs=$(kubectl get pods -n scan --no-headers -o custom-columns=N:.metadata.name,P:.status.phase </dev/null | awk '$2 == "Running" || $2 == "Pending" {print $1}')
  [ -z "$actifs" ] || { echo "KO   pod(s) actif(s) dans scan, étape remise : $actifs" >&2; exit 1; }
  echo "OK   hors des fenêtres planifiées ($h h UTC), aucun pod actif dans scan"
}

rendre_deb() { # nom : politique/scan-job.yaml (07a) rendu sur le deb, comme rendre_scan de plateforme.sh (image, nom et dépôt changés)
  sed -e "s#@NOM@#$1#" -e "s#@IMAGE@#$DEB_REF#g" -e "s#@NOM_IMAGE@#sample-app-deb#" -e "s#@DEPOT@#$REG/$DEPOT_SCAN_DEB#" \
    -e "s#@BASES@#$REG/vulndb/grype#" -e "s#@SOURCE@#https://sc-stockage.poc.test:3000/workspace/sample-app.git#" -e "s#@COMMIT@#$(val07 COMMIT)#" \
    -e "s#@OUTILS@#$REG/$(val07 OUTILS_SCAN)@$(val07 OUTILS_SCAN_DIGEST)#g" -e "s#@BAO@#$REG/$(val07 BAO_IMAGE)#g" \
    -e "s#@BUILDKIT@#$REG/$(val07 BUILDKIT_IMAGE)#g" "$P07/politique/scan-job.yaml"
}

cronjob_deb() { # CronJob du deb dans $T/cronjob.json : enveloppe de g7_periodique (07a), NATURE=deb, limites de revocation (08c)
  local rc rm lc lm
  read -r rc rm lc lm < <(awk -F'\t' '$1 == "CronJob" && $2 == "scan" && $3 == "scan-sample-app" && $4 == "revocation" && $5 == "containers" {print $6, $7, $8, $9}' "$LIMITES")
  [ -n "${lm:-}" ] || { echo "KO   limites de revocation absentes de limites.tsv" >&2; exit 1; }
  echo "limites de revocation (limites.tsv) : requêtes $rc et $rm, limites $lc et $lm"
  rendre_deb "$CRON_DEB" | kubectl create --dry-run=client -o json -f - | jq --arg h "$HORAIRE_DEB" --arg rc "$rc" --arg rm "$rm" --arg lc "$lc" --arg lm "$lm" '
    {apiVersion: "batch/v1", kind: "CronJob", metadata: {name: .metadata.name, namespace: .metadata.namespace},
     spec: {schedule: $h, timeZone: "Etc/UTC", concurrencyPolicy: "Forbid", startingDeadlineSeconds: 3600, successfulJobsHistoryLimit: 3, failedJobsHistoryLimit: 3,
       jobTemplate: {spec: (.spec | del(.ttlSecondsAfterFinished)
         | .template.spec.initContainers |= map(if .name == "analyser" then .env += [{name: "NATURE", value: "deb"}] else . end)
         | .template.spec.containers |= map(if .name == "revocation" then .resources = {requests: {cpu: $rc, memory: $rm}, limits: {cpu: $lc, memory: $lm}} else . end))}}}' \
    > "$T/cronjob.json"
}

comparer_cronjobs() { # gabarit du Job du deb (dry-run serveur), ramené à l'image, égal à celui de scan-sample-app en service
  kubectl apply --dry-run=server -o json -f "$T/cronjob.json" </dev/null > "$T/serveur.json"
  kubectl get cronjob -n scan scan-sample-app -o json </dev/null > "$T/en-service.json"
  jq -S --arg di "$DEB_REF" --arg ii "$APP_REF" --arg dd "$REG/$DEPOT_SCAN_DEB" --arg id "$REG/builds/scan/sample-app" '.spec.jobTemplate.spec
    | (.template.spec.initContainers, .template.spec.containers) |= map(.env |= (map(select(.name != "NATURE")
        | if .value == $di then .value = $ii elif .value == $dd then .value = $id elif .value == "sample-app-deb" then .value = "sample-app" else . end)))' \
    "$T/serveur.json" > "$T/deb-ramene.json"
  jq -S '.spec.jobTemplate.spec' "$T/en-service.json" > "$T/image.json"
  if cmp -s "$T/deb-ramene.json" "$T/image.json"; then echo "OK   gabarit du Job du deb égal à celui de scan-sample-app, hors image, nom, dépôt et NATURE"
  else echo "ÉCART gabarit du Job du deb, ramené à l'image, différent de celui en service :"; diff "$T/image.json" "$T/deb-ramene.json" | head -40; ECARTS=$((ECARTS + 1)); fi
  mesure "NATURE dans analyser" "$(jq -r '.spec.jobTemplate.spec.template.spec.initContainers[] | select(.name == "analyser") | .env[] | select(.name == "NATURE") | .value' "$T/serveur.json")" deb
  mesure "horaire, fuseau, concurrence" "$(jq -r '.spec | "\(.schedule) \(.timeZone) \(.concurrencyPolicy)"' "$T/serveur.json")" "$HORAIRE_DEB Etc/UTC Forbid"
  mesure "horaire de scan-sample-app (inchangé)" "$(jq -r .spec.schedule "$T/en-service.json")" "30 9 * * *"
}

etape_periodique() { # ACCORD NOMMÉ, après S5b et le relevé du 21/11 : écrit dans le cluster (ConfigMap, CronJob, Job) et dans Zot (referrer)
  local d=$DEB_DIGEST avant apres etat="" c m couche libre mini=999999 debut n
  T=$HOME/.cache/supply-chain-poc/06/s6a/periodique
  rm -rf -- "${T:?}"; mkdir -p "$T"
  echo "## préalables"
  applique s6a-scanner-deb.patch
  present builds/sample-app-deb "$d"
  [ -s "$R07/scanner-cle-publique.pem" ] || { echo "KO   clé publique du scanner absente (07a)" >&2; exit 1; }
  echo "## rendu, dry-run serveur, comparaison au CronJob de l'image"
  cronjob_deb
  comparer_cronjobs
  if [ "${S6A_SEC:-}" = 1 ]; then ecarts; echo "S6A_SEC=1 : rien d'écrit"; return 0; fi
  [ "$ECARTS" = 0 ] || { echo "KO   écart(s) avant toute écriture" >&2; exit 1; }
  hors_fenetre
  # corrigé avant tout lancement, après ffbdb87 : un job terminé d'un passage interrompu est retiré, seul un job actif fait refuser
  if kubectl get job -n scan "$JOB_DEB" -o name </dev/null 2>/dev/null | grep -q .; then
    [ -z "$(kubectl get job -n scan "$JOB_DEB" -o jsonpath='{.status.active}' </dev/null)" ] || { echo "KO   job $JOB_DEB encore actif" >&2; exit 1; }
    kubectl delete job -n scan "$JOB_DEB" --wait=true </dev/null >/dev/null
    echo "job $JOB_DEB terminé d'un passage précédent : supprimé (ses journaux sont dans Loki)"
  fi

  echo "## ConfigMap scan-config (comme cm_scan de la 07a), scanner.sh corrigé"
  kubectl create configmap scan-config -n scan --from-file=ca-poc.crt="$CA" --from-file=scanner.sh="$P07/politique/scanner.sh" \
    --from-file=scanner.pub="$R07/scanner-cle-publique.pem" --dry-run=client -o yaml </dev/null | kubectl apply --server-side -f -
  mesure "scanner.sh de scan-config égal à l'arbre" "$(kubectl get configmap -n scan scan-config -o json </dev/null | jq -j '.data["scanner.sh"]' | sha256sum | cut -c1-64)" \
    "$(sha256sum < "$P07/politique/scanner.sh" | cut -c1-64)"

  echo "## CronJob $CRON_DEB et un passage lancé depuis lui"
  kubectl apply --server-side -f "$T/cronjob.json" </dev/null
  avant=$(nb_referrers "$DEPOT_SCAN_DEB" "$d")
  echo "referrers du deb dans $DEPOT_SCAN_DEB avant : $avant"
  kubectl create job -n scan "$JOB_DEB" --from="cronjob/$CRON_DEB" </dev/null
  debut=$(date +%s)
  for _ in $(seq 380); do
    etat=$(kubectl get job -n scan "$JOB_DEB" -o jsonpath='{.status.succeeded}/{.status.failed}' </dev/null)
    # corrigé avant tout lancement, après ffbdb87 : une lecture de place ratée (SSH) n'arrête plus l'étape
    libre=$(ssh "${SSH8[@]}" poc@192.168.161.11 "df -m --output=avail / | tail -1" 2>/dev/null | tr -d ' ' || true)
    case $libre in ''|*[!0-9]*) ;; *) [ "$libre" -lt "$mini" ] && mini=$libre ;; esac
    case $etat in 1/*|*/1) break ;; esac
    sleep 5
  done
  echo "job $etat après $(( $(date +%s) - debut )) s ; place libre la plus basse sur sc-confiance pendant le job : $mini Mo"
  for c in source analyser jetons attester publier revocation; do
    kubectl logs -n scan "job/$JOB_DEB" -c "$c" </dev/null > "$T/$c.log" 2>&1 || true
    echo "### $c ($(grep -ciE 'jeton|token' "$T/$c.log" || true) ligne(s) filtrée(s), jeton|token)"
    grep -viE 'jeton|token' "$T/$c.log" | sed 's/^/  /' || true
  done
  mesure "job" "${etat%%/*}" 1
  mesure "deb extrait dans analyser" "$(grep -c "^DEB|sample-app_1.0.0-1_amd64.deb, sha256 $DEB_SHA, " "$T/analyser.log" || true)" 1
  n=$(sed -n 's/^ARTEFACT|deb, \([0-9]*\) PURL versionnées.*/\1/p' "$T/analyser.log")
  mesure "plancher de l'artefact seul tenu (PURL versionnées > 0)" "$([ "${n:-0}" -gt 0 ] && echo oui || echo "non (${n:-absent})")" oui
  apres=$(nb_referrers "$DEPOT_SCAN_DEB" "$d")
  mesure "referrers du deb dans $DEPOT_SCAN_DEB" "$apres" "$((avant + 1))"
  m=$(sed -n 's/^PUBLIE|[^@]*@\(sha256:[0-9a-f]*\),.*/\1/p' "$T/publier.log")
  [ -n "$m" ] || { echo "KO   aucune ligne PUBLIE" >&2; exit 1; }
  anon -H 'Accept: application/vnd.oci.image.manifest.v1+json' "https://$REG_HOTE/v2/$DEPOT_SCAN_DEB/manifests/$m" > "$T/manifeste.json"
  mesure "sujet du referrer publié" "$(jq -r .subject.digest "$T/manifeste.json")" "$d"
  couche=$(jq -r '.layers[0].digest' "$T/manifeste.json")
  anon -L "https://$REG_HOTE/v2/$DEPOT_SCAN_DEB/blobs/$couche" > "$T/bundle.json"
  if cosign verify-blob-attestation --bundle "$T/bundle.json" --new-bundle-format --key "$R07/scanner-cle-publique.pem" --insecure-ignore-tlog \
    --type "$PREDICAT_SCAN" --digest "${d#sha256:}" --digestAlg sha256 > "$T/v.out" 2>&1; then echo "OK   bundle vérifié sur l'hôte : clé du scanner, sujet $d"
  else sed 's/^/  /' "$T/v.out"; echo "ÉCART bundle non vérifié"; ECARTS=$((ECARTS + 1)); fi
  jq -r .dsseEnvelope.payload "$T/bundle.json" | base64 -d | jq -c '{sujet: [.subject[].name], scannedAt: .predicate.scannedAt, base: .predicate.scanner.db,
    vulnerabilites: (.predicate.vulnerabilities | length), kev: ([.predicate.vulnerabilities[] | select(.kev)] | length)}'
  cp "$T/bundle.json" "$R/s6a-periodique.bundle.json"
  kubectl delete job -n scan "$JOB_DEB" --wait=false </dev/null >/dev/null
  echo "job $JOB_DEB supprimé (journaux archivés ici et dans Loki)"
  ecarts
}

etape_fraicheur() { # ACCORD NOMMÉ, après periodique : sc-stockage (fraicheur-scan.py, fichier complémentaire de l'unité)
  local u=https://$REG_HOTE/v2 b scan_i scan_d base m=""
  T=$HOME/.cache/supply-chain-poc/06/s6a/fraicheur
  rm -rf -- "${T:?}"; mkdir -p "$T"
  echo "## préalables"
  applique s6a-fraicheur-deb.patch
  present builds/sample-app-deb "$DEB_DIGEST"
  for b in "builds/scan/sample-app $APP_DIGEST" "$DEPOT_SCAN_DEB $DEB_DIGEST"; do
    set -- $b
    [ "$(nb_referrers "$1" "$2")" -gt 0 ] || { echo "KO   aucun referrer dans $1 : la série serait absente" >&2; exit 1; }
  done
  echo "OK   un referrer au moins dans chaque dépôt de scan"
  printf '# Brique 06, S6a : deux dépôts de scan (fraicheur-scan.py corrigé par s6a-fraicheur-deb.patch) ; SCANS remplace DEPOT_SCAN et DIGEST.\n[Service]\nEnvironment="SCANS=builds/scan/sample-app@%s %s@%s"\n' \
    "$APP_DIGEST" "$DEPOT_SCAN_DEB" "$DEB_DIGEST" > "$T/s6a-deb.conf"
  cat "$T/s6a-deb.conf"
  echo "## installation sur sc-stockage"
  ssh "${SSH8[@]}" poc@192.168.161.13 'rm -rf /tmp/s6a-fraicheur && mkdir -m 0700 /tmp/s6a-fraicheur'
  scp -q "${SSH8[@]:1}" "$P07/systemd/fraicheur-scan.py" "$T/s6a-deb.conf" poc@192.168.161.13:/tmp/s6a-fraicheur/ </dev/null
  ssh "${SSH8[@]:1}" poc@192.168.161.13 "sudo bash -s" <<'EOS'
set -euo pipefail
cd /tmp/s6a-fraicheur
install -m 0755 fraicheur-scan.py /usr/local/lib/fraicheur-scan/
install -d -m 0755 /etc/systemd/system/fraicheur-scan.service.d
install -m 0644 s6a-deb.conf /etc/systemd/system/fraicheur-scan.service.d/
cd / && rm -rf /tmp/s6a-fraicheur
systemctl daemon-reload
systemctl start fraicheur-scan.service
EOS
  mesure "fraicheur-scan.py installé identique" "$(ssh "${SSH8[@]}" poc@192.168.161.13 'sha256sum /usr/local/lib/fraicheur-scan/fraicheur-scan.py' | cut -c1-64)" "$(sha256sum < "$P07/systemd/fraicheur-scan.py" | cut -c1-64)"
  ssh "${SSH8[@]}" poc@192.168.161.13 'systemctl show -p Result --value fraicheur-scan.service; systemctl is-active fraicheur-scan.timer; systemctl show -p DropInPaths --value fraicheur-scan.service; sudo journalctl -u fraicheur-scan.service -n 2 -o cat --no-pager; cat /etc/fichiers-metriques/fraicheur-scan.prom' | tee "$T/vm.txt"
  mesure "résultat du service" "$(sed -n 1p "$T/vm.txt")" success
  echo "## lecture témoin depuis l'hôte, par un autre chemin que le script (comme g8_metriques)"
  att() { anon "$u/$1/referrers/$2" | jq -r --arg p "$PREDICAT_SCAN" '[.manifests[] | select(.annotations["dev.sigstore.bundle.predicateType"] == $p) | .annotations["org.opencontainers.image.created"] | fromdate] | max'; }
  scan_i=$(att builds/scan/sample-app "$APP_DIGEST")
  scan_d=$(att "$DEPOT_SCAN_DEB" "$DEB_DIGEST")
  base=$(anon "$u/vulndb/grype/tags/list" | jq -r '[.tags[] | select(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))] | max')
  base=$(anon -H 'Accept: application/vnd.oci.image.manifest.v1+json' "$u/vulndb/grype/manifests/$base" | jq -r '.annotations["org.opencontainers.image.created"] | fromdate')
  local attendu_p="base_grype_construite_timestamp_seconds{vulndb/grype}=$base scan_dernier_referrer_timestamp_seconds{$DEPOT_SCAN_DEB}=$scan_d scan_dernier_referrer_timestamp_seconds{builds/scan/sample-app}=$scan_i"
  attendu_p=$(tr ' ' '\n' <<< "$attendu_p" | sort | paste -sd' ')
  for _ in $(seq 18); do   # collecte toutes les 30 s
    m=$(ssh "${SSH8[@]}" poc@192.168.161.13 "curl -s -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query={__name__=~\"scan_dernier_referrer_timestamp_seconds|base_grype_construite_timestamp_seconds\"}'" \
      | jq -r '[.data.result[] | "\(.metric.__name__){\(.metric.depot)}=\(.value[1])"] | sort | join(" ")')
    [ "$m" = "$attendu_p" ] && break
    sleep 5
  done
  mesure "séries lues dans Prometheus" "$m" "$attendu_p"
  ecarts
}

etape_porte() ( # ACCORD NOMMÉ, DISTRO=rke2, après periodique (et pousser_vsa pour une VSA ok) ; sous-shell : les variables de
  # politique.sh (here, R, T, REG, OUTILS…) ne sortent pas de l'étape
  [ "${DISTRO:-}" = rke2 ] || { echo "KO   DISTRO=rke2 attendu" >&2; exit 1; }
  local d=$DEB_DIGEST h06l=$h06 t j v nv vsa_att etat
  T=$HOME/.cache/supply-chain-poc/06/s6a/porte; rm -rf -- "${T:?}"; mkdir -p "$T"
  echo "## préalables (lectures anonymes)"
  present builds/sample-app-deb "$d"
  [ "$(nb_referrers "$DEPOT_SCAN_DEB" "$d")" -gt 0 ] || { echo "KO   aucun scan du deb dans $DEPOT_SCAN_DEB (étape periodique)" >&2; exit 1; }
  nv=$(nb_referrers builds/vsa/sample-app-deb "$d")
  if [ "$nv" -gt 0 ]; then vsa_att=ok; else vsa_att=refus; fi
  echo "referrers du deb dans builds/vsa/sample-app-deb : $nv, VSA attendue : $vsa_att"
  . "$h06l/../08-trust-plane/politique.sh"   # juger, passage, prov_pr ; REG, DEPOT_BUNDLES, TETE_J2, SAMPLE_APP…
  T=$W/s6a-porte; mkdir -p "$T"
  local src cible=builds/sample-app-deb@$d
  src=$(jq -nc --arg u "https://sc-stockage.poc.test:3000/$SAMPLE_APP.git" --arg r "$TETE_J2" '{git: {url: $u, revision: $r}}')
  echo "## porte sur le deb (comme l'étape porte de s4d3.sh)"
  mesure "PipelineRuns en cours dans builds" "$(kubectl get pipelineruns -n builds -o json </dev/null | jq '[.items[] | select((.status.conditions[0].status // "Unknown") == "Unknown")] | length')" 0
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  j=$(passage "$t")
  echo "passage d'horodatage $j"
  echo "provenance de PipelineRun la plus récente du deb (seule jugée) : $(prov_pr "$cible" | jq -sr 'max_by(.predicate.runDetails.metadata.finishedOn).predicate.runDetails.metadata.invocationId')"
  v=$(juger s6a-deb "$REG/$cible" policy.yaml porte "$src" "$REG/$DEPOT_BUNDLES"); echo "$v"
  mesure "deb : succès de ec" "$(cut -d'|' -f3 <<< "$v")" true
  mesure "deb : violations" "$(cut -d'|' -f4 <<< "$v")" ""
  mesure "deb : horodatage" "$(cut -d'|' -f7 <<< "$v")" ok
  mesure "deb : VSA" "$(cut -d'|' -f9 <<< "$v")" "$vsa_att"
  mesure "deb : scan" "$(cut -d'|' -f11 <<< "$v")" ok
  etat=$(kubectl get job -n porte porte-s6a-deb -o jsonpath='{.status.succeeded}/{.status.failed}' </dev/null)
  mesure "Job de la porte" "$etat" "$([ "$vsa_att" = ok ] && echo 1/ || echo /1)"
  ecarts
)

# Lecture par l'auditeur à travers Grafana : grafana_lignes de la 07a, reprise telle quelle (elle lit $S8 et $P, et pose ko=1 sur un
# HTTP autre que 200)
eval "$(sed -n '/^grafana_lignes() {/,/^}/p' "$P07/plateforme.sh")"

etape_grafana() { # ACCORD NOMMÉ, après periodique et fraicheur : lectures seules (comme g7_grafana et g8_grafana de la 07a)
  local de df c l m i ko=0 P=$O8/pki S8=$O8/secrets
  T=$HOME/.cache/supply-chain-poc/06/s6a/grafana
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$HOME/.cache/supply-chain-poc/06/s6a/grafana"' EXIT   # réponses et motifs supprimés même en cas d'échec
  echo "## préalables"
  for c in periodique fraicheur; do
    grep -q '^bilan : tout OK$' "$R/s6a-$c.log" 2>/dev/null || { echo "KO   étape $c non réussie (resultats/s6a-$c.log)" >&2; exit 1; }
  done
  de=$(date -ud "$(sed -n '1s/.*, //p' "$R/s6a-periodique.log")" +%s)
  df=$(date -ud "$(sed -n '1s/.*, //p' "$R/s6a-fraicheur.log")" +%s)
  echo "periodique à partir de $(date -ud "@$de" +%FT%TZ), fraicheur à partir de $(date -ud "@$df" +%FT%TZ)"
  # Un passage planifié depuis periodique ajouterait sa signature et son poussage aux lectures d'OpenBao et de Zot : refus.
  for c in scan-sample-app "$CRON_DEB"; do
    l=$(kubectl get cronjob -n scan "$c" -o jsonpath='{.status.lastScheduleTime}' </dev/null)
    { [ -z "$l" ] || [ "$(date -ud "$l" +%s)" -lt "$de" ]; } \
      || { echo "KO   passage planifié de $c à $l, après periodique : lectures d'OpenBao et de Zot non rattachables au seul $JOB_DEB" >&2; exit 1; }
  done
  echo "OK   aucun passage planifié depuis periodique (scan-sample-app, $CRON_DEB)"

  echo "## journaux du passage $JOB_DEB, lus par l'auditeur (Loki ingère avec quelques secondes de retard)"
  for i in $(seq 30); do
    grafana_lignes "{espace=\"scan\", pod=~\"$JOB_DEB-.*\"}" "$de" "$T/job.json" "$T/job.txt"
    grep -q '^PUBLIE|' "$T/job.txt" && grep -q 'jeton du rôle scanner révoqué' "$T/job.txt" && break
    sleep 2
  done
  # corrigé avant tout lancement, après e237b3d : lignes comptées, jamais affichées (comme g7_grafana) ; periodique archive déjà
  # celles de kubectl logs
  echo "$(wc -l < "$T/job.txt") ligne(s) après $i essai(s), non affichées"
  for m in '^SOURCE|' '^BASE|' "^DEB|sample-app_1.0.0-1_amd64.deb, sha256 $DEB_SHA, " '^ARTEFACT|deb, ' '^SCAN|' '^ATTESTATION|' '^PUBLIE|' \
    'jeton du rôle scanner révoqué'; do
    mesure "visible dans Grafana : ${m%%, sha256*}" "$(grep -q -- "$m" "$T/job.txt" && echo oui || echo non)" oui
  done
  mesure "PUBLIE dans Grafana égal au journal de periodique" "$(sed -n 's/^PUBLIE|//p' "$T/job.txt")" \
    "$(sed -n 's/^  PUBLIE|//p' "$R/s6a-periodique.log")"

  echo "## audit d'OpenBao et de Zot, lus par l'auditeur"
  grafana_lignes '{espace="openbao"} |= "transit/sign/scanner"' "$de" "$T/bao.json" "$T/bao.txt"
  mesure "signature du scanner dans l'audit d'OpenBao, visible dans Grafana" "$([ -s "$T/bao.txt" ] && echo oui || echo non)" oui
  echo "  $(wc -l < "$T/bao.txt") ligne(s) d'audit (non affichées)"
  grafana_lignes "{noeud=\"sc-stockage\", source=\"audit-zot\"} |= \"$DEPOT_SCAN_DEB\" |= \"poc-scan\"" "$de" "$T/zot.json" "$T/zot.txt"
  mesure "poussage par poc-scan dans $DEPOT_SCAN_DEB, visible dans Grafana" "$(grep -q 'manifests' "$T/zot.txt" && echo oui || echo non)" oui

  echo "## journal de fraicheur-scan, lu par l'auditeur"
  for i in $(seq 30); do
    grafana_lignes '{noeud="sc-stockage", source="journal", unite="fraicheur-scan.service"}' "$df" "$T/f.json" "$T/f.txt"
    grep -q '^scan builds/scan/sample-app=[0-9]* builds/scan/sample-app-deb=[0-9]*, base [0-9]*$' "$T/f.txt" && break
    sleep 2
  done
  sed 's/^/  /' "$T/f.txt"
  mesure "mesures des deux dépôts visibles dans Grafana" \
    "$(grep -q '^scan builds/scan/sample-app=[0-9]* builds/scan/sample-app-deb=[0-9]*, base [0-9]*$' "$T/f.txt" && echo oui || echo non)" oui

  echo "## identifiants de poc-scan absents des réponses"
  { cat "$S8/zot-poc-scan.password"; echo; printf 'poc-scan:%s' "$(cat "$S8/zot-poc-scan.password")" | base64 -w0; echo; } > "$T/motifs"
  mesure "mot de passe de poc-scan ou son encodage docker dans les réponses de Grafana" \
    "$(grep -q -F -f "$T/motifs" "$T"/*.json && echo oui || echo non)" non   # sans tube : sous pipefail, un SIGPIPE de cat donnerait « non »
  mesure "requêtes de l'auditeur en HTTP 200" "$([ "$ko" = 0 ] && echo oui || echo non)" oui
  ecarts
}

case "${1:-}:$#" in
  releve:1|essai:1|periodique:1|fraicheur:1|porte:1|grafana:1) ;;
  *) echo "usage : $0 releve|essai|periodique|fraicheur|porte|grafana" >&2; exit 2 ;;
esac
chrono "S6a $1"
{ echo "# ${0##*/} $1, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$1"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/s6a-$1.log"
chrono "S6a $1 fait"
