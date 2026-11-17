#!/usr/bin/env bash
# Banc hors cluster des étapes collecte, fermeture et restauration (s1-fermeture.patch), écrit le 17/11/2026 avant tout passage.
# Ni cluster, ni Zot ; registre crane local en loopback (http, disque sous le dossier du banc) ; réseau non utilisé.
# A : insertions seules ; la copie, blocs insérés retirés, redonne le s1.sh du dépôt octet pour octet.
# B : bash -n ; shellcheck : remarques de la copie comparées à celles du dépôt ; aucune de niveau warning ou error.
# C : primary_somme sur le vrai primary d'EPEL du dernier hote ; SONDE_COLLECTE rendue, /w remplacé, curl et rpm simulés (tar,
#     find, stat et sort réels) : nominal et quatre échecs ; portes de etape_collecte rejouées (lignes de la copie).
# D : fermeture_controle construire sur une doublure de la fermeture (noms des 222 rpm du vrai verrou, contenus et primary
#     factices, repodata et dossier dir: factices) : nominal, treize écarts ; puis sur les vrais primary de vault 9.7 (hote97) :
#     les 222 emplacements trouvés ; puis comparer : nominal et quatre écarts.
# E : etape_fermeture et etape_restauration de la copie contre le registre local, avec le vrai closure.sh et le vrai oras
#     1.3.6 (chemins à « : » et « @ » du dossier dir:) ; image factice poussée par crane ; auth_zot, oras_zot et sur simulés :
#     deux envois, même digest ; dépôt présent et tag déjà présent refusés sans envoi ; catalogue illisible refusé sans envoi ;
#     place illisible après l'envoi affichée sans arrêt ; fermeture changée refusée sans envoi ; restauration, liens relus.
# F : structure : étapes définies, collecte n'écrit pas dans Zot et retire le pod sur chaque échec, portes de voie2 égales.
# G : image d'essai (racine.tar lu par son nom) : commandes de SONDE_COLLECTE dans /usr/bin.
# Non couvert : vrai pod, vrais rpm et vrai rpm -K, vrai createrepo_c et skopeo, kubectl, réseau, Zot (droits, déduplication).
# Usage : banc-fermeture.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier du banc, absent> [dossier T] [adresse]
set -uo pipefail
export LC_ALL=C
D=$1; S1N=$2; B=$3; TT=${4:-$HOME/.cache/supply-chain-poc/08/travail/s1-05}; ADR=${5:-127.0.0.1:5909}
S1A=$D/poc/bricks/05-rpm-mock/s1.sh; RES=$D/poc/bricks/05-rpm-mock/resultats; V=$RES/s1-verrou_derivee.json
CLOS=$D/poc/bricks/03-deps-closure/closure.sh
CRANE=$(cd "$D" && mise which crane); ORASB=$(cd "$D" && mise which oras)
[ ! -e "$B" ] || { echo "KO   $B existe déjà"; exit 1; }
! curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 || { echo "KO   $ADR déjà pris"; exit 1; }
mkdir -p "$B/bin" "$B/T"
echo "# banc-fermeture.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), python3 $(python3 -I -c 'import sys; print(sys.version.split()[0])'), $("$ORASB" version | head -1 | tr -s ' '), crane $("$CRANE" version)"
echo "# s1.sh du dépôt $(sha256sum < "$S1A" | cut -c1-64) ; copie modifiée $(sha256sum < "$S1N" | cut -c1-64) ; closure.sh $(sha256sum < "$CLOS" | cut -c1-64)"
ko=0
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
egal() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else nok "$1 : $2 (attendu : $3)"; fi; }
BD=sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6   # digest de boot_image (s1-boot_image.log)
VSHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f

echo "## A : insertions seules"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
python3 -I - "$S1A" "$S1N" <<'PY' || ko=1
import sys
a, n = (open(f, encoding='utf-8').read() for f in sys.argv[1:3])
d = n.index('#   collecte    '); f = n.index('# Les replis (stockage vfs')
e = n.index('# Étapes collecte, fermeture et restauration '); g = n.index('lancer "$PREFIXE" "05 S1" "$@"\n')
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

echo "## C : primary_somme et SONDE_COLLECTE"
{ grep -E '^(VAULT97|EPEL9|DEPOT_DERIVE|VERROU_DERIVEE_SHA|POD_M2|POD_MF|DEPOT_FERMETURE|MOCK_CHEMIN|MOCK_SHA)=' "$S1N"; echo 'REG=sc-stockage.poc.test:5000'
  grep -E '^(attendu|champ)\(\) ' "$S1N"
  for f in m2_preparer primary_somme fermeture_controle zot_place zot_liens etape_fermeture etape_restauration; do sed -n "/^$f() {/,/^}/p" "$S1N"; done
  grep -E '^(oras_zot|de_plus)\(\) ' "$S1N"; sed -n "/^VOIE2_M2='/,/^'\$/p" "$S1N"; } > "$B/f.sh"
egal "fragments extraits (10 variables, 11 fonctions, VOIE2_M2), absents" "$(for x in VAULT97= EPEL9= DEPOT_DERIVE= VERROU_DERIVEE_SHA= POD_M2= POD_MF= DEPOT_FERMETURE= MOCK_CHEMIN= MOCK_SHA= REG= 'attendu() ' 'champ() ' 'm2_preparer() ' 'primary_somme() ' 'fermeture_controle() ' 'zot_place() ' 'etape_fermeture() ' 'etape_restauration() ' 'oras_zot() ' 'zot_liens() ' 'de_plus() ' "VOIE2_M2='"; do [ "$(grep -c -F -x -e "$x" <(cut -c1-${#x} "$B/f.sh"))" = 1 ] || printf '%s ' "$x"; done)" ""
egal "rpm de mock dans le vrai primary d'EPEL du dernier hote" \
  "$(bash -c '. "$1"; primary_somme "$2/epel9.primary.xml" "$MOCK_CHEMIN"' _ "$B/f.sh" "$TT")" "sha256 a5043350d6d3efd92340f6d6fb221d720f6029ee8a9a8d09210d58f17752ba1e"
egal "emplacement inconnu dans le primary d'EPEL" "$(bash -c '. "$1"; primary_somme "$2/epel9.primary.xml" Packages/m/mock-0.0-0.el9.noarch.rpm' _ "$B/f.sh" "$TT")" absent
SC=$(sed -n "/^SONDE_COLLECTE='/,/^'\$/p" "$S1N" | sed '1s/^SONDE_COLLECTE=.//; $d')
egal "sonde extraite : première et dernière lignes" "$(printf '%s\n' "$SC" | sed -n '1p;$p' | paste -sd '|' -)" 'set -u|df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"'
MOCKF='faux rpm de mock du banc'; MSHA=$(printf '%s' "$MOCKF" | sha256sum | cut -c1-64)
rendre() { sed -e "s|@MOCK_URL@|https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/m/mock-6.9-1.el9.noarch.rpm|g" \
  -e "s|@MOCK_NOM@|mock-6.9-1.el9.noarch.rpm|g" -e "s|@MOCK_SHA@|$MSHA|g" -e "s#/w/#$B/w/#g" -e "s#df -k /w #df -k $B/w #g" <<<"$SC"; }
egal "rendu : marque @…@ et /w restants (libellé « capacité de /w » mis à part)" "$(rendre | sed 's#capacité de /w : ##' | grep -c -E '@[A-Z_]+@|[ "]/w[/ ]')" 0
cat > "$B/bin/curl" <<'EOF'
#!/usr/bin/env bash
o=; u=; while [ $# -gt 0 ]; do case $1 in -o) o=$2; shift 2;; -w|--proto|--max-time) shift 2;; -*) shift;; *) u=$1; shift;; esac; done
echo "$u" >> "$BANC/curl.urls"
[ "${CAS:-}" = http404 ] && { printf 404; exit 0; }
if [ "${CAS:-}" = sha ]; then printf 'autre contenu' > "$o"; else printf '%s' "$MOCKF" > "$o"; fi; printf 200
EOF
cat > "$B/bin/rpm" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$BANC/rpm.args"
k=0; for a in "$@"; do [ "$a" = -K ] && k=1; done
[ $k = 1 ] || exit 0
if [ "${CAS:-}" = signature ]; then echo "${*: -1}: digests SIGNATURES NOT OK"; exit 1; fi
echo "${*: -1}: digests signatures OK"
EOF
chmod +x "$B/bin/"*
mkdir -p "$B/modele/voie2/depot/repodata" "$B/modele/voie2/depot/sc-stockage.poc.test@$BD" "$B/modele/cles"
for f in bash-5.1.8-9.el9.x86_64.rpm 'libstdc++-11.5.0-5.el9_5.x86_64.rpm' zlib-1.2.11-41.el9.x86_64.rpm; do printf 'rpm %s' "$f" > "$B/modele/voie2/depot/$f"; done
echo '<repomd/>' > "$B/modele/voie2/depot/repodata/repomd.xml"; echo manifeste > "$B/modele/voie2/depot/sc-stockage.poc.test@$BD/manifest.json"
echo verrou > "$B/modele/verrou.json"; echo cle > "$B/modele/cles/RPM-GPG-KEY-EPEL-9"; mkdir -p "$B/modele/voie2/rpmdb"; echo k > "$B/modele/voie2/k.log"
collecte() { # cas : sonde rendue jouée sous sh, sortie dans $B/T/mf-collecte.log, code rendu
  rm -rf "$B/w" "$B/curl.urls" "$B/rpm.args"; cp -r "$B/modele" "$B/w"
  [ "$1" = sansdepot ] && rm -rf "$B/w/voie2/depot"
  rendre | CAS=$1 BANC=$B MOCKF=$MOCKF PATH=$B/bin:$PATH sh -s > "$B/T/mf-collecte.log" 2>&1; echo $?
}
porte_collecte() { # seconde porte de etape_collecte, lignes de la copie ; « retiré » si pod_retirer est appelé
  local g; g=$(sed -n '/^etape_collecte() {/,/^}/p' "$S1N" | sed -n '/^  ( attendu "rpm de mock (porte de collecte)"/,/pod_retirer "\$n"; exit 1; }$/p')
  bash -c 'set -euo pipefail; . "$1"; T=$2; MOCK_SHA=$3; n=pod-banc; pod_retirer() { echo "retiré $1"; }; eval "$4"; echo "porte passée"' \
    _ "$B/f.sh" "$B/T" "$MSHA" "$g" 2>&1
}
r=$(collecte nominal); sed 's/^/     /' "$B/T/mf-collecte.log"
egal "nominal : code" "$r" 0
egal "nominal : URL demandée" "$(cat "$B/curl.urls")" https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/m/mock-6.9-1.el9.noarch.rpm
egal "nominal : rpmdb à part et seule clé d'EPEL" "$(grep -c -e "--dbpath $B/w/rpmdb-epel" "$B/rpm.args") $(grep -c -e '--import' "$B/rpm.args") $(grep -c -e "--import $B/w/cles/RPM-GPG-KEY-EPEL-9" "$B/rpm.args")" "3 1 1"
egal "nominal : porte" "$(grep -c -x "OK   rpm de mock : mock-6.9-1.el9.noarch.rpm sha256 $MSHA" "$B/T/mf-collecte.log")" 1
egal "nominal : dépôt déplacé sous fermeture, rpmdb et k.log laissés" "$([ -d "$B/w/voie2/depot" ] && echo reste || echo parti) $(cd "$B/w/fermeture" && find . -type f | sort | paste -sd ' ')" \
  "parti ./depot/bash-5.1.8-9.el9.x86_64.rpm ./depot/libstdc++-11.5.0-5.el9_5.x86_64.rpm ./depot/repodata/repomd.xml ./depot/sc-stockage.poc.test@$BD/manifest.json ./depot/zlib-1.2.11-41.el9.x86_64.rpm ./outils/mock-6.9-1.el9.noarch.rpm ./verrou.json"
egal "nominal : lignes fichier (chemin, sha256, taille) égales à un relevé de l'hôte" "$(grep '^fichier ' "$B/T/mf-collecte.log")" \
  "$(cd "$B/w/fermeture" && find . -type f -printf '%P\n' | sort | while IFS= read -r f; do echo "fichier $f $(sha256sum < "$f" | cut -c1-64) $(stat -c %s "$f")"; done)"
egal "nominal : compte et autres entrées" "$(grep -c -E '^fichiers de la fermeture : 7 ; octets : [0-9]+$' "$B/T/mf-collecte.log") $(grep -c -x 'autres entrées que fichiers et dossiers : 0' "$B/T/mf-collecte.log")" "1 1"
porte_collecte > "$B/porte.out"; sed 's/^/     /' "$B/porte.out"
egal "porte de etape_collecte, nominal" "$(tail -n 1 "$B/porte.out")" "porte passée"
for c in http404 sha signature sansdepot; do
  r=$(collecte $c)
  if [ "$r" = 1 ] && grep -q '^KO   ' "$B/T/mf-collecte.log" && ! grep -q -e '^OK   rpm de mock' -e '^fichiers de la fermeture' "$B/T/mf-collecte.log"; then
    ok "cas $c : code 1, $(grep '^KO   ' "$B/T/mf-collecte.log" | head -1 | cut -c1-110)"
  else nok "cas $c : code $r"; sed 's/^/     /' "$B/T/mf-collecte.log" | tail -n 5; fi
  porte_collecte > "$B/porte.out"
  egal "porte de etape_collecte, cas $c : pod retiré, porte non passée" "$(grep -c -x 'retiré pod-banc' "$B/porte.out") $(grep -c 'porte passée' "$B/porte.out")" "1 0"
done

echo "## D : fermeture_controle"
rm -rf "$B/o"; bash -c 'set -euo pipefail; . "$1"; m2_preparer "$2" "$3" "$4"' _ "$B/f.sh" "$V" "$B/o" "$BD" > "$B/prep.out" 2>&1
egal "liste.tsv du vrai verrou (m2_preparer de la copie) : code et paquets" "$? $(wc -l < "$B/o/liste.tsv")" "0 222"
cat > "$B/gen.py" <<'PY'
"""Doublure de la fermeture : arbre, primary factices, liste du pod. Usage : gen.py liste.tsv vault arbre primaires verrou nom-mock contenu-mock"""
import hashlib, json, os, sys
tsv, vault, d, prim, verrou, mnom, mcont = sys.argv[1:8]
h = lambda b: hashlib.sha256(b).hexdigest()
def ecrire(p, b):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'wb').write(b)
P = {'baseos97': [], 'appstream97': [], 'crb97': []}; DEP = {'BaseOS': 'baseos97', 'AppStream': 'appstream97', 'CRB': 'crb97'}
for l in open(tsv, encoding='utf-8'):
    u = l.rstrip('\n').split('\t')[5]; f = u.rsplit('/', 1)[1]; b = f'contenu factice de {f}\n'.encode()
    ecrire(f'{d}/depot/{f}', b); dep, _, href = u[len(vault) + 1:].partition('/x86_64/os/'); P[DEP[dep]].append((href, h(b), len(b)))
for n, z in P.items():
    x = ''.join(f'<package type="rpm"><name>x</name><checksum type="sha256" pkgid="YES">{s}</checksum><size package="{t}" installed="1"/>'
                f'<location href="{href}"/></package>' for href, s, t in z)
    ecrire(f'{prim}/{n}.primary.xml', f'<metadata xmlns="http://linux.duke.edu/metadata/common" packages="{len(z)}">{x}</metadata>'.encode())
rd = [(f'repodata/{k}-primary.xml.gz', f'primaire {k}'.encode()) for k in ('a1', 'b2')]
for p, b in rd: ecrire(f'{d}/depot/{p}', b)
ecrire(f'{d}/depot/repodata/repomd.xml', ('<repomd xmlns="http://linux.duke.edu/metadata/repo">' + ''.join(
    f'<data type="t{i}"><checksum type="sha256">{h(b)}</checksum><location href="{p}"/><size>{len(b)}</size></data>' for i, (p, b) in enumerate(rd))
    + '</repomd>').encode())
cfg, cou = b'{"config":"factice"}', b'couche factice'
m = json.dumps({'schemaVersion': 2, 'config': {'digest': 'sha256:' + h(cfg), 'size': len(cfg)}, 'layers': [{'digest': 'sha256:' + h(cou), 'size': len(cou)}]}).encode()
dos = 'sc-stockage.poc.test@sha256:' + h(m)
ecrire(f'{d}/depot/{dos}/manifest.json', m); ecrire(f'{d}/depot/{dos}/version', b'Directory Transport Version: 1.1\n')
ecrire(f'{d}/depot/{dos}/{h(cfg)}', cfg); ecrire(f'{d}/depot/{dos}/{h(cou)}', cou)
ecrire(f'{d}/verrou.json', open(verrou, 'rb').read()); ecrire(f'{d}/outils/{mnom}', mcont.encode())
print('sha256:' + h(m))
PY
liste_pod() { (cd "$1" && find . -type f -printf '%P\n' | sort | while IFS= read -r f; do echo "fichier $f $(sha256sum < "$f" | cut -c1-64) $(stat -c %s "$f")"; done); }
FBD=$(python3 -I "$B/gen.py" "$B/o/liste.tsv" https://dl.rockylinux.org/vault/rocky/9.7 "$B/arbre" "$B/prim" "$V" mock-6.9-1.el9.noarch.rpm "$MOCKF")
FDOS=sc-stockage.poc.test@$FBD
liste_pod "$B/arbre" > "$B/pod.txt"
construire() { # arbre primaires dos bd vsha msha pod sortie : code ; sortie dans $B/c.out
  bash -c '. "$1"; shift; fermeture_controle construire "$1" "$2" "$3" "$VAULT97" "$4" "$5" "$6" mock-6.9-1.el9.noarch.rpm "$7" "$8" "$9"' \
    _ "$B/f.sh" "$1" "$B/o/liste.tsv" "$2" "$3" "$4" "$5" "$6" "$7" "$8" > "$B/c.out" 2>&1; echo $?
}
r=$(construire "$B/arbre" "$B/prim" "$FDOS" "$FBD" "$VSHA" "$MSHA" "$B/pod.txt" "$B/att.txt"); sed 's/^/     /' "$B/c.out"
egal "nominal : code" "$r" 0
egal "nominal : rpm trouvés dans les primary" "$(grep -c -x 'rpm du verrou trouvés dans les primary de vault 9.7 vérifiés par hote97 : 222 sur 222' "$B/c.out")" 1
egal "nominal : liste attendue (222 rpm, 3 repodata, 4 image, verrou, mock)" "$(wc -l < "$B/att.txt")" 231
egal "nominal : liste attendue égale à la liste du pod (sha256 des deux listes)" "$(sed 's/^fichier //' "$B/pod.txt" | sha256sum | cut -c1-64)" "$(sha256sum < "$B/att.txt" | cut -c1-64)"
egal "nominal : classes" "$(grep '^classe ' "$B/c.out" | sed 's/, [0-9]* octets$//' | paste -sd '|')" \
  "classe rpm : 222 fichier(s)|classe repodata : 3 fichier(s)|classe image : 4 fichier(s)|classe verrou : 1 fichier(s)|classe outils : 1 fichier(s)"
ecart() { # libellé motif-attendu préparation(arbre) [arguments de construire modifiés] : copie de l'arbre altérée, refus attendu
  local l=$1 m=$2 p=$3; shift 3; rm -rf "$B/a2"; cp -a "$B/arbre" "$B/a2"; (cd "$B/a2" && eval "$p")
  [ -s "$B/pod2.txt" ] || liste_pod "$B/a2" > "$B/pod2.txt"
  local r; r=$(construire "$B/a2" "${PRIM:-$B/prim}" "${XDOS:-$FDOS}" "$FBD" "${XVSHA:-$VSHA}" "${XMSHA:-$MSHA}" "$B/pod2.txt" "$B/att2.txt")
  if [ "$r" = 1 ] && grep -q -F -- "$m" "$B/c.out"; then ok "refusé : $l ($(grep -m1 -F -- "$m" "$B/c.out" | cut -c1-100))"
  else nok "non refusé : $l (code $r)"; sed 's/^/     /' "$B/c.out" | tail -n 4; fi
  rm -f "$B/pod2.txt"
}
ecart "fichier en trop" "fichier en trop : depot/intrus.rpm" 'echo x > depot/intrus.rpm'
ecart "rpm manquant" "fichier manquant : depot/bash-" 'rm depot/bash-*.rpm'
ecart "rpm altéré" "depot/zlib-" 'echo x >> depot/zlib-*.rpm'
ecart "blob différent de son nom" "depot/$FDOS/" 'f=$(ls depot/sc-*/ | grep -E "^[0-9a-f]{64}$" | head -1); echo x >> "depot/'"$FDOS"'/$f"'
ecart "manifeste changé" "manifeste du dossier dir: absent ou différent" "echo ' ' >> 'depot/$FDOS/manifest.json'"
ecart "repodata altéré" "depot/repodata/a1-primary.xml.gz" 'echo x >> depot/repodata/a1-primary.xml.gz'
ecart "lien symbolique" "entrée qui n'est pas un fichier régulier : lien" 'ln -s verrou.json lien'
ecart "liste du pod différente" "liste du pod différente" 'liste_pod . | sed "1s/ [0-9]*\$/ 1/" > "$B/pod2.txt"'
ecart "emplacement de repomd refusé" "emplacement refusé" "sed -i 's#repodata/b2-primary.xml.gz#../b2#' depot/repodata/repomd.xml"
XVSHA=$(printf '%064d' 0) ecart "verrou d'un autre sha256" "verrou.json : sha256" ':'
XMSHA=$(printf '%064d' 1) ecart "rpm de mock d'un autre sha256" "outils/mock-6.9-1.el9.noarch.rpm : sha256" ':'
XDOS=sc-stockage.poc.test:5000@$FBD ecart "dossier dir: avec le port" "dossier dir: refusé" ':'
mkdir -p "$B/prim2"; cp "$B/prim/"* "$B/prim2/"; python3 -I - "$B/prim2/baseos97.primary.xml" <<'PY'
import re, sys
s = open(sys.argv[1]).read(); open(sys.argv[1], 'w').write(re.sub(r'<package type="rpm">.*?</package>', '', s, count=1))
PY
PRIM=$B/prim2 ecart "rpm absent des primary" "absent des primary de vault 9.7" ':'
r=$(construire "$B/arbre" "$TT" "$FDOS" "$FBD" "$VSHA" "$MSHA" "$B/pod.txt" "$B/att-vrai.txt")
egal "vrais primary de vault 9.7 (hote97) : 222 emplacements trouvés, contenus factices refusés" \
  "$r $(grep -c -x 'rpm du verrou trouvés dans les primary de vault 9.7 vérifiés par hote97 : 222 sur 222' "$B/c.out") $(grep -c -x 'KO   222 écart(s)' "$B/c.out")" "1 1 1"
comparer() { bash -c '. "$1"; fermeture_controle comparer "$2" "$3"' _ "$B/f.sh" "$1" "$2" > "$B/c.out" 2>&1; echo $?; }
egal "comparer, nominal" "$(comparer "$B/arbre" "$B/att.txt") $(grep -c '^OK   arbre égal à la liste : 231 fichiers, ' "$B/c.out")" "0 1"
for c in "trop:echo x > depot/x.rpm:fichier en trop" "manque:rm verrou.json:fichier manquant : verrou.json" \
  "altere:echo x >> outils/mock-6.9-1.el9.noarch.rpm:outils/mock-6.9-1.el9.noarch.rpm : sha256" "lien:ln -s verrou.json l:entrée qui n'est pas"; do
  IFS=: read -r l p m <<<"$c"; rm -rf "$B/a2"; cp -a "$B/arbre" "$B/a2"; (cd "$B/a2" && eval "$p")
  egal "comparer, cas $l : code et motif" "$(comparer "$B/a2" "$B/att.txt") $(grep -c -F -- "$m" "$B/c.out")" "1 1"
done

echo "## E : fermeture et restauration contre un registre local"
mkdir -p "$B/disque"; "$CRANE" registry serve --address "$ADR" --disk "$B/disque" > "$B/serve.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null; wait $srv 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://$ADR/v2/" >/dev/null && ok "registre local prêt (http, $ADR)" || nok "registre local"
mkdir -p "$B/couche/etc" && echo "image factice du banc" > "$B/couche/etc/banc" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$B/couche" -cf "$B/couche.tar" .
"$CRANE" append -f "$B/couche.tar" -t "$ADR/essais-05/rocky9-bootstrap:banc" > /dev/null 2>"$B/append.err" || nok "crane append"
IBD=$("$CRANE" digest "$ADR/essais-05/rocky9-bootstrap:banc"); IDOS=sc-stockage.poc.test@$IBD
mkdir -p "$B/T/mf"; cp -a "$B/arbre" "$B/T/mf/fermeture"; rm -rf "$B/T/mf/fermeture/depot/$FDOS"; mkdir -p "$B/T/mf/fermeture/depot/$IDOS"
"$CRANE" manifest "$ADR/essais-05/rocky9-bootstrap@$IBD" > "$B/T/mf/fermeture/depot/$IDOS/manifest.json"
printf 'Directory Transport Version: 1.1\n' > "$B/T/mf/fermeture/depot/$IDOS/version"
for g in $(jq -r '.config.digest, .layers[].digest' "$B/T/mf/fermeture/depot/$IDOS/manifest.json"); do
  "$CRANE" blob "$ADR/essais-05/rocky9-bootstrap@$g" > "$B/T/mf/fermeture/depot/$IDOS/${g#sha256:}"; done
liste_pod "$B/T/mf/fermeture" > "$B/pod-e.txt"
r=$(construire "$B/T/mf/fermeture" "$B/prim" "$IDOS" "$IBD" "$VSHA" "$MSHA" "$B/pod-e.txt" "$B/T/mf/fermeture.attendue")
egal "fermeture du banc (image du registre local en dossier dir:) : construire" "$r $(wc -l < "$B/T/mf/fermeture.attendue")" "0 231"
echo "$IBD" > "$B/T/boot-image.digest"
: > "$B/sur.args"; echo 1000000 > "$B/sur.n"
SUR='sur() { echo "$*" >> "$B/sur.args"
      case $* in
        *"df -B1"*) local n; n=$(cat "$B/sur.n"); echo $((n + 1000)) > "$B/sur.n"
          if [ "${SUR_CAS:-}" = illisible ] && [ "$(grep -c "df -B1" "$B/sur.args")" -gt 2 ]; then echo "df: refusé"; else echo "$n 999999999999"; fi ;;
        *"stat -c"*) echo "4242 2 4242 2" ;;
        *) echo "sur inattendu" >&2; return 1 ;;
      esac; }'
fermeture() { # préfixe [registre] : etape_fermeture de la copie, sortie dans $B/e.out, code rendu
  ( . "$B/f.sh"
    # shellcheck disable=SC2034  # lues par les fonctions chargées
    T=$B/T P=$B/P REG_HOTE=${2:-$ADR} REG=sc-stockage.poc.test:5000 PREFIXE=$1 CLOSURE=$CLOS ORAS=$ORASB
    export ORAS
    auth_zot() { echo '{}' > "$1"; }; oras_zot() { echo --plain-http; }; zot() { "$@"; }; crane() { "$CRANE" "$@"; }
    oras() { "$ORASB" "$@"; }
    eval "$SUR"
    set -euo pipefail; etape_fermeture ) > "$B/e.out" 2>&1; echo $?
}
restauration() {
  ( . "$B/f.sh"
    # shellcheck disable=SC2034
    T=$B/T P=$B/P REG_HOTE=$ADR REG=sc-stockage.poc.test:5000 CLOSURE=$CLOS ORAS=$ORASB
    export ORAS
    auth_zot() { echo '{}' > "$1"; }; oras_zot() { echo --plain-http; }
    eval "$SUR"
    set -euo pipefail; etape_restauration ) > "$B/e.out" 2>&1; echo $?
}
tags_locaux() { "$ORASB" repo tags --plain-http "$ADR/deps/sample-app/mock-buildroot-lock" 2>/dev/null | sort | paste -sd ' '; }
r=$(fermeture banc); sed 's/^/     /' "$B/e.out"
egal "fermeture : code" "$r" 0
egal "fermeture : catalogue lu, dépôt absent" "$(grep -c -E '^catalogue de Zot : [0-9]+ dépôts ; deps/sample-app/mock-buildroot-lock absent$' "$B/e.out")" 1
egal "fermeture : place lue quatre fois (deux avant, une après chaque envoi), liens relevés pour deux blobs" \
  "$(grep -c 'df -B1' "$B/sur.args") $(grep -c 'stat -c' "$B/sur.args")" "4 2"
egal "fermeture : commande de place" "$(grep 'df -B1' "$B/sur.args" | sort -u)" "sc-stockage df -B1 --output=used,avail /var/lib/zot | tail -n 1"
egal "fermeture : commande de liens (deux dépôts, blob par son nom)" "$(grep -m1 'stat -c' "$B/sur.args" | sed -E 's/[0-9a-f]{64}/<h>/')" \
  "sc-stockage for d in essais-05/rocky9-bootstrap deps/sample-app/mock-buildroot-lock; do stat -c '%i %h' /var/lib/zot/\$d/blobs/sha256/<h> 2>/dev/null || echo illisible; done | paste -sd ' '"
egal "fermeture : lignes de place et de liens" "$(grep -c -E '^/var/lib/zot avant l.envoi : utilisés 1000000 octets, puis 1001000 à une seconde lecture \(1000 octets de plus\) ; libres 999999999999 octets$' "$B/e.out") $(grep -c -x '/var/lib/zot, utilisés : envoi 1 : 1000 octets de plus ; envoi 2 : 1000 octets de plus' "$B/e.out") $(grep -c -E '^blob [0-9a-f]{12}… : inode et liens sous essais-05/rocky9-bootstrap puis deps/sample-app/mock-buildroot-lock : 4242 2 4242 2$' "$B/e.out")" "1 1 2"
egal "fermeture : portes" "$(grep -c -E '^OK   (blobs de l.image sous essais-05/rocky9-bootstrap = blobs du dossier dir:|digest du second envoi|digest du manifeste relu|couches du manifeste|couches \(titre, digest, taille\) = liste de collecte) : ' "$B/e.out")" 5
egal "fermeture : tags du registre local" "$(tags_locaux)" "banc banc-bis"
egal "fermeture : digest écrit" "$(cat "$B/T/mf/fermeture.digest")" "$(grep '^fermeture : ' "$B/e.out" | sed -n 's/^fermeture : sc-stockage.poc.test:5000\/deps\/sample-app\/mock-buildroot-lock@//p')"
egal "fermeture : titre d'une couche du dossier dir: (« : » et « @ » gardés)" \
  "$(jq -r --arg p "depot/$IDOS/manifest.json" '[.layers[] | select(.annotations["org.opencontainers.image.title"] == $p)] | length' "$B/T/mf/manifest.json")" 1
r=$(fermeture banc); egal "fermeture rejouée sous le même tag : dépôt présent, refusée avant envoi" \
  "$r $(grep -c -E '^catalogue de Zot : [0-9]+ dépôts ; deps/sample-app/mock-buildroot-lock présent, 2 tag\(s\)$' "$B/e.out") $(grep -c -x 'KO   tag banc ou banc-bis déjà présent' "$B/e.out") $(grep -c '^envoi ' "$B/e.out")" "1 1 1 0"
r=$(fermeture banc4 127.0.0.1:1); egal "catalogue illisible (registre injoignable) : refusée avant envoi" \
  "$r $(grep -c -x "KO   catalogue de Zot illisible : rien n'est envoyé" "$B/e.out") $(grep -c '^envoi ' "$B/e.out")" "1 1 0"
: > "$B/sur.args"; r=$(SUR_CAS=illisible fermeture banc3); sed 's/^/     /' "$B/e.out"
egal "place illisible après l'envoi : code 0, « illisible » affiché, même digest" \
  "$r $(grep -c -x '/var/lib/zot, utilisés : envoi 1 : illisible ; envoi 2 : illisible' "$B/e.out") $(grep -c '^OK   digest du second envoi : ' "$B/e.out") $(cat "$B/T/mf/fermeture.digest")" \
  "0 1 1 $(grep -m1 '^OK   digest du second envoi : ' "$B/e.out" | sed 's/^OK   digest du second envoi : //')"
echo x >> "$B/T/mf/fermeture/verrou.json"
r=$(fermeture banc2); egal "fermeture changée depuis collecte : refusée avant envoi" "$r $(grep -c -x 'KO   fermeture changée depuis collecte' "$B/e.out") $(grep -c '^envoi ' "$B/e.out")" "1 1 0"
egal "tags du registre local (ni banc2, ni banc4)" "$(tags_locaux)" "banc banc-bis banc3 banc3-bis"
: > "$B/sur.args"; r=$(restauration); sed 's/^/     /' "$B/e.out"
egal "restauration : code et conformité" "$r $(grep -c '^OK   arbre égal à la liste : 231 fichiers, ' "$B/e.out")" "0 1"
egal "restauration : liens relus pour deux blobs, place non lue" "$(grep -c 'stat -c' "$B/sur.args") $(grep -c 'df -B1' "$B/sur.args")" "2 0"
egal "restauration : dossier dir: recréé sous son nom" "$([ -f "$B/T/mf/restauree/depot/$IDOS/manifest.json" ] && echo présent)" présent
echo x >> "$B/T/mf/restauree/verrou.json"; r=$(restauration)
egal "restauration rejouée : dossier vidé puis conforme" "$r $(grep -c '^OK   arbre égal' "$B/e.out")" "0 1"

echo "## F : structure"
python3 -I - "$S1N" <<'PY' || ko=1
import re, sys
n = open(sys.argv[1], encoding='utf-8').read(); e = 0
def corps(f):
    i = n.index(f'\n{f}() {{\n'); return n[i:n.index('\n}\n', i)]
c, f, r, v = corps('etape_collecte'), corps('etape_fermeture'), corps('etape_restauration'), corps('etape_voie2')
g = lambda x, l: x[x.index('  ( attendu "verrou relu dans le pod"'):x.index('|| { pod_retirer "$n"; exit 1; }', x.index('  ( attendu "verrou relu dans le pod"'))].replace(l, 'X')
for nom, ok in [('trois étapes définies une fois', all(n.count(f'\netape_{x}() {{\n') == 1 for x in ('collecte', 'fermeture', 'restauration'))),
                ('collecte n écrit pas dans Zot (ni oras, ni closure, ni auth_zot, ni crane)', not re.search(r'oras|CLOSURE|auth_zot|crane', c)),
                ('collecte retire le pod sur ses trois échecs et à la fin', c.count('pod_retirer "$n"') == 4),
                ('collecte ne touche ni $T/m2 ni m2-voie2 ni POD_M2', not re.search(r'\$T/m2\b|m2-voie2|POD_M2', c)),
                ('porte voie2 de collecte égale à celle de etape_voie2 (libellé du journal mis à part)', g(c, 'mf-voie2') == g(v, 'm2-voie2')),
                ('fermeture et restauration sans kubectl', 'kubectl' not in f + r),
                ('fermeture pousse deux fois, restauration jamais', f.count('"$CLOSURE" push') == 2 and 'push' not in r and 'pull' not in f),
                ('nom du pod conforme (DNS-1123, 63 au plus) et distinct de POD_M2', re.search(r'^POD_MF=([a-z0-9-]{1,63})$', n, re.M) is not None and 'POD_MF=s1-05-m2\n' not in n)]:
    print(('OK   ' if ok else 'KO   ') + nom); e |= not ok
sys.exit(e)
PY

echo "## G : image d'essai"
egal "racine.tar (image d'essai), sha256 de l'étape racine" "$(sha256sum < "$TT/racine.tar" | cut -c1-64)" d7433a050469836de7317de87f2421d3bc7eaa52052cf422518809e276a94a9d
tar -tf "$TT/racine.tar" > "$B/racine.liste"
egal "commandes de SONDE_COLLECTE absentes de /usr/bin" "$(for x in curl rpm tar find stat sort sha256sum mv cp cut awk wc df mkdir rm; do grep -q -x "./usr/bin/$x" "$B/racine.liste" || echo "$x"; done | tr '\n' ' ')" ""
if [ $ko = 0 ]; then echo "# bilan : tenu, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; else echo "# bilan : NON TENU, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
exit $ko
