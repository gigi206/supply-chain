#!/usr/bin/env bash
# Brique 06, jalon S4b (décision du propriétaire du 11/11/2026, 16:42:27 UTC : « A, N1, combinée ») : fermetures de construction du
# deb produites par la plateforme. Prédictions : resultats/s4b-predictions.md, écrites et commitées avant ce lancement. Chaque étape
# qui écrit dans Zot ou le cluster attend un accord nommé.
#   prealables      hôte seul, hors ligne : artefact de packaging tiré par digest du layout local de S4c, verrou égal à celui du
#                   dépôt ; liste (colonnes 4 à 6) ; gabarits rendus (refs factices) ; script de prefetch-gomod v2 : syntaxe, écart
#                   avec la version 1 ; contrôle npm de la v2 tiré du gabarit rendu, sur l'arbre de sample-app et sur des cas
#                   altérés ; section oras push --oci-layout de publier-fermeture sur un faux miroir (contenus en double, + et ~)
#   taches_deb      écriture dans Zot (poc-ecriture) : artefact de packaging relu dans Zot par digest, égal au layout local ;
#                   pipeline prefetch-deb-sample-app rendue (prefetch-deb et publier-fermeture de la liste revue), signée, bundle
#   taches_sources  écriture dans Zot (poc-ecriture) : prefetch-gomod v2 signée (SIGNER=1 pour la signature versionnée, puis
#                   revue de la liste de la 08), bundle ; pipeline prefetch-sources-sample-app signée, bundle
#   deb             cluster et Zot : deux PipelineRuns de prefetch-deb-sample-app (s4b-deb-1, s4b-deb-2), l'un après l'autre
#   sources         cluster et Zot : deux PipelineRuns de prefetch-sources-sample-app (s4b-sources-1, s4b-sources-2)
#   comparaison     lecture dans Zot, puis hôte : fermetures tirées par digest ; deb : fichiers, pool égal au verrou, index selon
#                   l'InRelease ; sources : fichiers gomod égaux à ceux de F2, archive npm égale à l'integrity du lockfile
#   provenance      lecture dans Zot : provenances vérifiées par cosign (clé de Chains) ; sujets, buildType, dépendances
#                   résolues ; paramètres liste et paquets lus dans le contenu des TaskRuns ; autre clé refusée
# Rien n'est supprimé dans Zot (pas de droit de suppression) : dépôts tekton/pipelines/prefetch-deb-sample-app,
# tekton/pipelines/prefetch-sources-sample-app, tekton/tasks/prefetch-gomod (tag s4b), builds/fermetures/sample-app-deb et
# builds/fermetures/sample-app-sources définitifs.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4b.sh <étape>…   (journal : resultats/s4b-<étape>.log)
set -euo pipefail
export LC_ALL=C

h06=$(cd "$(dirname "$0")" && pwd)
here=$h06/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, OUTILS, refus, purger_pr, bundle, signe, auth_zot, lancer
R=$h06/resultats
F=$h06/fermetures
T=$W/s4b-06
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets, même en cas d'échec
umask 022

INSTANTANE=http://snapshot.debian.org/archive/debian/20261105T000000Z
INRELEASE=0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675   # s1-prealables.log : signataires vérifiés
PACKAGING=$REG/entrees/sample-app/packaging-deb@sha256:c1719b133236f49c7e2492f4b608a8dc421bf812d7f7e438d879a871f61c2e51   # S4c
LAYOUT_S4C=$W/s4c-06/layout-1   # layout local de S4c, même digest (C4, C5)
PREFETCH_IMAGE=$REG/plateforme/outils-prefetch@sha256:68e0ae705de5a8f993f168d8252b3218d7d3ed76e704cf24d4414006aea7b8cc   # prefetch.sh (03)
PAQUETS='[{"type": "gomod"}, {"type": "npm", "path": "web"}]'
DEPOT_DEB=$REG/builds/fermetures/sample-app-deb
DEPOT_SOURCES=$REG/builds/fermetures/sample-app-sources
COMMIT=6391fd437f26696847041be3226bbbf633f55a2f   # construction.sh : main de workspace/sample-app (arbre 30e808ff = poc/sample-app)
DEPOT_GIT=https://sc-stockage.poc.test:3000/workspace/sample-app.git
F2=$HOME/.cache/supply-chain-poc/03/f2/f-1   # fermeture gomod de F2 (même commit), tirée par digest en F2
LISTE_REVUE=$here/politique/porte/taches.yml
FACTICE=sha256:$(printf '0%.0s' {1..64})

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
ref_revue() { # dépôt-de-tâche préfixe-du-digest : référence complète lue dans la liste revue de la 08 (une seule)
  local r
  r=$(awk -v d="oci://$REG/tekton/tasks/$1:" -v p="sha256:$2" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && index($3, p) == 1 {print $3}' "$LISTE_REVUE")
  [ "$(grep -c . <<< "$r")" = 1 ] && [ -n "$r" ] || { echo "KO   $1 $2 : absente de la liste revue ou ambiguë" >&2; exit 1; }
  echo "$REG/tekton/tasks/$1@$r"
}
liste_revue() { # bundle (par digest) : présent dans la liste revue de la 08
  awk -v d="oci://${1%@*}:" -v r="${1#*@}" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && $3 == r {t = 1} END {exit !t}' "$LISTE_REVUE"
}
remplacer() { # source destination clé=valeur… : variables @CLE@ remplacées hors des commentaires ; @LISTE@ = fichier indenté
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
liste() { # répertoire de l'artefact de packaging tiré : liste « sha256 taille chemin » dans $T/liste.txt et $T/liste-indentee.txt
  attendu "verrou tiré égal au verrou du dépôt" "$(cmp -s "$1/verrou-deb.txt" "$repo/poc/packaging/verrou-deb.txt" && echo égal || echo différent)" égal
  awk '{print $4, $5, $6}' "$1/verrou-deb.txt" > "$T/liste.txt"
  sed 's/^/        /' "$T/liste.txt" > "$T/liste-indentee.txt"
  attendu "liste : lignes, octets" "$(grep -c . "$T/liste.txt") $(awk '{s += $2} END {print s}' "$T/liste.txt")" "162 193978008"
}
rendre_deb() { # prefetch-deb publier-fermeture
  remplacer "$F/prefetch-deb-sample-app.yaml" "$T/prefetch-deb-sample-app.yaml" "PREFETCH_DEB=$1" "PUBLIER_FERMETURE=$2" \
    "INSTANTANE=$INSTANTANE" "INRELEASE=$INRELEASE" "LISTE=$T/liste-indentee.txt" "DEPOT_FERMETURE=$DEPOT_DEB"
  attendu "liste rendue dans la pipeline deb, identique à la liste" \
    "$(yq '.spec.tasks[0].params[] | select(.name == "liste") | .value' "$T/prefetch-deb-sample-app.yaml" | sed '/^$/d' | cmp - "$T/liste.txt" && echo identique)" identique
  attendu "pipeline deb : subPath de prefetch, racine pour publier" \
    "$(yq -o=json -I=0 '[.spec.tasks[].workspaces[0].subPath]' "$T/prefetch-deb-sample-app.yaml")" '["fermeture",null]'
}
rendre_sources() { # prefetch-gomod publier-fermeture
  remplacer "$F/prefetch-sources-sample-app.yaml" "$T/prefetch-sources-sample-app.yaml" "PREFETCH_GOMOD=$1" "PUBLIER_FERMETURE=$2" \
    "PAQUETS=$PAQUETS" "DEPOT_FERMETURE=$DEPOT_SOURCES"
  attendu "demande Hermeto rendue dans la pipeline sources" \
    "$(yq '.spec.tasks[0].params[] | select(.name == "paquets") | .value' "$T/prefetch-sources-sample-app.yaml")" "$PAQUETS"
}

etape_prealables() {
  local x=$T/essais a
  rm -rf "$x"; mkdir -p "$x"
  echo "## artefact de packaging (layout local de S4c, tiré par digest)"
  oras pull --no-tty --oci-layout -o "$x/packaging" "$LAYOUT_S4C@${PACKAGING#*@}" > /dev/null
  liste "$x/packaging"
  echo "## gabarits rendus (refs factices)"
  remplacer "$F/prefetch-gomod.yaml" "$T/prefetch-gomod.yaml" "PREFETCH=$PREFETCH_IMAGE"
  rendre_deb "$REG/tekton/tasks/prefetch-deb@$FACTICE" "$REG/tekton/tasks/publier-fermeture@$FACTICE"
  rendre_sources "$REG/tekton/tasks/prefetch-gomod@$FACTICE" "$REG/tekton/tasks/publier-fermeture@$FACTICE"
  for a in prefetch-gomod prefetch-deb-sample-app prefetch-sources-sample-app; do
    attendu "$a : YAML lisible par yq, nom" "$(yq -e '.metadata.name' "$T/$a.yaml")" "$a"
  done
  attendu "prefetch-gomod v2 : paramètre paquets sans valeur par défaut" "$(yq '.spec.params[] | select(.name == "paquets") | has("default")' "$T/prefetch-gomod.yaml")" false
  echo "## prefetch-gomod : version 2 et version 1 (script)"
  yq '.spec.steps[0].script' "$T/prefetch-gomod.yaml" > "$x/v2.sh"
  sed "s#@PREFETCH@#$PREFETCH_IMAGE#g" "$here/politique/taches/prefetch-gomod.yaml" | yq '.spec.steps[0].script' > "$x/v1.sh"
  attendu "v2 : syntaxe sh du script" "$(sh -n "$x/v2.sh" 2>&1 && echo OK)" OK
  diff "$x/v1.sh" "$x/v2.sh" | grep '^[<>]' | cut -c1-150 | sed 's/^/     /' || true
  attendu "v1 et v2 : lignes de v1 changées (version des outils, appel d'Hermeto)" "$(diff "$x/v1.sh" "$x/v2.sh" | grep -c '^<' || true)" 2
  echo "## contrôle npm de la v2 (tiré du gabarit rendu), sur l'arbre de sample-app et sur des cas altérés"
  sed -n "/<<'FIN'$/,/^FIN$/p" "$x/v2.sh" | sed '1d;$d' > "$x/controle.py"
  python3 -I -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$x/controle.py" && echo "OK   contrôle : syntaxe Python"
  git -C "$repo" archive HEAD poc/sample-app | tar -x -C "$x" && mv "$x/poc/sample-app" "$x/src" && rmdir "$x/poc"
  attendu "arbre de sample-app (celui du commit $COMMIT)" "$(git -C "$repo" rev-parse HEAD:poc/sample-app)" 30e808ffa327288c656ddda7b6fafe4005234b77
  controle() { python3 -I "$x/controle.py" "$1" "$2" 2>&1; }
  attendu "cas positif (demande de la pipeline)" "$(controle "$x/src" "$PAQUETS" | tail -1)" \
    "npm web : package-lock.json, lockfileVersion 3, 1 paquet(s), tous de https://registry.npmjs.org/ avec integrity sha512"
  attendu "cas positif (gomod seul)" "$(controle "$x/src" '[{"type": "gomod"}]')" "gomod . : admis"
  cas() { # libellé demande modification-python-du-lockfile|- [fichier] : le contrôle doit refuser
    local c=$x/cas; rm -rf "$c"; cp -a "$x/src" "$c"
    [ "$3" = - ] || python3 -I - "$c/web/${4:-package-lock.json}" "$c/web/package-lock.json" "$3" <<'FIN'
import json, sys
dst, src, code = sys.argv[1:]
l = json.load(open(src)); m = l['packages']['node_modules/marked']
exec(code)
json.dump(l, open(dst, 'w'))
FIN
    local s; s=$(controle "$c" "$2" || true)
    case $s in "refusé : "*) echo "OK   refusé : $1 ($(cut -c11-120 <<< "$s"))" ;; *) echo "KO   accepté : $1 : $s" >&2; exit 1 ;; esac
  }
  cas "autre hôte en https" "$PAQUETS" "m['resolved'] = 'https://evil.example/marked/-/marked-16.4.1.tgz'"
  cas "registry.yarnpkg.com (admis par Hermeto)" "$PAQUETS" "m['resolved'] = m['resolved'].replace('registry.npmjs.org', 'registry.yarnpkg.com')"
  cas "hôte préfixe (registry.npmjs.org.evil.example)" "$PAQUETS" "m['resolved'] = m['resolved'].replace('registry.npmjs.org', 'registry.npmjs.org.evil.example')"
  cas "dépendance git" "$PAQUETS" "m['resolved'] = 'git+https://github.com/markedjs/marked.git#abc'"
  cas "integrity absente" "$PAQUETS" "del m['integrity']"
  cas "integrity sha1" "$PAQUETS" "m['integrity'] = 'sha1-AAAA'"
  cas "resolved absent (paquet groupé)" "$PAQUETS" "del m['resolved']"
  cas "entrée link" "$PAQUETS" "l['packages']['node_modules/x'] = {'resolved': '../x', 'link': True}"
  cas "lockfileVersion 1" "$PAQUETS" "l['lockfileVersion'] = 1"
  cas "npm-shrinkwrap.json lu avant package-lock.json" "$PAQUETS" "m['resolved'] = 'https://evil.example/m.tgz'" npm-shrinkwrap.json
  cas "chemin ../" '[{"type": "npm", "path": "../web"}]' -
  cas "chemin absolu" '[{"type": "npm", "path": "/tmp"}]' -
  cas "type pip" '[{"type": "pip"}]' -
  cas "forme objet (packages et flags)" '{"packages": [{"type": "gomod"}]}' -
  cas "clé en plus" '[{"type": "gomod", "flags": ["x"]}]' -
  cas "entrée en double" '[{"type": "gomod"}, {"type": "gomod", "path": "./"}]' -
  cas "demande vide" '[]' -
  echo "## publier-fermeture : section oras push --oci-layout sur un faux miroir"
  local m=$x/pf/fermeture/miroir s
  mkdir -p "$m/dists/trixie/main/binary-amd64/by-hash/SHA256" "$m/dists/trixie/main/i18n/by-hash/SHA256" "$m/pool/main/g/gcc" "$m/pool/main/a/a"
  echo inrelease > "$m/dists/trixie/InRelease"
  echo index > "$m/dists/trixie/main/binary-amd64/Packages.xz"; echo traduction > "$m/dists/trixie/main/i18n/Translation-en.xz"
  for a in main/binary-amd64/Packages.xz main/i18n/Translation-en.xz; do
    s=$(sha256sum < "$m/dists/trixie/$a" | cut -c1-64); cp "$m/dists/trixie/$a" "$m/dists/trixie/${a%/*}/by-hash/SHA256/$s"
  done
  echo deb1 > "$m/pool/main/g/gcc/g++-14_14.2.0-19_amd64.deb"; echo deb2 > "$m/pool/main/a/a/golang-go_1.24~2_amd64.deb"
  echo bom > "$x/pf/fermeture/bom.json"
  { echo 'set -eu'; echo "f=$x/pf/fermeture"
    yq '.spec.steps[0].script' "$here/politique/taches/publier-fermeture.yaml" | sed -n '/^cd "\$f"$/,/^  --annotation/p' | sed "s#/layout/f:#$x/pf/layout:#"
    echo 'echo "$d"'; } > "$x/pf/publier.sh"
  attendu "section extraite : cd, boucle find, oras push" "$(grep -c '^cd "$f"$\|find . -type f\|oras push' "$x/pf/publier.sh")" 3
  s=$(sh "$x/pf/publier.sh" 2>&1 | tail -1)
  a=$(jq -r '.manifests[0].digest' "$x/pf/layout/index.json")
  attendu "digest du manifeste" "$s" "$a"
  jq -r '.layers[] | .annotations["org.opencontainers.image.title"] + " " + .digest[7:19]' "$x/pf/layout/blobs/sha256/${a#sha256:}" | sed 's/^/     /'
  attendu "couches : nombre, titres distincts (7 fichiers hors bom.json)" \
    "$(jq -r '[.layers | length, (map(.annotations["org.opencontainers.image.title"]) | unique | length)] | join(" ")' "$x/pf/layout/blobs/sha256/${a#sha256:}")" "7 7"
  attendu "couches de même contenu sous deux titres (index et by-hash)" \
    "$(jq -r '[.layers | group_by(.digest)[] | select(length == 2)] | length' "$x/pf/layout/blobs/sha256/${a#sha256:}")" 2
  rm -rf "$x/pf2"; mkdir -p "$x/pf2"; cp -a "$x/pf/fermeture" "$x/pf2/"
  sed "s#$x/pf/#$x/pf2/#g" "$x/pf/publier.sh" > "$x/pf2/publier.sh"
  attendu "seconde poussée, autre copie : même digest" "$(sh "$x/pf2/publier.sh" 2>&1 | tail -1)" "$a"
}

signer_tache() { # nom : signature versionnée dans fermetures/, bundle (tag s4b), liste revue de la 08 (comme s4a.sh)
  local n=$1 v=$F/$1.signee.yaml r
  tkn task sign "$T/$n.yaml" -K "$S/taches.key" -f "$T/$n-signee.yaml" > /dev/null
  if [ -n "${SIGNER:-}" ] && ! { [ -s "$v" ] && cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v"); }; then
    cp "$T/$n-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans fermetures/$n.signee.yaml"
  fi
  [ -s "$v" ] || { echo "KO   signature versionnée absente : SIGNER=1, puis revue de la liste" >&2; exit 1; }
  cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") \
    && echo "OK   $n : signature versionnée conforme au gabarit rendu, signature exceptée" \
    || { echo "KO   $n : gabarit modifié depuis la signature versionnée" >&2; exit 1; }
  r=$REG/tekton/tasks/$n@$(bundle "$v" "tekton/tasks/$n" s4b)
  echo "$r" > "$T/$n.ref"
  if liste_revue "$r"; then echo "OK   $n dans la liste revue : $r"
  elif [ -n "${SIGNER:-}" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml (08) après revue du propriétaire : $r"
  else echo "KO   $n absente de la liste revue : $r" >&2; exit 1; fi
}
signer_pipeline() { # nom
  tkn pipeline sign "$T/$1.yaml" -K "$S/taches.key" -f "$T/$1-signee.yaml" > /dev/null
  echo "$REG/tekton/pipelines/$1@$(bundle "$T/$1-signee.yaml" "tekton/pipelines/$1" s4b)" | tee "$T/$1.ref"
}

etape_taches_deb() {
  local pd pf
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente" >&2; exit 1; }
  pd=$(ref_revue prefetch-deb 4dac0609); pf=$(ref_revue publier-fermeture 7fa92ad3)
  echo "tâches de la liste revue : $pd ; $pf"
  rm -rf "$T/packaging"
  oras pull --no-tty --ca-file "$P/ca-poc.crt" -o "$T/packaging" "${PACKAGING/$REG/$REG_HOTE}" > /dev/null
  echo "artefact de packaging relu dans Zot (lecture anonyme) : $PACKAGING"
  liste "$T/packaging"
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh), compte poc-ecriture
  echo "## pipeline prefetch-deb-sample-app (tkn $(tkn version --component client))"
  rendre_deb "$pd" "$pf"
  signer_pipeline prefetch-deb-sample-app
}

etape_taches_sources() {
  local pf
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente" >&2; exit 1; }
  pf=$(ref_revue publier-fermeture 7fa92ad3)
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"
  echo "## prefetch-gomod v2 (tkn $(tkn version --component client))"
  remplacer "$F/prefetch-gomod.yaml" "$T/prefetch-gomod.yaml" "PREFETCH=$PREFETCH_IMAGE"
  signer_tache prefetch-gomod
  [ -z "${SIGNER:-}" ] || { echo "SIGNER : pipeline non signée tant que la liste revue n'a pas été acceptée"; return 0; }
  [ "$(cut -d@ -f2 "$T/prefetch-gomod.ref")" != "sha256:5e7e5662e6e9bdc306e30b41300f1253e52c3cc5f5323d61380d4d265111cd0c" ] \
    && echo "OK   v2 distincte de la version 1 de la voie image (5e7e5662)" || { echo "KO   même digest que la version 1" >&2; exit 1; }
  echo "## pipeline prefetch-sources-sample-app"
  rendre_sources "$(cat "$T/prefetch-gomod.ref")" "$pf"
  signer_pipeline prefetch-sources-sample-app
}

pr_json() { # nom pipeline [commit] : PipelineRun, podTemplate du gabarit sample-app (comme s4a.sh), sans Kata
  jq -n --arg n "$1" --arg p "$2" --arg b "$(cat "$T/$2.ref")" --arg c "${3:-}" --arg u "$DEPOT_GIT" '
    {nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}}} as $z
    | {apiVersion: "tekton.dev/v1", kind: "PipelineRun", metadata: {name: $n, namespace: "builds"},
      spec: ({pipelineRef: {resolver: "bundles", params: [{name: "bundle", value: $b}, {name: "name", value: $p}, {name: "kind", value: "pipeline"}]},
        workspaces: [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "1Gi"}}}}}],
        taskRunTemplate: {serviceAccountName: "build", podTemplate: $z}}
        + (if $c == "" then {} else {params: [{name: "commit", value: $c}, {name: "depot", value: $u}]} end))}' > "$T/pr-$1.json"
}
fin_pr() { # nom : attend la fin (3600 s) ; « statut|raison|message »
  local st=""
  for _ in $(seq 1800); do
    st=$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' < /dev/null)
    [ -n "$st" ] && [ "$st" != Unknown ] && break; sleep 2
  done
  kubectl get pipelinerun -n builds "$1" -o json < /dev/null | jq -r '.status.conditions[] | select(.type == "Succeeded") | "\(.status)|\(.reason)|\(.message | gsub("\n"; " ") | .[0:300])"'
}
executer() { # préfixe pipeline [commit] : deux PipelineRuns l'un après l'autre ; digests dans $T/<préfixe>-<i>.digest
  local i pr r t p d
  [ -s "$T/$2.ref" ] || { echo "KO   pipeline $2 absente (étape taches)" >&2; exit 1; }
  for i in 1 2; do
    pr=s4b-$1-$i
    pr_json "$pr" "$2" "${3:-}"; purger_pr "$pr"
    kubectl create -f "$T/pr-$pr.json" < /dev/null > /dev/null
    echo "## $pr créé à $(date -u +%H:%M:%S) ($(cat "$T/$2.ref"))"
    r=$(fin_pr "$pr")
    for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
      p=$(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.podName}' < /dev/null)
      kubectl logs -n builds "$p" --all-containers < /dev/null 2>&1 | grep -viE 'jeton|token' > "$T/$t.log" || true
      echo "### TaskRun $t ($(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.conditions[0].reason}' < /dev/null)), pod $p sur $(
        kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName « {.spec.runtimeClassName} », tekton.dev/task {.metadata.labels.tekton\.dev/task}' < /dev/null 2> /dev/null)"
      grep -vE '^\s*$' "$T/$t.log" | grep -vE 'INFO (Downloading|Retrieving)' | tail -n 12 | cut -c1-220 | sed 's/^/     /'
    done
    attendu "PipelineRun $pr" "$(cut -d'|' -f1,2 <<< "$r")" "True|Succeeded"
    d=$(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
    echo "$d" > "$T/$1-$i.digest"
    echo "fermeture publiée : $(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null | jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value')@$d"
    attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
  done
  attendu "deux exécutions, même fermeture" "$(cat "$T/$1-2.digest")" "$(cat "$T/$1-1.digest")"
}
etape_deb() { executer deb prefetch-deb-sample-app; }
etape_sources() { executer sources prefetch-sources-sample-app "$COMMIT"; }

etape_comparaison() {
  local c=$T/comparaison d
  rm -rf "$c"; mkdir -p "$c"
  echo "## fermeture deb"
  d=$(cat "$T/deb-1.digest")
  oras pull --no-tty --ca-file "$P/ca-poc.crt" -o "$c/deb" "${DEPOT_DEB/$REG/$REG_HOTE}@$d" > /dev/null
  attendu "fichiers (162 .deb, InRelease, 2 index, 2 copies by-hash)" "$(find "$c/deb" -type f | wc -l) $(find "$c/deb/miroir/pool" -type f -name '*.deb' | wc -l)" "167 162"
  attendu "InRelease" "$(sha256sum < "$c/deb/miroir/dists/trixie/InRelease" | cut -c1-64)" "$INRELEASE"
  for a in main/binary-amd64/Packages.xz main/i18n/Translation-en.xz; do
    attendu "$a selon l'InRelease (sha256 taille)" "$(sha256sum < "$c/deb/miroir/dists/trixie/$a" | cut -c1-64) $(stat -c %s "$c/deb/miroir/dists/trixie/$a")" \
      "$(awk -v f="$a" '/^SHA256:/ {s = 1; next} /^[^ ]/ {s = 0} s && $3 == f {print $1, $2}' "$c/deb/miroir/dists/trixie/InRelease")"
    attendu "$a : copie by-hash" "$(ls "$c/deb/miroir/dists/trixie/${a%/*}/by-hash/SHA256")" "$(sha256sum < "$c/deb/miroir/dists/trixie/$a" | cut -c1-64)"
  done
  attendu "pool égal à la liste (sha256 taille chemin), octets" \
    "$(cd "$c/deb/miroir" && find pool -type f | sort | while read -r f; do echo "$(sha256sum < "$f" | cut -c1-64) $(stat -c %s "$f") $f"; done | sha256sum | cut -c1-64) $(find "$c/deb/miroir/pool" -type f -printf '%s\n' | awk '{s += $1} END {print s}')" \
    "$(sort -k3 "$T/liste.txt" | sha256sum | cut -c1-64) 193978008"
  echo "## fermeture applicative (sources)"
  d=$(cat "$T/sources-1.digest")
  oras pull --no-tty --ca-file "$P/ca-poc.crt" -o "$c/sources" "${DEPOT_SOURCES/$REG/$REG_HOTE}@$d" > /dev/null
  (cd "$c/sources" && find . -type f -printf '%P\n' | sort | while read -r f; do echo "     $(sha256sum < "$f" | cut -c1-16) $(stat -c %s "$f") $f"; done)
  attendu "fichiers (6 gomod, 1 npm, .build-config.json)" "$(find "$c/sources" -type f | wc -l) $(find "$c/sources/deps/gomod" -type f | wc -l) $(find "$c/sources/deps/npm" -type f | wc -l)" "8 6 1"
  attendu "fichiers gomod égaux à ceux de F2 (même commit)" \
    "$(cd "$c/sources" && find deps/gomod -type f | sort | xargs sha256sum | sha256sum | cut -c1-64)" "$(cd "$F2" && find deps/gomod -type f | sort | xargs sha256sum | sha256sum | cut -c1-64)"
  attendu "archive npm : sha512 égal à l'integrity du lockfile" \
    "sha512-$(openssl dgst -sha512 -binary "$c/sources/deps/npm/marked-16.4.1.tgz" | base64 -w0)" \
    "$(jq -r '.packages["node_modules/marked"].integrity' "$repo/poc/sample-app/web/package-lock.json")"
  echo "## .build-config.json : fermeture applicative et F2 (gomod seul)"
  diff <(jq -S . "$F2/.build-config.json") <(jq -S . "$c/sources/.build-config.json") | sed 's/^/     /' || true
}

etape_provenance() {
  local f i d uid pr
  for f in deb sources; do
    d=$(cat "$T/$f-1.digest"); pr=s4b-$f-1
    [ $f = deb ] && i=$DEPOT_DEB || i=$DEPOT_SOURCES
    uid=$(kubectl get pipelinerun -n builds "$pr" -o jsonpath='{.metadata.uid}' < /dev/null)
    echo "## provenance de $pr"
    cosign verify-attestation --key "$here/resultats/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true \
      --registry-cacert "$P/ca-poc.crt" "${i/$REG/$REG_HOTE}@$d" > "$T/att-$f.json" 2> "$T/cosign.err" || { cat "$T/cosign.err" >&2; exit 1; }
    echo "OK   cosign verify-attestation : $(wc -l < "$T/att-$f.json") enveloppe(s) valide(s) sur $d"
    jq -c --arg u "$uid" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$T/att-$f.json" > "$T/prov-$f.json"
    attendu "enveloppes du PipelineRun $pr" "$(wc -l < "$T/prov-$f.json")" 1
    jq -r '"buildType : \(.predicate.buildDefinition.buildType)", "resolvedDependencies :",
      (.predicate.buildDefinition.resolvedDependencies[] | "  \(.name // "-") \(.uri // "-") \(.digest // {} | to_entries | map(.key + ":" + .value) | join(","))")' "$T/prov-$f.json"
    attendu "sujet" "$(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$T/prov-$f.json")" "$i@$d"
    attendu "buildType" "$(jq -r '.predicate.buildDefinition.buildType' "$T/prov-$f.json")" https://tekton.dev/chains/v2/slsa-tekton
    taches() { jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
      | (.spec.taskRef.params // [] | map(select(.name == "name")) | .[0].value) + " " + (.spec.params | tostring)' "$T/prov-$f.json"; }
    attendu "tâches dans la provenance" "$(taches | cut -d' ' -f1 | sort | paste -sd' ')" "$([ $f = deb ] && echo prefetch-deb || echo prefetch-gomod) publier-fermeture"
    if [ $f = deb ]; then
      attendu "InRelease" "$(jq -r --arg u "$INSTANTANE/dists/trixie/InRelease" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | .digest.sha256' "$T/prov-$f.json")" "$INRELEASE"
      attendu "paramètre liste du TaskRun prefetch-deb, égal à la liste du verrou" \
        "$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
          | select(.spec.taskRef.params[]? | .name == "name" and .value == "prefetch-deb") | .spec.params[] | select(.name == "liste") | .value' "$T/prov-$f.json" | sed '/^$/d' | sha256sum | cut -c1-64)" \
        "$(sha256sum < "$T/liste.txt" | cut -c1-64)"
    else
      attendu "source" "$(jq -r --arg u "git+$DEPOT_GIT" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha1:" + .digest.sha1' "$T/prov-$f.json")" "sha1:$COMMIT"
      attendu "image d'outils du prefetch" "$(jq -r --arg u "oci://${PREFETCH_IMAGE%@*}" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha256:" + .digest.sha256' "$T/prov-$f.json" | sort -u)" "${PREFETCH_IMAGE#*@}"
      attendu "tâche prefetch-gomod v2 (bundle)" "$(jq -r --arg u "$REG/tekton/tasks/prefetch-gomod" '.predicate.buildDefinition.resolvedDependencies[]
        | select(.name == "pipelineTask" and .uri == $u) | "sha256:" + .digest.sha256' "$T/prov-$f.json")" "$(cut -d@ -f2 "$T/prefetch-gomod.ref")"
      attendu "paramètre paquets du TaskRun prefetch-gomod" \
        "$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
          | select(.spec.taskRef.params[]? | .name == "name" and .value == "prefetch-gomod") | .spec.params[] | select(.name == "paquets") | .value' "$T/prov-$f.json")" "$PAQUETS"
    fi
  done
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$T/autre.pub" 2> /dev/null
  refus "provenance vérifiée avec une autre clé" "no matching attestations|invalid signature|signature" \
    cosign verify-attestation --key "$T/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "${DEPOT_DEB/$REG/$REG_HOTE}@$(cat "$T/deb-1.digest")"
}

lancer s4b S4b "$@"
