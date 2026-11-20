#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b (§5 de resultats/m1b-carte.md), troisième point : les tâches prefetch-rpm (M4b) et construire-rpm (M4c)
# re-signées avec l'outillage de M1b (builds/builders/mock-rocky9@70f8c412) au lieu de l'outillage d'essai (essais-05/mock-rocky9
# @99790c13, « Option 1 »). Préparé à sec le 20/11/2026. Script frère de m4b.sh et m4c.sh, qui ne sont pas touchés : leurs
# gabarits, leurs tâches signées (fermeture/prefetch-rpm.signee.yaml, construction/construire-rpm.signee.yaml), leurs tags (m4b,
# m4c) et leurs journaux restent tels quels. Les gabarits sont rendus sans changement ; seule l'image change.
# Repris à l'identique (le banc les compare aux originaux) :
#   de m4b.sh : remplacer, rendre_taches, substituer, pod_spec, dans, ARBRE, et etape_essai_tache (devenue etape_essai_prefetch,
#               remplacements listés et comptés par le banc) ;
#   de m4c.sh : attendu, ref_revue, script_etape, mesure, pod_retirer, copier_pod, politique_relue, echec, admission, libre_zot,
#               normaliser, et etape_essai (devenue etape_essai_construire, de même) ;
#   de m1b-artefact.sh : neuf, sha, zot_lire.
#   local             hôte seul, hors ligne : sources contrôlées par sha256 ; témoin de méthode : les gabarits rendus avec l'image
#                     d'essai, normalisés, égaux aux tâches signées de M4b et M4c ; rendus avec l'image neuve : une seule feuille
#                     différente, .spec.steps[0].image ; scripts substitués égaux à ceux des essais de M4b (572fb78c) et de M4c
#                     (0b119024) ; entrees.tar de m4c prealables contrôlé (taille, sha256).
#   essai_prefetch    pod d'essai runc (rien dans Zot), copie de essai_tache de M4b, image neuve : le script substitué avec les
#                     paramètres de M4b (verrou b6d0f8f1, bootstrap d'essai) ; repomd.xml V2, résultat de bootstrap et arbre égal à
#                     celui de final (m4b-final-arbre.txt) ; cas refusé (repomd.xml faux) ; pod et PVC retirés.
#   essai_construire  pod d'essai Kata (rien dans Zot), copie de essai de M4c, image neuve : entrees.tar de m4c prealables (verrou
#                     b6d0f8f1, fermeture de M4b) ; Source0, src.rpm, rpm et digest de l'artefact relevés contre M3 et l'essai de
#                     M4c (07b7bd6f) sans arrêter ; pod supprimé.
#   taches            SIGNER=1 seulement, sur accord nommé du propriétaire (signature, écritures dans Zot) : rendus admis en
#                     dry-run serveur, témoin computeResources refusé ; les deux tâches signées (tkn, clé des tâches) et relues
#                     avant tout versionnement et toute poussée (égales au rendu, une seule feuille différente de M4b ou M4c, scripts
#                     des essais) ; gardes (tag neuf absent des deux dépôts, tags m4b et m4c sur leurs digests, place libre) ;
#                     signatures versionnées sous des noms neufs (<tâche>.<TAG>.signee.yaml) ; bundles poussés au tag neuf
#                     (écritures définitives) ; références à ajouter à la liste revue de la 08 après revue du propriétaire.
#                     Aucune pipeline n'est signée ici : prefetch-rpm-sample-app et sample-app-rpm changent avec M4b et M4c refaits.
# Aucun secret en argument ; l'authentification de Zot est écrite sous $T/auth (0700) et retirée à la sortie, même en échec.
# Un journal existant n'est jamais réécrit : relancer sous un autre PREFIXE (et donc un autre tag par défaut).
# Usage (racine du dépôt) : [PREFIXE=m1b] [TAG=$PREFIXE] [SIGNER=1] DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m1b-bundles.sh <étape>…
#         (journaux : resultats/$PREFIXE-bundles-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, bundle, listee, auth_zot, sur, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
N=${PREFIXE:-m1b}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
TAG=${TAG:-$N}
case $TAG in m4b|m4c|essai) echo "tag refusé : $TAG appartient à M4b, M4c ou aux essais" >&2; exit 2 ;; ''|*[!a-z0-9-]*) echo "TAG invalide : $TAG" >&2; exit 2 ;; esac
T=$W/$N-bundles-05
mkdir -p "$T"
umask 022

# Images d'outillage
IMAGE_NEUVE=$REG/builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae   # M1b (PN), m1b-verrou.sh
IMAGE_ESSAI=$REG/essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771   # « Option 1 », m4b.sh et m4c.sh
IMAGE=$IMAGE_NEUVE   # lue par rendre_taches et pod_spec (m4b.sh)
# Gabarits et tâches signées de M4b et M4c (lus seulement)
TACHES=$h05/fermeture
C=$h05/construction
GABARITS_SHA="fermeture/prefetch-rpm.yaml:96b9d6bd056224eeed144fc1d1b093820a32b2fa26e46f2217f797782837968c
fermeture/prefetch-rpm-sample-app.yaml:ee74c25874a43d14051c6f2d11aa53b264ac688bebfec970036a50c42192b534
construction/construire-rpm.yaml:e88f5521ede87f5b03330683939fd3494f5ff58544ded9a9326014e30b8d0f88
fermeture/prefetch-rpm.signee.yaml:4123539575b1f7986f82f648913ee147348c7198399018f3520c7037eeade199
construction/construire-rpm.signee.yaml:faab95fd9464d437aa0c0a98b63fce8fe0dd6a2e4f5c173fb2bcd632e6e2b70c"   # inchangés depuis 19837c2 et 75ed22a
# Références de M4b et M4c (liste revue, tags)
PREFETCH_M4B=$REG/tekton/tasks/prefetch-rpm@sha256:9afe09db6d97d065c29245417a44e54a147b5f32a7e37b7ff5f9616c8110893a     # m4b.sh, 05e2fe8
CONSTRUIRE_M4C=$REG/tekton/tasks/construire-rpm@sha256:d7f01398f188931c124273c8b5fb60e2a66c22e9d0a2dfcd229ecadee1e62164 # m4c.sh, 1d5e27d
LISTE_REVUE=$here/politique/porte/taches.yml
# Entrées des essais : celles de M4b et M4c, à l'identique ; seule l'image change
LISTE=$R/m4b-liste.txt
LISTE_SHA=95541ee86a3c8891d231df6896558a78f73a607037b2a7035312337ab80b8910   # m4b.sh
VERROU_SRC=$R/s1-verrou_derivee.json
VERROU_SHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f   # m4b.sh, m4c.sh
VERROU_ESSAI=$VERROU_SRC
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D   # m4b.sh
REPOMD_V2=239a5a71c887d4370228ffdff016517282086f19de93418ee740482c089be164   # m4b.sh
DEPOT_FERMETURE=$REG/builds/fermetures/sample-app-rpm   # m4b.sh
ARBRE_REF=$R/m4b-final-arbre.txt
ARBRE_REF_SHA=fc556539d9fe7255a7e65fa25278d37c7f85fd728ee97f08c8d8ea2c9f35e880
SCRIPT_PREFETCH_SHA=572fb78cf6b3104dbbbe2c834d236d313f1eb49e0da9b4171d03fc299fc42145   # SCRIPT_ESSAI_SHA de m4b.sh
SCRIPT_CONSTRUIRE_SHA=0b119024e9aa29dd21b486efd9f4951ee6e15b004ed816dbbc089e97d24aac3c # SCRIPTS_ESSAI_SHA de m4c.sh (construire)
ENTREES=$W/m4c-05/entrees.tar   # m4c.sh prealables, lu seulement
ENTREES_TAILLE=318842880
ENTREES_SHA=b84f68ee0ac565a4b3f7ec7f55c6b11ae4a0e5a709e38daef97b9d7369f5f284   # m4c-prealables.log
EPOQUE=1793229566   # m4c.sh
ARCHIVE_SHA=07521c1e60cdbed8a29912ad775e52201daf95003f7f54ccee76b3270742d9bb   # m4c.sh
RPM_M3_SHA=864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f    # m4c.sh
SRPM_M3_SHA=c802e60a511c140e3a6761752b0c9966b2d8959a909d2a3b73d85f9b4bfd1128   # m4c.sh
DIGEST_ESSAI_M4C=sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119   # DIGEST_ESSAI de m4c.sh
# Pods d'essai (valeurs de m4b.sh et m4c.sh)
LABEL=prefetch-rpm
LIMITES='{"cpu": "2", "memory": "2Gi"}'
VOLUME=4Gi
LABEL_PREPARER=preparer-rpm
LABEL_CONSTRUIRE=construire-rpm
MORCEAU_MIO=64
ECARTS=0
FACTICE=sha256:$(printf '0%.0s' {1..64})
LIBRE_MIN=1073741824

# --- recopié de m4c.sh ---
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
ref_revue() { # dépôt-de-tâche préfixe-du-digest : référence complète lue dans la liste revue de la 08 (une seule) ; de s4d.sh
  local r
  r=$(awk -v d="oci://$REG/tekton/tasks/$1:" -v p="sha256:$2" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && index($3, p) == 1 {print $3}' "$LISTE_REVUE")
  [ "$(grep -c . <<< "$r")" = 1 ] && [ -n "$r" ] || { echo "KO   $1 $2 : absente de la liste revue ou ambiguë" >&2; exit 1; }
  echo "$REG/tekton/tasks/$1@$r"
}
script_etape() { yq ".spec.steps[] | select(.name == \"$2\") | .script" "$1"; }   # fichier-rendu nom-d'étape
mesure() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS=$((ECARTS + 1)); }; }
pod_retirer() { kubectl delete pod -n builds "$1" --wait=false < /dev/null > /dev/null; echo "pod $1 supprimé"; }
copier_pod() { # pod conteneur fichier-hôte chemin-pod : par morceaux de 64 Mio, taille relevée après chaque morceau, sha256 final
  local n i k e m=$((MORCEAU_MIO * 1048576)) nb
  n=$(stat -c %s "$3"); nb=$(( (n + m - 1) / m )); [ "$nb" -gt 0 ] || nb=1
  kubectl exec -n builds "$1" -c "$2" -- sh -c ": > $4" < /dev/null
  for ((i = 0; i < nb; i++)); do
    k=$(( n - i * m < m ? n - i * m : m ))
    dd if="$3" bs=1M skip=$((i * MORCEAU_MIO)) count=$MORCEAU_MIO status=none \
      | timeout 120 kubectl exec -i -n builds "$1" -c "$2" -- sh -c "head -c $k >> $4" \
      || { pod_retirer "$1"; echo "KO   copie de ${3##*/}, morceau $((i + 1)) sur $nb" >&2; exit 1; }
    e=$(kubectl exec -n builds "$1" -c "$2" -- stat -c %s "$4" < /dev/null)
    [ "$e" = "$(( i * m + k ))" ] || { pod_retirer "$1"; echo "KO   copie de ${3##*/} : $e octets après le morceau $((i + 1))" >&2; exit 1; }
  done
  e=$(kubectl exec -n builds "$1" -c "$2" -- sha256sum "$4" < /dev/null | cut -c1-64)
  [ "$e" = "$(sha256sum < "$3" | cut -c1-64)" ] && echo "OK   copie de ${3##*/} dans le pod : $n octets en $nb morceau(x), sha256 conforme" \
    || { pod_retirer "$1"; echo "KO   copie de ${3##*/} : sha256 dans le pod $e" >&2; exit 1; }
}
politique_relue() { # politiques de builds relues dans le cluster, lecture seule ; KO si construire-rpm n'est pas coupé (s1.sh, M3)
  local t=$T/politiques.json
  { kubectl get networkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "NetworkPolicy"'
    kubectl get ciliumnetworkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "CiliumNetworkPolicy"'; } | jq -s '{items: .}' > "$t"
  echo "politiques de builds : $(jq -r '[.items[] | "\(.kind) \(.metadata.name)"] | join(", ")' "$t")"
  attendu "construction-rpm-sans-sortie : sélecteur, types, règles d'entrée et de sortie" \
    "$(jq -c '[.items[] | select(.kind == "NetworkPolicy" and .metadata.name == "construction-rpm-sans-sortie")
      | [.spec.podSelector, (.spec.policyTypes | sort), (.spec.ingress // []), (.spec.egress // [])]]' "$t")" \
    "[[{\"matchLabels\":{\"tekton.dev/task\":\"$LABEL_CONSTRUIRE\"}},[\"Egress\",\"Ingress\"],[],[]]]"
  attendu "politiques de builds qui sélectionnent $LABEL_CONSTRUIRE et autorisent du trafic" "$(jq -r -L "$here" --arg l "$LABEL_CONSTRUIRE" \
    'include "selecteurs"; [.items[] | select(selectionne({"tekton.dev/task": $l}) and autorise) | nom] | join(", ")' "$t")" ""
  echo "relevé : politiques de builds qui sélectionnent $LABEL_PREPARER : $(jq -r -L "$here" --arg l "$LABEL_PREPARER" \
    'include "selecteurs"; [.items[] | select(selectionne({"tekton.dev/task": $l})) | "\(.kind) \(nom)"] | join(", ")' "$t")"
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
# --- recopié de m4b.sh ---
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
# --- recopié de m1b-artefact.sh ---
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
# --- fin des copies ---

# Feuilles différentes entre deux objets JSON (une ligne « chemin : avant -> après » par feuille, triées ; <absent> si manquante)
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
sources() { # sha256 des gabarits, des tâches signées et des entrées des essais
  local e
  for e in $GABARITS_SHA; do attendu "${e%%:*} (sha256)" "$(sha "$h05/${e%%:*}")" "${e#*:}"; done
  attendu "liste des rpm (sha256)" "$(sha "$LISTE")" "$LISTE_SHA"
  attendu "verrou de M4a et M4b (sha256)" "$(sha "$VERROU_SRC")" "$VERROU_SHA"
  attendu "arbre de final (sha256)" "$(sha "$ARBRE_REF")" "$ARBRE_REF_SHA"
}
source_dossier() { # verrou : « source dossier » du bootstrap, comme m4b.sh (config.py:844-846)
  local src
  src=$(jq -r '.config.bootstrap_image' "$1"); echo "$src ${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$1")"
}
rendre() { # dossier image : prefetch-rpm, prefetch-rpm-sample-app (tâches factices, bootstrap de M4b) et construire-rpm rendus
  local src dos
  read -r src dos < <(source_dossier "$VERROU_SRC")
  mkdir -p "$1"
  (T=$1; IMAGE=$2; rendre_taches "$REG/tekton/tasks/prefetch-rpm@$FACTICE" "$REG/tekton/tasks/publier-fermeture@$FACTICE" "$src" "$dos")
  remplacer "$C/construire-rpm.yaml" "$1/construire-rpm.yaml" "IMAGE=$2"
}
scripts() { # dossier : scripts substitués de prefetch-rpm (paramètres de la pipeline de M4b) et de construire-rpm (comme m4c.sh)
  substituer "$1/prefetch-rpm.yaml" "$1/prefetch-rpm-sample-app.yaml" /workspace/sortie /tmp/resultat-bootstrap.json "$1/script-prefetch.sh"
  script_etape "$1/construire-rpm.yaml" construire \
    | sed -e 's#\$(workspaces.entrees.path)#/e#g' -e 's#\$(workspaces.sortie.path)#/o#g' -e 's#\$(results.DIGEST_CONSTRUIT.path)#/w/digest#g' \
    > "$1/script-construire.sh"
  attendu "${1##*/} : script de prefetch-rpm substitué, égal à celui de l'essai de M4b (sha256)" "$(sha "$1/script-prefetch.sh")" "$SCRIPT_PREFETCH_SHA"
  attendu "${1##*/} : script de construire-rpm substitué, égal à celui de l'essai de M4c (sha256)" "$(sha "$1/script-construire.sh")" "$SCRIPT_CONSTRUIRE_SHA"
}
une_feuille() { # libellé json-avant json-après : une seule feuille différente, l'image du pas
  local d
  d=$(diff_feuilles "$2" "$3")
  printf '%s\n' "$d" | sed 's/^/     /'
  attendu "$1 : feuilles différentes" "$d" ".spec.steps[0].image : \"$IMAGE_ESSAI\" -> \"$IMAGE_NEUVE\""
}

etape_local() { # hôte seul, hors ligne
  local n
  sources
  neuf "$T/local"; mkdir "$T/local"
  echo "## témoin de méthode : gabarits rendus avec l'image d'essai, normalisés, contre les tâches signées de M4b et M4c"
  rendre "$T/local/essai" "$IMAGE_ESSAI"
  normaliser "$TACHES/prefetch-rpm.signee.yaml" > "$T/local/prefetch-rpm-m4b.json"
  normaliser "$C/construire-rpm.signee.yaml" > "$T/local/construire-rpm-m4c.json"
  for n in prefetch-rpm construire-rpm; do normaliser "$T/local/essai/$n.yaml" > "$T/local/essai/$n.json"; done
  attendu "témoin : prefetch-rpm rendue avec l'image d'essai, égale à la tâche signée de M4b" \
    "$(cmp -s "$T/local/essai/prefetch-rpm.json" "$T/local/prefetch-rpm-m4b.json" && echo égale || echo différente)" égale
  attendu "témoin : construire-rpm rendue avec l'image d'essai, égale à la tâche signée de M4c" \
    "$(cmp -s "$T/local/essai/construire-rpm.json" "$T/local/construire-rpm-m4c.json" && echo égale || echo différente)" égale
  scripts "$T/local/essai"
  echo "## gabarits rendus avec l'image neuve"
  rendre "$T/local/neuf" "$IMAGE_NEUVE"
  for n in prefetch-rpm construire-rpm; do normaliser "$T/local/neuf/$n.yaml" > "$T/local/neuf/$n.json"; done
  une_feuille "prefetch-rpm neuve contre celle de M4b" "$T/local/prefetch-rpm-m4b.json" "$T/local/neuf/prefetch-rpm.json"
  une_feuille "construire-rpm neuve contre celle de M4c" "$T/local/construire-rpm-m4c.json" "$T/local/neuf/construire-rpm.json"
  attendu "pipeline de prefetch rendue : égale à celle du témoin (le bootstrap de M4b, l'image n'y figure pas)" \
    "$(cmp -s "$T/local/essai/prefetch-rpm-sample-app.yaml" "$T/local/neuf/prefetch-rpm-sample-app.yaml" && echo égale || echo différente)" égale
  scripts "$T/local/neuf"
  attendu "script de prefetch, sh -n (sh du pas de Tekton)" "$(sh -n "$T/local/neuf/script-prefetch.sh" && echo ok)" ok
  attendu "script de construire, bash -n (lancé par bash, comme à l'essai de M4c)" "$(bash -n "$T/local/neuf/script-construire.sh" && echo ok)" ok
  echo "## références de M4b et M4c dans la liste revue ; image neuve"
  attendu "prefetch-rpm de M4b, lue dans la liste revue" "$(ref_revue prefetch-rpm 9afe09db)" "$PREFETCH_M4B"
  attendu "construire-rpm de M4c, lue dans la liste revue" "$(ref_revue construire-rpm d7f01398)" "$CONSTRUIRE_M4C"
  echo "relevé : lignes de la liste revue qui citent l'image neuve : $(grep -c -F "${IMAGE_NEUVE##*@}" "$LISTE_REVUE" || true)"
  echo "## entrées de l'essai de construction (m4c prealables)"
  attendu "entrees.tar (taille, sha256)" "$(stat -c %s "$ENTREES") $(sha "$ENTREES")" "$ENTREES_TAILLE $ENTREES_SHA"
}

etape_essai_prefetch() { # pod d'essai : le script substitué de la tâche, tel qu'il sera signé ; puis le cas refusé (repomd.xml faux)
  sources
  local src dos rc POD=$N-bundles-prefetch faux=0000000000000000000000000000000000000000000000000000000000000000
  src=$(jq -r '.config.bootstrap_image' "$VERROU_SRC"); dos=${src%%:*}@$(jq -r '.bootstrap.pull_digest' "$VERROU_SRC")
  rendre_taches "$REG/tekton/tasks/prefetch-rpm@$FACTICE" "$REG/tekton/tasks/publier-fermeture@$FACTICE" "$src" "$dos"
  substituer "$T/prefetch-rpm.yaml" "$T/prefetch-rpm-sample-app.yaml" /workspace/sortie /tmp/resultat-bootstrap.json "$T/script-essai.sh"
  substituer "$T/prefetch-rpm.yaml" "$T/prefetch-rpm-sample-app.yaml" /workspace/sortie/refus /tmp/resultat-refus.json "$T/script-refus.sh" "$faux"
  attendu "scripts : nominal et refusé, seuls écarts le workspace, le résultat et repomd" \
    "$(diff "$T/script-essai.sh" "$T/script-refus.sh" | grep -c '^>')" 3
  attendu "script substitué, égal à celui de l'essai de M4b (sha256)" "$(sha256sum < "$T/script-essai.sh" | cut -c1-64)" "$SCRIPT_PREFETCH_SHA"
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
  attendu "arbre égal à celui de final" "$([ "$(sha256sum < "$T/prefetch-essai-arbre.txt")" = "$(sha256sum < "$ARBRE_REF")" ] && echo égal || echo différent)" égal
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

etape_essai_construire() { # pod Kata au label construire-rpm, à la forme que Tekton produira : contexte du podTemplate au niveau du pod (UID
  # 65532, runAsNonRoot), pas root privilégié au niveau du conteneur ; entrées sur un volume à part, remplies par un second
  # conteneur en UID 65532 et montées en lecture seule dans le conteneur de mock ; script de construire-rpm tiré du gabarit rendu,
  # variables de Tekton seules substituées ; image.tar rapatrié ; écarts à M3 relevés sans arrêter ; pod supprimé
  local p=$N-bundles-construire x=$T/essai-construire rc=0 d s
  attendu "entrees.tar de m4c prealables (taille, sha256)" "$(stat -c %s "$ENTREES") $(sha "$ENTREES")" "$ENTREES_TAILLE $ENTREES_SHA"
  neuf "$x"; mkdir -p "$x"
  rendre "$T" "$IMAGE_NEUVE"
  script_etape "$T/construire-rpm.yaml" construire \
    | sed -e 's#\$(workspaces.entrees.path)#/e#g' -e 's#\$(workspaces.sortie.path)#/o#g' -e 's#\$(results.DIGEST_CONSTRUIT.path)#/w/digest#g' > "$x/construire.sh"
  attendu "script d'essai : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/construire.sh" || true)" 0
  attendu "script d'essai : égal au script du gabarit, variables de Tekton exceptées" \
    "$(diff <(script_etape "$T/construire-rpm.yaml" construire) "$x/construire.sh" | grep -c '^>' || true)" 3
  attendu "script d'essai : égal à celui de l'essai de M4c (sha256)" "$(sha "$x/construire.sh")" "$SCRIPT_CONSTRUIRE_SHA"
  politique_relue
  jq -n --arg n "$p" --arg lb "$LABEL_CONSTRUIRE" --arg i "$IMAGE_NEUVE" --arg ep "$EPOQUE" \
    --argjson sc "$(yq -o=json -I=0 '.spec.steps[0].securityContext' "$T/construire-rpm.yaml")" \
    --argjson res "$(yq -o=json -I=0 '.spec.steps[0].resources' "$T/construire-rpm.yaml")" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"tekton.dev/task": $lb}},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      runtimeClassName: "kata",
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: "4Gi"}}, {name: "e", emptyDir: {}}, {name: "o", emptyDir: {}}],
      containers: [
        {name: "essai", image: $i, command: ["sleep", "7200"], securityContext: $sc, resources: $res, env: [{name: "EPOQUE", value: $ep}],
          volumeMounts: [{name: "w", mountPath: "/w"}, {name: "e", mountPath: "/e", readOnly: true}, {name: "o", mountPath: "/o"}]},
        {name: "remplir", image: $i, command: ["sleep", "7200"],
          securityContext: {runAsUser: 65532, runAsNonRoot: true, allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}},
          resources: {requests: {cpu: "100m", memory: "256Mi"}, limits: {cpu: "1", memory: "1Gi"}},
          volumeMounts: [{name: "e", mountPath: "/e"}]}]}}' > "$x/pod.json"
  attendu "pod d'essai : contexte du pas égal à celui du gabarit" "$(jq -c '.spec.containers[0].securityContext' "$x/pod.json")" \
    '{"privileged":true,"allowPrivilegeEscalation":true,"runAsUser":0,"runAsGroup":0,"runAsNonRoot":false}'
  kubectl delete pod -n builds "$p" --ignore-not-found --wait=true < /dev/null > /dev/null
  trap "kubectl delete pod -n builds $p --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true" EXIT
  kubectl create --dry-run=server -f "$x/pod.json" < /dev/null > /dev/null || { echo "KO   pod $p refusé en dry-run serveur" >&2; exit 1; }
  echo "OK   pod $p admis en dry-run serveur"
  kubectl create -f "$x/pod.json" < /dev/null > /dev/null
  echo "pod $p créé à $(date -u +%H:%M:%S) (image $IMAGE_NEUVE)"
  kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null \
    || { pod_retirer "$p"; echo "KO   pod $p non prêt" >&2; exit 1; }
  echo "pod prêt sur $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName {.spec.runtimeClassName}' < /dev/null)"
  copier_pod "$p" remplir "$T/entrees.tar" /e/entrees.tar
  kubectl exec -n builds "$p" -c remplir -- sh -c 'tar --no-same-owner -xf /e/entrees.tar -C /e && rm /e/entrees.tar && echo "entrées déballées par uid $(id -u) : $(find /e -type f | wc -l) fichiers"' < /dev/null \
    || { pod_retirer "$p"; echo "KO   déballage des entrées" >&2; exit 1; }
  # Le script est un fichier dans le pod, comme sous Tekton, et rien n'arrive sur son entrée standard (s4d.sh)
  copier_pod "$p" essai "$x/construire.sh" /w/construire.sh
  echo "## script de construire-rpm dans le pod ($(date -u +%H:%M:%S))"
  timeout 1800 kubectl exec -n builds "$p" -c essai -- bash /w/construire.sh < /dev/null > "$x/construire.log" 2>&1 || rc=$?
  echo "fin à $(date -u +%H:%M:%S)"
  sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' "$x/construire.log" > "$R/$N-bundles-construire-pod.log"
  grep -v '^paquet ' "$R/$N-bundles-construire-pod.log" | cut -c1-220 | sed 's/^/     /'
  echo "     (code de l'exec : $rc ; journal complet : resultats/$N-bundles-construire-pod.log)"
  if [ $rc = 0 ]; then
    kubectl exec -n builds "$p" -c essai -- cat /o/image.tar < /dev/null > "$x/image.tar"
    attendu "image.tar rapatrié (sha256 dans le pod)" "$(sha256sum < "$x/image.tar" | cut -c1-64)" "$(kubectl exec -n builds "$p" -c essai -- sha256sum /o/image.tar < /dev/null | cut -c1-64)"
    d=$(kubectl exec -n builds "$p" -c essai -- cat /w/digest < /dev/null)
  fi
  pod_retirer "$p"
  attendu "écriture refusée sur les entrées (ligne du script atteinte)" "$(grep -c '^invité : .*, écriture refusée$' "$x/construire.log" || true)" 1
  echo "relevé : montage des entrées vu dans le pod : $(sed -n 's/^invité : .* entrees : \(.*\), écriture refusée$/\1/p' "$x/construire.log")"
  s=$(sed -n 's/^Source0 sample-app-1.0.0.tar.gz (époque [0-9]*) : \([0-9a-f]\{64\}\) ;.*/\1/p' "$x/construire.log")
  mesure "Source0 faite par le tar et le gzip de l'image d'outillage, égale à l'archive de sources.sh" "$s" "$ARCHIVE_SHA"
  [ $rc = 0 ] || { echo "KO   script de construire-rpm : code $rc" >&2; exit 1; }
  attendu "dernière ligne du script atteinte (image.tar)" "$(grep -c '^image.tar : [0-9]* octets$' "$x/construire.log" || true)" 1
  mesure "src.rpm construit dans le pod d'essai" "$(sed -n 's/^rpm : [^ ]*\.src\.rpm sha256 \([0-9a-f]\{64\}\) .*/\1/p' "$x/construire.log")" "$SRPM_M3_SHA"
  mkdir -p "$x/lu"; tar -xf "$x/image.tar" -C "$x/lu"
  attendu "index.json lu comme publier-image : égal au résultat" "$(sed -n 's/.*"digest": *"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' "$x/lu/index.json")" "$d"
  mesure "rpm construit dans le pod d'essai (couche)" "$(tar -xOf "$x/lu/blobs/sha256/$(jq -r '.layers[0].digest' "$x/lu/blobs/sha256/${d#sha256:}" | cut -d: -f2)" | sha256sum | cut -c1-64)" "$RPM_M3_SHA"
  mesure "digest de l'artefact, égal à celui de l'essai de M4c" "$d" "$DIGEST_ESSAI_M4C"
  echo "relevé : paquets du buildroot imprimés : $(grep -c '^paquet ' "$x/construire.log" || true) ; écarts au verrou (nom, version, release, arch, sigmd5) : $(diff <(grep '^paquet ' "$x/construire.log") <(jq -r '.buildroot.rpms[] | "paquet \(.name) \(.version) \(.release) \(.arch) \(.sigmd5)"' "$VERROU_ESSAI" | sort) | grep -c '^[<>]' || true)"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

gardes_zot() { # lecture seule (anonyme) : tag neuf absent des deux dépôts, tags m4b et m4c sur leurs digests, place libre ; suffixe
  local libre
  echo '{}' > "$T/vide.json"
  attendu "G1 tekton/tasks/prefetch-rpm:$TAG, lecture anonyme ($1)" "$(zot_lire "tag $TAG" "tekton/tasks/prefetch-rpm:$TAG")" absent
  attendu "G1 tekton/tasks/construire-rpm:$TAG, lecture anonyme ($1)" "$(zot_lire "tag $TAG" "tekton/tasks/construire-rpm:$TAG")" absent
  attendu "G2 tekton/tasks/prefetch-rpm:m4b, lecture anonyme ($1)" "$(zot_lire "tag m4b" tekton/tasks/prefetch-rpm:m4b)" "${PREFETCH_M4B##*@}"
  attendu "G2 tekton/tasks/construire-rpm:m4c, lecture anonyme ($1)" "$(zot_lire "tag m4c" tekton/tasks/construire-rpm:m4c)" "${CONSTRUIRE_M4C##*@}"
  libre=$(libre_zot)
  case $libre in ''|*[!0-9]*) echec "G3 place libre illisible : $libre" ;; esac
  [ "$libre" -ge "$LIBRE_MIN" ] || echec "G3 place libre sur / de sc-stockage : $libre octets, sous $LIBRE_MIN"
  echo "OK   G3 octets libres sur / de sc-stockage (porte /var/lib/zot), $1 : $libre (seuil $LIBRE_MIN)"
}
controler_signee() { # tâche dossier : contenu signé relu (signature, égal au rendu, une seule feuille différente de M4b ou M4c)
  local n=$1 x=$2
  attendu "$n signée : annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$x/$n-signee.yaml")" true
  normaliser "$x/$n-signee.yaml" > "$x/$n-signee.json"
  attendu "$n signée : égale à la tâche rendue, signature exceptée (normalisées)" \
    "$(cmp -s "$x/$n-signee.json" "$x/$n.json" && echo égale || echo différente)" égale
}

etape_taches() { # SIGNER=1 seulement : signatures, versionnement sous des noms neufs, bundles au tag neuf ; aucune pipeline
  [ -n "${SIGNER:-}" ] || echec "étape taches : SIGNER=1 seulement, sur accord nommé du propriétaire"
  [ -s "$S/taches.key" ] || echec "clé des tâches absente"
  local x=$T/taches n v r libre
  local vp=$TACHES/prefetch-rpm.$TAG.signee.yaml vc=$C/construire-rpm.$TAG.signee.yaml
  neuf "$vp"; neuf "$vc"
  sources
  neuf "$x"; mkdir "$x"
  echo "## gabarits rendus avec l'image neuve ; admission en dry-run serveur, rien n'est créé"
  rendre "$x" "$IMAGE_NEUVE"
  scripts "$x"
  for n in prefetch-rpm construire-rpm; do attendu "$n rendue admise (code de kubectl)" "$(admission "$x/$n.yaml")" 0; done
  yq '.spec.steps[0].computeResources = .spec.steps[0].resources | del(.spec.steps[0].resources)' "$x/construire-rpm.yaml" > "$x/temoin-v1beta1.yaml"
  [ "$(admission "$x/temoin-v1beta1.yaml")" != 0 ] || echec "témoin (computeResources dans un pas v1beta1) admis : le dry-run ne contrôle plus le nom du champ"
  attendu "témoin refusé : champ inconnu (message mesuré le 18/11 en M4b)" \
    "$(grep -c -F 'strict decoding error: unknown field "spec.steps[0].computeResources"' "$T/admission.out")" 1
  normaliser "$TACHES/prefetch-rpm.signee.yaml" > "$x/prefetch-rpm-m4b.json"
  normaliser "$C/construire-rpm.signee.yaml" > "$x/construire-rpm-m4c.json"
  echo "## signatures (tkn $(tkn version --component client)) ; les deux tâches relues avant tout versionnement et toute poussée"
  for n in prefetch-rpm construire-rpm; do
    normaliser "$x/$n.yaml" > "$x/$n.json"
    tkn task sign "$x/$n.yaml" -K "$S/taches.key" -f "$x/$n-signee.yaml" > /dev/null
  done
  for n in prefetch-rpm construire-rpm; do controler_signee "$n" "$x"; done
  une_feuille "prefetch-rpm signée contre celle de M4b" "$x/prefetch-rpm-m4b.json" "$x/prefetch-rpm-signee.json"
  une_feuille "construire-rpm signée contre celle de M4c" "$x/construire-rpm-m4c.json" "$x/construire-rpm-signee.json"
  echo "## gardes avant toute écriture"
  gardes_zot avant
  cp "$x/prefetch-rpm-signee.yaml" "$vp"; cp "$x/construire-rpm-signee.yaml" "$vc"
  echo "signatures versionnées : fermeture/${vp##*/} (sha256 $(sha "$vp")), construction/${vc##*/} (sha256 $(sha "$vc"))"
  (umask 077 && mkdir -p "$T/auth")
  trap 'find "$T/auth" -depth -delete 2> /dev/null || true' EXIT   # copie du secret de Zot, retirée même en cas d'échec (sans rm)
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh), compte poc-ecriture
  echo "## bundles, tag $TAG (écritures définitives)"
  r=$REG/tekton/tasks/prefetch-rpm@$(bundle "$vp" tekton/tasks/prefetch-rpm "$TAG"); echo "$r" > "$x/prefetch-rpm.ref"
  echo "prefetch-rpm : $r"
  r=$REG/tekton/tasks/construire-rpm@$(bundle "$vc" tekton/tasks/construire-rpm "$TAG"); echo "$r" > "$x/construire-rpm.ref"
  echo "construire-rpm : $r"
  find "$T/auth" -depth -delete
  echo "## relecture anonyme après"
  for n in prefetch-rpm construire-rpm; do
    r=$(cat "$x/$n.ref")
    attendu "P1 tekton/tasks/$n:$TAG, lecture anonyme après" "$(zot_lire "tag $TAG" "tekton/tasks/$n:$TAG")" "${r##*@}"
  done
  attendu "P2 tekton/tasks/prefetch-rpm:m4b, lecture anonyme après" "$(zot_lire "tag m4b" tekton/tasks/prefetch-rpm:m4b)" "${PREFETCH_M4B##*@}"
  attendu "P2 tekton/tasks/construire-rpm:m4c, lecture anonyme après" "$(zot_lire "tag m4c" tekton/tasks/construire-rpm:m4c)" "${CONSTRUIRE_M4C##*@}"
  libre=$(libre_zot)
  echo "octets libres sur / de sc-stockage après : $libre"
  for n in prefetch-rpm construire-rpm; do
    r=$(cat "$x/$n.ref")
    if listee "$r"; then echo "OK   $n dans la liste revue : $r"
    else echo "SIGNER : à ajouter à politique/porte/taches.yml (08) après revue du propriétaire : $r"; fi
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  for e in "$@"; do [ ! -e "$R/$N-bundles-$e.log" ] || { echo "journal déjà présent, jamais réécrit : resultats/$N-bundles-$e.log" >&2; exit 2; }; done
  lancer "$N-bundles" "05 cascade de M1b, bundles" "$@"
fi
