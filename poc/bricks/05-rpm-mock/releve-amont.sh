#!/usr/bin/env bash
# Briques 05 et 06 : relevé des sources amont, en lecture seule. N'installe rien : métadonnées et textes amont, aux tags épinglés,
# et un seul paquet téléchargé, uidmap, comparé à l'index signé de l'instantané puis listé par dpkg-deb, jamais extrait ni
# exécuté. Journal : resultats/releve-amont.log.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
ROCKY=9.7
SNAPSHOT=20261105T000000Z
MOCK_TAG=mock-6.9-1
CONFIGS_TAG=mock-core-configs-45.2-1
SBUILD_TAG=debian/0.89.3+deb13u4
BRUT=https://raw.githubusercontent.com/rpm-software-management/mock
mkdir -p "$R"
T=$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/releve-amont.XXXXXX")
nettoyer() { rm -rf -- "${T:?}"; }
trap nettoyer EXIT

code() { curl -sS -o /dev/null -L --max-time 30 -w '%{http_code}' "$1"; }

releve() {
  date -u '+relevé du %d/%m/%Y à %H:%M UTC'
  echo
  echo "## mock dans EPEL 9"
  curl -sSL --max-time 30 https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/m/ \
    | grep -oE 'mock-(core-configs-)?[0-9][^"<]*\.rpm' | sort -u
  echo
  echo "## Rocky : versions publiées et archivées"
  echo "pub   : $(curl -sSL --max-time 30 https://dl.rockylinux.org/pub/rocky/ | grep -oE 'href="9\.[0-9]+/"' | sed 's/href="//;s/\/"//' | sort -V | tr '\n' ' ')"
  echo "vault : $(curl -sSL --max-time 30 https://dl.rockylinux.org/vault/rocky/ | grep -oE 'href="9\.[0-9]+/"' | sed 's/href="//;s/\/"//' | sort -V | tr '\n' ' ')"
  for depot in BaseOS AppStream CRB; do
    url=https://dl.rockylinux.org/vault/rocky/$ROCKY/$depot/x86_64/os/repodata
    echo "$depot $ROCKY : repomd.xml HTTP $(code "$url/repomd.xml"), repomd.xml.asc HTTP $(code "$url/repomd.xml.asc"), sha256 $(curl -sSL --max-time 30 "$url/repomd.xml" | sha256sum | cut -c1-64)"
  done
  echo
  echo "## Debian stable (madison)"
  for p in sbuild mmdebstrap mock diffoscope reprotest golang-go nodejs; do
    curl -sSL --max-time 30 "https://api.ftp-master.debian.org/madison?package=$p&f=json&s=stable,stable-updates" \
      | python3 -I -c "import json,sys
for e in json.load(sys.stdin):
    for p, suites in e.items():
        for s, vs in suites.items():
            print(p, s, *vs)"
  done
  echo
  echo "## Instantané Debian $SNAPSHOT"
  url=https://snapshot.debian.org/archive/debian/$SNAPSHOT
  curl -sS -L --max-time 30 -o "$T/InRelease" -w 'InRelease HTTP %{http_code}, %{num_redirects} redirection, servi par %{url_effective}\n' \
    "$url/dists/trixie/InRelease"
  echo "sha1 du contenu : $(sha1sum "$T/InRelease" | cut -c1-40) (l'adresse de /file/ est le sha1 du contenu)"
  grep -E '^(Suite|Codename|Date|Valid-Until):' "$T/InRelease"
  echo "Valid-Until : $(grep -c '^Valid-Until:' "$T/InRelease") ligne"
  echo
  echo "## Configuration de mock, tag $CONFIGS_TAG"
  curl -sSL --max-time 30 "$BRUT/$CONFIGS_TAG/mock-core-configs/etc/mock/rocky-9-x86_64.cfg" | grep -E "include"
  curl -sSL --max-time 30 "$BRUT/$CONFIGS_TAG/mock-core-configs/etc/mock/templates/rocky-9.tpl" \
    | grep -E "bootstrap_image|^mirrorlist=.*repo=(BaseOS|AppStream|CRB)-"
  echo
  echo "## Documentation hermétique de mock, tag $MOCK_TAG"
  curl -sSL --max-time 30 "$BRUT/$MOCK_TAG/docs/feature-hermetic-builds.md" \
    | grep -n -E "doesn't provide reproducible|Bootstrap Image to be|avoid using mirrored|Mock \(v[0-9]"
  curl -sSL --max-time 30 "$BRUT/$MOCK_TAG/docs/Plugin-BuildrootLock.md" | grep -n -E "exact same|version of Mock"
  echo
  echo "## Manuel de sbuild, tag $SBUILD_TAG"
  curl -sSL --max-time 30 "https://salsa.debian.org/debian/sbuild/-/raw/$SBUILD_TAG/man/sbuild.1.in" \
    | grep -n -E "newuidmap|^Don't enable network access"
  echo
  echo "## uidmap de Debian 13 : droits de newuidmap (paquet lu, rien d'extrait ni d'exécuté)"
  curl -sSL --max-time 60 -o "$T/Packages.xz" "$url/dists/trixie/main/binary-amd64/Packages.xz"
  empreinte=$(sha256sum "$T/Packages.xz" | cut -c1-64)
  grep -q "$empreinte .* main/binary-amd64/Packages.xz" "$T/InRelease" \
    && echo "OK   Packages.xz présent dans InRelease" || { echo "KO   Packages.xz absent d'InRelease" >&2; exit 1; }
  xz -dc "$T/Packages.xz" | awk 'BEGIN{RS="";FS="\n"} /^Package: uidmap\n/' > "$T/uidmap"
  chemin=$(sed -n 's/^Filename: //p' "$T/uidmap"); attendu=$(sed -n 's/^SHA256: //p' "$T/uidmap")
  curl -sSL --max-time 60 -o "$T/uidmap.deb" "$url/$chemin"
  [ "$(sha256sum "$T/uidmap.deb" | cut -c1-64)" = "$attendu" ] \
    && echo "OK   $(basename "$chemin") : sha256 conforme à l'index" || { echo "KO   sha256 de uidmap" >&2; exit 1; }
  dpkg-deb -c "$T/uidmap.deb" | grep -E 'new[ug]idmap$'
  echo "scripts du paquet : $(dpkg-deb -I "$T/uidmap.deb" | grep -c -E 'postinst')  postinst"
  dpkg-deb -e "$T/uidmap.deb" "$T/controle"
  [ ! -f "$T/controle/postinst" ] || grep -n -E 'setcap|newuidmap|newgidmap' "$T/controle/postinst" || echo "postinst sans setcap ni newuidmap"
}

releve 2>&1 | tee "$R/releve-amont.log"
