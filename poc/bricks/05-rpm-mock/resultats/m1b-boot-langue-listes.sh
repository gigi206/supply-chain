#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b (19/11/2026) : complément de m1b-boot-langue.sh, dont la comparaison des listes rpm -qa avec S1 n'a pas eu lieu
# (cmp absent de l'amorce : « cmp: command not found »). Sur l'hôte, en lecture seule : listes avant et après des deux installations
# contre celle de S1 ; côté et chemin des membres présents d'un seul côté entre z-all.tar et z-en.tar ; membres de locale de la base
# nue (n1.tar du banc du 18/11) que z-en.tar n'a plus.
set -euo pipefail
export LC_ALL=C
N=$HOME/.cache/supply-chain-poc/05/m1b-boot-langue-20261119T125140Z      # dossier du banc de 12:51:40 UTC : lecture seule
X=$HOME/.cache/supply-chain-poc/05/m1b-boot-20261118T214226Z/archives    # n1.tar, base nue du 18/11 : lecture seule
echo "# m1b-boot-langue-listes.sh, début $(date -u +%FT%TZ)"
for x in en all; do
  echo "avant-$x : $(wc -l < "$N/avant-$x.txt") lignes ; après-$x : $(wc -l < "$N/apres-$x.txt") lignes"
  cmp -s "$N/apres-$x.txt" "$N/s1-apres.txt" && echo "OK   liste rpm -qa après ($x) = celle de S1 ($(wc -l < "$N/s1-apres.txt") lignes)" \
    || { echo "ÉCART liste rpm -qa après ($x) différente de celle de S1"; diff "$N/s1-apres.txt" "$N/apres-$x.txt" | head -n 20 || true; }
done
cmp -s "$N/avant-en.txt" "$N/avant-all.txt" && echo "OK   listes avant (en, all) identiques" || echo "ÉCART listes avant (en, all) différentes"
python3 -I - "$N/z-all.tar" "$N/z-en.tar" "$X/n1.tar" <<'PY'
import sys, tarfile
def noms(p):
    with tarfile.open(p, 'r:') as t:
        return {m.name for m in t}
a, e, n = (noms(p) for p in sys.argv[1:4])
sa, se = sorted(a - e), sorted(e - a)
loc = lambda s: sum(1 for x in s if x.startswith('./usr/share/locale/'))
print(f'seulement dans z-all : {len(sa)}, dont {loc(sa)} sous usr/share/locale et {sum(1 for x in sa if x.endswith(".mo"))} fichiers .mo')
print(f'seulement dans z-en : {len(se)}')
for x in sa:
    if not x.startswith('./usr/share/locale/'):
        print(f'     seulement dans z-all, hors locale : {x}')
print('domaines .mo seulement dans z-all : ' + ', '.join(f'{d} {sum(1 for x in sa if x.endswith("/" + d))}' for d in sorted({x.rsplit("/", 1)[1] for x in sa if x.endswith(".mo")})))
ln = {x for x in n if x.startswith('./usr/share/locale/') and x.endswith('.mo')}
perdus = sorted(ln - e)
print(f'base nue n1 : {len(ln)} fichiers .mo sous usr/share/locale ; absents de z-en : {len(perdus)} ; absents de z-all : {len(ln - a)}')
print('domaines .mo de la base absents de z-en : ' + ', '.join(f'{d} {sum(1 for x in perdus if x.endswith("/" + d))}' for d in sorted({x.rsplit("/", 1)[1] for x in perdus})))
PY
echo "# fin $(date -u +%FT%TZ)"
