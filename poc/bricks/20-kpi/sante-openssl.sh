#!/usr/bin/env bash
# Brique 20 : relevé de santé d'OpenSSL selon les critères de docs/04, en lecture publique seulement (API de GitHub et de Scorecard,
# tracker.debian.org, security-tracker.debian.org). Ni clone, ni téléchargement de binaire. Aucune adresse électronique n'est imprimée :
# domaines comptés seulement. Le paquet employé serait celui de Debian 13 (trixie).
# Usage (racine du dépôt) : bash poc/bricks/20-kpi/sante-openssl.sh > poc/bricks/20-kpi/resultats/<journal neuf> 2>&1
set -uo pipefail
export LC_ALL=C
R=openssl/openssl
T=$HOME/.cache/supply-chain-poc/20/sante-openssl   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/sante-openssl ] || find ~/.cache/supply-chain-poc/20/sante-openssl -delete
mkdir -p "$T"
trap 'find ~/.cache/supply-chain-poc/20/sante-openssl -delete' EXIT
gha() { env -u GITHUB_TOKEN gh api "$@"; }
echo "# sante-openssl.sh, début $(date -u +%FT%TZ), dépôt $R, script $(sha256sum < "$0" | cut -c1-16)"
echo "## Scorecard (API publique, via tools/health/scorecard.sh)"
printf 'OpenSSL\topenssl/openssl\tsignature\toui\n' > "$T/p.tsv"
bash tools/health/scorecard.sh "$T/p.tsv"
echo "## Dépôt"
gha "repos/$R" --jq '"nom \(.full_name) ; archivé \(.archived) ; licence \(.license.spdx_id) ; branche \(.default_branch) ; dernier push \(.pushed_at)"'
echo "## Releases (15 dernières)"
gha "repos/$R/releases?per_page=15" --jq '.[] | "\(.tag_name)\t\(.published_at)\tpré-release=\(.prerelease)"'
TAG=$(gha "repos/$R/releases?per_page=50" --jq '[.[] | select(.tag_name | startswith("openssl-3.5."))][0].tag_name')
echo "dernière release 3.5 : $TAG ; fichiers attachés :"
gha "repos/$R/releases/tags/$TAG" --jq '.assets[] | "  \(.name)\t\(.size)"'
echo "tag $TAG : $(gha "repos/$R/git/ref/tags/$TAG" --jq '.object.type + " " + .object.sha')"
o=$(gha "repos/$R/git/ref/tags/$TAG" --jq .object.sha)
gha "repos/$R/git/tags/$o" --jq '"tag annoté, vérification GitHub : \(.verification.verified) (\(.verification.reason))"' 2> /dev/null || echo "tag léger"
S=$(date -u -d '90 days ago' +%FT%TZ)
echo "## Activité depuis $S (branche par défaut)"
gha --paginate "repos/$R/commits?since=$S&per_page=100" --jq '.[] | [.commit.author.email, (.author.type // "?"), (.parents | length)] | @tsv' > "$T/commits" || echo "KO   commits"
echo "commits : $(wc -l < "$T/commits") ; auteurs distincts (adresse) : $(cut -f1 "$T/commits" | sort -u | wc -l) ; commits de robots : $(awk -F'\t' '$2 == "Bot"' "$T/commits" | wc -l)"
echo "part du premier auteur : $(cut -f1 "$T/commits" | sort | uniq -c | sort -rn | awk 'NR == 1 {print $1}') commits"
echo "domaines (auteurs, commits) :"
cut -f1 "$T/commits" | awk -F@ '{d = $NF; n[d]++; if (!(($0) in vu)) {vu[$0] = 1; a[d]++}} END {for (d in n) print "  " d " : " a[d] " auteurs, " n[d] " commits"}' | sort -t, -k2 -rn | head -20
echo "## Processus de sécurité"
for f in SECURITY.md .github/SECURITY.md; do gha "repos/$R/contents/$f" --silent 2> /dev/null && echo "présent : $f" || echo "absent : $f"; done
curl -fsS --max-time 20 -o /dev/null -w 'politique https://openssl-library.org/policies/general/security-policy/ : HTTP %{http_code}\n' -L https://openssl-library.org/policies/general/security-policy/ || echo "politique : non lue"
echo "avis publiés (GHSA du dépôt) : $(gha "repos/$R/security-advisories?per_page=50" --jq length 2> /dev/null || echo 'non lus')"
echo "CLA : $(gha "repos/$R/contents/CONTRIBUTING.md" --jq .content 2> /dev/null | base64 -d 2> /dev/null | grep -ciE 'contributor license agreement|\bCLA\b') mention(s) dans CONTRIBUTING.md"
echo "## Debian trixie (source openssl)"
curl -fsS --max-time 30 'https://api.ftp-master.debian.org/madison?package=openssl&s=trixie,trixie-security,trixie-updates&f=json' | jq -r '.[] | .openssl | to_entries[] | "\(.key)\t\(.value | keys | join(" "))"' || echo "KO   madison"
curl -fsS --max-time 120 -o "$T/st.html" https://security-tracker.debian.org/tracker/source-package/openssl && \
  python3 -I - "$T/st.html" <<'PY'
import html, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
def texte(x): return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", x)).split())
for titre, bloc in re.findall(r"<h2>(.*?)</h2>(.*?)(?=<h2>|</body>)", t, re.S):
    if re.match(r"Available versions|Open ", texte(titre)):
        print("-", texte(titre))
        for ligne in re.findall(r"<tr>(.*?)</tr>", bloc, re.S):
            print("  " + " | ".join(texte(c)[:90] for c in re.findall(r"<t[hd].*?>(.*?)</t[hd]>", ligne, re.S)))
PY
echo "fin $(date -u +%FT%TZ)"
