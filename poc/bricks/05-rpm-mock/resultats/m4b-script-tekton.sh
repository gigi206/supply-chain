#!/bin/bash
# Reconstruit Args[1] de place-scripts comme placeScriptInContainer (Tekton v1.15.5, lecture) pour le script substitué,
# en mesure la longueur, vérifie le décodage local, puis passe un argument unique de cette longueur à sh -c sur sc-build.
export DISTRO=rke2
. poc/bricks/08-trust-plane/commun.sh >/dev/null 2>&1
set -u
SCRIPT=$HOME/.cache/supply-chain-poc/08/travail/m4b-05/script-essai.sh
SRC=$HOME/.cache/supply-chain-poc/05/tekton-v1.15.5-source/pkg/pod/script.go
date -u +%Y-%m-%dT%H:%M:%SZ
echo "script.go v1.15.5 : $(wc -c < "$SRC") octets, sha256 $(sha256sum < "$SRC" | cut -c1-64)"
echo "script substitué : $(wc -c < "$SCRIPT") octets, sha256 $(sha256sum < "$SCRIPT" | cut -c1-64)"
head -c 2 "$SCRIPT" | grep -q '^#!' && echo "shebang présent : pas de préambule ajouté par Tekton"
b64=$(base64 -w0 < "$SCRIPT")
f=/tekton/scripts/script-0-abcde
A=$(printf 'scriptfile="%s"\ntouch ${scriptfile} && chmod +x ${scriptfile}\ncat > ${scriptfile} << '"'"'_EOF_'"'"'\n%s\n_EOF_\n/tekton/bin/entrypoint decode-script "${scriptfile}"\n' "$f" "$b64")
echo "base64 : ${#b64} caractères ; Args[1] reconstruit : $(printf %s "$A" | wc -c) octets"
echo "décodage local égal au script : $(printf %s "$b64" | base64 -d | cmp -s - "$SCRIPT" && echo égal || echo différent)"
echo "_EOF_ absent du base64 : $(printf %s "$b64" | grep -c _EOF_)"
echo "getconf ARG_MAX sur sc-build : $(sur sc-build 'getconf ARG_MAX' </dev/null)"
n=$(printf %s "$A" | wc -c); n=$((n + 1000))
r=$(printf 'a=$(head -c %s /dev/zero | tr "\\000" A); sh -c "echo \\${#1}" x "$a"; echo "rc $?"\n' "$n" | sur sc-build 'bash -s' 2>&1 | tr '\n' ' '); echo "sur sc-build, sh -c avec un argument unique de $n caractères : $r"
for n in 131071 131072; do
  r=$(printf 'a=$(head -c %s /dev/zero | tr "\\000" A); sh -c "echo \\${#1}" x "$a" 2>&1 | head -c 120; echo " rc ${PIPESTATUS[0]}"\n' "$n" | sur sc-build 'bash -s' 2>&1 | tr '\n' ' '); echo "borne, sur sc-build, argument unique de $n caractères : $r"
done
date -u +%Y-%m-%dT%H:%M:%SZ
