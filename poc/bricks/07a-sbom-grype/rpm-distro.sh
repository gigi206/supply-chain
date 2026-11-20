#!/usr/bin/env bash
# Brique 07a, question ouverte des 10 et 12/11/2026 : syft, sur un .rpm isolé produit par mock (ou tiré
# d'une fermeture), sans /etc/os-release, émet-il distro= ? Et grype juge-t-il ce SBOM avec et sans --distro ?
# Hôte seul, hors réseau (syft et grype sous unshare -rn), syft 1.38.0 et grype 0.104.1 de mise, base du
# 04/11/2026 importée en G0. Rien dans le cluster, dans Zot ni dans les VM ; rien installé, rien téléchargé.
# Entrées : le rpm sample-app de la 05 (cascade M1b) et trois rpm Rocky de la fermeture tirée de Zot,
# copiés et contrôlés par sha256 contre les valeurs archivées avant tout usage.
# Écritures : $D (dossier neuf, refusé s'il existe) et le journal resultats/rpm-distro.log (refusé s'il existe).
# Lancement : mise exec -- ./rpm-distro.sh ; prédictions : resultats/rpm-distro-predictions.md
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R05=$here/../05-rpm-mock/resultats
G0=$HOME/.cache/supply-chain-poc/07a/g0
D=${D:-$HOME/.cache/supply-chain-poc/07a/rpm-distro}
LOG=${LOG:-$here/resultats/rpm-distro.log}
W8=$HOME/.cache/supply-chain-poc/08/travail
APP=$W8/m1b-construction-05/comparaison/travail/rpm/sample-app-1.0.0-2.el9.x86_64.rpm
APP_SHA=864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f   # m1b-construction-construction.log
FERM=$W8/m1b-fermeture-05/comparaison/tiree/depot
ARBRE=$R05/m1b-fermeture-essai-arbre.txt   # nom taille sha256, 230 lignes
ROCKY=(openssl-libs-3.5.1-7.el9_7.x86_64.rpm zlib-1.2.11-40.el9.x86_64.rpm glibc-2.34-231.el9_7.10.x86_64.rpm)
DISTRO=rocky:9.7

hors() { unshare -rn env GRYPE_DB_CACHE_DIR="$G0/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
  GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false "$@"; }
ko() { echo "KO   $*" >&2; exit 1; }

[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
[ ! -e "$D" ] || { echo "dossier présent, prendre un dossier neuf : $D" >&2; exit 2; }

resume() { # sbom.json grype.json|- : PURL du SBOM, puis correspondances de grype
  python3 -I - "$1" "$2" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
cs = s.get("components", [])
print(f"composants : {len(cs)}")
for c in cs:
    p = c.get("purl", "")
    print(f"   {c.get('type')} | {p} | distro= : {'oui' if 'distro=' in p else 'non'}")
if sys.argv[2] != "-":
    g = json.load(open(sys.argv[2]))
    m = g.get("matches", [])
    print(f"correspondances : {len(m)} ; distro vue par grype : {json.dumps(g.get('distro'))}")
    esp = sorted({x['vulnerability'].get('namespace') for x in m})
    print(f"espaces : {esp}")
    ids = sorted({x['vulnerability']['id'] for x in m})
    print(f"identifiants ({len(ids)}) : {' '.join(ids[:12])}{' …' if len(ids) > 12 else ''}")
    print("CVE-2026-9076 :", "présente" if "CVE-2026-9076" in ids or any(r.get("id") == "CVE-2026-9076" for x in m for r in x.get("relatedVulnerabilities", [])) else "absente")
PY
}

{
  echo "# rpm-distro.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16)"
  echo "syft $(syft version 2> /dev/null | sed -n 's/^Version: *//p'), grype $(grype version 2> /dev/null | sed -n 's/^Version: *//p'), base $(hors grype db status 2> /dev/null | grep -E 'Built' | tr -s ' ')"
  [ "$(wc -l < "$ARBRE")" = 230 ] || ko "arbre archivé : $(wc -l < "$ARBRE") lignes (attendu : 230)"
  mkdir -p "$D"
  echo "## entrées (copiées, sha256 contrôlé)"
  n=0
  for f in "$APP" "${ROCKY[@]/#/$FERM/}"; do
    b=${f##*/}
    if [ "$f" = "$APP" ]; then a=$APP_SHA; else a=$(awk -v n="$b" '$1 == n {print $3}' "$ARBRE"); fi
    [ -n "$a" ] || ko "$b absent de l'arbre archivé"
    mkdir -p "$D/$b.d" && cp -- "$f" "$D/$b.d/$b"
    s=$(sha256sum < "$D/$b.d/$b" | cut -c1-64)
    [ "$s" = "$a" ] || ko "$b : sha256 $s (attendu : $a)"
    echo "OK   $b : sha256 ${s:0:16}… = archivé"
    n=$((n + 1))
  done
  [ "$n" = 4 ] || ko "entrées : $n (attendu : 4)"
  for f in "${APP##*/}" "${ROCKY[@]}"; do
    d=$D/$f.d
    echo "## $f : syft dir: sur un dossier qui ne contient que lui"
    set +e; hors syft scan "dir:$d" -o cyclonedx-json="$D/$f.sbom.json" -q 2> "$D/$f.syft.err"; c=$?; set -e
    echo "syft : code $c ; sortie d'erreur : $(wc -l < "$D/$f.syft.err") ligne(s)"
    [ "$c" = 0 ] || { sed -n '1,5p' "$D/$f.syft.err"; continue; }
    echo "### grype sans --distro (-q, comme politique/scanner.sh)"
    set +e; hors grype "sbom:$D/$f.sbom.json" -o json --file "$D/$f.grype.json" -q 2> "$D/$f.grype.err"; c=$?; set -e
    echo "grype : code $c ; sortie d'erreur : $(wc -l < "$D/$f.grype.err") ligne(s)"
    resume "$D/$f.sbom.json" "$D/$f.grype.json"
    echo "### grype --distro $DISTRO"
    set +e; hors grype "sbom:$D/$f.sbom.json" --distro "$DISTRO" -o json --file "$D/$f.grype-distro.json" -q 2> "$D/$f.grype-distro.err"; c=$?; set -e
    echo "grype : code $c ; sortie d'erreur : $(wc -l < "$D/$f.grype-distro.err") ligne(s)"
    resume "$D/$f.sbom.json" "$D/$f.grype-distro.json" | sed -n '/^correspondances/,$p'
  done
  echo "## fin, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} 2>&1 | sed -u "s#$HOME#~#g" | sed -u '/jeton\|token/I c\[ligne masquée : motif jeton|token]' | tee "$LOG"
exit "${PIPESTATUS[0]}"
