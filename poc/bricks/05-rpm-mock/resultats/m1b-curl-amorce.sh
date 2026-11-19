#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # ok et ko n'échouent jamais ; scripts de unshare entre apostrophes voulus
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : curl exécuté par les prefetch, préparé le 19/11/2026 après le relevé de santé de curl (sante-curl.log).
# Prédictions CA1 à CA5 : m1b-predictions.md, commitées avant.
#   A  paquets curl et gnupg2 de l'amorce rockylinux:9.8 (couche 99c753a8, cache OCI local), relus par son rpm dans une racine
#      extraite à neuf (chroot sous unshare -n), avec leur changelog
#   B  mêmes paquets dans la racine de 99790c13, image de prefetch-rpm signée (couche e48fc4d6 reliée par s1-image-essai-local.log)
#   C  avis du projet curl (curl.se/docs/vuln.json, téléchargé à neuf, sha256 relevé) dont les versions touchées comptent 7.76.1,
#      publiés depuis un an
#   D  changelog Rocky de curl-minimal dans vault 9.8 BaseOS : repomd.xml vérifié par gpgv avec la clé de Rocky de l'amorce
#      (sha256 contrôlé), other.xml.gz contrôlé contre repomd.xml ; pour chaque avis de C, mention dans le changelog du paquet de
#      l'amorce et dans celui de la dernière révision de vault
# Lectures publiques : curl.se et dl.rockylinux.org (quelques Mo). Ni cluster, ni Zot.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-curl-amorce.sh < /dev/null > poc/bricks/05-rpm-mock/resultats/m1b-curl-amorce.log 2>&1
set -euo pipefail
export LC_ALL=C
umask 022
G=$(git rev-parse --show-toplevel)
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256
COUCHE_AMORCE=99c753a880cc03bbe9da8bf6e354c8ba2d99f19058e87b8a55b6487ffcf52f8a
IMG=$HOME/.cache/supply-chain-poc/05/banc-image/disque/sha256   # blobs de 99790c13
M99=99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771
C99=e48fc4d689daa5ec7af47350d996f93d76a138ff7267aed6972feefe3e4526bd   # couche de la racine (s1-image-essai-local.log)
CLE_SHA=3a66e521e7a4abac9768d889c7cd60a8250f59512b275cf576c8a10ff34624c1   # RPM-GPG-KEY-Rocky-9 (attendu-b.sha256 de m1bt3)
V98=https://dl.rockylinux.org/vault/rocky/9.8/BaseOS/x86_64/os
nko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; nko=$((nko + 1)); }
echo "# m1b-curl-amorce.sh, début $(date -u +%FT%TZ) ; HEAD $(git -C "$G" rev-parse --short=12 HEAD)"
D=$HOME/.cache/supply-chain-poc/05/m1b-curl-amorce-$(date -u +%Y%m%dT%H%M%SZ)   # dossier neuf
[ ! -e "$D" ] || { echo "KO   $D existe" >&2; exit 1; }
mkdir -p "$D"
QF='%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH} construit le %{BUILDTIME:date}\n'
paquets() { # racine : paquets curl et gnupg2 relus par le rpm de la racine
  unshare --map-auto --map-root-user -n chroot "$1" env -i PATH=/usr/bin:/bin rpm -qa --qf "$QF" 'curl*' 'libcurl*' gnupg2 | sort | sed 's/^/     /'
}

echo "## A : amorce rockylinux:9.8, couche ${COUCHE_AMORCE:0:12}…"
[ "$(sha256sum < "$OCI/$COUCHE_AMORCE" | cut -c1-64)" = "$COUCHE_AMORCE" ] && ok "couche de l'amorce : sha256 conforme" || { echo "KO   couche de l'amorce" >&2; exit 1; }
unshare --map-auto --map-root-user bash -c 'mkdir "$1" && tar -xzf "$2" -C "$1" --numeric-owner' _ "$D/amorce" "$OCI/$COUCHE_AMORCE"
paquets "$D/amorce"
unshare --map-auto --map-root-user -n chroot "$D/amorce" env -i PATH=/usr/bin:/bin rpm -q --changelog curl-minimal > "$D/changelog-amorce.txt"
echo "     changelog de curl-minimal dans l'amorce : $(grep -c '^\*' "$D/changelog-amorce.txt") entrées, la plus récente : $(grep -m1 '^\*' "$D/changelog-amorce.txt" | cut -c1-90)"
[ "$(sha256sum < "$D/amorce/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9" | cut -c1-64)" = "$CLE_SHA" ] && ok "clé RPM-GPG-KEY-Rocky-9 de l'amorce : sha256 conforme" || ko "clé de Rocky de l'amorce"

echo "## B : racine de 99790c13 (image de prefetch-rpm signée)"
# le manifeste n'est pas gardé en local : la couche de la racine est celle que relie à 99790c13 le journal du passage local de S1
J=$G/poc/bricks/05-rpm-mock/resultats/s1-image-essai-local.log
grep -q "^couche sha256:$C99 140611406 octets$" "$J" && grep -q "@sha256:$M99$" "$J" \
  && ok "s1-image-essai-local.log relie ${M99:0:12}… à la couche ${C99:0:12}…" || { echo "KO   lien 99790c13 et couche absent du journal" >&2; exit 1; }
c0=$C99
[ "$(sha256sum < "$IMG/$c0" | cut -c1-64)" = "$c0" ] && ok "couche ${c0:0:12}… : sha256 conforme, $(stat -c %s "$IMG/$c0") octets" || { echo "KO   couche de 99790c13" >&2; exit 1; }
unshare --map-auto --map-root-user bash -c 'mkdir "$1" && tar -xf "$2" -C "$1" --numeric-owner' _ "$D/i99" "$IMG/$c0"   # compression reconnue par tar
paquets "$D/i99"

echo "## C : avis du projet curl touchant 7.76.1, publiés depuis un an"
a=$(date -u -d '1 year ago' +%Y-%m-%d)
h=$(curl -sSL --proto =https --max-time 60 -o "$D/vuln.json" -w '%{http_code}' https://curl.se/docs/vuln.json) || h="$h, curl en échec"
[ "$h" = 200 ] || { echo "KO   vuln.json : HTTP $h" >&2; exit 1; }
echo "     vuln.json : $(stat -c %s "$D/vuln.json") octets, sha256 $(sha256sum < "$D/vuln.json" | cut -c1-64)"
python3 -I - "$D/vuln.json" "$a" > "$D/avis.tsv" <<'PY'
import json, sys
v, a = json.load(open(sys.argv[1], encoding="utf-8")), sys.argv[2]
for x in v:
    vs = [s for af in x.get("affected", []) for s in af.get("versions", [])]
    if "7.76.1" in vs and x.get("published", "")[:10] >= a:
        cve = [c for c in x.get("aliases", []) if c.startswith("CVE-")] or [x["id"].replace("CURL-", "")]
        print(x["published"][:10], x["id"], cve[0], (x.get("database_specific") or {}).get("severity", "?"), sep="\t")
PY
echo "     avis touchant 7.76.1 depuis $a : $(wc -l < "$D/avis.tsv") ; gravités : $(cut -f4 "$D/avis.tsv" | sort | uniq -c | tr -s ' ' | tr '\n' ';')"

echo "## D : changelog Rocky de curl-minimal (vault 9.8 BaseOS)"
mkdir -p "$D/v98" "$D/gnupg" && chmod 700 "$D/gnupg"
for f in repomd.xml repomd.xml.asc; do
  h=$(curl -sSL --proto =https --max-time 60 -o "$D/v98/$f" -w '%{http_code}' "$V98/repodata/$f") || h="$h, curl en échec"
  [ "$h" = 200 ] || { echo "KO   $f : HTTP $h" >&2; exit 1; }
done
GNUPGHOME=$D/gnupg gpg --batch --quiet --no-default-keyring --keyring "$D/gnupg/rocky.gpg" --import "$D/amorce/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9" 2> /dev/null
s=$(GNUPGHOME=$D/gnupg gpgv --keyring "$D/gnupg/rocky.gpg" --status-fd 1 "$D/v98/repomd.xml.asc" "$D/v98/repomd.xml" 2> /dev/null | awk '$2 == "VALIDSIG" {print $NF}' || true)
[ -n "$s" ] && ok "repomd.xml de vault 9.8 BaseOS : sha256 $(sha256sum < "$D/v98/repomd.xml" | cut -c1-64), signature valide (clé primaire $s)" || { echo "KO   signature de repomd.xml" >&2; exit 1; }
read -r o osha < <(python3 -I - "$D/v98/repomd.xml" <<'PY'
import sys, xml.etree.ElementTree as E
n = '{http://linux.duke.edu/metadata/repo}'
for x in E.parse(sys.argv[1]).getroot().findall(n + 'data'):
    if x.get('type') == 'other':
        print(x.find(n + 'location').get('href'), x.find(n + 'checksum').text)
PY
)
case $o in repodata/*) ;; *) echo "KO   chemin de other : $o" >&2; exit 1 ;; esac
h=$(curl -sSL --proto =https --max-time 300 -o "$D/v98/other" -w '%{http_code}' "$V98/$o") || h="$h, curl en échec"
[ "$h" = 200 ] && [ "$(sha256sum < "$D/v98/other" | cut -c1-64)" = "$osha" ] && ok "${o#repodata/} : $(stat -c %s "$D/v98/other") octets, sha256 conforme à repomd.xml" || { echo "KO   other ($h)" >&2; exit 1; }
python3 -I - "$D/v98/other" "$o" "$D/changelog-amorce.txt" "$D/avis.tsv" "$(grep -m1 '^curl-minimal-' <(paquets "$D/amorce" | sed 's/^ *//') | cut -d' ' -f1)" <<'PY'
import gzip, lzma, sys, xml.etree.ElementTree as E
f, nom, ch_am, avis, am = sys.argv[1:]
op = gzip.open if nom.endswith('.gz') else lzma.open if nom.endswith('.xz') else open
n = '{http://linux.duke.edu/metadata/other}'
ver = {}
for _, x in E.iterparse(op(f, 'rb'), events=('end',)):
    if x.tag == n + 'package':
        if x.get('name') == 'curl-minimal' and x.get('arch') == 'x86_64':
            v = x.find(n + 'version')
            ver[v.get('ver') + '-' + v.get('rel')] = [c.text or '' for c in x.findall(n + 'changelog')]
        x.clear()
cle = lambda r: tuple(int(c) if c.isdigit() else 0 for c in r.replace('_', '.').replace('-', '.').split('.'))
rs = sorted(ver, key=cle)
print(f"     curl-minimal dans vault 9.8 BaseOS : {len(rs)} révision(s) : {', '.join(rs)}")
der = rs[-1]
print(f"     changelog de la dernière ({der}) : {len(ver[der])} entrées dans other")
t_am = open(ch_am, encoding='utf-8', errors='replace').read(); t_der = ' '.join(ver[der])
print(f"     paquet de l'amorce : {am}")
for l in open(avis, encoding='utf-8'):
    p, i, c, g = l.rstrip('\n').split('\t')
    print(f"     {c} ({g}, publié le {p}) : changelog de l'amorce {'mentionne' if c in t_am else 'ne mentionne pas'} ; {der} {'mentionne' if c in t_der else 'ne mentionne pas'}")
PY
echo "place libre de /home : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB ; dossier laissé : $D"
echo "# fin $(date -u +%FT%TZ) ; KO $nko"
exit $((nko > 0))
