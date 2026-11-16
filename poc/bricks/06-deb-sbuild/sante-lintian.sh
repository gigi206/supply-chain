#!/usr/bin/env bash
# Brique 06, révision 1.0.0-2, étape lintian, commande 0 : santé de lintian selon les critères du doc 04 (§1), sans rien installer.
# Préparé à sec le 16/11/2026, sans accord nommé, en suite de la décision du propriétaire « Relevé de santé d'abord (Recommandé) » :
# lintian n'a aucun verdict au doc 04, et ce relevé passe avant tout lancement de lintian.sh. Prédictions :
# resultats/lintian-predictions.md (Z1 à Z7). Lectures publiques et anonymes seulement (https, redirections https comprises), rien
# d'écrit hors de ~/.cache/supply-chain-poc/06/sante-lintian et des journaux.
#   salsa   projet lintian/lintian sur salsa.debian.org (API GitLab v4) : archivé, branche par défaut, dernière activité ; derniers
#           tags et leur date ; signature du tag le plus récent telle que l'API la rapporte (404 = aucune signature rapportée par
#           cette API, ce qui ne prouve pas l'absence de signature GPG) ; commits de la branche par défaut sur 90 jours (plafond de
#           10 pages de 100, signalé), auteurs et domaines des adresses ; fusionneurs de 100 MR fusionnées, les plus récemment
#           mises à jour, et période couverte ; SECURITY.md à la racine. Scorecard : sans objet hors GitHub (n/d).
#   debian  sources.debian.org : versions de lintian et suites ; changelog de la version de sid : 12 dernières entrées, date de
#           l'entrée de la version employée, entrées et signataires sur 6 et 12 mois (lecture arrêtée à la première entrée de plus
#           de 12 mois après la version employée, entrées illisibles comptées) ; Maintainer et Uploaders de debian/control ;
#           security-tracker.debian.org : entrées CVE et TEMP de la page du paquet source, rubriques ouvertes et résolues présentes
#           ou non (le compte ne distingue pas ouvert de résolu).
# Toute lecture ou analyse en échec écrit une ligne KO (erreur HTTP distincte d'une réponse vide ; forme de réponse inattendue) et
# arrête l'étape ; le code de sortie vaut 1 dès qu'une ligne KO sort.
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/06-deb-sbuild/sante-lintian.sh salsa|debian…
#   (journal : resultats/sante-lintian-<étape>.log)
set -uo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
T=$HOME/.cache/supply-chain-poc/06/sante-lintian
DEPUIS=$(date -u -d '90 days ago' +%Y-%m-%dT00:00:00Z)
PLAFOND=10
P=https://salsa.debian.org/api/v4/projects/lintian%2Flintian
SRC=https://sources.debian.org
V_EMPLOYEE=2.122.0   # celle de l'instantané 20261105T000000Z, suite trixie (lintian.sh)
mkdir -p "$R" "$T"

ko() { echo "KO   $*"; return 1; }
code_http() { # $1 = URL, $2 = fichier ; écrit le code HTTP (ou « erreur curl N »)
  curl -sS -L --proto =https --proto-redir =https --max-time 60 -o "$2" -w '%{http_code}' "$1" || echo "erreur curl $?"
}
lire() { # $1 = URL, $2 = fichier ; rend 0 si HTTP 200, écrit une ligne KO sinon
  local code
  code=$(code_http "$1" "$2")
  [ "$code" = 200 ] || ko "$1 : HTTP $code"
}
jqm() { # jq dont l'échec (forme de réponse inattendue) écrit une ligne KO
  jq "$@" || ko "jq, forme inattendue : ${*: -1}"
}

etape_salsa() {
  local b n p tag code s
  echo "## salsa.debian.org, lintian/lintian (fenêtre des commits : depuis $DEPUIS)"
  lire "$P" "$T/projet.json" || return 1
  jqm -r '"nom \(.path_with_namespace), archivé \(.archived), branche \(.default_branch), dernière activité \(.last_activity_at[0:10]), créé \(.created_at[0:10])"' "$T/projet.json" || return 1
  b=$(jqm -r .default_branch "$T/projet.json") || { echo "$b"; return 1; }
  [ -n "$b" ] && [ "$b" != null ] || ko "branche par défaut absente" || return 1
  echo "## derniers tags"
  lire "$P/repository/tags?per_page=8&order_by=updated" "$T/tags.json" || return 1
  jqm -r '.[] | "  \(.name) : commit du \(.commit.committed_date[0:10]), tag créé \(.created_at // "-" | .[0:10]), annoté \(.message != null and .message != "")"' "$T/tags.json" || return 1
  tag=$(jqm -r '.[0].name // empty' "$T/tags.json") || { echo "$tag"; return 1; }
  [ -n "$tag" ] || ko "aucun tag" || return 1
  code=$(code_http "$P/repository/tags/$(jq -rn --arg t "$tag" '$t|@uri')/signature" "$T/sig.json")
  if [ "$code" = 200 ]; then
    s=$(jqm -r '"type \(.signature_type), statut \(.verification_status // "-"), clé \(.gpg_key_primary_keyid // .x509_certificate.subject // "-")"' "$T/sig.json") || { echo "$s"; return 1; }
    echo "signature du tag $tag rapportée par l'API : $s"
  else echo "signature du tag $tag : aucune rapportée par l'API, HTTP $code (404 ne prouve pas l'absence de signature GPG)"; fi
  echo "## commits de $b depuis $DEPUIS"
  : > "$T/commits.tsv"
  for p in $(seq "$PLAFOND"); do
    lire "$P/repository/commits?ref_name=$b&since=$DEPUIS&per_page=100&page=$p" "$T/page.json" || return 1
    jqm -r '.[] | [.author_name, (.author_email | split("@") | last), .committed_date[0:10]] | @tsv' "$T/page.json" > "$T/page.tsv" || { cat "$T/page.tsv"; return 1; }
    cat "$T/page.tsv" >> "$T/commits.tsv"
    [ "$(wc -l < "$T/page.tsv")" = 100 ] || break
  done
  n=$(wc -l < "$T/commits.tsv")
  if [ "$n" -ge $((PLAFOND * 100)) ]; then echo "commits : au moins $n (plafond atteint)"; else echo "commits : $n"; fi
  echo "plus récent : $(cut -f3 "$T/commits.tsv" | sort | tail -1), plus ancien : $(cut -f3 "$T/commits.tsv" | sort | head -1)"
  echo "auteurs (nom, domaine de l'adresse), robots compris, nommés tels quels :"
  cut -f1,2 "$T/commits.tsv" | sort | uniq -c | sort -rn | awk 'NR <= 12' | sed 's/^/  /'
  echo "auteurs distincts : $(cut -f1 "$T/commits.tsv" | sort -u | wc -l)"
  echo "## 100 MR fusionnées, les plus récemment mises à jour"
  lire "$P/merge_requests?state=merged&order_by=updated_at&sort=desc&per_page=100" "$T/mr.json" || return 1
  s=$(jqm -r --arg d "$DEPUIS" '"MR lues : \(length) ; fusionnées entre \([.[].merged_at // empty] | min | .[0:10]) et \([.[].merged_at // empty] | max | .[0:10]) ; fusionnées depuis \($d) : \([.[] | select((.merged_at // "") >= $d)] | length)\nfusionneurs : \([.[] | .merged_by.username // "-"] | group_by(.) | map("\(.[0]) \(length)") | sort_by(-(split(" ")[1] | tonumber)) | join(", "))"' "$T/mr.json") || { echo "$s"; return 1; }
  echo "$s"
  echo "## SECURITY.md à la racine de $b"
  echo "SECURITY.md : HTTP $(code_http "$P/repository/files/SECURITY.md?ref=$b" /dev/null) (404 = absent)"
  echo "## Scorecard : n/d (projet hors GitHub)"
}

etape_debian() {
  local sid s
  echo "## sources.debian.org, versions de lintian et suites"
  lire "$SRC/api/src/lintian/" "$T/versions.json" || return 1
  s=$(jqm -r '.versions[] | "  \(.version) : \(.suites | join(", "))"' "$T/versions.json") || { echo "$s"; return 1; }
  head -12 <<< "$s"
  s=$(jqm -r --arg v "$V_EMPLOYEE" '[.versions[] | select(.version == $v) | .suites[]] | join(", ") | if . == "" then "absente de la liste" else . end' "$T/versions.json") || { echo "$s"; return 1; }
  echo "version employée $V_EMPLOYEE, suites : $s"
  sid=$(jqm -r '[.versions[] | select(.suites | index("sid")) | .version] | first // empty' "$T/versions.json") || { echo "$sid"; return 1; }
  [ -n "$sid" ] || ko "aucune version dans sid" || return 1
  echo "version de sid : $sid"
  echo "## debian/changelog de $sid"
  lire "$SRC/data/main/l/lintian/$sid/debian/changelog" "$T/changelog" || return 1
  python3 -I - "$T/changelog" "$V_EMPLOYEE" <<'PY' || ko "analyse du changelog" || return 1
import re, sys
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
maint = datetime.now(timezone.utc)
an = maint - timedelta(days=365)
entrees, illisibles, v, employee, vue = [], 0, None, None, False
for l in open(sys.argv[1], encoding='utf-8', errors='replace'):
    m = re.match(r'^lintian \(([^)]+)\) ([^;]+);', l)
    if m:
        v = (m.group(1), m.group(2).strip())
        continue
    m = re.match(r'^ -- (.+?) <[^@>]+@([^>]+)>  (.+)$', l.rstrip('\n'))
    if not (m and v):
        continue
    try:
        d = parsedate_to_datetime(m.group(3))
        if d.tzinfo is None:
            raise ValueError('sans fuseau')
    except (TypeError, ValueError, IndexError):
        illisibles += 1
        v = None
        continue
    entrees.append((v[0], v[1], m.group(1), m.group(2), d))
    if v[0] == sys.argv[2]:
        employee, vue = entrees[-1], True
    v = None
    if vue and d < an:
        break
if not entrees:
    print('KO   aucune entrée lisible dans le changelog')
    sys.exit(1)
for e in entrees[:12]:
    print(f'  {e[0]} ({e[1]}) : {e[4].astimezone(timezone.utc):%Y-%m-%d}, {e[2]} ({e[3]})')
print(f'entrée de la version employée {sys.argv[2]} : ' + (f'{employee[4].astimezone(timezone.utc):%Y-%m-%d}, {employee[2]} ({employee[3]})' if employee else 'absente des entrées lues'))
for j, nom in ((183, '6 mois'), (365, '12 mois')):
    s = [e for e in entrees if e[4] >= maint - timedelta(days=j)]
    print(f'entrées sur {nom} : {len(s)}, signataires distincts : {len({e[2] for e in s})}')
print(f'entrées lues : {len(entrees)}, illisibles : {illisibles}')
PY
  echo "## debian/control de $sid : Maintainer et Uploaders"
  lire "$SRC/data/main/l/lintian/$sid/debian/control" "$T/control" || return 1
  awk '/^Maintainer:/ {print "  " $0} /^Uploaders:/ {u = 1; print "  " $0; next} u && /^[ \t]/ {print "  " $0; next} {u = 0}' "$T/control" \
    | sed -E 's/<[^@>]+@([^>]+)>/<…@\1>/g'
  grep -q '^Maintainer:' "$T/control" || ko "Maintainer absent de debian/control" || return 1
  echo "## security-tracker.debian.org, paquet source lintian"
  lire https://security-tracker.debian.org/tracker/source-package/lintian "$T/securite.html" || return 1
  echo "entrées CVE : $(grep -o -E 'CVE-[0-9]{4}-[0-9]+' "$T/securite.html" | sort -u | wc -l) ; entrées TEMP : $(grep -o -E 'TEMP-[0-9]+-[0-9A-F]+' "$T/securite.html" | sort -u | wc -l) (ouvertes et résolues confondues)"
  echo "rubriques : « Open issues » $(grep -q 'Open issues' "$T/securite.html" && echo présente || echo absente) ; « Resolved issues » $(grep -q 'Resolved issues' "$T/securite.html" && echo présente || echo absente)"
  grep -o -E 'CVE-[0-9]{4}-[0-9]+' "$T/securite.html" | sort -u | tail -8 | sed 's/^/  /'
}

[ $# -gt 0 ] || { echo "usage : $0 salsa|debian…" >&2; exit 2; }
rc=0
for e in "$@"; do
  case $e in
    salsa|debian) { echo "# sante-lintian.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "etape_$e" 2>&1 || echo "KO   étape $e"; } \
      | sed -E 's/.*([Jj][Ee][Tt][Oo][Nn]|[Tt][Oo][Kk][Ee][Nn]).*/[ligne masquée : motif jeton|token]/' | tee "$R/sante-lintian-$e.log"
      grep -q '^KO' "$R/sante-lintian-$e.log" && rc=1 ;;
    *) echo "étape inconnue : $e" >&2; exit 2 ;;
  esac
done
exit "$rc"
