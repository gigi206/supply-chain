#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b (§5 de resultats/m1b-carte.md), cinquième point : M4c refait sous un préfixe, avec la tâche
# construire-rpm de la cascade (tekton/tasks/construire-rpm@ca03f189, outillage 70f8c412, liste revue), la fermeture rpm de M4b
# refait (builds/fermetures/sample-app-rpm@09838980, bootstrap 6de899ac) et l'artefact de packaging de la cascade
# (entrees/sample-app/packaging-rpm@333b7322, verrou resultats/m1b-verrou.json c544599a). Préparé à sec le 20/11/2026 sous
# l'accord permanent. Script frère de m4c.sh, qui n'est pas touché : ses gabarits, ses tâches signées, sa pipeline (tag m4c,
# ca874375), son artefact (07b7bd6f) et ses journaux restent tels quels. preparer-rpm reste celle de M4c (2f65f390, liste revue).
# Recopié à l'identique de m4c.sh : attendu, ref_revue, remplacer, rendre_taches, rendre_pipeline, script_etape, bb_liens, modes,
# faux_rpm, mesure, pod_retirer, copier_pod, liste_arbre, politique_relue, echec, normaliser ; de m1b-bundles.sh : neuf, sha.
# Transformés par des remplacements listés et comptés (resultats/m1b-construction-copies.py) : entrees_hote, etape_prealables
# (devient etape_local), etape_essai_preparer (de m4c.sh), etape_essai_construire (de m1b-bundles.sh, devient etape_essai).
#   local   hôte seul, hors ligne, sans cluster ni Zot : prealables de m4c.sh avec les entrées neuves (fermeture tirée par la
#           comparaison de M4b refait, verrou c544599a sous le nom verrou-rpm.json de l'artefact) ; de plus, sha256 des gabarits et
#           des tâches signées, références de la liste revue, tâches rendues égales aux tâches signées versionnées (preparer-rpm
#           de M4c, construire-rpm de la cascade) ; confrontation au verrou neuf (dossier dir: 6de899ac, image_digest 77cff176) ;
#           entrees.tar neuf, dont la taille et le sha256 sont journalisés.
#   essai_preparer  pod d'essai runc (rien dans Zot), etape_essai_preparer de m4c.sh : vrais pulls de la fermeture 09838980 et
#           de l'artefact 333b7322 ; résultats ; arbre entrees/ égal à celui de local ; journal du pod archivé sous un nom neuf.
#   essai   pod d'essai Kata (rien dans Zot), etape_essai_construire de m1b-bundles.sh : entrees.tar de local (taille et sha256
#           égaux au journal de local), script de construire-rpm tel que signé ; première construction hermétique avec le
#           bootstrap de M1b : lignes du script relevées (dossier dir:, « Checking image digest », « Expected digest for image »,
#           repli, réseau) ; rpm et src.rpm comparés à M3, digest de l'artefact comparé à celui de l'essai de M4c, sans arrêter.
#   pipeline  ajoutée le 20/11/2026 après la décision du propriétaire « Même dépôt » ; SIGNER=1 seulement, sur accord nommé
#           (signature, écriture dans Zot) : etape_pipeline de m1b-fermeture.sh transformée (remplacements comptés) : gardes (essai
#           archivé sans écart, tag neuf absent, tag m4c sur ca874375, trois tâches de la liste revue, place libre) ; pipeline
#           sample-app-rpm rendue admise, trois feuilles de différence avec celle de M4c relue dans son bundle ; signée par tkn
#           (clé des tâches, jamais lue ici), relue, versionnée sous construction/sample-app-rpm.$TAG.signee.yaml ; bundle
#           tekton/pipelines/sample-app-rpm:$TAG ; relue anonymement, tag m4c inchangé. Digest épinglé ensuite dans PIPELINE_REF.
#   construction  ajoutée de même, sur accord nommé (cluster, écritures dans Zot) : etape_pipeline de m4c.sh transformée : deux
#           PipelineRuns $PREFIXE-construction-1 et -2 ; gardes (PIPELINE_REF épinglée et relue au tag, tag m4c inchangé, artefact
#           de M4c présent, journaux neufs) ; lignes de la construction hermétique relevées (hermetique) ; enveloppes d'attestation
#           de l'artefact relevées avant et après. Écritures dans Zot : le même digest, republié par publier-image, et les
#           attestations de Chains, ajoutées à celles de M4c.
#   essai_refus  ajoutée le 20/11/2026 après construction (accord permanent : pod d'essai Kata, rien dans Zot) : etape_essai
#           (etape_essai_construire de m1b-bundles.sh) avec une seule altération, bootstrap.image_digest du verrou livré au pod,
#           réécrit par le conteneur remplir ; refus attendu de mock (« Expected digest for image »), code non nul, aucun rpm.
# Comparaison et provenance viendront ensuite (lecture seule).
# Un journal existant n'est jamais réécrit : relancer sous un autre PREFIXE.
# Usage (racine du dépôt) : [PREFIXE=m1b] DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m1b-construction.sh <étape>…
#         (journaux : resultats/$PREFIXE-construction-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, OUTILS, OUTILS_DIGEST, listee, sur, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
N=${PREFIXE:-m1b}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; m4c) echo "préfixe refusé : m4c appartient à M4c" >&2; exit 2 ;; esac
TAG=${TAG:-$N}   # tag du bundle de la pipeline (étape pipeline, ajoutée le 20/11/2026)
case $TAG in m4b|m4c|essai) echo "tag refusé : $TAG appartient à M4b, M4c ou aux essais" >&2; exit 2 ;; ''|*[!a-z0-9-]*) echo "TAG invalide : $TAG" >&2; exit 2 ;; esac
C=$h05/construction
T=$W/$N-construction-05
mkdir -p "$T"
umask 022

PREFETCH_IMAGE=$REG/plateforme/outils-prefetch@sha256:68e0ae705de5a8f993f168d8252b3218d7d3ed76e704cf24d4414006aea7b8cc   # m4c.sh
OUTILS_IMAGE=$REG/$OUTILS@$OUTILS_DIGEST                                                                                  # m4c.sh
IMAGE_OUTILLAGE=$REG/builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae   # M1b (IMAGE_NEUVE de m1b-bundles.sh)
FERMETURE_RPM=$REG/builds/fermetures/sample-app-rpm@sha256:0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f    # M4b refait (FERMETURE_NEUVE de m1b-fermeture.sh)
FERMETURE_SOURCES=$REG/builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21   # m4c.sh
PACKAGING=$REG/entrees/sample-app/packaging-rpm@sha256:333b7322290ab5edd85989908fa2e181a48a72facfd4043e181a2962d2bcfe48      # cascade (m1b-artefact.sh publier)
PUBLIER_REF=$REG/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b         # m4c.sh
PREPARER_REF=$REG/tekton/tasks/preparer-rpm@sha256:2f65f3903e98caa9944ab3fee4b67585b15d67ad477ff48a8487e8e86af5526f       # m4c.sh, liste revue
CONSTRUIRE_REF=$REG/tekton/tasks/construire-rpm@sha256:ca03f18908d0b5e73edc57ecf9610513e2907267ce1da2d9f41fd36b969289c5   # cascade, liste revue (e2f15c1b)
EPOQUE=1793229566   # m4c.sh
IMAGE=$REG/builds/sample-app-rpm   # m4c.sh ; ici rendu seulement (paramètre de la pipeline), rien n'est publié
COMMIT=6391fd437f26696847041be3226bbbf633f55a2f   # m4c.sh
DEPOT_GIT=https://sc-stockage.poc.test:3000/workspace/sample-app.git
ARBRE=30e808ffa327288c656ddda7b6fafe4005234b77
VERROU=$R/m1b-verrou.json   # verrou de la cascade, livré sous le nom verrou-rpm.json dans l'artefact 333b7322
VERROU_SHA=c544599aba4b7460f7496066e7c0361c80a59b8e345655553509024a254a6c83   # m1b-verrou.sh verrou (6da4e4a1)
BOOT_DOSSIER=sc-stockage.poc.test@sha256:6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3   # dossier dir: du bootstrap (CP2 de M4b refait)
IMAGE_DIGEST_BOOT=77cff1767fea08670831a740051c2cc0c4025e74b48ed1c96d59cf06824e89ca   # bootstrap.image_digest du verrou, jamais mesuré par mock
IMAGE_DIGEST_FAUX=77cff1767fea08670831a740051c2cc0c4025e74b48ed1c96d59cf06824e89cb   # essai_refus : dernier caractère changé, rien d'autre
SPEC=$repo/poc/packaging/sample-app.spec
SPEC_SHA=918a83f592c31d322a77a4e887c808c61077e2f100442dc98abed5c67ae582a6     # m4c.sh
TIREE=$W/m1b-fermeture-05/comparaison/tiree   # fermeture 09838980 tirée par digest par la comparaison de M4b refait (égale à l'essai)
ARBRE_FERMETURE_SHA=a731fbce8ba11021508ff700e2ba6f72d976a92c5c835ba8e419b4ff88db014a   # resultats/m1b-fermeture-essai-arbre.txt (arbre de l'essai, prédit à sec)
S4B=$W/s4b-06                       # m4c.sh
PKG=$HOME/.cache/supply-chain-poc/packaging
ARCHIVE_SHA=07521c1e60cdbed8a29912ad775e52201daf95003f7f54ccee76b3270742d9bb   # m4c.sh
RPM_M3=$W/s1-05/m3/build-1/sample-app-1.0.0-2.el9.x86_64.rpm
RPM_M3_SHA=864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f   # m4c.sh
SRPM_M3_SHA=c802e60a511c140e3a6761752b0c9966b2d8959a909d2a3b73d85f9b4bfd1128  # m4c.sh
GO=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-go1.26.10.linux-amd64/bin   # m4c.sh
LISTE_REVUE=$here/politique/porte/taches.yml
LAYOUT_PREFETCH=$HOME/.cache/supply-chain-poc/03/f2/layout   # m4c.sh
BUSYBOX_PREFETCH=49227c027f9b972f929780d60ee486dee5948ea7042cb7ab400690bb104418bc   # m4c.sh
GABARITS_SHA="construction/preparer-rpm.yaml:a7dfa37e23948209c6b63c815eef1d41fc9ae5404fed3de4708e4167920ad9bc
construction/construire-rpm.yaml:e88f5521ede87f5b03330683939fd3494f5ff58544ded9a9326014e30b8d0f88
construction/sample-app-rpm.yaml:a9917a65c994421f25735c03971906e99aac7982821185a135535910f0e8f7cd
construction/preparer-rpm.signee.yaml:b32d073f75ca03aa48100f7052a23316297b8d5e318e7796ebc8a729b1d7acf9
construction/construire-rpm.m1b.signee.yaml:90151d43270fc2fa1a77765f4c6acdacdc2ecd2033d9bc0aa8494c5517f0a31b"   # gabarits de m4c.sh ; tâches signées de M4c (preparer) et de la cascade (construire)
SCRIPT_CONSTRUIRE_SHA=0b119024e9aa29dd21b486efd9f4951ee6e15b004ed816dbbc089e97d24aac3c   # m1b-bundles.sh (script substitué de construire-rpm)
DIGEST_ESSAI_M4C=sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119   # m1b-bundles.sh, m4c.sh (DIGEST_ESSAI)
LABEL_PREPARER=preparer-rpm
LABEL_CONSTRUIRE=construire-rpm
MORCEAU_MIO=64
ECARTS=0
FACTICE=sha256:$(printf '0%.0s' {1..64})
# Pipeline et PipelineRuns (ajouté le 20/11/2026 après la décision du propriétaire « Même dépôt ») : l'artefact est publié dans
# builds/sample-app-rpm, où M4c a déjà publié et attesté le même digest ; la publication s'observe par les enveloppes d'attestation.
PIPELINE_M4C=tekton/pipelines/sample-app-rpm@sha256:ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be   # m4c.sh (PIPELINE_REF)
FEUILLES_ATTENDUES=".spec.tasks[0].params[2].value
.spec.tasks[0].params[4].value
.spec.tasks[1].taskRef.params[0].value"   # fermeture rpm, artefact de packaging, bundle de construire-rpm (calcul à sec du 20/11)
PIPELINE_REF=$REG/tekton/pipelines/sample-app-rpm@sha256:7d361cb1d5ea9b7994727f839bc4365a29e4ebdc7948fceff4176b4a371abd6a   # étape pipeline du 20/11 (m1b-construction-pipeline.log) ; construction refuse de tourner si vide
DIGEST_ESSAI=sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119   # essai du 20/11 (m1b-construction-essai.log), égal à M4c
PVC_TAILLE=2Gi   # m4c.sh
LIBRE_MIN=1073741824   # m4c.sh

# --- recopié de m4c.sh et m1b-bundles.sh ---
# Blocs recopiés à l'identique de m4c.sh :
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
echec() { echo "KO   $*" >&2; exit 1; }
normaliser() { # fichier : JSON sans la signature ni les « resources: {} », « description: "" » et « annotations: {} » que tkn écrit
  # (mesuré au banc du 18/11), clés triées
  yq -o=json -I=0 'del(.metadata.annotations["tekton.dev/signature"]) | del(.. | select(tag == "!!map" and length == 0 and (path | .[-1]) == "resources"))
    | del(.. | select(tag == "!!str" and . == "" and (path | .[-1]) == "description"))
    | del(.metadata.annotations | select(length == 0)) | sort_keys(..)' "$1"
}
# Blocs recopiés à l'identique de m1b-bundles.sh :
neuf() { [ ! -e "$1" ] || echec "déjà présent, jamais réécrit : ${1#"$W"/}"; }
sha() { sha256sum < "$1" | cut -c1-64; }
# Blocs transformés (remplacements listés et comptés par resultats/m1b-construction-copies.py) :
entrees_hote() { # répertoire entrees : comme les tirerait le pas entrees (copies locales par digest), avant ses contrôles
  mkdir -p "$1/src" "$1/packaging"
  git -C "$repo" archive HEAD:poc/sample-app | tar -x -C "$1/src"
  cp -a "$TIREE" "$1/fermeture"
  cp -a "$S4B/comparaison/sources" "$1/sources"
  cp "$SPEC" "$1/packaging/"
  cp "$VERROU" "$1/packaging/verrou-rpm.json"   # nom du fichier dans l'artefact 333b7322 (m1b-artefact-local.log)
}

etape_local() { # hôte seul, hors ligne, sans cluster ni Zot ; etape_prealables de m4c.sh, transformée
  local x=$T/local e f a s d
  neuf "$x"; mkdir -p "$x"   # dossier neuf : rien n'est retiré
  echo "## sources de la cascade"
  sources_cascade
  echo "## références épinglées"
  attendu "verrou de M1b (sha256)" "$(sha256sum < "$VERROU" | cut -c1-64)" "$VERROU_SHA"
  attendu "spec du dépôt (sha256)" "$(sha256sum < "$SPEC" | cut -c1-64)" "$SPEC_SHA"
  attendu "publier-image dans la liste revue" "$(ref_revue publier-image d21931f3)" "$PUBLIER_REF"
  attendu "époque : date du dernier commit de poc/sample-app (celle de sources.sh)" "$(git -C "$repo" log -1 --format=%ct -- poc/sample-app)" "$EPOQUE"
  attendu "arbre de poc/sample-app à HEAD" "$(git -C "$repo" rev-parse HEAD:poc/sample-app)" "$ARBRE"
  attendu "archive de sources.sh (S1, M3)" "$(sha256sum < "$PKG/sample-app-1.0.0.tar.gz" | cut -c1-64)" "$ARCHIVE_SHA"
  attendu "rpm de M3 (build 1)" "$(sha256sum < "$RPM_M3" | cut -c1-64)" "$RPM_M3_SHA"
  attendu "fermeture rpm tirée par la comparaison de M4b refait : fichiers sous depot/" "$(find "$TIREE/depot" -type f | wc -l)" 230
  attendu "fermeture rpm tirée : rien d'autre que depot/ à la racine" "$(ls -A "$TIREE" | paste -sd' ')" depot

  echo "## gabarits rendus (références des tâches factices dans la pipeline)"
  rendre_taches
  rendre_pipeline "$REG/tekton/tasks/preparer-rpm@$FACTICE" "$REG/tekton/tasks/construire-rpm@$FACTICE" "$PUBLIER_REF"
  signees_egales
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
  attendu "entrees/verrou-rpm.json égal au verrou de M1b" "$(cmp -s "$e/verrou-rpm.json" "$VERROU" && echo égal || echo différent)" égal
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
    "$BOOT_DOSSIER $IMAGE_DIGEST_BOOT"
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

etape_essai_preparer() { # pod runc restreint au label preparer-rpm ; les trois pas en initContainers, images et montages de la tâche ;
  # vrai clone de Forgejo et vrais pulls dans Zot ; résultats lus ; arbre entrees/ comparé à celui de prealables ; pod supprimé
  local p=$N-construction-preparer x=$T/essai-preparer a c r
  [ -d "$T/local/ws/entrees" ] || { echo "KO   lancer d'abord local" >&2; exit 1; }
  neuf "$R/$N-construction-preparer-pod.log"
  neuf "$x"; mkdir -p "$x"
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
  trap "kubectl delete pod -n builds $p --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true" EXIT
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
  cat "$x"/{sources,entrees,assemblage,liste}.log > "$R/$N-construction-preparer-pod.log"
  pod_retirer "$p"
  attendu "pod d'essai de preparer-rpm" "$r" Succeeded
  attendu "résultat CHAINS-GIT_URL" "$(sed -n 's/^résultat CHAINS-GIT_URL : //p' "$x/liste.log")" "$DEPOT_GIT"
  attendu "résultat CHAINS-GIT_COMMIT" "$(sed -n 's/^résultat CHAINS-GIT_COMMIT : //p' "$x/liste.log")" "$COMMIT"
  for a in "FERMETURE_RPM $FERMETURE_RPM" "FERMETURE_SOURCES $FERMETURE_SOURCES" "PACKAGING $PACKAGING"; do
    set -- $a
    attendu "résultat $1_ARTIFACT_INPUTS" "$(sed -n "s/^résultat $1_ARTIFACT_INPUTS : //p" "$x/liste.log")" "{\"uri\":\"oci://${2%@*}\",\"digest\":\"${2#*@}\"}"
  done
  sed -n '/^----- liste -----$/,/^----- fin de la liste -----$/p' "$x/liste.log" | sed '1d;$d' > "$x/arbre-pod.txt"
  (cd "$T/local/ws/entrees" && sh -c "$(liste_arbre)") > "$x/arbre-hote.txt"
  echo "arbre entrees/ : $(grep -c '^[0-9a-f]\{64\} ' "$x/arbre-pod.txt") fichiers dans le pod, $(grep -c '^[0-9a-f]\{64\} ' "$x/arbre-hote.txt") dans local"
  diff "$x/arbre-hote.txt" "$x/arbre-pod.txt" | head -n 20 | cut -c1-200 | sed 's/^/     /' || true
  attendu "arbre entrees/ du pod égal à celui de local (contenu, modes, types)" "$(cmp -s "$x/arbre-hote.txt" "$x/arbre-pod.txt" && echo égal || echo différent)" égal
}

etape_essai() { # pod Kata au label construire-rpm, à la forme que Tekton produira : contexte du podTemplate au niveau du pod (UID
  # 65532, runAsNonRoot), pas root privilégié au niveau du conteneur ; entrées sur un volume à part, remplies par un second
  # conteneur en UID 65532 et montées en lecture seule dans le conteneur de mock ; script de construire-rpm tiré du gabarit rendu,
  # variables de Tekton seules substituées ; image.tar rapatrié ; écarts à M3 relevés sans arrêter ; pod supprimé
  local p=$N-construction-construire x=$T/essai-construire rc=0 d s j=$R/$N-construction-local.log
  [ -s "$j" ] && [ -s "$T/entrees.tar" ] || echec "lancer d'abord local (journal resultats/${j##*/} et entrees.tar)"
  attendu "entrees.tar de local (taille, sha256), égal au journal de local" "$(stat -c %s "$T/entrees.tar") $(sha "$T/entrees.tar")" \
    "$(sed -n 's/^entrees.tar : \([0-9]*\) octets, sha256 \([0-9a-f]\{64\}\)$/\1 \2/p' "$j")"
  neuf "$R/$N-construction-construire-pod.log"
  neuf "$x"; mkdir -p "$x"
  rendre_taches
  script_etape "$T/construire-rpm.yaml" construire \
    | sed -e 's#\$(workspaces.entrees.path)#/e#g' -e 's#\$(workspaces.sortie.path)#/o#g' -e 's#\$(results.DIGEST_CONSTRUIT.path)#/w/digest#g' > "$x/construire.sh"
  attendu "script d'essai : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/construire.sh" || true)" 0
  attendu "script d'essai : égal au script du gabarit, variables de Tekton exceptées" \
    "$(diff <(script_etape "$T/construire-rpm.yaml" construire) "$x/construire.sh" | grep -c '^>' || true)" 3
  attendu "script d'essai : égal à celui de l'essai de M4c (sha256)" "$(sha "$x/construire.sh")" "$SCRIPT_CONSTRUIRE_SHA"
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
  trap "kubectl delete pod -n builds $p --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true" EXIT
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
  sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' "$x/construire.log" > "$R/$N-construction-construire-pod.log"
  grep -v '^paquet ' "$R/$N-construction-construire-pod.log" | cut -c1-220 | sed 's/^/     /'
  echo "     (code de l'exec : $rc ; journal complet : resultats/$N-construction-construire-pod.log)"
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
  hermetique "$x/construire.log"
  [ $rc = 0 ] || { echo "KO   script de construire-rpm : code $rc" >&2; exit 1; }
  attendu "dernière ligne du script atteinte (image.tar)" "$(grep -c '^image.tar : [0-9]* octets$' "$x/construire.log" || true)" 1
  mesure "src.rpm construit dans le pod d'essai" "$(sed -n 's/^rpm : [^ ]*\.src\.rpm sha256 \([0-9a-f]\{64\}\) .*/\1/p' "$x/construire.log")" "$SRPM_M3_SHA"
  mkdir -p "$x/lu"; tar -xf "$x/image.tar" -C "$x/lu"
  attendu "index.json lu comme publier-image : égal au résultat" "$(sed -n 's/.*"digest": *"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' "$x/lu/index.json")" "$d"
  mesure "rpm construit dans le pod d'essai (couche)" "$(tar -xOf "$x/lu/blobs/sha256/$(jq -r '.layers[0].digest' "$x/lu/blobs/sha256/${d#sha256:}" | cut -d: -f2)" | sha256sum | cut -c1-64)" "$RPM_M3_SHA"
  mesure "digest de l'artefact, égal à celui de l'essai de M4c" "$d" "$DIGEST_ESSAI_M4C"
  echo "relevé : paquets du buildroot imprimés : $(grep -c '^paquet ' "$x/construire.log" || true) ; écarts au verrou (nom, version, release, arch, sigmd5) : $(diff <(grep '^paquet ' "$x/construire.log") <(jq -r '.buildroot.rpms[] | "paquet \(.name) \(.version) \(.release) \(.arch) \(.sigmd5)"' "$VERROU" | sort) | grep -c '^[<>]' || true)"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}
# --- fin des copies ---
# --- recopié pour la pipeline (m4c.sh, m1b-bundles.sh, m1b-fermeture.sh) ---
# Blocs recopiés à l'identique de m4c.sh :
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'
admission() { # fichier : kubectl create --dry-run=server dans builds (rien n'est créé) ; code de kubectl, sortie dans $T/admission.out (m4b.sh)
  local rc=0
  kubectl create --dry-run=server -n builds -f "$1" < /dev/null > "$T/admission.out" 2>&1 || rc=$?
  echo "$rc"
}
libre_zot() { sur sc-stockage 'df -B1 --output=avail / | tail -n 1' < /dev/null | tr -d ' '; }   # m4b.sh
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
# Blocs recopiés à l'identique de m1b-bundles.sh :
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
# Blocs recopiés à l'identique de m1b-fermeture.sh :
lire_manifeste() { # libellé référence-sans-registre sortie : octets du manifeste, lecture anonyme ; sha256 contrôlé par l'appelant
  oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" --output "$3" "$REG_HOTE/$2" < /dev/null 2> "$T/oras.err" \
    || echec "$1 : manifeste illisible, $(head -c 160 "$T/oras.err" | tr '\n' ' ')"
}
# Blocs transformés (remplacements listés et comptés par resultats/m1b-construction-copies.py) :
lire_bundle() { # référence-sans-registre sortie : objet d'un bundle Tekton (une couche, tar gzip d'un seul fichier), lecture anonyme
  local x=$T/bundle.json c
  lire_manifeste "bundle ${1%@*}" "$1" "$x"
  attendu "bundle ${1##*/} : manifeste relu (sha256)" "sha256:$(sha "$x")" "${1##*@}"
  attendu "bundle : une couche, pipeline sample-app-rpm" \
    "$(jq -r '[(.layers | length), .layers[0].annotations["dev.tekton.image.kind"], .layers[0].annotations["dev.tekton.image.name"]] | join(" ")' "$x")" \
    "1 pipeline sample-app-rpm"
  c=$(jq -r '.layers[0].digest' "$x")
  oras blob fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" --output "$T/couche.tgz" "$REG_HOTE/${1%@*}@$c" < /dev/null
  attendu "bundle : couche relue (sha256)" "sha256:$(sha "$T/couche.tgz")" "$c"
  attendu "bundle : un seul fichier dans la couche" "$(tar -tzf "$T/couche.tgz" | wc -l)" 1
  tar -xzOf "$T/couche.tgz" > "$2"
}

etape_pipeline() { # SIGNER=1 seulement : pipeline signée, relue, versionnée sous un nom neuf, bundle au tag neuf
  [ -n "${SIGNER:-}" ] || echec "étape pipeline : SIGNER=1 seulement, sur accord nommé du propriétaire"
  [ -s "$S/taches.key" ] || echec "clé des tâches absente"
  local x=$T/pipeline v=$C/sample-app-rpm.$TAG.signee.yaml p libre
  neuf "$v"
  sources_cascade
  attendu "essai archivé (resultats/$N-construction-essai.log) : digest de l'artefact, sans écart" \
    "$(sed -n 's/^OK   digest de l.artefact, égal à celui de l.essai de M4c : //p' "$R/$N-construction-essai.log") $(grep -c '^écarts : 0$' "$R/$N-construction-essai.log")" "$DIGEST_ESSAI 1"
  neuf "$x"; mkdir "$x"
  echo '{}' > "$T/vide.json"
  echo "## gardes avant toute écriture (lecture anonyme)"
  attendu "tag $TAG de la pipeline, absent" "$(zot_lire "tag $TAG" "tekton/pipelines/sample-app-rpm:$TAG")" absent
  attendu "tag m4c de la pipeline, sur celle de M4c" "$(zot_lire "tag m4c" tekton/pipelines/sample-app-rpm:m4c)" "${PIPELINE_M4C##*@}"
  attendu "preparer-rpm de M4c, lue dans la liste revue" "$(ref_revue preparer-rpm 2f65f390)" "$PREPARER_REF"
  attendu "construire-rpm de la cascade, lue dans la liste revue" "$(ref_revue construire-rpm ca03f189)" "$CONSTRUIRE_REF"
  attendu "publier-image, lue dans la liste revue" "$(ref_revue publier-image d21931f3)" "$PUBLIER_REF"
  libre=$(libre_zot)
  case $libre in ''|*[!0-9]*) echec "place libre illisible : $libre" ;; esac
  [ "$libre" -ge "$LIBRE_MIN" ] || echec "place libre sur / de sc-stockage : $libre octets, sous $LIBRE_MIN"
  echo "OK   octets libres sur / de sc-stockage (porte /var/lib/zot) : $libre (seuil $LIBRE_MIN)"
  echo "## pipeline rendue (références de la liste revue, fermeture et artefact de la cascade) ; admission en dry-run serveur, rien n'est créé"
  (T=$x; rendre_pipeline "$PREPARER_REF" "$CONSTRUIRE_REF" "$PUBLIER_REF")
  attendu "pipeline rendue admise (code de kubectl)" "$(admission "$x/sample-app-rpm.yaml")" 0
  lire_bundle "$PIPELINE_M4C" "$x/bundle-m4c.json"
  normaliser "$x/bundle-m4c.json" > "$x/bundle-m4c.n.json"
  normaliser "$x/sample-app-rpm.yaml" > "$x/rendue.n.json"
  diff_feuilles "$x/bundle-m4c.n.json" "$x/rendue.n.json" > "$x/feuilles.txt"
  attendu "rendue : feuilles différentes de la pipeline de M4c" "$(cut -d' ' -f1 "$x/feuilles.txt" | paste -sd' ')" "$(paste -sd' ' <<< "$FEUILLES_ATTENDUES")"
  attendu "pipeline rendue : références des tâches (bundles)" \
    "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$x/sample-app-rpm.yaml")" "$PREPARER_REF $CONSTRUIRE_REF $PUBLIER_REF"
  echo "## signature (tkn $(tkn version --component client)), relue avant tout versionnement et toute poussée"
  tkn pipeline sign "$x/sample-app-rpm.yaml" -K "$S/taches.key" -f "$x/signee.yaml" > /dev/null
  attendu "pipeline signée : annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$x/signee.yaml")" true
  normaliser "$x/signee.yaml" > "$x/signee.n.json"
  attendu "pipeline signée : égale à la rendue, signature exceptée (normalisées)" \
    "$(cmp -s "$x/signee.n.json" "$x/rendue.n.json" && echo égale || echo différente)" égale
  cp "$x/signee.yaml" "$v"
  echo "signature versionnée : construction/${v##*/} (sha256 $(sha "$v"))"
  (umask 077 && mkdir -p "$T/auth")
  trap 'find "$T/auth" -depth -delete 2> /dev/null || true' EXIT   # copie du secret de Zot, retirée même en cas d'échec (sans rm)
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundle (commun.sh), compte poc-ecriture
  echo "## bundle, tag $TAG (écriture définitive)"
  p=$REG/tekton/pipelines/sample-app-rpm@$(bundle "$v" tekton/pipelines/sample-app-rpm "$TAG")
  find "$T/auth" -depth -delete
  echo "$p" | tee "$x/pipeline.ref"
  echo "## relecture anonyme après"
  attendu "tag $TAG de la pipeline, sur le bundle poussé" "$(zot_lire "tag $TAG" "tekton/pipelines/sample-app-rpm:$TAG")" "${p##*@}"
  lire_bundle "${p#"$REG"/}" "$x/bundle-neuf.json"
  normaliser "$x/bundle-neuf.json" > "$x/bundle-neuf.n.json"
  attendu "bundle relu : égal à la pipeline signée (normalisés)" \
    "$(cmp -s "$x/bundle-neuf.n.json" "$x/signee.n.json" && echo égal || echo différent)" égal
  attendu "bundle relu : signature égale à celle de la version" \
    "$(yq -o=yaml '.metadata.annotations["tekton.dev/signature"]' "$x/bundle-neuf.json")" "$(yq -o=yaml '.metadata.annotations["tekton.dev/signature"]' "$v")"   # le bundle est du JSON : sortie YAML forcée des deux côtés
  attendu "tag m4c de la pipeline, inchangé" "$(zot_lire "tag m4c" tekton/pipelines/sample-app-rpm:m4c)" "${PIPELINE_M4C##*@}"
  echo "octets libres sur / de sc-stockage après : $(libre_zot)"
  echo "PIPELINE_REF à épingler (correction datée, banc rejoué) avant l'étape construction : $p"
}

etape_construction() { # deux PipelineRuns de sample-app-rpm ($N-construction-1, puis -2) ; rien n'est purgé ; artefact comparé à
  # l'essai ; etape_pipeline de m4c.sh, transformée
  local i pr r t p d u c k l x j g
  echo "## gardes, avant toute création"
  [ -n "$PIPELINE_REF" ] || echec "PIPELINE_REF non épinglée : étape pipeline, puis correction datée"
  [ -s "$T/pipeline/pipeline.ref" ] || echec "référence de la pipeline absente (étape pipeline)"
  attendu "pipeline écrite par l'étape pipeline" "$(cat "$T/pipeline/pipeline.ref")" "$PIPELINE_REF"
  echo '{}' > "$T/vide.json"
  attendu "tag m4c de la pipeline, inchangé" "$(zot_lire "tag m4c" tekton/pipelines/sample-app-rpm:m4c)" "${PIPELINE_M4C##*@}"
  for i in 1 2; do neuf "$R/$N-construction-$i-construire.log"; done
  attendu "pipeline relue dans Zot au tag $TAG (lecture anonyme)" \
    "$REG/tekton/pipelines/sample-app-rpm@$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" "$REG_HOTE/tekton/pipelines/sample-app-rpm:$TAG" < /dev/null | jq -r .digest)" \
    "$PIPELINE_REF"
  for r in "$PREPARER_REF" "$CONSTRUIRE_REF" "$PUBLIER_REF"; do
    if listee "$r"; then echo "OK   dans la liste revue : $r"; else echec "absente de la liste revue : $r"; fi
  done
  politique_relue
  for i in 1 2; do
    pr=$N-construction-$i
    echo "## $pr"
    if [ "$i" = 1 ]; then
      attendu "artefact de M4c présent avant le premier PipelineRun (décision « Même dépôt »)" \
        "$(zot_lire "artefact de M4c" "${IMAGE#"$REG"/}@$DIGEST_ESSAI")" "$DIGEST_ESSAI"
      enveloppes_att avant
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
    [ ! -f "$x" ] || cp "$x" "$R/$N-construction-$i-construire.log"
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
    hermetique "$x"
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
  enveloppes_att après
  attendu "tag m4c de la pipeline, inchangé après" "$(zot_lire "tag m4c" tekton/pipelines/sample-app-rpm:m4c)" "${PIPELINE_M4C##*@}"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}

etape_essai_refus() { # pod Kata au label construire-rpm, à la forme que Tekton produira : contexte du podTemplate au niveau du pod (UID
  # 65532, runAsNonRoot), pas root privilégié au niveau du conteneur ; entrées sur un volume à part, remplies par un second
  # conteneur en UID 65532 et montées en lecture seule dans le conteneur de mock ; script de construire-rpm tiré du gabarit rendu,
  # variables de Tekton seules substituées ; image.tar rapatrié ; écarts à M3 relevés sans arrêter ; pod supprimé
  local p=$N-construction-refus x=$T/essai-refus rc=0 d s j=$R/$N-construction-local.log
  [ -s "$j" ] && [ -s "$T/entrees.tar" ] || echec "lancer d'abord local (journal resultats/${j##*/} et entrees.tar)"
  attendu "entrees.tar de local (taille, sha256), égal au journal de local" "$(stat -c %s "$T/entrees.tar") $(sha "$T/entrees.tar")" \
    "$(sed -n 's/^entrees.tar : \([0-9]*\) octets, sha256 \([0-9a-f]\{64\}\)$/\1 \2/p' "$j")"
  attendu "image_digest altéré : même longueur, différent du verrou" "${#IMAGE_DIGEST_FAUX} $([ "$IMAGE_DIGEST_FAUX" != "$IMAGE_DIGEST_BOOT" ] && echo différent)" "64 différent"
  neuf "$R/$N-construction-refus-pod.log"
  neuf "$x"; mkdir -p "$x"
  rendre_taches
  script_etape "$T/construire-rpm.yaml" construire \
    | sed -e 's#\$(workspaces.entrees.path)#/e#g' -e 's#\$(workspaces.sortie.path)#/o#g' -e 's#\$(results.DIGEST_CONSTRUIT.path)#/w/digest#g' > "$x/construire.sh"
  attendu "script d'essai : variables Tekton restantes" "$(grep -c '\$(\(params\|workspaces\|results\)\.' "$x/construire.sh" || true)" 0
  attendu "script d'essai : égal au script du gabarit, variables de Tekton exceptées" \
    "$(diff <(script_etape "$T/construire-rpm.yaml" construire) "$x/construire.sh" | grep -c '^>' || true)" 3
  attendu "script d'essai : égal à celui de l'essai de M4c (sha256)" "$(sha "$x/construire.sh")" "$SCRIPT_CONSTRUIRE_SHA"
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
  trap "kubectl delete pod -n builds $p --ignore-not-found --wait=false < /dev/null > /dev/null 2>&1 || true" EXIT
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
  # Seule altération de l'essai : bootstrap.image_digest du verrou livré, réécrit par le conteneur remplir (UID 65532)
  kubectl exec -n builds "$p" -c remplir -- sh -c "sed -i 's/$IMAGE_DIGEST_BOOT/$IMAGE_DIGEST_FAUX/' /e/verrou-rpm.json && echo \"verrou altéré : \$(grep -c $IMAGE_DIGEST_FAUX /e/verrou-rpm.json) ligne(s) au faux image_digest, \$(grep -c $IMAGE_DIGEST_BOOT /e/verrou-rpm.json) au vrai\"" < /dev/null > "$x/alteration.txt" \
    || { pod_retirer "$p"; echo "KO   altération du verrou dans le pod" >&2; exit 1; }
  attendu "verrou altéré dans le pod (image_digest seul)" "$(cat "$x/alteration.txt")" "verrou altéré : 1 ligne(s) au faux image_digest, 0 au vrai"
  # Le script est un fichier dans le pod, comme sous Tekton, et rien n'arrive sur son entrée standard (s4d.sh)
  copier_pod "$p" essai "$x/construire.sh" /w/construire.sh
  echo "## script de construire-rpm dans le pod ($(date -u +%H:%M:%S))"
  timeout 1800 kubectl exec -n builds "$p" -c essai -- bash /w/construire.sh < /dev/null > "$x/construire.log" 2>&1 || rc=$?
  echo "fin à $(date -u +%H:%M:%S)"
  sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' "$x/construire.log" > "$R/$N-construction-refus-pod.log"
  grep -v '^paquet ' "$R/$N-construction-refus-pod.log" | cut -c1-220 | sed 's/^/     /'
  echo "     (code de l'exec : $rc ; journal complet : resultats/$N-construction-refus-pod.log)"
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
  attendu "script de construire-rpm refusé (code de l'exec non nul)" "$([ "$rc" != 0 ] && echo refusé || echo "accepté, code $rc")" refusé
  attendu "dossier dir: et image_digest altéré, lus par le script" \
    "$(grep -c -x -F "dossier dir: $BOOT_DOSSIER ; image_digest du verrou $IMAGE_DIGEST_FAUX" "$x/construire.log" || true)" 1
  attendu "mock --hermetic-build en échec (rc non nul)" "$(grep -c '^mock --hermetic-build : rc [1-9][0-9]* en [0-9]* s$' "$x/construire.log" || true)" 1
  attendu "lignes « Expected digest for image » dans la sortie de mock (au moins une)" \
    "$(sed -n 's/^lignes « Expected digest for image » : sortie \([0-9]*\) ; root.log [0-9]*$/\1/p' "$x/construire.log" | sed 's/^[1-9][0-9]*$/au moins une/')" "au moins une"
  attendu "fin du script : mock en échec, aucun rpm" "$(grep -c '^mock en échec$' "$x/construire.log" || true) $(grep -c '^rpm : ' "$x/construire.log" || true)" "1 0"
  echo "relevé : $(grep '^lignes « \(Using\|Checking\|Expected\|falling\)' "$x/construire.log" | paste -sd' ' -)"
  echo "relevé : première ligne de mock « Expected digest for image » : $(grep -v '^lignes « ' "$x/construire.log" | grep -m 1 -o 'Expected digest for image.*' | cut -c1-300)"
  echo "écarts : $ECARTS"
  [ "$ECARTS" = 0 ]
}
# --- fin des copies pour la pipeline ---

sources_cascade() { # sha256 des gabarits et des tâches signées ; références de la liste revue ; bootstrap du verrou neuf
  local e
  for e in $GABARITS_SHA; do attendu "${e%%:*} (sha256)" "$(sha "$h05/${e%%:*}")" "${e#*:}"; done
  attendu "preparer-rpm de M4c, lue dans la liste revue" "$(ref_revue preparer-rpm 2f65f390)" "$PREPARER_REF"
  attendu "construire-rpm de la cascade, lue dans la liste revue" "$(ref_revue construire-rpm ca03f189)" "$CONSTRUIRE_REF"
  attendu "verrou neuf : dossier dir: du bootstrap (config.bootstrap_image et pull_digest)" \
    "$(jq -r '.config.bootstrap_image' "$VERROU" | cut -d: -f1)@$(jq -r '.bootstrap.pull_digest' "$VERROU")" "$BOOT_DOSSIER"
  attendu "verrou neuf : image_digest du bootstrap" "$(jq -r '.bootstrap.image_digest' "$VERROU")" "$IMAGE_DIGEST_BOOT"
  attendu "fermeture tirée : arbre de depot/ (chemin, taille, sha256) égal à celui de l'essai de M4b refait (sha256 de la liste)" \
    "$(cd "$TIREE/depot" && find . -type f -printf '%P %s\n' | sort | while read -r e s; do echo "$e $s $(sha "$e")"; done | sha256sum | cut -c1-64)" "$ARBRE_FERMETURE_SHA"
}
signees_egales() { # tâches rendues par rendre_taches, égales (normalisées) aux tâches signées versionnées ; script de construire
  attendu "preparer-rpm rendue égale à construction/preparer-rpm.signee.yaml (M4c), normalisées" \
    "$(cmp -s <(normaliser "$T/preparer-rpm.yaml") <(normaliser "$C/preparer-rpm.signee.yaml") && echo égale || echo différente)" égale
  attendu "construire-rpm rendue égale à construction/construire-rpm.m1b.signee.yaml (cascade), normalisées" \
    "$(cmp -s <(normaliser "$T/construire-rpm.yaml") <(normaliser "$C/construire-rpm.m1b.signee.yaml") && echo égale || echo différente)" égale
  attendu "construire-rpm signée : script substitué égal à celui des essais de M4c et des bundles (sha256)" \
    "$(script_etape "$C/construire-rpm.m1b.signee.yaml" construire | sed -e 's#\$(workspaces.entrees.path)#/e#g' \
      -e 's#\$(workspaces.sortie.path)#/o#g' -e 's#\$(results.DIGEST_CONSTRUIT.path)#/w/digest#g' | sha256sum | cut -c1-64)" "$SCRIPT_CONSTRUIRE_SHA"
}
hermetique() { # journal du script : lignes de la construction hermétique relevées, sans arrêter (mesure) ; premier passage du
  # bootstrap de M1b (couche non compressée) et de son image_digest dans mock
  local j=$1 a
  for a in "dossier dir: $BOOT_DOSSIER ; image_digest du verrou $IMAGE_DIGEST_BOOT" \
      "lignes « Using container image: dir: » : sortie 1 ; root.log 1" \
      "lignes « Checking image digest: $IMAGE_DIGEST_BOOT » : sortie 1 ; root.log 1" \
      "lignes « Expected digest for image » : sortie 0 ; root.log 0" \
      "lignes « falling back to chroot installation » : sortie 0 ; root.log 0" \
      "lignes « No space left on device » : sortie 0 ; root.log 0" \
      "lignes http ou https de mock.out : 0" "lignes http ou https de root.log : 0" "lignes http ou https de build.log : 0" \
      "paquets du buildroot (rpm --root) : 222"; do
    mesure "ligne du script « $a »" "$(grep -c -x -F -- "$a" "$j" || true)" 1
  done
  mesure "ligne du script « mock --hermetic-build : rc 0 en … s »" "$(grep -c '^mock --hermetic-build : rc 0 en [0-9]* s$' "$j" || true)" 1
  mesure "témoins réseau en échec" "$(grep -c '^témoin .* : échec, code [0-9]* (attendu)$' "$j" || true)" 4
  echo "relevé : $(grep '^mock --hermetic-build : ' "$j" || echo 'aucune ligne mock --hermetic-build') ; $(grep '^avant mock, capacité de /w' "$j" || echo '-') ; $(grep '^après mock' "$j" || echo '-')"
}
enveloppes_att() { # moment : relevé, sans pari, du nombre de couches du manifeste .att de l'artefact (une par enveloppe d'attestation),
  # lecture anonyme ; la publication d'un digest déjà présent s'observe par là (décision « Même dépôt »)
  local r=${IMAGE#"$REG"/}:sha256-${DIGEST_ESSAI#sha256:}.att
  if oras manifest fetch --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" --output "$T/att-$1.json" "$REG_HOTE/$r" < /dev/null 2> "$T/oras.err"; then
    echo "relevé : enveloppes d'attestation de l'artefact ($1) : $(jq '.layers | length' "$T/att-$1.json") (manifeste .att sha256:$(sha "$T/att-$1.json"))"
  else
    echo "relevé : manifeste .att de l'artefact illisible ($1) : $(head -c 160 "$T/oras.err" | tr '\n' ' ')"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  for e in "$@"; do [ ! -e "$R/$N-construction-$e.log" ] || { echo "journal déjà présent, jamais réécrit : resultats/$N-construction-$e.log" >&2; exit 2; }; done
  lancer "$N-construction" "05 cascade de M1b, M4c refait" "$@"
fi
