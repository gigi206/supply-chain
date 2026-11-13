#!/usr/bin/env bash
# Brique 03, banc Debian (préparé à sec le 13/11/2026 sur la décision du propriétaire « Oui, les deux », puis « Oui, prépare-le ») :
# instruire l'option E du plan de sortie de Nix (doc 04, §6) pour l'image outils-prefetch de F2 : contenu Debian de l'instantané
# épinglé de la 06 à la place de la clôture Nix (python313, gitMinimal, cacert, busybox). Hors cluster, sans rien installer sur
# l'hôte, hors de sc-replay. Prédictions : resultats/banc-debian-predictions.md, commitées avant toute exécution.
#   lecture     réseau (accord nommé) : clés de ftp-master contrôlées contre les trois empreintes épinglées de la 06 (s1.sh l. 33),
#               InRelease de l'instantané vérifié par gpgv, Packages.xz contrôlé par InRelease ; versions des paquets candidats.
#               Commandes reprises de s1.sh prealables (l. 115-130), sans exécuter s1.sh.
#   simulation  hors réseau (unshare -rn) : apt de l'hôte, état dpkg vide, Packages vérifié pour seule source (montage repris de
#               s3.sh simulation) ; fermeture de python3.13, python3.13-venv, git, ca-certificates et busybox-static ; paquets
#               Essential tirés ou non ; tailles (Size, Installed-Size) ; dépendances de git et de python3.13-venv.
# Étapes suivantes (image, essai, mesure de fermeture avec le témoin Nix 68e0ae70) : à écrire après la simulation, sur sa liste réelle.
# Fichiers : ~/.cache/supply-chain-poc/03/banc-debian (hors de 08/travail, que vm.sh detruire efface).
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/03-deps-closure/banc-debian.sh <étape>…   (journal : resultats/banc-debian-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
T=$HOME/.cache/supply-chain-poc/03/banc-debian
SNAP=20261105T000000Z   # instantané de la 06 (s1.sh l. 30)
MIROIR=http://snapshot.debian.org/archive/debian/$SNAP   # intégrité par InRelease signé, pas par le transport
CLES="B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8 04B54C3CDCA79751B16BC6B5225629DF75B188BD 41587F7DB8C774BCCF131416762F67A0B2C39DE4"
#     archive 12/bookworm, archive 13/trixie, release 13/trixie (s1.sh l. 33)
VOULUS="python3.13 python3.13-venv git ca-certificates busybox-static"
mkdir -p "$R" "$T"

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }

etape_lecture() {
  local d=$T/hote s n
  rm -rf -- "${d:?}" && mkdir -p "$d"
  for n in archive-key-12 archive-key-13 release-13; do
    curl -fsS --max-time 60 -o "$d/$n.asc" "https://ftp-master.debian.org/keys/$n.asc"
    gpg --no-default-keyring --keyring "$d/cles.gpg" --batch --quiet --import "$d/$n.asc" 2>/dev/null
  done
  curl -fsSL --max-time 60 -o "$d/InRelease" "$MIROIR/dists/trixie/InRelease"
  s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/InRelease" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' | sort | paste -sd' ')
  attendu "signataires d'InRelease (clés primaires)" "$s" "$(tr ' ' '\n' <<<"$CLES" | sort | paste -sd' ')"
  echo "InRelease : sha256 $(sha256sum < "$d/InRelease" | cut -c1-64), $(sed -n 's/^Date: //p' "$d/InRelease")"
  s=$(awk '/^SHA256:/ {f = 1; next} /^[A-Z]/ {f = 0} f && $3 == "main/binary-amd64/Packages.xz" {print $1}' "$d/InRelease")
  curl -fsSL --max-time 300 -o "$d/Packages.xz" "$MIROIR/dists/trixie/main/binary-amd64/Packages.xz"
  attendu "Packages.xz contrôlé par InRelease" "$(sha256sum < "$d/Packages.xz" | cut -c1-64)" "$s"
  xz -dc "$d/Packages.xz" > "$T/Packages"
  echo "Packages : $(grep -c '^Package: ' "$T/Packages") paragraphes"
  for n in $VOULUS; do
    echo "candidat $n : $(awk -v p="$n" '$1 == "Package:" {q = ($2 == p)} q && $1 == "Version:" {print $2}' "$T/Packages" | paste -sd' ')"
  done
}

etape_simulation() {
  local S=$T/simulation o
  [ -s "$T/Packages" ] || { echo "KO   lancer d'abord lecture" >&2; exit 1; }
  rm -rf -- "${S:?}" && mkdir -p "$S/depot" "$S/listes/partial" "$S/cache/archives/partial" "$S/vide"
  : > "$S/status"
  cp "$T/Packages" "$S/depot/Packages"
  echo "deb [trusted=yes] file:$S/depot ./" > "$S/sources.list"   # Packages déjà vérifié par InRelease (étape lecture)
  o="-o APT::Sandbox::User=root -o Dir::State::status=$S/status -o Dir::State::Lists=$S/listes -o Dir::Cache=$S/cache"
  o="$o -o Dir::Etc::sourcelist=$S/sources.list -o Dir::Etc::sourceparts=$S/vide -o Dir::Etc::preferencesparts=$S/vide"
  o="$o -o APT::Architecture=amd64 -o APT::Architectures=amd64 -o Debug::NoLocking=1 -o APT::Install-Recommends=false"
  echo "apt de l'hôte : $(apt-get --version | awk 'NR == 1') (solveur de l'hôte, pas celui de trixie : limite du banc)"
  # shellcheck disable=SC2086
  unshare -rn sh -c "echo \"interfaces : \$(ip -o link | awk '{print \$2}' | paste -sd' ')\"; apt-get -q $o update >/dev/null && apt-get -s $o install $VOULUS" \
    > "$S/sim.log" 2>&1 || { tail -n 20 "$S/sim.log" >&2; echo "KO   simulation" >&2; exit 1; }
  awk 'NR == 1' "$S/sim.log"
  grep '^Inst ' "$S/sim.log" | sed -E 's/^Inst ([^ ]+) \(([^ ]+) .*/\1 \2/' | sort > "$T/fermeture.txt"
  python3 -I - "$T/Packages" "$T/fermeture.txt" <<'PY'
import sys
paras = {}
for p in open(sys.argv[1], encoding='utf-8').read().split('\n\n'):
    d = {}
    for l in p.splitlines():
        if l and not l[0].isspace() and ': ' in l:
            k, v = l.split(': ', 1); d[k] = v
    if 'Package' in d:
        paras[(d['Package'], d.get('Version'))] = d
ferm = [tuple(l.split()) for l in open(sys.argv[2]) if l.strip()]
taille = inst = 0
ess = []
for n, v in ferm:
    d = paras[(n, v)]
    taille += int(d.get('Size', 0)); inst += int(d.get('Installed-Size', 0))
    if d.get('Essential') == 'yes': ess.append(n)
print(f"fermeture : {len(ferm)} paquets ; .deb {taille / 1e6:.1f} Mo ; Installed-Size {inst / 1024:.1f} Mo")
print(f"paquets Essential dans la fermeture : {len(ess)} : {' '.join(ess) or '-'}")
print(f"base-files dans la fermeture : {'oui' if any(n == 'base-files' for n, _ in ferm) else 'non'}")
for n in ('git', 'python3.13-venv', 'python3.13', 'ca-certificates', 'busybox-static'):
    m = [d for (k, _), d in paras.items() if k == n and (k, d.get('Version')) in set(ferm)]
    print(f"{n} : Depends {m[0].get('Depends', '-') if m else 'absent de la fermeture'}")
for n, v in ferm:
    print(f"  {n} {v} {paras[(n, v)].get('Installed-Size', '?')}")
PY
}

[ $# -gt 0 ] || { echo "usage : $0 lecture|simulation…" >&2; exit 2; }
for e in "$@"; do
  case $e in
    lecture|simulation) { echo "# banc-debian.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e" 2>&1; } | tee "$R/banc-debian-$e.log" ;;
    *) echo "étape inconnue : $e" >&2; exit 2 ;;
  esac
done
