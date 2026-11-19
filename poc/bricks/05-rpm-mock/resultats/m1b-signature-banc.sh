#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : banc hors cluster et hors Zot de l'étape taches de m1b-signature.sh (préparée à sec le 19/11/2026), sur le
# modèle de m4c-taches-banc.sh. La vraie fonction etape_taches, chargée depuis le vrai script, jouée dans la forme de lancer
# ({ …; } 2>&1 | sed | tee), avec le vrai commun.sh (CONFIANCE_DIR du banc), le vrai tkn (mise), une clé P-256 jetable du banc
# (jamais taches.key), les vrais rendus de m1bt3 (TD1) et une copie de la vraie liste revue par cas ; faux : kubectl (dry-run
# serveur seul), bundle (poussées comptées, digest = sha256 du fichier), auth_zot, sur (octets libres).
# Cas : SIGNER=1 première passe ; rejouée sans changement ; sans SIGNER, absentes de la liste : refus ; sans SIGNER, rien de
# versionné : refus ; les deux listées : pipelines signées, références réelles, signatures vérifiées par tkn ; rendu altéré : refus
# avant toute signature ; tâche refusée à l'admission : refus ; disque de Zot bas : refus. Dans chaque cas : $T/auth absent à la
# fin, aucun appel de kubectl hors dry-run serveur.
# Non couvert : Zot (vrais bundles), vrai dry-run serveur, Tekton (résolution des bundles, Trusted Resources), clé réelle.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-signature-banc.sh <dossier-neuf>
set -uo pipefail
export LC_ALL=C
B=$1
RACINE=$PWD; SCRIPT=$RACINE/poc/bricks/05-rpm-mock/m1b-signature.sh
RENDU0=$HOME/.cache/supply-chain-poc/08/travail/m1bt3-05   # lecture seule
LISTE0=$RACINE/poc/bricks/08-trust-plane/politique/porte/taches.yml
REG=sc-stockage.poc.test:5000
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
mkdir -p "$B"
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
echo "# m1b-signature-banc.sh, $(date -u +%FT%TZ) ; m1b-signature.sh $(sha256sum < "$SCRIPT" | cut -c1-64)"
echo "# tkn $(tkn version --component client) ; yq $(yq --version | awk '{print $NF}') ; liste revue $(sha256sum < "$LISTE0" | cut -c1-64)"

mkdir -p "$B/kbin"
(umask 077 && mkdir -p "$B/O/secrets" && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$B/O/secrets/taches.key" 2> /dev/null)
openssl pkey -in "$B/O/secrets/taches.key" -pubout -out "$B/taches.pub" 2> /dev/null
egal "clé jetable du banc (P-256)" "$(openssl pkey -in "$B/taches.pub" -pubin -noout -text 2> /dev/null | grep -c 'NIST CURVE: P-256')" 1
cat > "$B/kbin/kubectl" <<'E'
#!/usr/bin/env bash
# faux kubectl : dry-run serveur seulement ; BANC_REFUSEE : nom d'objet refusé
echo "kubectl $*" >> "$BANC_APPELS"
case "$*" in
  "create --dry-run=server -n builds -f "*)
    f=${*: -1}
    if [ -n "${BANC_REFUSEE:-}" ] && [ "$(yq .metadata.name "$f")" = "$BANC_REFUSEE" ]; then echo "refus du banc" >&2; exit 1; fi
    exit 0 ;;
esac
echo "faux kubectl : appel inattendu : $*" >&2; exit 3
E
chmod +x "$B/kbin/kubectl"

jouer() { # W V L RENDU [VAR=valeur…] : etape_taches dans la forme de lancer ; sortie dans <W>/sortie.txt ; code rendu
  local w=$1 v=$2 l=$3 r=$4; shift 4
  mkdir -p "$w" "$v"; : > "$w/appels"; : > "$w/poussees"
  env CONFIANCE_DIR="$B/O-$(basename "$w")" DISTRO=rke2 RENDU="$r" VERSIONS="$v" LISTE_REVUE="$l" PATH="$B/kbin:$PATH" \
    BANC_APPELS="$w/appels" BANC_W="$w" "$@" bash -c '
    set -euo pipefail
    mkdir -p "$CONFIANCE_DIR" && cp -a "$(dirname "$CONFIANCE_DIR")/O/secrets" "$CONFIANCE_DIR/secrets"
    . "$1"
    bundle() { echo "$2:$3 $(sha256sum < "$1" | cut -c1-64)" >> "$BANC_W/poussees"; echo "sha256:$(sha256sum < "$1" | cut -c1-64)"; }
    auth_zot() { printf "{\"faux\":1}\n" > "$1"; }
    sur() { echo " ${BANC_LIBRE-3978911744}"; }
    { echo "# etape_taches (banc), $(date -u +%FT%TZ)"; etape_taches; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$BANC_W/sortie.txt" > /dev/null' _ "$SCRIPT"
}
tdir() { echo "$B/O-$(basename "$1")/travail/m1b-signature-05"; }
cas() { # libellé code motif W V L RENDU [VAR=valeur…]
  local lib=$1 voulu=$2 motif=$3 w=$4 rc; shift 3
  jouer "$@"; rc=$?
  if [ "$rc" = "$voulu" ] && grep -q -E -- "$motif" "$w/sortie.txt"; then echo "OK   $lib (code $rc)"; n=$((n + 1))
  else echo "KO   $lib : code $rc, attendu $voulu ; sortie : $(tail -n 3 "$w/sortie.txt" | tr '\n' ' ')"; k=$((k + 1)); fi
  egal "$lib : \$T/auth absent à la fin" "$([ -e "$(tdir "$w")/auth" ] && echo présent || echo absent)" absent
  egal "$lib : appels de kubectl hors dry-run serveur" "$(grep -c -v '^kubectl create --dry-run=server -n builds -f ' "$w/appels")" 0
}
poussees() { grep -c . "$1/poussees"; }
versionnees() { local f r=""; for f in prefetch-racine-rpm construire-racine-rpm; do [ -e "$1/$f.signee.yaml" ] && r="$r $f"; done; echo "${r# }"; }
aucune_trace() { egal "$1 : ni versionnement ni poussée" "[$(versionnees "$3")] $(poussees "$2")" "[] 0"; }
cp "$LISTE0" "$B/liste.yml"

echo "## SIGNER=1, première passe"
cas "première passe" 0 "^SIGNER : pipelines non signées tant que la liste revue n'a pas été acceptée$" "$B/W1" "$B/v1" "$B/liste.yml" "$RENDU0" SIGNER=1
egal "première passe : nouvelles signatures" "$(grep -c '^SIGNER : nouvelle signature dans builders/' "$B/W1/sortie.txt")" 2
egal "première passe : à ajouter à la liste" "$(grep -c '^SIGNER : à ajouter à politique/porte/taches.yml' "$B/W1/sortie.txt")" 2
egal "première passe : signatures versionnées" "$(versionnees "$B/v1")" "prefetch-racine-rpm construire-racine-rpm"
egal "première passe : poussées (deux tâches, tag m1b)" "$(cut -d' ' -f1 "$B/W1/poussees" | paste -sd' ')" "tekton/tasks/prefetch-racine-rpm:m1b tekton/tasks/construire-racine-rpm:m1b"
for t in prefetch-racine-rpm construire-racine-rpm; do
  egal "première passe : $t vérifiée par tkn (clé publique du banc)" "$(tkn task verify "$B/v1/$t.signee.yaml" -K "$B/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
  egal "première passe : $t, digest poussé = fichier versionné" "$(grep "^tekton/tasks/$t:m1b " "$B/W1/poussees" | cut -d' ' -f2)" "$(sha256sum < "$B/v1/$t.signee.yaml" | cut -c1-64)"
done
cp -a "$B/v1" "$B/v1-copie"

echo "## SIGNER=1, rejouée sans changement"
cas "rejouée" 0 "^SIGNER : pipelines non signées" "$B/W2" "$B/v1" "$B/liste.yml" "$RENDU0" SIGNER=1
egal "rejouée : aucune nouvelle signature" "$(grep -c '^SIGNER : nouvelle signature' "$B/W2/sortie.txt")" 0
egal "rejouée : signatures versionnées inchangées" "$(diff -r "$B/v1" "$B/v1-copie" > /dev/null && echo inchangées || echo changées)" inchangées

echo "## sans SIGNER, absentes de la liste"
cas "absentes de la liste" 1 "^KO   prefetch-racine-rpm absente de la liste revue" "$B/W3" "$B/v1" "$B/liste.yml" "$RENDU0"
echo "## sans SIGNER, rien de versionné"
cas "rien de versionné" 1 "^KO   prefetch-racine-rpm : signature versionnée absente" "$B/W4" "$B/v4" "$B/liste.yml" "$RENDU0"
aucune_trace "rien de versionné" "$B/W4" "$B/v4"

echo "## les deux listées : pipelines"
cp "$LISTE0" "$B/liste-2.yml"
for t in prefetch-racine-rpm construire-racine-rpm; do
  printf '  oci://%s/tekton/tasks/%s:\n    - ref: sha256:%s\n' "$REG" "$t" "$(sha256sum < "$B/v1/$t.signee.yaml" | cut -c1-64)" >> "$B/liste-2.yml"
done
egal "liste du banc : yq la lit, deux clés de plus" "$(( $(yq '.trusted_tasks | length' "$B/liste-2.yml") - $(yq '.trusted_tasks | length' "$LISTE0") ))" 2
cas "les deux listées" 0 "^$REG/tekton/pipelines/builder-rocky9-bootstrap@sha256:" "$B/W5" "$B/v1" "$B/liste-2.yml" "$RENDU0"
egal "listées : poussées (deux tâches, deux pipelines)" "$(cut -d' ' -f1 "$B/W5/poussees" | paste -sd' ')" \
  "tekton/tasks/prefetch-racine-rpm:m1b tekton/tasks/construire-racine-rpm:m1b tekton/pipelines/builder-mock-rocky9:m1b tekton/pipelines/builder-rocky9-bootstrap:m1b"
T5=$(tdir "$B/W5")
for p in builder-mock-rocky9 builder-rocky9-bootstrap; do
  egal "listées : $p vérifiée par tkn" "$(tkn pipeline verify "$T5/$p-signee.yaml" -K "$B/taches.pub" > /dev/null 2>&1 && echo vérifiée || echo refusée)" vérifiée
  egal "listées : $p, références = tâches listées et publier-image de la liste" \
    "$(yq '[.spec.tasks[].taskRef.params[] | select(.name == "bundle") | .value] | join(" ")' "$T5/$p-signee.yaml")" \
    "$REG/tekton/tasks/prefetch-racine-rpm@sha256:$(sha256sum < "$B/v1/prefetch-racine-rpm.signee.yaml" | cut -c1-64) $REG/tekton/tasks/construire-racine-rpm@sha256:$(sha256sum < "$B/v1/construire-racine-rpm.signee.yaml" | cut -c1-64) $REG/tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b"
done
egal "listées : seul changement relu, deux pipelines" "$(grep -c '^OK   .* : seul changement, les trois références' "$B/W5/sortie.txt")" 2

echo "## rendu altéré : refus avant toute signature"
mkdir -p "$B/rendu-altere"; cp "$RENDU0/prefetch-racine-rpm.yaml" "$RENDU0/construire-racine-rpm.yaml" "$RENDU0/pipeline-o.yaml" "$RENDU0/pipeline-b.yaml" "$B/rendu-altere/"
sed -i 's/runAsUser: 65532/runAsUser: 0/' "$B/rendu-altere/prefetch-racine-rpm.yaml"
egal "rendu altéré : une seule ligne changée" "$(diff "$RENDU0/prefetch-racine-rpm.yaml" "$B/rendu-altere/prefetch-racine-rpm.yaml" | grep -c '^>')" 1
cas "rendu altéré" 1 "^KO   prefetch-racine-rpm.yaml rendu égal à celui validé par Tekton" "$B/W6" "$B/v6" "$B/liste.yml" "$B/rendu-altere" SIGNER=1
aucune_trace "rendu altéré" "$B/W6" "$B/v6"
egal "rendu altéré : aucune signature dans \$T" "$(find "$(tdir "$B/W6")" -name '*-signee.yaml' | grep -c .)" 0

echo "## tâche refusée à l'admission"
cas "admission refusée" 1 "^KO   construire-racine-rpm admis \(code de kubectl\) : 1" "$B/W7" "$B/v7" "$B/liste.yml" "$RENDU0" SIGNER=1 BANC_REFUSEE=construire-racine-rpm
aucune_trace "admission refusée" "$B/W7" "$B/v7"

echo "## disque de Zot bas"
cas "Zot bas" 1 "^KO   octets libres sur / de sc-stockage sous 1073741824 : 1000$" "$B/W8" "$B/v8" "$B/liste.yml" "$RENDU0" SIGNER=1 BANC_LIBRE=1000
aucune_trace "Zot bas" "$B/W8" "$B/v8"

echo "# fin $(date -u +%FT%TZ) ; OK $n ; KO $k"
[ "$k" = 0 ]
