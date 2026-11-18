#!/usr/bin/env bash
# Brique 05, M1b : lecture de l'amorce rockylinux:9.8 (ed654c69) depuis le cache OCI local de s1.sh amorce. (18/11/2026)
#   1. Manifeste, configuration et couche : présence et sha256 (blobs adressés par contenu).
#   2. Couche extraite dans un dossier neuf ; dans la racine (chroot, /dev et /proc montés, HOME=/root) :
#      versions de rpm et dnf ; rpm -E '%_install_langs' ; fichiers de /etc/rpm et /usr/lib/rpm/macros.d qui citent install_langs ;
#      /etc/dnf/dnf.conf. Configuration de l'image : Env, User, Cmd (le umask n'y figure pas : il vient du lanceur).
#   3. Même lecture de %_install_langs dans la racine d'outils de 99790c13 (banc de l'outillage), pour comparaison.
# Hors ligne (unshare -n) ; rien n'est installé ; le cache n'est que lu.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-amorce-lecture.sh > poc/bricks/05-rpm-mock/resultats/m1b-amorce-lecture.log 2>&1
set -euo pipefail
export LC_ALL=C
O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux   # cache de s1.sh amorce : lecture seule
M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d                   # s1.sh, l. 169
D=$HOME/.cache/supply-chain-poc/05/m1b-amorce-$(date -u +%Y%m%dT%H%M%SZ)            # dossier neuf
OUT=$HOME/.cache/supply-chain-poc/05/m1b-outil-20261118T205714Z/outils             # racine d'outils du banc de l'outillage
ns() { unshare --map-auto --map-root-user -n "$@"; }
q() { local r=$1; shift; ns -m -p --fork bash -c 'mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || exit 97; export HOME=/root; exec chroot "$@"' _ "$r" "$@"; }
masque() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
h() { sha256sum < "$O/blobs/sha256/$1" | cut -c1-64; }
echo "# m1b-amorce-lecture.sh, début $(date -u +%FT%TZ)"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent" >&2; exit 1; }
echo "## 1. blobs"
[ "$(h $M)" = "$M" ] && echo "OK   manifeste ed654c69 : sha256 égal" || { echo "KO   manifeste" >&2; exit 1; }
read -r C L < <(python3 -I -c 'import json, sys; j = json.load(open(sys.argv[1])); assert len(j["layers"]) == 1; print(j["config"]["digest"][7:], j["layers"][0]["digest"][7:])' "$O/blobs/sha256/$M")
for x in "configuration $C" "couche $L"; do set -- $x; [ "$(h "$2")" = "$2" ] && echo "OK   $1 ${2:0:12} : sha256 égal, $(stat -c %s "$O/blobs/sha256/$2") octets" || { echo "KO   $1" >&2; exit 1; }; done
python3 -I -c 'import json, sys; c = json.load(open(sys.argv[1])); g = c.get("config", {}); print("configuration : Env", g.get("Env"), "; User", repr(g.get("User", "")), "; Cmd", g.get("Cmd"), "; créée", c.get("created"))' "$O/blobs/sha256/$C"
echo "## 2. racine de l'amorce"
mkdir -p "$D/racine"
ns tar -xf "$O/blobs/sha256/$L" -C "$D/racine" --numeric-owner --exclude='dev/*' 2>/dev/null || echo "tar code $? (fichiers spéciaux ignorés)"
mkdir -p "$D/racine/dev" "$D/racine/proc"
q "$D/racine" rpm --version
q "$D/racine" bash -c 'rpm -q --qf "%{NEVRA}\n" rpm dnf python3-dnf libsolv libdnf 2>&1'
echo "%_install_langs (amorce) : [$(q "$D/racine" rpm -E '%_install_langs')]"
echo "fichiers qui citent install_langs (amorce) :"
q "$D/racine" bash -c 'grep -rHn "install_langs" /etc/rpm /usr/lib/rpm/macros.d /etc/dnf 2>/dev/null || echo "(aucun)"' | masque | sed 's/^/     /'
echo "/etc/dnf/dnf.conf (amorce) :"
q "$D/racine" cat /etc/dnf/dnf.conf | masque | sed 's/^/     /'
echo "## 3. racine d'outils de 99790c13"
echo "%_install_langs (outils) : [$(q "$OUT" rpm -E '%_install_langs')]"
q "$OUT" bash -c 'grep -rHn "install_langs" /etc/rpm /usr/lib/rpm/macros.d /etc/dnf 2>/dev/null || echo "(aucun)"' | masque | sed 's/^/     /'
echo "racine de l'amorce laissée dans $D/racine"
echo "# fin $(date -u +%FT%TZ)"
