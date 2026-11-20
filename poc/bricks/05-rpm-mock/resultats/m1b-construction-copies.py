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


if mode == 'compter':
    for src, nom, T in TRANSFORMEES:
        transformer(src, nom, T, compter=True)
    sys.exit(0)

C = lignes(CIBLE)
assert C.count(DEBUT) == 1 and C.count(FIN) == 1
i, j = C.index(DEBUT), C.index(FIN)
Z = zone()
if mode == 'assembler':
    assert j == i + 1, 'zone déjà remplie : assembler n\'écrit que dans une zone vide'
    open(f'{d}/{CIBLE}', 'w', encoding='utf-8').write('\n'.join(C[:i + 1] + Z + C[j:]))
    C = lignes(CIBLE)
    i, j = C.index(DEBUT), C.index(FIN)
    print('zone écrite :', len(Z), 'lignes')
assert mode in ('assembler', 'verifier'), mode
OK = 0
Z = zone()   # recompte les remplacements
assert C[i + 1:j] == Z, 'zone différente des sources transformées'
ok(f'zone égale aux sources transformées : {len(Z)} lignes')
for nom in COPIES_M4C + COPIES_BUNDLES:
    src = lignes('m4c.sh' if nom in COPIES_M4C else 'm1b-bundles.sh')
    assert bloc(src, nom) == bloc(C, nom), nom
    ok(f'{nom} identique à sa source')
z = '\n'.join(Z)
for motif in ('m4c-essai', 'prealables/', '$ENTREES', 'IMAGE_NEUVE', 'VERROU_ESSAI', 'bundles-construire', 'rm -rf "$x"', '${x:?}'):
    assert motif not in z, motif
    ok(f'motif absent de la zone : {motif}')
print(f'bilan : {OK} OK')
