#!/usr/bin/env bash
# Prédiction N1 de la brique 05 : repasser packaging:sources après le portage de Q1 au spec (3e5f7f0).
# Garde une copie du cache avant le passage, lance la tâche, compare SHA256SUMS.
# Usage (racine du dépôt) : bash n1-sources.sh '<accord du propriétaire>' </dev/null
set -uo pipefail
export LC_ALL=C
accord=$1
racine=$(git rev-parse --show-toplevel)
cd "$racine" || exit 1
C=$HOME/.cache/supply-chain-poc/packaging
A=$(dirname "$(readlink -f "$0")")/avant
R=poc/bricks/05-rpm-mock/resultats
LOG=$R/n1-sources.log
[[ ! -e $A && ! -e $LOG ]] || { echo "ARRÊT : $A ou $LOG existe déjà"; exit 2; }
[[ -z $(git status --porcelain -- poc/sample-app poc/packaging "$R") ]] || { echo "ARRÊT : modifications non commitées"; exit 2; }
cp -a "$C" "$A" || exit 2
attendu_spec=918a83f592c31d322a77a4e887c808c61077e2f100442dc98abed5c67ae582a6
[[ $(sha256sum < poc/packaging/sample-app.spec | cut -d' ' -f1) == "$attendu_spec" ]] || { echo "ARRÊT : spec du dépôt inattendu"; exit 2; }

d=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '05 N1 sources\t%s\t\n' "$d" >> "$R/chrono.tsv"
{
  echo "# sources.sh (prédiction N1 de la 05, après le portage de Q1 au spec), $d, HEAD $(git rev-parse --short HEAD), « $accord »"
  mise run packaging:sources </dev/null 2>&1
  rc=$?
  f=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "# fin $f, code $rc"
  echo "## Contrôle N1 (copie du cache gardée avant le passage)"
  ko=0
  if [[ $rc -ne 0 ]]; then echo "NON TENUE : code $rc"; ko=1; fi
  av=$(grep -v ' sample-app.spec$' "$A/SHA256SUMS"); ap=$(grep -v ' sample-app.spec$' "$C/SHA256SUMS")
  if [[ $av == "$ap" && $(wc -l <<<"$ap") -eq 4 ]]; then echo "tenue     quatre lignes hors spec inchangées"; else echo "NON TENUE quatre lignes hors spec"; diff <(echo "$av") <(echo "$ap"); ko=1; fi
  ls=$(grep ' sample-app.spec$' "$C/SHA256SUMS")
  if [[ $ls == "$attendu_spec  sample-app.spec" ]]; then echo "tenue     ligne du spec : $ls"; else echo "NON TENUE ligne du spec : $ls"; ko=1; fi
  if cmp -s "$C/sample-app.spec" poc/packaging/sample-app.spec; then echo "tenue     copie du spec égale au spec du dépôt"; else echo "NON TENUE copie du spec"; ko=1; fi
  if (cd "$C" && sha256sum -c --quiet SHA256SUMS); then echo "tenue     SHA256SUMS vérifié sur le cache"; else echo "NON TENUE sha256sum -c"; ko=1; fi
  echo "# bilan N1 : $([[ $ko -eq 0 ]] && echo tenue || echo 'NON TENUE')"
  printf '05 N1 sources fait\t%s\t\n' "$f" >> "$R/chrono.tsv"
  exit $(( rc != 0 ? rc : ko ))
} 2>&1 | sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' | tee "$LOG"
exit "${PIPESTATUS[0]}"
