#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, M5b sous l'option C : banc de m5b-republier.sh sur un registre crane local (préparé à sec le 20/11/2026).
#   A  outils ; adresse loopback ; le script n'écrit ni clé ni signature ; script sourcé (sa partie principale ne tourne pas) avec
#      CONFIANCE_DIR dans le dossier du banc ; REG_HOTE remplacé par l'adresse locale et contrôlé avant toute lecture ou
#      poussée ; auth_zot (configuration vide, aucune authentification) et libre_zot (valeur fixe) remplacées.
#   F  manifestes des 9 références des contenus signés qui ne sont pas poussées par le script, lus dans Zot (lecture anonyme,
#      octets tels quels, sha256 égal au digest), puis déposés par digest dans le registre local, par lots, au fil des cas, sans
#      leurs couches (le registre local ne les exige pas).
#   N  cas nominaux dans l'ordre du rejeu (tag banc) : taches, pipeline_fermeture, pipeline_construction, puis taches relancée.
#   K  cas refusés : TAG refusé (script exécuté, arrêt avant tout accès), références absentes (trois étapes), fuseau UTC et
#      SOURCE_DATE_EPOCH posée (garde d'entrée), fichier altéré, tag déjà occupé, digest différent à la poussée (fuseau UTC,
#      poussées appelées sans la garde d'entrée).
# Non couvert : Zot (TLS, authentification, compte poc-ecriture), garde de place réelle, journal déjà présent, Tekton,
# admission par Trusted Resources, Kyverno.
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/05-rpm-mock/resultats/m5b-republier-banc.sh <dossier-neuf> [adresse]
# shellcheck disable=SC2034,SC2154,SC2030,SC2031  # variables partagées avec le script sourcé et ses sous-shells
set -uo pipefail
export LC_ALL=C
B=$1
ADR=${2:-127.0.0.1:5912}
RACINE=$PWD
D05=$RACINE/poc/bricks/05-rpm-mock
SCRIPT=$D05/m5b-republier.sh
CA_ZOT=$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt
ZOT=192.168.161.13:5000
n=0; k=0
egal() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; n=$((n + 1)); else echo "KO   $1 : $2 (attendu : $3)"; k=$((k + 1)); fi; }
case $ADR in 127.0.0.1:*) ;; *) echo "adresse hors loopback : $ADR" >&2; exit 2 ;; esac
[ ! -e "$B" ] || { echo "dossier déjà présent : $B" >&2; exit 2; }
! curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 || { echo "adresse déjà prise : $ADR" >&2; exit 2; }
echo "# m5b-republier-banc.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$RACINE" rev-parse --short=8 HEAD)"
echo "m5b-republier.sh : sha256 $(sha256sum < "$SCRIPT" | cut -c1-64)"

echo "## A  outils, script, environnement du banc"
egal "A1 tkn (client)" "$(tkn version --component client)" 0.46.2
egal "A2 crane" "$(crane version)" 0.20.6
egal "A3 script : mentions de taches.key" "$(grep -c 'taches\.key' "$SCRIPT")" 0
egal "A4 script : signatures (tkn task sign, tkn pipeline sign)" "$(grep -c -E 'tkn (task|pipeline) sign' "$SCRIPT")" 0
egal "A5 script : option --ctime" "$(grep -c -e '--ctime' "$SCRIPT")" 0
egal "A6 script : export TZ=Europe/Paris" "$(grep -c '^export TZ=Europe/Paris ' "$SCRIPT")" 1
egal "A7 script : unset SOURCE_DATE_EPOCH" "$(grep -c '^unset SOURCE_DATE_EPOCH ' "$SCRIPT")" 1
mkdir -p "$B/f" "$B/disque" "$B/resultats"
# K1 : script exécuté (non sourcé) avec un TAG refusé ; il s'arrête avant tout accès réseau
for t in m4c ''; do
  rc=0; o=$(CONFIANCE_DIR=$B/o-k1 TAG=$t bash "$SCRIPT" taches 2>&1) || rc=$?
  egal "K1 TAG « $t » : code" "$rc" 2
  egal "K1 TAG « $t » : message" "$(grep -c -E '^(tag refusé|TAG absent ou invalide)' <<< "$o")" 1
done
# shellcheck disable=SC1090  # script de la brique, sourcé pour ses fonctions
CONFIANCE_DIR=$B/o TAG=banc . "$SCRIPT"
set +e   # posé par le script sourcé ; chaque cas le repose dans son sous-shell
REG_HOTE=$ADR
R=$B/resultats
auth_zot() { echo '{}' > "$1"; echo "banc : auth_zot remplacée (configuration vide)"; }
libre_zot() { echo 99999999999; }
egal "A8 REG_HOTE du banc, loopback" "${REG_HOTE%%:*}" 127.0.0.1
egal "A9 T dans le dossier du banc" "$(case $T in "$B"/*) echo oui ;; *) echo non ;; esac)" oui
egal "A10 P dans le dossier du banc" "$(case $P in "$B"/*) echo oui ;; *) echo non ;; esac)" oui
egal "A11 TZ après chargement" "$TZ" Europe/Paris
egal "A12 SOURCE_DATE_EPOCH après chargement" "${SOURCE_DATE_EPOCH-absente}" absente

echo "## F  manifestes lus dans Zot (lecture anonyme)"
echo '{}' > "$B/f/config.json"
FIXTURES="builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae t
plateforme/outils-horodatage@sha256:c7bebae2bd33e57792988b8ba215536dd9360a9871ec0bdf807ee94d4c1f4ca0 t
plateforme/outils-prefetch@sha256:68e0ae705de5a8f993f168d8252b3218d7d3ed76e704cf24d4414006aea7b8cc t
builds/builders/rocky9-bootstrap@sha256:6de899ac5da41852c5d8518a t-f
tekton/tasks/publier-fermeture@sha256:7fa92ad3e4adb0d4b9bc4209ee t-f
builds/fermetures/sample-app-rpm@sha256:0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f c
builds/fermetures/sample-app-sources@sha256:50dc73f72d04be852a04 c
entrees/sample-app/packaging-rpm@sha256:333b7322290ab5edd8598990 c
tekton/tasks/publier-image@sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b c"
complet() { # préfixe de référence : référence complète lue dans les contenus signés (une seule)
  cat "$D05"/fermeture/*.m1b.signee.yaml "$D05"/construction/*.signee.yaml | grep -v 'tekton.dev/signature:' \
    | grep -o "sc-stockage.poc.test:5000/$1[0-9a-f]*" | sort -u | sed 's#^sc-stockage.poc.test:5000/##'
}
declare -A LOT
while read -r p l; do
  r=$(complet "$p")
  egal "F1 ${p%@*} : référence complète unique" "$(grep -c . <<< "$r")" 1
  i=${#LOT[@]}
  DOCKER_CONFIG=$B/f SSL_CERT_FILE=$CA_ZOT crane manifest "$ZOT/$r" > "$B/f/$i.json" 2> "$B/f/$i.err"
  egal "F2 ${r%@*} : sha256 du manifeste lu = digest" "sha256:$(sha256sum < "$B/f/$i.json" | cut -c1-64)" "${r#*@}"
  LOT[$r]="$l $i"
done <<< "$FIXTURES"
deposer() { # lot : manifestes du lot déposés par digest dans le registre local
  local r l i c
  for r in "${!LOT[@]}"; do
    read -r l i <<< "${LOT[$r]}"
    case " $l " in *" $1 "*) ;; *) continue ;; esac
    c=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: $(jq -r .mediaType "$B/f/$i.json")" \
      --data-binary "@$B/f/$i.json" "http://$ADR/v2/${r%@*}/manifests/${r#*@}")
    egal "F3 lot $1 : ${r%@*} déposé (code HTTP)" "$c" 201
  done
}

crane registry serve --address "$ADR" --disk "$B/disque" > "$B/serve.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null; wait $srv 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -fsS "http://$ADR/v2/" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://$ADR/v2/" >/dev/null && echo "registre local : prêt (http, $ADR)"

cas() { # nom tag commande… : sous-shell (set -e, T du tag), sortie dans $B/cas-<nom>.out, code renvoyé
  local c=$1 t=$2; shift 2
  ( set -e; TAG=$t; T=$W/m5b-republier-$t-05; mkdir -p "$T/auth"; "$@" ) > "$B/cas-$c.out" 2>&1
}
lignes() { grep -c -E -- "$2" "$B/cas-$1.out"; }   # cas motif
local_tag() { DOCKER_CONFIG=$B/f crane digest "$ADR/$1" 2>/dev/null || echo absent; }   # dépôt:tag
A_PREF=sha256:b9bbeba3e8c62113431cdb88aa74afe76bab13a28ab548a5b5ae6ffed22675dc
A_CONS=sha256:ca03f18908d0b5e73edc57ecf9610513e2907267ce1da2d9f41fd36b969289c5
A_PREP=sha256:2f65f3903e98caa9944ab3fee4b67585b15d67ad477ff48a8487e8e86af5526f
A_PF=sha256:61814acd6f15f0fde07f9f701f2e8cfd4324218caf2df9e1befcf182495ca60c
A_PC=sha256:7d361cb1d5ea9b7994727f839bc4365a29e4ebdc7948fceff4176b4a371abd6a

echo "## K  cas refusés, avant le lot t"
cas k2 banc-k2 etape_taches; egal "K2 taches sans les images : code" "$?" 1
egal "K2 KO de référence absente" "$(lignes k2 '^KO   référence du contenu signé présente dans Zot : builds/builders/mock-rocky9@')" 1
egal "K2 poussées" "$(lignes k2 '^poussée ')" 0
egal "K2 prefetch-rpm:banc-k2" "$(local_tag tekton/tasks/prefetch-rpm:banc-k2)" absent
deposer t
echo "## K  cas refusés, lot t déposé"
TZ=UTC cas k3 banc-k3 etape_taches; egal "K3 TZ=UTC : code" "$?" 1
egal "K3 KO de fuseau" "$(lignes k3 '^KO   fuseau : décalage de l.époque 0 \(TZ=UTC\) : \+00:00')" 1
egal "K3 poussées" "$(lignes k3 '^poussée ')" 0
SOURCE_DATE_EPOCH=0 cas k4 banc-k4 etape_taches; egal "K4 SOURCE_DATE_EPOCH=0 : code" "$?" 1
egal "K4 KO de SOURCE_DATE_EPOCH" "$(lignes k4 '^KO   SOURCE_DATE_EPOCH : 0')" 1
egal "K4 poussées" "$(lignes k4 '^poussée ')" 0
mkdir -p "$B/copie/fermeture" "$B/copie/construction"
cp "$D05/fermeture/prefetch-rpm.m1b.signee.yaml" "$B/copie/fermeture/"
cp "$D05/construction/construire-rpm.m1b.signee.yaml" "$D05/construction/preparer-rpm.signee.yaml" "$B/copie/construction/"
echo '# banc : ligne ajoutée' >> "$B/copie/construction/preparer-rpm.signee.yaml"
h05_reel=$h05
h05=$B/copie cas k5 banc-k5 etape_taches; egal "K5 preparer-rpm altéré (troisième fichier) : code" "$?" 1
egal "K5 h05 du banc rétabli" "$h05" "$h05_reel"
egal "K5 deux premiers fichiers contrôlés en entier (tag lu)" "$(lignes k5 '^OK   tekton/tasks/[a-z-]+:banc-k5 avant la poussée : absent')" 2
egal "K5 KO de sha256" "$(lignes k5 '^KO   sha256 du fichier')" 1
egal "K5 poussées" "$(lignes k5 '^poussée ')" 0
egal "K5 prefetch-rpm:banc-k5" "$(local_tag tekton/tasks/prefetch-rpm:banc-k5)" absent
i=$(read -r _ i <<< "${LOT[builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae]}"; echo "$i")
c=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: $(jq -r .mediaType "$B/f/$i.json")" \
  --data-binary "@$B/f/$i.json" "http://$ADR/v2/tekton/tasks/construire-rpm/manifests/banc-k6")
egal "K6 construire-rpm:banc-k6 occupé par un autre manifeste (code HTTP)" "$c" 201
cas k6 banc-k6 etape_taches; egal "K6 tag occupé : code" "$?" 1
egal "K6 KO de tag occupé" "$(lignes k6 '^KO   tekton/tasks/construire-rpm:banc-k6 déjà sur ')" 1
egal "K6 poussées" "$(lignes k6 '^poussée ')" 0
egal "K6 prefetch-rpm:banc-k6" "$(local_tag tekton/tasks/prefetch-rpm:banc-k6)" absent
egal "K6 construire-rpm:banc-k6 non déplacé" "$(local_tag tekton/tasks/construire-rpm:banc-k6)" "$(sha256sum < "$B/f/$i.json" | sed 's/^/sha256:/; s/ .*//')"
pousser_k7() { mkdir -p "$T/auth/docker" && echo '{}' > "$T/auth/docker/config.json" && pousser_tout "$TACHES_M1B"; }
TZ=UTC cas k7 banc-k7 pousser_k7; egal "K7 poussées sous TZ=UTC, sans garde d'entrée : code" "$?" 1
egal "K7 KO de digest" "$(lignes k7 '^KO   fermeture/prefetch-rpm.m1b.signee.yaml poussé, digest')" 1
egal "K7 poussées" "$(lignes k7 '^poussée ')" 1
d=$(local_tag tekton/tasks/prefetch-rpm:banc-k7)
egal "K7 prefetch-rpm:banc-k7 poussé, autre digest" "$(case $d in absent|"$A_PREF") echo "$d" ;; sha256:*) echo autre ;; esac)" autre
egal "K7 construire-rpm:banc-k7" "$(local_tag tekton/tasks/construire-rpm:banc-k7)" absent

echo "## N  cas nominaux (tag banc)"
cas n1 banc etape_taches; egal "N1 taches : code" "$?" 0
egal "N1 poussées" "$(lignes n1 '^poussées : 3$')" 1
egal "N1 prefetch-rpm:banc" "$(local_tag tekton/tasks/prefetch-rpm:banc)" "$A_PREF"
egal "N1 construire-rpm:banc" "$(local_tag tekton/tasks/construire-rpm:banc)" "$A_CONS"
egal "N1 preparer-rpm:banc" "$(local_tag tekton/tasks/preparer-rpm:banc)" "$A_PREP"
egal "N1 références contrôlées (1, 1, 2)" "$(grep '^références par digest du contenu signé' "$B/cas-n1.out" | cut -d: -f2 | paste -s -d,)" " 1, 1, 2"
cas k8 banc etape_pipeline_fermeture; egal "K8 pipeline_fermeture avant le lot t-f : code" "$?" 1
egal "K8 KO de référence absente" "$(lignes k8 '^KO   référence du contenu signé présente dans Zot : ')" 1
egal "K8 poussées" "$(lignes k8 '^poussée ')" 0
deposer t-f
cas n2 banc etape_pipeline_fermeture; egal "N2 pipeline_fermeture : code" "$?" 0
egal "N2 poussées" "$(lignes n2 '^poussées : 1$')" 1
egal "N2 prefetch-rpm-sample-app:banc" "$(local_tag tekton/pipelines/prefetch-rpm-sample-app:banc)" "$A_PF"
egal "N2 références contrôlées" "$(grep '^références par digest du contenu signé' "$B/cas-n2.out" | cut -d: -f2)" " 3"
cas k9 banc etape_pipeline_construction; egal "K9 pipeline_construction avant le lot c : code" "$?" 1
egal "K9 KO de référence absente" "$(lignes k9 '^KO   référence du contenu signé présente dans Zot : ')" 1
egal "K9 poussées" "$(lignes k9 '^poussée ')" 0
deposer c
cas n3 banc etape_pipeline_construction; egal "N3 pipeline_construction : code" "$?" 0
egal "N3 poussées" "$(lignes n3 '^poussées : 1$')" 1
egal "N3 sample-app-rpm:banc" "$(local_tag tekton/pipelines/sample-app-rpm:banc)" "$A_PC"
egal "N3 références contrôlées" "$(grep '^références par digest du contenu signé' "$B/cas-n3.out" | cut -d: -f2)" " 6"
cas n4 banc etape_taches; egal "N4 taches relancée sur les mêmes tags : code" "$?" 0
egal "N4 tags lus avant, déjà sur l'attendu" "$(lignes n4 '^OK   tekton/tasks/[a-z-]+:banc avant la poussée : sha256:')" 3
egal "N4 poussées" "$(lignes n4 '^poussées : 3$')" 1
for x in tekton/tasks/prefetch-rpm tekton/tasks/construire-rpm tekton/tasks/preparer-rpm tekton/pipelines/prefetch-rpm-sample-app tekton/pipelines/sample-app-rpm; do
  egal "N5 $x:banc, date de création" "$(DOCKER_CONFIG=$B/f crane config "$ADR/$x:banc" 2>/dev/null | jq -r '.created // "absente"')" 1970-01-01T01:00:00+01:00
done
egal "N6 authentification des poussées (configuration du banc)" "$(cat "$W/m5b-republier-banc-05/auth/docker/config.json")" '{}'
echo "dépôts du registre local : $(crane catalog "$ADR" | paste -s -d' ')"
echo "place du registre local : $(du -sk "$B/disque" | cut -f1) Kio"
for c in k2 k3 k4 k5 k6 k7 n1 k8 n2 k9 n3 n4; do
  echo "--- sortie du cas $c"
  sed -E 's/(sha256:[0-9a-f]{12})[0-9a-f]{52}/\1…/g' "$B/cas-$c.out"
done
echo "bilan : $n OK, $k KO"
[ "$k" = 0 ]
