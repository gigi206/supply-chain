#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # ok et ko ne échouent jamais ; scripts de unshare entre apostrophes voulus
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : cas refusés de construire-racine-rpm, au banc (hôte seul, hors ligne), préparés à sec le 19/11/2026.
# Prédictions RZ1 à RZ8 : m1b-predictions.md, commitées avant. Les scripts de construction sont ceux que prealables a rendus sous
# m1bt3 (script-co.sh 956e39c2…, script-cb.sh cad7f550…), relus au sha256 ; un cas change une seule chose (une ligne du script ou
# un octet d'une entrée) et le motif du refus est confronté à la garde visée. Chaque cas a sa racine de l'amorce extraite à neuf
# et ses entrées propres : liens durs quand rien n'est altéré, copie réelle sinon (les bancs du 18/11 restent intacts, relus à la
# fin). Même chroot que l'étape banc de m1b-builders.sh (unshare -n, entrées en lecture seule). Ni cluster, ni Zot, ni réseau.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-refus-banc.sh < /dev/null > poc/bricks/05-rpm-mock/resultats/m1b-refus-banc.log 2>&1
set -euo pipefail
export LC_ALL=C
umask 022
G=$(git rev-parse --show-toplevel)
T=$HOME/.cache/supply-chain-poc/08/travail/m1bt3-05   # rendu de prealables sous m1bt3 : lecture seule
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256
COUCHE_AMORCE=99c753a880cc03bbe9da8bf6e354c8ba2d99f19058e87b8a55b6487ffcf52f8a
COUCHE_BOOT=812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09
BANC_O=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/outils/m
BANC_B=$HOME/.cache/supply-chain-poc/05/m1b-boot-20261118T214226Z/outils/m
R_O=7c07083cd7bee149d391180633ad9cca6c82c7ad0dfa5c6bf248acad0b1ef9b7
R_B=b063feb3206deb3f1c0ad4eb7b497d683693967d194c7fdd366a2b0094823348
RPM_B=miroir/baseos97/Packages/d/dbus-libs-1.12.20-8.el9.x86_64.rpm
nko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; nko=$((nko + 1)); }
filtre() { sed -E -e 's/<[^>]*@[^>]*>/<adresse retirée>/g' -e '/jeton\|token/I c\[ligne masquée : motif jeton|token]'; }
echo "# m1b-refus-banc.sh, début $(date -u +%FT%TZ) ; HEAD $(git -C "$G" rev-parse --short=12 HEAD)"
D=$HOME/.cache/supply-chain-poc/05/m1b-refus-banc-$(date -u +%Y%m%dT%H%M%SZ)   # dossier neuf, jamais réutilisé
[ ! -e "$D" ] || { echo "KO   $D existe" >&2; exit 1; }
mkdir -p "$D"
echo "dossier : $D ; place libre de /home : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB"
for f in "script-co.sh 956e39c260a74aac9c9f71639af15ca4acc9986cf6ad52d18dddbac90ec2fee4" "script-cb.sh cad7f5501dfe61a370baff4a44e56c7c8bb9a3e739e428294a5073b2221b541c"; do
  read -r n s <<< "$f"
  [ "$(sha256sum < "$T/$n" | cut -c1-64)" = "$s" ] && ok "$n rendu sous m1bt3 : sha256 ${s:0:16}…" || { echo "KO   $n : sha256 inattendu" >&2; exit 1; }
done
sb_avant=$( (cd "$BANC_B" && find miroir cles -type f | sort | xargs sha256sum; sha256sum < "$OCI/$COUCHE_BOOT") | sha256sum | cut -c1-64)
so_avant=$( (cd "$BANC_O" && find miroir cles -type f | sort | xargs sha256sum) | sha256sum | cut -c1-64)

entrees() { # cas o|b copie|liens : entrées du cas, comme le prefetch les écrit (miroir/, cles/, couche.tar.gz pour b)
  local m; [ "$2" = o ] && m=$BANC_O || m=$BANC_B
  mkdir -p "$D/$1/entrees"
  if [ "$3" = copie ]; then cp -a "$m/miroir" "$m/cles" "$D/$1/entrees/"; else cp -al "$m/miroir" "$m/cles" "$D/$1/entrees/"; fi
  if [ "$2" = b ]; then if [ "$3" = copie ]; then cp "$OCI/$COUCHE_BOOT" "$D/$1/entrees/couche.tar.gz"; else ln "$OCI/$COUCHE_BOOT" "$D/$1/entrees/couche.tar.gz"; fi; fi
  (cd "$D/$1/entrees" && find . -type f | sed 's|^\./||' | sort | xargs sha256sum) | cmp -s - "$T/attendu-$2.sha256" \
    && echo "     entrées du cas $1 = entrées attendues du prefetch ($3)" || { echo "KO   entrées du cas $1" >&2; exit 1; }
}
alterer() { # cas chemin : un octet inversé au milieu d'une copie réelle (jamais un lien dur)
  local f=$D/$1/entrees/$2 a
  [ "$(stat -c %h "$f")" = 1 ] || { echo "KO   $2 : lien dur, altération refusée" >&2; exit 1; }
  a=$(sha256sum < "$f" | cut -c1-64)
  chmod u+w "$f"   # la copie garde le mode du cache OCI (0444) ; jamais un lien dur, contrôlé ci-dessus
  python3 -I -c 'import sys; f = open(sys.argv[1], "r+b"); f.seek(0, 2); n = f.tell() // 2; f.seek(n); b = f.read(1); f.seek(n); f.write(bytes([b[0] ^ 0xFF]))' "$f"
  echo "     altéré : $2, un octet au milieu ; sha256 ${a:0:16}… devient $(sha256sum < "$f" | cut -c1-16)…"
}
script_cas() { # cas o|b ancienne nouvelle : script du cas, une seule ligne changée (contrôlée), ou tel quel si ancienne = -
  mkdir -p "$D/$1/s"
  if [ "$3" = - ]; then cp "$T/script-c$2.sh" "$D/$1/s/script.sh"; return; fi
  [ "$(grep -cxF "$3" "$T/script-c$2.sh")" = 1 ] || { echo "KO   ligne absente ou en double : $3" >&2; exit 1; }
  awk -v a="$3" -v n="$4" '$0 == a {print n; next} {print}' "$T/script-c$2.sh" > "$D/$1/s/script.sh"
  [ "$(diff "$T/script-c$2.sh" "$D/$1/s/script.sh" | grep -c '^[<>]')" = 2 ] || { echo "KO   script du cas $1 : plus d'une ligne changée" >&2; exit 1; }
  echo "     script : « $3 » devient « $4 »"
}
jouer() { # cas : chroot dans une racine de l'amorce extraite à neuf ; code rendu dans $D/<cas>/code
  local c=$1 r=0
  unshare --map-auto --map-root-user bash -c 'mkdir "$1" && tar -xzf "$2" -C "$1" --numeric-owner' _ "$D/$c/r" "$OCI/$COUCHE_AMORCE" \
    || { echo "KO   extraction de l'amorce ($c)" >&2; exit 1; }
  mkdir -p "$D/$c/sortie" "$D/$c/tmp" "$D/$c/w"
  unshare --map-auto --map-root-user -n -m -p --fork bash -c 'set -e; r=$1; e=$2; s=$3; t=$4; c=$5; w=$6
    mkdir -p "$r/workspace/entrees" "$r/workspace/sortie" "$r/w" "$r/s"
    mount --rbind /dev "$r/dev"; mount -t proc proc "$r/proc"
    mount --bind "$e" "$r/workspace/entrees"; mount -o remount,bind,ro "$r/workspace/entrees"
    mount --bind "$s" "$r/workspace/sortie"; mount --bind "$w" "$r/w"; mount --bind "$t" "$r/tmp"
    mount --bind "$c" "$r/s"; mount -o remount,bind,ro "$r/s"
    exec chroot "$r" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin /bin/bash /s/script.sh' _ \
    "$D/$c/r" "$D/$c/entrees" "$D/$c/sortie" "$D/$c/tmp" "$D/$c/s" "$D/$c/w" > "$D/$c/journal" 2>&1 || r=$?
  echo "$r" > "$D/$c/code"
  filtre < "$D/$c/journal" | grep -v '^     tmpfs /w\|^     pic du tmpfs' | sed 's/^/        /'
}
verdict() { # cas libellé attendu(0|motif) [ligne-qui-doit-exister] : code, motif du refus, sorties absentes
  local c=$1 r k
  r=$(cat "$D/$c/code"); k=$(grep -c '^KO   ' "$D/$c/journal" || true)
  if [ "$3" = 0 ]; then
    [ "$r" = 0 ] && [ "$k" = 0 ] && [ -s "$D/$c/sortie/image.tar" ] && ok "$2 : code 0, résultat $(cat "$D/$c/tmp/resultat")" \
      || ko "$2 : code $r, $k ligne(s) KO, image.tar $([ -s "$D/$c/sortie/image.tar" ] && echo présente || echo absente)"
    return
  fi
  if [ "$r" != 0 ] && [ "$k" = 1 ] && [ "$(grep '^KO   ' "$D/$c/journal")" = "KO   $3" ]; then ok "$2 : code $r, refus « $3 »"
  else ko "$2 : code $r, $k ligne(s) KO, dernière : $(grep '^KO   ' "$D/$c/journal" | tail -n 1 | cut -c1-160)"; fi
  [ ! -e "$D/$c/sortie/image.tar" ] && [ ! -s "$D/$c/tmp/resultat" ] && ok "$2 : ni image.tar ni résultat DIGEST_CONSTRUIT" \
    || ko "$2 : une sortie a été écrite malgré le refus"
  if [ -n "${4:-}" ]; then grep -qF "$4" "$D/$c/journal" && ok "$2 : la garde est atteinte après « $4 »" || ko "$2 : « $4 » absent du journal"; fi
  if [ -z "${4:-}" ]; then grep -q 'dnf-3 code' "$D/$c/journal" && ko "$2 : dnf a tourné" || ok "$2 : refus avant dnf"; fi
}
cas() { # cas o|b copie|liens ancienne nouvelle altération(-|chemin) : prépare et joue un cas
  echo "## cas $1 ($2) : début $(date -u +%FT%TZ)"
  entrees "$1" "$2" "$3"
  [ "$6" = - ] || alterer "$1" "$6"
  script_cas "$1" "$2" "$4" "$5"
  jouer "$1"
  echo "## cas $1 : code $(cat "$D/$1/code"), fin $(date -u +%FT%TZ)"
}

cas b-temoin b liens - - -
verdict b-temoin "RZ1 bootstrap, témoin" 0
cas b-racine b liens "RACINE='$R_B'" "RACINE='$R_O'" -
verdict b-racine "RZ2 bootstrap, racine fixée fausse" "racine différente de la valeur fixée par la pipeline ($R_O)" "racine : 241981440 octets, 11472 membres, sha256 $R_B"
cas b-rpm b copie - - "$RPM_B"
verdict b-rpm "RZ3 bootstrap, rpm altéré" "rpm altéré : baseos97 ${RPM_B##*/}"
cas b-couche b copie - - couche.tar.gz
verdict b-couche "RZ4 bootstrap, couche altérée" "couche altérée"
cas b-repomd b copie - - miroir/baseos97/repodata/repomd.xml
verdict b-repomd "RZ5 bootstrap, repomd.xml altéré" "baseos97 : repomd.xml altéré"
cas o-temoin o liens - - -
verdict o-temoin "RZ6 outillage, témoin" 0
cas o-racine o liens "RACINE='$R_O'" "RACINE='$R_B'" -
verdict o-racine "RZ7 outillage, racine fixée fausse" "racine différente de la valeur fixée par la pipeline ($R_B)" "racine : 343930880 octets, 13332 membres, sha256 $R_O"

echo "## RZ8 : bancs du 18/11 intacts"
sb_apres=$( (cd "$BANC_B" && find miroir cles -type f | sort | xargs sha256sum; sha256sum < "$OCI/$COUCHE_BOOT") | sha256sum | cut -c1-64)
so_apres=$( (cd "$BANC_O" && find miroir cles -type f | sort | xargs sha256sum) | sha256sum | cut -c1-64)
[ "$sb_avant" = "$sb_apres" ] && ok "RZ8 entrées du bootstrap et couche amont inchangées : ${sb_apres:0:16}…" || ko "RZ8 entrées du bootstrap changées"
[ "$so_avant" = "$so_apres" ] && ok "RZ8 entrées de l'outillage inchangées : ${so_apres:0:16}…" || ko "RZ8 entrées de l'outillage changées"
echo "place libre de /home après : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB ; dossier laissé : $D"
echo "# fin $(date -u +%FT%TZ) ; KO $nko"
exit $((nko > 0))
