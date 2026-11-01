#!/bin/sh
# Brique 08, J8 (test 8) : contrôle 9 (horodatage RFC 3161) dans la porte de release, conteneur horodatage du Job de la
# porte (politique/porte-job.yaml), après ec. Image d'outils de J5 (cosign v3.1.4, busybox), épinglée par digest.
# Le jeton est lié aux enveloppes que ec a jugées : chaque signature d'attestation vérifiée par ec (sortie JSON de ec,
# /partage/ec.json) doit se retrouver dans un bundle du dépôt $BUNDLES vérifié par cosign (clé de la ConfigMap, sujet =
# digest de $IMAGE, prédicat slsaprovenance1, jeton exigé, racine de confiance du TSA). Un bundle valide pour le même
# digest mais d'une autre enveloppe (autre image de même digest, provenance plus ancienne) ne compte pas.
# cosign liste lui-même les referrers de $BUNDLES (COSIGN_REPOSITORY) : un bundle invalide ajouté au dépôt est écarté
# sans masquer les bundles valides (mesuré au test 8 pour des bundles bien formés). Aucune attestation vérifiée par ec, ou
# extraction incomplète : refus.
# Sortie : une ligne par enveloppe (COUVERTE ou NON_COUVERTE, empreinte de la signature), puis
# HORODATAGE|ok|… ou HORODATAGE|refus|… ; code de sortie 0 ou 1 (succès ou échec du Job).
set -eu
cd "$(mktemp -d)"
EC=/partage/ec.json
[ -s "$EC" ] || { echo "HORODATAGE|refus|verdict de ec absent"; exit 1; }
# Signatures des attestations seulement (celles de l'image suivent "success" et ont un keyid vide) ; une par enveloppe
# (Chains en dsse : une signature).
grep -o -E '"predicateType":"[^"]*",("predicateBuildType":"[^"]*",)?"signatures":\[\{"keyid":"[^"]*","sig":"[^"]*"' "$EC" \
  | sed -e 's/.*"sig":"//' -e 's/"$//' > sigs-ec || true
n=$(grep -c . sigs-ec || true)
[ "$n" -gt 0 ] || { echo "HORODATAGE|refus|aucune attestation vérifiée par ec"; exit 1; }
# Échec fermé : une attestation que l'extraction ne reconnaît pas (autre forme, plusieurs signatures) ne doit pas échapper au
# contrôle ; chaque attestation de la sortie de ec porte un champ predicateType (vérifié sur les verdicts archivés de J8).
a=$(grep -o '"predicateType":' "$EC" | wc -l)
[ "$a" = "$n" ] || { echo "HORODATAGE|refus|$a attestation(s) dans le verdict de ec, $n signature(s) extraite(s)"; exit 1; }
COSIGN_REPOSITORY=$BUNDLES cosign verify-attestation --key /etc/porte/chains.pub --insecure-ignore-tlog --use-signed-timestamps \
  --trusted-root /etc/porte/tsa-racine-confiance.json --type slsaprovenance1 --registry-cacert /etc/porte/ca-poc.crt \
  "$IMAGE" > verifiees 2> erreur || true
v=$(grep -c . verifiees || true)
m=0
while IFS= read -r s; do
  e=$(printf '%s' "$s" | base64 -d | sha256sum | cut -c1-16)
  if grep -q -F "\"sig\":\"$s\"" verifiees; then echo "COUVERTE|signature $e"
  else echo "NON_COUVERTE|signature $e"; m=$((m + 1)); fi
done < sigs-ec
c=$(sed -n 's/^Error: //p' erreur | head -1 | cut -c1-200)
[ "$m" = 0 ] && { echo "HORODATAGE|ok|$n/$n enveloppe(s) couverte(s), $v bundle(s) vérifié(s) dans $BUNDLES"; exit 0; }
echo "HORODATAGE|refus|$((n - m))/$n enveloppe(s) couverte(s), $v bundle(s) vérifié(s) dans $BUNDLES${c:+ ; cosign : $c}"
exit 1
