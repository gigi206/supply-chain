#!/usr/bin/env bash
# Brique 06 : entrées de l'hôte du bloc 06 du rejeu de zéro, gardées hors de $W (modèle : m5b-rejeu.sh entree de la 05).
# Écrit le 2026-11-23 après l'arrêt du rejeu plateforme-1 dans « 06 (S4c) » : vm.sh detruire efface $W (l. 154), or le bloc 06 lit
# sous $W des fichiers que le rejeu ne produit pas (reprise-06-rejeu-23-11-predictions.md, tableau des entrées).
#   garder    AVANT LE DÉMONTAGE. Si $E06 existe : chaque fichier relu, empreinte comparée à l'épingle (jamais réécrit). Sinon :
#             copie depuis $W, empreintes comparées avant et après. Échec si une entrée manque ou diffère : rien n'est démonté.
#   replacer  AVANT « 06 (S4c) ». Copie de $E06 vers $W (dossiers créés), Packages régénéré par xz -dc, empreintes comparées.
#             Un fichier déjà présent sous $W est comparé, pas réécrit.
# Ce qui n'est pas gardé : s1-06/racine.tar et s2-06/chroot.tar (lus par s4a.sh comparaison seulement, hors rejeu) ;
# s4d-06/digest-attendu (refait par « 06 (S4d, prealables) ») ; les identifiants de Zot (s1-06/zot.json, docker/, refaits par S1).
# Usage (racine du dépôt) : poc/bricks/06-deb-sbuild/rejeu-entrees.sh garder|replacer
set -uo pipefail
export LC_ALL=C
W=${CONFIANCE_DIR:-$HOME/.cache/supply-chain-poc/08}/travail
E06=${E06:-$HOME/.cache/supply-chain-poc/06/rejeu-entrees}
# chemin relatif à $W, sha256 attendu
ENTREES=(
  "s1-06/hote/InRelease 0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675"   # S1 prealables, signataires vérifiés
  "s1-06/hote/Packages.xz 7778d3e3f303b7ddb8ce0fe7c8d57473a076c6bf2e8f241f75421d2396352498" # contrôlé par l'InRelease (S4c verrou)
  "s3-06/build-1/sample-app_1.0.0-2_amd64.deb f66bbeb2aba31e5220b332ff3941697dce7660259aa182047a58e77f4f51892b"   # DEB_SHA de s4d.sh
)
PACKAGES_SHA=4f2c68d67001d595fbd343f6dbad44468953a51c4d9dec3a4803249f6e295940   # s1-06/Packages = xz -dc hote/Packages.xz
KO=0
sha() { sha256sum < "$1" 2> /dev/null | cut -c1-64; }
juge() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : ${2:0:16}…"; else echo "KO   $1 : ${2:-absent} (attendu ${3:0:16}…)"; KO=1; fi
}

garder() {
  local l c e
  if [ -d "$E06" ]; then
    echo "copie présente, relue : ${E06/#$HOME/\~}"
  else
    for l in "${ENTREES[@]}"; do read -r c e <<< "$l"; juge "\$W/$c" "$(sha "$W/$c")" "$e"; done
    [ "$KO" = 0 ] || { echo "KO   entrées absentes ou différentes sous \$W et pas de copie sous ${E06/#$HOME/\~} : rien n'est démonté"; return 1; }
    (umask 077 && mkdir -p "$E06")
    for l in "${ENTREES[@]}"; do read -r c e <<< "$l"; mkdir -p "$E06/$(dirname "$c")"; cp "$W/$c" "$E06/$c"; done
    echo "copie faite : ${E06/#$HOME/\~} ($(find "$E06" -type f | wc -l) fichiers)"
  fi
  for l in "${ENTREES[@]}"; do read -r c e <<< "$l"; juge "copie $c" "$(sha "$E06/$c")" "$e"; done
  [ "$KO" = 0 ]
}

replacer() {
  local l c e
  [ -d "$E06" ] || { echo "KO   copie absente : ${E06/#$HOME/\~} (garder n'a pas tourné)"; return 1; }
  for l in "${ENTREES[@]}"; do
    read -r c e <<< "$l"
    if [ -e "$W/$c" ]; then echo "déjà présent, comparé : \$W/$c"
    else mkdir -p "$W/$(dirname "$c")" && cp "$E06/$c" "$W/$c" && chmod 0644 "$W/$c"; fi
    juge "\$W/$c" "$(sha "$W/$c")" "$e"
  done
  [ -e "$W/s1-06/Packages" ] && echo "déjà présent, comparé : \$W/s1-06/Packages" || xz -dc "$W/s1-06/hote/Packages.xz" > "$W/s1-06/Packages"
  juge "\$W/s1-06/Packages (xz -dc de Packages.xz)" "$(sha "$W/s1-06/Packages")" "$PACKAGES_SHA"
  [ "$KO" = 0 ]
}

case ${1:-} in
  garder|replacer) date -u "+# rejeu-entrees.sh $1, %Y-%m-%dT%H:%M:%SZ"; "$1"; r=$?; [ "$r" = 0 ] && echo "bilan : tenu" || echo "bilan : KO"; exit "$r" ;;
  *) echo "usage : $0 garder|replacer" >&2; exit 2 ;;
esac
