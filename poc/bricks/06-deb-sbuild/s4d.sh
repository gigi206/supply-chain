#!/usr/bin/env bash
# Brique 06, jalon S4d1 (décisions du propriétaire du 11/11/2026, 17:54:35 UTC : « Oui, retiens-les ») : pipeline de la plateforme
# sample-app-deb, qui construit le deb de sample-app sous Kata, sans réseau, depuis les deux fermetures de S4b et l'artefact de
# packaging de S4c, et le publie dans builds/sample-app-deb. Prédictions : resultats/s4d-predictions.md, écrites et commitées avant
# toute étape qui touche le cluster ou Zot. Chaque étape qui écrit dans Zot ou le cluster attend un accord nommé.
#   prealables  hôte seul, hors ligne : gabarits rendus (refs factices), lisibles, scripts de tâche sans erreur de syntaxe ;
#               sections de preparer-deb rejouées aussi sous le busybox de l'image de prefetch (layout local) ;
#               sections de preparer-deb jouées sur les copies des fermetures et de l'artefact de packaging tirées en S4b
#               (confrontation au verrou, avec cas altérés ; assemblage sous unshare -rn) et arbre obtenu comparé à l'archive de
#               sources.sh ; sections de construire-deb jouées sur l'hôte : paquet source comparé à celui de sources.sh, layout
#               écrit avec le deb de S3 (0b489d43), d'où le digest attendu de l'artefact ; entrees.tar pour le pod d'essai
#   busybox_outils lecture dans Zot : image d'outils tirée par digest ; confrontation rejouée sous son busybox, avec deux cas
#               altérés
#   reseau      cluster : NetworkPolicy construction-deb-sans-sortie ; invariants (une seule politique sélectionne construire-deb,
#               en entrée et en sortie ; aucune NetworkPolicy de builds n'autorise de trafic ; aucune CiliumNetworkPolicy de builds
#               n'autorise de trafic à construire-deb)
#   essai       cluster (levier e, pod d'essai avant signature) : pod Kata privilégié, image de build de S4a par digest, UID 1000,
#               label tekton.dev/task construire-deb ; entrées de prealables copiées par morceaux de 64 Mio ; script de
#               construire-deb tiré du gabarit rendu (lecture seule des entrées non testée) ; image.tar rapatrié ; pod supprimé
#   taches      écritures dans Zot (poc-ecriture) : preparer-deb et construire-deb signées par tkn, comparées à leur signature
#               versionnée (SIGNER=1 pour la faire, puis revue de la liste de la 08), bundles ; pipeline sample-app-deb signée, bundle
#   pipeline    cluster et Zot : deux PipelineRuns l'un après l'autre (s4d-deb-1, s4d-deb-2) ; journaux des TaskRuns (lignes
#               filtrées), runtime et nœud des pods, digest publié, signature de Chains
#   comparaison lecture dans Zot, puis hôte : artefact copié par digest en layout OCI ; deb extrait de la couche, comparé à celui
#               de S3 ; Installed-Build-Depends du .buildinfo (journal de construire) comparés au verrou
#   provenance  lecture dans Zot : provenance vérifiée par cosign (clé de Chains) ; sujet, buildType, source, entrées déclarées,
#               image de build, tâches ; autre clé refusée
# Rien n'est supprimé dans Zot (pas de droit de suppression) : dépôts tekton/tasks/preparer-deb, tekton/tasks/construire-deb,
# tekton/pipelines/sample-app-deb et builds/sample-app-deb définitifs.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4d.sh <étape>…   (journal : resultats/s4d-<étape>.log)
set -euo pipefail
export LC_ALL=C

h06=$(cd "$(dirname "$0")" && pwd)
here=$h06/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, OUTILS, refus, purger_pr, bundle, signe, auth_zot, lancer
R=$h06/resultats
D=$h06/deb
T=$W/s4d-06
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets, même en cas d'échec
umask 022

PREFETCH_IMAGE=$REG/plateforme/outils-prefetch@sha256:68e0ae705de5a8f993f168d8252b3218d7d3ed76e704cf24d4414006aea7b8cc   # prefetch.sh (03)
OUTILS_IMAGE=$REG/$OUTILS@$OUTILS_DIGEST
BUILDER=$REG/builds/builders/sbuild-debian13@sha256:749d746cc9e1a9cfa8c80feac8ff68eae96bd6752c73ae9e46b304c38ad0c590   # S4a (A13)
FERMETURE_DEB=$REG/builds/fermetures/sample-app-deb@sha256:bb7599a2e1cde30770fdb4405a5f9cce94de5ea5b12c358e512dfbe7d5b9f290       # S4b
FERMETURE_SOURCES=$REG/builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21   # S4b
PACKAGING=$REG/entrees/sample-app/packaging-deb@sha256:c1719b133236f49c7e2492f4b608a8dc421bf812d7f7e438d879a871f61c2e51   # S4c
IMAGE=$REG/builds/sample-app-deb
COMMIT=6391fd437f26696847041be3226bbbf633f55a2f   # construction.sh : main de workspace/sample-app (arbre 30e808ff = poc/sample-app)
DEPOT_GIT=https://sc-stockage.poc.test:3000/workspace/sample-app.git
S4B=$W/s4b-06   # copies tirées par digest en S4b : comparaison/deb (fermeture deb), comparaison/sources (applicative), packaging
PKG=$HOME/.cache/supply-chain-poc/packaging   # archive de sources.sh (S1 à S3) : 07521c1e…
DEB_S3=$W/s3-06/build-1/sample-app_1.0.0-1_amd64.deb
DEB_SHA=0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5   # OBS, S1, S3
GO=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.26.10.linux-amd64/bin   # même version que l'image de prefetch
LISTE_REVUE=$here/politique/porte/taches.yml
LAYOUT_PREFETCH=$HOME/.cache/supply-chain-poc/03/f2/layout   # layout de l'image de prefetch (prefetch.sh image, brique 03), 68e0ae70
BUSYBOX_PREFETCH=49227c027f9b972f929780d60ee486dee5948ea7042cb7ab400690bb104418bc   # bin/busybox de cette image (BusyBox v1.36.1)
FACTICE=sha256:$(printf '0%.0s' {1..64})
LIMITES='{"cpu": "2", "memory": "6Gi"}'
MORCEAU_MIO=64

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
ECARTS=0
mesure() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS=$((ECARTS + 1)); }; }
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
remplacer() { # source destination clé=valeur… : variables @CLE@ remplacées hors des commentaires
  python3 -I - "$@" <<'FIN'
import sys
src, dst, *kv = sys.argv[1:]
paires = [a.split('=', 1) for a in kv]
r = []
for ligne in open(src, encoding='utf-8').read().split('\n'):
    if not ligne.lstrip().startswith('#'):   # les commentaires citent les variables : non rendus
        for k, v in paires:
            ligne = ligne.replace(f'@{k}@', v)
    r.append(ligne)
open(dst, 'w', encoding='utf-8').write('\n'.join(r))
FIN
  ! grep -n '@[A-Z_]*@' "$2" | grep -v '^[0-9]*:#' || { echo "KO   variable non rendue dans ${2##*/}" >&2; exit 1; }
}
rendre_taches() {
  remplacer "$D/preparer-deb.yaml" "$T/preparer-deb.yaml" "PREFETCH=$PREFETCH_IMAGE" "OUTILS=$OUTILS_IMAGE"
  remplacer "$D/construire-deb.yaml" "$T/construire-deb.yaml" "BUILDER=$BUILDER"
}
rendre_pipeline() { # preparer construire publier
  remplacer "$D/sample-app-deb.yaml" "$T/sample-app-deb.yaml" "PREPARER=$1" "CONSTRUIRE=$2" "PUBLIER=$3" \
    "FERMETURE_DEB=$FERMETURE_DEB" "FERMETURE_SOURCES=$FERMETURE_SOURCES" "PACKAGING=$PACKAGING" "IMAGE=$IMAGE"
  attendu "pipeline : subPath des workspaces (preparer, construire, publier)" \
    "$(yq -o=json -I=0 '[.spec.tasks[].workspaces[].subPath]' "$T/sample-app-deb.yaml")" '[null,"entrees","image","image"]'
  attendu "pipeline : entrées fixées par digest" \
    "$(yq '.spec.tasks[0].params[] | select(.name != "depot" and .name != "commit") | .value' "$T/sample-app-deb.yaml" | paste -sd' ')" \
    "$FERMETURE_DEB $FERMETURE_SOURCES $PACKAGING"
}
script_etape() { # fichier-rendu nom-d'étape : script de l'étape
  yq ".spec.steps[] | select(.name == \"$2\") | .script" "$1"
}

entrees_hote() { # répertoire entrees : comme les tirerait l'étape entrees (copies par digest de S4b), avant assemblage
  mkdir -p "$1/src"
  git -C "$repo" archive HEAD:poc/sample-app | tar -x -C "$1/src"
  cp -a "$S4B/comparaison/deb" "$1/fermeture"
  cp -a "$S4B/comparaison/sources/deps" "$1/deps"
  cp -a "$S4B/packaging" "$1/packaging"
}
bb_liens() { # busybox répertoire : un lien par applet vers ce busybox (PATH sans aucun outil de l'hôte)
  local a
  rm -rf "$2"; mkdir -p "$2"; cp "$1" "$2/busybox"; chmod 0755 "$2/busybox"
  for a in $("$2/busybox" --list); do [ "$a" = busybox ] || ln -s busybox "$2/$a"; done
}
modes() { (cd "$1" && find . -printf '%m %y %P\n' | sort); }

etape_prealables() {
  local x=$T/essais e a s
  chmod -R u+w "$x" 2> /dev/null || true   # cache de modules de go en lecture seule
  rm -rf "$x"; mkdir -p "$x/tmp"
  echo "## gabarits rendus (refs factices)"
  rendre_taches
  rendre_pipeline "$REG/tekton/tasks/preparer-deb@$FACTICE" "$REG/tekton/tasks/construire-deb@$FACTICE" "$REG/tekton/tasks/publier-image@$FACTICE"
  for a in preparer-deb construire-deb sample-app-deb; do
    attendu "$a : YAML lisible par yq, nom" "$(yq -e '.metadata.name' "$T/$a.yaml")" "$a"
  done
  attendu "preparer-deb : étapes" "$(yq '[.spec.steps[].name] | join(" ")' "$T/preparer-deb.yaml")" "sources entrees assemblage"
  attendu "construire-deb : image de build, UID, privilégiée" \
    "$(yq '.spec.steps[0] | .image + " " + (.securityContext.runAsUser | tostring) + " " + (.securityContext.privileged | tostring)' "$T/construire-deb.yaml")" "$BUILDER 1000 true"
  # Ajouté le 11/11/2026 après l'échec de s4d-deb-1 (/tmp de l'image de prefetch en 0755, root) : chaque étape de preparer-deb doit
  # avoir /tmp en emptyDir, ou une image dont /tmp est en 1777
  attendu "preparer-deb : emptyDir monté sur /tmp pour toutes les étapes" \
    "$(yq '[.spec.volumes[] | select(.name == "tmp") | has("emptyDir")] + [.spec.stepTemplate.volumeMounts[] | select(.mountPath == "/tmp") | .name] | join(" ")' "$T/preparer-deb.yaml")" "true tmp"
  attendu "construire-deb : workspace entrees en lecture seule" "$(yq '.spec.workspaces[] | select(.name == "entrees") | .readOnly' "$T/construire-deb.yaml")" true
  echo "## syntaxe des scripts"
  for a in sources entrees assemblage; do
    script_etape "$T/preparer-deb.yaml" "$a" > "$x/preparer-$a.sh"
    attendu "preparer-deb $a : syntaxe sh" "$(sh -n "$x/preparer-$a.sh" 2>&1 && echo OK)" OK
  done
  sed -n "/<<'FIN'$/,/^FIN$/p" "$x/preparer-assemblage.sh" | sed '1d;$d' > "$x/marked.py"
  python3 -I -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$x/marked.py" && echo "OK   preparer-deb assemblage : syntaxe Python"
  script_etape "$T/construire-deb.yaml" construire > "$x/construire.sh"
  attendu "construire-deb : syntaxe bash" "$(bash -n "$x/construire.sh" 2>&1 && echo OK)" OK

  echo "## preparer-deb, sur l'hôte : entrées comme les tirerait l'étape entrees (copies par digest de S4b)"
  e=$x/ws/entrees
  attendu "arbre de poc/sample-app (celui du commit $COMMIT)" "$(git -C "$repo" rev-parse HEAD:poc/sample-app)" 30e808ffa327288c656ddda7b6fafe4005234b77
  entrees_hote "$e"
  attendu "debian/rules dans l'artefact tiré (mode perdu par oras)" "$(stat -c %a "$e/packaging/debian/rules")" 644
  # Section de confrontation de l'étape entrees, jouée telle quelle (busybox remplacé par les outils de l'hôte)
  { echo 'set -eu'; echo 'e=$1'
    sed -n '/^# Confrontation de la fermeture deb au verrou/,/^echo "fermeture deb confrontée/p' "$x/preparer-entrees.sh"
  } | sed "s#/tmp/verrou#\$e/../verrou.tmp#g" > "$x/confrontation.sh"
  attendu "section de confrontation extraite (début, boucle, fin)" "$(grep -c '^# Confrontation\|^while read\|^echo "fermeture deb confrontée' "$x/confrontation.sh")" 3
  sh "$x/confrontation.sh" "$e" | sed 's/^/     /'
  cas() { # libellé commande-shell-sur-$c : la confrontation doit refuser
    local c=$x/cas/entrees r
    rm -rf "$x/cas"; mkdir -p "$x/cas"; cp -a "$e" "$c"
    (cd "$c" && eval "$2")
    r=$(sh "$x/confrontation.sh" "$c" 2>&1) && { echo "KO   accepté : $1 : $r" >&2; exit 1; }
    echo "OK   refusé : $1 ($(tail -1 <<< "$r" | cut -c1-110))"
  }
  cas "paquet altéré (un octet)" 'f=fermeture/miroir/pool/main/b/bash/bash_5.2.37-2+b10_amd64.deb; printf x | dd of=$f bs=1 seek=100 conv=notrunc status=none'
  cas "paquet retiré" 'rm fermeture/miroir/pool/main/b/bash/bash_5.2.37-2+b10_amd64.deb'
  cas "paquet en plus dans le pool" 'cp fermeture/miroir/pool/main/b/bash/bash_5.2.37-2+b10_amd64.deb fermeture/miroir/pool/main/b/bash/autre_1_amd64.deb'
  cas "paquet remplacé par un lien" 'f=fermeture/miroir/pool/main/b/bash/bash_5.2.37-2+b10_amd64.deb; mv $f $f.v; ln -s ${f##*/}.v $f'
  cas "chemin du verrou avec .." 'sed -i "1s#pool/main/a/autoconf/#pool/../pool/main/a/autoconf/#" packaging/verrou-deb.txt'
  cas "chemin du verrou hors de pool/" 'sed -i "1s# pool/main/a/autoconf/autoconf_2.72-3.1_all.deb# dists/trixie/InRelease#" packaging/verrou-deb.txt'
  cas "verrou vide" ': > packaging/verrou-deb.txt'
  echo "## preparer-deb, sur l'hôte : étape assemblage jouée sous unshare -rn (go $("$GO/go" version | cut -d' ' -f3))"
  sed -e "s#\$(workspaces.sortie.path)#$x/ws#g" -e "s#/tmp/#$x/tmp/#g" "$x/preparer-assemblage.sh" > "$x/assemblage.sh"
  attendu "assemblage : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/assemblage.sh" || true)" 0
  unshare -rn env -i HOME="$x/tmp" PATH="$GO:$(dirname "$(command -v python3)"):/usr/bin:/bin" sh "$x/assemblage.sh" 2>&1 | sed 's/^/     /'
  [ -d "$e/debian" ] && [ ! -e "$e/deps" ] || { echo "KO   assemblage incomplet" >&2; exit 1; }
  rm -rf "$x/arch"; mkdir -p "$x/arch"; tar -xzf "$PKG/sample-app-1.0.0.tar.gz" -C "$x/arch"
  attendu "archive de sources.sh (S1 à S3)" "$(sha256sum < "$PKG/sample-app-1.0.0.tar.gz" | cut -c1-64)" 07521c1e60cdbed8a29912ad775e52201daf95003f7f54ccee76b3270742d9bb
  attendu "entrees/src égal à l'arbre de l'archive (contenu)" "$(diff -r "$x/arch/sample-app-1.0.0" "$e/src" > "$x/src.diff" && echo égal || echo différent)" égal
  attendu "entrees/debian égal à poc/packaging/debian (contenu)" "$(diff -r "$repo/poc/packaging/debian" "$e/debian" > /dev/null && echo égal || echo différent)" égal
  attendu "entrees/debian : modes" "$(cd "$e/debian" && find . -type f -printf '%m %P\n' | sort | paste -sd,)" "644 changelog,644 control,644 copyright,644 source/format,755 rules"
  attendu "entrees/verrou-deb.txt égal au verrou du dépôt" "$(cmp -s "$e/verrou-deb.txt" "$repo/poc/packaging/verrou-deb.txt" && echo égal || echo différent)" égal
  attendu "entrees : contenu de premier niveau" "$(ls "$e" | paste -sd' ')" "debian fermeture src verrou-deb.txt"

  # Ajouté le 11/11/2026 avant tout lancement (avis du conseiller) : les sections ont tourné sous dash et les outils GNU ; dans la
  # pipeline, elles tournent sous busybox. Rejouées ici avec le busybox de l'image de prefetch (étapes sources et assemblage), seul
  # dans le PATH avec go et python3 ; l'étape entrees, sous le busybox de l'image d'outils, l'est par busybox_outils (lecture Zot).
  echo "## preparer-deb sous le busybox de l'image de prefetch (applets seuls, plus go et python3)"
  a=$(jq -r '.manifests[0].digest' "$LAYOUT_PREFETCH/index.json")
  attendu "layout local de l'image de prefetch" "$a" "${PREFETCH_IMAGE#*@}"
  a=$(jq -r '.layers[].digest' "$LAYOUT_PREFETCH/blobs/sha256/${a#sha256:}" | while read -r s; do
    if tar -tzf "$LAYOUT_PREFETCH/blobs/sha256/${s#sha256:}" 2> /dev/null | grep -x bin/busybox > /dev/null; then echo "$s"; fi; done)
  tar -xzOf "$LAYOUT_PREFETCH/blobs/sha256/${a#sha256:}" bin/busybox > "$x/busybox-prefetch"
  attendu "bin/busybox de l'image (couche ${a:7:12})" "$(sha256sum < "$x/busybox-prefetch" | cut -c1-64)" "$BUSYBOX_PREFETCH"
  bb_liens "$x/busybox-prefetch" "$x/bb"
  echo "     $("$x/bb/busybox" | head -1) ; $(ls "$x/bb" | wc -l) applets"
  f=$x/ws-bb/entrees
  entrees_hote "$f"
  r=$(env -i PATH="$x/bb" "$x/bb/sh" "$x/confrontation.sh" "$f")
  attendu "confrontation sous busybox" "$r" "fermeture deb confrontée au verrou : 162 paquets, sha256, taille et chemin identiques, aucun autre fichier dans le pool"
  sed -e "s#\$(workspaces.sortie.path)#$x/ws-bb#g" -e "s#/tmp/#$x/tmp-bb/#g" "$x/preparer-assemblage.sh" > "$x/assemblage-bb.sh"
  mkdir -p "$x/tmp-bb"
  unshare -rn env -i HOME="$x/tmp-bb" PATH="$(dirname "$(command -v python3)"):$GO:$x/bb" "$x/bb/sh" "$x/assemblage-bb.sh" 2>&1 | sed 's/^/     /'
  attendu "entrees obtenues sous busybox et sous les outils de l'hôte : contenu" "$(diff -r "$e" "$f" > /dev/null && echo égal || echo différent)" égal
  attendu "entrees obtenues sous busybox et sous les outils de l'hôte : modes et types" "$(cmp -s <(modes "$e") <(modes "$f") && echo égal || echo différent)" égal

  echo "## construire-deb, sur l'hôte : paquet source (section du script, outils de l'hôte)"
  rm -rf "$x/w"; mkdir -p "$x/w"
  { echo 'set -euo pipefail'; echo "e=$e"
    sed -n '/^c=\$e\/debian\/changelog$/,/^echo "paquet source/p' "$x/construire.sh"
  } | sed "s#/w/#$x/w/#g; s#/w\$#$x/w#g" > "$x/source.sh"
  attendu "section du paquet source extraite (début, dpkg-source, fin)" "$(grep -c '^c=\$e/debian/changelog$\|dpkg-source -q -b\|^echo "paquet source' "$x/source.sh")" 3
  bash "$x/source.sh" | sed 's/^/     /'
  a=sample-app_1.0.0.orig.tar.gz
  attendu "$a égal à celui de sources.sh" "$(sha256sum < "$x/w/src/$a" | cut -c1-64)" "$(awk -v f="$a" '$2 == f {print $1}' "$PKG/SHA256SUMS")"
  # Constat du 11/11/2026 (premier passage de prealables, 18:03 UTC) : le .debian.tar.xz de sources.sh porte le umask de l'hôte
  # (002 : 664 et 775, cp -r depuis l'arbre de travail), celui de la plateforme les modes de git (644 et 755). Seuls les modes
  # doivent différer ; le .dsc diffère donc aussi. Le deb n'en dépend pas (dh_fixperms), ce que la pipeline mesurera.
  a=sample-app_1.0.0-1.debian.tar.xz
  attendu "$a : mêmes membres, tailles et dates que celui de sources.sh, groupe sans écriture" \
    "$(tar -tvJf "$x/w/src/$a" | sha256sum | cut -c1-64)" "$(tar -tvJf "$PKG/$a" | sed -E 's/^(.{5})w/\1-/' | sha256sum | cut -c1-64)"
  echo "     (sur l'hôte : $a $(sha256sum < "$x/w/src/$a" | cut -c1-64), .dsc $(sha256sum < "$x/w/src/sample-app_1.0.0-1.dsc" | cut -c1-64) ; sources.sh : $(awk '$2 ~ /debian.tar.xz|dsc$/ {printf "%s %s ; ", $2, substr($1, 1, 16)}' "$PKG/SHA256SUMS"))"

  echo "## construire-deb, sur l'hôte : layout écrit avec le deb de S3 (section du script), lu comme publier-image"
  attendu "deb de S3" "$(sha256sum < "$DEB_S3" | cut -c1-64)" "$DEB_SHA"
  rm -rf "$x/w" "$x/o"; mkdir -p "$x/w/sortie" "$x/o"
  cp "$DEB_S3" "$x/w/sortie/"
  { echo 'set -euo pipefail'; echo "o=$x/o"; echo "deb=$x/w/sortie/${DEB_S3##*/}"
    sed -n '/^# Layout OCI à la main/,/^printf .sha256:%s/p' "$x/construire.sh" \
      | sed -e "s#/w/#$x/w/#g" -e "s#\$(results.DIGEST_CONSTRUIT.path)#$x/digest#g"
  } > "$x/layout.sh"
  attendu "section du layout extraite (début, fin)" "$(grep -c '^# Layout OCI à la main\|^printf .sha256:%s' "$x/layout.sh")" 2
  bash "$x/layout.sh" | sed 's/^/     /'
  rm -rf "$x/lu"; mkdir -p "$x/lu"; tar -xf "$x/o/image.tar" -C "$x/lu"
  s=$(sed -n 's/.*"digest": *"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' "$x/lu/index.json")   # sed de publier-image
  attendu "index.json lu comme publier-image : une ligne, égale au résultat" "$(wc -l <<< "$s") $s" "1 $(cat "$x/digest")"
  for a in "$x"/lu/blobs/sha256/*; do [ "$(sha256sum < "$a" | cut -c1-64)" = "${a##*/}" ] || { echo "KO   blob ${a##*/}" >&2; exit 1; }; done
  echo "OK   chaque blob a pour nom son sha256 ($(ls "$x/lu/blobs/sha256" | wc -l) blobs)"
  a=$x/lu/blobs/sha256/${s#sha256:}
  attendu "diff_ids égaux aux digests des couches" "$(jq -c '.rootfs.diff_ids' "$x/lu/blobs/sha256/$(jq -r '.config.digest' "$a" | cut -d: -f2)")" "$(jq -c '[.layers[].digest]' "$a")"
  attendu "couche : le deb seul, en 0644, propriétaire 0" "$(tar -tvf "$x/lu/blobs/sha256/$(jq -r '.layers[0].digest' "$a" | cut -d: -f2)" | awk '{print $1, $2, $6}')" "-rw-r--r-- 0/0 ${DEB_S3##*/}"
  attendu "deb de la couche égal au deb de S3" "$(tar -xOf "$x/lu/blobs/sha256/$(jq -r '.layers[0].digest' "$a" | cut -d: -f2)" | sha256sum | cut -c1-64)" "$DEB_SHA"
  echo "$s" > "$T/digest-attendu"
  echo "digest attendu de l'artefact, si le deb est $DEB_SHA et le tar de l'image de build écrit la même couche : $s"

  echo "## entrées du pod d'essai"
  tar -C "$e" --sort=name -cf "$T/entrees.tar" debian fermeture src verrou-deb.txt
  echo "entrees.tar : $(stat -c %s "$T/entrees.tar") octets, sha256 $(sha256sum < "$T/entrees.tar" | cut -c1-64)"
}

etape_busybox_outils() { # lecture dans Zot : image d'outils (étape entrees de preparer-deb) tirée par digest ; section de
  # confrontation rejouée sous son busybox, applets seuls (ajouté le 11/11/2026 avant tout lancement, avis du conseiller)
  local x=$T/essais l=$T/outils-layout m s a f
  [ -s "$x/confrontation.sh" ] && [ -d "$x/ws-bb/entrees" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  rm -rf "$l"
  oras cp --no-tty --from-ca-file "$P/ca-poc.crt" "${OUTILS_IMAGE/$REG/$REG_HOTE}" --to-oci-layout "$l:o" > /dev/null
  m=$l/blobs/sha256/${OUTILS_DIGEST#sha256:}
  attendu "image d'outils tirée par digest (manifeste)" "sha256:$(sha256sum < "$m" | cut -c1-64)" "$OUTILS_DIGEST"
  for s in $(jq -r '.layers[].digest' "$m"); do
    a=$(tar -tvzf "$l/blobs/sha256/${s#sha256:}" 2> /dev/null | awk '$1 ~ /^-/ && $NF ~ /(^|\/)busybox$/ {print $NF}' | head -1)
    [ -z "$a" ] || { tar -xzOf "$l/blobs/sha256/${s#sha256:}" "$a" > "$x/busybox-outils"; echo "busybox de l'image d'outils : /$a (couche ${s:7:12}), sha256 $(sha256sum < "$x/busybox-outils" | cut -c1-64)"; break; }
  done
  [ -s "$x/busybox-outils" ] || { echo "KO   busybox introuvable dans l'image d'outils" >&2; exit 1; }
  bb_liens "$x/busybox-outils" "$x/bb-outils"
  echo "     $("$x/bb-outils/busybox" | head -1) ; $(ls "$x/bb-outils" | wc -l) applets"
  f=$x/bbo/entrees
  rm -rf "$x/bbo"; mkdir -p "$x/bbo"
  entrees_hote "$f"
  attendu "confrontation sous le busybox de l'image d'outils" "$(env -i PATH="$x/bb-outils" "$x/bb-outils/sh" "$x/confrontation.sh" "$f")" \
    "fermeture deb confrontée au verrou : 162 paquets, sha256, taille et chemin identiques, aucun autre fichier dans le pool"
  a=$f/fermeture/miroir/pool/main/b/bash/bash_5.2.37-2+b10_amd64.deb
  cp "$a" "${a%/*}/autre_1_amd64.deb"
  r=$(env -i PATH="$x/bb-outils" "$x/bb-outils/sh" "$x/confrontation.sh" "$f" 2>&1) && { echo "KO   accepté : paquet en plus : $r" >&2; exit 1; }
  echo "OK   refusé sous busybox : paquet en plus ($(tail -1 <<< "$r"))"
  rm "${a%/*}/autre_1_amd64.deb"; printf x | dd of="$a" bs=1 seek=100 conv=notrunc status=none
  r=$(env -i PATH="$x/bb-outils" "$x/bb-outils/sh" "$x/confrontation.sh" "$f" 2>&1) && { echo "KO   accepté : paquet altéré : $r" >&2; exit 1; }
  echo "OK   refusé sous busybox : paquet altéré ($(tail -1 <<< "$r"))"
}

etape_reseau() {
  kubectl apply -f "$D/construction-deb-sans-sortie.yaml" < /dev/null > /dev/null
  kubectl get netpol -n builds -o json < /dev/null > "$T/netpol.json"
  echo "NetworkPolicy de builds : $(jq -r '[.items[].metadata.name] | join(", ")' "$T/netpol.json")"
  attendu "politiques qui sélectionnent construire-deb, sans entrée ni sortie" \
    "$(jq -r '[.items[] | select(.spec.podSelector.matchLabels["tekton.dev/task"] == "construire-deb" and (.spec.policyTypes | sort) == ["Egress", "Ingress"])] | length' "$T/netpol.json")" 1
  attendu "politiques de builds qui autorisent du trafic" \
    "$(jq -r '[.items[] | select(((.spec.egress // []) | length) > 0 or ((.spec.ingress // []) | length) > 0)] | length' "$T/netpol.json")" 0
  kubectl get ciliumnetworkpolicy -n builds -o json < /dev/null > "$T/cnp.json"
  attendu "CiliumNetworkPolicy de builds qui sélectionnent construire-deb et autorisent du trafic" \
    "$(jq -r -L "$here" 'include "selecteurs"; [.items[] | .kind = "CiliumNetworkPolicy" | select(selectionne({"tekton.dev/task": "construire-deb"}) and autorise) | nom] | join(", ")' "$T/cnp.json")" ""
}

pod_retirer() { kubectl delete pod -n builds "$1" --wait=false < /dev/null > /dev/null; echo "pod $1 supprimé"; }
copier_pod() { # pod fichier-hôte chemin-pod : par morceaux de 64 Mio (s3.sh), taille relevée après chaque morceau, sha256 final
  local n i k e m=$((MORCEAU_MIO * 1048576)) nb
  n=$(stat -c %s "$2"); nb=$(( (n + m - 1) / m )); [ "$nb" -gt 0 ] || nb=1
  kubectl exec -n builds "$1" -- sh -c ": > $3" < /dev/null
  for ((i = 0; i < nb; i++)); do
    k=$(( n - i * m < m ? n - i * m : m ))
    dd if="$2" bs=1M skip=$((i * MORCEAU_MIO)) count=$MORCEAU_MIO status=none \
      | timeout 120 kubectl exec -i -n builds "$1" -- sh -c "head -c $k >> $3" \
      || { pod_retirer "$1"; echo "KO   copie de ${2##*/}, morceau $((i + 1)) sur $nb" >&2; exit 1; }
    e=$(kubectl exec -n builds "$1" -- stat -c %s "$3" < /dev/null)
    [ "$e" = "$(( i * m + k ))" ] || { pod_retirer "$1"; echo "KO   copie de ${2##*/} : $e octets après le morceau $((i + 1))" >&2; exit 1; }
  done
  e=$(kubectl exec -n builds "$1" -- sha256sum "$3" < /dev/null | cut -c1-64)
  [ "$e" = "$(sha256sum < "$2" | cut -c1-64)" ] && echo "OK   copie de ${2##*/} dans le pod : $n octets en $nb morceau(x), sha256 conforme" \
    || { pod_retirer "$1"; echo "KO   copie de ${2##*/} : sha256 dans le pod $e" >&2; exit 1; }
}

etape_essai() {
  local p=s4d-essai x=$T/essai rc=0 d
  [ -s "$T/entrees.tar" ] && [ -s "$T/digest-attendu" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  rm -rf "$x"; mkdir -p "$x"
  rendre_taches
  # Script de construire-deb tiré du gabarit rendu ; entrees, sortie et résultat sur des emptyDir du pod ; la lecture seule des
  # entrées n'est pas testée ici (emptyDir écrit par la copie), elle l'est dans la pipeline
  script_etape "$T/construire-deb.yaml" construire \
    | sed -e 's#^! touch "\$e/.ecriture".*#echo "(essai : lecture seule des entrées non testée)"#' \
          -e 's#\$(workspaces.entrees.path)#/e#g' -e 's#\$(workspaces.sortie.path)#/o#g' -e 's#\$(results.DIGEST_CONSTRUIT.path)#/w/digest#g' > "$x/construire.sh"
  attendu "script d'essai : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/construire.sh" || true)" 0
  attendu "script d'essai : ligne de lecture seule remplacée" "$(grep -c '^echo "(essai : lecture seule' "$x/construire.sh")" 1
  jq -n --arg n "$p" --arg i "$BUILDER" --argjson l "$LIMITES" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"tekton.dev/task": "construire-deb"}},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      runtimeClassName: "kata",
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: "4Gi"}}, {name: "e", emptyDir: {}}, {name: "o", emptyDir: {}}],
      containers: [{name: "essai", image: $i, command: ["sleep", "7200"],
        securityContext: {privileged: true, allowPrivilegeEscalation: true, runAsUser: 1000, runAsGroup: 1000, runAsNonRoot: true},
        resources: {requests: $l, limits: $l},
        volumeMounts: [{name: "w", mountPath: "/w"}, {name: "e", mountPath: "/e"}, {name: "o", mountPath: "/o"}]}]}}' > "$x/pod.json"
  kubectl delete pod -n builds "$p" --ignore-not-found --wait=true < /dev/null > /dev/null
  # Pod supprimé même en cas d'échec (corrigé le 11/11/2026 avant tout lancement, avis du conseiller : une sortie en erreur après sa
  # création le laissait vivre jusqu'à deux heures). Piège posé ici : l'étape tourne dans le sous-shell de lancer (commun.sh), qui
  # n'hérite pas du piège global.
  trap 'kubectl delete pod -n builds s4d-essai --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true' EXIT
  kubectl create -f "$x/pod.json" < /dev/null > /dev/null
  echo "pod $p créé à $(date -u +%H:%M:%S) (image $BUILDER)"
  kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null \
    || { kubectl describe pod -n builds "$p" < /dev/null | tail -n 20 | grep -viE 'jeton|token' >&2; pod_retirer "$p"; echo "KO   pod $p non prêt" >&2; exit 1; }
  echo "pod prêt sur $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName {.spec.runtimeClassName}' < /dev/null)"
  copier_pod "$p" "$T/entrees.tar" /e/entrees.tar
  kubectl exec -n builds "$p" -- sh -c 'tar -xf /e/entrees.tar -C /e && rm /e/entrees.tar' < /dev/null \
    || { pod_retirer "$p"; echo "KO   déballage des entrées" >&2; exit 1; }
  # Le script est un fichier dans le pod, comme sous Tekton, et rien n'arrive sur son entrée standard (corrigé le 11/11/2026 avant
  # tout lancement, avis du conseiller : par bash -s, un processus fils qui lit l'entrée standard avalerait la suite du script)
  copier_pod "$p" "$x/construire.sh" /w/construire.sh
  echo "## script de construire-deb dans le pod ($(date -u +%H:%M:%S))"
  timeout 1800 kubectl exec -n builds "$p" -- bash /w/construire.sh < /dev/null > "$x/construire.log" 2>&1 || rc=$?
  echo "fin à $(date -u +%H:%M:%S)"
  grep -viE 'jeton|token' "$x/construire.log" > "$R/s4d-essai-construire.log" || true
  grep -v -e '^Installed-Build-Depends:' -e '^ [a-z0-9]' "$R/s4d-essai-construire.log" | cut -c1-220 | sed 's/^/     /'
  echo "     (code de l'exec : $rc ; journal complet : resultats/s4d-essai-construire.log)"
  attendu "dernière ligne du script atteinte (image.tar)" "$(grep -c '^image.tar : [0-9]* octets$' "$x/construire.log" || true)" 1
  if [ $rc = 0 ]; then
    kubectl exec -n builds "$p" -- cat /o/image.tar < /dev/null > "$x/image.tar"
    attendu "image.tar rapatrié (sha256 dans le pod)" "$(sha256sum < "$x/image.tar" | cut -c1-64)" "$(kubectl exec -n builds "$p" -- sha256sum /o/image.tar < /dev/null | cut -c1-64)"
    d=$(kubectl exec -n builds "$p" -- cat /w/digest < /dev/null)
  fi
  pod_retirer "$p"
  [ $rc = 0 ] || { echo "KO   script de construire-deb : code $rc" >&2; exit 1; }
  mkdir -p "$x/lu"; tar -xf "$x/image.tar" -C "$x/lu"
  attendu "index.json lu comme publier-image : égal au résultat" "$(sed -n 's/.*"digest": *"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' "$x/lu/index.json")" "$d"
  mesure "deb construit dans le pod d'essai" "$(tar -xOf "$x/lu/blobs/sha256/$(jq -r '.layers[0].digest' "$x/lu/blobs/sha256/${d#sha256:}" | cut -d: -f2)" | sha256sum | cut -c1-64)" "$DEB_SHA"
  mesure "digest de l'artefact" "$d" "$(cat "$T/digest-attendu")"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

signer_tache() { # nom : signature versionnée dans deb/, bundle (tag s4d), liste revue de la 08 (comme s4b.sh)
  local n=$1 v=$D/$1.signee.yaml r
  tkn task sign "$T/$n.yaml" -K "$S/taches.key" -f "$T/$n-signee.yaml" > /dev/null
  if [ -n "${SIGNER:-}" ] && ! { [ -s "$v" ] && cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v"); }; then
    cp "$T/$n-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans deb/$n.signee.yaml"
  fi
  [ -s "$v" ] || { echo "KO   signature versionnée absente : SIGNER=1, puis revue de la liste" >&2; exit 1; }
  cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") \
    && echo "OK   $n : signature versionnée conforme au gabarit rendu, signature exceptée" \
    || { echo "KO   $n : gabarit modifié depuis la signature versionnée" >&2; exit 1; }
  r=$REG/tekton/tasks/$n@$(bundle "$v" "tekton/tasks/$n" s4d)
  echo "$r" > "$T/$n.ref"
  if liste_revue "$r"; then echo "OK   $n dans la liste revue : $r"
  elif [ -n "${SIGNER:-}" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml (08) après revue du propriétaire : $r"
  else echo "KO   $n absente de la liste revue : $r" >&2; exit 1; fi
}

etape_taches() {
  local pu
  [ -s "$S/taches.key" ] || { echo "KO   clé des tâches absente" >&2; exit 1; }
  pu=$(ref_revue publier-image d21931f3)
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh), compte poc-ecriture
  echo "## tâches (tkn $(tkn version --component client))"
  rendre_taches
  signer_tache preparer-deb
  signer_tache construire-deb
  [ -z "${SIGNER:-}" ] || { echo "SIGNER : pipeline non signée tant que la liste revue n'a pas été acceptée"; return 0; }
  echo "## pipeline sample-app-deb"
  rendre_pipeline "$(cat "$T/preparer-deb.ref")" "$(cat "$T/construire-deb.ref")" "$pu"
  tkn pipeline sign "$T/sample-app-deb.yaml" -K "$S/taches.key" -f "$T/sample-app-deb-signee.yaml" > /dev/null
  echo "$REG/tekton/pipelines/sample-app-deb@$(bundle "$T/sample-app-deb-signee.yaml" tekton/pipelines/sample-app-deb s4d)" | tee "$T/pipeline.ref"
}

pr_json() { # nom : PipelineRun de sample-app-deb, podTemplate du gabarit sample-app, Kata pour la seule tâche construire
  jq -n --arg n "$1" --arg b "$(cat "$T/pipeline.ref")" --arg c "$COMMIT" --arg u "$DEPOT_GIT" '
    {nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}}} as $z
    | {apiVersion: "tekton.dev/v1", kind: "PipelineRun", metadata: {name: $n, namespace: "builds"},
      spec: {pipelineRef: {resolver: "bundles", params: [{name: "bundle", value: $b}, {name: "name", value: "sample-app-deb"}, {name: "kind", value: "pipeline"}]},
        params: [{name: "commit", value: $c}, {name: "depot", value: $u}],
        workspaces: [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: "1Gi"}}}}}],
        taskRunTemplate: {serviceAccountName: "build", podTemplate: $z},
        taskRunSpecs: [{pipelineTaskName: "construire", podTemplate: ($z + {runtimeClassName: "kata"})}]}}' > "$T/pr-$1.json"
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
  local i pr r t p d k
  [ -s "$T/pipeline.ref" ] || { echo "KO   pipeline absente (étape taches)" >&2; exit 1; }
  for i in 1 2; do
    pr=s4d-deb-$i
    pr_json "$pr"; purger_pr "$pr"
    kubectl create -f "$T/pr-$pr.json" < /dev/null > /dev/null
    echo "## $pr créé à $(date -u +%H:%M:%S) ($(cat "$T/pipeline.ref"))"
    r=$(fin_pr "$pr")
    for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
      p=$(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.podName}' < /dev/null)
      kubectl logs -n builds "$p" --all-containers < /dev/null 2>&1 | grep -viE 'jeton|token' > "$T/$t.log" || true
      k=$(kubectl get pod -n builds "$p" -o jsonpath='{.metadata.labels.tekton\.dev/task}' < /dev/null)
      echo "### TaskRun $t ($(kubectl get taskrun -n builds "$t" -o jsonpath='{.status.conditions[0].reason}' < /dev/null)), pod $p sur $(
        kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName « {.spec.runtimeClassName} », tekton.dev/task {.metadata.labels.tekton\.dev/task}' < /dev/null 2> /dev/null)"
      grep -vE '^\s*$' "$T/$t.log" | grep -v -e '^Installed-Build-Depends:' -e '^ [a-z0-9]' | tail -n 30 | cut -c1-220 | sed 's/^/     /'
      [ "$k" != construire-deb ] || cp "$T/$t.log" "$R/s4d-pipeline-$i-construire.log"
      case $k in
        construire-deb) attendu "$t : runtimeClassName" "$(kubectl get pod -n builds "$p" -o jsonpath='{.spec.runtimeClassName}' < /dev/null)" kata ;;
        *) attendu "$t : runtimeClassName" "$(kubectl get pod -n builds "$p" -o jsonpath='{.spec.runtimeClassName}' < /dev/null)" "" ;;
      esac
      attendu "$t : nœud" "$(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}' < /dev/null)" sc-build
    done
    attendu "PipelineRun $pr" "$(cut -d'|' -f1,2 <<< "$r")" "True|Succeeded"
    d=$(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null | jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value')
    echo "$d" > "$T/deb-$i.digest"
    echo "artefact publié : $(kubectl get pipelinerun -n builds "$pr" -o json < /dev/null | jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value')@$d"
    attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
  done
  mesure "deux exécutions, même artefact" "$(cat "$T/deb-2.digest")" "$(cat "$T/deb-1.digest")"
  mesure "artefact égal au digest attendu (prealables)" "$(cat "$T/deb-1.digest")" "$(cat "$T/digest-attendu")"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

etape_comparaison() {
  local c=$T/comparaison d m l i
  rm -rf "$c"; mkdir -p "$c"
  for i in 1 2; do
    d=$(cat "$T/deb-$i.digest")
    oras cp --no-tty --from-ca-file "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}@$d" --to-oci-layout "$c/layout-$i:a" > /dev/null
    m=$c/layout-$i/blobs/sha256/${d#sha256:}
    attendu "artefact $i : manifeste relu au digest publié" "$(sha256sum < "$m" | cut -c1-64)" "${d#sha256:}"
    l=$c/layout-$i/blobs/sha256/$(jq -r '.layers[0].digest' "$m" | cut -d: -f2)
    attendu "artefact $i : une couche, le deb seul" "$(jq '.layers | length' "$m") $(tar -tf "$l")" "1 sample-app_1.0.0-1_amd64.deb"
    mkdir -p "$c/deb-$i"; tar -xf "$l" -C "$c/deb-$i"
    mesure "artefact $i : deb égal à celui d'OBS, S1 et S3" "$(sha256sum < "$c/deb-$i/sample-app_1.0.0-1_amd64.deb" | cut -c1-64)" "$DEB_SHA"
    # Installed-Build-Depends du .buildinfo (journal de construire) comparés au verrou, nom=version
    sed -n '/^----- .*\.buildinfo -----$/,/^----- fin du .buildinfo -----$/p' "$R/s4d-pipeline-$i-construire.log" \
      | awk '/^Installed-Build-Depends:/ {b = 1; next} b && /^[^ ]/ {b = 0} b' | sed -E 's/^ *([^ ]+) \(= ([^)]+)\),?$/\1=\2/' | sort > "$c/ibd-$i.v"
    mesure "artefact $i : Installed-Build-Depends égaux au verrou (nom=version), lignes d'écart" \
      "$(diff "$c/ibd-$i.v" <(awk '{print $1 "=" $2}' "$repo/poc/packaging/verrou-deb.txt" | sort) | grep -c '^[<>]' || true)" 0
  done
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

etape_provenance() {
  local d uid pr=s4d-deb-1 f=$T/prov.json
  d=$(cat "$T/deb-1.digest")
  uid=$(kubectl get pipelinerun -n builds "$pr" -o jsonpath='{.metadata.uid}' < /dev/null)
  cosign verify-attestation --key "$here/resultats/chains-cle-publique.pem" --type slsaprovenance1 --insecure-ignore-tlog=true \
    --registry-cacert "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}@$d" > "$T/att.json" 2> "$T/cosign.err" || { cat "$T/cosign.err" >&2; exit 1; }
  echo "OK   cosign verify-attestation : $(wc -l < "$T/att.json") enveloppe(s) valide(s) sur $d"
  jq -c --arg u "$uid" '.payload | @base64d | fromjson | select(.predicate.runDetails.metadata.invocationId == $u)' "$T/att.json" > "$f"
  attendu "enveloppes du PipelineRun $pr" "$(wc -l < "$f")" 1
  jq -r '"buildType : \(.predicate.buildDefinition.buildType)", "resolvedDependencies :",
    (.predicate.buildDefinition.resolvedDependencies[] | "  \(.name // "-") \(.uri // "-") \(.digest // {} | to_entries | map(.key + ":" + .value) | join(","))")' "$f"
  attendu "sujet" "$(jq -r '.subject | map("\(.name)@sha256:\(.digest.sha256)") | join(",")' "$f")" "$IMAGE@$d"
  attendu "buildType" "$(jq -r '.predicate.buildDefinition.buildType' "$f")" https://tekton.dev/chains/v2/slsa-tekton
  attendu "source" "$(jq -r --arg u "git+$DEPOT_GIT" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha1:" + .digest.sha1' "$f")" "sha1:$COMMIT"
  dep() { jq -r --arg u "oci://${1%@*}" '.predicate.buildDefinition.resolvedDependencies[] | select(.uri == $u) | "sha256:" + .digest.sha256' "$f" | sort -u; }
  for a in "$FERMETURE_DEB" "$FERMETURE_SOURCES" "$PACKAGING" "$BUILDER"; do
    attendu "entrée ${a%@*}" "$(dep "$a")" "${a#*@}"
  done
  attendu "tâches dans la provenance" "$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
    | .spec.taskRef.params // [] | map(select(.name == "name")) | .[0].value' "$f" | sort | paste -sd' ')" "construire-deb preparer-deb publier-image"
  attendu "TaskRun de construire-deb : runtimeClassName kata dans la spec signée" "$(jq -r '.predicate.buildDefinition.resolvedDependencies[] | select(.name == "pipelineTask") | .content | @base64d | fromjson
    | select(.spec.taskRef.params[]? | .name == "name" and .value == "construire-deb") | .spec.podTemplate.runtimeClassName' "$f")" kata
  openssl ecparam -genkey -name prime256v1 2> /dev/null | openssl ec -pubout -out "$T/autre.pub" 2> /dev/null
  refus "provenance vérifiée avec une autre clé" "no matching attestations|invalid signature|signature" \
    cosign verify-attestation --key "$T/autre.pub" --type slsaprovenance1 --insecure-ignore-tlog=true --registry-cacert "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}@$d"
}

lancer s4d S4d1 "$@"
