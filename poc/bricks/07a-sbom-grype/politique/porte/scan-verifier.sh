#!/bin/sh
# Brique 07a, G5 : première moitié du contrôle 7 (attestation de scan, ADR 0000 §4) dans la porte de release. Conteneur
# d'initialisation scan-verifier du Job de la porte, après ec ; image d'outils de J5 (cosign v3.1.4, busybox), épinglée par digest.
# Le scan est un referrer de l'image dans un dépôt séparé (scanner.sh, publier) : builds/<nom> -> builds/scan/<nom>, dérivé ici du
# nom de $IMAGE, pas fourni par l'appelant. Une image hors de builds/, ou sous builds/scan/ ou builds/vsa/, n'a aucun scan recevable.
# cosign lit le dépôt par COSIGN_REPOSITORY (commande de vsa.sh, mesurée sur le scan réel le 04/11/2026) et vérifie avec la clé
# publique du scanner (ConfigMap, scanner.pub, prise hors bande dans poc/bricks/07a-sbom-grype/resultats/scanner-cle-publique.pem).
# Ce script ne juge rien : il écrit les énoncés vérifiés dans /partage/scan-entree.json, {"digest":…,"statements":[…]}, et le
# conteneur scan (ec validate input, politique/porte/scan.rego) retient le plus récent et rend la décision. Toujours le code 0 : un
# conteneur d'initialisation en échec empêcherait horodatage et vsa de démarrer, et l'entrée sans énoncé est refusée par la règle
# scan.scan_present. Rien d'écrit ou JSON invalide : ec échoue, le Job aussi (échec fermé).
# Sortie : une ligne par énoncé vérifié (LU, empreinte de l'énoncé, scannedAt), puis LECTURE|nombre d'énoncés vérifiés|dépôt|détail.
ENTREE=${ENTREE:-/partage/scan-entree.json}
T=https://supply-chain.example/scan/v1
cd "$(mktemp -d)" || exit 0
r=${IMAGE%@sha256:*} d=${IMAGE##*@sha256:} n=${r#*/}
depot=
[ "$r" != "$IMAGE" ] && [ ${#d} = 64 ] || d=
case $n in
  builds/scan/*|builds/vsa/*) ;;
  builds/*) depot=${r%%/*}/builds/scan/${n#builds/} ;;
esac
if [ -z "$d" ] || [ -z "$depot" ]; then
  printf '{"digest":"","statements":[]}' > "$ENTREE"
  echo "LECTURE|0|-|image sans digest sha256, hors de builds/ ou dans un dépôt d'attestations : $IMAGE"
  exit 0
fi
COSIGN_REPOSITORY=$depot cosign verify-attestation --key /etc/porte/scanner.pub --insecure-ignore-tlog --type "$T" \
  --registry-cacert /etc/porte/ca-poc.crt "$IMAGE" > verifiees 2> erreur
# Une ligne JSON par attestation vérifiée ; énoncé dans payload (base64).
grep '^{' verifiees > lignes
v=0
{
  printf '{"digest":"%s","statements":[' "$d"
  while IFS= read -r l; do
    printf '%s' "$l" | sed -n 's/.*"payload":"\([^"]*\)".*/\1/p' | base64 -d > enonce 2> /dev/null
    [ -s enonce ] || continue
    [ "$v" = 0 ] || printf ','
    cat enonce
    v=$((v + 1))
    echo "LU|énoncé $(sha256sum < enonce | cut -c1-16)|$(sed -n 's/.*"scannedAt": *"\([^"]*\)".*/\1/p' enonce | head -1)" >&2
  done < lignes
  printf ']}'
} > "$ENTREE" 2> lus
cat lus
c=$(sed -n 's/^Error: //p' erreur | head -1 | cut -c1-200 | tr '|' ' ')
[ -n "$c" ] || c=$(grep -v -e '^WARNING' -e '^$' -e '^Verification for' -e '^The following' -e '^  - ' erreur | head -1 | cut -c1-200 | tr '|' ' ')
echo "LECTURE|$v|$depot|${c:+cosign : $c}"
exit 0
