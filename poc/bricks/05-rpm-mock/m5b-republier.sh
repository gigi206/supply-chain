#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, M5b sous l'option C : republication sans signature des tâches et des pipelines rpm de M1b, depuis leurs signatures
# versionnées, pour le rejeu de zéro (préparée à sec le 20/11/2026 ; carte resultats/m5b-carte.md). Script frère : les m1b-*.sh
# de mesure ne sont pas touchés. Fondée sur le banc du 20/11/2026 (RE1 à RE7) : un même fichier signé, poussé par bundle
# (commun.sh) sous le fuseau Europe/Paris et sans SOURCE_DATE_EPOCH, redonne le digest de la liste revue, quel que soit le tag.
#   taches                 prefetch-rpm et construire-rpm (signatures de la cascade, *.m1b.signee.yaml), preparer-rpm (M4c)
#   pipeline_fermeture     prefetch-rpm-sample-app (fermeture/prefetch-rpm-sample-app.m1b.signee.yaml)
#   pipeline_construction  sample-app-rpm (construction/sample-app-rpm.m1b.signee.yaml)
# Chaque étape contrôle tous ses fichiers avant toute poussée : sha256 du fichier égal à la valeur épinglée ; annotation de
# signature présente ; digest attendu épinglé, égal à une référence de la liste revue de la 08 (tâches) ou à la ligne
# PIPELINE_REF du script de mesure (pipelines) ; chaque référence par digest du contenu signé présente dans Zot (lecture
# anonyme) ; tag $TAG absent ou déjà sur le digest attendu (jamais déplacé). Puis bundle au tag $TAG, dans l'ordre, et arrêt au
# premier digest différent de l'attendu (KO ; ce bundle reste poussé, aucun autre ne l'est après lui).
# Ordre dans le rejeu, imposé par les références des contenus signés : m1b-signature.sh taches et m1b-pipeline.sh pipeline
# (images), taches ; artefact de M4a et m1b-artefact.sh publier ; pipeline_fermeture ; m1b-fermeture.sh rpm (fermeture) ;
# pipeline_construction ; m1b-construction.sh construction. TAG doit être celui des étapes de mesure qui suivent : rpm et
# construction relisent la pipeline au tag $TAG.
# Rien n'est signé ici, aucune clé n'est lue. Un digest différent demande une nouvelle signature et une revue de la liste :
# décision du propriétaire, jamais prise ici.
# Garde : octets libres sur / de sc-stockage (porte /var/lib/zot) au moins LIBRE_MIN avant la première poussée de chaque étape.
# Aucun secret en argument ; l'authentification de Zot est écrite sous $T/auth (0700) et retirée à la sortie, même en échec.
# Usage (racine du dépôt) : TAG=<tag> DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m5b-republier.sh <étape>…
#         (journaux : resultats/m5b-republier-<tag>-<étape>.log, jamais réécrits)
set -euo pipefail
export LC_ALL=C
export TZ=Europe/Paris   # tkn 0.46.2 écrit l'époque 0 en heure locale, et le digest en dépend (RE5 à RE7, 20/11/2026)
unset SOURCE_DATE_EPOCH  # lue par tkn bundle push

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
# shellcheck disable=SC1091  # chemin calculé
. "$here/commun.sh"   # O, S, P, W, REG, REG_HOTE, bundle, auth_zot, sur, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
TAG=${TAG:-}
case $TAG in
  m4b|m4c|essai) echo "tag refusé : $TAG appartient à M4b, M4c ou aux essais" >&2; exit 2 ;;
  ''|*[!a-z0-9-]*) echo "TAG absent ou invalide : « $TAG » (celui des étapes de mesure qui suivent)" >&2; exit 2 ;;
esac
T=$W/m5b-republier-$TAG-05
(umask 077 && mkdir -p "$T/auth")
LISTE_REVUE=${LISTE_REVUE:-$here/politique/porte/taches.yml}
LIBRE_MIN=1073741824   # m4b.sh
TKN_VERSION=0.46.2     # seule version mesurée (RE1 à RE7)
DECALAGE=+01:00        # décalage de l'époque 0 sous Europe/Paris, celui des digests de la liste revue (RE7)
# fichier (relatif à la brique) dépôt sha256-du-fichier digest-attendu source-de-l'attendu
TACHES_M1B="fermeture/prefetch-rpm.m1b.signee.yaml tekton/tasks/prefetch-rpm d28acd2283bdf9648619c22055001b2436ddf228e1c1350d107cbe9af0a142e2 sha256:b9bbeba3e8c62113431cdb88aa74afe76bab13a28ab548a5b5ae6ffed22675dc liste
construction/construire-rpm.m1b.signee.yaml tekton/tasks/construire-rpm 90151d43270fc2fa1a77765f4c6acdacdc2ecd2033d9bc0aa8494c5517f0a31b sha256:ca03f18908d0b5e73edc57ecf9610513e2907267ce1da2d9f41fd36b969289c5 liste
construction/preparer-rpm.signee.yaml tekton/tasks/preparer-rpm b32d073f75ca03aa48100f7052a23316297b8d5e318e7796ebc8a729b1d7acf9 sha256:2f65f3903e98caa9944ab3fee4b67585b15d67ad477ff48a8487e8e86af5526f liste"
PIPE_FERMETURE="fermeture/prefetch-rpm-sample-app.m1b.signee.yaml tekton/pipelines/prefetch-rpm-sample-app be99c8f946849d92fa92b7db354138bee1880ee123186406107d012f18215ffd sha256:61814acd6f15f0fde07f9f701f2e8cfd4324218caf2df9e1befcf182495ca60c m1b-fermeture.sh"
PIPE_CONSTRUCTION="construction/sample-app-rpm.m1b.signee.yaml tekton/pipelines/sample-app-rpm 8b96852f970da6e1bccab3491587705cff16cafdf3649e312f9d6b87208e66e8 sha256:7d361cb1d5ea9b7994727f839bc4365a29e4ebdc7948fceff4176b4a371abd6a m1b-construction.sh"

echec() { echo "KO   $*" >&2; exit 1; }
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echec "$1 : $2 (attendu : $3)"; fi; }
libre_zot() { sur sc-stockage 'df -B1 --output=avail / | tail -n 1' < /dev/null | tr -d ' '; }   # m4b.sh
present() { # libellé référence-sans-registre : digest si présent, « absent » sur MANIFEST_UNKNOWN ou NAME_UNKNOWN seuls, sinon
  local d   # échec ; lecture anonyme (configuration vide)
  if d=$(DOCKER_CONFIG=$T/anonyme SSL_CERT_FILE=$P/ca-poc.crt crane digest "$REG_HOTE/$2" < /dev/null 2> "$T/crane.err"); then
    echo "$d"
  elif grep -q -E 'MANIFEST_UNKNOWN|NAME_UNKNOWN' "$T/crane.err"; then
    echo absent
  else
    echec "$1 : NON CONCLUANT, $(grep -v 'falling back on GET' "$T/crane.err" | head -c 160 | tr '\n' ' ')"
  fi
}
refs_signees() { # fichier : références par digest du contenu signé (registre des pods), sans doublon, triées
  grep -v 'tekton.dev/signature:' "$1" | grep -o "$REG/[a-z0-9._/-]*@sha256:[0-9a-f]\{64\}" | sort -u || true
}
listee() { # dépôt référence : « listée » si la référence exacte est sous ce dépôt dans la liste revue, sinon « absente »
  awk -v d="oci://$REG/$1:" -v r="$2" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && $3 == r {t = 1} END {print (t ? "listée" : "absente")}' "$LISTE_REVUE"
}
pipeline_ref() { # script dépôt : digest de la ligne PIPELINE_REF= du script de mesure
  sed -n "s#^PIPELINE_REF=\$REG/$2@\(sha256:[0-9a-f]\{64\}\) .*#\1#p" "$h05/$1"
}

entree() { # fuseau, SOURCE_DATE_EPOCH, version de tkn ; configuration anonyme
  attendu "fuseau : décalage de l'époque 0 (TZ=$TZ)" "$(date -d @0 +%:z)" "$DECALAGE"
  attendu "SOURCE_DATE_EPOCH" "${SOURCE_DATE_EPOCH-absente}" absente
  attendu "tkn (client)" "$(tkn version --component client)" "$TKN_VERSION"
  mkdir -p "$T/anonyme" && echo '{}' > "$T/anonyme/config.json"
  echo "registre (hôte) : $REG_HOTE ; tag : $TAG ; liste revue : sha256 $(sha256sum < "$LISTE_REVUE" | cut -c1-64)"
}
controler() { # lignes : tous les contrôles de tous les fichiers, avant toute poussée
  local f depot sha att src r d k
  while read -r f depot sha att src; do
    echo "## $f"
    attendu "sha256 du fichier" "$(sha256sum < "$h05/$f" | cut -c1-64)" "$sha"
    attendu "annotation de signature" "$(yq '.metadata.annotations["tekton.dev/signature"] | length > 0' "$h05/$f")" true
    case $src in
      liste) attendu "$depot@$att dans la liste revue" "$(listee "$depot" "$att")" listée ;;
      *) attendu "digest attendu égal à PIPELINE_REF de $src" "$(pipeline_ref "$src" "$depot")" "$att" ;;
    esac
    k=0
    while read -r r; do
      [ -n "$r" ] || continue
      d=$(present "${r#"$REG"/}" "${r#"$REG"/}")
      attendu "référence du contenu signé présente dans Zot : ${r#"$REG"/}" "$d" "${r##*@}"
      k=$((k + 1))
    done < <(refs_signees "$h05/$f")
    echo "références par digest du contenu signé : $k"
    d=$(present "tag $TAG" "$depot:$TAG")
    [ "$d" = absent ] || [ "$d" = "$att" ] || echec "$depot:$TAG déjà sur $d (attendu : absent ou $att) ; jamais déplacé ici"
    echo "OK   $depot:$TAG avant la poussée : $d"
  done <<< "$1"
}
pousser_tout() { # lignes : bundles au tag $TAG dans l'ordre ; arrêt au premier digest différent de l'attendu
  local f depot sha att src d n=0
  while read -r f depot sha att src; do
    d=$(bundle "$h05/$f" "$depot" "$TAG")
    n=$((n + 1))
    echo "poussée $n : $depot:$TAG"
    attendu "$f poussé, digest" "$d" "$att"
    d=$(present "tag $TAG après" "$depot:$TAG")
    attendu "$depot:$TAG relu (lecture anonyme)" "$d" "$att"
  done <<< "$1"
  echo "poussées : $n"
}
republier() { # lignes
  local libre
  entree
  controler "$1"
  libre=$(libre_zot)
  echo "relevé : octets libres sur / de sc-stockage (porte /var/lib/zot) avant les poussées : $libre"
  [ "$libre" -ge "$LIBRE_MIN" ] 2> /dev/null || echec "octets libres sur / de sc-stockage sous $LIBRE_MIN : $libre"
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # bundle (commun.sh), compte poc-ecriture
  echo "## poussées (tag $TAG, tkn $(tkn version --component client), TZ=$TZ)"
  pousser_tout "$1"
}

etape_taches() { republier "$TACHES_M1B"; }
etape_pipeline_fermeture() { republier "$PIPE_FERMETURE"; }
etape_pipeline_construction() { republier "$PIPE_CONSTRUCTION"; }

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  trap 'find "$T/auth" -depth -delete 2> /dev/null || true' EXIT   # copies de secrets, retirées même en cas d'échec (sans rm)
  for e in "$@"; do
    [ ! -e "$R/m5b-republier-$TAG-$e.log" ] || { echo "journal déjà présent, jamais réécrit : m5b-republier-$TAG-$e.log" >&2; exit 2; }
  done
  lancer "m5b-republier-$TAG" "05 M5b republication ($TAG)" "$@"
fi
