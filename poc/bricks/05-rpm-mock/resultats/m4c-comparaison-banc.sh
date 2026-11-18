#!/usr/bin/env bash
# Brique 05, M4c : banc hors cluster et hors Zot de l'étape comparaison de m4c.sh (préparée à sec le 18/11/2026, accord permanent
# du 18/11), écrit avant tout passage. Modèle : m4c-pipeline-banc.sh.
# A : insertions seules contre le m4c.sh d'avant (deux blocs : en-tête, bloc avant lancer) ; aucun nom de fonction ni de variable du
#     bloc déjà défini avant ; bash -n ; shellcheck : mêmes codes avant et après.
# B : la vraie fonction etape_comparaison, dans une copie jouable (commun.sh et lancer neutralisés, R redirigé dans le banc), avec le
#     vrai verrou, les vrais journaux archivés de construire (resultats/m4c-pipeline-1 et -2-construire.log) et, pour artefact, le
#     layout réel du pod d'essai (image.tar de l'étape essai, digest 07b7bd6f) ; le rpm de M3 du banc est celui de cette couche,
#     contrôlé par son sha256. Faux : kubectl (IMAGE_DIGEST des PipelineRuns, message de condition sentinelle), oras (cp : copie
#     d'un layout du banc). Cas : succès ; IMAGE_DIGEST divergent ; PipelineRun absent ; journal absent ; ligne de couche absente
#     du journal ; paquet hors verrou (ÉCART) ; échec d'oras ; manifeste à deux couches ; blob en plus ; configuration altérée ;
#     couche altérée ; rpm de M3 altéré. Dans chaque cas : seuls des appels de lecture (kubectl get pipelinerun, oras cp).
# C : la vraie fonction confronter_artefact seule : couche à deux membres (constantes de la copie remplacées par celles d'un layout
#     fabriqué) ; rpm de référence autre (deux ÉCART, aucun KO).
# Non couvert : Zot (lecture anonyme réelle, forme du layout écrit par oras cp), Tekton, Chains, réseau.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4c-comparaison-banc.sh <dossier-neuf> <m4c.sh avant> <m4c.sh>
set -uo pipefail
export LC_ALL=C
B=$1; AVANT=$2; COPIE=$3
RACINE=$PWD
ESSAI_TAR=${ESSAI_TAR:-$HOME/.cache/supply-chain-poc/08/travail/m4c-05/essai/image.tar}
ESSAI_TAR_SHA=cf482963d8e29726700e81d3b46ee9f09552542c0ae5cca1efafb1e6b62bbae8   # image.tar du pod d'essai (14:15, 18/11)
ESSAI=sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/kbin" "$B/layouts"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4c-comparaison-banc.sh, $(date -u +%FT%TZ) ; m4c.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; m4c.sh $(sha256sum < "$COPIE" | cut -c1-64)"

echo "## A : insertions seules, noms neufs, syntaxe, shellcheck"
diff "$AVANT" "$COPIE" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
grep '^>' "$B/diff.txt" | cut -c3- > "$B/ajout.txt"
sed -n 's/^\([a-z_][a-z_0-9]*\)() {.*/\1/p; s/^\([A-Z_][A-Z_0-9]*\)=.*/\1/p' "$B/ajout.txt" | sort > "$B/noms.txt"
echo "noms définis par l'ajout : $(paste -sd' ' "$B/noms.txt")"
egal "noms de l'ajout déjà définis avant" "$(while read -r x; do grep -c -E "^($x\(\) \{|$x=)" "$AVANT"; done < "$B/noms.txt" | awk '{s += $1} END {print s + 0}')" 0
egal "bash -n" "$(bash -n "$COPIE" && echo ok)" ok
sc() { LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$1" 2>/dev/null | grep -o 'SC[0-9]*' | sort | uniq -c; }
egal "shellcheck : mêmes codes avant et après" "$(diff <(sc "$AVANT") <(sc "$COPIE") > /dev/null && echo mêmes || echo différents)" mêmes

echo "## layouts du banc, tirés du layout réel de l'essai"
egal "image.tar de l'essai (sha256)" "$(sha256sum < "$ESSAI_TAR" | cut -c1-64)" "$ESSAI_TAR_SHA"
mkdir -p "$B/layouts/base" "$B/m3"
tar -xf "$ESSAI_TAR" -C "$B/layouts/base"
tar -xf "$B/layouts/base/blobs/sha256/ac3e3ef14c6e54fbba4f297b00f32bfeff840ef9bbe55a1a95bda853ee55e8e4" -C "$B/m3"
egal "rpm de la couche de l'essai = rpm de M3 (sha256)" "$(sha256sum < "$B/m3/sample-app-1.0.0-2.el9.x86_64.rpm" | cut -c1-64)" \
  864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f
python3 -I - "$B/layouts" "$B/m3/sample-app-1.0.0-2.el9.x86_64.rpm" <<'PY'
import hashlib, io, json, pathlib, shutil, sys, tarfile
L = pathlib.Path(sys.argv[1]); base = L / 'base'; rpm = pathlib.Path(sys.argv[2])
M, C, K = ('07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119', '48c5e33207f73ac7907cfae080f9fbd0a501d79565d06905688b351a53aa0cc4',
           'ac3e3ef14c6e54fbba4f297b00f32bfeff840ef9bbe55a1a95bda853ee55e8e4')
def copie(n):
    d = L / n; shutil.copytree(base, d); return d / 'blobs' / 'sha256'
b = copie('couches2'); m = json.loads((b / M).read_text()); m['layers'] = m['layers'] * 2; (b / M).write_text(json.dumps(m))
b = copie('blob_en_plus'); (b / ('e' * 64)).write_text('en plus')
b = copie('config_alteree'); c = json.loads((b / C).read_text()); c['rootfs']['diff_ids'] = ['sha256:' + 'f' * 64]; (b / C).write_text(json.dumps(c, separators=(',', ':')))
b = copie('couche_alteree'); x = bytearray((b / K).read_bytes()); x[-1] ^= 1; (b / K).write_bytes(bytes(x))
# couche à deux membres (section C) : layout fabriqué, digests écrits pour remplacer les constantes de la copie
d = L / 'couche_autre' / 'blobs' / 'sha256'; d.mkdir(parents=True)
f = io.BytesIO()
with tarfile.open(fileobj=f, mode='w', format=tarfile.PAX_FORMAT) as t:
    for nom, data in ((rpm.name, rpm.read_bytes()), ('en-plus.txt', b'en plus\n')):
        i = tarfile.TarInfo(nom); i.size = len(data); i.mode = 0o644; i.mtime = 0; t.addfile(i, io.BytesIO(data))
couche = f.getvalue(); kc = hashlib.sha256(couche).hexdigest(); (d / kc).write_bytes(couche)
cfg = json.dumps({'architecture': 'amd64', 'os': 'linux', 'rootfs': {'type': 'layers', 'diff_ids': ['sha256:' + kc]}}, separators=(',', ':')).encode()
cc = hashlib.sha256(cfg).hexdigest(); (d / cc).write_bytes(cfg)
man = json.dumps({'schemaVersion': 2, 'mediaType': 'application/vnd.oci.image.manifest.v1+json',
                  'config': {'mediaType': 'application/vnd.oci.image.config.v1+json', 'digest': 'sha256:' + cc, 'size': len(cfg)},
                  'layers': [{'mediaType': 'application/vnd.oci.image.layer.v1.tar', 'digest': 'sha256:' + kc, 'size': len(couche)}]},
                 separators=(',', ':')).encode()
mc = hashlib.sha256(man).hexdigest(); (d / mc).write_bytes(man)
(L / 'couche_autre' / 'index.json').write_text(json.dumps({'schemaVersion': 2, 'manifests': [{'mediaType': 'application/vnd.oci.image.manifest.v1+json', 'digest': 'sha256:' + mc, 'size': len(man)}]}))
(L / 'couche_autre.env').write_text(f'DIGEST_ESSAI=sha256:{mc}\nCOUCHE_ESSAI=sha256:{kc}\nCOUCHE_TAILLE={len(couche)}\nCONFIG_ESSAI=sha256:{cc}\n')
print('layouts écrits :', ' '.join(sorted(p.name for p in L.iterdir())))
PY
egal "layout de base : blobs" "$(find "$B/layouts/base/blobs" -type f | wc -l)" 3

# Copie jouable et faux outils
python3 -I - "$COPIE" "$B/m4c-jouable.sh" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text().split('\n')
r = {'. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, OUTILS, OUTILS_DIGEST, refus, bundle, auth_zot, lancer, chrono': ':',
     'h05=$(cd "$(dirname "$0")" && pwd)': 'h05=$RACINE/poc/bricks/05-rpm-mock',
     'R=$h05/resultats': 'R=$W/resultats',
     'lancer m4c "05 M4c" "$@"': ':'}
assert all(t.count(a) == 1 for a in r), [a for a in r if t.count(a) != 1]
pathlib.Path(sys.argv[2]).write_text('\n'.join(r.get(l, l) for l in t))
PY
cat > "$B/kbin/kubectl" <<'PY'
#!/usr/bin/env python3
# faux kubectl : get pipelinerun m4c-rpm-N -o json seulement (IMAGE_URL, IMAGE_DIGEST, condition avec message sentinelle)
import json, os, sys
a = sys.argv[1:]
open(os.environ['BANC_APPELS'], 'a').write('kubectl ' + ' '.join(a) + '\n')
cas = os.environ['BANC_CAS']
if a[:3] == ['get', 'pipelinerun', '-n'] and a[3] == 'builds' and a[5:] == ['-o', 'json']:
    pr = a[4]
    if cas == 'pr_absent' and pr == 'm4c-rpm-1':
        print(f'Error from server (NotFound): pipelineruns.tekton.dev "{pr}" not found', file=sys.stderr); sys.exit(1)
    d = 'sha256:' + 'b' * 64 if cas == 'digest_pr' and pr == 'm4c-rpm-2' else 'sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119'
    print(json.dumps({'metadata': {'name': pr}, 'status': {
        'conditions': [{'type': 'Succeeded', 'status': 'True', 'reason': 'Succeeded', 'message': 'SENTINELLE-MESSAGE'}],
        'results': [{'name': 'IMAGE_URL', 'value': 'sc-stockage.poc.test:5000/builds/sample-app-rpm'}, {'name': 'IMAGE_DIGEST', 'value': d}]}}))
    sys.exit(0)
print('appel non prévu : ' + ' '.join(a), file=sys.stderr); sys.exit(3)
PY
cat > "$B/kbin/oras" <<'PY'
#!/usr/bin/env python3
# faux oras : cp vers un layout seulement ; copie le layout du cas
import os, shutil, sys
a = sys.argv[1:]
open(os.environ['BANC_APPELS'], 'a').write('oras ' + ' '.join(a) + '\n')
if a[0] == 'cp' and '--to-oci-layout' in a and '--from-ca-file' in a:
    assert '192.168.161.13:5000/builds/sample-app-rpm@sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119' in a, a
    if os.environ['BANC_CAS'] == 'oras_echec':
        print('Error: failed to copy: banc', file=sys.stderr); sys.exit(1)
    shutil.copytree(os.environ['BANC_LAYOUT'], a[a.index('--to-oci-layout') + 1].rsplit(':', 1)[0], dirs_exist_ok=True)
    print('Copied [registry] 192.168.161.13:5000/builds/sample-app-rpm => [oci-layout] banc'); sys.exit(0)
print('appel non prévu : ' + ' '.join(a), file=sys.stderr); sys.exit(3)
PY
chmod +x "$B/kbin/kubectl" "$B/kbin/oras"

environnement() { # cas : W du cas (journaux archivés réels, rpm de M3 du banc), altérés selon le cas
  local c=$1 w=$B/$1/W
  mkdir -p "$w/resultats" "$w/s1-05/m3/build-1"
  cp "$RACINE"/poc/bricks/05-rpm-mock/resultats/m4c-pipeline-[12]-construire.log "$w/resultats/"
  cp "$B/m3/sample-app-1.0.0-2.el9.x86_64.rpm" "$w/s1-05/m3/build-1/"
  case $c in
    journal_absent) rm -- "$w/resultats/m4c-pipeline-2-construire.log" ;;
    journal_autre) sed -i 's/^couche sha256:ac3e3ef1/couche sha256:00000000/' "$w/resultats/m4c-pipeline-1-construire.log" ;;
    paquet_hors_verrou) sed -i '0,/^paquet \([^ ]*\) \([^ ]*\) /s//paquet \1 9.9.9 /' "$w/resultats/m4c-pipeline-1-construire.log" ;;
    m3_modifie) printf 'x' >> "$w/s1-05/m3/build-1/sample-app-1.0.0-2.el9.x86_64.rpm" ;;
  esac
}
jouer() { # cas : etape_comparaison de la copie jouable, sortie dans $B/<cas>.out ; code dans $B/<cas>.rc
  local c=$1 l=base
  case $1 in couches2|blob_en_plus|config_alteree|couche_alteree) l=$1 ;; esac
  environnement "$c"
  ( export BANC_CAS=$c BANC_APPELS=$B/$c/appels.txt BANC_LAYOUT=$B/layouts/$l RACINE PATH=$B/kbin:$PATH
    repo=$RACINE REG=sc-stockage.poc.test:5000 REG_HOTE=192.168.161.13:5000 P=$B/P W=$B/$c/W S=$B/S O=$B/O OUTILS=plateforme/outils OUTILS_DIGEST=sha256:0
    # shellcheck disable=SC1090
    . "$B/m4c-jouable.sh"
    { etape_comparaison; } 2>&1 ) > "$B/$c.out"
  echo $? > "$B/$c.rc"
  touch "$B/$c/appels.txt"
}
hors_lecture() { grep -v -c -E '^kubectl get pipelinerun -n builds m4c-rpm-[12] -o json$|^oras cp --no-tty --from-ca-file ' "$B/$1/appels.txt" || true; }
tirages() { grep -c '^oras cp ' "$B/$1/appels.txt" || true; }
sentinelle() { grep -c 'SENTINELLE' "$B/$1.out" || true; }
ko() { grep '^KO' "$B/$1.out"; }

echo "## B : etape_comparaison, faux kubectl et faux oras"
CAS="succes digest_pr pr_absent journal_absent journal_autre paquet_hors_verrou oras_echec couches2 blob_en_plus config_alteree couche_alteree m3_modifie"
for c in $CAS; do
  jouer "$c"
  echo "### cas $c : code $(cat "$B/$c.rc") ; tirages $(tirages "$c") ; appels hors lecture $(hors_lecture "$c") ; sentinelles $(sentinelle "$c")"
  grep -E '^(OK|KO)   |^ÉCART |écarts :' "$B/$c.out" | cut -c1-200 | sed 's/^/     /' | tail -n 4
  egal "$c : appels de lecture seulement" "$(hors_lecture "$c")" 0
  egal "$c : message de condition jamais affiché" "$(sentinelle "$c")" 0
done
egal "succes : code, tirages, OK, ÉCART ou KO" "$(cat "$B/succes.rc") $(tirages succes) $(grep -c '^OK   ' "$B/succes.out") $(grep -c '^ÉCART\|^KO' "$B/succes.out")" "0 1 21 0"
egal "succes : appels (deux lectures de PipelineRun, un tirage)" "$(wc -l < "$B/succes/appels.txt")" 3
egal "succes : membres imprimés, rpm tiré, écarts" \
  "$(grep -c '^membres de la couche (1) :$' "$B/succes.out") $(grep -c '^rpm tiré : sample-app-1.0.0-2.el9.x86_64.rpm, 2173376 octets, sha256 864d55f4' "$B/succes.out") $(grep '^écarts :' "$B/succes.out")" \
  "1 1 écarts : 0"
egal "succes : paquets confrontés au verrou" "$(grep -c '^m4c-rpm-[12] : paquets imprimés 222 ; lignes d.écart au verrou 0 ; 5 premières :$' "$B/succes.out")" 2
egal "succes : rpm extrait dans le dossier de travail" "$(sha256sum < "$B/succes/W/m4c-05/comparaison/travail/rpm/sample-app-1.0.0-2.el9.x86_64.rpm" | cut -c1-64)" \
  864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f
egal "digest_pr : code, tirages, KO" "$(cat "$B/digest_pr.rc") $(tirages digest_pr) $(ko digest_pr)" \
  "1 0 KO   IMAGE_DIGEST de m4c-rpm-2 (relu dans le cluster) : sha256:$(printf 'b%.0s' {1..64}) (attendu : $ESSAI)"
egal "pr_absent : code, tirages, KO" "$(cat "$B/pr_absent.rc") $(tirages pr_absent) $(ko pr_absent)" \
  "1 0 KO   IMAGE_DIGEST de m4c-rpm-1 (relu dans le cluster) :  (attendu : $ESSAI)"
egal "journal_absent : code, tirages, KO" "$(cat "$B/journal_absent.rc") $(tirages journal_absent) $(ko journal_absent)" \
  "1 0 KO   journal archivé de construire absent : $B/journal_absent/W/resultats/m4c-pipeline-2-construire.log"
egal "journal_autre : code, tirages, KO" "$(cat "$B/journal_autre.rc") $(tirages journal_autre) $(ko journal_autre)" \
  "1 0 KO   journal 1 de construire : couche, configuration et manifeste : 0 (attendu : 1)"
egal "paquet_hors_verrou : code, tirages, ÉCART, OK, écarts" \
  "$(cat "$B/paquet_hors_verrou.rc") $(tirages paquet_hors_verrou) $(grep '^ÉCART' "$B/paquet_hors_verrou.out") / $(grep -c '^OK   ' "$B/paquet_hors_verrou.out") $(grep '^écarts :' "$B/paquet_hors_verrou.out")" \
  "1 1 ÉCART m4c-rpm-1 : lignes d'écart au verrou (nom, version, release, arch, sigmd5) : 2 (attendu : 0) / 20 écarts : 1"
egal "paquet_hors_verrou : lignes d'écart imprimées" "$(grep -c '^     [<>] paquet ' "$B/paquet_hors_verrou.out")" 2
egal "oras_echec : code, KO, erreur d'oras imprimée avant" "$(cat "$B/oras_echec.rc") $(ko oras_echec) $(
  awk '/^Error: failed to copy: banc$/ && !e {e = NR} /^KO   oras cp/ && !q {q = NR} END {print (e && q && e < q) ? "avant" : "non"}' "$B/oras_echec.out")" \
  "1 KO   oras cp de l'artefact avant"
egal "couches2 : code, KO, manifeste à deux couches imprimé avant" "$(cat "$B/couches2.rc") $(grep -c '^KO   manifeste : sha256 des octets lus : ' "$B/couches2.out") $(
  awk '/^manifeste : .*"layers":\[\{.*\},\{.*\}\]\}$/ && !e {e = NR} /^KO   / && !q {q = NR} END {print (e && q && e < q) ? "avant" : "non"}' "$B/couches2.out")" "1 1 avant"
egal "blob_en_plus : code, KO" "$(cat "$B/blob_en_plus.rc") $(ko blob_en_plus)" "1 KO   blobs du layout : 4 (attendu : 3)"
egal "config_alteree : code, KO" "$(cat "$B/config_alteree.rc") $(grep -c '^KO   configuration : sha256 et taille des octets lus : ' "$B/config_alteree.out")" "1 1"
egal "couche_alteree : code, KO" "$(cat "$B/couche_alteree.rc") $(grep -c '^KO   couche : sha256 et taille des octets lus : ' "$B/couche_alteree.out")" "1 1"
egal "m3_modifie : code, tirages, KO" "$(cat "$B/m3_modifie.rc") $(tirages m3_modifie) $(grep -c '^KO   rpm de M3 (build 1) : ' "$B/m3_modifie.out")" "1 0 1"

echo "## C : confronter_artefact seule"
mkdir -p "$B/C/W" "$B/C/couche_autre" "$B/C/rpm_autre"
cp "$B/m3/sample-app-1.0.0-2.el9.x86_64.rpm" "$B/C/rpm-autre.rpm"; printf 'x' >> "$B/C/rpm-autre.rpm"
( export RACINE; repo=$RACINE REG=sc-stockage.poc.test:5000 REG_HOTE=192.168.161.13:5000 P=$B/P W=$B/C/W S=$B/S O=$B/O OUTILS=plateforme/outils OUTILS_DIGEST=sha256:0
  # shellcheck disable=SC1090
  . "$B/m4c-jouable.sh"
  # shellcheck disable=SC1091
  . "$B/layouts/couche_autre.env"
  { confronter_artefact "$B/layouts/couche_autre" "$B/C/couche_autre"; } 2>&1 ) > "$B/C/couche_autre.out"
echo $? > "$B/C/couche_autre.rc"
( export RACINE; repo=$RACINE REG=sc-stockage.poc.test:5000 REG_HOTE=192.168.161.13:5000 P=$B/P W=$B/C/W S=$B/S O=$B/O OUTILS=plateforme/outils OUTILS_DIGEST=sha256:0
  # shellcheck disable=SC1090
  . "$B/m4c-jouable.sh"
  RPM_M3=$B/C/rpm-autre.rpm; RPM_M3_SHA=$(sha256sum < "$RPM_M3" | cut -c1-64)
  { confronter_artefact "$B/layouts/base" "$B/C/rpm_autre"; echo "écarts : $ECARTS"; } 2>&1 ) > "$B/C/rpm_autre.out"
echo $? > "$B/C/rpm_autre.rc"
grep -E '^(OK|KO)   |^ÉCART |écarts :|^membres|^     -' "$B/C/couche_autre.out" "$B/C/rpm_autre.out" | cut -c1-200 | sed 's/^/     /' | tail -n 8
egal "couche_autre : code, OK avant le KO, membres imprimés avant" "$(cat "$B/C/couche_autre.rc") $(grep -c '^OK   ' "$B/C/couche_autre.out") $(
  awk '/^membres de la couche \(2\) :$/ && !e {e = NR} /^KO   couche : un membre, le rpm seul/ && !q {q = NR} END {print (e && q && e < q) ? "avant" : "non"}' "$B/C/couche_autre.out")" "1 8 avant"
egal "couche_autre : rien d'extrait" "$(find "$B/C/couche_autre" -name '*.rpm' | wc -l)" 0
egal "rpm_autre : code, ÉCART, KO, écarts" "$(cat "$B/C/rpm_autre.rc") $(grep -c '^ÉCART rpm tiré égal ' "$B/C/rpm_autre.out") $(grep -c '^KO' "$B/C/rpm_autre.out") $(grep '^écarts :' "$B/C/rpm_autre.out")" \
  "0 2 0 écarts : 2"
echo "# bilan : $n OK, $k KO ; fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
