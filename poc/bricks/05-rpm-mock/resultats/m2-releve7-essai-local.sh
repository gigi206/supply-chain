#!/usr/bin/env bash
# Essai hors réseau de releve7 (m2.sh), écrit le 12/11/2026 à partir de 17:46:28 UTC, avant tout passage. commun.sh remplacé
# par un lancer() qui appelle etape_<nom> ; HOME isolé ; s1.sh copié avec FP_ROCKY remplacé par l'empreinte d'une clé d'essai
# jetable (gpg, sans phrase de passe, effacée à la fin) ; m2.sh copié avec ARCHIVE_SHA remplacé par celle d'une archive
# synthétique (rocky-9.tpl réduit à chroot_setup_cmd) ; curl simulé : chaque URL est servie depuis un dossier de pages, 404
# sinon. gpg et gpgv sont les vrais. Cas : nominal, extras absent de vault, signature d'extras fausse, primary différent de
# repomd.xml, croisement non vide (par nom et par provides), mirrorlist en HTTP 500, empreinte de clé différente, deux dossiers
# extras à la casse près. Le primary de pub/rocky/9/extras est compressé en .xz, les autres en .gz.
# python3 du banc : l'interpréteur réel, lié dans bin/ avant le changement de HOME (sans quoi le relais de mise ne trouve
# plus sa configuration approuvée).
# Non couvert : vrais formats de la réponse du mirrorlist, de la liste HTML et des repomd de Rocky ; redirections ; réseau ;
# curl lui-même en échec ; un code HTTP autre que 200 et 404 sur le repomd d'un extras ; BaseOS, AppStream ou CRB absent ;
# primary en .bz2 ; le vrai lancer (sous-shell d'un tube, journal, chrono.tsv).
# Usage : m2-releve7-essai-local.sh <racine du dépôt> <dossier vidé>
set -u
D=$1; H=$2
rm -rf -- "${H:?}"
mkdir -p "$H/bin" "$H/home/.cache/supply-chain-poc/05/m2" "$H/b/resultats" "$H/arch/x/mock-core-configs/etc/mock/templates"
mkdir -m 700 "$H/gk"; export GNUPGHOME=$H/gk H
G=(gpg --batch --quiet --pinentry-mode loopback --passphrase '')
"${G[@]}" --quick-gen-key 'essai <essai@essai.test>' ed25519 sign never 2>/dev/null
"${G[@]}" --quick-gen-key 'autre <autre@essai.test>' ed25519 sign never 2>/dev/null
FP=$(gpg --batch --with-colons --list-keys 'essai@essai.test' 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
FA=$(gpg --batch --with-colons --list-keys 'autre@essai.test' 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
gpg --batch --armor --export "$FP" > "$H/cle.asc"; gpg --batch --armor --export "$FA" > "$H/autre.asc"
echo "clés d'essai : $(printf '%s\n' "$FP" "$FA" | grep -c -E '^[0-9A-F]{40}$') empreintes de 40 caractères"

echo "config_opts['chroot_setup_cmd'] = 'install bash which xz'" > "$H/arch/x/mock-core-configs/etc/mock/templates/rocky-9.tpl"
tar -czf "$H/home/.cache/supply-chain-poc/05/m2/mock.tar.gz" -C "$H/arch" x
SHA=$(sha256sum < "$H/home/.cache/supply-chain-poc/05/m2/mock.tar.gz" | cut -c1-64)
printf 'R=%s\nlancer() { "etape_$3"; }\n' "$H/b/resultats" > "$H/commun.sh"
sed -e "s#^\. \"\$here/../08-trust-plane/commun.sh\"\$#. $H/commun.sh#" -e "s#^ARCHIVE_SHA=[0-9a-f]\{64\} #ARCHIVE_SHA=$SHA #" \
  "$D/poc/bricks/05-rpm-mock/m2.sh" > "$H/b/m2.sh"
sed -e "s#^FP_ROCKY=[0-9A-F]\{40\} #FP_ROCKY=$FP #" "$D/poc/bricks/05-rpm-mock/s1.sh" > "$H/b/s1.sh"
grep -c "^\. $H/commun.sh\$" "$H/b/m2.sh" | sed 's/^/source remplacée : /'
grep -c "^ARCHIVE_SHA=$SHA " "$H/b/m2.sh" | sed 's/^/ARCHIVE_SHA d essai : /'
grep -c "^FP_ROCKY=$FP " "$H/b/s1.sh" | sed 's/^/FP_ROCKY d essai : /'
V=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$H/b/s1.sh")
CLE=$(sed -n 's|^CLE_ROCKY=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$H/b/s1.sh")
ML='https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=extras-9'

cat > "$H/bin/curl" <<'EOF2'
#!/usr/bin/env bash
o=/dev/stdout; w=; u=${*: -1}
while [ $# -gt 0 ]; do case $1 in -o) o=$2; shift ;; -w) w=$2; shift ;; esac; shift; done
f=$H/web/$(printf %s "$u" | sha256sum | cut -c1-16)
if [ "$CAS" = mirrorlist ] && [ "${u%%\?*}" = https://mirrors.rockylinux.org/mirrorlist ]; then c=500; echo erreur > "$o"
elif [ -f "$f" ]; then c=200; cp "$f" "$o"
else c=404; echo absent > "$o"; fi
[ -n "$w" ] && printf '%s' "$c"; exit 0
EOF2
chmod +x "$H/bin/curl"
ln -s "$(python3 -I -c 'import sys; print(sys.executable)')" "$H/bin/python3"

servir() { cp "$2" "$H/web/$(printf %s "$1" | sha256sum | cut -c1-16)"; }
depot() { # étiquette URL-de-base « nom version release provides… »… ; FAUX_SHA=1 : somme fausse ; FAUSSE_SIG=1 : autre contenu signé
  local b=$2 r=$H/depots/$1 href; shift 2
  mkdir -p "$r"
  href=$(python3 -I - "$r" "$@" <<'PY'
import gzip, hashlib, lzma, os, sys
o, pk = sys.argv[1], [s.split() for s in sys.argv[2:]]
x = ['<?xml version="1.0" encoding="UTF-8"?>',
     f'<metadata xmlns="http://linux.duke.edu/metadata/common" xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="{len(pk)}">']
for nom, ver, rel, *prov in pk:
    e = ''.join(f'<rpm:entry name="{p}"/>' for p in [nom] + prov)
    x.append(f'<package type="rpm"><name>{nom}</name><arch>x86_64</arch><version epoch="0" ver="{ver}" rel="{rel}"/>'
             f'<format><rpm:provides>{e}</rpm:provides></format></package>')
x.append('</metadata>')
z = os.environ.get('FORMAT', 'gz')
b = (lzma.compress if z == 'xz' else gzip.compress)('\n'.join(x).encode())
with open(f'{o}/primary.xml.{z}', 'wb') as f:
    f.write(b)
h = '0' * 64 if os.environ.get('FAUX_SHA') else hashlib.sha256(b).hexdigest()
href = f'repodata/{h[:8]}-primary.xml.{z}'
with open(f'{o}/repomd.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<repomd xmlns="http://linux.duke.edu/metadata/repo"><data type="primary">'
            f'<checksum type="sha256">{h}</checksum><location href="{href}"/></data></repomd>\n')
print(href)
PY
  )
  if [ -n "${FAUSSE_SIG:-}" ]; then echo autre > "$r/autre"; "${G[@]}" -u "$FP" --armor --detach-sign -o "$r/repomd.xml.asc" "$r/autre"
  else "${G[@]}" -u "$FP" --armor --detach-sign -o "$r/repomd.xml.asc" "$r/repomd.xml"; fi
  servir "$b/repodata/repomd.xml" "$r/repomd.xml"; servir "$b/repodata/repomd.xml.asc" "$r/repomd.xml.asc"
  servir "$b/$href" "$r/primary.xml.${FORMAT:-gz}"
}
monter() { # cas : pages servies pour ce cas
  local x dossiers='BaseOS/ AppStream/ CRB/ extras/ devel/'
  rm -rf -- "${H:?}/web" "${H:?}/depots"; mkdir -p "$H/web" "$H/depots"
  if [ "$1" = cle ]; then servir "$CLE" "$H/autre.asc"; else servir "$CLE" "$H/cle.asc"; fi
  printf '# repo = extras-9 arch = x86_64 country = ZZ\nhttps://m1.essai.test/pub/rocky/9.8/extras/x86_64/os/\nhttps://m2.essai.test/rocky/9.8/extras/x86_64/os/\nhttps://m3.essai.test/autre/\n' > "$H/ml"
  servir "$ML" "$H/ml"
  case $1 in absent) dossiers='BaseOS/ AppStream/ CRB/ devel/' ;; deux) dossiers="$dossiers Extras/" ;; esac
  for x in $dossiers; do printf '<a href="%s">%s</a>\n' "$x" "$x"; done > "$H/vault.html"
  servir "$V/" "$H/vault.html"
  depot vault-BaseOS "$V/BaseOS/x86_64/os" 'bash 5.1.8 9.el9' 'coreutils 8.32 36.el9' 'which 2.21 29.el9'
  depot vault-AppStream "$V/AppStream/x86_64/os" 'rpm-build 4.16.1.3 39.el9'
  depot vault-CRB "$V/CRB/x86_64/os" 'libfoo-devel 1.0 1.el9'
  case $1 in
    absent) ;;
    croisement) depot vault-extras "$V/extras/x86_64/os" 'epel-release 9 10.el9' 'which 2.21 30.el9' 'faux-xz 1 1.el9 xz' ;;
    signature) FAUSSE_SIG=1 depot vault-extras "$V/extras/x86_64/os" 'epel-release 9 10.el9' ;;
    primary) FAUX_SHA=1 depot vault-extras "$V/extras/x86_64/os" 'epel-release 9 10.el9' ;;
    *) depot vault-extras "$V/extras/x86_64/os" 'epel-release 9 10.el9' 'rocky-release-kernel 9.7 1.el9' ;;
  esac
  FORMAT=xz depot pub9-extras https://dl.rockylinux.org/pub/rocky/9/extras/x86_64/os 'epel-release 9 10.el9' 'elrepo-release 9.8 1.el9'
}
cas() {
  echo "== cas $1"
  monter "$1"
  CAS=$1 HOME=$H/home PATH=$H/bin:$PATH bash "$H/b/m2.sh" releve7 2>&1 | sed -e "s#$H#<essai>#g" -e "s#$FP#<empreinte d essai>#g" -e "s#$FA#<autre empreinte>#g"
  echo "code ${PIPESTATUS[0]}"
}
for c in nominal absent signature primary croisement mirrorlist cle deux; do cas $c; done
gpgconf --kill all 2>/dev/null || true
rm -rf -- "${H:?}"
