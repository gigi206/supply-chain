#!/usr/bin/env bash
# Brique 07b, avant la pièce 5 (ajout du 23/11/2026) : croisements « ancienne porte + prédicat neuf » et « ancien entrees-scan.py +
# prédicat neuf », mesurés à sec sur l'hôte. Entre la pièce 5 (scanner neuf) et les pièces 6 et 7, la porte et entrees-scan.py
# déployés sont ceux de HEAD, et les scans quotidiens portent le prédicat neuf. Rien dans le cluster, rien dans Zot, rien sur la VM.
# Étape (journal jamais réécrit) :
#   sec : 1. porte de HEAD (git show HEAD:…, égale à la ConfigMap porte/porte, contrôlé ici) jugeant, par ec validate input avec le
#            policy-scan.yaml de HEAD, des prédicats neufs du grand banc (passage 24) ; mesure en différentiel : même prédicat, avec et
#            sans les champs vex (entrées et bloc), les codes deny doivent être égaux ; cas sans KEV, entrée écartée passée en KEV,
#            repli ; plus le prédicat d'avant la tranche 3 contre le prédicat neuf sans VEX (compatibilité du banc) ;
#         2. entrees-scan.py de HEAD (comptes et entrees) sur les mêmes prédicats, avec et sans les champs vex : sorties égales.
# Usage (racine du dépôt) : poc/bricks/07a-sbom-grype/piece5-croisements.sh sec  (journal : resultats/piece5-croisements-sec.log)
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/../../.." && pwd)
e=${1:-}
[ "$e" = sec ] || { echo "usage : $0 sec" >&2; exit 2; }
L=$here/resultats/piece5-croisements-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
BANC=$HOME/.cache/supply-chain-poc/07a/t3/banc
T=$HOME/.cache/supply-chain-poc/07a/p5-croisements
[ ! -e "$T" ] || { echo "dossier de travail déjà présent : $T" >&2; exit 1; }
mkdir -m 700 "$T"
trap 'find "$HOME/.cache/supply-chain-poc/07a/p5-croisements" -delete' EXIT
KO=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; KO=$((KO + 1)); }
attendu() { [ "$2" = "$3" ] && ok "$1 : $2" || ko "$1 : $2 (attendu : $3)"; }
exec > "$L" 2>&1
echo "# piece5-croisements.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "outils : $(ec version 2>/dev/null | sed -n 's/^Version *//p' | head -1), $(python3 --version), HEAD $(git -C "$R" rev-parse --short=12 HEAD)"

echo "## 0. porte de HEAD = porte déployée"
mkdir "$T/regles"
git -C "$R" show HEAD:poc/bricks/07a-sbom-grype/politique/porte/scan.rego > "$T/regles/scan.rego"
git -C "$R" show HEAD:poc/bricks/07a-sbom-grype/politique/porte/policy-scan.yaml | sed "s#/etc/porte/regles-scan#$T/regles#" > "$T/politique.yaml"
git -C "$R" show HEAD:poc/bricks/07a-sbom-grype/systemd/entrees-scan.py > "$T/entrees-scan.py"
for k in scan.rego policy-scan.yaml; do
  a=$(KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml kubectl -n porte get cm porte -o json | jq -j --arg k "$k" '.data[$k]' | sha256sum | cut -c1-16)
  b=$(git -C "$R" show "HEAD:poc/bricks/07a-sbom-grype/politique/porte/$k" | sha256sum | cut -c1-16)
  attendu "$k : ConfigMap porte/porte = HEAD" "$a" "$b"
done
grep -q 'v.vex.expires' "$T/regles/scan.rego" && ok "porte de HEAD : exemption par v.vex.expires (champ absent du prédicat neuf)" || ko "porte de HEAD : v.vex.expires absent"
grep -q -- '- fixed' "$T/politique.yaml" && ok "politique de HEAD : fixed encore accepté (retiré par la pièce 6)" || ko "politique de HEAD : fixed absent"

echo "## 1. ancienne porte + prédicat neuf (ec validate input)"
D=1111111111111111111111111111111111111111111111111111111111111111
TYPE=https://supply-chain.example/scan/v1
# entrée de la porte, base datée du scan (comme le banc : base_recente hors sujet) ; $3 : id passé en KEV (AUCUNE : aucun)
entree() { jq -c --arg d "$D" --arg t "$TYPE" --arg k "$3" '{digest: $d, statements: [{_type: "https://in-toto.io/Statement/v0.1",
    subject: [{name: "sample-app", digest: {sha256: $d}}], predicateType: $t,
    predicate: (.scanner.db.built = .scannedAt | .vulnerabilities |= map(if .id == $k then .kev = true else . end))}]}' "$1" > "$2"; }
juger() { # fichier d'entrée -> code ec et codes deny triés
  local c=0
  ec validate input "$1" --policy "$T/politique.yaml" --info --output json > "$1.ec" 2> "$1.err" || c=$?
  echo "$c $(jq -r '[.filepaths[].violations[]?.metadata.code] | unique | join(",")' "$1.ec" 2>/dev/null || echo sans-verdict)"
}
sans_vex() { jq 'del(.vex) | .vulnerabilities |= map(del(.vex))' "$1" > "$2"; }
cas() { # libellé prédicat id-en-KEV verdict-attendu (code et codes deny)
  local n=$1 p=$2 k=$3 a=$4 v1 v2
  [ -s "$p" ] || { ko "$n : prédicat absent ($p)"; return; }
  sans_vex "$p" "$T/$n-sans.json"
  attendu "$n : kev booléen sur toutes les entrées du prédicat neuf (règle forme)" "$(jq '[.vulnerabilities[] | .kev | type] | unique | join(",")' -r "$p")" boolean
  entree "$p" "$T/$n-avec-entree.json" "$k"; entree "$T/$n-sans.json" "$T/$n-sans-entree.json" "$k"
  v1=$(juger "$T/$n-avec-entree.json"); v2=$(juger "$T/$n-sans-entree.json")
  attendu "$n : verdict, prédicat neuf avec vex = sans vex" "$v1" "$v2"
  attendu "$n : verdict de l'ancienne porte" "$v1" "$a"
  [ "${v1%% *}" = 0 ] || [ "${v1%% *}" = 1 ] || tail -1 "$T/$n-avec-entree.json.err" | cut -c1-200
}
cas complet-sans-kev "$BANC/cas/complet/scan.json" AUCUNE "0 "
cas complet-kev-ecartee "$BANC/cas/complet/scan.json" GHSA-mqqf-5wvp-8fh8 "1 scan.kev_without_vex"
cas deb-complet-sans-kev "$BANC/cas/deb-complet/scan.json" AUCUNE "0 "
cas deb-complet-kev-ecartee "$BANC/cas/deb-complet/scan.json" GO-2025-3849 "1 scan.kev_without_vex"
cas repli-sans-kev "$BANC/cas/repli/scan.json" AUCUNE "0 "
# prédicat d'avant la tranche 3 contre le prédicat neuf sans document VEX (état réel entre la pièce 5 et la pièce 8)
for x in avant-t3 compat-image; do entree "$BANC/$x.json" "$T/$x-entree.json" AUCUNE; done
attendu "compat-image : bloc vex vide, aucune entrée écartée" "$(jq -c '[.vex.documents, ([.vulnerabilities[] | select(.vex)] | length)]' "$BANC/compat-image.json")" '[[],0]'
attendu "compat-image (prédicat neuf sans VEX) = avant-t3, ancienne porte" "$(juger "$T/compat-image-entree.json")" "$(juger "$T/avant-t3-entree.json")"
attendu "avant-t3, ancienne porte" "$(juger "$T/avant-t3-entree.json")" "0 "

echo "## 2. ancien entrees-scan.py + prédicat neuf (comptes et entrees de HEAD)"
for c in complet deb-complet repli; do
  p=$BANC/cas/$c/scan.json
  sans_vex "$p" "$T/es-$c-sans.json"
  r=$(python3 -I - "$T/entrees-scan.py" "$p" "$T/es-$c-sans.json" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("es", sys.argv[1])
es = importlib.util.module_from_spec(spec)
spec.loader.exec_module(es)
a, b = (json.load(open(f, encoding="utf-8")) for f in sys.argv[2:4])
ca, cb = es.comptes("builds/x", a), es.comptes("builds/x", b)
ea, eb = list(es.entrees("builds/x", a)), list(es.entrees("builds/x", b))
kev = [l for l in ca.splitlines() if l.startswith("scan_entrees_kev{")]
print(f"{ca == cb} {ea == eb} {len(ca.splitlines())} {len(ea)} {'|'.join(kev)}")
PY
)
  set -- $r
  attendu "$c : séries de HEAD, prédicat neuf avec vex = sans vex" "$1" True
  attendu "$c : lignes de HEAD, prédicat neuf avec vex = sans vex" "$2" True
  echo "     $c : $3 séries, $4 lignes d'entrée, $5"
done
echo "     limite (lue dans le code, non mesurée) : une KEV écartée par un VEX resterait comptée dans scan_entrees_kev jusqu'à la pièce 7"
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$KO" = 0 ] && echo "bilan : tenue" || echo "bilan : $KO KO"
