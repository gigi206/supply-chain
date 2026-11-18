#!/usr/bin/env bash
# Évaluation PaC (hors ADR 0000) : lectures complémentaires après relecture par le conseiller (E1 : nom des PipelineRuns et filtre
# des runs existants ; signatures des trois images au tag ; origine de la phrase de docs/00). Rien n'est exécuté du dépôt de PaC.
# Usage (racine du dépôt) : bash poc/benchmarks/pac/lecture-complement.sh <clone> > poc/benchmarks/pac/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
[ $# = 1 ] || { echo "KO   usage : $0 <clone>" >&2; exit 1; }
D=$1
echo "# lecture-complement.sh, début $(date -u +%FT%TZ) ; HEAD $(git -C "$D" rev-parse HEAD) ; tag $(git -C "$D" describe --tags --exact-match) ; état [$(git -C "$D" status --porcelain | wc -l) lignes]"
x() { echo; echo "## $1 : $2, l. $3 à $4"; sed -n "$3,$4p" "$D/$2" | nl -ba -v "$3" -w4 -s ' | ' | sed '/jeton\|token/I c\     [ligne masquée : motif jeton|token]'; }
x "E1, le contrôleur résout avec GenerateName: true" pkg/pipelineascode/match.go 408 412
x "E1, effet : name remplacé par generateName" pkg/resolve/remote.go 250 256
x "E1, filtre des PipelineRuns existants : seulement /retest et /ok-to-test" pkg/matcher/annotation_matcher.go 482 487
x "E1, ce filtre ne retient que les runs réussis du même SHA" pkg/matcher/annotation_matcher.go 501 512
echo; echo "## E7, cosign tree des trois images de release.yaml au tag"
for i in controller watcher webhook; do
  echo "### pipelines-as-code-$i:$(git -C "$D" describe --tags --exact-match)"
  cosign tree "ghcr.io/tektoncd/pipelines-as-code/pipelines-as-code-$i:$(git -C "$D" describe --tags --exact-match)" 2>&1 | sed 's/^/  /' || echo "  cosign tree code $?"
done
echo; echo "## docs/00 : commit qui a introduit « sans vérification de signature des webhooks »"
git log --format='%h %ad %s' --date=iso-strict -S 'sans vérification de signature des webhooks' -- docs/00-etude-existant.md | cut -c1-160
echo; echo "# fin $(date -u +%FT%TZ)"
