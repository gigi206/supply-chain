#!/usr/bin/env bash
# Brique 09, O2 : troisième relevé, lecture publique, rien écrit hors du journal. Paragraphes complets du manuel de mmdebstrap
# (trixie) sur les modes « root », « unshare » lancé en root et « chrootless », pour écrire les replis de CR5.
# Journal : resultats/o2-releve-3.log.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd "$HOME/.cache/supply-chain-poc/09"
{
  echo "troisième relevé O2 commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  curl -fsSL --max-time 60 https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap.1.en.gz | python3 -I -c 'import re, sys
t = re.sub(r"\\f[BIRP]|\\&|\\\(..|\\\*\(..", "", sys.stdin.read()).replace("\\-", "-")
l = t.splitlines()
def para(debut):
    for i, x in enumerate(l):
        if x.startswith(".IP") and debut in x:
            out = []
            for y in l[i + 1:]:
                if y.startswith(".IP") or y.startswith(".SH"): break
                if not y.startswith("."): out.append(y.strip())
            return " ".join(out)
    return "(non trouvé)"
for m in ("\"sudo, root\"", "unshare", "chrootless"):
    p = para(m)
    print(f"## mode {m} ({len(p)} caractères)")
    for k in range(0, min(len(p), 1800), 180): print("  " + p[k:k + 180])'
  echo "troisième relevé O2 fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g' | tee "$here/resultats/o2-releve-3.log"
