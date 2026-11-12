#!/usr/bin/env bash
# Brique 13a, volet rpm/deb : licences déclarées des paquets construits (ouvert le 12/11/2026 sur « Oui, ouvre-le »). Préparé à
# sec le 12/11/2026, NON LANCÉ. Protocole et prédictions : resultats/paquets-predictions.md.
#   deb   hôte seul, sans réseau, ni cluster ni Zot ni VM : le deb de S3 de la brique 06 (sha256 épinglé, s3-comparaison.log)
#         est lu par paquets.py sans rien extraire sur disque ni exécuter ; son copyright (DEP-5) devient un SBOM CycloneDX
#         jugé par licences.py (politique de 13a, liste SPDX 3.27.0 du nixpkgs épinglé) ; comparaison avec
#         poc/packaging/debian/copyright ; puis quatre témoins négatifs (copyright synthétiques, écrits par cette étape) qui
#         doivent être refusés : GPL refusée par la politique, en-tête Format absent (NOASSERTION), paragraphe Files sans
#         License (refus de l analyse), nom DEP-5 non SPDX (Expat : invalide, jamais traduit). Sortie : prédicat archivé.
#   modules  (ajoutée à sec le 12/11/2026, après le premier passage de deb, NON LANCÉE) hôte seul, sans réseau : même deb, sha256
#         épinglé ; paquets.py modules lit en mémoire les informations de build de Go de chaque fichier de ./usr/bin (jamais écrit
#         sur disque ni exécuté) et rapproche chaque dépendance compilée des paragraphes Files du copyright ; bibliothèque
#         standard de Go en ÉCART (hors des sources) ; témoin : le même deb avec un copyright privé du paragraphe de TEMOIN_DEP, réécrit
#         en mémoire puis dans le dossier de travail (0700, effacé à la fin), doit donner un KO sur cette dépendance.
#   stdlib   (ajoutée à sec le 12/11/2026, décision « Axe 3, puis 1+2 », NON LANCÉE) hôte seul, sans réseau : même deb, et le paquet
#         golang-1.24-src de la fermeture de S3 de la 06 (sha256 épinglé, recoupé avec poc/packaging/verrou-deb.txt et avec
#         s3-build-1.buildinfo) ; paquets.py stdlib exige la même version de Go dans le binaire et en amont du paquet, puis met le
#         copyright DEP-5 de ce paquet en second composant du SBOM ; licences.py juge les deux composants ; témoin : le deb de
#         l application donné à la place du paquet de Go, refus exigé. Le deb n est pas modifié (axes 1 et 2 après S5b).
#         Traductions par nom (traductions-dep5.json, ajoutées le 12/11/2026) : un nom DEP-5 du copyright de Go n est traduit que si
#         le texte de son paragraphe License autonome a le sha256 de la preuve ET si l entrée est revue par le propriétaire ;
#         statut de chaque nom (SPDX, politique) journalisé.
#   noms     (ajoutée à sec le 12/11/2026, étude, « Oui, prépare-la », NON LANCÉE) hôte seul, sans réseau : mêmes deb et paquet de
#         Go (sha256 épinglés, verrou et buildinfo recoupés) ; paquets.py noms classe chaque paragraphe Files du copyright de Go
#         (empaquetage, cmd, testdata, ou paquet cherché dans le binaire par « \0<paquet>. ») et compare les textes des noms hors
#         SPDX ou hors politique aux textes SPDX candidats ; témoins : runtime et fmt présents, cmd/link/internal/ld absent. Aucun
#         SBOM ni verdict : une étude pour décision.
#   lies     (ajoutée à sec le 12/11/2026, « Oui, prépare-les », NON LANCÉE) : l étape stdlib avec la règle des paragraphes non
#         liés (paquets.py --lies) ; un paragraphe Files du copyright de Go n est écarté de l expression que si chacun de ses motifs
#         est probant contre (empaquetage, cmd, testdata, ou paquet absent du binaire dont la source a une fonction à corps hors
#         contrainte de build) ; tout le reste est gardé ; chaque paragraphe écarté journalisé avec ses motifs. Lecture du binaire
#         par le projet, pas une règle de Debian (le copyright décrit le paquet source). Prédicat : paquets-lies.licences.json.
#   Hors de ces étapes : rpm (après S1 de la 05), .dsc et SRPM en referrer dans Zot (après S5b, accord à part).
# Usage : mise exec -- poc/bricks/13a-licences/paquets.sh deb       (journal : resultats/paquets-deb.log)
#         mise exec -- poc/bricks/13a-licences/paquets.sh modules   (journal : resultats/paquets-modules.log)
#         mise exec -- poc/bricks/13a-licences/paquets.sh stdlib    (journal : resultats/paquets-stdlib.log)
#         mise exec -- poc/bricks/13a-licences/paquets.sh noms      (journal : resultats/paquets-noms.log)
#         mise exec -- poc/bricks/13a-licences/paquets.sh lies      (journal : resultats/paquets-lies.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
R=$here/resultats
DEB=${DEB:-$HOME/.cache/supply-chain-poc/08/travail/s3-06/build-1/sample-app_1.0.0-1_amd64.deb}
DEB_SHA=0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5   # deb des deux builds de S3 (06, s3-comparaison.log)
SRC=${SRC:-$HOME/.cache/supply-chain-poc/08/travail/s3-06/restauree-1/golang-1.24-src_1.24.4-1_all.deb}
SRC_SHA=c396bc2c2e94606e0a060cff52b9bbbf1d7cefacb040eb3c40a55604111e66e1   # verrou-deb.txt (golang-1.24-src 1.24.4-1)
SRC_BI="golang-1.24-src (= 1.24.4-1)"                                       # s3-build-1.buildinfo de la 06
TEMOIN_DEP=github.com/go-chi/chi/v5   # étape modules : dépendance dont le paragraphe Files est retiré du témoin
SPDX=${SPDX:?liste SPDX (mise exec)}
T=$HOME/.cache/supply-chain-poc/13a/paquets
chrono() { printf '%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >> "$R/chrono.tsv"; }

juger() { # sbom sortie : licences.py ; une ligne de bilan ; code de licences.py
  local rc=0
  python3 -I "$here/licences.py" --sbom "$1" --policy "$here/policy.json" --spdx "$SPDX/licenses.json" \
    --exceptions "$SPDX/exceptions.json" > "$2" || rc=$?
  python3 -I - "$2" "$rc" <<'EOP'
import json, sys
d = json.load(open(sys.argv[1]))
v = d["violations"]
print(f"licences.py : code {sys.argv[2]} ; liste SPDX {d['spdxListVersion']} ; erreurs {v['error']}, avertissements {v['warning']}, NOASSERTION {d['noassertion']}, invalides {d['invalid']}")
for i in d["components"]:
    print(f"     {i['verdict']:8} {i['purl']} : {i['expression']}" + (" ; " + "; ".join(i["reasons"]) if i["reasons"] else ""))
EOP
  return "$rc"
}

etape_deb() {
  local ko=0 s rc
  rm -rf -- "${T:?}" && mkdir -p "$T" && chmod 0700 "$T"
  echo "politique : $(sha256sum < "$here/policy.json" | cut -c1-64) ; licences.py : $(sha256sum < "$here/licences.py" | cut -c1-64) ; paquets.py : $(sha256sum < "$here/paquets.py" | cut -c1-64)"
  echo "liste SPDX : $(readlink -f "$SPDX" | sed "s#$HOME#~#")"
  echo "## deb de S3 de la 06"
  [ -f "$DEB" ] || { echo "KO   deb absent : $DEB"; exit 1; }
  s=$(sha256sum < "$DEB" | cut -c1-64)
  [ "$s" = "$DEB_SHA" ] || { echo "KO   sha256 du deb : $s, attendu $DEB_SHA"; exit 1; }
  echo "OK   sha256 du deb épinglé : $s"
  rc=0; python3 -I "$here/paquets.py" deb "$DEB" --sbom "$T/deb.sbom.json" | tee "$T/deb.out" || rc=$?
  [ "$rc" = 0 ] || { echo "KO   paquets.py : code $rc"; exit 1; }
  local c d
  c=$(sed -n 's/^copyright : sha256 \([0-9a-f]*\) .*/\1/p' "$T/deb.out")
  d=$(sha256sum < "$repo/poc/packaging/debian/copyright" | cut -c1-64)
  if [ "$c" = "$d" ]; then echo "OK   copyright du deb identique à poc/packaging/debian/copyright ($d)"
  else echo "ÉCART copyright du deb $c, poc/packaging/debian/copyright $d"; fi
  echo "## verdict (licences.py)"
  rc=0; juger "$T/deb.sbom.json" "$R/paquets-deb.licences.json" || rc=$?
  if [ "$rc" = 0 ] && python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); sys.exit(0 if d["violations"]["error"] == 0 and d["noassertion"] == 0 and d["invalid"] == 0 and len(d["components"]) == 1 else 1)' "$R/paquets-deb.licences.json"; then
    echo "OK   deb : 0 erreur, 0 NOASSERTION, 0 invalide (prédicat : resultats/paquets-deb.licences.json)"
  else echo "KO   deb : verdict non conforme"; ko=1; fi
  echo "## témoins négatifs (copyright synthétiques ; chacun doit être refusé)"
  local en='Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: temoin
'
  printf '%s\nFiles: *\nCopyright: 2026 temoin\nLicense: GPL-3.0-or-later\n texte\n' "$en" > "$T/t-gpl"
  printf 'Upstream-Name: temoin\n\nFiles: *\nCopyright: 2026 temoin\nLicense: MIT\n texte\n' > "$T/t-sans-format"
  printf '%s\nFiles: *\nCopyright: 2026 temoin\n' "$en" > "$T/t-sans-license"
  printf '%s\nFiles: *\nCopyright: 2026 temoin\nLicense: Expat\n texte\n' "$en" > "$T/t-expat"
  # témoin, étage attendu du refus (analyse : paquets.py ; politique : licences.py), motif attendu ; tout autre échec est un KO
  local t etage motif m
  while IFS='|' read -r t etage motif; do
    rc=0; python3 -I "$here/paquets.py" dep5 "$T/$t" --sbom "$T/$t.sbom.json" --purl "pkg:deb/debian/temoin@1.0-1?arch=amd64" > "$T/$t.out" 2>&1 || rc=$?
    if [ "$rc" != 0 ]; then
      m=$(awk '/^REFUS : / {sub("^REFUS : ", ""); print; exit}' "$T/$t.out")
      if [ "$etage" = analyse ] && [ -n "$m" ] && grep -qF -- "$motif" <<< "$m"; then echo "OK   $t : refusé par l analyse ($m)"
      else echo "KO   $t : paquets.py code $rc, attendu : $etage, « $motif »"; tail -3 "$T/$t.out"; ko=1; fi
      continue
    fi
    rc=0; juger "$T/$t.sbom.json" "$T/$t.lic.json" > "$T/$t.juge" 2>&1 || rc=$?
    m=$(awk 'NR == 2 {sub("^ +", ""); print}' "$T/$t.juge")
    if [ "$rc" = 1 ] && [ "$etage" = politique ] && grep -q '^ *error ' <<< "$m" && grep -qF -- "$motif" <<< "$m"; then
      echo "OK   $t : refusé par licences.py ($m)"
    else echo "KO   $t : licences.py code $rc, attendu : $etage, « $motif »"; tail -3 "$T/$t.juge"; ko=1; fi
  done <<'EOT'
t-gpl|politique|deny : GPL-3.0-or-later
t-sans-format|politique|NOASSERTION : curation nécessaire
t-sans-license|analyse|champ(s) manquant(s) : license
t-expat|politique|identifiant SPDX inconnu : Expat
EOT
  rm -rf -- "${T:?}"
  [ "$ko" = 0 ] && echo "bilan : deb jugé conforme, quatre témoins refusés" || { echo "bilan : KO"; exit 1; }
}

etape_modules() {
  local s rc
  rm -rf -- "${T:?}" && mkdir -p "$T" && chmod 0700 "$T"
  echo "paquets.py : $(sha256sum < "$here/paquets.py" | cut -c1-64)"
  [ -f "$DEB" ] || { echo "KO   deb absent : $DEB"; exit 1; }
  s=$(sha256sum < "$DEB" | cut -c1-64)
  [ "$s" = "$DEB_SHA" ] || { echo "KO   sha256 du deb : $s, attendu $DEB_SHA"; exit 1; }
  echo "OK   sha256 du deb épinglé : $s"
  rc=0; python3 -I "$here/paquets.py" modules "$DEB" || rc=$?
  [ "$rc" = 0 ] || { echo "KO   paquets.py modules : code $rc"; exit 1; }
  echo "## témoin : même deb, copyright sans le paragraphe de $TEMOIN_DEP (doit donner un KO sur cette dépendance)"
  python3 -I - "$DEB" "$T/temoin.deb" "$TEMOIN_DEP" <<'EOP'
import io, re, sys, tarfile
b = open(sys.argv[1], "rb").read()
ms, i = [], 8
while i < len(b):
    h = b[i:i + 60]; n = int(h[48:58]); ms.append([h[:16].decode().strip(), b[i + 60:i + 60 + n]]); i += 60 + n + (n & 1)
src = tarfile.open(fileobj=io.BytesIO(ms[2][1]), mode="r:xz")
out = io.BytesIO()
dst = tarfile.open(fileobj=out, mode="w:xz")
retire = 0
for m in src.getmembers():
    f = src.extractfile(m) if m.isfile() else None
    data = f.read() if f else None
    if m.name.endswith("/copyright") and data is not None:
        t, retire = re.subn(r"\n\nFiles: vendor/" + re.escape(sys.argv[3]) + r"/\*\n(?:[^\n]+\n)+?(?=\n)", "\n", data.decode() + "\n")
        t = t[:-1]
        data = t.encode(); m.size = len(data)
    dst.addfile(m, io.BytesIO(data) if data is not None else None)
dst.close()
assert retire == 1, f"paragraphe de {sys.argv[3]} retiré {retire} fois"
ms[2][1] = out.getvalue()
o = b"!<arch>\n"
for n, d in ms:
    o += f"{n:<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(d):<10}".encode() + b"`\n" + d + (b"\n" if len(d) & 1 else b"")
open(sys.argv[2], "wb").write(o)
print(f"témoin écrit : paragraphe de {sys.argv[3]} retiré 1 fois")
EOP
  rc=0; python3 -I "$here/paquets.py" modules "$T/temoin.deb" > "$T/temoin.out" 2>&1 || rc=$?
  if [ "$rc" = 1 ] && grep -qF "KO   dep $TEMOIN_DEP " "$T/temoin.out" && ! grep -q '^Traceback' "$T/temoin.out"; then
    echo "OK   témoin refusé : $(grep -m1 '^KO   dep ' "$T/temoin.out")"
  else echo "KO   témoin : code $rc"; tail -3 "$T/temoin.out"; rm -rf -- "${T:?}"; exit 1; fi
  rm -rf -- "${T:?}"
  echo "bilan : chaque dépendance compilée a son paragraphe Files ; témoin refusé"
}

stdlib_commun() { # nom (prédicat resultats/paquets-<nom>.licences.json) [--lies]
  local s rc
  rm -rf -- "${T:?}" && mkdir -p "$T" && chmod 0700 "$T"
  echo "paquets.py : $(sha256sum < "$here/paquets.py" | cut -c1-64) ; licences.py : $(sha256sum < "$here/licences.py" | cut -c1-64) ; politique : $(sha256sum < "$here/policy.json" | cut -c1-64)"
  [ -f "$DEB" ] && [ -f "$SRC" ] || { echo "KO   deb ou paquet de Go absent"; exit 1; }
  s=$(sha256sum < "$DEB" | cut -c1-64); [ "$s" = "$DEB_SHA" ] || { echo "KO   sha256 du deb : $s"; exit 1; }
  echo "OK   sha256 du deb épinglé : $s"
  s=$(sha256sum < "$SRC" | cut -c1-64); [ "$s" = "$SRC_SHA" ] || { echo "KO   sha256 du paquet de Go : $s, attendu $SRC_SHA"; exit 1; }
  echo "OK   sha256 du paquet de Go épinglé : $s"
  if grep -q " $SRC_SHA " "$repo/poc/packaging/verrou-deb.txt"; then echo "OK   même sha256 dans poc/packaging/verrou-deb.txt"
  else echo "KO   sha256 absent de poc/packaging/verrou-deb.txt"; exit 1; fi
  if grep -qF "$SRC_BI" "$repo/poc/bricks/06-deb-sbuild/resultats/s3-build-1.buildinfo"; then echo "OK   « $SRC_BI » dans s3-build-1.buildinfo"
  else echo "KO   « $SRC_BI » absent de s3-build-1.buildinfo"; exit 1; fi
  local ko=0
  echo "## témoin : le deb de l application à la place du paquet de Go (refus exigé ; avant l appel principal)"
  rc=0; python3 -I "$here/paquets.py" stdlib "$DEB" "$DEB" --sbom "$T/temoin.json" > "$T/temoin.out" 2>&1 || rc=$?
  if [ "$rc" = 1 ] && grep -q "^REFUS : .* n'est pas un paquet golang-X.Y-src" "$T/temoin.out"; then echo "OK   témoin refusé : $(grep -m1 '^REFUS' "$T/temoin.out")"
  else echo "KO   témoin : code $rc"; tail -3 "$T/temoin.out"; ko=1; fi
  echo "## deb et paquet de Go"
  echo "traductions : $(sha256sum < "$here/traductions-dep5.json" | cut -c1-64) (traductions-dep5.json)"
  rc=0; python3 -I "$here/paquets.py" stdlib "$DEB" "$SRC" --sbom "$T/stdlib.sbom.json" --traductions "$here/traductions-dep5.json" \
    --spdx "$SPDX/licenses.json" --policy "$here/policy.json" ${2:+"$2"} || rc=$?
  [ "$rc" = 0 ] || { echo "KO   paquets.py stdlib : code $rc"; rm -rf -- "${T:?}"; exit 1; }
  echo "## verdict (licences.py, deux composants)"
  rc=0; juger "$T/stdlib.sbom.json" "$R/paquets-$1.licences.json" || rc=$?
  if [ "$rc" = 0 ] && python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); sys.exit(0 if d["violations"]["error"] == 0 and d["noassertion"] == 0 and d["invalid"] == 0 and len(d["components"]) == 2 else 1)' "$R/paquets-$1.licences.json"; then
    echo "OK   deux composants : 0 erreur, 0 NOASSERTION, 0 invalide (prédicat : resultats/paquets-$1.licences.json)"
  else echo "KO   verdict non conforme (prédicat archivé tel quel : resultats/paquets-$1.licences.json)"; ko=1; fi
  rm -rf -- "${T:?}"
  [ "$ko" = 0 ] && echo "bilan : bibliothèque standard déclarée dans le prédicat, deux composants conformes ; témoin refusé" || { echo "bilan : KO"; exit 1; }
}

etape_stdlib() { stdlib_commun stdlib; }
etape_lies() { stdlib_commun lies --lies; }

etape_noms() {
  local s rc
  echo "paquets.py : $(sha256sum < "$here/paquets.py" | cut -c1-64)"
  [ -f "$DEB" ] && [ -f "$SRC" ] || { echo "KO   deb ou paquet de Go absent"; exit 1; }
  s=$(sha256sum < "$DEB" | cut -c1-64); [ "$s" = "$DEB_SHA" ] || { echo "KO   sha256 du deb : $s"; exit 1; }
  echo "OK   sha256 du deb épinglé : $s"
  s=$(sha256sum < "$SRC" | cut -c1-64); [ "$s" = "$SRC_SHA" ] || { echo "KO   sha256 du paquet de Go : $s, attendu $SRC_SHA"; exit 1; }
  echo "OK   sha256 du paquet de Go épinglé : $s"
  grep -q " $SRC_SHA " "$repo/poc/packaging/verrou-deb.txt" || { echo "KO   sha256 absent de poc/packaging/verrou-deb.txt"; exit 1; }
  grep -qF "$SRC_BI" "$repo/poc/bricks/06-deb-sbuild/resultats/s3-build-1.buildinfo" || { echo "KO   « $SRC_BI » absent de s3-build-1.buildinfo"; exit 1; }
  echo "OK   verrou et buildinfo recoupés"
  rc=0; python3 -I "$here/paquets.py" noms "$DEB" "$SRC" --spdx-details "$SPDX/details" || rc=$?
  [ "$rc" = 0 ] || { echo "KO   paquets.py noms : code $rc"; exit 1; }
  echo "bilan : étude écrite (aucun verdict)"
}

[ $# -gt 0 ] || { echo "usage : $0 deb|modules|stdlib|noms|lies" >&2; exit 2; }
for e in "$@"; do declare -F "etape_$e" >/dev/null || { echo "étape inconnue : $e" >&2; exit 2; }; done
for e in "$@"; do
  chrono "13a paquets $e"
  { echo "# ${0##*/} $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$R/paquets-$e.log"
  chrono "13a paquets $e fait"
done
