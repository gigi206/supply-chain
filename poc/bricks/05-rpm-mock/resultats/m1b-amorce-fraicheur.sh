#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # ok n'échoue jamais ; scripts de unshare entre apostrophes voulus
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : fraîcheur de l'amorce rockylinux:9.8 (ed654c69, D4 a), hors ligne, préparé le 19/11/2026 après
# m1b-curl-amorce.log. Prédictions FR1 à FR4 : m1b-predictions.md, commitées avant.
#   - date de l'image (created de sa config, cache OCI local) ;
#   - paquets installés (rpm de l'amorce, racine extraite à neuf, chroot sous unshare -n) contre le plus récent de chaque nom dans
#     les primary de BaseOS et AppStream 9.8 des bancs du 18/11 (repomd.xml abac8b17… et a3ca4230…, ceux que fixe la pipeline de
#     l'outillage ; primary et updateinfo contrôlés contre repomd.xml), comparés par rpm.labelCompare de l'amorce ;
#   - errata de sécurité de updateinfo qui portent une version plus récente qu'un paquet installé, comptés par gravité ;
#   - détail pour les paquets que le prefetch ou la construction chargent face au réseau ou en root (liste fixée ci-dessous).
# Ni réseau, ni cluster, ni Zot.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-amorce-fraicheur.sh < /dev/null > poc/bricks/05-rpm-mock/resultats/m1b-amorce-fraicheur.log 2>&1
set -euo pipefail
export LC_ALL=C
umask 022
G=$(git rev-parse --show-toplevel)
OCI=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux/blobs/sha256
M_AMORCE=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d
COUCHE_AMORCE=99c753a880cc03bbe9da8bf6e354c8ba2d99f19058e87b8a55b6487ffcf52f8a
MIR=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z/outils/m/miroir   # banc de l'outillage : lecture seule
EXPOSES="curl-minimal libcurl-minimal openssl-libs gnutls nss krb5-libs libnghttp2 libssh libpsl ca-certificates glibc zlib gnupg2 gpgme python3 python3-libs rpm rpm-libs dnf python3-dnf libdnf librepo libsolv tar"
echo "# m1b-amorce-fraicheur.sh, début $(date -u +%FT%TZ) ; HEAD $(git -C "$G" rev-parse --short=12 HEAD)"
D=$HOME/.cache/supply-chain-poc/05/m1b-amorce-fraicheur-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$D" ] || { echo "KO   $D existe" >&2; exit 1; }
mkdir -p "$D"
ok() { echo "OK   $*"; }
arret() { echo "KO   $*" >&2; exit 1; }

[ "$(sha256sum < "$OCI/$M_AMORCE" | cut -c1-64)" = "$M_AMORCE" ] || arret "manifeste de l'amorce"
c=$(jq -r '.config.digest' "$OCI/$M_AMORCE" | cut -c8-)
[ "$(sha256sum < "$OCI/$c" | cut -c1-64)" = "$c" ] || arret "config de l'amorce"
[ "$(jq -r '[.layers[].digest] | join(" ")' "$OCI/$M_AMORCE")" = "sha256:$COUCHE_AMORCE" ] || arret "couche de l'amorce"
ok "amorce ${M_AMORCE:0:12}… : config ${c:0:12}…, created $(jq -r '.created' "$OCI/$c"), une couche ${COUCHE_AMORCE:0:12}…"

mkdir -p "$D/meta"
for r in "baseos98 abac8b17ece74b6f242af937c8143f2e76537eb6a82bdc876682bac38b1af163" "appstream98 a3ca4230ce7eda565514f3ab084ce1811903c3eb6308a4c0e0cc7b8af819907b"; do
  read -r n s <<< "$r"
  [ "$(sha256sum < "$MIR/$n/repodata/repomd.xml" | cut -c1-64)" = "$s" ] || arret "$n : repomd.xml"
  python3 -I - "$MIR/$n" "$D/meta/$n" <<'PY' || arret "$n : primary ou updateinfo"
import hashlib, shutil, sys, xml.etree.ElementTree as E
m, o = sys.argv[1:]
ns = {'r': 'http://linux.duke.edu/metadata/repo'}
vus = []
for d in E.parse(f'{m}/repodata/repomd.xml').getroot().findall('r:data', ns):
    t = d.get('type')
    if t in ('primary', 'updateinfo'):
        h = d.find('r:location', ns).get('href')
        assert hashlib.sha256(open(f'{m}/{h}', 'rb').read()).hexdigest() == d.find('r:checksum', ns).text, h
        shutil.copyfile(f'{m}/{h}', f'{o}-{t}.xml.gz'); vus.append(t)
assert sorted(vus) == ['primary', 'updateinfo'], vus
PY
  ok "$n : repomd.xml ${s:0:12}… ; primary et updateinfo conformes"
done

unshare --map-auto --map-root-user bash -c 'mkdir "$1" && tar -xzf "$2" -C "$1" --numeric-owner && mkdir -p "$1/tmp/meta"' _ "$D/r" "$OCI/$COUCHE_AMORCE"
cp "$D"/meta/*.xml.gz "$D/r/tmp/meta/"
cat > "$D/r/tmp/fraicheur.py" <<'PY'
import gzip, sys, xml.etree.ElementTree as E
import rpm
exposes = sys.argv[1].split()
inst = {}
for h in rpm.TransactionSet().dbMatch():
    n = h['name']
    if n == 'gpg-pubkey':
        continue
    inst[n] = (str(h['epoch'] or 0), h['version'], h['release'])
c = '{http://linux.duke.edu/metadata/common}'
neuf = {}
for r in ('baseos98', 'appstream98'):
    for _, p in E.iterparse(gzip.open(f'/tmp/meta/{r}-primary.xml.gz'), events=('end',)):
        if p.tag != c + 'package':
            continue
        n, a = p.find(c + 'name').text, p.find(c + 'arch').text
        if n in inst and a in ('x86_64', 'noarch'):
            v = p.find(c + 'version')
            e = (v.get('epoch') or '0', v.get('ver'), v.get('rel'))
            if n not in neuf or rpm.labelCompare(e, neuf[n][0]) > 0:
                neuf[n] = (e, r)
        p.clear()
retard = sorted(n for n in inst if n in neuf and rpm.labelCompare(neuf[n][0], inst[n]) > 0)
absents = sorted(n for n in inst if n not in neuf)
print(f"paquets installés (hors gpg-pubkey) : {len(inst)} ; présents dans BaseOS ou AppStream 9.8 : {len(inst) - len(absents)} ; en retard : {len(retard)} ; absents des deux : {len(absents)}")
gr = {}; par = {}
for r in ('baseos98', 'appstream98'):
    for _, u in E.iterparse(gzip.open(f'/tmp/meta/{r}-updateinfo.xml.gz'), events=('end',)):
        if u.tag != 'update':
            continue
        if u.get('type') == 'security':
            sev = (u.findtext('severity') or '?').strip() or '?'
            i = u.findtext('id')
            for pk in u.iter('package'):
                n = pk.get('name')
                if n in inst and pk.get('arch') in ('x86_64', 'noarch'):
                    e = (pk.get('epoch') or '0', pk.get('version'), pk.get('release'))
                    if rpm.labelCompare(e, inst[n]) > 0:
                        par.setdefault(n, {})[i] = sev
        u.clear()
for n, d in par.items():
    for i, s in d.items():
        gr.setdefault(i, s)
print(f"errata de sécurité qui portent une version plus récente qu'un paquet installé : {len(gr)} ; gravités : " +
      ", ".join(f"{s} {sum(1 for x in gr.values() if x == s)}" for s in sorted(set(gr.values()))))
print(f"paquets installés touchés par au moins un de ces errata : {len(par)}")
for n in exposes:
    if n not in inst:
        print(f"  {n} : non installé"); continue
    i = '-'.join(inst[n][1:]); d = par.get(n, {})
    if n in retard:
        print(f"  {n} : {i} ; plus récent : {'-'.join(neuf[n][0][1:])} ({neuf[n][1]}) ; errata de sécurité : {len(d)}" +
              (f" ({', '.join(f'{k} {v}' for k, v in sorted(d.items()))})" if d else ""))
    else:
        print(f"  {n} : {i} ; à jour dans 9.8" + ("" if n in neuf else " (absent des deux dépôts)"))
PY
unshare --map-auto --map-root-user -n chroot "$D/r" env -i PATH=/usr/bin:/bin python3 -I /tmp/fraicheur.py "$EXPOSES" | sed 's/^/     /'
echo "place libre de /home : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB ; dossier laissé : $D"
echo "# fin $(date -u +%FT%TZ) ; KO 0"
