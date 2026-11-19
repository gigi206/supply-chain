#!/usr/bin/env bash
# shellcheck disable=SC2015,SC1091  # ok et ko n échouent jamais ; commun.sh chargé par un chemin calculé
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
# Brique 05, jalon M1b : cas refusés de prefetch-racine-rpm, dans des pods d'essai du cluster, préparés à sec le 19/11/2026.
# Prédictions PX1 à PX5 : m1b-predictions.md, commitées avant tout lancement. Le script de prefetch est celui du bootstrap que prealables
# a rendu sous m1bt3 (script-pb.sh 912520ea…), relu au sha256 ; chaque cas change une seule ligne (contrôlée par diff), et le motif
# du refus est confronté à la garde visée. Un pod runc par cas, comme essai_prefetch (image de l'amorce, UID 65532, label
# prefetch-rpm, sortie posée le 16/11), avec la sortie sur un emptyDir au lieu du PVC ; pods retirés. Ni politique, ni label neufs,
# ni signature, ni écriture dans Zot (lectures : vault 9.7 et Zot). Accord permanent du 18/11 pour les pods d'essai.
#   PX1 témoin, script tel quel ; PX2 repomd.xml de baseos97 fixé faux ; PX3 autre manifeste (ed654c69, l'amorce, dont la couche est
#   99c753a8) avec la couche fixée 812c4412 ; PX4 bon manifeste (ee90dc0e) avec une couche fausse (99c753a8)
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- bash poc/bricks/05-rpm-mock/resultats/m1b-refus-prefetch.sh < /dev/null > poc/bricks/05-rpm-mock/resultats/m1b-refus-prefetch.log 2>&1
set -euo pipefail
export LC_ALL=C
umask 022
G=$(git rev-parse --show-toplevel)
here=$G/poc/bricks/08-trust-plane   # commun.sh attend le répertoire de l appelant
. "$here/commun.sh"   # W, REG
N=${PREFIXE:-m1brp}   # une relance se fait sous un autre préfixe
S3=$W/m1bt3-05/script-pb.sh   # rendu de prealables sous m1bt3 : lecture seule
T=$W/$N-05
[ ! -e "$T" ] || { echo "KO   $T existe (relancer sous un autre préfixe)" >&2; exit 1; }
mkdir -p "$T"
AMORCE=$REG/amont/rockylinux/rockylinux@sha256:ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d
M_BOOT=ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2; C_BOOT=812c44127102f257d376d2c571aa5be68fbe4e46316a772cfeb9ac359f1adf09
M_AMORCE=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d; C_AMORCE=99c753a880cc03bbe9da8bf6e354c8ba2d99f19058e87b8a55b6487ffcf52f8a
R97=fa6d50542ea30eff797235527b46f0d21b7ec4159980f64580b4797589055258; R98=abac8b17ece74b6f242af937c8143f2e76537eb6a82bdc876682bac38b1af163
GARDE_M="manifeste de base : image OCI à une seule couche, la couche fixée, attendue"
nko=0
ok() { echo "OK   $*"; }
ko() { echo "KO   $*"; nko=$((nko + 1)); }
arret() { echo "KO   $*" >&2; exit 1; }
filtre() { sed -E -e 's/<[^>]*@[^>]*>/<adresse retirée>/g' -e '/jeton\|token/I c\[ligne masquée : motif jeton|token]'; }
echo "# m1b-refus-prefetch.sh, début $(date -u +%FT%TZ) ; HEAD $(git -C "$G" rev-parse --short=12 HEAD)"
[ "$(sha256sum < "$S3" | cut -c1-64)" = 912520eae2810d581fe229a29215bc2c60744a738125364954721ff31aa73c0a ] && ok "script-pb.sh rendu sous m1bt3 : sha256 912520eae2810d58…" || arret "script-pb.sh : sha256 inattendu"
t=$(kubectl get ciliumnetworkpolicy -n builds prefetch-rpm-sortie -o json < /dev/null | jq -c '.spec.endpointSelector')
[ "$t" = '{"matchLabels":{"tekton.dev/task":"prefetch-rpm"}}' ] && ok "prefetch-rpm-sortie : sélecteur $t" || arret "prefetch-rpm-sortie : sélecteur $t"

script_cas() { # cas ancienne nouvelle : une seule ligne changée, ou tel quel si ancienne = -
  if [ "$2" = - ]; then cp "$S3" "$T/script-$1.sh"; return; fi
  [ "$(grep -cxF "$2" "$S3")" = 1 ] || arret "ligne absente ou en double : ${2:0:80}"
  awk -v a="$2" -v n="$3" '$0 == a {print n; next} {print}' "$S3" > "$T/script-$1.sh"
  [ "$(diff "$S3" "$T/script-$1.sh" | grep -c '^[<>]')" = 2 ] || arret "script du cas $1 : plus d'une ligne changée"
  echo "     script : « ${2:0:110}… » devient « ${3:0:110}… »"
}
pod_json() { # nom
  jq -n --arg n "$1" --arg i "$AMORCE" --arg j "$N" \
    --argjson res "$(yq -o=json -I=0 '.spec.steps[0].resources' "$W/m1bt3-05/prefetch-racine-rpm.yaml")" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": $j, "tekton.dev/task": "prefetch-rpm"}},
    spec: {automountServiceAccountToken: false, enableServiceLinks: false, restartPolicy: "Never",
      nodeSelector: {zone: "build"}, tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {}}, {name: "tmp", emptyDir: {}}, {name: "ca-poc", configMap: {name: "ca-poc"}}],
      containers: [{name: "essai", image: $i, command: ["sleep", "3600"],
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}, env: [{name: "HOME", value: "/tmp"}],
        resources: $res,
        volumeMounts: [{name: "w", mountPath: "/workspace/sortie"}, {name: "tmp", mountPath: "/tmp"},
          {name: "ca-poc", mountPath: "/etc/ca-poc", readOnly: true}]}]}}' > "$T/$1.json"
}
cas() { # cas ancienne nouvelle attendu(0|motif) [ligne d'assertion attendue] : pod, script, verdict, retrait
  local p=$N-$1 rc=0 k
  echo "## cas $1 : début $(date -u +%FT%TZ)"
  [ -z "$(kubectl get pod -n builds --field-selector "metadata.name=$p" -o name < /dev/null 2> /dev/null)" ] || arret "pod $p déjà présent"
  script_cas "$1" "$2" "$3"
  pod_json "$p"
  kubectl create --dry-run=server -o name -f "$T/$p.json" < /dev/null > /dev/null 2>&1 || arret "pod $p refusé à blanc"
  kubectl create -f "$T/$p.json" < /dev/null > /dev/null
  kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null 2>&1 || { kubectl delete pod -n builds "$p" --wait=true < /dev/null > /dev/null || true; arret "pod $p non prêt"; }
  echo "     pod $p prêt : nœud $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.nodeName}' < /dev/null), runtimeClassName « $(kubectl get pod -n builds "$p" -o jsonpath='{.spec.runtimeClassName}' < /dev/null) »"
  kubectl exec -i -n builds "$p" -- sh -c 'cat > /tmp/script.sh' < "$T/script-$1.sh"
  [ "$(kubectl exec -n builds "$p" -- sha256sum /tmp/script.sh < /dev/null | cut -c1-64)" = "$(sha256sum < "$T/script-$1.sh" | cut -c1-64)" ] || arret "copie du script dans $p"
  kubectl exec -n builds "$p" -- bash /tmp/script.sh < /dev/null 2>&1 | filtre > "$T/$1.log" || rc=$?
  sed 's/^/        /' "$T/$1.log"
  k=$(grep -c '^KO   ' "$T/$1.log" || true)
  local base sortie
  base=$(kubectl exec -n builds "$p" -- sh -c 'test -s /tmp/resultat-base && cat /tmp/resultat-base || echo absent' < /dev/null)
  sortie=$(kubectl exec -n builds "$p" -- sh -c 'test -e /workspace/sortie/couche.tar.gz && echo présente || echo absente' < /dev/null)
  echo "     code $rc ; lignes KO $k ; BASE_ARTIFACT_INPUTS : $base ; couche.tar.gz : $sortie"
  if [ "$4" = 0 ]; then
    [ "$rc" = 0 ] && [ "$k" = 0 ] && [ "$base" = "{\"uri\":\"oci://sc-stockage.poc.test:5000/amont/rockylinux/rockylinux\",\"digest\":\"sha256:$M_BOOT\"}" ] && [ "$sortie" = présente ] \
      && ok "$1 : témoin, code 0, BASE_ARTIFACT_INPUTS ee90dc0e…, couche écrite" || ko "$1 : témoin en échec"
  else
    [ "$rc" != 0 ] && [ "$k" = 1 ] && [ "$(grep '^KO   ' "$T/$1.log")" = "KO   $4" ] && ok "$1 : code $rc, refus « $4 »" || ko "$1 : code $rc, $k ligne(s) KO, dernière : $(grep '^KO   ' "$T/$1.log" | tail -n 1 | cut -c1-160)"
    [ "$base" = absent ] && [ "$sortie" = absente ] && ok "$1 : ni BASE_ARTIFACT_INPUTS ni couche.tar.gz" || ko "$1 : une sortie a été écrite malgré le refus"
    if [ -n "${5:-}" ]; then grep -qxF "$5" "$T/$1.log" && ok "$1 : assertion « $5 »" || ko "$1 : assertion « $5 » absente"; fi
  fi
  kubectl delete pod -n builds "$p" --wait=true --timeout=180s < /dev/null > /dev/null && ok "$1 : pod $p retiré" || ko "$1 : retrait du pod $p"
  echo "## cas $1 : fin $(date -u +%FT%TZ)"
}

L97="baseos97 https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os $R97 RPM-GPG-KEY-Rocky-9"
LC="COUCHE='amont/rockylinux/rockylinux $M_BOOT $C_BOOT'"
cas temoin - - 0
cas repomd "$L97" "${L97/$R97/$R98}" "baseos97 : repomd.xml différent du sha256 fixé"
cas manifeste "$LC" "COUCHE='amont/rockylinux/rockylinux $M_AMORCE $C_BOOT'" "$GARDE_M" "AssertionError: ['sha256:$C_AMORCE']"
cas couche "$LC" "COUCHE='amont/rockylinux/rockylinux $M_BOOT $C_AMORCE'" "$GARDE_M" "AssertionError: ['sha256:$C_BOOT']"
r=$(kubectl get pods -n builds -o name < /dev/null | grep -c "/$N-" || true)
[ "$r" = 0 ] && ok "pods restants au préfixe $N- : 0" || ko "pods restants au préfixe $N- : $r"
echo "# fin $(date -u +%FT%TZ) ; KO $nko"
exit $((nko > 0))
