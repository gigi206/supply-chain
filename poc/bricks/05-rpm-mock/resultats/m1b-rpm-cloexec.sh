#!/usr/bin/env bash
# Brique 05, M1b : lecture publique du source de rpm 4.16.1.3 (tag amont rpm-4.16.1.3, version de l'amorce) après l'observation
# du pod m1b-a (m1b-pod-observation.log). Imprime rpmSetCloseOnExec (rpmio/rpmio.c) et son appel avant l'exec d'un scriptlet
# (lib/rpmscript.c), avec le sha256 de chaque fichier lu. Rien n'est installé ni exécuté. Usage (racine du dépôt) :
#   bash poc/bricks/05-rpm-mock/resultats/m1b-rpm-cloexec.sh > poc/bricks/05-rpm-mock/resultats/<journal neuf> 2>&1
set -euo pipefail
export LC_ALL=C
D=$(mktemp -d "${TMPDIR:-/tmp}/m1b-rpm-src.XXXXXX")
echo "# m1b-rpm-cloexec.sh, début $(date -u +%FT%TZ)"
echo "tag : $(env -u GITHUB_TOKEN gh api repos/rpm-software-management/rpm/git/ref/tags/rpm-4.16.1.3 --jq '"\(.ref) \(.object.type) \(.object.sha)"')"
for f in rpmio/rpmio.c lib/rpmscript.c; do
  env -u GITHUB_TOKEN gh api "repos/rpm-software-management/rpm/contents/$f?ref=rpm-4.16.1.3" --jq .content | base64 -d > "$D/${f//\//_}"
  echo "$f : $(wc -l < "$D/${f//\//_}") lignes, sha256 $(sha256sum < "$D/${f//\//_}" | cut -c1-64)"
done
echo "## rpmio/rpmio.c, rpmSetCloseOnExec"
n=$(grep -n '^void rpmSetCloseOnExec(void)' "$D/rpmio_rpmio.c" | cut -d: -f1)
sed -n "$((n - 11)),$((n + 36))p" "$D/rpmio_rpmio.c" | nl -ba -v $((n - 11)) -w5 -s ' | '
echo "## lib/rpmscript.c, appel dans doScriptExec"
grep -n 'static void doScriptExec\|rpmSetCloseOnExec()' "$D/lib_rpmscript.c"
for x in "$D"/*; do rm -f -- "$x"; done; rmdir -- "$D"
echo "# fin $(date -u +%FT%TZ)"
