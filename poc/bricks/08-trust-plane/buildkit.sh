#!/usr/bin/env bash
# Brique 08, jalon J7 : BuildKit rootless dans un pod Kata (construction de sample-app, reportée de J4 le 29/10/2026).
#   image   moby/buildkit v0.34.1-rootless : tag annoté signé ; index, manifeste linux/amd64 et manifeste d'attestation
#           épinglés ; seul le manifeste d'attestation est signé (bundle sigstore en référent OCI 1.1), et il désigne le
#           manifeste amd64 comme sujet, comme la provenance SLSA qu'il porte. Signature vérifiée par cosign (identité
#           exacte : workflow réutilisable docker/github-builder, appelé par moby/buildkit au tag, commit du tag,
#           déclencheur push) et par gh attestation verify (même chose, plus le workflow appelant et un exécuteur hébergé
#           par GitHub) ; identité voisine refusée ; copie dans Zot avec le référent, signature revérifiée sur la copie ;
#           capacités de fichier de newuidmap et newgidmap ; pour mémoire, v0.25.2-rootless (brique 04) non signée
#   essais  pods de builds conformes à restricted, prédiction d'abord (résultats de l'essai exploratoire du 30/10/2026) :
#           sonde runc et Kata (bounding set, no_new_privs, seccomp, AppArmor, user namespace et montage) ; rootlesskit de
#           l'image ; buildkitd sous unshare -U -r (un seul UID), deux constructions ; taille de l'invité avec des limites
#           (QEMU -smp et -m relevés sur sc-build pendant la vie du pod). Conclusion : aucun RUN possible en restricted
#   exempte après kata.sh exemption ; prédiction corrigée après un premier passage démenti (README) : attributs étendus
#           (racine du conteneur et tmpfs, runc et Kata) ; options de virtiofsd relevées sur sc-build ; rootlesskit de l'image
#           dans un pod Kata privilégié et dans un pod Kata non privilégié avec allowPrivilegeEscalation ; buildkitd en root
#           dans un pod Kata privilégié : trois constructions, dont une qui cherche le démon depuis une étape et joint Zot
#
# Usage (racine du dépôt) : mise run confiance:buildkit -- <étape>…   (journal : resultats/buildkit-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
BK_DEPOT=moby/buildkit
BK_VER=v0.34.1
BK_TAG_OBJET=401bf63d02833b70ef9393eb9702e2b5648dfaaf   # tag annoté v0.34.1
BK_COMMIT=f5b59a1f2fb25a0cb7072c398cab9aed7835da4e
BK_AMONT=docker.io/moby/buildkit
BK_INDEX=sha256:f68752a5a94acfcdad2d07867b7075601a421638e17fc5f28efc1c814d0c4f89   # tag v0.34.1-rootless
BK_AMD64=sha256:ace6811c21334fa502644b9711e0ea48e8539c5c2a843c2325dfb7b987ab260b
BK_ATT=sha256:163cf53ec3fffec55eb54fab08c1c95f7f7d9a61a9a966c20eb962a62d6bf8a5    # attestation de BK_AMD64 (SBOM, provenance)
BK_SIGNEUR=docker/github-builder/.github/workflows/bake.yml
BK_ID=https://github.com/$BK_SIGNEUR@58cb9f5b71b1836d6f690c1e95effdeb9b98cb8a     # workflow réutilisable, épinglé par l'appelant
BUNDLE=application/vnd.dev.sigstore.bundle.v0.3+json
MIROIR_BK=amont/moby/buildkit
T=$W/buildkit
mkdir -p "$T"

cosign_bk() { # référence [ref-du-tag] : signature du manifeste d'attestation, identité exacte
  cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity "$BK_ID" \
    --certificate-github-workflow-repository "$BK_DEPOT" --certificate-github-workflow-ref "refs/tags/${2:-$BK_VER}" \
    --certificate-github-workflow-trigger push --certificate-github-workflow-sha "$BK_COMMIT" "$1"
}

gh_bk() { # référence (oci://…) bundle : même signature, vérifiée par gh (workflow appelant, exécuteur hébergé)
  gh attestation verify "$1" --bundle "$2" --repo "$BK_DEPOT" --signer-workflow "$BK_SIGNEUR" \
    --source-ref "refs/tags/$BK_VER" --source-digest "$BK_COMMIT" --deny-self-hosted-runners \
    --predicate-type https://sigstore.dev/cosign/sign/v1 --format json \
    | jq -r '.[0].verificationResult.signature.certificate | "OK   gh attestation verify : signataire \(.buildSignerURI), appelant \(.buildConfigURI), commit \(.sourceRepositoryDigest), déclencheur \(.buildTrigger), exécuteur \(.runnerEnvironment)"'
}

bundle_bk() { # dépôt [options oras] : bundle sigstore référent du manifeste d'attestation, dans $T/attestation.sigstore.json
  local r l
  r=$(oras discover "${@:2}" --format json --artifact-type "$BUNDLE" "$1@$BK_ATT" | jq -r '[.referrers[].digest] | if length == 1 then .[0] else error("référents : \(length)") end')
  l=$(oras manifest fetch "${@:2}" "$1@$r" | jq -r '.layers[0].digest')
  oras blob fetch "${@:2}" --output "$T/attestation.sigstore.json" "$1@$l"
  echo "bundle sigstore référent de $BK_ATT : $r, sujet $(jq -r '.dsseEnvelope.payload' "$T/attestation.sigstore.json" | base64 -d | jq -r '.subject | map("sha256:" + .digest.sha256) | join(",")')"
}

etape_image() {
  local d p
  echo "## tag $BK_VER"
  [ "$(gh api "repos/$BK_DEPOT/git/ref/tags/$BK_VER" --jq '.object.type + " " + .object.sha')" = "tag $BK_TAG_OBJET" ] \
    && [ "$(gh api "repos/$BK_DEPOT/git/tags/$BK_TAG_OBJET" --jq '.object.sha + " " + (.verification.verified | tostring)')" = "$BK_COMMIT true" ] \
    && echo "OK   tag annoté $BK_VER (objet $BK_TAG_OBJET, signé et vérifié par GitHub) → commit $BK_COMMIT" \
    || { echo "KO   tag $BK_VER" >&2; exit 1; }
  echo "## image $BK_AMONT:$BK_VER-rootless"
  d=$(crane digest "$BK_AMONT:$BK_VER-rootless")
  echo "index $d $([ "$d" = "$BK_INDEX" ] && echo '(= digest épinglé)' || echo "(≠ digest épinglé $BK_INDEX)")"
  crane manifest "$BK_AMONT@$BK_INDEX" > "$T/index.json"
  jq -e --arg m "$BK_AMD64" --arg a "$BK_ATT" '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64")] == [.manifests[] | select(.digest == $m)]
    and ([.manifests[] | select(.digest == $a)] | length == 1 and .[0].annotations["vnd.docker.reference.digest"] == $m)' "$T/index.json" >/dev/null \
    && echo "OK   l'index référence le manifeste linux/amd64 $BK_AMD64 et son manifeste d'attestation $BK_ATT" \
    || { echo "KO   index" >&2; exit 1; }
  crane manifest "$BK_AMONT@$BK_ATT" > "$T/attestation.json"
  p=$(jq -r '.layers[] | select(.annotations["in-toto.io/predicate-type"] == "https://slsa.dev/provenance/v1") | .digest' "$T/attestation.json")
  crane blob "$BK_AMONT@$p" > "$T/provenance.json"
  [ "$(jq -r .subject.digest "$T/attestation.json")" = "$BK_AMD64" ] \
    && [ "$(jq -r '[.subject[].digest.sha256] | join(",")' "$T/provenance.json")" = "${BK_AMD64#sha256:}" ] \
    && echo "OK   sujet du manifeste d'attestation et de la provenance SLSA v1 qu'il porte : $BK_AMD64" \
    || { echo "KO   sujets de l'attestation" >&2; exit 1; }
  echo "provenance : constructeur $(jq -r .predicate.runDetails.builder.id "$T/provenance.json"), $(jq -r '.layers | length' "$T/attestation.json") couches in-toto ($(jq -r '[.layers[].annotations["in-toto.io/predicate-type"]] | join(", ")' "$T/attestation.json"))"
  echo "## signature (seul le manifeste d'attestation est signé ; l'image l'est à travers lui, par son sujet)"
  echo "référents de l'index : $(oras discover --format json "$BK_AMONT@$BK_INDEX" | jq '.referrers | length') ; du manifeste amd64 : $(oras discover --format json "$BK_AMONT@$BK_AMD64" | jq -c '[.referrers[].artifactType]')"
  bundle_bk "$BK_AMONT"
  cosign_bk "$BK_AMONT@$BK_ATT" > "$T/cosign.json" 2> "$T/cosign.err" || { cat "$T/cosign.err" >&2; exit 1; }
  echo "OK   cosign : $BK_ID, dépôt $BK_DEPOT, refs/tags/$BK_VER, commit $BK_COMMIT, déclencheur push ; type $(jq -r '[.[].critical.type] | unique | join(",")' "$T/cosign.json")"
  grep -E '^  - ' "$T/cosign.err" || true
  gh_bk "oci://$BK_AMONT@$BK_ATT" "$T/attestation.sigstore.json"
  refus "identité voisine (tag v0.34.0)" "no matching CertificateIdentity|expected GithubWorkflowRef" cosign_bk "$BK_AMONT@$BK_ATT" v0.34.0
  echo "## copie dans Zot"
  auth_zot "$T/zot.json"
  miroir "$BK_AMONT@$BK_AMD64" "$MIROIR_BK" "$T/zot.json"
  miroir "$BK_AMONT@$BK_ATT" "$MIROIR_BK" "$T/zot.json" -r
  cat /etc/ssl/certs/ca-certificates.crt "$P/ca-poc.crt" > "$T/ca-tous.pem"   # gh joint aussi GitHub
  echo "référents du manifeste amd64 dans Zot : $(oras discover --format json --ca-file "$P/ca-poc.crt" --registry-config "$T/zot.json" "$REG_HOTE/$MIROIR_BK@$BK_AMD64" | jq -c '[.referrers[] | .digest + " " + .artifactType]')"
  bundle_bk "$REG_HOTE/$MIROIR_BK" --ca-file "$P/ca-poc.crt" --registry-config "$T/zot.json"
  SSL_CERT_FILE=$T/ca-tous.pem cosign_bk "$REG_HOTE/$MIROIR_BK@$BK_ATT" > /dev/null 2> "$T/cosign-zot.err" \
    && echo "OK   cosign sur la copie de Zot" || { cat "$T/cosign-zot.err" >&2; exit 1; }
  SSL_CERT_FILE=$T/ca-tous.pem gh_bk "oci://$REG_HOTE/$MIROIR_BK@$BK_ATT" "$T/attestation.sigstore.json"
  echo "image des pods : $REG/$MIROIR_BK@$BK_AMD64"
  echo "## newuidmap et newgidmap dans les couches (rootlesskit les appelle pour une correspondance de plusieurs UID)"
  for d in $(jq -r '.layers[].digest' <(crane manifest "$BK_AMONT@$BK_AMD64")); do
    crane blob "$BK_AMONT@$d" | python3 -I -c '
import sys, tarfile
for m in tarfile.open(fileobj=sys.stdin.buffer, mode="r|*"):
    if m.name in ("usr/bin/newuidmap", "usr/bin/newgidmap"):
        c = m.pax_headers.get("SCHILY.xattr.security.capability", "").encode("latin-1", "surrogateescape")
        p = int.from_bytes(c[4:8], "little") if len(c) >= 8 else 0
        print(f"{m.name} : mode {m.mode:04o}, {m.uid}:{m.gid}, security.capability {c.hex() or 'absent'} (permis : "
              + (", ".join(n for b, n in ((6, "CAP_SETGID"), (7, "CAP_SETUID")) if p >> b & 1) or "aucun")
              + (", effectif" if c[:4] and int.from_bytes(c[:4], "little") & 1 else "") + ")")
'
  done
  echo "CONSTAT pas de bit setuid : capacités de fichier (attribut étendu security.capability) ; sous Kata, elles ne sont pas visibles"
  echo "        dans l'invité (virtiofsd sans --xattr : étape exempte)"
  echo "## pour mémoire : v0.25.2-rootless (version de la brique 04), non retenue"
  d=$(crane digest "$BK_AMONT:v0.25.2-rootless")
  crane manifest "$BK_AMONT@$d" > "$T/index-0.25.2.json"
  m=$(jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest' "$T/index-0.25.2.json")
  a=$(jq -r --arg m "$m" '.manifests[] | select(.annotations["vnd.docker.reference.digest"] == $m) | .digest' "$T/index-0.25.2.json")
  echo "index $d, linux/amd64 $m, attestation $a (provenance $(crane manifest "$BK_AMONT@$a" | jq -r '[.layers[].annotations["in-toto.io/predicate-type"] | select(startswith("https://slsa.dev"))] | join(",")'), sujet OCI $(crane manifest "$BK_AMONT@$a" | jq -r '.subject.digest // "absent"'))"
  echo "référents : index $(oras discover --format json "$BK_AMONT@$d" | jq '.referrers | length'), amd64 $(oras discover --format json "$BK_AMONT@$m" | jq '[.referrers[] | select(.artifactType != "application/vnd.docker.attestation.manifest.v1+json")] | length') (hors attestation), attestation $(oras discover --format json "$BK_AMONT@$a" | jq '.referrers | length')"
  echo "CONSTAT v0.25.2 : aucune signature (ni référent ni bundle), provenance non signée ; v0.34.1 retenue (signée, maintenue). La brique 04"
  echo "        a mesuré 3a7ca1b1 avec BuildKit 0.25.2 (nixpkgs et release amont), en root (cloud) et en rootless (laptop, rootlesskit"
  echo "        2.3.5) : un digest différent sous Kata exigera une contre-épreuve hors Kata avec la 0.34.1 avant d'être imputé à Kata"
}

BUSYBOX=$REG/amont/rancher/mirrored-library-busybox@sha256:ad9fa4d07136a83e69a54ef00102f579d04eba431932de3b0f098cc5d5948f9f   # amd64, glibc (tekton.sh miroir)
BUILDKIT=$REG/$MIROIR_BK@$BK_AMD64
LIMITES='{"cpu": "2", "memory": "3Gi"}'   # demandes = limites (QoS Guaranteed) ; invité dimensionné à partir des limites

RESTREINT='{"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}}'   # contexte de conteneur de restricted

pod_spec() { # nom runtimeClass|- image uid limites|- script [contexte du conteneur, JSON] : pod de builds, dans $T/<nom>.json ;
  # contexte de restricted par défaut ; runAsNonRoot sauf pour l'UID 0
  local sc=${7:-$RESTREINT}
  jq -n --arg n "$1" --arg rc "$2" --arg i "$3" --argjson u "$4" --arg l "$5" --arg s "$6" --argjson sc "$sc" --rawfile ca "$P/ca-poc.crt" '{apiVersion: "v1", kind: "Pod",
    metadata: {name: $n, namespace: "builds"},
    spec: ({restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: ($u != 0), runAsUser: $u, runAsGroup: $u, seccompProfile: {type: "RuntimeDefault"}},
      containers: [{name: "mesure", image: $i, command: ["sh", "-c", $s], env: [{name: "CA_POC", value: $ca}],
        securityContext: $sc}
        + (if $l == "-" then {} else {resources: {requests: ($l | fromjson), limits: ($l | fromjson)}} end)]}
      + (if $rc == "-" then {} else {runtimeClassName: $rc} end))}' > "$T/$1.json"
}

pod_lancer() { # nom [fonction appelée avec le nom, pendant la vie du pod, une fois prêt] : pod de $T/<nom>.json créé, attendu
  # jusqu'à une phase terminale (Succeeded ou Failed) ; sa sortie est archivée dans $T/<nom>.log et affichée avant tout jugement
  local ph=""
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true >/dev/null
  kubectl create -f "$T/$1.json" >/dev/null
  if [ -n "${2:-}" ]; then kubectl wait -n builds "pod/$1" --for=condition=Ready --timeout=300s >/dev/null; "$2" "$1"; fi
  for _ in $(seq 150); do
    ph=$(kubectl get pod -n builds "$1" -o jsonpath='{.status.phase}')
    case $ph in Succeeded|Failed) break ;; esac
    sleep 2
  done
  kubectl logs -n builds "$1" > "$T/$1.log" 2>&1 || true
  echo "### $1 ($(jq -r '"runtimeClassName \(.spec.runtimeClassName // "-"), uid \(.spec.securityContext.runAsUser), contexte \(.spec.containers[0].securityContext | tostring), limites \(.spec.containers[0].resources.limits // "-" | tostring)"' "$T/$1.json")) : phase $ph"
  sed 's/^/     /' "$T/$1.log"
  case $ph in Succeeded|Failed) ;; *) kubectl describe pod -n builds "$1" >&2; echo "KO   pod $1 non terminé (phase $ph)" >&2; exit 1 ;; esac
  kubectl delete pod -n builds "$1" --wait=false >/dev/null
}

pod_mesure() { pod_spec "$@"; pod_lancer "$1"; }   # nom runtimeClass|- image uid limites|- script [contexte]

champ() { sed -n "s/^$2[[:space:]]*:[[:space:]]*//p" "$T/$1.log" | head -1; }   # pod libellé : valeur d'une ligne « libellé : valeur »

attendu() { # libellé valeur-mesurée valeur-attendue
  [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }
}

SONDE='grep -E "^(CapEff|CapBnd|NoNewPrivs|Seccomp):" /proc/self/status
echo "AppArmor : $(cat /proc/self/attr/current 2>&1)"
echo "max_user_namespaces : $(cat /proc/sys/user/max_user_namespaces)"
unshare -U -r -m sh -c "sed -n \"s/^CapBnd:/espace CapBnd :/p\" /proc/self/status; echo \"espace uid_map : \$(tr -s \" \" < /proc/self/uid_map)\"; mount -t tmpfs none /tmp && echo \"espace tmpfs : monté\"" 2> /tmp/u.err
echo "unshare : rc $? $(cat /tmp/u.err)"'

ROOTLESSKIT='grep -E "^(CapBnd|NoNewPrivs):" /proc/self/status
rootlesskit true > /tmp/r.log 2>&1
echo "rootlesskit : rc $? $(grep -o "newuidmap.*" /tmp/r.log | head -1)"'

# Démon sous unshare -U -r (un seul UID, sans newuidmap), sans bac à sable des processus (procMount Unmasked hors de portée en
# restricted), snapshotter native comme la brique 04. Deux constructions : sur busybox de Zot (fichiers à d'autres UID que 0),
# puis sur une base où tout appartient à l'UID 0 (busybox et chargeur musl de l'image BuildKit, depuis scratch).
UNSHARE='echo "vCPU : $(nproc)"; grep MemTotal /proc/meminfo
mkdir -p /tmp/run /tmp/a /tmp/b/bin /tmp/b/lib
printf "%s\n" "$CA_POC" > /tmp/ca.crt
printf "[registry.\"sc-stockage.poc.test:5000\"]\n  ca = [\"/tmp/ca.crt\"]\n" > /tmp/bk.toml
printf "FROM %s\nRUN true\n" "'"$BUSYBOX"'" > /tmp/a/Dockerfile
cp -L /bin/busybox /tmp/b/bin/; cp -L /lib/ld-musl-x86_64.so.1 /tmp/b/lib/
printf "FROM scratch\nCOPY lib/ /lib/\nCOPY bin/ /bin/\nRUN [\"/bin/busybox\", \"true\"]\n" > /tmp/b/Dockerfile
unshare -U -r -m sh -c "
  buildkitd --config /tmp/bk.toml --rootless --oci-worker-no-process-sandbox --oci-worker-snapshotter=native --addr unix:///tmp/run/bk.sock --root /tmp/bk > /tmp/bkd.log 2>&1 &
  for i in \$(seq 30); do buildctl --addr unix:///tmp/run/bk.sock debug workers > /dev/null 2>&1 && break; sleep 1; done
  buildctl --addr unix:///tmp/run/bk.sock debug workers -v > /tmp/w.log 2>&1
  echo \"démon : \$(sed -n \"s/^BuildKit:[[:space:]]*//p\" /tmp/w.log), \$(grep -o \"process-mode:.*\" /tmp/w.log | tr -d \"\t\"), \$(grep -o \"snapshotter:.*\" /tmp/w.log | tr -d \"\t\")\"
  for c in a b; do
    buildctl --addr unix:///tmp/run/bk.sock build --no-cache --frontend dockerfile.v0 --local context=/tmp/\$c --local dockerfile=/tmp/\$c > /tmp/\$c.log 2>&1
    echo \"construction \$c : rc \$? \$(grep -o -m1 -E \"failed to Lchown [^:]*|error mounting .devpts.[^:]*: mount src=devpts[^:]*gid=5: [a-z ]*\" /tmp/\$c.log | head -1)\"
  done"'

etape_essais() {
  local f q
  echo "## prédiction : résultats de l'essai exploratoire du 30/10/2026, rejoués ici"
  echo "runc : CapBnd 0, NoNewPrivs 1, Seccomp 2, AppArmor cri-containerd.apparmor.d (enforce) ; unshare refusé (Operation not permitted)"
  echo "kata : CapBnd 0, NoNewPrivs 1, Seccomp 0, étiquette AppArmor illisible dans l'invité (Invalid argument) ; unshare -U -r -m réussit, bounding set complet dans"
  echo "       le nouvel espace (000001ffffffffff), uid_map 0 65532 1, tmpfs monté"
  echo "kata, rootlesskit de l'image : échec de newuidmap (« Could not set caps »)"
  echo "kata, buildkitd sous unshare -U -r : démon v0.34.1 démarré (no-sandbox, native) ; construction a (busybox de Zot) : échec"
  echo "       lchown d'un fichier à l'UID 65534 ; construction b (tout à l'UID 0) : échec du montage devpts (gid=5 hors correspondance)"
  echo "kata, limites 2 CPU et 3 Gi : static_sandbox_resource_mgmt (initial_size.rs) donne ceil(0,2 + 2) = 3 vCPU et 32 + 3072 = 3104 Mio ;"
  echo "       surcoût de la RuntimeClass (320Mi, 250m) exclu par kubelet (calculateSandboxResources, ExcludeOverhead) :"
  echo "       QEMU -smp 3, -m 3104M ; nproc 3, MemTotal sous 3104 Mio"
  echo "## mesures"
  pod_mesure j7-bk-sonde-runc - "$BUSYBOX" 65532 - "$SONDE"
  pod_mesure j7-bk-sonde-kata kata "$BUSYBOX" 65532 - "$SONDE"
  pod_mesure j7-bk-rootlesskit kata "$BUILDKIT" 1000 - "$ROOTLESSKIT"
  pod_spec j7-bk-unshare kata "$BUILDKIT" 1000 "$LIMITES" "sleep 5; $UNSHARE"
  kubectl delete pod -n builds j7-bk-unshare --ignore-not-found --wait=true >/dev/null
  kubectl create -f "$T/j7-bk-unshare.json" >/dev/null
  kubectl wait -n builds pod/j7-bk-unshare --for=condition=Ready --timeout=300s >/dev/null
  q=$(sur sc-build "sudo k3s crictl pods --namespace builds --name j7-bk-unshare --state ready -q")
  sur sc-build "pgrep -af 'qemu-system.*sandbox-$q'" > "$T/qemu.txt"
  kubectl wait -n builds pod/j7-bk-unshare --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s >/dev/null \
    || { kubectl describe pod -n builds j7-bk-unshare >&2; echo "KO   pod j7-bk-unshare non terminé" >&2; exit 1; }
  kubectl logs -n builds j7-bk-unshare > "$T/j7-bk-unshare.log"
  echo "### j7-bk-unshare (runtimeClassName kata, uid 1000, limites $LIMITES)"
  sed 's/^/     /' "$T/j7-bk-unshare.log"
  kubectl delete pod -n builds j7-bk-unshare --wait=false >/dev/null
  echo "processus QEMU du sandbox $q : $(wc -l < "$T/qemu.txt")"
  for f in -smp -m; do echo "$f $(tr ' ' '\n' < "$T/qemu.txt" | grep -A1 -x -m1 -- "$f" | tail -1)"; done | tee "$T/qemu-args.txt"
  echo "## comparaison"
  attendu "runc : bounding set, no_new_privs, seccomp" "$(champ j7-bk-sonde-runc CapBnd) $(champ j7-bk-sonde-runc NoNewPrivs) $(champ j7-bk-sonde-runc Seccomp)" "0000000000000000 1 2"
  attendu "runc : AppArmor" "$(champ j7-bk-sonde-runc AppArmor)" "cri-containerd.apparmor.d (enforce)"
  case $(champ j7-bk-sonde-runc unshare) in "rc 1 unshare: unshare("*"): Operation not permitted") echo "OK   runc : unshare refusé ($(champ j7-bk-sonde-runc unshare))" ;;
    *) echo "KO   runc : unshare $(champ j7-bk-sonde-runc unshare)" >&2; exit 1 ;; esac
  attendu "kata : bounding set, no_new_privs, seccomp" "$(champ j7-bk-sonde-kata CapBnd) $(champ j7-bk-sonde-kata NoNewPrivs) $(champ j7-bk-sonde-kata Seccomp)" "0000000000000000 1 0"
  attendu "kata : étiquette AppArmor (/proc/self/attr/current)" "$(champ j7-bk-sonde-kata AppArmor)" "cat: read error: Invalid argument"
  attendu "kata : unshare -U -r -m" "$(champ j7-bk-sonde-kata unshare)" "rc 0 "
  attendu "kata : nouvel espace (bounding set, uid_map, tmpfs)" "$(champ j7-bk-sonde-kata 'espace CapBnd') $(champ j7-bk-sonde-kata 'espace uid_map') $(champ j7-bk-sonde-kata 'espace tmpfs')" "000001ffffffffff 0 65532 1 monté"
  case $(champ j7-bk-rootlesskit rootlesskit) in "rc 1 newuidmap"*"Could not set caps"*) echo "OK   kata : rootlesskit en échec ($(champ j7-bk-rootlesskit rootlesskit))" ;;
    *) echo "KO   kata : rootlesskit $(champ j7-bk-rootlesskit rootlesskit)" >&2; exit 1 ;; esac
  attendu "kata : démon sous unshare" "$(champ j7-bk-unshare démon)" "github.com/moby/buildkit $BK_VER $BK_COMMIT, process-mode:no-sandbox, snapshotter:native"
  case $(champ j7-bk-unshare 'construction a') in "rc 1 failed to Lchown "*"for UID 65534, GID 65534") echo "OK   construction a (busybox de Zot) : $(champ j7-bk-unshare 'construction a')" ;;
    *) echo "KO   construction a : $(champ j7-bk-unshare 'construction a')" >&2; exit 1 ;; esac
  case $(champ j7-bk-unshare 'construction b') in "rc 1 error mounting "*"gid=5: invalid argument") echo "OK   construction b (tout à l'UID 0) : $(champ j7-bk-unshare 'construction b')" ;;
    *) echo "KO   construction b : $(champ j7-bk-unshare 'construction b')" >&2; exit 1 ;; esac
  attendu "kata, limites 2 CPU et 3 Gi : QEMU" "$(awk '$1 == "-smp" {s = $2} $1 == "-m" {split($2, a, ","); m = a[1]} END {print "-smp " s " -m " m}' "$T/qemu-args.txt")" "-smp 3 -m 3104M"
  [ "$(champ j7-bk-unshare vCPU)" = 3 ] && [ "$(champ j7-bk-unshare MemTotal | awk '{print $1}')" -lt $((3104 * 1024)) ] \
    && echo "OK   kata, limites 2 CPU et 3 Gi : invité de $(champ j7-bk-unshare vCPU) vCPU, MemTotal $(champ j7-bk-unshare MemTotal)" \
    || { echo "KO   taille de l'invité" >&2; exit 1; }
  echo "CONSTAT en restricted, BuildKit ne peut exécuter aucun RUN, sous runc (user namespace refusé par seccomp) comme sous Kata :"
  echo "        newuidmap échoue (cause mesurée par l'étape exempte : capacités de fichier invisibles dans l'invité), et une"
  echo "        correspondance d'un seul UID bute sur devpts (gid=5) pour toute étape RUN"
}

# Après l'exemption (kata.sh exemption). Démon relancé pour chaque essai (essai libellé lanceur|- options) : rootlesskit de
# l'image (correspondance de 65537 UID par newuidmap), ou buildkitd en root (buildkit-runc), sans rootlesskit. Constructions a
# et b comme dans essais ; c, sur busybox de Zot : une étape cherche le démon dans /proc (argv[0] « buildkitd » : signal,
# racine lisible), puis Zot joint par le réseau par défaut et en --network=none.
BK='grep -E "^(CapEff|CapBnd|NoNewPrivs|Seccomp):" /proc/self/status; echo "uid : $(id -u)"
mkdir -p /tmp/a /tmp/b/bin /tmp/b/lib /tmp/c
printf "%s\n" "$CA_POC" > /tmp/ca.crt
printf "[registry.\"sc-stockage.poc.test:5000\"]\n  ca = [\"/tmp/ca.crt\"]\n" > /tmp/bk.toml
printf "FROM %s\nRUN true\n" "'"$BUSYBOX"'" > /tmp/a/Dockerfile
cp -L /bin/busybox /tmp/b/bin/; cp -L /lib/ld-musl-x86_64.so.1 /tmp/b/lib/
printf "FROM scratch\nCOPY lib/ /lib/\nCOPY bin/ /bin/\nRUN [\"/bin/busybox\", \"true\"]\n" > /tmp/b/Dockerfile
cat > /tmp/c/Dockerfile <<"FIN"
FROM '"$BUSYBOX"'
RUN n=0; s=-; l=-; for p in /proc/[0-9]*; do [ "$(head -c 9 $p/cmdline 2>/dev/null)" = buildkitd ] || continue; n=$((n + 1)); kill -0 ${p#/proc/} 2>/dev/null && s=possible || s=refusé; ls $p/root/ > /dev/null 2>&1 && l=oui || l=non; done; echo "étape processus : démon visible $n, signal $s, racine lisible $l"
RUN nc -z -w 3 192.168.161.13 5000 && echo "étape réseau par défaut : Zot joignable" || echo "étape réseau par défaut : Zot injoignable"
RUN --network=none nc -z -w 3 192.168.161.13 5000 && echo "étape network=none : Zot joignable" || echo "étape network=none : Zot injoignable"
FIN
essai() {
  rm -rf /tmp/run; mkdir -p /tmp/run   # racine propre à chaque essai : ses fichiers peuvent appartenir aux UID subordonnés
  l=$2; [ "$l" = - ] && l=
  $l buildkitd --config /tmp/bk.toml --oci-worker-snapshotter=native $3 --addr unix:///tmp/run/bk.sock --root /tmp/bk-$1 > /tmp/bkd-$1.log 2>&1 &
  k=$!
  for i in $(seq 30); do buildctl --addr unix:///tmp/run/bk.sock debug workers > /dev/null 2>&1 && break; sleep 1; done
  buildctl --addr unix:///tmp/run/bk.sock debug workers -v > /tmp/w.log 2>&1
  echo "$1 démon : $(grep -o "process-mode:.*" /tmp/w.log | tr -d "\t") $(grep -o "network:.*" /tmp/w.log | tr -d "\t")$(grep -o -m1 "newuidmap.*" /tmp/bkd-$1.log)"
  for c in a b c; do
    buildctl --addr unix:///tmp/run/bk.sock build --no-cache --progress plain --frontend dockerfile.v0 --local context=/tmp/$c --local dockerfile=/tmp/$c > /tmp/$1-$c.log 2>&1
    echo "$1 construction $c : rc $? $(grep -o -m1 -E "error mounting [^:]*: [^:]*|failed to [^:]*" /tmp/$1-$c.log | head -1)"
  done
  sed -n -E "s/^#[0-9]+ [0-9.]+ (étape [^:]* : .*)/$1 \\1/p" /tmp/$1-c.log   # sorties des étapes, pas leur texte
  kill $k 2> /dev/null; wait $k 2> /dev/null; true
}'
PRIVILEGIE='{"privileged": true, "allowPrivilegeEscalation": true}'
ESCALADE='{"allowPrivilegeEscalation": true}'   # capacités par défaut de containerd, seccomp RuntimeDefault du pod

# Attributs étendus : un fichier de la racine du conteneur (servie par virtio-fs sous Kata), puis d'un tmpfs (emptyDir en mémoire)
XATTR='echo "racine du conteneur, système de fichiers : $(awk "\$2 == \"/\" {t = \$3} END {print t}" /proc/mounts)"
echo essai > /tmp/f; setfattr -n user.essai -v 1 /tmp/f 2> /tmp/e; echo "racine du conteneur : rc $? $(cat /tmp/e)"
echo essai > /m/f; setfattr -n user.essai -v 1 /m/f 2> /tmp/e; echo "tmpfs : rc $? $(cat /tmp/e)"
echo "tmpfs, relu : $(getfattr -n user.essai /m/f 2>&1 | grep user.essai)"'

releve_virtiofsd() { # pod : processus virtiofsd du sandbox du pod sur sc-build, dans $T/virtiofsd.txt
  local q
  q=$(sur sc-build "sudo k3s crictl pods --namespace builds --name $1 --state ready -q")
  sur sc-build "sudo pgrep -a virtiofsd" | grep -F "$q" > "$T/virtiofsd.txt" || true   # par nom de processus : ni QEMU ni sudo
  echo "virtiofsd du sandbox $q : $(wc -l < "$T/virtiofsd.txt") processus ; options : $(tr ' ' '\n' < "$T/virtiofsd.txt" | grep -E '^-' | sort -u | paste -sd' ')"
}

etape_exempte() {
  local p e
  echo "## prédiction corrigée le 30/10/2026, après le premier passage (resultats/buildkit-exempte-premiere-prediction.log) : la"
  echo "## prédiction du README, écrite avant l'accord, est démentie pour le pod privilégié (newuidmap en échec malgré NoNewPrivs 0)"
  echo "virtiofsd lancé sans --xattr (disable_guest_selinux = true, et runtime-rs 4.3.1 n'ajoute --xattr que si ce drapeau est"
  echo "       faux, share_virtio_fs_standalone.rs)"
  echo "attributs étendus : runc, racine du conteneur : posés ; kata, racine du conteneur (virtio-fs) : refusés (Operation not"
  echo "       supported) ; kata, tmpfs de l'invité : posés et relus"
  echo "kata privilégié, rootless (UID 1000) : NoNewPrivs 0, bounding set complet, mais newuidmap échoue (« Could not set caps ») :"
  echo "       les capacités de fichier ne sont pas visibles dans l'invité ; pas de démon, aucune construction"
  echo "kata non privilégié, allowPrivilegeEscalation et capacités par défaut, rootless : même échec de newuidmap"
  echo "kata privilégié, en root (UID 0, buildkitd sans rootlesskit) : démon en process-mode sandbox, réseau host (mode auto sans"
  echo "       configuration CNI : repli sur l'hôte, netproviders) ; constructions a, b et c réussies ; l'étape ne voit pas le démon ;"
  echo "       Zot joignable par le réseau par défaut, injoignable en --network=none"
  e=$(sur sc-confiance "sudo journalctl -u k3s --no-pager -o cat | grep 'Running kube-apiserver' | tail -n 1" | tr ' ' '\n' \
    | grep -c -x -- '--admission-control-config-file=/etc/rancher/k3s/pod-security.yaml' || true)
  [ "$e" = 1 ] && echo "OK   exemption de la RuntimeClass kata lue par kube-apiserver (kata.sh exemption)" \
    || { echo "KO   exemption absente : lancer kata.sh exemption" >&2; exit 1; }
  echo "## mesures"
  for p in "j7-xattr-runc -" "j7-xattr-kata kata"; do
    set -- $p
    pod_spec "$1" "$2" "$BUSYBOX" 65532 - "$XATTR"
    jq '.spec.volumes = [{name: "m", emptyDir: {medium: "Memory", sizeLimit: "16Mi"}}] | .spec.containers[0].volumeMounts = [{name: "m", mountPath: "/m"}]' \
      "$T/$1.json" > "$T/$1.tmp" && mv "$T/$1.tmp" "$T/$1.json"
    pod_lancer "$1"
  done
  pod_spec j7-bk-privilegie kata "$BUILDKIT" 1000 "$LIMITES" "sleep 5; $BK
essai rootless rootlesskit ''" "$PRIVILEGIE"
  pod_lancer j7-bk-privilegie releve_virtiofsd
  pod_mesure j7-bk-escalade kata "$BUILDKIT" 1000 "$LIMITES" "$BK
essai rootless rootlesskit ''" "$ESCALADE"
  pod_mesure j7-bk-root kata "$BUILDKIT" 0 "$LIMITES" "$BK
essai root - ''" "$PRIVILEGIE"
  echo "## comparaison"
  [ -s "$T/virtiofsd.txt" ] && ! tr ' ' '\n' < "$T/virtiofsd.txt" | grep -x -- '--xattr' >/dev/null \
    && echo "OK   virtiofsd du pod Kata lancé sans --xattr" || { echo "KO   virtiofsd : $(cat "$T/virtiofsd.txt")" >&2; exit 1; }
  attendu "runc : attribut étendu sur la racine du conteneur" "$(champ j7-xattr-runc 'racine du conteneur')" "rc 0 "
  case $(champ j7-xattr-kata 'racine du conteneur') in "rc 1 "*"not supported"*) echo "OK   kata : attribut étendu refusé sur la racine du conteneur ($(champ j7-xattr-kata 'racine du conteneur'))" ;;
    *) echo "KO   kata : racine du conteneur $(champ j7-xattr-kata 'racine du conteneur')" >&2; exit 1 ;; esac
  attendu "kata : attribut étendu sur le tmpfs de l'invité (témoin positif)" "$(champ j7-xattr-kata tmpfs) $(champ j7-xattr-kata 'tmpfs, relu')" 'rc 0  user.essai="1"'
  for p in j7-bk-privilegie j7-bk-escalade; do
    attendu "$p : no_new_privs" "$(champ $p NoNewPrivs)" "0"
    case $(champ $p 'rootless démon') in "newuidmap"*"Could not set caps") echo "OK   $p : rootlesskit en échec ($(champ $p 'rootless démon'))" ;;
      *) echo "KO   $p : démon $(champ $p 'rootless démon')" >&2; exit 1 ;; esac
  done
  attendu "j7-bk-privilegie : bounding set" "$(champ j7-bk-privilegie CapBnd)" "000001ffffffffff"
  p=j7-bk-root
  attendu "en root : UID, démon" "$(champ $p uid) | $(champ $p 'root démon')" "0 | process-mode:sandbox network:host"
  attendu "en root : constructions a, b, c" "$(champ $p 'root construction a')|$(champ $p 'root construction b')|$(champ $p 'root construction c')" "rc 0 |rc 0 |rc 0 "
  attendu "en root : étape et démon" "$(champ $p 'root étape processus')" "démon visible 0, signal -, racine lisible -"
  attendu "en root : réseau de l'étape" "$(champ $p 'root étape réseau par défaut') / $(champ $p 'root étape network=none')" "Zot joignable / Zot injoignable"
  echo "CONSTAT sous Kata, BuildKit rootless de l'image est impossible, même exempté et privilégié : virtiofsd sans --xattr, les"
  echo "        capacités de fichier de newuidmap ne sont pas visibles dans l'invité ; BuildKit en root dans un pod Kata privilégié"
  echo "        construit, avec le bac à sable des processus"
}

lancer buildkit J7 "$@"
