#!/usr/bin/env bash
# Brique 06, jalon S4c (ordre décidé par le propriétaire le 10/11/2026, 22:21:12 UTC ; verrou avec debian/, 22:20:23 UTC ; marked
# par la plateforme pour le deb, 11/11/2026, 16:19:27 UTC) : artefact de packaging du deb, publié par l'hôte dans Zot comme
# web/dist (construction.sh de la 08). Il contient poc/packaging/debian/ inchangé et le verrou poc/packaging/verrou-deb.txt,
# au format de builder/paquets.txt, que prefetch-deb lira en S4b. Prédictions : resultats/s4c-predictions.md, commitées avant.
#   verrou   hôte seul, hors ligne : InRelease (sha256 vérifié en S1), Packages.xz contrôlé par l'InRelease, Packages égal à
#            xz -dc Packages.xz ; Installed-Build-Depends du buildinfo de S2 rapprochés de Packages ; verrou écrit, puis comparé
#            à la fermeture de S2 (s2-fermeture-attendue.txt) ; artefact poussé deux fois dans deux layouts OCI locaux (C1 à C4)
#   publier  écriture dans Zot (compte poc-ecriture), sur accord nommé : deux poussées, digest égal à celui des layouts locaux ;
#            artefact tiré par digest dans un répertoire vide, fichiers égaux au dépôt, mode de debian/rules relevé (C5 à C7)
# Rien n'est supprimé dans Zot (pas de droit de suppression) : le dépôt entrees/sample-app/packaging-deb est définitif.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4c.sh <étape>…   (journal : resultats/s4c-<étape>.log)
set -euo pipefail
export LC_ALL=C

h06=$(cd "$(dirname "$0")" && pwd)
here=$h06/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, auth_zot, lancer
R=$h06/resultats
PKG=$repo/poc/packaging
VERROU=$PKG/verrou-deb.txt
T=$W/s4c-06
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets, même en cas d'échec
umask 022

INRELEASE=0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675   # s1-prealables.log : signataires vérifiés
HOTE=$W/s1-06/hote            # InRelease et Packages.xz tirés en S1 (étape prealables de s1.sh)
PACKAGES=$W/s1-06/Packages    # égal à xz -dc hote/Packages.xz
BUILDINFO=$R/s2-sample-app_1.0.0-1_amd64.buildinfo
FERMETURE_S2=$R/s2-fermeture-attendue.txt
DEPOT=entrees/sample-app/packaging-deb
TYPE=application/vnd.supply-chain.packaging-deb.v1
CREE=1970-01-01T00:00:00Z

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
fichiers() { # liste triée des fichiers de l'artefact, relatifs à poc/packaging
  (cd "$PKG" && { find debian -type f; echo verrou-deb.txt; } | sort)
}
pousser() { # cible oras (--oci-layout dir:tag, ou référence de registre) [options…] : digest du manifeste
  local cible=$1; shift
  local f=() x
  while IFS= read -r x; do f+=("$x:$TYPE.file"); done < <(fichiers)
  (cd "$PKG" && oras push "$@" --no-tty --format go-template='{{.digest}}' --artifact-type "$TYPE" \
    --annotation "org.opencontainers.image.created=$CREE" "$cible" "${f[@]}")
}

etape_verrou() {
  attendu "C1 InRelease (sha256 de S1)" "$(sha256sum < "$HOTE/InRelease" | cut -d' ' -f1)" "$INRELEASE"
  local xz
  xz=$(awk '/^SHA256:/ {s = 1; next} /^[^ ]/ {s = 0} s && $3 == "main/binary-amd64/Packages.xz" {print $1, $2}' "$HOTE/InRelease")
  attendu "C1 Packages.xz conforme à l'InRelease (sha256 taille)" "$(sha256sum < "$HOTE/Packages.xz" | cut -d' ' -f1) $(stat -c %s "$HOTE/Packages.xz")" "$xz"
  attendu "C1 Packages égal à xz -dc Packages.xz" "$(xz -dc "$HOTE/Packages.xz" | cmp - "$PACKAGES" && echo égal)" "égal"

  # C2 : Installed-Build-Depends de S2 → « nom version » ; rapprochement avec Packages (amd64 ou all), une seule entrée chacun
  awk '/^Installed-Build-Depends:/ {f = 1; next} f && /^[^ ]/ {f = 0}
    f {gsub(/[(),=]/, " "); print $1, $2}' "$BUILDINFO" | sort > "$T/ibd"
  attendu "C2 Installed-Build-Depends (nombre, distincts)" "$(wc -l < "$T/ibd") $(cut -d' ' -f1 "$T/ibd" | sort -u | wc -l)" "162 162"
  python3 -I - "$PACKAGES" "$T/ibd" "$T/verrou" <<'EOF'
import sys
paquets, ibd, sortie = sys.argv[1:]
voulu = dict(l.split() for l in open(ibd))
trouve = {}
for bloc in open(paquets, encoding='utf-8').read().split('\n\n'):
    c = {}
    for l in bloc.split('\n'):
        if ': ' in l and not l.startswith(' '):
            k, v = l.split(': ', 1); c[k] = v
    p = c.get('Package')
    if p in voulu and c.get('Version') == voulu[p] and c.get('Architecture') in ('amd64', 'all'):
        trouve.setdefault(p, []).append(f"{p} {c['Version']} {c['Architecture']} {c['SHA256']} {c['Size']} {c['Filename']}")
manque = sorted(set(voulu) - set(trouve)); doubles = sorted(p for p, v in trouve.items() if len(v) > 1)
for p in manque: print(f'KO   {p} {voulu[p]} absent de Packages')
for p in doubles: print(f'KO   {p} {voulu[p]} présent {len(trouve[p])} fois')
open(sortie, 'w').write(''.join(trouve[p][0] + '\n' for p in sorted(trouve) if p not in doubles))
print(f'{"OK  " if not manque and not doubles else "KO  "} C2 verrou rapproché de Packages : {len(trouve)} paquets, '
      f'{len(manque)} absent(s), {len(doubles)} en double')
sys.exit(1 if manque or doubles else 0)
EOF
  if [ -e "$VERROU" ]; then
    attendu "C2 verrou égal à celui du dépôt" "$(cmp -s "$T/verrou" "$VERROU" && echo égal || echo différent)" égal
  else
    cp "$T/verrou" "$VERROU" && echo "verrou écrit : poc/packaging/verrou-deb.txt"
  fi
  attendu "C3 verrou égal à la fermeture de S2 (fichier sha256 taille)" \
    "$(awk '{n = split($6, c, "/"); print c[n], $4, $5}' "$VERROU" | sort | sha256sum | cut -d' ' -f1)" \
    "$(sort "$FERMETURE_S2" | sha256sum | cut -d' ' -f1)"
  echo "verrou : $(wc -l < "$VERROU") paquets, $(awk '{s += $5} END {print s}' "$VERROU") octets, sha256 $(sha256sum < "$VERROU" | cut -d' ' -f1)"

  echo "artefact : $(fichiers | paste -sd' ')"
  fichiers | (cd "$PKG" && xargs sha256sum) | sed 's/^/     /'
  rm -rf "$T/layout-1" "$T/layout-2"
  local d1 d2
  d1=$(pousser "$T/layout-1:s4c" --oci-layout)
  d2=$(pousser "$T/layout-2:s4c" --oci-layout)
  attendu "C4 deux poussées locales, même digest" "$d1" "$d2"
  echo "$d1" > "$T/digest-local"
  echo "digest attendu dans Zot : $d1"
}

etape_publier() {
  [ -s "$T/digest-local" ] || { echo "KO   étape verrou à lancer d'abord (digest local absent)" >&2; exit 1; }
  local attendu_d d1 d2
  attendu_d=$(cat "$T/digest-local")
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # compte poc-ecriture, comme web/dist (construction.sh)
  d1=$(pousser "$REG_HOTE/$DEPOT:s4c" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json")
  d2=$(pousser "$REG_HOTE/$DEPOT:s4c" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json")
  attendu "C5 deux poussées dans Zot, même digest" "$d1" "$d2"
  attendu "C5 digest Zot égal au digest local" "$d1" "$attendu_d"
  rm -rf "$T/tire" && mkdir "$T/tire"
  (cd "$T/tire" && oras pull --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json" --no-tty \
    "$REG_HOTE/$DEPOT@$d1" > /dev/null)
  attendu "C6 fichiers tirés par digest égaux au dépôt" \
    "$(cd "$T/tire" && find . -type f -printf '%P\n' | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)" \
    "$(fichiers | (cd "$PKG" && xargs sha256sum) | sha256sum | cut -d' ' -f1)"
  echo "C7 mode de debian/rules tiré : $(stat -c %a "$T/tire/debian/rules") (dans le dépôt : $(stat -c %a "$PKG/debian/rules"))"
  echo "PACKAGING_DEB=$REG/$DEPOT@$d1"
}

lancer s4c S4c "$@"
