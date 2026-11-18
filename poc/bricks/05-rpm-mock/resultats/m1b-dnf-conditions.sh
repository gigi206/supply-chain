#!/usr/bin/env bash
# Brique 05, M1b : conditions posées par le conseiller à sa recommandation sur dnf 4 (18/11/2026).
#   1. Hors ligne, image d'outillage (racine extraite par le troisième banc) : entrées des changelogs de python3-dnf, libdnf, librepo et
#      libsolv sur les 12 derniers mois (date, version, première ligne du texte ; adresses retirées).
#   2. Lecture publique : dates des fusions des 100 dernières PR de openSUSE/libsolv, par fusionneur.
# Prédictions : m1b-predictions.md (section des conditions), commitées avant le lancement.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-dnf-conditions.sh > poc/bricks/05-rpm-mock/resultats/m1b-dnf-conditions.log 2>&1
set -euo pipefail
export LC_ALL=C
R=$HOME/.cache/supply-chain-poc/05/m1b-repro3-20261118T201556Z/racine
GH=$(command -v gh)
gh() { env -u GITHUB_TOKEN "$GH" "$@"; }
A=$(date -u -d '1 year ago' +%s)
echo "# m1b-dnf-conditions.sh, début $(date -u +%FT%TZ) ; entrées comptées depuis $(date -u -d "@$A" +%F)"
echo "## 1. changelogs de l'image d'outillage, 12 derniers mois"
for p in python3-dnf libdnf librepo libsolv; do
  unshare --map-auto --map-root-user -n chroot "$R" /usr/bin/rpm -q --qf '[%{CHANGELOGTIME}\t%{CHANGELOGNAME}\t%{CHANGELOGTEXT}\x1e]' "$p" \
    | python3 -I -c '
import datetime, re, sys
p, a = sys.argv[1], int(sys.argv[2])
e = [x.split("\t", 2) for x in sys.stdin.read().split("\x1e") if x.strip()]
r = [x for x in e if int(x[0]) >= a]
print(f"{p} : {len(e)} entrées en tout ; {len(r)} depuis un an")
for t, n, x in r:
    n = re.sub(r"<[^>]*>", "<adresse retirée>", n)
    l = [y.strip() for y in x.splitlines() if y.strip()]
    print(f"  {datetime.datetime.fromtimestamp(int(t), datetime.timezone.utc):%Y-%m-%d} ; {n[:90]} ; {len(l)} ligne(s) ; première : {l[0][:140] if l else chr(45)}")
' "$p" "$A"
done
echo "## 2. openSUSE/libsolv : dates des fusions des 100 dernières PR, par fusionneur"
gh pr list --repo openSUSE/libsolv --state merged --limit 100 --json mergedBy,mergedAt \
  --jq 'group_by(.mergedBy.login)[] | "  \(.[0].mergedBy.login) : \(length) fusion(s), de \(map(.mergedAt[0:10]) | min) à \(map(.mergedAt[0:10]) | max)"'
echo "# fin $(date -u +%FT%TZ)"
