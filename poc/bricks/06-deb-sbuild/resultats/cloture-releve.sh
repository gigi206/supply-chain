#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # ok/ko ne font qu'afficher ; motifs littéraux voulus entre apostrophes
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 06, relevé de clôture (19/11/2026), en lecture seule. Prédictions CL1 à CL6 : cloture-predictions.md, commitées avant.
#   A  scripts de la 06 : chaque usage de $PRIVILEGIE (pods d'essai de S1 à S3 et du diagnostic) est sur une ligne qui nomme kata ;
#      les pods JSON privilégiés de s4d.sh et s5.sh portent runtimeClassName kata (s5.sh : même condition $k == "kata") ;
#      les tâches privilégiées construire-builder et construire-deb ne reçoivent Kata que du PipelineRun : chaque gabarit qui les
#      lance pose runtimeClassName kata pour la tâche construire.
#   B  journaux archivés de S1 à S3 et du diagnostic : chaque pod au contexte privilégié affiché tourne sous kata.
#   C  cluster, lecture seule à l'heure du relevé : politique Kyverno pods-isolation (actions, règle « privilégié hors Kata »),
#      label Pod Security de l'espace builds, pods privilégiés hors Kata hors kube-system et kyverno (espace/nom seulement).
#   D  effort : commits qui touchent poc/bricks/06-deb-sbuild depuis la note du 14/11 (21:40:25Z), heures de commit en UTC,
#      blocs séparés par plus de 45 min, briques touchées par chaque commit (commits partagés). Aucune conversion en pw.
set -euo pipefail
G=$(git rev-parse --show-toplevel)
B=$G/poc/bricks/06-deb-sbuild
export KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml
nko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; nko=$((nko + 1)); }
echo "# cloture-releve.sh, début $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$G" rev-parse --short=12 HEAD)"

echo "## A : scripts"
n=0
while IFS= read -r l; do
  n=$((n + 1))
  case "$l" in *" kata "*) ok "usage privilégié avec kata : ${l%%:*}:$(cut -d: -f2 <<<"$l")" ;; *) ko "usage privilégié sans kata : $l" ;; esac
done < <(cd "$B" && grep -n '\$PRIVILEGIE' s1.sh s2.sh s3.sh diag-exec-kata.sh | grep -v "^[^:]*:[0-9]*:PRIVILEGIE=")
echo "usages de \$PRIVILEGIE : $n"
l=$(grep -n 'securityContext: {privileged: true' "$B/s4d.sh" | cut -d: -f1)
[ "$(sed -n "$((l - 6)),$((l - 1))p" "$B/s4d.sh" | grep -c 'runtimeClassName: "kata"')" = 1 ] \
  && ok "s4d.sh:$l : pod d'essai privilégié, runtimeClassName kata dans le même objet" || ko "s4d.sh:$l sans kata"
[ "$(grep -c 'securityContext: (if \$k == "kata" then {privileged: true' "$B/s5.sh")" = 1 ] \
  && [ "$(grep -c '+ \$z + (if \$k == "kata" then {runtimeClassName: "kata"} else {} end)' "$B/s5.sh")" = 1 ] \
  && ok "s5.sh : pod d'essai privilégié seulement si \$k == kata, et alors runtimeClassName kata" || ko "s5.sh : pod d'essai"
for f in builder/construire-builder.yaml builder/construire-builder.signee.yaml deb/construire-deb.yaml deb/construire-deb.signee.yaml; do
  echo "tâche privilégiée : $f ($(grep -c 'privileged: true' "$B/$f") ligne) ; runtimeClassName dans la tâche : $(grep -c '^ *runtimeClassName:' "$B/$f" || true)"
done
for x in 's4a.sh:pipelineTaskName: "construire", podTemplate: ($g.zone + {runtimeClassName: "kata"})' \
         's4d.sh:pipelineTaskName: "construire", podTemplate: ($z + {runtimeClassName: "kata"})' \
         's5.sh:podTemplate: (if $k == "kata" then $z + {runtimeClassName: "kata"} else $z end)'; do
  f=${x%%:*}; m=${x#*:}
  [ "$(grep -cF "$m" "$B/$f")" = 1 ] && ok "$f : gabarit de PipelineRun ou TaskRun, Kata posé : $m" || ko "$f : motif absent"
done
v=$(yq '.. | select(tag == "!!map") | select(has("pipelineTaskName")) | select(.pipelineTaskName == "construire") | .podTemplate.runtimeClassName' \
  "$B/deb/declencheur.yaml" | sort | uniq -c | tr -s ' ')
[ "$v" = " 1 kata" ] && ok "deb/declencheur.yaml : taskRunSpecs construire, runtimeClassName kata (une fois)" || ko "declencheur.yaml : $v"

echo "## B : journaux archivés"
np=0; nk=0; nr=0
while IFS= read -r l; do
  case "$l" in *'"privileged":true'*) np=$((np + 1)); case "$l" in *"runtimeClassName kata"*) ;; *) ko "pod privilégié hors kata : $l" ;; esac ;; esac
  case "$l" in *"runtimeClassName kata"*) nk=$((nk + 1)) ;; *"runtimeClassName -"*) nr=$((nr + 1)) ;; esac
done < <(cd "$B/resultats" && grep -h '^### ' s1*.log s2*.log s3*.log diag-exec-*.log | grep 'runtimeClassName')
echo "en-têtes de pod : $nk sous kata, $nr sans RuntimeClass ; contexte privilégié affiché : $np, tous sous kata si aucun KO ci-dessus"
(cd "$B/resultats" && grep -h '^### ' s1*.log s2*.log s3*.log diag-exec-*.log | grep 'runtimeClassName -' \
  | sed -E 's/ : prêt.*//; s/ à [0-9:]+ UTC//' | sort | uniq -c)

echo "## C : cluster, à $(date -u +%H:%M:%S) UTC"
p=$(kubectl get validatingpolicies.policies.kyverno.io pods-isolation -o json </dev/null)
echo "pods-isolation : actions $(jq -c '.spec.validationActions' <<<"$p"), $(jq '.spec.validations | length' <<<"$p") validations"
[ "$(jq '[.spec.validations[].expression | select(. == "variables.kata || variables.sc.all(s, !has(s.privileged) || !s.privileged)")] | length' <<<"$p")" = 1 ] \
  && ok "pods-isolation : règle « privilégié hors Kata » déployée telle que dans admission.yaml" || ko "règle privilégié absente"
echo "espace builds : pod-security enforce « $(kubectl get ns builds -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' </dev/null) »"
priv=$(kubectl get pods -A -o json </dev/null | jq -r '.items[]
  | select((.spec.runtimeClassName // "") != "kata")
  | select([(.spec.containers + (.spec.initContainers // []))[] | .securityContext.privileged // false] | any)
  | .metadata.namespace + " " + .metadata.name')
echo "pods privilégiés hors Kata, par espace : $(cut -d' ' -f1 <<<"$priv" | sed '/^$/d' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
h=$(grep -cvE '^(kube-system|kyverno) |^$' <<<"$priv" || true)
grep -vE '^(kube-system|kyverno) |^$' <<<"$priv" || true
echo "hors kube-system et kyverno : $h"

echo "## D : effort (heures de commit, UTC)"
commits=$(TZ=UTC git -C "$G" log --reverse --since=2026-11-14T21:40:25Z --format='%h %cd' --date=format-local:%Y-%m-%dT%H:%M:%SZ \
  -- poc/bricks/06-deb-sbuild | while read -r c d; do
  echo "$c $d $(git -C "$G" show --name-only --format= "$c" | sed -nE 's#^poc/bricks/([^/]+)/.*#\1#p; s#^(docs|tools)/.*#\1#p' | sort -u | tr '\n' ',')"
done)
COMMITS=$commits python3 -I - <<'PY'
import os, datetime as dt
L = [l.split() for l in os.environ["COMMITS"].splitlines() if l.strip()]
t = [dt.datetime.strptime(x[1], "%Y-%m-%dT%H:%M:%SZ") for x in L]
blocs, d = [], 0
for i, x in enumerate(t):
    if i == 0 or (x - t[i - 1]).total_seconds() > 45 * 60:
        blocs.append([i, i])
    else:
        blocs[-1][1] = i
for a, b in blocs:
    s = (t[b] - t[a]).total_seconds(); d += s
    autres = sorted({p for x in L[a:b + 1] for p in (x[2].split(",") if len(x) > 2 else []) if p and p != "06-deb-sbuild"})
    print(f"bloc {L[a][1]} à {L[b][1]} : {b - a + 1} commits, {dt.timedelta(seconds=int(s))} ; autres chemins : {', '.join(autres) or '-'}")
print(f"commits : {len(L)} ; blocs : {len(blocs)} ; somme des blocs : {dt.timedelta(seconds=int(d))} (borne basse : avant le premier commit de chaque bloc, non compté)")
PY
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ) ; KO $nko"
exit $((nko > 0))
