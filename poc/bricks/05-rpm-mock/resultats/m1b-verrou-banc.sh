#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b : banc de m1b-verrou.sh (préparé à sec le 20/11/2026), écrit avant tout passage de l'étape. Rien n'est
# écrit dans Zot ni dans le cluster : lectures seules (Zot en lecture anonyme, politiques relues, pod en dry-run serveur).
# A : syntaxe, shellcheck ; blocs recopiés de s1.sh (extraits ici par awk, indépendamment du générateur) égaux aux originaux, et
#     présents une seule fois ; lignes de constantes égales à celles de s1.sh.
# B : constantes contre des sources indépendantes : m1b-provenance.sh (images), m4a.sh et s1.sh (verrou de référence, bootstrap de
#     S1), journal de verrou_derivee (configurations), builders/outillage-fichiers.txt (configuration de base de l'outillage).
# C : gardes jouées pour de vrai (lecture seule), puis refus quand le verrou de sortie existe déjà.
# D : controles_cfg et controles_journaux rejoués sur les vrais journaux du pod de verrou_derivee (17/11), reconstitués depuis
#     s1-verrou_derivee.log, et sur des copies altérées : code 1 et libellé du KO attendu.
# E : comparer_verrou sur un verrou attendu (b6d0f8f1 aux quatre feuilles prévues) puis sur des copies altérées.
# Usage (racine du dépôt) :
#   DISTRO=rke2 KUBECONFIG=… mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-verrou-banc.sh <dossier-neuf> <m1b-verrou.sh>
export LC_ALL=C DISTRO=${DISTRO:-rke2} PREFIXE=banc
B=$1; S05=$2
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/t" "$B/d" "$B/e"
D05=$PWD/poc/bricks/05-rpm-mock
S1=$D05/s1.sh
REF=$D05/resultats/s1-verrou_derivee.json
LOG17=$D05/resultats/s1-verrou_derivee.log
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; echo OK >> "$B/compte"; else echo "KO   $1 : $2 (attendu : $3)"; echo KO >> "$B/compte"; fi; }
echo "# m1b-verrou-banc.sh, $(date -u +%FT%TZ) ; m1b-verrou.sh $(sha256sum < "$S05" | cut -c1-64)"
# Le script sourcé dans des sous-shells, sans lancer (garde BASH_SOURCE) ; T et les sorties redirigés vers le banc
charger() { . "$S05"; set +e; T=$B/t; OUT=$B/sortie.json; MOCKLOG=$B/sortie-mock.log; }

echo "## A : syntaxe, shellcheck, copies de s1.sh"
egal "bash -n" "$(bash -n "$S05" && echo ok)" ok
egal "shellcheck : codes" "$(LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$S05" 2> /dev/null | grep -o 'SC[0-9]*' | sort -u | paste -sd' ')" "SC2015 SC2016 SC2154"
extraire() { # fichier nom : bloc extrait par awk (une ligne pour une fonction d'une ligne, sinon jusqu'à la fin du bloc)
  case $2 in
    attendu|champ) grep "^$2() {" "$1" ;;
    pod_spec) awk '/^pod_spec\(\) \{/ {p = 1} p {print} p && /^pod_retirer\(\) \{/ {exit}' "$1" ;;
    MOCK_CFG) awk '/^MOCK_CFG="/ {p = 1; print; next} p {print} p && $0 == "\"" {exit}' "$1" ;;
    *) awk -v d="^$2='" '$0 ~ d {p = 1; print; next} p {print} p && $0 == "true'"'"'" {exit}' "$1" ;;
  esac
}
for b in attendu champ pod_spec MOCK_CFG SONDE_VERROU SONDE_BOOT SONDE_CFG_DERIVEE SONDE_REPLI; do
  o=$(extraire "$S1" "$b" | sha256sum | cut -c1-64); c=$(extraire "$S05" "$b" | sha256sum | cut -c1-64)
  egal "$b : copie égale à s1.sh ($(extraire "$S1" "$b" | wc -l) ligne(s)), définie une fois" "$c $(grep -c "^$b\(() {\|=\)" "$S05")" "$o 1"
done
for v in VAULT97 BOOT_DIGEST DEPOT_AMONT BOOT LABEL LIMITES TMPFS PRIVILEGIE CFG CFG_DERIVE; do
  egal "ligne $v égale à s1.sh" "$(grep "^$v=" "$S05" | sha256sum | cut -c1-16) $(grep -c "^$v=" "$S05")" "$(grep "^$v=" "$S1" | sha256sum | cut -c1-16) 1"
done
egal "PKG = valeur par défaut de PACKAGING_DIR dans s1.sh" "$(grep -c '^PKG=\${PACKAGING_DIR:-\$HOME/.cache/supply-chain-poc/packaging}$' "$S1") $(grep -c '^PKG=\$HOME/.cache/supply-chain-poc/packaging ' "$S05")" "1 1"
egal "ISOLATION = valeur par défaut de s1.sh" "$(grep -c '^ISOLATION=\${ISOLATION:-simple}$' "$S1") $(grep -c '^ISOLATION=simple ' "$S05")" "1 1"

echo "## B : constantes contre des sources indépendantes"
( charger
  P05=$D05/m1b-provenance.sh
  egal "outillage = IMAGE_o et DIGEST_o de m1b-provenance.sh" "$REG/$DEPOT_OUTILLAGE@$DIGEST_OUTILLAGE" \
    "$(sed -n 's/^ *IMAGE_o=\$REG\/\([^;]*\); DIGEST_o=\(sha256:[0-9a-f]*\)$/\1@\2/p' "$P05" | sed "s|^|$REG/|")"
  egal "bootstrap = IMAGE_b et DIGEST_b de m1b-provenance.sh" "$REG/$DEPOT_BOOTSTRAP@$DIGEST_BOOTSTRAP" \
    "$(sed -n 's/^ *IMAGE_b=\$REG\/\([^;]*\); DIGEST_b=\(sha256:[0-9a-f]*\)$/\1@\2/p' "$P05" | sed "s|^|$REG/|")"
  egal "deux digests au journal des PipelineRuns (deux exécutions chacun)" \
    "$(grep -c -E "^OK   digest publié .* : ($DIGEST_OUTILLAGE|$DIGEST_BOOTSTRAP)$" "$D05/resultats/m1b-pipeline-pipeline.log")" 4
  egal "VERROU_REF_SHA = VERROU_SHA de m4a.sh = VERROU_DERIVEE_SHA de s1.sh" \
    "$(sed -n 's/^VERROU_SHA=\([0-9a-f]*\) .*/\1/p' "$D05/m4a.sh") $(sed -n 's/^VERROU_DERIVEE_SHA=\([0-9a-f]*\) .*/\1/p' "$S1")" "$VERROU_REF_SHA $VERROU_REF_SHA"
  egal "verrou de référence au journal de verrou_derivee" "$(grep -c "^     verrou : buildroot_lock.json [0-9]* octets, sha256 $VERROU_REF_SHA$" "$LOG17")" 1
  egal "DIGEST_DERIVE_S1 = PULL_DIGEST de m4a.sh" "$(sed -n 's/^PULL_DIGEST=\(sha256:[0-9a-f]*\) .*/\1/p' "$D05/m4a.sh")" "$DIGEST_DERIVE_S1"
  egal "MOCK_CFG_SHA = configuration de base relue dans le pod le 17/11" \
    "$(grep -c "^OK   configuration de base du pod égale à MOCK_CFG de s1.sh : sha256 $MOCK_CFG_SHA$" "$LOG17")" 1
  egal "CFG_DERIVE_S1_SHA = configuration dérivée du 17/11" "$(grep -c "^configuration dérivée : sha256 $CFG_DERIVE_S1_SHA$" "$LOG17")" 1
  egal "MOCK_CFG = etc/mock/$CFG.cfg de builders/outillage-fichiers.txt (couche de configuration de l'outillage)" \
    "$(printf '%s' "$MOCK_CFG" | sha256sum | cut -c1-64)" \
    "$(awk -v f="=== etc/mock/$CFG.cfg" '/^=== / {p = ($0 == f); next} p' "$D05/builders/outillage-fichiers.txt" | sha256sum | cut -c1-64)"
  egal "sources de sample-app : spec du cache égale au dépôt" "$(cmp -s "$PKG/sample-app.spec" "$repo/poc/packaging/sample-app.spec" && echo égal)" égal
)

echo "## C : gardes, pour de vrai (lecture seule : Zot anonyme, politiques, dry-run serveur)"
( charger; ( gardes banc-05-verrou ) > "$B/c.log" 2>&1; echo "code $?" >> "$B/c.log" )
sed 's/^/     /' "$B/c.log"
egal "gardes : code" "$(tail -1 "$B/c.log")" "code 0"
egal "gardes : lignes OK, aucune KO" "$(grep -c '^OK ' "$B/c.log") $(grep -c '^KO ' "$B/c.log")" "14 0"
egal "écarts de configuration imprimés : ancien et nouveau bootstrap" \
  "$(grep -c "^écart prévu : < .*essais-05/rocky9-bootstrap@sha256:f0ccf105" "$B/c.log") $(grep -c "^écart prévu : > .*builds/builders/rocky9-bootstrap@sha256:6de899ac" "$B/c.log")" "1 1"
egal "id attendu = configuration du manifeste de 6de899ac" "$(cat "$B/t/config-bootstrap")" "sha256:ff96017c3f06a35a11d06a454930ec797002708cd0187ac46d7febe0891444a2"
: > "$B/sortie.json"
( charger; ( gardes banc-05-verrou ) > "$B/c0.log" 2>&1; echo "code $?" >> "$B/c0.log" )
egal "gardes, verrou de sortie déjà présent : code, libellé" "$(tail -1 "$B/c0.log") $(grep -c '^KO   verrou ou journal de mock déjà écrit' "$B/c0.log")" "code 1 1"
find "$B" -maxdepth 1 -name sortie.json -delete

echo "## D : contrôles du pod rejoués sur les journaux du 17/11"
python3 -I - "$LOG17" "$B/d" <<'PY'
import sys
lignes, sortie = open(sys.argv[1], encoding='utf-8').read().split('\n'), sys.argv[2]
blocs, cour = [], None
for l in lignes:
    if l.startswith('     (code de l'):
        blocs.append(cour or []); cour = None
    elif l.startswith('     '):
        cour = (cour or []) + [l[5:]]
    else:
        cour = None
noms = ['verrou-derivee-cfg', 'verrou-derivee', 'verrou-derivee-repli', 'verrou-derivee-boot']
assert len(blocs) == 4, len(blocs)
for n, b in zip(noms, blocs):
    open(f'{sortie}/{n}.log', 'w', encoding='utf-8').write('\n'.join(b) + '\n')
print('journaux reconstitués :', ', '.join(f'{n} ({len(b)} lignes)' for n, b in zip(noms, blocs)))
PY
cp "$REF" "$B/d/verrou.json"
( charger; T=$B/d; ( controles_cfg "$CFG_DERIVE_S1_SHA" "$DIGEST_DERIVE_S1" ) > "$T/cfg.txt" 2>&1; echo "code $?" >> "$T/cfg.txt" )
egal "controles_cfg, journal du 17/11 et valeurs du 17/11 : code, OK" "$(tail -1 "$B/d/cfg.txt") $(grep -c '^OK ' "$B/d/cfg.txt")" "code 0 4"
( charger; T=$B/d; ( controles_cfg "$(derivee "$REG/$DEPOT_BOOTSTRAP@$DIGEST_BOOTSTRAP" | sha256sum | cut -c1-64)" "$DIGEST_BOOTSTRAP" ) > "$T/cfg2.txt" 2>&1; echo "code $?" >> "$T/cfg2.txt" )
egal "controles_cfg, journal du 17/11 et configuration neuve : code, KO V1" "$(tail -1 "$B/d/cfg2.txt") $(grep -c '^KO   V1 configuration dérivée livrée' "$B/d/cfg2.txt")" "code 1 1"
( charger; T=$B/d; ( controles_journaux ) > "$T/j.txt" 2>&1; echo "code $?" >> "$T/j.txt" )
sed 's/^/     /' "$B/d/j.txt"
egal "controles_journaux, journaux du 17/11 : code, OK" "$(tail -1 "$B/d/j.txt") $(grep -c '^OK ' "$B/d/j.txt")" "code 0 8"
cas_d() { # nom libellé-du-KO commande-d-alteration : copie de $B/d altérée, controles_journaux en code 1 avec le KO attendu
  local c=$B/d-$1
  cp -r "$B/d" "$c"
  (cd "$c" && eval "$3")
  ( charger; T=$c; ( controles_journaux ) > "$T/j.txt" 2>&1; echo "code $?" >> "$T/j.txt" )
  egal "D $1 : code, KO attendu" "$(tail -1 "$c/j.txt") $(grep -c "^KO   $2" "$c/j.txt")" "code 1 1"
}
cas_d srpm_rc "V3 mock --buildsrpm" "sed -i 's/^\(mock --buildsrpm (image dérivée) : rc \)0 /\11 /' verrou-derivee.log"
cas_d calc_rc "V3 mock --calculate-build-dependencies" "sed -i 's/^\(mock --calculate-build-dependencies : rc \)0 /\11 /' verrou-derivee.log"
cas_d bootstrap_mis_a_jour "V3 root.log" "sed -i '/Not updating bootstrap chroot/d' verrou-derivee.log"
cas_d repli "V4 repli" "sed -i '0,/ : 0 ligne(s) de repli/s// : 1 ligne(s) de repli/' verrou-derivee-repli.log"
cas_d boot_ecart "V5 bootstrap de mock contre image" "echo 'seulement dans le bootstrap de mock : x.x86_64 0:1-1 sigpgp=(none) rsaheader=(none)' >> verrou-derivee-boot.log"
cas_d boot_illisible "V5 bootstrap de mock et image lus" "sed -i 's/^\(bootstrap de mock : rpm -qa rc \)0, /\11, /' verrou-derivee-boot.log"
cas_d verrou_absent "V6 aucun verrou" "find . -maxdepth 1 -name verrou.json -delete"
cas_d verrou_altere "V6 verrou copié égal" "printf ' ' >> verrou.json"
cas_d verrou_jeton "V6 lignes du verrou au motif" "sed -i '2i \"token\": 1,' verrou.json; s=\$(sha256sum < verrou.json | cut -c1-64); sed -i \"s/^\(verrou : [^ ]* [0-9]* octets, sha256 \)[0-9a-f]*/\1\$s/\" verrou-derivee.log"

echo "## E : comparer_verrou"
python3 -I - "$REF" "$B/e" <<'PY'
import copy, json, sys
ref, d = json.load(open(sys.argv[1], encoding='utf-8')), sys.argv[2]
IMG = 'sc-stockage.poc.test:5000/builds/builders/rocky9-bootstrap@sha256:6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3'
def attendu():
    x = copy.deepcopy(ref)
    x['config']['bootstrap_image'] = IMG
    x['bootstrap'].update(pull_digest=IMG.split('@')[1], id='ff96017c3f06a35a11d06a454930ec797002708cd0187ac46d7febe0891444a2',
                          image_digest='e' * 64)
    return x
def ecrire(nom, x): json.dump(x, open(f'{d}/{nom}.json', 'w', encoding='utf-8'), indent=1)
ecrire('attendu', attendu())
ecrire('identique', copy.deepcopy(ref))
def alt(nom, f):
    x = attendu(); f(x); ecrire(nom, x)
r = lambda x: x['buildroot']['rpms']
alt('url', lambda x: r(x)[5].update(url=r(x)[5]['url'].replace('/9.7/', '/9.8/')))
alt('rpm_retire', lambda x: r(x).pop(7))
alt('rpm_double', lambda x: r(x).append(dict(r(x)[0])))
alt('signature', lambda x: r(x)[3].update(signature='abc'))
alt('option_en_plus', lambda x: x['config'].update(bootstrap_image_fallback=True))
alt('pas_prete', lambda x: x['config'].update(bootstrap_image_ready=False))
alt('pull_faux', lambda x: x['bootstrap'].update(pull_digest='sha256:' + '1' * 64))
alt('id_faux', lambda x: x['bootstrap'].update(id='2' * 64))
alt('version', lambda x: x.update(version='1.2.0'))
alt('autre_image', lambda x: x['config'].update(bootstrap_image=x['config']['bootstrap_image'].replace('6de899ac', '6de899ad')))
alt('macro', lambda x: x['config']['macros'].update({'%_buildhost': 'autre'}))
alt('image_digest_absent', lambda x: x['bootstrap'].pop('image_digest'))
alt('image_digest_inchange', lambda x: x['bootstrap'].update(image_digest=ref['bootstrap']['image_digest']))
print('copies écrites')
PY
comparer() { ( charger; comparer_verrou "$B/e/$1.json" "$REF" "$DIGEST_BOOTSTRAP" "$REG/$DEPOT_BOOTSTRAP@$DIGEST_BOOTSTRAP" \
  ff96017c3f06a35a11d06a454930ec797002708cd0187ac46d7febe0891444a2 > "$B/e/$1.txt" 2>&1; echo "code $?" >> "$B/e/$1.txt" ); }
comparer attendu
sed 's/^/     /' "$B/e/attendu.txt"
egal "E attendu : code, OK, KO" "$(tail -1 "$B/e/attendu.txt") $(grep -c '^OK ' "$B/e/attendu.txt") $(grep -c '^KO ' "$B/e/attendu.txt")" "code 0 7 0"
cas_e() { comparer "$1"; egal "E $1 : code, KO attendu" "$(tail -1 "$B/e/$1.txt") $(grep -c "^KO   $2" "$B/e/$1.txt")" "code 1 1"; }
cas_e identique C1; cas_e url C2; cas_e rpm_retire C2; cas_e rpm_double C2; cas_e signature C2; cas_e option_en_plus C1
cas_e pas_prete C3; cas_e pull_faux C3; cas_e id_faux C4; cas_e version C1; cas_e autre_image C3; cas_e macro C1
cas_e image_digest_absent C5; cas_e image_digest_inchange C1

( charger; find "$W" -maxdepth 1 -name banc-verrou-05 -empty -delete )
echo "# bilan : $(grep -c '^OK$' "$B/compte") OK, $(grep -c '^KO$' "$B/compte") KO ; fin $(date -u +%FT%TZ)"
[ "$(grep -c '^KO$' "$B/compte")" = 0 ]
