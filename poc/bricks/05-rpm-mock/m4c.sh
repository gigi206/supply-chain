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
#   essai_preparer  ajoutée le 18/11/2026 (préparée à sec, accord permanent du 18/11), NON LANCÉE ; cluster (pod d'essai, rien dans
#               Zot) : pod runc restreint au label preparer-rpm ; les trois pas en initContainers, avec leurs images, leurs scripts
#               rendus et les montages de la tâche ; vrai clone de Forgejo et vrais pulls dans Zot ; résultats lus ; arbre entrees/
#               comparé à celui de prealables (contenu, modes, types) ; politiques de builds relues ; pod supprimé
#   essai       ajoutée de même, NON LANCÉE ; cluster (pod d'essai, rien dans Zot) : pod Kata au label construire-rpm, à la forme
#               que Tekton produira (contexte du podTemplate au niveau du pod, pas root privilégié au niveau du conteneur) ;
#               entrees.tar de prealables copié par morceaux de 64 Mio dans un volume à part, déballé par un second conteneur en UID
#               65532, monté en lecture seule pour mock ; script de construire-rpm tiré du gabarit rendu, variables de Tekton seules
#               substituées ; Source0, src.rpm, rpm et digest de l'artefact relevés contre M3 sans arrêter ; pod supprimé
#   taches      ajoutée le 18/11/2026 (préparée à sec, accord permanent du 18/11), NON LANCÉE ; Zot (bundles), rien dans le
#               cluster hors dry-run serveur : gabarits égaux à ceux des essais ; tâches et pipeline rendues admises, témoin
#               computeResources refusé ; preparer-rpm et construire-rpm signées et relues toutes deux (égalité au rendu, champs
#               de sécurité, scripts égaux à ceux des essais) avant tout versionnement sous construction/ et toute poussée (tag
#               m4c) ; SIGNER=1 : arrêt tant que la liste revue de la 08 ne porte pas les deux ; sinon : pipeline signée, bundle
#   pipeline    ajoutée le 18/11/2026 (préparée à sec, accord permanent du 18/11), NON LANCÉE ; cluster et Zot : deux PipelineRuns
#               de sample-app-rpm (bundle signé au tag m4c), podTemplate de M4b sans env, Kata pour la seule tâche construire ;
#               gardes avant toute création (pipeline relue au tag m4c, trois tâches dans la liste revue, politiques de builds,
#               dépôt builds/sample-app-rpm absent, aucun PipelineRun du même nom, disque de sc-stockage, dry-run serveur) ; rien
#               n'est purgé ; preuve imprimée avant toute assertion ; rpm comparé à celui de M3, artefact au digest du pod d'essai
#   comparaison ajoutée le 18/11/2026 (préparée à sec, accord permanent du 18/11), NON LANCÉE ; lecture seule (cluster lu, Zot
#               lu anonymement, rien n'est créé ni supprimé) : IMAGE_DIGEST des deux PipelineRuns relu, égal au digest de l'essai ;
#               artefact tiré une fois, par ce digest épinglé, dans un dossier neuf ; manifeste, configuration et couche égaux à ceux
#               de l'essai, couche au seul rpm ; rpm comparé à celui de M3 (sha256 et cmp) ; paquets du buildroot des deux
#               journaux archivés de construire contre le verrou
# Les étapes suivantes (taches, pipeline, comparaison, provenance) seront ajoutées après les essais.
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
  # Corrigé le 18/11/2026 après le second passage (rm refusé : le cache de modules de go est en lecture seule, comme sources.sh) :
  [ ! -d "$x" ] || chmod -R u+w "$x"
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

# Brique 05, M4c, étapes essai_preparer et essai (préparées à sec le 18/11/2026, accord permanent du 18/11) : pods d'essai avant
# toute signature (levier du 10/11/2026), sur le modèle de s4d.sh ; rien n'est écrit dans Zot.
LABEL_PREPARER=preparer-rpm
LABEL_CONSTRUIRE=construire-rpm   # sélectionné par construction-rpm-sans-sortie (M3)
SRPM_M3_SHA=c802e60a511c140e3a6761752b0c9966b2d8959a909d2a3b73d85f9b4bfd1128   # m3_comparaison
MORCEAU_MIO=64
ECARTS=0
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
liste_arbre() { # dans le répertoire courant : empreinte de chaque fichier, puis mode, type et chemin de chaque objet ; de s4d.sh
  echo 'find . -type f | xargs sha256sum | sort -k2; find . | xargs stat -c "%a %F %n" | sort -k3'
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

etape_essai_preparer() { # pod runc restreint au label preparer-rpm ; les trois pas en initContainers, images et montages de la tâche ;
  # vrai clone de Forgejo et vrais pulls dans Zot ; résultats lus ; arbre entrees/ comparé à celui de prealables ; pod supprimé
  local p=m4c-essai-preparer x=$T/essai-preparer a c r
  [ -d "$T/prealables/ws/entrees" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  rm -rf "$x"; mkdir -p "$x"
  rendre_taches
  for a in sources entrees assemblage; do
    script_etape "$T/preparer-rpm.yaml" "$a" | sed -e 's#\$(workspaces.sortie.path)#/workspace/sortie#g' \
      -e 's#\$(results\.\([A-Z_-]*\)\.path)#/resultats/\1#g' > "$x/$a.sh"
    attendu "script $a : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/$a.sh" || true)" 0
  done
  attendu "images des pas (gabarit rendu)" "$(yq '[.spec.steps[].image] | join(" ")' "$T/preparer-rpm.yaml")" "$PREFETCH_IMAGE $OUTILS_IMAGE $PREFETCH_IMAGE"
  politique_relue
  jq -n --arg n "$p" --arg lb "$LABEL_PREPARER" --arg pi "$PREFETCH_IMAGE" --arg oi "$OUTILS_IMAGE" --arg depot "$DEPOT_GIT" --arg commit "$COMMIT" \
    --arg fr "$FERMETURE_RPM" --arg fs "$FERMETURE_SOURCES" --arg pk "$PACKAGING" \
    --rawfile s1 "$x/sources.sh" --rawfile s2 "$x/entrees.sh" --rawfile s3 "$x/assemblage.sh" --arg liste "$(liste_arbre)" '
    {runAsUser: 65532, runAsNonRoot: true, allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}} as $sc
    | [{name: "ca-poc", mountPath: "/etc/ca-poc", readOnly: true}, {name: "tmp", mountPath: "/tmp"},
       {name: "sortie", mountPath: "/workspace/sortie"}, {name: "resultats", mountPath: "/resultats"}] as $vm
    | {requests: {cpu: "100m", memory: "128Mi"}, limits: {cpu: "1", memory: "1Gi"}} as $res
    | {apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"tekton.dev/task": $lb}},
      spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
        tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
        securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}},
        volumes: [{name: "ca-poc", configMap: {name: "ca-poc"}}, {name: "tmp", emptyDir: {}}, {name: "sortie", emptyDir: {}}, {name: "resultats", emptyDir: {}}],
        initContainers: [
          {name: "sources", image: $pi, command: ["/bin/sh", "-c", $s1], env: [{name: "DEPOT", value: $depot}, {name: "COMMIT", value: $commit}],
            securityContext: $sc, volumeMounts: $vm, resources: $res},
          {name: "entrees", image: $oi, command: ["/busybox/sh", "-c", $s2],
            env: [{name: "FERMETURE_RPM", value: $fr}, {name: "FERMETURE_SOURCES", value: $fs}, {name: "PACKAGING", value: $pk}],
            securityContext: $sc, volumeMounts: $vm, resources: $res},
          {name: "assemblage", image: $pi, command: ["/bin/sh", "-c", $s3], securityContext: $sc, volumeMounts: $vm, resources: $res}],
        containers: [{name: "liste", image: $oi, securityContext: $sc, volumeMounts: $vm, resources: $res,
          command: ["/busybox/sh", "-c", ("set -eu; for f in /resultats/*; do echo \"résultat ${f##*/} : $(cat \"$f\")\"; done; cd /workspace/sortie/entrees; echo ----- liste -----; " + $liste + "; echo ----- fin de la liste -----")]}]}}' > "$x/pod.json"
  trap 'kubectl delete pod -n builds m4c-essai-preparer --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true' EXIT
  kubectl delete pod -n builds "$p" --ignore-not-found --wait=true < /dev/null > /dev/null
  kubectl create --dry-run=server -f "$x/pod.json" < /dev/null > /dev/null || { echo "KO   pod $p refusé en dry-run serveur" >&2; exit 1; }
  echo "OK   pod $p admis en dry-run serveur"
  kubectl create -f "$x/pod.json" < /dev/null > /dev/null
  echo "pod $p créé à $(date -u +%H:%M:%S)"
  r=""
  for _ in $(seq 300); do
    r=$(kubectl get pod -n builds "$p" -o jsonpath='{.status.phase}' < /dev/null)
    case $r in Succeeded|Failed) break ;; esac; sleep 2
  done
  echo "pod $p : $r à $(date -u +%H:%M:%S), sur $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}, runtimeClassName « {.spec.runtimeClassName} »' < /dev/null)"
  for c in sources entrees assemblage liste; do
    kubectl logs -n builds "$p" -c "$c" < /dev/null 2>&1 | sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' > "$x/$c.log" || true
    echo "### $c (code $(kubectl get pod -n builds "$p" -o json < /dev/null | jq -r --arg c "$c" '[.status.initContainerStatuses[]?, .status.containerStatuses[]?] | map(select(.name == $c)) | .[0].state.terminated.exitCode // "-"'))"
    if [ "$c" = liste ]; then grep -v -e '^-----' -e '^[0-9a-f]\{64\} ' -e '^[0-7]\{3,4\} ' "$x/$c.log" | sed 's/^/     /' || true
    else sed 's/^/     /' "$x/$c.log" | tail -n 12; fi
  done
  cat "$x"/{sources,entrees,assemblage,liste}.log > "$R/m4c-essai-preparer-pod.log"
  pod_retirer "$p"
  attendu "pod d'essai de preparer-rpm" "$r" Succeeded
  attendu "résultat CHAINS-GIT_URL" "$(sed -n 's/^résultat CHAINS-GIT_URL : //p' "$x/liste.log")" "$DEPOT_GIT"
  attendu "résultat CHAINS-GIT_COMMIT" "$(sed -n 's/^résultat CHAINS-GIT_COMMIT : //p' "$x/liste.log")" "$COMMIT"
  for a in "FERMETURE_RPM $FERMETURE_RPM" "FERMETURE_SOURCES $FERMETURE_SOURCES" "PACKAGING $PACKAGING"; do
    set -- $a
    attendu "résultat $1_ARTIFACT_INPUTS" "$(sed -n "s/^résultat $1_ARTIFACT_INPUTS : //p" "$x/liste.log")" "{\"uri\":\"oci://${2%@*}\",\"digest\":\"${2#*@}\"}"
  done
  sed -n '/^----- liste -----$/,/^----- fin de la liste -----$/p' "$x/liste.log" | sed '1d;$d' > "$x/arbre-pod.txt"
  (cd "$T/prealables/ws/entrees" && sh -c "$(liste_arbre)") > "$x/arbre-hote.txt"
  echo "arbre entrees/ : $(grep -c '^[0-9a-f]\{64\} ' "$x/arbre-pod.txt") fichiers dans le pod, $(grep -c '^[0-9a-f]\{64\} ' "$x/arbre-hote.txt") dans prealables"
  diff "$x/arbre-hote.txt" "$x/arbre-pod.txt" | head -n 20 | cut -c1-200 | sed 's/^/     /' || true
  attendu "arbre entrees/ du pod égal à celui de prealables (contenu, modes, types)" "$(cmp -s "$x/arbre-hote.txt" "$x/arbre-pod.txt" && echo égal || echo différent)" égal
}

etape_essai() { # pod Kata au label construire-rpm, à la forme que Tekton produira : contexte du podTemplate au niveau du pod (UID
  # 65532, runAsNonRoot), pas root privilégié au niveau du conteneur ; entrées sur un volume à part, remplies par un second
  # conteneur en UID 65532 et montées en lecture seule dans le conteneur de mock ; script de construire-rpm tiré du gabarit rendu,
  # variables de Tekton seules substituées ; image.tar rapatrié ; écarts à M3 relevés sans arrêter ; pod supprimé
  local p=m4c-essai x=$T/essai rc=0 d s
  [ -s "$T/entrees.tar" ] && [ -s "$T/digest-attendu" ] || { echo "KO   lancer d'abord prealables" >&2; exit 1; }
  rm -rf "$x"; mkdir -p "$x"
  rendre_taches
  script_etape "$T/construire-rpm.yaml" construire \
    | sed -e 's#\$(workspaces.entrees.path)#/e#g' -e 's#\$(workspaces.sortie.path)#/o#g' -e 's#\$(results.DIGEST_CONSTRUIT.path)#/w/digest#g' > "$x/construire.sh"
  attendu "script d'essai : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/construire.sh" || true)" 0
  attendu "script d'essai : égal au script du gabarit, variables de Tekton exceptées" \
    "$(diff <(script_etape "$T/construire-rpm.yaml" construire) "$x/construire.sh" | grep -c '^>' || true)" 3
  politique_relue
  jq -n --arg n "$p" --arg lb "$LABEL_CONSTRUIRE" --arg i "$IMAGE_OUTILLAGE" --arg ep "$EPOQUE" \
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
  trap 'kubectl delete pod -n builds m4c-essai --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true' EXIT
  kubectl create --dry-run=server -f "$x/pod.json" < /dev/null > /dev/null || { echo "KO   pod $p refusé en dry-run serveur" >&2; exit 1; }
  echo "OK   pod $p admis en dry-run serveur"
  kubectl create -f "$x/pod.json" < /dev/null > /dev/null
  echo "pod $p créé à $(date -u +%H:%M:%S) (image $IMAGE_OUTILLAGE)"
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
  sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' "$x/construire.log" > "$R/m4c-essai-construire.log"
  grep -v '^paquet ' "$R/m4c-essai-construire.log" | cut -c1-220 | sed 's/^/     /'
  echo "     (code de l'exec : $rc ; journal complet : resultats/m4c-essai-construire.log)"
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
  mesure "digest de l'artefact" "$d" "$(cat "$T/digest-attendu")"
  echo "relevé : paquets du buildroot imprimés : $(grep -c '^paquet ' "$x/construire.log" || true) ; écarts au verrou (nom, version, release, arch, sigmd5) : $(diff <(grep '^paquet ' "$x/construire.log") <(jq -r '.buildroot.rpms[] | "paquet \(.name) \(.version) \(.release) \(.arch) \(.sigmd5)"' "$VERROU" | sort) | grep -c '^[<>]' || true)"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

# Brique 05, M4c, étape taches (préparée à sec le 18/11/2026, accord permanent du 18/11) : sur le modèle de l'étape taches de M4b
# (contenu signé relu avant tout versionnement), pour deux tâches : les deux sont signées et relues avant que l'une soit versionnée
# ou poussée. Gabarits : ceux des essais (f66229a), à l'octet près. Scripts : ceux joués dans les pods d'essai (resultats/m4c-essai-scripts).
GABARITS_SHA="preparer-rpm.yaml:a7dfa37e23948209c6b63c815eef1d41fc9ae5404fed3de4708e4167920ad9bc
construire-rpm.yaml:e88f5521ede87f5b03330683939fd3494f5ff58544ded9a9326014e30b8d0f88
sample-app-rpm.yaml:a9917a65c994421f25735c03971906e99aac7982821185a135535910f0e8f7cd"   # construction/ à f66229a, inchangés aux essais
SCRIPTS_ESSAI_SHA="preparer-rpm-sources:3f33ababe1f86b396db5df57f5f78e197014f25e5711ac4fdf152ff2cebc7681
preparer-rpm-entrees:6a33e3b1cf31b5240eda0a956746692b33592635272d6f4b9ff69acfe7129728
preparer-rpm-assemblage:554e0dba399a26bc596c5ae749e940c549b590f6067d6857eafc0a4abd35306d
construire-rpm-construire:0b119024e9aa29dd21b486efd9f4951ee6e15b004ed816dbbc089e97d24aac3c"   # $T/essai-preparer/*.sh, $T/essai/construire.sh
LIBRE_MIN=1073741824   # garde : octets libres sur / de sc-stockage (porte /var/lib/zot) avant toute poussée, comme l'étape rpm de M4b
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
scripts_substitues() { # tâche dossier : scripts des pas, variables de Tekton substituées par les expressions des essais
  local a
  case $(yq .metadata.name "$1") in
    preparer-rpm) for a in sources entrees assemblage; do
        script_etape "$1" "$a" | sed -e 's#\$(workspaces.sortie.path)#/workspace/sortie#g' \
          -e 's#\$(results\.\([A-Z_-]*\)\.path)#/resultats/\1#g' > "$2/preparer-rpm-$a.sh"; done ;;
    construire-rpm) script_etape "$1" construire \
        | sed -e 's#\$(workspaces.entrees.path)#/e#g' -e 's#\$(workspaces.sortie.path)#/o#g' -e 's#\$(results.DIGEST_CONSTRUIT.path)#/w/digest#g' \
        > "$2/construire-rpm-construire.sh" ;;
  esac
}
controler_tache() { # tâche-signée : contenu signé relu (signature, égalité au rendu, champs de sécurité, scripts des essais)
  local f=$1 n e s x=$T/scripts-signes o
  n=$(yq .metadata.name "$f"); mkdir -p "$x"; o=$x/$n.json
  attendu "$n signée : annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$f")" true
  normaliser "$f" > "$o"
  attendu "$n signée : égale à la tâche rendue, signature exceptée (normalisées)" "$(cmp -s "$o" <(normaliser "$T/$n.yaml") && echo égale || echo différente)" égale
  case $n in
    "$LABEL_PREPARER")
      attendu "$n signée : images des pas" "$(yq -p=json -o=yaml '[.spec.steps[].image] | join(" ")' "$o")" "$PREFETCH_IMAGE $OUTILS_IMAGE $PREFETCH_IMAGE"
      attendu "$n signée : contexte et montages du stepTemplate" "$(yq -p=json -o=json -I=0 '.spec.stepTemplate' "$o")" \
        '{"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true,"runAsUser":65532},"volumeMounts":[{"mountPath":"/etc/ca-poc","name":"ca-poc","readOnly":true},{"mountPath":"/tmp","name":"tmp"}]}'
      attendu "$n signée : pas (contexte, ressources, computeResources, env, montages propres)" \
        "$(yq -p=json -o=json -I=0 '[.spec.steps[] | [.name, has("securityContext"), has("resources"), has("computeResources"), ((.env // []) | map(.name + "=" + .value)), (.volumeMounts // [])]]' "$o")" \
        '[["sources",false,false,false,["DEPOT=$(params.depot)","COMMIT=$(params.commit)"],[]],["entrees",false,false,false,["FERMETURE_RPM=$(params.fermeture-rpm)","FERMETURE_SOURCES=$(params.fermeture-sources)","PACKAGING=$(params.packaging)"],[]],["assemblage",false,false,false,[],[]]]'
      attendu "$n signée : paramètres, workspaces, résultats, volumes" \
        "$(yq -p=json -o=json -I=0 '[[.spec.params[].name], .spec.workspaces, [.spec.results[] | .name + ":" + .type + ":" + ((.properties // {}) | keys | join(","))], .spec.volumes]' "$o")" \
        '[["depot","commit","fermeture-rpm","fermeture-sources","packaging"],[{"name":"sortie"}],["CHAINS-GIT_URL:string:","CHAINS-GIT_COMMIT:string:","FERMETURE_RPM_ARTIFACT_INPUTS:object:digest,uri","FERMETURE_SOURCES_ARTIFACT_INPUTS:object:digest,uri","PACKAGING_ARTIFACT_INPUTS:object:digest,uri"],[{"configMap":{"name":"ca-poc"},"name":"ca-poc"},{"emptyDir":{},"name":"tmp"}]]' ;;
    "$LABEL_CONSTRUIRE")
      attendu "$n signée : image du pas" "$(yq -p=json -o=yaml '[.spec.steps[].image] | join(" ")' "$o")" "$IMAGE_OUTILLAGE"
      attendu "$n signée : contexte du pas (root privilégié, comme l'essai), aucun stepTemplate" \
        "$(yq -p=json -o=json -I=0 '[.spec.steps[0].securityContext, (.spec | has("stepTemplate"))]' "$o")" \
        '[{"allowPrivilegeEscalation":true,"privileged":true,"runAsGroup":0,"runAsNonRoot":false,"runAsUser":0},false]'
      attendu "$n signée : ressources du pas (resources de v1beta1), aucun computeResources" \
        "$(yq -p=json -o=json -I=0 '[.spec.steps[0].resources, ([.. | select(tag == "!!map") | keys[] | select(. == "computeResources")] | length)]' "$o")" \
        '[{"limits":{"cpu":"2","memory":"6Gi"},"requests":{"cpu":"2","memory":"6Gi"}},0]'
      attendu "$n signée : env et montages du pas" "$(yq -p=json -o=json -I=0 '[.spec.steps[] | [.name, ((.env // []) | map(.name + "=" + .value)), .volumeMounts]]' "$o")" \
        '[["construire",["EPOQUE=$(params.epoque)"],[{"mountPath":"/w","name":"w"}]]]'
      attendu "$n signée : paramètres, workspaces (entrées en lecture seule), résultats, volumes" \
        "$(yq -p=json -o=json -I=0 '[[.spec.params[].name], .spec.workspaces, [.spec.results[] | .name + ":" + .type], .spec.volumes]' "$o")" \
        '[["epoque"],[{"name":"entrees","readOnly":true},{"name":"sortie"}],["DIGEST_CONSTRUIT:string"],[{"emptyDir":{"medium":"Memory","sizeLimit":"4Gi"},"name":"w"}]]' ;;
    *) echec "tâche signée inattendue : $n" ;;
  esac
  scripts_substitues "$f" "$x"
  for e in $SCRIPTS_ESSAI_SHA; do
    case ${e%%:*} in "$n"-*) ;; *) continue ;; esac
    s=$(sha256sum < "$x/${e%%:*}.sh" | cut -c1-64)
    attendu "$n signée : script ${e%%:*}, substitué, égal à celui joué à l'essai (sha256)" "$s" "${e#*:}"
  done
}
versionner() { # tâche : signature versionnée sous construction/ (SIGNER=1 : écrite si absente ou si le contenu hors signature change)
  local n=$1 v=$C/$1.signee.yaml
  if [ -n "${SIGNER:-}" ] && ! { [ -s "$v" ] && cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v"); }; then
    cp "$T/$n-signee.yaml" "$v"; echo "SIGNER : nouvelle signature dans construction/$n.signee.yaml"
  fi
  [ -s "$v" ] || echec "$n : signature versionnée absente : SIGNER=1, puis revue de la liste"
  attendu "$n : signature versionnée conforme au gabarit rendu, signature exceptée" \
    "$(cmp -s <(grep -v 'tekton.dev/signature:' "$T/$n-signee.yaml") <(grep -v 'tekton.dev/signature:' "$v") && echo conforme || echo différente)" conforme
  echo "construction/$n.signee.yaml : sha256 $(sha256sum < "$v" | cut -c1-64)"
}

etape_taches() { # SIGNER=1 : preparer-rpm et construire-rpm signées, relues, versionnées, bundles, à ajouter à la liste revue ;
  # une fois les deux listées : de plus la pipeline sample-app-rpm, rendue avec leurs références, signée, relue, bundle
  local e n r l=0 libre p
  [ -s "$S/taches.key" ] || echec "clé des tâches absente"
  attendu "publier-image, lue dans la liste revue" "$(ref_revue publier-image d21931f3)" "$PUBLIER_REF"
  for e in $GABARITS_SHA; do
    attendu "gabarit ${e%%:*} égal à celui des essais (sha256)" "$(sha256sum < "$C/${e%%:*}" | cut -c1-64)" "${e#*:}"
  done
  echo "## gabarits rendus (tâches factices dans la pipeline) ; admission en dry-run serveur, rien n'est créé"
  rendre_taches
  rendre_pipeline "$REG/tekton/tasks/preparer-rpm@$FACTICE" "$REG/tekton/tasks/construire-rpm@$FACTICE" "$PUBLIER_REF"
  for n in preparer-rpm construire-rpm sample-app-rpm; do attendu "$n rendue admise (code de kubectl)" "$(admission "$T/$n.yaml")" 0; done
  yq '.spec.steps[0].computeResources = .spec.steps[0].resources | del(.spec.steps[0].resources)' "$T/construire-rpm.yaml" > "$T/temoin-v1beta1.yaml"
  [ "$(admission "$T/temoin-v1beta1.yaml")" != 0 ] || echec "témoin (computeResources dans un pas v1beta1) admis : le dry-run ne contrôle plus le nom du champ"
  attendu "témoin refusé : champ inconnu (message mesuré le 18/11 en M4b, m4b-taches-admission.log)" \
    "$(grep -c -F 'strict decoding error: unknown field "spec.steps[0].computeResources"' "$T/admission.out")" 1
  echo "## signatures (tkn $(tkn version --component client)) ; les deux tâches relues avant tout versionnement et toute poussée"
  for n in preparer-rpm construire-rpm; do tkn task sign "$T/$n.yaml" -K "$S/taches.key" -f "$T/$n-signee.yaml" > /dev/null; done
  for n in preparer-rpm construire-rpm; do controler_tache "$T/$n-signee.yaml"; done
  libre=$(libre_zot)
  echo "relevé : octets libres sur / de sc-stockage (porte /var/lib/zot) avant les poussées : $libre"
  [ "$libre" -ge "$LIBRE_MIN" ] 2> /dev/null || echec "octets libres sur / de sc-stockage sous $LIBRE_MIN : $libre"
  for n in preparer-rpm construire-rpm; do versionner "$n"; done
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundles (commun.sh), compte poc-ecriture
  for n in preparer-rpm construire-rpm; do
    r=$REG/tekton/tasks/$n@$(bundle "$C/$n.signee.yaml" "tekton/tasks/$n" m4c)
    echo "$r" > "$T/$n.ref"
    if listee "$r"; then echo "OK   $n dans la liste revue : $r"; l=$((l + 1))
    elif [ -n "${SIGNER:-}" ]; then echo "SIGNER : à ajouter à politique/porte/taches.yml (08) après revue du propriétaire : $r"
    else echec "$n absente de la liste revue : $r"; fi
  done
  [ "$l" = 2 ] || { echo "SIGNER : pipeline non signée tant que la liste revue n'a pas été acceptée"; return 0; }
  echo "## pipeline sample-app-rpm, tâches de la liste revue"
  rendre_pipeline "$(cat "$T/preparer-rpm.ref")" "$(cat "$T/construire-rpm.ref")" "$PUBLIER_REF"
  attendu "pipeline rendue (références réelles) admise (code de kubectl)" "$(admission "$T/sample-app-rpm.yaml")" 0
  attendu "pipeline : références des tâches" \
    "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$T/sample-app-rpm.yaml")" \
    "$(cat "$T/preparer-rpm.ref") $(cat "$T/construire-rpm.ref") $PUBLIER_REF"
  tkn pipeline sign "$T/sample-app-rpm.yaml" -K "$S/taches.key" -f "$T/sample-app-rpm-signee.yaml" > /dev/null
  attendu "pipeline signée : annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$T/sample-app-rpm-signee.yaml")" true
  attendu "pipeline signée : égale à la pipeline rendue et relue, signature exceptée" \
    "$(cmp -s <(normaliser "$T/sample-app-rpm-signee.yaml") <(normaliser "$T/sample-app-rpm.yaml") && echo égale || echo différente)" égale
  p=$REG/tekton/pipelines/sample-app-rpm@$(bundle "$T/sample-app-rpm-signee.yaml" tekton/pipelines/sample-app-rpm m4c)
  echo "$p" | tee "$T/sample-app-rpm.ref"
}

# Brique 05, M4c, étape pipeline (préparée à sec le 18/11/2026, accord permanent du 18/11) : sur le modèle de l'étape rpm de M4b
# (gardes avant toute création, rien n'est purgé, preuve imprimée avant toute assertion, jamais le message d'une condition ni une
# variable d'environnement), deux PipelineRuns de sample-app-rpm. podTemplate de M4b (ni env) ; Kata pour la seule tâche construire
# (taskRunSpecs, comme s4d.sh de la 06). Référence de l'artefact : le digest du pod d'essai (resultats/m4c-essai.log, tar de l'image
# d'outillage), non celui de prealables (tar de l'hôte, $T/digest-attendu).
PIPELINE_REF=$REG/tekton/pipelines/sample-app-rpm@sha256:ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be   # a56a85b
PREPARER_REF=$REG/tekton/tasks/preparer-rpm@sha256:2f65f3903e98caa9944ab3fee4b67585b15d67ad477ff48a8487e8e86af5526f       # liste revue (1d5e27d)
CONSTRUIRE_REF=$REG/tekton/tasks/construire-rpm@sha256:d7f01398f188931c124273c8b5fb60e2a66c22e9d0a2dfcd229ecadee1e62164   # liste revue (1d5e27d)
DIGEST_ESSAI=sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119   # essai (148049f)
PVC_TAILLE=2Gi   # entrees/ de prealables : 318 609 833 octets ; image.tar de l'essai : 2 191 360 octets
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'
pr_m4c() { # nom : PipelineRun de sample-app-rpm ; podTemplate de M4b (nodeSelector, tolérance, contexte de sécurité ; ni env) ;
  # Kata pour la seule tâche construire (taskRunSpecs) ; workspace sortie sur un PVC de $PVC_TAILLE
  jq -n --arg n "$1" --arg b "$PIPELINE_REF" --arg c "$COMMIT" --arg u "$DEPOT_GIT" --arg t "$PVC_TAILLE" '
    {nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: "RuntimeDefault"}}} as $z
    | {apiVersion: "tekton.dev/v1", kind: "PipelineRun", metadata: {name: $n, namespace: "builds"},
      spec: {pipelineRef: {resolver: "bundles", params: [{name: "bundle", value: $b}, {name: "name", value: "sample-app-rpm"},
          {name: "kind", value: "pipeline"}]},
        params: [{name: "commit", value: $c}, {name: "depot", value: $u}],
        workspaces: [{name: "sortie", volumeClaimTemplate: {spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: $t}}}}}],
        taskRunTemplate: {serviceAccountName: "build", podTemplate: $z},
        taskRunSpecs: [{pipelineTaskName: "construire", podTemplate: ($z + {runtimeClassName: "kata"})}]}}' > "$T/pr-$1.json"
}
statut_pr() { # nom : « statut|raison » de la condition Succeeded (jamais le message) ; m4b.sh
  kubectl get pipelinerun -n builds "$1" -o json < /dev/null | jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "")|\(.reason // "")"'
}
attendre_pr() { # nom : attend la fin (3600 s au plus) ; « statut|raison » ; m4b.sh
  local st=""
  for _ in $(seq 1800); do
    st=$(statut_pr "$1"); case $st in True\|*|False\|*) break ;; esac; sleep 2
  done
  echo "$st"
}
releve_pod() { # pod : nœud, runtimeClassName, label ; conteneurs d'initialisation et de pas (état, code, raison) ; ressources.
  # Jamais de message ni de variable d'environnement (m4b.sh, sans le relevé de place-scripts).
  kubectl get pod -n builds "$1" -o json < /dev/null > "$T/pod-$1.json" || { echo "     pod $1 illisible"; return 0; }
  jq -r '"     pod \(.metadata.name) : nœud \(.spec.nodeName // "-"), runtimeClassName « \(.spec.runtimeClassName // "") », tekton.dev/task \(.metadata.labels["tekton.dev/task"] // "-"), phase \(.status.phase // "-")",
    ((.status.initContainerStatuses // []) + (.status.containerStatuses // []) | .[] |
      "     conteneur \(.name) : \(.state | to_entries[0] | "\(.key) code \(.value.exitCode // "-") raison \(.value.reason // "-")")"),
    ((.spec.initContainers // []) + .spec.containers | .[] |
      "     ressources \(.name) : demandes \(.resources.requests // {} | tojson) ; limites \(.resources.limits // {} | tojson)")' "$T/pod-$1.json"
}
lignes() { grep -c -- "$1" "$2" || true; }   # motif fichier : nombre de lignes

etape_pipeline() { # deux PipelineRuns de sample-app-rpm (m4c-rpm-1, puis m4c-rpm-2) ; rien n'est purgé ; artefact comparé à l'essai
  local i pr r t p d u c k l x j g
  echo "## gardes, avant toute création"
  [ -s "$T/sample-app-rpm.ref" ] || echec "référence de la pipeline absente (étape taches)"
  attendu "pipeline écrite par l'étape taches" "$(cat "$T/sample-app-rpm.ref")" "$PIPELINE_REF"
  attendu "pipeline relue dans Zot au tag m4c (lecture anonyme)" \
    "$REG/tekton/pipelines/sample-app-rpm@$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/tekton/pipelines/sample-app-rpm:m4c" < /dev/null | jq -r .digest)" \
    "$PIPELINE_REF"
  for r in "$PREPARER_REF" "$CONSTRUIRE_REF" "$PUBLIER_REF"; do
    if listee "$r"; then echo "OK   dans la liste revue : $r"; else echec "absente de la liste revue : $r"; fi
  done
  politique_relue
  for i in 1 2; do
    pr=m4c-rpm-$i
    echo "## $pr"
    if [ "$i" = 1 ]; then
      r=$(oras repo tags --ca-file "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}" < /dev/null 2>&1 || true)
      attendu "dépôt $IMAGE absent avant le premier PipelineRun" "$(grep -c 'name unknown' <<< "$r")" 1
    fi
    r=0; kubectl get pipelinerun -n builds "$pr" -o name < /dev/null > /dev/null 2>&1 || r=$?
    [ "$r" != 0 ] || echec "$pr existe déjà : rien n'est purgé, décision avant toute relance"
    l=$(libre_zot)
    echo "/ de sc-stockage : $l octets libres à $(date -u +%H:%M:%S) (garde : $LIBRE_MIN)"
    if ! [[ $l =~ ^[0-9]+$ ]] || [ "$l" -lt "$LIBRE_MIN" ]; then echec "espace libre illisible ou sous la garde sur sc-stockage"; fi
    pr_m4c "$pr"
    attendu "$pr : podTemplate commun sans env ; Kata pour construire seule" \
      "$(jq -c '[(.spec.taskRunTemplate.podTemplate | has("env")), [.spec.taskRunSpecs[] | .pipelineTaskName + ":" + (.podTemplate.runtimeClassName // "")]]' "$T/pr-$pr.json")" \
      '[false,["construire:kata"]]'
    attendu "$pr admis en dry-run serveur (ni résolveur, ni signatures, ni pods) : code de kubectl" "$(admission "$T/pr-$pr.json")" 0
    kubectl create -f "$T/pr-$pr.json" < /dev/null > /dev/null
    echo "$pr créé à $(date -u +%H:%M:%S) ($PIPELINE_REF)"
    r=$(attendre_pr "$pr")
    echo "$pr : condition Succeeded « $r », relevée à $(date -u +%H:%M:%S)"
    kubectl get pipelinerun -n builds "$pr" -o json < /dev/null > "$T/pr-$pr-etat.json"
    jq -r '"     début \(.status.startTime // "-") ; fin \(.status.completionTime // "-")"' "$T/pr-$pr-etat.json"
    for t in $(kubectl get taskrun -n builds -l "tekton.dev/pipelineRun=$pr" -o jsonpath='{.items[*].metadata.name}' < /dev/null); do
      kubectl get taskrun -n builds "$t" -o json < /dev/null > "$T/tr-$t.json"
      k=$(jq -r '.metadata.labels["tekton.dev/pipelineTask"] // "-"' "$T/tr-$t.json")
      p=$(jq -r '.status.podName // ""' "$T/tr-$t.json")
      echo "### TaskRun $t (tâche $k) : $(jq -r '[.status.conditions[]? | select(.type == "Succeeded")][0] // {} | "\(.status // "-")|\(.reason // "-")"' "$T/tr-$t.json") ; début $(jq -r '.status.startTime // "-"' "$T/tr-$t.json") ; fin $(jq -r '.status.completionTime // "-"' "$T/tr-$t.json")"
      jq -r '.status.results[]? | "     résultat \(.name) : \(.value | if type == "string" then . else tojson end)"' "$T/tr-$t.json"
      cp "$T/tr-$t.json" "$T/$pr-$k.tr.json"
      [ -n "$p" ] || { echo "     aucun pod"; continue; }
      echo "$p" > "$T/$pr-$k.pod"
      releve_pod "$p"
      for c in $(jq -r '.spec.containers[].name' "$T/pod-$p.json"); do
        kubectl logs -n builds "$p" -c "$c" < /dev/null 2>&1 | sed "$MASQUE" > "$T/$pr-$k-$c.log" || true
        echo "     journal de $c : $(wc -l < "$T/$pr-$k-$c.log") lignes, dont $(lignes '^paquet ' "$T/$pr-$k-$c.log") « paquet » (non répétées)"
        grep -v '^paquet \|^\s*$' "$T/$pr-$k-$c.log" | cut -c1-240 | sed 's/^/       /'
      done
    done
    jq -r '.status.results[]? | "résultat de \(.name) : \(.value)"' "$T/pr-$pr-etat.json"
    x=$T/$pr-construire-step-construire.log
    [ ! -f "$x" ] || cp "$x" "$R/m4c-pipeline-$i-construire.log"
    attendu "PipelineRun $pr" "$r" "True|Succeeded"
    for j in preparer:preparer-rpm: construire:construire-rpm:kata publier:publier-image:; do
      IFS=: read -r k g c <<< "$j"
      attendu "$pr, $k : tekton.dev/task|runtimeClassName|nœud" \
        "$(jq -r '"\(.metadata.labels["tekton.dev/task"] // "")|\(.spec.runtimeClassName // "")|\(.spec.nodeName // "")"' "$T/pod-$(cat "$T/$pr-$k.pod").json")" "$g|$c|sc-build"
    done
    attendu "preparer : CHAINS-GIT_URL et CHAINS-GIT_COMMIT" \
      "$(jq -r '[.status.results[] | select(.name | startswith("CHAINS-GIT_")) | .name + "=" + .value] | sort | join(" ")' "$T/$pr-preparer.tr.json")" \
      "CHAINS-GIT_COMMIT=$COMMIT CHAINS-GIT_URL=$DEPOT_GIT"
    for j in "FERMETURE_RPM $FERMETURE_RPM" "FERMETURE_SOURCES $FERMETURE_SOURCES" "PACKAGING $PACKAGING"; do
      read -r k g <<< "$j"
      attendu "preparer : ${k}_ARTIFACT_INPUTS (clés triées)" \
        "$(jq -cS --arg n "${k}_ARTIFACT_INPUTS" '.status.results[] | select(.name == $n) | .value' "$T/$pr-preparer.tr.json")" \
        "$(jq -cnS --arg s "$g" '{uri: ("oci://" + ($s | sub("@.*$"; ""))), digest: ($s | sub("^.*@"; ""))}')"
    done
    attendu "construire : écriture refusée sur les entrées (ligne du script atteinte)" "$(lignes '^invité : .*, écriture refusée$' "$x")" 1
    attendu "construire : témoins réseau en échec" "$(lignes '^témoin .* : échec, code [0-9]* (attendu)$' "$x")" 4
    attendu "construire : fermeture confrontée au verrou (222 rpm)" "$(lignes '^fermeture confrontée au verrou : 222 rpm (noms et sigmd5)' "$x")" 1
    attendu "construire : mock --hermetic-build rc 0" "$(lignes '^mock --hermetic-build : rc 0 en [0-9]* s$' "$x")" 1
    attendu "construire : aucun repli en chroot" "$(lignes '^lignes « falling back to chroot installation » : sortie 0 ; root.log 0$' "$x")" 1
    attendu "construire : aucune ligne http ou https (mock.out, root.log, build.log)" "$(lignes '^lignes http ou https de [a-z.]* : 0$' "$x")" 3
    attendu "construire : dernière ligne du script atteinte (image.tar)" "$(lignes '^image.tar : [0-9]* octets$' "$x")" 1
    mesure "construire : Source0 égale à l'archive de sources.sh" \
      "$(sed -n 's/^Source0 sample-app-1.0.0.tar.gz (époque [0-9]*) : \([0-9a-f]\{64\}\) ;.*/\1/p' "$x")" "$ARCHIVE_SHA"
    mesure "construire : src.rpm égal à celui de M3" "$(sed -n 's/^rpm : [^ ]*\.src\.rpm sha256 \([0-9a-f]\{64\}\) .*/\1/p' "$x")" "$SRPM_M3_SHA"
    mesure "construire : rpm égal à celui de M3" "$(sed -n 's/^rpm : [^ ]*\.x86_64\.rpm sha256 \([0-9a-f]\{64\}\) .*/\1/p' "$x")" "$RPM_M3_SHA"
    echo "relevé : paquets du buildroot imprimés : $(lignes '^paquet ' "$x") ; écarts au verrou (nom, version, release, arch, sigmd5) : $(diff <(grep '^paquet ' "$x") <(jq -r '.buildroot.rpms[] | "paquet \(.name) \(.version) \(.release) \(.arch) \(.sigmd5)"' "$VERROU" | sort) | grep -c '^[<>]' || true)"
    u=$(jq -r '.status.results[] | select(.name == "IMAGE_URL") | .value' "$T/pr-$pr-etat.json")
    d=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$T/pr-$pr-etat.json")
    echo "$d" > "$T/rpm-$i.digest"
    attendu "dépôt publié" "$u" "$IMAGE"
    attendu "construire : DIGEST_CONSTRUIT égal au digest publié" \
      "$(jq -r '.status.results[] | select(.name == "DIGEST_CONSTRUIT") | .value' "$T/$pr-construire.tr.json")" "$d"
    attendu "publier : ligne de publication" "$(lignes "^publiée : $IMAGE@$d (relue en lecture anonyme)$" "$T/$pr-publier-step-publier.log")" 1
    attendu "manifeste relu dans Zot (lecture anonyme) : digest du descripteur, couches" \
      "$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}@$d" < /dev/null | jq -r .digest) $(
        oras manifest fetch --ca-file "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}@$d" < /dev/null | jq '.layers | length')" "$d 1"
    mesure "digest de l'artefact égal à celui du pod d'essai" "$d" "$DIGEST_ESSAI"
    attendu "PipelineRun $pr signé par Chains" "$(signe pipelinerun "$pr")" true
    echo "/ de sc-stockage : $(libre_zot) octets libres à $(date -u +%H:%M:%S)"
  done
  mesure "deux exécutions, même artefact" "$(cat "$T/rpm-2.digest")" "$(cat "$T/rpm-1.digest")"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

# Brique 05, M4c, étape comparaison (préparée à sec le 18/11/2026, accord permanent du 18/11) : lecture seule, sur le modèle de
# etape_comparaison (s4d.sh de la 06) ; les deux PipelineRuns ont publié le même digest : un seul tirage, par la constante épinglée.
COUCHE_ESSAI=sha256:ac3e3ef14c6e54fbba4f297b00f32bfeff840ef9bbe55a1a95bda853ee55e8e4   # couche du pod d'essai (tar 1.34 de l'image)
COUCHE_TAILLE=2181120
CONFIG_ESSAI=sha256:48c5e33207f73ac7907cfae080f9fbd0a501d79565d06905688b351a53aa0cc4   # configuration du pod d'essai
RPM_NOM=sample-app-1.0.0-2.el9.x86_64.rpm
RPM_TAILLE=2173376
confronter_artefact() { # layout travail : manifeste, configuration, couche et rpm confrontés à l'essai et à M3 ; hors ligne (banc)
  local L=$1 a=$2 m g l
  m=$L/blobs/sha256/${DIGEST_ESSAI#sha256:}
  echo "blobs : $(find "$L/blobs" -type f | wc -l) ; index : $(jq -c '[.manifests[]? | {mediaType, digest}]' "$L/index.json" 2>&1)"
  [ -f "$m" ] || echec "manifeste $DIGEST_ESSAI absent du layout"
  echo "manifeste : $(jq -c '{mediaType, config: (.config | {mediaType, digest, size}), layers: [.layers[]? | {mediaType, digest, size}]}' "$m" 2>&1)"
  attendu "manifeste : sha256 des octets lus" "sha256:$(sha256sum < "$m" | cut -c1-64)" "$DIGEST_ESSAI"
  attendu "blobs du layout" "$(find "$L/blobs" -type f | wc -l)" 3
  attendu "manifeste : types, nombre de couches" "$(jq -r '[.mediaType, .config.mediaType, (.layers | length), .layers[0].mediaType] | join(" ")' "$m")" \
    "application/vnd.oci.image.manifest.v1+json application/vnd.oci.image.config.v1+json 1 application/vnd.oci.image.layer.v1.tar"
  attendu "manifeste : couche (digest et taille), celle de l'essai" "$(jq -r '.layers[0] | "\(.digest) \(.size)"' "$m")" "$COUCHE_ESSAI $COUCHE_TAILLE"
  attendu "manifeste : configuration, celle de l'essai" "$(jq -r '.config.digest' "$m")" "$CONFIG_ESSAI"
  g=$L/blobs/sha256/${CONFIG_ESSAI#sha256:}; l=$L/blobs/sha256/${COUCHE_ESSAI#sha256:}
  [ -f "$g" ] && [ -f "$l" ] || echec "configuration ou couche absente du layout"
  echo "configuration : $(jq -c . "$g" 2>&1)"
  attendu "configuration : sha256 et taille des octets lus" "sha256:$(sha256sum < "$g" | cut -c1-64) $(stat -c %s "$g")" "$CONFIG_ESSAI $(jq -r .config.size "$m")"
  attendu "configuration : diff_ids, la couche non compressée" "$(jq -c '.rootfs.diff_ids' "$g")" "[\"$COUCHE_ESSAI\"]"
  attendu "couche : sha256 et taille des octets lus" "sha256:$(sha256sum < "$l" | cut -c1-64) $(stat -c %s "$l")" "$COUCHE_ESSAI $COUCHE_TAILLE"
  TZ=UTC tar -tvf "$l" > "$a/membres.txt" 2>&1 || true
  echo "membres de la couche ($(wc -l < "$a/membres.txt")) :"; sed 's/^/     /' "$a/membres.txt"
  attendu "couche : un membre, le rpm seul (mode, propriétaire, taille, date, nom)" "$(awk '{print $1, $2, $3, $4, $5, $6}' "$a/membres.txt")" \
    "-rw-r--r-- 0/0 $RPM_TAILLE 1970-01-01 00:00 $RPM_NOM"
  mkdir -p "$a/rpm"; tar -xf "$l" -C "$a/rpm" || echec "extraction de la couche"
  echo "rpm tiré : $RPM_NOM, $(stat -c %s "$a/rpm/$RPM_NOM") octets, sha256 $(sha256sum < "$a/rpm/$RPM_NOM" | cut -c1-64)"
  mesure "rpm tiré égal à celui de M3 (sha256)" "$(sha256sum < "$a/rpm/$RPM_NOM" | cut -c1-64)" "$RPM_M3_SHA"
  mesure "rpm tiré égal au fichier de M3 (cmp)" "$(cmp -s "$a/rpm/$RPM_NOM" "$RPM_M3" && echo égal || echo différent)" égal
}
etape_comparaison() { # lecture seule : artefact tiré par digest (lecture anonyme) dans un dossier neuf, confronté à l'essai et à M3
  local c=$T/comparaison i x n
  rm -rf -- "${c:?}"; mkdir -p "$c/travail"
  echo "## gardes"
  attendu "rpm de M3 (build 1)" "$(sha256sum < "$RPM_M3" | cut -c1-64)" "$RPM_M3_SHA"
  attendu "verrou (sha256)" "$(sha256sum < "$VERROU" | cut -c1-64)" "$VERROU_SHA"
  for i in 1 2; do
    x=$R/m4c-pipeline-$i-construire.log
    [ -s "$x" ] || echec "journal archivé de construire absent : $x"
    attendu "journal $i de construire : couche, configuration et manifeste" \
      "$(lignes "^couche $COUCHE_ESSAI ($COUCHE_TAILLE octets) ; configuration $CONFIG_ESSAI ; manifeste $DIGEST_ESSAI$" "$x")" 1
    attendu "IMAGE_DIGEST de m4c-rpm-$i (relu dans le cluster)" \
      "$(kubectl get pipelinerun -n builds "m4c-rpm-$i" -o json < /dev/null | jq -r '.status.results[]? | select(.name == "IMAGE_DIGEST") | .value')" "$DIGEST_ESSAI"
  done
  echo "## buildroot des deux PipelineRuns contre le verrou (journaux archivés de construire)"
  jq -r '.buildroot.rpms[] | "paquet \(.name) \(.version) \(.release) \(.arch) \(.sigmd5)"' "$VERROU" | sort > "$c/verrou.txt"
  for i in 1 2; do
    grep '^paquet ' "$R/m4c-pipeline-$i-construire.log" > "$c/paquets-$i.txt" || true
    n=$(diff "$c/paquets-$i.txt" "$c/verrou.txt" | grep -c '^[<>]' || true)
    echo "m4c-rpm-$i : paquets imprimés $(wc -l < "$c/paquets-$i.txt") ; lignes d'écart au verrou $n ; 5 premières :"
    diff "$c/paquets-$i.txt" "$c/verrou.txt" | grep '^[<>]' | sed -n '1,5p' | cut -c1-200 | sed 's/^/     /' || true
    mesure "m4c-rpm-$i : paquets du buildroot" "$(wc -l < "$c/paquets-$i.txt")" 222
    mesure "m4c-rpm-$i : lignes d'écart au verrou (nom, version, release, arch, sigmd5)" "$n" 0
  done
  echo "## tirage par digest, lecture anonyme, dossier neuf"
  oras cp --no-tty --from-ca-file "$P/ca-poc.crt" "${IMAGE/$REG/$REG_HOTE}@$DIGEST_ESSAI" --to-oci-layout "$c/layout:a" < /dev/null > "$c/cp.out" 2>&1 \
    || { sed -n '1,5p' "$c/cp.out" >&2; echec "oras cp de l'artefact"; }
  echo "tiré : $DIGEST_ESSAI ; du -sb du layout : $(du -sb "$c/layout" | cut -f1) octets (relevé)"
  echo "## confrontation à l'essai et à M3"
  confronter_artefact "$c/layout" "$c/travail"
  echo "dossier tiré laissé : $c"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

lancer m4c "05 M4c" "$@"
