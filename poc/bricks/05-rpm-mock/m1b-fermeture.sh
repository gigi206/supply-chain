#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b (§5 de resultats/m1b-carte.md), quatrième point : M4b refait sous un préfixe, avec le bootstrap de
# M1b (builds/builders/rocky9-bootstrap@6de899ac, verrou resultats/m1b-verrou.json c544599a) et la tâche prefetch-rpm de la
# cascade (tekton/tasks/prefetch-rpm@b9bbeba3, outillage 70f8c412, liste revue). Préparé à sec le 20/11/2026. Script frère de
# m4b.sh, qui n'est pas touché : son gabarit, sa pipeline (tag m4b, 9b89b029), sa fermeture (2a9e2ea7) et ses journaux restent
# tels quels. Le gabarit de la pipeline est rendu sans changement ; seuls changent la référence de prefetch-rpm, la source et le
# dossier dir: du bootstrap (trois feuilles, contrôlées contre le bundle de M4b relu dans Zot).
# Repris à l'identique de m1b-bundles.sh (lui-même copie de m4b.sh et m4c.sh ; le banc les compare) : attendu, ref_revue, echec,
# admission, libre_zot, normaliser, remplacer, rendre_taches, substituer, pod_spec, dans, ARBRE, neuf, sha, zot_lire,
# DIFF_FEUILLES, diff_feuilles ; etape_essai_prefetch devient etape_essai (remplacements listés et comptés par le banc).
#   local   hôte, plus des lectures anonymes de Zot (rien n'est écrit) : sources contrôlées par sha256 ; témoin de méthode : la
#           pipeline signée de M4b relue dans son bundle (9b89b029) est égale, normalisée, au gabarit rendu avec les entrées de M4b ;
#           rendu neuf : exactement trois feuilles différentes ; scripts substitués (M4b 572fb78c, neuf épinglé) ; références de la
#           liste revue ; manifeste du bootstrap neuf relu (sha256 = pull_digest, configuration = bootstrap.id) ; arbre et digest
#           prédits par resultats/m1b-fermeture-digest.py, avec son témoin (bootstrap de M4b : arbre de final, digest 2a9e2ea7) ;
#           gardes de Zot relues (tag neuf de la pipeline absent, tag m4b sur 9b89b029, fermeture de M4b présente).
#   essai   pod d'essai runc (rien dans Zot), copie de essai_prefetch de m1b-bundles.sh : le script substitué neuf, tel que Tekton
#           le jouera ; repomd.xml V2, résultat de bootstrap, arbre égal à l'arbre prédit, archivé sous
#           resultats/$PREFIXE-fermeture-essai-arbre.txt ; cas refusé (repomd.xml faux) ; pod et PVC retirés.
#   pipeline  ajoutée le 20/11/2026 après la décision du propriétaire « Même dépôt, par digest » ; SIGNER=1 seulement, sur accord
#           nommé (signature, écriture dans Zot) : gardes (tag neuf absent, tag m4b sur 9b89b029, références de la liste revue, place
#           libre) ; pipeline rendue admise en dry-run serveur, trois feuilles de différence avec M4b, script substitué égal à celui
#           de l'essai ; signée par tkn (clé des tâches, jamais lue ici), relue, versionnée sous
#           fermeture/prefetch-rpm-sample-app.$TAG.signee.yaml ; bundle tekton/pipelines/prefetch-rpm-sample-app:$TAG ; relue
#           anonymement (égale à la versionnée), tag m4b inchangé. Son digest est épinglé ensuite dans PIPELINE_REF, par correction
#           datée et banc rejoué.
#   rpm     ajoutée de même, sur accord nommé (cluster et écritures dans Zot) : etape_rpm de m4b.sh, transformée par des
#           remplacements listés et comptés (resultats/m1b-fermeture-copies.py) : deux PipelineRuns $PREFIXE-rpm-1 et -2 de la
#           pipeline neuve ; gardes : PIPELINE_REF épinglée et relue au tag, tag m4b inchangé, arbre de l'essai archivé égal à
#           l'arbre prédit, fermeture de M4b présente dans le même dépôt, fermeture prédite absente avant le premier ; couches
#           attendues = fichiers de l'arbre de l'essai ; digest relevé à côté du digest prédit, sans en dépendre ; fermeture de M4b
#           toujours présente après. Écritures définitives dans Zot (fermeture par digest, attestations de Chains).
#   comparaison  ajoutée le 20/11/2026 après rpm (accord permanent, lecture seule) : etape_comparaison de m4b.sh transformée
#           (remplacements comptés) : IMAGE_DIGEST des deux PipelineRuns, manifeste relu, fermeture tirée par digest dans un dossier
#           neuf (lecture anonyme), confrontée à l'arbre de l'essai ; 222 rpm de la liste, repomd.xml, image de bootstrap neuve.
#   provenance  ajoutée de même (lecture seule) : etape_provenance de m4b.sh transformée : attestations du sujet vérifiées par
#           cosign (clé de Chains), une par PipelineRun ; dépendances et paramètres égaux à l'attendu (références de la cascade) ;
#           refus avec une autre clé.
# DEPOT_FERMETURE est celui de M4b (décision « Même dépôt, par digest », 20/11/2026) : publier-fermeture n'écrit que par digest.
# Un journal existant n'est jamais réécrit : relancer sous un autre PREFIXE.
# Usage (racine du dépôt) : [PREFIXE=m1b] [TAG=$PREFIXE] DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m1b-fermeture.sh <étape>…
#         (journaux : resultats/$PREFIXE-fermeture-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, listee, sur, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
N=${PREFIXE:-m1b}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
TAG=${TAG:-$N}
case $TAG in m4b|m4c|essai) echo "tag refusé : $TAG appartient à M4b, M4c ou aux essais" >&2; exit 2 ;; ''|*[!a-z0-9-]*) echo "TAG invalide : $TAG" >&2; exit 2 ;; esac
T=$W/$N-fermeture-05
mkdir -p "$T"
umask 022

IMAGE=$REG/builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae   # M1b ; rendre_taches, pod_spec
IMAGE_ESSAI=$REG/essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771   # M4b (témoin)
TACHES=$h05/fermeture
GABARITS_SHA="fermeture/prefetch-rpm.yaml:96b9d6bd056224eeed144fc1d1b093820a32b2fa26e46f2217f797782837968c
fermeture/prefetch-rpm-sample-app.yaml:ee74c25874a43d14051c6f2d11aa53b264ac688bebfec970036a50c42192b534
fermeture/prefetch-rpm.signee.yaml:4123539575b1f7986f82f648913ee147348c7198399018f3520c7037eeade199
fermeture/prefetch-rpm.m1b.signee.yaml:d28acd2283bdf9648619c22055001b2436ddf228e1c1350d107cbe9af0a142e2
resultats/m1b-fermeture-digest.py:a5d014290f0a6d4ce08e54b2693608f63dd0b18539f183199011b9c138d95f32"   # gabarits et tâches signées de M4b et de la cascade (lus seulement)
SIGNEE=$TACHES/prefetch-rpm.m1b.signee.yaml
LISTE_REVUE=$here/politique/porte/taches.yml   # lue par ref_revue (copie)
LISTE=$R/m4b-liste.txt
LISTE_SHA=95541ee86a3c8891d231df6896558a78f73a607037b2a7035312337ab80b8910   # m4b.sh
VERROU_SRC=$R/m1b-verrou.json
VERROU_SHA=c544599aba4b7460f7496066e7c0361c80a59b8e345655553509024a254a6c83   # m1b-verrou.sh verrou (6da4e4a1)
VERROU_M4B=$R/s1-verrou_derivee.json
VERROU_M4B_SHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f   # m4b.sh
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D   # m4b.sh
REPOMD_V2=239a5a71c887d4370228ffdff016517282086f19de93418ee740482c089be164   # m4b.sh
DEPOT_FERMETURE=$REG/builds/fermetures/sample-app-rpm   # celui de M4b : décision « Même dépôt, par digest » (20/11/2026)
FERMETURE_M4B=sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c   # m4b.sh (FERMETURE_RPM)
PREFETCH_REF=$REG/tekton/tasks/prefetch-rpm@sha256:b9bbeba3e8c62113431cdb88aa74afe76bab13a28ab548a5b5ae6ffed22675dc   # cascade, liste revue (e2f15c1b)
PREFETCH_M4B=$REG/tekton/tasks/prefetch-rpm@sha256:9afe09db6d97d065c29245417a44e54a147b5f32a7e37b7ff5f9616c8110893a   # m4b.sh
PUBLIER_REF=$REG/tekton/tasks/publier-fermeture@sha256:7fa92ad3e4adb0d4b9bc4209ee04096d476dee5ffa173fc08b9cac0614e2b135   # m4b.sh
PIPELINE_M4B=tekton/pipelines/prefetch-rpm-sample-app@sha256:9b89b0299353cd66f37c02484628d5d177f27043624f3f05b8f1a642738eb9db   # m4b.sh
SCRIPT_M4B_SHA=572fb78cf6b3104dbbbe2c834d236d313f1eb49e0da9b4171d03fc299fc42145   # SCRIPT_ESSAI_SHA de m4b.sh
SCRIPT_NEUF_SHA=4d8bfe827d718b275b056f1c52ecd0a519b2736529f93e0fc56d18aa01b02d0c  # calcul à sec du 20/11 (m1b-fermeture-predictions)
ARBRE_REF=$R/m4b-final-arbre.txt
ARBRE_REF_SHA=fc556539d9fe7255a7e65fa25278d37c7f85fd728ee97f08c8d8ea2c9f35e880   # m4b.sh
BOOT_M4B=essais-05/rocky9-bootstrap@sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6   # verrou de M4b (témoin)
ARBRE_PREDIT_SHA=a731fbce8ba11021508ff700e2ba6f72d976a92c5c835ba8e419b4ff88db014a   # calcul à sec du 20/11
DIGEST_PREDIT=sha256:0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f # calcul à sec du 20/11 ; relevé à rpm, jamais exigé
ARBRE_ESSAI=$R/$N-fermeture-essai-arbre.txt   # étape essai (bf35d748 pour m1b)
# Pipeline et PipelineRuns
PIPELINE_REF=$REG/tekton/pipelines/prefetch-rpm-sample-app@sha256:61814acd6f15f0fde07f9f701f2e8cfd4324218caf2df9e1befcf182495ca60c   # étape pipeline du 20/11 (m1b-fermeture-pipeline.log) ; rpm refuse de tourner si vide
LIBRE_MIN=1073741824   # garde : octets libres sur / de sc-stockage (porte /var/lib/zot), comme m4b.sh
ARGS_RECONSTRUIT='non refait ici (59848 en M4b)'   # lu par releve_pod (copie de m4b.sh) ; relevé, jamais exigé
FERMETURE_NEUVE=sha256:0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f   # étape rpm du 20/11 (m1b-fermeture-rpm.log)
CLE_CHAINS=$here/resultats/chains-cle-publique.pem   # m4b.sh
CLE_CHAINS_SHA=1e7b2a03f9d5d289898e63b57410aeafa4e3680e86474d4f35aaa4e01f0c5e65   # m4b.sh
HORODATAGE=$REG/plateforme/outils-horodatage@sha256:c7bebae2bd33e57792988b8ba215536dd9360a9871ec0bdf807ee94d4c1f4ca0   # m4b.sh (pas de publier-fermeture)
# Pod d'essai (valeurs de m4b.sh)
LABEL=prefetch-rpm
LIMITES='{"cpu": "2", "memory": "2Gi"}'
VOLUME=4Gi
FACTICE=sha256:$(printf '0%.0s' {1..64})

# --- recopié de m1b-bundles.sh ---
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
ref_revue() { # dépôt-de-tâche préfixe-du-digest : référence complète lue dans la liste revue de la 08 (une seule) ; de s4d.sh
  local r
  r=$(awk -v d="oci://$REG/tekton/tasks/$1:" -v p="sha256:$2" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && index($3, p) == 1 {print $3}' "$LISTE_REVUE")
  [ "$(grep -c . <<< "$r")" = 1 ] && [ -n "$r" ] || { echo "KO   $1 $2 : absente de la liste revue ou ambiguë" >&2; exit 1; }
  echo "$REG/tekton/tasks/$1@$r"
}
echec() { echo "KO   $*" >&2; exit 1; }
admission() { # fichier : kubectl create --dry-run=server dans builds (rien n'est créé) ; code de kubectl, sortie dans $T/admission.out (m4b.sh)
  local rc=0
  kubectl create --dry-run=server -n builds -f "$1" < /dev/null > "$T/admission.out" 2>&1 || rc=$?
  echo "$rc"
}
libre_zot() { sur sc-stockage 'df -B1 --output=avail / | tail -n 1' < /dev/null | tr -d ' '; }   # m4b.sh
normaliser() { # fichier : JSON sans la signature ni les « resources: {} », « description: "" » et « annotations: {} » que tkn écrit
  # (mesuré au banc du 18/11), clés triées
  yq -o=json -I=0 'del(.metadata.annotations["tekton.dev/signature"]) | del(.. | select(tag == "!!map" and length == 0 and (path | .[-1]) == "resources"))
    | del(.. | select(tag == "!!str" and . == "" and (path | .[-1]) == "description"))
    | del(.metadata.annotations | select(length == 0)) | sort_keys(..)' "$1"
}
remplacer() { # source destination clé=valeur… : @CLE@ remplacées hors des commentaires ; LISTE = fichier indenté (s4b.sh de la 06)
  python3 -I - "$@" <<'FIN'
import sys
src, dst, *kv = sys.argv[1:]
paires = [a.split('=', 1) for a in kv]
r = []
for ligne in open(src, encoding='utf-8').read().split('\n'):
    if not ligne.lstrip().startswith('#'):   # les commentaires citent les variables : non rendus
        for k, v in paires:
            if k == 'LISTE':
                v = open(v, encoding='utf-8').read().rstrip('\n')
            ligne = ligne.replace(f'@{k}@', v)
    r.append(ligne)
open(dst, 'w', encoding='utf-8').write('\n'.join(r))
FIN
  ! grep -n '@[A-Z_]*@' "$2" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans ${2##*/}" >&2; exit 1; }
}
rendre_taches() { # référence-prefetch-rpm référence-publier-fermeture source dossier : gabarits rendus sous $T
  sed 's/^/        /' "$LISTE" > "$T/liste-indentee.txt"
  remplacer "$TACHES/prefetch-rpm.yaml" "$T/prefetch-rpm.yaml" "IMAGE=$IMAGE"
  remplacer "$TACHES/prefetch-rpm-sample-app.yaml" "$T/prefetch-rpm-sample-app.yaml" "PREFETCH_RPM=$1" "PUBLIER_FERMETURE=$2" \
    "LISTE=$T/liste-indentee.txt" "SOURCE=$3" "DOSSIER=$4" "EMPREINTE=$FP_ROCKY" "REPOMD=$REPOMD_V2" "DEPOT_FERMETURE=$DEPOT_FERMETURE"
}
substituer() { # tâche-rendue pipeline-rendue chemin-du-workspace chemin-du-résultat sortie [repomd] : script du pas, comme Tekton
  python3 -I - "$@" <<'FIN'
import json, subprocess, sys
tache, pipe, ws, res, out = sys.argv[1:6]
y = lambda f, q: json.loads(subprocess.run(['yq', '-o=json', q, f], capture_output=True, text=True, check=True).stdout)
s = y(tache, '.spec.steps[0].script')
p = {x['name']: x['value'] for x in y(pipe, '.spec.tasks[0].params')}
if len(sys.argv) > 6:
    p['repomd'] = sys.argv[6]   # cas refusé de essai_tache seulement
assert sorted(p) == ['dossier', 'empreinte', 'liste', 'repomd', 'source'], sorted(p)
for k, v in p.items():
    s = s.replace('$(params.' + k + ')', v)
s = s.replace('$(workspaces.sortie.path)', ws).replace('$(results.BOOTSTRAP_ARTIFACT_INPUTS.path)', res)
assert not any(m in s for m in ('$(params.', '$(workspaces.', '$(results.', '$(context.')), 'référence de Tekton restante'
open(out, 'w', encoding='utf-8').write(s)
FIN
}
pod_spec() { # pod d'essai : runc, sans root, montages de la future tâche ; volume éphémère sous subPath comme un workspace
  jq -n --arg n "$POD" --arg i "$IMAGE" --argjson l "$LIMITES" --arg lb "$LABEL" --arg v "$VOLUME" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"tekton.dev/task": $lb}},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", ephemeral: {volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: $v}}}}}},
        {name: "tmp", emptyDir: {}}, {name: "ca-poc", configMap: {name: "ca-poc"}}],
      containers: [{name: "essai", image: $i, command: ["sleep", "7200"],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
        env: [{name: "HOME", value: "/tmp"}],
        resources: {requests: $l, limits: $l},
        volumeMounts: [{name: "w", mountPath: "/workspace/sortie", subPath: "fermeture"}, {name: "tmp", mountPath: "/tmp"},
          {name: "ca-poc", mountPath: "/etc/ca-poc", readOnly: true}]}]}}' > "$T/$POD.json"
}
dans() { # libellé : script sh sur l'entrée standard, exécuté dans le pod ; sortie dans $T/<libellé>.log, puis affichée
  local rc=0
  kubectl exec -i -n builds "$POD" -- sh -s > "$T/$1.log" 2>&1 || rc=$?
  sed 's/^/     /' "$T/$1.log"
  echo "     (code de l'exec : $rc)"
  return "$rc"
}
ARBRE=$(cat <<'SH'
set -u
cd "$SORTIE/depot" || exit 1
find . -type f -printf '%P %s\n' | sort | while read -r f s; do echo "$f $s $(sha256sum < "$f" | cut -c1-64)"; done
SH
)
neuf() { [ ! -e "$1" ] || echec "déjà présent, jamais réécrit : ${1#"$W"/}"; }
sha() { sha256sum < "$1" | cut -c1-64; }
zot_lire() { # libellé référence-sans-registre : digest si présent, « absent » sur un « not found » seul, sinon échec
  local d
  if d=$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" \
      "$REG_HOTE/$2" < /dev/null 2> "$T/oras.err" | jq -r .digest); then
    echo "$d"
  elif grep -q -i -E 'not found|MANIFEST_UNKNOWN|NAME_UNKNOWN' "$T/oras.err"; then
    echo absent
  else
    echec "$1 : NON CONCLUANT, $(head -c 160 "$T/oras.err" | tr '\n' ' ')"
  fi
}
DIFF_FEUILLES=$(cat <<'PY'
import json, sys
def feuilles(o, p=''):
    if isinstance(o, dict):
        if not o:
            yield p, '{}'
        for k in o:
            yield from feuilles(o[k], f'{p}.{k}')
    elif isinstance(o, list):
        if not o:
            yield p, '[]'
        for i, v in enumerate(o):
            yield from feuilles(v, f'{p}[{i}]')
    else:
        yield p, json.dumps(o, ensure_ascii=False)
a = dict(feuilles(json.load(open(sys.argv[1], encoding='utf-8'))))
b = dict(feuilles(json.load(open(sys.argv[2], encoding='utf-8'))))
for k in sorted(set(a) | set(b)):
    if a.get(k) != b.get(k):
        print(f'{k} : {a.get(k, "<absent>")} -> {b.get(k, "<absent>")}')
PY
)
diff_feuilles() { python3 -I -c "$DIFF_FEUILLES" "$1" "$2"; }   # json-avant json-après
# --- fin des copies ---
# --- recopié de m4b.sh ---
pr_rpm() { # nom : PipelineRun, podTemplate de pr_json (s4b.sh de la 06) : nodeSelector, tolérance, contexte de sécurité ; ni env, ni Kata
  jq -n --arg n "$1" --arg b "$PIPELINE_REF" '
    {nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}}} as $z
    | {apiVersion: "tekton.dev/v1", kind: "PipelineRun", metadata: {name: $n, namespace: "builds"},
      spec: {pipelineRef: {resolver: "bundles", params: [{name: "bundle", value: $b}, {name: "name", value: "prefetch-rpm-sample-app"},
          {name: "kind", value: "pipeline"}]},
        workspaces: [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "1Gi"}}}}}],
        taskRunTemplate: {serviceAccountName: "build", podTemplate: $z}}}' > "$T/pr-$1.json"
}
statut_pr() { # nom : « statut|raison » de la condition Succeeded (jamais le message)
  kubectl get pipelinerun -n builds "$1" -o json < /dev/null | jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "")|\(.reason // "")"'
}
attendre_pr() { # nom : attend la fin (3600 s au plus) ; « statut|raison »
  local st=""
  for _ in $(seq 1800); do
    st=$(statut_pr "$1"); case $st in True\|*|False\|*) break ;; esac; sleep 2
  done
  echo "$st"
}
releve_pod() { # pod : nœud, runtimeClassName, label ; conteneurs d'initialisation et de pas (état, code, raison) ; ressources ;
  # place-scripts : commande et longueur en octets de son dernier argument. Jamais de message ni de variable d'environnement.
  kubectl get pod -n builds "$1" -o json < /dev/null > "$T/pod-$1.json" || { echo "     pod $1 illisible"; return 0; }
  jq -r --arg a "$ARGS_RECONSTRUIT" '"     pod \(.metadata.name) : nœud \(.spec.nodeName // "-"), runtimeClassName « \(.spec.runtimeClassName // "") », tekton.dev/task \(.metadata.labels["tekton.dev/task"] // "-"), phase \(.status.phase // "-")",
    ((.status.initContainerStatuses // []) + (.status.containerStatuses // []) | .[] |
      "     conteneur \(.name) : \(.state | to_entries[0] | "\(.key) code \(.value.exitCode // "-") raison \(.value.reason // "-")")"),
    ((.spec.initContainers // []) + .spec.containers | .[] |
      "     ressources \(.name) : demandes \(.resources.requests // {} | tojson) ; limites \(.resources.limits // {} | tojson)"),
    (.spec.initContainers // [] | .[] | select(.name == "place-scripts") |
      "     place-scripts : commande \(.command | tojson), \(.args | length) argument(s), dernier argument \(.args[-1] | utf8bytelength) octets (reconstruit à sec : \($a))")' "$T/pod-$1.json"
}
# --- fin des copies de m4b.sh ---
# --- recopié de m4b.sh (comparaison, provenance) ---
arbre_de() { # dossier : « chemin taille sha256 » de chaque fichier, chemin relatif au dossier, trié sous LC_ALL=C
  (cd "$1" && find . -type f -printf '%P %s\n' | sort | while read -r f s; do echo "$f $s $(sha256sum < "$f" | cut -c1-64)"; done)
}
confronter() { # dossier arbre-de-référence (relatif à depot/) travail : tout imprimé, puis assertions ; hors ligne (banc)
  local x=$1 a=$3
  sed 's|^|depot/|' "$2" | sort > "$a/arbre-ref.txt"
  arbre_de "$x" > "$a/arbre-tire.txt"
  find "$x" ! -type f ! -type d > "$a/autres.txt"
  comm -3 "$a/arbre-tire.txt" "$a/arbre-ref.txt" > "$a/ecarts.txt"
  echo "fichiers tirés : $(wc -l < "$a/arbre-tire.txt") (référence : $(wc -l < "$a/arbre-ref.txt")) ; octets, somme des fichiers : $(awk '{s += $2} END {print s + 0}' "$a/arbre-tire.txt") ; hors de depot/ : $(grep -vc '^depot/' "$a/arbre-tire.txt" || true) ; ni fichier ni dossier : $(wc -l < "$a/autres.txt")"
  echo "écarts (comm -3 ; sans retrait : tiré seul ; avec retrait : référence seule) : $(wc -l < "$a/ecarts.txt"), 20 premiers :"
  sed -n '1,20p' "$a/ecarts.txt" | cut -c1-200 | sed 's/^/     /'
  attendu "fichiers tirés" "$(wc -l < "$a/arbre-tire.txt")" "$(wc -l < "$a/arbre-ref.txt")"
  attendu "fichiers hors de depot/" "$(grep -vc '^depot/' "$a/arbre-tire.txt" || true)" 0
  attendu "objets ni fichier ni dossier" "$(wc -l < "$a/autres.txt")" 0
  attendu "arbre tiré égal à l'arbre de final préfixé par depot/ (sha256 des listes)" \
    "$(sha256sum < "$a/arbre-tire.txt" | cut -c1-64)" "$(sha256sum < "$a/arbre-ref.txt" | cut -c1-64)"
}
lire_prov() { # provenance (un objet JSON décodé) travail : resolvedDependencies (« nom uri digest ») dans deps.txt ; paramètres des
  # pipelineTask (« tâche paramètre valeur ») dans params.txt ; valeur à saut de ligne : sha256 après retrait des lignes vides, et
  # nombre de ces lignes ; les deux listes triées ; jamais le contenu des pipelineTask en entier
  local p=$1 a=$2 t n v
  jq -r '.predicate.buildDefinition.resolvedDependencies[]
    | "\(.name // "-") \(.uri // "-") \(.digest // {} | to_entries | map(.key + ":" + .value) | join(","))"' "$p" | sort > "$a/deps.txt"
  jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
    | ((.spec.taskRef.params // []) | map(select(.name == "name")) | .[0].value // "-") as $t
    | .spec.params[]? | "\($t) \(.name) \(.value | if type == "string" then . else tojson end | @base64)"' "$p" \
    | while read -r t n v; do
        if [ "$(base64 -d <<< "$v" | wc -l)" -gt 0 ]; then
          echo "$t $n sha256:$(base64 -d <<< "$v" | sed '/^$/d' | sha256sum | cut -c1-64) ($(base64 -d <<< "$v" | sed '/^$/d' | wc -l) lignes non vides)"
        else
          echo "$t $n $(base64 -d <<< "$v")"
        fi
      done | sort > "$a/params.txt"
}
controler_prov() { # enveloppes uid sujet deps-attendues params-attendus travail : tout imprimé, puis assertions ; hors ligne (banc)
  local e=$1 u=$2 a=$6 n
  jq -c --arg u "$u" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$e" > "$a/prov.json"
  n=$(grep -c . "$a/prov.json" || true)
  : > "$a/deps.txt"; : > "$a/params.txt"
  [ "$n" != 1 ] || lire_prov "$a/prov.json" "$a"
  echo "enveloppes de l'invocation $u : $n"
  echo "sujet : $(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$a/prov.json" | paste -sd' ')"
  echo "buildType : $(jq -r '.predicate.buildDefinition.buildType' "$a/prov.json" | paste -sd' ') ; builder.id : $(jq -r '.predicate.runDetails.builder.id // "-"' "$a/prov.json" | paste -sd' ') (relevé)"
  echo "début et fin : $(jq -r '"\(.predicate.runDetails.metadata.startedOn // "-") \(.predicate.runDetails.metadata.finishedOn // "-")"' "$a/prov.json" | paste -sd' ') (relevé)"
  echo "resolvedDependencies ($(wc -l < "$a/deps.txt")) :"; sed 's/^/     /' "$a/deps.txt"
  echo "paramètres des tâches ($(wc -l < "$a/params.txt")) :"; cut -c1-200 "$a/params.txt" | sed 's/^/     /'
  sort "$4" > "$a/deps-attendues-triees.txt"; sort "$5" > "$a/params-attendus-tries.txt"   # copies triées, sous d'autres noms que les entrées
  echo "écarts (comm -3 ; sans retrait : provenance seule ; avec retrait : attendu seul) : dépendances, puis paramètres"
  comm -3 "$a/deps.txt" "$a/deps-attendues-triees.txt" | cut -c1-200 | sed 's/^/     /'
  comm -3 "$a/params.txt" "$a/params-attendus-tries.txt" | cut -c1-200 | sed 's/^/     /'
  attendu "enveloppes de l'invocation" "$n" 1
  attendu "sujet" "$(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$a/prov.json")" "$3"
  attendu "buildType" "$(jq -r '.predicate.buildDefinition.buildType' "$a/prov.json")" https://tekton.dev/chains/v2/slsa-tekton
  attendu "resolvedDependencies égales à l'attendu (sha256 des listes triées)" \
    "$(sha256sum < "$a/deps.txt" | cut -c1-64)" "$(sha256sum < "$a/deps-attendues-triees.txt" | cut -c1-64)"
  attendu "paramètres des tâches égaux à ceux de la pipeline (sha256 des listes triées)" \
    "$(sha256sum < "$a/params.txt" | cut -c1-64)" "$(sha256sum < "$a/params-attendus-tries.txt" | cut -c1-64)"
}
prov_attendue() { # source dossier travail : deps-attendues.txt et params-attendus.txt, tirés des références épinglées de ce fichier
  printf '%s\n' "pipeline ${PIPELINE_REF%@*} ${PIPELINE_REF#*@}" "pipelineTask ${PREFETCH_REF%@*} ${PREFETCH_REF#*@}" \
    "pipelineTask ${PUBLIER_REF%@*} ${PUBLIER_REF#*@}" "- oci://${IMAGE%@*} ${IMAGE#*@}" "- oci://${HORODATAGE%@*} ${HORODATAGE#*@}" \
    "inputs/result oci://${1%@*} ${1#*@}" > "$3/deps-attendues.txt"
  printf '%s\n' "prefetch-rpm dossier $2" "prefetch-rpm empreinte $FP_ROCKY" \
    "prefetch-rpm liste sha256:$LISTE_SHA ($(sed '/^$/d' "$LISTE" | wc -l) lignes non vides)" "prefetch-rpm repomd $REPOMD_V2" \
    "prefetch-rpm source $1" "publier-fermeture depot $DEPOT_FERMETURE" > "$3/params-attendus.txt"
}
# --- fin des copies de m4b.sh (comparaison, provenance) ---

source_dossier() { # verrou : « source dossier » du bootstrap, comme m4b.sh (config.py:844-846)
  local src
  src=$(jq -r '.config.bootstrap_image' "$1"); echo "$src ${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$1")"
}
sources() { # sha256 des gabarits, des tâches signées, du calcul et des entrées
  local e
  for e in $GABARITS_SHA; do attendu "${e%%:*} (sha256)" "$(sha "$h05/${e%%:*}")" "${e#*:}"; done
  attendu "liste des rpm (sha256)" "$(sha "$LISTE")" "$LISTE_SHA"
  attendu "verrou de la cascade (sha256)" "$(sha "$VERROU_SRC")" "$VERROU_SHA"
  attendu "verrou de M4b (sha256)" "$(sha "$VERROU_M4B")" "$VERROU_M4B_SHA"
  attendu "arbre de final (sha256)" "$(sha "$ARBRE_REF")" "$ARBRE_REF_SHA"
}
lire_manifeste() { # libellé référence-sans-registre sortie : octets du manifeste, lecture anonyme ; sha256 contrôlé par l'appelant
  oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" --output "$3" "$REG_HOTE/$2" < /dev/null 2> "$T/oras.err" \
    || echec "$1 : manifeste illisible, $(head -c 160 "$T/oras.err" | tr '\n' ' ')"
}
lire_bundle() { # référence-sans-registre sortie : objet d'un bundle Tekton (une couche, tar gzip d'un seul fichier), lecture anonyme
  local x=$T/bundle.json c
  lire_manifeste "bundle ${1%@*}" "$1" "$x"
  attendu "bundle ${1##*/} : manifeste relu (sha256)" "sha256:$(sha "$x")" "${1##*@}"
  attendu "bundle : une couche, pipeline prefetch-rpm-sample-app" \
    "$(jq -r '[(.layers | length), .layers[0].annotations["dev.tekton.image.kind"], .layers[0].annotations["dev.tekton.image.name"]] | join(" ")' "$x")" \
    "1 pipeline prefetch-rpm-sample-app"
  c=$(jq -r '.layers[0].digest' "$x")
  oras blob fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" --output "$T/couche.tgz" "$REG_HOTE/${1%@*}@$c" < /dev/null
  attendu "bundle : couche relue (sha256)" "sha256:$(sha "$T/couche.tgz")" "$c"
  attendu "bundle : un seul fichier dans la couche" "$(tar -tzf "$T/couche.tgz" | wc -l)" 1
  tar -xzOf "$T/couche.tgz" > "$2"
}
FEUILLES_ATTENDUES=".spec.tasks[0].params[1].value
.spec.tasks[0].params[2].value
.spec.tasks[0].taskRef.params[0].value"   # source, dossier, bundle de prefetch-rpm (calcul à sec du 20/11)

etape_local() { # hôte, plus des lectures anonymes de Zot ; rien n'est écrit dans Zot ni dans le cluster
  local x=$T/local src dos s0 d0 f
  sources
  neuf "$x"; mkdir "$x"
  echo '{}' > "$T/vide.json"
  echo "## témoin de méthode : pipeline signée de M4b, relue dans son bundle, contre le gabarit rendu avec les entrées de M4b"
  lire_bundle "$PIPELINE_M4B" "$x/bundle-m4b.json"
  read -r s0 d0 < <(source_dossier "$VERROU_M4B")
  (T=$x; IMAGE=$IMAGE_ESSAI; rendre_taches "$PREFETCH_M4B" "$PUBLIER_REF" "$s0" "$d0")
  mv "$x/prefetch-rpm-sample-app.yaml" "$x/pipeline-m4b.yaml"
  normaliser "$x/bundle-m4b.json" > "$x/bundle-m4b.n.json"
  normaliser "$x/pipeline-m4b.yaml" > "$x/pipeline-m4b.n.json"
  attendu "témoin : pipeline rendue avec les entrées de M4b, égale à son bundle (normalisées)" \
    "$(cmp -s "$x/bundle-m4b.n.json" "$x/pipeline-m4b.n.json" && echo égale || echo différente)" égale
  substituer "$TACHES/prefetch-rpm.signee.yaml" "$x/bundle-m4b.json" /workspace/sortie /tmp/resultat-bootstrap.json "$x/script-m4b.sh"
  attendu "témoin : script de la tâche de M4b substitué avec son bundle (sha256)" "$(sha "$x/script-m4b.sh")" "$SCRIPT_M4B_SHA"
  echo "## rendu neuf : prefetch-rpm de la cascade, bootstrap de M1b"
  read -r src dos < <(source_dossier "$VERROU_SRC")
  echo "source $src ; dossier $dos"
  (T=$x; rendre_taches "$PREFETCH_REF" "$PUBLIER_REF" "$src" "$dos")
  mv "$x/prefetch-rpm-sample-app.yaml" "$x/pipeline-neuve.yaml"
  normaliser "$x/pipeline-neuve.yaml" > "$x/pipeline-neuve.n.json"
  diff_feuilles "$x/bundle-m4b.n.json" "$x/pipeline-neuve.n.json" > "$x/feuilles.txt"
  cut -c1-240 "$x/feuilles.txt" | sed 's/^/     /'
  attendu "feuilles différentes de la pipeline de M4b" "$(cut -d' ' -f1 "$x/feuilles.txt" | paste -sd' ')" "$(paste -sd' ' <<< "$FEUILLES_ATTENDUES")"
  attendu "nouvelles valeurs : source, dossier, prefetch-rpm de la cascade" \
    "$(sed 's/.* -> //' "$x/feuilles.txt" | tr -d '"' | paste -sd' ')" "$src $dos $PREFETCH_REF"
  substituer "$SIGNEE" "$x/pipeline-neuve.yaml" /workspace/sortie /tmp/resultat-bootstrap.json "$x/script-neuf.sh"
  attendu "script neuf : tâche signée de la cascade substituée avec la pipeline neuve (sha256)" "$(sha "$x/script-neuf.sh")" "$SCRIPT_NEUF_SHA"
  attendu "script neuf contre celui de M4b : lignes différentes (SOURCE et DOSSIER)" \
    "$(diff "$x/script-m4b.sh" "$x/script-neuf.sh" | grep '^[<>]' | cut -d= -f1 | paste -sd' ')" "< SOURCE < DOSSIER > SOURCE > DOSSIER"
  attendu "script neuf, sh -n (sh du pas de Tekton)" "$(sh -n "$x/script-neuf.sh" && echo ok)" ok
  echo "## liste revue"
  attendu "prefetch-rpm de la cascade, lue dans la liste revue" "$(ref_revue prefetch-rpm b9bbeba3)" "$PREFETCH_REF"
  attendu "publier-fermeture, lue dans la liste revue" "$(ref_revue publier-fermeture 7fa92ad3)" "$PUBLIER_REF"
  echo "## bootstrap neuf, arbre et digest prédits (resultats/m1b-fermeture-digest.py)"
  lire_manifeste "bootstrap neuf" "${src#"$REG"/}" "$x/manifeste-bootstrap.json"
  attendu "manifeste du bootstrap neuf (sha256) = pull_digest du verrou" "sha256:$(sha "$x/manifeste-bootstrap.json")" "$(jq -r .bootstrap.pull_digest "$VERROU_SRC")"
  attendu "configuration du bootstrap neuf = bootstrap.id du verrou" "$(jq -r .config.digest "$x/manifeste-bootstrap.json")" "sha256:$(jq -r .bootstrap.id "$VERROU_SRC")"
  lire_manifeste "bootstrap de M4b" "$BOOT_M4B" "$x/manifeste-bootstrap-m4b.json"
  attendu "manifeste du bootstrap de M4b (sha256) = pull_digest du verrou de M4b" "sha256:$(sha "$x/manifeste-bootstrap-m4b.json")" "$(jq -r .bootstrap.pull_digest "$VERROU_M4B")"
  lire_manifeste "fermeture de M4b" "${DEPOT_FERMETURE#"$REG"/}@$FERMETURE_M4B" "$x/manifeste-m4b.json"
  python3 -I "$R/m1b-fermeture-digest.py" "$ARBRE_REF" "$x/manifeste-m4b.json" "$FERMETURE_M4B" "$x/manifeste-bootstrap-m4b.json" \
    "$(jq -r .bootstrap.pull_digest "$VERROU_M4B")" "$x/arbre-temoin.txt" > "$x/digest-temoin.log"
  sed 's/^/     témoin : /' "$x/digest-temoin.log"
  attendu "témoin du calcul : arbre prédit avec le bootstrap de M4b, égal à celui de final" \
    "$(cmp -s "$x/arbre-temoin.txt" "$ARBRE_REF" && echo égal || echo différent)" égal
  attendu "témoin du calcul : digest prédit avec le bootstrap de M4b" "$(sed -n 's/^digest prédit : //p' "$x/digest-temoin.log")" "$FERMETURE_M4B"
  python3 -I "$R/m1b-fermeture-digest.py" "$ARBRE_REF" "$x/manifeste-m4b.json" "$FERMETURE_M4B" "$x/manifeste-bootstrap.json" \
    "$(jq -r .bootstrap.pull_digest "$VERROU_SRC")" "$x/arbre-predit.txt" > "$x/digest-predit.log"
  sed 's/^/     /' "$x/digest-predit.log"
  attendu "arbre prédit (sha256)" "$(sha "$x/arbre-predit.txt")" "$ARBRE_PREDIT_SHA"
  attendu "digest prédit" "$(sed -n 's/^digest prédit : //p' "$x/digest-predit.log")" "$DIGEST_PREDIT"
  f=$(grep -c -v -F "$dos/" "$x/arbre-predit.txt" || true)
  attendu "arbre prédit : lignes hors du dossier du bootstrap, égales à celles de final" \
    "$(cmp -s <(grep -v -F "$dos/" "$x/arbre-predit.txt") <(grep -v -F "$d0/" "$ARBRE_REF") && echo "égales ($f)" || echo différentes)" "égales (226)"
  echo "## gardes de Zot (lecture anonyme)"
  attendu "tag $TAG de la pipeline, absent" "$(zot_lire "tag $TAG" "tekton/pipelines/prefetch-rpm-sample-app:$TAG")" absent
  attendu "tag m4b de la pipeline, sur celle de M4b" "$(zot_lire "tag m4b" tekton/pipelines/prefetch-rpm-sample-app:m4b)" "${PIPELINE_M4B##*@}"
  attendu "tag m1b de prefetch-rpm (bundles de la cascade), sur celle de la cascade" "$(zot_lire "tag m1b" tekton/tasks/prefetch-rpm:m1b)" "${PREFETCH_REF##*@}"
  attendu "fermeture de M4b présente" "$(zot_lire "fermeture de M4b" "${DEPOT_FERMETURE#"$REG"/}@$FERMETURE_M4B")" "$FERMETURE_M4B"
  attendu "fermeture prédite absente" "$(zot_lire "fermeture prédite" "${DEPOT_FERMETURE#"$REG"/}@$DIGEST_PREDIT")" absent
  echo "/ de sc-stockage : $(libre_zot) octets libres à $(date -u +%H:%M:%S) ; fichiers de la fermeture prédite : $(awk '{s += $2} END {print s}' "$x/arbre-predit.txt") octets"
}

etape_essai() { # pod d'essai : le script substitué de la tâche, tel qu'il sera signé ; puis le cas refusé (repomd.xml faux)
  sources
  local src dos rc POD=$N-fermeture-prefetch faux=0000000000000000000000000000000000000000000000000000000000000000 a=$R/$N-fermeture-essai-arbre.txt
  neuf "$a"
  [ -s "$T/local/arbre-predit.txt" ] || echec "arbre prédit absent : étape local d'abord"
  attendu "arbre prédit de local (sha256)" "$(sha "$T/local/arbre-predit.txt")" "$ARBRE_PREDIT_SHA"
  read -r src dos < <(source_dossier "$VERROU_SRC")
  rendre_taches "$REG/tekton/tasks/prefetch-rpm@$FACTICE" "$REG/tekton/tasks/publier-fermeture@$FACTICE" "$src" "$dos"
  substituer "$SIGNEE" "$T/prefetch-rpm-sample-app.yaml" /workspace/sortie /tmp/resultat-bootstrap.json "$T/script-essai.sh"
  substituer "$SIGNEE" "$T/prefetch-rpm-sample-app.yaml" /workspace/sortie/refus /tmp/resultat-refus.json "$T/script-refus.sh" "$faux"
  attendu "scripts : nominal et refusé, seuls écarts le workspace, le résultat et repomd" \
    "$(diff "$T/script-essai.sh" "$T/script-refus.sh" | grep -c '^>')" 3
  attendu "script substitué, égal au script neuf de local (sha256)" "$(sha256sum < "$T/script-essai.sh" | cut -c1-64)" "$SCRIPT_NEUF_SHA"
  pod_spec
  if kubectl create --dry-run=server -f "$T/$POD.json" < /dev/null > "$T/admis-$POD.out" 2>&1; then echo "OK   $POD admis en dry-run serveur"
  else echo "KO   $POD refusé à l'admission : $(head -c 300 "$T/admis-$POD.out" | tr '\n' ' ')" >&2; exit 1; fi
  kubectl delete pod -n builds "$POD" --ignore-not-found --wait=true < /dev/null > /dev/null
  kubectl create -f "$T/$POD.json" < /dev/null > /dev/null
  if ! kubectl wait -n builds "pod/$POD" --for=condition=Ready --timeout=300s < /dev/null > /dev/null; then
    kubectl get pod -n builds "$POD" -o json < /dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state
      | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"' >&2   # raisons, jamais les messages
    echo "KO   $POD non prêt" >&2; exit 1
  fi
  echo "### $POD (runc, uid 65532, label tekton.dev/task=$LABEL) : prêt sur $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.nodeName}' < /dev/null), runtimeClassName « $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.runtimeClassName}' < /dev/null) »"
  echo "## script de la tâche, nominal"
  rc=0; { printf 't0=$(date +%%s)\n'; cat "$T/script-essai.sh"; printf 'echo "durée du pas : $(($(date +%%s) - t0)) s"\n'; } | dans prefetch-essai || rc=$?
  [ "$rc" = 0 ] || { echo "KO   script de la tâche en échec ; pod laissé pour lecture : $POD" >&2; exit 1; }
  attendu "repomd.xml V2" "$(grep -m 1 '^repodata V2 : repomd.xml ' "$T/prefetch-essai.log" | cut -d' ' -f5)" "$REPOMD_V2"
  attendu "résultat BOOTSTRAP_ARTIFACT_INPUTS" "$(kubectl exec -n builds "$POD" -- cat /tmp/resultat-bootstrap.json < /dev/null)" \
    "{\"uri\":\"oci://${src%@*}\",\"digest\":\"${src##*@}\"}"
  rc=0; printf 'export SORTIE=/workspace/sortie\n%s\n' "$ARBRE" | kubectl exec -i -n builds "$POD" -- sh -s > "$T/prefetch-essai-arbre.txt" 2> "$T/prefetch-essai-arbre.err" || rc=$?
  attendu "arbre relevé (code de l'exec)" "$rc" 0
  cp "$T/prefetch-essai-arbre.txt" "$a"
  echo "arbre archivé : resultats/${a##*/} ($(wc -l < "$a") fichiers, sha256 $(sha "$a"))"
  attendu "arbre égal à l'arbre prédit" "$([ "$(sha256sum < "$T/prefetch-essai-arbre.txt")" = "$(sha256sum < "$T/local/arbre-predit.txt")" ] && echo égal || echo différent)" égal
  echo "## même script, repomd.xml attendu faux, workspace neuf (refus attendu avant la copie de l'image)"
  rc=0; dans prefetch-essai-refus < "$T/script-refus.sh" || rc=$?
  attendu "cas refusé : code" "$rc" 1
  attendu "cas refusé : message" "$(grep -c '^KO   repomd.xml différent de l.attendu (fixé par la pipeline)$' "$T/prefetch-essai-refus.log")" 1
  attendu "cas refusé : ni dossier dir:, ni résultat" \
    "$(kubectl exec -n builds "$POD" -- sh -c "ls -A /workspace/sortie/refus/depot | grep -c -F '$dos' ; ls /tmp/resultat-refus.json 2>/dev/null | wc -l" < /dev/null | paste -sd' ')" "0 0"
  rc=0; kubectl delete pod -n builds "$POD" --wait=true --timeout=180s < /dev/null > /dev/null || rc=$?
  attendu "retrait du pod (code de kubectl)" "$rc" 0
  rc=0; kubectl wait -n builds --for=delete "pvc/$POD-w" --timeout=180s < /dev/null > /dev/null 2>&1 || rc=$?   # PVC du volume éphémère
  attendu "PVC $POD-w retirée (code de kubectl wait)" "$rc" 0
  rc=0; kubectl get pods,pvc -n builds -o name < /dev/null > "$T/prefetch-essai-objets.txt" 2>&1 || rc=$?
  attendu "objets de builds relus (code de kubectl)" "$rc" 0
  attendu "pods et PVC restants au nom de $POD" "$(grep -c -F "$POD" "$T/prefetch-essai-objets.txt" || true)" 0
}

etape_pipeline() { # SIGNER=1 seulement : pipeline signée, relue, versionnée sous un nom neuf, bundle au tag neuf
  [ -n "${SIGNER:-}" ] || echec "étape pipeline : SIGNER=1 seulement, sur accord nommé du propriétaire"
  [ -s "$S/taches.key" ] || echec "clé des tâches absente"
  local x=$T/pipeline v=$TACHES/prefetch-rpm-sample-app.$TAG.signee.yaml src dos p libre
  neuf "$v"
  sources
  attendu "arbre de l'essai archivé (sha256), égal à l'arbre prédit" "$(sha "$ARBRE_ESSAI")" "$ARBRE_PREDIT_SHA"
  neuf "$x"; mkdir "$x"
  echo '{}' > "$T/vide.json"
  echo "## gardes avant toute écriture (lecture anonyme)"
  attendu "tag $TAG de la pipeline, absent" "$(zot_lire "tag $TAG" "tekton/pipelines/prefetch-rpm-sample-app:$TAG")" absent
  attendu "tag m4b de la pipeline, sur celle de M4b" "$(zot_lire "tag m4b" tekton/pipelines/prefetch-rpm-sample-app:m4b)" "${PIPELINE_M4B##*@}"
  attendu "prefetch-rpm de la cascade, lue dans la liste revue" "$(ref_revue prefetch-rpm b9bbeba3)" "$PREFETCH_REF"
  attendu "publier-fermeture, lue dans la liste revue" "$(ref_revue publier-fermeture 7fa92ad3)" "$PUBLIER_REF"
  libre=$(libre_zot)
  case $libre in ''|*[!0-9]*) echec "place libre illisible : $libre" ;; esac
  [ "$libre" -ge "$LIBRE_MIN" ] || echec "place libre sur / de sc-stockage : $libre octets, sous $LIBRE_MIN"
  echo "OK   octets libres sur / de sc-stockage (porte /var/lib/zot) : $libre (seuil $LIBRE_MIN)"
  echo "## pipeline rendue (références de la liste revue, bootstrap de M1b) ; admission en dry-run serveur, rien n'est créé"
  read -r src dos < <(source_dossier "$VERROU_SRC")
  (T=$x; rendre_taches "$PREFETCH_REF" "$PUBLIER_REF" "$src" "$dos")
  attendu "pipeline rendue admise (code de kubectl)" "$(admission "$x/prefetch-rpm-sample-app.yaml")" 0
  lire_bundle "$PIPELINE_M4B" "$x/bundle-m4b.json"
  normaliser "$x/bundle-m4b.json" > "$x/bundle-m4b.n.json"
  normaliser "$x/prefetch-rpm-sample-app.yaml" > "$x/rendue.n.json"
  diff_feuilles "$x/bundle-m4b.n.json" "$x/rendue.n.json" > "$x/feuilles.txt"
  attendu "rendue : feuilles différentes de la pipeline de M4b" "$(cut -d' ' -f1 "$x/feuilles.txt" | paste -sd' ')" "$(paste -sd' ' <<< "$FEUILLES_ATTENDUES")"
  substituer "$SIGNEE" "$x/prefetch-rpm-sample-app.yaml" /workspace/sortie /tmp/resultat-bootstrap.json "$x/script.sh"
  attendu "script de la tâche substitué avec la pipeline rendue, celui de l'essai (sha256)" "$(sha "$x/script.sh")" "$SCRIPT_NEUF_SHA"
  echo "## signature (tkn $(tkn version --component client)), relue avant tout versionnement et toute poussée"
  tkn pipeline sign "$x/prefetch-rpm-sample-app.yaml" -K "$S/taches.key" -f "$x/signee.yaml" > /dev/null
  attendu "pipeline signée : annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$x/signee.yaml")" true
  normaliser "$x/signee.yaml" > "$x/signee.n.json"
  attendu "pipeline signée : égale à la rendue, signature exceptée (normalisées)" \
    "$(cmp -s "$x/signee.n.json" "$x/rendue.n.json" && echo égale || echo différente)" égale
  cp "$x/signee.yaml" "$v"
  echo "signature versionnée : fermeture/${v##*/} (sha256 $(sha "$v"))"
  (umask 077 && mkdir -p "$T/auth")
  trap 'find "$T/auth" -depth -delete 2> /dev/null || true' EXIT   # copie du secret de Zot, retirée même en cas d'échec (sans rm)
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundle (commun.sh), compte poc-ecriture
  echo "## bundle, tag $TAG (écriture définitive)"
  p=$REG/tekton/pipelines/prefetch-rpm-sample-app@$(bundle "$v" tekton/pipelines/prefetch-rpm-sample-app "$TAG")
  find "$T/auth" -depth -delete
  echo "$p" | tee "$x/pipeline.ref"
  echo "## relecture anonyme après"
  attendu "tag $TAG de la pipeline, sur le bundle poussé" "$(zot_lire "tag $TAG" "tekton/pipelines/prefetch-rpm-sample-app:$TAG")" "${p##*@}"
  lire_bundle "${p#"$REG"/}" "$x/bundle-neuf.json"
  normaliser "$x/bundle-neuf.json" > "$x/bundle-neuf.n.json"
  attendu "bundle relu : égal à la pipeline signée (normalisés)" \
    "$(cmp -s "$x/bundle-neuf.n.json" "$x/signee.n.json" && echo égal || echo différent)" égal
  attendu "bundle relu : signature égale à celle de la version" \
    "$(yq -o=yaml '.metadata.annotations["tekton.dev/signature"]' "$x/bundle-neuf.json")" "$(yq -o=yaml '.metadata.annotations["tekton.dev/signature"]' "$v")"   # le bundle est du JSON : sortie YAML forcée des deux côtés
  attendu "tag m4b de la pipeline, inchangé" "$(zot_lire "tag m4b" tekton/pipelines/prefetch-rpm-sample-app:m4b)" "${PIPELINE_M4B##*@}"
  echo "octets libres sur / de sc-stockage après : $(libre_zot)"
  echo "PIPELINE_REF à épingler (correction datée, banc rejoué) avant l'étape rpm : $p"
}

etape_rpm() {
  sources
  local i pr r t p d u l src c n
  [ -n "$PIPELINE_REF" ] || echec "PIPELINE_REF non épinglée : étape pipeline d'abord, puis correction datée et banc rejoué"
  attendu "arbre de l'essai archivé (sha256), égal à l'arbre prédit" "$(sha "$ARBRE_ESSAI")" "$ARBRE_PREDIT_SHA"
  n=$(wc -l < "$ARBRE_ESSAI")
  echo '{}' > "$T/vide.json"
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC")
  echo "## gardes, avant toute création"
  attendu "pipeline relue dans Zot au tag $TAG (lecture anonyme)" \
    "$REG/tekton/pipelines/prefetch-rpm-sample-app@$(zot_lire "tag $TAG" "tekton/pipelines/prefetch-rpm-sample-app:$TAG")" "$PIPELINE_REF"
  attendu "tag m4b de la pipeline, inchangé" "$(zot_lire "tag m4b" tekton/pipelines/prefetch-rpm-sample-app:m4b)" "${PIPELINE_M4B##*@}"
  if listee "$PREFETCH_REF"; then echo "OK   prefetch-rpm dans la liste revue : $PREFETCH_REF"; else echec "prefetch-rpm absente de la liste revue"; fi
  for i in 1 2; do
    pr=$N-rpm-$i
    echo "## $pr"
    attendu "fermeture de M4b présente dans le même dépôt (« Même dépôt, par digest »)" \
      "$(zot_lire "fermeture de M4b" "${DEPOT_FERMETURE#"$REG"/}@$FERMETURE_M4B")" "$FERMETURE_M4B"
    if [ "$i" = 1 ]; then
      attendu "fermeture prédite absente avant le premier PipelineRun" \
        "$(zot_lire "fermeture prédite" "${DEPOT_FERMETURE#"$REG"/}@$DIGEST_PREDIT")" absent
    fi
    r=0; kubectl get pipelinerun -n builds "$pr" -o name < /dev/null > /dev/null 2>&1 || r=$?
    [ "$r" != 0 ] || echec "$pr existe déjà : rien n'est purgé, décision avant toute relance"
    l=$(libre_zot)
    echo "/ de sc-stockage : $l octets libres à $(date -u +%H:%M:%S) (garde : $LIBRE_MIN)"
    echo "/ de sc-build (emptyDir du layout de publier) : $(sur sc-build 'df -B1 --output=avail / | tail -n 1' < /dev/null | tr -d ' ') octets libres (relevé)"
    if ! [[ $l =~ ^[0-9]+$ ]] || [ "$l" -lt "$LIBRE_MIN" ]; then echec "espace libre illisible ou sous la garde sur sc-stockage"; fi
    pr_rpm "$pr"
    attendu "$pr admis en dry-run serveur (ni résolveur, ni signatures, ni pods) : code de kubectl" "$(admission "$T/pr-$pr.json")" 0
    kubectl create -f "$T/pr-$pr.json" < /dev/null > /dev/null
    echo "$pr créé à $(date -u +%H:%M:%S) ($PIPELINE_REF)"
    r=$(attendre_pr "$pr")
    echo "$pr : condition Succeeded « $r », relevée à $(date -u +%H:%M:%S)"
    kubectl get pipelinerun -n builds "$pr" -o json < /dev/null \
      | jq -r '"début \(.status.startTime // "-") ; fin \(.status.completionTime // "-")"' | sed 's/^/     /'
    for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
      kubectl get taskrun -n builds "$t" -o json < /dev/null > "$T/tr-$t.json"
      p=$(jq -r '.status.podName // ""' "$T/tr-$t.json")
      echo "### TaskRun $t : $(jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "-")|\(.reason // "-")"' "$T/tr-$t.json") ; début $(jq -r '.status.startTime // "-"' "$T/tr-$t.json") ; fin $(jq -r '.status.completionTime // "-"' "$T/tr-$t.json")"
      jq -r '.status.results[]? | "     résultat \(.name) : \(.value | if type == "string" then . else tojson end)"' "$T/tr-$t.json"
      [ -n "$p" ] || { echo "     aucun pod"; continue; }
      releve_pod "$p"
      for c in $(jq -r '.spec.containers[].name' "$T/pod-$p.json"); do
        kubectl logs -n builds "$p" -c "$c" < /dev/null > "$T/$t-$c.log" 2>&1 || true
        echo "     journal de $c : $(wc -l < "$T/$t-$c.log") lignes, dont $(grep -c '^repomd.xml V2 : ' "$T/$t-$c.log" || true) de repomd.xml imprimé (non répétées)"
        grep -v '^repomd.xml V2 : \|^\s*$' "$T/$t-$c.log" | cut -c1-240 | sed 's/^/       /'
      done
    done
    jq -r '.status.results[]? | "résultat de \(.name) : \(.value)"' <(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null)
    attendu "PipelineRun $pr" "$r" "True|Succeeded"
    attendu "prefetch : rpm -K" "$(grep -c '^rpm -K : rc 0, 222 OK sur 222$' "$T/$pr-prefetch-step-prefetch.log" || true)" 1
    attendu "prefetch : repomd.xml V2" "$(grep -m 1 '^repodata V2 : repomd.xml ' "$T/$pr-prefetch-step-prefetch.log" | cut -d' ' -f5)" "$REPOMD_V2"
    attendu "prefetch : résultat BOOTSTRAP_ARTIFACT_INPUTS (clés triées)" \
      "$(jq -cS '.status.results[] | select(.name == "BOOTSTRAP_ARTIFACT_INPUTS") | .value' "$T/tr-$pr-prefetch.json")" \
      "$(jq -cnS --arg s "$src" '{uri: ("oci://" + ($s | sub("@.*$"; ""))), digest: ($s | sub("^.*@"; ""))}')"
    u=$(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null | jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value')
    d=$(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
    echo "$d" > "$T/rpm-$i.digest"
    echo "digest relevé $d ; prédit à sec $DIGEST_PREDIT : $([ "$d" = "$DIGEST_PREDIT" ] && echo égaux || echo différents) (relevé, non exigé)"
    attendu "dépôt publié" "$u" "$DEPOT_FERMETURE"
    attendu "publier : $n couches dans le journal" "$(grep -c "^publiée : $DEPOT_FERMETURE@$d ($n couches, relue en lecture anonyme)" "$T/$pr-publier-step-publier.log" || true)" 1
    attendu "manifeste relu dans Zot (lecture anonyme) : couches" \
      "$(oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$d" < /dev/null | jq '.layers | length')" "$n"
    attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
    echo "/ de sc-stockage : $(libre_zot) octets libres à $(date -u +%H:%M:%S)"
  done
  attendu "deux exécutions, même fermeture" "$(cat "$T/rpm-2.digest")" "$(cat "$T/rpm-1.digest")"
  attendu "fermeture de M4b toujours présente après" "$(zot_lire "fermeture de M4b" "${DEPOT_FERMETURE#"$REG"/}@$FERMETURE_M4B")" "$FERMETURE_M4B"
  echo "fermeture neuve : $DEPOT_FERMETURE@$(cat "$T/rpm-1.digest") ; prédite à sec : $DIGEST_PREDIT"
}

etape_comparaison() { # lecture seule : fermeture tirée par digest (lecture anonyme) dans un dossier neuf, confrontée à l'arbre de final
  local c=$T/comparaison i d src b t f
  [ -n "$FERMETURE_NEUVE" ] || echec "FERMETURE_NEUVE non épinglée : étape rpm d'abord, puis correction datée"
  echo '{}' > "$T/vide.json"
  echo "## gardes"
  attendu "arbre de l'essai (sha256), égal à l'arbre prédit" "$(sha "$ARBRE_ESSAI")" "$ARBRE_PREDIT_SHA"
  attendu "arbre de l'essai : fichiers" "$(wc -l < "$ARBRE_ESSAI")" 230
  attendu "liste des rpm (sha256)" "$(sha256sum < "$LISTE" | cut -c1-64)" "$LISTE_SHA"
  attendu "verrou (sha256)" "$(sha256sum < "$VERROU_SRC" | cut -c1-64)" "$VERROU_SHA"
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC")
  echo "## IMAGE_DIGEST relu sur les deux PipelineRuns (relevé ; le tirage prend le digest épinglé)"
  for i in 1 2; do
    d=$(kubectl get pipelinerun -n builds "$N-rpm-$i" -o json < /dev/null | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
    attendu "IMAGE_DIGEST de $N-rpm-$i" "$d" "$FERMETURE_NEUVE"
  done
  neuf "$c"; mkdir -p "$c/tiree"
  echo "## manifeste (relevé : redit l'égalité des digests mesurée à rpm)"
  oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$FERMETURE_NEUVE" < /dev/null > "$c/manifeste.json"
  attendu "manifeste : sha256 des octets lus" "sha256:$(sha256sum < "$c/manifeste.json" | cut -c1-64)" "$FERMETURE_NEUVE"
  echo "artifactType $(jq -r '.artifactType // "-"' "$c/manifeste.json") ; couches par type : $(jq -r '[.layers[].mediaType] | group_by(.) | map("\(.[0]) x\(length)") | join(", ")' "$c/manifeste.json")"
  jq -r '.layers[] | "\(.annotations["org.opencontainers.image.title"] // "-") \(.size) \(.digest | sub("^sha256:"; ""))"' "$c/manifeste.json" | sort > "$c/manifeste-arbre.txt"
  echo "couches : $(wc -l < "$c/manifeste-arbre.txt"), sans titre : $(grep -c '^- ' "$c/manifeste-arbre.txt" || true) ; égales à l'arbre de final préfixé : $(
    [ "$(sha256sum < "$c/manifeste-arbre.txt")" = "$(sed 's|^|depot/|' "$ARBRE_ESSAI" | sort | sha256sum)" ] && echo oui || echo non) (relevé, non exigé)"
  echo "## tirage par digest, lecture anonyme, dossier neuf"
  t=$(date +%s)
  oras pull --no-tty --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" -o "$c/tiree" "${DEPOT_FERMETURE/$REG/$REG_HOTE}@$FERMETURE_NEUVE" < /dev/null > "$c/pull.out" 2>&1 \
    || { sed -n '1,5p' "$c/pull.out" >&2; echec "oras pull de la fermeture"; }
  echo "tirée en $(($(date +%s) - t)) s ; du -sb : $(du -sb "$c/tiree" | cut -f1) octets (dossiers compris, relevé)"
  echo "## confrontation à l'arbre de l'essai (libellés de confronter : « final » y désigne cet arbre)"
  confronter "$c/tiree" "$ARBRE_ESSAI" "$c"
  echo "## au-delà de l'arbre de final"
  awk '{n = $1; sub(/.*\//, "", n); print "depot/" n, $3, $2}' "$LISTE" | sort > "$c/liste-rpm.txt"
  grep -E '^depot/[^/]+\.rpm ' "$c/arbre-tire.txt" > "$c/tire-rpm.txt" || true
  attendu "rpm tirés au premier niveau de depot/" "$(wc -l < "$c/tire-rpm.txt")" 222
  attendu "rpm égaux à la liste (nom, taille, sha256)" "$(sha256sum < "$c/tire-rpm.txt" | cut -c1-64)" "$(sha256sum < "$c/liste-rpm.txt" | cut -c1-64)"
  attendu "repomd.xml" "$(sha256sum < "$c/tiree/depot/repodata/repomd.xml" | cut -c1-64)" "$REPOMD_V2"
  b=$(find "$c/tiree/depot" -mindepth 1 -maxdepth 1 -type d -name "*@${src#*@}")
  attendu "dossier de l'image de bootstrap (${src#*@})" "$(grep -c . <<< "$b" || true)" 1
  attendu "image de bootstrap : manifest.json" "sha256:$(sha256sum < "$b/manifest.json" | cut -c1-64)" "${src#*@}"
  for f in "$b"/*; do
    case ${f##*/} in manifest.json|version) continue ;; esac
    attendu "image de bootstrap : blob ${f##*/} nommé par son sha256" "$(sha256sum < "$f" | cut -c1-64)" "${f##*/}"
  done
  echo "dossier tiré laissé : $c/tiree ($(du -sb "$c/tiree" | cut -f1) octets)"
}

etape_provenance() { # lecture seule : attestations du sujet vérifiées par cosign (clé de Chains), une par PipelineRun de rpm ; refus
  local c=$T/provenance i pr uid src dos s r
  [ -n "$FERMETURE_NEUVE" ] || echec "FERMETURE_NEUVE non épinglée : étape rpm d'abord, puis correction datée"
  echo "## gardes"
  attendu "clé publique de Chains (sha256)" "$(sha256sum < "$CLE_CHAINS" | cut -c1-64)" "$CLE_CHAINS_SHA"
  attendu "liste des rpm (sha256)" "$(sha256sum < "$LISTE" | cut -c1-64)" "$LISTE_SHA"
  attendu "verrou (sha256)" "$(sha256sum < "$VERROU_SRC" | cut -c1-64)" "$VERROU_SHA"
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$VERROU_SRC")   # comme etape_taches
  s=$DEPOT_FERMETURE@$FERMETURE_NEUVE
  neuf "$c"; mkdir -p "$c"
  prov_attendue "$src" "$dos" "$c"
  echo "attendu : $(wc -l < "$c/deps-attendues.txt") dépendances, $(wc -l < "$c/params-attendus.txt") paramètres ; sujet $s"
  echo "## cosign verify-attestation (clé de Chains, sans journal de transparence), lecture anonyme"
  cosign verify-attestation --key "$CLE_CHAINS" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" \
    "${s/$REG/$REG_HOTE}" < /dev/null > "$c/enveloppes.json" 2> "$c/cosign.err" || { sed -n '1,5p' "$c/cosign.err" >&2; echec "cosign verify-attestation"; }
  echo "OK   cosign verify-attestation : $(grep -c . "$c/enveloppes.json") enveloppe(s) valide(s) sur $FERMETURE_NEUVE"
  for pr in $N-rpm-1 $N-rpm-2; do
    kubectl get pipelinerun -n builds "$pr" -o jsonpath='{.metadata.uid} PipelineRun {.metadata.name}{"\n"}' < /dev/null
    kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{range .items[*]}{.metadata.uid} TaskRun {.metadata.name}{"\n"}{end}' < /dev/null
  done > "$c/objets.txt"
  echo "invocationId des enveloppes (nombre, valeur, objet de rpm) :"
  jq -r '.payload | @base64d | fromjson | .predicate.runDetails.metadata.invocationId // "-"' "$c/enveloppes.json" | sort | uniq -c \
    | while read -r i uid; do echo "     $i $uid $(awk -v u="$uid" '$1 == u {print $2, $3}' "$c/objets.txt" | grep . || echo "(hors de rpm)")"; done
  for i in 1 2; do
    pr=$N-rpm-$i
    uid=$(kubectl get pipelinerun -n builds "$pr" -o jsonpath='{.metadata.uid}' < /dev/null)
    echo "## provenance de $pr ($uid)"
    mkdir -p "$c/$pr"
    controler_prov "$c/enveloppes.json" "$uid" "$s" "$c/deps-attendues.txt" "$c/params-attendus.txt" "$c/$pr"
  done
  echo "## signature simplesigning (tag .sig), relevé"
  r=0; cosign verify --key "$CLE_CHAINS" --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "${s/$REG/$REG_HOTE}" \
    < /dev/null > "$c/signatures.json" 2> "$c/verify.err" || r=$?
  echo "cosign verify : code $r ; $(jq -s 'flatten | length' "$c/signatures.json" 2> /dev/null || echo -) signature(s) valide(s) ; digests signés : $(
    jq -r -s 'flatten | map(.critical.image["docker-manifest-digest"]) | unique | join(" ")' "$c/signatures.json" 2> /dev/null || echo -) (relevé, non exigé)"
  echo "## refus"
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$c/autre.pub" 2> /dev/null
  refus "provenance vérifiée avec une autre clé" "no matching attestations|invalid signature" \
    cosign verify-attestation --key "$c/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "${s/$REG/$REG_HOTE}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  for e in "$@"; do [ ! -e "$R/$N-fermeture-$e.log" ] || { echo "journal déjà présent, jamais réécrit : resultats/$N-fermeture-$e.log" >&2; exit 2; }; done
  lancer "$N-fermeture" "05 cascade de M1b, M4b refait" "$@"
fi
