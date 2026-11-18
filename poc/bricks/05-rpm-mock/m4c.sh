#!/usr/bin/env bash
# Brique 05, jalon M4c (carte de M4c du 18/11/2026 ; décisions « rpm seul » et « option (i) ») : pipeline de la plateforme
# sample-app-rpm, qui construit le rpm de sample-app sous Kata, sans réseau, depuis la fermeture rpm de M4b, la fermeture
# applicative de la 06 et l'artefact de packaging de M4a, et le publie dans builds/sample-app-rpm. Modèle : s4d.sh de la 06.
# Prédictions : resultats/m4c-predictions.md, commitées avant tout lancement. Préparé à sec sous l'accord permanent du 18/11.
#   prealables  hôte seul, hors ligne, sans cluster ni Zot : références épinglées contrôlées ; gabarits de construction/ rendus
#               (références des tâches factices dans la pipeline) et relus ; scripts des pas sans erreur de syntaxe ; pas sources
#               et début du pas assemblage égaux à ceux de preparer-deb ; preparer-rpm joué sur l'hôte, sur les copies locales
#               (fermeture rpm tirée par comparaison de M4b, fermeture applicative tirée en S4b de la 06, spec et verrou du dépôt),
#               assemblage sous unshare -rn, avec les outils de l'hôte puis sous le busybox de l'image de prefetch ; arbre amont
#               comparé à celui de l'archive de sources.sh ; sections de construire-rpm jouées sur l'hôte : confrontation au
#               verrou (rpm simulé par une lecture Python du sigmd5 de l'en-tête de signature, l'hôte n'a pas rpm), avec des cas
#               altérés ; archive Source0 comparée à celle de sources.sh ; layout écrit avec le rpm de M3, d'où le digest attendu
#               de l'artefact ; entrees.tar pour le pod d'essai
# Les étapes suivantes (essai_preparer, essai, taches, pipeline, comparaison, provenance) seront ajoutées après prealables.
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/m4c.sh <étape>…
# (journal : resultats/m4c-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "$0")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, OUTILS, OUTILS_DIGEST, refus, bundle, auth_zot, lancer, chrono
R=$h05/resultats
C=$h05/construction
T=$W/m4c-05
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets (étapes à venir), retirées même en cas d'échec
umask 022

PREFETCH_IMAGE=$REG/plateforme/outils-prefetch@sha256:68e0ae705de5a8f993f168d8252b3218d7d3ed76e704cf24d4414006aea7b8cc   # preparer-deb (06)
OUTILS_IMAGE=$REG/$OUTILS@$OUTILS_DIGEST                                                                                  # preparer-deb (06)
IMAGE_OUTILLAGE=$REG/essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771       # « Option 1 »
FERMETURE_RPM=$REG/builds/fermetures/sample-app-rpm@sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c    # M4b
FERMETURE_SOURCES=$REG/builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21   # S4b (06)
PACKAGING=$REG/entrees/sample-app/packaging-rpm@sha256:41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8      # M4a
PUBLIER_REF=$REG/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b         # liste revue
EPOQUE=1793229566   # décision « option (i) » : date de l'archive de sources.sh (dernier commit de poc/sample-app, 3da431db)
IMAGE=$REG/builds/sample-app-rpm
COMMIT=6391fd437f26696847041be3226bbbf633f55a2f   # construction.sh : main de workspace/sample-app (arbre 30e808ff = poc/sample-app)
DEPOT_GIT=https://sc-stockage.poc.test:3000/workspace/sample-app.git
ARBRE=30e808ffa327288c656ddda7b6fafe4005234b77
VERROU=$repo/poc/packaging/verrou-rpm.json
VERROU_SHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f   # verrou_derivee (303b428), artefact de M4a
SPEC=$repo/poc/packaging/sample-app.spec
SPEC_SHA=918a83f592c31d322a77a4e887c808c61077e2f100442dc98abed5c67ae582a6     # artefact de M4a (V4)
TIREE=$W/m4b-05/comparaison/tiree   # fermeture rpm tirée par digest par l'étape comparaison de M4b (arbre égal à final sous depot/)
S4B=$W/s4b-06                       # fermeture applicative tirée par digest en S4b de la 06 (comparaison/sources)
PKG=$HOME/.cache/supply-chain-poc/packaging
ARCHIVE_SHA=07521c1e60cdbed8a29912ad775e52201daf95003f7f54ccee76b3270742d9bb   # sample-app-1.0.0.tar.gz de sources.sh (S1, M3)
RPM_M3=$W/s1-05/m3/build-1/sample-app-1.0.0-2.el9.x86_64.rpm
RPM_M3_SHA=864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f   # m3_comparaison
GO=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.26.10.linux-amd64/bin   # comme s4d.sh
LISTE_REVUE=$here/politique/porte/taches.yml
LAYOUT_PREFETCH=$HOME/.cache/supply-chain-poc/03/f2/layout   # layout de l'image de prefetch (prefetch.sh image, brique 03), 68e0ae70
BUSYBOX_PREFETCH=49227c027f9b972f929780d60ee486dee5948ea7042cb7ab400690bb104418bc   # bin/busybox de cette image (comme s4d.sh)
FACTICE=sha256:$(printf '0%.0s' {1..64})

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
ref_revue() { # dépôt-de-tâche préfixe-du-digest : référence complète lue dans la liste revue de la 08 (une seule) ; de s4d.sh
  local r
  r=$(awk -v d="oci://$REG/tekton/tasks/$1:" -v p="sha256:$2" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && index($3, p) == 1 {print $3}' "$LISTE_REVUE")
  [ "$(grep -c . <<< "$r")" = 1 ] && [ -n "$r" ] || { echo "KO   $1 $2 : absente de la liste revue ou ambiguë" >&2; exit 1; }
  echo "$REG/tekton/tasks/$1@$r"
}
remplacer() { # source destination clé=valeur… : variables @CLE@ remplacées hors des commentaires ; de s4d.sh
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
  remplacer "$C/preparer-rpm.yaml" "$T/preparer-rpm.yaml" "PREFETCH=$PREFETCH_IMAGE" "OUTILS=$OUTILS_IMAGE"
  remplacer "$C/construire-rpm.yaml" "$T/construire-rpm.yaml" "IMAGE=$IMAGE_OUTILLAGE"
}
rendre_pipeline() { # preparer construire publier
  remplacer "$C/sample-app-rpm.yaml" "$T/sample-app-rpm.yaml" "PREPARER=$1" "CONSTRUIRE=$2" "PUBLIER=$3" \
    "FERMETURE_RPM=$FERMETURE_RPM" "FERMETURE_SOURCES=$FERMETURE_SOURCES" "PACKAGING=$PACKAGING" "EPOQUE=$EPOQUE" "IMAGE=$IMAGE"
  attendu "pipeline : subPath des workspaces (preparer, construire, publier)" \
    "$(yq -o=json -I=0 '[.spec.tasks[].workspaces[].subPath]' "$T/sample-app-rpm.yaml")" '[null,"entrees","image","image"]'
  attendu "pipeline : entrées de preparer fixées par digest" \
    "$(yq '.spec.tasks[0].params[] | select(.name != "depot" and .name != "commit") | .value' "$T/sample-app-rpm.yaml" | paste -sd' ')" \
    "$FERMETURE_RPM $FERMETURE_SOURCES $PACKAGING"
  attendu "pipeline : époque de construire (chaîne)" "$(yq -o=json -I=0 '.spec.tasks[1].params' "$T/sample-app-rpm.yaml")" \
    "[{\"name\":\"epoque\",\"value\":\"$EPOQUE\"}]"
  attendu "pipeline : tâches (nom, tâche du bundle)" \
    "$(yq '.spec.tasks[] | .name + ":" + (.taskRef.params[] | select(.name == "name") | .value)' "$T/sample-app-rpm.yaml" | paste -sd' ')" \
    "preparer:preparer-rpm construire:construire-rpm publier:publier-image"
}
script_etape() { yq ".spec.steps[] | select(.name == \"$2\") | .script" "$1"; }   # fichier-rendu nom-d'étape
bb_liens() { # busybox répertoire : un lien par applet vers ce busybox (PATH sans aucun outil de l'hôte) ; de s4d.sh
  local a
  rm -rf "$2"; mkdir -p "$2"; cp "$1" "$2/busybox"; chmod 0755 "$2/busybox"
  for a in $("$2/busybox" --list); do [ "$a" = busybox ] || ln -s busybox "$2/$a"; done
}
modes() { (cd "$1" && find . -printf '%m %y %P\n' | sort); }
entrees_hote() { # répertoire entrees : comme les tirerait le pas entrees (copies locales par digest), avant ses contrôles
  mkdir -p "$1/src" "$1/packaging"
  git -C "$repo" archive HEAD:poc/sample-app | tar -x -C "$1/src"
  cp -a "$TIREE" "$1/fermeture"
  cp -a "$S4B/comparaison/sources" "$1/sources"
  cp "$SPEC" "$VERROU" "$1/packaging/"
}
faux_rpm() { # répertoire : commande rpm simulée (« rpm -qp --qf %{SIGMD5} fichier » seulement), lecture Python de l'en-tête de
  # signature (lead de 96 octets, en-tête 8e ad e8 01, étiquette 1004 RPMSIGTAG_MD5, type 7, 16 octets)
  mkdir -p "$1"
  cat > "$1/sigmd5.py" <<'FIN'
import struct, sys
a = sys.argv[1:]
if len(a) != 4 or a[:3] != ['-qp', '--qf', '%{SIGMD5}']:
    sys.exit(f'rpm simulé : arguments non pris en charge : {a}')
b = open(a[3], 'rb').read(65536)
if b[:4] != b'\xed\xab\xee\xdb' or b[96:100] != b'\x8e\xad\xe8\x01':
    sys.exit(f'rpm simulé : en-tête illisible : {a[3]}')
n, taille = struct.unpack('>II', b[104:112])
donnees = 112 + 16 * n
for i in range(n):
    tag, typ, dec, nb = struct.unpack('>IIII', b[112 + 16 * i:128 + 16 * i])
    if tag == 1004 and typ == 7 and nb == 16:
        sys.stdout.write(b[donnees + dec:donnees + dec + 16].hex())
        sys.exit(0)
sys.exit(f'rpm simulé : pas de MD5 dans la signature : {a[3]}')
FIN
  printf '#!/bin/sh\nexec %s -I %s "$@"\n' "$(command -v python3)" "$1/sigmd5.py" > "$1/rpm"
  chmod 0755 "$1/rpm"
}

etape_prealables() { # hôte seul, hors ligne, sans cluster ni Zot
  local x=$T/prealables e f a s d
  rm -rf -- "${x:?}"; mkdir -p "$x"
  echo "## références épinglées"
  attendu "verrou du dépôt (sha256)" "$(sha256sum < "$VERROU" | cut -c1-64)" "$VERROU_SHA"
  attendu "spec du dépôt (sha256)" "$(sha256sum < "$SPEC" | cut -c1-64)" "$SPEC_SHA"
  attendu "publier-image dans la liste revue" "$(ref_revue publier-image d21931f3)" "$PUBLIER_REF"
  attendu "époque : date du dernier commit de poc/sample-app (celle de sources.sh)" "$(git -C "$repo" log -1 --format=%ct -- poc/sample-app)" "$EPOQUE"
  attendu "arbre de poc/sample-app à HEAD" "$(git -C "$repo" rev-parse HEAD:poc/sample-app)" "$ARBRE"
  attendu "archive de sources.sh (S1, M3)" "$(sha256sum < "$PKG/sample-app-1.0.0.tar.gz" | cut -c1-64)" "$ARCHIVE_SHA"
  attendu "rpm de M3 (build 1)" "$(sha256sum < "$RPM_M3" | cut -c1-64)" "$RPM_M3_SHA"
  attendu "fermeture rpm tirée par comparaison (M4b) : fichiers sous depot/" "$(find "$TIREE/depot" -type f | wc -l)" 230
  attendu "fermeture rpm tirée : rien d'autre que depot/ à la racine" "$(ls -A "$TIREE" | paste -sd' ')" depot

  echo "## gabarits rendus (références des tâches factices dans la pipeline)"
  rendre_taches
  rendre_pipeline "$REG/tekton/tasks/preparer-rpm@$FACTICE" "$REG/tekton/tasks/construire-rpm@$FACTICE" "$PUBLIER_REF"
  for f in preparer-rpm construire-rpm sample-app-rpm; do
    attendu "$f.yaml : apiVersion, kind, nom" "$(yq '.apiVersion + " " + .kind + " " + .metadata.name' "$T/$f.yaml")" \
      "tekton.dev/v1beta1 $([ $f = sample-app-rpm ] && echo Pipeline || echo Task) $f"
  done
  attendu "preparer-rpm : pas et images" "$(yq '.spec.steps[] | .name + "=" + .image' "$T/preparer-rpm.yaml" | paste -sd' ')" \
    "sources=$PREFETCH_IMAGE entrees=$OUTILS_IMAGE assemblage=$PREFETCH_IMAGE"
  attendu "preparer-rpm : contexte de sécurité commun" "$(yq -o=json -I=0 '.spec.stepTemplate.securityContext' "$T/preparer-rpm.yaml")" \
    '{"runAsUser":65532,"runAsNonRoot":true,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}'
  attendu "preparer-rpm : résultats" "$(yq '.spec.results[].name' "$T/preparer-rpm.yaml" | paste -sd' ')" \
    "CHAINS-GIT_URL CHAINS-GIT_COMMIT FERMETURE_RPM_ARTIFACT_INPUTS FERMETURE_SOURCES_ARTIFACT_INPUTS PACKAGING_ARTIFACT_INPUTS"
  attendu "construire-rpm : un pas, image d'outillage" "$(yq '.spec.steps[] | .name + "=" + .image' "$T/construire-rpm.yaml" | paste -sd' ')" \
    "construire=$IMAGE_OUTILLAGE"
  attendu "construire-rpm : contexte de sécurité du pas" "$(yq -o=json -I=0 '.spec.steps[0].securityContext' "$T/construire-rpm.yaml")" \
    '{"privileged":true,"allowPrivilegeEscalation":true,"runAsUser":0,"runAsGroup":0,"runAsNonRoot":false}'
  attendu "construire-rpm : ressources (demandes = limites)" "$(yq -o=json -I=0 '.spec.steps[0].resources' "$T/construire-rpm.yaml")" \
    '{"requests":{"cpu":"2","memory":"6Gi"},"limits":{"cpu":"2","memory":"6Gi"}}'
  attendu "construire-rpm : workspaces (entrees en lecture seule)" "$(yq -o=json -I=0 '.spec.workspaces' "$T/construire-rpm.yaml")" \
    '[{"name":"entrees","readOnly":true},{"name":"sortie"}]'
  attendu "construire-rpm : env du pas (l'époque seule)" "$(yq -o=json -I=0 '.spec.steps[0].env' "$T/construire-rpm.yaml")" \
    '[{"name":"EPOQUE","value":"$(params.epoque)"}]'

  echo "## scripts des pas"
  for s in sources entrees assemblage; do script_etape "$T/preparer-rpm.yaml" $s > "$x/preparer-$s.sh"; done
  script_etape "$T/construire-rpm.yaml" construire > "$x/construire.sh"
  for s in sources assemblage; do sh -n "$x/preparer-$s.sh"; done
  sed '1s|^#!/busybox/sh$|#!/bin/sh|' "$x/preparer-entrees.sh" | sh -n
  bash -n "$x/construire.sh"
  echo "OK   syntaxe : sh -n (sources, entrees, assemblage), bash -n (construire)"
  remplacer "$h05/../06-deb-sbuild/deb/preparer-deb.yaml" "$x/preparer-deb.yaml" "PREFETCH=$PREFETCH_IMAGE" "OUTILS=$OUTILS_IMAGE"
  attendu "pas sources égal à celui de preparer-deb" "$(cmp -s <(script_etape "$x/preparer-deb.yaml" sources) "$x/preparer-sources.sh" && echo égal || echo différent)" égal
  a=$(script_etape "$x/preparer-deb.yaml" assemblage | sed '/^# debian\/ et verrou/,$d')
  s=$(sed '/^# spec et verrou/,$d' "$x/preparer-assemblage.sh")
  attendu "pas assemblage : début égal à celui de preparer-deb (jusqu'à la copie du packaging, lignes)" \
    "$([ "$a" = "$s" ] && echo "égal $(wc -l <<< "$s")" || echo différent)" "égal $(wc -l <<< "$a")"
  attendu "construire : un seul heredoc Python (lignes FIN)" "$(grep -c "^FIN$" "$x/construire.sh")" 1

  echo "## preparer-rpm, sur l'hôte : contrôles du pas entrees, puis assemblage sous unshare -rn (go $("$GO/go" version | cut -d' ' -f3))"
  e=$x/ws/entrees
  entrees_hote "$e"
  { echo 'set -eu'; echo "e=$e"
    sed -n '/^\[ -s "\$e\/packaging\/sample-app.spec" \]/,/^\[ -z "\$(find "\$e\/fermeture"/p' "$x/preparer-entrees.sh"
  } > "$x/entrees-controles.sh"
  attendu "contrôles du pas entrees extraits (lignes)" "$(grep -c . "$x/entrees-controles.sh")" 6
  sh "$x/entrees-controles.sh"
  echo "OK   contrôles du pas entrees passés sur les copies locales"
  sed -e "s#\$(workspaces.sortie.path)#$x/ws#g" -e "s#/tmp/#$x/tmp/#g" "$x/preparer-assemblage.sh" > "$x/assemblage.sh"
  attendu "assemblage : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/assemblage.sh" || true)" 0
  mkdir -p "$x/tmp"
  unshare -rn env -i HOME="$x/tmp" PATH="$GO:$(dirname "$(command -v python3)"):/usr/bin:/bin" sh "$x/assemblage.sh" 2>&1 | sed 's/^/     /'
  [ ! -e "$e/sources" ] && [ ! -e "$e/packaging" ] || { echo "KO   assemblage incomplet" >&2; exit 1; }
  rm -rf "$x/arch"; mkdir -p "$x/arch"; tar -xzf "$PKG/sample-app-1.0.0.tar.gz" -C "$x/arch"
  attendu "entrees/src égal à l'arbre de l'archive de sources.sh (contenu)" "$(diff -r "$x/arch/sample-app-1.0.0" "$e/src" > "$x/src.diff" && echo égal || echo différent)" égal
  attendu "entrees/sample-app.spec égal au spec du dépôt" "$(cmp -s "$e/sample-app.spec" "$SPEC" && echo égal || echo différent)" égal
  attendu "entrees/verrou-rpm.json égal au verrou du dépôt" "$(cmp -s "$e/verrou-rpm.json" "$VERROU" && echo égal || echo différent)" égal
  attendu "entrees : contenu de premier niveau" "$(ls "$e" | paste -sd' ')" "fermeture sample-app.spec src verrou-rpm.json"

  echo "## preparer-rpm sous le busybox de l'image de prefetch (applets seuls, plus go et python3)"
  a=$(jq -r '.manifests[0].digest' "$LAYOUT_PREFETCH/index.json")
  attendu "layout local de l'image de prefetch" "$a" "${PREFETCH_IMAGE#*@}"
  a=$(jq -r '.layers[].digest' "$LAYOUT_PREFETCH/blobs/sha256/${a#sha256:}" | while read -r s; do
    if tar -tzf "$LAYOUT_PREFETCH/blobs/sha256/${s#sha256:}" 2> /dev/null | grep -x bin/busybox > /dev/null; then echo "$s"; fi; done)
  tar -xzOf "$LAYOUT_PREFETCH/blobs/sha256/${a#sha256:}" bin/busybox > "$x/busybox-prefetch"
  attendu "bin/busybox de l'image (couche ${a:7:12})" "$(sha256sum < "$x/busybox-prefetch" | cut -c1-64)" "$BUSYBOX_PREFETCH"
  bb_liens "$x/busybox-prefetch" "$x/bb"
  f=$x/ws-bb/entrees
  entrees_hote "$f"
  sed -e "s#\$(workspaces.sortie.path)#$x/ws-bb#g" -e "s#/tmp/#$x/tmp-bb/#g" "$x/preparer-assemblage.sh" > "$x/assemblage-bb.sh"
  mkdir -p "$x/tmp-bb"
  unshare -rn env -i HOME="$x/tmp-bb" PATH="$(dirname "$(command -v python3)"):$GO:$x/bb" "$x/bb/sh" "$x/assemblage-bb.sh" 2>&1 | sed 's/^/     /'
  attendu "entrees obtenues sous busybox et sous les outils de l'hôte : contenu" "$(diff -r "$e" "$f" > /dev/null && echo égal || echo différent)" égal
  attendu "entrees obtenues sous busybox et sous les outils de l'hôte : modes et types" "$(cmp -s <(modes "$e") <(modes "$f") && echo égal || echo différent)" égal

  echo "## construire-rpm, sur l'hôte : confrontation au verrou (section Python du pas, rpm simulé)"
  sed -n "/<<'FIN'\$/,/^FIN\$/p" "$x/construire.sh" | sed '1d;$d' > "$x/confronter.py"
  attendu "section Python extraite (première et dernière lignes)" "$(sed -n '1p;$p' "$x/confronter.py" | paste -sd'|')" \
    "import hashlib, json, os, stat, subprocess, sys|print(dos, j['bootstrap']['image_digest'])"
  faux_rpm "$x/faux"
  confronter() { PATH="$x/faux:$PATH" python3 -I "$x/confronter.py" "$1" "$2"; }   # verrou depot
  mkdir -p "$x/w"; cp -a "$e/fermeture" "$x/w/fermeture"; d=$x/w/fermeture/depot
  r=$(confronter "$e/verrou-rpm.json" "$d" 2> "$x/confronter.err")
  sed 's/^/     /' "$x/confronter.err"
  attendu "confrontation : sortie (dossier dir:, image_digest)" "$r" \
    "sc-stockage.poc.test@sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6 $(jq -r '.bootstrap.image_digest' "$VERROU")"
  attendu "confrontation : message" "$(cat "$x/confronter.err")" \
    "fermeture confrontée au verrou : 222 rpm (noms et sigmd5), image de bootstrap (manifest.json égal au pull_digest), repodata 4 fichiers, dossier dir: 4 fichiers, aucun autre objet"
  cas() { # libellé motif commande-de-mise-en-place (dans une copie en liens durs, verrou copié sous v.json) : refus attendu
    local k=$x/cas r
    rm -rf "$k"; mkdir -p "$k"; cp -al "$d" "$k/depot"; cp "$e/verrou-rpm.json" "$k/v.json"
    (cd "$k" && eval "$3")
    r=0; confronter "$k/v.json" "$k/depot" > /dev/null 2> "$k/err" || r=$?
    if [ $r != 0 ] && grep -q -F -e "$2" "$k/err"; then echo "OK   cas refusé, $1 : code $r, « $(cut -c1-110 "$k/err") »"
    else echo "KO   cas $1 : code $r, « $(cut -c1-200 "$k/err") »" >&2; exit 1; fi
  }
  cas "rpm du verrou retiré" "rpm du verrou absent(s)" 'rm depot/bash-5.1.8-9.el9.x86_64.rpm'
  cas "rpm en trop" "hors du verrou" 'cp depot/bash-5.1.8-9.el9.x86_64.rpm depot/bash-0-0.el9.x86_64.rpm'
  cas "fichier hors de repodata et du dossier dir:" "hors du verrou" 'echo x > depot/LISEZMOI'
  cas "sous-dossier inattendu" "hors du verrou" 'mkdir depot/autre'
  cas "lien symbolique à la place d'un rpm" "hors du verrou" 'rm depot/bash-5.1.8-9.el9.x86_64.rpm && ln -s alternatives-1.24-2.el9.x86_64.rpm depot/bash-5.1.8-9.el9.x86_64.rpm'
  cas "rpm remplacé par un autre sous le même nom" "sigmd5 différent du verrou" 'rm depot/bash-5.1.8-9.el9.x86_64.rpm && cp depot/alternatives-1.24-2.el9.x86_64.rpm depot/bash-5.1.8-9.el9.x86_64.rpm'
  cas "sigmd5 du verrou altéré" "sigmd5 différent du verrou" 'jq -c ".buildroot.rpms[0].sigmd5 = \"00000000000000000000000000000000\"" v.json > v2 && mv v2 v.json'
  cas "manifest.json du dossier dir: altéré" "différent du pull_digest" 'm=$(ls -d depot/sc-stockage.poc.test@*)/manifest.json && cp "$m" m && rm "$m" && { cat m; echo; } > "$m"'
  cas "repomd.xml absent" "repomd.xml absent" 'rm depot/repodata/repomd.xml'
  cas "nom en double dans le verrou" "en double" 'jq -c ".buildroot.rpms += [.buildroot.rpms[0]]" v.json > v2 && mv v2 v.json'
  cas "verrou vide" "verrou vide" 'jq -c ".buildroot.rpms = []" v.json > v2 && mv v2 v.json'

  echo "## construire-rpm, sur l'hôte : archive Source0 (section du pas, outils de l'hôte : $(tar --version | head -1), $(gzip --version | head -1))"
  rm -rf "$x/w"; mkdir -p "$x/w"
  { echo 'set -euo pipefail'; echo "e=$e"; echo "EPOQUE=$EPOQUE"
    sed -n '/^# Archive Source0/,/^echo "Source0/p' "$x/construire.sh"
  } | sed "s#/w/#$x/w/#g" > "$x/source0.sh"
  attendu "section de Source0 extraite (début, tar, fin)" "$(grep -c '^# Archive Source0\|--format=gnu -cf -\|^echo "Source0' "$x/source0.sh")" 3
  bash "$x/source0.sh" | sed 's/^/     /'
  attendu "Source0 égale à l'archive de sources.sh" "$(sha256sum < "$x/w/sources/sample-app-1.0.0.tar.gz" | cut -c1-64)" "$ARCHIVE_SHA"
  attendu "spec livré à mock égal au spec du dépôt" "$(cmp -s "$x/w/sources/sample-app.spec" "$SPEC" && echo égal || echo différent)" égal

  echo "## construire-rpm, sur l'hôte : layout écrit avec le rpm de M3 (section du pas), lu comme publier-image"
  rm -rf "$x/w" "$x/o"; mkdir -p "$x/w/res" "$x/o"
  cp "$RPM_M3" "$x/w/res/"
  { echo 'set -euo pipefail'; echo "o=$x/o"; echo "p=$x/w/res/${RPM_M3##*/}"
    sed -n '/^# Layout OCI à la main/,/^printf .sha256:%s/p' "$x/construire.sh" \
      | sed -e "s#/w/#$x/w/#g" -e "s#\$(results.DIGEST_CONSTRUIT.path)#$x/digest#g"
  } > "$x/layout.sh"
  attendu "section du layout extraite (début, fin)" "$(grep -c '^# Layout OCI à la main\|^printf .sha256:%s' "$x/layout.sh")" 2
  bash "$x/layout.sh" | sed 's/^/     /'
  rm -rf "$x/lu"; mkdir -p "$x/lu"; tar -xf "$x/o/image.tar" -C "$x/lu"
  s=$(sed -n 's/.*"digest": *"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' "$x/lu/index.json")   # sed de publier-image (comme s4d.sh)
  attendu "index.json lu comme publier-image : une ligne, égale au résultat" "$(wc -l <<< "$s") $s" "1 $(cat "$x/digest")"
  for a in "$x"/lu/blobs/sha256/*; do [ "$(sha256sum < "$a" | cut -c1-64)" = "${a##*/}" ] || { echo "KO   blob ${a##*/}" >&2; exit 1; }; done
  echo "OK   chaque blob a pour nom son sha256 ($(ls "$x/lu/blobs/sha256" | wc -l) blobs)"
  a=$x/lu/blobs/sha256/${s#sha256:}
  attendu "diff_ids égaux aux digests des couches" "$(jq -c '.rootfs.diff_ids' "$x/lu/blobs/sha256/$(jq -r '.config.digest' "$a" | cut -d: -f2)")" "$(jq -c '[.layers[].digest]' "$a")"
  attendu "couche : le rpm seul, en 0644, propriétaire 0" "$(tar -tvf "$x/lu/blobs/sha256/$(jq -r '.layers[0].digest' "$a" | cut -d: -f2)" | awk '{print $1, $2, $6}')" "-rw-r--r-- 0/0 ${RPM_M3##*/}"
  attendu "rpm de la couche égal au rpm de M3" "$(tar -xOf "$x/lu/blobs/sha256/$(jq -r '.layers[0].digest' "$a" | cut -d: -f2)" | sha256sum | cut -c1-64)" "$RPM_M3_SHA"
  echo "$s" > "$T/digest-attendu"
  echo "digest attendu de l'artefact, si le rpm est $RPM_M3_SHA et le tar de l'image d'outillage écrit la même couche : $s"

  echo "## entrées du pod d'essai"
  tar -C "$e" --sort=name -cf "$T/entrees.tar" fermeture sample-app.spec src verrou-rpm.json
  echo "entrees.tar : $(stat -c %s "$T/entrees.tar") octets, sha256 $(sha256sum < "$T/entrees.tar" | cut -c1-64)"
}

lancer m4c "05 M4c" "$@"
