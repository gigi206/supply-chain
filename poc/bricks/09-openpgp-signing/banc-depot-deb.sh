#!/usr/bin/env bash
# Brique 09, banc O0 : dépôt apt signé sur l'hôte, autour d'une copie locale du deb D, SANS RIEN INSTALLER.
# Outils déjà présents sur l'hôte : gpg et gpgv (toujours avec un --homedir neuf), apt-ftparchive, gzip, python3 -I.
# Ne touche ni au cluster, ni à Zot, ni aux dossiers des briques 05, 06 et 08 (lecture seule de deux copies locales).
# Usage : banc-depot-deb.sh prealables | banc
#   prealables : versions des outils, copies locales contre les journaux archivés, .changes de S3 (taille et sha256 seulement).
#   banc       : clé jetable, dépôt, Release, Release.gpg, InRelease, vérifications et témoins.
# Journaux : resultats/banc-depot-deb-prealables.log, resultats/banc-depot-deb.log. Code 0 si toutes les attentes tiennent.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
J06=$here/../06-deb-sbuild/resultats/s3-comparaison.log
J05=$here/../05-rpm-mock/resultats/m4c-comparaison.log
BASE=$HOME/.cache/supply-chain-poc/09
DEB_SRC=$HOME/.cache/supply-chain-poc/08/travail/s3-06/build-1/sample-app_1.0.0-2_amd64.deb
CHANGES_SRC=$HOME/.cache/supply-chain-poc/08/travail/s3-06/build-1/sample-app_1.0.0-2_amd64.changes
RPM_A=$HOME/.cache/supply-chain-poc/05/banc-m4c-comparaison-copie/m3/sample-app-1.0.0-2.el9.x86_64.rpm
RPM_B=$HOME/.cache/supply-chain-poc/05/banc-m3-2-1/T/m3/build-1/sample-app-1.0.0-2.el9.x86_64.rpm
SDE=1763337600   # SOURCE_DATE_EPOCH du relevé de reproductibilité de Release (valeur arbitraire, fixe)
mkdir -p "$BASE" "$R"
cd "$BASE"

masquer() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<adresse retirée>/g'; }
attendu_deb() { grep -oE 'deb identiques sur les deux builds : [0-9a-f]{64}' "$J06" | grep -oE '[0-9a-f]{64}$'; }
attendu_rpm() { grep -oE 'rpm de M3 \(build 1\) : [0-9a-f]{64}' "$J05" | grep -oE '[0-9a-f]{64}$'; }

OK=0; ECART=0
ok() { OK=$((OK + 1)); echo "OK     $*"; }
ecart() { ECART=$((ECART + 1)); echo "ÉCART  $*"; }

prealables() {
  set +e
  echo "prealables commencée : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "gpg : $(gpg --version | head -1) ; gpgv : $(gpgv --version | head -1)"
  echo "apt-ftparchive : $(apt-ftparchive --version 2>&1 | head -1)"
  echo "dpkg-deb : $(dpkg-deb --version | head -1)"
  echo "python3 (répertoire courant $BASE) : $(command -v python3) $(python3 -I -c 'import sys; print(sys.version.split()[0])')"
  echo "paquets de l'hôte (dpkg-query, lecture seule) :"
  dpkg-query -W -f='  ${Package} ${Version}\n' gnupg gpg gpgv gpg-agent apt apt-utils dpkg gzip 2>&1
  echo "outils absents attendus :"
  for b in rpm rpmsign rpmkeys createrepo_c debsign sqv sq softhsm2-util gnupg-pkcs11-scd; do
    printf '  %s : %s\n' "$b" "$(command -v "$b" || echo absent)"
  done
  ed=$(attendu_deb); er=$(attendu_rpm)
  echo "attendu deb (s3-comparaison.log) : $ed"
  echo "attendu rpm (m4c-comparaison.log) : $er"
  s=$(sha256sum "$DEB_SRC" | cut -c1-64)
  [ -n "$ed" ] && [ "$s" = "$ed" ] && ok "copie locale du deb égale au journal : $s ($(stat -c %s "$DEB_SRC") octets)" || ecart "copie locale du deb : $s, attendu $ed"
  s=$(sha256sum "$RPM_A" | cut -c1-64)
  [ -n "$er" ] && [ "$s" = "$er" ] && ok "copie rpm banc-m4c-comparaison-copie/m3 égale au journal : $s" || ecart "copie rpm A : $s, attendu $er"
  s=$(sha256sum "$RPM_B" | cut -c1-64)
  [ "$s" != "$er" ] && ok "copie rpm banc-m3-2-1 différente du journal (garde nécessaire) : $s" || ecart "copie rpm B égale au journal, non attendu"
  if [ -f "$CHANGES_SRC" ]; then
    ok ".changes de S3 présent : $(stat -c %s "$CHANGES_SRC") octets, sha256 $(sha256sum "$CHANGES_SRC" | cut -c1-64), lignes portant le sha256 du deb : $(grep -c "$ed" "$CHANGES_SRC")"
  else
    ecart ".changes de S3 absent"
  fi
  echo "bilan prealables : $OK OK, $ECART ÉCART ; finie : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  [ "$ECART" = 0 ]
}

# chaine RELEASE DISTS DEPOT ATTENDU [PACKAGES_REMPLACANT] [DEB_REMPLACANT] : Release → Packages → deb ; code 0 si la chaîne tient.
chaine() {
  python3 -I - "$@" <<'PY'
import hashlib, os, sys
release, dists, depot, attendu = sys.argv[1:5]
pk_force = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None
deb_force = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] else None
def h(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest(), os.path.getsize(p)
champs, section = {}, None
for l in open(release, encoding="utf-8").read().splitlines():
    if l.startswith(" ") and section == "SHA256":
        s, n, f = l.split()
        champs[f] = (s, int(n))
    elif not l.startswith(" "):
        section = l.split(":")[0]
erreurs = 0
for f in ("main/binary-amd64/Packages", "main/binary-amd64/Packages.gz"):
    p = pk_force if (pk_force and f.endswith("Packages")) else os.path.join(dists, f)
    if f not in champs:
        print(f"  {f} absent de Release"); erreurs += 1; continue
    if h(p) == champs[f]:
        print(f"  {f} : sha256 et taille égaux à Release ({champs[f][0][:16]}…, {champs[f][1]} octets)")
    else:
        print(f"  {f} : DIFFÉRENT de Release (lu {h(p)[0][:16]}…, Release {champs[f][0][:16]}…)"); erreurs += 1
pk = pk_force or os.path.join(dists, "main/binary-amd64/Packages")
strophes = [s for s in open(pk, encoding="utf-8").read().split("\n\n") if s.strip()]
print(f"  Packages : {len(strophes)} strophe(s)")
for s in strophes:
    d = dict(l.split(": ", 1) for l in s.splitlines() if ": " in l and not l.startswith(" "))
    if d.get("Package") != "sample-app": continue
    print(f"  strophe : {d.get('Package')} {d.get('Version')} {d.get('Architecture')} Size {d.get('Size')} Filename {d.get('Filename')} SHA256 {d.get('SHA256')}")
    if d.get("SHA256") != attendu:
        print("  SHA256 de la strophe différent du journal"); erreurs += 1
    deb = deb_force or os.path.join(depot, d["Filename"])
    s2, n2 = h(deb)
    if s2 == d.get("SHA256") and str(n2) == d.get("Size"):
        print(f"  fichier {os.path.basename(deb)} : sha256 et taille égaux à la strophe")
    else:
        print(f"  fichier {os.path.basename(deb)} : DIFFÉRENT de la strophe ({s2[:16]}…, {n2} octets)"); erreurs += 1
sys.exit(1 if erreurs else 0)
PY
}

banc() {
  set +e
  TS=$(date -u '+%Y%m%dT%H%M%SZ')
  W=$BASE/banc-depot-deb-$TS
  G=$W/gnupg
  echo "banc commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; dossier neuf $W ; --homedir $G"
  mkdir "$W" && mkdir -m 700 "$G" && mkdir -p "$W/depot/pool/main/s/sample-app" "$W/depot/dists/poc/main/binary-amd64" "$W/temoins" || { ecart "dossiers"; return 1; }
  ed=$(attendu_deb)
  DEB=$W/depot/pool/main/s/sample-app/sample-app_1.0.0-2_amd64.deb
  cp "$DEB_SRC" "$DEB"
  s=$(sha256sum "$DEB" | cut -c1-64)
  if [ -n "$ed" ] && [ "$s" = "$ed" ]; then ok "BD1 garde : copie égale au journal ($s)"; else ecart "BD1 garde : $s, attendu $ed ; arrêt"; return 1; fi

  echo; echo "## Clés jetables (identité fictive, sans adresse, sans phrase de passe, aucun secret en argument)"
  for nom in "Banc 09 PoC cle jetable" "Banc 09 PoC autre cle"; do
    printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 4096' 'Key-Usage: sign' "Name-Real: $nom" 'Expire-Date: 2d' '%commit' > "$W/cle.params"
    gpg --homedir "$G" --batch --quiet --gen-key "$W/cle.params" 2>&1 | grep -v -i 'revocation\|révocation' | sed 's/^/  /'
  done
  F1=$(gpg --homedir "$G" --batch --with-colons --list-keys "Banc 09 PoC cle jetable" | awk -F: '$1=="fpr"{print $10; exit}')
  F2=$(gpg --homedir "$G" --batch --with-colons --list-keys "Banc 09 PoC autre cle" | awk -F: '$1=="fpr"{print $10; exit}')
  gpg --homedir "$G" --batch --with-colons --list-keys | awk -F: '$1=="pub"{print "  pub algo " $4 " bits " $3 " expire " strftime("%Y-%m-%d", $7, 1) " usage " $12}'
  [ -n "$F1" ] && [ -n "$F2" ] && [ "$F1" != "$F2" ] && ok "BD2 deux clés RSA créées : $F1 (signataire), $F2 (témoin)" || { ecart "BD2 clés"; return 1; }
  gpg --homedir "$G" --batch --export "$F1" > "$W/cle1.pub.gpg"
  gpg --homedir "$G" --batch --export "$F2" > "$W/cle2.pub.gpg"
  echo "  clés publiques exportées en binaire (non affichées) : cle1.pub.gpg $(stat -c %s "$W/cle1.pub.gpg") octets, cle2.pub.gpg $(stat -c %s "$W/cle2.pub.gpg") octets"

  echo; echo "## Dépôt : Packages, Packages.gz, Release"
  ( cd "$W/depot" && apt-ftparchive packages pool > dists/poc/main/binary-amd64/Packages ) || ecart "apt-ftparchive packages"
  gzip -9 -n -k "$W/depot/dists/poc/main/binary-amd64/Packages"
  sed 's/^/  | /' "$W/depot/dists/poc/main/binary-amd64/Packages" | masquer
  OPTS=(-o APT::FTPArchive::Release::Origin=poc -o APT::FTPArchive::Release::Label=poc -o APT::FTPArchive::Release::Suite=poc
        -o APT::FTPArchive::Release::Codename=poc -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main)
  ( cd "$W/depot" && SOURCE_DATE_EPOCH=$SDE apt-ftparchive "${OPTS[@]}" release dists/poc > "$W/Release.1" && SOURCE_DATE_EPOCH=$SDE apt-ftparchive "${OPTS[@]}" release dists/poc > "$W/Release.2" )
  cp "$W/Release.1" "$W/depot/dists/poc/Release"
  sed 's/^/  | /' "$W/depot/dists/poc/Release"
  echo "  BD5 (relevé, non prédit) : Date de Release « $(grep '^Date:' "$W/Release.1" | cut -c7-) » ; SOURCE_DATE_EPOCH=$SDE vaut « $(LC_ALL=C date -u -d "@$SDE" '+%a, %d %b %Y %H:%M:%S UTC') » ; deux sorties identiques : $(cmp -s "$W/Release.1" "$W/Release.2" && echo oui || echo non)"
  chaine "$W/depot/dists/poc/Release" "$W/depot/dists/poc" "$W/depot" "$ed" && ok "BD3 et BD4 : strophe et empreintes de Release conformes" || ecart "BD3 ou BD4"

  echo; echo "## Signature (clé $F1, SHA-512)"
  gpg --homedir "$G" --batch --yes --quiet --local-user "$F1" --digest-algo SHA512 --detach-sign -o "$W/depot/dists/poc/Release.gpg" "$W/depot/dists/poc/Release"
  gpg --homedir "$G" --batch --yes --quiet --local-user "$F1" --digest-algo SHA512 --clearsign -o "$W/depot/dists/poc/InRelease" "$W/depot/dists/poc/Release"
  echo "  Release.gpg $(stat -c %s "$W/depot/dists/poc/Release.gpg") octets ; InRelease $(stat -c %s "$W/depot/dists/poc/InRelease") octets"

  echo; echo "## Vérification par gpgv (homedir dédié, trousseau de la seule clé signataire)"
  gpgv --homedir "$G" --keyring "$W/cle1.pub.gpg" "$W/depot/dists/poc/Release.gpg" "$W/depot/dists/poc/Release" > "$W/v1.txt" 2>&1; rc=$?
  sed 's/^/  /' "$W/v1.txt"
  [ "$rc" = 0 ] && grep -q "$F1" "$W/v1.txt" && ok "BD6 Release.gpg vérifié (code 0, empreinte $F1)" || ecart "BD6 Release.gpg : code $rc"
  gpgv --homedir "$G" --keyring "$W/cle1.pub.gpg" --output "$W/InRelease.sortie" "$W/depot/dists/poc/InRelease" > "$W/v2.txt" 2>&1; rc=$?
  sed 's/^/  /' "$W/v2.txt"
  if [ "$rc" = 0 ] && cmp -s "$W/InRelease.sortie" "$W/depot/dists/poc/Release"; then ok "BD7 InRelease vérifié, texte sorti égal à Release octet pour octet"; else ecart "BD7 InRelease : code $rc, texte sorti égal à Release : $(cmp -s "$W/InRelease.sortie" "$W/depot/dists/poc/Release" && echo oui || echo non)"; fi
  gpg --homedir "$G" --batch --list-packets "$W/depot/dists/poc/Release.gpg" 2>/dev/null | grep -E 'signature packet|digest algo|version' | sed 's/^/  /'
  p=$(gpg --homedir "$G" --batch --list-packets "$W/depot/dists/poc/Release.gpg" 2>/dev/null)
  echo "$p" | grep -q 'algo 1,' && echo "$p" | grep -q 'version 4' && echo "$p" | grep -q 'digest algo 10' && ok "BD8 signature v4, RSA (algo 1), SHA-512 (digest algo 10)" || ecart "BD8 paquets de signature"
  chaine "$W/InRelease.sortie" "$W/depot/dists/poc" "$W/depot" "$ed" && ok "BD9 chaîne tenue depuis le texte sorti de la vérification d'InRelease" || ecart "BD9"

  echo; echo "## Témoins (copies sous temoins/)"
  T=$W/temoins
  python3 -I - "$W/depot/dists/poc/Release" "$T/Release.altere" <<'PY'
import sys
t = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(t.replace(b"Codename: poc", b"Codename: pod", 1))
PY
  gpgv --homedir "$G" --keyring "$W/cle1.pub.gpg" "$W/depot/dists/poc/Release.gpg" "$T/Release.altere" > "$T/n1.txt" 2>&1; rc=$?
  [ "$rc" != 0 ] && ok "BD10 N1 Release altéré refusé par gpgv (code $rc)" || ecart "BD10 N1 accepté"
  python3 -I - "$W/depot/dists/poc/InRelease" "$T/InRelease.altere" <<'PY'
import sys
t = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(t.replace(b"Codename: poc", b"Codename: pod", 1))
PY
  gpgv --homedir "$G" --keyring "$W/cle1.pub.gpg" --output "$T/n2.sortie" "$T/InRelease.altere" > "$T/n2.txt" 2>&1; rc=$?
  [ "$rc" != 0 ] && ok "BD10 N2 InRelease altéré refusé par gpgv (code $rc)" || ecart "BD10 N2 accepté"
  gpgv --homedir "$G" --keyring "$W/cle2.pub.gpg" "$W/depot/dists/poc/Release.gpg" "$W/depot/dists/poc/Release" > "$T/n3.txt" 2>&1; rc=$?
  [ "$rc" != 0 ] && ok "BD10 N3 clé étrangère : refusé par gpgv (code $rc)" || ecart "BD10 N3 accepté"
  python3 -I - "$W/depot/dists/poc/main/binary-amd64/Packages" "$T/Packages.altere" <<'PY'
import sys
t = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(t.replace(b"Package: sample-app", b"Package: sample-app\nX-Ajout: oui", 1))
PY
  chaine "$W/depot/dists/poc/Release" "$W/depot/dists/poc" "$W/depot" "$ed" "$T/Packages.altere" > "$T/n4.txt" 2>&1; rc=$?
  sed 's/^/  /' "$T/n4.txt"
  [ "$rc" != 0 ] && ok "BD10 N4 Packages altéré : écart détecté par la chaîne" || ecart "BD10 N4 non détecté"
  cp "$DEB" "$T/sample-app_1.0.0-2_amd64.deb"; printf 'x' >> "$T/sample-app_1.0.0-2_amd64.deb"
  chaine "$W/depot/dists/poc/Release" "$W/depot/dists/poc" "$W/depot" "$ed" "" "$T/sample-app_1.0.0-2_amd64.deb" > "$T/n5.txt" 2>&1; rc=$?
  sed 's/^/  /' "$T/n5.txt"
  [ "$rc" != 0 ] && ok "BD10 N5 deb altéré : écart détecté par la chaîne" || ecart "BD10 N5 non détecté"

  echo; echo "## Limite L1 : signature SHA-1 jugée par gpgv 2.4.8 (apt de trixie suit default-sequoia.config, non mesuré ici)"
  gpg --homedir "$G" --batch --yes --quiet --local-user "$F1" --digest-algo SHA1 --detach-sign -o "$T/Release.sha1.gpg" "$W/depot/dists/poc/Release" 2>&1 | sed 's/^/  /'
  gpgv --homedir "$G" --keyring "$W/cle1.pub.gpg" "$T/Release.sha1.gpg" "$W/depot/dists/poc/Release" > "$T/l1.txt" 2>&1; rc=$?
  sed 's/^/  /' "$T/l1.txt"
  [ "$rc" = 0 ] && ok "BD11 gpgv 2.4.8 accepte une signature SHA-1 (code 0) : gpgv ne reflète pas la politique d'apt" || ecart "BD11 gpgv refuse SHA-1 (code $rc)"

  echo; echo "## Fin"
  s=$(sha256sum "$DEB" | cut -c1-64)
  [ "$s" = "$ed" ] && ok "BD12 deb du dépôt inchangé : $s" || ecart "BD12 deb modifié : $s"
  gpgconf --homedir "$G" --kill all 2>/dev/null
  echo "bilan banc : $OK OK, $ECART ÉCART ; fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  [ "$ECART" = 0 ]
}

case "${1:-}" in
  prealables) prealables 2>&1 | masquer | tee "$R/banc-depot-deb-prealables.log"; exit "${PIPESTATUS[0]}" ;;
  banc)       banc 2>&1 | masquer | tee "$R/banc-depot-deb.log"; exit "${PIPESTATUS[0]}" ;;
  *) echo "usage : $0 prealables | banc" >&2; exit 64 ;;
esac
