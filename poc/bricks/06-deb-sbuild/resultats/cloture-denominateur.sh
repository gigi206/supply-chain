#!/usr/bin/env bash
# shellcheck disable=SC2016  # motifs littéraux voulus entre apostrophes
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 06, clôture : complément de cloture-releve.sh (19/11/2026), en lecture seule, sans cluster. Prédictions CL7 à CL9 :
# cloture-predictions.md, commitées avant.
#   E  dénominateur : toutes les lignes qui contiennent « privileged » (casse ignorée) dans les fichiers suivis de la 06, hors
#      resultats/ et hors .md, classées une à une ; une ligne non classée est un KO.
#   F  capacités et accès à l'hôte : lignes « capabilities », SYS_ADMIN, hostPID, hostNetwork, hostPath ; chaque bloc
#      « capabilities » doit être un drop ALL ; une autre forme est un KO.
#   G  en-têtes de pod des journaux de S1 à S3 et du diagnostic, lus avec grep -a (diag-exec-releve.log est vu comme binaire
#      par grep sans -a) : tout contexte privilégié affiché est sous kata.
set -euo pipefail
G=$(git rev-parse --show-toplevel)
B=$G/poc/bricks/06-deb-sbuild
nko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; nko=$((nko + 1)); }
echo "# cloture-denominateur.sh, début $(date -u +%Y-%m-%dT%H:%M:%SZ) ; HEAD $(git -C "$G" rev-parse --short=12 HEAD)"
cd "$B"
mapfile -t F < <(git ls-files . | grep -v '^resultats/' | grep -v '\.md$')
echo "fichiers suivis lus (hors resultats/ et .md) : ${#F[@]}"

echo "## E : lignes « privileged »"
n=0
while IFS= read -r l; do
  n=$((n + 1)); f=${l%%:*}; r=${l#*:}; r=${r#*:}
  case "$f|$r" in
    s1.sh\|PRIVILEGIE=*|s2.sh\|PRIVILEGIE=*|s3.sh\|PRIVILEGIE=*|diag-exec-kata.sh\|PRIVILEGIE=*) c="définition de PRIVILEGIE (usages : cloture-releve.sh, A)" ;;
    revision-1.0.0-2.patch\|" PRIVILEGIE="*|revision-1.0.0-2-v2.patch\|" PRIVILEGIE="*) c="ligne de contexte d'un correctif (définition de s3.sh)" ;;
    builder/construire-builder.yaml\|*"privileged: true"|builder/construire-builder.signee.yaml\|*"privileged: true"|deb/construire-deb.yaml\|*"privileged: true"|deb/construire-deb.signee.yaml\|*"privileged: true") c="tâche privilégiée, Kata posé par le PipelineRun (A)" ;;
    s4d.sh\|*"securityContext: {privileged: true"*) c="pod d'essai privilégié sous Kata (A)" ;;
    s5.sh\|*'securityContext: (if $k == "kata" then {privileged: true'*) c="pod d'essai privilégié seulement sous Kata (A)" ;;
    s4d.sh\|*'.securityContext.privileged | tostring'*) c="lecture du contexte d'une tâche (contrôle)" ;;
    s5.sh\|*'refus de Pod Security restricted (privileged)'*|s5.sh\|*'violates PodSecurity "restricted:latest".*privileged'*) c="mesure du refus N7 (contrôle)" ;;
    s6b.sh\|*unprivileged_userns_clone*) c="lecture d'un réglage du noyau de sc-replay (pas un pod)" ;;
    *) c="" ;;
  esac
  if [ -n "$c" ]; then ok "$f:$(cut -d: -f2 <<<"$l") : $c"; else ko "non classée : ${l:0:160}"; fi
done < <(grep -n -i -a 'privileged' "${F[@]}")
echo "lignes « privileged » : $n, dans $(grep -l -i -a 'privileged' "${F[@]}" | wc -l) fichiers"

echo "## F : capacités et accès à l'hôte"
n=0
while IFS= read -r l; do
  n=$((n + 1)); f=${l%%:*}; i=$(cut -d: -f2 <<<"$l")
  case "$l" in
    *'"capabilities": {"drop": ["ALL"]}'*|*'capabilities: {drop: ["ALL"]}'*|*'capabilities: {drop: [ALL]}'*) ok "$f:$i : drop ALL" ;;
    *capabilities:) s=$(sed -n "$((i + 1)),$((i + 2))p" "$f" | tr -s ' ' | tr '\n' ' ')
      case "$s" in " drop: [ALL] "*|" drop: - ALL "*) ok "$f:$i : drop ALL (bloc YAML)" ;; *) ko "$f:$i : bloc capabilities autre : $s" ;; esac ;;
    *) ko "autre forme : ${l:0:160}" ;;
  esac
done < <(grep -n -i -a 'capabilit\|SYS_ADMIN\|hostPID\|hostNetwork\|hostPath' "${F[@]}")
echo "lignes de capacités ou d'accès à l'hôte : $n"

echo "## G : journaux archivés, grep -a"
cd "$B/resultats"
np=0; nk=0; nr=0; nt=0
while IFS= read -r l; do
  nt=$((nt + 1))
  case "$l" in *'"privileged":true'*) np=$((np + 1)); case "$l" in *"runtimeClassName kata"*) ;; *) ko "pod privilégié hors kata : $l" ;; esac ;; esac
  case "$l" in *"runtimeClassName kata"*|*"(kata,"*) nk=$((nk + 1)) ;; *"runtimeClassName -"*|*"(-,"*) nr=$((nr + 1)) ;; esac
done < <(grep -a -h '^### ' s1*.log s2*.log s3*.log diag-exec-*.log | grep -E 'runtimeClassName|^### diag-exec-kata \((kata|-),')
echo "en-têtes de pod : $nt, dont $nk sous kata et $nr sans RuntimeClass ; contexte privilégié affiché : $np"
echo "diag-exec-releve.log, lu avec -a : $(grep -a -c '^### ' diag-exec-releve.log) en-tête(s) : $(grep -a -h '^### ' diag-exec-releve.log | sed -E 's/ : prêt.*//' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ) ; KO $nko"
exit $((nko > 0))
