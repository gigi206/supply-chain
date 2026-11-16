#!/usr/bin/env bash
# Brique 06, révision 1.0.0-2, étape lintian (étape 6 de la séquence d'après S5b) : le tag lintian
# missing-static-built-using-field-for-golang-package (sévérité info) sort pour le paquet source 1.0.0-1 et plus pour le 1.0.0-2.
# Préparé à sec le 16/11/2026 (« Oui, prépare-le ») ; prédictions resultats/lintian-predictions.md, commitées avant tout lancement.
# Décisions du propriétaire : chroot à part, même instantané (12/11/2026, 22:14:45 UTC) ; base = racine de S1 (16/11/2026) ;
# relevé de santé de lintian pour docs/04 avant tout lancement (16/11/2026).
# Tout sur l'hôte, sous ~/.cache/supply-chain-poc/06/lintian, en espace de noms utilisateur (unshare --map-auto --map-root-user) :
# rien d'installé au niveau système, rien dans le cluster ni dans Zot. Une étape par appel, chacune sur ACCORD NOMMÉ :
#   prealables  hors réseau : signataires d'InRelease (gpgv, clés de S1, empreintes épinglées) ; InRelease et Packages ; racine de
#               S1, ses listes d'apt égales à l'index vérifié, ses paquets tous dans l'index ; lintian dans l'index ; sources des
#               deux révisions (sha256 épinglés, Checksums-Sha256 des .dsc)
#   resoudre    hors réseau : racine extraite (sans les nœuds de /dev), apt-get -s install --no-install-recommends lintian dans la
#               racine ; verrou écrit dans lintian/verrou-lintian.txt (paquet, version, architecture, sha256, taille, chemin), à
#               commiter avant telecharger
#   telecharger réseau (snapshot.debian.org, https) : chaque .deb du verrou commité, sha256 et taille comparés ; reprise possible
#   installer   hors réseau : racine réextraite, .deb du verrou recontrôlés puis dpkg -i ; paquets installés = racine + verrou
#   juger       hors réseau : règle et tag relus dans le lintian installé ; debian/control des sources comparé ; lintian -I et
#               sans -I sur les deux .dsc ; jugement sur la ligne du tag (codes 0 ou 2 admis : 2 = un tag E: ; 1 = KO)
# Usage (racine du dépôt) : poc/bricks/06-deb-sbuild/lintian.sh prealables|resoudre|telecharger|installer|juger
#   (journal : resultats/lintian-<étape>.log)
set -euo pipefail
export LC_ALL=C
h06=$(cd "$(dirname "$0")" && pwd)
racine=$(cd "$h06/../../.." && pwd)
R=$h06/resultats
T=$HOME/.cache/supply-chain-poc/06/lintian
C=$T/chroot
S1=$HOME/.cache/supply-chain-poc/08/travail/s1-06
RACINE=$S1/racine.tar
RACINE_SHA=f8f221cadb6fe64ad6b3cf3a4baf6464ffe860d0cca80691dc3a47739381ca44      # mmdebstrap de S1 (s1b-racine.log l. 139)
HOTE=$S1/hote                                                                     # InRelease, Packages.xz et clés gardés par S1
INRELEASE_SHA=0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675    # s1-prealables.log
PACKAGES_SHA=4f2c68d67001d595fbd343f6dbad44468953a51c4d9dec3a4803249f6e295940     # main/binary-amd64/Packages, listé dans InRelease
CLES="B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8 04B54C3CDCA79751B16BC6B5225629DF75B188BD 41587F7DB8C774BCCF131416762F67A0B2C39DE4"
#     comme s1.sh l. 33 : archive 12/bookworm, archive 13/trixie, release 13/trixie
SNAP=20261105T000000Z
MIROIR=https://snapshot.debian.org/archive/debian/$SNAP
SOURCES_LIST="deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/$SNAP trixie main"   # celui de la racine
LISTES=var/lib/apt/lists/snapshot.debian.org_archive_debian_${SNAP}_dists_trixie
V_LINTIAN=2.122.0
SRC1=$HOME/.cache/supply-chain-poc/13a-axes12-esquisse/temoin-1.0.0-1      # témoin 1.0.0-1, copie hors dépôt du 12/11/2026
DSC1=sample-app_1.0.0-1.dsc
DSC1_SHA=9050679ed60032a2a3587b330c314717d1d781d46553363773f669951de9bef6       # poc/benchmarks/obs/resultats/build-4/debian_13/sha256.txt
SRC2=$HOME/.cache/supply-chain-poc/packaging                                   # sources.sh, révision 1.0.0-2 (option 1)
DSC2=sample-app_1.0.0-2.dsc
DSC2_SHA=ee2a6b8ef65f2464d4cae5ea7e79b3ec796c01f9efcc53c27bec128695221002       # revision-sha256sums-s1-option1.log l. 16
VERROU=$h06/lintian/verrou-lintian.txt
TAG=missing-static-built-using-field-for-golang-package
NS=(/usr/bin/unshare --map-auto --map-root-user --mount --pid --fork --net)     # /usr/bin en clair : le PATH donne celui de linuxbrew
ECARTS=0

chrono() { printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
mesure() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS=$((ECARTS + 1)); }; }
ecarts() { [ "$ECARTS" = 0 ] || { echo "KO   $ECARTS écart(s)" >&2; exit 1; }; echo "bilan : tout OK"; }
sha() { sha256sum < "$1" | cut -c1-64; }
lignes() { grep -v '^#' "$VERROU"; }   # lignes du verrou : nom version architecture sha256 taille chemin

# dans commande… : dans la racine extraite, en espace de noms (root projeté sur l'utilisateur, sans réseau), /proc neuf et /dev de
# l'hôte lié ; environnement vidé
dans() {
  "${NS[@]}" --mount-proc="$C/proc" /bin/sh -c 'c=$1; shift; /usr/bin/mount --rbind /dev "$c/dev" && exec /usr/bin/chroot "$c" \
    /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"' sh "$C" "$@" </dev/null
}

extraire() { # racine de S1 dans $C, sans les nœuds de /dev (mknod refusé dans l'espace de noms ; /dev de l'hôte lié par dans)
  attendu "racine.tar" "$(sha "$RACINE")" "$RACINE_SHA"
  [ ! -e "$C" ] || "${NS[@]}" /usr/bin/rm -rf -- "$C"
  mkdir -p "$C"
  "${NS[@]}" /usr/bin/tar -xpf "$RACINE" -C "$C" --numeric-owner --exclude='./dev/*'
  echo "racine extraite dans ${C/#$HOME/~} ($(du -sm "$C" 2>/dev/null | cut -f1) Mo)"
}

verrou_commite() {
  git -C "$racine" ls-files --error-unmatch "$VERROU" >/dev/null 2>&1 || { echo "KO   verrou non commité : $VERROU" >&2; exit 1; }
  git -C "$racine" diff --quiet HEAD -- "$VERROU" || { echo "KO   verrou modifié depuis son commit" >&2; exit 1; }
  echo "OK   verrou commité et inchangé : $(lignes | wc -l) paquet(s), sha256 $(sha "$VERROU")"
}

# index statut : paquets installés de la racine (fichier status de dpkg) comparés à l'index, ou verrou écrit depuis la simulation
idx() {
  python3 -I - "$@" <<'PY'
import sys
def paras(p):
    for b in open(p, encoding="utf-8").read().split("\n\n"):
        d = {}
        for l in b.splitlines():
            if l[:1] not in " \t" and ":" in l:
                k, v = l.split(":", 1)
                d[k] = v.strip()
        if "Package" in d:
            yield d
mode, packages = sys.argv[1], sys.argv[2]
index = {(d["Package"], d["Version"], d["Architecture"]): d for d in paras(packages)}
if mode == "statut":
    st = [d for d in paras(sys.argv[3]) if d.get("Status", "").endswith(" installed")]
    hors = [f'{d["Package"]} {d["Version"]} {d["Architecture"]}' for d in st if (d["Package"], d["Version"], d["Architecture"]) not in index]
    print(f"{len(st)} {len(hors)} {int(any(d['Package'] == 'lintian' for d in st))}")
    for h in hors:
        print("  hors index :", h)
elif mode == "lintian":
    print(" ".join(sorted(v for (n, v, a) in index if n == "lintian")))
elif mode == "verrou":
    import re
    inst = []
    for l in open(sys.argv[3], encoding="utf-8"):
        if l.startswith(("Remv ", "Purg ")):
            sys.exit(f"retrait dans la simulation : {l.strip()}")
        m = re.match(r"^Inst (\S+) (\[\S+\] )?\((\S+) .*\[(\S+)\]\)", l)
        if m:
            if m.group(2):
                sys.exit(f"mise à jour dans la simulation : {l.strip()}")
            inst.append((m.group(1).split(":")[0], m.group(3), m.group(4)))
    with open(sys.argv[4], "w", encoding="utf-8") as f:
        f.write(f"# Verrou de lintian {sys.argv[5]} (brique 06, lintian.sh resoudre) : apt-get -s install --no-install-recommends\n"
                f"# lintian dans la racine de S1, index de l'instantané (Packages {sys.argv[6]}) ; nom version architecture sha256 taille chemin\n")
        for n, v, a in sorted(inst):
            d = index.get((n, v, a))
            if d is None:
                sys.exit(f"absent de l'index : {n} {v} {a}")
            f.write(f'{n} {v} {a} {d["SHA256"]} {d["Size"]} {d["Filename"]}\n')
    print(len(inst))
PY
}

etape_prealables() {
  local x s n f ninst nhors nlint
  echo "## index de l'instantané $SNAP (copie gardée par S1, hors réseau)"
  s=$(/usr/bin/gpgv --keyring "$HOTE/cles.gpg" --status-fd 1 "$HOTE/InRelease" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' | sort | paste -sd' ')
  attendu "signataires d'InRelease (clés primaires)" "$s" "$(tr ' ' '\n' <<<"$CLES" | sort | paste -sd' ')"
  attendu "InRelease" "$(sha "$HOTE/InRelease")" "$INRELEASE_SHA"
  attendu "Packages listé dans InRelease" \
    "$(awk '/^SHA256:/ {f = 1; next} /^[A-Z]/ {f = 0} f && $3 == "main/binary-amd64/Packages" {print $1}' "$HOTE/InRelease")" "$PACKAGES_SHA"
  mkdir -p "$T"; x=$T/prealables; rm -rf -- "${x:?}"; mkdir -p "$x"
  xz -dc "$HOTE/Packages.xz" > "$x/Packages"
  attendu "Packages.xz décompressé" "$(sha "$x/Packages")" "$PACKAGES_SHA"
  attendu "lintian dans l'index" "$(idx lintian "$x/Packages")" "$V_LINTIAN"

  echo "## racine de S1"
  attendu "racine.tar" "$(sha "$RACINE")" "$RACINE_SHA"
  attendu "InRelease de la racine" "$(tar -xOf "$RACINE" "./${LISTES}_InRelease" | sha256sum | cut -c1-64)" "$INRELEASE_SHA"
  attendu "Packages de la racine" "$(tar -xOf "$RACINE" "./${LISTES}_main_binary-amd64_Packages" | sha256sum | cut -c1-64)" "$PACKAGES_SHA"
  attendu "sources.list de la racine" "$(tar -xOf "$RACINE" ./etc/apt/sources.list)" "$SOURCES_LIST"
  tar -xOf "$RACINE" ./var/lib/dpkg/status > "$x/status"
  read -r ninst nhors nlint < <(idx statut "$x/Packages" "$x/status" | head -1)
  idx statut "$x/Packages" "$x/status" | tail -n +2
  echo "paquets installés de la racine : $ninst"
  attendu "paquets de la racine hors de l'index" "$nhors" 0
  attendu "lintian déjà dans la racine" "$nlint" 0
  echo "nœuds de périphérique de la racine (non extraits) : $(tar -tvf "$RACINE" | awk '$1 ~ /^[cb]/' | wc -l)"

  echo "## sources des deux révisions"
  for n in "$SRC1 $DSC1 $DSC1_SHA" "$SRC2 $DSC2 $DSC2_SHA"; do
    set -- $n
    attendu "$2" "$(sha "$1/$2")" "$3"
    # chaque fichier de Checksums-Sha256 présent et égal
    sed -n '/^Checksums-Sha256:/,/^[^ ]/p' "$1/$2" | awk 'NF == 3 {print $1, $3}' | while read -r s f; do
      attendu "  $f (Checksums-Sha256 de $2)" "$(sha "$1/$f")" "$s"
    done
  done
  echo "## place libre sous ~/.cache : $(df -B1M --output=avail "$HOME/.cache" | tail -1 | tr -d ' ') Mo"
  rm -rf -- "${x:?}"
  echo "bilan : tout OK"
}

etape_resoudre() {
  local n
  [ ! -e "$VERROU" ] || { echo "KO   $VERROU existe déjà : rien résolu" >&2; exit 1; }
  extraire
  echo "## simulation d'apt dans la racine (hors réseau, listes de la racine)"
  attendu "Packages de la racine extraite" "$(sha "$C/${LISTES}_main_binary-amd64_Packages")" "$PACKAGES_SHA"
  rc=0; dans apt-get -s -o Debug::NoLocking=1 install --no-install-recommends "lintian=$V_LINTIAN" > "$T/simulation.txt" 2>&1 || rc=$?
  attendu "code d'apt-get -s" "$rc" 0
  echo "lignes Inst : $(grep -c '^Inst ' "$T/simulation.txt" || true) ; Conf : $(grep -c '^Conf ' "$T/simulation.txt" || true) ; Remv : $(grep -c '^Remv ' "$T/simulation.txt" || true)"
  grep -E '^[0-9]+ (upgraded|mis à jour)|newly installed' "$T/simulation.txt" | sed 's/^/  /' || true
  mkdir -p "${VERROU%/*}"
  n=$(idx verrou "$C/${LISTES}_main_binary-amd64_Packages" "$T/simulation.txt" "$VERROU" "$V_LINTIAN" "$PACKAGES_SHA")
  echo "verrou écrit : $n paquet(s), $(lignes | awk '{s += $5} END {print s}') octets de .deb, sha256 $(sha "$VERROU")"
  attendu "lintian dans le verrou" "$(lignes | awk '$1 == "lintian" {print $2, $3}')" "$V_LINTIAN all"
  "${NS[@]}" /usr/bin/rm -rf -- "$C"
  echo "bilan : tout OK (verrou à commiter avant telecharger)"
}

etape_telecharger() {
  local nom ver arch s taille chemin f n=0 r=0 o=0
  verrou_commite
  mkdir -p "$T/debs"
  while read -r nom ver arch s taille chemin; do
    f=$T/debs/${chemin##*/}
    if [ -f "$f" ] && [ "$(sha "$f")" = "$s" ]; then r=$((r + 1))
    else
      /usr/bin/curl -fsSL --proto =https --proto-redir =https --max-time 300 --retry 3 -o "$f.part" "$MIROIR/$chemin" </dev/null
      [ "$(sha "$f.part")" = "$s" ] && [ "$(stat -c %s "$f.part")" = "$taille" ] \
        || { echo "KO   $nom $ver $arch : sha256 ou taille différents de l'index" >&2; exit 1; }
      mv -- "$f.part" "$f"; n=$((n + 1))
    fi
    o=$((o + taille))
  done < <(lignes)
  echo "téléchargés et contrôlés : $n ; déjà présents et contrôlés : $r ; $o octets"
  attendu "fichiers .deb du dossier" "$(find "$T/debs" -name '*.deb' | wc -l)" "$(lignes | wc -l)"
  echo "bilan : tout OK"
}

etape_installer() {
  local nom ver arch s taille chemin rc
  verrou_commite
  extraire
  mkdir -p "$C/tmp/debs"
  while read -r nom ver arch s taille chemin; do
    cp -- "$T/debs/${chemin##*/}" "$C/tmp/debs/"
    [ "$(sha "$C/tmp/debs/${chemin##*/}")" = "$s" ] || { echo "KO   $nom $ver : sha256 dans la racine" >&2; exit 1; }
  done < <(lignes)
  echo "OK   $(lignes | wc -l) .deb recontrôlés dans la racine"
  echo "## dpkg -i (hors réseau)"
  rc=0; dans /bin/sh -c 'dpkg -i /tmp/debs/*.deb' > "$T/dpkg.log" 2>&1 || rc=$?
  echo "lignes « Setting up » : $(grep -c '^Setting up ' "$T/dpkg.log" || true) ; lignes d'erreur : $(grep -ciE 'error|erreur' "$T/dpkg.log" || true)"
  grep -iE 'error|erreur|warning' "$T/dpkg.log" | sed 's/^/  /' | head -20 || true
  attendu "code de dpkg -i" "$rc" 0
  "${NS[@]}" /usr/bin/rm -rf -- "$C/tmp/debs"
  echo "## paquets installés"
  dans dpkg-query -W -f '${db:Status-Abbrev}|${Package} ${Version} ${Architecture}\n' > "$T/installes.txt"
  attendu "paquets dans un autre état que ii" "$(grep -vc '^ii |' "$T/installes.txt" || true)" 0
  tar -xOf "$RACINE" ./var/lib/dpkg/status | awk '/^Package:/ {p = $2} /^Version:/ {v = $2} /^Architecture:/ {a = $2}
    /^Status:.* installed$/ {i = 1} /^$/ {if (i) print p, v, a; i = 0} END {if (i) print p, v, a}' > "$T/attendus.txt"
  lignes | awk '{print $1, $2, $3}' >> "$T/attendus.txt"
  attendu "installés = racine + verrou" "$(cut -d'|' -f2 "$T/installes.txt" | sort | sha256sum | cut -c1-64)" "$(sort "$T/attendus.txt" | sha256sum | cut -c1-64)"
  echo "paquets installés : $(wc -l < "$T/installes.txt")"
  attendu "lintian" "$(dans dpkg-query -W -f '${Version}' lintian)" "$V_LINTIAN"
  attendu "dpkg --audit" "$(dans dpkg --audit | wc -l)" 0
  echo "bilan : tout OK"
}

etape_juger() {
  local f p t d o rc
  attendu "lintian installé dans la racine" "$(dans dpkg-query -W -f '${Version}' lintian)" "$V_LINTIAN"
  echo "## règle et tag relus dans le lintian installé"
  p=$(find "$C/usr/share" -path '*/Lintian/Check/Languages/Golang/BuiltUsing.pm')
  t=$(find "$C/usr/share" -name "$TAG.tag")
  attendu "fichiers de la règle et du tag" "$(printf '%s\n' "$p" "$t" | grep -c .)" 2
  echo "${p#"$C"} : sha256 $(sha "$p")"
  grep -n -e 'Static-Built-Using' -e 'golang-go' -e 'golang-any' -e "$TAG" "$p" | sed 's/^/  /'
  echo "${t#"$C"} : sha256 $(sha "$t")"
  # champ Visibility ou Severity selon la version (non relu pour 2.122.0) : les deux sont acceptés ; mesure, pas arrêt
  mesure "sévérité du tag" "$(sed -n 's/^\(Visibility\|Severity\): *//p' "$t")" info

  echo "## sources copiées dans la racine ; debian/control"
  for d in "s1 $SRC1 $DSC1" "s2 $SRC2 $DSC2"; do
    set -- $d
    rm -rf -- "${C:?}/tmp/$1"; mkdir -p "$C/tmp/$1"
    cp -- "$2/$3" "$C/tmp/$1/"
    sed -n '/^Checksums-Sha256:/,/^[^ ]/p' "$2/$3" | awk 'NF == 3 {print $3}' | while read -r f; do cp -- "$2/$f" "$C/tmp/$1/"; done
  done
  git -C "$racine" show "HEAD:poc/packaging/debian/control" > "$T/control-head"
  mesure "debian/control de 1.0.0-2 égal à celui de HEAD (poc/packaging/debian/control)" \
    "$(tar -xJOf "$SRC2/sample-app_1.0.0-2.debian.tar.xz" debian/control | cmp -s - "$T/control-head" && echo oui || echo non)" oui
  echo "dernier commit de poc/packaging/debian/control : $(git -C "$racine" log -1 --format='%h %cI' -- poc/packaging/debian/control)"
  mesure "Static-Built-Using dans debian/control de 1.0.0-1" \
    "$(tar -xJOf "$SRC1/sample-app_1.0.0-1.debian.tar.xz" debian/control | grep -c 'Static-Built-Using' || true)" 0
  mesure "littéral dans debian/control de 1.0.0-2" \
    "$(tar -xJOf "$SRC2/sample-app_1.0.0-2.debian.tar.xz" debian/control | grep -cF 'Static-Built-Using: ${misc:Static-Built-Using}' || true)" 1

  echo "## lintian (hors réseau, root projeté)"
  for d in "1 s1/$DSC1" "2 s2/$DSC2"; do
    set -- $d
    for o in I sans; do
      f=$T/lintian-$1-$o
      rc=0
      if [ "$o" = I ]; then dans lintian -I "/tmp/$2" > "$f.out" 2> "$f.err" || rc=$?
      else dans lintian "/tmp/$2" > "$f.out" 2> "$f.err" || rc=$?; fi
      echo "### lintian $([ "$o" = I ] && echo '-I ')/tmp/$2 : code $rc, $(wc -l < "$f.out") ligne(s), $(wc -l < "$f.err") ligne(s) d'erreur"
      sed 's/^/  /' "$f.out"; sed 's/^/  err : /' "$f.err"
      mesure "code de lintian (0 ou 2)" "$([ "$rc" = 0 ] || [ "$rc" = 2 ] && echo admis || echo "$rc")" admis
    done
  done
  compte() { grep -cE "^I: sample-app source: $TAG( |$)" "$T/lintian-$1.out" || true; }
  mesure "Y5 : tag sur 1.0.0-1 avec -I (témoin)" "$(compte 1-I)" 1
  mesure "Y6 : tag sur 1.0.0-2 avec -I" "$(compte 2-I)" 0
  mesure "Y7 : tag sans -I (1.0.0-1, 1.0.0-2)" "$(compte 1-sans), $(compte 2-sans)" "0, 0"
  mesure "tag sous une autre forme (toute ligne qui le nomme, avec -I)" \
    "$(cat "$T/lintian-1-I.out" "$T/lintian-2-I.out" | grep -c "$TAG" || true)" "$(compte 1-I)"
  ecarts
}

case "${1:-}:$#" in
  prealables:1|resoudre:1|telecharger:1|installer:1|juger:1) ;;
  *) echo "usage : $0 prealables|resoudre|telecharger|installer|juger" >&2; exit 2 ;;
esac
mkdir -p "$T"
chrono "lintian $1"
{ echo "# ${0##*/} $1, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$1"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/lintian-$1.log"
chrono "lintian $1 fait"
