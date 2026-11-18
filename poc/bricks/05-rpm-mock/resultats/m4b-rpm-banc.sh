#!/usr/bin/env bash
# Brique 05, M4b : banc hors cluster et hors Zot de l'étape rpm de m4b.sh (préparée à sec le 18/11/2026, accord permanent du 18/11),
# écrit avant tout passage.
# A : insertions seules contre le m4b.sh d'avant (deux blocs : en-tête, bloc avant lancer) ; aucun nom de fonction ni de variable du
#     bloc déjà défini avant ; bash -n ; shellcheck : mêmes codes avant et après.
# B : la vraie fonction etape_rpm, dans une copie jouable (commun.sh et lancer neutralisés), avec la vraie liste, le vrai verrou, la
#     vraie liste revue de la 08 et la vraie fonction listee de commun.sh ; faux : kubectl (état des PipelineRuns dans un dossier,
#     TaskRuns, pods, journaux), oras (descripteur de la pipeline, tags du dépôt, manifeste), sleep (immédiat), sur (espace libre),
#     signe. Un message de condition sentinelle est posé dans chaque PipelineRun et TaskRun faux : il ne doit jamais sortir.
#     Cas : succès ; digest autre que le calcul (non exigé) ; échec de prefetch (OOMKilled : preuve imprimée avant le KO) ;
#     PipelineRun du même nom déjà présent ; dépôt déjà présent ; espace sous la garde ; pipeline autre au tag m4b ; digests
#     divergents entre les deux PipelineRuns ; 229 couches relues ; PipelineRun jamais terminé (attente épuisée).
#     Dans chaque cas : aucun appel de kubectl delete ; créations comptées.
# Non couvert : Tekton (résolveur, Trusted Resources, pods réels, place-scripts réel), Kyverno, Chains, Zot, réseau.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4b-rpm-banc.sh <dossier-neuf> <m4b.sh avant> <m4b.sh>
set -uo pipefail
export LC_ALL=C
B=$1; AVANT=$2; COPIE=$3
RACINE=$PWD
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B/kbin"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4b-rpm-banc.sh, $(date -u +%FT%TZ) ; m4b.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; m4b.sh $(sha256sum < "$COPIE" | cut -c1-64)"

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
python3 -I - "$COPIE" "$B/m4b-jouable.sh" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text().split('\n')
r = {'. "$here/commun.sh"   # repo, O, S, P, W, REG, lancer, chrono': ':', 'h05=$(cd "$(dirname "$0")" && pwd)': 'h05=$RACINE/poc/bricks/05-rpm-mock',
     'lancer m4b "05 M4b" "$@"': ':'}
assert all(t.count(a) == 1 for a in r)
pathlib.Path(sys.argv[2]).write_text('\n'.join(r.get(l, l) for l in t))
PY
printf '#!/bin/sh\nexit 0\n' > "$B/kbin/sleep"
cat > "$B/kbin/kubectl" <<'PY'
#!/usr/bin/env python3
# faux kubectl : PipelineRuns créés = fichiers de $BANC_ETAT ; TaskRuns, pods et journaux selon $BANC_CAS
import json, os, sys
a = sys.argv[1:]
open(os.environ['BANC_APPELS'], 'a').write('kubectl ' + ' '.join(a) + '\n')
cas, etat = os.environ['BANC_CAS'], os.environ['BANC_ETAT']
CALC = 'sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c'
DEPOT = 'sc-stockage.poc.test:5000/builds/fermetures/sample-app-rpm'
SRC = 'sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6'
MSG = 'SENTINELLE-MESSAGE'
def digest(pr):
    if cas == 'digest_autre': return 'sha256:' + 'a' * 64
    if cas == 'divergents' and pr.endswith('-2'): return 'sha256:' + 'b' * 64
    return CALC
def cond(ok):
    if cas == 'en_cours': return [{'type': 'Succeeded', 'status': 'Unknown', 'reason': 'Running', 'message': MSG}]
    return [{'type': 'Succeeded', 'status': 'True' if ok else 'False', 'reason': 'Succeeded' if ok else 'Failed', 'message': MSG}]
def echoue(pr): return cas == 'echec_prefetch' and pr.endswith('-1')
if a[0] == 'create':
    f = json.load(open(a[a.index('-f') + 1]))
    assert f['kind'] == 'PipelineRun' and 'env' not in f['spec']['taskRunTemplate']['podTemplate']
    if '--dry-run=server' not in a:
        open(os.path.join(etat, f['metadata']['name']), 'w').close()
    sys.exit(0)
if a[0] == 'get' and a[1] == 'pipelinerun':
    pr = a[4]
    if cas == 'existe' and pr == 'm4b-rpm-1' and not os.path.exists(os.path.join(etat, pr)):
        open(os.path.join(etat, pr), 'w').close()
    if not os.path.exists(os.path.join(etat, pr)):
        print(f'Error from server (NotFound): pipelineruns.tekton.dev "{pr}" not found', file=sys.stderr); sys.exit(1)
    if a[6] == 'name': print(f'pipelinerun.tekton.dev/{pr}'); sys.exit(0)
    ok = not echoue(pr)
    o = {'metadata': {'name': pr}, 'status': {'conditions': cond(ok), 'startTime': '2026-11-18T00:00:00Z'}}
    if ok and cas != 'en_cours':
        o['status']['completionTime'] = '2026-11-18T00:01:00Z'
        o['status']['results'] = [{'name': 'IMAGE_URL', 'value': DEPOT}, {'name': 'IMAGE_DIGEST', 'value': digest(pr)}]
    print(json.dumps(o)); sys.exit(0)
if a[0] == 'get' and a[1] == 'taskrun':
    if '-l' in a:
        pr = a[a.index('-l') + 1].split('=')[1]
        print(f'{pr}-prefetch' if echoue(pr) or cas == 'en_cours' else f'{pr}-prefetch {pr}-publier'); sys.exit(0)
    t = a[4]; pr = t.rsplit('-', 1)[0]; ok = not (echoue(pr) and t.endswith('prefetch'))
    o = {'metadata': {'name': t}, 'status': {'podName': t + '-pod', 'conditions': cond(ok)}}
    if ok and t.endswith('prefetch'):
        o['status']['results'] = [{'name': 'BOOTSTRAP_ARTIFACT_INPUTS', 'type': 'object',
            'value': {'digest': SRC.split('@')[1], 'uri': 'oci://' + SRC.split('@')[0]}}]
    print(json.dumps(o)); sys.exit(0)
if a[0] == 'get' and a[1] == 'pod':
    p = a[4]; pas = 'step-prefetch' if 'prefetch' in p else 'step-publier'
    oom = echoue(p.rsplit('-', 2)[0]) and pas == 'step-prefetch'
    d = {'limits': {'cpu': '1', 'memory': '512Mi'}, 'requests': {'cpu': '50m', 'memory': '64Mi'}}
    r = {'limits': {'cpu': '2', 'memory': '2Gi'}, 'requests': {'cpu': '2', 'memory': '2Gi'}} if pas == 'step-prefetch' else d
    term = {'terminated': {'exitCode': 137, 'reason': 'OOMKilled', 'message': MSG}} if oom else {'terminated': {'exitCode': 0, 'reason': 'Completed'}}
    print(json.dumps({'metadata': {'name': p, 'labels': {'tekton.dev/task': 'prefetch-rpm' if 'prefetch' in p else 'publier-fermeture'}},
        'spec': {'nodeName': 'sc-build', 'initContainers': [{'name': 'prepare', 'command': ['/ko-app/entrypoint'], 'args': ['init'], 'resources': d},
            {'name': 'place-scripts', 'command': ['sh'], 'args': ['-c', 'x' * 59848], 'resources': d}],
            'containers': [{'name': pas, 'resources': r, 'env': [{'name': 'SENTINELLE_ENV', 'value': MSG}]}]},
        'status': {'phase': 'Failed' if oom else 'Succeeded',
            'initContainerStatuses': [{'name': 'prepare', 'state': {'terminated': {'exitCode': 0, 'reason': 'Completed'}}},
                {'name': 'place-scripts', 'state': {'terminated': {'exitCode': 0, 'reason': 'Completed'}}}],
            'containerStatuses': [{'name': pas, 'state': term}]}})); sys.exit(0)
if a[0] == 'logs':
    p = a[3]; pr = p.rsplit('-', 2)[0]
    print('2026/11/18 00:00:00 Entrypoint initialization')
    if 'prefetch' in p:
        print('téléchargés et contrôlés (sha256, taille) : 222')
        if echoue(pr): sys.exit(0)
        print('rpm -K : rc 0, 222 OK sur 222')
        print('repodata V2 : repomd.xml 239a5a71c887d4370228ffdff016517282086f19de93418ee740482c089be164 ; fichiers 4 ; en 1 s')
        for _ in range(37): print('repomd.xml V2 :   <data/>')
    else:
        print('/tekton/scripts/script-0-xxxxx: line 17: can\'t open bom.json: no such file')
        print(f'publiée : {DEPOT}@{digest(pr)} (230 couches, relue en lecture anonyme) ; SBOM de Hermeto non publié : ')
    sys.exit(0)
print('appel non prévu : ' + ' '.join(a), file=sys.stderr); sys.exit(3)
PY
cat > "$B/kbin/oras" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ['BANC_APPELS'], 'a').write('oras ' + ' '.join(a) + '\n')
cas = os.environ['BANC_CAS']
if a[:2] == ['manifest', 'fetch'] and '--descriptor' in a:
    d = 'sha256:' + 'c' * 64 if cas == 'pipeline_autre' else 'sha256:9b89b0299353cd66f37c02484628d5d177f27043624f3f05b8f1a642738eb9db'
    print(json.dumps({'mediaType': 'application/vnd.oci.image.manifest.v1+json', 'digest': d, 'size': 566})); sys.exit(0)
if a[:2] == ['repo', 'tags']:
    if cas == 'depot_present': print('m4b'); sys.exit(0)
    print('Error response from registry: name unknown: repository name not known to registry', file=sys.stderr); sys.exit(1)
if a[:2] == ['manifest', 'fetch']:
    print(json.dumps({'layers': [{}] * (229 if cas == 'couches229' else 230)})); sys.exit(0)
print('appel non prévu : ' + ' '.join(a), file=sys.stderr); sys.exit(3)
PY
chmod +x "$B/kbin/sleep" "$B/kbin/kubectl" "$B/kbin/oras"
eval "$(sed -n '/^listee() {/,/^}/p' "$RACINE/poc/bricks/08-trust-plane/commun.sh")"
export -f listee

jouer() { # cas : etape_rpm de la copie jouable, sortie dans $B/<cas>.out ; code dans $B/<cas>.rc
  local c=$1
  mkdir -p "$B/$c/etat" "$B/$c/W"
  ( export BANC_CAS=$c BANC_ETAT=$B/$c/etat BANC_APPELS=$B/$c/appels.txt RACINE PATH=$B/kbin:$PATH
    REG=sc-stockage.poc.test:5000 REG_HOTE=192.168.161.13:5000 P=$B/P W=$B/$c/W S=$B/S O=$B/O
    sur() { [ "$BANC_CAS" = plein ] && echo "  100" || echo " 4472213504"; }
    signe() { echo true; }
    # shellcheck disable=SC1090
    . "$B/m4b-jouable.sh"
    { etape_rpm; } 2>&1 ) > "$B/$c.out"
  echo $? > "$B/$c.rc"
  touch "$B/$c/appels.txt"
}
creations() { grep -c '^kubectl create -f ' "$B/$1/appels.txt" || true; }
suppressions() { grep -c '^kubectl delete' "$B/$1/appels.txt" || true; }
sentinelle() { grep -c 'SENTINELLE' "$B/$1.out" || true; }

echo "## B : etape_rpm, faux kubectl et faux oras"
for c in succes digest_autre echec_prefetch existe depot_present plein pipeline_autre divergents couches229 en_cours; do
  jouer "$c"
  echo "### cas $c : code $(cat "$B/$c.rc") ; créations $(creations "$c") ; suppressions $(suppressions "$c") ; sentinelles $(sentinelle "$c")"
  grep -E '^(OK|KO)   |place-scripts|conteneur step|digest relevé' "$B/$c.out" | cut -c1-200 | sed 's/^/     /' | tail -n 8
  egal "$c : aucune suppression" "$(suppressions "$c")" 0
  egal "$c : ni message de condition ni variable d'environnement affichés" "$(sentinelle "$c")" 0
done
egal "succes : code, créations" "$(cat "$B/succes.rc") $(creations succes)" "0 2"
egal "succes : deux exécutions, même fermeture" "$(grep -c '^OK   deux exécutions, même fermeture' "$B/succes.out")" 1
egal "succes : digest égal au calcul, relevé deux fois" "$(grep -c 'calculé à sec .* : égaux (relevé, non exigé)' "$B/succes.out")" 2
egal "succes : place-scripts relevé (59848 octets)" "$(grep -c 'place-scripts : commande \["sh"\], 2 argument(s), dernier argument 59848 octets (reconstruit à sec : 59848)' "$B/succes.out")" 4
egal "succes : lignes de repomd.xml imprimé non répétées" "$(grep -c 'repomd.xml V2 :   <data/>' "$B/succes.out")" 0
egal "succes : OK" "$(grep -c '^OK   ' "$B/succes.out")" 23
egal "digest_autre : passe, digest différent du calcul relevé" "$(cat "$B/digest_autre.rc") $(grep -c ': différents (relevé, non exigé)' "$B/digest_autre.out")" "0 2"
egal "echec_prefetch : code, créations" "$(cat "$B/echec_prefetch.rc") $(creations echec_prefetch)" "1 1"
egal "echec_prefetch : OOMKilled imprimé avant le KO" \
  "$(awk '/conteneur step-prefetch : terminated code 137 raison OOMKilled/ && !o {o = NR} /^KO   PipelineRun m4b-rpm-1/ && !q {q = NR} END {print (o && q && o < q) ? "avant" : "non"}' "$B/echec_prefetch.out")" avant
egal "echec_prefetch : KO" "$(grep '^KO' "$B/echec_prefetch.out")" "KO   PipelineRun m4b-rpm-1 : False|Failed (attendu : True|Succeeded)"
for c in existe depot_present plein pipeline_autre; do
  egal "$c : arrêt avant toute création (code, créations, dry-run)" "$(cat "$B/$c.rc") $(creations "$c") $(grep -c 'dry-run=server' "$B/$c/appels.txt" || true)" "1 0 0"
done
egal "existe : KO" "$(grep '^KO' "$B/existe.out")" "KO   m4b-rpm-1 existe déjà : rien n'est purgé, décision avant toute relance"
egal "plein : KO" "$(grep '^KO' "$B/plein.out")" "KO   espace libre illisible ou sous la garde sur sc-stockage"
egal "divergents : code, créations, KO final" "$(cat "$B/divergents.rc") $(creations divergents) $(grep -c '^KO   deux exécutions, même fermeture' "$B/divergents.out")" "1 2 1"
egal "couches229 : code, créations, KO" "$(cat "$B/couches229.rc") $(creations couches229) $(grep -c '^KO   manifeste relu dans Zot (lecture anonyme) : couches : 229' "$B/couches229.out")" "1 1 1"
egal "en_cours : code, créations, KO après relevé" "$(cat "$B/en_cours.rc") $(creations en_cours) $(grep -c '^KO   PipelineRun m4b-rpm-1 : Unknown|Running' "$B/en_cours.out")" "1 1 1"
egal "en_cours : attente de 1800 lectures" "$(grep -c '^kubectl get pipelinerun -n builds m4b-rpm-1 -o json$' "$B/en_cours/appels.txt")" 1802
echo "# bilan : $n OK, $k KO ; fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
