#!/usr/bin/env bash
# Brique 09 : second complément au relevé amont, en lecture publique. Archive deux lectures faites à la main pendant la
# préparation (19/11/2026 vers 14:48 UTC) pour qu'aucune valeur citée ne vienne d'une lecture non journalisée :
# fichiers signd* d'obs-sign au tag 2.8.5 et sur la branche par défaut ; failles ouvertes de gnupg2 au security tracker
# (fichier du passage complements-20261119T144707Z, relu sans retéléchargement).
# Journal : resultats/releve-complements-2.log. Rien n'est écrit hors de ce journal.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
P2=$HOME/.cache/supply-chain-poc/09/complements-20261119T144707Z
cd "$HOME/.cache/supply-chain-poc/09"
{
  set +e
  echo "second complément commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo; echo "## obs-sign : fichiers signd* (API GitHub, contenu de la racine)"
  for ref in 2.8.5 master; do
    echo "  ref $ref : $(curl -fsSL --max-time 30 -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/openSUSE/obs-sign/contents/?ref=$ref" \
      | python3 -I -c 'import json,sys; print([(x["name"], x["type"], x["size"]) for x in json.load(sys.stdin) if x["name"].startswith("signd")])')"
  done
  echo "  commits de master postérieurs au tag 2.8.5 (2026-02-05T14:47:32Z), messages citant pkcs11 ou tpm :"
  curl -fsSL --max-time 30 -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/openSUSE/obs-sign/commits?since=2026-02-05T14:47:33Z&per_page=100" \
    | python3 -I -c 'import json,sys
c=json.load(sys.stdin); print("    commits :", len(c))
for x in c:
    m=x["commit"]["message"].splitlines()[0]
    if any(k in m.lower() for k in ("pkcs","tpm","hsm","token")): print("    ", x["commit"]["committer"]["date"], m[:120])'
  echo; echo "## gnupg2 au security tracker de Debian : section « Open issues » (fichier du passage complements-20261119T144707Z)"
  python3 -I - "$P2/tracker-gnupg2.html" <<'PY'
import re, sys, html
t = html.unescape(open(sys.argv[1], encoding="utf-8", errors="replace").read())
i = t.find("<h2>Open issues</h2>"); j = t.find("<h2>Resolved issues</h2>")
for row in re.findall(r"<tr>(.*?)</tr>", t[i:j], re.S):
    print("  " + " | ".join(re.sub(r"<[^>]+>|\s+", " ", c).strip() for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S))[:240])
PY
  echo "second complément fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g' | tee "$R/releve-complements-2.log"
