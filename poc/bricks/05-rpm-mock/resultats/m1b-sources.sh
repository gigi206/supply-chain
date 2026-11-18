#!/usr/bin/env bash
# Brique 05, M1b, point 1 B (carte de M1b) : relevé public, en lecture seule, des sources de l'outillage (D4 a). Les 199 rpm du
# 17/11 (s1-racine.log, l. 11 à 209 : dépôt, fichier, sha256) sont-ils encore servis, et à une adresse figée ?
#   - Rocky : index de pub/rocky et de vault/rocky ; pour pub/9.8 et, s'il existe, vault/9.8 : repomd.xml de BaseOS et AppStream
#     vérifié par gpgv (clé de Rocky, empreinte de s1.sh), primary contrôlé par repomd, puis chaque rpm cherché par nom et sha256
#     dans le primary, et son adresse interrogée (HEAD).
#   - EPEL 9 : repomd.xml actuel (sha256, .asc), primary contrôlé par repomd, chaque rpm cherché par nom et sha256 ; puis chaque
#     rpm téléchargé depuis kojipkgs.fedoraproject.org, au chemin de construction et au chemin signé par la clé d'EPEL 9, et
#     comparé au sha256 du 17/11 ; index de pub/archive/epel.
# Rien ne touche au cluster, à Zot ni aux dépôts de la brique. Téléchargements dans un dossier neuf, laissé en place :
# ~/.cache/supply-chain-poc/05/m1b-sources-<UTC>. Prédictions : m1b-predictions.md (section du point 1 B), commitées avant.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-sources.sh > poc/bricks/05-rpm-mock/resultats/m1b-sources.log 2>&1
set -euo pipefail
export LC_ALL=C
r=$(cd "$(dirname "$0")" && pwd)
J=$r/s1-racine.log
H=$r/s1-hote.log
D=$HOME/.cache/supply-chain-poc/05/m1b-sources-$(date -u +%Y%m%dT%H%M%SZ)   # un dossier par passage : jamais effacé ni réutilisé
ROCKY=https://dl.rockylinux.org
EPEL9=https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64
KOJI=https://kojipkgs.fedoraproject.org
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D   # s1.sh, l. 164
echo "# m1b-sources.sh, début $(date -u +%FT%TZ)"
[ ! -e "$D" ] || { echo "KO   dossier déjà présent : $D" >&2; exit 1; }
mkdir -p "$D"
echo "journal de référence : s1-racine.log, sha256 $(sha256sum < "$J" | cut -c1-64)"
grep -E '^     rpm (baseos98|appstream98|epel9) ' "$J" | awk '{print $2, $3, $4}' > "$D/attendus"
r_att="$(awk '{print $1}' "$D/attendus" | sort | uniq -c | awk '{printf "%s %s ", $2, $1}')"
echo "rpm attendus : $(wc -l < "$D/attendus") ($r_att)"
[ "$(wc -l < "$D/attendus")" = 199 ] && [ "$r_att" = "appstream98 21 baseos98 169 epel9 9 " ] \
  || { echo "KO   liste attendue différente de s1-racine.log, l. 222" >&2; exit 1; }
get() { curl -fsSL --max-time 300 -o "$1" "$2"; }
code() { # fichier url : télécharge sans -f et imprime le code HTTP (ou erreur-<code de curl>) ; seul 404 vaut « absent »
  curl -sSL --max-time 300 -o "$1" -w '%{http_code}' "$2" 2>/dev/null || echo "erreur-$?"; }
index() { # url : code HTTP, puis les entrées de répertoire de la page
  local c; c=$(code "$D/index.html" "$1")
  printf 'HTTP %s : ' "$c"; [ "$c" != 200 ] || grep -o 'href="[^"?/][^"]*/"' "$D/index.html" | sed 's/^href="//; s/"$//' | tr '\n' ' '; }

echo "## index"
echo "pub/rocky : $(index "$ROCKY/pub/rocky/")"
echo "vault/rocky : $(index "$ROCKY/vault/rocky/")"
ARCH_EPEL=$(index https://dl.fedoraproject.org/pub/archive/epel/)
echo "pub/archive/epel : $ARCH_EPEL"

echo "## clés"
get "$D/RPM-GPG-KEY-Rocky-9" "$ROCKY/pub/rocky/RPM-GPG-KEY-Rocky-9"
get "$D/RPM-GPG-KEY-EPEL-9" https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
fp() { gpg --batch --with-colons --show-keys "$1" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}'; }
fr=$(fp "$D/RPM-GPG-KEY-Rocky-9"); fe=$(fp "$D/RPM-GPG-KEY-EPEL-9")
fe17=$(sed -n "s/^empreinte de la clé d'EPEL 9 : //p" "$H" | head -1)
[ "$fr" = "$FP_ROCKY" ] && echo "OK   clé de Rocky : $fr" || { echo "KO   clé de Rocky : $fr" >&2; exit 1; }
[ "$fe" = "$fe17" ] && echo "OK   clé d'EPEL 9 : $fe (égale au relevé de s1-hote.log)" || { echo "KO   clé d'EPEL 9 : $fe (relevé : $fe17)" >&2; exit 1; }
for k in RPM-GPG-KEY-Rocky-9 RPM-GPG-KEY-EPEL-9; do gpg --no-default-keyring --keyring "$D/cles.gpg" --batch --quiet --import "$D/$k" 2>/dev/null; done
KID=$(printf '%s' "${fe: -8}" | tr 'A-F' 'a-f')
echo "identifiant court de la clé d'EPEL 9 : $KID"

decompresser() { case $1 in *.gz) gzip -dc "$1" ;; *.xz) xz -dc "$1" ;; *.zst) zstd -qdc "$1" ;; *) echo "KO   compression : $1" >&2; exit 1 ;; esac; }
primary() { # nom url-du-dépôt signataire-exigé|- : repomd (sha256, signature), primary contrôlé par repomd, dans $D/<nom>.primary.xml
  local p s v
  get "$D/$1.repomd.xml" "$2/repodata/repomd.xml"
  echo "$1 : repomd.xml sha256 $(sha256sum < "$D/$1.repomd.xml" | cut -c1-64)"
  if curl -fsSL --max-time 60 -o "$D/$1.repomd.xml.asc" "$2/repodata/repomd.xml.asc" 2>/dev/null; then
    v=$(gpgv --keyring "$D/cles.gpg" --status-fd 1 "$D/$1.repomd.xml.asc" "$D/$1.repomd.xml" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}' || true)
    echo "$1 : repomd.xml.asc présent, signataire valide : ${v:-aucun}"
  else
    v=; echo "$1 : repomd.xml.asc absent"
  fi
  [ "$3" = - ] || [ "$v" = "$3" ] || { echo "KO   $1 : signataire de repomd.xml ${v:-aucun} (exigé : $3)" >&2; exit 1; }
  read -r p s < <(python3 -I - "$D/$1.repomd.xml" <<'PY'
import sys, xml.etree.ElementTree as E
n = {'r': 'http://linux.duke.edu/metadata/repo'}
for d in E.parse(sys.argv[1]).getroot().findall('r:data', n):
    if d.get('type') == 'primary':
        c = d.find('r:checksum', n)
        print(d.find('r:location', n).get('href'), c.text if c.get('type') == 'sha256' else 'type-' + c.get('type'))
PY
  )
  get "$D/$1.${p##*/}" "$2/$p"
  [ "$(sha256sum < "$D/$1.${p##*/}" | cut -c1-64)" = "$s" ] && echo "$1 : primary contrôlé par repomd.xml" \
    || { echo "KO   $1 : primary non conforme à repomd.xml" >&2; exit 1; }
  decompresser "$D/$1.${p##*/}" > "$D/$1.primary.xml"
}
cherche() { # nom-du-primary dépôt-attendu url-du-dépôt : chaque rpm attendu cherché par nom de fichier et sha256, puis HEAD
  python3 -I - "$D/$1.primary.xml" "$D/attendus" "$2" "$3" "$D/$1.trouves" <<'PY'
import sys, xml.etree.ElementTree as E
C = '{http://linux.duke.edu/metadata/common}'; RP = '{http://linux.duke.edu/metadata/rpm}'
prim, att, dep, url, sortie = sys.argv[1:]
voulus = {f: s for d, f, s in (l.split() for l in open(att, encoding='utf-8')) if d == dep}
vu = {}
for _, p in E.iterparse(prim):
    if p.tag != C + 'package':
        continue
    h = p.find(C + 'location').get('href'); f = h.rsplit('/', 1)[-1]
    if f in voulus:
        c = p.find(C + 'checksum')
        vu[f] = (c.text if c.get('type') == 'sha256' else 'type-' + c.get('type'), h)
    p.clear()
egal = [f for f in voulus if f in vu and vu[f][0] == voulus[f]]
autre = [f for f in voulus if f in vu and vu[f][0] != voulus[f]]
absent = sorted(f for f in voulus if f not in vu)
print(f'{dep} dans {url} : {len(voulus)} attendus ; même fichier et même sha256 : {len(egal)} ; même fichier, autre sha256 : {len(autre)} ; absents : {len(absent)}')
for f in absent:
    print(f'     absent : {f}')
for f in sorted(autre):
    print(f'     autre sha256 : {f}')
with open(sortie, 'w', encoding='utf-8') as o:
    for f in sorted(egal):
        o.write(f'{url}/{vu[f][1]}\n')
PY
  local n=0 ko=0 u c
  while read -r u; do
    n=$((n + 1)); c=$(curl -sS -o /dev/null -I -L -w '%{http_code}' --max-time 60 "$u" 2>/dev/null || echo erreur)
    [ "$c" = 200 ] || { ko=$((ko + 1)); echo "     HEAD $c : ${u##*/}"; }
  done < "$D/$1.trouves"
  echo "$1 : HEAD sur les $n adresses trouvées : $((n - ko)) en 200, $ko autres"
}

echo "## Rocky 9.8, pub"
for x in BaseOS:baseos98 AppStream:appstream98; do
  primary "pub98-${x#*:}" "$ROCKY/pub/rocky/9.8/${x%:*}/x86_64/os" "$FP_ROCKY"
  cherche "pub98-${x#*:}" "${x#*:}" "$ROCKY/pub/rocky/9.8/${x%:*}/x86_64/os"
done
echo "## Rocky 9.8, vault"
c=$(code "$D/vault98.essai" "$ROCKY/vault/rocky/9.8/BaseOS/x86_64/os/repodata/repomd.xml")
if [ "$c" = 200 ]; then
  for x in BaseOS:baseos98 AppStream:appstream98; do
    primary "vault98-${x#*:}" "$ROCKY/vault/rocky/9.8/${x%:*}/x86_64/os" "$FP_ROCKY"
    cherche "vault98-${x#*:}" "${x#*:}" "$ROCKY/vault/rocky/9.8/${x%:*}/x86_64/os"
  done
else
  echo "vault/rocky/9.8/BaseOS/x86_64/os/repodata/repomd.xml : HTTP $c"
fi

echo "## EPEL 9, pub"
primary epel9 "$EPEL9" -
cherche epel9 epel9 "$EPEL9"

echo "## EPEL 9, instantanés de pub/archive/epel (entrées commençant par 9)"
n9=0
for e in ${ARCH_EPEL#*: }; do
  case $e in 9*) ;; *) continue ;; esac
  n9=$((n9 + 1)); u=https://dl.fedoraproject.org/pub/archive/epel/${e%/}/Everything/x86_64
  c=$(code "$D/archive-${e%/}.essai" "$u/repodata/repomd.xml")
  echo "archive ${e%/} : repomd.xml HTTP $c"
  [ "$c" != 200 ] || { primary "archive-${e%/}" "$u" -; cherche "archive-${e%/}" epel9 "$u"; }
done
echo "instantanés 9.x interrogés : $n9"

echo "## EPEL 9, kojipkgs (chemin de construction et chemin signé)"
python3 -I - "$D/attendus" "$D/epel9.primary.xml" > "$D/koji" <<'PY'
import sys, xml.etree.ElementTree as E
C = '{http://linux.duke.edu/metadata/common}'; RP = '{http://linux.duke.edu/metadata/rpm}'
voulus = [(f, s) for d, f, s in (l.split() for l in open(sys.argv[1], encoding='utf-8')) if d == 'epel9']
src = {}
for _, p in E.iterparse(sys.argv[2]):
    if p.tag == C + 'package':
        s = p.find(C + 'format').find(RP + 'sourcerpm').text or ''
        src[p.find(C + 'name').text] = s.rsplit('-', 2)[0]
        p.clear()
for f, s in voulus:
    b = f[:-len('.rpm')]; b, arch = b.rsplit('.', 1); nom, ver, rel = b.rsplit('-', 2)
    print(f, s, src.get(nom, nom), ver, rel, arch, 'primary' if nom in src else 'repli : nom binaire')
PY
while read -r f s sn ver rel arch org; do
  for k in construction signe; do
    if [ $k = construction ]; then u=$KOJI/packages/$sn/$ver/$rel/$arch/$f; else u=$KOJI/packages/$sn/$ver/$rel/data/signed/$KID/$arch/$f; fi
    mkdir -p "$D/koji-$k"
    c=$(code "$D/koji-$k/$f" "$u")
    if [ "$c" = 200 ]; then
      h=$(sha256sum < "$D/koji-$k/$f" | cut -c1-64)
      [ "$h" = "$s" ] && echo "$k : $f : HTTP 200, sha256 égal au 17/11" || echo "$k : $f : HTTP 200, sha256 différent ($h)"
    else
      echo "$k : $f : HTTP $c ($u ; paquet source : $sn, $org)"
    fi
  done
  c=$(curl -sS -o /dev/null -I -L -w '%{http_code}' --max-time 60 "$KOJI/packages/$sn/$ver/$rel/data/sigcache/$KID/$arch/$f.sig" 2>/dev/null || echo erreur)
  echo "sigcache : $f.sig : HTTP $c"
done < "$D/koji"
echo "# fin $(date -u +%FT%TZ)"
