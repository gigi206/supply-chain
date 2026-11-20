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

# Ajout du 20/11/2026 (étapes pipeline et rpm) : quatre fonctions de m4b.sh, et etape_rpm de m4b.sh transformée.
DEBUT_M4B, FIN_M4B = '# --- recopié de m4b.sh ---', '# --- fin des copies de m4b.sh ---'
COPIES_M4B = ['pr_rpm', 'statut_pr', 'attendre_pr', 'releve_pod']
TRANSFORMATIONS_RPM = [
    ('  attendu "liste des rpm (sha256)" "$(sha256sum < "$LISTE" | cut -c1-64)" "$LISTE_SHA"\n  local i pr r t p d u l src c\n',
     '  sources\n  local i pr r t p d u l src c n\n'
     '  [ -n "$PIPELINE_REF" ] || echec "PIPELINE_REF non épinglée : étape pipeline d\'abord, puis correction datée et banc rejoué"\n'
     '  attendu "arbre de l\'essai archivé (sha256), égal à l\'arbre prédit" "$(sha "$ARBRE_ESSAI")" "$ARBRE_PREDIT_SHA"\n'
     '  n=$(wc -l < "$ARBRE_ESSAI")\n'
     '  echo \'{}\' > "$T/vide.json"\n', 1),
    ('  attendu "pipeline relue dans Zot au tag m4b (lecture anonyme)" \\\n'
     '    "$REG/tekton/pipelines/prefetch-rpm-sample-app@$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/tekton/pipelines/prefetch-rpm-sample-app:m4b" < /dev/null | jq -r .digest)" \\\n'
     '    "$PIPELINE_REF"\n',
     '  attendu "pipeline relue dans Zot au tag $TAG (lecture anonyme)" \\\n'
     '    "$REG/tekton/pipelines/prefetch-rpm-sample-app@$(zot_lire "tag $TAG" "tekton/pipelines/prefetch-rpm-sample-app:$TAG")" "$PIPELINE_REF"\n'
     '  attendu "tag m4b de la pipeline, inchangé" "$(zot_lire "tag m4b" tekton/pipelines/prefetch-rpm-sample-app:m4b)" "${PIPELINE_M4B##*@}"\n', 1),
    ('    pr=m4b-rpm-$i\n', '    pr=$N-rpm-$i\n', 1),
    ('    if [ "$i" = 1 ]; then\n'
     '      r=$(oras repo tags --ca-file "$P/ca-poc.crt" "${DEPOT_FERMETURE/$REG/$REG_HOTE}" < /dev/null 2>&1 || true)\n'
     '      attendu "dépôt $DEPOT_FERMETURE absent avant le premier PipelineRun" "$(grep -c \'name unknown\' <<< "$r")" 1\n'
     '    fi\n',
     '    attendu "fermeture de M4b présente dans le même dépôt (« Même dépôt, par digest »)" \\\n'
     '      "$(zot_lire "fermeture de M4b" "${DEPOT_FERMETURE#"$REG"/}@$FERMETURE_M4B")" "$FERMETURE_M4B"\n'
     '    if [ "$i" = 1 ]; then\n'
     '      attendu "fermeture prédite absente avant le premier PipelineRun" \\\n'
     '        "$(zot_lire "fermeture prédite" "${DEPOT_FERMETURE#"$REG"/}@$DIGEST_PREDIT")" absent\n'
     '    fi\n', 1),
    ('    echo "/ de sc-stockage : $l octets libres à $(date -u +%H:%M:%S) (garde : $LIBRE_MIN)"\n',
     '    echo "/ de sc-stockage : $l octets libres à $(date -u +%H:%M:%S) (garde : $LIBRE_MIN)"\n'
     '    echo "/ de sc-build (emptyDir du layout de publier) : $(sur sc-build \'df -B1 --output=avail / | tail -n 1\' < /dev/null | tr -d \' \') octets libres (relevé)"\n', 1),
    ('calculé à sec $DIGEST_CALCULE : $([ "$d" = "$DIGEST_CALCULE" ]', 'prédit à sec $DIGEST_PREDIT : $([ "$d" = "$DIGEST_PREDIT" ]', 1),
    ('"publier : 230 couches dans le journal"', '"publier : $n couches dans le journal"', 1),
    ('(230 couches, relue en lecture anonyme)', '($n couches, relue en lecture anonyme)', 1),
    ('"$(oras manifest fetch --ca-file "$P/ca-poc.crt" "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$d" < /dev/null | jq \'.layers | length\')" 230\n',
     '"$(oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$d" < /dev/null | jq \'.layers | length\')" "$n"\n', 1),
    ('  attendu "deux exécutions, même fermeture" "$(cat "$T/rpm-2.digest")" "$(cat "$T/rpm-1.digest")"\n}',
     '  attendu "deux exécutions, même fermeture" "$(cat "$T/rpm-2.digest")" "$(cat "$T/rpm-1.digest")"\n'
     '  attendu "fermeture de M4b toujours présente après" "$(zot_lire "fermeture de M4b" "${DEPOT_FERMETURE#"$REG"/}@$FERMETURE_M4B")" "$FERMETURE_M4B"\n'
     '  echo "fermeture neuve : $DEPOT_FERMETURE@$(cat "$T/rpm-1.digest") ; prédite à sec : $DIGEST_PREDIT"\n}', 1),
]
src = lignes('m1b-bundles.sh')
m4b = lignes('m4b.sh')


def rpm_transformee():
    t = '\n'.join(bloc(m4b, 'etape_rpm'))
    for a, b, c in TRANSFORMATIONS_RPM:
        assert t.count(a) == c, ('etape_rpm', a[:60], t.count(a), c)
        t = t.replace(a, b)
    return t


if mode == 'assembler':
    f = lignes('m1b-fermeture.sh')
    i, j = f.index(DEBUT), f.index(FIN)
    zone = [l for n in COPIES for l in bloc(src, n)]
    f = f[:i + 1] + zone + f[j:]
    i, j = f.index(DEBUT_M4B), f.index(FIN_M4B)
    zone_m4b = [l for n in COPIES_M4B for l in bloc(m4b, n)]
    f = f[:i + 1] + zone_m4b + f[j:]
    if '@ETAPE_RPM@' in f:
        k = f.index('@ETAPE_RPM@')
        f = f[:k] + rpm_transformee().split('\n') + f[k + 1:]
    open(f'{d}/m1b-fermeture.sh', 'w', encoding='utf-8').write('\n'.join(f))
    print(f'zones des copies écrites : {len(zone)} et {len(zone_m4b)} lignes')
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
assert f.count(DEBUT_M4B) == 1 and f.count(FIN_M4B) == 1
i, j = f.index(DEBUT_M4B), f.index(FIN_M4B)
zone = f[i + 1:j]
for n in COPIES_M4B:
    assert bloc(zone, n) == bloc(m4b, n), f'copie différente : {n}'
    print(f'OK   copie identique à m4b.sh : {n} ({len(bloc(m4b, n))} lignes)')
assert zone == [l for n in COPIES_M4B for l in bloc(m4b, n)], 'zone des copies de m4b.sh : ordre ou lignes en plus'
print(f'OK   zone des copies de m4b.sh : exactement les {len(COPIES_M4B)} blocs, dans l\'ordre ({len(zone)} lignes)')
for n in COPIES_M4B:
    hors = [k for k, l in enumerate(f) if (k < i or k > j) and l.startswith(n + '() {')]
    assert not hors, f'{n} redéfini hors de la zone des copies de m4b.sh : lignes {hors}'
for a, b, c in TRANSFORMATIONS_RPM:
    print(f'OK   remplacement compté dans etape_rpm ({c}) : {a[:70]!r}')
assert '\n'.join(bloc(f, 'etape_rpm')) == rpm_transformee(), 'etape_rpm différente de celle de m4b.sh transformée'
print('OK   etape_rpm = etape_rpm de m4b.sh, transformée')
