#!/usr/bin/env bash
# Brique 05, M4c : banc hors cluster et hors Zot de l'étape pipeline de m4c.sh (préparée à sec le 18/11/2026, accord permanent du
# 18/11), écrit avant tout passage. Modèle : m4b-rpm-banc.sh.
# A : insertions seules contre le m4c.sh d'avant (deux blocs : en-tête, bloc avant lancer) ; aucun nom de fonction ni de variable du
#     bloc déjà défini avant ; bash -n ; shellcheck : mêmes codes avant et après.
# B : la vraie fonction etape_pipeline, dans une copie jouable (commun.sh et lancer neutralisés, R redirigé dans le banc), avec le
#     vrai verrou, la vraie liste revue de la 08, la vraie fonction listee de commun.sh, le vrai selecteurs.jq et, pour journal de
#     construire, le journal réel du pod d'essai (resultats/m4c-essai-construire.log, chemins de l'essai). Faux : kubectl (état des
#     PipelineRuns dans un dossier, TaskRuns, pods, journaux, politiques), oras (descripteurs, tags, manifeste), sleep (immédiat),
#     sur (espace libre), signe. Un message de condition, une variable d'environnement et une ligne « token » sentinelles sont posés
#     partout : ils ne doivent jamais sortir, ni dans la sortie ni dans le journal archivé de construire.
#     Cas : succès ; digest autre que l'essai ; digests divergents ; rpm autre que M3 ; échec de construire et de publier (preuve
#     imprimée avant le KO) ; construire sans Kata ; label faux ; témoin réseau absent ; deux couches ; PipelineRun déjà présent ;
#     dépôt déjà présent ; espace sous la garde ; pipeline autre au tag m4c ; référence de taches autre ; tâche hors de la liste
#     revue ; politique M3 absente ; refus à l'admission ; PipelineRun jamais terminé. Dans chaque cas : aucun kubectl delete.
# Non couvert : Tekton (résolveur, Trusted Resources, pods réels, montages réels), Kata, Kyverno, Chains, Zot, réseau.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4c-pipeline-banc.sh <dossier-neuf> <m4c.sh avant> <m4c.sh>
set -uo pipefail
export LC_ALL=C
B=$1; AVANT=$2; COPIE=$3
RACINE=$PWD
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/kbin"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4c-pipeline-banc.sh, $(date -u +%FT%TZ) ; m4c.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; m4c.sh $(sha256sum < "$COPIE" | cut -c1-64)"

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
printf '#!/bin/sh\nexit 0\n' > "$B/kbin/sleep"
cat > "$B/kbin/kubectl" <<'PY'
#!/usr/bin/env python3
# faux kubectl : PipelineRuns créés = fichiers de $BANC_ETAT ; TaskRuns, pods, journaux et politiques selon $BANC_CAS
import json, os, sys
a = sys.argv[1:]
open(os.environ['BANC_APPELS'], 'a').write('kubectl ' + ' '.join(a) + '\n')
cas, etat = os.environ['BANC_CAS'], os.environ['BANC_ETAT']
REG = 'sc-stockage.poc.test:5000'
IMAGE = REG + '/builds/sample-app-rpm'
ESSAI = 'sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119'
ENTREES = {'FERMETURE_RPM': REG + '/builds/fermetures/sample-app-rpm@sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c',
           'FERMETURE_SOURCES': REG + '/builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21',
           'PACKAGING': REG + '/entrees/sample-app/packaging-rpm@sha256:41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8'}
MSG = 'SENTINELLE-MESSAGE'
def digest(pr):
    if cas == 'digest_autre': return 'sha256:' + 'a' * 64
    if cas == 'divergents' and pr.endswith('-2'): return 'sha256:' + 'b' * 64
    return ESSAI
def echoue(pr, tache):   # tâche en échec au premier PipelineRun
    return pr.endswith('-1') and ((cas == 'echec_construire' and tache == 'construire') or (cas == 'echec_publier' and tache == 'publier'))
def pr_echoue(pr): return echoue(pr, 'construire') or echoue(pr, 'publier')
def cond(ok):
    if cas == 'en_cours': return [{'type': 'Succeeded', 'status': 'Unknown', 'reason': 'Running', 'message': MSG}]
    return [{'type': 'Succeeded', 'status': 'True' if ok else 'False', 'reason': 'Succeeded' if ok else 'Failed', 'message': MSG}]
def taches(pr):
    if cas == 'en_cours': return ['preparer']
    if echoue(pr, 'construire'): return ['preparer', 'construire']
    return ['preparer', 'construire', 'publier']
if a[0] == 'get' and a[1] in ('networkpolicy', 'ciliumnetworkpolicy'):
    if a[1] == 'ciliumnetworkpolicy':
        print(json.dumps({'items': [{'metadata': {'name': 'builds-sans-internet'}, 'spec': {
            'endpointSelector': {'matchExpressions': [{'key': 'tekton.dev/task', 'operator': 'NotIn', 'values': ['construire-rpm', 'construire-deb']}]},
            'egress': [{'toCIDR': ['192.168.161.13/32']}]}}]}))
    else:
        it = [] if cas == 'politique_absente' else [{'metadata': {'name': 'construction-rpm-sans-sortie'}, 'spec': {
            'podSelector': {'matchLabels': {'tekton.dev/task': 'construire-rpm'}}, 'policyTypes': ['Ingress', 'Egress']}}]
        print(json.dumps({'items': it}))
    sys.exit(0)
if a[0] == 'create':
    f = json.load(open(a[a.index('-f') + 1]))
    s = f['spec']
    assert f['kind'] == 'PipelineRun' and 'env' not in s['taskRunTemplate']['podTemplate']
    assert [(x['pipelineTaskName'], x['podTemplate'].get('runtimeClassName')) for x in s['taskRunSpecs']] == [('construire', 'kata')]
    assert s['workspaces'][0]['volumeClaimTemplate']['spec']['resources']['requests']['storage'] == '2Gi'
    if '--dry-run=server' in a:
        if cas == 'refus_admission':
            print('Error from server (Forbidden): admission webhook refusé ' + MSG, file=sys.stderr); sys.exit(1)
        sys.exit(0)
    open(os.path.join(etat, f['metadata']['name']), 'w').close()
    sys.exit(0)
if a[0] == 'get' and a[1] == 'pipelinerun':
    pr = a[4]
    if cas == 'existe' and pr == 'm4c-rpm-1' and not os.path.exists(os.path.join(etat, pr)):
        open(os.path.join(etat, pr), 'w').close()
    if not os.path.exists(os.path.join(etat, pr)):
        print(f'Error from server (NotFound): pipelineruns.tekton.dev "{pr}" not found', file=sys.stderr); sys.exit(1)
    if a[6] == 'name': print(f'pipelinerun.tekton.dev/{pr}'); sys.exit(0)
    ok = not pr_echoue(pr)
    o = {'metadata': {'name': pr}, 'status': {'conditions': cond(ok), 'startTime': '2026-11-18T00:00:00Z'}}
    if ok and cas != 'en_cours':
        o['status']['completionTime'] = '2026-11-18T00:04:00Z'
        o['status']['results'] = [{'name': 'IMAGE_URL', 'value': IMAGE}, {'name': 'IMAGE_DIGEST', 'value': digest(pr)}]
    print(json.dumps(o)); sys.exit(0)
if a[0] == 'get' and a[1] == 'taskrun':
    if '-l' in a:
        pr = a[a.index('-l') + 1].split('=')[1]
        print(' '.join(f'{pr}-{t}' for t in taches(pr))); sys.exit(0)
    t = a[4]; pr, tache = t.rsplit('-', 1); ok = not echoue(pr, tache)
    o = {'metadata': {'name': t, 'labels': {'tekton.dev/pipelineTask': tache, 'tekton.dev/pipelineRun': pr}},
         'status': {'podName': t + '-pod', 'conditions': cond(ok)}}
    if ok and tache == 'preparer':
        o['status']['results'] = [{'name': 'CHAINS-GIT_URL', 'type': 'string', 'value': 'https://sc-stockage.poc.test:3000/workspace/sample-app.git'},
            {'name': 'CHAINS-GIT_COMMIT', 'type': 'string', 'value': '6391fd437f26696847041be3226bbbf633f55a2f'}] + [
            {'name': f'{k}_ARTIFACT_INPUTS', 'type': 'object', 'value': {'uri': 'oci://' + v.split('@')[0], 'digest': v.split('@')[1]}}
            for k, v in ENTREES.items()]
    if ok and tache == 'construire': o['status']['results'] = [{'name': 'DIGEST_CONSTRUIT', 'type': 'string', 'value': digest(pr)}]
    if ok and tache == 'publier': o['status']['results'] = [{'name': 'IMAGE_URL', 'value': IMAGE}, {'name': 'IMAGE_DIGEST', 'value': digest(pr)}]
    print(json.dumps(o)); sys.exit(0)
if a[0] == 'get' and a[1] == 'pod':
    p = a[4]; t = p[:-4]; pr, tache = t.rsplit('-', 1)
    pas = {'preparer': ['step-sources', 'step-entrees', 'step-assemblage'], 'construire': ['step-construire'], 'publier': ['step-publier']}[tache]
    lab = {'preparer': 'preparer-rpm', 'construire': 'construire-rpm', 'publier': 'publier-image'}[tache]
    if cas == 'label_faux' and tache == 'preparer': lab = 'preparer-deb'
    d = {'limits': {'cpu': '1', 'memory': '512Mi'}, 'requests': {'cpu': '50m', 'memory': '64Mi'}}
    r = {'limits': {'cpu': '2', 'memory': '6Gi'}, 'requests': {'cpu': '2', 'memory': '6Gi'}} if tache == 'construire' else d
    ko = echoue(pr, tache)
    term = lambda c: {'terminated': {'exitCode': 1, 'reason': 'Error', 'message': MSG}} if ko and c == pas[-1] else {'terminated': {'exitCode': 0, 'reason': 'Completed'}}
    spec = {'nodeName': 'sc-build', 'initContainers': [{'name': 'prepare', 'resources': d, 'env': [{'name': 'SENTINELLE_ENV', 'value': MSG}]},
            {'name': 'place-scripts', 'resources': d}],
            'containers': [{'name': c, 'resources': r, 'env': [{'name': 'SENTINELLE_ENV', 'value': MSG}]} for c in pas]}
    if tache == 'construire' and cas != 'sans_kata': spec['runtimeClassName'] = 'kata'
    print(json.dumps({'metadata': {'name': p, 'labels': {'tekton.dev/task': lab}}, 'spec': spec,
        'status': {'phase': 'Failed' if ko else 'Succeeded',
            'initContainerStatuses': [{'name': 'prepare', 'state': {'terminated': {'exitCode': 0, 'reason': 'Completed'}}},
                {'name': 'place-scripts', 'state': {'terminated': {'exitCode': 0, 'reason': 'Completed'}}}],
            'containerStatuses': [{'name': c, 'state': term(c)} for c in pas]}})); sys.exit(0)
if a[0] == 'logs':
    p = a[3]; c = a[a.index('-c') + 1]; pr, tache = p[:-4].rsplit('-', 1)
    print('2026/11/18 00:00:00 Entrypoint initialization')
    print('jeton du compte de service : SENTINELLE-JETON')
    if c == 'step-construire':
        j = open(os.environ['BANC_ESSAI_LOG']).read().split('\n')
        if echoue(pr, 'construire'):
            j = [l for l in j if not l.startswith(('mock --hermetic-build', 'lignes', 'paquet', 'rpm :', 'couche', 'image.tar', 'après mock'))]
            j += ['mock --hermetic-build : rc 30 en 12 s', 'mock en échec']
        if cas == 'rpm_autre': j = [l.replace('864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f', 'f' * 64) for l in j]
        if cas == 'temoin_manquant': j = [l for l in j if not l.startswith('témoin TCP 199.')]
        print('\n'.join(l.replace('/e/', '/workspace/entrees/') for l in j).rstrip('\n'))
    elif c == 'step-publier':
        if echoue(pr, 'publier'): print("tar: can't open '/workspace/sortie/image.tar': Permission denied")
        else: print(f'publiée : {IMAGE}@{digest(pr)} (relue en lecture anonyme)')
    else:
        print(f'{c[5:]} : fait')
    sys.exit(0)
print('appel non prévu : ' + ' '.join(a), file=sys.stderr); sys.exit(3)
PY
cat > "$B/kbin/oras" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ['BANC_APPELS'], 'a').write('oras ' + ' '.join(a) + '\n')
cas = os.environ['BANC_CAS']
cible = a[-1]
if a[:2] == ['manifest', 'fetch'] and '--descriptor' in a:
    if cible.endswith('/tekton/pipelines/sample-app-rpm:m4c'):
        d = 'sha256:' + 'c' * 64 if cas == 'pipeline_autre' else 'sha256:ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be'
    else:
        d = cible.split('@')[1]
    print(json.dumps({'mediaType': 'application/vnd.oci.image.manifest.v1+json', 'digest': d, 'size': 566})); sys.exit(0)
if a[:2] == ['repo', 'tags']:
    if cas == 'depot_present': print('sha256-07b7bd6f.att'); sys.exit(0)
    print('Error response from registry: name unknown: repository name not known to registry', file=sys.stderr); sys.exit(1)
if a[:2] == ['manifest', 'fetch']:
    print(json.dumps({'layers': [{}] * (2 if cas == 'couches2' else 1)})); sys.exit(0)
print('appel non prévu : ' + ' '.join(a), file=sys.stderr); sys.exit(3)
PY
chmod +x "$B/kbin/sleep" "$B/kbin/kubectl" "$B/kbin/oras"
eval "$(sed -n '/^listee() {/,/^}/p' "$RACINE/poc/bricks/08-trust-plane/commun.sh")"
eval "$(declare -f listee | sed '1s/^listee/listee_vraie/')"
listee() { [ "$BANC_CAS" = non_listee ] && [[ $1 == */construire-rpm@* ]] && return 1; listee_vraie "$1"; }

jouer() { # cas : etape_pipeline de la copie jouable, sortie dans $B/<cas>.out ; code dans $B/<cas>.rc
  local c=$1
  mkdir -p "$B/$c/etat" "$B/$c/W/m4c-05" "$B/$c/W/resultats"
  if [ "$c" = ref_autre ]; then echo "sc-stockage.poc.test:5000/tekton/pipelines/sample-app-rpm@sha256:$(printf 'd%.0s' {1..64})" > "$B/$c/W/m4c-05/sample-app-rpm.ref"
  else echo "sc-stockage.poc.test:5000/tekton/pipelines/sample-app-rpm@sha256:ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be" > "$B/$c/W/m4c-05/sample-app-rpm.ref"; fi
  ( export BANC_CAS=$c BANC_ETAT=$B/$c/etat BANC_APPELS=$B/$c/appels.txt BANC_ESSAI_LOG=$RACINE/poc/bricks/05-rpm-mock/resultats/m4c-essai-construire.log RACINE PATH=$B/kbin:$PATH
    repo=$RACINE REG=sc-stockage.poc.test:5000 REG_HOTE=192.168.161.13:5000 P=$B/P W=$B/$c/W S=$B/S O=$B/O OUTILS=plateforme/outils OUTILS_DIGEST=sha256:0
    sur() { [ "$BANC_CAS" = plein ] && echo "  100" || echo " 4419796992"; }
    signe() { echo true; }
    # shellcheck disable=SC1090
    . "$B/m4c-jouable.sh"
    { etape_pipeline; } 2>&1 ) > "$B/$c.out"
  echo $? > "$B/$c.rc"
  touch "$B/$c/appels.txt"
}
creations() { grep -c '^kubectl create -f ' "$B/$1/appels.txt" || true; }
suppressions() { grep -c '^kubectl delete' "$B/$1/appels.txt" || true; }
sentinelle() { cat "$B/$1.out" "$B/$1"/W/resultats/* 2> /dev/null | grep -c 'SENTINELLE' || true; }
ko() { grep '^KO' "$B/$1.out"; }

echo "## B : etape_pipeline, faux kubectl et faux oras"
CAS="succes digest_autre divergents rpm_autre echec_construire echec_publier sans_kata label_faux temoin_manquant couches2 existe depot_present plein pipeline_autre ref_autre non_listee politique_absente refus_admission en_cours"
for c in $CAS; do
  jouer "$c"
  echo "### cas $c : code $(cat "$B/$c.rc") ; créations $(creations "$c") ; suppressions $(suppressions "$c") ; sentinelles $(sentinelle "$c")"
  grep -E '^(OK|KO|ÉCART)   |^ÉCART |conteneur step|écarts :' "$B/$c.out" | cut -c1-200 | sed 's/^/     /' | tail -n 6
  egal "$c : aucune suppression" "$(suppressions "$c")" 0
  egal "$c : ni message de condition, ni variable d'environnement, ni ligne de jeton affichés ou archivés" "$(sentinelle "$c")" 0
done
egal "succes : code, créations, dry-run" "$(cat "$B/succes.rc") $(creations succes) $(grep -c 'dry-run=server' "$B/succes/appels.txt")" "0 2 2"
egal "succes : OK" "$(grep -c '^OK   ' "$B/succes.out")" 61
egal "succes : aucun ÉCART ni KO" "$(grep -c '^ÉCART\|^KO' "$B/succes.out")" 0
egal "succes : deux exécutions, même artefact" "$(grep -c '^OK   deux exécutions, même artefact' "$B/succes.out")" 1
egal "succes : journaux de construire archivés (deux), masqués" \
  "$(ls "$B/succes/W/resultats" | paste -sd' ') $(grep -c '^\[ligne masquée : motif jeton|token\]$' "$B/succes/W/resultats/m4c-pipeline-1-construire.log")" \
  "m4c-pipeline-1-construire.log m4c-pipeline-2-construire.log 1"
egal "succes : lignes « paquet » non répétées dans la sortie" "$(grep -c '^ *paquet ' "$B/succes.out")" 0
egal "succes : relevé des écarts au verrou" "$(grep -c '^relevé : paquets du buildroot imprimés : 222 ; écarts au verrou (nom, version, release, arch, sigmd5) : 0$' "$B/succes.out")" 2
egal "succes : podTemplate de construire avec Kata, envoyé au dry-run puis créé" "$(jq -c '.spec.taskRunSpecs' "$B/succes/W/m4c-05/pr-m4c-rpm-1.json")" \
  '[{"pipelineTaskName":"construire","podTemplate":{"nodeSelector":{"zone":"build"},"tolerations":[{"key":"zone","operator":"Equal","value":"build","effect":"NoSchedule"}],"securityContext":{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}},"runtimeClassName":"kata"}}]'
egal "digest_autre : code, créations, ÉCART, écarts" \
  "$(cat "$B/digest_autre.rc") $(creations digest_autre) $(grep -c '^ÉCART digest de l.artefact égal à celui du pod d.essai' "$B/digest_autre.out") $(grep '^écarts :' "$B/digest_autre.out")" "1 2 2 écarts : 2"
egal "divergents : code, créations, ÉCART" \
  "$(cat "$B/divergents.rc") $(creations divergents) $(grep -c '^ÉCART deux exécutions, même artefact' "$B/divergents.out") $(grep '^écarts :' "$B/divergents.out")" "1 2 1 écarts : 2"
egal "rpm_autre : code, créations, ÉCART" "$(cat "$B/rpm_autre.rc") $(creations rpm_autre) $(grep -c '^ÉCART construire : rpm égal à celui de M3' "$B/rpm_autre.out")" "1 2 2"
for c in echec_construire echec_publier; do
  egal "$c : code, créations, KO" "$(cat "$B/$c.rc") $(creations "$c") $(ko "$c")" "1 1 KO   PipelineRun m4c-rpm-1 : False|Failed (attendu : True|Succeeded)"
done
egal "echec_construire : code 1 et journal imprimés avant le KO" \
  "$(awk '/conteneur step-construire : terminated code 1 raison Error/ && !o {o = NR} /mock --hermetic-build : rc 30/ && !m {m = NR} /^KO   PipelineRun/ && !q {q = NR} END {print (o && m && q && o < q && m < q) ? "avant" : "non"}' "$B/echec_construire.out")" avant
egal "echec_construire : journal archivé" "$(grep -c '^mock en échec$' "$B/echec_construire/W/resultats/m4c-pipeline-1-construire.log")" 1
egal "echec_publier : refus de lecture imprimé avant le KO" \
  "$(awk '/Permission denied/ && !o {o = NR} /^KO   PipelineRun/ && !q {q = NR} END {print (o && q && o < q) ? "avant" : "non"}' "$B/echec_publier.out")" avant
egal "sans_kata : KO" "$(ko sans_kata)" "KO   m4c-rpm-1, construire : tekton.dev/task|runtimeClassName|nœud : construire-rpm||sc-build (attendu : construire-rpm|kata|sc-build)"
egal "label_faux : KO" "$(ko label_faux)" "KO   m4c-rpm-1, preparer : tekton.dev/task|runtimeClassName|nœud : preparer-deb||sc-build (attendu : preparer-rpm||sc-build)"
egal "temoin_manquant : KO" "$(ko temoin_manquant)" "KO   construire : témoins réseau en échec : 3 (attendu : 4)"
egal "couches2 : KO" "$(ko couches2)" "KO   manifeste relu dans Zot (lecture anonyme) : digest du descripteur, couches : sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119 2 (attendu : sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119 1)"
for c in sans_kata label_faux temoin_manquant couches2; do egal "$c : code, créations" "$(cat "$B/$c.rc") $(creations "$c")" "1 1"; done
for c in existe depot_present plein pipeline_autre ref_autre non_listee politique_absente; do
  egal "$c : arrêt avant toute création (code, créations, dry-run)" "$(cat "$B/$c.rc") $(creations "$c") $(grep -c 'dry-run=server' "$B/$c/appels.txt" || true)" "1 0 0"
done
egal "existe : KO" "$(ko existe)" "KO   m4c-rpm-1 existe déjà : rien n'est purgé, décision avant toute relance"
egal "plein : KO" "$(ko plein)" "KO   espace libre illisible ou sous la garde sur sc-stockage"
egal "non_listee : KO" "$(ko non_listee)" "KO   absente de la liste revue : sc-stockage.poc.test:5000/tekton/tasks/construire-rpm@sha256:d7f01398f188931c124273c8b5fb60e2a66c22e9d0a2dfcd229ecadee1e62164"
egal "politique_absente : KO" "$(ko politique_absente)" 'KO   construction-rpm-sans-sortie : sélecteur, types, règles d'"'"'entrée et de sortie : [] (attendu : [[{"matchLabels":{"tekton.dev/task":"construire-rpm"}},["Egress","Ingress"],[],[]]])'
egal "refus_admission : code, créations, dry-run" "$(cat "$B/refus_admission.rc") $(creations refus_admission) $(grep -c 'dry-run=server' "$B/refus_admission/appels.txt")" "1 0 1"
egal "en_cours : code, créations, KO après relevé" "$(cat "$B/en_cours.rc") $(creations en_cours) $(grep -c '^KO   PipelineRun m4c-rpm-1 : Unknown|Running' "$B/en_cours.out")" "1 1 1"
egal "en_cours : attente de 1800 lectures" "$(grep -c '^kubectl get pipelinerun -n builds m4c-rpm-1 -o json$' "$B/en_cours/appels.txt")" 1801
echo "# bilan : $n OK, $k KO ; fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
