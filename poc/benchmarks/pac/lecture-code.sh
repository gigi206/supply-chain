#!/usr/bin/env bash
# Évaluation PaC (hors ADR 0000) : extraits du code lus pour E1 à E6, imprimés avec fichier, lignes et SHA, sans rien exécuter du dépôt.
# Usage (racine du dépôt) : bash poc/benchmarks/pac/lecture-code.sh <clone de releve-sante.sh> > poc/benchmarks/pac/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
[ $# = 1 ] || { echo "KO   usage : $0 <clone>" >&2; exit 1; }
D=$1
echo "# lecture-code.sh, début $(date -u +%FT%TZ) ; clone $D ; HEAD $(git -C "$D" rev-parse HEAD) ; tag $(git -C "$D" describe --tags --exact-match)"
echo "état du clone (git status --porcelain, vide attendu) : [$(git -C "$D" status --porcelain | wc -l) lignes]"
x() { # titre fichier première dernière
  echo; echo "## $1 : $2, l. $3 à $4 (sha256 du fichier $(sha256sum < "$D/$2" | cut -c1-16))"
  sed -n "$3,$4p" "$D/$2" | nl -ba -v "$3" -w4 -s ' | ' | sed '/jeton\|token/I c\     [ligne masquée : motif jeton|token]'
}
x "E1, signature Forgejo ou Gitea : HMAC du corps seul" pkg/provider/gitea/gitea.go 236 266
x "E1, identifiant de livraison : lu pour les journaux" pkg/adapter/adapter.go 176 179
x "E1, identifiant de livraison : fonction" pkg/adapter/adapter.go 294 301
echo; echo "## E1, recherche d'un anti-rejeu (dedup, duplicate, replay, already processed) hors tests :"
grep -rn -i "dedup\|duplicate\|replay\|already processed" --include=*.go "$D/pkg" | grep -v _test | sed "s|$D/||" | cut -c1-160
echo "## E1, usages de X-Gitea-Delivery hors tests :"
grep -rn "X-Gitea-Delivery" --include=*.go "$D/pkg" | grep -v _test | sed "s|$D/||" | cut -c1-160
x "E2, création auto du secret git (défaut)" pkg/params/settings/config.go 82 82
x "E2, secret git créé dans l'espace du Repository" pkg/pipelineascode/pipelineascode.go 330 346
x "E2, PipelineRun créé dans l'espace du Repository" pkg/pipelineascode/pipelineascode.go 384 385
x "E2, espace des secrets du fournisseur : Repository, ou Repository global par héritage" pkg/secrets/inherit.go 24 34
x "E2, lecture du secret de webhook dans cet espace" pkg/secrets/secret.go 78 100
x "E3, embarquement des tâches : seulement si resolver vide" pkg/resolve/resolve.go 142 165
x "E3, embarquement du pipeline : seulement si resolver vide" pkg/resolve/remote.go 215 231
x "E3, origine de .tekton : source (défaut) ou default_branch" pkg/apis/pipelinesascode/v1alpha1/types.go 111 117
x "E3, Forgejo ou Gitea : révision lue selon pipelinerun_provenance" pkg/provider/gitea/gitea.go 509 518
echo; echo "## E4, recherche d'un rattrapage (missed webhook, lost webhook, poll) hors tests :"
grep -rln -i "missed webhook\|lost webhook\|poll" --include=*.go "$D/pkg" | grep -v _test | sed "s|$D/||"
echo; echo "## E5, droits sur les Secrets (yq et jq sur config/20*.yaml)"
for f in config/201-controller-role.yaml config/202-watcher-role.yaml config/203-webhook-role.yaml; do
  yq -o=json . "$D/$f" | jq -c -s --arg f "$f" '.[] | select(.kind=="ClusterRole" or .kind=="Role") | {f:$f, kind, name:.metadata.name, secrets:[.rules[] | select(.resources|index("secrets")) | {verbs, resourceNames}]} | select(.secrets|length>0)'
  yq -o=json . "$D/$f" | jq -c -s '.[] | select(.kind|test("Binding")) | {kind, name:.metadata.name, role:.roleRef.name, sa:[.subjects[].name]}'
done
x "E6, statut de Forgejo" docs/content/docs/installation/requirements.md 189 189
x "E6, statut de Forgejo (liste des fournisseurs)" docs/content/docs/dev/_index.md 16 16
echo; echo "# fin $(date -u +%FT%TZ)"
