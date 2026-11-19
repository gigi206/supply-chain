#!/usr/bin/env bash
# Brique 09, O2 : relevé préalable, À SEC (lectures locales et publiques). N'installe rien, n'exécute rien de téléchargé,
# ne crée aucune clé, ne lance ni podman ni chroot. Les couches des amorces sont listées par python3 -I (tarfile), sans extraction.
#   1. Amorces du cache OCI local de la 05 et de la 06 (lecture seule) : manifestes, couches, outils présents.
#   2. Instantané Debian 20261105T000000Z (celui de la 06) : clés de ftp-master, InRelease vérifié par gpgv (homedir dédié),
#      Packages.xz contrôlé par InRelease, versions de gnupg, gpg, gpgv, gpg-agent, apt-utils et de leurs dépendances directes.
#   3. Rocky vault/rocky/9.8 (source figée de la 05, décision « Oui 9.8 ») : repomd.xml vérifiés, comparés à ceux de pub/9.8
#      du relevé du 19/11 ; si égaux, le primary déjà vérifié est relu au lieu d'être retéléchargé.
#   4. Hôte : unshare (mécanisme de la 05, m1b-amorce-lecture.sh), podman (changelog local), détection des clés par secrets-depot.sh.
# Journal : resultats/o2-releve.log ; téléchargements ajoutés à resultats/releve-amont-telechargements.tsv.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
BASE=$HOME/.cache/supply-chain-poc/09
TS=$(date -u '+%Y%m%dT%H%M%SZ')
D=$BASE/o2-releve-$TS
G=$BASE/o2-gnupg-$TS
P1=$BASE/releve-20261119T144438Z
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont
ROCKY_M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d   # rockylinux:9.8, 05 (m1b-amorce-lecture.sh)
DEB_M=7378260c   # debian:trixie-20261104-slim amd64, préfixe relevé en 06 ; le digest complet est lu dans l'index local
SNAP=20261105T000000Z
MIROIR=https://snapshot.debian.org/archive/debian/$SNAP
CLES="B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8 04B54C3CDCA79751B16BC6B5225629DF75B188BD 41587F7DB8C774BCCF131416762F67A0B2C39DE4"   # 06, s1.sh
VAULT=https://dl.rockylinux.org/vault/rocky/9.8
LISTE=$R/releve-amont-telechargements.tsv
mkdir -p "$BASE"
mkdir "$D"
mkdir -m 700 "$G"
cd "$BASE"

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g'; }
dl() {
  if curl -fsSL --max-time 300 -o "$D/$1" "$2"; then
    local n s; n=$(stat -c %s "$D/$1"); s=$(sha256sum "$D/$1" | cut -c1-64)
    printf '%s\t%s\t%s\t%s\n' "o2-releve-$TS/$1" "$2" "$n" "$s" >> "$LISTE"
    echo "téléchargé : $1 ($n octets, sha256 $s) depuis $2"
  else echo "ÉCHEC du téléchargement : $1 depuis $2"; return 1; fi
}

releve() {
  set +e
  echo "relevé O2 commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; dossier neuf $D ; homedir gpg dédié $G"

  echo; echo "## 1. Amorces du cache OCI local (lecture seule, sans extraction)"
  dm=$(python3 -I -c 'import json,sys
for m in json.load(open(sys.argv[1]))["manifests"]:
    if m["digest"][7:].startswith(sys.argv[2]): print(m["digest"][7:])' "$OCI/library/debian/index.json" "$DEB_M")
  for e in "rockylinux $OCI/rockylinux/rockylinux $ROCKY_M" "debian $OCI/library/debian $dm"; do
    set -- $e
    echo "### $1 : manifeste $3"
    python3 -I - "$2" "$3" <<'PY'
import hashlib, json, sys, tarfile
o, m = sys.argv[1], sys.argv[2]
def blob(d): return f"{o}/blobs/sha256/{d}"
def h(d): return hashlib.sha256(open(blob(d), "rb").read()).hexdigest()
print(f"  manifeste : sha256 {'égal' if h(m) == m else 'DIFFÉRENT'}")
j = json.load(open(blob(m)))
c = j["config"]["digest"][7:]
cfg = json.load(open(blob(c)))
print(f"  configuration {c[:12]} : sha256 {'égal' if h(c) == c else 'DIFFÉRENT'} ; créée {cfg.get('created')} ; architecture {cfg.get('architecture')}")
voulus = ["usr/bin/gpg", "usr/bin/gpg2", "usr/bin/gpgv", "usr/bin/gpgv2", "usr/bin/gpg-agent", "usr/bin/gpgconf", "usr/bin/rpm",
          "usr/bin/rpmsign", "usr/bin/rpmkeys", "usr/bin/createrepo_c", "usr/bin/dnf", "usr/bin/dnf-3", "usr/bin/apt-get",
          "usr/bin/apt-ftparchive", "usr/bin/dpkg", "usr/bin/sqv", "usr/share/keyrings/debian-archive-keyring.gpg",
          "etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9", "usr/bin/xz", "usr/bin/tar"]
for l in j["layers"]:
    d = l["digest"][7:]
    print(f"  couche {d[:12]} : sha256 {'égale' if h(d) == d else 'DIFFÉRENTE'}, {l['size']} octets, {l['mediaType']}")
    noms = set()
    plug = []
    with tarfile.open(blob(d), "r:*") as t:
        for i in t:
            n = i.name.lstrip("./")
            noms.add(n)
            if "dnf-plugins/" in n and n.endswith(".py") and "__" not in n: plug.append(n.rsplit("/", 1)[1])
    print(f"    entrées : {len(noms)}")
    for v in voulus:
        print(f"    {v} : {'présent' if v in noms else 'absent'}")
    print(f"    greffons dnf : {sorted(plug) if plug else 'aucun'}")
PY
  done

  echo; echo "## 2. Instantané Debian $SNAP"
  for n in archive-key-12 archive-key-13 release-13; do
    dl "$n.asc" "https://ftp-master.debian.org/keys/$n.asc" && gpg --homedir "$G" --batch --quiet --import "$D/$n.asc" 2>/dev/null
  done
  gpg --homedir "$G" --batch --export $CLES > "$D/debian-cles.gpg"
  dl InRelease "$MIROIR/dists/trixie/InRelease"
  s=$(gpgv --homedir "$G" --keyring "$D/debian-cles.gpg" --status-fd 1 --output "$D/InRelease.verifie" "$D/InRelease" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' | sort | paste -sd' ')
  a=$(tr ' ' '\n' <<<"$CLES" | sort | paste -sd' ')
  [ "$s" = "$a" ] && echo "OK   signataires d'InRelease (clés primaires) : $s" || echo "ÉCART signataires d'InRelease : [$s], attendu [$a]"
  grep -E '^(Suite|Codename|Version|Date):' "$D/InRelease.verifie" | sed 's/^/  /'
  x=$(awk '/^SHA256:/ {f = 1; next} /^[A-Z]/ {f = 0} f && $3 == "main/binary-amd64/Packages.xz" {print $1}' "$D/InRelease.verifie")
  dl Packages.xz "$MIROIR/dists/trixie/main/binary-amd64/Packages.xz"
  [ "$(sha256sum < "$D/Packages.xz" | cut -c1-64)" = "$x" ] && echo "OK   Packages.xz égal au sha256 du texte vérifié d'InRelease" || echo "ÉCART Packages.xz"
  python3 -I - "$D/Packages.xz" <<'PY'
import lzma, sys
voulus = ["gnupg", "gpg", "gpgv", "gpg-agent", "gpgconf", "gpgsm", "dirmngr", "keyboxd", "gnupg-utils", "gpg-wks-client",
          "apt", "apt-utils", "libgcrypt20", "libassuan9", "libksba8", "libnpth0t64", "pinentry-curses", "sqv"]
st = {}
for s in lzma.open(sys.argv[1]).read().decode("utf-8", "replace").split("\n\n"):
    d = {}
    for l in s.splitlines():
        if ": " in l and not l.startswith(" "):
            k, v = l.split(": ", 1); d[k] = v
    if d.get("Package") in voulus: st.setdefault(d["Package"], []).append(d)
for p in voulus:
    for d in st.get(p, []) or [None]:
        if d is None: print(f"  {p} : absent de l'instantané"); continue
        print(f"  {p} {d['Version']} {d.get('Architecture')} sha256 {d['SHA256'][:16]}… {d['Size']} octets")
        if p in ("gnupg", "gpg", "gpgv", "apt-utils"): print(f"    Depends : {d.get('Depends')}")
PY

  echo; echo "## 3. Rocky $VAULT"
  gpg --homedir "$G" --batch --quiet --dearmor -o "$D/rocky9.gpg" "$P1/RPM-GPG-KEY-Rocky-9" 2>/dev/null
  echo "  clé relue dans $P1 : $(gpg --homedir "$G" --batch --show-keys --with-colons "$P1/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
  for e in "BaseOS abac8b17ece74b6f242af937c8143f2e76537eb6a82bdc876682bac38b1af163" "AppStream a3ca4230ce7eda565514f3ab084ce1811903c3eb6308a4c0e0cc7b8af819907b"; do
    set -- $e
    dl "vault-$1-repomd.xml" "$VAULT/$1/x86_64/os/repodata/repomd.xml" || continue
    dl "vault-$1-repomd.xml.asc" "$VAULT/$1/x86_64/os/repodata/repomd.xml.asc" || continue
    gpgv --homedir "$G" --keyring "$D/rocky9.gpg" "$D/vault-$1-repomd.xml.asc" "$D/vault-$1-repomd.xml" >/dev/null 2>&1 \
      && echo "OK   $1 : repomd.xml de vault vérifié par la clé Rocky 9" || echo "ÉCART $1 : repomd.xml de vault non vérifié"
    s=$(sha256sum < "$D/vault-$1-repomd.xml" | cut -c1-64)
    [ "$s" = "$2" ] && echo "OK   $1 : repomd.xml de vault égal à celui de pub/9.8 du relevé du 19/11 ($s) : primary relu" \
                     || echo "ÉCART $1 : repomd.xml de vault $s, pub/9.8 $2 : primary NON relu"
    [ "$s" = "$2" ] || continue
    python3 -I - "$P1/rocky-$1-primary.xml.gz" <<'PY'
import gzip, sys, xml.etree.ElementTree as ET
ns = {"c": "http://linux.duke.edu/metadata/common", "rpm": "http://linux.duke.edu/metadata/rpm"}
voulus = {"gnupg2", "rpm-sign", "rpm-sign-libs", "createrepo_c", "createrepo_c-libs", "dnf-plugins-core", "python3-dnf-plugins-core",
          "libgcrypt", "gpgme", "rpm", "rpm-libs", "pinentry", "drpm", "libmodulemd"}
for p in ET.parse(gzip.open(sys.argv[1])).getroot().findall("c:package", ns):
    n = p.find("c:name", ns).text
    if n in voulus and p.find("c:arch", ns).text in ("x86_64", "noarch"):
        v = p.find("c:version", ns)
        req = [e.get("name") for e in p.findall("c:format/rpm:requires/rpm:entry", ns)]
        print(f"  {n}-{v.get('ver')}-{v.get('rel')}.{p.find('c:arch', ns).text} sha256 {p.find('c:checksum', ns).text[:16]}… {p.find('c:location', ns).get('href')}"
              + (f" ; requires {[r for r in req if not r.startswith(('lib', '/', 'rtld', 'rpmlib'))][:12]}" if n in ("rpm-sign", "rpm-sign-libs", "createrepo_c", "gnupg2") else ""))
PY
  done
  echo "  m1b-sources.log (brique 05), lignes citant repomd de vault 9.8 :"
  grep -nE 'vault.*9\.8.*repomd|repomd.*vault' "$here/../05-rpm-mock/resultats/m1b-sources.log" 2>/dev/null | head -6 | cut -c1-220 | sed 's/^/    /'

  echo; echo "## 4. Hôte"
  echo "  $(unshare --version)"
  unshare --map-auto --map-root-user -n true && echo "OK   unshare --map-auto --map-root-user -n disponible (code 0)" || echo "ÉCART unshare indisponible"
  echo "  podman : $(podman --version) ; paquet $(dpkg-query -W -f='${Version}' podman 2>/dev/null)"
  echo "  changelog.Debian de podman, lignes citant GHSA-2cvf ou 5.8.8 : $(zcat /usr/share/doc/podman/changelog.Debian.gz | grep -ciE '2cvf|5\.8\.8')"
  zcat /usr/share/doc/podman/changelog.Debian.gz | head -3 | sed 's/^/    /'
  echo "  secrets-depot.sh : dossiers de motifs lus : $(grep -oE 'supply-chain-poc/[0-9a-z]+/secrets' "$here/../../../tools/secrets-depot.sh" | sort -u | paste -sd' ') ; motif « BEGIN PGP » : $(grep -c 'BEGIN PGP' "$here/../../../tools/secrets-depot.sh")"
  gpgconf --homedir "$G" --kill all 2>/dev/null
  echo "relevé O2 fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

releve 2>&1 | masquer | tee "$R/o2-releve.log"
