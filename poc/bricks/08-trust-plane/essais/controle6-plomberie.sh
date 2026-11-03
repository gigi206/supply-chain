#!/bin/bash
# Brique 08, contrôle 6 : essai de plomberie SUR L'HÔTE de politique/porte/vsa.sh, avant l'étape controle6 de preuves.sh
# (prédictions : resultats/controle6-predictions.md). Lecture anonyme de Zot seulement, rien écrit, rien appliqué au cluster.
# Au plus près du pod : busybox sh et ses applets (grep, sed, base64…), cosign v3.1.4 (binaire du verrou mise), HOME vide,
# chemins /etc/porte remplacés par une copie locale (vsa.pub, ca-poc.crt) ; Zot par son adresse IP (le nom
# sc-stockage.poc.test ne résout que dans le cluster). Chaque appel au vrai cosign sous strace (connect) : connexions hors de
# Zot listées. Faux cosign local (énoncés de la brique 10 modifiés : FAILED, autre sujet, autre verifier.id) pour la branche
# ECARTE, que le registre ne peut pas montrer sans pousser une VSA témoin.
# Journal : resultats/controle6-plomberie.log
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")/.." && pwd)   # dossier de la brique
r10=$here/../10-independent-replay/resultats
d=$HOME/.cache/supply-chain-poc/08/essais/controle6
ZOT=192.168.161.13:5000
A=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5
rm -rf -- "${d:?}" && mkdir -p "$d/etc" "$d/home" "$d/tmp" "$d/bin" "$d/faux"
cosign=$(mise which cosign)
for a in grep sed base64 sha256sum cut head mktemp cat printf tail; do ln -s "$(command -v busybox)" "$d/bin/$a"; done
cp "$HOME/.cache/supply-chain-poc/08/pki/ca-poc.crt" "$d/etc/"
sed "s#/etc/porte#$d/etc#g" "$here/politique/porte/vsa.sh" > "$d/vsa.sh"
{
echo "# essais/controle6-plomberie.sh, $(date -u +%FT%TZ) ; vsa.sh $(sha256sum < "$here/politique/porte/vsa.sh" | cut -c1-16) ; cosign $("$cosign" version 2>/dev/null | awk '/GitVersion/ {print $2}') ; busybox $(busybox | head -1 | awk '{print $2}')"
cas() { # libellé dépôt clé [faux] : sortie de vsa.sh, code, connexions hors de Zot (vrai cosign)
  local l=$1 depot=$2 cle=$3 faux=${4:-} p=$d/bin:${cosign%/*} rc h
  cp "$cle" "$d/etc/vsa.pub"
  [ -n "$faux" ] && p=$d/faux:$p
  echo "## $l : $ZOT/$depot@${A:0:15}… ; clé $(openssl pkey -pubin -in "$cle" -outform DER | sha256sum | cut -c1-16)${faux:+ ; faux cosign}"
  rc=0; env -i PATH="$p" HOME="$d/home" TMPDIR="$d/tmp" IMAGE="$ZOT/$depot@$A" \
    "$(command -v strace)" -f -qq -e trace=connect -o "$d/trace" "$(command -v busybox)" sh "$d/vsa.sh" || rc=$?
  echo "code $rc"
  h=$(grep -E '^[0-9]+ +connect\(' "$d/trace" | grep -vF "sin_port=htons(${ZOT#*:}), sin_addr=inet_addr(\"${ZOT%:*}\")" \
    | grep -oE 'sa_family=AF_[A-Z0-9]+(, sun_path="[^"]*"|, sin_port=htons\([0-9]+\), sin_addr=inet_addr\("[^"]*"\))?' | sort | uniq -c | sed 's/^ *//' | paste -sd';' - || true)
  echo "connexions : $(grep -cE '^[0-9]+ +connect\(' "$d/trace" || true) connect() ; hors de Zot : ${h:-aucune}"
}
V=$r10/vsa-cle-publique.pem C=$here/resultats/chains-cle-publique.pem
cas reelle builds/sample-app "$V"
cas sans-vsa builds/essai-webhook "$V"
cas cle-chains builds/sample-app "$C"
cas hors-builds horodatage/bundles "$V"
cas depot-vsa builds/vsa/sample-app "$V"
# faux cosign : une ligne JSON par énoncé, comme la sortie mesurée de cosign verify-attestation (payload, payloadType, signatures)
E=$r10/r5-vsa-enonce.json
ligne() { printf '{"payloadType":"application/vnd.in-toto+json","payload":"%s","signatures":[{"keyid":"","sig":"x"}]}\n' "$(base64 -w0)"; }
{ sed 's/"PASSED"/"FAILED"/' "$E" | ligne; sed 's/3a7ca1b14dbf/0a7ca1b14dbf/' "$E" | ligne; sed 's/administrateur-unique@v1/autre@v1/' "$E" | ligne; } > "$d/ecartes"
{ cat "$d/ecartes"; ligne < "$E"; } > "$d/mixte"
for f in ecartes mixte; do
  printf '#!/bin/sh\ncat %s\n' "$d/$f" > "$d/faux/cosign" && chmod +x "$d/faux/cosign"
  cas "faux-$f" builds/sample-app "$V" 1
done
echo "énoncé de la brique 10 : $(sha256sum < "$E" | cut -c1-16)"
} 2>&1 | sed -u "s#$HOME#~#g" | tee "$here/resultats/controle6-plomberie.log"
rm -rf -- "${d:?}"
