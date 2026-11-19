#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : banc hors cluster et hors Zot de l'étape pipeline de m1b-pipeline.sh (préparée à sec le 19/11/2026), sur le
# modèle de m4c-pipeline-banc.sh et de m1b-signature-banc.sh. La vraie fonction etape_pipeline, chargée depuis le vrai script, jouée
# dans la forme de lancer ({ …; } 2>&1 | sed | tee), avec le vrai commun.sh (CONFIANCE_DIR du banc ; R redirigé dans le banc), le
# vrai selecteurs.jq, les sorties réelles de m1bt3 (digests du banc, journal d'essai de construction) à la place de la mesure d'un
# autre jour, les rendus de m1bt3 pour les pipelines « signées » (références de tâches fictives, sans signature) et une copie de la
# liste revue où ces références sont ajoutées. Journaux des pas : les blocs réels des essais de m1bt3 (prefetch et construction),
# marge retirée. Faux : kubectl (politiques, PipelineRuns dans un dossier, TaskRuns, pods, journaux, annotation de Chains), oras
# (descripteurs, tags, manifeste), sleep (immédiat), sur (octets libres). Messages des conditions et variables d'environnement
# marqués d'une sentinelle partout : ils ne doivent jamais sortir.
# Cas : succès ; mesure divergente ; pipeline autre au tag m1b ; tâche hors de la liste revue ; NotIn à trois labels ; NetworkPolicy
# de construction absente ; politique qui autorise du trafic à la construction ; PipelineRun déjà présent ; dépôt déjà présent ;
# relance sous un autre préfixe après publication de l'outillage (ajout du 19/11, correction des gardes d'entrée) ; espace sous la
# garde d'entrée (deux images) ou sous celle d'une image ; place tombée après le premier PipelineRun ; refus à l'admission ; prefetch de l'outillage en échec (résultat déclaré non
# écrit) ; digest autre ; digests divergents ; construction sans Kata ; témoin réseau absent ; couches ; non signé par Chains ;
# base du bootstrap autre ; base écrite pour l'outillage ; PipelineRun jamais terminé. Dans chaque cas : aucun kubectl delete,
# aucune sentinelle dans la sortie, nombre de créations attendu.
# Non couvert : Tekton (résolveur, Trusted Resources, pods réels, montages, résultat déclaré non écrit), Kata, Kyverno, Chains, Zot,
# réseau, Cilium.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-pipeline-banc.sh <dossier-neuf>
set -uo pipefail
export LC_ALL=C
B=$1
RACINE=$PWD; SCRIPT=$RACINE/poc/bricks/05-rpm-mock/m1b-pipeline.sh
RES=$RACINE/poc/bricks/05-rpm-mock/resultats
M3=$HOME/.cache/supply-chain-poc/08/travail/m1bt3-05   # lecture seule
LISTE0=$RACINE/poc/bricks/08-trust-plane/politique/porte/taches.yml
REG=sc-stockage.poc.test:5000
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/kbin" "$B/sig" "$B/journaux"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m1b-pipeline-banc.sh, $(date -u +%FT%TZ) ; m1b-pipeline.sh $(sha256sum < "$SCRIPT" | cut -c1-64)"
echo "# yq $(yq --version | awk '{print $NF}') ; jq $(jq --version) ; liste revue $(sha256sum < "$LISTE0" | cut -c1-64)"

# Pipelines « signées » du banc : rendus de m1bt3, références fictives des deux tâches neuves, publier-image de la liste revue
PF=$REG/tekton/tasks/prefetch-racine-rpm@sha256:$(printf 'a%.0s' {1..64})
CO=$REG/tekton/tasks/construire-racine-rpm@sha256:$(printf 'b%.0s' {1..64})
PU=$REG/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b
echo "$PF" > "$B/sig/prefetch-racine-rpm.ref"; echo "$CO" > "$B/sig/construire-racine-rpm.ref"
for x in o b; do
  nom=$(yq .metadata.name "$M3/pipeline-$x.yaml")
  A=$PF B_=$CO C=$PU yq '.spec.tasks[0].taskRef.params[0].value = strenv(A) | .spec.tasks[1].taskRef.params[0].value = strenv(B_)
    | .spec.tasks[2].taskRef.params[0].value = strenv(C)' "$M3/pipeline-$x.yaml" > "$B/sig/$nom-signee.yaml"
  echo "$REG/tekton/pipelines/$nom@sha256:$(sha256sum < "$B/sig/$nom-signee.yaml" | cut -c1-64)" > "$B/sig/$nom.ref"
done
cp "$LISTE0" "$B/liste.yml"
for r in "$PF" "$CO"; do printf '  oci://%s:\n    - ref: %s\n' "${r%@*}" "${r#*@}" >> "$B/liste.yml"; done
egal "liste du banc : yq la lit, deux clés de plus" "$(( $(yq '.trusted_tasks | length' "$B/liste.yml") - $(yq '.trusted_tasks | length' "$LISTE0") ))" 2
cp "$LISTE0" "$B/liste-sans.yml"
printf '  oci://%s:\n    - ref: %s\n' "${PF%@*}" "${PF#*@}" >> "$B/liste-sans.yml"   # construire-racine-rpm absente
# Mesure : les sorties réelles de m1bt3 (digests du banc ; journal d'essai copié dans le R du banc) ; une copie divergente
mkdir -p "$B/mesure/m1bt3-05" "$B/mesure-div/m1bt3-05"
cp "$M3/banc-digest-o" "$M3/banc-digest-b" "$B/mesure/m1bt3-05/"
cp "$M3/banc-digest-b" "$B/mesure-div/m1bt3-05/"; printf 'sha256:%s' "$(printf 'e%.0s' {1..64})" > "$B/mesure-div/m1bt3-05/banc-digest-o"
# Journaux des pas : blocs réels des essais de m1bt3, marge de cinq espaces retirée
for x in o b; do
  sed -n "/^## essai-p$x : début/,/^## essai-p$x : code/{/^## /d;s/^     //;p}" "$RES/m1b-builders-m1bt3-essai_prefetch.log" > "$B/journaux/prefetch-$x.log"
  sed -n "/^## essai-c$x : début/,/^## essai-c$x : code/{/^## /d;s/^     //;p}" "$RES/m1b-builders-m1bt3-essai_construire.log" > "$B/journaux/construire-$x.log"
done
egal "journaux d'essai repris (lignes : po pb co cb)" "$(wc -l < "$B/journaux/prefetch-o.log") $(wc -l < "$B/journaux/prefetch-b.log") $(wc -l < "$B/journaux/construire-o.log") $(wc -l < "$B/journaux/construire-b.log")" "13 10 27 22"

printf '#!/bin/sh\nexit 0\n' > "$B/kbin/sleep"
cat > "$B/kbin/kubectl" <<'PY'
#!/usr/bin/env python3
# faux kubectl : politiques selon $BANC_CAS ; PipelineRuns créés = fichiers de $BANC_ETAT ; TaskRuns, pods, journaux
import json, os, sys
a = sys.argv[1:]
open(os.environ['BANC_APPELS'], 'a').write('kubectl ' + ' '.join(a) + '\n')
cas, etat, jx = os.environ['BANC_CAS'], os.environ['BANC_ETAT'], os.environ['BANC_JOURNAUX']
REG = 'sc-stockage.poc.test:5000'
IMAGE = {'o': REG + '/builds/builders/mock-rocky9', 'b': REG + '/builds/builders/rocky9-bootstrap'}
DIG = {'o': 'sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae', 'b': 'sha256:6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3'}
BASE = {'uri': 'oci://' + REG + '/amont/rockylinux/rockylinux', 'digest': 'sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2'}
MSG = 'SENTINELLE-MESSAGE'
def image(pr): return pr.split('-')[-2]   # <préfixe>-<o|b>-<i>
def digest(pr):
    x = image(pr)
    if cas == 'digest_autre' and x == 'o': return 'sha256:' + 'a' * 64
    if cas == 'divergents' and pr.endswith('o-2'): return 'sha256:' + 'c' * 64
    return DIG[x]
def echoue(pr, t): return cas == 'prefetch_echoue' and pr.endswith('o-1') and t == 'prefetch'
def pr_echoue(pr): return echoue(pr, 'prefetch')
def cond(ok):
    if cas == 'en_cours': return [{'type': 'Succeeded', 'status': 'Unknown', 'reason': 'Running', 'message': MSG}]
    return [{'type': 'Succeeded', 'status': 'True' if ok else 'False', 'reason': 'Succeeded' if ok else 'Failed', 'message': MSG}]
def taches(pr):
    if cas == 'en_cours' or pr_echoue(pr): return ['prefetch']
    return ['prefetch', 'construire', 'publier']
if a[:4] == ['get', 'networkpolicy', '-n', 'builds']:
    it = [{'metadata': {'name': 'construction-rpm-sans-sortie'}, 'spec': {'podSelector': {'matchLabels': {'tekton.dev/task': 'construire-rpm'}}, 'policyTypes': ['Ingress', 'Egress']}}]
    if cas != 'politique_absente':   # autorise : la NetworkPolicy de construction reçoit une règle de sortie
        e = {'egress': [{'to': [{'ipBlock': {'cidr': '0.0.0.0/0'}}]}]} if cas == 'autorise' else {}
        it.append({'metadata': {'name': 'construction-racine-rpm-sans-sortie'}, 'spec': {'podSelector': {'matchLabels': {'tekton.dev/task': 'construire-racine-rpm'}}, 'policyTypes': ['Ingress', 'Egress'], **e}})
    print(json.dumps({'items': it})); sys.exit(0)
if a[:4] == ['get', 'ciliumnetworkpolicy', '-n', 'builds']:
    v = ['prefetch-deb', 'prefetch-gomod', 'prefetch-rpm'] + ([] if cas == 'notin3' else ['prefetch-racine-rpm'])
    it = [{'metadata': {'name': 'builds-sans-internet'}, 'spec': {'endpointSelector': {'matchExpressions': [{'key': 'tekton.dev/task', 'operator': 'NotIn', 'values': v}]},
            'egressDeny': [{'toCIDRSet': [{'cidr': '0.0.0.0/0'}]}]}},
          {'metadata': {'name': 'prefetch-rpm-sortie'}, 'spec': {'endpointSelector': {'matchLabels': {'tekton.dev/task': 'prefetch-rpm'}}, 'egress': [{'toCIDR': ['192.168.161.13/32']}]}},
          {'metadata': {'name': 'prefetch-racine-rpm-sortie'}, 'spec': {'endpointSelector': {'matchLabels': {'tekton.dev/task': 'prefetch-racine-rpm'}}, 'egress': [{'toCIDR': ['192.168.161.13/32']}]}}]
    print(json.dumps({'items': it})); sys.exit(0)
if a[0] == 'create':
    f = json.load(open(a[a.index('-f') + 1])); s = f['spec']
    assert f['kind'] == 'PipelineRun' and 'env' not in s['taskRunTemplate']['podTemplate'] and 'params' not in s
    assert [(x['pipelineTaskName'], x['podTemplate'].get('runtimeClassName')) for x in s['taskRunSpecs']] == [('construire', 'kata')]
    assert s['workspaces'][0]['volumeClaimTemplate']['spec']['resources']['requests']['storage'] == '2Gi'
    if '--dry-run=server' in a:
        if cas == 'refus_admission': print('Error from server (Forbidden): refusé ' + MSG, file=sys.stderr); sys.exit(1)
        sys.exit(0)
    open(os.path.join(etat, f['metadata']['name']), 'w').write(s['pipelineRef']['params'][0]['value'] + ' ' + s['pipelineRef']['params'][1]['value'])
    sys.exit(0)
if a[:2] == ['get', 'pipelinerun'] and '--field-selector' in a:
    pr = a[a.index('--field-selector') + 1].split('=', 1)[1]
    if (cas == 'existe' and pr.endswith('b-2')) or os.path.exists(os.path.join(etat, pr)): print(f'pipelinerun.tekton.dev/{pr}')
    sys.exit(0)
if a[:2] == ['get', 'pipelinerun']:
    pr = a[4]
    if not os.path.exists(os.path.join(etat, pr)):
        print(f'Error from server (NotFound): pipelineruns.tekton.dev "{pr}" not found', file=sys.stderr); sys.exit(1)
    if a[6].startswith('jsonpath'):
        print('' if cas == 'non_signe' else 'true', end=''); sys.exit(0)
    ok = not pr_echoue(pr)
    o = {'metadata': {'name': pr}, 'status': {'conditions': cond(ok), 'startTime': '2026-11-20T00:00:00Z'}}
    if ok and cas != 'en_cours':
        o['status']['completionTime'] = '2026-11-20T00:04:00Z'
        o['status']['results'] = [{'name': 'IMAGE_URL', 'value': IMAGE[image(pr)]}, {'name': 'IMAGE_DIGEST', 'value': digest(pr)}]
    print(json.dumps(o)); sys.exit(0)
if a[:2] == ['get', 'taskrun']:
    if '-l' in a:
        pr = a[a.index('-l') + 1].split('=')[1]
        print(' '.join(f'{pr}-{t}' for t in taches(pr))); sys.exit(0)
    t = a[4]; pr, tache = t.rsplit('-', 1); x = image(pr); ok = not echoue(pr, tache)
    o = {'metadata': {'name': t, 'labels': {'tekton.dev/pipelineTask': tache, 'tekton.dev/pipelineRun': pr}},
         'status': {'podName': t + '-pod', 'conditions': cond(ok), 'startTime': '2026-11-20T00:00:00Z'}}
    if tache == 'prefetch':
        o['status']['taskSpec'] = {'results': [{'name': 'BASE_ARTIFACT_INPUTS', 'type': 'object'}]}
        b = dict(BASE, digest='sha256:' + 'f' * 64) if cas == 'base_autre' else BASE
        if ok and (x == 'b' or cas == 'base_ecrite'): o['status']['results'] = [{'name': 'BASE_ARTIFACT_INPUTS', 'type': 'object', 'value': b}]
    if ok and tache == 'construire': o['status']['results'] = [{'name': 'DIGEST_CONSTRUIT', 'type': 'string', 'value': digest(pr)}]
    if ok and tache == 'publier': o['status']['results'] = [{'name': 'IMAGE_URL', 'value': IMAGE[x]}, {'name': 'IMAGE_DIGEST', 'value': digest(pr)}]
    print(json.dumps(o)); sys.exit(0)
if a[:2] == ['get', 'pod']:
    p = a[4]; t = p[:-4]; pr, tache = t.rsplit('-', 1)
    lab = {'prefetch': 'prefetch-racine-rpm', 'construire': 'construire-racine-rpm', 'publier': 'publier-image'}[tache]
    d = {'limits': {'cpu': '1', 'memory': '512Mi'}, 'requests': {'cpu': '50m', 'memory': '64Mi'}}
    ko = echoue(pr, tache)
    spec = {'nodeName': 'sc-build', 'initContainers': [{'name': 'prepare', 'resources': d, 'env': [{'name': 'SENTINELLE_ENV', 'value': MSG}]}],
            'containers': [{'name': 'step-' + tache, 'resources': d, 'env': [{'name': 'SENTINELLE_ENV', 'value': MSG}]}]}
    if tache == 'construire' and cas != 'sans_kata': spec['runtimeClassName'] = 'kata'
    st = {'terminated': {'exitCode': 1, 'reason': 'Error', 'message': MSG}} if ko else {'terminated': {'exitCode': 0, 'reason': 'Completed'}}
    print(json.dumps({'metadata': {'name': p, 'labels': {'tekton.dev/task': lab}}, 'spec': spec,
        'status': {'phase': 'Failed' if ko else 'Succeeded', 'initContainerStatuses': [{'name': 'prepare', 'state': {'terminated': {'exitCode': 0, 'reason': 'Completed'}}}],
                   'containerStatuses': [{'name': 'step-' + tache, 'state': st}]}})); sys.exit(0)
if a[0] == 'logs':
    p = a[3]; pr, tache = p[:-4].rsplit('-', 1); x = image(pr)
    print('2026/11/20 00:00:00 Entrypoint initialization')
    print('ligne du banc : jeton=SENTINELLE-JETON')
    if tache == 'publier': print(f'publiée : {IMAGE[x]}@{digest(pr)} (relue en lecture anonyme)')
    else:
        j = open(os.path.join(jx, f'{tache}-{x}.log')).read().rstrip('\n').split('\n')
        if echoue(pr, tache): j = j[:5] + ['échec du banc']
        if cas == 'temoin_manquant' and tache == 'construire': j = [l for l in j if not l.startswith('témoin TCP 192.168.161.13/3000')]
        if tache == 'construire' and digest(pr) != DIG[x]: j = [l.replace(DIG[x], digest(pr)) for l in j]
        print('\n'.join(j))
    sys.exit(0)
print('appel non prévu : ' + ' '.join(a), file=sys.stderr); sys.exit(3)
PY
cat > "$B/kbin/oras" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ['BANC_APPELS'], 'a').write('oras ' + ' '.join(a) + '\n')
cas, sig = os.environ['BANC_CAS'], os.environ['BANC_SIG']
cible = a[-1]
if a[:2] == ['manifest', 'fetch'] and '--descriptor' in a:
    if cible.endswith(':m1b'):
        nom = cible.rsplit('/', 1)[1][:-4]
        d = open(os.path.join(sig, nom + '.ref')).read().strip().split('@')[1]
        if cas == 'pipeline_autre' and nom == 'builder-rocky9-bootstrap': d = 'sha256:' + 'd' * 64
    else:
        d = cible.split('@')[1]
    print(json.dumps({'mediaType': 'application/vnd.oci.image.manifest.v1+json', 'digest': d, 'size': 553})); sys.exit(0)
if a[:2] == ['repo', 'tags']:
    if cas == 'depot_present' and cible.endswith('rocky9-bootstrap'): print('sha256-6de899ac.att'); sys.exit(0)
    if cas == 'relance' and cible.endswith('mock-rocky9'): print('sha256-70f8c412.att'); sys.exit(0)
    print('Error response from registry: name unknown: repository name not known to registry', file=sys.stderr); sys.exit(1)
if a[:2] == ['manifest', 'fetch']:
    c = 2 if 'mock-rocky9' in cible else 1
    if cas == 'couches' and 'mock-rocky9' in cible: c = 1
    print(json.dumps({'layers': [{}] * c})); sys.exit(0)
print('appel non prévu : ' + ' '.join(a), file=sys.stderr); sys.exit(3)
PY
chmod +x "$B/kbin/sleep" "$B/kbin/kubectl" "$B/kbin/oras"

jouer() { # cas mesure liste [VAR=valeur…] : etape_pipeline dans la forme de lancer ; sortie dans $B/<cas>/sortie.txt ; code rendu
  local c=$1 me=$2 li=$3 w=$B/$1; shift 3
  mkdir -p "$w/etat" "$w/R"; : > "$w/appels"
  cp "$RES/m1b-builders-m1bt3-essai_construire.log" "$w/R/"
  env CONFIANCE_DIR="$w/O" DISTRO=rke2 MESURE="$me/m1bt3-05" SIG="$B/sig" LISTE_REVUE="$li" PATH="$B/kbin:$PATH" \
    BANC_CAS="$c" BANC_ETAT="$w/etat" BANC_APPELS="$w/appels" BANC_JOURNAUX="$B/journaux" BANC_SIG="$B/sig" BANC_W="$w" "$@" bash -c '
    set -euo pipefail
    . "$1"
    R=$BANC_W/R
    sur() { case $1 in sc-stockage) if [ -n "$(ls -A "$BANC_ETAT")" ]; then echo " ${BANC_LIBRE2-${BANC_LIBRE-3978911744}}"; else echo " ${BANC_LIBRE-3978911744}"; fi ;; *) echo " 50000000000" ;; esac; }
    { echo "# etape_pipeline (banc), $(date -u +%FT%TZ)"; etape_pipeline; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$BANC_W/sortie.txt" > /dev/null' _ "$SCRIPT"
}
cas() { # libellé code motif créations cas mesure liste [VAR=valeur…]
  local lib=$1 voulu=$2 motif=$3 cr=$4 c=$5 rc; shift 4
  jouer "$@"; rc=$?
  local w=$B/$c
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$w/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 3 "$w/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
  egal "$lib : PipelineRuns créés" "$(grep -c '^kubectl create -f ' "$w/appels")" "$cr"
  egal "$lib : kubectl delete" "$(grep -c '^kubectl delete' "$w/appels")" 0
  egal "$lib : sentinelles dans la sortie et les journaux copiés" "$(cat "$w/sortie.txt" "$w"/R/m1b-pipeline-*.log 2> /dev/null | grep -c 'SENTINELLE')" 0
}
ME=$B/mesure; L=$B/liste.yml

echo "## succès"
cas "succès" 0 "^écarts : 0$" 4 succes "$ME" "$L"
egal "succès : ordre des PipelineRuns et pipelines" "$(grep '^kubectl create -f ' "$B/succes/appels" | sed 's#.*/pr-\(.*\)\.json#\1#' | paste -sd' ')" "m1b-o-1 m1b-o-2 m1b-b-1 m1b-b-2"
egal "succès : pipeline de chaque PipelineRun (nom)" "$(for p in m1b-o-1 m1b-o-2 m1b-b-1 m1b-b-2; do cut -d' ' -f2 "$B/succes/etat/$p"; done | paste -sd' ')" \
  "builder-mock-rocky9 builder-mock-rocky9 builder-rocky9-bootstrap builder-rocky9-bootstrap"
egal "succès : bundle de chaque PipelineRun = référence de la signature" "$(for p in m1b-o-1 m1b-b-1; do cut -d' ' -f1 "$B/succes/etat/$p"; done | paste -sd' ')" \
  "$(cat "$B/sig/builder-mock-rocky9.ref") $(cat "$B/sig/builder-rocky9-bootstrap.ref")"
egal "succès : journaux des pas copiés dans R" "$(find "$B/succes/R" -name 'm1b-pipeline-m1b-*.log' | wc -l)" 8
egal "succès : lignes masquées dans les journaux copiés" "$(cat "$B/succes/R"/m1b-pipeline-*.log | grep -c '^\[ligne masquée : motif jeton|token\]$')" 8
egal "succès : contrôles OK" "$(grep -c '^OK   ' "$B/succes/sortie.txt")" 113
egal "succès : tailles lues dans le journal d'essai" "$(grep -c '^[ob] : image.tar de l.essai m1bt3-c[ob] : \(343951360\|241991680\) octets$' "$B/succes/sortie.txt")" 2
egal "succès : outillage, résultat déclaré non écrit relevé" "$(grep -c '^relevé : outillage, BASE_ARTIFACT_INPUTS déclaré : 1 ; ligne « non écrit » : 1$' "$B/succes/sortie.txt")" 2
egal "succès : garde de place relevée avec la taille" "$(grep -c '(garde : 1073741824 + \(343951360\|241991680\))$' "$B/succes/sortie.txt")" 4

echo "## gardes avant toute création"
cas "mesure divergente" 1 "^KO   o : digest du banc de m1bt3 égal à celui de m1bt3 : sha256:e{64}" 0 mesure_div "$B/mesure-div" "$L"
cas "pipeline autre au tag m1b" 1 "^KO   builder-rocky9-bootstrap relue dans Zot au tag m1b" 0 pipeline_autre "$ME" "$L"
cas "tâche hors de la liste revue" 1 "^KO   absente de la liste revue : .*construire-racine-rpm@" 0 non_listee "$ME" "$B/liste-sans.yml"
cas "NotIn à trois labels" 1 "^KO   NotIn de builds-sans-internet : prefetch-deb,prefetch-gomod,prefetch-rpm " 0 notin3 "$ME" "$L"
cas "NetworkPolicy de construction absente" 1 "^KO   politiques qui sélectionnent un pod de construire-racine-rpm : CiliumNetworkPolicy builds-sans-internet " 0 politique_absente "$ME" "$L"
cas "politique qui autorise la construction" 1 "^KO   politiques qui autorisent du trafic à un pod de construire-racine-rpm : NetworkPolicy construction-racine-rpm-sans-sortie " 0 autorise "$ME" "$L"
cas "PipelineRun déjà présent" 1 "^KO   m1b-b-2 existe déjà" 0 existe "$ME" "$L"
cas "dépôt déjà présent" 1 "^KO   dépôt .*/builds/builders/rocky9-bootstrap absent \(aucune publication antérieure ; sinon décision avant toute relance\) : 0" 0 depot_present "$ME" "$L"
cas "relance sous un autre préfixe après publication de l'outillage" 1 "^KO   dépôt .*/builds/builders/mock-rocky9 absent \(aucune publication" 0 relance "$ME" "$L" PREFIXE=m1c
cas "espace sous la garde d'entrée (deux images)" 1 "^KO   espace libre illisible ou sous la garde d'entrée" 0 plein "$ME" "$L" BANC_LIBRE=1659684863
cas "espace sous la garde d'une image" 1 "^KO   espace libre illisible ou sous la garde d'entrée" 0 plein1 "$ME" "$L" BANC_LIBRE=1417693183
cas "place tombée après le premier PipelineRun" 1 "^KO   espace libre illisible ou sous la garde sur sc-stockage$" 1 tombee "$ME" "$L" BANC_LIBRE2=1417693183
egal "place tombée : m1b-o-1 contrôlé jusqu'au bout avant le refus" "$(grep -c '^OK   PipelineRun m1b-o-1 signé par Chains : true$' "$B/tombee/sortie.txt")" 1
cas "refus à l'admission" 1 "^KO   m1b-o-1 admis en dry-run serveur .* : 1" 0 refus_admission "$ME" "$L"
echo "## contrôles après création"
cas "prefetch de l'outillage en échec" 1 "^KO   PipelineRun m1b-o-1 : False\|Failed" 1 prefetch_echoue "$ME" "$L"
egal "prefetch en échec : preuve imprimée avant le KO" "$(grep -c '^### TaskRun m1b-o-1-prefetch (tâche prefetch) : False|Failed' "$B/prefetch_echoue/sortie.txt")" 1
cas "digest autre (outillage)" 1 "^écarts : 4$" 4 digest_autre "$ME" "$L"
cas "digests divergents" 1 "^ÉCART builder-mock-rocky9 : deux exécutions, même digest" 4 divergents "$ME" "$L"
cas "construction sans Kata" 1 "^KO   m1b-o-1, construire : tekton.dev/task\|runtimeClassName\|nœud : construire-racine-rpm\|\|sc-build" 1 sans_kata "$ME" "$L"
cas "témoin réseau absent" 1 "^KO   construire : témoins réseau en échec : 2" 1 temoin_manquant "$ME" "$L"
cas "couches" 1 "^KO   manifeste relu dans Zot .* : sha256:70f8c412[0-9a-f]* 1 " 1 couches "$ME" "$L"
cas "non signé par Chains" 1 "^KO   PipelineRun m1b-o-1 signé par Chains : absente" 1 non_signe "$ME" "$L"
cas "base du bootstrap autre" 1 "^KO   prefetch \(bootstrap\) : BASE_ARTIFACT_INPUTS" 3 base_autre "$ME" "$L"
cas "base écrite pour l'outillage" 1 "^KO   prefetch \(outillage\) : BASE_ARTIFACT_INPUTS absent des résultats du TaskRun : 1" 1 base_ecrite "$ME" "$L"
cas "PipelineRun jamais terminé" 1 "^KO   PipelineRun m1b-o-1 : Unknown\|Running" 1 en_cours "$ME" "$L"

echo "# fin $(date -u +%FT%TZ) ; OK $n ; KO $k"
[ "$k" = 0 ]
