#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, M5b sous l'option C : banc hors Zot et hors cluster de la republication depuis les signatures versionnées (préparé à
# sec le 20/11/2026). Hypothèse de l'estimation de M5b : un même fichier signé, poussé par bundle (commun.sh), redonne le digest de
# la liste revue, sans nouvelle signature.
#   A  outils et environnement : versions de tkn et crane, SOURCE_DATE_EPOCH retirée (tkn bundle push la lit), adresse loopback.
#   B  bundle extrait par texte de commun.sh (commun.sh n'est pas sourcé : son REG_HOTE est le vrai Zot) ; T et DOCKER_CONFIG
#      dans le dossier du banc (config.json vide, aucune authentification), P sans certificat (registre en http).
#   C  chacune des 9 signatures versionnées poussée sous son chemin de dépôt réel et le tag m1b, puis sous le tag banc2 ; digest
#      comparé à l'attendu lu dans le dépôt : taches.yml de la 08 pour les 7 tâches (référence de même préfixe sous le même dépôt),
#      lignes PIPELINE_REF de m1b-fermeture.sh et m1b-construction.sh pour les 2 pipelines ; date de création de la configuration.
# Aucune clé n'est lue ni utilisée : rien n'est signé.
# Non couvert : Zot (TLS, authentification, compte poc-ecriture), Tekton, admission par Trusted Resources, Kyverno.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m5b-republication-banc.sh <dossier-neuf> [adresse]
set -uo pipefail
export LC_ALL=C
unset SOURCE_DATE_EPOCH
B=$1
ADR=${2:-127.0.0.1:5909}
RACINE=$PWD
D05=$RACINE/poc/bricks/05-rpm-mock
COMMUN=$RACINE/poc/bricks/08-trust-plane/commun.sh
LISTE=$RACINE/poc/bricks/08-trust-plane/politique/porte/taches.yml
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
case $ADR in 127.0.0.1:*) ;; *) echo "adresse hors loopback : $ADR" >&2; exit 2 ;; esac
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
! curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 || { echo "adresse déjà prise : $ADR" >&2; exit 2; }
echo "# m5b-republication-banc.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$RACINE" rev-parse --short=8 HEAD)"

echo "## A  outils et environnement"
egal "A1 tkn (client)" "$(tkn version --component client)" 0.46.2
egal "A2 crane" "$(crane version)" 0.20.6
egal "A3 SOURCE_DATE_EPOCH" "${SOURCE_DATE_EPOCH-absente}" absente
egal "A4 adresse du registre local" "${ADR%%:*}" 127.0.0.1

echo "## B  fonction bundle extraite de commun.sh"
mkdir -p "$B/disque" "$B/t/auth/docker" "$B/p"
echo '{}' > "$B/t/auth/docker/config.json"
python3 -I - "$COMMUN" "$B/bundle.sh" <<'PY'
import sys
n = open(sys.argv[1], encoding='utf-8').read()
i = n.index('\nbundle() {') + 1; j = n.index('\n}\n', i) + 3
open(sys.argv[2], 'w', encoding='utf-8').write(n[i:j])
PY
echo "commun.sh : sha256 $(sha256sum < "$COMMUN" | cut -c1-16)… ; fonction extraite : $(wc -l < "$B/bundle.sh") lignes"
egal "B1 bundle contenue telle quelle dans commun.sh" "$(python3 -I -c 'import sys; print(open(sys.argv[2]).read() in open(sys.argv[1]).read())' "$COMMUN" "$B/bundle.sh")" True
# shellcheck disable=SC2016  # motifs littéraux cherchés dans la fonction extraite
egal "B2 bundle : tkn bundle push vers REG_HOTE" "$(grep -c -F 'tkn bundle push "$REG_HOTE/$2:${3:-essai}" -f "$1"' "$B/bundle.sh")" 1
# shellcheck disable=SC2016  # motif littéral
egal "B3 bundle : digest lu par crane" "$(grep -c -F 'crane digest "$REG_HOTE/$2:${3:-essai}"' "$B/bundle.sh")" 1
egal "B4 bundle : aucune option --ctime" "$(grep -c -e '--ctime' "$B/bundle.sh")" 0
egal "B5 config.json du banc" "$(cat "$B/t/auth/docker/config.json")" '{}'

crane registry serve --address "$ADR" --disk "$B/disque" > "$B/serve.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null; wait $srv 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://$ADR/v2/" >/dev/null && echo "registre local : prêt (http, $ADR)"

attendu_liste() { # dépôt préfixe : référence de taches.yml sous ce dépôt qui commence par ce préfixe (une seule)
  awk -v d="oci://sc-stockage.poc.test:5000/$1:" -v p="sha256:$2" '$1 == d {b = 1; next} b && /^  [^ ]/ {b = 0}
    b && $1 == "-" && $2 == "ref:" && index($3, p) == 1 {print $3}' "$LISTE"
}
attendu_pipeline() { # script dépôt : digest de la ligne PIPELINE_REF= du script
  sed -n "s#^PIPELINE_REF=\$REG/$2@\(sha256:[0-9a-f]\{64\}\) .*#\1#p" "$D05/$1"
}
pousser() { # fichier dépôt tag : digest renvoyé par bundle (sous-shell : T, P et REG_HOTE du banc seulement)
  ( set -uo pipefail
    # shellcheck disable=SC2034  # lues par bundle, chargée par la ligne suivante
    T=$B/t P=$B/p REG_HOTE=$ADR
    # shellcheck source=/dev/null  # fonction extraite à l'étape B
    . "$B/bundle.sh"
    bundle "$1" "$2" "$3" )
}

echo "## C  republication des 9 signatures versionnées (tags m1b puis banc2)"
t0=$(date +%s)
while read -r f depot attendu; do
  egal "C0 $f : attendu unique dans le dépôt" "$(printf '%s\n' "$attendu" | grep -c '^sha256:[0-9a-f]\{64\}$')" 1
  d1=$(pousser "$D05/$f" "$depot" m1b)
  egal "C1 $f ($depot, tag m1b)" "$d1" "$attendu"
  d2=$(pousser "$D05/$f" "$depot" banc2)
  egal "C2 $f ($depot, tag banc2)" "$d2" "$attendu"
  egal "C3 $f : date de création de la configuration" "$(crane config "$ADR/$depot@$d1" 2>/dev/null | jq -r '.created // "absente"')" 1970-01-01T00:00:00Z
done < <(
  for l in \
    "builders/prefetch-racine-rpm.signee.yaml tekton/tasks/prefetch-racine-rpm 16a32993" \
    "builders/construire-racine-rpm.signee.yaml tekton/tasks/construire-racine-rpm bdde08ed" \
    "fermeture/prefetch-rpm.signee.yaml tekton/tasks/prefetch-rpm 9afe09db" \
    "fermeture/prefetch-rpm.m1b.signee.yaml tekton/tasks/prefetch-rpm b9bbeba3" \
    "construction/construire-rpm.signee.yaml tekton/tasks/construire-rpm d7f01398" \
    "construction/construire-rpm.m1b.signee.yaml tekton/tasks/construire-rpm ca03f189" \
    "construction/preparer-rpm.signee.yaml tekton/tasks/preparer-rpm 2f65f390"; do
    # shellcheck disable=SC2086  # découpage voulu : fichier, dépôt, préfixe
    set -- $l; echo "$1 $2 $(attendu_liste "$2" "$3" | paste -s -d,)"
  done
  echo "fermeture/prefetch-rpm-sample-app.m1b.signee.yaml tekton/pipelines/prefetch-rpm-sample-app $(attendu_pipeline m1b-fermeture.sh tekton/pipelines/prefetch-rpm-sample-app)"
  echo "construction/sample-app-rpm.m1b.signee.yaml tekton/pipelines/sample-app-rpm $(attendu_pipeline m1b-construction.sh tekton/pipelines/sample-app-rpm)"
)
echo "durée des poussées : $(($(date +%s) - t0)) s ; place du registre local : $(du -sk "$B/disque" | cut -f1) Kio"
echo "dépôts du registre local : $(crane catalog "$ADR" | paste -s -d' ')"
echo "bilan : $n OK, $k KO"
[ "$k" = 0 ]
