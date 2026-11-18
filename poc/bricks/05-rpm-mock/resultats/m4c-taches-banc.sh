#!/usr/bin/env bash
# Brique 05, M4c : banc hors cluster et hors Zot de l'étape taches de m4c.sh (préparée à sec le 18/11/2026, accord permanent du
# 18/11), écrit avant tout passage, sur le modèle de m4b-taches-signer-banc.sh.
# A : insertions seules contre le m4c.sh d'avant (deux blocs : en-tête, bloc avant lancer) ; bash -n ; shellcheck : seul écart,
#     le nombre de SC2016 (expressions yq et valeurs attendues entre apostrophes). Scripts archivés des essais : sha256 = constantes.
# B : la vraie fonction etape_taches de la copie, jouée dans la forme de lancer ({ …; } 2>&1 | sed | tee), le vrai commun.sh chargé
#     (CONFIANCE_DIR du banc), avec le vrai tkn (mise) et une clé P-256 jetable du banc (jamais taches.key), les vrais gabarits
#     (copiés par cas, car SIGNER écrit les signatures versionnées à côté) et la vraie liste revue de la 08 ; faux : kubectl
#     (dry-run seul, témoin refusé avec le message mesuré en M4b), bundle (poussées comptées, digest = sha256 du fichier), listee,
#     auth_zot, sur (octets libres). Cas : SIGNER=1 première passe ; rejouée sans changement ; sans SIGNER, absentes : refus ; une
#     seule listée, sans SIGNER : refus ; avec SIGNER : pipeline non signée ; les deux listées : pipeline signée, trois poussées,
#     signatures vérifiées par tkn ; gabarit modifié : refus avant toute signature ; script, contexte du pas de construire-rpm ou
#     stepTemplate de preparer-rpm altérés (empreintes des gabarits remplacées dans le cas) : refus sans aucun versionnement ni
#     poussée, ni de l'une ni de l'autre ; contenu hors champs relus modifié depuis la signature versionnée : refus ; témoin
#     admis, tâche refusée à l'admission, disque de Zot bas : refus. Dans chaque cas : $T/auth absent à la fin, aucun appel de
#     kubectl hors dry-run serveur.
# Non couvert : Zot (vrais bundles), vrai dry-run serveur, Tekton (résolution des bundles, Trusted Resources), clé réelle.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4c-taches-banc.sh <dossier-neuf> <m4c.sh avant>
#         <copie modifiée de m4c.sh>
set -uo pipefail
export LC_ALL=C
B=$1; AVANT=$2; COPIE=$3
RACINE=$PWD; G=$RACINE/poc/bricks/05-rpm-mock/construction; ES=$RACINE/poc/bricks/05-rpm-mock/resultats/m4c-essai-scripts
REG=sc-stockage.poc.test:5000; LISTE_REVUE=$RACINE/poc/bricks/08-trust-plane/politique/porte/taches.yml
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4c-taches-banc.sh, $(date -u +%FT%TZ) ; m4c.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; copie $(sha256sum < "$COPIE" | cut -c1-64)"
echo "# gabarits : $(for f in preparer-rpm construire-rpm sample-app-rpm; do printf '%s %s ; ' "$f" "$(sha256sum < "$G/$f.yaml" | cut -c1-16)"; done)"
echo "# tkn $(tkn version --component client) ; yq $(yq --version | awk '{print $NF}') ; liste revue $(sha256sum < "$LISTE_REVUE" | cut -c1-64)"

echo "## A : insertions seules, syntaxe, shellcheck, scripts archivés"
diff "$AVANT" "$COPIE" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
egal "lignes insérées (en-tête 5, bloc 131)" "$(grep -c '^>' "$B/diff.txt")" 136
egal "bash -n" "$(bash -n "$COPIE" && echo ok)" ok
sc() { LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$1" 2>/dev/null | grep -o 'SC[0-9]*' | sort | uniq -c; }
egal "shellcheck : écarts (nombre de SC2016 seulement)" "$(diff <(sc "$AVANT") <(sc "$COPIE") | grep '^[<>]' | awk '{print $1, $3}' | paste -sd' ')" "< SC2016 > SC2016"
egal "scripts archivés des essais : sha256 égaux aux constantes de la copie" \
  "$(for f in "$ES"/*.sh; do printf '%s:%s\n' "$(basename "$f" .sh)" "$(sha256sum < "$f" | cut -c1-64)"; done | sort | paste -sd' ')" \
  "$(sed -n '/^SCRIPTS_ESSAI_SHA="/,/"/p' "$COPIE" | sed 's/^SCRIPTS_ESSAI_SHA="//; s/".*//' | sort | paste -sd' ')"

# Clé jetable du banc, copie jouable, faux outils
mkdir -p "$B/kbin"
(umask 077 && mkdir -p "$B/O/secrets" && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$B/O/secrets/taches.key" 2> /dev/null)
openssl pkey -in "$B/O/secrets/taches.key" -pubout -out "$B/taches.pub" 2> /dev/null
egal "clé jetable du banc (P-256)" "$(openssl pkey -in "$B/taches.pub" -pubin -noout -text 2> /dev/null | grep -c 'NIST CURVE: P-256')" 1
python3 -I - "$COPIE" "$B/m4c-jouable.sh" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text().split('\n')
r = {'h05=$(cd "$(dirname "$0")" && pwd)': 'h05=$RACINE/poc/bricks/05-rpm-mock', 'C=$h05/construction': 'C=$C_CAS',
     'lancer m4c "05 M4c" "$@"': ':'}
assert all(t.count(a) == 1 for a in r)
pathlib.Path(sys.argv[2]).write_text('\n'.join(r.get(l, l) for l in t))
PY
cat > "$B/kbin/kubectl" <<'E'
#!/usr/bin/env bash
# faux kubectl : dry-run serveur seulement ; témoin refusé avec le message mesuré le 18/11 (m4b-taches-admission.log)
echo "kubectl $*" >> "$BANC_APPELS"
case "$*" in
  "create --dry-run=server -n builds -f "*)
    f=${*: -1}
    if [ -n "${BANC_TACHE_REFUSEE:-}" ] && grep -q "^  name: $BANC_TACHE_REFUSEE$" "$f"; then echo "Error from server (Forbidden): refus du banc"; exit 1; fi
    if grep -q '^ *computeResources:' "$f" && [ -z "${BANC_TEMOIN_ADMIS:-}" ]; then
      echo "Error from server (BadRequest): error when creating \"$f\": Task in version \"v1beta1\" cannot be handled as a Task: strict decoding error: unknown field \"spec.steps[0].computeResources\""; exit 1
    fi
    echo "$(yq '.kind | downcase' "$f").tekton.dev/$(yq .metadata.name "$f") created (server dry run)"; exit 0 ;;
esac
echo "faux kubectl : appel inattendu : $*" >&2; exit 3
E
chmod +x "$B/kbin/kubectl"
gabarits() { mkdir -p "$1"; cp "$G/preparer-rpm.yaml" "$G/construire-rpm.yaml" "$G/sample-app-rpm.yaml" "$1/"; }
empreintes() { # dossier : GABARITS_SHA des gabarits de ce dossier (cas où l'on veut atteindre les contrôles d'après la signature)
  for f in preparer-rpm construire-rpm sample-app-rpm; do printf '%s.yaml:%s\n' "$f" "$(sha256sum < "$1/$f.yaml" | cut -c1-64)"; done
}
jouer() { # W C [VAR=valeur…] : etape_taches de la copie jouable, dans la forme de lancer ; sortie dans <W>/sortie.txt ; code rendu
  local w=$1 c=$2; shift 2
  mkdir -p "$w"; : > "$w/appels"; : > "$w/poussees"
  env CONFIANCE_DIR="$B/O-$(basename "$w")" DISTRO=rke2 RACINE="$RACINE" C_CAS="$c" PATH="$B/kbin:$PATH" BANC_APPELS="$w/appels" BANC_W="$w" "$@" bash -c '
    set -euo pipefail
    mkdir -p "$CONFIANCE_DIR" && cp -a "$(dirname "$CONFIANCE_DIR")/O/secrets" "$CONFIANCE_DIR/secrets"
    . "$1"
    [ -z "${BANC_GABARITS_SHA:-}" ] || GABARITS_SHA=$BANC_GABARITS_SHA
    bundle() { echo "$2:$3 $(sha256sum < "$1" | cut -c1-64)" >> "$BANC_W/poussees"; echo "sha256:$(sha256sum < "$1" | cut -c1-64)"; }
    listee() { [ -n "${BANC_LISTEE:-}" ] && grep -qxF "$1" "$BANC_LISTEE"; }
    auth_zot() { printf "{\"faux\":1}\n" > "$1"; }
    sur() { echo " ${BANC_LIBRE-4495519744}"; }
    { echo "# etape_taches (banc), $(date -u +%FT%TZ)"; etape_taches; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$BANC_W/sortie.txt" > /dev/null' _ "$B/m4c-jouable.sh"
}
tdir() { echo "$B/O-$(basename "$1")/travail/m4c-05"; }
cas() { # libellé code motif W C [VAR=valeur…]
  local lib=$1 voulu=$2 motif=$3 w=$4 c=$5 rc; shift 5
  jouer "$w" "$c" "$@"; rc=$?
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$w/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 3 "$w/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
  egal "$lib : \$T/auth absent à la fin" "$([ -e "$(tdir "$w")/auth" ] && echo présent || echo absent)" absent
  egal "$lib : appels de kubectl hors dry-run serveur" "$(grep -c -v '^kubectl create --dry-run=server -n builds -f ' "$w/appels")" 0
}
poussees() { grep -c . "$1/poussees"; }
versionnees() { local f r=""; for f in preparer-rpm construire-rpm; do [ -e "$1/$f.signee.yaml" ] && r="$r $f"; done; echo "${r# }"; }
aucune_trace() { # libellé W C : ni signature versionnée ni poussée
  egal "$1 : ni versionnement ni poussée" "[$(versionnees "$3")] $(poussees "$2")" "[] 0"
}

echo "## B : vraie fonction etape_taches, vrai tkn, clé jetable"
gabarits "$B/c1"
cas "SIGNER=1, première passe" 0 "^SIGNER : pipeline non signée tant que la liste revue n'a pas été acceptée$" "$B/W1" "$B/c1" SIGNER=1
egal "première passe : nouvelles signatures" "$(grep -c '^SIGNER : nouvelle signature dans construction/' "$B/W1/sortie.txt")" 2
egal "première passe : références à ajouter" "$(grep -c '^SIGNER : à ajouter à politique/porte/taches.yml' "$B/W1/sortie.txt")" 2
egal "première passe : lignes OK de l'étape" "$(grep -c '^OK   ' "$B/W1/sortie.txt")" 31
egal "première passe : scripts relus égaux à ceux des essais" "$(grep -c '^OK   .* signée : script .*, substitué, égal à celui joué à l.essai' "$B/W1/sortie.txt")" 4
egal "première passe : témoin refusé, message mesuré" "$(grep -c '^OK   témoin refusé : champ inconnu' "$B/W1/sortie.txt")" 1
egal "première passe : relevé du disque avant les poussées" "$(grep -c '^relevé : octets libres sur / de sc-stockage (porte /var/lib/zot) avant les poussées : 4495519744$' "$B/W1/sortie.txt")" 1
egal "première passe : poussées (deux tâches, tag m4c)" "$(cut -d' ' -f1 "$B/W1/poussees" | paste -sd' ')" "tekton/tasks/preparer-rpm:m4c tekton/tasks/construire-rpm:m4c"
egal "première passe : signatures versionnées, pipeline non signée" \
  "[$(versionnees "$B/c1")] $([ -e "$(tdir "$B/W1")/sample-app-rpm-signee.yaml" ] && echo signée || echo non-signée)" "[preparer-rpm construire-rpm] non-signée"
for t in preparer-rpm construire-rpm; do
  egal "première passe : $t vérifiée par tkn (clé publique du banc)" \
    "$(tkn task verify "$B/c1/$t.signee.yaml" -K "$B/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
  egal "première passe : $t, digest poussé = fichier versionné" "$(grep "^tekton/tasks/$t:m4c " "$B/W1/poussees" | cut -d' ' -f2)" "$(sha256sum < "$B/c1/$t.signee.yaml" | cut -c1-64)"
  cp "$B/c1/$t.signee.yaml" "$B/$t-signee-1.yaml"
  echo "première passe : $t signée du banc, $(wc -c < "$B/$t-signee-1.yaml") octets ; clés de metadata $(yq -o=json -I=0 '.metadata | keys' "$B/$t-signee-1.yaml")"
done
egal "première passe : scripts substitués de la copie = scripts archivés des essais" \
  "$(for f in "$ES"/*.sh; do cmp -s "$f" "$(tdir "$B/W1")/scripts-signes/${f##*/}" && echo égal || echo "différent ${f##*/}"; done | sort -u)" égal
VP=$(sha256sum < "$B/c1/preparer-rpm.signee.yaml" | cut -c1-64); VC=$(sha256sum < "$B/c1/construire-rpm.signee.yaml" | cut -c1-64)
RP=$REG/tekton/tasks/preparer-rpm@sha256:$VP; RC=$REG/tekton/tasks/construire-rpm@sha256:$VC
cas "SIGNER=1, rejouée sans changement" 0 "^SIGNER : pipeline non signée" "$B/W2" "$B/c1" SIGNER=1
egal "rejouée : pas de nouvelle signature" "$(grep -c '^SIGNER : nouvelle signature' "$B/W2/sortie.txt")" 0
egal "rejouée : fichiers versionnés et digests poussés inchangés" \
  "$(sha256sum < "$B/c1/preparer-rpm.signee.yaml" | cut -c1-64) $(sha256sum < "$B/c1/construire-rpm.signee.yaml" | cut -c1-64) $(cut -d' ' -f2 "$B/W2/poussees" | paste -sd' ')" "$VP $VC $VP $VC"
cas "sans SIGNER, absentes de la liste revue : refusé" 1 "^KO   preparer-rpm absente de la liste revue : $RP$" "$B/W3" "$B/c1"
echo "$RP" > "$B/une.txt"
cas "sans SIGNER, construire-rpm absente : refusé" 1 "^KO   construire-rpm absente de la liste revue : $RC$" "$B/W4" "$B/c1" BANC_LISTEE="$B/une.txt"
cas "SIGNER=1, une seule listée : pipeline non signée" 0 "^SIGNER : pipeline non signée" "$B/W5" "$B/c1" SIGNER=1 BANC_LISTEE="$B/une.txt"
egal "une seule listée : OK de preparer-rpm, construire-rpm à ajouter, aucune pipeline" \
  "$(grep -c "^OK   preparer-rpm dans la liste revue : $RP$" "$B/W5/sortie.txt") $(grep -c "^SIGNER : à ajouter .* : $RC$" "$B/W5/sortie.txt") $([ -e "$(tdir "$B/W5")/sample-app-rpm-signee.yaml" ] && echo signée || echo aucune)" "1 1 aucune"
printf '%s\n%s\n' "$RP" "$RC" > "$B/deux.txt"
cas "sans SIGNER, les deux listées : pipeline signée" 0 "^$REG/tekton/pipelines/sample-app-rpm@sha256:[0-9a-f]{64}$" "$B/W6" "$B/c1" BANC_LISTEE="$B/deux.txt"
egal "pipeline : lignes OK de l'étape" "$(grep -c '^OK   ' "$B/W6/sortie.txt")" 41
egal "pipeline : poussées (deux tâches, puis la pipeline)" "$(cut -d' ' -f1 "$B/W6/poussees" | paste -sd' ')" \
  "tekton/tasks/preparer-rpm:m4c tekton/tasks/construire-rpm:m4c tekton/pipelines/sample-app-rpm:m4c"
PS=$(tdir "$B/W6")/sample-app-rpm-signee.yaml
egal "pipeline : signature vérifiée par tkn (clé publique du banc)" "$(tkn pipeline verify "$PS" -K "$B/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
egal "pipeline signée : références des tâches" "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$PS")" \
  "$RP $RC $REG/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b"
egal "pipeline signée : entrées par digest, époque, subPath" \
  "$(yq -o=json -I=0 '[[.spec.tasks[0].params[2:][].value], .spec.tasks[1].params, [.spec.tasks[].workspaces[].subPath]]' "$PS")" \
  "[[\"$REG/builds/fermetures/sample-app-rpm@sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c\",\"$REG/builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21\",\"$REG/entrees/sample-app/packaging-rpm@sha256:41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8\"],[{\"name\":\"epoque\",\"value\":\"1793229566\"}],[null,\"entrees\",\"image\",\"image\"]]"
egal "pipeline : référence écrite sous \$T/sample-app-rpm.ref, aucun pipeline.ref" \
  "$(grep -c "^$REG/tekton/pipelines/sample-app-rpm@sha256:" "$(tdir "$B/W6")/sample-app-rpm.ref") $([ -e "$(tdir "$B/W6")/pipeline.ref" ] && echo présent || echo absent)" "1 absent"
egal "témoin de vérification : tâche altérée après signature refusée par tkn" \
  "$(sed 's/memory: 6Gi/memory: 7Gi/' "$B/construire-rpm-signee-1.yaml" > "$B/alteree.yaml"; tkn task verify "$B/alteree.yaml" -K "$B/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" refusée

gabarits "$B/c7"; sed -i 's/^  name: construire-rpm$/  name: construire-rpm\n  labels:\n    banc: modifie/' "$B/c7/construire-rpm.yaml"
cas "gabarit modifié : refusé avant toute signature" 1 "^KO   gabarit construire-rpm.yaml égal à celui des essais \(sha256\)" "$B/W7" "$B/c7" SIGNER=1
aucune_trace "gabarit modifié" "$B/W7" "$B/c7"
egal "gabarit modifié : aucune tâche signée" "$(ls "$(tdir "$B/W7")" | grep -c -- '-signee.yaml$')" 0
gabarits "$B/c8"; sed -i 's/echo "Source0 $nom-$ver.tar.gz (époque/echo "Source0 $nom-$ver.tar.gz (epoque/' "$B/c8/construire-rpm.yaml"
egal "script altéré : gabarit du banc modifié" "$(cmp -s "$G/construire-rpm.yaml" "$B/c8/construire-rpm.yaml" && echo identique || echo modifié)" modifié
cas "script de construire-rpm altéré, SIGNER=1 : refusé" 1 "^KO   construire-rpm signée : script construire-rpm-construire, substitué, égal à celui joué à l.essai" \
  "$B/W8" "$B/c8" SIGNER=1 BANC_GABARITS_SHA="$(empreintes "$B/c8")"
aucune_trace "script altéré" "$B/W8" "$B/c8"
gabarits "$B/c9"; sed -i 's/^      runAsUser: 0$/      runAsUser: 1000/' "$B/c9/construire-rpm.yaml"
cas "contexte du pas de construire-rpm altéré, SIGNER=1 : refusé" 1 "^KO   construire-rpm signée : contexte du pas" "$B/W9" "$B/c9" SIGNER=1 BANC_GABARITS_SHA="$(empreintes "$B/c9")"
aucune_trace "contexte altéré" "$B/W9" "$B/c9"
gabarits "$B/c10"; sed -i 's/^      runAsNonRoot: true$/      runAsNonRoot: false/' "$B/c10/preparer-rpm.yaml"
cas "stepTemplate de preparer-rpm altéré, SIGNER=1 : refusé" 1 "^KO   preparer-rpm signée : contexte et montages du stepTemplate" "$B/W10" "$B/c10" SIGNER=1 BANC_GABARITS_SHA="$(empreintes "$B/c10")"
aucune_trace "stepTemplate altéré" "$B/W10" "$B/c10"
gabarits "$B/c11"; cp "$B/preparer-rpm-signee-1.yaml" "$B/c11/preparer-rpm.signee.yaml"; cp "$B/construire-rpm-signee-1.yaml" "$B/c11/construire-rpm.signee.yaml"
sed -i 's/^  name: preparer-rpm$/  name: preparer-rpm\n  labels:\n    banc: modifie/' "$B/c11/preparer-rpm.yaml"
cas "contenu modifié depuis la signature versionnée, sans SIGNER : refusé" 1 "^KO   preparer-rpm : signature versionnée conforme au gabarit rendu, signature exceptée : différente" \
  "$B/W11" "$B/c11" BANC_GABARITS_SHA="$(empreintes "$B/c11")"
egal "contenu modifié : aucune poussée" "$(poussees "$B/W11")" 0
gabarits "$B/c12"
cas "témoin admis : refusé avant tkn" 1 "^KO   témoin \(computeResources dans un pas v1beta1\) admis" "$B/W12" "$B/c12" SIGNER=1 BANC_TEMOIN_ADMIS=1
egal "témoin admis : aucune tâche signée" "$(ls "$(tdir "$B/W12")" | grep -c -- '-signee.yaml$')" 0
aucune_trace "témoin admis" "$B/W12" "$B/c12"
gabarits "$B/c13"
cas "construire-rpm refusée à l'admission : refusé" 1 "^KO   construire-rpm rendue admise \(code de kubectl\) : 1" "$B/W13" "$B/c13" SIGNER=1 BANC_TACHE_REFUSEE=construire-rpm
aucune_trace "tâche refusée" "$B/W13" "$B/c13"
gabarits "$B/c14"
cas "disque de Zot bas : refusé avant tout versionnement" 1 "^KO   octets libres sur / de sc-stockage sous 1073741824 : 1000$" "$B/W14" "$B/c14" SIGNER=1 BANC_LIBRE=1000
aucune_trace "disque bas" "$B/W14" "$B/c14"
gabarits "$B/c15"
cas "octets libres illisibles : refusé" 1 "^KO   octets libres sur / de sc-stockage sous 1073741824 : $" "$B/W15" "$B/c15" SIGNER=1 BANC_LIBRE=
aucune_trace "octets illisibles" "$B/W15" "$B/c15"
egal "gabarits du dépôt inchangés par le banc" "$(for f in preparer-rpm construire-rpm sample-app-rpm; do sha256sum < "$G/$f.yaml" | cut -c1-16; done | paste -sd' ')" "a7dfa37e23948209 e88f5521ede87f5b a9917a65c994421f"
egal "aucune signature versionnée dans le dépôt" "$(ls "$G" | grep -c 'signee')" 0
echo "# bilan : $([ "$k" = 0 ] && echo tenu || echo NON TENU), $n OK, $k KO, fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
