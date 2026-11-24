#!/usr/bin/env bash
# Brique 20, étape 1 (README, « Plan proposé ») : relevé à sec, en lecture anonyme, des attestations des dépôts builds/ du vrai Zot.
# Lecture seule : GET et HEAD anonymes sur l'API de Zot ; ni ssh, ni sudo, ni Grafana, ni cluster ; rien n'est écrit dans Zot.
# Les énoncés sont décodés pour leur seul predicateType et pour savoir s'ils nomment leur sujet : signatures NON vérifiées (c'est
# l'étape 2). Aucun contenu d'énoncé n'est archivé (les VEX portent un auteur) : type, sujet, digest, date et comptes seulement.
# Sujets : tirés des tags sha256-<digest>.<suffixe> (Chains : .sig, .att) et des autres tags des dépôts de sujets. Limite : un
# artefact sans aucun tag reste invisible. Referrers : cherchés pour chaque sujet dans builds/<famille>/<nom> (familles scan, vsa,
# vex, avis), si ce dépôt est au catalogue. Classe : déduite du nom du dépôt, descriptive ; le dénominateur des KPI reste à choisir.
# Usage (racine du dépôt) : [SUFFIXE=-1] bash poc/bricks/20-kpi/releve-zot.sh   (journal : resultats/e1-releve-zot<SUFFIXE>.log)
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e1-releve-zot${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
mkdir -p "$here/resultats"
CA=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
U=https://192.168.161.13:5000/v2
T=$HOME/.cache/supply-chain-poc/20/releve-zot   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/releve-zot ] || find ~/.cache/supply-chain-poc/20/releve-zot -delete
mkdir -p "$T"
trap 'find ~/.cache/supply-chain-poc/20/releve-zot -delete' EXIT
ACC='Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json'
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
get() { curl -sS --cacert "$CA" -H "$ACC" "$U/$1"; }
code() { curl -sS -o /dev/null -w '%{http_code}' --cacert "$CA" -H "$ACC" -I "$U/$1" || echo échec; }
digest_de() { curl -sS -I --cacert "$CA" -H "$ACC" "$U/$1/manifests/$2" | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}'; }
classe() {
  case $1 in
    builds/scan/*|builds/vsa/*|builds/vex/*|builds/avis/*) echo attestation ;;
    builds/builders/*) echo builder ;;
    builds/fermetures/*) echo fermeture ;;
    builds/sample-app|builds/sample-app-deb|builds/sample-app-rpm) echo produit ;;
    *) echo autre ;;
  esac
}
enonce() { # dépôt digest-du-blob hex-du-sujet : « predicateType|nomme-le-sujet » d'une enveloppe DSSE ou d'un bundle sigstore
  local r
  r=$(get "$1/blobs/$2" | jq -r --arg h "$3" '(.dsseEnvelope.payload // .payload // empty) | @base64d | fromjson
    | "\(.predicateType // "-")|\(if any(.subject[]?; .digest.sha256 == $h) then "oui" else "non" end)"' 2>/dev/null) || r=""
  echo "${r:-illisible|-}"
}

{
echo "# releve-zot.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16)"
echo "# lecture seule, anonyme, API de Zot ($U) ; signatures non vérifiées ; aucun contenu d'énoncé archivé"
c=$(curl -sS -o "$T/catalogue.json" -w '%{http_code}' --cacert "$CA" "$U/_catalog")
attendu "catalogue en anonyme" "$c" 200
jq -r '.repositories[]' "$T/catalogue.json" | sort > "$T/depots"
echo "## 1. dépôts : $(wc -l < "$T/depots") au catalogue, $(grep -c '^builds/' "$T/depots") sous builds/ ; hors builds/ (non relevés), un par ligne :"
# une ligne par dépôt (correction du 24/11 après le passage e1-releve-zot.log : sur une seule ligne, le filtre jeton|token masquait tout)
grep -v '^builds/' "$T/depots" | sed 's/^/HORS|/'
grep '^builds/' "$T/depots" | while read -r d; do echo "DEPOT|$d|$(classe "$d")"; done

echo "## 2. sujets et attestations (tag .att, referrers des familles)"
grep '^builds/' "$T/depots" | while read -r d; do
  [ "$(classe "$d")" = attestation ] && continue
  get "$d/tags/list" | jq -r '.tags // [] | .[]' > "$T/tags"
  { sed -nE 's/^sha256-([0-9a-f]{64})\.[a-z]+$/sha256:\1/p' "$T/tags"
    grep -vE '^sha256-[0-9a-f]{64}\.[a-z]+$' "$T/tags" | while read -r t; do digest_de "$d" "$t"; done
  } | sort -u > "$T/sujets"
  nom=${d#builds/}
  while read -r s; do
    [ -n "$s" ] || continue
    h=${s#sha256:}
    sig=$(grep -cx "sha256-$h.sig" "$T/tags")
    natt=0
    if grep -qx "sha256-$h.att" "$T/tags"; then
      get "$d/manifests/sha256-$h.att" > "$T/att.json"
      natt=$(jq '.layers // [] | length' "$T/att.json")
      for b in $(jq -r '.layers // [] | .[].digest' "$T/att.json"); do
        echo "ATT|$d|${h:0:12}|tag .att|$d|$(enonce "$d" "$b" "$h")|-"
      done
    fi
    echo "SUJET|$d|$(classe "$d")|$s|manifeste $(code "$d/manifests/$s")|sig $sig|att $natt"
    for f in scan vsa vex avis; do
      a=builds/$f/$nom
      grep -qx "$a" "$T/depots" || continue
      get "$a/referrers/$s" > "$T/ref.json"
      for m in $(jq -r '.manifests // [] | .[].digest' "$T/ref.json"); do
        cr=$(jq -r --arg m "$m" '.manifests[] | select(.digest == $m) | .annotations["org.opencontainers.image.created"] // "-"' "$T/ref.json")
        b=$(get "$a/manifests/$m" | jq -r '.layers[0].digest // empty')
        echo "ATT|$d|${h:0:12}|referrer|$a|$(if [ -n "$b" ]; then enonce "$a" "$b" "$h"; else echo "sans couche|-"; fi)|$cr"
      done
    done
  done < "$T/sujets"
done | tee "$T/lignes"
echo "## 3. dépôts d'attestations sans dépôt de sujets du même nom (referrers non cherchés)"
grep -E '^builds/(scan|vsa|vex|avis)/' "$T/depots" | while read -r a; do
  n=${a#builds/*/}
  grep -qx "builds/$n" "$T/depots" || echo "ORPHELIN|$a"
done

echo "## 4. synthèse"
echo "sujets par classe : $(grep '^SUJET|' "$T/lignes" | cut -d'|' -f3 | sort | uniq -c | awk '{printf "%s %s ; ", $2, $1}')"
echo "attestations par classe du sujet, forme et type (énoncés non vérifiés) :"
grep '^ATT|' "$T/lignes" | while IFS='|' read -r _ d _ forme _ type _ _; do echo "$(classe "$d")|$forme|$type"; done | sort | uniq -c | sed 's/^ */  /'
echo "dates de création annotées, par dépôt d'attestations (plus ancienne, plus récente, nombre) :"
grep '^ATT|' "$T/lignes" | awk -F'|' '$4 == "referrer" && $8 != "-" {print $5 "|" $8}' | sort | awk -F'|' '
  {if (!($1 in min)) min[$1] = $2; max[$1] = $2; n[$1]++} END {for (d in n) print "  DATES|" d "|" min[d] "|" max[d] "|" n[d]}' | sort

echo "## 5. cas prédits (resultats/e1-predictions.md)"
compte() { grep -c "^ATT|$1|$2|referrer|$3|" "$T/lignes" || true; }
attendu "VSA de 3a7ca1b1 (builds/vsa/sample-app)" "$(compte builds/sample-app 3a7ca1b14dbf builds/vsa/sample-app)" 1
attendu "VSA de f5e6bcb0 (builds/vsa/sample-app)" "$(compte builds/sample-app f5e6bcb0e0fb builds/vsa/sample-app)" 0
attendu "VSA du deb 60f25f5c (builds/vsa/sample-app-deb)" "$(compte builds/sample-app-deb 60f25f5c3fb5 builds/vsa/sample-app-deb)" 1
attendu "VEX de 3a7ca1b1 (builds/vex/sample-app)" "$(compte builds/sample-app 3a7ca1b14dbf builds/vex/sample-app)" 1
attendu "VEX de f5e6bcb0 (builds/vex/sample-app)" "$(compte builds/sample-app f5e6bcb0e0fb builds/vex/sample-app)" 1
attendu "VEX du deb 60f25f5c (builds/vex/sample-app-deb)" "$(compte builds/sample-app-deb 60f25f5c3fb5 builds/vex/sample-app-deb)" 1
attendu "au moins un scan de f5e6bcb0" "$([ "$(compte builds/sample-app f5e6bcb0e0fb builds/scan/sample-app)" -ge 1 ] && echo oui || echo non)" oui
attendu "provenance SLSA v1 dans le .att de f5e6bcb0" "$(grep -c '^ATT|builds/sample-app|f5e6bcb0e0fb|tag .att|builds/sample-app|https://slsa.dev/provenance/v1|' "$T/lignes" | awk '{print ($1 >= 1) ? "oui" : "non"}')" oui
attendu "prédicats licences/v1" "$(grep -c '|https://supply-chain.example/licences/v1|' "$T/lignes" || true)" 0
# Correction du 24/11 après le passage e1-releve-zot.log (2 fautes de la prédiction) : les témoins négatifs voulus (J6 :
# essai-j6-att-illisible, essai-j6-autre-sujet ; G6 : builds/scan/essai-scan) sont attendus, et non plus comptés comme écarts.
TEMOINS='^builds/(essai-j6-att-illisible|essai-j6-autre-sujet|essai-scan)$'
attendu "referrers dont le type ne suit pas la famille, hors témoins" "$(grep '^ATT|' "$T/lignes" | awk -F'|' -v t="$TEMOINS" '$2 !~ t && $4 == "referrer" && !(($5 ~ /^builds\/scan\// && $6 == "https://supply-chain.example/scan/v1") || ($5 ~ /^builds\/vsa\// && $6 == "https://slsa.dev/verification_summary/v1") || ($5 ~ /^builds\/vex\// && $6 == "https://openvex.dev/ns/v0.2.0"))' | wc -l)" 0
attendu "énoncés qui ne nomment pas leur sujet, hors témoins" "$(grep '^ATT|' "$T/lignes" | awk -F'|' -v t="$TEMOINS" '$2 !~ t && $7 != "oui"' | wc -l)" 0
attendu "témoins négatifs : énoncés illisibles ou qui ne nomment pas leur sujet" "$(grep '^ATT|' "$T/lignes" | awk -F'|' -v t="$TEMOINS" '$2 ~ t && $7 != "oui"' | wc -l)" 4
echo "## bilan : $N cas, $KO écart(s)"
[ "$KO" = 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; $MASQUE" | tee "$LOG"
exit "${PIPESTATUS[0]}"
