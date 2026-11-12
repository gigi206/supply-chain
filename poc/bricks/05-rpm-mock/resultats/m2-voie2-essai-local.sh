#!/usr/bin/env bash
# Essai hors réseau du cœur de la voie 2 de m2.sh (voie2_preparer sur l'hôte, VOIE2 dans un faux pod), écrit le 12/11/2026 à
# partir de 16:34:20 UTC, avant tout branchement. commun.sh remplacé par un lancer() qui appelle la fonction nommée (le vrai
# n'appelle que des etape_*) ; HOME isolé ; s1.sh copié avec un BOOT_DIGEST d'essai, sha256 d'un faux manifeste ; curl, rpm,
# createrepo_c et skopeo simulés. Cas hôte : nominal, version, pull_digest, bootstrap_image, champ manquant, sigmd5 mal formé,
# URL hors des dépôts, nom refusé, remontée par « .. » sous le préfixe, doublon, verrou vide. Le script du pod est lu sur
# l'entrée standard (sh -s), comme le fera kubectl exec. Cas pod : nominal, HTTP 404, fichier manquant, signature, en-tête
# différent, createrepo_c en échec, manifeste différent.
# Non couvert : sorties réelles de rpm -K, rpm -qp, createrepo_c et skopeo dans l'image ; format réel de sigmd5 dans un verrou
# de mock ; réseau, Zot, sortie du pod ; absence d'un outil (command -v), puisque l'hôte n'a ni rpm, ni createrepo_c, ni skopeo.
set -u
D=$1; H=$2   # D : racine du dépôt ; H : dossier d'essai (vidé)
rm -rf -- "${H:?}"; mkdir -p "$H/bin" "$H/home" "$H/b/resultats" "$H/w/cles"
MANIFESTE='faux manifeste d essai'
BD=sha256:$(printf '%s\n' "$MANIFESTE" | sha256sum | cut -c1-64)
V97=https://dl.rockylinux.org/vault/rocky/9.7
printf 'R=%s\nREG=sc-stockage.poc.test:5000\nlancer() { "${@:3}"; }\n' "$H/b/resultats" > "$H/commun.sh"
sed -e "s#^\. \"\$here/../08-trust-plane/commun.sh\"\$#. $H/commun.sh#" "$D/poc/bricks/05-rpm-mock/m2.sh" > "$H/b/m2.sh"
sed -e "s#^BOOT_DIGEST=sha256:[0-9a-f]\{64\} #BOOT_DIGEST=$BD #" "$D/poc/bricks/05-rpm-mock/s1.sh" > "$H/b/s1.sh"
grep -c "^\. $H/commun.sh\$" "$H/b/m2.sh" | sed 's/^/source remplacée : /'
grep -c "^BOOT_DIGEST=$BD " "$H/b/s1.sh" | sed 's/^/BOOT_DIGEST d essai : /'
echo 'clé d essai' > "$H/w/cles/RPM-GPG-KEY-Rocky-9"

M1=0123456789abcdef0123456789abcdef; M2=fedcba9876543210fedcba9876543210
jq -n --arg bd "$BD" --arg v "$V97" --arg m1 $M1 --arg m2 $M2 '{version: "1.1.0",
  config: {bootstrap_image: ("sc-stockage.poc.test:5000/amont/rockylinux/rockylinux@" + $bd)},
  bootstrap: {pull_digest: $bd, image_digest: "sha256:autre", architecture: "amd64"},
  buildroot: {rpms: [
    {name: "bash", version: "5.1.8", release: "9.el9", arch: "x86_64", epoch: null, sigmd5: $m1, signature: "x",
     url: ($v + "/BaseOS/x86_64/os/Packages/b/bash-5.1.8-9.el9.x86_64.rpm")},
    {name: "libstdc++", version: "11.5.0", release: "5.el9_5", arch: "x86_64", epoch: null, sigmd5: $m2, signature: "x",
     url: ($v + "/AppStream/x86_64/os/Packages/l/libstdc++-11.5.0-5.el9_5.x86_64.rpm")}]}}' > "$H/verrou.json"
printf 'bash-5.1.8-9.el9.x86_64.rpm\tbash\t5.1.8\t9.el9\tx86_64\t%s\nlibstdc++-11.5.0-5.el9_5.x86_64.rpm\tlibstdc++\t11.5.0\t5.el9_5\tx86_64\t%s\n' \
  $M1 $M2 > "$H/entetes.tsv"

cat > "$H/bin/curl" <<'EOF2'
#!/usr/bin/env bash
o=/dev/stdout; w=; u=${*: -1}
while [ $# -gt 0 ]; do case $1 in -o) o=$2; shift ;; -w) w=$2; shift ;; esac; shift; done
echo "$u" >> "$H/curl.urls"; c=200
case "$CAS:$u" in 404:*libstdc*) c=404 ;; esac
case "$CAS:$u" in compte:*libstdc*) ;; *) echo "faux rpm" > "$o" ;; esac
[ -n "$w" ] && printf '%s' "$c"; exit 0
EOF2
cat > "$H/bin/rpm" <<'EOF2'
#!/usr/bin/env bash
case " $* " in
  *" --initdb "*) exit 0 ;;
  *" --import "*) [ -s "${*: -1}" ]; exit $? ;;
  *" -K "*) r=0; for f in "$@"; do case $f in *.rpm)
      if [ "$CAS" = signature ] && [ "${f##*/}" = bash-5.1.8-9.el9.x86_64.rpm ]; then echo "$f: digests SIGNATURES NOT OK"; r=1
      else echo "$f: digests signatures OK"; fi ;; esac; done; exit $r ;;
  *" -qp "*) l=$(awk -F '\t' -v f="${*: -1}" '{ sub(/.*\//, "", f) } $1 == f { print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }' "$H/entetes.tsv")
      [ "$CAS" = entete ] && l=${l/9.el9/9.el9_9}; printf '%s' "$l" ;;
  *) echo "faux rpm : appel inattendu $*" >&2; exit 2 ;;
esac
EOF2
cat > "$H/bin/createrepo_c" <<'EOF2'
#!/usr/bin/env bash
[ "$1" = --compatibility ] && [ $# = 2 ] || { echo "faux createrepo_c : appel inattendu $*"; exit 2; }
[ "$CAS" = createrepo ] && { echo "faux createrepo_c : échec d essai"; exit 1; }
mkdir -p "$2/repodata" && echo '<repomd/>' > "$2/repodata/repomd.xml"
EOF2
cat > "$H/bin/skopeo" <<'EOF2'
#!/usr/bin/env bash
echo "$*" > "$H/skopeo.args"
[ "$1 $2" = "copy --preserve-digests" ] && [ $# = 4 ] || { echo "faux skopeo : appel inattendu $*"; exit 2; }
d=${4#dir:}; mkdir -p "$d"
if [ "$CAS" = manifeste ]; then echo autre > "$d/manifest.json"; else printf '%s\n' "$MANIFESTE" > "$d/manifest.json"; fi
EOF2
chmod +x "$H/bin/"*
export H MANIFESTE

hote() { # cas filtre-jq : voie2_preparer sur une variante du verrou
  echo "== cas hôte $1"
  jq "$2" "$H/verrou.json" > "$H/v.json"; rm -rf -- "${H:?}/o"
  HOME=$H/home bash "$H/b/m2.sh" voie2_preparer "$H/v.json" "$H/o" 2>&1; echo "code $?"
}
pod() { # cas : voie2_preparer nominal, puis VOIE2 dans le faux pod
  echo "== cas pod $1"
  rm -rf -- "${H:?}/o" "${H:?}/w/voie2" "${H:?}/curl.urls"; mkdir -p "$H/w/voie2"
  HOME=$H/home bash "$H/b/m2.sh" voie2_preparer "$H/verrou.json" "$H/o" > /dev/null 2>&1 || { echo "préparation en échec"; return; }
  cp "$H/o/liste.tsv" "$H/w/voie2/liste.tsv"
  CAS=$1 VOIE2_RACINE=$H/w PATH=$H/bin:$PATH sh -s < "$H/o/voie2.sh" 2>&1 | sed "s#$H#<essai>#g"; echo "code ${PIPESTATUS[0]}"
}

hote nominal '.'
sed "s#$H#<essai>#g" "$H/o/liste.tsv"
grep -c -F "\"docker://sc-stockage.poc.test:5000/amont/rockylinux/rockylinux@$BD\" \"dir:\$D/sc-stockage.poc.test@$BD\"" "$H/o/voie2.sh" \
  | sed 's/^/ligne de skopeo avec la référence et le dossier substitués (1 attendue) : /'
grep -c '@SOURCE@\|@DOSSIER@\|@DIGEST@' "$H/o/voie2.sh" | sed 's/^/marqueurs restants (0 attendu) : /'
hote version '.version = "1.0.0"'
hote pull_digest '.bootstrap.pull_digest = "sha256:" + ("0" * 64)'
hote bootstrap_image '.config.bootstrap_image = "docker.io/library/rockylinux@" + .bootstrap.pull_digest'
hote champ_manquant '.buildroot.rpms[0].sigmd5 = null'
hote sigmd5 '.buildroot.rpms[0].sigmd5 = "ABC"'
hote url '.buildroot.rpms[1].url = "https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/m/mock-6.9-1.el9.noarch.rpm"'
hote nom '.buildroot.rpms[1].url = "https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os/Packages/x/x;id.rpm"'
hote remontee '.buildroot.rpms[1].url = "https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os/../../../../../pub/epel/x.rpm"'
hote doublon '.buildroot.rpms[1] = .buildroot.rpms[0]'
hote vide '.buildroot.rpms = []'
pod nominal
grep -c '%2B' "$H/curl.urls" | sed 's/^/URL avec « + » encodé (1 attendue) : /'
sed "s#$H#<essai>#g" "$H/skopeo.args" | sed 's/^/appel de skopeo : /'
for c in 404 compte signature entete createrepo manifeste; do pod $c; done
rm -rf -- "${H:?}"
