#!/usr/bin/env bash
# Brique 07a, G7 : relevé qui replanifie la tâche « première suppression réelle de Zot » après S5b (décision du propriétaire du
# 12/11/2026, « Oui, avance S5b » ; README de la 08, additif du même jour). Préparé à sec le 12/11/2026 à partir de 14:45:38 UTC,
# NON LANCÉ. Lecture seule, à lancer après S5b, sur accord nommé. Prédictions et consigne de la tâche : resultats/g7-replanification.md.
# Corrigé à sec le 12/11/2026 à partir de 14:50:52 UTC, NON LANCÉ, avant tout accord : dossier racine lu dans la configuration de la VM
# (et comparé au dépôt) au lieu d'être écrit en dur ; dossier absent ou find en échec signalés par un KO, au lieu d'un arrêt muet.
#   releve   sc-stockage, lecture seule (ssh, sudo pour lire le rootDirectory de Zot) : démarrage de zot.service, configuration de rétention et de
#            gc lue sur la VM et comparée au dépôt ; par dépôt de builds/scan/** et pour vulndb/grype : nombre de blobs, plus ancien et
#            plus récent (date de modification) ; calcul, sans mesure, de la première suppression possible (plus ancien blob de
#            builds/scan/** + delay), du premier balayage qui la suit (démarrage de Zot + k × gcInterval) et de l'heure proposée
#            pour la tâche (balayage + 45 min, comme le 06/11 : balayage attendu vers 15:15 UTC, tâche à 16:00 UTC)
# Rien n'est écrit sur la VM ni dans Zot ; la tâche planifiée n'est pas touchée par ce script.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/07a-sbom-grype/g7-replanifier.sh releve   (journal : resultats/g7-replanifier-releve.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
CONF_DEPOT=$here/../08-trust-plane/stockage/zot.json
MARGE_S=2700   # 45 min entre le début du balayage et la tâche, comme le 06/11 (15:15 puis 16:00 UTC)
T=$W/g7-replanifier
CHAMPS='{rootDirectory: .storage.rootDirectory, gc: .storage.gc, gcDelay: .storage.gcDelay, gcInterval: .storage.gcInterval, retention: .storage.retention}'
mkdir -p "$T"

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
duree_s() { # 336h, 24h, 1h, 30m → secondes (formes employées par zot.json)
  case $1 in *h) echo $(( ${1%h} * 3600 )) ;; *m) echo $(( ${1%m} * 60 )) ;; *s) echo "${1%s}" ;; *) echo "KO   durée inconnue : $1" >&2; exit 1 ;; esac
}

etape_releve() {
  local z d g o k s b r
  echo "## Zot sur sc-stockage"
  z=$(sur sc-stockage 'systemctl show zot.service -p ActiveEnterTimestamp --value' </dev/null)
  echo "zot.service démarré : $z"
  date -u -d "$z" +%s > "$T/demarrage.s"
  echo "démarrage en UTC : $(date -u -d "@$(cat "$T/demarrage.s")" +%Y-%m-%dT%H:%M:%SZ)"
  echo "## configuration de rétention et de gc, VM comparée au dépôt"
  sur sc-stockage 'sudo cat /etc/zot/config.json' </dev/null \
    | jq -c "$CHAMPS" > "$T/conf-vm.json"   # zot.json versionné, sans secret ; seuls ces champs sont gardés
  jq -c "$CHAMPS" "$CONF_DEPOT" > "$T/conf-depot.json"
  attendu "configuration de rétention et de gc identique au dépôt" "$(cmp -s "$T/conf-vm.json" "$T/conf-depot.json" && echo oui || echo non)" oui
  r=$(jq -r '.rootDirectory' "$T/conf-vm.json")
  [[ $r =~ ^/[A-Za-z0-9/_.-]+$ ]] || { echo "KO   rootDirectory inattendu : $r" >&2; exit 1; }
  d=$(jq -r '.retention.delay' "$T/conf-depot.json"); g=$(jq -r '.gcInterval' "$T/conf-depot.json")
  echo "rootDirectory : $r ; delay : $d ; gcInterval : $g"
  echo "## blobs par dépôt (date de modification, UTC)"
  sur sc-stockage "e=0; for x in '$r/builds/scan' '$r/vulndb/grype'; do
      if sudo test -d \"\$x\"; then sudo find \"\$x\" -path '*/blobs/sha256/*' -type f -printf '%T@ %p\n' || { echo \"KO   find en échec sur \$x\" >&2; e=1; }
      else echo \"ABSENT \$x\" >&2; fi
    done; exit \$e" </dev/null > "$T/blobs.txt" \
    || { echo "KO   relevé des blobs en échec (motif ci-dessus)" >&2; exit 1; }
  python3 -I - "$T/blobs.txt" "$r" <<'PY'
import sys, datetime as D
racine = sys.argv[2].rstrip('/') + '/'
par = {}
for l in open(sys.argv[1], encoding='utf-8'):
    t, p = l.split(' ', 1)
    depot = p.strip().split(racine, 1)[1].split('/blobs/', 1)[0]
    par.setdefault(depot, []).append(float(t))
f = lambda x: D.datetime.fromtimestamp(x, D.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
for depot, v in sorted(par.items()):
    print(f'{depot} : {len(v)} blob(s), plus ancien {f(min(v))}, plus récent {f(max(v))}')
scan = [x for d, v in par.items() if d.startswith('builds/scan/') for x in v]
print(f'plus ancien de builds/scan/** : {f(min(scan)) if scan else "aucun"}')
open(sys.argv[1] + '.min', 'w').write(str(int(min(scan))) if scan else '')
PY
  o=$(cat "$T/blobs.txt.min")
  [ -n "$o" ] || { echo "KO   aucun blob sous builds/scan : rien à replanifier avant un premier scan" >&2; exit 1; }
  echo "## calcul (pas une mesure ; un redémarrage de Zot le déplacerait)"
  s=$(cat "$T/demarrage.s")
  echo "première suppression possible : $(date -u -d "@$((o + $(duree_s "$d")))" +%Y-%m-%dT%H:%M:%SZ) (plus ancien blob + $d)"
  k=$(( (o + $(duree_s "$d") - s + $(duree_s "$g") - 1) / $(duree_s "$g") ))
  b=$(( s + k * $(duree_s "$g") ))
  echo "premier balayage qui la suit : $(date -u -d "@$b" +%Y-%m-%dT%H:%M:%SZ) (démarrage + $k × $g)"
  echo "heure proposée pour la tâche : $(date -u -d "@$((b + MARGE_S))" +%Y-%m-%dT%H:%M:%SZ) (balayage + $((MARGE_S / 60)) min)"
}

lancer g7-replanifier "07a G7 replanification" "$@"
