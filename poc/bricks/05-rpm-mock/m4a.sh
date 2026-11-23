#!/usr/bin/env bash
# Brique 05, jalon M4a (découpage décidé par le propriétaire le 17/11/2026, « Oui, ce découpage » ; verrou hors de la plateforme,
# « Hors plateforme » ; images d'essai, « Option 1 ») : relevé de l'état en service, puis artefact de packaging du rpm, publié par
# l'hôte dans Zot sur le modèle de packaging-deb (s4c.sh de la 06). Il contient poc/packaging/sample-app.spec inchangé et le
# verrou de verrou_derivee (resultats/s1-verrou_derivee.json, b6d0f8f1, repris tel quel, sans nouvelle résolution), copié sous
# poc/packaging/verrou-rpm.json. Prédictions : resultats/m4a-predictions.md, commitées avant tout lancement.
#   releve   lecture seule (API du cluster, Zot en anonyme par l'adresse IP) : objets dont M4 dépend comparés au dépôt champ par
#            champ (spec, différences listées, rien de retiré) ; valeur par défaut des ressources de Tekton (config-defaults,
#            08c) ; ConfigMap porte (sha256 de chaque clé tirée d'un fichier de politique du dépôt, 08 et 07a ; les autres clés,
#            par nom seul) ; feature-flags de Tekton ; noms des NetworkPolicy et CiliumNetworkPolicy de builds ; politiques
#            Kyverno et ImageValidatingPolicy en service, par nom ; Zot : images d'essai et fermeture applicative présentes par
#            digest, artefact de M4a absent (seul un « not found » vaut absent). N'écrit rien. Aucun secret lu ; aucun événement
#            affiché ; aucune clé affichée. Gabarits et déclencheurs non relevés : hors de M4 (décision du 17/11/2026).
#            verrou et publier attendent la carte de M4b : ce que prefetch-rpm lira (le verrou n'a ni sha256 ni taille).
#   politiques  lecture seule, complément de releve (ajouté le 17/11/2026, « Oui, complète-le ») : toutes les ValidatingPolicy de
#            admission.yaml (08) et de durcissement.yaml (08c), énumérées par yq et non plus écrites à la main ; celles de la 08c
#            comparées au fichier rendu comme par l'étape h5_deny de durcissement.sh (Audit remplacé par Deny, même sed) ;
#            ensemble des noms en service confronté à celui du dépôt. Journal à part : celui de releve n'est pas réécrit.
#   verrou   hôte seul, hors ligne : verrou contrôlé (sha256, 222 rpm, bootstrap), copié sous poc/packaging/verrou-rpm.json
#            s'il est absent (sinon comparé) ; artefact poussé deux fois dans deux layouts OCI locaux, même digest attendu
#   publier  écriture dans Zot (compte poc-ecriture, comme packaging-deb), sur accord nommé : deux poussées, digest égal à celui
#            des layouts locaux ; artefact tiré par digest dans un répertoire vide, fichiers égaux au dépôt
# Rien n'est supprimé dans Zot (pas de droit de suppression) : le dépôt entrees/sample-app/packaging-rpm est définitif.
#
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/m4a.sh <étape>…
# (journal : resultats/m4a-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "$0")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE, auth_zot, lancer, chrono
R=$h05/resultats
PKG=$repo/poc/packaging
VERROU_SRC=$R/s1-verrou_derivee.json
VERROU=$PKG/verrou-rpm.json
VERROU_SHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f   # verrou_derivee (303b428)
PULL_DIGEST=sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6   # boot_image
IMAGE_DIGEST=18d64b0330fe240fff58475e43a3f003e5dcfade898c4caa1d1165e8304be1af        # hermetique (« Checking image digest »)
OUTILLAGE=essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771   # image, M3
BOOTSTRAP=essais-05/rocky9-bootstrap@$PULL_DIGEST
SOURCES=builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21   # S4b (06)
DEPOT=entrees/sample-app/packaging-rpm
TYPE=application/vnd.supply-chain.packaging-rpm.v1
CREE=1970-01-01T00:00:00Z
T=$W/m4a-05
mkdir -p "$T"
(umask 077 && mkdir -p "$T/auth")
trap 'rm -rf "$T/auth"' EXIT   # copies de secrets, même en cas d'échec
umask 022

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
fichiers() { printf '%s\n' sample-app.spec verrou-rpm.json; }   # contenu de l'artefact, relatif à poc/packaging
pousser() { # cible oras (--oci-layout dir:tag, ou référence de registre) [options…] : digest du manifeste
  local cible=$1; shift
  local f=() x
  while IFS= read -r x; do f+=("$x:$TYPE.file"); done < <(fichiers)
  (cd "$PKG" && oras push "$@" --no-tty --format go-template='{{.digest}}' --artifact-type "$TYPE" \
    --annotation "org.opencontainers.image.created=$CREE" "$cible" "${f[@]}")
}

# Objet du dépôt comparé à l'objet en service : fichier, sélecteur yq du document, champs comparés (spec par défaut).
# Le document du dépôt est rendu en JSON par yq ; kubectl get -f lit l'objet en service de même type, nom et namespace.
COMPARE=$(cat <<'PY'
import json, sys
nom, champ, depot, service = sys.argv[1:5]
d = json.load(open(depot)); s = json.load(open(service))
a, b = d.get(champ), s.get(champ)
ecarts = []
import hashlib
def court(v, chemin):
    t = json.dumps(v, ensure_ascii=False, sort_keys=True)
    if 'key' in chemin.lower() or 'cle' in chemin.lower() or 'BEGIN' in t or 'PUBLIC KEY' in t or 'CERTIFICATE' in t:
        # aucune clé ni certificat affichés, même publics, par chemin ou par contenu : sha256 seul
        return 'sha256 ' + hashlib.sha256(t.encode()).hexdigest()[:12] + '…'
    return t if len(t) <= 140 else t[:140] + '…'
def comparer(x, y, chemin):
    if isinstance(x, dict) and isinstance(y, dict):
        for k in sorted(set(x) | set(y)):
            if k not in y: ecarts.append(f'{chemin}.{k} : dans le dépôt seulement, {court(x[k], chemin + "." + k)}')
            elif k not in x: ecarts.append(f'{chemin}.{k} : en service seulement, {court(y[k], chemin + "." + k)}')
            else: comparer(x[k], y[k], f'{chemin}.{k}')
    elif isinstance(x, list) and isinstance(y, list) and len(x) == len(y):
        for i, (u, v) in enumerate(zip(x, y)): comparer(u, v, f'{chemin}[{i}]')
    elif x != y:
        ecarts.append(f'{chemin} : dépôt {court(x, chemin)} ; en service {court(y, chemin)}')
comparer(a, b, champ)
print(f'{"égal" if not ecarts else "DIFFÉRENT"} : {nom} ({champ}, {len(ecarts)} écart(s))')
for e in ecarts: print(f'     {e}')
PY
)
comparer() { # libellé fichier sélecteur-yq [champ]
  local nom=$1 fic=$2 sel=$3 champ=${4:-spec}
  yq -o=json "select($sel)" "$fic" > "$T/depot.json"
  [ -s "$T/depot.json" ] || { echo "KO   $nom : document absent de ${fic#"$repo"/}" >&2; exit 1; }
  if kubectl get -f "$T/depot.json" -o json < /dev/null > "$T/service.json" 2> "$T/get.err"; then
    python3 -I -c "$COMPARE" "$nom" "$champ" "$T/depot.json" "$T/service.json"
  else
    echo "ABSENT : $nom ($(head -c 160 "$T/get.err" | tr '\n' ' '))"
  fi
}

zot_lire() { # libellé référence-sans-registre attendu(présent|absent) : lecture anonyme par l'adresse IP de Zot
  local nom=$1 ref=$2 voulu=$3 d
  if d=$(oras manifest fetch --descriptor --ca-file "$P/ca-poc.crt" --registry-config "$T/vide.json" \
      "$REG_HOTE/$ref" < /dev/null 2> "$T/oras.err" | jq -r .digest); then
    echo "$([ "$voulu" = présent ] && echo OK || echo KO)   $nom : présent ($d)"
  elif grep -q -i -E 'not found|MANIFEST_UNKNOWN|NAME_UNKNOWN' "$T/oras.err"; then
    echo "$([ "$voulu" = absent ] && echo OK || echo KO)   $nom : absent ($(head -c 160 "$T/oras.err" | tr '\n' ' '))"
  else
    echo "NON CONCLUANT   $nom : $(head -c 160 "$T/oras.err" | tr '\n' ' ')"
  fi
}

etape_releve() {
  local a=$here/politique/admission.yaml c=$repo/poc/bricks/08c-durcissement/politiques
  echo "## objets dont M4 dépend, dépôt contre service (aucun champ retiré de la comparaison)"
  comparer "NetworkPolicy builds/construction-rpm-sans-sortie" "$h05/politiques/construction-rpm-sans-sortie.yaml" '.kind == "NetworkPolicy"'
  comparer "CiliumNetworkPolicy builds/prefetch-rpm-sortie" "$h05/politiques/prefetch-rpm-sortie.yaml" '.kind == "CiliumNetworkPolicy"'
  comparer "CiliumNetworkPolicy builds/builds-sans-internet" "$c/cilium-sortie/builds-sans-internet.yaml" '.kind == "CiliumNetworkPolicy"'
  local v
  for v in tekton-references pods-isolation zone-confiance zone-build; do
    comparer "ValidatingPolicy $v (08)" "$a" ".kind == \"ValidatingPolicy\" and .metadata.name == \"$v\""
  done
  for v in limites-obligatoires images-zot-par-digest espace-default-interdit; do
    comparer "ValidatingPolicy $v (08c)" "$c/kyverno/durcissement.yaml" ".kind == \"ValidatingPolicy\" and .metadata.name == \"$v\""
  done
  # gabarit : la clé publique des tâches remplace @CLE@, comme à la pose (politique.sh de la 08)
  awk -v f="$P/taches.pub" '/^@CLE@$/ { while ((getline l < f) > 0) print "        " l; next } { print }' \
    "$here/politique/verification-policy.yaml" > "$T/verification-policy.yaml"
  comparer "VerificationPolicy builds/taches-plateforme" "$T/verification-policy.yaml" '.kind == "VerificationPolicy"'

  echo "## Tekton : default-container-resource-requirements (config-defaults) contre la 08c ; feature-flags"
  kubectl get configmap config-defaults -n tekton-pipelines -o json < /dev/null \
    | jq '.data["default-container-resource-requirements"] // "" ' -r > "$T/defauts-service.yaml"
  python3 -I -c 'import json, subprocess, sys
a = json.loads(subprocess.run(["yq", "-o=json", ".", sys.argv[1]], capture_output=True, text=True, check=True).stdout)
b = json.loads(subprocess.run(["yq", "-o=json", ".", sys.argv[2]], capture_output=True, text=True, check=True).stdout or "null")
print(("égal" if a == b else "DIFFÉRENT") + " : config-defaults, default-container-resource-requirements (service : " + json.dumps(b, sort_keys=True) + ")")' \
    "$c/tekton-defauts.yaml" "$T/defauts-service.yaml"
  kubectl get configmap feature-flags -n tekton-pipelines -o json < /dev/null \
    | jq -r '.data | to_entries | sort_by(.key) | map("\(.key)=\(.value)") | "feature-flags : " + join(" ")'

  echo "## NetworkPolicy et CiliumNetworkPolicy de builds (noms)"
  for r in networkpolicies ciliumnetworkpolicies; do
    echo "$r : $(kubectl get "$r" -n builds -o json < /dev/null | jq -r '[.items[].metadata.name] | sort | join(" ")')"
  done

  echo "## ConfigMap porte : sha256 de chaque clé tirée d'un fichier de politique du dépôt (08, 07a) ; autres clés : nom seul"
  kubectl get configmap porte -n porte -o json < /dev/null > "$T/cm-porte.json"
  python3 -I - "$T/cm-porte.json" "$here/politique/porte" "$repo/poc/bricks/07a-sbom-grype/politique/porte" <<'PY'
import hashlib, json, os, sys
cm, p08, p07 = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
fichiers = {k: os.path.join(p08, k) for k in ('policy.yaml', 'policy-trusted-task.yaml', 'porte.rego', 'taches.yml', 'horodatage.sh', 'vsa.sh')}
fichiers.update({k: os.path.join(p07, k) for k in ('scan-verifier.sh', 'scan.rego', 'policy-scan.yaml')})
data = cm.get('data', {})
for k in sorted(set(data) | set(fichiers)):
    if k not in data:
        print(f'ABSENTE en service : {k}')
    elif k in fichiers:
        h = hashlib.sha256(data[k].encode()).hexdigest()
        f = fichiers[k]; r = hashlib.sha256(open(f, 'rb').read()).hexdigest() if os.path.exists(f) else 'absent du dépôt'
        print(f'{"égal" if h == r else "DIFFÉRENT"} : {k} (service {h[:12]}… ; dépôt {r[:12]}…)')
    else:
        print(f'clé présente, non comparée : {k}')
PY

  echo "## politiques d'admission en service (noms ; pour les ImageValidatingPolicy : globs et namespaces)"
  local r
  for r in validatingpolicies.policies.kyverno.io clusterpolicies.kyverno.io policies.kyverno.io; do
    echo "$r : $(kubectl get "$r" -A -o json < /dev/null 2>/dev/null | jq -r '[.items[] | (.metadata.namespace // "-") + "/" + .metadata.name] | sort | join(" ")' || echo 'type absent')"
  done
  kubectl get imagevalidatingpolicies.policies.kyverno.io -o json < /dev/null 2>/dev/null \
    | jq -r '.items[] | "ImageValidatingPolicy \(.metadata.name) : globs \([.spec.matchImageReferences[]?.glob] | join(" ")) ; namespaces \(.spec.matchConstraints.namespaceSelector // "tous" | tostring)"' \
    || echo "ImageValidatingPolicy : type absent"

  echo "## Zot, lecture anonyme par l'adresse IP"
  echo '{}' > "$T/vide.json"
  zot_lire "image d'outillage de M3" "$OUTILLAGE" présent
  zot_lire "image de bootstrap (pull_digest du verrou)" "$BOOTSTRAP" présent
  zot_lire "fermeture applicative de S4b (06)" "$SOURCES" présent
  zot_lire "artefact de packaging rpm, avant M4a" "$DEPOT:m4a" absent
}

etape_politiques() {
  local a=$here/politique/admission.yaml c=$repo/poc/bricks/08c-durcissement/politiques/kyverno/durcissement.yaml n
  # rendu de la 08c comme par h5_deny (regles_deny, durcissement.sh) : même sed, sur le même fichier
  sed 's/^  validationActions: \[Audit\]$/  validationActions: [Deny]/' "$c" > "$T/durcissement-deny.yaml"
  echo "## ValidatingPolicy de la 08 (admission.yaml), énumérées par yq"
  for n in $(yq -N -r 'select(.kind == "ValidatingPolicy") | .metadata.name' "$a"); do
    comparer "ValidatingPolicy $n (08)" "$a" ".kind == \"ValidatingPolicy\" and .metadata.name == \"$n\""
  done
  echo "## ValidatingPolicy de la 08c (durcissement.yaml rendu comme par h5_deny), énumérées par yq"
  for n in $(yq -N -r 'select(.kind == "ValidatingPolicy") | .metadata.name' "$T/durcissement-deny.yaml"); do
    comparer "ValidatingPolicy $n (08c, rendu Deny)" "$T/durcissement-deny.yaml" ".kind == \"ValidatingPolicy\" and .metadata.name == \"$n\""
  done
  echo "## noms en service contre noms du dépôt"
  { yq -N -r 'select(.kind == "ValidatingPolicy") | .metadata.name' "$a"; yq -N -r 'select(.kind == "ValidatingPolicy") | .metadata.name' "$c"; } \
    | sort > "$T/noms-depot"
  kubectl get validatingpolicies.policies.kyverno.io -o json < /dev/null | jq -r '.items[].metadata.name' | sort > "$T/noms-service"
  echo "dépôt : $(wc -l < "$T/noms-depot") ; en service : $(wc -l < "$T/noms-service") ; en service hors du dépôt : $(comm -13 "$T/noms-depot" "$T/noms-service" | paste -sd' ') ; dans le dépôt, absentes en service : $(comm -23 "$T/noms-depot" "$T/noms-service" | paste -sd' ')"
}

etape_verrou() {
  attendu "V1 verrou de verrou_derivee (sha256)" "$(sha256sum < "$VERROU_SRC" | cut -d' ' -f1)" "$VERROU_SHA"
  python3 -I - "$VERROU_SRC" "$PULL_DIGEST" "$IMAGE_DIGEST" <<'PY'
import json, sys
v, pull, image = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
rpms = v['buildroot']['rpms']
noms = {(r['name'], r['arch']) for r in rpms}
hors = [r['url'] for r in rpms if not r['url'].startswith('https://dl.rockylinux.org/vault/rocky/9.7/') or '..' in r['url']]
ok = (len(rpms) == 222 and len(noms) == 222 and not hors and v['bootstrap']['pull_digest'] == pull
      and v['bootstrap']['image_digest'] == image and v['config']['bootstrap_image_ready'] is True)
print(f'{"OK  " if ok else "KO  "} V2 verrou : version {v["version"]}, {len(rpms)} rpm ({len(noms)} nom.arch distincts), '
      f'{len(hors)} URL hors de vault 9.7, pull_digest {v["bootstrap"]["pull_digest"][:19]}…, '
      f'image_digest {v["bootstrap"]["image_digest"][:12]}…, bootstrap_image_ready {v["config"]["bootstrap_image_ready"]}')
sys.exit(0 if ok else 1)
PY
  if [ -e "$VERROU" ]; then
    attendu "V3 verrou du dépôt égal à celui de verrou_derivee" "$(cmp -s "$VERROU_SRC" "$VERROU" && echo égal || echo différent)" égal
  else
    cp "$VERROU_SRC" "$VERROU" && echo "verrou écrit : poc/packaging/verrou-rpm.json"
  fi
  attendu "V3 sha256 de poc/packaging/verrou-rpm.json" "$(sha256sum < "$VERROU" | cut -d' ' -f1)" "$VERROU_SHA"
  echo "artefact : $(fichiers | paste -sd' ')"
  fichiers | (cd "$PKG" && xargs sha256sum) | sed 's/^/     /'
  rm -rf "$T/layout-1" "$T/layout-2"
  local d1 d2
  d1=$(pousser "$T/layout-1:m4a" --oci-layout)
  d2=$(pousser "$T/layout-2:m4a" --oci-layout)
  attendu "V4 deux poussées locales, même digest" "$d1" "$d2"
  echo "$d1" > "$T/digest-local"
  echo "digest attendu dans Zot : $d1"
}

etape_publier() {
  [ -s "$T/digest-local" ] || { echo "KO   étape verrou à lancer d'abord (digest local absent)" >&2; exit 1; }
  attendu "P0 verrou du dépôt inchangé depuis l'étape verrou" "$(sha256sum < "$VERROU" | cut -d' ' -f1)" "$VERROU_SHA"
  local attendu_d d1 d2
  attendu_d=$(cat "$T/digest-local")
  mkdir -p "$T/auth/docker" && auth_zot "$T/auth/docker/config.json"   # compte poc-ecriture, comme packaging-deb (s4c.sh)
  d1=$(pousser "$REG_HOTE/$DEPOT:m4a" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json")
  d2=$(pousser "$REG_HOTE/$DEPOT:m4a" --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json")
  attendu "P1 deux poussées dans Zot, même digest" "$d1" "$d2"
  attendu "P1 digest Zot égal au digest local" "$d1" "$attendu_d"
  rm -rf "$T/tire" && mkdir "$T/tire"
  (cd "$T/tire" && oras pull --ca-file "$P/ca-poc.crt" --registry-config "$T/auth/docker/config.json" --no-tty \
    "$REG_HOTE/$DEPOT@$d1" > /dev/null)
  attendu "P2 fichiers tirés par digest égaux au dépôt" \
    "$(cd "$T/tire" && find . -type f -printf '%P\n' | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)" \
    "$(fichiers | sort | (cd "$PKG" && xargs sha256sum) | sha256sum | cut -d' ' -f1)"
  echo "PACKAGING_RPM=$REG/$DEPOT@$d1"
}

# Additif du 2026-11-23T15:08:33Z (reconstruction des entrées de M5b après l'incident du rejeu m5b-1) : M4A_JOURNAUX=<dossier> écrit
# le journal de lancer ailleurs que dans resultats/ (un journal archivé n'est jamais réécrit) ; les entrées lues restent dans resultats/.
R=${M4A_JOURNAUX:-$R}

lancer m4a "05 M4a" "$@"
