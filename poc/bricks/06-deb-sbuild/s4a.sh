#!/usr/bin/env bash
# Brique 06, jalon S4a (décision du propriétaire du 10/11/2026, 22:52:55 UTC) : pipeline de la plateforme qui construit l'image de
# build sbuild-debian13 et la publie dans builds/builders/sbuild-debian13. Prédictions : resultats/s4a-predictions.md, écrites et
# commitées avant ce script et avant toute exécution. Chaque étape qui touche Zot ou le cluster attend un accord nommé.
#   prealables  hôte seul : liste builder/paquets.txt rapprochée du Packages contrôlé en S1 ; paquets de l'amorce (lignes
#               « deb amorce » de s1c-racine.log) retrouvés dans la liste ; gabarits rendus sans variable restante (A1)
#   taches      écritures dans Zot (poc-ecriture) : prefetch-deb et construire-builder signées par tkn, comparées à leur
#               signature versionnée (SIGNER=1 pour la faire), bundles, digests exigés dans la liste revue de la 08 ; pipeline
#               builder-sbuild signée et publiée à chaque passage (A2)
#   reseau      cluster : NetworkPolicy builder-sans-sortie ; invariants (une seule politique sélectionne construire-builder, en
#               entrée et en sortie ; aucune NetworkPolicy de builds n'autorise de trafic ; aucune CiliumNetworkPolicy de builds
#               n'autorise de trafic à construire-builder) (A3)
#   pipeline    cluster et Zot : deux PipelineRuns l'un après l'autre (s4a-builder-1, s4a-builder-2) ; journaux des TaskRuns
#               (lignes filtrées), runtime et nœud des pods, digest publié, signature de Chains (A4 à A13)
#   provenance  lecture dans Zot : provenance vérifiée par cosign (clé de Chains), sujet, buildType, amorce, InRelease et bundles
#               dans resolvedDependencies ; autre clé refusée (A15)
#   comparaison lecture dans Zot, puis hôte : manifeste, configuration et couches tirées par digest ; digest des couches égal à leur
#               sha256, diff_ids ; dpkg/status de la racine et du chroot comparé à ceux de S1 et S2 ; versions, compte
#               constructeur, subuid et subgid (A8, A14, A16, A17)
# Rien n'est supprimé dans Zot (pas de droit de suppression) : dépôts builds/builders/sbuild-debian13, tekton/tasks/prefetch-deb,
# tekton/tasks/construire-builder et tekton/pipelines/builder-sbuild définitifs.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4a.sh <étape>…   (journal : resultats/s4a-<étape>.log)
set -euo pipefail
export LC_ALL=C

h06=$(cd "$(dirname "$0")" && pwd)
here=$h06/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, OUTILS, refus, purger_pr, bundle, listee, signe, auth_zot, lancer
R=$h06/resultats
B=$h06/builder
T=$W/s4a-06
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets, même en cas d'échec
umask 022

SNAP=20261105T000000Z
INSTANTANE=http://snapshot.debian.org/archive/debian/$SNAP
INRELEASE=0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675   # s1-prealables.log : signataires vérifiés
SDE=1789199741   # Date de l'InRelease (Sat, 12 Sep 2026 07:55:41 UTC), comme s1.sh et s2.sh
INCLURE=sbuild=0.89.3+deb13u4,libsbuild-perl=0.89.3+deb13u4,mmdebstrap=1.5.7-1+deb13u1,uidmap=1:4.17.4-2,iproute2=6.15.0-1   # s1.sh
AMORCE=$REG/amont/library/debian@sha256:7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392   # s1.sh
PUBLIER=$REG/tekton/tasks/publier-image@sha256:d21931f3   # préfixe : digest complet relu dans la liste revue (etape_taches)
IMAGE=$REG/builds/builders/sbuild-debian13
PACKAGES=$W/s1-06/Packages   # égal à xz -dc hote/Packages.xz, contrôlé par l'InRelease en S1
S1RACINE=$W/s1-06/racine.tar  # f8f221ca…
S2CHROOT=$W/s2-06/chroot.tar  # e0b1f37c…

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
liste_revue() { # bundle (par digest) : présent dans la liste revue de la 08 (même règle que listee de commun.sh)
  awk -v d="oci://${1%@*}:" -v r="${1#*@}" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && $3 == r {t = 1} END {exit !t}' "$here/politique/porte/taches.yml"
}
installes() { # fichier status : « paquet version architecture » des paquets installés, triés
  awk -v RS= '/\nStatus: install ok installed/ {p = v = a = ""; n = split($0, L, "\n")
    for (i = 1; i <= n; i++) { if (L[i] ~ /^Package: /) p = substr(L[i], 10); if (L[i] ~ /^Version: /) v = substr(L[i], 10)
      if (L[i] ~ /^Architecture: /) a = substr(L[i], 15) } print p, v, a}' "$1" | sort
}

rendre() { # gabarits rendus dans $T ; refs des bundles depuis $T/*.ref (ou valeurs factices en prealables)
  local pf=${1:-} cb=${2:-} pu=${3:-}
  awk '{print $4, $5, $6}' "$B/paquets.txt" > "$T/liste.txt"
  sed 's/^/        /' "$T/liste.txt" > "$T/liste-indentee.txt"
  sed -e "s#@AMORCE@#$AMORCE#g" "$B/prefetch-deb.yaml" > "$T/prefetch-deb.yaml"
  sed -e "s#@AMORCE@#$AMORCE#g" "$B/construire-builder.yaml" > "$T/construire-builder.yaml"
  python3 -I - "$B/builder-sbuild.yaml" "$T/builder-sbuild.yaml" "$T/liste-indentee.txt" "$pf" "$cb" "$pu" "$INSTANTANE" \
    "$INRELEASE" "$(tr '\n' ' ' < "$T/amorce.txt" | sed 's/ $//')" "$SDE" "$INCLURE" "$IMAGE" <<'FIN'
import sys
src, dst, liste, pf, cb, pu, inst, inr, amorce, sde, incl, img = sys.argv[1:]
l = open(liste, encoding='utf-8').read().rstrip('\n')
r = []
for ligne in open(src, encoding='utf-8').read().split('\n'):
    if not ligne.lstrip().startswith('#'):   # les commentaires citent les variables : non rendus
        for k, v in (('@LISTE@', l), ('@PREFETCH_DEB@', pf), ('@CONSTRUIRE_BUILDER@', cb), ('@PUBLIER@', pu), ('@INSTANTANE@', inst),
                     ('@INRELEASE@', inr), ('@AMORCE_PAQUETS@', '"' + amorce + '"'), ('@SDE@', sde), ('@INCLURE@', incl), ('@IMAGE@', img)):
            ligne = ligne.replace(k, v)
    r.append(ligne)
open(dst, 'w', encoding='utf-8').write('\n'.join(r))
FIN
  local f
  for f in prefetch-deb construire-builder builder-sbuild; do
    ! grep -n '@[A-Z_]*@' "$T/$f.yaml" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans $f" >&2; exit 1; }
  done
}

etape_prealables() {
  [ -s "$PACKAGES" ] || { echo "KO   Packages de S1 absent : $PACKAGES" >&2; exit 1; }
  attendu "Packages égal à xz -dc Packages.xz" "$(xz -dc "$W/s1-06/hote/Packages.xz" | cmp - "$PACKAGES" && echo égal)" "égal"
  python3 -I - "$PACKAGES" "$B/paquets.txt" <<'FIN'
import sys
idx = {}
b = {}
def ranger():
    if 'Package' in b:
        idx[(b['Package'], b['Version'], b.get('Architecture'))] = (b['SHA256'], b['Size'], b['Filename'])
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    line = line.rstrip('\n')
    if not line:
        ranger(); b = {}; continue
    if line[0] in ' \t': continue
    k, _, v = line.partition(': ')
    b[k] = v
ranger()
n = ko = 0
for l in open(sys.argv[2], encoding='utf-8'):
    p, v, a, s, z, f = l.split()
    n += 1
    if idx.get((p, v, a)) != (s, z, f):
        ko += 1; print(f'KO   {p} {v} {a} absent ou différent dans Packages')
print(f'{"OK  " if ko == 0 else "KO  "} liste rapprochée de Packages : {n} paquets, {ko} écart(s)')
sys.exit(1 if ko else 0)
FIN
  attendu "paquets dans la liste" "$(grep -c . "$B/paquets.txt")" 199
  attendu "octets de la liste" "$(awk '{s += $5} END {print s}' "$B/paquets.txt")" 133065812
  sed -n 's/^ *deb amorce \S* \([0-9a-f]\{64\}\)$/\1/p' "$R/s1c-racine.log" | while read -r s; do
    awk -v s="$s" '$4 == s {print $6}' "$B/paquets.txt"
  done > "$T/amorce.txt"
  attendu "paquets de l'amorce retrouvés dans la liste" "$(grep -c . "$T/amorce.txt")" 20
  rendre "$REG/tekton/tasks/prefetch-deb@sha256:$(printf '0%.0s' {1..64})" "$REG/tekton/tasks/construire-builder@sha256:$(printf '0%.0s' {1..64})" \
    "$PUBLIER"
  echo "OK   gabarits rendus sans variable restante (refs factices) : $(wc -c < "$T/builder-sbuild.yaml") octets pour la pipeline"
  essais_hote
  for f in prefetch-deb construire-builder builder-sbuild; do
    attendu "$f : YAML lisible par yq, nom" "$(yq -e '.metadata.name' "$T/$f.yaml")" "$f"
  done
  attendu "liste rendue dans la pipeline (prefetch, puis construire)" \
    "$(yq '.spec.tasks[0].params[2].value' "$T/builder-sbuild.yaml" | grep -c .) $(yq '.spec.tasks[1].params[2].value' "$T/builder-sbuild.yaml" | grep -c .)" "199 199"
  attendu "liste rendue identique à la liste" "$(yq '.spec.tasks[0].params[2].value' "$T/builder-sbuild.yaml" | sed '/^$/d' | cmp - "$T/liste.txt" && echo identique)" identique
  yq '.spec.tasks[1].params[] | select(.name != "liste") | "     " + .name + " = " + (.value | tostring)' "$T/builder-sbuild.yaml" | cut -c1-200
}

essais_hote() { # hôte seul (ajouté le 10/11/2026 après le second passage) : syntaxe des scripts de tâche, arguments de mmdebstrap
  # (fonction mm avec un mmdebstrap factice), section du layout sur deux archives factices, lue ensuite comme publier-image
  local x=$T/essais d
  rm -rf "$x"; mkdir -p "$x/w" "$x/o" "$x/e"
  yq '.spec.steps[0].script' "$T/construire-builder.yaml" | sed -e "s#\$(workspaces.entrees.path)#$x/e#g" -e "s#\$(workspaces.sortie.path)#$x/o#g" \
    -e "s#\$(results.DIGEST_CONSTRUIT.path)#$x/digest#g" > "$x/construire.sh"
  yq '.spec.steps[0].script' "$T/prefetch-deb.yaml" | sed -e "s#\$(workspaces.sortie.path)#$x/o#g" \
    -e "s#\$(results.INSTANTANE_ARTIFACT_INPUTS.path)#$x/res#g" > "$x/prefetch.sh"
  attendu "construire-builder : syntaxe bash du script" "$(bash -n "$x/construire.sh" 2>&1 && echo OK)" OK
  attendu "prefetch-deb : syntaxe sh du script" "$(sh -n "$x/prefetch.sh" 2>&1 && echo OK)" OK
  attendu "construire-builder : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/construire.sh" || true)" 0
  # mm avec un mmdebstrap factice : un argument par ligne
  { echo 'set -euo pipefail'; echo "e=$x/e"; echo "INSTANTANE=$INSTANTANE"; echo "INCLURE=$INCLURE"
    echo 'mmdebstrap() { local a n=x; for a; do case $a in *.tar) n=${a##*/} ;; esac; done; printf "%s\n" "$@" > "$W_/args-$n"; : > "${@: -2:1}"; }'
    echo 'pic() { :; }'
    sed -n '/^src=/,/^finale=/p' "$x/construire.sh"
    sed -n '/^mm() {/,/^}/p' "$x/construire.sh"
    sed -n '/^mm racine/,/^mm chroot buildd/p' "$x/construire.sh"
  } | sed "s#/w/#@W@/#g; s#@W@#$x/w#g" > "$x/mm.sh"
  (cd "$x" && W_=$x/w bash "$x/mm.sh" > "$x/mm.out" 2>&1) || { cat "$x/mm.out" >&2; echo "KO   fonction mm" >&2; exit 1; }
  for d in racine chroot; do
    [ -s "$x/w/args-$d.tar" ] || { echo "KO   arguments de mmdebstrap ($d) non relevés" >&2; exit 1; }
    echo "## arguments de mmdebstrap ($d)"; sed 's/^/     /' "$x/w/args-$d.tar"
  done
  f=$x/w/args-racine.tar
  attendu "racine : --hook-dir avant les crochets" "$(grep -n -- '--hook-dir\|--customize-hook' "$f" | head -1 | cut -d: -f2- | cut -c1-10)" "--hook-dir"
  attendu "racine : retrait des points de montage en dernier crochet" "$(grep -- '--customize-hook' "$f" | tail -1 | grep -c "rmdir -p '${x#/}/e'" || true)" 1
  attendu "racine : crochet sources.list" "$(grep -c -- "--customize-hook=echo 'deb \[check-valid-until=no\] $INSTANTANE trixie main' > \"\$1/etc/apt/sources.list\"" "$f")" 1
  attendu "racine : source du miroir" "$(tail -1 "$f")" "deb [check-valid-until=no] file://$x/e trixie main"
  # section du layout sur deux archives factices
  mkdir -p "$x/fx/r" "$x/fx/c"; echo racine > "$x/fx/r/a"; echo chroot > "$x/fx/c/b"
  tar -C "$x/fx/r" -cf "$x/w/racine.tar" a; tar -C "$x/fx/c" -cf "$x/w/chroot.tar" b
  local r1; r1=$(sha256sum < "$x/w/racine.tar" | cut -c1-64)
  : > "$x/pic.txt"
  { echo 'set -euo pipefail'; echo "o=$x/o"; echo 'pic() { :; }'; echo 'sleep 120 & ech=$!'
    sed -n '/^c=\$(sha256sum < \/w\/chroot.tar/,/^printf .sha256:%s/p' "$x/construire.sh"
  } | sed "s#/tmp/pic.txt#$x/pic.txt#g; s#/w/#@W@/#g; s#/w\b#@W@#g; s#@W@#$x/w#g" > "$x/layout.sh"
  bash "$x/layout.sh" > "$x/layout.out" 2>&1 || { cat "$x/layout.out" >&2; echo "KO   section du layout" >&2; exit 1; }
  sed 's/^/     /' "$x/layout.out"
  mkdir -p "$x/lu"; tar -xf "$x/o/image.tar" -C "$x/lu"
  d=$(sed -n 's/.*"digest": *"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' "$x/lu/index.json")   # sed de publier-image
  attendu "index.json lu comme publier-image : une ligne, égale au résultat" "$(wc -l <<< "$d") $d" "1 $(cat "$x/digest")"
  for b in "$x"/lu/blobs/sha256/*; do [ "$(sha256sum < "$b" | cut -c1-64)" = "${b##*/}" ] || { echo "KO   blob ${b##*/}" >&2; exit 1; }; done
  echo "OK   chaque blob a pour nom son sha256 ($(ls "$x/lu/blobs/sha256" | wc -l) blobs)"
  m=$x/lu/blobs/sha256/${d#sha256:}
  attendu "manifeste et configuration lisibles par jq" "$(jq -e . "$m" > /dev/null && jq -e . "$x/lu/blobs/sha256/$(jq -r '.config.digest' "$m" | cut -d: -f2)" > /dev/null && echo oui)" oui
  attendu "diff_ids égaux aux digests des couches" "$(jq -c '.rootfs.diff_ids' "$x/lu/blobs/sha256/$(jq -r '.config.digest' "$m" | cut -d: -f2)")" "$(jq -c '[.layers[].digest]' "$m")"
  attendu "tailles exactes" "$(jq -r '[.config, .layers[]] | map((.size | tostring) + " " + .digest) | .[]' "$m" | while read -r s h; do [ "$(stat -c %s "$x/lu/blobs/sha256/${h#sha256:}")" = "$s" ] || echo x; done | grep -c x || true)" 0
  attendu "couche 1 = archive racine factice, telle quelle" "$(jq -r '.layers[0].digest' "$m")" "sha256:$r1"
  attendu "couche 2 : chroot sous opt/sbuild/trixie-amd64.tar" "$(tar -tf "$x/lu/blobs/sha256/$(jq -r '.layers[1].digest' "$m" | cut -d: -f2)" | grep -c '^opt/sbuild/trixie-amd64.tar$')" 1
}

signer_tache() { # nom : signature versionnée dans builder/, bundle, liste revue de la 08
  local n=$1 v=$B/$1.signee.yaml r
  tkn task sign "$T/$n.yaml" -K "$S/taches.key" -f "$T/$n-signee.yaml" > /dev/null
  # SIGNER=1 ne re-signe que si le gabarit rendu diffère de la signature versionnée (corrigé le 10/11/2026 à 23:18 UTC : la relance
  # de 23:17:20 UTC avait re-signé prefetch-deb inchangée, nouveau digest 9fa81ae9 inutilisé, signature versionnée restaurée)
  if [ -n "${SIGNER:-}" ] && ! { [ -s "$v" ] && cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v"); }; then
    cp "$T/$n-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans builder/$n.signee.yaml"
  fi
  [ -s "$v" ] || { echo "KO   signature versionnée absente : SIGNER=1, puis revue de la liste" >&2; exit 1; }
  cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") \
    && echo "OK   $n : signature versionnée conforme au gabarit rendu, signature exceptée" \
    || { echo "KO   $n : gabarit modifié depuis la signature versionnée" >&2; exit 1; }
  r=$REG/tekton/tasks/$n@$(bundle "$v" "tekton/tasks/$n" s4a)
  echo "$r" > "$T/$n.ref"
  if liste_revue "$r"; then echo "OK   $n dans la liste revue : $r"
  elif [ -n "${SIGNER:-}" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml (08) après revue du propriétaire : $r"
  else echo "KO   $n absente de la liste revue : $r" >&2; exit 1; fi
}

etape_taches() {
  local pu
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente" >&2; exit 1; }
  [ -s "$T/amorce.txt" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  pu=$(awk -v d="oci://$REG/tekton/tasks/publier-image:" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && index($3, "sha256:d21931f3") == 1 {print $3}' "$here/politique/porte/taches.yml" | head -1)
  [ -n "$pu" ] || { echo "KO   publier-image d21931f3 absente de la liste revue" >&2; exit 1; }
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh), compte poc-ecriture
  echo "## tâches (tkn $(tkn version --component client))"
  rendre "-" "-" "-"
  signer_tache prefetch-deb
  signer_tache construire-builder
  [ -z "${SIGNER:-}" ] || { echo "SIGNER : pipeline non signée tant que la liste revue n'a pas été acceptée"; return 0; }
  rendre "$(cat "$T/prefetch-deb.ref")" "$(cat "$T/construire-builder.ref")" "$REG/tekton/tasks/publier-image@$pu"
  tkn pipeline sign "$T/builder-sbuild.yaml" -K "$S/taches.key" -f "$T/builder-sbuild-signee.yaml" > /dev/null
  echo "$REG/tekton/pipelines/builder-sbuild@$(bundle "$T/builder-sbuild-signee.yaml" tekton/pipelines/builder-sbuild s4a)" | tee "$T/pipeline.ref"
}

etape_reseau() {
  kubectl apply -f "$B/builder-sans-sortie.yaml" < /dev/null > /dev/null
  kubectl get netpol -n builds -o json < /dev/null > "$T/netpol.json"
  echo "NetworkPolicy de builds : $(jq -r '[.items[].metadata.name] | join(", ")' "$T/netpol.json")"
  attendu "politiques qui sélectionnent construire-builder, sans entrée ni sortie" \
    "$(jq -r '[.items[] | select(.spec.podSelector.matchLabels["tekton.dev/task"] == "construire-builder" and (.spec.policyTypes | sort) == ["Egress", "Ingress"])] | length' "$T/netpol.json")" 1
  attendu "politiques de builds qui autorisent du trafic" \
    "$(jq -r '[.items[] | select(((.spec.egress // []) | length) > 0 or ((.spec.ingress // []) | length) > 0)] | length' "$T/netpol.json")" 0
  kubectl get ciliumnetworkpolicy -n builds -o json < /dev/null > "$T/cnp.json"
  attendu "CiliumNetworkPolicy de builds qui sélectionnent construire-builder et autorisent du trafic" \
    "$(jq -r -L "$here" 'include "selecteurs"; [.items[] | .kind = "CiliumNetworkPolicy" | select(selectionne({"tekton.dev/task": "construire-builder"}) and autorise) | nom] | join(", ")' "$T/cnp.json")" ""
}

pr_json() { # nom : PipelineRun de builder-sbuild, podTemplate du gabarit sample-app, Kata pour la seule tâche construire
  jq -n --arg n "$1" --arg b "$(cat "$T/pipeline.ref")" '
    {zone: {nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}}}} as $g
    | {apiVersion: "tekton.dev/v1", kind: "PipelineRun", metadata: {name: $n, namespace: "builds"},
      spec: {pipelineRef: {resolver: "bundles", params: [{name: "bundle", value: $b}, {name: "name", value: "builder-sbuild"}, {name: "kind", value: "pipeline"}]},
        workspaces: [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "2Gi"}}}}}],
        taskRunTemplate: {serviceAccountName: "build", podTemplate: $g.zone},
        taskRunSpecs: [{pipelineTaskName: "construire", podTemplate: ($g.zone + {runtimeClassName: "kata"})}]}}' > "$T/pr-$1.json"
}
fin_pr() { # nom : attend la fin (3600 s) ; « statut|raison|message »
  local st=""
  for _ in $(seq 1800); do
    st=$(kubectl get pipelinerun -n builds "$1" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' < /dev/null)
    [ -n "$st" ] && [ "$st" != Unknown ] && break; sleep 2
  done
  kubectl get pipelinerun -n builds "$1" -o json < /dev/null | jq -r '.status.conditions[] | select(.type == "Succeeded") | "\(.status)|\(.reason)|\(.message | gsub("\n"; " ") | .[0:300])"'
}

etape_pipeline() {
  local i pr r t p d
  [ -s "$T/pipeline.ref" ] || { echo "KO   pipeline absente (étape taches)" >&2; exit 1; }
  for i in 1 2; do
    pr=s4a-builder-$i
    pr_json "$pr"; purger_pr "$pr"
    kubectl create -f "$T/pr-$pr.json" < /dev/null > /dev/null
    echo "## $pr créé à $(date -u +%H:%M:%S) ($(cat "$T/pipeline.ref"))"
    r=$(fin_pr "$pr")
    for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
      p=$(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.podName}' < /dev/null)
      kubectl logs -n builds "$p" --all-containers < /dev/null 2>&1 | grep -viE 'jeton|token' > "$T/$t.log" || true
      echo "### TaskRun $t ($(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.conditions[0].reason}' < /dev/null)), pod $p sur $(
        kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName {.spec.runtimeClassName}, tekton.dev/task {.metadata.labels.tekton\.dev/task}' < /dev/null 2> /dev/null)"
      grep -vE '^\s*$' "$T/$t.log" | tail -n 16 | sed 's/^/     /'
      case $(kubectl get pod -n builds "$p" -o jsonpath='{.metadata.labels.tekton\.dev/task}' < /dev/null) in
        construire-builder) attendu "A12 $t : runtimeClassName" "$(kubectl get pod -n builds "$p" -o jsonpath='{.spec.runtimeClassName}' < /dev/null)" kata ;;
        *) attendu "A12 $t : runtimeClassName" "$(kubectl get pod -n builds "$p" -o jsonpath='{.spec.runtimeClassName}' < /dev/null)" "" ;;
      esac
      attendu "A12 $t : nœud" "$(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}' < /dev/null)" sc-build
    done
    attendu "PipelineRun $pr" "$(cut -d'|' -f1,2 <<< "$r")" "True|Succeeded"
    d=$(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
    echo "$d" > "$T/digest-$i"
    echo "image publiée : $IMAGE@$d"
    attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
  done
  attendu "même digest pour les deux exécutions" "$(cat "$T/digest-2")" "$(cat "$T/digest-1")"
}

etape_provenance() {
  local d uid
  d=$(cat "$T/digest-1"); uid=$(kubectl get pipelinerun -n builds s4a-builder-1 -o jsonpath='{.metadata.uid}' < /dev/null)
  cosign verify-attestation --key "$here/resultats/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true \
    --registry-cacert "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}@$d" > "$T/att.json" 2> "$T/cosign.err" || { cat "$T/cosign.err" >&2; exit 1; }
  echo "OK   cosign verify-attestation : $(wc -l < "$T/att.json") enveloppe(s) valide(s) sur $d"
  jq -c --arg u "$uid" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$T/att.json" > "$T/prov.json"
  attendu "enveloppes du PipelineRun s4a-builder-1" "$(wc -l < "$T/prov.json")" 1
  jq -r '"buildType : \(.predicate.buildDefinition.buildType)", "resolvedDependencies :",
    (.predicate.buildDefinition.resolvedDependencies[] | "  \(.name // "-") \(.uri // "-") \(.digest // {} | to_entries | map(.key + ":" + .value) | join(","))")' "$T/prov.json"
  attendu "sujet" "$(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$T/prov.json")" "$IMAGE@$d"
  attendu "buildType" "$(jq -r '.predicate.buildDefinition.buildType' "$T/prov.json")" https://tekton.dev/chains/v2/slsa-tekton
  attendu "amorce" "$(jq -r --arg u "oci://${AMORCE%@*}" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json" | sort -u)" "${AMORCE#*@}"
  attendu "InRelease" "$(jq -r --arg u "$INSTANTANE/dists/trixie/InRelease" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | .digest.sha256' "$T/prov.json")" "$INRELEASE"
  for t in prefetch-deb construire-builder; do
    attendu "tâche $t (bundle)" "$(jq -r --arg u "$REG/tekton/tasks/$t" '.predicate.buildDefinition.resolvedDependencies[]
      | select(.name == "pipelineTask" and .uri == $u) | "sha256:" + .digest.sha256' "$T/prov.json")" "$(cut -d@ -f2 "$T/$t.ref")"
  done
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$T/autre.pub" 2> /dev/null
  refus "provenance vérifiée avec une autre clé" "no matching attestations|invalid signature|signature" \
    cosign verify-attestation --key "$T/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}@$d"
}

etape_comparaison() {
  local d c l1 l2 x
  d=$(cat "$T/digest-1"); c=$T/comparaison
  rm -rf "$c"; mkdir -p "$c/racine" "$c/couche2"
  SSL_CERT_FILE=$P/ca-poc.crt crane manifest "${IMAGE/$REG/$REG_HOTE}@$d" > "$c/manifeste.json"
  attendu "digest du manifeste relu" "sha256:$(sha256sum < "$c/manifeste.json" | cut -c1-64)" "$d"
  SSL_CERT_FILE=$P/ca-poc.crt crane config "${IMAGE/$REG/$REG_HOTE}@$d" > "$c/config.json"
  attendu "configuration" "$(jq -c '{architecture, os, env: .config.Env}' "$c/config.json")" '{"architecture":"amd64","os":"linux","env":["PATH=/usr/sbin:/usr/bin:/sbin:/bin","HOME=/w/home"]}'
  attendu "diff_ids égaux aux digests des couches" "$(jq -c '.rootfs.diff_ids' "$c/config.json")" "$(jq -c '[.layers[].digest]' "$c/manifeste.json")"
  l1=$(jq -r '.layers[0].digest' "$c/manifeste.json"); l2=$(jq -r '.layers[1].digest' "$c/manifeste.json")
  SSL_CERT_FILE=$P/ca-poc.crt crane blob "${IMAGE/$REG/$REG_HOTE}@$l1" > "$c/racine.tar"
  SSL_CERT_FILE=$P/ca-poc.crt crane blob "${IMAGE/$REG/$REG_HOTE}@$l2" > "$c/couche2.tar"
  attendu "couche racine : sha256 de l'archive" "sha256:$(sha256sum < "$c/racine.tar" | cut -c1-64)" "$l1"
  attendu "couche du chroot : sha256 de l'archive" "sha256:$(sha256sum < "$c/couche2.tar" | cut -c1-64)" "$l2"
  tar -xf "$c/couche2.tar" -C "$c/couche2" opt/sbuild/trixie-amd64.tar
  attendu "A16 chroot intérieur égal au journal de construire" "$(sha256sum < "$c/couche2/opt/sbuild/trixie-amd64.tar" | cut -c1-64)" \
    "$(sed -n 's/.*chroot intérieur sha256 \([0-9a-f]\{64\}\).*/\1/p' "$T/s4a-builder-1-construire.log" | head -1)"
  for x in racine:"$c/racine.tar":"$S1RACINE" chroot:"$c/couche2/opt/sbuild/trixie-amd64.tar":"$S2CHROOT"; do
    IFS=: read -r n a ref <<< "$x"
    tar -xOf "$a" ./var/lib/dpkg/status > "$c/status-$n"; tar -xOf "$ref" ./var/lib/dpkg/status > "$c/status-$n-ref"
    installes "$c/status-$n" > "$c/installes-$n"; installes "$c/status-$n-ref" > "$c/installes-$n-ref"
    attendu "$n : paquets installés égaux à la référence ($(wc -l < "$c/installes-$n-ref"))" "$(diff "$c/installes-$n-ref" "$c/installes-$n" > "$c/diff-$n" && echo égaux || echo "écarts : $(grep -c '^[<>]' "$c/diff-$n")")" égaux
    echo "$n : hostname « $(tar -xOf "$a" ./etc/hostname) », resolv.conf $(tar -tvf "$a" ./etc/resolv.conf | awk '{print $3}') octets, sources.list « $(tar -xOf "$a" ./etc/apt/sources.list | head -1) », listes d'apt : $(tar -tf "$a" | grep -c '^\./var/lib/apt/lists/[^/]*_' || true)"
    attendu "$n : égalité bit à bit avec la référence (non attendue, A14)" "$(cmp -s "$a" "$ref" && echo égale || echo différente)" différente
  done
  attendu "A17 versions des paquets inclus" "$(grep -E '^(sbuild|libsbuild-perl|mmdebstrap|uidmap|iproute2) ' "$c/installes-racine" | awk '{print $1 "=" $2}' | sort | paste -sd,)" \
    "$(tr ',' '\n' <<< "$INCLURE" | sort | paste -sd,)"
  for x in racine:"$c/racine.tar" chroot:"$c/couche2/opt/sbuild/trixie-amd64.tar"; do
    attendu "${x%%:*} : sans point de montage du miroir (workspace/)" "$(tar -tf "${x#*:}" | grep -c '^\./workspace' || true)" 0
  done
  attendu "compte constructeur" "$(tar -xOf "$c/racine.tar" ./etc/passwd | awk -F: '$1 == "constructeur" {print $3 ":" $4}')" 1000:1000
  attendu "subuid" "$(tar -xOf "$c/racine.tar" ./etc/subuid)" constructeur:100000:65536
  attendu "subgid" "$(tar -xOf "$c/racine.tar" ./etc/subgid)" constructeur:100000:65536
}

lancer s4a S4a "$@"
