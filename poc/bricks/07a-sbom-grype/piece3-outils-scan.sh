#!/usr/bin/env bash
# Brique 07b, pose, pièce 3 : image plateforme/outils-scan reconstruite avec le scan-outil du patch de la tranche 3
# (politique/07b-t3.patch, partie outil/ seule), assemblée comme etape_g2_image de plateforme.sh (G2 du 04/11/2026). Écrit le
# 23/11/2026 après la levée par le propriétaire de la règle « rien dans le vrai Zot avant la lecture du n°9 de G7 » (« Oui »).
#   sec    aucune écriture dans le vrai Zot (GET anonymes seulement) : source d'outil/ au commit courant, patch appliqué à une copie ;
#          archives de grype, syft et oras vérifiées ; scan-outil construit deux fois, à cache vide ; couche assemblée deux fois ;
#          registre en mémoire (crane registry serve, 127.0.0.1) : base cosign copiée du vrai Zot, puis
#            témoin : l'ANCIENNE image (outil/ sans patch) réassemblée doit redonner le digest épinglé de G2 (7eb4f26e…), ce qui
#                     valide la méthode ;
#            neuve  : image avec le scan-outil du patch, assemblée deux fois, même digest ; ce digest est celui que pose doit obtenir
#   pose   refuse sans journal sec tenu, de 09:00 à 10:00 et de 11:00 à 11:45 UTC (scans) et si un Job de scan est actif ; pousse la
#          même couche sur le vrai Zot avec poc-ecriture, sous un NOUVEAU tag (TAG_NEUF : l'ancien tag reste sur l'ancien digest) ;
#          relit en anonyme : nouveau tag = digest du sec, ancien tag inchangé ; CronJob de scan non touchés (image et
#          resourceVersion) ; écritures de plateforme/outils-scan relues dans Loki, à travers Grafana (comptes seuls).
#          OUTILS_SCAN_DIGEST de plateforme.sh n'est PAS changé ici : il change avec scanner.sh (reste de la pièce 5), sans quoi un
#          rendu des CronJob mettrait l'ancien scanner.sh sur la nouvelle image (fusion à 5 arguments).
#   pose_releve  (ajout du 23/11/2026, après la pose de 13:01:35 UTC, tuée par l'environnement sur « sleep 20 », code 144, journal
#          vide car la sortie était retenue par sed) : lecture seule, sans attente, des contrôles de la pose : nouveau tag = digest
#          du sec, ancien tag inchangé, CronJob de scan sur l'ancienne image, aucun Job actif, écritures de plateforme/outils-scan
#          depuis 13:01:00 UTC dans Loki à travers Grafana (comptes seuls), dossier de travail sans identifiant
#   pose_releve_2  (ajout du 23/11/2026, après pose_releve, dont deux contrôles étaient faux : empreinte du tar non compressé
#          comparée au digest de la couche compressée ; image lue dans containers[] alors que le scanner tourne en initContainers)
#          lecture seule : dernier diff_id de la config de l'image poussée = couche du sec ; images de tous les conteneurs
#          (initContainers compris) des CronJob de scan : analyser, attester et publier sur l'ancienne image
# Usage (racine du dépôt) : mise exec -- poc/bricks/07a-sbom-grype/piece3-outils-scan.sh sec | pose | pose_releve | pose_releve_2   (journal : resultats/piece3-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=$HOME/.cache/supply-chain-poc
P=$O/08/pki
W=$O/07a
S8=$O/08/secrets
DL=$O/08/telechargements/tsa
DL7=$W/telechargements
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
REG_HOTE=192.168.161.13:5000
PATCH=$here/politique/07b-t3.patch
PATCH_SHA=b5a5e8d85760855c                     # passage 24 du grand banc (254 OK, 0 KO)
ORAS_TGZ_SHA=66fb0ad7206f3f6fa77ed5b552049d364ccf4b50b1684554f731f76302b52ca0
GRYPE_TGZ_SHA=2cb820b6c81f88fd6aff3fb4ca5a7161e9ab70af0f27fc5e99cd16deb987cd5f
SYFT_TGZ_SHA=bc664debb00db1b9b4b9dae4ba1a29d99621e33b641b94b78b9048374b812a3d
COSIGN_BASE=amont/sigstore/cosign/cosign@sha256:c142f6bc0c6d8e5e4a3d31b941200a12502ad90bb5ce93b78c875c868905619d
OUTILS_SCAN=plateforme/outils-scan
TAG_ANCIEN=grype-0.104.1-syft-1.38.0
DIGEST_ANCIEN=sha256:7eb4f26e7148bd9d000fe9609f58ee6e2ba1fd180f38bd7345e029132eb3f83f
TAG_NEUF=grype-0.104.1-syft-1.38.0-vex
e=${1:-}
case $e in sec|pose|pose_releve|pose_releve_2) ;; *) echo "usage : $0 sec | pose | pose_releve | pose_releve_2" >&2; exit 64 ;; esac
L=$R/piece3-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
if [ "$e" = pose ]; then
  grep -qx 'bilan : tenue' "$R/piece3-sec.log" 2>/dev/null || { echo "pose refusée : journal sec absent ou non tenu" >&2; exit 1; }
  hm=$(date -u +%H%M)
  if { [ "$hm" -ge 0900 ] && [ "$hm" -lt 1000 ]; } || { [ "$hm" -ge 1100 ] && [ "$hm" -lt 1145 ]; }; then
    echo "pose refusée de 09:00 à 10:00 et de 11:00 à 11:45 UTC (passages des scans) : aucun journal" >&2; exit 1; fi
fi
T=$W/piece3-$e
ko=0
ok() { echo "OK   $*"; }
attendu() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }
h() { sha256sum | cut -c1-64; }
couche() { # source d'outil/ (dossier), dossier de sortie : construit scan-outil à cache vide et assemble la couche
  local src=$1 out=$2 b
  b=$out/racine/usr/local/bin
  mkdir -p "$b" && chmod 0755 "$out/racine" "$out/racine/usr" "$out/racine/usr/local" "$b"
  tar -xzf "$DL/oras_1.3.6_linux_amd64.tar.gz" -C "$b" oras
  tar -xzf "$DL7/grype_0.104.1_linux_amd64.tar.gz" -C "$b" grype
  tar -xzf "$DL7/syft_1.38.0_linux_amd64.tar.gz" -C "$b" syft
  (cd "$src" && CGO_ENABLED=0 GOCACHE=$out/cache GOFLAGS=-mod=mod go build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o "$b/scan-outil" .)
  rm -rf -- "${out:?}/cache"
  chmod 0755 "$b"/*
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$out/couche.tar" -C "$out/racine" usr
}

if [ "$e" = pose_releve_2 ]; then
{
echo "# piece3-outils-scan.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; dépôt $(git -C "$here" rev-parse --short=8 HEAD)"
DN=$(sed -n 's/^DIGEST_NEUF=//p' "$R/piece3-sec.log")
attendu "nouveau tag relu en anonyme" "$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$OUTILS_SCAN:$TAG_NEUF")" "$DN"
attendu "dernier diff_id de l'image poussée = couche du sec (tar non compressé)" "$(SSL_CERT_FILE=$P/ca-poc.crt crane config "$REG_HOTE/$OUTILS_SCAN@$DN" | jq -r '.rootfs.diff_ids[-1]')" "sha256:$(sed -n 's/^OK   couche neuve, deux assemblages : //p' "$R/piece3-sec.log")"
attendu "autres couches = celles de l'ancienne image (base cosign)" "$(SSL_CERT_FILE=$P/ca-poc.crt crane config "$REG_HOTE/$OUTILS_SCAN@$DN" | jq -c '.rootfs.diff_ids[:-1]')" "$(SSL_CERT_FILE=$P/ca-poc.crt crane config "$REG_HOTE/$OUTILS_SCAN@$DIGEST_ANCIEN" | jq -c '.rootfs.diff_ids[:-1]')"
kubectl get cronjob -n scan -o json | jq -r '.items[] | .metadata.name as $n | .spec.jobTemplate.spec.template.spec | ((.initContainers // [])[], .containers[]) | "  \($n) \(.name) \(.image | sub(".*@"; ""))"'
attendu "conteneurs analyser, attester, publier des CronJob de scan : ancienne image" "$(kubectl get cronjob -n scan -o json | jq -r '[.items[].spec.jobTemplate.spec.template.spec | ((.initContainers // [])[], .containers[]) | select(.name == "analyser" or .name == "attester" or .name == "publier") | .image | sub(".*@"; "")] | "\(length) \(unique | join(","))"')" "6 $DIGEST_ANCIEN"
attendu "aucun conteneur des CronJob sur la nouvelle image" "$(kubectl get cronjob -n scan -o json | jq -r --arg d "$DN" '[.items[].spec.jobTemplate.spec.template.spec | ((.initContainers // [])[], .containers[]) | select(.image | endswith($d))] | length')" 0
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$ko" = 0 ] && echo "bilan : tenue" || echo "bilan : KO"
exit "$ko"
} > "$L" 2>&1
k=$?; sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' -i "$L"; cat "$L"; exit "$k"
fi
if [ "$e" = pose_releve ]; then
{
echo "# piece3-outils-scan.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; dépôt $(git -C "$here" rev-parse --short=8 HEAD)"
DN=$(sed -n 's/^DIGEST_NEUF=//p' "$R/piece3-sec.log")
echo "digest attendu (journal sec) : $DN"
echo "journal de la pose : $(stat -c '%s octets, modifié %y' "$R/piece3-pose.log")"
attendu "nouveau tag relu en anonyme" "$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$OUTILS_SCAN:$TAG_NEUF")" "$DN"
attendu "ancien tag inchangé (anonyme)" "$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$OUTILS_SCAN:$TAG_ANCIEN")" "$DIGEST_ANCIEN"
echo "tags : $(SSL_CERT_FILE=$P/ca-poc.crt crane ls "$REG_HOTE/$OUTILS_SCAN" | paste -sd' ')"
attendu "couche de l'image poussée = couche du sec (dernière couche)" "$(SSL_CERT_FILE=$P/ca-poc.crt crane manifest "$REG_HOTE/$OUTILS_SCAN@$DN" | jq -r '.layers[-1].digest')" "sha256:$(sed -n 's/^OK   couche neuve, deux assemblages : //p' "$R/piece3-sec.log")"
kubectl get cronjob -n scan -o json | jq -r '.items[] | "CronJob \(.metadata.name) : resourceVersion \(.metadata.resourceVersion), image \(.spec.jobTemplate.spec.template.spec.containers[0].image | sub(".*@"; ""))"'
attendu "CronJob de scan sur l'ancienne image" "$(kubectl get cronjob -n scan -o json | jq -r '[.items[].spec.jobTemplate.spec.template.spec.containers[].image | sub(".*@"; "")] | unique | join(",")')" "$DIGEST_ANCIEN"
attendu "Jobs de scan actifs" "$(kubectl get jobs -n scan -o json | jq '[.items[] | select((.status.active // 0) > 0)] | length')" 0
attendu "dossier de travail de la pose sans identifiant (docker/)" "$(find "$W/piece3-pose" -name config.json | wc -l)" 0
q() { printf 'user = "auditeur:%s"\n' "$(cat "$O/08/secrets/grafana-auditeur.password")" \
  | curl -sS -K - --cacert "$P/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query \
    -d "$(jq -nc --arg q "$1" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')" \
  | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end'; }
r=$(( $(date -u +%s) - $(date -ud 2026-11-23T13:01:00Z +%s) ))
Z='{noeud="sc-stockage", source="journal", unite="zot.service"} |= "plateforme/outils-scan"'
echo "Loki, zot.service, plateforme/outils-scan depuis 13:01:00 UTC (${r} s) : $(q "sum(count_over_time($Z [${r}s]))")"
for m in PUT POST PATCH HEAD GET; do echo "  méthode $m : $(q "sum(count_over_time($Z |= \"\\\"method\\\":\\\"$m\\\"\" [${r}s]))")"; done
n=$(q "sum(count_over_time($Z |= \"\\\"method\\\":\\\"PUT\\\"\" [${r}s]))")
case $n in aucune|0) echo "KO   aucune écriture de plateforme/outils-scan dans Grafana (Loki)"; ko=1 ;; *) ok "écritures (PUT) de plateforme/outils-scan visibles dans Grafana (Loki) : $n" ;; esac
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$ko" = 0 ] && echo "bilan : tenue" || echo "bilan : KO"
exit "$ko"
} > "$L" 2>&1
k=$?; sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' -i "$L"; cat "$L"; exit "$k"
fi
{
echo "# piece3-outils-scan.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; dépôt $(git -C "$here" rev-parse --short=8 HEAD)"
rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T")
trap 'kill "${srv:-0}" 2>/dev/null || true; rm -rf -- "$T"' EXIT
attendu "empreinte du patch (passage 24 du banc)" "$(h < "$PATCH" | cut -c1-16)" "$PATCH_SHA"
if (cd "$DL" && echo "$ORAS_TGZ_SHA  oras_1.3.6_linux_amd64.tar.gz" | sha256sum -c --quiet); then ok "archive d'oras 1.3.6"; else echo "KO   archive d'oras"; ko=1; fi
if (cd "$DL7" && echo "$GRYPE_TGZ_SHA  grype_0.104.1_linux_amd64.tar.gz" | sha256sum -c --quiet && echo "$SYFT_TGZ_SHA  syft_1.38.0_linux_amd64.tar.gz" | sha256sum -c --quiet); then
  ok "archives de grype 0.104.1 et syft 1.38.0"; else echo "KO   archives de grype ou de syft"; ko=1; fi
echo "go : $(go version)"
# Sources : outil/ du commit courant (git archive), ancienne et neuve (patch, partie outil/ seule).
RACINE=$(git -C "$here" rev-parse --show-toplevel)
D=poc/bricks/07a-sbom-grype/outil
for v in ancienne neuve; do
  mkdir -p "$T/src-$v" && git -C "$RACINE" archive HEAD "$D" | tar -x -C "$T/src-$v"
done
if [ -z "$(git -C "$RACINE" status --porcelain -- "$D")" ]; then ok "outil/ sans modification locale"; else echo "KO   outil/ modifié localement"; ko=1; fi
(cd "$T/src-neuve" && git apply -p1 --include="$D/*" "$PATCH")
echo "fichiers changés par le patch dans outil/ : $(diff -rq "$T/src-ancienne/$D" "$T/src-neuve/$D" | wc -l)"
case $e in
  sec)
    for v in ancienne neuve; do for n in 1 2; do couche "$T/src-$v/$D" "$T/$v-$n"; done
      attendu "scan-outil $v, deux constructions" "$(h < "$T/$v-2/racine/usr/local/bin/scan-outil")" "$(h < "$T/$v-1/racine/usr/local/bin/scan-outil")"
      attendu "couche $v, deux assemblages" "$(h < "$T/$v-2/couche.tar")" "$(h < "$T/$v-1/couche.tar")"
      echo "  scan-outil $v : $(h < "$T/$v-1/racine/usr/local/bin/scan-outil") ; couche : $(h < "$T/$v-1/couche.tar"), $(stat -c %s "$T/$v-1/couche.tar") octets"
    done
    u=$("$T/neuve-1/racine/usr/local/bin/scan-outil" 2>&1 || true)
    case $u in *"| vex <sha256>"*) ok "usage du scan-outil neuf : mode vex présent" ;; *) echo "KO   usage du scan-outil neuf : $u"; ko=1 ;; esac
    attendu "grype de la couche = grype de mise" "$(h < "$T/neuve-1/racine/usr/local/bin/grype")" "$(h < "$(type -P grype)")"
    attendu "syft de la couche = syft de mise" "$(h < "$T/neuve-1/racine/usr/local/bin/syft")" "$(h < "$(type -P syft)")"
    port=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    crane registry serve --address "127.0.0.1:$port" > "$T/registre.out" 2>&1 & srv=$!
    for i in $(seq 1 50); do curl -fs "http://127.0.0.1:$port/v2/" > /dev/null 2>&1 && break; sleep 0.1; done
    LOC=127.0.0.1:$port
    SSL_CERT_FILE=$P/ca-poc.crt crane copy "$REG_HOTE/$COSIGN_BASE" "$LOC/${COSIGN_BASE%@*}" 2>/dev/null
    attendu "base copiée (digest)" "$(crane digest "$LOC/$COSIGN_BASE")" "${COSIGN_BASE#*@}"
    dt=$(crane append -b "$LOC/$COSIGN_BASE" -f "$T/ancienne-1/couche.tar" -t "$LOC/$OUTILS_SCAN:temoin" 2>/dev/null)
    attendu "témoin : ancienne image réassemblée = digest épinglé de G2" "${dt##*@}" "$DIGEST_ANCIEN"
    d1=$(crane append -b "$LOC/$COSIGN_BASE" -f "$T/neuve-1/couche.tar" -t "$LOC/$OUTILS_SCAN:neuve-1" 2>/dev/null)
    d2=$(crane append -b "$LOC/$COSIGN_BASE" -f "$T/neuve-2/couche.tar" -t "$LOC/$OUTILS_SCAN:neuve-2" 2>/dev/null)
    attendu "image neuve, deux assemblages (même digest)" "${d2##*@}" "${d1##*@}"
    echo "DIGEST_NEUF=${d1##*@}"
    attendu "image neuve différente de l'ancienne" "$([ "${d1##*@}" != "$DIGEST_ANCIEN" ] && echo oui)" oui
    attendu "vrai Zot : ancien tag sur le digest épinglé (lecture anonyme)" "$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$OUTILS_SCAN:$TAG_ANCIEN")" "$DIGEST_ANCIEN"
    attendu "vrai Zot : nouveau tag absent" "$(SSL_CERT_FILE=$P/ca-poc.crt crane ls "$REG_HOTE/$OUTILS_SCAN" | grep -cx "$TAG_NEUF" || true)" 0 ;;
  pose)
    DN=$(sed -n 's/^DIGEST_NEUF=//p' "$R/piece3-sec.log")
    echo "digest attendu (journal sec) : $DN"
    attendu "Jobs de scan actifs" "$(kubectl get jobs -n scan -o json | jq '[.items[] | select((.status.active // 0) > 0)] | length')" 0
    cr0=$(kubectl get cronjob -n scan -o json | jq -r '[.items[] | "\(.metadata.name) \(.metadata.resourceVersion) \(.spec.jobTemplate.spec.template.spec.containers[0].image | sub(".*@"; ""))"] | join(", ")')
    echo "CronJob avant : $cr0"
    couche "$T/src-neuve/$D" "$T/neuve"
    echo "couche : $(h < "$T/neuve/couche.tar")"
    test -s "$S8/zot-poc-ecriture.password" && ok "mot de passe de poc-ecriture présent (non lu ici)"
    (umask 077 && mkdir -p "$T/docker" && printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG_HOTE" \
      "$(printf 'poc-ecriture:%s' "$(cat "$S8/zot-poc-ecriture.password")" | base64 -w0)" > "$T/docker/config.json")
    t0=$(date -u +%s); echo "poussée : $(date -u +%FT%TZ)"
    d=$(DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt crane append -b "$REG_HOTE/$COSIGN_BASE" -f "$T/neuve/couche.tar" -t "$REG_HOTE/$OUTILS_SCAN:$TAG_NEUF" 2>/dev/null)
    rm -rf -- "${T:?}/docker"
    attendu "digest poussé = digest du sec" "${d##*@}" "$DN"
    attendu "nouveau tag relu en anonyme" "$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$OUTILS_SCAN:$TAG_NEUF")" "$DN"
    attendu "ancien tag inchangé (anonyme)" "$(SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$OUTILS_SCAN:$TAG_ANCIEN")" "$DIGEST_ANCIEN"
    attendu "CronJob de scan non touchés (resourceVersion, image)" "$(kubectl get cronjob -n scan -o json | jq -r '[.items[] | "\(.metadata.name) \(.metadata.resourceVersion) \(.spec.jobTemplate.spec.template.spec.containers[0].image | sub(".*@"; ""))"] | join(", ")')" "$cr0"
    sleep 20
    q() { printf 'user = "auditeur:%s"\n' "$(cat "$O/08/secrets/grafana-auditeur.password")" \
      | curl -sS -K - --cacert "$P/ca-poc.crt" -H 'Content-Type: application/json' -X POST https://192.168.161.13:3001/api/ds/query \
        -d "$(jq -nc --arg q "$1" --arg t "$(date -u +%s)000" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')" \
      | jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | .data.values[1][0]] | if length == 0 then "aucune" else join(",") end'; }
    r=$(( $(date -u +%s) - t0 + 60 ))
    Z='{noeud="sc-stockage", source="journal", unite="zot.service"} |= "plateforme/outils-scan"'
    echo "Loki, zot.service, plateforme/outils-scan depuis la poussée (${r} s) : $(q "sum(count_over_time($Z [${r}s]))")"
    n=$(q "sum(count_over_time($Z |= \"\\\"method\\\":\\\"PUT\\\"\" [${r}s]))")
    echo "  dont PUT : $n"
    case $n in aucune|0) echo "KO   aucune écriture de plateforme/outils-scan dans Grafana (Loki)"; ko=1 ;; *) ok "écritures de plateforme/outils-scan visibles dans Grafana (Loki) : $n" ;; esac ;;
esac
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$ko" = 0 ] && echo "bilan : tenue" || echo "bilan : KO"
exit "$ko"
} 2>&1 | sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' | tee "$L"
exit "${PIPESTATUS[0]}"
