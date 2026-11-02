#!/usr/bin/env bash
# Brique 01, jalon S2 : Forgejo de la brique 08 (sc-stockage) préparé pour la synchronisation (protocole du 02/11/2026).
#   comptes        poc-sync (synchro), poc-dev (refs propres du fork), poc-amont (amont d'essai) : comptes ordinaires créés
#                  dans la VM, mot de passe aléatoire jeté ; jetons write:repository en 0600 sur l'hôte (…/08/secrets,
#                  donc cherchés par fuites.sh de la brique 08)
#   organisations  mirror (équipe synchro : poc-sync en écriture sur tous ses dépôts), amont-essai (équipe ecriture :
#                  poc-amont) ; workspace existe (brique 08, J2)
#   amont          amont-essai/sample-app : sources de poc/sample-app à HEAD, commit à auteur et date fixes, poussé par poc-amont
#   miroir         mirror/sample-app vide (administrateur), puis premier run de sync.py depuis l'hôte (--push par poc-sync)
#   archives       sonde : Forgejo accepte refs/archive/* (force-push d'une branche non sensible de l'amont, run, archive lue)
#   fork           workspace/sample-app-sync, fork de mirror/sample-app ; équipes de workspace limitées à ce dépôt :
#                  synchro (poc-sync) et dev-sample-app-sync (poc-dev) ; workspace/sample-app (brique 08) hors de leur portée
#   protections    sur le fork, une protection de branche par motif de refs-propres.json (liste blanche : poc-dev,
#                  apply_to_admins) et une protection de tag par motif (liste blanche : poc-dev)
#   refus          pushes refusés (mirror/ par poc-dev et poc-amont, refs propres du fork par poc-sync, workspace/sample-app
#                  par poc-sync) ; acceptés (refs propres du fork par poc-dev) ; administrateur : mesuré, pas supposé
#   bout_en_bout   collision amont sur custom/essai et avance de main : sync.py avec --push et --fork, code 2, ref propre du
#                  fork intacte, main du fork avancée, collision publiée dans mirror/
#   negatifs       S4, après executeur.sh installer : force-push de main, tag créé puis déplacé puis supprimé, branche
#                  supprimée, dans l'amont ; chaque fois un run du service de la VM : code, archive publiée dans mirror/,
#                  fork sans perte ; refs propres intactes ; restauration identique dans la VM
#   traefik        S6 : mirror/traefik depuis GitHub par le service de la VM, premier run sans fork, fork workspace/traefik,
#                  second run ; durées, bundles, espace disque ; timer horaire activé
# Aucun secret en argument de commande : jetons dans des fichiers 0600 ; en-tête Authorization passé à git par
# GIT_CONFIG_* et limité au préfixe d'URL de la cible (http.<url>.extraHeader) : il n'est jamais envoyé à l'amont.
#
# Usage (racine du dépôt) : poc/bricks/01-forgejo-sync/forgejo.sh <étape>…   (journal : resultats/forgejo-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
FORGEJO_HOTE=https://192.168.161.13:3000   # depuis l'hôte (SAN IP du certificat)
FG="runuser -u forgejo -- env HOME=/var/lib/forgejo USER=forgejo /usr/local/bin/forgejo -c /etc/forgejo/app.ini -w /var/lib/forgejo"
PROJET=sample-app-sync
AMONT="amont-essai/sample-app"
MIROIR=mirror/sample-app
FORK=workspace/$PROJET
CONF=$here/refs-propres.json
D1=${SYNCHRO_DIR:-$HOME/.cache/supply-chain-poc/01}   # miroir local, rapports et bundles de sync.py (hors du dépôt)
T=$W/synchro
mkdir -p "$T" && chmod 0700 "$T"
trap 'rm -rf "$T" "$W/refus.out"' EXIT   # copies de jetons, même en cas d'échec

entete() { # compte : fichier d'en-tête Authorization (0600) dans $T
  (umask 077 && printf 'Authorization: token %s\n' "$(cat "$S/forgejo-$1.token")" > "$T/entete-$1")
}
api() { # compte méthode chemin [corps-json] : appel de l'API ; sortie : corps de la réponse
  local fh=$T/entete-$1 m=$2 c=$3
  [ "$1" = poc-admin ] && fh=$T/entete-admin
  if [ $# -gt 3 ]; then
    curl -fsS --cacert "$P/ca-poc.crt" -H @"$fh" -H 'Content-Type: application/json' -X "$m" "$FORGEJO_HOTE/api/v1$c" -d "$4"
  else
    curl -fsS --cacert "$P/ca-poc.crt" -H @"$fh" -X "$m" "$FORGEJO_HOTE/api/v1$c"
  fi
}
existe() { curl -fs -o /dev/null --cacert "$P/ca-poc.crt" -H @"$T/entete-admin" "$FORGEJO_HOTE/api/v1$1"; }
gitc() { # compte préfixe-d'url commande-git… : git isolé de la configuration de l'utilisateur, jeton du compte limité au préfixe
  local c=$1 u=$2; shift 2
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    GIT_CONFIG_KEY_1="http.$u.extraHeader" GIT_CONFIG_VALUE_1="$(cat "$T/entete-$c")" git "$@"
}
pousser() { # compte dépôt refspec… : push depuis $T/w ; sortie et code dans $T/push.out, code renvoyé
  local c=$1 d=$2 r=0; shift 2
  # Préfixe d'URL de l'en-tête = URL exacte du dépôt, .git compris (git compare les chemins composant par composant).
  gitc "$c" "$FORGEJO_HOTE/$d.git" -C "$T/w" push "$FORGEJO_HOTE/$d.git" "$@" > "$T/push.out" 2>&1 || r=$?
  return $r
}
# Motifs de refus : un push qui échoue pour une autre raison (TLS, jeton, URL) est un KO, pas un refus.
# Forgejo 15.0.11 refuse un compte sans droit d'écriture par son hook pre-receive (mesuré le 02/11/2026, refus de poc-dev
# vers mirror/ : « User 'poc-dev' is not allowed to push to branch … »), pas par un 403.
DROITS="403|permission denied|User '[a-z-]+' is not allowed to push to branch"
# Réécriture forcée d'une branche protégée (mesuré le 02/11/2026) : « branch custom/essai is protected from force push ».
BRANCHE_PROTEGEE='protected branch|branch [^ ]+ is protected'
TAG_PROTEGE='protected tag|tag [^ ]+ is protected'
refuse() { # libellé motif compte dépôt refspec… : push attendu refusé, avec le motif dans la sortie
  local l=$1 m=$2; shift 2
  if pousser "$@"; then echo "KO   $l : accepté" >&2; cat "$T/push.out" >&2; exit 1; fi
  if grep -iE "$m" "$T/push.out" >/dev/null; then
    echo "OK   $l : refusé ($(grep -oiE "$m" "$T/push.out" | head -1))"
  else
    echo "KO   $l : refusé pour une autre raison" >&2; cat "$T/push.out" >&2; exit 1
  fi
}
accepte() { # libellé compte dépôt refspec… : push attendu accepté
  local l=$1; shift
  if pousser "$@"; then echo "OK   $l : accepté"; else echo "KO   $l : refusé" >&2; cat "$T/push.out" >&2; exit 1; fi
}
mesure() { # libellé compte dépôt refspec… : push dont l'issue est relevée, sans attendu (administrateur)
  local l=$1; shift
  if pousser "$@"; then echo "MESURE $l : accepté"; else echo "MESURE $l : refusé ($(grep -E '^remote: |error:' "$T/push.out" | head -2 | paste -sd' '))"; fi
}
distant() { # dépôt ref : valeur de la ref dans Forgejo (lecture anonyme, nom exact, tag annoté non déréférencé), vide si absente
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    git ls-remote --refs "$FORGEJO_HOTE/$1.git" "$2" | awk -v r="$2" '$2 == r {print $1}'
}
journal() { # depuis : requêtes git de Forgejo depuis cette date (VM), sans adresse ni durée
  sur sc-stockage "sudo journalctl -u forgejo --since '$1' -o cat" \
    | grep -E 'completed (POST|GET) /[^ ]+\.git/(info/refs\?service=git-receive-pack|git-receive-pack)' \
    | sed 's/ for 192.168.161.1:[0-9]*,/,/; s/ in [0-9.]*ms @.*//' || true
}
synchro() { # options de sync.py… : un run depuis l'hôte, jeton de poc-sync limité à mirror/ et au fork ; code renvoyé
  local r=0 v
  # Après executeur.sh installer, la VM est seule propriétaire de l'état : un miroir neuf sur l'hôte pousserait
  # refs/archive/* avec --prune et retirerait de mirror/ les archives créées par la VM.
  for v in "$D1/miroirs/$PROJET.git".passe-a-la-vm-*; do
    [ ! -e "$v" ] || { echo "KO   état passé à la VM (${v##*/}) : synchro depuis l'hôte refusée" >&2; exit 1; }
  done
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    GIT_CONFIG_KEY_1="http.$FORGEJO_HOTE/$MIROIR.git.extraHeader" GIT_CONFIG_VALUE_1="$(cat "$T/entete-poc-sync")" \
    GIT_CONFIG_KEY_2="http.$FORGEJO_HOTE/$FORK.git.extraHeader" GIT_CONFIG_VALUE_2="$(cat "$T/entete-poc-sync")" \
    python3 -I "$here/sync.py" --mirror "$D1/miroirs/$PROJET.git" --upstream "$FORGEJO_HOTE/$AMONT.git" \
      --report-dir "$D1/rapports/$PROJET" --bundle-dir "$D1/bundles/$PROJET" \
      --refs-propres "$CONF" --projet "$PROJET" --push "$FORGEJO_HOTE/$MIROIR.git" "$@" || r=$?
  return $r
}
clone_travail() { # dépôt : clone de travail neuf dans $T/w (lecture anonyme), identité d'essai
  rm -rf "$T/w"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.sslCAInfo GIT_CONFIG_VALUE_0="$P/ca-poc.crt" \
    git clone -q "$FORGEJO_HOTE/$1.git" "$T/w"
  git -C "$T/w" config user.name "PoC brique 01" && git -C "$T/w" config user.email poc-dev@poc.test
  git -C "$T/w" config commit.gpgsign false && git -C "$T/w" config tag.gpgsign false
}

(umask 077 && printf 'Authorization: token %s\n' "$(cat "$S/forgejo-admin.token")" > "$T/entete-admin")
for c in poc-sync poc-dev poc-amont; do [ ! -s "$S/forgejo-$c.token" ] || entete "$c"; done

etape_comptes() {
  local c liste
  liste=$(sur sc-stockage "sudo $FG admin user list 2>/dev/null" | awk 'NR > 1 {print $2}')
  for c in poc-sync poc-dev poc-amont; do
    if grep -qx "$c" <<<"$liste"; then echo "compte $c existant"; else
      rm -f "$S/forgejo-$c.token"
      # Mot de passe aléatoire jeté (les comptes n'agissent que par jeton) : la ligne qui le porte est filtrée dans la VM.
      sur sc-stockage "sudo $FG admin user create --username $c --email $c@poc.test --random-password --random-password-length 32 --must-change-password=false 2>/dev/null | grep -v 'generated random password'" || true
      echo "compte $c créé (ordinaire, mot de passe aléatoire non conservé)"
    fi
    if [ ! -s "$S/forgejo-$c.token" ]; then
      (umask 077 && sur sc-stockage "sudo $FG admin user generate-access-token --username $c --token-name s2-$(date -u +%Y%m%dT%H%M%SZ) --scopes write:repository --raw 2>/dev/null" > "$S/forgejo-$c.token")
      [ -s "$S/forgejo-$c.token" ] || { echo "KO   jeton de $c non relevé" >&2; exit 1; }
      echo "jeton de $c (write:repository) en 0600 sur l'hôte"
    fi
    entete "$c"
  done
  sur sc-stockage "sudo $FG admin user list 2>/dev/null" | awk 'NR == 1 || $2 ~ /^poc-/ {print $2, $3, $5, $6}'
  for c in poc-sync poc-dev poc-amont; do
    [ "$(sur sc-stockage "sudo $FG admin user list --admin 2>/dev/null" | awk -v c="$c" 'NR > 1 && $2 == c' | wc -l)" = 0 ] \
      && echo "OK   $c n'est pas administrateur" || { echo "KO   $c administrateur" >&2; exit 1; }
  done
}

equipe() { # org nom permission tous-les-dépôts(true|false) membre : équipe créée si absente, membre ajouté ; id
  local id
  id=$(api poc-admin GET "/orgs/$1/teams" | jq -r --arg n "$2" '.[] | select(.name == $n) | .id')
  [ -n "$id" ] || id=$(api poc-admin POST "/orgs/$1/teams" "$(jq -nc --arg n "$2" --arg p "$3" --argjson a "$4" \
    '{name: $n, permission: $p, includes_all_repositories: $a, units: ["repo.code"]}')" | jq -r .id)
  api poc-admin PUT "/teams/$id/members/$5" >/dev/null
  echo "$id"
}

etape_organisations() {
  local o id
  for o in mirror amont-essai; do
    existe "/orgs/$o" || api poc-admin POST /orgs "$(jq -nc --arg o "$o" '{username: $o, visibility: "public"}')" >/dev/null
  done
  id=$(equipe mirror synchro write true poc-sync)
  echo "équipe mirror/synchro ($id) : $(api poc-admin GET "/teams/$id" | jq -c '{permission, includes_all_repositories, units}') ; membres : $(api poc-admin GET "/teams/$id/members" | jq -r '[.[].login] | join(",")')"
  id=$(equipe amont-essai ecriture write true poc-amont)
  echo "équipe amont-essai/ecriture ($id) : membres : $(api poc-admin GET "/teams/$id/members" | jq -r '[.[].login] | join(",")')"
}

etape_amont() {
  local commit
  existe "/repos/$AMONT" || api poc-admin POST /orgs/amont-essai/repos '{"name": "sample-app", "default_branch": "main", "private": false}' >/dev/null
  rm -rf "$T/w" && mkdir -p "$T/w"
  git -C "$repo" archive HEAD poc/sample-app | tar -x -C "$T/w" --strip-components=2
  (export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
   export GIT_AUTHOR_NAME="Amont d'essai" GIT_AUTHOR_EMAIL=poc-amont@poc.test GIT_AUTHOR_DATE=2026-11-02T00:00:00Z
   export GIT_COMMITTER_NAME="Amont d'essai" GIT_COMMITTER_EMAIL=poc-amont@poc.test GIT_COMMITTER_DATE=2026-11-02T00:00:00Z
   cd "$T/w" && git init -q -b main && git add -A && git commit -qm "sample-app (brique 01, amont d'essai)")
  commit=$(git -C "$T/w" rev-parse HEAD)
  # Amont recréé à l'identique à chaque passage : force-push volontaire (c'est l'amont simulé).
  accepte "push de l'amont d'essai par poc-amont" poc-amont "$AMONT" --force main
  [ "$(distant "$AMONT" refs/heads/main)" = "$commit" ] && echo "OK   $AMONT : main = $commit" || { echo "KO   main de $AMONT" >&2; exit 1; }
}

etape_miroir() {
  local debut code
  existe "/repos/$MIROIR" || api poc-admin POST /orgs/mirror/repos '{"name": "sample-app", "default_branch": "main", "private": false}' >/dev/null
  debut=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'")
  code=0; synchro || code=$?
  echo "sync.py : code $code ; rapport $(ls -1 "$D1/rapports/$PROJET" | tail -1)"
  [ "$code" = 0 ] || [ "$code" = 2 ] || { echo "KO   premier run de sync.py en erreur" >&2; exit 1; }
  [ "$(distant "$MIROIR" refs/heads/main)" = "$(distant "$AMONT" refs/heads/main)" ] \
    && echo "OK   $MIROIR : main = main de $AMONT" || { echo "KO   main de $MIROIR" >&2; exit 1; }
  echo "## journal de Forgejo (pushes de ce run : poc-sync vers mirror/ seulement)"
  journal "$debut"
}

etape_archives() { # S2 : Forgejo accepte-t-il refs/archive/* ? force-push d'une branche non sensible de l'amont, puis un run
  local avant code
  clone_travail "$AMONT"
  git -C "$T/w" commit -q --allow-empty -m "amont : essai/archive (S2)"
  accepte "branche essai/archive par poc-amont" poc-amont "$AMONT" HEAD:refs/heads/essai/archive
  code=0; synchro || code=$?
  avant=$(distant "$AMONT" refs/heads/essai/archive)
  git -C "$T/w" commit -q --amend --allow-empty -m "amont : essai/archive réécrite (S2)"
  accepte "force-push de essai/archive par poc-amont" poc-amont "$AMONT" +HEAD:refs/heads/essai/archive
  code=0; synchro || code=$?
  local a
  a=$(jq -r '.events[] | select(.ref == "heads/essai/archive") | "\(.type) \(.archive)"' "$(ls -1 "$D1/rapports/$PROJET"/*.json | tail -1)")
  echo "sync.py : code $code ; événement : $a"
  [ "$code" = 0 ] && [ "${a%% *}" = force-push-unprotected ] && echo "OK   force-push non sensible : code 0, archivé" || { echo "KO   événement ou code inattendu" >&2; exit 1; }
  [ "$(distant "$MIROIR" "${a#* }")" = "$avant" ] && echo "OK   archive ${a#* } publiée dans $MIROIR (Forgejo accepte refs/archive/*)" \
    || { echo "KO   archive absente de $MIROIR" >&2; exit 1; }
}

etape_fork() {
  local id
  existe "/repos/$FORK" || api poc-admin POST "/repos/$MIROIR/forks" "$(jq -nc --arg n "$PROJET" '{organization: "workspace", name: $n}')" >/dev/null
  for _ in $(seq 30); do [ -n "$(distant "$FORK" refs/heads/main)" ] && break; sleep 1; done
  api poc-admin GET "/repos/$FORK" | jq -c '{full_name, fork, parent: .parent.full_name, default_branch}'
  for e in "synchro poc-sync" "dev-$PROJET poc-dev"; do
    set -- $e
    id=$(equipe workspace "$1" write false "$2")
    api poc-admin PUT "/teams/$id/repos/workspace/$PROJET" >/dev/null
    echo "équipe workspace/$1 ($id) : dépôts $(api poc-admin GET "/teams/$id/repos" | jq -r '[.[].full_name] | join(",")') ; membres $(api poc-admin GET "/teams/$id/members" | jq -r '[.[].login] | join(",")')"
  done
  [ "$(distant "$FORK" refs/heads/main)" = "$(distant "$MIROIR" refs/heads/main)" ] \
    && echo "OK   $FORK : main = main de $MIROIR" || { echo "KO   main de $FORK" >&2; exit 1; }
}

etape_protections() {
  local p
  for p in $(jq -r --arg p "$PROJET" '(.global.branches + (.depots[$p].branches // [])) | unique[]' "$CONF"); do
    api poc-admin GET "/repos/$FORK/branch_protections" | jq -e --arg p "$p" 'any(.[]; .rule_name == $p)' >/dev/null \
      || api poc-admin POST "/repos/$FORK/branch_protections" "$(jq -nc --arg p "$p" '{rule_name: $p, enable_push: true,
           enable_push_whitelist: true, push_whitelist_usernames: ["poc-dev"], apply_to_admins: true}')" >/dev/null
  done
  for p in $(jq -r --arg p "$PROJET" '(.global.tags + (.depots[$p].tags // [])) | unique[]' "$CONF"); do
    api poc-admin GET "/repos/$FORK/tag_protections" | jq -e --arg p "$p" 'any(.[]; .name_pattern == $p)' >/dev/null \
      || api poc-admin POST "/repos/$FORK/tag_protections" "$(jq -nc --arg p "$p" '{name_pattern: $p, whitelist_usernames: ["poc-dev"]}')" >/dev/null
  done
  api poc-admin GET "/repos/$FORK/branch_protections" \
    | jq -c '.[] | {rule_name, enable_push, enable_push_whitelist, push_whitelist_usernames, apply_to_admins}'
  api poc-admin GET "/repos/$FORK/tag_protections" | jq -c '.[] | {name_pattern, whitelist_usernames}'
}

etape_refus() {
  local debut
  debut=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'")
  clone_travail "$FORK"
  git -C "$T/w" commit -q --allow-empty -m "essai S2"
  refuse "push vers $MIROIR par poc-dev (hors de l'équipe synchro)" "$DROITS" poc-dev "$MIROIR" HEAD:refs/heads/essai-s2
  refuse "push vers $MIROIR par poc-amont" "$DROITS" poc-amont "$MIROIR" HEAD:refs/heads/essai-s2
  refuse "push vers workspace/sample-app (brique 08) par poc-sync" "$DROITS" poc-sync workspace/sample-app HEAD:refs/heads/essai-s2
  refuse "création de la branche propre custom/essai du fork par poc-sync" "$BRANCHE_PROTEGEE" poc-sync "$FORK" HEAD:refs/heads/custom/essai
  refuse "création de la branche propre paquet/deb du fork par poc-sync (motif du projet)" "$BRANCHE_PROTEGEE" poc-sync "$FORK" HEAD:refs/heads/paquet/deb
  refuse "création du tag propre custom-1 du fork par poc-sync" "$TAG_PROTEGE" poc-sync "$FORK" HEAD:refs/tags/custom-1
  # Le * de sync.py (fnmatch) traverse les / ; celui des règles de protection de Forgejo peut-être pas : mesuré.
  mesure "création de custom/a/b (deux niveaux) du fork par poc-sync" poc-sync "$FORK" HEAD:refs/heads/custom/a/b
  accepte "branche custom/essai du fork par poc-dev" poc-dev "$FORK" HEAD:refs/heads/custom/essai
  accepte "branche paquet/deb du fork par poc-dev" poc-dev "$FORK" HEAD:refs/heads/paquet/deb
  accepte "tag custom-1 du fork par poc-dev" poc-dev "$FORK" HEAD:refs/tags/custom-1
  accepte "branche ordinaire du fork par poc-sync (hors motif)" poc-sync "$FORK" HEAD:refs/heads/essai-s2
  refuse "réécriture de la branche propre custom/essai par poc-sync (force)" "$BRANCHE_PROTEGEE" poc-sync "$FORK" +HEAD~1:refs/heads/custom/essai
  refuse "suppression du tag propre custom-1 par poc-sync" "$TAG_PROTEGE" poc-sync "$FORK" :refs/tags/custom-1
  mesure "réécriture de custom/essai par poc-dev (force, liste blanche)" poc-dev "$FORK" +HEAD~1:refs/heads/custom/essai
  pousser poc-dev "$FORK" +HEAD:refs/heads/custom/essai >/dev/null || true   # remise à l'essai S2 si la réécriture est passée
  entete_admin_comme_compte
  mesure "réécriture de custom/essai par poc-admin (force, apply_to_admins)" poc-admin "$FORK" +HEAD~1:refs/heads/custom/essai
  mesure "tag propre custom-2 du fork par poc-admin" poc-admin "$FORK" HEAD:refs/tags/custom-2
  mesure "push vers $MIROIR par poc-admin" poc-admin "$MIROIR" HEAD:refs/heads/essai-s2-admin
  echo "## état du fork : $(distant "$FORK" refs/heads/custom/essai | cut -c1-12) custom/essai, $(distant "$FORK" refs/tags/custom-1 | cut -c1-12) custom-1"
  echo "## journal de Forgejo (requêtes de push de cet essai)"
  journal "$debut"
}
entete_admin_comme_compte() { cp "$T/entete-admin" "$T/entete-poc-admin"; }

etape_bout_en_bout() {
  local dev amont code debut
  debut=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'")
  dev=$(distant "$FORK" refs/heads/custom/essai)
  [ -n "$dev" ] || { echo "KO   custom/essai absente du fork (étape refus d'abord)" >&2; exit 1; }
  clone_travail "$AMONT"
  git -C "$T/w" commit -q --allow-empty -m "amont : avance de main (S2)"
  amont=$(git -C "$T/w" rev-parse HEAD)
  accepte "avance de main et branche custom/essai (collision) dans l'amont par poc-amont" poc-amont "$AMONT" main HEAD:refs/heads/custom/essai
  code=0; synchro --fork "$FORGEJO_HOTE/$FORK.git" || code=$?
  echo "sync.py : code $code"
  jq -c '{status, events: [.events[] | {type, ref}]}' "$(ls -1 "$D1/rapports/$PROJET"/*.json | tail -1)"
  [ "$code" = 2 ] && echo "OK   collision : code 2" || { echo "KO   code $code (2 attendu)" >&2; exit 1; }
  [ "$(distant "$MIROIR" refs/heads/custom/essai)" = "$amont" ] && echo "OK   collision publiée dans $MIROIR" || { echo "KO   custom/essai de $MIROIR" >&2; exit 1; }
  [ "$(distant "$FORK" refs/heads/custom/essai)" = "$dev" ] && echo "OK   custom/essai du fork intacte (poc-dev)" || { echo "KO   custom/essai du fork écrasée" >&2; exit 1; }
  [ "$(distant "$FORK" refs/heads/main)" = "$amont" ] && echo "OK   main du fork avancée" || { echo "KO   main du fork" >&2; exit 1; }
  [ -n "$(distant "$FORK" refs/tags/custom-1)" ] && echo "OK   tag custom-1 du fork intact" || { echo "KO   tag custom-1 du fork" >&2; exit 1; }
  echo "## journal de Forgejo (pushes de ce run)"
  journal "$debut"
}

# S4 : réécritures de l'amont d'essai, synchronisées par le service de la VM (S3, executeur.sh installer).
U=synchro@$PROJET
run_vm() { # attendu-code : un run du service, code de sync.py relevé (ExecMainStatus) ; dernier rapport dans $T/rapport.json
  local c f
  # systemd refuse plus de 5 démarrages en 10 s (StartLimitBurst par défaut, mesuré le 02/11/2026 au 6e run de S4) :
  # limite gardée pour le service, runs du test espacés.
  sleep 3
  sur sc-stockage "sudo systemctl start $U.service" || { echo "KO   échec de l'unité $U" >&2; exit 1; }
  c=$(sur sc-stockage "systemctl show -p ExecMainStatus --value $U.service")
  f=$(sur sc-stockage "sudo sh -c 'ls -1 /var/lib/synchro/$PROJET/rapports/*.json | tail -1'")
  sur sc-stockage "sudo cat $f" > "$T/rapport.json"
  echo "run ${f##*/} : code $c, $(jq -c '[.events[] | {type, ref, archive}]' "$T/rapport.json")"
  [ "$c" = "$1" ] && echo "OK   code $c" || { echo "KO   code $c ($1 attendu)" >&2; exit 1; }
}
archive_publiee() { # ref (heads/x ou tags/x) ancienne-valeur : l'archive du dernier rapport est dans mirror/ avec cette valeur
  local a
  a=$(jq -r --arg r "$1" '.events[] | select(.ref == $r and .archive != null) | .archive' "$T/rapport.json")
  [ -n "$a" ] && [ "$(distant "$MIROIR" "$a")" = "$2" ] && echo "OK   $1 archivée dans $MIROIR ($a)" || { echo "KO   archive de $1 absente de $MIROIR" >&2; exit 1; }
}

etape_negatifs() {
  local avant v1 v1b dev
  dev=$(distant "$FORK" refs/heads/custom/essai)
  clone_travail "$AMONT"
  echo "## 1. force-push de main (branche sensible)"
  avant=$(git -C "$T/w" rev-parse HEAD)
  git -C "$T/w" reset -q --hard HEAD~1 && git -C "$T/w" commit -q --allow-empty -m "amont : main réécrite (S4)"
  accepte "force-push de main par poc-amont" poc-amont "$AMONT" +main
  run_vm 2
  [ "$(jq -r '.events[] | select(.ref == "heads/main") | .type' "$T/rapport.json")" = force-push ] && echo "OK   force-push détecté" || { echo "KO   événement de main" >&2; exit 1; }
  archive_publiee heads/main "$avant"
  [ "$(distant "$FORK" refs/heads/main)" = "$(git -C "$T/w" rev-parse HEAD)" ] && echo "OK   main du fork suit l'amont (ancienne valeur archivée)" || { echo "KO   main du fork" >&2; exit 1; }
  echo "## 2. tag v1.0.0 créé, puis déplacé, puis supprimé"
  git -C "$T/w" tag -a v1.0.0 -m "v1.0.0 (S4)"
  accepte "tag v1.0.0 par poc-amont" poc-amont "$AMONT" refs/tags/v1.0.0
  run_vm 0
  v1=$(distant "$MIROIR" refs/tags/v1.0.0)
  git -C "$T/w" commit -q --allow-empty -m "amont : après v1.0.0" && git -C "$T/w" tag -f -a v1.0.0 -m "v1.0.0 déplacé (S4)" >/dev/null
  accepte "tag v1.0.0 déplacé par poc-amont" poc-amont "$AMONT" main +refs/tags/v1.0.0
  run_vm 2
  archive_publiee tags/v1.0.0 "$v1"
  v1b=$(distant "$MIROIR" refs/tags/v1.0.0)
  accepte "tag v1.0.0 supprimé par poc-amont" poc-amont "$AMONT" :refs/tags/v1.0.0
  run_vm 2
  archive_publiee tags/v1.0.0 "$v1b"
  [ -z "$(distant "$MIROIR" refs/tags/v1.0.0)" ] && echo "OK   tag supprimé de la vue amont de $MIROIR (archivé)" || { echo "KO   tag encore dans $MIROIR" >&2; exit 1; }
  [ "$(distant "$FORK" refs/tags/v1.0.0)" = "$v1b" ] && echo "OK   tag gardé dans le fork (pas de --prune)" || echo "MESURE tag du fork : $(distant "$FORK" refs/tags/v1.0.0)"
  echo "## 3. branche feature/x créée puis supprimée"
  accepte "branche feature/x par poc-amont" poc-amont "$AMONT" HEAD:refs/heads/feature/x
  run_vm 0
  avant=$(distant "$MIROIR" refs/heads/feature/x)
  accepte "branche feature/x supprimée par poc-amont" poc-amont "$AMONT" :refs/heads/feature/x
  run_vm 0
  archive_publiee heads/feature/x "$avant"
  [ "$(distant "$FORK" refs/heads/feature/x)" = "$avant" ] && echo "OK   feature/x gardée dans le fork" || { echo "KO   feature/x du fork" >&2; exit 1; }
  echo "## 4. refs propres du fork après toutes les réécritures"
  [ "$(distant "$FORK" refs/heads/custom/essai)" = "$dev" ] && [ -n "$(distant "$FORK" refs/heads/paquet/deb)" ] && [ -n "$(distant "$FORK" refs/tags/custom-1)" ] \
    && echo "OK   custom/essai, paquet/deb et custom-1 intactes" || { echo "KO   ref propre du fork modifiée" >&2; exit 1; }
  echo "## 5. restauration dans la VM depuis les bundles et les rapports"
  sur sc-stockage "sudo -u synchro bash -s" <<EOF
set -euo pipefail
d=/var/lib/synchro/$PROJET
t=\$(mktemp -d)
python3 -I /usr/local/lib/synchro/sync.py --mirror \$d/miroir.git --report-dir \$d/rapports --bundle-dir \$d/bundles --restore \$t/restaure.git
a=\$(git -C \$d/miroir.git for-each-ref --format='%(refname) %(objectname)' refs/upstream refs/archive | sha256sum)
b=\$(git -C \$t/restaure.git for-each-ref --format='%(refname) %(objectname)' refs/upstream refs/archive | sha256sum)
echo "refs upstream et archive : \$(git -C \$d/miroir.git for-each-ref refs/upstream refs/archive | wc -l) ; bundles : \$(ls \$d/bundles | wc -l)"
rm -rf \$t
[ "\$a" = "\$b" ] && echo "OK   miroir restauré identique (refs upstream et archive)" || { echo "KO   restauration différente" >&2; exit 1; }
EOF
}

# S6 : Traefik depuis GitHub, par le service de la VM (S3) ; durées, bundles et espace disque.
run_traefik() { # libellé : un run de synchro@traefik ; durée (horodatages de systemd), code, événements, bundle
  local u=synchro@traefik.service d0 d1 c f
  sur sc-stockage "sudo systemctl start $u" || { echo "KO   échec de l'unité $u" >&2; sur sc-stockage "sudo journalctl -u $u -n 20 -o cat" >&2; exit 1; }
  d0=$(sur sc-stockage "systemctl show -p ExecMainStartTimestampMonotonic --value $u")
  d1=$(sur sc-stockage "systemctl show -p ExecMainExitTimestampMonotonic --value $u")
  c=$(sur sc-stockage "systemctl show -p ExecMainStatus --value $u")
  f=$(sur sc-stockage "sudo sh -c 'ls -1 /var/lib/synchro/traefik/rapports/*.json | tail -1'")
  sur sc-stockage "sudo cat $f" > "$T/rapport.json"
  echo "$1 : code $c, $(( (d1 - d0) / 1000000 )) s ; $(jq -c '{status, evenements: (.events | group_by(.type) | map({(.[0].type): length}) | add),
    bundle: (if .bundle then {fichier: .bundle.file, refs: (.bundle.refs | length), prerequis: (.bundle.prerequisites | length)} else null end)}' "$T/rapport.json")"
  [ -z "$(jq -r '.bundle.file // empty' "$T/rapport.json")" ] \
    || echo "  taille du bundle : $(sur sc-stockage "sudo stat -c %s /var/lib/synchro/traefik/bundles/$(jq -r .bundle.file "$T/rapport.json")") octets"
}
espace() {
  sur sc-stockage "df -B1 / | tail -1; sudo du -sb /var/lib/synchro/traefik/miroir.git /var/lib/synchro/traefik/bundles /var/lib/forgejo/data/repos/mirror /var/lib/forgejo/data/repos/workspace 2>/dev/null || true"   # chemins absents avant le premier run
}

etape_traefik() {
  local id
  echo "## espace avant"; espace
  existe /repos/mirror/traefik || api poc-admin POST /orgs/mirror/repos '{"name": "traefik", "default_branch": "master", "private": false}' >/dev/null
  copier sc-stockage /tmp/traefik-env "$here/systemd/traefik.env"
  sur sc-stockage "sudo install -m 0644 /tmp/traefik-env/traefik.env /etc/synchro/traefik.env && rm -rf /tmp/traefik-env"
  run_traefik "premier run (sans fork)"
  [ "$(distant mirror/traefik refs/heads/master)" = "$(git ls-remote https://github.com/traefik/traefik.git refs/heads/master | cut -f1)" ] \
    && echo "OK   master de mirror/traefik = master de GitHub" || echo "MESURE master de GitHub a pu avancer pendant le run"
  existe /repos/workspace/traefik || api poc-admin POST /repos/mirror/traefik/forks '{"organization": "workspace", "name": "traefik"}' >/dev/null
  for _ in $(seq 60); do [ -n "$(distant workspace/traefik refs/heads/master)" ] && break; sleep 2; done
  sur sc-stockage "sudo sed -i 's#^FORK=\$#FORK=https://192.168.161.13:3000/workspace/traefik.git#' /etc/synchro/traefik.env && grep ^FORK= /etc/synchro/traefik.env"
  id=$(equipe workspace synchro write false poc-sync)
  api poc-admin PUT "/teams/$id/repos/workspace/traefik" >/dev/null
  run_traefik "second run (avec fork, incrément depuis le premier)"
  echo "## espace après"; espace
  sur sc-stockage "sudo systemctl enable --now synchro@traefik.timer && systemctl list-timers synchro@traefik.timer --no-pager | head -2"
}

lancer forgejo S2-S6 "$@"
