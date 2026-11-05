#!/usr/bin/env bash
# Brique 07a : scan dans la plateforme (protocole du 04/11/2026, décisions D1 à D6 du propriétaire, README « Suite sur le
# laptop »). Une étape par jalon ; journal dans resultats/<étape>.log.
#   g0  relevés sur l'hôte seul (rien dans Zot, Forgejo ni le cluster) : base Grype du jour téléchargée, empreinte vérifiée,
#       signature cherchée ; import hors réseau par la Grype épinglée (D5 a) ; SBOM de D1 (a) : Syft sur l'image lue par
#       digest dans Zot et sur la source au commit lue dans Forgejo, fusionnés ; scans hors réseau de sample-app et du cas KEV
#       (log4j-core 2.14.1 ajouté au SBOM, comme bench.sh)
#   G1 (D2, D3 a ; Zot reconfiguré avant par « mise run confiance:stockage -- zot » : comptes poc-vulndb et poc-scan,
#       dépôts vulndb/** et builds/scan/**) :
#   g1_oras   oras 1.3.6 de J5 (archive de …/08/telechargements/tsa, empreinte de mise.lock et signature GPG revérifiées) installé
#             dans sc-stockage (/usr/local/bin/oras), empreinte revérifiée dans la VM
#   g1_droits droits de Zot (D2) sur des dépôts jetables : poc-scan crée par digest dans builds/scan/, pas de tag, rien ailleurs ;
#             poc-images et poc-replay ne créent plus dans builds/scan/ ; poc-vulndb crée sous vulndb/, ne remplace pas un tag
#   g1_base   service et timer base-grype sur sc-stockage (utilisateur dédié, mot de passe de poc-vulndb par LoadCredential)
#   g1_essai  run du service : base du jour archivée sous vulndb/grype:<date>, empreinte et annotations relues en lecture
#             anonyme ; second run : déjà archivée ; contre-épreuve : archive tronquée refusée, rien poussé ; mot de passe absent
#             du journal ; timer activé
#   g1_grafana journal de base-grype.service lu par l'auditeur à travers Grafana (19b)
#   G2 (D5 a, D8) : image d'outils du scanner, plateforme/outils-scan dans Zot :
#   g2_telecharger archives de release de Grype 0.104.1 et Syft 1.38.0, checksums.txt, .sig et .pem (…/07a/telechargements)
#   g2_verifier    empreintes de mise.lock et de checksums.txt ; signature sans clé de checksums.txt vérifiée par cosign
#                  (identité : workflow de release du dépôt anchore, émetteur GitHub Actions ; vérification seule, comme
#                  tsa.sh pour cosign) ; contre-épreuve : identité d'un autre dépôt refusée
#   g2_image       couche reproductible (grype, syft, oras de J5, scan-outil construit depuis outil/ à cache vide) sur l'image
#                  cosign v3.1.4-dev (busybox) déjà copiée dans Zot par J5 ; poussée par poc-ecriture ; second assemblage :
#                  même digest
#   G3 (calque de J5 et J8 de la 08 : clé tsa, identifiants Zot du job d'horodatage) :
#   g3_cluster  espace scan (politique/scan.yaml : Pod Security restricted, compte scanner, sortie vers DNS, OpenBao, Zot et
#               Forgejo seulement), ConfigMap scan-config (CA du PoC) ; NetworkPolicy d'OpenBao ouverte aux pods app=scan de
#               l'espace scan (document NetworkPolicy de 08-trust-plane/openbao/openbao.yaml seul : le StatefulSet n'est pas
#               touché) ; scan ajouté à la règle zone-confiance de Kyverno (document de 08-trust-plane/politique/admission.yaml
#               seul) ; sonde : pod de scan sans nodeSelector refusé à l'admission
#   g3_openbao  clé Transit scanner (ecdsa-p256, non exportable, sans sauvegarde en clair), politiques scanner-signature et
#               scan-zot (politique/*.hcl), identifiants Zot de poc-scan dans kv/scan/zot (entrée standard, jamais en
#               argument), rôles JWT scanner (5 min) et scan-zot (1 min) liés au seul compte scan:scanner ; clé publique
#               exportée dans resultats/scanner-cle-publique.pem
#   g3_essais   rôles scanner et scan-zot pour leur compte (comptes exacts d'acceptations et de refus), connexions croisées
#               refusées ; signature Transit vérifiée sur l'hôte par openssl avec la clé publique exportée, refusée avec celle de
#               Chains ; audit d'OpenBao
#   g3_cosign   pod de l'espace scan : jeton du rôle scanner pris par un conteneur d'initialisation OpenBao, cosign sign-blob
#               --key hashivault://scanner hors de tout service Sigstore, jeton révoqué ; sondes réseau (Zot, Forgejo joints ;
#               Grafana, Internet injoignables) ; pod sans l'étiquette app=scan : OpenBao injoignable ; bundle vérifié sur l'hôte
#               (cosign verify-blob, clé exportée), contre-épreuves ; chemins d'OpenBao réellement appelés par cosign (audit)
#   g3_grafana  journaux du pod et signatures de l'audit d'OpenBao lus par l'auditeur à travers Grafana (19b) ; identifiants de
#               poc-scan absents des réponses ; pods d'essai supprimés ensuite (leurs journaux doivent d'abord être collectés)
#   G4 (D1 a, D2, D9 a) : job de scan (politique/scan-job.yaml, politique/scanner.sh, un mode par conteneur) :
#   g4_scan     ConfigMap scan-config complétée (scanner.sh, clé publique du scanner), job lancé sur l'image, attendu ; journaux
#               de chaque conteneur ; place libre de sc-confiance relevée pendant le job (base importée : 3,4 Go au plus haut)
#   g4_verifier referrer de l'image lu en anonyme dans builds/scan/sample-app ; bundle vérifié sur l'hôte (clé du scanner, sujet
#               = digest de l'image, prédicat), contre-épreuves (autre digest, autre prédicat, clé de Chains) ; prédicat relu :
#               scanner, base citée par digest, vulnérabilités et KEV ; audit d'OpenBao ; aucun Secret dans l'espace scan
#   g4_grafana  journaux du job, audit d'OpenBao et audit de Zot (poussage par poc-scan) lus par l'auditeur ; identifiants absents
#               des réponses ; job supprimé ensuite
#   G5 (D4, D6 a) : contrôle 7 dans la porte (politique/porte/, correctif politique/g5-porte.patch de la 08) :
#   g5_regles   hôte seul : ec opa check et ec opa test de scan.rego ; mutations (chaque condition retirée tour à tour, au moins un
#               test doit échouer), comme bascule.sh regle de la 03
#   g5_sec      hôte et lecture anonyme de Zot, rien d'écrit, porte et cluster non touchés : scan-verifier.sh dans le système de
#               fichiers de l'image d'outils de la porte, ec validate input dans celui de l'image de la porte, sans réseau ; scan réel
#               admis, contre-épreuves (sans scan, autre clé, dépôts refusés, entrée absente ou invalide, KEV, MAL-, scan trop vieux) ;
#               correctif appliqué à une copie : Job rendu comme par juger, validé par kubectl en dry-run client, controle7
#   g5_porte    APRÈS R5 SEULEMENT, ACCORD DU PROPRIÉTAIRE : refusé sans VSA nouvelle dans builds/vsa/sample-app (l'ancienne ne compte pas) ; correctif appliqué à l'arbre de
#               travail ; preuves.sh controle7 de la 08 (ConfigMap porte réappliquée, C1 image réelle, C2 sans scan, C3 autre clé)
#   g5_grafana  journaux des conteneurs scan-verifier et scan des Jobs de g5_porte lus par l'auditeur (19b) : trois lectures, un verdict
#               admis et deux refus de ec
#   G6 : témoins négatifs signés par une clé jetable (image à digest propre sous builds/essai-scan, scan en referrer sous
#   builds/scan/essai-scan, tableau resultats/g6-temoins.tsv : cas|digest|ConfigMap|énoncés|contrôle 7|règle) :
#   g6_sec      hôte seul, aucune écriture dans Zot, ni le cluster : tout le parcours sur un Zot jetable, dans un espace de noms réseau
#               vide, avec cosign et ec des images de la porte
#   g6_temoins  ACCORD DU PROPRIÉTAIRE : témoins écrits dans Zot (poc-ecriture, poc-scan), clé jetable effacée ensuite ; puis
#               preuves.sh temoins_scan de la 08 (ConfigMap porte-temoin, un Job de la porte par cas)
#   G7 (D7 b, D10) : rétention (storage de 08-trust-plane/stockage/zot.json), passage périodique du scan, intégration à rejeu.sh :
#   g7_sec      hôte seul, lecture seule de sc-stockage : copie du stockage réel, blobs vieillis de 30 jours, bases et scans synthétiques ;
#               Zot jetable, storage et compat de zot.json, sur trois copies : sans règle, à blanc, règles proposées ; un balayage complet
#   g7_zot      ACCORD DU PROPRIÉTAIRE : Zot reconfiguré et redémarré (confiance:stockage zot), lectures et horodatage contrôlés
#   g7_balayage premier balayage du vrai Zot attendu (35 min environ) : aucune suppression prédite, le store a moins de 14 jours
#   g7_retention décisions de ce balayage lues par l'auditeur (19b) ; hors de rejeu.sh : à J2, le dépôt vulndb/grype n'existe pas encore
#   g7_periodique ACCORD DU PROPRIÉTAIRE : CronJob scan-sample-app (rendu de scan-job.yaml), un passage lancé depuis lui, referrer vérifié
#   g7_grafana  journaux du passage, audit d'OpenBao et audit de Zot lus par l'auditeur (19b)
# Usage (racine du dépôt, outils de mise.toml) : mise exec -- poc/bricks/07a-sbom-grype/plateforme.sh <étape>…
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=$HOME/.cache/supply-chain-poc
P=$O/08/pki
W=$O/07a
REG_HOTE=192.168.161.13:5000                                   # Zot depuis l'hôte (SAN IP du certificat)
FORGEJO=https://192.168.161.13:3000/workspace/sample-app.git   # lecture anonyme
COMMIT=6391fd437f26696847041be3226bbbf633f55a2f                # tête de main relevée le 04/11/2026 à 18:31 UTC
IMAGE=builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
BASE=https://grype.anchore.io/databases/v6
O8=$O/08
S8=$O8/secrets
DL=$O8/telechargements/tsa
ORAS_TGZ_SHA=66fb0ad7206f3f6fa77ed5b552049d364ccf4b50b1684554f731f76302b52ca0   # mise.lock, oras 1.3.6 (comme tsa.sh)
ORAS_FPR=C6FC42F0DE84A345FAADB742F44418110791EF37   # « ORAS Project Release Signing » (KEYS du dépôt, oras.land ; tsa.sh)
DL7=$W/telechargements
GRYPE_TGZ_SHA=2cb820b6c81f88fd6aff3fb4ca5a7161e9ab70af0f27fc5e99cd16deb987cd5f   # mise.lock, grype 0.104.1
SYFT_TGZ_SHA=bc664debb00db1b9b4b9dae4ba1a29d99621e33b641b94b78b9048374b812a3d    # mise.lock, syft 1.38.0
COSIGN_BASE=amont/sigstore/cosign/cosign@sha256:c142f6bc0c6d8e5e4a3d31b941200a12502ad90bb5ce93b78c875c868905619d   # J5 (tsa.sh), v3.1.4-dev amd64
OUTILS_SCAN=plateforme/outils-scan
OUTILS_SCAN_DIGEST=sha256:7eb4f26e7148bd9d000fe9609f58ee6e2ba1fd180f38bd7345e029132eb3f83f   # G2 du 04/11/2026 (assemblage reproductible)
R8=$(cd "$here/../08-trust-plane" && pwd)
REG=sc-stockage.poc.test:5000                                  # Zot depuis les nœuds et les pods
BUILDKIT_IMAGE=amont/moby/buildkit@sha256:ace6811c21334fa502644b9711e0ea48e8539c5c2a843c2325dfb7b987ab260b   # construction.sh (seule image avec git)
BAO_IMAGE=amont/openbao/openbao@sha256:5046911075e137e154ce49ab051502f4ec7cf367d484ae4a4dce665d9b90561f   # openbao.sh (2.7.2)
SUJET_SCAN=system:serviceaccount:scan:scanner
DEPOT_SCAN=builds/scan/sample-app
JOB_SCAN=g4-sample-app
PREDICAT_SCAN=https://supply-chain.example/scan/v1
CRON_SCAN=scan-sample-app
HORAIRE_SCAN='30 9 * * *'   # après le timer de la base (08:00 UTC, retard aléatoire de 15 min au plus)
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
SSH_OPTS=(-i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
sur() { ssh "${SSH_OPTS[@]}" poc@192.168.161.13 "$@"; }   # sc-stockage
copier() { # répertoire-distant fichiers… (comme commun.sh de la 08)
  local d=$1; shift
  sur "rm -rf $d && mkdir -m 0700 $d"
  scp -q "${SSH_OPTS[@]}" "$@" "poc@192.168.161.13:$d/"
}
ko=0
ok() { echo "OK   $1"; }
attendu() { # libellé valeur attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi
}
offline() { unshare -rn env GRYPE_DB_CACHE_DIR="$T/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
  GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false "$@"; }
ms() { local u; read -r u _ < /proc/uptime; echo $(( 10 * 10#${u/./} )); }
purls() { python3 -I -c 'import json, sys; print("\n".join(sorted(c["purl"] for c in json.load(open(sys.argv[1])).get("components", []) if c.get("purl"))))' "$1"; }
racine() { # script sh sur l'entrée standard, exécuté dans openbao-0 avec le jeton root lu sur l'entrée standard (commun.sh de la 08)
  { tr -d '\n' < "$S8/openbao-root.token"; echo; cat; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c 'read -r BAO_TOKEN && export BAO_TOKEN && exec sh -s'
}
en_tant_que() { # compte espace rôle : script sh (entrée standard) exécuté dans openbao-0 après connexion JWT avec ce rôle (tsa.sh)
  # Le jeton du compte de service (audience openbao, 10 min) passe par l'entrée standard, jamais en argument.
  { kubectl create token "$1" -n "$2" --audience openbao --duration 10m; echo; echo "$3"; cat; } \
    | kubectl exec -i -n openbao openbao-0 -- sh -c '
read -r JWT; read -r ROLE
if ! r=$(printf "%s" "$JWT" | bao write -format=json auth/jwt/login role="$ROLE" jwt=- 2>&1); then
  echo "CONNEXION_REFUSEE|$(echo "$r" | grep -E "Code:|\* " | tr "\n\t" "  " | sed "s/  */ /g")"; exit 0
fi
BAO_TOKEN=$(echo "$r" | sed -n "s/.*\"client_token\": \"\([^\"]*\)\".*/\1/p"); export BAO_TOKEN
echo "CONNEXION_ACCEPTEE|$(echo "$r" | tr -d "\n " | grep -o "\"token_policies\":\[[^]]*\]")"
refus() { l=$1; shift; if o=$("$@" 2>&1); then echo "ACCEPTE|$l"; else echo "REFUSE|$l|$(echo "$o" | grep -E "Code:|\* " | tr "\n\t" "  " | sed "s/  */ /g")"; fi; }
eval "$(cat)"'
}
attendre_sa() { # espace : le compte de service default d'un espace neuf est créé de façon asynchrone (commun.sh de la 08)
  for _ in $(seq 60); do kubectl get serviceaccount default -n "$1" >/dev/null 2>&1 && return 0; sleep 1; done
  echo "KO   compte de service default absent de $1"; return 1
}
conforme() { # libellé fichier-attendu fichier-obtenu : chaque ligne obtenue commence par la ligne attendue de même rang
  if paste -d'\t' "$2" "$3" | awk -F'\t' -v n="$(wc -l < "$2")" 'index($2, $1) != 1 {k++} END {exit k > 0 || NR != n}'; then
    echo "OK   $1 ($(wc -l < "$2") lignes conformes)"
  else
    echo "KO   $1"; diff <(cut -c1-60 "$2") <(cut -c1-60 "$3") || true; ko=1
  fi
}
pod_scan() { # nom étiquette-app script : pod d'essai de l'espace scan (image d'outils du scanner), sur le nœud de confiance ;
  # étiquette vide : sans app=scan. Attend la fin (180 s au plus) et affiche la sortie.
  local nom=$1 phase=""
  kubectl delete pod -n scan "$nom" --ignore-not-found --wait=true >/dev/null
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $nom, namespace: scan, labels: {$([ -n "$2" ] && echo "app: $2")}}
spec:
  automountServiceAccountToken: false
  enableServiceLinks: false
  restartPolicy: Never
  nodeSelector: {zone: confiance}
  securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: essai
    image: $REG/$OUTILS_SCAN@$OUTILS_SCAN_DIGEST
    command: [sh, -c, $(jq -Rs . <<<"$3")]
    env: [{name: HOME, value: /travail}]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    volumeMounts: [{name: travail, mountPath: /travail}]
  volumes: [{name: travail, emptyDir: {sizeLimit: 16Mi}}]
EOF
  for _ in $(seq 90); do
    phase=$(kubectl get pod -n scan "$nom" -o jsonpath='{.status.phase}')
    case $phase in Succeeded|Failed) break ;; esac
    sleep 2
  done
  kubectl logs -n scan "$nom" -c essai
  [ "$phase" = Succeeded ] || { echo "KO   pod $nom : ${phase:-?}"; return 1; }
}
# Sonde réseau dans un pod (wget de busybox, sans vérification TLS : seule la joignabilité compte). Délai : connexion abandonnée.
# Nom non résolu : ni joint ni injoignable, le DNS répond à la place de la NetworkPolicy.
SONDE='sonde() { if r=$(timeout 10 wget -q -T 4 -O /dev/null "$2" 2>&1); then echo "JOINT|$1|réponse 2xx"; else
  case $r in *"bad address"*) echo "NON_RESOLU|$1|$r" ;; *"timed out"*|*nreachable*|"") echo "INJOIGNABLE|$1|${r:-délai de 10 s dépassé}" ;; *) echo "JOINT|$1|$(echo "$r" | head -1)" ;; esac; fi; }'
audit_openbao() { # instant : réponses d'OpenBao depuis cet instant (connexions JWT, transit, kv, jetons), agrégées
  kubectl exec -n openbao openbao-0 -- cat /openbao/data/audit.log > "$T/audit.log"
  jq -c --arg d "$1" 'select(.type == "response" and .time[0:19] >= ($d[0:19]) and (.request.path | test("^(auth/jwt/login|transit/|kv/|auth/token/)")))
    | {chemin: .request.path, op: .request.operation, role: (.auth.metadata.role // null), politiques: (.auth.policies // null),
       erreur: (.error // .response.data.error // null)}' "$T/audit.log" \
    | awk '{c[$0]++; if (c[$0] == 1) o[++n] = $0} END {for (i = 1; i <= n; i++) print o[i] (c[o[i]] > 1 ? " ×" c[o[i]] : "")}'
  rm -f "$T/audit.log"
}

cm_scan() { # ConfigMap scan-config : CA du PoC, script du job, clé publique du scanner (seule source : ne pas en réappliquer une partie)
  kubectl create configmap scan-config -n scan --from-file=ca-poc.crt="$P/ca-poc.crt" --from-file=scanner.sh="$here/politique/scanner.sh" \
    --from-file=scanner.pub="$R/scanner-cle-publique.pem" --dry-run=client -o yaml | kubectl apply --server-side -f -
}

rendre_scan() { # nom : politique/scan-job.yaml rendu sur l'image
  sed -e "s#@NOM@#$1#" -e "s#@IMAGE@#$REG/$IMAGE#g" -e "s#@NOM_IMAGE@#sample-app#" -e "s#@DEPOT@#$REG/$DEPOT_SCAN#" \
    -e "s#@BASES@#$REG/vulndb/grype#" -e "s#@SOURCE@#https://sc-stockage.poc.test:3000/workspace/sample-app.git#" -e "s#@COMMIT@#$COMMIT#" \
    -e "s#@OUTILS@#$REG/$OUTILS_SCAN@$OUTILS_SCAN_DIGEST#g" -e "s#@BAO@#$REG/$BAO_IMAGE#g" -e "s#@BUILDKIT@#$REG/$BUILDKIT_IMAGE#g" \
    "$here/politique/scan-job.yaml"
}

etape_g0() {
  T=$W/g0
  chmod -R u+w -- "$T" 2>/dev/null || true
  rm -rf -- "${T:?}"
  mkdir -p "$T"
  cd "$T"
  echo "## outils : grype $(grype version 2>/dev/null | sed -n 's/^Version: *//p') ($(grype version 2>/dev/null | sed -n 's/^BuildDate: *//p')), syft $(syft version 2>/dev/null | sed -n 's/^Version: *//p'), oras $(oras version 2>/dev/null | sed -n 's/^Version: *//p')"

  echo "## base du jour"
  curl -fsS -o latest.json "$BASE/latest.json"
  read -r path checksum built schema < <(python3 -I -c 'import json
d = json.load(open("latest.json"))
print(d["path"], d["checksum"], d["built"], d["schemaVersion"])')
  echo "latest.json : $(python3 -I -c 'import json; print(", ".join(sorted(json.load(open("latest.json")))))') ; construite $built ; schéma $schema"
  attendu "schéma" "$schema" v6.1.10
  t0=$(ms)
  curl -fsS -o "$path" "$BASE/$path"
  echo "archive $path : $(stat -c %s "$path") octets en $(( ($(ms) - t0) / 1000 )) s"
  attendu "empreinte de l'archive" "sha256:$(sha256sum < "$path" | cut -c1-64)" "$checksum"
  for s in "$path.sig" "$path.sigstore.json" "$path.pem" latest.json.sig latest.json.sigstore.json; do
    echo "signature cherchée : $s -> $(curl -s -o /dev/null -w '%{http_code}' "$BASE/$s")"
  done
  t0=$(ms)
  offline grype db import "$path" > import.out 2>&1 || { cat import.out; echo "KO   import hors réseau"; exit 1; }
  echo "import hors réseau en $(( ($(ms) - t0) / 1000 )) s : $(offline grype db status 2>/dev/null | grep -E 'Schema|Built|Status' | tr -s ' ' | paste -sd' ')"
  echo "base importée : $(du -sm dbcache | cut -f1) Mo"

  echo "## SBOM de D1 (a)"
  GIT_SSL_CAINFO=$P/ca-poc.crt git -c init.defaultBranch=main clone -q --no-checkout "$FORGEJO" source
  git -C source -c advice.detachedHead=false checkout -q "$COMMIT"
  attendu "commit de la source" "$(git -C source rev-parse HEAD)" "$COMMIT"
  git -C source fsck --no-progress > /dev/null 2>&1 && ok "git fsck de la source"
  echo "fichiers de verrou : $(cd source && find . -path ./.git -prune -o \( -name go.mod -o -name go.sum -o -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml \) -print | sort | paste -sd' ')"
  rm -rf source/.git
  oras copy --no-tty --from-ca-file "$P/ca-poc.crt" --to-oci-layout "$REG_HOTE/$IMAGE" "image:sample-app" > /dev/null
  attendu "digest de l'image lue" "$(python3 -I -c 'import json; print(json.load(open("image/index.json"))["manifests"][0]["digest"])')" "${IMAGE#*@}"
  offline syft scan "oci-dir:image" -o cyclonedx-json=sbom-image.json -q
  offline syft scan "dir:source" -o cyclonedx-json=sbom-source.json -q
  echo "image (Syft) :"; purls sbom-image.json | sed 's/^/  /'
  echo "source (Syft) :"; purls sbom-source.json | sed 's/^/  /'
  python3 -I "$here/sbom_merge.py" sbom-source.json sbom-image.json source image > sbom-ok.json
  echo "fusion :"; purls sbom-ok.json | sed 's/^/  /'
  # PURL de Syft des deux côtés (D1 a) : chi s'écrit …/chi@v5.2.3#v5, pas …/chi/v5@v5.2.3 comme chez Hermeto (constat de la
  # 07a ; premier passage du 04/11/2026 en KO sur ce seul contrôle, resultats/g0-premier-passage.log)
  for p in 'pkg:golang/github.com/go-chi/chi@v5.2.3#v5' 'pkg:golang/stdlib@' 'pkg:npm/marked@16.4.1'; do
    if purls sbom-ok.json | grep -q -F "$p"; then ok "fusion : $p"; else echo "KO   fusion : $p absent"; ko=1; fi
  done
  if purls sbom-image.json | grep -q 'pkg:npm/marked'; then echo "KO   image : marked vu par Syft (prédit absent)"; ko=1; else ok "image : marked absent (prédit)"; fi
  python3 -I - sbom-ok.json sbom-kev.json <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))
b["components"].append({"type": "library", "name": "log4j-core", "version": "2.14.1",
                        "purl": "pkg:maven/org.apache.logging.log4j/log4j-core@2.14.1"})
json.dump(b, open(sys.argv[2], "w"), indent=2)
PY

  echo "## scans hors réseau"
  for c in ok kev; do
    t0=$(ms)
    offline grype "sbom:sbom-$c.json" -o json --file "grype-$c.json" -q
    python3 -I "$here/scan_predicate.py" "grype-$c.json" "$BASE/$path ($checksum)" > "scan-$c.json"
    python3 -I -c 'import json, sys
v = json.load(open(sys.argv[1]))["vulnerabilities"]
print("scan", sys.argv[2], "en", sys.argv[3], "ms :", len(v), "vulnérabilités dont", sum(x["kev"] for x in v), "KEV :", ", ".join(sorted({c for x in v for c in x["kevCves"]})) or "-")
for x in v: print("  ", x["package"], x["id"], x["severity"], "KEV" if x["kev"] else "")' "scan-$c.json" "$c" "$(( $(ms) - t0 ))"
  done
  attendu "KEV de sample-app" "$(python3 -I -c 'import json, sys; print(sum(x["kev"] for x in json.load(open(sys.argv[1]))["vulnerabilities"]))' scan-ok.json)" 0
  for c in CVE-2021-44228 CVE-2021-45046; do
    if python3 -I -c 'import json, sys; sys.exit(0 if any(sys.argv[2] in x["kevCves"] for x in json.load(open(sys.argv[1]))["vulnerabilities"]) else 1)' scan-kev.json "$c"; then
      ok "cas KEV : $c"; else echo "KO   cas KEV : $c absente"; ko=1; fi
  done
  echo "## empreintes"; sha256sum sbom-image.json sbom-source.json sbom-ok.json scan-ok.json scan-kev.json
  return $ko
}

etape_g1_oras() {
  T=$W/g1-oras
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T/gnupg")
  GNUPGHOME=$T/gnupg gpg --batch --quiet --import "$DL/oras-KEYS" 2>/dev/null
  s=$(GNUPGHOME=$T/gnupg gpg --batch --status-fd 1 --verify "$DL/oras_1.3.6_checksums.txt.asc" "$DL/oras_1.3.6_checksums.txt" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}')
  attendu "signature GPG de oras_1.3.6_checksums.txt (clé primaire)" "$s" "$ORAS_FPR"
  (cd "$DL" && grep ' oras_1.3.6_linux_amd64.tar.gz$' oras_1.3.6_checksums.txt | sha256sum -c && echo "$ORAS_TGZ_SHA  oras_1.3.6_linux_amd64.tar.gz" | sha256sum -c)
  tar -xzf "$DL/oras_1.3.6_linux_amd64.tar.gz" -C "$T" oras
  b=$(sha256sum < "$T/oras" | cut -c1-64)
  attendu "binaire extrait identique à celui de mise" "$b" "$(sha256sum < "$(type -P oras)" | cut -c1-64)"
  copier /tmp/oras-installation "$T/oras"
  sur "sudo bash -s" <<EOF
set -euo pipefail
echo "$b  /tmp/oras-installation/oras" | sha256sum -c
install -m 0755 /tmp/oras-installation/oras /usr/local/bin/oras
rm -rf /tmp/oras-installation
echo "$b  /usr/local/bin/oras" | sha256sum -c
/usr/local/bin/oras version | head -1
EOF
  rm -rf -- "${T:?}"
  return $ko
}

etape_g1_droits() {
  local x=$W/g1-droits img r
  rm -rf -- "${x:?}" && (umask 077 && mkdir -p "$x")
  trap 'rm -rf -- "$W/g1-droits"' EXIT   # copies des mots de passe (auth-*.json) supprimées même en cas d'échec
  for c in poc-scan poc-vulndb poc-images; do
    printf '{"auths":{"%s":{"auth":"%s"}}}' "$REG_HOTE" "$(printf '%s:%s' "$c" "$(cat "$S8/zot-$c.password")" | base64 -w0)" > "$x/auth-$c.json"
  done
  printf 'essai 07a %s\n' "$(date -u +%FT%TZ)" > "$x/f.txt"
  ( cd "$x" && oras push --oci-layout "$x/image:v" f.txt > /dev/null )
  img=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifests"][0]["digest"])' "$x/image/index.json")
  essai() { # libellé attendu(accepte|refus) compte référence-cible
    if oras cp --to-registry-config "$x/auth-$3.json" --to-ca-file "$P/ca-poc.crt" --from-oci-layout "$x/image@$img" "$REG_HOTE/$4" > "$x/sortie" 2>&1; then r=accepte; else r=refus; fi
    [ "$r" = "$2" ] && echo "OK   $1 : $r" || { echo "KO   $1 : $r (attendu $2) : $(grep -m1 -iE 'error|denied|unauthor' "$x/sortie" | cut -c1-140)"; ko=1; }
  }
  essai "poc-scan, par digest dans builds/scan/essai-07a" accepte poc-scan "builds/scan/essai-07a@$img"
  essai "poc-scan, par tag dans builds/scan/essai-07a" refus poc-scan "builds/scan/essai-07a:tag-interdit"
  essai "poc-scan, par digest dans builds/essai-07a (hors de builds/scan/)" refus poc-scan "builds/essai-07a@$img"
  essai "poc-images, par digest dans builds/scan/essai-07a (motif le plus long)" refus poc-images "builds/scan/essai-07a@$img"
  essai "poc-images, par digest dans builds/essai-07a (témoin : droit inchangé)" accepte poc-images "builds/essai-07a@$img"
  essai "poc-vulndb, tag dans vulndb/essai-07a" accepte poc-vulndb "vulndb/essai-07a:v1"
  essai "poc-vulndb, même tag repoussé (mise à jour)" refus poc-vulndb "vulndb/essai-07a:v1"
  essai "poc-vulndb, par digest dans builds/essai-07a" refus poc-vulndb "builds/essai-07a@$img"
  if [ -s "$HOME/.cache/supply-chain-poc/10/secrets/zot-poc-replay.password" ]; then
    printf '{"auths":{"%s":{"auth":"%s"}}}' "$REG_HOTE" "$(printf 'poc-replay:%s' "$(cat "$HOME/.cache/supply-chain-poc/10/secrets/zot-poc-replay.password")" | base64 -w0)" > "$x/auth-poc-replay.json"
    essai "poc-replay, par digest dans builds/scan/essai-07a" refus poc-replay "builds/scan/essai-07a@$img"
  fi
  echo "tags de vulndb/essai-07a : $(oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/vulndb/essai-07a" | paste -sd' ')"
  rm -rf -- "${x:?}"
  return $ko
}

etape_g1_base() {
  copier /tmp/base-grype-installation "$here/fetch-db.sh" "$here/systemd/base-grype.sh" "$here/systemd/base-grype.service" \
    "$here/systemd/base-grype.timer" "$P/ca-poc.crt" "$S8/zot-poc-vulndb.password"
  sur "sudo bash -s" <<'EOF'
set -euo pipefail
cd /tmp/base-grype-installation
id base-grype >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/cache/base-grype --no-create-home --shell /usr/sbin/nologin base-grype
install -d -m 0755 /usr/local/lib/base-grype /etc/base-grype
install -d -m 0700 /etc/base-grype/secrets
install -m 0755 fetch-db.sh base-grype.sh /usr/local/lib/base-grype/
install -m 0644 ca-poc.crt /etc/base-grype/
install -m 0600 zot-poc-vulndb.password /etc/base-grype/secrets/poc-vulndb.password
install -m 0644 base-grype.service base-grype.timer /etc/systemd/system/
cd / && rm -rf /tmp/base-grype-installation
systemctl daemon-reload
ls -l /usr/local/lib/base-grype /etc/base-grype /etc/base-grype/secrets
EOF
  for f in fetch-db.sh systemd/base-grype.sh; do
    attendu "$(basename "$f") installé identique" "$(sur "sha256sum /usr/local/lib/base-grype/$(basename "$f")" | cut -c1-64)" "$(sha256sum < "$here/$f" | cut -c1-64)"
  done
  sur "systemd-analyze security base-grype.service 2>/dev/null | tail -1"
  return $ko
}

etape_g1_essai() {
  local debut r jour ref m
  debut=$(sur "date '+%Y-%m-%d %H:%M:%S'")
  r=0; sur "sudo systemctl start base-grype.service" || r=$?
  echo "premier run : code $r ; $(sur "systemctl show -p Result -p ExecMainStatus --value base-grype.service" | paste -sd' ')"
  echo "## journal du premier run"; sur "sudo journalctl -u base-grype.service --since '$debut' -o cat"
  [ "$r" = 0 ] || { echo "KO   premier run"; return 1; }
  curl -fsS -o "$W/latest.json" "$BASE/latest.json"
  read -r path checksum built < <(python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1])); print(d["path"], d["checksum"], d["built"])' "$W/latest.json")
  jour=${built%%T*}
  ref=$(oras manifest fetch --ca-file "$P/ca-poc.crt" --descriptor "$REG_HOTE/vulndb/grype:$jour" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["digest"])')
  echo "vulndb/grype:$jour -> $ref (lecture anonyme)"
  oras manifest fetch --ca-file "$P/ca-poc.crt" "$REG_HOTE/vulndb/grype@$ref" > "$W/manifeste.json"
  m=$(python3 -I -c 'import json, sys
m = json.load(open(sys.argv[1])); a = m.get("annotations", {})
c = [l["digest"] for l in m["layers"] if l["mediaType"] == "application/vnd.anchore.grype.db.v6+zstd"]
print(m.get("artifactType"), a.get("dev.anchore.grype.db.checksum"), a.get("org.opencontainers.image.created"), c[0] if c else "-")' "$W/manifeste.json")
  read -r at an cr co <<<"$m"
  attendu "artifactType" "$at" application/vnd.supply-chain.grype-db.v6
  attendu "empreinte annoncée (annotation)" "$an" "$checksum"
  attendu "date de construction (annotation)" "$cr" "$built"
  attendu "couche de l'archive = empreinte annoncée" "$co" "$checksum"
  debut=$(sur "date '+%Y-%m-%d %H:%M:%S'")
  r=0; sur "sudo systemctl start base-grype.service" || r=$?
  attendu "second run (code)" "$r" 0
  attendu "second run : base déjà archivée" "$(sur "sudo journalctl -u base-grype.service --since '$debut' -o cat" | grep -c '^déjà archivée : ')" 1
  echo "## contre-épreuve : archive tronquée dans le répertoire de travail (sans identifiants)"
  r=0; sur "bash -s" > "$W/alteree.out" 2>&1 <<EOF || r=$?
set -euo pipefail
t=\$(mktemp -d); trap 'rm -rf "\$t"' EXIT
curl -fsS -o "\$t/latest.json" $BASE/latest.json
p=\$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["path"])' "\$t/latest.json")
curl -fsS -r 0-1048575 -o "\$t/\$p" "$BASE/\$p"
ORAS=/usr/local/bin/oras ORAS_OPTS="--ca-file /etc/base-grype/ca-poc.crt" REG=192.168.161.13:5000 WORKDIR=\$t /usr/local/lib/base-grype/fetch-db.sh
EOF
  cat "$W/alteree.out"
  [ "$r" != 0 ] && grep -q '^empreinte invalide' "$W/alteree.out" && echo "OK   archive tronquée refusée (code $r)" || { echo "KO   contre-épreuve : code $r"; ko=1; }
  attendu "tags de vulndb/grype après la contre-épreuve" "$(oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/vulndb/grype" | paste -sd' ')" "$jour"
  if sur "sudo journalctl -u base-grype.service -o cat" | grep -q -F -f "$S8/zot-poc-vulndb.password"; then echo "KO   mot de passe dans le journal"; ko=1; else echo "OK   mot de passe de poc-vulndb absent du journal de l'unité"; fi
  sur "sudo systemctl enable --now base-grype.timer 2>&1; systemctl list-timers base-grype.timer --no-pager | head -2"
  rm -f "$W/latest.json" "$W/manifeste.json" "$W/alteree.out"
  return $ko
}

etape_g1_grafana() { # journal de base-grype.service lu par l'auditeur à travers Grafana (19b), depuis le début de G1
  local q c o=$W/graf.out
  q=$(jq -nc --arg e '{noeud="sc-stockage", source="journal", unite="base-grype.service"}' --arg de "$(date -ud 2026-11-04T19:20:00Z +%s)000" \
    --arg a "$(date -u +%s)000" '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: 1000, direction: "forward"}], from: $de, to: $a}')
  c=$(printf 'user = "auditeur:%s"\n' "$(cat "$S8/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$P/ca-poc.crt" -o "$o" -w '%{http_code}' -X POST -H 'Content-Type: application/json' "https://192.168.161.13:3001/api/ds/query" -d "$q")
  attendu "requête de l'auditeur (HTTP)" "$c" 200
  jq -r '.results.A.frames[]? | .data.values as $v | range(0; ($v[2] // []) | length) | "\($v[1][.] / 1000 | todate) \($v[2][.])"' "$o" > "$W/lignes"
  cat "$W/lignes"
  grep -q '/vulndb/grype@sha256:' "$W/lignes" && echo "OK   archivage visible dans Grafana" || { echo "KO   archivage absent de Grafana"; ko=1; }
  if grep -q -F -f "$S8/zot-poc-vulndb.password" "$o"; then echo "KO   mot de passe dans la réponse de Grafana"; ko=1; else echo "OK   mot de passe de poc-vulndb absent de la réponse"; fi
  rm -f "$o" "$W/lignes"
  return $ko
}

etape_g2_telecharger() {
  local o v
  mkdir -p "$DL7"
  for o in grype:0.104.1 syft:1.38.0; do
    v=${o#*:}; o=${o%%:*}
    for f in "${o}_${v}_linux_amd64.tar.gz" "${o}_${v}_checksums.txt" "${o}_${v}_checksums.txt.sig" "${o}_${v}_checksums.txt.pem"; do
      [ -s "$DL7/$f" ] || curl -fsSL -o "$DL7/$f" "https://github.com/anchore/$o/releases/download/v$v/$f"
      echo "$f : $(stat -c %s "$DL7/$f") octets"
    done
  done
}

etape_g2_verifier() {
  local o v c id
  T=$W/g2-verifier
  rm -rf -- "${T:?}" && mkdir -p "$T"
  for o in grype:0.104.1:$GRYPE_TGZ_SHA syft:1.38.0:$SYFT_TGZ_SHA; do
    IFS=: read -r o v c <<<"$o"
    echo "## $o $v"
    (cd "$DL7" && echo "$c  ${o}_${v}_linux_amd64.tar.gz" | sha256sum -c && grep " ${o}_${v}_linux_amd64.tar.gz\$" "${o}_${v}_checksums.txt" | sha256sum -c)
    # Certificat publié en PEM encodé en base64 (goreleaser) ou en PEM : ramené au PEM.
    if grep -q -- '-----BEGIN' "$DL7/${o}_${v}_checksums.txt.pem"; then cp "$DL7/${o}_${v}_checksums.txt.pem" "$T/$o.pem"; else base64 -d < "$DL7/${o}_${v}_checksums.txt.pem" > "$T/$o.pem"; fi
    id=$(openssl x509 -in "$T/$o.pem" -noout -ext subjectAltName | sed -n 's/^ *URI://p')
    echo "identité du certificat : $id"
    if cosign verify-blob --certificate "$T/$o.pem" --signature "$DL7/${o}_${v}_checksums.txt.sig" \
         --certificate-identity-regexp "^https://github\.com/anchore/$o/\.github/workflows/release\.yaml@refs/" \
         --certificate-oidc-issuer https://token.actions.githubusercontent.com "$DL7/${o}_${v}_checksums.txt" > "$T/v.out" 2>&1; then
      echo "OK   signature sans clé de ${o}_${v}_checksums.txt : $id"
    else cat "$T/v.out"; echo "KO   signature de ${o}_${v}_checksums.txt"; ko=1; fi
    if cosign verify-blob --certificate "$T/$o.pem" --signature "$DL7/${o}_${v}_checksums.txt.sig" \
         --certificate-identity-regexp "^https://github\.com/anchore/autre/" \
         --certificate-oidc-issuer https://token.actions.githubusercontent.com "$DL7/${o}_${v}_checksums.txt" > "$T/v.out" 2>&1; then
      echo "KO   identité d'un autre dépôt acceptée"; ko=1
    else echo "OK   identité d'un autre dépôt refusée : $(grep -m1 -iE 'error|expected' "$T/v.out" | cut -c1-140)"; fi
  done
  rm -rf -- "${T:?}"
  return $ko
}

etape_g2_image() {
  local d1 d2 b
  T=$W/g2-image
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T/docker")
  trap 'rm -rf -- "$W/g2-image"' EXIT   # copie du mot de passe de poc-ecriture supprimée même en cas d'échec
  printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" "$(printf 'poc-ecriture:%s' "$(cat "$S8/zot-poc-ecriture.password")" | base64 -w0)" > "$T/docker/config.json"
  (cd "$DL" && echo "$ORAS_TGZ_SHA  oras_1.3.6_linux_amd64.tar.gz" | sha256sum -c)
  (cd "$DL7" && echo "$GRYPE_TGZ_SHA  grype_0.104.1_linux_amd64.tar.gz" | sha256sum -c && echo "$SYFT_TGZ_SHA  syft_1.38.0_linux_amd64.tar.gz" | sha256sum -c)
  b=$T/racine/usr/local/bin
  mkdir -p "$b" && chmod 0755 "$T/racine" "$T/racine/usr" "$T/racine/usr/local" "$b"
  tar -xzf "$DL/oras_1.3.6_linux_amd64.tar.gz" -C "$b" oras
  tar -xzf "$DL7/grype_0.104.1_linux_amd64.tar.gz" -C "$b" grype
  tar -xzf "$DL7/syft_1.38.0_linux_amd64.tar.gz" -C "$b" syft
  (cd "$here/outil" && CGO_ENABLED=0 GOCACHE=$T/cache GOFLAGS=-mod=mod go build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o "$b/scan-outil" .)
  rm -rf -- "${T:?}/cache"
  chmod 0755 "$b"/*
  (cd "$b" && sha256sum grype syft oras scan-outil)
  attendu "grype de l'image = grype de mise" "$(sha256sum < "$b/grype" | cut -c1-64)" "$(sha256sum < "$(type -P grype)" | cut -c1-64)"
  attendu "syft de l'image = syft de mise" "$(sha256sum < "$b/syft" | cut -c1-64)" "$(sha256sum < "$(type -P syft)" | cut -c1-64)"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$T/couche.tar" -C "$T/racine" usr
  echo "couche : $(sha256sum < "$T/couche.tar" | cut -c1-64), $(stat -c %s "$T/couche.tar") octets"
  d1=$(DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt crane append -b "$REG_HOTE/$COSIGN_BASE" -f "$T/couche.tar" \
    -t "$REG_HOTE/$OUTILS_SCAN:grype-0.104.1-syft-1.38.0" 2>/dev/null)
  echo "image d'outils du scanner : $d1"
  d2=$(DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt crane append -b "$REG_HOTE/$COSIGN_BASE" -f "$T/couche.tar" \
    -t "$REG_HOTE/$OUTILS_SCAN:grype-0.104.1-syft-1.38.0" 2>/dev/null)
  attendu "second assemblage (même digest)" "${d2##*@}" "${d1##*@}"
  attendu "digest épinglé (G2 du 04/11/2026)" "${d1##*@}" "$OUTILS_SCAN_DIGEST"
  attendu "relue en lecture anonyme" "$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$OUTILS_SCAN:grype-0.104.1-syft-1.38.0")" "${d1##*@}"
  rm -rf -- "${T:?}"
  return $ko
}

etape_g3_cluster() {
  local avant apres msg i
  T=$W/g3-cluster
  rm -rf -- "${T:?}" && mkdir -p "$T"
  echo "## espace scan (politique/scan.yaml)"
  kubectl apply --server-side -f "$here/politique/scan.yaml"
  attendre_sa scan
  cm_scan   # scanner-cle-publique.pem du dépôt : sur une installation neuve, celle d'avant, remplacée par g4_scan après g3_openbao
  attendu "Pod Security de l'espace scan" "$(kubectl get ns scan -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" restricted
  attendu "compte scanner sans jeton monté d'office" "$(kubectl get sa -n scan scanner -o jsonpath='{.automountServiceAccountToken}')" false
  attendu "sorties de l'espace scan (ports)" "$(kubectl get networkpolicy -n scan scan -o json | jq -r '[.spec.egress[].ports[] | "\(.protocol)/\(.port)"] | join(",")')" \
    "UDP/53,TCP/53,TCP/8200,TCP/5000,TCP/3000"

  echo "## NetworkPolicy d'OpenBao (document NetworkPolicy de 08-trust-plane/openbao/openbao.yaml seul ; StatefulSet non touché)"
  avant=$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.metadata.uid} {.status.containerStatuses[0].restartCount}')
  awk 'BEGIN {RS = "\n---\n"} /\nkind: NetworkPolicy\n/' "$R8/openbao/openbao.yaml" | kubectl apply --server-side -f -
  kubectl get networkpolicy -n openbao openbao -o jsonpath='{range .spec.ingress[0].from[*]}{.namespaceSelector.matchLabels}{" "}{.podSelector.matchLabels}{"\n"}{end}'
  attendu "entrée de l'espace scan, pods app=scan seulement" "$(kubectl get networkpolicy -n openbao openbao -o json \
    | jq -r '[.spec.ingress[0].from[] | select(.namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "scan") | .podSelector.matchLabels.app] | join(",")')" scan
  apres=$(kubectl get pod -n openbao openbao-0 -o jsonpath='{.metadata.uid} {.status.containerStatuses[0].restartCount}')
  attendu "openbao-0 ni recréé ni redémarré (uid, redémarrages)" "$apres" "$avant"
  attendu "OpenBao descellé" "$(racine <<<'bao status -format=json' | jq -r .sealed)" false

  echo "## règle zone-confiance de Kyverno (document de 08-trust-plane/politique/admission.yaml seul, appliqué comme charger de politique.sh)"
  awk 'BEGIN {RS = "\n---\n"} /\n  name: zone-confiance\n/' "$R8/politique/admission.yaml" | kubectl apply -f -
  attendu "scan dans les espaces de zone-confiance" "$(kubectl get validatingpolicy zone-confiance -o json \
    | jq -r '.spec.matchConstraints.namespaceSelector.matchExpressions[0].values | index("scan") != null')" true
  # Sonde (comme sonde_kyverno de commun.sh) : pod de scan conforme à Pod Security restricted, sans nodeSelector, en dry-run
  # serveur ; refus attendu de zone-confiance une fois la règle publiée dans le webhook de Kyverno.
  jq -n --arg i "$REG/$OUTILS_SCAN@$OUTILS_SCAN_DIGEST" '{apiVersion: "v1", kind: "Pod", metadata: {name: "sonde-zone", namespace: "scan"},
    spec: {automountServiceAccountToken: false, securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "sonde", image: $i, securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}}' > "$T/sonde.json"
  for i in $(seq 90); do
    msg=$(kubectl create --dry-run=server -f "$T/sonde.json" 2>&1 || true)
    grep -qF 'zone confiance : nodeSelector zone=confiance obligatoire' <<<"$msg" && break
    sleep 2
  done
  if grep -qF 'zone confiance : nodeSelector zone=confiance obligatoire' <<<"$msg"; then
    ok "pod de scan sans nodeSelector refusé par zone-confiance ($i essai(s))"
  else echo "KO   pod de scan sans nodeSelector : $msg"; ko=1; fi
  jq '.spec.nodeSelector = {zone: "confiance"}' "$T/sonde.json" > "$T/sonde-confiance.json"
  msg=$(kubectl create --dry-run=server -f "$T/sonde-confiance.json" 2>&1 || true)
  attendu "contre-épreuve : même pod avec nodeSelector zone=confiance" "$msg" "pod/sonde-zone created (server dry run)"
  rm -rf -- "${T:?}"
  return $ko
}

etape_g3_openbao() {
  local cle pub
  T=$W/g3-openbao
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/g3-openbao"' EXIT   # copie des identifiants de poc-scan supprimée même en cas d'échec
  # Identifiants Zot du job au format docker, registre vu des pods ; passés à OpenBao par l'entrée standard (J8).
  (umask 077 && printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG" \
    "$(printf 'poc-scan:%s' "$(cat "$S8/zot-poc-scan.password")" | base64 -w0)" > "$T/zot-scan.json")
  echo "identifiants Zot du job : compte $(jq -r '.auths[].auth | @base64d | split(":")[0]' "$T/zot-scan.json"), registre $(jq -r '.auths | keys[0]' "$T/zot-scan.json")"
  racine <<EOF | jq -c 'if .data then .data else . end | if has("keys") then {name, type, exportable, allow_plaintext_backup, deletion_allowed, latest_version} else {bound_audiences, bound_subject, user_claim, token_policies, token_no_default_policy, token_type, token_ttl, token_max_ttl, token_period} end' | tee "$T/etat.jsonl"
set -eu
bao read transit/keys/scanner >/dev/null 2>&1 || bao write -f transit/keys/scanner type=ecdsa-p256 exportable=false allow_plaintext_backup=false >&2
bao read -format=json transit/keys/scanner
bao policy write scanner-signature - >&2 <<'POL'
$(cat "$here/politique/scanner-signature.hcl")
POL
bao policy write scan-zot - >&2 <<'POL'
$(cat "$here/politique/scan-zot.hcl")
POL
bao secrets list -format=json | grep -q '"kv/"' || bao secrets enable -path=kv -version=1 kv >&2
bao write kv/scan/zot config.json=- >&2 <<'JSON'
$(cat "$T/zot-scan.json")
JSON
bao write auth/jwt/role/scanner role_type=jwt user_claim=sub bound_audiences=openbao bound_subject=$SUJET_SCAN \
  token_policies=scanner-signature token_no_default_policy=true token_type=service token_ttl=5m token_max_ttl=5m >&2
bao write auth/jwt/role/scan-zot role_type=jwt user_claim=sub bound_audiences=openbao bound_subject=$SUJET_SCAN \
  token_policies=scan-zot token_no_default_policy=true token_type=service token_ttl=1m token_max_ttl=1m >&2
bao read -format=json auth/jwt/role/scanner
bao read -format=json auth/jwt/role/scan-zot
EOF
  cle=$(sed -n 1p "$T/etat.jsonl")
  attendu "clé scanner (type, exportable, sauvegarde en clair, suppression)" "$(jq -r '[.type, .exportable, .allow_plaintext_backup, .deletion_allowed] | join(",")' <<<"$cle")" "ecdsa-p256,false,false,false"
  attendu "rôle scanner" "$(sed -n 2p "$T/etat.jsonl" | jq -r '[.bound_subject, (.bound_audiences | join("+")), (.token_policies | join("+")), .token_no_default_policy, .token_type, .token_ttl, .token_max_ttl, .token_period] | join(",")')" \
    "$SUJET_SCAN,openbao,scanner-signature,true,service,300,300,0"
  attendu "rôle scan-zot" "$(sed -n 3p "$T/etat.jsonl" | jq -r '[.bound_subject, (.bound_audiences | join("+")), (.token_policies | join("+")), .token_no_default_policy, .token_type, .token_ttl, .token_max_ttl, .token_period] | join(",")')" \
    "$SUJET_SCAN,openbao,scan-zot,true,service,60,60,0"
  for p in scanner-signature scan-zot; do
    racine <<<"bao policy read $p" | grep -v '^#' > "$T/$p.hcl"
    attendu "politique $p = fichier versionné (hors commentaires et lignes vides)" "$(grep -v -e '^#' -e '^$' "$T/$p.hcl" | sha256sum | cut -c1-16)" \
      "$(grep -v -e '^#' -e '^$' "$here/politique/$p.hcl" | sha256sum | cut -c1-16)"
  done
  # Valeur relue dans OpenBao et comparée par empreinte, jamais affichée.
  attendu "kv/scan/zot = identifiants de poc-scan (empreinte du JSON compact)" \
    "$(racine <<<'bao read -format=json kv/scan/zot' | jq -r '.data["config.json"] | fromjson | tojson' | sha256sum | cut -c1-16)" \
    "$(jq -c . "$T/zot-scan.json" | sha256sum | cut -c1-16)"
  racine <<<'bao read -format=json transit/keys/scanner' | jq -r '.data.keys | to_entries | max_by(.key | tonumber) | .value.public_key' > "$R/scanner-cle-publique.pem"
  pub=$(openssl pkey -pubin -in "$R/scanner-cle-publique.pem" -outform DER | sha256sum | cut -c1-64)
  openssl pkey -pubin -in "$R/scanner-cle-publique.pem" -noout -text | sed -n '1p;/NIST CURVE/p'
  echo "clé publique exportée : resultats/scanner-cle-publique.pem (SPKI sha256 $pub)"
  return $ko
}

etape_g3_essais() {
  local debut h s
  T=$W/g3-essais
  rm -rf -- "${T:?}" && mkdir -p "$T"
  debut=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  h=$(printf 'Brique 07a, G3' | openssl dgst -sha256 -binary | base64)
  echo "## rôle scanner, compte scan:scanner"
  en_tant_que scanner scan scanner <<EOF | tee "$T/scanner.txt"
refus "lecture de transit/keys/scanner" bao read transit/keys/scanner
echo "SIGNATURE_SCANNER|\$(bao write -field=signature transit/sign/scanner/sha2-256 input=$h prehashed=true)"
refus "signature avec la clé chains" bao write transit/sign/chains/sha2-256 input=$h prehashed=true
refus "signature avec la clé tsa" bao write transit/sign/tsa/sha2-256 input=$h prehashed=true
refus "lecture de transit/keys/chains" bao read transit/keys/chains
refus "export de la clé scanner" bao read transit/export/signing-key/scanner
refus "clé scanner rendue exportable" bao write transit/keys/scanner/config exportable=true
refus "sauvegarde en clair de la clé scanner" bao read transit/backup/scanner
refus "lecture de kv/scan/zot" sh -c 'bao read -field=config.json kv/scan/zot >/dev/null'
refus "lecture de kv/horodatage/zot" sh -c 'bao read -field=config.json kv/horodatage/zot >/dev/null'
refus "lecture de son propre jeton" bao token lookup
refus "renouvellement de son propre jeton" bao token renew
refus "révocation de son propre jeton" bao token revoke -self
refus "signature avec la clé scanner après révocation" bao write transit/sign/scanner/sha2-256 input=$h prehashed=true
EOF
  printf '%s\n' 'CONNEXION_ACCEPTEE|"token_policies":["scanner-signature"]' "ACCEPTE|lecture de transit/keys/scanner" "SIGNATURE_SCANNER|vault:v1:" \
    "REFUSE|signature avec la clé chains|" "REFUSE|signature avec la clé tsa|" "REFUSE|lecture de transit/keys/chains|" \
    "REFUSE|export de la clé scanner|" "REFUSE|clé scanner rendue exportable|" "REFUSE|sauvegarde en clair de la clé scanner|" \
    "REFUSE|lecture de kv/scan/zot|" "REFUSE|lecture de kv/horodatage/zot|" "REFUSE|lecture de son propre jeton|" \
    "REFUSE|renouvellement de son propre jeton|" "ACCEPTE|révocation de son propre jeton" \
    "REFUSE|signature avec la clé scanner après révocation|" > "$T/attendu-scanner.txt"
  conforme "rôle scanner : signe avec la seule clé scanner ; 2 acceptations, 11 refus" "$T/attendu-scanner.txt" "$T/scanner.txt"

  echo "## rôle scan-zot, compte scan:scanner"
  en_tant_que scanner scan scan-zot <<EOF | tee "$T/scan-zot.txt"
refus "lecture de kv/scan/zot" sh -c 'bao read -field=config.json kv/scan/zot >/dev/null'
refus "signature avec la clé scanner" bao write transit/sign/scanner/sha2-256 input=$h prehashed=true
refus "lecture de transit/keys/scanner" bao read transit/keys/scanner
refus "écriture de kv/scan/zot" sh -c 'echo x | bao write kv/scan/zot config.json=-'
refus "lecture de kv/horodatage/zot" sh -c 'bao read -field=config.json kv/horodatage/zot >/dev/null'
refus "révocation de son propre jeton" bao token revoke -self
refus "lecture de kv/scan/zot après révocation" sh -c 'bao read -field=config.json kv/scan/zot >/dev/null'
EOF
  printf '%s\n' 'CONNEXION_ACCEPTEE|"token_policies":["scan-zot"]' "ACCEPTE|lecture de kv/scan/zot" "REFUSE|signature avec la clé scanner|" \
    "REFUSE|lecture de transit/keys/scanner|" "REFUSE|écriture de kv/scan/zot|" "REFUSE|lecture de kv/horodatage/zot|" \
    "ACCEPTE|révocation de son propre jeton" "REFUSE|lecture de kv/scan/zot après révocation|" > "$T/attendu-scan-zot.txt"
  conforme "rôle scan-zot : lit ses seuls identifiants, sans écriture ni signature ; révoqué, il ne lit plus rien" "$T/attendu-scan-zot.txt" "$T/scan-zot.txt"

  echo "## connexions croisées"
  for c in default:scan:scanner default:scan:scan-zot timestamp-authority:tsa:scanner tekton-chains-controller:tekton-chains:scanner \
           horodatage:horodatage:scan-zot scanner:scan:tsa scanner:scan:tekton-chains scanner:scan:horodatage; do
    IFS=: read -r s ns role <<<"$c"
    echo "$ns:$s, rôle $role : $(en_tant_que "$s" "$ns" "$role" </dev/null)"
  done | tee "$T/croisees.txt"
  attendu "connexions croisées refusées" "$(grep -c ' : CONNEXION_REFUSEE|' "$T/croisees.txt")/$(wc -l < "$T/croisees.txt")" "8/8"

  echo "## signature Transit vérifiée sur l'hôte"
  printf 'Brique 07a, G3' > "$T/donnee.txt"
  sed -n 's/^SIGNATURE_SCANNER|vault:v1://p' "$T/scanner.txt" | base64 -d > "$T/signature.der"
  if openssl dgst -sha256 -verify "$R/scanner-cle-publique.pem" -signature "$T/signature.der" "$T/donnee.txt" >/dev/null 2>&1; then
    ok "signature Transit (prehashed sha2-256) vérifiée par openssl avec resultats/scanner-cle-publique.pem"
  else echo "KO   signature Transit non vérifiée avec la clé exportée"; ko=1; fi
  if openssl dgst -sha256 -verify "$R8/resultats/chains-cle-publique.pem" -signature "$T/signature.der" "$T/donnee.txt" >/dev/null 2>&1; then
    echo "KO   signature vérifiée avec la clé de Chains"; ko=1
  else ok "contre-épreuve : même signature refusée avec la clé publique de Chains"; fi

  echo "## audit d'OpenBao depuis $debut"
  audit_openbao "$debut"
  rm -rf -- "${T:?}"
  return $ko
}

etape_g3_cosign() {
  local debut nom=scan-cosign phase="" c jeton_sh signer_sh revocation_sh
  T=$W/g3-cosign
  rm -rf -- "${T:?}" && mkdir -p "$T"
  jeton_sh='set -eu
umask 077
n=1
until bao write -field=token auth/jwt/login role=scanner jwt=@/var/run/secrets/openbao/token > /var/run/bao/token 2> /var/run/bao/erreur; do
  [ $n -lt 30 ] || { cat /var/run/bao/erreur >&2; exit 1; }
  n=$((n + 1)); sleep 1
done
rm -f /var/run/bao/erreur
echo "jeton du rôle scanner obtenu (essai $n)"'
  signer_sh="set -eu
cd /travail
$SONDE
sonde Zot https://$REG/v2/
sonde Forgejo https://192.168.161.13:3000/
sonde Grafana https://192.168.161.13:3001/
sonde \"Internet (1.1.1.1)\" https://1.1.1.1/"'
printf "Brique 07a, G3 : signature témoin\n" > temoin.txt
cosign signing-config create --out vide.json > cosign.log 2>&1
VAULT_TOKEN=$(cat /var/run/bao/token) cosign sign-blob --key hashivault://scanner --signing-config vide.json --bundle temoin.bundle.json --yes temoin.txt >> cosign.log 2>&1 \
  || { cat cosign.log; exit 1; }
tail -1 cosign.log
echo "CLE|$(VAULT_TOKEN=$(cat /var/run/bao/token) cosign public-key --key hashivault://scanner | base64 | tr -d "\n")"
echo "BUNDLE|$(base64 temoin.bundle.json | tr -d "\n")"'
  revocation_sh='BAO_TOKEN=$(cat /var/run/bao/token) bao token revoke -self && echo "jeton du rôle scanner révoqué"'
  debut=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "## pod $nom (app=scan) : jeton du rôle scanner, cosign sign-blob --key hashivault://scanner, révocation"
  kubectl delete pod -n scan "$nom" --ignore-not-found --wait=true >/dev/null
  # Conteneurs d'initialisation en séquence : jeton (OpenBao, jeton projeté d'audience openbao monté là seulement), signer
  # (cosign, sans service Sigstore : configuration de signature vide), puis revocation (OpenBao) en conteneur principal.
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $nom, namespace: scan, labels: {app: scan}}
spec:
  serviceAccountName: scanner
  automountServiceAccountToken: false
  enableServiceLinks: false
  restartPolicy: Never
  nodeSelector: {zone: confiance}
  securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: RuntimeDefault}}
  initContainers:
  - name: jeton
    image: $REG/$BAO_IMAGE
    command: [sh, -c, $(jq -Rs . <<<"$jeton_sh")]
    env: [{name: BAO_ADDR, value: "https://openbao.openbao.svc.cluster.local:8200"}, {name: BAO_CACERT, value: /etc/scan/ca-poc.crt}]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    volumeMounts: [{name: bao, mountPath: /var/run/bao}, {name: config, mountPath: /etc/scan, readOnly: true},
                   {name: openbao-jeton, mountPath: /var/run/secrets/openbao, readOnly: true}]
  - name: signer
    image: $REG/$OUTILS_SCAN@$OUTILS_SCAN_DIGEST
    command: [sh, -c, $(jq -Rs . <<<"$signer_sh")]
    env: [{name: VAULT_ADDR, value: "https://openbao.openbao.svc.cluster.local:8200"}, {name: VAULT_CACERT, value: /etc/scan/ca-poc.crt},
          {name: HOME, value: /travail}, {name: TMPDIR, value: /travail}]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    volumeMounts: [{name: travail, mountPath: /travail}, {name: bao, mountPath: /var/run/bao, readOnly: true},
                   {name: config, mountPath: /etc/scan, readOnly: true}]
  containers:
  - name: revocation
    image: $REG/$BAO_IMAGE
    command: [sh, -c, $(jq -Rs . <<<"$revocation_sh")]
    env: [{name: BAO_ADDR, value: "https://openbao.openbao.svc.cluster.local:8200"}, {name: BAO_CACERT, value: /etc/scan/ca-poc.crt}]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    volumeMounts: [{name: bao, mountPath: /var/run/bao, readOnly: true}, {name: config, mountPath: /etc/scan, readOnly: true}]
  volumes:
  - {name: travail, emptyDir: {sizeLimit: 16Mi}}
  - {name: bao, emptyDir: {medium: Memory, sizeLimit: 1Mi}}
  - {name: config, configMap: {name: scan-config}}
  - name: openbao-jeton
    projected: {sources: [{serviceAccountToken: {audience: openbao, expirationSeconds: 600, path: token}}]}
EOF
  for _ in $(seq 90); do
    phase=$(kubectl get pod -n scan "$nom" -o jsonpath='{.status.phase}')
    case $phase in Succeeded|Failed) break ;; esac
    sleep 2
  done
  for c in jeton signer revocation; do kubectl logs -n scan "$nom" -c "$c" > "$T/$c.log" 2>&1 || true; done
  cat "$T/jeton.log"; grep -v -E '^(CLE|BUNDLE)\|' "$T/signer.log" || true; cat "$T/revocation.log"
  attendu "pod $nom" "$phase" Succeeded
  attendu "sondes du pod app=scan" "$(grep -oE '^(JOINT|INJOIGNABLE|NON_RESOLU)\|[^|]*' "$T/signer.log" | paste -sd' ')" \
    "JOINT|Zot JOINT|Forgejo INJOIGNABLE|Grafana INJOIGNABLE|Internet (1.1.1.1)"

  echo "## bundle vérifié sur l'hôte"
  sed -n 's/^BUNDLE|//p' "$T/signer.log" | base64 -d > "$R/g3-temoin.bundle.json"
  printf 'Brique 07a, G3 : signature témoin\n' > "$T/temoin.txt"
  sed -n 's/^CLE|//p' "$T/signer.log" | base64 -d > "$T/cle-cosign.pem"
  attendu "clé publique lue par cosign = clé exportée (SPKI sha256)" "$(openssl pkey -pubin -in "$T/cle-cosign.pem" -outform DER | sha256sum | cut -c1-64)" \
    "$(openssl pkey -pubin -in "$R/scanner-cle-publique.pem" -outform DER | sha256sum | cut -c1-64)"
  jq -c '{mediaType, materiel: (.verificationMaterial | keys), signature: (.messageSignature | keys), condensat: .messageSignature.messageDigest.algorithm}' "$R/g3-temoin.bundle.json"
  if cosign verify-blob --key "$R/scanner-cle-publique.pem" --bundle "$R/g3-temoin.bundle.json" --insecure-ignore-tlog=true "$T/temoin.txt" > "$T/v.out" 2>&1; then
    ok "bundle vérifié par cosign verify-blob avec resultats/scanner-cle-publique.pem ($(tail -1 "$T/v.out"))"
  else cat "$T/v.out"; echo "KO   bundle non vérifié"; ko=1; fi
  printf 'autre contenu\n' > "$T/autre.txt"
  if cosign verify-blob --key "$R/scanner-cle-publique.pem" --bundle "$R/g3-temoin.bundle.json" --insecure-ignore-tlog=true "$T/autre.txt" > "$T/v.out" 2>&1; then
    echo "KO   contenu modifié accepté"; ko=1
  else ok "contre-épreuve : contenu modifié refusé ($(grep -m1 -oE 'invalid signature[^:]*' "$T/v.out"))"; fi
  if cosign verify-blob --key "$R8/resultats/chains-cle-publique.pem" --bundle "$R/g3-temoin.bundle.json" --insecure-ignore-tlog=true "$T/temoin.txt" > "$T/v.out" 2>&1; then
    echo "KO   bundle vérifié avec la clé de Chains"; ko=1
  else ok "contre-épreuve : clé publique de Chains refusée ($(grep -m1 -oE 'invalid signature[^:]*|key[^:]*mismatch[^:]*' "$T/v.out"))"; fi

  echo "## pod sans l'étiquette app=scan"
  pod_scan scan-sans-etiquette "" "$SONDE
sonde Zot https://$REG/v2/
sonde OpenBao https://openbao.openbao.svc.cluster.local:8200/v1/sys/health" | tee "$T/sans.txt"
  attendu "sondes du pod sans app=scan" "$(grep -oE '^(JOINT|INJOIGNABLE|NON_RESOLU)\|[^|]*' "$T/sans.txt" | paste -sd' ')" "JOINT|Zot INJOIGNABLE|OpenBao"

  echo "## audit d'OpenBao depuis $debut (chemins appelés par cosign)"
  audit_openbao "$debut"
  rm -rf -- "${T:?}"
  return $ko
}

grafana_lignes() { # requête-LogQL depuis-epoch fichier-réponse fichier-lignes : lecture par l'auditeur à travers Grafana (g1_grafana)
  local q c
  q=$(jq -nc --arg e "$1" --arg de "${2}000" --arg a "$(date -u +%s)000" \
    '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: 1000, direction: "forward"}], from: $de, to: $a}')
  c=$(printf 'user = "auditeur:%s"\n' "$(cat "$S8/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$P/ca-poc.crt" -o "$3" -w '%{http_code}' -X POST -H 'Content-Type: application/json' "https://192.168.161.13:3001/api/ds/query" -d "$q")
  [ "$c" = 200 ] || { echo "KO   requête de l'auditeur : HTTP $c"; ko=1; }
  jq -r '.results.A.frames[]? | .data.values as $v | range(0; ($v[2] // []) | length) | $v[2][.]' "$3" > "$4"
}

etape_g3_grafana() {
  local de i
  T=$W/g3-grafana
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/g3-grafana"' EXIT   # motif tiré du mot de passe de poc-scan supprimé même en cas d'échec
  de=$(date -ud "$(sed -n '1s/.*, //p' "$R/g3_cluster.log")" +%s)
  echo "## journaux du pod scan-cosign, lus par l'auditeur (Loki ingère avec quelques secondes de retard)"
  for i in $(seq 30); do
    grafana_lignes '{espace="scan", pod="scan-cosign"}' "$de" "$T/pod.json" "$T/pod.txt"
    grep -q 'jeton du rôle scanner révoqué' "$T/pod.txt" && break
    sleep 2
  done
  grep -v -E '^(CLE|BUNDLE)\|' "$T/pod.txt" || true
  grep -q 'jeton du rôle scanner obtenu' "$T/pod.txt" && grep -q 'jeton du rôle scanner révoqué' "$T/pod.txt" \
    && ok "connexion et révocation visibles dans Grafana ($i essai(s))" || { echo "KO   journaux du pod absents de Grafana"; ko=1; }
  echo "## audit d'OpenBao, lu par l'auditeur"
  for i in $(seq 30); do
    grafana_lignes '{espace="openbao"} |= "transit/sign/scanner"' "$de" "$T/audit.json" "$T/audit.txt"
    [ -s "$T/audit.txt" ] && break
    sleep 2
  done
  echo "lignes d'audit citant transit/sign/scanner : $(wc -l < "$T/audit.txt")"
  [ -s "$T/audit.txt" ] && ok "signatures de la clé scanner visibles dans Grafana ($i essai(s))" || { echo "KO   audit absent de Grafana"; ko=1; }
  echo "## identifiants de poc-scan absents des réponses"
  { cat "$S8/zot-poc-scan.password"; echo; printf 'poc-scan:%s' "$(cat "$S8/zot-poc-scan.password")" | base64 -w0; echo; } > "$T/motifs"
  if cat "$T/pod.json" "$T/audit.json" | grep -q -F -f "$T/motifs"; then echo "KO   identifiants dans les réponses de Grafana"; ko=1
  else ok "ni le mot de passe ni son encodage docker dans les réponses de Grafana"; fi
  kubectl delete pod -n scan scan-cosign scan-sans-etiquette --ignore-not-found --wait=false >/dev/null
  return $ko
}

etape_g4_scan() {
  local etat="" libre mini=999999 c tag base
  T=$W/g4-scan
  rm -rf -- "${T:?}" && mkdir -p "$T"
  echo "## ConfigMap scan-config : CA du PoC, script du job, clé publique du scanner"
  cm_scan
  echo "## job $JOB_SCAN sur $REG/$IMAGE"
  kubectl delete job -n scan "$JOB_SCAN" --ignore-not-found --wait=true >/dev/null
  rendre_scan "$JOB_SCAN" | kubectl apply -f -
  for _ in $(seq 180); do
    etat=$(kubectl get job -n scan "$JOB_SCAN" -o jsonpath='{.status.succeeded}/{.status.failed}')
    libre=$(ssh "${SSH_OPTS[@]}" poc@192.168.161.11 "df -m --output=avail / | tail -1" | tr -d ' ')
    [ "$libre" -lt "$mini" ] && mini=$libre
    case $etat in 1/*|*/1) break ;; esac
    sleep 5
  done
  for c in source analyser jetons attester publier revocation; do
    echo "### $c"; kubectl logs -n scan "job/$JOB_SCAN" -c "$c" 2>&1 | tee "$T/$c.log" | sed 's/^/  /'
  done
  kubectl get pods -n scan -l job-name="$JOB_SCAN" -o json | jq -c '.items[0] | {noeud: .spec.nodeName, phase: .status.phase, debut: .status.startTime,
    fin: (.status.containerStatuses[0].state.terminated.finishedAt // null), init: [.status.initContainerStatuses[] | {(.name): (.state.terminated.exitCode // "?")}] | add}'
  echo "place libre la plus basse sur sc-confiance pendant le job : $mini Mo"
  attendu "job" "${etat%%/*}" 1
  tag=$(oras repo tags --ca-file "$P/ca-poc.crt" "$REG_HOTE/vulndb/grype" | sort | tail -1)
  base=$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/vulndb/grype:$tag")
  attendu "base du job = base la plus récente ($tag)" "$(sed -n 's/^BASE|[^,]*, [^@]*@\(sha256:[0-9a-f]*\),.*/\1/p' "$T/analyser.log")" "$base"
  attendu "commit de la source" "$(sed -n 's/^SOURCE|commit \([0-9a-f]*\),.*/\1/p' "$T/source.log")" "$COMMIT"
  sed -n 's/^SCAN|[^,]*, //p;s/^IMPORT|//p' "$T/analyser.log"
  rm -rf -- "${T:?}"
  return $ko
}

etape_g4_verifier() {
  local d=${IMAGE#*@} h liste man couche c
  T=$W/g4-verifier
  rm -rf -- "${T:?}" && mkdir -p "$T"
  h=${d#sha256:}
  echo "## referrers de l'image dans $DEPOT_SCAN, en lecture anonyme"
  curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$DEPOT_SCAN/referrers/$d" > "$T/referrers.json"
  jq -c '.manifests[] | {digest, artifactType, annotations}' "$T/referrers.json"
  man=$(jq -r '[.manifests[] | select(.annotations["dev.sigstore.bundle.predicateType"] == "'"$PREDICAT_SCAN"'")] | sort_by(.annotations["org.opencontainers.image.created"]) | last | .digest' "$T/referrers.json")
  curl -fsS --cacert "$P/ca-poc.crt" -H 'Accept: application/vnd.oci.image.manifest.v1+json' "https://$REG_HOTE/v2/$DEPOT_SCAN/manifests/$man" > "$T/manifeste.json"
  attendu "empreinte du manifeste" "sha256:$(sha256sum < "$T/manifeste.json" | cut -c1-64)" "$man"
  attendu "sujet du manifeste" "$(jq -r .subject.digest "$T/manifeste.json")" "$d"
  couche=$(jq -r '.layers[0].digest' "$T/manifeste.json")
  curl -fsS --cacert "$P/ca-poc.crt" -L "https://$REG_HOTE/v2/$DEPOT_SCAN/blobs/$couche" > "$R/g4-scan.bundle.json"
  attendu "empreinte du bundle" "sha256:$(sha256sum < "$R/g4-scan.bundle.json" | cut -c1-64)" "$couche"
  verifier() { cosign verify-blob-attestation --bundle "$R/g4-scan.bundle.json" --new-bundle-format --key "$1" --insecure-ignore-tlog --type "$2" --digest "$3" --digestAlg sha256 > "$T/v.out" 2>&1; }
  echo "## bundle vérifié sur l'hôte"
  if verifier "$R/scanner-cle-publique.pem" "$PREDICAT_SCAN" "$h"; then ok "bundle vérifié : clé du scanner, sujet $d, prédicat $PREDICAT_SCAN ($(tail -1 "$T/v.out"))"
  else cat "$T/v.out"; echo "KO   bundle non vérifié"; ko=1; fi
  if verifier "$R/scanner-cle-publique.pem" "$PREDICAT_SCAN" "$(printf '0%.0s' $(seq 64))"; then echo "KO   autre digest accepté"; ko=1
  else ok "contre-épreuve, autre digest refusé : $(grep -m1 -oE 'provided artifact digest[^:]*' "$T/v.out")"; fi
  if verifier "$R/scanner-cle-publique.pem" https://slsa.dev/provenance/v1 "$h"; then echo "KO   autre prédicat accepté"; ko=1
  else ok "contre-épreuve, autre prédicat refusé : $(grep -m1 -oE 'invalid predicate type' "$T/v.out")"; fi
  if verifier "$R8/resultats/chains-cle-publique.pem" "$PREDICAT_SCAN" "$h"; then echo "KO   clé de Chains acceptée"; ko=1
  else ok "contre-épreuve, clé de Chains refusée : $(sed -n 's/^.*Error: //p;s/^error during command execution: //p' "$T/v.out" | head -1 | cut -c1-110)"; fi
  echo "## prédicat signé"
  jq -r .dsseEnvelope.payload "$R/g4-scan.bundle.json" | base64 -d > "$T/enonce.json"
  jq .predicate "$T/enonce.json" > "$R/g4-scan-predicat.json"
  jq -c '{sujet: .subject, predicat: .predicateType, scanner: .predicate.scanner, scannedAt: .predicate.scannedAt, malveillants: .predicate.malicious}' "$T/enonce.json"
  jq -r '.vulnerabilities[] | "  \(.id) \(.severity) kev=\(.kev) \(.packages // .package // "" | tostring | .[0:80])"' "$R/g4-scan-predicat.json"
  attendu "sujet de l'énoncé" "$(jq -r '.subject[0].digest.sha256' "$T/enonce.json")" "$h"
  attendu "scanner" "$(jq -r '"\(.scanner.id) \(.scanner.version)"' "$R/g4-scan-predicat.json")" "grype 0.104.1"
  attendu "base citée par digest" "$(jq -r '.scanner.db.ref | sub("@.*"; "")' "$R/g4-scan-predicat.json")" "$REG/vulndb/grype"
  attendu "KEV" "$(jq '[.vulnerabilities[] | select(.kev)] | length' "$R/g4-scan-predicat.json")" 0
  attendu "paquets malveillants" "$(jq '.malicious | length' "$R/g4-scan-predicat.json")" 0
  echo "vulnérabilités : $(jq '.vulnerabilities | length' "$R/g4-scan-predicat.json")"
  c=$(jq -r 'select(.scanner.db.built == $b) | [.vulnerabilities[].id] | sort | join(",")' --arg b "$(jq -r .scanner.db.built "$R/g4-scan-predicat.json")" "$O/07a/g0/scan-ok.json" 2>/dev/null || true)
  [ -z "$c" ] || attendu "identifiants = ceux de G0 (même base)" "$(jq -r '[.vulnerabilities[].id] | sort | join(",")' "$R/g4-scan-predicat.json")" "$c"
  echo "## aucun Secret dans l'espace scan"
  attendu "Secrets de l'espace scan" "$(kubectl get secrets -n scan -o name | wc -l)" 0
  echo "## audit d'OpenBao depuis le début du job"
  audit_openbao "$(sed -n '1s/.*, //p' "$R/g4_scan.log")"
  rm -rf -- "${T:?}"
  return $ko
}

etape_g4_grafana() {
  local de i
  T=$W/g4-grafana
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/g4-grafana"' EXIT   # motif tiré du mot de passe de poc-scan supprimé même en cas d'échec
  de=$(date -ud "$(sed -n '1s/.*, //p' "$R/g4_scan.log")" +%s)
  echo "## journaux du job, lus par l'auditeur"
  for i in $(seq 30); do
    grafana_lignes '{espace="scan", conteneur=~"source|analyser|jetons|attester|publier|revocation"}' "$de" "$T/job.json" "$T/job.txt"
    grep -q '^PUBLIE|' "$T/job.txt" && grep -q 'jeton du rôle scanner révoqué' "$T/job.txt" && break
    sleep 2
  done
  cut -c1-170 "$T/job.txt"
  for m in '^SOURCE|' '^BASE|' '^SCAN|' '^ATTESTATION|' '^PUBLIE|' 'jeton du rôle scanner révoqué'; do
    if grep -q "$m" "$T/job.txt"; then ok "visible dans Grafana : $m"; else echo "KO   absent de Grafana : $m"; ko=1; fi
  done
  echo "## audit d'OpenBao, lu par l'auditeur"
  grafana_lignes '{espace="openbao"} |= "transit/sign/scanner"' "$de" "$T/bao.json" "$T/bao.txt"
  echo "lignes d'audit citant transit/sign/scanner : $(wc -l < "$T/bao.txt")"
  [ -s "$T/bao.txt" ] && ok "signature du job visible dans Grafana" || { echo "KO   audit d'OpenBao absent de Grafana"; ko=1; }
  echo "## audit de Zot, lu par l'auditeur"
  for i in $(seq 30); do
    grafana_lignes '{noeud="sc-stockage", source="audit-zot"} |= "builds/scan/sample-app" |= "poc-scan"' "$de" "$T/zot.json" "$T/zot.txt"
    grep -q 'manifests' "$T/zot.txt" && break
    sleep 2
  done
  echo "lignes d'audit de Zot : $(wc -l < "$T/zot.txt")"
  grep -q 'manifests' "$T/zot.txt" && ok "poussage du manifeste par poc-scan visible dans Grafana" || { echo "KO   poussage absent de Grafana"; ko=1; }
  echo "## identifiants de poc-scan absents des réponses"
  { cat "$S8/zot-poc-scan.password"; echo; printf 'poc-scan:%s' "$(cat "$S8/zot-poc-scan.password")" | base64 -w0; echo; } > "$T/motifs"
  if cat "$T/job.json" "$T/bao.json" "$T/zot.json" | grep -q -F -f "$T/motifs"; then echo "KO   identifiants dans les réponses de Grafana"; ko=1
  else ok "ni le mot de passe ni son encodage docker dans les réponses de Grafana"; fi
  kubectl delete job -n scan "$JOB_SCAN" --wait=false >/dev/null
  return $ko
}

etape_g5_regles() {
  local b=$W/g5-regles c r k=0 p=$here/politique/porte
  rm -rf -- "${b:?}"; mkdir -p "$b/m"
  cp "$p/scan.rego" "$p/scan_test.rego" "$b/"
  echo "ec $(ec version 2>/dev/null | awk '/^Version/ {print $2}')"
  echo "## ec opa check"
  (cd "$b" && ec opa check scan.rego scan_test.rego) && ok "aucune erreur"
  echo "## ec opa test"
  (cd "$b" && ec opa test -v scan.rego scan_test.rego) | grep -E '^data\.scan_test\.|^PASS:|^FAIL:|^-'
  echo "## mutations : chaque condition retirée tour à tour, au moins un test doit échouer"
  while IFS= read -r c; do
    grep -vF -- "$c" "$b/scan.rego" > "$b/m/scan.rego"
    [ "$(wc -l < "$b/m/scan.rego")" = $(($(wc -l < "$b/scan.rego") - 1)) ] || { echo "KO   condition absente ou ambiguë : $c" >&2; exit 1; }
    r=$(cd "$b" && ec opa test m/scan.rego scan_test.rego 2>&1 | sed -n 's/^data\.scan_test\.\(test_[a-z_]*\): FAIL.*/\1/p' | paste -sd, -) || true
    [ -n "$r" ] && ok "sans « $c » : $r" || { echo "KO   condition non couverte par les tests : $c"; k=$((k + 1)); }
  done <<'FIN'
e.predicateType == _type
s.digest.sha256 == input.digest
s.t == max({a.t | some a in _scans})
count(_scans) == 0
"vulnerabilities": is_array(object.get(p, "vulnerabilities", null)),
"malicious": is_array(object.get(p, "malicious", null)),
"scanner.db.built": _date(object.get(p, ["scanner", "db", "built"], "")),
"kev": _kev_lisibles(p),
not ok
not _age_admis(age)
age >= 0 - _derive
age <= _seuil("scan_age_max_jours") * _jour
not _ecart_admis(ecart)
v.kev == true
not _vex_valide(v)
v.vex.status in _seuil("vex_statuts_acceptes")
time.parse_rfc3339_ns(v.vex.expires) > time.now_ns()
FIN
  [ "$k" = 0 ] || { echo "KO   $k condition(s) non couverte(s)" >&2; exit 1; }
}

VSA_ANCIENNE=sha256:c1bfbcbd7a1d8b44c42634225c89dbf067f13dcff823dec794bd7344da5e5e03   # manifeste de r5-pousser_vsa.log du 03/11/2026
G5_OUTILS=plateforme/outils-horodatage@sha256:c7bebae2bd33e57792988b8ba215536dd9360a9871ec0bdf807ee94d4c1f4ca0   # commun.sh de la 08
G5_PORTE=plateforme/porte@sha256:e77994c20705b4bffd434067033ef2c2f748cf2311f9997c7346b33f0b943926               # politique.sh de la 08
verifier_chroot() { # racine image : scan-verifier.sh dans le système de fichiers de l'image d'outils de la porte, Zot joint à son adresse
  unshare -rm sh -c 'mount --rbind /dev "$1/dev" && mount --rbind /proc "$1/proc" && exec chroot "$1" /busybox/env -i PATH=/busybox:/ko-app \
    HOME=/tmp TMPDIR=/tmp IMAGE="$2" /busybox/sh /etc/porte/scan-verifier.sh' _ "$1" "$2"
}
ec_chroot() { # racine : ec validate input dans le système de fichiers de l'image de la porte, aucune interface réseau, mêmes arguments que le Job
  unshare -rmn sh -c 'mount --rbind /dev "$1/dev" && mount --rbind /proc "$1/proc" && exec env -i HOME=/tmp TMPDIR=/tmp chroot "$1" /ec validate input \
    /partage/scan-entree.json --policy /etc/porte/policy-scan.yaml --info --show-successes --output json' _ "$1"
}
juger_entree() { # libellé code-attendu règles-attendues (triées, virgules ; vide : admis) : entrée posée dans la racine de la porte
  local c=0 v
  ec_chroot "$T/porte" > "$T/ec.out" 2> "$T/ec.err" || c=$?
  v="sans verdict"; [ ! -s "$T/ec.out" ] || v=$(jq -r '[.filepaths[].violations[].metadata.code] | unique | join(",")' "$T/ec.out")
  [ "$c" = "$2" ] && [ "$v" = "$3" ] && ok "$1 : code $c, ${v:-admis}" || { echo "KO   $1 : code $c, violations $v (attendu : code $2, ${3:-aucune}) ; $(tail -1 "$T/ec.err" | cut -c1-200)"; ko=1; }
}
entree_modifiee() { # filtre jq sur le prédicat du scan réel
  jq -c "$1" "$T/reel.json" > "$T/porte/partage/scan-entree.json"
}

etape_g5_sec() {
  local T=$W/g5-sec-jeu ko=0 d=${IMAGE##*@sha256:} n i l q p
  [ ! -d "$T" ] || chmod -R u+w "$T"
  rm -rf -- "${T:?}"; mkdir -p "$T/outils" "$T/porte"
  echo "## correctif de la 08 applicable à l'arbre, qui n'a pas changé"
  git -C "$here/../../.." apply --check "$here/politique/g5-porte.patch" && ok "git apply --check"
  echo "## systèmes de fichiers des images de la porte (Zot, lecture anonyme)"
  SSL_CERT_FILE=$P/ca-poc.crt crane export "$REG_HOTE/$G5_OUTILS" - | tar -xf - -C "$T/outils" --no-same-owner --exclude='dev/*' 2>/dev/null || true
  SSL_CERT_FILE=$P/ca-poc.crt crane export "$REG_HOTE/$G5_PORTE" - | tar -xf - -C "$T/porte" --no-same-owner
  [ -x "$T/outils/ko-app/cosign" ] && [ -x "$T/porte/ec" ] && ok "cosign et ec extraits des images épinglées" || { echo "KO   extraction"; return 1; }
  echo "version de ec dans l'image : $("$T/porte/ec" version 2>/dev/null | awk '/^Version/ {print $2}') ; empreinte $(sha256sum < "$T/porte/ec" | cut -c1-16)"
  for n in outils porte; do mkdir -p "$T/$n/etc/porte/regles-scan" "$T/$n/tmp" "$T/$n/partage" "$T/$n/dev" "$T/$n/proc"; done
  cp "$here/politique/porte/scan-verifier.sh" "$R/scanner-cle-publique.pem" "$P/ca-poc.crt" "$T/outils/etc/porte/"
  mv "$T/outils/etc/porte/scanner-cle-publique.pem" "$T/outils/etc/porte/scanner.pub"
  cp "$here/politique/porte/policy-scan.yaml" "$T/porte/etc/porte/"
  cp "$here/politique/porte/scan.rego" "$T/porte/etc/porte/regles-scan/"

  echo "## scan réel : scan-verifier, puis ec sans réseau"
  verifier_chroot "$T/outils" "$REG_HOTE/$IMAGE" | tee "$T/reel.scan-verifier"
  grep -q "^LECTURE|1|$REG_HOTE/$DEPOT_SCAN|$" "$T/reel.scan-verifier" && ok "1 énoncé vérifié, dépôt dérivé du nom de l'image" || { echo "KO   lecture"; ko=1; }
  jq -e --arg d "$d" '.digest == $d and (.statements | length) == 1' "$T/outils/partage/scan-entree.json" >/dev/null && ok "entrée : digest jugé, un énoncé, JSON valide" || { echo "KO   entrée"; ko=1; }
  cp "$T/outils/partage/scan-entree.json" "$T/reel.json"
  cp "$T/reel.json" "$T/porte/partage/scan-entree.json"
  /usr/bin/time -f "RSS maximal de ec : %M Ko, %e s" -o "$T/ec.time" bash -c "$(declare -f ec_chroot); ec_chroot '$T/porte'" > "$T/ec-reel.json" 2> /dev/null || { echo "KO   ec sur le scan réel"; ko=1; }
  cat "$T/ec.time"
  jq -c '{success, violations: [.filepaths[].violations[].metadata.code], succes: [.filepaths[].successes[].metadata.code]}' "$T/ec-reel.json"
  juger_entree "scan réel" 0 ""

  echo "## contre-épreuves de la lecture"
  for i in "builds/essai-webhook@sha256:$d" "builds/scan/sample-app@sha256:$d" "builds/vsa/sample-app@sha256:$d" "plateforme/porte@sha256:$d" "builds/sample-app:latest"; do
    l=$(verifier_chroot "$T/outils" "$REG_HOTE/$i" | tail -1)
    echo "$i : $(cut -c1-170 <<< "$l")"
    [ "$(cut -d'|' -f2 <<< "$l")" = 0 ] && ok "0 énoncé" || { echo "KO   $i"; ko=1; }
    cp "$T/outils/partage/scan-entree.json" "$T/porte/partage/"
    juger_entree "$i" 1 scan.scan_present
  done
  cp "$R8/resultats/chains-cle-publique.pem" "$T/outils/etc/porte/scanner.pub"
  l=$(verifier_chroot "$T/outils" "$REG_HOTE/$IMAGE" | tail -1)
  echo "clé de Chains à la place de celle du scanner : $(cut -c1-200 <<< "$l")"
  [ "$(cut -d'|' -f2 <<< "$l")" = 0 ] && ok "0 énoncé" || { echo "KO   clé de Chains"; ko=1; }
  cp "$T/outils/partage/scan-entree.json" "$T/porte/partage/"
  juger_entree "clé de Chains" 1 scan.scan_present
  cp "$R/scanner-cle-publique.pem" "$T/outils/etc/porte/scanner.pub"

  echo "## contre-épreuves du jugement, ec de l'image de la porte, entrée modifiée après la lecture (la signature n'est plus en jeu : rôle de G6)"
  entree_modifiee '.statements[0].predicate.vulnerabilities[0].kev = true'
  juger_entree "KEV" 1 scan.kev_without_vex
  entree_modifiee '.statements[0].predicate.vulnerabilities[0] += {kev: true, vex: {status: "not_affected", expires: "2020-01-01T00:00:00Z"}}'
  juger_entree "VEX expiré" 1 scan.kev_without_vex
  entree_modifiee '.statements[0].predicate.vulnerabilities[0] += {kev: true, vex: {status: "not_affected", expires: "2099-01-01T00:00:00Z"}}'
  juger_entree "VEX valide" 0 ""
  entree_modifiee '.statements[0].predicate.malicious = ["MAL-2026-1"]'
  juger_entree "MAL-" 1 scan.malicious
  entree_modifiee '.statements[0].predicate.scannedAt = "2026-10-01T00:00:00Z" | .statements[0].predicate.scanner.db.built = "2026-09-30T00:00:00Z"'
  juger_entree "scan trop vieux" 1 scan.scan_recent
  entree_modifiee '.statements[0].predicate.scanner.db.built = "2026-10-01T00:00:00Z"'
  juger_entree "base trop vieille" 1 scan.base_recente
  entree_modifiee '.statements[0].predicate |= del(.vulnerabilities)'
  juger_entree "prédicat sans vulnerabilities" 1 scan.forme
  printf '{"digest":"' > "$T/porte/partage/scan-entree.json"
  juger_entree "entrée au JSON invalide" 1 "sans verdict"
  rm "$T/porte/partage/scan-entree.json"
  juger_entree "entrée absente" 1 "sans verdict"

  echo "## correctif appliqué à une copie : Job rendu, ConfigMap, controle7"
  q=$T/copie; mkdir -p "$q"
  (cd "$here/../../.." && git archive HEAD poc/bricks/08-trust-plane/politique/porte-job.yaml poc/bricks/08-trust-plane/politique.sh poc/bricks/08-trust-plane/preuves.sh) | tar -xf - -C "$q"
  patch -d "$q" -p1 --quiet < "$here/politique/g5-porte.patch" && ok "correctif appliqué à la copie"
  p=$q/poc/bricks/08-trust-plane
  bash -n "$p/politique.sh" && bash -n "$p/preuves.sh" && ok "bash -n sur politique.sh et preuves.sh corrigés"
  sed -e 's#^\( *- \)--image$#\1--images#' -e "s#\"@IMAGE@\"#'{\"components\":[{\"name\":\"c\",\"containerImage\":\"$REG/$IMAGE\"}]}'#" -e "s#@NOM@#porte-g5#" -e "s#@IMAGE@#$REG/$IMAGE#" -e "s#@PORTE@#$REG/$G5_PORTE#" \
    -e "s#@POLITIQUE@#policy.yaml#" -e "s#@CM@#porte#" -e "s#@OUTILS@#$REG/$G5_OUTILS#" -e "s#@BUNDLES@#$REG/horodatage/bundles#" "$p/politique/porte-job.yaml" > "$T/job.yaml"
  ! grep -n '@[A-Z]*@' "$T/job.yaml" && ok "aucun marqueur restant dans le Job"
  kubectl apply --dry-run=client --validate=strict -f "$T/job.yaml" -o json > "$T/job.json" && ok "Job valide (dry-run client, schéma strict lu sur l'API, rien d'écrit dans le cluster)"
  jq -r '"initContainers : \([.spec.template.spec.initContainers[].name] | join(", ")) ; containers : \([.spec.template.spec.containers[].name] | join(", "))"' "$T/job.json"
  jq -e '.spec.template.spec.initContainers[0].name == "porte"' "$T/job.json" >/dev/null && ok "porte reste le premier conteneur d'initialisation (champ 6 de VERDICT)" || { echo "KO   ordre des conteneurs"; ko=1; }
  kubectl create configmap porte --dry-run=client -o json --from-file=scan-verifier.sh="$here/politique/porte/scan-verifier.sh" --from-file=policy-scan.yaml="$here/politique/porte/policy-scan.yaml" \
    --from-file=scan.rego="$here/politique/porte/scan.rego" --from-file=scanner.pub="$R/scanner-cle-publique.pem" > "$T/cm.json"
  [ "$(jq -r '.data["scan-verifier.sh"]' "$T/cm.json")" = "$(cat "$here/politique/porte/scan-verifier.sh")" ] && ok "clés de la ConfigMap lisibles" || { echo "KO   ConfigMap"; ko=1; }
  (
    eval "$(sed -n '/^controle7() {/,/^}/p' "$p/politique.sh")"
    cp "$T/reel.scan-verifier" "$T/c7.scan-verifier"; jq -c . "$T/ec-reel.json" > "$T/c7.scan"
    echo "controle7, scan réel : $(controle7 "$T/c7")"
    jq -c '.success = false | .filepaths[0].violations = [{metadata: {code: "scan.malicious"}}, {metadata: {code: "scan.kev_without_vex"}}]' "$T/ec-reel.json" > "$T/c7.scan"
    echo "controle7, refus : $(controle7 "$T/c7")"
    echo 'Error: fichier absent' > "$T/c7.scan"
    echo "controle7, ec sans verdict : $(controle7 "$T/c7")"
  )
  chmod -R u+w "$T"; rm -rf -- "${T:?}/outils" "${T:?}/porte"
  return $ko
}

vsa_nouvelles() { # referrers de l'image dans builds/vsa/sample-app autres que la VSA de la provenance d9006af7, poussée le 03/11/2026 et
  # toujours dans Zot : seule une nouvelle VSA prouve que R5 est passé
  curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/builds/vsa/sample-app/referrers/${IMAGE##*@}" 2>/dev/null \
    | jq --arg v "$VSA_ANCIENNE" '[.manifests[].digest | select(. != $v)] | length' 2>/dev/null || true
}

etape_g5_porte() { # APRÈS R5 SEULEMENT, ACCORD DU PROPRIÉTAIRE
  local n c=0 r=$(cd "$here/../../.." && pwd)
  n=$(vsa_nouvelles)
  [ "${n:-0}" -ge 1 ] || { echo "REFUS : aucune VSA nouvelle dans builds/vsa/sample-app, R5 de la 10 n'est pas fini (porte_avant et porte_apres comparent les verdicts)"; exit 1; }
  if git -C "$r" apply --reverse --check "$here/politique/g5-porte.patch" 2>/dev/null; then echo "correctif déjà appliqué"
  else git -C "$r" apply "$here/politique/g5-porte.patch"; ok "correctif appliqué à l'arbre de travail"; fi
  "$R8/preuves.sh" controle7 || c=$?
  cp "$R8/resultats/preuves-controle7.log" "$R/g5_porte.copie.log"   # copié aussi après un échec
  [ "$c" = 0 ] && ! grep -q '^KO' "$R/g5_porte.copie.log"
}

etape_g5_grafana() {
  local de i a r
  T=$W/g5-grafana
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  de=$(date -ud "$(sed -n '1s/.*, //p' "$R/g5_porte.log")" +%s)
  echo "## journaux des conteneurs scan-verifier et scan, lus par l'auditeur"
  for i in $(seq 30); do
    grafana_lignes '{espace="porte", conteneur=~"scan-verifier|scan"}' "$de" "$T/job.json" "$T/job.txt"
    [ "$(grep -c '^LECTURE|' "$T/job.txt" || true)" -ge 3 ] && break
    sleep 2
  done
  grep -E '^(LECTURE|LU)\|' "$T/job.txt" | cut -c1-170
  a=$(grep -c '^{"success":true' "$T/job.txt" || true); r=$(grep -c '^{"success":false' "$T/job.txt" || true)
  echo "verdicts de ec : $a admis, $r refusés"
  [ "$(grep -c '^LECTURE|' "$T/job.txt" || true)" = 3 ] && ok "trois lectures visibles dans Grafana" || { echo "KO   lectures absentes de Grafana"; ko=1; }
  [ "$a" = 1 ] && [ "$r" = 2 ] && ok "un verdict admis et deux refus visibles dans Grafana" || { echo "KO   verdicts de ec"; ko=1; }
  [ "$(grep '^{"success":false' "$T/job.txt" | jq -r '.filepaths[].violations[].metadata.code' | sort -u)" = scan.scan_present ] \
    && ok "refus lus : scan.scan_present" || { echo "KO   code des refus"; ko=1; }
  return $ko
}

G6_DEPOT=builds/essai-scan
temoin_scan() { # registre digest-signé digest-sujet prédicat : scan signé par la clé jetable (modes attester et publier de scanner.sh, hors
  # de tout OpenBao), publié en referrer de digest-sujet ; un digest signé différent du sujet donne le cas autre-digest
  local d=$T/travail/$RANDOM$RANDOM
  mkdir -p "$d"
  cp "$4" "$d/scan.json"
  env TRAVAIL="$d" CA="$G6_CA" CLE="$T/auth/temoin.key" CLE_PUBLIQUE="$T/auth/temoin.pub" COSIGN_PASSWORD= NOM=sample-app IMAGE="x@sha256:$2" \
    sh "$here/politique/scanner.sh" attester > "$d/attester.out"
  env TRAVAIL="$d" CA="$G6_CA" SECRETS="$T/auth" IMAGE="$1/$G6_DEPOT@sha256:$3" DEPOT="$1/builds/scan/${G6_DEPOT#builds/}" \
    sh "$here/politique/scanner.sh" publier > "$d/publier.out"
}
temoin_illisible() { # registre digest-sujet : referrer du type d'un bundle, dont la couche n'est pas du JSON
  local d=$T/travail/$RANDOM$RANDOM
  mkdir -p "$d"
  echo 'ceci n est pas un bundle' > "$d/bundle.json"
  env TRAVAIL="$d" CA="$G6_CA" SECRETS="$T/auth" IMAGE="$1/$G6_DEPOT@sha256:$2" DEPOT="$1/builds/scan/${G6_DEPOT#builds/}" \
    sh "$here/politique/scanner.sh" publier > "$d/publier.out"
}
temoins() { # registre image-de-base tableau : une image par cas, à digest propre ; DOCKER_CONFIG et $T/auth/config.json posés par l'appelant
  local reg=$1 base=$2 tab=$3 passage n b d c v j=$T/predicats
  mkdir -p "$j" "$T/travail"
  passage=$(date -u +%Y%m%dT%H%M%SZ); n=$(date -u +%FT%TZ); b=$(date -ud '1 hour ago' +%FT%TZ)
  (cd "$T/auth" && COSIGN_PASSWORD= cosign generate-key-pair --output-key-prefix temoin > /dev/null 2>&1)
  # Prédicats du scan réel de G4 et du cas log4j de G0, passé par scan-outil : mêmes champs, dates du passage
  propre() { jq --arg n "$n" --arg b "$b" '.scannedAt = $n | .scanner.db.built = $b' "$R/g4-scan-predicat.json"; }
  kev() { jq --arg n "$n" --arg b "$b" '.scannedAt = $n | .scanner.db.built = $b' "$R/g6-predicat-kev.json"; }
  vex() { kev | jq --arg s "$1" --arg e "$2" '.vulnerabilities |= map(if .kev then . + {vex: {status: $s, expires: $e}} else . end)'; }
  dater() { jq --arg n "$(date -ud "$1" +%FT%TZ)" --arg b "$(date -ud "$2" +%FT%TZ)" '.scannedAt = $n | .scanner.db.built = $b'; }
  propre > "$j/propre.json"; kev > "$j/kev.json"
  propre | jq '.malicious = ["MAL-2026-0001"]' > "$j/mal.json"
  vex not_affected "$(date -ud '1 day ago' +%FT%TZ)" > "$j/vex-expire.json"
  vex not_affected "$(date -ud '30 days' +%FT%TZ)" > "$j/vex-valide.json"
  propre | dater '8 days ago' '8 days ago 1 hour ago' > "$j/vieux.json"
  propre | dater '1 hour' 'now' > "$j/futur.json"
  propre | dater 'now' '4 days ago' > "$j/base-vieille.json"
  propre | jq 'del(.vulnerabilities)' > "$j/incomplet.json"
  propre | dater '1 day ago' '1 day ago 1 hour ago' > "$j/hier-propre.json"
  kev | dater '1 day ago' '1 day ago 1 hour ago' > "$j/hier-kev.json"
  : > "$tab"
  for c in propre absent kev mal vex-expire vex-valide vieux futur base-vieille incomplet autre-digest recent-propre recent-kev illisible; do
    d=$(crane mutate --label "poc.test/cas=g6-$c-$passage" -t "$reg/$G6_DEPOT:$c" "$base" 2>/dev/null)
    echo "${d##*@sha256:}" > "$T/image-$c"
  done
  i() { cat "$T/image-$1"; }
  v=$(i propre)
  temoin_scan "$reg" "$v" "$v" "$j/propre.json"
  for c in kev mal vex-expire vex-valide vieux futur base-vieille incomplet; do temoin_scan "$reg" "$(i "$c")" "$(i "$c")" "$j/$c.json"; done
  temoin_scan "$reg" "$v" "$(i autre-digest)" "$j/propre.json"
  temoin_scan "$reg" "$(i recent-propre)" "$(i recent-propre)" "$j/hier-kev.json"
  temoin_scan "$reg" "$(i recent-propre)" "$(i recent-propre)" "$j/propre.json"
  temoin_scan "$reg" "$(i recent-kev)" "$(i recent-kev)" "$j/hier-propre.json"
  temoin_scan "$reg" "$(i recent-kev)" "$(i recent-kev)" "$j/kev.json"
  temoin_scan "$reg" "$(i illisible)" "$(i illisible)" "$j/propre.json"
  temoin_illisible "$reg" "$(i illisible)"
  while IFS='|' read -r c cm e r l; do echo "${c#*:}|$(i "${c%%:*}")|$cm|$e|$r|$l" >> "$tab"; done <<'FIN'
propre|porte-temoin|1|ok|
propre:cle-etrangere|porte|0|refus|scan.scan_present
absent|porte-temoin|0|refus|scan.scan_present
kev|porte-temoin|1|refus|scan.kev_without_vex
mal|porte-temoin|1|refus|scan.malicious
vex-expire|porte-temoin|1|refus|scan.kev_without_vex
vex-valide|porte-temoin|1|ok|
vieux|porte-temoin|1|refus|scan.scan_recent
futur|porte-temoin|1|refus|scan.scan_recent
base-vieille|porte-temoin|1|refus|scan.base_recente
incomplet|porte-temoin|1|refus|scan.forme
autre-digest|porte-temoin|0|refus|scan.scan_present
recent-propre|porte-temoin|2|ok|
recent-kev|porte-temoin|2|refus|scan.kev_without_vex
illisible|porte-temoin|1|ok|
FIN
  echo "$(wc -l < "$tab") cas, $(ls "$T/travail" | wc -l) publications"
}

etape_g6_sec() {
  local T=$W/g6-sec-jeu n
  [ ! -d "$T" ] || chmod -R u+w "$T"
  rm -rf -- "${T:?}"; mkdir -p "$T/outils" "$T/porte"; (umask 077 && mkdir -p "$T/auth" "$T/docker")
  echo "## systèmes de fichiers des images de la porte et image de base (Zot, lecture anonyme)"
  SSL_CERT_FILE=$P/ca-poc.crt crane export "$REG_HOTE/$G5_OUTILS" - | tar -xf - -C "$T/outils" --no-same-owner --exclude='dev/*' 2>/dev/null || true
  SSL_CERT_FILE=$P/ca-poc.crt crane export "$REG_HOTE/$G5_PORTE" - | tar -xf - -C "$T/porte" --no-same-owner
  SSL_CERT_FILE=$P/ca-poc.crt crane pull --format=oci "$REG_HOTE/$IMAGE" "$T/base"
  for n in outils porte; do mkdir -p "$T/$n/etc/porte/regles-scan" "$T/$n/tmp" "$T/$n/partage" "$T/$n/dev" "$T/$n/proc"; done
  cp "$here/politique/porte/scan-verifier.sh" "$T/outils/etc/porte/"
  cp "$here/politique/porte/policy-scan.yaml" "$T/porte/etc/porte/"
  cp "$here/politique/porte/scan.rego" "$T/porte/etc/porte/regles-scan/"
  echo "## Zot jetable : certificat à la volée, écoute sur 127.0.0.1"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=zot-jetable -addext subjectAltName=IP:127.0.0.1 \
    -addext basicConstraints=critical,CA:TRUE -keyout "$T/auth/zot.key" -out "$T/zot.crt" 2>/dev/null
  cp "$T/zot.crt" "$T/outils/etc/porte/ca-poc.crt"
  jq -n --arg r "$T/zot" --arg c "$T/zot.crt" --arg k "$T/auth/zot.key" '{distSpecVersion: "1.1.1", storage: {rootDirectory: $r, gc: false},
    http: {address: "127.0.0.1", port: "15000", tls: {cert: $c, key: $k}}, log: {level: "error"}}' > "$T/zot.json"
  G6_T=$T unshare -rn bash -c 'ip link set lo up && exec "$@"' _ "$0" g6_sec_ns
  rm -f "$R/g6_sec_ns.log"
  chmod -R u+w "$T"; rm -rf -- "${T:?}/outils" "${T:?}/porte" "${T:?}/zot" "${T:?}/base" "${T:?}/auth"
}

etape_g6_sec_ns() { # dans l'espace de noms réseau vide de g6_sec
  local T=$G6_T reg=127.0.0.1:15000 c d cm e r l t ko=0 zp v
  zot serve "$T/zot.json" > "$T/zot.out" 2>&1 & zp=$!
  # shellcheck disable=SC2064   # développement à la pose, voulu
  trap "kill $zp 2>/dev/null || true" EXIT
  for _ in $(seq 40); do curl -fsS --cacert "$T/zot.crt" "https://$reg/v2/" >/dev/null 2>&1 && break; sleep 0.25; done
  export SSL_CERT_FILE=$T/zot.crt DOCKER_CONFIG=$T/docker G6_CA=$T/zot.crt
  echo '{}' > "$T/auth/config.json"; echo '{}' > "$T/docker/config.json"
  crane push "$T/base" "$reg/builds/sample-app:base" 2> /dev/null > /dev/null
  temoins "$reg" "$reg/builds/sample-app:base" "$T/temoins.tsv"
  cp "$T/auth/temoin.pub" "$T/temoin.pub"
  while IFS='|' read -r c d cm e r l; do
    if [ "$cm" = porte ]; then cp "$R/scanner-cle-publique.pem" "$T/outils/etc/porte/scanner.pub"; else cp "$T/temoin.pub" "$T/outils/etc/porte/scanner.pub"; fi
    t=$(verifier_chroot "$T/outils" "$reg/$G6_DEPOT@sha256:$d" | tee "$T/lecture-$c" | tail -1)
    v=$(cut -d'|' -f2 <<< "$t")
    echo "$c ($cm) : $(cut -d'|' -f2,4 <<< "$t" | cut -c1-150)"
    [ "$v" = "$e" ] && ok "$c : $e énoncé(s)" || { echo "KO   $c : $v énoncé(s), prédit $e"; ko=1; }
    cp "$T/outils/partage/scan-entree.json" "$T/porte/partage/"
    if [ "$r" = ok ]; then juger_entree "$c" 0 ""; else juger_entree "$c" 1 "$l"; fi
  done < "$T/temoins.tsv"
  return $ko
}

etape_g6_temoins() { # ACCORD DU PROPRIÉTAIRE : écrit dans Zot
  local T=$W/g6-temoins c=0
  [ ! -d "$T" ] || chmod -R u+w "$T"
  rm -rf -- "${T:?}"; (umask 077 && mkdir -p "$T/auth" "$T/docker")
  trap 'rm -rf -- "$W/g6-temoins/auth" "$W/g6-temoins/docker" "$W/g6-temoins/travail"' EXIT   # clé jetable et identifiants, même en cas d'échec
  printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" "$(printf 'poc-ecriture:%s' "$(cat "$S8/zot-poc-ecriture.password")" | base64 -w0)" > "$T/docker/config.json"
  printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" "$(printf 'poc-scan:%s' "$(cat "$S8/zot-poc-scan.password")" | base64 -w0)" > "$T/auth/config.json"
  export SSL_CERT_FILE=$P/ca-poc.crt DOCKER_CONFIG=$T/docker G6_CA=$P/ca-poc.crt
  temoins "$REG_HOTE" "$REG_HOTE/$IMAGE" "$R/g6-temoins.tsv"
  cp "$T/auth/temoin.pub" "$R/g6-temoin-cle-publique.pem"
  unset SSL_CERT_FILE DOCKER_CONFIG
  "$R8/preuves.sh" temoins_scan || c=$?
  cp "$R8/resultats/preuves-temoins_scan.log" "$R/g6_temoins.copie.log"   # copié aussi après un échec
  [ "$c" = 0 ] && ! grep -q '^KO' "$R/g6_temoins.copie.log"
}

g7_inventaire() { # racine : une ligne par entrée d'index.json (dépôt|digest|tag|sujet) ; VIDE|dépôt ; MANQUE|dépôt|digest pour chaque blob absent
  python3 -I - "$1" <<'PY' | LC_ALL=C sort
import json, os, sys
racine = sys.argv[1]
def chemin(depot, digest): return os.path.join(racine, depot, "blobs", "sha256", digest.split(":")[1])
def charge(depot, digest):
    if not os.path.exists(chemin(depot, digest)):
        print(f"MANQUE|{depot}|{digest}"); return None
    return json.load(open(chemin(depot, digest), "rb"))
def parcours(depot, j, vus):
    for d in [j.get("config")] + j.get("layers", []) + j.get("manifests", []):
        if not d or d["digest"] in vus: continue
        vus.add(d["digest"])
        if "manifest" in d.get("mediaType", ""):
            e = charge(depot, d["digest"])
            if e is not None: parcours(depot, e, vus)
        elif not os.path.exists(chemin(depot, d["digest"])):
            print(f"MANQUE|{depot}|{d['digest']}")
for rep, dirs, fichiers in os.walk(racine):
    dirs[:] = [d for d in dirs if d != "blobs"]
    if "index.json" not in fichiers or "oci-layout" not in fichiers: continue
    depot = os.path.relpath(rep, racine)
    lignes = json.load(open(os.path.join(rep, "index.json"))).get("manifests") or []
    if not lignes: print(f"VIDE|{depot}")
    for m in lignes:
        j = charge(depot, m["digest"])
        if j is None: continue
        parcours(depot, j, set())
        tag = (m.get("annotations") or {}).get("org.opencontainers.image.ref.name", "-")
        print(f"{depot}|{m['digest']}|{tag}|{(j.get('subject') or {}).get('digest', '-')}")
PY
}

g7_config() { # répertoire port filtre-jq : zot.json de la 08, seuls la racine, l'écoute, TLS, l'authentification et les journaux changent
  jq --arg r "$1/racine" --arg p "$2" --arg d "$1" '.storage.rootDirectory = $r | .http = {address: "127.0.0.1", port: $p, compat: .http.compat}
    | .log = {level: "debug", output: ($d + "/zot.log"), audit: ($d + "/audit.log")} | '"$3" "$R8/stockage/zot.json" > "$1/zot.json"
  zot verify "$1/zot.json" 2>&1 | grep -q 'config file is valid' || { echo "KO   configuration refusée par zot verify : $1/zot.json"; exit 1; }
}

g7_demarrer() { # répertoire port
  zot serve "$1/zot.json" > "$1/zot.out" 2>&1 &
  echo $! > "$1/zot.pid"
  for _ in $(seq 240); do curl -fsS "http://127.0.0.1:$2/v2/" >/dev/null 2>&1 && return 0; sleep 0.25; done
  echo "KO   Zot jetable muet : $1"; exit 1
}

g7_arreter() { kill "$(cat "$1/zot.pid")" 2>/dev/null || true; while kill -0 "$(cat "$1/zot.pid")" 2>/dev/null; do sleep 0.2; done; }

g7_referrer() { # registre racine dépôt sujet-descripteur libellé âge-en-jours : referrer de la forme de scanner.sh publier, vieilli par son blob ; digest rendu
  local f m d
  f=$(mktemp -d -p "$W")
  printf '{}' > "$f/vide"; printf '%s' "$5" > "$f/couche"
  oras blob push --plain-http "$1/$3" "$f/vide" > /dev/null
  oras blob push --plain-http "$1/$3" "$f/couche" > /dev/null
  jq -nc --arg t application/vnd.dev.sigstore.bundle.v0.3+json --arg c "sha256:$(sha256sum < "$f/couche" | cut -c1-64)" --argjson n "${#5}" --argjson s "$4" \
    --arg p "$PREDICAT_SCAN" '{schemaVersion: 2, mediaType: "application/vnd.oci.image.manifest.v1+json", artifactType: $t,
      config: {mediaType: "application/vnd.oci.empty.v1+json", digest: "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", size: 2},
      layers: [{mediaType: $t, digest: $c, size: $n}], subject: $s, annotations: {"dev.sigstore.bundle.predicateType": $p}}' | tr -d '\n' > "$f/manifeste"
  d=sha256:$(sha256sum < "$f/manifeste" | cut -c1-64)
  oras manifest push --plain-http "$1/$3@$d" "$f/manifeste" > /dev/null
  [ "$6" = 0 ] || touch -d "$6 days ago" "$2/$3/blobs/sha256/${d#sha256:}"
  rm -rf -- "${f:?}"
  echo "$d"
}

etape_g7_sec() {
  local T=$W/g7-sec P0 n i j c d s r sujet d15 d13 d0 v15 base04 base05 nd
  export LC_ALL=C
  [ ! -d "$T" ] || chmod -R u+w "$T"
  rm -rf -- "${T:?}"; mkdir -p "$T/prep/racine"
  # shellcheck disable=SC2064   # développement à la pose, voulu
  trap "for f in $T/*/zot.pid; do kill \"\$(cat \"\$f\" 2>/dev/null)\" 2>/dev/null || true; done" EXIT
  P0=$T/prep
  echo "## copie du stockage réel, lecture seule (ni sessions, ni téléversements en cours)"
  sur 'sudo tar -C /var/lib/zot --exclude=./_sessions --exclude=./.uploads -cf - .' | tar -xf - -C "$P0/racine" --no-same-owner
  echo "copie : $(du -sm "$P0/racine" | cut -f1) Mo, $(find "$P0/racine" -name index.json | wc -l) dépôts"
  echo "## blobs vieillis de 30 jours : sur un store de deux jours, le délai de rétention masquerait les suppressions à venir"
  find "$P0/racine" -path '*/blobs/sha256/*' -type f -exec touch -d '30 days ago' {} +
  g7_config "$P0" 15070 '.storage.gc = false | del(.storage.retention)'
  g7_demarrer "$P0" 15070
  r=127.0.0.1:15070
  sujet=$(curl -fsS "http://$r/v2/builds/sample-app/manifests/${IMAGE#*@}" -H 'Accept: application/vnd.oci.image.manifest.v1+json' -o "$T/m" -w '%{size_download}')
  sujet=$(jq -nc --arg d "${IMAGE#*@}" --argjson n "$sujet" '{mediaType: "application/vnd.oci.image.manifest.v1+json", digest: $d, size: $n}')
  base04=$(jq -r '.manifests[] | select(.annotations["org.opencontainers.image.ref.name"] == "2026-11-04") | .digest' "$P0/racine/vulndb/grype/index.json")
  echo "## bases synthétiques : douze tags datés, poussés dans l'ordre, 13 tags en tout"
  mkdir -p "$T/bases"
  for i in $(seq 1 12); do
    d=$(date -ud "2026-11-04 +$i days" +%F)
    echo "$d" > "$T/bases/base"
    (cd "$T/bases" && oras push --plain-http --artifact-type application/vnd.supply-chain.grype-db.v6 "$r/vulndb/grype:$d" base > /dev/null)
    sleep 1.1
  done
  base05=$(oras manifest fetch --plain-http --descriptor "$r/vulndb/grype:2026-11-05" | jq -r .digest)
  echo "## scans synthétiques : referrers de l'image réelle, de 15, 13 et 0 jours ; un referrer de 15 jours dans builds/vsa/sample-app"
  d15=$(g7_referrer "$r" "$P0/racine" "$DEPOT_SCAN" "$sujet" jour-15 15)
  d13=$(g7_referrer "$r" "$P0/racine" "$DEPOT_SCAN" "$sujet" jour-13 13)
  d0=$(g7_referrer "$r" "$P0/racine" "$DEPOT_SCAN" "$sujet" jour-0 0)
  v15=$(g7_referrer "$r" "$P0/racine" builds/vsa/sample-app "$sujet" jour-15-vsa 15)
  echo "scans : 15 j ${d15:7:12}, 13 j ${d13:7:12}, 0 j ${d0:7:12} ; VSA de 15 j ${v15:7:12}"
  g7_arreter "$P0"
  g7_inventaire "$P0/racine" > "$T/avant.txt"
  n=$(find "$P0/racine" -name oci-layout | wc -l)
  echo "avant : $n dépôts, $(grep -c '^[^|]*|sha256' "$T/avant.txt") entrées, $(grep -c '^VIDE|' "$T/avant.txt") dépôt(s) vide(s), $(grep -c '^MANQUE|' "$T/avant.txt" || true) blob(s) manquant(s)"
  attendu "blobs manquants avant le balayage" "$(grep -c '^MANQUE|' "$T/avant.txt" || true)" 0

  echo "## trois copies, un Zot par copie, un balayage complet ($n dépôts, 15 s par dépôt en moyenne)"
  i=15071
  for c in sansregle blanc prop; do
    mkdir -p "$T/$c"
    cp -al "$P0/racine" "$T/$c/racine"
    find "$P0/racine" \( -name index.json -o -name cache.db -o -name meta.db \) -printf '%P\n' | while read -r f; do cp --remove-destination -p "$P0/racine/$f" "$T/$c/racine/$f"; done
    case $c in
      sansregle) g7_config "$T/$c" "$i" 'del(.storage.retention)' ;;
      blanc) g7_config "$T/$c" "$i" '.storage.retention.dryRun = true' ;;
      prop) g7_config "$T/$c" "$i" '.' ;;
    esac
    g7_demarrer "$T/$c" "$i"
    i=$((i + 1))
  done
  for s in $(seq 3000); do
    j=0
    for c in sansregle blanc prop; do
      [ "$(grep -o 'gc successfully completed for [^"]*' "$T/$c/zot.log" | sort -u | wc -l)" -ge "$n" ] && j=$((j + 1))
    done
    [ "$j" = 3 ] && break
    sleep 2
  done
  echo "balayages finis : $j/3, $((s * 2)) s environ"
  for c in sansregle blanc prop; do echo "$c : $(grep -o 'gc successfully completed for [^"]*' "$T/$c/zot.log" | sort -u | wc -l) dépôts balayés"; done
  attendu "balayages complets" "$j" 3

  echo "## règles proposées : lectures par l'API, Zot jetable toujours en marche"
  r=127.0.0.1:15073
  h() { curl -s -o /dev/null -w '%{http_code}' -I -H 'Accept: application/vnd.oci.image.manifest.v1+json' "http://$r/v2/$1"; }
  attendu "image réelle, sans tag" "$(h "builds/sample-app/manifests/${IMAGE#*@}")" 200
  attendu "signature .sig" "$(h "builds/sample-app/manifests/sha256-${IMAGE#*@sha256:}.sig")" 200
  attendu "attestation .att" "$(h "builds/sample-app/manifests/sha256-${IMAGE#*@sha256:}.att")" 200
  attendu "VSA de builds/vsa/sample-app (2 réelles, 1 de 15 jours)" "$(curl -fsS "http://$r/v2/builds/vsa/sample-app/referrers/${IMAGE#*@}" | jq '.manifests | length')" 3
  attendu "scans restants (13 et 0 jours)" "$(curl -fsS "http://$r/v2/$DEPOT_SCAN/referrers/${IMAGE#*@}" | jq -r '[.manifests[].digest] | sort | join(" ")')" "$(printf '%s\n' "$d13" "$d0" | sort | paste -sd' ')"
  attendu "tags de vulndb/grype (les 11 plus récemment poussés)" "$(curl -fsS "http://$r/v2/vulndb/grype/tags/list" | jq -r '.tags | sort | join(" ")')" "$(for i in $(seq 2 12); do date -ud "2026-11-04 +$i days" +%F; done | paste -sd' ')"
  attendu "base du 5/11 : tag retiré" "$(h vulndb/grype/manifests/2026-11-05)" 404
  attendu "base du 5/11 : encore lisible par digest, plus jeune que le délai" "$(h "vulndb/grype/manifests/$base05")" 200
  attendu "base du 4/11 (30 jours) : effacée" "$(h "vulndb/grype/manifests/$base04")" 404
  for c in sansregle blanc prop; do g7_arreter "$T/$c"; g7_inventaire "$T/$c/racine" > "$T/$c/apres.txt"; done

  echo "## règles proposées : différence exacte avec la prédiction"
  awk -F'|' -v a="$d13" -v b="$d0" -v b4="$base04" -v b5="$base05" '
    $1 == "VIDE" { next }
    $1 ~ /^builds\/scan\// && $4 != "-" && $2 != a && $2 != b { next }
    $1 == "vulndb/grype" && $2 == b4 { next }
    $1 == "vulndb/grype" && $2 == b5 { print $1 "|" $2 "|-|" $4; next }
    { print }' "$T/avant.txt" | sort > "$T/prevu.txt"
  nd=$(diff "$T/prevu.txt" <(grep -v '^VIDE|' "$T/prop/apres.txt") | grep -c '^[<>]' || true)
  diff "$T/prevu.txt" <(grep -v '^VIDE|' "$T/prop/apres.txt") | cut -c1-140 | head -20 || true
  attendu "écarts à la prédiction ligne à ligne" "$nd" 0
  attendu "blobs manquants après le balayage" "$(grep -c '^MANQUE|' "$T/prop/apres.txt" || true)" 0
  echo "entrées : avant $(grep -c '^[^|]*|sha256' "$T/avant.txt"), après $(grep -c '^[^|]*|sha256' "$T/prop/apres.txt")"
  echo "taille : avant $(du -sm "$P0/racine" | cut -f1) Mo, après $(du -sm "$T/prop/racine" | cut -f1) Mo (liens durs : blobs mesurés séparément)"
  echo "dépôts disparus : $(comm -23 <(find "$P0/racine" -name oci-layout -printf '%P\n' | sed 's#/oci-layout$##' | sort) <(find "$T/prop/racine" -name oci-layout -printf '%P\n' | sed 's#/oci-layout$##' | sort) | paste -sd' ')"
  echo "journal d'audit, décisions de suppression : $(grep -c '"decision":"delete"' "$T/prop/audit.log" || true)"
  grep '"decision":"delete"' "$T/prop/audit.log" | jq -r '[.repository, .reason, .message] | join(" | ")' | sort | uniq -c
  cp "$T/prop/audit.log" "$R/g7-sec-audit-prop.log"

  echo "## à blanc : décisions journalisées, rien de changé"
  attendu "à blanc : entrées modifiées" "$(diff "$T/avant.txt" "$T/blanc/apres.txt" | grep -c '^[<>]' || true)" 0
  echo "décisions de suppression journalisées à blanc : $(grep -c '"decision":"delete"' "$T/blanc/audit.log" || true)"

  echo "## témoin sans règle : le défaut de Zot avec gc: true"
  echo "entrées : $(grep -c '^[^|]*|sha256' "$T/sansregle/apres.txt") (avant $(grep -c '^[^|]*|sha256' "$T/avant.txt")) ; blobs manquants : $(grep -c '^MANQUE|' "$T/sansregle/apres.txt" || true)"
  comm -23 <(grep '|sha256' "$T/avant.txt") <(grep '|sha256' "$T/sansregle/apres.txt") | cut -d'|' -f1 | sed -E 's#^(amont|bench|essais-[a-z0-9]+|plateforme|tekton|workspace|builds/scan|builds/vsa|horodatage|vulndb)(/.*)?$#\1#' | sort | uniq -c
  if grep -q "^builds/sample-app|${IMAGE#*@}|" "$T/sansregle/apres.txt"; then echo "KO   témoin : image réelle conservée sans règle"; ko=1
  else ok "témoin : image réelle sans tag effacée quand aucune règle ne la protège"; fi
  chmod -R u+w "$T"; rm -rf -- "${T:?}"
  return $ko
}

g7_lectures() { # image réelle, signature, attestation, scan, VSA et base lues en anonyme dans le vrai Zot
  local c=$P/ca-poc.crt u=https://$REG_HOTE/v2 d=${IMAGE#*@}
  h() { curl -s --cacert "$c" -o /dev/null -w '%{http_code}' -I -H 'Accept: application/vnd.oci.image.manifest.v1+json' "$u/$1"; }
  attendu "image réelle, sans tag" "$(h "builds/sample-app/manifests/$d")" 200
  attendu "signature .sig" "$(h "builds/sample-app/manifests/sha256-${d#sha256:}.sig")" 200
  attendu "attestation .att" "$(h "builds/sample-app/manifests/sha256-${d#sha256:}.att")" 200
  echo "referrers : $DEPOT_SCAN $(curl -fsS --cacert "$c" "$u/$DEPOT_SCAN/referrers/$d" | jq '.manifests | length'), builds/vsa/sample-app $(curl -fsS --cacert "$c" "$u/builds/vsa/sample-app/referrers/$d" | jq '.manifests | length')"
  echo "tags de vulndb/grype : $(curl -fsS --cacert "$c" "$u/vulndb/grype/tags/list" | jq -r '.tags | sort | join(" ")')"
  echo "dépôts au catalogue : $(curl -fsS --cacert "$c" "$u/_catalog?n=1000" | jq '.repositories | length')"
}

etape_g7_zot() { # ACCORD DU PROPRIÉTAIRE : modifie Zot et le redémarre
  local i a
  echo "## avant"; g7_lectures
  [ -e "$R8/resultats/stockage-zot-avant-g7.log" ] || cp "$R8/resultats/stockage-zot.log" "$R8/resultats/stockage-zot-avant-g7.log"   # le rejeu ciblé réécrit ce journal
  mise run confiance:stockage -- zot
  echo "## après"
  for i in $(seq 60); do curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/" >/dev/null 2>&1 && break; sleep 1; done
  echo "Zot répond après $i s"
  attendu "storage en service = storage de zot.json" "$(sur 'sudo cat /etc/zot/config.json' | jq -cS .storage | sha256sum | cut -c1-16)" "$(jq -cS .storage "$R8/stockage/zot.json" | sha256sum | cut -c1-16)"
  g7_lectures
  echo "## horodatage : deux passages de plus, chaque minute"
  a=$(date -u +%s)
  for i in $(seq 40); do
    [ "$(kubectl get jobs -n horodatage -o json | jq --argjson a "$a" '[.items[] | select((.status.completionTime // "2000-01-01T00:00:00Z" | fromdate) > $a and .status.succeeded == 1)] | length')" -ge 2 ] && break
    sleep 5
  done
  kubectl get jobs -n horodatage --no-headers | tail -3
  [ "$i" -lt 40 ] && ok "horodatage : passages réussis après le redémarrage" || { echo "KO   horodatage : pas de passage réussi après le redémarrage"; ko=1; }
  return $ko
}

etape_g7_balayage() { # premier balayage du vrai Zot, lu dans le journal de zot.service ; rien à effacer, le store a moins de 14 jours
  local de=$(date -ud "$(sed -n '1s/.*, //p' "$R/g7_zot.log")" '+%Y-%m-%d %H:%M:%S') n b=0 i a
  n=$(curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/_catalog?n=1000" | jq '.repositories | length')
  for i in $(seq 360); do
    b=$(sur "sudo journalctl -u zot.service --since '$de' -o cat" | grep -o 'gc successfully completed for [^"]*' | sort -u | wc -l)
    [ "$b" -ge "$n" ] && break
    sleep 10
  done
  attendu "dépôts balayés" "$b" "$n"
  a=$(sur "sudo journalctl -u zot.service --since '$de' -o cat" | grep -c '"decision":"delete"' || true)
  attendu "décisions de suppression" "$a" 0
  sur "sudo journalctl -u zot.service --since '$de' -o cat" | grep '"module":"retention"' | jq -r '[.repository, .decision, .reason] | join(" | ")' | sort | uniq -c | head -20
  g7_lectures
  sur 'df -m --output=used,avail / | tail -1; sudo du -sm /var/lib/zot'
  return $ko
}

etape_g7_retention() { # gcInterval vaut 24 h : en rejeu de zéro, aucun balayage n'a vu vulndb/grype, d'où cette étape à part
  local de
  T=$W/g7-retention
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/g7-retention"' EXIT
  de=$(date -ud "$(sed -n '1s/.*, //p' "$R/g7_zot.log")" +%s)
  echo "## décisions de rétention du vrai Zot, lues par l'auditeur"
  grafana_lignes '{noeud="sc-stockage", source="journal", unite="zot.service"} |= "\"module\":\"retention\"" |= "vulndb/grype"' "$de" "$T/ret.json" "$T/ret.txt"
  grep -q '"decision":"keep"' "$T/ret.txt" && ok "décision de rétention sur vulndb/grype visible dans Grafana ($(wc -l < "$T/ret.txt") ligne(s))" || { echo "KO   rétention absente de Grafana"; ko=1; }
  grafana_lignes '{noeud="sc-stockage", source="audit-zot"} |= "\"decision\":\"delete\""' "$de" "$T/sup.json" "$T/sup.txt"
  attendu "suppressions dans l'audit de Zot" "$(wc -l < "$T/sup.txt")" 0
  if cat "$T/ret.json" "$T/sup.json" | grep -q -F -f "$S8/zot-poc-scan.password"; then echo "KO   mot de passe dans les réponses de Grafana"; ko=1
  else ok "mot de passe de poc-scan absent des réponses de Grafana"; fi
  return $ko
}

etape_g7_periodique() { # ACCORD DU PROPRIÉTAIRE : CronJob dans l'espace scan, un passage lancé depuis lui
  local d=${IMAGE#*@} u=https://$REG_HOTE/v2/$DEPOT_SCAN avant apres etat="" c m couche libre mini=999999
  T=$W/g7-periodique
  rm -rf -- "${T:?}" && mkdir -p "$T"
  rendre_scan "$CRON_SCAN" | kubectl create --dry-run=client -o json -f - | jq --arg h "$HORAIRE_SCAN" '{apiVersion: "batch/v1", kind: "CronJob",
    metadata: {name: .metadata.name, namespace: .metadata.namespace},
    spec: {schedule: $h, timeZone: "Etc/UTC", concurrencyPolicy: "Forbid", startingDeadlineSeconds: 3600, successfulJobsHistoryLimit: 3, failedJobsHistoryLimit: 3,
      jobTemplate: {spec: (.spec | del(.ttlSecondsAfterFinished))}}}' > "$T/cronjob.json"
  if [ "${G7_SEC:-}" = 1 ]; then kubectl apply --dry-run=server -f "$T/cronjob.json"; return 0; fi
  # Hors de 09:00 à 10:00 UTC : deux scans simultanés demanderaient 6,8 Go sur sc-confiance, et compter les referrers n'aurait plus de sens.
  while [ "$(date -u +%H)" = 09 ]; do echo "attente de 10:00 UTC, le passage planifié est à 09:30"; sleep 60; done
  cm_scan
  kubectl apply --server-side -f "$T/cronjob.json"
  attendu "horaire" "$(kubectl get cronjob -n scan "$CRON_SCAN" -o jsonpath='{.spec.schedule} {.spec.timeZone} {.spec.concurrencyPolicy}')" "$HORAIRE_SCAN Etc/UTC Forbid"
  avant=$(curl -fsS --cacert "$P/ca-poc.crt" "$u/referrers/$d" | jq '.manifests | length')
  kubectl create job -n scan g7-manuel --from="cronjob/$CRON_SCAN"
  for _ in $(seq 360); do
    etat=$(kubectl get job -n scan g7-manuel -o jsonpath='{.status.succeeded}/{.status.failed}')
    libre=$(ssh "${SSH_OPTS[@]}" poc@192.168.161.11 "df -m --output=avail / | tail -1" | tr -d ' ')
    [ "$libre" -lt "$mini" ] && mini=$libre
    case $etat in 1/*|*/1) break ;; esac
    sleep 5
  done
  for c in source analyser jetons attester publier revocation; do
    echo "### $c"; kubectl logs -n scan job/g7-manuel -c "$c" 2>&1 | tee "$T/$c.log" | sed 's/^/  /'
  done
  echo "place libre la plus basse sur sc-confiance pendant le job : $mini Mo"
  attendu "job" "${etat%%/*}" 1
  apres=$(curl -fsS --cacert "$P/ca-poc.crt" "$u/referrers/$d" | jq '.manifests | length')
  attendu "referrers de l'image" "$apres" "$((avant + 1))"
  m=$(sed -n 's/^PUBLIE|[^@]*@\(sha256:[0-9a-f]*\),.*/\1/p' "$T/publier.log")
  curl -fsS --cacert "$P/ca-poc.crt" -H 'Accept: application/vnd.oci.image.manifest.v1+json' "$u/manifests/$m" > "$T/manifeste.json"
  attendu "sujet du referrer publié" "$(jq -r .subject.digest "$T/manifeste.json")" "$d"
  couche=$(jq -r '.layers[0].digest' "$T/manifeste.json")
  curl -fsS --cacert "$P/ca-poc.crt" -L "$u/blobs/$couche" > "$T/bundle.json"
  cosign verify-blob-attestation --bundle "$T/bundle.json" --new-bundle-format --key "$R/scanner-cle-publique.pem" --insecure-ignore-tlog \
    --type "$PREDICAT_SCAN" --digest "${d#sha256:}" --digestAlg sha256 > "$T/v.out" 2>&1 \
    && ok "bundle vérifié sur l'hôte : clé du scanner, sujet $d" || { cat "$T/v.out"; echo "KO   bundle non vérifié"; ko=1; }
  jq -r .dsseEnvelope.payload "$T/bundle.json" | base64 -d | jq -c '{scannedAt: .predicate.scannedAt, base: .predicate.scanner.db, vulnerabilites: (.predicate.vulnerabilities | length), kev: ([.predicate.vulnerabilities[] | select(.kev)] | length)}'
  rm -rf -- "${T:?}"
  return $ko
}

etape_g7_grafana() {
  local de i
  T=$W/g7-grafana
  rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
  trap 'rm -rf -- "$W/g7-grafana"' EXIT   # motif tiré du mot de passe de poc-scan supprimé même en cas d'échec
  de=$(date -ud "$(sed -n '1s/.*, //p' "$R/g7_periodique.log")" +%s)
  echo "## journaux du passage, lus par l'auditeur"
  for i in $(seq 30); do
    grafana_lignes '{espace="scan", pod=~"g7-manuel.*"}' "$de" "$T/job.json" "$T/job.txt"
    grep -q '^PUBLIE|' "$T/job.txt" && grep -q 'jeton du rôle scanner révoqué' "$T/job.txt" && break
    sleep 2
  done
  for m in '^SOURCE|' '^BASE|' '^SCAN|' '^ATTESTATION|' '^PUBLIE|' 'jeton du rôle scanner révoqué'; do
    if grep -q "$m" "$T/job.txt"; then ok "visible dans Grafana : $m"; else echo "KO   absent de Grafana : $m"; ko=1; fi
  done
  echo "## audit d'OpenBao et de Zot, lus par l'auditeur"
  grafana_lignes '{espace="openbao"} |= "transit/sign/scanner"' "$de" "$T/bao.json" "$T/bao.txt"
  [ -s "$T/bao.txt" ] && ok "signature du job visible dans Grafana ($(wc -l < "$T/bao.txt") ligne(s))" || { echo "KO   audit d'OpenBao absent de Grafana"; ko=1; }
  grafana_lignes '{noeud="sc-stockage", source="audit-zot"} |= "builds/scan/sample-app" |= "poc-scan"' "$de" "$T/zot.json" "$T/zot.txt"
  grep -q 'manifests' "$T/zot.txt" && ok "poussage par poc-scan visible dans Grafana" || { echo "KO   poussage absent de Grafana"; ko=1; }
  echo "## identifiants de poc-scan absents des réponses"
  { cat "$S8/zot-poc-scan.password"; echo; printf 'poc-scan:%s' "$(cat "$S8/zot-poc-scan.password")" | base64 -w0; echo; } > "$T/motifs"
  if cat "$T/job.json" "$T/bao.json" "$T/zot.json" | grep -q -F -f "$T/motifs"; then echo "KO   identifiants dans les réponses de Grafana"; ko=1
  else ok "ni le mot de passe ni son encodage docker dans les réponses de Grafana"; fi
  kubectl delete job -n scan g7-manuel --wait=false >/dev/null
  return $ko
}

[ $# -ge 1 ] || { sed -n 2,79p "$0"; exit 2; }
mkdir -p "$R" "$W"
for e in "$@"; do
  case $e in
    g0|g1_oras|g1_droits|g1_base|g1_essai|g1_grafana|g2_telecharger|g2_verifier|g2_image|g3_cluster|g3_openbao|g3_essais|g3_cosign|g3_grafana|g4_scan|g4_verifier|g4_grafana|g5_regles|g5_sec|g5_porte|g5_grafana|g6_sec|g6_sec_ns|g6_temoins|g7_sec|g7_zot|g7_balayage|g7_retention|g7_periodique|g7_grafana) ;;
    *) echo "étape inconnue : $e" >&2; exit 2 ;;
  esac
  echo "# plateforme.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$R/$e.log"
  set +e
  ( set -e; "etape_$e" ) 2>&1 | tee -a "$R/$e.log"
  rc=${PIPESTATUS[0]}
  set -e
  echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ), code $rc" | tee -a "$R/$e.log"
  [ "$rc" = 0 ] || exit "$rc"
done
