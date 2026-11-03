#!/bin/sh
# Brique 08 : contrôle 6 (VSA de replay, ADR 0000 §4) dans la porte de release, demandé par la brique 10 (choix du
# propriétaire du 03/11/2026 : « Contrôle 6 d'abord »). Conteneur vsa du Job de la porte (politique/porte-job.yaml), à côté du
# conteneur horodatage ; image d'outils de J5 (cosign v3.1.4, busybox), épinglée par digest.
# La VSA est un referrer de l'image dans un dépôt séparé (brique 10, R5 : un bundle dans le dépôt de l'image fait ignorer .sig
# et .att par ec et cosign) : builds/<nom> -> builds/vsa/<nom>, dérivé ici du nom de $IMAGE, pas fourni par l'appelant. Une image
# hors de builds/, ou déjà sous builds/vsa/, est refusée. cosign lit le dépôt par COSIGN_REPOSITORY (commande mesurée en R5,
# lire_vsa : seule connexion, Zot) et vérifie avec la clé publique du domaine de replay (ConfigMap, vsa.pub, prise hors bande
# dans poc/bricks/10-independent-replay/resultats/vsa-cle-publique.pem). Un énoncé vérifié n'est retenu que s'il porte le digest
# jugé en sujet, le verifier.id attendu et verificationResult PASSED ; il en faut au moins un. Rien de vérifié : refus.
# Sortie : une ligne par énoncé vérifié (RETENU ou ECARTE, empreinte de l'énoncé, motifs), puis VSA|ok|… ou VSA|refus|… ;
# code de sortie 0 ou 1 (succès ou échec du Job).
set -eu
cd "$(mktemp -d)"
ID=https://supply-chain.example/verifiers/replay-poc-administrateur-unique@v1
T=https://slsa.dev/verification_summary/v1
r=${IMAGE%@sha256:*} d=${IMAGE##*@sha256:}
[ "$r" != "$IMAGE" ] && [ ${#d} = 64 ] || { echo "VSA|refus|image sans digest sha256 : $IMAGE"; exit 1; }
n=${r#*/}
case $n in
  builds/vsa/*) echo "VSA|refus|image dans un dépôt de VSA : $n"; exit 1 ;;
  builds/*) VSA=${r%%/*}/builds/vsa/${n#builds/} ;;
  *) echo "VSA|refus|image hors de builds/ : $n"; exit 1 ;;
esac
COSIGN_REPOSITORY=$VSA cosign verify-attestation --key /etc/porte/vsa.pub --insecure-ignore-tlog --type "$T" \
  --registry-cacert /etc/porte/ca-poc.crt "$IMAGE" > verifiees 2> erreur || true
v=0 k=0
# Une ligne JSON par attestation vérifiée ; énoncé dans payload (base64). Espaces autour des « : » retirées avant les
# comparaisons (l'énoncé de la brique 10 est indenté).
grep '^{' verifiees > lignes || true
while IFS= read -r l; do
  v=$((v + 1))
  printf '%s' "$l" | sed -n 's/.*"payload":"\([^"]*\)".*/\1/p' | base64 -d > enonce 2> /dev/null || : > enonce
  sed 's/" *: *"/":"/g' enonce > plat
  m=
  grep -q -F "\"predicateType\":\"$T\"" plat || m="$m predicateType"
  grep -q -F "\"sha256\":\"$d\"" plat || m="$m sujet"
  grep -q -F "\"id\":\"$ID\"" plat || m="$m verifier.id"
  grep -q -F '"verificationResult":"PASSED"' plat || m="$m verificationResult"
  e=$(sha256sum < enonce | cut -c1-16)
  if [ -z "$m" ]; then echo "RETENU|énoncé $e"; k=$((k + 1)); else echo "ECARTE|énoncé $e|$m"; fi
done < lignes
c=$(sed -n 's/^Error: //p' erreur | head -1 | cut -c1-200)
[ -n "$c" ] || c=$(grep -v -e '^WARNING' -e '^$' erreur | head -1 | cut -c1-200)   # cosign absent ou arrêté sans « Error: »
[ "$k" -gt 0 ] && { echo "VSA|ok|$k/$v VSA retenue(s) dans $VSA"; exit 0; }
echo "VSA|refus|$k/$v VSA retenue(s) dans $VSA${c:+ ; cosign : $c}"
exit 1
