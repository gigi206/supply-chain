#!/usr/bin/env bash
# Brique 07a, G7, point 4 (resultats/g7-replanification.md, note du 20/11/2026 sur le point 4) : état de Zot lu en anonyme, par
# HTTPS, AVANT les premières suppressions réelles (balayages n°8 et n°9), puis APRÈS, pour les comparer digest par digest.
# Lecture seule : uniquement des GET et des HEAD anonymes sur l'API de Zot ; ni ssh, ni sudo, ni Grafana, ni cluster.
# Aucun fichier temporaire. Toute ligne au motif jeton|token est masquée avant l'écriture du journal.
# Usage (racine du dépôt) :
#   MOMENT=avant mise exec -- poc/bricks/07a-sbom-grype/g7-etat.sh     -> resultats/g7-etat-avant<SUFFIXE>.log
#   MOMENT=apres AVANT=resultats/g7-etat-avant.log mise exec -- poc/bricks/07a-sbom-grype/g7-etat.sh
#     -> resultats/g7-etat-apres<SUFFIXE>.log ; relit en plus chaque digest listé dans le journal AVANT (tags de vulndb/grype,
#        referrers) et donne son code HTTP, pour voir ce qui a disparu.
# Un journal présent n'est jamais réécrit : SUFFIXE=-2 pour une relance.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"   # P
MOMENT=${MOMENT:?MOMENT=avant|apres}
case $MOMENT in avant|apres) ;; *) echo "MOMENT=avant|apres" >&2; exit 2 ;; esac
SUFFIXE=${SUFFIXE:-}
LOG=$here/resultats/g7-etat-$MOMENT$SUFFIXE.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
if [ "$MOMENT" = apres ]; then
  AVANT=${AVANT:?AVANT=chemin du journal avant, relatif à la brique}
  [ -s "$here/$AVANT" ] || { echo "journal avant absent ou vide : $here/$AVANT" >&2; exit 2; }
fi
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'
U=https://192.168.161.13:5000/v2
IMAGE=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # builds/sample-app, sujet du CronJob scan-sample-app
DEB1=sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e    # deb 1.0.0-1, sujet du premier scan du deb (14/11)
DEB2=sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e    # deb 1.0.0-2, sujet du CronJob scan-sample-app-deb
VIDE=sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a    # {} (application/vnd.oci.empty.v1+json), H7
ACC='Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json'

get() { curl -sS --cacert "$P/ca-poc.crt" "$U/$1"; }
code() { curl -sS -o /dev/null -w '%{http_code}' -I --cacert "$P/ca-poc.crt" -H "$ACC" "$U/$1" || echo "échec"; }
digest_de() { # dépôt tag : digest du manifeste (en-tête Docker-Content-Digest du HEAD)
  curl -sS -I --cacert "$P/ca-poc.crt" -H "$ACC" "$U/$1/manifests/$2" | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}'
}
referrers() { # dépôt-des-referrers dépôt-du-sujet sujet : une ligne REF par referrer (digest, date de création annotée, type)
  local n
  n=$(get "$1/referrers/$3" | jq -r --arg r "$1" --arg s "${3:7:12}" \
    '.manifests // [] | (map("REF|\($r)|\(.digest)|\(.annotations["org.opencontainers.image.created"] // "-")|\(.artifactType // "-")|sujet \($s)") | .[]), "COMPTE|\($r)|sujet \($s)|\(length)"')
  echo "$n"
}

{
  echo "# g7-etat.sh $MOMENT, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16)"
  echo "# lecture seule, anonyme, API de Zot ($U) ; ni ssh, ni sudo, ni Grafana"
  echo "## 1. image réelle et deb, avec .sig et .att (HEAD, 200 attendu)"
  for x in "builds/sample-app $IMAGE" "builds/sample-app-deb $DEB1" "builds/sample-app-deb $DEB2"; do
    set -- $x
    echo "MANIFESTE|$1@${2:0:19}|$(code "$1/manifests/$2")"
    for e in sig att; do echo "TAG|$1:sha256-${2:7:12}….$e|$(code "$1/manifests/sha256-${2:7}.$e")"; done
  done
  echo "## 2. referrers des sujets réels (scans et VSA)"
  referrers builds/scan/sample-app builds/sample-app "$IMAGE"
  referrers builds/scan/sample-app-deb builds/sample-app-deb "$DEB1"
  referrers builds/scan/sample-app-deb builds/sample-app-deb "$DEB2"
  referrers builds/vsa/sample-app builds/sample-app "$IMAGE"
  referrers builds/vsa/sample-app-deb builds/sample-app-deb "$DEB1"
  referrers builds/vsa/sample-app-deb builds/sample-app-deb "$DEB2"
  echo "## 3. témoins de G6 : referrers dans builds/scan/essai-scan, par image de builds/essai-scan"
  t=0
  for g in $(get builds/essai-scan/tags/list | jq -r '.tags // [] | .[]'); do
    d=$(digest_de builds/essai-scan "$g")
    n=$(get "builds/scan/essai-scan/referrers/$d" | jq '.manifests // [] | length')
    echo "TEMOIN|$g|${d:0:19}|$n"
    get "builds/scan/essai-scan/referrers/$d" | jq -r '.manifests // [] | .[] | "REF|builds/scan/essai-scan|\(.digest)|\(.annotations["org.opencontainers.image.created"] // "-")|\(.artifactType // "-")|témoin"'
    t=$((t + n))
  done
  echo "COMPTE|builds/scan/essai-scan|tous les témoins|$t"
  echo "## 4. vulndb/grype : tags et digests"
  for g in $(get vulndb/grype/tags/list | jq -r '.tags // [] | .[]'); do echo "BASE|$g|$(digest_de vulndb/grype "$g")"; done
  echo "COMPTE|vulndb/grype|tags|$(get vulndb/grype/tags/list | jq '.tags // [] | length')"
  echo "## 5. blob vide {} (H7, HEAD, 200 attendu)"
  for r in builds/vsa/sample-app builds/vsa/sample-app-deb builds/scan/sample-app; do echo "BLOB|$r|${VIDE:0:19}|$(code "$r/blobs/$VIDE")"; done
  if [ "$MOMENT" = apres ]; then
    echo "## 6. digests du journal avant ($AVANT), relus un par un (200 : présent ; 404 : supprimé)"
    grep -E '^(REF|BASE)\|' "$here/$AVANT" | while IFS='|' read -r k a b _; do
      if [ "$k" = BASE ]; then echo "RELU|vulndb/grype|$a|$(code "vulndb/grype/manifests/$b")"; else echo "RELU|$a|$b|$(code "$a/manifests/$b")"; fi
    done
  fi
  echo "## fin, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} 2>&1 | sed -u "s#$HOME#~#g" | sed -u "$MASQUE" | tee "$LOG"
exit "${PIPESTATUS[0]}"
