#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, cascade de M1b (§5 de resultats/m1b-carte.md), deuxième point : l'artefact de packaging rpm de M4a republié avec le
# verrou de la cascade (resultats/m1b-verrou.json, c544599a), sous un tag neuf du même dépôt. Préparé à sec le 20/11/2026.
# Script frère de m4a.sh, qui n'est pas touché : son banc, ses journaux et poc/packaging/verrou-rpm.json (b6d0f8f1, verrou de
# M4a) restent tels quels. L'artefact est assemblé dans une zone de préparation neuve sous $T, avec les noms que lisent les
# tâches signées (preparer-rpm : packaging/sample-app.spec et packaging/verrou-rpm.json) :
#   sample-app.spec  copie de poc/packaging/sample-app.spec (918a83f5, celui de M4a) ;
#   verrou-rpm.json  copie de resultats/m1b-verrou.json (c544599a).
# Repris de m4a.sh à l'identique (le banc les compare) : attendu, fichiers, DEPOT, TYPE, CREE ; pousser ne diffère que par le
# dossier poussé, passé en premier argument au lieu de poc/packaging.
#   local    hôte seul, hors ligne : sources contrôlées par sha256 ; verrou neuf contrôlé contre des sources indépendantes (222 rpm
#            égaux à ceux du verrou de M4a, pull_digest et id du bootstrap de M1b) ; image_digest relevé, forme seule (c'est
#            une prédiction de M4b) ; témoin de méthode : la même préparation avec le verrou de M4a et le tag neuf redonne
#            41c639b7 ; artefact neuf poussé dans deux layouts OCI locaux, même digest ; manifeste neuf comparé à celui de M4a
#            ($W/m4a-05/layout-1, lu seulement) : seuls le digest et la taille de la couche du verrou diffèrent.
#   releve   lecture seule : tag neuf absent de Zot (seul un « not found » vaut absent), tag m4a sur 41c639b7 (lecture anonyme
#            par l'adresse IP), octets libres sur / de sc-stockage (porte /var/lib/zot).
#   publier  écriture dans Zot, sur accord nommé du propriétaire (compte poc-ecriture, comme m4a.sh) : gardes de releve rejouées,
#            deux poussées, digest égal au digest local ; artefact tiré par digest dans un dossier neuf, fichiers égaux à la zone
#            de préparation ; tag m4a toujours sur 41c639b7 après. Écriture définitive (pas de droit de suppression dans Zot).
# Aucun secret en argument ; l'authentification de Zot est écrite sous $T/auth (0700) et retirée à la sortie, même en échec.
# Un journal existant n'est jamais réécrit : relancer sous un autre PREFIXE (et donc un autre tag par défaut).
# Usage (racine du dépôt) : [PREFIXE=m1b] [TAG=$PREFIXE] DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/m1b-artefact.sh <étape>…
#         (journaux : resultats/$PREFIXE-artefact-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, P, W, REG, REG_HOTE, auth_zot, sur, lancer, chrono
R=$h05/resultats   # journaux de lancer (commun.sh)
export R
N=${PREFIXE:-m1b}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
TAG=${TAG:-$N}
case $TAG in m4a) echo "tag refusé : m4a appartient à l'artefact de M4a" >&2; exit 2 ;; ''|*[!a-z0-9-]*) echo "TAG invalide : $TAG" >&2; exit 2 ;; esac
T=$W/$N-artefact-05
umask 022

# Valeurs reprises de m4a.sh (le banc compare ces lignes à celles de m4a.sh)
DEPOT=entrees/sample-app/packaging-rpm
TYPE=application/vnd.supply-chain.packaging-rpm.v1
CREE=1970-01-01T00:00:00Z

# Sources et références (le banc les confronte à des journaux indépendants)
SPEC=$repo/poc/packaging/sample-app.spec
SPEC_SHA=918a83f592c31d322a77a4e887c808c61077e2f100442dc98abed5c67ae582a6        # m4a-verrou.log
VERROU_NEUF=$R/m1b-verrou.json
VERROU_NEUF_SHA=c544599aba4b7460f7496066e7c0361c80a59b8e345655553509024a254a6c83  # m1b-verrou-verrou.log
VERROU_M4A=$repo/poc/packaging/verrou-rpm.json
VERROU_M4A_SHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f   # VERROU_SHA de m4a.sh
M4A_DIGEST=sha256:41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8 # m4a-publier.log
M4A_LAYOUT=$W/m4a-05/layout-1                                                      # étape verrou de M4a, lue seulement
BOOTSTRAP=$REG/builds/builders/rocky9-bootstrap@sha256:6de899ac5da41852c5d8518abdb3785eabf41a379bd267ae61bb4db4e8dae6f3   # M1b
ID_BOOTSTRAP=ff96017c3f06a35a11d06a454930ec797002708cd0187ac46d7febe0891444a2       # configuration de l'image, G2 de m1b-verrou
LIBRE_MIN=1073741824                                                               # comme m1b-signature.sh

# --- recopié de m4a.sh ---
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
fichiers() { printf '%s\n' sample-app.spec verrou-rpm.json; }   # contenu de l'artefact, relatif à poc/packaging
# --- fin de la copie ---
pousser() { # dossier cible-oras (--oci-layout dir:tag, ou référence de registre) [options…] : digest du manifeste
  local dossier=$1 cible=$2; shift 2
  local f=() x
  while IFS= read -r x; do f+=("$x:$TYPE.file"); done < <(fichiers)
  (cd "$dossier" && oras push "$@" --no-tty --format go-template='{{.digest}}' --artifact-type "$TYPE" \
    --annotation "org.opencontainers.image.created=$CREE" "$cible" "${f[@]}")
}
echec() { echo "KO   $*" >&2; exit 1; }
neuf() { [ ! -e "$1" ] || echec "déjà présent, jamais réécrit : ${1#"$W"/}"; }
sha() { sha256sum < "$1" | cut -c1-64; }
preparer() { # dossier verrou : zone de préparation neuve, deux fichiers aux noms de l'artefact
  neuf "$1"; mkdir "$1"
  cp "$SPEC" "$1/sample-app.spec"; cp "$2" "$1/verrou-rpm.json"
  attendu "zone ${1##*/} : fichiers" "$(find "$1" -mindepth 1 -printf '%P %y\n' | sort | paste -sd' ')" "sample-app.spec f verrou-rpm.json f"
  attendu "zone ${1##*/} : copies égales aux sources" "$(cmp -s "$SPEC" "$1/sample-app.spec" && cmp -s "$2" "$1/verrou-rpm.json" && echo égales)" égales
}
blob() { # layout digest : chemin du blob, contrôlé par son sha256
  local b=$1/blobs/sha256/${2#sha256:}
  [ "sha256:$(sha "$b")" = "$2" ] || echec "blob ${2:0:19}… de ${1#"$W"/} : sha256 différent"
  echo "$b"
}
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
libre_zot() { sur sc-stockage 'df -B1 --output=avail / | tail -n 1' < /dev/null | tr -d ' '; }   # m4b.sh, m1b-signature.sh

# Manifeste neuf contre manifeste de M4a : feuilles différentes, attendues exactement (digest et taille de la couche du verrou)
COMPARE_MANIFESTE=$(cat <<'PY'
import json, sys
neuf, ancien, verrou_d, verrou_t = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
a, b = json.load(open(ancien)), json.load(open(neuf))
ecarts = []
def feuilles(x, y, chemin):
    if isinstance(x, dict) and isinstance(y, dict):
        for k in sorted(set(x) | set(y)):
            if k not in x or k not in y: ecarts.append((f'{chemin}.{k}', x.get(k), y.get(k)))
            else: feuilles(x[k], y[k], f'{chemin}.{k}')
    elif isinstance(x, list) and isinstance(y, list) and len(x) == len(y):
        for i, (u, v) in enumerate(zip(x, y)): feuilles(u, v, f'{chemin}[{i}]')
    elif x != y:
        ecarts.append((chemin, x, y))
feuilles(a, b, '')
for c, x, y in ecarts: print(f'     {c} : {x} -> {y}')
titres = [l.get('annotations', {}).get('org.opencontainers.image.title') for l in b.get('layers', [])]
i = titres.index('verrou-rpm.json') if titres.count('verrou-rpm.json') == 1 else -1
prevu = {f'.layers[{i}].digest', f'.layers[{i}].size'}
ok = i >= 0 and {c for c, _, _ in ecarts} == prevu and b['layers'][i]['digest'] == verrou_d and b['layers'][i]['size'] == verrou_t
print(f'{"OK  " if ok else "KO  "} A5 manifeste neuf contre celui de M4a : {len(ecarts)} feuille(s) différente(s), '
      f'prévues : couche {i} (verrou-rpm.json), digest et taille ; titres {titres}')
sys.exit(0 if ok else 1)
PY
)

etape_local() {
  echo "## A1 sources (sha256)"
  attendu "A1 poc/packaging/sample-app.spec" "$(sha "$SPEC")" "$SPEC_SHA"
  attendu "A1 resultats/m1b-verrou.json" "$(sha "$VERROU_NEUF")" "$VERROU_NEUF_SHA"
  attendu "A1 poc/packaging/verrou-rpm.json (verrou de M4a, inchangé)" "$(sha "$VERROU_M4A")" "$VERROU_M4A_SHA"
  echo "## A2 verrou neuf contre des sources indépendantes"
  python3 -I - "$VERROU_NEUF" "$VERROU_M4A" "$BOOTSTRAP" "$ID_BOOTSTRAP" <<'PY'
import json, re, sys
v, a = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
image, ident = sys.argv[3], sys.argv[4]
rpms = v['buildroot']['rpms']
noms = {(r['name'], r['arch']) for r in rpms}
hors = [r['url'] for r in rpms if not r['url'].startswith('https://dl.rockylinux.org/vault/rocky/9.7/') or '..' in r['url']]
b = v['bootstrap']
ok = (v['version'] == '1.1.0' and len(rpms) == 222 and len(noms) == 222 and not hors and rpms == a['buildroot']['rpms']
      and v['config']['bootstrap_image'] == image and b['pull_digest'] == image.split('@', 1)[1] and b['id'] == ident
      and v['config']['bootstrap_image_ready'] is True and b['architecture'] == 'amd64')
print(f'{"OK  " if ok else "KO  "} A2 verrou neuf : version {v["version"]}, {len(rpms)} rpm ({len(noms)} nom.arch distincts), '
      f'égaux à ceux du verrou de M4a : {rpms == a["buildroot"]["rpms"]}, {len(hors)} URL hors de vault 9.7, '
      f'bootstrap_image {v["config"]["bootstrap_image"]}, id {b["id"][:12]}…, ready {v["config"]["bootstrap_image_ready"]}, {b["architecture"]}')
forme = bool(re.fullmatch('[0-9a-f]{64}', b['image_digest']))
print(f'{"OK  " if forme else "KO  "} A2 image_digest, forme seule (prédiction de M4b, non contrôlée ici) : {b["image_digest"]}')
sys.exit(0 if ok and forme else 1)
PY
  mkdir -p "$T"
  echo "## A3 témoin de méthode : verrou de M4a, tag $TAG, zone neuve"
  preparer "$T/temoin" "$VERROU_M4A"
  neuf "$T/layout-temoin"
  attendu "A3 digest du témoin égal à celui de M4a" "$(pousser "$T/temoin" "$T/layout-temoin:$TAG" --oci-layout)" "$M4A_DIGEST"
  echo "## A4 artefact neuf, deux layouts locaux"
  preparer "$T/paquet" "$VERROU_NEUF"
  echo "artefact : $(fichiers | paste -sd' ')"
  fichiers | (cd "$T/paquet" && xargs sha256sum) | sed 's/^/     /'
  local d1 d2 m a
  neuf "$T/layout-1"; neuf "$T/layout-2"
  d1=$(pousser "$T/paquet" "$T/layout-1:$TAG" --oci-layout)
  d2=$(pousser "$T/paquet" "$T/layout-2:$TAG" --oci-layout)
  attendu "A4 deux poussées locales, même digest" "$d1" "$d2"
  [ "$d1" != "$M4A_DIGEST" ] || echec "A4 digest neuf égal à celui de M4a"
  echo "## A5 manifeste neuf contre celui de M4a"
  m=$(blob "$T/layout-1" "$d1"); a=$(blob "$M4A_LAYOUT" "$M4A_DIGEST")
  python3 -I -c "$COMPARE_MANIFESTE" "$m" "$a" "sha256:$VERROU_NEUF_SHA" "$(stat -c %s "$VERROU_NEUF")"
  echo "manifeste neuf : $(stat -c %s "$m") octets ; couches : $(jq -r '[.layers[].size] | add' "$m") octets"
  echo "$d1" > "$T/digest-local"
  echo "digest attendu dans Zot : $d1 (tag $TAG)"
}

gardes_zot() { # lecture seule : tag neuf absent, tag m4a sur M4a, place libre ; suffixe du libellé
  echo '{}' > "$T/vide.json"
  attendu "G1 $DEPOT:$TAG, lecture anonyme ($1)" "$(zot_lire "tag $TAG" "$DEPOT:$TAG")" absent
  attendu "G2 $DEPOT:m4a, lecture anonyme ($1)" "$(zot_lire "tag m4a" "$DEPOT:m4a")" "$M4A_DIGEST"
  local libre
  libre=$(libre_zot)
  case $libre in ''|*[!0-9]*) echec "G3 place libre illisible : $libre" ;; esac
  [ "$libre" -ge "$LIBRE_MIN" ] || echec "G3 place libre sur / de sc-stockage : $libre octets, sous $LIBRE_MIN"
  echo "OK   G3 octets libres sur / de sc-stockage (porte /var/lib/zot), $1 : $libre (seuil $LIBRE_MIN)"
}

etape_releve() {
  mkdir -p "$T"
  [ -s "$T/digest-local" ] && echo "digest local (étape local) : $(cat "$T/digest-local")" || echo "digest local : étape local non passée"
  gardes_zot "relevé"
}

etape_publier() {
  [ -s "$T/digest-local" ] || echec "étape local à lancer d'abord (digest local absent)"
  local attendu_d d1 d2
  attendu_d=$(cat "$T/digest-local")
  attendu "P0 sources inchangées depuis l'étape local" "$(sha "$SPEC") $(sha "$VERROU_NEUF")" "$SPEC_SHA $VERROU_NEUF_SHA"
  attendu "P0 zone de préparation inchangée" "$(sha "$T/paquet/sample-app.spec") $(sha "$T/paquet/verrou-rpm.json")" "$SPEC_SHA $VERROU_NEUF_SHA"
  gardes_zot "avant"
  neuf "$T/tire"
  (umask 077 && mkdir -p "$T/auth/docker")
  trap 'find "$T/auth" -depth -delete 2> /dev/null || true' EXIT   # copies de secrets, retirées même en cas d'échec (sans rm)
  auth_zot "$T/auth/docker/config.json"   # compte poc-ecriture, comme m4a.sh
  d1=$(pousser "$T/paquet" "$REG_HOTE/$DEPOT:$TAG" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json")
  d2=$(pousser "$T/paquet" "$REG_HOTE/$DEPOT:$TAG" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json")
  attendu "P1 deux poussées dans Zot, même digest" "$d1" "$d2"
  attendu "P1 digest Zot égal au digest local" "$d1" "$attendu_d"
  mkdir "$T/tire"
  (cd "$T/tire" && oras pull --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json" --no-tty \
    "$REG_HOTE/$DEPOT@$d1" > /dev/null)
  attendu "P2 fichiers tirés par digest égaux à la zone de préparation" \
    "$(cd "$T/tire" && find . -type f -printf '%P\n' | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)" \
    "$(fichiers | sort | (cd "$T/paquet" && xargs sha256sum) | sha256sum | cut -d' ' -f1)"
  attendu "P3 $DEPOT:$TAG, lecture anonyme après" "$(zot_lire "tag $TAG" "$DEPOT:$TAG")" "$d1"
  attendu "P3 $DEPOT:m4a, lecture anonyme après" "$(zot_lire "tag m4a" "$DEPOT:m4a")" "$M4A_DIGEST"
  echo "octets libres sur / de sc-stockage après : $(libre_zot)"
  echo "PACKAGING_RPM=$REG/$DEPOT@$d1"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  for e in "$@"; do [ ! -e "$R/$N-artefact-$e.log" ] || { echo "journal déjà présent, jamais réécrit : resultats/$N-artefact-$e.log" >&2; exit 2; }; done
  lancer "$N-artefact" "05 cascade de M1b, artefact" "$@"
fi
