#!/usr/bin/env bash
# Brique 09 : compléments au relevé amont (releve-amont.sh, passage 20261119T144438Z), en lecture publique.
# Relit, sans les retélécharger, des fichiers du premier passage (pages de manuel servies en clair malgré le suffixe .gz,
# primary.xml.gz de Rocky 9.8 BaseOS vérifié par son repomd signé) ; télécharge le reste dans un dossier neuf et vide.
# Journal : resultats/releve-complements.log ; téléchargements ajoutés à resultats/releve-amont-telechargements.tsv.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
P1=$HOME/.cache/supply-chain-poc/09/releve-20261119T144438Z
TS=$(date -u '+%Y%m%dT%H%M%SZ')
BASE=$HOME/.cache/supply-chain-poc/09
D=$BASE/complements-$TS
mkdir "$D"
cd "$BASE"
LISTE=$R/releve-amont-telechargements.tsv

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g'; }
dl() {
  if curl -fsSL --max-time 300 -o "$D/$1" "$2"; then
    local n s
    n=$(stat -c %s "$D/$1"); s=$(sha256sum "$D/$1" | cut -c1-64)
    printf '%s\t%s\t%s\t%s\n' "complements-$TS/$1" "$2" "$n" "$s" >> "$LISTE"
    echo "téléchargé : $1 ($n octets, sha256 $s) depuis $2"
  else
    echo "ÉCHEC du téléchargement : $1 depuis $2"; return 1
  fi
}
gh() { curl -fsSL --max-time 30 -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"; }
py() { python3 -I - "$@"; }

complements() {
  set +e
  echo "compléments commencés : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; premier passage relu : $P1 ; dossier neuf : $D"

  echo; echo "## A. debsign.1 et debsigs.1p de trixie (relus : servis en texte roff, pas en gzip)"
  for f in debsign.1.gz debsigs.1p.gz; do
    echo "### $f ($(head -c 2 "$P1/$f" | od -An -c | tr -s ' ') : début du fichier)"
    py "$P1/$f" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
t = re.sub(r"\\f[BIRP]|\\-|\\&", lambda m: "-" if m.group(0) == "\\-" else "", t)
for l in t.splitlines():
    if l.startswith('.\\"'): continue
    if re.search(r"\.dsc|\.changes|\.buildinfo|\.commands|\.deb\b|_gpg|signature|sign[s ]", l, re.I):
        print("  " + l.strip()[:220])
PY
  done

  echo; echo "## B. obs-sign : fichiers à la racine, pages de manuel, date du tag 2.8.5"
  gh "repos/openSUSE/obs-sign/contents/" | python3 -I -c 'import json,sys; print("  racine :", [x["name"] for x in json.load(sys.stdin)])'
  for m in sign.8 signd.8 sign.conf.5 README.md; do
    dl "obs-sign-$m" "https://raw.githubusercontent.com/openSUSE/obs-sign/2.8.5/$m" || continue
    echo "  $m, lignes citant pkcs11, hsm, card, token, rpm, deb, privsign, agent :"
    grep -n -iE 'pkcs|hsm|card|token|rpm|deb|privsign|agent|appimage|\-k ' "$D/obs-sign-$m" | head -15 | sed 's/^/    /'
  done
  sha=$(py "$P1/openSUSE_obs-sign-tags.json" <<'PY'
import json, sys
for t in json.load(open(sys.argv[1])):
    if t["name"] == "2.8.5": print(t["commit"]["sha"])
PY
)
  echo "  tag 2.8.5 : commit $sha ; date $(gh "repos/openSUSE/obs-sign/commits/$sha" | python3 -I -c 'import json,sys; d=json.load(sys.stdin)["commit"]; print(d["committer"]["date"])' 2>/dev/null || echo 'non lue')"

  echo; echo "## C. Fedora : documentation de la signature (adresse de redirection lue au premier passage)"
  dl fedora-signatures.html "https://docs.fedoraproject.org/en-US/fedora/security-team/cryptography/signatures/" || true
  py "$D/fedora-signatures.html" <<'PY'
import re, sys, html
t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(open(sys.argv[1], encoding="utf-8", errors="replace").read())))
for m in re.finditer(r"[^.]{0,200}(?:Siguldry|Sigul)[^.]{0,200}\.", t):
    print("  « " + m.group(0).strip()[:380] + " »")
PY

  echo; echo "## D. sigul : date du commit du tag v1.4 (git ls-remote puis page du commit sur pagure)"
  s14=$(git ls-remote --tags https://pagure.io/sigul.git 'refs/tags/v1.4^{}' 'refs/tags/v1.4' | awk '{print $1}' | tail -1)
  echo "  v1.4 → $s14"
  dl sigul-v1.4-commit.html "https://pagure.io/sigul/c/$s14" || true
  py "$D/sigul-v1.4-commit.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for m in sorted(set(re.findall(r"20[0-9]{2}-[0-9]{2}-[0-9]{2}[ T][0-9:]{5,8}(?: ?UTC)?", t)))[:6]:
    print("  date relevée dans la page :", m)
PY

  echo; echo "## E. Rocky 9.8 BaseOS (primary relu, vérifié au premier passage) : dépendances de rpm-libs et de rpm-sign"
  py "$P1/rocky-BaseOS-primary.xml.gz" <<'PY'
import gzip, sys, xml.etree.ElementTree as ET
ns = {"c": "http://linux.duke.edu/metadata/common", "rpm": "http://linux.duke.edu/metadata/rpm"}
for p in ET.parse(gzip.open(sys.argv[1])).getroot().findall("c:package", ns):
    n = p.find("c:name", ns).text
    if n not in ("rpm-libs", "rpm-sign", "rpm-sign-libs") or p.find("c:arch", ns).text != "x86_64": continue
    v = p.find("c:version", ns)
    req = [e.get("name") for e in p.findall("c:format/rpm:requires/rpm:entry", ns)]
    print(f"  {n} {v.get('ver')}-{v.get('rel')} : requires {len(req)}, dont {[r for r in req if any(k in r.lower() for k in ('sequoia', 'gpg', 'crypto', 'ssl', 'gcrypt', 'nss'))]}")
PY

  echo; echo "## F. Debian 13 : rpm et createrepo-c (madison) ; GnuPG au security tracker"
  curl -fsSL --max-time 30 "https://api.ftp-master.debian.org/madison?package=rpm+createrepo-c+libgcrypt20&f=json&s=trixie,trixie-updates,trixie-security" \
    | python3 -I -c 'import json,sys
for e in json.load(sys.stdin):
    for p, s in e.items():
        for su, vs in s.items(): print("  ", p, su, *vs.keys())'
  dl tracker-gnupg2.html "https://security-tracker.debian.org/tracker/source-package/gnupg2" || true
  py "$D/tracker-gnupg2.html" <<'PY'
import re, sys, html
t = html.unescape(open(sys.argv[1], encoding="utf-8", errors="replace").read())
cves = re.findall(r"CVE-[0-9]{4}-[0-9]+", t)
print(f"  identifiants CVE cités sur la page : {len(set(cves))} distincts ; plus récents : {sorted(set(cves), key=lambda c: (int(c.split('-')[1]), int(c.split('-')[2])))[-5:]}")
for h in re.findall(r"<h2>(.*?)</h2>", t):
    print("  section :", re.sub(r"<[^>]+>", "", h))
PY
  echo "compléments finis : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

complements 2>&1 | masquer | tee "$R/releve-complements.log"
echo "téléchargements de ce passage : $(grep -c "^complements-$TS/" "$LISTE") fichier(s)"
