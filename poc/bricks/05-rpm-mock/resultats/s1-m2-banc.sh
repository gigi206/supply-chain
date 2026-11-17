#!/usr/bin/env bash
# Banc hors réseau des étapes voie2 et hermetique (s1-m2.patch), écrit le 17/11/2026 avant tout passage. Ni cluster, ni Zot, ni
# réseau ; données sous le dossier de travail donné (pas sous /tmp).
# A : insertions seules ; la copie, blocs insérés retirés, redonne le s1.sh du dépôt octet pour octet.
# B : bash -n ; shellcheck : remarques de la copie comparées à celles du dépôt ; aucune de niveau warning ou error.
# C : m2_preparer et VOIE2_M2 extraits de la copie ; cœur comparé à celui de m2.sh (seuls les écarts déclarés) ; m2_preparer
#     sur le vrai verrou (s1-verrou_derivee.json) et le vrai digest de boot_image, puis sur onze verrous altérés.
# D : voie2.sh rendu pour un verrou synthétique (222 rpm du vrai verrou, digest d'un faux manifeste), joué sous sh avec curl,
#     rpm, createrepo_c et skopeo simulés et /w remplacé par un dossier : nominal et sept échecs ; porte de l'étape (lignes de
#     etape_voie2, champ et attendu de la copie) rejouée sur la sortie nominale et sur une sortie en échec.
# E : SONDE_HERMETIQUE_PRE et SONDE_HERMETIQUE rendues, /w remplacé ; porte de etape_hermetique rejouée (nominal, repomd.xml
#     changé) ; mock simulé : arguments reçus, comptes de lignes, rpm produits ; mock en échec.
# F : structure : étapes connues de lancer, hermetique ne recrée jamais le pod, voie2 le retire sur échec, nom du pod.
# G : image d'essai (racine.tar lu par son nom) : commandes des sondes dans /usr/bin, hermetic-build.cfg égal à celui du tag.
# Non couvert : vrai pod, vrai mock, vrais rpm, createrepo_c, skopeo et podman, réseau, Zot, kubectl.
# Usage : banc-m2.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier de travail, vidé> [dossier T]
set -uo pipefail
export LC_ALL=C
D=$1; S1N=$2; B=$3; TT=${4:-$HOME/.cache/supply-chain-poc/08/travail/s1-05}
S1A=$D/poc/bricks/05-rpm-mock/s1.sh; M2=$D/poc/bricks/05-rpm-mock/m2.sh
RES=$D/poc/bricks/05-rpm-mock/resultats; V=$RES/s1-verrou_derivee.json
ARC=$HOME/.cache/supply-chain-poc/05/m2/mock.tar.gz
rm -rf -- "${B:?}"; mkdir -p "$B/bin" "$B/T"
echo "# banc-m2.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), python3 $(python3 -I -c 'import sys; print(sys.version.split()[0])')"
echo "# s1.sh du dépôt $(sha256sum < "$S1A" | cut -c1-64) ; copie modifiée $(sha256sum < "$S1N" | cut -c1-64)"
ko=0
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
egal() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else nok "$1 : $2 (attendu : $3)"; fi; }
BD=sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6   # digest de boot_image (s1-boot_image.log)

echo "## A : insertions seules"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
python3 -I - "$S1A" "$S1N" <<'PY' || ko=1
import sys
a, n = (open(f, encoding='utf-8').read() for f in sys.argv[1:3])
d = n.index('#   voie2       '); f = n.index('# Les replis (stockage vfs')
e = n.index('# Étapes voie2 et hermetique '); g = n.index('lancer "$PREFIXE" "05 S1" "$@"\n')
r = n[:d] + n[f:e] + n[g:]
print('OK   copie sans les blocs insérés égale au dépôt' if r == a else 'KO   copie sans les blocs insérés différente du dépôt')
print('     en-tête inséré :', n[d:f].count('\n'), 'lignes ; bloc inséré :', n[e:g].count('\n'), 'lignes')
sys.exit(0 if r == a else 1)
PY

echo "## B : syntaxe et shellcheck"
bash -n "$S1N" && ok "bash -n de la copie" || nok "bash -n de la copie"
shellcheck -f gcc "$S1A" 2>/dev/null | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort | uniq -c > "$B/sc-avant.txt"
shellcheck -f gcc "$S1N" 2>/dev/null | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort | uniq -c > "$B/sc-apres.txt"
echo "     remarques shellcheck : dépôt $(awk '{s+=$1} END {print s+0}' "$B/sc-avant.txt"), copie $(awk '{s+=$1} END {print s+0}' "$B/sc-apres.txt")"
diff "$B/sc-avant.txt" "$B/sc-apres.txt" | sed 's/^/     diff shellcheck : /'
egal "remarques shellcheck de niveau warning ou error dans la copie" "$(shellcheck -S warning -f gcc "$S1N" 2>/dev/null | wc -l)" 0

echo "## C : m2_preparer sur le vrai verrou, puis sur des verrous altérés"
{ grep -E '^(VAULT97|DEPOT_DERIVE|VERROU_DERIVEE_SHA|POD_M2)=' "$S1N"; echo 'REG=sc-stockage.poc.test:5000'
  grep -E '^(attendu|champ)\(\) ' "$S1N"; sed -n '/^m2_preparer() {/,/^}/p' "$S1N"; sed -n "/^VOIE2_M2='/,/^'\$/p" "$S1N"; } > "$B/f.sh"
egal "fragments extraits (variables, attendu, champ, m2_preparer, VOIE2_M2)" "$(grep -c -E '^(VAULT97|DEPOT_DERIVE|VERROU_DERIVEE_SHA|POD_M2|REG)=|^(attendu|champ|m2_preparer)\(\) |^VOIE2_M2=' "$B/f.sh")" 9
diff <(sed -n "/^VOIE2='/,/^'\$/p" "$M2") <(sed -n "/^VOIE2_M2='/,/^'\$/p" "$S1N") | grep '^[<>]' > "$B/coeur.diff"
sed 's/^/     écart du cœur : /' "$B/coeur.diff"
egal "écarts du cœur à m2.sh : nom, verrou relu, df" "$(wc -l < "$B/coeur.diff")" 4
egal "verrou d'entrée, sha256 épinglé dans la copie" "$(sha256sum < "$V" | cut -c1-64)" "$(sed -n 's/^VERROU_DERIVEE_SHA=\([0-9a-f]\{64\}\) .*/\1/p' "$S1N")"
egal "digest de boot_image du dossier de travail" "$(cat "$TT/boot-image.digest")" "$BD"
prep() { # libellé verrou digest : code et dernières lignes de m2_preparer
  local r; rm -rf "$B/o"
  bash -c 'set -euo pipefail; . "$1"; m2_preparer "$2" "$3" "$4"' _ "$B/f.sh" "$2" "$B/o" "$3" > "$B/prep.out" 2>&1; r=$?
  echo "$r"
}
r=$(prep nominal "$V" "$BD"); sed 's/^/     /' "$B/prep.out"
egal "vrai verrou : code" "$r" 0
egal "vrai verrou : paquets" "$(wc -l < "$B/o/liste.tsv")" 222
egal "voie2.sh : marque @…@ restante" "$(grep -c -E '@(SOURCE|DOSSIER|DIGEST)@' "$B/o/voie2.sh")" 0
egal "voie2.sh : source de skopeo" "$(grep -c -F "\"docker://sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@$BD\"" "$B/o/voie2.sh")" 1
egal "voie2.sh : dossier dir: (config.py:844-847)" "$(grep -c -F "\"dir:\$D/sc-stockage.poc.test@$BD\"" "$B/o/voie2.sh")" 1
cp "$B/o/voie2.sh" "$B/voie2-vrai.sh"
alt() { # libellé filtre-jq motif-attendu : verrou altéré refusé, motif trouvé
  jq "$2" "$V" > "$B/alt.json"; local r; r=$(prep "$1" "$B/alt.json" "$BD")
  if [ "$r" != 0 ] && grep -q -F -- "$3" "$B/prep.out"; then ok "refusé : $1 (code $r)"; else nok "non refusé : $1 (code $r)"; sed 's/^/     /' "$B/prep.out"; fi
}
alt "version 1.0.0" '.version = "1.0.0"' "version du verrou"
alt "bootstrap_image_ready faux" '.config.bootstrap_image_ready = false' "bootstrap_image_ready du verrou"
alt "pull_digest d'une autre image" '.bootstrap.pull_digest = "sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2"' "pull_digest du verrou"
alt "bootstrap_image brute" '.config.bootstrap_image = "sc-stockage.poc.test:5000/amont/rockylinux/rockylinux@sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6"' "bootstrap_image du verrou"
alt "image_digest préfixé" '.bootstrap.image_digest = ("sha256:" + .bootstrap.image_digest)' "image_digest du verrou"
alt "URL manquante" '.buildroot.rpms[3].url = null' "champ manquant"
alt "sigmd5 court" '.buildroot.rpms[4].sigmd5 = "abc"' "sigmd5 inattendu"
alt "URL d'extras" '.buildroot.rpms[5].url |= sub("/BaseOS/"; "/extras/") | .buildroot.rpms[5].url |= sub("/AppStream/"; "/extras/")' "URL hors des dépôts"
alt "URL avec .." '.buildroot.rpms[6].url |= sub("/Packages/"; "/Packages/../Packages/")' "URL refusée"
alt "doublon" '.buildroot.rpms[7] = .buildroot.rpms[8]' "en double"
alt "verrou vide" '.buildroot.rpms = []' "aucun paquet"
r=$(prep "autre digest attendu" "$V" "sha256:$(printf '%064d' 0)"); [ "$r" != 0 ] && ok "refusé : digest de boot_image différent du verrou (code $r)" || nok "non refusé : digest différent"

echo "## D : voie2.sh joué avec des outils simulés"
MANIFESTE='faux manifeste du banc m2'
FBD=sha256:$(printf '%s' "$MANIFESTE" | sha256sum | cut -c1-64)
jq --arg b "$FBD" '.bootstrap.pull_digest = $b | .config.bootstrap_image = ("sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@" + $b)' "$V" > "$B/verrou-synth.json"
r=$(prep synthetique "$B/verrou-synth.json" "$FBD"); egal "verrou synthétique préparé : code" "$r" 0
DOS=sc-stockage.poc.test@$FBD
cat > "$B/bin/curl" <<'EOF'
#!/usr/bin/env bash
o=; u=; while [ $# -gt 0 ]; do case $1 in -o) o=$2; shift 2;; -w|--proto|--max-time) shift 2;; -*) shift;; *) u=$1; shift;; esac; done
echo "$u" >> "$BANC/curl.urls"
if [ "${CAS:-}" = http404 ] && [[ $u == */b/bash-* ]]; then printf 404; exit 0; fi
printf 'rpm factice %s\n' "${u##*/}" > "$o"; printf 200
EOF
cat > "$B/bin/rpm" <<'EOF'
#!/usr/bin/env bash
q=; m=; f=()
while [ $# -gt 0 ]; do case $1 in --dbpath) shift 2;; --initdb|--import) exit 0;; -K) m=K; shift;; -qp) m=qp; shift;; --qf) q=$2; shift 2;; *) f+=("$1"); shift;; esac; done
if [ "$m" = K ]; then r=0
  for x in "${f[@]}"; do if [ "${CAS:-}" = signature ] && [[ $x == */bash-* ]]; then echo "$x: digests SIGNATURES NOT OK"; r=1; else echo "$x: digests signatures OK"; fi; done; exit $r; fi
if [[ $q == *BUILDHOST* ]]; then printf 'BUILDHOST reproducible ; BUILDTIME 1731000000'; exit 0; fi
b=${f[0]##*/}; T=$(printf '\t')
awk -F '\t' -v b="$b" -v c="${CAS:-}" '{ u = $6; sub(/.*\//, "", u) } u == b { m = $5; if (c == "entete" && b ~ /^bash-/) m = "00000000000000000000000000000000"; printf "%s\t%s\t%s\t%s\t%s", $1, $2, $3, $4, m }' "$VOIE2_RACINE/voie2/liste.tsv"
EOF
cat > "$B/bin/createrepo_c" <<'EOF'
#!/usr/bin/env bash
[ "${CAS:-}" = createrepo ] && { echo "erreur simulée"; exit 1; }
d=${*: -1}; mkdir -p "$d/repodata"; echo "<repomd banc=\"$(ls "$d" | wc -l)\"/>" > "$d/repodata/repomd.xml"
EOF
cat > "$B/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$BANC/skopeo.args"; d=${*: -1}; d=${d#dir:}; mkdir -p "$d"
if [ "${CAS:-}" = manifeste ]; then printf 'autre' > "$d/manifest.json"; else printf '%s' "$MANIFESTE" > "$d/manifest.json"; fi
EOF
chmod +x "$B/bin/"*
sed "s#df -k /w #df -k $B/w #" "$B/o/voie2.sh" > "$B/voie2-banc.sh"
egal "voie2.sh du banc : seule la ligne df change" "$(diff "$B/o/voie2.sh" "$B/voie2-banc.sh" | grep -c '^>')" 1
jouer() { # cas : voie2.sh joué, sortie dans $B/T/m2-voie2.log (nom lu par champ), code rendu
  rm -rf "$B/w" "$B/curl.urls"; mkdir -p "$B/w/voie2" "$B/w/cles"
  cp "$B/o/liste.tsv" "$B/w/voie2/liste.tsv"; cp "$B/verrou-synth.json" "$B/w/verrou.json"; echo cle > "$B/w/cles/RPM-GPG-KEY-Rocky-9"
  CAS=$1 BANC=$B MANIFESTE=$MANIFESTE VOIE2_RACINE=$B/w PATH=$B/bin:$PATH sh -s < "$B/voie2-banc.sh" > "$B/T/m2-voie2.log" 2>&1
  echo $?
}
porte_voie2() { # porte de etape_voie2, lignes de la copie, sur $B/T/m2-voie2.log ; « retiré » si pod_retirer est appelé
  local g; g=$(sed -n '/^etape_voie2() {/,/^}/p' "$S1N" | sed -n '/^  ( attendu "verrou relu dans le pod"/,/pod_retirer "\$n"; exit 1; }$/p')
  bash -c 'set -euo pipefail; . "$1"; T=$2; VERROU_DERIVEE_SHA=$3; bd=$4; n=pod-banc; pod_retirer() { echo "retiré $1"; }; eval "$5"; echo "porte passée"' \
    _ "$B/f.sh" "$B/T" "$(sha256sum < "$B/verrou-synth.json" | cut -c1-64)" "$FBD" "$g" 2>&1
}
r=$(jouer nominal); sed 's/^/     /' "$B/T/m2-voie2.log" | grep -v -E 'digests signatures OK$'
egal "nominal : code" "$r" 0
egal "nominal : URL demandées" "$(wc -l < "$B/curl.urls")" 222
egal "nominal : dernière porte" "$(grep -c -x "OK   manifeste copié : $FBD" "$B/T/m2-voie2.log")" 1
egal "nominal : arguments de skopeo" "$(cat "$B/skopeo.args")" "copy --preserve-digests docker://sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@$FBD dir:$B/w/voie2/depot/$DOS"
egal "nominal : ligne df" "$(grep -c '^capacité de /w : [0-9]* kB ; utilisés : [0-9]* kB$' "$B/T/m2-voie2.log")" 1
porte_voie2 > "$B/porte.out"; sed 's/^/     /' "$B/porte.out"
egal "porte de etape_voie2 sur la sortie nominale" "$(tail -n 1 "$B/porte.out")" "porte passée"
cp "$B/T/m2-voie2.log" "$B/m2-voie2-nominal.log"; cp -r "$B/w" "$B/w-nominal"
for c in http404 signature entete createrepo manifeste; do
  r=$(jouer $c)
  if [ "$r" = 1 ] && grep -q '^KO   ' "$B/T/m2-voie2.log" && ! grep -q '^OK   manifeste copié' "$B/T/m2-voie2.log"; then
    ok "cas $c : code 1, $(grep '^KO   ' "$B/T/m2-voie2.log" | head -1 | cut -c1-100)"
  else nok "cas $c : code $r"; sed 's/^/     /' "$B/T/m2-voie2.log" | tail -n 5; fi
done
porte_voie2 > "$B/porte.out"
egal "porte de etape_voie2 sur la sortie du cas manifeste : pod retiré, porte non passée" "$(grep -c -x 'retiré pod-banc' "$B/porte.out") $(grep -c 'porte passée' "$B/porte.out")" "1 0"
for o in skopeo createrepo_c; do
  mv "$B/bin/$o" "$B/$o.de-cote"; r=$(jouer nominal); mv "$B/$o.de-cote" "$B/bin/$o"
  egal "cas sans $o : code et ligne" "$r $(grep -c -x "KO   $o absent de l image" "$B/T/m2-voie2.log")" "1 1"
done

echo "## E : sondes de hermetique"
PRE=$(sed -n "/^SONDE_HERMETIQUE_PRE='/,/^true'\$/p" "$S1N" | sed '1s/^SONDE_HERMETIQUE_PRE=.//; $s/.$//')
SH=$(sed -n "/^SONDE_HERMETIQUE='/,/^true'\$/p" "$S1N" | sed '1s/^SONDE_HERMETIQUE=.//; $s/.$//')
egal "sondes extraites : première et dernière lignes" "$(printf '%s\n' "$PRE" | sed -n '1p;$p' | paste -sd '|' -) $(printf '%s\n' "$SH" | sed -n '1p;$p' | paste -sd '|' -)" "set -u|true set -u|true"
rm -rf "$B/w"; cp -r "$B/w-nominal" "$B/w"; cp "$B/m2-voie2-nominal.log" "$B/T/m2-voie2.log"
pre() { sed -e "s|@DOSSIER@|$DOS|g" -e "s#/w/#$B/w/#g" <<<"$PRE" | sh -s > "$B/T/m2-hermetique-pre.log" 2>&1; }
porte_herm() {
  local g; g=$(sed -n '/^etape_hermetique() {/,/^}/p' "$S1N" | sed -n '/^  ( attendu "verrou relu dans le pod"/,/pod_retirer "\$n"; exit 1; }$/p')
  bash -c 'set -euo pipefail; . "$1"; T=$2; VERROU_DERIVEE_SHA=$3; bd=$4; n=pod-banc; pod_retirer() { echo "retiré $1"; }; eval "$5"; echo "porte passée"' \
    _ "$B/f.sh" "$B/T" "$(sha256sum < "$B/verrou-synth.json" | cut -c1-64)" "$FBD" "$g" 2>&1
}
pre; sed 's/^/     /' "$B/T/m2-hermetique-pre.log"; porte_herm > "$B/porte.out"; sed 's/^/     /' "$B/porte.out"
egal "porte de etape_hermetique, nominal" "$(tail -n 1 "$B/porte.out")" "porte passée"
echo '<repomd change/>' > "$B/w/voie2/depot/repodata/repomd.xml"; pre; porte_herm > "$B/porte.out"
egal "porte de etape_hermetique, repomd.xml changé : pod retiré, porte non passée" "$(grep -c -x 'retiré pod-banc' "$B/porte.out") $(grep -c 'porte passée' "$B/porte.out")" "1 0"
cat > "$B/bin/mock" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$BANC/mock.args"; rd=; bd=; for a in "$@"; do case $a in --resultdir=*) rd=${a#--resultdir=};; --config-opts=basedir=*) bd=${a#--config-opts=basedir=};; esac; done
mkdir -p "$rd"
L="INFO: Using container image: dir:/w/voie2/depot/x
INFO: Pulling image: dir:/w/voie2/depot/x
INFO: Tagging container image as mock-bootstrap-0000
INFO: Checking image digest: 18d64b0330fe240fff58475e43a3f003e5dcfade898c4caa1d1165e8304be1af
INFO: Calculating mock-bootstrap-0000 image OCI digest
INFO: Checking that 0000 image matches host's architecture
DEBUG: Executing command: ['/usr/bin/dnf-3', '--installroot=$bd/hermetic-build/root/', 'install', '*']"
echo "$L"; echo "$L" > "$rd/root.log"
[ "${CAS:-}" = mockko ] && { echo "ERROR: échec simulé"; exit 30; }
: > "$rd/sample-app-1.0.0-2.el9.src.rpm"; : > "$rd/sample-app-1.0.0-2.el9.x86_64.rpm"; : > "$rd/build.log"
EOF
chmod +x "$B/bin/mock"
mkdir -p "$B/w/src"; cp "$HOME/.cache/supply-chain-poc/packaging/sample-app.spec" "$B/w/src/"
cp "$HOME/.cache/supply-chain-poc/packaging/sample-app-1.0.0.tar.gz" "$B/w/src/"; cp "$TT/SHA256SUMS.s1" "$B/w/src/"
herm() { sed -e "s|@ISO@|simple|g" -e "s|@IMAGE_DIGEST@|18d64b0330fe240fff58475e43a3f003e5dcfade898c4caa1d1165e8304be1af|g" -e "s#/w/#$B/w/#g" -e "s#df -k /w #df -k $B/w #g" <<<"$SH" \
  | CAS=$1 BANC=$B PATH=$B/bin:$PATH sh -s > "$B/herm.out" 2>&1; }
herm nominal; sed 's/^/     /' "$B/herm.out"
egal "rendu : marque @…@ restante" "$(sed -e 's|@ISO@|simple|g' -e 's|@IMAGE_DIGEST@|x|g' <<<"$SH" | grep -c -E '@[A-Z_]+@')" 0
egal "sources livrées" "$(grep -c '^sources livrées : rc 0 ' "$B/herm.out")" 1
egal "arguments de mock" "$(cat "$B/mock.args")" "--hermetic-build $B/w/verrou.json $B/w/voie2/depot --isolation=simple --no-cleanup-after --config-opts=basedir=$B/w/mock-h --config-opts=cache_topdir=$B/w/mock-h-cache --resultdir=$B/w/res-h --spec $B/w/src/sample-app.spec --sources $B/w/src"
egal "mock : rc" "$(grep -c '^mock --hermetic-build : rc 0 en [0-9]* s$' "$B/herm.out")" 1
for m in "Using container image: dir:" "Pulling image: dir:" "Tagging container image as mock-bootstrap-" "Calculating .* image OCI digest" "matches host.s architecture"; do
  egal "compte « $m »" "$(grep -c -x -F "lignes « $m » : sortie 1 ; root.log 1" "$B/herm.out")" 1; done
egal "compte du digest affirmé" "$(grep -c -x -F 'lignes « Checking image digest: 18d64b0330fe240fff58475e43a3f003e5dcfade898c4caa1d1165e8304be1af » : sortie 1 ; root.log 1' "$B/herm.out")" 1
egal "compte du repli (0)" "$(grep -c -x -F 'lignes « falling back to chroot installation » : sortie 0 ; root.log 0' "$B/herm.out")" 1
egal "compte de --installroot sous le basedir (motif commençant par --, passé par -e)" "$(grep -c -x -F "lignes « --installroot=$B/w/mock-h/ » : sortie 1 ; root.log 1" "$B/herm.out")" 1
egal "compte de « No space left on device » (0)" "$(grep -c -x -F 'lignes « No space left on device » : sortie 0 ; root.log 0' "$B/herm.out")" 1
egal "rpm produits relevés" "$(grep -c '^rpm : sample-app-1.0.0-2.el9\.[a-z0-9_]*\.rpm sha256 [0-9a-f]\{64\} ; BUILDHOST reproducible ; BUILDTIME 1731000000$' "$B/herm.out")" 2
egal "lignes df avant et après" "$(grep -c -E '^(avant mock|après mock \(buildroot gardé, --no-cleanup-after\)), capacité de /w : [0-9]+ kB ; utilisés : [0-9]+ kB$' "$B/herm.out")" 2
herm mockko
egal "mock en échec : rc et fin de journal" "$(grep -c '^mock --hermetic-build : rc 30 ' "$B/herm.out") $(grep -c 'ERROR: échec simulé' "$B/herm.out")" "1 1"   # sortie de mock seulement : le faux root.log est écrit avant l'erreur

echo "## F : structure"
python3 -I - "$S1N" <<'PY' || ko=1
import re, sys
n = open(sys.argv[1], encoding='utf-8').read(); e = 0
def corps(f):
    i = n.index(f'\n{f}() {{\n'); return n[i:n.index('\n}\n', i)]
h, v = corps('etape_hermetique'), corps('etape_voie2')
for nom, ok in [('etape_voie2 et etape_hermetique définies une fois', n.count('\netape_voie2() {\n') == 1 and n.count('\netape_hermetique() {\n') == 1),
                ('hermetique ne recrée pas le pod (ni pod_spec, ni pod_demarrer)', 'pod_spec' not in h and 'pod_demarrer' not in h),
                ('hermetique retire le pod sur échec de sa porte et à la fin', h.count('pod_retirer "$n"') == 2),
                ('voie2 retire le pod sur échec de sa porte, et seulement là', v.count('pod_retirer "$n"') == 1),
                ('voie2 ne joue mock nulle part', 'mock ' not in v),
                ('nom du pod conforme (DNS-1123, 63 au plus)', re.search(r'^POD_M2=([a-z0-9-]{1,63})$', n, re.M) is not None)]:
    print(('OK   ' if ok else 'KO   ') + nom); e |= not ok
sys.exit(e)
PY

echo "## G : image d'essai"
egal "racine.tar (image d'essai), sha256 de l'étape racine" "$(sha256sum < "$TT/racine.tar" | cut -c1-64)" d7433a050469836de7317de87f2421d3bc7eaa52052cf422518809e276a94a9d
tar -tf "$TT/racine.tar" > "$B/racine.liste"
egal "commandes des sondes absentes de /usr/bin" "$(for c in curl rpm createrepo_c skopeo sha256sum find awk df paste ls wc grep sed head tail cut date mkdir rm mock; do grep -q -x "./usr/bin/$c" "$B/racine.liste" || echo "$c"; done | tr '\n' ' ')" ""
egal "archive des sources de mock, sha256 (m2-releve.log)" "$(sha256sum < "$ARC" | cut -c1-64)" 3c034916a721bb06b923399c856d5111fbf3d791804934dd6d909e3d292e4d88
egal "hermetic-build.cfg de l'image égal à celui du tag mock-6.9-1" "$(tar -xOf "$TT/racine.tar" ./etc/mock/hermetic-build.cfg | sha256sum | cut -c1-64)" "$(tar -xzOf "$ARC" mock-mock-6.9-1/mock/etc/mock/hermetic-build.cfg | sha256sum | cut -c1-64)"
if [ $ko = 0 ]; then echo "# bilan : tenu, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; else echo "# bilan : NON TENU, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
exit $ko
