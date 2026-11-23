#!/usr/bin/env bash
# Brique 07b, tranche 3, pièce 8 de la pose : juger, signer et publier un VEX (OpenVEX v0.2.0) écrit à la main par le propriétaire,
# en referrer du digest dans builds/vex/<nom>, comme publier de scanner.sh. Écrit à sec le 21/11/2026, non posé : la clé Transit
# hashivault://vex (pièce 2) et le compte d'écriture de builds/vex/** (pièce 4) n'existent pas encore.
# Le jugement est celui du scanner : scan-outil vex (le même code que l'image outils-scan) sur l'énoncé in-toto qui sera signé.
# Refus AVANT signature (code 1, ligne REFUS|… sur la sortie d'erreur) :
#   - document illisible, @context autre que OpenVEX v0.2.0, aucun énoncé ;
#   - statut fixed (retiré des statuts acceptés, choix 5) ; document qui mêle not_affected et d'autres statuts ;
#   - exemption (not_affected) : document que scan-outil vex rejette (justification, impact_statement…) ou énoncé non exemptant ;
#   - rétractation : statuts affected ou under_investigation seulement ; affected sans action_statement (MUST dans la description
#     du champ, OpenVEX v0.2.0, alors que la colonne « Required » le dit facultatif : lecture stricte, comme pour not_affected) ;
#   - énoncé sans nom de vulnérabilité, ou sans produit dont l'@id cite le digest ;
#   - horodatage illisible, ou postérieur à l'heure de la commande (un document daté du futur gagne tous les classements, et le
#     registre est en ajout seul : seul un retrait sur accord le répare) ;
#   - aucun scan signé vérifié pour le digest (passage 14 : le prédicat de scan est lu et vérifié ici, plus fourni par l'appelant) ;
#   - sous-composant qui n'est pas exactement le PURL d'une entrée du prédicat de scan ;
#   - énoncé dont aucun nom ne croise l'id ou un alias d'une entrée du prédicat de scan (passage 12 : une rétractation mal nommée
#     ne rétracterait rien) ; sous-composant d'une exemption qui n'est le paquet d'aucune entrée portant ce nom.
# Avis, sans refus (passage 16, limite 3 de l'inventaire) : les VEX déjà publiés sur le digest (builds/vex/<nom>, vérifiés par
#   CLE_PUBLIQUE, comme lire_vex de scanner.sh) sont lus et passés à scan-outil vex ; ligne PUBLIES| toujours écrite (nombre d'énoncés
#   publiés vérifiés, code de cosign). Un énoncé publié concurrent nomme une entrée du scan qui porte un nom de l'énoncé neuf (id ou
#   alias). Horodatages comparés à la nanoseconde.
#   - AVIS|renouvellement : exemption pas plus récente qu'un énoncé publié concurrent (recevable ou non, tout statut) ;
#   - AVIS|rétractation : rétractation dans le même cas, qui peut ne rien rétracter ;
#   - AVIS|âge : exemption dont l'échéance (horodatage + VEX_AGE_MAX_JOURS, 30 par défaut, comme vex_age_max_jours de la politique)
#     est passée ou à moins d'un jour (un VEX ne compte qu'au scan quotidien suivant) ; ECHEANCE| pour chaque énoncé d'exemption.
#   La couverture par paquet n'est pas comparée : l'avis peut avertir à tort.
# Après signature, et avant publication : signature vérifiée par la clé publique, contenu signé (payload DSSE) rejugé de même.
# Usage : signer-vex.sh verifier|signer <document.json> <hôte/dépôt@sha256:…>
#   Prédicat de scan : le plus récent (scannedAt) des scans attestés sur le digest dans <hôte>/builds/scan/<nom>, vérifiés par
#   cosign verify-attestation avec CLE_SCANNER (clé publique du scanner), comme lire_vex de scanner.sh pour les VEX.
#   Les deux modes lisent : CA (certificat du registre), CLE_SCANNER, CLE_PUBLIQUE (clé publique VEX, pour les VEX publiés) ;
#   SCAN_OUTIL (scan-outil par défaut), VEX_AGE_MAX_JOURS (30 par défaut).
#   signer lit en plus : CLE (hashivault://vex par défaut ; VAULT_ADDR et VAULT_TOKEN à la charge de l'appelant),
#   CONFIG_REGISTRE (fichier d'authentification d'oras).
set -euo pipefail
export LC_ALL=C
usage() { echo "usage : signer-vex.sh verifier|signer <document.json> <hôte/dépôt@sha256:…>" >&2; exit 2; }
[ $# = 3 ] || usage
MODE=$1 IMAGE=$3
case $MODE in verifier | signer) ;; *) usage ;; esac
[ -f "$2" ] || { echo "document introuvable" >&2; exit 2; }
printf '%s' "$IMAGE" | grep -qE '^[^@/]+/[^@]+@sha256:[0-9a-f]{64}$' || { echo "image attendue : hôte/dépôt@sha256:<64 hexadécimaux>" >&2; exit 2; }
DOC=$(realpath -- "$2")
CA=$(realpath -- "${CA:?CA : certificat du registre}")
CLE_SCANNER=$(realpath -- "${CLE_SCANNER:?CLE_SCANNER : clé publique du scanner}")
CLE_PUBLIQUE=$(realpath -- "${CLE_PUBLIQUE:?CLE_PUBLIQUE : clé publique VEX}")
VEX_AGE_MAX_JOURS=${VEX_AGE_MAX_JOURS:-30}
printf '%s' "$VEX_AGE_MAX_JOURS" | grep -qE '^[0-9]+$' || { echo "VEX_AGE_MAX_JOURS : entier attendu" >&2; exit 2; }
OPENVEX=https://openvex.dev/ns/v0.2.0
SCAN_OUTIL=${SCAN_OUTIL:-scan-outil}
hex=${IMAGE##*@sha256:} r=${IMAGE%@sha256:*}
n=${r#*/} nom=${r##*/}
depot_vex=${r%%/*}/builds/vex/${n#builds/} depot_scan=${r%%/*}/builds/scan/${n#builds/}
maintenant=$(date -u +%s)
heure=$(date -u -d "@$maintenant" +%Y-%m-%dT%H:%M:%SZ)
w=$(mktemp -d)
trap 'find "$w" -delete' EXIT
refus() { echo "REFUS|$1" >&2; exit 1; }

jq -e . "$DOC" > /dev/null 2>&1 || refus "document illisible (JSON)"
jq -e --arg c "$OPENVEX" '."@context" == $c' "$DOC" > /dev/null || refus "@context autre que $OPENVEX"
ne=$(jq '.statements | if type == "array" then length else 0 end' "$DOC")
[ "$ne" -gt 0 ] || refus "aucun énoncé"
statuts=$(jq -r '[.statements[].status // "-"] | unique | join(",")' "$DOC")
case ",$statuts," in *,fixed,*) refus "statut fixed : retiré des statuts acceptés (choix 5)" ;; esac
if jq -e 'any(.statements[]; .status == "not_affected")' "$DOC" > /dev/null; then
  [ "$statuts" = not_affected ] || refus "not_affected mêlé à d'autres statuts ($statuts) : un document par intention"
  nature=exemption
else
  jq -e 'all(.statements[]; .status == "affected" or .status == "under_investigation")' "$DOC" > /dev/null \
    || refus "statuts hors not_affected, affected et under_investigation : $statuts"
  nature=retractation
fi
jq -e 'all(.statements[] | select(.status == "affected"); (.action_statement // "" | tostring | gsub("\\s"; "")) != "")' "$DOC" > /dev/null \
  || refus "affected sans action_statement (MUST de la description du champ, OpenVEX v0.2.0)"
jq -e 'all(.statements[]; [.vulnerability."@id"?, .vulnerability.name?, (.vulnerability.aliases? // [])[]] | map(select(type == "string" and . != "")) | length > 0)' \
  "$DOC" > /dev/null || refus "énoncé sans nom de vulnérabilité (@id, name ou aliases)"
jq -e --arg h "$hex" 'all(.statements[]; [(.products // [])[] | (."@id" // "") | contains($h)] | any)' "$DOC" > /dev/null \
  || refus "énoncé sans produit dont l'@id cite le digest $hex"
# prédicat de scan : le plus récent des scans vérifiés par CLE_SCANNER, sujet égal au digest
COSIGN_REPOSITORY=$depot_scan cosign verify-attestation --key "$CLE_SCANNER" --insecure-ignore-tlog --type https://supply-chain.example/scan/v1 \
  --registry-cacert "$CA" "$IMAGE" > "$w/scans" 2> "$w/scans.err" || true
grep '^{' "$w/scans" > "$w/lignes" || true
i=0 nv=0 tmax=-1 meilleur=
while IFS= read -r l; do
  if printf '%s' "$l" | jq -r .payload | base64 -d > "$w/s-$i.json" 2> /dev/null \
    && jq -e --arg h "$hex" '.predicateType == "https://supply-chain.example/scan/v1" and any(.subject[]; .digest.sha256 == $h)' "$w/s-$i.json" > /dev/null 2>&1; then
    nv=$((nv + 1))
    t=$(date -u -d "$(jq -r .predicate.scannedAt "$w/s-$i.json")" +%s 2> /dev/null || echo -1)
    if [ "$t" -gt "$tmax" ]; then tmax=$t meilleur=$w/s-$i.json; fi
  fi
  i=$((i + 1))
done < "$w/lignes"
[ -n "$meilleur" ] || refus "aucun scan signé vérifié (clé CLE_SCANNER, $depot_scan, sujet sha256:$hex)"
SCAN=$w/scan.json
jq .predicate "$meilleur" > "$SCAN"
scanne=$(jq -r .scannedAt "$SCAN")
jq -r '[.vulnerabilities[]?.package // empty] | unique | .[]' "$SCAN" > "$w/purls"
[ -s "$w/purls" ] || refus "prédicat de scan sans entrée (vulnerabilities[].package)"
absents=$(jq -r --rawfile p "$w/purls" '([.statements[] | (.products // [])[] | (.subcomponents // [])[] | (."@id" // "")] | unique)
  - ($p | split("\n")) | join(" ")' "$DOC")
[ -z "$absents" ] || refus "sous-composant absent des entrées du prédicat de scan (égalité exacte) : $absents"
inconnus=$(jq -r --slurpfile sc "$SCAN" '[$sc[0].vulnerabilities[]? | .id, (.aliases // [])[]] as $s
  | [.statements | to_entries[] | select([.value.vulnerability."@id"?, .value.vulnerability.name?, (.value.vulnerability.aliases? // [])[]]
    | map(select(type == "string" and . != "")) | any(.[]; . as $x | $s | any(. == $x)) | not) | .key | tostring] | join(",")' "$DOC")
[ -z "$inconnus" ] || refus "énoncé dont aucun nom ne croise une entrée du prédicat de scan (id ou alias) : énoncé(s) $inconnus"
couples=$(jq -r --slurpfile sc "$SCAN" --arg h "$hex" '[$sc[0].vulnerabilities[]? | {p: .package, n: ([.id] + (.aliases // []))}] as $e
  | [.statements[] | select(.status == "not_affected")
    | ([.vulnerability."@id"?, .vulnerability.name?, (.vulnerability.aliases? // [])[]] | map(select(type == "string" and . != ""))) as $noms
    | (.products // [])[] | select((."@id" // "") | contains($h)) | (.subcomponents // [])[] | (."@id" // "") as $p
    | select([$e[] | select(.p == $p and any(.n[]; . as $x | $noms | any(. == $x)))] | length == 0) | $p] | unique | join(" ")' "$DOC")
[ -z "$couples" ] || refus "sous-composant sans entrée de cette vulnérabilité dans le prédicat de scan : $couples"
larges=$(jq --arg h "$hex" '[.statements[] | select(any((.products // [])[]; (."@id" // "" | contains($h)) and ((.subcomponents // []) | length == 0)))] | length' "$DOC")

mkdir "$w/vex"
juger() { # énoncé in-toto : verdict de scan-outil vex, sinon refus
  "$SCAN_OUTIL" vex "$hex" "$w/vex" "$1" > "$w/verdict.json" || refus "scan-outil vex en erreur"
  [ "$(jq '.enonces // [] | length' "$w/verdict.json")" = "$ne" ] \
    || refus "énoncés non classables par scan-outil vex (horodatage illisible ou nom absent) : $(jq '.enonces // [] | length' "$w/verdict.json")/$ne"
  if [ "$nature" = exemption ]; then
    [ "$(jq '.retenus | length' "$w/verdict.json")" = 1 ] || refus "rejeté par scan-outil vex : $(jq -r '.rejetes[0].raison // "?"' "$w/verdict.json")"
    jq -e 'all(.enonces[]; .exemptant)' "$w/verdict.json" > /dev/null || refus "énoncé non exemptant selon scan-outil vex"
  fi
  local h
  for h in $(jq -r '.enonces[].horodatage' "$w/verdict.json"); do
    [ "$(date -u -d "$h" +%s)" -le "$maintenant" ] || refus "horodatage $h postérieur à l'heure de la commande ($heure)"
  done
}
jq -n --arg n "$nom" --arg h "$hex" --arg t "$OPENVEX" --slurpfile d "$DOC" \
  '{_type: "https://in-toto.io/Statement/v1", subject: [{name: $n, digest: {sha256: $h}}], predicateType: $t, predicate: $d[0]}' > "$w/enonce.json"
juger "$w/enonce.json"
echo "JUGE|$nature, $ne énoncé(s) dont $larges large(s), document sha256 $(sha256sum < "$DOC" | cut -c1-64), sujet sha256:$hex, VEX vers $depot_vex, $heure ; scan du $scanne ($nv scan(s) vérifié(s))"

# avis de renouvellement (passage 16) : une fois, avant toute signature ; aucun refus
ns() { date -u -d "$1" +%s%N; }
mkdir "$w/pub" "$w/pubvex"
cp=0
COSIGN_REPOSITORY=$depot_vex cosign verify-attestation --key "$CLE_PUBLIQUE" --insecure-ignore-tlog --type "$OPENVEX" \
  --registry-cacert "$CA" "$IMAGE" > "$w/pub/verifiees" 2> "$w/pub/erreur" || cp=$?
grep '^{' "$w/pub/verifiees" > "$w/pub/lignes" || true
pub=() i=0
while IFS= read -r l; do
  if printf '%s' "$l" | jq -r .payload | base64 -d > "$w/pub/enonce-$i.json" 2> /dev/null && [ -s "$w/pub/enonce-$i.json" ]; then
    pub+=("$w/pub/enonce-$i.json")
  fi
  i=$((i + 1))
done < "$w/pub/lignes"
"$SCAN_OUTIL" vex "$hex" "$w/pubvex" ${pub[@]+"${pub[@]}"} > "$w/publies.json" || refus "scan-outil vex en erreur sur les VEX publiés"
e=$(sed -n 's/^Error: //p' "$w/pub/erreur" | head -1 | cut -c1-200 | tr '|' ' ')
echo "PUBLIES|$(jq '.enonces // [] | length' "$w/publies.json") énoncé(s) publié(s) vérifié(s) dans $depot_vex (CLE_PUBLIQUE), cosign code $cp${e:+ : $e}"
jour=86400000000000 now=$((maintenant * 1000000000)) duree=$((VEX_AGE_MAX_JOURS * 86400000000000))
while IFS= read -r x; do
  k=$(jq -r .key <<< "$x") st=$(jq -r .value.statut <<< "$x") hs=$(jq -r .value.horodatage <<< "$x") noms=$(jq -c .value.noms <<< "$x")
  ts=$(ns "$hs")
  etendus=$(jq -c --argjson n "$noms" '[.vulnerabilities[]? | [.id] + (.aliases // []) | select(any(.[]; . as $y | $n | any(. == $y)))]
    | add // [] | . + $n | unique' "$SCAN")
  tc=-1 hc='' sc=''
  while read -r h2 s2; do
    t2=$(ns "$h2")
    if [ "$t2" -gt "$tc" ]; then tc=$t2 hc=$h2 sc=$s2; fi
  done < <(jq -r --argjson x "$etendus" '.enonces[]? | select(any(.noms[]; . as $y | $x | any(. == $y))) | "\(.horodatage) \(.statut)"' "$w/publies.json")
  ici="énoncé $k ($(jq -r 'join(",")' <<< "$noms")) du $hs"
  if [ "$tc" -ge "$ts" ]; then
    if [ "$st" = not_affected ]; then
      echo "AVIS|renouvellement : $ici : énoncé publié du $hc ($sc) au moins aussi récent sur une entrée du scan de même nom ; ce document peut ne pas renouveler l'exemption (couverture par paquet non comparée)"
    else
      echo "AVIS|rétractation : $ici : énoncé publié du $hc ($sc) au moins aussi récent sur une entrée du scan de même nom ; cette rétractation peut ne rien rétracter (couverture par paquet non comparée)"
    fi
  fi
  if [ "$st" = not_affected ]; then
    ech=$(date -u -d "@$(((ts + duree) / 1000000000))" +%Y-%m-%dT%H:%M:%SZ)
    echo "ECHEANCE|énoncé $k : $ech ($VEX_AGE_MAX_JOURS jours après $hs)"
    [ $((ts + duree - now)) -ge "$jour" ] \
      || echo "AVIS|âge : $ici : échéance $ech passée ou à moins d'un jour ; un VEX ne compte qu'au scan quotidien suivant"
  fi
done < <(jq -c '.enonces | to_entries[]' "$w/verdict.json")
[ "$MODE" = signer ] || exit 0

CLE=${CLE:-hashivault://vex}
case $CLE in hashivault://*) ;; *) CLE=$(realpath -- "$CLE") ;; esac
CONFIG_REGISTRE=$(realpath -- "${CONFIG_REGISTRE:?CONFIG_REGISTRE : authentification d oras pour builds/vex}")
cosign signing-config create --out "$w/vide.json" > "$w/cosign.log" 2>&1 || { cat "$w/cosign.log" >&2; exit 1; }
cosign attest-blob --key "$CLE" --signing-config "$w/vide.json" --predicate "$DOC" --type "$OPENVEX" --bundle "$w/bundle.json" \
  --hash "$hex" --yes "$nom" >> "$w/cosign.log" 2>&1 || { cat "$w/cosign.log" >&2; refus "signature en échec"; }
cosign verify-blob-attestation --bundle "$w/bundle.json" --new-bundle-format --key "$CLE_PUBLIQUE" --insecure-ignore-tlog --type "$OPENVEX" \
  --digest "$hex" --digestAlg sha256 >> "$w/cosign.log" 2>&1 || refus "signature non vérifiée par la clé publique : rien n'est publié"
jq -r .dsseEnvelope.payload "$w/bundle.json" | base64 -d > "$w/signe.json"
juger "$w/signe.json"
echo "SIGNE|bundle sha256 $(sha256sum < "$w/bundle.json" | cut -c1-64), énoncé signé sha256 $(sha256sum < "$w/signe.json" | cut -c1-64)"

ecrire() { oras "$@" --ca-file "$CA" --registry-config "$CONFIG_REGISTRE"; }
oras manifest fetch --ca-file "$CA" --descriptor "$IMAGE" > "$w/sujet.json"
printf '{}' > "$w/config-vide.json"
ecrire blob push "$depot_vex" "$w/config-vide.json" > /dev/null
ecrire blob push "$depot_vex" "$w/bundle.json" > /dev/null
TY=application/vnd.dev.sigstore.bundle.v0.3+json
printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s",%s,%s,%s,%s}' "$TY" \
  '"config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2}' \
  "\"layers\":[{\"mediaType\":\"$TY\",\"digest\":\"sha256:$(sha256sum < "$w/bundle.json" | cut -c1-64)\",\"size\":$(wc -c < "$w/bundle.json")}]" \
  "\"subject\":$(cat "$w/sujet.json")" \
  "\"annotations\":{\"dev.sigstore.bundle.content\":\"dsse-envelope\",\"dev.sigstore.bundle.predicateType\":\"$OPENVEX\",\"org.opencontainers.image.created\":\"$heure\"}" \
  > "$w/manifeste.json"
d=sha256:$(sha256sum < "$w/manifeste.json" | cut -c1-64)
ecrire manifest push "$depot_vex@$d" "$w/manifeste.json" > /dev/null
echo "PUBLIE|$depot_vex@$d, referrer de sha256:$hex ; compte au scan quotidien suivant"
