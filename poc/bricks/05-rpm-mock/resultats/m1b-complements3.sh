#!/usr/bin/env bash
# Brique 05, M1b, point 1 A : compléments du troisième banc, après relecture du conseiller. Lecture seule du dossier du troisième
# banc (m1b-repro3-20261118T201556Z), hôte seul, hors ligne (unshare -n).
#   1. Versions et chaînes : rpm de la racine d'outils, p11-kit de l'arbre i3 ; présence de SOURCE_DATE_EPOCH dans librpm et trust
#      (lecture faite sans journal avant le troisième banc, archivée ici).
#   2. S calculé avant toute installation, par rpm -qp sur les 222 fichiers rpm, comparé à la valeur du banc (lue dans la base de i1).
#   3. Ordre des INSTALLTIME de i3 comparé à l'ordre des lignes « Installing » du journal de dnf de i3.
# Prédictions : m1b-predictions.md (section des compléments du troisième banc), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-complements3.sh > poc/bricks/05-rpm-mock/resultats/m1b-complements3.log 2>&1
set -euo pipefail
export LC_ALL=C
D=$HOME/.cache/supply-chain-poc/05/m1b-repro3-20261118T201556Z
SBANC=1778610852
ns() { unshare --map-auto --map-root-user -n "$@"; }
q() { ns chroot "$D/racine" "$@"; }
echo "# m1b-complements3.sh, début $(date -u +%FT%TZ)"
[ -d "$D/racine/m/i3/var/lib/rpm" ] && [ -f "$D/dnf-3.log" ] || { echo "KO   troisième banc absent" >&2; exit 1; }

echo "## 1. versions et chaînes"
echo "racine d'outils : $(q /usr/bin/rpm -q rpm python3-dnf | tr '\n' ' ')"
echo "arbre i3 : $(q /usr/bin/rpm --root=/m/i3 -q p11-kit p11-kit-trust ca-certificates | tr '\n' ' ')"
for f in usr/lib64/librpm.so.9 usr/lib64/librpmbuild.so.9 usr/lib64/librpmio.so.9; do
  echo "outils, $f -> $(readlink "$D/racine/$f") : lignes contenant SOURCE_DATE_EPOCH $(strings -a "$D/racine/$f" | grep -c SOURCE_DATE_EPOCH || true)"
done
echo "outils, librpm.so.9 : trois lignes avant et après la chaîne :"
strings -a "$D/racine/usr/lib64/librpm.so.9" | grep -B3 -A3 SOURCE_DATE_EPOCH | sed 's/^/     /'
for f in usr/bin/trust usr/bin/p11-kit; do
  echo "i3, $f : lignes contenant SOURCE_DATE_EPOCH $(strings -a "$D/racine/m/i3/$f" | grep -c SOURCE_DATE_EPOCH || true)"
done
echo "i3, update-ca-trust, ligne java-cacerts : $(grep -c 'trust extract --format=java-cacerts' "$D/racine/m/i3/usr/bin/update-ca-trust")"

echo "## 2. S calculé sur les fichiers rpm, avant toute installation"
n=$(wc -l < "$D/racine/m/liste")
# shellcheck disable=SC2046
q /usr/bin/rpm -qp --nosignature --qf '%{BUILDTIME}\n[%{FILEMTIMES}\n]' $(cat "$D/racine/m/liste") 2> "$D/complements3-qp.err" \
  | grep -E '^[0-9]+$' | sort -n | tail -n 1 > "$D/complements3-S"
SQP=$(cat "$D/complements3-S")
echo "fichiers lus : $n ; erreurs de rpm -qp : $(wc -l < "$D/complements3-qp.err") lignes"
echo "S par rpm -qp : $SQP ($(date -u -d "@$SQP" +%FT%TZ)) ; S du banc : $SBANC ; égaux : $([ "$SQP" = "$SBANC" ] && echo oui || echo non)"

echo "## 3. ordre des INSTALLTIME de i3 et ordre de la transaction (journal de dnf de i3)"
q /usr/bin/rpm --root=/m/i3 -qa --qf '%{INSTALLTIME} %|EPOCH?{%{EPOCH}:}:{}|%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' > "$D/complements3-installtime"
python3 -I - "$D/complements3-installtime" "$D/dnf-3.log" <<'PY'
import re, sys
it = sorted((int(a), b) for a, b in (l.split() for l in open(sys.argv[1], encoding='utf-8')))
tx = []
for l in open(sys.argv[2], encoding='utf-8', errors='replace'):
    m = re.match(r'^\s+Installing\s+:\s+(\S+)\s+(\d+)/(\d+)\s*$', l)
    if m:
        tx.append((int(m.group(2)), m.group(1)))
tx.sort()
print(f'paquets par INSTALLTIME : {len(it)} ; lignes « Installing » du journal : {len(tx)} ; rangs du journal 1 à {len(tx)} sans trou : {[r for r, _ in tx] == list(range(1, len(tx) + 1))}')
print(f'INSTALLTIME distincts : {len({t for t, _ in it})} ; de {it[0][0]} à {it[-1][0]}')
a, b = [n for _, n in it], [n for _, n in tx]
print(f'mêmes noms : {sorted(a) == sorted(b)} ; même ordre : {a == b}')
d = [(i + 1, x, y) for i, (x, y) in enumerate(zip(a, b)) if x != y]
print(f'rangs où les deux ordres diffèrent : {len(d)}')
for r, x, y in d[:10]:
    print(f'     rang {r} : INSTALLTIME {x} ; journal {y}')
PY
echo "# fin $(date -u +%FT%TZ)"
