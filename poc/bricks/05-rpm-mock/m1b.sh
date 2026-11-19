#!/usr/bin/env bash
# Brique 05, jalon M1b (carte resultats/m1b-carte.md) : pod d'essai Kata hors ligne, avant toute tâche neuve (processus allégé).
# L'outillage est installé par le dnf de l'amorce rockylinux:9.8 (ed654c69, transposition 3 retenue le 18/11), sur le miroir
# partiel vérifié du banc de l'amorce du 18/11, avec les valeurs fixées le 19/11 (en_US, umask 022, machine-id absent, racine en
# 0555, déjà mesurée dans a8), puis archivé par le tar de l'amorce. Cible : 7c07083c… (m1b-tar-amorce.log). Deux pods, une
# installation chacun. La création des deux pods est une écriture dans le cluster, prévue au point 4 de la carte, lancée sous
# l'accord permanent du 18/11 ; aucune politique ni label neuf (label construire-rpm, coupé par construction-rpm-sans-sortie),
# aucune écriture dans Zot, aucune tâche ni signature. Prédictions : resultats/m1b-predictions.md.
#   prealables  hôte et lecture : entrées (clés, miroir, dnf.conf) relues contre le banc du 18/11 et la liste épinglée ; archive de
#               transfert entrees.tar et sa liste de sha256 ; politiques de builds relues ; aucun objet $N-* ; pods rendus et admis
#               à blanc côté serveur
#   pod_a       cluster : pod $N-a créé ; entrées copiées par morceaux et revérifiées ; témoins (umask, langues, versions, S, réseau
#   pod_b       coupé) ; dnf --installroot ; archive par le tar de l'amorce ; archive rapatriée sur l'hôte ; pod supprimé
#   banc        hôte seul, hors ligne : les deux sondes des pods jouées telles quelles dans une racine de l'amorce extraite à
#               neuf (chroot sous unshare) ; archive comparée à la cible avant tout pod
#   comparer    hôte, hors ligne : archives des deux pods entre elles, à la cible 7c07083c… et, membre à membre, à a8 (06c289ad…)
# $N (PREFIXE, m1b par défaut) préfixe chaque objet : une relance se fait sous un autre préfixe, jamais en purgeant.
# Aucun secret en argument de commande ; journaux filtrés (jeton|token) ; jamais le message d'une condition ni d'un Event.
# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/m1b.sh <étape>… (journal : resultats/m1b-<étape>.log)
set -euo pipefail
export LC_ALL=C

h05=$(cd "$(dirname "$0")" && pwd)
here=$h05/../08-trust-plane
. "$here/commun.sh"   # repo, O, S, P, W, REG, REG_HOTE
N=${PREFIXE:-m1b}
case $N in ''|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac
T=$W/$N-05
mkdir -p "$T"
umask 022

AMORCE=$REG/amont/rockylinux/rockylinux@sha256:ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d   # s1.sh, l. 169
BANC=$HOME/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z   # banc de l'amorce du 18/11 : lecture seule
LISTE=$h05/resultats/m1b-listes-outillage.txt
DNF_CONF_SHA=d554fb1ce168663f                       # dnf.conf du banc (16 premiers caractères du sha256)
S_ATT=1793914619                                    # S du banc de l'amorce (m1b-outil-amorce.log, AJ4)
CIBLE=7c07083cd7bee149d391180633ad9cca6c82c7ad0dfa5c6bf248acad0b1ef9b7   # i8 archivé par le tar de l'amorce (m1b-tar-amorce.log)
A8=06c289ad8da33198dd845be6cc899f688ecfb8986e77e4b333629e838876dfa5      # même arbre, tar de l'hôte
NOMS="mock-6.9-1.el9 mock-core-configs-45.2-1.el9 podman-5.8.2-8.el9_8 skopeo-1.22.2-9.el9_8 rocky-release shadow-utils"   # m1b-outil-amorce.sh
LABEL_CONSTRUIRE=construire-rpm   # sélectionné par construction-rpm-sans-sortie (M3)
MORCEAU_MIO=64                    # s1.sh : l'exec sous Kata bloque à 512 Mio
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'

attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
echec() { echo "KO   $*" >&2; exit 1; }
filtre() { sed -E -e 's/<[^>]*@[^>]*>/<adresse retirée>/g' -e "$MASQUE"; }

pod_json() { # nom : pod d'essai Kata, image de l'amorce, contexte et ressources du pas construire de construire-rpm signée,
  # label construire-rpm, tmpfs /w ; sans PVC
  jq -n --arg n "$1" --arg i "$AMORCE" --arg lb "$LABEL_CONSTRUIRE" --arg j "$N" \
    --argjson sc "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .securityContext' "$h05/construction/construire-rpm.signee.yaml")" \
    --argjson res "$(yq -o=json -I=0 '.spec.steps[] | select(.name == "construire") | .resources' "$h05/construction/construire-rpm.signee.yaml")" '
    {apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"poc.test/jalon": $j, "tekton.dev/task": $lb}},
     spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, enableServiceLinks: false,
       runtimeClassName: "kata", nodeSelector: {zone: "build"},
       tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
       securityContext: {runAsNonRoot: false, runAsUser: 0, runAsGroup: 0, seccompProfile: {type: "RuntimeDefault"}},
       volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: "4Gi"}}],
       containers: [{name: "essai", image: $i, command: ["sleep", "21600"], securityContext: $sc, resources: $res,
         volumeMounts: [{name: "w", mountPath: "/w"}]}]}}' > "$T/pod-$1.json"
}
a_blanc() { # fichier : création admise à blanc côté serveur ; jamais le texte du refus, seulement des motifs comptés
  local r=0
  kubectl create --dry-run=server -o name -f "$1" < /dev/null > /dev/null 2> "$T/a-blanc.err" || r=$?
  if [ $r = 0 ]; then echo "OK   admis à blanc : ${1##*/}"
  else echo "KO   refusé à blanc : ${1##*/} (code $r ; motifs PodSecurity $(grep -ci 'podsecurity\|pod security' "$T/a-blanc.err" || true), kyverno $(grep -ci kyverno "$T/a-blanc.err" || true))" >&2; exit 1; fi
}
politique_relue() { # m5.sh : construction-rpm-sans-sortie relue, aucune politique de builds n'autorise de trafic à construire-rpm
  local t=$T/politiques.json
  { kubectl get networkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "NetworkPolicy"'
    kubectl get ciliumnetworkpolicy -n builds -o json < /dev/null | jq '.items[] | .kind = "CiliumNetworkPolicy"'; } | jq -s '{items: .}' > "$t"
  echo "politiques de builds : $(jq -r '[.items[] | "\(.kind) \(.metadata.name)"] | join(", ")' "$t")"
  attendu "construction-rpm-sans-sortie : sélecteur, types, règles d'entrée et de sortie" \
    "$(jq -c '[.items[] | select(.kind == "NetworkPolicy" and .metadata.name == "construction-rpm-sans-sortie")
      | [.spec.podSelector, (.spec.policyTypes | sort), (.spec.ingress // []), (.spec.egress // [])]]' "$t")" \
    "[[{\"matchLabels\":{\"tekton.dev/task\":\"$LABEL_CONSTRUIRE\"}},[\"Egress\",\"Ingress\"],[],[]]]"
  attendu "politiques de builds qui sélectionnent $LABEL_CONSTRUIRE et autorisent du trafic" "$(jq -r -L "$here" --arg l "$LABEL_CONSTRUIRE" \
    'include "selecteurs"; [.items[] | select(selectionne({"tekton.dev/task": $l}) and autorise) | nom] | join(", ")' "$t")" ""
}
copier() { # pod fichier-hôte chemin-pod : repris de s1.sh (morceaux de MORCEAU_MIO, taille relue après chaque morceau, sha256)
  local n i k e m=$((MORCEAU_MIO * 1048576)) nb
  n=$(stat -c %s "$2"); nb=$(( (n + m - 1) / m )); [ "$nb" -gt 0 ] || nb=1
  kubectl exec -n builds "$1" -- sh -c ": > $3" < /dev/null
  for ((i = 0; i < nb; i++)); do
    k=$(( n - i * m < m ? n - i * m : m ))
    dd if="$2" bs=1M skip=$((i * MORCEAU_MIO)) count=$MORCEAU_MIO status=none \
      | timeout 120 kubectl exec -i -n builds "$1" -- sh -c "head -c $k >> $3" \
      || { pod_retirer "$1"; echec "copie de ${2##*/}, morceau $((i + 1)) sur $nb"; }
    e=$(kubectl exec -n builds "$1" -- stat -c %s "$3" < /dev/null)
    [ "$e" = "$(( i * m + k ))" ] || { pod_retirer "$1"; echec "copie de ${2##*/} : $e octets après le morceau $((i + 1))"; }
  done
  e=$(kubectl exec -n builds "$1" -- sha256sum "$3" < /dev/null | cut -c1-64)
  [ "$e" = "$(sha256sum < "$2" | cut -c1-64)" ] && echo "OK   copie de ${2##*/} dans le pod : $n octets en $nb morceau(x), sha256 conforme" \
    || { pod_retirer "$1"; echec "copie de ${2##*/} : sha256 dans le pod $e"; }
}
pod_retirer() { kubectl delete pod -n builds "$1" --wait=false < /dev/null > /dev/null; echo "pod $1 supprimé"; }
dans() { # pod libellé : script sh sur l'entrée standard, exécuté dans le pod ; sortie filtrée dans $T/<libellé>.log, puis affichée
  local rc=0
  kubectl exec -i -n builds "$1" -- sh -s > "$T/$2.brut" 2>&1 || rc=$?
  filtre < "$T/$2.brut" > "$T/$2.log"; rm -f -- "$T/$2.brut"
  sed 's/^/     /' "$T/$2.log"
  echo "     (code de l'exec : $rc)"
  return $rc
}

etape_prealables() {
  local m=$BANC/outils/m e
  echo "## entrées, relues contre le banc de l'amorce du 18/11"
  attendu "a8.tar du banc" "$(sha256sum < "$BANC/archives/a8.tar" | cut -c1-64)" "$A8"
  attendu "dnf.conf du banc (16 car.)" "$(sha256sum < "$m/dnf.conf" | cut -c1-16)" "$DNF_CONF_SHA"
  grep -q "S = $S_ATT" "$h05/resultats/m1b-outil-amorce.log" && echo "OK   S = $S_ATT dans m1b-outil-amorce.log" || echec "S absente du journal"
  e=0
  while read -r dep f s; do
    [ "${dep:0:1}" = "#" ] && continue
    p=$(find "$m/miroir/$dep" -type f -name "$f" | head -1)
    [ -n "$p" ] && [ "$(sha256sum < "$p" | cut -c1-64)" = "$s" ] || echec "$dep $f : absent ou sha256 différent"
    e=$((e + 1))
  done < "$LISTE"
  echo "OK   rpm de la liste épinglée présents dans le miroir au bon sha256 : $e"
  echo "rpm dans le miroir : $(find "$m/miroir" -name '*.rpm' | wc -l) ; fichiers : $(find "$m/miroir" -type f | wc -l) ; clés : $(ls "$m/cles" | tr '\n' ' ')"
  echo "## archive de transfert (clés, miroir, dnf.conf, aucun/) et liste de sha256"
  ( cd "$m" && find cles miroir dnf.conf -type f | sort | xargs sha256sum ) > "$T/entrees.sha256"
  tar --sort=name --format=posix --pax-option=delete=atime,delete=ctime --mtime="@$S_ATT" --clamp-mtime --owner=0 --group=0 --numeric-owner \
    -C "$m" -cf "$T/entrees.tar" cles miroir dnf.conf aucun
  echo "entrees.tar : $(stat -c %s "$T/entrees.tar") octets, sha256 $(sha256sum < "$T/entrees.tar" | cut -c1-64) ; liste : $(wc -l < "$T/entrees.sha256") fichiers"
  echo "## cluster, lecture"
  politique_relue
  for o in "$N-a" "$N-b"; do
    [ -z "$(kubectl get pod -n builds --field-selector "metadata.name=$o" -o name < /dev/null 2> /dev/null)" ] || echec "pod $o déjà présent (relancer sous un autre PREFIXE)"
    pod_json "$o"
    a_blanc "$T/pod-$o.json"
  done
  echo "pod : image $(jq -r '.spec.containers[0].image' "$T/pod-$N-a.json") ; label $(jq -r '.metadata.labels["tekton.dev/task"]' "$T/pod-$N-a.json") ; ressources $(jq -c '.spec.containers[0].resources.limits' "$T/pod-$N-a.json")"
}

SONDE_POD='set -u
export LC_ALL=C
for o in dnf rpm tar sha256sum find bash timeout; do command -v $o >/dev/null 2>&1 || { echo "KO   $o absent de l image"; exit 1; }; done
echo "invité : $(uname -r), $(nproc) vCPU ; uid $(id -u) ; umask du conteneur : $(umask)"
echo "%_install_langs : [$(rpm -E %_install_langs)]"
echo "versions : $(rpm -q --qf "%{NEVRA} " rpm dnf python3-dnf libsolv libdnf tar)"
mkdir -p /w/m && cd /w/m && tar -xf /w/entrees.tar && rm -f /w/entrees.tar || { echo "KO   extraction"; exit 1; }
sha256sum -c --quiet /w/entrees.sha256 > /w/c.log 2>&1; r=$?
echo "entrées revérifiées dans le pod : rc $r ; fichiers $(find cles miroir dnf.conf -type f | wc -l) ; lignes de la liste $(wc -l < /w/entrees.sha256)"
[ $r = 0 ] || { head -c 400 /w/c.log; echo "KO   entrées"; exit 1; }
[ ! -e /m ] && ln -s /w/m /m && echo "lien /m vers /w/m posé" || { echo "KO   /m existe déjà dans l image"; exit 1; }
E=$(rpm -qp --nosignature --qf "%{BUILDTIME}\n" $(find /m/miroir -name "*.rpm") 2>/dev/null | grep -E "^[0-9]+$" | sort -n | tail -n 1)
F=$(rpm -qp --nosignature --qf "[%{FILEMTIMES}\n]" $(find /m/miroir -name "*.rpm") 2>/dev/null | grep -E "^[0-9]+$" | sort -n | tail -n 1)
echo "S recalculée dans le pod : $(( E > F ? E : F ))"
timeout 5 bash -c "exec 3<>/dev/tcp/@ZOT@/@ZOT_PORT@" > /w/t.log 2>&1; echo "témoin TCP Zot @ZOT@:@ZOT_PORT@ (5 s) : rc $?"
timeout 5 getent hosts dl.rockylinux.org > /w/t.log 2>&1; echo "témoin DNS dl.rockylinux.org (5 s) : rc $?"
df -k /w | awk "NR == 2 {print \"avant dnf, /w : capacité \" \$2 \" kB ; utilisés \" \$3 \" kB\"}"
true'
SONDE_INSTALL='set -u
cd /
t=$(date +%s); echo "dnf, début $(date -u +%FT%TZ)"
umask 022
env -i PATH=/usr/sbin:/usr/bin HOME=/root LC_ALL=C container=oci SOURCE_DATE_EPOCH=@S@ /usr/bin/dnf -y -c /m/dnf.conf \
  --setopt=reposdir=/m/aucun --setopt=cachedir=/m/cache --installroot=/m/i --releasever=9 install @NOMS@ > /w/dnf.log 2>&1
r=$?; echo "dnf code $r en $(($(date +%s) - t)) s ; $(wc -l < /w/dnf.log) lignes de journal ; fin $(date -u +%FT%TZ)"
echo "lignes « scriptlet », « warning » ou « error » (casse ignorée) : $(grep -Eci "scriptlet|(^|[^-[:alnum:]])(warning|error)" /w/dnf.log)"
[ $r = 0 ] || { tail -n 15 /w/dnf.log; echo "KO   dnf"; exit 1; }
echo "paquets installés : $(rpm --root=/m/i -qa | wc -l), dont gpg-pubkey $(rpm --root=/m/i -qa gpg-pubkey | wc -l)"
echo "racine de l arbre : $(stat -c %a /m/i) ; etc/machine-id : $(stat -c "%s octet(s), mode %a" /m/i/etc/machine-id 2>/dev/null || echo absent)"
tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime="@@S@" --clamp-mtime \
  --xattrs --xattrs-include="*" --numeric-owner \
  --exclude=./var/log/dnf.log --exclude=./var/log/dnf.librepo.log --exclude=./var/log/dnf.rpm.log --exclude=./var/log/hawkey.log \
  --exclude=./var/lib/dnf/history.sqlite --exclude=./var/lib/dnf/history.sqlite-shm --exclude=./var/lib/dnf/history.sqlite-wal \
  --exclude=./var/cache/ldconfig/aux-cache --exclude=./var/cache/dnf --exclude=./m --exclude=./etc/machine-id \
  -C /m/i -cf /w/p.tar . 2> /w/tar.err; r=$?
echo "tar code $r ; stderr $(wc -l < /w/tar.err) lignes"
echo "archive du pod : $(stat -c %s /w/p.tar) octets, $(tar -tf /w/p.tar | wc -l) membres, sha256 $(sha256sum < /w/p.tar | cut -c1-64)"
df -k /w | awk "NR == 2 {print \"après archive, /w : capacité \" \$2 \" kB ; utilisés \" \$3 \" kB\"}"
true'

pod_essai() { # a|b|c|d [limite|-] [proc] : pod $N-<x>, installation, archive rapatriée sous $T/p-<x>.tar ; avec une limite, dnf tourne
  # sous cette limite de fichiers ouverts, souple puis dure (ajout du 19/11/2026 pour pod_c, après m1b-cloexec-banc.log) ;
  # sans limite, SONDE_INSTALL est passée telle quelle, comme pour pod_a
  # avec « proc » (ajout du 19/11/2026 pour pod_d, décision « Mesurer aussi /proc ») : /proc monté dans la racine installée avant
  # dnf, démonté juste après dnf et avant tar, sans limite basse
  local x=$1 lim=${2:-} pr=${3:-} p=$N-$1 s sonde=$SONDE_INSTALL
  [ "$lim" != - ] || lim=""
  [ -s "$T/entrees.tar" ] || echec "lancer d'abord l'étape prealables"
  if [ ! -s "$T/pod-$p.json" ]; then
    [ -z "$(kubectl get pod -n builds --field-selector "metadata.name=$p" -o name < /dev/null 2> /dev/null)" ] || echec "pod $p déjà présent (relancer sous un autre PREFIXE)"
    pod_json "$p"
  fi
  if [ -n "$lim" ]; then
    [ "$(grep -c '^umask 022$' <<< "$sonde")" = 1 ] || echec "ligne umask 022 de SONDE_INSTALL introuvable"
    sonde=$(sed "s|^umask 022\$|umask 022\nulimit -Sn $lim \&\& ulimit -Hn $lim \|\| { echo \"KO   limite $lim refusée\"; exit 1; }\necho \"limite de fichiers ouverts avant dnf : \$(ulimit -Sn) / \$(ulimit -Hn)\"|" <<< "$sonde")
    echo "sonde d'installation : limite $lim ajoutée après umask 022"
  fi
  if [ "$pr" = proc ]; then
    [ "$(grep -c '^r=\$?; echo "dnf code' <<< "$sonde")" = 1 ] || echec "ligne du code de dnf introuvable dans SONDE_INSTALL"
    sonde=$(sed -e "s|^umask 022\$|umask 022\nmkdir -p /w/m/i/proc \&\& mount -t proc proc /w/m/i/proc \|\| { echo \"KO   montage de /proc dans la racine\"; exit 1; }\necho \"/proc monté dans la racine avant dnf : \$(grep -c ' /w/m/i/proc proc ' /proc/mounts) montage(s) ; mode de la racine \$(stat -c %a /w/m/i) ; mode du point de montage \$(stat -c %a /w/m/i/proc)\"|" \
      -e "s|^\(r=\$?; echo \"dnf code.*\)\$|\1\numount /w/m/i/proc \&\& echo \"/proc démonté de la racine après dnf : \$(grep -c ' /w/m/i/proc ' /proc/mounts) montage(s) restant(s)\" \|\| { echo \"KO   démontage de /proc\"; exit 1; }|" <<< "$sonde")
    echo "sonde d'installation : /proc monté dans la racine avant dnf, démonté après"
  fi
  [ ! -e "$T/p-$x.tar" ] || echec "$T/p-$x.tar existe (relancer sous un autre PREFIXE)"
  a_blanc "$T/pod-$p.json"
  kubectl create -f "$T/pod-$p.json" < /dev/null > /dev/null
  kubectl wait -n builds "pod/$p" --for=condition=Ready --timeout=300s < /dev/null > /dev/null \
    || { kubectl get pod -n builds "$p" -o json < /dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state
           | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"' >&2; pod_retirer "$p"; echec "pod $p non prêt"; }   # raisons, jamais les messages
  echo "pod $p prêt : $(kubectl get pod -n builds "$p" -o json < /dev/null | jq -r '"nœud \(.spec.nodeName), runtimeClassName \(.spec.runtimeClassName), label \(.metadata.labels["tekton.dev/task"]), image \(.status.containerStatuses[0].imageID)"')"
  copier "$p" "$T/entrees.tar" /w/entrees.tar
  copier "$p" "$T/entrees.sha256" /w/entrees.sha256
  sed -e "s|@ZOT@|${REG_HOTE%:*}|g" -e "s|@ZOT_PORT@|${REG_HOTE##*:}|g" <<< "$SONDE_POD" | dans "$p" "pod-$x-temoins" || { pod_retirer "$p"; echec "témoins du pod $p"; }
  if ! sed -e "s|@S@|$S_ATT|g" -e "s|@NOMS@|$NOMS|g" <<< "$sonde" | dans "$p" "pod-$x-install"; then
    echo "installation : exec en échec ; état du pod : $(kubectl get pod -n builds "$p" -o json < /dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"')"   # raisons, jamais les messages
    kubectl exec -n builds "$p" -- tail -n 30 /w/dnf.log < /dev/null 2>&1 | filtre | sed 's/^/   dnf.log : /' || true
    pod_retirer "$p"; echec "installation du pod $p"
  fi
  kubectl exec -n builds "$p" -- cat /w/dnf.log < /dev/null 2>/dev/null | filtre > "$T/pod-$x-dnf.log" || true
  echo "journal de dnf rapatrié (filtré) : $(wc -l < "$T/pod-$x-dnf.log") lignes, $T/pod-$x-dnf.log"
  s=$(sed -n 's/.*archive du pod : .* sha256 \([0-9a-f]\{64\}\)$/\1/p' "$T/pod-$x-install.log")
  [ -n "$s" ] || { pod_retirer "$p"; echec "sha256 de l'archive absent du journal"; }
  kubectl exec -n builds "$p" -- cat /w/p.tar < /dev/null > "$T/p-$x.tar" || { pod_retirer "$p"; echec "rapatriement de l'archive"; }
  attendu "archive du pod $p rapatriée" "$(sha256sum < "$T/p-$x.tar" | cut -c1-64)" "$s"
  pod_retirer "$p"
  [ "$s" = "$CIBLE" ] && echo "OK   archive du pod $p = cible 7c07083c… octet pour octet" || echo "ÉCART archive du pod $p différente de la cible"
}
etape_banc() { # hôte seul, hors ligne : SONDE_POD et SONDE_INSTALL jouées telles quelles (mêmes sed) dans une racine de
  # l'amorce extraite à neuf (chroot sous unshare, /w simple dossier) ; archive comparée à la cible
  local O=$HOME/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux M=ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d
  local D L s r
  D=$HOME/.cache/supply-chain-poc/05/m1b-banc-sondes-$(date -u +%Y%m%dT%H%M%SZ)   # dossier neuf, jamais effacé ni réutilisé
  [ -s "$T/entrees.tar" ] || echec "lancer d'abord l'étape prealables"
  [ ! -e "$D" ] || echec "dossier déjà présent : $D"
  echo "dossier du banc : $D ; place libre de /home avant : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB"
  mkdir -p "$D/r"
  attendu "manifeste ed654c69 (cache de s1.sh amorce)" "$(sha256sum < "$O/blobs/sha256/$M" | cut -c1-64)" "$M"
  L=$(python3 -I -c 'import json, sys; j = json.load(open(sys.argv[1])); assert len(j["layers"]) == 1; print(j["layers"][0]["digest"][7:])' "$O/blobs/sha256/$M")
  attendu "couche ${L:0:12}" "$(sha256sum < "$O/blobs/sha256/$L" | cut -c1-64)" "$L"
  unshare --map-auto --map-root-user -n tar -xf "$O/blobs/sha256/$L" -C "$D/r" --numeric-owner --exclude='dev/*' 2>/dev/null || echo "tar code $? (fichiers spéciaux ignorés)"
  unshare --map-auto --map-root-user -n mkdir -p "$D/r/dev" "$D/r/proc" "$D/r/w"
  cp "$T/entrees.tar" "$T/entrees.sha256" "$D/r/w/"
  chr() { unshare --map-auto --map-root-user -n -m -p --fork bash -c 'mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || exit 97
    exec chroot "$1" sh -s' _ "$D/r"; }
  r=0; sed -e "s|@ZOT@|${REG_HOTE%:*}|g" -e "s|@ZOT_PORT@|${REG_HOTE##*:}|g" <<< "$SONDE_POD" | chr > "$T/banc-temoins.brut" 2>&1 || r=$?
  filtre < "$T/banc-temoins.brut" > "$T/banc-temoins.log"; rm -f -- "$T/banc-temoins.brut"; sed 's/^/     /' "$T/banc-temoins.log"; echo "     (code : $r)"
  [ $r = 0 ] || echec "témoins du banc"
  r=0; sed -e "s|@S@|$S_ATT|g" -e "s|@NOMS@|$NOMS|g" <<< "$SONDE_INSTALL" | chr > "$T/banc-install.brut" 2>&1 || r=$?
  filtre < "$T/banc-install.brut" > "$T/banc-install.log"; rm -f -- "$T/banc-install.brut"; sed 's/^/     /' "$T/banc-install.log"; echo "     (code : $r)"
  [ $r = 0 ] || echec "installation du banc"
  s=$(sed -n 's/.*archive du pod : .* sha256 \([0-9a-f]\{64\}\)$/\1/p' "$T/banc-install.log")
  attendu "archive du banc relue sur l'hôte" "$(sha256sum < "$D/r/w/p.tar" | cut -c1-64)" "${s:-absent}"
  [ "$s" = "$CIBLE" ] && echo "OK   archive du banc = cible 7c07083c… octet pour octet" || echo "ÉCART archive du banc différente de la cible"
  python3 -I "$h05/resultats/m1b-repro2-comparer.py" "$BANC/archives/a8.tar" "$D/r/w/p.tar" 2>&1 | tail -n 12 | sed 's/^/   comparer : /'
  echo "place libre de /home après : $(df -k --output=avail "$HOME" | tail -1 | tr -d ' ') kB"
}
etape_pod_a() { pod_essai a; }
etape_pod_b() { pod_essai b; }
etape_pod_c() { pod_essai c 1024; }   # ajout du 19/11/2026 (« Oui, après pod A ») : durée de dnf dans Kata sous une limite basse
etape_pod_d() { pod_essai d - proc; }   # ajout du 19/11/2026 (« Mesurer aussi /proc ») : /proc monté dans la racine, limite par défaut

etape_comparer() {
  local a b
  [ -s "$T/p-a.tar" ] && [ -s "$T/p-b.tar" ] || echec "lancer d'abord pod_a et pod_b"
  a=$(sha256sum < "$T/p-a.tar" | cut -c1-64); b=$(sha256sum < "$T/p-b.tar" | cut -c1-64)
  echo "p-a.tar : sha256 $a ; p-b.tar : sha256 $b"
  cmp -s "$T/p-a.tar" "$T/p-b.tar" && echo "OK   les deux pods donnent la même archive" || echo "ÉCART les deux pods diffèrent"
  for x in a b; do
    [ "$(sha256sum < "$T/p-$x.tar" | cut -c1-64)" = "$CIBLE" ] && echo "OK   p-$x.tar = cible 7c07083c…" || echo "ÉCART p-$x.tar différente de la cible"
    echo "## p-$x.tar contre a8.tar (membre à membre)"
    python3 -I "$h05/resultats/m1b-repro2-comparer.py" "$BANC/archives/a8.tar" "$T/p-$x.tar" 2>&1 | tail -n 12 | sed 's/^/   comparer : /'
  done
}

[ $# -ge 1 ] || { echo "usage : $0 <étape>… (prealables banc pod_a pod_b pod_c pod_d comparer)" >&2; exit 2; }
for e in "$@"; do
  declare -F "etape_$e" > /dev/null || { echo "étape inconnue : $e" >&2; exit 2; }
  echo "# m1b.sh $e (PREFIXE $N), début $(date -u +%FT%TZ)"
  "etape_$e"
  echo "# fin $e $(date -u +%FT%TZ)"
done
