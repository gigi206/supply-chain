#!/usr/bin/env bash
# Brique 09 : relevé amont des options de signature OpenPGP, en lecture publique. N'installe rien, n'exécute rien de téléchargé.
# Les fichiers téléchargés vont dans un dossier neuf et vide (~/.cache/supply-chain-poc/09/releve-<horodatage>), sont listés
# avec nom, origine, taille et sha256, et sont lus par python3 -I ou par gpgv (vérification de signature seulement).
# gpg ne tourne qu'avec un --homedir neuf et dédié, jamais avec le trousseau de l'utilisateur.
# Journal : resultats/releve-amont.log ; liste des téléchargements : resultats/releve-amont-telechargements.tsv.
# Appels anonymes à l'API GitHub : au plus 26 (quota partagé de 60 par heure), regroupés ici.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
TS=$(date -u '+%Y%m%dT%H%M%SZ')
BASE=$HOME/.cache/supply-chain-poc/09
D=$BASE/releve-$TS
G=$BASE/gnupg-releve-$TS
mkdir -p "$BASE" "$R"
mkdir "$D"            # échoue s'il existe : dossier neuf et vide
mkdir -m 700 "$G"
cd "$BASE"            # jamais dans le dossier des téléchargements
LISTE=$R/releve-amont-telechargements.tsv
printf 'nom\torigine\toctets\tsha256\n' > "$LISTE"

ROCKY=9.8
ROCKY_FPR=21CB256AE16FC54C6E652949702D426D350D275D   # doc 04, §5 (clé Rocky 9, relevée en brique 05)
RPM_TAG=rpm-4.16.1.3
APT_TAG=3.0.3
DEPUIS=$(date -u -d '90 days ago' '+%Y-%m-%dT%H:%M:%SZ')

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g'; }

# dl NOM URL : télécharge dans $D, journalise nom, origine, taille, sha256 ; code 1 si échec.
dl() {
  if curl -fsSL --max-time 300 -o "$D/$1" "$2"; then
    local n s
    n=$(stat -c %s "$D/$1"); s=$(sha256sum "$D/$1" | cut -c1-64)
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$n" "$s" >> "$LISTE"
    echo "téléchargé : $1 ($n octets, sha256 $s) depuis $2"
  else
    echo "ÉCHEC du téléchargement : $1 depuis $2"; return 1
  fi
}
code() { curl -sS -o /dev/null -L --max-time 30 -w '%{http_code}' "$1" || echo erreur; }
gh() { curl -fsSL --max-time 30 -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"; }
gl() { curl -fsSL --max-time 30 "$1/api/v4/projects/$2$3"; }

# Python lancé depuis $BASE, avec -I, sur des chemins passés en argument.
py() { python3 -I - "$@"; }

releve() {
  set +e   # un relevé incomplet reste journalisé : chaque échec est écrit, rien n'arrête la suite
  echo "relevé commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "dossier des téléchargements : $D (neuf) ; homedir gpg dédié : $G (neuf, 0700)"
  echo "fenêtre des 90 jours : depuis $DEPUIS"
  echo "gpg de l'hôte : $(gpg --version | head -1) ; gpgv : $(gpgv --version | head -1)"

  echo; echo "## 1. GnuPG amont : swdb.lst signé, clés de release"
  dl swdb.lst https://versions.gnupg.org/swdb.lst || true
  dl swdb.lst.sig https://versions.gnupg.org/swdb.lst.sig || true
  dl signature_key.asc https://gnupg.org/signature_key.asc || true
  dl signature_key.html https://gnupg.org/signature_key.html || true
  echo "empreintes de signature_key.asc (gpg --show-keys, homedir dédié) :"
  gpg --homedir "$G" --batch --show-keys --with-colons "$D/signature_key.asc" 2>/dev/null \
    | awk -F: '$1=="pub"{a=$4; l=$3; c=$6} $1=="fpr"&&a!=""{print "  fpr " $10 " algo " a " bits " l " créée " strftime("%Y-%m-%d", c, 1); a=""} $1=="uid"{print "  uid " $10}' | masquer
  echo "empreintes citées dans signature_key.html (même site, recoupement faible) :"
  py "$D/signature_key.html" <<'PY'
import re, sys, html
t = html.unescape(open(sys.argv[1], encoding="utf-8", errors="replace").read())
for m in sorted(set(re.findall(r"(?:[0-9A-F]{4} ?){10}", t))):
    print("  " + m.replace(" ", ""))
PY
  gpg --homedir "$G" --batch --quiet --dearmor -o "$D/gnupg-cles.gpg" "$D/signature_key.asc" 2>/dev/null \
    && echo "clés converties en trousseau : $D/gnupg-cles.gpg ($(stat -c %s "$D/gnupg-cles.gpg") octets, produit localement)"
  echo "vérification de swdb.lst par gpgv contre ces clés :"
  gpgv --keyring "$D/gnupg-cles.gpg" "$D/swdb.lst.sig" "$D/swdb.lst" 2>&1 | sed 's/^/  /' | masquer || echo "  gpgv : code non nul"
  echo "lignes gnupg de swdb.lst :"
  grep -E '^gnupg[0-9]*_(ver|date|branch|eol)' "$D/swdb.lst" | sed 's/^/  /' || true
  dl gnupg-download.html https://gnupg.org/download/index.html || true
  echo "page de téléchargement, phrases sur la fin de vie et les branches :"
  py "$D/gnupg-download.html" <<'PY'
import re, sys, html
t = re.sub(r"<[^>]+>", " ", html.unescape(open(sys.argv[1], encoding="utf-8", errors="replace").read()))
t = re.sub(r"\s+", " ", t)
for m in re.finditer(r"[^.]{0,160}(?:end[- ]of[- ]life|EOL|LTS|long term|stable version|devel)[^.]{0,160}\.", t, re.I):
    print("  « " + m.group(0).strip()[:320] + " »")
PY
  dl gnupg-security.html https://gnupg.org/documentation/security.html || true
  echo "page sécurité, phrases sur le signalement :"
  py "$D/gnupg-security.html" <<'PY'
import re, sys, html
t = re.sub(r"<[^>]+>", " ", html.unescape(open(sys.argv[1], encoding="utf-8", errors="replace").read()))
t = re.sub(r"\s+", " ", t)
for m in re.finditer(r"[^.]{0,160}(?:report|security|CVE|advisor)[^.]{0,160}\.", t, re.I):
    print("  « " + m.group(0).strip()[:320] + " »")
PY

  echo; echo "## 2. Dépôts GitHub (API anonyme) : GnuPG (miroir gpg/gnupg), obs-sign, SoftHSMv2, gnupg-pkcs11-scd, siguldry, vault-gpg-plugin"
  for r in gpg/gnupg openSUSE/obs-sign softhsm/SoftHSMv2 alonbl/gnupg-pkcs11-scd fedora-infra/siguldry LeSuisse/vault-gpg-plugin; do
    f=${r//\//_}
    echo "### $r"
    gh "repos/$r" > "$D/$f-repo.json" && printf '%s\t%s\t%s\t%s\n' "$f-repo.json" "https://api.github.com/repos/$r" "$(stat -c %s "$D/$f-repo.json")" "$(sha256sum "$D/$f-repo.json" | cut -c1-64)" >> "$LISTE" || echo "  ÉCHEC repo"
    gh "repos/$r/releases?per_page=5" > "$D/$f-releases.json" && printf '%s\t%s\t%s\t%s\n' "$f-releases.json" "https://api.github.com/repos/$r/releases?per_page=5" "$(stat -c %s "$D/$f-releases.json")" "$(sha256sum "$D/$f-releases.json" | cut -c1-64)" >> "$LISTE" || echo "  ÉCHEC releases"
    gh "repos/$r/tags?per_page=5" > "$D/$f-tags.json" && printf '%s\t%s\t%s\t%s\n' "$f-tags.json" "https://api.github.com/repos/$r/tags?per_page=5" "$(stat -c %s "$D/$f-tags.json")" "$(sha256sum "$D/$f-tags.json" | cut -c1-64)" >> "$LISTE" || echo "  ÉCHEC tags"
    gh "repos/$r/commits?since=$DEPUIS&per_page=100" > "$D/$f-commits.json" && printf '%s\t%s\t%s\t%s\n' "$f-commits.json" "https://api.github.com/repos/$r/commits?since=$DEPUIS&per_page=100" "$(stat -c %s "$D/$f-commits.json")" "$(sha256sum "$D/$f-commits.json" | cut -c1-64)" >> "$LISTE" || echo "  ÉCHEC commits"
    py "$D/$f-repo.json" "$D/$f-releases.json" "$D/$f-tags.json" "$D/$f-commits.json" <<'PY'
import json, sys, collections
def lire(p):
    try: return json.load(open(p))
    except Exception: return None
repo, rel, tags, com = (lire(p) for p in sys.argv[1:5])
if repo: print(f"  archivé {repo.get('archived')}, défaut {repo.get('default_branch')}, dernier push {repo.get('pushed_at')}, licence {(repo.get('license') or {}).get('spdx_id')}, miroir {repo.get('mirror_url')}, description « {repo.get('description')} »")
if rel is not None:
    print(f"  releases GitHub : {len(rel)} lue(s)")
    for x in rel[:5]:
        print(f"    {x.get('tag_name')} publiée {x.get('published_at')} brouillon {x.get('draft')} préversion {x.get('prerelease')} fichiers {[a['name'] for a in x.get('assets', [])][:8]}")
if tags is not None:
    print(f"  tags (ordre de l'API, 5 au plus) : {[t['name'] for t in tags]}")
    if tags: print(f"  commit du premier tag : {tags[0]['commit']['sha']}")
if com is not None:
    n = len(com)
    dom = collections.Counter()
    noms = collections.Counter()
    for c in com:
        a = c["commit"]["author"]
        e = (a.get("email") or "").lower()
        dom[e.split("@")[-1] if "@" in e else "?"] += 1
        noms[a.get("name")] += 1
    print(f"  commits depuis 90 jours : {n}{' (page pleine : au moins 100)' if n == 100 else ''} ; auteurs distincts {len(noms)}")
    print(f"  domaines des adresses d'auteur : {dict(dom.most_common(8))}")
    print(f"  part du premier auteur : {noms.most_common(1)[0][1] if noms else 0} commits sur {n}")
    if com: print(f"  dernier commit : {com[0]['commit']['committer']['date']}")
PY
    sha=$(py "$D/$f-tags.json" <<'PY'
import json, sys
try:
    t = json.load(open(sys.argv[1])); print(t[0]["commit"]["sha"] if t else "")
except Exception: print("")
PY
)
    if [ -n "$sha" ] && [ "$(py "$D/$f-releases.json" <<'PY'
import json, sys
try: print(len(json.load(open(sys.argv[1]))))
except Exception: print(0)
PY
)" = 0 ]; then
      echo "  date du commit du premier tag (pas de release GitHub) : $(gh "repos/$r/commits/$sha" | python3 -I -c 'import json,sys; d=json.load(sys.stdin)["commit"]; print(d["committer"]["date"], "auteur", d["author"]["date"])' 2>/dev/null || echo 'non lue')"
    fi
    for s in SECURITY.md .github/SECURITY.md docs/SECURITY.md; do
      echo "  $s (raw, branche par défaut) : HTTP $(code "https://raw.githubusercontent.com/$r/HEAD/$s")"
    done
    echo "  Scorecard (API publique) : $(curl -fsSL --max-time 30 "https://api.securityscorecards.dev/projects/github.com/$r" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); c={x["name"]:x["score"] for x in d["checks"]}; print(d["score"], d["date"][:10], "Maintained", c.get("Maintained"), "Signed-Releases", c.get("Signed-Releases"), "Code-Review", c.get("Code-Review"), "Vulnerabilities", c.get("Vulnerabilities"))' 2>/dev/null || echo n/d)"
  done

  echo; echo "## 3. Dépôts GitLab : salsa (apt, devscripts, gnupg2 de Debian, debsigs, debsig-verify, reprepro), gitlab.com (Sequoia)"
  for e in "https://salsa.debian.org apt-team%2Fapt" "https://salsa.debian.org debian%2Fdevscripts" "https://salsa.debian.org debian%2Fgnupg2" \
           "https://salsa.debian.org debian%2Fdebsigs" "https://salsa.debian.org debian%2Fdebsig-verify" "https://salsa.debian.org debian%2Freprepro" \
           "https://gitlab.com sequoia-pgp%2Fsequoia-sqv" "https://gitlab.com sequoia-pgp%2Fsequoia"; do
    set -- $e
    f=gl_${2//%2F/_}
    echo "### $1 ${2//%2F//}"
    gl "$1" "$2" "" > "$D/$f-projet.json" || echo "  ÉCHEC projet"
    gl "$1" "$2" "/repository/tags?per_page=5" > "$D/$f-tags.json" || echo "  ÉCHEC tags"
    gl "$1" "$2" "/repository/commits?since=$DEPUIS&per_page=100" > "$D/$f-commits.json" || echo "  ÉCHEC commits"
    for k in projet tags commits; do
      [ -s "$D/$f-$k.json" ] && printf '%s\t%s\t%s\t%s\n' "$f-$k.json" "$1/api/v4/projects/$2 ($k)" "$(stat -c %s "$D/$f-$k.json")" "$(sha256sum "$D/$f-$k.json" | cut -c1-64)" >> "$LISTE"
    done
    py "$D/$f-projet.json" "$D/$f-tags.json" "$D/$f-commits.json" <<'PY'
import json, sys, collections
def lire(p):
    try: return json.load(open(p))
    except Exception: return None
p, t, c = (lire(x) for x in sys.argv[1:4])
if p: print(f"  archivé {p.get('archived')}, dernière activité {p.get('last_activity_at')}, défaut {p.get('default_branch')}")
if t is not None:
    for x in t[:5]:
        print(f"    tag {x['name']} commit {x['commit']['committed_date']}")
if c is not None:
    dom = collections.Counter((x.get("author_email") or "?").lower().split("@")[-1] for x in c)
    noms = collections.Counter(x.get("author_name") for x in c)
    print(f"  commits depuis 90 jours (branche par défaut) : {len(c)}{' (page pleine : au moins 100)' if len(c) == 100 else ''} ; auteurs distincts {len(noms)} ; premier auteur {noms.most_common(1)[0][1] if noms else 0}")
    print(f"  domaines des adresses d'auteur : {dict(dom.most_common(8))}")
PY
  done

  echo; echo "## 4. Debian 13 (madison, suites trixie)"
  curl -fsSL --max-time 30 "https://api.ftp-master.debian.org/madison?package=gnupg+gpg+gpgv+gpg-agent+sqv+apt+apt-utils+devscripts+debsigs+debsig-verify+reprepro+softhsm2+gnupg-pkcs11-scd+dpkg-sig+debusine-signing+obs-signd+sq&f=json&s=trixie,trixie-updates,trixie-security,trixie-proposed-updates" \
    | python3 -I -c 'import json,sys
vus=set()
for e in json.load(sys.stdin):
    for p, s in e.items():
        vus.add(p)
        for su, vs in s.items():
            print("  ", p, su, *vs.keys())
for p in "gnupg gpg gpgv gpg-agent sqv apt apt-utils devscripts debsigs debsig-verify reprepro softhsm2 gnupg-pkcs11-scd dpkg-sig debusine-signing obs-signd sq".split():
    if p not in vus: print("   absent de trixie (madison) :", p)'

  echo; echo "## 5. apt $APT_TAG (salsa) : vérificateur et politique"
  dl apt-default-sequoia.config "https://salsa.debian.org/apt-team/apt/-/raw/$APT_TAG/debian/default-sequoia.config" || true
  sed 's/^/  /' "$D/apt-default-sequoia.config" 2>/dev/null | head -60
  dl apt-sqv.cc "https://salsa.debian.org/apt-team/apt/-/raw/$APT_TAG/methods/sqv.cc" || true
  echo "  methods/sqv.cc, lignes citant gpgv, sqv, policy, Signed-By :"
  grep -n -iE 'gpgv|"sqv|sqv"|policy|Signed-By|SEQUOIA' "$D/apt-sqv.cc" | head -25 | sed 's/^/    /'
  dl apt-control "https://salsa.debian.org/apt-team/apt/-/raw/$APT_TAG/debian/control" || true
  echo "  debian/control, dépendances vers sqv ou gpgv :"
  grep -n -E 'sqv|gpgv' "$D/apt-control" | sed 's/^/    /'

  echo; echo "## 6. rpm amont, tag $RPM_TAG (base de rpm-4.16.1.3 de Rocky, correctifs de la distribution non lus)"
  dl rpmsign.8 "https://raw.githubusercontent.com/rpm-software-management/rpm/$RPM_TAG/doc/rpmsign.8" || true
  echo "  rpmsign.8, options et macros :"
  grep -n -E 'addsign|resign|delsign|_gpg_name|__gpg|fskpath|signfiles|rpmv3|key-id' "$D/rpmsign.8" | head -20 | sed 's/^/    /'
  dl rpm-macros.in "https://raw.githubusercontent.com/rpm-software-management/rpm/$RPM_TAG/macros.in" || true
  echo "  macros.in, commande de signature :"
  grep -n -A4 -E '^%__gpg_sign_cmd|^%__gpg[[:space:]]|^#%_gpg_name|^%_openpgp' "$D/rpm-macros.in" | head -20 | sed 's/^/    /'
  for x in rpmio/rpmpgp.c rpmio/digest_openssl.c rpmio/digest_libgcrypt.c rpmio/digest_nss.c; do
    n=${x//\//_}
    dl "$n" "https://raw.githubusercontent.com/rpm-software-management/rpm/$RPM_TAG/$x" || continue
    echo "  $x : occurrences EDDSA $(grep -c 'EDDSA' "$D/$n"), RSA $(grep -c 'PGPPUBKEYALGO_RSA' "$D/$n"), ECDSA $(grep -c 'ECDSA' "$D/$n")"
  done

  echo; echo "## 7. Rocky $ROCKY (BaseOS, AppStream) : repomd.xml vérifié, versions dans primary.xml"
  dl RPM-GPG-KEY-Rocky-9 "https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9" || true
  echo "  empreinte de la clé : $(gpg --homedir "$G" --batch --show-keys --with-colons "$D/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}') (attendue $ROCKY_FPR, doc 04)"
  gpg --homedir "$G" --batch --quiet --dearmor -o "$D/rocky9.gpg" "$D/RPM-GPG-KEY-Rocky-9" 2>/dev/null || true
  for depot in BaseOS AppStream; do
    u=https://dl.rockylinux.org/pub/rocky/$ROCKY/$depot/x86_64/os
    dl "rocky-$depot-repomd.xml" "$u/repodata/repomd.xml" || continue
    dl "rocky-$depot-repomd.xml.asc" "$u/repodata/repomd.xml.asc" || continue
    if gpgv --keyring "$D/rocky9.gpg" "$D/rocky-$depot-repomd.xml.asc" "$D/rocky-$depot-repomd.xml" >/dev/null 2>&1; then
      echo "  $depot : repomd.xml vérifié par gpgv avec la clé Rocky 9"
    else
      echo "  $depot : repomd.xml NON VÉRIFIÉ, primary non lu"; continue
    fi
    loc=$(py "$D/rocky-$depot-repomd.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {"r": "http://linux.duke.edu/metadata/repo"}
for d in ET.parse(sys.argv[1]).getroot().findall("r:data", ns):
    if d.get("type") == "primary":
        print(d.find("r:location", ns).get("href"), d.find("r:checksum", ns).text)
PY
)
    set -- $loc
    dl "rocky-$depot-primary.xml.gz" "$u/$1" || continue
    s=$(sha256sum "$D/rocky-$depot-primary.xml.gz" | cut -c1-64)
    [ "$s" = "$2" ] && echo "  $depot : primary.xml.gz égal au sha256 du repomd vérifié" || { echo "  $depot : primary.xml.gz DIFFÉRENT du repomd"; continue; }
    py "$D/rocky-$depot-primary.xml.gz" <<'PY'
import gzip, sys, time, xml.etree.ElementTree as ET
ns = {"c": "http://linux.duke.edu/metadata/common"}
voulus = {"gnupg2", "gnupg2-smime", "rpm", "rpm-sign", "rpm-sign-libs", "softhsm", "createrepo_c", "libgcrypt", "gpgme", "opensc", "p11-kit", "sequoia-sq", "sequoia-sqv", "rpm-sequoia"}
vus = {}
for p in ET.parse(gzip.open(sys.argv[1])).getroot().findall("c:package", ns):
    n = p.find("c:name", ns).text
    if n in voulus and p.find("c:arch", ns).text in ("x86_64", "noarch"):
        v = p.find("c:version", ns)
        t = int(p.find("c:time", ns).get("build"))
        vus.setdefault(n, []).append(f"{v.get('ver')}-{v.get('rel')} construit {time.strftime('%Y-%m-%d', time.gmtime(t))} sha256 {p.find('c:checksum', ns).text[:16]}…")
for n in sorted(vus):
    for x in vus[n][-2:]:
        print(f"    {n} {x}")
print("    absents de ce dépôt :", sorted(voulus - set(vus)))
PY
  done

  echo; echo "## 8. EPEL 9 (liste de répertoire NON SIGNÉE) : obs-signd, sigul, gnupg-pkcs11-scd"
  for l in o s g; do
    curl -fsSL --max-time 60 "https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/$l/" \
      | grep -oE '"(obs-signd|sigul|sigul-server|sigul-bridge|gnupg-pkcs11-scd)-[0-9][^"]*\.rpm"' | tr -d '"' | sort -uV | sed 's/^/  /' || true
  done

  echo; echo "## 9. sigul (pagure.io) et siguldry"
  echo "  tags de https://pagure.io/sigul.git (git ls-remote, aucune écriture) :"
  git ls-remote --tags https://pagure.io/sigul.git 2>&1 | awk '{print $2}' | grep -v '\^{}' | sort -V | tail -8 | sed 's/^/    /'
  echo "  changelog du paquet sigul d'EPEL 9 (mdapi.fedoraproject.org), 4 entrées :"
  curl -fsSL --max-time 30 https://mdapi.fedoraproject.org/epel9/changelog/sigul | python3 -I -c 'import json,sys,datetime
for c in json.load(sys.stdin)["changelogs"][:4]:
    print("    ", datetime.datetime.fromtimestamp(c["date"], datetime.UTC).date(), c["changelog"].splitlines()[0][:100])' | masquer || echo "    ÉCHEC"
  dl fedora-signatures.html "https://docs.fedoraproject.org/en-US/security/cryptography/signatures/" || true
  echo "  documentation Fedora sur la signature, phrases citant Sigul ou Siguldry :"
  py "$D/fedora-signatures.html" <<'PY'
import re, sys, html
t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(open(sys.argv[1], encoding="utf-8", errors="replace").read())))
for m in re.finditer(r"[^.]{0,200}(?:Siguldry|Sigul)[^.]{0,200}\.", t):
    print("    « " + m.group(0).strip()[:360] + " »")
PY

  echo; echo "## 10. Fonctions : HSM et forme des signatures, lues dans les textes amont"
  dl obs-sign-README.md "https://raw.githubusercontent.com/openSUSE/obs-sign/HEAD/README.md" || dl obs-sign-README "https://raw.githubusercontent.com/openSUSE/obs-sign/HEAD/README" || true
  echo "  obs-sign README, lignes citant pkcs11, hsm, card, rpm, deb, gpg :"
  grep -n -iE 'pkcs|hsm|card|token|rpm|deb|gpg|agent' "$D"/obs-sign-README* 2>/dev/null | head -20 | sed 's/^/    /'
  dl siguldry-README.md "https://raw.githubusercontent.com/fedora-infra/siguldry/HEAD/README.md" || true
  echo "  siguldry README, lignes citant pkcs11, hsm, openpgp, rpm, production :"
  grep -n -iE 'pkcs|hsm|openpgp|pgp|rpm|production|stable|deploy' "$D/siguldry-README.md" 2>/dev/null | head -20 | sed 's/^/    /'
  dl vault-gpg-plugin-README.md "https://raw.githubusercontent.com/LeSuisse/vault-gpg-plugin/HEAD/README.md" || true
  echo "  vault-gpg-plugin README, lignes citant OpenBao, Vault, sign :"
  grep -n -iE 'openbao|vault|sign' "$D/vault-gpg-plugin-README.md" 2>/dev/null | head -12 | sed 's/^/    /'
  dl debusine-configure-hsm.rst "https://freexian-team.pages.debian.net/debusine/_sources/howtos/configure-hsm.rst.txt" || true
  echo "  debusine, guide HSM, lignes citant static, OpenPGP, tested :"
  grep -n -iE 'static|openpgp|tested|yubihsm|pkcs' "$D/debusine-configure-hsm.rst" 2>/dev/null | head -12 | sed 's/^/    /'
  echo "  debusine, ticket 1099 (salsa, API) : $(curl -fsSL --max-time 30 'https://salsa.debian.org/api/v4/projects/freexian-team%2Fdebusine/issues/1099' | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["state"], "«", d["title"], "» mis à jour", d["updated_at"])' 2>/dev/null || echo 'non lu')"
  dl debsign.1.gz "https://manpages.debian.org/trixie/devscripts/debsign.1.en.gz" || true
  echo "  debsign.1 (trixie), ce qui est signé :"
  py "$D/debsign.1.gz" <<'PY'
import gzip, re, sys
t = gzip.open(sys.argv[1]).read().decode("utf-8", "replace")
for l in t.splitlines():
    if re.search(r"\.dsc|\.changes|\.buildinfo|\.commands|\.deb\b|sign", l) and not l.startswith(".\\\""):
        print("    " + l[:200])
PY
  dl debsigs.1p.gz "https://manpages.debian.org/trixie/debsigs/debsigs.1p.en.gz" || true
  echo "  debsigs.1p (trixie), membres ajoutés au .deb :"
  py "$D/debsigs.1p.gz" <<'PY'
import gzip, re, sys
t = gzip.open(sys.argv[1]).read().decode("utf-8", "replace")
for l in t.splitlines():
    if re.search(r"_gpg|origin|maint|archive|ar\b", l, re.I) and not l.startswith(".\\\""):
        print("    " + l[:200])
PY
  echo "  dpkg-sig, tracker Debian : HTTP $(code https://tracker.debian.org/pkg/dpkg-sig)"
  echo "relevé fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

releve 2>&1 | masquer | tee "$R/releve-amont.log"
gpgconf --homedir "$G" --kill all 2>/dev/null || true
echo "téléchargements : $(($(wc -l < "$LISTE") - 1)) fichier(s), $(awk -F'\t' 'NR>1{s+=$3} END{print s}' "$LISTE") octets, liste dans $LISTE"
