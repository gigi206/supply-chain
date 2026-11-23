#!/usr/bin/env bash
# Brique 07b, pièce 8, préparation à sec (écrit le 2026-11-23, pendant le rejeu un-trait-1) : relevé des entrées d'un scan signé
# et gabarit OpenVEX v0.2.0 à compléter par le propriétaire. Ne signe rien, n'écrit rien dans Zot ni dans le cluster.
# La liste des entrées est aussi dans Grafana (Loki, unite="entrees-scan.service", une ligne JSON par entrée), mais
# entrees-scan.py ne vérifie pas la signature ; ici, le scan est vérifié, comme par signer-vex.sh qui jugera le document.
#   Lecture du scan : celle de signer-vex.sh (l. 81-97) : cosign verify-attestation par CLE_SCANNER dans <hôte>/builds/scan/<nom>,
#   le plus récent (scannedAt) des scans dont le sujet est le digest. PREDICAT=<fichier> (banc seulement) : prédicat lu dans ce
#   fichier, NON VÉRIFIÉ, et la sortie le dit.
#   Sortie standard : tableau des entrées (identifiant, alias, gravité, KEV, EPSS, paquet, corrigé dans, VEX appliqué), puis
#   comptes.
#   Gabarit, seulement pour les identifiants donnés (scan-outil rejette un document entier dès qu'un énoncé est irrecevable) :
#   un énoncé not_affected par identifiant ; produit pkg:oci/<nom>@sha256:<hex> (forme des bancs de la 07b) ; sous-composants =
#   paquets des entrées de cet identifiant, chaîne du prédicat à l'octet près ; nom = identifiant ; alias = ceux du prédicat.
#   Laissés vides EXPRÈS : author, timestamp (document et énoncés), justification, impact_statement. Tel quel, le gabarit est
#   rejeté par scan-outil vex (mesuré au banc). Le propriétaire choisit la justification parmi les cinq de la spécification
#   (component_not_present, vulnerable_code_not_present, vulnerable_code_not_in_execute_path,
#   vulnerable_code_cannot_be_controlled_by_adversary, inline_mitigations_already_exist), écrit l'impact, date le document,
#   retire les énoncés qu'il ne retient pas, puis passe signer-vex.sh verifier, puis signer.
#   Le chemin du gabarit est obligatoire et n'a pas de défaut : où le propriétaire garde ses VEX non signés n'est pas décidé.
# Usage : [PREDICAT=<fichier>] CA=<certificat du registre> CLE_SCANNER=<clé publique du scanner> \
#           vex-gabarit.sh <hôte/dépôt@sha256:…> <gabarit.json | -> [identifiant…]
#   « - » : tableau seul, aucun gabarit (aucun identifiant accepté alors).
set -euo pipefail
export LC_ALL=C
usage() { echo "usage : vex-gabarit.sh <hôte/dépôt@sha256:…> <gabarit.json | -> [identifiant…]" >&2; exit 2; }
[ $# -ge 2 ] || usage
IMAGE=$1 SORTIE=$2
shift 2
printf '%s' "$IMAGE" | grep -qE '^[^@/]+/[^@]+@sha256:[0-9a-f]{64}$' || { echo "image attendue : hôte/dépôt@sha256:<64 hexadécimaux>" >&2; exit 2; }
if [ "$SORTIE" = - ]; then [ $# = 0 ] || { echo "identifiants sans chemin de gabarit" >&2; exit 2; }
else
  [ $# -gt 0 ] || { echo "gabarit demandé sans identifiant" >&2; exit 2; }
  [ ! -e "$SORTIE" ] || { echo "existe déjà, jamais réécrit : $SORTIE" >&2; exit 2; }
fi
OPENVEX=https://openvex.dev/ns/v0.2.0
hex=${IMAGE##*@sha256:} r=${IMAGE%@sha256:*}
n=${r#*/} nom=${r##*/}
depot_scan=${r%%/*}/builds/scan/${n#builds/}
w=$(mktemp -d)
trap 'find "$w" -delete' EXIT
refus() { echo "REFUS|$1" >&2; exit 1; }

if [ -n "${PREDICAT:-}" ]; then
  # prédicat seul, ou énoncé in-toto qui le porte (forme de 07b-t1-predicat-sample-app-deb.json)
  jq 'if has("predicate") then .predicate else . end' "$PREDICAT" > "$w/scan.json" 2> /dev/null || refus "PREDICAT illisible"
  jq -e '.vulnerabilities | type == "array"' "$w/scan.json" > /dev/null || refus "PREDICAT sans vulnerabilities"
  origine="PREDICAT=${PREDICAT##*/} (banc : NON VÉRIFIÉ)"
else
  CA=$(realpath -- "${CA:?CA : certificat du registre}")
  CLE_SCANNER=$(realpath -- "${CLE_SCANNER:?CLE_SCANNER : clé publique du scanner}")
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
  jq .predicate "$meilleur" > "$w/scan.json"
  origine="$nv scan(s) vérifié(s) par CLE_SCANNER (empreinte de la clé $(sha256sum < "$CLE_SCANNER" | cut -c1-16)) dans $depot_scan"
fi
S=$w/scan.json

echo "# vex-gabarit.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; sujet $nom@sha256:$hex ; scan du $(jq -r .scannedAt "$S") ; $origine"
echo
echo "| # | Identifiant | Alias | Gravité | KEV | EPSS | Paquet | Corrigé dans | VEX appliqué |"
echo "|---|---|---|---|---|---|---|---|---|"
jq -r '.vulnerabilities | sort_by(.id, .package) | to_entries[] | .key as $k | .value
  | "| \($k + 1) | \(.id) | \((.aliases // []) | join(", ")) | \(.severity // "?") | \(if .kev then "oui" else "non" end) | \(.epss // "n/d")"
    + " | `\(.package)` | \((.fixedIn // []) | join(", ")) | \(if .vex then "\(.vex.status) (\(.vex.timestamp))" else "-" end) |"' "$S"
echo
jq -r '.vulnerabilities as $v
  | "comptes : \($v | length) entrée(s), \($v | map(.id) | unique | length) identifiant(s) ; "
    + "KEV \($v | map(select(.kev)) | length) ; avec correctif \($v | map(select((.fixedIn // []) | length > 0)) | length) ; "
    + "écartées par un VEX \($v | map(select(.vex)) | length) ; gravités : "
    + ($v | group_by(.severity // "?") | map("\(.[0].severity // "?") \(length)") | join(", "))' "$S"

[ "$SORTIE" != - ] || exit 0
for id in "$@"; do
  jq -e --arg i "$id" 'any(.vulnerabilities[]; .id == $i)' "$S" > /dev/null || refus "identifiant absent du scan (id exact attendu) : $id"
done
jq --arg ctx "$OPENVEX" --arg prod "pkg:oci/$nom@sha256:$hex" --arg nom "$nom" --args '
  . as $s | {
    "@context": $ctx,
    "@id": "https://supply-chain.example/vex/\($nom)/A-NOMMER",
    author: "", timestamp: "", version: 1,
    statements: [$ARGS.positional | unique[] as $id | ($s.vulnerabilities | map(select(.id == $id))) as $e | {
      vulnerability: ({name: $id} + (($e | map(.aliases // []) | add | unique) as $a | if ($a | length) > 0 then {aliases: $a} else {} end)),
      products: [{"@id": $prod, subcomponents: ($e | map(.package) | unique | map({"@id": .}))}],
      status: "not_affected", justification: "", impact_statement: "", timestamp: ""
    }]
  }' "$@" < "$S" > "$w/gabarit.json"   # --args : tout ce qui suit le filtre est un argument, le prédicat arrive par l'entrée
(umask 077 && cp "$w/gabarit.json" "$SORTIE")
echo "gabarit écrit : $SORTIE ($(jq '.statements | length' "$SORTIE") énoncé(s), sha256 $(sha256sum < "$SORTIE" | cut -c1-16)) ; à compléter : author, timestamp, justification, impact_statement, @id"
