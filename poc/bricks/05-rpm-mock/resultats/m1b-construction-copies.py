#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b, M4c refait : copies de m1b-construction.sh contrôlées contre m4c.sh et m1b-bundles.sh (section A du
# banc).
#   verifier  la zone entre les deux marqueurs est égale, octet pour octet, à ce qu'assembler écrirait : blocs recopiés à
#             l'identique, dans l'ordre, puis entrees_hote, etape_local, etape_essai_preparer et etape_essai, chacune obtenue par
#             les remplacements listés ici, chacun compté ; aucune variable inconnue ; un « OK » par contrôle.
#   assembler écrit la zone depuis les deux sources, puis vérifie (préparation seulement).
#   compter   imprime, pour chaque remplacement, le nombre d'occurrences dans le bloc source (préparation seulement).
# Les lignes masquées des sources (motif jeton|token) ne sont jamais imprimées : elles sont copiées mécaniquement.
# Usage : python3 -I m1b-construction-copies.py verifier|assembler|compter <dossier de la 05>
import sys

mode, d = sys.argv[1:3]
CIBLE = 'm1b-construction.sh'
DEBUT, FIN = '# --- recopié de m4c.sh et m1b-bundles.sh ---', '# --- fin des copies ---'
COPIES_M4C = ['attendu', 'ref_revue', 'remplacer', 'rendre_taches', 'rendre_pipeline', 'script_etape', 'bb_liens', 'modes',
              'faux_rpm', 'mesure', 'pod_retirer', 'copier_pod', 'liste_arbre', 'politique_relue', 'echec', 'normaliser']
COPIES_BUNDLES = ['neuf', 'sha']
OK = 0


def ok(m):
    global OK
    OK += 1
    print(f'OK   {m}')


def lignes(f):
    return open(f'{d}/{f}', encoding='utf-8').read().split('\n')


def bloc(L, nom):
    if nom in HEREDOCS:   # affectation par heredoc : de la ligne d'ouverture à la parenthèse fermante
        o, f = HEREDOCS[nom]
        assert L.count(o) == 1, (nom, L.count(o))
        i = L.index(o)
        j = L.index(f, i)
        assert L[j + 1] == ')', (nom, L[j + 1])
        return L[i:j + 2]
    if nom.endswith('='):   # affectation d'une ligne (copiée sans être imprimée)
        deb = [k for k, l in enumerate(L) if l.startswith(nom)]
        assert len(deb) == 1, (nom, deb)
        return [L[deb[0]]]
    deb = [k for k, l in enumerate(L) if l.startswith(nom + '() {')]
    assert len(deb) == 1, (nom, deb)
    i = deb[0]
    if L[i].count('{') == L[i].count('}') and not L[i].rstrip().endswith('<<\'FIN\''):
        return [L[i]]   # fonction d'une ligne
    j = L.index('}', i)
    return L[i:j + 1]


# (ancien, nouveau, occurrences attendues dans le bloc source)
T_ENTREES = [
    ('  cp "$SPEC" "$VERROU" "$1/packaging/"',
     '  cp "$SPEC" "$1/packaging/"\n'
     '  cp "$VERROU" "$1/packaging/verrou-rpm.json"   # nom du fichier dans l\'artefact 333b7322 (m1b-artefact-local.log)', 1),
]
T_LOCAL = [
    ('etape_prealables() { # hôte seul, hors ligne, sans cluster ni Zot',
     'etape_local() { # hôte seul, hors ligne, sans cluster ni Zot ; etape_prealables de m4c.sh, transformée', 1),
    ('  local x=$T/prealables e f a s d', '  local x=$T/local e f a s d', 1),
    ('  # Corrigé le 18/11/2026 après le second passage (rm refusé : le cache de modules de go est en lecture seule, comme sources.sh) :\n'
     '  [ ! -d "$x" ] || chmod -R u+w "$x"\n'
     '  rm -rf -- "${x:?}"; mkdir -p "$x"',
     '  neuf "$x"; mkdir -p "$x"   # dossier neuf : rien n\'est retiré\n'
     '  echo "## sources de la cascade"\n'
     '  sources_cascade', 1),
    ('verrou du dépôt', 'verrou de M1b', 2),
    ('"fermeture rpm tirée par comparaison (M4b) : fichiers sous depot/"',
     '"fermeture rpm tirée par la comparaison de M4b refait : fichiers sous depot/"', 1),
    ('  rendre_pipeline "$REG/tekton/tasks/preparer-rpm@$FACTICE" "$REG/tekton/tasks/construire-rpm@$FACTICE" "$PUBLIER_REF"',
     '  rendre_pipeline "$REG/tekton/tasks/preparer-rpm@$FACTICE" "$REG/tekton/tasks/construire-rpm@$FACTICE" "$PUBLIER_REF"\n'
     '  signees_egales', 1),
    ('"sc-stockage.poc.test@sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6 $(jq -r \'.bootstrap.image_digest\' "$VERROU")"',
     '"$BOOT_DOSSIER $IMAGE_DIGEST_BOOT"', 1),
]
T_PREPARER = [
    ('  local p=m4c-essai-preparer x=$T/essai-preparer a c r', '  local p=$N-construction-preparer x=$T/essai-preparer a c r', 1),
    ('  [ -d "$T/prealables/ws/entrees" ] || { echo "KO   lancer d\'abord prealables" >&2; exit 1; }',
     '  [ -d "$T/local/ws/entrees" ] || { echo "KO   lancer d\'abord local" >&2; exit 1; }\n'
     '  neuf "$R/$N-construction-preparer-pod.log"', 1),
    ('  rm -rf "$x"; mkdir -p "$x"', '  neuf "$x"; mkdir -p "$x"', 1),
    ("  trap 'kubectl delete pod -n builds m4c-essai-preparer --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true' EXIT",
     '  trap "kubectl delete pod -n builds $p --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true" EXIT', 1),
    ('"$R/m4c-essai-preparer-pod.log"', '"$R/$N-construction-preparer-pod.log"', 1),
    ('(cd "$T/prealables/ws/entrees"', '(cd "$T/local/ws/entrees"', 1),
    ('dans prealables"', 'dans local"', 1),
    ('égal à celui de prealables (contenu', 'égal à celui de local (contenu', 1),
]
T_ESSAI = [
    ('etape_essai_construire() {', 'etape_essai() {', 1),
    ('  local p=$N-bundles-construire x=$T/essai-construire rc=0 d s', '  local p=$N-construction-construire x=$T/essai-construire rc=0 d s j=$R/$N-construction-local.log', 1),
    ('  attendu "entrees.tar de m4c prealables (taille, sha256)" "$(stat -c %s "$ENTREES") $(sha "$ENTREES")" "$ENTREES_TAILLE $ENTREES_SHA"',
     '  [ -s "$j" ] && [ -s "$T/entrees.tar" ] || echec "lancer d\'abord local (journal resultats/${j##*/} et entrees.tar)"\n'
     '  attendu "entrees.tar de local (taille, sha256), égal au journal de local" "$(stat -c %s "$T/entrees.tar") $(sha "$T/entrees.tar")" \\\n'
     '    "$(sed -n \'s/^entrees.tar : \\([0-9]*\\) octets, sha256 \\([0-9a-f]\\{64\\}\\)$/\\1 \\2/p\' "$j")"\n'
     '  neuf "$R/$N-construction-construire-pod.log"', 1),
    ('  rendre "$T" "$IMAGE_NEUVE"', '  rendre_taches', 1),
    ('$IMAGE_NEUVE', '$IMAGE_OUTILLAGE', 2),
    ('"$ENTREES"', '"$T/entrees.tar"', 1),
    ('$N-bundles-construire-pod.log', '$N-construction-construire-pod.log', 3),
    ('  mesure "Source0 faite par le tar et le gzip de l\'image d\'outillage, égale à l\'archive de sources.sh" "$s" "$ARCHIVE_SHA"',
     '  mesure "Source0 faite par le tar et le gzip de l\'image d\'outillage, égale à l\'archive de sources.sh" "$s" "$ARCHIVE_SHA"\n'
     '  hermetique "$x/construire.log"', 1),
    ('"$VERROU_ESSAI"', '"$VERROU"', 1),
]
TRANSFORMEES = [('m4c.sh', 'entrees_hote', T_ENTREES), ('m4c.sh', 'etape_prealables', T_LOCAL),
                ('m4c.sh', 'etape_essai_preparer', T_PREPARER), ('m1b-bundles.sh', 'etape_essai_construire', T_ESSAI)]


def transformer(src, nom, T, compter=False):
    t = '\n'.join(bloc(lignes(src), nom))
    for a, b, n in T:
        c = t.count(a)
        if compter:
            print(f'{src} {nom} : {c} occurrence(s) attendue(s) {n}')
        else:
            assert c == n, (src, nom, a[:60], c, n)
            ok(f'{nom} : remplacement compté ({n}) : {a.splitlines()[0][:70]}')
        t = t.replace(a, b)
    return t


# Ajout du 20/11/2026, après la décision « Même dépôt » : seconde zone, pour les étapes pipeline et construction.
DEBUT2, FIN2 = '# --- recopié pour la pipeline (m4c.sh, m1b-bundles.sh, m1b-fermeture.sh) ---', '# --- fin des copies pour la pipeline ---'
HEREDOCS = {'DIFF_FEUILLES': ("DIFF_FEUILLES=$(cat <<'PY'", 'PY')}
COPIES2 = [('m4c.sh', ['MASQUE=', 'admission', 'libre_zot', 'pr_m4c', 'statut_pr', 'attendre_pr', 'releve_pod', 'lignes']),
           ('m1b-bundles.sh', ['zot_lire', 'DIFF_FEUILLES', 'diff_feuilles']),
           ('m1b-fermeture.sh', ['lire_manifeste'])]
T_LIRE_BUNDLE = [('pipeline prefetch-rpm-sample-app', 'pipeline sample-app-rpm', 2)]
T_PIPELINE = [
    ('  local x=$T/pipeline v=$TACHES/prefetch-rpm-sample-app.$TAG.signee.yaml src dos p libre',
     '  local x=$T/pipeline v=$C/sample-app-rpm.$TAG.signee.yaml p libre', 1),
    ('  sources\n  attendu "arbre de l\'essai archivé (sha256), égal à l\'arbre prédit" "$(sha "$ARBRE_ESSAI")" "$ARBRE_PREDIT_SHA"',
     '  sources_cascade\n'
     '  attendu "essai archivé (resultats/$N-construction-essai.log) : digest de l\'artefact, sans écart" \\\n'
     '    "$(sed -n \'s/^OK   digest de l.artefact, égal à celui de l.essai de M4c : //p\' "$R/$N-construction-essai.log") $(grep -c \'^écarts : 0$\' "$R/$N-construction-essai.log")" "$DIGEST_ESSAI 1"', 1),
    ('tekton/pipelines/prefetch-rpm-sample-app:$TAG', 'tekton/pipelines/sample-app-rpm:$TAG', 2),
    ('"tag m4b de la pipeline, sur celle de M4b"', '"tag m4c de la pipeline, sur celle de M4c"', 1),
    ('"tag m4b de la pipeline, inchangé"', '"tag m4c de la pipeline, inchangé"', 1),
    ('"tag m4b"', '"tag m4c"', 2),
    ('tekton/pipelines/prefetch-rpm-sample-app:m4b', 'tekton/pipelines/sample-app-rpm:m4c', 2),
    ('"${PIPELINE_M4B##*@}"', '"${PIPELINE_M4C##*@}"', 2),
    ('  attendu "prefetch-rpm de la cascade, lue dans la liste revue" "$(ref_revue prefetch-rpm b9bbeba3)" "$PREFETCH_REF"\n'
     '  attendu "publier-fermeture, lue dans la liste revue" "$(ref_revue publier-fermeture 7fa92ad3)" "$PUBLIER_REF"',
     '  attendu "preparer-rpm de M4c, lue dans la liste revue" "$(ref_revue preparer-rpm 2f65f390)" "$PREPARER_REF"\n'
     '  attendu "construire-rpm de la cascade, lue dans la liste revue" "$(ref_revue construire-rpm ca03f189)" "$CONSTRUIRE_REF"\n'
     '  attendu "publier-image, lue dans la liste revue" "$(ref_revue publier-image d21931f3)" "$PUBLIER_REF"', 1),
    ('(références de la liste revue, bootstrap de M1b)', '(références de la liste revue, fermeture et artefact de la cascade)', 1),
    ('  read -r src dos < <(source_dossier "$VERROU_SRC")\n  (T=$x; rendre_taches "$PREFETCH_REF" "$PUBLIER_REF" "$src" "$dos")',
     '  (T=$x; rendre_pipeline "$PREPARER_REF" "$CONSTRUIRE_REF" "$PUBLIER_REF")', 1),
    ('  substituer "$SIGNEE" "$x/prefetch-rpm-sample-app.yaml" /workspace/sortie /tmp/resultat-bootstrap.json "$x/script.sh"\n'
     '  attendu "script de la tâche substitué avec la pipeline rendue, celui de l\'essai (sha256)" "$(sha "$x/script.sh")" "$SCRIPT_NEUF_SHA"',
     '  attendu "pipeline rendue : références des tâches (bundles)" \\\n'
     '    "$(yq \'[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")\' "$x/sample-app-rpm.yaml")" "$PREPARER_REF $CONSTRUIRE_REF $PUBLIER_REF"', 1),
    ('$x/prefetch-rpm-sample-app.yaml', '$x/sample-app-rpm.yaml', 3),
    ('bundle-m4b', 'bundle-m4c', 4),
    ('lire_bundle "$PIPELINE_M4B"', 'lire_bundle "$PIPELINE_M4C"', 1),
    ('"rendue : feuilles différentes de la pipeline de M4b"', '"rendue : feuilles différentes de la pipeline de M4c"', 1),
    ('signature versionnée : fermeture/${v##*/}', 'signature versionnée : construction/${v##*/}', 1),
    ('tekton/pipelines/prefetch-rpm-sample-app', 'tekton/pipelines/sample-app-rpm', 2),
    ("avant l'étape rpm : $p", "avant l'étape construction : $p", 1),
]
T_CONSTRUCTION = [
    ("etape_pipeline() { # deux PipelineRuns de sample-app-rpm (m4c-rpm-1, puis m4c-rpm-2) ; rien n'est purgé ; artefact comparé à l'essai",
     "etape_construction() { # deux PipelineRuns de sample-app-rpm ($N-construction-1, puis -2) ; rien n'est purgé ; artefact comparé à\n"
     "  # l'essai ; etape_pipeline de m4c.sh, transformée", 1),
    ('  [ -s "$T/sample-app-rpm.ref" ] || echec "référence de la pipeline absente (étape taches)"\n'
     '  attendu "pipeline écrite par l\'étape taches" "$(cat "$T/sample-app-rpm.ref")" "$PIPELINE_REF"',
     '  [ -n "$PIPELINE_REF" ] || echec "PIPELINE_REF non épinglée : étape pipeline, puis correction datée"\n'
     '  [ -s "$T/pipeline/pipeline.ref" ] || echec "référence de la pipeline absente (étape pipeline)"\n'
     '  attendu "pipeline écrite par l\'étape pipeline" "$(cat "$T/pipeline/pipeline.ref")" "$PIPELINE_REF"\n'
     '  echo \'{}\' > "$T/vide.json"\n'
     '  attendu "tag m4c de la pipeline, inchangé" "$(zot_lire "tag m4c" tekton/pipelines/sample-app-rpm:m4c)" "${PIPELINE_M4C##*@}"\n'
     '  for i in 1 2; do neuf "$R/$N-construction-$i-construire.log"; done', 1),
    ('"pipeline relue dans Zot au tag m4c (lecture anonyme)"', '"pipeline relue dans Zot au tag $TAG (lecture anonyme)"', 1),
    ('sample-app-rpm:m4c" < /dev/null', 'sample-app-rpm:$TAG" < /dev/null', 1),
    ('    pr=m4c-rpm-$i', '    pr=$N-construction-$i', 1),
    ('      r=$(oras repo tags --ca-file "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}" < /dev/null 2>&1 || true)\n'
     '      attendu "dépôt $IMAGE absent avant le premier PipelineRun" "$(grep -c \'name unknown\' <<< "$r")" 1',
     '      attendu "artefact de M4c présent avant le premier PipelineRun (décision « Même dépôt »)" \\\n'
     '        "$(zot_lire "artefact de M4c" "${IMAGE#"$REG"/}@$DIGEST_ESSAI")" "$DIGEST_ESSAI"\n'
     '      enveloppes_att avant', 1),
    ('    [ ! -f "$x" ] || cp "$x" "$R/m4c-pipeline-$i-construire.log"', '    [ ! -f "$x" ] || cp "$x" "$R/$N-construction-$i-construire.log"', 1),
    ('    attendu "construire : aucune ligne http ou https (mock.out, root.log, build.log)" "$(lignes \'^lignes http ou https de [a-z.]* : 0$\' "$x")" 3',
     '    attendu "construire : aucune ligne http ou https (mock.out, root.log, build.log)" "$(lignes \'^lignes http ou https de [a-z.]* : 0$\' "$x")" 3\n'
     '    hermetique "$x"', 1),
    ('  mesure "deux exécutions, même artefact" "$(cat "$T/rpm-2.digest")" "$(cat "$T/rpm-1.digest")"',
     '  mesure "deux exécutions, même artefact" "$(cat "$T/rpm-2.digest")" "$(cat "$T/rpm-1.digest")"\n'
     '  enveloppes_att après\n'
     '  attendu "tag m4c de la pipeline, inchangé après" "$(zot_lire "tag m4c" tekton/pipelines/sample-app-rpm:m4c)" "${PIPELINE_M4C##*@}"', 1),
]
TRANSFORMEES2 = [('m1b-fermeture.sh', 'lire_bundle', T_LIRE_BUNDLE), ('m1b-fermeture.sh', 'etape_pipeline', T_PIPELINE),
                 ('m4c.sh', 'etape_pipeline', T_CONSTRUCTION)]


def zone():
    L4, LB = lignes('m4c.sh'), lignes('m1b-bundles.sh')
    z = ['# Blocs recopiés à l\'identique de m4c.sh :']
    for nom in COPIES_M4C:
        z += bloc(L4, nom)
    z.append('# Blocs recopiés à l\'identique de m1b-bundles.sh :')
    for nom in COPIES_BUNDLES:
        z += bloc(LB, nom)
    z.append('# Blocs transformés (remplacements listés et comptés par resultats/m1b-construction-copies.py) :')
    for src, nom, T in TRANSFORMEES:
        z += transformer(src, nom, T).split('\n')
        z.append('')
    return z[:-1]


def zone2():
    z = []
    for src, noms in COPIES2:
        z.append(f'# Blocs recopiés à l\'identique de {src} :')
        L = lignes(src)
        for nom in noms:
            z += bloc(L, nom)
    z.append('# Blocs transformés (remplacements listés et comptés par resultats/m1b-construction-copies.py) :')
    for src, nom, T in TRANSFORMEES2:
        z += transformer(src, nom, T).split('\n')
        z.append('')
    return z[:-1]


if mode == 'compter':
    for src, nom, T in TRANSFORMEES + TRANSFORMEES2:
        transformer(src, nom, T, compter=True)
    sys.exit(0)

assert mode in ('assembler', 'verifier'), mode
for deb, fin, fz in ((DEBUT, FIN, zone), (DEBUT2, FIN2, zone2)):
    C = lignes(CIBLE)
    assert C.count(deb) == 1 and C.count(fin) == 1, deb
    i, j = C.index(deb), C.index(fin)
    if mode == 'assembler' and j == i + 1:   # n'écrit que dans une zone vide
        Z = fz()
        open(f'{d}/{CIBLE}', 'w', encoding='utf-8').write('\n'.join(C[:i + 1] + Z + C[j:]))
        print('zone écrite :', deb, len(Z), 'lignes')
OK = 0
C = lignes(CIBLE)
toutes = []
for deb, fin, fz in ((DEBUT, FIN, zone), (DEBUT2, FIN2, zone2)):
    i, j = C.index(deb), C.index(fin)
    Z = fz()   # recompte les remplacements
    assert C[i + 1:j] == Z, f'zone différente des sources transformées : {deb}'
    ok(f'zone égale aux sources transformées : {len(Z)} lignes ({deb})')
    toutes += Z
for src, noms in [('m4c.sh', COPIES_M4C), ('m1b-bundles.sh', COPIES_BUNDLES)] + COPIES2:
    for nom in noms:
        assert bloc(lignes(src), nom) == bloc(C, nom), nom
        ok(f'{nom} identique à sa source ({src})')
z = '\n'.join(toutes)
for motif in ('m4c-essai', 'prealables/', '$ENTREES', 'IMAGE_NEUVE', 'VERROU_ESSAI', 'bundles-construire', 'rm -rf "$x"', '${x:?}',
              'm4c-rpm', 'm4c-pipeline', 'prefetch-rpm-sample-app', 'PIPELINE_M4B', 'ARBRE_ESSAI', 'SCRIPT_NEUF', 'VERROU_SRC', '$TACHES',
              'sample-app-rpm.ref', 'name unknown'):
    assert motif not in z, motif
    ok(f'motif absent des zones : {motif}')
print(f'bilan : {OK} OK')
