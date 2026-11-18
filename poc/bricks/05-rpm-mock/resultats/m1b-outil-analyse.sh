#!/usr/bin/env bash
# Brique 05, M1b, banc de l'outillage : lecture des écarts du passage corrigé (18/11/2026, 20:57:14 à 20:59:22 UTC).
#   1. etc/machine-id de i5, i6, i7 et de racine.tar : taille et égalité seulement (contenu non imprimé) ; lignes des journaux de dnf
#      qui citent machine-id ou systemd ; lignes « scriptlet », « warning » ou « error » de dnf-5.log (adresses retirées).
#   2. Langues : membres sous usr/share/locale dans a5 et racine.tar ; %_install_langs et override_install_langs dans la racine
#      d'outils (99790c13), seule lisible ici (l'amorce ed654c69 n'est pas en local).
#   3. etc/shadow et etc/shadow- : troisième champ (jours) seulement, i5 et racine.tar ; mode de var/lib/dnf dans a5 et racine.tar.
# Lecture seule ; hors ligne (unshare -n) ; rien n'est installé.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-outil-analyse.sh > poc/bricks/05-rpm-mock/resultats/m1b-outil-analyse.log 2>&1
set -uo pipefail
export LC_ALL=C
D=$HOME/.cache/supply-chain-poc/05/m1b-outil-20261118T205714Z
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05   # jamais listé : racine.tar seule y est lue
ns() { unshare --map-auto --map-root-user -n "$@"; }
masque() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
echo "# m1b-outil-analyse.sh, début $(date -u +%FT%TZ)"
[ -d "$D/outils/m/i5" ] || { echo "KO   banc absent : $D" >&2; exit 1; }
echo "## 1. machine-id"
mi() { python3 -I -c 'import hashlib, sys; b = sys.stdin.buffer.read(); print(f"{len(b)} octet(s), empreinte courte {hashlib.sha256(b).hexdigest()[:12]}")'; }
for i in 5 6 7; do echo "i$i : $(ns cat "$D/outils/m/i$i/etc/machine-id" | mi)"; done
echo "racine.tar : $(tar -xOf "$T/racine.tar" ./etc/machine-id | mi)"
for i in 5 7; do
  echo "dnf-$i.log, lignes citant machine-id ou systemd-machine : $(grep -ci 'machine-id\|systemd-machine' "$D/dnf-$i.log")"
  grep -i 'machine-id\|systemd-machine' "$D/dnf-$i.log" | head -n 5 | masque | sed 's/^/     /'
done
echo "dnf-5.log, lignes « scriptlet », « warning » ou « error » :"
grep -Ei 'scriptlet|(^|[^-[:alnum:]])(warning|error)' "$D/dnf-5.log" | masque | cut -c1-200 | sed 's/^/     /'
echo "## 2. langues"
python3 -I - "$D/archives/a5.tar" "$T/racine.tar" <<'PY'
import sys, tarfile
for p in sys.argv[1:]:
    with tarfile.open(p, 'r:') as t:
        n = [m.name for m in t if m.name.startswith('./usr/share/locale/')]
    print(f'{p.rsplit("/", 1)[-1]} : {len(n)} membre(s) sous usr/share/locale ; fichiers .mo : {sum(x.endswith(".mo") for x in n)}')
PY
echo "racine d'outils, fichiers de macros de rpm sous etc/rpm : $(ls "$D/outils/etc/rpm" 2>/dev/null | tr '\n' ' ')"
echo "racine d'outils, %_install_langs : $(grep -rh '_install_langs' "$D/outils/etc/rpm" "$D/outils/usr/lib/rpm/macros.d" 2>/dev/null | tr '\n' ' ' || true)"
echo "racine d'outils, override_install_langs dans etc/dnf/dnf.conf : $(grep -c 'override_install_langs' "$D/outils/etc/dnf/dnf.conf" 2>/dev/null || echo absent)"
echo "racine.tar, membres sous etc/rpm : $(tar -tf "$T/racine.tar" | grep '^./etc/rpm/' | tr '\n' ' ')"
echo "## 3. shadow et var/lib/dnf"
for f in shadow shadow-; do
  echo "i5 etc/$f, troisième champ : $(ns cut -d: -f3 "$D/outils/m/i5/etc/$f" | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
  echo "racine.tar etc/$f, troisième champ : $(ns tar -xOf "$T/racine.tar" "./etc/$f" | cut -d: -f3 | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
done
echo "jour du 17/11/2026 : $(( $(date -u -d 2026-11-17 +%s) / 86400 )) ; jour de S : $(( 1793914619 / 86400 ))"
python3 -I - "$D/archives/a5.tar" "$T/racine.tar" <<'PY'
import sys, tarfile
for p in sys.argv[1:]:
    with tarfile.open(p, 'r:') as t:
        m = t.getmember('./var/lib/dnf')
    print(f'{p.rsplit("/", 1)[-1]} : var/lib/dnf mode {oct(m.mode)}')
PY
echo "# fin $(date -u +%FT%TZ)"
