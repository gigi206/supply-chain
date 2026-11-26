#!/usr/bin/env bash
# Brique 20 : genre() et les noms de Chains v0.30.0 (pipelineTask/<tâche>), à sec. Deux correctifs, appliqués à une copie jetable du dépôt
# (clone local de HEAD) : genre-temoins.patch (témoins et attendus du banc) et genre-chains-v0300.patch (exportateur et recalcul). Rien n'est
# posé ; l'exportateur du dépôt reste celui de sc-stockage.
#   banc     banc.sh sans le correctif (rouge), avec (vert), puis sept mutants du correctif, un fichier à la fois ; Zot jetable, sans réseau
#   sorties  les deux genre(), avant et après, sur les énoncés produits par les vrais v0.29.9 et v0.30.0 (08, essais/chains-v0300) et sur des
#            noms écrits à la main
#   zot      exportateur-zot.sh sur le vrai Zot (lecture anonyme ; Grafana par l'auditeur), avant puis après : mêmes lignes KPI et PROM
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/20-kpi/banc-genre.sh <banc|sorties|zot>
#   (journaux : resultats/e13-genre-*.log, jamais réécrits ; SUFFIXE=-2 pour un passage de plus)
# Les deux correctifs sont appliqués et commités depuis le 2026-11-26 (e15) : ce banc ne s'applique plus sur HEAD ; ses journaux e13
# restent la mesure (même précédent que alertes-kpi.patch et promql-banc.sh).
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
RACINE=$(cd "$here/../../.." && pwd)
G=$HOME/.cache/supply-chain-poc/20/banc-genre C=$HOME/.cache/supply-chain-poc/20/banc-genre/depot
R=$here/resultats S=${SUFFIXE:-}
ETAPE=${1:?banc, sorties ou zot}
LOG=$R/e13-genre-$ETAPE$S.log
for f in "$LOG" "$R/e13-genre-rouge$S.log" "$R/e13-genre-vert$S.log" "$R/e13-genre-zot-avant$S.log" "$R/e13-genre-zot-apres$S.log"; do
  case "$ETAPE:$f" in banc:*-zot-*|sorties:*-rouge*|sorties:*-vert*|sorties:*-zot-*|zot:*-rouge*|zot:*-vert*) continue ;; esac
  [ ! -e "$f" ] || { echo "journal présent, jamais réécrit : $f" >&2; exit 2; }
done
[ ! -e ~/.cache/supply-chain-poc/20/banc-genre ] || find ~/.cache/supply-chain-poc/20/banc-genre -delete
trap 'find ~/.cache/supply-chain-poc/20/banc-genre -delete' EXIT
mkdir -p "$G"
git clone -q --shared "$RACINE" "$C" || exit 1
ko=0
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=$((ko + 1)); fi; }
propre() { git -C "$C" checkout -q -- . && git -C "$C" apply "$@"; }   # copie remise à HEAD, puis correctifs
T=$here/genre-temoins.patch F=$here/genre-chains-v0300.patch
X=tools/metrics-exporter/metrics_exporter.py Y=poc/bricks/20-kpi/recalcul.py
passage() { # nom : un banc.sh de la copie ; son journal reste en $G/<nom>.log
  SUFFIXE="-$1" bash "$C/poc/bricks/20-kpi/banc.sh" > /dev/null 2>&1; local c=$?
  mv "$C/poc/bricks/20-kpi/resultats/e4-banc-$1.log" "$G/$1.log" || return 1
  echo "code $c ; $(grep -c '^## bilan' "$G/$1.log") bilans, comparaison $(grep -E '^## bilan : [0-9]+ cas' "$G/$1.log" | tail -1 | cut -d' ' -f4-) ; KO : $(grep '^KO' "$G/$1.log" | sed -E 's/^KO +//; s/ : [[{].*//' | paste -sd';')"
}
VERIF="vérifiées : dates des pins de banc-pins" RECALC="recalcul : genre, nom et pin des dépendances de banc-pins"
VU() { echo "code $1 ; 5 bilans, comparaison 25 cas, $2 écart(s) ; KO : $3"; }

banc() {
  propre "$T" || return 1
  attendu "rouge (témoins sans le correctif)" "$(passage rouge)" "$(VU 1 2 "$VERIF;$RECALC")"
  grep '^KO' "$G/rouge.log"
  propre "$T" "$F" || return 1
  attendu "vert (témoins et correctif)" "$(passage vert)" "$(VU 0 0 "")"
  cp "$G/rouge.log" "$R/e13-genre-rouge$S.log"; cp "$G/vert.log" "$R/e13-genre-vert$S.log"
  local n f a b d q
  while IFS='|' read -r n f a b q; do
    propre "$T" "$F" || return 1
    A=$a B=$b python3 -I -c 'import os, sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read(); a = os.environ["A"]; assert t.count(a) == 1, a; open(p, "w", encoding="utf-8").write(t.replace(a, os.environ["B"]))' "$C/$f" || return 1
    d=$VERIF; [ "$f" = "$X" ] || d=$RECALC
    attendu "mutant $n ($q)" "$(passage "m$n")" "$(VU 1 1 "$d")"
    grep '^KO' "$G/m$n.log"
  done <<MUT
1|$X|pipelineTask(/.+)?|pipelineTask|exportateur non corrigé, recalcul corrigé
2|$Y|bool(barre) == bool(suite)|not barre|recalcul non corrigé, exportateur corrigé
3|$X|pipelineTask(/.+)?|pipelineTask.*|exportateur : préfixe sans barre
4|$Y|debut == "pipelineTask" and bool(barre) == bool(suite)|debut.startswith("pipelineTask") and bool(barre) == bool(suite)|recalcul : préfixe sans barre
5|$X|pipelineTask(/.+)?|pipelineTask(/[^/]+)?|exportateur : matrice oubliée
6|$X|pipelineTask(/.+)?|pipelineTask/.+|exportateur : ancien nom oublié
7|$Y|bool(barre) == bool(suite)|True|recalcul : nom vide accepté
MUT
}

sorties() {
  local d=$HOME/.cache/supply-chain-poc/chains-v0300/sorties v
  propre "$T" || return 1
  mkdir -p "$G/avant" "$G/apres"
  cp "$C/$X" "$C/$Y" "$G/avant/"; propre "$T" "$F" || return 1; cp "$C/$X" "$C/$Y" "$G/apres/"
  python3 -I - "$G" "$d" <<'PY'
import json, re, sys
from pathlib import Path
G, S = Path(sys.argv[1]), Path(sys.argv[2])
ko = 0
def cas(nom, vu, voulu):
    global ko
    ko += vu != voulu
    print(f"{'OK  ' if vu == voulu else 'KO  '} {nom} : {vu}" + ("" if vu == voulu else f" (attendu : {voulu})"))
def genre(f):   # la fonction seule, sans lancer le module
    e = {"re": re}
    exec(re.search(r"^def genre\(.*?(?=^\S)", f.read_text(encoding="utf-8"), re.S | re.M).group(0), e)
    return e["genre"]
fs = {(m, q): genre(G / m / f) for m in ("avant", "apres") for q, f in (("exportateur", "metrics_exporter.py"), ("recalcul", "recalcul.py"))}
TACHES = {"f2-prefetch-1": 2, "j7-sample-app": 3, "m5b-4-construction-1": 3, "m5b-4-rpm-1": 2, "sample-app-deb-6391fd437f26696847041be3226bbbf633f55a2f": 3}
for n, t in TACHES.items():
    lus = {v: json.loads((S / f"{n}.{v}.json").read_text())["predicate"]["buildDefinition"]["resolvedDependencies"] for v in (29, 30)}
    for (m, q), f in fs.items():
        for v in (29, 30):
            cas(f"{n[:20]}, v0.{v}.x, {q} {m} : tâches", [f(x) for x in lus[v]].count("tache"), t if (m, v) != ("avant", 30) else 0)
    for q in ("exportateur", "recalcul"):
        f = fs["apres", q]
        cas(f"{n[:20]}, {q} après : mêmes genres, dans l'ordre, pour les deux formats", [f(x) for x in lus[30]] == [f(x) for x in lus[29]], True)
        cas(f"{n[:20]}, {q} : v0.29.x inchangé par le correctif", [f(x) for x in lus[29]] == [fs["avant", q](x) for x in lus[29]], True)
IMG = "oci://r/x/y"
A_LA_MAIN = [(None, "image"), (5, "image"), ("", "image"), ("pipeline", "pipeline"), ("pipeline/x", "image"), ("task", "image"), ("inputs/result", "image"),
             ("pipelineTask", "tache"), ("pipelineTask/x", "tache"), ("pipelineTask/x/y", "tache"), ("pipelineTask/", "image"), ("PipelineTask/x", "image"),
             ("pipelineTaskX", "image"), ("pipelineTaskX/y", "image"), ("x/pipelineTask/y", "image"), (" pipelineTask", "image"),
             ("pipelineTask/x\ny", "tache"), ("pipelineTask/x\n", "tache"), ("pipelineTask\n", "image")]
for nom, g in A_LA_MAIN:
    cas(f"nom {nom!r}", [fs["apres", q]({"name": nom, "uri": IMG}) for q in ("exportateur", "recalcul")], [g, g])
cas("sans nom", [fs["apres", q]({"uri": IMG}) for q in ("exportateur", "recalcul")], ["image", "image"])
sys.exit(1 if ko else 0)
PY
  v=$?; [ "$v" = 0 ] || ko=$((ko + 1))
}

zot_() {
  local m
  for m in avant apres; do
    if [ "$m" = avant ]; then git -C "$C" checkout -q -- .; else propre "$F"; fi || return 1
    SUFFIXE="-genre-$m" bash "$C/poc/bricks/20-kpi/exportateur-zot.sh" > /dev/null 2>&1
    attendu "$m : code" "$?" 0
    mv "$C/poc/bricks/20-kpi/resultats/e4-exportateur-zot-genre-$m.log" "$G/$m.log" || return 1
    cp "$G/$m.log" "$R/e13-genre-zot-$m$S.log"
    # horodatages du passage et du journal exclus
    grep -E '^(KPI|PROM)\|' "$G/$m.log" | grep -v 'kpi_exportateur_[a-z]*_timestamp_seconds' | sort > "$G/$m.lignes"
    tail -2 "$G/$m.log"
  done
  attendu "lignes KPI et PROM comparées" "$([ "$(wc -l < "$G/avant.lignes")" -gt 200 ] && echo "plus de 200" || wc -l < "$G/avant.lignes")" "plus de 200"
  echo "     ($(wc -l < "$G/avant.lignes") lignes, dont $(grep -c 'genre="tache"' "$G/avant.lignes") séries de tâche)"
  attendu "lignes différentes" "$(diff "$G/avant.lignes" "$G/apres.lignes" | grep -c '^[<>]')" 0
  diff "$G/avant.lignes" "$G/apres.lignes" | head -20
}

{
  echo "# banc-genre.sh $ETAPE, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$C" rev-parse --short=8 HEAD), témoins $(sha256sum < "$T" | cut -c1-16), correctif $(sha256sum < "$F" | cut -c1-16), script $(sha256sum < "$0" | cut -c1-16)"
  debut=$(cut -d' ' -f1 /proc/uptime)
  case "$ETAPE" in banc) banc ;; sorties) sorties ;; zot) zot_ ;; *) false ;; esac || { echo "KO   arrêt"; ko=$((ko + 1)); }
  echo "## $ETAPE : $ko KO, $(python3 -I -c 'import sys; print(f"{float(sys.argv[2]) - float(sys.argv[1]):.0f}")' "$debut" "$(cut -d' ' -f1 /proc/uptime)") s"
  [ "$ko" = 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
