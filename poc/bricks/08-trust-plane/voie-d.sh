#!/usr/bin/env bash
# Brique 08, jalon J7 : voie D, mesure demandée par le propriétaire le 30/10/2026. Construire sample-app sans conteneur
# imbriqué ni BuildKit : compiler dans le conteneur du pod Kata lui-même, réseau coupé par un espace réseau créé sans
# privilège, puis assembler l'image sans rien exécuter (tar GNU déterministe et crane, de mise.toml).
#   image      image de build assemblée sans rien exécuter : toolchain Go 1.26.10 (module vérifié par sum.golang.org),
#              busybox statique du nixpkgs épinglé et liens de ses applets, /tmp ; environnement du Dockerfile.builder de la
#              brique 04 ; deux assemblages depuis deux répertoires, même digest attendu ; poussée dans Zot
#   compiler   pod Kata de builds (contexte de restricted, limites) sur cette image ; entrées de la brique 03 livrées par
#              kubectl exec (canal de l'opérateur, tar vérifié par sha256) ; go build sous unshare -U -r -n avec les options
#              de la brique 04 ; témoins : Zot joignable depuis le pod, injoignable dans l'espace réseau ; fermeture vide ;
#              proxy réseau ; même spec sans runtimeClassName admise par Pod Security restricted (dry-run serveur)
#   assembler  image sample-app assemblée sans rien exécuter (tar GNU, crane), deux fois depuis deux répertoires, comparée
#              champ par champ à 3a7ca1b1 (binaire, en-tête tar, diff_id, configuration, digest)
# Retrait : dépôts Zot plateforme/builder-go-voie-d et essais-j7/sample-app-voie-d (Zot n'autorise pas la suppression).
#
# Usage (racine du dépôt) : mise run confiance:voie-d -- <étape>…   (journal : resultats/voie-d-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
: "${GOROOT_DIR:?}" "${BUSYBOX:?}" "${POC_OUTILS:?}"
B03=${B03:-$HOME/.cache/supply-chain-poc/w/b03}   # entrées de la brique 03 (bancs du laptop)
GO_MODULE=golang.org/toolchain@v0.0.1-go1.26.10.linux-amd64
DEPOT_BUILDER=plateforme/builder-go-voie-d
DEPOT_APP=essais-j7/sample-app-voie-d
APP_REF=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # sample-app par BuildKit (brique 04)
BIN_REF=e3749c68b6babe6d91a0d8af35aa9bddfe42f09dedafa6877d5ce702c5a69f11          # binaire de la brique 03
LIMITES='{"cpu": "2", "memory": "3Gi"}'
POD=j7-voie-d
T=$W/voie-d
mkdir -p "$T"
umask 022

zot() { DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt "$@"; }   # crane avec le compte d'écriture et la CA du PoC

arbre() { # répertoire : empreinte de l'arbre (chemins relatifs, types, modes et sha256 des fichiers, cibles des liens)
  (cd "$1" && find . -printf '%y %m %p %l\n' | sort | while read -r y m p l; do
    case $y in f) echo "f $m $p $(sha256sum < "$p" | cut -c1-64)" ;; l) echo "l $p -> $l" ;; *) echo "$y $m $p" ;; esac
  done) | sha256sum | cut -c1-64
}

tar_det() { # répertoire sortie entrées… : tar POSIX déterministe (ordre, dates, propriétaires, en-têtes étendus sans PID ni atime)
  local d=$1 o=$2; shift 2
  tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$d" -cf "$o" "$@"
}

racine_builder() { # répertoire : arborescence de l'image de build (Dockerfile.builder de la brique 04, sans RUN)
  chmod -R u+w -- "${1:?}" 2>/dev/null || true   # arbre de la toolchain en lecture seule (cache des modules)
  rm -rf -- "${1:?}" && mkdir -p "$1/bin" "$1/usr/local" "$1/tmp"
  install -m 0755 "$BUSYBOX" "$1/bin/busybox"
  for a in $("$BUSYBOX" --list); do [ "$a" = busybox ] || ln -s busybox "$1/bin/$a"; done
  cp -a "$GOROOT_DIR" "$1/usr/local/go"
  chmod -R u+w "$1/usr/local/go"   # comme la brique 04 (chmod -R u+w du contexte)
  chmod 1777 "$1/tmp"
}

etape_image() {
  local m s db i d
  echo "## prédiction"
  echo "deux assemblages de l'image de build, depuis deux répertoires : même tar, même digest (crane n'ajoute aucune date :"
  echo "  entrée d'historique à valeur nulle, mutate.AppendLayers de go-containerregistry v0.20.6)"
  echo "## entrées"
  m=${GO_MODULE%@*}
  s=$(cat "$POC_OUTILS/gomodcache/cache/download/$m/@v/${GO_MODULE#*@}.ziphash")
  db=$(curl -fsS --max-time 30 "https://sum.golang.org/lookup/$GO_MODULE" | awk -v v="${GO_MODULE#*@}" '$2 == v {print $3}')
  [ -n "$s" ] && [ "$s" = "$db" ] && echo "OK   toolchain $GO_MODULE : $s = sum.golang.org ; arbre extrait $(arbre "$GOROOT_DIR")" \
    || { echo "KO   toolchain : $s ≠ sum.golang.org $db" >&2; exit 1; }
  echo "busybox : $(readlink -f "$BUSYBOX") ($("$BUSYBOX" | sed -n 1p)), sha256 $(sha256sum < "$BUSYBOX" | cut -c1-64), $("$BUSYBOX" --list | wc -l) applets"
  echo "## assemblage (tar GNU, crane append et mutate), deux fois"
  auth_zot "$T/zot.json"
  mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"
  for i in a b; do
    racine_builder "$T/builder-$i/racine"
    tar_det "$T/builder-$i/racine" "$T/builder-$i/couche.tar" bin tmp usr
    zot crane append --oci-empty-base -f "$T/builder-$i/couche.tar" -t "$REG_HOTE/$DEPOT_BUILDER:$i" >/dev/null 2>"$T/crane.err" || { cat "$T/crane.err" >&2; exit 1; }
    zot crane mutate "$REG_HOTE/$DEPOT_BUILDER:$i" --set-platform linux/amd64 -t "$REG_HOTE/$DEPOT_BUILDER:$i" \
      -e PATH=/usr/local/go/bin:/bin -e HOME=/tmp -e CGO_ENABLED=0 -e GOTOOLCHAIN=local -e GOFLAGS=-mod=readonly -e GOSUMDB=off >/dev/null 2>"$T/crane.err" \
      || { cat "$T/crane.err" >&2; exit 1; }
    d=$(zot crane digest "$REG_HOTE/$DEPOT_BUILDER:$i")
    echo "$i : couche $(sha256sum < "$T/builder-$i/couche.tar" | cut -c1-64) ($(stat -c %s "$T/builder-$i/couche.tar") octets), image $d"
    echo "$d" > "$T/builder-$i.digest"
  done
  [ "$(cat "$T/builder-a.digest")" = "$(cat "$T/builder-b.digest")" ] && echo "OK   image de build identique sur deux assemblages : $(cat "$T/builder-a.digest")" \
    || { echo "KO   image de build : $(cat "$T/builder-a.digest") ≠ $(cat "$T/builder-b.digest")" >&2; exit 1; }
  zot crane config "$REG_HOTE/$DEPOT_BUILDER@$(cat "$T/builder-a.digest")" | jq -c '{architecture, os, config, history}'
  echo "image des pods : $REG/$DEPOT_BUILDER@$(cat "$T/builder-a.digest")"
}

pod_spec() { # nom runtimeClass|- image : pod de builds au contexte de restricted, limites explicites, qui attend
  jq -n --arg n "$1" --arg rc "$2" --arg i "$3" --argjson l "$LIMITES" '{apiVersion: "v1", kind: "Pod",
    metadata: {name: $n, namespace: "builds"},
    spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: true, runAsUser: 65532, runAsGroup: 65532, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "construction", image: $i, command: ["sleep", "900"], resources: {requests: $l, limits: $l},
        securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]}
      + (if $rc == "-" then {} else {runtimeClassName: $rc} end))}'
}

dans_pod() { # libellé script : exécuté dans le pod (sh -c), sortie archivée dans $T/<libellé>.log puis affichée
  kubectl exec -n builds "$POD" -- sh -c "$2" > "$T/$1.log" 2>&1 || true
  echo "### $1"; sed 's/^/     /' "$T/$1.log"
}

champ() { sed -n "s/^$2[[:space:]]*:[[:space:]]*//p" "$T/$1.log" | head -1; }   # journal libellé : valeur
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }

COMPILER='cd /tmp/w/src
grep -E "^(NoNewPrivs|CapBnd|CapEff|Seccomp):" /proc/self/status
echo "pod : $(nc -z -w 3 192.168.161.13 5000 && echo Zot joignable || echo Zot injoignable)"
mkdir -p /tmp/vide /tmp/w/out
unshare -U -r -n sh -c "
  echo \"espace réseau : interfaces \$(tail -n +3 /proc/net/dev | cut -d: -f1 | tr -d \" \" | paste -sd,)\"
  nc -z -w 3 192.168.161.13 5000 && echo \"espace réseau, Zot : joignable\" || echo \"espace réseau, Zot : injoignable\"
  t=\$(date +%s)
  GOPROXY=file:///tmp/w/deps/deps/gomod/pkg/mod/cache/download GOMODCACHE=/tmp/mod GOCACHE=/tmp/cache \
    go build -trimpath -buildvcs=false -ldflags \"-s -w -buildid= -X main.Version=1.0.0\" -o /tmp/w/out/sample-app . > /tmp/b.log 2>&1
  echo \"compilation : rc \$? en \$((\$(date +%s) - t)) s\"
  GOPROXY=file:///tmp/vide GOMODCACHE=/tmp/mod-vide GOCACHE=/tmp/cache-vide go build -o /tmp/w/out/n1 . > /tmp/n1.log 2>&1
  echo \"fermeture vide : rc \$? \$(grep -o -m1 \"github.com/go-chi/chi/v5@v5.2.3: [^\\\"]*\" /tmp/n1.log | head -c 150)\"
  GOPROXY=http://192.168.161.13:5000 GOMODCACHE=/tmp/mod-reseau GOCACHE=/tmp/cache-reseau go build -o /tmp/w/out/n2 . > /tmp/n2.log 2>&1
  echo \"proxy réseau : rc \$? \$(grep -o -m1 \"dial tcp [^\\\"]*\" /tmp/n2.log | head -c 150)\"
"
echo "binaire : $(sha256sum /tmp/w/out/sample-app | cut -c1-64)"
echo "go : $(go version)"'

etape_compiler() {
  local img d s
  img=$REG/$DEPOT_BUILDER@$(cat "$T/builder-a.digest")
  echo "## prédiction"
  echo "pod Kata (builds, contexte de restricted) : NoNewPrivs 1, CapBnd 0, CapEff 0, Seccomp 0 (disable_guest_seccomp) ; la même"
  echo "  spec sans runtimeClassName est admise par Pod Security restricted (dry-run serveur)"
  echo "Zot joignable depuis le pod ; dans unshare -U -r -n : interface lo seule, Zot injoignable"
  echo "compilation sous unshare -n, fermeture Hermeto en GOPROXY : réussie, binaire $BIN_REF (brique 03, image 3a7ca1b1)"
  echo "fermeture vide : échec, module github.com/go-chi/chi/v5@v5.2.3 introuvable ; proxy réseau (Zot) : échec, réseau injoignable"
  echo "## entrées de la compilation (arbre de la brique 04 : canon/source sans .git, plus web/dist)"
  rm -rf -- "${T:?}/entrees" && mkdir -p "$T/entrees/src" "$T/entrees/deps"
  (cd "$B03/canon/source" && tar --exclude=./.git --exclude=./web/node_modules -cf - .) | tar -xf - -C "$T/entrees/src"
  cp -a "$B03/build-apres/web/dist" "$T/entrees/src/web/"
  cp -a "$B03/canon/deps/." "$T/entrees/deps/"
  echo "sources $(arbre "$T/entrees/src") ; dont web/dist $(arbre "$T/entrees/src/web/dist") ; fermeture $(arbre "$T/entrees/deps")"
  echo "écart connu : poc/sample-app (dépôt Forgejo de J2) diffère de canon/source par web/package.json et web/package-lock.json"
  tar --sort=name --format=ustar --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$T/entrees" -cf "$T/entrees.tar" src deps   # ustar : lu par busybox
  s=$(sha256sum < "$T/entrees.tar" | cut -c1-64)
  echo "## pod $POD (image $img)"
  pod_spec "$POD" - "$img" > "$T/$POD-runc.json"
  kubectl create --dry-run=server -f "$T/$POD-runc.json" > "$T/dry.out" 2>&1 \
    && echo "OK   même spec sans runtimeClassName : admise dans builds (Pod Security restricted, dry-run serveur)" \
    || { cat "$T/dry.out" >&2; echo "KO   spec non conforme à restricted" >&2; exit 1; }
  pod_spec "$POD" kata "$img" > "$T/$POD.json"
  kubectl delete pod -n builds "$POD" --ignore-not-found --wait=true >/dev/null
  kubectl create -f "$T/$POD.json" >/dev/null
  kubectl wait -n builds "pod/$POD" --for=condition=Ready --timeout=300s >/dev/null
  echo "pod prêt sur $(kubectl get pod -n builds "$POD" -o jsonpath='{.spec.nodeName}'), image $(kubectl get pod -n builds "$POD" -o jsonpath='{.status.containerStatuses[0].imageID}')"
  d=$(kubectl exec -i -n builds "$POD" -- sh -c 'mkdir -p /tmp/w && tee /tmp/entrees.tar | sha256sum | cut -c1-64' < "$T/entrees.tar")
  attendu "entrées livrées par kubectl exec (sha256 du tar, hôte et pod)" "$d" "$s"
  kubectl exec -n builds "$POD" -- tar -xf /tmp/entrees.tar -C /tmp/w
  dans_pod compiler "$COMPILER"
  kubectl exec -n builds "$POD" -- cat /tmp/w/out/sample-app > "$T/sample-app"
  kubectl delete pod -n builds "$POD" --wait=false >/dev/null
  echo "## comparaison"
  attendu "pod Kata : NoNewPrivs, CapBnd, CapEff, Seccomp" "$(champ compiler NoNewPrivs) $(champ compiler CapBnd) $(champ compiler CapEff) $(champ compiler Seccomp)" "1 0000000000000000 0000000000000000 0"
  attendu "réseau : depuis le pod, puis dans l'espace réseau" "$(champ compiler pod) / $(champ compiler 'espace réseau') / $(champ compiler 'espace réseau, Zot')" "Zot joignable / interfaces lo / injoignable"
  case $(champ compiler compilation) in "rc 0 "*) echo "OK   compilation sous unshare -n : $(champ compiler compilation)" ;; *) echo "KO   compilation : $(champ compiler compilation)" >&2; exit 1 ;; esac
  attendu "binaire (pod, puis relu sur l'hôte)" "$(champ compiler binaire) $(sha256sum < "$T/sample-app" | cut -c1-64)" "$BIN_REF $BIN_REF"
  case $(champ compiler 'fermeture vide') in "rc 1 github.com/go-chi/chi/v5@v5.2.3: "*) echo "OK   fermeture vide : refusée ($(champ compiler 'fermeture vide'))" ;;
    *) echo "KO   fermeture vide : $(champ compiler 'fermeture vide')" >&2; exit 1 ;; esac
  case $(champ compiler 'proxy réseau') in "rc 1 dial tcp "*"network is unreachable"*) echo "OK   proxy réseau : refusé ($(champ compiler 'proxy réseau'))" ;;
    *) echo "KO   proxy réseau : $(champ compiler 'proxy réseau')" >&2; exit 1 ;; esac
}

etape_assembler() {
  local i d
  [ "$(sha256sum < "$T/sample-app" | cut -c1-64)" = "$BIN_REF" ] || { echo "KO   binaire absent ou différent : étape compiler" >&2; exit 1; }
  echo "## prédiction (écart d'en-tête relevé en exploratoire le 30/10/2026, avant cette prédiction ; corrigée après un premier"
  echo "## passage démenti sur created, resultats/voie-d-assembler-premiere-prediction.log)"
  echo "deux assemblages depuis deux répertoires : même couche, même digest"
  echo "face à 3a7ca1b1 : même binaire, mêmes nom, mode (0755), UID et GID (0), noms vides et date (0), même taille de tar ; en-tête"
  echo "  différent par devmajor et devminor (vides chez GNU tar, zéros octaux chez BuildKit), donc par la somme de contrôle :"
  echo "  diff_id différent ; configuration identique hors historique et created (User, Env, Entrypoint, WorkingDir, plateforme"
  echo "  fixés comme la référence ; created : 0001-01-01, date nulle de Go, chez crane, que crane 0.20.6 ne permet pas de fixer,"
  echo "  contre 1970-01-01 chez BuildKit) ; digest différent"
  for i in a b; do
    rm -rf -- "${T:?}/app-$i" && mkdir -p "$T/app-$i/racine"
    install -m 0755 "$T/sample-app" "$T/app-$i/racine/sample-app"
    tar --format=ustar --numeric-owner --owner=0 --group=0 --mtime=@0 -b 1 -C "$T/app-$i/racine" -cf "$T/app-$i/couche.tar" sample-app
    zot crane append --oci-empty-base -f "$T/app-$i/couche.tar" -t "$REG_HOTE/$DEPOT_APP:$i" >/dev/null 2>"$T/crane.err" || { cat "$T/crane.err" >&2; exit 1; }
    zot crane mutate "$REG_HOTE/$DEPOT_APP:$i" --set-platform linux/amd64 -u 65532:65532 --entrypoint /sample-app -w / \
      -e PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin -t "$REG_HOTE/$DEPOT_APP:$i" >/dev/null 2>"$T/crane.err" \
      || { cat "$T/crane.err" >&2; exit 1; }
    d=$(zot crane digest "$REG_HOTE/$DEPOT_APP:$i"); echo "$d" > "$T/app-$i.digest"
    echo "$i : couche $(sha256sum < "$T/app-$i/couche.tar" | cut -c1-64), image $d"
  done
  attendu "image sample-app identique sur deux assemblages" "$(cat "$T/app-a.digest")" "$(cat "$T/app-b.digest")"
  echo "## comparaison avec $APP_REF (BuildKit, brique 04)"
  d=$(cat "$T/app-a.digest")
  zot crane manifest "$REG_HOTE/workspace/sample-app@$APP_REF" > "$T/ref-manifeste.json"
  zot crane config "$REG_HOTE/workspace/sample-app@$APP_REF" > "$T/ref-config.json"
  zot crane config "$REG_HOTE/$DEPOT_APP@$d" > "$T/d-config.json"
  zot crane blob "$REG_HOTE/workspace/sample-app@$(jq -r '.layers[0].digest' "$T/ref-manifeste.json")" | gzip -dc > "$T/ref-couche.tar"
  attendu "binaire extrait de la couche de référence" "$(tar -xOf "$T/ref-couche.tar" sample-app | sha256sum | cut -c1-64)" "$BIN_REF"
  attendu "taille du tar (référence, voie D)" "$(stat -c %s "$T/ref-couche.tar") $(stat -c %s "$T/app-a/couche.tar")" "$(stat -c %s "$T/ref-couche.tar") $(stat -c %s "$T/ref-couche.tar")"
  cmp -l "$T/ref-couche.tar" "$T/app-a/couche.tar" > "$T/cmp.txt" || true
  echo "octets différents : $(wc -l < "$T/cmp.txt"), aux positions $(awk '{print $1 - 1}' "$T/cmp.txt" | paste -sd' ')"
  awk '{p = $1 - 1; f = (p >= 148 && p < 156) ? "chksum" : (p >= 329 && p < 337) ? "devmajor" : (p >= 337 && p < 345) ? "devminor" : "autre"; print f}' "$T/cmp.txt" | sort | uniq -c | awk '{printf "  %s : %s octet(s)\n", $2, $1}'
  [ -z "$(awk '{p = $1 - 1; if (!((p >= 148 && p < 156) || (p >= 329 && p < 345))) print}' "$T/cmp.txt")" ] \
    && echo "OK   écarts limités à l'en-tête du fichier : somme de contrôle, devmajor, devminor" || { echo "KO   écart hors de ces champs" >&2; exit 1; }
  echo "diff_id : référence $(jq -r '.rootfs.diff_ids[0]' "$T/ref-config.json"), voie D $(jq -r '.rootfs.diff_ids[0]' "$T/d-config.json")"
  attendu "configuration hors rootfs, historique et created (référence = voie D)" \
    "$(jq -S -c 'del(.rootfs, .history, .created)' "$T/d-config.json")" "$(jq -S -c 'del(.rootfs, .history, .created)' "$T/ref-config.json")"
  attendu "created (référence, voie D)" "$(jq -r .created "$T/ref-config.json") $(jq -r .created "$T/d-config.json")" "1970-01-01T00:00:00Z 0001-01-01T00:00:00Z"
  echo "historique de la voie D : $(jq -c .history "$T/d-config.json")"
  echo "historique de la référence : $(jq -c '[.history[].created_by]' "$T/ref-config.json")"
  zot crane blob "$REG_HOTE/workspace/sample-app@$(jq -r '.layers[0].digest' "$T/ref-manifeste.json")" > "$T/ref-couche.tar.gz"
  zot crane blob "$REG_HOTE/$DEPOT_APP@$(zot crane manifest "$REG_HOTE/$DEPOT_APP@$d" | jq -r '.layers[0].digest')" > "$T/d-couche.tar.gz"
  echo "en-tête gzip de la couche : référence $(head -c 10 "$T/ref-couche.tar.gz" | od -An -tx1 | tr -s ' '), voie D $(head -c 10 "$T/d-couche.tar.gz" | od -An -tx1 | tr -s ' ')"
  echo "couche compressée : référence $(jq -r '.layers[0].digest' "$T/ref-manifeste.json"), voie D $(sha256sum < "$T/d-couche.tar.gz" | cut -c1-64)"
  echo "digest : référence $APP_REF, voie D $d"
}

lancer voie-d J7 "$@"
