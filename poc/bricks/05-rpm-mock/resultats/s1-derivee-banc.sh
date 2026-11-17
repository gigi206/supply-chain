#!/usr/bin/env bash
# Banc hors réseau des étapes hote97, boot_racine et boot_image (s1-derivee.patch, décision « Dix lignes »), écrit le 17/11/2026
# avant tout passage. Ni cluster, ni Zot, ni réseau extérieur : un registre crane en loopback pour G.
# A : insertions seules ; la copie, blocs insérés retirés, redonne le s1.sh du dépôt octet pour octet.
# B : bash -n ; shellcheck : remarques de la copie comparées à celles du dépôt.
# C : script Python de hote97 sur des primary fictifs : nominal, paquet absent (et ancien derivee.sha256 retiré), deux
#     empreintes, mauvaise architecture ; DERIVEE comparé aux dix lignes archivées de verrou_brut.
# D : SONDE_DERIVEE rendue, /w remplacé par un dossier du banc, podman, dnf et rpm remplacés par des doublures (contenus
#     inventés) : nominal, cache dans la racine, pull refusé, installation refusée, rpm en trop.
# E : controle_derivee sur les journaux de D et le derivee.sha256 de C : conforme, rpm en trop, empreinte fausse, rpm absent.
# F : structure : fonctions, nom du pod, ordre de etape_boot_racine, pod retiré avant chaque arrêt, dnf97_conf contre le modèle
#     rocky-9 de mock 6.9 (archive de M2).
# G : etape_boot_image contre un registre crane en loopback : append, mutate (plateforme, annotations), manifeste, config ;
#     archive dont le sha256 diffère de celui de boot_racine : arrêt avant tout envoi.
# H : etape_boot_racine jouée avec des doublures (pod, livraison, sonde rejouée depuis les journaux de D, kubectl) : nominal,
#     repomd différent, rpm en trop, archive absente, archive corrompue ; pod retiré et aucune archive laissée hors du nominal.
# I : commandes de la sonde présentes dans racine.tar (image d'essai), lu par son nom, sha256 de l'étape racine.
# Non couvert : vrai pod, vrai dnf, vrai rpm, vrai podman, kubectl, Zot, vault 9.7.
# Usage : banc-derivee.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier de travail, vidé>
set -uo pipefail
export LC_ALL=C
D=$1; S1N=$2; B=$3
S1A=$D/poc/bricks/05-rpm-mock/s1.sh
R05=$D/poc/bricks/05-rpm-mock/resultats
rm -rf -- "${B:?}"; mkdir -p "$B"
echo "# banc-derivee.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), python3 $(python3 -c 'import platform; print(platform.python_version())')"
echo "# s1.sh du dépôt $(sha256sum < "$S1A" | cut -c1-64) ; copie modifiée $(sha256sum < "$S1N" | cut -c1-64)"
ko=0
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
egal() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else nok "$1 : $2 (attendu : $3)"; fi; }
extraire() { # début fin fichier : texte de la copie entre deux marqueurs (début inclus, fin exclue)
  python3 -I - "$S1N" "$1" "$2" "$3" <<'PY'
import sys
n = open(sys.argv[1], encoding='utf-8').read(); i = n.index(sys.argv[2]); j = n.index(sys.argv[3], i)
open(sys.argv[4], 'w', encoding='utf-8').write(n[i:j])
PY
}

echo "## A : insertions seules"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 3
python3 -I - "$S1A" "$S1N" <<'PY' || ko=1
import sys
a, n = (open(f, encoding='utf-8').read() for f in sys.argv[1:3])
c = [('#   hote97 ', '# Les replis (stockage vfs'), ('DEPOT_DERIVE=', 'T=$W/s1-05\n'), ('# Image de bootstrap dérivée (décision', 'lancer "$PREFIXE" "05 S1" "$@"\n')]
r = n; t = []
for d, f in c:
    i = r.index(d); j = r.index(f, i); t.append(r[i:j].count('\n')); r = r[:i] + r[j:]
print('OK   copie sans les blocs insérés égale au dépôt' if r == a else 'KO   copie sans les blocs insérés différente du dépôt')
print('     lignes insérées : en-tête %d, variables %d, étapes %d' % tuple(t))
sys.exit(0 if r == a else 1)
PY

echo "## B : syntaxe et shellcheck"
bash -n "$S1N" && ok "bash -n de la copie" || nok "bash -n de la copie"
shellcheck -f gcc "$S1A" 2>/dev/null | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort | uniq -c > "$B/sc-avant.txt"
shellcheck -f gcc "$S1N" 2>/dev/null | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort | uniq -c > "$B/sc-apres.txt"
echo "     remarques shellcheck : dépôt $(awk '{s+=$1} END {print s+0}' "$B/sc-avant.txt"), copie $(awk '{s+=$1} END {print s+0}' "$B/sc-apres.txt")"
diff "$B/sc-avant.txt" "$B/sc-apres.txt" | sed 's/^/     diff shellcheck : /'
egal "remarques shellcheck SC1112 (guillemet typographique) dans la copie" "$(grep -c SC1112 "$B/sc-apres.txt")" 0
egal "remarques shellcheck de niveau warning ou plus dans la copie" "$(shellcheck -S warning -f gcc "$S1N" 2>/dev/null | wc -l)" 0

echo "## C : hote97, dix paquets dans des primary fictifs"
extraire 'DERIVEE=(' 'DEPOTS97=(' "$B/derivee.sh"
extraire 'DEPOTS97=(' 'T=$W/s1-05' "$B/depots97.sh"
egal "entrées de DERIVEE" "$(. "$B/derivee.sh"; echo "${#DERIVEE[@]}")" 10
python3 -I - "$B/derivee.sh" "$R05/s1-verrou_brut.log" <<'PY' || ko=1
import re, sys
s = open(sys.argv[1], encoding='utf-8').read(); L = open(sys.argv[2], encoding='utf-8').read()
e = re.findall(r'"([^"]+)"', s)
aj = {l.split('seulement dans le bootstrap de mock : ', 1)[1].split(' sigpgp=')[0] for l in L.split('\n') if 'seulement dans le bootstrap de mock : ' in l}
d = {f'{n}.{a} {evr}' for n, evr, a in (x.split() for x in e)}
print(('OK   ' if d == aj and len(d) == 10 else 'KO   ') + f'DERIVEE égal aux dix lignes « seulement dans le bootstrap de mock » de s1-verrou_brut.log : {len(d & aj)} sur {len(aj)}')
sys.exit(0 if d == aj and len(d) == 10 else 1)
PY
python3 -I - "$S1N" "$B/h97.py" <<'PY'
import sys
n = open(sys.argv[1], encoding='utf-8').read(); k = n.index('etape_hote97() {')
i = n.index('\n', n.index("<<'PY'", k)) + 1; j = n.index('\nPY\n', i) + 1
open(sys.argv[2], 'w', encoding='utf-8').write(n[i:j])
PY
egal "boucle des dépôts de hote97 : noms" "$(. "$B/depots97.sh"; for n in "${DEPOTS97[@]}"; do printf '%s ' "${n,,}97"; done)" "baseos97 appstream97 crb97 extras97 "
primaires() { # cas : primary fictifs dans $B/c ; href Packages/<l>/<nom>-<ver>-<rel>.<arch>.rpm ; sha256 de « rpm banc <fichier> »
  rm -rf "$B/c"; mkdir -p "$B/c"
  python3 -I - "$B/c" "$1" "$B/derivee.sh" <<'PY'
import hashlib, re, sys
c, cas = sys.argv[1:3]; e = re.findall(r'"([^"]+)"', open(sys.argv[3], encoding='utf-8').read())
H = '<?xml version="1.0"?>\n<metadata xmlns="http://linux.duke.edu/metadata/common" xmlns:rpm="http://linux.duke.edu/metadata/rpm">\n'
dep = {d: [] for d in ('baseos97', 'appstream97', 'crb97', 'extras97')}
def pk(nom, ep, v, r, a, extra=''):
    f = f'{nom}-{v}-{r}.{a}.rpm'; h = hashlib.sha256(f'rpm banc {f}\n'.encode()).hexdigest()
    return (f'<package type="rpm"><name>{nom}</name><arch>{a}</arch><version epoch="{ep}" ver="{v}" rel="{r}"/>'
            f'<checksum type="sha256" pkgid="YES">{h}</checksum><location href="Packages/{nom[0]}/{f}"/>'
            f'<format>{extra}</format></package>\n')
REQ = ('<rpm:requires><rpm:entry name="python3-dnf" flags="GE" epoch="0" ver="4.4.3"/>'
       '<rpm:entry name="python(abi)" flags="EQ" epoch="0" ver="3.9"/><rpm:entry name="/usr/bin/python3"/></rpm:requires>'
       '<rpm:provides><rpm:entry name="banc-ne-pas-compter"/></rpm:provides>')
for i, x in enumerate(e):
    nom, evr, a = x.split(); ep, vr = evr.split(':'); v, r = vr.rsplit('-', 1)
    if cas == 'absent' and nom == 'python3-six': continue
    if cas == 'arch' and nom == 'yum': a = 'x86_64'
    d = 'baseos97' if i % 2 == 0 else 'appstream97'
    dep[d].append(pk(nom, ep, v, r, a, REQ if nom == 'python3-dnf-plugins-core' else ''))
    if nom == 'dbus-libs':   # présent aussi dans crb97 : même empreinte (accepté) ou autre (refusé)
        p = pk(nom, ep, v, r, a)
        dep['crb97'].append(p.replace('<checksum type="sha256" pkgid="YES">', '<checksum type="sha256" pkgid="YES">f') if cas == 'empreintes' else p)
dep['extras97'].append(pk('bruit', '0', '1', '1.el9', 'noarch'))
for d, l in dep.items(): open(f'{c}/{d}.primary.xml', 'w', encoding='utf-8').write(H + ''.join(l) + '</metadata>\n')
PY
}
jouer_c() { # cas : script de hote97 sur les primary du cas ; sortie dans $B/c-<cas>.out
  primaires "$1"; [ "$1" = nominal ] || cp "$B/c1.sha256" "$B/c/derivee.sha256"
  ( . "$B/derivee.sh"; python3 -I "$B/h97.py" "$B/c" "${DERIVEE[@]}" ) > "$B/c-$1.out" 2>&1; echo $? > "$B/c-$1.rc"
  sed 's/^/     /' "$B/c-$1.out"
}
echo "### C1 : nominal"
primaires nominal; ( . "$B/derivee.sh"; python3 -I "$B/h97.py" "$B/c" "${DERIVEE[@]}" ) > "$B/c-nominal.out" 2>&1
egal "C1 code" "$?" 0; sed 's/^/     /' "$B/c-nominal.out"
egal "C1 lignes OK" "$(grep -c '^OK   ' "$B/c-nominal.out")" 10
egal "C1 dbus-libs dans deux dépôts, même empreinte" "$(grep -c '^OK   dbus-libs-1:1.12.20-8.el9.x86_64 dans baseos97, crb97 : ' "$B/c-nominal.out")" 1
egal "C1 derivee.sha256 : lignes à trois champs" "$(awk 'NF == 3' "$B/c/derivee.sha256" | wc -l)" 10
egal "C1 nom de fichier sans epoch" "$(grep -c '^dbus-libs-1.12.20-8.el9.x86_64.rpm ' "$B/c/derivee.sha256")" 1
egal "C1 requires lus (provides exclus)" "$(sed -n 's/^requires de python3-dnf-plugins-core : //p' "$B/c-nominal.out")" "3 entrée(s)"
egal "C1 requires de python3-dnf" "$(grep -c '^requires de python3-dnf-plugins-core, appstream97 : python3-dnf GE 0:4.4.3$' "$B/c-nominal.out")" 1
egal "C1 requires sans version" "$(grep -c '^requires de python3-dnf-plugins-core, appstream97 : /usr/bin/python3$' "$B/c-nominal.out")" 1
cp "$B/c/derivee.sha256" "$B/c1.sha256"
echo "### C2 : python3-six absent"
jouer_c absent
egal "C2 code" "$(cat "$B/c-absent.rc")" 1
egal "C2 ligne KO" "$(grep -c '^KO   python3-six-0:1.15.0-9.el9.noarch : 0 candidat(s), 0 empreinte(s) distincte(s)$' "$B/c-absent.out")" 1
egal "C2 ancien derivee.sha256 retiré" "$(test -e "$B/c/derivee.sha256" && echo présent || echo retiré)" retiré
echo "### C3 : deux empreintes pour dbus-libs"
jouer_c empreintes
egal "C3 code" "$(cat "$B/c-empreintes.rc")" 1
egal "C3 ligne KO" "$(grep -c '^KO   dbus-libs-1:1.12.20-8.el9.x86_64 : 2 candidat(s), 2 empreinte(s) distincte(s)$' "$B/c-empreintes.out")" 1
echo "### C4 : yum en x86_64 seulement"
jouer_c arch
egal "C4 code" "$(cat "$B/c-arch.rc")" 1
egal "C4 ligne KO" "$(grep -c '^KO   yum-0:4.14.0-31.el9.rocky.0.1.noarch : 0 candidat(s)' "$B/c-arch.out")" 1

echo "## D : SONDE_DERIVEE avec doublures"
python3 -I - "$S1N" "$B" <<'PY'
import sys
n = open(sys.argv[1], encoding='utf-8').read(); B = sys.argv[2]
i = n.index("SONDE_DERIVEE='"); j = n.index("\ntrue'\n", i) + len("\ntrue'\n")
open(f'{B}/sonde-derivee.txt', 'w', encoding='utf-8').write(n[i + len("SONDE_DERIVEE='"):j - 2])
PY
P=$(. "$B/derivee.sh"; p=""; eval "$(grep -m1 'for x in "${DERIVEE\[@\]}"; do set -- $x; p=' "$S1N" | sed 's/^ *//')"; echo "${p# }")
egal "paquets demandés (epoch 0 retirée)" "$P" "dbus-libs-1:1.12.20-8.el9.x86_64 python3-dateutil-1:2.9.0.post0-1.el9_7.noarch python3-dbus-1.2.18-2.el9.0.1.x86_64 python3-dnf-plugins-core-4.3.0-24.el9_7.noarch python3-six-1.15.0-9.el9.noarch python3-systemd-234-19.el9.x86_64 dnf-4.14.0-31.el9.rocky.0.1.noarch dnf-data-4.14.0-31.el9.rocky.0.1.noarch python3-dnf-4.14.0-31.el9.rocky.0.1.noarch yum-4.14.0-31.el9.rocky.0.1.noarch"
sed -e "s|@BOOT@|exemple.test/r@sha256:0|g" -e "s|@PAQUETS@|$P|g" -e 's|\$R/w/|@RW@|g' -e "s|/w/|$B/w/|g" -e 's|@RW@|$R/w/|g' \
  -e "s|df -k /w |df -k $B/w |" "$B/sonde-derivee.txt" > "$B/sonde-rendue.txt"
egal "marqueurs @ restants" "$(grep -c '@[A-Z_]*@' "$B/sonde-rendue.txt")" 0
egal "/w restant hors banc (libellés et \$R/w exclus)" "$(sed -e 's|capacité de /w||' -e 's|restes de /w||' -e 's|\$R/w||g' "$B/sonde-rendue.txt" | grep -c '[^a-z]/w[/ "]')" 0
sh -n "$B/sonde-rendue.txt" && ok "sh -n de la sonde rendue" || nok "sh -n de la sonde rendue"
egal "appels de dnf sans -3 dans la sonde (début de commande)" "$(grep -o -E '(^|[;|&(] *|\$\()dnf( |$)' "$B/sonde-derivee.txt" | wc -l)" 0
mkdir -p "$B/bin"
cat > "$B/bin/podman" <<'X'
#!/bin/sh
case "$1 $2" in
  "pull "*) [ -e "$BANC/pull-ko" ] && { echo "doublure : pull refusé"; exit 125; }; exit 0 ;;
  "image mount") echo "$BANC/image" ;;
  "image umount") exit 0 ;;
  *) echo "doublure podman : appel inattendu $*" >&2; exit 9 ;;
esac
X
cat > "$B/bin/dnf-3" <<'X'
#!/bin/sh
[ "$1" = --version ] && { echo "4.14.0 (doublure)"; exit 0; }
case " $* " in *" -y -c $BANC/w/dnf97.conf --setopt=reposdir=$BANC/w/aucun --installroot=$BANC/w/boot-racine --releasever=9 "*) ;;
  *) echo "doublure dnf : appel inattendu $*" >&2; exit 9 ;; esac
root=$BANC/w/boot-racine; cmd=""; pk=""
for a in "$@"; do case $a in makecache|install) cmd=$a ;; -*) ;; *) [ "$cmd" = install ] && pk="$pk $a" ;; esac; done
c=$BANC/w/cache97; [ -e "$BANC/cache-racine" ] && c=$root/w/cache97
if [ "$cmd" = makecache ]; then
  for d in baseos97 appstream97 crb97 extras97; do mkdir -p "$c/$d-0123abcd/repodata"; echo "repomd $d banc" > "$c/$d-0123abcd/repodata/repomd.xml"; done; exit 0; fi
[ "$cmd" = install ] || { echo "doublure dnf : commande inattendue" >&2; exit 9; }
[ -e "$BANC/install-ko" ] && { echo "Error: Unable to find a match: banc"; exit 1; }
printf 'Dependencies resolved.\n================================================================================\n Package   Arch   Version   Repository   Size\n================================================================================\nInstalling:\n'
mkdir -p "$c/baseos97-0123abcd/packages"
for p in $pk; do f=$(echo "$p" | sed 's/-[0-9]*:/-/').rpm; printf 'rpm banc %s\n' "$f" > "$c/baseos97-0123abcd/packages/$f"; echo " $p   banc   baseos97   1 k"; done
[ -e "$BANC/rpm-en-trop" ] && printf 'rpm banc intrus\n' > "$c/baseos97-0123abcd/packages/intrus-1-1.el9.noarch.rpm"
printf '\nTransaction Summary\n================================================================================\nInstall  10 Packages\n\nComplete!\n'
cp "$root/var/lib/rpm/apres.modele" "$root/var/lib/rpm/apres.lst"; : > "$root/var/lib/rpm/cle"
X
cat > "$B/bin/rpm" <<'X'
#!/bin/sh
[ "$1" = --version ] && { echo "RPM version 4.16.1.3 (doublure)"; exit 0; }
[ "$1" = --root ] && [ "$2" = "$BANC/w/boot-racine" ] || { echo "doublure rpm : appel inattendu $*" >&2; exit 9; }
r=$2; shift 2
case "$1" in
  -qa) if [ "${2:-}" = --qf ]; then echo "avertissement de la doublure" >&2
         if [ -e "$r/var/lib/rpm/apres.lst" ]; then cat "$r/var/lib/rpm/apres.lst"; else cat "$r/var/lib/rpm/base.lst"; fi
       else [ -e "$r/var/lib/rpm/cle" ] && echo "gpg-pubkey-350d275d-6279464b"; fi ;;
  -K) shift; for f in "$@"; do echo "$f: digests signatures OK"; done ;;
  -q) [ "$2 $3" = "--requires python3-dnf-plugins-core" ] && echo "python3-dnf >= 4.4.3 (doublure)" ;;
  *) echo "doublure rpm : appel inattendu $*" >&2; exit 9 ;;
esac
X
chmod +x "$B/bin/podman" "$B/bin/dnf-3" "$B/bin/rpm"
image() { rm -rf "$B/image" "$B/w"; mkdir -p "$B/image/etc/yum.repos.d" "$B/image/var/lib/rpm" "$B/image/usr/bin" "$B/image/var/cache/dnf"
  : > "$B/image/etc/yum.repos.d/rocky.repo"; : > "$B/image/etc/yum.repos.d/rocky-extras.repo"; echo x > "$B/image/usr/bin/x"; echo c > "$B/image/var/cache/dnf/c"
  printf '%s\n' "bash.x86_64 0:5.1.8-9.el9 sigpgp=(none) rsaheader=banc" "dnf.noarch 0:4.14.0-31.el9 sigpgp=(none) rsaheader=banc" \
    "rpm.x86_64 0:4.16.1.3-39.el9 sigpgp=(none) rsaheader=banc" > "$B/image/var/lib/rpm/base.lst"
  printf '%s\n' "bash.x86_64 0:5.1.8-9.el9 sigpgp=(none) rsaheader=banc" "dnf.noarch 0:4.14.0-31.el9.rocky.0.1 sigpgp=(none) rsaheader=banc" \
    "python3-six.noarch 0:1.15.0-9.el9 sigpgp=(none) rsaheader=banc" "rpm.x86_64 0:4.16.1.3-39.el9 sigpgp=(none) rsaheader=banc" > "$B/image/var/lib/rpm/apres.modele"
  rm -f "$B/pull-ko" "$B/install-ko" "$B/cache-racine" "$B/rpm-en-trop"; }
jouer() { BANC=$B PATH=$B/bin:$PATH sh "$B/sonde-rendue.txt" > "$B/$1.log" 2>&1; egal "$1 : code" "$?" 0; sed 's/^/     /' "$B/$1.log"; }
communs() { # cas : contrôles d'un passage complet
  local l=$B/$1.log s
  egal "$1 copie de la racine" "$(grep -c '^copie de la racine de rockylinux:9.7 : rc 0, ' "$l")" 1
  egal "$1 dépôts de la racine affichés" "$(grep -c '^dépôts de la racine, écartés (reposdir=.*) : rocky-extras.repo rocky.repo $' "$l")" 1
  egal "$1 liste avant, stderr à part" "$(grep -c '^racine avant : rpm -qa 3 ligne(s), stderr 1 ligne(s)$' "$l")" 1
  egal "$1 gpg-pubkey avant, après" "$(grep -c -e '^gpg-pubkey avant : $' -e '^gpg-pubkey après : gpg-pubkey-350d275d-6279464b $' "$l")" 2
  egal "$1 repomd lus" "$(grep -c -E '^repomd (baseos97|appstream97|crb97|extras97) : sha256 [0-9a-f]{64}$' "$l")" 4
  egal "$1 repomd baseos97 = contenu de la doublure" "$(sed -n 's/^repomd baseos97 : sha256 //p' "$l")" "$(echo 'repomd baseos97 banc' | sha256sum | cut -c1-64)"
  egal "$1 transaction affichée (en-tête, Installing, dix lignes)" "$(grep -c '^transaction : ' "$l")" 12
  egal "$1 résumé" "$(grep -c '^résumé de la transaction : Install  10 Packages$' "$l")" 1
  egal "$1 rpm téléchargés" "$(grep -c -E '^rpm [^ ]+\.rpm [0-9a-f]{64}$' "$l")" 10
  egal "$1 rpm -K" "$(sed -n 's/^rpm -K : //p' "$l")" "10 OK sur 10"
  egal "$1 liste après, stderr à part" "$(grep -c '^racine dérivée : rpm -qa 4 ligne(s), stderr 1 ligne(s)$' "$l")" 1
  egal "$1 seulement dans la racine dérivée" "$(grep -c '^seulement dans la racine dérivée : ' "$l")" 2
  egal "$1 seulement dans l'image brute" "$(grep -c '^seulement dans rockylinux:9.7 brut : dnf.noarch 0:4.14.0-31.el9 ' "$l")" 1
  egal "$1 lignes communes" "$(sed -n 's/^lignes communes : //p' "$l")" 2
  egal "$1 liste complète" "$(grep -c '^racine dérivée, liste : ' "$l")" 4
  egal "$1 avertissement absent des listes" "$(grep -c 'avertissement' "$B/w/apres.txt" "$B/w/avant.txt" | awk -F: '{s+=$2} END {print s}')" 0
  egal "$1 requires du greffon" "$(grep -c '^requires du greffon installé : python3-dnf >= 4.4.3 (doublure)$' "$l")" 1
  egal "$1 restes de /w" "$(sed -n 's/^restes de \/w dans la racine : //p' "$l")" 0
  s=$(sed -n 's/^archive racine dérivée : rc 0, .*sha256 \([0-9a-f]\{64\}\)$/\1/p' "$l")
  egal "$1 archive : sha256 annoncé = fichier" "$s" "$(sha256sum < "$B/w/boot-racine.tar" | cut -c1-64)"
  tar -tf "$B/w/boot-racine.tar" > "$B/$1.tar.txt"
  egal "$1 archive : usr/bin/x présent" "$(grep -c '^\./usr/bin/x$' "$B/$1.tar.txt")" 1
  egal "$1 archive : pas de ./w" "$(grep -c '^\./w' "$B/$1.tar.txt")" 0
  egal "$1 archive : var/cache/dnf de la base gardé" "$(grep -c '^\./var/cache/dnf/c$' "$B/$1.tar.txt") $(grep -c '^var/cache/dnf de la racine : 1 entrée(s), gardées$' "$l")" "1 1"
  egal "$1 df en dernière ligne" "$(tail -n 1 "$l" | grep -c '^capacité de /w : [0-9]* kB ; utilisés : [0-9]* kB$')" 1
  egal "$1 montage jamais écrit" "$(test -e "$B/image/var/lib/rpm/apres.lst" -o -e "$B/image/var/lib/rpm/cle" && echo écrit || echo intact)" intact
}
echo "### D1 : nominal (cache sous /w)"
image; jouer d1; communs d1; cp "$B/w/boot-racine.tar" "$B/d1.tar"
echo "### D2 : cache dans la racine"
image; : > "$B/cache-racine"; jouer d2; communs d2
egal "D2 deux caches listés" "$(grep -c "^caches : $B/w/cache97 $B/w/boot-racine/w/cache97 \$" "$B/d2.log")" 1
echo "### D3 : pull refusé"
image; : > "$B/pull-ko"; jouer d3
egal "D3 pull en échec affiché" "$(grep -c '^podman pull de rockylinux:9.7 : rc 125 ' "$B/d3.log")" 1
egal "D3 arrêt avant dnf (aucune archive)" "$(grep -c -e '^makecache' -e '^archive racine dérivée' "$B/d3.log")" 0
echo "### D4 : installation refusée"
image; : > "$B/install-ko"; jouer d4
egal "D4 installation en échec" "$(grep -c '^installation : rc 1 ' "$B/d4.log")" 1
egal "D4 erreur de dnf affichée" "$(grep -c '^Error: Unable to find a match: banc$' "$B/d4.log")" 1
egal "D4 aucun rpm, aucune archive" "$(grep -c -e '^rpm .*\.rpm ' -e '^archive racine dérivée' "$B/d4.log")" 0
echo "### D5 : un rpm en trop"
image; : > "$B/rpm-en-trop"; jouer d5; cp "$B/w/boot-racine.tar" "$B/d5.tar"
egal "D5 rpm téléchargés" "$(grep -c -E '^rpm [^ ]+\.rpm [0-9a-f]{64}$' "$B/d5.log")" 11
egal "D5 rpm -K" "$(sed -n 's/^rpm -K : //p' "$B/d5.log")" "11 OK sur 11"
egal "doublures jamais appelées hors du contrat (D1 à D5)" "$(cat "$B"/d[1-5].log | grep -c 'appel inattendu\|commande inattendue')" 0

echo "## E : controle_derivee"
python3 -I - "$S1N" "$B/controle.py" <<'PY'
import sys
n = open(sys.argv[1], encoding='utf-8').read(); k = n.index('controle_derivee() {')
i = n.index('\n', n.index("<<'PY'", k)) + 1; j = n.index('\nPY\n', i) + 1
open(sys.argv[2], 'w', encoding='utf-8').write(n[i:j])
PY
ctl() { python3 -I "$B/controle.py" "$2" "$3" > "$B/e-$1.out" 2>&1; echo $? > "$B/e-$1.rc"; sed 's/^/     /' "$B/e-$1.out"; }
ctl e1 "$B/c1.sha256" "$B/d1.log"
egal "E1 conforme (sha256 de C1 contre rpm de D1)" "$(cat "$B/e-e1.rc") $(head -1 "$B/e-e1.out")" "0 OK   rpm téléchargés conformes aux dix de hote97 : 10 sur 10, 10 téléchargé(s)"
ctl e2 "$B/c1.sha256" "$B/d5.log"
egal "E2 rpm en trop" "$(cat "$B/e-e2.rc") $(grep -c '^     écart : non épinglé : intrus-1-1.el9.noarch.rpm$' "$B/e-e2.out")" "1 1"
awk 'NR == 1 {$2 = ($2 ~ /^0/ ? "1" : "0") substr($2, 2)} {print}' "$B/c1.sha256" > "$B/e3.sha256"
ctl e3 "$B/e3.sha256" "$B/d1.log"
egal "E3 empreinte fausse" "$(cat "$B/e-e3.rc") $(grep -c '^     écart : sha256 différent : ' "$B/e-e3.out")" "1 1"
grep -v '^rpm yum-' "$B/d1.log" > "$B/e4.log"
ctl e4 "$B/c1.sha256" "$B/e4.log"
egal "E4 rpm absent" "$(cat "$B/e-e4.rc") $(grep -c '^     écart : absent : yum-4.14.0-31.el9.rocky.0.1.noarch.rpm$' "$B/e-e4.out")" "1 1"
head -n 9 "$B/c1.sha256" > "$B/e5.sha256"; grep -v '^rpm yum-' "$B/d1.log" > "$B/e5.log"
ctl e5 "$B/e5.sha256" "$B/e5.log"
egal "E5 neuf attendus, neuf vus : refusé (dix exigés)" "$(cat "$B/e-e5.rc")" 1

echo "## F : structure"
for f in etape_hote97 dnf97_conf controle_derivee etape_boot_racine etape_boot_image; do egal "fonction $f" "$(grep -c "^$f() {" "$S1N")" 1; done
egal "nom du pod conforme (minuscules, chiffres, tirets)" "$(grep -o 'n=s1-05-boot-racine ' "$S1N" | grep -c -E '^n=[a-z0-9-]+ $')" 1
python3 -I - "$S1N" <<'PY' || ko=1
import sys
n = open(sys.argv[1], encoding='utf-8').read(); k = n.index('etape_boot_racine() {'); f = n.index('\n}\n', k) + 1
c = n[k:f]
o = [c.index(x) for x in ('pod_demarrer "$n"', 'livrer "$n" /w/cles/', 'dans "$n" boot-racine', 'attendu "repomd $r', 'attendu "rpm -K"',
                          'controle_derivee "$T/boot-racine.log"', 'kubectl exec -n builds "$n" -- cat', 'attendu "archive racine dérivée rapatriée"', 'echo "$s" > "$T/boot-racine.sha256"', '  pod_retirer "$n"\n')]
print('OK   ordre de etape_boot_racine : pod, clé, sonde, repomd, rpm -K, contrôle, rapatriement, sha256, retrait' if o == sorted(o) else 'KO   ordre : %s' % o)
apres = c[c.index('pod_demarrer "$n"'):]
nr = [l for l in apres.split('\n') if 'exit 1' in l and 'pod_retirer' not in l]
print(('OK   ' if not nr else 'KO   ') + f'arrêts après pod_demarrer sans pod_retirer : {len(nr)}')
for l in nr: print('     ' + l.strip())
sys.exit(0 if o == sorted(o) and not nr else 1)
PY
VAULT97=$(grep -m1 '^VAULT97=' "$S1N" | cut -d= -f2)
extraire 'dnf97_conf() {' '# Script de boot_racine' "$B/dnf97.sh"
( . "$B/depots97.sh"; . "$B/dnf97.sh"; dnf97_conf ) > "$B/dnf97.conf"
sed 's/^/     /' "$B/dnf97.conf"
egal "dnf97.conf : sections" "$(grep '^\[' "$B/dnf97.conf" | tr '\n' ' ')" "[main] [baseos97] [appstream97] [crb97] [extras97] "
egal "dnf97.conf : baseurl de vault 9.7" "$(grep -c "^baseurl=$VAULT97/\(BaseOS\|AppStream\|CRB\|extras\)/x86_64/os/$" "$B/dnf97.conf")" 4
egal "dnf97.conf : ni mirrorlist ni metalink" "$(grep -c -i 'mirrorlist\|metalink' "$B/dnf97.conf")" 0
egal "dnf97.conf : options de [main]" "$(sed -n '2,7p' "$B/dnf97.conf" | tr '\n' ' ')" "gpgcheck=1 install_weak_deps=0 best=1 keepcache=1 cachedir=/w/cache97 reposdir=/w/aucun "
egal "dnf97.conf : repo_gpgcheck et clé par dépôt" "$(grep -c -e '^repo_gpgcheck=1$' -e '^gpgkey=file:///w/cles/RPM-GPG-KEY-Rocky-9$' "$B/dnf97.conf")" 8
M2=$HOME/.cache/supply-chain-poc/05/m2/mock.tar.gz
egal "archive de mock 6.9-1 (M2)" "$(sha256sum < "$M2" | cut -c1-64)" 3c034916a721bb06b923399c856d5111fbf3d791804934dd6d909e3d292e4d88
tar -xzOf "$M2" mock-mock-6.9-1/mock-core-configs/etc/mock/templates/rocky-9.tpl > "$B/rocky-9.tpl"
egal "rocky-9.tpl : dépôts actifs = DEPOTS97" "$(awk '/^\[/ {s=$0} /^enabled=1$/ {print s}' "$B/rocky-9.tpl" | tr -d '[]' | tr '\n' ' ')" \
  "$(. "$B/depots97.sh"; for n in "${DEPOTS97[@]}"; do printf '%s ' "${n,,}"; done)"
egal "rocky-9.tpl : best et weak deps comme dnf97.conf" "$(grep -c -e '^best=1$' -e '^install_weak_deps=0$' "$B/rocky-9.tpl")" 2
egal "rocky-9.tpl : tsflags absent" "$(grep -c tsflags "$B/rocky-9.tpl")" 0

echo "## G : etape_boot_image contre un registre crane en loopback"
CRANE=$(cd "$D" && mise which crane)
ADR=127.0.0.1:5906
G=$B/g; mkdir -p "$G/t/docker" "$G/racine/usr/bin" "$G/disque"; echo '{}' > "$G/t/docker/config.json"; echo x > "$G/racine/usr/bin/x"
tar --sort=name --format=posix --numeric-owner --mtime=@0 -C "$G/racine" -cf "$G/t/boot-racine.tar" .
sha256sum < "$G/t/boot-racine.tar" | cut -c1-64 > "$G/t/boot-racine.sha256"
echo "     crane $("$CRANE" version)"
if curl -fsS "http://$ADR/v2/" >/dev/null 2>&1; then nok "port $ADR déjà pris"; else
"$CRANE" registry serve --address "$ADR" --disk "$G/disque" > "$G/serve.log" 2>&1 &
srv=$!
for _ in $(seq 30); do curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 && break; sleep 1; done
extraire 'etape_boot_image() {' $'\n}\n' "$G/fonction.sh"; printf '\n}\n' >> "$G/fonction.sh"
g_jouer() { (
  set -euo pipefail
  . "$G/fonction.sh"
  eval "$(grep -m1 '^attendu() {' "$S1N")"
  T=$G/t; REG_HOTE=$ADR; REG=sc-stockage.poc.test:5000; PREFIXE=banc
  eval "$(grep -m1 -e '^DEPOT_DERIVE=' "$S1N" | cut -d' ' -f1)"; eval "$(grep -m1 '^DEPOT_AMONT=' "$S1N")"; eval "$(grep -m1 '^BOOT_DIGEST=' "$S1N" | cut -d' ' -f1)"
  zot() { "$@"; }; crane() { "$CRANE" "$@"; }; auth_zot() { echo "auth_zot appelé (inattendu)"; }
  etape_boot_image
) > "$G/$1.log" 2>&1; }
echo 0000000000000000000000000000000000000000000000000000000000000000 > "$G/t/faux.sha256"
cp "$G/t/boot-racine.sha256" "$G/t/vrai.sha256"; cp "$G/t/faux.sha256" "$G/t/boot-racine.sha256"
g_jouer g2; egal "G2 empreinte fausse : code" "$?" 1
sed 's/^/     /' "$G/g2.log"
egal "G2 arrêt avant crane (KO d'attendu, dépôt absent du catalogue)" "$(grep -c -e '^KO   archive racine dérivée, sha256 égal à celui de boot_racine' "$G/g2.log") $(curl -fsS "http://$ADR/v2/_catalog" | grep -c rocky9-bootstrap)" '1 0'
cp "$G/t/vrai.sha256" "$G/t/boot-racine.sha256"
g_jouer g
egal "G code" "$?" 0
kill $srv 2>/dev/null; wait $srv 2>/dev/null
sed 's/^/     /' "$G/g.log"
egal "G une couche" "$(grep -c '^couche sha256:[0-9a-f]\{64\} [0-9]* octets$' "$G/g.log")" 1
egal "G annotation base.digest" "$(grep -c '^annotation org.opencontainers.image.base.digest = sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2$' "$G/g.log")" 1
egal "G annotation base.name" "$(grep -c '^annotation org.opencontainers.image.base.name = sc-stockage.poc.test:5000/amont/rockylinux/rockylinux$' "$G/g.log")" 1
egal "G plateforme" "$(grep -c '^config : os linux ; architecture amd64$' "$G/g.log")" 1
egal "G digest écrit et affiché" "$(grep -c "^image de bootstrap dérivée : sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@$(cat "$G/t/boot-image.digest")$" "$G/g.log")" 1
egal "G auth_zot non appelé (config docker présente)" "$(grep -c 'auth_zot appelé' "$G/g.log")" 0
fi

echo "## H : etape_boot_racine avec doublures"
extraire 'etape_boot_racine() {' $'\n}\n' "$B/h-fonction.sh"; printf '\n}\n' >> "$B/h-fonction.sh"
extraire 'controle_derivee() {' 'etape_boot_racine() {' "$B/h-controle.sh"
extraire "SONDE_DERIVEE='" 'controle_derivee() {' "$B/h-sonde.sh"
grep -m1 '^attendu() {' "$S1N" > "$B/h-commun.sh"; grep -m1 '^champ() {' "$S1N" >> "$B/h-commun.sh"
h_jouer() { # cas journal archive : etape_boot_racine dans un sous-shell ; sortie $B/h-<cas>.out, code $B/h-<cas>.rc
  ( set -euo pipefail
    . "$B/derivee.sh"; . "$B/depots97.sh"; . "$B/dnf97.sh"; . "$B/h-commun.sh"; . "$B/h-controle.sh"; . "$B/h-sonde.sh"; . "$B/h-fonction.sh"
    T=$B/h/t; P=$B/h; REG=sc-stockage.poc.test:5000; DEPOT_ESSAI=essais-05/mock-rocky9; BOOT=exemple.test/r@sha256:0
    J=$2; A=$3
    pod_spec() { echo "pod_spec $1"; }; pod_demarrer() { echo "pod_demarrer $1"; }; livrer() { echo "livrer $2"; }
    dans() { cat > "$T/sonde-recue.txt"; cp "$J" "$T/$2.log"; echo "     (sonde rejouée depuis ${J##*/})"; }
    kubectl() { cat "$A"; }; pod_retirer() { echo "pod $1 supprimé"; }
    etape_boot_racine
  ) > "$B/h-$1.out" 2>&1; echo $? > "$B/h-$1.rc"; sed 's/^/     /' "$B/h-$1.out"
}
h_init() { rm -rf "$B/h"; mkdir -p "$B/h/t/hote"; echo sha256:1 > "$B/h/t/image.digest"; cp "$B/c1.sha256" "$B/h/t/derivee.sha256"
  echo cle > "$B/h/t/hote/RPM-GPG-KEY-Rocky-9"; : > "$B/h/ca-poc.crt"
  for d in baseos97 appstream97 crb97 extras97; do echo "repomd $d banc" | sha256sum | cut -c1-64 > "$B/h/t/$d.repomd.sha256"; done
  echo ancienne > "$B/h/t/boot-racine.tar"; echo ancienne > "$B/h/t/boot-racine.sha256"; }
h_fin() { # cas code : code, retrait du pod, archive
  egal "$1 code" "$(cat "$B/h-$1.rc")" "$2"
  egal "$1 pod retiré une fois" "$(grep -c '^pod s1-05-boot-racine supprimé$' "$B/h-$1.out")" 1
  if [ "$2" = 0 ]; then egal "$1 archive et sha256 posés, égaux" "$(sha256sum < "$B/h/t/boot-racine.tar" 2>&1 | cut -c1-64) $(test -s "$B/h/t/boot-racine.sha256" && echo posé)" "$(cat "$B/h/t/boot-racine.sha256" 2>&1) posé"
  else egal "$1 aucune archive laissée" "$(ls "$B/h/t/boot-racine.tar" "$B/h/t/boot-racine.sha256" 2>/dev/null | wc -l)" 0; fi
}
echo "### H1 : nominal (journal et archive de D1)"
h_init; h_jouer h1 "$B/d1.log" "$B/d1.tar"; h_fin h1 0
egal "H1 archive = celle de D1" "$(sha256sum < "$B/h/t/boot-racine.tar" | cut -c1-64)" "$(sha256sum < "$B/d1.tar" | cut -c1-64)"
egal "H1 sonde envoyée sans marqueur" "$(grep -c '@[A-Z_]*@' "$B/h/t/sonde-recue.txt")" 0
egal "H1 paquets dans la sonde envoyée" "$(grep -c -- "install $P > " "$B/h/t/sonde-recue.txt")" 1
egal "H1 dnf97.conf livré et posé" "$(grep -c '^livrer /w/dnf97.conf$' "$B/h-h1.out") $(grep -c '^\[extras97\]$' "$B/h/t/dnf97.conf")" "1 1"
echo "### H2 : repomd de crb97 différent"
h_init; echo 0 > "$B/h/t/crb97.repomd.sha256"; h_jouer h2 "$B/d1.log" "$B/d1.tar"; h_fin h2 1
egal "H2 KO du repomd" "$(grep -c '^KO   repomd crb97 lu par dnf dans le pod = repomd vérifié sur l.hôte' "$B/h-h2.out")" 1
echo "### H3 : un rpm en trop (journal de D5, rpm -K ramené à 10 pour atteindre le contrôle)"
sed 's/^rpm -K : 11 OK sur 11$/rpm -K : 10 OK sur 10/' "$B/d5.log" > "$B/h3.log"
h_init; h_jouer h3 "$B/h3.log" "$B/d5.tar"; h_fin h3 1
egal "H3 contrôle en écart" "$(grep -c -e 'écart : non épinglé : intrus-1-1.el9.noarch.rpm' -e '^KO   rpm téléchargés différents des dix épinglés' "$B/h-h3.out")" 2
echo "### H3b : rpm -K à 11 sur 11 (journal de D5 brut)"
h_init; h_jouer h3b "$B/d5.log" "$B/d5.tar"; h_fin h3b 1
echo "### H4 : ligne d'archive absente"
grep -v '^archive racine dérivée : ' "$B/d1.log" > "$B/h4.log"
h_init; h_jouer h4 "$B/h4.log" "$B/d1.tar"; h_fin h4 1
egal "H4 KO archive absente" "$(grep -c '^KO   archive racine dérivée absente$' "$B/h-h4.out")" 1
echo "### H5 : archive rapatriée corrompue (celle de D5 pour le journal de D1)"
h_init; h_jouer h5 "$B/d1.log" "$B/d5.tar"; h_fin h5 1
egal "H5 KO du sha256" "$(grep -c '^KO   archive racine dérivée rapatriée' "$B/h-h5.out")" 1

echo "## I : commandes de la sonde dans l'image d'essai (racine.tar)"
RT=$HOME/.cache/supply-chain-poc/08/travail/s1-05/racine.tar
egal "sha256 de racine.tar (étape racine)" "$(sha256sum < "$RT" | cut -c1-64)" d7433a050469836de7317de87f2421d3bc7eaa52052cf422518809e276a94a9d
tar -tf "$RT" > "$B/racine-liste.txt"
m=""; for c in dnf-3 rpm podman cp du ls sort wc comm sed grep find sha256sum tar stat df awk cut tr mkdir rm head tail date sh; do
  grep -q -x "./usr/bin/$c" "$B/racine-liste.txt" || m="$m $c"; done
egal "commandes absentes de /usr/bin" "${m:-aucune}" aucune
egal "/usr/bin/dnf absent (raison de dnf-3)" "$(grep -c -x './usr/bin/dnf' "$B/racine-liste.txt")" 0
if [ $ko = 0 ]; then echo "# bilan : tenu, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; else echo "# bilan : NON TENU, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
exit $ko
