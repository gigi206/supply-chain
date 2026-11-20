#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b, M4b refait : copies de m1b-fermeture.sh contrôlées contre m1b-bundles.sh (section A du banc).
#   verifier  chaque bloc recopié est identique, octet pour octet, à celui de m1b-bundles.sh, dans l'ordre ; etape_essai est
#             etape_essai_prefetch transformée par les remplacements listés ici, chacun compté ; un « OK » par contrôle.
#   assembler écrit la zone des copies (entre les deux marqueurs) depuis m1b-bundles.sh, puis vérifie (préparation seulement).
# Usage : python3 -I m1b-fermeture-copies.py verifier|assembler <dossier de la 05>
import sys

mode, d = sys.argv[1:3]
DEBUT, FIN = '# --- recopié de m1b-bundles.sh ---', '# --- fin des copies ---'
COPIES = ['attendu', 'ref_revue', 'echec', 'admission', 'libre_zot', 'normaliser', 'remplacer', 'rendre_taches', 'substituer',
          'pod_spec', 'dans', 'ARBRE', 'neuf', 'sha', 'zot_lire', 'DIFF_FEUILLES', 'diff_feuilles']
HEREDOCS = {'ARBRE': ("ARBRE=$(cat <<'SH'", 'SH'), 'DIFF_FEUILLES': ("DIFF_FEUILLES=$(cat <<'PY'", 'PY')}


def lignes(f):
    return open(f'{d}/{f}', encoding='utf-8').read().split('\n')


def bloc(L, nom):
    if nom in HEREDOCS:
        a, b = HEREDOCS[nom]
        assert L.count(a) == 1, (nom, L.count(a))
        i = L.index(a)
        j = L.index(b, i)
        assert L[j + 1] == ')', (nom, L[j + 1])
        return L[i:j + 2]
    deb = [k for k, l in enumerate(L) if l.startswith(nom + '() {')]
    assert len(deb) == 1, (nom, deb)
    i = deb[0]
    if L[i].count('{') == L[i].count('}'):
        return [L[i]]   # fonction d'une ligne
    j = L.index('}', i)
    return L[i:j + 1]


TRANSFORMATIONS = [
    ('etape_essai_prefetch() {', 'etape_essai() {', 1),
    ('  local src dos rc POD=$N-bundles-prefetch faux=0000000000000000000000000000000000000000000000000000000000000000\n'
     '  src=$(jq -r \'.config.bootstrap_image\' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r \'.bootstrap.pull_digest\' "$VERROU_SRC")\n',
     '  local src dos rc POD=$N-fermeture-prefetch faux=0000000000000000000000000000000000000000000000000000000000000000 a=$R/$N-fermeture-essai-arbre.txt\n'
     '  neuf "$a"\n'
     '  [ -s "$T/local/arbre-predit.txt" ] || echec "arbre prédit absent : étape local d\'abord"\n'
     '  attendu "arbre prédit de local (sha256)" "$(sha "$T/local/arbre-predit.txt")" "$ARBRE_PREDIT_SHA"\n'
     '  read -r src dos < <(source_dossier "$VERROU_SRC")\n', 1),
    ('  substituer "$T/prefetch-rpm.yaml" "$T/prefetch-rpm-sample-app.yaml"', '  substituer "$SIGNEE" "$T/prefetch-rpm-sample-app.yaml"', 2),
    ('  attendu "script substitué, égal à celui de l\'essai de M4b (sha256)" "$(sha256sum < "$T/script-essai.sh" | cut -c1-64)" "$SCRIPT_PREFETCH_SHA"',
     '  attendu "script substitué, égal au script neuf de local (sha256)" "$(sha256sum < "$T/script-essai.sh" | cut -c1-64)" "$SCRIPT_NEUF_SHA"', 1),
    ('  attendu "arbre égal à celui de final" "$([ "$(sha256sum < "$T/prefetch-essai-arbre.txt")" = "$(sha256sum < "$ARBRE_REF")" ] && echo égal || echo différent)" égal',
     '  cp "$T/prefetch-essai-arbre.txt" "$a"\n'
     '  echo "arbre archivé : resultats/${a##*/} ($(wc -l < "$a") fichiers, sha256 $(sha "$a"))"\n'
     '  attendu "arbre égal à l\'arbre prédit" "$([ "$(sha256sum < "$T/prefetch-essai-arbre.txt")" = "$(sha256sum < "$T/local/arbre-predit.txt")" ] && echo égal || echo différent)" égal', 1),
]

src = lignes('m1b-bundles.sh')
if mode == 'assembler':
    f = lignes('m1b-fermeture.sh')
    i, j = f.index(DEBUT), f.index(FIN)
    zone = [l for n in COPIES for l in bloc(src, n)]
    open(f'{d}/m1b-fermeture.sh', 'w', encoding='utf-8').write('\n'.join(f[:i + 1] + zone + f[j:]))
    print(f'zone des copies écrite : {len(zone)} lignes')
f = lignes('m1b-fermeture.sh')
assert f.count(DEBUT) == 1 and f.count(FIN) == 1
i, j = f.index(DEBUT), f.index(FIN)
zone = f[i + 1:j]
attendue = [l for n in COPIES for l in bloc(src, n)]
for n in COPIES:
    assert bloc(zone, n) == bloc(src, n), f'copie différente : {n}'
    print(f'OK   copie identique à m1b-bundles.sh : {n} ({len(bloc(src, n))} lignes)')
assert zone == attendue, 'zone des copies : ordre ou lignes en plus'
print(f'OK   zone des copies : exactement les {len(COPIES)} blocs, dans l\'ordre ({len(zone)} lignes)')
for n in COPIES:
    hors = [k for k, l in enumerate(f) if (k < i or k > j) and (l.startswith(n + '() {') or l.startswith(n + '=$('))]
    assert not hors, f'{n} redéfini hors de la zone des copies : lignes {hors}'
print('OK   aucun bloc recopié redéfini hors de la zone')
t = '\n'.join(bloc(src, 'etape_essai_prefetch'))
for a, b, c in TRANSFORMATIONS:
    assert t.count(a) == c, (a[:60], t.count(a), c)
    t = t.replace(a, b)
    print(f'OK   remplacement compté ({c}) : {a[:70]!r}')
assert '\n'.join(bloc(f, 'etape_essai')) == t, 'etape_essai différente de etape_essai_prefetch transformée'
print('OK   etape_essai = etape_essai_prefetch de m1b-bundles.sh, transformée')
