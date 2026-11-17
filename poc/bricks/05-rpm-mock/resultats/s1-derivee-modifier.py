"""Copie modifiée de s1.sh : étapes hote97, boot_racine et boot_image (décision « Dix lignes »). Insertions seules.
Usage : python3 -I modifier.py <s1.sh du dépôt> <copie à écrire>"""
import hashlib, sys
src, dst = sys.argv[1:3]
a = open(src, encoding='utf-8').read()
assert hashlib.sha256(a.encode()).hexdigest().startswith('139aab3c')

ENTETE = """#   hote97      (../s1-derivee.patch, préparé à sec le 17/11/2026, NON APPLIQUÉ ; décision du propriétaire « Dix lignes ») : hôte
#               seul, ni cluster ni Zot ; primary de vault 9.7 (BaseOS, AppStream, CRB, extras : dépôts actifs du modèle rocky-9)
#               contrôlés par leur repomd.xml vérifié par gpgv ; dépôt et sha256 de chacun des dix paquets de l'image dérivée
#               (arrêt si l'un manque) ; Requires de python3-dnf-plugins-core lus dans le primary
#   boot_racine pod Kata privilégié, root, label prefetch-rpm, image d'essai : racine de rockylinux:9.7 copiée (podman image
#               mount), dnf --installroot des dix NEVRA exacts depuis vault 9.7, clé vérifiée sur l'hôte ; transaction affichée ;
#               rpm -K ; rpm téléchargés comparés aux dix de hote97, ni plus ni moins ; listes rpm -qa complètes avant et après ;
#               archive rapatriée, sha256 comparé ; rien poussé
#   boot_image  image de bootstrap dérivée assemblée sans rien exécuter (crane append d'une couche pleine), annotations de la
#               base, poussée dans Zot sous essais-05/rocky9-bootstrap:<PREFIXE> (dépôt définitif)
"""
VARS = """DEPOT_DERIVE=essais-05/rocky9-bootstrap   # image de bootstrap dérivée (décision « Dix lignes ») ; Zot : dépôt définitif
# nom epoch:version-release arch : les dix lignes de verrou_brut (six ajouts, quatre montées de version de la famille dnf)
DERIVEE=("dbus-libs 1:1.12.20-8.el9 x86_64" "python3-dateutil 1:2.9.0.post0-1.el9_7 noarch" "python3-dbus 0:1.2.18-2.el9.0.1 x86_64"
  "python3-dnf-plugins-core 0:4.3.0-24.el9_7 noarch" "python3-six 0:1.15.0-9.el9 noarch" "python3-systemd 0:234-19.el9 x86_64"
  "dnf 0:4.14.0-31.el9.rocky.0.1 noarch" "dnf-data 0:4.14.0-31.el9.rocky.0.1 noarch" "python3-dnf 0:4.14.0-31.el9.rocky.0.1 noarch"
  "yum 0:4.14.0-31.el9.rocky.0.1 noarch")
DEPOTS97=(BaseOS AppStream CRB extras)   # dépôts actifs du modèle rocky-9 de mock-core-configs 45.2 (enabled=1)
"""
BLOC = r"""# Image de bootstrap dérivée (décision du propriétaire « Dix lignes », 17/11/2026) : rockylinux:9.7 plus les six paquets que
# mock ajoute et les quatre montées de version de dnf qu'il fait (mesure de verrou_brut). Avec cette image marquée prête, mock
# n'installerait plus rien dans le bootstrap (buildroot.py:590, lecture). Trois étapes, trois accords : hote97 (hôte seul),
# boot_racine (pod, rien poussé), boot_image (écriture dans Zot).
# Non lus, à mesurer : qu'un dnf install d'un NEVRA exact fasse la montée de version d'un paquet présent ; qu'un dnf de 9.8 en
# --installroot donne le même état que le dnf du bootstrap dans le chroot ; si dnf importe la clé (gpg-pubkey) dans la racine.
# La racine n'est pas vide : ses .repo (mirrorlist) sont écartés par --setopt=reposdir=/w/aucun en ligne de commande, comme à
# racine. L'archive n'est pas reproductible au bit près (base rpm : INSTALLTIME ; journaux de dnf sous var/log).

etape_hote97() { # hôte seul, ni cluster ni Zot : primary de vault 9.7 (figé) vérifiés ; dépôt et sha256 des dix paquets
  local d=$T/hote fp n x
  [ -s "$d/RPM-GPG-KEY-Rocky-9" ] && [ -s "$d/cles.gpg" ] || { echo "KO   lancer d'abord l'étape hote" >&2; exit 1; }
  fp=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  attendu "empreinte de la clé de Rocky (relevée par hote)" "$fp" "$FP_ROCKY"
  echo "## dépôts de vault 9.7, vérifiés sur l'hôte"
  for n in "${DEPOTS97[@]}"; do
    x=${n,,}97
    depot_hote "$x" "$VAULT97/$n/x86_64/os" 1 "$FP_ROCKY"
    if [ -s "$d/v97-$n.repomd.xml" ]; then
      echo "$x : repomd.xml égal au relevé de hote : $(cmp -s "$d/v97-$n.repomd.xml" "$d/$x.repomd.xml" && echo oui || echo non)"
    else echo "$x : relevé de hote absent"; fi
  done
  echo "## les dix paquets de l'image dérivée"
  python3 -I - "$T" "${DERIVEE[@]}" <<'PY'
import os, sys, xml.etree.ElementTree as E
t = sys.argv[1]; ko = 0
C = '{http://linux.duke.edu/metadata/common}'; RP = '{http://linux.duke.edu/metadata/rpm}'
voulu = {}
for e in sys.argv[2:]:
    nom, evr, arch = e.split(); ep, vr = evr.split(':', 1); v, r = vr.rsplit('-', 1)
    voulu[(nom, ep, v, r, arch)] = []
req = []
for depot in ('baseos97', 'appstream97', 'crb97', 'extras97'):   # lecture en flux : le primary d'AppStream est gros
    for _, p in E.iterparse(f'{t}/{depot}.primary.xml'):
        if p.tag != C + 'package': continue
        x = p.find(C + 'version')
        k = (p.find(C + 'name').text, x.get('epoch'), x.get('ver'), x.get('rel'), p.find(C + 'arch').text)
        if k in voulu:
            voulu[k].append((depot, p.find(C + 'checksum').text, p.find(C + 'location').get('href')))
            if k[0] == 'python3-dnf-plugins-core':
                f = p.find(C + 'format'); q = f.find(RP + 'requires') if f is not None else None
                for y in (q if q is not None else []):
                    w = (y.get('epoch') + ':' if y.get('epoch') else '') + (y.get('ver') or '') + ('-' + y.get('rel') if y.get('rel') else '')
                    req.append(f"{depot} : {y.get('name')} {y.get('flags') or ''} {w}".rstrip())
        p.clear()
lignes = []
for k, c in voulu.items():
    nevra = f'{k[0]}-{k[1]}:{k[2]}-{k[3]}.{k[4]}'
    s = {h for _, h, _ in c}
    if c and len(s) == 1:
        print(f'OK   {nevra} dans {", ".join(d for d, _, _ in c)} : sha256 {c[0][1]} ({c[0][2]})')
        lignes.append(f'{c[0][2].rsplit("/", 1)[1]} {c[0][1]} {c[0][0]}')
    else:
        ko = 1; print(f'KO   {nevra} : {len(c)} candidat(s), {len(s)} empreinte(s) distincte(s)')
print(f'requires de python3-dnf-plugins-core : {len(req)} entrée(s)')
for y in req: print('requires de python3-dnf-plugins-core, ' + y)
if os.path.exists(f'{t}/derivee.sha256'): os.remove(f'{t}/derivee.sha256')
if ko == 0: open(f'{t}/derivee.sha256', 'w', encoding='utf-8').write('\n'.join(lignes) + '\n')
sys.exit(ko)
PY
}

dnf97_conf() { # configuration de dnf de boot_racine : options du modèle rocky-9 (best, weak deps), vault 9.7 en baseurl fixes
  local n
  cat <<EOF
[main]
gpgcheck=1
install_weak_deps=0
best=1
keepcache=1
cachedir=/w/cache97
reposdir=/w/aucun
EOF
  for n in "${DEPOTS97[@]}"; do
    printf '[%s97]\nname=Rocky 9.7 %s (vault)\nbaseurl=%s/%s/x86_64/os/\nrepo_gpgcheck=1\ngpgkey=file:///w/cles/RPM-GPG-KEY-Rocky-9\n' \
      "${n,,}" "$n" "$VAULT97" "$n"
  done
}

# Script de boot_racine (root, image d'essai). L'image d'essai porte /usr/bin/dnf-3 (python3-dnf 4.14.0-34.el9_8) mais pas
# /usr/bin/dnf (paquet dnf absent de racine.tar) : dnf-3 est appelé, comme le fait mock. dnf ne lit que /w/dnf97.conf ; la clé
# vient de l'hôte. Rien n'est écrit dans le
# montage de podman image mount : la racine est copiée sous /w. Sorties brutes ; l'hôte décide (repomd, rpm, rpm -K, archive).
SONDE_DERIVEE='set -u
export LC_ALL=C
Q="%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE} sigpgp=%{SIGPGP:pgpsig} rsaheader=%{RSAHEADER:pgpsig}\n"
R=/w/boot-racine
C="/w/cache97 $R/w/cache97"   # dnf peut placer cachedir dans la racine (--installroot) : les deux sont lus
DNF="dnf-3 -y -c /w/dnf97.conf --setopt=reposdir=/w/aucun --installroot=$R --releasever=9"
echo "dnf-3 : $(dnf-3 --version 2>/dev/null | head -1) ; rpm : $(rpm --version)"
mkdir -p /w/aucun /w/cache97
t=$(date +%s); podman pull @BOOT@ > /w/pull.log 2>&1; r=$?
echo "podman pull de rockylinux:9.7 : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || { tail -n 5 /w/pull.log; exit 0; }
m=$(podman image mount @BOOT@ 2>/w/mount.err); r=$?; echo "podman image mount : rc $r"
[ $r = 0 ] || { tail -n 3 /w/mount.err; exit 0; }
rm -rf "$R"; mkdir -p "$R"; cp -a "$m/." "$R/" 2>/w/cp.err; r=$?
podman image umount @BOOT@ >/dev/null 2>&1
echo "copie de la racine de rockylinux:9.7 : rc $r, $(du -sk "$R" | cut -f1) kB"
[ $r = 0 ] || { tail -n 3 /w/cp.err; exit 0; }
echo "dépôts de la racine, écartés (reposdir=/w/aucun) : $(ls "$R/etc/yum.repos.d" 2>/dev/null | tr "\n" " ")"
rpm --root "$R" -qa --qf "$Q" 2>/w/avant.err | sort > /w/avant.txt
echo "racine avant : rpm -qa $(wc -l < /w/avant.txt) ligne(s), stderr $(wc -l < /w/avant.err) ligne(s)"
echo "gpg-pubkey avant : $(rpm --root "$R" -qa "gpg-pubkey*" 2>/dev/null | tr "\n" " ")"
t=$(date +%s); $DNF makecache > /w/makecache.log 2>&1; r=$?
echo "makecache : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || { tail -n 15 /w/makecache.log; exit 0; }
echo "caches : $(for c in $C; do [ -d $c ] && printf "%s " $c; done)"
for d in baseos97 appstream97 crb97 extras97; do f=$(find $C -path "*/$d-*/repodata/repomd.xml" 2>/dev/null | head -1)
  echo "repomd $d : sha256 $([ -n "$f" ] && sha256sum < "$f" | cut -c1-64)"; done
t=$(date +%s); $DNF install @PAQUETS@ > /w/install.log 2>&1; r=$?
echo "installation : rc $r en $(($(date +%s) - t)) s"
sed -n "/^Transaction Summary/q; /^=\{10,\}/,\$p" /w/install.log | grep -v -e "^=" -e "^\$" | sed "s/^/transaction : /"
grep -E "^(Install|Upgrade|Remove|Downgrade|Reinstall|Skip) +[0-9]+ Package" /w/install.log | sed "s/^/résumé de la transaction : /"
[ $r = 0 ] || { tail -n 25 /w/install.log; exit 0; }
for f in $(find $C -name "*.rpm" 2>/dev/null | sort); do echo "rpm ${f##*/} $(sha256sum < $f | cut -c1-64)"; done
rpm --root "$R" -K $(find $C -name "*.rpm" 2>/dev/null) > /w/k.log 2>&1
echo "rpm -K : $(grep -c -E "digests signatures OK$" /w/k.log) OK sur $(find $C -name "*.rpm" 2>/dev/null | wc -l)"
grep -v -E "digests signatures OK$" /w/k.log | head -n 5
echo "gpg-pubkey après : $(rpm --root "$R" -qa "gpg-pubkey*" 2>/dev/null | tr "\n" " ")"
rpm --root "$R" -qa --qf "$Q" 2>/w/apres.err | sort > /w/apres.txt
echo "racine dérivée : rpm -qa $(wc -l < /w/apres.txt) ligne(s), stderr $(wc -l < /w/apres.err) ligne(s)"
comm -13 /w/avant.txt /w/apres.txt | sed "s/^/seulement dans la racine dérivée : /"
comm -23 /w/avant.txt /w/apres.txt | sed "s/^/seulement dans rockylinux:9.7 brut : /"
echo "lignes communes : $(comm -12 /w/avant.txt /w/apres.txt | wc -l)"
sed "s/^/racine dérivée, liste : /" /w/apres.txt
rpm --root "$R" -q --requires python3-dnf-plugins-core 2>&1 | sed "s/^/requires du greffon installé : /"
rm -rf "$R/w"   # seul dossier ajouté par la sonde ; var/cache/dnf de la base est gardé (base plus dix paquets)
echo "restes de /w dans la racine : $(ls -d "$R/w" 2>/dev/null | wc -l)"
echo "var/cache/dnf de la racine : $(find "$R/var/cache/dnf" -mindepth 1 2>/dev/null | wc -l) entrée(s), gardées"
tar --sort=name --format=posix --xattrs --xattrs-include="*" --numeric-owner -C "$R" -cf /w/boot-racine.tar .; r=$?
echo "archive racine dérivée : rc $r, $(stat -c %s /w/boot-racine.tar) octets, sha256 $(sha256sum < /w/boot-racine.tar | cut -c1-64)"
df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
true'

controle_derivee() { # journal : rpm téléchargés comparés aux dix fichiers et sha256 de hote97, ni plus ni moins
  python3 -I - "$T/derivee.sha256" "$1" <<'PY'
import sys
att = {}
for l in open(sys.argv[1], encoding='utf-8'):
    x = l.split()
    if len(x) == 3: att[x[0]] = x[1]
vu = {}
for l in open(sys.argv[2], encoding='utf-8'):
    x = l.split()
    if len(x) == 3 and x[0] == 'rpm' and x[1].endswith('.rpm'): vu[x[1]] = x[2]
ko = [f'non épinglé : {f}' for f in sorted(set(vu) - set(att))] + [f'absent : {f}' for f in sorted(set(att) - set(vu))] \
    + [f'sha256 différent : {f}' for f in sorted(set(vu) & set(att)) if vu[f] != att[f]]
bons = sum(1 for f in set(vu) & set(att) if vu[f] == att[f])
print(('OK   ' if not ko and len(att) == 10 else 'KO   ') + f'rpm téléchargés conformes aux dix de hote97 : {bons} sur {len(att)}, {len(vu)} téléchargé(s)')
for k in ko: print('     écart : ' + k)
sys.exit(1 if ko or len(att) != 10 else 0)
PY
}

etape_boot_racine() {
  local d img n=s1-05-boot-racine p="" r s x
  rm -f "$T/boot-racine.tar" "$T/boot-racine.sha256"   # aucune archive d'un passage précédent ne survit à un échec
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  [ -s "$T/derivee.sha256" ] && [ -s "$T/hote/RPM-GPG-KEY-Rocky-9" ] || { echo "KO   lancer d'abord l'étape hote97" >&2; exit 1; }
  for r in baseos97 appstream97 crb97 extras97; do [ -s "$T/$r.repomd.sha256" ] || { echo "KO   lancer d'abord l'étape hote97" >&2; exit 1; }; done
  for x in "${DERIVEE[@]}"; do set -- $x; p="$p $1-${2#0:}.$3"; done
  img=$REG/$DEPOT_ESSAI@$d
  echo "image du pod : $img ; base : $BOOT"
  echo "paquets demandés :$p"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/cles/RPM-GPG-KEY-Rocky-9 "$T/hote/RPM-GPG-KEY-Rocky-9"
  dnf97_conf > "$T/dnf97.conf" && livrer "$n" /w/dnf97.conf "$T/dnf97.conf"
  sed -e "s|@BOOT@|$BOOT|g" -e "s|@PAQUETS@|${p# }|g" <<<"$SONDE_DERIVEE" | dans "$n" boot-racine
  for r in baseos97 appstream97 crb97 extras97; do
    ( attendu "repomd $r lu par dnf dans le pod = repomd vérifié sur l'hôte" "$(champ boot-racine "repomd $r" | sed 's/^sha256 //')" \
      "$(cat "$T/$r.repomd.sha256")" ) || { pod_retirer "$n"; exit 1; }
  done
  ( attendu "rpm -K" "$(champ boot-racine 'rpm -K')" "10 OK sur 10" ) || { pod_retirer "$n"; exit 1; }
  controle_derivee "$T/boot-racine.log" || { pod_retirer "$n"; echo "KO   rpm téléchargés différents des dix épinglés : archive non rapatriée" >&2; exit 1; }
  s=$(sed -n 's/^archive racine dérivée : rc 0, .*sha256 \([0-9a-f]\{64\}\)$/\1/p' "$T/boot-racine.log")
  [ -n "$s" ] || { pod_retirer "$n"; echo "KO   archive racine dérivée absente" >&2; exit 1; }
  kubectl exec -n builds "$n" -- cat /w/boot-racine.tar </dev/null > "$T/boot-racine.tar" \
    || { rm -f "$T/boot-racine.tar"; pod_retirer "$n"; echo "KO   rapatriement" >&2; exit 1; }
  ( attendu "archive racine dérivée rapatriée" "$(sha256sum < "$T/boot-racine.tar" | cut -c1-64)" "$s" ) \
    || { rm -f "$T/boot-racine.tar"; pod_retirer "$n"; exit 1; }
  echo "$s" > "$T/boot-racine.sha256"
  pod_retirer "$n"
}

etape_boot_image() {
  local d
  [ -s "$T/boot-racine.tar" ] && [ -s "$T/boot-racine.sha256" ] || { echo "KO   lancer d'abord l'étape boot_racine" >&2; exit 1; }
  attendu "archive racine dérivée, sha256 égal à celui de boot_racine" "$(sha256sum < "$T/boot-racine.tar" | cut -c1-64)" "$(cat "$T/boot-racine.sha256")"
  echo "archive racine dérivée : $(stat -c %s "$T/boot-racine.tar") octets"
  [ -s "$T/docker/config.json" ] || { auth_zot "$T/zot.json"; mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"; }
  zot crane append --oci-empty-base -f "$T/boot-racine.tar" -t "$REG_HOTE/$DEPOT_DERIVE:$PREFIXE" >/dev/null 2>"$T/crane.err" \
    || { cat "$T/crane.err" >&2; exit 1; }
  zot crane mutate "$REG_HOTE/$DEPOT_DERIVE:$PREFIXE" --set-platform linux/amd64 -t "$REG_HOTE/$DEPOT_DERIVE:$PREFIXE" \
    -a "org.opencontainers.image.base.name=$REG/$DEPOT_AMONT" -a "org.opencontainers.image.base.digest=$BOOT_DIGEST" \
    >/dev/null 2>"$T/crane.err" || { cat "$T/crane.err" >&2; exit 1; }
  d=$(zot crane digest "$REG_HOTE/$DEPOT_DERIVE:$PREFIXE")
  echo "$d" > "$T/boot-image.digest"
  zot crane manifest "$REG_HOTE/$DEPOT_DERIVE@$d" | jq -r '.layers[] | "couche \(.digest) \(.size) octets"'
  zot crane manifest "$REG_HOTE/$DEPOT_DERIVE@$d" | jq -r '(.annotations // {}) | to_entries[] | "annotation \(.key) = \(.value)"'
  zot crane config "$REG_HOTE/$DEPOT_DERIVE@$d" | jq -r '"config : os \(.os) ; architecture \(.architecture)"'
  echo "image de bootstrap dérivée : $REG/$DEPOT_DERIVE@$d"
}

"""
for ancre, ajout, avant in [
    ("# Les replis (stockage vfs", ENTETE, True),
    ("T=$W/s1-05\n", VARS, True),
    ('lancer "$PREFIXE" "05 S1" "$@"\n', BLOC, True)]:
    assert a.count(ancre) == 1, ancre
    a = a.replace(ancre, ajout + ancre)
open(dst, 'w', encoding='utf-8').write(a)
print('copie écrite :', hashlib.sha256(a.encode()).hexdigest())
