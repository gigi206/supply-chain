#!/usr/bin/env bash
# Brique 05, M4b : banc hors cluster et hors Zot de l'étape taches de m4b.sh (préparée à sec le 18/11/2026, accord permanent du
# 18/11), écrit avant tout passage.
# A : insertions seules contre le m4b.sh d'avant (trois blocs : en-tête, auth et trap au niveau haut comme m4a.sh, bloc avant
#     lancer) ; bash -n ; shellcheck : mêmes codes avant et après.
# B : la vraie fonction etape_taches de la copie, jouée dans la forme de lancer ({ …; } 2>&1 | sed | tee), avec le vrai tkn
#     (0.46.2, mise) et une clé P-256 jetable du banc (jamais taches.key), les vrais gabarits (copiés par cas, car SIGNER écrit la
#     signature versionnée à côté), la vraie liste, le vrai verrou et la vraie liste revue de la 08 ; faux : kubectl (dry-run seul,
#     témoin refusé avec le message mesuré), bundle (poussées comptées, digest = sha256 du fichier), listee, auth_zot.
#     Cas : SIGNER=1 première passe ; SIGNER=1 rejouée sans changement (pas de nouvelle signature, l'erreur de S4a) ; sans SIGNER,
#     digest absent de la liste : refus ; présent : pipeline signée, deux poussées, signatures vérifiées par tkn avec la clé
#     publique du banc ; gabarit modifié depuis la signature : refus ; script altéré ou ressources retirées : refus sans
#     versionnement ni poussée ; témoin admis : refus avant tkn ; tâche refusée à l'admission : refus. Dans chaque cas : $T/auth
#     absent à la fin, aucun appel de kubectl hors dry-run serveur.
# C : l'ancien banc (m4b-taches-banc.sh, sections B à D : prealables_taches, script de la tâche, essai_tache) rejoué sur la copie ;
#     seuls KO admis : les trois de sa section A, propres à l'ajout précédent (deux blocs, 179 lignes, écart SC2016 attendus).
# Non couvert : Zot (vrais bundles), vrai dry-run serveur (mesuré à part : m4b-taches-admission.log), Tekton (résolution des
#     bundles, Trusted Resources), clé des tâches réelle.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m4b-taches-signer-banc.sh <dossier-neuf> <m4b.sh avant>
#         <copie modifiée de m4b.sh>
set -uo pipefail
export LC_ALL=C
B=$1; AVANT=$2; COPIE=$3
RACINE=$PWD; G=$RACINE/poc/bricks/05-rpm-mock/fermeture; REG=sc-stockage.poc.test:5000
LISTE_REVUE=$RACINE/poc/bricks/08-trust-plane/politique/porte/taches.yml
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m4b-taches-signer-banc.sh, $(date -u +%FT%TZ) ; m4b.sh avant $(sha256sum < "$AVANT" | cut -c1-64) ; copie $(sha256sum < "$COPIE" | cut -c1-64)"
echo "# gabarits : prefetch-rpm.yaml $(sha256sum < "$G/prefetch-rpm.yaml" | cut -c1-64) ; prefetch-rpm-sample-app.yaml $(sha256sum < "$G/prefetch-rpm-sample-app.yaml" | cut -c1-64)"
echo "# tkn $(tkn version --component client) ; yq $(yq --version | awk '{print $NF}') ; liste revue $(sha256sum < "$LISTE_REVUE" | cut -c1-64)"

echo "## A : insertions seules, syntaxe, shellcheck"
diff "$AVANT" "$COPIE" > "$B/diff.txt"
egal "lignes retirées ou changées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 3
egal "lignes insérées (en-tête 10, auth 2, bloc 85)" "$(grep -c '^>' "$B/diff.txt")" 97
egal "bash -n" "$(bash -n "$COPIE" && echo ok)" ok
sc() { LC_ALL=C.UTF-8 shellcheck -x -e SC1091 "$1" 2>/dev/null | grep -o 'SC[0-9]*' | sort | uniq -c; }
egal "shellcheck : mêmes codes avant et après" "$(diff <(sc "$AVANT") <(sc "$COPIE") > /dev/null && echo mêmes || echo différents)" mêmes

# Clé jetable du banc, copie jouable, faux outils
mkdir -p "$B/S" "$B/kbin"
(umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$B/S/taches.key" 2> /dev/null)
openssl pkey -in "$B/S/taches.key" -pubout -out "$B/taches.pub" 2> /dev/null
egal "clé jetable du banc (P-256)" "$(openssl pkey -in "$B/taches.pub" -pubin -noout -text 2> /dev/null | grep -c 'NIST CURVE: P-256')" 1
python3 -I - "$COPIE" "$B/m4b-jouable.sh" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text().split('\n')
r = {'. "$here/commun.sh"   # repo, O, S, P, W, REG, lancer, chrono': ':', 'h05=$(cd "$(dirname "$0")" && pwd)': 'h05=$RACINE/poc/bricks/05-rpm-mock',
     'lancer m4b "05 M4b" "$@"': ':'}
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
    if [ -n "${BANC_TACHE_REFUSEE:-}" ] && grep -q '^kind: Task$' "$f"; then echo "Error from server (Forbidden): refus du banc"; exit 1; fi
    if grep -q '^ *computeResources:' "$f" && [ -z "${BANC_TEMOIN_ADMIS:-}" ]; then
      echo "Error from server (BadRequest): error when creating \"$f\": Task in version \"v1beta1\" cannot be handled as a Task: strict decoding error: unknown field \"spec.steps[0].computeResources\""; exit 1
    fi
    echo "$(yq '.kind | downcase' "$f").tekton.dev/$(yq .metadata.name "$f") created (server dry run)"; exit 0 ;;
esac
echo "faux kubectl : appel inattendu : $*" >&2; exit 3
E
chmod +x "$B/kbin/kubectl"
gabarits() { mkdir -p "$1"; cp "$G/prefetch-rpm.yaml" "$G/prefetch-rpm-sample-app.yaml" "$1/"; }
jouer() { # W TACHES [VAR=valeur…] : etape_taches de la copie jouable, dans la forme de lancer ; sortie dans <W>/sortie.txt ; code rendu
  local w=$1 t=$2; shift 2
  mkdir -p "$w"; : > "$w/appels"; : > "$w/poussees"
  env W="$w" S="$B/S" REG="$REG" RACINE="$RACINE" TACHES_CAS="$t" PATH="$B/kbin:$PATH" BANC_APPELS="$w/appels" "$@" bash -c '
    set -euo pipefail
    . "$1"
    TACHES=$TACHES_CAS
    bundle() { echo "$2:$3 $(sha256sum < "$1" | cut -c1-64)" >> "$W/poussees"; echo "sha256:$(sha256sum < "$1" | cut -c1-64)"; }
    listee() { [ -n "${BANC_LISTEE:-}" ] && grep -qxF "$1" "$BANC_LISTEE"; }
    auth_zot() { printf "{\"faux\":1}\n" > "$1"; }
    { echo "# etape_taches (banc), $(date -u +%FT%TZ)"; etape_taches; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$W/sortie.txt" > /dev/null' _ "$B/m4b-jouable.sh"
}
cas() { # libellé code motif W TACHES [VAR=valeur…]
  local lib=$1 voulu=$2 motif=$3 w=$4 t=$5 rc; shift 5
  jouer "$w" "$t" "$@"; rc=$?
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$w/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 3 "$w/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
  egal "$lib : \$T/auth absent à la fin" "$([ -e "$w/m4b-05/auth" ] && echo présent || echo absent)" absent
  egal "$lib : appels de kubectl hors dry-run serveur" "$(grep -c -v '^kubectl create --dry-run=server -n builds -f ' "$w/appels")" 0
}
poussees() { grep -c . "$1/poussees"; }

echo "## B : vraie fonction etape_taches, vrai tkn, clé jetable"
gabarits "$B/f1"
cas "SIGNER=1, première passe" 0 "^SIGNER : pipeline non signée tant que la liste revue n'a pas été acceptée$" "$B/W1" "$B/f1" SIGNER=1
egal "première passe : nouvelle signature, à ajouter" "$(grep -c '^SIGNER : nouvelle signature dans fermeture/prefetch-rpm.signee.yaml$\|^SIGNER : à ajouter à politique/porte/taches.yml' "$B/W1/sortie.txt")" 2
egal "première passe : lignes OK de l'étape" "$(grep -c '^OK   ' "$B/W1/sortie.txt")" 13
egal "première passe : témoin refusé, message mesuré" "$(grep -c '^OK   témoin refusé : champ inconnu' "$B/W1/sortie.txt")" 1
egal "première passe : poussées (tâche seule, tag m4b)" "$(cut -d' ' -f1 "$B/W1/poussees" | paste -sd' ')" "tekton/tasks/prefetch-rpm:m4b"
egal "première passe : signature versionnée écrite, pipeline non signée" \
  "$([ -s "$B/f1/prefetch-rpm.signee.yaml" ] && echo écrite) $([ -e "$B/W1/m4b-05/prefetch-rpm-sample-app-signee.yaml" ] && echo signée || echo non-signée)" "écrite non-signée"
egal "première passe : signature de la tâche vérifiée par tkn (clé publique du banc)" \
  "$(tkn task verify "$B/f1/prefetch-rpm.signee.yaml" -K "$B/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
D1=$(cut -d' ' -f2 "$B/W1/poussees"); V1=$(sha256sum < "$B/f1/prefetch-rpm.signee.yaml" | cut -c1-64)
egal "première passe : digest poussé = fichier versionné" "$D1" "$V1"
egal "première passe : référence affichée" "$(grep -c -F "SIGNER : à ajouter à politique/porte/taches.yml (08) après revue du propriétaire : $REG/tekton/tasks/prefetch-rpm@sha256:$V1" "$B/W1/sortie.txt")" 1
cp "$B/f1/prefetch-rpm.signee.yaml" "$B/signee-1.yaml"
echo "première passe : tâche signée du banc, $(wc -c < "$B/signee-1.yaml") octets ; clés du pas $(yq -o=json -I=0 '.spec.steps[0] | keys' "$B/signee-1.yaml")"
cas "SIGNER=1, rejouée sans changement" 0 "^SIGNER : pipeline non signée" "$B/W2" "$B/f1" SIGNER=1
egal "rejouée : pas de nouvelle signature" "$(grep -c '^SIGNER : nouvelle signature' "$B/W2/sortie.txt")" 0
egal "rejouée : fichier versionné inchangé" "$(sha256sum < "$B/f1/prefetch-rpm.signee.yaml" | cut -c1-64)" "$V1"
egal "rejouée : même digest poussé" "$(cut -d' ' -f2 "$B/W2/poussees")" "$D1"
cas "sans SIGNER, digest absent de la liste revue : refusé" 1 "^KO   prefetch-rpm absente de la liste revue : $REG/tekton/tasks/prefetch-rpm@sha256:$V1$" "$B/W3" "$B/f1"
echo "$REG/tekton/tasks/prefetch-rpm@sha256:$V1" > "$B/listee.txt"
cas "sans SIGNER, digest dans la liste revue : pipeline signée" 0 "^$REG/tekton/pipelines/prefetch-rpm-sample-app@sha256:[0-9a-f]{64}$" "$B/W4" "$B/f1" BANC_LISTEE="$B/listee.txt"
egal "pipeline : lignes OK de l'étape" "$(grep -c '^OK   ' "$B/W4/sortie.txt")" 28
egal "pipeline : poussées (tâche, puis pipeline)" "$(cut -d' ' -f1 "$B/W4/poussees" | paste -sd' ')" "tekton/tasks/prefetch-rpm:m4b tekton/pipelines/prefetch-rpm-sample-app:m4b"
egal "pipeline : signature vérifiée par tkn (clé publique du banc)" \
  "$(tkn pipeline verify "$B/W4/m4b-05/prefetch-rpm-sample-app-signee.yaml" -K "$B/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
egal "pipeline : références des tâches signées" \
  "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$B/W4/m4b-05/prefetch-rpm-sample-app-signee.yaml")" \
  "$REG/tekton/tasks/prefetch-rpm@sha256:$V1 $REG/tekton/tasks/publier-fermeture@sha256:7fa92ad3e4adb0d4b9bc4209ee04096d476dee5ffa173fc08b9cac0614e2b135"
egal "témoin de vérification : tâche altérée après signature refusée par tkn" \
  "$(sed 's/memory: 2Gi/memory: 3Gi/' "$B/signee-1.yaml" > "$B/signee-alteree.yaml"; tkn task verify "$B/signee-alteree.yaml" -K "$B/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" refusée
gabarits "$B/f5"; cp "$B/signee-1.yaml" "$B/f5/prefetch-rpm.signee.yaml"
sed -i 's/^  name: prefetch-rpm$/  name: prefetch-rpm\n  labels:\n    banc: modifie/' "$B/f5/prefetch-rpm.yaml"
cas "gabarit modifié depuis la signature : refusé" 1 "^KO   signature versionnée conforme au gabarit rendu, signature exceptée : différente" "$B/W5" "$B/f5"
egal "gabarit modifié : aucune poussée" "$(poussees "$B/W5")" 0
gabarits "$B/f6"; sed -i 's/téléchargés et contrôlés (sha256, taille)/téléchargés et contrôlés/' "$B/f6/prefetch-rpm.yaml"
egal "script altéré : gabarit du banc modifié" "$(cmp -s "$G/prefetch-rpm.yaml" "$B/f6/prefetch-rpm.yaml" && echo identique || echo modifié)" modifié
cas "script altéré, SIGNER=1 : refusé" 1 "^KO   script de la tâche signée, substitué comme à l'essai \(sha256\)" "$B/W6" "$B/f6" SIGNER=1
egal "script altéré : ni versionnement ni poussée" "$([ -e "$B/f6/prefetch-rpm.signee.yaml" ] && echo versionnée || echo non) $(poussees "$B/W6")" "non 0"
gabarits "$B/f7"; sed -i '/^    resources:$/,/^        memory: 2Gi$/d; /^      limits:$/,/^        memory: 2Gi$/d' "$B/f7/prefetch-rpm.yaml"
egal "ressources retirées : gabarit du banc sans resources" "$(grep -c 'cpu: "2"' "$B/f7/prefetch-rpm.yaml")" 0
cas "ressources retirées, SIGNER=1 : refusé" 1 "^KO   tâche signée : ressources du pas" "$B/W7" "$B/f7" SIGNER=1
egal "ressources retirées : ni versionnement ni poussée" "$([ -e "$B/f7/prefetch-rpm.signee.yaml" ] && echo versionnée || echo non) $(poussees "$B/W7")" "non 0"
gabarits "$B/f8"
cas "témoin admis : refusé avant tkn" 1 "^KO   témoin \(computeResources dans un pas v1beta1\) admis" "$B/W8" "$B/f8" SIGNER=1 BANC_TEMOIN_ADMIS=1
egal "témoin admis : aucune signature produite" "$([ -e "$B/W8/m4b-05/prefetch-rpm-signee.yaml" ] && echo produite || echo aucune) $(poussees "$B/W8")" "aucune 0"
gabarits "$B/f9"
cas "tâche refusée à l'admission : refusé" 1 "^KO   tâche rendue admise \(code de kubectl\) : 1" "$B/W9" "$B/f9" SIGNER=1 BANC_TACHE_REFUSEE=1
egal "tâche refusée : aucune poussée" "$(poussees "$B/W9")" 0

echo "## C : ancien banc (prealables_taches, script, essai_tache) rejoué sur la copie"
bash poc/bricks/05-rpm-mock/resultats/m4b-taches-banc.sh "$B/ancien" "$AVANT" "$COPIE" > "$B/ancien.out" 2>&1
grep '^KO   ' "$B/ancien.out" | sed 's/^/     /'
egal "ancien banc : KO de sa section A (blocs, lignes, écart de shellcheck attendu pour l'ajout précédent)" \
  "$(sed -n '/^## A /,/^## B /p' "$B/ancien.out" | grep -c '^KO   ')" 3
egal "ancien banc : KO de sa section A, libellés" \
  "$(sed -n '/^## A /,/^## B /p' "$B/ancien.out" | grep '^KO   ' | sed 's/ :.*//' | paste -sd'|')" "KO   blocs insérés|KO   lignes insérées (en-tête 14, bloc 165)|KO   shellcheck"
egal "ancien banc : sections B à D, OK" "$(sed -n '/^## B /,$p' "$B/ancien.out" | grep -c '^OK   ')" "$(sed -n '/^## B /,$p' "$B/ancien.out" | grep -c '^OK   \|^KO   ')"
echo "ancien banc : $(tail -n 1 "$B/ancien.out")"
echo "# bilan : $([ "$k" = 0 ] && echo tenu || echo NON TENU), $n OK, $k KO, fin $(date -u +%FT%TZ)"
[ "$k" = 0 ]
