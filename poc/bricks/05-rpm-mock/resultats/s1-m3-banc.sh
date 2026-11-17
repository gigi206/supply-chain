#!/usr/bin/env bash
# Banc hors cluster des étapes m3_restauration, m3_build1, m3_build2 et m3_comparaison (s1-m3.patch), écrit le 17/11/2026
# avant tout passage. Ni cluster, ni Zot ; registre crane local en loopback (http, disque sous le dossier du banc) ; réseau non
# utilisé (les témoins TCP de la sonde passent par un faux bash).
# A : insertions seules ; la copie, blocs insérés retirés, redonne le s1.sh du dépôt octet pour octet.
# B : bash -n ; shellcheck : remarques de la copie comparées à celles du dépôt ; aucune de niveau warning ou error.
# C : motif installroot de la sonde contre les deux formes (« --installroot=… » et « '--installroot', '… »).
# D : etape_m3_restauration de la copie contre le registre local, avec le vrai closure.sh et le vrai oras : doublure de la
#     fermeture (vrai verrou, dossier dir: à « : » et « @ », un rpm factice de 2,5 Mio) poussée, puis deux restaurations
#     conformes ; digest différent de FERMETURE_DIGEST refusé avant tout pull.
# E : m3_build de la copie avec un faux kubectl qui joue le pod dans un dossier local (/w réécrit), faux bash (témoins TCP),
#     getent, mock et rpm ; copier en morceaux de 1 Mio (MORCEAU_MIO=1) : nominal pour les deux builds, puis refus : adresse
#     publique joignable (mock non lancé), label présent dans le cluster, spec refusée en dry-run, fermeture changée sur l'hôte
#     (aucun pod créé) ; pod retiré à chaque échec après sa création.
# F : etape_m3_comparaison sur les deux builds du banc : nominal ; rpm altéré et NEVRA illisibles comptés en écarts (pas
#     d'égalité à vide) ; paquet manquant au buildroot relevé sans écart.
# G : structure : étapes définies une fois, aucune écriture dans Zot, comparaison sans kubectl, noms de pods distincts.
# H : image d'essai (racine.tar lu par son nom) : commandes de SONDE_M3 dans /usr/bin.
# I : lignes de mock 6.9 citées dans les notes, relues dans l'archive des sources de M2 (sha256 3c034916…).
# Non couvert : vrai pod Kata, vraie politique Cilium, vrai mock et vrai rpm, exec Kata à 64 Mio, Zot (droits, lecture).
# Usage : s1-m3-banc.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier du banc, absent> [dossier T] [adresse]
set -uo pipefail
export LC_ALL=C
D=$1; S1N=$2; B=$3; TT=${4:-$HOME/.cache/supply-chain-poc/08/travail/s1-05}; ADR=${5:-127.0.0.1:5910}
S1A=$D/poc/bricks/05-rpm-mock/s1.sh; RES=$D/poc/bricks/05-rpm-mock/resultats; V=$RES/s1-verrou_derivee.json
CLOS=$D/poc/bricks/03-deps-closure/closure.sh
CRANE=$(cd "$D" && mise which crane); ORASB=$(cd "$D" && mise which oras)
[ ! -e "$B" ] || { echo "KO   $B existe déjà"; exit 1; }
! curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 || { echo "KO   $ADR déjà pris"; exit 1; }
mkdir -p "$B/bin" "$B/kbin" "$B/T" "$B/R" "$B/pkg"
echo "# s1-m3-banc.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), python3 $(python3 -I -c 'import sys; print(sys.version.split()[0])'), $("$ORASB" version | head -1 | tr -s ' '), crane $("$CRANE" version)"
echo "# s1.sh du dépôt $(sha256sum < "$S1A" | cut -c1-64) ; copie modifiée $(sha256sum < "$S1N" | cut -c1-64) ; closure.sh $(sha256sum < "$CLOS" | cut -c1-64)"
ko=0
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
egal() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else nok "$1 : $2 (attendu : $3)"; fi; }
VSHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f

echo "## A : insertions seules"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
python3 -I - "$S1A" "$S1N" <<'PY' || ko=1
import sys
a, n = (open(f, encoding='utf-8').read() for f in sys.argv[1:3])
d = n.index('#   m3_restauration (../s1-m3.patch'); f = n.index('# Les replis (stockage vfs')
e = n.index('# Étapes m3_restauration, m3_build1, m3_build2 et m3_comparaison'); g = n.index('lancer "$PREFIXE" "05 S1" "$@"\n')
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

echo "## C : motif installroot de la sonde"
SM=$(sed -n "/^SONDE_M3='/,/^true'\$/p" "$S1N")
egal "sonde extraite : première et dernière lignes" "$(printf '%s\n' "$SM" | sed -n '1p;$p' | paste -sd '|' -)" "SONDE_M3='set -u|true'"
egal "motif de la sonde" "$(printf '%s\n' "$SM" | grep -c -F '"installroot.{1,4}$B/mock-h/"')" 1
printf '%s\n' "DEBUG: Executing command: ['/usr/bin/dnf-3', '--installroot', '/w/b1/mock-h/hermetic-build/root/', 'install']" \
  "x --installroot=/w/b1/mock-h/hermetic-build/root/ y" "x --installroot /w/b2/mock-h/ y" > "$B/ir.txt"
egal "lignes trouvées pour /w/b1 (deux formes), aucune pour /w/b2" "$(grep -c -E 'installroot.{1,4}/w/b1/mock-h/' "$B/ir.txt") $(grep -c -E 'installroot.{1,4}/w/b2/mock-h/' "$B/ir.txt")" "2 1"

{ grep -E '^(VERROU_DERIVEE_SHA|POD_M2|POD_MF|POD_M3|DEPOT_FERMETURE|MOCK_CHEMIN|FERMETURE_DIGEST|RPM_HERMETIQUE|SRPM_HERMETIQUE|TEMOIN_HOTE|DEPOT_ESSAI|LIMITES|TMPFS|PRIVILEGIE)=' "$S1N"
  echo 'REG=sc-stockage.poc.test:5000'; echo 'LABEL=prefetch-rpm'; echo 'MORCEAU_MIO=1'; echo 'ISOLATION=simple'
  grep -E '^(attendu|champ|oras_zot|pod_retirer)\(\) ' "$S1N"
  for f in pod_spec pod_demarrer dans livrer fermeture_controle etape_m3_restauration copier m3_pod m3_build etape_m3_comparaison; do sed -n "/^$f() {/,/^}/p" "$S1N"; done
  grep -E '^(etape_m3_build1|etape_m3_build2|mesure_m3)\(\) ' "$S1N"; echo 'ECARTS_M3=0'
  printf '%s\n' "$SM"; } > "$B/f.sh"
egal "fragments extraits (fonctions attendues, une fois chacune)" "$(for x in 'attendu() ' 'champ() ' 'oras_zot() ' 'pod_retirer() ' 'pod_spec() ' 'pod_demarrer() ' 'dans() ' 'livrer() ' 'fermeture_controle() ' 'etape_m3_restauration() ' 'copier() ' 'm3_pod() ' 'm3_build() ' 'etape_m3_comparaison() ' 'etape_m3_build1() ' 'etape_m3_build2() ' 'mesure_m3() ' "SONDE_M3='" POD_M3= FERMETURE_DIGEST= TEMOIN_HOTE= MOCK_CHEMIN= DEPOT_FERMETURE=; do [ "$(grep -c -F -x -e "$x" <(cut -c1-${#x} "$B/f.sh"))" = 1 ] || printf '%s ' "$x"; done)" ""

echo "## D : m3_restauration contre un registre local"
python3 -I - "$B/arbre" "$V" <<'PY' > "$B/bd.txt"
import hashlib, json, os, sys
d, v = sys.argv[1:3]; h = lambda b: hashlib.sha256(b).hexdigest()
def ecrire(p, b): os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'wb').write(b)
gros = b''.join(hashlib.sha256(str(i).encode()).digest() for i in range(81920))   # 2,5 Mio, déterministe
ecrire(f'{d}/depot/gros-1.0-1.el9.x86_64.rpm', gros); ecrire(f'{d}/depot/petit-1.0-1.el9.noarch.rpm', b'rpm factice\n')
ecrire(f'{d}/depot/repodata/repomd.xml', b'<repomd/>\n')
cfg, cou = b'{"config":"factice"}', b'couche factice'
m = json.dumps({'schemaVersion': 2, 'config': {'digest': 'sha256:' + h(cfg), 'size': len(cfg)}, 'layers': [{'digest': 'sha256:' + h(cou), 'size': len(cou)}]}).encode()
dos = 'sc-stockage.poc.test@sha256:' + h(m)
ecrire(f'{d}/depot/{dos}/manifest.json', m); ecrire(f'{d}/depot/{dos}/version', b'Directory Transport Version: 1.1\n')
ecrire(f'{d}/depot/{dos}/{h(cfg)}', cfg); ecrire(f'{d}/depot/{dos}/{h(cou)}', cou)
ecrire(f'{d}/verrou.json', open(v, 'rb').read()); ecrire(f'{d}/outils/mock-6.9-1.el9.noarch.rpm', b'rpm de mock factice\n')
print('sha256:' + h(m))
PY
FBD=$(cat "$B/bd.txt"); echo "$FBD" > "$B/T/boot-image.digest"; echo sha256:image-du-banc > "$B/T/image.digest"
mkdir -p "$B/T/mf"
(cd "$B/arbre" && find . -type f -printf '%P\n' | sort | while IFS= read -r f; do echo "$f $(sha256sum < "$f" | cut -c1-64) $(stat -c %s "$f")"; done) > "$B/T/mf/fermeture.attendue"
egal "doublure : fichiers, verrou réel" "$(wc -l < "$B/T/mf/fermeture.attendue") $(sha256sum < "$B/arbre/verrou.json" | cut -c1-64)" "9 $VSHA"
mkdir -p "$B/disque"; "$CRANE" registry serve --address "$ADR" --disk "$B/disque" > "$B/serve.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null; wait $srv 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://$ADR/v2/" >/dev/null && ok "registre local prêt (http, $ADR)" || nok "registre local"
FD=$(ORAS=$ORASB ORAS_OPTS=--plain-http "$CLOS" push "$B/arbre" "$ADR/deps/sample-app/mock-buildroot-lock:banc"); FD=${FD#*@}
egal "doublure poussée par closure.sh, digest" "$([[ $FD =~ ^sha256:[0-9a-f]{64}$ ]] && echo lisible)" lisible
restauration() { # digest-de-fermeture.digest : etape_m3_restauration de la copie, sortie dans $B/e.out, code rendu
  echo "$1" > "$B/T/mf/fermeture.digest"
  ( . "$B/f.sh"
    # shellcheck disable=SC2034  # lues par les fonctions chargées
    T=$B/T P=$B/P REG_HOTE=$ADR CLOSURE=$CLOS ORAS=$ORASB FERMETURE_DIGEST=$FD
    export ORAS
    auth_zot() { echo '{}' > "$1"; }; oras_zot() { echo --plain-http; }
    set -euo pipefail; etape_m3_restauration ) > "$B/e.out" 2>&1; echo $?
}
r=$(restauration "$FD"); sed 's/^/     /' "$B/e.out"
egal "restauration : code, deux arbres conformes" "$r $(grep -c '^OK   arbre égal à la liste : 9 fichiers, ' "$B/e.out")" "0 2"
egal "restauration : dossier dir: recréé dans les deux arbres" "$(ls -d "$B/T/m3/restauree-1/depot/sc-stockage.poc.test@$FBD" "$B/T/m3/restauree-2/depot/sc-stockage.poc.test@$FBD" 2>/dev/null | wc -l)" 2
cp -a "$B/T/m3/restauree-1" "$B/garde-1"; echo x > "$B/T/m3/restauree-1/intrus"
r=$(restauration "sha256:$(printf '%064d' 0)")
egal "digest de fermeture.digest différent : refusé, aucun pull (intrus laissé)" "$r $(grep -c '^KO   digest écrit par l.étape fermeture' "$B/e.out") $([ -e "$B/T/m3/restauree-1/intrus" ] && echo laissé)" "1 1 laissé"
r=$(restauration "$FD"); egal "restauration rejouée : dossiers vidés puis conformes" "$r $(grep -c '^OK   arbre égal' "$B/e.out") $([ -e "$B/T/m3/restauree-1/intrus" ] && echo reste || echo parti)" "0 2 parti"

echo "## E : m3_build avec un faux kubectl"
cat > "$B/kbin/kubectl" <<'EOF'
#!/bin/bash
echo "$*" >> "$BANC/kubectl.args"
PW=$BANC/pod/w
sub() { sed "s#\(^\|[^A-Za-z0-9_.~-]\)/w\([/ \"']\|\$\)#\1$PW\2#g"; }
case $1 in
  delete|wait) exit 0 ;;
  create) if [[ " $* " == *" --dry-run=server "* ]]; then [ "${CAS:-}" = refus ] && exit 1; exit 0; fi
    rm -rf "$PW"; mkdir -p "$PW"; exit 0 ;;
  get) if [ "${CAS:-}" = label ]; then echo '{"metadata":{"labels":{"tekton.dev/task":"prefetch-rpm"}}}'; else echo '{"metadata":{"labels":{"app":"banc"}}}'; fi; exit 0 ;;
  exec) while [ "$1" != -- ]; do shift; done; shift
    if [ "$1" = sh ] && [ "$2" = -s ]; then tee "$BANC/sonde-recue.sh" | sub | PATH=$BANC/bin:$PATH sh -s; exit $?; fi
    if [ "$1" = sh ] && [ "$2" = -c ]; then c=$(printf '%s' "$3" | sub); PATH=$BANC/bin:$PATH sh -c "$c"; exit $?; fi
    a=(); for x in "$@"; do a+=("$(printf '%s' "$x" | sub)"); done; PATH=$BANC/bin:$PATH "${a[@]}"; exit $? ;;
esac
echo "kubectl inattendu : $*" >&2; exit 1
EOF
cat > "$B/bin/bash" <<'EOF'
#!/bin/bash
echo "$*" >> "$BANC/bash.args"
case $* in *dl.rockylinux.org/443*) [ "${CAS:-}" = public ] && exit 0; echo "connexion refusée (banc)"; exit 1 ;; *) exit 0 ;; esac
EOF
cat > "$B/bin/getent" <<'EOF'
#!/bin/bash
echo "192.0.2.1 $2"
EOF
cat > "$B/bin/mock" <<'EOF'
#!/bin/bash
echo "$*" >> "$BANC/mock.args"
for a; do case $a in --resultdir=*) res=${a#*=} ;; --config-opts=basedir=*) base=${a#*=basedir=} ;; esac; done
mkdir -p "$res" "$base/hermetic-build/root"
{ echo "INFO: Using container image: dir:/hermetic_repo/x"; echo "INFO: Checking image digest: $IMGD"
  echo "DEBUG: Executing command: ['/usr/bin/dnf-3', '--installroot', '$base/hermetic-build/root/', 'install', '*']"
  echo "DEBUG: baseurl=file:///hermetic_repo"; } > "$res/root.log"
echo "Wrote: sample-app" > "$res/build.log"; echo "bash-0:5.1.8-9.el9.x86_64 1 2 installed" > "$res/installed_pkgs.log"
printf 'src.rpm factice' > "$res/sample-app-1.0.0-2.el9.src.rpm"; printf 'rpm factice' > "$res/sample-app-1.0.0-2.el9.x86_64.rpm"
echo "Finish: rebuild"
EOF
cat > "$B/bin/rpm" <<'EOF'
#!/bin/bash
echo "$*" >> "$BANC/rpm.args"
case " $* " in
  *" -qa "*"--qf "*) jq -r '.buildroot.rpms[] | "paquet \(.name) \(.version) \(.release) \(.arch) \(.sigmd5)"' "$VERROU" | if [ "${CAS:-}" = paquet ]; then sed 1d; else cat; fi ;;
  *" -qa "*) jq -r '.buildroot.rpms[].name' "$VERROU" ;;
  *" -qp "*) f=${*: -1}; case $f in *mock-*) printf 'mock-6.9-1.el9.noarch %064d' 7 ;;
      *.src.rpm) printf 'sample-app-1.0.0-2.el9.src ; BUILDHOST reproducible ; BUILDTIME 1794787200' ;;
      *) printf 'sample-app-1.0.0-2.el9.x86_64 ; BUILDHOST reproducible ; BUILDTIME 1794787200' ;; esac ;;
  *" -q "*) printf 'mock-6.9-1.el9.noarch %064d' 7 ;;
esac
EOF
chmod +x "$B/bin/"* "$B/kbin/"*
printf 'tarball factice\n' > "$B/pkg/sample-app-1.0.0.tar.gz"; printf 'spec factice\n' > "$B/pkg/sample-app.spec"
(cd "$B/pkg" && sha256sum sample-app-1.0.0.tar.gz sample-app.spec) > "$B/T/SHA256SUMS.s1"
IMGD=$(jq -r '.bootstrap.image_digest' "$V")
build() { # n [cas] : m3_build de la copie, sortie dans $B/b.out, code rendu
  rm -f "$B/kubectl.args" "$B/mock.args" "$B/bash.args" "$B/sonde-recue.sh"
  ( . "$B/f.sh"
    # shellcheck disable=SC2034  # lues par les fonctions chargées
    T=$B/T R=$B/R P=$B/P PKG=$B/pkg PREFIXE=s1
    export BANC=$B CAS=${2:-} VERROU=$V IMGD=$IMGD PATH=$B/kbin:$PATH
    set -euo pipefail; "etape_m3_build$1" ) > "$B/b.out" 2>&1; echo $?
}
retire() { grep -c -x "delete pod -n builds s1-05-m3-$1 --wait=false" "$B/kubectl.args" 2>/dev/null || true; }
r=$(build 1); sed 's/^/     /' "$B/b.out"
egal "build 1 : code" "$r" 0
egal "build 1 : copie en morceaux de 1 Mio (tar de la fermeture)" "$(grep -c -E '^OK   copie de fermeture-1.tar dans le pod : [0-9]+ octets en [3-9] morceau\(x\), sha256 conforme$' "$B/b.out")" 1
egal "build 1 : dry-run avant la création, une création" "$(grep -n -E '^create ' "$B/kubectl.args" | sed -E 's/^([0-9]+):create (--dry-run=server )?.*/\2/' | paste -sd '|')" "--dry-run=server |"
egal "build 1 : spec sans label" "$(jq -c '.metadata.labels // "aucun"' "$B/T/s1-05-m3-1.json")" '"aucun"'
egal "build 1 : sonde reçue sans marque @…@" "$(grep -c -E '@[A-Z_]+@' "$B/sonde-recue.sh")" 0
egal "build 1 : chemins de mock sous /w/b1 (fermeture, basedir, cache, resultdir)" \
  "$(tr ' ' '\n' < "$B/mock.args" | grep -c -E "^($B/pod/w/b1/fermeture/verrou.json|$B/pod/w/b1/fermeture/depot|--config-opts=basedir=$B/pod/w/b1/mock-h|--config-opts=cache_topdir=$B/pod/w/b1/mock-h-cache|--resultdir=$B/pod/w/b1/res)\$")" 5
egal "build 1 : témoins (DNS, public, Zot) et porte" "$(grep -c -E '^(témoin DNS dl.rockylinux.org : rc 0|témoin TCP dl.rockylinux.org:443 \(10 s\) : rc 1 connexion refusée \(banc\) |témoin TCP sc-stockage.poc.test:5000 \(10 s\) : rc 0 |OK   témoin public : dl.rockylinux.org:443 injoignable)$' "$B/T/m3-build1.log")" 4
egal "build 1 : lignes comptées (image, digest, installroot ; aucune ligne http)" \
  "$(grep -c -E '^lignes « (Using container image: dir:|Checking image digest: [0-9a-f]{64}|installroot.\{1,4\}.*/b1/mock-h/) » : sortie 0 ; root.log 1$' "$B/T/m3-build1.log") $(grep -c -E '^lignes http ou https de (mock.out|root.log|build.log) : 0$' "$B/T/m3-build1.log")" "3 3"
egal "build 1 : paquets du buildroot relus (222) ; installed_pkgs.log lu" "$(grep -c '^paquet ' "$B/T/m3-build1.log") $(grep -c -x 'installed_pkgs.log : 1 ligne(s)' "$B/T/m3-build1.log")" "222 1"
egal "build 1 : journaux de mock archivés (quatre fichiers)" "$(grep -c '^### ' "$B/R/s1-m3_build1-mock.log")" 4
egal "build 1 : rpm rapatriés et portes" "$(ls "$B/T/m3/build-1" | paste -sd ' ') $(grep -c -E '^OK   (rpm rapatrié|rpm rapatriés|porte de la sonde|code de mock)' "$B/b.out")" "sample-app-1.0.0-2.el9.src.rpm sample-app-1.0.0-2.el9.x86_64.rpm 5"
egal "build 1 : pod retiré une fois" "$(retire 1)" 1
r=$(build 2); egal "build 2 : code, chemins sous /w/b2, pod retiré" "$r $(grep -c -e "--resultdir=$B/pod/w/b2/res" "$B/mock.args") $(retire 2)" "0 1 1"
cp -a "$B/T/m3/build-2" "$B/garde-build-2"; cp "$B/T/m3-build2.log" "$B/garde-m3-build2.log"
r=$(build 1 public); egal "adresse publique joignable : code 1, mock non lancé, pod retiré" \
  "$r $(grep -c -x 'KO   dl.rockylinux.org:443 joignable : mock non lancé' "$B/T/m3-build1.log") $([ -e "$B/mock.args" ] && echo lancé || echo 'non lancé') $(retire 1)" "1 1 non lancé 1"
r=$(build 1 label); egal "label présent dans le cluster : code 1, sonde non jouée, pod retiré" \
  "$r $([ -e "$B/sonde-recue.sh" ] && echo jouée || echo 'non jouée') $(retire 1)" "1 non jouée 1"
r=$(build 1 refus); egal "spec refusée en dry-run : code 1, aucune création" "$r $(grep -c -E '^create -f' "$B/kubectl.args" || true)" "1 0"
echo x >> "$B/T/m3/restauree-1/depot/petit-1.0-1.el9.noarch.rpm"
r=$(build 1); egal "fermeture changée sur l'hôte : code 1, aucun appel à kubectl" "$r $([ -e "$B/kubectl.args" ] && echo appelé || echo 'non appelé')" "1 non appelé"
rm -rf "$B/T/m3/restauree-1"; cp -a "$B/garde-1" "$B/T/m3/restauree-1"
r=$(build 1); egal "build 1 rejoué : code" "$r" 0

echo "## F : m3_comparaison"
comparaison() { ( . "$B/f.sh"; T=$B/T R=$B/R PREFIXE=s1; set -euo pipefail; etape_m3_comparaison ) > "$B/c.out" 2>&1; echo $?; }
r=$(comparaison); sed 's/^/     /' "$B/c.out"
egal "nominal : code et écarts" "$r $(grep -c -x 'écarts du critère : 0' "$B/c.out")" "0 1"
egal "nominal : mesures OK (verrou, nombre de rpm, lignes NEVRA, sha256, NEVRA)" "$(grep -c '^OK   ' "$B/c.out")" 5
egal "nominal : relevé d'hermetique (factices : 0 fois)" "$(grep -c -E '^relevé : sha256 [0-9a-f]{12}… d.hermetique .* build 1 : 0 fois ; build 2 : 0 fois$' "$B/c.out")" 2
egal "nominal : relevés par build (paquets 222 sans écart, aucune URL, mock égaux)" \
  "$(grep -c -E "^relevé, build [12] : (paquets du buildroot \(rpm --root\) 222, verrou 222 ; lignes d'écart \(nom, version, release, arch, sigmd5\) : 0|lignes http\(s\):// \(sortie, root.log, build.log\) : 0 0 0|mock de la fermeture : mock-6.9-1.el9.noarch 0{63}7 ; mock de l'image : mock-6.9-1.el9.noarch 0{63}7 ; égaux)$" "$B/c.out")" 6
echo x >> "$B/T/m3/build-2/sample-app-1.0.0-2.el9.x86_64.rpm"
r=$(comparaison); egal "rpm du build 2 altéré : code 1, un écart, diffoscope signalé" "$r $(grep -c -x 'écarts du critère : 1' "$B/c.out") $(grep -c 'diffoscope à demander' "$B/c.out")" "1 1 1"
rm -rf "$B/T/m3/build-2"; cp -a "$B/garde-build-2" "$B/T/m3/build-2"
sed -i '0,/^paquet /{/^paquet /d}' "$B/T/m3-build2.log"
r=$(comparaison); egal "paquet manquant au buildroot du build 2 : relevé seulement, code 0, une ligne d'écart relevée" \
  "$r $(grep -c -x 'écarts du critère : 0' "$B/c.out") $(grep -c -E "^relevé, build 2 : paquets du buildroot \(rpm --root\) 221, verrou 222 ; lignes d'écart .* : 1$" "$B/c.out")" "0 1 1"
cp "$B/garde-m3-build2.log" "$B/T/m3-build2.log"
sed -i 's/ ; NEVRA sample-app-1.0.0-2.el9.src ;/ ;/' "$B/T/m3-build2.log"
r=$(comparaison); egal "NEVRA du src.rpm illisible au build 2 : code 1, deux écarts (nombre de lignes, NEVRA)" \
  "$r $(grep -c -x 'écarts du critère : 2' "$B/c.out") $(grep -c -x 'ÉCART lignes NEVRA lues par build : 2 1 (attendu : 2 2)' "$B/c.out")" "1 1 1"
for n in 1 2; do sed -i 's/ ; NEVRA [^ ]* ;/ ;/' "$B/T/m3-build$n.log"; done
r=$(comparaison); egal "NEVRA illisibles aux deux builds : code 1, pas d'égalité à vide" \
  "$r $(grep -c -x 'ÉCART lignes NEVRA lues par build : 0 0 (attendu : 2 2)' "$B/c.out")" "1 1"
cp "$B/garde-m3-build2.log" "$B/T/m3-build2.log"

echo "## G : structure"
python3 -I - "$S1N" <<'PY' || ko=1
import re, sys
n = open(sys.argv[1], encoding='utf-8').read(); e = 0
def corps(f):
    i = n.index(f'\n{f}() {{'); return n[i:n.index('\n}\n', i)]
r, b, c, p = corps('etape_m3_restauration'), corps('m3_build'), corps('etape_m3_comparaison'), corps('m3_pod')
for nom, ok in [('quatre étapes définies une fois', all(n.count(f'\netape_m3_{x}() {{') == 1 for x in ('restauration', 'build1', 'build2', 'comparaison'))),
                ('aucune écriture dans Zot (ni push, ni crane, ni oras hors de closure.sh pull)', not re.search(r'push|crane|oras ', r + b + c + p)),
                ('restauration lit par FERMETURE_DIGEST seulement', r.count('"$CLOSURE" pull "$REG_HOTE/$DEPOT_FERMETURE@$FERMETURE_DIGEST"') == 1),
                ('comparaison sans kubectl ni Zot', not re.search(r'kubectl|CLOSURE|auth_zot', c)),
                ('build : une seule création de pod, par m3_pod ; dry-run avant', 'pod_demarrer' not in b and p.count('pod_demarrer "$1"') == 1 and p.index('--dry-run=server') < p.index('pod_demarrer "$1"')),
                ('build ne lit ni $T/m2, ni voie2, ni le verrou de resultats/', not re.search(r'\$T/m2\b|voie2|\$R/s1-verrou', b)),
                ('noms de pods conformes et distincts', re.search(r'^POD_M3=([a-z0-9-]{1,61})$', n, re.M) is not None and len({re.search(rf'^{x}=(\S+)', n, re.M).group(1) for x in ('POD_M2', 'POD_MF', 'POD_M3')}) == 3)]:
    print(('OK   ' if ok else 'KO   ') + nom); e |= not ok
sys.exit(e)
PY

echo "## H : image d'essai"
egal "racine.tar (image d'essai), sha256 de l'étape racine" "$(sha256sum < "$TT/racine.tar" | cut -c1-64)" d7433a050469836de7317de87f2421d3bc7eaa52052cf422518809e276a94a9d
tar -tf "$TT/racine.tar" > "$B/racine.liste"
egal "commandes de SONDE_M3 et des exec absentes de /usr/bin" "$(for x in sh bash getent timeout rpm mock sha256sum find df tar head stat mkdir rm cat sed ls wc awk paste tr date uname nproc id grep sort cut; do grep -q -x "./usr/bin/$x" "$B/racine.liste" || echo "$x"; done | tr '\n' ' ')" ""
echo "## I : lectures de mock 6.9 citées (archive des sources de M2)"
ARC=$HOME/.cache/supply-chain-poc/05/m2/mock.tar.gz   # archive de m2-releve (sha256 contrôlé ci-dessous)
egal "archive des sources de mock 6.9-1, sha256 (m2-releve.log)" "$(sha256sum < "$ARC" | cut -c1-64)" 3c034916a721bb06b923399c856d5111fbf3d791804934dd6d909e3d292e4d88
lire() { tar -xzOf "$ARC" "mock-mock-6.9-1/mock/py/mockbuild/$1" | sed -n "$2p"; }
for x in "config.py|98|    config_opts['rpmbuild_networking'] = False" "config.py|210|            'installed_pkgs': True," \
  "package_manager.py|238|            invocation += ['--installroot', self.buildroot.make_chroot_path('')]" \
  "plugins/package_state.py|70|        out_file = self.buildroot.resultdir + '/installed_pkgs.log'" \
  "backend.py|63|        self.private_network = not config['rpmbuild_networking']"; do
  IFS='|' read -r f l t <<<"$x"; egal "$f:$l" "$(lire "$f" "$l")" "$t"
done
egal "config.py : chroothome (chemin de build dans le chroot, le même pour les deux builds)" "$(tar -xzOf "$ARC" mock-mock-6.9-1/mock/py/mockbuild/config.py | grep -n -F "config_opts['chroothome'] = " | head -1)" "$(tar -xzOf "$ARC" mock-mock-6.9-1/mock/py/mockbuild/config.py | grep -n -F "config_opts['chroothome'] = '/builddir'" | head -1)"
if [ $ko = 0 ]; then echo "# bilan : tenu, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; else echo "# bilan : NON TENU, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
exit $ko
