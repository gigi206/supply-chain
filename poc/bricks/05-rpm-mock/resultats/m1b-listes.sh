#!/usr/bin/env bash
# Brique 05, M1b : listes complètes de l'outillage et du bootstrap, retirées de la base rpm des deux racines archivées (18/11/2026).
# Hôte seul, hors ligne (unshare -n), sans cluster ni Zot ; les deux archives de l'hôte ne sont que lues.
#   1. sha256 et taille de racine.tar (étape racine de S1, 17/11) et de boot-racine.tar (étape boot_racine, 17/11).
#   2. Extraction de ./var/lib/rpm seul, dans un dossier neuf ; lecture par le rpm de la racine d'outils (couches de 99790c13).
#   3. Outillage : chaque entrée de la base rapprochée d'une ligne « rpm » de s1-racine.log (nom de fichier, dépôt, sha256) ;
#      entrées sans ligne et lignes sans entrée, nommées. Liste épinglée écrite dans m1b-listes-outillage.txt.
#   4. Pour chaque base : borne S (même formule que le troisième banc), INSTALLTID et étalement des INSTALLTIME.
# Prédictions : m1b-predictions.md (section des listes), commitées avant le lancement.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-listes.sh > poc/bricks/05-rpm-mock/resultats/m1b-listes.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
T=$HOME/.cache/supply-chain-poc/08/travail/s1-05   # jamais listé : seuls deux fichiers nommés y sont lus
B=$HOME/.cache/supply-chain-poc/05/banc-image/disque/sha256
U=$(date -u +%Y%m%dT%H%M%SZ)
D=$HOME/.cache/supply-chain-poc/05/m1b-listes-$U                 # dossier neuf, jamais effacé ni réutilisé
COUCHES=(e48fc4d689daa5ec7af47350d996f93d76a138ff7267aed6972feefe3e4526bd fd00cdb1ac39ed07d03836b05bd7c24cf435e68a2b29d63403e5dfc4610ac157)
ns() { unshare --map-auto --map-root-user -n "$@"; }
q() { ns chroot "$D/outils" "$@"; }
echo "# m1b-listes.sh, début $(date -u +%FT%TZ)"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }

echo "## 1. archives"
for a in "racine.tar 361758720 d7433a05" "boot-racine.tar 258129920 8ae17f92"; do
  set -- $a
  [ -s "$T/$1" ] || { echo "KO   $1 absente" >&2; exit 1; }
  s=$(sha256sum < "$T/$1" | cut -c1-64); t=$(stat -c %s "$T/$1")
  echo "$1 : $t octets, sha256 $s"
  [ "$t" = "$2" ] && [ "${s:0:8}" = "$3" ] && echo "OK   $1 conforme au journal de S1 ($2 octets, $3…)" || echo "KO   $1 différente du journal de S1"
done

echo "## 2. extraction de ./var/lib/rpm"
mkdir -p "$D/outils/m/outillage" "$D/outils/m/bootstrap"
for l in "${COUCHES[@]}"; do
  s=$(sha256sum < "$B/$l" | cut -c1-64)
  [ "$s" = "$l" ] || { echo "KO   couche $l : sha256 $s" >&2; exit 1; }
  echo "OK   couche $l : sha256 égal à son nom"
done
ns bash -c 'for l in "$@"; do tar -xzf "$l" -C "'"$D"'/outils" --numeric-owner --exclude="dev/*" 2>/dev/null || echo "tar code $? (fichiers spéciaux ignorés)"; done' _ "${COUCHES[@]/#/$B/}"
[ -x "$D/outils/usr/bin/rpm" ] || { echo "KO   rpm absent de la racine d'outils" >&2; exit 1; }
echo "rpm de la racine d'outils : $(q /usr/bin/rpm --version)"
for a in "racine.tar outillage" "boot-racine.tar bootstrap"; do
  set -- $a
  ns tar -xf "$T/$1" -C "$D/outils/m/$2" --numeric-owner ./var/lib/rpm
  echo "$1 : $(find "$D/outils/m/$2/var/lib/rpm" -type f | wc -l) fichier(s) extrait(s) sous var/lib/rpm : $(cd "$D/outils/m/$2/var/lib/rpm" && find . -type f | sort | tr '\n' ' ')"
done

echo "## 3. relevés des deux bases"
F='%{NAME}|%{EPOCHNUM}|%{VERSION}|%{RELEASE}|%{ARCH}|%{BUILDTIME}|%{INSTALLTIME}|%{INSTALLTID}\n'
for n in outillage bootstrap; do
  q /usr/bin/rpm --dbpath "/m/$n/var/lib/rpm" -qa --qf "$F" | sort > "$D/$n.qa" 2> "$D/$n.err"
  q /usr/bin/rpm --dbpath "/m/$n/var/lib/rpm" -qa --qf '[%{FILEMTIMES}\n]' | grep -E '^[0-9]+$' | sort -n | tail -n 1 > "$D/$n.fm"
  echo "$n : $(wc -l < "$D/$n.qa") entrée(s) ; stderr $(wc -l < "$D/$n.err") ligne(s)"
done

echo "## 4. rapprochements et bornes"
python3 -I - "$D" "$r/s1-racine.log" "$r/m1b-listes-outillage.txt" <<'PY'
import collections, datetime, re, sys
d, journal, sortie = sys.argv[1:]
h = lambda t: datetime.datetime.fromtimestamp(int(t), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
lignes = {}
for x in open(journal, encoding='utf-8'):
    m = re.match(r'^\s+rpm (\S+) (\S+\.rpm) ([0-9a-f]{64})$', x)
    if m:
        assert m.group(2) not in lignes, m.group(2)
        lignes[m.group(2)] = (m.group(1), m.group(3))
print(f'lignes « rpm » de s1-racine.log : {len(lignes)} ; par dépôt : {dict(sorted(collections.Counter(v[0] for v in lignes.values()).items()))}')
for n in ('outillage', 'bootstrap'):
    e = [x.rstrip('\n').split('|') for x in open(f'{d}/{n}.qa', encoding='utf-8') if x.strip()]
    assert all(len(x) == 8 for x in e)
    vrais = [x for x in e if x[0] != 'gpg-pubkey']
    print(f'### {n} : {len(e)} entrée(s), dont {len(e) - len(vrais)} gpg-pubkey')
    for x in e:
        if x[0] == 'gpg-pubkey':
            print(f'  gpg-pubkey {x[2]}-{x[3]} ; INSTALLTIME {h(x[6])} ; INSTALLTID {x[7]}')
    bt = max(int(x[5]) for x in vrais)
    fm = int(open(f'{d}/{n}.fm').read().strip())
    s = max(bt, fm)
    print(f'  plus grand BUILDTIME {bt} ({h(bt)}) ; plus grande FILEMTIMES {fm} ({h(fm)}) ; S = {s} ({h(s)})')
    tid = collections.Counter(x[7] for x in e)
    print(f'  INSTALLTID distincts : {len(tid)}')
    for t, c in sorted(tid.items()):
        it = sorted(int(x[6]) for x in e if x[7] == t)
        print(f'    INSTALLTID {t} ({h(t)}) : {c} entrée(s) ; INSTALLTIME de {h(it[0])} à {h(it[-1])}, {len(set(it))} valeur(s) distincte(s)')
    if n == 'outillage':
        nom = {f'{x[0]}-{x[2]}-{x[3]}.{x[4]}.rpm': x for x in vrais}
        assert len(nom) == len(vrais)
        sans_ligne = sorted(set(nom) - set(lignes)); sans_entree = sorted(set(lignes) - set(nom))
        print(f'  entrées rapprochées d\'une ligne : {len(set(nom) & set(lignes))} ; entrées sans ligne : {len(sans_ligne)} ; lignes sans entrée : {len(sans_entree)}')
        for x in sans_ligne: print(f'    entrée sans ligne : {x}')
        for x in sans_entree: print(f'    ligne sans entrée : {x}')
        with open(sortie, 'w', encoding='utf-8') as f:
            f.write('# Liste épinglée de l\'outillage (M1b), retirée de la base rpm de racine.tar (d7433a05…) le 18/11/2026 ; '
                    'dépôt, fichier et sha256 tirés de s1-racine.log ; une ligne par entrée rapprochée.\n')
            for k in sorted(set(nom) & set(lignes)):
                f.write(f'{lignes[k][0]} {k} {lignes[k][1]}\n')
        print(f'  liste écrite : m1b-listes-outillage.txt, {len(set(nom) & set(lignes))} ligne(s)')
PY
echo "# fin $(date -u +%FT%TZ)"
